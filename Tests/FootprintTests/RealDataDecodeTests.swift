import XCTest
@testable import Footprint

/// F31: the other tests build records in memory, so they only ever exercise
/// records that already have every current field. These read the real registers
/// as they sit on disk and require the count to survive decode, normalize,
/// encode and decode again.
///
/// In the public repository TestData/ holds fictional records with the same
/// files and fields; the real registers live in the private footprint-data
/// repository, where the same tests run against them.
///
/// Adding a field to a stored record is a migration, not an extension. On
/// 2026-09-27 such a change made TeachingCourse fail to decode; 21 courses
/// became 2, the teaching registers emptied, and the next save wrote that to
/// disk. A test of this shape fails on the first count and stops the build.
final class RealDataDecodeTests: XCTestCase {
    private func payload(_ name: String) throws -> Data {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("TestData/\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("TestData/\(name).json saknas — kör exporten i notebooken först.")
        }
        return try Data(contentsOf: url)
    }

    private func storedCount(_ data: Data) throws -> Int {
        let value = try JSONSerialization.jsonObject(with: data)
        return (value as? [Any])?.count ?? -1
    }

    /// decode -> normalize -> encode -> decode, counting at every step.
    private func check<T: Codable>(_ name: String, as type: T.Type, normalize: (inout T) -> Void) throws {
        let data = try payload(name)
        let expected = try storedCount(data)
        XCTAssertGreaterThan(expected, 0, "\(name): underlaget är tomt, exportera om det")

        var records = try JSONDecoder().decode([T].self, from: data)
        XCTAssertEqual(records.count, expected, "\(name): avkodningen tappade poster")

        for index in records.indices { normalize(&records[index]) }
        XCTAssertEqual(records.count, expected, "\(name): normaliseringen tappade poster")

        let reencoded = try JSONEncoder().encode(records)
        let roundTripped = try JSONDecoder().decode([T].self, from: reencoded)
        XCTAssertEqual(roundTripped.count, expected, "\(name): posterna överlevde inte en spara-och-läs-cykel")
    }

    func testTeachingCoursesSurvivesDecodeNormalizeEncode() throws {
        try check("teaching_courses", as: TeachingCourse.self, normalize: { $0.normalize() })
    }

    func testTeachingAssignmentsSurvivesDecodeNormalizeEncode() throws {
        try check("teaching_assignments", as: TeachingAssignment.self, normalize: { $0.normalize() })
    }

    func testTeachingComponentsSurvivesDecodeNormalizeEncode() throws {
        try check("teaching_components", as: TeachingComponent.self, normalize: { $0.normalize() })
    }

    func testTeachingFormatsSurvivesDecodeNormalizeEncode() throws {
        try check("teaching_formats", as: TeachingFormatOption.self, normalize: { $0.normalize() })
    }

    func testDoctoralCandidatesSurvivesDecodeNormalizeEncode() throws {
        try check("doctoral_candidates", as: DoctoralCandidateRecord.self, normalize: { $0.normalize() })
    }

    func testApplicationsSurvivesDecodeNormalizeEncode() throws {
        try check("applications", as: GrantApplication.self, normalize: { _ in })
    }

    func testOrganizationsSurvivesDecodeNormalizeEncode() throws {
        try check("organizations", as: OrganizationRecord.self, normalize: { _ in })
    }

    func testProjectsSurvivesDecodeNormalizeEncode() throws {
        try check("projects", as: ProjectRecord.self, normalize: { _ in })
    }

    func testPublicationRecordsSurvivesDecodeNormalizeEncode() throws {
        try check("publication_records", as: PublicationRecord.self, normalize: { $0.normalize() })
    }

    func testPublicationAuthorsSurvivesDecodeNormalizeEncode() throws {
        try check("publication_authors", as: PublicationAuthor.self, normalize: { $0.normalize() })
    }

    func testCongressesSurvivesDecodeNormalizeEncode() throws {
        try check("congresses", as: StoredCongressRecord.self, normalize: { _ in })
    }

    func testCvReviewEntriesSurvivesDecodeNormalizeEncode() throws {
        try check("cv_review_entries", as: CVReviewEntry.self, normalize: { $0.normalize() })
    }

    func testCalendarMeetingRecordsSurvivesDecodeNormalizeEncode() throws {
        try check("calendar_meeting_records", as: CalendarMeetingRecord.self, normalize: { $0.normalize() })
    }
}
