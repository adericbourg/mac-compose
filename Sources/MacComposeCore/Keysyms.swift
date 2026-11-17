import Foundation

/// Character typed by a keysym name (`eacute`, `U2192`), or nil for keys without one (`dead_*`, `KP_*`, arrows...).
public func keysymCharacter(named name: String) -> Character? {
    if name.count > 1, name.hasPrefix("U"), let value = UInt32(name.dropFirst(), radix: 16) {
        return Unicode.Scalar(value).map(Character.init)
    }
    return keysymTable[name]
}

private let keysymTable: [String: Character] = {
    guard let url = bundledResource("keysymdef.h"), let text = try? String(contentsOf: url, encoding: .utf8) else {
        return [:]
    }
    var table: [String: Character] = [:]
    for line in text.split(separator: "\n") where line.hasPrefix("#define XK_") {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 3, parts[2].hasPrefix("0x"), let value = UInt32(parts[2].dropFirst(2), radix: 16) else {
            continue
        }
        let name = String(parts[1].dropFirst(3))
        // `/*<U+...>*/` marks keypad keys, which we treat as having no character.
        if let plus = line.range(of: "U+"), line[line.index(before: plus.lowerBound)] != "<" {
            let hex = line[plus.upperBound...].prefix(while: \.isHexDigit)
            table[name] = UInt32(hex, radix: 16).flatMap(Unicode.Scalar.init).map(Character.init)
        } else if (0x20...0xff).contains(value) {
            // Deprecated Latin-1 aliases (`quoteright`, `Thorn`...) have no U+ comment: their value is the code point.
            table[name] = Unicode.Scalar(value).map(Character.init)
        }
    }
    return table
}()
