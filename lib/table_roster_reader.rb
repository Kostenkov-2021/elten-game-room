require_relative 'game_room_background'
require_relative 'game_participants'
require_relative 'game_room_localization'
require_relative 'game_content'

# One explicit request for one view; late replies cannot speak over another
# table, a newly focused control, or a reopened list. No joining or polling.
class GameRoomTableRosterReader
  using GameRoomLocalization::Translations

  def initialize(loader:, selected:, id_for:, active:, speaker:, worker: nil)
    @loader, @selected, @id_for, @active, @speaker = loader, selected, id_for, active, speaker
    runtime = Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
    @worker = worker || GameRoomBackground::Work.new(runtime: runtime)
    @generation = 0
  end

  def invalidate; @generation += 1; end
  def close; invalidate; @worker.close; end

  def request
    return false if @worker.busy? || @worker.closed? || !@active.call
    snapshot = @selected.call
    unless snapshot
      say(_('No table selected.'))
      return false
    end
    @request = [@generation, @id_for.call(snapshot).to_s]
    @worker.start { @loader.call(snapshot) }
  end

  def update
    result = @worker.take
    return unless result
    snapshot = @selected.call
    return unless @active.call && snapshot && @request == [@generation, @id_for.call(snapshot).to_s]
    value, error = result
    if error || !value || value[:status] == :unavailable
      say(_('The table participants are currently unavailable.'))
    elsif value[:status] == :closed
      say(_('This table is no longer available.'))
    elsif value[:status] == :ready
      players = value.fetch(:players).map { |person| GameRoomParticipants.display_name(person) }
      observers = value.fetch(:observers)
      message = players.empty? ? _('No players at this table.') : _('Players: %{players}.') % {players: players.join(', ')}
      message += ' ' + (_('Observers: %{players}.') % {players: observers.join(', ')}) unless observers.empty?
      say(message)
    else
      say(_('The table participants are currently unavailable.'))
    end
  end

  private

  def say(text)
    @speaker.call(GameRoomContent.utf8(text))
  end
end
