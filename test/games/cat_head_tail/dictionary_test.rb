require_relative "../../support/cat_head_tail_dictionary"

repository = Object.new
def repository.players_for(session); session.fetch("__players"); end
def repository.actor_of(event, _session); event.fetch("actor"); end
def repository.event_id(event); event.fetch("id"); end

[:pl, :en, :missing_translation].each do |language|
  $cht_language = language
  GameRoomTestLocalization.use_language(language)
  game = EltenGameRoom::GAME_REGISTRY.build("cat_head_tail")
  expected_summary = language == :pl ? "do 100 punktów" : "to 100 points"
  raise "Untranslated table summary" unless game.options_summary(game.default_options) == expected_summary
  session = { "options" => JSON.generate(game.default_options), "__players" => ["Żaneta", "Łukasz"] }
  events = []
  texts = []
  [nil, "2", "3", "4", "5", "6", "7", "8|plus", "8|minus", "1"].each do |value|
    events << { "id" => events.length + 1, "actor" => "Żaneta", "action" => "roll", "value" => value } if value
    replay = game.replay(session, events, repository)
    shortcuts = game.game_shortcuts(replay, "Łukasz")
    keys = shortcuts.map { |shortcut| [shortcut.key, shortcut.modifiers] }
    raise "Duplicate shortcuts" unless keys.uniq == keys
    %w[c d s t].each { |key| raise "Missing #{key}" unless shortcuts.any? { |shortcut| shortcut.key == key } }
    texts.concat(shortcuts.map(&:message).compact)
    texts.concat(replay.history.map(&:text))
    surface = game.surface_spec(replay, replay.current_player)
    texts.concat(surface.zones.flat_map { |zone| [zone.header] + zone.cards.map(&:label) })
    roll_label = surface.zones.first.cards.find { |card| card.id == "roll" }.label
    raise "Wrong roll label" unless roll_label == (language == :pl ? "Rzuć kością" : "Roll")
    if value == "8|minus"
      expected = language == :pl ? "Żaneta, 8, -8 punktów." : "Żaneta, 8, -8 points."
      raise "Tail shortcut not translated" unless shortcuts.find { |shortcut| shortcut.key == "d" }.message == expected
    end
  end
  options = game.table_options_announcement(game.default_options)
  texts << options
  book = game.rule_book(options: game.default_options)
  raise "Wrong rule documents" unless book.documents.map(&:id) == [:rules, :controls, :current_options]
  authored = JSON.parse(File.read(File.join(BinaryRulesLoad::ROOT, "tools/data/rulebooks/cat_head_tail.json"), encoding: "UTF-8"))
  authored.fetch("sections").each do |section|
    actual = game.rule_sections.find { |item| item.id.to_s == section.fetch("id") }
    expected = section.fetch("paragraphs").map { |pair| pair.fetch(language == :pl ? "pl" : "en") }
    raise "Mixed-language rules: #{section['id']}" unless actual.paragraphs == expected
  end
  texts.concat(book.documents.map(&:text))
  texts.each do |text|
    raise "Broken non-ASCII encoding: #{text.inspect}" unless text.valid_encoding?
    combined = GameRoomContent.utf8(text) + " — pole tylko do odczytu"
    raise "Host role caused mixed encoding" unless combined.valid_encoding?
  end
  puts "PASS Cat, head, tail #{language}: binary sources, native/binary dictionary, actions, events, D/C/S/T, rules and options"
end
