#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AIWebUsageMonitor.xcodeproj"
SCHEME="AIWebUsageMonitor"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="$ROOT_DIR/.build/xcode-derived-data"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build >&2

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/AIWebUsageMonitor.app"
BUNDLE_IDENTIFIER="$(defaults read "$APP_PATH/Contents/Info" CFBundleIdentifier)"

codesign \
  --force \
  --deep \
  --sign - \
  --identifier "$BUNDLE_IDENTIFIER" \
  "$APP_PATH" >&2

echo "$APP_PATH"
