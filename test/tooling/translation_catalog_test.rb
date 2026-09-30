require "tmpdir"
require "gettext/mo"

catalog_path = File.expand_path("../../tools/support/translation_catalog.rb", __dir__)
raise "Missing standard gettext catalog layer" unless File.file?(catalog_path)
require catalog_path

class TranslationCatalogTest
  Catalog = GameRoomTranslationCatalog
  HEADER = "Project-Id-Version: test\nLanguage: pl\nContent-Type: text/plain; charset=UTF-8\nPlural-Forms: nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<12 || n%100>14) ? 1 : 2);\nX-Custom: retained\n"
  @tests = []

  def self.test(name, &block)
    @tests << [name, block]
  end

  def self.run
    @tests.each do |name, block|
      new.instance_exec(&block)
      puts "PASS #{name}"
    end
    puts "All #{@tests.length} translation catalog tests passed"
  end

  def assert(value, message)
    raise message unless value
  end

  def equal(expected, actual, message)
    assert(expected == actual, "#{message}: expected #{expected.inspect}, got #{actual.inspect}")
  end

  def rejects(pattern = nil, &block)
    begin
      block.call
    rescue Catalog::Error => error
      assert(pattern.nil? || error.message.match?(pattern), "Unexpected error: #{error.message}")
      return error
    end
    raise "Invalid catalog was accepted"
  end

  def fixture_mo(path, entries)
    mo = GetText::MO.new
    mo.update({ "" => HEADER }.merge(entries))
    mo.save_to_file(path)
  end

  test "complete MO seed survives a deterministic standard PO round trip" do
    source = File.expand_path("../../locale/PL.mo", __dir__)
    original = GetText::MO.open(source).transform_keys { |key| key.dup.force_encoding("UTF-8") }
      .transform_values { |value| value.dup.force_encoding("UTF-8") }
    singular = "%{count} question"
    plural = singular + "\0%{count} questions"
    if original.key?(singular) && original.key?(plural)
      equal(original[singular], original[plural].split("\0").first, "Seed duplicate conflicts")
      original.delete(singular)
    end
    po = Catalog.from_mo(source)
    assert(po.instance_of?(GetText::PO), "Catalog is not a standard gettext PO")
    equal(original, Catalog.message_map(po), "MO seed was lost")
    Dir.mktmpdir("catalog") do |dir|
      path = File.join(dir, "PL.po")
      Catalog.write_po(po, path)
      first = File.binread(path)
      restored = Catalog.read_po(path)
      equal(original, Catalog.message_map(restored), "PO round trip lost legacy entries")
      Catalog.write_po(restored, path)
      equal(first, File.binread(path), "PO serialization is not deterministic")
      compiled = File.join(dir, "PL.mo")
      Catalog.compile_file(path, compiled)
      result = GetText::MO.open(compiled).transform_values { |value| value.dup.force_encoding("UTF-8") }
      equal(original, result, "Compiled MO lost canonical legacy translations")
    end
  end
  test "failed PO replacement leaves the original authoritative file and no temporary files" do
    Dir.mktmpdir("catalog") do |dir|
      path = File.join(dir, "PL.po")
      po = GetText::PO.new
      po[""] = HEADER
      po["Keep"] = "Zachowaj"
      Catalog.write_po(po, path)
      original = File.binread(path)
      po["Keep"].msgstr = "Nowe tłumaczenie"
      rename = File.method(:rename)
      failure = nil
      begin
        File.define_singleton_method(:rename) do |source, target|
          raise IOError, "injected PO commit failure" if target == path
          rename.call(source, target)
        end
        begin
          Catalog.write_po(po, path)
        rescue IOError => error
          failure = error
        end
      ensure
        File.define_singleton_method(:rename, rename)
      end
      equal(original, File.binread(path), "Failed PO commit destroyed the authoritative translation")
      assert(failure && failure.message == "injected PO commit failure", "PO writes did not use an atomic replacement")
      equal(["PL.po"], Dir.children(dir), "Failed PO commit left a temporary file")
      equal(po, Catalog.write_po(po, path), "Atomic write changed the write_po return value")
      equal("Nowe tłumaczenie", Catalog.read_po(path)["Keep"].msgstr, "PO could not be replaced after a failed commit")
      equal(["PL.po"], Dir.children(dir), "Successful PO commit left a temporary file")
    end
  end
  test "duplicate PO identities are rejected rather than overwritten" do
    Dir.mktmpdir("catalog") do |dir|
      path = File.join(dir, "PL.po")
      ["msgid \"x\"\nmsgstr \"a\"\n\nmsgid \"x\"\nmsgstr \"b\"\n",
       "msgid \"x\"\nmsgstr \"a\"\n\nmsgid \"x\"\nmsgid_plural \"xs\"\nmsgstr[0] \"a\"\nmsgstr[1] \"b\"\n"].each do |text|
        File.binwrite(path, text)
        rejects(/duplicate/i) { Catalog.read_po(path) }
      end
      mo = File.join(dir, "conflict.mo")
      fixture_mo(mo, { "x" => "conflict", "x\0xs" => "a\0b\0c" })
      rejects(/duplicate/i) { Catalog.from_mo(mo) }
    end
  end
  test "plural parsing preserves empty variants and literal backslashes" do
    Dir.mktmpdir("catalog") do |dir|
      path = File.join(dir, "PL.po")
      mo = File.join(dir, "seed.mo")
      entries = { "disk\004Path \\name\n%{count} file\0Path \\name\n%{count} files" => "\0Ścieżka \\name\n%{count} pliki\0" }
      fixture_mo(mo, entries)
      po = Catalog.from_mo(mo)
      Catalog.write_po(po, path)
      equal(Catalog.message_map(po), Catalog.message_map(Catalog.read_po(path)), "Plural content was silently changed")
    end
  end
  test "malformed text, invalid UTF-8 and invalid plural indices fail closed" do
    Dir.mktmpdir("catalog") do |dir|
      path = File.join(dir, "PL.po")
      invalid = ["msgid \"x\"\n", "junk\nmsgid \"x\"\nmsgstr \"y\"\n", "msgid \"x\"\nmsgstr \"y\" junk\n",
        "msgid \"x\"\nmsgstr \"\xFF\"\n".b,
        "msgid \"x\"\nmsgid_plural \"xs\"\nmsgstr[1] \"a\"\n",
        "msgid \"x\"\nmsgid_plural \"xs\"\nmsgstr[0] \"a\"\nmsgstr[2] \"c\"\n",
        "msgid \"x\"\nmsgid_plural \"xs\"\nmsgstr[0] \"a\"\nmsgstr[0] \"b\"\n"]
      invalid.each do |text|
        File.binwrite(path, text)
        rejects { Catalog.read_po(path) }
      end
    end
  end
  test "compilation uses only PO, omits fuzzy and obsolete entries, and check is read-only" do
    Dir.mktmpdir("catalog") do |dir|
      input = File.join(dir, "PL.po")
      output = File.join(dir, "PL.mo")
      fixture_mo(output, { "old" => "stale translation", "Keep" => "Zachowaj" })
      po = Catalog.from_mo(output)
      Catalog.write_po(po, input)
      File.binwrite(input, File.binread(input).sub("msgid \"old\"\nmsgstr \"stale translation\"", "msgid \"old\"\nmsgstr \"\"") + <<~PO)

        # Translator note
        #. Extracted explanation
        #: game.rb:8
        #, fuzzy, ruby-format
        #| msgid "Earlier"
        msgid "Tentative"
        msgstr "Niepewne"

        #~ msgid "Removed"
        #~ msgstr "Usunięte"
      PO
      before = File.binread(input)
      rejects(/stale/i) { Catalog.compile_file(input, output, check: true) }
      Catalog.compile_file(input, output)
      compiled = GetText::MO.open(output)
      equal({ "" => HEADER, "Keep" => "Zachowaj" }, compiled, "Compilation revived stale, fuzzy, obsolete, or blank entries")
      current = File.binread(output)
      timestamp = Time.at(1_000_000_000)
      File.utime(timestamp, timestamp, input)
      File.utime(timestamp, timestamp, output)
      Catalog.compile_file(input, output, check: true)
      Catalog.compile_file(input, output)
      equal(timestamp, File.mtime(input), "Compile/check modified the PO timestamp")
      equal(timestamp, File.mtime(output), "Idempotent compile/check rewrote the MO")
      equal(before, File.binread(input), "Compile/check modified the PO")
      equal(current, File.binread(output), "MO compilation is nondeterministic")
      restored = Catalog.read_po(input)
      equal("Niepewne", Catalog.message_map(restored, include_fuzzy: true)["Tentative"], "Fuzzy translation was lost")
      Catalog.write_po(restored, input)
      rewritten = File.read(input, encoding: "UTF-8")
      ["Translator note", "Extracted explanation", "game.rb:8", "fuzzy", 'msgid "Earlier"', '#~ msgid "Removed"'].each do |text|
        assert(rewritten.include?(text), "PO update lost #{text}")
      end
      File.binwrite(output, "corrupted")
      rejects(/stale/i) { Catalog.compile_file(input, output, check: true) }
      equal("corrupted", File.binread(output), "Check repaired the MO")
      File.delete(output)
      rejects(/stale/i) { Catalog.compile_file(input, output, check: true) }
      assert(!File.exist?(output), "Check created a missing MO")
    end
  end
  test "obsolete blocks survive updates before, between and after active entries" do
    Dir.mktmpdir("catalog") do |dir|
      input = File.join(dir, "PL.po")
      output = File.join(dir, "PL.mo")
      header = GetText::PO.new
      header[""] = HEADER
      blocks = [
        "#~ # Historical translator note\n#~ msgid \"Historical\"\n#~ msgstr \"Dawne\"\n",
        "#~ msgctxt \"archive\"\n#~ msgid \"Old file\"\n#~ msgid_plural \"Old files\"\n#~ msgstr[0] \"Stary plik\"\n#~ msgstr[1] \"Stare pliki\"\n#~ msgstr[2] \"Starych plików\"\n",
        "#~ msgid \"Removed\"\n#~ msgstr \"\"\n#~ \"Usunięte\"\n"
      ]
      [0, 1].each do |position|
        parts = [header.to_s, "# Active translator note\nmsgid \"Keep\"\nmsgstr \"Zachowaj\"\n", blocks[1],
          "msgid \"Other\"\nmsgstr \"Inne\"\n", blocks[2]]
        parts.insert(position, blocks[0])
        File.binwrite(input, parts.join("\n"))
        po = Catalog.read_po(input)
        Catalog.add_messages(po, [{ msgid: "Keep", references: ["new.rb:2"] }])
        Catalog.write_po(po, input)
        rewritten = File.read(input, encoding: "UTF-8")
        blocks.each { |block| assert(rewritten.include?(block), "PO update lost obsolete block: #{block.inspect}") }
        equal("Active translator note", po["Keep"].translator_comment, "Active comment was lost")
        Catalog.write_po(Catalog.read_po(input), input)
        equal(rewritten, File.read(input, encoding: "UTF-8"), "Obsolete blocks were duplicated or changed on another update")
        Catalog.compile_file(input, output)
        equal({ "" => HEADER, "Keep" => "Zachowaj", "Other" => "Inne" }, GetText::MO.open(output), "Obsolete history leaked into MO")
      end
    end
  end
  test "compilation validates placeholders for each nonempty plural variant before replacing output" do
    Dir.mktmpdir("catalog") do |dir|
      input = File.join(dir, "PL.po")
      output = File.join(dir, "PL.mo")
      fixture_mo(output, { "Hello %{name}" => "Witaj %{other}" })
      po = Catalog.from_mo(output)
      Catalog.write_po(po, input)
      before = File.binread(output)
      rejects(/placeholder/i) { Catalog.compile_file(input, output) }
      equal(before, File.binread(output), "Invalid compilation replaced the last good MO")
      po["Hello %{name}"].msgstr = ""
      plural = GetText::POEntry.new(:plural)
      plural.msgid = "%{one} file"
      plural.msgid_plural = "%{many} files"
      plural.msgstr = "%{one} plik\0%{many} pliki\0%{wrong} plików"
      po[plural.msgid] = plural
      Catalog.write_po(po, input)
      rejects(/placeholder/i) { Catalog.compile_file(input, output) }
      plural.msgstr = "%{one} plik\0%{many} pliki\0"
      Catalog.write_po(po, input)
      Catalog.compile_file(input, output)
      equal(plural.msgstr, GetText::MO.open(output)["%{one} file\0%{many} files"], "Blank plural fallback or varying source placeholders were rejected")
    end
  end
  test "interpolated translations reject every unsupported percent token before MO replacement" do
    Dir.mktmpdir("catalog") do |dir|
      input = File.join(dir, "PL.po")
      output = File.join(dir, "PL.mo")
      po = GetText::PO.new
      po[""] = HEADER
      po["Hello %{name}"] = "Witaj %{name}"
      Catalog.write_po(po, input)
      Catalog.compile_file(input, output)
      before = File.binread(output)
      invalid = ["Witaj %{name}: %s", "%1$s: Witaj %{name}", "%{name} %d %d", "%{name} %q %q",
        "%{name} %", "%{name} %\n", "%{name} %{", "%{name} %{}", "%{name} %<name>s",
        "%{name} %999999999999999999999999s", "%{name} %*.*f"]
      invalid.each do |translation|
        po["Hello %{name}"].msgstr = translation
        Catalog.write_po(po, input)
        rejects(/placeholder|format/i) { Catalog.compile_file(input, output) }
        equal(before, File.binread(output), "Invalid Ruby format replaced the last good MO: #{translation.inspect}")
      end
    end
  end
  test "literal percentages and escaped percents preserve named reordering and repetition" do
    Dir.mktmpdir("catalog") do |dir|
      input = File.join(dir, "PL.po")
      output = File.join(dir, "PL.mo")
      entries = {
        "100%" => "Pełne 100%",
        "Keep 10% of the amount." => "Zachowaj 10% kwoty.",
        "%{name}%%" => "%{name}%%",
        "%{first} %{last}" => "%{last}, %{first}, %{first}: %%{literal}",
        "%%{literal}" => "%%{dosłownie}"
      }
      po = GetText::PO.new
      po[""] = HEADER
      entries.each { |source, translation| po[source] = translation }
      Catalog.write_po(po, input)
      Catalog.compile_file(input, output)
      compiled = GetText::MO.open(output).transform_values { |value| value.dup.force_encoding("UTF-8") }
      equal({ "" => HEADER }.merge(entries), compiled, "Valid percent syntax was rejected or changed")
      equal("Ala%", format(compiled["%{name}%%"], name: "Ala"), "Escaped percent does not format")
      equal("Kot, Ala, Ala: %{literal}", format(compiled["%{first} %{last}"], first: "Ala", last: "Kot"), "Reordered/repeated names do not format")
    end
  end
  test "every nonempty plural form rejects introduced printf syntax" do
    Dir.mktmpdir("catalog") do |dir|
      input = File.join(dir, "PL.po")
      output = File.join(dir, "PL.mo")
      po = GetText::PO.new
      po[""] = HEADER
      Catalog.add_messages(po, [{ msgid: "%{count} file", msgid_plural: "%{count} files" }])
      entry = po["%{count} file"]
      forms = ["%{count} plik", "%{count} pliki", "%{count} plików"]
      entry.msgstr = forms.join("\0")
      Catalog.write_po(po, input)
      Catalog.compile_file(input, output)
      before = File.binread(output)
      forms.each_index do |index|
        [" %s", " %", " %q %q"].each do |suffix|
          invalid = forms.dup
          invalid[index] += suffix
          entry.msgstr = invalid.join("\0")
          Catalog.write_po(po, input)
          rejects(/placeholder|format/i) { Catalog.compile_file(input, output) }
          equal(before, File.binread(output), "Invalid plural format replaced the MO")
        end
      end
    end
  end
  test "plural metadata and translated form counts are validated without evaluation" do
    Dir.mktmpdir("catalog") do |dir|
      input = File.join(dir, "PL.po")
      output = File.join(dir, "PL.mo")
      fixture_mo(output, { "file\0files" => "plik\0pliki\0plików" })
      po = Catalog.from_mo(output)
      original = po[""].msgstr
      invalid_rules = ["nplurals=0; plural=0;", "nplurals=17; plural=0;", "nplurals=3; plural=99;",
        "nplurals=3; plural=(1 / 0);", "nplurals=3; plural=-1;", "nplurals=3; plural=n;",
        "nplurals=3; plural=Kernel.exit;", "nplurals=3; plural=0; system('bad');", "nplurals=; plural=;"]
      before = File.binread(output)
      invalid_rules.each do |rule|
        po[""].msgstr = original.sub(/^Plural-Forms:.*$/, "Plural-Forms: #{rule}")
        Catalog.write_po(po, input)
        rejects(/plural/i) { Catalog.compile_file(input, output) }
        equal(before, File.binread(output), "Bad plural metadata replaced the MO")
      end
      po[""].msgstr = original
      ["plik\0pliki", "plik\0pliki\0plików\0extra"].each do |forms|
        po["file"].msgstr = forms
        Catalog.write_po(po, input)
        rejects(/plural|msgstr/i) { Catalog.compile_file(input, output) }
      end
    end
  end
  test "catalog headers and UTF-8 message identities fail closed" do
    Dir.mktmpdir("catalog") do |dir|
      input = File.join(dir, "PL.po")
      output = File.join(dir, "PL.mo")
      fixture_mo(output, { "Keep" => "Zachowaj" })
      po = Catalog.from_mo(output)
      invalid_headers = [HEADER.sub("UTF-8", "ISO-8859-2"), HEADER + "Plural-Forms: nplurals=1; plural=0;\n",
        HEADER.sub("Language: pl", "Language: en"), HEADER.sub("Language: pl", "Language: pl_PL"), ""]
      invalid_headers.each do |header|
        po[""].msgstr = header
        Catalog.write_po(po, input)
        rejects { Catalog.compile_file(input, output) }
      end
      File.binwrite(input, "msgid \"x\"\nmsgstr \"y\"\n")
      rejects(/header/i) { Catalog.compile_file(input, output) }
      po[""].msgstr = HEADER
      po["Keep"].msgid = "bad\0identity"
      Catalog.write_po(po, input)
      rejects { Catalog.compile_file(input, output) }
      fixture_mo(output, { "bad" => "\xFF".b })
      rejects(/UTF-8/i) { Catalog.from_mo(output) }
    end
  end
  test "source updates refresh references without losing translations or unknown legacy entries" do
    Dir.mktmpdir("catalog") do |dir|
      seed = File.join(dir, "seed.mo")
      fixture_mo(seed, { "Legacy" => "Dawny", "Keep" => "Zachowaj", "menu\004Open" => "Otwórz" })
      po = Catalog.from_mo(seed)
      po["Keep"].references = ["old.rb:99"]
      po["Keep"].translator_comment = "Keep the author's note"
      po["Keep"].flags = ["fuzzy"]
      po["Keep"].extracted_comment = "Prior context"
      messages = [{ msgid: "Keep", references: ["new.rb:2"], comments: ["New context"] },
        { msgid: "Keep", references: ["another.rb:5"], comments: ["New context"] },
        { msgid: "Open", msgctxt: "menu", references: ["menu.rb:1"] },
        { msgid: "New %{count} file", msgid_plural: "New %{count} files", references: ["new.rb:1"] }]
      Catalog.add_messages(po, messages)
      equal("Dawny", po["Legacy"].msgstr, "Unknown legacy entry was obsoleted")
      equal("Zachowaj", po["Keep"].msgstr, "Source update overwrote a translation")
      equal(["another.rb:5", "new.rb:2"], po["Keep"].references, "References were stale or lost")
      equal("Otwórz", po["menu", "Open"].msgstr, "Context translation disappeared")
      equal("\0\0", po["New %{count} file"].msgstr, "New Polish plural did not have three empty forms")
      equal("Keep the author's note", po["Keep"].translator_comment, "Translator comment disappeared")
      assert(po["Keep"].fuzzy?, "Fuzzy flag disappeared")
      assert(po["Keep"].extracted_comment.include?("Prior context") && po["Keep"].extracted_comment.include?("New context"), "Extracted comments disappeared")
      first = po.to_s
      Catalog.add_messages(po, messages.reverse)
      equal(first, po.to_s, "Source updates were not idempotent")
    end
  end
  test "adding plural source usage promotes a singular safely and rejects conflicting identities" do
    po = GetText::PO.new
    po[""] = HEADER
    po["%{count} file"] = "%{count} plik"
    Catalog.add_messages(po, [{ msgid: "%{count} file", msgid_plural: "%{count} files" }])
    assert(po["%{count} file"].plural?, "Plural source use was silently discarded")
    equal("%{count} plik\0\0", po["%{count} file"].msgstr, "Singular translation was lost on promotion")
    Catalog.add_messages(po, [{ msgid: "%{count} file" }])
    assert(po["%{count} file"].plural?, "Singular usage downgraded a plural")
    rejects(/conflict/i) { Catalog.add_messages(po, [{ msgid: "%{count} file", msgid_plural: "different files" }]) }
    rejects(/conflict/i) { Catalog.add_messages(po, [{ msgid: "x", msgid_plural: "xs" }, { msgid: "x", msgid_plural: "other" }]) }
  end
  test "POT templates contain no translations or target-language metadata and do not mutate the catalog" do
    po = GetText::PO.new
    po[""] = HEADER + "X-Language-Name: Polski\nLast-Translator: Someone\nPO-Revision-Date: 2020-01-01\n"
    po["Keep"] = "Zachowaj"
    po["Keep"].translator_comment = "Polish translator note"
    po["Keep"].extracted_comment = "Source explanation"
    po["Keep"].flags = ["fuzzy", "ruby-format"]
    Catalog.add_messages(po, [{ msgid: "%{count} file", msgid_plural: "%{count} files" }])
    original = po.to_s
    pot = Catalog.template(po)
    equal(original, po.to_s, "Template generation mutated the translation catalog")
    equal("", pot["Keep"].msgstr, "POT contains a translation")
    equal("\0", pot["%{count} file"].msgstr, "POT did not contain two empty source forms")
    headers = Catalog.metadata(pot)
    %w[Language X-Language-Name Plural-Forms Last-Translator PO-Revision-Date].each do |name|
      assert(!headers.key?(name), "POT retained #{name}")
    end
    equal("retained", headers["X-Custom"], "POT lost custom metadata")
    equal("Source explanation", pot["Keep"].extracted_comment, "POT lost source comments")
    equal(["ruby-format"], pot["Keep"].flags, "POT retained fuzzy or lost source format flags")
    pot["Keep"].references << "other.rb:1"
    assert(po["Keep"].references.empty?, "POT references alias the original catalog")
  end
  test "new Czech catalogs are blank, carry native metadata, and require verified plural data" do
    po = GetText::PO.new
    po[""] = HEADER
    po["Keep"] = "Zachowaj"
    Catalog.add_messages(po, [{ msgid: "%{count} file", msgid_plural: "%{count} files" }])
    pot = Catalog.template(po)
    before = pot.to_s
    rule = "nplurals=3; plural=(n == 1) ? 0 : (n >= 2 && n <= 4) ? 1 : 2;"
    cs = Catalog.new_catalog(pot, language: "cs", native_name: "Čeština", plural_forms: rule)
    headers = Catalog.metadata(cs)
    equal("cs", headers["Language"], "Czech language header is wrong")
    equal("Čeština", headers["X-Language-Name"], "Native language header is wrong")
    equal(rule, headers["Plural-Forms"], "Explicit validated plural metadata was replaced")
    equal("", cs["Keep"].msgstr, "New Czech catalog inherited Polish text")
    equal("\0\0", cs["%{count} file"].msgstr, "New Czech plural was not blank")
    equal(before, pot.to_s, "New catalog initialization mutated the POT")
    rejects(/plural/i) { Catalog.new_catalog(pot, language: "zz", native_name: "Unknown") }
    rejects(/English/i) { Catalog.new_catalog(pot, language: "en", native_name: "English", plural_forms: rule) }
    rejects(/two-letter/i) { Catalog.new_catalog(pot, language: "cs_CZ", native_name: "Čeština", plural_forms: rule) }
    rejects { Catalog.new_catalog(pot, language: "cs", native_name: "Čeština\nInjected: value", plural_forms: rule) }
    Dir.mktmpdir("catalog") do |dir|
      path = File.join(dir, "CS.po")
      output = File.join(dir, "CS.mo")
      Catalog.write_po(cs, path)
      Catalog.compile_file(path, output)
      equal([""], GetText::MO.open(output).keys, "Blank catalog emitted translated messages")
    end
  end
  test "compile never overwrites its PO input or creates an ignored English target" do
    Dir.mktmpdir("catalog") do |dir|
      input = File.join(dir, "PL.po")
      po = GetText::PO.new
      po[""] = HEADER
      po["Keep"] = "Zachowaj"
      Catalog.write_po(po, input)
      before = File.binread(input)
      rejects(/same|input/i) { Catalog.compile_file(input, input) }
      equal(before, File.binread(input), "Compile overwrote its input")
      rejects(/English/i) { Catalog.write_po(po, File.join(dir, "EN.po")) }
      rejects(/English/i) { Catalog.compile_file(input, File.join(dir, "EN.mo")) }
      equal(["PL.po"], Dir.children(dir), "Rejected writes left partial files")
    end
  end
  test "fuzzy headers still carry metadata while fuzzy messages stay excluded" do
    po = GetText::PO.new
    po[""] = HEADER
    po[""].flags = ["fuzzy"]
    po["Uncertain"] = "Niepewne"
    po["Uncertain"].flags = ["fuzzy"]
    equal({ "" => HEADER }, Catalog.message_map(po), "Fuzzy flag removed the MO metadata header")
  end
  test "MO imports reject duplicate raw records before the gettext hash can hide them" do
    Dir.mktmpdir("catalog") do |dir|
      path = File.join(dir, "duplicate.mo")
      fixture_mo(path, { "a" => "first", "b" => "conflicting" })
      bytes = File.binread(path)
      table = bytes.byteslice(12, 4).unpack1("V")
      bytes[table + 16, 8] = bytes.byteslice(table + 8, 8)
      File.binwrite(path, bytes)
      rejects(/duplicate/i) { Catalog.from_mo(path) }
    end
  end
  test "singular promotion uses the target language's singular index" do
    po = GetText::PO.new
    po[""] = "Language: xx\nContent-Type: text/plain; charset=UTF-8\nPlural-Forms: nplurals=2; plural=(n == 1);\n"
    po["file"] = "singular translation"
    Catalog.add_messages(po, [{ msgid: "file", msgid_plural: "files" }])
    equal("\0singular translation", po["file"].msgstr, "Singular promotion assumed index zero")
  end
end

TranslationCatalogTest.run
