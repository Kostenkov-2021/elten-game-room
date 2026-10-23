if ARGV.first
  previous=ENV['ELTEN_TEST_NATIVE_CONTROLS']
  begin
    ENV['ELTEN_TEST_NATIVE_CONTROLS']='1'
    require_relative '../support/binary_rules_load'
  ensure
    ENV['ELTEN_TEST_NATIVE_CONTROLS']=previous
  end
end
require_relative '../support/tournament_native'
require_relative '../support/tournament_entry_context'
require_relative '../support/tournament_public_ui'
require_relative '../../lib/tournaments/public_preview'

GameRoomLocalization.boot(settings:{'interface_language'=>'en','known_languages'=>['en']})
u=TournamentPublicUI
program=TournamentEntryContextTest::Program.new
start=Time.utc(2026,10,15,18).to_i
ending=Time.utc(2026,10,15,21).to_i
cases=[
  [:opens,99,100,'Registration open',true],
  [:closes,199,200,'Waiting for tournament start',false],
  [:starts,start-1,start,'Tournament in progress',false],
  [:deadline,ending-1,ending,'Deadline passed',false],
  [:retention,150,151,'',false]
]
begin
  cases.each do |name,initial,boundary,label,expected_join|
    now=initial
    reads=0
    snapshot=u.snapshot
    if name==:retention
      snapshot=Marshal.load(Marshal.dump(snapshot))
      snapshot['announcements'].first['expires_at']=boundary
    end
    parent=nil
    speech=nil
    key='Information and rules'
    driver=TournamentNativeDriver.new
    driver.step(/\APróba 11 — Łódź — /) do |form|
      parent=form
      list=form.fields.first
      list.index=list.options.index(key)
      assert(list.index,"#{name}: rules action missing")
      timer=form.instance_variable_get(:@timers).first
      assert(timer,"#{name}: missing native boundary timer")
      now=boundary
      timer.instance_variable_set(:@monotonic_starttime,Process.clock_gettime(Process::CLOCK_MONOTONIC)-2)
      speech=[SpeechOutput.calls.size,NVDA.calls.size]
    end
    driver.step(/\APróba 11 — Łódź — /) do |form|
      list=form.fields.first
      assert_equal(expected_join,list.options.include?('Join tournament'),"#{name}: stale membership action")
      if name==:retention
        assert_equal(['Refresh'],list.options,'Expired publication kept its old actions')
        assert_equal(1,reads,'Expiry must refresh once, not silently retain an expired source')
      else
        assert(list.header.include?(label),"#{name}: stale phase header #{list.header}")
        assert_equal(key,list.options[list.index],"#{name}: action identity moved")
        assert_equal(0,reads,"#{name}: local clock boundary polled the backend")
        assert_equal(speech,[SpeechOutput.calls.size,NVDA.calls.size],"#{name}: refresh announced or refocused the list")
        assert_equal(name==:deadline ? 0 : 1,form.instance_variable_get(:@timers).size,"#{name}: timers accumulated")
      end
      assert_equal(0,form.index,"#{name}: field focus moved")
    end
    driver.step(/\APróba 11 — Łódź — /,[27]){}
    GameRoomTournaments::PublicPreview.new(**u.arguments(snapshot,program:program,clock:->{now},
      load:->{reads+=1; name==:retention ? u.snapshot([]) : snapshot})).wait
    driver.finish
    assert_equal([],parent.instance_variable_get(:@timers),"#{name}: closed dashboard retained its callback")
  end
ensure
  program.finalize
  program.class.app_runtime.close
end
puts 'PASS native tournament dashboard: open/close/start/deadline/retention boundaries, stable silent focus, no polling and timer cleanup'
