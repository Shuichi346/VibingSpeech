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

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$APP_PATH"

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
/usr/bin/codesign --force --deep --sign - "$APP_PATH"

echo "Build complete: $APP_PATH"

