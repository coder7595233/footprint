import XCTest
@testable import Footprint

/// F7 step 1: the added fields must not disturb a single stored record.
final class Round2cStep1Tests: XCTestCase {
    private func storedCourses() throws -> Data {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("TestData/teaching_courses.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("TestData/teaching_courses.json saknas.")
        }
        return try Data(contentsOf: url)
    }

    func testEveryStoredCourseKeepsItsNameCodeAndProgramme() throws {
        let data = try storedCourses()
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        var courses = try JSONDecoder().decode([TeachingCourse].self, from: data)
        XCTAssertEqual(courses.count, raw.count, "en post försvann i avkodningen")

        for index in courses.indices { courses[index].normalize() }
        XCTAssertEqual(courses.count, raw.count, "en post försvann i normaliseringen")

        // Field by field against the JSON, so a silently emptied value is caught.
        for (stored, course) in zip(raw, courses) {
            let id = stored["id"] as? String ?? ""
            XCTAssertEqual(course.id, id)
            XCTAssertEqual(course.nameSv, stored["nameSv"] as? String ?? "", "nameSv ändrades för \(id)")
            XCTAssertEqual(course.courseCode, stored["courseCode"] as? String ?? "", "courseCode ändrades för \(id)")
            XCTAssertEqual(course.programSv, stored["programSv"] as? String ?? "", "programSv ändrades för \(id)")
        }
    }

    func testTheNewFieldsAreEmptyForEveryStoredCourse() throws {
        var courses = try JSONDecoder().decode([TeachingCourse].self, from: try storedCourses())
        for index in courses.indices { courses[index].normalize() }
        XCTAssertTrue(courses.allSatisfy { $0.programID == nil }, "programID ska vara tomt innan migreringen")
        XCTAssertTrue(courses.allSatisfy { $0.validFrom.isEmpty && $0.validTo.isEmpty })
        // normalize() mirrors an existing courseCode into the list; nothing else.
        for course in courses where course.courseCode.isEmpty {
            XCTAssertTrue(course.courseCodes.isEmpty)
        }
        for course in courses where !course.courseCode.isEmpty {
            XCTAssertEqual(course.courseCodes.map(\.code), [course.courseCode])
        }
    }

    func testSavingAndReadingBackChangesNothingForStoredCourses() throws {
        let data = try storedCourses()
        var courses = try JSONDecoder().decode([TeachingCourse].self, from: data)
        for index in courses.indices { courses[index].normalize() }

        let encoded = try JSONEncoder().encode(courses)
        var again = try JSONDecoder().decode([TeachingCourse].self, from: encoded)
        for index in again.indices { again[index].normalize() }

        XCTAssertEqual(again.count, courses.count)
        XCTAssertEqual(again, courses, "en spara-och-läs-cykel ändrade posterna")
    }

    func testCodeValidityAnswersByDate() {
        var entry = TeachingCourseCodeEntry(code: "8LAA10", validTo: "2025-12-31")
        entry.normalize()
        XCTAssertTrue(entry.covers(day: "2025-09-01"))
        XCTAssertFalse(entry.covers(day: "2026-01-01"))
        XCTAssertFalse(entry.covers(day: ""), "en avslutad kod är inte den aktuella")
    }
}
