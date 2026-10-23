class GameRoomLiveSessionStore
  module PrivateCards
    # Called by the existing snapshot worker. No foreign hand is requested,
    # including when this account owns the native table. Completed draws need
    # no read: their cards have already been revealed in the public history.
    def private_cards_snapshot(session, events)
      return session unless GameRoomPrivateCards.enabled?(session)
      native = active_session(session.fetch('table_id'))
      raise GameRoomNetworkErrors::GamePaused, 'The private card connection is unavailable' unless native
      user = endpoint.user.to_s
      boundary = GameRoomPrivateCards.retain_unrevealed_draws?(session['game']) ? 0 :
        (events.rindex { |event| event['action'] == 'private_deal' } || 0)
      revealed, completed_pools = private_snapshot_evidence(events, expired_before: boundary)
      own, obsolete = {}, {}
      events.each_with_index do |event, index|
        proof = event['__server_pool']
        next unless proof && proof['operation'] == 'take' && same_user?(event['actor'], user)
        if proof['visibility'] == 'public'
          obsolete[[proof['pool_id'], proof['draw_id']]] = true
          next
        end
        used = revealed[proof['draw_id']]
        # Slot-based exchanges need the original draw order on cold replay.
        # Such games retain this round's pools until the next fresh deal.
        if used.length == proof['count'] && !GameRoomPrivateCards.ordered?(session['game'])
          own[proof['draw_id']] = used
          obsolete[[proof['pool_id'], proof['draw_id']]] = true
          next
        end
        # Earlier pools may already be retired. Reconstruct fully disclosed
        # unordered hands above, but never request a deleted historical pool.
        if index < boundary
          obsolete[[proof['pool_id'], proof['draw_id']]] = true
          next
        end
        own[proof['draw_id']] = private_draw_values(session['table_id'], native, proof, user)
      end
      expire_private_snapshot_cache(session['table_id'], native, user, obsolete, completed_pools)
      session.merge('__private_viewer' => user, '__private_draws' => own)
    end

    # Audience is computed by the game's pure replay, never supplied by a
    # requester. The original drawing account remains the only server reader.
    # Shared values are presentation-only until a later native public reveal.
    def shared_private_draws_snapshot(session, audiences)
      lock = @mutex.synchronize { room_state(session.fetch('table_id')).shared_draw_lock }
      lock.synchronize { exchange_shared_private_draws(session, audiences) }
    end

    def exchange_shared_private_draws(session, audiences)
      table_id, session_id = session.values_at('table_id', '__id')
      native = active_session(table_id)
      raise GameRoomNetworkErrors::GamePaused, 'The private connection changed' unless native
      user = endpoint.user.to_s
      cache = @mutex.synchronize do
        room = room_state(table_id)
        key = [session_id, room.attachment]
        room.shared_draws.delete_if { |id, _| id != key }
        room.shared_draws[key] ||= {values: {}, sent: {}, requested: {}}
      end
      messages = take_private_game_messages(table_id, session_id)
      requested = {}
      messages.each do |message|
        packet, sender = message.values_at(:payload, :sender)
        next unless packet['type'] == 'private_draw_share'
        draw_id = packet['draw']
        spec = audiences[draw_id]
        next unless spec && packet['pool'] == spec[:pool]
        eligible = spec[:recipients].any? { |name| same_user?(name, user) }
        if packet['action'] == 'request' && same_user?(spec[:owner], user) &&
            spec[:recipients].any? { |name| same_user?(name, sender) }
          requested[[draw_id, sender.downcase]] = true
        elsif packet['action'] == 'values' && eligible && same_user?(sender, spec[:owner]) &&
            packet['values'].is_a?(Array) && packet['values'].size == spec[:count] &&
            packet['values'].all? { |value| value.is_a?(Integer) && value.between?(1, spec[:size]) }
          cache[:values][draw_id] = packet['values'].dup
        end
      end
      cache[:values].delete_if { |id, _| !audiences.key?(id) }
      cache[:sent].delete_if { |key, _| !audiences.key?(key.first) }
      cache[:requested].delete_if { |id, _| !audiences.key?(id) }
      audiences.each do |draw_id, spec|
        packet = {'type'=>'private_draw_share', 'draw'=>draw_id, 'pool'=>spec[:pool]}
        if same_user?(spec[:owner], user) && (values = session.fetch('__private_draws', {})[draw_id])
          spec[:recipients].each do |recipient|
            next if same_user?(recipient, user)
            key = [draw_id, recipient.downcase]
            next if cache[:sent][key] && !requested[key]
            send_private_game(table_id: table_id, session_id: session_id, recipient: recipient,
              payload: packet.merge('action'=>'values', 'values'=>values), message_id: SecureRandom.uuid)
            cache[:sent][key] = true
          end
        elsif spec[:recipients].any? { |name| same_user?(name, user) } && !cache[:values].key?(draw_id) && !cache[:requested][draw_id]
          send_private_game(table_id: table_id, session_id: session_id, recipient: spec[:owner],
            payload: packet.merge('action'=>'request'), message_id: SecureRandom.uuid)
          cache[:requested][draw_id] = true
        end
      end
      @mutex.synchronize do
        raise GameRoomNetworkErrors::GamePaused, 'The private connection changed' unless @sessions[table_id].equal?(native)
      end
      session.merge('__shared_draws'=>cache[:values].transform_values(&:dup))
    end

    private

    def private_snapshot_evidence(events, expired_before: 0)
      revealed = Hash.new { |all, id| all[id] = [] }
      pools = {}
      events.each_with_index do |event, index|
        proof = event['__server_pool']
        next unless proof
        if proof['operation'] == 'reveal'
          revealed[proof['draw_id']].concat(proof['values'])
        elsif proof['operation'] == 'take'
          pool = pools[proof['pool_id']] ||= {exhausted: false, past_round: false, draws: {}}
          pool[:exhausted] ||= proof['remaining'].zero?
          pool[:past_round] ||= index < expired_before
          pool[:draws][proof['draw_id']] = proof
        end
      end
      revealed.each_value(&:uniq!)
      completed = pools.select do |_, pool|
        pool[:past_round] || pool[:exhausted] && pool[:draws].all? do |id, proof|
          proof['visibility'] == 'public' || revealed[id].length == proof['count']
        end
      end
      [revealed, completed]
    end

    # Irreversible public evidence makes these local cache entries redundant.
    # Never enumerate native pools or remove an unseen/pending draw; ordered
    # current hands and Taboo's unrevealed historical slots retain their values.
    def expire_private_snapshot_cache(table_id, native, user, obsolete, completed_pools)
      @mutex.synchronize do
        room = @rooms[table_id]
        return unless room && @sessions[table_id].equal?(native)
        room.private_draws.delete_if do |(account, pool, draw), _|
          account == user.downcase && obsolete[[pool, draw]]
        end
        room.verified_pools.delete_if { |pool, _| completed_pools.key?(pool) }
      end
    end

    def private_draw_values(table_id, native, proof, user)
      key = [user.downcase, proof.fetch('pool_id'), proof.fetch('draw_id')]
      cached = @mutex.synchronize { room_state(table_id).private_draws[key] }
      return cached.dup if cached
      draw = native.pool(proof['pool_id']).draw(proof['draw_id'])
      values = draw.values
      unless same_user?(draw.user, user) && values.is_a?(Array) && values.length == proof['count'] &&
          values.uniq.length == values.length && values.all? { |value| value.is_a?(Integer) && value.positive? }
        raise GameRoomNetworkErrors::GamePaused, 'Invalid private hand returned by the server'
      end
      @mutex.synchronize do
        raise GameRoomNetworkErrors::GamePaused, 'The private card connection changed' unless @sessions[table_id].equal?(native)
        room_state(table_id).private_draws[key] = values.dup.freeze
      end
      values.dup
    end

    def prepare_private_pool(table_id, native, pending, &before_write)
      request = pending.pool_request
      case request.fetch('operation')
      when 'create'
        unless request['pool_id']
          retire_private_pools(table_id, native, request.fetch('retire', []), &before_write)
          before_write&.call
          pool = native.create_pool(min: 1, max: request.fetch('size'), private_draws: true,
            message_id: pending.message_id + '-pool')
          request['pool_id'] = pool.id
          pending.packet['data']['events'][0]['value'] += '|' + pool.id
        end
      when 'check'
        check_private_pool(table_id, native, request.fetch('pool_id'), request.fetch('size'))
      end
    end

    def retire_private_pools(table_id, native, retired, &before_write)
      return if retired.empty?
      native.pools.each do |pool|
        next unless retired.include?(pool.id)
        before_write&.call
        pool.delete
        @mutex.synchronize do
          room_state(table_id).private_draws.delete_if { |key, _| key[1] == pool.id }
          room_state(table_id).verified_pools.delete(pool.id)
        end
      end
    end

    def check_private_pool(table_id, native, pool_id, size)
      cached = @mutex.synchronize { room_state(table_id).verified_pools[pool_id] }
      return true if cached == size
      state = native.pool(pool_id).state
      unless state.values_at('min', 'max', 'size', 'private_draws') == [1, size, size, true]
        raise GameRoomNetworkErrors::GamePaused, 'The server deck does not match this game'
      end
      @mutex.synchronize do
        raise GameRoomNetworkErrors::GamePaused, 'The private card connection changed' unless @sessions[table_id].equal?(native)
        room_state(table_id).verified_pools[pool_id] = size
      end
      true
    end

    def write_private_pool(table_id, native, pending, &before_write)
      request = pending.pool_request
      prepare_private_pool(table_id, native, pending, &before_write)
      operation = request.fetch('operation')
      if %w[create check claim].include?(operation)
        before_write&.call
        return native.stack_push(pending.packet, message_id: pending.message_id)
      end
      params = {'delivery' => 'stack', 'context' => GameRoomPrivateCards.context(pending.packet),
        'message_id' => pending.message_id}
      if operation == 'take'
        params.merge!('count' => request.fetch('count'), 'visibility' => request.fetch('visibility', 'private'))
      elsif operation == 'reveal'
        params['values'] = GameRoomPrivateCards.reveal_values(request)
      else
        raise ArgumentError, 'Unknown private card operation'
      end
      before_write&.call
      result = native.pool_request(operation.to_sym, params, pool_id: request.fetch('pool_id'),
        draw_id: request['draw_id'])
      receipt = private_pool_receipt(result, request, pending, params)
      if operation == 'take'
        draw = result['draw']
        key = [pending.sender.downcase, request['pool_id'], draw['id']]
        @mutex.synchronize do
          room_state(table_id).private_draws[key] = draw['values'].dup.freeze if @sessions[table_id].equal?(native)
        end
      end
      receipt
    end

    def private_pool_receipt(result, request, pending, params)
      unless result.is_a?(Hash) && result['accepted'] == true && result['message_id'] == pending.message_id &&
          result.dig('pool', 'id') == request['pool_id']
        raise GameRoomNetworkErrors::UncertainWrite, 'Missing private card acknowledgement'
      end
      operation = request['operation']
      packet = {'pool_id' => request['pool_id'], 'context' => params['context']}
      if operation == 'take'
        draw = result['draw']
        unless draw.is_a?(Hash) && draw['id'] == pending.message_id && same_user?(draw['user'], pending.sender) &&
            draw['pool_id'] == request['pool_id'] && draw['visibility'] == request.fetch('visibility', 'private') &&
            draw['values'].is_a?(Array) && draw['values'].length == request['count'] &&
            draw['values'].uniq.length == draw['values'].length &&
            draw['values'].all? { |value| value.is_a?(Integer) && value.positive? }
          raise GameRoomNetworkErrors::UncertainWrite, 'Invalid private draw acknowledgement'
        end
        packet.merge!('draw_id' => draw['id'], 'count' => request['count'],
          'remaining' => result['pool']['remaining'], 'visibility' => draw['visibility'])
        packet['values'] = draw['values'] if draw['visibility'] == 'public'
      else
        values = GameRoomPrivateCards.reveal_values(request)
        unless result['revealed_values'].is_a?(Array) && (values - result['revealed_values']).empty?
          raise GameRoomNetworkErrors::UncertainWrite, 'Invalid reveal acknowledgement'
        end
        packet.merge!('draw_id' => request['draw_id'], 'values' => values)
      end
      result.merge('packet' => packet, 'origin' => 'server_pool',
        'pool' => {'id' => request['pool_id'], 'operation' => operation})
    end
  end

  include PrivateCards
end
