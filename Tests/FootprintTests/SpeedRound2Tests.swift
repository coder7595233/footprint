import XCTest
@testable import Footprint

/// Round 7, "Snabbare, omgång 2": the kept (memoized) results must be the
/// same as computing everything again, and must follow the changes that
/// matter to them.
final class SpeedRound2Tests: XCTestCase {
    private var storageDirectory: URL!

    // A store without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeedRound2Tests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Meetings: the memo survives organization changes

    private static func seedMeetings(count: Int) -> [CalendarMeetingRecord] {
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

    private static func clinicMeeting(id: String = "clinic-1") -> CalendarMeetingRecord {
        var clinic = CalendarMeetingRecord(id: id, date: "2026-02-03", title: "Mottagning", meetingType: "Klinik")
        clinic.normalize()
        return clinic
    }

    @MainActor
    private func save(_ organization: OrganizationRecord, renamedTo nameSv: String, in store: GrantDataStore) {
        store.autosaveOrganization(
            id: organization.id,
            nameSv: nameSv,
            nameEn: nameSv,
            addressLine: organization.addressLine,
            postalCode: organization.postalCode,
            city: organization.city,
            country: organization.country,
            category: organization.category,
            roles: organization.roles,
            note: organization.note,
            websiteURL: organization.websiteURL,
            phoneNumber: organization.phoneNumber,
            organizationNumber: organization.organizationNumber,
            vatNumber: organization.vatNumber,
            employerContacts: organization.employerContacts,
            flag: organization.flag,
            membershipFrom: organization.membershipFrom,
            membershipTo: organization.membershipTo,
            congresses: organization.congresses,
            projectTasks: organization.projectTasks,
            salaryCalculator: organization.salaryCalculator
        )
    }

    @MainActor
    func testUnrelatedOrganizationChangeReusesEveryMeeting() throws {
        let region = OrganizationRecord(id: "region-og", nameSv: "Region Exempelgöta", nameEn: "Region Exempelgöta")
        let other = OrganizationRecord(id: "org-other", nameSv: "Stiftelsen", nameEn: "The Foundation")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.homeRegionOrganizationID = "region-og"
        metadata.calendarMeetingRecords = [Self.clinicMeeting()] + Self.seedMeetings(count: 120)
        let store = GrantDataStore(metadata: metadata, organizations: [region, other], skipInitialMigration: true)
        try store.persistAll()

        let before = store.calendarMeetingRecords
        XCTAssertEqual(before.first { $0.id == "clinic-1" }?.organizationID, "region-og")

        let reuseBefore = store.calendarMeetingRecordMemoReuseCount
        XCTAssertTrue(store.updateOrganizationAddressSettings(organizationID: "org-other", addressNameEn: "Foundation", addressOrder: 2))
        let after = store.calendarMeetingRecords

        XCTAssertGreaterThanOrEqual(
            store.calendarMeetingRecordMemoReuseCount - reuseBefore,
            121,
            "a change to another organization reuses every meeting"
        )
        XCTAssertEqual(after, before)
        let fresh = GrantDataStore(metadata: store.metadata, organizations: store.organizations, skipInitialMigration: true)
        XCTAssertEqual(after, fresh.calendarMeetingRecords)
        store.flushPendingPersistenceIfNeeded()
    }

    @MainActor
    func testRenamedHomeRegionKeepsItsClinicMeetings() throws {
        let region = OrganizationRecord(id: "region-og", nameSv: "Region Exempelgöta", nameEn: "Region Exempelgöta")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.homeRegionOrganizationID = "region-og"
        metadata.calendarMeetingRecords = [Self.clinicMeeting()] + Self.seedMeetings(count: 30)
        let store = GrantDataStore(metadata: metadata, organizations: [region], skipInitialMigration: true)
        try store.persistAll()

        XCTAssertEqual(store.calendarMeetingRecords.first { $0.id == "clinic-1" }?.organizationID, "region-og")

        let reuseBefore = store.calendarMeetingRecordMemoReuseCount
        save(region, renamedTo: "Region Exempelgöta (RE)", in: store)
        XCTAssertEqual(store.organization(id: "region-og")?.nameSv, "Region Exempelgöta (RE)")

        let after = store.calendarMeetingRecords
        XCTAssertEqual(after.first { $0.id == "clinic-1" }?.organizationID, "region-og", "the stored home region id still applies")
        XCTAssertGreaterThanOrEqual(store.calendarMeetingRecordMemoReuseCount - reuseBefore, 31, "the rename did not force a rebuild")
        let fresh = GrantDataStore(metadata: store.metadata, organizations: store.organizations, skipInitialMigration: true)
        XCTAssertEqual(after, fresh.calendarMeetingRecords)
        store.flushPendingPersistenceIfNeeded()
    }

    @MainActor
    func testWithoutAStoredHomeRegionRenamingChangesNothingLikeAFreshRead() throws {
        // No stored home region: no organization is chosen by its name, so a
        // clinic meeting gets none, before and after a rename, as a fresh
        // read would also say.
        let region = OrganizationRecord(id: "region-og", nameSv: "Region Exempelgöta", nameEn: "Region Exempelgöta")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.homeRegionOrganizationID = nil
        metadata.calendarMeetingRecords = [Self.clinicMeeting()] + Self.seedMeetings(count: 10)
        let store = GrantDataStore(metadata: metadata, organizations: [region], skipInitialMigration: true)
        try store.persistAll()
        XCTAssertNil(store.calendarMeetingRecords.first { $0.id == "clinic-1" }?.organizationID)

        save(region, renamedTo: "Hälsoregionen", in: store)
        XCTAssertNil(store.calendarMeetingRecords.first { $0.id == "clinic-1" }?.organizationID)

        let fresh = GrantDataStore(metadata: store.metadata, organizations: store.organizations, skipInitialMigration: true)
        XCTAssertEqual(store.calendarMeetingRecords, fresh.calendarMeetingRecords)
        store.flushPendingPersistenceIfNeeded()
    }

    @MainActor
    func testChangedHomeRegionSettingMovesClinicMeetings() throws {
        let region = OrganizationRecord(id: "region-og", nameSv: "Region Exempelgöta", nameEn: "Region Exempelgöta")
        let other = OrganizationRecord(id: "region-other", nameSv: "Region Kalmar län", nameEn: "Region Kalmar County")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.homeRegionOrganizationID = "region-og"
        metadata.calendarMeetingRecords = [Self.clinicMeeting()] + Self.seedMeetings(count: 10)
        let store = GrantDataStore(metadata: metadata, organizations: [region, other], skipInitialMigration: true)
        try store.persistAll()
        XCTAssertEqual(store.calendarMeetingRecords.first { $0.id == "clinic-1" }?.organizationID, "region-og")

        store.autosaveHomeOrganizationSettings(
            homeCountry: "Sweden",
            homeRegionOrganizationID: "region-other"
        )
        store.flushPendingPersistenceIfNeeded()

        XCTAssertEqual(store.calendarMeetingRecords.first { $0.id == "clinic-1" }?.organizationID, "region-other")
        let fresh = GrantDataStore(metadata: store.metadata, organizations: store.organizations, skipInitialMigration: true)
        XCTAssertEqual(store.calendarMeetingRecords, fresh.calendarMeetingRecords)
    }

    // MARK: - Organization editor: leaving an employer changes nothing

    private static func storedCalculator() -> ManagerSalaryCalculator {
        var calculator = ManagerSalaryCalculator.empty
        let periods = [
            ("p-2024", "2024-01-01", "2024-12-31", "31,42", "2,5", "10"),
            ("p-2025", "2025-01-01", "2025-12-31", "31,42", "2,6", "12"),
        ]
        calculator.employerFeePeriods = periods.map { SalaryCalculatorPeriod(id: $0.0, value: $0.3, from: $0.1, to: $0.2) }
        calculator.regionalCostPeriods = periods.map { SalaryCalculatorPeriod(id: $0.0, value: $0.4, from: $0.1, to: $0.2) }
        calculator.overheadPeriods = periods.map { SalaryCalculatorPeriod(id: $0.0, value: $0.5, from: $0.1, to: $0.2) }
        calculator.itInfrastructureFeePeriods = []
        calculator.listedPatientCountPeriods = []
        return calculator
    }

    func testCostRowsGiveBackTheStoredCalculator() {
        let stored = Self.storedCalculator()
        let rows = OrganizationSalaryCostRows.mergedSharedCostPeriods(from: stored)
        XCTAssertEqual(rows.map(\.id), ["p-2024", "p-2025"], "the rows keep the stored ids")
        XCTAssertEqual(
            OrganizationSalaryCostRows.calculator(stored, applying: rows),
            stored,
            "opening and leaving the organization gives back exactly what is stored"
        )
        XCTAssertEqual(OrganizationSalaryCostRows.mergedSharedCostPeriods(from: stored), rows, "the same rows every time")
    }

    func testCostRowsSettleAfterOneSaveForOlderData() {
        // Older data: the three lists use different ids for the same period.
        var older = Self.storedCalculator()
        older.regionalCostPeriods = older.regionalCostPeriods.map {
            SalaryCalculatorPeriod(id: "regional-\($0.id)", value: $0.value, from: $0.from, to: $0.to)
        }
        let once = OrganizationSalaryCostRows.calculator(
            older,
            applying: OrganizationSalaryCostRows.mergedSharedCostPeriods(from: older)
        )
        let twice = OrganizationSalaryCostRows.calculator(
            once,
            applying: OrganizationSalaryCostRows.mergedSharedCostPeriods(from: once)
        )
        XCTAssertEqual(once, twice, "after one save nothing changes on later visits")
        XCTAssertEqual(once.regionalCostPeriods.map(\.value), ["2,5", "2,6"], "no value is lost")
        XCTAssertEqual(once.overheadPeriods.map(\.value), ["10", "12"])
        XCTAssertEqual(once.employerFeePeriods.map(\.value), ["31,42", "31,42"])
    }

    // MARK: - Data view: journal rows are kept

    @MainActor
    func testJournalMissingFieldRowsAreReusedUntilAJournalChanges() throws {
        let withoutISSN = PublicationJournal(id: "journal-1", name: "Journal Without Numbers")
        let complete = PublicationJournal(id: "journal-2", name: "Complete Journal", issn: "1234-5678")
        let other = OrganizationRecord(id: "org-other", nameSv: "Stiftelsen", nameEn: "The Foundation")
        let store = GrantDataStore(
            organizations: [other],
            publicationJournals: [withoutISSN, complete],
            skipInitialMigration: true
        )
        try store.persistAll()

        func journalRows(_ issues: [GrantDataStore.MissingFieldIssue]) -> [String] {
            issues.filter { $0.entityKind == .journal }.map { "\($0.id)|\($0.missingFields.joined(separator: ","))" }
        }

        let first = store.dataQualityMissingFieldIssues()
        XCTAssertTrue(first.contains { $0.recordID == "journal-1" })
        XCTAssertFalse(first.contains { $0.recordID == "journal-2" })

        // An unrelated change: the journal rows are taken from the memo.
        let reuseBefore = store.dataQualityJournalMissingFieldMemoReuseCount
        XCTAssertTrue(store.updateOrganizationAddressSettings(organizationID: "org-other", addressNameEn: "Foundation", addressOrder: 1))
        let second = store.dataQualityMissingFieldIssues()
        XCTAssertGreaterThanOrEqual(store.dataQualityJournalMissingFieldMemoReuseCount, reuseBefore + 1)
        XCTAssertEqual(journalRows(second), journalRows(first))

        // A journal change is seen.
        var fixed = withoutISSN
        fixed.issn = "8765-4321"
        store.autosavePublicationJournal(fixed, previousName: withoutISSN.name)
        let third = store.dataQualityMissingFieldIssues()
        XCTAssertFalse(third.contains { $0.recordID == "journal-1" }, "the fixed journal is no longer listed")

        let fresh = GrantDataStore(
            organizations: store.organizations,
            publicationJournals: store.publicationJournals,
            skipInitialMigration: true
        )
        XCTAssertEqual(journalRows(third), journalRows(fresh.dataQualityMissingFieldIssues()))
        store.flushPendingPersistenceIfNeeded()
    }

    // MARK: - Doctoral candidates: activity hours are kept

    @MainActor
    func testSupervisionActivityMinutesMatchAFullCountAndFollowTheCalendar() throws {
        let candidate = DoctoralCandidateRecord(
            id: "candidate-1",
            candidateName: "Ada Lovelace",
            supervisionPeriods: [
                DoctoralSupervisionPeriod(id: "spring", from: "2027-01-01", to: "2027-06-30"),
                DoctoralSupervisionPeriod(id: "autumn", from: "2027-07-01", to: "2027-12-31"),
            ]
        )
        var supervision = CalendarMeetingRecord(
            id: "supervision-1",
            date: "2027-02-10",
            startTime: "10:00",
            endTime: "11:30",
            title: "Supervision",
            doctoralCandidateIDs: [candidate.id]
        )
        supervision.normalize()
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [supervision] + Self.seedMeetings(count: 40)
        let store = GrantDataStore(metadata: metadata, doctoralCandidates: [candidate], skipInitialMigration: true)
        try store.persistAll()

        func fullCount(_ candidate: DoctoralCandidateRecord) -> [String: Int] {
            doctoralSupervisionCalendarActivityMinutesByPeriodID(
                candidate: candidate,
                periods: candidate.supervisionPeriods,
                meetings: store.calendarMeetingRecords
            )
        }

        XCTAssertEqual(store.doctoralSupervisionCalendarActivityMinutes(for: candidate), ["spring": 90])
        XCTAssertEqual(store.doctoralSupervisionCalendarActivityMinutes(for: candidate), fullCount(candidate))

        // Edited periods (the page's unsaved draft) are counted again.
        var draft = candidate
        draft.supervisionPeriods[0].to = "2027-01-31"
        XCTAssertEqual(store.doctoralSupervisionCalendarActivityMinutes(for: draft), [:])
        XCTAssertEqual(store.doctoralSupervisionCalendarActivityMinutes(for: draft), fullCount(draft))

        // A new linked activity in the calendar is counted.
        var autumnMeeting = CalendarMeetingRecord(
            id: "supervision-2",
            date: "2027-09-01",
            startTime: "13:00",
            endTime: "14:00",
            title: "Supervision",
            doctoralCandidateIDs: [candidate.id]
        )
        autumnMeeting.normalize()
        store.autosaveCalendarMeetingRecords(store.calendarMeetingRecords + [autumnMeeting])
        XCTAssertEqual(store.doctoralSupervisionCalendarActivityMinutes(for: candidate), ["spring": 90, "autumn": 60])
        XCTAssertEqual(store.doctoralSupervisionCalendarActivityMinutes(for: candidate), fullCount(candidate))
        XCTAssertTrue(store.flushPendingMetadataPersistenceIfNeeded())
    }
}
