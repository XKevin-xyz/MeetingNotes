#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "Building MeetingNotes in release mode..."
swift build -c release

BUILD_BINARY="$(find .build -type f -path '*/release/MeetingNotes' -perm -111 | head -1)"
if [[ -z "$BUILD_BINARY" ]]; then
    echo "Release binary not found" >&2
    exit 1
fi

APP_PATH="$PROJECT_ROOT/dist/MeetingNotes.app"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_BINARY" "$APP_PATH/Contents/MacOS/MeetingNotes"
cp "$PROJECT_ROOT/packaging/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_ROOT/assets/MeetingNotes-logo.png" "$APP_PATH/Contents/Resources/MeetingNotes-logo.png"
chmod +x "$APP_PATH/Contents/MacOS/MeetingNotes"

DMG_PATH="$PROJECT_ROOT/dist/MeetingNotes-0.2.0.dmg"
STAGING_DIR="$(mktemp -d /private/tmp/meetingnotes-dmg.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$APP_PATH" "$STAGING_DIR/MeetingNotes.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "MeetingNotes" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "Created: $APP_PATH"
echo "Created: $DMG_PATH"
echo "Open it with: open \"$APP_PATH\""
