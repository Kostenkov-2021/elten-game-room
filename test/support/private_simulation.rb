require_relative '../../lib/game_simulation'
require_relative '../../lib/hidden_submissions'

module GameRoomTest
  # A local vault for contract tests. Production simulations deliberately have
  # no account storage; these fixtures exercise real commit/reveal transitions.
  class PrivateSimulation < GameRoomSimulation::Environment
    def initialize(**arguments)
      super
      @vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
    end

    def context
      super.tap { |value| value.hidden_submissions = @vault }
    end
  end
end
