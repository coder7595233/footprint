import XCTest
@testable import Footprint

/// Round 16 (one colour per status, the "set to ongoing?" question).
/// All names and values below are made up.
final class Round16ColoursTests: XCTestCase {

    private let today = DateParsers.isoDay.date(from: "2026-10-01")!

    private func application(_ id: String = "app-1") -> GrantApplication {
        GrantApplication(id: id, rowNumber: 1, organization: "Invented Fund", grantName: "Invented grant")
    }

    // MARK: Applications

    func testApplicationStatusLabelsMapToTheApprovedTones() {
        func tone(_ label: String, spent: Bool = false, awaits: Bool = false, beforeOpening: Bool = false) -> AppStatusTone {
            AppStatusTones.application(resultLabel: label, isFullySpent: spent, awaitsAppliedAnswer: awaits, isBeforeOpening: beforeOpening)
        }
        XCTAssertEqual(tone("Beviljat"), .done)
        // Round 17: spent funds stay green (done); the fill is the paler
        // green (AppPalette.applicationFill), no longer grey.
        XCTAssertEqual(tone("Beviljat", spent: true), .done, "spent funds are a paler green")
        XCTAssertEqual(tone("Väntar svar"), .pending)
        XCTAssertEqual(tone("Att söka", awaits: true), .warning, "Stängd – sökt?")
        XCTAssertEqual(tone("Avslag"), .negative)
        XCTAssertEqual(tone("Tillbakadragen"), .inactive)
        XCTAssertEqual(tone("Ej sökt"), .inactive)
        XCTAssertEqual(tone("Att söka"), .none)
        XCTAssertEqual(tone(""), .none)
        XCTAssertEqual(tone("Att söka", beforeOpening: true), .notOpen)
    }

    func testApplicationToneFollowsItsDates() {
        var toApply = application()
        toApply.closesOn = "2026-11-01"
        XCTAssertEqual(AppStatusTones.application(toApply, today: today), .none)

        var notOpen = toApply
        notOpen.opensOn = "2026-10-15"
        XCTAssertEqual(AppStatusTones.application(notOpen, today: today), .notOpen)

        var closedUnanswered = application()
        closedUnanswered.closesOn = "2026-09-01"
        XCTAssertEqual(AppStatusTones.application(closedUnanswered, today: today), .warning)

        var waiting = application()
        waiting.appliedOn = "2026-09-01"
        XCTAssertEqual(AppStatusTones.application(waiting, today: today), .pending)

        var granted = application()
        granted.appliedOn = "2026-03-01"
        granted.grantedOn = "2026-06-01"
        XCTAssertEqual(AppStatusTones.application(granted, today: today), .done)
        // Round 17: spent = still done (drawn paler).
        XCTAssertEqual(AppStatusTones.application(granted, isFullySpent: true, today: today), .done)

        var denied = application()
        denied.appliedOn = "2026-03-01"
        denied.deniedOn = "2026-06-01"
        XCTAssertEqual(AppStatusTones.application(denied, today: today), .negative)
    }

    func testOldBadgeTonesUseTheSharedPalette() {
        XCTAssertEqual(statusTone(for: "Beviljat").statusTone, .done)
        XCTAssertEqual(statusTone(for: "Tillbakadragen").statusTone, .inactive, "withdrawn is grey, not red")
        XCTAssertEqual(statusTone(for: "Avslag").statusTone, .negative)
        // Round 17: positiveMuted (a spent grant) is done, drawn paler.
        XCTAssertEqual(BadgeTone.positiveMuted.statusTone, .done)
        for tone in AppStatusTone.allCases {
            XCTAssertEqual(BadgeTone(tone).statusTone, tone)
        }
    }

    // MARK: Publications, conference contributions, reviews, doctoral, tasks

    func testPublicationTones() {
        XCTAssertEqual(AppStatusTones.publication(.published), .done)
        XCTAssertEqual(AppStatusTones.publication(.accepted), .pending, "accepted, not yet published")
        XCTAssertEqual(AppStatusTones.publication(.submitted), .pending)
        XCTAssertEqual(AppStatusTones.publication(.rejected), .negative)
        XCTAssertEqual(AppStatusTones.publication(.planned), .none)
        XCTAssertEqual(AppStatusTones.publication(.inPreparation), .none)
        XCTAssertEqual(publicationStatusIndicatorStyle(for: .accepted), .inProgressSolid)
    }

