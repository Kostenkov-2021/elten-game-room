require_relative "ui"
require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_screen"
require_relative "native_room_harness"
require_relative "../../lib/game_bots"
require_relative "../../lib/game_content"
require_relative "../../content/languages"
require_relative "../../content/quiz_pl_wikidata"
require_relative "../../games/quiz_party"

module QuizRegressionClock
  def now; Time.at($quiz_regression_now); end
end
$quiz_regression_now = 1000
Time.singleton_class.prepend(QuizRegressionClock)

class QuizReviewFixture
  attr_reader :h, :game, :contexts
  def initialize(users = %w[Alice Bob Carol Dave], bots: 0)
    @game = GameRoomGames::QuizParty.new
    @h = NativeRoomHarness.new(game: game, users: users, bots: bots,
      options: game.default_options.merge("answer_time" => 5, "bot_delay" => 0))
    h.start
    @contexts = users.to_h do |u|
      [u, GameRoomGames::ActionContext.new(session_id: h.session["__id"], table_id: h.table["__id"], now: 1000,
        random_source: GameRoomRandom::SeededSource.new(33), hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new))]
    end
    auto("Alice")
    r = h.replay("Alice")
    h.submit("Alice", { "kind" => "question", "action" => "submit", "question_id" => game.send(:category_surface_id, r.state), "answer" => r.state[:choices].first }, context: contexts["Alice"])
    auto("Alice")
  end

  def advance(time)
    $quiz_regression_now = time
    contexts.each_value { |c| c.now = time }
  end
  def auto(user); h.submit(user, context: contexts.fetch(user)); end
  def answer(user, question_id: nil)
    r = h.replay(user)
    game.action_for({ "kind" => "question", "action" => "submit",
      "question_id" => question_id || game.send(:question_surface_id, r.state),
      "answer" => game.send(:correct_option_index, r.state).to_s }, r, user, context: contexts.fetch(user))
  end
  def plan(user)
    status, plan = answer(user)
    assert(status == :ok, "cannot prepare #{user}: #{status}")
    assert(plan.events.all? { |e| e.value.bytesize <= 64 }, "answer exceeds the unchanged wire limit")
    plan
  end
end
