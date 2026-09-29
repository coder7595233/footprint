import XCTest
@testable import Footprint

final class ProjectProtocolDocumentTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectProtocolDocumentTests-\(UUID().uuidString)", isDirectory: true)
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

    func testTaskItemProtocolTextDecodesFromLegacyPayloadAndRoundTrips() throws {
        let legacyJSON = Data("""
        {"id":"t1","createdOn":"","updatedOn":"","deadline":"2026-01-01","comment":"X","note":"","participantNames":[],"links":[]}
        """.utf8)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: legacyJSON)
        XCTAssertEqual(decoded.protocolText, "")

        var task = TaskItem(comment: "X")
        task.protocolText = "Beslut: fortsätt enligt plan."
        let roundTripped = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(roundTripped.protocolText, "Beslut: fortsätt enligt plan.")
    }

    func testCalendarMeetingRecordProtocolTextDecodesFromLegacyPayloadAndRoundTrips() throws {
        let legacyJSON = Data("""
        {"id":"m1","date":"2026-01-01","title":"Möte"}
        """.utf8)
        let decoded = try JSONDecoder().decode(CalendarMeetingRecord.self, from: legacyJSON)
        XCTAssertEqual(decoded.protocolText, "")

        var meeting = CalendarMeetingRecord(date: "2026-01-01", title: "Möte")
        meeting.protocolText = "Diskuterade tidsplanen."
        let roundTripped = try JSONDecoder().decode(CalendarMeetingRecord.self, from: JSONEncoder().encode(meeting))
        XCTAssertEqual(roundTripped.protocolText, "Diskuterade tidsplanen.")
    }

    @MainActor
    func testProjectSummaryDocumentListsProtocolEntriesOldestFirst() {
        var project = ProjectRecord(nameSv: "Testprojekt", nameEn: "Test project")
        project.collaboratorNames = ["Anna Andersson"]

        let olderMeeting = CalendarMeetingRecord(
            date: "2025-05-01",
            title: "Uppstartsmöte",
            participantNames: ["Anna Andersson", "Bo Berg"],
            projectIDs: [project.id],
            protocolText: "Projektet startades."
        )
        let newerMeeting = CalendarMeetingRecord(
            date: "2026-02-01",
            title: "Styrgruppsmöte",
            projectIDs: [project.id],
            protocolText: "Budgeten godkändes.\nNästa möte i mars."
        )
        let meetingWithoutProtocol = CalendarMeetingRecord(
            date: "2025-11-11",
            title: "Arbetsmöte",
            projectIDs: [project.id]
        )
        let taskWithProtocol = TaskItem(
            deadline: "2025-12-24",
            comment: "Skicka ansökan",
            participantNames: ["Cecilia Carlsson"],
            links: [TaskLink(kind: .project, targetID: project.id)],
            protocolText: "Ansökan inskickad i tid."
        )

        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [newerMeeting, olderMeeting, meetingWithoutProtocol]
        metadata.taskItems = [taskWithProtocol]

        let store = GrantDataStore(metadata: metadata, projects: [project])
        let document = store.projectSummaryDocument(for: project, exportLanguage: .swedish)

        XCTAssertEqual(document.title, "Testprojekt")
        // The generation date sits right-aligned on the title line, not as a summary line.
        XCTAssertFalse(document.titleTrailingText.isEmpty)
        XCTAssertTrue(document.summaryLines.isEmpty)
        XCTAssertTrue(document.compactTables)

        guard let collaboratorSection = document.sections.first(where: { $0.title == "Medarbetare" }) else {
            XCTFail("Document is missing the Medarbetare section")
            return
        }
        XCTAssertEqual(collaboratorSection.headers, ["Namn", "Tillhörighet"])
        XCTAssertEqual(collaboratorSection.rows, [["Anna Andersson", "–"]])

        guard let taskSection = document.sections.first(where: { $0.title == "Uppgifter" }) else {
            XCTFail("Document is missing the Uppgifter section")
            return
        }
        // Dates use non-breaking hyphens so they never wrap inside their column.
        XCTAssertEqual(taskSection.rows.first?[2], "2025\u{2011}12\u{2011}24")

        guard let protocolSection = document.sections.first(where: { $0.title == "Protokoll" }) else {
            XCTFail("Document is missing the Protokoll section")
            return
        }
        XCTAssertEqual(protocolSection.layoutKind, "protocol")
        XCTAssertEqual(
            protocolSection.subsections.map(\.title),
            [
                "2025-05-01 – Uppstartsmöte",
                "2025-12-24 – Skicka ansökan",
                "2026-02-01 – Styrgruppsmöte",
            ]
        )
        let firstEntry = protocolSection.subsections[0]
        XCTAssertEqual(
            firstEntry.richParagraphs.map { $0.runs.map(\.text).joined() },
            ["Deltagare: Anna Andersson, Bo Berg", "Projektet startades."]
        )
        // The "Deltagare: " line label is bold; the names are not.
        XCTAssertEqual(firstEntry.richParagraphs.first?.runs.first?.text, "Deltagare: ")
        XCTAssertEqual(firstEntry.richParagraphs.first?.runs.first?.bold, true)
        XCTAssertEqual(firstEntry.richParagraphs.first?.runs.last?.bold, false)
        let newestEntry = protocolSection.subsections[2]
        XCTAssertEqual(
            newestEntry.richParagraphs.map { $0.runs.map(\.text).joined() },
            ["Budgeten godkändes.", "Nästa möte i mars."]
        )

        // The calendar table lists every linked meeting, protocol or not.
        guard let calendarSection = document.sections.first(where: { $0.title == "Kalenderhändelser" }) else {
            XCTFail("Document is missing the Kalenderhändelser section")
            return
        }
        XCTAssertEqual(calendarSection.rows.count, 3)
        // Collaborators show as initials in table participant columns;
        // non-collaborators keep full names. Protocol entries keep full names.
        XCTAssertEqual(calendarSection.rows.first?[4], "AA, Bo Berg")

        // The statistics section sits between Sammanfattning and Medarbetare.
        let titles = document.sections.map(\.title)
        XCTAssertEqual(titles.prefix(3), ["Sammanfattning", "Statistik", "Medarbetare"])
        let statisticsSection = document.sections[1]
        XCTAssertTrue(statisticsSection.subsections.contains { $0.title == "Aktiviteter" && !$0.bars.isEmpty })
    }

    @MainActor
    func testProjectSummaryDocumentHonorsSectionSelectionAndUniqueInitials() {
        var project = ProjectRecord(nameSv: "Urvalsprojekt", nameEn: "Selection project")
        project.collaboratorNames = ["Per Grönvik", "Paula Gustavsdotter"]
        let meeting = CalendarMeetingRecord(
            date: "2026-03-03",
            title: "Möte",
            participantNames: ["Per Grönvik", "Paula Gustavsdotter", "Extern Person"],
            projectIDs: [project.id]
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [meeting]
        let store = GrantDataStore(metadata: metadata, projects: [project])

        let document = store.projectSummaryDocument(
            for: project,
            exportLanguage: .swedish,
            includedSections: [.summary, .calendar]
        )
        XCTAssertNil(document.sections.first(where: { $0.title == "Protokoll" }))
        XCTAssertNil(document.sections.first(where: { $0.title == "Statistik" }))

        guard let calendarSection = document.sections.first(where: { $0.title == "Kalenderhändelser" }) else {
            XCTFail("Document is missing the Kalenderhändelser section")
            return
        }
        // Shared "PG" initials extend the first name until they differ.
        XCTAssertEqual(calendarSection.rows.first?[4], "PeG, PaG, Extern Person")
    }

    func testProtocolMarkupRoundTripsFormattingAndBullets() {
        let markup = "**Beslut**: fortsätt med *budgeten* enligt __plan__.\n• Första punkten\n• *Kursiv* punkt"
        let document = ProtocolMarkup.document(from: markup)

        XCTAssertEqual(document.paragraphs.count, 3)
        let firstRuns = document.paragraphs[0].runs
        XCTAssertEqual(firstRuns.first?.text, "Beslut")
        XCTAssertEqual(firstRuns.first?.bold, true)
        XCTAssertTrue(firstRuns.contains { $0.text == "budgeten" && $0.italic && !$0.bold })
        XCTAssertTrue(firstRuns.contains { $0.text == "plan" && $0.underline })
        XCTAssertEqual(document.paragraphs[1].plainText, "• Första punkten")

        // Serialize → parse must be lossless for exactly these features.
        let reserialized = ProtocolMarkup.markup(from: document)
        XCTAssertEqual(ProtocolMarkup.document(from: reserialized).paragraphs.map(\.plainText), document.paragraphs.map(\.plainText))
        XCTAssertEqual(reserialized, markup)

        // Literal marker characters survive an editor round trip via escapes.
        let literal = CVRichTextDocument(paragraphs: [
            CVRichTextParagraph(runs: [CVRichTextRun(text: "a*b och c__d")])
        ])
        let escaped = ProtocolMarkup.markup(from: literal)
        XCTAssertEqual(ProtocolMarkup.document(from: escaped).paragraphs.first?.plainText, "a*b och c__d")

        let exportParagraphs = ProtocolMarkup.exportParagraphs(from: markup)
        XCTAssertEqual(exportParagraphs.count, 3)
        XCTAssertEqual(exportParagraphs[0].runs.first?.bold, true)
        XCTAssertEqual(exportParagraphs[2].runs.contains { $0.italic }, true)
    }

    func testProtocolMarkupPreservesEmptyParagraphsAndBulletLevels() {
        let markup = "Rad ett\n\n• Nivå ett\n◦ Nivå två\n▪ Nivå tre"
        let document = ProtocolMarkup.document(from: markup)

        // The deliberately empty paragraph survives parse and re-serialize.
        XCTAssertEqual(document.paragraphs.map(\.plainText), ["Rad ett", "", "• Nivå ett", "◦ Nivå två", "▪ Nivå tre"])
        XCTAssertEqual(ProtocolMarkup.markup(from: document), markup)
        XCTAssertEqual(ProtocolMarkup.exportParagraphs(from: markup).count, 5)

        XCTAssertNil(ProtocolMarkup.bulletLevel(ofLine: "Rad ett"))
        XCTAssertEqual(ProtocolMarkup.bulletLevel(ofLine: "• Nivå ett"), 1)
        XCTAssertEqual(ProtocolMarkup.bulletLevel(ofLine: "◦ Nivå två"), 2)
        XCTAssertEqual(ProtocolMarkup.bulletLevel(ofLine: "▪ Nivå tre"), 3)
        XCTAssertEqual(ProtocolMarkup.bulletPrefix(forLevel: 2), "◦ ")
        XCTAssertEqual(ProtocolMarkup.maxBulletLevel, 3)
    }

    @MainActor
    func testProjectDocumentHTMLKeepsEmptyParagraphsAndNestedBullets() {
        var project = ProjectRecord(nameSv: "Nivåprojekt", nameEn: "Level project")
        project.collaboratorNames = []
        let meeting = CalendarMeetingRecord(
            date: "2026-04-01",
            title: "Planeringsmöte",
            projectIDs: [project.id],
            protocolText: "Inledning.\n\n• Punkt\n◦ Underpunkt\n▪ Detalj"
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [meeting]
        let store = GrantDataStore(metadata: metadata, projects: [project])
        let document = store.projectSummaryDocument(for: project, exportLanguage: .swedish)

        guard let protocolSection = document.sections.first(where: { $0.title == "Protokoll" }),
              let entry = protocolSection.subsections.first else {
            XCTFail("Document is missing the protocol entry")
            return
        }
        // The empty paragraph between "Inledning." and the list is kept.
        XCTAssertEqual(
            entry.richParagraphs.map { $0.runs.map(\.text).joined() },
            ["Inledning.", "", "• Punkt", "◦ Underpunkt", "▪ Detalj"]
        )

        let html = htmlPreview(for: document)
        XCTAssertTrue(html.contains("<p>&nbsp;</p>"))
        XCTAssertTrue(html.contains("<p class=\"bullet-paragraph\">• Punkt</p>"))
        XCTAssertTrue(html.contains("<p class=\"bullet-paragraph bullet-level-2\">◦ Underpunkt</p>"))
        XCTAssertTrue(html.contains("<p class=\"bullet-paragraph bullet-level-3\">▪ Detalj</p>"))
    }

    @MainActor
    func testApplicationSummaryDocumentAggregatesLinkedRecords() {
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Vetenskapsrådet",
            grantName: "Projektbidrag"
        )
        let meeting = CalendarMeetingRecord(
            date: "2026-01-15",
            title: "Anslagsmöte",
            applicationIDs: ["app-1"],
            protocolText: "Diskuterade budgeten."
        )
        let task = TaskItem(
            deadline: "2026-03-01",
            comment: "Skicka rapport",
            links: [TaskLink(kind: .application, targetID: "app-1")],
            protocolText: "Rapporten planerad."
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [meeting]
        metadata.taskItems = [task]
        let store = GrantDataStore(applications: [application], metadata: metadata)

        let document = store.applicationSummaryDocument(for: application, exportLanguage: .swedish)
        XCTAssertEqual(document.title, "Projektbidrag")

        guard let summarySection = document.sections.first(where: { $0.title == "Sammanfattning" }) else {
            XCTFail("Document is missing the Sammanfattning section")
            return
        }
        XCTAssertTrue(summarySection.rows.contains(["Kalenderhändelser", "1"]))
        XCTAssertTrue(summarySection.rows.contains(["Uppgifter", "1"]))
        XCTAssertTrue(summarySection.rows.contains(["Protokollförda poster", "2"]))

        XCTAssertEqual(document.sections.first(where: { $0.title == "Kalenderhändelser" })?.rows.count, 1)
        XCTAssertEqual(document.sections.first(where: { $0.title == "Uppgifter" })?.rows.count, 1)

        guard let protocolSection = document.sections.first(where: { $0.title == "Protokoll" }) else {
            XCTFail("Document is missing the Protokoll section")
            return
        }
        XCTAssertEqual(
            protocolSection.subsections.map(\.title),
            ["2026-01-15 – Anslagsmöte", "2026-03-01 – Skicka rapport"]
        )

        // Section selection is honored, exactly like the project document.
        let limited = store.applicationSummaryDocument(
            for: application,
            exportLanguage: .swedish,
            includedSections: [.summary]
        )
        XCTAssertNil(limited.sections.first(where: { $0.title == "Protokoll" }))
        XCTAssertNil(limited.sections.first(where: { $0.title == "Kalenderhändelser" }))
    }

    @MainActor
    func testPublicationSummaryDocumentAggregatesLinkedRecords() {
        var publication = PublicationRecord(id: "pub-1", title: "Min artikel", year: "2024")
        publication.journal = "Tidskriften"
        publication.publicationTasks = [
            PublicationTaskItem(deadline: "2026-02-01", comment: "Revidera", protocolText: "Revision klar.")
        ]
        let meeting = CalendarMeetingRecord(
            date: "2026-01-10",
            title: "Manusmöte",
            publicationIDs: ["pub-1"],
            protocolText: "Gick igenom manuset."
        )
        let centralTask = TaskItem(
            deadline: "2026-04-01",
            comment: "Skicka in",
            links: [TaskLink(kind: .publication, targetID: "pub-1")],
            protocolText: "Inskickat."
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [meeting]
        metadata.taskItems = [centralTask]
        let store = GrantDataStore(metadata: metadata, publicationRecords: [publication])

        let document = store.publicationSummaryDocument(for: publication, exportLanguage: .swedish)
        XCTAssertEqual(document.title, "Min artikel")
        XCTAssertEqual(document.subtitle, "Tidskriften, 2024")

        guard let referenceSection = document.sections.first(where: { $0.title == "Referens" }) else {
            XCTFail("Document is missing the Referens section")
            return
        }
        XCTAssertEqual(referenceSection.subsections.first?.amaItems.count, 1)

        // The publication's own legacy task and the central task both count.
        XCTAssertEqual(document.sections.first(where: { $0.title == "Uppgifter" })?.rows.count, 2)
        XCTAssertEqual(document.sections.first(where: { $0.title == "Kalenderhändelser" })?.rows.count, 1)

        guard let protocolSection = document.sections.first(where: { $0.title == "Protokoll" }) else {
            XCTFail("Document is missing the Protokoll section")
            return
        }
        XCTAssertEqual(
            protocolSection.subsections.map(\.title),
            ["2026-01-10 – Manusmöte", "2026-02-01 – Revidera", "2026-04-01 – Skicka in"]
        )

        // The empty funding section is filtered out entirely.
        XCTAssertNil(document.sections.first(where: { $0.title == "Finansiering" }))
    }

    @MainActor
    func testProjectSummaryDocumentWithoutProtocolsKeepsHeadingWithPlaceholder() {
        let project = ProjectRecord(nameSv: "Tomt projekt", nameEn: "Empty project")
        let store = GrantDataStore(projects: [project])
        let document = store.projectSummaryDocument(for: project, exportLanguage: .swedish)

        guard let protocolSection = document.sections.first(where: { $0.title == "Protokoll" }) else {
            XCTFail("Document is missing the Protokoll section")
            return
        }
        XCTAssertTrue(protocolSection.subsections.isEmpty)
        XCTAssertEqual(protocolSection.paragraphs.count, 1)
    }
}
