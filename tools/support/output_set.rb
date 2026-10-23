require 'tempfile'

# Authoring only, for a single writer. Prepare the complete set before replacing
# outputs; recover the old set if a later replacement fails. This does not make
# several filesystem renames an atomic transaction or guarantee crash recovery.
module GameRoomToolOutputs
  def self.commit(outputs, label:, binary: true)
    temporary, prepared, installed = [], [], []
    preserve = false
    begin
      outputs.each do |path, bytes|
        stage = Tempfile.create(['.game-room-output-stage-', '.tmp'], File.dirname(path))
        temporary << stage
        binary ? stage.binmode : stage.set_encoding('UTF-8')
        encoded = bytes.encode('UTF-8')
        expected = encoded.bytesize + (!binary && File::ALT_SEPARATOR ? encoded.count("\n") : 0)
        raise IOError, 'Incomplete staged output' unless stage.write(encoded) == expected
        stage.close
        backup = nil
        if File.exist?(path)
          backup = Tempfile.create(['.game-room-output-backup-', '.tmp'], File.dirname(path))
          temporary << backup
          backup.binmode
          original = File.binread(path)
          raise IOError, 'Incomplete output backup' unless backup.write(original) == original.bytesize
          backup.close
        end
        prepared << [path, stage, backup]
      end
      prepared.each do |path, stage, backup|
        File.rename(stage.path, path)
        installed << [path, backup]
      end
    rescue StandardError => error
      failures = []
      installed.reverse_each do |path, backup|
        begin
          backup ? File.rename(backup.path, path) : File.unlink(path)
        rescue StandardError => rollback_error
          failures << "#{path}: #{rollback_error.class}"
        end
      end
      raise error if failures.empty?
      preserve = true
      raise IOError, "#{label} output rollback failed: #{failures.join('; ')}. Recovery files: #{temporary.map(&:path).join(', ')}"
    ensure
      temporary.each do |file|
        file.close unless file.closed?
        File.unlink(file.path) if !preserve && File.exist?(file.path)
      end
    end
  end
end
