import Foundation

struct TemporaryWorkspaceDirectory: Sendable {
    let url: URL

    init(prefix: String) throws {
        let sanitizedPrefix = prefix
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedPrefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}
