require_relative '../support/binary_rules_load' if ARGV.first
require_relative '../support/tournament_local_workspace'
require_relative '../support/host_source'
require EltenTestHost.file('src/eltenlink/error.rb')
require_relative '../../lib/tournaments/server_workspace'
include TournamentLocalWorkspaceSupport
include GameRoomTest::Assertions
T = GameRoomTournaments

sandbox do |c|
  tables = T::LocalTestTables.new(directory: File.join(c.directory, 'sdk-double'),
    user: -> { c.user }, clock: -> { c.now })
  build = -> do
    T::ServerWorkspace.new(program: c.program, registry: GameRoomGames::CATALOG,
      user: -> { c.user }, alert: ->(message) {
        assert_equal(c.ui_thread, Thread.current, 'Capacity feedback must remain on the UI thread')
        c.alerts << message
      }, clock: -> { c.now }, provider_factory: -> { tables })
  end
  owner = build.call
  values = params(timezone: 'UTC')
  values[:draft] = values[:draft].merge('participant_limit' => 2)
  publication = owner.publish(**values)
  assert_equal('confirmed', publication['status'])
  id = publication['evidence']['canonical_id']
  c.user = 'Second'
  assert_equal('confirmed', build.call.join(id)['status'])
  assert_equal([], c.alerts)

  c.user = 'Third'
  excess = build.call
  assert_equal(nil, excess.join(id))
  assert_equal(:participant_limit_reached, excess.last_error.code)
  assert_equal(['The tournament is full.'], c.alerts)
  assert_equal([], excess.operations, 'Refused enrollment must not prepare a write')

  c.user = 'RealOwner'
  c.alerts.clear
  operations = owner.operations
  assert_equal(nil, owner.invite_to_tournament(id, 'Fourth', 'capacity-feedback-invitation'))
  assert_equal(:participant_limit_reached, owner.last_error.code)
  assert_equal(['The tournament is full.'], c.alerts)
  assert_equal(operations, owner.operations, 'Refused invitation must not prepare or append a write')
  assert_equal(2, owner.load['members'].size)
  assert_equal([], owner.load.fetch('invitations', []))
end
puts 'PASS official workspace capacity feedback for excess enrollment and invitation; no attempted write'
