import XCTest
@testable import Footprint

/// Befattningar och examina som listval, flytten från fritext, föreslaget
/// karriärsteg och titeln. Alla namn och värden här är påhittade.
final class ResearcherPositionListTests: XCTestCase {
    private typealias P = ResearcherPositionOption.BuiltInID
    private typealias D = ResearcherDegreeOption.BuiltInID

    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResearcherPositionListTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
        ResearcherOptionRegistry.replace()
    }

    override func tearDown() {
        ResearcherOptionRegistry.replace()
        unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
        if let storageDirectory {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        storageDirectory = nil
        super.tearDown()
    }

    private var positions: [ResearcherPositionOption] { ResearcherPositionOption.builtInOptions }
    private var degrees: [ResearcherDegreeOption] { ResearcherDegreeOption.builtInOptions }

    private func options(_ ids: [String]) -> [ResearcherPositionOption] {
        ids.compactMap { id in positions.first { $0.id == id } }
    }

    // MARK: - Lagring

    func testOldResearcherJSONWithoutNewFieldsDecodesUnchanged() throws {
        let json = #"""
        {"id":"r1","firstName":"Testa","lastName":"Påhittad","titleSv":"Docent","titleEn":"Associate Professor",
         "positionSv":"Överläkare","positionEn":"Senior consultant","degreeSv":"Läkarexamen","degreeEn":"MD",
         "hasPhD":true,"careerStage":"B"}
        """#
        let author = try JSONDecoder().decode(PublicationAuthor.self, from: Data(json.utf8))

        XCTAssertEqual(author.positionIDs, [])
        XCTAssertEqual(author.positionOtherSv, "")
        XCTAssertEqual(author.positionOtherEn, "")
        XCTAssertFalse(author.isDocent)
        XCTAssertEqual(author.degreeEntries, [])
        XCTAssertEqual(author.titleSv, "Docent")
        XCTAssertEqual(author.positionSv, "Överläkare")
        XCTAssertEqual(author.positionEn, "Senior consultant")
        XCTAssertEqual(author.degreeEn, "MD")
        XCTAssertEqual(author.careerStage, .categoryB)
        XCTAssertTrue(author.hasPhD)

        // Saved again, it gets none of the new keys.
        let encoded = try JSONEncoder().encode(author)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["positionIDs", "positionOtherSv", "positionOtherEn", "isDocent", "degreeEntries"] {
            XCTAssertNil(object[key], key)
        }
    }

    func testOldResearcherWithoutCareerStageKeyStillGetsTheOldSuggestion() throws {
        let json = #"{"id":"r2","firstName":"Kim","lastName":"Exempel","hasPhD":true}"#
        let author = try JSONDecoder().decode(PublicationAuthor.self, from: Data(json.utf8))
        XCTAssertEqual(author.careerStage, .categoryB)
    }

    func testNewFieldsRoundTrip() throws {
        let author = PublicationAuthor(
            id: "r3",
            firstName: "Lo",
            lastName: "Exempel",
            hasPhD: true,
            careerStage: .categoryB,
            positionIDs: [P.seniorLecturer, P.seniorConsultant],
            positionOtherSv: "Påhittad roll",
            positionOtherEn: "Invented role",
            isDocent: true,
            degreeEntries: [
                ResearcherDegreeEntry(id: "d1", optionID: D.medical),
                ResearcherDegreeEntry(id: "d2", optionID: D.master, subjectSv: "Epidemiologi", subjectEn: "Epidemiology"),
                ResearcherDegreeEntry(id: "d3", otherText: "Påhittad examen"),
            ]
        )
        let decoded = try JSONDecoder().decode(PublicationAuthor.self, from: JSONEncoder().encode(author))
        XCTAssertEqual(decoded, author)
        XCTAssertEqual(decoded.positionIDs, [P.seniorLecturer, P.seniorConsultant])
        XCTAssertTrue(decoded.isDocent)
        XCTAssertEqual(decoded.degreeEntries.map(\.id), ["d1", "d2", "d3"])
    }

    func testOptionListsRoundTripAndMissingListsUseTheBuiltInOnes() throws {
        var metadata = DataSourceMetadata.bundledDefault
        XCTAssertNil(metadata.researcherPositionOptions)
        XCTAssertNil(metadata.researcherDegreeOptions)
        XCTAssertEqual(ResearcherPositionOption.resolvedOptions(nil), positions)
        XCTAssertEqual(ResearcherDegreeOption.resolvedOptions(nil), degrees)

        var changed = positions
        changed[0].nameSv = "Professor (påhittat namn)"
        changed.append(ResearcherPositionOption(id: "custom-1", nameSv: "Egen", nameEn: "Own", group: .other, careerStageHint: .categoryC))
        metadata.researcherPositionOptions = changed
        metadata.researcherDegreeOptions = degrees

        let decoded = try JSONDecoder().decode(DataSourceMetadata.self, from: JSONEncoder().encode(metadata))
        XCTAssertEqual(decoded.researcherPositionOptions, metadata.researcherPositionOptions)
        XCTAssertEqual(decoded.researcherDegreeOptions, metadata.researcherDegreeOptions)

        // Metadata saved by an older version has no list keys.
        let oldMetadata = try JSONEncoder().encode(DataSourceMetadata.bundledDefault)
        let oldDecoded = try JSONDecoder().decode(DataSourceMetadata.self, from: oldMetadata)
        XCTAssertNil(oldDecoded.researcherPositionOptions)
    }

    func testBuiltInListsHaveUniqueIDs() {
        XCTAssertEqual(Set(positions.map(\.id)).count, positions.count)
        XCTAssertEqual(Set(degrees.map(\.id)).count, degrees.count)
        XCTAssertEqual(positions.first { $0.id == P.phdStudent }?.careerStageHint, .categoryD)
        XCTAssertEqual(positions.first { $0.id == P.professor }?.careerStageHint, .categoryA)
        XCTAssertEqual(positions.first { $0.id == P.associateProfessor }?.givesProfessorTitle, false)
    }

    // MARK: - Flytten: befattningar

    func testPositionMapping() {
        typealias R = ResearcherLegacyFieldMapping
        XCTAssertEqual(R.mapPositionText("Professor").positionIDs, [P.professor])
        XCTAssertEqual(R.mapPositionText("PhD Student").positionIDs, [P.phdStudent])
        XCTAssertEqual(R.mapPositionText("PhD candidate").positionIDs, [P.phdStudent])
        XCTAssertEqual(R.mapPositionText("Doktorand").positionIDs, [P.phdStudent])
        XCTAssertEqual(R.mapPositionText("Medical student").positionIDs, [P.medicalStudent])
        XCTAssertEqual(R.mapPositionText("Läkarstudent").positionIDs, [P.medicalStudent])
        XCTAssertEqual(R.mapPositionText("Post-doc").positionIDs, [P.postdoc])
        XCTAssertEqual(R.mapPositionText("Postdoktor").positionIDs, [P.postdoc])
        XCTAssertEqual(R.mapPositionText("Adjunct Professor").positionIDs, [P.adjunctProfessor])
        XCTAssertEqual(R.mapPositionText("Professor Emeritus").positionIDs, [P.professorEmeritus])
        XCTAssertEqual(R.mapPositionText("Senior Professor").positionIDs, [P.seniorProfessor])
        XCTAssertEqual(R.mapPositionText("Biträdande universitetslektor").positionIDs, [P.assistantProfessor])
        XCTAssertEqual(R.mapPositionText("Assistant Professor").positionIDs, [P.assistantProfessor])
        XCTAssertEqual(R.mapPositionText("Affiliated to Research").positionIDs, [P.affiliatedResearcher])
        XCTAssertEqual(R.mapPositionText("Anknuten till forskning").positionIDs, [P.affiliatedResearcher])
        XCTAssertEqual(R.mapPositionText("Affilierad forskare").positionIDs, [P.affiliatedResearcher])
        XCTAssertEqual(R.mapPositionText("Forskare").positionIDs, [P.researcher])
        XCTAssertEqual(R.mapPositionText("Research engineer").positionIDs, [P.researchEngineer])
        XCTAssertEqual(R.mapPositionText("Statistiker").positionIDs, [P.statistician])
        XCTAssertEqual(R.mapPositionText("Verksamhetschef").positionIDs, [P.headOfDepartment])
        XCTAssertEqual(R.mapPositionText("Forskningssjuksköterska").positionIDs, [P.researchNurse])
        XCTAssertEqual(R.mapPositionText("Biomedicinsk analytiker").positionIDs, [P.biomedicalScientist])
        XCTAssertEqual(R.mapPositionText("Lecturer").positionIDs, [P.lecturer])
        XCTAssertEqual(R.mapPositionText("General practitioner").positionIDs, [P.specialistPhysician])
        XCTAssertEqual(R.mapPositionText("Allmänläkare").positionIDs, [P.specialistPhysician])
    }

    func testAssociateProfessorBecomesSeniorLecturerAndDocent() {
        typealias R = ResearcherLegacyFieldMapping
        for text in ["Associate Professor", "Senior Associate Professor"] {
            let result = R.mapPositionText(text)
            XCTAssertEqual(result.positionIDs, [P.seniorLecturer], text)
            XCTAssertTrue(result.isDocent, text)
            XCTAssertEqual(result.unmappedParts, [], text)
        }
        let adjunct = R.mapPositionText("Adjunct Associate Professor")
        XCTAssertEqual(adjunct.positionIDs, [P.adjunctSeniorLecturer])
        XCTAssertTrue(adjunct.isDocent)
    }

    func testCombinedPositionsAreSplit() {
        typealias R = ResearcherLegacyFieldMapping
        let lecturer = R.mapPositionText("Universitetslektor, Docent")
        XCTAssertEqual(lecturer.positionIDs, [P.seniorLecturer])
        XCTAssertTrue(lecturer.isDocent)

        let clinic = R.mapPositionText("Överläkare, docent")
        XCTAssertEqual(clinic.positionIDs, [P.seniorConsultant])
        XCTAssertTrue(clinic.isDocent)

        XCTAssertEqual(R.mapPositionText("Doktorand och AT-läkare").positionIDs, [P.phdStudent, P.internPhysician])
        XCTAssertEqual(R.mapPositionText("ST-läkare, docent").positionIDs, [P.residentPhysician])
        XCTAssertEqual(
            R.mapPositionText("Adjungerad universitetslektor, Specialistläkare i allmänmedicin").positionIDs,
            [P.adjunctSeniorLecturer, P.specialistPhysician]
        )
    }

    func testUnknownPositionTextIsKeptAsUnmapped() {
        typealias R = ResearcherLegacyFieldMapping
        let director = R.mapPositionText("Director, Påhittade institutet")
        XCTAssertEqual(director.positionIDs, [])
        XCTAssertEqual(director.unmappedParts, ["Director", "Påhittade institutet"])

        XCTAssertEqual(R.mapPositionText("Medical Doctor").unmappedParts, ["Medical Doctor"])
        XCTAssertEqual(R.mapPositionText("MD").unmappedParts, ["MD"])
        XCTAssertEqual(R.mapPositionText("Nurse Practitioner").unmappedParts, ["Nurse Practitioner"])
        XCTAssertEqual(R.mapPositionText("Senior Research Fellow").unmappedParts, ["Senior Research Fellow"])

        let mixed = R.mapPositionText("Specialistläkare, Påhittad chefsroll")
        XCTAssertEqual(mixed.positionIDs, [P.specialistPhysician])
        XCTAssertEqual(mixed.unmappedParts, ["Påhittad chefsroll"])
    }

    // MARK: - Flytten: examina

    func testDegreeMapping() {
        typealias R = ResearcherLegacyFieldMapping
        XCTAssertEqual(R.mapDegreeText("MD").matches, [.init(optionID: D.medical, subject: "")])
        XCTAssertEqual(R.mapDegreeText("RN").matches, [.init(optionID: D.nursing, subject: "")])
        XCTAssertEqual(R.mapDegreeText("Apotekarexamen").matches, [.init(optionID: D.pharmacy, subject: "")])
        XCTAssertEqual(R.mapDegreeText("Civil Engineer").matches, [.init(optionID: D.engineering, subject: "")])
        XCTAssertEqual(
            R.mapDegreeText("MBBS, MSc (Epidemiology)").matches,
            [.init(optionID: D.medical, subject: ""), .init(optionID: D.master, subject: "Epidemiology")]
        )
        XCTAssertEqual(R.mapDegreeText("MSc in Public Health").matches, [.init(optionID: D.master, subject: "Public Health")])
        XCTAssertEqual(R.mapDegreeText("Master i folkhälsovetenskap").matches, [.init(optionID: D.master, subject: "folkhälsovetenskap")])
        XCTAssertEqual(R.mapDegreeText("BSc Nursing").matches, [.init(optionID: D.bachelor, subject: "Nursing")])
        XCTAssertEqual(R.mapDegreeText("MSc").matches, [.init(optionID: D.master, subject: "")])

        let unknown = R.mapDegreeText("Påhittad examen")
        XCTAssertEqual(unknown.matches, [])
        XCTAssertEqual(unknown.unmappedParts, ["Påhittad examen"])
    }

    // MARK: - Flytten: en forskare

    func testMigrationFillsOnlyTheNewFields() {
        let author = PublicationAuthor(
            id: "r4",
            firstName: "Alva",
            lastName: "Exempel",
            title: "Dr",
            positionSv: "Universitetslektor, docent, Påhittad roll",
            positionEn: "Senior Lecturer, Associate Professor, Invented role",
            degreeSv: "Läkarexamen",
            degreeEn: "MD, MSc (Epidemiology)",
            hasPhD: true,
            careerStage: .categoryC
        )
        let migrated = ResearcherLegacyFieldMapping.migrated(author)

        XCTAssertEqual(migrated.positionIDs, [P.seniorLecturer])
        XCTAssertTrue(migrated.isDocent)
        XCTAssertEqual(migrated.positionOtherSv, "Påhittad roll")
        XCTAssertEqual(migrated.positionOtherEn, "Invented role")
        XCTAssertEqual(migrated.degreeEntries.map(\.optionID), [D.medical, D.master])
        XCTAssertEqual(migrated.degreeEntries.last?.subjectEn, "Epidemiology")

        // Nothing else changes.
        XCTAssertEqual(migrated.careerStage, .categoryC)
        XCTAssertTrue(migrated.hasPhD)
        XCTAssertEqual(migrated.positionSv, author.positionSv)
        XCTAssertEqual(migrated.positionEn, author.positionEn)
        XCTAssertEqual(migrated.degreeSv, author.degreeSv)
        XCTAssertEqual(migrated.degreeEn, author.degreeEn)
        XCTAssertEqual(migrated.titleSv, author.titleSv)
        XCTAssertEqual(migrated.titleEn, author.titleEn)

        // Running it again changes nothing.
        XCTAssertEqual(ResearcherLegacyFieldMapping.migrated(migrated), migrated)
    }

    func testMigrationKeepsUnknownDegreeTextAsOtherDegree() {
        let author = PublicationAuthor(id: "r5", firstName: "Bo", lastName: "Exempel", degree: "Påhittad examen")
        let migrated = ResearcherLegacyFieldMapping.migrated(author)
        XCTAssertEqual(migrated.degreeEntries.count, 1)
        XCTAssertNil(migrated.degreeEntries.first?.optionID)
        XCTAssertEqual(migrated.degreeEntries.first?.otherText, "Påhittad examen")
    }

    func testMigrationLeavesResearchersWithChoicesAlone() {
        let author = PublicationAuthor(
            id: "r6",
            firstName: "Cia",
            lastName: "Exempel",
            position: "Professor",
            positionIDs: [P.researcher]
        )
        let migrated = ResearcherLegacyFieldMapping.migrated(author)
        XCTAssertEqual(migrated.positionIDs, [P.researcher])
    }

    func testOldDocentTitleMakesDocent() {
        let author = PublicationAuthor(id: "r7", firstName: "Di", lastName: "Exempel", title: "Docent")
        XCTAssertTrue(ResearcherLegacyFieldMapping.migrated(author).isDocent)
    }

    @MainActor
    func testStoreMigrationRunsOnceAndKeepsEveryResearcher() {
        let authors = [
            PublicationAuthor(id: "s1", firstName: "Eva", lastName: "Exempel", position: "Professor", hasPhD: true, careerStage: .categoryA),
            PublicationAuthor(id: "s2", firstName: "Filip", lastName: "Exempel", position: "Doktorand", careerStage: .categoryD),
            PublicationAuthor(id: "s3", firstName: "Gun", lastName: "Exempel"),
        ]
        let store = GrantDataStore(publicationAuthors: authors, skipInitialMigration: true)
        XCTAssertTrue(store.runResearcherOptionListMigration())
        XCTAssertEqual(store.publicationAuthors.count, 3)
        XCTAssertEqual(store.publicationAuthor(id: "s1")?.positionIDs, [P.professor])
        XCTAssertEqual(store.publicationAuthor(id: "s1")?.careerStage, .categoryA)
        XCTAssertEqual(store.publicationAuthor(id: "s2")?.positionIDs, [P.phdStudent])
        XCTAssertTrue(store.metadata.migrationLog?.contains { $0.key == "round20-researcher-position-degree-lists" } ?? false)
        XCTAssertFalse(store.runResearcherOptionListMigration(), "runs only once")
        XCTAssertFalse(store.migrateResearcherPositionsAndDegreesToLists(), "running again changes nothing")
    }

    // MARK: - Föreslaget karriärsteg

    func testSuggestedCareerStage() {
        typealias S = ResearcherCareerStageSuggestion
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.professor]), isDocent: false, hasPhD: true), .categoryA)
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.associateProfessor]), isDocent: true, hasPhD: true), .categoryB)
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.seniorLecturer]), isDocent: false, hasPhD: true), .categoryB)
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.assistantProfessor]), isDocent: false, hasPhD: true), .categoryC)
        XCTAssertNil(S.suggestedCareerStage(positions: options([P.researchEngineer]), isDocent: false, hasPhD: false))
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.researchAssistant]), isDocent: false, hasPhD: false), .categoryD)
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.seniorLecturer]), isDocent: true, hasPhD: true), .categoryB)
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.adjunctSeniorLecturer]), isDocent: true, hasPhD: true), .categoryB)
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.postdoc]), isDocent: false, hasPhD: true), .categoryC)
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.phdStudent]), isDocent: false, hasPhD: false), .categoryD)
        // Highest hint wins.
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.phdStudent, P.researcher]), isDocent: false, hasPhD: true), .categoryC)
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.seniorLecturer, P.professor]), isDocent: true, hasPhD: true), .categoryA)
        // Clinical positions give no hint: a docent with a PhD is B, a PhD alone gives no guess.
        XCTAssertEqual(S.suggestedCareerStage(positions: options([P.seniorConsultant]), isDocent: true, hasPhD: true), .categoryB)
        XCTAssertNil(S.suggestedCareerStage(positions: options([P.seniorConsultant]), isDocent: false, hasPhD: true))
        XCTAssertNil(S.suggestedCareerStage(positions: [], isDocent: false, hasPhD: true))
        XCTAssertNil(S.suggestedCareerStage(positions: options([P.medicalStudent]), isDocent: false, hasPhD: false))
        XCTAssertNil(S.suggestedCareerStage(positions: [], isDocent: false, hasPhD: false))
    }

    // MARK: - Titel

    func testSuggestedTitle() {
        typealias S = ResearcherCareerStageSuggestion
        XCTAssertEqual(S.suggestedTitle(positions: options([P.professor]), isDocent: true, hasPhD: true, language: .swedish), "Professor")
        XCTAssertEqual(S.suggestedTitle(positions: options([P.professorEmeritus]), isDocent: false, hasPhD: true, language: .english), "Professor")
        XCTAssertEqual(S.suggestedTitle(positions: options([P.associateProfessor]), isDocent: true, hasPhD: true, language: .swedish), "Docent")
        XCTAssertEqual(S.suggestedTitle(positions: options([P.associateProfessor]), isDocent: true, hasPhD: true, language: .english), "Associate Professor")
        XCTAssertEqual(S.suggestedTitle(positions: options([P.postdoc]), isDocent: false, hasPhD: true, language: .swedish), "Dr")
        XCTAssertEqual(S.suggestedTitle(positions: options([P.phdStudent]), isDocent: false, hasPhD: false, language: .swedish), "")
    }

    func testDisplayTitleFallsBackToTheOldTitle() {
        // No choices yet: the old title is kept (not replaced by "Dr").
        let legacy = PublicationAuthor(id: "t1", firstName: "Hans", lastName: "Exempel", title: "Professor", hasPhD: true)
        XCTAssertEqual(legacy.displayTitle(language: .swedish, options: positions), "Professor")

        // Choices made: the worked-out title is used.
        var chosen = legacy
        chosen.positionIDs = [P.postdoc]
        XCTAssertEqual(chosen.displayTitle(language: .swedish, options: positions), "Dr")

        // Choices that give no title fall back to the old title.
        var student = PublicationAuthor(id: "t2", firstName: "Ida", lastName: "Exempel", title: "Leg. läkare")
        student.positionIDs = [P.medicalStudent]
        XCTAssertEqual(student.displayTitle(language: .swedish, options: positions), "Leg. läkare")

        // Nothing at all: derived from PhD.
        let phd = PublicationAuthor(id: "t3", firstName: "Jon", lastName: "Exempel", hasPhD: true)
        XCTAssertEqual(phd.displayTitle(language: .english, options: positions), "Dr")
    }

    // MARK: - Visning

    func testDisplayPositionAndDegreeUseTheListNames() {
        var author = PublicationAuthor(
            id: "v1",
            firstName: "Klara",
            lastName: "Exempel",
            positionSv: "Gammal text",
            positionEn: "Old text",
            degree: "Gammal examen"
        )
        XCTAssertEqual(author.displayPosition(language: .swedish, options: positions), "Gammal text")
        XCTAssertEqual(author.displayDegree(language: .swedish, options: degrees), "Gammal examen")

        author.positionIDs = [P.seniorLecturer, P.seniorConsultant]
        author.positionOtherSv = "Påhittad roll"
        XCTAssertEqual(author.displayPosition(language: .swedish, options: positions), "Universitetslektor, Överläkare, Påhittad roll")
        XCTAssertEqual(author.displayPosition(language: .english, options: positions), "Senior Lecturer, Senior Consultant, Påhittad roll")

        author.degreeEntries = [
            ResearcherDegreeEntry(optionID: D.medical),
            ResearcherDegreeEntry(optionID: D.master, subjectEn: "Epidemiology"),
        ]
        XCTAssertEqual(author.displayDegree(language: .english, options: degrees), "MD, MSc (Epidemiology)")

        // Renaming the option changes the text everywhere.
        var renamed = positions
        if let index = renamed.firstIndex(where: { $0.id == P.seniorLecturer }) {
            renamed[index].nameSv = "Lektor (nytt namn)"
        }
        XCTAssertEqual(author.displayPosition(language: .swedish, options: renamed), "Lektor (nytt namn), Överläkare, Påhittad roll")
    }

    // MARK: - Ny forskare, datakvalitet och listor

    @MainActor
    func testNewResearcherStartsWithoutCareerStage() {
        let store = GrantDataStore(publicationAuthors: [], skipInitialMigration: true)
        let id = store.addPublicationAuthor()
        XCTAssertNil(store.publicationAuthor(id: id)?.careerStage)
    }

    @MainActor
    func testDataQualityFlagsStageMismatchAndTextOutsideTheLists() {
        let mismatch = PublicationAuthor(
            id: "q1",
            firstName: "Lars",
            lastName: "Exempel",
            hasPhD: true,
            careerStage: .categoryC,
            positionIDs: [P.seniorLecturer],
            isDocent: true
        )
        let outside = PublicationAuthor(
            id: "q2",
            firstName: "Mia",
            lastName: "Exempel",
            hasPhD: true,
            careerStage: .categoryB,
            positionIDs: [P.associateProfessor],
            positionOtherSv: "Påhittad roll",
            degreeEntries: [ResearcherDegreeEntry(otherText: "Påhittad examen")]
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        let store = GrantDataStore(metadata: metadata, publicationAuthors: [mismatch, outside], skipInitialMigration: true)
        let issues = store.dataQualityCareerStageIssues()

        let stageIssue = issues.first { $0.recordID == "q1" && $0.id.hasSuffix("-careerStageSuggestion") }
        XCTAssertEqual(stageIssue?.subtitle, "Karriärsteg C stämmer inte med befattningen (förslag: B)")
        XCTAssertFalse(issues.contains { $0.recordID == "q2" && $0.id.hasSuffix("-careerStageSuggestion") })

        let positionIssue = issues.first { $0.recordID == "q2" && $0.id.hasSuffix("-positionOutsideList") }
        XCTAssertEqual(positionIssue?.subtitle, "Befattning utanför listan: Påhittad roll")
        let degreeIssue = issues.first { $0.recordID == "q2" && $0.id.hasSuffix("-degreeOutsideList") }
        XCTAssertEqual(degreeIssue?.subtitle, "Examen utanför listan: Påhittad examen")

        // The ids do not depend on the language.
        XCTAssertFalse(issues.contains { $0.id.contains("Befattning") || $0.id.contains("Karriärsteg") })
    }

    @MainActor
    func testOptionListsAreNotWrittenUntilChangedAndUsedOptionsAreKept() {
        let author = PublicationAuthor(id: "u1", firstName: "Nora", lastName: "Exempel", positionIDs: [P.statistician])
        let store = GrantDataStore(publicationAuthors: [author], skipInitialMigration: true)
        XCTAssertNil(store.metadata.researcherPositionOptions)
        XCTAssertEqual(store.researcherPositionOptions, positions)

        // Saving the unchanged list writes nothing.
        store.autosaveResearcherPositionOptions(store.researcherPositionOptions)
        XCTAssertNil(store.metadata.researcherPositionOptions)

        XCTAssertEqual(store.researcherPositionOptionUsageCounts()[P.statistician], 1)

        // An option in use is never dropped, even if left out.
        var edited = store.researcherPositionOptions.filter { $0.id != P.statistician }
        edited[0].nameSv = "Professor (nytt namn)"
        store.autosaveResearcherPositionOptions(edited)
        let saved = store.researcherPositionOptions
        XCTAssertTrue(saved.contains { $0.id == P.statistician })
        XCTAssertEqual(saved.first { $0.id == P.professor }?.nameSv, "Professor (nytt namn)")
    }
}
