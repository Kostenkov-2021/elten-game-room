# frozen_string_literal: true
ENV['ELTEN_TEST_NATIVE_CONTROLS'] = '1'
require_relative '../support/binary_rules_load'
require_relative '../support/tournament_control_callbacks'
require_relative '../support/tournament_public_service'
require_relative '../../lib/tournaments/public_service'
require_relative '../../lib/tournaments/public_preview'
include GameRoomTest::Assertions
include TournamentPublicServiceSupport
T = GameRoomTournaments
GameRoomLocalization.boot(settings: {'interface_language'=>'en','known_languages'=>['en']})

sandbox do |organizer|
  account = TournamentPublicServiceSupport::Context.new(organizer.directory, 'Alpha')
  owner, player = organizer.service, account.service
  base = draft('mille_bornes').merge('players_per_match'=>4)
  owner.publish(**params('mille_bornes', draft:base, timezone:'local_test:system'))
  row = player.list.fetch('announcements').first
  player.join(tournament_id:row.fetch('__id'))
  snapshot = player.list
  preview = T::PublicPreview.new(program:Object.new, registry:GameRoomGames::CATALOG,
    publication:snapshot.fetch('announcements').first, snapshot:snapshot,
    load:-> { player.list }, mode_label:'Shared tournaments', actor:'Alpha',
    clock:-> {150}, set_partner:->(*) { raise 'No partner mutation was requested' },
    join:->(*) { raise 'No registration was requested' }, alert:->(message) { raise message })
  driver = TournamentControlCallbacks.new
  driver.step(/Registration open/) do |form|
    assert(form.is_a?(EltenAPI::Controls::Form), 'Preview is not the native form')
    assert(!preview.instance_variable_get(:@action_keys).include?(:partner), 'Individual tournament offers a team partner')
    [2, 0, 2].each_with_index do |teams, index|
      revised = base.merge('game_options'=>base.fetch('game_options').merge('team_count'=>teams))
      result = owner.edit_tournament(tournament_id:row.fetch('__id'),
        **params('mille_bornes', draft:revised, intent_id:"preview-team-edit-#{index}", timezone:'local_test:system'))
      assert_equal('confirmed', result.fetch('status'))
      preview.send(:refresh_snapshot)
      assert(preview.snapshot.fetch('members').any? { |person| person['account']=='alpha' }, 'Confirmed edit lost the existing member')
      assert_equal(teams==2, preview.instance_variable_get(:@action_keys).include?(:partner),
        'Partner action must follow the current confirmed game options in the same open preview')
    end
    form.cancel_button.press
  end
  preview.wait
  driver.finish
end
puts 'PASS native preview follows confirmed individual/pair edits in both directions without reopening or mutating a partner'
