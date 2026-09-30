require_relative "../support/sequence_random"

require_relative "../support/no_bot_table_control"
require_relative "../support/krowa"

# A departed Categories player owns an unrevealed envelope. Returning with
# that envelope must resume normally, but nobody may invent their answer.
[:return, :cancel].each do |outcome|
  game = GameRoomGames::Categories.new
  h = NativeRoomHarness.new(game: game, users: %w[Alice Bob Carol])
  h.start
  contexts = h.users.to_h do |user|
    [user, GameRoomGames::ActionContext.new(session_id: h.session['__id'], table_id: h.table['__id'],
      hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
      random_source: GameRoomRandom::SequenceSource.new([1]), now: 1_000, table_owner: 'Alice')]
  end
  h.submit('Alice', context: contexts['Alice'])
  %w[Bob Carol].each do |user|
    answers = h.replay(user).state[:round_categories].to_h { |category| [category, "#{user}-answer"] }
    h.submit(user, {'kind' => 'answer_sheet', 'action' => 'submit', 'answers' => answers}, context: contexts[user])
  end
  h.as('Bob') { h.transports['Bob'].deactivate_table(table_id: h.table['__id']) }
  h.submit('Alice', context: contexts['Alice'])
  h.submit('Carol', context: contexts['Carol'])
  replay = h.replay('Alice')
  assert(replay.state[:phase] == :revealing && !replay.state[:reveals].key?('Bob'), 'Missing private envelope was invented')
  assert(game.automatic_action(replay, 'Alice', context: contexts['Alice']) == nil, 'Missing answer was automatically judged')
  assert(h.transports['Alice'].room_snapshot(h.table)[:bots].empty?, 'Private answer substituted by a bot')
  if outcome == :return
    h.join('Bob')
    h.submit('Bob', context: contexts['Bob'])
    h.submit('Alice', context: contexts['Alice'])
    assert(h.replay('Alice').state[:phase] == :review, 'Returning player could not reveal their original answer')
    h.assert_converged('Categories private return')
  else
    # Model server succession after an unexpected owner departure, bypassing
    # the intentional UI prohibition on abandoning unrevealed private data.
    h.as('Alice') do
      lobby = LobbyRepository.new(ProgramDouble.new(h.broker.endpoint('Alice')), transport: h.transports['Alice'], server_tables: Object.new)
      lobby.leave_table(h.table, 'Alice')
    end
    current = h.repositories['Carol'].session_for_table(h.table)
    assert(current['__table_owner'] == 'Carol', 'No remaining human inherited the table')
    no_bot_command(h, 'Carol', 'Alice', {'kind' => 'command', 'action' => 'cancel_round'}, now: 1_000, moderator: true)
    state = h.replay('Carol').state
    assert(state[:phase] == :round_complete && state[:completed_rounds] == 0, 'New master cannot cancel an unrecoverable round')
    assert(game.controller_change_error(h.replay('Carol')) == nil, 'Cancelled round did not unlock safe management')
  end
end

# Race and Word Tower use a secret retained by the master. A guest leaving
# must neither destroy it nor start an unsupported bot. No leaderboard or
# daily-access service is involved in these isolated model/transport tests.
%w[race tower].each do |variant|
  fixture = KrowaTestGame.new(variant: variant, players: %w[Alice Bob])
  game = fixture.game
  h = NativeRoomHarness.new(game: game, users: %w[Alice Bob],
    options: game.default_options.merge('variant' => variant, 'length' => 3))
  h.start
  runners = h.users.to_h { |user| [user, runner_for(h, user)] }
  step(h, runners['Alice'], count: 2)
  before = h.replay('Alice')
  secret_before = runners['Alice'].send(:context).hidden_submissions.reveal(
    session_id: h.session['__id'], round_id: 'krowa:1', user: 'Alice')
  h.as('Bob') { h.transports['Bob'].deactivate_table(table_id: h.table['__id']) }
  step(h, runners['Alice'], count: 5)
  assert(h.transports['Alice'].room_snapshot(h.table)[:bots].empty?, "Krowa #{variant}: invented bot")
  assert(h.replay('Alice').state == before.state, "Krowa #{variant}: departure changed the word/attempts")
  h.join('Bob')
  runners['Bob'].close
  runners['Bob'] = runner_for(h, 'Bob')
  step(h, runners['Bob'], 'Bob', count: 2)
  after = h.replay('Bob')
  assert(after.state == before.state, "Krowa #{variant}: reconnect lost the current word")
  assert(runners['Alice'].send(:context).hidden_submissions.reveal(
    session_id: h.session['__id'], round_id: 'krowa:1', user: 'Alice').payload == secret_before.payload,
    "Krowa #{variant}: guest reconnect replaced the secret")
  actor = variant == 'tower' ? after.current_player : 'Bob'
  choice = {'kind' => 'question', 'action' => 'submit', 'question_id' => 'krowa-answer-1',
    'answer' => secret_before.payload.fetch('word')}
  h.as(actor) do
    assert(runners[actor].submit(session: h.session, replay: after, selection: choice, actor: actor).first == :ok,
      "Krowa #{variant}: legal guess after reconnect was rejected")
  end
  step(h, runners['Alice'], count: 4)
  assert(h.replay('Alice').accepted_events.size > before.accepted_events.size, "Krowa #{variant}: pending guess did not advance")
  assert(h.replay('Alice').state[:pending].empty?, "Krowa #{variant}: master lost ability to evaluate")
  h.assert_converged("Krowa #{variant} guest departure/return and next guess")
  runners.each_value(&:close)
end
puts 'Private no-bot games: Categories missing reveal/return/new-master cancellation, Krowa Race/Tower guest return and continued evaluation: OK'
