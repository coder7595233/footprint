import XCTest
@testable import Footprint

/// "Alla kopplingar via id": every place that decides "which record does this
/// row point to?" uses the stored id first and the written name only for rows
/// without an id. The records below keep an old name as their text on
/// purpose; the id still points to the right record, so every list, panel and
/// label must still find it. The rename tests go through the real save paths.
final class IDLinkTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IDLinkTests-\(UUID().uuidString)", isDirectory: true)
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

    private func application(
        id: String,
        organizationID: String? = nil,
        organization: String,
        projectID: String? = nil,
        projectType: String? = nil,
        granted: Bool = false
    ) -> GrantApplication {
        var application = GrantApplication(
            id: id,
            rowNumber: 1,
            organizationID: organizationID,
            organization: organization,
            grantName: "Projektbidrag",
            projectID: projectID,
            projectType: projectType
        )
        if granted {
            application.appliedOn = "2024-09-01"
            application.grantedOn = "2025-01-10"
            application.grantedAmount = "100000"
        }
        return application
    }

    @MainActor
    private func organizationFields(_ organization: OrganizationRecord, renamedTo nameSv: String, _ store: GrantDataStore) {
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

    // MARK: - Organizations

    @MainActor
    func testOrganizationPageFindsApplicationsByIDWhenTheTextIsOld() {
        let renamed = OrganizationRecord(id: "org-1", nameSv: "Nya Fonden", nameEn: "New Fund", roles: [.grantProvider])
        let other = OrganizationRecord(id: "org-2", nameSv: "Gamla Fonden", nameEn: "Old Fund", roles: [.grantProvider])
        // Points to org-1 but still says the name org-2 has today.
        let linked = application(id: "a1", organizationID: "org-1", organization: "Gamla Fonden")
        let unlinked = application(id: "a2", organization: "Gamla Fonden")
        let store = GrantDataStore(
            applications: [linked, unlinked],
            organizations: [renamed, other],
            skipInitialMigration: true
        )

        XCTAssertEqual(store.applications(forOrganization: renamed).map(\.id), ["a1"], "the link decides, not the text")
        XCTAssertEqual(store.applications(forOrganization: other).map(\.id), ["a2"], "a row without a link is still matched by name")
        XCTAssertEqual(store.organizationLabel(for: linked, language: .swedish), "Nya Fonden")
        XCTAssertEqual(store.organizationLabel(for: linked, language: .english), "New Fund")
        XCTAssertEqual(store.funderName(for: linked), "Nya Fonden")
        XCTAssertEqual(store.linkedFunder(of: linked)?.id, "org-1")
        XCTAssertEqual(store.organizations.count, 2, "an old written name must not become an organization of its own")
    }

    @MainActor
    func testRenamingAnOrganizationKeepsEveryLinkAndPanel() {
        let organization = OrganizationRecord(id: "org-1", nameSv: "Diabetesfonden", nameEn: "Diabetesfonden", roles: [.grantProvider, .institution])
        let grant = application(id: "a1", organizationID: "org-1", organization: "Diabetesfonden")
        let review = CVReviewEntry(id: "r1", category: .grantProposalReview, organizationName: "Diabetesfonden")
        let course = TeachingCourse(id: "c1", name: "Kurs", institutionID: "org-1", institution: "Diabetesfonden")
        let candidate = DoctoralCandidateRecord(id: "d1", candidateName: "Doktorand", institutionID: "org-1", institution: "Diabetesfonden")
        let store = GrantDataStore(
            applications: [grant],
            organizations: [organization],
            teachingCourses: [course],
            doctoralCandidates: [candidate],
            cvReviewEntries: [review],
            skipInitialMigration: true
        )
        store.migrateNameReferencesToIDsForF13()
        XCTAssertEqual(store.cvReviewEntries.first?.organizationID, "org-1", "the review gets the organization's id")

        organizationFields(organization, renamedTo: "Svenska Diabetesfonden", store)

        let renamed = store.organization(id: "org-1")
        XCTAssertEqual(renamed?.nameSv, "Svenska Diabetesfonden")
        guard let renamed else { return }
        XCTAssertEqual(store.applications(forOrganization: renamed).map(\.id), ["a1"])
        XCTAssertEqual(store.applications.first?.organization, "Svenska Diabetesfonden")
        XCTAssertEqual(store.cvReviewEntries.first?.organizationID, "org-1")
        XCTAssertEqual(store.cvReviewEntries.first?.organizationName, "Svenska Diabetesfonden")
        XCTAssertEqual(store.linkedOrganization(of: store.cvReviewEntries[0])?.id, "org-1")
        XCTAssertEqual(store.doctoralCandidates.first?.institution, "Svenska Diabetesfonden")
        XCTAssertEqual(store.doctoralCandidates.first?.institutionID, "org-1")
        XCTAssertEqual(store.teachingInstitutionKey(for: store.teachingCourses[0]), "Svenska Diabetesfonden")
        XCTAssertEqual(store.organizationLabel(for: store.teachingCourses[0], language: .swedish), "Svenska Diabetesfonden")
    }

    @MainActor
    func testTeachingAndDoctoralInstitutionsAreReadByID() {
        let organization = OrganizationRecord(id: "org-1", nameSv: "Exempelköpings universitet", nameEn: "Exempelköping University")
        let course = TeachingCourse(id: "c1", name: "Kurs", institutionID: "org-1", institution: "Gammalt namn")
        let component = TeachingComponent(id: "m1", name: "Moment", institution: "Gammalt namn")
        let candidate = DoctoralCandidateRecord(id: "d1", candidateName: "Doktorand", institutionID: "org-1", institution: "Gammalt namn")
        let store = GrantDataStore(
            organizations: [organization],
            teachingCourses: [course],
            teachingComponents: [component],
            doctoralCandidates: [candidate],
            skipInitialMigration: true
        )
        XCTAssertEqual(store.teachingInstitutionKey(for: course), "Exempelköpings universitet")
        XCTAssertEqual(store.organizationLabel(for: course, language: .english), "Exempelköping University")
        XCTAssertEqual(store.organizationLabel(for: candidate, language: .swedish), "Exempelköpings universitet")
        XCTAssertEqual(store.teachingInstitutionKey(for: component), "Gammalt namn", "a moment without a link keeps its text")
    }

    @MainActor
    func testReviewOrganizationIsOnlyLinkedWhenTheNameIsUnambiguous() {
        // Two organizations share the English name.
        let first = OrganizationRecord(id: "org-1", nameSv: "Stiftelsen A", nameEn: "The Foundation")
        let second = OrganizationRecord(id: "org-2", nameSv: "Stiftelsen B", nameEn: "The Foundation")
        let unique = OrganizationRecord(id: "org-3", nameSv: "Hjärt-Lungfonden", nameEn: "Heart-Lung Foundation")
        let ambiguous = CVReviewEntry(id: "r1", category: .grantProposalReview, organizationName: "The Foundation")
        let clear = CVReviewEntry(id: "r2", category: .otherExpertAssignment, organizationName: "heart-lung foundation")
        let unknown = CVReviewEntry(id: "r3", category: .grantProposalReview, organizationName: "Någon annan")
        let store = GrantDataStore(
            organizations: [first, second, unique],
            cvReviewEntries: [ambiguous, clear, unknown],
            skipInitialMigration: true
        )
        store.migrateNameReferencesToIDsForF13()

        XCTAssertNil(store.cvReviewEntries.first { $0.id == "r1" }?.organizationID, "two organizations share the name")
        XCTAssertEqual(store.cvReviewEntries.first { $0.id == "r2" }?.organizationID, "org-3")
        XCTAssertEqual(store.cvReviewEntries.first { $0.id == "r2" }?.organizationName, "heart-lung foundation", "the written text is kept")
        XCTAssertNil(store.cvReviewEntries.first { $0.id == "r3" }?.organizationID)
        XCTAssertEqual(store.cvReviewEntries.count, 3)
        XCTAssertTrue(store.migrateNameReferencesToIDsForF13().isEmpty, "running it again changes nothing")
    }

    @MainActor
    func testDeletingAnOrganizationClearsRowsThatPointToIt() {
        let organization = OrganizationRecord(id: "org-1", nameSv: "Region Test", nameEn: "Region Test")
        var author = PublicationAuthor(id: "au-1", name: "Anna Lind", firstName: "Anna", lastName: "Lind")
        author.affiliations = [
            PublicationAffiliation(id: "aff-1", organization: "Annan text", isPrimary: true, organizationID: "org-1", unitID: "u1")
        ]
        var review = CVReviewEntry(id: "r1", category: .grantProposalReview, organizationName: "Region Test")
        review.organizationID = "org-1"
        let store = GrantDataStore(
            organizations: [organization],
            cvReviewEntries: [review],
            publicationAuthors: [author],
            skipInitialMigration: true
        )
        store.deleteOrganization(id: "org-1")
        store.confirmDeletionImpactWarning()

        XCTAssertFalse(store.organizations.contains { $0.id == "org-1" })
        let affiliation = store.publicationAuthors.first?.affiliations.first
        XCTAssertNil(affiliation?.organizationID, "the link to the deleted organization is gone")
        XCTAssertNil(affiliation?.unitID)
        XCTAssertEqual(affiliation?.organization, "Annan text", "the row's text is kept")
        XCTAssertNil(store.cvReviewEntries.first?.organizationID)
        XCTAssertEqual(store.cvReviewEntries.first?.organizationName, "Region Test", "the review's text is kept")
    }

    // MARK: - Projects

    @MainActor
    func testProjectPageFindsRecordsByIDWhenTheTextIsOld() {
        let project = ProjectRecord(id: "p1", nameSv: "Nytt namn", nameEn: "New name")
        let other = ProjectRecord(id: "p2", nameSv: "Annat projekt", nameEn: "Other project")
        let grant = application(id: "a1", organization: "Fonden", projectID: "p1", projectType: "Gammalt namn", granted: true)
        // Points to p1 although its text names p2.
        let misleading = application(id: "a2", organization: "Fonden", projectID: "p1", projectType: "Annat projekt")
        let publication = PublicationRecord(id: "pub-1", projectID: "p1", projectName: "Gammalt namn", title: "Artikel")
        var contribution = CVConferenceContribution(id: "cc-1", title: "Poster", projectName: "Gammalt namn")
        contribution.projectID = "p1"
        let store = GrantDataStore(
            applications: [grant, misleading],
            projects: [project, other],
            cvConferenceContributions: [contribution],
            publicationRecords: [publication],
            skipInitialMigration: true
        )

        XCTAssertEqual(Set(store.applications(forProjectName: "Nytt namn").map(\.id)), ["a1", "a2"])
        XCTAssertTrue(store.applications(forProjectName: "Annat projekt").isEmpty, "the text does not move an application that has a link")
        XCTAssertEqual(store.publications(forProjectName: "Nytt namn").map(\.id), ["pub-1"])
        XCTAssertEqual(store.projectApplicationCount(forProjectName: "Nytt namn"), 2)
        XCTAssertEqual(store.grantedApplications(for: publication).map(\.id), ["a1"])
        XCTAssertTrue(store.contributionBelongs(contribution, to: project))
        XCTAssertEqual(store.projectLabel(for: grant, language: .english), "New name")
        XCTAssertEqual(store.projectLabel(for: publication, language: .swedish), "Nytt namn")
    }

    @MainActor
    func testContributionKeepsItsProjectLinkAndMovesOnlyWhenAnotherProjectIsNamed() {
        let project = ProjectRecord(id: "p1", nameSv: "Nytt namn", nameEn: "New name")
        let other = ProjectRecord(id: "p2", nameSv: "Annat projekt", nameEn: "Other project")
        var stale = CVConferenceContribution(id: "cc-1", title: "Poster", projectName: "Gammalt namn")
        stale.projectID = "p1"
        var picked = CVConferenceContribution(id: "cc-2", title: "Föredrag", projectName: "Annat projekt")
        picked.projectID = "p1"
        let store = GrantDataStore(
            projects: [project, other],
            cvConferenceContributions: [stale, picked],
            skipInitialMigration: true
        )
        store.migrateNameReferencesToIDsForF13()

        let savedStale = store.cvConferenceContributions.first { $0.id == "cc-1" }
        XCTAssertEqual(savedStale?.projectID, "p1", "an old name never removes the link")
        XCTAssertEqual(savedStale?.projectNameSv, "Nytt namn")
        let savedPicked = store.cvConferenceContributions.first { $0.id == "cc-2" }
        XCTAssertEqual(savedPicked?.projectID, "p2", "a name that clearly names another project moves the link")
    }

    @MainActor
    func testRenamingAProjectKeepsEveryLink() {
        let project = ProjectRecord(id: "p1", nameSv: "Projektet", nameEn: "The project")
        let grant = application(id: "a1", organization: "Fonden", projectID: "p1", projectType: "Projektet", granted: true)
        let publication = PublicationRecord(id: "pub-1", projectID: "p1", projectName: "Projektet", title: "Artikel")
        var contribution = CVConferenceContribution(id: "cc-1", title: "Poster", projectName: "Projektet")
        contribution.projectID = "p1"
        let store = GrantDataStore(
            applications: [grant],
            projects: [project],
            cvConferenceContributions: [contribution],
            publicationRecords: [publication],
            skipInitialMigration: true
        )

        var renamed = project
        renamed.nameSv = "Projektet 2.0"
        renamed.nameEn = "The project 2.0"
        store.autosaveProjectRecord(renamed, previousID: "p1")

        guard let renamedProject = store.project(id: "p1") else {
            return XCTFail("the project is gone")
        }
        XCTAssertEqual(renamedProject.nameSv, "Projektet 2.0")
        XCTAssertEqual(store.applications(forProjectName: "Projektet 2.0").map(\.id), ["a1"])
        XCTAssertEqual(store.applications.first?.projectID, "p1")
        XCTAssertTrue(store.applicationBelongs(store.applications[0], to: renamedProject))
        XCTAssertEqual(store.publicationRecords.first?.projectID, "p1")
        XCTAssertTrue(store.publicationBelongs(store.publicationRecords[0], to: renamedProject))
        XCTAssertEqual(store.cvConferenceContributions.first?.projectID, "p1")
        XCTAssertTrue(store.contributionBelongs(store.cvConferenceContributions[0], to: renamedProject))
        XCTAssertEqual(store.projectLabel(for: store.publicationRecords[0], language: .english), "The project 2.0")
    }

    // MARK: - Journals

    @MainActor
    func testPublicationKeepsItsJournalLinkWhenItsTextIsOld() {
        let journal = PublicationJournal(id: "j1", name: "Ny tidskrift")
        let publication = PublicationRecord(id: "pub-1", title: "Artikel", journal: "Gammal tidskrift", journalID: "j1")
        var review = CVReviewEntry(id: "r1", category: .journalReview, journalName: "Gammal tidskrift")
        review.journalID = "j1"
        let store = GrantDataStore(
            cvReviewEntries: [review],
            publicationJournals: [journal],
            publicationRecords: [publication],
            skipInitialMigration: true
        )
        XCTAssertEqual(store.linkedJournal(of: publication)?.id, "j1")
        XCTAssertEqual(store.linkedJournal(ofSubmissionJournalName: "Gammal tidskrift", in: publication)?.id, "j1")

        store.migrateNameReferencesToIDsForF13()

        XCTAssertEqual(store.publicationRecords.first?.journalID, "j1", "an old name never removes the link")
        XCTAssertEqual(store.cvReviewEntries.first?.journalID, "j1")
        XCTAssertEqual(store.cvReviewEntries.first?.journalName, "Ny tidskrift")
    }

    @MainActor
    func testRenamingAJournalKeepsTheJournalPage() {
        let journal = PublicationJournal(id: "j1", name: "Old Journal")
        let publication = PublicationRecord(
            id: "pub-1",
            title: "Artikel",
            journal: "Old Journal",
            journalID: "j1",
            status: PublicationStatus.submitted.rawValue,
            statusTimeline: [PublicationStatusEntry(status: PublicationStatus.submitted.rawValue, journal: "Old Journal", date: "2025-03-01")]
        )
        let store = GrantDataStore(
            publicationJournals: [journal],
            publicationRecords: [publication],
            skipInitialMigration: true
        )

        var renamed = journal
        renamed.name = "New Journal"
        store.savePublicationJournal(renamed, previousName: "Old Journal")

        let saved = store.publicationRecords[0]
        XCTAssertEqual(saved.journalID, "j1")
        XCTAssertEqual(saved.journal, "New Journal")
        XCTAssertEqual(saved.statusTimeline.first?.journal, "New Journal", "the dated steps follow the rename")
        XCTAssertEqual(store.linkedJournal(of: saved)?.id, "j1")
        XCTAssertEqual(store.linkedJournal(ofSubmissionJournalName: "New Journal", in: saved)?.id, "j1")
    }

    // MARK: - Researchers

    @MainActor
    func testRenamingAResearcherKeepsTheirPublications() {
        let author = PublicationAuthor(id: "au-1", name: "Anna Andersson", firstName: "Anna", lastName: "Andersson")
        let publication = PublicationRecord(
            id: "pub-1",
            title: "Artikel",
            authorNames: ["Anna Andersson"],
            authorIDs: ["au-1"]
        )
        let store = GrantDataStore(
            publicationAuthors: [author],
            publicationRecords: [publication],
            skipInitialMigration: true
        )
        XCTAssertEqual(store.publications(forAuthorID: "au-1").map(\.id), ["pub-1"])

        var renamed = author
        renamed.name = "Anna Lind"
        renamed.lastName = "Lind"
        store.savePublicationAuthor(renamed, previousName: "Anna Andersson")

        XCTAssertEqual(store.publicationAuthors.first { $0.id == "au-1" }?.name, "Anna Lind")
        XCTAssertEqual(store.publicationRecords.first?.authorIDs, ["au-1"], "the link to the researcher is kept")
    }

    @MainActor
    func testAPublicationIsFoundByItsAuthorIDEvenWhenTheNameMatchesNobody() {
        let author = PublicationAuthor(id: "au-1", name: "Anna Lind", firstName: "Anna", lastName: "Lind")
        // The record still says an old name that is no longer one of hers.
        let publication = PublicationRecord(id: "pub-1", title: "Artikel", authorNames: ["A. Andersson"], authorIDs: ["au-1"])
        let store = GrantDataStore(
            publicationAuthors: [author],
            publicationRecords: [publication],
            skipInitialMigration: true
        )
        XCTAssertEqual(store.publications(forAuthorID: "au-1").map(\.id), ["pub-1"])
    }

    // MARK: - Stored data

    func testReviewOrganizationIDSurvivesEncodingAndOlderDataDecodes() throws {
        var review = CVReviewEntry(id: "r1", category: .grantProposalReview, organizationName: "Fonden")
        review.organizationID = "org-1"
        let decoded = try JSONDecoder().decode(CVReviewEntry.self, from: JSONEncoder().encode(review))
        XCTAssertEqual(decoded.organizationID, "org-1")
        XCTAssertEqual(decoded.organizationName, "Fonden")

        let older = #"{"id":"r2","categoryRaw":"grantProposalReview","organizationName":"Fonden"}"#
        let olderReview = try JSONDecoder().decode(CVReviewEntry.self, from: Data(older.utf8))
        XCTAssertNil(olderReview.organizationID)
        XCTAssertEqual(olderReview.organizationName, "Fonden")
    }

    @MainActor
    func testTheGenericRuleLetsTheIDDecide() {
        let rows: [(id: String, names: [String])] = [(id: "1", names: ["Ett"]), (id: "2", names: ["Två"])]
        func run(id: String?, name: String?) -> String? {
            GrantDataStore.idFirstLinkedRecord(
                id: id,
                name: name,
                byID: { wanted in rows.first { $0.id == wanted } },
                byName: { wanted in rows.first { $0.names.contains(wanted) } },
                recordID: { $0.id },
                recordNames: { $0.names }
            )?.id
        }
        XCTAssertEqual(run(id: "1", name: "Ett"), "1")
        XCTAssertEqual(run(id: "1", name: "Gammalt namn"), "1", "a name that names nothing keeps the link")
        XCTAssertEqual(run(id: "1", name: "Två"), "2", "a name that names another record moves the link")
        XCTAssertNil(run(id: "1", name: ""), "an empty name clears the link")
        XCTAssertEqual(run(id: nil, name: "Två"), "2", "without a link the name decides")
        XCTAssertEqual(run(id: "saknas", name: "Ett"), "1", "a link to nothing falls back to the name")
    }
}
