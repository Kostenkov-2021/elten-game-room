require_relative 'native_live_sessions'

# Only used by message-lane tests. Public send follows native Session#send,
# not Object#send; these messages never become entries in the durable stack.
class NativeLiveSessionsBroker
  MessageInfo = Struct.new(:recipient_user) do
    def private?; !recipient_user.nil?; end
  end
  class View
    attr_accessor :hold_message, :message_gate, :fail_next_message
    attr_reader :sent_messages
    def on_message(with_metadata: false, &block); (@message_callbacks ||= []) << block; end
    def send(packet, message_id: nil, retries: 2, **_options)
      raise EltenAPI::LiveSessions::SessionClosed if closed?
      @message_gate&.pop
      if @fail_next_message
        @fail_next_message = false
        raise IOError, 'offline preview'
      end
      (@sent_messages ||= []) << Marshal.load(Marshal.dump(packet))
      return true if @hold_message
      sender = participants.find { |participant| participant.user == user }
      @core.views.reject(&:closed?).each do |view|
        view.deliver_message(sender, packet, MessageInfo.new)
      end
      true
    end
    def deliver_message(sender, packet, info)
      @message_callbacks.to_a.each { |callback| callback.call(sender, Marshal.load(Marshal.dump(packet)), info) }
    end
  end
end
