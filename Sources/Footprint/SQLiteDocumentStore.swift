import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func sqlitePersistenceEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return encoder
}

struct RelationalSQLiteIntegritySummary: Hashable {
    var checkedReferenceCount: Int
    var brokenReferenceCount: Int
    var duplicateIdentityCount: Int
}

enum SQLiteHealthCheckOutcome: Hashable {
    case passed
    case failed([String])
    case unavailable(String)

    var isPassed: Bool {
        if case .passed = self { return true }
        return false
    }

    var isConfirmedFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

struct SQLiteStorageHealthSummary: Hashable {
    var integrityCheck: SQLiteHealthCheckOutcome
    var quickCheck: SQLiteHealthCheckOutcome
    var foreignKeyCheck: SQLiteHealthCheckOutcome
    var pageCount: Int
    var freelistCount: Int
    var pageSize: Int
    var searchIndexCount: Int
    var checkedAt: Date

    var integrityCheckPassed: Bool { integrityCheck.isPassed }
    var quickCheckPassed: Bool { quickCheck.isPassed }
    var foreignKeyViolationCount: Int {
        if case let .failed(violations) = foreignKeyCheck { return violations.count }
        return 0
    }

    var usedBytes: Int {
        max(0, pageCount - freelistCount) * pageSize
    }

    var freeBytes: Int {
        max(0, freelistCount) * pageSize
    }
}

struct SQLiteRuntimeSettingsSummary: Hashable {
    var journalMode: String
    var synchronous: Int
    var foreignKeysEnabled: Bool
    var busyTimeoutMilliseconds: Int
    var cacheSizePages: Int
    var mmapSizeBytes: Int
}

struct SQLiteQueryPlanObservation: Hashable {
    var name: String
    var detailLines: [String]

    var usesFullTableScan: Bool {
        detailLines.contains { detail in
            let normalized = detail.uppercased()
            return normalized.contains("SCAN ")
                && !normalized.contains("USING INDEX")
                && !normalized.contains("USING COVERING INDEX")
                && !normalized.contains("VIRTUAL TABLE")
        }
    }

    var summary: String {
        detailLines.joined(separator: " | ")
    }
}

final class SQLiteDocumentStore {
    enum StoreError: LocalizedError {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
        case bindFailed(String)
        case transactionFailed(String)

        var errorDescription: String? {
            switch self {
            case let .openFailed(message),
                 let .prepareFailed(message),
                 let .stepFailed(message),
                 let .bindFailed(message),
                 let .transactionFailed(message):
                return message
            }
        }
    }

    private let databaseURL: URL
    private var database: OpaquePointer?
    private(set) var isReadOnly = false
    private(set) var lastIncrementalRelationalTablesUpdated: Set<String> = []
    private(set) var lastIncrementalRelationalRowChanges: [String: Int] = [:]
    private static let relationalTableNames = [
        "rel_organizations",
        "rel_projects",
        "rel_applications",
        "rel_publication_authors",
        "rel_publications",
        "rel_congresses",
        "rel_calendar_travel",
        "rel_calendar_accommodation",
        "rel_calendar_meetings",
        "rel_conference_contributions",
        "rel_congress_participants",
        "rel_congress_funding",
        "rel_congress_travel",
        "rel_congress_accommodation",
        "rel_conference_contribution_congresses",
        "rel_conference_contribution_authors",
        "rel_calendar_meeting_projects",
        "rel_calendar_meeting_organizations",
        "rel_calendar_meeting_applications",
        "rel_calendar_meeting_publications",
        "rel_search_index",
    ]
    private static let currentPhysicalSchemaVersion = 4
    private static let relationalSchemaStatements = [
        "CREATE TABLE IF NOT EXISTS rel_metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS rel_organizations (id TEXT PRIMARY KEY NOT NULL, name_sv TEXT NOT NULL DEFAULT '', name_en TEXT NOT NULL DEFAULT '');",
        "CREATE TABLE IF NOT EXISTS rel_projects (id TEXT PRIMARY KEY NOT NULL, name_sv TEXT NOT NULL DEFAULT '', name_en TEXT NOT NULL DEFAULT '');",
        "CREATE TABLE IF NOT EXISTS rel_applications (id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL DEFAULT '', organization_id TEXT, project_id TEXT, status TEXT NOT NULL DEFAULT '');",
        "CREATE TABLE IF NOT EXISTS rel_publication_authors (id TEXT PRIMARY KEY NOT NULL, display_name TEXT NOT NULL DEFAULT '');",
        "CREATE TABLE IF NOT EXISTS rel_publications (id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL DEFAULT '', project_id TEXT, journal TEXT NOT NULL DEFAULT '', year TEXT NOT NULL DEFAULT '');",
        "CREATE TABLE IF NOT EXISTS rel_congresses (id TEXT PRIMARY KEY NOT NULL, organization_id TEXT NOT NULL, congress_id TEXT NOT NULL, title TEXT NOT NULL DEFAULT '', from_date TEXT NOT NULL DEFAULT '', to_date TEXT NOT NULL DEFAULT '');",
        "CREATE TABLE IF NOT EXISTS rel_calendar_travel (id TEXT PRIMARY KEY NOT NULL, date TEXT NOT NULL DEFAULT '', arrival_date TEXT NOT NULL DEFAULT '', departure_time TEXT NOT NULL DEFAULT '', arrival_time TEXT NOT NULL DEFAULT '', mode TEXT NOT NULL DEFAULT '', from_city TEXT NOT NULL DEFAULT '', from_country TEXT NOT NULL DEFAULT '', to_city TEXT NOT NULL DEFAULT '', to_country TEXT NOT NULL DEFAULT '', congress_organization_id TEXT, congress_id TEXT);",
        "CREATE TABLE IF NOT EXISTS rel_calendar_accommodation (id TEXT PRIMARY KEY NOT NULL, hotel_name TEXT NOT NULL DEFAULT '', check_in_date TEXT NOT NULL DEFAULT '', check_in_time TEXT NOT NULL DEFAULT '', check_out_date TEXT NOT NULL DEFAULT '', check_out_time TEXT NOT NULL DEFAULT '', city TEXT NOT NULL DEFAULT '', country TEXT NOT NULL DEFAULT '', congress_organization_id TEXT, congress_id TEXT);",
        "CREATE TABLE IF NOT EXISTS rel_calendar_meetings (id TEXT PRIMARY KEY NOT NULL, date TEXT NOT NULL DEFAULT '', start_time TEXT NOT NULL DEFAULT '', end_time TEXT NOT NULL DEFAULT '', title TEXT NOT NULL DEFAULT '', meeting_type TEXT NOT NULL DEFAULT '');",
        "CREATE TABLE IF NOT EXISTS rel_conference_contributions (id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT '', from_date TEXT NOT NULL DEFAULT '', to_date TEXT NOT NULL DEFAULT '', congress_organization_id TEXT, congress_id TEXT);",
        "CREATE TABLE IF NOT EXISTS rel_congress_participants (id TEXT PRIMARY KEY NOT NULL, organization_id TEXT NOT NULL, congress_id TEXT NOT NULL, congress_record_id TEXT NOT NULL, author_id TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS rel_congress_funding (id TEXT PRIMARY KEY NOT NULL, organization_id TEXT NOT NULL, congress_id TEXT NOT NULL, congress_record_id TEXT NOT NULL, application_id TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS rel_congress_travel (id TEXT PRIMARY KEY NOT NULL, organization_id TEXT NOT NULL, congress_id TEXT NOT NULL, congress_record_id TEXT NOT NULL, travel_id TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS rel_congress_accommodation (id TEXT PRIMARY KEY NOT NULL, organization_id TEXT NOT NULL, congress_id TEXT NOT NULL, congress_record_id TEXT NOT NULL, accommodation_id TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS rel_conference_contribution_congresses (id TEXT PRIMARY KEY NOT NULL, contribution_id TEXT NOT NULL, organization_id TEXT NOT NULL, congress_id TEXT NOT NULL, congress_record_id TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS rel_conference_contribution_authors (id TEXT PRIMARY KEY NOT NULL, contribution_id TEXT NOT NULL, author_id TEXT NOT NULL, role TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS rel_calendar_meeting_projects (id TEXT PRIMARY KEY NOT NULL, meeting_id TEXT NOT NULL, project_id TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS rel_calendar_meeting_organizations (id TEXT PRIMARY KEY NOT NULL, meeting_id TEXT NOT NULL, organization_id TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS rel_calendar_meeting_applications (id TEXT PRIMARY KEY NOT NULL, meeting_id TEXT NOT NULL, application_id TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS rel_calendar_meeting_publications (id TEXT PRIMARY KEY NOT NULL, meeting_id TEXT NOT NULL, publication_id TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS rel_search_index (id TEXT PRIMARY KEY NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, title TEXT NOT NULL DEFAULT '', subtitle TEXT NOT NULL DEFAULT '', body TEXT NOT NULL DEFAULT '', date_value TEXT NOT NULL DEFAULT '');",
    ]

