import Foundation
import os

/// Unified-logging categories. View with:
///   log stream --predicate 'subsystem == "com.howardliu.yt-dlp-ui"'
enum Log {
    private static let subsystem = "com.howardliu.yt-dlp-ui"

    static let tools = Logger(subsystem: subsystem, category: "tools")
    static let process = Logger(subsystem: subsystem, category: "process")
    static let downloads = Logger(subsystem: subsystem, category: "downloads")
    static let app = Logger(subsystem: subsystem, category: "app")
}
