module MonopolyDebtRoute
  # A complete accepted historical model/action path, not native SDK receipts.
  # Dice/entropy pairs also have possible monopoly_roll recipe outcomes.
  STEPS = [
    ['Alice', 'roll', '2,4,00000000000000000000000000000026'],
    ['Alice', 'buy', ''],
    ['Bob', 'roll', '3,6,00000000000000000000000000000004'],
    ['Bob', 'buy', ''],
    ['Carol', 'roll', '1,2,0000000000000000000000000000006b'],
    ['Carol', 'decline', '1800000005'],
    ['Alice', 'roll', '4,6,00000000000000000000000000000005'],
    ['Alice', 'buy', ''],
    ['Bob', 'roll', '3,6,00000000000000000000000000000004'],
    ['Bob', 'buy', ''],
    ['Carol', 'roll', '1,6,00000000000000000000000000000002'],
    ['Alice', 'roll', '3,6,00000000000000000000000000000004'],
    ['Alice', 'decline', '1800000012'],
    ['Bob', 'roll', '5,6,00000000000000000000000000000000'],
    ['Bob', 'decline', '1800000014'],
    ['Carol', 'roll', '4,6,00000000000000000000000000000005'],
    ['Alice', 'roll', '4,6,00000000000000000000000000000005'],
    ['Alice', 'decline', '1800000017'],
    ['Bob', 'roll', '5,6,00000000000000000000000000000000'],
    ['Carol', 'roll', '5,6,00000000000000000000000000000000'],
    ['Carol', 'decline', '1800000020'],
    ['Alice', 'roll', '2,6,0000000000000000000000000000000a'],
    ['Alice', 'decline', '1800000022'],
    ['Bob', 'roll', '1,4,00000000000000000000000000000029'],
    ['Bob', 'decline', '1800000024'],
    ['Carol', 'roll', '3,6,00000000000000000000000000000004'],
    ['Alice', 'roll', '1,6,00000000000000000000000000000002'],
    ['Bob', 'roll', '1,4,00000000000000000000000000000029'],
    ['Carol', 'roll', '4,6,00000000000000000000000000000005'],
    ['Alice', 'trade_prepare', '2'],
    ['Alice', 'trade_offer', '2|2|0|0|14200000|0'],
    ['Carol', 'trade_accept', ''],
    ['Alice', 'roll', '2,6,0000000000000000000000000000000a'],
    ['Bob', 'trade_prepare', '2'],
    ['Bob', 'trade_offer', '2|2|0|0|15999999|0'],
    ['Carol', 'trade_accept', ''],
    ['Bob', 'roll', '2,4,00000000000000000000000000000026']
  ].map { |step| step.map(&:freeze).freeze }.freeze

  def self.events
    STEPS.each_with_index.map do |(actor, action, value), index|
      {'id'=>index + 1, 'actor'=>actor.dup, 'action'=>action.dup, 'value'=>value.dup}
    end
  end
end
