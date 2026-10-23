require_relative '../../support/native_background_capacity'
require_relative '../../support/pong_client'
require_relative '../../support/native_room_harness'
require_relative '../../support/native_public_messages'
require_relative '../../support/word_picker'
require_relative '../../../games/scrabble'
require_relative '../../../lib/scrabble_preview'
include GameRoomTest::Assertions

# The public draft is disposable; a full local task queue must not throw out
# of its ordinary UI tick or consume its latest pending sketch as sent.
[0, 128].each do |backlog|
  GameRoomTest::NativeBackgroundCapacity.with(backlog) do |work, free_capacity|
    game = GameRoomGames::Scrabble.new
    harness = NativeRoomHarness.new(game: game, users: %w[Alice Watcher])
    harness.start
    state = game.initial_state(%w[Alice Bob], game.normalize_options('content_language_id' => 'en'))
    state.merge!(phase: :playing, current_player: 'Alice', revision: 1, turn: 1)
    replay = GameRoomGames::Replay.new(players: state[:players], current_player: 'Alice', state: state, history: [])
    now = 0.0
    client = GameRoomScrabblePreview.new(Class.new(Program).new, game,
      transport: harness.transports.fetch('Alice'), work: work, clock: -> { now })
    client.bind_screen(session_id: harness.session['__id'], table_id: harness.table['__id'], owner: 'Alice',
      viewer: 'Alice', members: -> { harness.users })
    client.update_table_control('__control_epoch' => 1)
    client.before_wait(replay, 'Alice')
    client.draft_changed([[112, 'c', false]])
    client.tick
    assert(harness.view('Alice').sent_messages.to_a.empty?, 'A sketch bypassed native task capacity')
    client.draft_changed([[112, 'a', false]])
    now += 0.13
    client.tick
    assert_equal([[112, 'a', false]], client.instance_variable_get(:@pending)['tiles'],
      'Refused admission consumed the newest public sketch')
    free_capacity.call
    GameRoomTest::NativeBackgroundCapacity.until_true do
      now += 0.13
      client.tick
      messages = harness.view('Alice').sent_messages.to_a
      messages.last&.dig('payload', 'tiles') == [[112, 'a', false]] && !work.busy?
    end
    count = harness.view('Alice').sent_messages.size
    5.times { now += 0.13; client.tick }
    assert_equal(count, harness.view('Alice').sent_messages.size, 'An idle sketch was sent again')
    assert(count <= 2, 'Local pressure queued every intermediate sketch')
  ensure
    client&.close
  end
end
puts 'PASS Scrabble public preview: actual native4 and4+128 pressure, nonthrowing UI tick, latest sketch retained, no idle resend'
