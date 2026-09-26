require_relative 'game_room_background'
require_relative 'game_content'

# An on-demand HTTP round trip, plus cached relay/direct RTTs and actual routes.
# No periodic requests, disk writes, UI pumps or speech on the worker thread.
require_relative "game_room_localization"

class GameRoomPing
  using GameRoomLocalization::Translations
  TIMEOUT = 5.0
  attr_accessor :communications_channel

  def self.for(program)
    program.instance_variable_get(:@game_room_ping) ||
      program.instance_variable_set(:@game_room_ping, new(program))
  end

  def initialize(program, worker: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, probe: nil)
    runtime = Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
    @worker = worker || GameRoomBackground::Work.new(runtime: runtime)
    @clock = clock
    @probe = probe || -> do
      EltenLink::System.server_time(program.send(:elten_link), timeout: TIMEOUT)
    end
  end

  def request(owner)
    @worker.take if @owner == nil
    return false if @worker.busy?
    @owner = owner
    @started = @clock.call
    @worker.start do
      started = @clock.call
      response = @probe.call
      elapsed = @clock.call - started
      raise 'Ping unavailable' if !response || !elapsed.finite? || elapsed < 0
      (elapsed * 1000).round
    end
  end

  def poll(owner)
    return unless @owner.equal?(owner)
    result = @worker.take
    return if result == nil && @clock.call - @started < TIMEOUT + 1
    @owner = nil
    # Do not announce an old result when returning from a different ELTEN
    # screen. Refreshing a Game Room form, however, may deliver a fresh one.
    return if result != nil && @clock.call - @started >= TIMEOUT + 1
    milliseconds, error = result
    http = if error || milliseconds == nil
      GameRoomContent.utf8(_("HTTP ping is unavailable."))
    else
      GameRoomContent.utf8(_("HTTP ping: %{milliseconds} ms.")) % {milliseconds: milliseconds}
    end
    [http, communications_announcement].compact.join(' ')
  end

  def cancel(owner)
    @owner = nil if @owner.equal?(owner)
  end

  private

  def communications_announcement
    channel = @communications_channel
    return unless channel.respond_to?(:ping_sample)
    sample = channel.ping_sample
    return unless sample
    peers = Array(sample[:peers])
    direct, relayed = peers.partition { |peer| peer[:transport] == :p2p }
    return relay_announcement(sample) if peers.empty?
    messages = []
    if !direct.empty? && !relayed.empty?
      messages << GameRoomContent.utf8(_("Communications: mixed P2P and relay connections."))
    end
    direct.each do |peer|
      milliseconds = peer[:p2p_ms]
      user = GameRoomContent.utf8(peer[:user])
      messages << if milliseconds.is_a?(Numeric) && milliseconds.finite? && milliseconds >= 0
        GameRoomContent.utf8(_("P2P with %{user}: %{milliseconds} ms.")) % {user: user, milliseconds: milliseconds.round}
      else
        GameRoomContent.utf8(_("P2P with %{user}: ping is unavailable.")) % {user: user}
      end
    end
    unless relayed.empty?
      users = relayed.map { |peer| GameRoomContent.utf8(peer[:user]) }.join(', ')
      messages << GameRoomContent.utf8(_("Communications via relay: %{users}.")) % {users: users}
      messages << relay_announcement(sample)
    end
    messages.join(' ')
  rescue StandardError
    GameRoomContent.utf8(_("Communications ping is unavailable."))
  end

  def relay_announcement(sample)
    milliseconds = sample[:relay_udp_ms]
    if milliseconds.is_a?(Numeric) && milliseconds.finite? && milliseconds >= 0
      GameRoomContent.utf8(_("Communications UDP relay ping: %{milliseconds} ms.")) % {milliseconds: milliseconds.round}
    else
      GameRoomContent.utf8(_("Communications UDP relay ping is unavailable."))
    end
  end
end
