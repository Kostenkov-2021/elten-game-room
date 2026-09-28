require_relative "support/settings_widget"

games = %w[uno makao]
old = { "widget_games" => ["uno"], "widget_known_games" => games, "invitation_notifications" => "contacts" }
values = GameRoomPreferences.normalize(old, games)
assert(!values["widget_contacts_only"] && !values["table_watch_contacts_only"], "existing settings silently enabled the new filters")
assert(values["widget_games"] == ["uno"] && values["invitation_notifications"] == "contacts", "migration reset existing choices")
both = GameRoomPreferences.normalize(old.merge("widget_contacts_only" => true, "table_watch_contacts_only" => true), games)
assert(both.values_at("widget_contacts_only", "table_watch_contacts_only") == [true, true], "enabled filters not persisted")

worker, names, loads = WidgetManualWorker.new, ["Bob"], 0
cache = GameRoomContacts::Cache.new(user: "Alice", worker: worker, loader: -> { names })
EltenGameRoom.contacts_stop
EltenGameRoom.instance_variable_set(:@contacts_cache, cache)
settings = values.merge("widget_contacts_only" => true)
rows = [WidgetSnapshot.new(table: { "__id" => 1, "game" => "uno", "owner" => "Bob" }),
  WidgetSnapshot.new(table: { "__id" => 2, "game" => "uno", "owner" => "Eve" }),
  WidgetSnapshot.new(table: { "__id" => 3, "game" => "makao", "owner" => "Bob" }),
  WidgetSnapshot.new(table: { "__id" => 4, "game" => "uno", "owner" => "Alice" })]
app = EltenGameRoom.allocate
lobby, transport = Object.new, Object.new
lobby.define_singleton_method(:open_table_snapshots) do |hide_inactive: false|
  assert(hide_inactive, 'Widget did not request the public-list inactivity filter')
  loads += 1
  rows
end
lobby.define_singleton_method(:owner_of) { |row| row["owner"] }
transport.define_singleton_method(:start) { }
app.instance_variable_set(:@transport, transport)
app.instance_variable_set(:@lobby, lobby)
app.define_singleton_method(:initialize_services) { }
app.define_singleton_method(:widget_table_available?) { |_row| true }
app.define_singleton_method(:game_room_settings) { |reload: false| settings }
assert(app.send(:load_widget_table_snapshots).is_a?(GameRoomWidget::Loading) && loads == 0, "cold filter pretended to have no tables or waited for contacts")
worker.finish
assert(app.send(:load_widget_table_snapshots) == [rows[0]], "widget did not intersect owners with selected games")
names = ["Eve"]
cache.snapshot(force: true)
assert(app.send(:load_widget_table_snapshots).is_a?(GameRoomWidget::Loading), "R reused old contacts")
worker.finish
assert(app.send(:load_widget_table_snapshots) == [rows[1]], "R did not update contact add/remove")
settings = settings.merge("widget_contacts_only" => false)
assert(app.send(:load_widget_table_snapshots) == [rows[0], rows[1], rows[3]], "disabled contact filter changed ordinary widget behavior")

# A delayed filter uses a truthful loading label, then reads one actual result.
widget_worker = WidgetManualWorker.new
active, now, manual = true, 0.0, 0
loaded = GameRoomWidget::Loading.new("Loading contacts")
widget = GameRoomWidget::TableList.new(loader: -> { loaded }, opener: ->(_) {},
  labeler: ->(r) { r.table["owner"] }, id_for: ->(r) { r.table["__id"] },
  active: -> { active }, clock: -> { now }, worker: widget_worker, manual_refresh: -> { manual += 1 })
widget.focus
assert(widget.empty_label == "Loading contacts" && widget.options.empty?, "unknown contacts displayed false no-tables message")
loaded = [rows[0]]
now = 5
widget.update
widget_worker.finish
widget.update
assert(widget.options == ["Bob"] && widget.sayoption_count == 1, "first filtered result was not read exactly once")
100.times { widget.focus if false; widget.update }
assert(manual == 0 && !widget_worker.busy?, "navigation forced contacts refresh")
$game_room_widget_r = true
widget.update
$game_room_widget_r = false
assert(manual == 1 && widget_worker.busy?, "R did not request contacts and widget refresh")
widget_worker.finish
widget.update
active = false
now += 100
widget.update
assert(!widget_worker.busy?, "inactive widget polled")
EltenGameRoom.contacts_stop
puts "PASS widget contact filters: opt-in migration, game/owner intersection, pending versus empty, fresh R, one first read, inactive/arrow behavior"
