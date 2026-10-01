import Foundation

private final class SerializedPeriodicBackupQueue: @unchecked Sendable {
    typealias Operation = @Sendable () throws -> Date?
    typealias Completion = @MainActor @Sendable (Result<Date?, Error>) -> Void

    private let queue = DispatchQueue(
        label: "GrantDataStore.backup.periodic",
        qos: .utility
    )
    private let lock = NSLock()
    private let activeGroup = DispatchGroup()
    private var pendingOperation: Operation?
    private var pendingCompletions: [Completion] = []
    private var isDrainScheduled = false

    func enqueue(
        operation: @escaping Operation,
        completion: @escaping Completion
    ) {
        lock.lock()
        pendingOperation = operation
        pendingCompletions.append(completion)
        if !isDrainScheduled {
            isDrainScheduled = true
            activeGroup.enter()
            queue.async { [self] in drain() }
        }
        lock.unlock()
    }

    func waitUntilIdle(timeout: TimeInterval?) -> Bool {
        guard let timeout else {
            activeGroup.wait()
            return true
        }
        return activeGroup.wait(timeout: .now() + timeout) == .success
    }

    private func drain() {
        while true {
            let operation: Operation
            let completions: [Completion]
            lock.lock()
            guard let pendingOperation else {
                isDrainScheduled = false
                lock.unlock()
                activeGroup.leave()
                return
            }
            operation = pendingOperation
            completions = pendingCompletions
            self.pendingOperation = nil
            pendingCompletions.removeAll(keepingCapacity: true)
            lock.unlock()

            let result = Result { try operation() }
            DispatchQueue.main.async {
                for completion in completions {
                    completion(result)
                }
            }
        }
    }
}

extension GrantDataStore {
    nonisolated private static let periodicBackupQueue = SerializedPeriodicBackupQueue()

    func restoreArchivedRecord(id: String) {
        let previousSnapshot = currentSnapshot()
        let previousArchived: [ArchivedRecordEnvelope]
        do {
            previousArchived = try loadArchivedRecords()
        } catch {
            loadError = error.localizedDescription
            notice = StoreNotice(message: language.text("Could not read the archive.", "Kunde inte läsa arkivet."), tone: .error)
            return
        }
        guard let index = previousArchived.firstIndex(where: { $0.id == id }) else { return }
        var updatedArchived = previousArchived
        let envelope = updatedArchived.remove(at: index)

        do {
            let scope = try restoreArchivedEnvelope(envelope)
            refreshState(for: scope)
            // Archive first (see restoreSnapshotAndArchivedRecords): a failed
            // archive write then leaves nothing half saved.
            try saveArchivedRecords(updatedArchived)
            try persist(persistenceSet(for: scope), includeBackup: false)
            enqueuePeriodicBackupSnapshotIfNeeded(now: Date())
            registerArchiveUndo(
                snapshot: previousSnapshot,
                archivedRecords: previousArchived,
                actionName: language.text("Restore archived record", "Återställ arkiverad post")
            )
            notice = StoreNotice(message: language.text("Restored archived record.", "Återställde arkiverad post."), tone: .success)
            loadError = nil
        } catch {
            restoreSnapshotWithoutUndo(previousSnapshot)
            let primaryError = error
            handlePersistenceRollback(
                primaryError: primaryError,
                context: "Archive restore"
            ) {
                try saveArchivedRecords(previousArchived)
            }
            stopPersistenceSaving()
            notice = StoreNotice(message: language.text("Could not restore archived record.", "Kunde inte återställa arkiverad post."), tone: .error)
        }
    }

    func permanentlyDeleteArchivedRecord(id: String) {
        let previousSnapshot = currentSnapshot()
        let previousArchived: [ArchivedRecordEnvelope]
        do {
            previousArchived = try loadArchivedRecords()
        } catch {
            loadError = error.localizedDescription
            notice = StoreNotice(message: language.text("Could not read the archive.", "Kunde inte läsa arkivet."), tone: .error)
            return
        }
        guard previousArchived.contains(where: { $0.id == id }) else { return }
        let updatedArchived = previousArchived.filter { $0.id != id }

        do {
            try saveArchivedRecords(updatedArchived)
            enqueuePeriodicBackupSnapshotIfNeeded(now: Date())
            registerArchiveUndo(
                snapshot: previousSnapshot,
                archivedRecords: previousArchived,
                actionName: language.text("Delete archived record", "Ta bort arkiverad post")
            )
            notice = StoreNotice(message: language.text("Deleted archived record.", "Tog bort arkiverad post."), tone: .success)
            loadError = nil
        } catch {
            let primaryError = error
            handlePersistenceRollback(
                primaryError: primaryError,
                context: "Permanent archive deletion"
            ) {
                try saveArchivedRecords(previousArchived)
            }
            notice = StoreNotice(message: language.text("Could not delete archived record.", "Kunde inte ta bort arkiverad post."), tone: .error)
        }
    }

