import XCTest
@testable import Footprint

/// Sjuksköterskespecialiteter för Specialistsjuksköterska: listan, visningen,
/// flytten från gammal text och snabbrättningen i Datakvalitet. Alla namn och
/// värden här är påhittade.
final class ResearcherNurseSpecialtyTests: XCTestCase {
    private typealias P = ResearcherPositionOption.BuiltInID
    private typealias S = ResearcherSpecialtyOption.BuiltInID
    private typealias R = ResearcherLegacyFieldMapping

    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResearcherNurseSpecialtyTests-\(UUID().uuidString)", isDirectory: true)
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
    private func swedishStore(_ authors: [PublicationAuthor], metadata base: DataSourceMetadata = .bundledDefault) -> GrantDataStore {
        var metadata = base
        metadata.interfaceLanguage = "sv"
        return GrantDataStore(metadata: metadata, publicationAuthors: authors, skipInitialMigration: true)
    }

    // MARK: - Listan

    func testStoredSpecialtyWithoutKindDecodesAsPhysician() throws {
        let json = #"""
        [{"id":"custom-old","nameSv":"Påhittad specialitet","nameEn":"Invented Specialty","isHidden":false,"sortOrder":0},
         {"id":"custom-odd","nameSv":"Annan påhittad","nameEn":"Other Invented","kind":"tandläkare","sortOrder":1}]
        """#
        let decoded = try JSONDecoder().decode([ResearcherSpecialtyOption].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.map(\.kind), [.physician, .physician])

        let nurse = ResearcherSpecialtyOption(id: "custom-nurse", nameSv: "Påhittad vård", nameEn: "Invented Care", kind: .nurse)
        let roundTrip = try JSONDecoder().decode(ResearcherSpecialtyOption.self, from: JSONEncoder().encode(nurse))
        XCTAssertEqual(roundTrip, nurse)
        XCTAssertEqual(roundTrip.kind, .nurse)
    }

    func testBuiltInNurseSpecialties() {
        let nurses = ResearcherSpecialtyOption.options(specialties, ofKind: .nurse)
        XCTAssertEqual(nurses.count, 14)
        XCTAssertEqual(nurses.first?.id, S.nurseEmergencyCare)
        XCTAssertTrue(nurses.contains { $0.id == S.nurseDistrictNursing && $0.nameSv == "Distriktssköterska" })
        XCTAssertEqual(ResearcherSpecialtyOption.options(specialties, ofKind: .physician).count, 37)
        XCTAssertTrue(ResearcherSpecialtyOption.builtInPhysicianOptions.allSatisfy { $0.kind == .physician })
    }

    func testStoredListWithoutNurseSpecialtiesGetsThemAppended() {
        var stored = ResearcherSpecialtyOption.builtInPhysicianOptions.filter { $0.id != S.urology }
        stored.append(ResearcherSpecialtyOption(id: "custom-physician", nameSv: "Påhittad specialitet", nameEn: "Invented Specialty", sortOrder: 99))
        let resolved = ResearcherSpecialtyOption.resolvedOptions(stored)
        XCTAssertEqual(resolved.count, stored.count + 14)
        XCTAssertFalse(resolved.contains { $0.id == S.urology }, "a removed physician specialty stays removed")
        XCTAssertEqual(resolved.last?.id, S.nurseDiabetesCare)
        XCTAssertEqual(
            ResearcherSpecialtyOption.options(resolved, ofKind: .nurse).map(\.id),
            ResearcherSpecialtyOption.builtInNurseOptions.map(\.id)
        )
        XCTAssertEqual(resolved.map(\.sortOrder), Array(0..<resolved.count))

        // A stored list that already has nurse specialties is used as it is.
        var withNurse = stored
        withNurse.append(ResearcherSpecialtyOption(id: "custom-nurse", nameSv: "Påhittad vård", nameEn: "Invented Care", kind: .nurse, sortOrder: 100))
        let resolvedWithNurse = ResearcherSpecialtyOption.resolvedOptions(withNurse)
        XCTAssertEqual(resolvedWithNurse.count, withNurse.count)
        XCTAssertEqual(ResearcherSpecialtyOption.options(resolvedWithNurse, ofKind: .nurse).map(\.id), ["custom-nurse"])
    }

    @MainActor
    func testAppendedNurseSpecialtiesAreNotWrittenUntilTheListChanges() {
        let stored = ResearcherSpecialtyOption.builtInPhysicianOptions
        var metadata = DataSourceMetadata.bundledDefault
        metadata.researcherSpecialtyOptions = stored
        let store = swedishStore([], metadata: metadata)
        XCTAssertEqual(ResearcherSpecialtyOption.options(store.researcherSpecialtyOptions, ofKind: .nurse).count, 14)

        store.autosaveResearcherSpecialtyOptions(store.researcherSpecialtyOptions)
        XCTAssertEqual(store.metadata.researcherSpecialtyOptions, stored, "nothing is written without a change")

        var edited = store.researcherSpecialtyOptions
        if let index = edited.firstIndex(where: { $0.id == S.nurseIntensiveCare }) {
            edited[index].isHidden = true
        }
        store.autosaveResearcherSpecialtyOptions(edited)
        let saved = store.metadata.researcherSpecialtyOptions ?? []
        XCTAssertEqual(ResearcherSpecialtyOption.options(saved, ofKind: .nurse).count, 14)
        XCTAssertEqual(saved.first { $0.id == S.nurseIntensiveCare }?.isHidden, true)
    }

    // MARK: - Visning och val

    func testNurseSpecialtyDisplay() {
        var author = PublicationAuthor(id: "n1", firstName: "Alva", lastName: "Exempel")
        author.positionIDs = [P.specialistNurse]
        author.positionSpecialtyIDs = [P.specialistNurse: S.nurseIntensiveCare]
        XCTAssertEqual(author.displayPosition(language: .swedish, options: positions, specialtyOptions: specialties), "Specialistsjuksköterska inom intensivvård")
        XCTAssertEqual(author.displayPosition(language: .english, options: positions, specialtyOptions: specialties), "Specialist Nurse, Intensive Care")

        author.positionSpecialtyIDs = [P.specialistNurse: S.nurseDistrictNursing]
        XCTAssertEqual(author.displayPosition(language: .swedish, options: positions, specialtyOptions: specialties), "Distriktssköterska")
        XCTAssertEqual(author.displayPosition(language: .english, options: positions, specialtyOptions: specialties), "District Nurse")

        author.positionSpecialtyIDs = [P.specialistNurse: S.nurseChildHealth]
        XCTAssertEqual(
            author.displayPosition(language: .swedish, options: positions, specialtyOptions: specialties),
            "Specialistsjuksköterska inom hälso- och sjukvård för barn och ungdomar"
        )

        // Without a specialty only the position's name is shown.
        author.positionSpecialtyIDs = [:]
        XCTAssertEqual(author.displayPosition(language: .swedish, options: positions, specialtyOptions: specialties), "Specialistsjuksköterska")

        // Physicians keep "i".
        author.positionIDs = [P.specialistPhysician]
        author.positionSpecialtyIDs = [P.specialistPhysician: S.emergencyMedicine]
        XCTAssertEqual(author.displayPosition(language: .swedish, options: positions, specialtyOptions: specialties), "Specialistläkare i akutsjukvård")

        // A registered nurse cannot have a specialty.
        author.positionIDs = [P.registeredNurse]
        author.positionSpecialtyIDs = [P.registeredNurse: S.nurseIntensiveCare]
        XCTAssertEqual(author.displayPosition(language: .swedish, options: positions, specialtyOptions: specialties), "Sjuksköterska")
    }

    func testEachPositionOffersOnlyItsOwnKindOfSpecialty() {
        let specialistNurse = positions.first { $0.id == P.specialistNurse }
        XCTAssertEqual(specialistNurse?.specialtyKind, .nurse)
        XCTAssertEqual(positions.first { $0.id == P.seniorConsultant }?.specialtyKind, .physician)
        XCTAssertNil(positions.first { $0.id == P.registeredNurse }?.specialtyKind)
        XCTAssertNil(positions.first { $0.id == P.researchNurse }?.specialtyKind)

        let nurseChoices = ResearcherPositionPickerField.specialtyChoices(specialties, kind: .nurse, selectedID: nil)
        XCTAssertEqual(nurseChoices.map(\.id), ResearcherSpecialtyOption.builtInNurseOptions.map(\.id))
        let physicianChoices = ResearcherPositionPickerField.specialtyChoices(specialties, kind: .physician, selectedID: nil)
        XCTAssertEqual(physicianChoices.count, 37)
        XCTAssertTrue(physicianChoices.allSatisfy { $0.kind == .physician })

        // A hidden specialty is offered only when it is already chosen.
        var list = specialties
        if let index = list.firstIndex(where: { $0.id == S.nurseDiabetesCare }) {
            list[index].isHidden = true
        }
        XCTAssertFalse(ResearcherPositionPickerField.specialtyChoices(list, kind: .nurse, selectedID: nil).contains { $0.id == S.nurseDiabetesCare })
        XCTAssertTrue(ResearcherPositionPickerField.specialtyChoices(list, kind: .nurse, selectedID: S.nurseDiabetesCare).contains { $0.id == S.nurseDiabetesCare })
    }

    // MARK: - Flytten från gammal text

    func testPositionTextGivesNurseSpecialties() {
        let intensive = R.mapPositionText("Specialistsjuksköterska inom intensivvård")
        XCTAssertEqual(intensive.positionIDs, [P.specialistNurse])
        XCTAssertEqual(intensive.specialtyIDs, [P.specialistNurse: S.nurseIntensiveCare])
        XCTAssertEqual(intensive.unmappedParts, [])

        let children = R.mapPositionText("Specialistsjuksköterska inom hälso- och sjukvård för barn och ungdomar")
        XCTAssertEqual(children.specialtyIDs, [P.specialistNurse: S.nurseChildHealth])
        XCTAssertEqual(children.unmappedParts, [])

        let words: [(String, String)] = [
            ("Distriktssköterska", S.nurseDistrictNursing),
            ("Intensivvårdssjuksköterska", S.nurseIntensiveCare),
            ("Anestesisjuksköterska", S.nurseAnaesthesiaCare),
            ("Operationssjuksköterska", S.nurseOperatingRoomCare),
            ("Diabetessjuksköterska", S.nurseDiabetesCare),
            ("Barnsjuksköterska", S.nursePaediatricCare),
            ("Psykiatrisjuksköterska", S.nursePsychiatricCare),
            ("District Nurse", S.nurseDistrictNursing),
        ]
        for (text, specialtyID) in words {
            let result = R.mapPositionText(text)
            XCTAssertEqual(result.positionIDs, [P.specialistNurse], text)
            XCTAssertEqual(result.specialtyIDs, [P.specialistNurse: specialtyID], text)
            XCTAssertEqual(result.unmappedParts, [], text)
        }

        // The same word for physicians and nurses goes to the right list.
        XCTAssertEqual(R.mapPositionText("Specialistsjuksköterska inom akutsjukvård").specialtyIDs, [P.specialistNurse: S.nurseEmergencyCare])
        XCTAssertEqual(R.mapPositionText("Specialistläkare i akutsjukvård").specialtyIDs, [P.specialistPhysician: S.emergencyMedicine])
        XCTAssertEqual(R.mapPositionText("Specialist Nurse, Intensive Care").specialtyIDs, [P.specialistNurse: S.nurseIntensiveCare])

        // A plain nurse with a specialty name stays a registered nurse.
        let plain = R.mapPositionText("Sjuksköterska")
        XCTAssertEqual(plain.positionIDs, [P.registeredNurse])
        XCTAssertEqual(plain.specialtyIDs, [:])
    }

    func testFreshMigrationGivesSpecialistNurseWithoutTouchingTheOldText() {
        let author = PublicationAuthor(
            id: "n2",
            firstName: "Bo",
            lastName: "Exempel",
            positionSv: "Distriktssköterska",
            positionEn: "District Nurse",
            hasPhD: true,
            careerStage: .categoryC
        )
        let migrated = R.migrated(author)
        XCTAssertEqual(migrated.positionIDs, [P.specialistNurse])
        XCTAssertEqual(migrated.positionSpecialtyIDs, [P.specialistNurse: S.nurseDistrictNursing])
        XCTAssertEqual(migrated.positionOtherSv, "")
        XCTAssertEqual(migrated.positionOtherEn, "")
        XCTAssertEqual(migrated.positionSv, "Distriktssköterska")
        XCTAssertEqual(migrated.positionEn, "District Nurse")
        XCTAssertEqual(migrated.careerStage, .categoryC)
        XCTAssertTrue(migrated.hasPhD)
        XCTAssertEqual(R.migrated(migrated), migrated)
    }

    func testNurseSpecialtyStepForResearchersAlreadyMigrated() {
        // Specialist nurse chosen, specialty only in the old text.
        let fromOldText = PublicationAuthor(
            id: "n3",
            firstName: "Cia",
            lastName: "Exempel",
            positionSv: "Specialistsjuksköterska inom intensivvård",
            hasPhD: false,
            careerStage: nil,
            positionIDs: [P.specialistNurse]
        )
        let first = R.migratedNurseSpecialties(fromOldText)
        XCTAssertEqual(first.positionSpecialtyIDs, [P.specialistNurse: S.nurseIntensiveCare])
        XCTAssertEqual(first.positionSv, fromOldText.positionSv)
        XCTAssertEqual(first.careerStage, fromOldText.careerStage, "career stage is never changed")
        XCTAssertFalse(first.hasPhD)
        XCTAssertEqual(R.migratedNurseSpecialties(first), first, "running again changes nothing")

        // "Distriktssköterska" was left as other text: it becomes Specialistsjuksköterska.
        let fromOther = PublicationAuthor(
            id: "n4",
            firstName: "Dag",
            lastName: "Exempel",
            positionSv: "Sjuksköterska, Distriktssköterska, Påhittad roll",
            hasPhD: true,
            careerStage: .categoryB,
            positionIDs: [P.registeredNurse],
            positionOtherSv: "Distriktssköterska, Påhittad roll"
        )
        XCTAssertEqual(R.migratedSpecialties(fromOther), fromOther, "the physician step leaves nurses alone")
        let second = R.migratedNurseSpecialties(fromOther)
        XCTAssertEqual(second.positionIDs, [P.registeredNurse, P.specialistNurse])
        XCTAssertEqual(second.positionSpecialtyIDs, [P.specialistNurse: S.nurseDistrictNursing])
        XCTAssertEqual(second.positionOtherSv, "Påhittad roll")
        XCTAssertEqual(second.positionSv, fromOther.positionSv)
        XCTAssertEqual(second.careerStage, .categoryB)
        XCTAssertTrue(second.hasPhD)
        XCTAssertEqual(R.migratedNurseSpecialties(second), second, "running again changes nothing")

        // A specialty name alone in "other" goes to the one specialist nurse without one.
        let looseName = PublicationAuthor(
            id: "n5",
            firstName: "Eva",
            lastName: "Exempel",
            positionIDs: [P.specialistNurse],
            positionOtherSv: "Operationssjukvård"
        )
        let third = R.migratedNurseSpecialties(looseName)
        XCTAssertEqual(third.positionSpecialtyIDs, [P.specialistNurse: S.nurseOperatingRoomCare])
        XCTAssertEqual(third.positionOtherSv, "")

        // A chosen specialty is never replaced, and physicians are left alone.
        let chosen = PublicationAuthor(
            id: "n6",
            firstName: "Fia",
            lastName: "Exempel",
            positionSv: "Specialistsjuksköterska inom intensivvård",
            positionIDs: [P.specialistNurse],
            positionSpecialtyIDs: [P.specialistNurse: S.nurseOncologyCare]
        )
        XCTAssertEqual(R.migratedNurseSpecialties(chosen), chosen)
        let physician = PublicationAuthor(
            id: "n7",
            firstName: "Gun",
            lastName: "Exempel",
            positionIDs: [P.seniorConsultant],
            positionOtherSv: "geriatriker"
        )
        XCTAssertEqual(R.migratedNurseSpecialties(physician), physician)
    }

    @MainActor
    func testStoreNurseSpecialtyStepRunsOnceAndKeepsEveryResearcher() {
        let authors = [
            PublicationAuthor(id: "s1", firstName: "Hugo", lastName: "Exempel", positionSv: "Specialistsjuksköterska inom diabetesvård", hasPhD: true, careerStage: .categoryB, positionIDs: [P.specialistNurse]),
            PublicationAuthor(id: "s2", firstName: "Ines", lastName: "Exempel", positionSv: "Överläkare i kardiologi", positionIDs: [P.seniorConsultant]),
            PublicationAuthor(id: "s3", firstName: "Jon", lastName: "Exempel"),
        ]
        let store = swedishStore(authors)
        XCTAssertTrue(store.runResearcherNurseSpecialtyMigration())
        XCTAssertEqual(store.publicationAuthors.count, 3)
        XCTAssertEqual(store.publicationAuthor(id: "s1")?.positionSpecialtyIDs, [P.specialistNurse: S.nurseDiabetesCare])
        XCTAssertEqual(store.publicationAuthor(id: "s1")?.careerStage, .categoryB)
        XCTAssertEqual(store.publicationAuthor(id: "s2")?.positionSpecialtyIDs, [:], "physicians belong to the physician step")
        XCTAssertTrue(store.metadata.migrationLog?.contains { $0.key == "round20c-nurse-specialties" } ?? false)
        XCTAssertFalse(store.runResearcherNurseSpecialtyMigration(), "runs only once")
        XCTAssertFalse(store.migrateResearcherNurseSpecialties(), "running again changes nothing")
        XCTAssertEqual(store.researcherSpecialtyOptionUsageCounts()[S.nurseDiabetesCare], 1)
    }

    // MARK: - Datakvalitet

    @MainActor
    func testChoosingSpecialistNursePicksUpTheSpecialtyInTheText() {
        let author = PublicationAuthor(
            id: "q1", firstName: "Kim", lastName: "Exempel",
            positionIDs: [P.registeredNurse],
            positionOtherSv: "Påhittad roll, Specialistsjuksköterska inom påhittad del av diabetesvård"
        )
        let store = swedishStore([author])
        XCTAssertTrue(store.chooseResearcherPositionForOutsideText(
            authorID: "q1",
            part: "Specialistsjuksköterska inom påhittad del av diabetesvård",
            optionID: P.specialistNurse
        ))
        let updated = store.publicationAuthor(id: "q1")
        XCTAssertEqual(updated?.positionIDs, [P.registeredNurse, P.specialistNurse])
        XCTAssertEqual(updated?.positionSpecialtyIDs, [P.specialistNurse: S.nurseDiabetesCare])
        XCTAssertEqual(updated?.positionOtherSv, "Påhittad roll")

        let district = PublicationAuthor(id: "q2", firstName: "Lis", lastName: "Exempel", positionOtherSv: "Distriktssköterska")
        let districtStore = swedishStore([district])
        XCTAssertTrue(districtStore.chooseResearcherPositionForOutsideText(authorID: "q2", part: "Distriktssköterska", optionID: P.specialistNurse))
        XCTAssertEqual(districtStore.publicationAuthor(id: "q2")?.positionSpecialtyIDs, [P.specialistNurse: S.nurseDistrictNursing])
        XCTAssertEqual(districtStore.publicationAuthor(id: "q2")?.positionOtherSv, "")

        // A physician position does not pick up a nurse specialty.
        let mixed = PublicationAuthor(id: "q3", firstName: "Max", lastName: "Exempel", positionOtherSv: "Överläkare, intensivvårdssjuksköterska")
        let mixedStore = swedishStore([mixed])
        XCTAssertTrue(mixedStore.chooseResearcherPositionForOutsideText(authorID: "q3", part: "intensivvårdssjuksköterska", optionID: P.seniorConsultant))
        XCTAssertEqual(mixedStore.publicationAuthor(id: "q3")?.positionSpecialtyIDs, [:])
    }
}
