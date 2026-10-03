import XCTest
@testable import Footprint

/// The web searches offered next to a missing field in the Data view. All
/// names below are invented.
final class DataQualitySearchQueryTests: XCTestCase {
    private func person(
        firstName: String = "Anna",
        lastName: String = "Exempel",
        organization: String = ""
    ) -> DataQualitySearchSubject {
        DataQualitySearchSubject(
            kind: .person,
            firstName: firstName,
            lastName: lastName,
            name: "\(firstName) \(lastName)",
            organization: organization
        )
    }

    func testPlainNameIsOneExactPhrase() {
        XCTAssertEqual(
            DataQualitySearchQuery.personTerm(firstName: "Anna", lastName: "Exempel"),
            "\"Anna Exempel\""
        )
    }

    func testMiddleInitialSearchesBothForms() {
        XCTAssertEqual(
            DataQualitySearchQuery.personTerm(firstName: "Anna B.", lastName: "Exempel"),
            "(\"Anna Exempel\" OR \"Anna B. Exempel\")"
        )
    }

    func testWrittenOutMiddleNameAlsoSearchesTheInitialForm() {
        XCTAssertEqual(
            DataQualitySearchQuery.personTerm(firstName: "Anna Britt", lastName: "Exempel"),
            "(\"Anna Exempel\" OR \"Anna B. Exempel\" OR \"Anna Britt Exempel\")"
        )
    }

    func testNameWithoutSplitFieldsUsesTheFullName() {
        XCTAssertEqual(
            DataQualitySearchQuery.personTerm(firstName: "", lastName: "", fullName: "Bertil Påhittad"),
            "\"Bertil Påhittad\""
        )
    }

    func testQuoteMarksInsideNamesAreRemoved() {
        XCTAssertEqual(
            DataQualitySearchQuery.personTerm(firstName: "Anna \"Ann\"", lastName: "Exempel"),
            "(\"Anna Exempel\" OR \"Anna A. Exempel\" OR \"Anna Ann Exempel\")"
        )
    }

    func testPositionQueryNamesTheOrganizationAndTitles() {
        let query = DataQualitySearchQuery.googleQuery(
            field: .researcherPosition,
            fieldLabel: "Position",
            subject: person(organization: "Exempeluniversitetet")
        )
        XCTAssertEqual(
            query,
            "\"Anna Exempel\" \"Exempeluniversitetet\" (professor OR docent OR lektor OR postdoc OR forskare OR \"associate professor\" OR researcher)"
        )
    }

    func testUnknownOrganizationIsLeftOut() {
        let query = DataQualitySearchQuery.googleQuery(
            field: .researcherTitle,
            fieldLabel: "Titel",
            subject: person(organization: "  ")
        )
        XCTAssertEqual(
            query,
            "\"Anna Exempel\" (professor OR docent OR lektor OR postdoc OR forskare OR \"associate professor\" OR researcher)"
        )
        XCTAssertFalse(query?.contains("\"\"") ?? true)
    }

    func testDegreeAndContactQueries() {
        XCTAssertEqual(
            DataQualitySearchQuery.googleQuery(field: .researcherDegree, fieldLabel: "Examen", subject: person()),
            "\"Anna Exempel\" (examen OR utbildning OR degree OR education OR MD OR PhD OR MSc)"
        )
        XCTAssertEqual(
            DataQualitySearchQuery.googleQuery(
                field: .researcherPrimaryEmail,
                fieldLabel: "Primär e-post",
                subject: person(organization: "Exempelsjukhuset")
            ),
            "\"Anna Exempel\" \"Exempelsjukhuset\" (e-post OR email OR kontakt OR contact)"
        )
    }

    func testQueriesNeverUseAND() {
        let subjects = [
            person(organization: "Exempeluniversitetet"),
            DataQualitySearchSubject(kind: .publication, name: "A made-up trial of invented things"),
            DataQualitySearchSubject(kind: .organization, name: "Påhittade stiftelsen"),
            DataQualitySearchSubject(kind: .journal, name: "Journal of Invented Results"),
        ]
        for subject in subjects {
            for key in DataQualityFieldKey.allCases {
                let query = DataQualitySearchQuery.googleQuery(field: key, fieldLabel: "Fält", subject: subject) ?? ""
                XCTAssertFalse(query.split(separator: " ").contains("AND"), query)
            }
        }
    }

    func testORCIDGetsItsOwnSearch() {
        let links = DataQualitySearchQuery.links(
            field: .researcherORCID,
            fieldLabel: "ORCID",
            subject: person(firstName: "Anna B.")
        )
        XCTAssertEqual(links.map(\.kind), [.google, .orcid])
        XCTAssertEqual(links[0].query, "(\"Anna Exempel\" OR \"Anna B. Exempel\") orcid")
        XCTAssertEqual(
            links[1].url.absoluteString,
            "https://orcid.org/orcid-search/search?searchQuery=Anna%20Exempel"
        )
    }

