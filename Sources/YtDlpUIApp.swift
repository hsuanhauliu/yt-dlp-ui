import SwiftUI

@main
struct YtDlpUIApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environment(appState)
        } label: {
            // MenuBarExtra labels allow only image / text / image+text.
            if appState.menuBarText.isEmpty {
                Image(systemName: appState.menuBarSymbol)
            } else {
                Label(appState.menuBarText, systemImage: appState.menuBarSymbol)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
