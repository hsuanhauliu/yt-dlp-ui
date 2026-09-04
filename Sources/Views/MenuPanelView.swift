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
    @State private var lastSubmittedURL: String?

    /// Reserve room for ~4 rows so the panel isn't cramped with one download,
    /// and grow to ~6 before scrolling.
    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 58
        let rows = min(max(appState.downloads.jobs.count, 4), 6)
        return CGFloat(rows) * rowHeight
    }

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
                    Picker("Type", selection: $appState.defaultSelection.kind) {
                        ForEach(MediaKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    switch appState.defaultSelection.kind {
                    case .video:
                        Picker("Quality", selection: $appState.defaultSelection.videoQuality) {
                            ForEach(VideoQuality.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 90)
                    case .audio:
                        Picker("Format", selection: $appState.defaultSelection.audioFormat) {
                            ForEach(AudioFormat.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 90)
                    }

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

            // MARK: Downloads

            if appState.downloads.jobs.isEmpty {
                ContentUnavailableView(
                    "No downloads yet",
                    systemImage: "arrow.down.circle",
                    description: Text("Paste a link above to get started.")
                )
                .frame(maxWidth: .infinity)
                .frame(height: listHeight)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.downloads.jobs) { job in
                            DownloadRowView(job: job)
                            if job.id != appState.downloads.jobs.last?.id {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(height: listHeight)
            }

            Divider()

            // MARK: Footer

            HStack {
                Button("Clear finished") {
                    appState.downloads.clearFinished()
                }
                .disabled(!appState.downloads.hasFinishedDownloads)

                Spacer()

                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }

                Button("Quit", role: .destructive) { confirmQuit() }
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
        // Don't re-offer a URL we just downloaded (it's usually still on the
        // clipboard when the panel is reopened).
        guard trimmed != lastSubmittedURL, isProbablyDownloadableURL(trimmed) else { return }
        urlText = trimmed
    }

    private func startDownload() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isProbablyDownloadableURL(trimmed) else { return }
        appState.requestNotificationPermissionIfNeeded()
        appState.downloads.enqueue(
            DownloadRequest(
                url: trimmed,
                selection: appState.defaultSelection,
                destinationDirectory: appState.downloadDirectory
            )
        )
        lastSubmittedURL = trimmed
        urlText = ""
    }

    private func confirmQuit() {
        guard appState.downloads.hasActiveDownloads else {
            NSApp.terminate(nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = "A download is still in progress."
        alert.informativeText = "Quitting now will cancel it."
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
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
