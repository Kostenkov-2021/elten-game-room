require_relative "../../support/background_help_game_screen"
require_relative "../../../games/scientific_war"

module ScientificWarTurnSoundTest
  module_function

  def check(enabled:, covered:, viewer:)
    game = GameRoomGames::ScientificWar.new
    room, screen = screen_fixture(game)
    $game_room_test_user = viewer # The shared fixture initializes the room as Alice.
    contexts = room.users.to_h do |user|
      [user, GameRoomGames::ActionContext.new(session_id: room.session['__id'],
        hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new))]
    end
    sounds = []
    program = screen.instance_variable_get(:@program)
    program.define_singleton_method(:play_sound_from_asset) { |name, **_options| sounds << name; nil }
    screen.instance_variable_set(:@runner_covered, -> { covered })
    screen.define_singleton_method(:speak) { |_message, **_options| }
    present = lambda do |stage, decision|
      replay = room.replay('Alice')
      sounds.clear
      screen.send(:process_new_events, replay)
      expected = enabled && covered && decision ? 1 : 0
      assert(sounds.count('ding') == expected,
        "#{stage}: #{viewer}, enabled=#{enabled}, covered=#{covered}: expected #{expected} ding, got #{sounds.inspect}")
      heard = sounds.dup
      screen.send(:process_new_events, replay)
      assert(sounds == heard, "#{stage}: refresh repeated a sound")
      replay
    end
    submit = lambda do |actor, action, card = nil|
      selection = {'kind' => card ? 'card' : 'command', 'action' => action}
      selection.merge!('zone' => 'hand', 'card' => card) if card
      room.submit(actor, selection, context: contexts.fetch(actor))
    end
    initial = present.call('initial choice', %w[Alice Bob].include?(viewer))
    bob_key = game.required_decision_key(initial, 'Bob')
    assert(bob_key && game.required_decision_key(initial, 'Observer').nil?, 'initial decision ownership is wrong')
    submit.call('Alice', 'select', 'QH1')
    after = present.call('another player committed', false)
    assert(game.required_decision_key(after, 'Bob') == bob_key, 'another choice changed the pending decision')
    assert(game.required_decision_key(after, 'Alice').nil?, 'a sealed choice still requests a decision')
    submit.call('Bob', 'select', '5S1')
    revealing = present.call('automatic reveals begin', false)
    assert(room.users.all? { |user| game.required_decision_key(revealing, user).nil? }, 'automatic reveals ring as decisions')
    submit.call('Alice', 'reveal')
    present.call('first automatic reveal', false)
    submit.call('Bob', 'reveal')
    second = present.call('next trick, spy waits', viewer == 'Bob')
    assert(game.required_decision_key(second, 'Alice').nil?, 'the spy was called before the others chose')
    assert(game.required_decision_key(second, 'Bob') != bob_key, 'next trick reused the previous decision key')
    submit.call('Bob', 'select', 'KS1')
    present.call('spy opponent committed', false)
    submit.call('Bob', 'reveal')
    spying = present.call('spy chooses', viewer == 'Alice')
    assert(game.required_decision_key(spying, 'Alice') && game.required_decision_key(spying, 'Bob').nil?, 'spy decision ownership is wrong')
    submit.call('Alice', 'select', 'AH1')
    present.call('ordinary next trick', %w[Alice Bob].include?(viewer))
    submit.call('Alice', 'select', '8H1')
    present.call('eight committed', false)
    submit.call('Bob', 'select', '2S1')
    present.call('eight trick committed', false)
    submit.call('Alice', 'reveal')
    present.call('eight first reveal', false)
    submit.call('Bob', 'reveal')
    before_swap = present.call('swap power next trick', %w[Alice Bob].include?(viewer))
    key = game.required_decision_key(before_swap, 'Alice')
    submit.call('Alice', 'swap')
    after_swap = present.call('same decision after swapping', false)
    assert(game.required_decision_key(after_swap, 'Alice') == key, 'swapping created a second decision')
    assert(game.legal_actions(after_swap, 'Alice').any?, 'the swap fixture lost the available choice')
    eliminated = Marshal.load(Marshal.dump(after_swap))
    eliminated.state[:eliminated]['Alice'] = true
    assert(game.required_decision_key(eliminated, 'Alice').nil?, 'an eliminated viewer has a decision')
    finished = Marshal.load(Marshal.dump(after_swap))
    finished.winner = 'Alice'
    assert(game.required_decision_key(finished, 'Alice').nil?, 'a finished game has a decision')
  ensure
    screen&.send(:stop_session_runner)
  end
end

$activecontrols = []
settings = {'background_table_speech' => false, 'background_turn_sound' => false}
ProgramDouble.define_singleton_method(:normalized_settings) { settings }
checks = 0
begin
  [false, true].product([false, true], %w[Alice Bob Observer]).each do |enabled, covered, viewer|
    settings['background_turn_sound'] = enabled
    ScientificWarTurnSoundTest.check(enabled: enabled, covered: covered, viewer: viewer)
    checks += 1
  end
ensure
  ProgramDouble.singleton_class.remove_method(:normalized_settings)
end
puts "PASS Scientific War decision sounds: #{checks} viewer/settings/background combinations, normal choices, spy, reveals, swap and refresh"
