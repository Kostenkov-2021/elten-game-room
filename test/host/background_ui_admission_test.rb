require_relative '../support/native_background_capacity'
require_relative '../support/widget'
require_relative '../../lib/game_room_contacts'
require_relative '../../lib/game_room_ping'
require_relative '../../lib/tournaments/proposal_notice_inbox'
include GameRoomTest::Assertions

# Actual public UI-facing methods and actual native Work/Tasks. Only data
# providers are local fixtures; a saturated queue never sends an HTTP request.
failures = []
[0, 128].each do |backlog|
  %i[contacts ping roster widget notice].each do |kind|
    GameRoomTest::NativeBackgroundCapacity.with(backlog) do |work, free_capacity|
      now, calls, said = 100.0, [], []
      cache = reader = widget = inbox = nil
      case kind
      when :contacts
        cache = GameRoomContacts::Cache.new(user: 'Host', worker: work, clock: -> { now },
          loader: -> { calls << true; ['New'] })
        # This is the valid cache state after an earlier successful read;
        # forcing a read must not mistake it for the new server result.
        cache.instance_variable_set(:@contacts, {'old' => true}.freeze)
        cache.instance_variable_set(:@loaded_at, now)
        assert(cache.snapshot(force: true).nil?, 'A pending explicit contact refresh exposed the old cache')
        assert(cache.snapshot.nil?, 'A refused forced contact read lost its unknown state')
        assert(calls.empty?, 'Contact read bypassed native capacity')
        free_capacity.call
        GameRoomTest::NativeBackgroundCapacity.until_true { cache.snapshot == {'new' => true} }
        5.times { cache.snapshot }
        assert_equal([true], calls, 'Forced contact read was lost or repeated')
        cache.close
      when :ping
        program = Object.new
        service = GameRoomPing.new(program, worker: work, clock: -> { now },
          probe: -> { calls << true; now += 0.042; true })
        assert_equal(backlog.zero?, service.request(program), 'Ping admission was not reported accurately')
        assert(calls.empty?, 'Ping bypassed native capacity')
        assert(service.poll(program).nil?, 'Unstarted ping produced a result')
        free_capacity.call
        assert(service.request(program), 'A refused ping could not be explicitly requested again') if backlog == 128
        message = nil
        GameRoomTest::NativeBackgroundCapacity.until_true { message = service.poll(program) }
        assert_equal('HTTP ping: 42 ms.', message)
        assert_equal([true], calls)
        assert(service.poll(program).nil?, 'Ping result repeated')
      when :roster
        selected = WidgetSnapshot.new(table: {'__id' => 7})
        reader = GameRoomTableRosterReader.new(worker: work, selected: -> { selected },
          active: -> { true }, id_for: ->(row) { row.table['__id'] }, speaker: ->(text) { said << text },
          loader: ->(_) { calls << true; {status: :ready, players: ['Host'], observers: []} })
        assert_equal(backlog.zero?, reader.request, 'Details admission was not reported accurately')
        assert_equal(backlog.zero? ? [] : ['The table participants are currently unavailable.'], said)
        assert(calls.empty?, 'Details read bypassed native capacity')
        free_capacity.call
        assert(reader.request, 'A refused details read could not be explicitly requested again') if backlog == 128
        GameRoomTest::NativeBackgroundCapacity.until_true { reader.update; said.last == 'Players: Host.' }
        assert_equal([true], calls)
        reader.close
      when :widget
        rows = [WidgetSnapshot.new(table: {'__id' => 7})]
        widget = GameRoomWidget::TableList.new(worker: work, loader: -> { calls << true; rows },
          opener: ->(*) {}, labeler: ->(_) { 'Current table' }, id_for: ->(row) { row.table['__id'] },
          clock: -> { now })
        assert_equal(backlog.zero?, widget.refresh, 'Widget admission was not reported accurately')
        assert(calls.empty?, 'Widget read bypassed native capacity')
        free_capacity.call
        assert(widget.refresh, 'Widget could not retry refused admission') if backlog == 128
        GameRoomTest::NativeBackgroundCapacity.until_true { widget.send(:apply_ready_result); widget.snapshots == rows }
        5.times { widget.send(:apply_ready_result) }
        assert_equal([true], calls)
        widget.close
      when :notice
        service = Object.new
        service.define_singleton_method(:inspect) do |metadata:, sender:|
          calls << sender
          {'metadata' => metadata}
        end
        service.define_singleton_method(:presentable?) { |_| true }
        inbox = GameRoomTournaments::ProposalNoticeInbox.new(service: service, worker: work,
          metadata: ->(value) { value }, clock: -> { now })
        assert(inbox.receive(id: 7, metadata: {'token' => 'a' * 64}, sender: 'Host'), 'Notice was not queued')
        assert_equal([], inbox.tick)
        assert(calls.empty?, 'Notice verification bypassed native capacity')
        free_capacity.call
        shown = []
        GameRoomTest::NativeBackgroundCapacity.until_true { shown.concat(inbox.tick); shown.size == 1 }
        5.times { assert_equal([], inbox.tick) }
        assert_equal(['host'], calls, 'Notice admission lost or repeated a verification')
        inbox.close
      end
    rescue StandardError => error
      failures << {case: kind, backlog: backlog, error: error.class.name, message: error.message}
    ensure
      cache&.close
      reader&.close
      widget&.close
      inbox&.close
    end
  end
end
assert(failures.empty?, "UI admission failures: #{failures.inspect}")
puts 'PASS UI-facing native task admission: contacts forced-cache recovery, explicit ping/details retry, widget refresh, no provider work before capacity'
