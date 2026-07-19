#!/bin/bash
# Packages dist/Macscout.app into dist/Macscout-<version>.dmg (drag-to-install).
# Builds are ad-hoc signed for now; when a Developer ID is available, sign the
# app with hardened runtime and notarize the DMG before publishing:
#   codesign --force --deep --options runtime --timestamp \
#            --sign "Developer ID Application: <name> (<team>)" dist/Macscout.app
#   xcrun notarytool submit "$DMG" --keychain-profile macscout --wait
#   xcrun stapler staple "$DMG"
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    Sources/Macscout/Resources/Info.plist)

./scripts/build.sh

STAGING=$(mktemp -d)
trap 'rm -rf "${STAGING}"' EXIT
cp -R "dist/Macscout.app" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

DMG="dist/Macscout-${VERSION}.dmg"
rm -f "${DMG}"
hdiutil create -volname "Macscout ${VERSION}" -srcfolder "${STAGING}" \
    -ov -format UDZO "${DMG}"

echo "==> ${DMG}"
