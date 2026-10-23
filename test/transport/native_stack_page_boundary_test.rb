require_relative '../support/native_tasks'
require_relative '../support/native_live_endpoint'
require EltenTestHost.file('src/eltenlink/error.rb')
require EltenTestHost.file('src/eltenlink/client.rb')
require EltenTestHost.file('src/eltenlink/apps.rb')
require_relative '../support/assertions'
require_relative '../support/log'
require_relative '../../lib/game_room_transport'
require_relative '../../lib/game_sync'
include GameRoomTest::Assertions

# Exercise the actual blocking Session/Endpoint queue, JSON envelope parser
# and worker. Only the HTTP reply is local; no real account or socket exists.
class StackPageReply
  attr_accessor :context, :page
  attr_reader :requests, :workers

  def initialize
    @requests, @workers = [], []
  end

  def e_json_request(method, path, params, **_options)
    @workers << Thread.current
    @requests << [method, path, params]
    page = @page.respond_to?(:call) ? @page.call(method, path, params) : @page
    yield JSON.generate('success' => true, 'data' => page), nil
  end
end

def with_stack_page_reader
  client = StackPageReply.new
  endpoint = EltenAPI::LiveSessions::Endpoint.new(app_id: 'ef8a0700-2d36-411b-ae13-6e6811a63a78',
    client: client, user: 'Alice', token: 'offline-only')
  context = Object.new
  context.define_singleton_method(:loop_update) do |*_|
    endpoint.send(:tick_stack_requests)
    Thread.pass
  end
  client.context = context
  metadata = {'kind' => GameRoomLiveSessionStore::KIND, 'protocol' => 7,
    'table_id' => 41, 'owner' => 'Alice', 'name' => 'Offline stack', 'game' => 'test', 'created_at' => 1}
  endpoint.define_singleton_method(:discovery_request) do |operation, params, **_options|
    raise 'Unexpected non-stack request' unless operation == :create
    {'id' => 'native-stack-page-test', 'metadata' => params.fetch('metadata'),
      'participant_id' => 'alice-id', 'owner_id' => 'alice-id', 'private_messages' => true,
      'capacity' => 8, 'participants' => [{'id' => 'alice-id', 'user' => 'Alice'}],
      'limits' => {'stack' => true, 'pools' => true, 'private_messages' => true,
        'max_stack_entries' => 4096, 'max_stack_entry_bytes' => 16384}}
  end
  session = endpoint.create(metadata: metadata, capacity: 8, stack_entries: 4096,
    stack_entry_bytes: 16384, pool_count: 1, private_messages: true)
  client.page = {'session_id' => session.id, 'entries' => [], 'cursor' => 0, 'through' => 0, 'has_more' => false}
  program = Struct.new(:live_sessions).new(endpoint)
  transport = GameRoomTransport.new(program)
  store = transport.instance_variable_get(:@live_store)
  store.send(:attach_session, 41, session)
  entries = (1..2).map do |seq|
    {'seq' => seq, 'message_id' => SecureRandom.uuid, 'sender' => {'user' => 'Alice'},
      'sender_id' => 'alice-id', 'created_at' => 1,
      'packet' => GameRoomEventProtocol.record_packet(kind: 'room_activity', actor: 'Alice',
        data: {'activity_kind' => 'chat', 'message' => "entry #{seq}"})}
  end
  valid = {'session_id' => session.id, 'entries' => entries, 'cursor' => 2, 'through' => 2, 'has_more' => false}
  yield store, transport, client, valid
ensure
  transport&.instance_variable_get(:@live_store)&.instance_variable_get(:@discovery_work)&.close
  endpoint&.close
  EltenAPI::LiveSessions.unregister(endpoint) if endpoint
  client&.workers&.uniq&.each(&:join)
end

