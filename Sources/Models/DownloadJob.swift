import Foundation
import Observation

@MainActor
@Observable
final class DownloadJob: Identifiable {
    enum Phase: Equatable, Sendable {
        case queued
        case running
        case postProcessing
        case completed
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let request: DownloadRequest
    let createdAt = Date()

    var title: String?
    var phase: Phase = .queued
    var progress = DownloadProgress()
    /// During the download this points into the staging dir; once complete it is
    /// the file's real location.
    var outputPath: URL?

    init(request: DownloadRequest) {
        self.request = request
    }

    var displayName: String {
        title ?? request.url
    }

    var isActive: Bool {
        switch phase {
        case .queued, .running, .postProcessing: return true
        case .completed, .failed, .cancelled: return false
        }
    }

    var isFinished: Bool { !isActive }
}
