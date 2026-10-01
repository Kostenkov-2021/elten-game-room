# encoding: UTF-8

require_relative "profile"
require_relative "server_store"
require_relative "warsaw_date"
require_relative "word_bank"

require_relative "../../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  # Account-scoped availability for the daily variant. The protected shared
  # table is private to its inserting account, so changing computers cannot
  # make an opened puzzle available again.
  class KrowaDailyAccess
    def initialize(program, user:, fetch: nil, store: nil, server_tables: nil)
      @user = user.to_s
      @profile = KrowaProfile.new(program, user: @user)
      @store = store || KrowaServerStore.new(
        server_tables: server_tables,
        bank: KrowaWordBank.default,
        user: @user
      )
      @fetch = fetch || -> {
        GameRoomClock.synchronize
        raise GameRoomNetworkErrors::ClockUnavailable, "Unconfirmed server time" unless GameRoomClock.synchronized?
        Time.at(GameRoomClock.now)
      }
      @date = nil
      @completed = nil
    end

    def prepare
      @prepared = true
      @error = nil
      stamp = @fetch.call
      raise "Invalid server time" unless stamp.is_a?(Time)

      @date = GameRoomKrowa::WarsawDate.today_id(clock: -> { stamp.utc })
      @server_time = stamp.to_f
      # Migrate local completions from preview builds before treating the
      # server as authoritative. A missing protected-table stamp fails closed.
      if @store.available?
        synchronized = @store.synchronize_daily(@profile.data["daily"])
        @completed = @store.daily_completed?(@date)
        @completed = true if !synchronized && Array(@profile.data["daily"]).include?(@date)
      else
        @completed = nil
        @error = access_error_message
      end
      self
    rescue StandardError => error
      raise if defined?(EltenAPI::Tasks::Cancelled) && error.is_a?(EltenAPI::Tasks::Cancelled)

      @completed = nil
      @error = access_error_message
      Log.warning("Krowa daily access: #{error.class}: #{error.message}") if defined?(Log)
      self
    end

    def option_definitions(definitions)
      return definitions.to_a unless completed_today?

      definitions.to_a.map do |definition|
        next definition unless definition.key.to_s == "variant"

        filtered = definition.dup
        filtered.choices = definition.choices.to_a.reject { |choice| choice.value.to_s == "daily" }
        filtered.default = filtered.choices.first&.value
        filtered
      end
    end

    def validation_error(options, previous_replay: nil)
      return nil unless options.to_h["variant"].to_s == "daily"
      return @error if @error
      return unavailable_message if completed_today? || completed_in_replay?(previous_replay)

      nil
    end

    # Called immediately before Game Room creates the session. Merely opening
    # the daily puzzle consumes it for this account, independently of whether
    # the player later solves, surrenders or closes the table.
    def consume(options)
      return true unless options.to_h["variant"].to_s == "daily"
      prepare
      return @error if @error
      return unavailable_message if completed_today?

      assignment = @store.assign_daily(@date, now: @server_time)
      return access_error_message unless assignment

      case @store.record_daily_open(@date)
      when :opened
        @completed = true
        options["__daily_day"] = @date
        options["__daily_assignment"] = assignment
        true
      when :already_used
        @completed = true
        unavailable_message
      else
        _("Could not record opening Daily Krowa on the server. Please try again.")
      end
    rescue StandardError => error
      raise if defined?(EltenAPI::Tasks::Cancelled) && error.is_a?(EltenAPI::Tasks::Cancelled)

      Log.warning("Krowa daily start: #{error.class}: #{error.message}") if defined?(Log)
      _("Could not record opening Daily Krowa on the server. Please try again.")
    end

    def close; end

    private

    def completed_today?
      raise "Daily availability was not prepared" unless @prepared
      @completed == true
    end

    def completed_in_replay?(replay)
      state = replay&.state
      return false unless state.to_h.dig(:options, "variant").to_s == "daily"
      return false unless state[:day].to_s == @date

      state[:results].to_h.keys.any? { |name| name.to_s.casecmp(@user).zero? }
    end

    def unavailable_message
      _("Today's Daily Krowa is no longer available. Come back tomorrow for a new word.")
    end

    def access_error_message
      _("Daily Krowa availability could not be checked on the server. Please try again later. Other variants remain available.")
    end
  end
end
