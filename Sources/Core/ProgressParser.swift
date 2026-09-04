import Foundation

enum ProgressEvent: Sendable, Equatable {
    case progress(DownloadProgress)
    case title(String)
    case outputPath(URL)
    case postProcessing
    case alreadyDownloaded
}

/// Stateless: turns one line of yt-dlp stdout into a `ProgressEvent`, or `nil`.
enum ProgressParser {

    static func parse(_ rawLine: String) -> ProgressEvent? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }

        if line.hasPrefix(ArgBuilder.progressSentinel) {
            return parseProgress(line.dropFirst(ArgBuilder.progressSentinel.count))
        }
        if line.hasPrefix(ArgBuilder.titleSentinel) {
            let title = line.dropFirst(ArgBuilder.titleSentinel.count).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : .title(title)
        }
        if line.hasPrefix(ArgBuilder.pathSentinel) {
            let path = line.dropFirst(ArgBuilder.pathSentinel.count).trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? nil : .outputPath(URL(fileURLWithPath: path))
        }
        if line.range(of: #"has already been downloaded"#, options: .caseInsensitive) != nil {
            return .alreadyDownloaded
        }
        if isPostProcessorLine(line) {
            return .postProcessing
        }
        return nil
    }

    // MARK: -

    private static func parseProgress(_ payload: Substring) -> ProgressEvent? {
        // The sentinel is followed by a tab, so the first split field is empty —
        // omit empties. yt-dlp emits "NA" (not "") for missing values, so this
        // does not misalign the columns.
        let fields = payload
            .split(separator: "\t", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 5 else { return nil }

        let downloaded = number(fields[0]).map { Int64($0) }
        let total = number(fields[1]).map { Int64($0) } ?? number(fields[2]).map { Int64($0) }
        let speed = number(fields[3])
        let eta = number(fields[4]).map { Int($0) }

        var progress = DownloadProgress(
            downloadedBytes: downloaded,
            totalBytes: total,
            speedBytesPerSecond: speed,
            etaSeconds: eta,
            fraction: nil
        )
        if let downloaded, let total, total > 0 {
            progress.fraction = min(1, max(0, Double(downloaded) / Double(total)))
        }
        return .progress(progress)
    }

    /// yt-dlp prints `NA` (sometimes `None`) for missing numeric fields.
    private static func number(_ string: String) -> Double? {
        switch string {
        case "", "NA", "N/A", "None", "none": return nil
        default: return Double(string)
        }
    }

    private static let postProcessorTags = [
        "[Merger]", "[ExtractAudio]", "[VideoConvertor]", "[VideoRemuxer]",
        "[Metadata]", "[EmbedThumbnail]", "[EmbedSubtitle]", "[ThumbnailsConvertor]",
        "[SplitChapters]", "[SponsorBlock]", "[Fixup",
    ]

    private static func isPostProcessorLine(_ line: String) -> Bool {
        postProcessorTags.contains { line.hasPrefix($0) }
    }
}
