require_relative "../support/table_notice_presentation"

# Controlled local latency, NOT a measurement of the user's two-second report.
# Mimic the old synchronous receipt write with a 150 ms storage callback.
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
delay = 0.15
slow_disk = ->(_value) { sleep(delay) }
started = clock.call
slow_disk.call("seen" => { "one" => 1300 })
old_receipt_ms = (clock.call - started) * 1000

now = 2_000_000_000
receiver = GameRoomTableWatch::Receiver.new(user: "Alice", games: ["uno"],
  uuid: EltenGameRoom.server_app_uuid, clock: -> { now }, persist: slow_disk)
EltenGameRoom.instance_variable_set(:@table_watch_receiver, receiver)
notice = Notice2.new(id: 900, app_uuid: EltenGameRoom.server_app_uuid,
  type: GameRoomTableWatch::TYPE, sender: "Bob", metadata: {
    "format" => 1, "game" => "uno", "table_id" => 8, "live_session_id" => "latency-room",
    "created_at" => now, "expires_at" => now + 300 })
audio_calls = 0
EltenGameRoom.define_singleton_method(:play_sound_from_asset) { |_, volume:| audio_calls += 1 }
started = clock.call
presentation = EltenGameRoom.map_notification(notice)
EltenGameRoom.notification_received(notice, presentation)
presentation.sound
receipt_ms = (clock.call - started) * 1000
assert(!presentation.default_suppressed && audio_calls == 1, "fast receipt lost speech/sound")
stages = GameRoomTableWatch::Timing.samples.group_by { |item| item[:stage] }
assert(%i[mapping receipt audio].all? { |stage| stages.key?(stage) }, "missing per-stage measurements")
puts JSON.generate(synthetic: true, storage_delay_ms: delay * 1000,
  old_synchronous_write_ms: old_receipt_ms.round(3), new_receipt_mapping_audio_ms: receipt_ms.round(3),
  stages_ms: %i[mapping receipt audio].to_h { |stage| [stage, stages[stage].last[:milliseconds].round(3)] })
puts "PASS table notice controlled latency and separate mapping/receipt/audio measurements"
