import Foundation

// F21: helpers for the organization tree screens (the unit editor on the
// organization page and the unit picker on researcher rows). Everything
// here reads data only; writes go through the store methods in
// DataStore.swift (addOrganizationUnit, updateOrganizationUnit,
// moveOrganizationUnit, removeOrganizationUnit, updateOrganizationAddressSettings).

/// One unit in an organization's tree as shown in a list: the unit and how
/// many levels below the organization it sits (0 = directly under it).
struct OrganizationUnitTreeRow: Hashable, Identifiable {
    var unit: OrganizationUnit
    var depth: Int

    var id: String { unit.id }
}

extension OrganizationRecord {
    /// The units in tree order: every unit is followed by the units below
    /// it, siblings in stored order. A unit whose parent is missing is shown
    /// at the top level, and so is a unit caught in a loop of parents, so
    /// every unit can be reached and moved. When `isIncluded` says no for a
    /// unit, that unit and the units below it are left out.
    func unitTreeRows(where isIncluded: (OrganizationUnit) -> Bool = { _ in true }) -> [OrganizationUnitTreeRow] {
        let knownIDs = Set(units.map(\.id))
        var childrenByParentID: [String: [OrganizationUnit]] = [:]
        var roots: [OrganizationUnit] = []
        for unit in units {
            if let parentID = unit.parentUnitID, parentID != unit.id, knownIDs.contains(parentID) {
                childrenByParentID[parentID, default: []].append(unit)
            } else {
                roots.append(unit)
            }
        }

        // Units that cannot be reached from a top-level unit sit in a loop
        // of parents; the first one found is shown at the top level.
        var reachable = Set<String>()
        var pending = roots
        while let unit = pending.popLast() {
            guard reachable.insert(unit.id).inserted else { continue }
            pending.append(contentsOf: childrenByParentID[unit.id] ?? [])
        }
        for unit in units where !reachable.contains(unit.id) {
            roots.append(unit)
            var loopPending = [unit]
            while let next = loopPending.popLast() {
                guard reachable.insert(next.id).inserted else { continue }
                loopPending.append(contentsOf: childrenByParentID[next.id] ?? [])
            }
        }

        var rows: [OrganizationUnitTreeRow] = []
        var visited = Set<String>()
        var stack: [(unit: OrganizationUnit, depth: Int)] = roots.reversed().map { (unit: $0, depth: 0) }
        while let entry = stack.popLast() {
            guard visited.insert(entry.unit.id).inserted else { continue }
            guard isIncluded(entry.unit) else { continue }
            rows.append(OrganizationUnitTreeRow(unit: entry.unit, depth: entry.depth))
            let children = childrenByParentID[entry.unit.id] ?? []
            for child in children.reversed() {
                stack.append((unit: child, depth: entry.depth + 1))
            }
        }
        return rows
    }

    /// True when `candidateID` is `rootID` itself or one of the units below
    /// it. Safe against loops of parents.
    func unitIsInSubtree(_ candidateID: String?, of rootID: String) -> Bool {
        var visited = Set<String>()
        var current = candidateID?.trimmedOrNil
        while let currentID = current, visited.insert(currentID).inserted {
            if currentID == rootID {
                return true
            }
            current = unit(withID: currentID)?.parentUnitID
        }
        return false
    }

    /// The units a unit may be moved under: every unit in the organization
    /// except the unit itself and the units below it.
    func moveTargets(forUnit unitID: String) -> [OrganizationUnitTreeRow] {
        unitTreeRows { !unitIsInSubtree($0.id, of: unitID) }
    }

    /// The ids of every unit below `unitID` (all levels), not the unit
    /// itself. Safe against loops of parents.
    func descendantUnitIDs(of unitID: String) -> Set<String> {
        Set(units.filter { $0.id != unitID && unitIsInSubtree($0.id, of: unitID) }.map(\.id))
    }

    /// The ids of the units that have at least one unit below them in the
    /// tree as shown (`unitTreeRows()`).
    func unitIDsWithChildren() -> Set<String> {
        let rows = unitTreeRows()
        var ids = Set<String>()
        for index in rows.indices.dropLast() where rows[index + 1].depth > rows[index].depth {
            ids.insert(rows[index].unit.id)
        }
        return ids
    }

