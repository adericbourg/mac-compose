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
for name in ["Compose", "keysymdef.h", "WinCompose.txt", "Emoji.txt", "gemoji.json"] {
    let size = bundledResource(name).flatMap { try? Data(contentsOf: $0).count } ?? 0
    check("bundledResource_of\(name)_returnsNonEmptyFile", size > 0)
}

// keysymCharacter
check("keysymCharacter_ofEacute_returnsEAcute", keysymCharacter(named: "eacute") == "é")
check("keysymCharacter_ofUnicodeName_returnsCharacter", keysymCharacter(named: "U2192") == "→")
check("keysymCharacter_ofDeprecatedLatin1Alias_returnsCharacter", keysymCharacter(named: "quoteright") == "'")
check("keysymCharacter_ofParenthesizedUnicodeComment_returnsCharacter", keysymCharacter(named: "leftcaret") == "<")
check("keysymCharacter_ofNonCharacterKeys_returnsNil",
      ["dead_iota", "KP_Space", "Left", "F1", "Multi_key"].allSatisfy { keysymCharacter(named: $0) == nil })
check("keysymCharacter_ofDeadKeys_returnsSpacingCharacter",
      keysymCharacter(named: "dead_acute") == "´" && keysymCharacter(named: "dead_circumflex") == "^"
      && keysymCharacter(named: "dead_diaeresis") == "¨" && keysymCharacter(named: "dead_grave") == "`"
      && keysymCharacter(named: "dead_tilde") == "~")
