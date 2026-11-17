/// Matches typed characters against the compose sequences. Only fed while composing; the caller feeds `composeKeyCharacter` for a Compose press.
public struct ComposeEngine: Sendable {
    public enum Result: Equatable, Sendable {
        case pending
        case emit(String)
        case invalid
    }

    private let sequences: [[Character]: String]
    private let prefixes: Set<[Character]>
    private var buffer: [Character] = []

    public init(sequences: [[Character]: String]) {
        self.sequences = sequences
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
        buffer = []
        return .invalid
    }

    public mutating func reset() {
        buffer = []
    }
}
