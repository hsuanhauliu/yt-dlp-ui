import Foundation

/// Builds the yt-dlp argument list for a `DownloadRequest`.
///
/// Every invocation is hermetic: `--ignore-config` (no `~/.config/yt-dlp`), our
/// own `--ffmpeg-location` and `--cache-dir`, never the PATH.
enum ArgBuilder {

    /// Sentinels prefixed onto machine-readable output lines so `ProgressParser`
    /// can pick them out of yt-dlp's normal chatter.
    static let progressSentinel = "@@YTUI-PROGRESS@@"
    static let titleSentinel = "@@YTUI-TITLE@@"
    static let pathSentinel = "@@YTUI-PATH@@"

    static func build(
        _ request: DownloadRequest,
        toolsDirectory: URL,
        cacheDirectory: URL,
        outputDirectory: URL
    ) -> [String] {
        var args: [String] = [
            "--ignore-config",
            "--no-colors",
            "--newline",
            "--no-simulate",              // --print otherwise implies --simulate
            "--progress",                 // ...and --print implies --quiet, which hides progress
            "--no-playlist",              // a pasted watch URL shouldn't grab the whole list (M2)
            "--cache-dir", cacheDirectory.path(percentEncoded: false),
            "--ffmpeg-location", toolsDirectory.path(percentEncoded: false),
            // yt-dlp writes into a private per-job staging dir; DownloadManager
            // moves the finished file to the real destination, giving it a
            // unique name if one is already there.
            "--paths", "home:" + outputDirectory.path(percentEncoded: false),
            "-o", "%(title).200B [%(id)s].%(ext)s",
            "--progress-template",
            "download:\(progressSentinel)\t"
                + "%(progress.downloaded_bytes)s\t"
                + "%(progress.total_bytes)s\t"
                + "%(progress.total_bytes_estimate)s\t"
                + "%(progress.speed)s\t"
                + "%(progress.eta)s",
            "--print", "video:\(titleSentinel) %(title)s",
            "--print", "after_move:\(pathSentinel) %(filepath)s",
        ]

        args += request.selection.ytDlpArguments
        args.append(request.url)
        return args
    }
}
