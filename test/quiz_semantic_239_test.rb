# encoding: UTF-8
require 'json'
require 'digest'
require 'uri'
require_relative '../content/languages'
require_relative '../content/quiz_general_en'
require_relative '../content/quiz_pl_wikidata'
require_relative '../content/quiz_witcher_pl'
require_relative '../content/quiz_witcher_pl_medium_data'

def assert(value, message); raise message unless value; end
root = File.expand_path('..', __dir__)
report = JSON.parse(File.read(File.join(root, 'docs/QUIZ_SEMANTIC_CORRECTIONS_239.json'), encoding: 'UTF-8'))
summary = report.fetch('summary')
changes = report.fetch('changes')
assert(changes.map { |r| r.fetch('id') }.uniq.size == changes.size, 'Duplicate semantic decisions')
assert(changes.size == summary.fetch('reviewed_decisions'), 'Incomplete report')
assert(changes.count { |r| !r.fetch('after') } == summary.fetch('removed_questions'), 'Removal count mismatch')
packs = summary.fetch('counts').to_h { |id, _| [id, GameRoomContent.registry.pack(id)] }
assert(packs.values.none?(&:verified?), 'Quiz registration should remain lazy')
data = packs.to_h do |id, pack|
  qs = pack.data.fetch('questions')
  indexed = qs.to_h { |q| [q.fetch('id'), q] }
  assert(qs.size == summary.fetch('counts').fetch(id) && pack.entry_count == qs.size, "Wrong count: #{id}")
  assert(indexed.size == qs.size, "Duplicate IDs: #{id}")
  assert(pack.version == (id == 'quiz.general.en' ? 4 : report.fetch('data_version')) && pack.verified?, "Version/checksum: #{id}")
  assert(pack.checksum == summary.fetch('checksums').fetch(id), "Unexpected checksum: #{id}") unless id == 'quiz.general.en'
  qs.each do |q|
    assert(q.fetch('prompt').valid_encoding? && !q.fetch('prompt').strip.empty?, 'Invalid prompt')
    options = [q.fetch('correct'), *q.fetch('wrong')]
    normalized = options.map { |s| UnicodeNormalize.normalize(s, :nfkc).strip.downcase }
    assert(normalized.size == 4 && normalized.uniq.size == 4 && normalized.none?(&:empty?), "Invalid choices: #{q['id']}")
  end
  [id, indexed]
end
media = GameRoomContent::WitcherPolishMediumData.load
changes.each do |r|
  id, after = r.fetch('id'), r.fetch('after')
  current = data.fetch(r.fetch('pack_id'))
  assert(!r.fetch('reason').strip.empty?, "Missing reason: #{id}")
  assert(!r.fetch('sources').empty?, "Missing sources: #{id}")
  r.fetch('sources').each do |source|
    url = URI.parse(source.fetch('url'))
    assert(url.scheme == 'https' && url.host && !url.host.empty?, "Invalid evidence URL: #{id}")
  end
  if after
    assert(current.fetch(id) == after, "Correction not applied: #{id}")
    assert(after.reject { |k, _| %w[prompt correct wrong].include?(k) } == r.fetch('before').reject { |k, _| %w[prompt correct wrong].include?(k) }, "Metadata changed: #{id}")
    assert(media.fetch('media').fetch(id) == r.fetch('medium_after'), "Medium not updated: #{id}") if r.key?('medium_after')
  else
    assert(!current.key?(id), "Rejected question remains: #{id}")
    assert(!media.fetch('media').key?(id), "Rejected medium remains: #{id}") if r.fetch('pack_id') == 'quiz.witcher.pl'
  end
end
all, games, books = data.values_at('quiz.witcher.pl', 'quiz.witcher.g.pl', 'quiz.witcher.b.pl')
assert((games.keys & books.keys).empty? && (games.keys + books.keys).sort == all.keys.sort, 'Witcher partition is incomplete')
assert(all == games.merge(books), 'Witcher question content differs between full and detailed sets')
assert(media.fetch('source_question_count') == all.size && media.fetch('media').keys.sort == all.keys.sort, 'Stale medium map')
assert(media.fetch('prompts').empty?, 'Do not maintain conflicting wording overlays')
%w[content/quiz_general_en.rb content/quiz_general_en_data.rb].each do |path|
  assert(Digest::SHA256.file(File.join(root, path)).hexdigest == report.fetch('baseline_sha256').fetch(path), 'English questions changed unintentionally')
end

# Regression cases: a named relationship, conditional game outcome, source
# medium, non-drug therapy, historical origin and an unsupported claim.
general = data.fetch('quiz.wikidata.pl')
assert(general.values.none? { |q| q['prompt'].include?('obywatelstwo przypisano') }, 'Vague citizenship template remains')
assert(all.values.none? { |q| q['prompt'].match?(/z którą.*powiązana ta postać/) }, 'Vague relationship template remains')
assert(general['f5716d4f4e58']['prompt'].include?('pochodził James Watt'), 'Origin confused with citizenship')
assert(general['a707edc4e80a']['prompt'].include?('poznawczo-behawioraln') && !general['a707edc4e80a']['prompt'].start_with?('Lek '), 'Therapy called a drug')
assert(!general.key?('09559cfc46fe'), 'False medical premise returned')
assert(general['97ad565f0400']['prompt'].include?('Teogonii'), 'Myth tradition left ambiguous')
assert(books['6954116f2096'] == nil && games['6954116f2096']['prompt'].include?('Krew i Wino'), 'Adela Marta confused with the story The Bounds of Reason')
assert(books['50798ae287af']['prompt'].include?('serialu Netflixa'), 'Actor still in game-only set')
assert(games.values.any? { |q| q['correct'] == 'Lambert' && q['prompt'].include?('Keira Metz może') }, 'Conditional romance presented as certain')
comic_relations = changes.select { |r| r['family'] == 'witcher_relation' && r['after'] && r['after']['prompt'].start_with?('Ostrit —', 'Merwina —') }
assert(comic_relations.size == 2 && comic_relations.all? { |r| r['after']['prompt'].include?('Klątwa kruków') }, 'Comic relationship assigned to the wrong comic')
assert(all.values.select { |q| q['prompt'].include?('Hanna, chłopka') }.all? { |q| !q['prompt'].include?('Krew i Wino') }, 'Hanna assigned to the wrong game')
puts "Quiz semantic corrections: #{changes.size} decisions, preserved identities, evidence, English unchanged, complete lazy Witcher views: OK"
