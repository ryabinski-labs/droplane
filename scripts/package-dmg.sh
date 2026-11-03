#!/bin/bash
# Builds a Developer ID signed, notarized, stapled DMG.
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE="droplane-notary" \
#   ./scripts/package-dmg.sh
#
# Or with the App Store Connect API key:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   NOTARY_KEY_PATH=/path/to/AuthKey.p8 APPLE_KEY_ID=... ASC_ISSUER_ID=... \
#   ./scripts/package-dmg.sh
#
# Local structural test without Apple's notary service:
#   ./scripts/package-dmg.sh --no-notarize
set -euo pipefail
cd "$(dirname "$0")/.."

NO_NOTARIZE=0
if [ "${1:-}" = "--no-notarize" ]; then
    NO_NOTARIZE=1
fi

VERSION="${VERSION:-0.1.2}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="${APP_PATH:-build/Droplane.app}"
DIST="${DIST_DIR:-dist}"
DMG="${DMG_PATH:-$DIST/Droplane-$VERSION.dmg}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/droplane-dmg.XXXXXX")"
MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/droplane-mount.XXXXXX")"

cleanup() {
    hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
    rm -rf "$STAGE" "$MOUNT" "${DMG_SIGN_ERROR:-}"
}
trap cleanup EXIT

if [ "$NO_NOTARIZE" -eq 1 ]; then
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
else
    : "${SIGN_IDENTITY:?Set SIGN_IDENTITY to a Developer ID Application identity}"
    if ! security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
        echo "error: code-signing identity not found: $SIGN_IDENTITY" >&2
        exit 1
    fi
fi

VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" APP_PATH="$APP" SIGN_IDENTITY="$SIGN_IDENTITY" ./scripts/make-app.sh

rm -rf "$DIST"
mkdir -p "$DIST"
ditto "$APP" "$STAGE/Droplane.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "Droplane" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$DMG"
else
    DMG_SIGN_ERROR="$(mktemp "${TMPDIR:-/tmp}/droplane-dmg-codesign.XXXXXX")"
    signed=0
    for attempt in 1 2 3 4 5; do
        if codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG" 2>"$DMG_SIGN_ERROR"; then
            signed=1
            break
        fi
        if ! grep -q "timestamp service is not available" "$DMG_SIGN_ERROR"; then
            cat "$DMG_SIGN_ERROR" >&2
            exit 1
        fi
        echo "codesign timestamp service unavailable for the DMG; retrying ($attempt/5)" >&2
        sleep 3
    done
    if [ "$signed" -ne 1 ]; then
        cat "$DMG_SIGN_ERROR" >&2
        exit 1
    fi
    rm -f "$DMG_SIGN_ERROR"
fi

if [ "$NO_NOTARIZE" -eq 0 ]; then
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    elif [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${APPLE_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
        xcrun notarytool submit "$DMG" \
            --key "$NOTARY_KEY_PATH" \
            --key-id "$APPLE_KEY_ID" \
            --issuer "$ASC_ISSUER_ID" \
            --wait
    else
        echo "error: set NOTARY_PROFILE, or NOTARY_KEY_PATH plus APPLE_KEY_ID and ASC_ISSUER_ID" >&2
        exit 1
    fi
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
codesign --verify --deep --strict "$MOUNT/Droplane.app"
if [ "$NO_NOTARIZE" -eq 0 ]; then
    spctl -a -vvv -t exec "$MOUNT/Droplane.app"
fi
hdiutil detach "$MOUNT" -quiet
rm -rf "$MOUNT"

if [ "$NO_NOTARIZE" -eq 0 ]; then
    spctl -a -vvv -t open --context context:primary-signature "$DMG"
    spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | grep -Fq "Notarized Developer ID"
else
    echo "Skipped Gatekeeper and notary checks because --no-notarize was passed."
fi

echo "$DMG"
