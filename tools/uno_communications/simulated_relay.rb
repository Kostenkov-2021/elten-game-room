# In-memory test server. This is NOT Elten's relay implementation and makes
# no network calls. It deliberately supplies a contract not yet verified in
# native Communications. Never package or use this as a production backend.
require_relative 'client'

module GameRoomUnoCommunicationsPrototype
  class SimulatedRelay
    Stream = Struct.new(:journal, :requests, :endpoints, keyword_init: true)
    attr_reader :requests

    def initialize
      @streams, @requests = {}, []
    end

    def endpoint(identity, user)
      stream = @streams[identity] ||= Stream.new(journal: [], requests: {}, endpoints: [])
      endpoint = Endpoint.new(self, identity, user)
      stream.endpoints << endpoint
      endpoint
    end

    def enqueue(endpoint, request_id, data)
      raise CapacityExceeded, 'Simulated send queue is full' if @requests.length >= MAX_GAP
      raise CapacityExceeded, 'Simulated packet is too large' if data.bytesize > MAX_PACKET_BYTES
      @requests << [endpoint, request_id.dup.freeze, data.dup.freeze]
    end

    # Tests explicitly choose server-arrival order, independently of when a
    # user clicked or which recipient is currently consuming its inbox.
    def accept(index = 0)
      endpoint, request_id, data = @requests.delete_at(index)
      return unless endpoint
      stream = @streams.fetch(endpoint.identity)
      key = [endpoint.user.downcase, request_id]
      receipt = stream.requests[key]
      if receipt
        raise ProtocolError, 'Simulated relay rejects a changed retry' if receipt.data != data
      else
        raise CapacityExceeded, 'Simulated journal is full' if stream.journal.length >= MAX_RECEIPTS
        receipt = Receipt.new(identity: endpoint.identity, sequence: stream.journal.length + 1,
          sender: endpoint.user, request_id: request_id, data: data).freeze
        stream.requests[key] = receipt
        stream.journal << receipt
      end
      stream.endpoints.each { |target| target.push(receipt) }
      receipt
    end

    def history(identity, after)
      journal = @streams.fetch(identity).journal
      [journal.length, journal.drop(after)]
    end

    class Endpoint
      attr_reader :identity, :user, :inbox
      attr_accessor :available, :fail_after_publish

      def initialize(relay, identity, user)
        @relay, @identity, @user = relay, identity.dup.freeze, user.dup.freeze
        @inbox, @available, @lost = [], true, false
      end

      def contract; ORDERED_CONTRACT; end

      def publish(request_id, data)
        raise TransportUnavailable, 'Simulated disconnect' unless @available
        @relay.enqueue(self, request_id, data)
        raise TransportUnavailable, 'Simulated unknown send outcome' if @fail_after_publish
      end

      def push(receipt)
        return unless @available
        if @inbox.length >= MAX_GAP
          @lost = true
        else
          @inbox << receipt
        end
      end

      def drain
        raise TransportUnavailable, 'Simulated disconnect' unless @available
        # Overflow is explicit, never a silent successful delivery. Recovery
        # reads the numbered journal rather than asking a player for order.
        if @lost
          @lost = false
          raise TransportUnavailable, 'Simulated inbox overflow; recover required'
        end
        entries, @inbox = @inbox, []
        entries
      end

      def recover_after(cursor)
        raise TransportUnavailable, 'Simulated recovery failure' unless @available
        @relay.history(@identity, cursor)
      end
    end
  end
end
