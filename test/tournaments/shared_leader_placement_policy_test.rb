require_relative '../support/new_games_fixture'
require_relative '../../games/scientific_war'
require_relative '../../games/krowa'
require_relative '../../lib/tournaments/game_result'
require_relative '../../lib/tournaments/standings'

class SharedLeaderMatch
  attr_reader :game, :replay, :events, :context, :options

  def initialize(game, options)
    @game = game
    @players = %w[Alice Bob Carol]
    @options = game.normalize_options(options)
    @session = {'options'=>JSON.generate(@options)}
    @repository = NewGames116Repository.new(@players)
    @events = []
    @context = GameRoomGames::ActionContext.new(session_id:7,
      hidden_submissions:HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
      random_source:GameRoomRandom::SeededSource.new(1),now:1_800_000_000)
    @replay = game.replay(@session,@events,@repository)
  end

  def act(actor, selection)
    @replay = append_action(game,@session,@repository,events,replay,actor,selection,context)
    assert(replay.accepted_events == events,'A complete ordinary history contains a rejected action')
  end

  def export(policy)
    assert(replay.finished?,'The ordinary match did not finish')
    GameRoomTournaments::GameResult.from_replay(game:game,replay:replay,
      players:@players.map { |p| {'username'=>p,'account'=>p.downcase} },options:options,
      events:events,event_count:events.size,result_policy:policy)
  end
end

scientific = SharedLeaderMatch.new(GameRoomGames::ScientificWar.new,'trick_limit'=>20)
chooser = Random.new(0)
700.times do
  break if scientific.replay.finished?
  actor = scientific.game.active_actors(scientific.replay).first
  action = scientific.game.legal_actions(scientific.replay,actor).sample(random:chooser)
  assert(actor && action,'Scientific War route stalled')
  scientific.act(actor,action)
end
totals = scientific.replay.players.to_h do |p|
  [p,scientific.replay.state[:hands][p].size + scientific.replay.state[:piles][p].size]
end
assert(scientific.events.size == 112 && totals == {'Alice'=>21,'Bob'=>21,'Carol'=>0},'Complete Scientific War tie route changed')

build_krowa = lambda do |mode|
  match = SharedLeaderMatch.new(GameRoomGames::Krowa.new,'variant'=>'race','length'=>3,'race_scoring'=>'attempts')
  match.act('Alice',{'kind'=>'automatic','action'=>'prepare'})
  solution = match.context.hidden_submissions.reveal(session_id:7,round_id:'krowa:1',user:'Alice',
    commitment:match.replay.state[:commitment]).payload.fetch('word')
  bank = GameRoomGames::KrowaWordBank.default
  wrong = %w[kot dom las].find { |word| bank.include?(word) && word != solution }
  assert(wrong,'No ordinary wrong-word control')
  sequence = case mode
  when :shared then [['Carol',wrong],['Alice',solution],['Bob',solution]]
  when :all then [['Alice',solution],['Bob',solution],['Carol',solution]]
  when :unique then [['Bob',wrong],['Carol',wrong],['Alice',solution],['Bob',solution]]
  end
  sequence.each do |actor, word|
    match.act(actor,{'kind'=>'question','action'=>'submit','question_id'=>'krowa-answer-1','answer'=>word})
    match.act('Alice',{'kind'=>'automatic','action'=>'evaluate'})
  end
  match.act('Alice',{'kind'=>'automatic','action'=>'reveal'})
  match
end
krowa = build_krowa.call(:shared)
assert(krowa.events.size == 10 && krowa.replay.state[:winners] == %w[Alice Bob],'Complete Krowa shared-leader route changed')

errors = []
type = GameRoomTournaments::GameResult
[scientific,krowa].each do |match|
  expected = {'participants'=>%w[alice bob carol],'winners'=>match.equal?(krowa) ? ['alice'] : [],
    'draw'=>!match.equal?(krowa),'scores'=>nil,'event_count'=>match.events.size}
  %w[game-owned-scores-v1 game-owned-result-v2 game-owned-result-v3
    game-owned-result-v4 game-owned-result-v5 game-owned-result-v6].each do |policy|
    legacy = expected.dup
    legacy['score_order'] = 'higher' if %w[game-owned-result-v4 game-owned-result-v5].include?(policy)
    assert(match.export(policy)==legacy,"Historical #{match.game.id} #{policy} changed")
  end
  before = Marshal.dump(match.replay.state)
  summary = match.export(type::CURRENT_RESULT_POLICY)
  errors << "#{match.game.id} lost shared leaders" unless !summary['draw'] && summary['winners']==%w[alice bob]
  if match.equal?(scientific)
    assert(summary['places']==[%w[alice bob],['carol']],'Scientific War lost finishing places')
    assert(match.game.tournament_placement_scores(match.replay,options:match.options)==
      {scores:totals,order:'higher'},'Scientific War placement card counts changed')
  end
  rows = GameRoomTournaments::Standings.calculate(units:%w[alice bob carol],
    results:[summary.slice('participants','winners','scores','score_order','places').merge('id'=>match.game.id)],
    points:GameRoomTournaments::Standings::MATCH_POINTS)
  assert(rows.to_h { |row| [row['unit'],row['points']] }=={'alice'=>3,'bob'=>3,'carol'=>0},
    "#{match.game.id} shared-first match points changed")
  assert(summary['scores'].nil? && !summary.key?('score_order'),'Placement repair enabled numeric small points')
  assert(Marshal.dump(match.replay.state)==before,'Export mutated the completed game')
end
raise errors.join('; ') unless errors.empty?

all = build_krowa.call(:all).export(type::CURRENT_RESULT_POLICY)
assert(all['draw'] && all['winners'].empty?,'Full Krowa tie did not become a full draw')
unique = build_krowa.call(:unique).export(type::CURRENT_RESULT_POLICY)
assert(!unique['draw'] && unique['winners']==['alice'],'Unique Krowa winner changed')
puts 'PASS complete accepted Krowa and Scientific War matches: shared leaders, full/unique Krowa outcomes, unchanged v1-v6 and disabled small points'
