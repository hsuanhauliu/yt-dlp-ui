import Foundation

struct ProcessOutput: Sendable {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String
    var timedOut: Bool

    var succeeded: Bool { exitCode == 0 && !timedOut }

    /// First non-empty, trimmed line of stdout — handy for `--version` probes.
    var firstOutputLine: String? {
        standardOutput
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// Up to `limit` trailing non-empty lines of stderr, for error display.
    func stderrTail(_ limit: Int = 4) -> String {
        standardError
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(limit)
            .joined(separator: "\n")
    }
}

enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message): return "Couldn’t launch process: \(message)"
        }
    }
}

/// Minimal async wrapper around `Process`. M1 reads output after exit (callers
/// only run `--version`-style probes); M2 adds a streaming variant for downloads.
enum ProcessRunner {

    /// Run `executable` and wait for it to exit, or terminate it after `timeout`.
    ///
    /// - Parameter environment: `nil` inherits this process's environment
    ///   (use for system tools like `codesign`). Pass `hermeticEnvironment()`
    ///   for yt-dlp / ffmpeg so the user's shell config can't leak in.
    static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: Duration = .seconds(15)
    ) async throws -> ProcessOutput {

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        Log.process.debug("run \(executable.lastPathComponent) \(arguments.joined(separator: " "), privacy: .public)")
        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let timedOut = AtomicFlag()
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
            try? await Task.sleep(for: .milliseconds(500))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        await Self.waitForExit(process)
        timeoutTask.cancel()
        Log.process.debug("exit \(executable.lastPathComponent) status=\(process.terminationStatus) timedOut=\(timedOut.value)")

        let out = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        let err = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()

        return ProcessOutput(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: out, as: UTF8.self),
            standardError: String(decoding: err, as: UTF8.self),
            timedOut: timedOut.value
        )
    }

    /// An environment that does not carry the user's shell configuration.
    static func hermeticEnvironment() -> [String: String] {
        var env: [String: String] = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8",
        ]
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] {
            env["TMPDIR"] = tmp
        }
        return env
    }

    private static func waitForExit(_ process: Process) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce { continuation.resume() }
            process.terminationHandler = { _ in once.fire() }
            if !process.isRunning { once.fire() }
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (() -> Void)?

    init(_ action: @escaping () -> Void) { self.action = action }

    func fire() {
        lock.lock()
        let action = self.action
        self.action = nil
        lock.unlock()
        action?()
    }
}

private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }

    func set() {
        lock.lock(); flag = true; lock.unlock()
    }
}
