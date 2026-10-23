# frozen_string_literal: true
ENV['ELTEN_TEST_NATIVE_CONTROLS'] = '1'
require 'json'
require_relative '../support/temporary_directory'
require_relative '../support/binary_rules_load'
require_relative '../support/tournament_control_callbacks'
require_relative '../support/tournament_public_ui'
require_relative '../support/tournament_public_service'
require_relative '../../lib/tournaments/public_service'
require_relative '../../lib/tournaments/public_preview'
include GameRoomTest::Assertions
include TournamentPublicServiceSupport
T = GameRoomTournaments
GameRoomLocalization.boot(settings: {'interface_language'=>'en','known_languages'=>['en']})
rows = []
[:join_then_removed, :withdraw_then_peer_rejoins].each do |mode|
  directory = GameRoomTest::TemporaryDirectory.create('preview-membership-')
  organizer = TournamentPublicServiceSupport::Context.new(directory, 'Organizer')
  account = TournamentPublicServiceSupport::Context.new(directory, 'Alpha')
  org, player = organizer.service, account.service
  org.publish(**params(timezone:'local_test:system'))
  row = player.list.fetch('announcements').first
  player.join(tournament_id:row.fetch('__id')) if mode == :withdraw_then_peer_rejoins
  calls, alerts = {join:0,withdraw:0}, []
  preview = T::PublicPreview.new(program:Object.new,registry:GameRoomGames::CATALOG,publication:row,
    snapshot:player.list,load:-> {player.list},mode_label:'Shared tournaments',actor:'Alpha',clock:-> {150},
    join:->(id) {calls[:join]+=1;player.join(tournament_id:id)},
    withdraw:->(id) {calls[:withdraw]+=1;player.withdraw(tournament_id:id)},alert:->(message) {alerts << message})
  driver = TournamentControlCallbacks.new
  driver.step(/Registration open/) do |form|
    assert(form.is_a?(EltenAPI::Controls::Form) && form.fields.first.is_a?(EltenAPI::Controls::ListBox),'Non-native preview')
    preview.send(:execute_action, mode == :join_then_removed ? :join : :withdraw)
    if mode == :join_then_removed
      org.remove_participant(tournament_id:row.fetch('__id'),account:'Alpha')
    else
      account.service(journal:account.reopen_journal).join(tournament_id:row.fetch('__id'))
    end
    preview.send(:refresh_snapshot)
    action = mode == :join_then_removed ? :join : :withdraw
    offered = preview.instance_variable_get(:@action_keys).dup
    assert(offered.include?(action), 'The next valid membership action is missing from the native action list')
    before = account.inserts.size
    preview.send(:execute_action,action)
    after = account.inserts.size
    members = player.list['members'].map { |person| person.slice('account','registration_id') }
    direct = action == :join ? player.join(tournament_id:row.fetch('__id')) : player.withdraw(tournament_id:row.fetch('__id'))
    rows << {mode:mode,offered_actions:offered,ui_calls:calls.dup,ui_new_inserts:after-before,
      members_after_ui:members,direct_status:direct['status'],direct_new_inserts:account.inserts.size-after,
      alerts:alerts.dup,directory:directory}
    form.cancel_button.press
  end
  preview.wait
  driver.finish
end
puts JSON.pretty_generate({cases:rows,
  fidelity:'Native PublicPreview plus real PublicService/journal/registration projection. Independent fixed-account contexts share authenticated local table files. No live accounts/network.'})
assert(rows.all? { |row| row[:direct_status]=='confirmed' && row[:direct_new_inserts]==0 },'Completed native membership operation was not idempotent at service readback')
assert(rows.all? { |row| row[:ui_new_inserts]==1 },'Confirmed membership latch blocks a later valid epoch in the same preview')



puts 'PASS native preview join/remove/rejoin and withdrawal/peer rejoin/withdrawal through actual service epochs'