    /// The units whose Swedish, English or address name (or abbreviation)
    /// contains `searchText`, ignoring case, accents and punctuation.
    /// Empty when the search text is empty.
    func unitIDsMatching(searchText: String) -> Set<String> {
        let key = OrganizationTree.matchKey(searchText)
        guard !key.isEmpty else { return [] }
        var ids = Set<String>()
        for unit in units {
            let names = [unit.nameSv, unit.nameEn, unit.addressNameEn, unit.abbreviation]
            if names.contains(where: { OrganizationTree.matchKey($0).contains(key) }) {
                ids.insert(unit.id)
            }
        }
        return ids
    }

    /// The units above the given units (not the units themselves, unless
    /// one of them sits above another).
    func ancestorUnitIDs(of unitIDs: Set<String>) -> Set<String> {
        var ids = Set<String>()
        for unitID in unitIDs {
            for unit in unitPath(to: unitID).dropLast() {
                ids.insert(unit.id)
            }
        }
        return ids
    }

    /// The rows shown in the collapsible unit list on the organization page.
    /// A unit with units below it shows them only when its id is in
    /// `expandedUnitIDs`. With a search text only the matching units and the
    /// units above them are shown.
    func visibleUnitTreeRows(expandedUnitIDs: Set<String>, searchText: String = "") -> [OrganizationUnitTreeRow] {
        var rows = unitTreeRows()
        let matches = unitIDsMatching(searchText: searchText)
        if OrganizationTree.matchKey(searchText).isEmpty == false {
            let included = matches.union(ancestorUnitIDs(of: matches))
            rows = rows.filter { included.contains($0.unit.id) }
        }
        let parentIDs = unitIDsWithChildren()
        var visible: [OrganizationUnitTreeRow] = []
        var hiddenBelowDepth: Int? = nil
        for row in rows {
            if let hiddenBelowDepth, row.depth > hiddenBelowDepth {
                continue
            }
            hiddenBelowDepth = nil
            visible.append(row)
            if parentIDs.contains(row.unit.id), !expandedUnitIDs.contains(row.unit.id) {
                hiddenBelowDepth = row.depth
            }
        }
        return visible
    }

    /// The units offered in the unit picker on a researcher row: units that
    /// exist on `day` (all units when `includeEnded` is true), never
    /// template units. The selected unit and the units above it
    /// are always kept so the current choice stays visible.
    func pickerUnitRows(onDay day: String, includeEnded: Bool, selectedUnitID: String?) -> [OrganizationUnitTreeRow] {
        unitTreeRows { unit in
            if let selectedUnitID, unitIsInSubtree(selectedUnitID, of: unit.id) {
                return true
            }
            guard !unit.isTemplate else { return false }
            return includeEnded || unit.isValid(onDay: day)
        }
    }
}

extension OrganizationUnit {
    /// F21: the one English name shown in the unit editor: the name used in
    /// publication addresses when there is one, else the English name.
    var editableEnglishName: String {
        addressNameEn.nonEmpty ?? nameEn
    }

    /// F21: saves the unit editor's English name as both the English name
    /// and the English name in publication addresses. Nothing changes when
    /// the text is the one already shown.
    mutating func setEditableEnglishName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != editableEnglishName.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        nameEn = trimmed
        addressNameEn = trimmed
    }
}

extension OrganizationTree {
    /// The organization whose Swedish or English name is `name` (case,
    /// accents and punctuation ignored). When several match, `preferredID`
    /// wins if it is one of them.
    static func organization(
        matchingName name: String,
        in organizations: [OrganizationRecord],
        preferredID: String? = nil
    ) -> OrganizationRecord? {
        let key = matchKey(name)
        guard !key.isEmpty else { return nil }
        let matches = organizations.filter { organization in
            matchKey(organization.nameSv) == key || matchKey(organization.nameEn) == key
        }
        if let preferredID, let preferred = matches.first(where: { $0.id == preferredID }) {
            return preferred
        }
        return matches.first
    }

