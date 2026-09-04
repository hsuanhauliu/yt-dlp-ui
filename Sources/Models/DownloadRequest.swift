import Foundation

/// A single "download this URL" instruction. Immutable once created.
struct DownloadRequest: Sendable, Equatable {
    var url: String
    var selection: FormatSelection
    var destinationDirectory: URL
}
