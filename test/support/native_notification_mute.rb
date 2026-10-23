require_relative 'host_source'

# Load the host's actual four-mode definition, not an obsolete application
# global or a Boolean stub that would hide a changed host mute contract.
path = EltenTestHost.file('src/ui/input.rb')
lines = File.readlines(path)
first = lines.index { |line| line.include?('def self.do_not_disturb_mode') }
last = lines.index { |line| line.include?('@@altdowntime') }
raise "Native notification mute boundary missing in #{path}" unless first && last && first < last
Object.class_eval("module EltenAPI; module UI\n#{lines[first...last].join}\nend; end", path, first + 1)

module GameRoomTest
  module NativeNotificationMute
    def self.with_mode(mode)
      present = EltenAPI::UI.instance_variable_defined?(:@do_not_disturb_mode)
      previous = EltenAPI::UI.instance_variable_get(:@do_not_disturb_mode)
      EltenAPI::UI.instance_variable_set(:@do_not_disturb_mode, mode)
      yield
    ensure
      if present
        EltenAPI::UI.instance_variable_set(:@do_not_disturb_mode, previous)
      else
        EltenAPI::UI.remove_instance_variable(:@do_not_disturb_mode)
      end
    end
  end
end
