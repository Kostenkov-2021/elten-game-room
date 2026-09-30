require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Base
    module Teams
      public

      def team_size(_options, player_count:)
        0
      end

      def team_assignment(options, players:)
        participants = GameRoomParticipants.unique(players)
        size = team_size(options, player_count: participants.length).to_i
        return nil if size <= 0

        normalized = normalize_options(options)
        GameRoomTeams::Assignment.new(
          players: participants,
          team_size: size,
          seats: normalized[GameRoomTeams::OPTION_KEY]
        )
      rescue ArgumentError
        nil
      end

      def with_team_assignment(options, players:, seats:)
        normalized = normalize_options(options)
        assignment = GameRoomTeams::Assignment.new(
          players: players,
          team_size: team_size(normalized, player_count: players.length),
          seats: seats
        )
        error = assignment.validation_error
        raise ArgumentError, error if error != nil

        normalized.merge(GameRoomTeams::OPTION_KEY => assignment.seats.dup,
          GameRoomTeams::PLAYERS_KEY => assignment.players.dup)
      end

      # A saved choice belongs to people, not row indices. A join, departure,
      # role change or different team size requires a new confirmation.
      def prepared_team_assignment(options, players:)
        raw_seats = options.to_h[GameRoomTeams::OPTION_KEY] || options.to_h[GameRoomTeams::OPTION_KEY.to_sym]
        return nil unless raw_seats.is_a?(Array) && raw_seats.all? { |seat| seat.is_a?(Integer) }
        normalized = normalize_options(options)
        saved = normalized[GameRoomTeams::PLAYERS_KEY]
        seats = normalized[GameRoomTeams::OPTION_KEY]
        current = GameRoomParticipants.unique(players)
        return nil unless saved.is_a?(Array) && saved.length == current.length && seats.is_a?(Array) && seats.length == saved.length
        return nil unless GameRoomParticipants.unique(saved).length == saved.length &&
          saved.all? { |player| GameRoomParticipants.includes?(current, player) }
        size = team_size(normalized, player_count: current.length).to_i
        return nil unless size.positive? && current.length % size == 0
        count = current.length / size
        return nil unless count >= 2 && seats.all? { |seat| seat.is_a?(Integer) && seat.between?(0, count - 1) }
        assignment = GameRoomTeams::Assignment.new(players: saved, team_size: size, seats: seats)
        assignment.valid? ? assignment : nil
      rescue ArgumentError
        nil
      end

      def options_for_team_roster(options, players:)
        normalized = normalize_options(options)
        assignment = prepared_team_assignment(normalized, players: players)
        if assignment
          with_team_assignment(normalized, players: players, seats: assignment.seats_for(players))
        else
          normalized.reject { |key, _value| [GameRoomTeams::OPTION_KEY, GameRoomTeams::PLAYERS_KEY].include?(key) }
        end
      end
    end

    include Teams
  end
end
