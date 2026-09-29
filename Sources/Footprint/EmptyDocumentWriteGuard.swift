import Foundation

/// F30: a register that had records must never be written back empty.
///
/// On 2026-09-27 a decoding fault left the teaching registers empty in memory,
/// and the next save wrote those empty lists over 27 assignments and 3 doctoral
/// candidates. Reading wrongly is a bug; writing the result is data loss. This
/// check refuses the write instead, so the records stay on disk and the failure
/// surfaces to the user.
enum EmptyDocumentWriteGuard {
    struct Refusal: Error, LocalizedError {
        let keys: [String]
        var errorDescription: String? {
            let list = keys.joined(separator: ", ")
            return "Sparningen stoppades: \(list) skulle ha tömts på poster. Inget har skrivits. Starta om appen; hjälper det inte, återställ från en säkerhetskopia. Vill du verkligen tömma registret, ta bort posterna några i taget."
        }
    }

    /// True when the payload is a JSON array with no elements.
    ///
    /// Answered from the bytes instead of parsing the whole document: every
    /// save ran this over each register written, which meant a full parse of
    /// megabyte-sized documents (metadata, the calendar, the journals) just to
    /// learn that they were not "[]". A valid empty JSON array is exactly "["
    /// and "]" with nothing but JSON whitespace around and between them, so
    /// the answer is the same as the parse gave for any UTF-8 payload (the
    /// only encoding the persistence encoder produces).
    static func isEmptyList(_ data: Data) -> Bool {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            let count = buffer.count
            var index = 0
            while index < count, isJSONWhitespace(buffer[index]) { index += 1 }
            guard index < count, buffer[index] == UInt8(ascii: "[") else { return false }
            index += 1
            while index < count, isJSONWhitespace(buffer[index]) { index += 1 }
            guard index < count, buffer[index] == UInt8(ascii: "]") else { return false }
            index += 1
            while index < count, isJSONWhitespace(buffer[index]) { index += 1 }
            return index == count
        }
    }

    /// JSON's four whitespace characters (RFC 8259): space, tab, LF, CR.
    static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    /// True when the first non-whitespace byte opens a JSON array. Anything
    /// else (an object such as metadata, or bytes that are not JSON) can never
    /// parse to a list, so the guards skip the parse for it.
    static func startsLikeJSONArray(_ data: Data) -> Bool {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            for byte in buffer where !isJSONWhitespace(byte) {
                return byte == UInt8(ascii: "[")
            }
            return false
        }
    }

    /// Deleting the last one or two records is something a person plausibly does
    /// on purpose, so the guard only refuses when this many records or more would
    /// disappear in a single write.
    static let refusalThreshold = 3

    static func hasRecordsWorthProtecting(_ data: Data) -> Bool {
        guard let value = try? JSONSerialization.jsonObject(with: data) else { return false }
        guard let array = value as? [Any] else { return false }
        return array.count >= refusalThreshold
    }

    /// Returns the keys that would go from "has records" to "empty".
    static func refusedKeys(
        writing documents: [(key: String, data: Data)],
        existing: (String) throws -> Data?
    ) rethrows -> [String] {
        var refused: [String] = []
        for document in documents {
            guard FootprintStorageContract.canonicalDocumentKeys.contains(document.key),
                  isEmptyList(document.data),
                  let stored = try existing(document.key),
                  hasRecordsWorthProtecting(stored) else { continue }
            refused.append(document.key)
        }
        return refused
    }

    // MARK: - Mass replacement

    /// F34: a register must not have most of its records swapped for others in
    /// one write. On 2026-09-27 a test wrote three placeholder assignments over
    /// 27 real ones; the list was not empty, so the check above let it through.
    /// Deleting in the app happens a record or a few at a time, so a single
    /// write that loses this many records, and most of the register, is refused.
    struct ReplacementRefusal: Error, LocalizedError {
        let keys: [String]
        var errorDescription: String? {
            let list = keys.joined(separator: ", ")
            return "Sparningen stoppades: de flesta posterna i \(list) skulle ha ersatts av andra. Inget har skrivits. Starta om appen; hjälper det inte, återställ från en säkerhetskopia. Vill du verkligen ta bort så många poster, gör det några i taget."
        }
    }

    static let replacementMinimumLost = 5

    /// The ids of a JSON list of records, or nil when the payload is not a list
    /// or some record has no text id (then there is nothing safe to compare).
    static func recordIDs(_ data: Data) -> [String]? {
        guard startsLikeJSONArray(data),
              let value = try? JSONSerialization.jsonObject(with: data),
              let array = value as? [Any] else { return nil }
        var ids: [String] = []
        ids.reserveCapacity(array.count)
        for element in array {
            guard let record = element as? [String: Any],
                  let id = record["id"] as? String else { return nil }
            ids.append(id)
        }
        return ids
    }

    /// True when writing `new` over `stored` would lose at least
    /// `replacementMinimumLost` records and keep fewer than half of them.
    static func isMassReplacement(stored: [String], new: [String]) -> Bool {
        let storedIDs = Set(stored)
        let kept = storedIDs.intersection(new).count
        let lost = storedIDs.count - kept
        return lost >= replacementMinimumLost && kept * 2 < storedIDs.count
    }

    /// Returns the keys whose write would replace most of the stored records.
    /// An empty list is left to `refusedKeys`, which already covers it.
    static func refusedReplacementKeys(
        writing documents: [(key: String, data: Data)],
        existing: (String) throws -> Data?
    ) rethrows -> [String] {
        var refused: [String] = []
        for document in documents {
            guard FootprintStorageContract.canonicalDocumentKeys.contains(document.key),
                  let newIDs = writtenRecordIDs(key: document.key, data: document.data),
                  !newIDs.isEmpty,
                  let stored = try existing(document.key),
                  let storedIDs = storedRecordIDs(key: document.key, data: stored),
                  isMassReplacement(stored: storedIDs, new: newIDs) else { continue }
            refused.append(document.key)
        }
        return refused
    }

    // MARK: - Remembered ids of the last written list

    /// The stored list is, almost always, exactly the bytes this process wrote
    /// the previous time. Parsing it again on every save doubled the guard's
    /// cost (a full parse of a megabyte-sized document per register per
    /// save). The ids of each written list are remembered together with its
    /// bytes and reused only when the stored bytes are byte-for-byte those
    /// same bytes, so the ids compared are always the ones on disk; any other
    /// stored payload is parsed as before. Protection is unchanged.
    final class RecordIDMemory: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: (data: Data, ids: [String])] = [:]

        func ids(forKey key: String, matching data: Data) -> [String]? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[key], entry.data == data else { return nil }
            return entry.ids
        }

        func remember(_ ids: [String], forKey key: String, data: Data) {
            lock.lock()
            defer { lock.unlock() }
            entries[key] = (data, ids)
        }
    }

    static let recordIDMemory = RecordIDMemory()

    /// Ids of a list about to be written, remembered so the next write of the
    /// same register can skip parsing the stored copy. Remembering before the
    /// write is safe: the entry is only used when stored bytes match it.
    static func writtenRecordIDs(key: String, data: Data) -> [String]? {
        if let ids = recordIDMemory.ids(forKey: key, matching: data) {
            return ids
        }
        guard let ids = recordIDs(data) else { return nil }
        recordIDMemory.remember(ids, forKey: key, data: data)
        return ids
    }

    /// Ids of the stored list: from memory when the stored bytes are exactly
    /// the last written ones, otherwise parsed (and not remembered, so a large
    /// stored copy is not kept alive).
    static func storedRecordIDs(key: String, data: Data) -> [String]? {
        if let ids = recordIDMemory.ids(forKey: key, matching: data) {
            return ids
        }
        return recordIDs(data)
    }
}
