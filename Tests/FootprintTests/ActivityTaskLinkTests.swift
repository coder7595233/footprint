import XCTest
@testable import Footprint

/// Round 7, "Aktiviteter och uppgifter kopplas likadant": the shared link rows
/// of the activity and task editors, the "Undervisning" list, the linked
/// lists by id and the doctoral activity suggestions.
final class ActivityTaskLinkTests: XCTestCase {

    // MARK: - Shared link rows

    func testRowTextsBecomeIDsInOrderAndBack() {
        let options = [
            CalendarLinkOption(id: "p1", label: "Alfa"),
            CalendarLinkOption(id: "p2", label: "Beta"),
        ]
        XCTAssertEqual(calendarLinkIDs(forLabels: ["Beta", "", "alfa", "Beta", "Okänd"], options: options), ["p2", "p1"])
        XCTAssertEqual(calendarLinkLabels(forIDs: ["p2", "borttagen", "p1", "p2"], options: options), ["Beta", "Alfa"])
    }

    func testSavingTheRowsReplacesTheLinksOfEachShownKindAndKeepsTheOthers() {
        let links = [
            TaskLink(kind: .project, targetID: "p1"),
            TaskLink(kind: .publication, targetID: "pub1"),
            TaskLink(kind: .congress, targetID: "c1", ownerID: "org1"),
            TaskLink(kind: .review, targetID: "r1"),
            TaskLink(kind: .conferenceContribution, targetID: "cc1"),
            TaskLink(kind: .teachingAssignment, targetID: "a1"),
        ]
        let selection = CalendarTaskLinkSelection(
            projectIDs: ["p2", "p3"],
            organizationIDs: ["o1"],
            teachingCourseIDs: ["k1"],
            doctoralCandidateIDs: ["d1"]
        )
        let listed: [TaskLinkKind: Set<String>] = [
            .project: ["p1", "p2", "p3"],
            .organization: ["o1"],
            .application: [],
            .publication: ["pub1"],
            .teachingCourse: ["k1"],
            .teachingAssignment: ["a1"],
            .doctoralCandidate: ["d1"],
        ]

        let updated = calendarTaskLinksApplyingSelection(links, selection: selection, listedIDs: listed)

        XCTAssertEqual(calendarTaskLinkTargetIDs(updated, kind: .project), ["p2", "p3"])
        XCTAssertEqual(calendarTaskLinkTargetIDs(updated, kind: .organization), ["o1"])
        XCTAssertEqual(calendarTaskLinkTargetIDs(updated, kind: .publication), [], "a removed row removes the link")
        XCTAssertEqual(calendarTaskLinkTargetIDs(updated, kind: .teachingAssignment), [])
        XCTAssertEqual(calendarTaskLinkTargetIDs(updated, kind: .teachingCourse), ["k1"])
        XCTAssertEqual(calendarTaskLinkTargetIDs(updated, kind: .doctoralCandidate), ["d1"])
        XCTAssertTrue(updated.contains(TaskLink(kind: .congress, targetID: "c1", ownerID: "org1")), "congress links are kept")
        XCTAssertTrue(updated.contains(TaskLink(kind: .review, targetID: "r1")), "review links are kept")
        XCTAssertTrue(updated.contains(TaskLink(kind: .conferenceContribution, targetID: "cc1")))
        XCTAssertEqual(CalendarTaskLinkSelection(links: updated).projectIDs, ["p2", "p3"])
    }

    func testALinkToARecordTheRowsCannotShowIsKept() {
        let links = [TaskLink(kind: .project, targetID: "removed-project")]
        let updated = calendarTaskLinksApplyingSelection(
            links,
            selection: CalendarTaskLinkSelection(projectIDs: ["p1"]),
            listedIDs: [.project: ["p1"]]
        )
        XCTAssertEqual(calendarTaskLinkTargetIDs(updated, kind: .project), ["p1", "removed-project"])
        XCTAssertEqual(
            calendarLinkIDsKeepingUnlisted(selected: [], existing: ["p1", "gone"], listedIDs: ["p1"]),
            ["gone"]
        )
    }

