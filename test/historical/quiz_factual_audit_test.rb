# encoding: UTF-8
$LOAD_PATH.unshift(File.expand_path("../..", __dir__))
require_relative '../support/historical_quiz_evidence'
HistoricalQuizEvidence.require_files!

def _(text)
  text
end

def p_(_context, text)
  text
end

require "json"
require_relative "../../lib/game_content"
require_relative "../../content/languages"
require_relative "../../content/quiz_general_en"
require_relative "../../content/quiz_general_en_data"
require_relative "../../content/quiz_pl_wikidata"
require_relative "../../content/quiz_pl_wikidata_data"
require_relative "../../content/quiz_witcher_pl"
require_relative "../../content/quiz_witcher_pl_data"
require_relative "../../content/quiz_witcher_pl_medium_data"

def assert(condition, message)
  raise message unless condition
end

root = File.expand_path("../..", __dir__)
audit_root = HistoricalQuizEvidence.path('quiz-factual-audit-220')
recovery_root = HistoricalQuizEvidence.path('quiz-recovery-audit-after-221')
recovery_payload = JSON.parse(File.read(File.join(recovery_root, "ALL_RECHECK_DECISIONS.json"), encoding: "UTF-8"))
recovery_rows = recovery_payload.fetch("decisions")
forum_corrections = JSON.parse(File.read(File.join(root, 'docs/QUIZ_FORUM_CORRECTIONS_239.json'), encoding: 'UTF-8'))
semantic_corrections = JSON.parse(File.read(File.join(root, 'docs/QUIZ_SEMANTIC_CORRECTIONS_239.json'), encoding: 'UTF-8')).fetch('changes')

definitions = {
  "quiz.general.en" => {
    decisions: "ENGLISH_FINAL_DECISIONS.json",
    questions: -> { GameRoomContent::Pack0e7a79bfbaaded2145287ed3.load.fetch("questions") }
  },
  "quiz.wikidata.pl" => {
    decisions: "POLISH_FINAL_DECISIONS_MERGED.json",
    questions: -> { GameRoomContent::Packa0830f585cc4689a1e2a6335.load.fetch("questions") }
  },
  "quiz.witcher.pl" => {
    decisions: "WITCHER_FINAL_DECISIONS.json",
    questions: -> { GameRoomContent::Pack1f9366a686ccc2dddda06ad6.load.fetch("questions") }
  }
}

