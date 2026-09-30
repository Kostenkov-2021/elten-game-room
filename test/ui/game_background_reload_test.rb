require 'weakref'

module EltenAPI
  module UI
    def loop_update; :host; end
  end
end

def attach_reloaded_presenter(source, path)
  space = Module.new
  helper = File.expand_path("../../lib/host_bridge.rb", __dir__)
  space.module_eval(File.binread(helper), helper)
  space.module_eval(source, path)
  program, runner = Object.new, Object.new
  runner.define_singleton_method(:covered?) { false }
  refs = [space, program, runner].map { |item| WeakRef.new(item) }
  registration = space.const_get(:GameRoomBackgroundPresentation).attach(Object.new,
    program: program, runner: runner, key: [:reload])
  registration.close
  refs
end

path = File.expand_path("../../lib/game_background_presentation.rb", __dir__)
source = File.binread(path)
refs = 20.times.map { attach_reloaded_presenter(source, path) }
3.times { GC.start }
raise 'Host bridge retained an unloaded app/runner' if refs.any? { |row| row.any?(&:weakref_alive?) }
raise 'Reload retained active registrations' unless EltenAPI::UI.instance_variable_get(:@game_room_presenters).empty?
bridge = EltenAPI::UI.instance_variable_get(:@game_room_presentation_bridge)
raise 'Reload stacked bridges' unless EltenAPI::UI.ancestors.count { |entry| entry.equal?(bridge) } == 1
puts 'PASS background bridge: 20 binary reloads, no retained namespace/program/runner, one host bridge'
