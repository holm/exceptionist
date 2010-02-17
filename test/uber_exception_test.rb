require File.dirname(__FILE__) + '/test_helper'

context 'Finding UberExceptions' do
  setup do
    Exceptionist.redis.flush_all
  end

  test 'should find all occurrences since' do
    project = Project.new('ExampleProject')

    old_ocr       = create_occurrence(:occurred_at => Time.now - (84600 * 4))
    yesterday_ocr = create_occurrence(:action_name => 'index', :occurred_at => Time.now - (84600 * 1))
    today_ocr     = create_occurrence(:action_name => 'create', :occurred_at => Time.now)

    UberException.occurred(old_ocr)
    UberException.occurred(yesterday_ocr)
    UberException.occurred(today_ocr)

    exceptions = UberException.find_new_since(project.name, Time.now - (84600 * 2))
    assert_equal 2, exceptions.size
    assert_equal [yesterday_ocr.uber_exception, today_ocr.uber_exception], exceptions
  end
end
