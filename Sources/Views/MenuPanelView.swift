import SwiftUI
import AppKit

/// The dropdown panel shown from the menu-bar icon.
///
/// M0: the input controls are live (clipboard prefill, folder picker, format
/// choice) but "start" is a stub — the download engine lands in M2.
struct MenuPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    @State private var urlText = ""

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {

            // MARK: Input

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    TextField("Paste or type a URL…", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(startDownload)

                    Button(action: startDownload) {
                        Image(systemName: "arrow.down.circle.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!isProbablyDownloadableURL(urlText))
                    .help("Start download")
                }

                HStack(spacing: 8) {
                    Picker("Format", selection: $appState.defaultFormat) {
                        ForEach(FormatPreset.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 170)

                    Spacer(minLength: 0)

                    Button(action: chooseFolder) {
                        Label(appState.downloadDirectory.lastPathComponent, systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.borderless)
                    .help(appState.downloadDirectory.path(percentEncoded: false))
                }
            }
            .padding(12)

            Divider()

            // MARK: Downloads (M3 fills this with DownloadRowView list)

            ContentUnavailableView(
                "No downloads yet",
                systemImage: "arrow.down.circle",
                description: Text("Paste a link above to get started.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)

            Divider()

            // MARK: Footer

            HStack {
                Button("Clear completed") {}
                    .disabled(true)

                Spacer()

                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }

                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .frame(width: 380)
        .onAppear(perform: prefillFromClipboard)
    }

    // MARK: Actions

    private func prefillFromClipboard() {
        guard urlText.isEmpty,
              let clip = NSPasteboard.general.string(forType: .string)
        else { return }
        let trimmed = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        if isProbablyDownloadableURL(trimmed) {
            urlText = trimmed
        }
    }

    private func startDownload() {
        guard isProbablyDownloadableURL(urlText) else { return }
        // M2: enqueue a DownloadJob on DownloadManager.
        NSLog("[YtDlpUI] TODO M2 — download %@ as %@", urlText, appState.defaultFormat.title)
        urlText = ""
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = appState.downloadDirectory
        if panel.runModal() == .OK, let url = panel.url {
            appState.downloadDirectory = url
        }
    }

    private func isProbablyDownloadableURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }
        return !(url.host()?.isEmpty ?? true)
    }
}

#Preview {
    MenuPanelView()
        .environment(AppState())
}
