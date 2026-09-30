require "timeout"
require_relative "../support/widget"

entered, release = Queue.new, Queue.new
calls, running, maximum, now = 0, 0, 0, 0.0
foreground_calls = 0
widget = GameRoomWidget::TableList.new(
  loader: -> do
    calls += 1
    number = calls
    running += 1
    maximum = [maximum, running].max
    begin
      if number == 2
        entered << true
        release.pop
      end
      [WidgetSnapshot.new(table: { "__id" => number })]
    ensure
      running -= 1
    end
  end,
  opener: ->(_) {}, labeler: ->(row) { row.table["__id"].to_s },
  id_for: ->(row) { row.table["__id"] }, clock: -> { now },
  foreground: ->(&operation) do
    foreground_calls += 1
    release << true if foreground_calls == 2
    operation.call
  end
)
Timeout.timeout(5) do
  widget.focus
  now = 5.0
  widget.update
  entered.pop
  widget.focus
  assert(widget.focus_texts == ["1", "3"], "entry read the old in-flight result")
  10.times { Thread.pass; widget.update }
  assert(maximum == 1 && calls == 3, "foreground/background discovery requests overlapped")
  assert(widget.options == ["3"] && widget.sayoption_count.to_i == 0, "late timer changed the current entry or interrupted speech")
end
widget.close
puts "Real background thread and Tab entry serialize requests without reusing the old timer result."