    /// Where a researcher row should point after its organization text was
    /// changed from `previousOrganizationText` to `newOrganizationText`:
    ///  - the same text (ignoring case, accents and punctuation): unchanged;
    ///  - the name of an organization: that organization, keeping the unit
    ///    only when it belongs to that organization;
    ///  - empty text or text that names no organization: not linked.
    static func relinkedIDs(
        organizationID: String?,
        unitID: String?,
        previousOrganizationText: String,
        newOrganizationText: String,
        organizations: [OrganizationRecord]
    ) -> (organizationID: String?, unitID: String?) {
        if matchKey(previousOrganizationText) == matchKey(newOrganizationText) {
            return (organizationID, unitID)
        }
        guard let matched = Self.organization(
            matchingName: newOrganizationText,
            in: organizations,
            preferredID: organizationID
        ) else {
            return (nil, nil)
        }
        let keptUnitID = matched.unit(withID: unitID) == nil ? nil : unitID
        return (matched.id, keptUnitID)
    }

    /// The organization a researcher row belongs to: the linked one when
    /// the row has an id, else the one its text names.
    static func rowOrganization(
        organizationID: String?,
        organizationTexts: [String],
        organizations: [OrganizationRecord]
    ) -> OrganizationRecord? {
        if let organizationID = organizationID?.trimmedOrNil,
           let linked = organizations.first(where: { $0.id == organizationID }) {
            return linked
        }
        for text in organizationTexts {
            if let matched = Self.organization(matchingName: text, in: organizations) {
                return matched
            }
        }
        return nil
    }
}

// MARK: Round 7: one correct spelling on researcher rows
//
// A row linked to an organization shows that organization's name, and a row
// linked to a unit shows that unit's name as its department. The texts are
// rewritten from the tree when the app starts, when an organization or a
// unit is renamed and when a unit is picked on a row. Rows without a link
// keep their text.

/// How many researcher rows got the official names written into them.
struct OfficialOrganizationNameReport: Equatable {
    var affiliations = 0
    var employments = 0
    var educationEntries = 0

    var total: Int { affiliations + employments + educationEntries }
    var isEmpty: Bool { total == 0 }
}

extension OrganizationRecord {
    /// The organization's official Swedish and English names for a
    /// researcher row; a missing name is filled with the other language's
    /// name. Nil when the organization has no name at all.
    var officialRowNames: (sv: String, en: String)? {
        let sv = nameSv.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = sv.nonEmpty ?? en.nonEmpty else { return nil }
        return (sv.nonEmpty ?? first, en.nonEmpty ?? first)
    }
}

extension OrganizationUnit {
    /// The unit's official Swedish and English names for a researcher row's
    /// department. English is the name used in publication addresses when
    /// there is one (the same English name as in the unit editor). A missing
    /// name is filled with the other language's name. Nil when the unit has
    /// no name at all.
    var officialRowNames: (sv: String, en: String)? {
        let sv = nameSv.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = editableEnglishName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = sv.nonEmpty ?? en.nonEmpty else { return nil }
        return (sv.nonEmpty ?? first, en.nonEmpty ?? first)
    }
}

extension OrganizationTree {
    /// True when at least one affiliation, employment or education row
    /// points to the organization.
    static func hasRows(linkedTo organizationID: String, in authors: [PublicationAuthor]) -> Bool {
        authors.contains { author in
            author.affiliations.contains { $0.organizationID == organizationID }
                || author.employments.contains { $0.organizationID == organizationID }
                || author.educationEntries.contains { $0.organizationID == organizationID }
        }
    }

    /// The organization and unit a row points to, when they exist. A unit
    /// id that is not in the linked organization counts as no unit.
    static func linkedOrganizationAndUnit(
        organizationID: String?,
        unitID: String?,
        organizationsByID: [String: OrganizationRecord]
    ) -> (organization: OrganizationRecord, unit: OrganizationUnit?)? {
        guard let organizationID = organizationID?.trimmedOrNil,
              let organization = organizationsByID[organizationID] else { return nil }
        return (organization, organization.unit(withID: unitID?.trimmedOrNil))
    }

