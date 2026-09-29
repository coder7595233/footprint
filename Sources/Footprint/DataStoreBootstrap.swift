import CryptoKit
import Foundation

extension GrantDataStore {
    struct StorageReadinessSnapshot {
        let hasSQLiteDatabase: Bool
        let sqliteDocumentCount: Int
        let missingRequiredSQLiteDocuments: [String]
        let backupCount: Int
        let hasCurrentStartupMaintenanceMarker: Bool

        var isSQLiteComplete: Bool {
            hasSQLiteDatabase && missingRequiredSQLiteDocuments.isEmpty
        }
    }

    private struct MaintenanceMarkers: Codable, Equatable {
        var startup: String? = nil
        var deferredLaunch: String? = nil
        var bundledJournalMetrics: String? = nil
    }

    /// Decodes the ~8 MB publication_journals document on a background queue
    /// concurrently with the main-thread decode of every other document. That
    /// single decode dominated the pre-first-frame bootstrap; running it in
    /// parallel shrinks bootstrap wall-clock to roughly max(journals, rest)
    /// while keeping fully synchronous load semantics — the join happens
    /// before publications are applied, and any failure falls back to the
    /// original synchronous decode path.
    private final class ParallelJournalsDecode: @unchecked Sendable {
        private let group = DispatchGroup()
        private var outcome: Result<[PublicationJournal], Error>?

        init(databaseURL: URL) {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { self.group.leave() }
                do {
                    // A separate WAL connection: reads run concurrently with
                    // any bootstrap writes on the primary connection.
                    let sqliteStore = try SQLiteDocumentStore(url: databaseURL)
                    guard let journals = try sqliteStore.load(
                        [PublicationJournal].self,
                        named: "publication_journals"
                    ) else {
                        throw NSError(domain: "Footprint", code: 23, userInfo: [
                            NSLocalizedDescriptionKey: "Required SQLite document 'publication_journals' is missing.",
                        ])
                    }
                    self.outcome = .success(journals)
                } catch {
                    self.outcome = .failure(error)
                }
            }
        }

