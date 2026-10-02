import XCTest
@testable import Footprint

/// Trial run against a copy of `data_snapshot/Footprint` (CLAUDE.md: changes to
/// the data model are tried on the snapshot before a pull request, with record
/// counts before and after). The snapshot itself is never opened: the files are
/// copied to a temporary folder first. The counts are printed with the prefix
/// "SNAPSHOT:" so they can be read in the CI log.
final class SnapshotTrialRunTests: XCTestCase {
    private var storageDirectory: URL!

    private static var snapshotDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("data_snapshot/Footprint", isDirectory: true)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let source = Self.snapshotDirectory
        let files = (try? FileManager.default.contentsOfDirectory(atPath: source.path)) ?? []
        guard files.contains("footprint.sqlite") else {
            throw XCTSkip("data_snapshot is not in this checkout")
        }
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotTrialRunTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        for file in files where file.hasPrefix("footprint.sqlite") {
            try FileManager.default.copyItem(
                at: source.appendingPathComponent(file),
                to: storageDirectory.appendingPathComponent(file)
            )
        }
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

    @MainActor
    private static func recordCounts(_ store: GrantDataStore) -> [(String, Int)] {
        [
            ("Ansökningar", store.applications.count),
            ("Projekt", store.projects.count),
            ("Organisationer", store.organizations.count),
            ("Forskare", store.publicationAuthors.count),
            ("Publikationer", store.publicationRecords.count),
            ("Tidskrifter", store.publicationJournals.count),
            ("Möten", store.calendarMeetingRecords.count),
            ("Resor", store.calendarTravelRecords.count),
            ("Boenden", store.calendarAccommodationRecords.count),
            ("Uppgifter", store.taskItems.count),
            ("Undervisningsuppdrag", store.teachingAssignments.count),
            ("Kurser och program", store.teachingCourses.count),
            ("Doktorander", store.doctoralCandidates.count),
            ("Konferensbidrag", store.cvConferenceContributions.count),
            ("Granskningsuppdrag", store.cvReviewEntries.count),
            ("Medieframträdanden", store.cvMediaAppearances.count),
            ("Medsökande (namn)", store.applications.reduce(0) { $0 + $1.coApplicants.count }),
            ("Projektmedlemmar (namn)", store.projects.reduce(0) { $0 + $1.collaboratorNames.count }),
            ("Publikationsförfattare (namn)", store.publicationRecords.reduce(0) { $0 + $1.authorNames.count }),
        ]
    }

    /// F21: researchers and their affiliation, employment and education rows.
    @MainActor
    private static func researcherRowCounts(_ store: GrantDataStore) -> [(String, Int)] {
        [
            ("Forskare", store.publicationAuthors.count),
            ("Affilieringar", store.publicationAuthors.reduce(0) { $0 + $1.affiliations.count }),
            ("Anställningar", store.publicationAuthors.reduce(0) { $0 + $1.employments.count }),
            ("Utbildningar", store.publicationAuthors.reduce(0) { $0 + $1.educationEntries.count }),
        ]
    }

    /// F21: how many rows of each kind point to a unit, to an organization
    /// only, or to nothing.
    @MainActor
    private static func treeLinkCounts(_ store: GrantDataStore) -> [(String, Int, Int, Int)] {
        let authors = store.publicationAuthors
        func counts(_ pairs: [(String?, String?)]) -> (Int, Int, Int) {
            let withUnit = pairs.filter { $0.1 != nil }.count
            let organizationOnly = pairs.filter { $0.0 != nil && $0.1 == nil }.count
            let unlinked = pairs.filter { $0.0 == nil }.count
            return (withUnit, organizationOnly, unlinked)
        }
        let affiliations = counts(authors.flatMap { $0.affiliations.map { ($0.organizationID, $0.unitID) } })
        let employments = counts(authors.flatMap { $0.employments.map { ($0.organizationID, $0.unitID) } })
        let education = counts(authors.flatMap { $0.educationEntries.map { ($0.organizationID, $0.unitID) } })
        return [
            ("Affilieringar", affiliations.0, affiliations.1, affiliations.2),
            ("Anställningar", employments.0, employments.1, employments.2),
            ("Utbildningar", education.0, education.1, education.2),
        ]
    }

