require_relative '../network_errors'

module GameRoomRealtime
  module Errors
    def self.expected?(error)
      # A rejected payload cannot become valid through reconnecting. Preserve
      # its native diagnostic and stop the faulty producer like a local bug.
      return false if defined?(EltenAPI::Communication::MessageTooLarge) && error.is_a?(EltenAPI::Communication::MessageTooLarge)
      GameRoomNetworkErrors.expected?(error) || GameRoomNetworkErrors.cancelled?(error) ||
        (defined?(EltenAPI::Communication::Error) && error.is_a?(EltenAPI::Communication::Error))
    end
  end
end
