import Foundation
import Observation

/// Keeps `yt-dlp` current: a check on launch (if a day has passed and nothing is
/// downloading), an hourly "is it due yet?" tick, and a manual "Check now".
/// `ffmpeg`/`ffprobe` are not touched here — they move only with an app update.
@MainActor
@Observable
final class UpdateScheduler {

    private let tools: ToolManager
    private let downloads: DownloadManager

    /// Provides the current channel setting (wired up by `AppState`).
    var channelProvider: () -> YtDlpChannel = { .stable }

    private let checkInterval: TimeInterval = 24 * 60 * 60
    private let tickInterval: TimeInterval = 60 * 60
    private static let lastCheckKey = "YtDlpUI.lastUpdateCheck"

    private(set) var isChecking = false
    private(set) var lastCheck: Date?
    private(set) var statusMessage: String?

    private var timer: Timer?

    init(tools: ToolManager, downloads: DownloadManager) {
        self.tools = tools
        self.downloads = downloads
        self.lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    }

    func start() {
        Task { await runIfDue() }
        let timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runIfDue() }
        }
        timer.tolerance = 5 * 60
        self.timer = timer
    }

    /// User-triggered.
    func checkNow() async {
        await check(force: true)
    }

    // MARK: -

    private func runIfDue() async {
        guard tools.state == .ready, !downloads.hasActiveDownloads else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < checkInterval { return }
        await check(force: false)
    }

    private func check(force: Bool) async {
        // No `await` between here and setting the flags — MainActor makes this
        // section atomic, so no download can slip in.
        guard !isChecking else { return }
        guard tools.state == .ready else {
            if force { statusMessage = String(localized: "Tools aren’t ready yet.") }
            return
        }
        if downloads.hasActiveDownloads {
            if force { statusMessage = String(localized: "Can’t update while a download is running.") }
            return
        }

        isChecking = true
        downloads.isBlockedForToolUpdate = true
        defer {
            isChecking = false
            downloads.isBlockedForToolUpdate = false
        }

        let channel = channelProvider()
        Log.tools.info("update check (force=\(force), channel=\(channel.rawValue, privacy: .public))")

        let outcome = await tools.updateYtDlp(channel: channel)

        lastCheck = Date()
        UserDefaults.standard.set(lastCheck, forKey: Self.lastCheckKey)

        switch outcome {
        case .upToDate(let version):
            statusMessage = String(localized: "yt-dlp is up to date (\(version)).")
        case .updated(_, let newVersion):
            statusMessage = String(localized: "Updated yt-dlp to \(newVersion).")
            Notifier.shared.notifyInfo(title: String(localized: "yt-dlp updated"), body: String(localized: "Now on version \(newVersion)."))
        case .failed(let reason):
            statusMessage = String(localized: "Update check failed: \(reason)")
        }
        Log.tools.info("update result: \(self.statusMessage ?? "", privacy: .public)")
    }

    var lastCheckText: String {
        guard let lastCheck else { return String(localized: "Never checked") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return String(localized: "Checked \(formatter.localizedString(for: lastCheck, relativeTo: Date()))")
    }
}