    func testConferenceContributionTones() {
        XCTAssertEqual(AppStatusTones.conferenceContribution(AppConferenceContributionBadgeStatus.presented), .done)
        XCTAssertEqual(AppStatusTones.conferenceContribution(AppConferenceContributionBadgeStatus.accepted), .pending)
        XCTAssertEqual(AppStatusTones.conferenceContribution(AppConferenceContributionBadgeStatus.submitted), .pending)
        XCTAssertEqual(AppStatusTones.conferenceContribution(AppConferenceContributionBadgeStatus.rejected), .negative)
        XCTAssertEqual(AppStatusTones.conferenceContribution(AppConferenceContributionBadgeStatus.planned), .none)
        XCTAssertEqual(AppStatusTones.conferenceContribution(CVConferenceContributionStatus.presented), .done)
        XCTAssertEqual(AppStatusTones.conferenceContribution(CVConferenceContributionStatus.planned), .none)
    }

    func testExpertAssignmentTones() {
        XCTAssertEqual(AppStatusTones.review(.accepted), .pending)
        XCTAssertEqual(AppStatusTones.review(.overdue), .warning)
        XCTAssertEqual(AppStatusTones.review(.completed), .done)
        XCTAssertEqual(AppStatusTones.review(nil), .none)
        XCTAssertEqual(AppStatusTones.review(.accepted, isDeclined: true), .inactive)
    }

    func testDoctoralAndTaskTones() {
        XCTAssertEqual(AppStatusTones.doctoral(.ongoing), .pending)
        XCTAssertEqual(AppStatusTones.doctoral(.completed), .done)
        XCTAssertEqual(AppStatusTones.doctoral(.endedEarly), .inactive)
        XCTAssertEqual(AppStatusTones.doctoral(.planned), .none)

        XCTAssertEqual(AppStatusTones.task(isCompleted: false, isOverdue: false), .none)
        XCTAssertEqual(AppStatusTones.task(isCompleted: false, isOverdue: true), .warning)
        XCTAssertEqual(AppStatusTones.task(isCompleted: true, isOverdue: true), .done)
    }

    // MARK: Deadlines

    func testDeadlineThresholdsAreSharedAndNeverGreen() {
        XCTAssertEqual(AppStatusTones.closingDeadline(daysRemaining: -1), .negative)
        XCTAssertEqual(AppStatusTones.closingDeadline(daysRemaining: 0), .warning)
        XCTAssertEqual(AppStatusTones.closingDeadline(daysRemaining: 7), .warning)
        XCTAssertEqual(AppStatusTones.closingDeadline(daysRemaining: 8), .pending)
        XCTAssertEqual(AppStatusTones.closingDeadline(daysRemaining: 30), .pending)
        XCTAssertEqual(AppStatusTones.closingDeadline(daysRemaining: 31), .none)

        XCTAssertEqual(AppStatusTones.dispositionDeadline(monthsRemaining: 2, hasPassed: false), .warning)
        XCTAssertEqual(AppStatusTones.dispositionDeadline(monthsRemaining: 3, hasPassed: false), .pending)
        XCTAssertEqual(AppStatusTones.dispositionDeadline(monthsRemaining: 11, hasPassed: false), .pending)
        XCTAssertEqual(AppStatusTones.dispositionDeadline(monthsRemaining: 12, hasPassed: false), .none)
        XCTAssertEqual(AppStatusTones.dispositionDeadline(monthsRemaining: 0, hasPassed: true), .negative)

        let inTwoYears = DateParsers.isoDay.date(from: "2028-10-01")!
        XCTAssertEqual(AppStatusTones.dispositionDeadline(inTwoYears, today: today), .none)
        XCTAssertEqual(DeadlineRingStyle.applicationClosing.tone(forDaysRemaining: 5), .warning)
        XCTAssertEqual(DeadlineRingStyle.remainingFunds.tone(forDaysRemaining: 400), .none)
        for style in [DeadlineRingStyle.closingSoon, .applicationClosing, .repaymentDue, .remainingFunds, .taskDeadline] {
            for days in [0, 10, 100, 1000] {
                XCTAssertNotEqual(style.tone(forDaysRemaining: days), .done)
            }
        }
    }

