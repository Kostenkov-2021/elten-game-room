require_relative '../support/temporary_directory'
require_relative '../support/assertions'
require_relative '../../tools/encode_audio'
include GameRoomTest::Assertions

GameRoomTest::TemporaryDirectory.create('audio-publication-') do |root|
  source, target = %w[original.wav output.opus].map { |name| File.join(root, name) }
  File.binwrite(source, 'original recording')
  original_probe = GameRoomAudioEncoding.method(:probe)
  original_capture = Open3.method(:capture3)
  original_copy = IO.method(:copy_stream)
  GameRoomAudioEncoding.define_singleton_method(:probe) do |path, **_options|
    {'streams' => [{'codec_type' => 'audio', 'codec_name' => path == source ? 'pcm_s16le' : 'opus',
      'channels' => 2, 'sample_rate' => '48000'}]}
  end
  Open3.define_singleton_method(:capture3) do |command, *arguments|
    raise 'Unexpected executable' unless command == 'test-conversion'
    File.binwrite(arguments.last, 'complete encoded fixture')
    ['', '', Struct.new(:success?).new(true)]
  end
  begin
    # Actual EXCL output/copy path; codec conversion alone is a fixture.
    [:error, :short_copy].each do |mode|
      reached = false
      IO.define_singleton_method(:copy_stream) do |_input, destination|
        reached = true
        destination.write('partial')
        raise IOError, 'Injected final-copy failure' if mode == :error
        7
      end
      assert_raises(IOError) { GameRoomAudioEncoding.encode(source, target, ffmpeg: 'test-conversion') }
      assert(reached, 'The output-copy boundary was not reached')
      assert(!File.exist?(target), 'Failed publication left a partial recording')
      assert_equal('original recording', File.binread(source))
    end
    IO.define_singleton_method(:copy_stream, original_copy)
    GameRoomAudioEncoding.encode(source, target, ffmpeg: 'test-conversion')
    assert_equal('complete encoded fixture', File.binread(target), 'Clean retry did not succeed')

    # A destination appearing during conversion belongs to someone else.
    File.delete(target)
    Open3.define_singleton_method(:capture3) do |_command, *arguments|
      File.binwrite(arguments.last, 'complete encoded fixture')
      File.binwrite(target, 'other output')
      ['', '', Struct.new(:success?).new(true)]
    end
    assert_raises(Errno::EEXIST) { GameRoomAudioEncoding.encode(source, target, ffmpeg: 'test-conversion') }
    assert_equal('other output', File.binread(target), 'EXCL failure removed someone else\'s file')
  ensure
    GameRoomAudioEncoding.define_singleton_method(:probe, original_probe)
    Open3.define_singleton_method(:capture3, original_capture)
    IO.define_singleton_method(:copy_stream, original_copy)
  end
end
puts 'PASS audio output: failed/short copy cleanup, retry, original preserved and concurrent EXCL destination preserved'
