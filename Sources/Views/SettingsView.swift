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
            Picker("Default format:", selection: $appState.defaultFormat) {
                ForEach(FormatPreset.allCases) { Text($0.title).tag($0) }
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
        panel.prompt = "Choose"
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
        let tools = appState.tools

        Form {
            Section {
                LabeledContent("yt-dlp:", value: tools.ytDlpVersion ?? "—")
                LabeledContent("ffmpeg:", value: tools.ffmpegVersion ?? "—")
                statusRow(tools.state)
            }

            Section {
                Button("Check for yt-dlp Update") {}
                    .disabled(true)

                Button("Reinstall Tools") {
                    Task { await tools.bootstrap(forceReinstall: true) }
                }
                .disabled(tools.isBusy)

                Button("Open Application Support Folder", action: openSupportFolder)
            } footer: {
                Text("yt-dlp updates itself automatically (arriving in the next milestone). ffmpeg is bundled with the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
