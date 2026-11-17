#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

app=build/MacCompose.app
bin=$(swift build -c release --show-bin-path)
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/MacCompose" "$app/Contents/MacOS/"
# Bundle.module looks in Bundle.main.resourceURL (Contents/Resources) for the SwiftPM resource bundle.
cp -R "$bin/MacCompose_MacComposeCore.bundle" "$app/Contents/Resources/"
cp Support/Info.plist "$app/Contents/"
/usr/libexec/PlistBuddy -c "Add :MacComposeCommit string $(git rev-parse --short HEAD)" "$app/Contents/Info.plist"

# A stable identity keeps the Accessibility and Input Monitoring grants across builds; ad-hoc ties them to one build.
identity="MacCompose Signing"
if ! security find-identity -p codesigning | grep -q "\"$identity\""; then
    echo "warning: no '$identity' identity in the keychain, signing ad-hoc" >&2
    identity=-
fi
# Hardened runtime: without it any process can load code into the app (DYLD_INSERT_LIBRARIES) and use its grants.
codesign --force --options runtime --sign "$identity" "$app"
