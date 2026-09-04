# yt-dlp UI

A minimal macOS **menu-bar** front-end for [yt-dlp](https://github.com/yt-dlp/yt-dlp).
Paste a link, pick video or audio, download. No Dock icon, no window — just a
dropdown from the menu bar.

The app carries its **own private copies** of `yt-dlp`, `ffmpeg` and `ffprobe`
in `~/Library/Application Support/YtDlpUI/` — it never touches a Homebrew /
system install or your `~/.config/yt-dlp`. `yt-dlp` updates itself
automatically.

- **Apple Silicon only**, macOS 14+
- Video (MP4 / MKV / WebM, up to 4K) or audio (MP3 / M4A / Opus / FLAC / WAV)
- Live progress, cancel, retry, reveal-in-Finder, completion notifications
- Never overwrites an existing file — re-downloads get ` (2)`, ` (3)`, …
- English and 繁體中文（台灣）

---

## Install

Download the latest `YtDlpUI-*-arm64.dmg` from
[**Releases**](../../releases/latest), open it, and drag **YtDlpUI.app** to
**Applications**.

The app is **ad-hoc signed, not notarized**, so on first launch macOS says it
"cannot be opened". Fix it once, either way:

```bash
xattr -dr com.apple.quarantine /Applications/YtDlpUI.app
```

…or right-click **YtDlpUI.app** in Finder → **Open** → **Open**.

Then click the ⬇︎ icon in the menu bar. First launch takes ~10 s while it sets
up the bundled tools.

## Using it

- **Paste a URL** (it auto-fills from the clipboard) and press ↩︎ or the ⬇︎ button.
- Toggle **Video / Audio** and pick a quality / format next to it.
- **Settings** (from the panel):
  - *General* — default format, download folder, notifications, launch at login,
    **language**.
  - *Tools* — bundled `yt-dlp` / `ffmpeg` versions, update **channel**
    (stable / nightly), "Check for yt-dlp Update", "Reinstall Tools".

`yt-dlp` is checked for updates about once a day (and won't update mid-download).
`ffmpeg` / `ffprobe` are pinned and only change when you install a new app
version.

## Build from source

Requires Xcode 16 or later.

```bash
git clone https://github.com/hsuanhauliu/yt-dlp-ui.git
cd yt-dlp-ui
./scripts/fetch-tools.sh          # downloads yt-dlp + ffmpeg/ffprobe into Vendor/ (~160 MB, git-ignored)
./scripts/build.sh                # → .build/DerivedData/Build/Products/Release/YtDlpUI.app
```

Or open `YtDlpUI.xcodeproj` in Xcode and press ⌘R (run `fetch-tools.sh` once first).

| Script | |
|---|---|
| `scripts/fetch-tools.sh` | Download + checksum-verify the bundled tools into `Vendor/` |
| `scripts/build.sh [Debug\|Release]` | `xcodebuild` + ad-hoc codesign |
| `scripts/make-dmg.sh <app> [out.dmg]` | Package a built `.app` into a drag-to-Applications `.dmg` |
| `scripts/make-icon.swift` | Regenerate the app icon (`swift scripts/make-icon.swift`) |

### Releasing

Push a `v*` tag — [`.github/workflows/release.yml`](.github/workflows/release.yml)
builds, tests, packages the DMG and creates a GitHub Release:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

## Notes

- **Not on the Mac App Store** and not sandboxed — it runs downloaded
  executables, which the sandbox forbids. Fine for personal use.
- No telemetry. Outbound connections: the video host (yt-dlp), `github.com`
  (yt-dlp updates), the Sparkle-style feed is **not** used — the app itself has
  no auto-updater yet.
- `--recode-video` (transcoding) and playlists-as-first-class are intentionally
  out of scope.

## License

MIT — see [LICENSE](LICENSE). yt-dlp, ffmpeg and ffprobe are bundled under their
own licenses.
