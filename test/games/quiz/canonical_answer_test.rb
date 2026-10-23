require_relative '../../support/quiz_party_review_regressions'

%w[0 1 2 3].each do |answer|
  $quiz_regression_now = 1000
  fixture = QuizReviewFixture.new(%w[Alice Bob])
  replay = fixture.h.replay('Alice')
  selection = {
    'kind' => 'question', 'action' => 'submit',
    'question_id' => fixture.game.send(:question_surface_id, replay.state),
    'answer' => answer
  }
  vault = fixture.contexts.fetch('Alice').hidden_submissions
  prepare = vault.method(:prepare)
  writes = 0
  vault.define_singleton_method(:prepare) do |**arguments|
    writes += 1
    prepare.call(**arguments)
  end
  [nil, '', '00', '01', '03', '0003', '-1', '4', '10', ' 0', "0\n", '０'].each do |invalid|
    status, plan = fixture.game.action_for(selection.merge('answer' => invalid), replay, 'Alice',
      context: fixture.contexts.fetch('Alice'))
    assert(status == :invalid && plan.nil?, "Noncanonical answer #{invalid.inspect} was accepted")
  end
  assert(writes.zero?, 'Rejected answers wrote private envelopes')
  status, plan = fixture.game.action_for(selection, replay, 'Alice', context: fixture.contexts.fetch('Alice'))
  assert(status == :ok && writes == 1, "Canonical answer #{answer} was rejected")
  fixture.h.write('Alice', plan.events)
  fixture.h.write('Bob', fixture.plan('Bob').events)
  fixture.auto('Alice') # Close normally once both commitments arrive.
  fixture.auto('Alice')
  fixture.auto('Bob')
  revealed = fixture.h.replay('Alice')
  assert(revealed.state[:reveals].fetch('Alice') == answer.to_i,
    "Accepted answer #{answer} could not be revealed")
  fixture.auto('Alice')
  assert(fixture.h.replay('Alice').state[:phase] == :starting,
    'Canonical commitments needed a timeout to finish')
  fixture.h.assert_converged("Canonical option #{answer} round trip")
end

puts 'PASS Quiz canonical answer validation: no malformed envelope writes; all four options commit/reveal normally'