    // MARK: Projects

    func testProjectStatusRule() {
        XCTAssertEqual(AppStatusTones.project(status: .completed, hasProgress: true), .inactive, "grey, not red")
        XCTAssertEqual(AppStatusTones.project(status: .completed, hasProgress: false), .inactive)
        XCTAssertEqual(AppStatusTones.project(status: .ongoing, hasProgress: true), .done)
        XCTAssertEqual(AppStatusTones.project(status: .ongoing, hasProgress: false), .pending)
        XCTAssertEqual(AppStatusTones.project(status: .planned, hasProgress: true), .pending)
        XCTAssertEqual(AppStatusTones.project(status: .planned, hasProgress: false), .none)
    }

    func testProjectOwnProgressCountsDataCollectionsAndEthics() {
        let empty = ProjectRecord(id: "p-1", nameSv: "Påhittat projekt", nameEn: "Invented project", projectStatus: .planned)
        XCTAssertFalse(AppStatusTones.projectHasOwnProgress(empty))

        var withCollection = empty
        withCollection.dataCollections = [ProjectDataCollection(id: "dc-1", from: "2026-11-01")]
        XCTAssertTrue(AppStatusTones.projectHasOwnProgress(withCollection))

        var withEthics = empty
        withEthics.ethicsBaseApplication = ProjectEthicsApplication(id: "e-1", caseNumber: "0000-00000-00")
        XCTAssertTrue(AppStatusTones.projectHasOwnProgress(withEthics))
    }

    // MARK: "Ska projektet ändras till Pågående?"

    func testNewDataCollectionStartAndEthicsDatesAreTriggers() {
        let before = ProjectRecord(id: "p-1", nameSv: "Påhittat projekt", nameEn: "Invented project", projectStatus: .planned)
        var after = before
        after.dataCollections = [ProjectDataCollection(id: "dc-1", from: "2026-11-01")]
        after.ethicsBaseApplication = ProjectEthicsApplication(id: "e-1", appliedOn: "2026-09-15")
        XCTAssertEqual(
            Set(ProjectOngoingPrompt.newTriggerKeys(previous: before, current: after)),
            ["dataCollection:dc-1", "ethicsApplied:e-1"]
        )

        // The same events saved again are not new.
        XCTAssertTrue(ProjectOngoingPrompt.newTriggerKeys(previous: after, current: after).isEmpty)

        // An approval date is a new event of its own.
        var approved = after
        approved.ethicsBaseApplication.grantedOn = "2026-10-01"
        XCTAssertEqual(ProjectOngoingPrompt.newTriggerKeys(previous: after, current: approved), ["ethicsApproved:e-1"])

        // A data collection without a start date is not a trigger.
        var noStart = before
        noStart.dataCollections = [ProjectDataCollection(id: "dc-2", from: "", to: "2027-01-01")]
        XCTAssertTrue(ProjectOngoingPrompt.newTriggerKeys(previous: before, current: noStart).isEmpty)
    }

    func testGrantedApplicationIsATriggerOnlyWhenItBecomesGrantedForTheProject() {
        let waiting = { () -> GrantApplication in
            var app = application()
            app.appliedOn = "2026-03-01"
            return app
        }()
        var granted = waiting
        granted.grantedOn = "2026-09-01"

        XCTAssertTrue(ProjectOngoingPrompt.becameGrantedForProject(
            previous: waiting, previousProjectID: "p-1", current: granted, currentProjectID: "p-1"
        ))
        XCTAssertFalse(ProjectOngoingPrompt.becameGrantedForProject(
            previous: granted, previousProjectID: "p-1", current: granted, currentProjectID: "p-1"
        ), "already granted for this project")
        XCTAssertTrue(ProjectOngoingPrompt.becameGrantedForProject(
            previous: granted, previousProjectID: "p-0", current: granted, currentProjectID: "p-1"
        ), "a granted application newly linked to the project")
        XCTAssertFalse(ProjectOngoingPrompt.becameGrantedForProject(
            previous: waiting, previousProjectID: "p-1", current: waiting, currentProjectID: "p-1"
        ))
        XCTAssertFalse(ProjectOngoingPrompt.becameGrantedForProject(
            previous: waiting, previousProjectID: nil, current: granted, currentProjectID: nil
        ), "no project, no question")
    }

