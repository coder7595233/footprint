import XCTest
@testable import Footprint

/// Karriärsteg kan nu saknas (nil). Alla namn här är påhittade.
final class CareerStageOptionalTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CareerStageOptionalTests-\(UUID().uuidString)", isDirectory: true)
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

    private func decodeAuthor(careerStageJSON: String?, hasPhD: Bool = true) throws -> PublicationAuthor {
        var json = #"{"id":"author-x","firstName":"Testa","lastName":"Påhittad","hasPhD":\#(hasPhD)"#
        if let careerStageJSON {
            json += #","careerStage":\#(careerStageJSON)"#
        }
        json += "}"
        return try JSONDecoder().decode(PublicationAuthor.self, from: Data(json.utf8))
    }

    // MARK: - Avkodning

    func testStoredStagesAToDDecodeUnchanged() throws {
        XCTAssertEqual(try decodeAuthor(careerStageJSON: #""A""#).careerStage, .categoryA)
        XCTAssertEqual(try decodeAuthor(careerStageJSON: #""B""#).careerStage, .categoryB)
        XCTAssertEqual(try decodeAuthor(careerStageJSON: #""C""#).careerStage, .categoryC)
        XCTAssertEqual(try decodeAuthor(careerStageJSON: #""D""#).careerStage, .categoryD)
        XCTAssertEqual(try decodeAuthor(careerStageJSON: #""D""#, hasPhD: false).careerStage, .categoryD)
        XCTAssertEqual(try decodeAuthor(careerStageJSON: #""A""#, hasPhD: false).careerStage, .categoryA)
    }

    func testEmptyStoredStageDecodesAsNoStage() throws {
        XCTAssertNil(try decodeAuthor(careerStageJSON: #""""#).careerStage)
        XCTAssertNil(try decodeAuthor(careerStageJSON: #""   ""#).careerStage)
    }

    func testExplicitNullStageDecodesAsNoStage() throws {
        XCTAssertNil(try decodeAuthor(careerStageJSON: "null").careerStage)
    }

    /// Äldre data utan nyckeln får samma föreslagna steg som tidigare, så att
    /// befintlig data inte ändras.
    func testMissingStageKeyKeepsLegacySuggestion() throws {
        XCTAssertEqual(try decodeAuthor(careerStageJSON: nil, hasPhD: true).careerStage, .categoryB)
        XCTAssertEqual(try decodeAuthor(careerStageJSON: nil, hasPhD: false).careerStage, .categoryA)
    }

    func testUnknownNonEmptyStageStillFallsBackToB() throws {
        XCTAssertEqual(try decodeAuthor(careerStageJSON: #""x""#).careerStage, .categoryB)
    }

    func testNoStageRoundTripsAsNil() throws {
        var author = PublicationAuthor(
            id: "author-none",
            firstName: "Lisa",
            lastName: "Läkarstudent",
            hasPhD: false
        )
        author.careerStage = nil

        let data = try JSONEncoder().encode(author)
        let decoded = try JSONDecoder().decode(PublicationAuthor.self, from: data)

        XCTAssertNil(decoded.careerStage)
        XCTAssertEqual(decoded.hasPhD, false)
    }

    func testSelectedStageRoundTripsUnchanged() throws {
        for stage in PublicationAuthorCareerStage.allCases {
            let author = PublicationAuthor(
                id: "author-\(stage.rawValue)",
                firstName: "Kim",
                lastName: "Exempel",
                hasPhD: stage != .categoryD,
                careerStage: stage
            )
            let data = try JSONEncoder().encode(author)
            let decoded = try JSONDecoder().decode(PublicationAuthor.self, from: data)
            XCTAssertEqual(decoded.careerStage, stage)
        }
    }

    func testDisplayTextShowsDashForNoStage() {
        XCTAssertEqual(PublicationAuthorCareerStage.displayText(for: nil), "–")
        XCTAssertEqual(PublicationAuthorCareerStage.displayText(for: .categoryC), "C")
    }

    // MARK: - Datakvalitet

    @MainActor
    private func careerStageIssues(for authors: [PublicationAuthor]) -> [GrantDataStore.IntegrityIssue] {
        let store = GrantDataStore(publicationAuthors: authors)
        return store.dataQualityIntegrityIssues().filter { $0.id.contains("-careerStage-") }
    }

    @MainActor
    func testStageDWithPhDIsFlagged() {
        let author = PublicationAuthor(
            id: "author-d-phd",
            firstName: "Doris",
            lastName: "Doktorand",
            hasPhD: true,
            careerStage: .categoryD
        )

        let issues = careerStageIssues(for: [author])

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.recordID, "author-d-phd")
        XCTAssertEqual(issues.first?.destination, .people)
        XCTAssertEqual(issues.first?.kind, .semantic)
        XCTAssertTrue(issues.first?.id.hasSuffix("careerStage-D-hasPhD") ?? false)
    }

    @MainActor
    func testStagesAToCWithoutPhDAreFlagged() {
        let authors = [PublicationAuthorCareerStage.categoryA, .categoryB, .categoryC].map { stage in
            PublicationAuthor(
                id: "author-\(stage.rawValue)-no-phd",
                firstName: "Nils",
                lastName: "Nodisputation",
                hasPhD: false,
                careerStage: stage
            )
        }

        let issues = careerStageIssues(for: authors)

        XCTAssertEqual(Set(issues.map(\.recordID)), Set(authors.map(\.id)))
        XCTAssertTrue(issues.allSatisfy { $0.id.hasSuffix("-missingPhD") })
    }

    @MainActor
    func testConsistentOrMissingStagesAreNotFlagged() {
        var noStage = PublicationAuthor(
            id: "author-none",
            firstName: "Lisa",
            lastName: "Läkarstudent",
            hasPhD: false
        )
        noStage.careerStage = nil
        let authors = [
            noStage,
            PublicationAuthor(id: "author-d", firstName: "Dan", lastName: "Doktorand", hasPhD: false, careerStage: .categoryD),
            PublicationAuthor(id: "author-c", firstName: "Cia", lastName: "Postdok", hasPhD: true, careerStage: .categoryC),
            PublicationAuthor(id: "author-a", firstName: "Åke", lastName: "Professor", hasPhD: true, careerStage: .categoryA),
        ]

        XCTAssertTrue(careerStageIssues(for: authors).isEmpty)
    }

    @MainActor
    func testCareerStageIssueCanBeHidden() {
        let author = PublicationAuthor(
            id: "author-hide",
            firstName: "Hedda",
            lastName: "Dold",
            hasPhD: true,
            careerStage: .categoryD
        )
        let store = GrantDataStore(publicationAuthors: [author])
        guard let issue = store.dataQualityIntegrityIssues().first(where: { $0.id.contains("-careerStage-") }) else {
            return XCTFail("Expected a career stage issue")
        }

        XCTAssertFalse(store.isDataQualityWarningHidden(issue))
        XCTAssertTrue(store.hideDataQualityWarning(issue))
        XCTAssertTrue(store.isDataQualityWarningHidden(issue))
    }
}
