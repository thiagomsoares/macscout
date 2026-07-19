#!/bin/bash
# Builds dist/Macscout.app: release build, bundle assembly, ad-hoc signing.
# Works with Command Line Tools only (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Macscout"
BUNDLE="dist/${APP_NAME}.app"
BINARY_NAME="Macscout"

echo "==> Building ${BINARY_NAME} (release)"
# Try a universal (arm64 + x86_64) build first; fall back to the host arch.
if swift build -c release --product "${BINARY_NAME}" --arch arm64 --arch x86_64 2>/dev/null; then
    echo "==> Universal build succeeded"
else
    echo "==> Universal build unavailable, falling back to host architecture"
    swift build -c release --product "${BINARY_NAME}"
fi

BIN_DIR=$(swift build -c release --product "${BINARY_NAME}" --show-bin-path)
BINARY="${BIN_DIR}/${BINARY_NAME}"
if [[ ! -x "${BINARY}" ]]; then
    echo "error: release binary not found at ${BINARY}" >&2
    exit 1
fi

echo "==> Assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "${BINARY}" "${BUNDLE}/Contents/MacOS/${BINARY_NAME}"
cp "Sources/Macscout/Resources/Info.plist" "${BUNDLE}/Contents/Info.plist"
cp "Sources/Macscout/Resources/AppIcon.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns"
cp -R "Sources/Macscout/Resources/Fonts" "${BUNDLE}/Contents/Resources/Fonts"
# Localizations (Localizable.strings per language).
for lproj in Sources/Macscout/Resources/*.lproj; do
    [ -d "${lproj}" ] && cp -R "${lproj}" "${BUNDLE}/Contents/Resources/"
done

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "${BUNDLE}"

echo "==> Verifying"
codesign --verify --verbose=1 "${BUNDLE}"
file "${BUNDLE}/Contents/MacOS/${BINARY_NAME}"

echo "==> Done: ${BUNDLE}"
