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

# The ffmpeg build server can be slow; be patient but bounded.
CURL=(curl -fsSL --connect-timeout 20 --max-time 600 --retry 3 --retry-delay 3)

# ---------------------------------------------------------------- yt-dlp -------
echo "==> yt-dlp  (github.com/yt-dlp/yt-dlp, latest stable)"
"${CURL[@]}" -o "$TMP/yt-dlp_macos" \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
"${CURL[@]}" -o "$TMP/SHA2-256SUMS" \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS"

expected="$(awk '$2 == "yt-dlp_macos" { print $1 }' "$TMP/SHA2-256SUMS")"
actual="$(shasum -a 256 "$TMP/yt-dlp_macos" | awk '{ print $1 }')"
[ -n "$expected" ]            || { echo "!! no checksum listed for yt-dlp_macos"; exit 1; }
[ "$expected" = "$actual" ]   || { echo "!! yt-dlp checksum mismatch"; exit 1; }

chmod +x "$TMP/yt-dlp_macos"
ytdlp_version="$("$TMP/yt-dlp_macos" --version --ignore-config)"
echo "    verified, version $ytdlp_version"

# ------------------------------------------------------- ffmpeg + ffprobe -----
# ffprobe is required by yt-dlp's audio-extraction postprocessor (`-x`).
fetch_riedl() {  # $1 = ffmpeg | ffprobe  -> echoes "<version>"
  local name="$1"
  local final
  final="$("${CURL[@]}" -o "$TMP/$name.zip" -w '%{url_effective}' \
    "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/$name.zip")"
  "${CURL[@]}" -o "$TMP/$name.zip.sha256" "${final}.sha256"
  local expected actual
  expected="$(awk '{ print $1 }' "$TMP/$name.zip.sha256")"
  actual="$(shasum -a 256 "$TMP/$name.zip" | awk '{ print $1 }')"
  [ -n "$expected" ] && [ "$expected" = "$actual" ] || { echo "!! $name checksum mismatch" >&2; exit 1; }
  ( cd "$TMP" && unzip -oq "$name.zip" )
  chmod +x "$TMP/$name"
  "$TMP/$name" -version >/dev/null
  printf '%s' "$final" | sed -E "s#.*/arm64/[0-9]+_([^/]+)/$name\\.zip#\\1#"
}

echo "==> ffmpeg  (ffmpeg.martin-riedl.de, macOS arm64 release)"
ffmpeg_version="$(fetch_riedl ffmpeg)"
echo "    verified, version $ffmpeg_version"
echo "==> ffprobe"
ffprobe_version="$(fetch_riedl ffprobe)"
echo "    verified, version $ffprobe_version"

# ---------------------------------------------------------------- install -----
mv -f "$TMP/yt-dlp_macos" "$VENDOR/yt-dlp_macos"
mv -f "$TMP/ffmpeg"       "$VENDOR/ffmpeg"
mv -f "$TMP/ffprobe"      "$VENDOR/ffprobe"

sha()  { shasum -a 256 "$1" | awk '{ print $1 }'; }
size() { stat -f %z "$1"; }

cat > "$VENDOR/seed.json" <<JSON
{
  "fetchedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tools": {
    "yt-dlp_macos": { "version": "$ytdlp_version",  "sha256": "$(sha "$VENDOR/yt-dlp_macos")", "size": $(size "$VENDOR/yt-dlp_macos") },
    "ffmpeg":       { "version": "$ffmpeg_version",  "sha256": "$(sha "$VENDOR/ffmpeg")",       "size": $(size "$VENDOR/ffmpeg") },
    "ffprobe":      { "version": "$ffprobe_version", "sha256": "$(sha "$VENDOR/ffprobe")",      "size": $(size "$VENDOR/ffprobe") }
  }
}
JSON

echo "==> Vendor/ ready:"
ls -lh "$VENDOR"
cat "$VENDOR/seed.json"
