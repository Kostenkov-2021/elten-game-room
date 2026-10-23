require_relative '../../support/new_games_fixture'
require_relative '../../support/monopoly_debt_route'
require 'digest'

game = GameRoomGames::Monopoly.new
players = %w[Alice Bob Carol]
repository = NewGames116Repository.new(players)
session = {'options'=>JSON.generate(game.normalize_options('board'=>'barcelona'))}
events = MonopolyDebtRoute.events
digest = Digest::SHA256.hexdigest(JSON.generate(events))
assert(digest == 'b0880ab2f3288bac935c4ec118198de2e6b323e3ea66b944420e7ea9dd7805cf', 'Original accepted debt route changed')
replay = game.replay(session, events, repository)
assert(replay.accepted_events == events && Digest::SHA256.hexdigest(JSON.generate(events)) == digest, 'Debt repair changed accepted input')
assert(replay.state[:cash].values_at(*players) == [0, 1, 49_199_999] && replay.state[:debts].values.all?(&:empty?), 'Reciprocal rent accounting changed')
assert(replay.current_player == 'Carol' && !replay.finished?, 'Debt settlement changed the next turn')
assert(replay.history.length < 100, 'One reciprocal rent still expands into amount-scaled history')
continued = append_action(game, session, repository, events, replay, 'Carol', {'action'=>'roll'}, context_for)
assert(continued.accepted_events == events && events.length == 38, 'The next ordinary roll no longer works')

# The literal former serial accounting is a small-state oracle. Keep debt
# order, bank/sink handling and negative balances; do not replace it by netting.
serial = lambda do |state|
  loop do
    paid_any = false
    state[:debts].each do |player, debts|
      available = [state[:cash][player] + debts.sum { |debt| debt[:amount] }, 0].max
      debts.each do |debt|
        paid = [available, debt[:amount]].min
        next if paid <= 0
        debt[:amount] -= paid
        available -= paid
        game.send(:credit_money, state, debt[:to], paid)
        paid_any = true
      end
      debts.reject! { |debt| debt[:amount] <= 0 }
    end
    break unless paid_any
  end
end
random = Random.new(49)
128.times do |index|
  names = Array.new(2 + index % 7) { |seat| "Seat#{seat}" }
  debts = names.shuffle(random: random).to_h do |name|
    recipients = (names - [name]) + [:bank, :jackpot]
    [name, Array.new(random.rand(0..3)) { {to: recipients.sample(random: random), amount: random.rand(1..30)} }]
  end
  state = {players: names, debts: debts, bankrupt: names.to_h { |name| [name, random.rand(8).zero?] },
    cash: names.to_h { |name| [name, random.rand(-4..12) - debts[name].sum { |debt| debt[:amount] }] }, jackpot: 0}
  expected = Marshal.load(Marshal.dump(state))
  serial.call(expected)
  game.send(:settle_debts, state)
  assert(state == expected, "Changed serial creditor priority/accounting for seed49 case#{index}")
end

# A period-two cycle must release money to the next creditor only after the
# first claim is exhausted. The second case cannot skip even one full cycle.
[[20, 1, true], [4, 3, false]].each do |amount, liquidity, accelerates|
  names = %w[Alice Bob Carol Dave]
  state = {players:names, bankrupt:{}, jackpot:0, debts:{
    'Alice'=>[{to:'Carol', amount:amount}, {to:'Dave', amount:5}],
    'Bob'=>[{to:'Alice', amount:amount}], 'Carol'=>[{to:'Bob', amount:amount}], 'Dave'=>[]},
    cash:{'Alice'=>liquidity - amount - 5, 'Bob'=>-amount, 'Carol'=>-amount, 'Dave'=>0}}
  expected = Marshal.load(Marshal.dump(state))
  serial.call(expected)
  cycle_returns = []
  trace = TracePoint.new(:return) do |event|
    cycle_returns << event.return_value if event.self.equal?(game) && event.method_id == :settle_repeated_debt_cycle
  end
  trace.enable { game.send(:settle_debts, state) }
  assert(state == expected && state[:cash]['Dave'] == liquidity, 'Later creditor received the wrong residual funds')
  assert(cycle_returns.include?(accelerates), 'Named repeated-cycle/full-cycle-zero boundary was not reached')
end

# Without a repeated cycle, preserve ordinary repayment messages and keys,
# including the unpaid remainder, exactly rather than rewriting all history.
ordinary = {players:%w[Alice Bob Carol], bankrupt:{}, jackpot:0,
  cash:{'Alice'=>-4, 'Bob'=>0, 'Carol'=>0},
  debts:{'Alice'=>[{to:'Bob', amount:5}, {to:'Carol', amount:2}], 'Bob'=>[], 'Carol'=>[]}}
history = []
game.send(:settle_debts, ordinary, 77, history)
assert(history.map(&:to_h) == [{key:'debt:77:0',
  text:'Alice repays 3 of debt to Bob. Alice still owes 2 to Bob.',
  event_id:77, actor:'Alice', kind: :game, field:nil, value:nil}], 'Ordinary repayment history changed')

# Reverse insertion order makes circulation take several passes; two disjoint
# cycles also have a multi-pass period. Work must not depend on debt magnitude.
[[1, 0], [2, 0, 1], [1, 2, 0, 4, 5, 6, 7, 3]].each do |recipients|
  names = recipients.each_index.map { |index| "Cycle#{index}" }
  amount = 10**12
  debts = names.reverse.to_h do |name|
    index = names.index(name)
    [name, [{to: names[recipients[index]], amount: amount}]]
  end
  cash = names.to_h { |name| [name, -amount] }
  cash[names.first] += 1
  cash[names[3]] += 1 if names.length == 8
  state = {players: names, debts: debts, cash: cash, bankrupt: {}, jackpot: 0}
  history = []
  game.send(:settle_debts, state, 99, history)
  assert(state[:debts].values.all?(&:empty?) && state[:cash].values.sum == (names.length == 8 ? 2 : 1), 'Large cycle accounting changed')
  assert(history.length <= 512 && history.map(&:key).uniq.length == history.length, 'Large cycle work/history is not bounded by its topology')
end
puts 'PASS Monopoly: complete accepted rent route, next roll, 128 serial oracles, later-creditor/zero-bulk boundaries, exact ordinary history and large multi-pass cycles'
