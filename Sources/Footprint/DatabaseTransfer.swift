import Foundation

extension GrantDataStore {
    nonisolated private static let databaseExportDescriptorFileName = "database_export.json"
    nonisolated private static let databaseExportPayloadDirectoryName = "payload"

    private struct DatabaseImportSource: Sendable {
        let payloadURL: URL
        let descriptor: FootprintDatabaseExportDescriptor?
    }

    private struct SelectiveDatabaseImportResult: @unchecked Sendable {
        let previousSnapshot: Snapshot
        let mergedSnapshot: Snapshot
        let previousArchivedRecords: [ArchivedRecordEnvelope]
        let previousReceivedGrantsData: Data?
    }

    /// Revalidates every source of truth immediately before a destructive
    /// restore/import commit. Preparation is deliberately allowed off-main,
    /// but the check and commit run in one MainActor turn.
    func requireUnchangedDataForDestructiveCommit(
        snapshot: Snapshot,
        archivedRecords: [ArchivedRecordEnvelope],
        receivedGrantsData: Data?,
        tolerateUnreadableAuxiliaryData: Bool = false
    ) throws {
        // In blocked-writes recovery the auxiliary documents were unreadable
        // at capture time too; an unreadable read here means "still
        // unchanged", not "changed".
        let currentArchivedRecords = tolerateUnreadableAuxiliaryData
            ? ((try? loadArchivedRecords()) ?? archivedRecords)
            : try loadArchivedRecords()
        let currentReceivedGrantsData = tolerateUnreadableAuxiliaryData
            ? ((try? loadReceivedGrantsData()) ?? receivedGrantsData)
            : try loadReceivedGrantsData()
        guard currentSnapshot() == snapshot,
              currentArchivedRecords == archivedRecords,
              currentReceivedGrantsData == receivedGrantsData else {
            throw NSError(
                domain: "FootprintDatabaseTransfer",
                code: 409,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Local data changed while the destructive operation was being prepared. No imported data was committed."
                ]
            )
        }
    }

    func exportDatabasePackage(
        to destinationURL: URL,
        scope: FootprintDataExchangeScope,
        categories: Set<FootprintDataExchangeCategory>
    ) {
        let requestedCategories = scope == .entireApp
            ? Set(FootprintDataExchangeCategory.allCases)
            : categories.intersection(Set(FootprintDataExchangeCategory.selectableCases(for: .databasePackage)))
        guard scope == .entireApp || !requestedCategories.isEmpty else {
            notice = StoreNotice(
                message: language.text("Choose at least one data category.", "Välj minst en datakategori."),
                tone: .info
            )
            return
        }
        let resolvedCategories = scope == .entireApp
            ? requestedCategories
            : FootprintDataExchangeCategory.dependencyClosure(for: requestedCategories)

        guard flushAllPendingPersistenceIfNeeded() else {
            notice = StoreNotice(
                message: language.text(
                    "Export was stopped because pending changes could not be saved.",
                    "Exporten stoppades eftersom väntande ändringar inte kunde sparas."
                ),
                tone: .error
            )
            return
        }
        let archivedRecords: [ArchivedRecordEnvelope]
        let receivedGrantsData: Data?
        do {
            archivedRecords = scope == .entireApp ? try loadArchivedRecords() : []
            receivedGrantsData = scope == .entireApp ? try loadReceivedGrantsData() : nil
        } catch {
            loadError = error.localizedDescription
            notice = StoreNotice(
                message: language.text(
                    "Export was stopped because auxiliary database data could not be read.",
                    "Exporten stoppades eftersom kompletterande databasdata inte kunde läsas."
                ),
                tone: .error
            )
            return
        }
        let attachmentRevision = Self.currentManagedAttachmentRevision()
        let sourceSnapshot = currentSnapshot()
        let exportedSnapshot = scope == .entireApp
            ? sourceSnapshot
            : Self.selectiveDatabaseSnapshot(from: sourceSnapshot, categories: resolvedCategories)
        let descriptor = FootprintDatabaseExportDescriptor(
            formatVersion: FootprintDatabaseExportDescriptor.currentFormatVersion,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            categories: FootprintDataExchangeCategory.allCases.filter(resolvedCategories.contains),
            isCompleteDatabase: scope == .entireApp,
            payloadDirectoryName: Self.databaseExportPayloadDirectoryName
        )
        let startMessage = language.text("Exporting database…", "Exporterar databas…")
        let successMessage = language.text(
            "Exported a verified database package to \(destinationURL.lastPathComponent).",
            "Exporterade ett verifierat databaspaket till \(destinationURL.lastPathComponent)."
        )
        let failureMessage = language.text("Database export failed.", "Databasexporten misslyckades.")
        let exportLanguage = language

        performBackgroundOperation(
            startMessage: startMessage,
            failureMessage: failureMessage,
            work: {
                try Self.writeDatabaseExportPackage(
                    snapshot: exportedSnapshot,
                    archivedRecords: archivedRecords,
                    receivedGrantsData: receivedGrantsData,
                    descriptor: descriptor,
                    destinationURL: destinationURL,
                    expectedAttachmentRevision: attachmentRevision,
                    language: exportLanguage
                )
            }
        ) { (_: Void) in
            self.loadError = nil
            self.notice = StoreNotice(message: successMessage, tone: .success)
        }
    }

    func importDatabasePackage(from selectedURL: URL) {
        let language = language
        performBackgroundOperation(
            startMessage: language.text("Inspecting database package…", "Kontrollerar databaspaket…"),
            failureMessage: language.text("Database import failed.", "Databasimporten misslyckades."),
            work: {
                try Self.databaseImportSource(for: selectedURL)
            }
        ) { source in
            if source.descriptor?.isCompleteDatabase != false {
                self.restoreFromBackupAsync(directoryURL: source.payloadURL)
                return
            }

            self.importSelectiveDatabasePackage(from: source)
        }
    }

    private func importSelectiveDatabasePackage(from source: DatabaseImportSource) {
        guard !storageWritesBlockedByLoadFailure else {
            // With writes blocked the in-memory state is empty; merging a
            // package into it and committing would overwrite the on-disk
            // database with the package-plus-nothing, and the pre-import
            // safety backup would preserve only the empty memory.
            notice = StoreNotice(
                message: language.text(
                    "Selective import is unavailable while the database could not be loaded. Restore a full backup instead.",
                    "Selektiv import är inte tillgänglig när databasen inte kunde läsas in. Återställ en fullständig backup i stället."
                ),
                tone: .error
            )
            return
        }
        guard let descriptor = source.descriptor else {
            loadError = DatabaseTransferError.invalidPackage(
                "The selective export descriptor is missing."
            ).localizedDescription
            return
        }
        let allowed = Set(FootprintDataExchangeCategory.selectableCases(for: .databasePackage))
        let describedCategories = Set(descriptor.categories).intersection(allowed)
        let categories = FootprintDataExchangeCategory.dependencyClosure(for: describedCategories)
        guard !categories.isEmpty else {
            loadError = DatabaseTransferError.invalidPackage(
                "The package contains no supported selective data category."
            ).localizedDescription
            return
        }
        guard flushAllPendingPersistenceIfNeeded() else {
            notice = StoreNotice(
                message: language.text(
                    "Import was stopped because pending changes could not be saved.",
                    "Importen stoppades eftersom väntande ändringar inte kunde sparas."
                ),
                tone: .error
            )
            return
        }

        let attachmentRevision = Self.currentManagedAttachmentRevision()
        let previousSnapshot = currentSnapshot()
        let previousArchivedRecords: [ArchivedRecordEnvelope]
        let previousReceivedGrantsData: Data?
        do {
            previousArchivedRecords = try loadArchivedRecords()
            previousReceivedGrantsData = try loadReceivedGrantsData()
        } catch {
            loadError = error.localizedDescription
            notice = StoreNotice(
                message: language.text(
                    "Import was stopped because the current auxiliary data could not be read.",
                    "Importen stoppades eftersom nuvarande kompletterande data inte kunde läsas."
                ),
                tone: .error
            )
            return
        }
        let language = language
        performBackgroundOperation(
            startMessage: language.text("Preparing selected database data…", "Förbereder valda databasdata…"),
            failureMessage: language.text("Database import failed.", "Databasimporten misslyckades."),
            work: {
                let payload = try Self.decodeRestorePayload(from: source.payloadURL)
                let mergedSnapshot = Self.mergedDatabaseSnapshot(
                    current: previousSnapshot,
                    incoming: payload.snapshot,
                    categories: categories
                )
                try Self.createForcedBackupSnapshot(
                    snapshot: previousSnapshot,
                    archivedRecords: previousArchivedRecords,
                    receivedGrantsData: previousReceivedGrantsData,
                    prefix: "pre-selective-import",
                    expectedAttachmentRevision: attachmentRevision
                )
                return SelectiveDatabaseImportResult(
                    previousSnapshot: previousSnapshot,
                    mergedSnapshot: mergedSnapshot,
                    previousArchivedRecords: previousArchivedRecords,
                    previousReceivedGrantsData: previousReceivedGrantsData
                )
            }
        ) { result in
            do {
                try self.requireUnchangedDataForDestructiveCommit(
                    snapshot: result.previousSnapshot,
                    archivedRecords: result.previousArchivedRecords,
                    receivedGrantsData: result.previousReceivedGrantsData
                )
                let payload = RestorePayload(
                    snapshot: result.mergedSnapshot,
                    archivedRecords: nil,
                    receivedGrantsData: nil,
                    sourceDirectoryURL: nil,
                    replacesArchivedRecords: false,
                    replacesReceivedGrantsData: false
                )
                // The revision check, atomic storage commit and memory publish
                // intentionally share one MainActor turn so edits cannot
                // interleave and then be overwritten.
                let persistedCache = try Self.writeRestorePayloadToStorage(
                    payload,
                    expectedReport: Self.healthReport(for: result.mergedSnapshot)
                )
                self.restoreSnapshotWithoutUndo(result.mergedSnapshot)
                self.persistedDocumentCache = persistedCache
                self.backupSnapshotsCache = try? Self.loadBackupSnapshots()
                self.registerUndo(
                    snapshot: result.previousSnapshot,
                    actionName: language.text("Import selected database data", "Importera valda databasdata")
                )
                self.notice = StoreNotice(
                    message: language.text(
                        "Imported selected data after creating a verified safety backup.",
                        "Importerade valda data efter att en verifierad säkerhetsbackup skapats."
                    ),
                    tone: .success
                )
                self.loadError = nil
            } catch {
                self.loadError = error.localizedDescription
                self.notice = StoreNotice(
                    message: language.text(
                        "Import was cancelled because local data changed or the commit could not be verified.",
                        "Importen avbröts eftersom lokala data ändrades eller committen inte kunde verifieras."
                    ),
                    tone: .error
                )
            }
        }
    }

    nonisolated private static func writeDatabaseExportPackage(
        snapshot: Snapshot,
        archivedRecords: [ArchivedRecordEnvelope],
        receivedGrantsData: Data?,
        descriptor: FootprintDatabaseExportDescriptor,
        destinationURL: URL,
        expectedAttachmentRevision: UInt64,
        language: AppLanguage
    ) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw DatabaseTransferError.destinationExists
        }
        let stagingURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".footprint-export-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        var published = false
        defer {
            if !published {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        let payloadURL = stagingURL.appendingPathComponent(descriptor.payloadDirectoryName, isDirectory: true)
        _ = try writeVerifiedBackupPackage(
            snapshot: snapshot,
            archivedRecords: archivedRecords,
            receivedGrantsData: receivedGrantsData,
            finalDirectory: payloadURL,
            expectedAttachmentRevision: expectedAttachmentRevision
        )
        let descriptorURL = stagingURL.appendingPathComponent(databaseExportDescriptorFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(descriptor).write(to: descriptorURL, options: .atomic)
        // F1b: a readable list of the attachments, next to (not inside) the
        // payload, so import and payload verification never see it.
        try writeDatabaseExportAttachmentList(
            snapshot: snapshot,
            packageDirectory: stagingURL,
            payloadDirectoryName: descriptor.payloadDirectoryName,
            language: language
        )
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        published = true
    }

    nonisolated private static func databaseImportSource(
        for selectedURL: URL
    ) throws -> DatabaseImportSource {
        let descriptorURL = selectedURL.appendingPathComponent(databaseExportDescriptorFileName)
        guard FileManager.default.fileExists(atPath: descriptorURL.path) else {
            _ = try decodeRestorePayload(from: selectedURL)
            return DatabaseImportSource(payloadURL: selectedURL, descriptor: nil)
        }
        let descriptor = try JSONDecoder().decode(
            FootprintDatabaseExportDescriptor.self,
            from: Data(contentsOf: descriptorURL)
        )
        guard FootprintDatabaseExportDescriptor.supportedFormatVersions.contains(descriptor.formatVersion),
              descriptor.payloadDirectoryName == databaseExportPayloadDirectoryName else {
            throw DatabaseTransferError.invalidPackage("This database package version is not supported.")
        }
        let payloadURL = selectedURL.appendingPathComponent(descriptor.payloadDirectoryName, isDirectory: true)
        _ = try decodeRestorePayload(from: payloadURL)
        return DatabaseImportSource(payloadURL: payloadURL, descriptor: descriptor)
    }

    nonisolated private static func selectiveDatabaseSnapshot(
        from source: Snapshot,
        categories: Set<FootprintDataExchangeCategory>
    ) -> Snapshot {
        Snapshot(
            applications: categories.contains(.applications) ? source.applications : [],
            metadata: .bundledDefault,
            organizations: categories.contains(.organizations) ? source.organizations : [],
            managers: categories.contains(.organizations) ? source.managers : [],
            projects: categories.contains(.projects) ? source.projects : [],
            teachingCourses: categories.contains(.teaching) ? source.teachingCourses : [],
            teachingComponents: categories.contains(.teaching) ? source.teachingComponents : [],
            teachingFormats: categories.contains(.teaching) ? source.teachingFormats : [],
            teachingAssignments: categories.contains(.teaching) ? source.teachingAssignments : [],
            doctoralCandidates: [],
            cvPersonalResume: CVPersonalResume(),
            cvConferenceContributions: [],
            cvMediaAppearances: [],
            cvReviewEntries: [],
            cvOtherPublications: [],
            publicationAuthors: categories.contains(.researchers) ? source.publicationAuthors : [],
            publicationJournals: categories.contains(.journals) ? source.publicationJournals : [],
            publicationRecords: []
        )
    }

    nonisolated private static func mergedDatabaseSnapshot(
        current: Snapshot,
        incoming: Snapshot,
        categories: Set<FootprintDataExchangeCategory>
    ) -> Snapshot {
        Snapshot(
            applications: categories.contains(.applications)
                ? mergeDatabaseRecords(current.applications, incoming.applications)
                : current.applications,
            metadata: current.metadata,
            organizations: categories.contains(.organizations)
                ? mergeDatabaseRecords(current.organizations, incoming.organizations)
                : current.organizations,
            managers: categories.contains(.organizations)
                ? mergeDatabaseRecords(current.managers, incoming.managers)
                : current.managers,
            projects: categories.contains(.projects)
                ? mergeDatabaseRecords(current.projects, incoming.projects)
                : current.projects,
            teachingCourses: categories.contains(.teaching)
                ? mergeDatabaseRecords(current.teachingCourses, incoming.teachingCourses)
                : current.teachingCourses,
            teachingComponents: categories.contains(.teaching)
                ? mergeDatabaseRecords(current.teachingComponents, incoming.teachingComponents)
                : current.teachingComponents,
            teachingFormats: categories.contains(.teaching)
                ? mergeDatabaseRecords(current.teachingFormats, incoming.teachingFormats)
                : current.teachingFormats,
            teachingAssignments: categories.contains(.teaching)
                ? mergeDatabaseRecords(current.teachingAssignments, incoming.teachingAssignments)
                : current.teachingAssignments,
            doctoralCandidates: current.doctoralCandidates,
            cvPersonalResume: current.cvPersonalResume,
            cvConferenceContributions: current.cvConferenceContributions,
            cvMediaAppearances: current.cvMediaAppearances,
            cvReviewEntries: current.cvReviewEntries,
            cvOtherPublications: current.cvOtherPublications,
            publicationAuthors: categories.contains(.researchers)
                ? mergeDatabaseRecords(current.publicationAuthors, incoming.publicationAuthors)
                : current.publicationAuthors,
            publicationJournals: categories.contains(.journals)
                ? mergeDatabaseJournals(current: current.publicationJournals, incoming: incoming.publicationJournals)
                : current.publicationJournals,
            publicationRecords: current.publicationRecords
        )
    }

    nonisolated private static func mergeDatabaseRecords<Record: Identifiable>(
        _ current: [Record],
        _ incoming: [Record]
    ) -> [Record] where Record.ID == String {
        var merged = current
        var indices: [String: Int] = [:]
        for index in current.indices where indices[current[index].id] == nil {
            indices[current[index].id] = index
        }
        for record in incoming {
            if let index = indices[record.id] {
                merged[index] = record
            } else {
                indices[record.id] = merged.count
                merged.append(record)
            }
        }
        return merged
    }

    nonisolated private static func mergeDatabaseJournals(
        current: [PublicationJournal],
        incoming: [PublicationJournal]
    ) -> [PublicationJournal] {
        var merged = current
        for journal in incoming {
            // An exact ID match is authoritative; a higher fuzzy
            // title/ISSN score must not redirect the merge onto a
            // different local journal and leave the ID match stale.
            let match = merged.firstIndex(where: { $0.id == journal.id })
                ?? merged.indices
                    .map { ($0, merged[$0].transferIdentityMatchScore(with: journal)) }
                    .filter { $0.1 >= 2 }
                    .max { $0.1 < $1.1 }?
                    .0
            if let match {
                merged[match] = journal.replacingTransferIdentity(withLocalID: merged[match].id)
            } else {
                merged.append(journal)
            }
        }
        return merged
    }
}

private enum DatabaseTransferError: LocalizedError {
    case destinationExists
    case invalidPackage(String)

    var errorDescription: String? {
        switch self {
        case .destinationExists:
            return "A file or folder already exists at the selected export destination."
        case let .invalidPackage(message):
            return message
        }
    }
}
