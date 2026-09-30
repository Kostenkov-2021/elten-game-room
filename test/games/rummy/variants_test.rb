require_relative "../../support/new_games_fixture"
require_relative "../../../games/rummy"

game = GameRoomGames::Rummy.new
rules = GameRoomRummyRules
2.upto(8) do |count|
  [false, true].each do |identities|
    players = count.times.map { |i| "Player#{i}" }
    repo = NewGames116Repository.new(players)
    options = game.default_options.merge("identities" => identities)
    session = { "options" => JSON.generate(options) }
    events = []
    replay = game.replay(session, events, repo)
    replay = append_action(game, session, repo, events, replay, players.first, { "action" => "deal" }, context_for)
    cards = replay.state[:stock] + replay.state[:hands].values.flatten
    copies = identities ? 4 : count <= 4 ? 2 : count <= 6 ? 3 : 4
    assert(cards.length == 54 * copies && cards.uniq.length == cards.length, "deck conservation #{count}/#{identities}")
    assert(cards.count { |c| rules.joker?(c) } == copies * 2, "joker count")
    assert(replay.state[:hands].values.all? { |h| h.length == 14 }, "deal count")
  end
end

# Every legal action uses the same validation as replay. This bounded smoke run
# covers all discard modes and both score directions; it is not a bot strength
# claim or a search for a lucky completed match.
timings = []
%w[none discard single multiple].each do |mode|
  [false, true].each do |elimination|
    options = game.default_options.merge("discard_mode" => mode, "elimination" => elimination, "first_meld" => 15)
    players = %w[Alice Bob]
    repo = NewGames116Repository.new(players)
    session = { "options" => JSON.generate(options) }
    events = []
    replay = game.replay(session, events, repo)
    random = NewGames116Random.new
    ctx = context_for(random)
    24.times do
      actor = replay.current_player || players.first
      auto = game.automatic_action(replay, players.first, context: ctx)
      if auto
        actor = players.first
        action = auto
      else
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        actions = game.legal_actions(replay, actor, context: ctx)
        action = GameRoomBots.choose(game.bot_strategy, actions: actions, actor: actor, game: game, replay: replay, random_source: random)
        timings << Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        assert(action, "bot deadlock in #{mode}")
      end
      replay = append_action(game, session, repo, events, replay, actor, action, ctx)
      assert(replay.accepted_events.length == events.length, "a valid action was rejected in replay")
      cards = replay.state[:hands].values.flatten + replay.state[:stock] + replay.state[:discard] + replay.state[:melds].flat_map { |m| m[:cards] }
      assert(cards.length == 108 && cards.uniq.length == 108, "lost or duplicated physical card")
      assert(events.all? { |e| e["value"].length <= 64 }, "oversized event")
      assert(replay.state == game.replay(session, events, repo).state, "replay divergence")
      break if replay.finished?
    end
  end
end
puts "Rummy variants, conservation and deterministic multi-client replay: OK; max bot decision #{(timings.max * 1000).round(1)} ms"
