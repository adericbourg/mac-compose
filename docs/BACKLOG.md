# Backlog

Known limits, ordered by user impact. Sizes: S (under a day), M (a few days), L (a week or more).

Not a bug: `include "%L"` in `~/.XCompose` is ignored on purpose. The bundled rules are always loaded first, and reloading them would undo `WinCompose.txt`.

## Limits

### 1. kragen's dotXCompose rules are not bundled (S)

- **Problem:** WinCompose ships them, so some of its sequences are missing here.
- **Where:** `Sources/MacComposeCore/Resources/`.
- **Fix:** ask the author for a license. Without an answer, tell users to copy the rules into `~/.XCompose`.

### 2. `KP_*` rules are skipped (M)

- **Problem:** 108 Xorg rules using keypad keys are not loaded. This is on purpose: a keypad key types the same character as the main row, so the app cannot tell them apart.
- **Where:** `Sources/MacComposeCore/Keysyms.swift`.
- **Fix:** match on key codes instead of characters.
