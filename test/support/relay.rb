require_relative 'pong_client'
require_relative 'realtime_channel'

class RelayFixture
  attr_accessor :now, :ignore_until
  attr_reader :workers, :endpoints, :groups, :invites
  def initialize(ignore_until: 0)
    @now, @ignore_until = 0.0, ignore_until
    @workers, @endpoints, @groups, @invites = [], {}, [], []
  end
  def worker(name)
    work = ChannelWork.new
    @workers << [name, work]
    work
  end
  def advance_work
    @workers.dup.each do |name, work|
      next if name == 'Bob' && @now < 0.3
      work.finish if work.operation
    end
  end
  def endpoint(name)
    @endpoints[name] = RelayEndpoint.new(self, name)
  end
end

class RelayEndpoint
  attr_reader :name, :rig
  def initialize(rig, name); @rig, @name, @queue = rig, name, []; end
  def closed?; @closed == true; end
  def on_invitation(&block); @invitation_handler = block; end
  def next_invitation(timeout:); raise unless timeout == 0; @queue.shift; end
  def enqueue(invitation); @queue << invitation; end
  def create_session(metadata:, **options)
    group = { id: "session-#{rig.groups.length}", metadata: metadata, owner: name, views: {}, options: options }
    rig.groups << group
    RelaySession.new(self, group)
  end
  def close
    @closed = true
    rig.groups.each do |group|
      group[:views][name]&.close if group[:views][name]&.endpoint.equal?(self)
    end
  end
end

class RelayInvite
  attr_reader :sender, :session_metadata, :status
  def initialize(endpoint, group)
    @endpoint, @group = endpoint, group
    @sender = ChannelParticipant.new(0, group[:owner])
    @session_metadata, @status = group[:metadata], :pending
  end
  def accept
    raise 'expired native invitation' if @endpoint.closed? || @group[:closed]
    @status = :accepted
    RelaySession.new(@endpoint, @group)
  end
end

class RelaySession
  attr_reader :endpoint
  def initialize(endpoint, group)
    @endpoint, @group = endpoint, group
    group[:views][endpoint.name] = self
  end
  def id; @group[:id]; end
  def state; @closed || @group[:closed] || endpoint.closed? ? :closed : :open; end
  def self_id; endpoint.name; end
  def participants
    @group[:views].filter_map { |name, view| ChannelParticipant.new(name, name) if view.state == :open }
  end
  def invite(name)
    endpoint.rig.invites << endpoint.rig.now
    target = endpoint.rig.endpoints[name]
    raise 'PeerUnavailable' if !target || target.closed?
    target.enqueue(RelayInvite.new(target, @group)) if endpoint.rig.now >= endpoint.rig.ignore_until
    true
  end
  def on_unreliable(&block); @unreliable = block; end
  def on_reliable(&block); @reliable = block; end
  def on_owner_changed(&_block); end
  def send_unreliable(data, to:); deliver(:@unreliable, data, to); end
  def send_reliable(data, to:)
    deliver(:@reliable, data, to)
    results = to.to_h { |recipient| [recipient, :delivered] }
    Object.new.tap { |delivery| delivery.define_singleton_method(:results) { results } }
  end
  def deliver(lane, data, targets)
    targets.each do |target|
      view = @group[:views][target.user]
      next unless view && view.state == :open
      view.instance_variable_get(lane)&.call(ChannelMessage.new(ChannelParticipant.new(self_id, self_id), data))
    end
  end
  def close
    @closed = true
    @group[:closed] = true if endpoint.name == @group[:owner]
  end
  alias leave close
end
