#!/usr/bin/env bash
# Build YtDlpUI.app and ad-hoc code-sign it (no Apple Developer account needed).
#
#   ./scripts/build.sh            # Release
#   ./scripts/build.sh Debug
#
# Result: build/Build/Products/<config>/YtDlpUI.app
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="YtDlpUI"
CONFIG="${1:-Release}"
DERIVED="$PWD/.build/DerivedData"   # under .build/ so it stays out of git
APP="$DERIVED/Build/Products/$CONFIG/$SCHEME.app"

xcodebuild \
  -project "$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  build

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=2 "$APP"

echo "==> Built: $APP"
