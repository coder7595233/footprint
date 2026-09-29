import XCTest
import SwiftUI
import SQLite3
@testable import Footprint

private struct FocusLoopProbeView: View {
    @State private var first = "a"
    @State private var second = "a"
    @State private var text = "2026"
    @State private var standardText = "Journal"
    @State private var person = ""
    @State private var flag = false

    var body: some View {
        HStack {
            AppMenuSelectionField(selection: $first, options: [("A", "a"), ("B", "b")])
                .frame(width: 120)
            AppMenuSelectionField(selection: $second, options: [("A", "a"), ("B", "b")])
                .frame(width: 120)
            CommitFormattingTextField(placeholder: "Year", text: $text, formatter: { $0 })
                .frame(width: 100)
                .appTextInputChrome()
            TextField("Standard", text: $standardText)
                .appTextInputChrome()
                .frame(width: 100)
            Button("Accessory") {}
                .buttonStyle(.plain)
                .formKeyboardNavigable()
            AutocompleteSelectionField(
                text: $person,
                options: ["Ada Lovelace"],
                placeholder: "Person",
                onCommit: {}
            )
            .frame(width: 140)
            HStack(spacing: 0) {
                ForEach(["D", "C", "B", "A"], id: \.self) { title in
                    Button(title) {}
                        .buttonStyle(.plain)
                        .focusable(false)
                        .frame(width: 25, height: 30)
                }
            }
            .background {
                AppCompoundFieldFocusBridge(
                    onFocusChange: { _ in },
                    onMoveLeft: {},
                    onMoveRight: {}
                )
            }
            Toggle("Flag", isOn: $flag)
                .appCheckboxStyle()
        }
        .padding()
    }
}

final class StabilityTests: XCTestCase {
    private var isolatedStorageDirectory: URL!

    override func setUpWithError() throws {
        XCTAssertTrue(
            GrantDataStore.waitForPendingPeriodicBackupWork(timeout: 10),
            "Periodic backup work from the previous test did not finish."
        )
        isolatedStorageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FootprintTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: isolatedStorageDirectory)
        try FileManager.default.createDirectory(at: isolatedStorageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", isolatedStorageDirectory.path, 1)
    }

    override func tearDownWithError() throws {
        XCTAssertTrue(
            GrantDataStore.waitForPendingPeriodicBackupWork(timeout: 10),
            "Periodic backup work did not finish before test storage cleanup."
        )
        unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
        if let isolatedStorageDirectory {
            try? FileManager.default.removeItem(at: isolatedStorageDirectory)
        }
        isolatedStorageDirectory = nil
    }

    private func relativeLuminance(of color: NSColor) -> CGFloat {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        return (0.299 * converted.redComponent) + (0.587 * converted.greenComponent) + (0.114 * converted.blueComponent)
    }

    func testCalendarTravelModesUseDistinctTransportSymbols() {
        XCTAssertEqual(CalendarTravelMode.flight.calendarSystemImageName, "airplane")
        XCTAssertEqual(CalendarTravelMode.train.calendarSystemImageName, "train.side.front.car")
        XCTAssertEqual(CalendarTravelMode.bus.calendarSystemImageName, "bus")
        XCTAssertEqual(CalendarTravelMode.car.calendarSystemImageName, "car")
        XCTAssertEqual(CalendarTravelMode.boat.calendarSystemImageName, "ferry")
        XCTAssertEqual(
            Set(CalendarTravelMode.allCases.map(\.calendarSystemImageName)).count,
            CalendarTravelMode.allCases.count
        )
    }

    @MainActor
    func testUndoManagerKeepsAtLeastTwentySteps() {
        let store = GrantDataStore(skipInitialMigration: true)
        XCTAssertGreaterThanOrEqual(store.undoManager.levelsOfUndo, 20)
    }

    @MainActor
    func testReferenceRepairPreservesUnmatchedProductionValues() {
        var application = GrantApplication(
            id: "application-unmatched",
            rowNumber: 1,
            organization: "External free-text funder",
            grantName: "Grant"
        )
        application.applicationManager = "External manager"
        application.projectType = "External project"
        application.coApplicants = ["External collaborator"]
        let publication = PublicationRecord(
            id: "publication-unmatched",
            projectName: "External project",
            title: "Publication",
            journal: "External journal",
            year: "2025",
            authorNames: ["External author"]
        )
        let store = GrantDataStore(
            applications: [application],
            publicationRecords: [publication],
            skipInitialMigration: true
        )

        _ = store.repairStoredReferenceIntegrity()

        XCTAssertEqual(store.applications.first?.organization, "External free-text funder")
        XCTAssertEqual(store.applications.first?.applicationManager, "External manager")
        XCTAssertEqual(store.applications.first?.projectType, "External project")
        XCTAssertEqual(store.applications.first?.coApplicants, ["External collaborator"])
        XCTAssertEqual(store.publications.first?.authorNames, ["External author"])
        XCTAssertEqual(store.publications.first?.journal, "External journal")
        XCTAssertEqual(store.publications.first?.projectName, "External project")
        XCTAssertFalse(store.repairStoredReferenceIntegrity(), "A second repair pass must be idempotent.")
    }

    func testCalendarTaskPrimaryLinkEditPreservesAdditionalAndUnrelatedLinks() {
        let links = [
            TaskLink(kind: .project, targetID: "project-1"),
            TaskLink(kind: .project, targetID: "project-2"),
            TaskLink(kind: .doctoralCandidate, targetID: "candidate-1"),
        ]

        let updated = calendarTaskLinksReplacingPrimary(
            in: links,
            kind: .project,
            targetID: "project-3"
        )

        XCTAssertEqual(
            updated,
            [
                TaskLink(kind: .project, targetID: "project-3"),
                TaskLink(kind: .project, targetID: "project-2"),
                TaskLink(kind: .doctoralCandidate, targetID: "candidate-1"),
            ]
        )
    }

    @MainActor
    func testStableIDDeletionPreservesDuplicateNamedRecords() {
        let organizations = [
            OrganizationRecord(id: "organization-1", nameSv: "Duplicate", nameEn: "First"),
            OrganizationRecord(id: "organization-2", nameSv: "Duplicate", nameEn: "Second"),
        ]
        let projects = [
            ProjectRecord(id: "project-1", nameSv: "Duplicate", nameEn: "First"),
            ProjectRecord(id: "project-2", nameSv: "Duplicate", nameEn: "Second"),
        ]
        let store = GrantDataStore(
            organizations: organizations,
            projects: projects,
            skipInitialMigration: true
        )

        store.deleteOrganization(id: "organization-1")
        store.deleteProject(id: "project-1")

        XCTAssertEqual(store.organizations.map(\.id), ["organization-2"])
        XCTAssertEqual(store.projects.map(\.id), ["project-2"])
    }

    @MainActor
    func testStandardTextEditingContextMenuKeepsClipboardCommandsWithCustomItems() {
        let labels = AppTextEditingSupport.MenuLabels(
            cut: "Cut",
            copy: "Copy",
            paste: "Paste",
            selectAll: "Select All"
        )
        let custom = NSMenuItem(title: "Uncertain", action: nil, keyEquivalent: "")

        let menu = AppTextEditingSupport.standardContextMenu(labels: labels, additionalItems: [custom])
        let titles = menu.items.map(\.title)

        XCTAssertTrue(titles.contains("Cut"))
        XCTAssertTrue(titles.contains("Copy"))
        XCTAssertTrue(titles.contains("Paste"))
        XCTAssertTrue(titles.contains("Select All"))
        XCTAssertEqual(titles.last, "Uncertain")
    }

    @MainActor
    func testTextEditingSupportPreparesPlainUndoableFieldEditor() {
        let textView = NSTextView()
        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true

        AppTextEditingSupport.prepareEditor(textView)

        XCTAssertTrue(textView.allowsUndo)
        XCTAssertFalse(textView.isRichText)
        XCTAssertFalse(textView.importsGraphics)
        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(textView.isAutomaticSpellingCorrectionEnabled)
        XCTAssertTrue(textView.menu?.items.contains { $0.action == #selector(NSText.copy(_:)) } == true)
    }

    @MainActor
    func testTextEditingStandardBehaviorChecksCoverEditableAndLockedFields() {
        let editableChecks = AppTextEditingSupport.standardBehaviorChecks(isEditable: true)
        let lockedChecks = AppTextEditingSupport.standardBehaviorChecks(isEditable: false)

        XCTAssertTrue(editableChecks.allSatisfy(\.isPassing))
        XCTAssertTrue(lockedChecks.allSatisfy(\.isPassing))
        XCTAssertTrue(editableChecks.contains { $0.id == "copy" })
        XCTAssertTrue(lockedChecks.contains { $0.id == "copy" })
    }

    func testLockedFieldVisibilityHidesEmptyReadOnlyValues() {
        XCTAssertTrue(AppLockedFieldVisibility.shouldShow(isLocked: false, value: ""))
        XCTAssertFalse(AppLockedFieldVisibility.shouldShow(isLocked: true, value: nil))
        XCTAssertFalse(AppLockedFieldVisibility.shouldShow(isLocked: true, value: "   "))
        XCTAssertTrue(AppLockedFieldVisibility.shouldShow(isLocked: true, value: "2026-06-13"))

        XCTAssertFalse(AppLockedFieldVisibility.shouldShow(isLocked: true, values: [nil, "  "]))
        XCTAssertTrue(AppLockedFieldVisibility.shouldShow(isLocked: true, values: [nil, "Data"]))

        let rows = ["", "A", "  "]
        XCTAssertEqual(
            AppLockedFieldVisibility.visibleItems(rows, isLocked: true) { $0.trimmedOrNil == nil },
            ["A"]
        )
        XCTAssertEqual(
            AppLockedFieldVisibility.visibleItems(rows, isLocked: false) { $0.trimmedOrNil == nil },
            rows
        )
    }

    func testYearFieldParserKeepsOnlyUnambiguousFourDigitYears() {
        XCTAssertEqual(AppFieldParsers.canonicalYear(" 2026 "), "2026")
        XCTAssertEqual(AppFieldParsers.canonicalYear("2026-07-01"), "2026")
        XCTAssertEqual(AppFieldParsers.canonicalYear("26"), "26")
        XCTAssertEqual(AppFieldParsers.canonicalYear("20255"), "20255")
        XCTAssertEqual(AppFieldParsers.canonicalYear("2026/2027"), "2026/2027")
        XCTAssertFalse(AppFieldValidators.optionalYear("2026").state.isInvalid)
        XCTAssertTrue(AppFieldValidators.optionalYear("20255").state.isInvalid)
        XCTAssertTrue(AppFieldValidators.optionalYear("2026/2027").state.isInvalid)
    }

    @MainActor
    func testStandardCommitFieldCommandsCommitTabAndCancelEscape() {
        let field = NSTextField(string: "2026-06-12")
        let textView = NSTextView()
        var committedValues: [String] = []
        var didCancel = false

        XCTAssertTrue(
            AppTextEditingSupport.handleCommitFieldCommand(
                #selector(NSResponder.insertTab(_:)),
                field: field,
                textView: textView,
                commit: { committedValues.append($0.stringValue) },
                cancel: { _ in didCancel = true }
            )
        )
        XCTAssertEqual(committedValues, ["2026-06-12"])

        XCTAssertTrue(
            AppTextEditingSupport.handleCommitFieldCommand(
                #selector(NSResponder.insertBacktab(_:)),
                field: field,
                textView: textView,
                commit: { committedValues.append($0.stringValue) },
                cancel: { _ in didCancel = true }
            )
        )
        XCTAssertEqual(committedValues, ["2026-06-12", "2026-06-12"])

        XCTAssertTrue(
            AppTextEditingSupport.handleCommitFieldCommand(
                #selector(NSResponder.cancelOperation(_:)),
                field: field,
                textView: textView,
                commit: { committedValues.append($0.stringValue) },
                cancel: { _ in didCancel = true }
            )
        )
        XCTAssertTrue(didCancel)
    }

    @MainActor
    func testFormKeyboardRoutingDistinguishesTabFromBacktab() {
        XCTAssertEqual(
            AppFormKeyboardRouting.focusDirection(for: #selector(NSResponder.insertTab(_:))),
            .forward
        )
        XCTAssertEqual(
            AppFormKeyboardRouting.focusDirection(for: #selector(NSResponder.insertBacktab(_:))),
            .backward
        )
        XCTAssertNil(
            AppFormKeyboardRouting.focusDirection(for: #selector(NSResponder.insertNewline(_:)))
        )
    }

    @MainActor
    func testRenewedFormControlsHaveOneOrderedKeyViewAndNativeFocusPulse() {
        AppRuntime.chromeStyleOverrideForTesting = .renewed
        defer { AppRuntime.chromeStyleOverrideForTesting = nil }
        let hostingView = NSHostingView(rootView: FocusLoopProbeView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        window.recalculateKeyViewLoop()

        func keyViewDescriptions(in view: NSView) -> [String] {
            let own = view.canBecomeKeyView
                ? ["\(type(of: view)) frame=\(view.convert(view.bounds, to: hostingView))"]
                : []
            return own + view.subviews.flatMap(keyViewDescriptions)
        }
        let descriptions = keyViewDescriptions(in: hostingView)
        XCTAssertEqual(descriptions.count, 7, descriptions.joined(separator: "\n"))

        func allViews(in view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(allViews)
        }
        let keyViews = allViews(in: hostingView).filter(\.canBecomeKeyView)
        let expectedTypes = [
            "FocusablePopUpButton",
            "FocusablePopUpButton",
            "CommitFormattingNSTextField",
            "AppKitTextField",
            "AutocompleteNSTextField",
            "FocusView",
            "FocusableCheckboxButton",
        ]
        var current = keyViews.first
        var actualTypes: [String] = []
        for _ in expectedTypes.indices {
            guard let view = current else { break }
            actualTypes.append(String(describing: type(of: view)))
            current = view.nextValidKeyView
        }
        XCTAssertEqual(actualTypes, expectedTypes)

        guard let firstMenu = keyViews.first, keyViews.indices.contains(1) else {
            return XCTFail("Missing menu key views")
        }
        XCTAssertTrue(window.makeFirstResponder(firstMenu))
        firstMenu.insertTab(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(window.firstResponder === keyViews[1])

        guard let standardField = keyViews.first(where: { String(describing: type(of: $0)) == "AppKitTextField" }) as? NSTextField,
              let autocompleteAfterStandard = keyViews.first(where: { String(describing: type(of: $0)) == "AutocompleteNSTextField" }) as? NSTextField else {
            return XCTFail("Missing standard text-field sequence")
        }
        XCTAssertTrue(window.makeFirstResponder(standardField))
        XCTAssertTrue(AppFormKeyboardRouting.moveFocus(from: standardField, direction: .forward))
        XCTAssertTrue(
            window.firstResponder === autocompleteAfterStandard
                || autocompleteAfterStandard.currentEditor() === window.firstResponder
        )

        guard let autocomplete = keyViews.first(where: { String(describing: type(of: $0)) == "AutocompleteNSTextField" }) as? NSTextField else {
            return XCTFail("Missing autocomplete key view")
        }
        XCTAssertTrue(window.makeFirstResponder(autocomplete))
        autocomplete.selectText(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertNotNil(autocomplete.layer?.sublayers?.first(where: { $0.name == AppFocusPulse.layerName }))
    }

    @MainActor
    func testKeyboardFocusPulseUsesOnePointOverlayAndPreservesUnderlyingChrome() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 32))
        view.wantsLayer = true
        view.layer?.borderWidth = 2
        view.layer?.borderColor = NSColor.systemRed.cgColor

        AppFocusPulse.setFocused(true, on: view)

        let focusLayer = try XCTUnwrap(
            view.layer?.sublayers?.first(where: { $0.name == AppFocusPulse.layerName }) as? CAShapeLayer
        )
        XCTAssertFalse(focusLayer.isHidden)
        XCTAssertEqual(focusLayer.lineWidth, 1)
        XCTAssertEqual(view.layer?.borderWidth, 2)
        XCTAssertEqual(view.layer?.borderColor, NSColor.systemRed.cgColor)

        AppFocusPulse.setFocused(false, on: view)
        XCTAssertTrue(focusLayer.isHidden)
    }

    @MainActor
    func testUndoRedoRoutingUsesNativeTextUndoOnlyForSeparateTextUndoManagers() {
        final class UndoTarget: NSObject {}
        let storeUndoManager = UndoManager()
        let textUndoManager = UndoManager()
        let target = UndoTarget()
        textUndoManager.registerUndo(withTarget: target) { _ in }

        XCTAssertTrue(
            AppUndoRedoRouting.shouldUseNativeTextUndoRedo(
                isEditableTextResponder: true,
                textUndoManager: textUndoManager,
                storeUndoManager: storeUndoManager,
                isRedo: false
            )
        )
        XCTAssertFalse(
            AppUndoRedoRouting.shouldUseNativeTextUndoRedo(
                isEditableTextResponder: true,
                textUndoManager: storeUndoManager,
                storeUndoManager: storeUndoManager,
                isRedo: false
            )
        )
        XCTAssertFalse(
            AppUndoRedoRouting.shouldUseNativeTextUndoRedo(
                isEditableTextResponder: false,
                textUndoManager: textUndoManager,
                storeUndoManager: storeUndoManager,
                isRedo: false
            )
        )
    }

    @MainActor
    func testNoopUndoableChangeDoesNotCreateUndoStep() {
        let store = GrantDataStore(skipInitialMigration: true)

        store.saveTeachingCourse(TeachingCourse(id: "missing-course", name: "Missing course"))

        XCTAssertFalse(store.undoManager.canUndo)
    }

    @MainActor
    func testMetadataUserPreferencesAreUndoable() {
        let store = GrantDataStore(skipInitialMigration: true)

        store.setFooterStatusBarVisible(true)
        XCTAssertTrue(store.showsFooterStatusBar)
        XCTAssertTrue(store.undoManager.canUndo)

        store.undoManager.undo()

        XCTAssertFalse(store.showsFooterStatusBar)
    }

    @MainActor
    func testHiddenAutomaticCalendarEventsAreUndoable() {
        let store = GrantDataStore(skipInitialMigration: true)

        store.setAutomaticCalendarEventHidden("deadline:application-1", hidden: true)
        XCTAssertTrue(store.isAutomaticCalendarEventHidden("deadline:application-1"))
        XCTAssertTrue(store.undoManager.canUndo)

        store.undoManager.undo()

        XCTAssertFalse(store.isAutomaticCalendarEventHidden("deadline:application-1"))
    }

    @MainActor
    func testArchivedApplicationUndoRestoresRecord() {
        let applicationID = "55555555-5555-4555-8555-555555555555"
        let application = GrantApplication(
            id: applicationID,
            rowNumber: 1,
            organization: "Funder",
            grantName: "Grant"
        )
        let store = GrantDataStore(applications: [application], skipInitialMigration: true)

        store.deleteApplication(id: applicationID)
        XCTAssertTrue(store.applications.isEmpty)
        XCTAssertTrue(store.undoManager.canUndo)

        store.undoManager.undo()

        XCTAssertEqual(store.applications.map(\.id), [applicationID])
    }

    @MainActor
    func testUndoRevealRequestTargetsEditedApplication() {
        var application = GrantApplication(
            id: "application-1",
            rowNumber: 1,
            organization: "Funder",
            grantName: "Grant"
        )
        let store = GrantDataStore(applications: [application], skipInitialMigration: true)
        application.grantName = "Updated grant"

        store.save(application: application)
        store.undoManager.undo()

        guard case let .route(route) = store.undoRevealRequest?.target.destination else {
            return XCTFail("Expected undo to reveal the edited application.")
        }
        XCTAssertEqual(route.destination, .applications)
        XCTAssertEqual(route.recordID, "application-1")
    }

    @MainActor
    func testSeparateApplicationAutosavesUndoOneStepAtATime() {
        var application = GrantApplication(
            id: "application-1",
            rowNumber: 1,
            organization: "Funder",
            grantName: "Grant"
        )
        let store = GrantDataStore(applications: [application], skipInitialMigration: true)

        application.coApplicants = ["Anna Andersson"]
        store.autosave(application: application)
        application.maxAmount = "100000"
        store.autosave(application: application)

        store.undoManager.undo()
        XCTAssertEqual(store.undoRevealRequest?.target.fieldKey, "maxAmount")
        XCTAssertEqual(store.applications.first?.coApplicants, ["Anna Andersson"])
        XCTAssertNil(store.applications.first?.maxAmount)

        store.undoManager.undo()
        XCTAssertEqual(store.undoRevealRequest?.target.fieldKey, "coApplicants")
        XCTAssertEqual(store.applications.first?.coApplicants, [])
        XCTAssertNil(store.applications.first?.maxAmount)
    }

    @MainActor
    func testSeparatePublicationAuthorAutosavesUndoOneStepAtATime() {
        var author = PublicationAuthor(id: "author-1", name: "Anna Andersson")
        let store = GrantDataStore(publicationAuthors: [author], skipInitialMigration: true)

        author.orcid = "0000-0002-1825-0097"
        store.autosavePublicationAuthor(author, previousName: "Anna Andersson")
        author.title = "Professor"
        store.autosavePublicationAuthor(author, previousName: "Anna Andersson")

        store.undoManager.undo()
        XCTAssertEqual(store.undoRevealRequest?.target.fieldKey, "title")
        XCTAssertEqual(store.publicationAuthors.first?.orcid, "0000-0002-1825-0097")
        XCTAssertEqual(store.publicationAuthors.first?.title, "")

        store.undoManager.undo()
        XCTAssertEqual(store.undoRevealRequest?.target.fieldKey, "orcid")
        XCTAssertEqual(store.publicationAuthors.first?.orcid, "")
        XCTAssertEqual(store.publicationAuthors.first?.title, "")
    }

    @MainActor
    func testSeparateProjectAutosavesUndoOneStepAtATime() {
        var project = ProjectRecord(id: "project-1", nameSv: "Project", nameEn: "Project")
        let store = GrantDataStore(projects: [project], skipInitialMigration: true)

        project.collaboratorNames = ["Anna Andersson"]
        store.autosaveProjectRecord(project, previousID: "project-1")
        project.projectStatus = .completed
        store.autosaveProjectRecord(project, previousID: "project-1")

        store.undoManager.undo()
        XCTAssertEqual(store.undoRevealRequest?.target.fieldKey, "status")
        XCTAssertEqual(store.projects.first?.collaboratorNames, ["Anna Andersson"])
        XCTAssertEqual(store.projects.first?.projectStatus, .ongoing)

        store.undoManager.undo()
        XCTAssertEqual(store.undoRevealRequest?.target.fieldKey, "collaborators")
        XCTAssertEqual(store.projects.first?.collaboratorNames, [])
        XCTAssertEqual(store.projects.first?.projectStatus, .ongoing)
    }

    @MainActor
    func testSeparatePublicationAutosavesUndoOneStepAtATime() async {
        var publication = PublicationRecord(id: "publication-1", title: "Original title", year: "2025")
        let store = GrantDataStore(publicationRecords: [publication], skipInitialMigration: true)
        store.savePublication(publication, silently: true)

        publication.publicationType = "Article"
        store.autosavePublication(publication)
        XCTAssertTrue(store.flushPendingPersistenceIfNeeded())
        publication.year = "2026"
        store.autosavePublication(publication)
        XCTAssertTrue(store.flushPendingPersistenceIfNeeded())

        store.undoManager.undo()
        XCTAssertTrue(store.flushPendingPersistenceIfNeeded())
        await Task.yield()
        XCTAssertEqual(store.undoRevealRequest?.target.fieldKey, "year")
        XCTAssertEqual(store.publications.first?.publicationType, "Article")
        XCTAssertEqual(store.publications.first?.year, "2025")

        store.undoManager.undo()
        XCTAssertTrue(store.flushPendingPersistenceIfNeeded())
        await Task.yield()
        XCTAssertEqual(store.undoRevealRequest?.target.fieldKey, "type")
        XCTAssertEqual(store.publications.first?.publicationType, "")
        XCTAssertEqual(store.publications.first?.year, "2025")
    }

    func testPerformanceDiagnosticsSummaryExtractsSlowestCachesAndFreezes() {
        let logText = """
        [2026-06-02 10:00:00] cache-profile scope=calendar cache=visible-window items=120 duration_ms=41.25 days=77
        [2026-06-02 10:00:01] cache-profile scope=researcher-detail cache=linked-primary items=30 duration_ms=12.50 author=author-1
        [2026-06-02 10:00:02] main-thread-freeze duration_ms=85.00 context=calendar-scroll
        [2026-06-02 10:00:03] persist-encode scope=autosave total_ms=18.75 bytes=1200
        """

        let summary = GrantDataStore.performanceDiagnosticsSummaryText(language: .swedish, logText: logText)

        XCTAssertTrue(summary.contains("calendar/visible-window"))
        XCTAssertTrue(summary.contains("researcher-detail/linked-primary"))
        XCTAssertTrue(summary.contains("calendar-scroll"))
        XCTAssertTrue(summary.contains("persist-encode"))
    }

    func testPerformanceDiagnosticsSummaryBudgetStaysSmall() {
        let logLine = "[2026-06-02 10:00:00] cache-profile scope=calendar cache=visible-window items=120 duration_ms=41.25 days=77"
        let logText = Array(repeating: logLine, count: 1_000).joined(separator: "\n")
        let startedAt = CFAbsoluteTimeGetCurrent()

        _ = GrantDataStore.performanceDiagnosticsSummaryText(language: .english, logText: logText)

        let durationMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        XCTAssertLessThan(durationMs, 100)
    }

    func testPerformanceDiagnosticsStatusItemsClassifySlowOperations() {
        let logText = [
            "[2026-06-02 10:00:00] view-ready scope=applications id=1 ready_ms=820.0",
            "[2026-06-02 10:00:01] cache-profile scope=calendar cache=visible-window items=120 duration_ms=90.0",
            "[2026-06-02 10:00:02] main-thread-lag delay_ms=640.0 context=route=applications",
            "[2026-06-02 10:00:03] persist scope=applications total_ms=1650.0"
        ].joined(separator: "\n")

        let items = GrantDataStore.performanceDiagnosticsStatusItems(language: .swedish, logText: logText)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        XCTAssertEqual(byID["rows"]?.value, "4")
        XCTAssertEqual(byID["views"]?.tone, "warning")
        XCTAssertEqual(byID["lag"]?.tone, "critical")
        XCTAssertEqual(byID["persistence"]?.tone, "critical")
    }

    @MainActor
    func testPublicationAuthorContributionSummaryDoesNotDoubleCountNameVariants() {
        let author = PublicationAuthor(
            id: "author-1",
            name: "Anna Andersson",
            nameVariants: ["A Andersson"]
        )
        let records = [
            PublicationRecord(
                id: "publication-1",
                title: "Shared title",
                authorNames: ["Anna Andersson", "A Andersson"]
            ),
            PublicationRecord(
                id: "publication-2",
                title: "Shared title",
                authorNames: ["A Andersson"]
            ),
        ]
        let store = GrantDataStore(skipInitialMigration: true)

        store.applyLoadedPublicationState(
            GrantDataStore.LoadedPublicationState(
                authors: [author],
                journals: [],
                records: records
            )
        )

        let contribution = store.publicationAuthors.first?.publications.first
        XCTAssertEqual(contribution?.title, "Shared title")
        XCTAssertEqual(contribution?.count, 2)
    }

    func testBackupPreviewDeltaLinesShowRestoreImpact() {
        let current = GrantDataStore.BackupHealthReport(
            generatedAt: "2026-06-02T10:00:00Z",
            interfaceLanguage: AppLanguage.swedish.rawValue,
            lastSelectedTab: "applications",
            applicationCount: 10,
            applicationsToApplyWithCloseDate: 2,
            managerCount: 3,
            managerNames: [],
            projectCount: 4,
            projectCollaboratorCount: 8,
            salarySourceCount: 1,
            salaryCoveragePeriodCount: 5,
            publicationAuthorCount: 6,
            publicationRecordCount: 7
        )
        let selected = GrantDataStore.BackupHealthReport(
            generatedAt: "2026-06-01T10:00:00Z",
            interfaceLanguage: AppLanguage.swedish.rawValue,
            lastSelectedTab: "applications",
            applicationCount: 8,
            applicationsToApplyWithCloseDate: 1,
            managerCount: 4,
            managerNames: [],
            projectCount: 5,
            projectCollaboratorCount: 8,
            salarySourceCount: 2,
            salaryCoveragePeriodCount: 3,
            publicationAuthorCount: 6,
            publicationRecordCount: 9
        )

        let lines = GrantDataStore.backupPreviewDeltaLines(language: .swedish, current: current, selected: selected)

        XCTAssertTrue(lines.contains("Förändring vid återställning:"))
        XCTAssertTrue(lines.contains("Ansökningar: 8 (-2)"))
        XCTAssertTrue(lines.contains("Medelsförvaltare: 4 (+1)"))
        XCTAssertTrue(lines.contains("Publikationer: 9 (+2)"))
    }

    func testOrganizationTimelineDefaultsOpenForNonEmployers() {
        XCTAssertTrue(organizationTimelineExpandedByDefault(for: [.grantProvider]))
        XCTAssertTrue(organizationTimelineExpandedByDefault(for: [.fundManager]))
        XCTAssertTrue(organizationTimelineExpandedByDefault(for: [.association]))
    }

    func testOrganizationTimelineDefaultsClosedForEmployers() {
        XCTAssertFalse(organizationTimelineExpandedByDefault(for: [.employer]))
        XCTAssertFalse(organizationTimelineExpandedByDefault(for: [.association, .employer]))
    }

    @MainActor
    func testCongressNavigationDoesNotReplayAnOlderClickOverANewerClick() {
        let first = OrganizationCongress(id: "congress-1", title: "First")
        let second = OrganizationCongress(id: "congress-2", title: "Second")
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organization",
            nameEn: "Organization",
            congresses: [first, second]
        )
        let store = GrantDataStore(organizations: [organization], skipInitialMigration: true)

        store.openRouteToCongress(organizationID: organization.id, congressID: first.id)
        let firstRequest = try! XCTUnwrap(store.pendingCongressRoute)
        store.openRouteToCongress(organizationID: organization.id, congressID: second.id)
        let secondRequest = try! XCTUnwrap(store.pendingCongressRoute)

        XCTAssertNotEqual(firstRequest.requestID, secondRequest.requestID)
        XCTAssertFalse(firstRequest.targetsSameRecord(as: secondRequest))

        // A delayed handler for the first click must not consume the second.
        store.consumePendingCongressRoute(firstRequest)
        XCTAssertEqual(store.pendingCongressRoute?.requestID, secondRequest.requestID)
        XCTAssertEqual(store.route?.requestID, secondRequest.requestID)
        XCTAssertEqual(store.route?.recordID, "organizationCongress:organization-1:congress-2")
    }

    func testAppRouteRepeatedTargetHasDistinctNavigationRequestIdentity() {
        let first = AppRoute(recordID: "project-1", destination: .projects)
        let second = AppRoute(recordID: "project-1", destination: .projects)

        XCTAssertNotEqual(first.requestID, second.requestID)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.targetsSameRecord(as: second))
    }

    @MainActor
    func testUndoRevealRequestTargetsCalendarMeeting() {
        let meeting = CalendarMeetingRecord(
            id: "meeting-1",
            date: "2027-02-10",
            title: "Activity"
        )
        let store = GrantDataStore(skipInitialMigration: true)

        store.autosaveCalendarMeetingRecords([meeting])
        store.undoManager.undo()

        guard case let .calendar(dayString, eventSource) = store.undoRevealRequest?.target.destination else {
            return XCTFail("Expected undo to reveal the edited calendar meeting.")
        }
        XCTAssertEqual(dayString, "2027-02-10")
        XCTAssertEqual(eventSource, .meeting("meeting-1"))
    }

    @MainActor
    func testUndoRevealRequestTargetsAutosavedCongress() {
        let congress = OrganizationCongress(
            id: "congress-1",
            title: "Original congress",
            from: "2027-03-10"
        )
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organization",
            nameEn: "Organization",
            congresses: [congress]
        )
        let store = GrantDataStore(organizations: [organization], skipInitialMigration: true)
        var updatedCongress = congress
        updatedCongress.title = "Updated congress"

        store.autosaveOrganization(
            id: organization.id,
            nameSv: organization.nameSv,
            nameEn: organization.nameEn,
            addressLine: organization.addressLine,
            postalCode: organization.postalCode,
            city: organization.city,
            country: organization.country,
            category: organization.category,
            roles: organization.roles,
            note: organization.note,
            websiteURL: organization.websiteURL,
            phoneNumber: organization.phoneNumber,
            organizationNumber: organization.organizationNumber,
            vatNumber: organization.vatNumber,
            employerContacts: organization.employerContacts,
            flag: organization.flag,
            membershipFrom: organization.membershipFrom,
            membershipTo: organization.membershipTo,
            congresses: [updatedCongress],
            projectTasks: organization.projectTasks,
            salaryCalculator: organization.salaryCalculator,
            actionName: "Redigera kongress"
        )
        store.undoManager.undo()

        guard case let .route(route) = store.undoRevealRequest?.target.destination else {
            return XCTFail("Expected undo to reveal the edited congress.")
        }
        XCTAssertEqual(route.destination, .congresses)
        XCTAssertEqual(route.recordID, "organizationCongress:organization-1:congress-1")
        XCTAssertEqual(store.undoRevealRequest?.target.fieldKey, "title")
    }

    @MainActor
    func testUndoRevealRequestTargetsAutosavedCongressVenue() {
        let congress = OrganizationCongress(
            id: "congress-1",
            title: "Congress",
            from: "2027-03-10",
            venue: "Original venue"
        )
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organization",
            nameEn: "Organization",
            congresses: [congress]
        )
        let store = GrantDataStore(organizations: [organization], skipInitialMigration: true)
        var updatedCongress = congress
        updatedCongress.venue = "Updated venue"

        store.autosaveOrganization(
            id: organization.id,
            nameSv: organization.nameSv,
            nameEn: organization.nameEn,
            addressLine: organization.addressLine,
            postalCode: organization.postalCode,
            city: organization.city,
            country: organization.country,
            category: organization.category,
            roles: organization.roles,
            note: organization.note,
            websiteURL: organization.websiteURL,
            phoneNumber: organization.phoneNumber,
            organizationNumber: organization.organizationNumber,
            vatNumber: organization.vatNumber,
            employerContacts: organization.employerContacts,
            flag: organization.flag,
            membershipFrom: organization.membershipFrom,
            membershipTo: organization.membershipTo,
            congresses: [updatedCongress],
            projectTasks: organization.projectTasks,
            salaryCalculator: organization.salaryCalculator,
            actionName: "Redigera plats på kongress"
        )
        store.undoManager.undo()

        guard case let .route(route) = store.undoRevealRequest?.target.destination else {
            return XCTFail("Expected undo to reveal the edited congress venue.")
        }
        XCTAssertEqual(route.destination, .congresses)
        XCTAssertEqual(route.recordID, "organizationCongress:organization-1:congress-1")
        XCTAssertEqual(store.undoRevealRequest?.target.fieldKey, "venue")
    }

    @MainActor
    func testUndoRevealRequestTargetsAutosavedCongressParticipants() {
        let congress = OrganizationCongress(
            id: "congress-1",
            title: "Congress",
            from: "2027-03-10",
            participantNames: ["Original Researcher"]
        )
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organization",
            nameEn: "Organization",
            congresses: [congress]
        )
        let store = GrantDataStore(organizations: [organization], skipInitialMigration: true)
        var updatedCongress = congress
        updatedCongress.participantNames = ["Original Researcher", "New Researcher"]

        store.autosaveOrganization(
            id: organization.id,
            nameSv: organization.nameSv,
            nameEn: organization.nameEn,
            addressLine: organization.addressLine,
            postalCode: organization.postalCode,
            city: organization.city,
            country: organization.country,
            category: organization.category,
            roles: organization.roles,
            note: organization.note,
            websiteURL: organization.websiteURL,
            phoneNumber: organization.phoneNumber,
            organizationNumber: organization.organizationNumber,
            vatNumber: organization.vatNumber,
            employerContacts: organization.employerContacts,
            flag: organization.flag,
            membershipFrom: organization.membershipFrom,
            membershipTo: organization.membershipTo,
            congresses: [updatedCongress],
            projectTasks: organization.projectTasks,
            salaryCalculator: organization.salaryCalculator,
            actionName: "Redigera medverkande forskare på kongress"
        )
        store.undoManager.undo()

        guard case let .route(route) = store.undoRevealRequest?.target.destination else {
            return XCTFail("Expected undo to reveal the edited congress participants.")
        }
        XCTAssertEqual(route.destination, .congresses)
        XCTAssertEqual(route.recordID, "organizationCongress:organization-1:congress-1")
        XCTAssertEqual(store.undoRevealRequest?.target.fieldKey, "participants")
    }

    func testCalendarMeetingRecordDecodesLegacyTeachingAssignmentLinkAsNil() throws {
        let data = Data("""
        {
          "id": "meeting-1",
          "date": "2027-02-10",
          "startTime": "10:00",
          "endTime": "12:00",
          "title": "Activity"
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(CalendarMeetingRecord.self, from: data)
        XCTAssertNil(decoded.teachingAssignmentID)
        XCTAssertTrue(decoded.mediaAppearanceIDs.isEmpty)

        var linked = decoded
        linked.mediaAppearanceIDs = ["media-2", "media-1", "media-2"]
        linked.normalize()
        XCTAssertEqual(linked.mediaAppearanceIDs, ["media-2", "media-1"])
        let roundTripped = try JSONDecoder().decode(
            CalendarMeetingRecord.self,
            from: JSONEncoder().encode(linked)
        )
        XCTAssertEqual(roundTripped.mediaAppearanceIDs, ["media-2", "media-1"])
    }

    func testPublicationAuthorNameVariantsDoNotInventMissingLastName() {
        var author = PublicationAuthor(
            id: "author-1",
            name: "",
            firstName: "Ada",
            lastName: "Lovelace",
            nameVariantRows: [
                PublicationAuthorNameVariant(firstName: "Ada", lastName: "")
            ]
        )

        author.normalize()

        XCTAssertEqual(author.nameVariantRows.map(\.displayName), ["Ada"])
        XCTAssertFalse(author.nameVariantRows.contains { $0.lastName == "Lovelace" })
    }

    @MainActor
    func testNewPublicationAuthorStartsWithoutLocalizedPlaceholderNameParts() {
        let store = GrantDataStore(skipInitialMigration: true)

        let id = store.addPublicationAuthor()
        let author = store.publicationAuthors.first { $0.id == id }

        XCTAssertEqual(author?.name, "")
        XCTAssertEqual(author?.firstName, "")
        XCTAssertEqual(author?.lastName, "")
        XCTAssertEqual(author?.nameVariantRows, [])
    }

    @MainActor
    func testFirstAddedPublicationAuthorBecomesCurrentUserInOneUndoStep() {
        let store = GrantDataStore(skipInitialMigration: true)
        XCTAssertTrue(store.publicationAuthors.isEmpty)
        XCTAssertNil(store.metadata.currentUserAuthorID)

        let firstID = store.addPublicationAuthor()

        XCTAssertEqual(store.metadata.currentUserAuthorID, firstID)
        XCTAssertEqual(store.currentUserAuthor()?.id, firstID)

        let secondID = store.addPublicationAuthor()

        XCTAssertNotEqual(secondID, firstID)
        XCTAssertEqual(store.metadata.currentUserAuthorID, firstID)
        XCTAssertEqual(store.currentUserAuthor()?.id, firstID)

        store.undoManager.undo()
        XCTAssertEqual(store.publicationAuthors.map(\.id), [firstID])
        XCTAssertEqual(store.metadata.currentUserAuthorID, firstID)

        store.undoManager.undo()
        XCTAssertTrue(store.publicationAuthors.isEmpty)
        XCTAssertNil(store.metadata.currentUserAuthorID)
    }

    @MainActor
    func testAddedPublicationAuthorReplacesMissingCurrentUserButKeepsValidOne() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-deleted"
        let first = PublicationAuthor(id: "author-a", name: "Anna Andersson", firstName: "Anna", lastName: "Andersson")
        let second = PublicationAuthor(id: "author-b", name: "Bertil Berg", firstName: "Bertil", lastName: "Berg")
        let store = GrantDataStore(
            metadata: metadata,
            publicationAuthors: [first, second],
            skipInitialMigration: true
        )

        let newID = store.addPublicationAuthor()
        XCTAssertEqual(store.metadata.currentUserAuthorID, newID)

        store.setCurrentUserAuthor(id: "author-a")
        _ = store.addPublicationAuthor()
        XCTAssertEqual(store.metadata.currentUserAuthorID, "author-a")
    }

    @MainActor
    func testAddedPublicationAuthorPinsLoneImplicitCurrentUser() {
        let only = PublicationAuthor(id: "author-only", name: "Anna Andersson", firstName: "Anna", lastName: "Andersson")
        let store = GrantDataStore(publicationAuthors: [only], skipInitialMigration: true)
        XCTAssertEqual(store.currentUserAuthor()?.id, "author-only")

        _ = store.addPublicationAuthor()

        XCTAssertEqual(store.metadata.currentUserAuthorID, "author-only")
        XCTAssertEqual(store.currentUserAuthor()?.id, "author-only")
    }

    @MainActor
    func testAMACitationBoldsCurrentUserNameFormsOnly() throws {
        func boldedRanges(_ patterns: [String], in text: String) -> [String] {
            patterns.flatMap { pattern -> [String] in
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
                return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
                    .map { (text as NSString).substring(with: $0.range) }
            }
        }

        let emptyStore = GrantDataStore(skipInitialMigration: true)
        XCTAssertEqual(emptyStore.currentUserAMAAuthorBoldPatterns(), [])

        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-pontus"
        let currentUser = PublicationAuthor(
            id: "author-pontus",
            name: "Pontus af Lindholm",
            firstName: "Pontus",
            lastName: "af Lindholm",
            nameVariantRows: [PublicationAuthorNameVariant(firstName: "Pontus A.", lastName: "Lindholm (Test)")]
        )
        let other = PublicationAuthor(id: "author-falk", name: "Fredrik Falk", firstName: "Fredrik", lastName: "Falk")
        let store = GrantDataStore(metadata: metadata, publicationAuthors: [currentUser, other], skipInitialMigration: true)
        let patterns = store.currentUserAMAAuthorBoldPatterns()

        XCTAssertEqual(boldedRanges(patterns, in: "Falk F, af Lindholm P*, Andersson A"), ["af Lindholm P*"])
        XCTAssertEqual(boldedRanges(patterns, in: "Af Lindholm P, Falk F"), ["Af Lindholm P"])
        // Regex metacharacters in a stored variant are matched literally.
        XCTAssertEqual(boldedRanges(patterns, in: "Falk F, Lindholm (Test) PA"), ["Lindholm (Test) PA"])
        // A longer initial string belongs to someone else.
        XCTAssertEqual(boldedRanges(patterns, in: "af Lindholm PK, Falk F"), [])
    }

    @MainActor
    func testJournalCatalogIsReadFromReferenceFolderBeforeBundle() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("footprint-journal-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
        defer {
            unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
            try? FileManager.default.removeItem(at: storageDirectory)
        }

        // Without a catalog in Reference/ the loader must not fail; it falls
        // back to a bundled copy only if a build carries one.
        _ = GrantDataStore.bundledPublicationJournals()

        let reference = GrantDataStore.referenceDataDirectory
        try FileManager.default.createDirectory(at: reference, withIntermediateDirectories: true)
        let plain = try JSONEncoder().encode([PublicationJournal(id: "catalog-plain", name: "Plain Catalog Journal")])
        try plain.write(to: reference.appendingPathComponent(GrantDataStore.journalCatalogFileName))

        XCTAssertEqual(GrantDataStore.journalCatalogCandidateURLs().first?.url.deletingLastPathComponent().lastPathComponent, "Reference")
        XCTAssertEqual(GrantDataStore.bundledPublicationJournals().map(\.id), ["catalog-plain"])

        let compressedJSON = try JSONEncoder().encode([PublicationJournal(id: "catalog-zlib", name: "Compressed Catalog Journal")])
        let compressed = try (compressedJSON as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: reference.appendingPathComponent(GrantDataStore.journalCatalogCompressedFileName))

        XCTAssertEqual(GrantDataStore.bundledPublicationJournals().map(\.id), ["catalog-zlib"])
    }

    @MainActor
    func testPublicationAuthorRenameDropsNewAuthorPlaceholderIntermediateNameVariant() {
        var previous = PublicationAuthor(
            id: "author-1",
            name: "",
            firstName: "test",
            lastName: "författare",
            affiliations: [PublicationAffiliation(isPrimary: true)]
        )
        previous.normalize()
        let store = GrantDataStore(publicationAuthors: [previous], skipInitialMigration: true)
        var updated = previous
        updated.lastName = "test"

        store.autosavePublicationAuthor(updated, previousName: previous.name)

        XCTAssertEqual(store.publicationAuthors.first?.name, "test test")
        XCTAssertEqual(store.publicationAuthors.first?.nameVariantRows, [])
    }

    @MainActor
    func testPublicationAuthorRenameDropsIncompleteIntermediateNameVariant() {
        var previous = PublicationAuthor(
            id: "author-1",
            name: "",
            firstName: "test",
            lastName: "",
            affiliations: [PublicationAffiliation(isPrimary: true)]
        )
        previous.normalize()
        let store = GrantDataStore(publicationAuthors: [previous], skipInitialMigration: true)
        var updated = previous
        updated.lastName = "test"

        store.autosavePublicationAuthor(updated, previousName: previous.name)

        XCTAssertEqual(store.publicationAuthors.first?.name, "test test")
        XCTAssertEqual(store.publicationAuthors.first?.nameVariantRows, [])
    }

    func testCalendarMeetingTeachingAssignmentLinksBackfillAndDeduplicate() throws {
        let legacyJSON = """
        {
          "id": "meeting-1",
          "date": "2027-02-10",
          "title": "Teaching",
          "teachingAssignmentID": "assignment-legacy"
        }
        """.data(using: .utf8)!

        var decoded = try JSONDecoder().decode(CalendarMeetingRecord.self, from: legacyJSON)
        decoded.normalize()

        XCTAssertEqual(decoded.teachingAssignmentIDs, ["assignment-legacy"])
        XCTAssertEqual(decoded.teachingAssignmentID, "assignment-legacy")

        var record = CalendarMeetingRecord(
            date: "2027-02-10",
            title: "Teaching",
            teachingAssignmentIDs: ["assignment-1", " assignment-2 ", "assignment-1"]
        )
        record.normalize()

        XCTAssertEqual(record.teachingAssignmentIDs, ["assignment-1", "assignment-2"])
        XCTAssertEqual(record.teachingAssignmentID, "assignment-1")
    }

    @MainActor
    func testCalendarMeetingSavePublishesImmediateCalendarContentUpdate() {
        let original = CalendarMeetingRecord(
            id: "meeting-1",
            date: "2027-02-10",
            title: "Original activity"
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [original]
        let store = GrantDataStore(metadata: metadata, skipInitialMigration: true)
        var updated = original
        updated.date = "2027-02-11"

        store.autosaveCalendarMeetingRecords([updated])

        XCTAssertEqual(store.calendarContentUpdate?.source, .meeting("meeting-1"))
    }

    @MainActor
    func testCentralTaskDateSaveInvalidatesCalendarAndPublishesTargetedUpdate() {
        let original = TaskItem(
            id: "task-1",
            deadline: "2027-02-10",
            comment: "Original task"
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [original]
        let store = GrantDataStore(metadata: metadata, skipInitialMigration: true)
        let previousGeneration = store.calendarContentGeneration
        var updated = original
        updated.deadline = "2027-02-11"

        store.autosaveTaskItems([updated])

        XCTAssertEqual(store.taskItems.first?.deadline, "2027-02-11")
        XCTAssertEqual(store.calendarContentGeneration, previousGeneration + 1)
        XCTAssertEqual(store.calendarContentUpdate?.source, .teachingTask(taskID: "task-1"))
    }

    func testCentralCalendarTaskExposesItsLinksToCalendarMetadata() {
        let task = TaskItem(
            id: "task-1",
            deadline: "2027-02-10",
            comment: "Linked task",
            links: [
                TaskLink(kind: .project, targetID: "project-1"),
                TaskLink(kind: .organization, targetID: "organization-1"),
                TaskLink(kind: .publication, targetID: "publication-1"),
                TaskLink(kind: .application, targetID: "application-1"),
                TaskLink(kind: .teachingAssignment, targetID: "assignment-1")
            ]
        )

        XCTAssertEqual(
            calendarCentralTaskProjectIDs(
                task,
                applicationsByID: [:],
                publicationsByID: [:]
            ),
            ["project-1"]
        )
        XCTAssertEqual(calendarCentralTaskTargetIDs(task, kind: .organization), ["organization-1"])
        XCTAssertEqual(calendarCentralTaskTargetIDs(task, kind: .publication), ["publication-1"])
        XCTAssertEqual(calendarCentralTaskTargetIDs(task, kind: .application), ["application-1"])
        XCTAssertEqual(calendarCentralTaskTargetIDs(task, kind: .teachingAssignment), ["assignment-1"])

        let researcherNames = calendarCentralTaskResearcherNames(
            task,
            projectsByID: [
                "project-1": ProjectRecord(
                    id: "project-1",
                    nameSv: "Projekt",
                    nameEn: "Project",
                    collaboratorNames: ["Project researcher"]
                )
            ],
            applicationsByID: [
                "application-1": GrantApplication(
                    id: "application-1",
                    rowNumber: 1,
                    organization: "Funder",
                    grantName: "Grant",
                    coApplicants: ["Grant researcher"]
                )
            ],
            publicationsByID: [
                "publication-1": PublicationRecord(
                    id: "publication-1",
                    title: "Publication",
                    authorNames: ["Publication researcher"]
                )
            ]
        )
        XCTAssertEqual(
            researcherNames,
            ["Project researcher", "Grant researcher", "Publication researcher"]
        )
    }

    func testCentralCalendarTaskCopyPreservesLinksAndClearsCompletion() {
        let original = TaskItem(
            id: "task-1",
            createdOn: "2026-07-01",
            updatedOn: "2026-07-02",
            deadline: "2026-07-03",
            comment: "Linked task",
            participantNames: ["Ada Lovelace"],
            links: [TaskLink(kind: .project, targetID: "project-1")],
            completedOn: "2026-07-04"
        )

        let copy = duplicatedCalendarCentralTask(
            original,
            id: "task-copy",
            deadline: "2026-07-10",
            todayString: "2026-07-05"
        )

        XCTAssertEqual(copy.id, "task-copy")
        XCTAssertEqual(copy.createdOn, "2026-07-05")
        XCTAssertEqual(copy.updatedOn, "2026-07-05")
        XCTAssertEqual(copy.deadline, "2026-07-10")
        XCTAssertNil(copy.completedOn)
        XCTAssertEqual(copy.links, original.links)
        XCTAssertEqual(copy.participantNames, original.participantNames)
    }

    @MainActor
    func testCentralTaskMovedToFutureClearsItsActiveReminderBadgeImmediately() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let original = TaskItem(
            id: "task-1",
            deadline: DateParsers.isoDay.string(from: yesterday),
            comment: "Past task"
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [original]
        let store = GrantDataStore(metadata: metadata, skipInitialMigration: true)
        store.updateCalendarTaskReminderBadgeEntries([
            CalendarTaskReminderEntry(
                id: "teaching-task:task-1",
                source: .teachingTask(taskID: "task-1"),
                displayDate: today,
                title: "Past task",
                context: "General",
                badgeTargets: []
            )
        ])
        XCTAssertEqual(store.calendarTaskReminderBadgeEntries.map(\.source), [.teachingTask(taskID: "task-1")])

        var updated = original
        updated.deadline = DateParsers.isoDay.string(from: tomorrow)
        store.autosaveTaskItems([updated])

        XCTAssertTrue(store.calendarTaskReminderBadgeEntries.isEmpty)
    }

    func testCalendarMeetingDoctoralCandidateLinksBackfillAndDeduplicate() throws {
        let legacyJSON = """
        {
          "id": "meeting-1",
          "date": "2027-02-10",
          "title": "Supervision",
          "doctoralCandidateID": "candidate-legacy"
        }
        """.data(using: .utf8)!

        var decoded = try JSONDecoder().decode(CalendarMeetingRecord.self, from: legacyJSON)
        decoded.normalize()

        XCTAssertEqual(decoded.doctoralCandidateIDs, ["candidate-legacy"])
        XCTAssertEqual(decoded.doctoralCandidateID, "candidate-legacy")

        var record = CalendarMeetingRecord(
            date: "2027-02-10",
            title: "Supervision",
            doctoralCandidateIDs: ["candidate-1", " candidate-2 ", "candidate-1"]
        )
        record.normalize()

        XCTAssertEqual(record.doctoralCandidateIDs, ["candidate-1", "candidate-2"])
        XCTAssertEqual(record.doctoralCandidateID, "candidate-1")
    }

    func testIllogicalCongressDateFieldKeysMarksEndBeforeStart() {
        let congress = OrganizationCongress(
            id: "congress-1",
            title: "Congress",
            from: "2026-07-02",
            to: "2026-06-06"
        )

        XCTAssertEqual(
            illogicalCongressDateFieldKeys(for: congress),
            [
                CongressDateValidationFieldKey.from,
                CongressDateValidationFieldKey.to
            ]
        )
    }

    func testIllogicalCongressDateFieldKeysMarksLateAbstractBeforeRegularDeadline() {
        let congress = OrganizationCongress(
            id: "congress-1",
            title: "Congress",
            from: "2026-07-02",
            abstractSubmissionDeadline: "2026-04-13",
            lateAbstractSubmissionDeadline: "2026-03-12"
        )

        XCTAssertEqual(
            illogicalCongressDateFieldKeys(for: congress),
            [
                CongressDateValidationFieldKey.abstractSubmissionDeadline,
                CongressDateValidationFieldKey.lateAbstractSubmissionDeadline
            ]
        )
    }

    func testIllogicalCongressDateFieldKeysMarksAbstractDeadlineAfterCongressStart() {
        let congress = OrganizationCongress(
            id: "congress-1",
            title: "Congress",
            from: "2026-07-02",
            abstractSubmissionDeadline: "2026-07-03"
        )

        XCTAssertEqual(
            illogicalCongressDateFieldKeys(for: congress),
            [
                CongressDateValidationFieldKey.from,
                CongressDateValidationFieldKey.abstractSubmissionDeadline
            ]
        )
    }

    func testCongressPassedAbstractDeadlineUsesLatestAvailableDeadline() throws {
        let congress = OrganizationCongress(
            id: "congress-1",
            title: "Congress",
            abstractSubmissionDeadline: "2026-03-01",
            lateAbstractSubmissionDeadline: "2026-04-01"
        )
        let referenceDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-03-15"))

        XCTAssertFalse(congressHasPassedAbstractDeadline(congress, on: referenceDate))
    }

    func testCongressPassedAbstractDeadlineIsTrueWhenAllDeadlinesHavePassed() throws {
        let congress = OrganizationCongress(
            id: "congress-1",
            title: "Congress",
            abstractSubmissionDeadline: "2026-03-01",
            lateAbstractSubmissionDeadline: "2026-03-10"
        )
        let referenceDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-03-15"))

        XCTAssertTrue(congressHasPassedAbstractDeadline(congress, on: referenceDate))
    }

    func testCongressWithoutValidAbstractDeadlineIsNotPassed() throws {
        let congress = OrganizationCongress(
            id: "congress-1",
            title: "Congress",
            abstractSubmissionDeadline: "not-a-date"
        )
        let referenceDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-03-15"))

        XCTAssertFalse(congressHasPassedAbstractDeadline(congress, on: referenceDate))
    }

    func testIllogicalApplicationDateFieldKeysMarksClosingBeforeOpening() {
        let application = GrantApplication(
            id: "application-1",
            rowNumber: 1,
            organization: "Funder",
            grantName: "Grant",
            opensOn: "2027-02-01",
            closesOn: "2027-01-15"
        )

        XCTAssertEqual(
            illogicalApplicationDateFieldKeys(for: application),
            [
                ApplicationDateValidationFieldKey.opensOn,
                ApplicationDateValidationFieldKey.closesOn
            ]
        )
    }

    func testIllogicalApplicationDateFieldKeysMarksOutcomeBeforeApplied() {
        let application = GrantApplication(
            id: "application-1",
            rowNumber: 1,
            organization: "Funder",
            grantName: "Grant",
            appliedOn: "2027-02-01",
            grantedOn: "2027-01-15"
        )

        XCTAssertEqual(
            illogicalApplicationDateFieldKeys(for: application),
            [
                ApplicationDateValidationFieldKey.appliedOn,
                ApplicationDateValidationFieldKey.grantedOn
            ]
        )
    }

    func testIllogicalApplicationDateFieldKeysAllowsDecisionBeforeExpectedDate() {
        let application = GrantApplication(
            id: "application-1",
            rowNumber: 1,
            organization: "Funder",
            grantName: "Grant",
            decisionExpectedOn: "2027-04-30",
            firstDispositionOn: "2027-04-15"
        )

        XCTAssertTrue(illogicalApplicationDateFieldKeys(for: application).isEmpty)
    }

    func testIllogicalConferenceContributionDateFieldKeysMarksSubmissionDeadlineBeforeSubmission() {
        let contribution = CVConferenceContribution(
            id: "contribution-1",
            submissionAppliedOn: "2027-03-10",
            submissionClosesOn: "2027-03-01"
        )

        XCTAssertEqual(
            illogicalConferenceContributionDateFieldKeys(for: contribution),
            [
                ConferenceContributionDateValidationFieldKey.submissionAppliedOn,
                ConferenceContributionDateValidationFieldKey.submissionClosesOn
            ]
        )
    }

    func testIllogicalPublicationDateFieldKeysMarksWorkflowBeforeSubmission() {
        let publication = PublicationRecord(
            id: "publication-1",
            currentSubmissionDate: "2027-04-10",
            workflowStatusDate: "2027-04-01"
        )

        XCTAssertEqual(
            illogicalPublicationDateFieldKeys(for: publication),
            [
                PublicationDateValidationFieldKey.currentSubmissionDate,
                PublicationDateValidationFieldKey.workflowStatusDate
            ]
        )
    }

    func testIllogicalPublicationSubmissionDateFieldKeysMarksRejectedBeforeSubmitted() {
        let row = PublicationSubmissionEditorRow(
            submittedDate: "2027-04-10",
            rejectedDate: "2027-04-01"
        )

        XCTAssertEqual(
            illogicalPublicationSubmissionDateFieldKeys(for: row),
            [
                PublicationSubmissionDateValidationFieldKey.submittedDate,
                PublicationSubmissionDateValidationFieldKey.rejectedDate
            ]
        )
    }

    func testIllogicalDoctoralDateFieldKeysMarksHalftimeBeforePlanning() {
        let candidate = DoctoralCandidateRecord(
            id: "doctoral-1",
            planningSeminarDate: "2027-03-10",
            halftimeDate: "2027-03-01"
        )

        XCTAssertEqual(
            illogicalDoctoralDateFieldKeys(for: candidate),
            [
                DoctoralDateValidationFieldKey.planningSeminarDate,
                DoctoralDateValidationFieldKey.halftimeDate
            ]
        )
    }

    func testValidationDateRangeIsIllogicalMarksEndBeforeStart() {
        XCTAssertTrue(validationDateRangeIsIllogical(from: "2027-06-10", to: "2027-06-01"))
        XCTAssertFalse(validationDateRangeIsIllogical(from: "2027-06-01", to: "2027-06-10"))
    }

    func testISODateParserRejectsOverflowDatesAndArbitraryEmbeddedDigits() {
        XCTAssertNil(DateParsers.isoDay.date(from: "2024-02-30"))
        XCTAssertNil(DateParsers.isoDay.date(from: "2024-2-3"))
        XCTAssertEqual(DateParsers.canonicalizedDayInput("20240229"), "2024-02-29")
        XCTAssertEqual(DateParsers.canonicalizedDayInput("2024/02/29"), "2024-02-29")
        XCTAssertEqual(DateParsers.canonicalizedDayInput("reference 20240229"), "reference 20240229")
        XCTAssertNotNil(DateParsers.isoDay.date(from: "2024-02-29"))
    }

    func testLinkedTeachingActivityMinutesAreSummedPerPeriod() {
        let periods = [
            TeachingAssignmentPeriod(id: "spring", from: "2027-01-01", to: "2027-06-30"),
            TeachingAssignmentPeriod(id: "autumn", from: "2027-07-01", to: "2027-12-31")
        ]
        let meetings = [
            CalendarMeetingRecord(
                id: "lecture-1",
                date: "2027-02-10",
                startTime: "10:00",
                endTime: "12:00",
                title: "Teaching",
                teachingAssignmentID: "assignment-1"
            ),
            CalendarMeetingRecord(
                id: "lecture-2",
                date: "2027-03-10",
                startTime: "13:00",
                endTime: "14:30",
                title: "Teaching",
                teachingAssignmentID: "assignment-1"
            ),
            CalendarMeetingRecord(
                id: "other-assignment",
                date: "2027-03-10",
                startTime: "15:00",
                endTime: "16:00",
                title: "Other",
                teachingAssignmentID: "assignment-2"
            ),
            CalendarMeetingRecord(
                id: "autumn-lecture",
                date: "2027-08-10",
                startTime: "09:00",
                endTime: "10:00",
                title: "Teaching",
                teachingAssignmentID: "assignment-1"
            )
        ]

        let minutes = teachingAssignmentCalendarActivityMinutesByPeriodID(
            assignmentID: "assignment-1",
            periods: periods,
            meetings: meetings
        )

        XCTAssertEqual(minutes["spring"], 210)
        XCTAssertEqual(minutes["autumn"], 60)
    }

    func testLinkedTeachingActivityMinutesAreSplitAcrossMultipleAssignments() {
        let periods = [
            TeachingAssignmentPeriod(id: "spring", from: "2027-01-01", to: "2027-06-30")
        ]
        let meetings = [
            CalendarMeetingRecord(
                id: "shared-lecture",
                date: "2027-02-10",
                startTime: "10:00",
                endTime: "12:00",
                title: "Shared teaching",
                teachingAssignmentIDs: ["assignment-1", "assignment-2"]
            )
        ]

        let firstAssignmentMinutes = teachingAssignmentCalendarActivityMinutesByPeriodID(
            assignmentID: "assignment-1",
            periods: periods,
            meetings: meetings
        )
        let secondAssignmentMinutes = teachingAssignmentCalendarActivityMinutesByPeriodID(
            assignmentID: "assignment-2",
            periods: periods,
            meetings: meetings
        )

        XCTAssertEqual(firstAssignmentMinutes["spring"], 60)
        XCTAssertEqual(secondAssignmentMinutes["spring"], 60)
    }

    func testLinkedTeachingActivityMinutesPreserveRemainderAcrossAssignments() {
        let periods = [
            TeachingAssignmentPeriod(id: "spring", from: "2027-01-01", to: "2027-06-30")
        ]
        let meeting = CalendarMeetingRecord(
            id: "shared-lecture-with-remainder",
            date: "2027-02-10",
            startTime: "10:00",
            endTime: "11:01",
            title: "Shared teaching",
            teachingAssignmentIDs: ["assignment-2", "assignment-1"]
        )

        let first = teachingAssignmentCalendarActivityMinutesByPeriodID(
            assignmentID: "assignment-1",
            periods: periods,
            meetings: [meeting]
        )
        let second = teachingAssignmentCalendarActivityMinutesByPeriodID(
            assignmentID: "assignment-2",
            periods: periods,
            meetings: [meeting]
        )

        XCTAssertEqual(first["spring"], 31)
        XCTAssertEqual(second["spring"], 30)
        XCTAssertEqual((first["spring"] ?? 0) + (second["spring"] ?? 0), 61)
    }

    func testLinkedCalendarActivityRejectsEndBeforeStartPeriods() {
        let reversedPeriod = TeachingAssignmentPeriod(
            id: "reversed",
            from: "2027-06-30",
            to: "2027-01-01"
        )
        let meeting = CalendarMeetingRecord(
            id: "lecture-in-reversed-range",
            date: "2027-03-10",
            startTime: "10:00",
            endTime: "11:00",
            title: "Teaching",
            teachingAssignmentID: "assignment-1"
        )

        let minutes = teachingAssignmentCalendarActivityMinutesByPeriodID(
            assignmentID: "assignment-1",
            periods: [reversedPeriod],
            meetings: [meeting]
        )

        XCTAssertTrue(minutes.isEmpty)

        let candidate = DoctoralCandidateRecord(
            id: "candidate-1",
            candidateName: "Ada Lovelace"
        )
        let reversedSupervisionPeriod = DoctoralSupervisionPeriod(
            id: "reversed-supervision",
            from: "2027-06-30",
            to: "2027-01-01"
        )
        let supervisionMeeting = CalendarMeetingRecord(
            id: "supervision-in-reversed-range",
            date: "2027-03-10",
            startTime: "10:00",
            endTime: "11:00",
            title: "Supervision",
            doctoralCandidateIDs: [candidate.id]
        )
        let supervisionMinutes = doctoralSupervisionCalendarActivityMinutesByPeriodID(
            candidate: candidate,
            periods: [reversedSupervisionPeriod],
            meetings: [supervisionMeeting]
        )

        XCTAssertTrue(supervisionMinutes.isEmpty)
    }

    func testCalendarMeetingStatisticsDoesNotCountImplicitOvernightDuration() {
        let meeting = CalendarMeetingRecord(
            id: "implicit-overnight",
            date: "2027-03-10",
            startTime: "23:30",
            endTime: "00:30",
            title: "Overnight without explicit end date",
            teachingAssignmentID: "assignment-1"
        )
        let periods = [
            TeachingAssignmentPeriod(id: "spring", from: "2027-01-01", to: "2027-06-30")
        ]

        let teachingMinutes = teachingAssignmentCalendarActivityMinutesByPeriodID(
            assignmentID: "assignment-1",
            periods: periods,
            meetings: [meeting]
        )
        let summary = calendarMeetingHoursSummary(
            meetings: [meeting],
            referenceDate: Date.distantFuture,
            matchingMeeting: { _ in true }
        )

        XCTAssertTrue(teachingMinutes.isEmpty)
        XCTAssertEqual(summary.completedMinutes, 0)
        XCTAssertEqual(summary.completedMeetingsWithoutDurationCount, 1)
        XCTAssertNil(summary.completedMeetings.first?.durationMinutes)
    }

    func testDoctoralSupervisionActivityMinutesUseExplicitDoctoralCandidateLinks() {
        let candidate = DoctoralCandidateRecord(
            id: "candidate-1",
            candidateName: "Ada Lovelace",
            supervisionPeriods: [DoctoralSupervisionPeriod(id: "spring", from: "2027-01-01", to: "2027-06-30")]
        )
        let meetings = [
            CalendarMeetingRecord(
                id: "supervision-1",
                date: "2027-02-10",
                startTime: "10:00",
                endTime: "11:30",
                title: "Supervision",
                doctoralCandidateIDs: [candidate.id]
            )
        ]

        let minutes = doctoralSupervisionCalendarActivityMinutesByPeriodID(
            candidate: candidate,
            periods: candidate.supervisionPeriods,
            meetings: meetings
        )

        XCTAssertEqual(minutes["spring"], 90)
    }

    func testDoctoralSupervisionActivityMinutesDoNotInferLinksFromMatchingNames() {
        let candidate = DoctoralCandidateRecord(
            id: "candidate-1",
            candidateName: "Ada Lovelace",
            supervisionPeriods: [DoctoralSupervisionPeriod(id: "spring", from: "2027-01-01", to: "2027-06-30")]
        )
        let unlinkedMeeting = CalendarMeetingRecord(
            id: "same-name",
            date: "2027-02-10",
            startTime: "10:00",
            endTime: "11:30",
            title: "Unrelated meeting",
            participantNames: ["Ada Lovelace"]
        )

        let minutes = doctoralSupervisionCalendarActivityMinutesByPeriodID(
            candidate: candidate,
            periods: candidate.supervisionPeriods,
            meetings: [unlinkedMeeting]
        )

        XCTAssertTrue(minutes.isEmpty)
    }

    func testAcceptedConferenceSubmissionIsNotPresented() {
        let contribution = CVConferenceContribution(
            id: "accepted-contribution",
            status: .planned,
            submissionOutcome: .granted
        )

        XCTAssertEqual(contribution.effectiveStatus, .accepted)
        XCTAssertNotEqual(contribution.effectiveStatus, .presented)
    }

    func testLegacyConferenceContributionDoesNotInferPresentationFromPastDateOrNotes() throws {
        let data = """
        {
          "id": "legacy-contribution",
          "from": "2020-01-01",
          "to": "2020-01-02",
          "publicationData": "Legacy notes",
          "journalName": "Legacy journal",
          "publicationYear": "2020"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CVConferenceContribution.self, from: data)

        XCTAssertEqual(decoded.status, .planned)
        XCTAssertEqual(decoded.effectiveStatus, .planned)
    }

    func testTeachingNormalizationPreservesMissingLocalizedValues() {
        var component = TeachingComponent(nameSv: " Föreläsning ", nameEn: "")
        component.normalize()
        XCTAssertEqual(component.nameSv, "Föreläsning")
        XCTAssertEqual(component.nameEn, "")

        var format = TeachingFormatOption(nameSv: "", nameEn: " Seminar ")
        format.normalize()
        XCTAssertEqual(format.nameSv, "")
        XCTAssertEqual(format.nameEn, "Seminar")

        var course = TeachingCourse(
            nameSv: " Kurs ",
            nameEn: "",
            programSv: " Program ",
            programEn: "",
            termSv: " VT 2027 ",
            termEn: ""
        )
        course.normalize()
        XCTAssertEqual(course.nameSv, "Kurs")
        XCTAssertEqual(course.nameEn, "")
        XCTAssertEqual(course.programSv, "Program")
        XCTAssertEqual(course.programEn, "")
        XCTAssertEqual(course.termSv, "VT 2027")
        XCTAssertEqual(course.termEn, "")
    }

    @MainActor
    func testCalendarAbstractDeadlineTitleIncludesCongressDateRange() throws {
        let organization = OrganizationRecord(
            id: "org-1",
            nameSv: "Organisation",
            nameEn: "Organization",
            congresses: [
                OrganizationCongress(
                    id: "congress-1",
                    title: "Testkongress",
                    from: "2027-02-27",
                    to: "2027-02-28",
                    abstractSubmissionDeadline: "2027-01-10"
                )
            ]
        )
        let store = GrantDataStore(organizations: [organization], skipInitialMigration: true)
        try store.persist(.allCoreData, includeBackup: false)
        let calendar = Calendar(identifier: .gregorian)
        let events = buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: DateParsers.isoDay.date(from: "2027-01-01")!,
            displayedMonthEnd: DateParsers.isoDay.date(from: "2027-01-31")!,
            calendar: calendar
        )

        let deadlineEvent = events.first { $0.id.hasPrefix("congress-deadline:") }
        XCTAssertEqual(deadlineEvent?.title, "Testkongress (27-28 februari 2027)")
    }

    func testResearcherLinkedDateRangeUsesReadableMonthSpan() {
        XCTAssertEqual(
            publicationAuthorLinkedDateRangeText(from: "2025-09-15", to: "2025-09-19", language: .swedish),
            "15-19 september 2025"
        )
        XCTAssertEqual(
            publicationAuthorLinkedDateRangeText(from: "2025-08-30", to: "2025-09-02", language: .swedish),
            "30 augusti-2 september 2025"
        )
        XCTAssertEqual(
            publicationAuthorLinkedDateRangeText(from: "2025-09-15", to: "2025-09-15", language: .swedish),
            "15 september 2025"
        )
    }

    func testResearcherDetailTeachingAssignmentFilterKeepsIndividualAndDoctoralRows() {
        let doctoralCourse = TeachingCourse(
            id: "doctoral-course",
            name: "Forskarutbildningskurs",
            contextType: .doctoralEducation
        )
        let groupLecture = TeachingAssignment(
            id: "group",
            authorID: "author",
            activityName: "Föreläsning",
            reportCategory: .lecture,
            roles: [.lecturer],
            participantForm: .group
        )
        let individualSupervision = TeachingAssignment(
            id: "individual",
            authorID: "author",
            activityName: "Individuell handledning",
            reportCategory: .thesisSupervision,
            roles: [.supervisor],
            studentName: "Student A",
            participantForm: .individual
        )
        let doctoralSupervision = TeachingAssignment(
            id: "doctoral",
            authorID: "author",
            activityName: "Doktorandhandledning",
            reportCategory: .doctoralPrincipalSupervision,
            roles: [.principalSupervisor],
            studentName: "Doktorand A"
        )
        let doctoralCourseTeaching = TeachingAssignment(
            id: "doctoral-course-teaching",
            authorID: "author",
            contextID: doctoralCourse.id,
            activityName: "Seminarium",
            reportCategory: .doctoralCourseTeaching,
            roles: [.seminarLeader],
            participantForm: .group
        )

        XCTAssertFalse(
            researcherDetailTeachingAssignmentIsListable(
                groupLecture,
                courses: [doctoralCourse],
                components: [],
                formats: []
            )
        )
        XCTAssertTrue(
            researcherDetailTeachingAssignmentIsListable(
                individualSupervision,
                courses: [doctoralCourse],
                components: [],
                formats: []
            )
        )
        XCTAssertTrue(
            researcherDetailTeachingAssignmentIsListable(
                doctoralSupervision,
                courses: [doctoralCourse],
                components: [],
                formats: []
            )
        )
        XCTAssertFalse(
            researcherDetailTeachingAssignmentIsListable(
                doctoralCourseTeaching,
                courses: [doctoralCourse],
                components: [],
                formats: []
            )
        )
    }

    func testLegacyOrganizationAndProjectIDsAreDeterministic() {
        let legacy = LocalizedOption(
            nameSv: "Exempelköpings universitet",
            nameEn: "Exempelköping University",
            addressLine: "",
            postalCode: "",
            city: "",
            country: "",
            category: nil,
            collaboratorNames: [],
            roles: [],
            note: nil,
            websiteURL: "",
            phoneNumber: "",
            organizationNumber: "",
            vatNumber: "",
            employerContacts: [],
            flag: "",
            membershipFrom: "",
            membershipTo: "",
            congresses: [],
            salaryCalculator: nil,
            projectStatus: .ongoing,
            hasDataCollection: false,
            ethicsBaseApplication: ProjectEthicsApplication(),
            ethicsAmendments: [],
            ethicsLink: nil,
            clinicalTrialRegistrations: [],
            dataCollections: [],
            projectTasks: [],
            suppressedSeedProjectTaskComments: [],
            isArchived: false
        )

        XCTAssertEqual(
            OrganizationRecord(legacy: legacy).id,
            OrganizationRecord(legacy: legacy).id
        )
        XCTAssertEqual(
            ProjectRecord(legacy: legacy).id,
            ProjectRecord(legacy: legacy).id
        )
    }

    func testGrantApplicationRoundTripPreservesRelationIDs() throws {
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organizationID: "organization-uni",
            organization: "Exempelköpings universitet",
            grantName: "Grant",
            projectID: "project-alpha",
            projectType: "Alpha",
            applicationManagerID: "manager-uni",
            applicationManager: "EXU"
        )

        let data = try JSONEncoder().encode(application)
        let decoded = try JSONDecoder().decode(GrantApplication.self, from: data)

        XCTAssertEqual(decoded.organizationID, "organization-uni")
        XCTAssertEqual(decoded.projectID, "project-alpha")
        XCTAssertEqual(decoded.applicationManagerID, "manager-uni")
    }

    @MainActor
    func testIntegrityIssuesFlagStaleStoredRelationIDs() {
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organizationID: "missing-organization",
            organization: "",
            grantName: "Grant",
            projectID: "missing-project",
            projectType: nil,
            applicationManagerID: "missing-manager",
            applicationManager: nil
        )
        let publication = PublicationRecord(
            id: "pub-1",
            projectID: "missing-publication-project",
            title: "Publication",
            year: "2026"
        )
        let candidate = DoctoralCandidateRecord(
            id: "candidate-1",
            candidateAuthorID: "missing-candidate-author",
            candidateName: "Doctoral candidate",
            institutionID: "missing-institution",
            linkedProjectID: "missing-doctoral-project",
            linkedPublicationIDs: ["missing-linked-publication"],
            supervisors: [
                DoctoralSupervisorLink(authorID: "missing-supervisor-author", name: "Supervisor")
            ]
        )
        let store = GrantDataStore(
            applications: [application],
            doctoralCandidates: [candidate],
            publicationRecords: [publication],
            skipInitialMigration: true
        )

        let issues = store.integrityIssues(includeHidden: true)
        let issueDetails = Set(issues.map(\.details))

        XCTAssertTrue(issueDetails.contains("missing-organization"))
        XCTAssertTrue(issueDetails.contains("missing-project"))
        XCTAssertTrue(issueDetails.contains("missing-manager"))
        XCTAssertTrue(issueDetails.contains("missing-publication-project"))
        XCTAssertTrue(issueDetails.contains("missing-candidate-author"))
        XCTAssertTrue(issueDetails.contains("missing-institution"))
        XCTAssertTrue(issueDetails.contains("missing-doctoral-project"))
        XCTAssertTrue(issueDetails.contains("missing-linked-publication"))
        XCTAssertTrue(issueDetails.contains("missing-supervisor-author"))
        XCTAssertTrue(issues.contains { $0.recordID == "app-1" && $0.destination == .applications })
        XCTAssertTrue(issues.contains { $0.recordID == "candidate-1" && $0.destination == .doctoralCandidates })
    }

    func testGrantTimelineDateEditDoesNotShiftLinkedEndDates() {
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Formas",
            grantName: "Grant",
            opensOn: "2026-01-01",
            closesOn: "2026-02-01",
            firstDispositionOn: "2026-03-01",
            lastDispositionOn: "2026-04-01"
        )

        let updatedOpenDates = applyingGrantTimelineDateEdit(
            application,
            keyPath: \.opensOn,
            value: "2026-01-10"
        )
        let updatedDispositionDates = applyingGrantTimelineDateEdit(
            application,
            keyPath: \.firstDispositionOn,
            value: "2026-03-10"
        )

        XCTAssertEqual(updatedOpenDates.opensOn, "2026-01-10")
        XCTAssertEqual(updatedOpenDates.closesOn, "2026-02-01")
        XCTAssertEqual(updatedDispositionDates.firstDispositionOn, "2026-03-10")
        XCTAssertEqual(updatedDispositionDates.lastDispositionOn, "2026-04-01")
    }

    @MainActor
    func testDataQualityFlagsGrantDispositionBeforeGrantedDate() {
        let funder = OrganizationRecord(
            id: "organization-forte",
            nameSv: "Forte",
            nameEn: "Forte",
            roles: [.grantProvider]
        )
        let application = GrantApplication(
            id: "application-forte-2025",
            rowNumber: 1,
            organizationID: funder.id,
            organization: funder.nameSv,
            grantName: "Forskning om nära vård 2025",
            decisionExpectedOn: "2025-11-18",
            firstDispositionOn: "2025-12-01",
            lastDispositionOn: "2029-11-30",
            appliedOn: "2025-08-26",
            grantedOn: "2026-05-18",
            result: "Beviljat",
            applicationTitle: "Forskning om nära vård 2025",
            coApplicants: ["Test Person"]
        )
        let store = GrantDataStore(applications: [application], organizations: [funder])
        let expectedSubtitle = store.language.text(
            "First disposition before granted date",
            "Första disponering före beviljat datum"
        )

        let issues = store.integrityIssues(includeHidden: true)
        let matchingIssues = issues.filter { issue in
            issue.recordID == application.id
        }

        XCTAssertTrue(matchingIssues.contains { $0.subtitle == expectedSubtitle })
        XCTAssertTrue(matchingIssues.contains { $0.details.contains("2026-05-18") })
        XCTAssertTrue(matchingIssues.contains { $0.details.contains("2025-12-01") })
    }

    @MainActor
    func testDataQualityAllowsDecisionBeforeExpectedDecisionDate() {
        let funder = OrganizationRecord(
            id: "organization-circm",
            nameSv: "CircM",
            nameEn: "CircM",
            roles: [.grantProvider]
        )
        let application = GrantApplication(
            id: "application-circm-2022",
            rowNumber: 1,
            organizationID: funder.id,
            organization: funder.nameSv,
            grantName: "CircM",
            decisionExpectedOn: "2022-12-31",
            appliedOn: "2022-10-01",
            grantedOn: "2022-12-01",
            result: "Beviljat",
            applicationTitle: "CircM",
            coApplicants: ["Test Person"]
        )
        let store = GrantDataStore(applications: [application], organizations: [funder])
        let obsoleteSubtitle = store.language.text(
            "Expected decision after registered decision",
            "Beslut väntas efter registrerat beslut"
        )

        let issues = store.integrityIssues(includeHidden: true)
        let matchingIssues = issues.filter { $0.recordID == application.id }

        XCTAssertFalse(matchingIssues.contains { $0.subtitle == obsoleteSubtitle })
    }

    @MainActor
    func testDataQualityAllowsDispositionDatesOnRejectedApplications() {
        let funder = OrganizationRecord(
            id: "organization-circm",
            nameSv: "CircM",
            nameEn: "CircM",
            roles: [.grantProvider]
        )
        let application = GrantApplication(
            id: "application-circm-seed",
            rowNumber: 1,
            organizationID: funder.id,
            organization: funder.nameSv,
            grantName: "CircM, Seed grant",
            decisionExpectedOn: "2025-12-31",
            firstDispositionOn: "2026-01-01",
            lastDispositionOn: "2026-12-31",
            appliedOn: "2025-10-01",
            deniedOn: "2025-12-01",
            result: "Avslag",
            applicationTitle: "CircM, Seed grant",
            coApplicants: ["Test Person"]
        )
        let store = GrantDataStore(applications: [application], organizations: [funder])
        let obsoleteSubtitle = store.language.text(
            "Disposition dates on rejected or withdrawn application",
            "Disponeringstid på avslagen eller tillbakadragen ansökan"
        )

        let issues = store.integrityIssues(includeHidden: true)
        let matchingIssues = issues.filter { $0.recordID == application.id }

        XCTAssertFalse(matchingIssues.contains { $0.subtitle == obsoleteSubtitle })
    }

    func testGrantConsumptionPeriodEditDoesNotShiftEndDate() {
        let period = GrantConsumptionPeriod(
            id: "period-1",
            from: "2026-01-01",
            to: "2026-01-31",
            amount: "1000"
        )

        let updated = applyingGrantConsumptionPeriodEdit(
            period,
            keyPath: \.from,
            value: "2026-01-10"
        )

        XCTAssertEqual(updated.from, "2026-01-10")
        XCTAssertEqual(updated.to, "2026-01-31")
    }

    func testTeachingAndDoctoralRecordsRoundTripInstitutionID() throws {
        let course = TeachingCourse(
            id: "course-1",
            name: "Forskarlinjen",
            institutionID: "organization-uni",
            institution: "Exempelköpings universitet"
        )
        let candidate = DoctoralCandidateRecord(
            id: "candidate-1",
            candidateName: "Elias Jonsson",
            institutionID: "organization-uni",
            institution: "Exempelköpings universitet"
        )

        let courseData = try JSONEncoder().encode(course)
        let candidateData = try JSONEncoder().encode(candidate)

        XCTAssertEqual(try JSONDecoder().decode(TeachingCourse.self, from: courseData).institutionID, "organization-uni")
        XCTAssertEqual(try JSONDecoder().decode(DoctoralCandidateRecord.self, from: candidateData).institutionID, "organization-uni")
    }

    func testPublicationRoundTripPreservesProjectID() throws {
        let record = PublicationRecord(
            id: "publication-1",
            projectID: "project-alpha",
            projectName: "Alpha",
            title: "Title",
            epubDate: "2025-12-31",
            authorNames: ["Pontus af Lindholm", "Anna Andersson"],
            correspondingAuthorName: "Anna Andersson"
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(PublicationRecord.self, from: data)

        XCTAssertEqual(decoded.projectID, "project-alpha")
        XCTAssertEqual(decoded.epubDate, "2025-12-31")
        XCTAssertEqual(decoded.correspondingAuthorName, "Anna Andersson")
    }

    func testPublicationEpubDateCanonicalizesCompactDayInput() {
        let record = PublicationRecord(
            id: "publication-1",
            title: "Epub date",
            epubDate: "20240120"
        )

        XCTAssertEqual(record.epubDate, "2024-01-20")
    }

    func testPublicationAuthorRoundTripPreservesGender() throws {
        let author = PublicationAuthor(
            id: "author-1",
            name: "Anna Andersson",
            firstName: "Anna",
            lastName: "Andersson",
            gender: .female,
            hasPhD: true,
            careerStage: .categoryC
        )

        let data = try JSONEncoder().encode(author)
        let decoded = try JSONDecoder().decode(PublicationAuthor.self, from: data)

        XCTAssertEqual(decoded.gender, .female)
        XCTAssertTrue(decoded.hasPhD)
        XCTAssertEqual(decoded.careerStage, .categoryC)
    }

    func testPublicationAuthorDecodeDefaultsNameVariantsForLegacyData() throws {
        let data = Data(#"{"id":"author-1","name":"Anna Berg","firstName":"Anna","lastName":"Berg"}"#.utf8)
        let decoded = try JSONDecoder().decode(PublicationAuthor.self, from: data)

        XCTAssertEqual(decoded.nameVariants, [])
        XCTAssertEqual(decoded.nameVariantRows, [])
    }

    func testPublicationAuthorNormalizeDeduplicatesNameVariants() {
        var author = PublicationAuthor(
            name: "Anna Berg",
            firstName: "Anna",
            lastName: "Berg",
            nameVariants: [" Anna Andersson ", "anna andersson", "Anna Berg", ""]
        )

        author.normalize()

        XCTAssertEqual(author.nameVariants, ["Anna Andersson"])
        XCTAssertEqual(author.nameVariantRows, [
            PublicationAuthorNameVariant(firstName: "Anna", lastName: "Andersson")
        ])
    }

    func testPublicationAuthorDecodesLegacyFullNameVariantAsStructuredParts() throws {
        let data = Data(#"{"id":"author-1","name":"Anna Berg","firstName":"Anna","lastName":"Berg","nameVariants":["Anna Andersson"]}"#.utf8)
        let decoded = try JSONDecoder().decode(PublicationAuthor.self, from: data)

        XCTAssertEqual(decoded.nameVariantRows, [
            PublicationAuthorNameVariant(firstName: "Anna", lastName: "Andersson")
        ])
        XCTAssertEqual(decoded.nameVariants, ["Anna Andersson"])
    }

    func testPublicationAuthorCanPromoteNameVariantToPrimaryName() {
        var author = PublicationAuthor(
            name: "Anna Berg",
            firstName: "Anna",
            lastName: "Berg",
            nameVariantRows: [
                PublicationAuthorNameVariant(firstName: "Anna", lastName: "Andersson")
            ]
        )

        XCTAssertTrue(author.promoteNameVariant(PublicationAuthorNameVariant(firstName: "Anna", lastName: "Andersson")))
        XCTAssertEqual(author.name, "Anna Andersson")
        XCTAssertEqual(author.firstName, "Anna")
        XCTAssertEqual(author.lastName, "Andersson")
        XCTAssertEqual(author.nameVariantRows, [
            PublicationAuthorNameVariant(firstName: "Anna", lastName: "Berg")
        ])
    }

    func testPublicationAuthorCanPromoteSurnameOnlyNameVariantToPrimaryName() {
        var author = PublicationAuthor(
            name: "Anna Berg",
            firstName: "Anna",
            lastName: "Berg",
            nameVariantRows: [
                PublicationAuthorNameVariant(firstName: "", lastName: "Andersson")
            ]
        )

        XCTAssertTrue(author.promoteNameVariant(PublicationAuthorNameVariant(firstName: "", lastName: "Andersson")))
        XCTAssertEqual(author.name, "Anna Andersson")
        XCTAssertEqual(author.firstName, "Anna")
        XCTAssertEqual(author.lastName, "Andersson")
        XCTAssertEqual(author.nameVariantRows, [
            PublicationAuthorNameVariant(firstName: "Anna", lastName: "Berg")
        ])
    }

    @MainActor
    func testPublicationAuthorOptionsIncludeHistoricalNameVariants() {
        let author = PublicationAuthor(
            id: "author-1",
            name: "Anna Berg",
            firstName: "Anna",
            lastName: "Berg",
            nameVariantRows: [
                PublicationAuthorNameVariant(firstName: "Anna", lastName: "Andersson")
            ]
        )
        let store = GrantDataStore(publicationAuthors: [author])
        let display: (String) -> String = { name in
            store.publicationAuthor(named: name) == nil && store.publicationAuthor(matchingPresentedName: name) != nil
                ? "\(name) (tidigare)"
                : name
        }

        XCTAssertEqual(store.publicationAuthorOptionNames, ["Anna Berg", "Anna Andersson"])
        XCTAssertEqual(
            filteredAutocompleteOptions(
                options: store.publicationAuthorOptionNames,
                queryText: "Andersson",
                showsSuggestionsWithoutQuery: false,
                display: display
            ),
            ["Anna Andersson"]
        )
        XCTAssertEqual(display("Anna Andersson"), "Anna Andersson (tidigare)")
    }

    @MainActor
    func testPublicationAuthorNameVariantLinksHistoricalPublicationName() throws {
        let author = PublicationAuthor(
            id: "author-1",
            name: "Anna Berg",
            firstName: "Anna",
            lastName: "Berg",
            nameVariantRows: [
                PublicationAuthorNameVariant(firstName: "Anna", lastName: "Andersson")
            ]
        )
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Historical name",
            authorNames: ["Anna Andersson"]
        )
        let store = GrantDataStore(
            publicationAuthors: [author],
            publicationRecords: [publication]
        )
        store.savePublicationAuthor(author, previousName: author.name)
        store.savePublication(publication, silently: true)

        XCTAssertEqual(store.publicationAuthor(matchingPresentedName: "Anna Andersson")?.id, "author-1")
        XCTAssertEqual(store.publications(forAuthorName: "Anna Berg").map(\.id), ["publication-1"])
        XCTAssertEqual(store.publications.first?.authorNames, ["Anna Andersson"])
    }

    @MainActor
    func testPublicationAuthorNameVariantPreservesHistoricalSurnameInAMACitation() throws {
        let author = PublicationAuthor(
            id: "author-1",
            name: "Anna Berg",
            firstName: "Anna",
            lastName: "Berg",
            nameVariantRows: [
                PublicationAuthorNameVariant(firstName: "Anna", lastName: "Andersson")
            ]
        )
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Historical name",
            journal: "Journal",
            status: PublicationStatus.published.rawValue,
            year: "2025",
            authorNames: ["Anna Andersson"]
        )
        let store = GrantDataStore(
            publicationAuthors: [author],
            publicationRecords: [publication]
        )

        XCTAssertTrue(store.amaCitationItem(for: publication).plain.contains("Andersson A"))
        XCTAssertFalse(store.amaCitationItem(for: publication).plain.contains("Berg A"))
    }

    func testPublicationAuthorDecodeInfersCareerStageForLegacyData() throws {
        let data = Data(#"{"id":"author-1","name":"Anna Andersson","firstName":"Anna","lastName":"Andersson","titleSv":"Professor","hasPhD":true}"#.utf8)
        let decoded = try JSONDecoder().decode(PublicationAuthor.self, from: data)

        XCTAssertEqual(decoded.careerStage, .categoryA)
    }

    func testPublicationAuthorDecodeDefaultsCareerStageAToLegacyNonPhDData() throws {
        let data = Data(#"{"id":"author-2","name":"Axel Almö","firstName":"Axel","lastName":"Almö","hasPhD":false}"#.utf8)
        let decoded = try JSONDecoder().decode(PublicationAuthor.self, from: data)

        XCTAssertEqual(decoded.careerStage, .categoryA)
    }

    func testPublicationAuthorNormalizePreservesManualCareerStageWithoutPhD() {
        var author = PublicationAuthor(
            firstName: "Alex",
            lastName: "Example",
            hasPhD: false,
            careerStage: .categoryB
        )

        author.normalize()

        XCTAssertEqual(author.careerStage, .categoryB)
    }

    func testPublicationAuthorNormalizePreservesManualCareerStageForPhDHolders() {
        var author = PublicationAuthor(
            firstName: "Alex",
            lastName: "Example",
            hasPhD: true,
            careerStage: .categoryD
        )

        author.normalize()

        XCTAssertEqual(author.careerStage, .categoryD)
    }

    func testPublicationAuthorInitializationDefaultsCareerStageAWithoutPhD() {
        let author = PublicationAuthor(
            firstName: "Alex",
            lastName: "Example",
            hasPhD: false
        )

        XCTAssertEqual(author.careerStage, .categoryA)
    }

    func testPublicationAuthorInitializationDefaultsCareerStageBForPhDHolders() {
        let author = PublicationAuthor(
            firstName: "Alex",
            lastName: "Example",
            hasPhD: true
        )

        XCTAssertEqual(author.careerStage, .categoryB)
    }

    @MainActor
    func testResearcherMissingFieldIssuesMatchSummaryCompletenessFields() {
        let author = PublicationAuthor(
            id: "author-1",
            name: "Alex Example",
            firstName: "Alex",
            lastName: "Example",
            gender: .female,
            affiliations: [
                PublicationAffiliation(
                    organization: "Exempelkoping University",
                    country: "Sweden",
                    isPrimary: true
                )
            ]
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        let store = GrantDataStore(metadata: metadata, publicationAuthors: [author])

        let issue = store.missingFieldIssues().first { $0.recordID == author.id }

        XCTAssertEqual(issue?.entityKind, .researcher)
        XCTAssertEqual(issue?.missingFields, ["Titel", "Position", "Examen", "ORCID", "Primär e-post"])
    }

    @MainActor
    func testTeachingAssignmentNameWithoutCatalogLinkIsNotMissingFieldIssue() {
        let course = TeachingCourse(id: UUID().uuidString, name: "Klinisk medicin 1")
        let assignment = TeachingAssignment(
            id: UUID().uuidString,
            contextID: course.id,
            activityName: "Fältstudiegranskning"
        )
        let store = GrantDataStore(
            teachingCourses: [course],
            teachingAssignments: [assignment],
            skipInitialMigration: true
        )

        let issues = store.missingFieldIssues().filter { $0.recordID == assignment.id }
        XCTAssertFalse(issues.contains { $0.missingFields.contains("Saknar länkad aktivitet") })
        XCTAssertFalse(issues.contains { $0.missingFields.contains("Missing linked activity") })
    }

    func testPublicationAuthorAutomaticCareerStageWhenEnablingPhDPromotesDToC() {
        XCTAssertEqual(
            PublicationAuthor.automaticCareerStageWhenEnablingPhD(from: .categoryD),
            .categoryC
        )
    }

    func testPublicationAuthorAutomaticCareerStageWhenEnablingPhDUsesCWhenUnset() {
        XCTAssertEqual(
            PublicationAuthor.automaticCareerStageWhenEnablingPhD(from: nil),
            .categoryC
        )
    }

    func testPublicationAuthorAutomaticCareerStageWhenEnablingPhDKeepsExistingNonDSelection() {
        XCTAssertNil(PublicationAuthor.automaticCareerStageWhenEnablingPhD(from: .categoryA))
        XCTAssertNil(PublicationAuthor.automaticCareerStageWhenEnablingPhD(from: .categoryB))
        XCTAssertNil(PublicationAuthor.automaticCareerStageWhenEnablingPhD(from: .categoryC))
    }

    func testPublicationAuthorCareerStageEditorDisplayOrderShowsLowestStageFirst() {
        XCTAssertEqual(PublicationAuthorCareerStage.editorDisplayOrder, [
            .categoryD,
            .categoryC,
            .categoryB,
            .categoryA,
        ])
    }

    func testPublicationAuthorCareerStageHelpTextsUseShortFrascatiDefinitions() {
        XCTAssertEqual(
            PublicationAuthorCareerStage.overviewHelpText,
            """
            A: Highest career stage, e.g., full professor
            B: Intermediate stage between C and A, e.g., associate professor
            C: First post after PhD, e.g., assistant professor or postdoctoral researcher
            D: Doctoral student researcher
            """
        )
        XCTAssertEqual(PublicationAuthorCareerStage.categoryA.helpText, "Highest career stage, e.g., full professor")
        XCTAssertEqual(PublicationAuthorCareerStage.categoryB.helpText, "Intermediate stage between C and A, e.g., associate professor")
        XCTAssertEqual(PublicationAuthorCareerStage.categoryC.helpText, "First post after PhD, e.g., assistant professor or postdoctoral researcher")
        XCTAssertEqual(PublicationAuthorCareerStage.categoryD.helpText, "Doctoral student researcher")
    }

    func testPublicationAuthorSortComparatorsSortOrganizationAscending() {
        let rows = [
            publicationAuthorRowSnapshot(
                id: "row-1",
                sortName: "Zeta",
                sortOrganization: "orebro universitet",
                primaryOrganization: "Örebro universitet"
            ),
            publicationAuthorRowSnapshot(
                id: "row-2",
                sortName: "Alpha",
                sortOrganization: "karolinska institutet",
                primaryOrganization: "Karolinska Institutet"
            ),
        ]

        let sorted = rows.sorted(using: publicationAuthorSortComparators(for: .organization, ascending: true))

        XCTAssertEqual(sorted.map(\.id), ["row-2", "row-1"])
    }

    func testPublicationAuthorSortComparatorsSortProjectCountDescending() {
        let rows = [
            publicationAuthorRowSnapshot(
                id: "row-1",
                sortName: "Alpha",
                projectCount: 2
            ),
            publicationAuthorRowSnapshot(
                id: "row-2",
                sortName: "Beta",
                projectCount: 7
            ),
        ]

        let sorted = rows.sorted(using: publicationAuthorSortComparators(for: .project, ascending: false))

        XCTAssertEqual(sorted.map(\.id), ["row-2", "row-1"])
    }

    func testPublicationAuthorOrganizationFilterMatchesAnyAffiliation() {
        let row = publicationAuthorRowSnapshot(
            id: "row-1",
            sortName: "Alpha",
            primaryOrganization: "Exempelköpings universitet",
            affiliationOrganizations: ["Exempelköpings universitet", "Region Exempelgöta"]
        )

        XCTAssertTrue(!Set(row.affiliationOrganizations).isDisjoint(with: ["Region Exempelgöta"]))
        XCTAssertFalse(!Set(row.affiliationOrganizations).isDisjoint(with: ["Karolinska Institutet"]))
    }

    func testPublicationNormalizeClearsMissingCorrespondingAuthor() {
        var record = PublicationRecord(
            id: "publication-1",
            title: "Title",
            authorNames: ["Pontus af Lindholm", "Anna Andersson"],
            correspondingAuthorName: "Anna Andersson"
        )

        record.authorNames = ["Pontus af Lindholm"]
        record.normalize()

        XCTAssertNil(record.correspondingAuthorName)
    }

    @MainActor
    func testSubmissionAuthorWorkbookPayloadUsesExplicitEnglishExportLanguage() {
        let store = GrantDataStore()
        let payload = store.submissionAuthorWorkbookPayload(
            from: [
                SubmissionAuthorExportRow(
                    firstName: "Anna",
                    lastName: "Andersson",
                    titleSv: "Professor",
                    titleEn: "Professor",
                    orcid: "0000-0001",
                    organizationSv: "Exempelköpings universitet",
                    organizationEn: "Exempelkoping University",
                    departmentSv: "Avdelningen för kardiologi",
                    departmentEn: "Division of Cardiology",
                    city: "Exempelköping",
                    country: "Sweden",
                    email: "anna@example.com",
                    phoneLabel: "Work",
                    phoneNumber: "010-100 00 00",
                    phoneLabelSecondary: "",
                    phoneNumberSecondary: "",
                    creditRoles: [],
                    creditRoleContributions: [:]
                )
            ],
            configuration: .standard(language: .english)
        )

        XCTAssertEqual(Array(payload.headers.prefix(8)), [
            "First name",
            "Last name",
            "Title",
            "ORCID",
            "Institution",
            "Department",
            "City",
            "Country",
        ])
        XCTAssertEqual(Array(payload.rows[0].prefix(8)), [
            "Anna",
            "Andersson",
            "Professor",
            "0000-0001",
            "Exempelkoping University",
            "Division of Cardiology",
            "Exempelköping",
            "Sweden",
        ])
    }

    @MainActor
    func testSubmissionAuthorWorkbookPayloadUsesExplicitSwedishExportLanguage() {
        let store = GrantDataStore()
        let payload = store.submissionAuthorWorkbookPayload(
            from: [
                SubmissionAuthorExportRow(
                    firstName: "Anna",
                    lastName: "Andersson",
                    titleSv: "Professor",
                    titleEn: "Professor",
                    orcid: "0000-0001",
                    organizationSv: "Exempelköpings universitet",
                    organizationEn: "Exempelkoping University",
                    departmentSv: "Avdelningen för kardiologi",
                    departmentEn: "Division of Cardiology",
                    city: "Exempelköping",
                    country: "Sverige",
                    email: "anna@example.com",
                    phoneLabel: "Arbete",
                    phoneNumber: "010-100 00 00",
                    phoneLabelSecondary: "",
                    phoneNumberSecondary: "",
                    creditRoles: [],
                    creditRoleContributions: [:]
                )
            ],
            configuration: .standard(language: .swedish)
        )

        XCTAssertEqual(Array(payload.headers.prefix(8)), [
            "Förnamn",
            "Efternamn",
            "Titel",
            "ORCID",
            "Organisation",
            "Avdelning",
            "Ort",
            "Land",
        ])
        XCTAssertEqual(Array(payload.rows[0].prefix(8)), [
            "Anna",
            "Andersson",
            "Professor",
            "0000-0001",
            "Exempelköpings universitet",
            "Avdelningen för kardiologi",
            "Exempelköping",
            "Sverige",
        ])
    }

    @MainActor
    func testSubmissionAuthorWorkbookPayloadKeepsEditorialManagerEnglish() {
        let store = GrantDataStore()
        let payload = store.submissionAuthorWorkbookPayload(
            from: [
                SubmissionAuthorExportRow(
                    firstName: "Anna",
                    lastName: "Andersson",
                    titleSv: "Professor",
                    titleEn: "Professor",
                    orcid: "0000-0001",
                    organizationSv: "Exempelköpings universitet",
                    organizationEn: "Exempelkoping University",
                    departmentSv: "Avdelningen för kardiologi",
                    departmentEn: "Division of Cardiology",
                    city: "Exempelköping",
                    country: "Sweden",
                    email: "anna@example.com",
                    phoneLabel: "",
                    phoneNumber: "",
                    phoneLabelSecondary: "",
                    phoneNumberSecondary: "",
                    creditRoles: [],
                    creditRoleContributions: [:]
                )
            ],
            configuration: SubmissionAuthorExportConfiguration(mode: .editorialManager, exportLanguage: .swedish)
        )

        XCTAssertEqual(payload.headers, [
            "Title",
            "First name",
            "Last name",
            "E-mail",
            "ORCID",
            "Institution",
            "Country",
            "CRediT",
        ])
        XCTAssertEqual(payload.rows[0][0], "Professor")
        XCTAssertEqual(payload.rows[0][5], "Exempelkoping University")
    }

    @MainActor
    func testProjectSubmissionAuthorRowsUseProjectCollaborators() {
        let collaborator = PublicationAuthor(
            id: "author-anna",
            name: "Anna Andersson",
            firstName: "Anna",
            lastName: "Andersson",
            titleSv: "Professor",
            titleEn: "Professor",
            affiliations: [
                PublicationAffiliation(
                    organizationSv: "Exempelköpings universitet",
                    organizationEn: "Exempelkoping University",
                    departmentSv: "Avdelningen för kardiologi",
                    departmentEn: "Division of Cardiology",
                    city: "Exempelköping",
                    country: "Sweden",
                    email: "anna@example.com",
                    isPrimary: true
                )
            ]
        )
        let publicationOnlyAuthor = PublicationAuthor(
            id: "author-bertil",
            name: "Bertil Berg",
            firstName: "Bertil",
            lastName: "Berg"
        )
        let project = ProjectRecord(
            id: "project-1",
            nameSv: "Projekt Alpha",
            nameEn: "Project Alpha",
            collaboratorNames: ["Anna Andersson"]
        )
        let linkedPublication = PublicationRecord(
            id: "publication-1",
            projectID: "project-1",
            projectName: "Project Alpha",
            title: "Linked paper",
            authorNames: ["Bertil Berg"]
        )
        let store = GrantDataStore(
            publicationAuthors: [collaborator, publicationOnlyAuthor],
            publicationRecords: [linkedPublication]
        )

        let rows = store.submissionAuthorRows(for: project)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].firstName, "Anna")
        XCTAssertEqual(rows[0].lastName, "Andersson")
        XCTAssertEqual(rows[0].email, "anna@example.com")
        XCTAssertEqual(rows[0].organizationEn, "Exempelkoping University")
    }

    @MainActor
    func testProjectSubmissionValidationDoesNotRequireLinkedPublications() {
        let collaborator = PublicationAuthor(
            id: "author-anna",
            name: "Anna Andersson",
            firstName: "Anna",
            lastName: "Andersson",
            affiliations: [
                PublicationAffiliation(
                    organizationSv: "Exempelköpings universitet",
                    organizationEn: "Exempelkoping University",
                    city: "Exempelköping",
                    country: "Sweden",
                    email: "anna@example.com",
                    isPrimary: true
                )
            ]
        )
        let project = ProjectRecord(
            id: "project-1",
            nameSv: "Projekt Alpha",
            nameEn: "Project Alpha",
            collaboratorNames: ["Anna Andersson"]
        )
        let store = GrantDataStore(publicationAuthors: [collaborator])

        XCTAssertEqual(store.projectSubmissionValidationIssues(for: project), [])
    }

    @MainActor
    func testApplicationCoApplicantDoesNotCreateImplicitResearchProjectLink() {
        let applicationOnlyAuthor = PublicationAuthor(
            id: "11111111-1111-4111-8111-111111111111",
            name: "Jonas Ljung",
            firstName: "Jonas",
            lastName: "Ljung"
        )
        let explicitCollaborator = PublicationAuthor(
            id: "22222222-2222-4222-8222-222222222222",
            name: "Anna Andersson",
            firstName: "Anna",
            lastName: "Andersson"
        )
        let application = GrantApplication(
            id: "33333333-3333-4333-8333-333333333333",
            rowNumber: 1,
            organization: "FUTURUM",
            grantName: "ALPHA-STUDY",
            projectID: "44444444-4444-4444-8444-444444444444",
            projectType: "ALPHA-STUDY",
            coApplicants: ["Jonas Ljung"]
        )
        let project = ProjectRecord(
            id: "44444444-4444-4444-8444-444444444444",
            nameSv: "ALPHA-STUDY",
            nameEn: "ALPHA-STUDY",
            collaboratorNames: ["Anna Andersson"]
        )
        let store = GrantDataStore(
            applications: [application],
            projects: [project],
            publicationAuthors: [applicationOnlyAuthor, explicitCollaborator]
        )

        XCTAssertEqual(store.grantCount(forAuthorID: applicationOnlyAuthor.id), 1)
        XCTAssertEqual(store.projectCount(forAuthorID: applicationOnlyAuthor.id), 0)
        XCTAssertEqual(store.authorProjectNames(forAuthorID: applicationOnlyAuthor.id), [String]())
        XCTAssertEqual(store.projectCount(forAuthorID: explicitCollaborator.id), 1)
        XCTAssertEqual(store.authorProjectNames(forAuthorID: explicitCollaborator.id), ["ALPHA-STUDY"])

        let applicationOnlyRelations = store.researcherProjectRelations(forAuthorID: applicationOnlyAuthor.id)
        XCTAssertEqual(applicationOnlyRelations.map(\.projectName), ["ALPHA-STUDY"])
        XCTAssertEqual(applicationOnlyRelations.map(\.kind), [.applicationCoApplicant])
        XCTAssertFalse(applicationOnlyRelations[0].countsAsResearchProject)

        let collaboratorRelations = store.researcherProjectRelations(forAuthorID: explicitCollaborator.id)
        XCTAssertEqual(collaboratorRelations.map(\.projectName), ["ALPHA-STUDY"])
        XCTAssertEqual(collaboratorRelations.map(\.kind), [.explicitProjectCollaborator])
        XCTAssertTrue(collaboratorRelations[0].countsAsResearchProject)
    }

    func testPackageModeInferenceForLegacyJournalsStorageFallsBackToSelfContained() {
        let mode = AppRuntime.inferPackageMode(
            explicitModeRaw: nil,
            isShareMode: false,
            storageFolderName: "Footprint Journals",
            bootstrapSourceFolderName: nil,
            defaultsPrefix: "com.codex.footprint.journals"
        )

        XCTAssertEqual(mode, .selfContained)
    }

    func testPackageModeInferenceForLocalBootstrap() {
        let mode = AppRuntime.inferPackageMode(
            explicitModeRaw: nil,
            isShareMode: false,
            storageFolderName: "Footprint",
            bootstrapSourceFolderName: "Footprint",
            defaultsPrefix: "com.codex.footprint"
        )

        XCTAssertEqual(mode, .localBootstrap)
    }

    func testPackageModeInferenceForSelfContained() {
        let mode = AppRuntime.inferPackageMode(
            explicitModeRaw: "self-contained",
            isShareMode: false,
            storageFolderName: "Footprint",
            bootstrapSourceFolderName: nil,
            defaultsPrefix: "com.codex.footprint"
        )

        XCTAssertEqual(mode, .selfContained)
    }

    func testSalaryCoverageVisibleFromKeepsIncompletePastDraftVisible() throws {
        let visibleFromDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-01-01"))
        let draft = SalaryCoveragePeriod(
            id: "draft-period",
            sourceReference: "",
            from: "2025-01-01",
            to: "",
            percentage: ""
        )

        XCTAssertTrue(
            salaryCoveragePeriodPassesVisibleFromFilter(
                draft,
                visibleFromDate: visibleFromDate
            )
        )
    }

    func testSalaryCoverageVisibleFromCanForceRecentlyEditedPastPeriodVisible() throws {
        let visibleFromDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-01-01"))
        let pastPeriod = SalaryCoveragePeriod(
            id: "past-period",
            sourceReference: "custom:clinic",
            from: "2025-01-01",
            to: "2025-12-31",
            percentage: "50"
        )

        XCTAssertFalse(
            salaryCoveragePeriodPassesVisibleFromFilter(
                pastPeriod,
                visibleFromDate: visibleFromDate
            )
        )
        XCTAssertTrue(
            salaryCoveragePeriodPassesVisibleFromFilter(
                pastPeriod,
                visibleFromDate: visibleFromDate,
                forceVisiblePeriodIDs: [pastPeriod.id]
            )
        )
    }

    @MainActor
    func testPublicationJournalSnapshotsAddPublisherAndWebsiteOnlyToExtendedSearchBlob() throws {
        let journal = PublicationJournal(
            id: "journal-1",
            name: "Clinical Signals",
            abbreviatedName: "Clin Signals",
            publisher: "Publisher Search Only",
            journalURL: "https://publisher-search-only.example/journal-home",
            category: "General medicine"
        )

        let store = GrantDataStore(publicationJournals: [journal])
        let snapshot = try XCTUnwrap(store.publicationJournalRowSnapshots().first)

        XCTAssertFalse(snapshot.normalizedFilterSearchBlob.contains(normalizedSearchFilterText(journal.publisher)))
        XCTAssertFalse(snapshot.normalizedFilterSearchBlob.contains(normalizedSearchFilterText(journal.journalURL)))
        XCTAssertTrue(snapshot.normalizedExtendedFilterSearchBlob.contains(normalizedSearchFilterText(journal.publisher)))
        XCTAssertTrue(snapshot.normalizedExtendedFilterSearchBlob.contains(normalizedSearchFilterText(journal.journalURL)))
    }

    func testJournalCategoryFilterCanExcludeCategoriesWithoutIncludedSelection() {
        let filter = JournalCategoryFilterState(
            includedCategories: [],
            excludedCategories: ["Review"]
        )

        XCTAssertTrue(filter.matches(categorySet: ["Cardiology"]))
        XCTAssertFalse(filter.matches(categorySet: ["Cardiology", "Review"]))
        XCTAssertFalse(filter.matches(categorySet: ["Review"]))
    }

    func testJournalCategoryFilterCombinesIncludedAndExcludedCategories() {
        let filter = JournalCategoryFilterState(
            includedCategories: ["Cardiology"],
            excludedCategories: ["Review"]
        )

        XCTAssertTrue(filter.matches(categorySet: ["Cardiology"]))
        XCTAssertFalse(filter.matches(categorySet: ["Neurology"]))
        XCTAssertFalse(filter.matches(categorySet: ["Cardiology", "Review"]))
    }

    @MainActor
    func testPublicationExportSectionsIncludeNonPeerReviewedSectionWhenSelected() {
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Non-peer publication",
            journal: "Medical Magazine",
            status: PublicationStatus.published.rawValue,
            year: "2024",
            isPeerReviewed: false,
            authorNames: ["Pontus af Lindholm"]
        )
        let store = GrantDataStore(publicationRecords: [publication])

        let sections = store.amaSections(
            exportLanguage: .english,
            includedSections: [.publishedNonPeerReviewedPublications]
        )

        XCTAssertEqual(sections.map(\.title), ["Other publications, non-peer-reviewed"])
        XCTAssertEqual(sections.first?.items.count, 1)
    }

    @MainActor
    func testPublicationExportLegacyNonPeerReviewedToggleStillIncludesSection() {
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Legacy non-peer publication",
            journal: "Medical Magazine",
            status: PublicationStatus.published.rawValue,
            year: "2024",
            isPeerReviewed: false,
            authorNames: ["Pontus af Lindholm"]
        )
        let store = GrantDataStore(publicationRecords: [publication])
        var options = PublicationExportOptions()
        options.includeNonPeerReviewedPublications = true

        let sections = store.amaSections(
            exportLanguage: .english,
            options: options,
            includedSections: [.publishedOriginalArticles]
        )

        XCTAssertTrue(sections.contains(where: { $0.title == "Other publications, non-peer-reviewed" }))
    }

    @MainActor
    func testISSNLTWAShortNameExportUsesSingleSeparatorBeforeBibliographicTail() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-pontus"
        let currentUser = PublicationAuthor(id: "author-pontus", name: "Pontus af Lindholm")
        let journal = PublicationJournal(
            id: "journal-1",
            name: "American Journal of Hypertension",
            abbreviatedName: "Am J Hypertens",
            issnLTWAAbbreviatedName: "Am. J. Hypertens."
        )
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Self-measured home orthostatic hypo- and hypertension",
            journal: journal.name,
            status: PublicationStatus.published.rawValue,
            volume: "39",
            issue: "3",
            pageRange: "372-381",
            year: "2026",
            publicationType: "Original Article",
            isPeerReviewed: true,
            authorNames: ["Fredrik Falk", "Pontus af Lindholm"]
        )
        let store = GrantDataStore(
            metadata: metadata,
            publicationAuthors: [currentUser],
            publicationJournals: [journal],
            publicationRecords: [publication]
        )
        var options = PublicationExportOptions()
        options.journalShortNameStyle = .issnLTWA

        let item = store.amaCitationItem(for: publication, options: options)

        XCTAssertEqual(item.journal, "Am. J. Hypertens.")
        XCTAssertTrue(item.plain.contains("Am. J. Hypertens. 2026;39(3):372-381."))
        XCTAssertFalse(item.plain.contains("Hypertens.."))

        let publicationDocument = store.publicationAMAPreviewDocument(
            title: "Publications",
            options: options,
            includedSections: Set<PublicationExportSectionKey>([.publishedOriginalArticles]),
            exportLanguage: AppLanguage.english,
            layout: ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false)
        )
        let publicationOutputURL = isolatedStorageDirectory.appendingPathComponent("publications.docx")
        try GrantDataStore.renderPublicationDocument(publicationDocument, to: publicationOutputURL)
        let publicationText = try docxPlainText(in: publicationOutputURL)
        XCTAssertTrue(publicationText.contains("Am. J. Hypertens. 2026;39(3):372-381."))
        XCTAssertFalse(publicationText.contains("Hypertens.."))

        let cvDocument = store.cvExportDocument(
            style: CVDocumentExportStyle.own,
            exportLanguage: AppLanguage.english,
            includedSections: Set<CVExportSectionKey>([.originalArticles]),
            publicationOptions: options
        )
        let cvOutputURL = isolatedStorageDirectory.appendingPathComponent("cv.docx")
        try GrantDataStore.renderCVDocument(cvDocument, to: cvOutputURL)
        let cvText = try docxPlainText(in: cvOutputURL)
        XCTAssertTrue(cvText.contains("Am. J. Hypertens. 2026;39(3):372-381"))
        XCTAssertFalse(cvText.contains("Hypertens.."))
    }

    @MainActor
    func testPublicationExportIncludesEpubDateAfterDOIAndBeforeMetrics() throws {
        let journal = PublicationJournal(
            id: "journal-1",
            name: "Medical Journal",
            abbreviatedName: "Med J",
            rankingRows: [
                JournalRankingRow(
                    kind: .clarivateScieJIF,
                    yearlyMetrics: [JournalYearMetric(year: 2025, value: "8.7", quartile: "Q1")]
                )
            ]
        )
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Epub article",
            journal: journal.name,
            status: PublicationStatus.published.rawValue,
            doi: "10.1234/example",
            epubDate: "2025-12-31",
            volume: "12",
            issue: "3",
            pageRange: "45-49",
            year: "2025",
            publicationType: "Original Article",
            authorNames: ["Pontus af Lindholm"]
        )
        var options = PublicationExportOptions()
        options.includeDOI = true
        options.includeEpubDate = true
        options.includeClarivateSCIEJIF = true
        let store = GrantDataStore(publicationJournals: [journal], publicationRecords: [publication])

        let item = store.amaCitationItem(for: publication, options: options)

        XCTAssertTrue(item.plain.contains("doi:10.1234/example. Epub 2025 Dec 31. (IF 8.7)"))
    }

    @MainActor
    func testPublicationAndCVExportFallsBackToESCIJIFAndQuartileWithoutQuestionMark() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-pontus"
        let currentUser = PublicationAuthor(id: "author-pontus", name: "Pontus af Lindholm")
        let journal = PublicationJournal(
            id: "journal-1",
            name: "ESCI Journal",
            abbreviatedName: "ESCI J",
            rankingRows: [
                JournalRankingRow(
                    kind: .clarivateEsciJIF,
                    yearlyMetrics: [JournalYearMetric(year: 2025, value: "5.4", quartile: "Q2")]
                )
            ]
        )
        let publication = PublicationRecord(
            id: "publication-1",
            title: "ESCI indexed article",
            journal: journal.name,
            status: PublicationStatus.published.rawValue,
            volume: "7",
            pageRange: "10-14",
            year: "2025",
            publicationType: "Original Article",
            authorNames: ["Pontus af Lindholm"]
        )
        var options = PublicationExportOptions()
        options.includeClarivateSCIEJIF = true
        options.includeQuartile = true
        let store = GrantDataStore(
            metadata: metadata,
            publicationAuthors: [currentUser],
            publicationJournals: [journal],
            publicationRecords: [publication]
        )

        let publicationItem = try XCTUnwrap(
            store.amaSections(
                exportLanguage: .english,
                options: options,
                includedSections: [.publishedOriginalArticles]
            ).first?.items.first
        )
        let cvItem = try XCTUnwrap(
            exportedSection(
                titled: "Original articles",
                in: store.cvExportDocument(
                    style: .own,
                    exportLanguage: .english,
                    includedSections: [.originalArticles],
                    publicationOptions: options
                )
            )?.subsections.flatMap(\.amaItems).first
        )

        XCTAssertTrue(publicationItem.plain.contains("(IF 5.4, Q2)"))
        XCTAssertFalse(publicationItem.plain.contains("?"))
        XCTAssertTrue(cvItem.plain.contains("(IF 5.4, Q2)"))
        XCTAssertFalse(cvItem.plain.contains("?"))
    }

    @MainActor
    func testPublicationAndCVExportCanUsePublishedStatusDateInBibliographicTail() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-pontus"
        let currentUser = PublicationAuthor(id: "author-pontus", name: "Pontus af Lindholm")
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Publication date article",
            journal: "Medical Journal",
            status: PublicationStatus.published.rawValue,
            pmid: "10000001",
            volume: "24",
            issue: "1",
            articleNumber: "340",
            year: "2025",
            publicationType: "Original Article",
            authorNames: ["Pontus af Lindholm"],
            statusTimeline: [
                PublicationStatusEntry(
                    status: PublicationStatus.published.rawValue,
                    journal: "Medical Journal",
                    date: "2025-08-18"
                )
            ]
        )
        let store = GrantDataStore(
            metadata: metadata,
            publicationAuthors: [currentUser],
            publicationRecords: [publication]
        )
        let defaultItem = store.amaCitationItem(for: publication)

        XCTAssertTrue(defaultItem.plain.contains("2025;24(1):340"))
        XCTAssertFalse(defaultItem.plain.contains("2025 Aug 18;24(1):340"))

        var options = PublicationExportOptions()
        options.includePublicationDate = true
        let publicationItem = try XCTUnwrap(
            store.amaSections(
                exportLanguage: .english,
                options: options,
                includedSections: [.publishedOriginalArticles]
            ).first?.items.first
        )
        let cvItem = try XCTUnwrap(
            exportedSection(
                titled: "Original articles",
                in: store.cvExportDocument(
                    style: .own,
                    exportLanguage: .english,
                    includedSections: [.originalArticles],
                    publicationOptions: options
                )
            )?.subsections.flatMap(\.amaItems).first
        )

        XCTAssertTrue(publicationItem.plain.contains("2025 Aug 18;24(1):340"))
        XCTAssertTrue(cvItem.plain.contains("2025 Aug 18;24(1):340"))
    }

    @MainActor
    func testCVReviewExportShowsOnlyYearForReviewDates() throws {
        let review = CVReviewEntry(
            id: "review-1",
            date: "2026-04-21",
            journalName: "Journal of Internal Medicine",
            reference: "1234567"
        )
        let store = GrantDataStore(cvReviewEntries: [review])

        let ownDocument = store.cvExportDocument(
            style: .own,
            exportLanguage: .english,
            includedSections: [.reviews]
        )
        let ownReviewSection = try XCTUnwrap(exportedSection(titled: "Reviews", in: ownDocument))
        XCTAssertEqual(ownReviewSection.items, ["2026\tJournal of Internal Medicine (1234567)"])
        XCTAssertFalse(ownReviewSection.items.joined(separator: "\n").contains("2026-04-21"))

        let liuDocument = store.cvExportDocument(
            style: .liu,
            exportLanguage: .english,
            includedSections: [.reviews]
        )
        let liuReviewSubsection = try XCTUnwrap(
            exportedSubsection(
                titled: "3.5.4 Refereeuppdrag för tidskrifter. Ange vilka tidskrifter och genomsnittligt antal uppdrag per år",
                in: liuDocument
            )
        )
        XCTAssertEqual(liuReviewSubsection.items, ["2026\tJournal of Internal Medicine (1234567)"])
        XCTAssertFalse(liuReviewSubsection.items.joined(separator: "\n").contains("2026-04-21"))
    }

    @MainActor
    func testCVExportUsesSelectedCurrentUserAuthorName() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-real"
        let placeholder = PublicationAuthor(id: "author-placeholder", name: "Ny författare")
        let selectedAuthor = PublicationAuthor(
            id: "author-real",
            name: "Anna Andersson",
            firstName: "Anna",
            lastName: "Andersson"
        )
        let store = GrantDataStore(
            metadata: metadata,
            publicationAuthors: [placeholder, selectedAuthor]
        )

        let document = store.cvExportDocument(
            style: .own,
            exportLanguage: .swedish,
            includedSections: [.contactDetails]
        )

        XCTAssertEqual(store.currentUserAuthor()?.name, "Anna Andersson")
        XCTAssertEqual(document.subtitle, "Anna Andersson")
        XCTAssertNotEqual(document.subtitle, "Ny författare")
    }

    @MainActor
    func testCVContactDetailsSourceIDsRouteHomeAndWorkAddressesToCorrectEditors() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-real"
        let selectedAuthor = PublicationAuthor(
            id: "author-real",
            name: "Anna Andersson",
            firstName: "Anna",
            lastName: "Andersson",
            homeAddress: "Exempelgatan 1A, 12345 Exempelvik",
            affiliations: [
                PublicationAffiliation(
                    organization: "Exempelköping University",
                    department: "Department of Example Medicine, and Caring Sciences",
                    city: "Exempelvik",
                    country: "Sweden",
                    email: "anna@example.test",
                    isPrimary: true
                )
            ]
        )
        let store = GrantDataStore(
            metadata: metadata,
            publicationAuthors: [selectedAuthor]
        )

        let document = store.cvExportDocument(
            style: .own,
            exportLanguage: .english,
            includedSections: [.contactDetails]
        )

        let contactSection = try XCTUnwrap(exportedSection(titled: "Contact details", in: document))
        XCTAssertTrue(contactSection.items[0].hasPrefix("Home address"))
        XCTAssertTrue(contactSection.items[1].hasPrefix("Work address"))
        XCTAssertEqual(contactSection.itemSourceIDs?[0], "profile-editor")
        XCTAssertEqual(contactSection.itemSourceIDs?[1], "author-author-real")
        XCTAssertEqual(contactSection.itemSourceIDs?[2], "author-author-real")
    }

    @MainActor
    func testCVTeachingDoctoralRowsUseExactDoctoralCandidateSourceIDs() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-pontus"
        let currentUser = PublicationAuthor(
            id: "author-pontus",
            name: "Pontus af Lindholm",
            firstName: "Pontus",
            lastName: "af Lindholm"
        )
        let includedBySupervisorName = DoctoralCandidateRecord(
            id: "doctoral-right",
            candidateName: "Jolin Tidlund",
            doctoralProjectName: "The Importance of early nutrition, infections and microbioma for the development of psoriasis",
            institution: "Exempelköping University",
            supervisors: [
                DoctoralSupervisorLink(name: "Pontus af Lindholm")
            ],
            supervisionPeriods: [
                DoctoralSupervisionPeriod(from: "2025-01-01", to: "")
            ]
        )
        let otherCandidate = DoctoralCandidateRecord(
            id: "doctoral-wrong",
            candidateName: "Other Candidate",
            doctoralProjectName: "The Importance of early nutrition, infections and microbioma for the development of psoriasis",
            institution: "Exempelköping University",
            supervisors: [
                DoctoralSupervisorLink(authorID: "author-other", name: "Other Supervisor")
            ],
            supervisionPeriods: [
                DoctoralSupervisionPeriod(from: "2025-01-01", to: "")
            ]
        )
        let store = GrantDataStore(
            metadata: metadata,
            doctoralCandidates: [otherCandidate, includedBySupervisorName],
            publicationAuthors: [currentUser]
        )

        XCTAssertEqual(store.doctoralCandidatesForCurrentUser().map(\.id), ["doctoral-right"])

        let document = store.cvExportDocument(
            style: .own,
            exportLanguage: .english,
            includedSections: [.teaching]
        )
        let section = try XCTUnwrap(exportedSection(titled: "Supervision and teaching activities", in: document))
        let rowIndex = try XCTUnwrap(section.items.firstIndex { $0.contains("Jolin Tidlund") })
        XCTAssertEqual(section.itemSourceIDs?[rowIndex], "doctoral-doctoral-right")
    }

    @MainActor
    func testCVPersonalResumeExportOmitsBlankRichTextParagraphs() throws {
        var resume = CVPersonalResume()
        resume.contentEn = CVRichTextDocument(paragraphs: [
            CVRichTextParagraph(runs: [CVRichTextRun(text: "First resume paragraph.")]),
            CVRichTextParagraph(runs: []),
            CVRichTextParagraph(runs: [CVRichTextRun(text: "Second resume paragraph.")])
        ])
        let store = GrantDataStore(cvPersonalResume: resume)

        let document = store.cvExportDocument(
            style: .own,
            exportLanguage: .english,
            includedSections: [.personalResume]
        )
        let section = try XCTUnwrap(exportedSection(titled: "Personal resume", in: document))

        XCTAssertEqual(section.richParagraphs.map { $0.runs.map(\.text).joined() }, [
            "First resume paragraph.",
            "Second resume paragraph."
        ])
    }

    @MainActor
    func testOwnCVSourceIDsCoverProfileTeachingAndMembershipRows() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-self"
        let currentUser = PublicationAuthor(
            id: "author-self",
            name: "Pontus af Lindholm",
            firstName: "Pontus",
            lastName: "af Lindholm",
            employments: [
                PublicationAuthorEmployment(
                    id: "employment-current",
                    from: "2024-01-01",
                    title: "Researcher",
                    organization: "Exempelköping University"
                )
            ],
            educationEntries: [
                PublicationAuthorEducation(
                    id: "education-degree",
                    level: .doctoral,
                    to: "2024-09-27",
                    degree: "PhD",
                    organization: "Exempelköping University"
                )
            ]
        )
        let teaching = TeachingAssignment(
            id: "teaching-source",
            periods: [TeachingAssignmentPeriod(from: "2025-01-01", to: "2025-06-30")],
            activityName: "Teaching activity"
        )
        let association = OrganizationRecord(
            id: "association-source",
            nameSv: "Svensk förening",
            nameEn: "Swedish Association",
            roles: [.association],
            membershipFrom: "2025"
        )
        let store = GrantDataStore(
            metadata: metadata,
            organizations: [association],
            teachingAssignments: [teaching],
            publicationAuthors: [currentUser]
        )

        let document = store.cvExportDocument(
            style: .own,
            exportLanguage: .english,
            includedSections: [.degreesAndLicenses, .currentPositions, .teaching, .currentAssociationMemberships]
        )

        let degrees = try XCTUnwrap(exportedSection(titled: "Degrees and licenses", in: document))
        XCTAssertEqual(degrees.itemSourceIDs, ["profile-editor"])
        let positions = try XCTUnwrap(exportedSection(titled: "Current positions", in: document))
        XCTAssertEqual(positions.itemSourceIDs, ["profile-editor"])
        let teachingSection = try XCTUnwrap(exportedSection(titled: "Supervision and teaching activities", in: document))
        XCTAssertEqual(teachingSection.itemSourceIDs, ["teaching-teaching-source"])
        let memberships = try XCTUnwrap(exportedSection(titled: "Current association memberships", in: document))
        XCTAssertEqual(memberships.itemSourceIDs, ["organization-association-source"])
    }

    @MainActor
    func testPublicationExportHidesSharedLastNoteWhenLastAuthorsAreTruncated() throws {
        let currentUser = PublicationAuthor(
            id: "author-pontus",
            name: "Pontus af Lindholm",
            firstName: "Pontus",
            lastName: "af Lindholm"
        )
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Long author list",
            journal: "Medical Journal",
            status: PublicationStatus.published.rawValue,
            year: "2025",
            isPeerReviewed: true,
            authorNames: [
                "Pontus af Lindholm",
                "Alice Andersson",
                "Bertil Berg",
                "Carla Carlsson",
                "David Dahl"
            ],
            sharedLastAuthorship: true
        )
        var options = PublicationExportOptions()
        options.authorCountBeforeEtAl = 3
        let store = GrantDataStore(
            publicationAuthors: [currentUser],
            publicationRecords: [publication]
        )

        let publicationItem = try XCTUnwrap(
            store.amaSections(
                exportLanguage: .english,
                options: options,
                includedSections: [.publishedOriginalArticles]
            ).first?.items.first
        )
        let cvItem = try XCTUnwrap(
            exportedSection(
                titled: "Original articles",
                in: store.cvExportDocument(
                    style: .own,
                    exportLanguage: .english,
                    includedSections: [.originalArticles],
                    publicationOptions: options
                )
            )?.subsections.flatMap(\.amaItems).first
        )

        XCTAssertFalse(publicationItem.authors.contains("*"))
        XCTAssertFalse(publicationItem.plain.contains("Shared last"))
        XCTAssertEqual(publicationItem.note, "")
        XCTAssertEqual(cvItem.note, "")
    }

    @MainActor
    func testPublicationExportKeepsSharedLastNoteWhenSharedLastMarkerIsVisible() throws {
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Visible shared last author",
            journal: "Medical Journal",
            status: PublicationStatus.published.rawValue,
            year: "2025",
            isPeerReviewed: true,
            authorNames: [
                "Pontus af Lindholm",
                "Alice Andersson",
                "Bertil Berg",
                "Carla Carlsson"
            ],
            sharedLastAuthorship: true
        )
        var options = PublicationExportOptions()
        options.authorCountBeforeEtAl = 3
        let store = GrantDataStore(publicationRecords: [publication])

        let item = try XCTUnwrap(
            store.amaSections(
                exportLanguage: .english,
                options: options,
                includedSections: [.publishedOriginalArticles]
            ).first?.items.first
        )

        XCTAssertTrue(item.authors.contains("*"))
        XCTAssertEqual(item.note, "*Shared last authorship")
        XCTAssertTrue(item.plain.contains("*Shared last authorship"))
    }

    @MainActor
    func testHeartLungfondenPublicationExportUsesA4TimesNewRomanAndShortHeadings() throws {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let original = PublicationRecord(
            id: "publication-original",
            title: "Original article",
            journal: "Medical Journal",
            status: PublicationStatus.published.rawValue,
            statusDate: "\(currentYear)-01-01",
            year: "\(currentYear)",
            publicationType: "Original Article",
            isPeerReviewed: true,
            authorNames: ["Pontus af Lindholm"]
        )
        let review = PublicationRecord(
            id: "publication-review",
            title: "Review article",
            journal: "Medical Journal",
            status: PublicationStatus.published.rawValue,
            statusDate: "\(currentYear)-01-01",
            year: "\(currentYear)",
            publicationType: "Review Article",
            isPeerReviewed: true,
            authorNames: ["Pontus af Lindholm"]
        )
        let store = GrantDataStore(publicationRecords: [original, review])

        let payload = store.publicationHeartLungfondenPreviewDocument(
            configuration: PublicationHeartLungfondenExportConfiguration()
        )

        XCTAssertEqual(payload.sections.map(\.title), ["Originalarbeten", "Andra arbeten"])
        XCTAssertEqual(payload.fontFamily, "Times New Roman")
        XCTAssertEqual(payload.fontSizeHalfPoints, 24)
        XCTAssertEqual(payload.titleFontSizeHalfPoints, 32)
        XCTAssertEqual(payload.sectionFontSizeHalfPoints, 28)
        XCTAssertEqual(payload.pageWidthTwips, 11906)
        XCTAssertEqual(payload.pageHeightTwips, 16838)
        XCTAssertEqual(payload.pageSizeCode, 9)

        let outputURL = isolatedStorageDirectory.appendingPathComponent("hjart-lungfonden.docx")
        try GrantDataStore.renderHeartLungfondenDocument(payload, to: outputURL)

        let inspectionScript = isolatedStorageDirectory.appendingPathComponent("inspect-docx.py")
        try """
        import sys
        import zipfile

        with zipfile.ZipFile(sys.argv[1]) as archive:
            sys.stdout.write(archive.read("word/document.xml").decode("utf-8"))
        """.write(to: inspectionScript, atomically: true, encoding: .utf8)

        let result = try ExternalProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [inspectionScript.path, outputURL.path],
            timeout: 10
        )
        let documentXML = result.stdout

        XCTAssertTrue(documentXML.contains(#"<w:pgSz w:w="11906" w:h="16838" w:code="9"/>"#))
        XCTAssertTrue(documentXML.contains(#"<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>"#))
        XCTAssertTrue(documentXML.contains(#"<w:sz w:val="32"/><w:szCs w:val="32"/>"#))
        XCTAssertTrue(documentXML.contains(#"<w:sz w:val="28"/><w:szCs w:val="28"/>"#))
        XCTAssertTrue(documentXML.contains(#"<w:sz w:val="24"/><w:szCs w:val="24"/>"#))
        XCTAssertTrue(documentXML.contains("Originalarbeten"))
        XCTAssertTrue(documentXML.contains("Andra arbeten"))
        XCTAssertFalse(documentXML.contains("tidskrifter med refereesystem"))
        XCTAssertFalse(documentXML.contains("ledare, översiktsartiklar"))
    }

    @MainActor
    func testHeartLungfondenPublicationExportSortOrderCanBeReversed() throws {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let older = PublicationRecord(
            id: "publication-older",
            title: "Older original article",
            journal: "Medical Journal",
            status: PublicationStatus.published.rawValue,
            statusDate: "\(currentYear - 1)-01-01",
            year: "\(currentYear - 1)",
            publicationType: "Original Article",
            isPeerReviewed: true,
            authorNames: ["Pontus af Lindholm"]
        )
        let newer = PublicationRecord(
            id: "publication-newer",
            title: "Newer original article",
            journal: "Medical Journal",
            status: PublicationStatus.published.rawValue,
            statusDate: "\(currentYear)-01-01",
            year: "\(currentYear)",
            publicationType: "Original Article",
            isPeerReviewed: true,
            authorNames: ["Pontus af Lindholm"]
        )
        let store = GrantDataStore(publicationRecords: [newer, older])

        let ascendingPayload = store.publicationHeartLungfondenPreviewDocument(
            configuration: PublicationHeartLungfondenExportConfiguration()
        )
        XCTAssertEqual(
            ascendingPayload.sections.first?.items.map(\.title),
            ["Older original article", "Newer original article"]
        )

        var descendingConfiguration = PublicationHeartLungfondenExportConfiguration()
        descendingConfiguration.sortOrder = .newestFirst
        let descendingPayload = store.publicationHeartLungfondenPreviewDocument(configuration: descendingConfiguration)
        XCTAssertEqual(
            descendingPayload.sections.first?.items.map(\.title),
            ["Newer original article", "Older original article"]
        )
    }

    @MainActor
    func testCVProtocolSectionIncludesCanonicalAndLegacyProtocolTypes() throws {
        let currentUser = PublicationAuthor(
            id: "author-pontus",
            name: "Pontus af Lindholm",
            firstName: "Pontus",
            lastName: "af Lindholm"
        )
        let canonicalProtocol = PublicationRecord(
            id: "publication-protocol",
            title: "Canonical protocol",
            journal: "BMJ Open",
            status: PublicationStatus.published.rawValue,
            year: "2025",
            publicationType: "Protocol",
            isPeerReviewed: true,
            authorNames: ["Pontus af Lindholm"]
        )
        let legacyProtocol = PublicationRecord(
            id: "publication-protocol-legacy",
            title: "Legacy protocol",
            journal: "Trials",
            status: PublicationStatus.published.rawValue,
            year: "2024",
            publicationType: "Protocol article",
            isPeerReviewed: true,
            authorNames: ["Pontus af Lindholm"]
        )
        let store = GrantDataStore(
            publicationAuthors: [currentUser],
            publicationRecords: [canonicalProtocol, legacyProtocol]
        )

        let document = store.cvExportDocument(
            style: .own,
            exportLanguage: .english,
            includedSections: [.originalArticles, .protocolArticles]
        )

        let protocolSection = try XCTUnwrap(exportedSection(titled: "Protocol articles", in: document))
        let originalSection = try XCTUnwrap(exportedSection(titled: "Original articles", in: document))
        let protocolItems = protocolSection.subsections.flatMap(\.amaItems)
        let originalItems = originalSection.subsections.flatMap(\.amaItems)

        XCTAssertEqual(Set(protocolItems.map(\.title)), ["Canonical protocol", "Legacy protocol"])
        XCTAssertTrue(originalItems.isEmpty)
    }

    @MainActor
    func testCVOtherPublicationsDeduplicateLegacyNonPeerReviewedEntriesAndLiftEnglishTitle() throws {
        let currentUser = PublicationAuthor(
            id: "author-pontus",
            name: "Pontus af Lindholm",
            firstName: "Pontus",
            lastName: "af Lindholm"
        )
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Kvällspromenader och hemblodtryck i en exempelkohort [Evening walks and home blood pressure in an example cohort]",
            journal: "Vaskulär Medicin [English: Journal of The Swedish Society of Hypertension, Stroke and Vascular Medicine]",
            status: PublicationStatus.published.rawValue,
            year: "2024",
            isPeerReviewed: false,
            authorNames: ["Pontus af Lindholm"]
        )
        let manualEntry = CVOtherPublicationEntry(
            id: "other-1",
            date: "2024",
            category: "Övriga publikationer, ej peer review",
            authors: "af Lindholm P",
            title: "Kvällspromenader och hemblodtryck i en exempelkohort [Evening walks and home blood pressure in an example cohort]",
            outlet: "Vaskulär Medicin [English: Journal of The Swedish Society of Hypertension, Stroke and Vascular Medicine]",
            publicationData: "12(3):45-47. Swedish."
        )
        let store = GrantDataStore(
            cvOtherPublications: [manualEntry],
            publicationAuthors: [currentUser],
            publicationRecords: [publication]
        )

        let document = store.cvExportDocument(
            style: .own,
            exportLanguage: .english,
            includedSections: [.otherPublications]
        )

        XCTAssertEqual(document.sections.count, 1)

        let section = try XCTUnwrap(exportedSection(titled: "Other publications, not peer reviewed", in: document))
        XCTAssertEqual(section.subsections.count, 1)
        XCTAssertEqual(section.subsections[0].title, "")
        XCTAssertEqual(section.subsections[0].amaItems.count, 1)
        XCTAssertTrue(section.subsections[0].items.isEmpty)
        XCTAssertNil(exportedSection(titled: "Other publications", in: document))
        XCTAssertFalse(section.subsections.contains(where: { $0.title.contains("Övriga") }))
    }

    @MainActor
    func testVetenskapsradetPublicationCandidateUsesJournalRankingMetrics() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-pontus"
        let currentUser = PublicationAuthor(id: "author-pontus", name: "Pontus af Lindholm")
        let journal = PublicationJournal(
            id: "journal-1",
            name: "High Impact Journal",
            abbreviatedName: "High Impact J",
            rankingRows: [
                JournalRankingRow(
                    kind: .clarivateScieJIF,
                    yearlyMetrics: [JournalYearMetric(year: 2024, value: "8,7", quartile: "Q1")]
                ),
                JournalRankingRow(
                    kind: .norwegianList,
                    yearlyMetrics: [JournalYearMetric(year: 2024, value: "2", quartile: "")]
                ),
            ],
            category: "General medicine"
        )
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Strong original article",
            journal: "High Impact Journal",
            status: PublicationStatus.published.rawValue,
            year: "2024",
            isPeerReviewed: true,
            authorNames: ["Pontus af Lindholm"]
        )
        let store = GrantDataStore(
            metadata: metadata,
            publicationAuthors: [currentUser],
            publicationJournals: [journal],
            publicationRecords: [publication]
        )

        let candidate = try XCTUnwrap(
            store.vetenskapsradetOutputCandidates().first(where: { $0.sourceID == publication.id })
        )

        XCTAssertEqual(candidate.latestImpactFactorValue, 8.7, accuracy: 0.0001)
        XCTAssertEqual(candidate.latestNorwegianLevelValue, 2, accuracy: 0.0001)
        XCTAssertEqual(candidate.impactFactorText, "8.7")
        XCTAssertEqual(candidate.norwegianLevelText, "2")
    }

    func testCVVROutputFilterOptionsCombineSearchImpactFactorAndNorwegianLevel() {
        let matchingCandidate = CVVROutputCandidate(
            id: "publication:1",
            sourceKind: .publication,
            sourceID: "publication-1",
            category: .peerReviewedOriginalArticle,
            authorsText: "Pontus af Lindholm",
            title: "Angstrom study",
            journalText: "High Impact Journal",
            citation: "",
            noteSuggestion: "",
            yearText: "2024",
            sortDate: "2024-01-01",
            latestImpactFactorValue: 8.7,
            latestNorwegianLevelValue: 2,
            impactFactorText: "8.7",
            norwegianLevelText: "2"
        )
        var lowImpactCandidate = matchingCandidate
        lowImpactCandidate.id = "publication:2"
        lowImpactCandidate.latestImpactFactorValue = 2.1
        lowImpactCandidate.impactFactorText = "2.1"

        var wrongNorwegianCandidate = matchingCandidate
        wrongNorwegianCandidate.id = "publication:3"
        wrongNorwegianCandidate.latestNorwegianLevelValue = 1
        wrongNorwegianCandidate.norwegianLevelText = "1"

        var wrongSearchCandidate = matchingCandidate
        wrongSearchCandidate.id = "publication:4"
        wrongSearchCandidate.title = "Other topic"

        let options = CVVROutputFilterOptions(
            searchText: "angstrom",
            minimumImpactFactor: 5,
            includedNorwegianLevels: [2]
        )

        XCTAssertTrue(options.matches(matchingCandidate))
        XCTAssertFalse(options.matches(lowImpactCandidate))
        XCTAssertFalse(options.matches(wrongNorwegianCandidate))
        XCTAssertFalse(options.matches(wrongSearchCandidate))
    }

    @MainActor
    func testCVConferenceContributionAddsPeriodAfterFinalPresenterName() throws {
        let contribution = CVConferenceContribution(
            id: "conference-1",
            status: .presented,
            from: "2025-05-23",
            to: "2025-05-23",
            title: "Self-measured home orthostatic hypo- and hypertension",
            name: "European Meeting on Hypertension",
            contributorNames: ["Fredrik Falk", "Pontus af Lindholm"],
            presentedBy: "Fredrik Falk",
            meeting: "European Meeting on Hypertension",
            meetingCity: "Milan",
            meetingCountry: "Italy"
        )
        let store = GrantDataStore(cvConferenceContributions: [contribution])

        let document = store.cvExportDocument(
            style: .own,
            exportLanguage: .english,
            includedSections: [.conferenceContributions]
        )

        let line = try XCTUnwrap(exportedItem(containing: contribution.titleEn, in: document))
        XCTAssertTrue(line.hasSuffix("Presented by Fredrik Falk."))
    }

    @MainActor
    func testDoctoralThesisExportUsesConfiguredPublisherNameLength() throws {
        let currentUser = PublicationAuthor(
            id: "author-pontus",
            name: "Pontus af Lindholm",
            firstName: "Pontus",
            lastName: "af Lindholm"
        )
        let thesis = CVOtherPublicationEntry(
            id: "thesis-1",
            date: "2024",
            category: "Doktorsavhandling",
            authors: "Pontus af Lindholm",
            title: "Blood pressure in an example cohort",
            outlet: "Exempelköping University Press",
            publisherShortName: "Exempelköping Univ Press",
            publicationData: "English.",
            city: "Exempelköping",
            doi: "10.0000/9780000000000",
            language: "English"
        )
        let store = GrantDataStore(
            cvOtherPublications: [thesis],
            publicationAuthors: [currentUser]
        )

        var abbreviatedOptions = PublicationExportOptions()
        abbreviatedOptions.journalNameMode = .abbreviated

        var fullOptions = PublicationExportOptions()
        fullOptions.journalNameMode = .full

        let abbreviatedOwnDocument = store.cvExportDocument(
            style: .own,
            exportLanguage: .english,
            includedSections: [.doctoralThesis],
            publicationOptions: abbreviatedOptions
        )
        let fullOwnDocument = store.cvExportDocument(
            style: .own,
            exportLanguage: .english,
            includedSections: [.doctoralThesis],
            publicationOptions: fullOptions
        )
        let abbreviatedLiUDocument = store.cvExportDocument(
            style: .liu,
            exportLanguage: .english,
            includedSections: [.doctoralThesis],
            publicationOptions: abbreviatedOptions
        )
        let fullLiUDocument = store.cvExportDocument(
            style: .liu,
            exportLanguage: .english,
            includedSections: [.doctoralThesis],
            publicationOptions: fullOptions
        )

        let abbreviatedOwnLine = try XCTUnwrap(exportedItem(containing: thesis.titleEn, in: abbreviatedOwnDocument))
        let fullOwnLine = try XCTUnwrap(exportedItem(containing: thesis.titleEn, in: fullOwnDocument))
        let abbreviatedLiULine = try XCTUnwrap(exportedItem(containing: thesis.titleEn, in: abbreviatedLiUDocument))
        let fullLiULine = try XCTUnwrap(exportedItem(containing: thesis.titleEn, in: fullLiUDocument))

        for line in [abbreviatedOwnLine, abbreviatedLiULine] {
            XCTAssertTrue(line.contains("Exempelköping Univ Press, Exempelköping"))
            XCTAssertFalse(line.contains("Exempelköping University Press"))
        }

        for line in [fullOwnLine, fullLiULine] {
            XCTAssertTrue(line.contains("Exempelköping University Press, Exempelköping"))
            XCTAssertFalse(line.contains("Exempelköping Univ Press"))
        }
    }

    @MainActor
    func testDoctoralThesisExportUnderlinesCoSupervisorWithDottedInitial() throws {
        let thesis = CVOtherPublicationEntry(
            id: "thesis-1",
            date: "2024",
            category: "Doktorsavhandling",
            authors: "Pontus af Lindholm",
            title: "Blood pressure in an example cohort",
            outlet: "Exempelköping University Press",
            city: "Exempelköping",
            language: "English",
            mainSupervisor: "Karin Exempel",
            coSupervisor: "Erik J. Exempelsson"
        )
        let store = GrantDataStore(cvOtherPublications: [thesis])

        let ownDocument = store.cvExportDocument(
            style: .own,
            exportLanguage: .english,
            includedSections: [.doctoralThesis],
            underlineDoctoralCoSupervisor: true
        )
        let liuDocument = store.cvExportDocument(
            style: .liu,
            exportLanguage: .english,
            includedSections: [.doctoralThesis],
            underlineDoctoralCoSupervisor: true
        )

        for document in [ownDocument, liuDocument] {
            let line = try XCTUnwrap(exportedItem(containing: thesis.titleEn, in: document))
            XCTAssertTrue(line.contains("Co-supervisor: [[UNDERLINE]]Erik J. Exempelsson[[/UNDERLINE]]"))
        }
    }

    @MainActor
    func testLiUCVExportUsesSwedishTemplateAndOmitsEmptyHeadings() throws {
        let currentUser = PublicationAuthor(
            id: "author-pontus",
            name: "Pontus af Lindholm",
            firstName: "Pontus",
            lastName: "af Lindholm",
            birthDate: "1970-01-02"
        )
        let article = PublicationRecord(
            id: "publication-article",
            title: "Peer reviewed article",
            journal: "Medical Journal",
            status: PublicationStatus.published.rawValue,
            statusDate: "2026-01-01",
            year: "2026",
            publicationType: "Original Article",
            isPeerReviewed: true,
            authorNames: ["Pontus af Lindholm"]
        )
        let publishedOther = PublicationRecord(
            id: "publication-other",
            title: "Clinical handbook",
            journal: "Book Outlet",
            status: PublicationStatus.published.rawValue,
            statusDate: "2025-01-01",
            year: "2025",
            publicationType: "Book",
            isPeerReviewed: false,
            authorNames: ["Pontus af Lindholm"]
        )
        let duplicateManualOther = CVOtherPublicationEntry(
            id: "manual-duplicate",
            date: "2025",
            category: "Bok",
            authors: "Pontus af Lindholm",
            title: "Clinical handbook",
            outlet: "Manual source"
        )
        let uniqueManualOther = CVOtherPublicationEntry(
            id: "manual-unique",
            date: "2024",
            category: "Rapport",
            authors: "Pontus af Lindholm",
            title: "Unique report",
            outlet: "Reports"
        )
        let store = GrantDataStore(
            cvOtherPublications: [duplicateManualOther, uniqueManualOther],
            publicationAuthors: [currentUser],
            publicationRecords: [article, publishedOther]
        )

        let document = store.cvExportDocument(
            style: .liu,
            exportLanguage: .english,
            includedSections: [.contactDetails, .originalArticles, .otherPublications, .teaching]
        )

        XCTAssertEqual(document.style, CVDocumentExportStyle.liu.rawValue)
        XCTAssertEqual(document.highlightName, "")
        XCTAssertTrue(document.summaryLines.isEmpty)
        XCTAssertTrue(document.summaryRichParagraphs.isEmpty)
        XCTAssertEqual(document.sections.map(\.title), [
            "1.0 Personuppgifter",
            "3.0 Vetenskapliga meriter",
            "4.0 Pedagogiska meriter",
        ])
        XCTAssertFalse(document.sections.map(\.title).contains("2.0 Examina"))
        XCTAssertFalse(document.sections.map(\.title).contains("5.0 Annan relevant yrkesskicklighet"))
        XCTAssertFalse(document.sections.map(\.title).contains("6.0 Administrativ skicklighet - chefs- och/eller ledarskapsuppdrag"))

        let subsectionTitles = document.sections.flatMap { $0.subsections.map(\.title) }
        XCTAssertTrue(subsectionTitles.contains("1.1 Namn"))
        XCTAssertTrue(subsectionTitles.contains("1.2 Personnummer"))
        XCTAssertTrue(subsectionTitles.contains("3.3 Publikationslista"))
        XCTAssertTrue(subsectionTitles.contains("3.3.2 Övriga publikationer"))
        XCTAssertTrue(subsectionTitles.contains("4.1 Beskrivning av egen pedagogisk verksamhet på grundläggande/avancerad/forskarnivå"))
        XCTAssertFalse(subsectionTitles.contains("1.4.1 Epostadress"))
        XCTAssertFalse(subsectionTitles.contains { $0.contains("Manuscripts") })
        XCTAssertFalse(subsectionTitles.contains { $0.contains("Current association memberships") })
        XCTAssertFalse(subsectionTitles.contains { $0.hasPrefix("3.3.3") })

        let teaching = try XCTUnwrap(exportedSubsection(titled: "4.1 Beskrivning av egen pedagogisk verksamhet på grundläggande/avancerad/forskarnivå", in: document))
        XCTAssertTrue(teaching.paragraphs.contains("Universitet/högskola"))
        XCTAssertTrue(teaching.paragraphs.contains("Kursansvar/examinator"))

        let otherPublications = try XCTUnwrap(exportedSubsection(titled: "3.3.2 Övriga publikationer", in: document))
        XCTAssertTrue(otherPublications.amaItems.contains { $0.title == "Clinical handbook" })
        XCTAssertTrue(otherPublications.items.contains { $0.contains("Unique report") })
        XCTAssertFalse(otherPublications.items.contains { $0.contains("Clinical handbook") })
    }

    @MainActor
    func testLiUCVDocumentRenderingOmitsOwnCVPreambleAndLayoutChrome() throws {
        let store = GrantDataStore()
        var document = CVExportDocument(
            style: CVDocumentExportStyle.liu.rawValue,
            exportLanguage: AppLanguage.english.rawValue,
            highlightName: "Pontus af Lindholm",
            title: "Pontus af Lindholm",
            subtitle: "Personal profile",
            summaryLines: ["Summary from own CV"],
            summaryRichParagraphs: [
                CVExportRichTextParagraph(runs: [
                    CVExportRichTextRun(text: "Rich summary from own CV")
                ])
            ],
            sections: [
                CVExportSection(
                    title: "1.0 Personuppgifter",
                    subsections: [
                        CVExportSubsection(title: "1.1 Namn", items: ["Pontus af Lindholm"])
                    ]
                ),
                CVExportSection(
                    title: "4.0 Pedagogiska meriter",
                    subsections: [
                        CVExportSubsection(
                            title: "4.1 Beskrivning av egen pedagogisk verksamhet på grundläggande/avancerad/forskarnivå",
                            paragraphs: ["Universitet/högskola"],
                            items: ["Undervisning med [[PUBDATA]]metadata[[/PUBDATA]]\tspalt, 6[[SUP]]th[[/SUP]] semester"]
                        )
                    ]
                ),
            ],
            headerText: "Ignored header",
            footerText: "Ignored footer",
            includePageNumbers: true
        )

        store.applyLayout(
            ExportDocumentLayoutOptions(currentDatePlacement: .header, includePageNumbers: true),
            to: &document,
            exportLanguage: .english
        )

        XCTAssertEqual(document.headerText, "")
        XCTAssertEqual(document.footerText, "")
        XCTAssertFalse(document.includePageNumbers)

        let outputURL = isolatedStorageDirectory.appendingPathComponent("liu-cv.docx")
        try GrantDataStore.renderCVDocument(document, to: outputURL)

        let documentXML = try docxEntry(named: "word/document.xml", in: outputURL)
        let headerXML = try docxEntry(named: "word/header1.xml", in: outputURL)
        let footerXML = try docxEntry(named: "word/footer1.xml", in: outputURL)

        XCTAssertTrue(documentXML.contains("1.0 Personuppgifter"))
        XCTAssertTrue(documentXML.contains("4.1 Beskrivning av egen pedagogisk verksamhet på grundläggande/avancerad/forskarnivå"))
        XCTAssertTrue(documentXML.contains("Undervisning med metadata spalt, 6"))
        XCTAssertTrue(documentXML.contains(#"<w:vertAlign w:val="superscript"/>"#))
        XCTAssertFalse(documentXML.contains("Personal profile"))
        XCTAssertFalse(documentXML.contains("Summary from own CV"))
        XCTAssertFalse(documentXML.contains("Rich summary from own CV"))
        XCTAssertFalse(documentXML.contains("Ignored header"))
        XCTAssertFalse(documentXML.contains("Ignored footer"))
        XCTAssertFalse(documentXML.contains("headerReference"))
        XCTAssertFalse(documentXML.contains("footerReference"))
        XCTAssertFalse(headerXML.contains("Ignored header"))
        XCTAssertFalse(footerXML.contains("Ignored footer"))
        XCTAssertTrue(documentXML.contains(#"<w:pStyle w:val="LiuSection"/>"#))
        XCTAssertTrue(documentXML.contains(#"<w:pStyle w:val="LiuSubsection"/>"#))
        XCTAssertTrue(documentXML.contains(#"<w:b/><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/><w:sz w:val="24"/><w:szCs w:val="24"/>"#))
        XCTAssertTrue(documentXML.contains(#"<w:i/><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/><w:szCs w:val="24"/>"#))
        XCTAssertFalse(documentXML.contains("[[PUBDATA]]"))
        XCTAssertFalse(documentXML.contains("[[SUP]]"))
    }

    @MainActor
    func testAnnualReportGrantApplicationCountMatchesVisibleStatusRows() throws {
        let currentUser = "Pontus af Lindholm"
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-pontus"
        let currentUserAuthor = PublicationAuthor(id: "author-pontus", name: currentUser)
        let waiting = GrantApplication(
            id: "waiting",
            rowNumber: 1,
            organization: "Funder",
            grantName: "Waiting grant",
            appliedOn: "2026-01-10",
            coApplicants: [currentUser]
        )
        let granted = GrantApplication(
            id: "granted",
            rowNumber: 2,
            organization: "Funder",
            grantName: "Granted grant",
            appliedOn: "2026-02-10",
            appliedAmount: "1500",
            appliedAmountValue: 1500,
            grantedOn: "2026-03-10",
            grantedAmount: "1500",
            grantedAmountValue: 1500,
            coApplicants: [currentUser]
        )
        let declined = GrantApplication(
            id: "declined",
            rowNumber: 3,
            organization: "Funder",
            grantName: "Declined grant",
            appliedOn: "2026-03-10",
            deniedOn: "2026-04-10",
            coApplicants: [currentUser]
        )
        let collaboratorWaiting = GrantApplication(
            id: "collaborator-waiting",
            rowNumber: 4,
            organization: "Funder",
            grantName: "Collaborator waiting grant",
            appliedOn: "2026-04-10",
            coApplicants: ["Collaborator", currentUser]
        )
        let toApply = GrantApplication(
            id: "to-apply",
            rowNumber: 5,
            organization: "Funder",
            grantName: "Future grant",
            closesOn: "2026-05-10",
            coApplicants: [currentUser]
        )
        let withdrawn = GrantApplication(
            id: "withdrawn",
            rowNumber: 6,
            organization: "Funder",
            grantName: "Withdrawn grant",
            appliedOn: "2026-06-10",
            withdrawnOn: "2026-07-10",
            coApplicants: [currentUser]
        )
        let store = GrantDataStore(
            applications: [waiting, granted, declined, collaboratorWaiting, toApply, withdrawn],
            metadata: metadata,
            publicationAuthors: [currentUserAuthor]
        )

        let document = store.annualReportPreviewDocument(
            year: 2026,
            exportLanguage: .swedish,
            layout: ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false)
        )
        let grants = try XCTUnwrap(document.sections.first { $0.title == "Anslag" })
        let mainGrantDetails = try XCTUnwrap(document.sections.first { $0.title == "Detaljerade poster - anslag, huvudsökande" })
        let coApplicantGrantDetails = try XCTUnwrap(document.sections.first { $0.title == "Detaljerade poster - anslag, medsökande" })

        XCTAssertEqual(Array(document.sections.prefix(5).map(\.title)), [
            "Sammanfattning",
            "Anslag",
            "Publikationer",
            "Undervisning",
            "Spridning och uppdrag",
        ])
        XCTAssertEqual(mainGrantDetails.layoutKind, "pageBreakBefore")
        XCTAssertEqual(grants.rows.first { $0.first == "Ansökningar" }, ["Ansökningar", "3", "1"])
        XCTAssertEqual(grants.rows.first { $0.first == "Beviljade" }, ["Beviljade", "1", "0"])
        XCTAssertEqual(grants.rows.first { $0.first == "Väntar beslut" }, ["Väntar beslut", "1", "1"])
        XCTAssertEqual(grants.rows.first { $0.first == "Avslagna" }, ["Avslagna", "1", "0"])
        XCTAssertEqual(mainGrantDetails.headers, ["Status", "Datum", "Finansiär", "Anslag", "Belopp i SEK"])
        XCTAssertEqual(mainGrantDetails.rows.count, 3)
        XCTAssertEqual(coApplicantGrantDetails.rows.count, 1)
        XCTAssertTrue(mainGrantDetails.rows.contains { $0.contains("Waiting grant") })
        XCTAssertTrue(coApplicantGrantDetails.rows.contains { $0.contains("Collaborator waiting grant") })
        XCTAssertFalse(mainGrantDetails.rows.contains { $0.contains("Future grant") })
        XCTAssertEqual(mainGrantDetails.rows.first { $0.contains("Granted grant") }?[1], "10 mars")
        let grantedAmount = try XCTUnwrap(mainGrantDetails.rows.first { $0.contains("Granted grant") }?.last)
        XCTAssertFalse(grantedAmount.contains("SEK"))
        XCTAssertFalse(grantedAmount.contains("≈"))
        XCTAssertFalse(grantedAmount.contains("="))
    }

    @MainActor
    func testAnnualReportDetailSectionsUseCurrentYearAndSplitAssignments() throws {
        let currentUser = "Pontus af Lindholm"
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "annual-report-author"
        let currentPublication = PublicationRecord(
            id: "publication-current",
            title: "Z published publication",
            journal: "Journal",
            status: PublicationStatus.published.rawValue,
            year: "2026",
            publicationType: "Original article",
            isPeerReviewed: true,
            authorNames: [currentUser]
        )
        let submittedPublication = PublicationRecord(
            id: "publication-submitted",
            title: "A submitted manuscript",
            journal: "Journal",
            status: PublicationStatus.submitted.rawValue,
            statusDate: "2026-05-01",
            publicationType: "Original article",
            isPeerReviewed: true,
            authorNames: [currentUser]
        )
        let olderCitationOnlyPublication = PublicationRecord(
            id: "publication-older",
            title: "Older cited publication",
            journal: "Journal",
            status: PublicationStatus.published.rawValue,
            year: "2025",
            publicationType: "Original article",
            isPeerReviewed: true,
            authorNames: [currentUser],
            citationYears: [PublicationCitationYear(year: "2026", count: "10")]
        )
        let teaching = TeachingAssignment(
            id: "teaching",
            periods: [
                TeachingAssignmentPeriod(from: "2025-01-01", to: "2026-06-30", hoursPerTerm: "10")
            ],
            activityName: "Long teaching period"
        )
        let journalReview = CVReviewEntry(
            id: "journal-review",
            category: .journalReview,
            date: "2026-02-01",
            journalName: "Review journal",
            subjectTitle: "Journal review title"
        )
        let otherReview = CVReviewEntry(
            id: "other-review",
            category: .grantProposalReview,
            date: "2026-03-01",
            organizationName: "Grant council"
        )
        let conferenceContribution = CVConferenceContribution(
            id: "conference-contribution",
            from: "2026-05-05",
            to: "2026-05-10",
            title: "Conference abstract",
            name: "Annual meeting"
        )
        let mediaAppearance = CVMediaAppearance(
            id: "media-appearance",
            authorID: "annual-report-author",
            date: "2025-12-20",
            publicationDate: "2026-04-15",
            title: "Published media interview"
        )
        let store = GrantDataStore(
            metadata: metadata,
            teachingAssignments: [teaching],
            cvConferenceContributions: [conferenceContribution],
            cvMediaAppearances: [mediaAppearance],
            cvReviewEntries: [journalReview, otherReview],
            publicationAuthors: [PublicationAuthor(id: "annual-report-author", name: currentUser)],
            publicationRecords: [submittedPublication, currentPublication, olderCitationOnlyPublication]
        )
        store.savePublicationAuthor(
            PublicationAuthor(id: "annual-report-author", name: currentUser),
            previousName: currentUser
        )
        for publication in [submittedPublication, currentPublication, olderCitationOnlyPublication] {
            store.savePublication(publication, silently: true)
        }

        let document = store.annualReportPreviewDocument(
            year: 2026,
            exportLanguage: .swedish,
            layout: ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false)
        )
        let publicationDetails = try XCTUnwrap(document.sections.first { $0.title == "Detaljerade poster - publikationer" })
        let teachingDetails = try XCTUnwrap(document.sections.first { $0.title == "Detaljerade poster - undervisning" })
        let journalReviewDetails = try XCTUnwrap(document.sections.first { $0.title == "Detaljerade poster - tidskriftsreviews" })
        let otherAssignmentDetails = try XCTUnwrap(document.sections.first { $0.title == "Detaljerade poster - övriga uppdrag" })

        XCTAssertEqual(publicationDetails.headers, ["Status", "Typ", "Titel", "Tidskrift", "Citeringar", "JIF"])
        XCTAssertTrue(publicationDetails.rows.contains { $0.contains("Z published publication") })
        XCTAssertTrue(publicationDetails.rows.contains { $0.contains("A submitted manuscript") })
        XCTAssertEqual(publicationDetails.rows.map { $0[2] }.prefix(2), ["Z published publication", "A submitted manuscript"])
        XCTAssertFalse(publicationDetails.rows.contains { $0.contains("Older cited publication") })
        XCTAssertEqual(teachingDetails.rows.first { $0.contains("Long teaching period") }?[1], "1 jan-30 juni")
        XCTAssertEqual(journalReviewDetails.headers, ["Datum", "Titel", "Sammanhang"])
        XCTAssertTrue(journalReviewDetails.rows.contains { $0.contains("Journal review title") })
        XCTAssertEqual(journalReviewDetails.rows.first { $0.contains("Journal review title") }?[0], "1 feb")
        XCTAssertFalse(journalReviewDetails.rows.flatMap { $0 }.contains("Tidskriftsreview"))
        XCTAssertFalse(journalReviewDetails.rows.contains { $0.contains("Grant council") })
        XCTAssertEqual(otherAssignmentDetails.headers, ["Typ", "Datum", "Titel", "Sammanhang"])
        XCTAssertTrue(otherAssignmentDetails.rows.contains { $0.contains("Grant council") })
        XCTAssertEqual(otherAssignmentDetails.rows.first { $0.contains("Grant council") }?[1], "1 mars")
        XCTAssertEqual(otherAssignmentDetails.rows.first { $0.contains("Conference abstract") }?[1], "5-10 maj")
        XCTAssertEqual(otherAssignmentDetails.rows.first { $0.contains("Published media interview") }?[1], "15 apr")
        XCTAssertFalse(otherAssignmentDetails.rows.contains { $0.contains("Journal review title") })
    }

    func testECBHistoricalRatesParseAndConvertToSEK() throws {
        let xml = """
        <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
          <Cube>
            <Cube time="2026-03-10">
              <Cube currency="USD" rate="1.1000"/>
              <Cube currency="SEK" rate="11.0000"/>
            </Cube>
            <Cube time="2026-03-09">
              <Cube currency="USD" rate="1.0000"/>
              <Cube currency="SEK" rate="10.0000"/>
            </Cube>
          </Cube>
        </gesmes:Envelope>
        """

        let cache = try CurrencyExchangeRateCache.parsedECBHistoricalXML(
            Data(xml.utf8),
            firstApplicationDate: "2026-03-09",
            fetchedAt: DateParsers.isoDay.date(from: "2026-03-11")!
        )

        XCTAssertEqual(cache.days.map(\.date), ["2026-03-10", "2026-03-09"])
        XCTAssertEqual(try XCTUnwrap(cache.convertingToSEK(100, currency: "USD", onOrBefore: "2026-03-10")), 1000, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(cache.convertingToSEK(100, currency: "USD", onOrBefore: "2026-03-11")), 1000, accuracy: 0.01)
        let quote = try XCTUnwrap(cache.conversionQuoteToSEK(for: "USD", onOrBefore: "2026-03-11"))
        XCTAssertEqual(quote.rateDate, "2026-03-10")
        XCTAssertEqual(quote.requestedDate, "2026-03-11")
        XCTAssertEqual(quote.factorToSEK, 10, accuracy: 0.01)
    }

    @MainActor
    func testAnnualReportGrantAmountsUseDecisionDateExchangeRate() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-pontus"
        let currentUser = PublicationAuthor(id: "author-pontus", name: "Pontus af Lindholm")
        let xml = """
        <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
          <Cube>
            <Cube time="2026-03-10">
              <Cube currency="SEK" rate="11.0000"/>
            </Cube>
          </Cube>
        </gesmes:Envelope>
        """
        let cache = try CurrencyExchangeRateCache.parsedECBHistoricalXML(
            Data(xml.utf8),
            firstApplicationDate: "2026-01-01",
            fetchedAt: DateParsers.isoDay.date(from: "2026-03-11")!
        )
        let application = GrantApplication(
            id: "eur-grant",
            rowNumber: 1,
            organization: "Funder",
            grantName: "EUR grant",
            currency: "EUR",
            appliedOn: "2026-01-10",
            appliedAmount: "100000",
            appliedAmountValue: 100_000,
            grantedOn: "2026-03-10",
            grantedAmount: "100000",
            grantedAmountValue: 100_000,
            coApplicants: ["Pontus af Lindholm"]
        )
        let store = GrantDataStore(
            applications: [application],
            metadata: metadata,
            publicationAuthors: [currentUser]
        )
        store.currencyExchangeRateCache = cache

        let document: CVExportDocument = store.annualReportPreviewDocument(
            year: 2026,
            exportLanguage: AppLanguage.swedish,
            layout: ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false)
        )
        let grants = try XCTUnwrap(document.sections.first { $0.title == "Anslag" })

        XCTAssertEqual(grants.rows.first { $0.first == "Beviljat belopp" }?[1], "1,1 mkr")
    }

    func testCVDocumentRenderingIncludesSectionRows() throws {
        let document = CVExportDocument(
            style: CVDocumentExportStyle.own.rawValue,
            exportLanguage: AppLanguage.swedish.rawValue,
            title: "ÅRSRAPPORT 2026",
            subtitle: "CV-profil",
            summaryLines: [],
            sections: [
                CVExportSection(
                    title: "Anslag",
                    headers: ["Mått", "Huvudsökande", "Medsökande"],
                    rows: [
                        ["Ansökningar", "3", "1"],
                        ["Väntar beslut", "1", "1"],
                    ]
                )
            ]
        )
        let outputURL = isolatedStorageDirectory.appendingPathComponent("annual-report-table.docx")

        try GrantDataStore.renderCVDocument(document, to: outputURL)

        let text = try docxPlainText(in: outputURL)
        XCTAssertTrue(text.contains("Mått"))
        XCTAssertTrue(text.contains("Ansökningar"))
        XCTAssertTrue(text.contains("Väntar beslut"))
    }

    @MainActor
    func testPublicationPDFResolutionFallsBackToActiveStorageDirectory() throws {
        try GrantDataStore.ensurePublicationPDFsDirectory()
        let expectedURL = GrantDataStore.publicationPDFsDirectory.appendingPathComponent("legacy-publication.pdf")
        try Data("pdf".utf8).write(to: expectedURL)

        let resolved = GrantDataStore.resolvePublicationPDFURL(
            publicationID: "publication-legacy",
            finalPDFPath: "/Users/example/Library/Application Support/GrantDesk/Publication PDFs/legacy-publication.pdf",
            finalPDFFilename: nil
        )

        XCTAssertEqual(resolved?.path, expectedURL.path)
    }

    @MainActor
    func testPublicationPDFResolutionPrefersManagedAttachmentForPublicationID() throws {
        try GrantDataStore.ensurePublicationPDFsDirectory()
        let managedURL = GrantDataStore.managedPublicationPDFURL(forPublicationID: "publication-1")
        try Data("managed".utf8).write(to: managedURL)

        let legacyURL = isolatedStorageDirectory.appendingPathComponent("legacy.pdf")
        try Data("legacy".utf8).write(to: legacyURL)

        let resolved = GrantDataStore.resolvePublicationPDFURL(
            publicationID: "publication-1",
            finalPDFPath: legacyURL.path,
            finalPDFFilename: "legacy.pdf"
        )

        XCTAssertEqual(resolved?.path, managedURL.path)
    }

    @MainActor
    func testSavingPublicationCanonicalizesPDFToManagedStorage() throws {
        let publication = PublicationRecord(id: "publication-1", title: "Title")
        let store = GrantDataStore(publicationRecords: [publication])

        let sourceURL = isolatedStorageDirectory.appendingPathComponent("source.pdf")
        let sourceData = Data("managed-pdf".utf8)
        try sourceData.write(to: sourceURL)

        var updated = publication
        updated.finalPDFFilename = "source.pdf"
        updated.finalPDFPath = sourceURL.path
        store.savePublication(updated, silently: true)

        let stored = try XCTUnwrap(store.publications.first)
        let managedURL = GrantDataStore.managedPublicationPDFURL(forPublicationID: publication.id)
        XCTAssertEqual(stored.finalPDFFilename, "source.pdf")
        XCTAssertEqual(stored.finalPDFPath, GrantDataStore.portableAttachmentPath(for: managedURL))
        XCTAssertEqual(try Data(contentsOf: managedURL), sourceData)
    }

    @MainActor
    func testRemovingPublicationAttachmentDeletesManagedPDF() throws {
        try GrantDataStore.ensurePublicationPDFsDirectory()
        let managedURL = GrantDataStore.managedPublicationPDFURL(forPublicationID: "publication-1")
        try Data("managed".utf8).write(to: managedURL)

        let publication = PublicationRecord(
            id: "publication-1",
            title: "Title",
            finalPDFFilename: "source.pdf",
            finalPDFPath: managedURL.path
        )
        let store = GrantDataStore(publicationRecords: [publication])

        var updated = publication
        updated.finalPDFFilename = nil
        updated.finalPDFPath = nil
        store.savePublication(updated, silently: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertNil(store.publications.first?.finalPDFFilename)
        XCTAssertNil(store.publications.first?.finalPDFPath)
    }

    func testPublicationNormalizePreservesOrderForUndatedPlannedStatusEntries() {
        var record = PublicationRecord(
            id: "publication-1",
            title: "Title",
            statusTimeline: [
                PublicationStatusEntry(status: PublicationStatus.inPreparation.rawValue, journal: "First planned", date: nil),
                PublicationStatusEntry(status: PublicationStatus.inPreparation.rawValue, journal: "Second planned", date: nil),
                PublicationStatusEntry(status: PublicationStatus.submitted.rawValue, journal: "Current journal", date: "2026-04-01")
            ]
        )

        record.normalize()

        XCTAssertEqual(record.statusTimeline.map(\.journal), ["Current journal", "First planned", "Second planned"])
    }

    func testPublicationEditingLockDefaultsFalseAndRoundTrips() throws {
        let legacyJSON = """
        {
          "id": "publication-1",
          "number": "",
          "title": "Legacy publication",
          "journal": "",
          "status": "In preparation",
          "doi": "",
          "epubDate": "",
          "pmid": "",
          "volume": "",
          "issue": "",
          "pageRange": "",
          "articleNumber": "",
          "year": "",
          "position": "",
          "independence": "",
          "geography": "",
          "phdStage": "",
          "publicationType": "",
          "isPeerReviewed": true,
          "citations": "",
          "norwegianCurrent": "",
          "norwegian2025": "",
          "sjrCurrent": "",
          "sjr2024": "",
          "jifCurrent": "",
          "jifQuartileCurrent": "",
          "jif2024": "",
          "category": "",
          "authorNames": [],
          "sharedFirstAuthorship": false,
          "sharedLastAuthorship": false,
          "citationYears": [],
          "statusTimeline": [],
          "previousAttempts": [],
          "publicationTasks": [],
          "creditRoleAssignments": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let legacyRecord = try decoder.decode(PublicationRecord.self, from: legacyJSON)
        XCTAssertFalse(legacyRecord.isEditingLocked)

        var lockedRecord = legacyRecord
        lockedRecord.isEditingLocked = true
        let encoded = try JSONEncoder().encode(lockedRecord)
        let roundTripped = try decoder.decode(PublicationRecord.self, from: encoded)
        XCTAssertTrue(roundTripped.isEditingLocked)
    }

    func testAdditionalEditorLocksDefaultFalseAndRoundTrip() throws {
        let decoder = JSONDecoder()

        XCTAssertFalse(try decoder.decode(GrantApplication.self, from: Data("{}".utf8)).isEditingLocked)
        XCTAssertFalse(try decoder.decode(ProjectRecord.self, from: Data("{}".utf8)).isEditingLocked)
        XCTAssertFalse(try decoder.decode(DoctoralCandidateRecord.self, from: Data("{}".utf8)).isEditingLocked)
        XCTAssertEqual(try decoder.decode(ProjectRecord.self, from: Data("{}".utf8)).fullNameSv, "")
        XCTAssertEqual(try decoder.decode(ProjectRecord.self, from: Data("{}".utf8)).fullNameEn, "")

        let lockedApplication = GrantApplication(
            id: "application-1",
            rowNumber: 1,
            organization: "Funder",
            grantName: "Grant",
            isEditingLocked: true
        )
        let lockedProject = ProjectRecord(
            id: "project-1",
            nameSv: "Projekt",
            nameEn: "Project",
            isEditingLocked: true
        )
        let lockedCandidate = DoctoralCandidateRecord(
            id: "doctoral-1",
            candidateName: "Candidate",
            isEditingLocked: true
        )

        XCTAssertTrue(try decoder.decode(GrantApplication.self, from: JSONEncoder().encode(lockedApplication)).isEditingLocked)
        XCTAssertTrue(try decoder.decode(ProjectRecord.self, from: JSONEncoder().encode(lockedProject)).isEditingLocked)
        XCTAssertTrue(try decoder.decode(DoctoralCandidateRecord.self, from: JSONEncoder().encode(lockedCandidate)).isEditingLocked)
    }

    func testPublicationReviewRegistrationDefaultsAndURLs() throws {
        let legacyPublication = try JSONDecoder().decode(PublicationRecord.self, from: Data("{}".utf8))
        XCTAssertEqual(legacyPublication.reviewRegistrationRegistry, "")
        XCTAssertEqual(legacyPublication.reviewRegistrationID, "")
        XCTAssertEqual(legacyPublication.reviewRegistrationDate, "")

        XCTAssertEqual(
            PublicationRecord(publicationType: "Systematic review", reviewRegistrationRegistry: "PROSPERO", reviewRegistrationID: "CRD42025123456").reviewRegistrationURL?.absoluteString,
            "https://www.crd.york.ac.uk/prospero/display_record.php?RecordID=42025123456"
        )
        XCTAssertEqual(
            PublicationRecord(publicationType: "Systematic review", reviewRegistrationRegistry: "INPLASY", reviewRegistrationID: "INPLASY202540123").reviewRegistrationURL?.absoluteString,
            "https://inplasy.com/inplasy-2025-40123/"
        )
        XCTAssertEqual(
            PublicationRecord(publicationType: "Systematic review", reviewRegistrationRegistry: "OSF Registries", reviewRegistrationID: "abcde").reviewRegistrationURL?.absoluteString,
            "https://osf.io/abcde"
        )
        XCTAssertEqual(
            PublicationRecord(publicationType: "Systematic review", reviewRegistrationRegistry: "OSF Registries", reviewRegistrationID: "https://osf.io/abcde").reviewRegistrationURL?.absoluteString,
            "https://osf.io/abcde"
        )
        XCTAssertEqual(
            PublicationRecord(publicationType: "Systematic review", reviewRegistrationRegistry: "Research Registry", reviewRegistrationID: "researchregistry1234").reviewRegistrationURL?.absoluteString,
            "https://www.researchregistry.com/browse-the-registry#home/registrationdetails/researchregistry1234"
        )
        XCTAssertEqual(
            PublicationRecord(publicationType: "Systematic review", reviewRegistrationRegistry: "protocols.io", reviewRegistrationID: "10.17504/protocols.io.example").reviewRegistrationURL?.absoluteString,
            "https://doi.org/10.17504/protocols.io.example"
        )
        XCTAssertEqual(
            PublicationRecord(publicationType: "Systematic review", reviewRegistrationRegistry: "protocols.io", reviewRegistrationID: "abc123").reviewRegistrationURL?.absoluteString,
            "https://www.protocols.io/view/abc123"
        )
    }

    func testDoctoralCandidateLegacyTimelineDatesMigrateWithoutDroppingValues() throws {
        let decoder = JSONDecoder()
        let plannedOnlyJSON = Data("""
        {
          "id": "doctoral-planned",
          "halftimeDate": "2027-03-01",
          "halftimeDatePreliminary": true,
          "plannedDisputationDate": "2029-01-15",
          "plannedDisputationDatePreliminary": true
        }
        """.utf8)

        let plannedOnly = try decoder.decode(DoctoralCandidateRecord.self, from: plannedOnlyJSON)
        XCTAssertEqual(plannedOnly.estimatedHalftimeDate, "2027-03-01")
        XCTAssertTrue(plannedOnly.estimatedHalftimeDatePreliminary)
        XCTAssertEqual(plannedOnly.halftimeDate, "")
        XCTAssertEqual(plannedOnly.plannedDisputationDate, "2029-01-15")
        XCTAssertEqual(plannedOnly.disputationDate, "")

        let completedJSON = Data("""
        {
          "id": "doctoral-completed",
          "halftimeDate": "2027-03-01",
          "halftimeOutcomeRaw": "completed",
          "plannedDisputationDate": "2029-01-15",
          "plannedDisputationOutcomeRaw": "completed"
        }
        """.utf8)

        let completed = try decoder.decode(DoctoralCandidateRecord.self, from: completedJSON)
        XCTAssertEqual(completed.halftimeDate, "2027-03-01")
        XCTAssertEqual(completed.estimatedHalftimeDate, "")
        XCTAssertEqual(completed.disputationDate, "2029-01-15")
        XCTAssertEqual(completed.plannedDisputationDate, "")
    }

    func testDoctoralCandidateLegacyDataDefaultsNewDocumentCourseAndEISPFields() throws {
        let data = Data(#"{"id":"doctoral-legacy","candidateName":"Legacy Candidate"}"#.utf8)
        let candidate = try JSONDecoder().decode(DoctoralCandidateRecord.self, from: data)

        XCTAssertEqual(candidate.id, "doctoral-legacy")
        XCTAssertEqual(candidate.candidateName, "Legacy Candidate")
        XCTAssertEqual(candidate.eISPLink, "")
        XCTAssertTrue(candidate.documents.isEmpty)
        XCTAssertTrue(candidate.courses.isEmpty)
    }

    func testDoctoralCandidateDocumentsCoursesAndEISPRoundTrip() throws {
        var candidate = DoctoralCandidateRecord(
            id: "doctoral-new-fields",
            candidateName: "Candidate",
            eISPLink: "https://eisp.example.test/candidate",
            documents: [
                DoctoralCandidateDocument(
                    id: "document-1",
                    title: "Individual study plan",
                    date: "2026-02-03",
                    filename: "study-plan.pdf",
                    path: "/managed/study-plan.pdf"
                )
            ],
            courses: [
                DoctoralCandidateCourse(
                    id: "course-1",
                    year: "2025",
                    title: "Research ethics",
                    credits: "3,5",
                    completedOn: "2025-11-14"
                )
            ]
        )
        candidate.normalize()

        let decoded = try JSONDecoder().decode(
            DoctoralCandidateRecord.self,
            from: JSONEncoder().encode(candidate)
        )

        XCTAssertEqual(decoded.eISPLink, "https://eisp.example.test/candidate")
        XCTAssertEqual(decoded.documents.first?.title, "Individual study plan")
        XCTAssertEqual(decoded.documents.first?.date, "2026-02-03")
        XCTAssertEqual(decoded.documents.first?.filename, "study-plan.pdf")
        XCTAssertEqual(decoded.courses.first?.year, "2025")
        XCTAssertEqual(decoded.courses.first?.title, "Research ethics")
        XCTAssertEqual(decoded.courses.first?.credits, "3,5")
        XCTAssertEqual(decoded.courses.first?.completedOn, "2025-11-14")
    }

    func testDoctoralCandidateLegacyCourseDefaultsCompletionDateToNil() throws {
        let data = Data(#"{"id":"legacy-course","year":"2024","title":"Methods","credits":"3"}"#.utf8)
        let course = try JSONDecoder().decode(DoctoralCandidateCourse.self, from: data)

        XCTAssertEqual(course.id, "legacy-course")
        XCTAssertEqual(course.title, "Methods")
        XCTAssertNil(course.completedOn)
    }

    func testDoctoralCandidateCoursesSortChronologicallyWithMissingYearsLast() {
        var candidate = DoctoralCandidateRecord(
            id: "doctoral-sorted-courses",
            candidateName: "Candidate",
            courses: [
                DoctoralCandidateCourse(id: "course-2026-z", year: "2026", title: "Zoology", credits: "2"),
                DoctoralCandidateCourse(id: "course-missing-year", year: "", title: "Introduction", credits: "1"),
                DoctoralCandidateCourse(id: "course-2024", year: "2024", title: "Methods", credits: "3"),
                DoctoralCandidateCourse(id: "course-2026-a", year: "2026", title: "Advanced methods", credits: "4")
            ]
        )

        candidate.normalize()

        XCTAssertEqual(
            candidate.courses.map(\.id),
            ["course-2024", "course-2026-a", "course-2026-z", "course-missing-year"]
        )
    }

    func testDoctoralCandidateAutosaveRestoresNewProvisionalCourseRow() {
        let savedCourse = DoctoralCandidateCourse(
            id: "saved-course",
            year: "2025",
            title: "Research ethics",
            credits: "3"
        )
        let provisionalCourse = DoctoralCandidateCourse(id: "new-course")
        let unrelatedEmptyCourse = DoctoralCandidateCourse(id: "unrelated-empty-course")

        let restored = doctoralCandidateCoursesRestoringProvisionalRows(
            normalizedCourses: [savedCourse],
            draftCourses: [savedCourse, provisionalCourse, unrelatedEmptyCourse],
            provisionalCourseIDs: [provisionalCourse.id]
        )

        XCTAssertEqual(restored.map(\.id), ["saved-course", "new-course"])
        XCTAssertTrue(restored.last?.isEmpty == true)
    }

    @MainActor
    func testDoctoralCandidatePDFUsesManagedAttachmentStorage() throws {
        let documentID = "doctoral-document-\(UUID().uuidString)"
        let expectedData = Data("%PDF-1.4 doctoral candidate".utf8)
        let url = try GrantDataStore.persistManagedDoctoralCandidatePDF(
            data: expectedData,
            forDocumentID: documentID
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let document = DoctoralCandidateDocument(
            id: documentID,
            title: "Study plan",
            filename: "source.pdf",
            path: "/missing/source.pdf"
        )

        XCTAssertEqual(
            GrantDataStore.resolveDoctoralCandidatePDFURL(document: document),
            url
        )
        XCTAssertEqual(try Data(contentsOf: url), expectedData)
    }

    func testDerivedSubmissionRowsKeepPlannedRowsAfterDatedRowsInStoredOrder() {
        var record = PublicationRecord(
            id: "publication-1",
            title: "Title",
            statusTimeline: [
                PublicationStatusEntry(status: PublicationStatus.inPreparation.rawValue, journal: "Plan A", date: nil),
                PublicationStatusEntry(status: PublicationStatus.inPreparation.rawValue, journal: "Plan B", date: nil),
                PublicationStatusEntry(status: PublicationStatus.submitted.rawValue, journal: "Active journal", date: "2026-03-18")
            ]
        )
        record.normalize()

        let rows = derivedSubmissionRows(for: record)

        XCTAssertEqual(rows.map(\.journal), ["Active journal", "Plan A", "Plan B"])
        XCTAssertEqual(rows.first?.submittedDate, "2026-03-18")
        XCTAssertTrue(rows.dropFirst().allSatisfy { $0.supportsManualOrdering })
    }

    private func exportedItem(containing text: String, in document: CVExportDocument) -> String? {
        document.sections
            .flatMap { section in
                section.items + section.subsections.flatMap(\.items)
            }
            .first { $0.contains(text) }
    }

    private func exportedSection(titled title: String, in document: CVExportDocument) -> CVExportSection? {
        document.sections.first { $0.title == title }
    }

    private func exportedSubsection(titled title: String, in document: CVExportDocument) -> CVExportSubsection? {
        document.sections
            .flatMap(\.subsections)
            .first { $0.title == title }
    }

    private func officeArchiveEntry(named entryName: String, in documentURL: URL) throws -> String {
        let inspectionScript = isolatedStorageDirectory.appendingPathComponent("inspect-office-entry.py")
        try """
        import sys
        import zipfile

        with zipfile.ZipFile(sys.argv[1]) as archive:
            name = sys.argv[2]
            if name in archive.namelist():
                sys.stdout.write(archive.read(name).decode("utf-8"))
        """.write(to: inspectionScript, atomically: true, encoding: .utf8)

        let result = try ExternalProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [inspectionScript.path, documentURL.path, entryName],
            timeout: 10
        )
        return result.stdout
    }

    private func docxEntry(named entryName: String, in docxURL: URL) throws -> String {
        try officeArchiveEntry(named: entryName, in: docxURL)
    }

    private func xlsxEntry(named entryName: String, in xlsxURL: URL) throws -> String {
        try officeArchiveEntry(named: entryName, in: xlsxURL)
    }

    private func docxPlainText(in docxURL: URL) throws -> String {
        let inspectionScript = isolatedStorageDirectory.appendingPathComponent("inspect-docx-text.py")
        try """
        import sys
        import zipfile
        import xml.etree.ElementTree as ET

        ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
        with zipfile.ZipFile(sys.argv[1]) as archive:
            root = ET.fromstring(archive.read("word/document.xml"))

        paragraphs = []
        for paragraph in root.findall(".//w:p", ns):
            text = "".join(node.text or "" for node in paragraph.findall(".//w:t", ns))
            if text:
                paragraphs.append(text)
        sys.stdout.write("\\n".join(paragraphs))
        """.write(to: inspectionScript, atomically: true, encoding: .utf8)

        let result = try ExternalProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [inspectionScript.path, docxURL.path],
            timeout: 10
        )
        return result.stdout
    }

    func testPublicationNormalizePrefersSubmittedOverRejectedWhenDatesMatch() {
        var record = PublicationRecord(
            id: "publication-1",
            title: "Title",
            statusTimeline: [
                PublicationStatusEntry(status: PublicationStatus.rejected.rawValue, journal: "Journal A", date: "2026-04-17"),
                PublicationStatusEntry(status: PublicationStatus.submitted.rawValue, journal: "Journal B", date: "2026-04-17")
            ]
        )

        record.normalize()

        XCTAssertEqual(record.statusLabel, PublicationStatus.submitted.rawValue)
        XCTAssertEqual(record.journal, "Journal B")
        XCTAssertEqual(record.statusDate, "2026-04-17")
    }

    func testPublicationNormalizePrefersRejectedOverSubmittedWhenDateAndJournalMatch() {
        var record = PublicationRecord(
            id: "publication-1",
            title: "Title",
            statusTimeline: [
                PublicationStatusEntry(status: PublicationStatus.submitted.rawValue, journal: "Journal A", date: "2026-04-17"),
                PublicationStatusEntry(status: PublicationStatus.rejected.rawValue, journal: "Journal A", date: "2026-04-17")
            ]
        )

        record.normalize()

        XCTAssertEqual(record.statusLabel, PublicationStatus.rejected.rawValue)
        XCTAssertEqual(record.journal, "Journal A")
        XCTAssertEqual(record.statusDate, "2026-04-17")
    }

    func testSubmissionRowLatestStatusPrefersRejectedOverSubmittedWhenDatesMatch() {
        let row = PublicationSubmissionEditorRow(
            journal: "Journal B",
            submittedDate: "2026-04-17",
            rejectedDate: "2026-04-17"
        )

        XCTAssertEqual(row.latestStatus, .rejected)
        XCTAssertEqual(row.latestDateString, "2026-04-17")
    }

    @MainActor
    func testPublicationDataQualityAllowsSameDayResubmissionToDifferentJournal() {
        let publication = PublicationRecord(
            id: "publication-1",
            projectName: "Project",
            title: "Title",
            journal: "Journal B",
            status: PublicationStatus.submitted.rawValue,
            statusDate: "2026-04-17",
            doi: "10.1234/example",
            pmid: "12345678",
            authorNames: ["Author Example"],
            statusTimeline: [
                PublicationStatusEntry(status: PublicationStatus.rejected.rawValue, journal: "Journal A", date: "2026-04-17"),
                PublicationStatusEntry(status: PublicationStatus.submitted.rawValue, journal: "Journal B", date: "2026-04-17")
            ],
            currentSubmissionDate: "2026-04-17"
        )
        let store = GrantDataStore(publicationRecords: [publication])

        XCTAssertFalse(store.integrityIssues().contains(where: {
            $0.recordID == publication.id
                && $0.subtitle == "Current status differs from publication history"
        }))
        XCTAssertFalse(store.missingFieldIssues().contains(where: {
            $0.recordID == publication.id
                && $0.missingFields.contains("Publication history out of order")
        }))
    }

    @MainActor
    func testNormalizedTimeInputAcceptsThreeDigitTimes() {
        XCTAssertEqual(GrantDataStore.normalizedTimeInput("930"), "09:30")
        XCTAssertEqual(GrantDataStore.normalizedTimeInput("7:45"), "07:45")
    }

    func testNormalizedCalendarTimeInputAcceptsFourDigitTimes() {
        XCTAssertEqual(normalizedCalendarTimeInput("1500"), "15:00")
        XCTAssertEqual(normalizedCalendarTimeInput("2000"), "20:00")
    }

    func testExternalProcessRunnerCapturesStdout() throws {
        let scriptURL = isolatedStorageDirectory.appendingPathComponent("echo.sh")
        try "#!/bin/sh\necho ready\n".write(to: scriptURL, atomically: true, encoding: .utf8)

        let result = try ExternalProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [scriptURL.path],
            timeout: 1
        )

        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ready")
        XCTAssertEqual(result.terminationStatus, 0)
    }

    @MainActor
    func testGroupMailIncludesEveryAffiliationAddressAndDeduplicatesResearchers() {
        let first = PublicationAuthor(
            id: "author-1",
            name: "Anna Andersson",
            affiliations: [
                PublicationAffiliation(email: "anna@university.example", isPrimary: true),
                PublicationAffiliation(email: "Anna@University.example; anna.private@example.org"),
            ]
        )
        let second = PublicationAuthor(
            id: "author-2",
            name: "Bo Berg",
            nameVariants: ["B. Berg"],
            affiliations: [PublicationAffiliation(email: "Bo Berg <bo@example.net>")]
        )
        let currentUser = PublicationAuthor(
            id: "author-current",
            name: "Current User",
            nameVariants: ["C. User"],
            affiliations: [PublicationAffiliation(email: "me@example.com")]
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = currentUser.id
        let store = GrantDataStore(metadata: metadata, publicationAuthors: [first, second, currentUser])

        let addresses = store.groupMailAddresses(
            authorIDs: [first.id],
            presentedNames: [first.name, "B. Berg", "C. User", "Unknown Person"]
        )

        XCTAssertEqual(
            addresses,
            ["anna@university.example", "anna.private@example.org", "bo@example.net"]
        )
        XCTAssertEqual(
            groupMailURL(for: addresses)?.absoluteString.removingPercentEncoding,
            "mailto:anna@university.example,anna.private@example.org,bo@example.net"
        )
    }

    @MainActor
    func testAddingSelectedJournalsToUnpublishedPublicationPreservesOrderAndSkipsDuplicates() {
        let first = PublicationJournal(name: "First Journal")
        let second = PublicationJournal(name: "Second Journal")
        let third = PublicationJournal(name: "Third Journal")
        let publication = PublicationRecord(
            title: "Draft article",
            journal: first.name,
            status: PublicationStatus.inPreparation.rawValue
        )
        let store = GrantDataStore(
            publicationJournals: [first, second, third],
            publicationRecords: [publication]
        )

        store.addPublicationJournals(
            [second.id, first.id, third.id, second.id],
            toPublicationID: publication.id
        )

        let updated = try! XCTUnwrap(store.publication(id: publication.id))
        XCTAssertEqual(
            derivedSubmissionRows(for: updated).filter { !$0.isEmpty }.map(\.journal),
            [first.name, second.name, third.name]
        )
    }

    @MainActor
    func testPublicationJournalListExportUsesMetricsOrderAndSwedishFinalConjunction() {
        let first = PublicationJournal(
            name: "First Journal",
            rankingRows: [
                JournalRankingRow(kind: .clarivateScieJIF, yearlyMetrics: [JournalYearMetric(year: 2025, value: "4.20", quartile: "Q1")]),
                JournalRankingRow(kind: .norwegianList, yearlyMetrics: [JournalYearMetric(year: 2025, value: "2", quartile: "")]),
            ]
        )
        let second = PublicationJournal(name: "Second Journal")
        let third = PublicationJournal(
            name: "Third Journal",
            rankingRows: [
                JournalRankingRow(kind: .clarivateScieJIF, yearlyMetrics: [JournalYearMetric(year: 2025, value: "1.5", quartile: "3")]),
                JournalRankingRow(kind: .norwegianList, yearlyMetrics: [JournalYearMetric(year: 2025, value: "1", quartile: "")]),
            ]
        )
        let store = GrantDataStore(publicationJournals: [first, second, third])

        XCTAssertEqual(
            store.publicationJournalListExportText(
                journalNames: [first.name, second.name, first.name, third.name],
                publicationYear: 2025,
                language: .swedish
            ),
            "First Journal (IF 4.2, Q1, norska listan 2), Second Journal (IF –, –, norska listan –) och Third Journal (IF 1.5, Q3, norska listan 1)"
        )
    }

    @MainActor
    func testClipboardPreviewProjectionPublishesTransientConfirmation() {
        let store = GrantDataStore()
        let projection = ClipboardPreviewProjection(store: store)
        XCTAssertNil(projection.payload)

        let payload = ClipboardPreviewPayload(text: "Exported journal list")
        store.clipboardPreview = payload

        XCTAssertEqual(projection.payload, payload)
    }

    func testExternalProcessRunnerCapturesLargeIndependentOutputStreams() throws {
        let scriptURL = isolatedStorageDirectory.appendingPathComponent("large-output.sh")
        try """
        #!/bin/sh
        index=0
        while [ "$index" -lt 3000 ]; do
          echo "stdout-$index-abcdefghijklmnopqrstuvwxyz"
          echo "stderr-$index-abcdefghijklmnopqrstuvwxyz" >&2
          index=$((index + 1))
        done
        """.write(to: scriptURL, atomically: true, encoding: .utf8)

        let result = try ExternalProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [scriptURL.path],
            timeout: 10
        )

        XCTAssertTrue(result.stdout.contains("stdout-2999-abcdefghijklmnopqrstuvwxyz"))
        XCTAssertTrue(result.stderr.contains("stderr-2999-abcdefghijklmnopqrstuvwxyz"))
        XCTAssertEqual(result.terminationStatus, 0)
    }

    func testPythonRuntimeResolverRejectsMissingExecutable() {
        let missing = URL(fileURLWithPath: "/definitely-missing-footprint-python")
        XCTAssertNil(PythonScriptRunner.resolvedExecutableURL(candidates: [missing]))
        XCTAssertTrue(PythonScriptRunner.RuntimeError.unavailable.localizedDescription.contains("Python 3"))
    }

    func testExternalProcessRunnerTimesOutSlowScript() throws {
        let scriptURL = isolatedStorageDirectory.appendingPathComponent("slow.sh")
        try "#!/bin/sh\nsleep 1\n".write(to: scriptURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try ExternalProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: [scriptURL.path],
                timeout: 0.1
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("timed out"))
        }
    }

    func testFilteredAutocompleteOptionsCanShowGrantProvidersWithoutQuery() {
        let options = ["Formas", "Forte", "Vetenskapsrådet"]

        let filtered = filteredAutocompleteOptions(
            options: options,
            queryText: "",
            showsSuggestionsWithoutQuery: true
        )

        XCTAssertEqual(filtered, ["Formas", "Forte", "Vetenskapsrådet"])
    }

    func testApplicationOrganizationAutocompleteOptionsIncludeExistingApplicationFunders() {
        let university = OrganizationRecord(id: "org-uni", nameSv: "Exempelköpings universitet", nameEn: "Exempelköping University", roles: [.institution])
        let funder = OrganizationRecord(id: "org-formas", nameSv: "Formas", nameEn: "Formas", roles: [.grantProvider])
        let applications = [
            GrantApplication(id: "app-1", rowNumber: 1, organization: "Vetenskapsrådet", grantName: "A"),
            GrantApplication(id: "app-2", rowNumber: 2, organization: "Formas", grantName: "B")
        ]

        let options = applicationOrganizationAutocompleteOptions(
            organizations: [university, funder],
            applications: applications,
            selectedOrganizationID: nil,
            selectedOrganizationName: nil,
            language: .swedish
        )

        XCTAssertTrue(options.contains("Formas"))
        XCTAssertTrue(options.contains("Vetenskapsrådet"))
        XCTAssertFalse(options.contains("Exempelköpings universitet"))
    }

    func testApplicationOrganizationAutocompleteOptionsFallsBackToAllOrganizations() {
        let university = OrganizationRecord(id: "org-uni", nameSv: "Exempelköpings universitet", nameEn: "Exempelköping University", roles: [.institution])
        let region = OrganizationRecord(id: "org-region", nameSv: "Region Exempelgöta", nameEn: "Region Exempelgota", roles: [.employer])

        let options = applicationOrganizationAutocompleteOptions(
            organizations: [university, region],
            applications: [],
            selectedOrganizationID: nil,
            selectedOrganizationName: nil,
            language: .swedish
        )

        XCTAssertEqual(options, ["Exempelköpings universitet", "Region Exempelgöta"])
    }

    func testCVReviewProgramAutocompleteOptionsUseExistingGrantPrograms() {
        let options = cvReviewProgramAutocompleteOptions(reviewEntries: [
            CVReviewEntry(id: "review-1", category: .grantProposalReview, programName: "CircM call"),
            CVReviewEntry(id: "review-2", category: .grantProposalReview, programName: "Wallenberg Scholars"),
            CVReviewEntry(id: "review-3", category: .doctoralExamination, programName: "Ignore me")
        ])

        XCTAssertEqual(options, ["CircM call", "Wallenberg Scholars"])
    }

    func testCVReviewPersonAutocompleteOptionsIncludeDoctoralCandidates() {
        let options = cvReviewPersonAutocompleteOptions(
            category: .doctoralExamination,
            reviewEntries: [
                CVReviewEntry(id: "review-1", category: .doctoralExamination, personName: "Anna Candidate"),
                CVReviewEntry(id: "review-2", category: .doctoralExamination, personName: "Nils Student")
            ],
            doctoralCandidates: [
                DoctoralCandidateRecord(id: "candidate-1", candidateName: "Anna Candidate"),
                DoctoralCandidateRecord(id: "candidate-2", candidateName: "Beata Student")
            ]
        )

        XCTAssertEqual(options, ["Anna Candidate", "Beata Student", "Nils Student"])
    }

    func testCVReviewPersonAutocompleteOptionsIncludeAuthorsForOtherAssignments() {
        let options = cvReviewPersonAutocompleteOptions(
            category: .otherExpertAssignment,
            reviewEntries: [
                CVReviewEntry(id: "review-1", category: .otherExpertAssignment, personName: "Lisa Person")
            ],
            publicationAuthors: [
                PublicationAuthor(id: "author-1", name: "Karl Karlsson"),
                PublicationAuthor(id: "author-2", name: "Lisa Person")
            ]
        )

        XCTAssertEqual(options, ["Karl Karlsson", "Lisa Person"])
    }

    func testJournalReviewListTitleIncludesArticleTitleWhenPresent() {
        let review = CVReviewEntry(
            id: "review-1",
            category: .journalReview,
            date: "2026-04-21",
            journalName: "Journal of Useful Findings",
            subjectTitle: "A useful article",
            reference: "JUF-2026-001"
        )

        XCTAssertEqual(review.displayTitle, "A useful article")
        XCTAssertEqual(review.listTitle, "A useful article - Journal of Useful Findings")
    }

    func testJournalReviewListTitleOmitsDateWhenArticleTitleIsMissing() {
        let review = CVReviewEntry(
            id: "review-1",
            category: .journalReview,
            date: "2026-04-21",
            journalName: "Journal of Useful Findings",
            reference: "JUF-2026-001"
        )

        XCTAssertEqual(review.displayTitle, "Journal of Useful Findings")
        XCTAssertEqual(review.listTitle, "Journal of Useful Findings")
    }

    func testTeachingAutocompleteCourseNameOptionsPreferExactProgramMatches() {
        let courses = [
            TeachingCourse(id: "leaf-1", name: "Basal kurs", contextType: .course, programSv: "Exempelprogrammet", institution: "EXU"),
            TeachingCourse(id: "leaf-2", name: "Fortsattningskurs", contextType: .course, programSv: "Exempelprogrammet 2", institution: "EXU"),
            TeachingCourse(id: "track-1", name: "Programgren", contextType: .programTrack, programSv: "Exempelprogrammet", institution: "EXU"),
            TeachingCourse(id: "leaf-3", name: "Extern kurs", contextType: .course, programSv: "Exempelprogrammet", institution: "GU")
        ]

        let options = TeachingAutocompleteIndex.courseNameOptions(
            courses: courses,
            language: .swedish,
            institution: "EXU",
            program: "Exempelprogrammet",
            scope: .leafOnly
        )

        XCTAssertEqual(options, ["Basal kurs"])
    }

    func testTeachingAutocompleteTermOptionsAllowPartialProgramMatchesWhenNeeded() {
        let courses = [
            TeachingCourse(id: "course-1", name: "Basal kurs", contextType: .course, programSv: "Exempelprogrammet", term: "VT24", institution: "EXU"),
            TeachingCourse(id: "course-2", name: "Avancerad kurs", contextType: .course, programSv: "Exempelforskning", term: "HT24", institution: "EXU")
        ]

        let options = TeachingAutocompleteIndex.termOptions(
            courses: courses,
            language: .swedish,
            institution: "EXU",
            program: "Exempel",
            scope: .leafOnly
        )

        XCTAssertEqual(options, ["HT24", "VT24"])
    }

    @MainActor
    func testDeferredAutosaveFlushPersistsLatestApplicationState() throws {
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Org",
            grantName: "Original"
        )
        let store = GrantDataStore(applications: [application])

        var firstUpdate = application
        firstUpdate.grantName = "First"
        store.autosave(application: firstUpdate)

        var secondUpdate = firstUpdate
        secondUpdate.grantName = "Second"
        store.autosave(application: secondUpdate)

        XCTAssertTrue(store.flushPendingPersistenceIfNeeded())

        let persisted = try XCTUnwrap(store.sqliteStore?.load([GrantApplication].self, named: "applications"))
        XCTAssertEqual(persisted.first?.grantName, "Second")
    }

    @MainActor
    func testSavingApplicationCanonicalizesNameRelationsFromIDs() {
        let organization = OrganizationRecord(id: "organization-uni", nameSv: "Exempelköpings universitet", nameEn: "Exempelköping University")
        var funder = organization
        funder.roles = [.fundManager]
        let project = ProjectRecord(id: "project-alpha", nameSv: "Alpha", nameEn: "Alpha")
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organizationID: "organization-uni",
            organization: "Old org text",
            grantName: "Grant",
            projectID: "project-alpha",
            projectType: "Old project text",
            applicationManagerID: "organization-uni",
            applicationManager: "Old manager text"
        )

        let store = GrantDataStore(
            applications: [application],
            organizations: [funder],
            managers: [ManagerOption(id: "organization-uni", nameSv: "Exempelköpings universitet", nameEn: "Exempelköping University", reason: nil)],
            projects: [project]
        )

        store.save(application: application)

        XCTAssertEqual(store.applications.first?.organization, "Exempelköpings universitet")
        XCTAssertEqual(store.applications.first?.projectType, "Alpha")
        XCTAssertEqual(store.applications.first?.applicationManager, "Exempelköpings universitet")
        XCTAssertEqual(store.applications.first?.coApplicants, [])
    }

    @MainActor
    func testSavingApplicationRelationEditsReplaceStaleIDsAndNames() throws {
        let oldFunder = OrganizationRecord(id: "organization-old", nameSv: "Old funder", nameEn: "Old funder", roles: [.grantProvider])
        let newFunder = OrganizationRecord(id: "organization-new", nameSv: "New funder", nameEn: "New funder", roles: [.grantProvider])
        let oldManager = OrganizationRecord(id: "manager-old", nameSv: "Old manager", nameEn: "Old manager", roles: [.fundManager])
        let newManager = OrganizationRecord(id: "manager-new", nameSv: "New manager", nameEn: "New manager", roles: [.fundManager])
        let oldProject = ProjectRecord(id: "project-old", nameSv: "Old project", nameEn: "Old project")
        let newProject = ProjectRecord(id: "project-new", nameSv: "New project", nameEn: "New project")
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organizationID: "organization-old",
            organization: "Old funder",
            grantName: "Grant",
            projectID: "project-old",
            projectType: "Old project",
            applicationManagerID: "manager-old",
            applicationManager: "Old manager"
        )
        let store = GrantDataStore(
            applications: [application],
            organizations: [oldFunder, newFunder, oldManager, newManager],
            projects: [oldProject, newProject]
        )

        var edited = try XCTUnwrap(store.applications.first)
        edited.organizationID = "organization-new"
        edited.organization = "New funder"
        edited.projectType = "New project"
        edited.applicationManagerID = "manager-new"
        edited.applicationManager = "New manager"
        store.save(application: edited)

        let saved = try XCTUnwrap(store.applications.first)
        XCTAssertEqual(saved.organizationID, "organization-new")
        XCTAssertEqual(saved.organization, "New funder")
        XCTAssertEqual(saved.projectID, "project-new")
        XCTAssertEqual(saved.projectType, "New project")
        XCTAssertEqual(saved.applicationManagerID, "manager-new")
        XCTAssertEqual(saved.applicationManager, "New manager")
    }

    @MainActor
    func testSavingApplicationRelationEditsCanClearStaleIDs() throws {
        let project = ProjectRecord(id: "project-old", nameSv: "Old project", nameEn: "Old project")
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organizationID: "organization-old",
            organization: "Old funder",
            grantName: "Grant",
            projectID: "project-old",
            projectType: "Old project",
            applicationManagerID: "manager-old",
            applicationManager: "Old manager"
        )
        let store = GrantDataStore(
            applications: [application],
            organizations: [
                OrganizationRecord(id: "organization-old", nameSv: "Old funder", nameEn: "Old funder", roles: [.grantProvider]),
                OrganizationRecord(id: "manager-old", nameSv: "Old manager", nameEn: "Old manager", roles: [.fundManager])
            ],
            projects: [project]
        )

        var edited = try XCTUnwrap(store.applications.first)
        edited.organizationID = nil
        edited.organization = ""
        edited.projectType = nil
        edited.applicationManagerID = nil
        edited.applicationManager = nil
        store.save(application: edited)

        let saved = try XCTUnwrap(store.applications.first)
        XCTAssertNil(saved.organizationID)
        XCTAssertEqual(saved.organization, "")
        XCTAssertNil(saved.projectID)
        XCTAssertNil(saved.projectType)
        XCTAssertNil(saved.applicationManagerID)
        XCTAssertNil(saved.applicationManager)
    }

    @MainActor
    func testNotAppliedApplicationKeepsRelationsStoredButHidesThemFromQualityAndIndexes() {
        let project = ProjectRecord(id: "project-alpha", nameSv: "Alpha", nameEn: "Alpha")
        let author = PublicationAuthor(
            id: "author-anna",
            name: "Anna Andersson",
            firstName: "Anna",
            lastName: "Andersson"
        )
        let notApplied = GrantApplication(
            id: "app-not-applied",
            rowNumber: 1,
            organization: "Funder",
            grantName: "Grant",
            projectID: project.id,
            projectType: project.nameSv,
            result: "Ej sökt",
            coApplicants: [author.name]
        )
        let store = GrantDataStore(
            applications: [notApplied],
            projects: [project],
            publicationAuthors: [author]
        )

        let missingIssue = store.missingFieldIssues(includeHidden: true).first {
            $0.destination == AppRoute.Destination.applications && $0.recordID == notApplied.id
        }
        XCTAssertNil(missingIssue)
        XCTAssertEqual(store.applications(forProjectName: project.nameSv).map { $0.id }, [String]())
        XCTAssertEqual(store.applications(forPersonName: author.name).map { $0.id }, [String]())

        var toApply = notApplied
        toApply.result = "Att söka"
        store.save(application: toApply)

        XCTAssertEqual(store.applications(forProjectName: project.nameSv).map { $0.id }, [notApplied.id])
        XCTAssertEqual(store.applications(forPersonName: author.name).map { $0.id }, [notApplied.id])
    }

    @MainActor
    func testApplicationRowSnapshotsMarkFirstApplicant() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-pontus"
        let currentUser = PublicationAuthor(id: "author-pontus", name: "Pontus af Lindholm")
        let firstApplicant = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Org",
            grantName: "Grant A",
            coApplicants: ["Pontus af Lindholm", "Anna Andersson"]
        )
        let collaboratorApplication = GrantApplication(
            id: "app-2",
            rowNumber: 2,
            organization: "Org",
            grantName: "Grant B",
            coApplicants: ["Anna Andersson", "Pontus af Lindholm"]
        )
        let store = GrantDataStore(
            applications: [firstApplicant, collaboratorApplication],
            metadata: metadata,
            publicationAuthors: [currentUser]
        )
        let snapshots = store.applicationRowSnapshots()

        XCTAssertEqual(
            snapshots.first(where: { $0.id == "app-1" })?.isCurrentUserFirstApplicant,
            true
        )
        XCTAssertEqual(
            snapshots.first(where: { $0.id == "app-2" })?.isCurrentUserFirstApplicant,
            false
        )
        XCTAssertEqual(
            snapshots
                .filter {
                    applicationMatchesCurrentUserFirstApplicantFilter(
                        $0,
                        showsOnlyCurrentUserFirstApplicant: true
                    )
                }
                .map(\.id),
            ["app-1"]
        )
        XCTAssertEqual(
            snapshots
                .filter {
                    applicationMatchesCurrentUserFirstApplicantFilter(
                        $0,
                        showsOnlyCurrentUserFirstApplicant: false
                    )
                }
                .map(\.id),
            ["app-1", "app-2"]
        )
    }

    @MainActor
    func testProjectTimelineCollaboratorGrantDefaultsFollowProjectLeader() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-pontus"
        let currentUser = PublicationAuthor(id: "author-pontus", name: "Pontus af Lindholm")
        let ownProject = ProjectRecord(
            id: "project-own",
            nameSv: "Eget projekt",
            nameEn: "Own project",
            collaboratorNames: ["Pontus af Lindholm", "Anna Andersson"]
        )
        let otherProject = ProjectRecord(
            id: "project-other",
            nameSv: "Annat projekt",
            nameEn: "Other project",
            collaboratorNames: ["Anna Andersson", "Pontus af Lindholm"]
        )
        let ownGrant = GrantApplication(
            id: "grant-own",
            rowNumber: 1,
            organization: "Org",
            grantName: "Own grant",
            firstDispositionOn: "2026-01-01",
            lastDispositionOn: "2026-12-31",
            result: "Beviljat",
            coApplicants: ["Pontus af Lindholm", "Anna Andersson"]
        )
        let collaboratorGrant = GrantApplication(
            id: "grant-collaborator",
            rowNumber: 2,
            organization: "Org",
            grantName: "Collaborator grant",
            firstDispositionOn: "2026-01-01",
            lastDispositionOn: "2026-12-31",
            result: "Beviljat",
            coApplicants: ["Anna Andersson", "Pontus af Lindholm"]
        )
        let store = GrantDataStore(
            applications: [ownGrant, collaboratorGrant],
            metadata: metadata,
            projects: [ownProject, otherProject],
            publicationAuthors: [currentUser]
        )

        XCTAssertTrue(store.isCurrentUserProjectLeader(ownProject))
        XCTAssertFalse(store.includesCollaboratorGrantsInProjectTimelineByDefault(for: ownProject))
        XCTAssertFalse(store.isCurrentUserProjectLeader(otherProject))
        XCTAssertTrue(store.includesCollaboratorGrantsInProjectTimelineByDefault(for: otherProject))

        let currentUserTimelineApplications = [ownGrant, collaboratorGrant].filter {
            store.isCurrentUserFirstApplicant($0)
        }
        let snapshot = GrantDataStore.buildProjectTimelineSnapshot(
            project: ownProject,
            orderedTimelineApplications: currentUserTimelineApplications,
            publications: [],
            organizationLabels: ["Org": "Org"],
            language: .swedish
        )

        XCTAssertEqual(snapshot.grantBars.map(\.applicationID), ["grant-own"])
    }

    func testOrganizationTimelineSeparatesGrantProviderAndFundManagerApplications() throws {
        let organization = OrganizationRecord(
            id: "org-dual",
            nameSv: "Dubbel organisation",
            nameEn: "Dual organization",
            roles: [.grantProvider, .fundManager]
        )
        let providerGrant = GrantApplication(
            id: "app-provider",
            rowNumber: 1,
            organizationID: organization.id,
            organization: organization.nameSv,
            grantName: "Provider grant",
            maxAmount: "125000",
            opensOn: "2027-01-01",
            closesOn: "2027-02-01",
            projectType: "Projekt Alfa",
            result: "Att söka"
        )
        let managerGrant = GrantApplication(
            id: "app-manager",
            rowNumber: 2,
            organization: "Annan anslagsgivare",
            grantName: "Managed grant",
            decisionExpectedOn: "2026-06-01",
            projectType: "Projekt Beta",
            appliedOn: "2026-01-15",
            appliedAmountValue: 200000,
            result: "Väntar svar",
            applicationManagerID: organization.id,
            applicationManager: organization.nameSv
        )
        let sharedGrant = GrantApplication(
            id: "app-shared",
            rowNumber: 3,
            organizationID: organization.id,
            organization: organization.nameSv,
            grantName: "Shared grant",
            firstDispositionOn: "2026-01-01",
            lastDispositionOn: "2026-12-31",
            grantedAmountValue: 100000,
            result: "Beviljat",
            applicationManagerID: organization.id,
            applicationManager: organization.nameSv,
            receivedConsumptionPeriods: [
                GrantConsumptionPeriod(from: "2026-01-01", to: "2026-03-31", amount: "40000"),
                GrantConsumptionPeriod(from: "2026-04-01", to: "2026-06-30", amount: "60000")
            ]
        )

        let snapshot = GrantDataStore.buildOrganizationTimelineSnapshot(
            organization: organization,
            funderApplications: [providerGrant, sharedGrant],
            managedApplications: [managerGrant, sharedGrant],
            currentUserAuthor: nil,
            language: .swedish
        )

        XCTAssertEqual(snapshot.groups.map { $0.id }, ["grantProvider", "fundManager"])
        let providerBars = try XCTUnwrap(snapshot.groups.first { $0.id == "grantProvider" }?.bars)
        let managerBars = try XCTUnwrap(snapshot.groups.first { $0.id == "fundManager" }?.bars)

        XCTAssertTrue(providerBars.contains { $0.id == "funder-grant-app-shared" && $0.applicationID == "app-shared" })
        XCTAssertTrue(managerBars.contains { $0.id == "managed-grant-app-shared" && $0.applicationID == "app-shared" })
        let providerBar = try XCTUnwrap(providerBars.first { $0.applicationID == "app-provider" })
        XCTAssertEqual(providerBar.title, "Projekt Alfa · Dubbel organisation · 125 000 SEK")
        XCTAssertFalse(providerBar.title.contains("Att söka"))
        let managerBar = try XCTUnwrap(managerBars.first { $0.applicationID == "app-manager" })
        XCTAssertEqual(managerBar.title, "Projekt Beta · Annan anslagsgivare · 200 000 SEK")
        XCTAssertFalse(managerBar.title.contains("Väntar svar"))
        let sharedProviderBar = try XCTUnwrap(providerBars.first { $0.applicationID == "app-shared" })
        XCTAssertEqual(sharedProviderBar.fullySpentDate.map(DateParsers.isoDay.string(from:)), "2026-06-30")
        XCTAssertTrue(providerBars.contains { bar in
            if case .grantProviderGrant(.toApply) = bar.kind {
                return bar.applicationID == "app-provider"
            }
            return false
        })
        XCTAssertTrue(managerBars.contains { bar in
            if case .fundManagerGrant(.waiting) = bar.kind {
                return bar.applicationID == "app-manager"
            }
            return false
        })
    }

    func testOrganizationTimelinePacksGrantRowsByRoleSpecificIdentity() throws {
        let organization = OrganizationRecord(
            id: "org-dual",
            nameSv: "Dubbel organisation",
            nameEn: "Dual organization",
            roles: [.grantProvider, .fundManager]
        )
        let providerFirst = GrantApplication(
            id: "provider-first",
            rowNumber: 1,
            organizationID: organization.id,
            organization: organization.nameSv,
            grantName: "Projektbidrag",
            firstDispositionOn: "2026-01-01",
            lastDispositionOn: "2026-03-31",
            result: "Beviljat"
        )
        let providerSecond = GrantApplication(
            id: "provider-second",
            rowNumber: 2,
            organizationID: organization.id,
            organization: organization.nameSv,
            grantName: "Projektbidrag",
            firstDispositionOn: "2026-04-01",
            lastDispositionOn: "2026-06-30",
            result: "Beviljat"
        )
        let providerDifferentGrant = GrantApplication(
            id: "provider-different",
            rowNumber: 3,
            organizationID: organization.id,
            organization: organization.nameSv,
            grantName: "Resebidrag",
            firstDispositionOn: "2026-07-01",
            lastDispositionOn: "2026-08-31",
            result: "Beviljat"
        )
        let managerFirst = GrantApplication(
            id: "manager-first",
            rowNumber: 4,
            organizationID: "org-funder-a",
            organization: "Funder A",
            grantName: "Grant A1",
            firstDispositionOn: "2026-01-01",
            lastDispositionOn: "2026-03-31",
            result: "Beviljat",
            applicationManagerID: organization.id,
            applicationManager: organization.nameSv
        )
        let managerSecond = GrantApplication(
            id: "manager-second",
            rowNumber: 5,
            organizationID: "org-funder-a",
            organization: "Funder A",
            grantName: "Grant A2",
            firstDispositionOn: "2026-04-01",
            lastDispositionOn: "2026-06-30",
            result: "Beviljat",
            applicationManagerID: organization.id,
            applicationManager: organization.nameSv
        )
        let managerDifferentFunder = GrantApplication(
            id: "manager-different",
            rowNumber: 6,
            organizationID: "org-funder-b",
            organization: "Funder B",
            grantName: "Grant B",
            firstDispositionOn: "2026-07-01",
            lastDispositionOn: "2026-08-31",
            result: "Beviljat",
            applicationManagerID: organization.id,
            applicationManager: organization.nameSv
        )

        let snapshot = GrantDataStore.buildOrganizationTimelineSnapshot(
            organization: organization,
            funderApplications: [providerFirst, providerSecond, providerDifferentGrant],
            managedApplications: [managerFirst, managerSecond, managerDifferentFunder],
            currentUserAuthor: nil,
            language: .swedish
        )

        let providerGroup = try XCTUnwrap(snapshot.groups.first { $0.id == "grantProvider" })
        XCTAssertEqual(providerGroup.rows.count, 2)
        XCTAssertTrue(providerGroup.rows.contains { row in
            Set(row.compactMap(\.applicationID)) == Set(["provider-first", "provider-second"])
        })
        XCTAssertTrue(providerGroup.rows.contains { row in
            Set(row.compactMap(\.applicationID)) == Set(["provider-different"])
        })

        let managerGroup = try XCTUnwrap(snapshot.groups.first { $0.id == "fundManager" })
        XCTAssertEqual(managerGroup.rows.count, 2)
        XCTAssertTrue(managerGroup.rows.contains { row in
            Set(row.compactMap(\.applicationID)) == Set(["manager-first", "manager-second"])
        })
        XCTAssertTrue(managerGroup.rows.contains { row in
            Set(row.compactMap(\.applicationID)) == Set(["manager-different"])
        })
    }

    func testOrganizationTimelineIncludesCongressAndEmploymentSalaryPeriods() throws {
        let congress = OrganizationCongress(
            id: "congress-1",
            title: "Nordic Congress",
            from: "2026-05-10",
            fromUncertain: true,
            to: "2026-05-12"
        )
        let organization = OrganizationRecord(
            id: "org-employer",
            nameSv: "Region Exempelgöta",
            nameEn: "Region Exempelgota",
            roles: [.association, .employer],
            congresses: [congress]
        )
        let currentUser = PublicationAuthor(
            id: "author-current",
            name: "Pontus af Lindholm",
            employments: [
                PublicationAuthorEmployment(
                    id: "employment-1",
                    from: "2026-01-01",
                    to: "2026-12-31",
                    title: "Researcher",
                    organization: "Region Exempelgöta"
                )
            ]
        )
        var calculator = ManagerSalaryCalculator.empty
        calculator.monthlySalaryPeriods = [
            SalaryCalculatorPeriod(id: "salary-1", value: "55000", from: "2026-03-01", to: "2026-06-30"),
            SalaryCalculatorPeriod(id: "salary-2", value: "56000", from: "2026-07-01", to: "2026-08-31")
        ]

        let snapshot = GrantDataStore.buildOrganizationTimelineSnapshot(
            organization: organization,
            salaryCalculator: calculator,
            funderApplications: [],
            managedApplications: [],
            currentUserAuthor: currentUser,
            language: .swedish
        )

        XCTAssertEqual(snapshot.groups.map { $0.id }, ["employer", "association"])
        let congressBar = try XCTUnwrap(snapshot.groups.first { $0.id == "association" }?.bars.first)
        XCTAssertEqual(congressBar.title, "Nordic Congress, 10-12 maj 2026")
        XCTAssertTrue(congressBar.hasUncertainOutline)

        let employerGroup = try XCTUnwrap(snapshot.groups.first { $0.id == "employer" })
        XCTAssertEqual(employerGroup.rows.count, 1)
        XCTAssertEqual(employerGroup.bars.count, 2)

        let employmentBar = try XCTUnwrap(employerGroup.bars.first)
        XCTAssertEqual(employmentBar.title, "Researcher · 55 000 SEK/mån · 2026-03-01 - 2026-06-30")
        XCTAssertEqual(employmentBar.hoverText, "Arbetsgivare: anställning och lön\nResearcher · 55 000 SEK/mån · 2026-03-01 - 2026-06-30")
        XCTAssertTrue(employmentBar.title.contains("55 000 SEK/mån"))
        XCTAssertEqual(DateParsers.isoDay.string(from: employmentBar.start), "2026-03-01")
        XCTAssertEqual(DateParsers.isoDay.string(from: employmentBar.end), "2026-06-30")
    }

    func testOrganizationTimelineExtendsOpenEndedEmploymentAndSalaryPeriods() throws {
        let referenceDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-05-24"))
        let organization = OrganizationRecord(
            id: "org-open-employer",
            nameSv: "Region Exempelgöta",
            nameEn: "Region Exempelgota",
            roles: [.employer]
        )
        let currentUser = PublicationAuthor(
            id: "author-current",
            name: "Pontus af Lindholm",
            employments: [
                PublicationAuthorEmployment(
                    id: "employment-open",
                    from: "2026-04-01",
                    title: "Senior Researcher",
                    organization: "Region Exempelgöta"
                )
            ]
        )
        var calculator = ManagerSalaryCalculator.empty
        calculator.monthlySalaryPeriods = [
            SalaryCalculatorPeriod(id: "salary-open", value: "60000", from: "2026-05-01")
        ]

        let combinedSnapshot = GrantDataStore.buildOrganizationTimelineSnapshot(
            organization: organization,
            salaryCalculator: calculator,
            funderApplications: [],
            managedApplications: [],
            currentUserAuthor: currentUser,
            language: .swedish,
            referenceDate: referenceDate
        )

        let combinedBar = try XCTUnwrap(combinedSnapshot.groups.first { $0.id == "employer" }?.bars.first)
        XCTAssertEqual(DateParsers.isoDay.string(from: combinedBar.start), "2026-05-01")
        XCTAssertEqual(DateParsers.isoDay.string(from: combinedBar.end), "2027-12-31")
        XCTAssertEqual(combinedBar.title, "Senior Researcher · 60 000 SEK/mån · 2026-05-01 - pågående")

        let salaryOnlySnapshot = GrantDataStore.buildOrganizationTimelineSnapshot(
            organization: organization,
            salaryCalculator: calculator,
            funderApplications: [],
            managedApplications: [],
            currentUserAuthor: nil,
            language: .swedish,
            referenceDate: referenceDate
        )
        let salaryOnlyBar = try XCTUnwrap(salaryOnlySnapshot.groups.first { $0.id == "employer" }?.bars.first)
        XCTAssertEqual(DateParsers.isoDay.string(from: salaryOnlyBar.end), "2027-12-31")
        XCTAssertEqual(salaryOnlyBar.title, "60 000 SEK/mån · 2026-05-01 - pågående")

        let employmentOnlySnapshot = GrantDataStore.buildOrganizationTimelineSnapshot(
            organization: organization,
            salaryCalculator: .empty,
            funderApplications: [],
            managedApplications: [],
            currentUserAuthor: currentUser,
            language: .swedish,
            referenceDate: referenceDate
        )
        let employmentOnlyBar = try XCTUnwrap(employmentOnlySnapshot.groups.first { $0.id == "employer" }?.bars.first)
        XCTAssertEqual(DateParsers.isoDay.string(from: employmentOnlyBar.end), "2027-12-31")
        XCTAssertEqual(employmentOnlyBar.title, "Senior Researcher · 2026-04-01 - pågående")
    }

    func testCongressMapRowsIncludeUpcomingCongressesWithLocations() throws {
        let today = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-05-24"))
        let organization = OrganizationRecord(
            id: "org-congress-map",
            nameSv: "European Society",
            nameEn: "European Society",
            roles: [.association],
            congresses: [
                OrganizationCongress(
                    id: "past",
                    title: "Past Meeting",
                    from: "2026-05-10",
                    to: "2026-05-12",
                    city: "Oslo",
                    country: "Norway"
                ),
                OrganizationCongress(
                    id: "ongoing",
                    title: "Current Meeting",
                    from: "2026-05-23",
                    to: "2026-05-25",
                    city: "Stockholm",
                    country: "Sweden"
                ),
                OrganizationCongress(
                    id: "future",
                    title: "Future Meeting",
                    from: "2026-06-01",
                    city: "Berlin",
                    country: "Germany",
                    link: "example.org"
                )
            ]
        )

        let rows = CongressMapModel.upcomingCongressRows(
            organizations: [organization],
            language: .swedish,
            today: today
        )

        XCTAssertEqual(rows.map(\.congressID), ["ongoing", "future"])
        XCTAssertEqual(rows.first?.placeText, "Stockholm, Sweden")
        XCTAssertEqual(rows.first?.startDateText, "23 maj 2026")
        XCTAssertEqual(rows.first?.dateText, "23-25 maj 2026")
        XCTAssertEqual(rows.last?.startDateText, "1 juni 2026")
        XCTAssertEqual(rows.last?.dateText, "1 juni 2026")
        XCTAssertEqual(rows.last?.locationCacheKey, "berlin, germany")
        XCTAssertEqual(rows.last?.link, "example.org")
    }

    func testCongressMapRowsCanLimitMonthsAheadAndHidePassedAbstractDeadlines() throws {
        let today = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-05-24"))
        let organization = OrganizationRecord(
            id: "org-congress-map-filter",
            nameSv: "Congress Society",
            nameEn: "Congress Society",
            roles: [.association],
            congresses: [
                OrganizationCongress(
                    id: "passed-abstract",
                    title: "Passed abstract",
                    from: "2026-06-20",
                    abstractSubmissionDeadline: "2026-05-01",
                    city: "Paris",
                    country: "France"
                ),
                OrganizationCongress(
                    id: "late-abstract-open",
                    title: "Late abstract still open",
                    from: "2026-06-22",
                    abstractSubmissionDeadline: "2026-05-01",
                    lateAbstractSubmissionDeadline: "2026-06-01",
                    city: "Rome",
                    country: "Italy"
                ),
                OrganizationCongress(
                    id: "too-far-away",
                    title: "Too far away",
                    from: "2026-09-01",
                    city: "Madrid",
                    country: "Spain"
                )
            ]
        )

        let rows = CongressMapModel.upcomingCongressRows(
            organizations: [organization],
            language: .swedish,
            monthsAhead: 2,
            hidesPassedAbstractDeadlines: true,
            today: today
        )

        XCTAssertEqual(rows.map(\.congressID), ["late-abstract-open"])
    }

    func testCongressMapRowsHideMapHiddenCongressesUnlessRequested() throws {
        let today = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-05-24"))
        let organization = OrganizationRecord(
            id: "org-congress-map-hidden",
            nameSv: "Congress Society",
            nameEn: "Congress Society",
            roles: [.association],
            congresses: [
                OrganizationCongress(
                    id: "hidden",
                    title: "Hidden congress",
                    from: "2026-06-01",
                    city: "Paris",
                    country: "France",
                    isHiddenOnMap: true
                ),
                OrganizationCongress(
                    id: "visible",
                    title: "Visible congress",
                    from: "2026-06-02",
                    city: "Rome",
                    country: "Italy"
                )
            ]
        )

        let defaultRows = CongressMapModel.upcomingCongressRows(
            organizations: [organization],
            language: .swedish,
            today: today
        )
        let rowsWithHidden = CongressMapModel.upcomingCongressRows(
            organizations: [organization],
            language: .swedish,
            showsHiddenCongresses: true,
            today: today
        )

        XCTAssertEqual(defaultRows.map(\.congressID), ["visible"])
        XCTAssertEqual(rowsWithHidden.map(\.congressID), ["hidden", "visible"])
        XCTAssertEqual(rowsWithHidden.first?.isHiddenOnMap, true)
    }

    func testCongressMapAdaptiveLayoutClustersNearbyCongressesAtTheSameLocation() {
        let items = [
            CongressMapAdaptiveLayoutItem(
                id: "later",
                point: CGPoint(x: 120, y: 140),
                locationCacheKey: "paris, france",
                city: "Paris",
                placeText: "Paris, France",
                startDate: Date(timeIntervalSinceReferenceDate: 300),
                currentUserParticipates: false
            ),
            CongressMapAdaptiveLayoutItem(
                id: "participating",
                point: CGPoint(x: 128, y: 145),
                locationCacheKey: "paris, france",
                city: "Paris",
                placeText: "Paris, France",
                startDate: Date(timeIntervalSinceReferenceDate: 200),
                currentUserParticipates: true
            ),
            CongressMapAdaptiveLayoutItem(
                id: "earlier",
                point: CGPoint(x: 132, y: 151),
                locationCacheKey: "paris, france",
                city: "Paris",
                placeText: "Paris, France",
                startDate: Date(timeIntervalSinceReferenceDate: 100),
                currentUserParticipates: false
            )
        ]

        let plans = CongressMapAdaptiveLayout.labelPlans(
            items: items,
            selectedID: nil,
            capacity: 10
        )

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.representativeID, "participating")
        XCTAssertEqual(plans.first?.memberIDs.sorted(), ["earlier", "later", "participating"])
        XCTAssertEqual(plans.first?.kind, .cluster(count: 3, placeText: "Paris"))
    }

    func testCongressMapAdaptiveLayoutAlwaysBreaksSelectedCongressOutOfCluster() {
        let items = [
            CongressMapAdaptiveLayoutItem(
                id: "selected",
                point: CGPoint(x: 200, y: 200),
                locationCacheKey: "berlin, germany",
                city: "Berlin",
                placeText: "Berlin, Germany",
                startDate: Date(timeIntervalSinceReferenceDate: 300),
                currentUserParticipates: false
            ),
            CongressMapAdaptiveLayoutItem(
                id: "second",
                point: CGPoint(x: 204, y: 202),
                locationCacheKey: "berlin, germany",
                city: "Berlin",
                placeText: "Berlin, Germany",
                startDate: Date(timeIntervalSinceReferenceDate: 200),
                currentUserParticipates: false
            ),
            CongressMapAdaptiveLayoutItem(
                id: "third",
                point: CGPoint(x: 208, y: 205),
                locationCacheKey: "berlin, germany",
                city: "Berlin",
                placeText: "Berlin, Germany",
                startDate: Date(timeIntervalSinceReferenceDate: 100),
                currentUserParticipates: false
            )
        ]

        let plans = CongressMapAdaptiveLayout.labelPlans(
            items: items,
            selectedID: "selected",
            capacity: 2
        )

        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans.first?.representativeID, "selected")
        XCTAssertEqual(plans.first?.kind, .congress)
        XCTAssertEqual(plans.first?.isSelected, true)
        XCTAssertEqual(plans.last?.kind, .cluster(count: 2, placeText: "Berlin"))
    }

    func testCongressMapAdaptiveLayoutPrioritizesSelectedCongressWhenCapacityIsLimited() {
        let items = [
            CongressMapAdaptiveLayoutItem(
                id: "participating",
                point: CGPoint(x: 40, y: 40),
                locationCacheKey: "oslo, norway",
                city: "Oslo",
                placeText: "Oslo, Norway",
                startDate: Date(timeIntervalSinceReferenceDate: 100),
                currentUserParticipates: true
            ),
            CongressMapAdaptiveLayoutItem(
                id: "selected",
                point: CGPoint(x: 500, y: 500),
                locationCacheKey: "tokyo, japan",
                city: "Tokyo",
                placeText: "Tokyo, Japan",
                startDate: Date(timeIntervalSinceReferenceDate: 500),
                currentUserParticipates: false
            )
        ]

        let plans = CongressMapAdaptiveLayout.labelPlans(
            items: items,
            selectedID: "selected",
            capacity: 1
        )

        XCTAssertEqual(plans.map(\.representativeID), ["selected"])
    }

    func testCongressMapRowsCanLimitMonthsFromAndThrough() throws {
        let today = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-05-24"))
        let organization = OrganizationRecord(
            id: "org-congress-map-range-filter",
            nameSv: "Congress Society",
            nameEn: "Congress Society",
            roles: [.association],
            congresses: [
                OrganizationCongress(
                    id: "too-early",
                    title: "Too early",
                    from: "2026-08-01",
                    to: "2026-08-02",
                    city: "Paris",
                    country: "France"
                ),
                OrganizationCongress(
                    id: "overlaps-start",
                    title: "Overlaps start",
                    from: "2026-08-23",
                    to: "2026-08-25",
                    city: "Rome",
                    country: "Italy"
                ),
                OrganizationCongress(
                    id: "inside-range",
                    title: "Inside range",
                    from: "2026-09-10",
                    city: "Madrid",
                    country: "Spain"
                ),
                OrganizationCongress(
                    id: "too-late",
                    title: "Too late",
                    from: "2026-12-01",
                    city: "Berlin",
                    country: "Germany"
                )
            ]
        )

        let rows = CongressMapModel.upcomingCongressRows(
            organizations: [organization],
            language: .swedish,
            monthsFrom: 3,
            monthsAhead: 6,
            today: today
        )

        XCTAssertEqual(rows.map(\.congressID), ["overlaps-start", "inside-range"])
    }

    func testCongressMapParticipatedFilterIncludesPastCongresses() throws {
        let today = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-05-24"))
        let currentUser = PublicationAuthor(
            id: "author-current",
            name: "Fredrik Falk",
            firstName: "Fredrik",
            lastName: "Falk"
        )
        let organization = OrganizationRecord(
            id: "org-congress-map-participated",
            nameSv: "Congress Society",
            nameEn: "Congress Society",
            roles: [.association],
            congresses: [
                OrganizationCongress(
                    id: "past-attended",
                    title: "Past attended",
                    from: "2024-06-10",
                    to: "2024-06-12",
                    city: "Toronto",
                    country: "Canada",
                    participantAuthorIDs: ["author-current"]
                ),
                OrganizationCongress(
                    id: "past-abstract",
                    title: "Past abstract",
                    from: "2024-09-10",
                    city: "Oslo",
                    country: "Norway"
                ),
                OrganizationCongress(
                    id: "past-unrelated",
                    title: "Past unrelated",
                    from: "2024-10-10",
                    city: "Berlin",
                    country: "Germany"
                )
            ]
        )
        let contribution = CVConferenceContribution(
            id: "contribution-past",
            title: "Linked abstract",
            congressOrganizationID: organization.id,
            congressID: "past-abstract"
        )

        let rows = CongressMapModel.upcomingCongressRows(
            organizations: [organization],
            conferenceContributions: [contribution],
            language: .swedish,
            currentUserAuthor: currentUser,
            monthsAhead: 1,
            hidesPassedAbstractDeadlines: true,
            showsParticipatedCongressesOnly: true,
            today: today
        )

        XCTAssertEqual(rows.map(\.congressID), ["past-attended", "past-abstract"])
    }

    func testOrganizationTimelineDisplaysCongressLocationDatesAndDeadlineMarkersInPackedRows() throws {
        let congressWithDeadlines = OrganizationCongress(
            id: "congress-1",
            title: "Epidemiology Summit",
            from: "2026-05-09",
            to: "2026-05-12",
            abstractSubmissionDeadline: "2026-04-01",
            lateAbstractSubmissionDeadline: "2026-04-15",
            lateAbstractSubmissionDeadlineUncertain: true,
            city: "Stockholm",
            country: "Sweden"
        )
        let overlappingCongress = OrganizationCongress(
            id: "congress-2",
            title: "Methods Meeting",
            from: "2026-04-10",
            to: "2026-04-11",
            city: "Oslo",
            country: "Norway"
        )
        let followingCongress = OrganizationCongress(
            id: "congress-3",
            title: "Registry Days",
            from: "2026-05-20",
            to: "2026-05-22",
            city: "Copenhagen",
            country: "Denmark"
        )
        let organization = OrganizationRecord(
            id: "org-association",
            nameSv: "Föreningen",
            nameEn: "Association",
            roles: [.association],
            congresses: [congressWithDeadlines, overlappingCongress, followingCongress]
        )

        let snapshot = GrantDataStore.buildOrganizationTimelineSnapshot(
            organization: organization,
            funderApplications: [],
            managedApplications: [],
            currentUserAuthor: nil,
            language: .swedish
        )

        let associationGroup = try XCTUnwrap(snapshot.groups.first { $0.id == "association" })
        let congressBar = try XCTUnwrap(associationGroup.bars.first { $0.id == "congress-congress-1" })
        XCTAssertEqual(congressBar.title, "Stockholm, Sweden, 9-12 maj 2026")
        XCTAssertEqual(congressBar.markers.count, 2)
        XCTAssertEqual(DateParsers.isoDay.string(from: congressBar.packingStart), "2026-04-01")
        XCTAssertEqual(DateParsers.isoDay.string(from: congressBar.packingEnd), "2026-05-12")
        XCTAssertTrue(congressBar.markers.contains { marker in
            marker.id == "congress-congress-1-abstract-deadline"
                && marker.title == "Abstractfrist"
                && DateParsers.isoDay.string(from: marker.date) == "2026-04-01"
        })
        XCTAssertTrue(congressBar.markers.contains { marker in
            guard marker.id == "congress-congress-1-late-abstract-deadline",
                  DateParsers.isoDay.string(from: marker.date) == "2026-04-15",
                  marker.hasUncertainOutline else { return false }
            if case .congressLateAbstractDeadline = marker.kind {
                return true
            }
            return false
        })

        XCTAssertEqual(associationGroup.rows.count, 2)
        XCTAssertTrue(associationGroup.rows.contains { row in
            Set(row.map { $0.id }) == Set(["congress-congress-1", "congress-congress-3"])
        })
        XCTAssertTrue(associationGroup.rows.contains { row in
            Set(row.map { $0.id }) == Set(["congress-congress-2"])
        })
    }

    func testOrganizationTimelineCanHidePastEventsAndRejectedGrants() throws {
        let pastCongress = OrganizationCongress(
            id: "past-congress",
            title: "Past Congress",
            from: "2026-01-10",
            to: "2026-01-12",
            city: "Uppsala",
            country: "Sweden"
        )
        let futureCongress = OrganizationCongress(
            id: "future-congress",
            title: "Future Congress",
            from: "2026-06-10",
            to: "2026-06-12",
            abstractSubmissionDeadline: "2026-05-01",
            lateAbstractSubmissionDeadline: "2026-06-01",
            city: "Stockholm",
            country: "Sweden"
        )
        let organization = OrganizationRecord(
            id: "org-filters",
            nameSv: "Filterorganisation",
            nameEn: "Filter organization",
            roles: [.association, .grantProvider],
            congresses: [pastCongress, futureCongress]
        )
        let pastGrantedGrant = GrantApplication(
            id: "past-granted",
            rowNumber: 1,
            organizationID: organization.id,
            organization: organization.nameSv,
            grantName: "Past granted",
            firstDispositionOn: "2026-01-01",
            lastDispositionOn: "2026-02-01",
            result: "Beviljat"
        )
        let futureRejectedGrant = GrantApplication(
            id: "future-rejected",
            rowNumber: 2,
            organizationID: organization.id,
            organization: organization.nameSv,
            grantName: "Future rejected",
            appliedOn: "2026-06-01",
            deniedOn: "2026-07-01",
            result: "Avslag"
        )
        let futureWaitingGrant = GrantApplication(
            id: "future-waiting",
            rowNumber: 3,
            organizationID: organization.id,
            organization: organization.nameSv,
            grantName: "Future waiting",
            decisionExpectedOn: "2026-07-01",
            appliedOn: "2026-06-01",
            result: "Väntar svar"
        )
        let referenceDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-05-24"))

        let snapshot = GrantDataStore.buildOrganizationTimelineSnapshot(
            organization: organization,
            funderApplications: [pastGrantedGrant, futureRejectedGrant, futureWaitingGrant],
            managedApplications: [],
            currentUserAuthor: nil,
            language: .swedish,
            hidePastEvents: true,
            hideRejectedGrants: true,
            referenceDate: referenceDate
        )

        let associationGroup = try XCTUnwrap(snapshot.groups.first { $0.id == "association" })
        XCTAssertEqual(associationGroup.bars.map { $0.id }, ["congress-future-congress"])
        let congressBar = try XCTUnwrap(associationGroup.bars.first)
        XCTAssertEqual(congressBar.markers.map { $0.id }, ["congress-future-congress-late-abstract-deadline"])

        let providerGroup = try XCTUnwrap(snapshot.groups.first { $0.id == "grantProvider" })
        XCTAssertEqual(providerGroup.bars.map { $0.applicationID }, ["future-waiting"])
    }

    func testGrantSalaryApproximationSplitsTotalByYear() throws {
        let calculator = ManagerSalaryCalculator(
            birthDate: "2000-01-01",
            monthlySalaryPeriods: [SalaryCalculatorPeriod(value: "1000", from: "2027-01-01", to: "2028-12-31")],
            employerFeePeriods: [],
            regionalCostPeriods: [],
            itInfrastructureFeePeriods: [],
            listedPatientCountPeriods: [],
            overheadPeriods: [],
            annualIncreaseAfterCurrentYearPercent: "0",
            allocationPercent: "",
            allocationMonths: ""
        )
        let startMonth = try XCTUnwrap(DateParsers.isoDay.date(from: "2027-01-01"))

        let breakdown = try XCTUnwrap(
            calculateGrantSalaryApproximation(
                calculator: calculator,
                percentageText: "100",
                monthsText: "24",
                startMonth: startMonth,
                includesOverhead: false
            )
        )

        XCTAssertEqual(breakdown.yearlyAmounts.map(\.year), [2027, 2028])
        XCTAssertEqual(breakdown.yearlyAmounts[0].amount, 12_151.25, accuracy: 0.01)
        XCTAssertEqual(breakdown.yearlyAmounts[1].amount, 12_151.25, accuracy: 0.01)
        XCTAssertEqual(breakdown.totalAmount, 24_302.50, accuracy: 0.01)
    }

    @MainActor
    func testInitializationDoesNotInjectTeachingSeedDataOrPublicationAuthors() {
        let store = GrantDataStore(
            teachingCourses: [],
            teachingComponents: [],
            teachingFormats: [],
            teachingAssignments: [],
            doctoralCandidates: [],
            publicationAuthors: []
        )

        XCTAssertTrue(store.publicationAuthors.isEmpty)
        XCTAssertTrue(store.teachingCourses.isEmpty)
        XCTAssertTrue(store.teachingFormats.isEmpty)
    }

    @MainActor
    func testInitializationDoesNotSeedProjectDetails() {
        let project = ProjectRecord(id: "project-alpha-study", nameSv: "ALPHA-STUDY", nameEn: "ALPHA-STUDY")
        let store = GrantDataStore(projects: [project])

        XCTAssertEqual(store.projects.count, 1)
        XCTAssertFalse(store.projects[0].hasDataCollection)
        XCTAssertTrue(store.projects[0].ethicsBaseApplication.isEmpty)
        XCTAssertTrue(store.projects[0].ethicsAmendments.isEmpty)
        XCTAssertTrue(store.projects[0].clinicalTrialRegistrations.isEmpty)
        XCTAssertTrue(store.projects[0].projectTasks.isEmpty)
    }

    @MainActor
    func testDeferredLaunchMaintenanceDoesNotSeedCVEntries() {
        let store = GrantDataStore(
            teachingAssignments: [],
            cvReviewEntries: [],
            cvOtherPublications: []
        )

        store.runDeferredLaunchMaintenanceIfNeeded()

        XCTAssertTrue(store.cvOtherPublications.isEmpty)
    }

    @MainActor
    func testSavingProjectDoesNotInjectDefaultFundingTask() {
        let project = ProjectRecord(
            id: "project-own",
            nameSv: "Own project",
            nameEn: "Own project",
            collaboratorNames: ["Pontus af Lindholm"],
            projectStatus: .ongoing,
            projectTasks: []
        )
        let store = GrantDataStore(projects: [project])

        store.updateProjectRecord(project, previousID: project.id)

        XCTAssertEqual(store.projects.first?.projectTasks, [])
    }

    @MainActor
    func testAwardingApplicationCreatesLinkedNewFundsProjectTask() throws {
        let template = ProjectTaskItem(
            id: "task-template",
            reminder: .newFundsReceived,
            comment: "Informera chef/Tessaadministratör, controller och redovisningsekonom om nya beviljade medel"
        )
        let project = ProjectRecord(
            id: "project-alpha-study",
            nameSv: "ALPHA-STUDY",
            nameEn: "ALPHA-STUDY",
            projectTasks: [template]
        )
        let application = GrantApplication(
            id: "application-alpha-study",
            rowNumber: 1,
            organization: "Region Exempelgöta",
            grantName: "Forskningsanslag",
            projectID: project.id
        )
        let store = GrantDataStore(applications: [application], projects: [project], skipInitialMigration: true)

        var awarded = application
        awarded.grantedOn = "2026-06-14"
        awarded.grantedAmount = "100000"
        store.save(application: awarded)

        let linkedTasks = try XCTUnwrap(store.projects.first?.projectTasks).filter {
            $0.reminder == .newFundsReceived && $0.applicationID == application.id
        }
        XCTAssertEqual(linkedTasks.count, 1)
        let linkedTask = try XCTUnwrap(linkedTasks.first)
        XCTAssertEqual(linkedTask.deadline, "2026-06-14")
        XCTAssertEqual(linkedTask.comment, template.comment)
        XCTAssertFalse(linkedTask.id.isEmpty)
        XCTAssertNotEqual(linkedTask.id, template.id)
        XCTAssertEqual(store.applications.first?.result, "Beviljat")

        store.save(application: awarded)

        let repeatedLinkedTasks = try XCTUnwrap(store.projects.first?.projectTasks).filter {
            $0.reminder == .newFundsReceived && $0.applicationID == application.id
        }
        XCTAssertEqual(repeatedLinkedTasks.count, 1)
        let persistedProjects = try XCTUnwrap(store.sqliteStore?.load([ProjectRecord].self, named: "projects"))
        XCTAssertEqual(
            persistedProjects.first?.projectTasks.filter {
                $0.reminder == .newFundsReceived && $0.applicationID == application.id
            }.count,
            1
        )
    }

    @MainActor
    func testMigrationBackfillsLinkedNewFundsProjectTasksForAlreadyGrantedApplications() throws {
        let applicationID = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        let projectID = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        let template = ProjectTaskItem(
            id: "task-template",
            reminder: .newFundsReceived,
            comment: "Informera chef/Tessaadministratör, controller och redovisningsekonom om nya beviljade medel"
        )
        let project = ProjectRecord(
            id: projectID,
            nameSv: "ALPHA-STUDY",
            nameEn: "ALPHA-STUDY",
            projectTasks: [template]
        )
        let application = GrantApplication(
            id: applicationID,
            rowNumber: 1,
            organization: "Region Exempelgöta",
            grantName: "Forskningsanslag",
            projectID: projectID,
            grantedOn: "2026-06-14",
            result: "Beviljat"
        )
        let store = GrantDataStore(applications: [application], projects: [project], skipInitialMigration: true)

        _ = store.migrateRecordsIfNeeded()

        let linkedTasks = try XCTUnwrap(store.projects.first?.projectTasks).filter {
            $0.reminder == .newFundsReceived && $0.applicationID == applicationID
        }
        XCTAssertEqual(linkedTasks.count, 1)
        XCTAssertEqual(linkedTasks.first?.deadline, "2026-06-14")

        _ = store.migrateRecordsIfNeeded()

        let repeatedLinkedTasks = try XCTUnwrap(store.projects.first?.projectTasks).filter {
            $0.reminder == .newFundsReceived && $0.applicationID == applicationID
        }
        XCTAssertEqual(repeatedLinkedTasks.count, 1)
    }

    @MainActor
    func testCompletedDataCollectionMovesDependentProjectTasksToToday() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayString = DateParsers.isoDay.string(from: today)
        let yesterdayString = DateParsers.isoDay.string(
            from: calendar.date(byAdding: .day, value: -1, to: today) ?? today
        )

        let project = ProjectRecord(
            id: "project-alpha-study",
            nameSv: "ALPHA-STUDY",
            nameEn: "ALPHA-STUDY",
            hasDataCollection: true,
            dataCollections: [ProjectDataCollection(id: "collection-1", from: "2026-05-01", to: todayString)],
            projectTasks: [
                ProjectTaskItem(
                    id: "task-1",
                    deadline: "",
                    reminder: .dataCollectionCompleted,
                    comment: "Check data"
                )
            ]
        )
        let store = GrantDataStore(projects: [project])

        var updated = project
        updated.dataCollections = [
            ProjectDataCollection(id: "collection-1", from: "2026-05-01", to: yesterdayString)
        ]
        store.updateProjectRecord(updated, previousID: project.id)

        let task = store.projects.first?.projectTasks.first
        XCTAssertEqual(task?.deadline, todayString)
        XCTAssertEqual(task?.updatedOn, todayString)
    }

    func testEasterSundayUsesGregorianEcclesiasticalRule() throws {
        let calendar = Calendar(identifier: .gregorian)

        let easter2026 = try XCTUnwrap(HolidayCalendarBuilder.easterSunday(year: 2026, calendar: calendar))
        let easter2027 = try XCTUnwrap(HolidayCalendarBuilder.easterSunday(year: 2027, calendar: calendar))

        XCTAssertEqual(DateParsers.isoDay.string(from: easter2026), "2026-04-05")
        XCTAssertEqual(DateParsers.isoDay.string(from: easter2027), "2027-03-28")
    }

    func testSwedishAndNorwegianHolidayGenerationIncludesMovableAndRangeBasedDates() {
        let calendar = Calendar(identifier: .gregorian)
        let holidays = HolidayCalendarBuilder.holidays(for: [.sweden, .norway], year: 2026, calendar: calendar)

        XCTAssertTrue(
            holidays.contains {
                $0.country == .sweden &&
                $0.key == "midsummerEve" &&
                DateParsers.isoDay.string(from: $0.date) == "2026-06-19"
            }
        )
        XCTAssertTrue(
            holidays.contains {
                $0.country == .sweden &&
                $0.key == "allSaintsDay" &&
                DateParsers.isoDay.string(from: $0.date) == "2026-10-31"
            }
        )
        XCTAssertTrue(
            holidays.contains {
                $0.country == .norway &&
                $0.key == "labourDay" &&
                DateParsers.isoDay.string(from: $0.date) == "2026-05-01"
            }
        )
        XCTAssertTrue(
            holidays.contains {
                $0.country == .norway &&
                $0.key == "constitutionDay" &&
                DateParsers.isoDay.string(from: $0.date) == "2026-05-17"
            }
        )
        XCTAssertTrue(
            holidays.contains {
                $0.country == .norway &&
                $0.key == "pentecostMonday" &&
                DateParsers.isoDay.string(from: $0.date) == "2026-05-25"
            }
        )
    }

    @MainActor
    func testHolidayCountrySelectionDefaultsToSwedenButCanBeEmpty() {
        let defaultStore = GrantDataStore(metadata: .bundledDefault)
        XCTAssertEqual(defaultStore.holidayCountries, [.sweden])

        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarHolidayCountries = []
        let emptyStore = GrantDataStore(metadata: metadata)

        XCTAssertEqual(emptyStore.holidayCountries, [])
    }

    @MainActor
    func testCalendarCountryDisplayModeDefaultsToFlagsAndReadsStoredChoice() {
        let defaultStore = GrantDataStore(metadata: .bundledDefault)
        XCTAssertEqual(defaultStore.calendarCountryDisplayMode, .flags)

        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarCountryDisplayMode = CalendarCountryDisplayMode.text.rawValue
        XCTAssertEqual(GrantDataStore(metadata: metadata).calendarCountryDisplayMode, .text)

        metadata.calendarCountryDisplayMode = CalendarCountryDisplayMode.hidden.rawValue
        XCTAssertEqual(GrantDataStore(metadata: metadata).calendarCountryDisplayMode, .hidden)
    }

    @MainActor
    func testFooterStatusBarDefaultsHiddenAndReadsStoredChoice() {
        let defaultStore = GrantDataStore(metadata: .bundledDefault)
        XCTAssertFalse(defaultStore.showsFooterStatusBar)

        var metadata = DataSourceMetadata.bundledDefault
        metadata.showsFooterStatusBar = true
        XCTAssertTrue(GrantDataStore(metadata: metadata).showsFooterStatusBar)

        metadata.showsFooterStatusBar = false
        XCTAssertFalse(GrantDataStore(metadata: metadata).showsFooterStatusBar)
    }

    @MainActor
    func testFooterStatusBarVisibilityStoresOnlyShownChoice() {
        let store = GrantDataStore(metadata: .bundledDefault)

        store.setFooterStatusBarVisible(true)
        XCTAssertTrue(store.showsFooterStatusBar)
        XCTAssertEqual(store.metadata.showsFooterStatusBar, true)

        store.setFooterStatusBarVisible(false)
        XCTAssertFalse(store.showsFooterStatusBar)
        XCTAssertNil(store.metadata.showsFooterStatusBar)
    }

    @MainActor
    func testCalendarHiddenColumnKeysDefaultEmptyAndNormalizeStoredValues() {
        let defaultStore = GrantDataStore(metadata: .bundledDefault)
        XCTAssertEqual(defaultStore.calendarHiddenColumnKeys, [])

        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarHiddenColumnKeys = ["date", " title ", "", "date", "year", "weekNumber"]

        XCTAssertEqual(GrantDataStore(metadata: metadata).calendarHiddenColumnKeys, Set(["date", "title", "weekNumber", "year"]))
        XCTAssertEqual(GrantDataStore.sanitizedMetadata(metadata).calendarHiddenColumnKeys, ["date", "title", "weekNumber", "year"])
    }

    @MainActor
    func testCalendarHiddenAutomaticEventKeysDefaultEmptyAndNormalizeStoredValues() {
        let defaultStore = GrantDataStore(metadata: .bundledDefault)
        XCTAssertEqual(defaultStore.calendarHiddenAutomaticEventKeys, [])

        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarHiddenAutomaticEventKeys = [" application-deadline:a ", "", "application-deadline:a", "congress-abstract-deadline:o:c"]

        XCTAssertEqual(defaultStore.isAutomaticCalendarEventHidden("application-deadline:a"), false)
        XCTAssertEqual(
            GrantDataStore(metadata: metadata).calendarHiddenAutomaticEventKeys,
            Set(["application-deadline:a", "congress-abstract-deadline:o:c"])
        )
        XCTAssertEqual(
            GrantDataStore.sanitizedMetadata(metadata).calendarHiddenAutomaticEventKeys,
            ["application-deadline:a", "congress-abstract-deadline:o:c"]
        )
    }

    func testMetadataTaskNormalizationPreservesDuplicateAndBlankIDRecords() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [
            TaskItem(id: "duplicate", createdOn: "2026-01-01", comment: "First"),
            TaskItem(id: "duplicate", createdOn: "2026-01-02", comment: "Second"),
            TaskItem(id: "  ", createdOn: "2026-01-03", comment: "Blank ID"),
            TaskItem(id: "empty", createdOn: "2026-01-04")
        ]

        let tasks = try XCTUnwrap(GrantDataStore.sanitizedMetadata(metadata).taskItems)

        XCTAssertEqual(tasks.map(\.comment), ["First", "Second", "Blank ID"])
        XCTAssertEqual(Set(tasks.map(\.id)).count, 3)
        XCTAssertEqual(tasks.first?.id, "duplicate")
        XCTAssertTrue(tasks.dropFirst().allSatisfy { $0.id.trimmedOrNil != nil && $0.id != "duplicate" })
    }

    @MainActor
    func testThrowingPersistenceClearsSavingStatus() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.projectTimelineYearColumnWidth = .nan
        let store = GrantDataStore(metadata: metadata, skipInitialMigration: true)

        XCTAssertThrowsError(try store.persist(.appSettings, includeBackup: false))
        XCTAssertFalse(store.persistenceStatus.isSaving)
        XCTAssertNil(store.persistenceStatus.lastSavedAt)
    }

    @MainActor
    func testCalendarColorLayoutOptionsDefaultFalseAndReadStoredChoices() {
        let defaultStore = GrantDataStore(metadata: .bundledDefault)
        XCTAssertFalse(defaultStore.calendarUsesCompactEventColorBands)
        XCTAssertFalse(defaultStore.calendarUsesCompactDayHighlightBands)

        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarUsesCompactEventColorBands = true
        metadata.calendarUsesCompactDayHighlightBands = true
        let store = GrantDataStore(metadata: metadata)

        XCTAssertTrue(store.calendarUsesCompactEventColorBands)
        XCTAssertTrue(store.calendarUsesCompactDayHighlightBands)
    }

    func testNavigationChromeColorsResolveExplicitLightAfterDark() {
        _ = AppPalette.chromeTopNSColor(for: .darkNew)

        let lightTop = AppPalette.chromeTopNSColor(for: .lightClean)
        let darkTop = AppPalette.chromeTopNSColor(for: .darkNew)

        XCTAssertGreaterThan(relativeLuminance(of: lightTop), 0.85)
        XCTAssertLessThan(relativeLuminance(of: darkTop), 0.25)
    }

    func testFormattedCalendarPlaceSupportsCountryDisplayModes() {
        XCTAssertEqual(
            formattedCalendarPlace(
                city: "Oslo",
                country: "Norway",
                language: .swedish,
                countryDisplayMode: .flags
            ),
            "Oslo 🇳🇴"
        )
        XCTAssertEqual(
            formattedCalendarPlace(
                city: "Oslo",
                country: "Norway",
                language: .swedish,
                countryDisplayMode: .text
            ),
            "Oslo, Norge"
        )
        XCTAssertEqual(
            formattedCalendarPlace(
                city: "Oslo",
                country: "Norway",
                language: .swedish,
                countryDisplayMode: .hidden
            ),
            "Oslo"
        )
        XCTAssertEqual(
            formattedCalendarPlace(
                city: "",
                country: "Norway",
                language: .swedish,
                countryDisplayMode: .hidden
            ),
            ""
        )
    }

    @MainActor
    func testPhysicalCalendarActivityDoesNotRepeatModeInDetails() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 21)))
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: "physical-activity",
                date: "2026-04-21",
                title: "Physical activity",
                meetingMode: CalendarMeetingMode.physical.rawValue,
                place: "Exempelköping",
                country: "Sweden",
                detail: "Agenda"
            )
        ]
        let store = GrantDataStore(metadata: metadata)

        let events = buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: date)),
            displayedMonthEnd: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: date)),
            calendar: calendar
        )

        let activity = try XCTUnwrap(events.first { $0.id == "meeting:physical-activity" })
        XCTAssertEqual(activity.detail, "Agenda")
        XCTAssertEqual(activity.place, "Exempelköping 🇸🇪")
    }

    func testEmptyMeetingCategoryDisplaysAsUncategorized() {
        XCTAssertEqual(calendarMeetingCategoryDisplayName("", language: .swedish), "Ej kategoriserad")
        XCTAssertEqual(calendarMeetingCategoryDisplayName("  ", language: .english), "Uncategorized")
        XCTAssertEqual(calendarMeetingCategoryDisplayName("Handledning", language: .swedish), "Handledning")
    }

    @MainActor
    func testCalendarDayHighlightColorsReadStoredLightAndDarkValues() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarDayHighlightColors = [
            CalendarDayHighlightColorSetting(
                id: CalendarDayHighlightColorSetting.id(for: .holiday),
                lightTextHexColor: "#112233",
                lightBackgroundHexColor: "#445566",
                darkTextHexColor: "#778899",
                darkBackgroundHexColor: "#AABBCC"
            ),
            CalendarDayHighlightColorSetting(
                id: CalendarDayHighlightColorSetting.id(for: .saturday),
                lightTextHexColor: "#123456",
                lightBackgroundHexColor: "#654321",
                darkTextHexColor: "#ABCDEF",
                darkBackgroundHexColor: "#FEDCBA"
            )
        ]

        let store = GrantDataStore(metadata: metadata)

        XCTAssertEqual(store.calendarDayHighlightTextHex(.holiday, usesDarkAppearance: false), "#112233")
        XCTAssertEqual(store.calendarDayHighlightBackgroundHex(.holiday, usesDarkAppearance: false), "#445566")
        XCTAssertEqual(store.calendarDayHighlightTextHex(.holiday, usesDarkAppearance: true), "#778899")
        XCTAssertEqual(store.calendarDayHighlightBackgroundHex(.holiday, usesDarkAppearance: true), "#AABBCC")
        XCTAssertEqual(store.calendarDayHighlightTextHex(.saturday, usesDarkAppearance: false), "#123456")
        XCTAssertEqual(store.calendarDayHighlightBackgroundHex(.saturday, usesDarkAppearance: true), "#FEDCBA")
        XCTAssertNil(store.calendarDayHighlightTextHex(.sunday, usesDarkAppearance: false))
    }

    @MainActor
    func testColorPresetAccessorsSynthesizeNamedCurrentDefaults() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarDayHighlightColors = [
            CalendarDayHighlightColorSetting(
                id: CalendarDayHighlightColorSetting.id(for: .holiday),
                lightTextHexColor: "#112233",
                lightBackgroundHexColor: "#445566",
                darkTextHexColor: "#778899",
                darkBackgroundHexColor: "#AABBCC"
            )
        ]
        metadata.calendarCategoryColors = [
            CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.fixedColorID(for: .travel),
                lightHexColor: "#AA5500",
                darkHexColor: "#0055AA"
            )
        ]
        metadata.calendarMeetingTypeOptions = ["Klinik"]
        metadata.appSemanticColorsLight = AppSemanticColorSettings(
            negative: .make("#101010", "#111111"),
            inProgress: .make("#222222", "#333333"),
            positive: .make("#444444", "#555555"),
            neutral: .make("#666666", "#777777")
        )
        metadata.appSemanticColorsDark = AppSemanticColorSettings(
            negative: .make("#888888", "#999999"),
            inProgress: .make("#AAAAAA", "#BBBBBB"),
            positive: .make("#CCCCCC", "#DDDDDD"),
            neutral: .make("#EEEEEE", "#FFFFFF")
        )
        metadata.appSemanticColorPresetsLight = [
            AppSemanticColorPreset(
                id: "builtin:pastel",
                name: "Egen pastell",
                colors: AppSemanticColorSettings(
                    negative: .make("#010101", "#020202"),
                    inProgress: .make("#030303", "#040404"),
                    positive: .make("#050505", "#060606"),
                    neutral: .make("#070707", "#080808")
                )
            ),
            AppSemanticColorPreset(
                id: "custom:legacy",
                name: "Gammal egen preset",
                colors: .default
            )
        ]
        metadata.appSemanticColorPresetsDark = [
            AppSemanticColorPreset(
                id: "default",
                name: "Egen standard",
                colors: AppSemanticColorSettings(
                    negative: .make("#111111", "#121212"),
                    inProgress: .make("#131313", "#141414"),
                    positive: .make("#151515", "#161616"),
                    neutral: .make("#171717", "#181818")
                )
            )
        ]

        let store = GrantDataStore(metadata: metadata)

        XCTAssertEqual(store.calendarDayHighlightColorPresets.first?.name, "Standard")
        XCTAssertEqual(
            store.calendarDayHighlightColorPresets.first?.settings.first(where: { $0.id == CalendarDayHighlightColorSetting.id(for: .holiday) })?.lightTextHexColor,
            "#112233"
        )
        XCTAssertEqual(store.calendarDayHighlightColorPresets.dropFirst().count, 3)
        XCTAssertTrue(store.calendarDayHighlightColorPresets.contains { $0.id == "builtin:pastel" && $0.name == "Pastell" })
        XCTAssertFalse(store.calendarDayHighlightColorPresets.contains { $0.id == "builtin:clear" })

        XCTAssertEqual(store.calendarCategoryColorPresets.map(\.id), ["default", "builtin:pastel", "builtin:calm", "builtin:contrast"])
        XCTAssertEqual(store.calendarCategoryColorPresets.first?.name, "Standard")
        XCTAssertEqual(
            store.calendarCategoryColorPresets.first?.settings.first(where: { $0.id == CalendarCategoryColorSetting.fixedColorID(for: .travel) })?.lightHexColor,
            "#B6D8A6"
        )
        XCTAssertEqual(
            store.calendarCategoryColorPresets.first?.settings.first(where: { $0.id == CalendarCategoryColorSetting.newActivityCategoryDefaultColorID })?.lightHexColor,
            "#A1D1E6"
        )
        XCTAssertEqual(
            store.calendarCategoryColorPresets.first?.settings.first(where: { $0.id == CalendarCategoryColorSetting.newActivityCategoryDefaultColorID })?.darkHexColor,
            "#124680"
        )
        XCTAssertNil(
            store.calendarCategoryColorPresets.first?.settings.first(where: { $0.id == CalendarCategoryColorSetting.meetingColorID(for: "Klinik") })
        )
        XCTAssertEqual(store.calendarCategoryColorPresets.count, 4)
        XCTAssertTrue(store.calendarCategoryColorPresets.contains { $0.id == "builtin:pastel" && $0.name == "Pastell" })

        XCTAssertEqual(store.appSemanticColorPresetsLight.map(\.id), ["default", "builtin:pastel", "builtin:calm", "builtin:contrast"])
        XCTAssertEqual(store.appSemanticColorPresetsLight.first?.name, "Standard")
        XCTAssertEqual(store.appSemanticColorPresetsLight.first?.colors.inProgress.solidHex, "#F1E08C")
        XCTAssertNil(store.appSemanticColorPresetsLight.first(where: { $0.id == "current" }))
        XCTAssertNil(store.appSemanticColorPresetsLight.first(where: { $0.id == "custom:legacy" }))
        XCTAssertEqual(store.appSemanticColorPresetsLight.first(where: { $0.id == "builtin:pastel" })?.colors.negative.solidHex, "#010101")
        XCTAssertEqual(store.appSemanticColorPresetsLight.count, 4)
        XCTAssertEqual(store.appSemanticColorPresetsDark.map(\.id), ["default", "builtin:pastel", "builtin:calm", "builtin:contrast"])
        XCTAssertEqual(store.appSemanticColorPresetsDark.first?.name, "Standard")
        XCTAssertEqual(store.appSemanticColorPresetsDark.first?.colors.neutral.shadeHex, "#181818")
        XCTAssertNil(store.appSemanticColorPresetsDark.first(where: { $0.id == "current" }))
        XCTAssertEqual(store.appSemanticColorPresetsDark.count, 4)
    }

    @MainActor
    func testAppChromeSchemeDefaultsToStandardAndReadsStoredValue() {
        var metadata = DataSourceMetadata.bundledDefault

        XCTAssertEqual(GrantDataStore(metadata: metadata).appChromeScheme, .standard)

        metadata.appChromeScheme = AppChromeScheme.contrast.rawValue

        XCTAssertEqual(GrantDataStore(metadata: metadata).appChromeScheme, .contrast)
    }

    func testUIDensityIsAlwaysComfortableAndIgnoresLegacyCompactDefault() {
        let legacyKey = AppRuntime.scopedDefaultsKey("UIDensity")
        UserDefaults.standard.set("compact", forKey: legacyKey)
        defer { UserDefaults.standard.removeObject(forKey: legacyKey) }

        XCTAssertEqual(AppUIDensity.allCases, [.comfortable])
        XCTAssertEqual(AppDensityRegistry.current(), .comfortable)
        XCTAssertEqual(AppDensityRegistry.current().scale, 1.0)
    }

    func testBuiltInLightChromeMenuColorsAreLight() {
        for scheme in AppChromeScheme.allCases {
            XCTAssertGreaterThan(
                relativeLuminance(of: scheme.builtInNSColor(for: .menu, useDarkAppearance: false)),
                0.85
            )
            XCTAssertLessThan(
                relativeLuminance(of: scheme.builtInNSColor(for: .menu, useDarkAppearance: true)),
                0.20
            )
        }
    }

    func testCalendarChromeSurfaceDefaultsToWorkspaceForLegacySettings() throws {
        let data = """
        {
            "menuHex": "#111111",
            "listHex": "#222222",
            "workspaceHex": "#333333"
        }
        """.data(using: .utf8)!

        var colors = try JSONDecoder().decode(AppChromeModeColorSettings.self, from: data)

        XCTAssertNil(colors.calendarHex)
        XCTAssertNil(colors.calendarFilterHex)
        XCTAssertNil(colors.calendarHeaderHex)
        XCTAssertNil(colors.calendarWorkspaceHex)
        XCTAssertNil(colors.calendarDayRowHex)
        XCTAssertEqual(colors.hex(for: .calendar), "#333333")
        XCTAssertEqual(colors.hex(for: .calendarFilter), "#222222")
        XCTAssertEqual(colors.hex(for: .calendarHeader), "#222222")
        XCTAssertEqual(colors.hex(for: .calendarWorkspace), "#333333")

        colors.setHex("#444444", for: .calendar)
        XCTAssertEqual(colors.hex(for: .calendar), "#444444")
        XCTAssertEqual(colors.hex(for: .workspace), "#333333")
        colors.setHex("#555555", for: .calendarFilter)
        colors.setHex("#666666", for: .calendarHeader)
        colors.setHex("#777777", for: .calendarWorkspace)
        colors.setHex("#888888", for: .calendarDayRow)
        XCTAssertEqual(colors.hex(for: .calendarFilter), "#555555")
        XCTAssertEqual(colors.hex(for: .calendarHeader), "#666666")
        XCTAssertEqual(colors.hex(for: .calendarWorkspace), "#777777")
        XCTAssertEqual(colors.hex(for: .calendarDayRow), "#888888")
    }

    func testChromeSurfaceOrderPlacesCalendarSurfacesAfterWorkspace() {
        XCTAssertEqual(
            AppChromeSurface.allCases,
            [.menu, .list, .workspace, .calendar, .calendarFilter, .calendarHeader, .calendarWorkspace, .calendarDayRow]
        )
    }

    func testAppAppearanceRegistryUsesCustomChromeSurfaceColors() throws {
        var metadata = DataSourceMetadata.bundledDefault
        var colors = AppChromeColorSettings.builtIn
        colors.standardLight = AppChromeModeColorSettings(
            menuHex: "#111111",
            listHex: "#223344",
            workspaceHex: "#556677",
            calendarHex: "#8899AA",
            calendarFilterHex: "#AABBCC",
            calendarHeaderHex: "#BBCCDD",
            calendarWorkspaceHex: "#CCDDEE",
            calendarDayRowHex: "#DDEEFF"
        )
        metadata.appChromeColors = colors

        AppAppearanceRegistry.update(from: metadata)
        defer { AppAppearanceRegistry.update(from: DataSourceMetadata.bundledDefault) }

        func assertColor(_ surface: AppChromeSurface, red: CGFloat, green: CGFloat, blue: CGFloat) throws {
            let expected = try XCTUnwrap(
                NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
                    .usingColorSpace(.deviceRGB)
            )
            let actual = try XCTUnwrap(
                AppAppearanceRegistry.chromeColor(for: .standard, surface: surface, useDarkAppearance: false)
                    .usingColorSpace(.deviceRGB)
            )
            XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.001)
            XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.001)
            XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.001)
        }

        try assertColor(.list, red: 0x22, green: 0x33, blue: 0x44)
        try assertColor(.workspace, red: 0x55, green: 0x66, blue: 0x77)
        try assertColor(.calendar, red: 0x88, green: 0x99, blue: 0xAA)
        try assertColor(.calendarFilter, red: 0xAA, green: 0xBB, blue: 0xCC)
        try assertColor(.calendarHeader, red: 0xBB, green: 0xCC, blue: 0xDD)
        try assertColor(.calendarWorkspace, red: 0xCC, green: 0xDD, blue: 0xEE)
        try assertColor(.calendarDayRow, red: 0xDD, green: 0xEE, blue: 0xFF)
    }

    func testLegacyDarkLightChromeMenuDefaultsMigrateToCurrentLightDefaults() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.appChromeScheme = AppChromeScheme.contrast.rawValue
        metadata.appChromeColors = .legacyDarkLightMenuBuiltIn

        let sanitized = GrantDataStore.sanitizedMetadata(metadata)

        XCTAssertNil(sanitized.appChromeColors)
        XCTAssertEqual(sanitized.appChromeScheme, AppChromeScheme.contrast.rawValue)
    }

    @MainActor
    func testCalendarClinicCategoryColorFallsBackAcrossClinicAliases() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarCategoryColors = [
            CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.meetingColorID(for: "Klinik"),
                lightHexColor: "#D97706",
                darkHexColor: "#F59E0B"
            )
        ]

        let store = GrantDataStore(metadata: metadata)

        XCTAssertEqual(store.calendarMeetingCategoryColorHex(named: "Klinik", usesDarkAppearance: false), "#D97706")
        XCTAssertEqual(store.calendarMeetingCategoryColorHex(named: "Clinic", usesDarkAppearance: false), "#D97706")
        XCTAssertEqual(store.calendarMeetingCategoryColorHex(named: "Clinic", usesDarkAppearance: true), "#F59E0B")
    }

    @MainActor
    func testCalendarMeetingCategoriesUseStoredDefaultColorWhenNoCategoryOverrideExists() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarCategoryColors = [
            CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.newActivityCategoryDefaultColorID,
                lightHexColor: "#112233",
                darkHexColor: "#445566"
            )
        ]

        let store = GrantDataStore(metadata: metadata)

        XCTAssertEqual(store.calendarNewActivityCategoryDefaultColorHex(usesDarkAppearance: false), "#112233")
        XCTAssertEqual(store.calendarNewActivityCategoryDefaultColorHex(usesDarkAppearance: true), "#445566")
        XCTAssertEqual(store.calendarMeetingCategoryColorHex(named: "Seminarium", usesDarkAppearance: false), "#112233")
        XCTAssertEqual(store.calendarMeetingCategoryColorHex(named: "Seminarium", usesDarkAppearance: true), "#445566")
    }

    func testCalendarDayHighlightColorSettingsNormalizationDeduplicatesByID() {
        let normalized = GrantDataStore.normalizedCalendarDayHighlightColorSettings([
            CalendarDayHighlightColorSetting(
                id: " holiday ",
                lightTextHexColor: "abcdef",
                lightBackgroundHexColor: "112233",
                darkTextHexColor: "445566",
                darkBackgroundHexColor: "778899"
            ),
            CalendarDayHighlightColorSetting(
                id: CalendarDayHighlightColorSetting.id(for: .holiday),
                lightTextHexColor: "#123456",
                lightBackgroundHexColor: "#654321",
                darkTextHexColor: "#ABCDEF",
                darkBackgroundHexColor: "#FEDCBA"
            ),
            CalendarDayHighlightColorSetting(
                id: " ",
                lightTextHexColor: "#000000",
                lightBackgroundHexColor: "#000000",
                darkTextHexColor: "#000000",
                darkBackgroundHexColor: "#000000"
            )
        ])

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized.first?.id, CalendarDayHighlightColorSetting.id(for: .holiday))
        XCTAssertEqual(normalized.first?.lightTextHexColor, "#ABCDEF")
        XCTAssertEqual(normalized.first?.lightBackgroundHexColor, "#112233")
        XCTAssertEqual(normalized.first?.darkTextHexColor, "#445566")
        XCTAssertEqual(normalized.first?.darkBackgroundHexColor, "#778899")
    }

    @MainActor
    func testCalendarEventsExcludeAlreadyAppliedGrantDeadlines() throws {
        let toApply = GrantApplication(
            id: "app-open",
            rowNumber: 1,
            organization: "Org A",
            grantName: "Open grant",
            closesOn: "2026-05-10"
        )
        let applied = GrantApplication(
            id: "app-applied",
            rowNumber: 2,
            organization: "Org B",
            grantName: "Applied grant",
            closesOn: "2026-05-11",
            appliedOn: "2026-04-01",
            result: "Väntar svar"
        )
        let store = GrantDataStore(applications: [toApply, applied])
        try store.persist(.allCoreData, includeBackup: false)
        let calendar = footprintCalendar(for: .swedish)
        let monthStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let monthEnd = try XCTUnwrap(calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart))

        let events = buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: monthStart,
            displayedMonthEnd: monthEnd,
            calendar: calendar
        )

        XCTAssertTrue(events.contains { $0.title == "Open grant" && $0.kind == .applicationDeadline })
        XCTAssertFalse(events.contains { $0.title == "Applied grant" && $0.kind == .applicationDeadline })
    }

    @MainActor
    func testVacationCalendarMeetingsDoNotShowActivityFallbackOrDashTitle() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: "vacation-empty",
                date: "2026-07-01",
                title: "",
                meetingType: "Semester"
            ),
            CalendarMeetingRecord(
                id: "vacation-dash",
                date: "2026-07-02",
                title: "-",
                meetingType: "Semester"
            )
        ]
        let store = GrantDataStore(metadata: metadata)
        let calendar = footprintCalendar(for: .swedish)
        let monthStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let monthEnd = try XCTUnwrap(calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart))

        let events = buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: monthStart,
            displayedMonthEnd: monthEnd,
            calendar: calendar
        )

        let emptyTitleEvent = try XCTUnwrap(events.first { $0.id == "meeting:vacation-empty" })
        let dashTitleEvent = try XCTUnwrap(events.first { $0.id == "meeting:vacation-dash" })
        XCTAssertEqual(emptyTitleEvent.title, "")
        XCTAssertEqual(dashTitleEvent.title, "")
    }

    func testCalendarUsesConfiguredFirstWeekday() {
        let swedishMonday = footprintCalendar(for: .swedish, weekStart: .monday)
        let swedishSunday = footprintCalendar(for: .swedish, weekStart: .sunday)

        XCTAssertEqual(swedishMonday.firstWeekday, 2)
        XCTAssertEqual(swedishSunday.firstWeekday, 1)
    }

    @MainActor
    func testIncompleteCalendarTasksRollForwardInContinuousList() throws {
        let calendar = footprintCalendar(for: .swedish, weekStart: .monday)
        let today = calendar.startOfDay(for: Date())
        let overdueDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today))
        let rangeEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 30, to: today))

        let task = PublicationTaskItem(
            createdOn: DateParsers.isoDay.string(from: overdueDate),
            updatedOn: DateParsers.isoDay.string(from: overdueDate),
            deadline: DateParsers.isoDay.string(from: overdueDate),
            comment: "Rolled task"
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.teachingWorkspaceTasks = [task]
        let store = GrantDataStore(metadata: metadata)

        let events = buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: today,
            displayedMonthEnd: rangeEnd,
            calendar: calendar,
            taskDisplayPolicy: .rollOverPastDue
        )

        let rolledTask = try XCTUnwrap(events.first { $0.title == "Rolled task" })
        XCTAssertEqual(calendar.startOfDay(for: rolledTask.displayDate), today)
        XCTAssertTrue(rolledTask.isRolledOverPastDue)
    }

    @MainActor
    func testCalendarIncludesOrganizationTaskDeadlines() throws {
        let calendar = footprintCalendar(for: .swedish, weekStart: .monday)
        let deadline = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)))
        let organization = OrganizationRecord(
            id: "organization-calendar-task",
            nameSv: "Organisation",
            nameEn: "Organization",
            city: "Exempelköping",
            country: "Sverige",
            projectTasks: [
                ProjectTaskItem(
                    id: "organization-task-1",
                    deadline: "2026-09-14",
                    comment: "Organisationsuppgift"
                )
            ]
        )
        let store = GrantDataStore(organizations: [organization])
        try store.persist(.allCoreData, includeBackup: false)

        let events = buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: deadline)),
            displayedMonthEnd: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: deadline)),
            calendar: calendar
        )

        let event = try XCTUnwrap(events.first { $0.id == "organization-task:organization-calendar-task:organization-task-1" })
        XCTAssertEqual(event.title, "Organisationsuppgift")
        XCTAssertEqual(event.subtitle, "Organisation")
        XCTAssertEqual(calendar.startOfDay(for: event.displayDate), calendar.startOfDay(for: deadline))
        if case let .organizationTask(organizationID, taskID) = event.source {
            XCTAssertEqual(organizationID, "organization-calendar-task")
            XCTAssertEqual(taskID, "organization-task-1")
        } else {
            XCTFail("Expected organization task source")
        }
    }

    @MainActor
    func testCompletedCalendarTasksUseCompletionDateInContinuousList() throws {
        let calendar = footprintCalendar(for: .swedish, weekStart: .monday)
        let today = calendar.startOfDay(for: Date())
        let overdueDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today))
        let completedDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let rangeEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 30, to: today))

        let task = PublicationTaskItem(
            createdOn: DateParsers.isoDay.string(from: overdueDate),
            updatedOn: DateParsers.isoDay.string(from: completedDate),
            deadline: DateParsers.isoDay.string(from: overdueDate),
            comment: "Completed rolled task",
            completedOn: DateParsers.isoDay.string(from: completedDate)
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.teachingWorkspaceTasks = [task]
        let store = GrantDataStore(metadata: metadata)

        let events = buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: overdueDate,
            displayedMonthEnd: rangeEnd,
            calendar: calendar,
            taskDisplayPolicy: .rollOverPastDue
        )

        let completedTask = try XCTUnwrap(events.first { $0.title == "Completed rolled task" })
        XCTAssertEqual(calendar.startOfDay(for: completedTask.displayDate), completedDate)
        XCTAssertFalse(completedTask.isRolledOverPastDue)
    }

    func testStatisticsTeachingYearSliderDefaultsToCurrentYearAndExtendsToDataMax() {
        let dataYears: Set<Int> = [2024, 2026, 2034]

        XCTAssertEqual(
            statisticsTeachingYearSliderRange(currentYear: 2026, dataYears: dataYears),
            2025...2034
        )
        XCTAssertEqual(
            statisticsTeachingVisibleThroughYear(currentYear: 2026, dataYears: dataYears, selectedYear: nil),
            2026
        )
        XCTAssertEqual(
            statisticsTeachingVisibleThroughYear(currentYear: 2026, dataYears: dataYears, selectedYear: 2024),
            2025
        )
        XCTAssertEqual(
            statisticsTeachingVisibleThroughYear(currentYear: 2026, dataYears: dataYears, selectedYear: 2040),
            2034
        )
    }

    func testStatisticsTeachingVisibleYearsStopsAtSelectedUpperYear() {
        XCTAssertEqual(
            statisticsTeachingVisibleYears(from: [2024, 2026, 2034], through: 2026),
            ["2024", "2025", "2026"]
        )
        XCTAssertEqual(
            statisticsTeachingVisibleYears(from: [2024, 2026, 2034], through: 2034),
            (2024...2034).map(String.init)
        )
        XCTAssertEqual(
            statisticsTeachingVisibleYears(from: [2034], through: 2026),
            []
        )
    }

    func testStatisticsLinkedProjectHoursExcludeUnlinkedActivities() {
        let hours = statisticsLinkedProjectHoursByYear(
            [
                2025: ["Project A": 12, "Project B": 8, "Ej kopplat till projekt": 20],
                2026: ["Project A": 6, "Ej kopplat till projekt": 4]
            ],
            excludingUnlinkedKey: "Ej kopplat till projekt"
        )

        XCTAssertEqual(hours[2025], 20)
        XCTAssertEqual(hours[2026], 6)
    }

    func testJournalStatisticsRankingSeriesCombinesClarivateKindsAndKeepsAnnualValues() throws {
        let journal = PublicationJournal(
            name: "Test Journal",
            rankingRows: [
                JournalRankingRow(
                    kind: .clarivateScieJIF,
                    yearlyMetrics: [
                        JournalYearMetric(year: 2024, value: "5.2", quartile: "Q1"),
                        JournalYearMetric(year: 2023, value: "4,8", quartile: "Q1"),
                    ]
                ),
                JournalRankingRow(
                    kind: .clarivateScieJCI,
                    yearlyMetrics: [
                        JournalYearMetric(year: 2024, value: "1.4", quartile: "Q1"),
                    ]
                ),
                JournalRankingRow(
                    kind: .scimagoSJR,
                    yearlyMetrics: [
                        JournalYearMetric(year: 2024, value: "2.1", quartile: "Q1"),
                    ]
                ),
                JournalRankingRow(
                    kind: .norwegianList,
                    yearlyMetrics: [
                        JournalYearMetric(year: 2024, value: "2", quartile: ""),
                        JournalYearMetric(year: 2023, value: "1", quartile: ""),
                    ]
                ),
            ]
        )

        let series = publicationJournalRankingSeries(for: journal)
        let jif = try XCTUnwrap(series.first { $0.metric == .jif })
        let jci = try XCTUnwrap(series.first { $0.metric == .jci })
        let sjr = try XCTUnwrap(series.first { $0.metric == .sjr })
        let norwegian = try XCTUnwrap(series.first { $0.metric == .norwegian })

        XCTAssertEqual(jif.points, [
            PublicationJournalRankingPoint(year: 2023, value: 4.8),
            PublicationJournalRankingPoint(year: 2024, value: 5.2),
        ])
        XCTAssertEqual(jci.points, [PublicationJournalRankingPoint(year: 2024, value: 1.4)])
        XCTAssertEqual(sjr.points, [PublicationJournalRankingPoint(year: 2024, value: 2.1)])
        XCTAssertEqual(norwegian.points, [
            PublicationJournalRankingPoint(year: 2023, value: 1),
            PublicationJournalRankingPoint(year: 2024, value: 2),
        ])
    }

    func testDoctoralStatisticsSeparatesCompletedAndPlannedCreditsAndSupervisionHours() throws {
        let candidate = DoctoralCandidateRecord(
            admissionDate: "2025-01-01",
            plannedDisputationDate: "2027-12-31",
            courses: [
                DoctoralCandidateCourse(year: "2025", title: "Completed", credits: "7,5", completedOn: "2025-06-01"),
                DoctoralCandidateCourse(year: "2026", title: "Planned", credits: "3", completedOn: nil),
            ],
            supervisionPeriods: [
                DoctoralSupervisionPeriod(
                    from: "2025-01-01",
                    to: "2027-12-31",
                    hoursPerSemester: "10"
                )
            ]
        )
        let referenceDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-07-27"))

        let rows = doctoralStatisticsYearRows(
            candidate: candidate,
            publications: [],
            journalForPublication: { _ in nil },
            referenceDate: referenceDate
        )

        let year2025 = try XCTUnwrap(rows.first { $0.year == 2025 })
        XCTAssertEqual(year2025.completedCourseCredits, 7.5)
        XCTAssertEqual(year2025.plannedCourseCredits, 0)
        XCTAssertEqual(year2025.completedSupervisionHours, 20)
        XCTAssertEqual(year2025.plannedSupervisionHours, 0)

        let year2026 = try XCTUnwrap(rows.first { $0.year == 2026 })
        XCTAssertEqual(year2026.completedCourseCredits, 0)
        XCTAssertEqual(year2026.plannedCourseCredits, 3)
        XCTAssertEqual(year2026.completedSupervisionHours, 10)
        XCTAssertEqual(year2026.plannedSupervisionHours, 10)

        let year2027 = try XCTUnwrap(rows.first { $0.year == 2027 })
        XCTAssertEqual(year2027.completedSupervisionHours, 0)
        XCTAssertEqual(year2027.plannedSupervisionHours, 20)
    }

    func testCalendarTaskIsRolledOverPastDueOnlyForIncompletePastDeadlines() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 22)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        XCTAssertTrue(
            calendarTaskIsRolledOverPastDue(
                deadline: yesterday,
                displayDate: today,
                isCompleted: false,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            )
        )
        XCTAssertFalse(
            calendarTaskIsRolledOverPastDue(
                deadline: yesterday,
                displayDate: yesterday,
                isCompleted: false,
                today: today,
                calendar: calendar,
                policy: .scheduled
            )
        )
        XCTAssertFalse(
            calendarTaskIsRolledOverPastDue(
                deadline: tomorrow,
                displayDate: tomorrow,
                isCompleted: false,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            )
        )
        XCTAssertFalse(
            calendarTaskIsRolledOverPastDue(
                deadline: yesterday,
                displayDate: today,
                isCompleted: true,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            )
        )
    }

    @MainActor
    func testCalendarTaskReminderEntriesIncludeOnlyUnresolvedVisibleTasks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let todayString = DateParsers.isoDay.string(from: today)
        let yesterdayString = DateParsers.isoDay.string(from: yesterday)
        let tomorrowString = DateParsers.isoDay.string(from: tomorrow)

        let project = ProjectRecord(
            id: "project-1",
            nameSv: "Projekt",
            nameEn: "Project",
            projectTasks: [
                ProjectTaskItem(deadline: todayString, comment: "Today project task"),
                ProjectTaskItem(deadline: yesterdayString, comment: "Rolled project task"),
                ProjectTaskItem(deadline: todayString, comment: "Completed project task", completedOn: todayString),
                ProjectTaskItem(deadline: tomorrowString, comment: "Future project task"),
            ]
        )
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Publication",
            publicationTasks: [
                PublicationTaskItem(deadline: todayString, comment: "Today publication task")
            ]
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [
            TaskItem(id: "central-task-1", deadline: yesterdayString, comment: "Rolled central task")
        ]
        metadata.teachingWorkspaceTasks = [
            PublicationTaskItem(deadline: todayString, comment: "Today general task")
        ]
        let store = GrantDataStore(metadata: metadata, projects: [project], publicationRecords: [publication])
        try store.persist(.allCoreData, includeBackup: false)

        let entries = calendarTaskReminderEntries(
            store: store,
            language: .swedish,
            calendar: calendar,
            today: today,
            through: today
        )

        XCTAssertEqual(entries.map(\.title), [
            "Rolled central task",
            "Rolled project task",
            "Today general task",
            "Today project task",
            "Today publication task",
        ])
        XCTAssertTrue(entries.allSatisfy { calendar.isDate($0.displayDate, inSameDayAs: today) })
    }

    @MainActor
    func testCalendarTaskReminderPlansFireAtNoon() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 8)))
        let todayString = "2026-04-20"
        var metadata = DataSourceMetadata.bundledDefault
        metadata.teachingWorkspaceTasks = [
            PublicationTaskItem(deadline: todayString, comment: "Noon task")
        ]
        let store = GrantDataStore(metadata: metadata)

        let plan = try XCTUnwrap(calendarTaskReminderPlans(
            store: store,
            language: .swedish,
            calendar: calendar,
            now: today
        ).first)
        let components = calendar.dateComponents([.hour, .minute], from: plan.fireDate)

        XCTAssertEqual(plan.id, "calendar-task-reminder-2026-04-20")
        XCTAssertEqual(plan.title, "Olöst uppgift idag")
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 0)
    }

    @MainActor
    func testCalendarTaskDockBadgeEntriesRemainVisibleAllDayWithNavigationSource() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20)))
        let beforeBadge = try XCTUnwrap(calendar.date(bySettingHour: 17, minute: 59, second: 0, of: day))
        let atBadge = try XCTUnwrap(calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day))
        let task = ProjectTaskItem(id: "task-1", deadline: "2026-04-20", comment: "Follow up")
        let project = ProjectRecord(
            id: "project-1",
            nameSv: "Projekt Alfa",
            nameEn: "Project Alpha",
            projectTasks: [task]
        )
        let store = GrantDataStore(projects: [project])

        let entriesBeforeEvening = calendarTaskDockBadgeEntries(
            store: store,
            language: .swedish,
            calendar: calendar,
            now: beforeBadge
        )
        XCTAssertEqual(entriesBeforeEvening.map(\.title), ["Follow up"])

        let entries = calendarTaskDockBadgeEntries(
            store: store,
            language: .swedish,
            calendar: calendar,
            now: atBadge
        )

        XCTAssertEqual(entries.map(\.title), ["Follow up"])
        XCTAssertEqual(entries.map(\.context), ["Projekt Alfa"])
        XCTAssertEqual(entries.first?.source, .projectTask(projectID: "project-1", taskID: "task-1"))
    }

    @MainActor
    func testCalendarTodoReminderPreservesLinkedWorkspaceDestinations() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 18)))
        let projectID = "00000000-0000-4000-8000-000000000021"
        let publicationID = "00000000-0000-4000-8000-000000000022"
        let applicationID = "00000000-0000-4000-8000-000000000023"
        var metadata = DataSourceMetadata.bundledDefault
        metadata.teachingWorkspaceTasks = [
            PublicationTaskItem(
                id: "todo-1",
                deadline: "2026-04-20",
                comment: "Linked task",
                projectID: projectID,
                publicationID: publicationID,
                applicationID: applicationID
            )
        ]
        let store = GrantDataStore(
            applications: [GrantApplication(id: applicationID, rowNumber: 1, organization: "Funder", grantName: "Grant")],
            metadata: metadata,
            projects: [ProjectRecord(id: projectID, nameSv: "Projekt", nameEn: "Project")],
            publicationRecords: [PublicationRecord(id: publicationID, title: "Publication")]
        )
        try store.persist(.allCoreData, includeBackup: false)

        let entry = try XCTUnwrap(calendarTaskDockBadgeEntries(
            store: store,
            language: .swedish,
            calendar: calendar,
            now: now
        ).first)

        XCTAssertTrue(entry.badgeTargets.contains(.project(projectID)))
        XCTAssertTrue(entry.badgeTargets.contains(.publication(publicationID)))
        XCTAssertTrue(entry.badgeTargets.contains(.application(applicationID)))
    }

    @MainActor
    func testCentralTaskReminderPreservesEverySupportedWorkspaceDestination() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 18)))
        let projectID = "project-1"
        let organizationID = "organization-1"
        let publicationID = "publication-1"
        let applicationID = "application-1"
        let assignmentID = "assignment-1"
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [
            TaskItem(
                id: "central-task-1",
                deadline: "2026-04-20",
                comment: "Linked central task",
                links: [
                    TaskLink(kind: .project, targetID: projectID),
                    TaskLink(kind: .organization, targetID: organizationID),
                    TaskLink(kind: .publication, targetID: publicationID),
                    TaskLink(kind: .application, targetID: applicationID),
                    TaskLink(kind: .teachingAssignment, targetID: assignmentID),
                ]
            )
        ]
        let store = GrantDataStore(
            applications: [GrantApplication(id: applicationID, rowNumber: 1, organization: "Funder", grantName: "Grant")],
            metadata: metadata,
            organizations: [OrganizationRecord(id: organizationID, nameSv: "Organisation", nameEn: "Organization")],
            projects: [ProjectRecord(id: projectID, nameSv: "Projekt", nameEn: "Project")],
            teachingAssignments: [TeachingAssignment(id: assignmentID, activityName: "Seminar")],
            publicationRecords: [PublicationRecord(id: publicationID, title: "Publication")],
            skipInitialMigration: true
        )
        try store.persist(.allCoreData, includeBackup: false)

        let entry = try XCTUnwrap(calendarTaskDockBadgeEntries(
            store: store,
            language: .swedish,
            calendar: calendar,
            now: now
        ).first)

        XCTAssertEqual(
            entry.badgeTargets,
            [
                .project(projectID),
                .organization(organizationID),
                .publication(publicationID),
                .application(applicationID),
                .teachingAssignment(assignmentID),
            ]
        )
    }

    @MainActor
    func testTeachingAssignmentTaskRoutesUpToTeachingWorkspace() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 18)))
        let task = PublicationTaskItem(id: "task-1", deadline: "2026-04-20", comment: "Prepare seminar")
        let assignment = TeachingAssignment(
            id: "assignment-1",
            activityName: "Seminar",
            tasks: [task]
        )
        let store = GrantDataStore(teachingAssignments: [assignment])

        let entries = calendarTaskDockBadgeEntries(
            store: store,
            language: .swedish,
            calendar: calendar,
            now: now
        )
        let entry = try XCTUnwrap(entries.first)
        let counts = calendarTaskReminderBadgeCounts(entries: entries)

        XCTAssertEqual(entry.id, calendarTeachingAssignmentTaskReminderID(assignmentID: "assignment-1", taskID: "task-1"))
        XCTAssertNil(entry.source)
        XCTAssertEqual(entry.badgeTargets, [.teachingAssignment("assignment-1")])
        XCTAssertEqual(counts.calendarBadgeCount, 0)
        XCTAssertEqual(counts.teachingAssignmentCounts, ["assignment-1": 1])
        XCTAssertEqual(counts.teachingBadgeCount, 1)
    }

    @MainActor
    func testReminderBadgeRouterRejectsStaleLinkedRecordIDs() {
        let router = CalendarTaskReminderBadgeRouter(store: GrantDataStore())

        XCTAssertTrue(router.targets(
            linkedProjectID: "missing-project",
            linkedPublicationID: "missing-publication",
            linkedApplicationID: "missing-application"
        ).isEmpty)
    }

    func testCalendarTaskReminderBadgeCountsRouteOnlySourcesWithWorkspaceRows() {
        let entries = [
            CalendarTaskReminderEntry(
                id: "project-1-task-1",
                source: .projectTask(projectID: "project-1", taskID: "task-1"),
                displayDate: Date(timeIntervalSince1970: 0),
                title: "P1",
                context: "Project",
                badgeTargets: [.project("project-1")]
            ),
            CalendarTaskReminderEntry(
                id: "project-1-task-2",
                source: .projectTask(projectID: "project-1", taskID: "task-2"),
                displayDate: Date(timeIntervalSince1970: 0),
                title: "P2",
                context: "Project",
                badgeTargets: [.project("project-1")]
            ),
            CalendarTaskReminderEntry(
                id: "organization-1-task-1",
                source: .organizationTask(organizationID: "organization-1", taskID: "task-1"),
                displayDate: Date(timeIntervalSince1970: 0),
                title: "O1",
                context: "Organization",
                badgeTargets: [.organization("organization-1")]
            ),
            CalendarTaskReminderEntry(
                id: "publication-1-task-1",
                source: .publicationTask(publicationID: "publication-1", taskID: "task-1"),
                displayDate: Date(timeIntervalSince1970: 0),
                title: "U1",
                context: "Publication",
                badgeTargets: [.publication("publication-1")]
            ),
            CalendarTaskReminderEntry(
                id: "teaching-task-1",
                source: .teachingTask(taskID: "task-1"),
                displayDate: Date(timeIntervalSince1970: 0),
                title: "T1",
                context: "Calendar",
                badgeTargets: [.project("project-2"), .publication("publication-2"), .application("application-1")]
            ),
            CalendarTaskReminderEntry(
                id: "teaching-assignment-task:assignment-1:task-1",
                displayDate: Date(timeIntervalSince1970: 0),
                title: "Teaching task",
                context: "Teaching assignment",
                badgeTargets: [.teachingAssignment("assignment-1")]
            ),
        ]

        let counts = calendarTaskReminderBadgeCounts(entries: entries)

        XCTAssertEqual(counts.totalCount, 6)
        XCTAssertEqual(counts.calendarBadgeCount, 5)
        XCTAssertEqual(counts.projectCounts, ["project-1": 2, "project-2": 1])
        XCTAssertEqual(counts.organizationCounts, ["organization-1": 1])
        XCTAssertEqual(counts.publicationCounts, ["publication-1": 1, "publication-2": 1])
        XCTAssertEqual(counts.applicationCounts, ["application-1": 1])
        XCTAssertEqual(counts.teachingAssignmentCounts, ["assignment-1": 1])
        XCTAssertEqual(counts.projectBadgeCount, 2)
        XCTAssertEqual(counts.organizationBadgeCount, 1)
        XCTAssertEqual(counts.publicationBadgeCount, 2)
        XCTAssertEqual(counts.applicationBadgeCount, 1)
        XCTAssertEqual(counts.teachingBadgeCount, 1)
        XCTAssertTrue(counts.contains(source: .projectTask(projectID: "project-1", taskID: "task-2")))
    }

    func testCalendarTaskActiveBadgeRemainsVisibleUntilCompletion() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20)))
        let beforeBadge = try XCTUnwrap(calendar.date(bySettingHour: 17, minute: 59, second: 0, of: day))
        let atBadge = try XCTUnwrap(calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day))

        XCTAssertTrue(calendarTaskShowsActiveBadge(
            deadline: "2026-04-19",
            title: "Past task",
            isCompleted: false,
            calendar: calendar,
            now: beforeBadge
        ))
        XCTAssertTrue(calendarTaskShowsActiveBadge(
            deadline: "2026-04-19",
            title: "Past task",
            isCompleted: false,
            calendar: calendar,
            now: atBadge
        ))
        XCTAssertFalse(calendarTaskShowsActiveBadge(
            deadline: "2026-04-20",
            title: "Completed task",
            isCompleted: true,
            calendar: calendar,
            now: atBadge
        ))
        XCTAssertFalse(calendarTaskShowsActiveBadge(
            deadline: "2026-04-19",
            title: "Hidden task",
            isCompleted: false,
            isBadgeHidden: true,
            calendar: calendar,
            now: atBadge
        ))
    }

    @MainActor
    func testCalendarTaskDockBadgeIsRemovedWhenAnOverdueTaskMovesToTheFuture() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let now = try XCTUnwrap(calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        var project = ProjectRecord(
            id: "project-1",
            nameSv: "Projekt Alfa",
            nameEn: "Project Alpha",
            projectTasks: [ProjectTaskItem(
                id: "task-1",
                deadline: DateParsers.isoDay.string(from: yesterday),
                comment: "Follow up"
            )]
        )
        let store = GrantDataStore(projects: [project])

        XCTAssertEqual(calendarTaskDockBadgeEntries(
            store: store,
            language: .swedish,
            calendar: calendar,
            now: now
        ).map(\.id), ["project-task:project-1:task-1"])

        project.projectTasks[0].deadline = DateParsers.isoDay.string(from: tomorrow)
        store.autosaveProjectRecord(project, previousID: project.id)

        XCTAssertTrue(calendarTaskDockBadgeEntries(
            store: store,
            language: .swedish,
            calendar: calendar,
            now: now
        ).isEmpty)
    }

    @MainActor
    func testCalendarShowsCongressOnEveryCongressDayAndBothAbstractDeadlines() throws {
        let calendar = footprintCalendar(for: .swedish, weekStart: .monday)
        let today = calendar.startOfDay(for: Date())
        let abstractDeadline = calendar.date(byAdding: .day, value: 3, to: today) ?? today
        let lateDeadline = calendar.date(byAdding: .day, value: 5, to: today) ?? today
        let congressStart = calendar.date(byAdding: .day, value: 10, to: today) ?? today
        let congressMiddle = calendar.date(byAdding: .day, value: 11, to: today) ?? today
        let congressEnd = calendar.date(byAdding: .day, value: 12, to: today) ?? today
        let congress = OrganizationCongress(
            title: "Nordic Congress",
            from: DateParsers.isoDay.string(from: congressStart),
            fromUncertain: true,
            to: DateParsers.isoDay.string(from: congressEnd),
            abstractSubmissionDeadline: DateParsers.isoDay.string(from: abstractDeadline),
            abstractSubmissionDeadlineUncertain: true,
            lateAbstractSubmissionDeadline: DateParsers.isoDay.string(from: lateDeadline),
            city: "Oslo",
            country: "NO"
        )
        let organization = OrganizationRecord(
            id: "org-1",
            nameSv: "Nordisk organisation",
            nameEn: "Nordic organization",
            congresses: [congress]
        )
        let store = GrantDataStore(organizations: [organization])
        try store.persist(.allCoreData, includeBackup: false)
        let rangeStart = today
        let rangeEnd = calendar.date(byAdding: .day, value: 20, to: today) ?? today

        let events = buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: calendar.startOfDay(for: rangeStart),
            displayedMonthEnd: calendar.startOfDay(for: rangeEnd),
            calendar: calendar,
            taskDisplayPolicy: .rollOverPastDue
        )

        let congressRows = events.filter { event in
            event.title == "Nordic Congress"
                && event.subtitle == "Oslo 🇳🇴"
                && event.detail.isEmpty
        }
        let congressDays = congressRows.map { event in
            DateParsers.isoDay.string(from: calendar.startOfDay(for: event.displayDate))
        }
        XCTAssertEqual(congressDays, [
            DateParsers.isoDay.string(from: congressStart),
            DateParsers.isoDay.string(from: congressMiddle),
            DateParsers.isoDay.string(from: congressEnd)
        ])
        XCTAssertTrue(congressRows.allSatisfy { $0.isDateUncertain })

        let deadlineDateRange = publicationAuthorLinkedDateRangeText(
            from: DateParsers.isoDay.string(from: congressStart),
            to: DateParsers.isoDay.string(from: congressEnd),
            language: .swedish,
            emptyText: ""
        )
        let deadlineTitle = "Nordic Congress (\(deadlineDateRange))"
        let deadlineRows = events.filter { event in
            event.title == deadlineTitle && !event.detail.isEmpty
        }
        let deadlineLabels = deadlineRows.map { $0.detail }
        XCTAssertTrue(deadlineLabels.contains("Abstractfrist (osäkert datum)"))
        XCTAssertTrue(deadlineLabels.contains("Sen abstractfrist"))
        XCTAssertTrue(deadlineRows.contains { $0.detail == "Abstractfrist (osäkert datum)" && $0.isDateUncertain })
        XCTAssertTrue(deadlineRows.contains { $0.detail == "Sen abstractfrist" && !$0.isDateUncertain })
        XCTAssertTrue(deadlineRows.allSatisfy { $0.kind == .applicationDeadline })
        XCTAssertTrue(congressRows.allSatisfy { $0.kind == .congress })
    }

    func testCalendarDetailsShowUncertainDateForCongressDeadlines() {
        let event = CalendarWorkspaceEvent(
            id: "congress-deadline:org-1:congress-1:abstract:2026-06-01",
            source: .congress(organizationID: "org-1", congressID: "congress-1"),
            displayDate: DateParsers.isoDay.date(from: "2026-06-01") ?? Date(),
            isDateUncertain: true,
            title: "Nordic Congress",
            subtitle: "Abstractfrist (osäkert datum)",
            detail: "Abstractfrist (osäkert datum)",
            place: "Oslo",
            timeText: "",
            kind: .applicationDeadline,
            completedOn: nil,
            action: nil,
            toggleCompletion: nil
        )

        XCTAssertEqual(calendarWorkspaceVisibleDetailText(for: event, language: .swedish), "Osäkert datum")
    }

    func testOrganizationReminderLabelsMarkUncertainCongressDates() {
        let congress = OrganizationCongress(
            title: "Nordic Congress",
            from: "2026-10-29",
            fromUncertain: true,
            to: "2026-10-31",
            abstractSubmissionDeadline: "2026-06-01",
            abstractSubmissionDeadlineUncertain: true,
            lateAbstractSubmissionDeadline: "2026-07-01"
        )

        let uncertainReminders = ProjectTaskReminder.uncertainOrganizationReminderOptions(in: [congress])

        XCTAssertTrue(uncertainReminders.contains(.congressStart))
        XCTAssertTrue(uncertainReminders.contains(.abstractDeadline))
        XCTAssertFalse(uncertainReminders.contains(.congressEnd))
        XCTAssertFalse(uncertainReminders.contains(.lateAbstractDeadline))
        XCTAssertEqual(
            ProjectTaskReminder.congressStart.displayName(language: .swedish, marksUncertainDate: true),
            "Kongress start (osäkert datum)"
        )
    }

    func testCalendarApplicationDeadlineFilterIsNamedDeadlines() {
        XCTAssertEqual(CalendarWorkspaceEventKind.applicationDeadline.filterTitle(language: .swedish), "Deadlines")
        XCTAssertEqual(CalendarWorkspaceEventKind.applicationDeadline.filterTitle(language: .english), "Deadlines")
    }

    func testDarkModesUsePositivePrimaryActionButtons() throws {
        let expected = try XCTUnwrap(
            AppAppearanceRegistry.semanticColor(.positive, shaded: false, useDarkPalette: true)
                .usingColorSpace(.deviceRGB)
        )

        for mode in [AppVisualMode.dark, .darkClean, .darkNew] {
            let actual = try XCTUnwrap(AppPalette.actionSaveColor(for: mode).usingColorSpace(.deviceRGB))
            XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.001)
            XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.001)
            XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.001)
            XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.001)
        }
    }

    func testDeleteActionUsesClearFixedButtonColors() throws {
        let expectedLight = try XCTUnwrap(
            NSColor(calibratedRed: 0xC6 / 255.0, green: 0x28 / 255.0, blue: 0x28 / 255.0, alpha: 1)
                .usingColorSpace(.deviceRGB)
        )
        // Dark delete darkened from 0xE5484D so a white 13 pt label clears
        // WCAG AA (4.5:1).
        let expectedDark = try XCTUnwrap(
            NSColor(calibratedRed: 0xD9 / 255.0, green: 0x30 / 255.0, blue: 0x36 / 255.0, alpha: 1)
                .usingColorSpace(.deviceRGB)
        )

        for mode in [AppVisualMode.light, .lightClean] {
            let actual = try XCTUnwrap(AppPalette.actionDeleteColor(for: mode).usingColorSpace(.deviceRGB))
            XCTAssertEqual(actual.redComponent, expectedLight.redComponent, accuracy: 0.001)
            XCTAssertEqual(actual.greenComponent, expectedLight.greenComponent, accuracy: 0.001)
            XCTAssertEqual(actual.blueComponent, expectedLight.blueComponent, accuracy: 0.001)
            XCTAssertEqual(actual.alphaComponent, expectedLight.alphaComponent, accuracy: 0.001)
        }

        for mode in [AppVisualMode.dark, .darkClean, .darkNew] {
            let actual = try XCTUnwrap(AppPalette.actionDeleteColor(for: mode).usingColorSpace(.deviceRGB))
            XCTAssertEqual(actual.redComponent, expectedDark.redComponent, accuracy: 0.001)
            XCTAssertEqual(actual.greenComponent, expectedDark.greenComponent, accuracy: 0.001)
            XCTAssertEqual(actual.blueComponent, expectedDark.blueComponent, accuracy: 0.001)
            XCTAssertEqual(actual.alphaComponent, expectedDark.alphaComponent, accuracy: 0.001)
        }
    }

    func testCompactLinkIconsUseApprovedSymbols() {
        XCTAssertEqual(AppLinkDestinationKind.app.systemImage, "arrow.up.right.square")
        XCTAssertEqual(AppLinkDestinationKind.pdf.systemImage, "doc.richtext.fill")
    }

    func testLinkActionUsesFixedColorsAcrossProfiles() throws {
        let expectedLight = try XCTUnwrap(
            NSColor(calibratedRed: 0x2F / 255.0, green: 0x2F / 255.0, blue: 0xE4 / 255.0, alpha: 1)
                .usingColorSpace(.deviceRGB)
        )
        let expectedDark = try XCTUnwrap(
            NSColor(calibratedRed: 0x3A / 255.0, green: 0x9A / 255.0, blue: 0xFF / 255.0, alpha: 1)
                .usingColorSpace(.deviceRGB)
        )

        for mode in [AppVisualMode.light, .lightClean] {
            let actual = try XCTUnwrap(AppPalette.linkActionColor(for: mode).usingColorSpace(.deviceRGB))
            XCTAssertEqual(actual.redComponent, expectedLight.redComponent, accuracy: 0.001)
            XCTAssertEqual(actual.greenComponent, expectedLight.greenComponent, accuracy: 0.001)
            XCTAssertEqual(actual.blueComponent, expectedLight.blueComponent, accuracy: 0.001)
            XCTAssertEqual(actual.alphaComponent, expectedLight.alphaComponent, accuracy: 0.001)
        }

        for mode in [AppVisualMode.dark, .darkClean, .darkNew] {
            let actual = try XCTUnwrap(AppPalette.linkActionColor(for: mode).usingColorSpace(.deviceRGB))
            XCTAssertEqual(actual.redComponent, expectedDark.redComponent, accuracy: 0.001)
            XCTAssertEqual(actual.greenComponent, expectedDark.greenComponent, accuracy: 0.001)
            XCTAssertEqual(actual.blueComponent, expectedDark.blueComponent, accuracy: 0.001)
            XCTAssertEqual(actual.alphaComponent, expectedDark.alphaComponent, accuracy: 0.001)
        }
    }

    func testSelectionColorUsesFixedColorsAcrossProfiles() throws {
        let expectedLight = try XCTUnwrap(
            NSColor(calibratedRed: 0x3A / 255.0, green: 0x9A / 255.0, blue: 0xFF / 255.0, alpha: 1)
                .usingColorSpace(.deviceRGB)
        )
        let expectedDark = try XCTUnwrap(
            NSColor(calibratedRed: 0x26 / 255.0, green: 0x1C / 255.0, blue: 0xC1 / 255.0, alpha: 1)
                .usingColorSpace(.deviceRGB)
        )

        for mode in [AppVisualMode.light, .lightClean] {
            let actual = try XCTUnwrap(AppPalette.selectionColor(for: mode).usingColorSpace(.deviceRGB))
            XCTAssertEqual(actual.redComponent, expectedLight.redComponent, accuracy: 0.001)
            XCTAssertEqual(actual.greenComponent, expectedLight.greenComponent, accuracy: 0.001)
            XCTAssertEqual(actual.blueComponent, expectedLight.blueComponent, accuracy: 0.001)
            XCTAssertEqual(actual.alphaComponent, expectedLight.alphaComponent, accuracy: 0.001)
        }

        for mode in [AppVisualMode.dark, .darkClean, .darkNew] {
            let actual = try XCTUnwrap(AppPalette.selectionColor(for: mode).usingColorSpace(.deviceRGB))
            XCTAssertEqual(actual.redComponent, expectedDark.redComponent, accuracy: 0.001)
            XCTAssertEqual(actual.greenComponent, expectedDark.greenComponent, accuracy: 0.001)
            XCTAssertEqual(actual.blueComponent, expectedDark.blueComponent, accuracy: 0.001)
            XCTAssertEqual(actual.alphaComponent, expectedDark.alphaComponent, accuracy: 0.001)
        }
    }

    func testMainMenuSelectionUsesPaleBlueInLightModes() throws {
        let expectedLightFill = try XCTUnwrap(
            NSColor(calibratedRed: 0x3A / 255.0, green: 0x9A / 255.0, blue: 0xFF / 255.0, alpha: 0.16)
                .usingColorSpace(.deviceRGB)
        )
        let expectedLightStroke = try XCTUnwrap(
            NSColor(calibratedRed: 0x3A / 255.0, green: 0x9A / 255.0, blue: 0xFF / 255.0, alpha: 0.68)
                .usingColorSpace(.deviceRGB)
        )
        let expectedLightText = try XCTUnwrap(
            NSColor(calibratedRed: 0x2F / 255.0, green: 0x2F / 255.0, blue: 0xE4 / 255.0, alpha: 1)
                .usingColorSpace(.deviceRGB)
        )

        for mode in [AppVisualMode.light, .lightClean] {
            let fill = try XCTUnwrap(AppPalette.mainMenuSelectionSurfaceColor(for: mode).usingColorSpace(.deviceRGB))
            XCTAssertEqual(fill.redComponent, expectedLightFill.redComponent, accuracy: 0.001)
            XCTAssertEqual(fill.greenComponent, expectedLightFill.greenComponent, accuracy: 0.001)
            XCTAssertEqual(fill.blueComponent, expectedLightFill.blueComponent, accuracy: 0.001)
            XCTAssertEqual(fill.alphaComponent, expectedLightFill.alphaComponent, accuracy: 0.001)

            let stroke = try XCTUnwrap(AppPalette.mainMenuSelectionStrokeColor(for: mode).usingColorSpace(.deviceRGB))
            XCTAssertEqual(stroke.redComponent, expectedLightStroke.redComponent, accuracy: 0.001)
            XCTAssertEqual(stroke.greenComponent, expectedLightStroke.greenComponent, accuracy: 0.001)
            XCTAssertEqual(stroke.blueComponent, expectedLightStroke.blueComponent, accuracy: 0.001)
            XCTAssertEqual(stroke.alphaComponent, expectedLightStroke.alphaComponent, accuracy: 0.001)

            let text = try XCTUnwrap(AppPalette.mainMenuSelectionTextColor(for: mode).usingColorSpace(.deviceRGB))
            XCTAssertEqual(text.redComponent, expectedLightText.redComponent, accuracy: 0.001)
            XCTAssertEqual(text.greenComponent, expectedLightText.greenComponent, accuracy: 0.001)
            XCTAssertEqual(text.blueComponent, expectedLightText.blueComponent, accuracy: 0.001)
            XCTAssertEqual(text.alphaComponent, expectedLightText.alphaComponent, accuracy: 0.001)
        }
    }

    func testDarkCVPreviewAppearanceUsesInvertedDocumentColors() {
        XCTAssertEqual(ExportPreviewAppearance.standard.paperBackgroundCSS, "#ffffff")
        XCTAssertEqual(ExportPreviewAppearance.standard.textColorCSS, "#1f2328")
        XCTAssertEqual(ExportPreviewAppearance.darkCVPreview.paperBackgroundCSS, "#050608")
        XCTAssertEqual(ExportPreviewAppearance.darkCVPreview.textColorCSS, "#f5f7f8")
    }

    func testPublicationStatusesHideProjectCollaboratorAuthorButtonsAfterSubmission() {
        XCTAssertTrue(PublicationStatus.inPreparation.showsProjectCollaboratorAuthorButtons)
        XCTAssertTrue(PublicationStatus.rejected.showsProjectCollaboratorAuthorButtons)
        XCTAssertFalse(PublicationStatus.submitted.showsProjectCollaboratorAuthorButtons)
        XCTAssertFalse(PublicationStatus.accepted.showsProjectCollaboratorAuthorButtons)
        XCTAssertFalse(PublicationStatus.published.showsProjectCollaboratorAuthorButtons)
    }

    func testPublicationListRejectedStatusUsesNegativeSolidIndicator() {
        XCTAssertEqual(publicationStatusIndicatorStyle(for: .inPreparation), .neutralOutline)
        XCTAssertEqual(publicationStatusIndicatorStyle(for: .submitted), .inProgressSolid)
        XCTAssertEqual(publicationStatusIndicatorStyle(for: .rejected), .negativeSolid)
        XCTAssertEqual(publicationStatusIndicatorStyle(for: .accepted), .positiveSolid)
    }

    func testCalendarMeetingRecordNormalizesAndDeduplicatesParticipants() {
        var record = CalendarMeetingRecord(
            date: "2026-04-13",
            title: "Meeting",
            participantNames: [" Ada Lovelace ", "Ada Lovelace", " Grace Hopper "]
        )
        record.normalize()

        XCTAssertEqual(record.participantNames, ["Ada Lovelace", "Grace Hopper"])
    }

    func testCalendarMeetingHoursSummaryBucketsPastAndPlannedMeetings() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 13, hour: 12)))
        let records = [
            CalendarMeetingRecord(
                id: "past-meeting",
                date: "2026-04-12",
                startTime: "09:00",
                endTime: "10:30",
                title: "Past",
                meetingMode: CalendarMeetingMode.physical.rawValue,
                participantNames: ["Ada Lovelace", "Grace Hopper"],
                projectIDs: ["project-alpha"]
            ),
            CalendarMeetingRecord(
                id: "later-today-meeting",
                date: "2026-04-13",
                startTime: "14:00",
                endTime: "15:00",
                title: "Later today",
                projectIDs: ["project-alpha"]
            ),
            CalendarMeetingRecord(
                id: "future-meeting",
                date: "2026-04-14",
                startTime: "10:00",
                endTime: "12:00",
                title: "Future",
                projectIDs: ["project-beta"]
            ),
        ]

        let summary = calendarMeetingHoursSummary(
            meetings: records,
            calendar: calendar,
            referenceDate: referenceDate
        ) { meeting in
            (meeting.projectIDs.isEmpty ? (meeting.projectID.map { [$0] } ?? []) : meeting.projectIDs)
                .contains("project-alpha")
        }

        XCTAssertEqual(summary.completedMeetingCount, 1)
        XCTAssertEqual(summary.completedMinutes, 90)
        XCTAssertEqual(summary.completedMeetings.map(\.id), ["past-meeting"])
        XCTAssertEqual(summary.completedMeetings.first?.source, .meeting("past-meeting"))
        XCTAssertEqual(summary.completedMeetings.first?.meetingMode, CalendarMeetingMode.physical.rawValue)
        XCTAssertEqual(summary.completedMeetings.first?.participantNames, ["Ada Lovelace", "Grace Hopper"])
        XCTAssertEqual(summary.plannedMeetingCount, 1)
        XCTAssertEqual(summary.plannedMinutes, 60)
        XCTAssertEqual(summary.plannedMeetings.map(\.id), ["later-today-meeting"])
        XCTAssertEqual(summary.plannedMeetings.first?.source, .meeting("later-today-meeting"))
    }

    func testCalendarMeetingHoursSummaryTracksMeetingsWithoutCompleteTimes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 13, hour: 12)))
        let records = [
            CalendarMeetingRecord(
                date: "2026-04-13",
                startTime: "09:00",
                title: "Missing end",
                participantNames: ["Ada Lovelace"]
            ),
            CalendarMeetingRecord(
                date: "2026-04-14",
                startTime: "10:00",
                title: "Planned missing end",
                participantNames: ["Ada Lovelace"]
            ),
        ]

        let summary = calendarMeetingHoursSummary(
            meetings: records,
            calendar: calendar,
            referenceDate: referenceDate
        ) { meeting in
            meeting.participantNames.contains("Ada Lovelace")
        }

        XCTAssertEqual(summary.completedMeetingCount, 1)
        XCTAssertEqual(summary.completedMinutes, 0)
        XCTAssertEqual(summary.completedMeetingsWithoutDurationCount, 1)
        XCTAssertEqual(summary.plannedMeetingCount, 1)
        XCTAssertEqual(summary.plannedMinutes, 0)
        XCTAssertEqual(summary.plannedMeetingsWithoutDurationCount, 1)
        XCTAssertEqual(summary.meetingsWithoutDurationCount, 2)
    }

    @MainActor
    func testCurrentUserMeetingStatisticsIncludesAllCalendarMeetings() throws {
        let author = PublicationAuthor(
            id: "author-self",
            name: "Ada Lovelace",
            firstName: "Ada",
            lastName: "Lovelace"
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = author.id
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: "self-without-participants",
                date: "2026-04-12",
                startTime: "09:00",
                endTime: "10:00",
                title: "Own meeting without participants"
            ),
            CalendarMeetingRecord(
                id: "self-with-other-participants",
                date: "2026-04-13",
                startTime: "13:00",
                endTime: "14:30",
                title: "Own meeting with other participants",
                participantNames: ["Grace Hopper"]
            ),
        ]
        let store = GrantDataStore(metadata: metadata, publicationAuthors: [author])
        let referenceDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 14, hour: 12)))

        let summary = calendarMeetingHoursSummary(
            store: store,
            scope: .researcher(author),
            referenceDate: referenceDate
        )

        XCTAssertEqual(summary.completedMeetingCount, 2)
        XCTAssertEqual(summary.completedMinutes, 150)
        XCTAssertEqual(summary.completedMeetings.map(\.id), [
            "self-with-other-participants",
            "self-without-participants",
            ])
    }

    @MainActor
    func testCurrentUserMeetingStatisticsExcludesTravelAndClinicCategories() throws {
        let author = PublicationAuthor(
            id: "author-self",
            name: "Ada Lovelace",
            firstName: "Ada",
            lastName: "Lovelace"
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = author.id
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: "research-meeting",
                date: "2026-04-12",
                startTime: "09:00",
                endTime: "10:00",
                title: "Research meeting",
                meetingType: "Projektmöte"
            ),
            CalendarMeetingRecord(
                id: "travel-activity",
                date: "2026-04-12",
                startTime: "10:00",
                endTime: "11:00",
                title: "Travel",
                meetingType: "Resa"
            ),
            CalendarMeetingRecord(
                id: "clinic-activity",
                date: "2026-04-12",
                startTime: "11:00",
                endTime: "12:30",
                title: "Clinic",
                meetingType: "Klinik"
            ),
            CalendarMeetingRecord(
                id: "english-travel-activity",
                date: "2026-04-12",
                startTime: "13:00",
                endTime: "14:00",
                title: "English travel",
                meetingType: "Travel"
            ),
            CalendarMeetingRecord(
                id: "english-clinic-activity",
                date: "2026-04-12",
                startTime: "14:00",
                endTime: "15:00",
                title: "English clinic",
                meetingType: "Clinic"
            ),
        ]
        let store = GrantDataStore(metadata: metadata, publicationAuthors: [author])
        let referenceDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 14, hour: 12)))

        let summary = calendarMeetingHoursSummary(
            store: store,
            scope: .researcher(author),
            referenceDate: referenceDate
        )

        XCTAssertEqual(summary.completedMeetingCount, 1)
        XCTAssertEqual(summary.completedMinutes, 60)
        XCTAssertEqual(summary.completedMeetings.map(\.id), ["research-meeting"])
    }

    @MainActor
    func testClinicMeetingAbroadKeepsNoRegionOrganization() {
        let region = OrganizationRecord(id: "org-region", nameSv: "Region Exempelgöta", nameEn: "Region Exempelgöta")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.homeRegionOrganizationID = "org-region"
        let store = GrantDataStore(metadata: metadata, organizations: [region], skipInitialMigration: true)

        let abroad = store.normalizedCalendarMeetingRecord(
            CalendarMeetingRecord(date: "2026-04-13", title: "Mottagning", meetingType: "Klinik", place: "Bergen", country: "Norway")
        )
        let domestic = store.normalizedCalendarMeetingRecord(
            CalendarMeetingRecord(date: "2026-04-13", title: "Mottagning", meetingType: "Klinik", place: "Exempelvik", country: "Sweden")
        )
        let noCountry = store.normalizedCalendarMeetingRecord(
            CalendarMeetingRecord(date: "2026-04-13", title: "Mottagning", meetingType: "Clinic")
        )

        XCTAssertNil(abroad.organizationID)
        XCTAssertEqual(domestic.organizationID, "org-region")
        XCTAssertEqual(noCountry.organizationID, "org-region")
    }

    @MainActor
    func testCalendarMeetingDefaultsAndTimeNormalization() {
        let store = GrantDataStore(metadata: .bundledDefault)
        XCTAssertTrue(store.calendarMeetingTypeOptions.contains("Kongressdeltagande"))
        XCTAssertTrue(store.calendarMeetingTypeOptions.contains("Handledning"))

        var record = CalendarMeetingRecord(
            date: "2026-04-13",
            startTime: "930",
            endTime: "1115",
            title: "Meeting",
            meetingType: " Handledning ",
            meetingMode: " hybrid ",
            place: " Oslo ",
            participantNames: [" Ada Lovelace ", "Ada Lovelace"]
        )
        record.normalize()

        XCTAssertEqual(record.startTime, "09:30")
        XCTAssertEqual(record.endTime, "11:15")
        XCTAssertEqual(record.meetingType, "Handledning")
        XCTAssertEqual(record.meetingMode, "hybrid")
        XCTAssertEqual(record.place, "Oslo")
        XCTAssertEqual(record.participantNames, ["Ada Lovelace"])
    }

    func testShiftedDateRangeEndPreservesDayOffset() {
        let shifted = shiftedDateRangeEnd(
            previousStart: "2026-04-10",
            newStart: "2026-04-13",
            currentEnd: "2026-04-12"
        )

        XCTAssertEqual(shifted, "2026-04-15")
    }

    func testShiftedTimeRangeEndPreservesMinuteOffset() {
        let shifted = shiftedTimeRangeEnd(
            previousStart: "08:30",
            newStart: "09:45",
            currentEnd: "10:00"
        )

        XCTAssertEqual(shifted, "11:15")
    }

    func testCommittedCalendarTimeForRangeShiftRequiresCompleteTime() {
        XCTAssertNil(committedCalendarTimeForRangeShift("15:0"))
        XCTAssertEqual(committedCalendarTimeForRangeShift("15:00"), "15:00")
        XCTAssertEqual(committedCalendarTimeForRangeShift("1500"), "15:00")
    }

    func testUpdatingCommittedTimeRangeEndUsesLastCommittedStartTime() {
        let incompleteUpdate = updatingCommittedTimeRangeEnd(
            previousCommittedStart: "19:00",
            newInput: "15:0",
            currentEnd: "20:00"
        )
        let completeUpdate = updatingCommittedTimeRangeEnd(
            previousCommittedStart: incompleteUpdate.committedStart,
            newInput: "15:00",
            currentEnd: "20:00"
        )

        XCTAssertEqual(incompleteUpdate.committedStart, "19:00")
        XCTAssertNil(incompleteUpdate.shiftedEnd)
        XCTAssertEqual(completeUpdate.committedStart, "15:00")
        XCTAssertEqual(completeUpdate.shiftedEnd, "16:00")
    }

    func testShiftedDateTimeRangeEndPreservesCombinedOffsetAcrossMidnight() {
        let shifted = shiftedDateTimeRangeEnd(
            previousStartDate: "2026-04-10",
            previousStartTime: "23:30",
            newStartDate: "2026-04-11",
            newStartTime: "00:30",
            currentEndDate: "2026-04-11",
            currentEndTime: "01:15"
        )

        XCTAssertEqual(shifted?.date, "2026-04-11")
        XCTAssertEqual(shifted?.time, "02:15")
    }

    func testUpdatingCommittedDateTimeRangeEndUsesLastCommittedStartTime() {
        let incompleteUpdate = updatingCommittedDateTimeRangeEnd(
            previousCommittedStartDate: "2026-04-17",
            previousCommittedStartTime: "19:00",
            newStartDate: "2026-04-17",
            newStartTimeInput: "15:0",
            currentEndDate: "2026-04-17",
            currentEndTime: "20:00"
        )
        let completeUpdate = updatingCommittedDateTimeRangeEnd(
            previousCommittedStartDate: "2026-04-17",
            previousCommittedStartTime: incompleteUpdate.committedStartTime,
            newStartDate: "2026-04-17",
            newStartTimeInput: "15:00",
            currentEndDate: "2026-04-17",
            currentEndTime: "20:00"
        )

        XCTAssertEqual(incompleteUpdate.committedStartTime, "19:00")
        XCTAssertNil(incompleteUpdate.shiftedEnd)
        XCTAssertEqual(completeUpdate.committedStartTime, "15:00")
        XCTAssertEqual(completeUpdate.shiftedEnd?.date, "2026-04-17")
        XCTAssertEqual(completeUpdate.shiftedEnd?.time, "16:00")
    }

    func testCalendarMeetingTypeOptionsPreserveConfiguredOrder() {
        let normalized = GrantDataStore.normalizedCalendarMeetingTypeOptions([
            "Klinik",
            " Handledning ",
            "Klinik",
            "Forskningsdag",
            "Handledning"
        ])

        XCTAssertEqual(normalized, ["Klinik", "Handledning", "Forskningsdag"])
    }

    func testCalendarMeetingRecordBackfillsAndDeduplicatesProjectLinks() throws {
        let legacyJSON = """
        {
          "id": "meeting-1",
          "date": "2026-04-13",
          "title": "Meeting",
          "projectID": "project-alpha"
        }
        """.data(using: .utf8)!

        var decoded = try JSONDecoder().decode(CalendarMeetingRecord.self, from: legacyJSON)
        decoded.normalize()

        XCTAssertEqual(decoded.projectIDs, ["project-alpha"])
        XCTAssertEqual(decoded.projectID, "project-alpha")

        var record = CalendarMeetingRecord(
            date: "2026-04-13",
            title: "Meeting",
            projectIDs: ["project-alpha", " project-beta ", "project-alpha"]
        )
        record.normalize()

        XCTAssertEqual(record.projectIDs, ["project-alpha", "project-beta"])
        XCTAssertEqual(record.projectID, "project-alpha")
    }

    @MainActor
    func testCalendarKnownMeetingCategoriesIncludeSavedCategoriesAndColorOverrides() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: "meeting-1",
                date: "2026-04-13",
                title: "Meeting",
                meetingType: "Forskningsdag"
            )
        ]
        metadata.calendarCategoryColors = [
            CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.meetingColorID(for: "Forskningsdag"),
                lightHexColor: "12ab34",
                darkHexColor: "3456ef"
            ),
            CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.fixedColorID(for: .travel),
                lightHexColor: "#AA5500",
                darkHexColor: "#0055AA"
            ),
            CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.fixedColorID(for: .deadline),
                lightHexColor: "#CC1122",
                darkHexColor: "#2200CC"
            ),
            CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.fixedColorID(for: .uncategorized),
                lightHexColor: "#778899",
                darkHexColor: "#998877"
            ),
            CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.activityColorID(for: .activity2),
                lightHexColor: "#246810",
                darkHexColor: "#135790"
            ),
            CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.activityColorID(for: .activity3),
                lightHexColor: "#ABC123",
                darkHexColor: "#321CBA"
            )
        ]

        let store = GrantDataStore(metadata: metadata)

        XCTAssertTrue(store.calendarKnownMeetingCategories.contains("Forskningsdag"))
        XCTAssertEqual(store.calendarMeetingCategoryColorHex(named: "Forskningsdag", usesDarkAppearance: false), "#12AB34")
        XCTAssertEqual(store.calendarMeetingCategoryColorHex(named: "Forskningsdag", usesDarkAppearance: true), "#3456EF")
        XCTAssertEqual(store.calendarFixedCategoryColorHex(.travel, usesDarkAppearance: false), "#AA5500")
        XCTAssertEqual(store.calendarFixedCategoryColorHex(.travel, usesDarkAppearance: true), "#0055AA")
        XCTAssertEqual(store.calendarFixedCategoryColorHex(.deadline, usesDarkAppearance: false), "#CC1122")
        XCTAssertEqual(store.calendarFixedCategoryColorHex(.deadline, usesDarkAppearance: true), "#2200CC")
        XCTAssertEqual(store.calendarFixedCategoryColorHex(.uncategorized, usesDarkAppearance: false), "#778899")
        XCTAssertEqual(store.calendarFixedCategoryColorHex(.uncategorized, usesDarkAppearance: true), "#998877")
        XCTAssertEqual(store.calendarActivityColorHex(.activity2, usesDarkAppearance: false), "#246810")
        XCTAssertEqual(store.calendarActivityColorHex(.activity2, usesDarkAppearance: true), "#135790")
        XCTAssertEqual(store.calendarActivityColorHex(.activity3, usesDarkAppearance: false), "#ABC123")
        XCTAssertEqual(store.calendarActivityColorHex(.activity3, usesDarkAppearance: true), "#321CBA")
    }

    func testSalarySourcesUseRequestedCalendarColorTargets() {
        XCTAssertEqual(
            salaryCalendarColorTarget(for: SalarySource(category: .clinic, project: "Vårdcentralen Exempel")),
            .clinicMeetingCategory
        )
        XCTAssertEqual(
            salaryCalendarColorTarget(for: SalarySource(category: .research, project: "Research project")),
            .activity3
        )
        // Round 7: the name no longer decides the colour; the chosen colour does.
        XCTAssertNil(
            salaryCalendarColorTarget(for: SalarySource(category: .teaching, project: "Exempelköpings universitet"))
        )
        XCTAssertEqual(
            salaryCalendarColorTarget(for: SalarySource(category: .teaching, project: "Exempelköpings universitet", color: .calendarActivity2)),
            .activity2
        )
        XCTAssertNil(
            salaryCalendarColorTarget(for: SalarySource(category: .other, project: "Tjänstledighet"))
        )
        XCTAssertEqual(salaryCalendarColorTarget(forSourceReference: "grant:application-1"), .activity3)
        XCTAssertNil(salaryCalendarColorTarget(forSourceReference: "custom:source-1"))
    }

    func testSalaryTimelineMonthBoundariesUseExactEqualWidthCoordinates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        let january = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let february = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let march = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let april = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        let monthWidth: CGFloat = 80
        let monthStarts = [january, february, march]

        XCTAssertEqual(
            salaryTimelineMonthScaledPositionX(
                for: february,
                monthStarts: monthStarts,
                timelineEndExclusive: april,
                monthWidth: monthWidth
            ),
            monthWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            salaryTimelineMonthScaledPositionX(
                for: march,
                monthStarts: monthStarts,
                timelineEndExclusive: april,
                monthWidth: monthWidth
            ),
            monthWidth * 2,
            accuracy: 0.001
        )
    }

    func testSalaryTimelineRecognizesLeaveLabelsForNeutralHatching() {
        XCTAssertTrue(salaryTimelineLabelIsLeave("Tjänstledighet"))
        XCTAssertTrue(salaryTimelineLabelIsLeave("On leave"))
        XCTAssertTrue(salaryTimelineLabelIsLeave(" tjänstledighet "))
        XCTAssertFalse(salaryTimelineLabelIsLeave("Exempelköpings universitet"))
    }

    func testSalaryTimelineStacksLongerPeriodsAboveShorterPeriods() throws {
        let annualStart = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-01-01"))
        let annualEnd = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-12-31"))
        let partialStart = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-03-01"))
        let partialEnd = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-06-30"))
        let annual = SalaryTimelineStackPriority(
            isLeave: false,
            duration: annualEnd.timeIntervalSince(annualStart),
            from: annualStart,
            to: annualEnd,
            percentage: 20,
            rowOrder: 8,
            rowKey: "annual",
            id: "annual"
        )
        let partial = SalaryTimelineStackPriority(
            isLeave: false,
            duration: partialEnd.timeIntervalSince(partialStart),
            from: partialStart,
            to: partialEnd,
            percentage: 45,
            rowOrder: 1,
            rowKey: "partial",
            id: "partial"
        )

        XCTAssertTrue(salaryTimelineStackPriorityComesBefore(annual, partial))
        XCTAssertFalse(salaryTimelineStackPriorityComesBefore(partial, annual))
    }

    func testSalaryTimelineUsesHigherPercentageWhenDurationsMatch() throws {
        let start = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-01-01"))
        let end = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-12-31"))
        let larger = SalaryTimelineStackPriority(
            isLeave: false,
            duration: end.timeIntervalSince(start),
            from: start,
            to: end,
            percentage: 30,
            rowOrder: 2,
            rowKey: "larger",
            id: "larger"
        )
        let smaller = SalaryTimelineStackPriority(
            isLeave: false,
            duration: end.timeIntervalSince(start),
            from: start,
            to: end,
            percentage: 15,
            rowOrder: 1,
            rowKey: "smaller",
            id: "smaller"
        )

        XCTAssertTrue(salaryTimelineStackPriorityComesBefore(larger, smaller))
    }

    func testSalaryTimelineAlwaysStacksLeaveBelowOtherPeriods() throws {
        let start = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-01-01"))
        let regularEnd = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-03-31"))
        let leaveEnd = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-12-31"))
        let regular = SalaryTimelineStackPriority(
            isLeave: false,
            duration: regularEnd.timeIntervalSince(start),
            from: start,
            to: regularEnd,
            percentage: 5,
            rowOrder: 10,
            rowKey: "regular",
            id: "regular"
        )
        let leave = SalaryTimelineStackPriority(
            isLeave: true,
            duration: leaveEnd.timeIntervalSince(start),
            from: start,
            to: leaveEnd,
            percentage: 100,
            rowOrder: 0,
            rowKey: "leave",
            id: "leave"
        )

        XCTAssertTrue(salaryTimelineStackPriorityComesBefore(regular, leave))
        XCTAssertFalse(salaryTimelineStackPriorityComesBefore(leave, regular))
    }

    func testCalendarCategoryColorSettingsNormalizationDeduplicatesByID() {
        let normalized = GrantDataStore.normalizedCalendarCategoryColorSettings([
            CalendarCategoryColorSetting(id: " fixed:travel ", lightHexColor: "abcdef", darkHexColor: "fedcba"),
            CalendarCategoryColorSetting(id: CalendarCategoryColorSetting.fixedColorID(for: .travel), lightHexColor: "#123456", darkHexColor: "#654321"),
            CalendarCategoryColorSetting(id: " ", lightHexColor: "#000000", darkHexColor: "#000000")
        ])

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized.first?.id, CalendarCategoryColorSetting.fixedColorID(for: .travel))
        XCTAssertEqual(normalized.first?.lightHexColor, "#ABCDEF")
        XCTAssertEqual(normalized.first?.darkHexColor, "#FEDCBA")
    }

    func testColorPresetNormalizationDeduplicatesIDsAndFallsBackToDefaultNames() {
        let normalizedDayPresets = GrantDataStore.normalizedCalendarDayHighlightColorPresets([
            CalendarDayHighlightColorPreset(
                id: " default ",
                name: " ",
                settings: [
                    CalendarDayHighlightColorSetting(
                        id: CalendarDayHighlightColorSetting.id(for: .holiday),
                        lightTextHexColor: "112233",
                        lightBackgroundHexColor: "445566"
                    )
                ]
            ),
            CalendarDayHighlightColorPreset(
                id: "default",
                name: "Ignored",
                settings: []
            )
        ])

        XCTAssertEqual(normalizedDayPresets.count, 1)
        XCTAssertEqual(normalizedDayPresets.first?.name, "Standard")

        let normalizedSemanticPresets = GrantDataStore.normalizedAppSemanticColorPresets([
            AppSemanticColorPreset(
                id: " default ",
                name: " ",
                colors: AppSemanticColorSettings(
                    negative: .make("123456", "654321"),
                    inProgress: .make("111111", "222222"),
                    positive: .make("333333", "444444"),
                    neutral: .make("555555", "666666")
                )
            )
        ], fallbackName: "Standard")

        XCTAssertEqual(normalizedSemanticPresets.count, 1)
        XCTAssertEqual(normalizedSemanticPresets.first?.name, "Standard")
        XCTAssertEqual(normalizedSemanticPresets.first?.colors.negative.solidHex, "#123456")
    }

    func testCalendarCategoryColorSettingDecodesLegacySingleHexForBothModes() throws {
        let legacyJSON = """
        {
          "id": "fixed:travel",
          "hexColor": "#ABCDEF"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CalendarCategoryColorSetting.self, from: legacyJSON)

        XCTAssertEqual(decoded.lightHexColor, "#ABCDEF")
        XCTAssertEqual(decoded.darkHexColor, "#ABCDEF")
    }

    func testCalendarMeetingCategoryFilterNamesIncludeUncategorizedAndDeduplicate() {
        let filters = calendarMeetingCategoryFilterNames(from: [" Klinik ", "Seminarium", "klinik", ""])

        XCTAssertEqual(filters, ["", "Klinik", "Seminarium"])
    }

    func testCalendarMeetingCategoryFilterKeyUsesDedicatedUncategorizedValue() {
        XCTAssertEqual(calendarMeetingCategoryFilterKey(for: ""), "__uncategorized__")
        XCTAssertEqual(calendarMeetingCategoryFilterKey(for: " Klinik "), "klinik")
    }

    func testCalendarExclusiveCategorySelectionClearsOtherCategoryGroups() {
        let selection = calendarExclusiveCategorySelection(for: .travel)

        XCTAssertEqual(selection.selectedKinds, [.travel])
        XCTAssertTrue(selection.selectedMeetingCategoryKeys.isEmpty)
    }

    func testCalendarExclusiveMeetingCategorySelectionClearsOtherCategoryGroups() {
        let selection = calendarExclusiveMeetingCategorySelection(for: "klinik")

        XCTAssertEqual(selection.selectedKinds, [.meeting])
        XCTAssertEqual(selection.selectedMeetingCategoryKeys, ["klinik"])
    }

    func testCalendarMeetingCategoryUsageCountMatchesNormalizedCategoryName() {
        let records = [
            CalendarMeetingRecord(id: "meeting-1", date: "2026-04-13", title: "A", meetingType: " Klinik "),
            CalendarMeetingRecord(id: "meeting-2", date: "2026-04-14", title: "B", meetingType: "klinik"),
            CalendarMeetingRecord(id: "meeting-3", date: "2026-04-15", title: "C", meetingType: "Seminarium")
        ]

        XCTAssertEqual(calendarMeetingCategoryUsageCount(in: records, named: "Klinik"), 2)
        XCTAssertEqual(calendarMeetingCategoryUsageCount(in: records, named: "Seminarium"), 1)
        XCTAssertEqual(calendarMeetingCategoryUsageCount(in: records, named: "Missing"), 0)
    }

    func testReassignCalendarMeetingCategoryMovesSavedActivitiesToReplacementCategory() {
        let records = [
            CalendarMeetingRecord(id: "meeting-1", date: "2026-04-13", title: "A", meetingType: "Klinik"),
            CalendarMeetingRecord(id: "meeting-2", date: "2026-04-14", title: "B", meetingType: "Seminarium"),
            CalendarMeetingRecord(id: "meeting-3", date: "2026-04-15", title: "C", meetingType: "klinik")
        ]

        let updated = reassignCalendarMeetingCategory(in: records, from: " Klinik ", to: "Mottagning")

        XCTAssertEqual(updated[0].meetingType, "Mottagning")
        XCTAssertEqual(updated[1].meetingType, "Seminarium")
        XCTAssertEqual(updated[2].meetingType, "Mottagning")
    }

    func testReassignCalendarMeetingCategoryCanClearCategoryToUncategorized() {
        let records = [
            CalendarMeetingRecord(id: "meeting-1", date: "2026-04-13", title: "A", meetingType: "Klinik"),
            CalendarMeetingRecord(id: "meeting-2", date: "2026-04-14", title: "B", meetingType: "Seminarium")
        ]

        let updated = reassignCalendarMeetingCategory(in: records, from: "Klinik", to: nil)

        XCTAssertEqual(updated[0].meetingType, "")
        XCTAssertEqual(updated[1].meetingType, "Seminarium")
    }

    func testCalendarTravelRecordClearsUncertaintyFlagsWhenValuesAreRemoved() {
        var record = CalendarTravelRecord(
            date: "",
            dateUncertain: true,
            departureTime: "",
            departureTimeUncertain: true,
            arrivalTime: "",
            arrivalTimeUncertain: true
        )
        record.normalize()

        XCTAssertFalse(record.dateUncertain)
        XCTAssertFalse(record.departureTimeUncertain)
        XCTAssertFalse(record.arrivalTimeUncertain)
    }

    func testCalendarTravelRecordDerivesArrivalDateWhenTimePassesMidnight() {
        var overnight = CalendarTravelRecord(
            date: "2026-04-14",
            departureTime: "23:15",
            arrivalTime: "01:05"
        )
        overnight.normalize()

        XCTAssertEqual(overnight.arrivalDate, "2026-04-15")

        var sameDay = CalendarTravelRecord(
            date: "2026-04-14",
            departureTime: "09:00",
            arrivalTime: "10:30"
        )
        sameDay.normalize()

        XCTAssertEqual(sameDay.arrivalDate, "2026-04-14")
    }

    @MainActor
    func testPastOrganizationCongressesAndDeadlinesAreHiddenFromCalendar() throws {
        let calendar = footprintCalendar(for: .swedish, weekStart: .monday)
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let fiveDaysAhead = calendar.date(byAdding: .day, value: 5, to: today) ?? today

        let pastCongress = OrganizationCongress(
            title: "Past Congress",
            from: DateParsers.isoDay.string(from: twoDaysAgo),
            to: DateParsers.isoDay.string(from: yesterday),
            abstractSubmissionDeadline: DateParsers.isoDay.string(from: twoDaysAgo),
            lateAbstractSubmissionDeadline: DateParsers.isoDay.string(from: yesterday),
            city: "Oslo",
            country: "Norge"
        )
        let futureCongressWithPastDeadline = OrganizationCongress(
            title: "Future Congress",
            from: DateParsers.isoDay.string(from: fiveDaysAhead),
            to: DateParsers.isoDay.string(from: fiveDaysAhead),
            abstractSubmissionDeadline: DateParsers.isoDay.string(from: yesterday),
            lateAbstractSubmissionDeadline: "",
            city: "Stockholm",
            country: "Sverige"
        )
        let organization = OrganizationRecord(
            id: "org-1",
            nameSv: "Testorganisation",
            nameEn: "Test organization",
            congresses: [pastCongress, futureCongressWithPastDeadline]
        )
        let store = GrantDataStore(organizations: [organization])
        try store.persist(.allCoreData, includeBackup: false)
        let rangeStart = calendar.date(byAdding: .day, value: -10, to: today) ?? today
        let rangeEnd = calendar.date(byAdding: .day, value: 10, to: today) ?? today

        let events = buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: rangeStart,
            displayedMonthEnd: rangeEnd,
            calendar: calendar,
            taskDisplayPolicy: .rollOverPastDue
        )

        XCTAssertFalse(events.contains(where: { $0.title == "Past Congress" }))
        XCTAssertFalse(events.contains(where: { $0.title == "Future Congress" && $0.detail == "Deadline abstract" }))
        XCTAssertTrue(events.contains(where: { $0.title == "Future Congress" && $0.detail.isEmpty }))
    }

    @MainActor
    func testAutosavingOrganizationCongressesPreservesSortedRowLinksAndDates() throws {
        let organization = OrganizationRecord(
            id: "organization-association",
            nameSv: "Association",
            nameEn: "Association",
            roles: [.association]
        )
        let laterCongress = OrganizationCongress(
            id: "congress-later",
            title: "Later congress",
            from: "2027-11-03",
            to: "2027-11-07",
            venue: "Convention Centre",
            city: "Cape Town",
            country: "Sydafrika",
            link: "https://example.org/later",
            participantNames: ["Fredrik Falk"],
            isHiddenOnMap: true,
            travelFlights: [
                OrganizationCongressFlight(
                    id: "flight-1",
                    fromCity: "Stockholm",
                    fromCountry: "Sverige",
                    toCity: "Cape Town",
                    toCountry: "Sydafrika",
                    fromDate: "20271102",
                    toDate: "2027-11-08"
                )
            ],
            hotelName: "Congress Hotel",
            hotelFrom: "20271102",
            hotelTo: "2027-11-08",
            congressFeeSEK: "7500",
            fundingApplicationIDs: ["application-1", "application-1", " application-2 "]
        )
        let earlierCongress = OrganizationCongress(
            id: "congress-earlier",
            title: "Earlier congress",
            from: "2026-10-29",
            to: "2026-10-31",
            abstractSubmissionDeadline: "2026-06-01",
            link: "https://example.org/earlier"
        )
        let store = GrantDataStore(organizations: [organization])

        store.autosaveOrganization(
            id: organization.id,
            nameSv: organization.nameSv,
            nameEn: organization.nameEn,
            addressLine: organization.addressLine,
            postalCode: organization.postalCode,
            city: organization.city,
            country: organization.country,
            category: organization.category,
            roles: organization.roles,
            note: organization.note,
            websiteURL: organization.websiteURL,
            phoneNumber: organization.phoneNumber,
            organizationNumber: organization.organizationNumber,
            vatNumber: organization.vatNumber,
            employerContacts: organization.employerContacts,
            flag: organization.flag,
            membershipFrom: organization.membershipFrom,
            membershipTo: organization.membershipTo,
            congresses: [laterCongress, earlierCongress],
            projectTasks: organization.projectTasks,
            salaryCalculator: organization.salaryCalculator
        )

        XCTAssertTrue(store.flushPendingPersistenceIfNeeded())
        let persisted = try XCTUnwrap(store.sqliteStore?.load([OrganizationRecord].self, named: "organizations"))
        let congresses = try XCTUnwrap(persisted.first { $0.id == organization.id }?.congresses)
        XCTAssertEqual(congresses.map(\.id), ["congress-earlier", "congress-later"])
        XCTAssertEqual(congresses.map(\.from), ["2026-10-29", "2027-11-03"])
        XCTAssertEqual(congresses.map(\.link), ["https://example.org/earlier", "https://example.org/later"])
        XCTAssertEqual(congresses.map(\.isHiddenOnMap), [false, true])
        XCTAssertEqual(congresses.last?.venue, "Convention Centre")
        XCTAssertEqual(congresses.last?.participantNames, ["Fredrik Falk"])
        XCTAssertEqual(congresses.last?.travelFlights, [])
        XCTAssertEqual(congresses.last?.travelHotels, [])
        XCTAssertEqual(congresses.last?.hotelName, "")
        XCTAssertEqual(congresses.last?.hotelFrom, "")
        XCTAssertEqual(congresses.last?.hotelTo, "")
        XCTAssertEqual(congresses.last?.congressFeeSEK, "7500")
        XCTAssertEqual(congresses.last?.fundingApplicationIDs, ["application-1", "application-2"])
        let travelRecords = try XCTUnwrap(store.sqliteStore?.load([CalendarTravelRecord].self, named: "calendar_travel_records"))
        let travel = try XCTUnwrap(travelRecords.first)
        XCTAssertEqual(travel.id, "flight-1")
        XCTAssertEqual(travel.date, "2027-11-02")
        let hotelRecords = try XCTUnwrap(store.sqliteStore?.load([CalendarAccommodationRecord].self, named: "calendar_accommodation_records"))
        let hotel = try XCTUnwrap(hotelRecords.first)
        XCTAssertEqual(hotel.hotelName, "Congress Hotel")
        XCTAssertEqual(hotel.checkInDate, "2027-11-02")
    }

    func testOrganizationCongressMapFlagsDefaultFalseForLegacyData() throws {
        let json = """
        {
          "id": "legacy-congress",
          "title": "Legacy congress",
          "from": "2026-10-29"
        }
        """
        let congress = try JSONDecoder().decode(OrganizationCongress.self, from: Data(json.utf8))

        XCTAssertFalse(congress.isHiddenOnMap)
        XCTAssertEqual(congress.venue, "")
        XCTAssertEqual(congress.travelFlights, [])
        XCTAssertEqual(congress.hotelName, "")
        XCTAssertEqual(congress.hotelFrom, "")
        XCTAssertEqual(congress.hotelTo, "")
        XCTAssertEqual(congress.congressFeeSEK, "")
        XCTAssertEqual(congress.fundingApplicationIDs, [])
    }

    func testOrganizationCongressNormalizationAssignsUniqueIDsForLegacyDuplicates() {
        let laterCongress = OrganizationCongress(
            id: "legacy-congress",
            title: "Later congress",
            from: "2027-11-03"
        )
        let earlierCongress = OrganizationCongress(
            id: "legacy-congress",
            title: "Earlier congress",
            from: "2026-10-29"
        )

        let persisted = persistedOrganizationCongresses(from: [laterCongress, earlierCongress])

        XCTAssertEqual(persisted.map(\.title), ["Earlier congress", "Later congress"])
        XCTAssertEqual(persisted.map(\.id), ["legacy-congress", "legacy-congress-2"])
    }

    func testOrganizationCongressNormalizationAssignsUUIDForModernDuplicates() throws {
        let sharedID = UUID().uuidString
        let laterCongress = OrganizationCongress(
            id: sharedID,
            title: "Later congress",
            from: "2027-11-03"
        )
        let earlierCongress = OrganizationCongress(
            id: sharedID,
            title: "Earlier congress",
            from: "2026-10-29"
        )

        let persisted = persistedOrganizationCongresses(from: [laterCongress, earlierCongress])

        XCTAssertEqual(persisted.map(\.title), ["Earlier congress", "Later congress"])
        XCTAssertEqual(persisted.first?.id, sharedID)
        let secondID = try XCTUnwrap(persisted.last?.id)
        XCTAssertNotEqual(secondID, sharedID)
        XCTAssertFalse(secondID.hasPrefix("\(sharedID)-"))
        XCTAssertNotNil(UUID(uuidString: secondID))
    }

    func testOrganizationCongressNormalizationPreservesEditorLock() {
        let congress = OrganizationCongress(
            id: "locked-congress",
            title: "Locked congress",
            from: "2027-11-03",
            isEditingLocked: true
        )

        let persisted = persistedOrganizationCongresses(from: [congress])

        XCTAssertEqual(persisted.count, 1)
        XCTAssertTrue(persisted[0].isEditingLocked)
    }

    func testRemovingOrganizationCongressWithLegacyDuplicateIDKeepsOtherCongresses() {
        let firstCongress = OrganizationCongress(
            id: "legacy-congress",
            title: "First congress",
            from: "2026-10-29"
        )
        let secondCongress = OrganizationCongress(
            id: "legacy-congress",
            title: "Second congress",
            from: "2027-11-03"
        )

        let rows = organizationCongressRowsRemovingFirstMatch(
            id: "legacy-congress",
            from: [firstCongress, secondCongress]
        )
        let persisted = persistedOrganizationCongresses(from: rows)

        XCTAssertEqual(persisted.map(\.title), ["Second congress"])
        XCTAssertEqual(persisted.map(\.id), ["legacy-congress"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.last?.isEmpty == true)
    }

    func testCountryParsingIncludesSomaliland() {
        XCTAssertTrue(GrantParsing.countryOptions.contains("Somaliland"))
        XCTAssertEqual(GrantParsing.canonicalCountryName("Somaliland"), "Somaliland")
        XCTAssertEqual(AppLanguage.swedish.localizedCountry("Somaliland"), "Somaliland")
        XCTAssertEqual(AppLanguage.english.localizedCountry("Somaliland"), "Somaliland")
    }

    func testCalendarWorkspaceTodayProgressBucketKeepsCompletedItemsHandled() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))
        let now = try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 30, second: 0, of: today))
        let futureCutoff = try XCTUnwrap(calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today))
        let pastCutoff = try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today))
        let otherDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        XCTAssertEqual(
            calendarWorkspaceTodayProgressBucket(
                displayDate: today,
                today: today,
                now: now,
                calendar: calendar,
                isCompleted: true,
                cutoffDate: nil
            ),
            .handled
        )
        XCTAssertEqual(
            calendarWorkspaceTodayProgressBucket(
                displayDate: today,
                today: today,
                now: now,
                calendar: calendar,
                isCompleted: false,
                cutoffDate: futureCutoff
            ),
            .scheduledRemaining
        )
        XCTAssertEqual(
            calendarWorkspaceTodayProgressBucket(
                displayDate: today,
                today: today,
                now: now,
                calendar: calendar,
                isCompleted: false,
                cutoffDate: pastCutoff
            ),
            .handled
        )
        XCTAssertEqual(
            calendarWorkspaceTodayProgressBucket(
                displayDate: today,
                today: today,
                now: now,
                calendar: calendar,
                isCompleted: false,
                cutoffDate: nil
            ),
            .unscheduledRemaining
        )
        XCTAssertNil(
            calendarWorkspaceTodayProgressBucket(
                displayDate: otherDay,
                today: today,
                now: now,
                calendar: calendar,
                isCompleted: true,
                cutoffDate: nil
            )
        )
    }

    func testCalendarClampedVerticalScrollOffsetPreservesInRangeValue() {
        XCTAssertEqual(
            calendarClampedVerticalScrollOffset(240, contentHeight: 1000, viewportHeight: 400),
            240
        )
    }

    func testCalendarClampedVerticalScrollOffsetClampsOutsideViewportRange() {
        XCTAssertEqual(
            calendarClampedVerticalScrollOffset(-30, contentHeight: 1000, viewportHeight: 400),
            0
        )
        XCTAssertEqual(
            calendarClampedVerticalScrollOffset(900, contentHeight: 1000, viewportHeight: 400),
            600
        )
    }

    func testCalendarShouldRestoreSavedScrollOffsetWhenTokenChanges() {
        XCTAssertTrue(
            calendarShouldRestoreSavedScrollOffset(
                didAttachNewScrollView: false,
                lastAppliedToken: 1,
                restoreToken: 2
            )
        )
    }

    func testCalendarShouldNotRestoreSavedScrollOffsetOnlyBecauseNewScrollViewAttaches() {
        XCTAssertFalse(
            calendarShouldRestoreSavedScrollOffset(
                didAttachNewScrollView: true,
                lastAppliedToken: 3,
                restoreToken: 3
            )
        )
    }

    func testCalendarShouldNotRestoreSavedScrollOffsetForInitialToken() {
        XCTAssertFalse(
            calendarShouldRestoreSavedScrollOffset(
                didAttachNewScrollView: true,
                lastAppliedToken: nil,
                restoreToken: 0
            )
        )
    }

    func testCalendarShouldNotRestoreSavedScrollOffsetWhenNothingChanged() {
        XCTAssertFalse(
            calendarShouldRestoreSavedScrollOffset(
                didAttachNewScrollView: false,
                lastAppliedToken: 4,
                restoreToken: 4
            )
        )
    }

    func testCalendarShouldUseDefaultOpenPositionWhenNoRequestsArePending() {
        XCTAssertTrue(
            calendarShouldUseDefaultOpenPosition(
                pendingOpenRequest: nil,
                pendingRevealRequest: nil
            )
        )
    }

    func testCalendarShouldNotUseDefaultOpenPositionWhenRevealRequestExists() {
        XCTAssertFalse(
            calendarShouldUseDefaultOpenPosition(
                pendingOpenRequest: nil,
                pendingRevealRequest: CalendarRevealRequest(dayString: "2026-04-17")
            )
        )
    }

    func testCalendarShouldRestorePersistedViewportWhenNoRequestsArePending() {
        XCTAssertTrue(
            calendarShouldRestorePersistedViewport(
                hasPersistedViewport: true,
                pendingOpenRequest: nil,
                pendingRevealRequest: nil
            )
        )
    }

    func testCalendarShouldNotRestorePersistedViewportWhenRevealRequestExists() {
        XCTAssertFalse(
            calendarShouldRestorePersistedViewport(
                hasPersistedViewport: true,
                pendingOpenRequest: nil,
                pendingRevealRequest: CalendarRevealRequest(dayString: "2026-04-17")
            )
        )
    }

    func testCalendarRevealTargetUsesMatchingEventYear() throws {
        let calendar = Calendar(identifier: .gregorian)
        let targetDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2027-04-22"))
        let wrongYearDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-04-22"))
        let request = CalendarRevealRequest(
            dayString: "2027-04-22",
            eventSource: .congress(organizationID: "org-1", congressID: "congress-1")
        )
        let events = [
            calendarRevealTestEvent(
                id: "wrong-year",
                source: .congress(organizationID: "org-2", congressID: "congress-2"),
                displayDate: wrongYearDate
            ),
            calendarRevealTestEvent(
                id: "target",
                source: .congress(organizationID: "org-1", congressID: "congress-1"),
                displayDate: targetDate
            )
        ]

        XCTAssertEqual(
            calendarRevealTargetDate(request: request, events: events, calendar: calendar),
            targetDate
        )
    }

    func testCalendarRevealTargetUsesFirstVisibleMatchingEventAfterRequestedDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let requestedDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2027-04-22"))
        let visibleDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2027-04-23"))
        let request = CalendarRevealRequest(
            dayString: DateParsers.isoDay.string(from: requestedDate),
            eventSource: .congress(organizationID: "org-1", congressID: "congress-1")
        )
        let events = [
            calendarRevealTestEvent(
                id: "visible",
                source: .congress(organizationID: "org-1", congressID: "congress-1"),
                displayDate: visibleDate
            )
        ]

        XCTAssertEqual(
            calendarRevealTargetDate(request: request, events: events, calendar: calendar),
            visibleDate
        )
    }

    @MainActor
    func testCalendarVisibleDateRangeIncludesPinnedRevealDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))
        let revealDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2029, month: 12, day: 9)))
        let store = GrantDataStore()

        let range = calendarVisibleDateRange(
            store: store,
            calendar: calendar,
            today: today,
            additionalDates: [revealDate]
        )

        XCTAssertLessThanOrEqual(range.lowerBound, calendar.startOfDay(for: revealDate))
        XCTAssertGreaterThanOrEqual(range.upperBound, calendar.startOfDay(for: revealDate))
    }

    func testCalendarDefaultOpenDateUsesMondayOfCurrentWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22)))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20)))

        XCTAssertEqual(
            calendarDefaultOpenDate(today: today, calendar: calendar),
            monday
        )
    }

    func testCalendarDefaultOpenDateUsesPreviousMondayWhenTodayIsSunday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 19)))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 13)))

        XCTAssertEqual(
            calendarDefaultOpenDate(today: today, calendar: calendar),
            monday
        )
    }

    func testCalendarShouldUseStoredViewportSnapshotForDefaultOpenDayAtTopOffset() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))
        let defaultOpenDate = calendarDefaultOpenDate(today: today, calendar: calendar)

        XCTAssertTrue(
            calendarShouldUseStoredViewportSnapshot(
                verticalScrollOffset: 0,
                topVisibleDate: defaultOpenDate,
                today: today,
                calendar: calendar
            )
        )
    }

    func testCalendarShouldUseStoredViewportSnapshotForTodayAtTopOffset() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))

        XCTAssertTrue(
            calendarShouldUseStoredViewportSnapshot(
                verticalScrollOffset: 0,
                topVisibleDate: today,
                today: today,
                calendar: calendar
            )
        )
    }

    func testCalendarShouldIgnoreStoredViewportSnapshotForOtherDayAtTopOffset() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))
        let otherDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        XCTAssertFalse(
            calendarShouldUseStoredViewportSnapshot(
                verticalScrollOffset: 0,
                topVisibleDate: otherDay,
                today: today,
                calendar: calendar
            )
        )
    }

    func testCalendarShouldRefreshViewportRestoreTokenAfterScrollPositionIsCaptured() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))

        XCTAssertTrue(
            calendarShouldRefreshViewportRestoreToken(
                verticalScrollOffset: 240,
                topVisibleDate: today,
                today: today,
                pendingOpenRequest: nil,
                pendingRevealRequest: nil,
                pendingDefaultOpenDate: nil,
                calendar: calendar
            )
        )
    }

    func testCalendarShouldNotRefreshViewportRestoreTokenDuringInitialDefaultOpen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))
        let defaultOpenDate = calendarDefaultOpenDate(today: today, calendar: calendar)

        XCTAssertFalse(
            calendarShouldRefreshViewportRestoreToken(
                verticalScrollOffset: 0,
                topVisibleDate: defaultOpenDate,
                today: today,
                pendingOpenRequest: nil,
                pendingRevealRequest: nil,
                pendingDefaultOpenDate: nil,
                calendar: calendar
            )
        )
    }

    func testCalendarShouldNotPersistViewportSnapshotWhileDefaultOpenIsPending() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))
        let transientTopDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        XCTAssertFalse(
            calendarShouldPersistViewportSnapshot(
                verticalScrollOffset: 0,
                topVisibleDate: transientTopDay,
                today: today,
                pendingOpenRequest: nil,
                pendingRevealRequest: nil,
                pendingDefaultOpenDate: today,
                pendingPersistedViewportRestore: false,
                calendar: calendar
            )
        )
    }

    func testCalendarShouldPersistViewportSnapshotAfterDefaultOpen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))
        let defaultOpenDate = calendarDefaultOpenDate(today: today, calendar: calendar)

        XCTAssertTrue(
            calendarShouldPersistViewportSnapshot(
                verticalScrollOffset: 0,
                topVisibleDate: defaultOpenDate,
                today: today,
                pendingOpenRequest: nil,
                pendingRevealRequest: nil,
                pendingDefaultOpenDate: nil,
                pendingPersistedViewportRestore: false,
                calendar: calendar
            )
        )
    }

    func testCalendarShouldPreserveViewportOnWindowResize() {
        XCTAssertTrue(
            calendarShouldPreserveViewportOnResize(
                oldSize: CGSize(width: 900, height: 700),
                newSize: CGSize(width: 1100, height: 700),
                didInitialLoad: true,
                pendingOpenRequest: nil,
                pendingRevealRequest: nil,
                pendingDefaultOpenDate: nil,
                pendingPersistedViewportRestore: false
            )
        )
    }

    func testCalendarShouldNotPreserveViewportOnInitialLayoutSize() {
        XCTAssertFalse(
            calendarShouldPreserveViewportOnResize(
                oldSize: .zero,
                newSize: CGSize(width: 1100, height: 700),
                didInitialLoad: true,
                pendingOpenRequest: nil,
                pendingRevealRequest: nil,
                pendingDefaultOpenDate: nil,
                pendingPersistedViewportRestore: false
            )
        )
    }

    func testCalendarShouldNotPreserveViewportResizeDuringPendingDefaultOpen() throws {
        let pendingDefaultOpenDate = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 12))
        )

        XCTAssertFalse(
            calendarShouldPreserveViewportOnResize(
                oldSize: CGSize(width: 900, height: 700),
                newSize: CGSize(width: 1100, height: 700),
                didInitialLoad: true,
                pendingOpenRequest: nil,
                pendingRevealRequest: nil,
                pendingDefaultOpenDate: pendingDefaultOpenDate,
                pendingPersistedViewportRestore: false
            )
        )
    }

    func testCalendarPreferredDateForFilterChangeUsesDefaultOpenDateWhileStabilizing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let defaultOpenDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 16)))
        let transientTopVisibleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 4, day: 16)))

        XCTAssertEqual(
            calendarPreferredDateForFilterChange(
                topVisibleDate: transientTopVisibleDate,
                defaultOpenDate: defaultOpenDate,
                pendingDefaultOpenDate: nil,
                isStabilizingDefaultOpen: true,
                calendar: calendar
            ),
            defaultOpenDate
        )
    }

    func testCalendarPreferredDateForFilterChangePreservesVisibleDateAfterStabilizing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let defaultOpenDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 16)))
        let visibleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20)))

        XCTAssertEqual(
            calendarPreferredDateForFilterChange(
                topVisibleDate: visibleDate,
                defaultOpenDate: defaultOpenDate,
                pendingDefaultOpenDate: nil,
                isStabilizingDefaultOpen: false,
                calendar: calendar
            ),
            visibleDate
        )
    }

    func testCalendarFilterViewportPreservationRunsWithoutTargetedNavigation() {
        XCTAssertTrue(
            calendarShouldPreserveViewportAfterFilterChange(
                hasPendingTargetedScroll: false
            )
        )
    }

    func testCalendarFilterViewportPreservationDoesNotOverrideTargetedNavigation() {
        XCTAssertFalse(
            calendarShouldPreserveViewportAfterFilterChange(
                hasPendingTargetedScroll: true
            )
        )
    }

    func testCalendarShouldRefreshViewportRestoreTokenWhenViewingAnotherDayAtTopOffset() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))
        let otherDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))

        XCTAssertTrue(
            calendarShouldRefreshViewportRestoreToken(
                verticalScrollOffset: 0,
                topVisibleDate: otherDay,
                today: today,
                pendingOpenRequest: nil,
                pendingRevealRequest: nil,
                pendingDefaultOpenDate: nil,
                calendar: calendar
            )
        )
    }

    func testCalendarShouldNotRefreshViewportRestoreTokenWhileDefaultOpenIsPending() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))
        let pendingTarget = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 18)))

        XCTAssertFalse(
            calendarShouldRefreshViewportRestoreToken(
                verticalScrollOffset: 240,
                topVisibleDate: today,
                today: today,
                pendingOpenRequest: nil,
                pendingRevealRequest: nil,
                pendingDefaultOpenDate: pendingTarget,
                calendar: calendar
            )
        )
    }

    func testTaskCompletionDateAfterTogglePreservesExistingDate() {
        XCTAssertEqual(
            taskCompletionDateAfterToggle(
                existingCompletedOn: "2026-04-16",
                isCompleted: true,
                todayString: "2026-04-17"
            ),
            "2026-04-16"
        )
    }

    func testTaskCompletionDateAfterToggleDefaultsToTodayWhenMissing() {
        XCTAssertEqual(
            taskCompletionDateAfterToggle(
                existingCompletedOn: nil,
                isCompleted: true,
                todayString: "2026-04-17"
            ),
            "2026-04-17"
        )
        XCTAssertNil(
            taskCompletionDateAfterToggle(
                existingCompletedOn: "2026-04-16",
                isCompleted: false,
                todayString: "2026-04-17"
            )
        )
    }

    func testCalendarHasVisibleDateMatchesSameDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let targetDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17, hour: 12)))
        let availableDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17, hour: 0)))
        let otherDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 0)))

        XCTAssertTrue(
            calendarHasVisibleDate(
                targetDate,
                in: [otherDate, availableDate],
                calendar: calendar
            )
        )
    }

    func testCalendarWorkspaceEventSortPlacesHandledRowsAboveRemainingTimedRowsToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))
        let now = try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 30, second: 0, of: today))
        let pastMeetingCutoff = try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today))
        let futureMeetingCutoff = try XCTUnwrap(calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today))

        let pastMeeting = CalendarWorkspaceEvent(
            id: "meeting-past",
            source: .meeting("meeting-past"),
            displayDate: today,
            title: "Morning meeting",
            subtitle: "",
            detail: "",
            place: "",
            timeText: "09:00-10:00",
            kind: .meeting,
            completedOn: nil,
            action: nil,
            toggleCompletion: nil
        )
        let completedTask = CalendarWorkspaceEvent(
            id: "task-completed",
            source: .teachingTask(taskID: "task-completed"),
            displayDate: today,
            title: "Done task",
            subtitle: "",
            detail: "",
            place: "",
            timeText: "",
            kind: .taskDeadline,
            completedOn: "2026-04-17",
            action: nil,
            toggleCompletion: { _ in }
        )
        let futureMeeting = CalendarWorkspaceEvent(
            id: "meeting-future",
            source: .meeting("meeting-future"),
            displayDate: today,
            title: "Afternoon meeting",
            subtitle: "",
            detail: "",
            place: "",
            timeText: "14:00-15:00",
            kind: .meeting,
            completedOn: nil,
            action: nil,
            toggleCompletion: nil
        )
        let openTask = CalendarWorkspaceEvent(
            id: "task-open",
            source: .teachingTask(taskID: "task-open"),
            displayDate: today,
            title: "Open task",
            subtitle: "",
            detail: "",
            place: "",
            timeText: "",
            kind: .taskDeadline,
            completedOn: nil,
            action: nil,
            toggleCompletion: { _ in }
        )

        let cutoffsByID: [String: Date] = [
            pastMeeting.id: pastMeetingCutoff,
            futureMeeting.id: futureMeetingCutoff,
        ]

        let sorted = [futureMeeting, openTask, completedTask, pastMeeting].sorted {
            calendarWorkspaceEventSort(
                $0,
                $1,
                today: today,
                now: now,
                calendar: calendar,
                cutoffDateProvider: { cutoffsByID[$0.id] }
            )
        }

        XCTAssertEqual(sorted.map(\.id), [
            pastMeeting.id,
            completedTask.id,
            futureMeeting.id,
            openTask.id,
        ])
    }

    func testContributorCompositionSnapshotBuildsExpectedDistributions() {
        let anna = PublicationAuthor(
            name: "Anna Andersson",
            firstName: "Anna",
            lastName: "Andersson",
            titleSv: "Professor",
            titleEn: "Ms",
            hasPhD: true,
            careerStage: .categoryB,
            affiliations: [
                PublicationAffiliation(
                    organizationSv: "Exempelköpings universitet",
                    organizationEn: "Exempelkoping University",
                    country: "Sverige",
                    isPrimary: true
                )
            ]
        )
        let bjorn = PublicationAuthor(
            name: "Björn Berg",
            firstName: "Björn",
            lastName: "Berg",
            titleEn: "Mr",
            positionSv: "Överläkare",
            hasPhD: false,
            affiliations: [
                PublicationAffiliation(
                    organizationSv: "Karolinska Institutet",
                    organizationEn: "Karolinska Institutet",
                    country: "Sverige",
                    isPrimary: true
                )
            ]
        )

        let snapshot = ContributorCompositionSnapshot(
            contributorNames: [
                "Anna Andersson",
                "Björn Berg",
                "Okänd Person"
            ],
            language: .swedish,
            resolveAuthor: { name in
                switch name {
                case "Anna Andersson":
                    anna
                case "Björn Berg":
                    bjorn
                default:
                    nil
                }
            }
        )

        XCTAssertEqual(snapshot.totalCount, 3)
        XCTAssertEqual(snapshot.resolvedCount, 2)
        XCTAssertEqual(snapshot.firstPosition?.gender, .female)
        XCTAssertEqual(snapshot.lastPosition?.gender, .unknown)
        XCTAssertEqual(snapshot.genderDistribution, [
            ContributorCompositionDistributionEntry(label: "Män", count: 1, contributorNames: ["Björn Berg"]),
            ContributorCompositionDistributionEntry(label: "Kvinnor", count: 1, contributorNames: ["Anna Andersson"]),
            ContributorCompositionDistributionEntry(label: "Okänt", count: 1, contributorNames: ["Okänd Person"]),
        ])
        XCTAssertEqual(snapshot.phdDistribution, [
            ContributorCompositionDistributionEntry(label: "Disputerade", count: 1, contributorNames: ["Anna Andersson"]),
            ContributorCompositionDistributionEntry(label: "Ej disputerade", count: 1, contributorNames: ["Björn Berg"]),
            ContributorCompositionDistributionEntry(label: "Saknas", count: 1, contributorNames: ["Okänd Person"]),
        ])
        XCTAssertEqual(snapshot.careerStageDistribution, [
            ContributorCompositionDistributionEntry(label: "B", count: 1, contributorNames: ["Anna Andersson"]),
            ContributorCompositionDistributionEntry(label: "A", count: 1, contributorNames: ["Björn Berg"]),
            ContributorCompositionDistributionEntry(label: "Saknas", count: 1, contributorNames: ["Okänd Person"]),
        ])
        XCTAssertEqual(snapshot.titleDistribution, [
            ContributorCompositionDistributionEntry(label: "Professor", count: 1, contributorNames: ["Anna Andersson"]),
            ContributorCompositionDistributionEntry(label: "Överläkare", count: 1, contributorNames: ["Björn Berg"]),
            ContributorCompositionDistributionEntry(label: "Saknas", count: 1, contributorNames: ["Okänd Person"]),
        ])
        XCTAssertEqual(snapshot.organizationDistribution, [
            ContributorCompositionDistributionEntry(label: "Exempelköpings universitet", count: 1, contributorNames: ["Anna Andersson"]),
            ContributorCompositionDistributionEntry(label: "Karolinska Institutet", count: 1, contributorNames: ["Björn Berg"]),
            ContributorCompositionDistributionEntry(label: "Saknas", count: 1, contributorNames: ["Okänd Person"]),
        ])
        XCTAssertEqual(snapshot.countryDistribution, [
            ContributorCompositionDistributionEntry(label: "Sverige", count: 2, contributorNames: ["Anna Andersson", "Björn Berg"]),
            ContributorCompositionDistributionEntry(label: "Saknas", count: 1, contributorNames: ["Okänd Person"]),
        ])
    }

    func testContributorCompositionSnapshotUsesUnknownGenderWhenNoHonorificMetadataExists() {
        let author = PublicationAuthor(
            name: "Alex Example",
            firstName: "Alex",
            lastName: "Example",
            titleSv: "Professor",
            hasPhD: true
        )

        let snapshot = ContributorCompositionSnapshot(
            contributorNames: ["Alex Example"],
            language: .english,
            resolveAuthor: { _ in author }
        )

        XCTAssertEqual(snapshot.firstPosition?.gender, .unknown)
        XCTAssertEqual(snapshot.genderDistribution, [
            ContributorCompositionDistributionEntry(label: "Unknown", count: 1, contributorNames: ["Alex Example"])
        ])
    }

    func testContributorCompositionSnapshotPrefersExplicitGenderOverHonorifics() {
        let author = PublicationAuthor(
            name: "Pat Example",
            firstName: "Pat",
            lastName: "Example",
            titleEn: "Mr",
            gender: .female,
            hasPhD: true
        )

        let snapshot = ContributorCompositionSnapshot(
            contributorNames: ["Pat Example"],
            language: .english,
            resolveAuthor: { _ in author }
        )

        XCTAssertEqual(snapshot.firstPosition?.gender, .female)
        XCTAssertEqual(snapshot.genderDistribution, [
            ContributorCompositionDistributionEntry(label: "Women", count: 1, contributorNames: ["Pat Example"])
        ])
    }

    @MainActor
    func testCurrentViewWorkbookSheetsIncludeCalendarOnlyWhenCalendarIsSelected() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.lastSelectedTab = "calendar"
        metadata.calendarTravelRecords = [
            CalendarTravelRecord(
                id: "travel-1",
                date: "2026-04-21",
                fromCity: "Exempelköping",
                fromCountry: "Sweden",
                toCity: "Oslo",
                toCountry: "Norway"
            )
        ]
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: "meeting-1",
                date: "2026-04-21",
                title: "Project meeting",
                meetingType: "Meeting",
                participantNames: ["Pontus af Lindholm"]
            )
        ]
        metadata.teachingWorkspaceTasks = [
            PublicationTaskItem(
                id: "teaching-task-1",
                deadline: "2026-04-21",
                comment: "Teaching task"
            )
        ]
        let store = GrantDataStore(
            applications: [
                GrantApplication(id: "application-1", rowNumber: 1, organization: "Funder", grantName: "Grant", closesOn: "2026-05-01")
            ],
            metadata: metadata,
            projects: [
                ProjectRecord(
                    nameSv: "Projekt",
                    nameEn: "Project",
                    projectTasks: [
                        ProjectTaskItem(id: "project-task-1", deadline: "2026-04-22", comment: "Project task")
                    ]
                )
            ],
            publicationRecords: [
                PublicationRecord(
                    id: "publication-1",
                    title: "Publication",
                    publicationTasks: [
                        PublicationTaskItem(id: "publication-task-1", deadline: "2026-04-23", comment: "Publication task")
                    ]
                )
            ]
        )

        let sheetNames = Set(store.currentViewWorkbookSheets().map { $0.name })

        XCTAssertTrue(sheetNames.contains("Data - Calendar travels"))
        XCTAssertTrue(sheetNames.contains("Data - Calendar activities"))
        XCTAssertTrue(sheetNames.contains("Data - Calendar application deadlines"))
        XCTAssertTrue(sheetNames.contains("Data - Project tasks"))
        XCTAssertTrue(sheetNames.contains("Data - Publication tasks"))
        XCTAssertTrue(sheetNames.contains("Data - Teaching tasks"))
        XCTAssertFalse(sheetNames.contains("Data - Applications"))
        XCTAssertFalse(sheetNames.contains("Data - Publications"))
    }

    @MainActor
    func testEntireAppWorkbookSheetsIncludeAllPersistentExportDomains() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarTravelRecords = [CalendarTravelRecord(id: "travel-1", date: "2026-04-21")]
        metadata.calendarMeetingRecords = [CalendarMeetingRecord(id: "meeting-1", date: "2026-04-21", title: "Activity")]
        metadata.salarySources = [SalarySource(category: .research, project: "Project", projectNumber: "123")]
        metadata.salaryCoveragePeriods = [SalaryCoveragePeriod(sourceReference: "Project", from: "2026-01-01", to: "2026-12-31", percentage: "50")]
        let store = GrantDataStore(
            applications: [GrantApplication(id: "application-1", rowNumber: 1, organization: "Funder", grantName: "Grant")],
            metadata: metadata,
            organizations: [OrganizationRecord(nameSv: "Organisation", nameEn: "Organization")],
            managers: [ManagerOption(nameSv: "Förvaltare", nameEn: "Manager", reason: nil)],
            projects: [ProjectRecord(nameSv: "Projekt", nameEn: "Project")],
            teachingCourses: [TeachingCourse(id: "course-1", name: "Course")],
            teachingComponents: [TeachingComponent(id: "component-1", name: "Activity")],
            teachingFormats: [TeachingFormatOption(id: "format-1", name: "Format")],
            teachingAssignments: [TeachingAssignment(id: "assignment-1")],
            doctoralCandidates: [DoctoralCandidateRecord(id: "candidate-1", candidateName: "Doctoral Candidate")],
            cvConferenceContributions: [CVConferenceContribution(id: "conference-1", title: "Conference")],
            cvMediaAppearances: [CVMediaAppearance(id: "media-1", date: "2026-04-21", title: "Media")],
            cvReviewEntries: [CVReviewEntry(id: "review-1", date: "2026-04-21", journalName: "Journal", reference: "Review")],
            cvOtherPublications: [CVOtherPublicationEntry(id: "other-1", title: "Other publication")],
            publicationAuthors: [PublicationAuthor(id: "author-1", name: "Author")],
            publicationJournals: [PublicationJournal(id: "journal-1", name: "Journal")],
            publicationRecords: [PublicationRecord(id: "publication-1", title: "Publication")]
        )

        let sheetNames = store.entireAppWorkbookSheets().map { $0.name }

        XCTAssertTrue(sheetNames.contains("Calendar - Data - Calendar travels"))
        XCTAssertTrue(sheetNames.contains("Calendar - Data - Calendar activities"))
        XCTAssertTrue(sheetNames.contains("Data quality - Missing fields"))
        XCTAssertTrue(sheetNames.contains("Doctoral candidates - Data - Doctoral candidates"))
        XCTAssertTrue(sheetNames.contains("Teaching - Data - Teaching assignments"))
        XCTAssertTrue(sheetNames.contains("Salary - Data - Salary periods"))
        XCTAssertTrue(sheetNames.contains("App settings - Data - Metadata"))
        XCTAssertTrue(sheetNames.contains("CV - Data - CV other publications"))
    }

    @MainActor
    func testSalaryCoverageWorkbookExportUsesSwedishLabels() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "en"
        metadata.salarySources = [
            SalarySource(
                id: "source-1",
                category: .teaching,
                project: "Exempelköping University",
                projectSv: "Svenskt projekt",
                projectEn: "English project",
                projectNumber: "123",
                peoe: "456"
            )
        ]
        metadata.salaryCoveragePeriods = [
            SalaryCoveragePeriod(
                sourceReference: "custom:source-1",
                from: "2026-01-01",
                to: "2026-06-30",
                percentage: "50"
            ),
            SalaryCoveragePeriod(
                sourceReference: "grant:application-1",
                from: "2026-07-01",
                to: "2026-12-31",
                percentage: "25"
            ),
        ]
        let store = GrantDataStore(
            applications: [
                GrantApplication(
                    id: "application-1",
                    rowNumber: 1,
                    organization: "Finansiär",
                    grantName: "Anslag",
                    receivedProjectNumber: "789",
                    receivedPEOE: "012"
                )
            ],
            metadata: metadata,
            organizations: [
                OrganizationRecord(nameSv: "Finansiär", nameEn: "Funder")
            ]
        )

        let rows = store.salaryCoverageExportRows(language: .swedish)

        XCTAssertEqual(rows.map(\.source), [
            "Svenskt projekt",
            "Finansiär, Saknar projekt, Saknar nummer",
        ])
        XCTAssertFalse(rows.contains { $0.source.contains("English project") })

        let outputURL = isolatedStorageDirectory.appendingPathComponent("loneplan.xlsx")
        try GrantDataStore.renderSalaryCoverageWorkbook(rows, to: outputURL)

        let workbookXML = try xlsxEntry(named: "xl/workbook.xml", in: outputURL)
        let sheetXML = try xlsxEntry(named: "xl/worksheets/sheet1.xml", in: outputURL)

        XCTAssertTrue(workbookXML.contains(#"sheet name="Löneplan""#))
        XCTAssertFalse(workbookXML.contains("Salary plan"))
        XCTAssertTrue(sheetXML.contains("Lönekälla"))
        XCTAssertTrue(sheetXML.contains("Projektnummer"))
        XCTAssertTrue(sheetXML.contains("%-sats"))
        XCTAssertTrue(sheetXML.contains("Period från"))
        XCTAssertTrue(sheetXML.contains("Period till"))
        XCTAssertTrue(sheetXML.contains("Svenskt projekt"))
        XCTAssertTrue(sheetXML.contains("Finansiär, Saknar projekt, Saknar nummer"))
        XCTAssertFalse(sheetXML.contains("English project"))
        XCTAssertFalse(sheetXML.contains("No project"))
        XCTAssertFalse(sheetXML.contains("No number"))
    }

    @MainActor
    func testTeachingMeritsExportUsesTermRowsAndCandidateOnlyDoctoralSupervisionTables() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        let currentUser = PublicationAuthor(id: "author-pontus", name: "Pontus af Lindholm")
        let groupCourse = TeachingCourse(
            id: "course-group",
            nameSv: "Klinisk medicin",
            nameEn: "Clinical Medicine",
            contextType: .course,
            programSv: "Exempelprogrammet",
            termSv: "Termin 3",
            institution: "Exempelköpings universitet",
            credits: "30",
            teachingLanguage: "sv"
        )
        let doctoralLevelCourse = TeachingCourse(
            id: "course-doctoral-level",
            nameSv: "Forskar-AT-projekt",
            nameEn: "Research internship project",
            contextType: .doctoralEducation,
            programSv: "Forskarutbildning",
            institution: "Exempelköpings universitet",
            credits: "15",
            teachingLanguage: "sv",
            level: .doctoral
        )
        let clinicalCourse = TeachingCourse(
            id: "course-clinical",
            nameSv: "Klinisk placering",
            nameEn: "Clinical placement",
            contextType: .clinicalTeaching,
            programSv: "Exempelprogrammet",
            institution: "Region Exempelgöta",
            credits: "7.5",
            teachingLanguage: "sv"
        )
        let administrationCourse = TeachingCourse(
            id: "course-admin",
            nameSv: "Kursadministration I",
            nameEn: "Course administration I",
            contextType: .courseAdministration,
            programSv: "Exempelprogrammet",
            termSv: "Termin 5",
            institution: "Exempelköpings universitet",
            teachingLanguage: "sv"
        )
        let store = GrantDataStore(
            metadata: metadata,
            teachingCourses: [groupCourse, doctoralLevelCourse, clinicalCourse, administrationCourse],
            teachingAssignments: [
                TeachingAssignment(
                    id: "assignment-group",
                    periods: [TeachingAssignmentPeriod(from: "2025-01-01", to: "2025-12-31", hoursPerTerm: "2")],
                    contextID: groupCourse.id,
                    activityName: "Skriftlig omtentamen",
                    reportCategory: .groupTeaching,
                    activityTypeName: "Individuell handledning",
                    roles: [.supervisor]
                ),
                TeachingAssignment(
                    id: "assignment-clinical",
                    periods: [TeachingAssignmentPeriod(from: "2025-09-01", to: "2025-12-31", hoursPerTerm: "4")],
                    contextID: clinicalCourse.id,
                    activityName: "Klinisk handledning",
                    reportCategory: .groupTeaching,
                    activityTypeName: "Doktorandhandledning",
                    roles: [.supervisor]
                ),
                TeachingAssignment(
                    id: "assignment-doctoral-level",
                    kind: .supervision,
                    periods: [TeachingAssignmentPeriod(from: "2024-01-01", to: "2024-06-30", hoursPerTerm: "12")],
                    contextID: doctoralLevelCourse.id,
                    activityName: "Projektarbete",
                    reportCategory: .doctoralPrincipalSupervision,
                    activityTypeName: "Handledning",
                    roles: [.principalSupervisor],
                    studentName: "Forskar-AT-student"
                ),
                TeachingAssignment(
                    id: "assignment-admin",
                    periods: [TeachingAssignmentPeriod(from: "2025-07-01", to: "2025-12-31", hoursPerTerm: "8")],
                    contextID: administrationCourse.id,
                    activityName: "Kursansvar",
                    reportCategory: .courseAdministration,
                    activityTypeName: "Utvecklingsarbete"
                )
            ],
            doctoralCandidates: [
                DoctoralCandidateRecord(
                    id: "candidate-1",
                    candidateName: "Doktorand A",
                    institution: "Exempelköpings universitet",
                    admissionDate: "2024-01-01",
                    halftimeDate: "2025-07-01",
                    plannedDisputationDate: "2026-05-01",
                    supervisors: [DoctoralSupervisorLink(authorID: currentUser.id, name: currentUser.name)],
                    supervisionPeriods: [
                        DoctoralSupervisionPeriod(
                            semesterLabel: "VT 2026",
                            from: "2026-01-01",
                            to: "2026-06-30",
                            hoursPerSemester: "40"
                        )
                    ]
                )
            ],
            publicationAuthors: [currentUser]
        )

        let document = store.teachingMeritsPreviewDocument()
        let group = try XCTUnwrap(document.groups.first { $0.title == "Gruppundervisning" })
        let groupTeachingTable = try XCTUnwrap(group.tables.first { $0.title.hasPrefix("Schemalagd grupphandledning") })
        let writtenExamRows = groupTeachingTable.rows.filter { $0[2].contains("Skriftlig omtentamen") }
        XCTAssertEqual(writtenExamRows.map { $0[0] }, ["HT 2025", "VT 2025"])
        XCTAssertEqual(writtenExamRows.map { $0[1] }, ["2", "2"])
        XCTAssertTrue(writtenExamRows[0][2].contains("Klinisk medicin"))
        XCTAssertTrue(writtenExamRows[0][2].contains("Skriftlig omtentamen"))
        XCTAssertTrue(writtenExamRows[0][2].contains("30 hp"))
        XCTAssertFalse(writtenExamRows[0][2].contains("Termin"))
        XCTAssertFalse(writtenExamRows[0][2].contains("Exempelköpings universitet"))
        XCTAssertEqual(writtenExamRows[0][3], "Exempelköpings universitet")
        XCTAssertEqual(writtenExamRows[0][6], "Individuell handledning")

        let clinicalRow = try XCTUnwrap(groupTeachingTable.rows.first { $0[2].contains("Klinisk placering") })
        XCTAssertEqual(clinicalRow[6], "Handledning")

        let supervision = try XCTUnwrap(document.groups.first { $0.title == "Handledning" })
        let thesisTable = try XCTUnwrap(supervision.tables.first { $0.title.hasPrefix("Handledning av examensarbeten") })
        let researchInternshipRow = try XCTUnwrap(thesisTable.rows.first { $0[0] == "VT 2024" && $0[5] == "Forskar-AT-student" })
        XCTAssertEqual(researchInternshipRow[4], "Forskarutbildning, Forskar-AT-projekt")

        let doctoralPrincipalTable = try XCTUnwrap(supervision.tables.first { $0.title.contains("studerande på forskarnivå - huvudhandledare") })
        XCTAssertEqual(doctoralPrincipalTable.rows.count, 1)
        XCTAssertEqual(doctoralPrincipalTable.rows[0][0], "2026")
        XCTAssertEqual(doctoralPrincipalTable.rows[0][3], "Från drygt 2 år in på studierna, efter halvtid")
        XCTAssertEqual(doctoralPrincipalTable.rows[0][5], "Doktorand A")
        XCTAssertFalse(doctoralPrincipalTable.rows.contains { $0.contains("Forskar-AT-student") })

        let administration = try XCTUnwrap(document.groups.first { $0.title == "Kursadministration" })
        let administrationTable = try XCTUnwrap(administration.tables.first)
        let administrationCourseColumn = try XCTUnwrap(administrationTable.rows.first?[5])
        XCTAssertTrue(administrationCourseColumn.contains("Kursadministration I"))
        XCTAssertFalse(administrationCourseColumn.contains("Exempelköpings universitet"))
        XCTAssertFalse(administrationCourseColumn.contains("Termin"))
    }

    @MainActor
    func testProjectWorkbookExportContainsSummaryAndCompleteRelatedDataSheets() throws {
        let project = ProjectRecord(
            id: "project-export",
            nameSv: "Projekt Export",
            nameEn: "Project Export",
            fullNameSv: "Fullständigt projektnamn",
            collaboratorNames: ["Ada Lovelace"],
            projectTasks: [
                ProjectTaskItem(id: "legacy-project-task", deadline: "2026-08-20", comment: "Legacy task")
            ]
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = AppLanguage.swedish.rawValue
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: "project-meeting",
                date: "2026-08-10",
                startTime: "09:00",
                endTime: "10:30",
                title: "Projektmöte",
                projectIDs: [project.id]
            )
        ]
        metadata.taskItems = [
            TaskItem(
                id: "central-project-task",
                deadline: "2026-08-21",
                comment: "Central task",
                links: [TaskLink(kind: .project, targetID: project.id)]
            )
        ]
        let store = GrantDataStore(
            applications: [
                GrantApplication(
                    id: "project-application",
                    rowNumber: 1,
                    organization: "Finansiär",
                    grantName: "Projektanslag",
                    currency: "SEK",
                    maxAmount: "1 000 000",
                    approximateAmount: "900 000",
                    approximateAmountValue: 900_000,
                    projectID: project.id,
                    projectType: project.nameSv,
                    primaryLink: "https://www.example.com/call",
                    secondaryLink: "https://example.org/details",
                    appliedCaseNumber: "CASE-123",
                    appliedAmount: "750 000",
                    appliedAmountValue: 750_000,
                    grantedOn: "2026-08-01",
                    grantedAmount: "500 000",
                    grantedAmountValue: 500_000,
                    result: "Beviljat",
                    receivedConsumedAmount: "125 000",
                    receivedConsumedAmountValue: 125_000
                )
            ],
            metadata: metadata,
            projects: [project],
            cvConferenceContributions: [
                CVConferenceContribution(
                    id: "project-contribution",
                    status: .presented,
                    from: "2026-08-12",
                    title: "Project abstract",
                    contributorNames: ["Ada Lovelace"],
                    presentedBy: "Ada Lovelace",
                    publicationYear: "2026",
                    projectName: project.nameSv,
                    meeting: "Research Congress",
                    meetingCity: "Oslo",
                    meetingCountry: "Norge",
                    journalDOI: "10.1000/abstract"
                )
            ],
            publicationAuthors: [
                PublicationAuthor(
                    id: "author-ada",
                    name: "Ada Lovelace",
                    firstName: "Ada",
                    lastName: "Lovelace",
                    careerStage: .categoryC,
                    university: "Should not be exported",
                    homeAddress: "Should not be exported",
                    birthDate: "1815-12-10",
                    orcid: "0000-0001-2345-6789",
                    affiliations: [
                        PublicationAffiliation(
                            organizationSv: "Svenskt universitet",
                            organizationEn: "Swedish University",
                            departmentSv: "Svensk avdelning",
                            departmentEn: "English Department",
                            city: "Stockholm",
                            country: "Sweden",
                            email: "ada@example.com",
                            isPrimary: true
                        )
                    ],
                    publications: [
                        PublicationAuthorContribution(title: "Unrelated publication", count: 99)
                    ]
                )
            ],
            publicationRecords: [
                PublicationRecord(
                    id: "project-publication",
                    projectID: project.id,
                    projectName: project.nameSv,
                    title: "Project article",
                    doi: "10.1000/project",
                    authorNames: ["Ada Lovelace"]
                )
            ]
        )

        let sheets = store.projectWorkbookSheets(for: project)

        XCTAssertEqual(sheets.map(\.name), [
            "Sammanfattning",
            "Etik och studieregistrering",
            "Medarbetare",
            "Ansökningar",
            "Publikationer",
            "Kalenderhändelser",
            "Uppgifter",
        ])
        XCTAssertEqual(sheets.first?.style, "projectSummary")
        XCTAssertEqual(sheets[0].rows[14][3], "500000")
        XCTAssertEqual(sheets[0].currencyCells, [GrantDataStore.WorkbookExportCellReference(row: 14, column: 3)])
        XCTAssertTrue(sheets.dropFirst().allSatisfy { $0.style == "projectTable" })
        XCTAssertEqual(Array(sheets[2].rows[0].prefix(2)), ["Förnamn", "Efternamn"])
        XCTAssertEqual(Array(sheets[2].rows[1].prefix(2)), ["Ada", "Lovelace"])
        XCTAssertEqual(sheets[2].rows[0][5], "Karriärsteg (Frascati 2015)")
        XCTAssertEqual(sheets[2].rows[1][5], "C")
        XCTAssertFalse(sheets[2].rows[0].contains("Universitet"))
        XCTAssertFalse(sheets[2].rows[0].contains("Telefon"))
        XCTAssertFalse(sheets[2].rows[0].contains("Alternativ telefon"))
        XCTAssertFalse(sheets[2].rows[0].contains("Hemadress"))
        XCTAssertFalse(sheets[2].rows[0].contains("Födelsedatum"))
        XCTAssertFalse(sheets[2].rows[0].contains("Anställningar"))
        XCTAssertFalse(sheets[2].rows[0].contains("Utbildning"))
        XCTAssertEqual(sheets[2].rows[1][8], "Svenskt universitet")
        XCTAssertTrue(sheets[2].rows[1].last?.contains("Project article") == true)
        XCTAssertFalse(sheets[2].rows[1].last?.contains("Unrelated publication") == true)
        XCTAssertTrue(sheets[2].rows[0].contains("ORCID"))
        XCTAssertTrue(sheets[3].rows[0].contains("Ansökningsnummer"))
        XCTAssertEqual(sheets[3].rows[1][7], "750000")
        XCTAssertEqual(sheets[3].rows[1][8], "500000")
        XCTAssertEqual(sheets[3].rows[1][21], "1000000")
        XCTAssertEqual(sheets[3].rows[1][22], "900000")
        XCTAssertEqual(sheets[3].rows[1][33], "www.example.com/call")
        XCTAssertEqual(sheets[3].rows[1][34], "https://example.org/details")
        XCTAssertEqual(Set(sheets[3].currencyCells.map(\.column)), Set([7, 8, 21, 22, 41]))
        XCTAssertEqual(sheets[3].hyperlinks.count, 2)
        XCTAssertTrue(sheets[4].rows[0].contains("DOI"))
        XCTAssertTrue(sheets[4].rows[0].contains("Författare"))
        XCTAssertTrue(sheets[4].rows[0].contains("Tidskrift"))
        XCTAssertTrue(sheets[5].rows[0].contains("Datum"))
        XCTAssertFalse(sheets.dropFirst().contains { sheet in
            sheet.rows.first?.contains(where: { $0 == "id" || $0.contains(".") }) == true
        })
        let detailCells = sheets.dropFirst().flatMap(\.rows).flatMap { $0 }
        XCTAssertFalse(detailCells.contains(project.id))
        XCTAssertFalse(detailCells.contains { $0.hasPrefix("[{") || $0.hasPrefix("[\"") })
        for sheet in sheets.dropFirst() {
            let columnCount = try XCTUnwrap(sheet.rows.first).count
            for (rowIndex, row) in sheet.rows.dropFirst().enumerated() {
                XCTAssertEqual(row.count, columnCount, "\(sheet.name), datarad \(rowIndex + 1)")
            }
        }
        XCTAssertEqual(sheets[4].rows.count, 3)
        XCTAssertEqual(sheets[6].rows.count, 3)

        let englishSheets = store.projectWorkbookSheets(for: project, language: .english)
        XCTAssertEqual(englishSheets.map(\.name), ["Summary", "Ethics & trials", "Collaborators", "Applications", "Publications", "Calendar events", "Tasks"])
        XCTAssertEqual(englishSheets[2].rows[0][5], "Career stage (Frascati 2015)")
        XCTAssertEqual(englishSheets[2].rows[1][8], "Swedish University")
        XCTAssertTrue(englishSheets[4].rows[0].contains("Authors"))
        XCTAssertTrue(englishSheets[4].rows[0].contains("Journal"))

        let outputURL = isolatedStorageDirectory.appendingPathComponent("project-export.xlsx")
        try GrantDataStore.renderGenericWorkbook(
            sheets,
            to: outputURL,
            workspacePrefix: "FootprintProjectWorkbookTest"
        )

        let workbookXML = try xlsxEntry(named: "xl/workbook.xml", in: outputURL)
        let summaryXML = try xlsxEntry(named: "xl/worksheets/sheet1.xml", in: outputURL)
        let collaboratorsXML = try xlsxEntry(named: "xl/worksheets/sheet3.xml", in: outputURL)
        let applicationsXML = try xlsxEntry(named: "xl/worksheets/sheet4.xml", in: outputURL)
        let applicationRelationshipsXML = try xlsxEntry(named: "xl/worksheets/_rels/sheet4.xml.rels", in: outputURL)
        let stylesXML = try xlsxEntry(named: "xl/styles.xml", in: outputURL)
        XCTAssertTrue(workbookXML.contains(#"sheet name="Sammanfattning""#))
        XCTAssertTrue(summaryXML.contains(#"mergeCell ref="A1:D1""#))
        XCTAssertTrue(collaboratorsXML.contains(#"state="frozen""#))
        XCTAssertTrue(collaboratorsXML.contains("autoFilter"))
        XCTAssertTrue(applicationsXML.contains(#"<c r="H2" s="8"><v>750000</v></c>"#))
        XCTAssertTrue(applicationsXML.contains(#"<hyperlink ref="AH2" r:id="rId1"/>"#))
        XCTAssertTrue(applicationsXML.contains(#"<hyperlink ref="AI2" r:id="rId2"/>"#))
        XCTAssertTrue(applicationRelationshipsXML.contains(#"Target="https://www.example.com/call" TargetMode="External""#))
        XCTAssertTrue(applicationRelationshipsXML.contains(#"Target="https://example.org/details" TargetMode="External""#))
        XCTAssertTrue(stylesXML.contains("numFmtId=\"164\""))
        XCTAssertTrue(stylesXML.contains(" kr"))
        XCTAssertTrue(stylesXML.contains("FF243447"))
        XCTAssertTrue(stylesXML.contains("FF2B6F73"))

    }

    @MainActor
    func testProjectWorkbookDefaultLocationExportCompletesThroughBackgroundPipeline() async throws {
        let project = ProjectRecord(id: "project-background-export", nameSv: "Bakgrundsexport", nameEn: "Background export")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = AppLanguage.swedish.rawValue
        metadata.exportDirectoryPath = isolatedStorageDirectory.path
        let store = GrantDataStore(metadata: metadata, projects: [project])

        store.exportProjectWorkbookToDefaultLocation(for: project)

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while store.backgroundActivityCount > 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(store.backgroundActivityCount, 0)
        XCTAssertNil(store.loadError)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: isolatedStorageDirectory
                    .appendingPathComponent("Bakgrundsexport, komplett projektexport.xlsx")
                    .path
            )
        )
    }

    @MainActor
    func testGenericWorkbookRendererWritesExpandedEntireAppWorkbook() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.lastSelectedTab = "projects"
        metadata.calendarMeetingRecords = [CalendarMeetingRecord(id: "meeting-1", date: "2026-04-21", title: "Activity")]
        let longNote = String(repeating: "Long project task note. ", count: 2_000)
        let store = GrantDataStore(
            metadata: metadata,
            projects: [
                ProjectRecord(
                    nameSv: "Projekt",
                    nameEn: "Project",
                    projectTasks: [
                        ProjectTaskItem(
                            id: "project-task-1",
                            deadline: "2026-04-21",
                            comment: "Task",
                            note: longNote
                        )
                    ]
                )
            ]
        )
        let sheets = store.entireAppWorkbookSheets()
        let projectDataSheet = try XCTUnwrap(sheets.first { $0.name == "Projects - Data - Projects" })
        let headers = projectDataSheet.rows.first ?? []

        XCTAssertTrue(headers.contains("projectTasks__part_count"))

        let outputURL = isolatedStorageDirectory.appendingPathComponent("expanded-export.xlsx")
        try GrantDataStore.renderGenericWorkbook(
            sheets,
            to: outputURL,
            workspacePrefix: "FootprintWorkbookExportTest"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertGreaterThan((try? Data(contentsOf: outputURL).count) ?? 0, 1_000)
    }

    @MainActor
    func testFailedExportLeavesExistingDestinationFileUntouched() throws {
        let destinationURL = isolatedStorageDirectory.appendingPathComponent("teaching-merits.docx")
        let existingBytes = Data("previous good export".utf8)
        try existingBytes.write(to: destinationURL)

        let corruptTemplateURL = isolatedStorageDirectory.appendingPathComponent("corrupt-template.docx")
        try Data("not a zip archive".utf8).write(to: corruptTemplateURL)
        setenv("FOOTPRINT_TEACHING_MERITS_TEMPLATE", corruptTemplateURL.path, 1)
        defer { unsetenv("FOOTPRINT_TEACHING_MERITS_TEMPLATE") }

        let document = TeachingMeritsExportDocument(
            title: "Merits",
            groups: [],
            summaryHeaders: [],
            summaryRows: []
        )
        XCTAssertThrowsError(
            try GrantDataStore.renderTeachingMeritsDocument(document, to: destinationURL)
        )
        XCTAssertEqual(try Data(contentsOf: destinationURL), existingBytes)
    }

    func testPublicationLTWADoesNotAbbreviateOneWordTitles() {
        XCTAssertEqual(PublicationLTWA.shortName(for: "Nature"), "Nature")
        XCTAssertEqual(PublicationLTWA.shortName(for: "The Cosmopolitan"), "Cosmopolitan")
        XCTAssertEqual(PublicationLTWA.shortName(for: "Sans frontière"), "Sans frontière")
        XCTAssertEqual(PublicationLTWA.shortName(for: "Resuscitation"), "Resuscitation")
    }

    func testPublicationLTWAStillAbbreviatesMultiwordTitles() {
        XCTAssertEqual(PublicationLTWA.shortName(for: "Journal of Hypertension"), "J. Hypertens.")
        XCTAssertEqual(PublicationLTWA.shortName(for: "Nature Reviews Cardiology"), "Nat. Rev. Cardiol.")
    }

    func testPublicationLTWAPreservesManualPunctuationAndAcronymRules() {
        XCTAssertEqual(PublicationLTWA.shortName(for: "Forum (University)"), "Forum (Univ.)")
        XCTAssertEqual(PublicationLTWA.shortName(for: "E.S.A. journal"), "E.S.A. j.")
        XCTAssertEqual(PublicationLTWA.shortName(for: "Journal of in vitro transfer"), "J. in vitro transf.")
        XCTAssertEqual(PublicationLTWA.shortName(for: "Los Alamos science"), "Los Alamos sci.")
        XCTAssertEqual(PublicationLTWA.shortName(for: "bio-acoustics"), "bio-acoust.")
    }

    @MainActor
    // Historical calendar-ID migration was deliberately retired with the JSON cutover.
    // Keep the fixture temporarily for reference, but exclude it from XCTest discovery.
    func retiredLegacyCalendarProjectMigrationFixture() throws {
        let betaStudyID = "82392743-3D52-4C64-A31E-7AF38F5F6DAE"
        let alphaStudyID = "9F5F6F45-4322-46EF-864C-28993CF45FFA"
        let betaMeetingID = "ABABABAB-ABAB-4BAB-8BAB-ABABABABABAB"
        let alphaMeetingID = "ACACACAC-ACAC-4CAC-8CAC-ACACACACACAC"
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: betaMeetingID,
                date: "2026-05-01",
                title: "BetaStudy",
                projectIDs: ["553089F0-0E99-4167-8E5A-A275E23D12BF"],
                projectID: "553089F0-0E99-4167-8E5A-A275E23D12BF"
            ),
            CalendarMeetingRecord(
                id: alphaMeetingID,
                date: "2026-05-02",
                title: "ALPHA-STUDY",
                projectIDs: ["59C7D85B-4459-4D82-90AD-7098E9C9760C"],
                projectID: "59C7D85B-4459-4D82-90AD-7098E9C9760C"
            )
        ]
        let store = GrantDataStore(
            metadata: metadata,
            projects: [
                ProjectRecord(id: betaStudyID, nameSv: "BETASTUDY", nameEn: "BETASTUDY"),
                ProjectRecord(id: alphaStudyID, nameSv: "ALPHA-STUDY", nameEn: "ALPHA-STUDY")
            ],
            skipInitialMigration: true
        )

        XCTAssertTrue(store.migrateRecordsIfNeeded())
        let meetings = Dictionary(uniqueKeysWithValues: store.calendarMeetingRecords.map { ($0.id, $0) })
        XCTAssertEqual(meetings[betaMeetingID]?.projectID, betaStudyID)
        XCTAssertEqual(meetings[betaMeetingID]?.projectIDs, [betaStudyID])
        XCTAssertEqual(meetings[alphaMeetingID]?.projectID, alphaStudyID)
        XCTAssertEqual(meetings[alphaMeetingID]?.projectIDs, [alphaStudyID])
        XCTAssertFalse(store.migrateRecordsIfNeeded())
    }

    @MainActor
    func testRelationalAuthorIDsAreDerivedFromNamesWithoutRemovingNames() throws {
        let authorID = "FAFAFAFA-FAFA-4AFA-8AFA-FAFAFAFAFAFA"
        let organizationID = "FBFBFBFB-FBFB-4BFB-8BFB-FBFBFBFBFBFB"
        let congressID = "FCFCFCFC-FCFC-4CFC-8CFC-FCFCFCFCFCFC"
        let author = PublicationAuthor(
            id: authorID,
            name: "Fredrik Falk",
            firstName: "Fredrik",
            lastName: "Falk"
        )
        let congress = OrganizationCongress(
            id: congressID,
            title: "ICND",
            participantNames: ["Fredrik Falk"]
        )
        let organization = OrganizationRecord(
            id: organizationID,
            nameSv: "ICDA",
            nameEn: "ICDA",
            congresses: [congress]
        )
        let contribution = CVConferenceContribution(
            id: "contribution-1",
            title: "Abstract",
            contributorNames: ["Fredrik Falk"],
            presentedBy: "Fredrik Falk",
            congressOrganizationID: organizationID,
            congressID: congressID
        )
        let store = GrantDataStore(
            organizations: [organization],
            cvConferenceContributions: [contribution],
            publicationAuthors: [author],
            skipInitialMigration: true
        )

        XCTAssertTrue(store.migrateRecordsIfNeeded())
        let savedCongress = try XCTUnwrap(store.organizations.first?.congresses.first)
        XCTAssertEqual(savedCongress.participantNames, ["Fredrik Falk"])
        XCTAssertEqual(savedCongress.participantAuthorIDs, [authorID])
        let savedContribution = try XCTUnwrap(store.cvConferenceContributions.first)
        XCTAssertEqual(savedContribution.contributorNames, ["Fredrik Falk"])
        XCTAssertEqual(savedContribution.contributorAuthorIDs, [authorID])
        XCTAssertEqual(savedContribution.presentedBy, "Fredrik Falk")
        XCTAssertEqual(savedContribution.presentedByAuthorID, authorID)
        XCTAssertFalse(store.migrateRecordsIfNeeded())
    }

    @MainActor
    func testRelationalCoreSnapshotContainsStableIDLinks() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: "meeting-1",
                date: "2026-05-03",
                title: "Project meeting",
                projectIDs: ["project-1"],
                organizationIDs: ["organization-1"],
                applicationIDs: ["application-1"],
                publicationIDs: ["publication-1"]
            )
        ]
        metadata.calendarTravelRecords = [
            CalendarTravelRecord(
                id: "travel-1",
                date: "2026-05-02",
                departureTime: "10:00",
                fromCity: "Stockholm",
                fromCountry: "Sverige",
                arrivalTime: "12:00",
                toCity: "Oslo",
                toCountry: "Norge",
                congressOrganizationID: "organization-1",
                congressID: "congress-1"
            )
        ]
        metadata.calendarAccommodationRecords = [
            CalendarAccommodationRecord(
                id: "accommodation-1",
                hotelName: "Congress Hotel",
                checkInDate: "2026-05-02",
                checkOutDate: "2026-05-05",
                congressOrganizationID: "organization-1",
                congressID: "congress-1"
            )
        ]
        let congress = OrganizationCongress(
            id: "congress-1",
            title: "Congress",
            participantAuthorIDs: ["author-1"],
            fundingApplicationIDs: ["application-1"]
        )
        let contribution = CVConferenceContribution(
            id: "contribution-1",
            title: "Abstract",
            contributorAuthorIDs: ["author-1"],
            presentedByAuthorID: "author-1",
            congressOrganizationID: "organization-1",
            congressID: "congress-1"
        )
        let store = GrantDataStore(
            metadata: metadata,
            organizations: [
                OrganizationRecord(
                    id: "organization-1",
                    nameSv: "Organisation",
                    nameEn: "Organization",
                    congresses: [congress]
                )
            ],
            cvConferenceContributions: [contribution],
            skipInitialMigration: true
        )

        let snapshot = store.relationalCoreSnapshot(generatedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.congresses.map(\.id), ["congress-1"])
        XCTAssertEqual(snapshot.congressParticipants.map(\.authorID), ["author-1"])
        XCTAssertEqual(snapshot.congressFunding.map(\.applicationID), ["application-1"])
        XCTAssertEqual(snapshot.congressTravel.map(\.travelID), ["travel-1"])
        XCTAssertEqual(snapshot.congressAccommodation.map(\.accommodationID), ["accommodation-1"])
        XCTAssertEqual(snapshot.conferenceContributionCongresses.map(\.contributionID), ["contribution-1"])
        XCTAssertEqual(Set(snapshot.conferenceContributionAuthors.map(\.role)), Set(["contributor", "presenter"]))
        XCTAssertEqual(snapshot.calendarMeetingProjects.map(\.projectID), ["project-1"])
        XCTAssertEqual(snapshot.calendarMeetingOrganizations.map(\.organizationID), ["organization-1"])
        XCTAssertEqual(snapshot.calendarMeetingApplications.map(\.applicationID), ["application-1"])
        XCTAssertEqual(snapshot.calendarMeetingPublications.map(\.publicationID), ["publication-1"])
    }

    @MainActor
    func testCongressTravelPlanningRowsCreateMatchingCalendarRecords() throws {
        let organizationID = "66666666-6666-4666-8666-666666666666"
        let congressID = "77777777-7777-4777-8777-777777777777"
        let travelID = "88888888-8888-4888-8888-888888888888"
        let hotelID = "99999999-9999-4999-8999-999999999999"
        let congress = OrganizationCongress(
            id: congressID,
            title: "Congress",
            city: "Toronto",
            country: "Kanada",
            travelFlights: [
                OrganizationCongressFlight(
                    id: travelID,
                    mode: .flight,
                    fromCity: "Köpenhamn",
                    fromCountry: "Danmark",
                    toCity: "Toronto",
                    toCountry: "Kanada",
                    fromDate: "2024-06-10",
                    fromTime: "12:30",
                    toDate: "2024-06-10",
                    toTime: "20:45"
                )
            ],
            travelHotels: [
                OrganizationCongressHotel(
                    id: hotelID,
                    hotelName: "Holiday Inn Toronto Downtown Centre",
                    fromDate: "2024-06-10",
                    fromTime: "20:45",
                    toDate: "2024-06-15",
                    toTime: "10:50"
                )
            ]
        )
        let organization = OrganizationRecord(
            id: organizationID,
            nameSv: "ICDA",
            nameEn: "ICDA",
            congresses: [congress]
        )
        let store = GrantDataStore(
            organizations: [organization],
            skipInitialMigration: true
        )

        XCTAssertTrue(store.migrateRecordsIfNeeded())
        let travel = try XCTUnwrap(store.calendarTravelRecords.first { $0.id == travelID })
        XCTAssertEqual(travel.congressOrganizationID, organizationID)
        XCTAssertEqual(travel.congressID, congressID)
        XCTAssertEqual(travel.date, "2024-06-10")
        XCTAssertEqual(travel.fromCity, "Köpenhamn")
        XCTAssertEqual(travel.toCity, "Toronto")

        let accommodation = try XCTUnwrap(store.calendarAccommodationRecords.first { $0.id == hotelID })
        XCTAssertEqual(accommodation.congressOrganizationID, organizationID)
        XCTAssertEqual(accommodation.congressID, congressID)
        XCTAssertEqual(accommodation.hotelName, "Holiday Inn Toronto Downtown Centre")
        XCTAssertEqual(accommodation.city, "Toronto")
        XCTAssertEqual(accommodation.country, "Kanada")
        let savedCongress = try XCTUnwrap(store.organizations.first?.congresses.first)
        XCTAssertEqual(savedCongress.travelFlights, [])
        XCTAssertEqual(savedCongress.travelHotels, [])
        XCTAssertEqual(savedCongress.hotelName, "")
        XCTAssertFalse(store.integrityIssues(includeHidden: true).contains { issue in
            issue.subtitle.contains("Kongressresa saknar") || issue.subtitle.contains("Kongressboende saknar")
        })
    }

    @MainActor
    func testCalendarLinkedCongressPlanningMarksParticipationWithoutCopyingRows() throws {
        let authorID = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        let organizationID = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        let congressID = "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC"
        let travelID = "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD"
        let hotelID = "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE"
        let author = PublicationAuthor(
            id: authorID,
            name: "Fredrik Falk",
            firstName: "Fredrik",
            lastName: "Falk"
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = author.id
        metadata.calendarTravelRecords = [
            CalendarTravelRecord(
                id: travelID,
                date: "2026-09-10",
                arrivalDate: "2026-09-10",
                departureTime: "12:30",
                fromCity: "Köpenhamn",
                fromCountry: "Danmark",
                arrivalTime: "20:45",
                toCity: "Toronto",
                toCountry: "Kanada",
                congressOrganizationID: organizationID,
                congressID: congressID
            )
        ]
        metadata.calendarAccommodationRecords = [
            CalendarAccommodationRecord(
                id: hotelID,
                hotelName: "Congress Hotel",
                checkInDate: "2026-09-10",
                checkOutDate: "2026-09-12",
                congressOrganizationID: organizationID,
                congressID: congressID
            )
        ]
        let organization = OrganizationRecord(
            id: organizationID,
            nameSv: "ICDA",
            nameEn: "ICDA",
            congresses: [
                OrganizationCongress(
                    id: congressID,
                    title: "Congress"
                )
            ]
        )
        let store = GrantDataStore(
            metadata: metadata,
            organizations: [organization],
            publicationAuthors: [author],
            skipInitialMigration: true
        )

        XCTAssertTrue(store.migrateRecordsIfNeeded())
        let savedCongress = try XCTUnwrap(store.organizations.first?.congresses.first)
        XCTAssertEqual(savedCongress.participantNames, ["Fredrik Falk"])
        XCTAssertEqual(savedCongress.participantAuthorIDs, [authorID])
        XCTAssertEqual(savedCongress.travelFlights, [])
        XCTAssertEqual(savedCongress.travelHotels, [])
        XCTAssertEqual(store.calendarTravelRecords.map(\.id), [travelID])
        XCTAssertEqual(store.calendarAccommodationRecords.map(\.id), [hotelID])
        XCTAssertFalse(store.migrateRecordsIfNeeded())
    }

    func testTopLevelCongressRecordsOverrideEmbeddedOrganizationCongresses() {
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organisation",
            nameEn: "Organization",
            roles: [.grantProvider, .fundManager],
            congresses: [
                OrganizationCongress(
                    id: "congress-1",
                    title: "Embedded title",
                    from: "2026-01-01"
                )
            ]
        )
        let stored = StoredCongressRecord(
            id: StoredCongressRecord.recordID(organizationID: "organization-1", congressID: "congress-1"),
            organizationID: "organization-1",
            organizationName: "Organisation",
            congress: OrganizationCongress(
                id: "congress-1",
                title: "Top-level title",
                from: "2026-02-01"
            )
        )

        let merged = GrantDataStore.organizationsByMergingStoredCongressRecords([stored], into: [organization])

        XCTAssertEqual(merged.first?.congresses.map(\.title), ["Top-level title"])
        XCTAssertEqual(merged.first?.congresses.map(\.from), ["2026-02-01"])
    }

    func testAppSettingsSnapshotSeparatesSettingsFromDomainCalendarRecords() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = AppLanguage.swedish.rawValue
        metadata.calendarFirstWeekday = "monday"
        metadata.calendarTravelRecords = [
            CalendarTravelRecord(
                id: "travel-1",
                date: "2026-01-01",
                fromCity: "Stockholm",
                toCity: "Oslo"
            )
        ]

        let settings = AppSettingsSnapshot(metadata: metadata)
        let applied = GrantDataStore.metadataByApplyingAppSettings(.bundledDefault, settings: settings)

        XCTAssertEqual(applied.interfaceLanguage, AppLanguage.swedish.rawValue)
        XCTAssertEqual(applied.calendarFirstWeekday, "monday")
        XCTAssertNil(applied.calendarTravelRecords)
    }

    @MainActor
    func testPersistenceIncludesSeparatedAppSettingsDocument() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = AppLanguage.swedish.rawValue
        let store = GrantDataStore(metadata: metadata, skipInitialMigration: true)

        let documents = try Dictionary(uniqueKeysWithValues: store.encodedSQLiteDocuments(for: [.metadata, .appSettings]))

        XCTAssertNotNil(documents["metadata"])
        let settingsData = try XCTUnwrap(documents["app_settings"])
        let settings = try JSONDecoder().decode(AppSettingsSnapshot.self, from: settingsData)
        XCTAssertEqual(settings.interfaceLanguage, AppLanguage.swedish.rawValue)
    }

    @MainActor
    func testActivePersistenceWritesSQLiteWithoutJSONMirror() throws {
        let application = GrantApplication(
            id: "application-1",
            rowNumber: 1,
            organization: "Funder",
            grantName: "Grant"
        )
        let store = GrantDataStore(applications: [application], skipInitialMigration: true)

        try store.persist(.applications, includeBackup: false)

        let persisted = try XCTUnwrap(store.sqliteStore?.load([GrantApplication].self, named: "applications"))
        XCTAssertEqual(persisted.map(\.id), ["application-1"])
        XCTAssertTrue(try XCTUnwrap(store.sqliteStore).containsDocument(named: "applications"))
    }

    @MainActor
    func testSQLiteBackupDoesNotPersistDerivedManagersDocument() throws {
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Förvaltaren",
            nameEn: "The Manager",
            roles: [.fundManager]
        )
        let store = GrantDataStore(organizations: [organization], skipInitialMigration: true)

        let documents = try Dictionary(uniqueKeysWithValues: GrantDataStore.encodedSQLiteDocuments(for: store.currentSnapshot()))

        XCTAssertNil(documents["managers"])
        XCTAssertNotNil(documents["organizations"])
    }

    @MainActor
    func testBootstrapLoadsCompleteSQLiteWithoutActiveJSONFiles() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let seedStore = GrantDataStore(
            applications: snapshot.applications,
            metadata: snapshot.metadata,
            organizations: snapshot.organizations,
            managers: snapshot.managers,
            projects: snapshot.projects,
            teachingCourses: snapshot.teachingCourses,
            teachingComponents: snapshot.teachingComponents,
            teachingFormats: snapshot.teachingFormats,
            teachingAssignments: snapshot.teachingAssignments,
            doctoralCandidates: snapshot.doctoralCandidates,
            cvPersonalResume: snapshot.cvPersonalResume,
            cvConferenceContributions: snapshot.cvConferenceContributions,
            cvMediaAppearances: snapshot.cvMediaAppearances,
            cvReviewEntries: snapshot.cvReviewEntries,
            cvOtherPublications: snapshot.cvOtherPublications,
            publicationAuthors: snapshot.publicationAuthors,
            publicationJournals: snapshot.publicationJournals,
            publicationRecords: snapshot.publicationRecords,
            skipInitialMigration: true
        )

        try seedStore.persist(.allCoreData, includeBackup: false)
        try GrantDataStore.writeCurrentStartupMaintenanceMarker()

        let loadedStore = GrantDataStore.loadFromBundle()

        XCTAssertNil(loadedStore.loadError)
        XCTAssertEqual(loadedStore.applicationsForRead.map(\.id), ["application-1"])
        XCTAssertEqual(loadedStore.projectsForRead.map(\.id), ["project-1"])
        XCTAssertEqual(loadedStore.publicationRecordsForRead.map(\.id), ["publication-1"])
        XCTAssertNotNil(loadedStore.sqliteStore)
    }

    @MainActor
    func testBootstrapPreservesExistingIDsWhenHistoricalIDMigrationIsRetired() throws {
        let organizationID = UUID().uuidString
        let legacyCongressID = "\(UUID().uuidString)-2"
        var metadata = DataSourceMetadata.bundledDefault
        metadata.idAliases = []
        metadata.migrationLog = [
            DataSchemaMigrationLogEntry(
                id: "schema-v9-modern-first-class-ids",
                key: "schema-v9-modern-first-class-ids",
                appliedAt: "test",
                details: "First-class IDs were previously migrated."
            )
        ]
        let seedStore = GrantDataStore(
            metadata: metadata,
            organizations: [
                OrganizationRecord(
                    id: organizationID,
                    nameSv: "World Heart Federation",
                    nameEn: "World Heart Federation",
                    congresses: [
                        OrganizationCongress(
                            id: legacyCongressID,
                            title: "World Congress of Cardiology 2025"
                        )
                    ]
                )
            ],
            skipInitialMigration: true
        )

        try seedStore.persist(.allCoreData, includeBackup: false)
        try GrantDataStore.writeCurrentStartupMaintenanceMarker()

        let loadedStore = GrantDataStore.loadFromBundle()

        XCTAssertNil(loadedStore.loadError)
        let storedCongressID = try XCTUnwrap(loadedStore.organizations.first?.congresses.first?.id)
        XCTAssertEqual(storedCongressID, legacyCongressID)
        let idDiagnostic = try XCTUnwrap(loadedStore.dataStructureDiagnostics().first { $0.id == "first-class-record-ids" })
        XCTAssertEqual(idDiagnostic.details.first { $0.id == "legacy-ids" }?.value, "1")

        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        let persistedOrganizations = try XCTUnwrap(sqliteStore.load([OrganizationRecord].self, named: "organizations"))
        XCTAssertEqual(persistedOrganizations.first?.congresses.first?.id, legacyCongressID)
        let safetyBackup = try GrantDataStore.loadBackupSnapshots()
            .first { $0.url.lastPathComponent.contains("pre-first-class-id-repair") }
        XCTAssertNil(safetyBackup)
    }

    @MainActor
    func testBootstrapLeavesInactiveLegacyJSONFilesUntouched() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let seedStore = GrantDataStore(
            applications: snapshot.applications,
            metadata: snapshot.metadata,
            organizations: snapshot.organizations,
            managers: snapshot.managers,
            projects: snapshot.projects,
            teachingCourses: snapshot.teachingCourses,
            teachingComponents: snapshot.teachingComponents,
            teachingFormats: snapshot.teachingFormats,
            teachingAssignments: snapshot.teachingAssignments,
            doctoralCandidates: snapshot.doctoralCandidates,
            cvPersonalResume: snapshot.cvPersonalResume,
            cvConferenceContributions: snapshot.cvConferenceContributions,
            cvMediaAppearances: snapshot.cvMediaAppearances,
            cvReviewEntries: snapshot.cvReviewEntries,
            cvOtherPublications: snapshot.cvOtherPublications,
            publicationAuthors: snapshot.publicationAuthors,
            publicationJournals: snapshot.publicationJournals,
            publicationRecords: snapshot.publicationRecords,
            skipInitialMigration: true
        )

        try seedStore.persist(.allCoreData, includeBackup: false)
        let legacyJSONURL = isolatedStorageDirectory.appendingPathComponent("applications.json")
        try Data("[]".utf8).write(to: legacyJSONURL)
        var exchangeRateCache = CurrencyExchangeRateCache(
            sourceURL: "https://example.test/rates.xml",
            fetchedAt: "2026-05-26",
            firstApplicationDate: nil,
            days: [
                CurrencyExchangeRateDay(date: "2026-05-25", rates: ["EUR": 1, "SEK": 11.0])
            ]
        )
        exchangeRateCache.normalize()
        try GrantDataStore.encode(exchangeRateCache, to: GrantDataStore.currencyExchangeRatesURL)
        let obsoletePreFlightsBackupURL = isolatedStorageDirectory
            .appendingPathComponent("metadata.json.pre_flights_20260414114605.bak")
        try Data("{}".utf8).write(to: obsoletePreFlightsBackupURL)
        try GrantDataStore.writeCurrentStartupMaintenanceMarker()

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyJSONURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: obsoletePreFlightsBackupURL.path))
        let loadedStore = GrantDataStore.loadFromBundle()

        XCTAssertNil(loadedStore.loadError)
        XCTAssertEqual(loadedStore.applicationsForRead.map(\.id), ["application-1"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyJSONURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: obsoletePreFlightsBackupURL.path))
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        let storedExchangeRateCache = try XCTUnwrap(
            sqliteStore.load(CurrencyExchangeRateCache.self, named: GrantDataStore.currencyExchangeRatesStorageKey)
        )
        XCTAssertEqual(storedExchangeRateCache.days.first?.rates["SEK"], 11.0)
        XCTAssertNil(
            try GrantDataStore.loadBackupSnapshots()
                .first { $0.url.lastPathComponent.contains("pre-active-json-cleanup") }
        )
    }

    @MainActor
    func testBootstrapRejectsIncompleteSQLiteWithoutJSONRepair() throws {
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        try sqliteStore.save(
            [GrantApplication(id: "stale-application", rowNumber: 1, organization: "Old", grantName: "Old")],
            named: "applications"
        )

        let loadedStore = GrantDataStore.loadFromBundle()

        XCTAssertNotNil(loadedStore.loadError)
        XCTAssertEqual(loadedStore.applicationsForRead.map(\.id), [])
        let unrepairedSQLiteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        XCTAssertNil(try unrepairedSQLiteStore.load([PublicationRecord].self, named: "publication_records"))
    }

    @MainActor
    func testRestorePayloadWritesSQLiteWithoutActiveJSONMirror() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let expectedReport = GrantDataStore.healthReport(for: snapshot)

        _ = try GrantDataStore.writeRestorePayloadToStorage(
            .init(snapshot: snapshot, archivedRecords: [], receivedGrantsData: nil),
            expectedReport: expectedReport
        )

        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        XCTAssertTrue(try sqliteStore.containsDocument(named: "applications"))
        XCTAssertEqual(
            try sqliteStore.load([GrantApplication].self, named: "applications")?.map(\.id),
            ["application-1"]
        )
        XCTAssertTrue(try sqliteStore.containsDocument(named: "applications"))
    }

    @MainActor
    func testModernBackupRepresentsEmptyAuxiliaryDataExplicitly() throws {
        let backupURL = try GrantDataStore.createForcedBackupSnapshot(
            snapshot: makeSQLiteOnlySnapshot(),
            archivedRecords: [],
            receivedGrantsData: nil,
            prefix: "empty-auxiliary",
            now: Date(timeIntervalSince1970: 1_800_001_000)
        )

        let payload = try GrantDataStore.decodeRestorePayload(from: backupURL)

        XCTAssertEqual(payload.archivedRecords?.count, 0)
        XCTAssertNil(payload.receivedGrantsData)
        XCTAssertTrue(payload.replacesArchivedRecords)
        XCTAssertTrue(payload.replacesReceivedGrantsData)
    }

    @MainActor
    func testModernRestoreClearsNewerAuxiliaryDocumentsExactly() throws {
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        let archived = GrantDataStore.ArchivedRecordEnvelope(
            id: "archived-1",
            kind: "application",
            title: "Archived",
            deletedAt: "2026-07-13T12:00:00Z",
            payload: Data("{}".utf8),
            relatedDocumentStates: nil
        )
        try sqliteStore.save([archived], named: "archived_records")
        try sqliteStore.save(Data("newer-received-grants".utf8), named: "received_grants")
        let snapshot = makeSQLiteOnlySnapshot()
        let payload = GrantDataStore.RestorePayload(
            snapshot: snapshot,
            archivedRecords: [],
            receivedGrantsData: nil,
            sourceDirectoryURL: nil,
            replacesArchivedRecords: true,
            replacesReceivedGrantsData: true
        )

        _ = try GrantDataStore.writeRestorePayloadToStorage(
            payload,
            expectedReport: GrantDataStore.healthReport(for: snapshot)
        )

        XCTAssertEqual(try sqliteStore.load([GrantDataStore.ArchivedRecordEnvelope].self, named: "archived_records")?.count, 0)
        XCTAssertNil(try sqliteStore.loadData(named: "received_grants"))
    }

    @MainActor
    func testLegacyRestorePreservesAuxiliaryDocumentsWhenBackupDidNotDefineThem() throws {
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        let receivedData = Data("existing-received-grants".utf8)
        try sqliteStore.save(receivedData, named: "received_grants")
        let snapshot = makeSQLiteOnlySnapshot()

        _ = try GrantDataStore.writeRestorePayloadToStorage(
            .init(snapshot: snapshot, archivedRecords: nil, receivedGrantsData: nil),
            expectedReport: GrantDataStore.healthReport(for: snapshot)
        )

        XCTAssertEqual(try sqliteStore.loadData(named: "received_grants"), receivedData)
    }

    @MainActor
    func testInterruptedUncommittedAttachmentRestoreRollsBackFromJournal() throws {
        _ = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        let transactionID = "uncommitted-test"
        let directoryName = "Publication PDFs"
        let destination = GrantDataStore.storageDirectory.appendingPathComponent(directoryName, isDirectory: true)
        let staging = GrantDataStore.storageDirectory.appendingPathComponent(".restore-staging-\(transactionID)", isDirectory: true)
        let previous = staging.appendingPathComponent("previous", isDirectory: true).appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try Data("incoming".utf8).write(to: destination.appendingPathComponent("document.pdf"))
        try Data("original".utf8).write(to: previous.appendingPathComponent("document.pdf"))
        let journal = GrantDataStore.AttachmentRestoreJournal(
            formatVersion: 1,
            transactionID: transactionID,
            destinationPath: GrantDataStore.storageDirectory.path,
            stagingPath: staging.path,
            entries: [.init(directoryName: directoryName, hadPrevious: true)]
        )
        let journalURL = GrantDataStore.storageDirectory.appendingPathComponent(".restore-transaction.json")
        try GrantDataStore.encode(journal, to: journalURL)

        try GrantDataStore.recoverInterruptedRestoreIfNeeded()

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("document.pdf")), Data("original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    @MainActor
    func testInterruptedCommittedAttachmentRestoreFinishesFromJournal() throws {
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        let transactionID = "committed-test"
        let directoryName = "Publication PDFs"
        let destination = GrantDataStore.storageDirectory.appendingPathComponent(directoryName, isDirectory: true)
        let staging = GrantDataStore.storageDirectory.appendingPathComponent(".restore-staging-\(transactionID)", isDirectory: true)
        let previous = staging.appendingPathComponent("previous", isDirectory: true).appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try Data("committed".utf8).write(to: destination.appendingPathComponent("document.pdf"))
        try Data("original".utf8).write(to: previous.appendingPathComponent("document.pdf"))
        let journal = GrantDataStore.AttachmentRestoreJournal(
            formatVersion: 1,
            transactionID: transactionID,
            destinationPath: GrantDataStore.storageDirectory.path,
            stagingPath: staging.path,
            entries: [.init(directoryName: directoryName, hadPrevious: true)]
        )
        let journalURL = GrantDataStore.storageDirectory.appendingPathComponent(".restore-transaction.json")
        try GrantDataStore.encode(journal, to: journalURL)
        try sqliteStore.save(Data(transactionID.utf8), named: "restore_transaction_marker")

        try GrantDataStore.recoverInterruptedRestoreIfNeeded()

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("document.pdf")), Data("committed".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
        XCTAssertNil(try sqliteStore.loadData(named: "restore_transaction_marker"))
    }

    @MainActor
    func testSQLiteOnlyBackupDecodesWithoutJSONSnapshot() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        try GrantDataStore.ensurePublicationPDFsDirectory()
        let livePDFURL = GrantDataStore.managedPublicationPDFURL(forPublicationID: "legacy-live")
        let livePDFData = Data("preserve-this-live-attachment".utf8)
        try livePDFData.write(to: livePDFURL)
        let backupURL = isolatedStorageDirectory.appendingPathComponent("sqlite-only-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        let sqliteStore = try SQLiteDocumentStore(url: backupURL.appendingPathComponent(GrantDataStore.defaultDatabaseFileName))
        try sqliteStore.saveBatch(GrantDataStore.encodedSQLiteDocuments(for: snapshot))
        try sqliteStore.checkpointAndClose()
        try GrantDataStore.encode(GrantDataStore.healthReport(for: snapshot), to: backupURL.appendingPathComponent("health_check.json"))
        try GrantDataStore.writeBackupManifest(in: backupURL)

        let payload = try GrantDataStore.decodeRestorePayload(from: backupURL)
        _ = try GrantDataStore.writeRestorePayloadToStorage(
            payload,
            expectedReport: GrantDataStore.healthReport(for: snapshot)
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.appendingPathComponent("applications.json").path))
        XCTAssertEqual(payload.snapshot.applications.map(\.id), ["application-1"])
        XCTAssertEqual(payload.snapshot.publicationRecords.map(\.id), ["publication-1"])
        XCTAssertEqual(payload.attachmentRestoreMode, .preserveExisting)
        XCTAssertEqual(try Data(contentsOf: livePDFURL), livePDFData)
    }

    func testPersistenceVerificationRejectsMissingSQLiteDocument() throws {
        let databaseURL = isolatedStorageDirectory.appendingPathComponent("missing-document.sqlite")
        let document = DocumentPersistenceWorker.Document(
            storageKey: "applications",
            data: Data("[]".utf8)
        )

        XCTAssertThrowsError(
            try DocumentPersistenceWorker.verify([document], databaseURL: databaseURL)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testOpeningMissingSQLiteWithoutCreationDoesNotCreateFile() throws {
        let databaseURL = isolatedStorageDirectory.appendingPathComponent("must-remain-missing.sqlite")

        XCTAssertThrowsError(
            try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    @MainActor
    func testFutureSchemaDatabaseOpensReadOnlyBeforeBootstrapMaintenance() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let seedStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        try seedStore.saveBatch(GrantDataStore.encodedSQLiteDocuments(for: snapshot))
        var futureMetadata = snapshot.metadata
        futureMetadata.schemaVersion = DataSourceMetadata.currentSchemaVersion + 1
        try seedStore.save(futureMetadata, named: "metadata")
        let metadataUpdatedAt = try XCTUnwrap(seedStore.documentUpdatedAt(named: "metadata"))
        try seedStore.checkpointAndClose()

        let readOnlyStore = try SQLiteDocumentStore(
            url: GrantDataStore.databaseURL,
            createIfMissing: false
        )
        XCTAssertTrue(readOnlyStore.isReadOnly)
        XCTAssertEqual(
            try readOnlyStore.documentUpdatedAt(named: "metadata"),
            metadataUpdatedAt
        )
        XCTAssertThrowsError(
            try readOnlyStore.save(Data("must-not-write".utf8), named: "future-schema-write")
        )
        XCTAssertFalse(try readOnlyStore.containsDocument(named: "future-schema-write"))

        let loadedStore = GrantDataStore.loadFromBundle()

        XCTAssertTrue(loadedStore.hasUnsupportedStorageSchema)
        XCTAssertTrue(loadedStore.sqliteStore?.isReadOnly == true)
        XCTAssertFalse(loadedStore.loadError?.isEmpty ?? true)
        XCTAssertEqual(
            try readOnlyStore.documentUpdatedAt(named: "metadata"),
            metadataUpdatedAt
        )
    }

    func testPhysicalSchemaMigrationsAreOrderedAndIdempotent() throws {
        let databaseURL = isolatedStorageDirectory.appendingPathComponent("ordered-migrations.sqlite")
        let firstStore = try SQLiteDocumentStore(url: databaseURL)
        XCTAssertEqual(try firstStore.appliedSchemaMigrationIDs(), [1, 2, 3, 4])
        try firstStore.checkpointAndClose()

        let reopenedStore = try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        XCTAssertEqual(try reopenedStore.appliedSchemaMigrationIDs(), [1, 2, 3, 4])
        try reopenedStore.checkpointAndClose()
    }

    func testPhysicalSchemaMigrationsUpgradeExistingDatabaseWithoutRewritingDocuments() throws {
        let databaseURL = isolatedStorageDirectory.appendingPathComponent("legacy-physical-schema.sqlite")
        try executeSQLiteFixture(
            at: databaseURL,
            sql: """
            CREATE TABLE documents (
                key TEXT PRIMARY KEY NOT NULL,
                payload BLOB NOT NULL,
                updated_at REAL NOT NULL
            );
            CREATE INDEX idx_documents_updated_at ON documents(updated_at);
            INSERT INTO documents (key, payload, updated_at)
            VALUES ('legacy', X'6C65676163792D7061796C6F6164', 1);
            CREATE TABLE rel_calendar_travel (
                id TEXT PRIMARY KEY NOT NULL,
                date TEXT NOT NULL DEFAULT '',
                arrival_date TEXT NOT NULL DEFAULT '',
                mode TEXT NOT NULL DEFAULT '',
                from_city TEXT NOT NULL DEFAULT '',
                from_country TEXT NOT NULL DEFAULT '',
                to_city TEXT NOT NULL DEFAULT '',
                to_country TEXT NOT NULL DEFAULT '',
                congress_organization_id TEXT,
                congress_id TEXT
            );
            CREATE TABLE rel_calendar_accommodation (
                id TEXT PRIMARY KEY NOT NULL,
                hotel_name TEXT NOT NULL DEFAULT '',
                check_in_date TEXT NOT NULL DEFAULT '',
                check_out_date TEXT NOT NULL DEFAULT '',
                city TEXT NOT NULL DEFAULT '',
                country TEXT NOT NULL DEFAULT '',
                congress_organization_id TEXT,
                congress_id TEXT
            );
            """
        )

        let store = try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        XCTAssertEqual(try store.appliedSchemaMigrationIDs(), [1, 2, 3, 4])
        XCTAssertEqual(try store.loadData(named: "legacy"), Data("legacy-payload".utf8))
        try store.checkpointAndClose()
    }

    func testFuturePhysicalSchemaLedgerOpensReadOnlyWithoutMutation() throws {
        let databaseURL = isolatedStorageDirectory.appendingPathComponent("future-physical-schema.sqlite")
        try executeSQLiteFixture(
            at: databaseURL,
            sql: """
            CREATE TABLE schema_migrations (
                id INTEGER PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                applied_at REAL NOT NULL
            );
            INSERT INTO schema_migrations (id, name, applied_at)
            VALUES (99, 'future', 1);
            """
        )

        let store = try SQLiteDocumentStore(url: databaseURL, createIfMissing: false)
        XCTAssertTrue(store.isReadOnly)
        XCTAssertEqual(try store.appliedSchemaMigrationIDs(), [99])
        XCTAssertThrowsError(try store.save(Data("blocked".utf8), named: "blocked"))
    }

    @MainActor
    func testFailedRestoreVerificationRollsBackSQLiteDocuments() throws {
        let original = makeSQLiteOnlySnapshot()
        let store = GrantDataStore(
            applications: original.applications,
            metadata: original.metadata,
            organizations: original.organizations,
            managers: original.managers,
            projects: original.projects,
            teachingCourses: original.teachingCourses,
            teachingComponents: original.teachingComponents,
            teachingFormats: original.teachingFormats,
            teachingAssignments: original.teachingAssignments,
            doctoralCandidates: original.doctoralCandidates,
            cvPersonalResume: original.cvPersonalResume,
            cvConferenceContributions: original.cvConferenceContributions,
            cvMediaAppearances: original.cvMediaAppearances,
            cvReviewEntries: original.cvReviewEntries,
            cvOtherPublications: original.cvOtherPublications,
            publicationAuthors: original.publicationAuthors,
            publicationJournals: original.publicationJournals,
            publicationRecords: original.publicationRecords,
            skipInitialMigration: true
        )
        try store.persist(.allCoreData, includeBackup: false)
        let incoming = GrantDataStore.Snapshot(
            applications: [],
            metadata: original.metadata,
            organizations: original.organizations,
            managers: original.managers,
            projects: original.projects,
            teachingCourses: original.teachingCourses,
            teachingComponents: original.teachingComponents,
            teachingFormats: original.teachingFormats,
            teachingAssignments: original.teachingAssignments,
            doctoralCandidates: original.doctoralCandidates,
            cvPersonalResume: original.cvPersonalResume,
            cvConferenceContributions: original.cvConferenceContributions,
            cvMediaAppearances: original.cvMediaAppearances,
            cvReviewEntries: original.cvReviewEntries,
            cvOtherPublications: original.cvOtherPublications,
            publicationAuthors: original.publicationAuthors,
            publicationJournals: original.publicationJournals,
            publicationRecords: original.publicationRecords
        )
        let payload = GrantDataStore.RestorePayload(
            snapshot: incoming,
            archivedRecords: nil,
            receivedGrantsData: nil,
            sourceDirectoryURL: nil
        )

        XCTAssertThrowsError(
            try GrantDataStore.writeRestorePayloadToStorage(
                payload,
                expectedReport: GrantDataStore.healthReport(for: original)
            )
        )

        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        let storedApplications = try XCTUnwrap(
            sqliteStore.load([GrantApplication].self, named: "applications")
        )
        XCTAssertEqual(storedApplications.map(\.id), ["application-1"])
    }

    @MainActor
    func testBackupListingIgnoresIncompletePublishedDirectoryAndStagingDirectory() throws {
        try GrantDataStore.ensureBackupDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let incomplete = GrantDataStore.backupsDirectory.appendingPathComponent(
            "\(GrantDataStore.backupFolderName(for: now))-incomplete",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)
        _ = try SQLiteDocumentStore(url: incomplete.appendingPathComponent(GrantDataStore.defaultDatabaseFileName))
        let staging = GrantDataStore.backupsDirectory.appendingPathComponent(
            ".backup-in-progress-test",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let validURL = try GrantDataStore.createForcedBackupSnapshot(
            snapshot: makeSQLiteOnlySnapshot(),
            archivedRecords: [],
            receivedGrantsData: nil,
            prefix: "verified",
            now: now.addingTimeInterval(1)
        )
        let snapshots = try GrantDataStore.loadBackupSnapshots()

        XCTAssertEqual(
            snapshots.map { $0.url.resolvingSymlinksInPath().path },
            [validURL.resolvingSymlinksInPath().path]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: incomplete.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))
    }

    @MainActor
    func testBackupListingIgnoresPreManifestSQLiteBackup() throws {
        try GrantDataStore.ensureBackupDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_200)
        let legacyURL = GrantDataStore.backupsDirectory.appendingPathComponent(
            "\(GrantDataStore.backupFolderName(for: now))-pre-manifest",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: legacyURL, withIntermediateDirectories: true)
        try GrantDataStore.writeSQLiteBackupSnapshot(
            makeSQLiteOnlySnapshot(),
            archivedRecords: [],
            receivedGrantsData: nil,
            to: legacyURL
        )

        XCTAssertNil(
            try GrantDataStore.loadBackupSnapshots().first { $0.url.lastPathComponent == legacyURL.lastPathComponent }
        )
    }

    @MainActor
    func testForcedBackupSnapshotIncludesRestorableSQLiteDatabase() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let backupURL = try GrantDataStore.createForcedBackupSnapshot(
            snapshot: snapshot,
            archivedRecords: [],
            receivedGrantsData: nil,
            prefix: "sqlite-safety",
            now: now
        )

        XCTAssertTrue(
            backupURL.lastPathComponent.hasPrefix(
                "\(GrantDataStore.backupFolderName(for: now))-sqlite-safety-"
            )
        )
        let sqliteURL = backupURL.appendingPathComponent(GrantDataStore.defaultDatabaseFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sqliteURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.appendingPathComponent("applications.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.appendingPathComponent("publication_records.json").path))

        try GrantDataStore.verifyBackupSnapshotPackage(in: backupURL, expectedSnapshot: snapshot)
        let payload = try GrantDataStore.decodeRestorePayload(from: backupURL)
        XCTAssertEqual(payload.snapshot.applications.map(\.id), ["application-1"])
        XCTAssertEqual(payload.snapshot.projects.map(\.id), ["project-1"])
        XCTAssertEqual(payload.snapshot.publicationRecords.map(\.id), ["publication-1"])
    }

    @MainActor
    func testVerifiedBackupPackageStagesBesideFinalExportDestination() throws {
        let exportParent = isolatedStorageDirectory.appendingPathComponent(
            "External Export Volume",
            isDirectory: true
        )
        let finalURL = exportParent.appendingPathComponent(
            "Footprint Export.footprintdb",
            isDirectory: true
        )

        let publishedURL = try GrantDataStore.writeVerifiedBackupPackage(
            snapshot: makeSQLiteOnlySnapshot(),
            archivedRecords: [],
            receivedGrantsData: nil,
            finalDirectory: finalURL
        )

        XCTAssertEqual(publishedURL.standardizedFileURL, finalURL.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.path))
        let remainingNames = try FileManager.default.contentsOfDirectory(atPath: exportParent.path)
        XCTAssertFalse(remainingNames.contains { $0.contains(".backup-in-progress-") })
        try GrantDataStore.verifyBackupSnapshotPackage(
            in: finalURL,
            expectedSnapshot: makeSQLiteOnlySnapshot()
        )
    }

    func testSQLiteBackupDocumentVerificationRejectsSameCountContentChanges() throws {
        let sqliteURL = isolatedStorageDirectory.appendingPathComponent(
            "exact-backup-document-verification.sqlite"
        )
        let sqliteStore = try SQLiteDocumentStore(url: sqliteURL)
        let expectedDocuments = [
            ("applications", Data(#"[{"id":"application-1"}]"#.utf8)),
            ("archived_records", Data(#"[{"id":"archived-1"}]"#.utf8)),
        ]
        try sqliteStore.saveBatch(expectedDocuments)
        try GrantDataStore.verifySQLiteBackupDocuments(
            in: sqliteStore,
            expectedDocuments: expectedDocuments
        )

        try sqliteStore.save(
            Data(#"[{"id":"application-2"}]"#.utf8),
            named: "applications"
        )

        XCTAssertThrowsError(
            try GrantDataStore.verifySQLiteBackupDocuments(
                in: sqliteStore,
                expectedDocuments: expectedDocuments
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("applications:digest"))
        }
    }

    func testUnverifiedBackupCannotEvictVerifiedRecoveryPointDuringPruning() throws {
        let verifiedURL = isolatedStorageDirectory.appendingPathComponent(
            "verified-recovery-point",
            isDirectory: true
        )
        let unverifiedURL = isolatedStorageDirectory.appendingPathComponent(
            "new-unverified-backup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: verifiedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unverifiedURL, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_450)

        // Aged past the unverified-prune grace window; a fresh unverified
        // snapshot is deliberately kept (see the grace test below).
        try GrantDataStore.pruneBackupSnapshots(
            [
                .init(url: unverifiedURL, date: now.addingTimeInterval(-7 * 3600), isVerified: false),
                .init(url: verifiedURL, date: now.addingTimeInterval(-8 * 3600), isVerified: true),
            ],
            now: now
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: verifiedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unverifiedURL.path))
    }

    func testFreshUnverifiedBackupSurvivesPruning() throws {
        let unverifiedURL = isolatedStorageDirectory.appendingPathComponent(
            "fresh-unverified-backup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: unverifiedURL, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_450)

        // A backup whose completion marker crashed moments ago is still the
        // freshest copy of the data; pruning must give it a grace window.
        try GrantDataStore.pruneBackupSnapshots(
            [.init(url: unverifiedURL, date: now.addingTimeInterval(-60), isVerified: false)],
            now: now
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: unverifiedURL.path))
    }

    func testBackupPruningSurfacesDeletionFailures() throws {
        let missingURL = isolatedStorageDirectory.appendingPathComponent(
            "already-missing-unverified-backup",
            isDirectory: true
        )
        let now = Date(timeIntervalSince1970: 1_800_000_451)

        XCTAssertThrowsError(
            try GrantDataStore.pruneBackupSnapshots(
                [.init(url: missingURL, date: now.addingTimeInterval(-7 * 3600), isVerified: false)],
                now: now
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("could not be removed"))
            XCTAssertTrue(error.localizedDescription.contains(missingURL.lastPathComponent))
        }
    }

    func testSupportScriptResolutionReturnsRegularNonSymlinkedResource() throws {
        let scriptURL = try GrantDataStore.supportScriptURL(named: "export_grants.py")
        let values = try scriptURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )

        XCTAssertEqual(values.isRegularFile, true)
        XCTAssertNotEqual(values.isSymbolicLink, true)
    }

    @MainActor
    func testForcedBackupsWithSameTimestampAndPrefixDoNotCollide() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let now = Date(timeIntervalSince1970: 1_800_000_452)

        let firstURL = try GrantDataStore.createForcedBackupSnapshot(
            snapshot: snapshot,
            archivedRecords: [],
            receivedGrantsData: nil,
            prefix: "collision-test",
            now: now
        )
        let secondURL = try GrantDataStore.createForcedBackupSnapshot(
            snapshot: snapshot,
            archivedRecords: [],
            receivedGrantsData: nil,
            prefix: "collision-test",
            now: now
        )

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertTrue(firstURL.lastPathComponent.contains("-collision-test-"))
        XCTAssertTrue(secondURL.lastPathComponent.contains("-collision-test-"))
    }

    @MainActor
    func testPeriodicBackupQueueSerializesAndRateLimitsAutomaticSnapshots() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let store = GrantDataStore(
            applications: snapshot.applications,
            metadata: snapshot.metadata,
            organizations: snapshot.organizations,
            projects: snapshot.projects,
            teachingCourses: snapshot.teachingCourses,
            teachingComponents: snapshot.teachingComponents,
            teachingFormats: snapshot.teachingFormats,
            teachingAssignments: snapshot.teachingAssignments,
            doctoralCandidates: snapshot.doctoralCandidates,
            cvPersonalResume: snapshot.cvPersonalResume,
            cvConferenceContributions: snapshot.cvConferenceContributions,
            cvMediaAppearances: snapshot.cvMediaAppearances,
            cvReviewEntries: snapshot.cvReviewEntries,
            cvOtherPublications: snapshot.cvOtherPublications,
            publicationAuthors: snapshot.publicationAuthors,
            publicationJournals: snapshot.publicationJournals,
            publicationRecords: snapshot.publicationRecords,
            skipInitialMigration: true
        )
        let now = Date(timeIntervalSince1970: 1_800_004_000)

        store.enqueuePeriodicBackupSnapshotIfNeeded(now: now)
        store.enqueuePeriodicBackupSnapshotIfNeeded(now: now.addingTimeInterval(1))

        XCTAssertTrue(store.waitForPendingPeriodicBackup(timeout: 10))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let snapshots = try GrantDataStore.loadBackupSnapshots()
        XCTAssertEqual(snapshots.filter(\.isVerified).count, 1)
        XCTAssertNil(store.loadError)
        let backupNames = try FileManager.default.contentsOfDirectory(
            atPath: GrantDataStore.backupsDirectory.path
        )
        XCTAssertFalse(backupNames.contains { $0.contains(".backup-in-progress-") })
    }

    @MainActor
    func testPeriodicBackupFailureSurfacesOnMainActor() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let store = GrantDataStore(
            applications: snapshot.applications,
            metadata: snapshot.metadata,
            projects: snapshot.projects,
            publicationAuthors: snapshot.publicationAuthors,
            publicationJournals: snapshot.publicationJournals,
            publicationRecords: snapshot.publicationRecords,
            skipInitialMigration: true
        )
        let now = Date(timeIntervalSince1970: 1_800_005_000)
        try GrantDataStore.ensureBackupDirectory()
        let collidingDirectory = GrantDataStore.backupsDirectory.appendingPathComponent(
            GrantDataStore.backupFolderName(for: now),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: collidingDirectory,
            withIntermediateDirectories: true
        )

        store.enqueuePeriodicBackupSnapshotIfNeeded(now: now)

        XCTAssertTrue(store.waitForPendingPeriodicBackup(timeout: 10))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(store.loadError?.contains("same timestamp") == true)
        XCTAssertNotNil(store.notice)
    }

    @MainActor
    func testDestructiveRestoreRequiresCompleteRootManifestInventory() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let backupURL = isolatedStorageDirectory.appendingPathComponent(
            "strict-root-manifest-backup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try GrantDataStore.writeSQLiteBackupSnapshot(
            snapshot,
            archivedRecords: [],
            receivedGrantsData: nil,
            to: backupURL
        )

        XCTAssertThrowsError(try GrantDataStore.decodeRestorePayload(from: backupURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("manifest is missing"))
        }

        try GrantDataStore.writeBackupManifest(in: backupURL)
        try Data("not-listed".utf8).write(to: backupURL.appendingPathComponent("unexpected.txt"))
        XCTAssertThrowsError(try GrantDataStore.decodeRestorePayload(from: backupURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("not-in-manifest"))
        }
    }

    @MainActor
    func testDestructiveRestoreRequiresMatchingCompletionMarkerForModernBackup() throws {
        let backupURL = isolatedStorageDirectory.appendingPathComponent(
            "missing-completion-marker-backup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try GrantDataStore.writeSQLiteBackupSnapshot(
            makeSQLiteOnlySnapshot(),
            archivedRecords: [],
            receivedGrantsData: nil,
            to: backupURL
        )
        try GrantDataStore.writeBackupManifest(in: backupURL)

        XCTAssertThrowsError(try GrantDataStore.decodeRestorePayload(from: backupURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("completion marker"))
        }

        try GrantDataStore.writeBackupCompletionMarker(in: backupURL)
        _ = try GrantDataStore.decodeRestorePayload(from: backupURL)
    }

    @MainActor
    func testDestructiveRestoreRejectsNewerMetadataSchema() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let backupURL = isolatedStorageDirectory.appendingPathComponent(
            "future-schema-backup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try GrantDataStore.writeSQLiteBackupSnapshot(
            snapshot,
            archivedRecords: [],
            receivedGrantsData: nil,
            to: backupURL
        )
        var futureMetadata = snapshot.metadata
        futureMetadata.schemaVersion = DataSourceMetadata.currentSchemaVersion + 1
        let sqliteStore = try SQLiteDocumentStore(
            url: backupURL.appendingPathComponent(GrantDataStore.defaultDatabaseFileName)
        )
        try sqliteStore.save(futureMetadata, named: "metadata")
        try sqliteStore.checkpointAndClose()
        try GrantDataStore.writeBackupManifest(in: backupURL)
        try GrantDataStore.writeBackupCompletionMarker(in: backupURL)

        XCTAssertThrowsError(try GrantDataStore.decodeRestorePayload(from: backupURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("newer than this app supports"))
        }
    }

    @MainActor
    func testSQLiteBackupIncludesAndRestoresManagedAttachmentManifest() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        try GrantDataStore.ensurePublicationPDFsDirectory()
        let pdfURL = GrantDataStore.managedPublicationPDFURL(forPublicationID: "publication-1")
        let pdfData = Data("publication-pdf".utf8)
        try pdfData.write(to: pdfURL)

        let backupURL = isolatedStorageDirectory.appendingPathComponent("sqlite-attachment-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try GrantDataStore.writeSQLiteBackupSnapshot(
            snapshot,
            archivedRecords: [],
            receivedGrantsData: nil,
            to: backupURL
        )
        try GrantDataStore.writeBackupManifest(in: backupURL)
        try GrantDataStore.writeBackupCompletionMarker(in: backupURL)

        let attachmentManifestURL = backupURL.appendingPathComponent("attachments_manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentManifestURL.path))
        try GrantDataStore.verifyAttachmentManifest(in: backupURL)

        try FileManager.default.removeItem(at: GrantDataStore.publicationPDFsDirectory)
        let payload = try GrantDataStore.decodeRestorePayload(from: backupURL)
        XCTAssertEqual(payload.attachmentRestoreMode, .replaceWithVerifiedBackup)
        _ = try GrantDataStore.writeRestorePayloadToStorage(payload, expectedReport: GrantDataStore.healthReport(for: snapshot))

        XCTAssertEqual(try Data(contentsOf: pdfURL), pdfData)
    }

    @MainActor
    func testAttachmentManifestRejectsUnlistedFiles() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let backupURL = isolatedStorageDirectory.appendingPathComponent(
            "sqlite-attachment-extra-file-backup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try GrantDataStore.writeSQLiteBackupSnapshot(
            snapshot,
            archivedRecords: [],
            receivedGrantsData: nil,
            to: backupURL
        )
        let unlistedDirectory = backupURL.appendingPathComponent("Publication PDFs", isDirectory: true)
        try FileManager.default.createDirectory(at: unlistedDirectory, withIntermediateDirectories: true)
        try Data("unlisted".utf8).write(to: unlistedDirectory.appendingPathComponent("unlisted.pdf"))

        XCTAssertThrowsError(try GrantDataStore.verifyAttachmentManifest(in: backupURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("not-in-manifest"))
        }
    }

    @MainActor
    func testRecoveryQuarantineMovesSQLiteWALAndSHMOutOfLiveLocation() throws {
        try GrantDataStore.ensureStorageDirectory()
        let databaseData = Data("database-bytes".utf8)
        let walData = Data("wal-bytes".utf8)
        let shmData = Data("shm-bytes".utf8)
        try databaseData.write(to: GrantDataStore.databaseURL)
        try walData.write(to: GrantDataStore.databaseWALURL)
        try shmData.write(to: GrantDataStore.databaseSHMURL)

        let quarantineURL = try GrantDataStore.quarantineCurrentSQLiteStoreBeforeRecovery(
            reason: "test",
            now: Date(timeIntervalSince1970: 1_800_002_000)
        )

        XCTAssertEqual(
            try Data(contentsOf: quarantineURL.appendingPathComponent(GrantDataStore.databaseURL.lastPathComponent)),
            databaseData
        )
        XCTAssertEqual(
            try Data(contentsOf: quarantineURL.appendingPathComponent(GrantDataStore.databaseWALURL.lastPathComponent)),
            walData
        )
        XCTAssertEqual(
            try Data(contentsOf: quarantineURL.appendingPathComponent(GrantDataStore.databaseSHMURL.lastPathComponent)),
            shmData
        )
        // The live location must be cleared, or every reopen after recovery
        // keeps failing on the damaged files the quarantine preserved above.
        XCTAssertFalse(FileManager.default.fileExists(atPath: GrantDataStore.databaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: GrantDataStore.databaseWALURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: GrantDataStore.databaseSHMURL.path))
    }

    @MainActor
    func testSQLiteBackupCopiesAndRestoresSnapshotReferencedExternalPDFs() throws {
        let baseSnapshot = makeSQLiteOnlySnapshot()
        let externalDirectory = isolatedStorageDirectory.appendingPathComponent("External PDFs", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)

        let publicationPDFURL = externalDirectory.appendingPathComponent("publication-source.pdf")
        let publicationPDFData = Data("external-publication-pdf".utf8)
        try publicationPDFData.write(to: publicationPDFURL)

        var publication = baseSnapshot.publicationRecords[0]
        publication.finalPDFFilename = publicationPDFURL.lastPathComponent
        publication.finalPDFPath = publicationPDFURL.path

        let mediaPDFURL = externalDirectory.appendingPathComponent("media-source.pdf")
        let mediaPDFData = Data("external-media-pdf".utf8)
        try mediaPDFData.write(to: mediaPDFURL)
        let mediaAppearance = CVMediaAppearance(
            id: "media-1",
            date: "2026-05-26",
            title: "Media",
            pdfFilename: mediaPDFURL.lastPathComponent,
            pdfPath: mediaPDFURL.path
        )

        let snapshot = GrantDataStore.Snapshot(
            applications: baseSnapshot.applications,
            metadata: baseSnapshot.metadata,
            organizations: baseSnapshot.organizations,
            managers: baseSnapshot.managers,
            projects: baseSnapshot.projects,
            teachingCourses: baseSnapshot.teachingCourses,
            teachingComponents: baseSnapshot.teachingComponents,
            teachingFormats: baseSnapshot.teachingFormats,
            teachingAssignments: baseSnapshot.teachingAssignments,
            doctoralCandidates: baseSnapshot.doctoralCandidates,
            cvPersonalResume: baseSnapshot.cvPersonalResume,
            cvConferenceContributions: baseSnapshot.cvConferenceContributions,
            cvMediaAppearances: [mediaAppearance],
            cvReviewEntries: baseSnapshot.cvReviewEntries,
            cvOtherPublications: baseSnapshot.cvOtherPublications,
            publicationAuthors: baseSnapshot.publicationAuthors,
            publicationJournals: baseSnapshot.publicationJournals,
            publicationRecords: [publication]
        )

        let backupURL = isolatedStorageDirectory.appendingPathComponent("sqlite-external-attachment-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try GrantDataStore.writeSQLiteBackupSnapshot(
            snapshot,
            archivedRecords: [],
            receivedGrantsData: nil,
            to: backupURL
        )
        try GrantDataStore.writeBackupManifest(in: backupURL)
        try GrantDataStore.writeBackupCompletionMarker(in: backupURL)
        try GrantDataStore.verifyAttachmentManifest(in: backupURL)

        let backedUpPublicationPDF = backupURL
            .appendingPathComponent("Publication PDFs", isDirectory: true)
            .appendingPathComponent("publication-1.pdf")
        let backedUpMediaPDF = backupURL
            .appendingPathComponent("Media Appearance PDFs", isDirectory: true)
            .appendingPathComponent("media-1.pdf")
        XCTAssertEqual(try Data(contentsOf: backedUpPublicationPDF), publicationPDFData)
        XCTAssertEqual(try Data(contentsOf: backedUpMediaPDF), mediaPDFData)

        let payload = try GrantDataStore.decodeRestorePayload(from: backupURL)
        _ = try GrantDataStore.writeRestorePayloadToStorage(payload, expectedReport: GrantDataStore.healthReport(for: snapshot))

        XCTAssertEqual(
            try Data(contentsOf: GrantDataStore.managedPublicationPDFURL(forPublicationID: "publication-1")),
            publicationPDFData
        )
        XCTAssertEqual(
            try Data(contentsOf: GrantDataStore.managedCVMediaAppearancePDFURL(forMediaAppearanceID: "media-1")),
            mediaPDFData
        )
    }

    @MainActor
    func testSQLiteRelationalSearchIndexAndHealthChecksArePopulated() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        let sqliteStore = try SQLiteDocumentStore(url: isolatedStorageDirectory.appendingPathComponent("search-index.sqlite"))

        try sqliteStore.saveBatch(GrantDataStore.encodedSQLiteDocuments(for: snapshot))

        let health = try sqliteStore.storageHealthSummary()
        XCTAssertTrue(health.integrityCheckPassed)
        XCTAssertTrue(health.quickCheckPassed)
        XCTAssertEqual(health.foreignKeyViolationCount, 0)
        XCTAssertGreaterThan(health.searchIndexCount, 0)
    }

    @MainActor
    func testRestoreStopsWhenSQLiteBackupIsIncompleteInsteadOfFallingBackToJSON() throws {
        let backupURL = isolatedStorageDirectory.appendingPathComponent("mixed-incomplete-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        let sqliteStore = try SQLiteDocumentStore(url: backupURL.appendingPathComponent(GrantDataStore.defaultDatabaseFileName))
        try sqliteStore.save(
            [GrantApplication(id: "stale-application", rowNumber: 1, organization: "Old", grantName: "Old")],
            named: "applications"
        )
        try GrantDataStore.writeBackupManifest(in: backupURL)

        XCTAssertThrowsError(try GrantDataStore.decodeRestorePayload(from: backupURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("SQLite backup is incomplete"))
        }
    }

    @MainActor
    func testStorageDiagnosticsRefreshAfterSQLiteWrite() throws {
        let currentProject = ProjectRecord(id: "project-1", nameSv: "Current", nameEn: "Current")
        let staleProject = ProjectRecord(id: "project-1", nameSv: "Stale", nameEn: "Stale")
        let store = GrantDataStore(projects: [currentProject], skipInitialMigration: true)
        let sqliteStore = try XCTUnwrap(store.sqliteStore)
        try sqliteStore.save([GrantApplication](), named: "applications")
        try sqliteStore.save([staleProject], named: "projects")
        try sqliteStore.save([PublicationAuthor](), named: "publication_authors")
        try sqliteStore.save([PublicationRecord](), named: "publication_records")

        let warningDiagnostic = try XCTUnwrap(store.dataStructureDiagnostics().first { $0.id == "sqlite-primary-core-registers" })
        XCTAssertEqual(
            warningDiagnostic.details.first(where: { $0.id == "project-reason" })?.value,
            "projects-content-mismatch"
        )
        XCTAssertEqual(store.projectsForRead.map(\.nameSv), ["Current"])
        XCTAssertEqual(
            warningDiagnostic.details.first(where: { $0.id == "project-source" })?.value,
            "SQLite (1)"
        )

        try store.persist(.projects, includeBackup: false)

        let refreshedDiagnostic = try XCTUnwrap(store.dataStructureDiagnostics().first { $0.id == "sqlite-primary-core-registers" })
        XCTAssertEqual(
            refreshedDiagnostic.details.first(where: { $0.id == "project-source" })?.value,
            "SQLite (1)"
        )
        XCTAssertEqual(
            refreshedDiagnostic.details.first(where: { $0.id == "project-reason" })?.value,
            "Primary SQLite"
        )
    }

    @MainActor
    func testAuthoritativeReadKeepsAcceptedMemoryWhenDiagnosticDocumentIsMissing() throws {
        let inMemoryApplication = GrantApplication(
            id: "memory-only",
            rowNumber: 1,
            organization: "In-memory funder",
            grantName: "In-memory grant"
        )
        let store = GrantDataStore(
            applications: [inMemoryApplication],
            skipInitialMigration: true
        )
        let sqliteStore = try XCTUnwrap(store.sqliteStore)
        try sqliteStore.deleteDocuments(named: ["applications"])

        XCTAssertEqual(store.applicationsForRead.map(\.id), ["memory-only"])
        let diagnostic = try XCTUnwrap(
            store.dataStructureDiagnostics().first { $0.id == "sqlite-primary-core-registers" }
        )
        XCTAssertEqual(
            diagnostic.details.first(where: { $0.id == "application-reason" })?.value,
            "applications-document-missing"
        )
        XCTAssertTrue(["Unavailable", "Otillgänglig"].contains(diagnostic.value))
    }

    private func makeSQLiteOnlySnapshot() -> GrantDataStore.Snapshot {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = AppLanguage.swedish.rawValue
        metadata.calendarTravelRecords = []
        metadata.calendarAccommodationRecords = []
        metadata.calendarMeetingRecords = []
        metadata.calendarVerticalNoteRecords = []
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organisation",
            nameEn: "Organization",
            roles: [.grantProvider]
        )
        let project = ProjectRecord(id: "project-1", nameSv: "Projekt", nameEn: "Project")
        let application = GrantApplication(
            id: "application-1",
            rowNumber: 1,
            organizationID: organization.id,
            organization: "Organisation",
            grantName: "Anslag",
            projectID: project.id
        )
        let author = PublicationAuthor(id: "author-1", name: "Anna Andersson")
        let journal = PublicationJournal(id: "journal-1", name: "Journal")
        let publication = PublicationRecord(
            id: "publication-1",
            projectID: project.id,
            projectName: project.nameSv,
            title: "Publication",
            authorNames: [author.name]
        )

        return GrantDataStore.Snapshot(
            applications: [application],
            metadata: metadata,
            organizations: [organization],
            managers: [],
            projects: [project],
            teachingCourses: [],
            teachingComponents: [],
            teachingFormats: [],
            teachingAssignments: [],
            doctoralCandidates: [],
            cvPersonalResume: CVPersonalResume(),
            cvConferenceContributions: [],
            cvMediaAppearances: [],
            cvReviewEntries: [],
            cvOtherPublications: [],
            publicationAuthors: [author],
            publicationJournals: [journal],
            publicationRecords: [publication]
        )
    }

    @MainActor
    func testIntegrityIssuesDetectBrokenCongressParticipantAndFundingIDs() {
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organisation",
            nameEn: "Organization",
            congresses: [
                OrganizationCongress(
                    id: "congress-1",
                    title: "Congress",
                    participantAuthorIDs: ["missing-author"],
                    fundingApplicationIDs: ["missing-application"]
                )
            ]
        )
        let store = GrantDataStore(
            organizations: [organization],
            publicationAuthors: [],
            skipInitialMigration: true
        )

        let subtitles = Set(store.integrityIssues(includeHidden: true).map(\.subtitle))

        // The participant-ID check now lives in the organizations loop and
        // routes to the congress record that holds the stale link.
        XCTAssertTrue(subtitles.contains("Congress participant ID links to missing researcher"))
        XCTAssertTrue(subtitles.contains("Congress funding links to missing grant"))
    }

    @MainActor
    func testStructureDiagnosticsExposeCoreStorageHealth() {
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organisation",
            nameEn: "Organization",
            congresses: [
                OrganizationCongress(id: "congress-1", title: "Congress")
            ]
        )
        let store = GrantDataStore(
            metadata: .bundledDefault,
            organizations: [organization],
            skipInitialMigration: true
        )

        let diagnosticIDs = Set(store.dataStructureDiagnostics().map(\.id))
        let relationalSQLiteDiagnostic = store.dataStructureDiagnostics().first { $0.id == "relational-sqlite" }

        XCTAssertTrue(diagnosticIDs.contains("schema-version"))
        XCTAssertTrue(diagnosticIDs.contains("congresses-document"))
        XCTAssertTrue(diagnosticIDs.contains("calendar-owned-planning"))
        XCTAssertTrue(diagnosticIDs.contains("relationship-index"))
        XCTAssertTrue(diagnosticIDs.contains("relational-sqlite"))
        XCTAssertTrue(diagnosticIDs.contains("relational-sqlite-indexes"))
        XCTAssertTrue(diagnosticIDs.contains("startup-storage-readiness"))
        XCTAssertTrue(diagnosticIDs.contains("active-storage-mode"))
        XCTAssertTrue(diagnosticIDs.contains("database-lock"))
        XCTAssertTrue(diagnosticIDs.contains("sqlite-primary-core-registers"))
        XCTAssertTrue(diagnosticIDs.contains("sqlite-primary-congresses"))
        XCTAssertTrue(diagnosticIDs.contains("sqlite-primary-calendar-planning"))
        XCTAssertTrue(diagnosticIDs.contains("app-settings"))
        XCTAssertTrue(diagnosticIDs.contains("backup-count"))
        XCTAssertTrue(relationalSQLiteDiagnostic?.details.contains { $0.id == "rel_calendar_travel" } == true)
        let databaseLockDiagnostic = store.dataStructureDiagnostics().first { $0.id == "database-lock" }
        XCTAssertEqual(
            databaseLockDiagnostic?.details.first { $0.id == "contract" }?.value,
            FootprintStorageContract.version
        )
        XCTAssertEqual(
            databaseLockDiagnostic?.details.first { $0.id == "canonical-store" }?.value,
            FootprintStorageContract.canonicalStore
        )
    }

    @MainActor
    func testDatabaseLockDiagnosticPassesForSQLiteOnlyModernIDsAndCleanRelations() throws {
        let organizationID = UUID().uuidString
        let projectID = UUID().uuidString
        let applicationID = UUID().uuidString
        let authorID = UUID().uuidString
        let publicationID = UUID().uuidString
        let congressID = UUID().uuidString
        var metadata = DataSourceMetadata.bundledDefault
        metadata.schemaVersion = DataSourceMetadata.currentSchemaVersion
        metadata.calendarTravelRecords = []
        metadata.calendarAccommodationRecords = []
        metadata.calendarMeetingRecords = []
        metadata.calendarVerticalNoteRecords = []

        let store = GrantDataStore(
            applications: [
                GrantApplication(
                    id: applicationID,
                    rowNumber: 1,
                    organizationID: organizationID,
                    organization: "Organisation",
                    grantName: "Grant",
                    projectID: projectID
                )
            ],
            metadata: metadata,
            organizations: [
                OrganizationRecord(
                    id: organizationID,
                    nameSv: "Organisation",
                    nameEn: "Organization",
                    congresses: [OrganizationCongress(id: congressID, title: "Congress")]
                )
            ],
            projects: [ProjectRecord(id: projectID, nameSv: "Project", nameEn: "Project")],
            publicationAuthors: [PublicationAuthor(id: authorID, name: "Ada Lovelace")],
            publicationRecords: [
                PublicationRecord(
                    id: publicationID,
                    projectID: projectID,
                    title: "Publication",
                    authorNames: ["Ada Lovelace"]
                )
            ],
            skipInitialMigration: true
        )

        try store.persist(.allCoreData, includeBackup: false)

        let databaseLockDiagnostic = try XCTUnwrap(store.dataStructureDiagnostics().first { $0.id == "database-lock" })
        XCTAssertEqual(databaseLockDiagnostic.value, "Ready")
        XCTAssertEqual(databaseLockDiagnostic.details.first { $0.id == "sqlite-only" }?.value, "Yes")
        XCTAssertEqual(databaseLockDiagnostic.details.first { $0.id == "uuid-ids" }?.value, "Yes")
        XCTAssertEqual(databaseLockDiagnostic.details.first { $0.id == "relational-indexes" }?.value, "Yes")
        XCTAssertEqual(databaseLockDiagnostic.details.first { $0.id == "backup-restore" }?.value, "SQLite")
    }

    @MainActor
    // Historical ID-alias migration was deliberately retired with the JSON cutover.
    // Keep the fixture temporarily for reference, but exclude it from XCTest discovery.
    func retiredLegacyFirstClassIDMigrationFixture() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.schemaVersion = 8
        metadata.migrationLog = []
        metadata.currentUserAuthorID = "author-1"
        metadata.lastSelectedApplicationID = "application-1"
        metadata.lastSelectedProjectID = "project-1"
        metadata.lastSelectedOrganizationID = "organization-1"
        metadata.lastSelectedJournalID = "journal-1"
        metadata.lastSelectedPublicationID = "publication-1"
        metadata.lastSelectedTeachingID = "teaching-1"
        metadata.lastSelectedDoctoralCandidateID = "doctoral-1"
        metadata.calendarTravelRecords = [
            CalendarTravelRecord(
                id: "travel-1",
                date: "2026-09-10",
                arrivalDate: "2026-09-10",
                departureTime: "12:30",
                fromCity: "Stockholm",
                arrivalTime: "13:25",
                toCity: "Oslo",
                congressOrganizationID: "organization-1",
                congressID: "congress-1"
            )
        ]
        metadata.calendarAccommodationRecords = [
            CalendarAccommodationRecord(
                id: "hotel-1",
                hotelName: "Congress Hotel",
                checkInDate: "2026-09-10",
                checkOutDate: "2026-09-12",
                congressOrganizationID: "organization-1",
                congressID: "congress-1"
            )
        ]
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: "meeting-1",
                date: "2026-09-10",
                title: "Meeting",
                projectIDs: ["project-1"],
                organizationIDs: ["organization-1"],
                applicationIDs: ["application-1"],
                publicationIDs: ["publication-1"],
                projectID: "project-1",
                researcherID: "author-1",
                organizationID: "organization-1"
            )
        ]
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organisation",
            nameEn: "Organization",
            congresses: [
                OrganizationCongress(
                    id: "congress-1",
                    title: "Congress",
                    participantAuthorIDs: ["author-1"],
                    fundingApplicationIDs: ["application-1"]
                )
            ]
        )
        let project = ProjectRecord(
            id: "project-1",
            nameSv: "Projekt",
            nameEn: "Project",
            projectTasks: [
                ProjectTaskItem(id: "project-task-1", publicationID: "publication-1", applicationID: "application-1")
            ]
        )
        let application = GrantApplication(
            id: "application-1",
            rowNumber: 1,
            organizationID: "organization-1",
            organization: "Organisation",
            grantName: "Anslag",
            projectID: "project-1",
            applicationManagerID: "organization-1",
            applicationManager: "Organisation"
        )
        let author = PublicationAuthor(id: "author-1", name: "Ada Lovelace")
        let journal = PublicationJournal(id: "journal-1", name: "Journal")
        let publication = PublicationRecord(
            id: "publication-1",
            projectID: "project-1",
            title: "Publication",
            authorNames: ["Ada Lovelace"]
        )
        let contribution = CVConferenceContribution(
            id: "contribution-1",
            title: "Abstract",
            contributorAuthorIDs: ["author-1"],
            presentedByAuthorID: "author-1",
            congressOrganizationID: "organization-1",
            congressID: "congress-1",
            journalID: "journal-1"
        )
        let teachingCourse = TeachingCourse(id: "course-1", name: "Course", institutionID: "organization-1")
        let teachingComponent = TeachingComponent(id: "component-1", name: "Lecture", allowedContextIDs: ["course-1"])
        let teachingAssignment = TeachingAssignment(
            id: "teaching-1",
            authorID: "author-1",
            contextID: "course-1",
            activityID: "component-1"
        )
        let doctoralCandidate = DoctoralCandidateRecord(
            id: "doctoral-1",
            candidateAuthorID: "author-1",
            institutionID: "organization-1",
            linkedProjectID: "project-1",
            linkedPublicationIDs: ["publication-1"],
            sourceAssignmentIDs: ["teaching-1"]
        )
        let store = GrantDataStore(
            applications: [application],
            metadata: metadata,
            organizations: [organization],
            projects: [project],
            teachingCourses: [teachingCourse],
            teachingComponents: [teachingComponent],
            teachingAssignments: [teachingAssignment],
            doctoralCandidates: [doctoralCandidate],
            cvConferenceContributions: [contribution],
            cvMediaAppearances: [CVMediaAppearance(id: "media-1", authorID: "author-1")],
            cvReviewEntries: [CVReviewEntry(id: "review-1", authorID: "author-1")],
            cvOtherPublications: [CVOtherPublicationEntry(id: "other-publication-1")],
            publicationAuthors: [author],
            publicationJournals: [journal],
            publicationRecords: [publication],
            skipInitialMigration: true
        )

        XCTAssertTrue(store.migrateRecordsIfNeeded())
        let aliases = try XCTUnwrap(store.metadata.idAliases)
        let aliasLookup = Dictionary(uniqueKeysWithValues: aliases.map { ("\($0.entityType)#\($0.oldID)", $0.newID) })
        func migratedID(_ entityType: String, _ oldID: String) throws -> String {
            let newID = try XCTUnwrap(aliasLookup["\(entityType)#\(oldID)"])
            XCTAssertNotEqual(newID, oldID)
            XCTAssertNotNil(UUID(uuidString: newID))
            return newID
        }

        let newApplicationID = try migratedID("application", "application-1")
        let newOrganizationID = try migratedID("organization", "organization-1")
        let newProjectID = try migratedID("project", "project-1")
        let newAuthorID = try migratedID("publication_author", "author-1")
        let newJournalID = try migratedID("publication_journal", "journal-1")
        let newPublicationID = try migratedID("publication", "publication-1")
        let newCongressID = try migratedID("congress", "congress-1")

        XCTAssertEqual(store.applications.first?.id, newApplicationID)
        XCTAssertEqual(store.applications.first?.organizationID, newOrganizationID)
        XCTAssertEqual(store.applications.first?.projectID, newProjectID)
        XCTAssertEqual(store.applications.first?.applicationManagerID, newOrganizationID)
        XCTAssertEqual(store.projects.first?.projectTasks.first?.publicationID, newPublicationID)
        XCTAssertEqual(store.projects.first?.projectTasks.first?.applicationID, newApplicationID)
        XCTAssertEqual(store.organizations.first?.id, newOrganizationID)
        XCTAssertEqual(store.organizations.first?.congresses.first?.id, newCongressID)
        XCTAssertEqual(store.organizations.first?.congresses.first?.participantAuthorIDs, [newAuthorID])
        XCTAssertEqual(store.organizations.first?.congresses.first?.fundingApplicationIDs, [newApplicationID])
        XCTAssertEqual(store.publicationRecords.first?.id, newPublicationID)
        XCTAssertEqual(store.publicationRecords.first?.projectID, newProjectID)
        XCTAssertEqual(store.cvConferenceContributions.first?.congressOrganizationID, newOrganizationID)
        XCTAssertEqual(store.cvConferenceContributions.first?.congressID, newCongressID)
        XCTAssertEqual(store.cvConferenceContributions.first?.contributorAuthorIDs, [newAuthorID])
        XCTAssertEqual(store.cvConferenceContributions.first?.presentedByAuthorID, newAuthorID)
        XCTAssertEqual(store.cvConferenceContributions.first?.journalID, newJournalID)
        XCTAssertEqual(store.calendarTravelRecords.first?.congressOrganizationID, newOrganizationID)
        XCTAssertEqual(store.calendarTravelRecords.first?.congressID, newCongressID)
        XCTAssertEqual(store.calendarAccommodationRecords.first?.congressOrganizationID, newOrganizationID)
        XCTAssertEqual(store.calendarAccommodationRecords.first?.congressID, newCongressID)

        let idDiagnostic = try XCTUnwrap(store.dataStructureDiagnostics().first { $0.id == "first-class-record-ids" })
        XCTAssertEqual(idDiagnostic.details.first { $0.id == "legacy-ids" }?.value, "0")
        XCTAssertGreaterThan(Int(idDiagnostic.details.first { $0.id == "aliases" }?.value ?? "0") ?? 0, 0)
        XCTAssertFalse(store.migrateRecordsIfNeeded())
        XCTAssertEqual(store.metadata.idAliases?.count, aliases.count)

        try store.persist(.allCoreData, includeBackup: false)
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        XCTAssertEqual(try sqliteStore.idAliasCount(), aliases.count)
        XCTAssertEqual(try sqliteStore.relationalIntegritySummary().brokenReferenceCount, 0)
    }

    @MainActor
    func retiredCurrentSchemaLegacyIDMigrationFixture() throws {
        let organizationID = UUID().uuidString
        let suffixedCongressID = "\(UUID().uuidString)-2"
        var metadata = DataSourceMetadata.bundledDefault
        metadata.schemaVersion = DataSourceMetadata.currentSchemaVersion
        metadata.idAliases = []
        let store = GrantDataStore(
            metadata: metadata,
            organizations: [
                OrganizationRecord(
                    id: organizationID,
                    nameSv: "World Heart Federation",
                    nameEn: "World Heart Federation",
                    congresses: [
                        OrganizationCongress(
                            id: suffixedCongressID,
                            title: "World Congress of Cardiology 2025"
                        )
                    ]
                )
            ],
            skipInitialMigration: true
        )

        let initialDiagnostic = try XCTUnwrap(store.dataStructureDiagnostics().first { $0.id == "first-class-record-ids" })
        XCTAssertEqual(initialDiagnostic.details.first { $0.id == "legacy-ids" }?.value, "1")

        XCTAssertTrue(store.migrateRecordsIfNeeded())

        let migratedCongressID = try XCTUnwrap(store.organizations.first?.congresses.first?.id)
        XCTAssertNotEqual(migratedCongressID, suffixedCongressID)
        XCTAssertNotNil(UUID(uuidString: migratedCongressID))
        let alias = try XCTUnwrap(store.metadata.idAliases?.first { $0.entityType == "congress" && $0.oldID == suffixedCongressID })
        XCTAssertEqual(alias.newID, migratedCongressID)
        let repairedDiagnostic = try XCTUnwrap(store.dataStructureDiagnostics().first { $0.id == "first-class-record-ids" })
        XCTAssertEqual(repairedDiagnostic.details.first { $0.id == "legacy-ids" }?.value, "0")
        XCTAssertFalse(store.migrateRecordsIfNeeded())
    }

    @MainActor
    func retiredUUIDCaseMigrationFixture() throws {
        let authorID = "1A1CF8AC-49AC-59E6-A203-FFC8A95BD579"
        let lowercaseAuthorID = authorID.lowercased()
        let organizationID = "16C7EB0E-128A-429C-B4CA-B63C2817A3F2"
        let congressID = "383EBF56-70BC-4679-9A73-B6B860165D82"
        let contributionID = "2E76D06F-F22C-449F-84BF-466DFBA3EF7E"

        var metadata = DataSourceMetadata.bundledDefault
        metadata.schemaVersion = 9
        metadata.migrationLog = []
        metadata.currentUserAuthorID = lowercaseAuthorID
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(
                id: "B1D86B84-13AF-4772-A961-10C4DDC8605D",
                date: "2026-09-10",
                title: "Research meeting",
                researcherID: lowercaseAuthorID
            )
        ]

        let store = GrantDataStore(
            metadata: metadata,
            organizations: [
                OrganizationRecord(
                    id: organizationID,
                    nameSv: "Organisation",
                    nameEn: "Organization",
                    congresses: [
                        OrganizationCongress(
                            id: congressID,
                            title: "Congress",
                            participantAuthorIDs: [lowercaseAuthorID]
                        )
                    ]
                )
            ],
            cvConferenceContributions: [
                CVConferenceContribution(
                    id: contributionID,
                    title: "Abstract",
                    contributorAuthorIDs: [lowercaseAuthorID],
                    presentedByAuthorID: lowercaseAuthorID,
                    congressOrganizationID: organizationID,
                    congressID: congressID
                )
            ],
            publicationAuthors: [
                PublicationAuthor(id: authorID, name: "Alva E. Exempel")
            ],
            skipInitialMigration: true
        )

        XCTAssertTrue(store.migrateRecordsIfNeeded())
        XCTAssertEqual(store.metadata.currentUserAuthorID, authorID)
        XCTAssertEqual(store.calendarMeetingRecords.first?.researcherID, authorID)
        XCTAssertEqual(store.organizations.first?.congresses.first?.participantAuthorIDs, [authorID])
        XCTAssertEqual(store.cvConferenceContributions.first?.contributorAuthorIDs, [authorID])
        XCTAssertEqual(store.cvConferenceContributions.first?.presentedByAuthorID, authorID)
        XCTAssertFalse(store.migrateRecordsIfNeeded())

        try store.persist(.allCoreData, includeBackup: false)
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        XCTAssertEqual(try sqliteStore.relationalIntegritySummary().brokenReferenceCount, 0)
    }

    @MainActor
    func testSQLiteRelationalTablesArePopulatedFromCoreDocuments() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarTravelRecords = [
            CalendarTravelRecord(
                id: "travel-1",
                date: "2026-09-10",
                arrivalDate: "2026-09-10",
                departureTime: "12:30",
                fromCity: "Stockholm",
                arrivalTime: "13:25",
                toCity: "Oslo",
                congressOrganizationID: "organization-1",
                congressID: "congress-1"
            )
        ]
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organisation",
            nameEn: "Organization",
            congresses: [
                OrganizationCongress(
                    id: "congress-1",
                    title: "Congress",
                    participantAuthorIDs: ["author-1"]
                )
            ]
        )
        let author = PublicationAuthor(
            id: "author-1",
            name: "Ada Lovelace",
            firstName: "Ada",
            lastName: "Lovelace"
        )
        let store = GrantDataStore(
            metadata: metadata,
            organizations: [organization],
            publicationAuthors: [author],
            skipInitialMigration: true
        )
        let sqliteURL = isolatedStorageDirectory.appendingPathComponent("relational.sqlite")
        let sqliteStore = try SQLiteDocumentStore(url: sqliteURL)

        try sqliteStore.saveBatch(store.encodedSQLiteDocuments(for: .allCoreData))
        let counts = try sqliteStore.relationalTableCounts()

        XCTAssertEqual(counts["rel_organizations"], 1)
        XCTAssertEqual(counts["rel_congresses"], 1)
        XCTAssertEqual(counts["rel_publication_authors"], 1)
        XCTAssertEqual(counts["rel_calendar_travel"], 1)
        XCTAssertEqual(counts["rel_congress_participants"], 1)
        XCTAssertEqual(counts["rel_congress_travel"], 1)
        let loadedTravel = try XCTUnwrap(try sqliteStore.loadRelationalCalendarTravelRecords()?.first)
        XCTAssertEqual(loadedTravel.departureTime, "12:30")
        XCTAssertEqual(loadedTravel.arrivalTime, "13:25")
        XCTAssertGreaterThan(try sqliteStore.relationalIndexCount(), 0)
        let runtimeSettings = try sqliteStore.runtimeSettingsSummary()
        XCTAssertEqual(runtimeSettings.journalMode.lowercased(), "wal")
        XCTAssertTrue(runtimeSettings.foreignKeysEnabled)
        XCTAssertGreaterThanOrEqual(runtimeSettings.busyTimeoutMilliseconds, 5_000)
        XCTAssertLessThan(runtimeSettings.cacheSizePages, 0)
        XCTAssertGreaterThanOrEqual(runtimeSettings.mmapSizeBytes, 0)
        let queryPlans = try sqliteStore.relationalQueryPlanObservations()
        XCTAssertFalse(queryPlans.isEmpty)
        XCTAssertEqual(queryPlans.filter(\.usesFullTableScan).count, 0)
        let integrity = try sqliteStore.relationalIntegritySummary()
        XCTAssertEqual(integrity.brokenReferenceCount, 0)
        XCTAssertEqual(integrity.duplicateIdentityCount, 0)
    }

    @MainActor
    func testSQLitePrimaryCongressReadsActivateWhenDocumentMatches() throws {
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organisation",
            nameEn: "Organization",
            congresses: [
                OrganizationCongress(
                    id: "congress-1",
                    title: "Congress",
                    from: "2026-09-10",
                    city: "Stockholm"
                )
            ]
        )
        let store = GrantDataStore(
            metadata: .bundledDefault,
            organizations: [organization],
            skipInitialMigration: true
        )
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)

        try sqliteStore.saveBatch(store.encodedSQLiteDocuments(for: .allCoreData))

        let congressDiagnostic = try XCTUnwrap(store.dataStructureDiagnostics().first { $0.id == "sqlite-primary-congresses" })
        let queryPlanDiagnostic = try XCTUnwrap(store.dataStructureDiagnostics().first { $0.id == "sqlite-query-plans" })
        XCTAssertTrue(["Active", "Aktiv"].contains(congressDiagnostic.value))
        XCTAssertEqual(queryPlanDiagnostic.value, "4/4")
        XCTAssertEqual(store.congressRecordsForRead.map(\.id), ["organization-1#congress-1"])
        XCTAssertEqual(store.organizationsForCongressRead.first?.congresses.first?.title, "Congress")
    }

    @MainActor
    func testSQLitePrimaryCoreRegisterReadsActivateWhenDocumentsMatch() throws {
        let application = GrantApplication(
            id: "application-1",
            rowNumber: 1,
            organization: "Funder",
            grantName: "Grant"
        )
        let project = ProjectRecord(id: "project-1", nameSv: "Projekt", nameEn: "Project")
        let author = PublicationAuthor(
            id: "author-1",
            name: "Ada Lovelace",
            firstName: "Ada",
            lastName: "Lovelace"
        )
        let publication = PublicationRecord(
            id: "publication-1",
            title: "Publication",
            authorNames: ["Ada Lovelace"]
        )
        let store = GrantDataStore(
            applications: [application],
            projects: [project],
            publicationAuthors: [author],
            publicationRecords: [publication],
            skipInitialMigration: true
        )
        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)

        try sqliteStore.saveBatch(store.encodedSQLiteDocuments(for: .allCoreData))
        var sqliteAuthor = author
        sqliteAuthor.publications = [
            PublicationAuthorContribution(id: "legacy-derived-id", title: "Publication", count: 1)
        ]
        try sqliteStore.save([sqliteAuthor], named: "publication_authors")

        let coreDiagnostic = try XCTUnwrap(store.dataStructureDiagnostics().first { $0.id == "sqlite-primary-core-registers" })
        XCTAssertTrue(["Active", "Aktiv"].contains(coreDiagnostic.value))
        XCTAssertEqual(store.applicationsForRead.map(\.id), ["application-1"])
        XCTAssertEqual(store.projectsForRead.map(\.id), ["project-1"])
        XCTAssertEqual(store.publicationAuthorsForRead.map(\.id), ["author-1"])
        XCTAssertEqual(store.publicationRecordsForRead.map(\.id), ["publication-1"])
    }

    @MainActor
    func testMetadataAutosaveKeepsRelationalSQLiteTablesInSync() throws {
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Organisation",
            nameEn: "Organization",
            congresses: [
                OrganizationCongress(id: "congress-1", title: "Congress")
            ]
        )
        let store = GrantDataStore(
            metadata: .bundledDefault,
            organizations: [organization],
            skipInitialMigration: true
        )
        try store.persist(.allCoreData, includeBackup: false)

        store.autosaveCalendarTravelRecords([
            CalendarTravelRecord(
                id: "travel-1",
                date: "2026-09-10",
                fromCity: "Stockholm",
                toCity: "Oslo",
                congressOrganizationID: "organization-1",
                congressID: "congress-1"
            )
        ])
        store.flushPendingMetadataPersistenceIfNeeded()

        let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        let counts = try sqliteStore.relationalTableCounts()
        XCTAssertEqual(counts["rel_calendar_travel"], 1)
        XCTAssertEqual(counts["rel_congress_travel"], 1)
        XCTAssertEqual(try sqliteStore.relationalIntegritySummary().brokenReferenceCount, 0)
        let readDiagnostic = try XCTUnwrap(store.dataStructureDiagnostics().first { $0.id == "sqlite-primary-calendar-planning" })
        XCTAssertTrue(["Active", "Aktiv"].contains(readDiagnostic.value))
    }

    @MainActor
    func testSettingsOnlyMetadataAutosaveDoesNotRewriteRelationalSnapshots() throws {
        let project = ProjectRecord(id: "project-1", nameSv: "Projekt", nameEn: "Project")
        let store = GrantDataStore(projects: [project], skipInitialMigration: true)
        try store.persist(.allCoreData, includeBackup: false)
        let sqliteStore = try XCTUnwrap(store.sqliteStore)
        let relationalSnapshotUpdatedAt = try XCTUnwrap(
            sqliteStore.documentUpdatedAt(named: "relational_sqlite_snapshot")
        )
        let relationalCoreUpdatedAt = try XCTUnwrap(
            sqliteStore.documentUpdatedAt(named: "relational_core")
        )

        var metadata = store.editableMetadataSnapshot
        metadata.interfaceLanguage = AppLanguage.swedish.rawValue
        store.persistMetadataSilently(metadata, includeBackup: false)
        store.flushPendingMetadataPersistenceIfNeeded()

        XCTAssertEqual(
            try sqliteStore.documentUpdatedAt(named: "relational_sqlite_snapshot"),
            relationalSnapshotUpdatedAt
        )
        XCTAssertEqual(
            try sqliteStore.documentUpdatedAt(named: "relational_core"),
            relationalCoreUpdatedAt
        )
        XCTAssertEqual(
            try sqliteStore.load(AppSettingsSnapshot.self, named: "app_settings")?.interfaceLanguage,
            AppLanguage.swedish.rawValue
        )
    }

    @MainActor
    func testDeferredMetadataAutosaveCannotOverwriteNewerCoreRelationalSnapshot() throws {
        let oldProject = ProjectRecord(id: "project-1", nameSv: "Gammalt", nameEn: "Old")
        let store = GrantDataStore(projects: [oldProject], skipInitialMigration: true)
        try store.persist(.allCoreData, includeBackup: false)
        let sqliteStore = try XCTUnwrap(store.sqliteStore)

        store.autosaveCalendarTravelRecords([
            CalendarTravelRecord(
                id: "travel-new",
                date: "2026-09-10",
                fromCity: "Stockholm",
                toCity: "Oslo"
            )
        ])

        let newProject = ProjectRecord(id: "project-1", nameSv: "Nytt", nameEn: "New")
        let encoder = GrantDataStore.makePersistenceEncoder()
        let newerRelationalSnapshot = GrantDataStore.relationalSQLiteSnapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            applications: [],
            metadata: .bundledDefault,
            organizations: [],
            projects: [newProject],
            publicationAuthors: [],
            publicationRecords: [],
            cvConferenceContributions: []
        )
        try sqliteStore.saveBatch([
            ("projects", try encoder.encode([newProject])),
            ("relational_sqlite_snapshot", try encoder.encode(newerRelationalSnapshot)),
        ])
        store.flushPendingMetadataPersistenceIfNeeded()

        let persistedSnapshot = try XCTUnwrap(
            sqliteStore.load(RelationalSQLiteSnapshot.self, named: "relational_sqlite_snapshot")
        )
        XCTAssertEqual(persistedSnapshot.projects.map(\.nameEn), ["New"])
        XCTAssertEqual(persistedSnapshot.calendarTravel.map(\.id), ["travel-new"])
        XCTAssertEqual(
            try sqliteStore.loadRelationalCalendarTravelRecords()?.map(\.id),
            ["travel-new"]
        )
    }

    func testCalendarSearchableFieldTextIncludesEveryMeetingTextField() {
        let meeting = CalendarMeetingRecord(
            id: "meeting-1",
            date: "2026-07-24",
            startTime: "09:00",
            endTime: "10:00",
            title: "Samtal",
            meetingType: "Intervju",
            meetingMode: "Hybrid",
            place: "Oslo",
            country: "Norway",
            detail: "Kandidatdiskussion",
            participantNames: ["Ada Lovelace"]
        )

        let searchableText = calendarSearchableFieldText(meeting)

        for queryText in ["intervju", "hybrid", "kandidatdiskussion", "Ada Lovelace", "2026-07-24"] {
            XCTAssertTrue(
                SearchFilterQuery(raw: queryText).matches(haystack: searchableText),
                "Expected calendar source fields to contain \(queryText)"
            )
        }
    }

    func testLockedMediaLanguagesAreLocalizedSortedAndCommaSeparated() {
        XCTAssertEqual(
            cvMediaLanguageListText(
                codes: ["sv", "fr", "en"],
                options: MediaLanguageOption.builtInOptions,
                language: .swedish
            ),
            "Engelska, Franska, Svenska"
        )
        XCTAssertEqual(
            cvMediaLanguageListText(
                codes: ["sv", "fr", "en"],
                options: MediaLanguageOption.builtInOptions,
                language: .english
            ),
            "English, French, Swedish"
        )
    }

    func testActiveCalendarSearchKeepsHitsOutsideRenderedWindow() throws {
        let historicalHit = try XCTUnwrap(DateParsers.isoDay.date(from: "2024-03-14"))
        let visibleDate = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-07-26"))
        let renderedWindowDates = Set([visibleDate])

        let searchDates = calendarFilteredCandidateDates(
            [historicalHit],
            isSearchActive: true,
            isInsideRenderedWindow: renderedWindowDates.contains
        )
        let ordinaryDates = calendarFilteredCandidateDates(
            [historicalHit],
            isSearchActive: false,
            isInsideRenderedWindow: renderedWindowDates.contains
        )

        XCTAssertEqual(searchDates, [historicalHit])
        XCTAssertTrue(ordinaryDates.isEmpty)
    }

    @MainActor
    func testHistoricalCalendarInterviewCanBeBuiltAndMatched() throws {
        let meeting = CalendarMeetingRecord(
            id: "historical-interview",
            date: "2024-03-14",
            startTime: "15:30",
            endTime: "16:00",
            title: "Intervju med TT",
            meetingType: "Möte"
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [meeting]
        let store = GrantDataStore(metadata: metadata)
        let calendar = footprintCalendar(for: .swedish)
        let rangeStart = try XCTUnwrap(DateParsers.isoDay.date(from: "2024-01-01"))
        let rangeEnd = try XCTUnwrap(DateParsers.isoDay.date(from: "2024-12-31"))

        let event = try XCTUnwrap(buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: rangeStart,
            displayedMonthEnd: rangeEnd,
            calendar: calendar
        ).first { $0.id == "meeting:historical-interview" })
        let searchableText = [
            event.title,
            event.subtitle,
            event.detail,
            event.place,
            event.timeText,
            calendarSearchableFieldText(meeting)
        ].joined(separator: " ")

        XCTAssertTrue(SearchFilterQuery(raw: "intervju").matches(haystack: searchableText))
    }

    func testLegacyMediaAppearanceDecodingSeedsResearcherAssociation() throws {
        let legacyJSON = Data(
            """
            {
              "id": "media-legacy",
              "authorID": "author-1",
              "date": "2026-07-26",
              "title": "Intervju"
            }
            """.utf8
        )

        var appearance = try JSONDecoder().decode(CVMediaAppearance.self, from: legacyJSON)
        appearance.normalize()

        XCTAssertEqual(appearance.authorID, "author-1")
        XCTAssertEqual(appearance.authorIDs, ["author-1"])
        XCTAssertEqual(appearance.date, "2026-07-26")
        XCTAssertEqual(appearance.publicationDate, "2026-07-26")
        XCTAssertTrue(appearance.projectIDs.isEmpty)
        XCTAssertTrue(appearance.publicationIDs.isEmpty)
        XCTAssertTrue(appearance.applicationIDs.isEmpty)
        XCTAssertEqual(appearance.startTime, "")
        XCTAssertEqual(appearance.endTime, "")
        XCTAssertEqual(appearance.meetingMode, "")
        XCTAssertEqual(appearance.place, "")
        XCTAssertEqual(appearance.country, "")
        XCTAssertEqual(appearance.comment, "")

        let roundTripped = try JSONDecoder().decode(
            CVMediaAppearance.self,
            from: JSONEncoder().encode(appearance)
        )
        XCTAssertEqual(roundTripped.authorIDs, ["author-1"])
    }

    func testMediaAppearanceLocationRoundTripsAndOnlineClearsPhysicalPlace() throws {
        var physical = CVMediaAppearance(
            id: "media-physical",
            date: "2026-08-10",
            publicationDate: "2026-08-12",
            meetingMode: CalendarMeetingMode.physical.rawValue,
            place: "Exempelsjukhuset",
            country: "Sweden",
            title: "Intervju"
        )
        physical.normalize()
        let roundTripped = try JSONDecoder().decode(
            CVMediaAppearance.self,
            from: JSONEncoder().encode(physical)
        )

        XCTAssertEqual(roundTripped.meetingMode, CalendarMeetingMode.physical.rawValue)
        XCTAssertEqual(roundTripped.date, "2026-08-10")
        XCTAssertEqual(roundTripped.publicationDate, "2026-08-12")
        XCTAssertEqual(roundTripped.place, "Exempelsjukhuset")
        XCTAssertEqual(roundTripped.country, "Sweden")

        var online = physical
        online.meetingMode = CalendarMeetingMode.online.rawValue
        online.normalize()
        XCTAssertEqual(online.place, "")
        XCTAssertEqual(online.country, "")
    }

    func testMediaAppearancePreservesManuallyChosenResearcherOrder() throws {
        var appearance = CVMediaAppearance(
            id: "media-ordered-researchers",
            authorID: "author-3",
            authorIDs: ["author-3", "author-1", "author-2"],
            title: "Intervju"
        )

        appearance.normalize()
        XCTAssertEqual(appearance.authorIDs, ["author-3", "author-1", "author-2"])
        XCTAssertEqual(appearance.authorID, "author-3")

        let roundTripped = try JSONDecoder().decode(
            CVMediaAppearance.self,
            from: JSONEncoder().encode(appearance)
        )
        XCTAssertEqual(roundTripped.authorIDs, ["author-3", "author-1", "author-2"])
    }

    @MainActor
    func testMediaAppearanceCalendarEventAndCurrentResearcherCVFilter() throws {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.currentUserAuthorID = "author-1"
        let included = CVMediaAppearance(
            id: "media-included",
            authorID: "author-1",
            authorIDs: ["author-1", "author-2"],
            projectIDs: ["project-1"],
            publicationIDs: ["publication-1"],
            applicationIDs: ["application-1"],
            date: "2026-07-26",
            publicationDate: "2026-07-29",
            startTime: "09:15",
            endTime: "09:45",
            meetingMode: CalendarMeetingMode.physical.rawValue,
            place: "Göteborg",
            country: "Sweden",
            title: "Intervju",
            comment: "Kommentar"
        )
        let excluded = CVMediaAppearance(
            id: "media-excluded",
            authorID: "author-2",
            authorIDs: ["author-2"],
            date: "2026-07-27",
            title: "Annan intervju"
        )
        let store = GrantDataStore(
            applications: [
                GrantApplication(id: "application-1", rowNumber: 1, organization: "Funder", grantName: "Grant")
            ],
            metadata: metadata,
            projects: [ProjectRecord(id: "project-1", nameSv: "Projekt", nameEn: "Project")],
            cvMediaAppearances: [included, excluded],
            publicationAuthors: [
                PublicationAuthor(id: "author-1", name: "Forskare Ett"),
                PublicationAuthor(id: "author-2", name: "Forskare Två"),
            ],
            publicationRecords: [PublicationRecord(id: "publication-1", title: "Publikation")],
            skipInitialMigration: true
        )

        XCTAssertTrue(store.mediaAppearanceIncludesCurrentUser(included))
        XCTAssertFalse(store.mediaAppearanceIncludesCurrentUser(excluded))

        let events = buildFootprintCalendarEvents(
            store: store,
            language: .swedish,
            displayedMonthStart: try XCTUnwrap(DateParsers.isoDay.date(from: "2026-07-01")),
            displayedMonthEnd: try XCTUnwrap(DateParsers.isoDay.date(from: "2026-07-31")),
            calendar: footprintCalendar(for: .swedish)
        )
        let event = try XCTUnwrap(events.first { $0.id == "media-appearance:media-included" })
        XCTAssertEqual(event.source, .mediaAppearance("media-included"))
        XCTAssertEqual(event.meetingCategoryName, "Övrigt")
        XCTAssertEqual(event.timeText, "09:15–09:45")
        XCTAssertTrue(event.place.contains("Göteborg"))
        XCTAssertTrue(event.detail.contains("Kommentar"))
        XCTAssertEqual(DateParsers.isoDay.string(from: event.displayDate), "2026-07-26")
        XCTAssertNotEqual(DateParsers.isoDay.string(from: event.displayDate), included.publicationDate)
    }

    func testEditableClinicalTrialRegistrationsPreserveAllStoredRowsAndIDs() {
        let stored = [
            ProjectClinicalTrialRegistration(
                id: "trial-1",
                registeredOn: "2024-01-01",
                updatedOn: "2024-02-01",
                trialID: "NCT00000001"
            ),
            ProjectClinicalTrialRegistration(
                id: "trial-2",
                registeredOn: "2025-01-01",
                updatedOn: "2025-02-01",
                trialID: "NCT00000002"
            ),
            ProjectClinicalTrialRegistration(
                id: "trial-3",
                registeredOn: "2026-01-01",
                updatedOn: "2026-02-01",
                trialID: "NCT00000003"
            ),
        ]

        let editable = editableProjectClinicalTrialRegistrations(stored)

        XCTAssertEqual(editable, stored)
        XCTAssertEqual(editable.map(\.id), ["trial-1", "trial-2", "trial-3"])
    }

    func testEditableClinicalTrialRegistrationsProvidesOneEmptyRowForNewProject() {
        let editable = editableProjectClinicalTrialRegistrations([])

        XCTAssertEqual(editable.count, 1)
        XCTAssertTrue(editable[0].isEmpty)
    }

    func testNormalizedWebLinkURLAllowsOnlySupportedExternalSchemes() {
        XCTAssertEqual(normalizedWebLinkURL("example.org/path")?.absoluteString, "https://example.org/path")
        XCTAssertEqual(normalizedWebLinkURL("http://example.org")?.scheme, "http")
        XCTAssertEqual(normalizedWebLinkURL("https://example.org")?.scheme, "https")
        XCTAssertEqual(normalizedWebLinkURL("mailto:researcher@example.org")?.scheme, "mailto")

        XCTAssertNil(normalizedWebLinkURL("file:///tmp/private.txt"))
        XCTAssertNil(normalizedWebLinkURL("ftp://example.org/archive"))
        XCTAssertNil(normalizedWebLinkURL("javascript://example.org/alert"))
        XCTAssertNil(normalizedWebLinkURL("footprint://record/123"))
        XCTAssertNil(normalizedWebLinkURL("https:///missing-host"))
    }

    func testNormalizedWebLinkURLStillCanonicalizesDOI() {
        XCTAssertEqual(
            normalizedWebLinkURL("doi:10.1000/example")?.absoluteString,
            "https://doi.org/10.1000/example"
        )
    }

    func testLoadPDFDataForUserActionRejectsNonPDFAndEmptyPDF() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let textURL = directory.appendingPathComponent("notes.txt")
        try Data("not a pdf".utf8).write(to: textURL)
        XCTAssertThrowsError(try loadPDFDataForUserAction(from: textURL)) { error in
            XCTAssertEqual(error as? AttachmentActionError, .unsupportedPDF)
        }

        let emptyPDFURL = directory.appendingPathComponent("empty.pdf")
        try Data().write(to: emptyPDFURL)
        XCTAssertThrowsError(try loadPDFDataForUserAction(from: emptyPDFURL)) { error in
            XCTAssertEqual(error as? AttachmentActionError, .emptyFile)
        }

        let renamedTextURL = directory.appendingPathComponent("renamed.pdf")
        try Data("not actually a pdf".utf8).write(to: renamedTextURL)
        XCTAssertThrowsError(try loadPDFDataForUserAction(from: renamedTextURL)) { error in
            XCTAssertEqual(error as? AttachmentActionError, .unsupportedPDF)
        }
    }

    func testLoadPDFDataForUserActionReturnsSelectedPDFBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pdfURL = directory.appendingPathComponent("document.PDF")
        let expected = Data("%PDF-1.7 test".utf8)
        try expected.write(to: pdfURL)

        XCTAssertEqual(try loadPDFDataForUserAction(from: pdfURL), expected)
    }

    private func calendarRevealTestEvent(
        id: String,
        source: CalendarWorkspaceEventSource,
        displayDate: Date
    ) -> CalendarWorkspaceEvent {
        CalendarWorkspaceEvent(
            id: id,
            source: source,
            displayDate: displayDate,
            title: "Event",
            subtitle: "",
            detail: "",
            place: "",
            timeText: "",
            kind: .congress,
            completedOn: nil,
            action: nil,
            toggleCompletion: nil
        )
    }

    func testTeachingFormatDeletionSuppressesPersistenceOnlyAfterRecordIsGone() {
        XCTAssertFalse(
            TeachingFormatDeletionPersistence.shouldSuppress(
                deleteRequested: true,
                recordStillExists: true
            )
        )
        XCTAssertTrue(
            TeachingFormatDeletionPersistence.shouldSuppress(
                deleteRequested: true,
                recordStillExists: false
            )
        )
        XCTAssertFalse(
            TeachingFormatDeletionPersistence.shouldSuppress(
                deleteRequested: false,
                recordStillExists: false
            )
        )
    }

    func testSelectiveDatabaseCategoryClosureIncludesTransitiveRecordDependencies() {
        let applicationClosure = FootprintDataExchangeCategory.dependencyClosure(for: [.applications])
        XCTAssertEqual(
            applicationClosure,
            [.applications, .projects, .organizations, .researchers]
        )

        let teachingClosure = FootprintDataExchangeCategory.dependencyClosure(for: [.teaching])
        XCTAssertEqual(
            teachingClosure,
            [.teaching, .organizations, .researchers]
        )

        XCTAssertEqual(
            FootprintDataExchangeCategory.dependencyClosure(for: [.journals]),
            [.journals]
        )
    }

    func testDatabaseExportDescriptorStillSupportsVersionOnePackages() {
        XCTAssertTrue(FootprintDatabaseExportDescriptor.supportedFormatVersions.contains(1))
        XCTAssertTrue(
            FootprintDatabaseExportDescriptor.supportedFormatVersions.contains(
                FootprintDatabaseExportDescriptor.currentFormatVersion
            )
        )
    }

    func testManagedAttachmentURLsContainUnsafeImportedIdentifiers() {
        let rootsAndURLs = [
            (
                GrantDataStore.publicationPDFsDirectory,
                GrantDataStore.managedPublicationPDFURL(forPublicationID: "../../Documents/report")
            ),
            (
                GrantDataStore.mediaAppearancePDFsDirectory,
                GrantDataStore.managedCVMediaAppearancePDFURL(forMediaAppearanceID: "/tmp/report")
            ),
            (
                GrantDataStore.conferenceContributionPDFsDirectory,
                GrantDataStore.managedCVConferenceContributionPDFURL(forContributionID: #"folder\report"#)
            ),
            (
                GrantDataStore.doctoralCandidatePDFsDirectory,
                GrantDataStore.managedDoctoralCandidatePDFURL(forDocumentID: "%2e%2e%2fDocuments%2freport")
            ),
        ]

        for (root, url) in rootsAndURLs {
            XCTAssertEqual(url.standardizedFileURL.deletingLastPathComponent(), root.standardizedFileURL)
            XCTAssertTrue(url.lastPathComponent.hasPrefix("unsafe-id-"))
        }
        XCTAssertEqual(
            GrantDataStore.managedPublicationPDFURL(forPublicationID: "legacy-publication").lastPathComponent,
            "legacy-publication.pdf"
        )
    }

    @MainActor
    func testManagedAttachmentWriteRejectsRealSymlinkEscape() throws {
        try GrantDataStore.ensurePublicationPDFsDirectory()
        let outsideURL = isolatedStorageDirectory.appendingPathComponent("outside.pdf")
        let originalData = Data("outside-must-not-change".utf8)
        try originalData.write(to: outsideURL)
        let symlinkURL = GrantDataStore.managedPublicationPDFURL(forPublicationID: "escape")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideURL)

        XCTAssertThrowsError(
            try GrantDataStore.persistManagedPublicationPDF(
                data: Data("replacement".utf8),
                forPublicationID: "escape"
            )
        )
        XCTAssertEqual(try Data(contentsOf: outsideURL), originalData)
        XCTAssertTrue(
            (try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkURL.path)) != nil
        )
        XCTAssertNil(
            GrantDataStore.resolvePublicationPDFURL(
                publicationID: nil,
                finalPDFPath: symlinkURL.path,
                finalPDFFilename: nil
            )
        )
    }

    func testAttachmentFallbackReadRejectsTraversalFilename() throws {
        let outsideURL = isolatedStorageDirectory.appendingPathComponent("outside-fallback.pdf")
        try Data("outside".utf8).write(to: outsideURL)

        XCTAssertNil(
            GrantDataStore.resolvePublicationPDFURL(
                publicationID: nil,
                finalPDFPath: nil,
                finalPDFFilename: "../outside-fallback.pdf"
            )
        )
        XCTAssertNil(
            GrantDataStore.resolveCVMediaAppearancePDFURL(
                mediaAppearanceID: nil,
                pdfPath: nil,
                pdfFilename: #"..\outside-fallback.pdf"#
            )
        )
    }

    func testBackupAttachmentManifestRejectsSymlinkEscape() throws {
        let backupURL = isolatedStorageDirectory.appendingPathComponent("symlink-backup", isDirectory: true)
        let attachmentDirectory = backupURL.appendingPathComponent("Publication PDFs", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        let outsideURL = isolatedStorageDirectory.appendingPathComponent("outside-backup.pdf")
        try Data("outside".utf8).write(to: outsideURL)
        let symlinkURL = attachmentDirectory.appendingPathComponent("escape.pdf")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideURL)
        let manifest = GrantDataStore.BackupAttachmentManifest(
            generatedAt: GrantParsing.timestampNow(),
            entries: [
                GrantDataStore.BackupAttachmentManifestEntry(
                    relativePath: "Publication PDFs/escape.pdf",
                    byteCount: 7,
                    sha256: "unused"
                )
            ]
        )
        try GrantDataStore.encode(
            manifest,
            to: backupURL.appendingPathComponent("attachments_manifest.json")
        )

        XCTAssertThrowsError(try GrantDataStore.verifyAttachmentManifest(in: backupURL))
    }

    @MainActor
    func testBackupStagingRejectsAttachmentRevisionChangedAfterSnapshotCapture() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        _ = try GrantDataStore.persistManagedPublicationPDF(
            data: Data("before".utf8),
            forPublicationID: "publication-1"
        )
        let capturedRevision = GrantDataStore.currentManagedAttachmentRevision()
        _ = try GrantDataStore.persistManagedPublicationPDF(
            data: Data("after".utf8),
            forPublicationID: "publication-1"
        )
        let finalDirectory = isolatedStorageDirectory.appendingPathComponent(
            "stale-attachment-revision-backup",
            isDirectory: true
        )

        XCTAssertThrowsError(
            try GrantDataStore.writeVerifiedBackupPackage(
                snapshot: snapshot,
                archivedRecords: [],
                receivedGrantsData: nil,
                finalDirectory: finalDirectory,
                expectedAttachmentRevision: capturedRevision
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalDirectory.path))
    }

    @MainActor
    func testUnchangedAttachmentsAreDeduplicatedAcrossCompatibleBackups() throws {
        let snapshot = makeSQLiteOnlySnapshot()
        _ = try GrantDataStore.persistManagedPublicationPDF(
            data: Data("stable-attachment".utf8),
            forPublicationID: "publication-1"
        )
        let revision = GrantDataStore.currentManagedAttachmentRevision()
        let first = try GrantDataStore.createForcedBackupSnapshot(
            snapshot: snapshot,
            archivedRecords: [],
            receivedGrantsData: nil,
            prefix: "dedup-first",
            now: Date(timeIntervalSince1970: 1_800_000_000),
            expectedAttachmentRevision: revision
        )
        ManagedAttachmentRevisionCoordinator.shared.clearPublishedBackupCache()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: first.appendingPathComponent("attachments_manifest.json").path
            )
        )
        XCTAssertTrue(try GrantDataStore.verifyAttachmentManifestIfPresent(in: first))
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: first.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            ).contains { $0.standardizedFileURL == first.standardizedFileURL }
        )
        XCTAssertEqual(
            GrantDataStore.newestCompatibleAttachmentBackup(
                in: first.deletingLastPathComponent(),
                excluding: first.deletingLastPathComponent()
                    .appendingPathComponent("not-yet-published", isDirectory: true)
            )?.standardizedFileURL,
            first.standardizedFileURL
        )
        let second = try GrantDataStore.createForcedBackupSnapshot(
            snapshot: snapshot,
            archivedRecords: [],
            receivedGrantsData: nil,
            prefix: "dedup-second",
            now: Date(timeIntervalSince1970: 1_800_000_001),
            expectedAttachmentRevision: revision
        )
        let relativePath = "Publication PDFs/publication-1.pdf"
        let firstFile = first.appendingPathComponent(relativePath)
        let secondFile = second.appendingPathComponent(relativePath)
        let firstAttributes = try FileManager.default.attributesOfItem(atPath: firstFile.path)
        let secondAttributes = try FileManager.default.attributesOfItem(atPath: secondFile.path)

        XCTAssertEqual(
            firstAttributes[.systemFileNumber] as? NSNumber,
            secondAttributes[.systemFileNumber] as? NSNumber
        )
        try GrantDataStore.verifyAttachmentManifest(in: first)
        try GrantDataStore.verifyAttachmentManifest(in: second)
        XCTAssertEqual(
            try GrantDataStore.decodeRestorePayload(from: first).snapshot.publicationRecords.map(\.id),
            snapshot.publicationRecords.map(\.id)
        )
    }

    @MainActor
    func testUnverifiedRollbackFailureBlocksSubsequentStorageWrites() throws {
        let store = GrantDataStore()
        let primary = NSError(
            domain: "FootprintTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Primary persistence failed."]
        )
        let rollback = NSError(
            domain: "FootprintTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Rollback persistence failed."]
        )

        store.handlePersistenceRollback(
            primaryError: primary,
            context: "Fault injection"
        ) {
            throw rollback
        }

        XCTAssertTrue(store.storageWritesBlockedByUnverifiedRollback)
        XCTAssertTrue(store.loadError?.contains("Primary persistence failed") == true)
        XCTAssertTrue(store.loadError?.contains("Rollback persistence failed") == true)
        XCTAssertThrowsError(try store.saveArchivedRecords([]))
    }

    func testLegacyManagerSalaryCalculatorWithoutBirthDateDecodesAsUnknown() throws {
        let data = Data(#"{"monthlySalaryPeriods":[]}"#.utf8)
        let calculator = try JSONDecoder().decode(ManagerSalaryCalculator.self, from: data)
        XCTAssertEqual(calculator.birthDate, "")
    }

    private func executeSQLiteFixture(at url: URL, sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        ) == SQLITE_OK, let database else {
            sqlite3_close_v2(database)
            throw NSError(
                domain: "FootprintTests.SQLiteFixture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create SQLite fixture."]
            )
        }
        defer { sqlite3_close_v2(database) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite fixture error."
            sqlite3_free(errorMessage)
            throw NSError(
                domain: "FootprintTests.SQLiteFixture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    @MainActor
    func testStableStringDraftRowsPreserveIdentityWhileEditingValue() {
        let values = ["Alex", "Alex", "Bo"]
        let identity = StableStringDraftListState(values: values)
        let initialRows = identity.rows(for: values)
        var edited = values
        edited[1] = "Alexandra"
        identity.updateValue(at: 1, to: edited[1])
        let editedRows = identity.rows(for: edited)

        XCTAssertEqual(editedRows.map(\.value), edited)
        XCTAssertEqual(editedRows.map(\.id), initialRows.map(\.id))
    }

    @MainActor
    func testStableStringDraftRowsMoveAndDeleteExactDuplicateIdentity() {
        var values = ["Alex", "Alex", "Bo"]
        let identity = StableStringDraftListState(values: values)
        let initialRows = identity.rows(for: values)

        let offsets = IndexSet(integer: 1)
        values.move(fromOffsets: offsets, toOffset: 3)
        identity.move(fromOffsets: offsets, toOffset: 3)
        let movedRows = identity.rows(for: values)
        XCTAssertEqual(movedRows.map(\.id), [initialRows[0].id, initialRows[2].id, initialRows[1].id])

        identity.remove(at: 0)
        values.remove(at: 0)
        let remainingRows = identity.rows(for: values)
        XCTAssertEqual(remainingRows.map(\.id), [initialRows[2].id, initialRows[1].id])
        XCTAssertEqual(remainingRows.map(\.value), ["Bo", "Alex"])
    }

    @MainActor
    func testStableStringDraftRowsReconcileExternalValuesLosslessly() {
        let identity = StableStringDraftListState(values: ["Alex", "Alex", "Bo"])
        let initialRows = identity.rows(for: identity.valuesSnapshot)

        let externallyUpdated = ["Bo", "Alex", "Alex", "Kim"]
        identity.reconcileExternal(externallyUpdated)
        let rows = identity.rows(for: externallyUpdated)

        XCTAssertEqual(rows.map(\.value), externallyUpdated)
        XCTAssertEqual(rows.map(\.id), [
            initialRows[2].id,
            initialRows[0].id,
            initialRows[1].id,
            rows[3].id,
        ])
        XCTAssertEqual(Set(rows.map(\.id)).count, externallyUpdated.count)
    }

    func testCalendarLinkedDictionaryKeepsFirstDuplicateDeterministically() {
        struct Value: Equatable {
            let id: String
            let payload: String
        }
        let values = [
            Value(id: "duplicate", payload: "first"),
            Value(id: "duplicate", payload: "second"),
            Value(id: "unique", payload: "third"),
        ]

        let index = calendarLinkedDictionary(values, keyedBy: \.id)

        XCTAssertEqual(index["duplicate"]?.payload, "first")
        XCTAssertEqual(index["unique"]?.payload, "third")
    }

    func testCongressRowsGenerationRejectsStaleAndCancelledBuilds() {
        XCTAssertTrue(CongressRowsBuildGenerationPolicy.shouldPublish(
            completedGeneration: 4,
            currentGeneration: 4,
            isCancelled: false
        ))
        XCTAssertFalse(CongressRowsBuildGenerationPolicy.shouldPublish(
            completedGeneration: 3,
            currentGeneration: 4,
            isCancelled: false
        ))
        XCTAssertFalse(CongressRowsBuildGenerationPolicy.shouldPublish(
            completedGeneration: 4,
            currentGeneration: 4,
            isCancelled: true
        ))
    }

    @MainActor
    func testSelectionCoordinatorRejectsStaleCallbackUntilReleased() {
        let coordinator = AppSelectionCoordinator<String>()
        coordinator.arm("new", previousID: "old")

        XCTAssertFalse(coordinator.accepts(candidate: "old"))
        XCTAssertFalse(coordinator.accepts(candidate: nil))
        XCTAssertTrue(coordinator.accepts(candidate: "new"))

        coordinator.release(ifMatching: "new")
        XCTAssertTrue(coordinator.accepts(candidate: "old"))
    }

    func testSalaryCalculationRequiresExplicitValidBirthDate() {
        var calculator = ManagerSalaryCalculator.empty
        calculator.birthDate = ""
        XCTAssertFalse(salaryCalculationHasKnownAge(calculator))

        calculator.birthDate = "1980-06-15"
        XCTAssertTrue(salaryCalculationHasKnownAge(calculator))

        calculator.birthDate = "not-a-date"
        XCTAssertFalse(salaryCalculationHasKnownAge(calculator))
    }

    func testPublicationThreeWayMergePreservesConcurrentCanonicalFields() throws {
        let baseline = PublicationRecord(
            id: "publication-merge",
            title: "Baseline title",
            journal: "Baseline journal",
            year: "2026"
        )
        var draft = baseline
        draft.title = "Locally edited title"
        var current = baseline
        current.year = "2027"

        let merged = try XCTUnwrap(
            PublicationDraftThreeWayMerge.merge(
                baseline: baseline,
                draft: draft,
                current: current
            )
        )

        XCTAssertEqual(merged.title, "Locally edited title")
        XCTAssertEqual(merged.journal, "Baseline journal")
        XCTAssertEqual(merged.year, "2027")
    }

    func testPublicationThreeWayMergeRejectsSameFieldConflict() {
        let baseline = PublicationRecord(
            id: "publication-conflict",
            title: "Baseline title",
            journal: "Journal",
            year: "2026"
        )
        var draft = baseline
        draft.title = "Local title"
        var current = baseline
        current.title = "Concurrent title"

        XCTAssertNil(
            PublicationDraftThreeWayMerge.merge(
                baseline: baseline,
                draft: draft,
                current: current
            )
        )
    }

    func testResponsiveLayoutMinimumsFitSupportedCompactWindows() {
        XCTAssertEqual(AppResponsiveLayout.mainMinimumWidth, 960)
        XCTAssertEqual(AppResponsiveLayout.mainMinimumHeight, 640)
        XCTAssertEqual(AppResponsiveLayout.settingsMinimumWidth, 920)
        XCTAssertEqual(AppResponsiveLayout.settingsMinimumHeight, 680)
        XCTAssertLessThanOrEqual(
            AppResponsiveLayout.settingsMinimumWidth,
            AppResponsiveLayout.mainMinimumWidth
        )
    }

    func testResponsiveDialogMinimumNeverExceedsIdealSize() {
        let compact = AppResponsiveLayout.clampedDialogMinimum(
            idealWidth: 360,
            idealHeight: 240
        )
        XCTAssertEqual(compact, CGSize(width: 360, height: 240))

        let regular = AppResponsiveLayout.clampedDialogMinimum(
            idealWidth: 920,
            idealHeight: 1_040,
            minimumWidth: 640,
            minimumHeight: 520
        )
        XCTAssertEqual(regular, CGSize(width: 640, height: 520))
    }

    @MainActor
    func testCalendarDeletionIsAtomicAndUndoableForEveryOwnedRecordKind() {
        let meeting = CalendarMeetingRecord(id: "meeting-delete", date: "2027-02-10", title: "Meeting")
        let travel = CalendarTravelRecord(id: "travel-delete", date: "2027-02-11", toCity: "Oslo")
        let accommodation = CalendarAccommodationRecord(
            id: "hotel-delete",
            hotelName: "Hotel",
            checkInDate: "2027-02-11"
        )
        let metadataStore = GrantDataStore(skipInitialMigration: true)
        metadataStore.autosaveCalendarMeetingRecords([meeting])
        metadataStore.autosaveCalendarTravelRecords([travel])
        metadataStore.autosaveCalendarAccommodationRecords([accommodation])
        metadataStore.undoManager.removeAllActions()

        XCTAssertTrue(metadataStore.deleteCalendarEvent(source: .meeting(meeting.id)))
        XCTAssertFalse(metadataStore.calendarMeetingRecords.contains { $0.id == meeting.id })
        metadataStore.undoManager.undo()
        XCTAssertTrue(metadataStore.calendarMeetingRecords.contains { $0.id == meeting.id })

        metadataStore.undoManager.removeAllActions()
        XCTAssertTrue(metadataStore.deleteCalendarEvent(source: .travel(travel.id)))
        XCTAssertFalse(metadataStore.calendarTravelRecords.contains { $0.id == travel.id })
        metadataStore.undoManager.undo()
        XCTAssertTrue(metadataStore.calendarTravelRecords.contains { $0.id == travel.id })

        metadataStore.undoManager.removeAllActions()
        XCTAssertTrue(metadataStore.deleteCalendarEvent(source: .accommodation(accommodation.id)))
        XCTAssertFalse(metadataStore.calendarAccommodationRecords.contains { $0.id == accommodation.id })
        metadataStore.undoManager.undo()
        XCTAssertTrue(metadataStore.calendarAccommodationRecords.contains { $0.id == accommodation.id })

        let centralTask = TaskItem(id: "central-delete", deadline: "2027-02-12", comment: "Central")
        metadataStore.autosaveTaskItems([centralTask])
        metadataStore.undoManager.removeAllActions()
        XCTAssertTrue(metadataStore.deleteCalendarEvent(source: .teachingTask(taskID: centralTask.id)))
        XCTAssertFalse(metadataStore.taskItems.contains { $0.id == centralTask.id })
        metadataStore.undoManager.undo()
        XCTAssertTrue(metadataStore.taskItems.contains { $0.id == centralTask.id })

        let legacyTask = PublicationTaskItem(id: "legacy-delete", deadline: "2027-02-13", comment: "Legacy")
        metadataStore.autosaveTeachingWorkspaceTasks([legacyTask])
        metadataStore.undoManager.removeAllActions()
        XCTAssertTrue(metadataStore.deleteCalendarEvent(source: .teachingTask(taskID: legacyTask.id)))
        XCTAssertFalse(metadataStore.teachingWorkspaceTasks.contains { $0.id == legacyTask.id })
        metadataStore.undoManager.undo()
        XCTAssertTrue(metadataStore.teachingWorkspaceTasks.contains { $0.id == legacyTask.id })

        let organizationTask = ProjectTaskItem(id: "organization-task-delete", comment: "Organization")
        let organization = OrganizationRecord(
            id: "organization-delete",
            nameSv: "Organisation",
            nameEn: "Organization",
            projectTasks: [organizationTask]
        )
        let projectTask = ProjectTaskItem(id: "project-task-delete", comment: "Project")
        let project = ProjectRecord(
            id: "project-delete",
            nameSv: "Projekt",
            nameEn: "Project",
            projectTasks: [projectTask]
        )
        let publicationTask = PublicationTaskItem(id: "publication-task-delete", comment: "Publication")
        let publication = PublicationRecord(
            id: "publication-delete",
            title: "Publication",
            publicationTasks: [publicationTask]
        )
        let hostedStore = GrantDataStore(
            organizations: [organization],
            projects: [project],
            publicationRecords: [publication],
            skipInitialMigration: true
        )

        XCTAssertTrue(
            hostedStore.deleteCalendarEvent(
                source: .organizationTask(
                    organizationID: organization.id,
                    taskID: organizationTask.id
                )
            )
        )
        XCTAssertFalse(hostedStore.organizations[0].projectTasks.contains { $0.id == organizationTask.id })
        hostedStore.undoManager.undo()
        XCTAssertTrue(hostedStore.organizations[0].projectTasks.contains { $0.id == organizationTask.id })

        hostedStore.undoManager.removeAllActions()
        XCTAssertTrue(
            hostedStore.deleteCalendarEvent(
                source: .projectTask(projectID: project.id, taskID: projectTask.id)
            )
        )
        XCTAssertFalse(hostedStore.projects[0].projectTasks.contains { $0.id == projectTask.id })
        hostedStore.undoManager.undo()
        XCTAssertTrue(hostedStore.projects[0].projectTasks.contains { $0.id == projectTask.id })

        hostedStore.undoManager.removeAllActions()
        XCTAssertTrue(
            hostedStore.deleteCalendarEvent(
                source: .publicationTask(
                    publicationID: publication.id,
                    taskID: publicationTask.id
                )
            )
        )
        XCTAssertFalse(hostedStore.publications[0].publicationTasks.contains { $0.id == publicationTask.id })
        hostedStore.undoManager.undo()
        XCTAssertTrue(hostedStore.publications[0].publicationTasks.contains { $0.id == publicationTask.id })

        hostedStore.undoManager.removeAllActions()
        XCTAssertFalse(hostedStore.deleteCalendarEvent(source: .meeting("missing")))
        XCTAssertFalse(hostedStore.undoManager.canUndo)
    }

    private func publicationAuthorRowSnapshot(
        id: String,
        sortName: String,
        sortOrganization: String = "",
        primaryOrganization: String = "",
        affiliationOrganizations: [String] = [],
        projectCount: Int = 0
    ) -> PublicationAuthorRowSnapshot {
        PublicationAuthorRowSnapshot(
            id: id,
            sortName: sortName,
            sortOrganization: sortOrganization,
            displayName: sortName,
            displaySubtitle: "",
            primaryOrganization: primaryOrganization,
            affiliationOrganizations: affiliationOrganizations,
            primaryCountry: "",
            countryFlags: [],
            isCurrentUser: false,
            projectCount: projectCount,
            grantCount: 0,
            publicationCount: 0,
            disseminationCount: 0,
            expertAssignmentCount: 0,
            teachingCount: 0,
            normalizedSearchBlob: "",
            missingORCID: false,
            missingEmail: false,
            missingPrimaryOrganization: false,
            missingPrimaryCountry: false,
            missingTitle: false
        )
    }
}
