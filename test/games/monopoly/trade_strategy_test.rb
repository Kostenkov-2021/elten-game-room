require_relative "../../support/new_games_fixture"
game = GameRoomGames::Monopoly.new
state = game.send(:initial_state, %w[Alice Bob Carol], game.default_options)
state[:cash].transform_values! { 10_000 }
properties = state[:board].select { |square| square[:type] == :property }
group = properties.group_by { |square| square[:group] }.values.find { |items| items.length == 3 }
deed = group.first
state[:owners][deed[:index]] = "Bob"
offer = { from: "Alice", target: "Bob", give_properties: [], receive_properties: [deed[:index]], give_cash: deed[:price], receive_cash: 0 }
state[:trade_offer] = offer
assert(!game.send(:monopoly_trade_safe?, state, "Bob"), "bot sold a solitary deed for face price")
solo = game.send(:trade_property_value, state, deed[:index], "Bob")
group.drop(1).each { |square| state[:owners][square[:index]] = "Alice" }
blocked = game.send(:trade_property_value, state, deed[:index], "Bob")
assert(blocked > solo, "last monopoly blocker has no strategic premium")
offer[:give_cash] = solo
assert(!game.send(:monopoly_trade_safe?, state, "Bob"), "bot gave away the last block for an ordinary solitary-deed price")
group.each { |square| state[:owners][square[:index]] = "Bob" }
offer[:give_cash] = blocked
assert(!game.send(:monopoly_trade_safe?, state, "Bob"), "bot split its own monopoly without compensation")
state[:owners].clear
state[:owners][deed[:index]] = "Bob"
offer[:give_cash] = solo * 2
assert(game.send(:monopoly_trade_safe?, state, "Bob"), "bot rejected a genuinely profitable sale automatically")
puts "Monopoly trade strategy: OK"
