require_relative 'realtime_channel'
require_relative '../../lib/realtime/event_channel'

class ChannelSession
  attr_reader :reliable_sent
  attr_accessor :reliable_error
  def on_reliable(&block); @event_receiver = block; end
  def send_reliable(data, to:)
    raise EltenAPI::Communication::ConnectionError, 'send failed' if @reliable_error
    (@reliable_sent ||= []) << [data, to.map(&:user)]
    Struct.new(:results).new(to.to_h { |target| [target, :delivered] })
  end
  def deliver_event(user, data)
    @event_receiver.call(ChannelMessage.new(ChannelParticipant.new(99, user), data))
  end
end
