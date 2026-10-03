import XCTest
@testable import Footprint

/// Läkarspecialiteter, ordningen på befattningar och snabbrättningarna i
/// Datakvalitet > Integritet. Alla namn och värden här är påhittade.
final class ResearcherSpecialtyAndQualityFixTests: XCTestCase {
    private typealias P = ResearcherPositionOption.BuiltInID
    private typealias D = ResearcherDegreeOption.BuiltInID
    private typealias S = ResearcherSpecialtyOption.BuiltInID
    private typealias R = ResearcherLegacyFieldMapping

    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResearcherSpecialtyAndQualityFixTests-\(UUID().uuidString)", isDirectory: true)
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
    private var specialties: [ResearcherSpecialtyOption] { ResearcherSpecialtyOption.builtInOptions }

    @MainActor
    private func swedishStore(_ authors: [PublicationAuthor]) -> GrantDataStore {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        return GrantDataStore(metadata: metadata, publicationAuthors: authors, skipInitialMigration: true)
    }

    @MainActor
    private func issue(_ store: GrantDataStore, authorID: String, suffix: String) -> GrantDataStore.IntegrityIssue? {
        store.dataQualityCareerStageIssues().first { $0.recordID == authorID && $0.id.hasSuffix(suffix) }
    }

    // MARK: - Lagring

