import SwiftUI

@main
struct YtDlpUIApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environment(appState)
        } label: {
            Image(systemName: appState.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
