import XCTest
@testable import Footprint

/// Round 18: a shared task may have a clock time on its deadline day.
/// All task titles and ids below are made up.
final class Round18TaskTimeTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round18TaskTimeTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: Stored data

    func testOldTaskJSONWithoutTimeStillDecodes() throws {
        let json = """
        {"id":"task-old","createdOn":"2026-01-02","updatedOn":"2026-01-02","deadline":"2026-10-15",
         "reminder":"none","comment":"Påhittad uppgift","note":"","participantNames":[],"links":[],
         "agendaText":"","protocolText":""}
        """
        let task = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        XCTAssertEqual(task.id, "task-old")
        XCTAssertEqual(task.deadline, "2026-10-15")
        XCTAssertNil(task.deadlineTime)
        XCTAssertEqual(task.deadlineDisplayText, "2026-10-15")
    }

    func testTaskWithoutTimeDoesNotWriteTheKey() throws {
        let task = TaskItem(id: "task-plain", deadline: "2026-10-15", comment: "Påhittad uppgift")
        let text = String(decoding: try JSONEncoder().encode(task), as: UTF8.self)
        XCTAssertFalse(text.contains("deadlineTime"))
    }

    func testDeadlineTimeRoundTrips() throws {
        let task = TaskItem(
            id: "task-timed",
            deadline: "2026-10-15",
            deadlineTime: "14:00",
            comment: "Påhittad utlysning stänger"
        )
        let decoded = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(decoded, task)
        XCTAssertEqual(decoded.deadlineTime, "14:00")
        XCTAssertEqual(decoded.deadlineDisplayText, "2026-10-15 14:00")
    }

    // MARK: Normalization

    func testDeadlineTimeNormalization() {
        XCTAssertEqual(TaskItem.normalizedDeadlineTime("9"), "09:00")
        XCTAssertEqual(TaskItem.normalizedDeadlineTime("930"), "09:30")
        XCTAssertEqual(TaskItem.normalizedDeadlineTime("9.30"), "09:30")
        XCTAssertEqual(TaskItem.normalizedDeadlineTime("09:30"), "09:30")
        XCTAssertEqual(TaskItem.normalizedDeadlineTime(" 14:05 "), "14:05")
        XCTAssertNil(TaskItem.normalizedDeadlineTime("25:00"))
        XCTAssertNil(TaskItem.normalizedDeadlineTime("abc"))
        XCTAssertNil(TaskItem.normalizedDeadlineTime(""))
        XCTAssertNil(TaskItem.normalizedDeadlineTime(nil))
    }

    func testNormalizeCleansTimeAndDropsItWithoutDate() {
        var timed = TaskItem(id: "a", deadline: "2026-10-15", deadlineTime: "930", comment: "Påhittad")
        timed.normalize()
        XCTAssertEqual(timed.deadlineTime, "09:30")

        var invalid = TaskItem(id: "b", deadline: "2026-10-15", deadlineTime: "99:99", comment: "Påhittad")
        invalid.normalize()
        XCTAssertNil(invalid.deadlineTime)

        var undated = TaskItem(id: "c", deadline: "", deadlineTime: "14:00", comment: "Påhittad")
        undated.normalize()
        XCTAssertNil(undated.deadlineTime)
    }

    // MARK: Calendar

    @MainActor
    func testCalendarTaskEventShowsDeadlineTimeAndSortsByIt() throws {
        let calendar = Calendar.current
        let day = try XCTUnwrap(DateParsers.isoDay.date(from: "2030-03-12"))
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [
            TaskItem(id: "task-late", deadline: "2030-03-12", deadlineTime: "16:00", comment: "Påhittad sen uppgift"),
            TaskItem(id: "task-early", deadline: "2030-03-12", deadlineTime: "9", comment: "Påhittad tidig uppgift"),
            TaskItem(id: "task-allday", deadline: "2030-03-12", comment: "Påhittad heldagsuppgift"),
        ]
        let store = GrantDataStore(metadata: metadata)

        let events = buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: day)),
            displayedMonthEnd: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day)),
            calendar: calendar
        )
        let late = try XCTUnwrap(events.first { $0.id == "central-task:task-late" })
        let early = try XCTUnwrap(events.first { $0.id == "central-task:task-early" })
        let allDay = try XCTUnwrap(events.first { $0.id == "central-task:task-allday" })
        XCTAssertEqual(late.timeText, "16:00")
        XCTAssertEqual(early.timeText, "09:00")
        XCTAssertEqual(allDay.timeText, "")

        let now = try XCTUnwrap(calendar.date(byAdding: .day, value: -30, to: day))
        let sorted = [allDay, late, early].sorted {
            calendarWorkspaceEventSort(
                $0,
                $1,
                today: calendar.startOfDay(for: now),
                now: now,
                calendar: calendar,
                cutoffDateProvider: { _ in nil }
            )
        }
        XCTAssertEqual(sorted.map(\.id), [early.id, late.id, allDay.id])
    }

    func testTimeIsOnlyShownOnTheDeadlineDay() throws {
        let calendar = Calendar.current
        let task = TaskItem(id: "t", deadline: "2030-03-12", deadlineTime: "14:00", comment: "Påhittad")
        let deadlineDay = try XCTUnwrap(DateParsers.isoDay.date(from: "2030-03-12"))
        let laterDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: deadlineDay))
        XCTAssertEqual(task.calendarTimeText(displayDate: deadlineDay, calendar: calendar), "14:00")
        XCTAssertEqual(task.calendarTimeText(displayDate: laterDay, calendar: calendar), "")
    }

    func testTaskWithTimeIsOverdueOnceTheTimeHasPassed() throws {
        let calendar = Calendar.current
        let task = TaskItem(id: "t", deadline: "2030-03-12", deadlineTime: "14:00", comment: "Påhittad")
        let today = try XCTUnwrap(DateParsers.isoDay.date(from: "2030-03-12"))
        let moment = try XCTUnwrap(task.deadlineMoment(calendar: calendar))
        let before = moment.addingTimeInterval(-60)
        let after = moment.addingTimeInterval(60)

        XCTAssertFalse(calendarTaskIsRolledOverPastDue(
            deadline: today,
            displayDate: today,
            isCompleted: false,
            today: today,
            calendar: calendar,
            policy: .rollOverPastDue,
            deadlineMoment: moment,
            now: before
        ))
        XCTAssertTrue(calendarTaskIsRolledOverPastDue(
            deadline: today,
            displayDate: today,
            isCompleted: false,
            today: today,
            calendar: calendar,
            policy: .rollOverPastDue,
            deadlineMoment: moment,
            now: after
        ))
        // Completed tasks and tasks without a time keep the old rule.
        XCTAssertFalse(calendarTaskIsRolledOverPastDue(
            deadline: today,
            displayDate: today,
            isCompleted: true,
            today: today,
            calendar: calendar,
            policy: .rollOverPastDue,
            deadlineMoment: moment,
            now: after
        ))
        XCTAssertFalse(calendarTaskIsRolledOverPastDue(
            deadline: today,
            displayDate: today,
            isCompleted: false,
            today: today,
            calendar: calendar,
            policy: .rollOverPastDue,
            deadlineMoment: nil,
            now: after
        ))
    }

    // MARK: Reminders

    func testReminderComesBeforeAnEarlyDeadlineTime() throws {
        let calendar = Calendar.current
        let day = try XCTUnwrap(DateParsers.isoDay.date(from: "2030-03-12"))
        let usual = calendarTaskReminderFireDate(on: day, calendar: calendar)
        let early = try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day))
        let late = try XCTUnwrap(calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day))

        XCTAssertEqual(calendarTaskReminderFireDate(on: day, calendar: calendar, deadlineMoments: [late]), usual)
        XCTAssertEqual(
            calendarTaskReminderFireDate(on: day, calendar: calendar, deadlineMoments: [late, early]),
            early.addingTimeInterval(-3600)
        )
    }
}
