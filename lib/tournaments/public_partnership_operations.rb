# frozen_string_literal: true
module GameRoomTournaments
  module PublicPartnershipOperations
    Data = Publication::Data
    def choose_partnership(tournament_id:, account:, partner:, intent_id:, expected_request_key: nil)
      raise PublicService::Error, :own_partnership_only unless Data.account(account).downcase == @journal.owner
      previous = boundary { @journal.find(kind: 'partnership', intent_id: intent_id) || @journal.find(kind: 'pairing', intent_id: intent_id) }
      return reconcile_record(previous, snapshot) if previous && previous['status'] != 'prepared'
      view, row, state = partnership_source(tournament_id)
      partner = Data.account(partner).downcase unless partner.nil?
      incoming = partner && state['requests'][partner]
      if state['links'][@journal.owner]
        raise PublicService::Error, :partner_already_set if partner
        action, partner = 'dissolve', state['links'][@journal.owner]
      elsif partner.nil?
        request = state['requests'][@journal.owner]
        return nil unless request
        action, expected_request_key = 'cancel', request['key']
      elsif incoming && incoming['to'] == @journal.owner
        action = 'accept'
        expected_request_key ||= incoming['key']
      else
        action = 'request'
        old = state['requests'][@journal.owner]
        return {'status'=>'confirmed', 'evidence'=>{'pairing_applied'=>true}} if old && old['to'] == partner
        raise PublicService::Error, :source_changed if expected_request_key && old&.fetch('key') != expected_request_key
        expected_request_key = old&.fetch('key')
      end
      write_partnership(row, view, state, action: action, partner: partner,
        request_key: expected_request_key, intent_id: intent_id)
    end

    def partnership_action(tournament_id:, action:, partner:, request_key:, intent_id:)
      raise PublicService::Error, :invalid_partner_action unless Partnerships::ACTIONS.include?(action)
      previous = boundary { @journal.find(kind: 'partnership', intent_id: intent_id) }
      return reconcile_record(previous, snapshot) if previous && previous['status'] != 'prepared'
      view, row, state = partnership_source(tournament_id)
      partner = Data.account(partner).downcase unless partner.nil?
      write_partnership(row, view, state, action: action, partner: partner,
        request_key: request_key, intent_id: intent_id)
    end

    # Called only by manual Start or its managed scheduled-start coordinator.
    # Ordinary directory, rules, results and match reads remain read-only.
    def complete_partnerships(tournament_id:, starting: false)
      view = snapshot
      row = view.fetch(:model).to_h['announcements'].find { |item| item['alias_ids'].include?(tournament_id) }
      raise PublicService::Error, :unknown_tournament unless row
      settings = JSON.parse(row['settings_json'])
      game = @registry.build(row['game'])
      return nil unless game.team_size(settings['game_options'], player_count: settings['players_per_match']) == 2
      raise PublicService::Error, :not_organizer if starting && row['__insertion_user'].downcase != @journal.owner
      state = view.fetch(:model).partnership_state(row['__id'])
      raise PublicService::Error, :not_registered unless state['active'].include?(@journal.owner) || row['__insertion_user'].downcase == @journal.owner
      raise PublicService::Error.new(:too_few_players, count: state['active'].size, minimum: settings['players_per_match']) if state['active'].size < settings['players_per_match']
      free = state['active'].reject { |person| state['links'][person] }
      return nil if free.empty?
      raise PublicService::Error.new(:incomplete_pairs, count: free.length) if free.length.odd?
      unless starting || TournamentTiming.started?(row, boundary { @clock.call })
        raise PublicService::Error, :tournament_not_started
      end
      generation = state['draw_generation']
      intent = "pair-draw:#{row['__id']}:#{generation}"
      previous = boundary { @journal.find(kind: 'pair_draw', intent_id: intent) }
      if previous && previous['status'] != 'prepared'
        return reconcile_record(previous, view)
      end
      unresolved_mutation!(row, view, Partnerships::KINDS, intent)
      values = RegistrationProjection.join_values(tournament_id: row['__id'], operation_key: SecureRandom.uuid).merge(
        'kind'=>'pair_draw', 'account'=>@journal.owner, 'partner'=>nil, 'pairing_generation'=>generation,
        'amendment_json'=>JSON.generate({'version'=>1, 'seed'=>SecureRandom.hex(32)}))
      record = previous || boundary { @journal.prepare(kind: 'pair_draw', intent_id: intent, values: values) }
      result = attempt(record)
      fresh = snapshot.fetch(:model).partnership_state(row['__id'])
      raise PublicService::Error, :source_changed unless fresh['active'].all? { |person| fresh['links'][person] }
      result
    end

    private

    def partnership_source(tournament_id)
      raise PublicService::Error, :invalid_tournament_id unless Data.integer?(tournament_id, 1)
      view = snapshot
      row = view.fetch(:model).to_h['announcements'].find { |item| item['alias_ids'].include?(tournament_id) }
      raise PublicService::Error, :unknown_tournament unless row
      before_tournament_start!(row)
      settings = JSON.parse(row['settings_json'])
      game = @registry.build(row['game'])
      raise PublicService::Error, :unsupported_role_family unless game.team_size(settings['game_options'], player_count: settings['players_per_match']) == 2
      state = view.fetch(:model).partnership_state(row['__id'])
      raise PublicService::Error, :not_registered unless state['active'].include?(@journal.owner)
      [view, row, state]
    end

    def write_partnership(row, view, state, action:, partner:, request_key:, intent_id:)
      previous = boundary { @journal.find(kind: 'partnership', intent_id: intent_id) }
      return reconcile_record(previous, view) if previous && previous['status'] != 'prepared'
      unresolved_mutation!(row, view, %w[pairing partnership], intent_id)
      if partner
        raise PublicService::Error, :not_registered unless state['active'].include?(partner)
        raise PublicService::Error, :invalid_partner if partner == @journal.owner
      end
      raise PublicService::Error, :partner_unavailable if %w[request accept].include?(action) && partner && state['links'][partner]
      raise PublicService::Error, :partner_already_set if %w[request accept].include?(action) && state['links'][@journal.owner]
      if %w[accept decline].include?(action)
        request = state['requests'][partner]
        raise PublicService::Error, :source_changed unless request && request['to'] == @journal.owner && request['key'] == request_key
      end
      if action == 'request' && state['requests'][@journal.owner]&.fetch('key') != request_key
        raise PublicService::Error, :source_changed
      end
      body = {'version'=>1, 'action'=>action, 'request_key'=>request_key}
      generation = Partnerships.choice_generation(state, @journal.owner, partner)
      values = RegistrationProjection.join_values(tournament_id: row['__id'], operation_key: SecureRandom.uuid).merge(
        'kind'=>'partnership', 'account'=>@journal.owner, 'partner'=>partner,
        'pairing_generation'=>generation, 'amendment_json'=>JSON.generate(body))
      record = previous || boundary { @journal.prepare(kind: 'partnership', intent_id: intent_id, values: values) }
      raise PublicService::Error, :source_changed unless record['values']['pairing_generation'] == generation
      before_tournament_start!(row)
      attempt(record)
    end
  end
end
