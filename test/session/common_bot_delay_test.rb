require_relative "../support/ui"
require_relative "../support/log"
class Program
  def self.server_app(**_options); end
end
require_relative "../../__app"
require_relative "../../lib/bot_turn_gate"
require_relative '../support/catalog_options'

def assert(value, message); raise message unless value; end
games = EltenGameRoom::GAME_REGISTRY.ids.map { |id| EltenGameRoom::GAME_REGISTRY.build(id) }
games.each do |game|
  next unless game.supports_bots?
  unless game.supports_bot_move_delay?
    assert(game.effective_option_definitions.none? { |d| d.key == 'bot_delay' }, "continuous bot has turn delay #{game.id}")
    next
  end
  default = 1
  profile = GameRoomTest::CatalogOptions.for_players(game, bots: true)
  defs = game.effective_option_definitions.select { |d| d.key == "bot_delay" }
  assert(defs.length == 1 && defs.first.default == default, "shared option #{game.id}")
  assert(game.normalize_options(profile.reject { |key, _| key == 'bot_delay' })['bot_delay'] == default,
    "missing delay did not use the shared default #{game.id}")
  assert(game.table_creation_options(profile.reject { |key, _| key == 'bot_delay' })['bot_delay'] == default,
    "new table lost default bot delay #{game.id}")
  [0, 1, 5].each do |delay|
    options = profile.merge("bot_delay" => delay)
    assert(game.validation_error(options).nil?, "valid delay #{game.id}/#{delay}")
    assert(game.options_from_json(JSON.generate(options))["bot_delay"] == delay, "stored delay #{game.id}")
    state = { options: options, current_player: "Alice", phase: :playing }
    replay = GameRoomGames::Replay.new(players: %w[Alice Bob], state: state)
    context = GameRoomGames::ActionContext.new(options: options, now: 100)
    assert(game.bot_move_delay(replay, "Alice", context: context) == delay, "runtime delay #{game.id}")
    state[:turn_deadline] = 101
    assert(game.bot_move_delay(replay, "Alice", context: context) == 0, "deadline guard #{game.id}")
  end
  [-1, 6].each { |n| assert(game.validation_error(profile.merge("bot_delay" => n)), "invalid delay #{game.id}") }
end
assert(GameRoomGames::Uno.new.validation_error({ "bot_delay" => 5, "thinking_time" => 2 }), "thinking-time validation")
clock = 0.0
gate = GameRoomBots::TurnController.new(clock: -> { clock })
gate.schedule_decision(session_id: 1, actor: "bot:1:1", revision: [1, 2], delay: 5)
clock = 4.0
gate.schedule_decision(session_id: 1, actor: "bot:1:1", revision: [1, 2], delay: 5)
assert(!gate.ready?(session_id: 1, actor: "bot:1:1"), "pause too short")
clock = 5.0
assert(gate.ready?(session_id: 1, actor: "bot:1:1"), "refresh restarted delay")

# Complete authored editions do not append generic pacing text. An extension
# using Base's fallback rules must still describe the shared one-second default.
require_relative '../support/localization'
fallback = GameRoomGames::Uno.new
fallback.define_singleton_method(:localized_rule_sections) { nil }
{
  'en' => 'The default delay is one second.',
  'pl' => 'Domyślnie ustawiona jest jedna sekunda.',
  'cs' => 'Výchozí prodleva je jedna sekunda.',
  'es' => 'La pausa predeterminada es de un segundo.',
  'ru' => 'По умолчанию задержка составляет одну секунду.'
}.each do |language, sentence|
  GameRoomTestLocalization.use_language(language)
  chapter = fallback.rule_book.sections.find { |section| section.id == :bot_pacing }
  assert(chapter.paragraphs.first.end_with?(sentence), "fallback rules describe a different default #{language}")
end
puts "Common bot delay: #{games.length} game classes, defaults, range, replay and timer guard OK"
