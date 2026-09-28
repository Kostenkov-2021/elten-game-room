require_relative "../game_room_localization"

module GameRoomRealtime
  using GameRoomLocalization::Translations
  # Tasks.run owns the native UI loop. This optional UI adapter keeps a real-
  # time client alive while its usual game form is detached for a server read
  # or write. It never pumps the UI, refreshes a form, or runs UI on a worker.
  class TaskUI
    def self.updates_form?(ui, form)
      form && (ui.equal?(form) || (ui.is_a?(GameRoomUI::PendingOperation) && ui.form.equal?(form)))
    end

    def initialize(ui:, title:, show_after:, cancellation_token:, clock:, tick:)
      @ui, @title, @show_after, @token = ui, title, show_after, cancellation_token
      @title = GameRoomContent.utf8(@title.to_s)
      @clock, @tick, @started_at = clock, tick, clock.call
    end

    def update
      @tick.call
      if @ui.respond_to?(:update)
        @ui.update
      elsif @ui == nil || @ui == :automatic
        open_wait if !@opened && @clock.call - @started_at >= @show_after
        if @opened && key_pressed?(:key_escape)
          @token.cancel(EltenAPI::Tasks::Cancelled.new('Task cancelled'))
          play_sound('cancel')
        end
      end
    end

    def close
      return unless @opened
      @opened = false
      begin
        waiting_end if @owns_waiting
      ensure
        @owns_waiting = false
        modal_interaction_close
      end
    end

    private

    def open_wait
      modal_interaction_open
      @opened = true
      unless waiting_opened
        @owns_waiting = true
        waiting
      end
      speak([@title, GameRoomContent.utf8(_('Please wait...'))].uniq.join("\n"))
    end
  end
end
