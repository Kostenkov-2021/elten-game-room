# Explicit authoring tool, never run automatically when tests fail.
require 'json'
require 'fileutils'
require 'optparse'
require_relative '../support/model_contract'
require_relative '../support/spades_decision_contract'

options = {source: nil, output: nil}
OptionParser.new do |parser|
  parser.on('--source DIRECTORY') { |value| options[:source] = File.expand_path(value) }
  parser.on('--write DIRECTORY') { |value| options[:output] = File.expand_path(value) }
end.parse!
abort 'Unexpected arguments' unless ARGV.empty?
abort 'Specify the reference checkout with --source' unless options[:source]
abort 'Specify a NEW corpus directory with --write' unless options[:output]
abort 'Corpus already exists; create a new version and review the differences' if File.exist?(options[:output])

source = options.fetch(:source)
# The baseline predates the headless catalog. Load that snapshot in this process
# without mixing any production files from the working tree into the oracle.
require File.join(source, 'test/support/ui')
require File.join(source, 'test/support/log')
require File.join(source, 'test/support/native_live_sessions')
class Program
  def self.server_app(**_options); end
end
require File.join(source, '__app')
require File.join(source, 'lib/game_simulation')
require File.join(source, 'lib/hidden_submissions')

class CorpusEnvironment < GameRoomSimulation::Environment
  def initialize(**arguments)
    super
    @vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
  end
  def context; super.tap { |value| value.hidden_submissions = @vault }; end
end

cases = []
EltenGameRoom::GAME_REGISTRY.ids.sort.each do |id|
  game = EltenGameRoom::GAME_REGISTRY.build(id)
  next if %w[axel_pong audio_ball].include?(game.id)
  seed = 137
  settings = game.default_options.merge('bot_delay' => 0)
  players = GameRoomTest::ModelContract.players_for(game, settings)
  # Synthetic secrets only; this override is confined to this authoring process.
  random = Random.new(seed)
  SecureRandom.define_singleton_method(:hex) { |n = 16| Array.new(n) { random.rand(256).to_s(16).rjust(2, '0') }.join }
  env = CorpusEnvironment.new_game(game: game, players: players, options: settings, seed: seed)
  steps = []
  16.times do
    break if env.finished?
    actor = env.active_actor
    action = env.legal_actions(actor).first
    break unless action
    checkpoint = GameRoomTest::ModelContract.checkpoint(env)
    status = env.step(action, actor: actor)
    raise "#{id}: rejected legal action: #{status}" unless status == :ok
    steps << checkpoint.merge('action' => action)
  end
  cases << { 'game' => id, 'seed' => seed, 'players' => players, 'options' => settings,
    'steps' => steps, 'final' => GameRoomTest::ModelContract.checkpoint(env),
    'session' => env.session, 'events' => env.events }
  puts "#{id}: #{steps.length} actions, #{env.events.length} events"
end
decisions = GameRoomTest::SpadesDecisionContract.capture(GameRoomGames::Spades.new,
  cases.find { |item| item.fetch('game') == 'spades' })
FileUtils.mkdir_p(File.dirname(options[:output]))
Dir.mkdir(options[:output]) # Atomic refusal if another process created this version.
File.write(File.join(options[:output], 'histories.json'), JSON.pretty_generate('schema' => 1, 'cases' => cases) + "\n", mode: 'wx')
File.write(File.join(options[:output], 'spades-decisions.json'), JSON.pretty_generate(decisions) + "\n", mode: 'wx')
