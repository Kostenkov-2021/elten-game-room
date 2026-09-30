require_relative "../support/binary_rule_dictionary"

def assert(condition, message)
  raise message unless condition
end

class GameRoomUI::Form
  class << self; attr_accessor :feedback_driver; end
  def wait
    self.class.feedback_driver.call(self)
  end
  def resume; end
end

%w[pl en fallback].each do |language|
  $rules_english = language != "pl"
  GameRoomTestLocalization.use_language(language)
  game = GameRoomGames::Monopoly.new
  state = game.send(:initial_state, ["Żaneta", "Łukasz"], game.default_options)
  state[:owners].merge!(1 => "Żaneta", 3 => "Żaneta", 12 => "Łukasz")
  state[:houses][1] = 2
  state[:cash]["Żaneta"] = 5000
  state[:houses][3] = 2
  replay = GameRoomGames::Replay.new(state: state, players: state[:players], current_player: "Żaneta")
  shortcuts = game.custom_game_shortcuts(replay, "Żaneta")
  own = shortcuts.find { |s| s.key == "v" && s.modifiers.empty? }
  board = shortcuts.find { |s| s.key == "d" && s.modifiers == [:shift] }
  all = board.choices.map(&:label) + own.choices.flat_map { |c| [c.label] + c.value.map(&:label) }
  all.each { |text| assert((text + " — słowo").valid_encoding?, "Bad property encoding in #{language}") }
  assert(own.choices.first.label.include?(language == "pl" ? "grupa 2 z 2" : "group 2 of 2"), "Untranslated group count")
  rent = language == "pl" ? "Odwiedzający płaci 30 graczowi Żaneta." : "Visitors pay 30 to Żaneta."
  assert(own.choices.first.value.first.label == rent, "Wrong rent wording: #{own.choices.first.value.first.label}")
  visits = 0
  GameRoomUI::Form.feedback_driver = lambda do |form|
    visits += 1
    if visits == 1
      form.fields.first.trigger(:select)
    else
      assert(visits == 2 && form.fields.first.options == [rent], "Enter did not open the rent details")
    end
    form.cancel_button.trigger(:press)
  end
  screen = GameScreen.allocate
  assert(screen.send(:activate_game_shortcut, own) == nil && visits == 2, "Inspection tried to submit a game action")
  history = []
  repository = Object.new
  repository.define_singleton_method(:event_id) { |event| event["id"] }
  event = {"id" => 3, "action" => "build", "value" => "1"}
  assert(game.send(:apply_property_action, state, event, "Żaneta", repository, history), "Could not build fixture")
  assert(history.first.text.include?(language == "pl" ? "buduje trzeci dom" : "builds the third house"), "Ordinal was not translated")
  assert((history.first.text + " — dom").valid_encoding?, "Binary build announcement")

  fleet = GameRoomGames::Battleship.new
  empty = GameRoomGames::Replay.new(state: fleet.send(:initial_state, ["Żaneta", "Łukasz"], fleet.default_options))
  surface = GameSurfaces.build(fleet.surface_spec(empty, "Żaneta"))
  prompt = surface.take_cursor_announcement(0)
  assert((prompt + " — flota").valid_encoding?, "Binary setup prompt")
  seal = GameRoomGames::HistoryEntry.new(key: "seal:4", text: "sealed", event_id: 4, actor: "Żaneta", kind: :seal)
  after = GameRoomGames::Replay.new(history: [seal])
  message = fleet.describe_event_for_display({"id" => 4, "action" => "place"}, repository, after, "Żaneta", surface_state: {"setup_mode" => "random"}).first
  expected = language == "pl" ? "Twoje statki zostały rozstawione automatycznie." : "Your ships have been placed automatically."
  assert(message == expected && (message + " — flota").valid_encoding?, "Random confirmation translation or encoding")
end
puts "PASS binary/native dictionary: Monopoly board, numbered houses and real V/Enter browse; fleet prompts in PL/EN/fallback"
