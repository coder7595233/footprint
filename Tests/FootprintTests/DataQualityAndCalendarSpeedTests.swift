import XCTest
@testable import Footprint

/// Round 7, "Snabbare Datakvalitet och kalender": the faster paths must give
/// exactly the results of the slow ones they replace.
final class DataQualityAndCalendarSpeedTests: XCTestCase {
    private var storageDirectory: URL!

    // A store without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataQualityAndCalendarSpeedTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
    }

    override func tearDown() {
        unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
        if let storageDirectory {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        storageDirectory = nil
        super.tearDown()
    }

    // MARK: - Sorting: same order as the old comparators

    /// The comparator the store and the meeting autosave used before.
    private static func previousMeetingOrder(_ records: [CalendarMeetingRecord]) -> [CalendarMeetingRecord] {
        records.sorted {
            let leftDate = DateParsers.isoDay.date(from: $0.date) ?? .distantFuture
            let rightDate = DateParsers.isoDay.date(from: $1.date) ?? .distantFuture
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            let leftStart = normalizedCalendarTimeInput($0.startTime)
            let rightStart = normalizedCalendarTimeInput($1.startTime)
            if leftStart != rightStart {
                if leftStart.isEmpty { return false }
                if rightStart.isEmpty { return true }
                return leftStart.localizedStandardCompare(rightStart) == .orderedAscending
            }
            let comparison = $0.title.localizedStandardCompare($1.title)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id < $1.id
        }
    }

    private static func previousTravelOrder(_ records: [CalendarTravelRecord]) -> [CalendarTravelRecord] {
        records.sorted {
            let leftDate = DateParsers.isoDay.date(from: $0.date) ?? .distantFuture
            let rightDate = DateParsers.isoDay.date(from: $1.date) ?? .distantFuture
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            if $0.departureTime != $1.departureTime {
                return $0.departureTime.localizedStandardCompare($1.departureTime) == .orderedAscending
            }
            return $0.id < $1.id
        }
    }

    private static func mixedMeetings() -> [CalendarMeetingRecord] {
        let dates = ["2026-03-05", "2026-03-04", "", "2026-13-40", "2026-03-05", "2025-12-31"]
        let starts = ["09:00", "9:00", "", "930", "13:15", "08:05", " 10:00 "]
        let titles = ["Möte 10", "Möte 2", "möte 2", "Alfa", "", "Zeta 1"]
        var records: [CalendarMeetingRecord] = []
        for index in 0..<240 {
            records.append(
                CalendarMeetingRecord(
                    id: "meeting-\((index * 37) % 240)",
                    date: dates[index % dates.count],
                    startTime: starts[(index / 2) % starts.count],
                    title: titles[(index / 3) % titles.count]
                )
            )
        }
        // Two records that differ only by id, and a duplicate id.
        records.append(CalendarMeetingRecord(id: "b", date: "2026-03-05", startTime: "09:00", title: "Same"))
        records.append(CalendarMeetingRecord(id: "a", date: "2026-03-05", startTime: "09:00", title: "Same"))
        records.append(CalendarMeetingRecord(id: "a", date: "2026-03-05", startTime: "09:00", title: "Same"))
        return records
    }

    func testMeetingOrderIsUnchanged() {
        let records = Self.mixedMeetings()
        XCTAssertEqual(
            calendarMeetingRecordsSortedChronologically(records),
            Self.previousMeetingOrder(records)
        )
        XCTAssertEqual(
            calendarMeetingRecordsSortedChronologically(Array(records.reversed())),
            Self.previousMeetingOrder(Array(records.reversed()))
        )
    }

    func testTravelOrderIsUnchanged() {
        let dates = ["2026-05-01", "", "2026-04-30", "2026-05-01", "not a date"]
        let times = ["07:30", "7:30", "", "18:00", "07:30"]
        var records: [CalendarTravelRecord] = []
        for index in 0..<120 {
            records.append(
                CalendarTravelRecord(
                    id: "travel-\((index * 53) % 120)",
                    date: dates[index % dates.count],
                    departureTime: times[(index / 2) % times.count],
                    toCity: "Oslo"
                )
            )
        }
        XCTAssertEqual(
            calendarTravelRecordsSortedChronologically(records),
            Self.previousTravelOrder(records)
        )
    }

    // MARK: - Meetings: unchanged meetings are reused after one edit

    private static func normalizedSeedMeetings(count: Int) -> [CalendarMeetingRecord] {
        (0..<count).map { index in
            var record = CalendarMeetingRecord(
                id: "meeting-\(index)",
                date: String(format: "2026-%02ld-%02ld", index % 12 + 1, index % 28 + 1),
                startTime: index % 3 == 0 ? "" : String(format: "%02ld:00", 8 + index % 9),
                title: "Meeting \(index % 17)"
            )
            record.normalize()
            return record
        }
    }

    @MainActor
    func testOneEditedMeetingReusesTheOthersAndMatchesAFreshRead() throws {
        let meetingCount = 300
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = Self.normalizedSeedMeetings(count: meetingCount)
        let store = GrantDataStore(metadata: metadata, skipInitialMigration: true)
        try store.persistAll()

        let firstRead = store.calendarMeetingRecords
        XCTAssertEqual(firstRead.count, meetingCount)

        var edited = firstRead
        let editedIndex = edited.firstIndex { $0.id == "meeting-42" }!
        edited[editedIndex].title = "Edited title"
        edited[editedIndex].date = "2027-01-02"
        let reuseBefore = store.calendarMeetingRecordMemoReuseCount
        store.autosaveCalendarMeetingRecords(edited)

        let secondRead = store.calendarMeetingRecords
        XCTAssertGreaterThanOrEqual(
            store.calendarMeetingRecordMemoReuseCount - reuseBefore,
            meetingCount - 1,
            "every meeting but the edited one is taken from the previous build"
        )
        XCTAssertEqual(secondRead.first { $0.id == "meeting-42" }?.title, "Edited title")
        XCTAssertEqual(secondRead.last?.id, "meeting-42", "the moved meeting is re-sorted")

        // Same list as a store that reads the saved meetings from scratch.
        let fresh = GrantDataStore(metadata: store.metadata, skipInitialMigration: true)
        XCTAssertEqual(secondRead, fresh.calendarMeetingRecords)
        XCTAssertTrue(store.flushPendingMetadataPersistenceIfNeeded())
    }

    @MainActor
    func testClinicMeetingsFollowOrganizationChangesDespiteTheMemo() {
        var clinic = CalendarMeetingRecord(id: "clinic-1", date: "2026-02-03", title: "Mottagning", meetingType: "Klinik")
        clinic.normalize()
        var metadata = DataSourceMetadata.bundledDefault
        metadata.homeRegionOrganizationID = "region-og"
        metadata.calendarMeetingRecords = [clinic] + Self.normalizedSeedMeetings(count: 20)
        let region = OrganizationRecord(id: "region-og", nameSv: "Region Exempelgöta", nameEn: "Region Exempelgöta")
        let store = GrantDataStore(metadata: metadata, organizations: [region], skipInitialMigration: true)

        XCTAssertEqual(store.calendarMeetingRecords.first { $0.id == "clinic-1" }?.organizationID, "region-og")
        let fresh = GrantDataStore(metadata: metadata, organizations: [region], skipInitialMigration: true)
        XCTAssertEqual(store.calendarMeetingRecords, fresh.calendarMeetingRecords)
    }

    @MainActor
    func testSaveNormalizationMatchesNormalizingEveryMeeting() {
        let store = GrantDataStore(skipInitialMigration: true)
        var records = Self.mixedMeetings()
        records.append(CalendarMeetingRecord(id: "empty"))
        records.append(CalendarMeetingRecord(id: "spaces", date: " 2026-01-01 ", title: "  Padded  ", place: "Online"))
        let expected = records
            .map { record -> CalendarMeetingRecord in
                var copy = record
                copy.normalize()
                return copy
            }
            .filter { !$0.isEmpty }

        let first = store.calendarMeetingRecordsNormalizedForSave(records)
        XCTAssertEqual(first.records, expected)

        let second = store.calendarMeetingRecordsNormalizedForSave(records)
        XCTAssertEqual(second.records, expected)
        XCTAssertGreaterThanOrEqual(second.reused, records.count - 1, "only the second of a duplicate id is redone")

        var changed = records
        changed[5].title = "Changed"
        var expectedChanged = changed[5]
        expectedChanged.normalize()
        let third = store.calendarMeetingRecordsNormalizedForSave(changed)
        XCTAssertTrue(third.records.contains(expectedChanged))
        XCTAssertEqual(
            third.records,
            changed.map { record -> CalendarMeetingRecord in
                var copy = record
                copy.normalize()
                return copy
            }
            .filter { !$0.isEmpty }
        )
    }

    // MARK: - Hidden warnings

    @MainActor
    private func translationStore() throws -> GrantDataStore {
        var course = TeachingCourse(id: "c1", name: "Kliniskt resonemang")
        course.nameSv = "Kliniskt resonemang"
        course.nameEn = "Kliniskt resonemang"
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        let store = GrantDataStore(metadata: metadata, teachingCourses: [course], skipInitialMigration: true)
        try store.persistAll()
        store.undoManager.removeAllActions()
        return store
    }

    @MainActor
    func testHidingAWarningQueuesTheWriteAndKeepsTheLists() throws {
        let store = try translationStore()
        guard let issue = store.translationIssues().first(where: { $0.recordID == "c1" }) else {
            return XCTFail("expected a row for the identical course name")
        }
        let persistCountBefore = store.synchronousPersistCount
        let listGenerationBefore = store.dataQualityCacheGeneration
        let countGenerationBefore = store.dataQualityIssueCountGeneration

        XCTAssertTrue(store.hideDataQualityWarning(issue))

        XCTAssertEqual(store.synchronousPersistCount, persistCountBefore, "no synchronous write on the main thread")
        XCTAssertEqual(store.dataQualityCacheGeneration, listGenerationBefore, "the Data view lists are not reloaded")
        XCTAssertNotEqual(store.dataQualityIssueCountGeneration, countGenerationBefore, "the navigation count is redone")
        XCTAssertNotNil(store.cachedTranslationIssues, "the translation list is kept")
        XCTAssertTrue(store.isDataQualityWarningHidden(issue))
        XCTAssertFalse(store.translationIssues().contains { $0.id == issue.id })
        XCTAssertTrue(store.translationIssues(includeHidden: true).contains { $0.id == issue.id })
        XCTAssertFalse(store.hideDataQualityWarning(issue), "hiding twice changes nothing")

        // The queued write reaches the database.
        XCTAssertTrue(store.flushPendingMetadataPersistenceIfNeeded())
        let storedData = try XCTUnwrap(
            try SQLiteDocumentStore(url: GrantDataStore.databaseURL).loadData(named: "metadata")
        )
        let stored = try JSONDecoder().decode(DataSourceMetadata.self, from: storedData)
        XCTAssertTrue(stored.hiddenDataQualityWarningKeys?.contains(issue.id) ?? false)

        // Undo shows it again.
        XCTAssertTrue(store.undoManager.canUndo)
        store.undoManager.undo()
        XCTAssertFalse(store.isDataQualityWarningHidden(issue))
        XCTAssertTrue(store.translationIssues().contains { $0.id == issue.id })
    }

    @MainActor
    func testHiddenKeysReadWithoutSanitizingMatchTheSanitizedLists() {
        XCTAssertEqual(
            GrantDataStore.combinedHiddenDataQualityWarningKeys(hidden: [" a ", "b", "", "   "], ignored: ["c", "b "]),
            ["a", "b", "c"]
        )
        XCTAssertEqual(GrantDataStore.combinedHiddenDataQualityWarningKeys(hidden: nil, ignored: nil), [])

        var metadata = DataSourceMetadata.bundledDefault
        metadata.hiddenDataQualityWarningKeys = ["name-link|anna andersson "]
        metadata.ignoredDuplicateWarningKeys = [" name-link|bertil berg"]
        var sanitized = metadata
        sanitized.migrateLegacyFields()
        XCTAssertEqual(
            GrantDataStore.combinedHiddenDataQualityWarningKeys(
                hidden: metadata.hiddenDataQualityWarningKeys,
                ignored: metadata.ignoredDuplicateWarningKeys
            ),
            Set(sanitized.hiddenDataQualityWarningKeys ?? []).union(sanitized.ignoredDuplicateWarningKeys ?? [])
        )
    }
}
