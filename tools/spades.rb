require 'optparse'
require_relative 'training/spades_workflow'

module GameRoomSpadesCLI
  module_function

  def run(arguments)
    args = arguments.dup
    command = args.shift
    unless %w[train evaluate].include?(command)
      raise ArgumentError, 'Usage: ruby tools/spades.rb train|evaluate [options]; use COMMAND --help'
    end
    options = {profiles: nil, seed: 300_000, score_limits: [300], output: nil}
    options.merge!(command == 'train' ? {
      profiles: SpadesLearning::ARRANGEMENT_PROFILES.keys, max_series: 6, plateau_limit: 3,
      generations: 3, population: 6, evaluation_seeds: 2, validation_seeds: 2,
      holdout_seeds: 20, mutation_scale: 0.7, training_max_actions: 6_000, validation_max_actions: 6_000
    } : {report: nil, seed: 12_000_000, seeds: 40, max_actions: 6_000, calibration: true})
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: ruby tools/spades.rb #{command} [options]"
      opts.on('--profiles LIST', Array) { |value| options[:profiles] = value }
      opts.on('--seed NUMBER', Integer) { |value| options[:seed] = value }
      opts.on('--score-limits LIST', Array) { |value| options[:score_limits] = value.map { |item| Integer(item, 10) } }
      opts.on('--output NEW_FILE', 'Otherwise write JSON to stdout') { |value| options[:output] = value }
      if command == 'train'
        %i[max_series plateau_limit generations population evaluation_seeds validation_seeds holdout_seeds
          training_max_actions validation_max_actions].each do |key|
          opts.on("--#{key.to_s.tr('_', '-')} N", Integer) { |value| options[key] = value }
        end
        opts.on('--mutation-scale NUMBER', Float) { |value| options[:mutation_scale] = value }
      else
        opts.on('--report FILE', 'Training report containing selected_profiles') { |value| options[:report] = value }
        opts.on('--seeds N', Integer) { |value| options[:seeds] = value }
        opts.on('--max-actions N', Integer) { |value| options[:max_actions] = value }
        opts.on('--skip-calibration') { options[:calibration] = false }
      end
    end
    parser.parse!(args)
    raise ArgumentError, "Unexpected arguments: #{args.join(' ')}" unless args.empty?
    validate!(command, options)
    report = GameRoomSpadesTools.public_send(command, options)
    json = JSON.pretty_generate(report) + "\n"
    options[:output] ? File.write(options[:output], json, mode: 'wx') : puts(json)
    incomplete = report.fetch(:arrangements).any? do |record|
      candidates = command == 'train' ? [record.fetch(:head_to_head)] : [record]
      candidates += [record[:candidate_calibration], record[:baseline_calibration]].compact
      candidates.any? { |evaluation| evaluation.fetch(:incomplete_games).positive? }
    end
    warn 'Evaluation contains incomplete games; inspect the report before using the profiles.' if incomplete
    incomplete ? 2 : 0
  end

  def validate!(command, options)
    GameRoomSpadesTools.validate_profiles!(options[:profiles]) if options[:profiles]
    if options[:score_limits].empty? || options[:score_limits].any? { |value| value <= 0 }
      raise ArgumentError, 'Score limits must be positive'
    end
    options.each do |key, value|
      next unless value.is_a?(Numeric) && key != :seed
      valid = key == :mutation_scale ? value.finite? && value >= 0 : value > 0
      raise ArgumentError, "Invalid --#{key.to_s.tr('_', '-')}" unless valid
    end
    raise ArgumentError, '--report is required for evaluate' if command == 'evaluate' && options[:report].to_s.empty?
    raise ArgumentError, "Output already exists: #{options[:output]}" if options[:output] && File.exist?(options[:output])
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit GameRoomSpadesCLI.run(ARGV)
  rescue ArgumentError, KeyError, JSON::ParserError => error
    warn error.message
    exit 1
  end
end
