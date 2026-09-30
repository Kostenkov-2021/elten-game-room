require_relative "../support/session_runner"

messages = []
Log.define_singleton_method(:warning) { |message| messages << message }
h = NativeRoomHarness.new(game: GameRoomGames::TicTacToe.new, users: %w[Alice Bob])
h.start
r = runner_for(h)
calls = 0
failure = NoMethodError.new('deliberate broken reducer')
failure.set_backtrace(['reducer.rb:42:in apply'])
r.instance_variable_set(:@room_snapshot_provider, -> { calls += 1; raise failure })
writes = h.view('Alice').calls[:push]
h.as('Alice') { 100.times { r.step } }
assert(calls == 1, 'internal exception was automatically retried')
assert(r.take_error.equal?(failure) && r.take_error.nil?, 'UI must receive original internal exception exactly once')
assert(!r.instance_variable_get(:@sync).recovery_pending? && r.recovery_delay == 0, 'internal failure masquerades as network outage')
assert(messages.length == 1 && messages.first.include?('reducer.rb:42'), 'missing/bursting internal error diagnostic')
assert(!h.core.closed && h.view('Alice').calls[:push] == writes, 'internal fault mutated or closed server state')
begin
  submit(h, r)
  raise 'faulted executor accepted another write'
rescue NoMethodError => error
  assert(error.equal?(failure), 'replaced original failure')
end
r.close

[EltenAPI::LiveSessions::TimeoutError.new('timeout'), GameRoomNetworkErrors::UncertainWrite.new('HTTP 429: rate limited')].each do |error|
  h = NativeRoomHarness.new(game: GameRoomGames::TicTacToe.new, users: %w[Alice Bob])
  h.start
  r = runner_for(h)
  tick, calls = 0.0, 0
  r.instance_variable_get(:@sync).instance_variable_set(:@clock, -> { tick })
  provider = r.instance_variable_get(:@room_snapshot_provider)
  r.instance_variable_set(:@room_snapshot_provider, -> { calls += 1; raise error if calls == 1; provider.call })
  h.as('Alice') { 100.times { r.step } }
  assert(calls == 1 && r.instance_variable_get(:@internal_error).nil?, 'network backoff lost')
  assert(r.instance_variable_get(:@sync).next_reconcile_at == (error.message.include?('429') ? 60 : 30), 'wrong recovery delay')
  tick = 61
  step(h, r, count: 3)
  assert(r.presentation_snapshot && r.take_error.nil?, 'known network error no longer recovers')
  # Recovery deliberately leaves historical errors unannounced. A later
  # programmer error must replace that stale queue entry, not disappear.
  r.instance_variable_set(:@dirty, true)
  fatal = NoMethodError.new('failure after recovery')
  r.instance_variable_set(:@room_snapshot_provider, -> { raise fatal })
  h.as('Alice') { r.step }
  assert(r.take_error.equal?(fatal), 'old network error hid a new internal failure')
  r.close
end
puts 'Internal faults: one diagnostic, no retries/writes/close, original UI error; timeout and rate-limit recovery retained'
