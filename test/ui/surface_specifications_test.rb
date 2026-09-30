require_relative "../support/assertions"
require_relative "../../lib/game_surfaces/specifications"
require_relative "../../lib/game_layout_spec"
include GameRoomTest::Assertions

assert(!defined?(Form) && !defined?(GameRoomUI), 'specifications loaded native UI')
action = GameSurfaces::Action.from_h({'kind' => 'card', 'action' => 'play', 'card' => 'AS'}, source: 'hand')
assert_equal({'kind' => 'card', 'action' => 'play', 'card' => 'AS', 'source' => 'hand'}, action.to_h)
spec = GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(id: 'hand', cards: [])])
view = GameRoomLayout::ViewSpec.new(surface: spec)
assert(view.surface.equal?(spec), 'layout copied or replaced the declared surface')
assert_equal(:users, view.sections.last)
puts 'PASS pure action, surface and layout specifications'