    init(url: URL, createIfMissing: Bool = true) throws {
        self.databaseURL = url
        let fileManager = FileManager.default
        let databaseExisted = fileManager.fileExists(atPath: url.path)

        if databaseExisted {
            try openConnection(flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX)
            _ = sqlite3_busy_timeout(database, 1500)
            try execute("PRAGMA query_only=ON;")

            if let storedVersion = try storedMetadataSchemaVersion(),
               storedVersion > DataSourceMetadata.currentSchemaVersion {
                isReadOnly = true
                return
            }
            if let physicalVersion = try storedPhysicalSchemaVersion(),
               physicalVersion > Self.currentPhysicalSchemaVersion {
                isReadOnly = true
                return
            }

            try closeConnection()
        } else {
            guard createIfMissing else {
                throw StoreError.openFailed("SQLite store does not exist at \(url.path).")
            }
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        let creationFlag = databaseExisted ? 0 : SQLITE_OPEN_CREATE
        try openConnection(flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | creationFlag)
        try configureWritableConnection()
    }

    private func openConnection(flags: Int32) throws {
        let result = sqlite3_open_v2(databaseURL.path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error."
            sqlite3_close_v2(database)
            self.database = nil
            throw StoreError.openFailed("Could not open SQLite store: \(message)")
        }
        self.database = database
    }

    private func closeConnection() throws {
        guard let openDatabase = database else { return }
        database = nil
        guard sqlite3_close_v2(openDatabase) == SQLITE_OK else {
            database = openDatabase
            throw StoreError.transactionFailed("Could not close SQLite store.")
        }
    }

    private func storedMetadataSchemaVersion() throws -> Int? {
        guard try relationalTableExists("documents"),
              let metadataData = try loadData(named: "metadata") else {
            return nil
        }
        let object = try JSONSerialization.jsonObject(with: metadataData)
        guard let dictionary = object as? [String: Any] else {
            throw StoreError.stepFailed("Stored metadata is not a JSON object.")
        }
        if let version = dictionary["schemaVersion"] as? NSNumber {
            return version.intValue
        }
        if let version = dictionary["schema_version"] as? NSNumber {
            return version.intValue
        }
        return nil
    }

    private func storedPhysicalSchemaVersion() throws -> Int? {
        guard try relationalTableExists("schema_migrations") else { return nil }
        return try optionalScalarInt("SELECT MAX(id) FROM schema_migrations;")
    }

    private func configureWritableConnection() throws {
        guard let database else {
            throw StoreError.openFailed("SQLite store is not open.")
        }
        _ = sqlite3_busy_timeout(database, 5000)
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("PRAGMA temp_store=MEMORY;")
        try execute("PRAGMA foreign_keys=ON;")
        try execute("PRAGMA busy_timeout=5000;")
        try? execute("PRAGMA cache_size=-20000;")
        try? execute("PRAGMA mmap_size=268435456;")
        try applyPhysicalSchemaMigrations()
    }

    private func applyPhysicalSchemaMigrations() throws {
        if try !relationalTableExists("schema_migrations") {
            try performImmediateTransaction {
                try execute(
                    "CREATE TABLE schema_migrations (id INTEGER PRIMARY KEY NOT NULL, name TEXT NOT NULL, applied_at REAL NOT NULL);"
                )
            }
        }
        let migrations: [(id: Int, name: String)] = [
            (1, "core_documents"),
            (2, "id_aliases"),
            (3, "relational_projection"),
            (4, "calendar_time_columns"),
        ]
        let applied = Set(try appliedSchemaMigrationIDs())
        var didSnapshotBeforeMigration = false
        for migration in migrations {
            if applied.contains(migration.id) {
                guard try verifyPhysicalMigration(migration.id) else {
                    throw StoreError.transactionFailed(
                        "Physical schema migration \(migration.id) is recorded but its schema verification failed."
                    )
                }
                continue
            }
            // DDL used to run with no safety copy at all. Before the first
            // unapplied migration touches a database that holds documents,
            // keep a one-time file snapshot under Backups (fresh or empty
            // databases - including export packages - have nothing to copy).
            if !didSnapshotBeforeMigration,
               try !verifyPhysicalMigration(migration.id),
               try relationalTableExists("documents"),
               try documentCount() > 0 {
                didSnapshotBeforeMigration = true
                Self.snapshotDatabaseBeforePhysicalMigration(databaseURL: databaseURL, migrationID: migration.id)
            }
            try performImmediateTransaction {
                if try !verifyPhysicalMigration(migration.id) {
                    try applyPhysicalMigration(migration.id)
                }
                guard try verifyPhysicalMigration(migration.id) else {
                    throw StoreError.transactionFailed(
                        "Physical schema migration \(migration.id) did not pass verification."
                    )
                }
                try insertSchemaMigration(id: migration.id, name: migration.name)
            }
        }
        guard try appliedSchemaMigrationIDs() == migrations.map(\.id) else {
            throw StoreError.transactionFailed("Physical schema migration ledger is incomplete or out of order.")
        }
    }

    nonisolated private static func snapshotDatabaseBeforePhysicalMigration(databaseURL: URL, migrationID: Int) {
        let fileManager = FileManager.default
        // Lives under Backups like "Recovery Quarantine": the backup and
        // attachment scanners ignore non-timestamp directories there, whereas
        // an unexpected directory in the storage root fails verification.
        let directory = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("Pre-Migration Snapshots", isDirectory: true)
        let destination = directory.appendingPathComponent(
            "pre-physical-migration-\(migrationID)",
            isDirectory: true
        )
        // One snapshot per migration id; a concurrent connection racing this
        // best-effort copy is harmless.
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        try? fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.copyItem(
                at: source,
                to: destination.appendingPathComponent(source.lastPathComponent)
            )
        }
    }

    private func applyPhysicalMigration(_ id: Int) throws {
        switch id {
        case 1:
            try execute("CREATE TABLE IF NOT EXISTS documents (key TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL, updated_at REAL NOT NULL);")
            try execute("CREATE INDEX IF NOT EXISTS idx_documents_updated_at ON documents(updated_at);")
        case 2:
            try createIDAliasSchema()
        case 3:
            for statement in Self.relationalSchemaStatements {
                try execute(statement)
            }
            try createRelationalIndexes()
        case 4:
            try addRelationalColumnIfNeeded(tableName: "rel_calendar_travel", columnName: "departure_time", definition: "TEXT NOT NULL DEFAULT ''")
            try addRelationalColumnIfNeeded(tableName: "rel_calendar_travel", columnName: "arrival_time", definition: "TEXT NOT NULL DEFAULT ''")
            try addRelationalColumnIfNeeded(tableName: "rel_calendar_accommodation", columnName: "check_in_time", definition: "TEXT NOT NULL DEFAULT ''")
            try addRelationalColumnIfNeeded(tableName: "rel_calendar_accommodation", columnName: "check_out_time", definition: "TEXT NOT NULL DEFAULT ''")
        default:
            throw StoreError.transactionFailed("Unknown physical schema migration \(id).")
        }
    }

    private func verifyPhysicalMigration(_ id: Int) throws -> Bool {
        switch id {
        case 1:
            return try relationalTableExists("documents")
                && relationalIndexExists("idx_documents_updated_at")
        case 2:
            return try relationalTableExists("id_aliases")
                && relationalIndexExists("idx_id_aliases_new_id")
        case 3:
            return try Self.relationalTableNames.allSatisfy { try relationalTableExists($0) }
                && relationalTableExists("rel_metadata")
                && relationalIndexExists("idx_rel_search_entity")
        case 4:
            return try relationalColumnExists(tableName: "rel_calendar_travel", columnName: "departure_time")
                && relationalColumnExists(tableName: "rel_calendar_travel", columnName: "arrival_time")
                && relationalColumnExists(tableName: "rel_calendar_accommodation", columnName: "check_in_time")
                && relationalColumnExists(tableName: "rel_calendar_accommodation", columnName: "check_out_time")
        default:
            return false
        }
    }

    private func insertSchemaMigration(id: Int, name: String) throws {
        guard let statement = try prepare(
            "INSERT INTO schema_migrations (id, name, applied_at) VALUES (?, ?, ?);"
        ) else { return }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int64(statement, 1, sqlite3_int64(id)) == SQLITE_OK else {
            throw StoreError.bindFailed(lastErrorMessage())
        }
        try bindText(name, at: 2, in: statement)
        guard sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970) == SQLITE_OK else {
            throw StoreError.bindFailed(lastErrorMessage())
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.stepFailed(lastErrorMessage())
        }
    }

    func appliedSchemaMigrationIDs() throws -> [Int] {
        guard try relationalTableExists("schema_migrations"),
              let statement = try prepare("SELECT id FROM schema_migrations ORDER BY id;") else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        var ids: [Int] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                ids.append(Int(sqlite3_column_int64(statement, 0)))
            case SQLITE_DONE:
                return ids
            default:
                throw StoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    private init(readOnlyURL url: URL) throws {
        self.databaseURL = url
        self.isReadOnly = true
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        try openConnection(flags: flags)
        guard let database else { return }
        _ = sqlite3_busy_timeout(database, 1500)
        try execute("PRAGMA query_only=ON;")
    }

    deinit {
        if let database {
            sqlite3_close_v2(database)
        }
    }

    func containsDocument(named key: String) throws -> Bool {
        let sql = "SELECT 1 FROM documents WHERE key = ? LIMIT 1;"
        guard let statement = try prepare(sql) else { return false }
        defer { sqlite3_finalize(statement) }
        try bindText(key, at: 1, in: statement)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw StoreError.stepFailed(lastErrorMessage())
        }
    }

