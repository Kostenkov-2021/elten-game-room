module GameSurfaces
  module StateReader
    MISSING = Object.new.freeze
    module_function

    def fetch(state, key, default)
      return default if !state.respond_to?(:key?)
      return state[key] if state.key?(key)
      return state[key.to_sym] if state.key?(key.to_sym)
      default
    end

    def integer(state, key, default)
      value = fetch(state, key, MISSING)
      value.equal?(MISSING) ? default : value.to_i
    end

    private

    def state_value(state, key, default)
      StateReader.fetch(state, key, default)
    end
  end
end
