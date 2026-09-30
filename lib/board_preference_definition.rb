module GameRoomBoardPreference
  Definition = Struct.new(:key, :values, :command, :state_key, :relative_orientation, keyword_init: true) do
    def read(spec, state)
      return state[state_key] unless relative_orientation
      state['orientation'] != (spec.default_orientation || 'normal')
    end

    def restore(spec, value, state)
      if relative_orientation
        return unless spec.respond_to?(:default_orientation)
        normal = spec.default_orientation || 'normal'
        state['orientation'] = value ? (normal == 'rotated' ? 'normal' : 'rotated') : normal
      elsif value != nil
        state[state_key] = value
      end
    end
  end

  def self.orientation
    Definition.new(key: 'orientation_flipped', values: [true, false],
      command: 'toggle_orientation', state_key: 'orientation', relative_orientation: true)
  end
end
