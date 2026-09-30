require_relative '../network_errors'

module GameRoomUseCases
  # A save owns its freeze receipt. Failed persistence or close may release
  # only that boundary; the transport revalidates session and current owner.
  class SaveGame
    def initialize(repository:, transport:, archives:)
      @repository, @transport, @archives = repository, transport, archives
    end

    def call(table:, table_id:, session:, game:)
      boundary = nil
      begin
        boundary = @transport.freeze_game(session)
        confirmed = @repository.snapshot_for(session, force_events: true)
        raise ArgumentError, 'The room is no longer active' if confirmed == nil
        @archives.call.put(game: game, table: table, snapshot: confirmed, repository: @repository,
          now: (confirmed.session['__frozen_at'] || boundary.created_at).to_i)
      rescue StandardError
        @transport.freeze_game(session, frozen: false, expected_boundary: boundary) if boundary
        raise
      end
      begin
        @transport.deactivate_table(table_id: table_id)
      rescue StandardError
        @transport.freeze_game(session, frozen: false, expected_boundary: boundary)
        raise
      end
      true
    end
  end
end
