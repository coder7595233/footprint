import Foundation

extension GrantDataStore {
    private struct BackgroundRestoreResult: Sendable {
        let previousSnapshot: Snapshot
        let previousArchivedRecords: [ArchivedRecordEnvelope]
        let previousReceivedGrantsData: Data?
        // nil when restoring out of a blocked-writes state: the in-memory
        // "previous" state is empty then, and a safety backup or rollback
        // built from it would overwrite the damaged database with nothing.
        let safetyBackupURL: URL?
        let restoredPayload: RestorePayload
    }

    func loadBackupHealthSummaryAsync(
        onSuccess: @escaping @MainActor @Sendable (String) -> Void
    ) {
        flushPendingPersistenceIfNeeded()
        let language = language
        performBackgroundOperation(
            startMessage: language.text("Checking backup health…", "Kontrollerar backuphälsa…"),
            failureMessage: language.text("Backup health check failed.", "Kontroll av backuphälsa misslyckades."),
            work: {
                try Self.backupHealthSummaryText(language: language)
            },
            onSuccess: onSuccess
        )
    }

    func loadBackupRestorePreviewSummaryAsync(
        for directoryURL: URL,
        onSuccess: @escaping @MainActor @Sendable (String) -> Void
    ) {
        flushPendingPersistenceIfNeeded()
        let language = language
        performBackgroundOperation(
            startMessage: language.text("Preparing backup preview…", "Förbereder backupförhandsvisning…"),
            failureMessage: language.text("Backup preview failed.", "Backupförhandsvisning misslyckades."),
            work: {
                try Self.backupRestorePreviewSummaryText(language: language, directoryURL: directoryURL)
            },
            onSuccess: onSuccess
        )
    }

