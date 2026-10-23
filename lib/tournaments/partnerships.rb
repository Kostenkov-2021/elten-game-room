# frozen_string_literal: true
require 'digest'
require_relative 'publication'
require_relative '../game_random'

module GameRoomTournaments
  # One ordered, authenticated partnership projection. Legacy rows retain
  # their historical interpretation; new choices identify the exact request.
  class Partnerships
    Data = Publication::Data
    KINDS = %w[partnership pair_draw].freeze
    ACTIONS = %w[request accept decline cancel dissolve].freeze
    attr_reader :links, :requests, :changes, :applied

    def self.body(row)
      value = row['amendment_json']
      raise Publication::Invalid, :invalid_partnership unless Data.text?(value) && value.bytesize <= 2048
      value = StrictJson.parse(value, max_nesting: 3)
      keys = row['kind'] == 'pair_draw' ? %w[seed version] : %w[action request_key version]
      raise Publication::Invalid, :invalid_partnership unless value.is_a?(Hash) && value.keys.sort == keys && value['version'] == 1
      if row['kind'] == 'pair_draw'
        raise Publication::Invalid, :invalid_partnership unless value['seed'].is_a?(String) && value['seed'].match?(/\A[0-9a-f]{64}\z/)
      else
        raise Publication::Invalid, :invalid_partnership unless ACTIONS.include?(value['action'])
        Data.key!(value['request_key']) unless value['request_key'].nil?
        if %w[accept decline cancel].include?(value['action']) && value['request_key'].nil?
          raise Publication::Invalid, :invalid_partnership
        end
      end
      value
    rescue JSON::ParserError
      raise Publication::Invalid, :invalid_partnership
    end

    def initialize
      @active, @links, @requests, @names = {}, {}, {}, {}
      @changes, @applied = [], []
      @modern = false
    end

    def generation
      Digest::SHA256.hexdigest(JSON.generate([@active.sort, @links.sort,
        @requests.sort.map { |from, request| [from, request['to'], request['key']] }]))
    end

    def draw_generation
      Digest::SHA256.hexdigest(JSON.generate([@active.sort, @links.sort]))
    end

    def self.choice_generation(state, account, partner)
      people = [account, partner].compact.uniq.sort
      values = people.map do |person|
        request = state.fetch('requests')[person]
        [person, state.fetch('epochs')[person], state.fetch('links')[person],
          request && [request['to'], request['key']]]
      end
      Digest::SHA256.hexdigest(JSON.generate(['partnership-v1', values]))
    end

    def apply(row, organizer:)
      actor = row['__insertion_user'].downcase
      account = %w[removal pairing partnership pair_draw].include?(row['kind']) ? row['account'] : actor
      case row['kind']
      when 'join'
        @active[account] ||= row['__id']
        @names[account] ||= row['__insertion_user']
      when 'withdrawal', 'removal'
        @active.delete(account)
        dissolve(account, row) if @links[account]
        clear_requests([account], row)
      when 'pairing'
        legacy(row, organizer) unless @modern
      when 'partnership'
        partner = row['partner']
        current = self.class.choice_generation({'epochs'=>@active, 'links'=>@links, 'requests'=>@requests}, actor, partner)
        return unless account == actor && @active[actor] && row['pairing_generation'] == current
        return unless partner.nil? || (@active[partner] && partner != actor)
        body = self.class.body(row)
        return unless change(body, actor, partner, row)
        @modern = true
        @applied << row['__id']
      when 'pair_draw'
        return unless (@active[actor] || organizer) && row['pairing_generation'] == draw_generation
        free = @active.keys.reject { |person| @links[person] }.sort
        return unless free.length.positive? && free.length.even?
        seed = self.class.body(row).fetch('seed').to_i(16)
        GameRoomRandom.shuffle(free, random: Random.new(seed)).each_slice(2) do |a, b|
          establish(a, b, row, automatic: true)
        end
        @modern = true
        @applied << row['__id']
      end
    end

    def state
      Data.freeze_tree(Data.copy({'generation'=>generation, 'draw_generation'=>draw_generation,
        'links'=>@links, 'requests'=>@requests, 'active'=>@active.keys.sort, 'epochs'=>@active, 'modern'=>@modern}))
    end

    private

    def change(body, actor, partner, row)
      case body['action']
      when 'request'
        return false unless partner && !@links[actor] && !@links[partner]
        return false if @requests[actor]&.fetch('to') == partner
        notice('cancelled', actor, @requests[actor]['to'], row, @requests[actor]['key']) if @requests[actor]
        @requests[actor] = {'to'=>partner, 'key'=>row['operation_key']}
        notice('requested', actor, partner, row, row['operation_key'])
      when 'accept', 'decline'
        request = @requests[partner]
        return false unless partner && request && request['to'] == actor && request['key'] == body['request_key']
        return false if @links[actor] || @links[partner]
        if body['action'] == 'accept'
          establish(actor, partner, row)
        else
          @requests.delete(partner)
          notice('declined', actor, partner, row, request['key'])
        end
      when 'cancel'
        request = @requests[actor]
        return false unless request && request['key'] == body['request_key']
        @requests.delete(actor)
        notice('cancelled', actor, request['to'], row, request['key'])
      when 'dissolve'
        return false unless @links[actor] && partner == @links[actor]
        dissolve(actor, row)
      end
      true
    end

    def establish(a, b, row, automatic: false)
      @links[a], @links[b] = b, a
      clear_requests([a, b], row)
      notice(automatic ? 'assigned' : 'established', a, b, row)
    end

    def dissolve(account, row)
      partner = @links.delete(account)
      @links.delete(partner)
      notice('dissolved', account, partner, row) if partner
    end

    def clear_requests(people, row)
      @requests.delete_if do |from, request|
        remove = people.include?(from) || people.include?(request['to'])
        notice('cancelled', from, request['to'], row, request['key']) if remove && !(people.include?(from) && people.include?(request['to']))
        remove
      end
    end

    def notice(kind, from, to, row, request_key = nil)
      return unless @modern || KINDS.include?(row['kind'])
      @changes << {'kind'=>kind, 'from'=>from, 'to'=>to, 'request_key'=>request_key,
        'key'=>row['operation_key'], 'row_id'=>row['__id'], 'author'=>row['__insertion_user'].downcase,
        'from_name'=>@names.fetch(from, from), 'to_name'=>@names.fetch(to, to), 'time'=>row['__insertion_time'],
        'index'=>@changes.last&.fetch('row_id') == row['__id'] ? @changes.last.fetch('index') + 1 : 0}
      @changes.shift while @changes.size > 512
    end

    def legacy(row, organizer)
      account, partner = row.values_at('account', 'partner')
      old_generation = Digest::SHA256.hexdigest(JSON.generate([@active.keys.sort, @links.select { |a,b| a < b }.sort]))
      return unless old_generation == row['pairing_generation'] && @active[account] && (partner.nil? || @active[partner])
      return if !organizer && partner && @links[partner] && @links[partner] != account
      @applied << row['__id']
      @links.delete(@links.delete(account))
      @requests.delete(account)
      if partner && ((organizer && row['__insertion_user'].downcase != account) || @requests[partner]&.fetch('to') == account)
        @links.delete(@links.delete(partner))
        @links[account], @links[partner] = partner, account
        @requests.delete_if { |from, request| [account,partner].include?(from) || [account,partner].include?(request['to']) }
      elsif partner
        @requests[account] = {'to'=>partner, 'key'=>row['operation_key']}
      else
        @requests.delete_if { |_, request| request['to'] == account }
      end
    end
  end
end
