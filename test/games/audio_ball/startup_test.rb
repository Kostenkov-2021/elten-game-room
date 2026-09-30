require 'json'

def assert(value, message); raise message unless value; end
root = File.expand_path("../../..", __dir__)
manifest = JSON.parse(File.read(File.join(root, 'manifest.json'), encoding: 'UTF-8'))
source = File.read(File.join(root, '__app.rb'), encoding: 'UTF-8')
embedded = JSON.parse(source.split('=begin Elten3AppInfo', 2).last.split('=end Elten3AppInfo', 2).first)
assert(manifest == embedded, 'Audio Ball changed only one of the application manifests')
%w[audio_ball_up audio_ball_left audio_ball_down audio_ball_prepare].each do |name|
  assert(manifest.fetch('required_assets').fetch('sounds').count(name) == 1, "required Audio Ball asset is absent: #{name}")
end
require_relative "../../support/ui"
class Program
  def self.server_app(**_options); end
end
require_relative "../../../__app"
assert(EltenGameRoom::GAME_REGISTRY.ids.include?('audio_ball'), 'Audio Ball is missing from the game registry')
game = EltenGameRoom::GAME_REGISTRY.build('audio_ball')
assert(game.name == 'Audio Ball' && game.minimum_players == 2 && game.maximum_players == 2, 'Audio Ball was registered with the wrong identity or roster')
assert(game.rule_book.documents.map(&:id) == [:rules, :controls], 'Audio Ball rules cannot be opened from the game list')
assert(EltenGameRoom::DEFAULT_SETTINGS['lobby_games'].include?('audio_ball'), 'fresh settings hide Audio Ball from the lobby')
puts 'PASS Audio Ball asset declarations, matching manifests, registry, rule book and lobby defaults'