        // group.leave() → wait() provides the happens-before edge on outcome.
        func waitForJournals() -> Result<[PublicationJournal], Error> {
            group.wait()
            return outcome ?? .failure(NSError(domain: "Footprint", code: 23, userInfo: [
                NSLocalizedDescriptionKey: "Parallel journals decode produced no result.",
            ]))
        }
    }

    func bootstrap() {
        blocksSQLitePrimaryReads = true
        do {
            try Self.ensureStorageDirectory()
            Self.hardenStorageFilePermissions()
            try Self.recoverInterruptedRestoreIfNeeded()
            let hasSQLiteDatabase = FileManager.default.fileExists(atPath: Self.databaseURL.path)
            let startupStorageReadiness = Self.storageReadinessSnapshot()
            appendStartupDiagnostic("bootstrap:start hasSQLiteDatabase=\(hasSQLiteDatabase) sqliteComplete=\(startupStorageReadiness.isSQLiteComplete) missingSQLiteDocuments=\(startupStorageReadiness.missingRequiredSQLiteDocuments.joined(separator: ",")) backups=\(startupStorageReadiness.backupCount)")
            guard hasSQLiteDatabase else {
                loadError = "SQLite database is required. JSON startup migration has been removed."
                notice = StoreNotice(
                    message: language.text(
                        "SQLite database is required. No JSON startup migration will be used.",
                        "SQLite-databas krävs. Ingen JSON-startmigrering används."
                    ),
                    tone: .error
                )
                appendStartupDiagnostic("bootstrap:missingRequiredSQLiteDatabase")
                return
            }

            var didMigrate = false
            let parallelJournalsDecode = ParallelJournalsDecode(databaseURL: Self.databaseURL)
            do {
                try reloadFromSQLite()
                appendStartupDiagnostic("bootstrap:loaded applications via sqlite count=\(applications.count)")
                if let storedVersion = metadata.schemaVersion,
                   storedVersion > DataSourceMetadata.currentSchemaVersion {
                    blocksSQLitePrimaryReads = false
                    loadError = language.text(
                        "This database was created by a newer Footprint version (schema \(storedVersion); supported \(DataSourceMetadata.currentSchemaVersion)). It is open without write access.",
                        "Databasen skapades av en nyare Footprint-version (schema \(storedVersion); stöd upp till \(DataSourceMetadata.currentSchemaVersion)). Den är öppnad utan skrivåtkomst."
                    )
                    notice = StoreNotice(message: loadError ?? "", tone: .error)
                    appendStartupDiagnostic(
                        "bootstrap:futureSchemaReadOnly stored=\(storedVersion) supported=\(DataSourceMetadata.currentSchemaVersion)"
                    )
                    return
                }
                try retireCalendarVerticalNotesIfNeeded()
                try reloadPublicationResources(parallelJournalsDecode: parallelJournalsDecode)
                blocksSQLitePrimaryReads = false
                appendStartupDiagnostic("bootstrap:loaded publications via sqlite authors=\(publicationAuthors.count) journals=\(publicationJournals.count) records=\(publicationRecords.count)")
                let hasCurrentMaintenanceMarker = Self.hasCurrentStartupMaintenanceMarker()
                let shouldRunMaintenance = !hasCurrentMaintenanceMarker
                let hasCurrentJournalMetricMarker = Self.hasCurrentBundledJournalMetricMarker()
                if !hasCurrentJournalMetricMarker, Self.journalCatalogCandidateURLs().isEmpty {
                    // No journal catalog in Reference/ or in the bundle:
                    // nothing to merge. The marker stays unwritten so the
                    // merge runs once a catalog is put in place.
                    appendStartupDiagnostic("bootstrap:bundledJournalMetrics skipped catalog=missing")
                } else if !hasCurrentJournalMetricMarker {
                    let metricStartedAt = CFAbsoluteTimeGetCurrent()
                    let preBundledJournalMetricMaintenanceSnapshot = currentSnapshot()
                    let mergedNorwegianRankings = mergeMissingBundledNorwegianJournalRankings()
                    let mergedClarivateMetrics = mergeMissingBundledClarivate2025JournalMetrics()
                    if mergedNorwegianRankings > 0 || mergedClarivateMetrics > 0 {
                        do {
                            try Self.createForcedBackupSnapshot(
                                snapshot: preBundledJournalMetricMaintenanceSnapshot,
                                archivedRecords: try loadArchivedRecords(),
                                receivedGrantsData: try loadReceivedGrantsData(),
                                prefix: "pre-bundled-journal-metric-maintenance"
                            )
                        } catch {
                            try? reloadPublicationResources()
                            appendStartupDiagnostic("bootstrap:preBundledJournalMetricMaintenanceBackup failed error=\(error.localizedDescription)")
                            loadError = error.localizedDescription
                            notice = StoreNotice(
                                message: language.text(
                                    "Journal metric update was paused because the safety backup could not be created.",
                                    "Uppdatering av tidskriftsmetrik pausades eftersom säkerhetsbackupen inte kunde skapas."
                                ),
                                tone: .error
                            )
                            return
                        }
                        try persist(.publicationJournals)
                    }
                    try Self.writeCurrentBundledJournalMetricMarker()
                    appendStartupDiagnostic(
                        String(
                            format: "bootstrap:bundledJournalMetrics norwegian=%ld clarivate2025=%ld total_ms=%.2f",
                            mergedNorwegianRankings,
                            mergedClarivateMetrics,
                            (CFAbsoluteTimeGetCurrent() - metricStartedAt) * 1000
                        )
                    )
                } else {
                    // Persist the backward-compatible promotion from the
                    // existing startup marker so subsequent launches need
                    // only one marker read.
                    try? Self.writeCurrentBundledJournalMetricMarker()
                    appendStartupDiagnostic("bootstrap:bundledJournalMetrics skipped marker=current")
                }
                appendStartupDiagnostic("bootstrap:maintenance shouldRun=\(shouldRunMaintenance) hasMarker=\(hasCurrentMaintenanceMarker)")
                if shouldRunMaintenance {
                    do {
                        try createForcedBackupSnapshot(prefix: "pre-startup-maintenance-v\(Self.startupMaintenanceVersion)")
                        appendStartupDiagnostic("bootstrap:preMaintenanceBackup completed")
                    } catch {
                        appendStartupDiagnostic("bootstrap:preMaintenanceBackup failed error=\(error.localizedDescription)")
                        loadError = error.localizedDescription
                        notice = StoreNotice(
                            message: language.text(
                                "Startup maintenance was paused because the safety backup could not be created.",
                                "Startunderhåll pausades eftersom säkerhetsbackupen inte kunde skapas."
                            ),
                            tone: .error
                        )
                        return
                    }
                    let preMaintenanceSnapshot = currentSnapshot()
                    let verificationBefore = relationshipMetrics()
                    let didRepairReferences = repairStoredReferenceIntegrity()
                    // F21: organizations created with an id made from the
                    // name get a UUID; every reference follows.
                    let repairedOrganizationIDs = repairLegacyOrganizationIDs()
                    appendStartupDiagnostic("bootstrap:organizationIDRepair repaired=\(repairedOrganizationIDs.count)")
                    didMigrate = migrateRecordsIfNeeded()
                    let verificationReport = migrationVerificationReport(
                        before: verificationBefore,
                        phase: "startup-maintenance-v\(Self.startupMaintenanceVersion)"
                    )
                    let didUpdateVerificationReport = updateLastMigrationVerificationReport(verificationReport)
                    appendStartupDiagnostic("bootstrap:post-migrate didMigrate=\(didMigrate) didRepairReferences=\(didRepairReferences) verificationPassed=\(verificationReport.passed) authors=\(publicationAuthors.count) journals=\(publicationJournals.count) records=\(publicationRecords.count)")
                    guard verificationReport.passed else {
                        restoreSnapshotWithoutUndo(preMaintenanceSnapshot)
                        throw NSError(
                            domain: "FootprintMigration",
                            code: 91,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Startup maintenance verification failed. The existing database was not changed; a safety backup is available."
                            ]
                        )
                    }
                    if didMigrate || didRepairReferences || !repairedOrganizationIDs.isEmpty || didUpdateVerificationReport {
                        try persistAll()
                        appendStartupDiagnostic("bootstrap:persistAll completed")
                    }
                    do {
                        try Self.writeCurrentStartupMaintenanceMarker()
                        appendStartupDiagnostic("bootstrap:maintenance markerWritten=true")
                    } catch {
                        appendStartupDiagnostic("bootstrap:maintenance markerWriteFailed error=\(error.localizedDescription)")
                    }
                } else {
                    appendStartupDiagnostic("bootstrap:maintenance skipped using existing persisted state")
                }
                // Round 7: linked researcher rows show the official names of
                // their organization and unit (one correct spelling). Runs on
                // every start; changes and saves only what differs.
                applyOfficialOrganizationNamesAtLaunch()
                // F49: where each media PDF is looked for; runs on every start.
                logMediaPDFLookupForDiagnostics()
                compactDatabaseIfNeeded()
                // Captured on main before detaching; see sweep doc comment.
                let sweepStorageRoot = Self.storageDirectory
                let sweepBackupsRoot = Self.backupsDirectory
                Task.detached(priority: .utility) {
                    Self.sweepStaleWorkingDirectories(
                        storageRoot: sweepStorageRoot,
                        backupsRoot: sweepBackupsRoot
                    )
                }
                scheduleLaunchPresentationCachePrewarm()
            } catch {
                if recoverFromLatestBackupAfterLoadFailure(error, hadExistingLocalData: true) {
                    appendStartupDiagnostic("bootstrap:recoveredFromBackupAfterLoadFailure originalError=\(error.localizedDescription)")
                    return
                }

                if blocksSQLitePrimaryReads {
                    // The load itself failed: block writes so a save cannot
                    // overwrite good on-disk data with empty state.
                    storageWritesBlockedByLoadFailure = true
                    loadError = error.localizedDescription
                    notice = StoreNotice(
                        message: language.text(
                            "Could not load SQLite data, and automatic backup recovery also failed.",
                            "Kunde inte läsa SQLite-data, och automatisk återhämtning från backup misslyckades också."
                        ),
                        tone: .error
                    )
                    appendStartupDiagnostic("bootstrap:failedWithSQLiteData error=\(error.localizedDescription) writesBlocked=true")
                } else {
                    // Data loaded and was verified; a later maintenance step
                    // failed. Writes stay enabled and maintenance retries on
                    // the next launch.
                    loadError = error.localizedDescription
                    notice = StoreNotice(
                        message: language.text(
                            "Startup maintenance could not complete. Your data is loaded; maintenance retries on the next launch.",
                            "Startunderhållet kunde inte slutföras. Dina data är laddade; underhållet försöker igen vid nästa start."
                        ),
                        tone: .error
                    )
                    appendStartupDiagnostic("bootstrap:maintenanceFailed error=\(error.localizedDescription)")
                }
            }
        } catch {
            if FileManager.default.fileExists(atPath: Self.databaseURL.path) {
                storageWritesBlockedByLoadFailure = true
            }
            loadError = error.localizedDescription
            appendStartupDiagnostic("bootstrap:outer failure error=\(error.localizedDescription) writesBlocked=\(storageWritesBlockedByLoadFailure)")
        }
    }

    private func recoverFromLatestBackupAfterLoadFailure(_ originalError: Error, hadExistingLocalData: Bool) -> Bool {
        guard hadExistingLocalData else { return false }
        guard Self.confirmsUnusableSQLiteStore(liveStore: sqliteStore) else {
            appendStartupDiagnostic(
                "bootstrap:automaticRecoverySkipped reason=load-failure-without-confirmed-sqlite-corruption error=\(originalError.localizedDescription)"
            )
            return false
        }

        do {
            let candidates = try backupSnapshots()
                .filter(\.isVerified)
                .sorted(by: { $0.date > $1.date })
            guard !candidates.isEmpty else { return false }
            let quarantineURL = try Self.quarantineCurrentSQLiteStoreBeforeRecovery(
                reason: originalError.localizedDescription
            )
            appendStartupDiagnostic(
                "bootstrap:recoveryQuarantineCreated path=\(quarantineURL.path)"
            )
            // The damaged file is quarantined; the recovery apply path below
            // (archived records, migration, persistence) needs a live handle
            // to the fresh database that the restore write will populate.
            guard reopenLiveSQLiteStoreAfterRecovery() else { return false }
            var recoveryErrors: [String] = []
            for backup in candidates {
                do {
                    let payload = try Self.decodeRestorePayload(from: backup.url)
                    let expectedReport = Self.healthReport(for: payload.snapshot)
                    try applySnapshotToMemoryAndStorage(
                        payload.snapshot,
                        restorePayload: payload,
                        expectedReport: expectedReport,
                        includeBackup: false
                    )

                    loadError = "\(language.text("Recovered from a verified backup after load failure.", "Återhämtade en verifierad backup efter laddningsfel.")) \(originalError.localizedDescription)"
                    blocksSQLitePrimaryReads = false
                    notice = StoreNotice(
                        message: language.text(
                            "Recovered a verified backup automatically after a load failure.",
                            "Återhämtade automatiskt en verifierad backup efter ett laddningsfel."
                        ),
                        tone: .info
                    )
                    return true
                } catch {
                    recoveryErrors.append("\(backup.url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            loadError = "\(originalError.localizedDescription) | \(recoveryErrors.joined(separator: " | "))"
            return false
        } catch {
            loadError = "\(originalError.localizedDescription) | \(error.localizedDescription)"
            return false
        }
    }

    // Best-effort: compaction failure must never break startup.
    private func compactDatabaseIfNeeded() {
        // The conditional VACUUM of a ≥16 MB file used to run synchronously
        // before the first frame. It runs on a detached task with its own
        // connection now; if a concurrent write makes it fail with BUSY it
        // simply retries on the next launch. The database URL is captured
        // before detaching so a storage-environment change cannot redirect
        // the VACUUM to a different store.
        let databaseURL = Self.databaseURL
        Task.detached(priority: .utility) { [weak self] in
            let message: String?
            do {
                let sqliteStore = try SQLiteDocumentStore(url: databaseURL)
                let result = try sqliteStore.compactIfNeeded()
                message = result.didCompact
                    ? String(
                        format: "bootstrap:vacuum before_bytes=%ld after_bytes=%ld freelist_ratio=%.2f",
                        result.fileBytesBefore,
                        result.fileBytesAfter,
                        result.freelistRatioBefore
                    )
                    : nil
            } catch {
                message = "bootstrap:vacuum failed error=\(error.localizedDescription)"
            }
            if let message {
                await MainActor.run { [weak self] in
                    self?.appendStartupDiagnostic(message)
                }
            }
        }
    }

    /// True only when the on-disk database is demonstrably unusable: either a
    /// confirmed integrity/quick-check failure on the live connection, or -
    /// when the file was so damaged that no connection could be opened at all
    /// (previously this skipped recovery and left the user on an error
    /// screen) - an independent probe connection that also fails to open or
    /// fails its health check. A file that opens cleanly on the probe is left
    /// alone: the load failure then has a different cause than corruption.
    nonisolated private static func confirmsUnusableSQLiteStore(liveStore: SQLiteDocumentStore?) -> Bool {
        func hasConfirmedFailure(_ store: SQLiteDocumentStore) -> Bool {
            guard let health = try? store.storageHealthSummary() else { return false }
            return health.integrityCheck.isConfirmedFailure || health.quickCheck.isConfirmedFailure
        }
        if let liveStore {
            return hasConfirmedFailure(liveStore)
        }
        guard let probeStore = try? SQLiteDocumentStore(url: databaseURL) else {
            return FileManager.default.fileExists(atPath: databaseURL.path)
        }
        return hasConfirmedFailure(probeStore)
    }

    nonisolated static func quarantineCurrentSQLiteStoreBeforeRecovery(
        reason: String,
        now: Date = Date()
    ) throws -> URL {
        let fileManager = FileManager.default
        try ensureBackupDirectory()
        let quarantineRoot = backupsDirectory
            .appendingPathComponent("Recovery Quarantine", isDirectory: true)
        try fileManager.createDirectory(
            at: quarantineRoot,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let quarantineDirectory = quarantineRoot.appendingPathComponent(
            "\(backupFolderName(for: now))-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: quarantineDirectory,
            withIntermediateDirectories: false,
            attributes: nil
        )

        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: quarantineDirectory)
            }
        }

        var copiedFileNames: [String] = []
        for sourceURL in [databaseURL, databaseWALURL, databaseSHMURL] {
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let destinationURL = quarantineDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            copiedFileNames.append(sourceURL.lastPathComponent)
        }
        guard copiedFileNames.contains(databaseURL.lastPathComponent) else {
            throw NSError(
                domain: "FootprintRecovery",
                code: 78,
                userInfo: [NSLocalizedDescriptionKey: "The live SQLite database could not be quarantined before recovery."]
            )
        }

        let quarantineMetadata = [
            "createdAt": ISO8601DateFormatter().string(from: now),
            "reason": reason,
            "files": copiedFileNames.sorted().joined(separator: ","),
        ]
        try encode(
            quarantineMetadata,
            to: quarantineDirectory.appendingPathComponent("quarantine.json")
        )
        completed = true
        // Quarantine must also clear the live location: recovery and restore
        // reopen the database path afterwards, and a damaged file left in
        // place would keep every reopen failing. The copies above are the
        // preserved evidence; removal only runs once they are all in place.
        for sourceURL in [databaseURL, databaseWALURL, databaseSHMURL]
        where fileManager.fileExists(atPath: sourceURL.path) {
            try fileManager.removeItem(at: sourceURL)
        }
        return quarantineDirectory
    }

    @discardableResult
    private func mergeMissingBundledNorwegianJournalRankings() -> Int {
        let bundledJournals = Self.bundledPublicationJournals()
        guard !bundledJournals.isEmpty, !publicationJournals.isEmpty else { return 0 }

        let bundledByID = Dictionary(uniqueKeysWithValues: bundledJournals.map { ($0.id, $0) })
        var bundledByISSN: [String: PublicationJournal] = [:]
        var bundledByName: [String: PublicationJournal] = [:]

        for journal in bundledJournals {
            for value in [journal.issn, journal.eissn] {
                let key = Self.normalizedJournalISSN(value)
                if !key.isEmpty, bundledByISSN[key] == nil {
                    bundledByISSN[key] = journal
                }
            }
            let nameKey = Self.normalizedJournalName(journal.name)
            if !nameKey.isEmpty, bundledByName[nameKey] == nil {
                bundledByName[nameKey] = journal
            }
        }

        var updatedJournals = publicationJournals
        var changedCount = 0
        for index in updatedJournals.indices {
            let stored = updatedJournals[index]
            let bundled =
                bundledByID[stored.id]
                ?? Self.firstBundledJournalMatchingISSN(stored, in: bundledByISSN)
                ?? bundledByName[Self.normalizedJournalName(stored.name)]

            guard let bundled else { continue }

            let bundledMetrics = Self.norwegianRankingMetrics(bundled, minimumYear: 2019)
            guard !bundledMetrics.isEmpty
            else { continue }

            var journalChanged = false
            if let latestMetric = bundledMetrics.max(by: { $0.year < $1.year }),
               updatedJournals[index].norwegianLevel.trimmingCharacters(in: .whitespacesAndNewlines) != latestMetric.value {
                updatedJournals[index].norwegianLevel = latestMetric.value
                journalChanged = true
            }

            if let existingIndex = updatedJournals[index].rankingRows.firstIndex(where: { $0.kind == .norwegianList }) {
                var existing = updatedJournals[index].rankingRows[existingIndex]
                for bundledMetric in bundledMetrics {
                    if let metricIndex = existing.yearlyMetrics.firstIndex(where: { $0.year == bundledMetric.year }) {
                        if existing.yearlyMetrics[metricIndex].value != bundledMetric.value
                            || existing.yearlyMetrics[metricIndex].quartile != bundledMetric.quartile {
                            existing.yearlyMetrics[metricIndex] = bundledMetric
                            journalChanged = true
                        }
                    } else {
                        existing.yearlyMetrics.append(bundledMetric)
                        journalChanged = true
                    }
                }
                existing.yearlyMetrics.sort { $0.year > $1.year }
                updatedJournals[index].rankingRows[existingIndex] = existing
            } else {
                let bundledRowID = bundled.rankingRows.first(where: { $0.kind == .norwegianList })?.id ?? UUID().uuidString
                updatedJournals[index].rankingRows.append(
                    JournalRankingRow(
                        id: bundledRowID,
                        kind: .norwegianList,
                        yearlyMetrics: bundledMetrics
                    )
                )
                journalChanged = true
            }

            if journalChanged {
                changedCount += 1
            }
        }

        if changedCount > 0 {
            applyLoadedPublicationState(
                .init(
                    authors: publicationAuthors,
                    journals: updatedJournals,
                    records: publicationRecords
                )
            )
        }
        return changedCount
    }

    @discardableResult
    private func mergeMissingBundledClarivate2025JournalMetrics() -> Int {
        let bundledJournals = Self.bundledPublicationJournals()
        guard !bundledJournals.isEmpty, !publicationJournals.isEmpty else { return 0 }

        var bundledByTitle: [String: Set<Int>] = [:]
        var bundledByISSN: [String: Set<Int>] = [:]
        var bundledByEISSN: [String: Set<Int>] = [:]

        for (index, journal) in bundledJournals.enumerated() where Self.hasClarivate2025Metrics(journal) {
            let titleKey = Self.normalizedClarivateJournalTitle(journal.name)
            if !titleKey.isEmpty {
                bundledByTitle[titleKey, default: []].insert(index)
            }
            for key in Self.normalizedJournalISSNValues(journal.issn) where !key.isEmpty {
                bundledByISSN[key, default: []].insert(index)
            }
            for key in Self.normalizedJournalISSNValues(journal.eissn) where !key.isEmpty {
                bundledByEISSN[key, default: []].insert(index)
            }
        }

        var updatedJournals = publicationJournals
        var changedCount = 0

        for index in updatedJournals.indices {
            let stored = updatedJournals[index]
            guard let bundled = Self.bestBundledClarivate2025Match(
                for: stored,
                bundledJournals: bundledJournals,
                bundledByTitle: bundledByTitle,
                bundledByISSN: bundledByISSN,
                bundledByEISSN: bundledByEISSN
            ) else { continue }

            var journalChanged = false
            for bundledRow in bundled.rankingRows where Self.isClarivateKind(bundledRow.kind) {
                guard let bundledMetric = bundledRow.yearlyMetrics.first(where: { metric in
                    metric.year == 2025 && metric.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }) else { continue }

                let rowCategory = normalizedJournalCategory(bundledRow.category)
                if let rowIndex = updatedJournals[index].rankingRows.firstIndex(where: { row in
                    row.kind == bundledRow.kind
                        && normalizedJournalCategory(row.category) == rowCategory
                }) {
                    if Self.upsertClarivateMetric(bundledMetric, into: &updatedJournals[index].rankingRows[rowIndex]) {
                        journalChanged = true
                    }
                } else {
                    updatedJournals[index].rankingRows.append(
                        JournalRankingRow(
                            id: bundledRow.id,
                            kind: bundledRow.kind,
                            category: rowCategory,
                            yearlyMetrics: [bundledMetric]
                        )
                    )
                    journalChanged = true
                }
            }

            if journalChanged {
                updatedJournals[index].normalize()
                changedCount += 1
            }
        }

        if changedCount > 0 {
            applyLoadedPublicationState(
                .init(
                    authors: publicationAuthors,
                    journals: updatedJournals,
                    records: publicationRecords
                )
            )
        }
        return changedCount
    }

    private static func norwegianRankingMetrics(
        _ journal: PublicationJournal,
        minimumYear: Int
    ) -> [JournalYearMetric] {
        var metricsByYear: [Int: JournalYearMetric] = [:]
        for row in journal.rankingRows where row.kind == .norwegianList {
            for metric in row.yearlyMetrics where metric.year >= minimumYear {
                guard !metric.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                metricsByYear[metric.year] = JournalYearMetric(
                    year: metric.year,
                    value: metric.value.trimmingCharacters(in: .whitespacesAndNewlines),
                    quartile: ""
                )
            }
        }
        return metricsByYear.values.sorted { $0.year > $1.year }
    }

    private static func firstBundledJournalMatchingISSN(
        _ journal: PublicationJournal,
        in bundledByISSN: [String: PublicationJournal]
    ) -> PublicationJournal? {
        for value in [journal.issn, journal.eissn] {
            let key = normalizedJournalISSN(value)
            if let bundled = bundledByISSN[key] {
                return bundled
            }
        }
        return nil
    }

    private static func normalizedJournalISSN(_ value: String) -> String {
        value.uppercased().filter { $0.isNumber || $0 == "X" }
    }

    private static func normalizedJournalISSNValues(_ value: String) -> Set<String> {
        Set(
            value
                .components(separatedBy: CharacterSet(charactersIn: ",;/|"))
                .map(normalizedJournalISSN)
                .filter { !$0.isEmpty && $0 != "NA" }
        )
    }

    private static func normalizedJournalName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !["the", "a", "an"].contains($0) }
            .joined(separator: " ")
    }

    private static func normalizedClarivateJournalTitle(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: "and")
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func hasClarivate2025Metrics(_ journal: PublicationJournal) -> Bool {
        journal.rankingRows.contains { row in
            isClarivateKind(row.kind)
                && row.yearlyMetrics.contains { metric in
                    metric.year == 2025 && !metric.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
        }
    }

    private static func isClarivateKind(_ kind: JournalRankingKind) -> Bool {
        switch kind {
        case .clarivateScieJIF, .clarivateScieJCI, .clarivateEsciJIF, .clarivateEsciJCI:
            return true
        case .scimagoSJR, .norwegianList:
            return false
        }
    }

    private static func bestBundledClarivate2025Match(
        for stored: PublicationJournal,
        bundledJournals: [PublicationJournal],
        bundledByTitle: [String: Set<Int>],
        bundledByISSN: [String: Set<Int>],
        bundledByEISSN: [String: Set<Int>]
    ) -> PublicationJournal? {
        var candidateIndices = Set<Int>()
        let titleKey = normalizedClarivateJournalTitle(stored.name)
        if !titleKey.isEmpty {
            candidateIndices.formUnion(bundledByTitle[titleKey] ?? [])
        }
        for key in normalizedJournalISSNValues(stored.issn) {
            candidateIndices.formUnion(bundledByISSN[key] ?? [])
        }
        for key in normalizedJournalISSNValues(stored.eissn) {
            candidateIndices.formUnion(bundledByEISSN[key] ?? [])
        }

        let matches = candidateIndices.compactMap { index -> (journal: PublicationJournal, score: Int)? in
            let bundled = bundledJournals[index]
            let score = clarivateMatchScore(stored, bundled)
            guard score >= 2 else { return nil }
            return (bundled, score)
        }
        guard let bestScore = matches.map(\.score).max() else { return nil }
        let bestMatches = matches.filter { $0.score == bestScore }
        guard bestMatches.count == 1 else { return nil }
        return bestMatches[0].journal
    }

    private static func clarivateMatchScore(_ lhs: PublicationJournal, _ rhs: PublicationJournal) -> Int {
        var score = 0
        let lhsTitle = normalizedClarivateJournalTitle(lhs.name)
        let rhsTitle = normalizedClarivateJournalTitle(rhs.name)
        if !lhsTitle.isEmpty, lhsTitle == rhsTitle {
            score += 1
        }
        if !normalizedJournalISSNValues(lhs.issn).isDisjoint(with: normalizedJournalISSNValues(rhs.issn)) {
            score += 1
        }
        if !normalizedJournalISSNValues(lhs.eissn).isDisjoint(with: normalizedJournalISSNValues(rhs.eissn)) {
            score += 1
        }
        return score
    }

    private static func upsertClarivateMetric(_ metric: JournalYearMetric, into row: inout JournalRankingRow) -> Bool {
        let normalizedMetric = JournalYearMetric(
            year: metric.year,
            value: metric.value.trimmingCharacters(in: .whitespacesAndNewlines),
            quartile: metric.quartile.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let metricIndex = row.yearlyMetrics.firstIndex(where: { $0.year == normalizedMetric.year }) {
            guard row.yearlyMetrics[metricIndex] != normalizedMetric else { return false }
            row.yearlyMetrics[metricIndex] = normalizedMetric
        } else {
            row.yearlyMetrics.append(normalizedMetric)
        }
        row.yearlyMetrics.sort { $0.year > $1.year }
        return true
    }

    private func reloadFromSQLite() throws {
        guard let sqliteStore else {
            throw NSError(domain: "Footprint", code: 21, userInfo: [
                NSLocalizedDescriptionKey: "SQLite storage is unavailable.",
            ])
        }
        applyLoadedPersistentState(try Self.loadPersistentStateFromSQLite(sqliteStore))
    }

    /// After a load failure the live handle is nil or bound to a damaged
    /// file. Once the damaged database has been quarantined (or rewritten by
    /// a verified restore) the handle can be reopened so archived records,
    /// persistence and diagnostics work again without a relaunch.
    @discardableResult
    func reopenLiveSQLiteStoreAfterRecovery() -> Bool {
        guard let reopened = try? SQLiteDocumentStore(url: Self.databaseURL) else {
            appendStartupDiagnostic("recovery:reopenLiveSQLiteStore failed")
            return false
        }
        sqliteStore = reopened
        appendStartupDiagnostic("recovery:reopenLiveSQLiteStore ok")
        return true
    }

    nonisolated static func loadPersistentStateFromSQLite(_ sqliteStore: SQLiteDocumentStore) throws -> LoadedPersistentState {
        let loadedMetadata = Self.metadataByApplyingAppSettings(
            Self.metadataByApplyingCalendarDocuments(
                try requireSQLiteDocument(DataSourceMetadata.self, named: "metadata", from: sqliteStore),
                travelRecords: try requireSQLiteDocument([CalendarTravelRecord].self, named: "calendar_travel_records", from: sqliteStore),
                accommodationRecords: try requireSQLiteDocument([CalendarAccommodationRecord].self, named: "calendar_accommodation_records", from: sqliteStore),
                meetingRecords: try requireSQLiteDocument([CalendarMeetingRecord].self, named: "calendar_meeting_records", from: sqliteStore),
                verticalNoteRecords: try sqliteStore.load([CalendarVerticalNoteRecord].self, named: "calendar_vertical_note_records")
            ),
            settings: try requireSQLiteDocument(AppSettingsSnapshot.self, named: "app_settings", from: sqliteStore)
        )
        let loadedOrganizations = try Self.loadRequiredOrganizationRecords(from: sqliteStore)
        return .init(
            applications: try requireSQLiteDocument([GrantApplication].self, named: "applications", from: sqliteStore),
            metadata: loadedMetadata,
            organizations: Self.organizationsByMergingStoredCongressRecords(
                try requireSQLiteDocument([StoredCongressRecord].self, named: "congresses", from: sqliteStore),
                into: loadedOrganizations
            ),
            managers: [],
            projects: try Self.loadRequiredProjectRecords(from: sqliteStore),
            teachingCourses: try requireSQLiteDocument([TeachingCourse].self, named: "teaching_courses", from: sqliteStore),
            teachingComponents: try requireSQLiteDocument([TeachingComponent].self, named: "teaching_components", from: sqliteStore),
            teachingFormats: try requireSQLiteDocument([TeachingFormatOption].self, named: "teaching_formats", from: sqliteStore),
            teachingAssignments: try requireSQLiteDocument([TeachingAssignment].self, named: "teaching_assignments", from: sqliteStore),
            doctoralCandidates: try requireSQLiteDocument([DoctoralCandidateRecord].self, named: "doctoral_candidates", from: sqliteStore),
            cvPersonalResume: try requireSQLiteDocument(CVPersonalResume.self, named: "cv_personal_resume", from: sqliteStore),
            cvConferenceContributions: try requireSQLiteDocument([CVConferenceContribution].self, named: "cv_conference_contributions", from: sqliteStore),
            cvMediaAppearances: try requireSQLiteDocument([CVMediaAppearance].self, named: "cv_media_appearances", from: sqliteStore),
            cvReviewEntries: try requireSQLiteDocument([CVReviewEntry].self, named: "cv_review_entries", from: sqliteStore),
            cvOtherPublications: try requireSQLiteDocument([CVOtherPublicationEntry].self, named: "cv_other_publications", from: sqliteStore)
        )
    }

    /// Calendar vertical notes had no editor or renderer. Preserve any records
    /// from older databases in the recoverable archive, then remove their
    /// retired document. Stable archive IDs make this safe to retry after an
    /// interrupted launch.
    private func retireCalendarVerticalNotesIfNeeded() throws {
        guard let sqliteStore,
              let notes = try sqliteStore.load([CalendarVerticalNoteRecord].self, named: "calendar_vertical_note_records") else {
            return
        }

        guard !notes.isEmpty else {
            try sqliteStore.deleteDocuments(named: ["calendar_vertical_note_records"])
            clearRetiredCalendarVerticalNotesFromMetadata()
            try persist(.metadata)
            appendStartupDiagnostic("bootstrap:retiredCalendarVerticalNotes archived=0")
            return
        }

        try createForcedBackupSnapshot(prefix: "pre-retire-calendar-vertical-notes-v1")
        var archived = try loadArchivedRecords()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        for note in notes {
            let archiveID = "retired-calendar-vertical-note:\(note.id)"
            guard !archived.contains(where: { $0.id == archiveID }) else { continue }
            archived.insert(
                ArchivedRecordEnvelope(
                    id: archiveID,
                    kind: "retired-calendar-vertical-note",
                    title: note.text.trimmedOrNil ?? language.text("Untitled calendar note", "Namnlös kalendernotering"),
                    deletedAt: GrantParsing.timestampNow(),
                    payload: try encoder.encode(note),
                    relatedDocumentStates: nil
                ),
                at: 0
            )
        }
        try saveArchivedRecords(archived)
        try sqliteStore.deleteDocuments(named: ["calendar_vertical_note_records"])
        clearRetiredCalendarVerticalNotesFromMetadata()
        try persist(.metadata)
        appendStartupDiagnostic("bootstrap:retiredCalendarVerticalNotes archived=\(notes.count)")
    }

    private func reloadPublicationResources(
        parallelJournalsDecode: ParallelJournalsDecode? = nil
    ) throws {
        guard let sqliteStore,
              try sqliteStore.containsDocument(named: "publication_records") else {
            throw NSError(domain: "Footprint", code: 22, userInfo: [
                NSLocalizedDescriptionKey: "Required SQLite publication documents are missing.",
            ])
        }
        let storedJournals: [PublicationJournal]
        if let parallelJournalsDecode {
            let joinStartedAt = CFAbsoluteTimeGetCurrent()
            switch parallelJournalsDecode.waitForJournals() {
            case let .success(journals):
                storedJournals = journals
                appendStartupDiagnostic(String(
                    format: "bootstrap:journals-parallel-join wait_ms=%.1f count=%ld",
                    (CFAbsoluteTimeGetCurrent() - joinStartedAt) * 1000,
                    journals.count
                ))
            case let .failure(error):
                // Fall back to the original synchronous decode so error
                // behavior stays byte-for-byte identical to the serial path.
                appendStartupDiagnostic("bootstrap:journals-parallel-join failed error=\(error.localizedDescription)")
                storedJournals = try Self.requireSQLiteDocument([PublicationJournal].self, named: "publication_journals", from: sqliteStore)
            }
        } else {
            storedJournals = try Self.requireSQLiteDocument([PublicationJournal].self, named: "publication_journals", from: sqliteStore)
        }
        // The first window used to wait ~1.6 s for the journal lookup/metric
        // pass; bootstrap now defers it to a detached build (with a scheduled
        // synchronous full refresh as fallback) and runs crossrefs-only here.
        journalLookupBuildDeferredForBootstrap = true
        let decodeStartedAt = CFAbsoluteTimeGetCurrent()
        let loadedAuthors = try Self.requireSQLiteDocument([PublicationAuthor].self, named: "publication_authors", from: sqliteStore)
        let loadedRecords = try Self.requireSQLiteDocument([PublicationRecord].self, named: "publication_records", from: sqliteStore)
        let applyStartedAt = CFAbsoluteTimeGetCurrent()
        applyLoadedPublicationState(
            .init(
                authors: loadedAuthors,
                journals: storedJournals,
                records: loadedRecords
            ),
            normalizeLoadedCollections: false,
            deferExpensiveRefreshWork: true
        )
        appendStartupDiagnostic(String(
            format: "bootstrap:publication-phase decode_ms=%.1f apply_ms=%.1f",
            (applyStartedAt - decodeStartedAt) * 1000,
            (CFAbsoluteTimeGetCurrent() - applyStartedAt) * 1000
        ))
        beginBootstrapJournalLookupCacheBuild()
        beginBootstrapPersistedJournalCachePrewarm()
    }

    nonisolated static func requireSQLiteDocument<T: Decodable>(
        _ type: T.Type,
        named key: String,
        from sqliteStore: SQLiteDocumentStore
    ) throws -> T {
        guard let document = try sqliteStore.load(type, named: key) else {
            throw NSError(domain: "Footprint", code: 23, userInfo: [
                NSLocalizedDescriptionKey: "Required SQLite document '\(key)' is missing.",
            ])
        }
        return document
    }

    nonisolated static func bundledResourceURL(named fileName: String, subdirectory: String? = nil) throws -> URL {
        let fileManager = FileManager.default
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent()
        let appContentsDirectory = Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        var baseCandidates: [URL] = []

        func appendBase(_ url: URL?) {
            guard let url else { return }
            let standardized = url.standardizedFileURL
            guard !baseCandidates.contains(standardized) else { return }
            baseCandidates.append(standardized)
        }

        for bundleName in ["Footprint_Footprint", "GrantDesk_GrantDesk"] {
            appendBase(Bundle.main.url(forResource: bundleName, withExtension: "bundle"))
            appendBase(Bundle.main.resourceURL?.appendingPathComponent("\(bundleName).bundle", isDirectory: true))
            appendBase(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("\(bundleName).bundle", isDirectory: true))
            appendBase(executableDirectory.appendingPathComponent("\(bundleName).bundle", isDirectory: true))
            appendBase(executableDirectory.deletingLastPathComponent().appendingPathComponent("Resources", isDirectory: true).appendingPathComponent("\(bundleName).bundle", isDirectory: true))

            for bundle in Bundle.allBundles + Bundle.allFrameworks {
                appendBase(bundle.resourceURL?.appendingPathComponent("\(bundleName).bundle", isDirectory: true))
                if bundle.bundleURL.lastPathComponent == "\(bundleName).bundle" {
                    appendBase(bundle.bundleURL)
                }
            }
        }

        appendBase(Bundle.main.resourceURL)
        appendBase(appContentsDirectory.appendingPathComponent("Resources", isDirectory: true))
        appendBase(executableDirectory)
#if DEBUG
        // Source-tree lookup is useful for local SwiftPM development, but a
        // release build must never execute a same-named script from a
        // caller-controlled working directory when a bundled resource is
        // missing.
        appendBase(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/Footprint/Resources", isDirectory: true))
        appendBase(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/Footprint/Resources/Data", isDirectory: true))
        appendBase(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/Footprint/Resources/Scripts", isDirectory: true))
#endif

        for baseURL in baseCandidates {
            let candidates = [
                subdirectory.map { baseURL.appendingPathComponent($0, isDirectory: true).appendingPathComponent(fileName) },
                baseURL.appendingPathComponent(fileName),
            ].compactMap { $0 }

            for candidate in candidates {
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        throw NSError(domain: "Footprint", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Missing bundled resource \(fileName).",
        ])
    }

    nonisolated static let journalCatalogCompressedFileName = "publication_journals.json.zlib"
    nonisolated static let journalCatalogFileName = "publication_journals.json"

    /// Folder in the storage directory where the user keeps reference data
    /// that must not ship with the public app, such as the journal catalog
    /// with licensed journal metrics.
    nonisolated static var referenceDataDirectory: URL {
        storageDirectory.appendingPathComponent("Reference", isDirectory: true)
    }

    /// Journal catalog files in lookup order: the user's Reference folder
    /// first, then a copy bundled with the app (public builds carry none).
    /// Each entry says whether the file is raw-deflate compressed.
    nonisolated static func journalCatalogCandidateURLs() -> [(url: URL, isCompressed: Bool)] {
        let fileManager = FileManager.default
        var candidates: [(url: URL, isCompressed: Bool)] = []
        let reference = referenceDataDirectory
        for (fileName, isCompressed) in [(journalCatalogCompressedFileName, true), (journalCatalogFileName, false)] {
            let url = reference.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: url.path) {
                candidates.append((url, isCompressed))
            }
        }
        if let url = try? bundledResourceURL(named: journalCatalogCompressedFileName) {
            candidates.append((url, true))
        }
        if let url = try? bundledResourceURL(named: journalCatalogFileName) {
            candidates.append((url, false))
        }
        return candidates
    }

    /// The journal catalog used to fill in missing journal metrics. Empty
    /// when no catalog is present; the user's stored journals are unaffected.
    static func bundledPublicationJournals() -> [PublicationJournal] {
        for candidate in journalCatalogCandidateURLs() {
            guard let data = try? Data(contentsOf: candidate.url) else { continue }
            let json: Data
            if candidate.isCompressed {
                // Minified and raw-deflate compressed
                // (15.6 MB pretty-printed -> ~1 MB).
                guard let decompressed = try? (data as NSData).decompressed(using: .zlib) as Data else { continue }
                json = decompressed
            } else {
                json = data
            }
            if let journals = try? JSONDecoder().decode([PublicationJournal].self, from: json) {
                return journals
            }
        }
        return []
    }

    nonisolated static func supportScriptURL(named fileName: String) throws -> URL {
#if DEBUG
        if let url = try? bundledResourceURL(named: fileName, subdirectory: "Scripts") {
            return url
        }
        return try bundledResourceURL(named: fileName)
#else
        // The resource bundle lives in Contents/Resources, where code signing
        // allows it. SwiftPM's Bundle.module only looks next to the .app, so it
        // is the fallback for runs outside a packaged app.
        let resources = Bundle.main.url(forResource: "Footprint_Footprint", withExtension: "bundle")
            .flatMap(Bundle.init(url:))
            ?? Bundle.module
        let candidates = [
            resources.url(forResource: fileName, withExtension: nil, subdirectory: "Scripts"),
            resources.url(forResource: fileName, withExtension: nil),
        ].compactMap { $0 }

        for candidate in candidates {
            let values = try candidate.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            if values.isRegularFile == true, values.isSymbolicLink != true {
                return candidate
            }
        }

        throw NSError(domain: "Footprint", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Missing trusted bundled support script \(fileName).",
        ])
#endif
    }

    nonisolated static func runPython(scriptURL: URL, arguments: [String]) throws -> String {
        try PythonScriptRunner.run(scriptURL: scriptURL, arguments: arguments)
    }

    nonisolated private static let appSupportFolderName = "Footprint"
    nonisolated private static let legacyAppSupportFolderName = "GrantDesk"
    nonisolated static let defaultDatabaseFileName = "footprint.sqlite"
    // 19: one-time settings step for home organization, calendar categories
    // and the application salary calculator (migrateHomeOrganizationSettingsIfNeeded).
    // 20: one-time step that ticks the course checkbox "Klinisk undervisning"
    // (migrateClinicalTeachingCheckboxForRound7).
    // 21: the values that used to be built in (standard programme, faculty,
    // home region, salary calculator rates) are stored in the data. That step
    // ran in the version before this one; the number is kept in step so the
    // maintenance does not run again for data it has already handled.
    // 22: round 8, the old no-overhead checkbox on a salary calculator
    // becomes the funder setting Max OH (runRound8OneTimeDataMigrations).
    // 23: round 8, Max OH on a grant provider becomes its OH rule
    // (migrateFunderMaxOverheadToOverheadRuleForRound8).
    private static let startupMaintenanceVersion = 23
    private static let deferredLaunchMaintenanceVersion = 4
    private static let bundledJournalMetricVersion = 1
    private static let maintenanceMarkersStorageKey = "maintenance_markers"
    nonisolated private static let shareModeStorageFolderName = "Footprint Share"
    nonisolated static let requiredSQLiteDocumentKeys = FootprintStorageContract.requiredSQLiteDocumentKeys

    nonisolated static var isShareMode: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "FootprintShareMode") as? Bool) ?? false
    }

    nonisolated private static var configuredAppSupportFolderName: String {
        if let configured = (Bundle.main.object(forInfoDictionaryKey: "FootprintStorageFolderName") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return configured
        }
        return isShareMode ? shareModeStorageFolderName : appSupportFolderName
    }

    nonisolated static var configuredDatabaseFileName: String {
        if let configured = (Bundle.main.object(forInfoDictionaryKey: "FootprintDatabaseFileName") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return configured
        }
        return defaultDatabaseFileName
    }

    nonisolated private static var overriddenStorageDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment

        if let rawOverride = environment["FOOTPRINT_STORAGE_DIRECTORY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawOverride.isEmpty {
            return URL(fileURLWithPath: rawOverride, isDirectory: true)
        }

        // F34: `swift test` does not set Xcode's variable, so test mode is
        // recognised on several signals (see TestProcessDetection).
        if TestProcessDetection.isRunningTests {
            let temporaryRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("FootprintTests", isDirectory: true)
            return temporaryRoot.appendingPathComponent(
                "\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
        }

        return nil
    }

    /// The folders that hold the user's real data. A test process must never
    /// resolve its storage to one of them.
    nonisolated static var realStorageRoots: [URL] {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return [appSupportFolderName, shareModeStorageFolderName, legacyAppSupportFolderName, configuredAppSupportFolderName]
            .map { applicationSupport.appendingPathComponent($0, isDirectory: true) }
    }

    nonisolated static var storageDirectory: URL {
        let resolved = overriddenStorageDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(configuredAppSupportFolderName, isDirectory: true)
        // F34, last line of defence: stopping the test run is recoverable,
        // writing test data into the real database is not.
        if TestProcessDetection.isRunningTests,
           TestProcessDetection.isInside(resolved, anyOf: realStorageRoots) {
            fatalError("F34: a test run tried to use the real Footprint storage at \(resolved.path). Nothing was written.")
        }
        return resolved
    }

    nonisolated private static var legacyStorageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(legacyAppSupportFolderName, isDirectory: true)
    }

    nonisolated static var startupDiagnosticsURL: URL {
        storageDirectory.appendingPathComponent("startup_diagnostics.log")
    }

    nonisolated static var performanceDiagnosticsURL: URL {
        storageDirectory.appendingPathComponent("performance_diagnostics.log")
    }

    nonisolated static var startupMaintenanceMarkerURL: URL {
        storageDirectory.appendingPathComponent("startup_maintenance_marker.txt")
    }

    nonisolated static var startupMaintenanceMarkerDefaultsKey: String {
        "footprint.startup_maintenance_marker.\(storageDirectory.path)"
    }

    nonisolated static var deferredLaunchMaintenanceMarkerDefaultsKey: String {
        "footprint.deferred_launch_maintenance_marker.\(storageDirectory.path)"
    }

    nonisolated static var deferredLaunchMaintenanceMarkerURL: URL {
        storageDirectory.appendingPathComponent("deferred_launch_maintenance_marker.txt")
    }

    nonisolated static var backupsDirectory: URL {
        storageDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    nonisolated static var databaseURL: URL {
        storageDirectory.appendingPathComponent(configuredDatabaseFileName)
    }

    nonisolated static var databaseWALURL: URL {
        storageDirectory.appendingPathComponent("\(configuredDatabaseFileName)-wal")
    }

    nonisolated static var databaseSHMURL: URL {
        storageDirectory.appendingPathComponent("\(configuredDatabaseFileName)-shm")
    }

    nonisolated static var publicationPDFsDirectory: URL {
        storageDirectory.appendingPathComponent("Publication PDFs", isDirectory: true)
    }

    nonisolated static var mediaAppearancePDFsDirectory: URL {
        storageDirectory.appendingPathComponent("Media Appearance PDFs", isDirectory: true)
    }

    nonisolated static var mediaAppearanceFilesDirectory: URL {
        storageDirectory.appendingPathComponent("Media Appearance Files", isDirectory: true)
    }

    nonisolated static var conferenceContributionPDFsDirectory: URL {
        storageDirectory.appendingPathComponent("Conference Contribution PDFs", isDirectory: true)
    }

    nonisolated static var doctoralCandidatePDFsDirectory: URL {
        storageDirectory.appendingPathComponent("Doctoral Candidate PDFs", isDirectory: true)
    }

    nonisolated static var reviewCertificatePDFsDirectory: URL {
        storageDirectory.appendingPathComponent("Review Certificate PDFs", isDirectory: true)
    }

    nonisolated static func resolvePublicationPDFURL(publicationID: String?, finalPDFPath: String?, finalPDFFilename: String?) -> URL? {
        if let publicationID = publicationID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
           let managedURL = try? validatedManagedAttachmentURL(
               root: publicationPDFsDirectory,
               id: publicationID,
               fileExtension: "pdf"
           ) {
            if FileManager.default.fileExists(atPath: managedURL.path) {
                return managedURL
            }
            if let legacyURL = legacyManagedAttachmentURL(root: publicationPDFsDirectory, id: publicationID, fileExtension: "pdf") {
                return legacyURL
            }
        }

        if let directPath = finalPDFPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directPath.isEmpty {
            let directURL = absoluteAttachmentURL(fromStored: directPath) ?? URL(fileURLWithPath: directPath)
            if FileManager.default.fileExists(atPath: directURL.path),
               (try? FileManager.default.destinationOfSymbolicLink(atPath: directURL.path)) == nil {
                return directURL
            }
        }

        let normalizedPath = finalPDFPath?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let fallbackFilename =
            normalizedPath.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nonEmpty }
            ?? finalPDFFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fallbackFilename,
              isSafeAttachmentLeafName(fallbackFilename) else { return nil }

        let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let candidateDirectories = [
            publicationPDFsDirectory,
            applicationSupportDirectory
                .appendingPathComponent(appSupportFolderName, isDirectory: true)
                .appendingPathComponent("Publication PDFs", isDirectory: true),
            legacyStorageDirectory
                .appendingPathComponent("Publication PDFs", isDirectory: true)
        ]

        for directory in candidateDirectories {
            guard let candidateURL = try? validatedContainedAttachmentURL(
                directory.appendingPathComponent(fallbackFilename),
                within: directory
            ) else { continue }
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    /// `legacyStoredFilenames`: the stored names of the record's files from
    /// the earlier Media attachment UI. They lie in "Media Appearance Files"
    /// and are the last place looked, so a PDF that was only ever saved there
    /// is still found (and copied into place at the next start).
    nonisolated static func resolveCVMediaAppearancePDFURL(
        mediaAppearanceID: String?,
        pdfPath: String?,
        pdfFilename: String?,
        legacyStoredFilenames: [String] = []
    ) -> URL? {
        if let mediaAppearanceID = mediaAppearanceID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
           let managedURL = try? validatedManagedAttachmentURL(
               root: mediaAppearancePDFsDirectory,
               id: mediaAppearanceID,
               fileExtension: "pdf"
           ) {
            if FileManager.default.fileExists(atPath: managedURL.path) {
                return managedURL
            }
            if let legacyURL = legacyManagedAttachmentURL(root: mediaAppearancePDFsDirectory, id: mediaAppearanceID, fileExtension: "pdf") {
                return legacyURL
            }
            // F49: a PDF saved under the record's id in the older folder.
            if let olderFolderURL = resolveLegacyMediaAppearanceFileURL(
                storedFilename: "\(managedAttachmentFileStem(for: mediaAppearanceID)).pdf"
            ) {
                return olderFolderURL
            }
        }

        if let directPath = pdfPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directPath.isEmpty {
            let directURL = absoluteAttachmentURL(fromStored: directPath) ?? URL(fileURLWithPath: directPath)
            if FileManager.default.fileExists(atPath: directURL.path),
               (try? FileManager.default.destinationOfSymbolicLink(atPath: directURL.path)) == nil {
                return directURL
            }
        }

        let normalizedPath = pdfPath?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let fallbackFilename =
            normalizedPath.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nonEmpty }
            ?? pdfFilename?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let fallbackFilename, isSafeAttachmentLeafName(fallbackFilename) {
            let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let candidateDirectories = [
                mediaAppearancePDFsDirectory,
                applicationSupportDirectory
                    .appendingPathComponent(appSupportFolderName, isDirectory: true)
                    .appendingPathComponent("Media Appearance PDFs", isDirectory: true),
                legacyStorageDirectory
                    .appendingPathComponent("Media Appearance PDFs", isDirectory: true),
                mediaAppearanceFilesDirectory
            ]

            for directory in candidateDirectories {
                guard let candidateURL = try? validatedContainedAttachmentURL(
                    directory.appendingPathComponent(fallbackFilename),
                    within: directory
                ) else { continue }
                if FileManager.default.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }
            }
        }

        for storedFilename in legacyStoredFilenames {
            if let legacyURL = resolveLegacyMediaAppearanceFileURL(storedFilename: storedFilename) {
                return legacyURL
            }
        }

        return nil
    }

    nonisolated static func resolveCVReviewCertificatePDFURL(reviewEntryID: String?, certificatePath: String?, certificateFilename: String?) -> URL? {
        if let reviewEntryID = reviewEntryID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
           let managedURL = try? validatedManagedAttachmentURL(
               root: reviewCertificatePDFsDirectory,
               id: reviewEntryID,
               fileExtension: "pdf"
           ) {
            if FileManager.default.fileExists(atPath: managedURL.path) {
                return managedURL
            }
            if let legacyURL = legacyManagedAttachmentURL(root: reviewCertificatePDFsDirectory, id: reviewEntryID, fileExtension: "pdf") {
                return legacyURL
            }
        }

        if let directPath = certificatePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directPath.isEmpty {
            let directURL = absoluteAttachmentURL(fromStored: directPath) ?? URL(fileURLWithPath: directPath)
            if FileManager.default.fileExists(atPath: directURL.path),
               (try? FileManager.default.destinationOfSymbolicLink(atPath: directURL.path)) == nil {
                return directURL
            }
        }

        let normalizedPath = certificatePath?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let fallbackFilename =
            normalizedPath.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nonEmpty }
            ?? certificateFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fallbackFilename,
              isSafeAttachmentLeafName(fallbackFilename) else { return nil }

        // This directory never existed under the legacy GrantDesk layout,
        // so the managed directory is the only filename candidate.
        guard let candidateURL = try? validatedContainedAttachmentURL(
            reviewCertificatePDFsDirectory.appendingPathComponent(fallbackFilename),
            within: reviewCertificatePDFsDirectory
        ) else { return nil }
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }

        return nil
    }

    nonisolated static func resolveCVConferenceContributionPDFURL(contributionID: String?, pdfPath: String?, pdfFilename: String?) -> URL? {
        if let contributionID = contributionID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
           let managedURL = try? validatedManagedAttachmentURL(
               root: conferenceContributionPDFsDirectory,
               id: contributionID,
               fileExtension: "pdf"
           ) {
            if FileManager.default.fileExists(atPath: managedURL.path) {
                return managedURL
            }
            if let legacyURL = legacyManagedAttachmentURL(root: conferenceContributionPDFsDirectory, id: contributionID, fileExtension: "pdf") {
                return legacyURL
            }
        }

        if let directPath = pdfPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directPath.isEmpty {
            let directURL = absoluteAttachmentURL(fromStored: directPath) ?? URL(fileURLWithPath: directPath)
            if FileManager.default.fileExists(atPath: directURL.path),
               (try? FileManager.default.destinationOfSymbolicLink(atPath: directURL.path)) == nil {
                return directURL
            }
        }

        let normalizedPath = pdfPath?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let fallbackFilename =
            normalizedPath.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nonEmpty }
            ?? pdfFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fallbackFilename,
              isSafeAttachmentLeafName(fallbackFilename) else { return nil }

        let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let candidateDirectories = [
            conferenceContributionPDFsDirectory,
            applicationSupportDirectory
                .appendingPathComponent(appSupportFolderName, isDirectory: true)
                .appendingPathComponent("Conference Contribution PDFs", isDirectory: true),
            legacyStorageDirectory
                .appendingPathComponent("Conference Contribution PDFs", isDirectory: true)
        ]

        for directory in candidateDirectories {
            guard let candidateURL = try? validatedContainedAttachmentURL(
                directory.appendingPathComponent(fallbackFilename),
                within: directory
            ) else { continue }
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    static func storageReadinessSnapshot() -> StorageReadinessSnapshot {
        let fileManager = FileManager.default
        let hasSQLiteDatabase = fileManager.fileExists(atPath: databaseURL.path)
        let sqliteStore = hasSQLiteDatabase ? try? SQLiteDocumentStore(url: databaseURL) : nil
        let missingRequiredSQLiteDocuments = requiredSQLiteDocumentKeys.filter { key in
            guard let sqliteStore else { return true }
            return ((try? sqliteStore.containsDocument(named: key)) ?? false) == false
        }
        let sqliteDocumentCount = (try? sqliteStore?.documentCount()) ?? 0
        let backupCount = (try? loadBackupSnapshots().count) ?? 0
        return StorageReadinessSnapshot(
            hasSQLiteDatabase: hasSQLiteDatabase,
            sqliteDocumentCount: sqliteDocumentCount,
            missingRequiredSQLiteDocuments: missingRequiredSQLiteDocuments,
            backupCount: backupCount,
            hasCurrentStartupMaintenanceMarker: hasCurrentStartupMaintenanceMarker()
        )
    }

    nonisolated static func ensureStorageDirectory() throws {
        try createPrivateDirectory(at: storageDirectory)
    }

    // Storage holds personal data (salaries, personnel, certificates); keep the
    // tree readable by the owning user only instead of the default 0755/0644.
    nonisolated private static func createPrivateDirectory(at url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // createDirectory attributes only apply when the directory is created;
        // normalize pre-existing directories too.
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    /// Removes leftover working directories that a crash or SIGKILL can leave
    /// behind (their `defer`-based cleanup never ran): hidden attachment
    /// snapshot stagings, backup-in-progress stagings, and recovery
    /// quarantines. Only the app's own name patterns are touched, and only
    /// after a generous age margin so nothing in-flight is ever removed.
    // storageRoot/backupsRoot are parameters so callers on detached tasks can
    // capture them while their storage environment is in effect; resolving
    // them at execution time can hit a different root (the test-pollution
    // incident class) — and this sweep deletes files.
    nonisolated static func sweepStaleWorkingDirectories(
        now: Date = Date(),
        storageRoot: URL = GrantDataStore.storageDirectory,
        backupsRoot: URL = GrantDataStore.backupsDirectory
    ) {
        let fileManager = FileManager.default
        let stagingCutoff = now.addingTimeInterval(-2 * 24 * 3600)
        let quarantineCutoff = now.addingTimeInterval(-30 * 24 * 3600)

        func modificationDate(_ url: URL) -> Date? {
            (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        }
        func sweep(directory: URL, cutoff: Date, matches: (String) -> Bool) {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            ) else { return }
            for entry in entries where matches(entry.lastPathComponent) {
                guard let date = modificationDate(entry), date < cutoff else { continue }
                try? fileManager.removeItem(at: entry)
            }
        }

        for root in [storageRoot, backupsRoot] {
            sweep(directory: root, cutoff: stagingCutoff) { name in
                name.hasPrefix(".attachment-snapshot-")
                    || (name.hasPrefix(".") && name.contains(".backup-in-progress-"))
            }
        }
        sweep(
            directory: backupsRoot.appendingPathComponent("Recovery Quarantine", isDirectory: true),
            cutoff: quarantineCutoff
        ) { _ in true }
    }

    nonisolated static func hardenStorageFilePermissions() {
        let fileManager = FileManager.default
        let files = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            startupDiagnosticsURL,
            performanceDiagnosticsURL,
            startupMaintenanceMarkerURL,
        ]
        for url in files where fileManager.fileExists(atPath: url.path) {
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private static func currentStartupMaintenanceMarkerValue() -> String {
        "v\(startupMaintenanceVersion)"
    }

    private static func currentDeferredLaunchMaintenanceMarkerValue() -> String {
        "v\(deferredLaunchMaintenanceVersion)"
    }

    private static func currentBundledJournalMetricMarkerValue() -> String {
        "v\(bundledJournalMetricVersion)"
    }

    private static func legacyMarkerValue(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    private static func storedMaintenanceMarkers() -> MaintenanceMarkers {
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              let sqliteStore = try? SQLiteDocumentStore(url: databaseURL),
              let markers = try? sqliteStore.load(MaintenanceMarkers.self, named: maintenanceMarkersStorageKey) else {
            return MaintenanceMarkers()
        }
        return markers
    }

    private static func maintenanceMarkersIncludingLegacy() -> MaintenanceMarkers {
        var markers = storedMaintenanceMarkers()
        let currentStartup = currentStartupMaintenanceMarkerValue()
        let currentDeferred = currentDeferredLaunchMaintenanceMarkerValue()
        let currentBundledJournalMetrics = currentBundledJournalMetricMarkerValue()

        if markers.startup != currentStartup {
            let fileValue = legacyMarkerValue(at: startupMaintenanceMarkerURL)
            let defaultsValue = UserDefaults.standard.string(forKey: startupMaintenanceMarkerDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if fileValue == currentStartup || defaultsValue == currentStartup {
                markers.startup = currentStartup
            }
        }

        if markers.deferredLaunch != currentDeferred {
            let fileValue = legacyMarkerValue(at: deferredLaunchMaintenanceMarkerURL)
            let defaultsValue = UserDefaults.standard.string(forKey: deferredLaunchMaintenanceMarkerDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if fileValue == currentDeferred || defaultsValue == currentDeferred {
                markers.deferredLaunch = currentDeferred
            }
        }

        // Versions that already carry the current startup marker have run the
        // bundled metric merge on every prior launch. Promote that known-safe
        // state without forcing one more multi-second scan after upgrading.
        if markers.bundledJournalMetrics != currentBundledJournalMetrics,
           markers.startup == currentStartup {
            markers.bundledJournalMetrics = currentBundledJournalMetrics
        }

        return markers
    }

    private static func saveMaintenanceMarkers(_ markers: MaintenanceMarkers) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw NSError(domain: "Footprint", code: 66, userInfo: [
                NSLocalizedDescriptionKey: "SQLite storage is required for maintenance markers.",
            ])
        }
        let sqliteStore = try SQLiteDocumentStore(url: databaseURL)
        try sqliteStore.save(markers, named: maintenanceMarkersStorageKey)
        if let startup = markers.startup {
            UserDefaults.standard.set(startup, forKey: startupMaintenanceMarkerDefaultsKey)
        }
        if let deferredLaunch = markers.deferredLaunch {
            UserDefaults.standard.set(deferredLaunch, forKey: deferredLaunchMaintenanceMarkerDefaultsKey)
        }
    }

    /// Restore deletes the maintenance_markers document so startup/deferred
    /// maintenance re-runs against the restored data, but
    /// maintenanceMarkersIncludingLegacy() would re-promote the old markers
    /// from UserDefaults or the legacy marker files. Both fallbacks must be
    /// cleared in the same operation, or migrations (legacy-task promotion,
    /// certificate extraction) never re-run after restoring an older backup.
    nonisolated static func clearMaintenanceMarkerFallbacks() {
        UserDefaults.standard.removeObject(forKey: startupMaintenanceMarkerDefaultsKey)
        UserDefaults.standard.removeObject(forKey: deferredLaunchMaintenanceMarkerDefaultsKey)
        try? FileManager.default.removeItem(at: startupMaintenanceMarkerURL)
        try? FileManager.default.removeItem(at: deferredLaunchMaintenanceMarkerURL)
    }

    private static func persistCurrentLegacyMaintenanceMarkersIfNeeded() throws {
        let markers = maintenanceMarkersIncludingLegacy()
        guard markers.startup == currentStartupMaintenanceMarkerValue()
            || markers.deferredLaunch == currentDeferredLaunchMaintenanceMarkerValue() else {
            return
        }
        try saveMaintenanceMarkers(markers)
    }

    static func hasCurrentStartupMaintenanceMarker() -> Bool {
        maintenanceMarkersIncludingLegacy().startup == currentStartupMaintenanceMarkerValue()
    }

    static func hasCurrentDeferredLaunchMaintenanceMarker() -> Bool {
        maintenanceMarkersIncludingLegacy().deferredLaunch == currentDeferredLaunchMaintenanceMarkerValue()
    }

    static func hasCurrentBundledJournalMetricMarker() -> Bool {
        maintenanceMarkersIncludingLegacy().bundledJournalMetrics == currentBundledJournalMetricMarkerValue()
    }

    static func writeCurrentStartupMaintenanceMarker() throws {
        try ensureStorageDirectory()
        var markers = maintenanceMarkersIncludingLegacy()
        markers.startup = currentStartupMaintenanceMarkerValue()
        try saveMaintenanceMarkers(markers)
    }

    static func writeCurrentDeferredLaunchMaintenanceMarker() throws {
        try ensureStorageDirectory()
        var markers = maintenanceMarkersIncludingLegacy()
        markers.deferredLaunch = currentDeferredLaunchMaintenanceMarkerValue()
        try saveMaintenanceMarkers(markers)
    }

    static func writeCurrentBundledJournalMetricMarker() throws {
        try ensureStorageDirectory()
        var markers = maintenanceMarkersIncludingLegacy()
        markers.bundledJournalMetrics = currentBundledJournalMetricMarkerValue()
        try saveMaintenanceMarkers(markers)
    }

    nonisolated static func ensureBackupDirectory() throws {
        try createPrivateDirectory(at: backupsDirectory)
    }

    /// Variant for callers that captured the backups directory at enqueue and
    /// must not re-resolve it at execution time.
    nonisolated static func createPrivateBackupDirectory(at url: URL) throws {
        try createPrivateDirectory(at: url)
    }

    static func ensurePublicationPDFsDirectory() throws {
        try createPrivateDirectory(at: publicationPDFsDirectory)
    }

    static func ensureMediaAppearancePDFsDirectory() throws {
        try createPrivateDirectory(at: mediaAppearancePDFsDirectory)
    }

    static func ensureConferenceContributionPDFsDirectory() throws {
        try createPrivateDirectory(at: conferenceContributionPDFsDirectory)
    }

    static func ensureDoctoralCandidatePDFsDirectory() throws {
        try createPrivateDirectory(at: doctoralCandidatePDFsDirectory)
    }

    static func ensureReviewCertificatePDFsDirectory() throws {
        try createPrivateDirectory(at: reviewCertificatePDFsDirectory)
    }

    /// An id made only of ASCII letters, digits, "-", "_" and "." (not "." or
    /// "..") is used as the file name as it is; anything else gets a digest.
    /// The check is on plain ASCII scalars on purpose: records in the user's
    /// data carried "unsafe-id-<digest>" paths for ordinary UUIDs, so the
    /// earlier Foundation-based check rejected them in the packaged app.
    nonisolated static func managedAttachmentFileStem(for id: String) -> String {
        if isPlainAttachmentID(id) {
            return id
        }
        return legacyUnsafeAttachmentFileStem(for: id)
    }

    nonisolated static func isPlainAttachmentID(_ id: String) -> Bool {
        guard !id.isEmpty, id != ".", id != ".." else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true // 0-9 A-Z a-z
            case 0x2D, 0x5F, 0x2E: return true // - _ .
            default: return false
            }
        }
    }

    /// Files saved under "unsafe-id-<digest>" names for ordinary ids are still
    /// found, so a record never loses its file over how the file was named.
    nonisolated static func legacyManagedAttachmentURL(root: URL, id: String, fileExtension: String) -> URL? {
        let root = root.standardizedFileURL
        let candidate = root.appendingPathComponent("\(legacyUnsafeAttachmentFileStem(for: id)).\(fileExtension)")
        guard let validated = try? validatedContainedAttachmentURL(candidate, within: root),
              FileManager.default.fileExists(atPath: validated.path) else { return nil }
        return validated
    }

    nonisolated static func legacyUnsafeAttachmentFileStem(for id: String) -> String {
        let digest = SHA256.hash(data: Data(id.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "unsafe-id-\(digest)"
    }

    nonisolated private static func isSafeAttachmentLeafName(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.contains("%")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    /// F1: attachment locations are stored relative to the storage
    /// directory so they survive a move to another user account.
    nonisolated static func portableAttachmentPath(for url: URL) -> String {
        let standardizedPath = url.standardizedFileURL.path
        let root = storageDirectory.standardizedFileURL.path
        if standardizedPath.hasPrefix(root + "/") {
            return String(standardizedPath.dropFirst(root.count + 1))
        }
        return standardizedPath
    }

    /// F1: resolves a stored location (relative, or absolute from any user
    /// account) against the current storage directory.
    nonisolated static func absoluteAttachmentURL(fromStored stored: String) -> URL? {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") {
            for folderName in [configuredAppSupportFolderName, legacyAppSupportFolderName] {
                let marker = "/Application Support/\(folderName)/"
                if let range = trimmed.range(of: marker) {
                    let relative = String(trimmed[range.upperBound...])
                    if !relative.isEmpty {
                        return storageDirectory.appendingPathComponent(relative).standardizedFileURL
                    }
                }
            }
            return URL(fileURLWithPath: trimmed)
        }
        return storageDirectory.appendingPathComponent(trimmed).standardizedFileURL
    }

    nonisolated private static func managedAttachmentURL(
        root: URL,
        id: String,
        fileExtension: String
    ) -> URL {
        let stem = managedAttachmentFileStem(for: id)
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeExtension = ext.allSatisfy({ $0.isLetter || $0.isNumber }) ? ext : ""
        let filename = safeExtension.isEmpty ? stem : "\(stem).\(safeExtension)"
        let root = root.standardizedFileURL
        return root.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
    }

    nonisolated static func validatedContainedAttachmentURL(
        _ candidateURL: URL,
        within baseDirectory: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let base = baseDirectory.standardizedFileURL
        let candidate = candidateURL.standardizedFileURL
        let baseComponents = base.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count > baseComponents.count,
              Array(candidateComponents.prefix(baseComponents.count)) == baseComponents else {
            throw NSError(
                domain: "FootprintAttachmentPath",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Attachment path escapes its managed directory."]
            )
        }

        var current = base
        let componentsToCheck = [String?](arrayLiteral: nil)
            + candidateComponents.dropFirst(baseComponents.count).map(Optional.some)
        for component in componentsToCheck {
            if let component {
                current.appendPathComponent(component)
            }
            if (try? fileManager.destinationOfSymbolicLink(atPath: current.path)) != nil {
                throw NSError(
                    domain: "FootprintAttachmentPath",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Managed attachment paths may not contain symbolic links."]
                )
            }
        }

        let resolvedBase = base.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resolvedBaseComponents = resolvedBase.pathComponents
        let resolvedCandidateComponents = resolvedCandidate.pathComponents
        guard resolvedCandidateComponents.count > resolvedBaseComponents.count,
              Array(resolvedCandidateComponents.prefix(resolvedBaseComponents.count)) == resolvedBaseComponents else {
            throw NSError(
                domain: "FootprintAttachmentPath",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Attachment path resolves outside its managed directory."]
            )
        }
        return candidate
    }

    nonisolated static func validatedManagedAttachmentURL(
        root: URL,
        id: String,
        fileExtension: String
    ) throws -> URL {
        try validatedContainedAttachmentURL(
            managedAttachmentURL(root: root, id: id, fileExtension: fileExtension),
            within: root
        )
    }

    nonisolated static func managedPublicationPDFURL(forPublicationID id: String) -> URL {
        managedAttachmentURL(root: publicationPDFsDirectory, id: id, fileExtension: "pdf")
    }

    nonisolated static func managedCVMediaAppearancePDFURL(forMediaAppearanceID id: String) -> URL {
        managedAttachmentURL(root: mediaAppearancePDFsDirectory, id: id, fileExtension: "pdf")
    }

    nonisolated static func managedCVConferenceContributionPDFURL(forContributionID id: String) -> URL {
        managedAttachmentURL(root: conferenceContributionPDFsDirectory, id: id, fileExtension: "pdf")
    }

    nonisolated static func managedDoctoralCandidatePDFURL(forDocumentID id: String) -> URL {
        managedAttachmentURL(root: doctoralCandidatePDFsDirectory, id: id, fileExtension: "pdf")
    }

    nonisolated static func managedCVReviewCertificatePDFURL(forReviewEntryID id: String) -> URL {
        managedAttachmentURL(root: reviewCertificatePDFsDirectory, id: id, fileExtension: "pdf")
    }

    static func persistManagedPublicationPDF(
        data: Data,
        forPublicationID id: String
    ) throws -> URL {
        try ensurePublicationPDFsDirectory()
        let url = try validatedManagedAttachmentURL(
            root: publicationPDFsDirectory,
            id: id,
            fileExtension: "pdf"
        )
        try performManagedAttachmentMutation {
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    static func persistManagedCVMediaAppearancePDF(
        data: Data,
        forMediaAppearanceID id: String
    ) throws -> URL {
        try ensureMediaAppearancePDFsDirectory()
        let url = try validatedManagedAttachmentURL(
            root: mediaAppearancePDFsDirectory,
            id: id,
            fileExtension: "pdf"
        )
        try performManagedAttachmentMutation {
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    static func persistManagedCVConferenceContributionPDF(
        data: Data,
        forContributionID id: String
    ) throws -> URL {
        try ensureConferenceContributionPDFsDirectory()
        let url = try validatedManagedAttachmentURL(
            root: conferenceContributionPDFsDirectory,
            id: id,
            fileExtension: "pdf"
        )
        try performManagedAttachmentMutation {
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    static func persistManagedDoctoralCandidatePDF(
        data: Data,
        forDocumentID id: String
    ) throws -> URL {
        try ensureDoctoralCandidatePDFsDirectory()
        let url = try validatedManagedAttachmentURL(
            root: doctoralCandidatePDFsDirectory,
            id: id,
            fileExtension: "pdf"
        )
        try performManagedAttachmentMutation {
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    nonisolated static func resolveDoctoralCandidatePDFURL(document: DoctoralCandidateDocument) -> URL? {
        if let managedURL = try? validatedManagedAttachmentURL(
            root: doctoralCandidatePDFsDirectory,
            id: document.id,
            fileExtension: "pdf"
        ), FileManager.default.fileExists(atPath: managedURL.path) {
            return managedURL
        }
        if let legacyURL = legacyManagedAttachmentURL(root: doctoralCandidatePDFsDirectory, id: document.id, fileExtension: "pdf") {
            return legacyURL
        }
        guard let path = document.path?.trimmedOrNil else { return nil }
        let directURL = absoluteAttachmentURL(fromStored: path) ?? URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: directURL.path) ? directURL : nil
    }

    /// The names a PDF from the earlier Media attachment UI can have in
    /// "Media Appearance Files": the stored name, and the attachment's id
    /// (the files there are named by the attachment's id).
    nonisolated static func legacyMediaPDFCandidateNames(_ attachments: [CVMediaAttachment]) -> [String] {
        attachments
            .filter {
                $0.filename.lowercased().hasSuffix(".pdf") || $0.storedFilename.lowercased().hasSuffix(".pdf")
            }
            .flatMap { attachment -> [String] in
                var names = [attachment.storedFilename]
                if let id = attachment.id.trimmedOrNil {
                    names.append("\(managedAttachmentFileStem(for: id)).pdf")
                }
                return names
            }
    }

    /// The file of one attachment from the earlier Media attachment UI.
    nonisolated static func resolveLegacyMediaAppearanceAttachmentURL(_ attachment: CVMediaAttachment) -> URL? {
        for name in legacyMediaPDFCandidateNames([attachment]) {
            if let url = resolveLegacyMediaAppearanceFileURL(storedFilename: name) {
                return url
            }
        }
        return resolveLegacyMediaAppearanceFileURL(storedFilename: attachment.storedFilename)
    }

    /// A file from the earlier Media attachment UI in "Media Appearance
    /// Files". A stored name that carries a folder or a full path is looked
    /// up by its last part, so the file is found wherever the name came from.
    nonisolated static func resolveLegacyMediaAppearanceFileURL(storedFilename: String) -> URL? {
        let trimmed = storedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidates = [trimmed]
        let leaf = URL(fileURLWithPath: trimmed).lastPathComponent
        if leaf != trimmed {
            candidates.append(leaf)
        }
        for candidate in candidates {
            guard isSafeAttachmentLeafName(candidate),
                  let url = try? validatedContainedAttachmentURL(
                      mediaAppearanceFilesDirectory.appendingPathComponent(candidate),
                      within: mediaAppearanceFilesDirectory
                  ),
                  FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            return url
        }
        return nil
    }

    static func canonicalizePublicationPDFAttachment(for publication: inout PublicationRecord) throws -> Bool {
        publication.finalPDFFilename = publication.finalPDFFilename?.trimmedOrNil
        publication.finalPDFPath = publication.finalPDFPath?.trimmedOrNil

        guard publication.finalPDFFilename != nil || publication.finalPDFPath != nil else {
            return false
        }

        let managedURL = try validatedManagedAttachmentURL(
            root: publicationPDFsDirectory,
            id: publication.id,
            fileExtension: "pdf"
        )
        let resolvedURL = resolvePublicationPDFURL(
            publicationID: publication.id,
            finalPDFPath: publication.finalPDFPath,
            finalPDFFilename: publication.finalPDFFilename
        )

        var didChange = false
        if publication.finalPDFFilename == nil,
           let recoveredFilename = resolvedURL?.lastPathComponent.nonEmpty {
            publication.finalPDFFilename = recoveredFilename
            didChange = true
        }

        if let resolvedURL,
           resolvedURL.path != managedURL.path {
            let data = try Data(contentsOf: resolvedURL)
            guard !data.isEmpty else { return didChange }
            _ = try persistManagedPublicationPDF(data: data, forPublicationID: publication.id)
            didChange = true
        }

        if FileManager.default.fileExists(atPath: managedURL.path),
           publication.finalPDFPath != Self.portableAttachmentPath(for: managedURL) {
            publication.finalPDFPath = Self.portableAttachmentPath(for: managedURL)
            didChange = true
        }

        return didChange
    }

    static func canonicalizeCVMediaAppearancePDFAttachment(for appearance: inout CVMediaAppearance) throws -> Bool {
        appearance.pdfFilename = appearance.pdfFilename?.trimmedOrNil
        appearance.pdfPath = appearance.pdfPath?.trimmedOrNil

        guard appearance.pdfFilename != nil || appearance.pdfPath != nil else {
            return false
        }

        let managedURL = try validatedManagedAttachmentURL(
            root: mediaAppearancePDFsDirectory,
            id: appearance.id,
            fileExtension: "pdf"
        )
        let resolvedURL = resolveCVMediaAppearancePDFURL(
            mediaAppearanceID: appearance.id,
            pdfPath: appearance.pdfPath,
            pdfFilename: appearance.pdfFilename,
            legacyStoredFilenames: legacyMediaPDFCandidateNames(appearance.attachments)
        )

        var didChange = false
        if appearance.pdfFilename == nil,
           let recoveredFilename = resolvedURL?.lastPathComponent.nonEmpty {
            appearance.pdfFilename = recoveredFilename
            didChange = true
        }

        if let resolvedURL,
           resolvedURL.path != managedURL.path {
            let data = try Data(contentsOf: resolvedURL)
            guard !data.isEmpty else { return didChange }
            _ = try persistManagedCVMediaAppearancePDF(data: data, forMediaAppearanceID: appearance.id)
            didChange = true
        }

        if FileManager.default.fileExists(atPath: managedURL.path),
           appearance.pdfPath != Self.portableAttachmentPath(for: managedURL) {
            appearance.pdfPath = Self.portableAttachmentPath(for: managedURL)
            didChange = true
        }

        return didChange
    }

    static func persistManagedCVReviewCertificatePDF(
        data: Data,
        forReviewEntryID id: String
    ) throws -> URL {
        try ensureReviewCertificatePDFsDirectory()
        let url = try validatedManagedAttachmentURL(
            root: reviewCertificatePDFsDirectory,
            id: id,
            fileExtension: "pdf"
        )
        try performManagedAttachmentMutation {
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    static func canonicalizeCVReviewCertificatePDFAttachment(for entry: inout CVReviewEntry) throws -> Bool {
        entry.certificateFilename = entry.certificateFilename?.trimmedOrNil
        entry.certificatePath = entry.certificatePath?.trimmedOrNil

        // Inline-data extraction: legacy records embedded the PDF bytes in
        // the JSON document itself. Write them to the managed location and
        // clear the inline copy only once the file is confirmed on disk.
        if let inlineData = entry.certificatePDFData, !inlineData.isEmpty {
            let managedURL = try persistManagedCVReviewCertificatePDF(
                data: inlineData,
                forReviewEntryID: entry.id
            )
            if entry.certificateFilename == nil {
                entry.certificateFilename = entry.certificatePath
                    .flatMap { URL(fileURLWithPath: $0).lastPathComponent.nonEmpty }
                    ?? "review-certificate.pdf"
            }
            entry.certificatePath = Self.portableAttachmentPath(for: managedURL)
            guard FileManager.default.fileExists(atPath: managedURL.path) else {
                throw NSError(domain: "FootprintAttachmentPath", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "Review certificate file was not written."
                ])
            }
            entry.certificatePDFData = nil
            return true
        }

        guard entry.certificateFilename != nil || entry.certificatePath != nil else {
            return false
        }

        let managedURL = try validatedManagedAttachmentURL(
            root: reviewCertificatePDFsDirectory,
            id: entry.id,
            fileExtension: "pdf"
        )
        let resolvedURL = resolveCVReviewCertificatePDFURL(
            reviewEntryID: entry.id,
            certificatePath: entry.certificatePath,
            certificateFilename: entry.certificateFilename
        )

        var didChange = false
        if entry.certificateFilename == nil,
           let recoveredFilename = resolvedURL?.lastPathComponent.nonEmpty {
            entry.certificateFilename = recoveredFilename
            didChange = true
        }

        if let resolvedURL,
           resolvedURL.path != managedURL.path {
            let data = try Data(contentsOf: resolvedURL)
            guard !data.isEmpty else { return didChange }
            _ = try persistManagedCVReviewCertificatePDF(data: data, forReviewEntryID: entry.id)
            didChange = true
        }

        if FileManager.default.fileExists(atPath: managedURL.path),
           entry.certificatePath != Self.portableAttachmentPath(for: managedURL) {
            entry.certificatePath = Self.portableAttachmentPath(for: managedURL)
            didChange = true
        }

        return didChange
    }

    static func canonicalizeCVConferenceContributionPDFAttachment(for contribution: inout CVConferenceContribution) throws -> Bool {
        contribution.pdfFilename = contribution.pdfFilename?.trimmedOrNil
        contribution.pdfPath = contribution.pdfPath?.trimmedOrNil

        guard contribution.pdfFilename != nil || contribution.pdfPath != nil else {
            return false
        }

        let managedURL = try validatedManagedAttachmentURL(
            root: conferenceContributionPDFsDirectory,
            id: contribution.id,
            fileExtension: "pdf"
        )
        let resolvedURL = resolveCVConferenceContributionPDFURL(
            contributionID: contribution.id,
            pdfPath: contribution.pdfPath,
            pdfFilename: contribution.pdfFilename
        )

        var didChange = false
        if contribution.pdfFilename == nil,
           let recoveredFilename = resolvedURL?.lastPathComponent.nonEmpty {
            contribution.pdfFilename = recoveredFilename
            didChange = true
        }

        if let resolvedURL,
           resolvedURL.path != managedURL.path {
            let data = try Data(contentsOf: resolvedURL)
            guard !data.isEmpty else { return didChange }
            _ = try persistManagedCVConferenceContributionPDF(data: data, forContributionID: contribution.id)
            didChange = true
        }

        if FileManager.default.fileExists(atPath: managedURL.path),
           contribution.pdfPath != Self.portableAttachmentPath(for: managedURL) {
            contribution.pdfPath = Self.portableAttachmentPath(for: managedURL)
            didChange = true
        }

        return didChange
    }

    static func removeManagedPublicationPDFIfPresent(forPublicationID id: String) throws {
        let url = try validatedManagedAttachmentURL(
            root: publicationPDFsDirectory,
            id: id,
            fileExtension: "pdf"
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try performManagedAttachmentMutation {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func removeManagedCVMediaAppearancePDFIfPresent(forMediaAppearanceID id: String) throws {
        let url = try validatedManagedAttachmentURL(
            root: mediaAppearancePDFsDirectory,
            id: id,
            fileExtension: "pdf"
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try performManagedAttachmentMutation {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func removeManagedCVReviewCertificatePDFIfPresent(forReviewEntryID id: String) throws {
        let url = try validatedManagedAttachmentURL(
            root: reviewCertificatePDFsDirectory,
            id: id,
            fileExtension: "pdf"
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try performManagedAttachmentMutation {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func removeManagedCVConferenceContributionPDFIfPresent(forContributionID id: String) throws {
        let url = try validatedManagedAttachmentURL(
            root: conferenceContributionPDFsDirectory,
            id: id,
            fileExtension: "pdf"
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try performManagedAttachmentMutation {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func normalizedTimeInput(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.replacingOccurrences(of: ":", with: "")
        if digits.count == 4, digits.allSatisfy(\.isNumber) {
            let hours = Int(digits.prefix(2)) ?? -1
            let minutes = Int(digits.suffix(2)) ?? -1
            if (0..<24).contains(hours), (0..<60).contains(minutes) {
                return "\(String(format: "%02d", hours)):\(String(format: "%02d", minutes))"
            }
        }
        if digits.count == 3, digits.allSatisfy(\.isNumber) {
            let chars = Array(digits)
            let hours = Int(String(chars[0])) ?? -1
            let minutes = Int(String(chars[1...2])) ?? -1
            if (0..<24).contains(hours), (0..<60).contains(minutes) {
                return "\(String(format: "%02d", hours)):\(String(format: "%02d", minutes))"
            }
        }
        return trimmed
    }
}
