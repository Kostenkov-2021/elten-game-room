require "gettext/po"
require "gettext/po_parser"
require "gettext/mo"
require "tempfile"
require_relative "../../lib/game_room_plural_rule"

module GameRoomTranslationCatalog
  class Error < StandardError; end

  module EmptyPluralEntry
    def to_s(options = {})
      super + "msgstr[0] \"\"\n"
    end
  end

  class SeedMO < GetText::MO
    def []=(key, value)
      raise Error, "Duplicate raw MO record: #{key.inspect}" if key?(key)
      super
    end
  end

  class ValidatingParser < GetText::POParser
    def on_message(msgid, msgstr)
      if @data.has_key?(@msgctxt, msgid)
        raise Error, "Duplicate PO identity: #{[@msgctxt, msgid].inspect}"
      end
      comments = @comments
      super
      @comments = comments
      @plural_index = 0
    end

    # gettext 3.5.2's plural reductions re-unescape strings and drop leading blank forms.
    def _reduce_9(values, _stack, _result)
      @msgid_plural = values[3]
      on_message(values[1], values[4])
      @fuzzy = false
      ""
    end

    def _reduce_10(values, _stack, _result)
      values.join("\0")
    end

    def _reduce_12(values, stack, result)
      @plural_index ||= 0
      unless values[1] == @plural_index.to_s && @plural_index < 16
        raise Error, "Plural msgstr indices must be consecutive from 0 (got #{values[1]})"
      end
      @plural_index += 1
      super
    end
  end

  module_function

  def read_po(path)
    text = File.binread(path).force_encoding("UTF-8")
    raise Error, "#{path}: invalid UTF-8" unless text.valid_encoding?
    # The upstream lexer silently skips unknown characters; reject them before parsing.
    text.each_line.with_index(1) do |line, number|
      unless line.match?(/\A[ \t]*(?:\#.*|(?:(?:msgctxt|msgid_plural|msgid|msgstr(?:\[\d+\])?)[ \t]+)?"(?:[^"\\\r\n]|\\["\\nrt])*"[ \t]*)?\r?\n?\z/)
        raise Error, "#{path}:#{number}: invalid PO syntax"
      end
    end
    parser = ValidatingParser.new
    parser.ignore_fuzzy = false
    parser.report_warning = false
    parser.parse(text, GetText::PO.new)
  rescue Racc::ParseError => error
    raise Error, "#{path}: #{error.message}"
  end

  def write_po(po, path)
    reject_english_path(path)
    ordered = GetText::PO.new(:insertion)
    po.sort_by { |entry| [entry.obsolete? ? 1 : 0, entry.msgid.to_s, entry.msgctxt.to_s] }.each do |entry|
      if entry.plural? && entry.msgstr.to_s.empty? && !entry.obsolete?
        entry = entry.dup
        entry.msgstr = ""
        entry.extend(EmptyPluralEntry)
      end
      ordered[entry.msgctxt, entry.msgid] = entry
    end
    Tempfile.create([".catalog-", ".po"], File.dirname(File.expand_path(path))) do |file|
      file.binmode
      file.write(ordered.to_s(max_line_width: -1))
      file.flush
      file.fsync
      file.close
      File.rename(file.path, path)
    end
    po
  end

  def from_mo(path)
    po = GetText::PO.new
    SeedMO.open(path).each do |key, value|
      key = key.dup.force_encoding("UTF-8")
      value = value.dup.force_encoding("UTF-8")
      raise Error, "Invalid UTF-8 in MO seed" unless key.valid_encoding? && value.valid_encoding?
      singular, plural = key.split("\0", 2)
      singular ||= ""
      context = nil
      context, singular = singular.split("\004", 2) if singular.include?("\004")
      entry = build_entry(singular, plural, context)
      entry.msgstr = value
      existing = po[context, singular]
      if existing
        single, multiple = [existing, entry].sort_by { |item| item.plural? ? 1 : 0 }
        unless !single.plural? && multiple.plural? && single.msgstr == multiple.msgstr.split("\0", -1).first
          raise Error, "Conflicting duplicate MO identity: #{singular.inspect}"
        end
        entry = multiple
      end
      po[context, singular] = entry
    end
    po
  end

  def message_map(po, include_fuzzy: false)
    po.each_with_object({}) do |entry, messages|
      next if entry.obsolete? || (entry.fuzzy? && !include_fuzzy && !entry.header?)
      key = entry.msgctxt.nil? ? +"" : entry.msgctxt + "\004"
      key << entry.msgid
      key << "\0" << entry.msgid_plural if entry.plural?
      messages[key] = entry.msgstr.to_s
    end
  end

  def add_messages(po, messages)
    forms = metadata(po)["Plural-Forms"]
    count, rule = forms ? plural_rule(forms) : [2, nil]
    messages.group_by { |message| [message[:msgctxt], message.fetch(:msgid)] }.each do |identity, sources|
      context, msgid = identity
      plurals = sources.map { |source| source[:msgid_plural] }.compact
      plurals << po[context, msgid].msgid_plural if po[context, msgid]&.plural?
      raise Error, "Conflicting plural identity: #{identity.inspect}" if plurals.uniq.length > 1
      plural = plurals.first
      entry = po[context, msgid] || build_entry(msgid, plural, context)
      if plural && !entry.plural?
        entry.type = context.nil? ? :plural : :msgctxt_plural
        entry.msgid_plural = plural
        translations = Array.new(count, "")
        translations[rule ? rule.index(1) : 0] = entry.msgstr.to_s
        entry.msgstr = translations.join("\0")
      end
      entry.msgstr = entry.plural? ? Array.new(count, "").join("\0") : "" if entry.msgstr.nil?
      entry.references = sources.flat_map { |source| Array(source[:references]) }.uniq.sort
      comments = entry.extracted_comment.to_s.lines.map(&:chomp)
      comments.concat(sources.flat_map { |source| Array(source[:comments]) })
      entry.extracted_comment = comments.uniq.sort.join("\n")
      po[context, msgid] = entry
    end
    po
  end

  def template(po)
    pot = GetText::PO.new
    po.each do |original|
      next if original.obsolete?
      entry = copy_entry(original)
      entry.flags.delete("fuzzy")
      entry.translator_comment = nil
      if entry.header?
        entry.msgstr = original.msgstr.to_s.lines.reject do |line|
          line.match?(/\A(?:Language|Language-Team|X-Language-Name|Last-Translator|PO-Revision-Date|Plural-Forms):/i)
        end.join
      else
        entry.msgstr = entry.plural? ? "\0" : ""
      end
      pot[entry.msgctxt, entry.msgid] = entry
    end
    pot
  end

  def new_catalog(source, language:, native_name:, plural_forms: nil)
    language = target_language(language)
    unless native_name.is_a?(String) && native_name.dup.force_encoding("UTF-8").valid_encoding? &&
        !native_name.strip.empty? && !native_name.match?(/[\x00-\x1F\x7F]/)
      raise Error, "Native language name must be nonempty UTF-8 without control characters"
    end
    unless plural_forms
      require "gettext/tools/msginit"
      plural_forms = GetText::Tools::MsgInit::CLDRPluralsConverter.new(language).convert
      unless plural_forms.match?(/\Anplurals=\d+;/)
        raise Error, "No gettext plural data for #{language}; supply explicit plural_forms metadata"
      end
    end
    count, = plural_rule(plural_forms)
    po = template(source)
    headers = metadata(po)
    headers["Project-Id-Version"] ||= "ELTEN Game Room"
    headers["MIME-Version"] = "1.0"
    headers["Content-Type"] = "text/plain; charset=UTF-8"
    headers["Content-Transfer-Encoding"] = "8bit"
    headers["Language"] = language
    headers["Plural-Forms"] = plural_forms
    headers["X-Language-Name"] = native_name
    po[""] = headers.map { |key, value| "#{key}: #{value}\n" }.join
    po.each { |entry| entry.msgstr = Array.new(count, "").join("\0") if entry.plural? }
    validate!(po)
  end

  def copy_entry(original)
    entry = original.dup
    %i[msgid msgid_plural msgctxt msgstr separator translator_comment extracted_comment previous comment references flags].each do |field|
      value = original.public_send(field)
      entry.public_send("#{field}=", value.dup) unless value.nil?
    end
    entry
  end
  private_class_method :copy_entry

  def build_entry(msgid, plural = nil, context = nil)
    type = context.nil? ? (plural.nil? ? :normal : :plural) : (plural.nil? ? :msgctxt : :msgctxt_plural)
    entry = GetText::POEntry.new(type)
    entry.msgid = msgid
    entry.msgid_plural = plural
    entry.msgctxt = context
    entry
  end
  private_class_method :build_entry

  def compile_file(input, output, check: false)
    if File.expand_path(input) == File.expand_path(output) || (File.exist?(output) && File.identical?(input, output))
      raise Error, "Compiled output must not be the same file as the PO input"
    end
    reject_english_path(output)
    po = read_po(input)
    validate!(po)
    mo = GetText::MO.new
    message_map(po).each do |key, value|
      mo[key] = value if key.empty? || value.split("\0", -1).any? { |form| !form.empty? }
    end
    buffer = StringIO.new("".b)
    mo.save_to_stream(buffer)
    bytes = buffer.string
    return :unchanged if File.file?(output) && File.binread(output) == bytes
    raise Error, "Stale compiled catalog: #{output}" if check
    Tempfile.create([".catalog-", ".mo"], File.dirname(File.expand_path(output))) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      file.fsync
      file.close
      File.rename(file.path, output)
    end
    :written
  end

  def validate!(po)
    raise Error, "Missing PO header" unless po[""] && !po[""].msgstr.to_s.empty?
    headers = metadata(po)
    unless headers["Content-Type"].to_s.match?(/\Atext\/plain;\s*charset=UTF-8\z/i)
      raise Error, "Content-Type header must declare UTF-8"
    end
    target_language(headers["Language"])
    count, rule = plural_rule(headers["Plural-Forms"])
    identities = {}
    po.each do |entry|
      next if entry.obsolete?
      [entry.msgid, entry.msgctxt, entry.msgid_plural, entry.msgstr].compact.each do |text|
        raise Error, "Invalid UTF-8 in PO message" unless text.is_a?(String) && text.dup.force_encoding("UTF-8").valid_encoding?
      end
      [entry.msgid, entry.msgctxt, entry.msgid_plural].compact.each do |text|
        raise Error, "Reserved NUL/context separator in PO identity" if text.match?(/[\0\004]/)
      end
      identity = [entry.msgctxt, entry.msgid]
      raise Error, "Duplicate PO identity: #{identity.inspect}" if identities[identity]
      identities[identity] = true
      next if entry.header? || entry.fuzzy?
      translations = entry.msgstr.to_s.split("\0", -1)
      translations = [""] if translations.empty?
      if entry.plural? && translations.length != count
        raise Error, "Expected #{count} plural msgstr forms for #{entry.msgid.inspect}, got #{translations.length}"
      end
      raise Error, "NUL in singular msgstr" if !entry.plural? && entry.msgstr.to_s.include?("\0")
      translations.each_with_index do |translation, index|
        next if translation.empty?
        source = entry.plural? && index != rule.index(1) ? entry.msgid_plural : entry.msgid
        expected = placeholders(source)
        unless expected == placeholders(translation, interpolated: !expected.empty?)
          raise Error, "Ruby placeholder mismatch in #{entry.msgid.inspect}, msgstr[#{index}]"
        end
      end
    end
    po
  end

  def plural_rule(forms)
    match = /\Anplurals\s*=\s*(\d+)\s*;\s*plural\s*=\s*([^;\r\n]+);\s*\z/.match(forms.to_s)
    raise Error, "Invalid Plural-Forms metadata" unless match && (1..16).include?(match[1].to_i)
    count = match[1].to_i
    rule = GameRoomLocalization::PluralRule.new(match[2])
    samples = (0..1000).to_a + [10_000, 100_000, 1_000_000, 1_000_000_000]
    match[2].scan(/\d+/).each { |value| samples.concat([value.to_i - 1, value.to_i, value.to_i + 1]) }
    samples.uniq.select { |value| value >= 0 }.each do |value|
      index = rule.index(value)
      unless index.is_a?(Integer) && index >= 0 && index < count
        raise Error, "Plural rule returns #{index.inspect} outside 0...#{count} for n=#{value}"
      end
    end
    [count, rule]
  rescue ArgumentError => error
    raise Error, "Invalid plural expression: #{error.message}"
  end
  private_class_method :plural_rule

  def target_language(language)
    unless language.is_a?(String) && language.match?(/\A[a-zA-Z]{2}\z/)
      raise Error, "Target language must be a two-letter code"
    end
    raise Error, "English is the source language, not a target catalog" if language.downcase == "en"
    language.downcase
  end
  private_class_method :target_language

  def reject_english_path(path)
    if File.basename(path).match?(/\Aen\.(?:po|mo)\z/i)
      raise Error, "English is the source language; EN.po/EN.mo targets are not supported"
    end
  end
  private_class_method :reject_english_path

  def metadata(po)
    po[""]&.msgstr.to_s.each_line.each_with_object({}) do |line, result|
      key, value = line.split(":", 2)
      raise Error, "Malformed catalog header: #{line.inspect}" unless value && key.match?(/\A[A-Za-z][A-Za-z0-9-]*\z/)
      raise Error, "Duplicate catalog header: #{key}" if result.keys.any? { |name| name.casecmp?(key) }
      result[key] = value.to_s.strip
    end
  end

  def placeholders(text, interpolated: false)
    tokens = text.to_s.scan(/%%|%\{[^}]+\}|%/)
    names = tokens.filter_map { |token| token[2...-1] if token.start_with?("%{") }.uniq.sort
    if (interpolated || !names.empty?) && tokens.include?("%")
      raise Error, "Invalid Ruby placeholder format; preserve %{name} tokens and escape literal % as %%: #{text.inspect}"
    end
    names
  end
  private_class_method :placeholders
end
