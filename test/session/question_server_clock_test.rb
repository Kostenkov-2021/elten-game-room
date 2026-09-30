if ARGV.delete("--binary")
  require_relative "../support/binary_rules_load"
  BinaryRulesLoad.load(File.expand_path(__FILE__))
  exit
end
unless defined?(BinaryRulesLoad)
  require_relative "../support/ui"
  require_relative "../../lib/game_surfaces"
end
require "json"
require_relative "../support/server_clock"
require_relative "../../lib/game_random"
require_relative "../../lib/hidden_submissions"
require_relative "../../lib/game_content"
require_relative "../../content/languages"
require_relative "../../content/quiz_pl_wikidata"
require_relative "../../games/quiz_party"
require_relative "../../games/categories"

def assert(value,message); raise message unless value; end
class ClockQuestionRepository
  def players_for(_); %w[Alice Bob]; end
  def actor_of(event,_); event.fetch("actor"); end
  def event_id(event); event.fetch("id"); end
end
def append_clock_plan(events,plan,now)
  plan.events.each do |command|
    events << {"id"=>events.length+1,"actor"=>"Alice","action"=>command.action,"value"=>command.value,"created_at"=>now}
  end
end

server = 1_800_000_000
elapsed = 0.0
clock = game_room_test_clock { server + elapsed }
clock.synchronize
GameRoomClock.instance_variable_set(:@clock, clock)
old_wall = Time.method(:now)
begin
  [-7200,7200].product([-86_400,86_400]).each do |founder_skew, local_skew|
    Time.define_singleton_method(:now) { Time.at(server + local_skew) }
    elapsed = 0.0
    game = GameRoomGames::QuizParty.new
    session = {"options"=>JSON.generate(game.normalize_options("answer_time"=>5)),
      "created_at"=>server+founder_skew,"__server_started_at"=>server}
    events, repo = [], ClockQuestionRepository.new
    context = GameRoomGames::ActionContext.new(now:server+founder_skew,session_id:7,table_id:4,
      hidden_submissions:HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
      random_source:GameRoomRandom::SeededSource.new(4242))
    replay = game.replay(session,events,repo)
    status,plan = game.action_for(game.automatic_action(replay,"Alice",context:context),replay,"Alice",context:context)
    assert(status==:ok,"round draw rejected")
    append_clock_plan(events,plan,server)
    replay = game.replay(session,events,repo)
    surface = game.surface_spec(replay,"Alice")
    choice = {"kind"=>"question","action"=>"submit","question_id"=>surface.id,"answer"=>surface.options.first.id}
    status, plan = game.action_for(choice,replay,"Alice",context:context)
    assert(status==:ok,"category rejected")
    append_clock_plan(events,plan,server)
    replay = game.replay(session,events,repo)
    action = game.automatic_action(replay,"Alice",context:context)
    status, plan = game.action_for(action,replay,"Alice",context:context)
    assert(status==:ok,"question could not start")
    append_clock_plan(events,plan,server)
    replay = game.replay(session,events,repo)
    assert(replay.state[:deadline]==server+founder_skew+5,"question deadline used a different epoch")
    assert(game.send(:remaining_time_text,replay.state)==(_("%{seconds} seconds remaining.") % {seconds:5}),"question UI used OS time")
    elapsed = 5.0
    assert(game.send(:remaining_time_text,replay.state)==(_("%{seconds} seconds remaining.") % {seconds:0}),"question UI ignored elapsed time")
    elapsed += game.class::DEADLINE_SUBMISSION_GRACE
    context.now = GameRoomSessionClock.for_state(replay.state).to_i
    assert(game.automatic_action_due?(replay,"Alice",context:context),"answer closing stuck on skewed founder")
    2.times do
      action = game.automatic_action(replay,"Alice",context:context)
      status, plan = game.action_for(action,replay,"Alice",context:context)
      assert(status==:ok,"question closing/finishing rejected")
      append_clock_plan(events,plan,server+elapsed.to_i)
      replay = game.replay(session,events,repo)
    end
    assert(replay.state[:phase]==:starting,"question did not finish")
    assert(replay.state[:resume_at]==context.now+game.class::NEXT_QUESTION_PAUSE,"presentation pause used another epoch")
    assert(!game.automatic_action_due?(replay,"Alice",context:context),"presentation pause skipped")
    elapsed += game.class::NEXT_QUESTION_PAUSE
    context.now = GameRoomSessionClock.for_state(replay.state).to_i
    assert(game.automatic_action_due?(replay,"Alice",context:context),"next question stuck after pause")

    categories = GameRoomGames::Categories.new
    state = GameRoomSessionClock.attach({phase: :answering, deadline:context.now+10},session)
    assert(categories.send(:remaining_time_text,state).include?("10"),"Categories UI used another epoch")
  end
ensure
  Time.define_singleton_method(:now,old_wall)
end
puts "PASS question clocks: +/-2h founder, +/-1 day local clock, deadlines, answer closure, next question pause and Categories remaining time"
