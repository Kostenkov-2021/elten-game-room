require_relative "../support/ui"
require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_screen"
require_relative "../../lib/hidden_submissions"
require_relative "../../lib/saved_games"
require_relative "../../games/rummy"
require_relative "../../games/domino"
require_relative "../../games/mexican_train"
require_relative "../../games/scrabble"
require_relative "../../games/taboo"
require_relative "../../games/biblios"

def n_(one, many, count); count == 1 ? one : many; end
def assert(value, message); raise message unless value; end
module Session
  class << self; attr_accessor :name; end
end

class AnnouncementRandom
  def initialize; @random = Random.new(227); end
  def roll(count:, sides:)
    Struct.new(:values).new(Array.new(count) { @random.rand(sides) + 1 })
  end
end

def announcement_screen(game, session, repo)
  GameScreen.new(program: Object.new, repository: repo, game: game,
    session: session, table: {}, table_owner: "Alice",
    room_snapshot_provider: nil, synchronizer: nil)
end

failures = []
[GameRoomGames::Rummy, GameRoomGames::Domino, GameRoomGames::MexicanTrain,
 GameRoomGames::Scrabble, GameRoomGames::Taboo, GameRoomGames::Biblios].flat_map do |klass|
  klass.new.supports_bots? ? [[klass, "Bob"], [klass, "bot:1:1"]] : [[klass, "Bob"]]
end.each do |klass, opponent|
  game = klass.new
  players = game.id == "taboo" ? %w[Alice Bob Carol Dave] : ["Alice", opponent]
  repo = SavedGames::ReplayRepository.new
  def repo.bot_turn_controller(_table_id); nil; end
  session = { "__players" => players, "options" => JSON.generate(game.default_options) }
  events = []
  replay = game.replay(session, events, repo)
  viewers = players + ["Observer"]
  screens = viewers.to_h { |viewer| [viewer, announcement_screen(game, session, repo)] }
  screens.each { |viewer, screen| Session.name = viewer; screen.send(:process_new_events, replay) }
  random = AnnouncementRandom.new
  now = 1_800_000_000
  transitions = 0
  8.times do |index|
    actor = players.first
    context = GameRoomGames::ActionContext.new(now: now, random_source: random)
    action = game.automatic_action(replay, actor, context: context)
    unless action
      actor = replay.current_player
      action = case game.id
      when "rummy"
        replay.state[:drawn] ? { "action" => "discard", "card" => game.hand(replay.state, actor).last } : { "action" => "draw" }
      when "scrabble" then { "action" => "pass" }
      when "taboo"
        if replay.state[:phase] == :ready
          { "action" => "start", "token" => game.token(replay.state) }
        elsif replay.state[:phase] == :describing
          { "action" => "correct", "token" => game.token(replay.state) }
        elsif replay.state[:phase] == :review
          actor = players.first
          { "action" => "approve", "token" => game.token(replay.state) }
        end
      else
        game.legal_actions(replay, actor, context: context).first
      end
    end
    assert(action, "#{game.id}: no test action at #{index}")
    status, plan = game.action_for(action, replay, actor, context: context)
    assert(status == :ok, "#{game.id}: #{status} for #{action}")
    before = replay
    batch = plan.events.map.with_index do |command, i|
      { "id" => events.length + i + 1, "actor" => actor,
        "action" => command.action, "value" => command.value }
    end
    # A multi-part move may arrive over several refreshes. Do not speak its
    # technical pieces or announce a move before its final part is present.
    (1...batch.length).each do |count|
      partial = game.replay(session, events + batch.first(count), repo)
      screens.each do |viewer, screen|
        Session.name = viewer
        $spoken_messages.clear
        screen.send(:process_new_events, partial)
        assert($spoken_messages.empty?, "#{game.id}: speech for an incomplete move")
      end
    end
    events.concat(batch)
    replay = game.replay(session, events, repo)
    assert(replay.accepted_events.length == events.length, "#{game.id}: replay rejects move")
    expected = replay.history.reject { |entry| [:start, :turn, :result].include?(entry.kind) || entry.event_id.to_i <= before.accepted_events.last.to_h.fetch("id", 0) }.map(&:text)
    assert(!expected.empty?, "#{game.id}: action has no public history")
    screens.each do |viewer, screen|
      Session.name = viewer
      $spoken_messages.clear
      screen.send(:process_new_events, replay)
      expected.each do |message|
        failures << "#{game.id}/#{viewer}/#{action['action']}: missing #{message}" unless $spoken_messages.count(message) == expected.count(message)
      end
      if game.id == "taboo" && replay.state[:phase] == :describing
        secret = game.cards(replay.state)[replay.state[:card]]["word"]
        assert($spoken_messages.none? { |text| text.include?(secret) }, "Taboo speaks a secret through public announcements")
      end
      $spoken_messages.clear
      screen.send(:process_new_events, replay)
      assert($spoken_messages.empty?, "#{game.id}: repeats announcements without new events")
    end
    # Joining/reopening must not speak the entire archived game.
    Session.name = "Observer"
    $spoken_messages.clear
    announcement_screen(game, session, repo).send(:process_new_events, replay)
    assert($spoken_messages.empty?, "#{game.id}: announces old history on entry")
    transitions += 1
    now += game.id == "taboo" && index == 4 ? 100 : 4
  end
  # Result and turn are announced by GameScreen separately, not twice by the
  # public-history adapter. Technical fragments must not produce speech either.
  last = events.last
  replay.history << GameRoomGames::HistoryEntry.new(event_id: last['id'], kind: :turn, text: "SENTINEL TURN")
  replay.history << GameRoomGames::HistoryEntry.new(event_id: last['id'], kind: :result, text: "SENTINEL RESULT")
  text = Array(game.describe_event_for_display(last, repo, replay, "Alice")).join
  assert(!text.include?("SENTINEL"), "#{game.id}: duplicate framework announcements")
  puts "#{game.id}/#{opponent}: #{transitions} accepted transitions, #{viewers.length} viewers"
end
raise failures.first(15).join("\n") + "\n#{failures.length} missing announcements" unless failures.empty?
puts "New games: live move speech, observers, replay deduplication and hidden information OK"
