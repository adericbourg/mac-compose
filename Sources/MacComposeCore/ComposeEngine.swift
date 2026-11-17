/// Matches typed characters against the compose sequences. Only fed while composing; the caller feeds `composeKeyCharacter` for a Compose press.
/// After a second Compose press, input that matches no sequence is an emoji name. It emits as soon as it is a name no other
/// name continues (`sob`, not `joy` because of `joystick`), or when ended by Return, Tab or `finishName()`.
public struct ComposeEngine: Sendable {
    public enum Result: Equatable, Sendable {
        case pending
        case emit(String)
        case invalid
    }

    private let sequences: [[Character]: String]
    private let prefixes: Set<[Character]>
    private let emoji: [EmojiName]
    /// Names no other name continues, each with a single emoji.
    private let unambiguousNames: [String: String]
    /// Free text longer than any emoji name gives up, so a forgotten Compose doesn't keep swallowing keys.
    private let maxFreeTextLength: Int
    private var buffer: [Character] = []
    /// The characters fed so far in the current sequence, Compose presses included.
    public var typed: [Character] { buffer }
    /// True while typing an emoji name, not the start of a double Compose rule.
    public var isTypingName: Bool {
        buffer.first == composeKeyCharacter && buffer.count > 1 && !prefixes.contains(buffer)
    }

    public init(sequences: [[Character]: String], emoji: [EmojiName]) {
        self.sequences = sequences
        self.emoji = emoji
        let namePrefixes = Set(emoji.flatMap { entry in (0..<entry.name.count).map { String(entry.name.prefix($0)) } })
        let emojiByName = Dictionary(grouping: emoji, by: \.name).mapValues { Set($0.map(\.emoji)) }
        unambiguousNames = emojiByName.compactMapValues { $0.count == 1 ? $0.first : nil }
            .filter { !namePrefixes.contains($0.key) }
        maxFreeTextLength = (emoji.map(\.name.count).max() ?? 0) + 5
        prefixes = Set(sequences.keys.flatMap { sequence in (0..<sequence.count).map { Array(sequence[..<$0]) } })
    }

    public mutating func feed(_ character: Character) -> Result {
        buffer.append(character)
        if let output = sequences[buffer] {
            buffer = []
            return .emit(output)
        }
        if prefixes.contains(buffer) {
            return .pending
        }
        if buffer.first == composeKeyCharacter, buffer.count <= maxFreeTextLength + 1 {
            if character == "\u{7F}" {
                buffer.removeLast()
                if buffer.count > 1 { buffer.removeLast() }
                return .pending
            }
            if character == "\r" || character == "\t" {
                defer { buffer = [] }
                buffer.removeLast()
                return finishName() ?? .invalid
            }
            if let output = unambiguousNames[String(buffer.dropFirst()).lowercased()] {
                buffer = []
                return .emit(output)
            }
            return .pending
        }
        buffer = []
        return .invalid
    }

    /// Ends the emoji name being typed with its closest emoji; nil when no name is being typed.
    public mutating func finishName() -> Result? {
        guard buffer.first == composeKeyCharacter, buffer.count > 1 else { return nil }
        let query = String(buffer.dropFirst())
        buffer = []
        return bestEmoji(for: query, in: emoji).map(Result.emit) ?? .invalid
    }

    public mutating func reset() {
        buffer = []
    }
}