    func restoreFromBackupAsync(
        directoryURL: URL,
        onSuccess: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        guard flushAllPendingPersistenceIfNeeded() else {
            notice = StoreNotice(
                message: language.text(
                    "Restore was stopped because pending changes could not be saved.",
                    "Återställningen stoppades eftersom väntande ändringar inte kunde sparas."
                ),
                tone: .error
            )
            return
        }
        let attachmentRevision = Self.currentManagedAttachmentRevision()
        let restoringWhileWritesBlocked = storageWritesBlockedByLoadFailure
        let previousSnapshot = currentSnapshot()
        var loadedArchivedRecords: [ArchivedRecordEnvelope] = []
        var loadedReceivedGrantsData: Data?
        do {
            loadedArchivedRecords = try loadArchivedRecords()
            loadedReceivedGrantsData = try loadReceivedGrantsData()
        } catch {
            guard restoringWhileWritesBlocked else {
                loadError = error.localizedDescription
                notice = StoreNotice(
                    message: language.text(
                        "Restore was stopped because the current auxiliary data could not be read.",
                        "Återställningen stoppades eftersom nuvarande kompletterande data inte kunde läsas."
                    ),
                    tone: .error
                )
                return
            }
            // The unreadable auxiliary data is the very condition the user is
            // recovering from; restore must stay available.
            loadedArchivedRecords = []
            loadedReceivedGrantsData = nil
        }
        let previousArchivedRecords = loadedArchivedRecords
        let previousReceivedGrantsData = loadedReceivedGrantsData
        let language = language

        performBackgroundOperation(
            startMessage: language.text("Restoring backup…", "Återställer backup…"),
            failureMessage: language.text("Could not restore backup.", "Kunde inte återställa backup."),
            work: {
                let payload = try Self.decodeRestorePayload(from: directoryURL)
                // With writes blocked the in-memory state is empty; a safety
                // backup of it would be an empty decoy that rollback or
                // auto-recovery could later treat as real data.
                let safetyBackupURL = restoringWhileWritesBlocked ? nil : try Self.createForcedBackupSnapshot(
                    snapshot: previousSnapshot,
                    archivedRecords: previousArchivedRecords,
                    receivedGrantsData: previousReceivedGrantsData,
                    prefix: "pre-restore",
                    expectedAttachmentRevision: attachmentRevision
                )
                return BackgroundRestoreResult(
                    previousSnapshot: previousSnapshot,
                    previousArchivedRecords: previousArchivedRecords,
                    previousReceivedGrantsData: previousReceivedGrantsData,
                    safetyBackupURL: safetyBackupURL,
                    restoredPayload: payload
                )
            }
        ) { result in
            var didStartCommit = false
            do {
                try self.requireUnchangedDataForDestructiveCommit(
                    snapshot: result.previousSnapshot,
                    archivedRecords: result.previousArchivedRecords,
                    receivedGrantsData: result.previousReceivedGrantsData,
                    tolerateUnreadableAuxiliaryData: restoringWhileWritesBlocked
                )
                if restoringWhileWritesBlocked, self.sqliteStore == nil {
                    // The database that blocked the load may still be
                    // unopenable. Preserve it in quarantine, let the restore
                    // start against a fresh file, and bring the live handle
                    // back so post-restore reads and writes work.
                    if FileManager.default.fileExists(atPath: Self.databaseURL.path),
                       (try? SQLiteDocumentStore(url: Self.databaseURL)) == nil {
                        _ = try Self.quarantineCurrentSQLiteStoreBeforeRecovery(
                            reason: "manual restore over an unopenable database"
                        )
                    }
                    guard self.reopenLiveSQLiteStoreAfterRecovery() else {
                        throw NSError(domain: "FootprintRestore", code: 71, userInfo: [
                            NSLocalizedDescriptionKey:
                                "The database could not be reopened for restore.",
                        ])
                    }
                }
                // Keep the revision check, atomic storage replacement and
                // memory publish in one MainActor turn. This is intentionally
                // a short, exclusive commit barrier after off-main preflight.
                didStartCommit = true
                var persistedCache = try Self.writeRestorePayloadToStorage(
                    result.restoredPayload,
                    expectedReport: Self.healthReport(for: result.restoredPayload.snapshot)
                )
                self.restoreSnapshotWithoutUndo(result.restoredPayload.snapshot)
                if self.migrateRecordsIfNeeded() {
                    let migratedPayload = RestorePayload(
                        snapshot: self.currentSnapshot(),
                        archivedRecords: result.restoredPayload.archivedRecords,
                        receivedGrantsData: result.restoredPayload.receivedGrantsData,
                        sourceDirectoryURL: nil,
                        replacesArchivedRecords: result.restoredPayload.replacesArchivedRecords,
                        replacesReceivedGrantsData: result.restoredPayload.replacesReceivedGrantsData
                    )
                    persistedCache = try Self.writeRestorePayloadToStorage(
                        migratedPayload,
                        expectedReport: Self.healthReport(for: migratedPayload.snapshot)
                    )
                }
                self.completeBackupRestore(
                    result: result,
                    persistedCache: persistedCache,
                    restoredWhileWritesBlocked: restoringWhileWritesBlocked,
                    onSuccess: onSuccess
                )
            } catch {
                let originalError = error
                // Without a safety backup (blocked-writes recovery) there is
                // nothing safe to roll back to; the SQLite transaction has
                // already rolled itself back and the damaged database is
                // preserved as it was.
                if didStartCommit, let safetyBackupURL = result.safetyBackupURL {
                    do {
                        let rollbackPayload = try Self.decodeRestorePayload(from: safetyBackupURL)
                        let rollbackCache = try Self.writeRestorePayloadToStorage(
                            rollbackPayload,
                            expectedReport: Self.healthReport(for: result.previousSnapshot)
                        )
                        self.restoreSnapshotWithoutUndo(result.previousSnapshot)
                        self.persistedDocumentCache = rollbackCache
                    } catch {
                        let rollbackError = error
                        self.handlePersistenceRollback(
                            primaryError: originalError,
                            context: "Backup restore"
                        ) {
                            throw rollbackError
                        }
                    }
                }
                if self.loadError == nil {
                    self.loadError = originalError.localizedDescription
                }
                self.notice = StoreNotice(
                    message: self.language.text(
                        "Restore was cancelled because local data changed or the commit could not be verified.",
                        "Återställningen avbröts eftersom lokala data ändrades eller committen inte kunde verifieras."
                    ),
                    tone: .error
                )
            }
        }
    }

    private func completeBackupRestore(
        result: BackgroundRestoreResult,
        persistedCache: [String: Data],
        restoredWhileWritesBlocked: Bool,
        onSuccess: @escaping @MainActor @Sendable () -> Void
    ) {
        persistedDocumentCache = persistedCache
        backupSnapshotsCache = try? Self.loadBackupSnapshots()
        if restoredWhileWritesBlocked {
            // Storage now holds verified restored data, so the load-failure
            // write gate no longer protects anything — left set, every
            // autosave after this point would silently fail until relaunch.
            // No undo registration: the pre-restore memory was empty, and
            // undoing into it would wipe the restored data.
            storageWritesBlockedByLoadFailure = false
            blocksSQLitePrimaryReads = false
            appendStartupDiagnostic("restore: cleared load-failure write gate after verified restore")
        } else {
            // The restore also replaced the archived-records document; a plain
            // snapshot undo would bring back core data but leave the backup's
            // archive contents in place.
            registerArchiveUndo(
                snapshot: result.previousSnapshot,
                archivedRecords: result.previousArchivedRecords,
                actionName: language.text("Restore backup", "Återställ backup")
            )
        }
        notice = StoreNotice(
            message: language.text(
                "Restored backup and verified stored data.",
                "Återställde backup och verifierade lagrade data."
            ),
            tone: .success
        )
        loadError = nil
        onSuccess()
    }
}
