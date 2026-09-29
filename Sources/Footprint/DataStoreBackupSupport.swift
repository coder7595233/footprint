import CryptoKit
import Foundation

extension GrantDataStore {
    nonisolated private static func derivedManagersForBackup(from organizations: [OrganizationRecord]) -> [ManagerOption] {
        organizations
            .filter { $0.roles.contains(.fundManager) }
            .map {
                ManagerOption(
                    id: $0.id,
                    nameSv: $0.nameSv,
                    nameEn: $0.nameEn,
                    reason: $0.note?.trimmedOrNil,
                    salaryCalculator: $0.salaryCalculator
                )
            }
            .sorted { $0.nameSv.localizedStandardCompare($1.nameSv) == .orderedAscending }
    }

    struct BackupHealthReport: Codable, Equatable {
        let generatedAt: String
        let interfaceLanguage: String?
        let lastSelectedTab: String?
        let applicationCount: Int
        let applicationsToApplyWithCloseDate: Int
        let managerCount: Int
        let managerNames: [String]
        let projectCount: Int
        let projectCollaboratorCount: Int
        let salarySourceCount: Int
        let salaryCoveragePeriodCount: Int
        let publicationAuthorCount: Int
        let publicationRecordCount: Int
    }

    struct BackupManifestEntry: Codable, Equatable {
        let fileName: String
        let byteCount: Int
        let sha256: String
    }

    struct BackupManifest: Codable, Equatable {
        let generatedAt: String
        let appVersion: String
        let entries: [BackupManifestEntry]
    }

    struct BackupAttachmentManifest: Codable, Equatable {
        let generatedAt: String
        let entries: [BackupAttachmentManifestEntry]
    }

    struct BackupAttachmentManifestEntry: Codable, Equatable {
        let relativePath: String
        let byteCount: Int
        let sha256: String
    }

    struct RestorePayload {
        enum AttachmentRestoreMode: Equatable {
            case preserveExisting
            case replaceWithVerifiedBackup
        }

        let snapshot: Snapshot
        let archivedRecords: [ArchivedRecordEnvelope]?
        let receivedGrantsData: Data?
        var sourceDirectoryURL: URL?
        var replacesArchivedRecords: Bool = false
        var replacesReceivedGrantsData: Bool = false
        var attachmentRestoreMode: AttachmentRestoreMode = .preserveExisting
    }

    private struct BackupAuxiliaryState: Codable, Equatable {
        let formatVersion: Int
        let hasReceivedGrants: Bool
    }

    private struct BackupCompletionMarker: Codable, Equatable {
        let formatVersion: Int
        let manifestSHA256: String
    }

    struct AttachmentRestoreJournalEntry: Codable, Equatable {
        let directoryName: String
        let hadPrevious: Bool
    }

    struct AttachmentRestoreJournal: Codable, Equatable {
        let formatVersion: Int
        let transactionID: String
        let destinationPath: String
        let stagingPath: String
        let entries: [AttachmentRestoreJournalEntry]
    }

    struct BackupSnapshot {
        let url: URL
        let date: Date
        let isVerified: Bool
    }

    private final class AttachmentRestoreTransaction {
        private let fileManager = FileManager.default
        private let destinationDirectory: URL
        private let stagingRoot: URL
        private let incomingRoot: URL
        private let previousRoot: URL
        private let journalURL: URL
        let transactionID: String
        private let entries: [AttachmentRestoreJournalEntry]

        init(
            destinationDirectory: URL,
            stagingRoot: URL,
            incomingRoot: URL,
            previousRoot: URL,
            journalURL: URL,
            transactionID: String,
            entries: [AttachmentRestoreJournalEntry]
        ) {
            self.destinationDirectory = destinationDirectory
            self.stagingRoot = stagingRoot
            self.incomingRoot = incomingRoot
            self.previousRoot = previousRoot
            self.journalURL = journalURL
            self.transactionID = transactionID
            self.entries = entries
        }

        func apply() throws {
            try ManagedAttachmentRevisionCoordinator.shared.performMutation {
                try applyManagedDirectories()
            }
        }

        private func applyManagedDirectories() throws {
            for entry in entries {
                let directoryName = entry.directoryName
                let incoming = try GrantDataStore.validatedContainedAttachmentURL(
                    incomingRoot.appendingPathComponent(directoryName, isDirectory: true),
                    within: incomingRoot
                )
                let destination = try GrantDataStore.validatedContainedAttachmentURL(
                    destinationDirectory.appendingPathComponent(directoryName, isDirectory: true),
                    within: destinationDirectory
                )
                let previous = try GrantDataStore.validatedContainedAttachmentURL(
                    previousRoot.appendingPathComponent(directoryName, isDirectory: true),
                    within: previousRoot
                )

                if entry.hadPrevious {
                    try fileManager.moveItem(at: destination, to: previous)
                }
                if fileManager.fileExists(atPath: incoming.path) {
                    try fileManager.moveItem(at: incoming, to: destination)
                }
            }
        }

        func rollback() throws {
            try ManagedAttachmentRevisionCoordinator.shared.performMutation {
                try rollbackManagedDirectories()
            }
        }

        private func rollbackManagedDirectories() throws {
            var failures: [String] = []
            for entry in entries.reversed() {
                let directoryName = entry.directoryName
                do {
                    let destination = try GrantDataStore.validatedContainedAttachmentURL(
                        destinationDirectory.appendingPathComponent(directoryName, isDirectory: true),
                        within: destinationDirectory
                    )
                    let previous = try GrantDataStore.validatedContainedAttachmentURL(
                        previousRoot.appendingPathComponent(directoryName, isDirectory: true),
                        within: previousRoot
                    )
                    if fileManager.fileExists(atPath: previous.path) {
                        if fileManager.fileExists(atPath: destination.path) {
                            try fileManager.removeItem(at: destination)
                        }
                        try fileManager.moveItem(at: previous, to: destination)
                    } else if entry.hadPrevious {
                        guard fileManager.fileExists(atPath: destination.path) else {
                            throw NSError(domain: "FootprintRestore", code: 66, userInfo: [
                                NSLocalizedDescriptionKey: "The original attachment directory \(directoryName) could not be located."
                            ])
                        }
                    } else if fileManager.fileExists(atPath: destination.path) {
                        try fileManager.removeItem(at: destination)
                    }
                } catch {
                    failures.append("\(directoryName): \(error.localizedDescription)")
                }
            }
            guard failures.isEmpty else {
                throw NSError(domain: "FootprintRestore", code: 67, userInfo: [
                    NSLocalizedDescriptionKey: "Attachment rollback is incomplete. Recovery data remains at \(stagingRoot.path). \(failures.joined(separator: "; "))"
                ])
            }
            try removeRecoveryArtifacts()
        }

        func finish() throws {
            try removeRecoveryArtifacts()
        }

        private func removeRecoveryArtifacts() throws {
            if fileManager.fileExists(atPath: stagingRoot.path) {
                try fileManager.removeItem(at: stagingRoot)
            }
            if fileManager.fileExists(atPath: journalURL.path) {
                try fileManager.removeItem(at: journalURL)
            }
        }
    }

    func backupRestorePreviewSummary(for directoryURL: URL) -> String {
        do {
            flushPendingPersistenceIfNeeded()
            return try Self.backupRestorePreviewSummaryText(language: language, directoryURL: directoryURL)
        } catch {
            return error.localizedDescription
        }
    }

    func backupHealthSummary() -> String {
        do {
            flushPendingPersistenceIfNeeded()
            return try Self.backupHealthSummaryText(language: language)
        } catch {
            return error.localizedDescription
        }
    }

    func backupSnapshots() throws -> [BackupSnapshot] {
        if let backupSnapshotsCache {
            return backupSnapshotsCache
        }
        let loaded = try Self.loadBackupSnapshots()
        backupSnapshotsCache = loaded
        return loaded
    }

    func liveStorageHealthReport() throws -> BackupHealthReport {
        flushPendingPersistenceIfNeeded()
        return try Self.liveStorageHealthReportFromStorage()
    }

