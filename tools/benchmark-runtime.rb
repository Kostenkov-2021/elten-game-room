require 'json'
require 'optparse'
require 'digest'
require_relative '../games/catalog'
require_relative '../lib/game_simulation'
require_relative '../test/support/contract_values'

options = {iterations: 10, games: %w[spades monopoly uno categories quiz four_in_a_row], output: nil}
OptionParser.new do |parser|
  parser.on('--iterations N', Integer) { |value| options[:iterations] = value }
  parser.on('--games IDS', Array) { |value| options[:games] = value }
  parser.on('--output FILE') { |value| options[:output] = value }
end.parse!
abort 'iterations must be positive' unless options[:iterations].positive?
corpus_path = File.expand_path('../test/fixtures/contracts/v1/histories.json', __dir__)
corpus = JSON.parse(File.read(corpus_path, encoding: 'UTF-8')).fetch('cases')
results = []

def measure(iterations)
  GC.start
  allocations = GC.stat(:total_allocated_objects)
  cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
  wall = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  value = nil
  iterations.times { value = yield }
  { wall_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall,
    cpu_seconds: Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu,
    allocated_objects: GC.stat(:total_allocated_objects) - allocations,
    result: GameRoomTest::ContractValues.digest(value) }
end

options[:games].each do |id|
  item = corpus.find { |candidate| candidate.fetch('game') == id } or abort "Unknown corpus game: #{id}"
  game = GameRoomGames::CATALOG.build(id)
  session, events = item.values_at('session', 'events')
  repository = GameRoomSimulation::Repository.new(item.fetch('players'))
  replay = game.replay(session, events, repository)
  viewer = replay.current_player || replay.players.first
  tasks = {
    replay: -> { game.replay(session, events, repository) },
    snapshot_copy: -> { Marshal.load(Marshal.dump(replay)) },
    view: -> { game.game_view_spec(replay, viewer); nil },
    legal_actions: -> { game.legal_actions(replay, viewer) }
  }
  if game.supports_bots? && !replay.finished?
    tasks[:bot] = -> do
      context = GameRoomGames::ActionContext.new(session_id: session['__id'], table_id: session['table_id'],
        options: game.options_from_json(session['options']), now: events.length,
        random_source: GameRoomRandom::SeededSource.new(241))
      decision = GameRoomBots::Coordinator.new.decide(game: game, replay: replay, actor: viewer,
        context: context, controlled_actors: [viewer],
        simulation_factory: -> { GameRoomSimulation::Environment.from_snapshot(game: game, session: session, events: events, players: replay.players, seed: 241) })
      [decision&.action, context.random_source.roll(count: 8, sides: 1000).values]
    end
  end
  tasks.each do |phase, task|
    task.call # Warm lazy content/code independently of measured iterations.
    results << {game: id, phase: phase, events: events.length, iterations: options[:iterations]}.merge(measure(options[:iterations], &task))
  end
end

lock = Mutex.new
results << {game: nil, phase: 'uncontended_lock', iterations: options[:iterations] * 1000}.merge(
  measure(options[:iterations] * 1000) { lock.synchronize { nil } })
report = {schema: 1, ruby: RUBY_DESCRIPTION, platform: RUBY_PLATFORM,
  corpus_sha256: Digest::SHA256.file(corpus_path).hexdigest,
  scope: 'Local CPU/allocation benchmark; no UI controls, network, disk writes or contended session planning in measured sections.',
  results: results}
json = JSON.pretty_generate(report) + "\n"
options[:output] ? File.write(options[:output], json) : puts(json)
