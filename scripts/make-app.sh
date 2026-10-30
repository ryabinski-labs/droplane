#!/bin/bash
# Builds a local, ad-hoc signed Droplane.app for testing. Release signing/notarization is separate.
set -euo pipefail
cd "$(dirname "$0")/.."
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
<key>CFBundleExecutable</key><string>Droplane</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
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
cp LICENSE THIRD_PARTY_NOTICES.md "$RES/"
cp -R LICENSES "$RES/LICENSES"

IDENTITY="${SIGN_IDENTITY:--}"
RUNTIME=(); [ "$IDENTITY" != "-" ] && RUNTIME=(--options runtime --timestamp)
codesign --force --sign "$IDENTITY" ${RUNTIME[@]+"${RUNTIME[@]}"} "$FW"/*.dylib
codesign --force --sign "$IDENTITY" ${RUNTIME[@]+"${RUNTIME[@]}"} "$APP"
echo "$APP"
