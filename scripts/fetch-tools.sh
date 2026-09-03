#!/usr/bin/env bash
# Download the bundled tool seeds into ./Vendor/. These are copied into the .app
# at build time and seeded into Application Support on first launch.
#
# Vendor/ is git-ignored; run this once after cloning, and again to refresh the
# seeds before cutting a release.
set -euo pipefail
cd "$(dirname "$0")/.."

VENDOR="$PWD/Vendor"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$VENDOR"

# ---------------------------------------------------------------- yt-dlp -------
echo "==> yt-dlp  (github.com/yt-dlp/yt-dlp, latest stable)"
curl -fsSL -o "$TMP/yt-dlp_macos" \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
curl -fsSL -o "$TMP/SHA2-256SUMS" \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS"

expected="$(awk '$2 == "yt-dlp_macos" { print $1 }' "$TMP/SHA2-256SUMS")"
actual="$(shasum -a 256 "$TMP/yt-dlp_macos" | awk '{ print $1 }')"
[ -n "$expected" ]            || { echo "!! no checksum listed for yt-dlp_macos"; exit 1; }
[ "$expected" = "$actual" ]   || { echo "!! yt-dlp checksum mismatch"; exit 1; }

chmod +x "$TMP/yt-dlp_macos"
ytdlp_version="$("$TMP/yt-dlp_macos" --version --ignore-config)"
echo "    verified, version $ytdlp_version"

# ---------------------------------------------------------------- ffmpeg -------
echo "==> ffmpeg  (ffmpeg.martin-riedl.de, macOS arm64 release)"
final="$(curl -fsSL -o "$TMP/ffmpeg.zip" -w '%{url_effective}' \
  "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip")"
curl -fsSL -o "$TMP/ffmpeg.zip.sha256" "${final}.sha256"

expected="$(awk '{ print $1 }' "$TMP/ffmpeg.zip.sha256")"
actual="$(shasum -a 256 "$TMP/ffmpeg.zip" | awk '{ print $1 }')"
[ -n "$expected" ]          || { echo "!! no checksum for ffmpeg.zip"; exit 1; }
[ "$expected" = "$actual" ] || { echo "!! ffmpeg checksum mismatch"; exit 1; }

# .../arm64/<timestamp>_<version>/ffmpeg.zip  ->  <version>
ffmpeg_version="$(printf '%s' "$final" | sed -E 's#.*/arm64/[0-9]+_([^/]+)/ffmpeg\.zip#\1#')"
( cd "$TMP" && unzip -oq ffmpeg.zip )
chmod +x "$TMP/ffmpeg"
"$TMP/ffmpeg" -version >/dev/null
echo "    verified, version $ffmpeg_version"

# ---------------------------------------------------------------- install -----
mv -f "$TMP/yt-dlp_macos" "$VENDOR/yt-dlp_macos"
mv -f "$TMP/ffmpeg"       "$VENDOR/ffmpeg"

ytdlp_sha="$(shasum -a 256 "$VENDOR/yt-dlp_macos" | awk '{ print $1 }')"
ytdlp_size="$(stat -f %z "$VENDOR/yt-dlp_macos")"
ffmpeg_sha="$(shasum -a 256 "$VENDOR/ffmpeg" | awk '{ print $1 }')"
ffmpeg_size="$(stat -f %z "$VENDOR/ffmpeg")"

cat > "$VENDOR/seed.json" <<JSON
{
  "fetchedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tools": {
    "yt-dlp_macos": { "version": "$ytdlp_version", "sha256": "$ytdlp_sha", "size": $ytdlp_size },
    "ffmpeg":       { "version": "$ffmpeg_version", "sha256": "$ffmpeg_sha", "size": $ffmpeg_size }
  }
}
JSON

echo "==> Vendor/ ready:"
ls -lh "$VENDOR"
cat "$VENDOR/seed.json"
