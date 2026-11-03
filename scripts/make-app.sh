#!/bin/bash
# Builds a local, ad-hoc signed Droplane.app for testing. Release signing/notarization is separate.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
swift build -c release
APP="${APP_PATH:-build/Droplane.app}"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Droplane "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ryabinskilabs.droplane</string>
<key>CFBundleName</key><string>Droplane</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>Droplane</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>com.ryabinskilabs.droplane.phone-item</string>
<key>UTTypeDescription</key><string>Droplane phone item</string>
<key>UTTypeConformsTo</key><array><string>public.data</string></array>
</dict></array>
</dict></plist>
PL
# Bundle libmtp + libusb (LGPL, dynamically linked) so the app runs without Homebrew.
FW="$APP/Contents/Frameworks"; mkdir -p "$FW"
MTP=$(brew --prefix libmtp)/lib/libmtp.9.dylib
USB=$(brew --prefix libusb)/lib/libusb-1.0.0.dylib
cp "$MTP" "$USB" "$FW/"; chmod u+w "$FW"/*.dylib
install_name_tool -id @rpath/libmtp.9.dylib "$FW/libmtp.9.dylib"
install_name_tool -id @rpath/libusb-1.0.0.dylib "$FW/libusb-1.0.0.dylib"
install_name_tool -change "$(otool -L "$FW/libmtp.9.dylib" | awk '/libusb/{print $1}')" @rpath/libusb-1.0.0.dylib "$FW/libmtp.9.dylib"
BIN="$APP/Contents/MacOS/Droplane"
install_name_tool -change "$(otool -L "$BIN" | awk '/libmtp/{print $1}')" @rpath/libmtp.9.dylib "$BIN"
install_name_tool -add_rpath @executable_path/../Frameworks "$BIN"

# Ad-hoc signatures carry no Team ID, so hardened runtime's library validation would reject
# the bundled dylibs. Local builds skip it; Developer ID builds (SIGN_IDENTITY set) keep it.
# LGPL notices: ship the license texts with the app.
RES="$APP/Contents/Resources"
[ -f Resources/AppIcon.icns ] || { echo "error: Resources/AppIcon.icns is missing; run ./scripts/make-icon.sh" >&2; exit 1; }
cp Resources/AppIcon.icns "$RES/AppIcon.icns"
cp LICENSE THIRD_PARTY_NOTICES.md "$RES/"
cp -R LICENSES "$RES/LICENSES"

IDENTITY="${SIGN_IDENTITY:--}"
RUNTIME=(); [ "$IDENTITY" != "-" ] && RUNTIME=(--options runtime --timestamp)
SIGN_ERROR="$(mktemp "${TMPDIR:-/tmp}/droplane-codesign.XXXXXX")"
trap 'rm -f "$SIGN_ERROR"' EXIT
sign() {
    for attempt in 1 2 3 4 5; do
        if codesign --force --sign "$IDENTITY" ${RUNTIME[@]+"${RUNTIME[@]}"} "$@" 2>"$SIGN_ERROR"; then
            return 0
        fi
        if ! grep -q "timestamp service is not available" "$SIGN_ERROR"; then
            cat "$SIGN_ERROR" >&2
            return 1
        fi
        echo "codesign timestamp service unavailable; retrying ($attempt/5)" >&2
        sleep 3
    done
    cat "$SIGN_ERROR" >&2
    return 1
}
sign "$FW"/*.dylib
sign "$APP"
echo "$APP"
