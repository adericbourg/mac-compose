import Foundation

/// An emoji and its lowercased English name, as in `Emoji.txt`.
public struct EmojiName: Sendable {
    public let name: String
    public let emoji: String
}

public func loadDefaultEmojiNames() -> [EmojiName] {
    (bundledResource("Emoji.txt").map(loadEmojiNames) ?? []) + (bundledResource("gemoji.json").map(loadEmojiAliases) ?? [])
}

/// Every line of a WinCompose emoji file, commented out or not: `... "😉" U1F609 # winking face`.
public func loadEmojiNames(from url: URL) -> [EmojiName] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        return []
    }
    return text.split(whereSeparator: \.isNewline).compactMap { line in
        let parts = line.split(separator: "\"", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[1].isEmpty, let hash = line.range(of: "# ", options: .backwards) else {
            return nil
        }
        return EmojiName(name: line[hash.upperBound...].trimmingCharacters(in: .whitespaces).lowercased(), emoji: String(parts[1]))
    }
}

/// One name per gemoji alias (`sob`, `+1`, `ok_hand`), with underscores as spaces so each word can be searched.
public func loadEmojiAliases(from url: URL) -> [EmojiName] {
    struct Entry: Decodable {
        let emoji: String
        let aliases: [String]
    }
    guard let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
        return []
    }
    return entries.flatMap { entry in
        entry.aliases.map { EmojiName(name: $0.replacingOccurrences(of: "_", with: " "), emoji: entry.emoji) }
    }
}

/// The emoji whose name, or a word in it, starts closest to `query`, allowing a typo or two in longer queries.
/// Ties go to a whole word, then to the name's first word, then to the shorter name, then to file order.
public func bestEmoji(for query: String, in names: [EmojiName]) -> String? {
    let query = Array(query.trimmingCharacters(in: .whitespaces).lowercased())
    guard !query.isEmpty else {
        return nil
    }
    let maxDistance = query.count <= 3 ? 0 : query.count <= 6 ? 1 : 2
    var best: (rank: (Int, Int, Int, Int), emoji: String)?
    for entry in names {
        let name = Array(entry.name)
        let wordStarts = name.indices.filter { $0 == 0 || name[$0 - 1] == " " }
        for (wordIndex, start) in wordStarts.enumerated() {
            let (distance, isWholeWord) = prefixDistance(query, name[start...], maxDistance: maxDistance)
            let rank = (distance, isWholeWord ? 0 : 1, wordIndex == 0 ? 0 : 1, name.count)
            if distance <= maxDistance, best.map({ rank < $0.rank }) ?? true {
                best = (rank, entry.emoji)
            }
        }
    }
    return best?.emoji
}

/// Optimal string alignment distance (edits and swaps of adjacent characters) from `query` to the closest prefix of `text`,
/// and whether the first word of `text` is one of the closest prefixes.
private func prefixDistance(_ query: [Character], _ rest: ArraySlice<Character>, maxDistance: Int) -> (Int, Bool) {
    let text = Array(rest.prefix(query.count + maxDistance))
    var previous: [Int] = []
    var row = Array(0...text.count)
    for i in 1...query.count {
        var next = [i] + Array(repeating: 0, count: text.count)
        for j in stride(from: 1, through: text.count, by: 1) {
            next[j] = min(row[j] + 1, next[j - 1] + 1, row[j - 1] + (query[i - 1] == text[j - 1] ? 0 : 1))
            if i > 1, j > 1, query[i - 1] == text[j - 2], query[i - 2] == text[j - 1] {
                next[j] = min(next[j], previous[j - 2] + 1)
            }
        }
        previous = row
        row = next
    }
    let distance = row.min()!
    // Only seen when the word fits in the compared prefix: a longer word is not whole anyway.
    let wordEnd = text.firstIndex(of: " ") ?? (text.count == rest.count ? text.count : nil)
    let isWholeWord = wordEnd.map { row[$0] == distance } ?? false
    return (distance, isWholeWord)
}
