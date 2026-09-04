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

/// A Sendable control handle for a running streamed process.
struct ProcessControl: Sendable {
    private let onTerminate: @Sendable () -> Void
    init(onTerminate: @escaping @Sendable () -> Void) { self.onTerminate = onTerminate }
    /// SIGTERM now, SIGKILL shortly after if it doesn't exit.
    func terminate() { onTerminate() }
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

    // MARK: Streaming

    /// Run `executable`, delivering stdout lines to `onStdoutLine` as they
    /// arrive. Resolves once the process has exited and both pipes are drained.
    /// `ProcessOutput.standardOutput` is empty (it was streamed); stderr is
    /// captured (last ~200 lines) for error reporting.
    static func stream(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        onStart: (@Sendable (ProcessControl) -> Void)? = nil,
        onStdoutLine: @escaping @Sendable (String) -> Void
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

        let stderr = RingBuffer(limit: 200)
        let stdoutReader = LineReader(handle: outPipe.fileHandleForReading, onLine: onStdoutLine)
        let stderrReader = LineReader(handle: errPipe.fileHandleForReading, onLine: { stderr.append($0) })

        Log.process.debug("stream \(executable.lastPathComponent) \(arguments.joined(separator: " "), privacy: .public)")
        do {
            try process.run()
        } catch {
            stdoutReader.cancel()
            stderrReader.cancel()
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        onStart?(ProcessControl { Self.terminate(process) })

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await Self.waitForExit(process) }
            group.addTask { await stdoutReader.waitForEOF() }
            group.addTask { await stderrReader.waitForEOF() }
        }

        Log.process.debug("stream exit \(executable.lastPathComponent) status=\(process.terminationStatus)")

        return ProcessOutput(
            exitCode: process.terminationStatus,
            standardOutput: "",
            standardError: stderr.joined(),
            timedOut: false
        )
    }

    /// SIGTERM, then SIGKILL after `graceSeconds` if still alive.
    static func terminate(_ process: Process, graceSeconds: Double = 3) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        Task {
            try? await Task.sleep(for: .seconds(graceSeconds))
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private static func waitForExit(_ process: Process) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce { continuation.resume() }
            process.terminationHandler = { _ in once.fire() }
            if !process.isRunning { once.fire() }
        }
    }
}

/// Splits a `FileHandle`'s byte stream into lines (`\n` or `\r`), delivering each
/// complete line to `onLine`. `waitForEOF()` resolves when the handle closes.
private final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [UInt8] = []
    private var didFinish = false
    private var eofContinuation: CheckedContinuation<Void, Never>?
    private let onLine: @Sendable (String) -> Void
    private let handle: FileHandle

    init(handle: FileHandle, onLine: @escaping @Sendable (String) -> Void) {
        self.handle = handle
        self.onLine = onLine
        handle.readabilityHandler = { [weak self] fileHandle in
            guard let self else { return }
            let data = fileHandle.availableData
            if data.isEmpty {
                self.finish()
            } else {
                self.consume(data)
            }
        }
    }

    func waitForEOF() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if didFinish {
                lock.unlock()
                continuation.resume()
            } else {
                eofContinuation = continuation
                lock.unlock()
            }
        }
    }

    func cancel() {
        handle.readabilityHandler = nil
        finish()
    }

    private func consume(_ data: Data) {
        var lines: [String] = []
        lock.lock()
        pending.append(contentsOf: data)
        while let index = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let line = String(decoding: pending[0..<index], as: UTF8.self)
            pending.removeFirst(index + 1)
            if !line.isEmpty { lines.append(line) }
        }
        lock.unlock()
        for line in lines { onLine(line) }
    }

    private func finish() {
        var trailing: String?
        var continuation: CheckedContinuation<Void, Never>?
        lock.lock()
        if !didFinish {
            didFinish = true
            if !pending.isEmpty {
                trailing = String(decoding: pending, as: UTF8.self)
                pending.removeAll()
            }
            continuation = eofContinuation
            eofContinuation = nil
        }
        lock.unlock()
        if let trailing, !trailing.isEmpty { onLine(trailing) }
        continuation?.resume()
    }
}

private final class RingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        lock.unlock()
    }

    func joined() -> String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
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
