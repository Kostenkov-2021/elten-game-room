require_relative 'native_tasks'
require_relative '../../lib/realtime/channel'
require_relative 'assertions'
Object.include(GameRoomTest::Assertions)

# Match the native error hierarchy without loading a network endpoint.
module EltenAPI
  module Communication
    class Error < StandardError; end
    class ConnectionError < Error; end
    class PeerUnavailable < Error; end
    class SessionClosed < Error; end
    class MessageTooLarge < Error; end
  end
end

# Deterministic finite workers. The endpoint/session fake intentionally exposes
# only the verified public API; no pump, transport internals or live accounts.
require_relative 'manual_work'
class ChannelWork < GameRoomTest::ManualWork; end
ChannelParticipant = Struct.new(:id, :user)
ChannelMessage = Struct.new(:sender, :data)
class ChannelSession
  attr_reader :id, :participants, :self_id, :sent, :invites
  attr_accessor :state, :leave_error
  def initialize(id, viewer, names)
    @id, @state, @self_id = id, :open, names.index(viewer)
    @participants = names.each_with_index.map { |user, i| ChannelParticipant.new(i, user) }
    @sent, @invites = [], []
  end
  def send_unreliable(data, to:); @sent << [data, to.map(&:user)]; end
  def invite(user); @invites << user; end
  def on_unreliable(&block); @receiver = block; end
  def on_owner_changed(&block); @owner_changed = block; end
  def deliver(user, data); @receiver.call(ChannelMessage.new(ChannelParticipant.new(99, user), data)); end
  def transfer; @owner_changed.call(ChannelParticipant.new(7, 'Mallory')); end
  def close; @state = :closed; end
  def leave; raise EltenAPI::Communication::ConnectionError, 'departure failure' if @leave_error; close; end
end
class ChannelEndpoint
  attr_reader :creates, :closes
  attr_accessor :create_hook
  def initialize(viewer)
    @viewer, @creates, @closes = viewer, [], 0
  end
  def closed?; @closes > 0; end
  def close; @closes += 1; @created&.close; end
  def create_session(**args)
    @creates << args
    @create_hook&.call
    @created = ChannelSession.new('native-session', @viewer, [@viewer])
  end
  def on_invitation(&block); @invitation_handler = block; end
  def next_invitation(timeout:); raise 'blocking invitation poll' unless timeout == 0; (@queue ||= []).shift; end
  def enqueue(invitation); (@queue ||= []) << invitation; end
  def deliver(invitation); @invitation_handler.call(invitation); end
end
class ChannelProgram
  attr_reader :endpoints, :released
  attr_accessor :creation_hook
  def initialize(viewer); @viewer, @endpoints, @released = viewer, [], []; end
  def communication
    @creation_hook&.call
    @endpoints << ChannelEndpoint.new(@viewer)
    @endpoints.last
  end
  def release(endpoint); @released << endpoint; end
end
class ChannelInvitation
  attr_reader :sender, :session_metadata, :status, :accepts
  def initialize(session, sender: 'Alice', metadata: {'gr_realtime' => 1, 'match' => 'match'})
    @session, @sender = session, ChannelParticipant.new(0, sender)
    @session_metadata, @status, @accepts = metadata, :pending, 0
  end
  def accept; @accepts += 1; @status = :accepted; @session; end
end