malformed = {
  no_progress: ->(page) { page.merge('entries' => [], 'cursor' => 0, 'has_more' => true) },
  absent_entries: ->(page) { page.reject { |key, _| key == 'entries' } },
  null_entries: ->(page) { page.merge('entries' => nil) },
  scalar_entries: ->(page) { page.merge('entries' => 'not an array') },
  wrong_session: ->(page) { page.merge('session_id' => 'another-native-session') },
  string_cursor: ->(page) { page.merge('cursor' => '2') },
  absent_through: ->(page) { page.reject { |key, _| key == 'through' } },
  string_through: ->(page) { page.merge('through' => '2') },
  cursor_jump: ->(page) { page.merge('entries' => []) },
  bad_late_entry: ->(page) { page.merge('entries' => [page['entries'][0], page['entries'][1].merge('seq' => 3)]) },
  absent_late_packet: ->(page) { page.merge('entries' => [page['entries'][0], page['entries'][1].reject { |key, _| key == 'packet' }]) },
  wrong_more: ->(page) { page.merge('has_more' => true) },
  scalar_more: ->(page) { page.merge('has_more' => 'false') },
  bad_gap: ->(page) { page.merge('gap' => {'from' => 2, 'to' => 2}) },
  gap_beyond_through: ->(page) { page.merge('gap' => {'from' => 1, 'to' => 3}) },
  oversize: lambda do |page|
    entries = Array.new(GameRoomLiveSessionStore::STACK_PAGE_SIZE + 1) { |i| page['entries'][0].merge('seq' => i + 1) }
    page.merge('entries' => entries, 'cursor' => entries.length, 'through' => entries.length)
  end
}
malformed.each do |name, change|
  with_stack_page_reader do |store, transport, client, valid|
    client.page = change.call(valid)
    clock = [0.0]
    sync = GameRoomSync::Controller.new(transport: transport, table_id: 41, clock: -> { clock[0] })
    before = client.requests.length
    error = assert_raises(EltenLink::Error) { sync.synchronize { store.send(:ensure_current, 41, force: true) } }
    assert_equal('invalid_json', error.code, "#{name}: failure did not use ordinary transient recovery")
    state = store.send(:room_state, 41)
    assert_equal([0, []], [state.stack_cursor, state.records], "#{name}: malformed page partly changed the history")
    assert_equal(before + 1, client.requests.length, "#{name}: boundary bypassed real blocking SDK request")
    clock[0] = GameRoomSync::ERROR_BACKOFF + 1
    assert(5.times.filter_map { sync.next_event }.any? { |event| event.kind == :recovery }, "#{name}: read failure lost recovery")
    # Recovery reconciles once before the caller's forced read. The normal
    # response must respect each actual after cursor, including the empty tail.
    client.page = lambda do |_method, path, _params|
      after = URI.decode_www_form(URI.parse(path).query).to_h.fetch('after').to_i
      valid.merge('entries' => valid['entries'].select { |entry| entry['seq'] > after })
    end
    begin
      assert(sync.synchronize { store.send(:ensure_current, 41, force: true) }, "#{name}: valid retry failed")
    rescue StandardError
      warn "#{name}: retry cursor=#{state.stack_cursor.inspect}, page=#{client.page.inspect}"
      raise
    end
    assert_equal([2, [1, 2]], [state.stack_cursor, state.records.map(&:sequence)], "#{name}: valid retry skipped or duplicated records")
  end
end

[:empty, :trimmed, :trimmed_empty, :paged, :bad_second_page].each do |scenario|
  with_stack_page_reader do |store, _transport, client, valid|
    entries = case scenario
    when :empty, :trimmed_empty then []
    when :trimmed then [valid['entries'][0].merge('seq' => 3)]
    else
      Array.new(130) { |i| valid['entries'][0].merge('seq' => i + 1, 'message_id' => SecureRandom.uuid) }
    end
    through = scenario == :trimmed_empty ? 2 : entries.last&.fetch('seq') || 0
    broken = scenario == :bad_second_page
    client.page = lambda do |_method, path, _params|
      after = URI.decode_www_form(URI.parse(path).query).to_h.fetch('after').to_i
      gap = {'from' => after + 1, 'to' => 2} if scenario.to_s.start_with?('trimmed') && after < 2
      tail = entries.select { |entry| entry['seq'] > after }.take(GameRoomLiveSessionStore::STACK_PAGE_SIZE)
      tail = [tail.first, tail.last.merge('seq' => 131)] if broken && after == 128
      cursor = tail.last&.fetch('seq') || [after, gap&.fetch('to') || 0].max
      valid.merge('entries' => tail, 'cursor' => cursor, 'through' => through,
        'has_more' => cursor < through, 'gap' => gap)
    end
    state = store.send(:room_state, 41)
    if broken
      assert_raises(EltenLink::Error) { store.send(:ensure_current, 41, force: true) }
      assert_equal([128, (1..128).to_a], [state.stack_cursor, state.records.map(&:sequence)], 'Bad second page changed the valid prefix or partially ingested its entries')
      broken = false
    end
    before = client.requests.length
    assert(store.send(:ensure_current, 41, force: true), "#{scenario}: valid native page rejected")
    assert_equal(through, state.stack_cursor, "#{scenario}: valid page cursor lost")
    assert_equal(entries.map { |entry| entry['seq'] }, state.records.map(&:sequence), "#{scenario}: valid page positions lost or duplicated")
    assert_equal(scenario == :paged ? 2 : 1, client.requests.length - before, "#{scenario}: unexpected read count")
  end
end
puts "PASS blocking native stack pages: #{malformed.length} malformed successful replies rejected before page ingestion, recovery/retry, empty/trimmed/multipage history and late-page retry (actual SDK/offline JSON only)"