    /// Bulk counterpart of permanentlyDeleteArchivedRecord: one archive save
    /// and one undo registration for the whole selection, so a multi-delete
    /// can be reverted as a single step.
    func permanentlyDeleteArchivedRecords(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let previousSnapshot = currentSnapshot()
        let previousArchived: [ArchivedRecordEnvelope]
        do {
            previousArchived = try loadArchivedRecords()
        } catch {
            loadError = error.localizedDescription
            notice = StoreNotice(message: language.text("Could not read the archive.", "Kunde inte läsa arkivet."), tone: .error)
            return
        }
        let updatedArchived = previousArchived.filter { !ids.contains($0.id) }
        let deletedCount = previousArchived.count - updatedArchived.count
        guard deletedCount > 0 else { return }

        do {
            try saveArchivedRecords(updatedArchived)
            enqueuePeriodicBackupSnapshotIfNeeded(now: Date())
            registerArchiveUndo(
                snapshot: previousSnapshot,
                archivedRecords: previousArchived,
                actionName: language.text("Delete archived records", "Ta bort arkiverade poster")
            )
            notice = StoreNotice(
                message: language.text(
                    "Deleted \(deletedCount) archived records.",
                    "Tog bort \(deletedCount) arkiverade poster."
                ),
                tone: .success
            )
            loadError = nil
        } catch {
            let primaryError = error
            handlePersistenceRollback(
                primaryError: primaryError,
                context: "Permanent archive deletion"
            ) {
                try saveArchivedRecords(previousArchived)
            }
            notice = StoreNotice(message: language.text("Could not delete archived records.", "Kunde inte ta bort arkiverade poster."), tone: .error)
        }
    }

    func restoreFromBackup(directoryURL: URL) {
        restoreFromBackupAsync(directoryURL: directoryURL)
    }

    func createForcedBackupSnapshot(prefix: String) throws {
        let attachmentRevision = Self.currentManagedAttachmentRevision()
        let snapshot = currentSnapshot()
        try Self.createForcedBackupSnapshot(
            snapshot: snapshot,
            archivedRecords: try loadArchivedRecords(),
            receivedGrantsData: try loadReceivedGrantsData(),
            prefix: prefix,
            expectedAttachmentRevision: attachmentRevision
        )
        backupSnapshotsCache = try? Self.loadBackupSnapshots()
    }

    func applySnapshotToMemoryAndStorage(
        _ snapshot: Snapshot,
        restorePayload: RestorePayload?,
        expectedReport: BackupHealthReport,
        includeBackup: Bool = false
    ) throws {
        guard flushAllPendingPersistenceIfNeeded() else {
            throw CocoaError(.fileWriteUnknown)
        }
        restoreSnapshotWithoutUndo(snapshot)
        // Verify against the caller's expectation BEFORE migration mutates
        // the state; the post-migration report alone is self-referential
        // and would pass even if migration dropped records.
        try Self.verifyRestoreReport(
            Self.healthReport(for: currentSnapshot()),
            matches: expectedReport
        )
        // Inline-certificate extraction must not run here: this path
        // migrates BEFORE the attachment restore transaction, which would
        // wipe the freshly extracted files. Restore clears the maintenance
        // markers, so extraction runs safely on the next launch instead.
        _ = migrateRecordsIfNeeded(extractInlineReviewCertificates: false)
        let effectivePayload = RestorePayload(
            snapshot: currentSnapshot(),
            archivedRecords: restorePayload?.archivedRecords,
            receivedGrantsData: restorePayload?.receivedGrantsData,
            sourceDirectoryURL: restorePayload?.sourceDirectoryURL,
            replacesArchivedRecords: restorePayload?.replacesArchivedRecords ?? false,
            replacesReceivedGrantsData: restorePayload?.replacesReceivedGrantsData ?? false,
            attachmentRestoreMode: restorePayload?.attachmentRestoreMode ?? .preserveExisting
        )
        let persistedCache = try Self.writeRestorePayloadToStorage(
            effectivePayload,
            expectedReport: Self.healthReport(for: effectivePayload.snapshot)
        )
        persistedDocumentCache = persistedCache

        if includeBackup {
            enqueuePeriodicBackupSnapshotIfNeeded(now: Date())
        }
    }

