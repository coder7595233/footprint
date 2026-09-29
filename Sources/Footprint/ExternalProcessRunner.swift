import Darwin
import Foundation

enum ExternalProcessRunner {
    struct CompletedProcess: Sendable {
        let stdout: String
        let stderr: String
        let terminationStatus: Int32
    }

    enum RunnerError: LocalizedError {
        case timedOut(command: String, timeout: TimeInterval, stdout: String, stderr: String)
        case nonZeroExit(command: String, status: Int32, stdout: String, stderr: String)

        var errorDescription: String? {
            switch self {
            case let .timedOut(command, timeout, stdout, stderr):
                let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if details.isEmpty {
                    return "Tidsgränsen på \(Int(timeout)) sekunder överskreds (command timed out): \(command)"
                }
                return "Tidsgränsen på \(Int(timeout)) sekunder överskreds (command timed out): \(command)\n\(details)"
            case let .nonZeroExit(command, status, stdout, stderr):
                let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if details.isEmpty {
                    return "Kommandot misslyckades (command failed) med kod \(status): \(command)"
                }
                return details
            }
        }
    }

    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval = 180,
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil
    ) throws -> CompletedProcess {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        if let environment {
            process.environment = environment
        }

        // FileHandle readability callbacks can still be running when Process
        // reports termination. Reading those same pipes synchronously at that
        // point races Foundation's callback machinery and can terminate the
        // host app. Spool each stream to its own temporary file instead; this
        // also avoids pipe back-pressure for large exports.
        let outputWorkspace = try TemporaryWorkspaceDirectory(prefix: "FootprintProcessOutput")
        defer { outputWorkspace.cleanup() }
        let stdoutURL = outputWorkspace.url.appendingPathComponent("stdout")
        let stderrURL = outputWorkspace.url.appendingPathComponent("stderr")
        guard FileManager.default.createFile(atPath: stdoutURL.path, contents: nil),
              FileManager.default.createFile(atPath: stderrURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }
        let completionGroup = DispatchGroup()
        completionGroup.enter()

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        process.terminationHandler = { _ in
            completionGroup.leave()
        }

        let command = ([executableURL.path] + arguments).joined(separator: " ")
        try process.run()

        let didFinishInTime = completionGroup.wait(timeout: .now() + timeout) == .success
        if !didFinishInTime {
            terminate(process: process, completionGroup: completionGroup)
        }

        try stdoutHandle.close()
        try stderrHandle.close()
        let stdout = String(data: try Data(contentsOf: stdoutURL), encoding: .utf8) ?? ""
        let stderr = String(data: try Data(contentsOf: stderrURL), encoding: .utf8) ?? ""

        guard didFinishInTime else {
            throw RunnerError.timedOut(
                command: command,
                timeout: timeout,
                stdout: stdout,
                stderr: stderr
            )
        }

        guard process.terminationStatus == 0 else {
            throw RunnerError.nonZeroExit(
                command: command,
                status: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        }

        return CompletedProcess(
            stdout: stdout,
            stderr: stderr,
            terminationStatus: process.terminationStatus
        )
    }

    private static func terminate(process: Process, completionGroup: DispatchGroup) {
        process.terminate()
        if completionGroup.wait(timeout: .now() + 1) == .success {
            return
        }
        kill(process.processIdentifier, SIGKILL)
        _ = completionGroup.wait(timeout: .now() + 1)
    }
}

enum PythonScriptRunner {
    enum RuntimeError: LocalizedError {
        case unavailable
        case allCandidatesFailed([String])

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Exporten kräver Python 3, men ingen betrodd Python-miljö hittades (no trusted Python runtime). Installera Apples Command Line Tools eller använd en Footprint-version med inbyggd Python."
            case let .allCandidatesFailed(errors):
                return "Ingen betrodd Python-miljö kunde slutföra exporten (export failed). " + errors.joined(separator: " | ")
            }
        }
    }

    private static func defaultCandidates() -> [URL] {
        [
            Bundle.main.resourceURL?
                .appendingPathComponent("Python", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("python3-footprint"),
            URL(fileURLWithPath: "/usr/bin/python3"),
        ].compactMap { $0 }
    }

    private static func trustedExecutableURLs(
        candidates: [URL],
        fileManager: FileManager
    ) -> [URL] {
        candidates.compactMap { candidate in
            let standardized = candidate.standardizedFileURL
            guard fileManager.isExecutableFile(atPath: standardized.path) else { return nil }
            if standardized.path.hasPrefix(Bundle.main.bundleURL.standardizedFileURL.path + "/") {
                let isTrustedBundledFile = (try? standardized.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]))
                    .map { $0.isRegularFile == true && $0.isSymbolicLink != true } == true
                return isTrustedBundledFile ? standardized : nil
            }
            return standardized.path == "/usr/bin/python3" ? standardized : nil
        }
    }

    static func resolvedExecutableURL(
        candidates: [URL]? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        trustedExecutableURLs(
            candidates: candidates ?? defaultCandidates(),
            fileManager: fileManager
        ).first
    }

    static func run(
        scriptURL: URL,
        arguments: [String],
        timeout: TimeInterval = 180
    ) throws -> String {
        let executableURLs = trustedExecutableURLs(
            candidates: defaultCandidates(),
            fileManager: .default
        )
        guard !executableURLs.isEmpty else {
            throw RuntimeError.unavailable
        }

        var failures: [String] = []
        for executableURL in executableURLs {
            do {
                let result = try ExternalProcessRunner.run(
                    executableURL: executableURL,
                    // -E ignores PYTHONPATH/PYTHONSTARTUP and -s skips the user
                    // site directory, so the interpreter only runs the vetted
                    // script even if the parent environment is attacker-controlled.
                    // (-I would also drop the script's own directory from
                    // sys.path, breaking the sibling ooxml_workbook import.)
                    arguments: ["-E", "-s", scriptURL.path] + arguments,
                    timeout: timeout,
                    environment: scrubbedEnvironment()
                )
                return result.stdout
            } catch {
                failures.append("\(executableURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        throw RuntimeError.allCandidatesFailed(failures)
    }

    // The export scripts read nothing from the environment (payload, template and
    // output paths all arrive as arguments), so the child gets a minimal
    // environment instead of inheriting PYTHON*/DYLD_* variables from the parent.
    private static func scrubbedEnvironment() -> [String: String] {
        var environment: [String: String] = ["LC_CTYPE": "UTF-8"]
        if let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"] {
            environment["TMPDIR"] = tmpdir
        }
        return environment
    }
}
