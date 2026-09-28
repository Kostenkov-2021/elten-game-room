require_relative 'support/game_option_encoding'

GameRoomTestLocalization.use_language('en')
$option_host_language = 'en'
app = EltenGameRoom.allocate
app.define_singleton_method(:read_json) { |_path, default:| default }
app.define_singleton_method(:remember_multiple_choice_options) { |*_args| }
app.define_singleton_method(:alert) { |message| raise message }
game = EltenGameRoom::GAME_REGISTRY.build('audio_ball')
forms = 0
[false, true].each do |private_table|
  [1, 2, 3, 4, 5].product([1, 2, 3]).each do |difficulty, sets|
    Form.option_encoding_driver = lambda do |form|
      fields = form.fields.select { |field| field.is_a?(CheckBox) || field.is_a?(ListBox) }
      raise 'Audio Ball table has unexpected controls' unless fields.length == 5
      labels = fields.map { |field| field.is_a?(CheckBox) ? field.label : field.header }
      raise "Wrong Audio Ball tab order: #{labels.inspect}" unless labels == ['Private table', 'Game mode', 'Difficulty and ball speed', 'Sets to win', 'Full P2P (direct connections between participants)']
      raise 'Classic is not the only Audio Ball mode' unless fields[1].options == ['Classic']
      raise 'The lobby is missing a difficulty or has wrong labels' unless fields[2].options == ['Very easy', 'Easy', 'Normal', 'Hard', 'Very hard']
      raise 'Table privacy was not preserved' unless fields[0].checked == private_table
      fields[2].index = difficulty - 1
      fields[3].index = sets - 1
      forms += 1
      form.accept_button.trigger(:press)
    end
    result = app.send(:configure_game_options, game, creating_table: true, initial_private_table: private_table)
    raise 'Audio Ball creation lost privacy or selected choices' unless result == {
      private_table: private_table, game_options: {'mode' => 'classic', 'difficulty' => difficulty, 'sets_to_win' => sets,
        'p2p_enabled' => false, 'p2p_participants_limit' => 8}}
  end
end
repo = Object.new
repo.define_singleton_method(:players_for) { |_session| ['Łucja'.b, 'Żaneta'.b] }
replay = game.replay({'__insertion_user' => 'Łucja'.b, 'options' => '{}'}, [], repo)
surface = GameSurfaces.build(game.surface_spec(replay, 'Żaneta'.b))
$spoken_messages.clear
surface.handle_command('scores')
raise 'Binary player names broke Audio Ball speech' unless $spoken_messages.last.encoding == Encoding::UTF_8 && $spoken_messages.last.include?('Żaneta')
shortcuts = game.game_shortcuts(replay, 'Żaneta'.b)
raise 'Bare S is still bound as a readout' if shortcuts.any? { |shortcut| shortcut.key == 's' && shortcut.modifiers.empty? }
raise 'Shift+S is missing' unless shortcuts.any? { |shortcut| shortcut.key == 's' && shortcut.modifiers == [:shift] }
raise 'Ctrl+W is missing' unless shortcuts.any? { |shortcut| shortcut.key == 'w' && shortcut.modifiers == [:control] }
puts "PASS Audio Ball lobby: #{forms} real option forms, privacy first, choice preservation, binary names and shortcuts"
