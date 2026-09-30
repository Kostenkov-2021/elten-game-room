require_relative "../support/binary_rule_dictionary"

Form.prepend(Module.new do
  def initialize(fields, **options)
    @tutorial_opening_header = fields.first.header
    super
  end
end)

class Form
  class << self; attr_accessor :audio_locale_driver; end
  def wait; Form.audio_locale_driver.call(self); end
  def resume; end
end

expected_pl = ['Dźwięk piłki: strzałka w górę lub W', 'Dźwięk piłki: strzałka w lewo lub D',
  'Dźwięk piłki: strzałka w dół lub S', 'Przygotowanie piłki: strzałka w prawo lub A',
  'Zatrzymanie piłki po skutecznej obronie']
welcome_pl = 'Witaj w tutorialu. Tu poznasz dźwięki używane w tej grze. Poruszaj się strzałkami. Aby odtworzyć dźwięk, wciśnij Spację lub Enter.'
%w[pl en fallback].each do |language|
  $rules_english = language == 'en'
  GameRoomTestLocalization.use_language(language)
  if language == 'fallback'
    if ENV['ELTEN_DICTIONARY_SOURCE']
      $rules_dictionary.send(:loadmo, nil)
    else
      $rules_dictionary = BinaryRuleDictionary.new({})
    end
    source = 'Ball sound: Up arrow or W'.b
    raise 'Fallback fixture did not retain an untranslated binary key' unless _(source).equal?(source)
  end
  game = GameRoomGames::AudioBall.new
  entries = game.audio_tutorial_entries
  if language == 'pl'
    raise 'Audio Ball tutorial labels are untranslated' unless entries.map(&:label) == expected_pl
  else
    raise 'English fallback lost the sound controls' unless entries.first.label == 'Ball sound: Up arrow or W'
  end
  Form.audio_locale_driver = lambda do |form|
    raise 'Welcome opened a separate field' unless form.fields.length == 1
    list = form.fields.first
    title = language == 'pl' ? 'Audiotutorial' : 'Audio tutorial'
    raise 'Wrong tutorial title' unless list.header == title
    welcome = form.instance_variable_get(:@tutorial_opening_header)
    ([list.header] + list.options + [welcome]).each do |text|
      raise 'Binary text reached native UI' unless text.encoding == Encoding::UTF_8 && (text + ' — список').valid_encoding?
    end
    raise 'Polish welcome is missing' if language == 'pl' && welcome != welcome_pl
    form.trigger(:key_escape)
  end
  GameRoomAudioTutorial.new(entries, program: Object.new).wait
end
path = File.join(BinaryRulesLoad::ROOT, 'lib/audio_tutorial.rb')
raise 'Tutorial bypassed binary loading' unless BinaryRulesLoad.instance_variable_get(:@loaded)[path]
puts "PASS audio tutorial #{ARGV.first ? 'installer' : 'binary sources'}: PL, EN, missing translation and native dictionary encoding"
