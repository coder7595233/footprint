import Foundation

/// F34: recognises a test run, whatever started it.
///
/// Storage isolation used to hang on one environment variable that Xcode sets
/// and `swift test` does not, so every command-line test run read and wrote the
/// user's real database. On 2026-09-27 a test wrote three placeholder teaching
/// assignments over 27 real ones. Any one of these signals is enough.
enum TestProcessDetection {
    static let environmentKeys = [
        "XCTestConfigurationFilePath",
        "XCTestBundlePath",
        "XCTestSessionIdentifier",
    ]

    static let testRunnerProcessNames: Set<String> = ["xctest", "swiftpm-testing-helper"]

    static func isTestProcess(
        environment: [String: String],
        processName: String,
        arguments: [String],
        bundlePath: String,
        xctestIsLoaded: Bool
    ) -> Bool {
        if environmentKeys.contains(where: { environment[$0] != nil }) { return true }
        if xctestIsLoaded { return true }
        if testRunnerProcessNames.contains(processName.lowercased()) { return true }
        if processName.hasSuffix(".xctest") || bundlePath.hasSuffix(".xctest") { return true }
        return arguments.contains { $0.hasSuffix(".xctest") || $0.hasSuffix(".xctest/") }
    }

    /// Evaluated once: none of the signals change while the process runs.
    static let isRunningTests: Bool = isTestProcess(
        environment: ProcessInfo.processInfo.environment,
        processName: ProcessInfo.processInfo.processName,
        arguments: CommandLine.arguments,
        bundlePath: Bundle.main.bundlePath,
        xctestIsLoaded: NSClassFromString("XCTestCase") != nil
    )

    /// True when `directory` is one of `protectedRoots` or lies inside one.
    static func isInside(_ directory: URL, anyOf protectedRoots: [URL]) -> Bool {
        let path = directory.standardizedFileURL.resolvingSymlinksInPath().path
        return protectedRoots.contains { root in
            let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }
}
