require_relative "../support/audio_tutorial"

def visit_tutorial(game, program)
  stage = 0
  Form.tutorial_driver = lambda do |form|
    visible = form.fields - form.hidden_controls
    assert(visible.length == 1 && visible.first.is_a?(ListBox), 'Help or tutorial gained extra fields')
    list = visible.first
    case stage
    when 0
      assert(list.options == ['Rules', 'In-game keyboard shortcuts', 'Current table options', 'Audio tutorial'],
        'The in-room rules menu does not end with Audio tutorial')
      stage += 1
      list.index = 3
      form.accept_button.trigger(:press)
    when 1
      assert(list.options == game.audio_tutorial_entries.map(&:label), 'The rules menu opened another game tutorial')
      stage += 1
      list.trigger(:select)
      assert(program.plays.last[0] == game.audio_tutorial_entries.first.asset, 'The tutorial did not use the supplied program')
      form.trigger(:key_escape)
    when 2
      assert(list.index == 3, 'Returning from the tutorial lost the menu position')
      assert(program.plays.last[2].closed, 'Returning to rules left the tutorial sound playing')
      stage += 1
      form.cancel_button.trigger(:press)
    else
      raise 'The tutorial reopened after Escape'
    end
  end
  yield
  assert(stage == 3, 'The full rules/tutorial/return path was not exercised')
end

game = GameRoomGames::AudioBall.new
app = EltenGameRoom.allocate
app.define_singleton_method(:read_json) { |_path, default:| default }
played = []
app.define_singleton_method(:play_sound_from_asset) do |name, **options|
  sound = TutorialSound.new
  played << [name, options, sound]
  sound
end
app.define_singleton_method(:plays) { played }
app.define_singleton_method(:game_room_sound_enabled?) { |_name| true }
app.define_singleton_method(:game_room_sound_volume) { |_name| 0.5 }
visit_tutorial(game, app) { app.send(:show_game_rules, game, options: game.default_options) }

program = TutorialProgram.new
screen = GameScreen.allocate
screen.instance_variable_set(:@game, game)
screen.instance_variable_set(:@program, program)
screen.instance_variable_set(:@session, {'options' => JSON.generate(game.default_options)})
replay = GameRoomGames::Replay.new(players: %w[Alice Bob], state: {}, history: [])
before = Marshal.dump(replay)
visit_tutorial(game, program) { screen.send(:show_game_rules, replay) }
assert(Marshal.dump(replay) == before, 'Listening to the tutorial changed the game state')

class AnotherTutorialGame < GameRoomGames::Makao
  def audio_tutorial_entries
    [GameRoomAudioTutorial::Entry.new(label: 'Draw a card', asset: 'draw')]
  end
end
other = AnotherTutorialGame.new
visit_tutorial(other, app) { app.send(:show_game_rules, other, options: other.default_options) }

Form.tutorial_driver = lambda do |form|
  list = (form.fields - form.hidden_controls).first
  assert(list.options == ['Rules', 'In-game keyboard shortcuts', 'Current table options'],
    'A game without sounds gained an empty audio tutorial')
  form.cancel_button.trigger(:press)
end
app.send(:show_game_rules, GameRoomGames::Makao.new, options: {})
puts 'PASS audio tutorial integration: waiting room, active game, return position, unchanged game state and future game opt-in'
