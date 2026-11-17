import Foundation

/// A compose sequence as shown to the user.
public struct SequenceEntry: Identifiable, Sendable {
    /// `⎄` for the Compose key, then each key separated by a space; a space key is `␣`.
    public let keys: String
    public let output: String
    /// Lowercased Unicode name of the output, like `winking face`.
    public let name: String
    /// The keys as typed after the Compose key, for search.
    let typedKeys: String
    public var id: String { keys }
}

public func sequenceEntries(_ sequences: [[Character]: String]) -> [SequenceEntry] {
    sequences.map { sequence, output in
        let shown = sequence.map { $0 == composeKeyCharacter ? "⎄" : $0 == " " ? "␣" : String($0) }
        let name = (output.applyingTransform(.toUnicodeName, reverse: false) ?? "")
            .replacing("\\N{", with: "").replacing("}", with: " ")
            .trimmingCharacters(in: .whitespaces).lowercased()
        return SequenceEntry(keys: (["⎄"] + shown).joined(separator: " "), output: output, name: name, typedKeys: String(sequence))
    }.sorted { $0.keys < $1.keys }
}

/// Emoji typed by name: `⎄ ⎄ winking face ⏎`.
public func sequenceEntries(_ names: [EmojiName]) -> [SequenceEntry] {
    names.map { SequenceEntry(keys: "⎄ ⎄ \($0.name) ⏎", output: $0.emoji, name: $0.name, typedKeys: $0.name) }
}

extension SequenceEntry {
    /// Case-insensitive search in the output, the name and the typed keys; an empty query matches everything.
    public func matches(_ query: String) -> Bool {
        query.isEmpty || [output, name, typedKeys].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
