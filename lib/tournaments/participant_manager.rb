require_relative 'ui_dialogs'
require_relative 'participant_rows'
require_relative 'tournament_invitation_screen'
require_relative '../game_shortcut_bindings'
require_relative 'tournament_lifecycle'
require_relative 'view_refresh'

module GameRoomTournaments
  class ParticipantManager < Dialogs::Window
    using GameRoomLocalization::Translations
    def initialize(program:, workspace:, owner:, publication:, confirm:, alert:, invite: nil, clock: -> { GameRoomClock.now.to_i }, member_accounts: nil)
      @program, @workspace, @owner, @publication, @confirm, @alert, @invite, @clock = program, workspace, owner, publication, confirm, alert, invite, clock
      @member_accounts = member_accounts&.sort&.freeze
      @attempted = {}
    end
    private
    def build_form
      return unless @owner.check
      @list = ListBox.new([], header: text(@member_accounts ? _("Team members") : _("Participants")), quiet: true)
      back = button(_("Back"))
      make_form([@list, back], cancel: back)
      reference = {'author'=>@publication['__insertion_user'].downcase, 'publication_key'=>@publication['publication_key']}
      @view_refresh = ViewRefresh.new(@program, reference: reference) { interaction(focus: false) { refresh_members } }
      @form.hub_update = -> { @view_refresh.tick unless @busy || @finished }
      @form.hide(back)
      @list.on(:select) { interaction { open_user } }
      @list.bind_context { |menu| context(menu) }
      shortcuts = [
        ['i', [:control], :invite, _("Invite to tournament")],
        ['l', [:control], :invitations, _("Invited users")],
        ['delete', [], :remove, _("Remove selected participant")],
        ['r', [:control], :refresh, _("Refresh")]
      ].map { |key, modifiers, action, label| GameRoomGames::GameShortcut.new(key: key, modifiers: modifiers, kind: :action, action_kind: 'tournament', action_name: action.to_s, label: text(label)) }
      GameRoomShortcutBindings.bind(@form, [@list], shortcuts, consume: ->(_) { EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState) }) do |shortcut|
        interaction { execute(shortcut.action_name.to_sym) }
      end
      refresh_members
    end
    def organizer?
      @owner.current&.downcase == @publication['__insertion_user'].downcase
    end
    def editable?
      !@stale && @group_current != false && organizer? && [:soon, :registration, :waiting].include?(TournamentLifecycle.classify(@publication, now: @clock.call)[:state])
    end
    def pair_game?
      settings = JSON.parse(@publication['settings_json'])
      @workspace.registry.build(@publication['game']).team_size(settings['game_options'], player_count: settings['players_per_match']).to_i > 1
    end
    def selected_row
      @rows&.[](@list.index) if @list.index && @list.index >= 0
    end
    def selected
      row = selected_row
      @members.find { |person| person['account'] == row['accounts'].first } if row && row['accounts'].length == 1
    end
    def open_user
      row = selected_row
      return unless row && @owner.check
      if row['accounts'].length > 1
        ParticipantManager.new(program: @program, workspace: @workspace, owner: @owner, publication: @publication,
          confirm: @confirm, alert: @alert, invite: @invite, clock: @clock, member_accounts: row['accounts']).run
        refresh_members
        return
      end
      person = selected
      @program.send(:usermenu, person['username']) if person && @owner.check
    end
    def context(menu)
      available_actions.each do |action, label, key|
        account = selected&.fetch('account')
        row_key = selected_row&.fetch('key')
        menu.option(text(label), nil, key) { interaction { execute(action, account: account, row_key: row_key) } }
      end
    end
    def available_actions
      actions = []
      actions << [:members, _("Team members"), :Enter] if selected_row && selected_row['accounts'].length > 1 && !@stale
      if editable?
        actions << [:invite, _("Invite to tournament"), 'i'] if @invite && TournamentTiming.registration_open?(@publication, @clock.call)
        actions << [:remove, _("Remove selected participant"), :Delete] if selected
      end
      actions << [:invitations, _("Invited users"), 'l'] if organizer? && !@stale
      actions << [:refresh, _("Refresh"), 'r']
      actions
    end
    def execute(action, account: selected&.fetch('account'), row_key: selected_row&.fetch('key'))
      return unless @owner.check
      return if %i[remove members].include?(action) && row_key != selected_row&.fetch('key')
      return if action == :remove && account != selected&.fetch('account')
      return unless available_actions.any? { |item| item.first == action }
      case action
      when :members then open_user
      when :refresh then refresh_members
      when :invite then @invite.call(@publication); refresh_members
      when :invitations
        TournamentInvitationScreen.new(program: @program, workspace: @workspace, owner: @owner, publication: @publication, clock: @clock).run
      when :remove then remove_selected(account)
      end
    end
    def refresh_members
      return unless @owner.check
      @view_refresh&.acknowledge
      snapshot = @workspace.load
      return unless snapshot && @owner.check
      current = snapshot['announcements'].find { |row| row['__id'] == @publication['__id'] && row['publication_key'] == @publication['publication_key'] && row['__insertion_user'] == @publication['__insertion_user'] }
      @stale = current.nil?
      @publication = current if current
      @attempted.delete_if { |_account, status| status == :confirmed } if current
      @members = snapshot['members'].select { |person| person['tournament_id'] == @publication['__id'] }
      teams = pair_game? ? snapshot.fetch('pairs', []).select { |pair| pair['tournament_id'] == @publication['__id'] } : []
      @rows = ParticipantRows.build(@members, teams)
      if @member_accounts
        @group_current = @rows.any? { |row| row['accounts'] == @member_accounts }
        @rows = @members.select { |person| @member_accounts.include?(person['account']) }.map do |person|
          {'key'=>"person:#{person['account']}", 'accounts'=>[person['account']], 'names'=>[person['username']]}
        end
      end
      @list.update_options(@rows.map { |row| text(row['names'].join(', ')) }, keys: @rows.map { |row| row['key'] })
      @list.extend(GameRoomContextHelp::DynamicTips) unless @list.is_a?(GameRoomContextHelp::DynamicTips)
      @list.game_room_context_help_provider = -> { available_actions.map { |_action, label, key| GameRoomContextHelp.shortcut_tip(key.is_a?(Symbol) ? key.to_s : "Ctrl+#{key.upcase}", label) } }
      @list.game_room_game_help_tips = @rows.empty? ? [text(_("No participants."))] : []
    end
    def remove_selected(account)
      person = selected
      return unless person && person['account'] == account
      return @alert.call(text(_("Check Operations before trying again."))) if @attempted[account]
      return unless @confirm.call(text(_("Remove participant %{player}?")) % {player: person['username']})
      refresh_members
      return unless editable? && @members.any? { |entry| entry['account'] == account }
      @attempted[account] = true
      result = @workspace.remove_participant(@publication['__id'], account)
      @attempted[account] = :confirmed if result && result['status'] == 'confirmed'
      @alert.call(text(result && result['status'] == 'confirmed' ? _("Participant removal confirmed.") : _("Participant removal not confirmed. Check Operations before trying again.")))
      refresh_members
    end
  end
end
