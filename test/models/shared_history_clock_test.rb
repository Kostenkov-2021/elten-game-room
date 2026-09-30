require_relative "../support/native_live_sessions"

def at_wall(stamp)
  previous = Time.method(:now)
  Time.define_singleton_method(:now) { Time.at(stamp) }
  yield
ensure
  Time.define_singleton_method(:now, previous)
end

failures = []
[-7200, 7200].product([false, true], [false, true]).each do |skew, timestamp_in_ack, callback_first|
  broker = NativeLiveSessionsBroker.new
  broker.automatic_delivery = false
  stores = %w[Alice Bob].to_h { |user| [user, GameRoomLiveSessionStore.new(ProgramDouble.new(broker.endpoint(user)))] }
  table = stores["Alice"].create_room(name: "Clock", game: "makao", owner: "Alice", game_options: "{}")
  stores["Bob"].join_room(table, "Bob")
  broker.deliver
  core = broker.cores.values.first
  server_now = 1_800_000_000
  core.views.each do |view|
    original = view.method(:stack_push)
    view.define_singleton_method(:stack_push) do |packet, **arguments|
      response = at_wall(server_now) { original.call(packet, **arguments) }
      broker.deliver(duplicate: true) if callback_first
      timestamp_in_ack ? response.merge("entry" => response["entry"].merge("created_at" => server_now)) : response
    end
  end
  ["Alice", "Bob", "Alice"].each_with_index do |user, index|
    server_now += 1
    at_wall(server_now + (user == "Alice" ? skew : 0)) do
      stores[user].append_activity(table: table, kind: "chat", actor: user, message: "message #{index + 1}")
    end
  end
  broker.deliver(duplicate: true)
  projected = stores.transform_values do |store|
    proxy = Object.new
    proxy.define_singleton_method(:live_store?) { true }
    proxy.define_singleton_method(:activity_records) { |row| store.activity_records(row) }
    repository = TableActivityRepository.new(server_tables: nil, transport: proxy)
    repository.entries_for(table).select { |e| e.kind == "chat" }.map { |e| [e.message, e.created_at] }
  end
  expected = (1..3).map { |n| ["message #{n}", 1_800_000_000 + n] }
  failures << {skew: skew, ack_time: timestamp_in_ack, callback_first: callback_first, clients: projected} unless projected.values.all? { |rows| rows == expected }
end
raise "Client histories/timestamps differ: #{failures.inspect}" unless failures.empty?
puts "PASS shared history: +/-2h, before/after acknowledgement, full/minimal acknowledgement, duplicate callbacks"

require_relative "../../lib/game_screen"
broker = NativeLiveSessionsBroker.new
broker.automatic_delivery = false
changes = []
store = GameRoomLiveSessionStore.new(ProgramDouble.new(broker.endpoint("Alice")), changed: ->(*change) { changes << change })
store.instance_variable_set(:@record_clock,GameRoomSessionClock.new(sample: -> { 900 },elapsed: -> { 0 },wall: -> { 777 }))
table = store.create_room(name:"Mixed history",game:"makao",owner:"Alice",game_options:"{}")
guest = GameRoomLiveSessionStore.new(ProgramDouble.new(broker.endpoint("Bob")))
guest.join_room(table,"Bob")
session = store.start_game(table:table,game:"makao",players:%w[Alice Bob],options:"{}",actor:"Alice")
broker.deliver
session = store.game_session(session["__id"],table:table)
$game_room_test_user = 'Alice'
store.append_game_action(session:session,sequence:1,events:[{action:"draw",value:""},{action:"pass",value:""}],actor:"Alice")
events_before = store.game_events(session)
session_before = store.game_session(session["__id"],table:table)
core = broker.cores.values.first
core.entries.last["created_at"] = 1000
changes.clear
broker.deliver(duplicate:true)
session_after = store.game_session(session["__id"],table:table)
assert(session_after["__clock_revision"] > session_before["__clock_revision"],"game timestamp correction did not invalidate cached view")
assert(changes.count { |e| e[1]==:game }==1,"clock correction was lost or announced twice")
proxy = Object.new
proxy.define_singleton_method(:live_store?) { true }
proxy.define_singleton_method(:find_game_session) { |row, **options, &predicate| store.find_game_session(row, **options, &predicate) }
proxy.define_singleton_method(:game_session) { |id,table:| store.game_session(id,table:table) }
proxy.define_singleton_method(:game_events) { |row,**_| store.game_events(row) }
repo = GameRepository.new(nil,transport:proxy,server_tables:{})
screen = GameScreen.allocate
screen.instance_variable_set(:@repository,repo)
screen.instance_variable_set(:@table,table)
screen.instance_variable_set(:@session,session_before)
assert(screen.send(:remote_game_update,repo.events_revision(events_before))==[:refresh,nil],"same-ID metadata update did not refresh actual GameScreen")
assert(repo.events_revision(events_before)==repo.events_revision(store.game_events(session)),"metadata changed action IDs or counts")

# Restored events have old IDs and no native stack sequence; they precede the
# new session. Commands in one packet retain their own order, not wall time.
repo = TableActivityRepository.new(server_tables:nil)
history_item = Struct.new(:event_id,:text)
game_events = [{"id"=>999_999,"created_at"=>5000},
  {"id"=>1_000_201,"__stack_sequence"=>2,"created_at"=>9000},
  {"id"=>1_000_202,"__stack_sequence"=>2,"created_at"=>9000},
  {"id"=>1_000_401,"__stack_sequence"=>4,"created_at"=>1000}]
items = game_events.each_with_index.map { |e,i| history_item.new(e["id"],"game#{i}") }
chat = TableActivityRepository::Entry.new(id:3,kind:"chat",actor:"Bob",message:"chat",created_at:20000,stack_sequence:3)
texts = repo.merged_history_entries(game_entries:items,game_events:game_events,activity_entries:[chat],game_name:->(_) { "Makao" }).map(&:text)
assert(texts==["game0","game1","game2","Bob: chat","game3"],"mixed/restored history followed timestamps or incomparable IDs: #{texts.inspect}")
archived = [{"id"=>1,"created_at"=>9000,"move_id"=>"archive:a:1"},
  {"id"=>2,"created_at"=>1000,"move_id"=>"archive:a:2"}]
texts = repo.merge_history(game_entries:[history_item.new(1,"first"),history_item.new(2,"second")],
  game_events:archived,activity_entries:[],game_name:->(_) { "Makao" })
assert(texts==%w[first second],"an archive without new events reverted to wall-clock ordering")
puts "PASS same-ID correction refreshes GameScreen once; mixed game/chat/restored history follows stack order"
