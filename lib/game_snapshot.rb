# An owned snapshot preserves Ruby value types, internal aliases and cycles,
# while sharing no mutable model with its producer. Copy failure is explicit;
# callers that can rebuild a projection own that narrowly scoped fallback.
module GameRoomSnapshot
  def self.copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
