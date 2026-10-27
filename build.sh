#!/bin/bash
# Claude Usage Bar'ı derler ve build/ClaudeUsageBar.app paketini üretir.
# Kullanım: ./build.sh            (release)
#           ./build.sh --install  (ayrıca /Applications'a kopyalar)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ClaudeUsageBar"
APP="build/$APP_NAME.app"

echo "▸ Derleniyor (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "▸ Paketleniyor → $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Ad-hoc imzalanıyor"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "▸ /Applications'a kuruluyor"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    echo "✓ Kuruldu: /Applications/$APP_NAME.app  (açmak için: open /Applications/$APP_NAME.app)"
else
    echo "✓ Hazır: $APP  (açmak için: open $APP)"
fi
