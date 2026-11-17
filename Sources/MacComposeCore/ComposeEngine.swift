/// Matches typed characters against the compose sequences. Only fed while composing; the caller feeds `composeKeyCharacter` for a Compose press.
/// After a second Compose press, input that matches no sequence is an emoji name, ended by Return or Tab.
public struct ComposeEngine: Sendable {
    public enum Result: Equatable, Sendable {
        case pending
        case emit(String)
        case invalid
    }

    private let sequences: [[Character]: String]
    private let prefixes: Set<[Character]>
    private let emoji: [EmojiName]
    /// Free text longer than any emoji name gives up, so a forgotten Compose doesn't keep swallowing keys.
    private let maxFreeTextLength: Int
    private var buffer: [Character] = []

    public init(sequences: [[Character]: String], emoji: [EmojiName]) {
        self.sequences = sequences
        self.emoji = emoji
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
            guard character == "\r" || character == "\t" else {
                return .pending
            }
            let query = String(buffer.dropFirst().dropLast())
            buffer = []
            return bestEmoji(for: query, in: emoji).map(Result.emit) ?? .invalid
        }
        buffer = []
        return .invalid
    }

    public mutating func reset() {
        buffer = []
    }
}
