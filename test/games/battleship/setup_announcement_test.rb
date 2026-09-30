require_relative "../../support/battleship_presentation"

# Model native focus speaking with the default stop=true. The older form
# simulation did not announce focus and therefore could not detect cuts.
$setup_output = []
def speak(text, **options)
  $spoken_messages << text.to_s
  $setup_output << [text.to_s, options]
end
class GridBox
  alias_method :setup_original_focus, :focus
  def focus(*args, **options)
    result = setup_original_focus(*args, **options)
    speak("GRID FOCUS") if last_focus_spoken
    result
  end
end
class ListBox
  alias_method :setup_original_focus, :focus
  def focus(*args, **options)
    result = setup_original_focus(*args, **options)
    speak("LIST FOCUS") if last_focus_spoken
    result
  end
end
class Form
  def wait
    fields[index.to_i]&.focus if @announce_wait != false && (@quiet == true || @updated == true)
    Form.driver.call(self)
  end
end

%w[before after].each do |opponent_ready|
  h = NativeRoomHarness.new(game: GameRoomGames::Battleship.new, users: %w[Alice Bob])
  h.start
  vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
  context = GameRoomGames::ActionContext.new(session_id: h.session["__id"], hidden_submissions: vault)
  sync = GameRoomSync::Controller.new(transport: h.transports["Alice"], table_id: h.table["__id"], session_id: h.session["__id"])
  10.times { sync.next_event }
  screen = GameScreen.new(program: ProgramDouble.new(h.broker.endpoint("Alice")), repository: h.repositories["Alice"],
    game: h.game, session: h.session, table: h.table, table_owner: "Alice", synchronizer: sync,
    room_snapshot_provider: -> { LobbyRepository::TableSnapshot.new(**h.transports["Alice"].room_snapshot(h.table)) })
  screen.instance_variable_set(:@hidden_submissions, vault)
  screen.define_singleton_method(:alert) { |message| raise "Unexpected setup alert: #{message}" }
  $setup_output.clear
  stage = 0
  Form.driver = lambda do |form|
    stage += 1
    raise "Setup loop did not finish" if stage > 3
    layout = screen.instance_variable_get(:@layout)
    texts = $setup_output.map(&:first)
    prompt = "How would you like to arrange your fleet? Randomly"
    confirmation = "Your ships have been placed automatically."
    assert(texts.count(prompt) == 1, "Setup question was not spoken once at a fresh game start")
    if stage == 1
      assert(h.events("Alice").one?, "Actual automatic initialization was not exercised")
      if opponent_ready == "before"
        h.submit("Bob", {"action" => "random_fleet"}, context: context)
        form.instance_variable_get(:@timers).each(&:fire)
      else
        layout.surface.fields.first.trigger(:select)
      end
    elsif stage == 2
      if opponent_ready == "before"
        layout.surface.fields.first.trigger(:select)
      else
        assert(texts.count(confirmation) == 1 && !texts.include?("It is your turn."), "Random confirmation did not precede opponent readiness")
        h.submit("Bob", {"action" => "random_fleet"}, context: context)
        form.instance_variable_get(:@timers).each(&:fire)
      end
    else
      assert(texts.count(confirmation) == 1, "Random placement confirmation missing or repeated")
      assert(texts.count("It is your turn.") == 1, "First shooting turn missing or repeated")
      assert(texts.index(confirmation) < texts.index("It is your turn."), "Turn precedes placement confirmation")
      assert($setup_output.all? { |_text, options| options[:stop] == false && options[:break_sequence] == false },
        "Automatic setup feedback or form focus interrupts the speech queue")
      assert(layout.surface.is_a?(GameSurfaces::CompositeSurface), "Playing boards not displayed")
      layout.back_button.trigger(:press)
    end
  end
  h.as("Alice") { assert(screen.run == :back && stage == 3, "Setup screen failed") }
  h.assert_converged("after setup announcements", expected_count: 3)
end
puts "PASS Battleship fresh-screen speech: one question, accepted random confirmation, first turn, quiet refresh in both seal orders"
