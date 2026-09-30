# Exercise the real wait -> Ctrl+F1 -> cleanup -> rules dialog sequence.
# The earlier live-help test opened the dialog before wait_for_action cleanup.
if ARGV.first || ENV["RULES_LIFECYCLE_BINARY_SOURCE"] == "1"
  require_relative "../support/binary_rule_dictionary"
else
  require_relative "../support/ui"
  class Program
    def self.server_app(**_options); end
  end
  require_relative "../../__app"
end
require_relative "../support/log"
require_relative "../support/localization"

module Session
  class << self
    attr_accessor :help_test_user
    def name; help_test_user || "Alice"; end
  end
end

class FormTimer
  def initialize(_interval, repeat:, &callback); @callback = callback; end
  def fire; @callback.call; end
end

class Form
  class << self; attr_accessor :help_lifecycle_driver; end
  def wait; Form.help_lifecycle_driver.call(self); end
  def keyboard_idle_frame?; true; end
  def resume; end
  def focus(*_args); fields[index.to_i]&.focus; end
end

class HelpLifecycleRepository
  def initialize; @controller = GameRoomBots::TurnController.new; end
  def players_for(_session); %w[Alice Bob]; end
  def session_id(session); session.fetch("__id"); end
  def bot_turn_controller(_table); @controller; end
  def append_events(**_options); raise "Reading help submitted a move"; end
end

def assert(value, message); raise message unless value; end

def help_screen(game, viewer = "Alice")
  Session.help_test_user = viewer
  options = game.default_options
  session = { "__id" => 101, "options" => JSON.generate(options) }
  table = { "__id" => 102, "owner" => "Alice", "game" => game.id,
    "status" => "playing", "max_players" => game.maximum_players,
    "game_options" => JSON.generate(options), "name" => "Help test" }
  room = LobbyRepository::TableSnapshot.new(table: table, members: %w[Alice Bob Observer], bots: [])
  sync = Object.new
  sync.define_singleton_method(:recovery_pending?) { false }
  GameScreen.new(program: Object.new, repository: HelpLifecycleRepository.new,
    game: game, session: session, table: table, table_owner: "Alice",
    room_snapshot_provider: -> { room }, synchronizer: sync)
end

def help_replay(game, phase: :playing)
  state = game.send(:initial_state, %w[Alice Bob], game.default_options)
  state.update(phase: phase, current_player: "Alice")
  case game.id
  when "scrabble"
    state.update(racks: { "Alice" => (0...7).to_a, "Bob" => (7...14).to_a }, bag: (14...100).to_a)
  when "makao"
    state.update(hands: { "Alice" => %w[9H 9S AS], "Bob" => %w[2S] }, discard: ["8H"])
  when "poker"
    state[:hands] = { "Alice" => %w[9H 9S AS 2D 3C], "Bob" => %w[2S 3S 4S 5S 6S] }
  end
  GameRoomGames::Replay.new(players: state[:players], current_player: "Alice",
    state: state, history: [], accepted_events: [])
end

