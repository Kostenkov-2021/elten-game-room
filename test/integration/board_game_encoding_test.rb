require_relative "../support/translation_reference"
require_relative "../support/binary_rule_dictionary"

def board_assert(value, message)
  raise message unless value
end

repo = GameRoomSavedGameArchive::ReplayRepository.new
players = %w[Alice Bob]
sample = [[0,1,2,3],[20,21,22],[40,41,42],[60,61],[80,81],[85,86],[8],[28],[48],[68]]
messages = 0
[false, true].each do |english|
  $rules_english = english
  GameRoomTestLocalization.use_language(english ? :en : :pl)
  game = GameRoomGames::Battleship.new
  session = { "__id" => 77, "table_id" => 1, "__players" => players, "options" => JSON.generate(game.default_options) }
  context = GameRoomGames::ActionContext.new(session_id: 77,
    hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new))
  start = game.replay(session, [], repo)
  grid = GameSurfaces.build(game.surface_spec(start, "Alice"))
  board_assert(grid.fields.first.options == (english ? ["Randomly", "Manually"] : ["Losowo", "Ręcznie"]), "binary setup choice is missing or untranslated")
  setup_text = [grid.fields.first.header] + grid.fields.first.options
  grid.fields.first.index = 1
  grid.fields.first.trigger(:select)
  grid.fields.first.trigger(:select, [0,0])
  board_assert(grid.state["bow"] == 0, "binary grid did not mark bow")
  grid.fields.first.trigger(:select, [3,0])
  board_assert(grid.state["ships"] == [[0,1,2,3]], "binary fleet placement failed")
  retained = GameSurfaces.build(game.surface_spec(start, "Alice"), state: grid.state)
  board_assert(retained.state["ships"] == grid.state["ships"], "refresh lost draft ships")
  retained.handle_command("undo")
  board_assert(retained.state["ships"].empty?, "binary undo failed")
  events = players.each_with_index.map do |player, index|
    envelope = context.hidden_submissions.prepare(session_id: 77, round_id: "fleet", user: player, payload: { "ships" => sample })
    { "id" => index+1, "actor" => player, "action" => "place", "value" => envelope.commitment }
  end
  events += [{ "id" => 3, "actor" => "Alice", "action" => "shoot", "value" => "0" },
    { "id" => 4, "actor" => "Bob", "action" => "answer", "value" => "hit" }]
  replay = game.replay(session, events, repo)
  players.each { |viewer| game.prepare_view(replay, viewer, context: context) }
  text = setup_text
  (players + ["Observer"]).each do |viewer|
    spec = game.surface_spec(replay, viewer)
    GameSurfaces.build(spec)
    spec.parts.each { |part| text << part.surface.header; text.concat(part.surface.cells.flatten) }
    text.concat(game.game_shortcuts(replay, viewer).select { |shortcut| shortcut.kind == :announcement }.map(&:message))
    text.concat(game.describe_event(events.last, repo, replay, viewer))
  end
  board_assert(text.any? { |value| value.include?(english ? "hit" : "trafiony") }, "binary shot text not translated")
  %w[oware ayoayo kalah].each do |variant|
    mancala = GameRoomGames::Mancala.new
    match = session.merge("options" => JSON.generate(mancala.normalize_options("variant" => variant)))
    event = { "id" => 1, "actor" => "Alice", "action" => "sow", "value" => "0" }
    position = mancala.replay(match, [event], repo)
    (players + ["Observer"]).each do |viewer|
      spec = mancala.surface_spec(position, viewer)
      GameSurfaces.build(spec)
      text << spec.header
      text.concat(spec.cells.flatten)
      text.concat(mancala.describe_event(event, repo, position, viewer))
      text.concat(mancala.game_shortcuts(position, viewer).select { |shortcut| shortcut.kind == :announcement }.map(&:message))
    end
  end
  text.each do |value|
    value = value.to_s
    board_assert(value.valid_encoding?, "invalid board text")
    combined = value + (english ? " Флажок" : " Pole wyboru")
    board_assert(combined.valid_encoding?, "board text incompatible with another host language")
    messages += 1
  end
end
translations = GameRoomTest::TranslationReference.fetch("board_games")
translations.each do |en, pl|
  board_assert(RULES_CATALOG[en] == pl, "new-game translation is missing: #{en}")
end
puts "PASS binary new boards: #{messages} PL/EN labels, native dictionary, fleet draft refresh, public shots and all Mancala variants"
