import XCTest
@testable import Footprint

/// Round 7: fixed names (the home country, the home region, Klinik, Resa,
/// Semester, fixed reminder times) became settings. No organization is chosen
/// by its name; the user's choices are stored in the data.
final class HomeOrganizationSettingsTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is not automatic: without this a store reads and
    // writes the real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeOrganizationSettingsTests-\(UUID().uuidString)", isDirectory: true)
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

    private static func author(_ id: String, country: String) -> PublicationAuthor {
        PublicationAuthor(
            id: id,
            name: "Forskare \(id)",
            affiliations: [PublicationAffiliation(id: "\(id)-a", organization: "Org", department: "", city: "", country: country)]
        )
    }

    // MARK: Home country

    func testCountryNamesMatchAcrossLanguages() {
        XCTAssertTrue(countryNamesMatch("Sverige", "Sweden"))
        XCTAssertTrue(countryNamesMatch("sweden", "Sweden"))
        XCTAssertFalse(countryNamesMatch("Norway", "Sweden"))
        XCTAssertFalse(countryNamesMatch("", "Sweden"))
    }

    @MainActor
    func testHomeCountryDefaultsToSwedenAndFollowsSetting() {
        let store = GrantDataStore()
        XCTAssertEqual(store.homeCountryName, "Sweden")
        XCTAssertTrue(store.isHomeCountry("Sverige"))
        XCTAssertFalse(store.isHomeCountry("Norway"))

        var metadata = DataSourceMetadata.bundledDefault
        metadata.homeCountry = "Norway"
        let norwegian = GrantDataStore(metadata: metadata)
        XCTAssertEqual(norwegian.homeCountryName, "Norway")
        XCTAssertTrue(norwegian.isHomeCountry("Norway"))
        XCTAssertFalse(norwegian.isHomeCountry("Sweden"))
    }

    func testPublicationGeographyUsesHomeCountry() {
        let swedish = Self.author("se", country: "Sweden")
        let swedishInSwedish = Self.author("sv", country: "Sverige")
        let norwegian = Self.author("no", country: "Norway")

        XCTAssertEqual(PublicationDerivation.geography(for: [swedish, swedishInSwedish]), "National")
        XCTAssertEqual(PublicationDerivation.geography(for: [swedish, norwegian]), "International")
        XCTAssertEqual(PublicationDerivation.geography(for: [norwegian], homeCountry: "Norway"), "National")
        XCTAssertEqual(PublicationDerivation.geography(for: [swedish], homeCountry: "Norway"), "International")
    }

    @MainActor
    func testClinicalActivityUsesHomeRegionAndHomeCountrySettings() {
        let region = OrganizationRecord(id: "org-region", nameSv: "Region Exempelgöta", nameEn: "Region Exempelgöta")
        let other = OrganizationRecord(id: "org-other", nameSv: "Helse Bergen", nameEn: "Helse Bergen")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.homeCountry = "Norway"
        metadata.homeRegionOrganizationID = "org-other"
        let store = GrantDataStore(metadata: metadata, organizations: [region, other])

        let inBergen = store.normalizedCalendarMeetingRecord(
            CalendarMeetingRecord(date: "2026-04-13", title: "Mottagning", meetingType: "Klinik", place: "Bergen", country: "Norway")
        )
        let inSweden = store.normalizedCalendarMeetingRecord(
            CalendarMeetingRecord(date: "2026-04-13", title: "Mottagning", meetingType: "Klinik", place: "Exempelköping", country: "Sweden")
        )

        XCTAssertEqual(inBergen.organizationID, "org-other")
        XCTAssertNil(inSweden.organizationID)
    }

    @MainActor
    func testHomeRegionIsNeverChosenByName() {
        let region = OrganizationRecord(id: "org-region", nameSv: "Region Exempel", nameEn: "Region Exempel")
        let university = OrganizationRecord(id: "org-uni", nameSv: "Exempeluniversitetet", nameEn: "Example University")
        let store = GrantDataStore(organizations: [region, university])

        XCTAssertNil(store.metadata.homeRegionOrganizationID)
        XCTAssertNil(store.homeRegionOrganizationID, "nothing stored means no home region")

        _ = store.migrateHomeOrganizationSettingsIfNeeded()
        XCTAssertNil(store.metadata.homeRegionOrganizationID, "the one-time step picks no organization by name")
        XCTAssertNil(store.metadata.mainEmployerOrganizationID, "the removed main employer setting is no longer filled in")

        // A stored choice counts (it is kept in the data).
        store.autosaveHomeOrganizationSettings(homeCountry: "Sweden", homeRegionOrganizationID: "org-region")
        store.flushPendingPersistenceIfNeeded()
        XCTAssertEqual(store.homeRegionOrganizationID, "org-region")
        XCTAssertFalse(store.migrateHomeOrganizationSettingsIfNeeded(), "running it again changes nothing")
        XCTAssertEqual(store.homeRegionOrganizationID, "org-region")

        // "None" chosen in Settings is kept.
        store.autosaveHomeOrganizationSettings(homeCountry: "Sweden", homeRegionOrganizationID: "")
        store.flushPendingPersistenceIfNeeded()
        XCTAssertNil(store.homeRegionOrganizationID)
    }

    // MARK: Roles are not overridden

    @MainActor
    func testOrganizationRolesAreNotOverriddenByName() {
        let uni = OrganizationRecord(
            id: "org-uni",
            nameSv: "Exempelköpings universitet",
            nameEn: "Exempelköping University",
            roles: [.fundManager, .employer]
        )
        let region = OrganizationRecord(
            id: "org-region",
            nameSv: "Region Exempelgöta",
            nameEn: "Region Exempelgöta",
            roles: [.employer]
        )
        let scholarship = OrganizationRecord(
            id: "org-scholarship",
            nameSv: "Stipendium",
            nameEn: "Scholarship",
            roles: [.fundManager, .employer]
        )
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Vetenskapsrådet",
            grantName: "Grant",
            applicationManager: "Exempelköpings universitet"
        )
        let store = GrantDataStore(applications: [application], organizations: [uni, region, scholarship])

        _ = store.migrateRecordsIfNeeded()
        store.refreshOptionListsFromApplications(preserveCustomLists: true)

        XCTAssertEqual(store.organization(id: "org-uni")?.roles, [.fundManager, .employer].sortedByRoleOrder)
        XCTAssertEqual(store.organization(id: "org-region")?.roles, [.employer])
        XCTAssertEqual(store.organization(id: "org-scholarship")?.roles, [.fundManager, .employer].sortedByRoleOrder)
    }

    @MainActor
    func testNewOrganizationFromApplicationStillGetsSuggestedRoles() {
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Ny finansiär",
            grantName: "Grant",
            applicationManager: "Nytt universitet"
        )
        let store = GrantDataStore(applications: [application])
        store.refreshOptionListsFromApplications(preserveCustomLists: true)

        let manager = store.organizations.first { $0.nameSv == "Nytt universitet" }
        XCTAssertEqual(Set(manager?.roles ?? []), [.fundManager, .employer, .institution])
        let funder = store.organizations.first { $0.nameSv == "Ny finansiär" }
        XCTAssertEqual(funder?.roles, [.grantProvider])
    }

    // MARK: Salary calculator for applications

    @MainActor
    func testSalaryCalculatorIsNeverChosenByName() throws {
        let region = OrganizationRecord(id: "org-region", nameSv: "Region Exempel", nameEn: "Region Exempel", roles: [.employer])
        let university = OrganizationRecord(id: "org-uni", nameSv: "Exempeluniversitetet", nameEn: "Example University", roles: [.employer])
        let store = GrantDataStore(organizations: [region, university])
        XCTAssertNil(store.applicationSalaryCalculatorOrganization)

        _ = store.migrateHomeOrganizationSettingsIfNeeded()
        XCTAssertNil(store.applicationSalaryCalculatorOrganization, "no organization is ticked because of its name")

        // The user's own choice counts, and only one organization can be chosen.
        XCTAssertTrue(store.setOrganizationUsesAsApplicationSalaryCalculator(organizationID: "org-region", enabled: true))
        XCTAssertEqual(store.applicationSalaryCalculatorOrganization?.id, "org-region")
        XCTAssertTrue(store.setOrganizationUsesAsApplicationSalaryCalculator(organizationID: "org-uni", enabled: true))
        XCTAssertEqual(store.applicationSalaryCalculatorOrganization?.id, "org-uni", "only one organization can be chosen")
        XCTAssertFalse(try XCTUnwrap(store.organization(id: "org-region")).usesAsApplicationSalaryCalculator)
        XCTAssertTrue(store.setOrganizationUsesAsApplicationSalaryCalculator(organizationID: "org-uni", enabled: false))
        XCTAssertFalse(store.migrateHomeOrganizationSettingsIfNeeded())
        XCTAssertNil(store.applicationSalaryCalculatorOrganization, "the one-time step does not tick one")
    }

    func testSalaryCalculatorTemplateCarriesNoRatesOfItsOwn() {
        let template = ManagerSalaryCalculator.defaultSalaryCalculatorTemplate
        XCTAssertTrue(template.employerFeePeriods.isEmpty)
        XCTAssertTrue(template.regionalCostPeriods.isEmpty)
        XCTAssertTrue(template.itInfrastructureFeePeriods.isEmpty)
        XCTAssertTrue(template.overheadPeriods.isEmpty)
        XCTAssertEqual(template.annualIncreaseAfterCurrentYearPercent, "3")
    }

    func testOrganizationSalaryCalculatorFlagDecodesAndEncodes() throws {
        let json = #"{"id":"o1","nameSv":"Region Exempelgöta","nameEn":"Region Exempelgöta","roles":["employer"]}"#
        let decoded = try JSONDecoder().decode(OrganizationRecord.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.usesAsApplicationSalaryCalculator)

        let unchanged = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertFalse(unchanged.contains("usesAsApplicationSalaryCalculator"), "an unticked flag is not written")

        var flagged = decoded
        flagged.usesAsApplicationSalaryCalculator = true
        let roundTrip = try JSONDecoder().decode(OrganizationRecord.self, from: JSONEncoder().encode(flagged))
        XCTAssertEqual(roundTrip, flagged)
    }

    func testSalaryCalculatorVacationDefaults() throws {
        let calculator = ManagerSalaryCalculator.empty
        XCTAssertEqual(calculator.vacationDays(atAge: nil), 25)
        XCTAssertEqual(calculator.vacationDays(atAge: 39), 25)
        XCTAssertEqual(calculator.vacationDays(atAge: 40), 31)
        XCTAssertEqual(calculator.vacationDays(atAge: 49), 31)
        XCTAssertEqual(calculator.vacationDays(atAge: 50), 32)
        XCTAssertEqual(calculator.vacationSupplementRatePerDay, 0.00605, accuracy: 1e-12)

        let legacyJSON = #"{"birthDate":"1980-01-01","annualIncreaseAfterCurrentYearPercent":"3"}"#
        let decoded = try JSONDecoder().decode(ManagerSalaryCalculator.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.vacationDaysBase, "25")
        XCTAssertEqual(decoded.vacationSupplementPercentPerDay, "0,605")
        let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertFalse(encoded.contains("vacation"), "default vacation values are not written")

        var changed = calculator
        changed.vacationDaysBase = "28"
        changed.vacationSupplementPercentPerDay = "0,8"
        XCTAssertEqual(changed.vacationDays(atAge: 30), 28)
        XCTAssertEqual(changed.vacationSupplementRatePerDay, 0.008, accuracy: 1e-12)
        let roundTrip = try JSONDecoder().decode(ManagerSalaryCalculator.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(roundTrip, changed)
    }

    // MARK: Reminder settings

    func testReminderSettingsDefaultsMatchPreviousFixedValues() throws {
        let defaults = CalendarReminderSettings.standard
        XCTAssertEqual(defaults.grantClosingLeadDays, 7)
        XCTAssertEqual(defaults.grantDecisionFollowUpDays, 7)
        XCTAssertEqual(defaults.grantDispositionEndLeadMonths, 3)
        XCTAssertEqual(defaults.grantReminderTime, "09:00")
        XCTAssertEqual(defaults.taskNotificationTime, "12:00")
        XCTAssertEqual(defaults.taskDueSoonDays, 7)

        let decoded = try JSONDecoder().decode(CalendarReminderSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, defaults)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
        let grantDate = GrantReminderCoordinator.reminderDate(on: day, settings: defaults, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: grantDate), 9)
        XCTAssertEqual(calendar.component(.minute, from: grantDate), 0)
        let taskDate = calendarTaskReminderFireDate(on: day, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: taskDate), 12)

        var custom = defaults
        custom.grantReminderTime = "7:30"
        custom.taskNotificationTime = "1745"
        let customGrant = GrantReminderCoordinator.reminderDate(on: day, settings: custom.normalized(), calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: customGrant), 7)
        XCTAssertEqual(calendar.component(.minute, from: customGrant), 30)
        let customTask = calendarTaskReminderFireDate(on: day, calendar: calendar, settings: custom.normalized())
        XCTAssertEqual(calendar.component(.hour, from: customTask), 17)
        XCTAssertEqual(calendar.component(.minute, from: customTask), 45)

        XCTAssertEqual(CalendarReminderSettings.normalizedTime("9"), "09:00")
        XCTAssertNil(CalendarReminderSettings.normalizedTime("25:00"))
        XCTAssertEqual(GrantReminderCoordinator.closingSoonTitle(days: 7, language: .swedish), "1 vecka kvar innan stängning")
        XCTAssertEqual(GrantReminderCoordinator.closingSoonTitle(days: 14, language: .swedish), "14 dagar kvar innan stängning")
    }

    @MainActor
    func testStoreReminderSettingsDefaultAndSave() {
        let store = GrantDataStore()
        XCTAssertEqual(store.calendarReminderSettings, .standard)
        XCTAssertNil(store.metadata.calendarReminderSettings)

        var changed = CalendarReminderSettings.standard
        changed.grantClosingLeadDays = 14
        store.autosaveCalendarReminderSettings(changed)
        store.flushPendingPersistenceIfNeeded()
        XCTAssertEqual(store.calendarReminderSettings.grantClosingLeadDays, 14)

        store.autosaveCalendarReminderSettings(.standard)
        store.flushPendingPersistenceIfNeeded()
        XCTAssertNil(store.editableMetadataSnapshot.calendarReminderSettings, "defaults are not stored")
    }

    // MARK: Calendar categories

    private static func statisticsMetadata(behaviors: [CalendarCategoryBehaviorSetting]?) -> (DataSourceMetadata, PublicationAuthor) {
        let author = PublicationAuthor(id: "author-self", name: "Ada Lovelace", firstName: "Ada", lastName: "Lovelace")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = author.id
        metadata.calendarCategoryBehaviors = behaviors
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(id: "meeting", date: "2026-04-12", startTime: "09:00", endTime: "10:00", title: "Möte", meetingType: "Möte"),
            CalendarMeetingRecord(id: "travel", date: "2026-04-12", startTime: "10:00", endTime: "11:00", title: "Resa", meetingType: "Resa"),
            CalendarMeetingRecord(id: "clinic", date: "2026-04-12", startTime: "11:00", endTime: "12:00", title: "Klinik", meetingType: "Klinik"),
        ]
        return (metadata, author)
    }

    @MainActor
    func testCategoryStatisticsFlagDecidesWhatIsCounted() throws {
        let referenceDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 14, hour: 12)))

        // Before anything is stored: the old names apply (Resa and Klinik are left out).
        let (legacyMetadata, author) = Self.statisticsMetadata(behaviors: nil)
        let legacyStore = GrantDataStore(metadata: legacyMetadata, publicationAuthors: [author])
        let legacy = calendarMeetingHoursSummary(store: legacyStore, scope: .researcher(author), referenceDate: referenceDate)
        XCTAssertEqual(legacy.completedMeetings.map(\.id), ["meeting"])

        // The user's settings count: Resa is counted, Möte is left out.
        let (customMetadata, _) = Self.statisticsMetadata(behaviors: [
            CalendarCategoryBehaviorSetting(categoryName: "Resa", excludedFromMeetingStatistics: false),
            CalendarCategoryBehaviorSetting(categoryName: "Möte", excludedFromMeetingStatistics: true),
            CalendarCategoryBehaviorSetting(categoryName: "Klinik", excludedFromMeetingStatistics: true, isClinicalTime: true),
        ])
        let customStore = GrantDataStore(metadata: customMetadata, publicationAuthors: [author])
        let custom = calendarMeetingHoursSummary(store: customStore, scope: .researcher(author), referenceDate: referenceDate)
        XCTAssertEqual(custom.completedMeetings.map(\.id), ["travel"])
    }

    @MainActor
    func testCategoryMigrationStoresOldNamesAsSettings() {
        let (metadata, author) = Self.statisticsMetadata(behaviors: nil)
        let store = GrantDataStore(metadata: metadata, publicationAuthors: [author])

        XCTAssertTrue(store.migrateHomeOrganizationSettingsIfNeeded())
        let stored = store.metadata.calendarCategoryBehaviors ?? []
        let byName = Dictionary(uniqueKeysWithValues: stored.map { ($0.categoryName, $0) })
        XCTAssertEqual(byName["Resa"]?.excludedFromMeetingStatistics, true)
        XCTAssertEqual(byName["Klinik"]?.excludedFromMeetingStatistics, true)
        XCTAssertEqual(byName["Klinik"]?.isClinicalTime, true)
        XCTAssertNil(byName["Möte"], "categories without any setting are not listed")
        XCTAssertFalse(store.calendarCategoryIsExcludedFromMeetingStatistics(named: "Möte"))
        XCTAssertTrue(store.calendarCategoryIsClinicalTime(named: "Klinik"))

        // A category the user renames or unticks keeps the user's choice.
        store.autosaveCalendarCategoryBehaviors([
            CalendarCategoryBehaviorSetting(categoryName: "Klinik", excludedFromMeetingStatistics: false, isClinicalTime: false)
        ])
        store.flushPendingPersistenceIfNeeded()
        XCTAssertFalse(store.calendarCategoryIsClinicalTime(named: "Klinik"))
        XCTAssertFalse(store.calendarCategoryIsExcludedFromMeetingStatistics(named: "Resa"))
        XCTAssertFalse(store.migrateHomeOrganizationSettingsIfNeeded(), "stored settings are not replaced")
    }

    func testLegacyCategoryDefaults() {
        XCTAssertTrue(CalendarCategoryBehaviorSetting.legacyDefault(forCategoryNamed: "Klinik").isClinicalTime)
        XCTAssertTrue(CalendarCategoryBehaviorSetting.legacyDefault(forCategoryNamed: "clinic").excludedFromMeetingStatistics)
        XCTAssertTrue(CalendarCategoryBehaviorSetting.legacyDefault(forCategoryNamed: "Travel").excludedFromMeetingStatistics)
        XCTAssertFalse(CalendarCategoryBehaviorSetting.legacyDefault(forCategoryNamed: "Travel").isClinicalTime)
        XCTAssertTrue(CalendarCategoryBehaviorSetting.legacyDefault(forCategoryNamed: "Semester").isLeave)
        XCTAssertFalse(CalendarCategoryBehaviorSetting.legacyDefault(forCategoryNamed: "Möte").hasAnyFlag)
    }
}

private extension Array where Element == OrganizationRole {
    var sortedByRoleOrder: [OrganizationRole] {
        OrganizationRole.allCases.filter { self.contains($0) }
    }
}
