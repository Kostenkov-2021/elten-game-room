# encoding: UTF-8
$LOAD_PATH.unshift(File.expand_path("..", __dir__))

def _(text)
  text
end

def p_(_context, text)
  text
end

module GameSurfaces
  Action = Struct.new(:kind, :name, :payload, :source, keyword_init: true) do
    def initialize(kind:, name:, payload: {}, source: nil)
      super(kind: kind.to_s, name: name.to_s, payload: payload, source: source)
    end

    def [](key)
      return kind if key.to_s == "kind"
      return name if ["action", "name"].include?(key.to_s)
      payload[key.to_s]
    end
  end
  QuestionOption = Struct.new(:id, :label, :value, keyword_init: true)
  QuestionSpec = Struct.new(:id, :prompt, :mode, :options, :value, :submit_label, :required, :read_only, :max_length, :submit_on_select, :prompt_in_choices, keyword_init: true)
end

require "json"
require_relative "../lib/game_random"
require_relative "../lib/game_bots"
require_relative "../lib/hidden_submissions"
require_relative "../lib/game_content"
require_relative "../content/languages"
require_relative "../content/quiz_witcher_pl"
require_relative "../content/quiz_witcher_pl_data"
require_relative "../content/quiz_witcher_pl_medium_data"
require_relative "../games/quiz_party"

class WitcherSplitRepository
  def initialize(players)
    @players = players
  end

  def players_for(_session)
    @players
  end

  def actor_of(event, _session = nil)
    event.fetch("actor")
  end

  def event_id(event)
    event.fetch("id")
  end
end

def assert(condition, message)
  raise message if !condition
end

pack_ids = %w[quiz.witcher.pl quiz.witcher.g.pl quiz.witcher.b.pl]
packs = pack_ids.map { |id| GameRoomContent.registry.pack(id) }
assert(packs.none?(&:verified?), "registering Witcher sets eagerly loaded question data")
assert(
  packs.map(&:title) == ["Wiedźmin", "Wiedźmin — gry", "Wiedźmin — książki i ekranizacje"],
  "the Polish Witcher set names are wrong"
)
assert(packs.all? { |pack| pack.version == 6 }, "a Witcher set did not receive data version 6")

full, games, books_screen = packs.map(&:data)
full_questions = full.fetch("questions")
game_questions = games.fetch("questions")
book_screen_questions = books_screen.fetch("questions")
audit_path = File.expand_path("../diagnostics/quiz-factual-audit-220/WITCHER_FINAL_DECISIONS.json", File.expand_path("..", __dir__))
audit = JSON.parse(File.read(audit_path, encoding: "UTF-8"))
recovery_path = File.expand_path("../diagnostics/quiz-recovery-audit-after-221/ALL_RECHECK_DECISIONS.json", File.expand_path("..", __dir__))
recovery = JSON.parse(File.read(recovery_path, encoding: "UTF-8"))
restored_decisions = recovery.fetch("decisions").select do |row|
  row.fetch("pack_id") == "quiz.witcher.pl" && row.fetch("decision") == "restore"
end
retained_decisions = audit.fetch("decisions").reject { |row| row.fetch("decision") == "remove" } + restored_decisions
retained_by_id = retained_decisions.to_h { |row| [row.fetch("id"), row] }
forum_corrections = JSON.parse(File.read(File.expand_path('../docs/QUIZ_FORUM_CORRECTIONS_239.json', __dir__), encoding: 'UTF-8')).fetch('quiz.witcher.pl').to_h { |row| [row.fetch('id'), row] }
forum_corrections.each_value do |correction|
  row = retained_by_id.fetch(correction.fetch('id'))
  assert(row.fetch('reviewed') == correction.fetch('before'), 'Forum correction lost its audited baseline')
  row['reviewed'] = correction.fetch('after')
end
semantic_corrections = JSON.parse(File.read(File.expand_path('../docs/QUIZ_SEMANTIC_CORRECTIONS_239.json', __dir__), encoding: 'UTF-8')).fetch('changes')
semantic_corrections.select { |r| r.fetch('pack_id') == 'quiz.witcher.pl' }.each do |correction|
  id = correction.fetch('id')
  row = retained_by_id.fetch(id)
  assert(row.fetch('reviewed') == correction.fetch('before'), 'Semantic correction lost its audited baseline')
  assert(row.fetch('medium') == correction.fetch('medium_before'), 'Medium correction lost its audited baseline') if correction.key?('medium_before')
  if correction.fetch('after')
    row['reviewed'] = correction.fetch('after')
    row['medium'] = correction.fetch('medium_after') if correction.key?('medium_after')
  else
    retained_by_id.delete(id)
  end
