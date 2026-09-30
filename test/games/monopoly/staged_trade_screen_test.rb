require_relative "../../support/background_help_game_screen"
require_relative "../../../games/monopoly"

# Only the starting possessions are arranged. Forms, event submission, replay,
# native stack and the managed bot executor are the production implementations.
class TradeScreenMonopoly < GameRoomGames::Monopoly
  private
  def initial_state(players, options)
    super.tap do |state|
      state[:owners].merge!(1 => players[0], 3 => players[0], 6 => players[0], 8 => players[0], 9 => players[1])
      state[:cash].transform_values! { 10_000 }
    end
  end
end

module EditBox::Flags
  Numbers = 4 unless const_defined?(:Numbers)
end
class EditBox
  def select_all; @index, @check = 0, text.length; end
end

[:direct, :cancel_recipient, :cancel_offer_then_send, :cancel_all, :human].each do |variant|
$game_room_test_user = 'Alice'
h, screen = screen_fixture(TradeScreenMonopoly.new, bots: variant == :human ? 0 : 1)
screen.instance_variable_set(:@game_services, {transport: h.transports['Alice']})
screen.define_singleton_method(:getkeychar) { '' }
stage, finished, cancelled, replied = :open, false, false, false
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
Form.driver = lambda do |form|
  events = h.events('Alice')
  raise "Trade stopped at #{stage}: #{events.map { |event| event['action'] }.inspect}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  case stage
  when :open
    stage = :choose
    form.trigger(:key_e, [false, false, false])
  when :choose
    assert(form.fields.first.header == 'Choose a player for the trade', 'missing recipient form')
    if variant == :cancel_recipient || (variant == :cancel_all && cancelled)
      stage = :exit_cancelled
      form.cancel_button.trigger(:press)
      next
    end
    stage = :offer
    form.accept_button.trigger(:press)
  when :offer
    assert(form.fields[2].is_a?(ListBox) && form.fields[3].is_a?(ListBox), 'missing property lists')
    if [:cancel_offer_then_send, :cancel_all].include?(variant) && !cancelled
      cancelled = true
      stage = :choose
      form.cancel_button.trigger(:press)
      next
    end
    form.fields[2].select_multiselection_indices([0, 1, 2, 3])
    form.fields[3].select_multiselection_indices([0])
    stage = :response
    form.accept_button.trigger(:press)
  when :response
    if variant == :human && !replied && events.any? { |event| event['action'] == 'trade_offer' }
      replied = true
      h.submit('Bob', {'kind' => 'command', 'action' => 'trade_accept'})
    end
    if events.any? { |event| %w[trade_accept trade_reject].include?(event['action']) }
      assert(events.count { |event| event['action'] == 'trade_prepare' } == (cancelled ? 2 : 1), 'duplicate preparation')
      assert(events.count { |event| event['action'] == 'trade_offer' } == 1, 'missing or duplicate final offer')
      finished = true
      screen.instance_variable_get(:@layout).back_button.trigger(:press)
    end
    sleep 0.002
  when :exit_cancelled
    assert(events.none? { |event| event['action'] == 'trade_offer' }, 'cancellation submitted an offer')
    assert(events.count { |event| event['action'] == 'trade_prepare' } == (cancelled ? 1 : 0), 'cancel changed preparations')
    finished = true
    screen.instance_variable_get(:@layout).back_button.trigger(:press)
  end
end
h.as('Alice') { assert(screen.run == :back, 'trade changed exit behavior') }
assert(finished, 'bot did not resolve the trade')
assert(h.replay('Alice').current_player == 'Alice', 'trade did not return control to proposer')
puts "PASS Monopoly staged form #{variant}: no stale revision, no duplicate or unwanted offer, continued turn"
end
