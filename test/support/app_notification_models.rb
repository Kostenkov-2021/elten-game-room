require_relative 'host_source'
path = EltenTestHost.file('src/eapi/program.rb')
lines = File.readlines(path)
first = lines.index { |line| line.start_with?('  class NotificationPresentation') }
last = lines.index { |line| line.start_with?('  class Leaderboard') }
raise "Native notification model boundaries missing in #{path}" unless first && last && first < last

# Validate every extraction boundary before evaluating any native fragment.
# A host change must fail here, not leave a partly loaded fixture or nil+1.
fragments = [["module Programs\n#{lines[first...last].join}\nend", first]]
%w[app_notification_from notification_value map_app_notification receive_app_notification].each do |name|
  first = lines.index { |line| line.start_with?("    def #{name}(") }
  raise "Native notification dispatch boundary missing for #{name} in #{path}" unless first

  last = ((first + 1)...lines.size).find { |index| lines[index].start_with?('    def ') }
  raise "Native notification dispatch end boundary missing for #{name} in #{path}" unless last

  fragments << ["module Programs\nclass << self\n#{lines[first...last].join}\nend\nend", first - 1]
end
fragments.each { |source, line| Object.class_eval(source, path, line) }
