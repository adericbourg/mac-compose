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

if failures > 0 {
    print("\(failures) check(s) failed")
    exit(1)
}
print("All checks passed")
