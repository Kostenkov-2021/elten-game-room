class GameRoomLiveSessionStore
  module Invitations
    public

    def invite_user(table_id:, user:, metadata:)
      session = active_session(table_identifier(table_id))
      return false if session == nil

      # The current API accepts a participant identity for invitations, not just
      # the room owner's identity. Let it validate the actual membership.
      result = session.invite(user.to_s, metadata: metadata.to_h.merge("purpose" => "game_invitation"))
      result
    end

    def pending_invitations
      prune_invitations
      recipient = endpoint.user.to_s
      @mutex.synchronize do
        @pending_invitations.values.map do |stored|
          invitation = stored[:invitation]
          metadata = invitation.invitation_metadata.to_h
          inviter = invitation.respond_to?(:inviter) ? invitation.inviter.user.to_s : metadata["sender"].to_s
          {
            "__id" => stored[:id],
            "table_id" => stored[:table_id],
            "sender" => inviter,
            "recipient" => recipient,
            "status" => "pending",
            "created_at" => stored[:created_at],
            "expires_at" => invitation_expiration(stored),
            "__native_invitation" => invitation
          }
        end
      end
    end

    def accept_invitation(table_id:, invitation_id:, participant_metadata: {})
      stored = take_invitation(table_id, invitation_id)
      return false if stored == nil

      session = stored[:invitation].accept(participant_metadata: participant_metadata(table_id).merge(participant_metadata.to_h))
      status = admit_joined_session(stored[:table_id], session)
      resolve_invitation(stored[:id])
      status == :joined
    rescue StandardError
      restore_invitation(stored) if stored && stored[:invitation].pending?
      raise
    end

    def reject_invitation(table_id:, invitation_id:)
      stored = take_invitation(table_id, invitation_id)
      return false if stored == nil

      stored[:invitation].reject
      resolve_invitation(stored[:id])
      true
    rescue StandardError
      restore_invitation(stored) if stored
      raise
    end

    # A notification may be opened by a brand-new endpoint. The native server
    # invitation in fresh discovery, not another endpoint's queue, grants access.
    def reject_discovered_invitation(table)
      item = table["__discovered_session"]
      data = item.respond_to?(:invitation) ? item.invitation : nil
      raise GameRoomNetworkErrors::UnsupportedInvitation, "The server did not provide the private invitation identity" unless data.is_a?(Hash)
      native_id = data["invitation_id"] || data["id"]
      raise GameRoomNetworkErrors::UnsupportedInvitation, "The server did not provide the private invitation identity" if native_id.to_s.empty?

      identity = Struct.new(:id, :invitation_id, :generation).new(item.id, native_id, data["generation"].to_i)
      endpoint.reject_invitation(identity)
      true
    end

    private

    def register_invitation_callback(current)
      register = @mutex.synchronize do
        next false if @invitation_endpoint.equal?(current)

        @invitation_endpoint = current
        true
      end
      return if !register

      current.on_invitation { |invitation| receive_invitation(invitation) }
      return if !current.respond_to?(:next_invitation)

      loop do
        invitation = current.next_invitation(timeout: 0)
        break if invitation == nil

        receive_invitation(invitation)
      end
    end

    def receive_invitation(invitation)
      return if invitation.respond_to?(:pending?) && !invitation.pending?

      metadata = invitation.metadata.to_h
      return if !supported_metadata?(metadata)

      invitation_metadata = invitation.invitation_metadata.to_h
      return if invitation_metadata["purpose"].to_s != "game_invitation"

      table_id = positive_identifier(metadata["table_id"])
      invitation_id = positive_identifier(invitation_metadata["invitation_id"])
      return if table_id == nil || invitation_id == nil

      @mutex.synchronize do
        return if @resolved_invitations.key?(invitation_id)

        @pending_invitations[invitation_id] = {
          id: invitation_id,
          table_id: table_id,
          invitation: invitation,
          created_at: GameRoomClock.now.to_i
        }
      end
      emit_change(table_id, :invitation, invitation_id)
    rescue StandardError => error
      log_warning("incoming invitation", nil, error)
    end

    def take_invitation(table_id, invitation_id)
      prune_invitations
      id = positive_identifier(invitation_id)
      room_id = table_identifier(table_id)
      return nil if id == nil || room_id == nil

      @mutex.synchronize do
        stored = @pending_invitations[id]
        next nil if stored == nil || stored[:table_id] != room_id

        @pending_invitations.delete(id)
      end
    end

    def restore_invitation(stored)
      @mutex.synchronize { @pending_invitations[stored[:id]] = stored }
    end

    def resolve_invitation(id)
      @mutex.synchronize do
        @pending_invitations.delete(id.to_i)
        @resolved_invitations[id.to_i] = GameRoomClock.now.to_i + INVITATION_TTL
      end
    end

    def prune_invitations
      now = GameRoomClock.now.to_i
      expired = []
      @mutex.synchronize do
        @pending_invitations.delete_if do |_id, stored|
          invitation = stored[:invitation]
          no_longer_pending = invitation.respond_to?(:pending?) && !invitation.pending?
          timed_out = invitation_expiration(stored) <= now
          expired << invitation if timed_out && !no_longer_pending
          no_longer_pending || timed_out
        end
        @resolved_invitations.delete_if { |_id, expires_at| expires_at <= now }
      end
      expired.each do |invitation|
        invitation.reject if !invitation.respond_to?(:pending?) || invitation.pending?
      rescue StandardError => error
        log_warning("expired invitation cleanup", nil, error)
      end
    end

    def invitation_expiration(stored)
      local_expiration = stored[:created_at].to_i + INVITATION_TTL
      invitation = stored[:invitation]
      native_expiration = invitation.respond_to?(:expires_at) ? invitation.expires_at.to_i : 0
      native_expiration.positive? ? [local_expiration, native_expiration].min : local_expiration
    end
  end

  include Invitations
end
