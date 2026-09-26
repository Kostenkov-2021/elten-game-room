# encoding: UTF-8
require "securerandom"
require_relative "game_room_localization"

module GameRoomBotNames
  # These positions are persistent name codes in seats/saved games. Append
  # future names; do not reorder or recycle an existing position.
  POLISH = [
    "Jola", "eufrozyna", "grazia", "rychu", "Zdzichu", "Miecio pijak",
    "przegryw", "Karol Nawrocki", "Andrzej Duda", "Jarek Kaczor",
    "brzydkie Kaczątko", "Geralt", "Jenefer", "wujo weselnik",
    "ciocia Zdzisia", "Prymityw", "Król Karol", "Czesio", "Anusiak",
    "Maślana", "Konieczko", "Pani Frau", "Higienistka", "Wacław",
    "Klara Sobieraj", "asystent Google", "Max z Orange", "Siri", "Lolek",
    "Marek Dyrektor", "Baltazar Świździpała", "ciocia Henia", "Wujo Janek",
    "Wiesław", "Jaskier", "Aluś", "Eulalia", "Andżej", "Audiobukis", "Natala",
    "Gienek Gienerator", "Siostra Konsoleta", "amelinium", "Mymłon",
    "Generał Italia", "Pułkowniciowy"
  ].map(&:freeze).freeze
  ENGLISH = [
    "Batman", "Indiana jones", "Noob's spirit", "Sister duck", "Thinky winky",
    "Porcelain duck", "Doctor house", "Grandma duck", "Bugs bunny", "Space cat",
    "Yellow duck", "Terminator", "plastic duck", "Sarah connor", "Anakin skywalker",
    "Mickey mouse", "Dr. jeckil", "Peter pan", "Billy the kid", "Uncle duck",
    "Albator", "Green duck", "Sir duck", "the loser", "Prince of persia", "Baracouda"
  ].map(&:freeze).freeze
  POOLS = { "pl" => POLISH, "en" => ENGLISH }.freeze
  NAMES = POOLS.each_with_object({}) do |(language, names), result|
    names.each_with_index { |name, index| result["%s%02d" % [language, index + 1]] = name }
  end.freeze

  module_function

  def interface_language
    GameRoomLocalization.primary_language == "pl" ? "pl" : "en"
  end

  def name_for(token)
    NAMES[token]
  end

  def pick(language: interface_language, occupied: [], random: SecureRandom)
    prefix = language.to_s.downcase.split(/[-_.]/).first == "pl" ? "pl" : "en"
    taken = occupied.map { |name| name.to_s.strip.downcase }
    choices = NAMES.keys.select { |token| token.start_with?(prefix) && !taken.include?(NAMES.fetch(token).downcase) }
    raise ArgumentError, "No unused computer name" if choices.empty?
    # Only the creator draws once; the chosen code is sent with the bot.
    index = random.respond_to?(:random_number) ? random.random_number(choices.length) : random.rand(choices.length)
    choices.fetch(index)
  end
end
