require_relative "../support/statistics_tables"

module StatisticsPaginationTest
  Period = Struct.new(:from_day, :to_day)
  class Cancelled < StandardError; end

  def self.check(value, message)
    @checks = @checks.to_i + 1
    raise message unless value
  end

  def self.rejects(error, &block)
    begin
      block.call
    rescue error
      return check(true, "rejected")
    end
    check(false, "Incomplete report was accepted instead of #{error}")
  end

  def self.row(id, kind: "visit", key: id, day: 20260930)
    {"__id" => id, "event_key" => format("%064x", key), "kind" => kind,
      "game" => kind == "visit" ? "" : "mancala", "mode" => kind == "visit" ? "" : "bots",
      "person" => kind == "visit" ? id : 0, "day_key" => day}
  end

  def self.fixture(cap: 1000, declared: 2000, current_user: -> { "Alice" })
    api = StatisticsMemoryApi.new
    api.schema_value["data"]["server"]["tables"]["statistics_events"]["limits"]["max_select_limit"] = declared
    table = api.tables.fetch("statistics_events")
    table.server_select_limit = cap
    store = GameRoomStatistics::Store.new(app_uuid: "pagination", user: "Alice", client: Object.new,
      api: api, current_user: current_user)
    [store, table]
  end

  def self.pages(table)
    table.queries.select { |query| query[:distinct] }
  end

  def self.run(name)
    yield
    puts "PASS #{name}"
  rescue StandardError => error
    (@failures ||= []) << "#{name}: #{error.class}: #{error.message}"
    warn @failures.last
  end

  [1000, 333, 17].each do |cap|
    run("schema 2000 / server #{cap}: starts after completions, raw duplicates") do
      store, table = fixture(cap: cap)
      table.rows.concat((1..1001).map { |id| row(id, kind: "completed") })
      table.rows.concat((1002..2003).map { |id| row(id, kind: "started") })
      table.rows << table.rows.first.merge("__id" => 2004)
      report = store.report(Period.new(nil, 20260930))
      check(report.values_at("started", "completed") == [1002, 1001], "Truncated match totals")
      check(report["games"].first["modes"]["bots"] == {"started" => 1002, "completed" => 1001}, "Truncated game/mode totals")
      offsets = (0..2003).step(cap).to_a
      offsets << 2003 unless offsets.last == 2003
      check(pages(table).map { |q| q[:offset] } == offsets, "Did not advance by actual distinct rows through empty tail")
      check(pages(table).all? { |q| q[:limit] == 1000 && q[:where]["__id"] == {"lte" => 2004} }, "Unbounded page or changing snapshot")
      check(table.rows.length == 2004 && table.bulk_calls.empty?, "Reading changed history")
    end
  end

  run("exact pages, shorter schema limit and empty interval") do
    [[1000, 2000, 2000], [17, 2000, 34], [1000, 2, 6], [1, 2, 3]].each do |cap, declared, count|
      store, table = fixture(cap: cap, declared: declared)
      table.rows.concat((1..count).map { |id| row(id) })
      check(store.report(Period.new(nil, 20260930))["visitors"] == count, "Exact-sized pages lost visitors")
      size = [cap, declared, 1000].min
      check(pages(table).map { |q| q[:offset] } == (0..count).step(size).to_a, "Exact multiple has no empty tail")
      check(table.queries.all? { |q| q[:limit] <= [declared, 1000].min }, "Ignored the lower schema limit")
      table.queries.clear
      check(store.report(Period.new(20260101, 20260101))["visitors"] == 0, "Empty interval was not empty")
      check(pages(table).map { |q| q[:offset] } == [0], "Empty interval kept polling")
    end
    store, table = fixture
    check(store.report(Period.new(nil, 20260930))["visitors"] == 0 && pages(table).empty?, "Empty table kept polling")
  end

  run("short pages preserve canonical dates and exclude concurrent inserts") do
    store, table = fixture(cap: 1)
    table.rows.concat([row(1, kind: "started", day: 20260929), row(2, kind: "started", key: 1),
      row(3, kind: "completed"), row(4, kind: "completed", key: 3), row(5)])
    table.after_select = lambda do |query, _rows|
      table.rows << row(6) if query[:distinct] && query[:offset] == 0 && table.rows.length == 5
    end
    today = store.report(Period.new(20260930, 20260930), reuse_snapshot: true)
    check(today.values_at("started", "completed", "visitors") == [0, 1, 1], "Canonical day, deduplication or snapshot changed")
    check(pages(table).all? { |q| q[:where]["__id"] == {"lte" => 5} }, "A page escaped the snapshot")
    check(store.report(Period.new(nil, 20260930), reuse_snapshot: true).values_at("started", "completed", "visitors") == [1, 1, 1],
      "Cached canonical rows changed cross-period totals")
    check(store.report(Period.new(nil, 20260930))["visitors"] == 2, "Fresh report did not see the new insert")
  end

  run("later-page failure, cancellation and account change never return partial totals") do
    [:failure, :cancel, :account, :empty_tail_failure].each do |mode|
      user, cancelled = "Alice", false
      token = Object.new
      token.define_singleton_method(:raise_if_cancelled!) { raise Cancelled if cancelled }
      store, table = fixture(cap: 2, current_user: -> { user })
      table.rows.concat((1..3).map { |id| row(id) })
      reached = []
      table.after_select = lambda do |query, _rows|
        next unless query[:distinct]
        reached << query[:offset]
        next unless query[:offset] == (mode == :empty_tail_failure ? 3 : 2)
        case mode
        when :failure, :empty_tail_failure then raise IOError, "later page unavailable"
        when :cancel then cancelled = true
        when :account then user = "Bob"
        end
      end
      error = mode == :cancel ? Cancelled : mode == :account ? GameRoomStatistics::Unavailable : IOError
      rejects(error) { store.report(Period.new(nil, 20260930), cancellation_token: token, reuse_snapshot: true) }
      check(reached == (mode == :empty_tail_failure ? [0, 2, 3] : [0, 2]), "Requests continued after interruption")
      user, cancelled, table.after_select = "Alice", false, nil
      check(store.report(Period.new(nil, 20260930), reuse_snapshot: true)["visitors"] == 3, "Retry cached a partial report")
    end
  end

  run("short repeated and malformed pages are errors, not EOF") do
    store, table = fixture(cap: 2)
    table.rows.concat((1..3).map { |id| row(id) })
    previous = nil
    table.after_select = lambda do |query, rows|
      next unless query[:distinct]
      previous ? rows.replace(previous) : previous = rows.map(&:dup)
    end
    rejects(GameRoomStatistics::Unavailable) { store.report(Period.new(nil, 20260930)) }
    check(pages(table).length == 2, "Repeated short page did not stop immediately")
    [nil, {}, false, Array.new(1001) { row(1).reject { |key, _| key == "__id" } }].each do |bad|
      store, table = fixture
      table.rows << row(1)
      original = table.method(:select)
      table.define_singleton_method(:select) { |**query| result = original.call(**query); query[:distinct] ? bad : result }
      rejects(GameRoomStatistics::Unavailable) { store.report(Period.new(nil, 20260930)) }
    end
  end

  raise @failures.join("\n") if @failures && !@failures.empty?
  puts "PASS statistics pagination: #{@checks} assertions"
end
