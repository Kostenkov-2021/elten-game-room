module GameRoomTest
  # Only for Open3 tuples/readers created by the calling test. Never discover
  # processes by name or reuse this as a general-purpose process terminator.
  module OwnedProcessCleanup
    def self.run(children, reader_threads: [])
      primary_error = nil
      begin
        yield
      rescue Exception => error
        primary_error = error
        raise
      ensure
        call(children, primary_error: primary_error, reader_threads: reader_threads)
      end
    end

    def self.call(children, primary_error: nil, reader_threads: [])
      errors = []
      children.each do |child|
        *streams, waiter = child
        streams.each do |stream|
          begin
            stream.close unless stream.closed?
          rescue StandardError => error
            errors << error
          end
        end
        begin
          Process.kill('KILL', waiter.pid) if waiter.alive?
        rescue Errno::ESRCH
          # The owned child can exit after alive? and before the signal.
        rescue StandardError => error
          errors << error
        ensure
          begin
            raise 'Owned test worker cleanup timed out' unless waiter.join(5)
          rescue StandardError => error
            errors << error
          end
        end
      end
      reader_threads.each do |reader|
        begin
          reader.kill if reader.alive?
        rescue StandardError => error
          errors << error
        ensure
          begin
            raise 'Owned test reader cleanup timed out' unless reader.join(5)
          rescue StandardError => error
            errors << error
          end
        end
      end
      errors.each { |error| warn "Test worker cleanup failed: #{error.class}: #{error.message}" }
      raise errors.first if !primary_error && !errors.empty?
    end
  end
end
