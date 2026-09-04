#!/usr/bin/env bash
# Build YtDlpUI.app and ad-hoc code-sign it (no Apple Developer account needed).
#
#   ./scripts/build.sh                 # Release
#   ./scripts/build.sh Debug
#   YTDLPUI_VERSION=0.2.0 ./scripts/build.sh   # override CFBundleShortVersionString
#
# Needs Vendor/ populated first: ./scripts/fetch-tools.sh
# Result: .build/DerivedData/Build/Products/<config>/YtDlpUI.app
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="YtDlpUI"
CONFIG="${1:-Release}"
DERIVED="$PWD/.build/DerivedData"   # under .build/ so it stays out of git
APP="$DERIVED/Build/Products/$CONFIG/$SCHEME.app"

[ -f Vendor/seed.json ] || { echo "!! Vendor/ is empty — run ./scripts/fetch-tools.sh first"; exit 1; }

EXTRA_SETTINGS=(CODE_SIGN_IDENTITY="-")
[ -n "${YTDLPUI_VERSION:-}" ] && EXTRA_SETTINGS+=("MARKETING_VERSION=$YTDLPUI_VERSION")

xcodebuild \
  -project "$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  "${EXTRA_SETTINGS[@]}" \
  build

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=2 "$APP"

echo "==> Built: $APP"
