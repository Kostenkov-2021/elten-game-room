module GameRoomTest
  # Finite worker driven explicitly by the scenario; no sleeping or threads.
  class ManualWork
    attr_reader :operation
    def busy?; @operation || @result; end
    def start(&block); return false if busy? || @closed; @operation = block; true; end
    def finish
      operation, @operation = @operation, nil
      value = operation.call
      @result = [value, nil] unless @closed
    rescue StandardError => error
      @result = [nil, error] unless @closed
    end
    def take; result, @result = @result, nil; result; end
    def close; @closed = true; @result = nil; end
  end
end
