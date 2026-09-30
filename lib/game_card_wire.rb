module GameRoomCardWire
  def self.parse_deal(value)
    fields = value.to_s.split('|', -1)
    raise ArgumentError, 'invalid deal' if fields.length != 3
    round = Integer(fields[0], 10)
    dealer = Integer(fields[1], 10)
    seed = fields[2].to_s.downcase
    raise ArgumentError, 'invalid deal seed' if seed !~ /\A[0-9a-f]{32}\z/
    [round, dealer, seed]
  end
end
