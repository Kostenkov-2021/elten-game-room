# Optional audit provenance, deliberately separate from portable game tests.
module HistoricalQuizEvidence
  REQUIRED_FILES = %w[
    quiz-factual-audit-220/ENGLISH_FINAL_DECISIONS.json
    quiz-factual-audit-220/POLISH_FINAL_DECISIONS_MERGED.json
    quiz-factual-audit-220/WITCHER_FINAL_DECISIONS.json
    quiz-recovery-audit-after-221/ALL_RECHECK_DECISIONS.json
  ].freeze

  def self.root
    configured = ENV['GAME_ROOM_QUIZ_AUDIT_ROOT'].to_s
    configured.empty? ? File.expand_path('../../../diagnostics', __dir__) : File.expand_path(configured)
  end

  def self.path(relative)
    File.join(root, relative)
  end

  def self.require_files!
    missing = REQUIRED_FILES.reject { |relative| File.file?(path(relative)) }
    return if missing.empty?

    abort "Historical quiz evidence is unavailable. Set GAME_ROOM_QUIZ_AUDIT_ROOT to the directory containing the original audit folders. Missing:\n#{missing.join("\n")}"
  end
end
