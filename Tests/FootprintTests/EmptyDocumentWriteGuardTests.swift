import XCTest
@testable import Footprint

final class EmptyDocumentWriteGuardTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testEmptyingARegisterThatHasRecordsIsRefused() throws {
        let stored = ["teaching_assignments": data("[{\"id\":\"a\"},{\"id\":\"b\"},{\"id\":\"c\"}]")]
        let refused = EmptyDocumentWriteGuard.refusedKeys(
            writing: [(key: "teaching_assignments", data: data("[]"))],
            existing: { stored[$0] }
        )
        XCTAssertEqual(refused, ["teaching_assignments"])
    }

    func testEmptyingAnAlreadyEmptyRegisterIsAllowed() throws {
        let stored = ["teaching_assignments": data("[]")]
        let refused = EmptyDocumentWriteGuard.refusedKeys(
            writing: [(key: "teaching_assignments", data: data("[]"))],
            existing: { stored[$0] }
        )
        XCTAssertTrue(refused.isEmpty, "nothing is lost when the register was already empty")
    }

    func testDeletingTheLastRecordOfANonCanonicalDocumentIsAllowed() throws {
        let stored = ["relational_core": data("[{\"id\":\"x\"},{\"id\":\"y\"},{\"id\":\"z\"}]")]
        let refused = EmptyDocumentWriteGuard.refusedKeys(
            writing: [(key: "relational_core", data: data("[]"))],
            existing: { stored[$0] }
        )
        XCTAssertTrue(refused.isEmpty, "derived documents are rebuilt and may legitimately empty")
    }

    func testWritingRecordsIsNeverRefused() throws {
        let stored = ["applications": data("[{\"id\":\"a\"}]")]
        let refused = EmptyDocumentWriteGuard.refusedKeys(
            writing: [(key: "applications", data: data("[{\"id\":\"a\"},{\"id\":\"b\"}]"))],
            existing: { stored[$0] }
        )
        XCTAssertTrue(refused.isEmpty)
    }

    func testObjectDocumentsAreNotTreatedAsEmptyLists() throws {
        let stored = ["metadata": data("{\"a\":1}")]
        let refused = EmptyDocumentWriteGuard.refusedKeys(
            writing: [(key: "metadata", data: data("{}"))],
            existing: { stored[$0] }
        )
        XCTAssertTrue(refused.isEmpty, "the guard only covers lists of records")
    }

    func testDeletingTheLastCoupleOfRecordsIsAllowed() throws {
        let stored = ["cv_other_publications": data("[{\"id\":\"a\"},{\"id\":\"b\"}]")]
        let refused = EmptyDocumentWriteGuard.refusedKeys(
            writing: [(key: "cv_other_publications", data: data("[]"))],
            existing: { stored[$0] }
        )
        XCTAssertTrue(refused.isEmpty, "emptying a two-record register is a plausible deliberate edit")
    }

    func testTheRefusalNamesEveryAffectedRegister() {
        let refusal = EmptyDocumentWriteGuard.Refusal(keys: ["teaching_assignments", "doctoral_candidates"])
        let message = refusal.errorDescription ?? ""
        XCTAssertTrue(message.contains("teaching_assignments"))
        XCTAssertTrue(message.contains("doctoral_candidates"))
    }

    // MARK: - F34: mass replacement

    private func records(_ ids: [String]) -> Data {
        data("[" + ids.map { "{\"id\":\"\($0)\"}" }.joined(separator: ",") + "]")
    }

    func testPlaceholdersOverwritingRealAssignmentsAreRefused() throws {
        // The 2026-09-27 loss: three placeholders written over 27 assignments.
        let stored = ["teaching_assignments": records((1...27).map { "real-\($0)" })]
        let refused = EmptyDocumentWriteGuard.refusedReplacementKeys(
            writing: [(key: "teaching_assignments", data: records(["assignment-1", "assignment-2", "assignment-3"]))],
            existing: { stored[$0] }
        )
        XCTAssertEqual(refused, ["teaching_assignments"])
    }

    func testDeletingAFewRecordsIsAllowed() throws {
        let ids = (1...27).map { "real-\($0)" }
        let stored = ["teaching_assignments": records(ids)]
        let refused = EmptyDocumentWriteGuard.refusedReplacementKeys(
            writing: [(key: "teaching_assignments", data: records(Array(ids.dropFirst(4))))],
            existing: { stored[$0] }
        )
        XCTAssertTrue(refused.isEmpty, "four deletions in one save is ordinary editing")
    }

    func testAddingAndEditingRecordsIsAllowed() throws {
        let ids = (1...10).map { "real-\($0)" }
        let stored = ["projects": records(ids)]
        let refused = EmptyDocumentWriteGuard.refusedReplacementKeys(
            writing: [(key: "projects", data: records(ids + ["new-1", "new-2"]))],
            existing: { stored[$0] }
        )
        XCTAssertTrue(refused.isEmpty)
    }

    func testReplacingASmallRegisterIsLeftToTheEmptyCheck() throws {
        let stored = ["doctoral_candidates": records(["a", "b", "c"])]
        let refused = EmptyDocumentWriteGuard.refusedReplacementKeys(
            writing: [(key: "doctoral_candidates", data: records(["x"]))],
            existing: { stored[$0] }
        )
        XCTAssertTrue(refused.isEmpty, "fewer than five records lost is below the threshold")
    }

    func testDerivedDocumentsAreNotChecked() throws {
        let stored = ["relational_core": records((1...20).map { "r\($0)" })]
        let refused = EmptyDocumentWriteGuard.refusedReplacementKeys(
            writing: [(key: "relational_core", data: records(["other"]))],
            existing: { stored[$0] }
        )
        XCTAssertTrue(refused.isEmpty, "derived documents are rebuilt and may change wholesale")
    }

    func testEmptyWritesAreLeftToTheEmptyCheck() throws {
        let stored = ["applications": records((1...20).map { "a\($0)" })]
        let refused = EmptyDocumentWriteGuard.refusedReplacementKeys(
            writing: [(key: "applications", data: data("[]"))],
            existing: { stored[$0] }
        )
        XCTAssertTrue(refused.isEmpty, "the empty check reports this with its own message")
    }

    func testRecordsWithoutIDsAreNotCompared() {
        XCTAssertNil(EmptyDocumentWriteGuard.recordIDs(data("[{\"name\":\"x\"}]")))
        XCTAssertNil(EmptyDocumentWriteGuard.recordIDs(data("{\"id\":\"x\"}")))
        XCTAssertEqual(EmptyDocumentWriteGuard.recordIDs(data("[{\"id\":\"x\"}]")), ["x"])
    }

    func testTheWorkerRefusesAMassReplacementAndKeepsTheStoredRecords() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmptyDocumentWriteGuardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("footprint.sqlite")

        let real = records((1...27).map { "real-\($0)" })
        try DocumentPersistenceWorker.write(
            [.init(storageKey: "teaching_assignments", data: real)],
            databaseURL: databaseURL
        )
        XCTAssertThrowsError(
            try DocumentPersistenceWorker.write(
                [.init(storageKey: "teaching_assignments", data: records(["assignment-1", "assignment-2", "assignment-3"]))],
                databaseURL: databaseURL
            )
        ) { error in
            XCTAssertTrue(error is EmptyDocumentWriteGuard.ReplacementRefusal)
        }
        let kept = try SQLiteDocumentStore(url: databaseURL).loadData(named: "teaching_assignments")
        XCTAssertEqual(kept.flatMap(EmptyDocumentWriteGuard.recordIDs)?.count, 27)
    }
}

