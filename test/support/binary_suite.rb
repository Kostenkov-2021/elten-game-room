require_relative "../run"

# Suite membership is data. No scenario is imported into another scenario.
module BinaryTestSuite
  def self.run(names, mode: "source", package: ARGV.first, polish: [])
    unknown = polish - names
    raise ArgumentError, "Polish scenarios are missing from the suite: #{unknown.join(', ')}" unless unknown.empty?
    entries = names.map do |name|
      {script: "test/#{name}",
        env: {"GAME_ROOM_BINARY_MODE" => mode,
          "GAME_ROOM_BINARY_LANGUAGE" => polish.include?(name) ? "pl" : "en"},
        ruby_args: ["-r", File.expand_path("binary_suite_bootstrap.rb", __dir__)],
        args: package ? [File.expand_path(package)] : []}
    end
    results = GameRoomTestRunner.run(entries, report: ENV["GAME_ROOM_BINARY_REPORT"])
    GameRoomTestRunner.summary(results)
    exit 1 unless GameRoomTestRunner.success?(results)
  end
end
