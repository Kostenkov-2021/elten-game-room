require "json"
require_relative "../../lib/game_statistics_store"

class StatisticsMemoryTable
  attr_reader :rows, :queries, :upserts, :bulk_calls
  attr_accessor :lose_ack, :after_upsert, :after_select, :after_insert, :after_bulk, :server_select_limit

  def initialize(identity: false)
    @identity, @rows, @queries, @upserts, @bulk_calls = identity, [], [], 0, []
    # The live endpoint can cap replies below max_select_limit in the schema.
    @server_select_limit = 1000
  end

  def upsert(values)
    @upserts += 1
    @rows << values.merge("__id" => 7, "__insertion_user" => "Alice") if @rows.empty?
    row = masked(@rows.first)
    @after_upsert.call(row) if @after_upsert
    row
  end

  def insert(values)
    row = values.merge("__id" => (@rows.map { |item| item["__id"] }.max || 0) + 1)
    @rows << row
    if @lose_ack
      @lose_ack = false
      raise IOError, "acknowledgement lost"
    end
    result = row.dup
    @after_insert.call(result) if @after_insert
    result
  end

  def insert_many(values)
    @bulk_calls << values.map(&:dup)
    rows = values.map { |value| insert(value) }
    @after_bulk&.call(rows)
    rows
  end

  def select(where: {}, columns: nil, aggregates: nil, group_by: nil, order: [], limit: 2000, offset: 0, distinct: false, include_access: false)
    @queries << {where: where, columns: columns, aggregates: aggregates, limit: limit, offset: offset,
      distinct: distinct, include_access: include_access}
    @queries.last[:group_by] = group_by if group_by
    @queries.last[:order] = order unless order.empty?
    %w[event_key __id].each do |key|
      values = where[key]
      raise "Canonical lookup exceeds the supported key chunk" if values.is_a?(Hash) && values["in"] && values["in"].length > 100
    end
    selected = @rows.map { |row| masked(row) }.select do |row|
      where.all? do |key, value|
        if value.is_a?(Hash)
          value.all? do |operator, expected|
            case operator
            when "in" then expected.include?(row[key])
            when "lte" then row[key] <= expected
            when "gte" then row[key] >= expected
            else raise "Unexpected operator #{operator}"
            end
          end
        else
          row[key] == value
        end
      end
    end
    if aggregates
      groups = group_by ? selected.group_by { |row| group_by.map { |key| row[key] } } : {[] => selected}
      selected = groups.map do |keys, rows|
        values = aggregates.to_h do |name, spec|
          raise "Unsupported aggregate #{spec.inspect}" unless spec["function"] == "min"
          [name, rows.map { |row| row[spec["column"]] }.compact.min]
        end
        (group_by || []).zip(keys).to_h.merge(values)
      end
    end
    order.reverse_each do |key, direction|
      selected = selected.sort_by { |row| row[key] }
      selected.reverse! if direction == "desc"
    end
    selected = selected.map { |row| columns ? row.select { |key, _| (columns + (aggregates || {}).keys).include?(key) } : row.dup }
    selected = selected.uniq if distinct
    selected = selected.drop(offset).first([limit, @server_select_limit].min)
    selected.each { |row| row["__access"] = {"owner" => true} } if include_access && !columns
    @after_select.call(@queries.last, selected) if @after_select
    selected
  end

  def masked(row)
    return row.dup unless @identity
    row.merge(GameRoomStatistics::Schema::HIDDEN.to_h { |key| [key, nil] })
  end
end

class StatisticsMemoryApi
  attr_reader :tables, :calls
  attr_accessor :schema_value, :after_schema

  def initialize
    definitions = JSON.parse(JSON.generate(GameRoomStatistics::Schema::TABLES))
    definitions.each_value { |table| table["permissions"] = table["permissions"].to_h { |key| [key, true] } }
    @schema_value = {"data" => {"server" => {"tables" => definitions}}}
    @calls = []
    @tables = definitions.keys.to_h { |name| [name, StatisticsMemoryTable.new(identity: name == GameRoomStatistics::Schema::ACCOUNTS)] }
  end

  def schema(*)
    @calls << :schema
    @after_schema&.call
    @schema_value
  end

  def table(_client, _uuid, name)
    @tables.fetch(name)
  end
end
