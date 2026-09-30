require_relative "../../support/pong_mixed"
require_relative "../../support/realtime_event_channel"

class MixedGoalSession < ChannelSession
  attr_reader :reliable_sent
  def initialize(network, viewer, names)
    super('mixed-goal-session', viewer, names)
    @network, @viewer, @reliable_sent = network, viewer, []
    network[viewer] = self
  end
  def send_unreliable(data, to:)
    super
    to.each { |target| @network.fetch(target.user).deliver(@viewer, data) }
  end
  def send_reliable(data, to:)
    @reliable_sent << [data, to.map(&:user)]
    to.each { |target| @network.fetch(target.user).deliver_event(@viewer, data) }
    Struct.new(:results).new(to.to_h { |target| [target, :delivered] })
  end
end

[
  ['Alice', 'Bob', 'Carol', 'bot:7:1'],
  ['Bob', 'Carol', 'Dave', 'bot:7:1'],
  ['Bob', 'bot:7:1']
].each do |players|
  h = mixed_goal_match(players)
  begin
    sessions, workers = {}, []
    names = h.clients.keys
    names.each { |name| MixedGoalSession.new(sessions, name, names) }
    h.clients.each do |name, client|
      previous = h.network.fetch(name.downcase)
      previous.close
      factory = -> { worker = ChannelWork.new; workers << worker; worker }
      native = GameRoomRealtime::EventChannel.new(program: ChannelProgram.new(name),
        match: client.instance_variable_get(:@match), owner: 'Alice', viewer: name,
        clock: -> { h.now }, members: -> { names }, work_factory: factory, event_work_factory: factory)
      native.enable_events(previous.event_protocol)
      native.instance_variable_set(:@endpoint, ChannelEndpoint.new(name))
      native.__send__(:attach, sessions.fetch(name))
      client.instance_variable_set(:@channel, native)
      client.before_wait(h.replay, name)
      h.network[name.downcase] = native
    end
    advance = ->(count) do
      count.times do
        workers.each { |worker| worker.finish if worker.operation }
        h.advance(1)
      end
    end
    advance.call(200)
    assert(h.clients.values.none?(&:paused), 'native EventChannel mixed match failed to prepare')
    concede_mixed_goal(h, advance: advance)
    advance.call(20)
    assert(names.all? { |name| mixed_audio(h, name).goals.length == 1 }, 'native confirmation did not present the goal')
    assert(h.replay.state[:rally].zero?, 'native confirmation advanced durable state')
    sends = sessions.fetch('Alice').reliable_sent.select { |data, _| JSON.parse(data).dig('d', 'action') == 'point' }
    assert(sends.length == 1 && sends.first[1].sort == (names - ['Alice']).sort,
      'goal confirmation was repeated or omitted a human/observer')
    assert((names - ['Alice']).all? { |name| sessions[name].reliable_sent.none? { |data, _| JSON.parse(data).dig('d', 'action') == 'point' } },
      'guest echoed the confirmation')
    data = sends.first.first
    assert(data.bytesize <= GameRoomRealtime::Protocol::MAX_BYTES, 'goal confirmation exceeded packet size')
    sessions.fetch('Bob').deliver_event('Alice', data)
    sessions.fetch('Bob').deliver_event('Mallory', data)
    sessions.fetch('Bob').deliver_event('Alice', JSON.generate(JSON.parse(data).merge('e' => 'old epoch')))
    advance.call(2)
    assert(mixed_audio(h, 'Bob').goals.length == 1, 'native sender/generation/deduplication checks failed')
    deliver_mixed_point(h, h.clients['Alice'].context_data.fetch('pong_point'))
    assert(names.all? { |name| mixed_audio(h, name).goals.length == 1 }, 'native confirmation duplicated durable audio')
  ensure
    h.close
  end
end

puts 'PASS mixed goal EventChannel: finite worker, reliable delivery to humans/observers, native validation, no guest echo, owner-player/observer and Single'
