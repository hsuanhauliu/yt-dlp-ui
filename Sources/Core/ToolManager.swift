import Foundation
import Observation
import CryptoKit

/// Owns the private copies of `yt-dlp` and `ffmpeg` that live in Application
/// Support, keeps them runnable, and reports their versions to the UI.
///
/// M1: seed from the app bundle, ad-hoc re-sign if needed, smoke-test.
/// M4 adds the yt-dlp self-update path.
@MainActor
@Observable
final class ToolManager {

    enum Tool: String, CaseIterable, Sendable {
        case ytDlp = "yt-dlp_macos"
        case ffmpeg

        var displayName: String {
            switch self {
            case .ytDlp: return "yt-dlp"
            case .ffmpeg: return "ffmpeg"
            }
        }
    }

    enum State: Sendable, Equatable {
        case idle
        case working(String)
        case ready
        case failed(String)
    }

    // MARK: Observable status

    private(set) var state: State = .idle
    private(set) var ytDlpVersion: String?
    private(set) var ffmpegVersion: String?

    var isBusy: Bool {
        if case .working = state { return true }
        return false
    }

    // MARK: Locations

    let binDirectory: URL
    private let manifestURL: URL
    private let statusURL: URL

    private var seedDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Vendor", isDirectory: true)
    }

    init(supportDirectory: URL = AppState.applicationSupportDirectory) {
        self.binDirectory = supportDirectory.appendingPathComponent("bin", isDirectory: true)
        self.manifestURL = binDirectory.appendingPathComponent("installed.json")
        self.statusURL = supportDirectory.appendingPathComponent("tool-status.json")
    }

    /// Absolute path to a managed tool (valid only after a successful bootstrap).
    func url(for tool: Tool) -> URL {
        binDirectory.appendingPathComponent(tool.rawValue)
    }

    // MARK: Bootstrap

    /// Idempotent. Runs on every launch and behind the "Reinstall Tools" button.
    ///
    /// Fast path (seeds already installed and unchanged): no subprocesses, just
    /// reads the cached versions. Slow path (first launch / new seed / reinstall):
    /// copy, ad-hoc re-sign if needed, and probe `--version`.
    func bootstrap(forceReinstall: Bool = false) async {
        Log.tools.info("bootstrap start (force=\(forceReinstall))")
        state = .working("Preparing tools…")

        do {
            let fm = FileManager.default
            try fm.createDirectory(at: binDirectory, withIntermediateDirectories: true)

            let seed = try loadSeed()
            var manifest = loadManifest()
            var freshlySeeded: Set<Tool> = []

            for tool in Tool.allCases {
                let destination = url(for: tool)
                let record = manifest[tool.rawValue]
                let seedEntry = seed[tool.rawValue]

                let needsSeed =
                    forceReinstall
                    || record == nil
                    || !fm.isExecutableFile(atPath: destination.path)
                    || fileSize(destination) != record?.size
                    || (record?.source == .seed && record?.version != seedEntry?.version)

                if needsSeed {
                    Log.tools.info("seeding \(tool.rawValue, privacy: .public) -> \(seedEntry?.version ?? "?", privacy: .public)")
                    state = .working("Installing \(tool.displayName)…")
                    try installSeed(tool, to: destination, expected: seedEntry)
                    try await prepareForExecution(destination)
                    manifest[tool.rawValue] = InstalledRecord(
                        version: seedEntry?.version ?? "unknown",
                        source: .seed,
                        size: fileSize(destination)
                    )
                    freshlySeeded.insert(tool)
                }
            }
            saveManifest(manifest)

            // Probe only tools we just (re)installed, or that have no cached
            // version; otherwise trust the manifest and skip the subprocess.
            if freshlySeeded.contains(.ytDlp) || manifest[Tool.ytDlp.rawValue]?.version == nil {
                state = .working("Checking yt-dlp…")
                let version = try await probeVersion(.ytDlp, arguments: ["--version", "--ignore-config"])
                manifest[Tool.ytDlp.rawValue]?.version = version
            }
            ytDlpVersion = manifest[Tool.ytDlp.rawValue]?.version

            if freshlySeeded.contains(.ffmpeg) || manifest[Tool.ffmpeg.rawValue]?.version == nil {
                state = .working("Checking ffmpeg…")
                let line = try await probeVersion(.ffmpeg, arguments: ["-version"])
                manifest[Tool.ffmpeg.rawValue]?.version = Self.parseFfmpegVersion(line)
            }
            ffmpegVersion = manifest[Tool.ffmpeg.rawValue]?.version

            saveManifest(manifest)

            if ytDlpVersion != nil, ffmpegVersion != nil {
                state = .ready
            } else {
                state = .failed("Couldn’t determine tool versions. Try Reinstall Tools.")
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Log.tools.error("bootstrap failed: \(message, privacy: .public)")
            state = .failed(message)
        }

        Log.tools.info("bootstrap done: \(String(describing: self.state), privacy: .public)")
        writeStatusSnapshot()
    }

    // MARK: Steps

    private func installSeed(_ tool: Tool, to destination: URL, expected: SeedEntry?) throws {
        guard let seedDirectory else { throw ToolError.seedDirectoryMissing }
        let source = seedDirectory.appendingPathComponent(tool.rawValue)
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw ToolError.seedMissing(tool.displayName)
        }
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)

        if let expected {
            let digest = try Self.sha256(of: destination)
            guard digest == expected.sha256.lowercased() else {
                try? fm.removeItem(at: destination)
                throw ToolError.checksumMismatch(tool.displayName)
            }
        }
    }

    private func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func prepareForExecution(_ url: URL) async throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )

        // Best effort: strip any quarantine flag (curl-downloaded files in M4
        // won't have one, but a manually dropped file might).
        _ = try? await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/xattr"),
            arguments: ["-d", "com.apple.quarantine", url.path],
            timeout: .seconds(5)
        )

        // On Apple Silicon an unsigned binary is killed on exec. Our seeds are
        // already signed (ffmpeg: Developer ID, yt-dlp: ad-hoc); re-sign only if
        // verification fails.
        let verify = try await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--strict", url.path],
            timeout: .seconds(30)
        )
        if !verify.succeeded {
            Log.tools.notice("re-signing \(url.lastPathComponent, privacy: .public) (ad-hoc)")
            _ = try await ProcessRunner.run(
                URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["--force", "--sign", "-", url.path],
                timeout: .seconds(60)
            )
        }
    }

    private func probeVersion(_ tool: Tool, arguments: [String]) async throws -> String {
        let result = try await ProcessRunner.run(
            url(for: tool),
            arguments: arguments,
            environment: ProcessRunner.hermeticEnvironment(),
            timeout: .seconds(30)
        )
        guard result.succeeded, let line = result.firstOutputLine else {
            let detail: String
            if result.timedOut {
                detail = "timed out"
            } else {
                let tail = result.stderrTail(3)
                detail = tail.isEmpty ? "no output (exit \(result.exitCode))" : tail
            }
            throw ToolError.probeFailed(tool: tool.displayName, detail: detail)
        }
        return line
    }

    /// `"ffmpeg version 9.0.1-https://... Copyright ..."` -> `"9.0.1"`.
    static func parseFfmpegVersion(_ firstLine: String) -> String {
        if let match = firstLine.firstMatch(of: /version\s+([\w.]+)/) {
            return String(match.1)
        }
        return firstLine
    }

    // MARK: Manifest

    private struct InstalledRecord: Codable, Sendable {
        enum Source: String, Codable, Sendable { case seed, update }
        var version: String?
        var source: Source
        var size: Int?
    }

    struct SeedEntry: Decodable, Sendable {
        var version: String
        var sha256: String
        var size: Int
    }

    private struct SeedManifest: Decodable {
        var tools: [String: SeedEntry]
    }

    private func loadManifest() -> [String: InstalledRecord] {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([String: InstalledRecord].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveManifest(_ manifest: [String: InstalledRecord]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    private func loadSeed() throws -> [String: SeedEntry] {
        guard let seedDirectory else { throw ToolError.seedDirectoryMissing }
        let url = seedDirectory.appendingPathComponent("seed.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SeedManifest.self, from: data)
        else { throw ToolError.seedDirectoryMissing }
        return decoded.tools
    }

    /// Human-readable snapshot in Application Support, for support/debugging.
    private func writeStatusSnapshot() {
        let stateString: String
        switch state {
        case .idle: stateString = "idle"
        case .working(let m): stateString = "working: \(m)"
        case .ready: stateString = "ready"
        case .failed(let m): stateString = "failed: \(m)"
        }
        let snapshot: [String: String] = [
            "state": stateString,
            "ytDlpVersion": ytDlpVersion ?? "",
            "ffmpegVersion": ffmpegVersion ?? "",
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: statusURL, options: .atomic)
        }
    }
}

enum ToolError: LocalizedError {
    case seedDirectoryMissing
    case seedMissing(String)
    case checksumMismatch(String)
    case probeFailed(tool: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .seedDirectoryMissing:
            return "The app is missing its bundled tools. Rebuild after running scripts/fetch-tools.sh."
        case .seedMissing(let name):
            return "The bundled copy of \(name) is missing. Rebuild after running scripts/fetch-tools.sh."
        case .checksumMismatch(let name):
            return "The bundled copy of \(name) failed its integrity check."
        case .probeFailed(let tool, let detail):
            return "\(tool) didn’t run correctly:\n\(detail)"
        }
    }
}
