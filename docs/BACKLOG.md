# Backlog

Known limits and missing features, ordered by user impact. Sizes: S (under a day), M (a few days), L (a week or more).

Not a bug: `include "%L"` in `~/.XCompose` is ignored on purpose. The bundled rules are always loaded first, and reloading them would undo `WinCompose.txt`.

## Limits


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
