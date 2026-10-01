import XCTest
@testable import Footprint

/// Round 7: reminders about applications are switched on (with an on/off
/// setting under Settings > Calendar > Reminder times), and the amount groups
/// are shown in Statistics > Grants.
final class GrantRemindersAndAmountGroupsTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is not automatic: without this a store reads and
    // writes the real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrantRemindersAndAmountGroupsTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
        WorkflowDefaultSettingsRegistry.replace(with: .builtIn)
    }

    override func tearDown() {
        unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
        WorkflowDefaultSettingsRegistry.replace(with: .builtIn)
        if let storageDirectory {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        storageDirectory = nil
        super.tearDown()
    }

    // MARK: Reminders

    private static func schedule(_ application: GrantApplication, settings: CalendarReminderSettings = .standard) -> [GrantReminderSchedule] {
        GrantReminderCoordinator.reminderSchedule(for: application, settings: settings, calendar: Calendar.current)
    }

    private static func day(_ schedule: GrantReminderSchedule) -> String {
        DateParsers.isoDay.string(from: schedule.fireDate)
    }

    private static var toApply: GrantApplication {
        GrantApplication(
            id: "to-apply",
            rowNumber: 1,
            organization: "Stiftelsen",
            grantName: "Projektbidrag",
            opensOn: "2027-03-01",
            closesOn: "2027-04-01"
        )
    }

    func testApplicationStillToApplyForGetsOpeningAndClosingReminders() {
        XCTAssertEqual(Self.toApply.resultLabel, "Att söka")
        let schedules = Self.schedule(Self.toApply)
        XCTAssertEqual(schedules.map(\.kind), [.opens, .closingSoon, .closedUnanswered])
        XCTAssertEqual(schedules.map(Self.day), ["2027-03-01", "2027-03-25", "2027-04-02"])
        XCTAssertEqual(schedules.map(\.id), [
            "grant-open-to-apply-2027-03-01",
            "grant-close-soon-to-apply-2027-04-01",
            "grant-closed-unanswered-to-apply-2027-04-01",
        ])
        for schedule in schedules {
            XCTAssertEqual(Calendar.current.component(.hour, from: schedule.fireDate), 9)
            XCTAssertEqual(Calendar.current.component(.minute, from: schedule.fireDate), 0)
        }

        var settings = CalendarReminderSettings.standard
        settings.grantClosingLeadDays = 14
        settings.grantReminderTime = "07:30"
        let custom = Self.schedule(Self.toApply, settings: settings)
        XCTAssertEqual(custom.map(Self.day), ["2027-03-01", "2027-03-18", "2027-04-02"])
        XCTAssertEqual(Calendar.current.component(.hour, from: custom[1].fireDate), 7)
        XCTAssertEqual(Calendar.current.component(.minute, from: custom[1].fireDate), 30)
    }

    func testSchedulingTwiceGivesTheSameIdentifiers() {
        // The same ids every time: a refresh replaces the waiting
        // notifications instead of adding copies.
        XCTAssertEqual(Self.schedule(Self.toApply), Self.schedule(Self.toApply))
        XCTAssertEqual(Set(Self.schedule(Self.toApply).map(\.id)).count, 3)
    }

    func testDeclinedWithdrawnAndNotAppliedGetNoReminders() {
        let notApplied = GrantApplication(
            id: "not-applied",
            rowNumber: 2,
            organization: "Stiftelsen",
            grantName: "Projektbidrag",
            opensOn: "2027-03-01",
            closesOn: "2027-04-01",
            notAppliedOn: "2027-02-01"
        )
        let declined = GrantApplication(
            id: "declined",
            rowNumber: 3,
            organization: "Stiftelsen",
            grantName: "Projektbidrag",
            opensOn: "2027-03-01",
            closesOn: "2027-04-01",
            decisionExpectedOn: "2027-06-01",
            lastDispositionOn: "2029-12-31",
            appliedOn: "2027-03-20",
            deniedOn: "2027-06-05",
            receivedRepaymentDueOn: "2027-08-01"
        )
        let withdrawn = GrantApplication(
            id: "withdrawn",
            rowNumber: 4,
            organization: "Stiftelsen",
            grantName: "Projektbidrag",
            closesOn: "2027-04-01",
            decisionExpectedOn: "2027-06-01",
            appliedOn: "2027-03-20",
            withdrawnOn: "2027-04-15"
        )
        XCTAssertEqual(notApplied.resultLabel, "Ej sökt")
        XCTAssertEqual(declined.resultLabel, "Avslag")
        XCTAssertEqual(withdrawn.resultLabel, "Tillbakadragen")
        XCTAssertEqual(Self.schedule(notApplied), [])
        XCTAssertEqual(Self.schedule(declined), [])
        XCTAssertEqual(Self.schedule(withdrawn), [])
    }

    func testWaitingApplicationGetsOnlyTheDecisionReminder() {
        let waiting = GrantApplication(
            id: "waiting",
            rowNumber: 5,
            organization: "Stiftelsen",
            grantName: "Projektbidrag",
            opensOn: "2027-01-01",
            closesOn: "2027-02-15",
            decisionExpectedOn: "2027-06-01",
            appliedOn: "2027-02-01"
        )
        XCTAssertEqual(waiting.resultLabel, "Väntar svar")
        let schedules = Self.schedule(waiting)
        XCTAssertEqual(schedules.map(\.kind), [.decisionOverdue])
        XCTAssertEqual(schedules.map(Self.day), ["2027-06-08"])
    }

    func testGrantedApplicationGetsDispositionAndRepaymentReminders() {
        let granted = GrantApplication(
            id: "granted",
            rowNumber: 6,
            organization: "Stiftelsen",
            grantName: "Projektbidrag",
            closesOn: "2027-02-15",
            decisionExpectedOn: "2027-06-01",
            lastDispositionOn: "2028-12-31",
            appliedOn: "2027-02-01",
            grantedOn: "2027-06-01",
            grantedAmount: "500000",
            grantedAmountValue: 500_000,
            receivedRepaymentDueOn: "2029-03-01"
        )
        XCTAssertTrue(granted.isGranted)
        let schedules = Self.schedule(granted)
        XCTAssertEqual(schedules.map(\.kind), [.dispositionEndingSoon, .dispositionEnded, .repaymentOverdue])
        XCTAssertEqual(schedules.map(Self.day), ["2028-09-30", "2028-12-31", "2029-03-01"])

        var noLead = CalendarReminderSettings.standard
        noLead.grantDispositionEndLeadMonths = 0
        XCTAssertEqual(Self.schedule(granted, settings: noLead).map(\.kind), [.dispositionEnded, .repaymentOverdue])
    }

    func testSwitchedOffGivesNoReminders() {
        var off = CalendarReminderSettings.standard
        off.grantRemindersEnabled = false
        XCTAssertEqual(Self.schedule(Self.toApply, settings: off), [])
    }

    func testOverdueRemindersAreOnlySentForTheLastWeek() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(
            GrantReminderCoordinator.overdueWindowStart(now: now),
            now.addingTimeInterval(-7 * 24 * 60 * 60)
        )
    }

    // MARK: Reminder on/off setting

    func testReminderToggleDefaultsToOnAndIsStored() throws {
        XCTAssertTrue(CalendarReminderSettings.standard.grantRemindersEnabled)
        let decodedOld = try JSONDecoder().decode(
            CalendarReminderSettings.self,
            from: Data(#"{"grantClosingLeadDays": 10}"#.utf8)
        )
        XCTAssertTrue(decodedOld.grantRemindersEnabled, "data saved before the setting existed keeps reminders on")
        XCTAssertEqual(decodedOld.grantClosingLeadDays, 10)

        var off = CalendarReminderSettings.standard
        off.grantRemindersEnabled = false
        let roundTrip = try JSONDecoder().decode(CalendarReminderSettings.self, from: JSONEncoder().encode(off))
        XCTAssertFalse(roundTrip.grantRemindersEnabled)
        XCTAssertFalse(off.normalized().grantRemindersEnabled)
        XCTAssertNotEqual(off, .standard)
    }

    @MainActor
    func testStoreSavesTheReminderToggle() {
        let store = GrantDataStore()
        XCTAssertTrue(store.calendarReminderSettings.grantRemindersEnabled)

        var off = CalendarReminderSettings.standard
        off.grantRemindersEnabled = false
        store.autosaveCalendarReminderSettings(off)
        store.flushPendingPersistenceIfNeeded()
        XCTAssertFalse(store.calendarReminderSettings.grantRemindersEnabled)

        store.autosaveCalendarReminderSettings(.standard)
        store.flushPendingPersistenceIfNeeded()
        XCTAssertTrue(store.calendarReminderSettings.grantRemindersEnabled)
        XCTAssertNil(store.editableMetadataSnapshot.calendarReminderSettings, "defaults are not stored")
    }

    // MARK: Amount groups in the statistics

    private static func application(
        id: String,
        amount: Double,
        grantedAmount: Double? = nil,
        result: String
    ) -> GrantApplication {
        GrantApplication(
            id: id,
            rowNumber: 1,
            organization: "Stiftelsen",
            grantName: "Projektbidrag",
            approximateAmount: String(Int(amount)),
            approximateAmountValue: amount,
            grantedAmountValue: grantedAmount,
            result: result
        )
    }

    func testAmountGroupSummariesCountApplicationsGrantedAndSum() {
        let applications = [
            Self.application(id: "small-granted", amount: 100_000, grantedAmount: 90_000, result: "Beviljat"),
            Self.application(id: "medium-declined", amount: 300_000, result: "Avslag"),
            Self.application(id: "medium-granted", amount: 500_000, grantedAmount: 400_000, result: "Beviljat"),
            Self.application(id: "large-granted", amount: 2_000_000, grantedAmount: 1_500_000, result: "Beviljat"),
            Self.application(id: "large-declined", amount: 2_000_000, result: "Avslag"),
        ]
        let settings = WorkflowDefaultSettings.builtIn
        let summaries = grantAmountBucketSummaries(
            applications: applications,
            bucket: { settings.amountBucket(for: $0.preferredBudgetAmountValue ?? 0) },
            isGranted: { $0.isGranted },
            grantedAmount: { $0.grantedAmountValue ?? 0 }
        )
        XCTAssertEqual(summaries, [
            GrantAmountBucketSummary(bucket: .below, applicationCount: 1, grantedCount: 1, grantedAmount: 90_000),
            GrantAmountBucketSummary(bucket: .between, applicationCount: 2, grantedCount: 1, grantedAmount: 400_000),
            GrantAmountBucketSummary(bucket: .above, applicationCount: 2, grantedCount: 1, grantedAmount: 1_500_000),
        ])

        var changed = WorkflowDefaultSettings.builtIn
        changed.amountBucketLowerLimit = 400_000
        changed.amountBucketUpperLimit = 3_000_000
        let regrouped = grantAmountBucketSummaries(
            applications: applications,
            bucket: { changed.amountBucket(for: $0.preferredBudgetAmountValue ?? 0) },
            isGranted: { $0.isGranted },
            grantedAmount: { $0.grantedAmountValue ?? 0 }
        )
        XCTAssertEqual(regrouped.map(\.applicationCount), [2, 3, 0])
        XCTAssertEqual(regrouped.map(\.grantedCount), [1, 2, 0])
        XCTAssertEqual(regrouped.map(\.grantedAmount), [90_000, 1_900_000, 0])
    }

    func testAmountGroupSummariesAreEmptyWithoutApplications() {
        let summaries = grantAmountBucketSummaries(
            applications: [],
            bucket: { $0.amountBucket },
            isGranted: { $0.isGranted },
            grantedAmount: { $0.grantedAmountValue ?? 0 }
        )
        XCTAssertEqual(summaries.map(\.bucket), [.below, .between, .above])
        XCTAssertEqual(summaries.map(\.applicationCount), [0, 0, 0])
    }
}