def open_shortcuts_after_wait(screen, replay, focus: :game, via_menu: false, close_with: :enter)
  expected = before = layout = nil
  Form.help_lifecycle_driver = lambda do |form|
    layout = screen.instance_variable_get(:@layout)
    field = { game: layout.game_help_fields.first, chat: layout.chat,
      history: layout.history, users: layout.users }.fetch(focus)
    form.index = form.fields.index(field)
    layout.chat.text = "Preserved draft ąę"
    layout.chat.index, layout.chat.check = 5, 2
    expected = GameRoomContextHelp.game_field_tips(layout.game_help_fields)
    assert(!expected.empty?, "#{screen.instance_variable_get(:@game).id}: fixture has no help")
    assert(expected.uniq == expected, "Duplicate game shortcuts")
    assert(expected.none? { |tip| tip.match?(/Ctrl\+F1|Ctrl\+I|Ctrl\+R|Shift\+F2|Chat|czat/i) }, "Non-game help leaked")
    before = Marshal.dump([replay, layout.surface.state, form.index,
      layout.chat.text, layout.chat.index, layout.chat.check, layout.history.index])
    if via_menu
      menu = FakeMenu.new
      form.context(menu, false)
      menu.options.find { |option| option[0] == GameRoomLocalization.translate("Game rules") }[3].call
    else
      form.trigger(:key_f1, [false, true, false])
    end
  end
  assert(screen.send(:wait_for_action, replay, [0, 0]) == :rules, "Ctrl+F1 did not leave wait with :rules")
  # Help is nonblocking: keep the owning view alive so its session still
  # advances behind the document. Rebinding must replace, not duplicate tips.
  assert(!layout.form.instance_variable_get(:@timers).empty?, "Help stopped gameplay progress")
  assert(GameRoomContextHelp.game_field_tips(layout.game_help_fields) == expected, "Help changed the owning view bindings")
  stage = 0
  shown = nil
  Form.help_lifecycle_driver = lambda do |form|
    field = (form.fields - form.hidden_controls).first
    assert(field.is_a?(ListBox), "Shortcuts are not an arrow-key list")
    case stage
    when 0
      assert(field.options.length == 3, "Rules picker lost rules, shortcuts or table settings")
      field.index = 1
      form.accept_button.trigger(:press)
    when 1
      shown = field.options.dup
      assert(form.accept_button.equal?(form.cancel_button), "Enter and Escape differ")
      (close_with == :enter ? form.accept_button : form.cancel_button).trigger(:press)
    when 2
      assert(field.index == 1, "Returning from shortcuts moved the document selection")
      form.cancel_button.trigger(:press)
    else
      raise "Help did not close"
    end
    stage += 1
  end
  screen.send(:show_game_rules, replay)
  while (help_form = layout.form.game_room_background_help_form)
    Form.help_lifecycle_driver.call(help_form)
    if stage == 2
      # The nonblocking picker stays alive underneath the document rather
      # than being reconstructed by another nested modal wait.
      assert(layout.form.game_room_background_help_form.fields.first.index == 1,
        'Returning from shortcuts moved the document selection')
    end
  end
  assert(shown == expected, "#{screen.instance_variable_get(:@game).id}: shortcut descriptions vanished between Ctrl+F1 and the rules dialog (expected #{expected.length}, got #{shown.inspect})")
  after = Marshal.dump([replay, layout.surface.state, layout.form.index,
    layout.chat.text, layout.chat.index, layout.chat.check, layout.history.index])
  assert(after == before, "Help changed the game, cursor, draft or chat")
  assert(screen.instance_variable_get(:@rules_shortcut_snapshot) == nil, "Help retained a stale snapshot")
  if defined?(BinaryRulesLoad)
    role = $rules_english ? " — справка" : " — lista"
    assert(shown.all? { |text| (text + role).valid_encoding? }, "Mixed binary/UTF-8 shortcut rows")
  end
  shown
ensure
  Form.help_lifecycle_driver = nil
end

languages = defined?(BinaryRulesLoad) ? %w[en pl fallback] : %w[en]
cases = 0
languages.each do |language|
  $rules_english = language != "pl"
  GameRoomTestLocalization.use_language(language)
  game = GameRoomGames::Scrabble.new
  replay = help_replay(game)
  %w[Alice Bob Observer].each do |viewer|
    screen = help_screen(game, viewer)
    %i[game chat history users].each_with_index do |focus, index|
      open_shortcuts_after_wait(screen, replay, focus: focus, via_menu: index.odd?, close_with: index.odd? ? :escape : :enter)
      cases += 1
    end
  end
  # Finished boards still have game-field help; no obsolete turn metadata.
  replay.winner = "Alice"
  open_shortcuts_after_wait(help_screen(game), replay)
  cases += 1

  [GameRoomGames::Makao.new, GameRoomGames::Poker.new].each do |card_game|
    phase = card_game.id == "poker" ? :exchange : :playing
    current = help_replay(card_game, phase: phase)
    screen = help_screen(card_game)
    first = open_shortcuts_after_wait(screen, current)
    assert(first.any? { |tip| tip.include?("Shift+Enter") }, "Native packet help lost")
    # Fresh definitions on the same screen must replace, not accumulate.
    card_game.define_singleton_method(:game_shortcuts) do |_replay, _viewer|
      [GameRoomGames::GameShortcut.new(key: "y", label: "New phase only", kind: :announcement, message: "New phase")]
    end
    second = open_shortcuts_after_wait(screen, current, via_menu: true, close_with: :escape)
    assert(second.any? { |tip| tip.include?("New phase only") }, "New phase help not captured")
    assert(second.none? { |tip| tip.include?("Press T ") }, "Old phase help accumulated")
    cases += 2
  end
end
Session.help_test_user = nil
puts "PASS rules help lifecycle: #{cases} Ctrl+F1/menu transitions, Scrabble players/observer/finished board, native packet help, phase replacement, timer cleanup and preserved state/chat/focus"
