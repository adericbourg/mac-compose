import Foundation

/// The text split into chunks of at most 20 UTF-16 units, never inside a character, one key event each.
/// Receivers keep only the first 20 UTF-16 units of an event's string (observed limit, undocumented).
public func utf16Chunks(_ text: String) -> [[UniChar]] {
    var chunks: [[UniChar]] = [[]]
    for character in text {
        let units = Array(String(character).utf16)
        // A character over 20 units still goes alone in one event: it can't be split.
        if !chunks[chunks.count - 1].isEmpty && chunks[chunks.count - 1].count + units.count > 20 { chunks.append([]) }
        chunks[chunks.count - 1] += units
    }
    return chunks
}
