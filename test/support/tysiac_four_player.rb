require_relative "tysiac_two_player"

class FourPlayerTysiacFixture < TwoPlayerTysiacFixture
  def initialize(variant: "four_players", seats: [0, 1, 0, 1], players: %w[Alice Bob Carol David])
    @game = GameRoomGames::Tysiac.new
    @players = players
    @repository = NewGames116Repository.new(players)
    options = game.normalize_options("variant" => variant, "score_limit" => 10_000)
    options = game.with_team_assignment(options, players: players, seats: seats) if variant == "teams"
    @session = {"options" => JSON.generate(options), "__players" => players}
    @events = []
  end

  def next_deal
    state = replay.state
    round = state[:round] + 1
    dealer = state[:dealer_index] ? (state[:dealer_index] + 1) % 4 : 0
    event(players.first, "deal", "#{round}|#{dealer}|#{round.to_s(16).rjust(32, '0')}")
  end

  def finish_auction
    move({"kind" => "command", "action" => "bid", "bid" => 100})
    move({"kind" => "command", "action" => "bid", "bid" => "pass"}) while replay.state[:phase] == :bidding
  end

  def pass_cards
    while replay.state[:phase] == :passing
      move(game.legal_actions(replay, replay.current_player).find { |action| action["kind"] == "card" })
    end
  end

  def finish_play
    move({"kind" => "command", "action" => "contract", "bid" => 100})
    while replay.state[:phase] == :playing
      move(game.legal_actions(replay, replay.current_player).find { |action| action["card"].start_with?("normal|") })
    end
  end
end
