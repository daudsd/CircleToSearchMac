#!/bin/bash
# Builds Circle Search.app.  Usage:
#   ./build.sh            -> build/Circle Search.app
#   ./build.sh --install  -> also copies it to /Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ Compiling (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Circle Search.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CircleSearch" "$APP/Contents/MacOS/CircleSearch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Signing (ad-hoc)…"
codesign --force --sign - --identifier com.daud.CircleSearch "$APP"

echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x CircleSearch 2>/dev/null || true
    rm -rf "/Applications/Circle Search.app"
    cp -R "$APP" /Applications/
    # Each rebuild changes the ad-hoc signature, so macOS forgets the old
    # Screen Recording approval. Reset it so the app asks cleanly again.
    tccutil reset ScreenCapture com.daud.CircleSearch >/dev/null 2>&1 || true
    open "/Applications/Circle Search.app"
    echo "✓ Installed to /Applications and launched"
fi
