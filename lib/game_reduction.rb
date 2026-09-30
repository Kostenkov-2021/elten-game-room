module GameRoomReduction
  # Decoded wire input is distinct from the mutable, replay-owned fold. A
  # handler validates its entire transition before applying state/history.
  Event = Struct.new(:action, :actor, :id, :value, :timestamp, :source, keyword_init: true)
  Frame = Struct.new(:state, :players, :options, :history, :winner, :draw, keyword_init: true)

  def self.decode(event, session, repository, timestamp: nil)
    actor = repository.actor_of(event, session)
    return if actor.to_s.empty?
    Event.new(action: event['action'].to_s, actor: actor,
      id: repository.event_id(event), value: event['value'].to_s, timestamp: timestamp, source: event)
  end
end
