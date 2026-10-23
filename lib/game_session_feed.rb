require "thread"

# An independent, coalescing subscription. Consuming it never steals a wake-up
# from the visible screen. It contains no payloads, UI or network pump.
class GameRoomSessionFeed
  def initialize(transport, table_id)
    @transport, @table_id = transport, table_id.to_i
    @mutex = Mutex.new
    @game = @started = @recovery = nil
    @table = @closed = false
  end

  def notify(kind, value)
    @mutex.synchronize do
      return if @closed
      case kind.to_sym
      when :game then @game = [value.to_i, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
      when :game_started then @started, @table = value.to_i, true
      when :table then @table = true
      when :closed then @recovery = :closed
      when :recovery then @recovery ||= true
      when :network_error then @recovery = value unless @recovery == :closed
      end
    end
  end

  def consume_game_change(id)
    @mutex.synchronize do
      next nil unless @game && @game.first == id.to_i
      value, @game = @game.last, nil
      value
    end
  end

  def consume_room_game_change(_id)
    @mutex.synchronize { value, @game = @game&.last, nil; value }
  end

  def consume_game_start(_id)
    @mutex.synchronize { value, @started = @started, nil; value }
  end

  def consume_table_change(_id)
    @mutex.synchronize { value, @table = @table, false; value }
  end

  def consume_recovery(_id)
    @mutex.synchronize { value, @recovery = @recovery, nil; value }
  end

  def reconcile(id); @transport.reconcile(id); end
  def pending_move_error(id); @transport.pending_move_error(id); end

  def close
    @mutex.synchronize { @closed = true; @game = @started = @recovery = nil }
    @transport.unsubscribe_game_session(@table_id, self)
  end
end
