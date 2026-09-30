require_relative "../support/binary_rule_dictionary"

[:pl, :en, :fallback].each do |language|
  GameRoomTestLocalization.use_language(language)
  repository = TableActivityRepository.new(server_tables: {})
  entries = [
    TableActivityRepository::Entry.new(kind: 'options_changed', actor: 'Łucja'.b, owner: 'Łucja'.b,
      game: 'axel_pong', teams: [['Łucja'.b, 'Żaneta'.b], ['Ala'.b, 'Bob'.b]]),
    TableActivityRepository::Entry.new(kind: 'role_changed', actor: 'Łucja'.b, owner: 'Łucja'.b,
      game: 'axel_pong', subject: 'Żaneta'.b, role: 'observer')
  ]
  messages = entries.map { |entry| repository.text_for(entry, game_name: ->(id) { id }) }
  raise 'Binary team/role announcements have bad encoding' unless messages.all? { |m| m.encoding == Encoding::UTF_8 && m.valid_encoding? }
  raise 'Team members lost' unless messages.first.include?('Łucja, Żaneta') && messages.first.include?('Ala, Bob')
  expected = language == :pl ? ['Drużyna', 'obserwatora'] : ['Team', 'observer']
  raise 'Team/role localization ignored interface language' unless messages.zip(expected).all? { |m, word| m.include?(word) }
  edit = GameRoomParticipantMenu.entries.find { |e| e.action == :edit_teams }
  raise 'Team menu missing/untranslated' unless edit.label == (language == :pl ? 'Wybierz drużyny' : 'Choose teams')

  layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new,
    history_items: ['Żaneta: wiadomość'], phase: :waiting, own_table: true)
  layout.chat.text = 'Piszę wiadomość'
  layout.chat.restore_selection(index: 3, check: 7)
  layout.form.index = layout.form.fields.index(layout.chat)
  [:active, :finished, :active].each do |phase|
    layout.update(view_spec: GameRoomLayout::ViewSpec.new, history_items: ['Żaneta: wiadomość', 'Wynik'],
      user_items: [], users_header: '', phase: phase, own_table: true)
    raise 'Binary phase focus/caret regression' unless layout.focus_location == [:chat, 0] &&
      [layout.chat.text, layout.chat.index, layout.chat.check] == ['Piszę wiadomość', 3, 7]
  end
end
puts 'PASS binary PL/EN/fallback: team and role messages/menu, stable Unicode chat focus/caret'
