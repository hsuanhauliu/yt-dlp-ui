import SwiftUI
import AppKit

struct DownloadRowView: View {
    @Environment(AppState.self) private var appState
    let job: DownloadJob

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.displayName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if job.phase == .running {
                    ProgressView(value: job.progress.fraction ?? 0, total: 1)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                }

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(isFailed ? .red : .secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 4)

            actions
                .opacity(showActionsAlways || hovering ? 1 : 0.35)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(job.phase.isFailure ? failureHelp : job.displayName)
    }

    // MARK: Detail line

    private var detailText: String {
        switch job.phase {
        case .queued:
            return "Queued"
        case .running:
            let parts = [
                job.progress.percentText,
                job.progress.sizeText.map { size in
                    job.progress.percentText != nil ? "of \(size)" : size
                },
                job.progress.speedText,
                job.progress.etaText.map { "ETA \($0)" },
            ].compactMap { $0 }
            return parts.isEmpty ? "Starting…" : parts.joined(separator: "  ·  ")
        case .postProcessing:
            return "Processing…"
        case .completed:
            return "Completed"
        case .failed(let message):
            return message.split(whereSeparator: \.isNewline).last.map(String.init) ?? "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    private var failureHelp: String {
        if case .failed(let message) = job.phase { return message }
        return job.displayName
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch job.phase {
        case .queued, .running, .postProcessing:
            iconButton("xmark.circle.fill", help: "Cancel") { appState.downloads.cancel(job) }

        case .completed:
            iconButton("magnifyingglass.circle.fill", help: "Reveal in Finder", action: revealInFinder)

        case .failed:
            HStack(spacing: 2) {
                iconButton("arrow.clockwise.circle.fill", help: "Retry") { appState.downloads.retry(job) }
                iconButton("xmark.circle.fill", help: "Dismiss") { appState.downloads.remove(job) }
            }

        case .cancelled:
            iconButton("xmark.circle.fill", help: "Dismiss") { appState.downloads.remove(job) }
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).imageScale(.medium)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var showActionsAlways: Bool {
        switch job.phase {
        case .running, .postProcessing, .failed: return true
        default: return false
        }
    }

    private func revealInFinder() {
        if let path = job.outputPath, FileManager.default.fileExists(atPath: path.path) {
            NSWorkspace.shared.activateFileViewerSelecting([path])
        } else {
            NSWorkspace.shared.open(job.request.destinationDirectory)
        }
    }

    // MARK: Appearance

    private var isFailed: Bool { job.phase.isFailure }

    private var icon: String {
        switch job.phase {
        case .queued: return "clock"
        case .running: return "arrow.down.circle"
        case .postProcessing: return "gearshape"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "slash.circle"
        }
    }

    private var iconColor: Color {
        switch job.phase {
        case .completed: return .green
        case .failed: return .red
        case .running, .postProcessing: return .accentColor
        default: return .secondary
        }
    }
}

extension DownloadJob.Phase {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
