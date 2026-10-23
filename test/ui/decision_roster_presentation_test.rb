require_relative '../support/duck_game_adapter'
require_relative '../games/duck_racing/challenge_audio_helpers'
require_relative '../../lib/game_event_presenter'

include GameRoomTest::Assertions

def roster_presenter(harness, viewer, program, covered, messages)
  GameRoomEventPresenter.new(
    game: -> { harness.game }, repository: -> { harness.repository },
    program: -> { program }, viewer: -> { viewer }, client: -> {},
    surface_state: -> { {} }, clock: -> { program.now_ms / 1000.0 },
    covered: -> { covered }, speech: ->(message) { messages[program] << message }, trace: ->(*_args, **_options) {},
    history_changed: ->(*_args) {}, session_changed: -> {}
  )
end

original_play = GameRoomSounds.method(:play)
cues = Hash.new { |hash, program| hash[program] = [] }
messages = Hash.new { |hash, program| hash[program] = [] }
GameRoomSounds.define_singleton_method(:play) { |program, cue| cues[program] << cue; nil }
failures = []
scenarios = 0
begin
  [false, true].each do |covered|
    [:queued, :idle, :unrelated_epoch].each do |mode|
      h = DuckGameAdapterTest::Harness.new
      seed = (1..100).find do |candidate|
        state = GameRoomDuckRacing::Race.start(player_count: 2, laps: 3,
          enabled_challenges: ['guess_number'], seed: candidate)
        GameRoomDuckRacing::Race.new(state).apply(seat: 0, revision: 0, action: {kind: :roll})
        state[:phase] == :turn && state[:turn] == 1
      end
      assert(seed, 'No legal ordinary roll fixture found')
      h.start(seed: seed)
      programs = %w[Bob Carol].to_h { |viewer| [viewer, DuckChallengeAudioTest::Program.new] }
      presenters = programs.to_h { |viewer, program| [viewer, roster_presenter(h, viewer, program, covered, messages)] }
      presenters.each_value { |presenter| presenter.process_new_events(h.replay, session: h.session) }
      h.accept({'action' => 'race', 'input' => {'kind' => 'roll'}}, actor: 'Alice')
      before = h.replay
      assert_equal('Bob', before.current_player, 'Roll did not leave a real pending Bob turn')
      assert_equal(nil, before.state[:round], 'Fixture entered a private challenge')
      assert_equal(nil, h.game.controller_change_phase_error(before), 'The actual game forbids this replacement')
      original_events = Marshal.dump(h.events)
      presenters.each_value { |presenter| presenter.process_new_events(h.replay, session: h.session) }
      assert(presenters.values.all?(&:event_presentation_busy?), 'The actual Duck stages did not defer the turn')

      advance = lambda do
        [1_000, 3_000].each do |time|
          presenters.each do |viewer, presenter|
            programs.fetch(viewer).now_ms = time
            presenter.event_presentation.advance
          end
        end
        assert(presenters.values.none?(&:event_presentation_busy?), 'Ordinary roll stages did not complete')
      end
      advance.call if mode == :idle
      baseline = programs.transform_values { |program| cues[program].count('ding') }
      speech_baseline = programs.transform_values { |program| messages[program].size }

      # The shared fixture records a seat-change boundary. The real participant
      # replay wrapper maps the model and preserves the original accepted log;
      # no replay state or current_player is supplied to the presenter by hand.
      h.replace(1, 'Carol') unless mode == :unrelated_epoch
      h.session['__control_epoch'] = 1
      current = h.replay
      expected_player = mode == :unrelated_epoch ? 'Bob' : 'Carol'
      assert_equal(expected_player, current.current_player)
      assert_equal(original_events, Marshal.dump(h.events), 'Replacement changed the accepted wire prefix')
      assert_equal(h.events, current.accepted_events, 'Participant projection did not retain original events')
      canonical = DuckGameAdapterTest.semantic([current.state, current.history])

      3.times do
        presenters.each_value { |presenter| presenter.process_new_events(h.replay, session: h.session) }
      end
      advance.call unless mode == :idle
      3.times do
        presenters.each_value { |presenter| presenter.process_new_events(h.replay, session: h.session) }
      end

      # Ding is an outside-window reminder, not a second foreground turn cue.
      expected = mode == :unrelated_epoch ? {'Bob' => covered ? 1 : 0, 'Carol' => 0} :
        {'Bob' => 0, 'Carol' => covered ? 1 : 0}
      programs.each do |viewer, program|
        actual = cues[program].count('ding') - baseline.fetch(viewer)
        failures << "#{mode}/covered=#{covered}/#{viewer}: expected #{expected.fetch(viewer)} current-decision cues, got #{actual}" unless actual == expected.fetch(viewer)
        old_turn = h.game.turn_announcement(before, viewer)
        current_turn = h.game.turn_announcement(current, viewer)
        turns = messages[program].drop(speech_baseline.fetch(viewer)).select { |message| [old_turn, current_turn].include?(message) }
        expected_turns = mode == :idle ? [] : [current_turn]
        failures << "#{mode}/covered=#{covered}/#{viewer}: expected current turn speech #{expected_turns.inspect}, got #{turns.inspect}" unless turns == expected_turns
      end
      assert_equal(original_events, Marshal.dump(h.events), 'Presentation mutated accepted events')
      fresh = h.replay
      assert_equal(canonical, DuckGameAdapterTest.semantic([fresh.state, fresh.history]), 'Presentation changed canonical state/history')
      scenarios += 1
    ensure
      presenters&.each_value { |presenter| presenter.event_presentation&.close }
    end
  end
  raise failures.join("\n") unless failures.empty?
ensure
  GameRoomSounds.define_singleton_method(:play, original_play)
end
puts "PASS current decision and turn speech after roster refresh: #{scenarios} real-model queued/idle/unchanged cases, foreground/background, canonical history preserved"
