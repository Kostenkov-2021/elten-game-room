require_relative "../../support/krowa_services"

run = KrowaTestGame.new
run.automatic
assert(run.guess('Alice', 'xyz', adding: true) == :ok, 'prepare vocabulary')
run.automatic
original = run.replay
event = original.accepted_events.find { |item| item['action'] == 'krowa_vocab' }
profile = GameRoomGames::KrowaProfile.new(run.program, user: 'Alice')
profile.observe(original)
profile.remove_dictionary(['xyz'])
assert(run.action('Alice', 'kind' => 'command', 'action' => 'reroll') == :ok, 'reroll')
run.automatic
run.automatic
after = run.replay
assert(after.state[:round] == 2 && after.state[:commitment] != original.state[:commitment], 'fixture must change round commitment')
profile.observe(after)
assert(!profile.data['dictionary'].include?('xyz'), 'reroll resurrected removed vocabulary')
profile = GameRoomGames::KrowaProfile.new(run.program, user: 'Alice')
writes = run.program.writes
profile.observe(after)
assert(!profile.data['dictionary'].include?('xyz') && run.program.writes == writes, 'reload/idle observation changed processed vocabulary')

# Both prior marker layouts survive: digest=>true and old word=>digest.
[original.state[:commitment], after.state[:commitment], nil].each do |old_commitment|
  digest = Digest::SHA256.hexdigest(JSON.generate([old_commitment, event]))
  [{digest => true}, {'xyz' => digest}].each do |markers|
    program = KrowaTestProgram.new
    legacy = GameRoomGames::KrowaProfile.new(program, user: 'Alice')
    program.write_json(legacy.instance_variable_get(:@path), {'dictionary' => [], 'dictionary_events' => markers})
    legacy = GameRoomGames::KrowaProfile.new(program, user: 'Alice')
    legacy.observe(after)
    assert(!legacy.data['dictionary'].include?('xyz'), 'legacy removed marker lost on migration')
    assert(legacy.data['dictionary_events'].key?(digest), 'legacy marker discarded')
    legacy = GameRoomGames::KrowaProfile.new(program, user: 'Alice')
    legacy.observe(original)
    assert(!legacy.data['dictionary'].include?('xyz'), 'older replay resurrected migrated removal')
  end
end
corrected = Marshal.load(Marshal.dump(after))
corrected.accepted_events.find { |item| item['action'] == 'krowa_vocab' }['created_at'] += 1
profile.observe(corrected)
assert(!profile.data['dictionary'].include?('xyz'), 'timestamp correction changed stable event identity')
assert(run.guess('Alice', 'xyz', adding: true) == :ok, 'prepare deliberate new addition')
run.automatic
profile.observe(run.replay)
assert(profile.data['dictionary'].include?('xyz'), 'new explicit addition of same word denied')
profile.remove_dictionary(['xyz'])
other = KrowaTestGame.new(program: run.program)
other.context.session_id = 50
other.automatic; other.guess('Alice', 'xyz', adding: true); other.automatic
profile.observe(other.replay)
assert(profile.data['dictionary'].include?('xyz'), 'separate session addition denied')
profile.remove_dictionary(['xyz'])
unseen = KrowaTestGame.new(program: run.program)
unseen.context.session_id = 51
unseen.automatic; unseen.guess('Alice', 'xyz', adding: true); unseen.automatic
run.program.fail_write = true
snapshot = Marshal.load(Marshal.dump(profile.data))
failed = false
begin
  profile.observe(unseen.replay)
rescue IOError
  failed = true
end
assert(failed && profile.data == snapshot, 'failed profile write changed in-memory markers or was hidden')
puts 'Krowa profile: reroll, legacy markers, reload, time correction, new addition and separate session OK'
