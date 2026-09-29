import Foundation

enum DocumentPersistenceWorker {
    struct Document: Sendable {
        let storageKey: String
        let data: Data
    }

    static func write(
        _ documents: [Document],
        databaseURL: URL?
    ) throws {
        guard !documents.isEmpty else { return }

        if let databaseURL {
            let sqliteStore = try SQLiteDocumentStore(url: databaseURL)
            let pairs = documents.map { (key: $0.storageKey, data: $0.data) }
            var storedByKey: [String: Data?] = [:]
            let existing: (String) throws -> Data? = { key in
                if let cached = storedByKey[key] { return cached }
                let loaded = try sqliteStore.loadData(named: key)
                storedByKey[key] = .some(loaded)
                return loaded
            }
            // F30: never replace a register that has records with an empty one.
            let refused = try EmptyDocumentWriteGuard.refusedKeys(writing: pairs, existing: existing)
            guard refused.isEmpty else {
                throw EmptyDocumentWriteGuard.Refusal(keys: refused)
            }
            // F34: nor swap most of its records for others in one write.
            let replaced = try EmptyDocumentWriteGuard.refusedReplacementKeys(writing: pairs, existing: existing)
            guard replaced.isEmpty else {
                throw EmptyDocumentWriteGuard.ReplacementRefusal(keys: replaced)
            }
            try sqliteStore.saveBatch(documents.map { ($0.storageKey, $0.data) })
        }
    }

    static func verify(
        _ documents: [Document],
        databaseURL: URL?
    ) throws {
        guard !documents.isEmpty else { return }

        let sqliteStore: SQLiteDocumentStore?
        if let databaseURL {
            sqliteStore = try SQLiteDocumentStore(
                url: databaseURL,
                createIfMissing: false
            )
        } else {
            sqliteStore = nil
        }
        for document in documents {
            if let sqliteStore {
                guard let sqliteData = try sqliteStore.loadData(named: document.storageKey) else {
                    throw NSError(domain: "Footprint", code: 303, userInfo: [
                        NSLocalizedDescriptionKey: "SQLite persistence verification found no document for \(document.storageKey)."
                    ])
                }
                guard sqliteData == document.data else {
                    throw NSError(domain: "Footprint", code: 302, userInfo: [
                        NSLocalizedDescriptionKey: "SQLite persistence verification failed for \(document.storageKey)."
                    ])
                }
            }
        }
    }
}
