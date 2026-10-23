require_relative 'client_helpers'

class DuckClientSessionPauseTest
  include DuckClientTest

  def run
    private_deadline
    countdown
    active_sound
    historical_feedback
    retained_result
    pause_control_and_roster
    report('Duck durable pause: private time, input, countdown, native resume and historical feedback')
  end

  def setup_paused_client(kind, **options)
    setup_client(kind, **options, session_time: ->(state) {
      raw = state[:frozen_at] || (100.0 + @program.now_ms / 1000.0)
      ((raw - state[:clock_offset].to_f) * 1000).round
    })
  end

  def set_paused(paused)
    if paused
      @freeze_start = @program.now_ms
      @replay.state[:frozen_at] = 100.0 + @program.now_ms / 1000.0
    else
      @replay.state[:clock_offset] = @replay.state[:clock_offset].to_f +
        (@program.now_ms - @freeze_start) / 1000.0
      @replay.state.delete(:frozen_at)
    end
    @client.update_table_control({'__players' => @replay.players,
      '__table_owner' => @replay.state[:owner], '__control_epoch' => 'initial',
      '__frozen' => paused})
    @client.before_wait(@replay, @viewer)
  end

  def private_deadline
    setup_paused_client('quiz')
    advance(100)
    trace = @client.instance_variable_get(:@trace)
    original = Marshal.dump(trace.state)
    set_paused(true)
    @surface.push(:answer, value: trace.state[:model][:question][:correct_index])
    advance(25_100, background: true)
    assert(!trace.finished?, 'A paused private quiz used its answer time')
    assert_equal(original, Marshal.dump(trace.state))
    assert_equal(100, @client.send(:elapsed_ms))
    assert_equal(nil, request)
    assert_equal(false, @client.local_input_during_operation?(@surface))
    advance(25_100) # Present the paused view when this field is foreground again.
    assert_equal(false, @surface.presentation[:enabled])
    set_paused(false)
    advance(25_200)
    assert_equal([], trace.instance_variable_get(:@actions), 'Input during the pause was replayed')
    assert_equal(true, @surface.presentation[:enabled])
    @surface.push(:answer, value: trace.state[:model][:question][:correct_index])
    advance(25_300)
    assert(trace.finished?)
    assert_equal([300], request['trace']['actions'].map { |action| action['at'] })
    assert_equal(300, request['trace']['finished_at'])
  ensure
    close
  end

  def countdown
    setup_paused_client('copy_number')
    advance(5_000)
    advance(5_100)
    sound = @program.sounds.find { |item| item.asset == GameRoomDuckRacing::ChallengeAudio::COUNTDOWN_ASSET }
    set_paused(true)
    position = sound.position
    advance(35_100)
    assert(!sound.playing?, 'The physical countdown kept playing during the durable pause')
    assert_equal(position, sound.position)
    assert(@client.local_view[:preparing])
    assert_equal(nil, request)
    set_paused(false)
    assert_equal([0], sound.seeks, 'Resuming sought back to the beginning of the countdown')
    assert_equal(2, sound.plays)
    advance(30_000 + ENGINE::PREPARATION_MS - 1)
    assert(@client.local_view[:preparing])
    advance(30_000 + ENGINE::PREPARATION_MS)
    assert(!@client.local_view[:preparing])
    trace = @client.instance_variable_get(:@trace)
    @surface.push(:answer, value: trace.state[:model][:answer])
    advance(30_100 + ENGINE::PREPARATION_MS)
    assert_equal(100, request['trace']['finished_at'])
    assert(sound.closed?)
  ensure
    close
  end

  def active_sound
    setup_paused_client('simon')
    advance(0)
    advance(50)
    sound = @program.sounds.first
    trace = @client.instance_variable_get(:@trace)
    state = Marshal.dump(trace.state)
    set_paused(true)
    position = sound.position
    advance(10_050)
    assert_equal(state, Marshal.dump(trace.state))
    assert(!sound.playing?)
    assert_equal(position, sound.position)
    assert_equal(nil, request)
    set_paused(false)
    advance(10_150)
    assert_equal(:responding, @client.local_view.dig(:own, :phase))
    assert_equal(5_150, @client.local_view.dig(:own, :deadline_ms))
    assert_equal([0], sound.seeks)
    assert_equal(2, sound.plays)
    assert_equal(nil, request)
    # The pause level is not tied to control epochs, and repeated refreshes
    # must not add the same elapsed interval a second time.
    3.times { @client.update_table_control({'__players' => @replay.players,
      '__table_owner' => 'Alice', '__control_epoch' => 'initial', '__frozen' => false}) }
    advance(10_160)
    assert_equal(160, @client.send(:elapsed_ms))
  ensure
    close
  end

  def historical_feedback
    setup_paused_client('sound_memory')
    before = Marshal.load(Marshal.dump(@replay))
    engine = @replay.state[:round][:engine]
    seat = ENGINE.current_turn(engine)
    assert(ENGINE.submit(engine, seat: seat,
      action: {kind: :reveal, value: 1, press_id: 1}, now_ms: 10, resources: resources))
    @replay.state[:revision] += 1
    @client.before_wait(@replay, @viewer)
    feedback = @client.event({'__id' => 1}, before, @replay, @viewer, Repository.new)
    advance(20)
    assert(feedback.busy?)
    set_paused(true)
    advance(500)
    assert(feedback.finished?, 'A durable pause stalled already accepted historical feedback')
    assert_equal([], @program.managed)
    assert_equal(nil, request)
  ensure
    close
  end

  def retained_result
    setup_paused_client('quiz')
    trace = @client.instance_variable_get(:@trace)
    @surface.push(:answer, value: trace.state[:model][:question][:correct_index])
    advance(100)
    original = Marshal.dump(request)
    assert(trace.finished?)
    set_paused(true)
    advance(30_100)
    assert_equal(nil, request)
    set_paused(false)
    advance(30_200)
    assert_equal(original, Marshal.dump(request), 'A pause discarded or recaptured a completed attempt')
  ensure
    close
  end

  def pause_control_and_roster
    setup_paused_client('guess_number')
    advance(100)
    trace = @client.instance_variable_get(:@trace)
    set_paused(true)
    # A same-challenge host change must not discard the local attempt.
    @replay.state[:owner] = 'Bob'
    @client.update_table_control({'__players' => @replay.players,
      '__table_owner' => 'Bob', '__control_epoch' => 'transfer', '__frozen' => true})
    @client.before_wait(@replay, @viewer)
    advance(125_100)
    assert_equal(trace, @client.instance_variable_get(:@trace))
    assert(!trace.finished?)
    assert_equal(100, @client.send(:elapsed_ms))
    @client.update_table_control({'__players' => %w[Alice Replacement Charlie],
      '__table_owner' => 'Bob', '__control_epoch' => 'replacement', '__frozen' => true})
    assert_equal(nil, @client.instance_variable_get(:@trace))
    assert_equal(nil, request)
    assert_equal([], @program.managed)
  ensure
    close
  end
end

DuckClientSessionPauseTest.new.run