    func testPublicationIdentifierSearchesPubMedAndCrossref() {
        let subject = DataQualitySearchSubject(kind: .publication, name: "A made-up trial of invented things")
        let links = DataQualitySearchQuery.links(field: .publicationDOIFormat, fieldLabel: "DOI", subject: subject)
        XCTAssertEqual(links.map(\.kind), [.google, .pubmed, .crossref])
        XCTAssertEqual(links[0].query, "\"A made-up trial of invented things\" doi")
        XCTAssertEqual(
            links[1].url.absoluteString,
            "https://pubmed.ncbi.nlm.nih.gov/?term=A%20made-up%20trial%20of%20invented%20things"
        )
        XCTAssertEqual(
            links[2].url.absoluteString,
            "https://search.crossref.org/search/works?q=A%20made-up%20trial%20of%20invented%20things&from_ui=yes"
        )
    }

    func testOtherFieldsGetOnlyGoogle() {
        let links = DataQualitySearchQuery.links(field: .researcherDegree, fieldLabel: "Examen", subject: person())
        XCTAssertEqual(links.map(\.kind), [.google])
    }

    func testSwedishLettersQuotesAndPlusAreEncoded() {
        let url = DataQualitySearchQuery.googleURL(query: "\"Åsa Öberg\" ä CD4+")
        let text = url?.absoluteString ?? ""
        XCTAssertTrue(text.hasPrefix("https://www.google.com/search?q="), text)
        XCTAssertTrue(text.contains("%22%C3%85sa%20%C3%96berg%22"), text)
        XCTAssertTrue(text.contains("%C3%A4"), text)
        XCTAssertTrue(text.contains("CD4%2B"), text)
        XCTAssertFalse(text.contains(" "), text)
    }

    func testLongTitlesStayWithinGooglesWordLimit() {
        let title = (1...40).map { "ord\($0)" }.joined(separator: " ")
        let subject = DataQualitySearchSubject(kind: .publication, name: title)
        let query = DataQualitySearchQuery.googleQuery(field: .publicationDOIFormat, fieldLabel: "DOI", subject: subject) ?? ""
        XCTAssertLessThanOrEqual(DataQualitySearchQuery.wordCount(query), DataQualitySearchQuery.googleWordLimit)
        XCTAssertTrue(query.hasPrefix("\"ord1 ord2"), query)
        XCTAssertTrue(query.hasSuffix(" doi"), query)
    }

    func testGenericFieldAddsItsLabel() {
        let subject = DataQualitySearchSubject(kind: .organization, name: "Påhittade stiftelsen")
        XCTAssertEqual(
            DataQualitySearchQuery.googleQuery(field: nil, fieldLabel: "Kategori", subject: subject),
            "\"Påhittade stiftelsen\" Kategori"
        )
    }

    func testNothingToSearchWithGivesNoLinks() {
        let subject = DataQualitySearchSubject(kind: .journal, name: "   ")
        XCTAssertTrue(DataQualitySearchQuery.links(field: .journalISSN, fieldLabel: "ISSN", subject: subject).isEmpty)
    }

    @MainActor
    func testMissingFieldIssueKeepsTextsAndAddsKeys() {
        let issue = GrantDataStore.MissingFieldIssue(
            id: "author-x",
            entityKind: .researcher,
            recordID: "x",
            destination: .people,
            title: "Anna Exempel",
            subtitle: "",
            missingFields: ["ORCID", "Kön"],
            fieldKeys: ["ORCID": .researcherORCID]
        )
        XCTAssertEqual(issue.missingFields, ["ORCID", "Kön"])
        XCTAssertEqual(issue.fields.map(\.label), ["ORCID", "Kön"])
        XCTAssertEqual(issue.fields.map(\.key), [.researcherORCID, nil])
        XCTAssertEqual(issue.fields.map(\.hideKeyComponent), ["researcherORCID", "Kön"])
    }
}