    func testOnlyPlannedProjectsAreAskedAndNotNowIsRemembered() {
        var planned = ProjectRecord(id: "p-1", nameSv: "Påhittat projekt", nameEn: "Invented project", projectStatus: .planned)
        let keys = ["dataCollection:dc-1", "granted:app-1"]
        XCTAssertEqual(ProjectOngoingPrompt.keysToAsk(project: planned, keys: keys), keys)

        planned.dismissedOngoingPromptKeys = ProjectOngoingPrompt.addingDismissed(["granted:app-1"], to: nil)
        XCTAssertEqual(ProjectOngoingPrompt.keysToAsk(project: planned, keys: keys), ["dataCollection:dc-1"])
        XCTAssertEqual(ProjectOngoingPrompt.keysToAsk(project: planned, keys: ["granted:app-2"]), ["granted:app-2"], "a new event asks again")

        var ongoing = planned
        ongoing.projectStatus = .ongoing
        XCTAssertTrue(ProjectOngoingPrompt.keysToAsk(project: ongoing, keys: keys).isEmpty)

        let completed = ProjectRecord(id: "p-2", nameSv: "Påhittat projekt 2", nameEn: "Invented project 2", projectStatus: .completed)
        XCTAssertTrue(ProjectOngoingPrompt.keysToAsk(project: completed, keys: keys).isEmpty)
    }

    func testDismissedKeysSurviveAnOlderEditorCopy() {
        var stored = ProjectRecord(id: "p-1", nameSv: "Påhittat projekt", nameEn: "Invented project", projectStatus: .planned)
        stored.dismissedOngoingPromptKeys = ["granted:app-1"]
        let olderDraft = ProjectRecord(id: "p-1", nameSv: "Påhittat projekt", nameEn: "Invented project", projectStatus: .planned)
        XCTAssertEqual(ProjectOngoingPrompt.mergedDismissedKeys(stored, olderDraft), ["granted:app-1"])
        XCTAssertNil(ProjectOngoingPrompt.mergedDismissedKeys(olderDraft, olderDraft))
    }

    func testDismissedKeysAreOptionalInSavedProjects() throws {
        let old = ProjectRecord(id: "p-1", nameSv: "Påhittat projekt", nameEn: "Invented project", projectStatus: .planned)
        let oldData = try JSONEncoder().encode(old)
        let oldJSON = String(decoding: oldData, as: UTF8.self)
        XCTAssertFalse(oldJSON.contains("dismissedOngoingPromptKeys"), "nothing is written when empty")
        XCTAssertNil(try JSONDecoder().decode(ProjectRecord.self, from: oldData).dismissedOngoingPromptKeys)

        var answered = old
        answered.dismissedOngoingPromptKeys = ["dataCollection:dc-1"]
        let decoded = try JSONDecoder().decode(ProjectRecord.self, from: JSONEncoder().encode(answered))
        XCTAssertEqual(decoded.dismissedOngoingPromptKeys, ["dataCollection:dc-1"])
    }

    @MainActor
    func testStoreAsksForAPlannedProjectWithANewDataCollection() {
        let before = ProjectRecord(id: "p-1", nameSv: "Påhittat projekt", nameEn: "Invented project", projectStatus: .planned)
        let store = GrantDataStore(projects: [before])
        var after = before
        after.dataCollections = [ProjectDataCollection(id: "dc-1", from: "2026-11-01")]
        store.evaluateOngoingQuestion(previous: before, current: after)
        XCTAssertEqual(store.pendingOngoingQuestion, ProjectOngoingQuestion(projectID: "p-1", triggerKeys: ["dataCollection:dc-1"]))

        store.pendingOngoingQuestion = nil
        var ongoing = after
        ongoing.projectStatus = .ongoing
        store.evaluateOngoingQuestion(previous: before, current: ongoing)
        XCTAssertNil(store.pendingOngoingQuestion, "ongoing projects are never asked")
    }
}