    func backupHealthLines(label: String, report: BackupHealthReport?) -> [String] {
        guard let report else { return ["\(label): \(language.text("Not available", "Saknas"))"] }
        return [
            "\(label):",
            "\(language.text("Language", "Språk")): \(report.interfaceLanguage ?? "-")",
            "\(language.text("Tab", "Flik")): \(report.lastSelectedTab ?? "-")",
            "\(language.text("Applications", "Ansökningar")): \(report.applicationCount)",
            "\(language.text("To apply with closing date", "Att söka med stängningsdatum")): \(report.applicationsToApplyWithCloseDate)",
            "\(language.text("Managers", "Medelsförvaltare")): \(report.managerCount)",
            "\(language.text("Projects", "Projekt")): \(report.projectCount)",
            "\(language.text("Project collaborators", "Projektmedarbetare")): \(report.projectCollaboratorCount)",
            "\(language.text("Salary sources", "Lönekällor")): \(report.salarySourceCount)",
            "\(language.text("Salary periods", "Löneperioder")): \(report.salaryCoveragePeriodCount)",
        ]
    }

    nonisolated static func decodeRestorePayload(from directoryURL: URL) throws -> RestorePayload {
        try verifyBackupManifest(
            in: directoryURL,
            requireManifest: true,
            requireCompleteFileList: true
        )
        let hasVerifiedAttachmentManifest = try verifyAttachmentManifestIfPresent(in: directoryURL)
        guard let backupSQLiteURL = backupSQLiteURL(in: directoryURL) else {
            throw NSError(
                domain: "FootprintBackup",
                code: 53,
                userInfo: [
                    NSLocalizedDescriptionKey: "SQLite backup is required. JSON backup snapshots are no longer accepted as restore sources."
                ]
            )
        }
        let validationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FootprintRestoreValidation-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: validationDirectory,
            withIntermediateDirectories: false,
            attributes: nil
        )
        defer { try? FileManager.default.removeItem(at: validationDirectory) }
        let validationSQLiteURL = validationDirectory.appendingPathComponent(backupSQLiteURL.lastPathComponent)
        try FileManager.default.copyItem(at: backupSQLiteURL, to: validationSQLiteURL)
        for suffix in ["-wal", "-shm"] {
            let source = URL(fileURLWithPath: backupSQLiteURL.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(
                at: source,
                to: URL(fileURLWithPath: validationSQLiteURL.path + suffix)
            )
        }
        let sqliteStore = try SQLiteDocumentStore(url: validationSQLiteURL)
        do {
            let isModernBackup = try sqliteStore.containsDocument(named: "backup_auxiliary_state")
            guard !isModernBackup || hasValidBackupCompletionMarker(in: directoryURL) else {
                throw NSError(
                    domain: "FootprintBackup",
                    code: 77,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Modern backup completion marker is missing or does not match the manifest."
                    ]
                )
            }
            guard try sqliteStore.integrityCheckPassed() else {
                throw NSError(
                    domain: "FootprintBackup",
                    code: 71,
                    userInfo: [NSLocalizedDescriptionKey: "SQLite backup integrity check failed."]
                )
            }
            guard try sqliteStore.foreignKeyViolationCount() == 0 else {
                throw NSError(
                    domain: "FootprintBackup",
                    code: 72,
                    userInfo: [NSLocalizedDescriptionKey: "SQLite backup foreign-key check failed."]
                )
            }
            try verifySupportedBackupSchema(in: sqliteStore)
            var payload = try restorePayloadFromSQLiteBackup(sqliteStore)
            payload.sourceDirectoryURL = directoryURL
            payload.attachmentRestoreMode = hasVerifiedAttachmentManifest
                ? .replaceWithVerifiedBackup
                : .preserveExisting
            return payload
        } catch {
            throw NSError(
                domain: "FootprintBackup",
                code: 54,
                userInfo: [
                    NSLocalizedDescriptionKey: "SQLite backup is incomplete or unreadable: \(error.localizedDescription)"
                ]
            )
        }
    }

    private nonisolated static func restorePayloadFromSQLiteBackup(
        _ sqliteStore: SQLiteDocumentStore
    ) throws -> RestorePayload {
        let auxiliaryState = try sqliteStore.load(BackupAuxiliaryState.self, named: "backup_auxiliary_state")
        let hasArchivedRecordsDocument = try sqliteStore.containsDocument(named: "archived_records")
        let hasReceivedGrantsDocument = try sqliteStore.containsDocument(named: "received_grants")
        let state = try loadPersistentStateFromSQLite(sqliteStore)
        let snapshot = Snapshot(
            applications: state.applications,
            metadata: state.metadata,
            organizations: state.organizations,
            managers: derivedManagersForBackup(from: state.organizations),
            projects: state.projects,
            teachingCourses: state.teachingCourses,
            teachingComponents: state.teachingComponents,
            teachingFormats: state.teachingFormats,
            teachingAssignments: state.teachingAssignments,
            doctoralCandidates: state.doctoralCandidates,
            cvPersonalResume: state.cvPersonalResume,
            cvConferenceContributions: state.cvConferenceContributions,
            cvMediaAppearances: state.cvMediaAppearances,
            cvReviewEntries: state.cvReviewEntries,
            cvOtherPublications: state.cvOtherPublications,
            publicationAuthors: try requireSQLiteDocument([PublicationAuthor].self, named: "publication_authors", from: sqliteStore),
            publicationJournals: try requireSQLiteDocument([PublicationJournal].self, named: "publication_journals", from: sqliteStore),
            publicationRecords: try requireSQLiteDocument([PublicationRecord].self, named: "publication_records", from: sqliteStore)
        )

        return RestorePayload(
            snapshot: snapshot,
            archivedRecords: try sqliteStore.load([ArchivedRecordEnvelope].self, named: "archived_records"),
            receivedGrantsData: try sqliteStore.loadData(named: "received_grants"),
            sourceDirectoryURL: nil,
            replacesArchivedRecords: auxiliaryState != nil || hasArchivedRecordsDocument,
            replacesReceivedGrantsData: auxiliaryState != nil || hasReceivedGrantsDocument,
            attachmentRestoreMode: .preserveExisting
        )
    }

    private nonisolated static func verifySupportedBackupSchema(
        in sqliteStore: SQLiteDocumentStore
    ) throws {
        let metadata = try requireSQLiteDocument(
            DataSourceMetadata.self,
            named: "metadata",
            from: sqliteStore
        )
        if let schemaVersion = metadata.schemaVersion,
           schemaVersion > DataSourceMetadata.currentSchemaVersion {
            throw NSError(
                domain: "FootprintBackup",
                code: 73,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The backup schema version \(schemaVersion) is newer than this app supports (\(DataSourceMetadata.currentSchemaVersion))."
                ]
            )
        }

        let appSettings = try requireSQLiteDocument(
            AppSettingsSnapshot.self,
            named: "app_settings",
            from: sqliteStore
        )
        guard appSettings.schemaVersion <= AppSettingsSnapshot.currentSchemaVersion else {
            throw NSError(
                domain: "FootprintBackup",
                code: 74,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The backup app-settings schema version \(appSettings.schemaVersion) is newer than this app supports (\(AppSettingsSnapshot.currentSchemaVersion))."
                ]
            )
        }

        let relationalCore = try requireSQLiteDocument(
            RelationalCoreSnapshot.self,
            named: "relational_core",
            from: sqliteStore
        )
        guard relationalCore.schemaVersion <= RelationalCoreSnapshot.currentSchemaVersion else {
            throw NSError(
                domain: "FootprintBackup",
                code: 80,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The backup relational-core schema version \(relationalCore.schemaVersion) is newer than this app supports (\(RelationalCoreSnapshot.currentSchemaVersion))."
                ]
            )
        }

        let relationalSQLite = try requireSQLiteDocument(
            RelationalSQLiteSnapshot.self,
            named: "relational_sqlite_snapshot",
            from: sqliteStore
        )
        guard relationalSQLite.schemaVersion <= RelationalSQLiteSnapshot.currentSchemaVersion else {
            throw NSError(
                domain: "FootprintBackup",
                code: 81,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The backup relational SQLite schema version \(relationalSQLite.schemaVersion) is newer than this app supports (\(RelationalSQLiteSnapshot.currentSchemaVersion))."
                ]
            )
        }
    }

    nonisolated static func backupHealthSummaryText(language: AppLanguage) throws -> String {
        let current = try liveStorageHealthReportFromStorage()
        let latestBackup = try loadBackupSnapshots().sorted { $0.date > $1.date }.first
        let latestReport = try latestBackup.flatMap { snapshot in
            let reportURL = snapshot.url.appendingPathComponent("health_check.json")
            if FileManager.default.fileExists(atPath: reportURL.path) {
                return try Self.decode(BackupHealthReport.self, from: reportURL)
            }
            return Self.healthReport(for: try Self.decodeRestorePayload(from: snapshot.url).snapshot)
        }

        return (
            backupHealthLines(
                language: language,
                label: language.text("Current live data", "Aktiv live-data"),
                report: current
            ) + [""]
                + backupHealthLines(
                    language: language,
                    label: language.text("Latest backup", "Senaste backup"),
                    report: latestReport
                )
        )
        .joined(separator: "\n")
    }

    nonisolated static func backupRestorePreviewSummaryText(language: AppLanguage, directoryURL: URL) throws -> String {
        let current = try liveStorageHealthReportFromStorage()
        let payload = try Self.decodeRestorePayload(from: directoryURL)
        let reportURL = directoryURL.appendingPathComponent("health_check.json")
        let selectedReport = FileManager.default.fileExists(atPath: reportURL.path)
            ? try Self.decode(BackupHealthReport.self, from: reportURL)
            : Self.healthReport(for: payload.snapshot)
        let hasSQLite = Self.backupSQLiteURL(in: directoryURL) != nil
        let hasHealth = FileManager.default.fileExists(atPath: reportURL.path)
        let manifestStatus = backupPreviewVerificationStatus(language: language) {
            try verifyBackupManifest(in: directoryURL, requireManifest: true, requireCompleteFileList: true)
        }
        let attachmentStatus = backupPreviewVerificationStatus(language: language) {
            try verifyAttachmentManifest(in: directoryURL)
        }
        let restoreStatus = backupPreviewVerificationStatus(language: language) {
            try verifyRestoreReport(healthReport(for: payload.snapshot), matches: selectedReport)
        }

        let formatLines = [
            language.text("Folder", "Mapp") + ": " + directoryURL.lastPathComponent,
            "SQLite: " + (hasSQLite ? language.text("Yes", "Ja") : language.text("No", "Nej")),
            language.text("Health report", "Hälsorapport") + ": " + (hasHealth ? language.text("Yes", "Ja") : language.text("No", "Nej")),
            language.text("Manifest", "Manifest") + ": " + manifestStatus,
            language.text("Attachments", "Bilagor") + ": " + attachmentStatus,
            language.text("Restore payload", "Återställningspaket") + ": " + restoreStatus
        ]

        return (
            formatLines + [""]
                + backupPreviewDeltaLines(language: language, current: current, selected: selectedReport) + [""]
                + backupHealthLines(
                    language: language,
                    label: language.text("Current live data", "Aktiv live-data"),
                    report: current
                ) + [""]
                + backupHealthLines(
                    language: language,
                    label: language.text("Selected backup", "Vald backup"),
                    report: selectedReport
                )
        )
        .joined(separator: "\n")
    }

    nonisolated static func backupPreviewDeltaLines(
        language: AppLanguage,
        current: BackupHealthReport,
        selected: BackupHealthReport
    ) -> [String] {
        func deltaLine(_ title: String, _ currentValue: Int, _ selectedValue: Int) -> String {
            let delta = selectedValue - currentValue
            let sign = delta > 0 ? "+" : ""
            return "\(title): \(selectedValue) (\(sign)\(delta))"
        }

        return [
            language.text("Changes if restored", "Förändring vid återställning") + ":",
            deltaLine(language.text("Applications", "Ansökningar"), current.applicationCount, selected.applicationCount),
            deltaLine(language.text("Managers", "Medelsförvaltare"), current.managerCount, selected.managerCount),
            deltaLine(language.text("Projects", "Projekt"), current.projectCount, selected.projectCount),
            deltaLine(language.text("Project collaborators", "Projektmedarbetare"), current.projectCollaboratorCount, selected.projectCollaboratorCount),
            deltaLine(language.text("Salary sources", "Lönekällor"), current.salarySourceCount, selected.salarySourceCount),
            deltaLine(language.text("Salary periods", "Löneperioder"), current.salaryCoveragePeriodCount, selected.salaryCoveragePeriodCount),
            deltaLine(language.text("Researchers", "Forskare"), current.publicationAuthorCount, selected.publicationAuthorCount),
            deltaLine(language.text("Publications", "Publikationer"), current.publicationRecordCount, selected.publicationRecordCount),
        ]
    }

    nonisolated private static func backupPreviewVerificationStatus(
        language: AppLanguage,
        operation: () throws -> Void
    ) -> String {
        do {
            try operation()
            return language.text("Verified", "Verifierad")
        } catch {
            return language.text("Problem", "Problem") + ": " + error.localizedDescription
        }
    }

    nonisolated static func liveStorageHealthReportFromStorage() throws -> BackupHealthReport {
        let sqliteStore = try SQLiteDocumentStore(url: databaseURL)
        let state = try loadPersistentStateFromSQLite(sqliteStore)
        let authors = try requireSQLiteDocument([PublicationAuthor].self, named: "publication_authors", from: sqliteStore)
        let records = try requireSQLiteDocument([PublicationRecord].self, named: "publication_records", from: sqliteStore)
        return Self.healthReport(
            applications: state.applications,
            metadata: state.metadata,
            managers: derivedManagersForBackup(from: state.organizations),
            projects: state.projects,
            publicationAuthors: authors,
            publicationRecords: records
        )
    }

    nonisolated static func encodedSQLiteDocuments(for snapshot: Snapshot) throws -> [(String, Data)] {
        let encoder = makePersistenceEncoder()
        return [
            ("applications", try encoder.encode(snapshot.applications)),
            ("metadata", try encoder.encode(sanitizedMetadata(snapshot.metadata))),
            ("app_settings", try encoder.encode(AppSettingsSnapshot(metadata: snapshot.metadata))),
            ("calendar_travel_records", try encoder.encode(snapshot.metadata.calendarTravelRecords ?? [])),
            ("calendar_accommodation_records", try encoder.encode(snapshot.metadata.calendarAccommodationRecords ?? [])),
            ("calendar_meeting_records", try encoder.encode(snapshot.metadata.calendarMeetingRecords ?? [])),
            ("organizations", try encoder.encode(snapshot.organizations)),
            ("congresses", try encoder.encode(storedCongressRecords(from: snapshot.organizations))),
            ("relational_core", try encoder.encode(relationalCoreSnapshot(
                generatedAt: Date(timeIntervalSince1970: 0),
                metadata: sanitizedMetadata(snapshot.metadata),
                organizations: snapshot.organizations,
                cvConferenceContributions: snapshot.cvConferenceContributions
            ))),
            ("relational_sqlite_snapshot", try encoder.encode(relationalSQLiteSnapshot(
                generatedAt: Date(timeIntervalSince1970: 0),
                applications: snapshot.applications,
                metadata: sanitizedMetadata(snapshot.metadata),
                organizations: snapshot.organizations,
                projects: snapshot.projects,
                publicationAuthors: snapshot.publicationAuthors,
                publicationRecords: snapshot.publicationRecords,
                cvConferenceContributions: snapshot.cvConferenceContributions
            ))),
            ("projects", try encoder.encode(snapshot.projects)),
            ("teaching_courses", try encoder.encode(snapshot.teachingCourses)),
            ("teaching_components", try encoder.encode(snapshot.teachingComponents)),
            ("teaching_formats", try encoder.encode(snapshot.teachingFormats)),
            ("teaching_assignments", try encoder.encode(snapshot.teachingAssignments)),
            ("doctoral_candidates", try encoder.encode(snapshot.doctoralCandidates)),
            ("cv_personal_resume", try encoder.encode(snapshot.cvPersonalResume)),
            ("cv_conference_contributions", try encoder.encode(snapshot.cvConferenceContributions)),
            ("cv_media_appearances", try encoder.encode(snapshot.cvMediaAppearances)),
            ("cv_review_entries", try encoder.encode(snapshot.cvReviewEntries)),
            ("cv_other_publications", try encoder.encode(snapshot.cvOtherPublications)),
            ("publication_authors", try encoder.encode(snapshot.publicationAuthors)),
            ("publication_journals", try encoder.encode(snapshot.publicationJournals)),
            ("publication_records", try encoder.encode(snapshot.publicationRecords))
        ]
    }

    @discardableResult
    nonisolated static func createForcedBackupSnapshot(
        snapshot: Snapshot,
        archivedRecords: [ArchivedRecordEnvelope],
        receivedGrantsData: Data?,
        prefix: String,
        now: Date = Date(),
        expectedAttachmentRevision: UInt64? = nil
    ) throws -> URL {
        try ensureBackupDirectory()
        let timestamp = backupFolderName(for: now)
        let directory = backupsDirectory.appendingPathComponent(
            "\(timestamp)-\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        return try writeVerifiedBackupPackage(
            snapshot: snapshot,
            archivedRecords: archivedRecords,
            receivedGrantsData: receivedGrantsData,
            finalDirectory: directory,
            expectedAttachmentRevision: expectedAttachmentRevision
        )
    }

    @discardableResult
    nonisolated static func writeVerifiedBackupPackage(
        snapshot: Snapshot,
        archivedRecords: [ArchivedRecordEnvelope],
        receivedGrantsData: Data?,
        finalDirectory: URL,
        expectedAttachmentRevision: UInt64? = nil,
        storageRoot: URL = GrantDataStore.storageDirectory
    ) throws -> URL {
        let fileManager = FileManager.default
        let finalParentDirectory = finalDirectory.deletingLastPathComponent()
        let stagingDirectory = finalParentDirectory.appendingPathComponent(
            ".\(finalDirectory.lastPathComponent).backup-in-progress-\(UUID().uuidString)",
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: finalDirectory.path) else {
            throw NSError(domain: "FootprintBackup", code: 62, userInfo: [
                NSLocalizedDescriptionKey: "A backup with the same timestamp already exists."
            ])
        }
        try fileManager.createDirectory(
            at: finalParentDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let deduplicationSourceDirectory =
            ManagedAttachmentRevisionCoordinator.shared.latestPublishedBackup(
                in: finalParentDirectory
            )
            ?? newestCompatibleAttachmentBackup(
                in: finalParentDirectory,
                excluding: finalDirectory
            )
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true, attributes: nil)
        var published = false
        defer {
            if !published {
                try? fileManager.removeItem(at: stagingDirectory)
            }
        }

        try writeSQLiteBackupSnapshot(
            snapshot,
            archivedRecords: archivedRecords,
            receivedGrantsData: receivedGrantsData,
            to: stagingDirectory,
            expectedAttachmentRevision: expectedAttachmentRevision,
            deduplicationSourceDirectory: deduplicationSourceDirectory,
            storageRoot: storageRoot
        )
        let report = healthReport(for: snapshot)
        try encode(report, to: stagingDirectory.appendingPathComponent("health_check.json"))
        try writeBackupManifest(in: stagingDirectory)
        try writeBackupCompletionMarker(in: stagingDirectory)
        try verifyBackupSnapshotPackage(in: stagingDirectory, expectedSnapshot: snapshot)
        try fileManager.moveItem(at: stagingDirectory, to: finalDirectory)
        published = true
        ManagedAttachmentRevisionCoordinator.shared.recordPublishedBackup(finalDirectory)
        return finalDirectory
    }

    nonisolated static func writeSQLiteBackupSnapshot(
        _ snapshot: Snapshot,
        archivedRecords: [ArchivedRecordEnvelope],
        receivedGrantsData: Data?,
        to directory: URL,
        expectedAttachmentRevision: UInt64? = nil,
        deduplicationSourceDirectory: URL? = nil,
        storageRoot: URL = GrantDataStore.storageDirectory
    ) throws {
        let stagedAttachments = try stageManagedAttachmentSnapshot(
            expectedRevision: expectedAttachmentRevision,
            storageRoot: storageRoot
        )
        defer { try? FileManager.default.removeItem(at: stagedAttachments) }
        let backupURL = directory.appendingPathComponent(defaultDatabaseFileName)
        let sqliteStore = try SQLiteDocumentStore(url: backupURL)
        var sqliteDocuments = try encodedSQLiteDocuments(for: snapshot)
        sqliteDocuments.append(("archived_records", try makePersistenceEncoder().encode(archivedRecords)))
        sqliteDocuments.append((
            "backup_auxiliary_state",
            try makePersistenceEncoder().encode(
                BackupAuxiliaryState(formatVersion: 2, hasReceivedGrants: receivedGrantsData != nil)
            )
        ))
        if let receivedGrantsData {
            sqliteDocuments.append(("received_grants", receivedGrantsData))
        }
        try sqliteStore.saveBatch(sqliteDocuments)
        try sqliteStore.checkpointAndClose()
        try verifySQLiteBackupSnapshot(
            at: backupURL,
            expectedSnapshot: snapshot,
            expectedDocuments: sqliteDocuments
        )
        try writeAttachmentBackup(
            from: stagedAttachments,
            snapshot: snapshot,
            to: directory,
            deduplicationSourceDirectory: deduplicationSourceDirectory
        )
    }

    nonisolated static func newestCompatibleAttachmentBackup(
        in parentDirectory: URL,
        excluding excludedURL: URL
    ) -> URL? {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: parentDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return nil }
        for url in urls.sorted(by: {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
        }) {
            guard fileManager.fileExists(
                atPath: url.appendingPathComponent("attachments_manifest.json").path
            ),
            fileManager.fileExists(
                atPath: url.appendingPathComponent("backup_manifest.json").path
            ),
            fileManager.fileExists(
                atPath: url.appendingPathComponent(".backup-complete.json").path
            ) else { continue }
            // Each candidate file is independently required to be a real file
            // with matching size and SHA-256 before it is hard-linked.
            return url
        }
        return nil
    }

    nonisolated private static func stageManagedAttachmentSnapshot(
        expectedRevision: UInt64?,
        storageRoot: URL = GrantDataStore.storageDirectory
    ) throws -> URL {
        try ManagedAttachmentRevisionCoordinator.shared.stageSnapshot(
            expectedRevision: expectedRevision
        ) {
            let fileManager = FileManager.default
            let stagingRoot = storageRoot.appendingPathComponent(
                ".attachment-snapshot-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            do {
                _ = try actualBackupAttachmentRelativePaths(in: storageRoot)
                for directoryName in managedAttachmentDirectoryNames {
                    let source = try validatedContainedAttachmentURL(
                        storageRoot.appendingPathComponent(directoryName, isDirectory: true),
                        within: storageRoot
                    )
                    guard fileManager.fileExists(atPath: source.path) else { continue }
                    let destination = try validatedContainedAttachmentURL(
                        stagingRoot.appendingPathComponent(directoryName, isDirectory: true),
                        within: stagingRoot
                    )
                    try stageAttachmentDirectoryByLinking(
                        from: source,
                        to: destination
                    )
                }
                return stagingRoot
            } catch {
                try? fileManager.removeItem(at: stagingRoot)
                throw error
            }
        }
    }

    nonisolated private static func stageAttachmentDirectoryByLinking(
        from sourceDirectory: URL,
        to destinationDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return }
        for case let sourceURL as URL in enumerator {
            let values = try sourceURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw NSError(
                    domain: "FootprintBackup",
                    code: 76,
                    userInfo: [NSLocalizedDescriptionKey: "Managed attachments may not contain symbolic links."]
                )
            }
            let relativePath = String(
                sourceURL.standardizedFileURL.path.dropFirst(
                    sourceDirectory.standardizedFileURL.path.count + 1
                )
            )
            let destinationURL = destinationDirectory.appendingPathComponent(relativePath)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            } else if values.isRegularFile == true {
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                do {
                    try fileManager.linkItem(at: sourceURL, to: destinationURL)
                } catch {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                }
            }
        }
    }

    private nonisolated static func verifySQLiteBackupSnapshot(
        at backupURL: URL,
        expectedSnapshot: Snapshot,
        expectedDocuments: [(String, Data)]
    ) throws {
        let sqliteStore = try SQLiteDocumentStore(url: backupURL)
        guard try sqliteStore.integrityCheckPassed() else {
            throw NSError(
                domain: "FootprintBackup",
                code: 55,
                userInfo: [NSLocalizedDescriptionKey: "SQLite backup integrity check failed."]
            )
        }
        try verifySQLiteBackupDocuments(
            in: sqliteStore,
            expectedDocuments: expectedDocuments
        )
        let payload = try restorePayloadFromSQLiteBackup(sqliteStore)
        try verifyRestoreReport(healthReport(for: payload.snapshot), matches: healthReport(for: expectedSnapshot))
    }

    nonisolated static func verifySQLiteBackupDocuments(
        in sqliteStore: SQLiteDocumentStore,
        expectedDocuments: [(String, Data)]
    ) throws {
        var mismatches: [String] = []
        var seenKeys = Set<String>()
        for (key, expectedData) in expectedDocuments.sorted(by: { $0.0 < $1.0 }) {
            guard seenKeys.insert(key).inserted else {
                mismatches.append("\(key):duplicate-expected-key")
                continue
            }
            guard let actualData = try sqliteStore.loadData(named: key) else {
                mismatches.append("\(key):missing")
                continue
            }
            guard actualData != expectedData else { continue }
            mismatches.append(
                "\(key):digest expected=\(sha256Hex(for: expectedData)) actual=\(sha256Hex(for: actualData))"
            )
        }
        guard mismatches.isEmpty else {
            throw NSError(
                domain: "FootprintBackup",
                code: 56,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "SQLite backup document verification failed: \(mismatches.joined(separator: ", "))."
                ]
            )
        }
    }

    nonisolated static func writeRestorePayloadToStorage(
        _ payload: RestorePayload,
        expectedReport: BackupHealthReport
    ) throws -> [String: Data] {
        try ensureStorageDirectory()
        try recoverInterruptedRestoreIfNeeded()
        let persistedCache = try Dictionary(
            uniqueKeysWithValues: encodedSQLiteDocuments(for: payload.snapshot)
        )

        let sqliteStore = try SQLiteDocumentStore(url: databaseURL)
        var documents = Array(persistedCache)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
        if let archivedRecords = payload.archivedRecords {
            documents.append(("archived_records", try makePersistenceEncoder().encode(archivedRecords)))
        }
        if let receivedGrantsData = payload.receivedGrantsData {
            documents.append(("received_grants", receivedGrantsData))
        }
        var keysToDelete: [String] = ["maintenance_markers"]
        if payload.replacesArchivedRecords, payload.archivedRecords == nil {
            keysToDelete.append("archived_records")
        }
        if payload.replacesReceivedGrantsData, payload.receivedGrantsData == nil {
            keysToDelete.append("received_grants")
        }
        let attachmentTransaction: AttachmentRestoreTransaction?
        if payload.attachmentRestoreMode == .replaceWithVerifiedBackup,
           let sourceDirectoryURL = payload.sourceDirectoryURL {
            attachmentTransaction = try prepareAttachmentRestore(
                from: sourceDirectoryURL,
                to: storageDirectory
            )
        } else {
            attachmentTransaction = nil
        }
        let restoreMarkerData = attachmentTransaction.map { Data($0.transactionID.utf8) }
        do {
            try sqliteStore.performImmediateTransaction {
                try sqliteStore.saveBatchInCurrentTransaction(documents)
                try sqliteStore.deleteDocumentsInCurrentTransaction(named: keysToDelete)
                if let restoreMarkerData {
                    try sqliteStore.saveBatchInCurrentTransaction([(restoreTransactionMarkerKey, restoreMarkerData)])
                }
                for (key, expectedData) in documents {
                    guard try sqliteStore.loadData(named: key) == expectedData else {
                        throw NSError(domain: "FootprintRestore", code: 63, userInfo: [
                            NSLocalizedDescriptionKey: "Restore verification failed for SQLite document \(key)."
                        ])
                    }
                }
                if payload.replacesArchivedRecords, payload.archivedRecords == nil,
                   try sqliteStore.containsDocument(named: "archived_records") {
                    throw NSError(domain: "FootprintRestore", code: 64, userInfo: [
                        NSLocalizedDescriptionKey: "Restore verification failed while clearing archived records."
                    ])
                }
                if payload.replacesReceivedGrantsData, payload.receivedGrantsData == nil,
                   try sqliteStore.containsDocument(named: "received_grants") {
                    throw NSError(domain: "FootprintRestore", code: 65, userInfo: [
                        NSLocalizedDescriptionKey: "Restore verification failed while clearing received grants."
                    ])
                }
                let storedPayload = try restorePayloadFromSQLiteBackup(sqliteStore)
                try verifyRestoreReport(healthReport(for: storedPayload.snapshot), matches: expectedReport)
                try attachmentTransaction?.apply()
            }
        } catch let restoreError {
            if let attachmentTransaction {
                do {
                    try attachmentTransaction.rollback()
                } catch let rollbackError {
                    throw NSError(domain: "FootprintRestore", code: 69, userInfo: [
                        NSLocalizedDescriptionKey: "Restore failed. \(restoreError.localizedDescription) Recovery data was retained because rollback is incomplete: \(rollbackError.localizedDescription)"
                    ])
                }
            }
            throw restoreError
        }
        // The transaction above deleted the maintenance_markers document; the
        // UserDefaults/legacy-file fallbacks would re-promote the old markers
        // and defeat the intended maintenance re-run on the restored data.
        clearMaintenanceMarkerFallbacks()
        if let attachmentTransaction {
            do {
                try attachmentTransaction.finish()
                try? sqliteStore.deleteDocuments(named: [restoreTransactionMarkerKey])
            } catch {
                // The committed SQLite marker and journal deliberately remain so
                // startup recovery can complete cleanup without rolling data back.
            }
        }
        return persistedCache
    }

    nonisolated static func backupHealthLines(
        language: AppLanguage,
        label: String,
        report: BackupHealthReport?
    ) -> [String] {
        guard let report else { return ["\(label): \(language.text("Not available", "Saknas"))"] }
        return [
            "\(label):",
            "\(language.text("Language", "Språk")): \(report.interfaceLanguage ?? "-")",
            "\(language.text("Tab", "Flik")): \(report.lastSelectedTab ?? "-")",
            "\(language.text("Applications", "Ansökningar")): \(report.applicationCount)",
            "\(language.text("To apply with closing date", "Att söka med stängningsdatum")): \(report.applicationsToApplyWithCloseDate)",
            "\(language.text("Managers", "Medelsförvaltare")): \(report.managerCount)",
            "\(language.text("Projects", "Projekt")): \(report.projectCount)",
            "\(language.text("Project collaborators", "Projektmedarbetare")): \(report.projectCollaboratorCount)",
            "\(language.text("Salary sources", "Lönekällor")): \(report.salarySourceCount)",
            "\(language.text("Salary periods", "Löneperioder")): \(report.salaryCoveragePeriodCount)",
        ]
    }

    nonisolated static func loadBackupSnapshots(
        in backupsDirectory: URL = GrantDataStore.backupsDirectory
    ) throws -> [BackupSnapshot] {
        guard FileManager.default.fileExists(atPath: backupsDirectory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let date = backupDate(from: url.lastPathComponent),
                  backupSQLiteURL(in: url) != nil else { return nil }
            let manifestURL = url.appendingPathComponent("backup_manifest.json")
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                return BackupSnapshot(
                    url: url,
                    date: date,
                    isVerified: hasValidBackupCompletionMarker(in: url)
                )
            }
            return nil
        }
    }

    nonisolated static func healthReport(for snapshot: Snapshot) -> BackupHealthReport {
        healthReport(
            applications: snapshot.applications,
            metadata: snapshot.metadata,
            managers: derivedManagersForBackup(from: snapshot.organizations),
            projects: snapshot.projects,
            publicationAuthors: snapshot.publicationAuthors,
            publicationRecords: snapshot.publicationRecords
        )
    }

    nonisolated static func healthReport(
        applications: [GrantApplication],
        metadata: DataSourceMetadata,
        managers: [ManagerOption],
        projects: [ProjectRecord],
        publicationAuthors: [PublicationAuthor],
        publicationRecords: [PublicationRecord]
    ) -> BackupHealthReport {
        BackupHealthReport(
            generatedAt: GrantParsing.timestampNow(),
            interfaceLanguage: metadata.interfaceLanguage,
            lastSelectedTab: metadata.lastSelectedTab,
            applicationCount: applications.count,
            applicationsToApplyWithCloseDate: applications.filter {
                $0.resultLabel == "Att söka" && $0.closesOn?.trimmedOrNil != nil
            }.count,
            managerCount: managers.count,
            managerNames: managers.map(\.nameSv).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            projectCount: projects.count,
            projectCollaboratorCount: projects.reduce(0) { $0 + $1.collaboratorNames.count },
            salarySourceCount: metadata.salarySources?.count ?? 0,
            salaryCoveragePeriodCount: metadata.salaryCoveragePeriods?.count ?? 0,
            publicationAuthorCount: publicationAuthors.count,
            publicationRecordCount: publicationRecords.count
        )
    }

    nonisolated static func verifyRestoreReport(_ actual: BackupHealthReport, matches expected: BackupHealthReport) throws {
        var mismatches: [String] = []
        if actual.interfaceLanguage != expected.interfaceLanguage {
            mismatches.append("interfaceLanguage")
        }
        if actual.lastSelectedTab != expected.lastSelectedTab {
            mismatches.append("lastSelectedTab")
        }
        if actual.applicationCount != expected.applicationCount {
            mismatches.append("applicationCount")
        }
        if actual.applicationsToApplyWithCloseDate != expected.applicationsToApplyWithCloseDate {
            mismatches.append("applicationsToApplyWithCloseDate")
        }
        if actual.managerCount != expected.managerCount {
            mismatches.append("managerCount")
        }
        if actual.managerNames != expected.managerNames {
            mismatches.append("managerNames")
        }
        if actual.projectCount != expected.projectCount {
            mismatches.append("projectCount")
        }
        if actual.projectCollaboratorCount != expected.projectCollaboratorCount {
            mismatches.append("projectCollaboratorCount")
        }
        if actual.salarySourceCount != expected.salarySourceCount {
            mismatches.append("salarySourceCount")
        }
        if actual.salaryCoveragePeriodCount != expected.salaryCoveragePeriodCount {
            mismatches.append("salaryCoveragePeriodCount")
        }
        if actual.publicationAuthorCount != expected.publicationAuthorCount {
            mismatches.append("publicationAuthorCount")
        }
        if actual.publicationRecordCount != expected.publicationRecordCount {
            mismatches.append("publicationRecordCount")
        }

        guard mismatches.isEmpty else {
            throw NSError(
                domain: "FootprintRestore",
                code: 41,
                userInfo: [
                    NSLocalizedDescriptionKey: "Restore verification failed: \(mismatches.joined(separator: ", ")).",
                ]
            )
        }
    }

    nonisolated static func writeBackupManifest(in directoryURL: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let entries = try urls
            .filter { $0.lastPathComponent != "backup_manifest.json" }
            .compactMap { url -> BackupManifestEntry? in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else { return nil }
                return BackupManifestEntry(
                    fileName: url.lastPathComponent,
                    byteCount: values.fileSize ?? 0,
                    sha256: try sha256Hex(forFileAt: url)
                )
            }
            .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }

        let manifest = BackupManifest(
            generatedAt: GrantParsing.timestampNow(),
            appVersion: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev",
            entries: entries
        )
        try encode(manifest, to: directoryURL.appendingPathComponent("backup_manifest.json"))
    }

    nonisolated static func writeBackupCompletionMarker(in directoryURL: URL) throws {
        let manifestURL = directoryURL.appendingPathComponent("backup_manifest.json")
        let marker = BackupCompletionMarker(
            formatVersion: 1,
            manifestSHA256: try sha256Hex(forFileAt: manifestURL)
        )
        try encode(marker, to: directoryURL.appendingPathComponent(".backup-complete.json"))
    }

    nonisolated private static func hasValidBackupCompletionMarker(in directoryURL: URL) -> Bool {
        let markerURL = directoryURL.appendingPathComponent(".backup-complete.json")
        let manifestURL = directoryURL.appendingPathComponent("backup_manifest.json")
        guard FileManager.default.fileExists(atPath: markerURL.path),
              FileManager.default.fileExists(atPath: manifestURL.path),
              let marker = try? decode(BackupCompletionMarker.self, from: markerURL),
              marker.formatVersion == 1,
              let digest = try? sha256Hex(forFileAt: manifestURL) else {
            return false
        }
        return marker.manifestSHA256 == digest
    }

    nonisolated static func verifyBackupManifest(
        in directoryURL: URL,
        requireManifest: Bool = false,
        requireCompleteFileList: Bool = false
    ) throws {
        let manifestURL = directoryURL.appendingPathComponent("backup_manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            if requireManifest {
                throw NSError(
                    domain: "FootprintBackup",
                    code: 61,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Backup manifest is missing."
                    ]
                )
            }
            return
        }
        let manifest = try decode(BackupManifest.self, from: manifestURL)
        var mismatches: [String] = []
        var seenFileNames = Set<String>()
        let manifestFileNames = Set(manifest.entries.map(\.fileName))
        for entry in manifest.entries {
            guard isSafeBackupRootFileName(entry.fileName) else {
                mismatches.append("\(entry.fileName):unsafe-name")
                continue
            }
            guard seenFileNames.insert(entry.fileName).inserted else {
                mismatches.append("\(entry.fileName):duplicate")
                continue
            }
            let fileURL = directoryURL.appendingPathComponent(entry.fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                mismatches.append("\(entry.fileName):missing")
                continue
            }
            let values = try fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                mismatches.append("\(entry.fileName):symbolic-link")
                continue
            }
            if values.isRegularFile != true {
                mismatches.append("\(entry.fileName):not-file")
                continue
            }
            if values.fileSize != entry.byteCount {
                mismatches.append("\(entry.fileName):size")
            }
            if try sha256Hex(forFileAt: fileURL) != entry.sha256 {
                mismatches.append("\(entry.fileName):checksum")
            }
        }
        if requireCompleteFileList {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
            var actualFileNames = Set<String>()
            for url in urls {
                let fileName = url.lastPathComponent
                let values = try url.resourceValues(
                    forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
                )
                if values.isSymbolicLink == true {
                    mismatches.append("\(fileName):unexpected-symbolic-link")
                } else if values.isRegularFile == true {
                    if fileName != "backup_manifest.json",
                       fileName != ".backup-complete.json" {
                        actualFileNames.insert(fileName)
                    }
                } else if values.isDirectory == true {
                    if !managedAttachmentDirectoryNames.contains(fileName) {
                        mismatches.append("\(fileName):unexpected-directory")
                    }
                } else {
                    mismatches.append("\(fileName):unexpected-entry")
                }
            }
            let missingFromManifest = actualFileNames.subtracting(manifestFileNames).sorted()
            let staleManifestEntries = manifestFileNames.subtracting(actualFileNames).sorted()
            mismatches.append(contentsOf: missingFromManifest.map { "\($0):not-in-manifest" })
            mismatches.append(contentsOf: staleManifestEntries.map { "\($0):stale-manifest-entry" })
        }
        guard mismatches.isEmpty else {
            throw NSError(
                domain: "FootprintBackup",
                code: 52,
                userInfo: [
                    NSLocalizedDescriptionKey: "Backup manifest verification failed: \(mismatches.joined(separator: ", "))."
                ]
            )
        }
    }

    nonisolated private static func isSafeBackupRootFileName(_ fileName: String) -> Bool {
        guard let normalized = fileName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
              normalized == fileName,
              normalized != ".",
              normalized != "..",
              !normalized.contains("/"),
              !normalized.contains("\\") else {
            return false
        }
        return URL(fileURLWithPath: normalized).lastPathComponent == normalized
    }

    nonisolated static func verifyBackupSnapshotPackage(
        in directoryURL: URL,
        expectedSnapshot: Snapshot
    ) throws {
        try verifyBackupManifest(
            in: directoryURL,
            requireManifest: true,
            requireCompleteFileList: true
        )
        try verifyAttachmentManifest(in: directoryURL)
        let payload = try decodeRestorePayload(from: directoryURL)
        try verifyRestoreReport(
            healthReport(for: payload.snapshot),
            matches: healthReport(for: expectedSnapshot)
        )
    }

    nonisolated static func writeAttachmentBackup(
        from sourceDirectory: URL,
        snapshot: Snapshot,
        to backupDirectory: URL,
        deduplicationSourceDirectory: URL? = nil
    ) throws {
        let fileManager = FileManager.default
        _ = try actualBackupAttachmentRelativePaths(in: sourceDirectory)
        _ = try actualBackupAttachmentRelativePaths(in: backupDirectory)
        for directoryName in managedAttachmentDirectoryNames {
            let source = try validatedContainedAttachmentURL(
                sourceDirectory.appendingPathComponent(directoryName, isDirectory: true),
                within: sourceDirectory
            )
            let destination = try validatedContainedAttachmentURL(
                backupDirectory.appendingPathComponent(directoryName, isDirectory: true),
                within: backupDirectory
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let deduplicationSource = deduplicationSourceDirectory?
                .appendingPathComponent(directoryName, isDirectory: true)
            try copyAttachmentDirectoryDeduplicated(
                from: source,
                to: destination,
                matching: deduplicationSource
            )
        }
        try copySnapshotReferencedPDFs(snapshot, into: backupDirectory)
        var entries: [BackupAttachmentManifestEntry] = []
        for directoryName in managedAttachmentDirectoryNames {
            let destination = backupDirectory.appendingPathComponent(directoryName, isDirectory: true)
            guard fileManager.fileExists(atPath: destination.path) else { continue }
            entries.append(contentsOf: try attachmentManifestEntries(for: destination, baseDirectory: backupDirectory))
        }
        let manifest = BackupAttachmentManifest(
            generatedAt: GrantParsing.timestampNow(),
            entries: entries.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        )
        try encode(manifest, to: backupDirectory.appendingPathComponent("attachments_manifest.json"))
    }

    nonisolated private static func copyAttachmentDirectoryDeduplicated(
        from sourceDirectory: URL,
        to destinationDirectory: URL,
        matching deduplicationSourceDirectory: URL?
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else { return }
        for case let sourceURL as URL in enumerator {
            let values = try sourceURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true else {
                throw NSError(
                    domain: "FootprintBackup",
                    code: 76,
                    userInfo: [NSLocalizedDescriptionKey: "Backup attachments may not contain symbolic links."]
                )
            }
            let relativePath = String(
                sourceURL.standardizedFileURL.path.dropFirst(
                    sourceDirectory.standardizedFileURL.path.count + 1
                )
            )
            let destinationURL = destinationDirectory.appendingPathComponent(relativePath)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                continue
            }
            guard values.isRegularFile == true else { continue }
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if let candidate = deduplicationSourceDirectory?.appendingPathComponent(relativePath),
               fileManager.fileExists(atPath: candidate.path) {
                let candidateValues = try candidate.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                )
                if candidateValues.isSymbolicLink != true,
                   candidateValues.isRegularFile == true,
                   candidateValues.fileSize == values.fileSize,
                   try sha256Hex(forFileAt: candidate) == sha256Hex(forFileAt: sourceURL) {
                    do {
                        try fileManager.linkItem(at: candidate, to: destinationURL)
                        continue
                    } catch {
                        // Cross-volume exports cannot hard-link. Fall through
                        // to the compatible clone/copy path.
                    }
                }
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    nonisolated static func verifyAttachmentManifest(in directoryURL: URL) throws {
        _ = try verifyAttachmentManifestIfPresent(in: directoryURL)
    }

    @discardableResult
    nonisolated static func verifyAttachmentManifestIfPresent(in directoryURL: URL) throws -> Bool {
        let manifestURL = directoryURL.appendingPathComponent("attachments_manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return false }
        let manifest = try decode(BackupAttachmentManifest.self, from: manifestURL)
        var mismatches: [String] = []
        var seenRelativePaths = Set<String>()
        for entry in manifest.entries {
            guard let fileURL = try safeBackupAttachmentURL(
                relativePath: entry.relativePath,
                baseDirectory: directoryURL
            ) else {
                mismatches.append("\(entry.relativePath):unsafe-path")
                continue
            }
            guard seenRelativePaths.insert(entry.relativePath).inserted else {
                mismatches.append("\(entry.relativePath):duplicate")
                continue
            }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                mismatches.append("\(entry.relativePath):missing")
                continue
            }
            let values = try fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true, values.isRegularFile == true else {
                mismatches.append("\(entry.relativePath):not-file")
                continue
            }
            if values.fileSize != entry.byteCount {
                mismatches.append("\(entry.relativePath):size")
            }
            if try sha256Hex(forFileAt: fileURL) != entry.sha256 {
                mismatches.append("\(entry.relativePath):checksum")
            }
        }
        let actualRelativePaths = try actualBackupAttachmentRelativePaths(in: directoryURL)
        let manifestRelativePaths = Set(manifest.entries.map(\.relativePath))
        mismatches.append(
            contentsOf: actualRelativePaths
                .subtracting(manifestRelativePaths)
                .sorted()
                .map { "\($0):not-in-manifest" }
        )
        mismatches.append(
            contentsOf: manifestRelativePaths
                .subtracting(actualRelativePaths)
                .sorted()
                .map { "\($0):stale-manifest-entry" }
        )
        guard mismatches.isEmpty else {
            throw NSError(
                domain: "FootprintBackup",
                code: 59,
                userInfo: [
                    NSLocalizedDescriptionKey: "Backup attachment manifest verification failed: \(mismatches.joined(separator: ", "))."
                ]
            )
        }
        return true
    }

    nonisolated private static func safeBackupAttachmentURL(
        relativePath: String,
        baseDirectory: URL
    ) throws -> URL? {
        guard let normalized = relativePath.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
              normalized == relativePath,
              !normalized.hasPrefix("/"),
              !normalized.contains("\\"),
              !normalized.contains("%") else {
            return nil
        }
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2,
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              managedAttachmentDirectoryNames.contains(components[0]) else {
            return nil
        }
        let candidate = baseDirectory
            .appendingPathComponent(normalized)
            .standardizedFileURL
        return try validatedContainedAttachmentURL(candidate, within: baseDirectory)
    }

    nonisolated private static func actualBackupAttachmentRelativePaths(
        in directoryURL: URL
    ) throws -> Set<String> {
        let fileManager = FileManager.default
        _ = try validatedContainedAttachmentURL(
            directoryURL.appendingPathComponent(".attachment-containment-check"),
            within: directoryURL
        )
        var paths = Set<String>()
        for directoryName in managedAttachmentDirectoryNames {
            let directory = directoryURL.appendingPathComponent(directoryName, isDirectory: true)
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            let directoryValues = try directory.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard directoryValues.isSymbolicLink != true,
                  directoryValues.isDirectory == true else {
                throw NSError(
                    domain: "FootprintBackup",
                    code: 79,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Backup attachment roots must be real directories: \(directoryName)."
                    ]
                )
            }
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: []
            ) else {
                throw NSError(
                    domain: "FootprintBackup",
                    code: 75,
                    userInfo: [NSLocalizedDescriptionKey: "Could not enumerate backup attachments in \(directoryName)."]
                )
            }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    throw NSError(
                        domain: "FootprintBackup",
                        code: 76,
                        userInfo: [NSLocalizedDescriptionKey: "Backup attachments may not contain symbolic links: \(url.lastPathComponent)."]
                    )
                }
                guard values.isRegularFile == true else { continue }
                paths.insert(relativeBackupPath(for: url, baseDirectory: directoryURL))
            }
        }
        return paths
    }

    nonisolated private static func copySnapshotReferencedPDFs(_ snapshot: Snapshot, into backupDirectory: URL) throws {
        for publication in snapshot.publicationRecords {
            guard let sourceURL = resolvePublicationPDFURL(
                publicationID: publication.id,
                finalPDFPath: publication.finalPDFPath,
                finalPDFFilename: publication.finalPDFFilename
            ) else { continue }
            let destination = try validatedManagedAttachmentURL(
                root: backupDirectory.appendingPathComponent("Publication PDFs", isDirectory: true),
                id: publication.id,
                fileExtension: "pdf"
            )
            try copyBackupAttachmentIfNeeded(from: sourceURL, to: destination)
        }

        for appearance in snapshot.cvMediaAppearances {
            guard let sourceURL = resolveCVMediaAppearancePDFURL(
                mediaAppearanceID: appearance.id,
                pdfPath: appearance.pdfPath,
                pdfFilename: appearance.pdfFilename,
                legacyStoredFilenames: legacyMediaPDFCandidateNames(appearance.attachments)
            ) else { continue }
            let destination = try validatedManagedAttachmentURL(
                root: backupDirectory.appendingPathComponent("Media Appearance PDFs", isDirectory: true),
                id: appearance.id,
                fileExtension: "pdf"
            )
            try copyBackupAttachmentIfNeeded(from: sourceURL, to: destination)
        }

        for contribution in snapshot.cvConferenceContributions {
            guard let sourceURL = resolveCVConferenceContributionPDFURL(
                contributionID: contribution.id,
                pdfPath: contribution.pdfPath,
                pdfFilename: contribution.pdfFilename
            ) else { continue }
            let destination = try validatedManagedAttachmentURL(
                root: backupDirectory.appendingPathComponent("Conference Contribution PDFs", isDirectory: true),
                id: contribution.id,
                fileExtension: "pdf"
            )
            try copyBackupAttachmentIfNeeded(from: sourceURL, to: destination)
        }

        for entry in snapshot.cvReviewEntries {
            guard let sourceURL = resolveCVReviewCertificatePDFURL(
                reviewEntryID: entry.id,
                certificatePath: entry.certificatePath,
                certificateFilename: entry.certificateFilename
            ) else { continue }
            let destination = try validatedManagedAttachmentURL(
                root: backupDirectory.appendingPathComponent("Review Certificate PDFs", isDirectory: true),
                id: entry.id,
                fileExtension: "pdf"
            )
            try copyBackupAttachmentIfNeeded(from: sourceURL, to: destination)
        }
    }

    nonisolated private static func copyBackupAttachmentIfNeeded(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        if sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
            return
        }
        let values = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
            throw NSError(
                domain: "FootprintAttachmentPath",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Backup attachment sources must be real files."]
            )
        }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try validatedContainedAttachmentURL(
            destinationURL,
            within: destinationURL.deletingLastPathComponent()
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            let destinationValues = try destinationURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            if destinationValues.isSymbolicLink != true,
               destinationValues.isRegularFile == true,
               destinationValues.fileSize == values.fileSize,
               try sha256Hex(forFileAt: destinationURL) == sha256Hex(forFileAt: sourceURL) {
                return
            }
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    nonisolated private static let restoreTransactionMarkerKey = "restore_transaction_marker"

    nonisolated private static func restoreJournalURL(in destinationDirectory: URL) -> URL {
        destinationDirectory.appendingPathComponent(".restore-transaction.json")
    }

    nonisolated static func recoverInterruptedRestoreIfNeeded() throws {
        let fileManager = FileManager.default
        let journalURL = restoreJournalURL(in: storageDirectory)
        guard fileManager.fileExists(atPath: journalURL.path) else { return }
        let journal = try decode(AttachmentRestoreJournal.self, from: journalURL)
        guard journal.formatVersion == 1,
              URL(fileURLWithPath: journal.destinationPath).standardizedFileURL == storageDirectory.standardizedFileURL else {
            throw NSError(domain: "FootprintRestore", code: 70, userInfo: [
                NSLocalizedDescriptionKey: "The interrupted restore journal is invalid and was retained at \(journalURL.path)."
            ])
        }

        let stagingRoot = URL(fileURLWithPath: journal.stagingPath, isDirectory: true)
        let transaction = AttachmentRestoreTransaction(
            destinationDirectory: storageDirectory,
            stagingRoot: stagingRoot,
            incomingRoot: stagingRoot.appendingPathComponent("incoming", isDirectory: true),
            previousRoot: stagingRoot.appendingPathComponent("previous", isDirectory: true),
            journalURL: journalURL,
            transactionID: journal.transactionID,
            entries: journal.entries
        )
        let sqliteStore = try SQLiteDocumentStore(url: databaseURL)
        let committedMarker = try sqliteStore.loadData(named: restoreTransactionMarkerKey)
        if committedMarker == Data(journal.transactionID.utf8) {
            try transaction.finish()
        } else {
            try transaction.rollback()
        }
        try? sqliteStore.deleteDocuments(named: [restoreTransactionMarkerKey])
    }

    nonisolated private static func prepareAttachmentRestore(
        from backupDirectory: URL,
        to destinationDirectory: URL
    ) throws -> AttachmentRestoreTransaction {
        let fileManager = FileManager.default
        try recoverInterruptedRestoreIfNeeded()
        try verifyAttachmentManifest(in: backupDirectory)
        let transactionID = UUID().uuidString
        let stagingRoot = destinationDirectory.appendingPathComponent(
            ".restore-staging-\(transactionID)",
            isDirectory: true
        )
        let incomingRoot = stagingRoot.appendingPathComponent("incoming", isDirectory: true)
        let previousRoot = stagingRoot.appendingPathComponent("previous", isDirectory: true)
        let journalURL = restoreJournalURL(in: destinationDirectory)
        try fileManager.createDirectory(at: incomingRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: previousRoot, withIntermediateDirectories: true)
        do {
            let manifestSource = backupDirectory.appendingPathComponent("attachments_manifest.json")
            if fileManager.fileExists(atPath: manifestSource.path) {
                try fileManager.copyItem(
                    at: manifestSource,
                    to: incomingRoot.appendingPathComponent("attachments_manifest.json")
                )
            }
            for directoryName in managedAttachmentDirectoryNames {
                let source = try validatedContainedAttachmentURL(
                    backupDirectory.appendingPathComponent(directoryName, isDirectory: true),
                    within: backupDirectory
                )
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let incoming = try validatedContainedAttachmentURL(
                    incomingRoot.appendingPathComponent(directoryName, isDirectory: true),
                    within: incomingRoot
                )
                try fileManager.copyItem(at: source, to: incoming)
            }
            try verifyAttachmentManifest(in: incomingRoot)
            let entries = managedAttachmentDirectoryNames.map { directoryName in
                AttachmentRestoreJournalEntry(
                    directoryName: directoryName,
                    hadPrevious: fileManager.fileExists(
                        atPath: destinationDirectory.appendingPathComponent(directoryName, isDirectory: true).path
                    )
                )
            }
            let journal = AttachmentRestoreJournal(
                formatVersion: 1,
                transactionID: transactionID,
                destinationPath: destinationDirectory.path,
                stagingPath: stagingRoot.path,
                entries: entries
            )
            try encode(journal, to: journalURL)
            return AttachmentRestoreTransaction(
                destinationDirectory: destinationDirectory,
                stagingRoot: stagingRoot,
                incomingRoot: incomingRoot,
                previousRoot: previousRoot,
                journalURL: journalURL,
                transactionID: transactionID,
                entries: entries
            )
        } catch {
            if !fileManager.fileExists(atPath: journalURL.path) {
                try? fileManager.removeItem(at: stagingRoot)
            }
            throw error
        }
    }

    nonisolated static func backupSQLiteURL(in directoryURL: URL) -> URL? {
        let candidates = [
            directoryURL.appendingPathComponent(configuredDatabaseFileName),
            directoryURL.appendingPathComponent(defaultDatabaseFileName)
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    nonisolated static func pruneBackupSnapshots(_ snapshots: [BackupSnapshot], now: Date) throws {
        let sortedVerified = snapshots
            .filter(\.isVerified)
            .sorted { $0.date > $1.date }
        var keep = Set<URL>()

        if let newest = sortedVerified.first {
            keep.insert(newest.url)
        }

        for policy in backupPolicies {
            let relevant = sortedVerified.filter { now.timeIntervalSince($0.date) <= policy.horizon }
            var keptSlots = Set<Int64>()
            for snapshot in relevant {
                let slot = Int64(floor(snapshot.date.timeIntervalSince1970 / policy.slot))
                if keptSlots.insert(slot).inserted {
                    keep.insert(snapshot.url)
                }
            }
        }

        var deletionFailures: [String] = []
        // Unverified snapshots inside the grace window are kept: a backup
        // whose completion-marker write crashed moments ago is still the
        // freshest copy of the data and must not be pruned before a human or
        // the next verified backup supersedes it.
        let unverifiedPruneGrace: TimeInterval = 6 * 3600
        for snapshot in snapshots where !keep.contains(snapshot.url) {
            if !snapshot.isVerified, now.timeIntervalSince(snapshot.date) < unverifiedPruneGrace {
                continue
            }
            do {
                try FileManager.default.removeItem(at: snapshot.url)
            } catch {
                deletionFailures.append(
                    "\(snapshot.url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
        guard deletionFailures.isEmpty else {
            throw NSError(
                domain: "FootprintBackup",
                code: 83,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Some expired backups could not be removed: \(deletionFailures.joined(separator: "; "))"
                ]
            )
        }
    }

    nonisolated static func backupFolderName(for date: Date) -> String {
        makeBackupTimestampFormatter().string(from: date)
    }

    nonisolated static func backupDate(from folderName: String) -> Date? {
        let formatter = makeBackupTimestampFormatter()
        if let exact = formatter.date(from: folderName) {
            return exact
        }
        let prefix = String(folderName.prefix(15))
        return formatter.date(from: prefix)
    }

    nonisolated private static func makeBackupTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }

    nonisolated private static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static var managedAttachmentDirectoryNames: [String] {
        ["Publication PDFs", "Media Appearance PDFs", "Media Appearance Files", "Conference Contribution PDFs", "Doctoral Candidate PDFs", "Review Certificate PDFs"]
    }

    nonisolated private static func attachmentManifestEntries(
        for directory: URL,
        baseDirectory: URL
    ) throws -> [BackupAttachmentManifestEntry] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else {
            return []
        }
        var entries: [BackupAttachmentManifestEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw NSError(
                    domain: "FootprintBackup",
                    code: 76,
                    userInfo: [NSLocalizedDescriptionKey: "Backup attachments may not contain symbolic links: \(url.lastPathComponent)."]
                )
            }
            guard values.isRegularFile == true else { continue }
            entries.append(
                BackupAttachmentManifestEntry(
                    relativePath: relativeBackupPath(for: url, baseDirectory: baseDirectory),
                    byteCount: values.fileSize ?? 0,
                    sha256: try sha256Hex(forFileAt: url)
                )
            )
        }
        return entries
    }

    nonisolated private static func relativeBackupPath(for url: URL, baseDirectory: URL) -> String {
        let basePath = baseDirectory.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(basePath + "/") else { return url.lastPathComponent }
        return String(filePath.dropFirst(basePath.count + 1))
    }

    nonisolated private static func sha256Hex(forFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1024 * 1024)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
