# encoding: UTF-8
require "cgi"

module QuizInput
  module_function

  # Preserve visible labels; links remain in the provenance rather than speech.
  def text(value)
    CGI.unescapeHTML(value.to_s)
      .gsub(/\[\[(?:[^\]|]+\|)?([^\]]+)\]\]/, '\\1')
      .gsub(/\[https?:\/\/[^\s\]]+\s+([^\]]+)\]/, '\\1')
      .gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
  end

  def problem(question)
    prompt = question.fetch("prompt", "")
    return "missing actor/context" if prompt.match?(/\A\(?serial[, )].*—.*ta osoba/i)
    return "depends on another question" if prompt.match?(/\b(?:previous|preceding|last|next|earlier|above|following) (?:question|answer)\b|\b(?:question|answer) (?:number |no\. ?|#)\d/i)
    values = [prompt, question["correct"], *question["wrong"]].map(&:to_s)
    return "unresolved import markup" if values.any? { |v| v.match?(/\[https?:\/\/|\[\[|\]\]|[|]|\{\{|\}\}|\[[^\]]*\z/) }
    return "empty question/answer" if values.any?(&:empty?)
    return "duplicate choices after cleanup" if values.drop(1).map(&:downcase).uniq.length != 4
    nil
  end

end
