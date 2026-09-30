require_relative "../../games/catalog"
require "json"
require_relative "../../lib/board_preferences"
def assert(value, message); raise message unless value; end
class BoardPreferenceStorage
  attr_accessor :data, :failure
  attr_reader :reads, :writes
  def initialize; @data = {}; @reads = @writes = 0; end
  def read_json(*, **); @reads += 1; JSON.parse(JSON.generate(@data)); end
  def update_json(*, **); @writes += 1; raise IOError if @failure; yield @data; @data; end
end
storage = BoardPreferenceStorage.new
spec = Struct.new(:default_orientation).new("normal")
chess = GameRoomBoardPreferences.new(storage, GameRoomGames::Chess.new)
assert(chess.restore(spec, {})["orientation"] == "normal", "Default board changed")
chess.remember("toggle_orientation", spec, {"orientation" => "rotated", "selected" => [3, 3]})
assert(storage.data == {"chess" => {"orientation_flipped" => true}}, "Saved transient state")
again = GameRoomBoardPreferences.new(storage, GameRoomGames::Chess.new)
assert(again.restore(spec, {})["orientation"] == "rotated", "Rotation was not restored")
assert(again.restore(Struct.new(:default_orientation).new("rotated"), {})["orientation"] == "normal", "New seat lost relative orientation")
checks = GameRoomBoardPreferences.new(storage, GameRoomGames::Checkers.new)
checks.remember("toggle_coordinate_labels", spec, {"coordinate_label_set" => "algebraic"})
ludo = GameRoomBoardPreferences.new(storage, GameRoomGames::Ludo.new)
ludo.remember("toggle_player_labels", nil, {"player_labels" => "colours", "cursor" => 8})
assert(storage.data.keys.sort == %w[chess checkers ludo].sort, "Preferences of another game were lost")
reads, writes = storage.reads, storage.writes
100.times { ludo.restore(nil, {"index" => 3}); ludo.remember("next", nil, {}) }
assert([reads, writes] == [storage.reads, storage.writes], "Refresh did disk I/O")
assert(GameRoomBoardPreferences.new(BoardPreferenceStorage.new, GameRoomGames::Ludo.new).values == {}, "Profiles leaked")
storage.failure = true
ludo.remember("toggle_player_labels", nil, {"player_labels" => "names"})
assert(ludo.values == {"player_labels" => "names"}, "Failure discarded the local choice")
storage.data["chess"] = {"orientation_flipped" => "false", "cursor" => 7}
assert(GameRoomBoardPreferences.new(storage, GameRoomGames::Chess.new).values.empty?, "Corrupt values reached the surface")
puts "PASS persistent board choices: relative seats, profiles, invalid data, bounded I/O, no drafts"
