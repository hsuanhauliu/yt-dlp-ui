import Testing
import Foundation
@testable import YtDlpUI

struct SettingsStoreTests {

    private func scratchDefaults() -> UserDefaults {
        let name = "test.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func returnsDefaultsWhenEmpty() {
        let store = SettingsStore(scratchDefaults())
        #expect(store.format == FormatSelection())
        #expect(store.notificationsEnabled == true)
        #expect(store.ytDlpChannel == .stable)
        #expect(store.downloadDirectory == SettingsStore.defaultDownloadDirectory)
    }

    @Test func persistsAndReloads() {
        let defaults = scratchDefaults()

        let store = SettingsStore(defaults)
        store.format = FormatSelection(kind: .audio, videoContainer: .mkv, audioFormat: .opus)
        store.notificationsEnabled = false
        store.ytDlpChannel = .nightly
        store.downloadDirectory = URL(fileURLWithPath: "/tmp/yt")

        let reloaded = SettingsStore(defaults)
        #expect(reloaded.format == FormatSelection(kind: .audio, videoContainer: .mkv, audioFormat: .opus))
        #expect(reloaded.notificationsEnabled == false)
        #expect(reloaded.ytDlpChannel == .nightly)
        #expect(reloaded.downloadDirectory.path == "/tmp/yt")
    }

    @Test func ignoresGarbageValues() {
        let defaults = scratchDefaults()
        defaults.set("not json", forKey: "defaultSelection")
        defaults.set("banana", forKey: "ytDlpChannel")

        let store = SettingsStore(defaults)
        #expect(store.format == FormatSelection())
        #expect(store.ytDlpChannel == .stable)
    }
}
