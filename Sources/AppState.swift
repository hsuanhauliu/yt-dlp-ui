import Foundation
import Observation
import ServiceManagement
import AppKit

/// App-wide state. In M0 the settings live in memory only; persistence and the
/// download queue arrive in later milestones.
@MainActor
@Observable
final class AppState {

    // MARK: Settings

    var defaultSelection = FormatSelection()

    var downloadDirectory: URL = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }()

    var notificationsEnabled: Bool = true
    var ytDlpChannel: YtDlpChannel = .stable

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

        #if DEBUG
        if let spec = ProcessInfo.processInfo.environment["YTDLPUI_DEBUG_UPDATE"] {
            Task {
                while tools.state != .ready { try? await Task.sleep(for: .milliseconds(200)) }
                if spec.contains("@") {
                    let outcome = await tools.updateYtDlp(target: spec)
                    FileHandle.standardError.write(Data("DEBUGUPDATE \(outcome)\n".utf8))
                } else {
                    await updates.checkNow()
                    FileHandle.standardError.write(Data("DEBUGUPDATE \(updates.statusMessage ?? "-")\n".utf8))
                }
            }
        }
        #endif

        #if DEBUG
        if let debugURL = ProcessInfo.processInfo.environment["YTDLPUI_DEBUG_DOWNLOAD"] {
            var selection = FormatSelection()
            switch ProcessInfo.processInfo.environment["YTDLPUI_DEBUG_FORMAT"] {
            case "audio", "mp3": selection.kind = .audio
            case "m4a": selection.kind = .audio; selection.audioFormat = .m4a
            case "mkv": selection.videoContainer = .mkv
            case "webm": selection.videoContainer = .webm
            case "720": selection.videoQuality = .p720
            default: break
            }
            let downloads = self.downloads
            let directory = ProcessInfo.processInfo.environment["YTDLPUI_DEBUG_DIR"]
                .map { URL(fileURLWithPath: $0) } ?? self.downloadDirectory
            Task {
                while tools.state != .ready { try? await Task.sleep(for: .milliseconds(200)) }
                downloads.enqueue(DownloadRequest(url: debugURL, selection: selection, destinationDirectory: directory))
                guard let job = downloads.jobs.first else { return }
                if let cancelAfter = ProcessInfo.processInfo.environment["YTDLPUI_DEBUG_CANCEL_AFTER"].flatMap(Double.init) {
                    Task {
                        try? await Task.sleep(for: .seconds(cancelAfter))
                        downloads.cancel(job)
                    }
                }
                var lastLine = ""
                while job.isActive {
                    let line = "phase=\(job.phase) title=\(job.title ?? "-") pct=\(job.progress.percentText ?? "-") path=\(job.outputPath?.lastPathComponent ?? "-")"
                    if line != lastLine { FileHandle.standardError.write(Data(("DEBUGJOB " + line + "\n").utf8)); lastLine = line }
                    try? await Task.sleep(for: .milliseconds(150))
                }
                FileHandle.standardError.write(Data(("DEBUGJOB FINAL phase=\(job.phase) path=\(job.outputPath?.path ?? "-")\n").utf8))
            }
        }
        #endif
    }

    /// Path we will manage the bundled tools in (used from M1 onward).
    static var applicationSupportDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("YtDlpUI", isDirectory: true)
    }
}