all_original_ids = []
definitions.each do |pack_id, definition|
  payload = JSON.parse(File.read(File.join(audit_root, definition.fetch(:decisions)), encoding: "UTF-8"))
  decisions = payload.fetch("decisions")
  ids = decisions.map { |row| row.fetch("id") }
  assert(ids.uniq.length == ids.length, "#{pack_id} has duplicate audit decisions")
  all_original_ids.concat(ids)

  decisions.each do |row|
    assert(row.fetch("original").fetch("id") == row.fetch("id"), "#{pack_id} changed an original ID")
    if row.fetch("decision") == "remove"
      assert(row["reviewed"] == nil, "#{pack_id} retained content for a removed question")
    else
      assert(row.fetch("reviewed").fetch("id") == row.fetch("id"), "#{pack_id} changed a retained ID")
      assert(!Array(row["evidence"]).empty?, "#{pack_id} retained a question without recorded evidence")
    end
  end

  removed_ids = decisions.select { |row| row.fetch("decision") == "remove" }.map { |row| row.fetch("id") }
  pack_rechecks = recovery_rows.select { |row| row.fetch("pack_id") == pack_id }
  assert(pack_rechecks.map { |row| row.fetch("id") }.sort == removed_ids.sort,
    "#{pack_id} recovery audit does not cover every removed question")
  pack_rechecks.each do |row|
    assert(%w[restore remain_removed].include?(row.fetch("decision")), "#{pack_id} has an invalid recovery decision")
    if row.fetch("decision") == "restore"
      assert(row.fetch("reviewed").fetch("id") == row.fetch("id"), "#{pack_id} recovery changed an ID")
      assert(!Array(row["evidence"]).empty?, "#{pack_id} restored a question without evidence")
    else
      assert(row["reviewed"] == nil, "#{pack_id} kept content for a question that remains removed")
    end
  end

  expected = decisions.reject { |row| row.fetch("decision") == "remove" }.map { |row| row.fetch("reviewed") } +
    pack_rechecks.select { |row| row.fetch("decision") == "restore" }.map { |row| row.fetch("reviewed") }
  actual = definition.fetch(:questions).call
  expected_by_id = expected.to_h { |row| [row.fetch("id"), row] }
  forum_corrections.fetch(pack_id, []).each do |change|
    assert(expected_by_id.fetch(change.fetch('id')) == change.fetch('before'), 'Forum correction lost its audited baseline')
    expected_by_id[change.fetch('id')] = change.fetch('after')
  end
  semantic_corrections.select { |row| row.fetch('pack_id') == pack_id }.each do |change|
    id = change.fetch('id')
    assert(expected_by_id.fetch(id) == change.fetch('before'), 'Semantic correction lost its audited baseline')
    if change.fetch('after')
      expected_by_id[id] = change.fetch('after')
    else
      expected_by_id.delete(id)
    end
  end
  assert(actual.map { |row| row.fetch('id') }.sort == expected_by_id.keys.sort,
    "#{pack_id} data do not match retained audit decisions and subsequent corrections")
  actual.each do |question|
    assert(question == expected_by_id.fetch(question.fetch("id")), "#{pack_id} differs from its reviewed decision")
    options = [question.fetch("correct"), *question.fetch("wrong")]
    normalized = options.map { |answer| UnicodeNormalize.normalize(answer.to_s, :nfkc).strip.downcase }
    assert(normalized.uniq.length == normalized.length, "#{pack_id} has duplicate answers for #{question.fetch('id')}")
  end

  if pack_id == "quiz.general.en"
    missing_apostrophe = /\b(?:aint|arent|cant|couldnt|didnt|doesnt|dont|hasnt|havent|isnt|shouldnt|wasnt|werent|wont|wouldnt|youll|youre|youve)\b/i
    actual.each do |question|
      text = [question.fetch("prompt"), question.fetch("correct"), *question.fetch("wrong")].join(" ")
      assert(!text.match?(missing_apostrophe), "English contraction was not corrected for #{question.fetch('id')}")
      assert(!question.fetch("prompt").match?(/\bBrodway\b|\AWhere is its natural habitat of\b/i),
        "known English wording defect remains in #{question.fetch('id')}")
    end
  elsif pack_id == "quiz.wikidata.pl"
    actual.each do |question|
      prompt = question.fetch("prompt")
      assert(!prompt.include?("wznieśiono"), "Polish spelling defect remains in #{question.fetch('id')}")
      assert(!prompt.match?(/jakie (?:jest obywatelstwo tej osoby|obywatelstwo ma ta osoba|ma obywatelstwo)\?/i),
        "Polish citizenship prompt was not made time-neutral for #{question.fetch('id')}")
      assert(!prompt.match?(/ — w jakim klubie (?:gra|trenuje)\?\z/i),
        "undated current-club question remains in #{question.fetch('id')}")
    end
  end

  pack = GameRoomContent.registry.pack(pack_id)
  assert(pack.data.fetch("questions").length == actual.length, "#{pack_id} lazy pack has the wrong count")
  assert(pack.verified?, "#{pack_id} checksum was not verified")
end

assert(all_original_ids.uniq.length == all_original_ids.length, "an original ID occurs in more than one source pack")
assert(all_original_ids.length == 50_574, "the audit does not cover all 50,574 original questions")

witcher = GameRoomContent::WitcherPolishMediumData.load
retained_witcher = definitions.fetch("quiz.witcher.pl").fetch(:questions).call
retained_ids = retained_witcher.map { |question| question.fetch("id") }
assert(witcher.fetch("version") == 6, "the Witcher medium map was not advanced to version 6")
assert(witcher.fetch("media").keys.sort == retained_ids.sort, "the Witcher medium map does not cover the retained source")
assert(witcher.fetch("media").values.all? { |code| %w[g b s].include?(code) }, "the Witcher medium map has an invalid code")

games = GameRoomContent.registry.pack("quiz.witcher.g.pl").data.fetch("questions")
books_screen = GameRoomContent.registry.pack("quiz.witcher.b.pl").data.fetch("questions")
assert((games.map { |q| q.fetch("id") } & books_screen.map { |q| q.fetch("id") }).empty?, "the Witcher views overlap")
assert((games + books_screen).map { |q| q.fetch("id") }.sort == retained_ids.sort, "the Witcher views are not a partition")

puts "Quiz factual audit tests passed: every original ID has one decision, retained data match it, checksums load, and Witcher views partition the audited source"
