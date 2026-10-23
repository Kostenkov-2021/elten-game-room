require_relative '../support/tournament_forfeit_native'
require 'timeout'

module ResultFirstRetainTest
  # Exercise the real journal access/write boundary, not a fake service error.
  class Journal < GameRoomTournaments::OperationJournal
    attr_accessor :failure
    attr_reader :failures

    private

    def write(document)
      result = document['operations'].any? do |entry|
        entry['kind'] == 'plan_document' &&
          JSON.parse(entry['values']['document_json'])['kind'] == 'ordinary-match-result-v1'
      end
      return super unless result && failure
      mode = failure.is_a?(Array) ? failure.shift : failure
      self.failure = nil unless failure.is_a?(Array) && !failure.empty?
      @failures = (@failures || 0) + 1
      if mode == :before
        # The owned missing directory gives a real pre-rename SystemCallError.
        File.open(File.join(File.dirname(path), 'missing-result-parent', 'result'), 'wb') {}
      elsif mode == :after
        super
        raise IOError, 'Local result write completed but acknowledgement failed'
      else
        raise GameRoomTournaments::OperationJournal::Corrupt, :corrupt_journal
      end
    end
  end

  class ErrorGate < Queue
    attr_reader :arrived, :resume
    def initialize
      super
      @arrived, @resume = Queue.new, Queue.new
    end
    def <<(error)
      super
      @arrived << true
      @resume.pop
      self
    end
  end

  def self.run(mode, retry_route)
    TournamentForfeitNative.with_fixture do |fixture|
      fixture.start
      h, alice = fixture.h, fixture.services.fetch('Alice')
      original = alice.instance_variable_get(:@journal)
      journal = Journal.new(directory: File.dirname(original.path), owner: original.owner,
        backend_identity: original.backend_identity)
      alice.instance_variable_set(:@journal, journal)
      12.times do
        replay = h.replay('Alice')
        break if replay.finished?
        h.submit(replay.current_player, h.game.legal_actions(replay, replay.current_player).first)
      end
      replay = h.replay('Alice')
      assert(replay.finished?, 'The ordinary native-contract match did not finish')
      events = h.events('Alice')
      original_digest = Digest::SHA256.hexdigest(JSON.generate(events))
      baseline_writes = fixture.documents.insert_count
      journal.failure = mode.is_a?(Array) ? mode.dup : mode
      if retry_route == :gate || mode == :permanent
        gate = ErrorGate.new
        alice.instance_variable_set(:@errors, gate)
      end
      alice.observe(h.table, h.session, replay, events)
      Timeout.timeout(5) { gate.arrived.pop } if gate
      error = Timeout.timeout(5) { alice.instance_variable_get(:@errors).pop }
      assert(error.is_a?(GameRoomTournaments::OperationJournal::Error), error.inspect)
      assert_equal(mode == :permanent ? :corrupt_journal : :journal_io_error, error.code)
      assert_equal(1, journal.failures)
      assert_equal(baseline_writes, fixture.documents.insert_count, 'Unretained result reached the server')
      retained = journal.list.select do |entry|
        JSON.parse(entry['values']['document_json'])['kind'] == 'ordinary-match-result-v1'
      end
      assert_equal(mode == :after ? 1 : 0, retained.size)

      # A later projection is valid but has different non-sporting evidence.
      # A retry must keep the FIRST captured receipt, not recapture this one.
      later = Marshal.load(Marshal.dump(events))
      later.first['created_at'] = later.first.fetch('created_at') + 1
      later_replay = h.game.replay(h.session, later, h.repositories.fetch('Alice'))
      assert(later_replay.finished?)
      assert(original_digest != Digest::SHA256.hexdigest(JSON.generate(later)))
      if retry_route == :gate
        alice.take_error
        gate.resume << true
        Timeout.timeout(5) { gate.arrived.pop }
        again = gate.pop
        assert_equal(:journal_io_error, again.code)
        assert_equal(2, journal.failures)
        alice.take_error
        gate.resume << true
      elsif retry_route == :observe
        alice.observe(h.table, h.session, later_replay, later)
      else
        alice.take_error # The normal Matches overview reads this error channel.
      end
      if mode == :permanent
        # The worker is held at error delivery, so it cannot consume a wrongly
        # admitted retry before this assertion observes the queue.
        assert(alice.instance_variable_get(:@jobs).empty?, 'Corrupt storage admitted a retry')
        assert_equal(baseline_writes, fixture.documents.insert_count)
        assert_equal(1, journal.failures, 'Corrupt storage must not be retried')
        return
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      loop do
        error = alice.take_error
        raise error if error
        break if fixture.changes.any?
        raise 'First result capture was lost after local journal failure' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.01
      end
      view = fixture.services.fetch('Bob').result_view
      assert_equal(1, view.fetch('results').size)
      assert_equal(original_digest, view['results'].first['history_digest'], 'Retry replaced original capture')
      result_records = journal.list.select do |entry|
        JSON.parse(entry['values']['document_json'])['kind'] == 'ordinary-match-result-v1'
      end
      assert_equal(1, result_records.size, 'Retry duplicated the retained result')
      assert_equal('confirmed', result_records.first['status'])
      assert_equal(original_digest, JSON.parse(result_records.first['values']['document_json'])['history_digest'])
      writes = fixture.documents.insert_count
      4.times { alice.observe(h.table, h.session, later_replay, later); alice.take_error }
      assert_equal(writes, fixture.documents.insert_count, 'Repeated callback or overview duplicated result')
    ensure
      2.times { gate.resume << true } if gate
    end
  end
end

cases = [[:before, :observe], [:before, :overview], [:after, :observe], [:after, :overview], [:permanent, :overview]]
cases << [[:before, :before], :gate]
cases = cases.first(1) if ENV['RESULT_RETAIN_FIRST_ONLY'] == '1'
cases = cases.last(1) if ENV['RESULT_RETAIN_GATE_ONLY'] == '1'
cases.each { |mode, route| ResultFirstRetainTest.run(mode, route) }
puts "PASS first local result retain: #{cases.size} worker/journal scenarios, exact first capture and no duplicate or corrupt-storage retry"
