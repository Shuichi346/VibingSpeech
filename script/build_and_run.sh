#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/VibingSpeech.xcodeproj"
SCHEME="VibingSpeech"
CONFIGURATION="Debug"
APP_NAME="VibingSpeech"
DERIVED_DATA="$ROOT_DIR/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

MODE="run"

for arg in "$@"; do
  case "$arg" in
    --debug|debug) MODE="debug" ;;
    --logs|logs) MODE="logs" ;;
    --telemetry|telemetry) MODE="telemetry" ;;
    --verify|verify) MODE="verify" ;;
    run) MODE="run" ;;
    *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
  esac
done

/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true

/usr/bin/xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

open_app() {
  /usr/bin/open -n "$APP_PATH"
}

case "$MODE" in
  run)
    open_app
    ;;
  debug)
    /usr/bin/lldb -- "$APP_PATH/Contents/MacOS/$APP_NAME"
    ;;
  logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"com.shuichi.VibingSpeech\""
    ;;
  verify)
    open_app
    for _ in {1..20}; do
      if /usr/bin/pgrep -x "$APP_NAME" >/dev/null; then
        echo "$APP_NAME is running"
        exit 0
      fi
      sleep 0.25
    done
    echo "$APP_NAME did not start" >&2
    exit 1
    ;;
esac
