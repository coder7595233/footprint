import AppKit
import SwiftUI
import XCTest
@testable import Footprint

/// Round 7, area E–H: defaults for new applications, teaching and exports are
/// settings whose built-in values equal the old fixed behaviour, and the removed
/// lektor/docent/professor computation leaves the statistics view working.
final class WorkflowDefaultSettingsTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkflowDefaultSettingsTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
        WorkflowDefaultSettingsRegistry.replace(with: .builtIn)
    }

    override func tearDown() {
        WorkflowDefaultSettingsRegistry.replace(with: .builtIn)
        unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
        if let storageDirectory {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        storageDirectory = nil
        super.tearDown()
    }

    @MainActor
    private func store(
        settings: WorkflowDefaultSettings? = nil,
        applications: [GrantApplication] = [],
        publicationAuthors: [PublicationAuthor] = [],
        publicationRecords: [PublicationRecord] = []
    ) -> GrantDataStore {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        metadata.workflowDefaults = settings
        return GrantDataStore(
            applications: applications,
            metadata: metadata,
            publicationAuthors: publicationAuthors,
            publicationRecords: publicationRecords,
            skipInitialMigration: true
        )
    }

    private static func isoDay(monthsFromToday months: Int) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let date = calendar.date(byAdding: .month, value: months, to: today) ?? today
        return DateParsers.isoDay.string(from: date)
    }

    // MARK: Built-in values equal the old behaviour

    func testBuiltInValuesMatchTheOldFixedBehaviour() {
        let settings = WorkflowDefaultSettings.builtIn
        XCTAssertEqual(settings.resolvedOpensAfterMonths, 1)
        XCTAssertEqual(settings.resolvedClosesAfterMonths, 3)
        XCTAssertEqual(settings.resolvedCurrency, "SEK")
        XCTAssertEqual(settings.resolvedStatus, "Att söka")
        XCTAssertEqual(settings.resolvedCurrencyOptions, ["SEK", "EUR", "USD", "NOK"])
        XCTAssertEqual(settings.resolvedAmountBucketLowerLimit, 250_000)
        XCTAssertEqual(settings.resolvedAmountBucketUpperLimit, 1_000_000)
        XCTAssertEqual(settings.resolvedDefaultTeachingProgramSv, "Programmet", "a neutral name; the user's own is stored in the settings")
        XCTAssertEqual(settings.resolvedDefaultTeachingProgramEn, "The programme")
        XCTAssertEqual(settings.resolvedClinicalTeachingOrganizationWords, ["region"])
        XCTAssertEqual(settings.resolvedTeachingMeritsFacultyName, "", "no faculty is built in")
        XCTAssertTrue(settings.isBuiltIn)
    }

    /// The contact e-mail was removed (user decision). Settings saved with it
    /// still load, the old value is ignored and it is not written again.
    func testOldStoredContactEmailIsIgnored() throws {
        let old = Data(#"{"teachingMeritsFacultyName":"Exempelfakulteten","teachingMeritsContactEmail":"kontakt@example.org","newApplicationCurrency":"EUR"}"#.utf8)
        let decoded = try JSONDecoder().decode(WorkflowDefaultSettings.self, from: old)
        XCTAssertEqual(decoded.resolvedTeachingMeritsFacultyName, "Exempelfakulteten")
        XCTAssertEqual(decoded.resolvedCurrency, "EUR")
        let text = try XCTUnwrap(String(data: JSONEncoder().encode(decoded), encoding: .utf8))
        XCTAssertFalse(text.contains("teachingMeritsContactEmail"))
        XCTAssertFalse(text.contains("kontakt@example.org"))
    }

    /// Values an earlier version stored in the data are used as they are.
    func testStoredProgrammeAndFacultyAreUsed() {
        var settings = WorkflowDefaultSettings()
        settings.defaultTeachingProgramSv = "Exempelprogrammet"
        settings.defaultTeachingProgramEn = "Example Programme"
        settings.teachingMeritsFacultyName = "Exempelfakulteten"
        let normalized = settings.normalized()
        XCTAssertEqual(normalized.resolvedDefaultTeachingProgramSv, "Exempelprogrammet")
        XCTAssertEqual(normalized.resolvedDefaultTeachingProgramEn, "Example Programme")
        XCTAssertEqual(normalized.resolvedTeachingMeritsFacultyName, "Exempelfakulteten")
        XCTAssertFalse(normalized.isBuiltIn)
    }

    func testOldSavedSettingsWithoutTheNewFieldDecodeUnchanged() throws {
        let metadata = DataSourceMetadata.bundledDefault
        let data = try JSONEncoder().encode(AppSettingsSnapshot(metadata: metadata))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "workflowDefaults")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: oldData)
        XCTAssertNil(decoded.workflowDefaults)

        let partial = try JSONDecoder().decode(
            WorkflowDefaultSettings.self,
            from: Data(#"{"newApplicationCurrency":"EUR"}"#.utf8)
        )
        XCTAssertEqual(partial.resolvedCurrency, "EUR")
        XCTAssertEqual(partial.resolvedStatus, "Att söka", "fields that are missing keep the built-in value")
    }

    func testSettingsTravelThroughTheSettingsDocument() throws {
        var settings = WorkflowDefaultSettings()
        settings.newApplicationClosesAfterMonths = 6
        settings.teachingMeritsFacultyName = "Filosofiska fakulteten"
        var metadata = DataSourceMetadata.bundledDefault
        metadata.workflowDefaults = settings

        let snapshot = AppSettingsSnapshot(metadata: metadata)
        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: JSONEncoder().encode(snapshot))
        let restored = decoded.applying(to: DataSourceMetadata.bundledDefault)
        XCTAssertEqual(restored.workflowDefaults, settings)
    }

    func testNormalizationKeepsOnlyChangedValues() {
        var settings = WorkflowDefaultSettings()
        settings.newApplicationOpensAfterMonths = 1
        settings.newApplicationCurrency = " sek "
        settings.newApplicationStatus = "Att söka"
        settings.currencyOptions = ["SEK", "EUR", "USD", "NOK"]
        settings.teachingMeritsFacultyName = "   "
        settings.fundingStatementTemplateEn = ""
        XCTAssertTrue(settings.isBuiltIn, "values equal to the built-in ones are not stored")

        settings.newApplicationStatus = "Något annat"
        XCTAssertEqual(settings.resolvedStatus, "Att söka", "an unknown status falls back to the built-in one")
        settings.newApplicationStatus = "Väntar svar"
        XCTAssertEqual(settings.resolvedStatus, "Att söka", "a status that needs a date is not offered")

        settings.newApplicationCurrency = "dkk"
        settings.currencyOptions = ["sek", "DKK", "SEK", " "]
        let normalized = settings.normalized()
        XCTAssertEqual(normalized.newApplicationCurrency, "DKK")
        XCTAssertEqual(normalized.currencyOptions, ["SEK", "DKK"])
        XCTAssertEqual(WorkflowDefaultSettings.currencyList(fromText: "SEK, eur;usd\nNOK"), ["SEK", "EUR", "USD", "NOK"])
    }

    // MARK: E. New applications

    @MainActor
    func testNewApplicationUsesTodaysDefaultsWhenNothingIsChanged() throws {
        let testStore = store()
        let id = testStore.addApplication()
        let application = try XCTUnwrap(testStore.application(id: id))
        XCTAssertEqual(application.currency, "SEK")
        XCTAssertEqual(application.resultLabel, "Att söka")
        XCTAssertEqual(application.opensOn, Self.isoDay(monthsFromToday: 1))
        XCTAssertEqual(application.closesOn, Self.isoDay(monthsFromToday: 3))
    }

    @MainActor
    func testNewApplicationFollowsTheSettings() throws {
        var settings = WorkflowDefaultSettings()
        settings.newApplicationOpensAfterMonths = 2
        settings.newApplicationClosesAfterMonths = 6
        settings.newApplicationCurrency = "EUR"
        settings.newApplicationStatus = "Ej sökt"
        let testStore = store(settings: settings)
        let id = testStore.addApplication()
        let application = try XCTUnwrap(testStore.application(id: id))
        XCTAssertEqual(application.currency, "EUR")
        XCTAssertEqual(application.resultLabel, "Ej sökt")
        XCTAssertEqual(application.opensOn, Self.isoDay(monthsFromToday: 2))
        XCTAssertEqual(application.closesOn, Self.isoDay(monthsFromToday: 6))
    }

    func testCurrencyPickerKeepsTheApplicationsOwnCurrency() {
        var settings = WorkflowDefaultSettings()
        settings.currencyOptions = ["SEK", "EUR"]
        XCTAssertEqual(settings.currencyPickerOptions(including: "NOK"), ["SEK", "EUR", "NOK"])
        XCTAssertEqual(settings.currencyPickerOptions(including: "EUR"), ["SEK", "EUR"])
    }

    // MARK: E. Amount groups

    private static func application(id: String, amount: Double) -> GrantApplication {
        GrantApplication(
            id: id,
            rowNumber: 1,
            organization: "Stiftelsen",
            grantName: "Projektbidrag",
            approximateAmount: String(Int(amount)),
            approximateAmountValue: amount,
            result: "Beviljat"
        )
    }

    func testAmountGroupsKeepTheOldLimitsAndLabels() {
        let settings = WorkflowDefaultSettings.builtIn
        XCTAssertEqual(settings.amountBucket(for: 249_999), .below)
        XCTAssertEqual(settings.amountBucket(for: 250_000), .between)
        XCTAssertEqual(settings.amountBucket(for: 999_999), .between)
        XCTAssertEqual(settings.amountBucket(for: 1_000_000), .above)
        XCTAssertEqual(settings.amountBucketLabel(.below), "<250 k")
        XCTAssertEqual(settings.amountBucketLabel(.between), "250 k - 1 mil")
        XCTAssertEqual(settings.amountBucketLabel(.above), "≥1 mil")
        XCTAssertEqual(Self.application(id: "a", amount: 100_000).amountBucketLabel, "<250 k")
    }

    @MainActor
    func testAmountGroupsFollowTheSettingsInTheStatistics() {
        var settings = WorkflowDefaultSettings()
        settings.amountBucketLowerLimit = 100_000
        settings.amountBucketUpperLimit = 500_000
        let testStore = store(
            settings: settings,
            applications: [
                Self.application(id: "small", amount: 50_000),
                Self.application(id: "medium", amount: 300_000),
                Self.application(id: "large", amount: 800_000),
            ]
        )
        XCTAssertEqual(WorkflowDefaultSettingsRegistry.current.amountBucketLabel(.between), "100 k - 500 k")
        let grantedRows = testStore.statisticsBlocks.flatMap(\.resultRows).filter { $0.result == "Beviljat" }
        XCTAssertEqual(grantedRows.map(\.below250k).reduce(0, +), 1)
        XCTAssertEqual(grantedRows.map(\.between250kAnd1m).reduce(0, +), 1)
        XCTAssertEqual(grantedRows.map(\.above1m).reduce(0, +), 1)
    }

    func testAnUpperLimitBelowTheLowerLimitIsIgnored() {
        var settings = WorkflowDefaultSettings()
        settings.amountBucketLowerLimit = 2_000_000
        settings.amountBucketUpperLimit = 500_000
        XCTAssertGreaterThanOrEqual(settings.resolvedAmountBucketUpperLimit, settings.resolvedAmountBucketLowerLimit)
    }

    // MARK: G. Teaching

    private func course(term: String = "", institution: String = "") -> TeachingCourse {
        var course = TeachingCourse(id: UUID().uuidString, name: "Kurs")
        course.contextType = nil
        course.programSv = ""
        course.programEn = ""
        course.termSv = term
        course.termEn = ""
        course.institution = institution
        return course
    }

    func testCourseWithTermGetsTheStandardProgramme() {
        let withTerm = course(term: "Termin 6")
        XCTAssertEqual(withTerm.localizedProgram(language: .swedish), "Programmet")
        XCTAssertEqual(withTerm.localizedProgram(language: .english), "The programme")

        var settings = WorkflowDefaultSettings()
        settings.defaultTeachingProgramSv = "Sjuksköterskeprogrammet"
        settings.defaultTeachingProgramEn = "Nursing Programme"
        WorkflowDefaultSettingsRegistry.replace(with: settings)
        XCTAssertEqual(withTerm.localizedProgram(language: .swedish), "Sjuksköterskeprogrammet")
        XCTAssertEqual(withTerm.localizedProgram(language: .english), "Nursing Programme")
    }

    /// Round 7 (user decision): clinical teaching is the course checkbox, not a
    /// word in the organization name.
    func testClinicalTeachingCheckboxDecidesTheFallbackProgramme() {
        let regionCourse = course(institution: "Region Exempelgöta")
        XCTAssertNotEqual(regionCourse.localizedProgram(language: .swedish), "Klinisk undervisning", "the word in the name no longer decides")

        var ticked = regionCourse
        ticked.isClinicalTeaching = true
        XCTAssertEqual(ticked.localizedProgram(language: .swedish), "Klinisk undervisning")
        XCTAssertEqual(ticked.localizedProgram(language: .english), "Clinical teaching")

        var tickedOther = course(institution: "Exempelköpings universitet")
        tickedOther.isClinicalTeaching = true
        XCTAssertEqual(tickedOther.localizedProgram(language: .swedish), "Klinisk undervisning", "any organization")

        var withTerm = course(term: "Termin 6", institution: "Region Exempelgöta")
        withTerm.isClinicalTeaching = true
        XCTAssertEqual(withTerm.localizedProgram(language: .swedish), "Programmet", "a term still wins, as before")
    }

    func testClinicalTeachingCheckboxIsStoredAndOldCoursesDecodeUnticked() throws {
        var ticked = course(institution: "Region Exempelgöta")
        ticked.isClinicalTeaching = true
        let decoded = try JSONDecoder().decode(TeachingCourse.self, from: JSONEncoder().encode(ticked))
        XCTAssertTrue(decoded.isClinicalTeaching)

        let old = try JSONDecoder().decode(TeachingCourse.self, from: Data(#"{"id":"old","nameSv":"Kurs","institution":"Region Exempelgöta"}"#.utf8))
        XCTAssertFalse(old.isClinicalTeaching)
        let text = try XCTUnwrap(String(data: JSONEncoder().encode(old), encoding: .utf8))
        XCTAssertFalse(text.contains("isClinicalTeaching"), "an unticked box is not written")
    }

    func testMigrationFindsTheCoursesTheWordRulePlacedUnderClinicalTeaching() {
        let settings = WorkflowDefaultSettings.builtIn
        XCTAssertTrue(course(institution: "Region Exempelgöta").resolvesToClinicalTeachingByInstitutionWord(settings: settings))
        XCTAssertFalse(course(institution: "Exempelköpings universitet").resolvesToClinicalTeachingByInstitutionWord(settings: settings))
        XCTAssertFalse(course(term: "Termin 6", institution: "Region Exempelgöta").resolvesToClinicalTeachingByInstitutionWord(settings: settings), "a term placed it under the standard programme")

        var withProgramme = course(institution: "Region Exempelgöta")
        withProgramme.programSv = "Exempelprogrammet"
        XCTAssertFalse(withProgramme.resolvesToClinicalTeachingByInstitutionWord(settings: settings), "its own programme wins")

        var alreadyClinical = course(institution: "Region Exempelgöta")
        alreadyClinical.contextType = .clinicalTeaching
        XCTAssertFalse(alreadyClinical.resolvesToClinicalTeachingByInstitutionWord(settings: settings), "already clinical by type")

        var administration = course(institution: "Region Exempelgöta")
        administration.contextType = .courseAdministration
        XCTAssertFalse(administration.resolvesToClinicalTeachingByInstitutionWord(settings: settings))

        var custom = WorkflowDefaultSettings()
        custom.clinicalTeachingOrganizationWords = ["sjukhus"]
        XCTAssertTrue(course(institution: "Universitetssjukhuset").resolvesToClinicalTeachingByInstitutionWord(settings: custom))
        XCTAssertFalse(course(institution: "Region Exempelgöta").resolvesToClinicalTeachingByInstitutionWord(settings: custom))
    }

    @MainActor
    func testClinicalTeachingMigrationRunsOnceAndKeepsEveryCourse() {
        let region = TeachingCourse(id: "region", name: "Klinisk placering", institution: "Region Exempelgöta")
        let university = TeachingCourse(id: "uni", name: "Föreläsning", institution: "Exempelköpings universitet")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.migrationLog = []
        let store = GrantDataStore(
            metadata: metadata,
            teachingCourses: [region, university],
            skipInitialMigration: true
        )
        store.runRound7OneTimeDataMigrations()
        XCTAssertEqual(store.teachingCourses.count, 2)
        XCTAssertEqual(store.teachingCourses.first { $0.id == "region" }?.isClinicalTeaching, true)
        XCTAssertEqual(store.teachingCourses.first { $0.id == "uni" }?.isClinicalTeaching, false)
        XCTAssertTrue((store.metadata.migrationLog ?? []).contains { $0.key == "round7-clinical-teaching-checkbox" })
        XCTAssertEqual(
            store.teachingCourses.first { $0.id == "region" }?.localizedProgram(language: .swedish),
            "Klinisk undervisning",
            "the course stays where it was"
        )
    }

    func testTermTranslationUsesTheSettings() {
        XCTAssertEqual(WorkflowDefaultSettings.builtIn.translatedTeachingTerm(fromSwedish: "Termin 6"), "Semester 6")
        XCTAssertNil(WorkflowDefaultSettings.builtIn.translatedTeachingTerm(fromSwedish: "HT 2025"))

        var settings = WorkflowDefaultSettings()
        settings.teachingTermWordEn = "Term"
        XCTAssertEqual(settings.translatedTeachingTerm(fromSwedish: "Termin 6"), "Term 6")
    }

    // MARK: G. Teaching merits export

    func testSupervisionHeadingsMatchTheOldText() {
        let settings = WorkflowDefaultSettings.builtIn
        XCTAssertEqual(
            settings.doctoralSupervisionTitle(principal: true),
            "Handledning av studerande på forskarnivå - huvudhandledare (6 månader på heltid (100%) motsvarar 40 timmar; max 320 timmar/doktorand kan redovisas)"
        )
        XCTAssertEqual(
            settings.doctoralSupervisionTitle(principal: false),
            "Handledning av studerande på forskarnivå - bihandledare (12 månader på heltid (100%) motsvarar 40 timmar; max 160 timmar/doktorand kan redovisas)"
        )
    }

    @MainActor
    func testTeachingMeritsDocumentCarriesFacultyAndRules() throws {
        var settings = WorkflowDefaultSettings()
        settings.teachingMeritsFacultyName = "Filosofiska fakulteten"
        settings.principalSupervisionMaxHours = 400
        let document = store(settings: settings).teachingMeritsExportDocument()
        XCTAssertEqual(document.facultyName, "Filosofiska fakulteten")
        XCTAssertEqual(store(settings: WorkflowDefaultSettings()).teachingMeritsExportDocument().facultyName, "", "no faculty is built in")
        let titles = document.groups.flatMap(\.tables).map(\.title)
        XCTAssertTrue(titles.contains { $0.contains("huvudhandledare") && $0.contains("max 400 timmar") }, "\(titles)")
    }

    // MARK: H. Statements

    func testStatementTextsMatchTheOldTextByDefault() {
        let settings = WorkflowDefaultSettings.builtIn
        XCTAssertEqual(settings.fundingStatement(fundersText: "A and B", english: true), "The study was funded by A and B.")
        XCTAssertEqual(settings.fundingStatement(fundersText: "A och B", english: false), "Studien finansierades av A och B.")
        XCTAssertEqual(
            settings.ethicsStatement(caseNumbers: [], trialIDs: ["NCT1"], english: true),
            "The study complied with the declaration of Helsinki."
        )
        XCTAssertEqual(
            settings.ethicsStatement(caseNumbers: ["2020-1", "2021-2"], trialIDs: ["NCT1"], english: true),
            "The study complied with the declaration of Helsinki and was approved by the Swedish Ethical Review Authority (Dnr 2020-1, 2021-2). All participants gave written, informed consent prior to participation. Prior to commencement, the study was registered at ClinicalTrials.gov (registration number NCT1)."
        )
        XCTAssertEqual(
            settings.ethicsStatement(caseNumbers: ["2020-1"], trialIDs: [], english: false),
            "Studien följde Helsingforsdeklarationen och godkändes av Etikprövningsmyndigheten (Dnr 2020-1). Samtliga deltagare lämnade skriftligt informerat samtycke före deltagande."
        )
    }

    func testStatementTemplatesReplaceTheirPlaceholders() {
        var settings = WorkflowDefaultSettings()
        settings.fundingStatementTemplateEn = "Funding: {funders}."
        settings.ethicsApprovalTemplateEn = "Approved ({dnr})."
        settings.ethicsTrialTemplateEn = "Registered as {trial}."
        XCTAssertEqual(settings.fundingStatement(fundersText: "X", english: true), "Funding: X.")
        XCTAssertEqual(
            settings.ethicsStatement(caseNumbers: ["1"], trialIDs: ["NCT9"], english: true),
            "Approved (1). Registered as NCT9."
        )
    }

    // MARK: H. Hjärt-Lungfonden and author lists

    func testHeartLungfondenPeriodDefaultsToFiveAndSixYears() {
        var configuration = PublicationHeartLungfondenExportConfiguration()
        XCTAssertEqual(configuration.yearWindow, 5)
        configuration.includeCompensableTime = true
        XCTAssertEqual(configuration.yearWindow, 6)
        configuration.baseYearWindow = 3
        XCTAssertEqual(configuration.yearWindow, 4)
        configuration.includeCompensableTime = false
        XCTAssertEqual(configuration.yearWindow, 3)
    }

    func testAlwaysShowMyNameIsOnForOldSavedOptions() throws {
        var options = PublicationExportOptions()
        XCTAssertTrue(options.alwaysShowOwnName)
        let data = try JSONEncoder().encode(options)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "alwaysShowOwnName")
        let old = try JSONDecoder().decode(PublicationExportOptions.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.alwaysShowOwnName)

        options.alwaysShowOwnName = false
        let roundTrip = try JSONDecoder().decode(PublicationExportOptions.self, from: JSONEncoder().encode(options))
        XCTAssertFalse(roundTrip.alwaysShowOwnName)
    }

    @MainActor
    func testAuthorListIsExtendedToMyNameOnlyWhenChosen() throws {
        let currentUser = PublicationAuthor(
            id: "author-me",
            name: "Pontus af Lindholm",
            firstName: "Pontus",
            lastName: "af Lindholm"
        )
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Long author list",
            journal: "Medical Journal",
            status: PublicationStatus.published.rawValue,
            year: "2025",
            isPeerReviewed: true,
            authorNames: [
                "Alice Andersson",
                "Bertil Berg",
                "Carla Carlsson",
                "David Dahl",
                "Pontus af Lindholm",
                "Erik Ek"
            ]
        )
        let testStore = store(publicationAuthors: [currentUser], publicationRecords: [publication])
        var options = PublicationExportOptions()
        options.authorCountBeforeEtAl = 3

        func authors() throws -> String {
            try XCTUnwrap(
                testStore.amaSections(
                    exportLanguage: .english,
                    options: options,
                    includedSections: [.publishedOriginalArticles]
                ).first?.items.first
            ).authors
        }

        let extended = try authors()
        XCTAssertTrue(extended.contains("Lindholm"), extended)
        XCTAssertTrue(extended.contains("et al"), extended)

        options.alwaysShowOwnName = false
        let cut = try authors()
        XCTAssertFalse(cut.contains("Lindholm"), cut)
        XCTAssertFalse(cut.contains("Dahl"), cut)
        XCTAssertTrue(cut.contains("et al"), cut)
    }

    // MARK: F. Statistics without the qualification computation

    @MainActor
    func testStatisticsViewStillRendersEveryTab() {
        let testStore = store(applications: [Self.application(id: "a", amount: 300_000)])
        for tab in StatisticsDashboardTab.allCases {
            let hostingView = NSHostingView(rootView: StatisticsView(store: testStore, isActive: true, initialTab: tab))
            hostingView.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            hostingView.layoutSubtreeIfNeeded()
            XCTAssertEqual(hostingView.frame.width, 1200, "tab \(tab.rawValue)")
        }
        XCTAssertFalse(testStore.statisticsBlocks.isEmpty)
    }

    // MARK: Journal metrics: publication year, else the latest registered year

    private static func journal() -> PublicationJournal {
        PublicationJournal(
            name: "Test Journal",
            rankingRows: [
                JournalRankingRow(kind: .clarivateScieJIF, yearlyMetrics: [
                    JournalYearMetric(year: 2022, value: "3.1", quartile: "Q2"),
                    JournalYearMetric(year: 2024, value: "4.2", quartile: "Q1"),
                ]),
                JournalRankingRow(kind: .norwegianList, yearlyMetrics: [
                    JournalYearMetric(year: 2023, value: "2", quartile: ""),
                ]),
            ],
            // A stored year that no longer steers anything.
            metricsYear: "2021"
        )
    }

    func testJournalMetricUsesThePublicationYearWhenItHasAValue() throws {
        let metric = try XCTUnwrap(Self.journal().metric(for: .clarivateScieJIF, publicationYear: 2022))
        XCTAssertEqual(metric.value, "3.1")
        XCTAssertEqual(metric.quartile, "Q2")
        XCTAssertFalse(metric.uncertain)

        let snapshot = Self.journal().rankingSnapshot(for: 2022)
        XCTAssertEqual(snapshot.jif, "3.1")
        XCTAssertFalse(snapshot.uncertain)
    }

    func testJournalMetricFallsBackToTheLatestRegisteredYear() throws {
        let metric = try XCTUnwrap(Self.journal().metric(for: .clarivateScieJIF, publicationYear: 2023))
        XCTAssertEqual(metric.value, "4.2", "2023 has no value, so the newest registered year is used")
        XCTAssertTrue(metric.uncertain)

        let snapshot = Self.journal().rankingSnapshot(for: 2023)
        XCTAssertEqual(snapshot.jif, "4.2")
        XCTAssertEqual(snapshot.norwegian, "2", "the Norwegian list has its own registered year")
        XCTAssertTrue(snapshot.uncertain)

        let withoutYear = Self.journal().rankingSnapshot(for: nil)
        XCTAssertEqual(withoutYear.jif, "4.2", "no publication year: the newest year, not the stored metrics year")
        XCTAssertEqual(withoutYear.norwegian, "2")
        XCTAssertFalse(withoutYear.uncertain)
    }

    func testMetricsYearLabelIsTheNewestYearWithValues() {
        let journal = Self.journal()
        XCTAssertEqual(journal.latestRegisteredMetricsYear, 2024)
        XCTAssertEqual(journal.latestRegisteredYear(for: [.norwegianList]), 2023)
        XCTAssertNil(PublicationJournal(name: "Empty").latestRegisteredMetricsYear)
    }

    @MainActor
    func testExportCanUseTheLatestRegisteredYearInsteadOfThePublicationYear() throws {
        let publication = PublicationRecord(
            id: "publication-metrics",
            title: "Metrics",
            journal: "Test Journal",
            status: PublicationStatus.published.rawValue,
            year: "2022",
            isPeerReviewed: true,
            authorNames: ["Alice Andersson"]
        )
        let testStore = GrantDataStore(
            publicationJournals: [Self.journal()],
            publicationRecords: [publication]
        )
        var options = PublicationExportOptions()
        options.includeClarivateSCIEJIF = true
        XCTAssertEqual(options.impactFactorYearMode, .publicationYear, "the publication year is the default")

        func exported() throws -> String {
            try XCTUnwrap(
                testStore.amaSections(
                    exportLanguage: .english,
                    options: options,
                    includedSections: [.publishedOriginalArticles]
                ).first?.items.first
            ).plain
        }

        let publicationYearText = try exported()
        XCTAssertTrue(publicationYearText.contains("IF 3.1"), publicationYearText)
        options.impactFactorYearMode = .latestAvailable
        let latestText = try exported()
        XCTAssertTrue(latestText.contains("IF 4.2"), latestText)
    }
}
