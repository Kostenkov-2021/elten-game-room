# encoding: UTF-8
require_relative 'ui_dialogs'

module GameRoomTournaments
  class PartnerChoice < Dialogs::Window
    using GameRoomLocalization::Translations
    def initialize(program:, publication:, account:, load:, choose:, action:, alert:, confirm:)
      @program, @publication, @account = program, publication, account.downcase
      @load, @choose, @action, @alert, @confirm = load, choose, action, alert, confirm
    end

    private

    def build_form
      @snapshot = @load.call
      return unless @snapshot
      members, pairs, requests = values(@snapshot)
      return unless members.any? { |person| person['account'] == @account }
      @names = members.to_h { |person| [person['account'], person['username']] }
      @own_pair = pairs.find { |pair| pair['accounts'].include?(@account) }
      @own_request = requests.find { |request| request['from'] == @account }
      @choices = []
      if @own_pair
        partner = (@own_pair['accounts'] - [@account]).first
        status = text(_("Your partner: %{player}")) % {player: @names.fetch(partner)}
        @choices << {action: 'dissolve', partner: partner, key: nil,
          label: text(_("Dissolve partnership with %{player}")) % {player: @names.fetch(partner)}}
      else
        status = @own_request ? text(_("Waiting for %{player} to confirm your partnership.")) % {player: @names.fetch(@own_request['to'])} :
          text(_("Choose a partner or accept an invitation."))
        unavailable = pairs.flat_map { |pair| pair['accounts'] }
        members.reject { |person| person['account'] == @account || unavailable.include?(person['account']) }.each do |person|
          account, name = person.values_at('account', 'username')
          incoming = requests.find { |request| request['from'] == account && request['to'] == @account }
          if incoming
            @choices << {action: 'accept', partner: account, key: incoming['key'],
              label: text(_("Accept partnership with %{player}")) % {player: name}}
            @choices << {action: 'decline', partner: account, key: incoming['key'],
              label: text(_("Decline partnership with %{player}")) % {player: name}} if @action
          elsif @own_request && @own_request['to'] == account
            @choices << {action: 'waiting', partner: account, key: @own_request['key'],
              label: text(_("Waiting for %{player}")) % {player: name}}
          else
            @choices << {action: 'request', partner: account, key: @own_request&.[]('key'), label: name}
          end
        end
        if @own_request
          @choices << {action: 'cancel', partner: nil, key: @own_request['key'], label: text(_("Cancel partner invitation"))}
        end
      end
      @details = GameRoomUI::HelpText.new(text(_("Team")), type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
        text: status, quiet: true)
      @list = ListBox.new(@choices.map { |choice| choice[:label] }, header: text(_("Partner")), quiet: true,
        empty_label: text(_("No available partners.")))
      back = button(_("Back"))
      make_form([@details, @list, back], cancel: back)
      @form.hide(back)
      @list.on(:select) { interaction { submit } }
    end

    def values(snapshot)
      id = @publication['__id']
      [snapshot.fetch('members').select { |person| person['tournament_id'] == id },
        snapshot.fetch('pairs', []).select { |pair| pair['tournament_id'] == id },
        snapshot.fetch('pair_requests', []).select { |request| request['tournament_id'] == id }]
    end

    def submit
      return if @submitted || @list.index.to_i < 0
      choice = @choices[@list.index]
      return unless choice
      if choice[:action] == 'waiting'
        @alert.call(text(_("This partner invitation is still pending.")))
        return
      end
      if choice[:action] == 'dissolve'
        return unless @confirm.call(text(_("Dissolve your partnership with %{player}?")) % {player: @names.fetch(choice[:partner])})
      elsif choice[:action] == 'request' && @own_request
        return unless @confirm.call(text(_("Cancel the invitation to %{old} and invite %{new}?")) %
          {old: @names.fetch(@own_request['to']), new: @names.fetch(choice[:partner])})
      end
      fresh = @load.call
      return unless fresh
      members, pairs, requests = values(fresh)
      own = pairs.find { |pair| pair['accounts'].include?(@account) }
      request = requests.find { |item| item['from'] == @account }
      unless own == @own_pair && request == @own_request && members.any? { |person| person['account'] == @account }
        @alert.call(text(_("The tournament changed. Refresh and choose the action again.")))
        finish
        return
      end
      @submitted = true
      intent = 'partner-choice:' + SecureRandom.uuid
      result = if @action
        @action.call(@publication['__id'], choice[:action], choice[:partner], choice[:key], intent)
      else
        # Compatibility port for older local test compositions. Production
        # supplies the explicit action callback, including request identities.
        partner = %w[cancel dissolve].include?(choice[:action]) ? nil : choice[:partner]
        @choose.call(@publication['__id'], @account, partner, intent)
      end
      message = if result && result['status'] == 'confirmed'
        result.dig('evidence', 'pairing_applied') == false ? _("The tournament changed. Refresh and choose the action again.") : _("Partner choice saved.")
      else
        _("The partner choice could not be confirmed. Refresh to check its status.")
      end
      @alert.call(text(message))
      finish
    end
  end
end
