require 'open3'
require 'timeout'
require 'stringio'
require_relative '../support/assertions'
require_relative '../support/tournament_readiness_fixture'
include GameRoomTest::Assertions

class ReadinessCleanupStream
  attr_accessor :binmode_failure
  attr_reader :closes
  def initialize
    @closed, @closes, @release = false, 0, Queue.new
  end
  def binmode; raise binmode_failure if binmode_failure; self; end
  def closed?; @closed; end
  def close; @closes += 1; @closed = true; @release << true; end
  def read; @release.pop; ''; end
end

class ReadinessCleanupWaiter
  attr_reader :pid, :joins
  def initialize(primary)
    @primary, @pid, @joins = primary, Object.new, []
  end
  def value; raise @primary; end
  def alive?; true; end
  def join(seconds = nil); @joins << seconds; self; end
end

parent = File.expand_path('../tournaments/readiness_process_test.rb', __dir__)
%i[wait_timeout binmode].each do |failure|
  primary = Timeout::Error.new('original owned-child failure')
  streams = Array.new(3) { ReadinessCleanupStream.new }
  streams.first.binmode_failure = primary if failure == :binmode
  waiter = ReadinessCleanupWaiter.new(primary)
  readers, signals, observations = [], [], nil
  original_open, original_kill = Open3.method(:popen3), Process.method(:kill)
  original_thread, original_stderr = Thread.method(:new), $stderr
  warnings, caught = StringIO.new, nil
  begin
    Open3.define_singleton_method(:popen3) { |*| [*streams, waiter] }
    Process.define_singleton_method(:kill) do |signal, pid|
      raise 'Unowned signal' unless signal == 'KILL' && pid.equal?(waiter.pid)
      signals << pid
      raise Errno::ESRCH
    end
    Thread.define_singleton_method(:new) do |*values, **options, &block|
      caller_path = caller_locations(1, 1).first.path
      thread = original_thread.call(*values, **options, &block)
      if caller_path == parent
        joins, native_join = [], thread.method(:join)
        thread.define_singleton_method(:join) { |*args| joins << args; native_join.call(*args) }
        readers << [thread, joins]
      end
      thread
    end
    $stderr = warnings
    begin
      # Execute the actual complete parent unchanged in a fresh namespace;
      # only its owned OS child is replaced. No copied launch/join logic.
      Module.new.module_eval(File.read(parent, encoding: 'UTF-8'), parent, 1)
    rescue StandardError => error
      caught = error
    end
    observations = {closed: streams.map(&:closed?), closes: streams.map(&:closes),
      waiter_joins: waiter.joins.dup, signals: signals.length,
      readers: readers.map { |thread, joins| [thread.alive?, joins.map(&:dup)] }}
  ensure
    Open3.define_singleton_method(:popen3, original_open)
    Process.define_singleton_method(:kill, original_kill)
    Thread.define_singleton_method(:new, original_thread)
    $stderr = original_stderr
    # A failing original implementation must not leak this regression's own
    # readers. Capture maintained cleanup above, before this safety net.
    streams.each { |stream| stream.close unless stream.closed? }
    readers.each { |thread, _| thread.kill if thread.alive?; thread.join(5) }
  end
  assert(caught.equal?(primary), "#{failure}: primary failure was replaced")
  assert_equal([true] * 3, observations[:closed], "#{failure}: actual parent left a pipe open")
  assert_equal([1] * 3, observations[:closes])
  assert_equal([5], observations[:waiter_joins], 'Actual parent cleanup did not bound its owned-child join')
  assert_equal(1, observations[:signals])
  assert_equal(failure == :binmode ? 0 : 2, observations[:readers].length)
  observations[:readers].each do |alive, joins|
    assert(!alive, 'A reader survived maintained cleanup')
    assert_equal([[5]], joins, 'Reader cleanup did not use a bounded join')
  end
  assert(warnings.string.empty?, 'Expected exited-child race produced a cleanup warning')
  puts "PASS readiness actual parent #{failure}: three pipes, reader lifetime, original exception and bounded cleanup"
end
