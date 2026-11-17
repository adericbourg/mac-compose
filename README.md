# mac-compose

A Compose key for macOS, like the one on Linux and in WinCompose. Tap the Compose key, type a few characters, get the symbol: `' e` gives é, `- >` gives →.

It runs in the menu bar and works in any app.

## Install

You need macOS 27.2 or later on Apple silicon.

```sh
brew install --cask adericbourg/tap/mac-compose
```

To test the latest `main`, install the daily build `mac-compose-nightly` instead. It's the same app, so it replaces `mac-compose` and keeps its permission and settings:

```sh
brew uninstall --cask mac-compose
brew install --cask adericbourg/tap/mac-compose-nightly
```

The app is self-signed and not notarized, so Gatekeeper would refuse to open it. The cask removes the quarantine attribute after installing, so installing from the tap means trusting it to bypass Gatekeeper for this app.

To install by hand instead:

1. Download the zip from the [releases page](https://github.com/adericbourg/mac-compose/releases).
2. Move `MacCompose.app` to `/Applications`.
3. Remove the quarantine attribute:

```sh
xattr -d com.apple.quarantine /Applications/MacCompose.app
```

## First launch

1. Open MacCompose. A keyboard icon appears in the menu bar.
2. Grant the Accessibility permission in System Settings → Privacy & Security → Accessibility. The app needs it to read your keystrokes and type the result. Until you do, the menu shows "Accessibility permission needed". Composing starts as soon as the permission is granted.

## Use

1. Tap the Compose key alone, without holding it with another key. The default is Right Option. The menu bar icon changes while you compose. With "Compose while held" on, you can also keep it held while typing the sequence.
2. Type the sequence, one key at a time.

| Keys | Result |
|---|---|
| `' e` | é |
| `- >` | → |
| `o o` | ° |
| Compose, Compose, then `wink` and Return | 😉 |

Emoji are Compose, Compose, then the emoji's English name or the start of any word in it, then Return or Tab: `wink`, `winking face` or even `wniking` all give 😉, and `joy` gives 😂. GitHub and Slack short names work too: `sob` gives 😭, `+1` gives 👍. Typos are allowed in longer names. If several emoji match, the shortest name wins. If nothing is close, it beeps. To find any sequence, pick "Show sequences…" in the menu and search by result (`é`), name (`arrow`) or keys (`'e`). The list includes your `~/.XCompose` rules.

Escape cancels. A sequence that doesn't exist beeps and is dropped. Holding the Compose key with another key still works as a normal modifier, unless "Compose while held" is on: the Compose key then no longer works as a modifier at all. For example, with Right Option as the Compose key, it no longer types Option characters or does Option+arrow; with Right Command, it no longer triggers shortcuts. Its left twin keeps working.

The menu bar menu has:

| Item | Result |
|---|---|
| Enabled | Turns composing on or off |
| Compose key | Right Option (default), Right Command or Right Control |
| Compose while held | Holding the Compose key while typing composes too, like on Linux. Off by default |
| Launch at login | Starts the app when you log in. Turned on the first time the app runs; untick it to keep it off. Only works from the app bundle |
| Reload sequences | Reads `~/.XCompose` again |
| Show sequences… | Lists every sequence, with a search field |
| Version | The version and commit you are running. Include them when you report a bug |
| Quit | Quits the app |

## Custom sequences

Add rules to `~/.XCompose`, in the X11 format:

```
<Multi_key> <x> <x> : "✗"
```

Then pick "Reload sequences" in the menu.

- Your rules are loaded after the default ones, and a later rule replaces an earlier one with the same keys.
- `include "%L"` lines are ignored: the default sequences are always loaded first.

## Default sequences

The Xorg `en_US.UTF-8` Compose rules, plus the [WinCompose](https://github.com/samhocevar/wincompose) rules and emoji, and the [gemoji](https://github.com/github/gemoji) short names. Sources and licenses are in [NOTICE](Sources/MacComposeCore/Resources/NOTICE).

## Known limits

- Sequences with dead keys (`dead_*`) or keypad keys (`KP_*`) are skipped when loading: 529 of the Xorg rules.
- `~/.XCompose`: octal and hex escapes in quoted output are not supported, modifier lines (`~Ctrl`, `!`) are skipped, and `$XCOMPOSEFILE` is not read.
- The Compose key is Right Option, Right Command or Right Control. Caps Lock is not possible.
- A dead key pressed while composing is swallowed and types nothing.
- A mouse click does not cancel composing. Press Escape.
- If you revoke the Accessibility permission while the app runs, the menu does not warn you.
- Apple silicon only, macOS 27.2 or later.

Each limit, with the planned fix and the missing features (on-screen feedback, timeout), is in the [backlog](docs/BACKLOG.md).

## Uninstall

```sh
brew uninstall --cask mac-compose
```

## More

- [Development](docs/DEVELOPMENT.md): build from source and release
- [Backlog](docs/BACKLOG.md): known limits and missing features

## License

[GPLv3](LICENSE)
