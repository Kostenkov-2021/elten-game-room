require_relative '../support/tournament_individual_ui'
require_relative '../../lib/tournaments/partner_choice'
include GameRoomTest::Assertions
I = TournamentIndividualUI
F = I::F
T = GameRoomTournaments
GameRoomLocalization.boot(settings: {'interface_language' => 'pl', 'known_languages' => ['pl']})
label = ->(value) { GameRoomContent.utf8(GameRoomLocalization.translate(value)) }
state = I.fixture(names: %w[Alpha Beta Gamma Delta], game: 'spades',
  game_options: {'team_size' => 2}, players_per_match: 4)
state[:now] = 150
alerts = []
factory = ->(actor) do
  T::LocalWorkspace.new(program: state[:program], registry: GameRoomGames::CATALOG,
    user: -> { F::OWNER }, actor: actor, alert: ->(message) { raise message }, clock: -> { state[:now] })
end
workspace = factory.call('Delta')
publication = workspace.load['announcements'].first
id = publication['__id']
act = lambda do |actor, action, partner, key, intent|
  state[:actor] = actor
  gateway = T::TablesGateway.new(server_tables: state[:tables], user: -> { state[:actor] },
    operation_error_classes: [T::LocalTestTables::Error])
  service = T::PublicService.new(gateway: gateway, journal: state[:journal].call,
    registry: GameRoomGames::CATALOG, user: -> { state[:actor] },
    backend_identity: state[:tables].backend_identity, clock: -> { state[:now] })
  service.partnership_action(tournament_id: id, action: action, partner: partner, request_key: key, intent_id: intent)
end
request = act.call('Gamma', 'request', 'Delta', nil, 'gamma-request')
key = request.dig('values', 'operation_key')
act.call('Alpha', 'request', 'Beta', nil, 'alpha-request')
original_insert = state[:tables].method(:insert_row)
injected = false
state[:tables].define_singleton_method(:insert_row) do |table, row|
  if !injected && table == 'tournament_registrations' && row['kind'] == 'partnership' && row['account'] == 'delta'
    injected = true
    act.call('Gamma', 'cancel', nil, key, 'gamma-cancel')
    alpha_key = workspace.load['pair_requests'].find { |item| item['from'] == 'alpha' }['key']
    act.call('Beta', 'accept', 'Alpha', alpha_key, 'beta-accept')
    state[:actor] = 'Delta'
  end
  original_insert.call(table, row)
end
driver = TournamentNativeDriver.new
driver.step(label.call('Team'), [13]) do |form|
  list = F.field(form, label.call('Partner'))
  list.index = list.options.index(label.call('Accept partnership with %{player}') % {player: 'Gamma'})
  assert(list.index, 'The current incoming request must be selectable before the write races')
  form.index = form.fields.index(list)
end
T::PartnerChoice.new(program: state[:program], publication: publication, account: 'Delta',
  load: workspace.method(:load), choose: nil,
  action: ->(_id, action, partner, key, intent) { act.call('Delta', action, partner, key, intent) },
  alert: ->(message) { alerts << message }, confirm: ->(*) { true }).run
driver.finish
assert(injected, "The request must be cancelled between validation and the tested insert: #{alerts.inspect}")
assert_equal([%w[alpha beta]], workspace.load['pairs'].map { |row| row['accounts'] })
assert(alerts.include?(label.call('The tournament changed. Refresh and choose the action again.')),
  'A durable but ignored acceptance must report stale state')
assert(!alerts.include?(label.call('Partner choice saved.')), 'No false acceptance success')
state[:program].finalize
state[:program].class.app_runtime.close
puts 'PASS native exact-request acceptance race: cancelled request is not revived and a durable ignored write reports stale state'
