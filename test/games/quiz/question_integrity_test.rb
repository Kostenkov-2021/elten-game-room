# encoding: UTF-8
require 'json'
require_relative "../../../content/languages"
require_relative "../../../content/quiz_general_en"
require_relative "../../../content/quiz_pl_wikidata"
require_relative "../../../content/quiz_witcher_pl"
require_relative "../../../content/quiz_witcher_pl_medium_data"

def assert(value, message); raise message unless value; end
root = File.expand_path("../../..", __dir__)
reference = JSON.parse(File.read(File.join(root, 'test/fixtures/quiz/questions.json'), encoding: 'UTF-8'))
expected_packs = reference.fetch('packs')
packs = expected_packs.to_h { |id, _| [id, GameRoomContent.registry.pack(id)] }
assert(packs.values.none?(&:verified?), 'Quiz registration should remain lazy')
data = packs.to_h do |id, pack|
  qs = pack.data.fetch('questions')
  indexed = qs.to_h { |q| [q.fetch('id'), q] }
  assert(qs.size == expected_packs.fetch(id).fetch('count') && pack.entry_count == qs.size, "Wrong count: #{id}")
  assert(indexed.size == qs.size, "Duplicate IDs: #{id}")
  assert(pack.version == expected_packs.fetch(id).fetch('version') && pack.verified?, "Version/checksum: #{id}")
  assert(pack.checksum == expected_packs.fetch(id).fetch('checksum'), "Unexpected checksum: #{id}")
  qs.each do |q|
    assert(q.fetch('prompt').valid_encoding? && !q.fetch('prompt').strip.empty?, 'Invalid prompt')
    options = [q.fetch('correct'), *q.fetch('wrong')]
    normalized = options.map { |s| UnicodeNormalize.normalize(s, :nfkc).strip.downcase }
    assert(normalized.size == 4 && normalized.uniq.size == 4 && normalized.none?(&:empty?), "Invalid choices: #{q['id']}")
  end
  [id, indexed]
end
media = GameRoomContent::WitcherPolishMediumData.load
reference.fetch('excluded_ids').each do |pack_id, ids|
  ids.each do |id|
    assert(!data.fetch(pack_id).key?(id), "Rejected question remains: #{id}")
    assert(!media.fetch('media').key?(id), "Rejected medium remains: #{id}") if pack_id == 'quiz.witcher.pl'
  end
end
reference.fetch('medium').each do |id, expected|
  assert(media.fetch('media').fetch(id) == expected, "Unexpected medium: #{id}")
end
all, games, books = data.values_at('quiz.witcher.pl', 'quiz.witcher.g.pl', 'quiz.witcher.b.pl')
assert((games.keys & books.keys).empty? && (games.keys + books.keys).sort == all.keys.sort, 'Witcher partition is incomplete')
assert(all == games.merge(books), 'Witcher question content differs between full and detailed sets')
assert(media.fetch('source_question_count') == all.size && media.fetch('media').keys.sort == all.keys.sort, 'Stale medium map')
assert(media.fetch('prompts').empty?, 'Do not maintain conflicting wording overlays')
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
comic_relations = %w[85ec02362906 eb2bb9f3f506].map { |id| all.fetch(id) }
assert(comic_relations.size == 2 && comic_relations.all? { |q| q['prompt'].include?('Klątwa kruków') }, 'Comic relationship assigned to the wrong comic')
assert(all.values.select { |q| q['prompt'].include?('Hanna, chłopka') }.all? { |q| !q['prompt'].include?('Krew i Wino') }, 'Hanna assigned to the wrong game')
puts "Quiz question integrity: pinned content, excluded questions, classifications and complete lazy Witcher views: OK"
