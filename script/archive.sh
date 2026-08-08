#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/VibingSpeech.xcodeproj"
SCHEME="VibingSpeech"
CONFIGURATION="Release"
APP_NAME="VibingSpeech"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
APP_ENTITLEMENTS="$ROOT_DIR/VibingSpeech/Resources/VibingSpeech.entitlements"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$APP_PATH"

# Archive for Apple Silicon only.
# Pass ARCHS=arm64 to Swift package builds.
# Archive unsigned here; signing is done in the steps below.
/usr/bin/xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  EXCLUDED_ARCHS=x86_64 \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$APP_PATH"

# Strip any existing partial signatures (ignore if none exist)
find "$APP_PATH" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 \
  | xargs -0 -I{} /usr/bin/codesign --remove-signature "{}" 2>/dev/null || true
find "$APP_PATH" -type d -name "*.framework" -print0 \
  | xargs -0 -I{} /usr/bin/codesign --remove-signature "{}" 2>/dev/null || true
/usr/bin/codesign --remove-signature "$APP_PATH" 2>/dev/null || true

# Sign from the inside out with ad-hoc + Hardened Runtime. Do not use --deep.

# 1) dylib / .so
find "$APP_PATH" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 \
  | while IFS= read -r -d '' f; do
      /usr/bin/codesign --force --options runtime --timestamp=none --sign - "$f"
    done

# 2) .framework
find "$APP_PATH" -type d -name "*.framework" -print0 \
  | while IFS= read -r -d '' fw; do
      /usr/bin/codesign --force --options runtime --timestamp=none --sign - "$fw"
    done

# 3) XPC / appex if present
find "$APP_PATH/Contents" -type d \( -name "*.xpc" -o -name "*.appex" \) -print0 \
  | while IFS= read -r -d '' b; do
      /usr/bin/codesign --force --options runtime --timestamp=none --sign - "$b"
    done

# 4) App bundle itself (last)
/usr/bin/codesign --force --options runtime --timestamp=none \
  --entitlements "$APP_ENTITLEMENTS" --sign - "$APP_PATH"

# Verify
/usr/bin/codesign --verify --strict --verbose=2 "$APP_PATH"

# Confirm Hardened Runtime flag is present (should show adhoc,runtime)
if ! /usr/bin/codesign -dvv "$APP_PATH" 2>&1 | grep "flags=.*runtime" >/dev/null; then
  echo "ERROR: Hardened Runtime flag not present on $APP_PATH" >&2
  exit 1
fi

# Strip quarantine for manual distribution (optional)
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo "Build complete: $APP_PATH"
