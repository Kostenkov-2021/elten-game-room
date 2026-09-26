# encoding: UTF-8
$LOAD_PATH.unshift(File.expand_path("..", __dir__))

def _(text)
  text
end

def p_(_context, text)
  text
end

require "json"
require_relative "../lib/game_content"
require_relative "../content/languages"
require_relative "../content/quiz_general_en"
require_relative "../content/quiz_pl_wikidata"
require_relative "../content/quiz_witcher_pl"

def assert(condition, message)
  raise message unless condition
end

root = File.expand_path("..", __dir__)
base_root = File.expand_path("../diagnostics/quiz-factual-audit-220", root)
recovery_root = File.expand_path("../diagnostics/quiz-recovery-audit-after-221", root)
recovery = JSON.parse(File.read(File.join(recovery_root, "ALL_RECHECK_DECISIONS.json"), encoding: "UTF-8"))
rows = recovery.fetch("decisions")
semantic_corrections = JSON.parse(File.read(File.join(root, 'docs/QUIZ_SEMANTIC_CORRECTIONS_239.json'), encoding: 'UTF-8')).fetch('changes')

assert(rows.length == 20_730, "the second audit does not cover all previously removed questions")
keys = rows.map { |row| [row.fetch("pack_id"), row.fetch("id")] }
assert(keys.uniq.length == keys.length, "the second audit contains duplicate decisions")

base_files = {
  "quiz.general.en" => "ENGLISH_FINAL_DECISIONS.json",
  "quiz.wikidata.pl" => "POLISH_FINAL_DECISIONS_MERGED.json",
  "quiz.witcher.pl" => "WITCHER_FINAL_DECISIONS.json"
}
base_files.each do |pack_id, filename|
  base = JSON.parse(File.read(File.join(base_root, filename), encoding: "UTF-8"))
  removed = base.fetch("decisions").select { |row| row.fetch("decision") == "remove" }.map { |row| row.fetch("id") }
  reviewed = rows.select { |row| row.fetch("pack_id") == pack_id }
  assert(reviewed.map { |row| row.fetch("id") }.sort == removed.sort, "#{pack_id} has incomplete recovery coverage")

  pack = GameRoomContent.registry.pack(pack_id)
  data_ids = pack.data.fetch("questions").map { |question| question.fetch("id") }
  restored = reviewed.select { |row| row.fetch("decision") == "restore" }
  still_removed = reviewed.select { |row| row.fetch("decision") == "remain_removed" }
  subsequently_removed = semantic_corrections.select { |row| row.fetch('pack_id') == pack_id && !row.fetch('after') }.map { |row| row.fetch('id') }
  assert((restored.map { |row| row.fetch("id") } - subsequently_removed - data_ids).empty?, "#{pack_id} did not restore every still-approved question")
  assert((subsequently_removed & data_ids).empty?, "#{pack_id} retained a subsequently rejected question")
  assert((still_removed.map { |row| row.fetch("id") } & data_ids).empty?, "#{pack_id} made a quarantined question playable")
  restored.each do |row|
    question = row.fetch("reviewed")
    assert(question.fetch("id") == row.fetch("id"), "#{pack_id} changed an ID while restoring")
    assert(!Array(row["evidence"]).empty?, "#{pack_id} restored a question without evidence")
    answers = [question.fetch("correct"), *question.fetch("wrong")]
    normalized = answers.map { |answer| UnicodeNormalize.normalize(answer, :nfkc).downcase.strip }
    assert(normalized.uniq.length == normalized.length, "#{pack_id}/#{row.fetch('id')} has duplicate answers")
  end
  expected_version = pack_id == "quiz.general.en" ? 4 : 6
  assert(pack.version == expected_version && pack.verified?, "#{pack_id} data version or checksum is invalid")
end

# This question illustrates why textual containment cannot decide the result:
# the declared correct answer is "Paul", while "John and Paul" is a distractor.
# Its wording does not distinguish sole composition from formal song credit, so
# this exact item remains quarantined. A different, precise question could make
# either the shorter or the broader answer uniquely correct.
logical_trap = rows.find { |row| row.fetch("id") == "aaaf844bf311" }
assert(logical_trap && logical_trap.fetch("decision") == "remain_removed", "a logical answer-overlap trap was restored")

puts "Quiz recovery audit tests passed: all 20,730 rejections reconsidered, approved restorations loaded, and quarantined IDs excluded"
