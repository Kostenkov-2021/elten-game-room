require_relative '../game_statistics_service'
require_relative 'store'

module GameRoomSportsRankings
  # Reuse the durable analytics queue, account guards and bounded upload retry.
  # Observing unfinished games is a no-op; terminal callbacks stage scalars only.
  class Service < GameRoomStatistics::Service
    PATH = 'sports-rankings-pending.json'.freeze

    def initialize(program:, user:, storage: program, store: nil, queue: nil, **options)
      store ||= Store.new(app_uuid: program.respond_to?(:server_app_uuid) ? program.server_app_uuid : program.class.server_app_uuid,
        user: user, current_user: options.fetch(:current_user, -> { Session.name }))
      queue ||= GameRoomStatistics::Queue.new(storage: storage, user: user, path: PATH,
        before_write: -> { check_context!(@flush_token) })
      super(program: program, user: user, storage: storage, store: store, queue: queue, **options)
    end

    def observe(game:, session:, replay:)
      return false unless replay&.finished?
      result = Result.from_replay(game: game, session: session, replay: replay)
      return false unless result && Result.parse(result).fetch('sides').any? { |side| GameRoomParticipants.includes?(side['players'], @user) }
      record(result)
    rescue StandardError => error
      failed(error)
    end

    def observe_tournament(game:, candidate:, match:, receipt:, players:, finished_at:)
      result = Result.from_tournament(game: game, candidate: candidate, match: match, receipt: receipt,
        players: players, finished_at: finished_at)
      result ? record(result) : false
    rescue StandardError => error
      failed(error)
    end

    private

    def record(row)
      enqueue(row.merge('kind'=>'sports_result', 'match'=>row.fetch('match_key')))
    end
  end
end