    func testOldJSONWithoutSpecialtiesDecodesAndSavesWithoutTheKey() throws {
        let json = #"""
        {"id":"x1","firstName":"Testa","lastName":"Påhittad","positionSv":"Överläkare","hasPhD":true,"careerStage":"B",
         "positionIDs":["position-senior-consultant"]}
        """#
        let author = try JSONDecoder().decode(PublicationAuthor.self, from: Data(json.utf8))
        XCTAssertEqual(author.positionSpecialtyIDs, [:])
        XCTAssertEqual(author.positionIDs, [P.seniorConsultant])

        let encoded = try JSONEncoder().encode(author)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["positionSpecialtyIDs"])
        XCTAssertEqual(try JSONDecoder().decode(PublicationAuthor.self, from: encoded), author)
    }

    func testBrokenSpecialtyValueDecodesAsEmpty() throws {
        let json = #"{"id":"x2","firstName":"Kim","lastName":"Exempel","positionSpecialtyIDs":"inte en lista"}"#
        let author = try JSONDecoder().decode(PublicationAuthor.self, from: Data(json.utf8))
        XCTAssertEqual(author.positionSpecialtyIDs, [:])
    }

    func testSpecialtiesRoundTripAndAreKeptOnlyForChosenPositions() throws {
        let author = PublicationAuthor(
            id: "x3",
            firstName: "Lo",
            lastName: "Exempel",
            positionIDs: [P.specialistPhysician],
            positionSpecialtyIDs: [P.specialistPhysician: S.generalPractice, P.seniorConsultant: S.geriatrics]
        )
        // A specialty for a position that is not chosen is dropped.
        XCTAssertEqual(author.positionSpecialtyIDs, [P.specialistPhysician: S.generalPractice])
        let decoded = try JSONDecoder().decode(PublicationAuthor.self, from: JSONEncoder().encode(author))
        XCTAssertEqual(decoded, author)
        XCTAssertEqual(decoded.positionSpecialtyIDs[P.specialistPhysician], S.generalPractice)
    }

    func testSpecialtyListRoundTripAndBuiltInList() throws {
        XCTAssertEqual(specialties.count, 51)
        XCTAssertEqual(ResearcherSpecialtyOption.builtInPhysicianOptions.count, 37)
        XCTAssertEqual(ResearcherSpecialtyOption.builtInNurseOptions.count, 14)
        XCTAssertEqual(Set(specialties.map(\.id)).count, specialties.count)
        XCTAssertEqual(ResearcherSpecialtyOption.resolvedOptions(nil), specialties)

        var metadata = DataSourceMetadata.bundledDefault
        XCTAssertNil(metadata.researcherSpecialtyOptions)
        var changed = specialties
        changed.append(ResearcherSpecialtyOption(id: "custom-specialty", nameSv: "Påhittad specialitet", nameEn: "Invented Specialty"))
        metadata.researcherSpecialtyOptions = changed
        let decoded = try JSONDecoder().decode(DataSourceMetadata.self, from: JSONEncoder().encode(metadata))
        XCTAssertEqual(decoded.researcherSpecialtyOptions, metadata.researcherSpecialtyOptions)

        let oldDecoded = try JSONDecoder().decode(DataSourceMetadata.self, from: JSONEncoder().encode(DataSourceMetadata.bundledDefault))
        XCTAssertNil(oldDecoded.researcherSpecialtyOptions)
    }

    // MARK: - Visning och ordning

    func testDisplayTextWithSpecialty() {
        var author = PublicationAuthor(id: "v1", firstName: "Klara", lastName: "Exempel")
        author.positionIDs = [P.specialistPhysician]
        author.positionSpecialtyIDs = [P.specialistPhysician: S.generalPractice]
        XCTAssertEqual(author.displayPosition(language: .swedish, options: positions, specialtyOptions: specialties), "Specialistläkare i allmänmedicin")
        XCTAssertEqual(author.displayPosition(language: .english, options: positions, specialtyOptions: specialties), "Specialist Physician, General Practice")

        author.positionIDs = [P.seniorConsultant]
        author.positionSpecialtyIDs = [P.seniorConsultant: S.dermatology]
        XCTAssertEqual(author.displayPosition(language: .swedish, options: positions, specialtyOptions: specialties), "Överläkare i dermatologi och venereologi")

        author.positionIDs = [P.residentPhysician]
        author.positionSpecialtyIDs = [P.residentPhysician: S.internalMedicine]
        XCTAssertEqual(author.displayPosition(language: .swedish, options: positions, specialtyOptions: specialties), "ST-läkare i internmedicin")
        XCTAssertEqual(author.displayPosition(language: .english, options: positions, specialtyOptions: specialties), "Resident Physician, Internal Medicine")

        // Positions that cannot have a specialty never show one.
        author.positionIDs = [P.internPhysician]
        author.positionSpecialtyIDs = [P.internPhysician: S.surgery]
        XCTAssertEqual(author.displayPosition(language: .swedish, options: positions, specialtyOptions: specialties), "AT-läkare")

        // An abbreviation at the start keeps its capitals.
        XCTAssertEqual(ResearcherSpecialtyOption.inlineSwedishName("ÖNH-sjukdomar"), "ÖNH-sjukdomar")
        XCTAssertEqual(ResearcherSpecialtyOption.inlineSwedishName("Geriatrik"), "geriatrik")
    }

    func testPositionsAreShownAcademicThenClinicalThenOther() {
        var author = PublicationAuthor(id: "v2", firstName: "Mia", lastName: "Exempel")
        author.positionIDs = [P.statistician, P.seniorConsultant, P.seniorLecturer, P.phdStudent]
        XCTAssertEqual(
            author.selectedPositionOptions(options: positions).map(\.id),
            [P.seniorLecturer, P.phdStudent, P.seniorConsultant, P.statistician]
        )
        XCTAssertEqual(
            author.displayPosition(language: .swedish, options: positions, specialtyOptions: specialties),
            "Universitetslektor, Doktorand, Överläkare, Statistiker"
        )
        XCTAssertEqual(ResearcherPositionGroup.displayOrder, [.academic, .clinical, .other])

        // A custom academic option placed last in the list still comes before clinical ones.
        var custom = positions
        custom.append(ResearcherPositionOption(id: "custom-academic", nameSv: "Påhittad akademisk", nameEn: "Invented academic", group: .academic, sortOrder: 999))
        author.positionIDs = [P.seniorConsultant, "custom-academic"]
        XCTAssertEqual(author.selectedPositionOptions(options: custom).map(\.id), ["custom-academic", P.seniorConsultant])
    }

    // MARK: - Flytten från fritext

    func testPositionTextGivesSpecialties() {
        let general = R.mapPositionText("Specialistläkare i allmänmedicin")
        XCTAssertEqual(general.positionIDs, [P.specialistPhysician])
        XCTAssertEqual(general.specialtyIDs, [P.specialistPhysician: S.generalPractice])

        let obstetrics = R.mapPositionText("Överläkare i obstetrik och gynekologi")
        XCTAssertEqual(obstetrics.positionIDs, [P.seniorConsultant])
        XCTAssertEqual(obstetrics.specialtyIDs, [P.seniorConsultant: S.obstetrics])
        XCTAssertEqual(obstetrics.unmappedParts, [])

        let ent = R.mapPositionText("ST-läkare i öron-, näs- och halssjukdomar")
        XCTAssertEqual(ent.specialtyIDs, [P.residentPhysician: S.otorhinolaryngology])
        XCTAssertEqual(ent.unmappedParts, [])

        let loose = R.mapPositionText("Överläkare, geriatriker")
        XCTAssertEqual(loose.positionIDs, [P.seniorConsultant])
        XCTAssertEqual(loose.specialtyIDs, [P.seniorConsultant: S.geriatrics])
        XCTAssertEqual(loose.unmappedParts, [])

        let surgeon = R.mapPositionText("Kirurg")
        XCTAssertEqual(surgeon.positionIDs, [P.specialistPhysician])
        XCTAssertEqual(surgeon.specialtyIDs, [P.specialistPhysician: S.surgery])

        let gp = R.mapPositionText("Distriktsläkare")
        XCTAssertEqual(gp.specialtyIDs, [P.specialistPhysician: S.generalPractice])
        XCTAssertEqual(R.mapPositionText("General practitioner").specialtyIDs, [P.specialistPhysician: S.generalPractice])

        // A specialty word next to an academic position is not a physician specialty.
        let professor = R.mapPositionText("Professor i kirurgi")
        XCTAssertEqual(professor.positionIDs, [P.professor])
        XCTAssertEqual(professor.specialtyIDs, [:])

        // Two physician positions without a specialty: the loose word is kept as text.
        let twoPhysicians = R.mapPositionText("ST-läkare, Överläkare, kardiolog")
        XCTAssertEqual(twoPhysicians.specialtyIDs, [:])
        XCTAssertEqual(twoPhysicians.unmappedParts, ["kardiolog"])
    }

    func testFreshMigrationFillsSpecialtiesButNotTheOldText() {
        let author = PublicationAuthor(
            id: "m1",
            firstName: "Nils",
            lastName: "Exempel",
            positionSv: "Universitetslektor, Specialistläkare i allmänmedicin",
            positionEn: "Senior Lecturer, Specialist in General Practice",
            hasPhD: true,
            careerStage: .categoryB
        )
        let migrated = R.migrated(author)
        XCTAssertEqual(migrated.positionIDs, [P.seniorLecturer, P.specialistPhysician])
        XCTAssertEqual(migrated.positionSpecialtyIDs, [P.specialistPhysician: S.generalPractice])
        XCTAssertEqual(migrated.positionSv, author.positionSv)
        XCTAssertEqual(migrated.careerStage, .categoryB)
        XCTAssertTrue(migrated.hasPhD)
        XCTAssertEqual(R.migrated(migrated), migrated)
    }

    func testSpecialtyStepForResearchersAlreadyMigrated() {
        // Already migrated: physician position, specialty only in the old text.
        let fromOldText = PublicationAuthor(
            id: "b1",
            firstName: "Olle",
            lastName: "Exempel",
            positionSv: "Distriktsläkare",
            hasPhD: false,
            careerStage: nil,
            positionIDs: [P.specialistPhysician]
        )
        let first = R.migratedSpecialties(fromOldText)
        XCTAssertEqual(first.positionSpecialtyIDs, [P.specialistPhysician: S.generalPractice])
        XCTAssertEqual(first.positionSv, "Distriktsläkare")
        XCTAssertEqual(first.careerStage, fromOldText.careerStage)
        XCTAssertFalse(first.hasPhD)
        XCTAssertEqual(R.migratedSpecialties(first), first, "running again changes nothing")

        // The specialty word sits alone in "other": it is moved out of it.
        let fromOther = PublicationAuthor(
            id: "b2",
            firstName: "Pia",
            lastName: "Exempel",
            positionSv: "Överläkare, geriatriker",
            hasPhD: true,
            careerStage: .categoryC,
            positionIDs: [P.seniorConsultant],
            positionOtherSv: "geriatriker, Påhittad roll"
        )
        let second = R.migratedSpecialties(fromOther)
        XCTAssertEqual(second.positionSpecialtyIDs, [P.seniorConsultant: S.geriatrics])
        XCTAssertEqual(second.positionOtherSv, "Påhittad roll")
        XCTAssertEqual(second.positionSv, fromOther.positionSv)
        XCTAssertEqual(second.careerStage, .categoryC)
        XCTAssertEqual(R.migratedSpecialties(second), second)

        // "Kirurg" alone in "other" and no physician position: Specialistläkare i kirurgi.
        let surgeon = PublicationAuthor(id: "b3", firstName: "Rut", lastName: "Exempel", positionSv: "Kirurg", positionOtherSv: "Kirurg")
        let third = R.migratedSpecialties(surgeon)
        XCTAssertEqual(third.positionIDs, [P.specialistPhysician])
        XCTAssertEqual(third.positionSpecialtyIDs, [P.specialistPhysician: S.surgery])
        XCTAssertEqual(third.positionOtherSv, "")
        XCTAssertEqual(third.positionSv, "Kirurg")

        // Unsure (two physician positions without specialty): nothing changes.
        let unsure = PublicationAuthor(
            id: "b4",
            firstName: "Sam",
            lastName: "Exempel",
            positionIDs: [P.residentPhysician, P.seniorConsultant],
            positionOtherSv: "kardiolog"
        )
        XCTAssertEqual(R.migratedSpecialties(unsure), unsure)

        // A chosen specialty is never replaced.
        let chosen = PublicationAuthor(
            id: "b5",
            firstName: "Tea",
            lastName: "Exempel",
            positionSv: "Specialistläkare i allmänmedicin",
            positionIDs: [P.specialistPhysician],
            positionSpecialtyIDs: [P.specialistPhysician: S.cardiology]
        )
        XCTAssertEqual(R.migratedSpecialties(chosen), chosen)
    }

    @MainActor
    func testStoreSpecialtyStepRunsOnceAndKeepsEveryResearcher() {
        let authors = [
            PublicationAuthor(id: "s1", firstName: "Ulf", lastName: "Exempel", positionSv: "Överläkare i kardiologi", hasPhD: true, careerStage: .categoryB, positionIDs: [P.seniorConsultant]),
            PublicationAuthor(id: "s2", firstName: "Vera", lastName: "Exempel", position: "Doktorand", careerStage: .categoryD, positionIDs: [P.phdStudent]),
            PublicationAuthor(id: "s3", firstName: "Wim", lastName: "Exempel"),
        ]
        let store = GrantDataStore(publicationAuthors: authors, skipInitialMigration: true)
        XCTAssertTrue(store.runResearcherSpecialtyMigration())
        XCTAssertEqual(store.publicationAuthors.count, 3)
        XCTAssertEqual(store.publicationAuthor(id: "s1")?.positionSpecialtyIDs, [P.seniorConsultant: S.cardiology])
        XCTAssertEqual(store.publicationAuthor(id: "s1")?.careerStage, .categoryB)
        XCTAssertEqual(store.publicationAuthor(id: "s2")?.positionSpecialtyIDs, [:])
        XCTAssertTrue(store.metadata.migrationLog?.contains { $0.key == "round20b-physician-specialties" } ?? false)
        XCTAssertFalse(store.runResearcherSpecialtyMigration(), "runs only once")
        XCTAssertFalse(store.migrateResearcherPhysicianSpecialties(), "running again changes nothing")
        XCTAssertEqual(store.researcherSpecialtyOptionUsageCounts()[S.cardiology], 1)
    }

    @MainActor
    func testSpecialtyListIsNotWrittenUntilChangedAndUsedSpecialtiesAreKept() {
        let author = PublicationAuthor(
            id: "u1",
            firstName: "Yngve",
            lastName: "Exempel",
            positionIDs: [P.specialistPhysician],
            positionSpecialtyIDs: [P.specialistPhysician: S.urology]
        )
        let store = GrantDataStore(publicationAuthors: [author], skipInitialMigration: true)
        store.autosaveResearcherSpecialtyOptions(store.researcherSpecialtyOptions)
        XCTAssertNil(store.metadata.researcherSpecialtyOptions)

        let edited = store.researcherSpecialtyOptions.filter { $0.id != S.urology }
        store.autosaveResearcherSpecialtyOptions(edited)
        XCTAssertTrue(store.researcherSpecialtyOptions.contains { $0.id == S.urology })
    }

    // MARK: - Snabbrättningar i Datakvalitet

    @MainActor
    func testStageSuggestionCanBeUsedOrSetDirectly() {
        let author = PublicationAuthor(
            id: "f1", firstName: "Ada", lastName: "Exempel",
            hasPhD: true, careerStage: .categoryC,
            positionIDs: [P.seniorLecturer], isDocent: true
        )
        let store = swedishStore([author])
        let found = issue(store, authorID: "f1", suffix: "-careerStageSuggestion")
        XCTAssertNotNil(found)
        if let found {
            XCTAssertEqual(store.researcherIntegrityFix(for: found), .careerStageSuggestion(current: .categoryC, suggestion: .categoryB))
        }

        XCTAssertTrue(store.applyResearcherCareerStageSuggestion(authorID: "f1"))
        XCTAssertEqual(store.publicationAuthor(id: "f1")?.careerStage, .categoryB)
        XCTAssertNil(issue(store, authorID: "f1", suffix: "-careerStageSuggestion"))
        XCTAssertEqual(store.publicationAuthors.count, 1)

        // Setting another stage directly, then clearing it.
        XCTAssertTrue(store.setResearcherCareerStageFromDataQuality(authorID: "f1", stage: .categoryA))
        XCTAssertEqual(store.publicationAuthor(id: "f1")?.careerStage, .categoryA)
        XCTAssertTrue(store.setResearcherCareerStageFromDataQuality(authorID: "f1", stage: nil))
        XCTAssertNil(store.publicationAuthor(id: "f1")?.careerStage)
        XCTAssertNil(issue(store, authorID: "f1", suffix: "-careerStageSuggestion"))
        XCTAssertEqual(store.publicationAuthors.count, 1)
    }

    @MainActor
    func testPhDIssuesCanBeFixedWithThePhDBoxOrTheStage() {
        let missing = PublicationAuthor(id: "f2", firstName: "Bea", lastName: "Exempel", hasPhD: false, careerStage: .categoryB)
        let doctoral = PublicationAuthor(id: "f3", firstName: "Cid", lastName: "Exempel", hasPhD: true, careerStage: .categoryD)
        let store = swedishStore([missing, doctoral])

        let missingIssue = issue(store, authorID: "f2", suffix: "-careerStage-B-missingPhD")
        XCTAssertNotNil(missingIssue)
        if let missingIssue {
            XCTAssertEqual(store.researcherIntegrityFix(for: missingIssue), .careerStagePhD(current: .categoryB, hasPhD: false))
        }
        XCTAssertTrue(store.setResearcherPhDFromDataQuality(authorID: "f2", hasPhD: true))
        XCTAssertTrue(store.publicationAuthor(id: "f2")?.hasPhD ?? false)
        XCTAssertEqual(store.publicationAuthor(id: "f2")?.careerStage, .categoryB, "the stage is not changed")
        XCTAssertNil(issue(store, authorID: "f2", suffix: "-missingPhD"))

        XCTAssertNotNil(issue(store, authorID: "f3", suffix: "-careerStage-D-hasPhD"))
        XCTAssertTrue(store.setResearcherCareerStageFromDataQuality(authorID: "f3", stage: .categoryC))
        XCTAssertNil(issue(store, authorID: "f3", suffix: "-hasPhD"))
        XCTAssertEqual(store.publicationAuthors.count, 2)
    }

    @MainActor
    func testPositionOutsideTheListCanBeChosenFromTheList() {
        let author = PublicationAuthor(
            id: "f4", firstName: "Dan", lastName: "Exempel",
            positionIDs: [P.seniorLecturer],
            positionOtherSv: "Påhittad chefsroll, Överläkare i påhittad del av geriatrik"
        )
        let store = swedishStore([author])
        let found = issue(store, authorID: "f4", suffix: "-positionOutsideList")
        XCTAssertNotNil(found)
        if let found {
            XCTAssertEqual(
                store.researcherIntegrityFix(for: found),
                .positionOutsideList(parts: ["Påhittad chefsroll", "Överläkare i påhittad del av geriatrik"])
            )
        }

        XCTAssertTrue(store.chooseResearcherPositionForOutsideText(
            authorID: "f4",
            part: "Överläkare i påhittad del av geriatrik",
            optionID: P.seniorConsultant
        ))
        let updated = store.publicationAuthor(id: "f4")
        XCTAssertEqual(updated?.positionIDs, [P.seniorLecturer, P.seniorConsultant])
        XCTAssertEqual(updated?.positionSpecialtyIDs, [P.seniorConsultant: S.geriatrics])
        XCTAssertEqual(updated?.positionOtherSv, "Påhittad chefsroll")
        XCTAssertNotNil(issue(store, authorID: "f4", suffix: "-positionOutsideList"), "the other part is still outside the list")

        XCTAssertTrue(store.chooseResearcherPositionForOutsideText(authorID: "f4", part: "Påhittad chefsroll", optionID: P.headOfDepartment))
        XCTAssertEqual(store.publicationAuthor(id: "f4")?.positionOtherSv, "")
        XCTAssertNil(issue(store, authorID: "f4", suffix: "-positionOutsideList"))
        XCTAssertEqual(store.publicationAuthors.count, 1)
    }

    @MainActor
    func testPositionOutsideTheListCanBeAddedToTheList() {
        let author = PublicationAuthor(
            id: "f5", firstName: "Eli", lastName: "Exempel",
            positionOtherSv: "Påhittad roll",
            positionOtherEn: "Invented role"
        )
        let store = swedishStore([author])
        let optionCount = store.researcherPositionOptions.count
        XCTAssertTrue(store.addResearcherPositionToListFromDataQuality(authorID: "f5", part: "Påhittad roll", group: .clinical))

        let added = store.researcherPositionOptions.first { $0.nameSv == "Påhittad roll" }
        XCTAssertNotNil(added)
        XCTAssertEqual(added?.nameEn, "Invented role")
        XCTAssertEqual(added?.group, .clinical)
        XCTAssertEqual(store.researcherPositionOptions.count, optionCount + 1)
        let updated = store.publicationAuthor(id: "f5")
        XCTAssertEqual(updated?.positionIDs, added.map { [$0.id] })
        XCTAssertEqual(updated?.positionOtherSv, "")
        XCTAssertEqual(updated?.positionOtherEn, "")
        XCTAssertNil(issue(store, authorID: "f5", suffix: "-positionOutsideList"))
        XCTAssertEqual(updated?.displayPosition(language: .english), "Invented role")
        XCTAssertEqual(store.publicationAuthors.count, 1)
    }

    @MainActor
    func testDegreeOutsideTheListCanBeChosenWithoutLosingText() {
        let author = PublicationAuthor(
            id: "f6", firstName: "Fia", lastName: "Exempel",
            degreeEntries: [
                ResearcherDegreeEntry(id: "e1", otherText: "Master i påhittat ämne"),
                ResearcherDegreeEntry(id: "e2", otherText: "Påhittad examen"),
            ]
        )
        let store = swedishStore([author])
        let found = issue(store, authorID: "f6", suffix: "-degreeOutsideList")
        XCTAssertNotNil(found)
        if let found {
            XCTAssertEqual(store.researcherIntegrityFix(for: found), .degreeOutsideList(entries: [
                .init(id: "e1", text: "Master i påhittat ämne"),
                .init(id: "e2", text: "Påhittad examen"),
            ]))
        }

        // A degree with a subject: the rest of the text becomes the subject.
        XCTAssertTrue(store.chooseResearcherDegreeForOutsideText(authorID: "f6", entryID: "e1", optionID: D.master))
        let first = store.publicationAuthor(id: "f6")?.degreeEntries.first { $0.id == "e1" }
        XCTAssertEqual(first?.optionID, D.master)
        XCTAssertEqual(first?.subjectSv, "påhittat ämne")
        XCTAssertEqual(first?.otherText, "")

        // A degree without a subject that does not explain the text: the text stays on the row.
        XCTAssertTrue(store.chooseResearcherDegreeForOutsideText(authorID: "f6", entryID: "e2", optionID: D.medical))
        let second = store.publicationAuthor(id: "f6")?.degreeEntries.first { $0.id == "e2" }
        XCTAssertEqual(second?.optionID, D.medical)
        XCTAssertEqual(second?.otherText, "Påhittad examen")
        XCTAssertNil(issue(store, authorID: "f6", suffix: "-degreeOutsideList"))
        XCTAssertEqual(store.publicationAuthor(id: "f6")?.degreeEntries.count, 2)
    }

    func testChoosingADegreeWithASubjectKeepsUnclearTextAsTheSubject() {
        let master = ResearcherDegreeOption.builtInOptions.first { $0.id == D.master }!
        let entry = ResearcherDegreeEntry(id: "e9", otherText: "Påhittad utbildning")
        let chosen = R.degreeEntry(entry, choosing: master)
        XCTAssertEqual(chosen.optionID, D.master)
        XCTAssertEqual(chosen.subjectSv, "Påhittad utbildning")
        XCTAssertEqual(chosen.subjectEn, "Påhittad utbildning")
        XCTAssertEqual(chosen.otherText, "")
    }

    @MainActor
    func testDegreeOutsideTheListCanBeAddedToTheList() {
        let author = PublicationAuthor(
            id: "f7", firstName: "Gus", lastName: "Exempel",
            degreeEntries: [ResearcherDegreeEntry(id: "e3", otherText: "Påhittad examen")]
        )
        let store = swedishStore([author])
        XCTAssertTrue(store.addResearcherDegreeToListFromDataQuality(authorID: "f7", entryID: "e3"))
        let added = store.researcherDegreeOptions.first { $0.nameSv == "Påhittad examen" }
        XCTAssertNotNil(added)
        let entry = store.publicationAuthor(id: "f7")?.degreeEntries.first
        XCTAssertEqual(entry?.optionID, added?.id)
        XCTAssertEqual(entry?.otherText, "")
        XCTAssertNil(issue(store, authorID: "f7", suffix: "-degreeOutsideList"))
        XCTAssertEqual(store.publicationAuthor(id: "f7")?.displayDegree(language: .swedish), "Påhittad examen")
        XCTAssertEqual(store.publicationAuthors.count, 1)
    }

    @MainActor
    func testOtherIntegrityIssuesGetNoInlineFix() {
        let store = swedishStore([PublicationAuthor(id: "f8", firstName: "Hed", lastName: "Exempel")])
        let unrelated = GrantDataStore.IntegrityIssue(
            id: "semantic-people-f8-somethingElse",
            kind: .semantic,
            destination: .people,
            recordID: "f8",
            title: "Hed Exempel",
            subtitle: "",
            details: ""
        )
        XCTAssertNil(store.researcherIntegrityFix(for: unrelated))
    }
}
