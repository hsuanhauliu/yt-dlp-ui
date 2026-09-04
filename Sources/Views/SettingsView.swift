import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            ToolsSettingsView()
                .tabItem { Label("Tools", systemImage: "shippingbox") }
        }
        .frame(width: 460)
        .frame(minHeight: 280)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section("Default download") {
                Picker("Type:", selection: $appState.defaultSelection.kind) {
                    ForEach(MediaKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                switch appState.defaultSelection.kind {
                case .video:
                    Picker("Quality:", selection: $appState.defaultSelection.videoQuality) {
                        ForEach(VideoQuality.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Container:", selection: $appState.defaultSelection.videoContainer) {
                        ForEach(VideoContainer.allCases) { Text($0.label).tag($0) }
                    }
                case .audio:
                    Picker("Format:", selection: $appState.defaultSelection.audioFormat) {
                        ForEach(AudioFormat.allCases) { Text($0.label).tag($0) }
                    }
                }
            }

            LabeledContent("Save to:") {
                HStack(spacing: 8) {
                    Text(appState.downloadDirectory.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Change…", action: chooseFolder)
                }
            }

            Toggle("Show a notification when a download finishes",
                   isOn: $appState.notificationsEnabled)

            Toggle("Launch at login", isOn: $appState.launchAtLogin)

            Section {
                Picker("Language:", selection: $appState.appLanguage) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                if appState.languageChangePending {
                    HStack(spacing: 8) {
                        Text("Relaunch to apply the new language.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Relaunch Now") { appState.relaunch() }
                    }
                }
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.directoryURL = appState.downloadDirectory
        if panel.runModal() == .OK, let url = panel.url {
            appState.downloadDirectory = url
        }
    }
}

// MARK: - Tools

private struct ToolsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        let tools = appState.tools
        let updates = appState.updates

        Form {
            Section {
                LabeledContent("yt-dlp:", value: tools.ytDlpVersion ?? "—")
                LabeledContent("ffmpeg:", value: tools.ffmpegVersion ?? "—")
                statusRow(tools.state)
            }

            Section {
                Picker("Channel:", selection: $appState.ytDlpChannel) {
                    ForEach(YtDlpChannel.allCases) { Text($0.label).tag($0) }
                }

                HStack {
                    Button("Check for yt-dlp Update") {
                        Task { await updates.checkNow() }
                    }
                    .disabled(updates.isChecking || tools.isBusy)

                    if updates.isChecking {
                        ProgressView().controlSize(.small)
                    }
                }

                if let message = updates.statusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("\(updates.lastCheckText). yt-dlp is checked automatically about once a day. ffmpeg is bundled and moves only with an app update.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reinstall Tools") {
                    Task { await tools.bootstrap(forceReinstall: true) }
                }
                .disabled(tools.isBusy)

                Button("Open Application Support Folder", action: openSupportFolder)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func statusRow(_ state: ToolManager.State) -> some View {
        switch state {
        case .idle, .ready:
            EmptyView()
        case .working(let message):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(message).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func openSupportFolder() {
        let url = AppState.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
