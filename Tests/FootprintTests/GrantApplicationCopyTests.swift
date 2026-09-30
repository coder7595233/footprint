import XCTest
@testable import Footprint

/// Round 10 ("Utlysningar och anslag"): "Kopiera till nästa år" makes next
/// year's record for the same call. Invented data only.
final class GrantApplicationCopyTests: XCTestCase {
    private func source() -> GrantApplication {
        var application = GrantApplication(
            id: "call-2026",
            rowNumber: 7,
            organizationID: "funder-1",
            organization: "Invented Foundation",
            grantName: "Project grant 2026",
            grantNameSv: "Projektbidrag 2026",
            grantNameEn: "Project grant 2026",
            currency: "SEK",
            maxAmount: "500 000",
            yearCount: "3",
            opensOn: "2026-01-15",
            closesOn: "2026-02-29",
            closesOnUncertain: true,
            decisionExpectedOn: "2026-06-01",
            firstDispositionOn: "2027-01-01",
            lastDispositionOn: "2029-12-31",
            projectID: "project-1",
            projectType: "Invented project",
            applicantCriteria: "Early career",
            primaryLink: "https://example.org/call",
            secondaryLink: "https://example.org/my-application",
            appliedOn: "2026-02-20",
            appliedCaseNumber: "APP-1",
            appliedAmount: "1 500 000",
            appliedAmountValue: 1_500_000,
            grantedOn: "2026-06-03",
            grantedAmount: "1 200 000",
            grantedAmountValue: 1_200_000,
            result: "Beviljat",
            institutionCaseNumber: "CASE-9",
            applicationManagerID: "manager-1",
            applicationManager: "Invented University",
            managerReason: "Standard",
            applicationTitle: "Invented title",
            coApplicants: ["A. Person"],
            coApplicantAuthorIDs: ["author-1"],
            appliedYear: "2026",
            fundingSalary: true,
            receivedProjectNumber: "P-1",
            receivedPEOE: "123",
            receivedConsumptionPeriods: [GrantConsumptionPeriod(from: "2027-01-01", to: "2027-12-31", amount: "100 000")],
            receivedUsageFrom: "2027-01-01",
            receivedUsageTo: "2029-12-31"
        )
        application.isEditingLocked = true
        return application
    }

    func testCopyKeepsTheCallAndMovesEveryDateOneYear() {
        let copy = source().copiedToNextYear(newID: "call-2027", rowNumber: 8, status: "Att söka")
        XCTAssertEqual(copy.id, "call-2027")
        XCTAssertEqual(copy.rowNumber, 8)
        XCTAssertEqual(copy.organizationID, "funder-1")
        XCTAssertEqual(copy.grantNameSv, "Projektbidrag 2027")
        XCTAssertEqual(copy.grantNameEn, "Project grant 2027")
        XCTAssertEqual(copy.maxAmount, "500 000")
        XCTAssertEqual(copy.yearCount, "3")
        XCTAssertEqual(copy.opensOn, "2027-01-15")
        XCTAssertEqual(copy.closesOn, "2027-02-28")
        XCTAssertTrue(copy.closesOnUncertain)
        XCTAssertEqual(copy.decisionExpectedOn, "2027-06-01")
        XCTAssertEqual(copy.firstDispositionOn, "2028-01-01")
        XCTAssertEqual(copy.lastDispositionOn, "2030-12-31")
        XCTAssertEqual(copy.appliedYear, "2027")
        XCTAssertEqual(copy.projectID, "project-1")
        XCTAssertEqual(copy.applicationManagerID, "manager-1")
        XCTAssertEqual(copy.managerReason, "Standard")
        XCTAssertEqual(copy.coApplicantAuthorIDs, ["author-1"])
        XCTAssertEqual(copy.primaryLink, "https://example.org/call")
        XCTAssertTrue(copy.fundingSalary)
        XCTAssertFalse(copy.isEditingLocked)
    }

    func testCopyLeavesTheApplicationAndGrantPartsEmpty() {
        let copy = source().copiedToNextYear(newID: "call-2027", rowNumber: 8, status: "Att söka")
        XCTAssertEqual(copy.result, "Att söka")
        XCTAssertNil(copy.appliedOn)
        XCTAssertNil(copy.appliedCaseNumber)
        XCTAssertNil(copy.appliedAmountValue)
        XCTAssertNil(copy.grantedOn)
        XCTAssertNil(copy.grantedAmountValue)
        XCTAssertNil(copy.institutionCaseNumber)
        XCTAssertNil(copy.secondaryLink)
        XCTAssertNil(copy.receivedProjectNumber)
        XCTAssertNil(copy.receivedPEOE)
        XCTAssertTrue(copy.receivedConsumptionPeriods.isEmpty)
        XCTAssertNil(copy.receivedUsageFrom)
        XCTAssertNil(copy.receivedUsageTo)
    }

    func testYearShiftOnlyTouchesYears() {
        XCTAssertEqual(grantApplicationYearShifted("Forsknings-ALF 2027, kategori 2"), "Forsknings-ALF 2028, kategori 2")
        XCTAssertEqual(grantApplicationYearShifted("Anslag 12345 och 2099"), "Anslag 12345 och 2100")
        XCTAssertEqual(grantApplicationYearShifted("Utan år"), "Utan år")
        XCTAssertEqual(grantApplicationDateShiftedOneYear("2026"), "2027")
        XCTAssertNil(grantApplicationDateShiftedOneYear(nil))
    }
}
