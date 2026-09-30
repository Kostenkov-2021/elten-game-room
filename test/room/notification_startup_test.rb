require_relative "../support/ui"
require_relative "../support/localization"

class Program
  def self.server_app(**_options); end
  def self.read_json(*)
    raise "A notification callback reopened settings after startup"
  end
end

module Programs
  class << self
    attr_accessor :fixture
    def current_runtime; fixture; end
  end
end

runtime = GameRoomTestLocalization.runtime("pl")
runtime.define_singleton_method(:read_json) do |path, default:|
  raise "Unexpected file" unless path == "settings.json"
  @settings_reads = @settings_reads.to_i + 1
  super(path, default: default)
end
runtime.settings.merge!("widget_enabled" => false, "invitation_notifications" => "nobody",
  "sound_volumes" => {"all" => 70, "notifications" => 50})
Programs.fixture = runtime
require_relative "../../__app"

def assert(value, message)
  raise message unless value
end

assert(runtime.instance_variable_get(:@settings_reads) == 1, "startup added another settings read beside localization")
100.times do
  settings = EltenGameRoom.normalized_settings
  assert(settings["widget_enabled"] == false && settings["invitation_notifications"] == "nobody", "startup lost saved filters")
  assert(settings["sound_volumes"]["notifications"] == 50, "startup lost saved volume")
end
assert(GameRoomLocalization.primary_language == "pl", "sharing startup settings changed the selected language")
runtime.settings["sound_volumes"]["notifications"] = 100
assert(EltenGameRoom.normalized_settings["sound_volumes"]["notifications"] == 50, "published preferences share mutable storage")
assert(EltenGameRoom.normalized_settings.frozen? && EltenGameRoom.normalized_settings["sound_volumes"].frozen?, "published snapshot is mutable")
assert(runtime.instance_variable_get(:@settings_reads) == 1, "callbacks reopened the file")
puts "PASS one startup read shared by localization/notifications, saved filters, volume and detached snapshot"
