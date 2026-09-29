import XCTest
@testable import Footprint

/// F21: organization tree. Units in any number of levels, publication address
/// lines from the tree, unit validity and decoding of old data.
final class OrganizationTreeTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrganizationTreeTests-\(UUID().uuidString)", isDirectory: true)
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
            roles: [.institution]
        )
    }
    private static var region: OrganizationRecord {
        OrganizationRecord(
            id: "org-ro",
            nameSv: "Region Exempelgöta",
            nameEn: "Region Exempelgöta",
            city: "Exempelköping",
            country: "Sweden",
            roles: [.employer]
        )
    }
    private static var stockholm: OrganizationRecord {
        OrganizationRecord(
            id: "org-rs",
            nameSv: "Region Stockholm",
            nameEn: "Region Stockholm",
            city: "Stockholm",
            country: "Sweden"
        )
    }

    private static func author(
        _ id: String,
        _ affiliations: [PublicationAffiliation],
        employments: [PublicationAuthorEmployment] = [],
        education: [PublicationAuthorEducation] = []
    ) -> PublicationAuthor {
        PublicationAuthor(
            id: id,
            name: "Forskare \(id)",
            affiliations: affiliations,
            employments: employments,
            educationEntries: education
        )
    }

    @MainActor
    private func makeStore(
        organizations: [OrganizationRecord] = [OrganizationTreeTests.uni, OrganizationTreeTests.region, OrganizationTreeTests.stockholm],
        authors: [PublicationAuthor]
    ) -> GrantDataStore {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        return GrantDataStore(
            metadata: metadata,
            organizations: organizations,
            publicationAuthors: authors,
            skipInitialMigration: true
        )
    }

    // MARK: Address lines

    func testAddressLineForDivisionCollapsesToItsDepartment() {
        var organization = Self.uni
        organization.units = [
            OrganizationUnit(id: "fak", nameSv: "Exempelfakulteten", nameEn: "Faculty of Example Sciences", inAddress: false),
            OrganizationUnit(
                id: "iem",
                parentUnitID: "fak",
                nameSv: "Institutionen för exempelmedicin och vård",
                abbreviation: "IEM",
                addressNameEn: "Department of Example Medicine, and Caring Sciences",
                city: "Exempelköping",
                childrenInAddress: false
            ),
            OrganizationUnit(id: "avd", parentUnitID: "iem", nameSv: "Avdelningen för prevention, rehabilitering och vård", nameEn: "Division of Prevention"),
        ]
        let division = organization.unit(withID: "avd")

        XCTAssertEqual(organization.unitPath(to: "avd").map(\.id), ["fak", "iem", "avd"])
        XCTAssertEqual(organization.addressUnit(for: "avd")?.id, "iem")
        XCTAssertEqual(
            OrganizationTree.publicationAddressLine(organization: organization, unit: division),
            "Department of Example Medicine, and Caring Sciences, Exempelköping University, Exempelköping, Sweden"
        )
    }

    func testAddressLineForRegionClinicSkipsTheCentrum() {
        var organization = Self.region
        organization.units = [
            OrganizationUnit(id: "centrum", nameSv: "Centrum för kirurgi, ortopedi och cancervård", inAddress: false),
            OrganizationUnit(
                id: "kir",
                parentUnitID: "centrum",
                nameSv: "Kirurgiska kliniken Exempelvik",
                addressNameEn: "Clinical Department of Surgery in Exempelvik",
                city: "Exempelvik"
            ),
        ]
        XCTAssertEqual(
            organization.publicationAddressLine(unit: organization.unit(withID: "kir")),
            "Clinical Department of Surgery in Exempelvik, Region Exempelgöta, Exempelvik, Sweden"
        )
        XCTAssertEqual(
            organization.publicationAddressLine(unit: organization.unit(withID: "centrum")),
            "Region Exempelgöta, Exempelköping, Sweden",
            "a level that is not printed leaves only the organization"
        )
    }

    func testHospitalIsWrittenInsteadOfItsRegion() {
        var organization = Self.stockholm
        organization.units = [
            OrganizationUnit(
                id: "karolinska",
                nameSv: "Karolinska universitetssjukhuset",
                nameEn: "Karolinska University Hospital",
                city: "Stockholm",
                standsInForOrganizationInAddress: true
            ),
            OrganizationUnit(
                id: "micro",
                parentUnitID: "karolinska",
                nameSv: "Klinisk mikrobiologi",
                nameEn: "Department of Clinical Microbiology"
            ),
        ]
        XCTAssertEqual(
            organization.publicationAddressLine(unit: organization.unit(withID: "micro")),
            "Department of Clinical Microbiology, Karolinska University Hospital, Stockholm, Sweden"
        )
        XCTAssertEqual(
            organization.publicationAddressLine(unit: organization.unit(withID: "karolinska")),
            "Karolinska University Hospital, Stockholm, Sweden",
            "the hospital itself is written once"
        )
    }

    @MainActor
    func testUniversityAddressLineComesBeforeRegionLine() {
        var uni = Self.uni
        uni.addressOrder = 1
        uni.units = [
            OrganizationUnit(
                id: "iem",
                nameSv: "Institutionen för exempelmedicin och vård",
                addressNameEn: "Department of Example Medicine, and Caring Sciences",
                city: "Exempelköping",
                childrenInAddress: false
            ),
        ]
        var region = Self.region
        region.addressOrder = 2
        region.units = [
            OrganizationUnit(id: "vc", nameSv: "Vårdcentralen Exempelholmen", addressNameEn: "Primary Healthcare Center Exempelholmen", city: "Exempelköping"),
        ]
        let researcher = Self.author(
            "a1",
            [
                PublicationAffiliation(id: "r1", organization: "Region Exempelgöta", department: "Vårdcentralen Exempelholmen", organizationID: "org-ro", unitID: "vc"),
                PublicationAffiliation(id: "r2", organization: "Exempelköpings universitet", department: "IEM", organizationID: "org-uni", unitID: "iem"),
            ],
            employments: [
                PublicationAuthorEmployment(id: "e1", from: "2020-01-01", organization: "Exempelköpings universitet", organizationID: "org-uni", unitID: "iem"),
                PublicationAuthorEmployment(id: "e2", from: "2010-01-01", to: "2012-12-31", organization: "Karolinska Institutet", city: "Stockholm", country: "Sweden"),
            ]
        )
        let day = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 6, day: 1).date ?? Date()

        let lines = OrganizationTree.publicationAddressLines(for: researcher, organizations: [region, uni], asOf: day)
        XCTAssertEqual(lines, [
            "Department of Example Medicine, and Caring Sciences, Exempelköping University, Exempelköping, Sweden",
            "Primary Healthcare Center Exempelholmen, Region Exempelgöta, Exempelköping, Sweden",
        ], "EXU first, one line per unit, the ended employment is left out")

        let store = makeStore(organizations: [region, uni], authors: [researcher])
        XCTAssertEqual(store.publicationAddressLines(for: researcher, asOf: day), lines)
    }

    // MARK: Validity

    func testUnitThatEndsBeforeItStartsIsInvalid() {
        XCTAssertFalse(OrganizationUnit(nameSv: "A", validFrom: "2020", validTo: "2019").hasValidDateRange)
        XCTAssertFalse(OrganizationUnit(nameSv: "A", validFrom: "2020-06-01", validTo: "2020-05-31").hasValidDateRange)
        XCTAssertTrue(OrganizationUnit(nameSv: "A", validFrom: "2020-06-01", validTo: "2020").hasValidDateRange)
        XCTAssertTrue(OrganizationUnit(nameSv: "A", validFrom: "", validTo: "2019").hasValidDateRange)
        XCTAssertTrue(OrganizationUnit(nameSv: "A", validFrom: "2019", validTo: "2019").hasValidDateRange)
        XCTAssertTrue(OrganizationUnit(nameSv: "A", validFrom: "2019").isValid(onDay: "2026-01-01"))
        XCTAssertFalse(OrganizationUnit(nameSv: "A", validTo: "2019").isValid(onDay: "2026-01-01"))
    }

    // MARK: Old data

    func testOldJSONWithoutTheNewKeysDecodes() throws {
        let organizationJSON = #"{"id":"o1","nameSv":"Exempelköpings universitet","nameEn":"Exempelköping University","roles":["institution"]}"#
        let organization = try JSONDecoder().decode(OrganizationRecord.self, from: Data(organizationJSON.utf8))
        XCTAssertEqual(organization.units, [])
        XCTAssertEqual(organization.addressNameEn, "")
        XCTAssertNil(organization.addressOrder)

        let affiliationJSON = #"{"id":"a1","organization":"Exempelköpings universitet","department":"IEM","city":"Exempelköping","isPrimary":true}"#
        let affiliation = try JSONDecoder().decode(PublicationAffiliation.self, from: Data(affiliationJSON.utf8))
        XCTAssertEqual(affiliation.department, "IEM")
        XCTAssertNil(affiliation.organizationID)
        XCTAssertNil(affiliation.unitID)

        let employmentJSON = #"{"id":"e1","from":"2020-01-01","organization":"Region Exempelgöta","department":"Sjukhuset i Exempelvik"}"#
        let employment = try JSONDecoder().decode(PublicationAuthorEmployment.self, from: Data(employmentJSON.utf8))
        XCTAssertNil(employment.organizationID)
        XCTAssertNil(employment.unitID)

        let educationJSON = #"{"id":"d1","organization":"Karolinska Institutet"}"#
        let education = try JSONDecoder().decode(PublicationAuthorEducation.self, from: Data(educationJSON.utf8))
        XCTAssertNil(education.organizationID)
        XCTAssertNil(education.unitID)

        var linked = organization
        linked.addressOrder = 1
        linked.units = [OrganizationUnit(id: "u1", nameSv: "IEM", validFrom: "2019")]
        let roundTripped = try JSONDecoder().decode(OrganizationRecord.self, from: JSONEncoder().encode(linked))
        XCTAssertEqual(roundTripped, linked)

        var linkedAffiliation = affiliation
        linkedAffiliation.organizationID = "o1"
        linkedAffiliation.unitID = "u1"
        let affiliationRoundTrip = try JSONDecoder().decode(PublicationAffiliation.self, from: JSONEncoder().encode(linkedAffiliation))
        XCTAssertEqual(affiliationRoundTrip, linkedAffiliation)
    }
}
