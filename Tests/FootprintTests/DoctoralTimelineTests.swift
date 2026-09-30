import XCTest
@testable import Footprint

/// Round 7 (Doktorandvyns tidslinje): the timeline at the top of the doctoral
/// record page. Labels and markers must never overlap, close activities share
/// one marker with a count, and every milestone keeps the status chosen in its
/// popover ("Genomfört" for the planning seminar was lost before).
final class DoctoralTimelineTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoctoralTimelineTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: Label lanes

    func testOverlappingLabelsGetDifferentLanes() {
        // "Antagning 2025-11-21" and "Planeringsseminarium 2026-02-03" start
        // 20 points apart but are 140 points wide: they may not share a lane.
        let spans: [ClosedRange<Double>] = [100...240, 120...300, 500...600]
        let lanes = DoctoralTimelineLayout.lanes(for: spans, gap: 12)
        XCTAssertEqual(lanes, [0, 1, 0])
    }

    func testLabelsInTheSameLaneNeverOverlap() {
        let spans: [ClosedRange<Double>] = [
            0...150, 40...120, 60...260, 130...200, 170...330, 300...360, 305...420, 700...720,
        ]
        let gap = 8.0
        let lanes = DoctoralTimelineLayout.lanes(for: spans, gap: gap)
        XCTAssertEqual(lanes.count, spans.count)
        for i in spans.indices {
            for j in spans.indices where i < j && lanes[i] == lanes[j] {
                let apart = spans[i].upperBound + gap <= spans[j].lowerBound
                    || spans[j].upperBound + gap <= spans[i].lowerBound
                XCTAssertTrue(apart, "spans \(i) and \(j) share lane \(lanes[i]) but overlap")
            }
        }
    }

    func testLanesKeepInputOrderAndReuseFreeLanes() {
        // Given out of order: the result still follows the input.
        let spans: [ClosedRange<Double>] = [400...450, 0...100, 50...150, 200...260]
        XCTAssertEqual(DoctoralTimelineLayout.lanes(for: spans, gap: 10), [0, 0, 1, 0])
        XCTAssertEqual(DoctoralTimelineLayout.lanes(for: [], gap: 10), [])
    }

    func testLabelNearTheRightEdgeEndsAtItsNode() {
        let normal = DoctoralTimelineLayout.labelSpan(nodeX: 100, labelWidth: 120, plotWidth: 600, inset: 9)
        XCTAssertFalse(normal.anchorsTrailing)
        XCTAssertEqual(normal.span, 91...211)

        let nearEdge = DoctoralTimelineLayout.labelSpan(nodeX: 560, labelWidth: 120, plotWidth: 600, inset: 9)
        XCTAssertTrue(nearEdge.anchorsTrailing)
        XCTAssertEqual(nearEdge.span, 449...569)
    }

    // MARK: Activity groups

    func testCloseActivitiesShareOneMarker() {
        // Eight activities within a few points, then one far away.
        let positions: [Double] = [300, 302, 305, 306, 309, 310, 312, 315, 600]
        let groups = DoctoralTimelineLayout.clusters(positions: positions, window: 56)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].count, 8, "the eight close activities become one marker showing 8")
        XCTAssertEqual(groups[1], [8])
    }

    func testGroupMarkersNeverTouch() {
        // Evenly spread activities (one every 7 points) over a long axis.
        let positions = (0..<120).map { Double($0) * 7 }
        let window = 56.0
        let groups = DoctoralTimelineLayout.clusters(positions: positions, window: window)
        XCTAssertEqual(groups.flatMap { $0 }.sorted(), Array(positions.indices), "every activity is in exactly one group")
        let centers = groups.map { group -> Double in
            let values = group.map { positions[$0] }
            return (values.min()! + values.max()!) / 2
        }
        for (left, right) in zip(centers, centers.dropFirst()) {
            XCTAssertGreaterThanOrEqual(right - left, window / 2, "markers up to half the window wide never touch")
        }
    }

    func testClustersAcceptUnsortedPositions() {
        let groups = DoctoralTimelineLayout.clusters(positions: [500, 10, 12, 505], window: 20)
        XCTAssertEqual(groups, [[1, 2], [0, 3]])
        XCTAssertEqual(DoctoralTimelineLayout.clusters(positions: [], window: 20), [])
    }

    // MARK: Year axis

    func testAxisStartsAtTheEarliestItem() {
        XCTAssertEqual(DoctoralTimelineLayout.axisYears([2025, 2033, 2023, 2026]), 2023...2033)
        XCTAssertNil(DoctoralTimelineLayout.axisYears([]))
        XCTAssertNil(DoctoralTimelineLayout.axisYears([1900]))
    }

    func testVeryOldActivitiesDoNotHideTheTimeline() {
        // Before, a span over 25 years hid the whole timeline.
        XCTAssertEqual(DoctoralTimelineLayout.axisYears([1995, 2025, 2033], maxSpan: 25), 2008...2033)
    }

    func testScrollableAxisLeavesRoomToCentreOnToday() {
        // Five visible years around mid-2026 need 2024…2028 at least.
        XCTAssertEqual(
            DoctoralTimelineLayout.scrollableAxisYears([2026], today: 2026.5, visibleYears: 5),
            2024...2029
        )
        // Data further out widens the range; nothing to draw gives nil.
        XCTAssertEqual(
            DoctoralTimelineLayout.scrollableAxisYears([2020, 2033], today: 2026.5, visibleYears: 5),
            2020...2033
        )
        XCTAssertNil(DoctoralTimelineLayout.scrollableAxisYears([], today: 2026.5))
    }

    // MARK: Supervision per semester

    private func day(_ text: String) -> Date {
        DateParsers.isoDay.date(from: text)!
    }

    func testSupervisionSemestersKeepRetendoConfirmation() {
        let periods = [
            DoctoralSupervisionPeriod(from: "2025-02-01", to: "2025-12-31", hoursPerSemester: "5", confirmedInRetendo: false),
            DoctoralSupervisionPeriod(from: "2026-01-10", to: "2026-12-31", hoursPerSemester: "20", confirmedInRetendo: true),
        ]
        let blocks = doctoralSupervisionSemesterBlocks(periods: periods, referenceDate: day("2026-09-29"))
        XCTAssertEqual(blocks.map(\.id), ["2025-1", "2025-2", "2026-1", "2026-2"])
        // Round 12: in proportion to days; a whole half-year gives the full hours.
        XCTAssertEqual(blocks[0].hours, 5 * 150 / 181, accuracy: 0.001, "1 Feb–30 Jun is 150 of 181 days")
        XCTAssertEqual(blocks[1].hours, 5, accuracy: 0.001)
        XCTAssertEqual(blocks[2].hours, 20 * 172 / 181, accuracy: 0.001, "10 Jan–30 Jun is 172 of 181 days")
        XCTAssertEqual(blocks[3].hours, 20, accuracy: 0.001)
        // Not confirmed: needs attention.
        XCTAssertTrue(blocks[0].needsConfirmation)
        XCTAssertTrue(blocks[1].needsConfirmation)
        // Confirmed: fine, also the running semester.
        XCTAssertTrue(blocks[2].isFullyConfirmed)
        XCTAssertFalse(blocks[2].needsConfirmation)
        XCTAssertFalse(blocks[3].needsConfirmation)
    }

    func testOverlappingPeriodsAddUpPerSemester() {
        let periods = [
            DoctoralSupervisionPeriod(from: "2025-01-01", to: "2025-06-30", hoursPerSemester: "10", confirmedInRetendo: true),
            DoctoralSupervisionPeriod(from: "2025-03-01", to: "2025-06-30", hoursPerSemester: "4", confirmedInRetendo: false),
        ]
        let blocks = doctoralSupervisionSemesterBlocks(periods: periods, referenceDate: day("2026-09-29"))
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].hours, 10 + 4.0 * 122 / 181, accuracy: 0.001, "1 Mar–30 Jun is 122 of 181 days")
        XCTAssertEqual(blocks[0].confirmedHours, 10, accuracy: 0.001)
        XCTAssertTrue(blocks[0].needsConfirmation)
    }

    /// Round 12 (user decision 2026-09-30): not confirmed in Retendo is red
    /// also while the semester runs and before it has started, and a period
    /// without hours still shows.
    func testUnconfirmedRunningAndFutureSemestersAreFlagged() {
        let periods = [
            DoctoralSupervisionPeriod(from: "2026-07-01", to: "2027-06-30", hoursPerSemester: "", confirmedInRetendo: false),
        ]
        let blocks = doctoralSupervisionSemesterBlocks(periods: periods, referenceDate: day("2026-09-29"))
        XCTAssertEqual(blocks.map(\.id), ["2026-2", "2027-1"])
        XCTAssertTrue(blocks.allSatisfy(\.needsConfirmation))
        XCTAssertFalse(blocks[0].hasEnded)
        XCTAssertTrue(periods[0].needsRetendoConfirmation)
        XCTAssertFalse(DoctoralSupervisionPeriod(from: "2026-07-01", to: "2027-06-30", hoursPerSemester: "10", confirmedInRetendo: true).needsRetendoConfirmation)
    }

    // MARK: Paper lines

    func testPaperStartIsTheEarliestStoredDate() {
        let paper = PublicationRecord(
            id: "paper-1",
            title: "Invented paper",
            status: PublicationStatus.submitted.rawValue,
            statusTimeline: [
                PublicationStatusEntry(status: PublicationStatus.inPreparation.rawValue, date: "2024-03-01"),
                PublicationStatusEntry(status: PublicationStatus.submitted.rawValue, date: "2025-01-15"),
            ],
            workflowStatusDate: "2024-05-01"
        )
        XCTAssertEqual(doctoralPaperStartDate(paper), day("2024-03-01"))
        XCTAssertNil(doctoralPaperPublishedDate(paper))
        XCTAssertNil(doctoralPaperStartDate(PublicationRecord(id: "paper-2", title: "No dates")))
    }

    func testPublishedPaperUsesItsPublishedDate() {
        let paper = PublicationRecord(
            id: "paper-3",
            title: "Invented published paper",
            status: PublicationStatus.published.rawValue,
            epubDate: "2025-06-01",
            year: "2025",
            statusTimeline: [
                PublicationStatusEntry(status: PublicationStatus.published.rawValue, date: "2025-05-20"),
            ]
        )
        XCTAssertEqual(doctoralPaperPublishedDate(paper), day("2025-05-20"))
    }

    // MARK: Milestone status

    func testStatusWordsAreWritten() {
        XCTAssertEqual(DoctoralMilestoneStatus.preliminary.title(language: .swedish), "Preliminärt")
        XCTAssertEqual(DoctoralMilestoneStatus.booked.title(language: .swedish), "Bokat")
        XCTAssertEqual(DoctoralMilestoneStatus.completed.title(language: .swedish), "Genomfört")
        XCTAssertEqual(DoctoralMilestoneStatus.endedBefore.title(language: .swedish), "Avslutat innan")
    }

    func testEveryStatusReadsBackAsItself() {
        for status in DoctoralMilestoneStatus.allCases {
            let values = status.storedValues
            XCTAssertEqual(
                DoctoralMilestoneStatus.current(preliminary: values.preliminary, outcomeRaw: values.outcomeRaw),
                status
            )
        }
    }

    func testOldCandidateDataHasNoPlanningSeminarOutcome() throws {
        let json = """
        {"id":"old","candidateName":"Gammal","admissionDate":"2025-11-21","planningSeminarDate":"2026-02-03","planningSeminarDatePreliminary":false}
        """
        let candidate = try JSONDecoder().decode(DoctoralCandidateRecord.self, from: Data(json.utf8))
        XCTAssertNil(candidate.admissionOutcomeRaw)
        XCTAssertNil(candidate.planningSeminarOutcomeRaw)
        XCTAssertEqual(
            DoctoralMilestoneStatus.current(preliminary: candidate.planningSeminarDatePreliminary, outcomeRaw: candidate.planningSeminarOutcomeRaw),
            .booked
        )
        let text = try XCTUnwrap(String(data: JSONEncoder().encode(candidate), encoding: .utf8))
        XCTAssertFalse(text.contains("planningSeminarOutcomeRaw"), "nothing new is written until a status is chosen")
        XCTAssertFalse(text.contains("admissionOutcomeRaw"))
    }

    func testCompletedPlanningSeminarSurvivesNormalizeAndEncoding() throws {
        var candidate = DoctoralCandidateRecord(id: "c", planningSeminarDate: "2026-02-03")
        let values = DoctoralMilestoneStatus.completed.storedValues
        candidate.planningSeminarDatePreliminary = values.preliminary
        candidate.planningSeminarOutcomeRaw = values.outcomeRaw
        candidate.admissionOutcomeRaw = values.outcomeRaw
        candidate.normalize()
        let decoded = try JSONDecoder().decode(DoctoralCandidateRecord.self, from: JSONEncoder().encode(candidate))
        XCTAssertEqual(
            DoctoralMilestoneStatus.current(preliminary: decoded.planningSeminarDatePreliminary, outcomeRaw: decoded.planningSeminarOutcomeRaw),
            .completed
        )
        XCTAssertEqual(decoded.admissionOutcomeRaw, DoctoralMilestoneOutcome.completed.rawValue)

        var garbage = DoctoralCandidateRecord(id: "g", planningSeminarOutcomeRaw: "  nonsense ")
        garbage.normalize()
        XCTAssertNil(garbage.planningSeminarOutcomeRaw, "an unknown value is cleared, as for halftime")
    }

    @MainActor
    func testPlanningSeminarMarkedCompletedSurvivesSaveAndReload() throws {
        let original = DoctoralCandidateRecord(
            id: "candidate-emir",
            candidateName: "Erik Exempelsson",
            admissionDate: "2025-11-21",
            planningSeminarDate: "2026-02-03",
            planningSeminarDatePreliminary: false,
            estimatedHalftimeDate: "2028-02-01",
            plannedDisputationDate: "2033-06-30"
        )
        let seeded = GrantDataStore(doctoralCandidates: [original])
        try seeded.persistAll()

        let store = GrantDataStore.loadFromBundle()
        XCTAssertFalse(store.storageWritesBlockedByLoadFailure, store.loadError ?? "")
        var edited = try XCTUnwrap(store.doctoralCandidates.first { $0.id == original.id })
        XCTAssertEqual(
            DoctoralMilestoneStatus.current(preliminary: edited.planningSeminarDatePreliminary, outcomeRaw: edited.planningSeminarOutcomeRaw),
            .booked
        )

        // What the popover does when "Genomfört" is chosen.
        let values = DoctoralMilestoneStatus.completed.storedValues
        edited.planningSeminarDatePreliminary = values.preliminary
        edited.planningSeminarOutcomeRaw = values.outcomeRaw
        store.autosaveDoctoralCandidate(edited, resolveDerivedLinks: false)
        XCTAssertTrue(store.flushPendingPersistenceIfNeeded())

        let saved = try XCTUnwrap(store.doctoralCandidates.first { $0.id == original.id })
        XCTAssertEqual(saved.planningSeminarOutcomeRaw, DoctoralMilestoneOutcome.completed.rawValue)

        let reloaded = GrantDataStore.loadFromBundle()
        let after = try XCTUnwrap(reloaded.doctoralCandidates.first { $0.id == original.id })
        XCTAssertEqual(
            DoctoralMilestoneStatus.current(preliminary: after.planningSeminarDatePreliminary, outcomeRaw: after.planningSeminarOutcomeRaw),
            .completed,
            "Genomfört must still be chosen after saving and opening the data again"
        )
        XCTAssertEqual(after.planningSeminarDate, "2026-02-03")
        XCTAssertEqual(after.admissionDate, "2025-11-21")
        XCTAssertNil(after.admissionOutcomeRaw, "other milestones are untouched")
        XCTAssertEqual(reloaded.doctoralCandidates.count, 1)
    }
}
