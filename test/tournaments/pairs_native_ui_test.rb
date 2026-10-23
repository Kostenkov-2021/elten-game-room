require_relative '../support/tournament_individual_ui'
require_relative '../../lib/tournaments/participant_manager'
require_relative '../../lib/tournaments/public_preview'
include GameRoomTest::Assertions
I=TournamentIndividualUI
F=I::F
T=GameRoomTournaments
GameRoomLocalization.boot(settings:{'interface_language'=>'pl','known_languages'=>['pl']})
label=->(s){GameRoomContent.utf8(GameRoomLocalization.translate(s))}
state=I.fixture(names:%w[Alpha Beta Gamma Delta],game:'spades',game_options:{'team_size'=>2},players_per_match:4)
factory=->(actor){T::LocalWorkspace.new(program:state[:program],registry:GameRoomGames::CATALOG,
  user:-> {F::OWNER},actor:actor,alert:->(m){raise m},clock:-> {state[:now]})}
workspace=factory.call('Organizator')
id=workspace.load['announcements'].first['__id']
factory.call('Alpha').set_partner(id,'Alpha','Beta','request')
factory.call('Beta').set_partner(id,'Beta','Alpha','accept')
owner=T::Dialogs::Owner.new(-> {'Organizator'},->(m){raise m})
opened=[]
state[:program].define_singleton_method(:usermenu){|name|opened<<name}
driver=TournamentNativeDriver.new
driver.step(label.call('Participants'),[13]) do |form|
  assert_equal(['Alpha, Beta','Delta','Gamma'],form.fields.first.options)
  assert_equal(1,form.fields.count{|field|field.is_a?(ListBox)},'Participants gained another list under Tab')
  form.index=0
end
driver.step(label.call('Team members'),[13]) do |form|
  assert_equal(%w[Alpha Beta],form.fields.first.options)
  form.fields.first.index=1
  form.index=0
end
driver.step(label.call('Team members'),[27]) do |_form|
  assert_equal(['Beta'],opened,'Team row was treated as a synthetic native user')
end
driver.step(label.call('Participants'),[13]) do |form|
  assert_equal(0,form.fields.first.index,'Returning from team members lost the selected team')
  form.fields.first.index=2
  form.index=0
end
driver.step(label.call('Participants'),[27]) do |_form|
  assert_equal(%w[Beta Gamma],opened,'Unpaired entrant did not open the native user menu')
end
T::ParticipantManager.new(program:state[:program],workspace:workspace,owner:owner,
  publication:workspace.load['announcements'].first,confirm:->(*){true},alert:->(*){},clock:-> {state[:now]}).run
driver.finish
gamma=factory.call('Gamma')
gamma.partnership_action(id,'request','Delta',nil,'incoming-for-notification')
delta=factory.call('Delta')
driver=TournamentNativeDriver.new
driver.step(label.call('Team'),[27]) do |form|
  list=F.field(form,label.call('Partner'))
  assert(list.options.include?(label.call('Accept partnership with %{player}')%{player:'Gamma'}),
    'Opening the partnership notice did not reach the current incoming proposal')
end
driver.step(/\AIndividual UI — /,[27])
T::PublicPreview.new(program:state[:program],registry:GameRoomGames::CATALOG,
  publication:delta.load['announcements'].first,snapshot:delta.load,load:delta.method(:load),
  join:delta.method(:join),actor:'Delta',mode_label:delta.mode_label,initial_action: :partner,
  set_partner:delta.method(:set_partner),partner_action:delta.method(:partnership_action),
  alert:->(message){raise message},clock:-> {state[:now]}).wait
driver.finish
assert_equal(['delta'],delta.load['pair_requests'].map{|request|request['to']},
  'Opening a partnership notification silently accepted it')
state[:program].finalize
state[:program].class.app_runtime.close
puts 'PASS native grouped Participants: one list, team once, unpaired entrants, member user menu and stable return focus'
