require_relative 'host_source'
# Actual host Form/EditBox/KeyboardState, with deterministic input peripherals.
require_relative 'background_help_native'
require_relative 'native_scene_dispatch'
require_relative '../../lib/live_session_store'
host = EltenTestHost.root
require File.join(host, 'src/eapi/live_sessions')

module EltenWindow
  class << self; attr_accessor :test_character; end
  def self.take_character(_multi)
    result = test_character.to_s
    self.test_character = ''
    result
  end
end

class ParallelNativeDriver < BackgroundHelpNativeDriver
  include NativeSceneDispatch
  attr_accessor :characters, :endpoint, :delivered
  def tick(form)
    active = form.equal?(root) && form.instance_variable_get(:@wait)
    super
    return unless active

    char = characters.shift
    EltenWindow.test_character = char.to_s
    endpoint.enqueue_callback(-> { delivered << char }) if char
    native_scene_frame
  end
end
