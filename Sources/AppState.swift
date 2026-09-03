import Foundation
import Observation
import ServiceManagement

/// App-wide state. In M0 the settings live in memory only; persistence and the
/// download queue arrive in later milestones.
@MainActor
@Observable
final class AppState {

    // MARK: Settings

    var defaultFormat: FormatPreset = .best

    var downloadDirectory: URL = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }()

    var notificationsEnabled: Bool = true

    // MARK: Managed tools

    let tools = ToolManager()

    // MARK: Transient UI

    var lastError: String?

    // MARK: Derived

    /// Menu-bar icon. Becomes stateful (downloading / failed) once the download
    /// engine exists.
    var menuBarSymbol: String { "arrow.down.circle" }

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
                lastError = "Couldn’t update Launch at Login: \(error.localizedDescription)"
                launchAtLogin = oldValue
            }
        }
    }

    init() {
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        let tools = self.tools
        Task { await tools.bootstrap() }
    }

    /// Path we will manage the bundled tools in (used from M1 onward).
    static var applicationSupportDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("YtDlpUI", isDirectory: true)
    }
}
