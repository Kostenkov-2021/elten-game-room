require_relative '../support/table_watch_runtime'
require_relative '../support/app_notification_models'
require EltenTestHost.file('src/eapi/notificationgroups.rb')

def p_(_context, text); text; end

class SenderPresentationApp < EltenGameRoom
  class << self
    attr_accessor :effective_settings, :played
    def normalized_settings; effective_settings; end
    def play_sound_from_asset(name, volume:); played << [name, volume]; end
    def contacts_cache; raise 'Envelope validation requested contacts'; end
  end
end

SENDER_RUNTIME = TestTaskRuntime.new('sender-presentation')
module Programs
  def self.notification_program(_); SenderPresentationApp; end
  def self.runtime_for(_); SENDER_RUNTIME; end
end
SenderHostNotice = Struct.new(:id, :cat, :app_uuid, :date, :update_time, :revoked, :payload, :alert, keyword_init: true)
program = SenderPresentationApp
GameRoomLocalization.boot(settings: {}, host_language: 'en')
GameRoomInvitationReceipts.install(program)
grouping = Object.new.extend(NotificationGroups)
now = Time.now.to_i
sequence = 0
[false, true].each do |tournament|
  [
    ['BoB', 'Alice', false], ['', 'Alice', false],
    ['BoB', 'bOb', true], ['BoB', '', true], ['BoB', nil, true]
  ].each do |sender, claimed, allowed|
    sequence += 1
    program.effective_settings = GameRoomPreferences.normalize(
      {'invitation_notifications' => 'everyone', 'invitation_sounds' => true}, program::GAME_REGISTRY.ids)
    program.played = []
    metadata = {'game' => 'uno', 'table_name' => 'Room', 'table_id' => sequence,
      'invitation_id' => sequence, 'live_session_id' => "room-#{sequence}",
      'expires_in' => 300, 'tournament_match' => tournament}
    metadata['sender'] = claimed unless claimed.nil?
    row = SenderHostNotice.new(id: sequence, cat: 'app', app_uuid: program.server_app_uuid,
      date: now, revoked: false, alert: '', payload: {
        'sender' => sender, 'type' => 'game_room.invitation', 'metadata' => metadata})
    _, notice, presentation = Programs.receive_app_notification(row)
    assert(presentation.default_suppressed? == !allowed, "Wrong delivery for #{sender.inspect}/#{claimed.inspect}")
    presentation.sound
    assert(program.played.size == (allowed ? 1 : 0), 'Invalid sender played a sound or valid sender lost it')
    assert(grouping.build_notification_groups([row]).flat_map(&:ids) == (allowed ? [sequence] : []),
      'Host list disagrees with delivery')
    assert(!presentation.alert.include?('Alice'), 'A metadata name leaked into the invitation')
    assert(presentation.alert.include?('BoB invites') == allowed, 'Authenticated original-case name was lost')
    gateway = Object.new
    gateway.define_singleton_method(:list) { |*, **| [notice] }
    repository = InvitationNotifications.new(client: :offline, app_uuid: program.server_app_uuid,
      gateway: gateway, current_user: -> { 'Guest' })
    pending = repository.pending(recipient: 'Guest')
    reference = GameRoomInvitationIdentity.notification_reference(notice, recipient: 'Guest')
    assert(pending.size == (allowed ? 1 : 0) && !reference.nil? == allowed,
      'Presentation and authoritative lookup disagree')
    assert(pending.first.fetch('sender') == 'BoB' && reference.fetch('sender') == 'BoB',
      'Lookup changed native spelling') if allowed
    unless allowed
      program.effective_settings = program.effective_settings.merge('invitation_notifications' => 'contacts')
      assert(program.contact_notification_allowed?(notice) == false, 'Malformed envelope reached the contact cache')
    end
  end
end

# Keep the historical non-native adapter fallback, including symbol keys.
legacy = Object.new
assert(GameRoomInvitationIdentity.notification_sender(legacy, sender: 'Legacy') == 'Legacy',
  'Legacy adapter metadata fallback changed')
assert(GameRoomInvitationIdentity.notification_sender(legacy, {}) == '',
  'Legacy missing-name semantics changed')
puts 'PASS invitation sender: native delivery/list/audio and lookup agree, casing/missing claims, tournament parity and legacy adapters'
