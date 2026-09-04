import Foundation

/// A snapshot of a running download's progress.
struct DownloadProgress: Sendable, Equatable {
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var speedBytesPerSecond: Double?
    var etaSeconds: Int?
    /// 0...1 when known.
    var fraction: Double?

    var percentText: String? {
        guard let fraction else { return nil }
        return "\(Int((fraction * 100).rounded()))%"
    }

    var speedText: String? {
        guard let speed = speedBytesPerSecond, speed > 0 else { return nil }
        return Int64(speed).formatted(.byteCount(style: .file)) + "/s"
    }

    var etaText: String? {
        guard let eta = etaSeconds, eta >= 0 else { return nil }
        let minutes = eta / 60
        let seconds = eta % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var sizeText: String? {
        guard let total = totalBytes, total > 0 else { return nil }
        return total.formatted(.byteCount(style: .file))
    }
}
