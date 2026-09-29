import Foundation

/// Serializes the short filesystem boundary between attachment mutations and
/// backup staging. The staged files are immutable hard links (or copied
/// fallbacks), so hashing and package publication can continue off-lock.
final class ManagedAttachmentRevisionCoordinator: @unchecked Sendable {
    static let shared = ManagedAttachmentRevisionCoordinator()

    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var latestPublishedBackupByParentPath: [String: URL] = [:]

    private init() {}

    func currentRevision() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return revision
    }

    func performMutation<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        let result = try body()
        revision &+= 1
        return result
    }

    func stageSnapshot<T>(
        expectedRevision: UInt64?,
        _ body: () throws -> T
    ) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if let expectedRevision, expectedRevision != revision {
            throw NSError(
                domain: "FootprintAttachmentRevision",
                code: 409,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Managed attachments changed while the backup snapshot was being prepared. The backup was not published."
                ]
            )
        }
        return try body()
    }

    func latestPublishedBackup(in parentDirectory: URL) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return latestPublishedBackupByParentPath[parentDirectory.standardizedFileURL.path]
    }

    func recordPublishedBackup(_ backupURL: URL) {
        lock.lock()
        latestPublishedBackupByParentPath[
            backupURL.deletingLastPathComponent().standardizedFileURL.path
        ] = backupURL
        lock.unlock()
    }

    func clearPublishedBackupCache() {
        lock.lock()
        latestPublishedBackupByParentPath.removeAll()
        lock.unlock()
    }
}

extension GrantDataStore {
    nonisolated static func currentManagedAttachmentRevision() -> UInt64 {
        ManagedAttachmentRevisionCoordinator.shared.currentRevision()
    }

    nonisolated static func performManagedAttachmentMutation<T>(
        _ body: () throws -> T
    ) throws -> T {
        try ManagedAttachmentRevisionCoordinator.shared.performMutation(body)
    }
}
