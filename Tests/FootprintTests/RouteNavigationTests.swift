import XCTest
@testable import Footprint

/// Locks in the navigation-audit fixes: the CV-area prefixed route tokens
/// must land in their actual tabs, and translation issues must resolve to
/// real records. The click-through audit found ~24 broken links in exactly
/// these mappings before they were fixed.
final class RouteNavigationTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RouteNavigationTests-\(UUID().uuidString)", isDirectory: true)
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

    func testCVAreaPrefixedTokensRouteToTheirActualTabs() {
        XCTAssertEqual(appTabForRoute(AppRoute(recordID: "review:r-1", destination: .cv)), .expertAssignments)
        XCTAssertEqual(appTabForRoute(AppRoute(recordID: "conferenceContribution:c-1", destination: .cv)), .congresses)
        XCTAssertEqual(appTabForRoute(AppRoute(recordID: "organizationCongress:org-1:con-1", destination: .cv)), .congresses)
        XCTAssertEqual(appTabForRoute(AppRoute(recordID: "mediaAppearance:m-1", destination: .cv)), .dissemination)
        XCTAssertEqual(appTabForRoute(AppRoute(recordID: "otherPublication:o-1", destination: .cv)), .dissemination)
        XCTAssertEqual(
            appTabForRoute(AppRoute(recordID: "raw-id", destination: .cv)),
            .cv,
            "raw ids keep the dissemination-area fallback"
        )
    }

    func testEveryPlainDestinationRoutesToItsOwnTab() {
        let expectations: [(AppRoute.Destination, AppTab)] = [
            (.applications, .applications),
            (.congresses, .congresses),
            (.expertAssignments, .expertAssignments),
            (.publications, .publications),
            (.projects, .projects),
            (.teaching, .teaching),
            (.doctoralCandidates, .doctoralCandidates),
            (.organizations, .organizations),
            (.people, .coauthors),
            (.journals, .journals),
        ]
        for (destination, tab) in expectations {
            XCTAssertEqual(appTabForRoute(AppRoute(recordID: "id", destination: destination)), tab)
        }
    }

    @MainActor
    func testUntranslatedRecordIssuesFlagMissingAndIdenticalTranslations() {
        let store = GrantDataStore(
            organizations: [
                OrganizationRecord(id: "org-untranslated", nameSv: "Vetenskapsrådet", nameEn: ""),
                OrganizationRecord(id: "org-identical", nameSv: "Same name", nameEn: "Same name"),
                OrganizationRecord(id: "org-ok", nameSv: "Hjärnfonden", nameEn: "The Brain Foundation"),
            ],
            projects: [
                ProjectRecord(id: "project-untranslated", nameSv: "", nameEn: "Only English"),
            ]
        )

        let issues = store.untranslatedRecordIssues(includeHidden: true)
        let issueRecordIDs = Set(issues.map(\.recordID))

        XCTAssertTrue(issueRecordIDs.contains("org-untranslated"), "missing English name must be flagged")
        XCTAssertTrue(issueRecordIDs.contains("org-identical"), "identical names must be flagged as untranslated")
        XCTAssertTrue(issueRecordIDs.contains("project-untranslated"), "missing Swedish name must be flagged")
        XCTAssertFalse(issueRecordIDs.contains("org-ok"), "properly translated records must not be flagged")
    }

    @MainActor
    func testSaveTranslatedNamesResolvesTheIssue() {
        let store = GrantDataStore(
            organizations: [
                OrganizationRecord(id: "org-untranslated", nameSv: "Vetenskapsrådet", nameEn: ""),
            ]
        )
        guard let issue = store.untranslatedRecordIssues(includeHidden: true)
            .first(where: { $0.recordID == "org-untranslated" }) else {
            return XCTFail("expected an untranslated-organization issue")
        }

        store.saveTranslatedNames(for: issue, nameSv: "Vetenskapsrådet", nameEn: "Swedish Research Council")

        XCTAssertTrue(
            store.untranslatedRecordIssues(includeHidden: true)
                .allSatisfy { $0.recordID != "org-untranslated" },
            "saving both names must resolve the issue"
        )
        XCTAssertEqual(
            store.organizations.first(where: { $0.id == "org-untranslated" })?.nameEn,
            "Swedish Research Council"
        )
    }
}
