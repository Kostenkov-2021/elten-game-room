require "json"

module GameRoomTranslationDocuments
  class StaleFiles < StandardError; end

  module_function

  def sync(root, messages, check: false)
    root = File.expand_path(root)
    outputs = {}
    Dir.glob('*.json', base: File.join(root, 'tools/data/rulebooks')).sort.each do |name|
      path = safe_path(root, "tools/data/rulebooks/#{name}")
      book = JSON.parse(File.read(path, encoding: "UTF-8"))
      book.fetch("sections").each do |section|
        ([section.fetch("title")] + section.fetch("paragraphs")).each do |pair|
          pair["pl"] = translation(messages, pair.fetch("en"))
        end
      end
      outputs[path] = json_output(path, book)
    end
    changed = outputs.reject { |path, content| File.file?(path) && File.binread(path) == content.b }
    raise StaleFiles, "Translated documents are stale: #{changed.keys.join(', ')}" if check && !changed.empty?
    changed.each { |path, content| atomic_write(path, content) } unless check
    changed.keys
  end

  def translation(messages, key)
    return messages.fetch(key).to_s if messages.key?(key)
    unless key.include?("\0")
      plural = messages.keys.find { |candidate| candidate.start_with?(key + "\0") }
      return messages.fetch(plural).to_s.split("\0", -1).first if plural
    end
    ""
  end

  def json_output(path, values)
    if File.file?(path)
      previous = File.binread(path).force_encoding('UTF-8')
      unchanged = begin
        JSON.parse(previous) == values
      rescue JSON::ParserError
        false
      end
      return previous if unchanged
    end
    JSON.pretty_generate(values) + "\n"
  end

  def safe_path(root, relative)
    parts = relative.to_s.tr("\\", "/").split("/")
    if parts.empty? || parts.include?("..") || parts.any?(&:empty?) || relative.to_s.include?(":")
      raise ArgumentError, "invalid generated translation path"
    end
    path = File.expand_path(relative, root)
    raise ArgumentError, "generated translation path escapes the project" unless path.start_with?(root + "/")
    parent = File.realpath(File.dirname(path))
    raise ArgumentError, "generated translation path follows an external link" unless parent.start_with?(File.realpath(root) + "/")
    path
  end

  def atomic_write(path, content)
    temporary = "#{path}.tmp-#{Process.pid}"
    File.binwrite(temporary, content.encode("UTF-8"))
    File.rename(temporary, path)
  ensure
    File.delete(temporary) if defined?(temporary) && File.file?(temporary)
  end
end
