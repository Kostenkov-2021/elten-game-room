module GameRoomAudioBall
  # The same immutable seat order drives service and each successive return.
  module Rotation
    module_function
    def order(teams)
      raise ArgumentError,'Invalid Audio Ball teams' unless teams==[0,1] ||
        (teams.is_a?(Array) && teams.size==4 && teams.count(0)==2 && teams.count(1)==2)
      a=teams.each_index.select { |seat| teams[seat]==0 }
      b=teams.each_index.select { |seat| teams[seat]==1 }
      a.zip(b).flatten.freeze
    end
    def seat(teams, first, offset)
      ring=order(teams)
      ring[(ring.index(first)+offset)%ring.length]
    end
  end
end
