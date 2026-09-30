require_relative "../support/widget"
worker = WidgetManualWorker.new
rows = [WidgetSnapshot.new(table: {'__id'=>1}), WidgetSnapshot.new(table: {'__id'=>2})]
selected, active, calls, said = rows[0], true, 0, []
value = {status: :ready, players: ['Żaneta'], observers: ['Bob']}
reader = GameRoomTableRosterReader.new(loader: ->(_) { calls += 1; value }, selected: -> { selected },
  id_for: ->(s) { s.table['__id'] }, active: -> { active }, speaker: ->(s) { said << s }, worker: worker)
assert(reader.request && !reader.request, 'Duplicate request queued')
worker.finish; reader.update
assert(calls == 1 && said == ['Players: Żaneta. Observers: Bob.'], 'Roster formatting wrong')
reader.request; selected = rows[1]; worker.finish; reader.update
assert(said.size == 1, 'Late reply read for other table')
reader.request; reader.invalidate; selected = rows[0]; selected = rows[1]; worker.finish; reader.update
assert(said.size == 1, 'Leave and return accepted stale reply')
reader.request; active = false; worker.finish; reader.update
assert(said.size == 1, 'Blur spoke over other field')
active = true; value = {status: :unavailable}; reader.request; worker.finish; reader.update
assert(said.last.include?('unavailable'), 'Unknown list treated empty')
value = {status: :ready, players: [], observers: []}; reader.request; worker.finish; reader.update
assert(said.last == 'No players at this table.', 'Known empty list wrong')
reader.request; reader.close; worker.finish; reader.update
assert(said.last == 'No players at this table.', 'Closed view spoke')
assert(!reader.request, 'Closed view started new work')
puts 'PASS roster reader: one request, Unicode, generations, selection, blur, unavailable, empty, close'
