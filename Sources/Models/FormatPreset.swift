import Foundation

/// A user-facing download quality/format choice, mapped to yt-dlp arguments.
enum FormatPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case best
    case p1080
    case p720
    case audioM4A
    case audioMP3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .best: return "Best quality"
        case .p1080: return "1080p max"
        case .p720: return "720p max"
        case .audioM4A: return "Audio only (M4A)"
        case .audioMP3: return "Audio only (MP3)"
        }
    }

    /// yt-dlp arguments for this preset. Consumed by `ArgBuilder` from M2 onward.
    var arguments: [String] {
        switch self {
        case .best:
            return ["-f", "bv*+ba/b", "--merge-output-format", "mp4"]
        case .p1080:
            return ["-f", "bv*[height<=1080]+ba/b[height<=1080]", "--merge-output-format", "mp4"]
        case .p720:
            return ["-f", "bv*[height<=720]+ba/b[height<=720]", "--merge-output-format", "mp4"]
        case .audioM4A:
            return ["-x", "--audio-format", "m4a", "--audio-quality", "0"]
        case .audioMP3:
            return ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        }
    }
}
