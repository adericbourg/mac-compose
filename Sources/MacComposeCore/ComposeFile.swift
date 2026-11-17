import Foundation

/// Stands for a Compose key press inside a sequence (WinCompose's `<Multi_key> <Multi_key> ...` emoji sequences).
public let composeKeyCharacter: Character = "\u{E000}"

/// Bundled Xorg Compose, WinCompose.txt, then the user's `~/.XCompose`. Emoji.txt is searched by name instead (`loadDefaultEmojiNames`).
public func loadDefaultComposeSequences() -> [[Character]: String] {
    let bundled = ["Compose", "WinCompose.txt"].compactMap(bundledResource)
    return loadComposeSequences(from: bundled + [FileManager.default.homeDirectoryForCurrentUser.appending(path: ".XCompose")])
}

/// Sequences typed after the Compose key, mapped to their output. Missing files are skipped; later definitions win.
public func loadComposeSequences(from urls: [URL]) -> [[Character]: String] {
    let root = TrieNode()
    for url in urls {
        load(url, into: root, depth: 0)
    }
    var sequences: [[Character]: String] = [:]
    root.collect(prefix: [], into: &sequences)
    return sequences
}

// A trie enforces X11's rule that no sequence is a prefix of another: inserting removes the conflicting ones.
private final class TrieNode {
    var children: [Character: TrieNode] = [:]
    var output: String?

    func insert(_ sequence: [Character], _ output: String) {
        var node = self
        for character in sequence {
            node.output = nil
            if let child = node.children[character] {
                node = child
            } else {
                let child = TrieNode()
                node.children[character] = child
                node = child
            }
        }
        node.output = output
        node.children = [:]
    }

    func collect(prefix: [Character], into sequences: inout [[Character]: String]) {
        if let output {
            sequences[prefix] = output
        }
        for (character, child) in children {
            child.collect(prefix: prefix + [character], into: &sequences)
        }
    }
}

private func load(_ url: URL, into root: TrieNode, depth: Int) {
    guard depth < 10, let text = try? String(contentsOf: url, encoding: .utf8) else {
        return
    }
    for line in text.split(whereSeparator: \.isNewline) {
        let line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("include") {
            if let included = includeURL(line) {
                load(included, into: root, depth: depth + 1)
            }
        } else if let (sequence, output) = parseRule(Substring(line)) {
            root.insert(sequence, output)
        } else if !line.hasPrefix("#"), !line.hasPrefix("<"), line.contains("<Multi_key>") {
            NSLog("MacCompose: skipped rule with modifiers (not supported): %@", line)
        }
    }
}

private func includeURL(_ line: String) -> URL? {
    let parts = line.split(separator: "\"")
    // %L is skipped: the bundled Compose is always loaded first, and reloading it would undo WinCompose.txt.
    guard parts.count >= 2, !parts[1].contains("%S"), !parts[1].contains("%L") else {
        return nil
    }
    return URL(filePath: String(parts[1]).replacing("%H", with: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)))
}

/// `<Multi_key> <a> <b> : "output" keysym # comment`, without the leading `<Multi_key>`.
private func parseRule(_ line: Substring) -> ([Character], String)? {
    var rest = line
    var names: [Substring] = []
    while let first = rest.first, first != ":" {
        if first.isWhitespace {
            rest = rest.dropFirst()
            continue
        }
        // WinCompose also writes literal characters as names: `<!>`, `< >`.
        guard first == "<", let close = rest.dropFirst().firstIndex(of: ">") else {
            return nil
        }
        names.append(rest[rest.index(after: rest.startIndex)..<close])
        rest = rest[rest.index(after: close)...]
    }
    guard names.first == "Multi_key", names.count > 1, !rest.isEmpty else {
        return nil
    }
    var sequence: [Character] = []
    for name in names.dropFirst() {
        guard let character = name == "Multi_key" ? composeKeyCharacter
            : keysymCharacter(named: String(name)) ?? (name.count == 1 ? name.first : nil) else {
            return nil
        }
        sequence.append(character)
    }
    rest = rest.dropFirst().drop(while: \.isWhitespace)
    guard let output = rest.first == "\"" ? parseQuoted(rest.dropFirst())
        : rest.split(whereSeparator: \.isWhitespace).first.flatMap({ keysymCharacter(named: String($0)) }).map(String.init),
        !output.isEmpty else {
        return nil
    }
    return (sequence, output)
}

/// Escapes: `\"`, `\\`, octal `\NNN` (1-3 digits) and hex `\xHH` (1-2 digits). Xlib stores a byte there; values above 0x7F are read as the Unicode scalar of the same value (Latin-1).
private func parseQuoted(_ text: Substring) -> String? {
    var output = ""
    var rest = text
    while let character = rest.popFirst() {
        if character == "\\", let escaped = rest.popFirst() {
            let isHex = escaped == "x"
            let digits = (isHex ? rest : Substring([escaped] + rest)).prefix(isHex ? 2 : 3)
                .prefix(while: { isHex ? $0.isHexDigit : ("0"..."7").contains($0) })
            if let value = UInt32(digits, radix: isHex ? 16 : 8), let scalar = Unicode.Scalar(value) {
                output.append(Character(scalar))
                rest = rest.dropFirst(isHex ? digits.count : digits.count - 1)
            } else {
                output.append(escaped)
            }
        } else if character == "\"" {
            return output
        } else {
            output.append(character)
        }
    }
    return nil
}
