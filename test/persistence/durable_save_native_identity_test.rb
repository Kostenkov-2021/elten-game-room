# frozen_string_literal: true
require_relative '../support/durable_save_fixture'

# Supply the identifier at room creation, not by changing an existing table.
# The one-shot UUID override is scoped to the native broker's create call.
module SaveNativeIdentityEndpoint
  def create(**arguments)
    Thread.current[:save_test_next_id] = Thread.current[:save_test_native_id]
    super
  ensure
    Thread.current[:save_test_next_id] = nil
  end
end
module SaveNativeIdentityValue
  def uuid(*arguments)
    if (identifier = Thread.current[:save_test_next_id])
      Thread.current[:save_test_next_id] = nil
      return identifier
    end
    super
  end
end
NativeLiveSessionsBroker::Endpoint.prepend(SaveNativeIdentityEndpoint)
SecureRandom.singleton_class.prepend(SaveNativeIdentityValue)

opaque = 'j3CsRMOmH11NQS_WlKb3IH3F2uJThD9X'
[[nil, true], [opaque, true], ['12345678', true], [opaque, false]].each do |identifier, use_intent|
  Thread.current[:save_test_native_id] = identifier
  GameRoomTest::TemporaryDirectory.create('save-native-identity-') do |root|
    harness = DurableSaveFixture.room
    harness.as('Alice') do
      resources = DurableSaveFixture::Resources.new(root)
      intent = DurableSaveFixture.intent(root)
      resources.intent = intent if use_intent
      archive = AccountSavedGames.new(DurableSaveFixture.program, owner: 'Alice', resources: resources)
      command = DurableSaveFixture.use_case(harness, archive)
      assert_equal(2, harness.replay('Alice').accepted_events.size)
      assert_equal(identifier, harness.core.id) if identifier
      arguments = DurableSaveFixture.arguments(harness)
      arguments[:intent] = intent if use_intent
      if use_intent
        begin
          command.call(**arguments)
          raise 'Conditional close must remain pending in this native fixture'
        rescue GameRoomSavedGameSaveIntent::ClosePending
          # Archive is confirmed; this optional path must not pretend to have
          # conditionally closed a session when that API is unavailable.
        end
        record = intent.list.fetch(0)
        assert_equal('readback_confirmed', record['status'])
        assert_equal(harness.core.id, record.dig('values', 'source', 'native_room'))
        assert_equal(intent.list, DurableSaveFixture.intent(root).list, 'Cold journal identity changed')
        assert(!harness.core.closed, 'Unsupported conditional close closed the room')
      else
        assert_equal(true, command.call(**arguments))
        assert(harness.core.closed, 'Ordinary save did not close its room')
      end
      assert_equal(1, resources.state.fetch('uploads'), 'Save retried the upload')
    end
  end
ensure
  Thread.current[:save_test_native_id] = nil
end
puts 'PASS optional durable save: historical UUID, opaque/short native IDs, cold journal readback and ordinary control; one upload'
