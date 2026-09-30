require_relative '../lobby_repository'
require_relative '../network_errors'

module GameRoomUseCases
  # Existing membership policies also serve ordinary departure. These ports
  # intentionally call those policies again at the write boundary.
  InvitationMembership = Struct.new(:pending, :complete, :establish, :reconnect,
    :leave, :apply_role, :revoke, keyword_init: true)
  InvitationJoin = Struct.new(:result, :left_current, keyword_init: true)

  class AcceptInvitation
    def initialize(lobby:, transport:, invitations:, membership:, user:)
      @lobby, @transport, @invitations = lobby, transport, invitations
      @membership, @user = membership, user
    end

    def lookup(invitation)
      tables = @transport.discover_rooms(include_private: true)
      snapshots = tables.map do |table|
        @lobby.snapshot_for(table) || LobbyRepository::TableSnapshot.new(table: table,
          members: [@lobby.owner_of(table)], bots: @lobby.bots_for(table))
      end
      pending = @invitations.pending_by_id(invitation.id, @user.call, tables: snapshots.map(&:table))
      snapshot = snapshots.find { |item| @lobby.table_id(item.table) == invitation.table_id }
      [pending, snapshot, @lobby.current_table_for(@user.call)]
    end

    def reconnect(invitation)
      pending = @membership.pending.call(invitation.table)
      accepted = @membership.reconnect.call(invitation.table)
      @membership.complete.call(invitation.table, pending) if accepted
      accepted
    end

    def join(invitation, current:, notification_id: nil)
      left_current = false
      pending = @membership.pending.call(invitation.table)
      status = @membership.establish.call(invitation.table)
      if status == :full
        return InvitationJoin.new(result: :table_full, left_current: false)
      elsif status == :closed
        @membership.revoke.call(invitation.id, notification_id: notification_id)
        return InvitationJoin.new(result: :table_closed, left_current: false)
      elsif ![:joined, :already_here].include?(status)
        return InvitationJoin.new(result: :transport_failed, left_current: false)
      end

      if current != nil
        begin
          left = @membership.leave.call(current)
          raise GameRoomNetworkErrors::GamePaused, 'The current table could not be left' if left == nil
          left_current = true
        rescue StandardError
          @transport.deactivate_table(table_id: invitation.table_id)
          raise
        end
      end

      joined = @lobby.join_table(invitation.table, @user.call, announce: false)
      @membership.apply_role.call(joined.table) if joined.entered?
      if joined.entered?
        @membership.complete.call(joined.table, pending)
      elsif joined.status == :closed
        @transport.deactivate_table(table_id: invitation.table_id)
        @invitations.respond(invitation, recipient: @user.call, response: 'expired')
        @membership.revoke.call(invitation.id, notification_id: notification_id)
      else
        @transport.deactivate_table(table_id: invitation.table_id)
      end
      InvitationJoin.new(result: joined, left_current: left_current)
    end
  end
end
