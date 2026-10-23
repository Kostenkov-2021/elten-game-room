require_relative 'difficulty'
require_relative 'rotation'

module GameRoomAudioBall
  class Engine
    WIDTH = 25.0
    SHOTS = %w[up left down].map(&:freeze).freeze
    INITIAL_DURATION = Difficulty::PROFILES.map { |profile| profile.fetch(:duration) }.freeze
    ACCELERATION = Array.new(Difficulty::PROFILES.length, Difficulty::SPEED_MULTIPLIER).freeze

    attr_reader :phase, :holder, :receiver, :shot, :turn, :goal, :warning,
      :duration, :position, :hits, :server, :level

    def initialize(level: 1, server: 0, teams: [0,1])
      @teams=teams.dup.freeze
      Rotation.order(@teams)
      raise ArgumentError, 'level must be an integer from 1 to 5' unless valid_level?(level)
      raise ArgumentError, 'Invalid server seat' unless valid_side?(server)
      @level = level
      @server = server
      @phase = :waiting
      @holder = server
      @receiver = @shot = @goal = @warning = @fault = nil
      @turn = @hits = 0
      @duration = INITIAL_DURATION[level - 1]
      @position = endpoint(server)
      @transitions = []
    end

    def press(side, command)
      if @phase == :flying
        return false unless side == @receiver && command == @shot
        return false unless (@position - endpoint(side)).abs <= 2.0 + 1e-12
        return emit('defend', side, 'shot' => @shot)
      end
      return false unless side == @holder
      if @phase == :waiting && command == 'prepare'
        emit('prepare', side)
      elsif @phase == :prepared && SHOTS.include?(command)
        emit('hit', side, 'shot' => command)
      else
        false
      end
    end

    def warn(side)
      return false unless valid_side?(side)
      return false unless [:waiting, :prepared].include?(@phase)
      return false unless team(side) != team(@holder) && @warning.nil?
      @warning = 10.0
      true
    end

    def team(seat); @teams.fetch(seat); end
    def active_seat; @phase==:flying ? @receiver : @holder; end
    def wrong_turn?(side)
      @teams.length == 4 && @phase == :flying && partner_of?(side, @receiver)
    end

    def wrong_turn(side)
      return false unless wrong_turn?(side)
      emit('wrong_turn',side)
    end

    def step(seconds, controlled: [0, 1], defenses: {})
      raise ArgumentError, 'seconds must be finite and nonnegative' unless finite_number?(seconds) && seconds >= 0
      unless controlled.is_a?(Array) && controlled.all? { |side| valid_side?(side) }
        raise ArgumentError, 'controlled must contain valid player seats'
      end
      unless defenses.is_a?(Hash) && defenses.all? { |side, shot| valid_side?(side) && SHOTS.include?(shot) }
        raise ArgumentError, 'defenses must map player sides to shot types'
      end
      if @phase == :flying
        @elapsed = [@elapsed + seconds, @duration].min
        @elapsed = @duration if @duration - @elapsed <= @duration * 1e-12
        progress = @elapsed / @duration
        @position = team(@receiver) == 0 ? WIDTH * progress : WIDTH * (1.0 - progress)
        if controlled.include?(@receiver)
          if defenses[@receiver] == @shot && (@position - endpoint(@receiver)).abs <= 2.0 + 1e-12
            emit('defend', @receiver, 'shot' => @shot)
          elsif @elapsed >= @duration
            emit('miss', @receiver)
          end
        end
      elsif @warning
        @warning = [@warning - seconds, 0.0].max
        @warning = 0.0 if @warning <= 1e-12
        emit('miss', @holder, 'reason' => 'timeout') if @warning.zero? && controlled.include?(@holder)
      end
    end

    def apply(data)
      if @phase==:over && @teams.length==4 && data['action']=='wrong_turn' && @fault.nil? &&
          data.keys.sort==%w[action side turn] && data['turn']==@turn && @hits > 0 && @turn == 3 * @hits &&
          partner_of?(data['side'], Rotation.seat(@teams,@server,@hits))
        @fault=data['side']
        @goal=1-team(@fault)
        return true
      end
      return false unless valid_transition?(data) && allowed_transition?(data)
      side = data['side']
      case data['action']
      when 'prepare'
        @phase = :prepared
      when 'hit'
        @phase = :flying
        @receiver = Rotation.seat(@teams,side,1)
        @holder = nil
        @shot = SHOTS.find { |value| value == data['shot'] }
        @duration /= ACCELERATION[@level - 1] if @hits > 0
        @hits += 1
        @elapsed = 0.0
        @warning = nil
      when 'defend'
        @phase = :waiting
        @holder = side
        @receiver = @shot = nil
        @position = endpoint(side)
      when 'miss'
        @phase = :over
        @goal = 1 - team(side)
        @position = endpoint(side)
        @holder = @receiver = @shot = @warning = nil
      when 'wrong_turn'
        @phase=:over
        @fault=side
        @goal=1-team(side)
        @holder=@receiver=@shot=@warning=nil
      end
      @turn = data['turn']
      true
    end

    def snapshot
      value={'phase' => @phase.to_s, 'holder' => @holder, 'receiver' => @receiver,
        'shot' => @shot, 'turn' => @turn, 'goal' => @goal, 'warning' => @warning,
        'duration' => @duration, 'position' => @position, 'hits' => @hits,
        'server' => @server, 'level' => @level}
      value['fault']=@fault if @teams.length==4
      value
    end

    def restore(data)
      return false unless valid_snapshot?(data)
      @phase = data['phase'].to_sym
      @holder = data['holder']
      @receiver = data['receiver']
      @shot = SHOTS.find { |value| value == data['shot'] }
      @turn = data['turn']
      @goal = data['goal']
      @fault=data['fault']
      @warning = data['warning']
      @duration = data['duration']
      @position = data['position']
      @hits = data['hits']
      @server = data['server']
      @level = data['level']
      if @phase == :flying
        @elapsed = @duration * (team(@receiver) == 0 ? @position : WIDTH - @position) / WIDTH
      end
      @transitions.clear
      true
    end

    def take_transition
      @transitions.shift
    end

    private

    def partner_of?(side, receiver)
      valid_side?(side) && valid_side?(receiver) && side != receiver && team(side) == team(receiver)
    end

    def endpoint(side)
      team(side) == 0 ? WIDTH : 0.0
    end

    def valid_side?(side)
      side.is_a?(Integer) && side.between?(0,@teams.length-1)
    end

    def finite_number?(value)
      (value.is_a?(Integer) || value.is_a?(Float)) && value.finite?
    end

    def valid_level?(value)
      Difficulty.valid?(value)
    end

    def valid_snapshot?(data)
      return false unless data.is_a?(Hash) && data.keys.all? { |key| key.is_a?(String) }
      keys=%w[duration goal hits holder level phase position receiver server shot turn warning]
      keys << 'fault' if @teams.length==4
      return false unless data.keys.sort == keys.sort
      return false unless valid_level?(data['level']) && valid_side?(data['server'])
      return false unless %w[waiting prepared flying over].include?(data['phase'])
      return false unless %w[holder receiver fault].all? { |key| data[key].nil? || valid_side?(data[key]) }
      return false unless [nil,0,1].include?(data['goal'])
      return false if data['fault'] && data['phase']!='over'
      return false unless %w[turn hits].all? { |key| data[key].is_a?(Integer) && data[key] >= 0 }
      return false unless finite_number?(data['position']) && data['position'].between?(0, WIDTH)
      return false unless finite_number?(data['duration']) && data['duration'] > 0
      warning = data['warning']
      return false unless warning.nil? || (finite_number?(warning) && warning.between?(0, 10))
      hits = data['hits']
      expected_duration = INITIAL_DURATION[data['level'] - 1] / ACCELERATION[data['level'] - 1] ** [hits - 1, 0].max
      return false unless (data['duration'] - expected_duration).abs <= expected_duration * 1e-10
      owner = Rotation.seat(@teams,data['server'],hits)
      case data['phase']
      when 'waiting', 'prepared'
        expected_turn = 3 * hits + (data['phase'] == 'prepared' ? 1 : 0)
        data['holder'] == owner && data['receiver'].nil? && data['shot'].nil? &&
          data['goal'].nil? && data['turn'] == expected_turn && data['position'] == endpoint(owner)
      when 'flying'
        hits > 0 && data['holder'].nil? && data['receiver'] == owner && SHOTS.include?(data['shot']) &&
          data['goal'].nil? && warning.nil? && data['turn'] == 3 * hits - 1
      when 'over'
        offset = data['turn'] - 3 * hits
        valid_end = (offset == 0 && hits > 0) || offset == 1 || offset == 2
        fault=data['fault']
        valid_end && (fault ? offset == 0 && hits > 0 && partner_of?(fault, owner) && data['goal']==1-team(fault) : data['goal']==1-team(owner) && data['position']==endpoint(owner)) &&
          data['holder'].nil? && data['receiver'].nil? && data['shot'].nil? && warning.nil?
      end
    end

    def valid_transition?(data)
      return false unless data.is_a?(Hash) && data.keys.all? { |key| key.is_a?(String) }
      return false unless valid_side?(data['side']) && data['turn'].is_a?(Integer) && data['turn'] == @turn + 1
      keys = %w[action side turn]
      case data['action']
      when 'prepare', 'wrong_turn'
      when 'hit', 'defend'
        return false unless SHOTS.include?(data['shot'])
        keys << 'shot'
      when 'miss'
        if data.key?('reason')
          return false unless data['reason'] == 'timeout'
          keys << 'reason'
        end
      else
        return false
      end
      data.keys.sort == keys.sort
    end

    def allowed_transition?(data)
      case data['action']
      when 'wrong_turn'
        wrong_turn?(data['side'])
      when 'prepare'
        @phase == :waiting && data['side'] == @holder
      when 'hit'
        @phase == :prepared && data['side'] == @holder
      when 'defend'
        @phase == :flying && data['side'] == @receiver && data['shot'] == @shot
      when 'miss'
        if data['reason'] == 'timeout'
          [:waiting, :prepared].include?(@phase) && !@warning.nil? && data['side'] == @holder
        else
          @phase == :flying && data['side'] == @receiver
        end
      end
    end

    def emit(action, side, extra = {})
      data = {'action' => action, 'side' => side, 'turn' => @turn + 1}.merge(extra)
      return false unless apply(data)
      data['shot'] = SHOTS.find { |value| value == data['shot'] } if data.key?('shot')
      @transitions << data
      true
    end
  end
end
