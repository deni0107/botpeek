#!/usr/bin/env bash
# Builds dist/BotPeek.app (universal by default) on macOS.
#
#   VERSION=0.1.0 ./scripts/build-app.sh
#
# Signing: with DEVELOPER_ID_APPLICATION set (an identity in the keychain),
# signs with hardened runtime for notarization; otherwise signs ad hoc.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(cat VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:-arm64 x86_64}"
DIST="$ROOT/dist"
APP="$DIST/BotPeek.app"

arch_args=()
for arch in $ARCHS; do arch_args+=(--arch "$arch"); done

echo "==> Building BotPeek $VERSION ($BUILD_NUMBER) for: $ARCHS"
swift build -c release --product BotPeek "${arch_args[@]}"
BIN_DIR="$(swift build -c release --product BotPeek "${arch_args[@]}" --show-bin-path)"

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BotPeek" "$APP/Contents/MacOS/BotPeek"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD_NUMBER/g" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"

echo "==> Drawing app icon"
swift scripts/make-icon.swift "$DIST/AppIcon.iconset"
iconutil -c icns "$DIST/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$DIST/AppIcon.iconset"

echo "==> Signing"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP"
else
  echo "    No Developer ID configured: signing ad hoc."
  codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/BotPeek")"
"$APP/Contents/MacOS/BotPeek" --version
echo "==> Built $APP"
