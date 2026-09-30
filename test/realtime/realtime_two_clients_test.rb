require_relative "../support/relay"

[0.0, 14.0].each do |ignore_until|
  rig = RelayFixture.new(ignore_until: ignore_until)
  rules = GameRoomGames::AxelPong.new
  repository = Object.new
  def repository.players_for(_session); %w[Alice Bob]; end
  replay = rules.replay({'__insertion_user' => 'Alice', 'options' => '{}'}, [], repository)
  clients = %w[Alice Bob].to_h do |name|
    program = Program.new
    program.define_singleton_method(:communication) { rig.endpoint(name) }
    program.define_singleton_method(:release) { |_resource| }
    client = GameRoomPong::Client.new(program, rules, clock: -> { rig.now }, audio: PongTestAudio.new,
      channel_factory: ->(**args) { GameRoomRealtime::EventChannel.new(**args,
        work_factory: -> { rig.worker(name) }, event_work_factory: -> { rig.worker(name) }) })
    client.bind_screen(session_id: 5, table_id: 6, owner: 'Alice', viewer: name, members: -> { %w[Alice Bob] })
    client.start
    client.before_wait(replay, name)
    client.attach_view(Form.new([]), PongTestSurface.new)
    [name, client]
  end
  ready_at = nil
  1600.times do
    rig.now += 0.016
    rig.advance_work
    clients.each_value(&:frame)
    if clients.values.none?(&:paused)
      ready_at = rig.now
      break
    end
  end
  assert(ready_at, "real Channel/client combination stranded a handshake (ignored until #{ignore_until})")
  assert(ignore_until > 0 || ready_at < 4.5, 'transient missing endpoint still added five seconds to startup')
  assert(ignore_until.zero? || rig.groups.length >= 2, 'silent handshake was not actually replaced')
  assert(rig.invites.length < 30, 'recovery flooded invitations')
  clients.each_value(&:close)
  assert(rig.endpoints.values.all?(&:closed?), 'native fixture endpoint leaked')
  puts "PASS two real Channel/Pong clients: ignored_until=#{ignore_until}, ready_at=#{ready_at.round(3)}, invitations=#{rig.invites.length}, sessions=#{rig.groups.length}"
end
