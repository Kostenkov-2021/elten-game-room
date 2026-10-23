# frozen_string_literal: true
ENV['ELTEN_TEST_NATIVE_CONTROLS'] = '1'
require 'json'
require_relative '../support/temporary_directory'
require_relative '../support/binary_rules_load'
require_relative '../support/tournament_control_callbacks'
require_relative '../support/tournament_public_ui'
require_relative '../support/tournament_public_service'
require_relative '../../lib/tournaments/public_service'
require_relative '../../lib/tournaments/participant_manager'
require_relative '../../lib/tournaments/local_participant_manager'
include GameRoomTest::Assertions
include TournamentPublicServiceSupport
T = GameRoomTournaments
GameRoomLocalization.boot(settings: {'interface_language'=>'en','known_languages'=>['en']})

outcomes = []
[:public, :local].each do |kind|
  [:confirmed, :uncertain].each do |outcome|
    directory = GameRoomTest::TemporaryDirectory.create('participant-epoch-')
    c = TournamentPublicServiceSupport::Context.new(directory)
    organizer = c.actor.dup
    service = c.service
    service.publish(**params(timezone:'local_test:system'))
    row = service.list.fetch('announcements').first
    c.actor = 'Alpha'
    player = c.service(journal:c.reopen_journal)
    first_join = player.join(tournament_id:row.fetch('__id'))
    c.actor = organizer
    calls, alerts, statuses = [], [], []
    workspace = Object.new
    workspace.define_singleton_method(:registry) { GameRoomGames::CATALOG }
    workspace.define_singleton_method(:load) { service.list }
    workspace.define_singleton_method(:remove_participant) do |id, account|
      calls << [id, account]
      if outcome == :uncertain
        c.after_insert = ->(_table, values, _id) { raise IOError, 'ACK deliberately lost' if values['kind'] == 'removal' }
      end
      begin
        result = service.remove_participant(tournament_id:id,account:account)
        statuses << result['status']
        result
      rescue T::TablesGateway::UnconfirmedWrite
        statuses << 'unconfirmed'
        nil
      ensure
        c.after_insert = nil
      end
    end
    type = kind == :public ? T::ParticipantManager : T::LocalParticipantManager
    owner_type = kind == :public ? T::Dialogs::Owner : T::LocalTestDialogs::Owner
    owner = owner_type.new(-> {c.actor}, ->(message) {raise message})
    arguments = {program:Object.new,workspace:workspace,owner:owner,publication:row,
      confirm:->(*) {true},alert:->(message) {alerts << message}}
    arguments[:clock] = -> {150} if kind == :public
    manager = type.new(**arguments)
    driver = TournamentControlCallbacks.new
    second_join = nil
    header = kind == :public ? 'Participants' : 'Registered participants'
    driver.step(header) do |form|
      assert(form.is_a?(EltenAPI::Controls::Form), 'Proof did not reach native Form')
      assert(form.fields.first.is_a?(EltenAPI::Controls::ListBox), 'Proof did not reach native participant list')
      kind == :public ? manager.send(:execute,:remove) : manager.send(:remove_selected)
      assert_equal([],service.list['members'],'First removal was not accepted by the real projection')
      c.actor = 'Alpha'
      second_join = player.join(tournament_id:row.fetch('__id'))
      c.actor = organizer
      kind == :public ? manager.send(:execute,:refresh) : manager.send(:refresh_members)
      assert_equal(['Alpha'],form.fields.first.options,'Rejoined member missing from actual projected UI')
      form.fields.first.index = 0
      kind == :public ? manager.send(:execute,:remove) : manager.send(:remove_selected)
      form.cancel_button.press
    end
    manager.run
    driver.finish
    after_ui = service.list['members'].map { |member| member.slice('account','registration_id') }
    before_direct = c.inserts.size
    direct = outcome == :confirmed ? service.remove_participant(tournament_id:row.fetch('__id'),account:'alpha') : nil
    journal = c.journal.list.select { |record| record['kind']=='removal' }
    outcomes << {manager:kind,outcome:outcome,native_manager_calls:calls.size,statuses:statuses,
      first_join:first_join.dig('evidence','record_ids'),second_join:second_join.dig('evidence','record_ids'),
      members_after_ui:after_ui,alerts:alerts,remove_intents:journal.map { |record| record.slice('intent_id','status') },
      direct_followup_status:direct&.fetch('status'),direct_new_insert_count:c.inserts.size-before_direct,
      directory:directory}
  end
end
puts JSON.pretty_generate({cases:outcomes,
  fidelity:'Real PublicService, authenticated file-backed LocalTestTables, OperationJournal and RegistrationProjection; native public/local manager Forms/callbacks. No server or live accounts.'})
assert(outcomes.select { |row| row[:outcome]==:uncertain }.all? { |row| row[:native_manager_calls]==1 },
  'An uncertain manager removal was blindly retried')
assert(outcomes.select { |row| row[:outcome]==:confirmed }.all? { |row| row[:direct_followup_status]=='confirmed' && row[:direct_new_insert_count]==0 && row[:remove_intents].size==2 },
  'Confirmed next epoch was not idempotent after the second native removal')
assert(outcomes.select { |row| row[:outcome]==:confirmed }.all? { |row| row[:native_manager_calls]==2 },
  'Confirmed removal latch prevents removing a freshly rejoined participant in the same manager')



assert(outcomes.select { |row| row[:outcome]==:confirmed }.all? { |row| row[:members_after_ui].empty? }, 'Second native removal left a member registered')
puts 'PASS confirmed removal/rejoin/removal in both native managers; lost-ACK attempts stay blocked'
