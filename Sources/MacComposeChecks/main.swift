import Foundation
import MacComposeCore

nonisolated(unsafe) var failures = 0

func check(_ name: String, _ isOK: Bool) {
    if !isOK {
        failures += 1
        print("FAIL \(name)")
    }
}

// bundledResource
for name in ["Compose", "keysymdef.h", "WinCompose.txt", "Emoji.txt"] {
    let size = bundledResource(name).flatMap { try? Data(contentsOf: $0).count } ?? 0
    check("bundledResource_of\(name)_returnsNonEmptyFile", size > 0)
}

// keysymCharacter
check("keysymCharacter_ofEacute_returnsEAcute", keysymCharacter(named: "eacute") == "é")
check("keysymCharacter_ofUnicodeName_returnsCharacter", keysymCharacter(named: "U2192") == "→")
check("keysymCharacter_ofDeprecatedLatin1Alias_returnsCharacter", keysymCharacter(named: "quoteright") == "'")
check("keysymCharacter_ofParenthesizedUnicodeComment_returnsCharacter", keysymCharacter(named: "leftcaret") == "<")
check("keysymCharacter_ofNonCharacterKeys_returnsNil",
      ["dead_acute", "KP_Space", "Left", "F1", "Multi_key"].allSatisfy { keysymCharacter(named: $0) == nil })

// loadComposeSequences
let fixtureDirectory = FileManager.default.temporaryDirectory.appending(path: "MacComposeChecks-\(UUID())")
try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

func fixture(_ name: String, _ content: String) -> URL {
    let url = fixtureDirectory.appending(path: name)
    try! content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

// Given a file mixing escapes, U names, keysym-only outputs, literal names and lines to ignore
let rules = fixture("rules", #"""
# comment
<Multi_key> <q> <q> : "\"" quotedbl
<Multi_key> <b> <b> : "\\" backslash
<Multi_key> <U2192> <x> : "x→"
<Multi_key> <k> <s> : eacute
<Multi_key> <!> < > : "bang"
<Multi_key> <Multi_key> <e> : "😀"
<dead_acute> <e> : "é"
<Multi_key> <Left> <e> : "nope"
<Multi_key> <k> <k> "no colon"
garbage line
"""#)
// When loading it
let parsed = loadComposeSequences(from: [rules, fixtureDirectory.appending(path: "missing")])
// Then each rule maps as expected, ignored lines are dropped and the missing file is skipped
check("parse_ofQuotedEscape_returnsQuote", parsed[["q", "q"]] == "\"")
check("parse_ofBackslashEscape_returnsBackslash", parsed[["b", "b"]] == "\\")
check("parse_ofUnicodeName_returnsCharacter", parsed[["→", "x"]] == "x→")
check("parse_ofKeysymOutput_returnsKeysymCharacter", parsed[["k", "s"]] == "é")
check("parse_ofLiteralNames_returnsOutput", parsed[["!", " "]] == "bang")
check("parse_ofDoubleMultiKey_usesComposeKeyCharacter", parsed[[composeKeyCharacter, "e"]] == "😀")
check("parse_ofNonMultiKeyAndUnresolvableAndMalformed_ignoresThem", parsed.count == 6)

// Given a later file overriding a rule and conflicting by prefix with two others
let base = fixture("base", """
<Multi_key> <a> <a> : "1"
<Multi_key> <c> <c> <c> : "2"
<Multi_key> <d> : "3"
""")
let overrides = fixture("overrides", """
<Multi_key> <a> <a> : "override"
<Multi_key> <c> <c> : "shorter"
<Multi_key> <d> <d> : "longer"
""")
// When loading both in order
let merged = loadComposeSequences(from: [base, overrides])
// Then the later definitions win and the conflicting earlier ones are removed
check("load_whenRedefined_laterWins", merged[["a", "a"]] == "override")
check("load_whenLaterIsPrefix_removesLonger", merged[["c", "c"]] == "shorter" && merged[["c", "c", "c"]] == nil)
check("load_whenEarlierIsPrefix_removesShorter", merged[["d", "d"]] == "longer" && merged[["d"]] == nil)

// Given a user file including the bundled locale file, then overriding one of its rules
let user = fixture("user", """
include "%L"
include "%S/en_US.UTF-8/Compose"
<Multi_key> <o> <o> : "custom"
""")
// When loading it
let included = loadComposeSequences(from: [user])
// Then the includes are skipped (the bundled files are always loaded first) and the user's rule applies
check("load_ofIncludeL_skipsInclude", included[["'", "e"]] == nil)
check("load_ofIncludeL_keepsUserRule", included[["o", "o"]] == "custom")

// Given the bundled files, When loading them, Then the well-known sequences are present
let start = Date()
let bundled = loadComposeSequences(from: ["Compose", "WinCompose.txt", "Emoji.txt"].compactMap(bundledResource))
print("Loaded \(bundled.count) bundled sequences in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
check("load_ofBundledFiles_returnsMoreThan3000Sequences", bundled.count > 3000)
check("load_ofBundledFiles_composesEAcute", bundled[["'", "e"]] == "é")
check("load_ofBundledFiles_composesArrow", bundled[["-", ">"]] == "→")
check("load_ofBundledFiles_composesDegree", bundled[["o", "o"]] == "°")
check("load_ofBundledFiles_composesEmoji", bundled[[composeKeyCharacter] + Array("winking")] == "😉")

// Given an engine on the bundled sequences
var engine = ComposeEngine(sequences: bundled)
// When feeding a valid prefix, then completing it
let pending = engine.feed("'")
let emitted = engine.feed("e")
// Then it is pending, then emits the character
check("feed_ofPrefix_isPendingThenEmits", pending == .pending && emitted == .emit("é"))
// When feeding an unknown character after a prefix, then a full sequence
_ = engine.feed("'")
let invalid = engine.feed("\u{1}")
let afterInvalid = engine.feed("-") == .pending && engine.feed(">") == .emit("→")
// Then it is invalid, and the buffer was reset
check("feed_ofUnknownCharacter_isInvalidAndResets", invalid == .invalid && afterInvalid)
// When resetting mid-sequence, then typing a full sequence
_ = engine.feed("'")
engine.reset()
// Then the abandoned prefix is forgotten
check("reset_forgetsBuffer_thenEmits", engine.feed("o") == .pending && engine.feed("o") == .emit("°"))
// When feeding the second Compose press (the first one started composing) then the emoji name
var emojiResults = [engine.feed(composeKeyCharacter)]
emojiResults += "winking".map { engine.feed($0) }
// Then everything is pending until the last character emits
check("feed_ofDoubleComposeEmoji_emits", emojiResults.dropLast().allSatisfy { $0 == .pending } && emojiResults.last == .emit("😉"))

if failures > 0 {
    print("\(failures) check(s) failed")
    exit(1)
}
print("All checks passed")
