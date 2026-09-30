require_relative "../support/ui"
require_relative "../../lib/game_simulation"
require_relative "../../games/makao"
require_relative "../../games/checkers"
require_relative "../../lib/participant_menu"
require_relative "../../lib/game_room_ui"

game = GameRoomGames::Makao.new
options = game.normalize_options({ "profile" => "polish", "cards_per_player" => 7, "bot_delay" => 4 })
before = Marshal.dump(options)
message = game.table_options_announcement(options)
raise "not the same settings source" unless message == ([game.name] + game.rules_options_text(options).split(/\r?\n/).reject(&:empty?)).join('. ')
raise "options mutated" unless Marshal.dump(options) == before
game.effective_option_definitions.select { |item| item.kind == :boolean }.each do |item|
  raise "disabled setting announced" if options[item.key.to_s] == false && message.include?(item.label)
end

layout = Struct.new(:form, :users, :back_button).new(GameRoomUI::Form.new([ListBox.new(["A"], header: "Users")]), ListBox.new(["A"], header: "Users"), nil)
GameRoomContextHelp.replace([layout.users], [])
dispatches = []
reads = 0
GameRoomParticipantMenu.bind(layout, available: -> { [:leave] }, read_options: -> { reads += 1 }) { |*args| dispatches << args }
menu = Object.new
menu.define_singleton_method(:option) { |label, _unused, key, &block| block.call if key == "r" }
layout.form.context(menu)
raise "reader dispatched/resumed game" unless reads == 1 && dispatches.empty?
puts "Table options announcement: OK"
