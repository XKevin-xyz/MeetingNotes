#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_PATH="$PROJECT_ROOT/dist/MeetingNotes.app"
DMG_PATH="$PROJECT_ROOT/dist/MeetingNotes-0.2.0.dmg"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "DEVELOPER_ID_APPLICATION is not set."
    echo "Example: export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'"
    echo "Create the unsigned package with: zsh scripts/package.sh"
    exit 2
fi

echo "Building the release package..."
zsh "$PROJECT_ROOT/scripts/package.sh"

echo "Signing app with: $SIGNING_IDENTITY"
codesign --deep --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$APP_PATH"

echo "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Creating DMG from the signed app..."
STAGING_DIR="$(mktemp -d /private/tmp/meetingnotes-release-dmg.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$APP_PATH" "$STAGING_DIR/MeetingNotes.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "MeetingNotes" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "No NOTARY_KEYCHAIN_PROFILE configured."
    echo "The app is signed, but not notarized."
    echo "Set a notarytool keychain profile and run this script again for distribution."
    exit 0
fi

echo "Submitting DMG for notarization..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler staple "$DMG_PATH"

echo "Validating Gatekeeper assessment..."
spctl --assess --type execute --verbose=2 "$APP_PATH"

echo "Release ready: $DMG_PATH"
