import Foundation

/// Reads and writes the persisted user settings. Split out from `AppState` so it
/// can be exercised with a scratch `UserDefaults` in tests.
struct SettingsStore {
    let defaults: UserDefaults

    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let format = "defaultSelection"
        static let downloadDirectory = "downloadDirectory"
        static let notifications = "notificationsEnabled"
        static let channel = "ytDlpChannel"
    }

    var format: FormatSelection {
        get {
            guard let data = defaults.data(forKey: Key.format),
                  let value = try? JSONDecoder().decode(FormatSelection.self, from: data)
            else { return FormatSelection() }
            return value
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.format)
            }
        }
    }

    var downloadDirectory: URL {
        get {
            defaults.string(forKey: Key.downloadDirectory)
                .map { URL(fileURLWithPath: $0) } ?? Self.defaultDownloadDirectory
        }
        nonmutating set {
            defaults.set(newValue.path(percentEncoded: false), forKey: Key.downloadDirectory)
        }
    }

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: Key.notifications) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.notifications) }
    }

    var ytDlpChannel: YtDlpChannel {
        get { defaults.string(forKey: Key.channel).flatMap(YtDlpChannel.init) ?? .stable }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.channel) }
    }

    static var defaultDownloadDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
}
