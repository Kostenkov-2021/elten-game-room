require_relative "../../support/krowa"
require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"

def reroll_button(run, viewer = "Alice")
  run.game.surface_spec(run.replay, viewer).parts.flat_map do |part|
    part.surface.respond_to?(:commands) ? part.surface.commands : []
  end.find { |command| command.id == "reroll" }
end

run = KrowaTestGame.new
run.session["options"] = JSON.generate(run.game.default_options.merge("variant" => "random", "length" => 0))
run.automatic
button = reroll_button(run)
assert(button && button.label == "Draw another word", "random word lacks a reroll button")
assert(!reroll_button(run, "Observer"), "observer can reroll")
selection = {"kind" => "command", "action" => "reroll", "round" => run.replay.state[:round]}
assert(run.action("Observer", selection) == :not_player, "observer reroll accepted")
assert(run.action("Alice", selection) == :ok, "random reroll rejected")
assert(run.replay.state[:reason] == :reroll && !run.replay.finished?, "reroll finished game")
run.automatic # reveal old secret using the usual commitment
old_word = run.replay.state[:last_solution]
assert(run.replay.state[:phase] == :setup && run.replay.state[:results].empty?, "reroll recorded a result")
run.automatic
assert(run.replay.state[:round] == 2 && run.replay.state[:attempts].empty?, "new word not started cleanly")
assert(run.replay.state[:used_words] == [old_word], "old secret not excluded")
assert(run.action("Alice", selection) == :stale, "double click rerolled another word")
assert(run.events == Marshal.load(Marshal.dump(run.events)), "events cannot be restored")
assert(run.game.replay(run.session, run.events, run.repository).state == run.replay.state, "reroll replay differs")

pending = KrowaTestGame.new
pending.automatic
pending.guess("Alice", "las")
assert(pending.action("Alice", {"kind" => "command", "action" => "reroll"}) == :pending, "pending guess discarded")
pending.automatic
assert(pending.action("Alice", {"kind" => "command", "action" => "reroll"}) == :ok, "cannot reroll after a checked attempt")
pending.automatic; pending.automatic
assert(pending.replay.state[:attempts].empty?, "previous attempts leaked into new word")

%w[daily tower].each do |variant|
  guarded = KrowaTestGame.new(variant: variant, players: variant == "tower" ? %w[Alice Bob] : ["Alice"])
  guarded.automatic
  assert(!reroll_button(guarded), "#{variant} offers reroll")
  assert(guarded.action("Alice", {"kind" => "command", "action" => "reroll"}) == :invalid, "#{variant} reroll accepted")
  forged = {"id" => 3, "actor" => "Alice", "action" => "krowa_reroll", "value" => "1"}
  assert(guarded.game.replay(guarded.session, guarded.events + [forged], guarded.repository).accepted_events.length == guarded.events.length, "#{variant} forged reroll accepted")
end
race = KrowaTestGame.new(variant: "race", players: %w[Alice Bob])
race.automatic
assert(reroll_button(race) && !reroll_button(race, "Bob"), "race ownership changed")
assert(race.action("Alice", {"kind" => "command", "action" => "reroll"}) == :ok, "existing race reroll broken")
puts "Krowa random reroll: UI, pending guesses, observers, stale commands, replay and daily protection OK"
