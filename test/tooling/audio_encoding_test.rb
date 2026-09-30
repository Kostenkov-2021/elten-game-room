require "tmpdir"
require_relative "../../tools/encode_audio"

def assert(value, message); raise message unless value; end

args = GameRoomAudioEncoding.arguments("source with spaces.wav", "new.opus")
{"-b:a" => "144k", "-vbr" => "on", "-frame_duration" => "20", "-ar" => "48000",
 "-application" => "audio", "-compression_level" => "10", "-c:a" => "libopus",
 "-map_metadata" => "0", "-map_metadata:s:a:0" => "0:s:a:0"}.each do |option, value|
  assert(args[args.index(option).to_i + 1] == value, "Wrong default for #{option}")
end
assert(args[args.index("-i") + 1] == "source with spaces.wav", "Source path was split")
assert((args & %w[-ac -af -ss -t -to]).empty?, "Default conversion must not downmix, change gain or trim")
Dir.mktmpdir("gr-encoding-test-") do |directory|
  original = File.join(directory, "source.wav")
  target = File.join(directory, "target.opus")
  File.binwrite(original, "original")
  File.binwrite(target, "existing")
  begin
    GameRoomAudioEncoding.encode(original, target, ffmpeg: "must-not-run", ffprobe: "must-not-run")
    raise "Existing asset overwritten"
  rescue RuntimeError => error
    raise unless error.message.include?("Refusing to overwrite")
  end
  assert(File.binread(original) == "original" && File.binread(target) == "existing", "Originals changed")
end
puts "PASS audio authoring defaults: Opus 144 VBR/20 ms, channels/gain/metadata, separate output, no overwrite"
