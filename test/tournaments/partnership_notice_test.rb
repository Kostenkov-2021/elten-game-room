require_relative '../support/tournament_public_ui'
require_relative '../../lib/tournaments/tournament_event_notice'
require_relative '../../lib/tournaments/tournament_start_publisher'
include GameRoomTest::Assertions
T=GameRoomTournaments
row=TournamentPublicUI.publication(11).merge('__insertion_user'=>'Organizer','__insertion_time'=>100)
reference={'author'=>'organizer','publication_key'=>row['publication_key']}
change={'kind'=>'requested','from'=>'alpha','to'=>'beta','from_name'=>'Alpha','to_name'=>'Beta',
  'author'=>'alpha','time'=>150,'key'=>'proposal-one','request_key'=>'proposal-one','index'=>0}
source={'publication'=>row,'people'=>%w[organizer alpha beta],'members'=>[],
  'pair_requests'=>[{'from'=>'alpha','to'=>'beta','key'=>'proposal-one'}],
  'partner_changes'=>[change], 'usernames'=>{'alpha'=>'Alpha','beta'=>'Beta'}}
scope={'account'=>'alpha','account_epoch'=>'one','backend_identity'=>'test-partners'}
make=-> {T::TournamentEventNotice.new(kind:'partnership',source:->(_ref){source},
  context:-> {scope},clock:-> {160},registry:GameRoomGames::CATALOG)}
service=make.call
notice,name=service.notices(publication_ref:reference,change_key:change['key'],change_index:0,addressed:true).first
assert_equal('Beta',name,'Delivery must preserve authenticated case')
assert_equal('beta',notice['recipient'])
assert_equal('alpha',service.inspect(metadata:notice,sender:'Alpha',delivery:true)['sender'])
scope=scope.merge('account'=>'beta','account_epoch'=>'two')
recipient=make.call
assert(recipient.presentable?(recipient.inspect(metadata:notice,sender:'Alpha')))
assert_raises(T::ProposalNotice::Stale) {recipient.inspect(metadata:notice,sender:'Organizer')}
source['pair_requests']=[]
assert_raises(T::ProposalNotice::Stale) {recipient.inspect(metadata:notice,sender:'Alpha')}
source['pair_requests']=[{'from'=>'alpha','to'=>'beta','key'=>'replacement'}]
assert_raises(T::ProposalNotice::Stale) {recipient.inspect(metadata:notice,sender:'Alpha')}
change=change.merge('kind'=>'established','author'=>'beta','key'=>'accepted','time'=>155)
source['partner_changes']=[change]
scope=scope.merge('account'=>'beta','account_epoch'=>'three')
service=make.call
notices=service.notices(publication_ref:reference,change_key:'accepted',change_index:0)
assert_equal(['alpha'],notices.map{|n|n['recipient']})
state={'version'=>1,'operations'=>{}}
sent=[]
publisher=T::TournamentStartPublisher.new(service:service,sender:-> {'Beta'},
  transaction:->(&block){block.call(state)},send:->(*args){sent<<args;true})
2.times {assert_equal(:sent,publisher.deliver(metadata:notices.first))}
assert_equal(1,sent.size,'Reload/reconciliation may not replay a transition')
change=change.merge('kind'=>'assigned','author'=>'organizer','key'=>'automatic','time'=>156)
source['partner_changes']=[change]
scope=scope.merge('account'=>'organizer','account_epoch'=>'four')
assert_equal(%w[alpha beta],make.call.notices(publication_ref:reference,change_key:'automatic',change_index:0).map{|n|n['recipient']})
puts 'PASS partnership notices: authenticated participant sender, exact proposal, stale rejection, canonical delivery names, both drawn partners and durable deduplication'
