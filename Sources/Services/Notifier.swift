import Foundation
import UserNotifications
import AppKit

/// Local notifications for finished / failed downloads.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private var didRequestAuthorization = false

    private override init() {
        super.init()
        center.delegate = self
    }

    /// Ask once, lazily (first time the user starts a download).
    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { Log.app.error("notification auth: \(error.localizedDescription, privacy: .public)") }
            else { Log.app.info("notification auth granted=\(granted)") }
        }
    }

    func notify(_ job: DownloadJob) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch job.phase {
        case .completed:
            content.title = String(localized: "Download complete")
            content.body = job.displayName
            if let path = job.outputPath {
                content.userInfo = ["revealPath": path.path(percentEncoded: false)]
            }
        case .failed(let reason):
            let oneLine = reason.replacingOccurrences(of: "\n", with: " ")
            content.title = String(localized: "Download failed")
            content.body = "\(job.displayName)\n\(String(oneLine.prefix(160)))"
        default:
            return
        }

        center.add(UNNotificationRequest(identifier: job.id.uuidString, content: content, trigger: nil))
    }

    func notifyInfo(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // Show the banner even when the app is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Tapping a "complete" notification reveals the file.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let path = response.notification.request.content.userInfo["revealPath"] as? String else { return }
        let url = URL(fileURLWithPath: path)
        await MainActor.run {
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}
