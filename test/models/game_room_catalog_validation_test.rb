require_relative "../../lib/game_room_localization"

def assert(condition, message)
  raise message unless condition
end

def catalog_bytes(entries, rule: "nplurals=2; plural=(n != 1);", order: "V")
  entries = { "" => "Content-Type: text/plain; charset=UTF-8\nPlural-Forms: #{rule}\n" }.merge(entries).sort
  offset = 28 + entries.length * 16
  blob = "".b
  tables = [entries.map(&:first), entries.map(&:last)].map do |strings|
    strings.map do |value|
      entry = [value.bytesize, offset + blob.bytesize].pack("#{order}2")
      blob << value.b << "\0"
      entry
    end.join
  end
  [0x950412de, 0, entries.length, 28, 28 + entries.length * 8, 0, 0].pack("#{order}7") + tables.join + blob
end

["V", "N"].each do |order|
  data = catalog_bytes({ "Name" => "Jméno", "coin\0coins" => "mince\0mincí" }, order: order)
  catalog = GameRoomLocalization::Catalog.new(data)
  assert(catalog.translate("Name".b) == "Jméno", "MO endianness or UTF-8 decoding is incorrect")
  assert(catalog.translate("coin", count: 2) == "mincí", "MO plural variants were not preserved")
  ["", data.byteslice(0, 12), data.byteslice(0, 40), data.dup.tap { |bytes| bytes[12, 4] = [0xffffffff].pack(order) }].each do |broken|
    rejected = false
    begin
      GameRoomLocalization::Catalog.new(broken)
    rescue ArgumentError
      rejected = true
    end
    assert(rejected, "a truncated or out-of-bounds MO catalog was accepted")
  end
end

["Kernel.system(1)", "n;exit", "n**1000", "n?1", "(" * 300 + "n" + ")" * 300, "n" * 300].each do |expression|
  rejected = false
  begin
    GameRoomLocalization::PluralRule.new(expression)
  rescue ArgumentError
    rejected = true
  end
  assert(rejected, "unsafe or malformed plural expression was accepted: #{expression[0, 30]}")
end
[0, 1, 2, 4, 5, 11, 12, 14, 21, 22, 24, 25, 101, 112].each do |count|
  expected = count == 1 ? 0 : (count % 10 >= 2 && count % 10 <= 4 && !(12..14).include?(count % 100) ? 1 : 2)
  rule = GameRoomLocalization::PluralRule.new("n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<12 || n%100>14) ? 1 : 2")
  assert(rule.index(count) == expected, "Polish plural boundaries failed for #{count}")
end
assert(GameRoomLocalization::PluralRule.new("n==1 || 1/0").index(1) == 1, "plural OR did not short-circuit")
assert(GameRoomLocalization::PluralRule.new("n!=1 && 1/0").index(1) == 0, "plural AND did not short-circuit")
assert(GameRoomLocalization::PluralRule.new("n==1 ? 0 : 1/0").index(1) == 0, "plural ternary evaluated the unused branch")
assert(GameRoomLocalization::PluralRule.new("1/0").index(2).nil?, "invalid arithmetic escaped plural fallback")

empty = GameRoomLocalization::Catalog.new(catalog_bytes({ "Name" => "" }))
known = GameRoomLocalization::Catalog.new(catalog_bytes({ "Name" => "Jméno" }))
translator = GameRoomLocalization::Translator.new(catalogs: { "pl" => empty, "cs" => known }, primary: "pl", known: ["cs"])
assert(translator.translate("Name") == "Jméno", "an empty msgstr blocked a known-language fallback")
puts "MO byte order/bounds/UTF-8, bounded safe plurals and empty-entry fallback passed"
