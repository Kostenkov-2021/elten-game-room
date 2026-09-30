require_relative "../support/binary_rule_dictionary"
require_relative "../../lib/game_history_view"

def assert(value, message); raise message unless value; end

%w[pl en fallback].each do |language|
  $rules_english = language != 'pl'
  GameRoomTestLocalization.use_language(language)
  view = GameRoomHistory::View.new(header: 'Historia żółtego stołu'.b)
  texts = ["Żaneta: pierwszy\nwiadomość w dwóch wierszach", 'Łukasz: drugi', 'koniec']
  entries = texts.each_with_index.map { |text, i| GameRoomHistory::Entry.new(text: text, category: [:chat, :game, :room][i]) }
  view.replace_entries(texts.map(&:b))
  assert(view.text == texts.join("\n") && view.entry_index == 2, 'history text/offsets/encoding')
  assert((view.header + ' — поле').valid_encoding?, 'history binary heading')
  view.entry_index = 0
  view.index, view.check = 3, 9
  view.replace_entries(texts + ['nowy'])
  assert([view.index, view.check] == [3, 9], 'append lost native selection')
  view.replace_entries(['wcześniejszy'] + texts + ['nowy'])
  assert(view.text[view.index...view.check] == texts.first[3...9], 'insert lost selected entry')
  view.replace_entries(texts)
  view.entry_index = 2
  view.replace_entries(texts + ['najnowszy'])
  assert(view.entry_index == 3 && view.index == view.check, 'history stopped following newest entry')
  view.replace_entries(texts)
  navigator = GameRoomHistory::Navigator.new
  chat = EditBox.new('Chat', text: 'draft . , <>')
  form = GameSurfaces::RefreshAwareForm.new([Button.new('Play'), view, chat], quiet: true)
  form.extend(GameRoomLayout::ShortcutFormBehavior)
  spoken = []
  GameRoomHistory.bind(form) do |operation, value|
    spoken << navigator.navigate(entries, operation, value, view: view, focused: form.index == 1)
  end
  form.held_modifiers = [:main_modifier]
  assert(!form.key_processed(:key_comma), 'Ctrl+comma blocked')
  form.trigger(:key_comma, [false, true, false])
  form.trigger(:key_comma, [false, true, false])
  assert(spoken.last == texts[1] && form.index == 0, 'quick history changed focus or skipped entry')
  form.trigger(:key_home, [false, true, false])
  assert(spoken.last == texts[0], 'multiline event not read whole')
  form.trigger(:key_period, [true, true, false])
  form.trigger(:key_end, [false, true, false])
  assert(spoken.last == texts[1], 'Ctrl+End ignored selected category')
  form.index = 1
  form.trigger(:key_home, [false, true, false])
  assert(view.entry_index == 1 && view.index == view.check, 'history jump did not align text cursor')
  form.trigger(:'key_>', [true, true, false])
  form.trigger(:key_end, [false, true, false])
  assert(spoken.last == texts[0], 'shifted punctuation/category alias failed')
  form.index = 2
  chat.index, chat.check = 2, 5
  original = [chat.text, chat.index, chat.check, form.index]
  before = spoken.length
  %w[comma period].each do |key|
    assert(!form.key_processed("key_#{key}".to_sym), 'history punctuation blocked in chat')
    form.trigger("key_#{key}".to_sym, [false, true, false])
    form.trigger("key_#{key}".to_sym, [true, true, false])
  end
  assert(spoken.length == before + 4, 'history shortcuts missing while writing')
  assert([chat.text, chat.index, chat.check, form.index] == original, 'history changed chat draft/selection/focus')
  before = spoken.length
  %w[home end].each do |key|
    assert(form.key_processed("key_#{key}".to_sym), 'native text navigation intercepted')
    form.trigger("key_#{key}".to_sym, [false, true, false])
  end
  assert(spoken.length == before, 'Home/End stopped belonging to the editor')
  assert(form.game_room_general_help_tips.length == 6 && form.game_room_general_help_tips.uniq.length == 6, 'one shortcut per help line')
  assert(form.game_room_general_help_tips.all? { |tip| language != 'pl' || !tip.include?('read the') }, 'history help untranslated')
end
puts 'PASS history text: binary PL/EN, multiline events, selection/insert/tail, categories, punctuation aliases, focus and chat scope'

view = GameRoomHistory::View.new
texts = ['earlier', 'same', 'same', 'last']
view.replace_entries(texts)
view.entry_index = 2
selection = [view.index, view.check]
normalizations = 0
normalize = GameRoomContent.method(:utf8)
GameRoomContent.define_singleton_method(:utf8) { |value| normalizations += 1; normalize.call(value) }
view.replace_entries(texts.map(&:dup))
assert(normalizations.zero? && [view.index, view.check] == selection, 'unchanged normalized entries rebuilt history')
texts[0].replace('corrected earlier')
view.replace_entries(texts)
assert(view.items.first == 'corrected earlier' && view.entry_index == 2, 'same-array prefix correction lost history/duplicate anchor')
texts[0].replace('changed again outside view')
assert(view.items.first == 'corrected earlier', 'history retained caller-owned text')
view.replace_entries(["binary\r\nentry\n".b])
assert(view.items == ["binary\nentry"] && view.items.first.encoding == Encoding::UTF_8, 'normalization skipped for changed input')
GameRoomContent.define_singleton_method(:utf8, normalize)
puts 'PASS history value reuse: no normalization on equal values, same-array corrections, duplicate anchors and caller ownership'
