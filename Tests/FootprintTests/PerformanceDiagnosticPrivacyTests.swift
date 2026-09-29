import Foundation
import XCTest
@testable import Footprint

final class PerformanceDiagnosticPrivacyTests: XCTestCase {
    func testPersistentPerformanceDiagnosticRedactsFixturePIIAndKeepsMetrics() throws {
        let fixtureName = "Ada Fixture Lovelace"
        let fixtureProject = "Secret Lung Study"
        let fixtureJournal = "Private Journal"
        let fixtureEmail = "ada.fixture@example.test"
        let fixtureID = "123E4567-E89B-12D3-A456-426614174000"
        let message = """
            editor-ready application=\(fixtureName) project=\(fixtureProject) \
            journal=\(fixtureJournal) author=\(fixtureEmail) id=\(fixtureID) \
            items=42 duration_ms=17.25
            """

        let sanitized = GrantDataStore.redactedPerformanceDiagnosticMessage(message)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("footprint-diagnostic-privacy-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Data(sanitized.utf8).write(to: temporaryURL, options: .atomic)
        let persisted = try String(contentsOf: temporaryURL, encoding: .utf8)

        for pii in [fixtureName, fixtureProject, fixtureJournal, fixtureEmail, fixtureID] {
            XCTAssertFalse(persisted.contains(pii), "Diagnostic log leaked fixture PII: \(pii)")
        }
        XCTAssertTrue(persisted.contains("application=redacted-"))
        XCTAssertTrue(persisted.contains("project=redacted-"))
        XCTAssertTrue(persisted.contains("journal=redacted-"))
        XCTAssertTrue(persisted.contains("author=redacted-"))
        XCTAssertTrue(persisted.contains("id=redacted-"))
        XCTAssertTrue(persisted.contains("items=42"))
        XCTAssertTrue(persisted.contains("duration_ms=17.25"))
    }

    func testStartupDiagnosticRedactsPathsErrorsAndPII() {
        let storagePath = GrantDataStore.storageDirectory.path
        let homePath = NSHomeDirectory()
        let message = """
            bootstrap:recoveryQuarantineCreated path=\(storagePath)/Recovery Quarantine/x \
            error=The file \(homePath)/Documents/secret.sqlite could not be opened \
            author=Ada Fixture Lovelace
            """

        let sanitized = GrantDataStore.redactedStartupDiagnosticMessage(message)

        XCTAssertFalse(sanitized.contains(storagePath))
        XCTAssertFalse(sanitized.contains(homePath))
        XCTAssertFalse(sanitized.contains("Ada Fixture Lovelace"))
        XCTAssertTrue(sanitized.contains("<storage>/Recovery Quarantine/x"))
        XCTAssertTrue(sanitized.contains("bootstrap:recoveryQuarantineCreated"))
    }

    func testPerformanceDiagnosticDigestIsStableWithoutExposingOriginalValue() {
        let first = GrantDataStore.redactedPerformanceDiagnosticMessage(
            "project-open project=Same Sensitive Project duration_ms=1.0"
        )
        let second = GrantDataStore.redactedPerformanceDiagnosticMessage(
            "project-open project=Same Sensitive Project duration_ms=9.0"
        )

        let firstToken = first.split(separator: " ").first { $0.hasPrefix("project=") }
        let secondToken = second.split(separator: " ").first { $0.hasPrefix("project=") }
        XCTAssertEqual(firstToken, secondToken)
        XCTAssertFalse(first.contains("Same Sensitive Project"))
    }
}
