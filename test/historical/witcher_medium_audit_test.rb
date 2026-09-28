# encoding: UTF-8
require_relative '../support/historical_quiz_evidence'
HistoricalQuizEvidence.require_files!
require 'json'
require_relative '../../content/languages'
require_relative '../../content/quiz_witcher_pl'
require_relative '../../content/quiz_witcher_pl_medium_data'

def assert(condition, message)
  raise message unless condition
end

root = File.expand_path('../..', __dir__)
full_questions = GameRoomContent.registry.pack('quiz.witcher.pl').data.fetch('questions')
game_questions = GameRoomContent.registry.pack('quiz.witcher.g.pl').data.fetch('questions')
book_screen_questions = GameRoomContent.registry.pack('quiz.witcher.b.pl').data.fetch('questions')
audit_path = HistoricalQuizEvidence.path('quiz-factual-audit-220/WITCHER_FINAL_DECISIONS.json')
audit = JSON.parse(File.read(audit_path, encoding: 'UTF-8'))
recovery_path = HistoricalQuizEvidence.path('quiz-recovery-audit-after-221/ALL_RECHECK_DECISIONS.json')
recovery = JSON.parse(File.read(recovery_path, encoding: 'UTF-8'))
restored_decisions = recovery.fetch('decisions').select do |row|
  row.fetch('pack_id') == 'quiz.witcher.pl' && row.fetch('decision') == 'restore'
end
retained_decisions = audit.fetch('decisions').reject { |row| row.fetch('decision') == 'remove' } + restored_decisions
retained_by_id = retained_decisions.to_h { |row| [row.fetch('id'), row] }
forum_corrections = JSON.parse(File.read(File.join(root, 'docs/QUIZ_FORUM_CORRECTIONS_239.json'), encoding: 'UTF-8')).fetch('quiz.witcher.pl').to_h { |row| [row.fetch('id'), row] }
forum_corrections.each_value do |correction|
  row = retained_by_id.fetch(correction.fetch('id'))
  assert(row.fetch('reviewed') == correction.fetch('before'), 'Forum correction lost its audited baseline')
  row['reviewed'] = correction.fetch('after')
end
semantic_corrections = JSON.parse(File.read(File.join(root, 'docs/QUIZ_SEMANTIC_CORRECTIONS_239.json'), encoding: 'UTF-8')).fetch('changes')
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
expected_media = retained_by_id.values.group_by { |row| row.fetch('medium') }.transform_values(&:length)
assert(full_questions.length == retained_by_id.length, 'the full Witcher set does not match the factual audit and corrections')
assert(game_questions.length == expected_media.fetch('g'), 'the game set has the wrong size')
assert(book_screen_questions.length == expected_media.fetch('b', 0) + expected_media.fetch('s', 0), 'the books and screen set has the wrong size')
classification = GameRoomContent::WitcherPolishMediumData.load
assert(classification.fetch('media').values.tally == expected_media, 'the reviewed medium totals do not match the audit')
full_questions.each do |question|
  expected = retained_by_id.fetch(question.fetch('id')).fetch('reviewed')
  assert(question == expected, "the source differs from the reviewed audit decision for #{question.fetch('id')}")
end
puts 'Historical Witcher audit: original decisions, restoration, subsequent corrections, exact questions and medium totals passed'
