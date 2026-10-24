require_relative '../support/binary_rules_load'
require_relative '../../lib/sports_rankings/screen'

schema=GameRoomSportsRankings::Schema::TABLES
schema.each { |name,definition| raise 'Packaged sports schema differs' unless EltenGameRoom::SERVER_TABLES.fetch(name)==definition }
games=%w[axel_pong audio_ball].map { |id| EltenGameRoom::GAME_REGISTRY.build(id) }
raise 'Sports games missing leaderboard capability' unless games.all?(&:supports_leaderboards?)
expected={'pl'=>'Wygrane mecze: 2','en'=>'Matches won: 2','cs'=>'Vyhrané zápasy: 2','es'=>'Victorias: 2','ru'=>'Победы: 2'}
row={'user'=>'Alice','won'=>2,'lost'=>1,'scored'=>24,'conceded'=>18,'points'=>1.234567}
expected.each do |language,label|
  GameRoomTestLocalization.use_language(language)
  screen=GameRoomSportsRankings::Screen.new(program:Object.new,game:games.first,service:nil)
  text=screen.send(:statistics_text,row)
  raise "Missing sports translation: #{language}" unless text.include?(label)
  raise 'Internal ranking points leaked into details' if text.include?('1.234567') || text.lines.size!=6
  raise 'Binary sports text has wrong encoding' unless text.encoding==Encoding::UTF_8 && text.valid_encoding?
end
%w[result game store service runtime screen].each do |name|
  path=File.join(BinaryRulesLoad::ROOT,"lib/sports_rankings/#{name}.rb")
  raise "Sports source did not load from binary: #{name}" unless BinaryRulesLoad.instance_variable_get(:@loaded)[path]
end
puts 'PASS binary sports leaderboards: games, schema, all five UI languages, six counters and hidden internal score'
