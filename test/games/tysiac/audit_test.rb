def _(text)
  text
end

require_relative "../../support/tysiac_audit"

def assert(condition, message)
  raise message if !condition
end

benchmark = TysiacAudit::Benchmark.new(
  matches: 1,
  seed: 91_000,
  score_limit: 200,
  deep_checks: 2,
  information_set_samples: 4
)
collector = benchmark.run
summary = collector.summary
assert(summary["matches"] == 1, "the audit did not record its match")
assert(summary["finished_matches"] == 1, "the audit match did not finish")
assert(summary["rounds"] > 0, "the audit did not reconstruct completed rounds")
assert(summary["decisions"] > 0, "the audit did not record decisions")
assert(summary["play_decisions"] > 0, "the audit did not inspect card play")
assert(collector.rounds.all? { |round| round.key?("contract_margin") }, "a round has no contract margin")
assert(collector.decisions.all? { |decision| decision.key?("action_key") }, "a decision has no stable action key")

puts "Tysiac audit tests passed"
