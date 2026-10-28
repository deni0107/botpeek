#!/usr/bin/env bash
# Packages dist/BotPeek.app into a drag-to-Applications DMG and a ZIP, with
# SHA-256 checksums. Notarizes and staples when Apple credentials are set:
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(cat VERSION)}"
DIST="$ROOT/dist"
APP="$DIST/BotPeek.app"
NAME="BotPeek-$VERSION-macos-universal"
ZIP="$DIST/$NAME.zip"
DMG="$DIST/$NAME.dmg"

[[ -d "$APP" ]] || { echo "Build the app first: scripts/build-app.sh" >&2; exit 1; }

notarize() {
  local file="$1"
  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "==> Notarizing $(basename "$file")"
    xcrun notarytool submit "$file" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait
    return 0
  fi
  return 1
}

rm -f "$ZIP" "$DMG" "$DIST/SHA256SUMS.txt"

# Notarize the app itself first (via a temporary zip) so both archives contain a stapled app.
if [[ -n "${APPLE_ID:-}" ]]; then
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  notarize "$DIST/notarize.zip"
  xcrun stapler staple "$APP"
  rm -f "$DIST/notarize.zip"
fi

echo "==> Creating $(basename "$ZIP")"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Creating $(basename "$DMG")"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read Me First.txt" <<'EOF'
Drag BotPeek into Applications, then open it from Applications.

If macOS says it can't verify the developer: open System Settings → Privacy & Security,
scroll down and click "Open Anyway" next to BotPeek. Do not disable Gatekeeper.

BotPeek is free, open source (MIT) and not affiliated with Grok Bot, xAI or Cursor.
https://github.com/DenisDule/botpeek
EOF
hdiutil create -volname "BotPeek $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG"
fi
if notarize "$DMG"; then xcrun stapler staple "$DMG"; fi

echo "==> Checksums"
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" | tee SHA256SUMS.txt)
