import XCTest
@testable import Footprint

/// Round 7: one correct spelling on researcher rows (the linked
/// organization's and unit's names), reviews left as they are stored, and
/// salary sources with a stored colour instead of built-in name checks.
final class Round7OrganizationNamesTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round7OrganizationNamesTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: Test data

    private static var uni: OrganizationRecord {
        OrganizationRecord(
            id: "org-uni",
            nameSv: "Exempelköpings universitet",
            nameEn: "Exempelköping University",
            city: "Exempelköping",
            country: "Sweden",
            units: [
                OrganizationUnit(
                    id: "iem",
                    nameSv: "Institutionen för exempelmedicin och vård",
                    nameEn: "Department of Example Medicine and Caring Sciences",
                    abbreviation: "IEM",
                    addressNameEn: "Department of Example Medicine, and Caring Sciences"
                ),
                OrganizationUnit(
                    id: "ike",
                    nameSv: "Institutionen för kliniska exempelvetenskaper",
                    nameEn: "Department of Clinical Example Sciences"
                ),
            ]
        )
    }

    private static var region: OrganizationRecord {
        OrganizationRecord(id: "org-ro", nameSv: "Region Exempelgöta", nameEn: "Region Exempelgöta")
    }

    private static var author: PublicationAuthor {
        PublicationAuthor(
            id: "a1",
            name: "Forskare Ett",
            affiliations: [
                PublicationAffiliation(
                    id: "aff-unit",
                    organization: "Exempelkoping Univ",
                    department: "IEM",
                    organizationID: "org-uni",
                    unitID: "iem"
                ),
                PublicationAffiliation(
                    id: "aff-org",
                    organization: "EXU",
                    department: "Min egen avdelning",
                    organizationID: "org-uni"
                ),
                PublicationAffiliation(id: "aff-free", organization: "Karolinska Institutet", department: "MEB"),
                PublicationAffiliation(
                    id: "aff-missing",
                    organization: "Gammal organisation",
                    department: "Gammal avdelning",
                    organizationID: "org-removed",
                    unitID: "unit-removed"
                ),
            ],
            employments: [
                PublicationAuthorEmployment(
                    id: "emp-unit",
                    from: "2020-01-01",
                    organization: "Exempelköpings Universitet",
                    department: "IKE",
                    organizationID: "org-uni",
                    unitID: "ike"
                ),
                PublicationAuthorEmployment(id: "emp-free", from: "2010-01-01", organization: "Region Stockholm", department: "Akuten"),
            ],
            educationEntries: [
                PublicationAuthorEducation(id: "edu-org", organization: "Exempelköping univ.", organizationID: "org-uni"),
                PublicationAuthorEducation(id: "edu-free", organization: "Uppsala universitet"),
            ]
        )
    }

    @MainActor
    private func makeStore(
        organizations: [OrganizationRecord] = [Round7OrganizationNamesTests.uni, Round7OrganizationNamesTests.region],
        authors: [PublicationAuthor] = [Round7OrganizationNamesTests.author],
        metadata: DataSourceMetadata = .bundledDefault,
        reviews: [CVReviewEntry] = []
    ) -> GrantDataStore {
        var metadata = metadata
        metadata.interfaceLanguage = "sv"
        return GrantDataStore(
            metadata: metadata,
            organizations: organizations,
            cvReviewEntries: reviews,
            publicationAuthors: authors,
            skipInitialMigration: true
        )
    }

    // MARK: 1. One correct spelling

    func testLinkedRowsGetTheOfficialNamesAndUnlinkedRowsAreKept() throws {
        let result = OrganizationTree.applyingOfficialNames(
            to: [Self.author],
            organizations: [Self.uni, Self.region]
        )
        let author = try XCTUnwrap(result.authors.first)

        let withUnit = try XCTUnwrap(author.affiliations.first { $0.id == "aff-unit" })
        XCTAssertEqual(withUnit.organizationSv, "Exempelköpings universitet")
        XCTAssertEqual(withUnit.organizationEn, "Exempelköping University")
        XCTAssertEqual(withUnit.departmentSv, "Institutionen för exempelmedicin och vård")
        XCTAssertEqual(
            withUnit.departmentEn,
            "Department of Example Medicine, and Caring Sciences",
            "English is the publication address name when the unit has one"
        )

        let organizationOnly = try XCTUnwrap(author.affiliations.first { $0.id == "aff-org" })
        XCTAssertEqual(organizationOnly.organizationSv, "Exempelköpings universitet")
        XCTAssertEqual(organizationOnly.departmentSv, "Min egen avdelning", "no unit: the department text is kept")

        let free = try XCTUnwrap(author.affiliations.first { $0.id == "aff-free" })
        XCTAssertEqual(free, Self.author.affiliations.first { $0.id == "aff-free" }, "a row without a link is untouched")
        let missing = try XCTUnwrap(author.affiliations.first { $0.id == "aff-missing" })
        XCTAssertEqual(missing, Self.author.affiliations.first { $0.id == "aff-missing" }, "a link to a missing organization is untouched")

        let employment = try XCTUnwrap(author.employments.first { $0.id == "emp-unit" })
        XCTAssertEqual(employment.organizationSv, "Exempelköpings universitet")
        XCTAssertEqual(employment.departmentSv, "Institutionen för kliniska exempelvetenskaper")
        XCTAssertEqual(employment.departmentEn, "Department of Clinical Example Sciences", "no address name: the English name")
        XCTAssertEqual(author.employments.first { $0.id == "emp-free" }, Self.author.employments.first { $0.id == "emp-free" })

        let education = try XCTUnwrap(author.educationEntries.first { $0.id == "edu-org" })
        XCTAssertEqual(education.organizationSv, "Exempelköpings universitet")
        XCTAssertEqual(education.organizationEn, "Exempelköping University")
        XCTAssertEqual(author.educationEntries.first { $0.id == "edu-free" }, Self.author.educationEntries.first { $0.id == "edu-free" })

        XCTAssertEqual(result.report, OfficialOrganizationNameReport(affiliations: 2, employments: 1, educationEntries: 1))
        XCTAssertEqual(author.affiliations.count, Self.author.affiliations.count)
        XCTAssertEqual(author.employments.count, Self.author.employments.count)
        XCTAssertEqual(author.educationEntries.count, Self.author.educationEntries.count)
    }

    func testRewriteIsIdempotent() {
        let first = OrganizationTree.applyingOfficialNames(to: [Self.author], organizations: [Self.uni, Self.region])
        XCTAssertFalse(first.report.isEmpty)
        let second = OrganizationTree.applyingOfficialNames(to: first.authors, organizations: [Self.uni, Self.region])
        XCTAssertTrue(second.report.isEmpty, "running it again changes nothing")
        XCTAssertEqual(second.authors, first.authors)
    }

    @MainActor
    func testStoreRewriteChangesOnlyLinkedRowsAndSecondRunChangesNothing() {
        let store = makeStore()
        let report = store.applyOfficialOrganizationNamesToResearcherRows()
        XCTAssertEqual(report.total, 4)
        XCTAssertEqual(store.publicationAuthors.count, 1)
        XCTAssertTrue(store.applyOfficialOrganizationNamesToResearcherRows().isEmpty)
    }

    @MainActor
    func testRenamedUnitIsWrittenIntoLinkedRowsAndCanBeUndone() throws {
        let store = makeStore()
        store.applyOfficialOrganizationNamesToResearcherRows()
        let authorsBefore = store.publicationAuthors

        var unit = try XCTUnwrap(store.organizations.first { $0.id == "org-uni" }?.unit(withID: "iem"))
        unit.nameSv = "Institutionen för exempelmedicin och omvårdnad"
        unit.setEditableEnglishName("Department of Example Medicine and Nursing")
        XCTAssertTrue(store.updateOrganizationUnit(organizationID: "org-uni", unit: unit))

        let row = try XCTUnwrap(store.publicationAuthors.first?.affiliations.first { $0.id == "aff-unit" })
        XCTAssertEqual(row.departmentSv, "Institutionen för exempelmedicin och omvårdnad")
        XCTAssertEqual(row.departmentEn, "Department of Example Medicine and Nursing")
        let otherRow = try XCTUnwrap(store.publicationAuthors.first?.employments.first { $0.id == "emp-unit" })
        XCTAssertEqual(otherRow.departmentSv, "Institutionen för kliniska exempelvetenskaper", "rows of another unit are unchanged")

        store.undoManager.undo()
        XCTAssertEqual(store.publicationAuthors, authorsBefore, "undo also restores the researcher rows")
    }

    @MainActor
    func testRenamedOrganizationIsWrittenIntoLinkedRows() throws {
        let store = makeStore()
        store.applyOfficialOrganizationNamesToResearcherRows()
        let organization = try XCTUnwrap(store.organizations.first { $0.id == "org-uni" })

        store.updateOrganization(
            id: organization.id,
            nameSv: "Exempelköpings universitet (EXU)",
            nameEn: "Exempelköping University (EXU)",
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

        let renamed = try XCTUnwrap(store.organizations.first { $0.id == "org-uni" })
        let author = try XCTUnwrap(store.publicationAuthors.first)
        for affiliation in author.affiliations where affiliation.organizationID == "org-uni" {
            XCTAssertEqual(affiliation.organizationSv, renamed.nameSv, affiliation.id)
            XCTAssertEqual(affiliation.organizationEn, renamed.nameEn, affiliation.id)
        }
        XCTAssertEqual(author.educationEntries.first { $0.id == "edu-org" }?.organizationSv, renamed.nameSv)
        XCTAssertEqual(author.affiliations.first { $0.id == "aff-free" }?.organizationSv, "Karolinska Institutet")
        XCTAssertEqual(author.affiliations.count, Self.author.affiliations.count)
    }

    // MARK: 2. Reviews are left as they are

    /// The one-time correction of a single review was removed (user
    /// decision): the round 7 migrations leave every review exactly as it is
    /// stored, and the migration log gets no review entry.
    @MainActor
    func testRound7MigrationsLeaveReviewsUntouched() throws {
        let review = CVReviewEntry(id: "r1", category: .journalReview, date: "2025-06-22", reference: "Exempel 1")
        let store = makeStore(reviews: [review])
        let before = store.cvReviewEntries
        XCTAssertEqual(before.count, 1)
        store.runRound7OneTimeDataMigrations()
        XCTAssertEqual(store.cvReviewEntries, before)
        XCTAssertFalse((store.metadata.migrationLog ?? []).contains { $0.key.contains("review") })
    }

    // MARK: 4. Salary source colours

    func testSalaryColorMigrationKeepsTodaysColorsAndNames() throws {
        let sources = [
            SalarySource(id: "clinic", category: .clinic, project: "Exempelhälsan Centrum", projectSv: "Exempelhälsan Centrum"),
            SalarySource(id: "uni", category: .teaching, project: "Example University", projectEn: "Example University"),
            SalarySource(id: "research", category: .research, project: "EXEMPELSTUDIEN"),
            SalarySource(id: "leave", category: .other, project: "Tjänstledighet", projectSv: "Tjänstledighet", projectEn: "On leave"),
            SalarySource(id: "teaching", category: .teaching, project: "Kurs"),
            SalarySource(id: "other", category: .other, project: "Annat"),
            SalarySource(id: "chosen", category: .research, project: "Exempelköpings universitet", color: .blue),
        ]
        let migrated = SalarySource.migratedForStoredColorsAndNames(sources)
        func source(_ id: String) throws -> SalarySource { try XCTUnwrap(migrated.first { $0.id == id }) }

        // The colour each source had before round 7.
        XCTAssertEqual(salaryCalendarColorTarget(for: try source("clinic")), .clinicMeetingCategory)
        XCTAssertEqual(try source("uni").effectiveColor, .blue, "no organization name decides the colour; the category's colour is stored")
        XCTAssertEqual(salaryCalendarColorTarget(for: try source("research")), .activity3)
        XCTAssertNil(salaryCalendarColorTarget(for: try source("leave")))
        XCTAssertEqual(try source("leave").effectiveColor, .red)
        XCTAssertEqual(try source("teaching").effectiveColor, .blue)
        XCTAssertEqual(try source("other").effectiveColor, .red)
        XCTAssertEqual(try source("chosen").effectiveColor, .blue, "a chosen colour is kept")

        // The built-in names are now stored on the source.
        XCTAssertNil(try source("uni").projectSv, "no organization name is built in")
        XCTAssertEqual(try source("uni").projectEn, "Example University")
        XCTAssertEqual(try source("leave").projectEn, "On leave")
        XCTAssertNil(try source("research").projectSv)

        XCTAssertTrue(migrated.allSatisfy { $0.color != nil })
        XCTAssertEqual(migrated.count, sources.count)
        XCTAssertEqual(SalarySource.migratedForStoredColorsAndNames(migrated), migrated, "running it again changes nothing")
    }

    func testSalaryColorDecodesFromOldDataAndUnknownValue() throws {
        let old = #"{"id":"s1","category":"Klinik","project":"Klinik A"}"#
        let decodedOld = try JSONDecoder().decode(SalarySource.self, from: Data(old.utf8))
        XCTAssertNil(decodedOld.color)
        XCTAssertEqual(decodedOld.effectiveColor, .clinicCalendarCategory)

        let unknown = #"{"id":"s2","category":"Forskning","project":"P","color":"purple"}"#
        let decodedUnknown = try JSONDecoder().decode(SalarySource.self, from: Data(unknown.utf8))
        XCTAssertEqual(decodedUnknown.effectiveColor, .calendarActivity3, "an unknown colour falls back to the category's colour")
    }

    @MainActor
    func testStoreSalaryMigrationRunsOnce() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.salarySources = [
            SalarySource(id: "uni", category: .teaching, project: "Example University", projectEn: "Example University"),
        ]
        let store = makeStore(metadata: metadata)
        XCTAssertTrue(store.runRound7OneTimeDataMigrations())
        let source = try XCTUnwrap(store.salarySources.first)
        XCTAssertEqual(source.effectiveColor, .blue)
        XCTAssertNotNil(source.color, "the colour is stored")
        XCTAssertEqual(source.projectEn, "Example University")
        XCTAssertEqual(store.salarySources.count, 1)
        XCTAssertFalse(store.runRound7OneTimeDataMigrations())
    }
}
