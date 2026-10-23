require_relative '../support/private_card_games'

# Mutations affect detached test projections, not the game, receipts or ledger.
PrivateProjectionView = Struct.new(:native, :users, :change) do
  def game; native.game; end

  def replay(user)
    state = native.replay(user).state.dup
    change.call(state, user)
    Struct.new(:state).new(state)
  end
end

h, runners = PrivateCardGamesTest.create(GameRoomGames::Uno.new,
  users: %w[Alice Bob], random_values: Array.new(16, 8))
begin
  assert(h.replay('Alice').state[:phase] == :playing, 'private opening incomplete')
  assert(h.replay('Alice').accepted_events.size == h.events('Alice').size,
    'private opening contains rejected events')
  PrivateCardGamesTest.assert_private(h)

  # Hash insertion order and different deliberately private fields do not make
  # an otherwise equal public projection divergent.
  equivalent = PrivateProjectionView.new(h, %w[Bob Alice], lambda do |state, user|
    state[:private_test_value] = user
    state[:shared_nil] = nil
    state.replace(state.to_a.reverse.to_h) if user == 'Bob'
  end)
  PrivateCardGamesTest.assert_private(equivalent)

  [%w[Alice Bob], %w[Bob Alice]].each do |users|
    h.users.each do |changed_user|
      [nil, ['extra value']].each do |value|
        view = PrivateProjectionView.new(h, users, lambda do |state, user|
          state[:unexpected_public_branch] = value if user == changed_user
        end)
        error = begin
          PrivateCardGamesTest.assert_private(view)
          nil
        rescue RuntimeError => failure
          failure
        end
        assert(error && error.message.include?('public state diverged') &&
          error.message.include?('unexpected_public_branch'),
          "missed public key difference: #{users.inspect}, #{changed_user}, #{value.inspect}")
      end
    end
  end

  view = PrivateProjectionView.new(h, h.users, lambda do |state, user|
    state[:round] += 1 if user == 'Bob'
  end)
  error = begin
    PrivateCardGamesTest.assert_private(view)
    nil
  rescue RuntimeError => failure
    failure
  end
  assert(error && error.message.include?('public state diverged') &&
    error.message.include?('round'), 'missed common public value difference')
ensure
  runners.each_value(&:close)
end

puts 'PASS private projection assertion: symmetric keys, missing versus nil, values and unchanged private filtering'
