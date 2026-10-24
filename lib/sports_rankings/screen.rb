require_relative 'result'
require_relative '../game_room_ui'
require_relative '../game_room_background'

module GameRoomSportsRankings
  class Screen
    using GameRoomLocalization::Translations

    class Form < GameRoomUI::Form
      attr_accessor :rankings_update
      def update
        super
        rankings_update&.call
      end
    end
    private_constant :Form

    def initialize(program:, game:, service:, today: -> { GameRoomStatistics::Periods.today })
      @program, @game, @service, @today = program, game, service, today
      @user = Session.name.to_s.dup.freeze
      @runtime = program.class.app_runtime if program.class.respond_to?(:app_runtime)
      @closed = false
    end

    def run
      unless @service
        alert(text(_("Sports leaderboards are temporarily unavailable.")))
        return
      end
      index = 0
      loop do
        selected = choose([_('Single'), _('Doubles')], header: @game.name, index: index)
        break if selected.nil?
        index, @mode = selected, selected.zero? ? 'singles' : 'doubles'
        show_periods
      end
    end

    def close
      @closed = true
      @token&.cancel
      @work&.close
    end

    private

    def current?
      !@closed && GameRoomParticipants.same?(@user, Session.name) &&
        (!@runtime || @program.class.app_runtime.equal?(@runtime))
    end

    def text(value); GameRoomContent.utf8(value); end

    def choose(options, header:, index: 0)
      list = ListBox.new(options.map { |option| text(option) }, header: text(header), index: index, quiet: true)
      open_button, back = Button.new(text(_('Open'))), Button.new(text(_('Back')))
      form = GameRoomUI::Form.new([list, open_button, back], program: @program, quiet: true)
      form.accept_button, form.cancel_button = open_button, back
      form.hide(open_button)
      form.hide(back)
      selected = nil
      open_button.on(:press) { selected = list.index; form.resume }
      back.on(:press) { form.resume }
      form.wait
      selected if current?
    end

    def show_periods
      index = 0
      labels = [_('My statistics'), _('Leaderboard: last 7 days'), _('Leaderboard: last 30 days'),
        _('Leaderboard: last six months'), _('Leaderboard: last year')]
      while current?
        selected = choose(labels, header: heading, index: index)
        break if selected.nil?
        index = selected
        show_results(selected, labels.fetch(selected))
      end
    end

    def heading
      text(_('%{game}: %{mode}')) % {game: text(@game.name), mode: text(@mode == 'doubles' ? _('Doubles') : _('Single'))}
    end

    def range(index, today)
      first = case index
      when 0 then nil
      when 1 then today - 6
      when 2 then today - 29
      when 3 then (today << 6) + 1
      when 4 then (today << 12) + 1
      else raise ArgumentError, 'Unknown leaderboard period'
      end
      [first&.strftime('%Y%m%d')&.to_i, today.strftime('%Y%m%d').to_i]
    end

    def show_results(index, label)
      @rows = []
      control = if index.zero?
        EditBox.new(text(_('My statistics')), type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
          text: text(_('Loading statistics')), quiet: true)
      else
        TableBox.new([_('Place'), _('User')].map { |value| text(value) }, [],
          header: text(label), empty_label: text(_('Loading statistics')), quiet: true)
      end
      details = Button.new(text(_('Player statistics')))
      refresh, back = Button.new(text(_('Refresh'))), Button.new(text(_('Back')))
      @form = Form.new([control, refresh, details, back], program: @program, quiet: true)
      @form.cancel_button = back
      @form.accept_button = details unless index.zero?
      @form.hide(details)
      back.on(:press) { @form.resume }
      details.on(:press) do
        next if index.zero?
        next unless @form.fields[@form.index].equal?(control) && @rows[control.index]
        show_details(@rows.fetch(control.index), label)
      end
      @work = GameRoomBackground::Work.new
      refresh.on(:press) { request_results(index, control, fresh: true) }
      @form.rankings_update = -> { receive_results(index, control) }
      request_results(index, control)
      @form.wait
    ensure
      @token&.cancel
      @work&.close
      @work = @token = nil
      @form.rankings_update = nil if @form
    end

    def request_results(index, control, fresh: false)
      return unless current? && !@work.busy?
      @token = EltenAPI::Tasks::CancellationToken.new
      token, mode = @token, @mode
      @work.start do
        token.raise_if_cancelled!
        raise Unavailable, 'Leaderboard account changed' unless current?
        GameRoomClock.synchronize
        from, to = range(index, @today.call)
        @service.store.report(game: @game.id, mode: mode, from_day: from, to_day: to, cancellation_token: token, fresh: fresh)
      end
    rescue EltenAPI::Tasks::Busy => error
      show_error(control, error)
    end

    def receive_results(index, control)
      return @form.resume unless current?
      return unless (outcome = @work.take)
      rows, error = outcome
      return show_error(control, error || Unavailable.new('Missing leaderboard response')) unless rows.is_a?(Array) && !error
      selected = @rows[control.index]&.fetch('user') unless index.zero?
      @rows = rows
      if index.zero?
        own = rows.find { |row| GameRoomParticipants.same?(row.fetch('user'), @user) } || empty_statistics(@user)
        control.set_text(statistics_text(own))
      else
        control.rows = rows.map { |row| [row.fetch('place').to_s, text(row.fetch('user'))] }
        control.empty_label = text(_('No published results'))
        control.reload
        control.index = rows.index { |row| row['user'] == selected } || 0
      end
      control.focus if @form.fields[@form.index].equal?(control) && @form.game_room_hotkeys_active? && !@form.game_room_background_help?
    end

    def show_error(control, error)
      Log.warning("Sports leaderboard read failed: #{error.class}") if defined?(Log)
      message = text(_('Sports leaderboards are unavailable. Try Refresh.'))
      @rows = []
      if control.is_a?(EditBox)
        control.set_text(message)
      else
        control.rows = []
        control.empty_label = message
        control.reload
      end
    end

    def empty_statistics(user)
      {'user'=>user, 'won'=>0, 'lost'=>0, 'scored'=>0, 'conceded'=>0, 'points'=>0.0}
    end

    def statistics_text(row)
      [text(_('Matches won: %{count}')) % {count: row.fetch('won')},
        text(_('Matches lost: %{count}')) % {count: row.fetch('lost')},
        text(_('Match balance: %{count}')) % {count: row.fetch('won') - row.fetch('lost')},
        text(_('Goals scored: %{count}')) % {count: row.fetch('scored')},
        text(_('Goals conceded: %{count}')) % {count: row.fetch('conceded')},
        text(_('Goal balance: %{count}')) % {count: row.fetch('scored') - row.fetch('conceded')}].join("\n")
    end

    def show_details(row, period)
      field = EditBox.new(text(_('%{player}: %{period}')) % {player: text(row.fetch('user')), period: text(period)},
        type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine, text: statistics_text(row), quiet: true)
      back = Button.new(text(_('Back')))
      form = GameRoomUI::Form.new([field, back], program: @program, quiet: true)
      form.cancel_button = back
      back.on(:press) { form.resume }
      form.wait
    end
  end
end
