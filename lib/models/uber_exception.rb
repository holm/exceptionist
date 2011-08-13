class UberException
  attr_accessor :id

  def initialize(attributes={})
    @id = attributes['_id']
  end

  def self.count_all(project)
    redis.zcard("Exceptionist::Project:#{project}:UberExceptions")
  end

  def self.find_all(project)
    uber_exceptions = redis.zrange("Exceptionist::Project:#{project}:UberExceptions", 0, -1) || []
    uber_exceptions.map { |id| new(id) }
  end

  def self.find_all_sorted_by_time(project, start, limit)
    set_key = "Exceptionist::Project:#{project}:UberExceptions"

    uber_exceptions = redis.zrevrange(set_key, start, start + limit - 1) || []
    uber_exceptions.map { |id| new(id) }
  rescue RuntimeError
    []
  end

  def self.find_all_sorted_by_occurrence_count(project, start, limit)
    set_key = "Exceptionist::Project:#{project}:UberExceptions"

    sort_key = "Exceptionist::UberException:*:OccurrenceCount"

    redis.sort(set_key, :by => sort_key, :order => 'DESC', :limit => [start, limit]).map { |id| new(id) }
  rescue RuntimeError
    []
  end

  def self.find_new_on(project, day)
    all = redis.sort("Exceptionist::Project:#{project}:UberExceptions",
            :by => "Exceptionist::UberException:*:OccurrenceCount",
            :order => 'DESC').map { |id| new(id) }

    next_day = day + 86400
    all.select { |uber_exp| uber_exp.first_occurred_at >= day && uber_exp.first_occurred_at < next_day }
  end

  def self.occurred(occurrence)
    # TODO: first and last occurrence, occurrence count?
    uber_exception = {
      :_id => occurrence.uber_key,
      :project_name => occurrence.project_name,
      :occurred_at => occurrence.occurred_at
    }
    Exceptionist.mongo['exceptions'].update({:_id => occurrence.uber_key}, uber_exception, :upsert => true, :safe => true)

    # # store a sorted set of exceptions per project
    # redis.zadd("Exceptionist::Project:#{occurrence.project_name}:UberExceptions", occurrence.occurred_at.to_i, occurrence.uber_key)

    # # store a list of occurrences per project per day
    # redis.rpush("Exceptionist::Project:#{occurrence.project_name}:OnDay:#{occurrence.occurred_at.strftime('%Y-%m-%d')}", occurrence.id)

    # # store a top level set of projects
    # redis.sadd("Exceptionist::Projects", occurrence.project_name)

    # return the UberException
    new(occurrence.uber_key)
  end

  def self.forget_old_exceptions(project, days)
    since_date = Time.now - (84600 * days)
    deleted = 0

    uber_exceptions = redis.zrange("Exceptionist::Project:#{project}:UberExceptions", 0, -1, :with_scores => true) || []
    while uber_exceptions.any?
      id, score = uber_exceptions.pop(2)
      exception_date = Time.at(score.to_i)

      if exception_date < since_date
        UberException.new(id).forget
        redis.zrem("Exceptionist::Project:#{project}:UberExceptions", id)
        redis.del("Exceptionist::Project:#{project}:OnDay:#{exception_date.strftime('%Y-%m-%d')}")
        deleted += 1
      end
    end

    deleted
  end

  def forget
    occurrence_keys = occurrences_list(0, -1).map { |id| Occurrence.key(id) }

    # delete all occurrences
    occurrence_keys.each { |key| redis.del(key) }

    # delete all the stuff from #occurred
    redis.del("Exceptionist::UberException:#{id}:Occurrences")
    redis.del("Exceptionist::UberException:#{id}:OccurrenceCount")
  end

  def last_occurrence
    @last_occurrence ||= Occurrence.find(occurrences_list(-1, -1))
  end

  def first_occurrence
    @first_occurrence ||= Occurrence.find(occurrences_list(0, 0))
  end

  def occurrences
    Occurrence.find_all(occurrences_list(0, -1))
  end

  def current_occurrence(position)
    Occurrence.find(redis.zrange(key(id, 'Occurrences'), position - 1, position - 1))
  end

  def first_occurred_at
    first_occurrence.occurred_at
  end

  def last_occurred_at
    last_occurrence.occurred_at
  end

  def title
    last_occurrence.title
  end

  def url
    last_occurrence.url
  end

  def occurrences_count()
    count_key = "Exceptionist::UberException:#{id}:OccurrenceCount"

    @occurrences_count ||= redis.get(count_key).to_i
  end

  def last_thirty_days
    thirty_days_ago = Time.now - (60 * 60 * 24 * 30)
    groups = occurrences.select { |o| o.occurred_at >= thirty_days_ago }.group_by { |o| Time.mktime(o.occurred_at.year, o.occurred_at.month, o.occurred_at.day) }
    groups = groups.map { |group| [group[0], group[1].size] }
    groups.sort_by { |g| g.first }
  end

  def ==(other)
    id == other.id
  end

  def inspect
    "(UberException: id: #{id})"
  end

private

  def self.redis
    Exceptionist.redis
  end

  def redis
    Exceptionist.redis
  end

  def self.key(*parts)
    "#{Exceptionist.namespace}::#{name}:#{parts.join(':')}"
  end

  def key(*parts)
    self.class.key(*parts)
  end

  def occurrences_list(start_position, end_position)
    redis.zrange(key(id, 'Occurrences'), start_position, end_position) || []
  end
end