    func documentCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM documents;")
    }

    func checkpointAndClose() throws {
        try execute("PRAGMA wal_checkpoint(TRUNCATE);")
        guard let openDatabase = database else { return }
        database = nil
        guard sqlite3_close_v2(openDatabase) == SQLITE_OK else {
            throw StoreError.transactionFailed("Could not close SQLite store.")
        }
    }

    struct CompactionResult {
        let didCompact: Bool
        let fileBytesBefore: Int
        let fileBytesAfter: Int
        let freelistRatioBefore: Double
    }

    // Whole-document rewrites leave heavy freelist churn behind, and SQLite
    // never returns that space on its own — the file only ever grows.
    func compactIfNeeded(
        minimumFileBytes: Int = 16_000_000,
        freelistRatioThreshold: Double = 0.25
    ) throws -> CompactionResult {
        let pageSize = try scalarInt("PRAGMA page_size;")
        let pageCount = try scalarInt("PRAGMA page_count;")
        let freelistCount = try scalarInt("PRAGMA freelist_count;")
        let fileBytes = pageSize * pageCount
        let ratio = pageCount > 0 ? Double(freelistCount) / Double(pageCount) : 0
        guard fileBytes >= minimumFileBytes, ratio >= freelistRatioThreshold else {
            return CompactionResult(
                didCompact: false,
                fileBytesBefore: fileBytes,
                fileBytesAfter: fileBytes,
                freelistRatioBefore: ratio
            )
        }
        try execute("VACUUM;")
        let pageCountAfter = try scalarInt("PRAGMA page_count;")
        return CompactionResult(
            didCompact: true,
            fileBytesBefore: fileBytes,
            fileBytesAfter: pageSize * pageCountAfter,
            freelistRatioBefore: ratio
        )
    }

    func integrityCheckPassed() throws -> Bool {
        switch try conclusiveHealthCheck(sql: "PRAGMA integrity_check;") {
        case .passed:
            return true
        case .failed:
            return false
        case let .unavailable(message):
            throw StoreError.stepFailed(message)
        }
    }

    func quickCheckPassed() throws -> Bool {
        switch try conclusiveHealthCheck(sql: "PRAGMA quick_check;") {
        case .passed:
            return true
        case .failed:
            return false
        case let .unavailable(message):
            throw StoreError.stepFailed(message)
        }
    }

    func foreignKeyViolationCount() throws -> Int {
        guard let statement = try prepare("PRAGMA foreign_key_check;") else { return 0 }
        defer { sqlite3_finalize(statement) }
        var count = 0
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                count += 1
            case SQLITE_DONE:
                // Existing production relational tables predate physical
                // FOREIGN KEY clauses. Keep their format untouched and add
                // the complete non-destructive reference audit so this health
                // value cannot report a false zero.
                return count + (try relationalIntegritySummary().brokenReferenceCount)
            default:
                throw StoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    func storageHealthSummary() throws -> SQLiteStorageHealthSummary {
        let healthStore = try SQLiteDocumentStore(readOnlyURL: databaseURL)
        return try healthStore.storageHealthSummaryOnCurrentConnection()
    }

    private func storageHealthSummaryOnCurrentConnection() throws -> SQLiteStorageHealthSummary {
        SQLiteStorageHealthSummary(
            integrityCheck: healthCheckWithRetry(sql: "PRAGMA integrity_check;"),
            quickCheck: healthCheckWithRetry(sql: "PRAGMA quick_check;"),
            foreignKeyCheck: foreignKeyCheckWithRetry(),
            pageCount: try scalarInt("PRAGMA page_count;"),
            freelistCount: try scalarInt("PRAGMA freelist_count;"),
            pageSize: try scalarInt("PRAGMA page_size;"),
            searchIndexCount: (try? searchIndexCount()) ?? 0,
            checkedAt: Date()
        )
    }

    private func conclusiveHealthCheck(sql: String) throws -> SQLiteHealthCheckOutcome {
        let rows = try healthCheckRows(sql: sql, columnCount: 1)
        guard !rows.isEmpty else {
            return .unavailable("SQLite returned no result for \(sql)")
        }
        if rows.count == 1, rows[0].lowercased() == "ok" {
            return .passed
        }
        return .failed(rows)
    }

    private func healthCheckWithRetry(sql: String) -> SQLiteHealthCheckOutcome {
        healthCheckWithRetry {
            try conclusiveHealthCheck(sql: sql)
        }
    }

    private func foreignKeyCheckWithRetry() -> SQLiteHealthCheckOutcome {
        healthCheckWithRetry {
            let rows = try healthCheckRows(sql: "PRAGMA foreign_key_check;", columnCount: 4)
            let relational = try relationalIntegritySummary()
            var failures = rows
            if relational.brokenReferenceCount > 0 {
                failures.append("relational-reference-audit:\(relational.brokenReferenceCount)")
            }
            return failures.isEmpty ? .passed : .failed(failures)
        }
    }

    private func healthCheckWithRetry(
        operation: () throws -> SQLiteHealthCheckOutcome
    ) -> SQLiteHealthCheckOutcome {
        let retryDelays: [TimeInterval] = [0, 0.1, 0.3, 0.7]
        for (attempt, delay) in retryDelays.enumerated() {
            if delay > 0 {
                guard !Thread.isMainThread else {
                    return .unavailable("SQLite health check was busy; retry requires a background operation.")
                }
                Thread.sleep(forTimeInterval: delay)
            }
            do {
                return try operation()
            } catch {
                let errorCode = database.map(sqlite3_errcode) ?? SQLITE_ERROR
                let isTransient = errorCode == SQLITE_BUSY || errorCode == SQLITE_LOCKED
                if isTransient, attempt < retryDelays.count - 1 {
                    continue
                }
                return .unavailable(error.localizedDescription)
            }
        }
        return .unavailable("SQLite health check could not be completed.")
    }

    private func healthCheckRows(sql: String, columnCount: Int32) throws -> [String] {
        guard let statement = try prepare(sql) else {
            throw StoreError.prepareFailed("Could not prepare SQLite health check: \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        var rows: [String] = []
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                let values = (0..<columnCount).map { columnText(statement, $0) }
                rows.append(values.joined(separator: " | "))
            case SQLITE_DONE:
                return rows
            default:
                throw StoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    func runtimeSettingsSummary() throws -> SQLiteRuntimeSettingsSummary {
        SQLiteRuntimeSettingsSummary(
            journalMode: try scalarText("PRAGMA journal_mode;"),
            synchronous: try scalarInt("PRAGMA synchronous;"),
            foreignKeysEnabled: try scalarInt("PRAGMA foreign_keys;") == 1,
            busyTimeoutMilliseconds: try scalarInt("PRAGMA busy_timeout;"),
            cacheSizePages: try scalarInt("PRAGMA cache_size;"),
            mmapSizeBytes: try scalarInt("PRAGMA mmap_size;")
        )
    }

    func load<T: Decodable>(_ type: T.Type, named key: String) throws -> T? {
        guard let data = try loadData(named: key) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func loadData(named key: String) throws -> Data? {
        let sql = "SELECT payload FROM documents WHERE key = ? LIMIT 1;"
        guard let statement = try prepare(sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        try bindText(key, at: 1, in: statement)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            break
        case SQLITE_DONE:
            return nil
        default:
            throw StoreError.stepFailed(lastErrorMessage())
        }
        let bytes = sqlite3_column_blob(statement, 0)
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard let bytes, count > 0 else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    func documentUpdatedAt(named key: String) throws -> TimeInterval? {
        let sql = "SELECT updated_at FROM documents WHERE key = ? LIMIT 1;"
        guard let statement = try prepare(sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        try bindText(key, at: 1, in: statement)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            break
        case SQLITE_DONE:
            return nil
        default:
            throw StoreError.stepFailed(lastErrorMessage())
        }
        return sqlite3_column_double(statement, 0)
    }

    func save<T: Encodable>(_ value: T, named key: String) throws {
        let encoder = sqlitePersistenceEncoder()
        let data = try encoder.encode(value)
        try save(data, named: key)
    }

    func save(_ data: Data, named key: String) throws {
        try saveBatch([(key, data)])
    }

    func saveBatch(_ documents: [(String, Data)]) throws {
        guard !documents.isEmpty else { return }
        try performImmediateTransaction {
            try saveBatchInCurrentTransaction(documents)
        }
    }

    func performImmediateTransaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try operation()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func saveBatchInCurrentTransaction(_ documents: [(String, Data)]) throws {
        guard !documents.isEmpty else { return }
        let idAliases = try documents
            .last(where: { $0.0 == "metadata" })
            .map { try JSONDecoder().decode(DataSourceMetadata.self, from: $0.1).idAliases ?? [] }
        let relationalSnapshot = try documents
            .last(where: { $0.0 == "relational_sqlite_snapshot" })
            .map { try JSONDecoder().decode(RelationalSQLiteSnapshot.self, from: $0.1) }
        let previousRelationalSnapshot = try relationalSnapshot == nil
            ? nil
            : load(RelationalSQLiteSnapshot.self, named: "relational_sqlite_snapshot")
        try upsertDocumentsInCurrentTransaction(documents)
        if let relationalSnapshot {
            if let previousRelationalSnapshot,
               previousRelationalSnapshot.schemaVersion == relationalSnapshot.schemaVersion {
                try updateRelationalTables(
                    from: previousRelationalSnapshot,
                    to: relationalSnapshot
                )
            } else {
                lastIncrementalRelationalTablesUpdated = []
                lastIncrementalRelationalRowChanges = [:]
                try replaceRelationalTables(with: relationalSnapshot)
            }
        }
        if let idAliases {
            try replaceIDAliases(with: idAliases)
        }
    }

    private func upsertDocumentsInCurrentTransaction(_ documents: [(String, Data)]) throws {
        guard !documents.isEmpty else { return }
        let sql = "INSERT INTO documents (key, payload, updated_at) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at;"
        guard let statement = try prepare(sql) else {
            throw StoreError.prepareFailed("Could not prepare SQLite document upsert.")
        }
        defer { sqlite3_finalize(statement) }

        for (key, data) in documents {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(key, at: 1, in: statement)
            try bindBlob(data, at: 2, in: statement)
            if sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970) != SQLITE_OK {
                throw StoreError.bindFailed(lastErrorMessage())
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    @discardableResult
    func saveMetadataBatch(
        _ documents: [(String, Data)],
        calendarSnapshot: RelationalSQLiteSnapshot?
    ) throws -> [(String, Data)] {
        var writtenDocuments = documents
        try performImmediateTransaction {
            var previousRelationalSnapshot: RelationalSQLiteSnapshot?
            var updatedRelationalSnapshot: RelationalSQLiteSnapshot?
            if let calendarSnapshot {
                let encoder = sqlitePersistenceEncoder()
                if var relationalSnapshot = try load(RelationalSQLiteSnapshot.self, named: "relational_sqlite_snapshot") {
                    previousRelationalSnapshot = relationalSnapshot
                    relationalSnapshot.generatedAt = calendarSnapshot.generatedAt
                    relationalSnapshot.calendarTravel = calendarSnapshot.calendarTravel
                    relationalSnapshot.calendarAccommodation = calendarSnapshot.calendarAccommodation
                    relationalSnapshot.calendarMeetings = calendarSnapshot.calendarMeetings
                    relationalSnapshot.relations.congressTravel = calendarSnapshot.relations.congressTravel
                    relationalSnapshot.relations.congressAccommodation = calendarSnapshot.relations.congressAccommodation
                    relationalSnapshot.relations.calendarMeetingProjects = calendarSnapshot.relations.calendarMeetingProjects
                    relationalSnapshot.relations.calendarMeetingOrganizations = calendarSnapshot.relations.calendarMeetingOrganizations
                    relationalSnapshot.relations.calendarMeetingApplications = calendarSnapshot.relations.calendarMeetingApplications
                    relationalSnapshot.relations.calendarMeetingPublications = calendarSnapshot.relations.calendarMeetingPublications
                    updatedRelationalSnapshot = relationalSnapshot
                    writtenDocuments.append(("relational_sqlite_snapshot", try encoder.encode(relationalSnapshot)))
                }
                if var relationalCore = try load(RelationalCoreSnapshot.self, named: "relational_core") {
                    relationalCore.generatedAt = calendarSnapshot.relations.generatedAt
                    relationalCore.congressTravel = calendarSnapshot.relations.congressTravel
                    relationalCore.congressAccommodation = calendarSnapshot.relations.congressAccommodation
                    relationalCore.calendarMeetingProjects = calendarSnapshot.relations.calendarMeetingProjects
                    relationalCore.calendarMeetingOrganizations = calendarSnapshot.relations.calendarMeetingOrganizations
                    relationalCore.calendarMeetingApplications = calendarSnapshot.relations.calendarMeetingApplications
                    relationalCore.calendarMeetingPublications = calendarSnapshot.relations.calendarMeetingPublications
                    writtenDocuments.append(("relational_core", try encoder.encode(relationalCore)))
                }
            }

            try upsertDocumentsInCurrentTransaction(writtenDocuments)
            if let metadataData = documents.last(where: { $0.0 == "metadata" })?.1 {
                let aliases = try JSONDecoder().decode(DataSourceMetadata.self, from: metadataData).idAliases ?? []
                try replaceIDAliases(with: aliases)
            }
            if let calendarSnapshot {
                if let previousRelationalSnapshot, let updatedRelationalSnapshot {
                    try updateRelationalTables(
                        from: previousRelationalSnapshot,
                        to: updatedRelationalSnapshot
                    )
                } else {
                    try replaceCalendarRelationalTables(with: calendarSnapshot)
                }
            }
        }
        return writtenDocuments
    }

    func deleteDocumentsInCurrentTransaction(named keys: [String]) throws {
        guard !keys.isEmpty else { return }
        let sql = "DELETE FROM documents WHERE key = ?;"
        guard let statement = try prepare(sql) else {
            throw StoreError.prepareFailed("Could not prepare SQLite document deletion.")
        }
        defer { sqlite3_finalize(statement) }

        for key in keys {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(key, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    func deleteDocuments(named keys: [String]) throws {
        guard !keys.isEmpty else { return }
        try performImmediateTransaction {
            try deleteDocumentsInCurrentTransaction(named: keys)
        }
    }

    func idAliasCount() throws -> Int {
        try createIDAliasSchema()
        return try scalarInt("SELECT COUNT(*) FROM id_aliases;")
    }

    func relationalTableCounts() throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for tableName in Self.relationalTableNames {
            guard try relationalTableExists(tableName) else {
                counts[tableName] = 0
                continue
            }
            counts[tableName] = try scalarInt("SELECT COUNT(*) FROM \(tableName);")
        }
        return counts
    }

    func relationalIndexCount() throws -> Int {
        try scalarInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND (name LIKE 'idx_rel_%' OR name LIKE 'uniq_rel_%');"
        )
    }

    func relationalQueryPlanObservations() throws -> [SQLiteQueryPlanObservation] {
        guard try relationalTableExists("rel_applications"),
              try relationalTableExists("rel_calendar_travel"),
              try relationalTableExists("rel_calendar_meetings"),
              try relationalTableExists("rel_conference_contribution_authors") else {
            return []
        }
        return try [
            explainQueryPlan(
                name: "applications-project-status",
                sql: "SELECT id FROM rel_applications WHERE project_id = 'project-1' AND status = 'Beviljat' ORDER BY title;"
            ),
            explainQueryPlan(
                name: "calendar-travel-date-mode",
                sql: "SELECT id FROM rel_calendar_travel WHERE mode = 'flight' AND date >= '2026-01-01' ORDER BY date, departure_time;"
            ),
            explainQueryPlan(
                name: "meeting-project-join",
                sql: "SELECT m.id FROM rel_calendar_meetings m JOIN rel_calendar_meeting_projects mp ON mp.meeting_id = m.id WHERE mp.project_id = 'project-1' ORDER BY m.date;"
            ),
            explainQueryPlan(
                name: "contribution-author-join",
                sql: "SELECT cc.id FROM rel_conference_contributions cc JOIN rel_conference_contribution_authors ca ON ca.contribution_id = cc.id WHERE ca.author_id = 'author-1' ORDER BY cc.from_date;"
            ),
        ]
    }

    func explainQueryPlan(name: String, sql: String) throws -> SQLiteQueryPlanObservation {
        guard let statement = try prepare("EXPLAIN QUERY PLAN \(sql)") else {
            return SQLiteQueryPlanObservation(name: name, detailLines: [])
        }
        defer { sqlite3_finalize(statement) }
        var details: [String] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                details.append(columnText(statement, 3))
            case SQLITE_DONE:
                return SQLiteQueryPlanObservation(name: name, detailLines: details)
            default:
                throw StoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    func searchIndexCount() throws -> Int {
        guard try relationalTableExists("rel_search_index") else { return 0 }
        return try scalarInt("SELECT COUNT(*) FROM rel_search_index;")
    }

    func relationalIntegritySummary() throws -> RelationalSQLiteIntegritySummary {
        for tableName in Self.relationalTableNames {
            guard try relationalTableExists(tableName) else {
                return RelationalSQLiteIntegritySummary(
                    checkedReferenceCount: 0,
                    brokenReferenceCount: 0,
                    duplicateIdentityCount: 0
                )
            }
        }

        let referenceChecks = [
            "SELECT COUNT(*) FROM rel_applications a WHERE a.organization_id IS NOT NULL AND a.organization_id != '' AND NOT EXISTS (SELECT 1 FROM rel_organizations o WHERE o.id = a.organization_id);",
            "SELECT COUNT(*) FROM rel_applications a WHERE a.project_id IS NOT NULL AND a.project_id != '' AND NOT EXISTS (SELECT 1 FROM rel_projects p WHERE p.id = a.project_id);",
            "SELECT COUNT(*) FROM rel_publications p WHERE p.project_id IS NOT NULL AND p.project_id != '' AND NOT EXISTS (SELECT 1 FROM rel_projects pr WHERE pr.id = p.project_id);",
            "SELECT COUNT(*) FROM rel_congresses c WHERE NOT EXISTS (SELECT 1 FROM rel_organizations o WHERE o.id = c.organization_id);",
            "SELECT COUNT(*) FROM rel_calendar_travel t WHERE t.congress_organization_id IS NOT NULL AND t.congress_organization_id != '' AND t.congress_id IS NOT NULL AND t.congress_id != '' AND NOT EXISTS (SELECT 1 FROM rel_congresses c WHERE c.organization_id = t.congress_organization_id AND c.congress_id = t.congress_id);",
            "SELECT COUNT(*) FROM rel_calendar_accommodation a WHERE a.congress_organization_id IS NOT NULL AND a.congress_organization_id != '' AND a.congress_id IS NOT NULL AND a.congress_id != '' AND NOT EXISTS (SELECT 1 FROM rel_congresses c WHERE c.organization_id = a.congress_organization_id AND c.congress_id = a.congress_id);",
            "SELECT COUNT(*) FROM rel_conference_contributions cc WHERE cc.congress_organization_id IS NOT NULL AND cc.congress_organization_id != '' AND cc.congress_id IS NOT NULL AND cc.congress_id != '' AND NOT EXISTS (SELECT 1 FROM rel_congresses c WHERE c.organization_id = cc.congress_organization_id AND c.congress_id = cc.congress_id);",
            "SELECT COUNT(*) FROM rel_congress_participants cp WHERE NOT EXISTS (SELECT 1 FROM rel_congresses c WHERE c.id = cp.congress_record_id);",
            "SELECT COUNT(*) FROM rel_congress_participants cp WHERE NOT EXISTS (SELECT 1 FROM rel_publication_authors a WHERE a.id = cp.author_id);",
            "SELECT COUNT(*) FROM rel_congress_funding cf WHERE NOT EXISTS (SELECT 1 FROM rel_congresses c WHERE c.id = cf.congress_record_id);",
            "SELECT COUNT(*) FROM rel_congress_funding cf WHERE NOT EXISTS (SELECT 1 FROM rel_applications a WHERE a.id = cf.application_id);",
            "SELECT COUNT(*) FROM rel_congress_travel ct WHERE NOT EXISTS (SELECT 1 FROM rel_congresses c WHERE c.id = ct.congress_record_id);",
            "SELECT COUNT(*) FROM rel_congress_travel ct WHERE NOT EXISTS (SELECT 1 FROM rel_calendar_travel t WHERE t.id = ct.travel_id);",
            "SELECT COUNT(*) FROM rel_congress_accommodation ca WHERE NOT EXISTS (SELECT 1 FROM rel_congresses c WHERE c.id = ca.congress_record_id);",
            "SELECT COUNT(*) FROM rel_congress_accommodation ca WHERE NOT EXISTS (SELECT 1 FROM rel_calendar_accommodation a WHERE a.id = ca.accommodation_id);",
            "SELECT COUNT(*) FROM rel_conference_contribution_congresses ccc WHERE NOT EXISTS (SELECT 1 FROM rel_conference_contributions cc WHERE cc.id = ccc.contribution_id);",
            "SELECT COUNT(*) FROM rel_conference_contribution_congresses ccc WHERE NOT EXISTS (SELECT 1 FROM rel_congresses c WHERE c.id = ccc.congress_record_id);",
            "SELECT COUNT(*) FROM rel_conference_contribution_authors cca WHERE NOT EXISTS (SELECT 1 FROM rel_conference_contributions cc WHERE cc.id = cca.contribution_id);",
            "SELECT COUNT(*) FROM rel_conference_contribution_authors cca WHERE NOT EXISTS (SELECT 1 FROM rel_publication_authors a WHERE a.id = cca.author_id);",
            "SELECT COUNT(*) FROM rel_calendar_meeting_projects mp WHERE NOT EXISTS (SELECT 1 FROM rel_calendar_meetings m WHERE m.id = mp.meeting_id);",
            "SELECT COUNT(*) FROM rel_calendar_meeting_projects mp WHERE NOT EXISTS (SELECT 1 FROM rel_projects p WHERE p.id = mp.project_id);",
            "SELECT COUNT(*) FROM rel_calendar_meeting_organizations mo WHERE NOT EXISTS (SELECT 1 FROM rel_calendar_meetings m WHERE m.id = mo.meeting_id);",
            "SELECT COUNT(*) FROM rel_calendar_meeting_organizations mo WHERE NOT EXISTS (SELECT 1 FROM rel_organizations o WHERE o.id = mo.organization_id);",
            "SELECT COUNT(*) FROM rel_calendar_meeting_applications ma WHERE NOT EXISTS (SELECT 1 FROM rel_calendar_meetings m WHERE m.id = ma.meeting_id);",
            "SELECT COUNT(*) FROM rel_calendar_meeting_applications ma WHERE NOT EXISTS (SELECT 1 FROM rel_applications a WHERE a.id = ma.application_id);",
            "SELECT COUNT(*) FROM rel_calendar_meeting_publications mp WHERE NOT EXISTS (SELECT 1 FROM rel_calendar_meetings m WHERE m.id = mp.meeting_id);",
            "SELECT COUNT(*) FROM rel_calendar_meeting_publications mp WHERE NOT EXISTS (SELECT 1 FROM rel_publications p WHERE p.id = mp.publication_id);",
        ]
        let duplicateChecks = [
            "SELECT COALESCE(SUM(row_count - 1), 0) FROM (SELECT COUNT(*) AS row_count FROM rel_congresses GROUP BY organization_id, congress_id HAVING COUNT(*) > 1);",
            "SELECT COALESCE(SUM(row_count - 1), 0) FROM (SELECT COUNT(*) AS row_count FROM rel_congress_participants GROUP BY organization_id, congress_id, author_id HAVING COUNT(*) > 1);",
            "SELECT COALESCE(SUM(row_count - 1), 0) FROM (SELECT COUNT(*) AS row_count FROM rel_congress_funding GROUP BY organization_id, congress_id, application_id HAVING COUNT(*) > 1);",
            "SELECT COALESCE(SUM(row_count - 1), 0) FROM (SELECT COUNT(*) AS row_count FROM rel_congress_travel GROUP BY organization_id, congress_id, travel_id HAVING COUNT(*) > 1);",
            "SELECT COALESCE(SUM(row_count - 1), 0) FROM (SELECT COUNT(*) AS row_count FROM rel_congress_accommodation GROUP BY organization_id, congress_id, accommodation_id HAVING COUNT(*) > 1);",
            "SELECT COALESCE(SUM(row_count - 1), 0) FROM (SELECT COUNT(*) AS row_count FROM rel_conference_contribution_authors GROUP BY contribution_id, author_id, role HAVING COUNT(*) > 1);",
        ]

        var brokenReferenceCount = 0
        for check in referenceChecks {
            brokenReferenceCount += try scalarInt(check)
        }
        var duplicateIdentityCount = 0
        for check in duplicateChecks {
            duplicateIdentityCount += try scalarInt(check)
        }
        return RelationalSQLiteIntegritySummary(
            checkedReferenceCount: referenceChecks.count,
            brokenReferenceCount: brokenReferenceCount,
            duplicateIdentityCount: duplicateIdentityCount
        )
    }

    func loadRelationalCalendarTravelRecords() throws -> [CalendarTravelRecord]? {
        guard try relationalTableExists("rel_calendar_travel") else { return nil }
        let sql = """
            SELECT id, date, arrival_date, departure_time, arrival_time, mode, from_city, from_country, to_city, to_country, congress_organization_id, congress_id
            FROM rel_calendar_travel
            ORDER BY date, departure_time, id;
            """
        guard let statement = try prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }

        var records: [CalendarTravelRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw StoreError.stepFailed(lastErrorMessage())
            }
            var record = CalendarTravelRecord(
                id: columnText(statement, 0),
                date: columnText(statement, 1),
                arrivalDate: columnText(statement, 2),
                departureTime: columnText(statement, 3),
                fromCity: columnText(statement, 6),
                fromCountry: columnText(statement, 7),
                arrivalTime: columnText(statement, 4),
                toCity: columnText(statement, 8),
                toCountry: columnText(statement, 9),
                mode: CalendarTravelMode(rawValue: columnText(statement, 5)) ?? .flight,
                congressOrganizationID: columnText(statement, 10),
                congressID: columnText(statement, 11)
            )
            record.normalize()
            if !record.isEmpty {
                records.append(record)
            }
        }
        return records
    }

    func loadRelationalCalendarAccommodationRecords() throws -> [CalendarAccommodationRecord]? {
        guard try relationalTableExists("rel_calendar_accommodation") else { return nil }
        let sql = """
            SELECT id, hotel_name, check_in_date, check_in_time, check_out_date, check_out_time, city, country, congress_organization_id, congress_id
            FROM rel_calendar_accommodation
            ORDER BY check_in_date, check_in_time, id;
            """
        guard let statement = try prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }

        var records: [CalendarAccommodationRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw StoreError.stepFailed(lastErrorMessage())
            }
            var record = CalendarAccommodationRecord(
                id: columnText(statement, 0),
                hotelName: columnText(statement, 1),
                checkInDate: columnText(statement, 2),
                checkInTime: columnText(statement, 3),
                checkOutDate: columnText(statement, 4),
                checkOutTime: columnText(statement, 5),
                city: columnText(statement, 6),
                country: columnText(statement, 7),
                congressOrganizationID: columnText(statement, 8),
                congressID: columnText(statement, 9)
            )
            record.normalize()
            if !record.isEmpty {
                records.append(record)
            }
        }
        return records.sorted(by: calendarAccommodationSort)
    }

    /// Updates only relational tables whose canonical projection changed.
    /// This keeps the relational snapshot document authoritative while
    /// avoiding the previous delete/reinsert of every table for a one-domain
    /// edit. A full rebuild remains the fallback for first creation and schema
    /// upgrades.
    private func updateRelationalTables(
        from previous: RelationalSQLiteSnapshot,
        to current: RelationalSQLiteSnapshot
    ) throws {
        lastIncrementalRelationalTablesUpdated = []
        lastIncrementalRelationalRowChanges = [:]
        try createRelationalSchema()
        try saveRelationalMetadata(current)

        try replaceTableIfChanged(
            previous.organizations,
            current.organizations,
            tableName: "rel_organizations",
            sql: "INSERT INTO rel_organizations (id, name_sv, name_en) VALUES (?, ?, ?);",
            rows: { $0.map { [$0.id, $0.nameSv, $0.nameEn] } },
            searchEntityType: "organization",
            searchRows: {
                $0.map { ["organization:\($0.id)", "organization", $0.id, $0.nameSv.nonEmpty ?? $0.nameEn, $0.nameEn, $0.nameSv, ""] }
            }
        )
        try replaceTableIfChanged(
            previous.projects,
            current.projects,
            tableName: "rel_projects",
            sql: "INSERT INTO rel_projects (id, name_sv, name_en) VALUES (?, ?, ?);",
            rows: { $0.map { [$0.id, $0.nameSv, $0.nameEn] } },
            searchEntityType: "project",
            searchRows: {
                $0.map { ["project:\($0.id)", "project", $0.id, $0.nameSv.nonEmpty ?? $0.nameEn, $0.nameEn, $0.nameSv, ""] }
            }
        )
        try replaceTableIfChanged(
            previous.applications,
            current.applications,
            tableName: "rel_applications",
            sql: "INSERT INTO rel_applications (id, title, organization_id, project_id, status) VALUES (?, ?, ?, ?, ?);",
            rows: { $0.map { [$0.id, $0.title, $0.organizationID, $0.projectID, $0.status] } },
            searchEntityType: "application",
            searchRows: {
                $0.map { ["application:\($0.id)", "application", $0.id, $0.title, $0.status, [$0.organizationID, $0.projectID].compactMap { $0 }.joined(separator: " "), ""] }
            }
        )
        try replaceTableIfChanged(
            previous.authors,
            current.authors,
            tableName: "rel_publication_authors",
            sql: "INSERT INTO rel_publication_authors (id, display_name) VALUES (?, ?);",
            rows: { $0.map { [$0.id, $0.displayName] } },
            searchEntityType: "author",
            searchRows: {
                $0.map { ["author:\($0.id)", "author", $0.id, $0.displayName, "", "", ""] }
            }
        )
        try replaceTableIfChanged(
            previous.publications,
            current.publications,
            tableName: "rel_publications",
            sql: "INSERT INTO rel_publications (id, title, project_id, journal, year) VALUES (?, ?, ?, ?, ?);",
            rows: { $0.map { [$0.id, $0.title, $0.projectID, $0.journal, $0.year] } },
            searchEntityType: "publication",
            searchRows: {
                $0.map { ["publication:\($0.id)", "publication", $0.id, $0.title, [$0.journal, $0.year].filter { !$0.isEmpty }.joined(separator: " "), $0.projectID ?? "", $0.year] }
            }
        )
        try replaceTableIfChanged(
            previous.relations.congresses,
            current.relations.congresses,
            key: { StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.id) },
            tableName: "rel_congresses",
            sql: "INSERT INTO rel_congresses (id, organization_id, congress_id, title, from_date, to_date) VALUES (?, ?, ?, ?, ?, ?);",
            rows: {
                $0.map { [StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.id), $0.organizationID, $0.id, $0.title, $0.from, $0.to] }
            },
            searchEntityType: "congress",
            searchRows: {
                $0.map {
                    let recordID = StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.id)
                    return ["congress:\(recordID)", "congress", recordID, $0.title, [$0.from, $0.to].filter { !$0.isEmpty }.joined(separator: " - "), $0.organizationID, $0.from]
                }
            }
        )
        try replaceTableIfChanged(
            previous.calendarTravel,
            current.calendarTravel,
            tableName: "rel_calendar_travel",
            sql: "INSERT INTO rel_calendar_travel (id, date, arrival_date, departure_time, arrival_time, mode, from_city, from_country, to_city, to_country, congress_organization_id, congress_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            rows: { $0.map { [$0.id, $0.date, $0.arrivalDate, $0.departureTime, $0.arrivalTime, $0.mode, $0.fromCity, $0.fromCountry, $0.toCity, $0.toCountry, $0.congressOrganizationID, $0.congressID] } },
            searchEntityType: "calendar_travel",
            searchRows: {
                $0.map { ["calendar_travel:\($0.id)", "calendar_travel", $0.id, [$0.fromCity, $0.toCity].filter { !$0.isEmpty }.joined(separator: " -> "), $0.mode, [$0.fromCountry, $0.toCountry, $0.congressOrganizationID, $0.congressID].compactMap { $0 }.joined(separator: " "), $0.date] }
            }
        )
        try replaceTableIfChanged(
            previous.calendarAccommodation,
            current.calendarAccommodation,
            tableName: "rel_calendar_accommodation",
            sql: "INSERT INTO rel_calendar_accommodation (id, hotel_name, check_in_date, check_in_time, check_out_date, check_out_time, city, country, congress_organization_id, congress_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            rows: { $0.map { [$0.id, $0.hotelName, $0.checkInDate, $0.checkInTime, $0.checkOutDate, $0.checkOutTime, $0.city, $0.country, $0.congressOrganizationID, $0.congressID] } },
            searchEntityType: "calendar_accommodation",
            searchRows: {
                $0.map { ["calendar_accommodation:\($0.id)", "calendar_accommodation", $0.id, $0.hotelName, [$0.checkInDate, $0.checkOutDate].filter { !$0.isEmpty }.joined(separator: " - "), [$0.city, $0.country, $0.congressOrganizationID, $0.congressID].compactMap { $0 }.joined(separator: " "), $0.checkInDate] }
            }
        )
        try replaceTableIfChanged(
            previous.calendarMeetings,
            current.calendarMeetings,
            tableName: "rel_calendar_meetings",
            sql: "INSERT INTO rel_calendar_meetings (id, date, start_time, end_time, title, meeting_type) VALUES (?, ?, ?, ?, ?, ?);",
            rows: { $0.map { [$0.id, $0.date, $0.startTime, $0.endTime, $0.title, $0.meetingType] } },
            searchEntityType: "calendar_meeting",
            searchRows: {
                $0.map { ["calendar_meeting:\($0.id)", "calendar_meeting", $0.id, $0.title, $0.meetingType, [$0.startTime, $0.endTime].filter { !$0.isEmpty }.joined(separator: " - "), $0.date] }
            }
        )
        try replaceTableIfChanged(
            previous.conferenceContributions,
            current.conferenceContributions,
            tableName: "rel_conference_contributions",
            sql: "INSERT INTO rel_conference_contributions (id, title, status, from_date, to_date, congress_organization_id, congress_id) VALUES (?, ?, ?, ?, ?, ?, ?);",
            rows: { $0.map { [$0.id, $0.title, $0.status, $0.from, $0.to, $0.congressOrganizationID, $0.congressID] } },
            searchEntityType: "conference_contribution",
            searchRows: {
                $0.map { ["conference_contribution:\($0.id)", "conference_contribution", $0.id, $0.title, $0.status, [$0.congressOrganizationID, $0.congressID].compactMap { $0 }.joined(separator: " "), $0.from] }
            }
        )

        try replaceRelationTableIfChanged(previous.relations.congressParticipants, current.relations.congressParticipants, tableName: "rel_congress_participants", sql: "INSERT INTO rel_congress_participants (id, organization_id, congress_id, congress_record_id, author_id) VALUES (?, ?, ?, ?, ?);") {
            $0.map { [$0.id, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID), $0.authorID] }
        }
        try replaceRelationTableIfChanged(previous.relations.congressFunding, current.relations.congressFunding, tableName: "rel_congress_funding", sql: "INSERT INTO rel_congress_funding (id, organization_id, congress_id, congress_record_id, application_id) VALUES (?, ?, ?, ?, ?);") {
            $0.map { [$0.id, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID), $0.applicationID] }
        }
        try replaceRelationTableIfChanged(previous.relations.congressTravel, current.relations.congressTravel, tableName: "rel_congress_travel", sql: "INSERT INTO rel_congress_travel (id, organization_id, congress_id, congress_record_id, travel_id) VALUES (?, ?, ?, ?, ?);") {
            $0.map { [$0.id, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID), $0.travelID] }
        }
        try replaceRelationTableIfChanged(previous.relations.congressAccommodation, current.relations.congressAccommodation, tableName: "rel_congress_accommodation", sql: "INSERT INTO rel_congress_accommodation (id, organization_id, congress_id, congress_record_id, accommodation_id) VALUES (?, ?, ?, ?, ?);") {
            $0.map { [$0.id, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID), $0.accommodationID] }
        }
        try replaceRelationTableIfChanged(previous.relations.conferenceContributionCongresses, current.relations.conferenceContributionCongresses, tableName: "rel_conference_contribution_congresses", sql: "INSERT INTO rel_conference_contribution_congresses (id, contribution_id, organization_id, congress_id, congress_record_id) VALUES (?, ?, ?, ?, ?);") {
            $0.map { [$0.id, $0.contributionID, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID)] }
        }
        try replaceRelationTableIfChanged(previous.relations.conferenceContributionAuthors, current.relations.conferenceContributionAuthors, tableName: "rel_conference_contribution_authors", sql: "INSERT INTO rel_conference_contribution_authors (id, contribution_id, author_id, role) VALUES (?, ?, ?, ?);") {
            $0.map { [$0.id, $0.contributionID, $0.authorID, $0.role] }
        }
        try replaceRelationTableIfChanged(previous.relations.calendarMeetingProjects, current.relations.calendarMeetingProjects, tableName: "rel_calendar_meeting_projects", sql: "INSERT INTO rel_calendar_meeting_projects (id, meeting_id, project_id) VALUES (?, ?, ?);") {
            $0.map { [$0.id, $0.meetingID, $0.projectID] }
        }
        try replaceRelationTableIfChanged(previous.relations.calendarMeetingOrganizations, current.relations.calendarMeetingOrganizations, tableName: "rel_calendar_meeting_organizations", sql: "INSERT INTO rel_calendar_meeting_organizations (id, meeting_id, organization_id) VALUES (?, ?, ?);") {
            $0.map { [$0.id, $0.meetingID, $0.organizationID] }
        }
        try replaceRelationTableIfChanged(previous.relations.calendarMeetingApplications, current.relations.calendarMeetingApplications, tableName: "rel_calendar_meeting_applications", sql: "INSERT INTO rel_calendar_meeting_applications (id, meeting_id, application_id) VALUES (?, ?, ?);") {
            $0.map { [$0.id, $0.meetingID, $0.applicationID] }
        }
        try replaceRelationTableIfChanged(previous.relations.calendarMeetingPublications, current.relations.calendarMeetingPublications, tableName: "rel_calendar_meeting_publications", sql: "INSERT INTO rel_calendar_meeting_publications (id, meeting_id, publication_id) VALUES (?, ?, ?);") {
            $0.map { [$0.id, $0.meetingID, $0.publicationID] }
        }
        try createRelationalIndexes()
    }

    private func replaceTableIfChanged<Row: Equatable & Identifiable>(
        _ previous: [Row],
        _ current: [Row],
        key: (Row) -> String = { $0.id },
        tableName: String,
        sql: String,
        rows: ([Row]) -> [[String?]],
        searchEntityType: String,
        searchRows: ([Row]) -> [[String?]]
    ) throws where Row.ID == String {
        let previousByID = Dictionary(previous.map { (key($0), $0) }, uniquingKeysWith: { _, latest in latest })
        let currentByID = Dictionary(current.map { (key($0), $0) }, uniquingKeysWith: { _, latest in latest })
        let changedIDs = Set(previousByID.keys)
            .union(currentByID.keys)
            .filter { previousByID[$0] != currentByID[$0] }
            .sorted()
        guard !changedIDs.isEmpty else { return }
        try deleteRows(in: tableName, ids: changedIDs)
        let changedRows = current.filter { changedIDs.contains(key($0)) }
        try insertRows(sql: sql, rows: rows(changedRows))
        lastIncrementalRelationalTablesUpdated.insert(tableName)
        lastIncrementalRelationalRowChanges[tableName] = changedIDs.count
        try deleteSearchRows(entityType: searchEntityType, entityIDs: changedIDs)
        try insertRows(
            sql: "INSERT INTO rel_search_index (id, entity_type, entity_id, title, subtitle, body, date_value) VALUES (?, ?, ?, ?, ?, ?, ?);",
            rows: searchRows(changedRows)
        )
    }

    private func replaceRelationTableIfChanged<Row: Equatable & Identifiable>(
        _ previous: [Row],
        _ current: [Row],
        tableName: String,
        sql: String,
        rows: ([Row]) -> [[String?]]
    ) throws where Row.ID == String {
        let previousByID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let currentByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let changedIDs = Set(previousByID.keys)
            .union(currentByID.keys)
            .filter { previousByID[$0] != currentByID[$0] }
            .sorted()
        guard !changedIDs.isEmpty else { return }
        try deleteRows(in: tableName, ids: changedIDs)
        try insertRows(sql: sql, rows: rows(current.filter { changedIDs.contains($0.id) }))
        lastIncrementalRelationalTablesUpdated.insert(tableName)
        lastIncrementalRelationalRowChanges[tableName] = changedIDs.count
    }

    private func deleteRows(in tableName: String, ids: [String]) throws {
        guard !ids.isEmpty else { return }
        guard Self.relationalTableNames.contains(tableName),
              let statement = try prepare("DELETE FROM \(tableName) WHERE id = ?;") else {
            throw StoreError.prepareFailed("Could not prepare incremental relational deletion.")
        }
        defer { sqlite3_finalize(statement) }
        for id in ids {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(id, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    private func deleteSearchRows(entityType: String, entityIDs: [String]) throws {
        guard !entityIDs.isEmpty,
              let statement = try prepare(
                "DELETE FROM rel_search_index WHERE entity_type = ? AND entity_id = ?;"
              ) else {
            throw StoreError.prepareFailed("Could not prepare incremental search-index deletion.")
        }
        defer { sqlite3_finalize(statement) }
        for id in entityIDs {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(entityType, at: 1, in: statement)
            try bindText(id, at: 2, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    private func replaceRelationalTables(with snapshot: RelationalSQLiteSnapshot) throws {
        try createRelationalSchema()
        try clearRelationalTables()
        try saveRelationalMetadata(snapshot)
        try insertRows(
            sql: "INSERT INTO rel_organizations (id, name_sv, name_en) VALUES (?, ?, ?);",
            rows: snapshot.organizations.map { [$0.id, $0.nameSv, $0.nameEn] }
        )
        try insertRows(
            sql: "INSERT INTO rel_projects (id, name_sv, name_en) VALUES (?, ?, ?);",
            rows: snapshot.projects.map { [$0.id, $0.nameSv, $0.nameEn] }
        )
        try insertRows(
            sql: "INSERT INTO rel_applications (id, title, organization_id, project_id, status) VALUES (?, ?, ?, ?, ?);",
            rows: snapshot.applications.map { [$0.id, $0.title, $0.organizationID, $0.projectID, $0.status] }
        )
        try insertRows(
            sql: "INSERT INTO rel_publication_authors (id, display_name) VALUES (?, ?);",
            rows: snapshot.authors.map { [$0.id, $0.displayName] }
        )
        try insertRows(
            sql: "INSERT INTO rel_publications (id, title, project_id, journal, year) VALUES (?, ?, ?, ?, ?);",
            rows: snapshot.publications.map { [$0.id, $0.title, $0.projectID, $0.journal, $0.year] }
        )
        try insertRows(
            sql: "INSERT INTO rel_congresses (id, organization_id, congress_id, title, from_date, to_date) VALUES (?, ?, ?, ?, ?, ?);",
            rows: snapshot.relations.congresses.map {
                [StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.id), $0.organizationID, $0.id, $0.title, $0.from, $0.to]
            }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_travel (id, date, arrival_date, departure_time, arrival_time, mode, from_city, from_country, to_city, to_country, congress_organization_id, congress_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            rows: snapshot.calendarTravel.map { [$0.id, $0.date, $0.arrivalDate, $0.departureTime, $0.arrivalTime, $0.mode, $0.fromCity, $0.fromCountry, $0.toCity, $0.toCountry, $0.congressOrganizationID, $0.congressID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_accommodation (id, hotel_name, check_in_date, check_in_time, check_out_date, check_out_time, city, country, congress_organization_id, congress_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            rows: snapshot.calendarAccommodation.map { [$0.id, $0.hotelName, $0.checkInDate, $0.checkInTime, $0.checkOutDate, $0.checkOutTime, $0.city, $0.country, $0.congressOrganizationID, $0.congressID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_meetings (id, date, start_time, end_time, title, meeting_type) VALUES (?, ?, ?, ?, ?, ?);",
            rows: snapshot.calendarMeetings.map { [$0.id, $0.date, $0.startTime, $0.endTime, $0.title, $0.meetingType] }
        )
        try insertRows(
            sql: "INSERT INTO rel_conference_contributions (id, title, status, from_date, to_date, congress_organization_id, congress_id) VALUES (?, ?, ?, ?, ?, ?, ?);",
            rows: snapshot.conferenceContributions.map { [$0.id, $0.title, $0.status, $0.from, $0.to, $0.congressOrganizationID, $0.congressID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_congress_participants (id, organization_id, congress_id, congress_record_id, author_id) VALUES (?, ?, ?, ?, ?);",
            rows: snapshot.relations.congressParticipants.map { [$0.id, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID), $0.authorID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_congress_funding (id, organization_id, congress_id, congress_record_id, application_id) VALUES (?, ?, ?, ?, ?);",
            rows: snapshot.relations.congressFunding.map { [$0.id, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID), $0.applicationID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_congress_travel (id, organization_id, congress_id, congress_record_id, travel_id) VALUES (?, ?, ?, ?, ?);",
            rows: snapshot.relations.congressTravel.map { [$0.id, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID), $0.travelID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_congress_accommodation (id, organization_id, congress_id, congress_record_id, accommodation_id) VALUES (?, ?, ?, ?, ?);",
            rows: snapshot.relations.congressAccommodation.map { [$0.id, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID), $0.accommodationID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_conference_contribution_congresses (id, contribution_id, organization_id, congress_id, congress_record_id) VALUES (?, ?, ?, ?, ?);",
            rows: snapshot.relations.conferenceContributionCongresses.map { [$0.id, $0.contributionID, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID)] }
        )
        try insertRows(
            sql: "INSERT INTO rel_conference_contribution_authors (id, contribution_id, author_id, role) VALUES (?, ?, ?, ?);",
            rows: snapshot.relations.conferenceContributionAuthors.map { [$0.id, $0.contributionID, $0.authorID, $0.role] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_meeting_projects (id, meeting_id, project_id) VALUES (?, ?, ?);",
            rows: snapshot.relations.calendarMeetingProjects.map { [$0.id, $0.meetingID, $0.projectID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_meeting_organizations (id, meeting_id, organization_id) VALUES (?, ?, ?);",
            rows: snapshot.relations.calendarMeetingOrganizations.map { [$0.id, $0.meetingID, $0.organizationID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_meeting_applications (id, meeting_id, application_id) VALUES (?, ?, ?);",
            rows: snapshot.relations.calendarMeetingApplications.map { [$0.id, $0.meetingID, $0.applicationID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_meeting_publications (id, meeting_id, publication_id) VALUES (?, ?, ?);",
            rows: snapshot.relations.calendarMeetingPublications.map { [$0.id, $0.meetingID, $0.publicationID] }
        )
        try replaceSearchIndexTables(with: snapshot)
        try createRelationalIndexes()
    }

    private func replaceCalendarRelationalTables(with snapshot: RelationalSQLiteSnapshot) throws {
        try createRelationalSchema()
        for tableName in [
            "rel_calendar_meeting_publications",
            "rel_calendar_meeting_applications",
            "rel_calendar_meeting_organizations",
            "rel_calendar_meeting_projects",
            "rel_congress_accommodation",
            "rel_congress_travel",
            "rel_calendar_meetings",
            "rel_calendar_accommodation",
            "rel_calendar_travel",
        ] {
            try execute("DELETE FROM \(tableName);")
        }
        try execute(
            "DELETE FROM rel_search_index WHERE entity_type IN ('calendar_travel', 'calendar_accommodation', 'calendar_meeting');"
        )

        try insertRows(
            sql: "INSERT INTO rel_calendar_travel (id, date, arrival_date, departure_time, arrival_time, mode, from_city, from_country, to_city, to_country, congress_organization_id, congress_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            rows: snapshot.calendarTravel.map { [$0.id, $0.date, $0.arrivalDate, $0.departureTime, $0.arrivalTime, $0.mode, $0.fromCity, $0.fromCountry, $0.toCity, $0.toCountry, $0.congressOrganizationID, $0.congressID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_accommodation (id, hotel_name, check_in_date, check_in_time, check_out_date, check_out_time, city, country, congress_organization_id, congress_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            rows: snapshot.calendarAccommodation.map { [$0.id, $0.hotelName, $0.checkInDate, $0.checkInTime, $0.checkOutDate, $0.checkOutTime, $0.city, $0.country, $0.congressOrganizationID, $0.congressID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_meetings (id, date, start_time, end_time, title, meeting_type) VALUES (?, ?, ?, ?, ?, ?);",
            rows: snapshot.calendarMeetings.map { [$0.id, $0.date, $0.startTime, $0.endTime, $0.title, $0.meetingType] }
        )
        try insertRows(
            sql: "INSERT INTO rel_congress_travel (id, organization_id, congress_id, congress_record_id, travel_id) VALUES (?, ?, ?, ?, ?);",
            rows: snapshot.relations.congressTravel.map { [$0.id, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID), $0.travelID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_congress_accommodation (id, organization_id, congress_id, congress_record_id, accommodation_id) VALUES (?, ?, ?, ?, ?);",
            rows: snapshot.relations.congressAccommodation.map { [$0.id, $0.organizationID, $0.congressID, StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.congressID), $0.accommodationID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_meeting_projects (id, meeting_id, project_id) VALUES (?, ?, ?);",
            rows: snapshot.relations.calendarMeetingProjects.map { [$0.id, $0.meetingID, $0.projectID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_meeting_organizations (id, meeting_id, organization_id) VALUES (?, ?, ?);",
            rows: snapshot.relations.calendarMeetingOrganizations.map { [$0.id, $0.meetingID, $0.organizationID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_meeting_applications (id, meeting_id, application_id) VALUES (?, ?, ?);",
            rows: snapshot.relations.calendarMeetingApplications.map { [$0.id, $0.meetingID, $0.applicationID] }
        )
        try insertRows(
            sql: "INSERT INTO rel_calendar_meeting_publications (id, meeting_id, publication_id) VALUES (?, ?, ?);",
            rows: snapshot.relations.calendarMeetingPublications.map { [$0.id, $0.meetingID, $0.publicationID] }
        )

        var searchRows: [[String?]] = []
        searchRows.append(contentsOf: snapshot.calendarTravel.map {
            ["calendar_travel:\($0.id)", "calendar_travel", $0.id, [$0.fromCity, $0.toCity].filter { !$0.isEmpty }.joined(separator: " -> "), $0.mode, [$0.fromCountry, $0.toCountry, $0.congressOrganizationID, $0.congressID].compactMap { $0 }.joined(separator: " "), $0.date]
        })
        searchRows.append(contentsOf: snapshot.calendarAccommodation.map {
            ["calendar_accommodation:\($0.id)", "calendar_accommodation", $0.id, $0.hotelName, [$0.checkInDate, $0.checkOutDate].filter { !$0.isEmpty }.joined(separator: " - "), [$0.city, $0.country, $0.congressOrganizationID, $0.congressID].compactMap { $0 }.joined(separator: " "), $0.checkInDate]
        })
        searchRows.append(contentsOf: snapshot.calendarMeetings.map {
            ["calendar_meeting:\($0.id)", "calendar_meeting", $0.id, $0.title, $0.meetingType, [$0.startTime, $0.endTime].filter { !$0.isEmpty }.joined(separator: " - "), $0.date]
        })
        try insertRows(
            sql: "INSERT INTO rel_search_index (id, entity_type, entity_id, title, subtitle, body, date_value) VALUES (?, ?, ?, ?, ?, ?, ?);",
            rows: searchRows
        )
        try insertRows(
            sql: "INSERT OR REPLACE INTO rel_metadata (key, value) VALUES (?, ?);",
            rows: [
                ["schema_version", "\(snapshot.schemaVersion)"],
                ["generated_at", snapshot.generatedAt],
                ["relations_schema_version", "\(snapshot.relations.schemaVersion)"],
            ]
        )
        try createRelationalIndexes()
    }

    private func createRelationalSchema() throws {
        try applyPhysicalSchemaMigrations()
    }

    private func createIDAliasSchema() throws {
        try execute("CREATE TABLE IF NOT EXISTS id_aliases (entity_type TEXT NOT NULL, old_id TEXT NOT NULL, new_id TEXT NOT NULL, migrated_at TEXT NOT NULL DEFAULT '', PRIMARY KEY (entity_type, old_id));")
        try execute("CREATE INDEX IF NOT EXISTS idx_id_aliases_new_id ON id_aliases(entity_type, new_id);")
    }

    private func replaceIDAliases(with aliases: [IDAliasRecord]) throws {
        try createIDAliasSchema()
        try execute("DELETE FROM id_aliases;")
        try insertRows(
            sql: "INSERT INTO id_aliases (entity_type, old_id, new_id, migrated_at) VALUES (?, ?, ?, ?);",
            rows: aliases.compactMap { alias in
                guard let normalized = alias.normalized() else { return nil }
                return [
                    normalized.entityType,
                    normalized.oldID,
                    normalized.newID,
                    normalized.migratedAt,
                ]
            }
        )
    }

    private func createRelationalIndexes() throws {
        let statements = [
            "CREATE INDEX IF NOT EXISTS idx_rel_applications_org ON rel_applications(organization_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_applications_project ON rel_applications(project_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_applications_status ON rel_applications(status);",
            "CREATE INDEX IF NOT EXISTS idx_rel_applications_project_status ON rel_applications(project_id, status);",
            "CREATE INDEX IF NOT EXISTS idx_rel_applications_org_status ON rel_applications(organization_id, status);",
            "CREATE INDEX IF NOT EXISTS idx_rel_applications_title ON rel_applications(title);",
            "CREATE INDEX IF NOT EXISTS idx_rel_organizations_name_sv ON rel_organizations(name_sv);",
            "CREATE INDEX IF NOT EXISTS idx_rel_organizations_name_en ON rel_organizations(name_en);",
            "CREATE INDEX IF NOT EXISTS idx_rel_projects_name_sv ON rel_projects(name_sv);",
            "CREATE INDEX IF NOT EXISTS idx_rel_projects_name_en ON rel_projects(name_en);",
            "CREATE INDEX IF NOT EXISTS idx_rel_authors_display_name ON rel_publication_authors(display_name);",
            "CREATE INDEX IF NOT EXISTS idx_rel_publications_project ON rel_publications(project_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_publications_year ON rel_publications(year);",
            "CREATE INDEX IF NOT EXISTS idx_rel_publications_journal_year ON rel_publications(journal, year);",
            "CREATE INDEX IF NOT EXISTS idx_rel_publications_title ON rel_publications(title);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congresses_org ON rel_congresses(organization_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congresses_congress_id ON rel_congresses(congress_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congresses_dates ON rel_congresses(from_date, to_date);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congresses_title ON rel_congresses(title);",
            "CREATE UNIQUE INDEX IF NOT EXISTS uniq_rel_congresses_org_congress ON rel_congresses(organization_id, congress_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_travel_congress ON rel_calendar_travel(congress_organization_id, congress_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_travel_dates ON rel_calendar_travel(date, arrival_date);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_travel_mode_date ON rel_calendar_travel(mode, date);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_travel_from_place ON rel_calendar_travel(from_country, from_city);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_travel_to_place ON rel_calendar_travel(to_country, to_city);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_accommodation_congress ON rel_calendar_accommodation(congress_organization_id, congress_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_accommodation_dates ON rel_calendar_accommodation(check_in_date, check_out_date);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_accommodation_place ON rel_calendar_accommodation(country, city);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_accommodation_hotel ON rel_calendar_accommodation(hotel_name);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_meetings_date ON rel_calendar_meetings(date);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_meetings_type ON rel_calendar_meetings(meeting_type);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_meetings_type_date ON rel_calendar_meetings(meeting_type, date);",
            "CREATE INDEX IF NOT EXISTS idx_rel_calendar_meetings_title ON rel_calendar_meetings(title);",
            "CREATE INDEX IF NOT EXISTS idx_rel_contributions_congress ON rel_conference_contributions(congress_organization_id, congress_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_contributions_status_dates ON rel_conference_contributions(status, from_date, to_date);",
            "CREATE INDEX IF NOT EXISTS idx_rel_contributions_title ON rel_conference_contributions(title);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congress_participants_congress ON rel_congress_participants(congress_record_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congress_participants_author ON rel_congress_participants(author_id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS uniq_rel_congress_participants_identity ON rel_congress_participants(organization_id, congress_id, author_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congress_funding_congress ON rel_congress_funding(congress_record_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congress_funding_application ON rel_congress_funding(application_id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS uniq_rel_congress_funding_identity ON rel_congress_funding(organization_id, congress_id, application_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congress_travel_congress ON rel_congress_travel(congress_record_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congress_travel_travel ON rel_congress_travel(travel_id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS uniq_rel_congress_travel_identity ON rel_congress_travel(organization_id, congress_id, travel_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congress_accommodation_congress ON rel_congress_accommodation(congress_record_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_congress_accommodation_accommodation ON rel_congress_accommodation(accommodation_id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS uniq_rel_congress_accommodation_identity ON rel_congress_accommodation(organization_id, congress_id, accommodation_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_contribution_congress_contribution ON rel_conference_contribution_congresses(contribution_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_contribution_congress_congress ON rel_conference_contribution_congresses(congress_record_id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS uniq_rel_contribution_congress_identity ON rel_conference_contribution_congresses(contribution_id, organization_id, congress_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_contribution_authors_contribution ON rel_conference_contribution_authors(contribution_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_contribution_authors_author ON rel_conference_contribution_authors(author_id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS uniq_rel_contribution_authors_identity ON rel_conference_contribution_authors(contribution_id, author_id, role);",
            "CREATE INDEX IF NOT EXISTS idx_rel_meeting_projects_meeting ON rel_calendar_meeting_projects(meeting_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_meeting_projects_project ON rel_calendar_meeting_projects(project_id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS uniq_rel_meeting_projects_identity ON rel_calendar_meeting_projects(meeting_id, project_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_meeting_organizations_meeting ON rel_calendar_meeting_organizations(meeting_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_meeting_organizations_organization ON rel_calendar_meeting_organizations(organization_id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS uniq_rel_meeting_organizations_identity ON rel_calendar_meeting_organizations(meeting_id, organization_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_meeting_applications_meeting ON rel_calendar_meeting_applications(meeting_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_meeting_applications_application ON rel_calendar_meeting_applications(application_id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS uniq_rel_meeting_applications_identity ON rel_calendar_meeting_applications(meeting_id, application_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_meeting_publications_meeting ON rel_calendar_meeting_publications(meeting_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_meeting_publications_publication ON rel_calendar_meeting_publications(publication_id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS uniq_rel_meeting_publications_identity ON rel_calendar_meeting_publications(meeting_id, publication_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_search_entity ON rel_search_index(entity_type, entity_id);",
            "CREATE INDEX IF NOT EXISTS idx_rel_search_date ON rel_search_index(date_value);",
            "CREATE INDEX IF NOT EXISTS idx_rel_search_title ON rel_search_index(title);",
        ]
        for statement in statements {
            try execute(statement)
        }
    }

    private func clearRelationalTables() throws {
        for tableName in [
            "rel_calendar_meeting_publications",
            "rel_calendar_meeting_applications",
            "rel_calendar_meeting_organizations",
            "rel_calendar_meeting_projects",
            "rel_search_index",
            "rel_conference_contribution_authors",
            "rel_conference_contribution_congresses",
            "rel_congress_accommodation",
            "rel_congress_travel",
            "rel_congress_funding",
            "rel_congress_participants",
            "rel_conference_contributions",
            "rel_calendar_meetings",
            "rel_calendar_accommodation",
            "rel_calendar_travel",
            "rel_congresses",
            "rel_publications",
            "rel_publication_authors",
            "rel_applications",
            "rel_projects",
            "rel_organizations",
            "rel_metadata",
        ] {
            try execute("DELETE FROM \(tableName);")
        }
    }

    private func replaceSearchIndexTables(with snapshot: RelationalSQLiteSnapshot) throws {
        var rows: [[String?]] = []
        rows.append(contentsOf: snapshot.organizations.map {
            ["organization:\($0.id)", "organization", $0.id, $0.nameSv.nonEmpty ?? $0.nameEn, $0.nameEn, $0.nameSv, ""]
        })
        rows.append(contentsOf: snapshot.projects.map {
            ["project:\($0.id)", "project", $0.id, $0.nameSv.nonEmpty ?? $0.nameEn, $0.nameEn, $0.nameSv, ""]
        })
        rows.append(contentsOf: snapshot.applications.map {
            ["application:\($0.id)", "application", $0.id, $0.title, $0.status, [$0.organizationID, $0.projectID].compactMap { $0 }.joined(separator: " "), ""]
        })
        rows.append(contentsOf: snapshot.authors.map {
            ["author:\($0.id)", "author", $0.id, $0.displayName, "", "", ""]
        })
        rows.append(contentsOf: snapshot.publications.map {
            ["publication:\($0.id)", "publication", $0.id, $0.title, [$0.journal, $0.year].filter { !$0.isEmpty }.joined(separator: " "), $0.projectID ?? "", $0.year]
        })
        rows.append(contentsOf: snapshot.relations.congresses.map {
            let recordID = StoredCongressRecord.recordID(organizationID: $0.organizationID, congressID: $0.id)
            return ["congress:\(recordID)", "congress", recordID, $0.title, [$0.from, $0.to].filter { !$0.isEmpty }.joined(separator: " - "), $0.organizationID, $0.from]
        })
        rows.append(contentsOf: snapshot.calendarTravel.map {
            ["calendar_travel:\($0.id)", "calendar_travel", $0.id, [$0.fromCity, $0.toCity].filter { !$0.isEmpty }.joined(separator: " -> "), $0.mode, [$0.fromCountry, $0.toCountry, $0.congressOrganizationID, $0.congressID].compactMap { $0 }.joined(separator: " "), $0.date]
        })
        rows.append(contentsOf: snapshot.calendarAccommodation.map {
            ["calendar_accommodation:\($0.id)", "calendar_accommodation", $0.id, $0.hotelName, [$0.checkInDate, $0.checkOutDate].filter { !$0.isEmpty }.joined(separator: " - "), [$0.city, $0.country, $0.congressOrganizationID, $0.congressID].compactMap { $0 }.joined(separator: " "), $0.checkInDate]
        })
        rows.append(contentsOf: snapshot.calendarMeetings.map {
            ["calendar_meeting:\($0.id)", "calendar_meeting", $0.id, $0.title, $0.meetingType, [$0.startTime, $0.endTime].filter { !$0.isEmpty }.joined(separator: " - "), $0.date]
        })
        rows.append(contentsOf: snapshot.conferenceContributions.map {
            ["conference_contribution:\($0.id)", "conference_contribution", $0.id, $0.title, $0.status, [$0.congressOrganizationID, $0.congressID].compactMap { $0 }.joined(separator: " "), $0.from]
        })

        try insertRows(
            sql: "INSERT INTO rel_search_index (id, entity_type, entity_id, title, subtitle, body, date_value) VALUES (?, ?, ?, ?, ?, ?, ?);",
            rows: rows
        )
    }

    private func saveRelationalMetadata(_ snapshot: RelationalSQLiteSnapshot) throws {
        try insertRows(
            sql: "INSERT INTO rel_metadata (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
            rows: [
                ["schema_version", "\(snapshot.schemaVersion)"],
                ["generated_at", snapshot.generatedAt],
                ["relations_schema_version", "\(snapshot.relations.schemaVersion)"],
            ]
        )
    }

    private func insertRows(sql: String, rows: [[String?]]) throws {
        guard !rows.isEmpty else { return }
        guard let statement = try prepare(sql) else { return }
        defer { sqlite3_finalize(statement) }
        for row in rows {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            for (offset, value) in row.enumerated() {
                try bindNullableText(value, at: Int32(offset + 1), in: statement)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    private func relationalTableExists(_ tableName: String) throws -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;"
        guard let statement = try prepare(sql) else { return false }
        defer { sqlite3_finalize(statement) }
        try bindText(tableName, at: 1, in: statement)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw StoreError.stepFailed(lastErrorMessage())
        }
    }

    private func relationalIndexExists(_ indexName: String) throws -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ? LIMIT 1;"
        guard let statement = try prepare(sql) else { return false }
        defer { sqlite3_finalize(statement) }
        try bindText(indexName, at: 1, in: statement)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw StoreError.stepFailed(lastErrorMessage())
        }
    }

    private func relationalColumnExists(tableName: String, columnName: String) throws -> Bool {
        let sql = "PRAGMA table_info(\(tableName));"
        guard let statement = try prepare(sql) else { return false }
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return false
            }
            guard result == SQLITE_ROW else {
                throw StoreError.stepFailed(lastErrorMessage())
            }
            if columnText(statement, 1) == columnName {
                return true
            }
        }
    }

    private func addRelationalColumnIfNeeded(tableName: String, columnName: String, definition: String) throws {
        guard try relationalTableExists(tableName),
              try !relationalColumnExists(tableName: tableName, columnName: columnName) else { return }
        try execute("ALTER TABLE \(tableName) ADD COLUMN \(columnName) \(definition);")
    }

    private func scalarInt(_ sql: String) throws -> Int {
        guard let statement = try prepare(sql) else { return 0 }
        defer { sqlite3_finalize(statement) }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            break
        case SQLITE_DONE:
            return 0
        default:
            throw StoreError.stepFailed(lastErrorMessage())
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func optionalScalarInt(_ sql: String) throws -> Int? {
        guard let statement = try prepare(sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
            return Int(sqlite3_column_int64(statement, 0))
        case SQLITE_DONE:
            return nil
        default:
            throw StoreError.stepFailed(lastErrorMessage())
        }
    }

    private func scalarText(_ sql: String) throws -> String {
        guard let statement = try prepare(sql) else { return "" }
        defer { sqlite3_finalize(statement) }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            break
        case SQLITE_DONE:
            return ""
        default:
            throw StoreError.stepFailed(lastErrorMessage())
        }
        return columnText(statement, 0)
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard let database else {
            throw StoreError.openFailed("SQLite store is not open.")
        }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(lastErrorMessage())
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw StoreError.openFailed("SQLite store is not open.")
        }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.transactionFailed(lastErrorMessage())
        }
    }

    private func bindText(_ value: String, at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw StoreError.bindFailed(lastErrorMessage())
        }
    }

    private func bindNullableText(_ value: String?, at index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw StoreError.bindFailed(lastErrorMessage())
            }
            return
        }
        try bindText(value, at: index, in: statement)
    }

    private func bindBlob(_ data: Data, at index: Int32, in statement: OpaquePointer?) throws {
        let result = data.withUnsafeBytes { buffer -> Int32 in
            let baseAddress = buffer.baseAddress
            return sqlite3_bind_blob(statement, index, baseAddress, Int32(buffer.count), sqliteTransient)
        }
        guard result == SQLITE_OK else {
            throw StoreError.bindFailed(lastErrorMessage())
        }
    }

    private func lastErrorMessage() -> String {
        guard let database else { return "Unknown SQLite error." }
        return String(cString: sqlite3_errmsg(database))
    }
}
