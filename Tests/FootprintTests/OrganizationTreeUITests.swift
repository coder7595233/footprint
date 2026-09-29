import XCTest
@testable import Footprint

/// F21: the store methods and helpers behind the organization tree screens:
/// adding, editing, moving and removing units (each one undoable), the
/// organization's publication address settings, the indented tree used in
/// lists and drop-downs, and the unit picker's rule that a unit is dropped
/// when the row's organization changes.
final class OrganizationTreeUITests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrganizationTreeUITests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: Test data

    /// Exempelköpings universitet with Exempelfakulteten > IEM > Avdelningen
    /// för prevention, rehabilitering och nära vård, and IKE directly under
    /// the organization.
    private static var uni: OrganizationRecord {
        OrganizationRecord(
            id: "org-uni",
            nameSv: "Exempelköpings universitet",
            nameEn: "Exempelköping University",
            city: "Exempelköping",
            country: "Sweden",
            units: [
                OrganizationUnit(id: "u-fak", nameSv: "Exempelfakulteten", nameEn: "Faculty of Example Sciences", inAddress: false),
                OrganizationUnit(id: "u-iem", parentUnitID: "u-fak", nameSv: "Institutionen för exempelmedicin och vård", abbreviation: "IEM", childrenInAddress: false),
                OrganizationUnit(id: "u-avd", parentUnitID: "u-iem", nameSv: "Avdelningen för prevention, rehabilitering och nära vård"),
                OrganizationUnit(id: "u-ike", nameSv: "Institutionen för kliniska exempelvetenskaper", abbreviation: "IKE"),
            ]
        )
    }

    private static var region: OrganizationRecord {
        OrganizationRecord(
            id: "org-ro",
            nameSv: "Region Exempelgöta",
            nameEn: "Region Exempelgöta",
            city: "Exempelköping",
            country: "Sweden",
            units: [
                OrganizationUnit(id: "u-kir", nameSv: "Kirurgiska kliniken"),
            ]
        )
    }

    @MainActor
    private func makeStore(authors: [PublicationAuthor] = []) -> GrantDataStore {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        return GrantDataStore(
            metadata: metadata,
            organizations: [Self.uni, Self.region],
            publicationAuthors: authors,
            skipInitialMigration: true
        )
    }

    @MainActor
    private func units(_ store: GrantDataStore, _ organizationID: String = "org-uni") -> [OrganizationUnit] {
        store.organizations.first { $0.id == organizationID }?.units ?? []
    }

    // MARK: Adding and editing

    @MainActor
    func testAddUnitUnderParentIsUndoable() {
        let store = makeStore()
        let before = units(store)

        let newID = store.addOrganizationUnit(organizationID: "org-uni", parentUnitID: "u-iem", nameSv: "Avdelningen för diagnostik och specialistmedicin")
        XCTAssertNotNil(newID)
        let added = units(store).first { $0.id == newID }
        XCTAssertEqual(added?.parentUnitID, "u-iem")
        XCTAssertEqual(added?.nameSv, "Avdelningen för diagnostik och specialistmedicin")
        XCTAssertEqual(units(store).count, before.count + 1)

        store.undoManager.undo()
        XCTAssertEqual(units(store), before)
    }

    @MainActor
    func testAddUnitUnderMissingParentChangesNothing() {
        let store = makeStore()
        let before = units(store)
        XCTAssertNil(store.addOrganizationUnit(organizationID: "org-uni", parentUnitID: "u-kir"), "a unit of another organization is not a parent")
        XCTAssertNil(store.addOrganizationUnit(organizationID: "org-missing"))
        XCTAssertEqual(units(store), before)
    }

    @MainActor
    func testUpdateUnitKeepsItsPlaceAndNeedsAName() {
        let store = makeStore()
        guard var iem = units(store).first(where: { $0.id == "u-iem" }) else {
            return XCTFail("IEM exists")
        }
        iem.addressNameEn = "Department of Example Medicine, and Caring Sciences"
        iem.validFrom = "2014"
        iem.parentUnitID = nil
        XCTAssertTrue(store.updateOrganizationUnit(organizationID: "org-uni", unit: iem))
        let saved = units(store).first { $0.id == "u-iem" }
        XCTAssertEqual(saved?.addressNameEn, "Department of Example Medicine, and Caring Sciences")
        XCTAssertEqual(saved?.parentUnitID, "u-fak", "the place in the tree changes only by moving")

        var nameless = iem
        nameless.nameSv = "  "
        nameless.nameEn = ""
        XCTAssertFalse(store.updateOrganizationUnit(organizationID: "org-uni", unit: nameless))
        XCTAssertEqual(units(store).first { $0.id == "u-iem" }?.nameSv, "Institutionen för exempelmedicin och vård")

        store.undoManager.undo()
        XCTAssertEqual(units(store).first { $0.id == "u-iem" }?.addressNameEn, "")
    }

    // MARK: Moving

    @MainActor
    func testUnitCannotBeMovedIntoItselfOrItsOwnUnits() {
        let store = makeStore()
        let before = units(store)

        XCTAssertFalse(store.moveOrganizationUnit(organizationID: "org-uni", unitID: "u-fak", toParentUnitID: "u-fak"))
        XCTAssertFalse(store.moveOrganizationUnit(organizationID: "org-uni", unitID: "u-fak", toParentUnitID: "u-iem"))
        XCTAssertFalse(store.moveOrganizationUnit(organizationID: "org-uni", unitID: "u-fak", toParentUnitID: "u-avd"))
        XCTAssertFalse(store.moveOrganizationUnit(organizationID: "org-uni", unitID: "u-iem", toParentUnitID: "u-kir"), "only within the same organization")
        XCTAssertEqual(units(store), before)

        let organization = store.organizations.first { $0.id == "org-uni" }
        XCTAssertEqual(organization?.moveTargets(forUnit: "u-fak").map(\.unit.id), ["u-ike"])
        XCTAssertEqual(organization?.moveTargets(forUnit: "u-avd").map(\.unit.id), ["u-fak", "u-iem", "u-ike"])
    }

    @MainActor
    func testMoveUnitIsUndoable() {
        let store = makeStore()
        let before = units(store)

        XCTAssertTrue(store.moveOrganizationUnit(organizationID: "org-uni", unitID: "u-ike", toParentUnitID: "u-fak"))
        XCTAssertEqual(units(store).first { $0.id == "u-ike" }?.parentUnitID, "u-fak")

        store.undoManager.undo()
        XCTAssertEqual(units(store), before)

        XCTAssertTrue(store.moveOrganizationUnit(organizationID: "org-uni", unitID: "u-avd", toParentUnitID: nil))
        XCTAssertNil(units(store).first { $0.id == "u-avd" }?.parentUnitID)
    }

    // MARK: Removing

    @MainActor
    func testUnitUsedByAResearcherRowCannotBeRemoved() {
        let author = PublicationAuthor(
            id: "a1",
            name: "Forskare a1",
            affiliations: [
                PublicationAffiliation(
                    id: "x1",
                    organization: "Exempelköpings universitet",
                    department: "Avdelningen för prevention, rehabilitering och nära vård",
                    organizationID: "org-uni",
                    unitID: "u-avd"
                ),
            ],
            employments: [
                PublicationAuthorEmployment(
                    id: "e1",
                    from: "2020-01-01",
                    organization: "Exempelköpings universitet",
                    organizationID: "org-uni",
                    unitID: "u-avd"
                ),
            ]
        )
        let store = makeStore(authors: [author])
        let before = units(store)

        XCTAssertEqual(store.organizationUnitUsageCount(organizationID: "org-uni", unitID: "u-avd"), 2)
        XCTAssertFalse(store.removeOrganizationUnit(organizationID: "org-uni", unitID: "u-avd"), "a used unit stays")
        XCTAssertFalse(store.removeOrganizationUnit(organizationID: "org-uni", unitID: "u-fak"), "a unit with units below it stays")
        XCTAssertEqual(units(store), before)
        XCTAssertEqual(store.publicationAuthors.first?.affiliations.first?.unitID, "u-avd")
    }

    @MainActor
    func testUnusedUnitCanBeRemovedAndUndone() {
        let store = makeStore()
        let before = units(store)

        XCTAssertEqual(store.organizationUnitUsageCount(organizationID: "org-uni", unitID: "u-ike"), 0)
        XCTAssertTrue(store.removeOrganizationUnit(organizationID: "org-uni", unitID: "u-ike"))
        XCTAssertNil(units(store).first { $0.id == "u-ike" })

        store.undoManager.undo()
        XCTAssertEqual(units(store), before)
    }

    /// A researcher with rows pointing to IEM, the division below it and
    /// (in another organization) Kirurgiska kliniken.
    private static var linkedAuthor: PublicationAuthor {
        PublicationAuthor(
            id: "a2",
            name: "Forskare a2",
            affiliations: [
                PublicationAffiliation(
                    id: "x-iem",
                    organization: "Exempelköpings universitet",
                    department: "Institutionen för exempelmedicin och vård",
                    organizationID: "org-uni",
                    unitID: "u-iem"
                ),
                PublicationAffiliation(
                    id: "x-kir",
                    organization: "Region Exempelgöta",
                    department: "Kirurgiska kliniken",
                    organizationID: "org-ro",
                    unitID: "u-kir"
                ),
            ],
            employments: [
                PublicationAuthorEmployment(
                    id: "e-avd",
                    from: "2020-01-01",
                    organization: "Exempelköpings universitet",
                    organizationID: "org-uni",
                    unitID: "u-avd"
                ),
            ],
            educationEntries: [
                PublicationAuthorEducation(
                    id: "d-iem",
                    organization: "Exempelköpings universitet",
                    organizationID: "org-uni",
                    unitID: "u-iem"
                ),
            ]
        )
    }

    @MainActor
    func testRemovingOnlyTheUnitMovesItsSubUnitsUpAndClearsItsLinks() {
        let store = makeStore(authors: [Self.linkedAuthor])
        let unitsBefore = units(store)
        let authorsBefore = store.publicationAuthors

        XCTAssertTrue(store.removeOrganizationUnit(organizationID: "org-uni", unitID: "u-iem", keepsChildren: true))
        XCTAssertNil(units(store).first { $0.id == "u-iem" })
        XCTAssertEqual(units(store).first { $0.id == "u-avd" }?.parentUnitID, "u-fak", "the division moves up one level")
        XCTAssertEqual(units(store).count, unitsBefore.count - 1)

        let author = store.publicationAuthors.first
        let iemAffiliation = author?.affiliations.first { $0.id == "x-iem" }
        XCTAssertNil(iemAffiliation?.unitID, "the row loses the removed unit")
        XCTAssertEqual(iemAffiliation?.organizationID, "org-uni", "the row keeps the organization")
        XCTAssertEqual(iemAffiliation?.departmentSv, "Institutionen för exempelmedicin och vård", "the text stays")
        XCTAssertNil(author?.educationEntries.first?.unitID)
        XCTAssertEqual(author?.employments.first?.unitID, "u-avd", "a row at the moved sub-unit keeps its unit")
        XCTAssertEqual(author?.affiliations.first { $0.id == "x-kir" }?.unitID, "u-kir")

        store.undoManager.undo()
        XCTAssertEqual(units(store), unitsBefore)
        XCTAssertEqual(store.publicationAuthors, authorsBefore)
    }

    @MainActor
    func testRemovingTheUnitWithSubUnitsRemovesThemAllAndClearsTheirLinks() {
        let store = makeStore(authors: [Self.linkedAuthor])
        let unitsBefore = units(store)
        let authorsBefore = store.publicationAuthors

        XCTAssertTrue(store.removeOrganizationUnit(organizationID: "org-uni", unitID: "u-fak", keepsChildren: false))
        XCTAssertEqual(units(store).map(\.id), ["u-ike"])

        let author = store.publicationAuthors.first
        XCTAssertNil(author?.affiliations.first { $0.id == "x-iem" }?.unitID)
        XCTAssertEqual(author?.affiliations.first { $0.id == "x-iem" }?.organizationID, "org-uni")
        XCTAssertNil(author?.employments.first?.unitID)
        XCTAssertEqual(author?.employments.first?.organizationID, "org-uni")
        XCTAssertNil(author?.educationEntries.first?.unitID)
        XCTAssertEqual(author?.affiliations.first { $0.id == "x-kir" }?.unitID, "u-kir", "another organization is left alone")
        XCTAssertEqual(store.organizations.first { $0.id == "org-ro" }?.units.map(\.id), ["u-kir"])

        store.undoManager.undo()
        XCTAssertEqual(units(store), unitsBefore)
        XCTAssertEqual(store.publicationAuthors, authorsBefore)
    }

    @MainActor
    func testRemovingATopLevelUnitMovesItsSubUnitsDirectlyUnderTheOrganization() {
        let store = makeStore()
        XCTAssertTrue(store.removeOrganizationUnit(organizationID: "org-uni", unitID: "u-fak", keepsChildren: true))
        XCTAssertNil(units(store).first { $0.id == "u-iem" }?.parentUnitID)
        XCTAssertEqual(units(store).first { $0.id == "u-avd" }?.parentUnitID, "u-iem", "only one level moves")
        XCTAssertFalse(store.removeOrganizationUnit(organizationID: "org-uni", unitID: "u-missing", keepsChildren: true))
    }

    // MARK: Unit editor: one English name

    func testEditingTheEnglishNameSetsBothEnglishNames() {
        var unit = OrganizationUnit(nameSv: "Kirurgiska kliniken", nameEn: "Department of Surgery")
        XCTAssertEqual(unit.editableEnglishName, "Department of Surgery")

        unit.setEditableEnglishName("Department of Surgery")
        XCTAssertEqual(unit.addressNameEn, "", "the text shown is not saved again")

        unit.setEditableEnglishName(" Department of Surgery, Exempelköping ")
        XCTAssertEqual(unit.nameEn, "Department of Surgery, Exempelköping")
        XCTAssertEqual(unit.addressNameEn, "Department of Surgery, Exempelköping")

        let withAddressName = OrganizationUnit(
            nameSv: "Institutionen för exempelmedicin och vård",
            nameEn: "Department of Example Medicine and Caring Sciences",
            addressNameEn: "Department of Example Medicine, and Caring Sciences"
        )
        XCTAssertEqual(withAddressName.editableEnglishName, "Department of Example Medicine, and Caring Sciences")
    }

    // MARK: Unit list: collapsed tree and search

    func testUnitListStartsCollapsedAndOpensUnitByUnit() {
        let organization = Self.uni
        XCTAssertEqual(organization.unitIDsWithChildren(), ["u-fak", "u-iem"])
        XCTAssertEqual(organization.visibleUnitTreeRows(expandedUnitIDs: []).map(\.unit.id), ["u-fak", "u-ike"])
        XCTAssertEqual(organization.visibleUnitTreeRows(expandedUnitIDs: ["u-fak"]).map(\.unit.id), ["u-fak", "u-iem", "u-ike"])
        XCTAssertEqual(
            organization.visibleUnitTreeRows(expandedUnitIDs: ["u-fak", "u-iem"]).map(\.depth),
            [0, 1, 2, 0]
        )
        XCTAssertEqual(organization.descendantUnitIDs(of: "u-fak"), ["u-iem", "u-avd"])
        XCTAssertEqual(organization.descendantUnitIDs(of: "u-ike"), [])
    }

    func testUnitSearchShowsMatchesWithTheUnitsAboveThem() {
        let organization = Self.uni
        let matches = organization.unitIDsMatching(searchText: "prevention")
        XCTAssertEqual(matches, ["u-avd"])
        let above = organization.ancestorUnitIDs(of: matches)
        XCTAssertEqual(above, ["u-fak", "u-iem"])
        XCTAssertEqual(
            organization.visibleUnitTreeRows(expandedUnitIDs: above, searchText: "prevention").map(\.unit.id),
            ["u-fak", "u-iem", "u-avd"]
        )
        XCTAssertEqual(organization.unitIDsMatching(searchText: "ike"), ["u-ike"], "the abbreviation is searched too")
        XCTAssertEqual(organization.visibleUnitTreeRows(expandedUnitIDs: [], searchText: "ingen sådan enhet").count, 0)
    }

    // MARK: Publication address settings

    @MainActor
    func testAddressSettingsAreSavedAndUndoable() {
        let store = makeStore()
        XCTAssertTrue(store.updateOrganizationAddressSettings(organizationID: "org-uni", addressNameEn: " Exempelköping University ", addressOrder: 1))
        let saved = store.organizations.first { $0.id == "org-uni" }
        XCTAssertEqual(saved?.addressNameEn, "Exempelköping University")
        XCTAssertEqual(saved?.addressOrder, 1)
        XCTAssertEqual(saved?.units, Self.uni.units, "the units are left alone")

        store.undoManager.undo()
        XCTAssertNil(store.organizations.first { $0.id == "org-uni" }?.addressOrder)
        XCTAssertEqual(store.organizations.first { $0.id == "org-uni" }?.addressNameEn, "")
    }

    // MARK: Tree order

    func testTreeRowsAreIndentedUnderTheirParents() {
        let rows = Self.uni.unitTreeRows()
        XCTAssertEqual(rows.map(\.unit.id), ["u-fak", "u-iem", "u-avd", "u-ike"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 0])
    }

    func testTreeRowsSurviveMissingParentsAndLoops() {
        let organization = OrganizationRecord(
            id: "org-x",
            nameSv: "X",
            nameEn: "X",
            units: [
                OrganizationUnit(id: "orphan", parentUnitID: "gone", nameSv: "Utan överenhet"),
                OrganizationUnit(id: "loop-a", parentUnitID: "loop-b", nameSv: "A"),
                OrganizationUnit(id: "loop-b", parentUnitID: "loop-a", nameSv: "B"),
            ]
        )
        let rows = organization.unitTreeRows()
        XCTAssertEqual(Set(rows.map(\.unit.id)), ["orphan", "loop-a", "loop-b"], "every unit is shown once")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.first { $0.unit.id == "orphan" }?.depth, 0)
    }

    func testPickerLeavesOutTemplatesAndEndedUnitsButKeepsTheChosenOne() {
        let organization = OrganizationRecord(
            id: "org-y",
            nameSv: "Y",
            nameEn: "Y",
            units: [
                OrganizationUnit(id: "current", nameSv: "Gäller"),
                OrganizationUnit(id: "ended", nameSv: "Upphörd", validTo: "2019"),
                OrganizationUnit(id: "template", nameSv: "Vårdcentraler", isTemplate: true),
            ]
        )
        let today = "2026-09-28"
        XCTAssertEqual(
            organization.pickerUnitRows(onDay: today, includeEnded: false, selectedUnitID: nil).map(\.unit.id),
            ["current"]
        )
        XCTAssertEqual(
            organization.pickerUnitRows(onDay: today, includeEnded: true, selectedUnitID: nil).map(\.unit.id),
            ["current", "ended"]
        )
        XCTAssertEqual(
            organization.pickerUnitRows(onDay: today, includeEnded: false, selectedUnitID: "ended").map(\.unit.id),
            ["current", "ended"]
        )
    }

    // MARK: Unit picker: organization changes

    func testChangingTheOrganizationDropsAUnitOfTheOldOrganization() {
        let organizations = [Self.uni, Self.region]
        let linked = OrganizationTree.relinkedIDs(
            organizationID: "org-uni",
            unitID: "u-iem",
            previousOrganizationText: "Exempelköpings universitet",
            newOrganizationText: "Region Exempelgöta",
            organizations: organizations
        )
        XCTAssertEqual(linked.organizationID, "org-ro")
        XCTAssertNil(linked.unitID)
    }

    func testSameOrganizationTextKeepsTheLink() {
        let organizations = [Self.uni, Self.region]
        let unchanged = OrganizationTree.relinkedIDs(
            organizationID: "org-uni",
            unitID: "u-iem",
            previousOrganizationText: "Exempelköpings universitet",
            newOrganizationText: "exempelköpings  universitet",
            organizations: organizations
        )
        XCTAssertEqual(unchanged.organizationID, "org-uni")
        XCTAssertEqual(unchanged.unitID, "u-iem")

        let english = OrganizationTree.relinkedIDs(
            organizationID: nil,
            unitID: nil,
            previousOrganizationText: "",
            newOrganizationText: "Exempelköping University",
            organizations: organizations
        )
        XCTAssertEqual(english.organizationID, "org-uni")
        XCTAssertNil(english.unitID)
    }

    func testTextThatNamesNoOrganizationClearsTheLink() {
        let organizations = [Self.uni, Self.region]
        let cleared = OrganizationTree.relinkedIDs(
            organizationID: "org-uni",
            unitID: "u-iem",
            previousOrganizationText: "Exempelköpings universitet",
            newOrganizationText: "Okänd högskola",
            organizations: organizations
        )
        XCTAssertNil(cleared.organizationID)
        XCTAssertNil(cleared.unitID)

        let empty = OrganizationTree.relinkedIDs(
            organizationID: "org-uni",
            unitID: "u-iem",
            previousOrganizationText: "Exempelköpings universitet",
            newOrganizationText: "",
            organizations: organizations
        )
        XCTAssertNil(empty.organizationID)
        XCTAssertNil(empty.unitID)
    }
}
