require_relative '../support/tournament_forfeit_native'
T = GameRoomTournaments

GameRoomTest::TemporaryDirectory.create('retention-complete-boundary-') do |directory|
  fixture = TournamentForfeitNative::Fixture.new(directory)
  service = fixture.services.fetch('Alice')
  preview = fixture.preview
  key = service.send(:anchor, fixture.candidate, 5, fixture.match, 'forfeit').fetch('operation_key')
  original_insert = fixture.documents.method(:insert_as)
  intercepted = false
  fixture.documents.on_insert = ->(row) { row['__insertion_time'] = 150 + 29 * 86_400 }
  fixture.documents.define_singleton_method(:insert_as) do |values, actor|
    selected = !intercepted && values['operation_key'] == key && values['part_index'] == 0
    if selected
      intercepted = true
      # A native game and its real collector finish after the last forfeit
      # authorization but before that competing header is actually accepted.
      fixture.start
      9.times do
        replay = fixture.h.replay('Alice')
        break if replay.finished?
        player = replay.current_player
        fixture.h.submit(player, fixture.h.game.legal_actions(replay, player).first)
      end
      assert(fixture.h.replay('Alice').finished?)
      service.collect(service.instance_variable_get(:@bindings).fetch(fixture.h.table.fetch('__id')))
    end
    inserted = original_insert.call(values, actor)
    raise IOError, 'Late header accepted; acknowledgement lost' if selected
    inserted
  end
  assert_raises(IOError) { fixture.confirm(preview) }
  before = fixture.documents.insert_count
  observer = fixture.services.fetch('Bob')
  ordinary_view = observer.result_view
  strict_view = observer.result_view(allow_incomplete_forfeits: false)
  assert_equal(ordinary_view, strict_view, 'A late partial upload hid an already complete natural result')
  assert(strict_view.fetch('completed'))
  assert_equal(['ordinary-match-result-v1'], strict_view.fetch('results').map { |row| row.fetch('kind') })
  assert_equal([150 + 29 * 86_400], strict_view.fetch('progress_times'))
  assert_equal(before, fixture.documents.insert_count, 'A retention result read wrote a document')
ensure
  fixture&.close
end
puts 'PASS retention boundary: complete native result remains decisive despite a later incomplete administrative header'
