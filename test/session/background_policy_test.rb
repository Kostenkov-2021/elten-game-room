require_relative "../support/native_live_sessions"
require_relative "../../games/quiz_party"
require_relative "../../games/categories"
require_relative "../../games/battleship"
require_relative "../../games/krowa"
require_relative "../../games/uno"
require_relative "../../lib/game_background_policy"

class BackgroundPolicyProgram
  class << self; attr_accessor :settings; end
  def self.normalized_settings; settings; end
end
program = BackgroundPolicyProgram.new
BackgroundPolicyProgram.settings = {'background_table_speech'=>false, 'background_turn_sound'=>true}
policy = GameRoomBackgroundPolicy
original = policy.method(:window_foreground?)
foreground = true
policy.define_singleton_method(:window_foreground?) { foreground }
begin
  $activecontrols = []
  assert(policy.speech?(program) && !policy.turn_sound?(program), 'Foreground presentation changed')
  assert(!policy.speech?(program, covered: true) && policy.turn_sound?(program, covered: true), 'Covered scene settings ignored')
  foreground = false
  assert(!policy.speech?(program) && policy.turn_sound?(program), 'Another application uses different settings')
  help = Object.new
  def help.game_room_hotkeys_active?; true; end
  help.define_singleton_method(:game_room_program) { program }
  $activecontrols = [help]
  assert(!policy.speech?(program, covered: true), 'Own help must not hide lost OS foreground')
  foreground = true
  assert(policy.speech?(program, covered: true) && !policy.turn_sound?(program, covered: true), 'Own help is not an outside window')
  BackgroundPolicyProgram.settings['background_turn_sound'] = false
  assert(!policy.turn_sound?(program, covered: true), 'Disabled cue ignored')
ensure
  policy.define_singleton_method(:window_foreground?, original)
  $activecontrols = []
end

def decision_replay(phase, current: nil, **state)
  GameRoomGames::Replay.new(players: %w[Alice Bob], current_player: current,
    accepted_events: [], state: {phase: phase, players: %w[Alice Bob]}.merge(state))
end
quiz = GameRoomGames::QuizParty.new
question = decision_replay(:answering, round: 1, position: 1, commitments: {})
key = quiz.required_decision_key(question, 'Alice')
assert(key && !quiz.required_decision_key(question, 'Observer'), 'Question must alert each answering player, not observers')
question.state[:commitments]['Alice'] = 'digest'
assert(!quiz.required_decision_key(question, 'Alice'), 'Submitted answer is no longer a decision')
question.state[:phase] = :revealing
question.state[:reveals] = {}
assert(!quiz.required_decision_key(question, 'Alice'), 'Automatic reveal must not alert')
categories = GameRoomGames::Categories.new
sheet = decision_replay(:answering, round: 1, attempt: 1, active_players: ['Bob'], commitments: {})
assert(categories.required_decision_key(sheet, 'Bob') && !categories.required_decision_key(sheet, 'Alice'), 'Judge must not receive the writing cue')
sheet.state[:phase] = :review
sheet.current_player = 'Alice'
assert(categories.required_decision_key(sheet, 'Alice'), 'Review decision missing')
battleship = GameRoomGames::Battleship.new
fleet = decision_replay(:placing, commitments: {})
assert(battleship.required_decision_key(fleet, 'Bob'), 'Initial fleet setup requires a decision')
fleet.state[:commitments]['Bob'] = 'digest'
assert(!battleship.required_decision_key(fleet, 'Bob'), 'Sealed fleet must not alert')
fleet.state[:phase] = :answering
fleet.current_player = 'Bob'
assert(!battleship.required_decision_key(fleet, 'Bob'), 'Private hit computation is not a human decision')
krowa = GameRoomGames::Krowa.new
word = decision_replay(:active, options: {'variant'=>'race'}, results: {}, round: 1)
assert(krowa.required_decision_key(word, 'Alice'), 'Simultaneous word decision missing')
word.state[:results]['Alice'] = {}
assert(!krowa.required_decision_key(word, 'Alice'), 'Completed race player must not alert')
uno = GameRoomGames::Uno.new
cards = decision_replay(:playing, current: 'Bob')
assert(!uno.required_decision_key(cards, 'Alice') && uno.required_decision_key(cards, 'Bob'), 'Interception is not an own-turn cue')
cards.winner = 'Alice'
assert(!uno.required_decision_key(cards, 'Bob'), 'Finished game must not alert')
puts 'PASS background policy: common settings, own help, foreground, sequential and simultaneous decisions'
