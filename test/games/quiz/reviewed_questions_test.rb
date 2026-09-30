# encoding: UTF-8
require_relative "../../../content/languages"
require_relative "../../../content/quiz_pl_wikidata"
require_relative "../../../content/quiz_witcher_pl"
def assert(value, message); raise message unless value; end
expected = {'quiz.wikidata.pl' => 11083, 'quiz.witcher.pl' => 5132,
  'quiz.witcher.g.pl' => 2668, 'quiz.witcher.b.pl' => 2464}
data = expected.to_h do |id, count|
  pack = GameRoomContent.registry.pack(id)
  questions = pack.data.fetch('questions')
  ids = questions.map { |question| question.fetch('id') }
  assert(pack.version == 6 && pack.verified?, "#{id}: version/checksum")
  assert(ids.length == count && ids.uniq == ids, "#{id}: count/duplicate IDs")
  [id, questions.to_h { |question| [question.fetch('id'), question] }]
end
all, games, books = data.values_at('quiz.witcher.pl', 'quiz.witcher.g.pl', 'quiz.witcher.b.pl')
assert((games.keys & books.keys).empty? && (games.keys + books.keys).sort == all.keys.sort, 'Incomplete/overlapping medium partition')
(games.merge(books)).each { |id, question| assert(question == all[id], 'Full/detail wording differs') }
general = data.fetch('quiz.wikidata.pl')
assert(general['34cc7fbe233b']['correct'] == 'Frigg' && general['34cc7fbe233b']['prompt'].include?('żoną'), 'Odin ambiguity returned')
assert(general['43196e358538']['correct'] == 'tężec' && general['43196e358538']['prompt'].include?('pomocniczo'), 'Valid adjunct indication removed')
assert(general['dc01f86efbb5']['prompt'].include?('Kolumb'), 'Missing Virgin Islands event')
%w[755215bfb62a 7843ccb89aeb].each { |id| assert(general[id]['category'] == 'chemia' && general[id]['prompt'].include?('pierwiastek'), 'Sulphur classified as discovery') }
%w[74a52fd22210 b22e943857b8 7b0b05c80ea6].each { |id| assert(books.key?(id), 'Loredo book village moved into games') }
assert(books['74a52fd22210']['correct'] == 'wieś' && !books['74a52fd22210']['wrong'].include?('wioska'), 'Two synonymous correct choices')
%w[7a193c109c77 7bfa3a3165f8 86277e2087bb].each { |id| assert(games[id]['prompt'].include?('Carys') && games[id]['prompt'].include?('Hail'), 'Carys confused with Cerys') }
%w[86185faaec88 33a78b6ff1ee].each { |id| assert(games[id]['correct'] == 'GWINT: Wiedźmińska Gra Karciana', 'Valid Gwent answer replaced') }
puts 'Forum quiz fixes: four checksums, stable counts/IDs, full/detail agreement and 14 reviewed questions: OK'
