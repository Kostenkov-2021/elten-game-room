module GameRoomTest
  # State is optional. A semantic replay includes the board, turn, result,
  # accepted history and its original authors, including clientless games.
  module ReplaySnapshot
    FIELDS = %i[board players current_player winner draw accepted_events history state].freeze

    def self.capture(replay)
      Marshal.load(Marshal.dump(FIELDS.to_h { |field| [field, replay.public_send(field)] }))
    end
  end
end
