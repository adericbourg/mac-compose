# Backlog

Known limits and missing features, ordered by user impact. Sizes: S (under a day), M (a few days), L (a week or more).

Not a bug: `include "%L"` in `~/.XCompose` is ignored on purpose. The bundled rules are always loaded first, and reloading them would undo `WinCompose.txt`.

## Limits

### 2. Dead keys pressed while composing type nothing (M)

- **Problem:** on layouts with dead keys (French, Spanish...), pressing one while composing is swallowed. The user sees no reaction.
- **Where:** `Sources/MacCompose/KeyTap.swift` (`handle`, `.keyDown` case: `characters` is empty for a dead key).
- **Fix:** depends on item 1, and on knowing which `dead_*` a key is (it varies by layout). Check feasibility first.

### 4. Revoked Accessibility is not detected (S)

- **Problem:** after revoking the permission, the app looks active and the menu shows no warning.
- **Where:** `Sources/MacCompose/main.swift` (the permission is only polled until first granted), `Sources/MacCompose/KeyTap.swift` (`handle` re-enables a disabled tap without checking).
- **Fix:** poll `AXIsProcessTrusted()` every second. Set `isPermissionNeeded` when it is false, and drop and recreate the tap when it becomes true again.

### 5. Output typed with virtual key 0 may break in some apps (S to verify, M to fix)

- **Problem:** an app that reads the key code instead of the event string would type `a`. Terminals are to verify.
- **Where:** `Sources/MacCompose/KeyTap.swift` (`type`).
- **Fix:** test in Terminal, iTerm2, a VM and a remote desktop client. If one fails, choose a fallback then.

### 6. The event tap and typing path is not tested end to end (M)

- **Problem:** it needs the Accessibility permission, so no automated check covers it. Regressions are found by users.
- **Where:** `Sources/MacCompose/KeyTap.swift`, `Sources/MacComposeChecks/main.swift`.
- **Fix:** run the manual list under "Verification" in the plan `i-am-missing-a-cuddly-wren.md` before each release, and record it in `docs/DEVELOPMENT.md`.

### 7. Caps Lock cannot be the Compose key (M)

- **Problem:** WinCompose and many Linux users use Caps Lock. Only Right Option, Right Command and Right Control are offered.
- **Where:** `Sources/MacCompose/KeyTap.swift` (`ComposeKey`), `Sources/MacComposeCore/ComposeKeyDetector.swift`.
- **Fix:** Caps Lock sends `flagsChanged` with a toggled state, not a press and release. Detect the toggle, then reset the state. Alternatively, document remapping Caps Lock to Right Control in System Settings.

### 9. Output is chunked at 20 UTF-16 units (S)

- **Problem:** the limit is observed, not documented. A macOS update could change it and truncate long emoji sequences.
- **Where:** `Sources/MacCompose/KeyTap.swift` (`type`).
- **Fix:** add a check that types a 40-unit string in a text field, and run it on each new macOS version.

### 10. kragen's dotXCompose rules are not bundled (S)

- **Problem:** WinCompose ships them, so some of its sequences are missing here.
- **Where:** `Sources/MacComposeCore/Resources/`.
- **Fix:** ask the author for a license. Without an answer, tell users to copy the rules into `~/.XCompose`.

### 11. Local builds lose the Accessibility grant (S)

- **Problem:** without the `MacCompose Signing` certificate, `scripts/bundle.sh` signs ad-hoc and the grant is lost at every rebuild.
- **Where:** `scripts/bundle.sh`, `docs/DEVELOPMENT.md` ("Signing certificate").
- **Fix:** create the certificate once, as documented. No code change.

### 12. Homebrew casks hold placeholder values (S)

- **Problem:** `sha256` is `000...0` in `mac-compose.rb` and `mac-compose-nightly.rb` until a workflow runs, so `brew install` fails.
- **Where:** `Casks/` in `adericbourg/homebrew-tap`.
- **Fix:** run the Release workflow once.


## Missing features

Compared with WinCompose.

### 2. No feedback of the sequence being typed (M)

- **Problem:** the user cannot see what was typed so far. Only the menu bar icon changes. Emoji names make this worse: the result of a fuzzy match is only seen once it's typed.
- **Where:** `Sources/MacCompose/KeyTap.swift` (`feed`), `Sources/MacCompose/main.swift` (status item).
- **Fix:** show the typed keys as the menu bar item title, for example `' …`. A floating window near the caret is larger and needs more permissions.
