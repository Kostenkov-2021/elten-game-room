require_relative "../support/widget"
require_relative "../../games/uno"
worker = WidgetManualWorker.new
row = WidgetSnapshot.new(table: {"__id" => 5})
selected, active, calls, said = row, true, 0, []
game = GameRoomGames::Uno.new
value = {status: :ready, game: "uno", options: JSON.generate(game.default_options.merge("interceptions" => true))}
reader = GameRoomTableOptionsReader.new(loader: ->(_) { calls += 1; value }, selected: -> {selected},
  id_for: ->(s) {s.table["__id"]}, active: -> {active}, speaker: ->(s) {said << s},
  game_for: ->(_) {game}, worker: worker)
assert(calls == 0, "reader fetched without shortcut")
assert(reader.request && !reader.request && calls == 0, "blocking fetch or duplicate request")
worker.finish; reader.update
assert(said == [game.table_options_announcement(game.options_from_json(value[:options]))], "different Ctrl+R text")
reader.request; reader.invalidate; worker.finish; reader.update
assert(said.length == 1, "stale settings read after movement")
reader.request; active = false; worker.finish; reader.update
assert(said.length == 1, "settings read over another field")
active = true; value = {status: :closed}; reader.request; worker.finish; reader.update
assert(said.last.include?("no longer available"), "gone table became default settings")
value = {status: :unavailable}; reader.request; worker.finish; reader.update
assert(said.last.include?("not available"), "missing settings guessed")
selected = nil; reader.request
assert(said.last == "No table selected.", "empty list unclear")
reader.close
puts "PASS Ctrl+R details reader: explicit async lookup, same in-table description, generation/focus/closed guards"
