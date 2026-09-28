# Explicitly fired timer for scripted forms; no host clock or background loop.
class FormTimer
  def initialize(_interval, repeat:, &callback)
    @callback = callback
  end

  def fire
    @callback.call
  end
end
