# An owned snapshot preserves Ruby value types, internal aliases and cycles,
# while sharing no mutable model with its producer. Copy failure is explicit;
# callers that can rebuild a projection own that narrowly scoped fallback.
module GameRoomSnapshot
  # A closed, owned log can be shared between worker/UI copies: neither the
  # collection nor any of its entries can change. Mutable game state still
  # uses Marshal, retaining its aliases, cycles and custom serialization.
  CONTEXT_KEY = :game_room_snapshot_capture_context

  class Log < Array
    attr_reader :retained_bytes

    def self.from_owned(values, previous: nil, bytes: nil)
      return values if values.is_a?(self) && values.frozen?
      prefix = previous.is_a?(self) && previous.frozen? && previous.length <= values.length &&
        previous.each_with_index.all? { |item, index| item.equal?(values[index]) }
      tail = prefix ? values.drop(previous.length) : values.to_a
      return previous if prefix && tail.empty? && (bytes.nil? || bytes == previous.retained_bytes)
      seen = {}.compare_by_identity
      tail.each { |item| seal(item, seen) }
      size = bytes || ((prefix ? previous.retained_bytes : 0) + Marshal.dump(tail).bytesize + tail.length * 8)
      new(values, size)
    end

    # The authenticated replay input has already recursively sealed each row.
    # Do not traverse all of those old record graphs on every refresh again.
    def self.from_sealed(values, bytes:)
      raise TypeError, 'Unsealed immutable log entry' unless values.all?(&:frozen?)
      new(values, bytes)
    end

    def self.seal(value, seen)
      return if seen[value]
      seen[value] = true
      case value
      when Hash
        value.each { |key, item| seal(key, seen); seal(item, seen) }
      when Array, Struct
        value.each { |item| seal(item, seen) }
      when String, Numeric, Symbol, NilClass, TrueClass, FalseClass
      else
        raise TypeError, "Unsupported immutable log value: #{value.class}"
      end
      value.freeze
    end
    private_class_method :seal

    def initialize(values, bytes)
      super(values)
      @retained_bytes = bytes
      freeze
    end

    def _dump(_depth)
      context = Thread.current[CONTEXT_KEY]
      if frozen? && context && context[:writing]
        index = context[:indexes][self]
        unless index
          index = context[:logs].length
          context[:indexes][self] = index
          context[:logs] << self
        end
        "R#{index}"
      else
        # Ordinary Marshal remains self-contained (archives, test snapshots,
        # debug output). Only capture's paired dump/load uses local references.
        'V' + Marshal.dump(Array.new(self))
      end
    end

    def self._load(payload)
      if payload.start_with?('R')
        context = Thread.current[CONTEXT_KEY]
        raise TypeError, 'Immutable log reference outside its snapshot' unless context && !context[:writing]
        item = context[:logs].fetch(Integer(payload.delete_prefix('R'), 10))
        raise TypeError, 'Invalid immutable log reference' unless item.is_a?(self) && item.frozen?
        item
      elsif payload.start_with?('V')
        values = Marshal.load(payload.delete_prefix('V'))
        raise TypeError, 'Invalid immutable log contents' unless values.is_a?(Array)
        from_owned(values, bytes: payload.bytesize + values.length * 8)
      else
        raise TypeError, 'Invalid immutable log encoding'
      end
    end
  end

  class Capture
    attr_reader :bytesize

    def initialize(value)
      context = {writing: true, indexes: {}.compare_by_identity, logs: []}
      @encoded = GameRoomSnapshot.with_context(context) { Marshal.dump(value).freeze }
      @logs = context[:logs].freeze
      @bytesize = @encoded.bytesize + @logs.sum(&:retained_bytes)
      freeze
    end

    def restore
      GameRoomSnapshot.with_context(writing: false, logs: @logs) { Marshal.load(@encoded) }
    end
  end

  def self.with_context(context)
    previous = Thread.current[CONTEXT_KEY]
    Thread.current[CONTEXT_KEY] = context
    yield
  ensure
    Thread.current[CONTEXT_KEY] = previous
  end

  def self.capture(value)
    Capture.new(value)
  end

  def self.copy(value)
    capture(value).restore
  end
end