    func testReplacingOneKindLeavesOtherKindsUntouched() {
        let links = [
            TaskLink(kind: .project, targetID: "p1"),
            TaskLink(kind: .congress, targetID: "c1", ownerID: "org1"),
        ]
        let updated = calendarTaskLinksReplacingKind(in: links, kind: .project, targetIDs: ["p2", " ", "p2"])
        XCTAssertEqual(updated, [
            TaskLink(kind: .congress, targetID: "c1", ownerID: "org1"),
            TaskLink(kind: .project, targetID: "p2"),
        ])
    }

    // MARK: - "Undervisning": courses with their assignments

    func testTeachingOptionsListEachCourseFollowedByItsAssignments() {
        let courses = [
            TeachingCourse(id: "k-b", name: "Kurs B"),
            TeachingCourse(id: "k-a", name: "Kurs A", termSv: "HT 2025", termEn: "Autumn 2025"),
            TeachingCourse(id: "prog", name: "Programmet", contextType: .programTrack),
        ]
        let assignments = [
            TeachingAssignment(id: "a2", contextID: "k-b", activityName: "Seminarium"),
            TeachingAssignment(id: "a1", contextID: "k-b", activityName: "Föreläsning"),
            TeachingAssignment(id: "a3", contextID: "k-a", activityName: "Examination"),
            TeachingAssignment(id: "a4", activityName: "Fristående"),
        ]

        let options = calendarTeachingLinkOptions(
            courses: courses,
            assignments: assignments,
            courseLabel: { calendarTeachingCourseLabel($0, language: .swedish) },
            assignmentLabel: { $0.activityName }
        )

        XCTAssertEqual(options.map(\.label), [
            "Kurs A (HT 2025)", "Examination",
            "Kurs B", "Föreläsning", "Seminarium",
            "Fristående",
        ])
        XCTAssertEqual(options.map(\.indentLevel), [0, 1, 0, 1, 1, 0])
        XCTAssertFalse(options.contains { $0.label == "Programmet" }, "a programme row without assignments is not listed")
        XCTAssertEqual(calendarLinkOptionDisplayText("Examination", options: options), "\u{2003}\u{2003}Examination")
        XCTAssertEqual(calendarLinkOptionDisplayText("Kurs B", options: options), "Kurs B")

        let chosen = calendarLinkIDs(forLabels: ["Kurs B", "Examination"], options: options)
        let selection = calendarTeachingSelection(fromOptionIDs: chosen)
        XCTAssertEqual(selection.courseIDs, ["k-b"])
        XCTAssertEqual(selection.assignmentIDs, ["a3"])
        XCTAssertEqual(
            calendarTeachingOptionIDs(courseIDs: selection.courseIDs, assignmentIDs: selection.assignmentIDs),
            [calendarTeachingCourseOptionID("k-b"), calendarTeachingAssignmentOptionID("a3")]
        )
    }

    func testTeachingOptionLabelsAreUnique() {
        let options = calendarTeachingLinkOptions(
            courses: [TeachingCourse(id: "k1", name: "Kurs"), TeachingCourse(id: "k2", name: "Kurs")],
            assignments: [],
            courseLabel: { calendarTeachingCourseLabel($0, language: .swedish) },
            assignmentLabel: { $0.activityName }
        )
        XCTAssertEqual(Set(options.map(\.label)).count, 2)
    }

    // MARK: - Activities decode the new course links

    func testActivityWithoutCourseLinksDecodesAndEncodesAsBefore() throws {
        let json = #"{"id":"m1","date":"2027-02-10","title":"Möte"}"#
        let decoded = try JSONDecoder().decode(CalendarMeetingRecord.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.teachingCourseIDs, [])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        XCTAssertNil(encoded?["teachingCourseIDs"], "no new key for activities without a course link")

        var linked = CalendarMeetingRecord(id: "m2", date: "2027-02-10", teachingCourseIDs: [" k1 ", "k1"])
        linked.normalize()
        XCTAssertEqual(linked.teachingCourseIDs, ["k1"])
        let roundTrip = try JSONDecoder().decode(CalendarMeetingRecord.self, from: JSONEncoder().encode(linked))
        XCTAssertEqual(roundTrip.teachingCourseIDs, ["k1"])
    }

    // MARK: - Participants by id