    func enqueuePeriodicBackupSnapshotIfNeeded(
        now: Date = Date(),
        updatesPersistenceStatus: Bool = true
    ) {
        let attachmentRevision = Self.currentManagedAttachmentRevision()
        let snapshot = currentSnapshot()
        let archivedRecords: [ArchivedRecordEnvelope]
        let receivedGrantsData: Data?
        do {
            archivedRecords = try loadArchivedRecords()
            receivedGrantsData = try loadReceivedGrantsData()
        } catch {
            surfacePeriodicBackupFailure(error)
            return
        }

        // Captured while the caller's storage environment is in effect. A test
        // or tool that changes FOOTPRINT_STORAGE_DIRECTORY between enqueue and
        // execution must not write its snapshot into a different rotation:
        // that once left a tiny test-data backup as the "newest verified"
        // candidate in the real backups directory. The captured roots are
        // passed all the way through the write so no callee re-resolves them
        // mid-operation; the guard below stays as defense-in-depth.
        let expectedStorageRoot = Self.storageDirectory
        let expectedBackupsDirectory = Self.backupsDirectory
        Self.periodicBackupQueue.enqueue(
            operation: {
                guard Self.storageDirectory == expectedStorageRoot else { return nil }
                return try Self.writePeriodicBackupSnapshotIfNeeded(
                    snapshot: snapshot,
                    archivedRecords: archivedRecords,
                    receivedGrantsData: receivedGrantsData,
                    now: now,
                    expectedAttachmentRevision: attachmentRevision,
                    storageRoot: expectedStorageRoot,
                    backupsDirectory: expectedBackupsDirectory
                )
            },
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case let .success(backupDate):
                    self.backupSnapshotsCache = try? Self.loadBackupSnapshots()
                    if updatesPersistenceStatus, let backupDate {
                        self.recordPeriodicBackupCompletion(at: backupDate)
                    }
                case let .failure(error):
                    self.surfacePeriodicBackupFailure(error)
                }
            }
        )
    }

    @discardableResult
    func waitForPendingPeriodicBackup(timeout: TimeInterval? = nil) -> Bool {
        let didFinish = Self.waitForPendingPeriodicBackupWork(timeout: timeout)
        if !didFinish {
            surfacePeriodicBackupFailure(
                NSError(
                    domain: "FootprintBackup",
                    code: 82,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Pending automatic backup did not finish before the timeout."
                    ]
                )
            )
        }
        return didFinish
    }

    nonisolated static func waitForPendingPeriodicBackupWork(
        timeout: TimeInterval? = nil
    ) -> Bool {
        periodicBackupQueue.waitUntilIdle(timeout: timeout)
    }

    private func surfacePeriodicBackupFailure(_ error: Error) {
        loadError = error.localizedDescription
        notice = StoreNotice(
            message: language.text(
                "Automatic backup failed.",
                "Automatisk backup misslyckades."
            ),
            tone: .error
        )
    }

    nonisolated private static func writePeriodicBackupSnapshotIfNeeded(
        snapshot: Snapshot,
        archivedRecords: [ArchivedRecordEnvelope],
        receivedGrantsData: Data?,
        now: Date,
        expectedAttachmentRevision: UInt64,
        storageRoot: URL,
        backupsDirectory: URL
    ) throws -> Date? {
        try Self.createPrivateBackupDirectory(at: backupsDirectory)
        let existing = try Self.loadBackupSnapshots(in: backupsDirectory)
        let newest = existing.filter(\.isVerified).max(by: { $0.date < $1.date })
        if let newest, now.timeIntervalSince(newest.date) < 15 * 60 {
            try Self.pruneBackupSnapshots(existing, now: now)
            return nil
        }

        let snapshotDirectory = backupsDirectory.appendingPathComponent(Self.backupFolderName(for: now), isDirectory: true)
        try Self.writeVerifiedBackupPackage(
            snapshot: snapshot,
            archivedRecords: archivedRecords,
            receivedGrantsData: receivedGrantsData,
            finalDirectory: snapshotDirectory,
            expectedAttachmentRevision: expectedAttachmentRevision,
            storageRoot: storageRoot
        )

        var snapshots = existing
        snapshots.append(BackupSnapshot(url: snapshotDirectory, date: now, isVerified: true))
        try Self.pruneBackupSnapshots(snapshots, now: now)
        return now
    }
}
