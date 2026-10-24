require 'json'
require 'digest'
require_relative '../game_participants'
require_relative '../participant_replay'
require_relative '../game_statistics_periods'
require_relative '../game_statistics_store'

module GameRoomSportsRankings
  class InvalidResult < ArgumentError; end
  class Unavailable < GameRoomStatistics::Unavailable; end

  # An immutable, terminal match, shared by ordinary and tournament reporting.
  # No networking, clock synchronisation or storage belongs in this projection.
  module Result
    GAMES = %w[axel_pong audio_ball].freeze
    FIELDS = %w[match_key game mode finished_at day_key result_json].freeze
    module_function

    def build(identity:, game:, finished_at:, sides:, winner:)
      raise InvalidResult, 'Missing match identity' unless identity.is_a?(String) && identity.bytesize.between?(1, 2048)
      document = {'version'=>1, 'sides'=>sides, 'winner'=>winner}
      row = {'match_key'=>Digest::SHA256.hexdigest(identity), 'game'=>game,
        'mode'=>sides.first.fetch('players').size == 2 ? 'doubles' : 'singles',
        'finished_at'=>finished_at, 'day_key'=>day(finished_at), 'result_json'=>JSON.generate(document)}
      parse(row)
      row.to_h { |key, value| [key.freeze, value.is_a?(String) ? value.dup.freeze : value] }.freeze
    end

    def parse(row)
      unless row.is_a?(Hash) && /\A[0-9a-f]{64}\z/.match?(row['match_key'].to_s) &&
          GAMES.include?(row['game']) && %w[singles doubles].include?(row['mode']) &&
          row['finished_at'].is_a?(Integer) && row['finished_at'].between?(1, 253402214399) && row['day_key'] == day(row['finished_at']) &&
          row['result_json'].is_a?(String) && row['result_json'].bytesize <= 4096
        raise InvalidResult, 'Invalid match report'
      end
      value = JSON.parse(row['result_json'], max_nesting: 8)
      unless value.is_a?(Hash) && value.keys.sort == %w[sides version winner] && value['version'] == 1 &&
          value['winner'].is_a?(Integer) && [0, 1].include?(value['winner']) && value['sides'].is_a?(Array) && value['sides'].size == 2
        raise InvalidResult, 'Invalid match outcome'
      end
      size = row['mode'] == 'doubles' ? 2 : 1
      players = value['sides'].flat_map do |side|
        unless side.is_a?(Hash) && side.keys.sort == %w[goals players] &&
            side['goals'].is_a?(Integer) && side['goals'].between?(0, 1_000_000_000) &&
            side['players'].is_a?(Array) && side['players'].size == size && side['players'].all? { |name|
              name.is_a?(String) && name.valid_encoding? && !name.strip.empty? && name.bytesize <= 64 &&
                name == name.strip && !name.start_with?('bot:')
            }
          raise InvalidResult, 'Invalid ranked participants or goals'
        end
        side['players']
      end
      raise InvalidResult, 'Repeated ranked participant' unless players.map(&:downcase).uniq.size == size * 2
      value
    rescue JSON::ParserError, EncodingError => error
      raise InvalidResult, "Invalid match encoding: #{error.class}"
    end

    def from_replay(game:, session:, replay:)
      return unless replay && replay.finished? && !replay.draw && !session['__aborted'] &&
        game.respond_to?(:sports_ranking_result) && !session['__tournament_match']
      terminal = replay.accepted_events.last
      return unless terminal && terminal['created_at'].is_a?(Integer) && terminal['created_at'].positive?
      # Later replacements must not rewrite the roster at the winning point.
      roster = GameRoomParticipantReplay.roster_at(session, (terminal['__id'] || terminal['id']).to_i + 1)
      return if roster.any? { |player| GameRoomParticipants.bot?(player) }
      return if session.fetch('__controllers', {}).any? { |person, controller|
        controller == 'bot' && GameRoomParticipants.includes?(roster, person)
      }
      outcome = game.sports_ranking_result(replay)
      return unless outcome
      sides = outcome.fetch(:sides).map do |side|
        {'players'=>side.fetch(:seats).map { |seat| roster.fetch(seat) }.sort_by(&:downcase), 'goals'=>side.fetch(:goals)}
      end
      identity = session.dig('__statistics', 'id')
      return unless identity.is_a?(String) && !identity.empty?
      build(identity: "ordinary:#{game.id}:#{identity}", game: game.id,
        finished_at: terminal['created_at'], sides: sides, winner: outcome.fetch(:winner))
    end

    def from_tournament(game:, candidate:, match:, receipt:, players:, finished_at:)
      return unless game.respond_to?(:sports_ranking_result)
      summary = receipt.fetch('summary')
      return if summary['draw'] || summary['resolution'] == 'all_zero' || summary.fetch('winners').size != 1
      units = summary.fetch('participants')
      scores = summary['scores']
      return unless units.size == 2 && scores.is_a?(Hash)
      sides = units.map do |unit|
        people = players.select { |person| (person['team'] || person['account']) == unit }
        {'players'=>people.map { |person| person.fetch('username', person.fetch('account')) }.sort_by(&:downcase),
          'goals'=>scores.fetch(unit)}
      end
      reference = candidate.fetch('publication_ref')
      identity = JSON.generate(['tournament', reference.fetch('author').downcase, reference.fetch('publication_key'),
        candidate.fetch('schedule_id'), match.fetch('match_id'), match.fetch('leg')])
      build(identity: identity, game: game.id, finished_at: finished_at, sides: sides,
        winner: units.index(summary.fetch('winners').first))
    end

    # Calculate each match separately; aggregating raw goal totals first would
    # give long score targets disproportionate influence on the goal component.
    def points(won:, scored:, conceded:)
      total = scored + conceded
      winning_goals = won ? scored : conceded
      ((won ? 10.0 : -10.0) + (total.zero? ? 0.0 : 5.0 * (scored - conceded) / total)) * winning_goals / 100.0
    end

    def day(epoch)
      GameRoomStatistics::Periods.today(clock: -> { Time.at(epoch) }).strftime('%Y%m%d').to_i
    end
  end
end
