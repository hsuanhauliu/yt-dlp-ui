import Foundation
import Observation
import ServiceManagement
import AppKit

/// App-wide state. Settings persist in `UserDefaults` (via `SettingsStore`);
/// the download queue is in-memory and cleared on quit.
@MainActor
@Observable
final class AppState {

    @ObservationIgnored private var store: SettingsStore { SettingsStore() }

    // MARK: Settings (persisted)

    var defaultSelection: FormatSelection {
        didSet { store.format = defaultSelection }
    }

    var downloadDirectory: URL {
        didSet { store.downloadDirectory = downloadDirectory }
    }

    var notificationsEnabled: Bool {
        didSet { store.notificationsEnabled = notificationsEnabled }
    }

    var ytDlpChannel: YtDlpChannel {
        didSet { store.ytDlpChannel = ytDlpChannel }
    }

    var appLanguage: AppLanguage = .current {
        didSet {
            guard appLanguage != oldValue else { return }
            appLanguage.persist()
            languageChangePending = true
        }
    }

    /// True once the language was changed this session (needs a relaunch).
    private(set) var languageChangePending = false

    // MARK: Managed tools & downloads

    let tools: ToolManager
    let downloads: DownloadManager
    let updates: UpdateScheduler

    // MARK: Transient UI

    var lastError: String?

    // MARK: Derived

    private var activeDownloadCount: Int {
        downloads.jobs.filter(\.isActive).count
    }

    /// Menu-bar icon, reflecting download activity.
    var menuBarSymbol: String {
        activeDownloadCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle"
    }

    /// Optional text shown next to the icon — the count of active downloads.
    var menuBarText: String {
        activeDownloadCount > 0 ? "\(activeDownloadCount)" : ""
    }

    func requestNotificationPermissionIfNeeded() {
        guard notificationsEnabled else { return }
        Notifier.shared.requestAuthorizationIfNeeded()
    }

    /// Quit and start a fresh instance (used to apply a language change).
    func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: Launch at login

    @ObservationIgnored private var isSyncingLoginItem = false

    var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLoginItem else { return }
            isSyncingLoginItem = true
            defer { isSyncingLoginItem = false }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                lastError = String(localized: "Couldn’t update Launch at Login: \(error.localizedDescription)")
                launchAtLogin = oldValue
            }
        }
    }

    init() {
        let store = SettingsStore()
        self.defaultSelection = store.format
        self.downloadDirectory = store.downloadDirectory
        self.notificationsEnabled = store.notificationsEnabled
        self.ytDlpChannel = store.ytDlpChannel

        let tools = ToolManager()
        let downloads = DownloadManager(tools: tools)
        let updates = UpdateScheduler(tools: tools, downloads: downloads)
        self.tools = tools
        self.downloads = downloads
        self.updates = updates
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        downloads.onJobFinished = { [weak self] job in
            guard self?.notificationsEnabled == true else { return }
            Notifier.shared.notify(job)
        }
        updates.channelProvider = { [weak self] in self?.ytDlpChannel ?? .stable }

        Task {
            await tools.bootstrap()
            updates.start()
        }
    }

    /// Where the app manages its private copies of yt-dlp / ffmpeg.
    static var applicationSupportDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("YtDlpUI", isDirectory: true)
    }
}
