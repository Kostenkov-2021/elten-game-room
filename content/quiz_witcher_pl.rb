# encoding: UTF-8
# The three sets share one source database and one audited medium map. Their
# contents are materialized only when the selected set is opened.
require_relative "../lib/game_content"

witcher_sets = [
  {
    id: "quiz.witcher.pl",
    set_id: "quiz.witcher",
    title: "Wiedźmin",
    scope: :all,
    entry_count: 5132,
    checksum: "c59f28827d46cc36dbf0893eed96365abc351d7b8d76dbee3f77baabb8dff39f"
  },
  {
    id: "quiz.witcher.g.pl",
    set_id: "quiz.witcher.g",
    title: "Wiedźmin — gry",
    scope: :games,
    entry_count: 2668,
    checksum: "60fe568f5239d93b29a2685b1b93e5b81f9576e0952290e878f77e7d73f85b2f"
  },
  {
    id: "quiz.witcher.b.pl",
    set_id: "quiz.witcher.b",
    title: "Wiedźmin — książki i ekranizacje",
    scope: :books_screen,
    entry_count: 2464,
    checksum: "7fb4a930a341ba985020ab460dbd996c8155945b730ad8dbbe70c371accb65b7"
  }
].freeze

witcher_sets.each do |definition|
  scope = definition.fetch(:scope)
  GameRoomContent.registry.register_pack(GameRoomContent::Pack.new(
    id: definition.fetch(:id),
    set_id: definition.fetch(:set_id),
    kind: :quiz,
    language_id: "pl-PL",
    version: 6,
    title: definition.fetch(:title),
    game_ids: ["quiz"],
    license: "CC BY-SA 3.0 (Fandom, Wiedźmin Wiki)",
    author: "ELTEN Game Room",
    entry_count: definition.fetch(:entry_count),
    checksum: definition.fetch(:checksum),
    loader: lambda {
      require_relative "quiz_witcher_pl_sets"
      GameRoomContent::WitcherPolishSets.load(scope)
    }
  ))
end
