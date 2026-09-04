import Foundation
import Observation

/// Owns the download queue and the one running yt-dlp process.
/// M2: serial (one download at a time). Parallelism is post-MVP.
@MainActor
@Observable
final class DownloadManager {

    private(set) var jobs: [DownloadJob] = []   // newest first

    private let tools: ToolManager
    private var isRunning = false
    private var activeJob: DownloadJob?
    private var activeControl: ProcessControl?
    private var lastProgressUpdate = Date.distantPast

    /// Called once per job when it reaches `.completed` or `.failed`
    /// (not `.cancelled`).
    var onJobFinished: ((DownloadJob) -> Void)?

    /// While true, queued jobs don't start (a yt-dlp self-update is running).
    var isBlockedForToolUpdate = false {
        didSet {
            if oldValue && !isBlockedForToolUpdate { startNextIfIdle() }
        }
    }

    init(tools: ToolManager) {
        self.tools = tools
        // Clear any staging dirs left behind by a crash (nothing runs at launch).
        try? FileManager.default.removeItem(at: Self.stagingRoot)
    }

    private static var stagingRoot: URL {
        AppState.applicationSupportDirectory.appendingPathComponent("staging", isDirectory: true)
    }

    var hasActiveDownloads: Bool { jobs.contains(where: \.isActive) }
    var hasFinishedDownloads: Bool { jobs.contains(where: \.isFinished) }

    // MARK: Intents

    func enqueue(_ request: DownloadRequest) {
        jobs.insert(DownloadJob(request: request), at: 0)
        Log.downloads.info("enqueue \(request.url, privacy: .public)")
        startNextIfIdle()
    }

    func cancel(_ job: DownloadJob) {
        switch job.phase {
        case .queued:
            job.phase = .cancelled
        case .running, .postProcessing:
            job.phase = .cancelled
            if job.id == activeJob?.id {
                activeControl?.terminate()
            }
        case .completed, .failed, .cancelled:
            break
        }
    }

    func retry(_ job: DownloadJob) {
        guard case .failed = job.phase,
              let index = jobs.firstIndex(where: { $0.id == job.id })
        else { return }
        jobs[index] = DownloadJob(request: job.request)
        startNextIfIdle()
    }

    func remove(_ job: DownloadJob) {
        if job.isActive { cancel(job) }
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() {
        jobs.removeAll { $0.isFinished }
    }

    // MARK: Queue

    private func startNextIfIdle() {
        guard !isRunning, !isBlockedForToolUpdate,
              let next = jobs.last(where: { $0.phase == .queued })
        else { return }

        isRunning = true
        Task {
            await run(next)
            isRunning = false
            startNextIfIdle()
        }
    }

    private func run(_ job: DownloadJob) async {
        guard job.phase == .queued else { return }
        guard tools.state == .ready else {
            job.phase = .failed(String(localized: "Tools aren’t ready yet — check Settings ▸ Tools."))
            return
        }

        job.phase = .running
        activeJob = job

        let fileManager = FileManager.default
        let cacheDirectory = AppState.applicationSupportDirectory
            .appendingPathComponent("cache", isDirectory: true)
        let staging = Self.stagingRoot.appendingPathComponent(job.id.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        let arguments = ArgBuilder.build(
            job.request,
            toolsDirectory: tools.binDirectory,
            cacheDirectory: cacheDirectory,
            outputDirectory: staging
        )

        let output: ProcessOutput
        do {
            output = try await ProcessRunner.stream(
                tools.url(for: .ytDlp),
                arguments: arguments,
                environment: ProcessRunner.hermeticEnvironment(),
                onStart: { control in
                    Task { @MainActor in self.activeControl = control }
                },
                onStdoutLine: { line in
                    guard let event = ProgressParser.parse(line) else { return }
                    Task { @MainActor in self.apply(event, to: job) }
                }
            )
        } catch {
            activeJob = nil
            activeControl = nil
            if job.phase != .cancelled { job.phase = .failed(error.localizedDescription); onJobFinished?(job) }
            try? fileManager.removeItem(at: staging)
            return
        }

        activeJob = nil
        activeControl = nil
        defer { try? fileManager.removeItem(at: staging) }

        if job.phase == .cancelled {
            Log.downloads.info("cancelled \(job.request.url, privacy: .public)")
            return
        }

        guard output.succeeded else {
            let detail = output.stderrTail(4)
            job.phase = .failed(detail.isEmpty ? String(localized: "yt-dlp exited with code \(output.exitCode)") : detail)
            Log.downloads.error("failed \(job.request.url, privacy: .public)")
            onJobFinished?(job)
            return
        }

        do {
            let finalURL = try placeOutput(for: job, staging: staging)
            job.outputPath = finalURL
            job.phase = .completed
            job.progress.fraction = 1
            Log.downloads.info("completed \(finalURL.lastPathComponent, privacy: .public)")
        } catch {
            job.phase = .failed(String(localized: "Download finished but the file couldn’t be saved: \(error.localizedDescription)"))
            Log.downloads.error("place failed: \(error.localizedDescription, privacy: .public)")
        }
        onJobFinished?(job)
    }

    /// Move the finished file out of the per-job staging dir into the real
    /// destination, appending " (2)", " (3)"… if that name is already taken.
    private func placeOutput(for job: DownloadJob, staging: URL) throws -> URL {
        let fileManager = FileManager.default
        let destination = job.request.destinationDirectory
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let source = try primaryFile(in: staging, preferredName: job.outputPath?.lastPathComponent)

        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        var candidate = destination.appendingPathComponent(source.lastPathComponent)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            candidate = destination.appendingPathComponent(name)
            counter += 1
        }
        try fileManager.moveItem(at: source, to: candidate)
        return candidate
    }

    private func primaryFile(in staging: URL, preferredName: String?) throws -> URL {
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        )) ?? []

