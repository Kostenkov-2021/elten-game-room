require_relative '../support/tournament_native'
require_relative '../support/native_background_capacity'
require_relative '../../lib/tournaments/server_proposal_screen'
include GameRoomTest::Assertions
T = GameRoomTournaments

GameRoomTest::NativeBackgroundCapacity.with(128) do |work, free_capacity, runtime|
  revision, cached = 2, nil
  program_class = Class.new do
    class << self; attr_accessor :app_runtime; end
  end
  program_class.app_runtime = runtime
  program_class.define_singleton_method(:tournament_view_revision) { |_reference| revision }
  program_class.define_singleton_method(:tournament_proposal_snapshot) { |*_, **_| cached }
  context = Object.new
  context.define_singleton_method(:current?) { |_lease| true }
  calls = []
  value = {'state'=>'awaiting_consent', 'token'=>'a'*64, 'table_available'=>false,
    'players'=>%w[alice bob], 'accepted'=>['alice'], 'window'=>{'opens'=>100,'closes'=>280}}
  workspace = Object.new
  workspace.define_singleton_method(:proposal_view_on_worker) do |**arguments|
    calls << arguments
    value
  end
  screen = T::ServerProposalScreen.allocate
  {program:program_class.new, workspace:workspace, context:context, lease:Object.new,
    reference:{'author'=>'alice','publication_key'=>'fixture'}, match:{'match_id'=>'b'*64,'leg'=>1},
    clock:-> {100}, refresh_work:work, read_generation:1, view_revision:1,
    observed:value}.each { |name,input| screen.instance_variable_set("@#{name}", input) }
  # Admission boundary uses the actual update method, Work and native capacity.
  # Rendering/context are fixture projections; full native form behavior has a
  # separate existing server_proposal_refresh_native_test.
  rendered = []
  screen.define_singleton_method(:render) do |result|
    rendered << result
    @observed = result
  end
  3.times { screen.send(:update_invitation) }
  assert_equal(1, screen.instance_variable_get(:@view_revision), 'Refusal consumed the pending view revision')
  assert(calls.empty?, 'Full capacity was bypassed')
  cached = value.merge('state'=>'declined')
  revision = 3
  screen.send(:update_invitation)
  assert_equal(cached, rendered.last, 'Already available coordinator view must not need a worker slot')
  assert_equal(3, screen.instance_variable_get(:@view_revision))
  cached = nil
  revision = 4
  screen.send(:update_invitation)
  assert_equal(3, screen.instance_variable_get(:@view_revision), 'Missing cached view discarded the unadmitted refresh')
  free_capacity.call
  screen.send(:update_invitation)
  wait_background_work(work)
  screen.send(:update_invitation)
  assert_equal(4, screen.instance_variable_get(:@view_revision))
  assert_equal(value, rendered.last)
  3.times { screen.send(:update_invitation) }
  assert_equal(1, calls.size, 'Unchanged accepted refresh was submitted again')
end
puts 'PASS maintained legacy proposal-screen admission: unchanged native4+128 capacity, pending revision retained, cached presentation remains local, exactly one admitted refresh'
