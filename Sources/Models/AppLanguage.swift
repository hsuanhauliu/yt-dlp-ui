import Foundation

/// The app's display-language choice. `.system` follows macOS; the others
/// override it (written to the `AppleLanguages` user default, applied on
/// relaunch).
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case traditionalChineseTW = "zh-Hant"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return String(localized: "System Default")
        case .english: return "English"
        case .traditionalChineseTW: return "繁體中文（台灣）"
        }
    }

    /// Value for the `AppleLanguages` default; `nil` means "remove the override".
    var appleLanguages: [String]? {
        self == .system ? nil : [rawValue]
    }

    private static let overrideKey = "appLanguageOverride"

    static var current: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: overrideKey) else { return .system }
        return AppLanguage(rawValue: raw) ?? .system
    }

    /// Persist the choice and sync `AppleLanguages` (takes effect on next launch).
    func persist() {
        let defaults = UserDefaults.standard
        if self == .system {
            defaults.removeObject(forKey: Self.overrideKey)
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set(rawValue, forKey: Self.overrideKey)
            defaults.set(appleLanguages, forKey: "AppleLanguages")
        }
    }
}