        let outputs = entries.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
            return !["part", "ytdl", "tmp"].contains(url.pathExtension.lowercased())
        }

        if let preferredName,
           let match = outputs.first(where: { $0.lastPathComponent == preferredName }) {
            return match
        }
        let biggest = outputs.max { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let r = (try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return l < r
        }
        guard let biggest else { throw DownloadError.noOutputProduced }
        return biggest
    }

    enum DownloadError: LocalizedError {
        case noOutputProduced
        var errorDescription: String? {
            switch self {
            case .noOutputProduced: return String(localized: "yt-dlp finished without producing a file.")
            }
        }
    }

    // MARK: Output handling

    private func apply(_ event: ProgressEvent, to job: DownloadJob) {
        guard job.isActive else { return }

        switch event {
        case .title(let title):
            if job.title == nil {
                job.title = title
                Log.downloads.info("title \(title, privacy: .public)")
            }

        case .outputPath(let url):
            job.outputPath = url
            Log.downloads.debug("outputPath \(url.lastPathComponent, privacy: .public)")

        case .postProcessing:
            if job.phase == .running {
                job.phase = .postProcessing
                Log.downloads.info("post-processing")
            }

        case .alreadyDownloaded:
            job.progress.fraction = 1

        case .progress(let incoming):
            let now = Date()
            let isFinalTick = (incoming.fraction ?? 0) >= 1
            guard isFinalTick || now.timeIntervalSince(lastProgressUpdate) >= 0.2 else { return }
            lastProgressUpdate = now
            merge(incoming, into: job)
            Log.downloads.debug("progress \(job.progress.percentText ?? "?", privacy: .public) \(job.progress.speedText ?? "", privacy: .public)")
        }
    }

    private func merge(_ incoming: DownloadProgress, into job: DownloadJob) {
        var merged = job.progress
        merged.downloadedBytes = incoming.downloadedBytes ?? merged.downloadedBytes
        merged.totalBytes = incoming.totalBytes ?? merged.totalBytes
        merged.speedBytesPerSecond = incoming.speedBytesPerSecond
        merged.etaSeconds = incoming.etaSeconds
        merged.fraction = incoming.fraction ?? merged.fraction
        job.progress = merged
    }
}
