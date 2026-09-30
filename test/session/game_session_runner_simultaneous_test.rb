require_relative "../support/ui"
require_relative "../../lib/game_surfaces"
require_relative "../support/session_runner"
require_relative "../../content/languages"
require_relative "../../content/quiz_pl_wikidata"
require_relative "../../games/quiz_party"
require_relative "../../games/battleship"

[GameRoomGames::QuizParty.new, GameRoomGames::Categories.new, GameRoomGames::Battleship.new].each do |game|
  h = NativeRoomHarness.new(game: game, users: game.id == 'categories' ? %w[Alice Bob Carol] : %w[Alice Bob])
  h.start
  rs = h.users.to_h { |u| [u, runner_for(h, u)] }
  step(h, rs['Alice'], count: 3)
  if game.id == 'quiz'
    current = h.replay('Alice')
    choice = game.legal_actions(current, 'Alice', context: rs['Alice'].send(:context)).first
    h.as('Alice') { rs['Alice'].submit(session: h.session, replay: current, selection: choice, actor: 'Alice') }
    step(h, rs['Alice'], count: 2)
  end
  # Both forms display the same revision. Alice submits first, without a UI
  # refresh on Bob's side. His independent answer/fleet must remain usable.
  before = h.replay('Bob')
  actors = game.id == 'categories' ? before.state[:active_players] : h.users
  actions = actors.to_h do |u|
    choice = case game.id
    when 'quiz' then game.legal_actions(before, u, context: rs[u].send(:context)).first
    when 'categories' then {'kind'=>'answer_sheet','action'=>'submit','answers'=>{'country'=>'Angola'}}
    when 'battleship' then {'kind'=>'command','action'=>'random_fleet'}
    end
    [u, choice]
  end
  actors.each do |u|
    result = h.as(u) { rs[u].submit(session: h.session, replay: before, selection: actions[u], actor: u) }
    assert(result.first == :ok, "#{game.id}: concurrent submission rejected: #{result.first}")
  end
  h.users.each { |u| step(h, rs[u], u, count: 3) }
  h.assert_converged("#{game.id} simultaneous inputs")
  assert(h.events('Alice').size == h.replay('Alice').accepted_events.size, "#{game.id}: wrote rejected inputs")
  rs.each_value(&:close)
end
puts 'Runner simultaneous inputs: Quiz, Categories and Battleship passed'
