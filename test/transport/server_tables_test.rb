module EltenLink
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  module Apps
    class << self
      attr_reader :table_calls

      def table(client, uuid, name)
        @table_calls ||= []
        object = Object.new
        @table_calls << [client, uuid, name, object]
        object
      end
    end
  end
end

require_relative "../../lib/game_room_server_tables"

def assert(condition, message)
  raise message if !condition
end

program = Struct.new(:server_app_uuid).new("server-uuid")
client = Object.new
tables = GameRoomServerTables.new(program, client: client)
first = tables.fetch("tables")
second = tables.fetch("tables")
events = tables.fetch("game_events")

assert(first.equal?(second), "a server table object was recreated")
assert(!first.equal?(events), "different server tables shared one object")
assert(EltenLink::Apps.table_calls.length == 2, "the provider repeated a table lookup")
assert(
  EltenLink::Apps.table_calls.all? { |call| call[0].equal?(client) && call[1] == "server-uuid" },
  "the provider did not reuse its context-free client and declared UUID"
)

puts "Server table provider tests passed"

calls = []
failure = nil
raw_users = EltenLink::Apps.table_calls.first.last
raw_users.define_singleton_method(:select) do |**options|
  calls << [:select, options]
  raise failure if failure

  []
end
raw_users.define_singleton_method(:insert) do |values|
  calls << [:insert, values]
  raise failure if failure

  values.merge("__id" => 1)
end
EltenLink::Apps.define_singleton_method(:table) { |_client, _uuid, _name| raw_users }
access = GameRoomServerTables.new(program, client: client)
users = access.fetch("game_room_users")
assert(!access.available?, "tables were enabled before checking access")
assert(users.select.empty? && calls.empty?, "an unchecked provider sent a request")
assert(access.check_access(username: "Alice"), "an empty successful probe did not enable tables")
assert(calls == [[:select, { where: { "username" => "Alice" }, limit: 1 }]], "the probe was not a minimal read")
assert(access.available?, "successful access check was not remembered")

failure = EltenLink::Error.new("apps.tables.stamp_required")
begin
  users.insert("username" => "Alice")
  raise "a denied write was reported as successful"
rescue EltenLink::Error => error
  assert(error.equal?(failure), "the original table error was replaced")
end
assert(access.stamp_required?, "a later write denial did not disable tables")
count = calls.length
assert(users.select.empty? && users.insert({}) == nil, "disabled operations returned a fake success")
assert(calls.length == count, "table operations continued after a denial")

failure = nil
assert(access.check_access(username: "Bob"), "a later launch did not restore access")
assert(calls.last == [:select, { where: { "username" => "Bob" }, limit: 1 }], "a later launch did not probe the current account")
assert(access.last_error == nil, "a successful recheck retained an old error")

%w[network_error timeout auth.unauthorized apps.tables.forbidden apps.tables.not_found api_error].each do |code|
  failure = EltenLink::Error.new(code)
  assert(!access.check_access(username: "Alice"), "a failed probe enabled tables")
  assert(!access.stamp_required? && !access.available?, "#{code} was misclassified as a development restriction")
  count = calls.length
  users.select
  users.insert({})
  assert(calls.length == count, "#{code} triggered another request")
end

failure = EltenLink::Error.new("apps.tables.stamp_required")
assert(!access.check_access(username: "Alice") && access.stamp_required?, "the protected-table error was not recognized")
access.reset_access!
assert(!access.available? && !access.stamp_required? && access.last_error == nil, "reset retained access from a previous launch")
puts "Server table access tests passed"
