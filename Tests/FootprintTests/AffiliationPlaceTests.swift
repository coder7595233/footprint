import XCTest
@testable import Footprint

/// F48: choosing a unit or an organization on an affiliation fills in city
/// and country from the unit, else its nearest parent unit, else the
/// organization.
final class AffiliationPlaceTests: XCTestCase {
    private static var organization: OrganizationRecord {
        var organization = OrganizationRecord(
            id: "org-uni",
            nameSv: "Exempelköpings universitet",
            nameEn: "Exempelköping University",
            city: "Exempelköping",
            country: "Sweden"
        )
        organization.units = [
            OrganizationUnit(id: "campus", nameSv: "Campus Exempelby", city: "Exempelby"),
            OrganizationUnit(id: "dept", parentUnitID: "campus", nameSv: "Institutionen för exempelvetenskap"),
            OrganizationUnit(id: "own", parentUnitID: "campus", nameSv: "Avdelningen i Annanstad", city: "Annanstad"),
            OrganizationUnit(id: "plain", nameSv: "Institutionen utan ort")
        ]
        return organization
    }

    func testUnitCityIsUsed() {
        let organization = Self.organization
        var affiliation = PublicationAffiliation(city: "Gammal ort", country: "Norway")
        XCTAssertTrue(affiliation.applyPlace(organization: organization, unit: organization.unit(withID: "own")))
        XCTAssertEqual(affiliation.city, "Annanstad")
        XCTAssertEqual(affiliation.country, "Sweden")
    }

    func testParentUnitCityIsUsedWhenUnitHasNone() {
        let organization = Self.organization
        var affiliation = PublicationAffiliation()
        affiliation.applyPlace(organization: organization, unit: organization.unit(withID: "dept"))
        XCTAssertEqual(affiliation.city, "Exempelby")
    }

    func testOrganizationIsUsedWithoutUnitCity() {
        let organization = Self.organization
        var withUnit = PublicationAffiliation()
        withUnit.applyPlace(organization: organization, unit: organization.unit(withID: "plain"))
        XCTAssertEqual(withUnit.city, "Exempelköping")

        var withoutUnit = PublicationAffiliation()
        withoutUnit.applyPlace(organization: organization, unit: nil)
        XCTAssertEqual(withoutUnit.city, "Exempelköping")
        XCTAssertEqual(withoutUnit.country, "Sweden")
    }

    func testUnknownPlaceKeepsWhatIsWritten() {
        let organization = OrganizationRecord(id: "org-x", nameSv: "Organisation utan adress", nameEn: "")
        var affiliation = PublicationAffiliation(city: "Egen ort", country: "Denmark")
        XCTAssertFalse(affiliation.applyPlace(organization: organization, unit: nil))
        XCTAssertEqual(affiliation.city, "Egen ort")
        XCTAssertEqual(affiliation.country, "Denmark")
    }
}
