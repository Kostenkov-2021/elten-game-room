require_relative "../support/host_source"
require_relative "../support/invitation_receipts"
def p_(_context, text); text; end

# Execute the actual host grouping and notification objects, not an imagined
# suppress_default implementation. This is entirely offline.
host = File.join(EltenTestHost.root, "src/eapi")
lines = File.readlines(File.join(host, "program.rb"))
first = lines.index { |line| line.start_with?("  class NotificationPresentation") }
last = lines.index { |line| line.start_with?("  class Leaderboard") }
Object.class_eval("module Programs\n#{lines[first...last].join}\nend", "host_notification_classes.rb")
%w[app_notification_from notification_value map_app_notification receive_app_notification].each do |name|
  first = lines.index { |line| line.start_with?("    def #{name}(") }
  last = ((first + 1)...lines.length).find { |index| lines[index].start_with?("    def ") }
  Object.class_eval("module Programs\nclass << self\n#{lines[first...last].join}\nend\nend", "host_#{name}.rb")
end
require File.join(host, "notificationgroups.rb")
class << EltenGameRoom
  def server_app_uuid; "test-app"; end
  def normalized_settings; EltenGameRoom::DEFAULT_SETTINGS.dup; end
  def name; "ELTEN Game Room"; end
  attr_accessor :received_receipts
  def receive_invitation_receipt(notification); (self.received_receipts ||= []) << notification; end
end
module Programs
  def self.notification_program(uuid); uuid == "test-app" ? EltenGameRoom : OtherNoticeProgram; end
  def self.runtime_for(_program); :receipt_runtime; end
  def self.current_runtime; :another_app_runtime; end
  def self.with_runtime(runtime); Thread.current[:receipt_runtime] = runtime; yield; end
end
class OtherNoticeProgram
  def self.name; "Other app"; end
  def self.map_notification(notification); notification.presentation(body: "Other app message"); end
end
HostNotice = Struct.new(:id, :cat, :app_uuid, :date, :update_time, :revoked, :payload, :alert, keyword_init: true)
helper = Object.new.extend(NotificationGroups)
GameRoomInvitationReceipts.install(EltenGameRoom)
ancestors = NotificationGroups.ancestors.length
GameRoomInvitationReceipts.install(EltenGameRoom)
assert(NotificationGroups.ancestors.length == ancestors, "repeat installation duplicated the bridge")
rows = ["game_room.invitation_resolved", "game_room.invitation_rejected", "game_room.invitation"].each_with_index.map do |type, index|
  HostNotice.new(id: 301 + index, cat: "app", app_uuid: "test-app", date: Time.now.to_i, revoked: false,
    payload: { "type" => type, "sender" => "Guest", "metadata" => { "sender" => "Guest", "table_name" => "Table", "game_name" => "Makao" } }, alert: "")
end
rows << rows.first.dup.tap { |row| row.id = 304; row.app_uuid = "other-app" }
rows << rows.first.dup.tap { |row| row.id = 305; row.revoked = true }
groups = helper.build_notification_groups(rows)
assert(groups.flat_map(&:ids).sort == [303, 304], "blank/rejection entry remains or ordinary/foreign notification was hidden")
assert(EltenGameRoom.received_receipts.map(&:id).sort == [301, 302], "list catch-up missed a reply or processed read history")
assert(helper.build_notification_groups(rows, include_revoked: false).flat_map(&:ids).sort == [303, 304], "active list differs from history filtering")
rows.first(2).each do |row|
  _program, _notification, presentation = Programs.map_app_notification(row)
  assert(presentation.default_suppressed? && presentation.sound == nil && presentation.alert.empty?, "technical reply produced an automatic alert/sound")
end
EltenGameRoom.received_receipts = []
Programs.receive_app_notification(rows.first)
assert(EltenGameRoom.received_receipts.map(&:id) == [301], "host two-argument receipt hook failed")

# One-shot background work uses the app runtime even from the main-window list.
class EltenLink::Client; end
module EltenLink::Notifications
  def self.revoke(_client, id)
    ($background_receipts ||= []) << [id, Thread.current[:receipt_runtime]]
  end
end
$game_room_test_user = "Owner"
notice = Programs.app_notification_from(rows.first)
assert(GameRoomInvitationReceipts.enqueue(EltenGameRoom, notice), "background receipt not scheduled")
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
until GameRoomInvitationReceipts::LOCK.synchronize { GameRoomInvitationReceipts::INFLIGHT.empty? }
  raise "background receipt did not finish" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  sleep(0.01)
end
assert($background_receipts == [[301, :receipt_runtime]], "background receipt lost authentication runtime")
puts "Actual ELTEN notification groups and callback: no blank/decline entries, ordinary notices intact, background runtime: OK"
