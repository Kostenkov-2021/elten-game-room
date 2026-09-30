require_relative "../../support/pong_ui"

def assert(value, message); raise message unless value; end

rules = GameRoomGames::AxelPong.new
repository = Object.new
def repository.players_for(session); session['__players']; end
def repository.actor_of(event, _session); event['actor']; end
def repository.event_id(event); event['__id']; end
names = ['Łucja', 'Żaneta', 'Ścibor', 'Józef']
options = rules.with_team_assignment({'team_size' => 2}, players: names, seats: [1, 0, 1, 0])
session = {'__players' => names.map(&:b), '__insertion_user' => 'Owner', 'options' => JSON.generate(options)}
events = 11.times.map { |i| {'__id' => i + 1, '__insertion_user' => 'Owner', 'action' => 'pong_point', 'value' => "#{i}:1"} }
dictionary, english = $rules_dictionary, $rules_english
previous_language = GameRoomTestLocalization.language
begin
  [:pl, :en, :fallback].each do |language|
    $rules_english = language == :en
    GameRoomTestLocalization.use_language(language)
    $rules_dictionary = language == :fallback ? BinaryRuleDictionary.new({}) : dictionary
    definitions = rules.option_definitions
    match_type = definitions.find { |definition| definition.key == 'team_size' }
    assert(match_type.label == (language == :pl ? 'Rodzaj meczu' : 'Match type'), "#{language}: untranslated match type")
    assert(match_type.choices.map(&:label) == (language == :pl ? %w[Singiel Debel] : %w[Single Doubles]), "#{language}: untranslated match choices")
    target = definitions.find { |definition| definition.key == 'target' }
    expected_targets = language == :pl ? ['Własna liczba', 'Nieskończony'] : ['Custom number', 'Unlimited']
    assert(target.choices.last(2).map(&:label) == expected_targets, "#{language}: untranslated point targets")
    custom = definitions.find { |definition| definition.key == 'custom_target' }
    assert(custom.label == (language == :pl ? 'Własna liczba punktów (2–999)' : 'Custom number of points (2-999)'), "#{language}: wrong custom edit label")
    custom_options = options.merge('target' => 'custom', 'custom_target' => 31)
    assert(rules.table_options_announcement(custom_options).include?('31'), "#{language}: Ctrl+R omits the custom target")
    error = rules.validation_error(custom_options.merge('custom_target' => 1000))
    assert(error == (language == :pl ? 'Wpisz całkowitą liczbę punktów od 2 do 999.' : 'Enter a whole number of points from 2 to 999.'), "#{language}: invalid target is not translated")
    assert([custom.label, error].all? { |text| text.encoding == Encoding::UTF_8 && text.valid_encoding? }, "#{language}: target strings have binary encoding")
    initial_announcement = _('%{variant}. %{difficulty}. Unlimited match.') % {variant: _('Classic'), difficulty: 'Normal'}
    assert(initial_announcement.include?(language == :pl ? 'Mecz nieskończony.' : 'Unlimited match.'), "#{language}: untranslated unlimited announcement")
    replay = rules.replay(session, events.take(3), repository)
    views = rules.game_shortcuts(replay, 'Watcher').select { |shortcut| shortcut.key.match?(/\A[1-4]\z/) }
    assert(views.map(&:key) == %w[1 2 3 4], "#{language}: missing individual spectator shortcuts")
    assert(views.all? { |shortcut| shortcut.label.encoding == Encoding::UTF_8 && shortcut.label.valid_encoding? }, "#{language}: spectator shortcut encoding")
    expected = language == :pl ? ['trzeciego gracza', 'czwartego gracza'] : ["third player's perspective", "fourth player's perspective"]
    expected.each_with_index do |text, i|
      assert(views[i + 2].label.include?(text), "#{language}: untranslated individual spectator shortcut")
    end
    spec = rules.surface_spec(replay, names[3].b)
    surface = GameSurfaces.build(spec)
    state = GameRoomPong::Engine.new(teams: [1, 0, 1, 0]).snapshot
    state['p'] = [4.0, 8.0, 12.0, 16.0]
    surface.present(state, 'Ready.')
    $spoken_messages.clear
    surface.handle_command('scores')
    text = $spoken_messages.last
    assert(text.encoding == Encoding::UTF_8 && text.valid_encoding?, "#{language}: binary doubles score encoding")
    assert(names.all? { |name| text.include?(name) }, "#{language}: the team score omitted a participant")
    assert(text.index(names[1]) < text.index(names[3]) && text.index(names[3]) < text.index(names[0]), "#{language}: team scores ignored chosen assignments")
    assert(text.include?(language == :pl ? 'Drużyna ' : 'Team '), "#{language}: untranslated team scores")
    surface.handle_command('server')
    assert($spoken_messages.last.include?(language == :pl ? 'będzie serwować do' : 'will serve against'), "#{language}: untranslated server/receiver announcement")
    %w[position effects].each { |command| surface.handle_command(command) }
    assert($spoken_messages.all? { |message| message.encoding == Encoding::UTF_8 && message.valid_encoding? }, "#{language}: binary doubles readout encoding")
    assert(replay.history.all? { |entry| entry.text.valid_encoding? }, "#{language}: binary doubles history encoding")
    before = rules.replay(session, events.take(10), repository)
    after = rules.replay(session, events, repository)
    names.each_with_index do |player, index|
      expected = [0, 2].include?(index) ? 'win_party' : 'lose_party'
      assert(GameRoomSounds.result_cue(rules, before, after, player.b) == expected, "#{language}: teammate received the wrong result sound")
    end
    assert(GameRoomSounds.result_cue(rules, before, after, 'Watcher') == nil, "#{language}: spectator received a participant result")
    assert(GameRoomSounds.result_cue(rules, after, after, names.first.b) == nil, "#{language}: duplicate result sound")
    assert(rules.result_text(after).encoding == Encoding::UTF_8 && rules.result_text(after).valid_encoding?, "#{language}: binary team result encoding")
  end
ensure
  $rules_dictionary, $rules_english = dictionary, english
  GameRoomTestLocalization.use_language(previous_language)
end
puts 'PASS binary doubles: native PL/EN/fallback dictionary, four non-ASCII names, team readouts/history and both partners result sounds'
