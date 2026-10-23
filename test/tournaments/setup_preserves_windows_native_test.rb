require_relative '../support/tournament_individual_ui'
require_relative '../support/tournament_window_fields'
require File.join(EltenTestHost.root, 'src/ui/controls/static')
Object.const_set(:Static, EltenAPI::Controls.const_get(:Static)) unless Object.const_defined?(:Static)
require_relative '../../lib/tournaments/tournament_setup_editor'
require_relative '../../lib/tournaments/server_match_window'
include GameRoomTest::Assertions
T = GameRoomTournaments

def edit_windows(version:, mode:, language: 'en', timezone: 'UTC')
  fixture = TournamentIndividualUI.fixture
  program = fixture.fetch(:program)
  GameRoomLocalization.boot(settings: {'interface_language' => language, 'known_languages' => [language]})
  translate = ->(value) { GameRoomContent.utf8(GameRoomLocalization.translate(value)) }
  windows = [15, 16].map do |day|
    {'date' => "2026-10-#{day}", 'start' => '12:00', 'end_date' => "2026-10-#{day}", 'end' => '16:00'}
  end
  draft = {'name' => 'Existing windows', 'game_id' => 'tic_tac_toe', 'game_options' => {},
    'format' => 'round_robin', 'rematch' => false, 'players_per_match' => 2, 'pairing' => 'all_combinations',
    'participant_limit' => 16, 'participants' => [], 'windows' => windows}
  if version == 2
    draft.merge!('starts_at' => T::LocalRegistrationTime.convert_in_zone('2026-10-15', '12:00', timezone: timezone),
      'deadline_at' => T::LocalRegistrationTime.convert_in_zone('2026-10-16', '16:00', timezone: timezone))
  end
  row = T::Publication.from_draft(draft: draft, registry: GameRoomGames::CATALOG, publication_key: 'retained-windows',
    rules: 'Existing note', registration_opens_at: Time.utc(2026, 10, 10).to_i,
    registration_closes_at: Time.utc(2026, 10, 14).to_i, timezone: timezone).to_row
  assert_equal(version, row['schema_version'])
  original = JSON.generate(row)
  values = T::TournamentDatesEditor.values(row)
  values['windows'].first['start'] = '01:00'
  assert_equal(windows, T::TournamentTiming.schedule(row)['windows'], 'Extracting editor values mutated the publication')
  captured, alerts = nil, []
  editor = T::TournamentSetupEditor.new(program: program, registry: GameRoomGames::CATALOG,
    configure: ->(*) { raise 'Metadata edit requested game options' }, alert: ->(text) { alerts << text },
    clock: -> { Time.utc(2026, 10, 12, 12).to_i }, publication: row,
    publish: ->(**attributes) { captured = attributes; {'status' => 'confirmed'} })
  driver = TournamentNativeDriver.new
  driver.step(translate.call('Tournament name'), [13]) do |form|
    assert(form.is_a?(GameRoomUI::Form), 'Setup did not use the native form')
    editor.instance_variable_get(:@name).set_text('Renamed only')
    editor.instance_variable_get(:@organizer_notes).set_text('Updated note')
    target = mode == :untouched ? form.accept_button : TournamentIndividualUI::F.button(form, translate.call('Dates and playing hours'))
    form.index = form.fields.index(target)
  end
  unless mode == :untouched
    driver.step(translate.call('Dates and playing hours'), mode == :cancel ? [27] : [13]) do |form|
      keep = form.fields.grep(CheckBox).find { |field| field.label == translate.call('Keep existing playing windows') }
      limited = form.fields.grep(CheckBox).find { |field| field.label == translate.call('Limit playing hours') }
      assert(keep&.checked, 'Existing concrete playing windows were disabled on reopening')
      assert(!limited.checked, 'Concrete windows were reinterpreted as daily hours')
      description = TournamentIndividualUI::F.field(form, translate.call('Playing windows'))
      assert(description.text.include?('2026-10-15') && description.text.include?('2026-10-16'), 'The original schedule is not visible')
      case mode
      when :daily, :cancel
        limited.checked = true
        limited.trigger(:change)
        assert(!keep.checked, 'Choosing daily hours retained incompatible concrete windows')
        if mode == :cancel
          keep.checked = true
          keep.trigger(:change)
          assert(!limited.checked, 'Restoring concrete windows retained incompatible daily hours')
        end
      when :remove
        keep.checked = false
        keep.trigger(:change)
      when :registration
        opening = form.fields.grep(ListBox).find { |field| field.header == translate.call('Open registration') }
        opening.index = 2
        opening.trigger(:move)
      end
      form.index = form.fields.index(form.accept_button)
    end
    driver.step(translate.call('Tournament name'), [13]) { |form| form.index = form.fields.index(form.accept_button) }
  end
  assert_equal({'status' => 'confirmed'}, editor.wait)
  driver.finish
  assert_equal([], alerts)
  assert_equal(original, JSON.generate(row), 'The editor mutated its input publication')
  changed = T::Publication.from_draft(**captured.merge(registry: GameRoomGames::CATALOG, publication_key: 'retained-windows')).to_row
  schedule = T::TournamentTiming.schedule(changed)
  if [:daily, :remove].include?(mode)
    assert_equal([], schedule['windows'], 'An explicit schedule replacement was ignored')
    assert_equal('UTC', changed['timezone'])
    assert_equal(mode == :daily, schedule.key?('daily_hours'))
  else
    assert_equal(windows, schedule['windows'], "#{mode} erased or changed concrete windows")
    assert_equal(timezone, changed['timezone'], 'Retained civil windows changed their timezone')
    instant = T::LocalRegistrationTime.convert_in_zone('2026-10-15', '18:00', timezone: timezone)
    begin
      T::ServerMatchWindow.current(schedule.merge('timezone' => changed['timezone']), instant)
      raise 'Metadata/date editing opened a previously forbidden gap'
    rescue T::Publication::Invalid => error
      assert_equal(:outside_window, error.code)
    end
  end
  assert_equal(0, changed['registration_opens_at']) if mode == :registration
ensure
  program&.finalize
  program&.class&.app_runtime&.close
end

[1, 2].each do |version|
  %i[untouched cancel save registration remove daily].each { |mode| edit_windows(version: version, mode: mode) }
  %w[pl cs es ru].each { |language| edit_windows(version: version, mode: :save, language: language) }
  edit_windows(version: version, mode: :save, timezone: 'local_test:system')
end
puts 'PASS native edit retains schema1/2 concrete windows/timezone in five languages; cancel, date save, registration edit and explicit replacement'
