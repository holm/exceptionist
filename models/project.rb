class Project
  attr_accessor :name

  def initialize(name)
    self.name = name
  end

  def exceptions_count
    UberException.count_all(name)
  end

  def last_thirty_days
    last_n_days(30).map { |day| [day, occurrence_count_on(day)] }
  end

  def last_n_days(days)
    today = Time.now
    start = today - (3600 * 24 * (days - 1)) # `days` days ago

    n_days = []
    begin
      n_days << start
    end while (start += 86400) <= today

    n_days
  end

  def occurrence_count_on(date)
    Exceptionist.redis.list_length("Exceptionist::Project:#{name}:OnDay:#{date.strftime('%Y-%m-%d')}")
  end

  def last_three_exceptions
    latest_exceptions(0, 3)
  end

  def latest_exceptions(filter, start, limit = 25)
    UberException.find_all_sorted_by_time(name, filter, start, limit)
  end

  def most_frequest_exceptions(filter, start, limit = 25)
    UberException.find_all_sorted_by_occurrence_count(name, filter, start, limit)
  end

  def ==(other)
    name == other.name
  end

  def self.all
    Exceptionist.redis.set_members('Exceptionist::Projects').map { |name| Project.new(name) }
  end
end
