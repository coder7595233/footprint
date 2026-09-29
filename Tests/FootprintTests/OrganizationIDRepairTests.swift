import XCTest
@testable import Footprint

/// F21: organizations created with an id made from the name
/// ("organization-university-of-sydney") get a UUID at startup, and every
/// reference to the old id follows.
final class OrganizationIDRepairTests: XCTestCase {
    private static let legacyID = "organization-university-of-sydney"
    private static let longerLegacyID = "organization-university-of-sydney-2"
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrganizationIDRepairTests-\(UUID().uuidString)", isDirectory: true)
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

    private static func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }

    @MainActor
    func testRepairGivesLegacyOrganizationsUUIDsAndMovesEveryReference() throws {
        let legacyID = Self.legacyID
        let longerLegacyID = Self.longerLegacyID
        let keptID = UUID().uuidString
        let applicationID = UUID().uuidString
        let authorID = UUID().uuidString
        let missingIssueKey = [
            "data-quality-warning:v1",
            "missing",
            "organizations",
            Self.lengthPrefixed(legacyID),
            Self.lengthPrefixed("missing-organizations-\(legacyID)-country"),
        ].joined(separator: "|")

        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        metadata.lastSelectedOrganizationID = legacyID
        metadata.lastSelectedManagerID = legacyID
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: "meeting-1",
                date: "2026-03-01",
                title: "Möte med Sydney",
                organizationIDs: [legacyID, keptID],
                organizationID: legacyID
            ),
        ]
        metadata.calendarHiddenAutomaticEventKeys = [
            CalendarAutomaticEventHideKey.congressAbstractDeadline(organizationID: legacyID, congressID: "congress-1"),
        ]
        metadata.taskItems = [
            TaskItem(
                id: "task-1",
                deadline: "2026-04-01",
                links: [
                    TaskLink(kind: .organization, targetID: legacyID),
                    TaskLink(kind: .congress, targetID: "congress-1", ownerID: legacyID),
                ]
            ),
        ]
        metadata.hiddenDataQualityWarningKeys = [missingIssueKey]

        let store = GrantDataStore(
            applications: [
                GrantApplication(
                    id: applicationID,
                    rowNumber: 1,
                    organizationID: legacyID,
                    organization: "University of Sydney",
                    grantName: "Bidrag",
                    applicationManagerID: legacyID,
                    applicationManager: "University of Sydney"
                ),
            ],
            metadata: metadata,
            organizations: [
                OrganizationRecord(id: legacyID, nameSv: "University of Sydney", nameEn: "University of Sydney", roles: [.grantProvider, .fundManager]),
                OrganizationRecord(id: longerLegacyID, nameSv: "University of Sydney Medical School", nameEn: "University of Sydney Medical School"),
                OrganizationRecord(id: keptID, nameSv: "Exempelköpings universitet", nameEn: "Exempelköping University"),
            ],
            publicationAuthors: [
                PublicationAuthor(
                    id: authorID,
                    name: "Forskare Ett",
                    affiliations: [
                        PublicationAffiliation(id: "aff-1", organization: "University of Sydney", organizationID: legacyID),
                        PublicationAffiliation(id: "aff-2", organization: "University of Sydney Medical School", organizationID: longerLegacyID),
                        PublicationAffiliation(id: "aff-3", organization: "Exempelköpings universitet", organizationID: keptID),
                    ]
                ),
            ],
            skipInitialMigration: true
        )
        let duplicateKeyBefore = try XCTUnwrap(store.duplicateWarningSuppressionKey(
            groupKind: .funders,
            normalizedKey: "university of sydney",
            recordIDs: [legacyID, keptID]
        ))
        XCTAssertEqual(
            GrantDataStore.warningKeyRewritingOrganizationIDs(duplicateKeyBefore, orderedMapping: []),
            duplicateKeyBefore,
            "a key without an old id comes back unchanged"
        )

        let organizationCountBefore = store.organizations.count
        let applicationCountBefore = store.applications.count
        let authorCountBefore = store.publicationAuthors.count
        let affiliationCountBefore = store.publicationAuthors.reduce(0) { $0 + $1.affiliations.count }
        let meetingCountBefore = store.metadata.calendarMeetingRecords?.count ?? 0
        let taskCountBefore = store.metadata.taskItems?.count ?? 0

        let mapping = store.repairLegacyOrganizationIDs()

        XCTAssertEqual(Set(mapping.keys), [legacyID, longerLegacyID], "only the organizations without a UUID are repaired")
        let newID = try XCTUnwrap(mapping[legacyID])
        let newLongerID = try XCTUnwrap(mapping[longerLegacyID])
        XCTAssertNotNil(UUID(uuidString: newID))
        XCTAssertNotNil(UUID(uuidString: newLongerID))
        XCTAssertNotEqual(newID, newLongerID)

        // Nothing is added or removed, and names are kept.
        XCTAssertEqual(store.organizations.count, organizationCountBefore)
        XCTAssertEqual(store.applications.count, applicationCountBefore)
        XCTAssertEqual(store.publicationAuthors.count, authorCountBefore)
        XCTAssertEqual(store.publicationAuthors.reduce(0) { $0 + $1.affiliations.count }, affiliationCountBefore)
        XCTAssertEqual(store.metadata.calendarMeetingRecords?.count ?? 0, meetingCountBefore)
        XCTAssertEqual(store.metadata.taskItems?.count ?? 0, taskCountBefore)
        XCTAssertTrue(store.organizations.allSatisfy { UUID(uuidString: $0.id) != nil })
        XCTAssertEqual(store.organizations.first { $0.id == newID }?.nameSv, "University of Sydney")
        XCTAssertEqual(store.organizations.first { $0.id == newLongerID }?.nameSv, "University of Sydney Medical School")
        XCTAssertNotNil(store.organizations.first { $0.id == keptID }, "an organization with a UUID keeps it")

        // The affiliation, the application and the meeting follow.
        let affiliations = try XCTUnwrap(store.publicationAuthors.first { $0.id == authorID }?.affiliations)
        XCTAssertEqual(affiliations.first { $0.id == "aff-1" }?.organizationID, newID)
        XCTAssertEqual(affiliations.first { $0.id == "aff-2" }?.organizationID, newLongerID)
        XCTAssertEqual(affiliations.first { $0.id == "aff-3" }?.organizationID, keptID)
        let application = try XCTUnwrap(store.applications.first { $0.id == applicationID })
        XCTAssertEqual(application.organizationID, newID)
        XCTAssertEqual(application.applicationManagerID, newID)
        XCTAssertEqual(application.organization, "University of Sydney")
        let meeting = try XCTUnwrap(store.metadata.calendarMeetingRecords?.first { $0.id == "meeting-1" })
        XCTAssertEqual(Set(meeting.organizationIDs), [newID, keptID])
        XCTAssertEqual(meeting.organizationID, newID)

        // Task links, remembered selections, hidden keys and aliases.
        let links = try XCTUnwrap(store.metadata.taskItems?.first { $0.id == "task-1" }?.links)
        XCTAssertEqual(links.first { $0.kind == .organization }?.targetID, newID)
        XCTAssertEqual(links.first { $0.kind == .congress }?.ownerID, newID)
        XCTAssertEqual(links.first { $0.kind == .congress }?.targetID, "congress-1")
        XCTAssertEqual(store.metadata.lastSelectedOrganizationID, newID)
        XCTAssertEqual(store.metadata.lastSelectedManagerID, newID)
        XCTAssertEqual(
            store.metadata.calendarHiddenAutomaticEventKeys,
            [CalendarAutomaticEventHideKey.congressAbstractDeadline(organizationID: newID, congressID: "congress-1")]
        )
        let expectedMissingKey = [
            "data-quality-warning:v1",
            "missing",
            "organizations",
            Self.lengthPrefixed(newID),
            Self.lengthPrefixed("missing-organizations-\(newID)-country"),
        ].joined(separator: "|")
        XCTAssertTrue(store.metadata.hiddenDataQualityWarningKeys?.contains(expectedMissingKey) == true)
        let orderedMapping: [(old: String, new: String)] = [(old: longerLegacyID, new: newLongerID), (old: legacyID, new: newID)]
        XCTAssertEqual(
            GrantDataStore.warningKeyRewritingOrganizationIDs(duplicateKeyBefore, orderedMapping: orderedMapping),
            store.duplicateWarningSuppressionKey(groupKind: .funders, normalizedKey: "university of sydney", recordIDs: [newID, keptID]),
            "a hidden duplicate warning stays hidden after the repair"
        )
        let aliases = store.metadata.idAliases ?? []
        XCTAssertEqual(aliases.first { $0.entityType == "organization" && $0.oldID == legacyID }?.newID, newID)
        XCTAssertEqual(aliases.first { $0.entityType == "organization" && $0.oldID == longerLegacyID }?.newID, newLongerID)

        // No stored record mentions the old ids any more (the aliases do, on purpose).
        var metadataWithoutAliases = store.metadata
        metadataWithoutAliases.idAliases = nil
        let encoder = JSONEncoder()
        let encoded = [
            try encoder.encode(store.organizations),
            try encoder.encode(store.applications),
            try encoder.encode(store.publicationAuthors),
            try encoder.encode(metadataWithoutAliases),
        ].map { String(decoding: $0, as: UTF8.self) }
        for text in encoded {
            XCTAssertFalse(text.contains(legacyID), "the old id is gone")
        }

        // A second run changes nothing.
        let organizationsAfter = store.organizations
        let applicationsAfter = store.applications
        let authorsAfter = store.publicationAuthors
        let metadataAfter = store.metadata
        XCTAssertTrue(store.repairLegacyOrganizationIDs().isEmpty)
        XCTAssertEqual(store.organizations, organizationsAfter)
        XCTAssertEqual(store.applications, applicationsAfter)
        XCTAssertEqual(store.publicationAuthors, authorsAfter)
        XCTAssertEqual(store.metadata, metadataAfter)
    }

    @MainActor
    func testRepairLeavesUUIDOrganizationsAlone() {
        let id = UUID().uuidString
        let store = GrantDataStore(
            organizations: [OrganizationRecord(id: id, nameSv: "Exempelköpings universitet", nameEn: "Exempelköping University")],
            skipInitialMigration: true
        )
        let metadataBefore = store.metadata
        XCTAssertTrue(store.repairLegacyOrganizationIDs().isEmpty)
        XCTAssertEqual(store.organizations.map(\.id), [id])
        XCTAssertEqual(store.metadata, metadataBefore)
    }
}