let defaultSequences = loadDefaultComposeSequences()
check("loadDefaultComposeSequences_ofDeadKeyRules_loadsThemWithoutBreakingMainRowOnes",
      defaultSequences[["´", "e"]] == "é" && defaultSequences[["'", "e"]] == "é"
      && defaultSequences[["^", "e"]] == "ê")

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
<Multi_key> <o> <o> : "\101\x42\1013"
<Multi_key> <h> <h> : "\x4a\xe9"
~Ctrl <Multi_key> <m> <m> : "modifier"
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
check("parse_ofOctalAndHexEscapes_returnsCharacters", parsed[["o", "o"]] == "ABA3" && parsed[["h", "h"]] == "Jé")
check("parse_ofUnicodeName_returnsCharacter", parsed[["→", "x"]] == "x→")
check("parse_ofKeysymOutput_returnsKeysymCharacter", parsed[["k", "s"]] == "é")
check("parse_ofLiteralNames_returnsOutput", parsed[["!", " "]] == "bang")
check("parse_ofDoubleMultiKey_usesComposeKeyCharacter", parsed[[composeKeyCharacter, "e"]] == "😀")
check("parse_ofNonMultiKeyAndUnresolvableAndMalformed_ignoresThem", parsed.count == 8)

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
let bundled = loadComposeSequences(from: ["Compose", "WinCompose.txt"].compactMap(bundledResource))
print("Loaded \(bundled.count) bundled sequences in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
check("load_ofBundledFiles_returnsMoreThan2500Sequences", bundled.count > 2500)
check("load_ofBundledFiles_composesEAcute", bundled[["'", "e"]] == "é")
check("load_ofBundledFiles_composesArrow", bundled[["-", ">"]] == "→")
check("load_ofBundledFiles_composesDegree", bundled[["o", "o"]] == "°")
check("load_ofBundledFiles_composesDoubleComposeRule", bundled[[composeKeyCharacter] + Array("bzh")] != nil)
check("loadDefaultComposeSequences_leavesEmojiToFuzzySearch", loadDefaultComposeSequences()[[composeKeyCharacter] + Array("winking")] == nil)

// Given an emoji file with an active and a commented-out line
let emojiFixture = fixture("emoji", """
<Multi_key> <Multi_key> <w> <i> <n> <k> <i> <n> <g> : "😉" U1F609 # winking face
# "#️⃣" U0023 UFE0F U20E3 # keycap: #
not an emoji line
""")
// When loading its names, Then both lines are kept, in order, with their full name
let fixtureNames = loadEmojiNames(from: emojiFixture)
check("loadEmojiNames_ofActiveAndCommentedLines_returnsBoth",
      fixtureNames.map(\.emoji) == ["😉", "#️⃣"] && fixtureNames.map(\.name) == ["winking face", "keycap: #"])

// Given a gemoji file with several aliases
let aliasFixture = fixture("gemoji.json", """
[{"emoji": "👌", "description": "OK hand", "aliases": ["ok_hand", "okay"], "tags": ["fine"]}]
""")
// When loading its aliases, Then each alias is a name, with spaces instead of underscores, and tags are left out
let fixtureAliases = loadEmojiAliases(from: aliasFixture)
check("loadEmojiAliases_ofEntry_returnsOneNamePerAliasWithSpaces",
      fixtureAliases.map(\.name) == ["ok hand", "okay"] && fixtureAliases.allSatisfy { $0.emoji == "👌" })

// Given the bundled emoji names
let emojiNames = loadDefaultEmojiNames()
check("bestEmoji_ofShortAlias_returnsEmoji",
      ["sob": "😭", "+1": "👍", "tada": "🎉", "100": "💯"].allSatisfy { bestEmoji(for: $0.key, in: emojiNames) == $0.value })
check("loadDefaultEmojiNames_returnsAllEmojiLines", emojiNames.count > 3000)
// When searching, Then prefixes, typos, full names and later words find the closest, shortest name
check("bestEmoji_ofPrefixTypoFullNameOrUppercase_returnsWinking",
      ["wink", "wniking", "winking face", "WINK", " wink "].allSatisfy { bestEmoji(for: $0, in: emojiNames) == "😉" })
check("bestEmoji_ofFormerlyCommentedOutName_returnsIt", bestEmoji(for: "winking face with tongue", in: emojiNames) == "😜")
check("bestEmoji_ofLaterWord_prefersShorterName", bestEmoji(for: "joy", in: emojiNames) == "😂")
check("bestEmoji_ofNothingClose_returnsNil", bestEmoji(for: "xqzz", in: emojiNames) == nil)
check("bestEmoji_ofShortQuery_allowsNoTypo", bestEmoji(for: "wni", in: emojiNames) == nil)

// Given the bundled sequences, When listing them for display
let entries = sequenceEntries(bundled.merging([[composeKeyCharacter] + Array("winking"): "😉"]) { $1 })
let winking = entries.first { $0.output == "😉" }
// Then the Compose key and spaces are visible and the emoji has its Unicode name
check("sequenceEntries_ofDoubleComposeEmoji_showsComposeSymbolAndName",
      winking?.keys == "⎄ ⎄ w i n k i n g" && winking?.name == "winking face")
// When listing the emoji names for display, Then they show the name followed by Return
let emojiEntries = sequenceEntries(emojiNames)
check("sequenceEntries_ofEmojiNames_showsNameThenReturn",
      emojiEntries.first { $0.output == "😜" }?.keys == "⎄ ⎄ winking face with tongue ⏎" && emojiEntries.count == emojiNames.count)
check("sequenceEntries_ofSpaceKey_showsVisibleSpace", sequenceEntries([[" ", " "]: "x"]).first?.keys == "⎄ ␣ ␣")
check("sequenceEntries_isSortedByKeys", entries.map(\.keys) == entries.map(\.keys).sorted())
// When searching, Then the name, the keys, the output match case-insensitively, and nothing else
check("matches_ofNameKeysOrOutput_findsEntry",
      ["winking", "😉", "WINK", ""].allSatisfy { winking?.matches($0) == true } && winking?.matches("zzz") == false)
check("matches_ofKeysWithoutSeparators_findsEntry", entries.first { $0.output == "é" && $0.matches("'e") } != nil)

// Given an engine on the bundled sequences
var engine = ComposeEngine(sequences: bundled, emoji: emojiNames)
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
// When feeding the second Compose press (the first one started composing), a misspelled emoji name, then Return
var emojiResults = [engine.feed(composeKeyCharacter)]
emojiResults += "wniking\r".map { engine.feed($0) }
// Then everything is pending until Return emits the closest emoji
check("feed_ofDoubleComposeFreeText_emitsOnReturn", emojiResults.dropLast().allSatisfy { $0 == .pending } && emojiResults.last == .emit("😉"))
// When ending free text with Tab, Then it emits too
check("feed_ofDoubleComposeFreeText_emitsOnTab", ([composeKeyCharacter] + Array("joy\t")).map { engine.feed($0) }.last == .emit("😂"))
// When nothing is close, Then Return is invalid
check("feed_ofDoubleComposeUnknownName_isInvalid", ([composeKeyCharacter] + Array("xqzz\r")).map { engine.feed($0) }.last == .invalid)
// When typing an exact double Compose rule, Then it still emits right away
check("feed_ofDoubleComposeRule_emitsRightAway", ([composeKeyCharacter] + Array("bzh")).map { engine.feed($0) }.last.map { $0 != .pending && $0 != .invalid } == true)
// When free text gets longer than any name, Then it gives up
let runaway = ([composeKeyCharacter] + Array(repeating: "x", count: 100)).map { engine.feed($0) }
check("feed_ofRunawayFreeText_isInvalid", runaway.contains(.invalid))
// When Backspace is typed in free text, Then it removes the last character, and never the leading Compose
let afterBackspace = ([composeKeyCharacter] + Array("wxy\u{7F}\u{7F}\u{7F}\u{7F}\u{7F}wink\r")).map { engine.feed($0) }
check("feed_ofBackspaceInFreeText_removesLastCharacter",
      afterBackspace.dropLast().allSatisfy { $0 == .pending } && afterBackspace.last == .emit("😉"))

// ComposeKeyDetector
// Given a detector on Right Option (61)
var detector = ComposeKeyDetector(keyCode: 61)
// When pressing then releasing it alone, Then it is a tap (on release only)
check("modifierChanged_ofPressRelease_isTap",
      !detector.modifierChanged(keyCode: 61, isKeyDown: true) && detector.modifierChanged(keyCode: 61, isKeyDown: false))
// When a key is pressed while it is held, Then its release is no tap
_ = detector.modifierChanged(keyCode: 61, isKeyDown: true)
detector.otherInputPressed()
check("modifierChanged_whenKeyPressedWhileHeld_isNoTap", !detector.modifierChanged(keyCode: 61, isKeyDown: false))
// When another modifier changes while it is held, Then its release is no tap
_ = detector.modifierChanged(keyCode: 61, isKeyDown: true)
_ = detector.modifierChanged(keyCode: 56, isKeyDown: true)
check("modifierChanged_whenOtherModifierChangedWhileHeld_isNoTap", !detector.modifierChanged(keyCode: 61, isKeyDown: false))
// When another modifier is tapped, Then it is no tap
check("modifierChanged_ofOtherModifier_isNoTap",
      !detector.modifierChanged(keyCode: 58, isKeyDown: true) && !detector.modifierChanged(keyCode: 58, isKeyDown: false))

if failures > 0 {
    print("\(failures) check(s) failed")
    exit(1)
}
print("All checks passed")
