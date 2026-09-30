# encoding: UTF-8
require_relative "../../../tools/support/quiz_input"
require_relative "../../support/assertions"
include GameRoomTest::Assertions

def question(prompt, correct = 'Answer', wrong = %w[One Two Three])
  {'prompt' => QuizInput.text(prompt), 'correct' => QuizInput.text(correct),
    'wrong' => wrong.map { |value| QuizInput.text(value) }}
end

assert_equal('Name & label Actor', QuizInput.text("  [[Article|Name]] &amp; <b>label</b>\n[https://example.org Actor] "))
assert_equal('', QuizInput.text(nil))
assert_equal('missing actor/context', QuizInput.problem(question('(serial, 2019 — którą postać zagrała ta osoba?')))
assert_equal('depends on another question', QuizInput.problem(question('Who was in the previous question?')))
assert_equal('unresolved import markup', QuizInput.problem(question('Unfinished [[link')))
assert_equal('empty question/answer', QuizInput.problem(question('A complete question?', '  ')))
assert_equal('duplicate choices after cleanup', QuizInput.problem(question('Collision?', '[[Name]]', %w[name Two Three])))
[
  'Film legend Charlie Chaplin was born in which country?',
  "(You're) Having My Baby was sung by whom?",
  'What does com mean in http://www.microsoft.com?',
  'Abigail — gdzie mieszkała ta postać?',
  'Abigail — w jakim państwie mieszkała ta postać?'
].each { |prompt| assert_equal(nil, QuizInput.problem(question(prompt)), "valid input rejected: #{prompt}") }
puts 'PASS Quiz input: markup normalization, validation and valid counterexamples'
