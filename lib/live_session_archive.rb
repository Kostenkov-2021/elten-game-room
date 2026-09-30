class GameRoomLiveSessionStore
  module Archive
    private

    # A roster row can be larger than a move (eight Unicode participant names).
    # Respect both native byte and item limits before publishing anything.
    def archive_chunks(archive, archive_id:, actor:, byte_limit: STACK_ENTRY_BYTES, entry_limit: STACK_ENTRIES)
      chunks, current = [], []
      fits = lambda do |events, index|
        events.length <= ARCHIVE_EVENTS_PER_RECORD && JSON.generate({
          'version' => PROTOCOL, 'kind' => 'game_archive', 'actor' => actor.to_s,
          'data' => {'archive_id' => archive_id, 'index' => index, 'events' => events}
        }).bytesize <= byte_limit
      end
      archive.each do |event|
        unless fits.call(current + [event], chunks.length)
          chunks << current unless current.empty?
          current = []
        end
        raise ArgumentError, 'The saved game is too large to restore safely' unless fits.call(current + [event], chunks.length)
        current << event
      end
      chunks << current unless current.empty?
      raise ArgumentError, 'The saved game is too large to restore safely' if chunks.length > entry_limit - 8
      chunks
    end

    def archive_events_for(game_record)
      data = game_record.packet["data"]
      chunks = records_for(game_record.table_id).select do |item|
        item.sequence < game_record.sequence && item.packet["kind"] == "game_archive" && item.packet.dig("data", "archive_id") == data["archive_id"]
      end.sort_by { |item| item.packet.dig("data", "index") }
      return nil unless chunks.each_with_index.all? { |item, index| item.packet.dig("data", "index") == index }
      events = chunks.flat_map { |item| item.packet.dig("data", "events") }
      return nil unless events.length == data["archive_events"] && events.map { |event| event["id"] }.max.to_i == data["event_id_base"]
      previous = 0
      players = data.fetch('initial_players', data['players'])
      return nil unless events.all? do |event|
        valid = event['id'] > previous
        if event.key?('players')
          valid &&= event['players'].length == players.length
          players = event['players']
        else
          valid &&= GameRoomParticipants.includes?(players, event['actor'])
        end
        previous = event["id"]
        valid
      end
      return nil unless players == data['players']
      events
    end
  end

  include Archive
end
