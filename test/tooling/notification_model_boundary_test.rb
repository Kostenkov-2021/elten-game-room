require_relative '../support/table_watch_runtime'
require_relative '../support/assertions'
include GameRoomTest::Assertions

path = EltenTestHost.file('src/eapi/program.rb')
original = File.method(:readlines)
source = original.call(path)
helper = File.expand_path('../support/app_notification_models.rb', __dir__)
markers = ['  class NotificationPresentation', '  class Leaderboard',
  *%w[app_notification_from notification_value map_app_notification receive_app_notification].map { |name| "    def #{name}(" }]

markers.each do |marker|
  index = source.index { |line| line.start_with?(marker) }
  assert(index, "Missing source precondition #{marker}")
  changed = source.dup
  changed[index] = "# removed native fixture boundary\n"
  before = Programs.constants(false)
  File.define_singleton_method(:readlines) do |name, *args, **options|
    name == path ? changed.dup : original.call(name, *args, **options)
  end
  begin
    error = assert_raises(RuntimeError) { load helper }
    assert(error.message.include?('notification') && error.message.include?('boundar'),
      "Missing boundary did not produce the explicit fixture diagnosis: #{error.message}")
    assert_equal(before, Programs.constants(false), 'Bad boundaries partially loaded native model classes')
  ensure
    File.define_singleton_method(:readlines, original)
  end
end

first = source.index { |line| line.start_with?(markers[0]) }
last = source.index { |line| line.start_with?(markers[1]) }
changed = source.dup
changed[first], changed[last] = changed[last], changed[first]
File.define_singleton_method(:readlines) do |name, *args, **options|
  name == path ? changed.dup : original.call(name, *args, **options)
end
begin
  assert_raises(RuntimeError) { load helper }
ensure
  File.define_singleton_method(:readlines, original)
end
puts 'PASS native notification fixture boundaries: missing classes/dispatch methods and reversed class range fail explicitly; original reader restored'
