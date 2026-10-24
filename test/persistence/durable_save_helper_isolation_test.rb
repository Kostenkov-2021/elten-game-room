require_relative '../support/durable_save_cases'
include DurableSaveCases

mutable = {'value' => []}
assert_equal(false, mutable.frozen?, 'The save fixture replaced Ruby object immutability')
assert_equal(true, mutable.freeze.frozen?, 'The save fixture replaced Ruby object immutability')
assert_equal(0, mutable.method(:frozen?).arity, 'The save fixture changed the native frozen? signature')
assert_equal(false, Object.new.frozen?, 'Including save cases changed all Ruby objects')
assert(respond_to?(:game_frozen?, true), 'The game-specific freeze helper is missing')
puts 'PASS durable save helper isolation: native frozen? remains intact after importing the shared cases'
