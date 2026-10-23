# encoding: UTF-8
require_relative 'preferences'
require_relative '../game_room_ui'

require_relative "../game_room_localization"

module GameRoomPong
  using GameRoomLocalization::Translations
  # The category and quick dialog use precisely the same fields and defaults.
  class SettingsFields
    attr_reader :fields
    def _(text); GameRoomContent.utf8(super(text)); end
    def initialize(values)
      values = Preferences.normalize(values)
      @automatic = CheckBox.new(_('Automatic return (only for you)'), checked: values['auto_return'])
      labels = {'own_volume' => _('Your paddle volume'), 'opponent_volume' => _('Opponent paddle volume'),
        'announcer_volume' => _('Announcer volume')}
      @volumes = labels.to_h do |key, label|
        [key, ListBox.new((0..200).map { |n| "#{n}%" }, header: label, index: values[key], quiet: true)]
      end
      @doubles = ListBox.new([_('By team position'),_('Keep your own sounds the same')],
        header:_('Player sounds in doubles'),index:values['doubles_sounds']=='personal' ? 1 : 0,quiet:true)
      @fields = [@automatic] + @volumes.values + [@doubles]
    end

    def values
      Preferences.normalize(@volumes.to_h { |key, field| [key, field.index.to_i] }.merge(
        'auto_return' => @automatic.checked,'doubles_sounds'=>@doubles.index==1 ? 'personal' : 'seats'))
    end
  end

  class Settings
    def _(text); GameRoomContent.utf8(super(text)); end
    def initialize(values, program:, tick: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @values, @program, @tick, @clock = values, program, tick, clock
    end

    def wait
      require_relative '../realtime/timer' if @tick
      fields = SettingsFields.new(@values)
      save, cancel = Button.new(_('Save')), Button.new(_('Cancel'))
      form = GameRoomUI::Form.new(fields.fields + [save, cancel], program: @program, quiet: true)
      form.accept_button, form.cancel_button = save, cancel
      accepted = false
      save.on(:press) { accepted = true; form.resume }
      cancel.on(:press) { form.resume }
      timer = GameRoomRealtime::Timer.new(clock: @clock, &@tick) if @tick
      form.add_timer(timer) if timer
      form.wait
      accepted ? fields.values : nil
    ensure
      timer&.stop
      form.delete_timer(timer) if form && timer
    end
  end
end