    /// Round 7: the stored salary sources, read straight from the copied
    /// database before the app has touched it.
    @MainActor
    private static func storedRound7SalarySources() throws -> [SalarySource]? {
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL, createIfMissing: false)
        let metadata = try sqliteStore.load(DataSourceMetadata.self, named: "metadata")
        return metadata?.salarySources
    }

    /// F21 / round 7: the stored researchers, read straight from the copied
    /// database before the app has touched them.
    @MainActor
    private static func storedResearchers() throws -> [PublicationAuthor] {
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL, createIfMissing: false)
        return try sqliteStore.load([PublicationAuthor].self, named: "publication_authors") ?? []
    }

    private static func salarySourceLine(_ source: SalarySource) -> String {
        "\(source.projectSv ?? "–") / \(source.projectEn ?? "–") (\(source.category.rawValue)): färg \(source.color ?? "ingen sparad") → \(source.effectiveColor.rawValue)"
    }

    /// Round 7: how many rows of each kind show another text in `after`
    /// than in `before` (organization or department text).
    private static func changedTextCounts(before: [PublicationAuthor], after: [PublicationAuthor]) -> (affiliations: Int, employments: Int, education: Int) {
        let beforeByID = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var counts = (affiliations: 0, employments: 0, education: 0)
        for author in after {
            guard let previous = beforeByID[author.id] else { continue }
            for row in author.affiliations {
                guard let old = previous.affiliations.first(where: { $0.id == row.id }) else { continue }
                if [old.organizationSv, old.organizationEn, old.departmentSv, old.departmentEn]
                    != [row.organizationSv, row.organizationEn, row.departmentSv, row.departmentEn] {
                    counts.affiliations += 1
                }
            }
            for row in author.employments {
                guard let old = previous.employments.first(where: { $0.id == row.id }) else { continue }
                if [old.organizationSv, old.organizationEn, old.departmentSv, old.departmentEn]
                    != [row.organizationSv, row.organizationEn, row.departmentSv, row.departmentEn] {
                    counts.employments += 1
                }
            }
            for row in author.educationEntries {
                guard let old = previous.educationEntries.first(where: { $0.id == row.id }) else { continue }
                if [old.organizationSv, old.organizationEn] != [row.organizationSv, row.organizationEn] {
                    counts.education += 1
                }
            }
        }
        return counts
    }

    @MainActor
    func testSnapshotLoadsMigratesAndKeepsEveryRecord() throws {
        let storedSalarySources = try Self.storedRound7SalarySources()
        let storedAuthors = try Self.storedResearchers()
        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let before = Self.recordCounts(store)

        let report = store.migrateNameReferencesToIDsForF13()
        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let after = Self.recordCounts(reloaded)

        for line in report {
            print("SNAPSHOT: \(line)")
        }
        for ((label, countBefore), (_, countAfter)) in zip(before, after) {
            print("SNAPSHOT: \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(before.map(\.1), after.map(\.1), "no record may be lost or added")

        // F13b: how many person names now also carry the researcher's id.
        let coverage: [(String, Int, Int)] = [
            ("Medsökande", reloaded.applications.reduce(0) { $0 + $1.coApplicantAuthorIDs.count },
             reloaded.applications.reduce(0) { $0 + $1.coApplicants.count }),
            ("Projektmedlemmar", reloaded.projects.reduce(0) { $0 + $1.collaboratorAuthorIDs.count },
             reloaded.projects.reduce(0) { $0 + $1.collaboratorNames.count }),
            ("Publikationsförfattare", reloaded.publicationRecords.reduce(0) { $0 + $1.authorIDs.count },
             reloaded.publicationRecords.reduce(0) { $0 + $1.authorNames.count }),
            ("Uppgiftsdeltagare", reloaded.taskItems.reduce(0) { $0 + $1.participantAuthorIDs.count },
             reloaded.taskItems.reduce(0) { $0 + $1.participantNames.count }),
            ("Mötesdeltagare", reloaded.calendarMeetingRecords.reduce(0) { $0 + $1.participantAuthorIDs.count },
             reloaded.calendarMeetingRecords.reduce(0) { $0 + $1.participantNames.count }),
        ]
        for (label, linked, total) in coverage {
            print("SNAPSHOT: \(label) med id: \(linked) av \(total) namn")
        }
        print("SNAPSHOT: Namn att koppla: \(reloaded.unlinkedPersonNames(includeHidden: true).count)")

        // Round 7: the salary sources before and after the one-time data
        // changes.
        let salarySourcesBefore = storedSalarySources ?? []
        print("SNAPSHOT: Omgång 7 lönekällor: före \(salarySourcesBefore.count), efter \(reloaded.salarySources.count)")
        for source in salarySourcesBefore {
            print("SNAPSHOT: Omgång 7 lönekälla före: \(Self.salarySourceLine(source))")
        }
        for source in reloaded.salarySources {
            print("SNAPSHOT: Omgång 7 lönekälla efter: \(Self.salarySourceLine(source))")
        }
        if storedSalarySources != nil {
            XCTAssertEqual(reloaded.salarySources.map(\.id), salarySourcesBefore.map(\.id), "no salary source is lost or added")
            for source in salarySourcesBefore {
                guard let migrated = reloaded.salarySources.first(where: { $0.id == source.id }) else { continue }
                XCTAssertEqual(
                    migrated.effectiveColor,
                    SalarySource.migratedForStoredColorsAndNames([source]).first?.effectiveColor,
                    "salary source \(source.project) keeps today's colour"
                )
                XCTAssertNotNil(migrated.color, "salary source \(source.project) has a stored colour")
            }
        }

        // F21: the organization tree as it is stored (it is built in the
        // data; there is no tool that builds it any more).
        let organizationsBefore = reloaded.organizations
        let rowsBefore = Self.researcherRowCounts(reloaded)
        let unitsBefore = reloaded.organizations.reduce(0) { $0 + $1.units.count }
        print("SNAPSHOT: F21 Organisationer: \(organizationsBefore.count), enheter: \(unitsBefore)")
        for (label, withUnit, organizationOnly, unlinked) in Self.treeLinkCounts(reloaded) {
            print("SNAPSHOT: F21 \(label): \(withUnit) kopplade till en enhet, \(organizationOnly) bara till en organisation, \(unlinked) utan koppling")
        }
        for organization in reloaded.organizations where !organization.units.isEmpty {
            print("SNAPSHOT: F21 \(organization.nameSv): \(organization.units.count) enheter")
        }
        let storedRows = [
            ("Forskare", storedAuthors.count),
            ("Affilieringar", storedAuthors.reduce(0) { $0 + $1.affiliations.count }),
            ("Anställningar", storedAuthors.reduce(0) { $0 + $1.employments.count }),
            ("Utbildningar", storedAuthors.reduce(0) { $0 + $1.educationEntries.count }),
        ]
        for ((label, countBefore), (_, countAfter)) in zip(storedRows, rowsBefore) {
            print("SNAPSHOT: F21 \(label): sparat \(countBefore), efter start \(countAfter)")
        }

        // F21: the start-up repair of old organization ids, run directly on
        // the reloaded store. It never adds or removes a record, and running
        // it again changes nothing.
        let countsBeforeRepair = Self.recordCounts(reloaded) + Self.researcherRowCounts(reloaded)
        let repairedIDs = reloaded.repairLegacyOrganizationIDs()
        let countsAfterRepair = Self.recordCounts(reloaded) + Self.researcherRowCounts(reloaded)
        print("SNAPSHOT: F21 ID-reparation: \(repairedIDs.count) organisationer fick nytt id")
        for ((label, countBefore), (_, countAfter)) in zip(countsBeforeRepair, countsAfterRepair) {
            print("SNAPSHOT: F21 ID-reparation \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(countsBeforeRepair.map(\.1), countsAfterRepair.map(\.1), "the repair never adds or removes a record")
        let legacyOrganizations = reloaded.organizations.filter { UUID(uuidString: $0.id) == nil }
        print("SNAPSHOT: F21 Äldre ID:n efter reparationen: \(legacyOrganizations.count)")
        let idDiagnostic = reloaded.dataStructureDiagnostics().first { $0.id == "first-class-record-ids" }
        print("SNAPSHOT: F21 Förstaklass-ID:n, äldre totalt: \(idDiagnostic?.details.first { $0.id == "legacy-ids" }?.value ?? "?")")
        XCTAssertTrue(legacyOrganizations.isEmpty, "\(legacyOrganizations.map(\.id))")
        XCTAssertEqual(reloaded.organizations.count, organizationsBefore.count, "the repair never adds or removes an organization")
        XCTAssertTrue(reloaded.repairLegacyOrganizationIDs().isEmpty, "running the repair again changes nothing")

        // Round 7: one correct spelling. Loading ran the start-up step that
        // writes the linked organization's and unit's names into the rows;
        // show how many rows got another text than was stored, then run the
        // step directly on the reloaded store (it must change nothing more).
        let atLaunch = Self.changedTextCounts(before: storedAuthors, after: reloaded.publicationAuthors)
        print("SNAPSHOT: Omgång 7 officiella namn vid start: affilieringar \(atLaunch.affiliations), anställningar \(atLaunch.employments), utbildningar \(atLaunch.education) rader fick ny text")
        let authorsBeforeRewrite = reloaded.publicationAuthors
        let rewriteReport = reloaded.applyOfficialOrganizationNamesToResearcherRows()
        let rewritten = Self.changedTextCounts(before: authorsBeforeRewrite, after: reloaded.publicationAuthors)
        print("SNAPSHOT: Omgång 7 officiella namn, körd direkt: \(rewriteReport.total) rader (affilieringar \(rewritten.affiliations), anställningar \(rewritten.employments), utbildningar \(rewritten.education))")
        let beforeRewriteByID = Dictionary(authorsBeforeRewrite.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var unlinkedChanged = 0
        for author in reloaded.publicationAuthors {
            guard let previous = beforeRewriteByID[author.id] else { continue }
            for row in author.affiliations where row.organizationID == nil {
                guard let old = previous.affiliations.first(where: { $0.id == row.id }) else { continue }
                if [old.organizationSv, old.organizationEn, old.departmentSv, old.departmentEn]
                    != [row.organizationSv, row.organizationEn, row.departmentSv, row.departmentEn] {
                    unlinkedChanged += 1
                }
            }
            for row in author.employments where row.organizationID == nil {
                guard let old = previous.employments.first(where: { $0.id == row.id }) else { continue }
                if [old.organizationSv, old.organizationEn, old.departmentSv, old.departmentEn]
                    != [row.organizationSv, row.organizationEn, row.departmentSv, row.departmentEn] {
                    unlinkedChanged += 1
                }
            }
            for row in author.educationEntries where row.organizationID == nil {
                guard let old = previous.educationEntries.first(where: { $0.id == row.id }) else { continue }
                if [old.organizationSv, old.organizationEn] != [row.organizationSv, row.organizationEn] {
                    unlinkedChanged += 1
                }
            }
        }
        print("SNAPSHOT: Omgång 7 rader utan koppling som ändrades: \(unlinkedChanged)")
        XCTAssertEqual(unlinkedChanged, 0, "rows without a link are untouched")
        let rowsAfterRewrite = Self.researcherRowCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(rowsBefore, rowsAfterRewrite) {
            print("SNAPSHOT: Omgång 7 \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(rowsBefore.map(\.1), rowsAfterRewrite.map(\.1), "no researcher or row may be lost or added")
        let secondRun = reloaded.applyOfficialOrganizationNamesToResearcherRows()
        print("SNAPSHOT: Omgång 7 officiella namn, andra körningen: \(secondRun.total) rader")
        XCTAssertTrue(secondRun.isEmpty, "running the rewrite again changes nothing")
    }

    /// Round 7 (E–H): the new default-value settings are stored in the app
    /// settings only. Saving one must not add or lose a single record.
    @MainActor
    func testSnapshotKeepsEveryRecordWhenDefaultValuesAreSaved() throws {
        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let before = Self.recordCounts(store)
        print("SNAPSHOT: E-H sparade standardvärden före: \(store.metadata.workflowDefaults == nil ? "inga" : "finns")")
        XCTAssertEqual(store.workflowDefaultSettings.resolvedCurrency, "SEK", "the snapshot keeps today's defaults")

        var settings = store.workflowDefaultSettings
        settings.newApplicationClosesAfterMonths = 4
        settings.teachingMeritsFacultyName = "Testfakulteten"
        store.autosaveWorkflowDefaultSettings(settings)
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        XCTAssertFalse(reloaded.storageWritesBlockedByLoadFailure, reloaded.loadError ?? "")
        let after = Self.recordCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(before, after) {
            print("SNAPSHOT: E-H \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(before.map(\.1), after.map(\.1), "no record may be lost or added")
        XCTAssertEqual(reloaded.workflowDefaultSettings.resolvedClosesAfterMonths, 4)
        XCTAssertEqual(reloaded.workflowDefaultSettings.resolvedTeachingMeritsFacultyName, "Testfakulteten")
        XCTAssertEqual(reloaded.workflowDefaultSettings.resolvedCurrency, "SEK")
        WorkflowDefaultSettingsRegistry.replace(with: .builtIn)
    }

    /// Round 7: home organization, calendar category settings and the salary
    /// calculator flag. Roles stored on the organizations must stay exactly as
    /// they are (the app no longer adds or removes roles by name).
    @MainActor
    func testSnapshotHomeOrganizationSettingsKeepRolesAndRecords() throws {
        let databaseURL = storageDirectory.appendingPathComponent("footprint.sqlite")
        let rawStore = try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        let storedOrganizations = try XCTUnwrap(rawStore.load([OrganizationRecord].self, named: "organizations"))
        let rolesBefore = Dictionary(uniqueKeysWithValues: storedOrganizations.map { ($0.id, $0.roles) })

        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let countsBefore = Self.recordCounts(store)
        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let countsAfter = Self.recordCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: R7 \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")

        var changedRoles = 0
        for organization in reloaded.organizations {
            guard let before = rolesBefore[organization.id] else { continue }
            if Set(before) != Set(organization.roles) {
                changedRoles += 1
                print("SNAPSHOT: R7 roller ändrade: \(organization.nameSv): \(before.map(\.rawValue)) -> \(organization.roles.map(\.rawValue))")
            }
        }
        print("SNAPSHOT: R7 Organisationer: före \(storedOrganizations.count), efter \(reloaded.organizations.count)")
        print("SNAPSHOT: R7 Organisationer med ändrade roller: \(changedRoles)")
        XCTAssertEqual(changedRoles, 0, "stored roles are kept")
        let flagged = reloaded.organizations.filter(\.usesAsApplicationSalaryCalculator)
        print("SNAPSHOT: R7 Lönekalkyl för ansökningar: \(flagged.count) organisation(er)")
        XCTAssertLessThanOrEqual(flagged.count, 1)
        for organization in flagged {
            print("SNAPSHOT: R7 Lönekalkylens organisation: roller \(organization.roles.map(\.rawValue))")
        }

        let regionName = reloaded.homeRegionOrganizationID.flatMap { reloaded.organization(id: $0)?.nameSv } ?? "ingen"
        print("SNAPSHOT: R7 Hemland: \(reloaded.homeCountryName), hemregion: \(regionName)")
        // The removed "Main employer" setting: an old stored value is kept as it was.
        print("SNAPSHOT: R7 Sparat värde för borttagen huvudarbetsgivare (orört): \(reloaded.metadata.mainEmployerOrganizationID ?? "inget")")
        for setting in reloaded.metadata.calendarCategoryBehaviors ?? [] {
            print("SNAPSHOT: R7 Kategori \(setting.categoryName): ej i mötesstatistik=\(setting.excludedFromMeetingStatistics), klinisk tid=\(setting.isClinicalTime), ledighet=\(setting.isLeave)")
        }
        XCTAssertNotNil(reloaded.metadata.calendarCategoryBehaviors, "the category settings are stored once")

        // Clinical activities are placed at the home region as before.
        let clinical = reloaded.calendarMeetingRecords.filter { reloaded.calendarCategoryIsClinicalTime(named: $0.meetingType) }
        let atRegion = clinical.filter { $0.organizationID != nil && $0.organizationID == reloaded.homeRegionOrganizationID }
        print("SNAPSHOT: R7 Kliniska aktiviteter: \(clinical.count), kopplade till hemregionen: \(atRegion.count)")
    }

    /// Round 7 (Handledningstimmar, user decision): the hours on the supervision
    /// periods are hours per term, summed up to today or the period's end date.
    /// Nothing is written: prints each candidate's total and checks that the
    /// candidates, supervisors and periods stay exactly as stored.
    @MainActor
    func testSnapshotDoctoralSupervisionHoursAreSummedFromPeriodsAndKeepRecords() throws {
        let databaseURL = storageDirectory.appendingPathComponent("footprint.sqlite")
        let rawStore = try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        let storedCandidates = try rawStore.load([DoctoralCandidateRecord].self, named: "doctoral_candidates") ?? []
        let storedPeriodCount = storedCandidates.reduce(0) { $0 + $1.supervisionPeriods.count }
        print("SNAPSHOT: Handledningstimmar doktorander i databasen: \(storedCandidates.count), tidsperioder: \(storedPeriodCount)")

        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let countsBefore = Self.recordCounts(store)
        let fixedReference = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-09-29"))
        for candidate in store.doctoralCandidates {
            let totalText = candidate.accruedSupervisionHours(referenceDate: fixedReference).map { String(Int($0)) + " h" } ?? "inga timmar per termin"
            let todayText = candidate.accruedSupervisionHours().map { String(Int($0)) + " h" } ?? "-"
            print("SNAPSHOT: Handledningstimmar \(candidate.candidateName): \(totalText) per 2026-09-29, \(todayText) idag")
            for period in candidate.supervisionPeriods where !period.isEmpty {
                let terms = DoctoralSupervisionPeriod.accruedTerms(from: period.from, to: period.to, referenceDate: fixedReference)
                let endText = period.to.isEmpty ? "(öppen)" : period.to
                print("SNAPSHOT: Handledningstimmar   \(period.from) till \(endText): \(period.hoursPerSemester) h/termin x \(terms) terminer")
            }
        }

        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let countsAfter = Self.recordCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: Handledningstimmar \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")
        XCTAssertEqual(storedCandidates.count, reloaded.doctoralCandidates.count)
        let reloadedPeriodCount = reloaded.doctoralCandidates.reduce(0) { $0 + $1.supervisionPeriods.count }
        print("SNAPSHOT: Handledningstimmar tidsperioder: före \(storedPeriodCount), efter \(reloadedPeriodCount)")
        XCTAssertEqual(storedPeriodCount, reloadedPeriodCount)

        let reloadedByID = Dictionary(uniqueKeysWithValues: reloaded.doctoralCandidates.map { ($0.id, $0) })
        for stored in storedCandidates {
            let after = try XCTUnwrap(reloadedByID[stored.id])
            XCTAssertEqual(after.supervisors.map(\.name), stored.supervisors.map(\.name))
            XCTAssertEqual(after.supervisionPeriods.map(\.from), stored.supervisionPeriods.map(\.from))
            XCTAssertEqual(after.supervisionPeriods.map(\.to), stored.supervisionPeriods.map(\.to))
            XCTAssertEqual(after.supervisionPeriods.map(\.hoursPerSemester), stored.supervisionPeriods.map(\.hoursPerSemester))
            XCTAssertEqual(
                after.accruedSupervisionHours(referenceDate: fixedReference),
                stored.accruedSupervisionHours(referenceDate: fixedReference),
                "the total comes from the stored periods only"
            )
        }
    }

    /// Round 7 (user decision): clinical teaching is a checkbox on the course.
    /// The one-time step ticks it for the courses the word rule placed under
    /// "Klinisk undervisning", so the same courses are there before and after.
    @MainActor
    func testSnapshotClinicalTeachingCheckboxKeepsTheSameCourses() throws {
        let databaseURL = storageDirectory.appendingPathComponent("footprint.sqlite")
        let rawStore = try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        let storedCourses = try rawStore.load([TeachingCourse].self, named: "teaching_courses") ?? []
        let storedMetadata = try rawStore.load(DataSourceMetadata.self, named: "metadata")
        let settings = storedMetadata?.workflowDefaults ?? .builtIn
        WorkflowDefaultSettingsRegistry.replace(with: settings)
        defer { WorkflowDefaultSettingsRegistry.replace(with: .builtIn) }

        let viaWord = storedCourses.filter { $0.resolvesToClinicalTeachingByInstitutionWord(settings: settings) }
        let clinicalLabel = "Klinisk undervisning"
        let underClinicalBefore = storedCourses.filter {
            $0.localizedProgram(language: .swedish) == clinicalLabel
                || $0.resolvesToClinicalTeachingByInstitutionWord(settings: settings)
        }

        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let countsBefore = Self.recordCounts(store)
        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let countsAfter = Self.recordCounts(reloaded)
        let ticked = reloaded.teachingCourses.filter(\.isClinicalTeaching)
        let underClinicalAfter = reloaded.teachingCourses.filter { $0.localizedProgram(language: .swedish) == clinicalLabel }
        print("SNAPSHOT: Kurser med klinisk undervisning: före (via ord) \(viaWord.count), efter (kryssruta) \(ticked.count)")
        print("SNAPSHOT: Kurser under Klinisk undervisning: före \(underClinicalBefore.count), efter \(underClinicalAfter.count)")
        print("SNAPSHOT: Kurser och program: före \(storedCourses.count), efter \(reloaded.teachingCourses.count)")
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: Klinisk undervisning \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(viaWord.count, ticked.count)
        XCTAssertEqual(Set(viaWord.map(\.id)), Set(ticked.map(\.id)))
        XCTAssertEqual(Set(underClinicalBefore.map(\.id)), Set(underClinicalAfter.map(\.id)), "no course moves")
        XCTAssertEqual(storedCourses.count, reloaded.teachingCourses.count)
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")
        XCTAssertTrue((reloaded.metadata.migrationLog ?? []).contains { $0.key == "round7-clinical-teaching-checkbox" })
    }

    /// "Alla kopplingar via id": how many rows point to their record by id,
    /// as stored before the app has touched the copy and after the start-up
    /// steps and a save. The review assignments' organization is the new
    /// link; it is filled only where exactly one organization has the name.
    /// No record may be lost or added, and no written organization text may
    /// change.
    @MainActor
    func testSnapshotLinksByIDBeforeAndAfter() throws {
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL, createIfMissing: false)
        let storedApplications = try sqliteStore.load([GrantApplication].self, named: "applications") ?? []
        let storedPublications = try sqliteStore.load([PublicationRecord].self, named: "publication_records") ?? []
        let storedContributions = try sqliteStore.load([CVConferenceContribution].self, named: "cv_conference_contributions") ?? []
        let storedReviews = try sqliteStore.load([CVReviewEntry].self, named: "cv_review_entries") ?? []
        let storedCandidates = try sqliteStore.load([DoctoralCandidateRecord].self, named: "doctoral_candidates") ?? []
        let storedCourses = try sqliteStore.load([TeachingCourse].self, named: "teaching_courses") ?? []

        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let before = Self.recordCounts(store)
        _ = store.migrateNameReferencesToIDsForF13()
        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        XCTAssertFalse(reloaded.storageWritesBlockedByLoadFailure, reloaded.loadError ?? "")
        let after = Self.recordCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(before, after) {
            print("SNAPSHOT: Alla kopplingar via id, \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(before.map(\.1), after.map(\.1), "no record may be lost or added")

        func coverage<Row>(_ rows: [Row], name: (Row) -> String?, id: (Row) -> String?) -> (linked: Int, total: Int) {
            let named = rows.filter { name($0)?.trimmedOrNil != nil }
            return (named.filter { id($0)?.trimmedOrNil != nil }.count, named.count)
        }
        typealias Coverage = (linked: Int, total: Int)
        var lines: [(label: String, stored: Coverage, migrated: Coverage)] = []
        lines.append((
            "Ansökningar, anslagsgivare",
            coverage(storedApplications, name: { $0.organization }, id: { $0.organizationID }),
            coverage(reloaded.applications, name: { $0.organization }, id: { $0.organizationID })
        ))
        lines.append((
            "Ansökningar, medelsförvaltare",
            coverage(storedApplications, name: { $0.applicationManager }, id: { $0.applicationManagerID }),
            coverage(reloaded.applications, name: { $0.applicationManager }, id: { $0.applicationManagerID })
        ))
        lines.append((
            "Ansökningar, projekt",
            coverage(storedApplications, name: { $0.projectType }, id: { $0.projectID }),
            coverage(reloaded.applications, name: { $0.projectType }, id: { $0.projectID })
        ))
        lines.append((
            "Publikationer, tidskrift",
            coverage(storedPublications, name: { $0.journal }, id: { $0.journalID }),
            coverage(reloaded.publicationRecords, name: { $0.journal }, id: { $0.journalID })
        ))
        lines.append((
            "Publikationer, projekt",
            coverage(storedPublications, name: { $0.projectName }, id: { $0.projectID }),
            coverage(reloaded.publicationRecords, name: { $0.projectName }, id: { $0.projectID })
        ))
        lines.append((
            "Konferensbidrag, projekt",
            coverage(storedContributions, name: { $0.projectName }, id: { $0.projectID }),
            coverage(reloaded.cvConferenceContributions, name: { $0.projectName }, id: { $0.projectID })
        ))
        lines.append((
            "Konferensbidrag, tidskrift",
            coverage(storedContributions, name: { $0.journalName }, id: { $0.journalID }),
            coverage(reloaded.cvConferenceContributions, name: { $0.journalName }, id: { $0.journalID })
        ))
        lines.append((
            "Granskningar, tidskrift",
            coverage(storedReviews, name: { $0.journalName }, id: { $0.journalID }),
            coverage(reloaded.cvReviewEntries, name: { $0.journalName }, id: { $0.journalID })
        ))
        let storedReviewOrganizations = coverage(storedReviews, name: { $0.organizationName }, id: { $0.organizationID })
        let migratedReviewOrganizations = coverage(reloaded.cvReviewEntries, name: { $0.organizationName }, id: { $0.organizationID })
        lines.append(("Granskningar, organisation (nytt fält)", storedReviewOrganizations, migratedReviewOrganizations))
        lines.append((
            "Doktorander, lärosäte",
            coverage(storedCandidates, name: { $0.institution }, id: { $0.institutionID }),
            coverage(reloaded.doctoralCandidates, name: { $0.institution }, id: { $0.institutionID })
        ))
        lines.append((
            "Kurser och program, lärosäte",
            coverage(storedCourses, name: { $0.institution }, id: { $0.institutionID }),
            coverage(reloaded.teachingCourses, name: { $0.institution }, id: { $0.institutionID })
        ))
        for line in lines {
            print("SNAPSHOT: Alla kopplingar via id, \(line.label): före \(line.stored.linked) av \(line.stored.total) kopplade med id, efter \(line.migrated.linked) av \(line.migrated.total) kopplade med id")
        }
        XCTAssertGreaterThanOrEqual(migratedReviewOrganizations.linked, storedReviewOrganizations.linked, "no review organization link may be lost")
        XCTAssertGreaterThanOrEqual(migratedReviewOrganizations.total, storedReviewOrganizations.total, "no review organization text may be lost")

        // The new review link: every id points to an organization that
        // exists, and the organization text the user wrote is kept.
        let organizationIDs = Set(reloaded.organizations.map(\.id))
        XCTAssertEqual(storedReviews.count, reloaded.cvReviewEntries.count, "no review may be lost or added")
        for review in reloaded.cvReviewEntries {
            if let organizationID = review.organizationID {
                XCTAssertTrue(organizationIDs.contains(organizationID), "review \(review.id) points to a missing organization")
            }
            if let stored = storedReviews.first(where: { $0.id == review.id }),
               stored.organizationName.trimmedOrNil != nil {
                XCTAssertEqual(
                    review.organizationName.trimmingCharacters(in: .whitespacesAndNewlines),
                    stored.organizationName.trimmingCharacters(in: .whitespacesAndNewlines),
                    "review \(review.id): the written organization is kept"
                )
            }
        }
        XCTAssertTrue(reloaded.migrateNameReferencesToIDsForF13().isEmpty, "running the migration again changes nothing")
    }

    /// Doktorandvyns tidslinje: admission and planning seminar get their own
    /// stored status ("Genomfört"). Nothing changes at start (data from
    /// before the feature has no status, newer data keeps the one it has);
    /// marking one planning seminar as done keeps every record and every
    /// date, and the choice is still there after reloading.
    @MainActor
    func testSnapshotDoctoralMilestoneStatusKeepsRecords() throws {
        let rawStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL, createIfMissing: false)
        let storedCandidates = try rawStore.load([DoctoralCandidateRecord].self, named: "doctoral_candidates") ?? []
        let storedWithStatus = storedCandidates.filter { $0.planningSeminarOutcomeRaw != nil || $0.admissionOutcomeRaw != nil }.count
        print("SNAPSHOT: Tidslinje doktorander i databasen: \(storedCandidates.count), med sparad status för antagning/planeringsseminarium: \(storedWithStatus)")

        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let countsBefore = Self.recordCounts(store)

        guard var target = store.doctoralCandidates.first(where: { $0.planningSeminarDate.trimmedOrNil != nil }) else {
            throw XCTSkip("no doctoral candidate with a planning seminar in the snapshot")
        }
        let values = DoctoralMilestoneStatus.completed.storedValues
        target.planningSeminarDatePreliminary = values.preliminary
        target.planningSeminarOutcomeRaw = values.outcomeRaw
        store.autosaveDoctoralCandidate(target, resolveDerivedLinks: false)
        XCTAssertTrue(store.flushPendingPersistenceIfNeeded())
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let countsAfter = Self.recordCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: Tidslinje \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")

        let after = try XCTUnwrap(reloaded.doctoralCandidates.first { $0.id == target.id })
        print("SNAPSHOT: Tidslinje planeringsseminarium för en doktorand satt till Genomfört: efter omladdning \(DoctoralMilestoneStatus.current(preliminary: after.planningSeminarDatePreliminary, outcomeRaw: after.planningSeminarOutcomeRaw).title(language: .swedish))")
        XCTAssertEqual(after.planningSeminarOutcomeRaw, DoctoralMilestoneOutcome.completed.rawValue)

        let reloadedByID = Dictionary(uniqueKeysWithValues: reloaded.doctoralCandidates.map { ($0.id, $0) })
        for stored in storedCandidates {
            let candidate = try XCTUnwrap(reloadedByID[stored.id])
            XCTAssertEqual(
                [candidate.admissionDate, candidate.planningSeminarDate, candidate.halftimeDate, candidate.estimatedHalftimeDate, candidate.disputationDate, candidate.plannedDisputationDate],
                [stored.admissionDate, stored.planningSeminarDate, stored.halftimeDate, stored.estimatedHalftimeDate, stored.disputationDate, stored.plannedDisputationDate].map(DateParsers.canonicalizedDayInput(_:)),
                "the dates of \(stored.candidateName) are kept"
            )
            XCTAssertEqual(candidate.halftimeOutcomeRaw, stored.halftimeOutcomeRaw)
            XCTAssertEqual(candidate.plannedDisputationOutcomeRaw, stored.plannedDisputationOutcomeRaw)
            XCTAssertEqual(candidate.admissionOutcomeRaw, stored.admissionOutcomeRaw, "a stored admission status is kept")
            if stored.id != target.id {
                XCTAssertEqual(candidate.planningSeminarOutcomeRaw, stored.planningSeminarOutcomeRaw, "a stored planning seminar status is kept")
                XCTAssertEqual(candidate.planningSeminarDatePreliminary, stored.planningSeminarDatePreliminary)
            }
        }
    }

    /// Round 7 ("Aktiviteter och uppgifter kopplas likadant"): links of
    /// activities and tasks, per kind.
    @MainActor
    private static func activityAndTaskLinkCounts(_ store: GrantDataStore) -> [(String, Int)] {
        let meetings = store.calendarMeetingRecords
        let tasks = store.taskItems
        func meetingSum(_ count: (CalendarMeetingRecord) -> Int) -> Int {
            meetings.reduce(0) { $0 + count($1) }
        }
        var rows: [(String, Int)] = [
            ("Aktiviteter", meetings.count),
            ("Aktivitetskopplingar projekt", meetingSum { $0.projectIDs.count }),
            ("Aktivitetskopplingar organisation", meetingSum { $0.organizationIDs.count }),
            ("Aktivitetskopplingar anslag", meetingSum { $0.applicationIDs.count }),
            ("Aktivitetskopplingar publikation", meetingSum { $0.publicationIDs.count }),
            ("Aktivitetskopplingar media", meetingSum { $0.mediaAppearanceIDs.count }),
            ("Aktivitetskopplingar undervisningsuppdrag", meetingSum { calendarMeetingTeachingAssignmentIDs($0).count }),
            ("Aktivitetskopplingar kurs", meetingSum { $0.teachingCourseIDs.count }),
            ("Aktivitetskopplingar doktorand", meetingSum { calendarMeetingDoctoralCandidateIDs($0).count }),
            ("Uppgifter", tasks.count),
        ]
        for kind in TaskLinkKind.allCases {
            rows.append(("Uppgiftskopplingar \(kind.rawValue)", tasks.reduce(0) { total, task in
                total + task.links.filter { $0.kind == kind }.count
            }))
        }
        return rows
    }

    /// Round 7: the shared link rows add an optional course link to
    /// activities; nothing is rewritten when the data is loaded and saved.
    /// The doctoral candidate page now uses only id links; the activities the
    /// old project/name rule found are only suggested (Data quality), and
    /// linking one adds exactly one link.
    @MainActor
    func testSnapshotActivityAndTaskLinksAreKeptAndDoctoralSuggestionsCounted() throws {
        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let countsBefore = Self.recordCounts(store)
        let linksBefore = Self.activityAndTaskLinkCounts(store)
        let participantsBefore = (
            meetings: store.calendarMeetingRecords.reduce(0) { $0 + $1.participantAuthorIDs.count },
            tasks: store.taskItems.reduce(0) { $0 + $1.participantAuthorIDs.count }
        )

        let suggestions = store.doctoralActivityLinkSuggestions(includeHidden: true)
        let byProject = suggestions.filter(\.matchedByProject).count
        let byName = suggestions.filter(\.matchedByName).count
        print("SNAPSHOT: Aktiviteter att koppla till doktorand: \(suggestions.count) förslag (via projekt \(byProject), via namn \(byName), \(Set(suggestions.map(\.meetingID)).count) olika aktiviteter)")
        for candidate in store.doctoralCandidates {
            let linked = store.calendarMeetingRecords.filter { calendarMeetingDoctoralCandidateIDs($0).contains(candidate.id) }.count
            let suggested = suggestions.filter { $0.candidateID == candidate.id }.count
            print("SNAPSHOT: Doktorand \(candidate.candidateName.nonEmpty ?? candidate.id): kopplade aktiviteter \(linked), föreslagna \(suggested)")
        }
        XCTAssertFalse(
            suggestions.contains { suggestion in
                store.calendarMeetingRecords.contains {
                    $0.id == suggestion.meetingID && calendarMeetingDoctoralCandidateIDs($0).contains(suggestion.candidateID)
                }
            },
            "an activity already linked to the candidate is never suggested"
        )

        try store.persistAll()
        let reloaded = GrantDataStore.loadFromBundle()
        let countsAfter = Self.recordCounts(reloaded)
        let linksAfter = Self.activityAndTaskLinkCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: Kopplas likadant \(label): före \(countBefore), efter \(countAfter)")
        }
        for ((label, countBefore), (_, countAfter)) in zip(linksBefore, linksAfter) {
            print("SNAPSHOT: Kopplas likadant \(label): före \(countBefore), efter \(countAfter)")
        }
        print("SNAPSHOT: Kopplas likadant deltagare med id: aktiviteter \(participantsBefore.meetings) → \(reloaded.calendarMeetingRecords.reduce(0) { $0 + $1.participantAuthorIDs.count }), uppgifter \(participantsBefore.tasks) → \(reloaded.taskItems.reduce(0) { $0 + $1.participantAuthorIDs.count })")
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")
        XCTAssertEqual(linksBefore.map(\.1), linksAfter.map(\.1), "no link may be lost or added")
        XCTAssertEqual(
            reloaded.doctoralActivityLinkSuggestions(includeHidden: true).count,
            suggestions.count,
            "nothing is linked automatically"
        )

        // "Koppla" on one suggestion: exactly one more doctoral candidate link.
        guard let first = reloaded.doctoralActivityLinkSuggestions(includeHidden: true).first else {
            print("SNAPSHOT: Kopplas likadant: inga förslag att prova Koppla på")
            return
        }
        XCTAssertTrue(reloaded.linkSuggestedDoctoralActivity(first))
        _ = reloaded.flushPendingPersistenceIfNeeded()
        let linksAfterLink = Self.activityAndTaskLinkCounts(reloaded)
        let recordsAfterLink = Self.recordCounts(reloaded)
        XCTAssertEqual(recordsAfterLink.map(\.1), countsAfter.map(\.1), "linking adds or loses no record")
        for ((label, countBefore), (_, countAfter)) in zip(linksAfter, linksAfterLink) {
            if countAfter != countBefore {
                print("SNAPSHOT: Kopplas likadant efter Koppla \(label): före \(countBefore), efter \(countAfter)")
            }
            if label == "Aktivitetskopplingar doktorand" {
                XCTAssertEqual(countAfter, countBefore + 1, "Koppla adds exactly one doctoral candidate link")
            } else {
                XCTAssertGreaterThanOrEqual(countAfter, countBefore, "Koppla loses no link: \(label)")
            }
        }
        print("SNAPSHOT: Kopplas likadant efter Koppla på ett förslag: \(reloaded.doctoralActivityLinkSuggestions(includeHidden: true).count) förslag kvar")
    }

    /// Round 8 (user decision): the old no-overhead checkbox on a salary
    /// calculator is cleared without guessing a cap, and the funder setting
    /// "Max OH (%)" becomes the "OH-regel" (a value = "Högst value %", 0 =
    /// "Ingen OH"). No other organization changes, no record is lost or
    /// added, and running the steps again changes nothing. Only counts are
    /// printed.
    @MainActor
    func testSnapshotFunderMaxOverheadMigrationKeepsRecords() throws {
        let databaseURL = storageDirectory.appendingPathComponent("footprint.sqlite")
        let rawStore = try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        let storedOrganizations = try XCTUnwrap(rawStore.load([OrganizationRecord].self, named: "organizations"))
        let storedByID = Dictionary(storedOrganizations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let flaggedIDs = Set(storedOrganizations.filter { $0.salaryCalculator?.legacyExcludesOverhead == true }.map(\.id))
        print("SNAPSHOT: R8 Organisationer med gamla kryssrutan utan OH: \(flaggedIDs.count)")
        print("SNAPSHOT: R8 Organisationer med Max OH före: \(storedOrganizations.filter { $0.legacyMaxOverheadPercent != nil }.count)")
        print("SNAPSHOT: R8 Organisationer med OH-regel före: \(storedOrganizations.filter { $0.overheadRule != nil }.count)")

        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let countsBefore = Self.recordCounts(store)
        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let countsAfter = Self.recordCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: R8 \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")
        XCTAssertEqual(reloaded.organizations.count, storedOrganizations.count)

        var changedOther = 0
        for organization in reloaded.organizations {
            guard let stored = storedByID[organization.id] else { continue }
            // The rule after the steps is exactly what the stored data gives
            // (a stored rule, or the one made from Max OH); nothing is guessed.
            if organization.overheadRule != stored.overheadRule {
                changedOther += 1
            }
            XCTAssertNil(organization.legacyMaxOverheadPercent, "Max OH is no longer stored")
            XCTAssertNotEqual(organization.salaryCalculator?.legacyExcludesOverhead, true, "the old checkbox is no longer stored")
        }
        XCTAssertEqual(changedOther, 0, "no organization gets an OH rule automatically")
        let capped = reloaded.organizations.filter { $0.overheadRule != nil }
        let cappedIDs = Set(capped.map(\.id))
        let linkedApplications = reloaded.applications.filter { application in
            application.organizationID.map { cappedIDs.contains($0) } ?? false
        }
        print("SNAPSHOT: R8 Organisationer med OH-regel efter: \(capped.count)")
        print("SNAPSHOT: R8 Organisationer med OH-undantag efter: \(reloaded.organizations.filter { !($0.overheadRuleExceptions ?? []).isEmpty }.count)")
        print("SNAPSHOT: R8 Ansökningar kopplade (via id) till en finansiär med OH-regel: \(linkedApplications.count)")
        XCTAssertTrue((reloaded.metadata.migrationLog ?? []).contains { $0.key == "round8-funder-max-overhead" })
        XCTAssertTrue((reloaded.metadata.migrationLog ?? []).contains { $0.key == "round8-funder-overhead-rule" })
        XCTAssertFalse(reloaded.runRound8OneTimeDataMigrations(), "running the step again changes nothing")
        XCTAssertFalse(reloaded.migrateLegacyOverheadCheckboxToFunderCapForRound8(), "no checkbox is left to move")
        XCTAssertFalse(reloaded.migrateFunderMaxOverheadToOverheadRuleForRound8(), "no Max OH is left to move")
    }

    /// Round 10 (user decision 2026-09-29): the fund managers' empty "OH som
    /// tas ut" gets this year's OH from their own salary calculator, and only
    /// unlocked records with the status "Att söka" or "Ej sökt" get copies of
    /// the OH numbers. Locked records and records already applied for are
    /// exactly as before, no record is lost or added, and running the step
    /// again changes nothing. Only counts are printed.
    @MainActor
    func testSnapshotRound10RecordOverheadKeepsAppliedRecords() throws {
        let databaseURL = storageDirectory.appendingPathComponent("footprint.sqlite")
        let rawStore = try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        let storedApplications = try XCTUnwrap(rawStore.load([GrantApplication].self, named: "applications"))
        let storedOrganizations = try XCTUnwrap(rawStore.load([OrganizationRecord].self, named: "organizations"))
        let storedByID = Dictionary(storedApplications.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let eligible = storedApplications.filter { !$0.isEditingLocked && $0.isNotYetApplied }
        print("SNAPSHOT: R10 Poster: \(storedApplications.count), varav låsta \(storedApplications.filter(\.isEditingLocked).count)")
        print("SNAPSHOT: R10 Olåsta poster med Att söka eller Ej sökt: \(eligible.count)")
        print("SNAPSHOT: R10 Förvaltare utan OH som tas ut före: \(storedOrganizations.filter { $0.roles.contains(.fundManager) && $0.managerOverheadPercent == nil }.count)")
        print("SNAPSHOT: R10 Finansiärer med OH-regel: \(storedOrganizations.filter { $0.overheadRule != nil }.count), med undantag: \(storedOrganizations.filter { !($0.overheadRuleExceptions ?? []).isEmpty }.count)")

        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let countsBefore = Self.recordCounts(store)
        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let countsAfter = Self.recordCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: R10 \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")

        var filled = 0
        var changedOutsideScope = 0
        for application in reloaded.applications {
            guard let stored = storedByID[application.id] else { continue }
            let inScope = !stored.isEditingLocked && stored.isNotYetApplied
            let gotNumbers = application.funderMaxOverheadPercent != stored.funderMaxOverheadPercent
                || application.managerOverheadPercent != stored.managerOverheadPercent
            if gotNumbers {
                if inScope { filled += 1 } else { changedOutsideScope += 1 }
            }
        }
        print("SNAPSHOT: R10 Poster som fick OH-siffror: \(filled)")
        print("SNAPSHOT: R10 Låsta eller redan sökta poster som ändrades: \(changedOutsideScope)")
        print("SNAPSHOT: R10 Förvaltare utan OH som tas ut efter: \(reloaded.organizations.filter { $0.roles.contains(.fundManager) && $0.managerOverheadPercent == nil }.count)")
        XCTAssertEqual(changedOutsideScope, 0, "locked and applied records are never changed")
        XCTAssertTrue((reloaded.metadata.migrationLog ?? []).contains { $0.key == "round10-record-overhead" })
        XCTAssertFalse(reloaded.runRound10OneTimeDataMigrations(), "running the step again changes nothing")
    }

    /// Round 11 (user decisions 2026-09-30): salary calculators on
    /// organizations not marked as employer are removed once (the one chosen
    /// in Settings stays); employers keep theirs. No record is lost or added,
    /// no other organization field changes, and running the step again
    /// changes nothing. Only counts are printed.
    @MainActor
    func testSnapshotRound11RemovesOnlyHiddenSalaryCalculators() throws {
        let databaseURL = storageDirectory.appendingPathComponent("footprint.sqlite")
        let rawStore = try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        let storedOrganizations = try XCTUnwrap(rawStore.load([OrganizationRecord].self, named: "organizations"))
        let storedApplications = try XCTUnwrap(rawStore.load([GrantApplication].self, named: "applications"))
        let hidden = storedOrganizations.filter {
            $0.salaryCalculator != nil && !$0.roles.contains(.employer) && !$0.usesAsApplicationSalaryCalculator
        }
        let employersWithCalculator = storedOrganizations.filter { $0.salaryCalculator != nil && $0.roles.contains(.employer) }
        print("SNAPSHOT: R11 Organisationer: \(storedOrganizations.count), med lönekalkyl: \(storedOrganizations.filter { $0.salaryCalculator != nil }.count)")
        print("SNAPSHOT: R11 Dolda lönekalkyler (ej arbetsgivare) före: \(hidden.count), varav förvaltare: \(hidden.filter { $0.roles.contains(.fundManager) }.count)")
        print("SNAPSHOT: R11 Arbetsgivare med lönekalkyl före: \(employersWithCalculator.count)")
        print("SNAPSHOT: R11 Ej sökt-poster med dolda ansökningsuppgifter: \(storedApplications.filter { $0.isNotAppliedStatus && !$0.hiddenApplicationDetailTitles(hasOtherApplicants: false, language: .swedish).isEmpty }.count)")

        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let countsBefore = Self.recordCounts(store)
        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let countsAfter = Self.recordCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: R11 \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")

        let storedByID = Dictionary(storedOrganizations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var calculatorRemoved = 0
        var otherwiseChanged = 0
        var employerCalculatorChanged = 0
        for organization in reloaded.organizations {
            guard let stored = storedByID[organization.id] else { continue }
            if stored.salaryCalculator != nil, organization.salaryCalculator == nil { calculatorRemoved += 1 }
            if stored.roles.contains(.employer), stored.salaryCalculator != organization.salaryCalculator { employerCalculatorChanged += 1 }
            var comparable = organization
            comparable.salaryCalculator = stored.salaryCalculator
            if comparable.roles != stored.roles || comparable.nameSv != stored.nameSv || comparable.managerOverheadPercent != stored.managerOverheadPercent || comparable.overheadRule != stored.overheadRule {
                otherwiseChanged += 1
            }
        }
        print("SNAPSHOT: R11 Lönekalkyler borttagna: \(calculatorRemoved)")
        print("SNAPSHOT: R11 Arbetsgivares lönekalkyler som ändrades: \(employerCalculatorChanged)")
        print("SNAPSHOT: R11 Organisationer med annan ändring (namn, roller, OH): \(otherwiseChanged)")
        XCTAssertEqual(calculatorRemoved, hidden.count, "exactly the hidden calculators are removed")
        XCTAssertEqual(employerCalculatorChanged, 0, "employers keep their calculators")
        XCTAssertEqual(otherwiseChanged, 0, "nothing else on the organizations changes")
        XCTAssertTrue((reloaded.metadata.migrationLog ?? []).contains { $0.key == "round11-hidden-salary-calculators" })
        XCTAssertFalse(reloaded.runRound11OneTimeDataMigrations(), "running the step again changes nothing")
    }

    /// Round 13: amounts are read in more ways ("1,5 M", "250 tkr"). Counts
    /// how many stored amount texts the new reading gives a different value
    /// than the old one, how many foreign amounts lack an exchange rate, and
    /// that loading and saving keeps every record. Only counts are printed.
    @MainActor
    func testSnapshotRound13AmountReadingAndCurrency() throws {
        let databaseURL = storageDirectory.appendingPathComponent("footprint.sqlite")
        let rawStore = try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        let storedApplications = try XCTUnwrap(rawStore.load([GrantApplication].self, named: "applications"))

        func oldReading(_ raw: String?) -> String? {
            guard let raw = raw?.trimmedOrNil else { return nil }
            let withoutDecimals = raw.replacingOccurrences(of: #"[.,]\d{1,2}\s*(kr|SEK)?\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            let digits = withoutDecimals.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            guard !digits.isEmpty else { return nil }
            var parts: [String] = []
            var current = digits
            while current.count > 3 {
                parts.insert(String(current.suffix(3)), at: 0)
                current.removeLast(3)
            }
            parts.insert(current, at: 0)
            return parts.joined(separator: " ")
        }
        var amountTexts = 0
        var sameValue = 0
        var differentValue = 0
        for application in storedApplications {
            for raw in [application.approximateAmount, application.appliedAmount, application.grantedAmount] {
                guard raw?.trimmedOrNil != nil else { continue }
                amountTexts += 1
                let old = GrantParsing.numericValue(from: oldReading(raw))
                let new = GrantParsing.numericValue(from: GrantParsing.formatAmountInput(raw))
                if old == new { sameValue += 1 } else { differentValue += 1 }
            }
        }
        print("SNAPSHOT: R13 Beloppstexter: \(amountTexts), samma värde: \(sameValue), annat värde: \(differentValue)")

        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let foreign = store.applications.filter { $0.currencyCode != "SEK" }
        let unconverted = foreign.filter {
            store.isGrantAmountUnconverted(for: $0, amount: $0.grantedAmountValue ?? $0.appliedAmountValue)
        }
        let foreignWithSalaryEstimate = foreign.filter { $0.approximateAmountValue != nil }
        print("SNAPSHOT: R13 Ansökningar i utländsk valuta: \(foreign.count), utan växelkurs: \(unconverted.count)")
        print("SNAPSHOT: R13 Ansökningar i utländsk valuta med lönekalkylbelopp i kronor: \(foreignWithSalaryEstimate.count)")
        print("SNAPSHOT: R13 Dolda varningar: \(store.hiddenDataQualityWarningTotalCount)")

        let countsBefore = Self.recordCounts(store)
        let amountsBefore = Dictionary(
            store.applications.map { ($0.id, [$0.approximateAmountValue, $0.appliedAmountValue, $0.grantedAmountValue]) },
            uniquingKeysWith: { first, _ in first }
        )
        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let countsAfter = Self.recordCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: R13 \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")
        let changedAmounts = reloaded.applications.filter {
            amountsBefore[$0.id] != [$0.approximateAmountValue, $0.appliedAmountValue, $0.grantedAmountValue]
        }.count
        print("SNAPSHOT: R13 Ansökningar vars belopp ändrades vid sparning: \(changedAmounts)")
        XCTAssertEqual(changedAmounts, 0, "saving does not change any amount")
    }

    /// Round 14: old decided records without a decision date keep their
    /// result, attachment locations outside storage are refused unless they
    /// are PDFs, and two repairs that ran on every launch run once. Counts
    /// how many records each change touches; no record may be lost or added.
    /// Only counts are printed.
    @MainActor
    func testSnapshotRound14OldDecisionsAttachmentsAndRepairs() throws {
        let databaseURL = storageDirectory.appendingPathComponent("footprint.sqlite")
        let rawStore = try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        let rawApplications = try XCTUnwrap(rawStore.loadData(named: "applications"))
        let rows = (try JSONSerialization.jsonObject(with: rawApplications) as? [[String: Any]]) ?? []
        func text(_ row: [String: Any], _ key: String) -> String? {
            (row[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        let decidedWithoutDate = rows.filter { row in
            ["Beviljat", "Avslag", "Tillbakadragen"].contains(text(row, "result") ?? "")
                && ["grantedOn", "deniedOn", "withdrawnOn", "decisionOn"].allSatisfy { text(row, $0) == nil }
        }
        print("SNAPSHOT: R14 Ansökningar i databasen: \(rows.count), beslutade utan beslutsdatum: \(decidedWithoutDate.count)")

        let publications = try rawStore.load([PublicationRecord].self, named: "publication_records") ?? []
        let storedPaths = publications.compactMap(\.finalPDFPath).compactMap(\.trimmedOrNil)
        let refusedPaths = storedPaths.filter { GrantDataStore.absoluteAttachmentURL(fromStored: $0) == nil }
        print("SNAPSHOT: R14 Publikationer med sparad PDF-sökväg: \(storedPaths.count), sökvägar som inte längre godtas: \(refusedPaths.count)")

        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let countsBefore = Self.recordCounts(store)
        let projectTasksBefore = store.projects.reduce(0) { $0 + $1.projectTasks.count }
        let congressesBefore = Dictionary(
            store.organizations.map { ($0.id, $0.congresses) },
            uniquingKeysWith: { first, _ in first }
        )
        print("SNAPSHOT: R14 Låsta projekt: \(store.projects.filter(\.isEditingLocked).count)")
        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let countsAfter = Self.recordCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: R14 \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")
        let projectTasksAfter = reloaded.projects.reduce(0) { $0 + $1.projectTasks.count }
        let congressesChanged = reloaded.organizations.filter { congressesBefore[$0.id] != $0.congresses }.count
        print("SNAPSHOT: R14 Projektuppgifter: före \(projectTasksBefore), efter \(projectTasksAfter)")
        print("SNAPSHOT: R14 Organisationer vars kongresser ändrades: \(congressesChanged)")

        _ = reloaded.migrateRecordsIfNeeded()
        let projectTasksAgain = reloaded.projects.reduce(0) { $0 + $1.projectTasks.count }
        print("SNAPSHOT: R14 Projektuppgifter efter en till start: \(projectTasksAgain)")
        XCTAssertEqual(projectTasksAgain, projectTasksAfter, "a second start adds no tasks")
        XCTAssertTrue((reloaded.metadata.migrationLog ?? []).contains { $0.key == "round14-new-funds-tasks-once" })
    }

    /// Round 16: projects get a new optional field (answers to "set to
    /// ongoing?") and one colour rule. Counts how many projects get each
    /// colour, that no project or other record is lost or added by loading
    /// and saving, and that no project gets stored answers by itself.
    /// Only counts are printed.
    @MainActor
    func testSnapshotRound16ProjectColoursAndPromptField() throws {
        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        var toneCounts: [String: Int] = [:]
        for project in store.projects {
            toneCounts[store.projectStatusTone(project).rawValue, default: 0] += 1
        }
        let toneSummary = AppStatusTone.allCases.map { "\($0.rawValue) \(toneCounts[$0.rawValue] ?? 0)" }.joined(separator: ", ")
        print("SNAPSHOT: R16 Projektfärger: \(toneSummary)")
        var applicationToneCounts: [String: Int] = [:]
        for application in store.applications {
            applicationToneCounts[store.applicationStatusTone(application).rawValue, default: 0] += 1
        }
        let applicationSummary = AppStatusTone.allCases.map { "\($0.rawValue) \(applicationToneCounts[$0.rawValue] ?? 0)" }.joined(separator: ", ")
        print("SNAPSHOT: R16 Ansökningsfärger: \(applicationSummary)")

        let countsBefore = Self.recordCounts(store)
        let projectsBefore = Dictionary(store.projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let countsAfter = Self.recordCounts(reloaded)
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: R16 \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")
        let withAnswers = reloaded.projects.filter { !($0.dismissedOngoingPromptKeys ?? []).isEmpty }.count
        let changedProjects = reloaded.projects.filter { projectsBefore[$0.id] != $0 }.count
        print("SNAPSHOT: R16 Projekt med sparade svar på frågan om Pågående: \(withAnswers)")
        print("SNAPSHOT: R16 Projekt som ändrades vid sparning: \(changedProjects)")
        XCTAssertEqual(withAnswers, 0, "no answers are stored without the user answering")
    }

    /// Round 17: "Tillbakadragen" is its own (grey) group and never counts
    /// as "Avslag"; a fully spent grant is a paler green instead of grey.
    /// Prints only counts: applications per outcome group, fully spent
    /// grants, and the declined/withdrawn totals of the organisation
    /// summaries. No names or values.
    @MainActor
    func testSnapshotRound17WithdrawnAndSpentCounts() throws {
        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")

        var groupCounts: [AppStatusTones.ApplicationOutcomeGroup: Int] = [:]
        for application in store.applications {
            let group = AppStatusTones.applicationOutcomeGroup(
                resultLabel: application.resultLabel,
                isGranted: application.isGranted
            )
            groupCounts[group, default: 0] += 1
        }
        let groupSummary = AppStatusTones.ApplicationOutcomeGroup.allCases
            .map { "\($0.rawValue) \(groupCounts[$0] ?? 0)" }
            .joined(separator: ", ")
        print("SNAPSHOT: R17 Ansökningar per utfall: \(groupSummary)")

        let spentGrants = store.applications.filter { $0.isGranted && store.isEffectivelyFullySpent($0) }.count
        print("SNAPSHOT: R17 Förbrukade beviljade anslag (ljusare grön): \(spentGrants)")

        var summary = OrganizationApplicationSummary()
        for application in store.applications {
            summary.include(application)
        }
        print("SNAPSHOT: R17 Organisationssammanfattning (alla ansökningar): avslag \(summary.rejected), tillbakadragna \(summary.withdrawn)")
        XCTAssertEqual(summary.rejected, groupCounts[.declined] ?? 0, "only Avslag counts as declined")
        XCTAssertEqual(summary.withdrawn, groupCounts[.withdrawn] ?? 0)

        let rows = store.organizationRowSnapshots()
        let rowDeclined = rows.reduce(0) { $0 + $1.rejectedCount }
        let rowWithdrawn = rows.reduce(0) { $0 + $1.withdrawnCount }
        print("SNAPSHOT: R17 Organisationsrader: \(rows.count), avslag \(rowDeclined), tillbakadragna \(rowWithdrawn)")

        let dashboard = store.summary
        print("SNAPSHOT: R17 Översikt: avslag \(dashboard.rejectedCount), tillbakadragna \(dashboard.withdrawnCount)")
    }

    /// Round 18: shared tasks get an optional deadline time. Old tasks have
    /// none, so loading and saving must keep every task and add no times by
    /// itself. Prints only counts.
    @MainActor
    func testSnapshotRound18TaskDeadlineTimes() throws {
        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        let tasksBefore = store.taskItems.count
        let timedBefore = store.taskItems.filter { $0.deadlineTime != nil }.count
        let datedBefore = store.taskItems.filter { $0.deadline.trimmedOrNil != nil }.count
        let countsBefore = Self.recordCounts(store)

        _ = store.migrateRecordsIfNeeded()
        try store.persistAll()

        let reloaded = GrantDataStore.loadFromBundle()
        let tasksAfter = reloaded.taskItems.count
        let timedAfter = reloaded.taskItems.filter { $0.deadlineTime != nil }.count
        let datedAfter = reloaded.taskItems.filter { $0.deadline.trimmedOrNil != nil }.count
        let countsAfter = Self.recordCounts(reloaded)
        print("SNAPSHOT: R18 Uppgifter: före \(tasksBefore), efter \(tasksAfter)")
        print("SNAPSHOT: R18 Uppgifter med datum: före \(datedBefore), efter \(datedAfter)")
        print("SNAPSHOT: R18 Uppgifter med klockslag: före \(timedBefore), efter \(timedAfter)")
        for ((label, countBefore), (_, countAfter)) in zip(countsBefore, countsAfter) {
            print("SNAPSHOT: R18 \(label): före \(countBefore), efter \(countAfter)")
        }
        XCTAssertEqual(tasksBefore, tasksAfter, "no task may be lost or added")
        XCTAssertEqual(datedBefore, datedAfter, "no deadline may be lost")
        XCTAssertEqual(timedBefore, timedAfter, "no deadline time is added or lost by saving")
        XCTAssertEqual(countsBefore.map(\.1), countsAfter.map(\.1), "no record may be lost or added")
    }
}
