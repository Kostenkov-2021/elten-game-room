require_relative "../../support/sequence_random"

require_relative "../../support/audio_ball_client"

module Session
  def self.name; @name || 'Alice'; end
  def self.name=(value); @name = value; end
end

class AudioBallPointTransport
  attr_reader :calls, :events
  def initialize; @calls, @events = [], []; end
  def live_store?; true; end
  def append_game_action(**args)
    @calls << args
    args[:events].map do |command|
      event = {'__id' => @events.length + 1, '__insertion_user' => Session.name,
        '__controller' => args[:controller], 'actor' => args[:actor],
        'action' => command.action, 'value' => command.value, 'created_at' => 100 + @events.length * 10}
      @events << event
      event
    end
  end
end

game = GameRoomGames::AudioBall.new
[%w[Alice Bob], %w[Bob Carol], ['bot:7:1', 'bot:7:2']].each do |players|
  transport = AudioBallPointTransport.new
  repository = GameRepository.new(Program.new, transport: transport, server_tables: {})
  session = {'__id' => 11, 'table_id' => 7, '__players' => players, '__insertion_user' => 'Alice',
    'player_one' => players.first, 'options' => JSON.generate(game.default_options)}
  context = GameRoomGames::ActionContext.new(table_owner: 'Alice', random_source: GameRoomRandom::SequenceSource.new([2]), local_data: {}, now: 100)
  screen = GameScreen.allocate
  {game: game, repository: repository, session: session, table_owner: 'Alice', table: {'__id' => 7}, pending_event_ids: []}.each do |key, value|
    screen.instance_variable_set("@#{key}", value)
  end
  screen.define_singleton_method(:action_context) { context }
  screen.define_singleton_method(:network_task) { |_title, **_options, &work| work.call }
  screen.define_singleton_method(:game_recipients) { ['Alice', *players.reject { |name| name.start_with?('bot:') }].uniq }
  replay = game.replay(session, [], repository)
  assert(screen.send(:automatic_action_due?, replay), 'real screen did not wake for the first server draw')
  assert(screen.send(:perform_automatic_action, replay), 'real screen did not persist the first server')
  assert(transport.calls.last[:actor] == players.first && transport.calls.last[:controller] == (players.first != 'Alice'), 'start bypassed the authenticated controller route')
  replay = game.replay(session, transport.events, repository)
  assert(replay.state[:first_server] == 1 && replay.state[:rally] == 0, 'real repository lost the recorded random server')
  GameRoomGames::AudioBall::POINTS_TO_WIN.times do |point|
    context.local_data = {'audio_ball_point' => "#{point}:0"}
    context.now = 100 + transport.events.length * 10
    assert(screen.send(:automatic_action_due?, replay), 'real screen did not wake for an agreed point')
    assert(screen.send(:perform_automatic_action, replay), 'real screen did not submit an agreed point')
    assert(screen.instance_variable_get(:@pending_event_ids) == [transport.events.last['__id']], 'point bypassed pending-event confirmation')
    replay = game.replay(session, transport.events, repository)
  end
  assert(replay.finished? && replay.winner == players.first, 'real screen/repository path did not finish the set')
  assert(transport.events.count { |event| event['action'] == 'audio_ball_start' } == 1, 'server draw repeated during a match')
  Session.name = 'Bob'
  fresh = game.replay(session, [], repository)
  assert(!screen.send(:automatic_action_due?, fresh) && !screen.send(:perform_automatic_action, fresh), 'guest became score authority in the real screen')
  Session.name = 'Alice'
end
puts 'PASS Audio Ball real GameScreen/GameRepository: server draw, complete set, pending confirmations, owner/player and owner/spectator authority'
