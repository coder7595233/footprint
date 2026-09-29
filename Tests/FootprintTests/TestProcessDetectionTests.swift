import XCTest
@testable import Footprint

/// F34: tests must never reach the user's real storage, however they are run.
final class TestProcessDetectionTests: XCTestCase {
    private func detects(
        environment: [String: String] = [:],
        processName: String = "Footprint",
        arguments: [String] = ["/Applications/Footprint.app/Contents/MacOS/Footprint"],
        bundlePath: String = "/Applications/Footprint.app",
        xctestIsLoaded: Bool = false
    ) -> Bool {
        TestProcessDetection.isTestProcess(
            environment: environment,
            processName: processName,
            arguments: arguments,
            bundlePath: bundlePath,
            xctestIsLoaded: xctestIsLoaded
        )
    }

    func testTheAppItselfIsNotATestRun() {
        XCTAssertFalse(detects())
    }

    func testEachSignalOnItsOwnIsEnough() {
        for key in TestProcessDetection.environmentKeys {
            XCTAssertTrue(detects(environment: [key: "x"]), key)
        }
        XCTAssertTrue(detects(xctestIsLoaded: true))
        XCTAssertTrue(detects(processName: "xctest"))
        XCTAssertTrue(detects(processName: "swiftpm-testing-helper"))
        XCTAssertTrue(detects(processName: "FootprintPackageTests.xctest"))
        XCTAssertTrue(detects(bundlePath: "/tmp/build/FootprintPackageTests.xctest"))
        XCTAssertTrue(detects(arguments: ["/usr/bin/xctest", "/tmp/build/FootprintPackageTests.xctest"]))
    }

    func testThisProcessIsRecognisedAsATestRun() {
        XCTAssertTrue(TestProcessDetection.isRunningTests)
    }

    func testStorageWithoutOverrideLiesInTheTemporaryFolder() {
        let saved = ProcessInfo.processInfo.environment["FOOTPRINT_STORAGE_DIRECTORY"]
        unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
        defer { if let saved { setenv("FOOTPRINT_STORAGE_DIRECTORY", saved, 1) } }

        let storage = GrantDataStore.storageDirectory
        XCTAssertTrue(
            TestProcessDetection.isInside(storage, anyOf: [FileManager.default.temporaryDirectory]),
            "test storage resolved to \(storage.path)"
        )
        XCTAssertFalse(TestProcessDetection.isInside(storage, anyOf: GrantDataStore.realStorageRoots))
        XCTAssertFalse(TestProcessDetection.isInside(GrantDataStore.databaseURL, anyOf: GrantDataStore.realStorageRoots))
    }

    func testTheExportIsOffDuringTests() {
        XCTAssertFalse(FootprintExportWriter.shared.isEnabled)
    }

    func testRealStorageRootsIncludeTheAppFolder() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let real = applicationSupport.appendingPathComponent("Footprint", isDirectory: true)
        XCTAssertTrue(TestProcessDetection.isInside(real, anyOf: GrantDataStore.realStorageRoots))
        XCTAssertTrue(TestProcessDetection.isInside(
            real.appendingPathComponent("footprint.sqlite"),
            anyOf: GrantDataStore.realStorageRoots
        ))
        XCTAssertFalse(TestProcessDetection.isInside(
            applicationSupport.appendingPathComponent("FootprintOther", isDirectory: true),
            anyOf: GrantDataStore.realStorageRoots
        ))
    }
}
