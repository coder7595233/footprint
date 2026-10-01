import AppKit
import XCTest
@testable import Footprint

/// Round 17 (withdrawn as its own grey group, spent grants paler green,
/// Norwegian list levels, congress rule, edge and mark colours).
/// All names and values below are made up.
final class Round17ColoursTests: XCTestCase {

    private func application(
        _ id: String,
        organizationID: String? = nil,
        appliedOn: String? = "2026-01-10",
        grantedOn: String? = nil,
        deniedOn: String? = nil,
        withdrawnOn: String? = nil
    ) -> GrantApplication {
        GrantApplication(
            id: id,
            rowNumber: 1,
            organizationID: organizationID,
            organization: "Invented Fund",
            grantName: "Invented grant \(id)",
            appliedOn: appliedOn,
            appliedAmountValue: 100000,
            grantedOn: grantedOn,
            deniedOn: deniedOn,
            withdrawnOn: withdrawnOn
        )
    }

    private func hex(_ color: NSColor) -> Int? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let red = Int((srgb.redComponent * 255).rounded())
        let green = Int((srgb.greenComponent * 255).rounded())
        let blue = Int((srgb.blueComponent * 255).rounded())
        return (red << 16) | (green << 8) | blue
    }

    // MARK: Withdrawn is never declined

    func testWithdrawnIsItsOwnOutcomeGroup() {
        XCTAssertEqual(AppStatusTones.applicationOutcomeGroup(resultLabel: "Tillbakadragen", isGranted: false), .withdrawn)
        XCTAssertEqual(AppStatusTones.applicationOutcomeGroup(resultLabel: "Avslag", isGranted: false), .declined)
        XCTAssertEqual(AppStatusTones.applicationOutcomeGroup(resultLabel: " Avslag ", isGranted: false), .declined)
        XCTAssertEqual(AppStatusTones.applicationOutcomeGroup(resultLabel: "Beviljat", isGranted: true), .granted)
        XCTAssertEqual(AppStatusTones.applicationOutcomeGroup(resultLabel: "Väntar svar", isGranted: false), .awaiting)
        XCTAssertEqual(AppStatusTones.applicationOutcomeGroup(resultLabel: "Ej sökt", isGranted: false), .other)
        XCTAssertFalse(AppStatusTones.isDeclined(resultLabel: "Tillbakadragen"))
        XCTAssertTrue(AppStatusTones.isWithdrawn(resultLabel: "Tillbakadragen"))
        XCTAssertEqual(
            AppStatusTones.application(resultLabel: "Tillbakadragen", isFullySpent: false, awaitsAppliedAnswer: false, isBeforeOpening: false),
            .inactive,
            "withdrawn is grey"
        )
    }

    func testOrganizationSummaryCountsWithdrawnApartFromDeclined() {
        let declined = application("app-declined", deniedOn: "2026-05-01")
        let withdrawn = application("app-withdrawn", withdrawnOn: "2026-04-01")
        let granted = application("app-granted", grantedOn: "2026-06-01")
        XCTAssertEqual(declined.resultLabel, "Avslag")
        XCTAssertEqual(withdrawn.resultLabel, "Tillbakadragen")

        var summary = OrganizationApplicationSummary()
        for item in [declined, withdrawn, granted] {
            summary.include(item)
        }
        XCTAssertEqual(summary.submitted, 3)
        XCTAssertEqual(summary.rejected, 1, "only Avslag is declined")
        XCTAssertEqual(summary.withdrawn, 1)
        XCTAssertEqual(summary.granted, 1)
    }

    @MainActor
    func testDashboardSummaryCountsWithdrawnApartFromDeclined() {
        let store = GrantDataStore(
            applications: [
                application("app-declined", deniedOn: "2026-05-01"),
                application("app-withdrawn-1", withdrawnOn: "2026-04-01"),
                application("app-withdrawn-2", withdrawnOn: "2026-04-02"),
            ],
            skipInitialMigration: true
        )
        let summary = store.summary
        XCTAssertEqual(summary.rejectedCount, 1)
        XCTAssertEqual(summary.withdrawnCount, 2)
    }

    func testOrganizationTimelineDrawsWithdrawnGrey() throws {
        let organization = OrganizationRecord(
            id: "org-invented",
            nameSv: "Påhittad stiftelse",
            nameEn: "Invented foundation",
            roles: [.grantProvider]
        )
        let withdrawn = application("app-withdrawn", organizationID: organization.id, withdrawnOn: "2026-04-01")
        let declined = application("app-declined", organizationID: organization.id, deniedOn: "2026-05-01")
        let snapshot = GrantDataStore.buildOrganizationTimelineSnapshot(
            organization: organization,
            funderApplications: [withdrawn, declined],
            managedApplications: [],
            currentUserAuthor: nil,
            language: .swedish
        )
        let bars = snapshot.groups.flatMap(\.bars)
        XCTAssertTrue(bars.contains { bar in
            if case .grantProviderGrant(.withdrawn) = bar.kind { return bar.applicationID == "app-withdrawn" }
            return false
        }, "withdrawn has its own (grey) bar kind")
        XCTAssertTrue(bars.contains { bar in
            if case .grantProviderGrant(.rejected) = bar.kind { return bar.applicationID == "app-declined" }
            return false
        })
        XCTAssertFalse(bars.contains { bar in
            if case .grantProviderGrant(.rejected) = bar.kind { return bar.applicationID == "app-withdrawn" }
            return false
        }, "withdrawn is never drawn as declined")

        let hidden = GrantDataStore.buildOrganizationTimelineSnapshot(
            organization: organization,
            funderApplications: [withdrawn, declined],
            managedApplications: [],
            currentUserAuthor: nil,
            language: .swedish,
            hideRejectedGrants: true
        )
        XCTAssertTrue(hidden.groups.flatMap(\.bars).filter { $0.applicationID != nil }.isEmpty,
                      "hiding declined grants also hides withdrawn ones, as before")
    }

    func testWithdrawnSegmentHasItsOwnTitle() {
        XCTAssertEqual(GrantOutcomeSegmentKind.withdrawn.title(language: .swedish), "Tillbakadragna")
        XCTAssertEqual(GrantOutcomeSegmentKind.rejected.title(language: .swedish), "Avslagna")
    }

    // MARK: Spent grants

    @MainActor
    func testSpentGrantIsAPalerGreen() {
        XCTAssertEqual(
            AppStatusTones.application(resultLabel: "Beviljat", isFullySpent: true, awaitsAppliedAnswer: false, isBeforeOpening: false),
            .done
        )
        XCTAssertEqual(hex(AppPalette.statusFillPaleNSColor(.done, dark: false)), 0xDCEBD3)
        XCTAssertEqual(hex(AppPalette.statusFillPaleNSColor(.done, dark: true)), 0x0D3F3B)
        XCTAssertNotEqual(
            hex(AppPalette.statusFillPaleNSColor(.done, dark: false)),
            hex(AppPalette.statusFillNSColor(.done, dark: false)),
            "paler than a grant with money left"
        )
        XCTAssertNil(AppPalette.applicationFill(.none, isFullySpent: true))
        XCTAssertNotNil(AppPalette.applicationFill(.done, isFullySpent: true))
        XCTAssertEqual(applicationTone(for: application("app-granted", grantedOn: "2026-06-01")), .positive)
        XCTAssertEqual(BadgeTone.positiveMuted.statusTone, .done)
    }

    // MARK: Norwegian list

    func testNorwegianListLevelTones() {
        XCTAssertEqual(AppStatusTones.norwegianListLevel(2), .done)
        XCTAssertEqual(AppStatusTones.norwegianListLevel(1), .pending)
        XCTAssertEqual(AppStatusTones.norwegianListLevel(0), .negative)
        XCTAssertEqual(AppStatusTones.norwegianListLevel(3), .done)
    }

    // MARK: Congresses

    func testCongressRule() {
        func tone(attending: Bool, past: Bool, contribution: Bool = false, rejected: Bool = false) -> AppStatusTone {
            AppStatusTones.congress(AppStatusTones.congressStatus(
                isAttending: attending,
                isPast: past,
                hasContribution: contribution,
                hasRejectedContribution: rejected
            ))
        }
        XCTAssertEqual(tone(attending: true, past: false), .pending, "registered for a future congress")
        XCTAssertEqual(tone(attending: true, past: true), .done, "attended")
        XCTAssertEqual(tone(attending: false, past: true), .inactive, "not attending")
        XCTAssertEqual(tone(attending: false, past: false), .none, "planned without decision")
        XCTAssertEqual(tone(attending: false, past: false, contribution: true), .pending)
        XCTAssertEqual(AppStatusTones.conferenceContribution(CVConferenceContributionStatus.accepted), .pending)
        XCTAssertEqual(AppStatusTones.conferenceContribution(CVConferenceContributionStatus.presented), .done)
    }

    // MARK: Edge, mark and late colours

    func testEdgeAndMarkColoursExistForFilledTones() {
        for tone in AppStatusTone.allCases where tone.hasFill {
            for dark in [false, true] {
                let edge = AppPalette.statusEdgeNSColor(tone, dark: dark)
                let mark = AppPalette.statusMarkNSColor(tone, dark: dark)
                XCTAssertGreaterThan(edge.alphaComponent, 0, "\(tone) edge")
                XCTAssertGreaterThan(mark.alphaComponent, 0, "\(tone) mark")
                XCTAssertNotEqual(hex(edge), hex(AppPalette.statusFillNSColor(tone, dark: dark)), "\(tone) edge differs from the fill")
            }
        }
        XCTAssertEqual(hex(AppPalette.statusEdgeNSColor(.pending, dark: false)), 0xD6BF55)
        XCTAssertEqual(hex(AppPalette.statusEdgeNSColor(.pending, dark: true)), 0xB8892C)
        XCTAssertEqual(hex(AppPalette.statusMarkNSColor(.done, dark: false)), 0x5FA35A)
        XCTAssertEqual(hex(AppPalette.lateMarkNSColor(dark: false)), 0xE8551F)
        XCTAssertEqual(hex(AppPalette.lateTextNSColor(dark: true)), 0xFF9C63)
    }
}
