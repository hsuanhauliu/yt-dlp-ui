#!/usr/bin/env bash
# Package a built .app into a drag-to-Applications .dmg.
#
#   ./scripts/make-dmg.sh <path/to/YtDlpUI.app> [output.dmg]
set -euo pipefail

APP="${1:?usage: make-dmg.sh <YtDlpUI.app> [out.dmg]}"
OUT="${2:-YtDlpUI.dmg}"
VOLNAME="yt-dlp UI"

[ -d "$APP" ] || { echo "!! not found: $APP"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -format UDZO \
  -ov \
  "$OUT" >/dev/null

echo "==> $OUT  ($(du -h "$OUT" | cut -f1))"
