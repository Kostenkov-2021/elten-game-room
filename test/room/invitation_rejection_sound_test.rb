require_relative '../support/table_watch_runtime'
played = []
program = Object.new
program.define_singleton_method(:play_sound_from_asset) { |asset, **options| played << [asset, options] }
enabled = true
program.define_singleton_method(:game_room_sound_enabled?) { |_name| enabled }
program.define_singleton_method(:game_room_sound_volume) { |_name| 0.35 }
entry = Struct.new(:kind, :actor).new('invitation_rejected', 'Alice')
GameRoomSounds.table_activity(program, entry, viewer: 'ALICE')
assert(played == [['invitation_rejected', {volume: 0.35}]], 'rejection cue or volume wrong')
GameRoomSounds.table_activity(program, entry, viewer: 'Bob')
assert(played.length == 1, 'unrelated player heard rejection')
enabled = false
GameRoomSounds.table_activity(program, entry, viewer: 'Alice')
assert(played.length == 1, 'muted rejection made a sound')
assert(GameRoomPreferences.sound_group('invitation_rejected') == 'notifications', 'wrong sound category')
manifest = JSON.parse(File.read(File.expand_path('../../manifest.json', __dir__), encoding: 'UTF-8'))
assert(manifest.dig('required_assets','sounds').include?('invitation_rejected'), 'asset undeclared')
assert(File.binread(File.expand_path('../../Audio/invitation_rejected.opus', __dir__),64).include?('OpusHead'), 'not Opus')
puts 'PASS invitation rejection sound: sender only, shared volume, mute and packaged Opus asset'