    @MainActor
    func testTaskParticipantsAreLinkedToResearchersByID() throws {
        let anna = PublicationAuthor(id: "au-anna", name: "Anna Andersson", firstName: "Anna", lastName: "Andersson")
        let store = GrantDataStore(publicationAuthors: [anna], skipInitialMigration: true)
        try store.persistAll()
        let names = ["Anna Andersson", "Okänd Person"]
        let ids = store.synchronizedPersonAuthorIDs(existingIDs: [], names: names)
        XCTAssertEqual(ids, ["au-anna"])

        store.saveTaskItem(TaskItem(
            id: "t1",
            deadline: "2027-02-10",
            comment: "Uppgift",
            participantNames: names,
            participantAuthorIDs: ids
        ))
        XCTAssertEqual(store.taskItems.first(where: { $0.id == "t1" })?.participantAuthorIDs, ["au-anna"])
        XCTAssertEqual(store.taskItems.first(where: { $0.id == "t1" })?.participantNames, names)
        _ = store.flushPendingMetadataPersistenceIfNeeded()
    }

    // MARK: - Linked activities and tasks by id

    @MainActor
    func testLinkedListsFollowTheIDLinksOnly() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(id: "m-candidate", date: "2027-02-10", title: "Handledning", doctoralCandidateIDs: ["d1"]),
            CalendarMeetingRecord(id: "m-name-only", date: "2027-02-11", title: "Möte", participantNames: ["Ada Lovelace"]),
            CalendarMeetingRecord(id: "m-assignment", date: "2027-02-12", title: "Föreläsning", teachingAssignmentIDs: ["a1"]),
            CalendarMeetingRecord(id: "m-course", date: "2027-02-13", title: "Kursmöte", teachingCourseIDs: ["k1"]),
        ]
        metadata.taskItems = [
            TaskItem(id: "t-candidate", deadline: "2027-03-01", comment: "Läs manus", links: [TaskLink(kind: .doctoralCandidate, targetID: "d1")]),
            TaskItem(id: "t-course", deadline: "2027-03-02", comment: "Boka sal", links: [TaskLink(kind: .teachingCourse, targetID: "k1")]),
            TaskItem(id: "t-assignment", deadline: "2027-03-03", comment: "Rätta", links: [TaskLink(kind: .teachingAssignment, targetID: "a1")]),
        ]
        let store = GrantDataStore(
            metadata: metadata,
            teachingCourses: [TeachingCourse(id: "k1", name: "Kurs")],
            teachingAssignments: [TeachingAssignment(id: "a1", contextID: "k1", activityName: "Föreläsning")],
            doctoralCandidates: [DoctoralCandidateRecord(id: "d1", candidateName: "Ada Lovelace")],
            skipInitialMigration: true
        )

        func ids(_ scope: CalendarLinkedEventScope, includesTasks: Bool = true) -> Set<String> {
            Set(calendarLinkedEventRows(
                store: store,
                language: .swedish,
                scope: scope,
                includesTasks: includesTasks,
                includesPastEvents: true
            ).map(\.id))
        }

        XCTAssertEqual(ids(.doctoralCandidate("d1")), ["meeting:m-candidate", "teaching-task:t-candidate"])
        XCTAssertEqual(ids(.doctoralCandidate("d1"), includesTasks: false), ["meeting:m-candidate"])
        XCTAssertEqual(ids(.teachingAssignment("a1")), ["meeting:m-assignment", "teaching-task:t-assignment"])
        XCTAssertEqual(
            ids(.teachingCourse("k1")),
            ["meeting:m-assignment", "meeting:m-course", "teaching-task:t-course", "teaching-task:t-assignment"],
            "a course's list includes what is linked to its assignments"
        )
    }

    // MARK: - Activities to link to a doctoral candidate

    func testSuggestionsFollowTheOldRuleAndLeaveOutLinkedActivities() {
        let candidate = DoctoralCandidateRecord(id: "d1", candidateName: "Ada Lovelace", linkedProjectID: "p1")
        let meetings = [
            CalendarMeetingRecord(id: "linked", date: "2027-01-01", projectIDs: ["p1"], doctoralCandidateIDs: ["d1"]),
            CalendarMeetingRecord(id: "legacy-linked", date: "2027-01-02", projectIDs: ["p1"], doctoralCandidateID: "d1"),
            CalendarMeetingRecord(id: "by-project", date: "2027-01-03", projectIDs: ["p1"]),
            CalendarMeetingRecord(id: "by-name", date: "2027-01-04", participantNames: ["Ada Lovelace"]),
            CalendarMeetingRecord(id: "unrelated", date: "2027-01-05", participantNames: ["Någon Annan"], projectIDs: ["p2"]),
        ]

        let suggestions = computeDoctoralActivityLinkSuggestions(
            candidates: [candidate],
            meetings: meetings,
            meetingProjectIDs: { $0.projectIDs },
            candidateTakesPart: { meeting, candidate in meeting.participantNames.contains(candidate.candidateName) }
        )

        XCTAssertEqual(suggestions.map(\.meetingID), ["by-name", "by-project"], "newest first, linked ones left out")
        XCTAssertEqual(suggestions.first?.matchedByName, true)
        XCTAssertEqual(suggestions.last?.matchedByProject, true)
        XCTAssertTrue(suggestions.allSatisfy { $0.candidateID == "d1" })
    }

    @MainActor
    func testLinkingASuggestionAddsTheCandidateByIDAndHidingRemembersIt() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(id: "m1", date: "2027-01-03", title: "Projektmöte", projectIDs: ["p1"]),
            CalendarMeetingRecord(id: "m2", date: "2027-01-04", title: "Seminarium", participantNames: ["Ada Lovelace"]),
        ]
        let store = GrantDataStore(
            metadata: metadata,
            doctoralCandidates: [DoctoralCandidateRecord(id: "d1", candidateName: "Ada Lovelace", linkedProjectID: "p1")],
            skipInitialMigration: true
        )
        try store.persistAll()

        let suggestions = store.doctoralActivityLinkSuggestions()
        XCTAssertEqual(Set(suggestions.map(\.meetingID)), ["m1", "m2"])
        let meetingCountBefore = store.calendarMeetingRecords.count

        let first = try XCTUnwrap(suggestions.first(where: { $0.meetingID == "m1" }))
        XCTAssertTrue(store.linkSuggestedDoctoralActivity(first))
        let linked = try XCTUnwrap(store.calendarMeetingRecords.first(where: { $0.id == "m1" }))
        XCTAssertEqual(linked.doctoralCandidateIDs, ["d1"])
        XCTAssertEqual(linked.projectIDs, ["p1"], "nothing else on the activity changes")
        XCTAssertEqual(store.calendarMeetingRecords.count, meetingCountBefore)
        XCTAssertFalse(store.linkSuggestedDoctoralActivity(first), "linking twice changes nothing")
        XCTAssertEqual(store.doctoralActivityLinkSuggestions().map(\.meetingID), ["m2"])

        let second = try XCTUnwrap(store.doctoralActivityLinkSuggestions().first)
        XCTAssertTrue(store.hideDataQualityWarning(second))
        XCTAssertTrue(store.doctoralActivityLinkSuggestions().isEmpty)
        XCTAssertEqual(store.doctoralActivityLinkSuggestions(includeHidden: true).map(\.meetingID), ["m2"])
        XCTAssertNil(store.calendarMeetingRecords.first(where: { $0.id == "m2" })?.doctoralCandidateIDs.first, "hiding never links")
        _ = store.flushPendingMetadataPersistenceIfNeeded()
    }

    // MARK: - Reminder badges

    @MainActor
    func testTasksLinkedToACourseOrDoctoralCandidateCountOnTheTeachingTab() {
        let store = GrantDataStore(
            teachingCourses: [TeachingCourse(id: "k1", name: "Kurs")],
            doctoralCandidates: [DoctoralCandidateRecord(id: "d1", candidateName: "Ada Lovelace")],
            skipInitialMigration: true
        )
        let router = CalendarTaskReminderBadgeRouter(store: store)
        let targets = router.targets(links: [
            TaskLink(kind: .teachingCourse, targetID: "k1"),
            TaskLink(kind: .doctoralCandidate, targetID: "d1"),
            TaskLink(kind: .doctoralCandidate, targetID: "missing"),
        ])
        XCTAssertEqual(targets, [.teachingCourse("k1"), .doctoralCandidate("d1")])

        let counts = calendarTaskReminderBadgeCounts(entries: [
            CalendarTaskReminderEntry(id: "e1", displayDate: Date(), title: "Uppgift", context: "", badgeTargets: targets)
        ])
        XCTAssertEqual(counts.teachingCourseCounts, ["k1": 1])
        XCTAssertEqual(counts.doctoralCandidateCounts, ["d1": 1])
        XCTAssertEqual(counts.teachingBadgeCount, 2)
    }
}
