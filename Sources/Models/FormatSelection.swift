import Foundation

enum MediaKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case video, audio
    var id: String { rawValue }
    var label: String {
        self == .video ? String(localized: "Video") : String(localized: "Audio")
    }
}

enum VideoQuality: String, CaseIterable, Codable, Sendable, Identifiable {
    case best, p2160, p1440, p1080, p720, p480
    var id: String { rawValue }

    var label: String {
        switch self {
        case .best: return String(localized: "Best")
        case .p2160: return "4K"
        case .p1440: return "1440p"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        }
    }

    /// nil means "no cap — take the best available".
    var maxHeight: Int? {
        switch self {
        case .best: return nil
        case .p2160: return 2160
        case .p1440: return 1440
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        }
    }
}

/// Output container for video downloads (the "advanced output format" knob).
enum VideoContainer: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto, mp4, mkv, webm
    var id: String { rawValue }
    var label: String { self == .auto ? String(localized: "Auto") : rawValue.uppercased() }
}

enum AudioFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case mp3, m4a, opus, flac, wav
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

/// The complete "what to download" choice. `kind` is the primary switch; the
/// rest are per-mode details with sensible defaults.
struct FormatSelection: Codable, Sendable, Equatable {
    var kind: MediaKind = .video
    var videoQuality: VideoQuality = .best
    var videoContainer: VideoContainer = .mp4
    var audioFormat: AudioFormat = .mp3

    /// Short human summary for the UI, e.g. "1080p · MP4" or "MP3".
    var summary: String {
        switch kind {
        case .video: return "\(videoQuality.label) · \(videoContainer.label)"
        case .audio: return audioFormat.label
        }
    }

    var ytDlpArguments: [String] {
        switch kind {
        case .video:
            var args: [String]
            if let height = videoQuality.maxHeight {
                args = ["-f", "bv*[height<=\(height)]+ba/b[height<=\(height)]/bv*+ba/b"]
            } else {
                args = ["-f", "bv*+ba/b"]
            }
            switch videoContainer {
            case .auto:
                break
            case .mp4, .mkv, .webm:
                // --merge-output-format covers the video+audio merge case;
                // --remux-video forces the container for an already-muxed single file.
                args += [
                    "--merge-output-format", videoContainer.rawValue,
                    "--remux-video", videoContainer.rawValue,
                ]
            }
            return args

        case .audio:
            return ["-x", "--audio-format", audioFormat.rawValue, "--audio-quality", "0"]
        }
    }
}
