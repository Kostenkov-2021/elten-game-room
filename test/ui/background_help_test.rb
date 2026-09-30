require_relative "../support/ui"
require_relative "../support/log"
class Program
  def self.server_app(**_options); end
end
require_relative "../../__app"

def assert(value, message); raise message unless value; end
class Form
  def update
    $activecontrols ||= []
    $activecontrols << self
    fields[index.to_i]&.update
    @timers.to_a.dup.each(&:update)
  end
  def focus(*_args); fields[index.to_i]&.focus; end
end
class FormTimer
  def initialize(*_args, **_options, &block); @block = block; end
  def update; @block.call; end
end

game = ListBox.new(['Card one', 'Card two'], header: 'Hand', index: 1)
chat = EditBox.new('Chat', text: 'Preserved draft')
chat.index, chat.check = 4, 8
form = GameSurfaces::RefreshAwareForm.new([game, chat], quiet: true)
form.game_room_background_help_enabled = true
ticks, gameplay_updates = 0, 0
game.define_singleton_method(:update) { gameplay_updates += 1 }
timer = FormTimer.new { ticks += 1; form.resume_for_refresh if ticks == 3 }
form.add_timer(timer)
form.show_game_room_help
dialog = form.game_room_background_help_form
assert(dialog && dialog.fields.first.is_a?(GameRoomUI::HelpText), 'F1 still waits in a blocking dialog')
dialog.fields.first.index = 12
5.times { form.update }
assert(ticks == 5 && gameplay_updates.zero?, 'Help stopped timers or sent its keys to the hand')
assert(form.game_room_background_help_form.equal?(dialog) && dialog.fields.first.index == 12,
  'Maintenance closed/recreated help or moved its reading cursor')
form.delete_timer(timer)
form.update
assert(ticks == 5, 'Removed timer still runs behind help')
dialog.accept_button.trigger(:press)
assert(!form.game_room_background_help? && game.index == 1, 'Enter did not return to the same hand card')
assert([chat.text, chat.index, chat.check] == ['Preserved draft', 4, 8], 'Help changed the chat draft')
assert(!dialog.game_room_hotkeys_active?, 'Closed help retained the host hotkey override')
form.update
assert(gameplay_updates == 1, 'Game input did not resume after help')

ball = GameRoomGames::AudioBall.new
program = Object.new
sounds = []
program.define_singleton_method(:play_sound_from_asset) do |*_args, **_options|
  sound = Object.new
  sound.define_singleton_method(:close) { @closed = true }
  sounds << sound
  sound
end
rules = GameRoomScreens::GameRules.new(ball.rule_book(options: ball.default_options),
  program: program, audio_tutorial: ball.audio_tutorial_entries)
rules.open_on(form)
picker = form.game_room_background_help_form
picker.fields.first.index = picker.fields.first.options.length - 1
picker.accept_button.trigger(:press)
tutorial = form.game_room_background_help_form
assert(tutorial != picker && tutorial.fields.length == 1, 'Tutorial did not open above the rules picker')
tutorial.fields.first.trigger(:select)
assert(sounds.length == 1, 'Tutorial did not play the selected sound')
tutorial.show_game_room_help
nested = form.game_room_background_help_form
assert(nested != tutorial, 'Tutorial F1 blocked instead of opening background help')
nested.cancel_button.trigger(:press)
assert(form.game_room_background_help_form.equal?(tutorial), 'Nested F1 lost the tutorial')
tutorial.trigger(:key_escape)
assert(sounds.first.instance_variable_get(:@closed), 'Escape leaked the preview sound')
assert(form.game_room_background_help_form.equal?(picker), 'Tutorial Escape did not return to its menu')
assert(picker.fields.first.index == picker.fields.first.options.length - 1, 'Returning moved the selected document')
picker.accept_button.trigger(:press)
form.game_room_background_help_form.fields.first.trigger(:select)
form.clear_game_room_background_help
assert(sounds.all? { |sound| sound.instance_variable_get(:@closed) }, 'Closing the game leaked tutorial sounds')
assert(!form.game_room_background_help?, 'Closing the game left help open')
puts 'PASS background help: timers, refresh, input isolation, retained caret/draft, nested rules/tutorial, cleanup'