    /// Writes the official names into every linked affiliation, employment
    /// and education row: the organization's names into the organization
    /// text, and the unit's names into the department text when the row
    /// points to a unit (education rows have no department). Rows without a
    /// link, or pointing to an organization that no longer exists, are left
    /// alone. With `onlyOrganizationIDs`, only rows linked to those
    /// organizations are touched (used when one organization or unit is
    /// renamed). No row is added or removed; running it again changes nothing.
    static func applyingOfficialNames(
        to authors: [PublicationAuthor],
        organizations: [OrganizationRecord],
        onlyOrganizationIDs: Set<String>? = nil
    ) -> (authors: [PublicationAuthor], report: OfficialOrganizationNameReport) {
        var organizationsByID: [String: OrganizationRecord] = [:]
        for organization in organizations where organizationsByID[organization.id] == nil {
            if let onlyOrganizationIDs, !onlyOrganizationIDs.contains(organization.id) {
                continue
            }
            organizationsByID[organization.id] = organization
        }
        var report = OfficialOrganizationNameReport()
        var updatedAuthors = authors
        for authorIndex in updatedAuthors.indices {
            var author = updatedAuthors[authorIndex]
            var authorChanged = false
            for rowIndex in author.affiliations.indices {
                guard let link = linkedOrganizationAndUnit(
                    organizationID: author.affiliations[rowIndex].organizationID,
                    unitID: author.affiliations[rowIndex].unitID,
                    organizationsByID: organizationsByID
                ) else { continue }
                if author.affiliations[rowIndex].applyOfficialNames(organization: link.organization, unit: link.unit) {
                    report.affiliations += 1
                    authorChanged = true
                }
            }
            for rowIndex in author.employments.indices {
                guard let link = linkedOrganizationAndUnit(
                    organizationID: author.employments[rowIndex].organizationID,
                    unitID: author.employments[rowIndex].unitID,
                    organizationsByID: organizationsByID
                ) else { continue }
                if author.employments[rowIndex].applyOfficialNames(organization: link.organization, unit: link.unit) {
                    report.employments += 1
                    authorChanged = true
                }
            }
            for rowIndex in author.educationEntries.indices {
                guard let link = linkedOrganizationAndUnit(
                    organizationID: author.educationEntries[rowIndex].organizationID,
                    unitID: author.educationEntries[rowIndex].unitID,
                    organizationsByID: organizationsByID
                ) else { continue }
                if author.educationEntries[rowIndex].applyOfficialNames(organization: link.organization) {
                    report.educationEntries += 1
                    authorChanged = true
                }
            }
            if authorChanged {
                updatedAuthors[authorIndex] = author
            }
        }
        return (updatedAuthors, report)
    }
}

extension PublicationAffiliation {
    /// Writes the organization's (and the unit's) official names into the
    /// row. Returns true when a text changed.
    @discardableResult
    mutating func applyOfficialNames(organization: OrganizationRecord, unit: OrganizationUnit?) -> Bool {
        let before = self
        if let names = organization.officialRowNames {
            organizationSv = names.sv
            organizationEn = names.en
        }
        if let names = unit?.officialRowNames {
            departmentSv = names.sv
            departmentEn = names.en
        }
        return self != before
    }
}

extension PublicationAuthorEmployment {
    /// Writes the organization's (and the unit's) official names into the
    /// row. Returns true when a text changed.
    @discardableResult
    mutating func applyOfficialNames(organization: OrganizationRecord, unit: OrganizationUnit?) -> Bool {
        let before = self
        if let names = organization.officialRowNames {
            organizationSv = names.sv
            organizationEn = names.en
        }
        if let names = unit?.officialRowNames {
            departmentSv = names.sv
            departmentEn = names.en
        }
        return self != before
    }
}

extension PublicationAuthorEducation {
    /// Writes the organization's official names into the row (education
    /// rows have no department). Returns true when a text changed.
    @discardableResult
    mutating func applyOfficialNames(organization: OrganizationRecord) -> Bool {
        let before = self
        if let names = organization.officialRowNames {
            organizationSv = names.sv
            organizationEn = names.en
        }
        return self != before
    }
}

extension GrantDataStore {
    /// F21: how many affiliation, employment and education rows point to
    /// each unit of the organization (units nobody uses are missing).
    func organizationUnitUsageCounts(organizationID: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        func tally(_ rowOrganizationID: String?, _ rowUnitID: String?) {
            guard rowOrganizationID == organizationID, let rowUnitID else { return }
            counts[rowUnitID, default: 0] += 1
        }
        for author in publicationAuthors {
            for affiliation in author.affiliations {
                tally(affiliation.organizationID, affiliation.unitID)
            }
            for employment in author.employments {
                tally(employment.organizationID, employment.unitID)
            }
            for education in author.educationEntries {
                tally(education.organizationID, education.unitID)
            }
        }
        return counts
    }

    /// F21: how many researcher rows point to the unit.
    func organizationUnitUsageCount(organizationID: String, unitID: String) -> Int {
        organizationUnitUsageCounts(organizationID: organizationID)[unitID] ?? 0
    }
}
