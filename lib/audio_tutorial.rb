require_relative "game_room_localization"

class GameRoomAudioTutorial
  using GameRoomLocalization::Translations
  Entry = Struct.new(:label, :asset, :asset_resolver, keyword_init: true) do
    def initialize(label:, asset:, asset_resolver: nil)
      super(label: GameRoomContent.utf8(label), asset: asset.to_s, asset_resolver: asset_resolver)
    end

    def asset_for(program)
      asset_resolver ? asset_resolver.call(program) : asset
    end
  end

  def initialize(entries, program:)
    @entries = entries
    @program = program
  end

  def wait
    return if @entries.empty?

    build_form.wait
  ensure
    stop
  end

  def open_on(parent)
    return if @entries.empty?

    # The constructor speaks the welcome once. Do not refocus it on opening
    # the overlay; later game refreshes must not interrupt or repeat it.
    parent.open_game_room_background_help(build_form, on_close: method(:stop), focus: false)
  rescue Exception
    stop
    raise
  end

  private

  def build_form
    welcome = GameRoomContent.utf8(_("Welcome to the audio tutorial. Here you will learn the sounds used in this game. Use the arrow keys to browse. Press Space or Enter to play a sound."))
    list = ListBox.new(@entries.map(&:label), header: welcome, quiet: true)
    list.on(:select) { play(@entries[list.index]) }
    list.on(:key_space) { play(@entries[list.index]) if list.send(:key_first_pressed?, :key_space) }
    list.on(:move) { stop }
    GameRoomContextHelp.replace([list], [
      GameRoomContextHelp.shortcut_tip('Enter', _("Play the selected sound")),
      GameRoomContextHelp.shortcut_tip('Space', _("Play the selected sound")),
      GameRoomContextHelp.shortcut_tip('Escape', _("Return to game rules"))
    ])
    form = GameRoomUI::Form.new([list], program: @program, quiet: false)
    list.header = GameRoomContent.utf8(_("Audio tutorial"))
    form.on(:key_escape) { form.resume }
    form
  end

  def play(entry)
    stop
    return unless entry

    asset = entry.asset_for(@program)
    volume = @program.respond_to?(:game_room_sound_volume, true) ? @program.send(:game_room_sound_volume, asset).to_f : 1.0
    enabled = !@program.respond_to?(:game_room_sound_enabled?, true) || @program.send(:game_room_sound_enabled?, asset)
    if !enabled || volume <= 0
      speak(GameRoomContent.utf8(_("This sound is muted in Power Games settings.")))
      return
    end
    @sound = @program.play_sound_from_asset(asset, volume: volume, sample: false, loop: false)
    speak(GameRoomContent.utf8(_("This sound could not be played."))) unless @sound
  end

  def stop
    @sound&.close
    @sound = nil
  end
end