/// Typing a missing field in the Data view and hiding single fields. All
/// names below are invented.
final class DataQualityFieldEditingTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataQualityFieldEditingTests-\(UUID().uuidString)", isDirectory: true)
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

    @MainActor
    private func makeStore() -> GrantDataStore {
        let author = PublicationAuthor(
            id: "author-1",
            name: "Anna Exempel",
            firstName: "Anna",
            lastName: "Exempel",
            affiliations: [PublicationAffiliation(organization: "Exempeluniversitetet", isPrimary: true)]
        )
        return GrantDataStore(publicationAuthors: [author], skipInitialMigration: true)
    }

    @MainActor
    private func authorIssue(_ store: GrantDataStore) throws -> GrantDataStore.MissingFieldIssue {
        try XCTUnwrap(store.missingFieldIssues(includeHidden: true).first { $0.recordID == "author-1" })
    }

    @MainActor
    func testResearcherFieldsHaveKeys() throws {
        let store = makeStore()
        let keys = Set(try authorIssue(store).fields.compactMap(\.key))
        XCTAssertTrue(keys.contains(.researcherORCID))
        XCTAssertTrue(keys.contains(.researcherPosition))
        XCTAssertTrue(keys.contains(.researcherPrimaryEmail))
        // The title is worked out from position, docent and PhD; it is not flagged.
        XCTAssertFalse(keys.contains(.researcherTitle))
    }

    @MainActor
    func testTypedORCIDIsSavedOnTheResearcher() throws {
        let store = makeStore()
        let issue = try authorIssue(store)
        let field = try XCTUnwrap(issue.fields.first { $0.key == .researcherORCID })
        XCTAssertEqual(store.dataQualityEditableField(for: issue, field: field)?.value, "")
        store.saveDataQualityField(issue, field: field, value: "  0000-0002-1825-0097  ")
        XCTAssertEqual(store.publicationAuthors.first?.orcid, "0000-0002-1825-0097")
    }

    @MainActor
    func testPositionAndDegreeAreOpenedAndEmailIsSaved() throws {
        let store = makeStore()
        let issue = try authorIssue(store)
        let position = try XCTUnwrap(issue.fields.first { $0.key == .researcherPosition })
        let degree = try XCTUnwrap(issue.fields.first { $0.key == .researcherDegree })
        let email = try XCTUnwrap(issue.fields.first { $0.key == .researcherPrimaryEmail })
        // Position and degree are chosen from the lists in the editor.
        XCTAssertNil(store.dataQualityEditableField(for: issue, field: position))
        XCTAssertNil(store.dataQualityEditableField(for: issue, field: degree))
        store.saveDataQualityField(issue, field: position, value: "Forskare")
        XCTAssertEqual(store.publicationAuthors.first?.position, "")
        store.saveDataQualityField(issue, field: email, value: "anna@example.org")
        XCTAssertEqual(store.publicationAuthors.first?.primaryAffiliation?.email, "anna@example.org")
    }

    @MainActor
    func testChosenPositionAndDegreeAreNotMissing() throws {
        let author = PublicationAuthor(
            id: "author-1",
            name: "Anna Exempel",
            firstName: "Anna",
            lastName: "Exempel",
            affiliations: [PublicationAffiliation(organization: "Exempeluniversitetet", isPrimary: true)],
            positionIDs: [ResearcherPositionOption.BuiltInID.researcher],
            degreeEntries: [ResearcherDegreeEntry(optionID: ResearcherDegreeOption.BuiltInID.medical)]
        )
        let store = GrantDataStore(publicationAuthors: [author], skipInitialMigration: true)
        let keys = Set(try authorIssue(store).fields.compactMap(\.key))
        XCTAssertFalse(keys.contains(.researcherPosition))
        XCTAssertFalse(keys.contains(.researcherDegree))
    }

    @MainActor
    func testEmptyBoxDoesNotChangeAMissingField() throws {
        let store = makeStore()
        let issue = try authorIssue(store)
        let field = try XCTUnwrap(issue.fields.first { $0.key == .researcherORCID })
        let before = store.publicationAuthors
        store.saveDataQualityField(issue, field: field, value: "   ")
        XCTAssertEqual(store.publicationAuthors, before)
    }

    @MainActor
    func testListFieldsAreOpenedInsteadOfTyped() throws {
        let store = makeStore()
        let issue = try authorIssue(store)
        let gender = try XCTUnwrap(issue.fields.first { $0.key == .researcherGender })
        XCTAssertNil(store.dataQualityEditableField(for: issue, field: gender))
    }

    @MainActor
    func testHidingEveryFieldHidesTheRecordAndShowAllBringsItBack() throws {
        let store = makeStore()
        let issue = try authorIssue(store)
        let first = try XCTUnwrap(issue.fields.first)
        XCTAssertTrue(store.hideDataQualityField(issue, field: first))
        XCTAssertTrue(store.isDataQualityFieldHidden(issue, field: first))
        XCTAssertFalse(store.isDataQualityWarningHidden(issue), "only the field is hidden")
        XCTAssertFalse(store.unhiddenDataQualityFields(of: issue).contains(first))
        XCTAssertTrue(store.missingFieldIssues().contains { $0.recordID == "author-1" })

        for field in issue.fields.dropFirst() {
            store.hideDataQualityField(issue, field: field)
        }
        XCTAssertFalse(store.missingFieldIssues().contains { $0.recordID == "author-1" })

        XCTAssertTrue(store.showAllHiddenDataQualityWarnings())
        XCTAssertFalse(store.isDataQualityFieldHidden(issue, field: first))
        XCTAssertTrue(store.missingFieldIssues().contains { $0.recordID == "author-1" })
    }
}
