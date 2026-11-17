# Development

## Build

Command Line Tools are enough, Xcode is not needed.

```sh
./scripts/bundle.sh
open --stderr "$(tty)" build/MacCompose.app
```

`bundle.sh` signs with the `MacCompose Signing` identity when it is in the keychain, and ad-hoc otherwise (with a warning). An ad-hoc build loses the permission on every rebuild. Both sign with the hardened runtime, so that no other process can load code into the app and use its permission. The app sends no Apple events, so it has no entitlements file.

Coming from an ad-hoc build, grant the permission once more. If MacCompose already shows ON but composing does nothing, reset the grant, then grant it again:

```sh
tccutil reset Accessibility io.github.adericbourg.mac-compose
```

## Checks

`swift run MacComposeChecks` runs the pure-logic checks (no XCTest on Command Line Tools) and exits non-zero on failure.

## Manual checks before a release

The event tap needs the Accessibility permission, so no automated check covers it. Run these on the release build:

1. `swift run MacComposeChecks` passes.
2. `./scripts/bundle.sh && open build/MacCompose.app`, then grant Accessibility.
3. In TextEdit: Compose, `'`, `e` gives `é`; `-`, `>` gives `→`; `o`, `o` gives `°`; Compose, Compose, `wink`, Return gives `😉`; Compose, Compose, `sob` gives `😭` with no Return; Compose, Compose, `joy` gives `😂` after a 1 s pause.
4. With "Compose while held" off, Right Option held with `e` still types the normal Option character.
5. Pick Right Command in the menu, then repeat step 3.
6. Add `<Multi_key> <x> <x> : "✗"` to `~/.XCompose`, pick "Reload sequences", then type Compose, `x`, `x`.
7. While composing, the typed keys appear next to the menu bar icon, and clear when the sequence ends or is cancelled.
8. In an emoji name, Backspace deletes the last character.
9. A mouse click cancels composing.
10. Composing cancels after 5 s without a key.
11. On a French layout, Compose, the dead `^` key, `e` gives `ê`. On US-International, do the same with Shift+6.
12. In System Settings, revoke Accessibility: the menu shows "Accessibility permission needed" and keys are no longer swallowed. Grant it again: composing works without a restart.
13. "Launch at login" is ticked on the first launch. Untick it and relaunch: it stays unticked. Tick it, log out and in: the app starts.
14. Compose output types correctly in Terminal, iTerm2, a VM and a remote desktop client. The app posts output with virtual key 0, so an app that reads key codes would type `a`.
15. Open "Compose sequences" from the menu and type without clicking: the text goes into the search field. Close the window, bring another app to the front, reopen it and type again.
16. An output of 40 UTF-16 units or more (a long ZWJ emoji sequence, or a test rule in `~/.XCompose`) arrives whole in a text field. The app types output in chunks of 20 units, an observed and undocumented limit. Run this on each new macOS version.

## Releasing

Apple silicon only. `./scripts/archive.sh` builds the bundle and zips it into `build/MacCompose-<version>.zip`, printing the path and its sha256 (for the cask). To release: run the Release workflow from the Actions tab on `main` and pick the part to increase: `patch`, `minor` (default) or `major`. It runs the checks, sets the next version in `Support/Info.plist` with `./scripts/bump-version.sh` (both `CFBundleShortVersionString` and `CFBundleVersion`), builds and signs the zip, then creates the GitHub release `v<version>` on a `chore: release v<version>` commit, and pushes that commit to `main` last. Up to there, nothing is left if a step fails: the push fails if `main` moved during the run, and the release and its tag are then deleted. Don't edit the version by hand. A second job then sets `version` and `sha256` in `Casks/mac-compose.rb` of `adericbourg/homebrew-tap` and pushes it to that repository's `main`. If this job fails, the release and the version commit stay: re-run the job, or edit the cask by hand. It needs the `HOMEBREW_TAP_TOKEN` secret: a fine-grained token limited to the tap, with `Contents: Read and write`.

### Nightly

The Nightly workflow builds `main` every day at 03:00 UTC, or when started from the Actions tab. If `main` hasn't moved since the last nightly, it stops there. Otherwise it runs the checks, builds and signs the zip as a release does, and publishes it as the pre-release `nightly-<YYYY-MM-DD>`. The bundle's `CFBundleShortVersionString` is that tag, so the menu shows `Version nightly-<YYYY-MM-DD> (<commit>)`; the version in `Support/Info.plist` on `main` doesn't change. A second run on the same day replaces that day's nightly. It then sets `version` and `sha256` in `Casks/mac-compose-nightly.rb` of the tap, and only after that deletes the previous `nightly-*` releases and their tags.

### Signing certificate

Releases are signed with a self-signed certificate (`CN=MacCompose Signing`). TCC then pins the grant to `identifier + certificate leaf` instead of each build's cdhash. Losing the certificate means every user grants the permission once more, so keep the `.p12` and its password in a password manager. The Release workflow imports it from the `SIGNING_CERT_P12` (base64 of the `.p12`) and `SIGNING_CERT_PASSWORD` secrets, and refuses to release an ad-hoc build. To create one (valid 10 years), then use the same `.p12` on your Mac so local builds share the grant:

```sh
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -subj "/CN=MacCompose Signing" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -name "MacCompose Signing" -out MacCompose-signing.p12
security import MacCompose-signing.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
base64 -i MacCompose-signing.p12 | pbcopy
```

Then, in the repository's Settings > Secrets and variables > Actions, add the repository secret `SIGNING_CERT_P12` and paste the clipboard as its value, then add `SIGNING_CERT_PASSWORD` with the `.p12` password.

`security find-identity -p codesigning` lists it as `CSSMERR_TP_NOT_TRUSTED`; that is expected and does not prevent signing.