end
expected_media = retained_by_id.values.group_by { |row| row.fetch("medium") }.transform_values(&:length)
assert(full_questions.length == retained_by_id.length, "the full Witcher set does not match the factual audit and corrections")
assert(game_questions.length == expected_media.fetch("g"), "the game set has the wrong size")
assert(book_screen_questions.length == expected_media.fetch("b", 0) + expected_media.fetch("s", 0), "the books and screen set has the wrong size")

full_ids = full_questions.map { |question| question.fetch("id") }
game_ids = game_questions.map { |question| question.fetch("id") }
book_screen_ids = book_screen_questions.map { |question| question.fetch("id") }
assert(full_ids.uniq.length == full_ids.length, "the full Witcher set contains duplicate IDs")
assert(game_ids.uniq.length == game_ids.length, "the game set contains duplicate IDs")
assert(book_screen_ids.uniq.length == book_screen_ids.length, "the books and screen set contains duplicate IDs")
assert((game_ids & book_screen_ids).empty?, "a question belongs to both detailed sets")
assert((game_ids + book_screen_ids).sort == full_ids.sort, "the detailed sets do not partition all retained IDs")

classification = GameRoomContent::WitcherPolishMediumData.load
assert(classification.fetch("version") == 6, "the medium map has the wrong data version")
assert(classification.fetch("media").keys.sort == full_ids.sort, "the medium map does not cover every question")
assert(classification.fetch("media").values.tally == expected_media, "the reviewed medium totals do not match the audit")
assert(game_ids.all? { |id| classification.fetch("media").fetch(id) == "g" }, "the game set contains another medium")
assert(book_screen_ids.all? { |id| classification.fetch("media").fetch(id) != "g" }, "the books and screen set contains a game question")

full_questions.each do |question|
  expected = retained_by_id.fetch(question.fetch("id")).fetch("reviewed")
  assert(question == expected, "the source differs from the reviewed audit decision for #{question.fetch('id')}")
end
assert(classification.fetch("prompts").empty?, "clarified prompts should be stored in the audited shared source")
assert(full_questions.none? { |question| question.fetch("prompt").include?("] —") }, "an imported actor name still ends in a bracket")
assert(full_questions.none? { |question| question.fetch("prompt").start_with?("dubbing: )") }, "the malformed dubbing subject remains")

game = GameRoomGames::QuizParty.new
repository = WitcherSplitRepository.new(["Alice", "Bob"])
context = GameRoomGames::ActionContext.new(
  session_id: 218,
  table_id: 218,
  hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
  random_source: GameRoomRandom::SeededSource.new(218),
  now: 100
)

[
  ["quiz.witcher", full_questions],
  ["quiz.witcher.g", game_questions],
  ["quiz.witcher.b", book_screen_questions]
].each do |set_id, selected_questions|
  options = game.normalize_options("content_set_id" => set_id, "content_language_id" => "pl-PL")
  assert(game.validation_error(options, player_count: 2) == nil, "#{set_id} cannot start a match")
  session = { "options" => JSON.generate(options) }
  initial = game.replay(session, [], repository)
  assert(initial.state[:phase] == :drawing, "#{set_id} did not begin in the drawing phase")
  action = game.automatic_action(initial, "Alice", context: context)
  status, plan = game.action_for(action, initial, "Alice", context: context)
  assert(status == :ok && plan.events.length == 1, "#{set_id} could not draw its first categories")
  event = plan.events.first
  stored = [{ "id" => 1, "actor" => "Alice", "action" => event.action, "value" => event.value, "created_at" => 100 }]
  replayed = game.replay(session, stored, repository)
  assert(replayed.state[:phase] == :choosing, "#{set_id} could not replay its first event")
  available_categories = selected_questions.map { |question| question.fetch("category") }.uniq
  assert((replayed.state[:choices] - available_categories).empty?, "#{set_id} replayed a category from another set")
end

puts "Witcher medium split tests passed: #{full_ids.length} audited stable IDs, exact partition, lazy packs, Polish names, start and replay"
