import Foundation

// F21: organization tree. An organization has units (faculties,
// departments, centres, clinics, …) in any number of levels. Researchers'
// affiliations, employments and education entries point into the tree by id;
// their text stays as the display fallback.
//
// Everything in this file is pure (no store access) so it can be tested and
// reused by the UI. The store API lives in `GrantDataStore`:
//   - `publicationAddressLines(for:asOf:)`

/// One unit in an organization's tree.
struct OrganizationUnit: Codable, Hashable, Identifiable {
    var id: String
    /// The unit above this one; nil = directly under the organization.
    var parentUnitID: String?
    var nameSv: String
    var nameEn: String
    var abbreviation: String
    /// English name used in a publication address ("" = use `nameEn`).
    var addressNameEn: String
    /// City for the publication address ("" = the parent's or the organization's city).
    var city: String
    /// Whether this level is printed in a publication address (faculties and
    /// centrum levels are not).
    var inAddress: Bool
    /// False = units below this one are written as this unit in a
    /// publication address (for example the divisions of a department).
    var childrenInAddress: Bool
    /// First day or year the unit exists ("" = open).
    var validFrom: String
    /// Last day or year the unit exists ("" = open).
    var validTo: String
    /// A pattern (for example "Vårdcentraler" with a "[clinic]"
    /// placeholder), not a real unit. Never matched to text.
    var isTemplate: Bool
    /// Written in a publication address instead of the organization's name,
    /// for units below it too. Some university hospitals are written this
    /// way: their researchers write "Department of Cardiology, <hospital>,
    /// <city>, Sweden", never the region.
    var standsInForOrganizationInAddress: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case parentUnitID
        case nameSv
        case nameEn
        case abbreviation
        case addressNameEn
        case city
        case inAddress
        case childrenInAddress
        case validFrom
        case validTo
        case isTemplate
        case standsInForOrganizationInAddress
    }

    init(
        id: String = UUID().uuidString,
        parentUnitID: String? = nil,
        nameSv: String,
        nameEn: String = "",
        abbreviation: String = "",
        addressNameEn: String = "",
        city: String = "",
        inAddress: Bool = true,
        childrenInAddress: Bool = true,
        validFrom: String = "",
        validTo: String = "",
        isTemplate: Bool = false,
        standsInForOrganizationInAddress: Bool = false
    ) {
        self.id = id
        self.parentUnitID = parentUnitID
        self.nameSv = nameSv
        self.nameEn = nameEn
        self.abbreviation = abbreviation
        self.addressNameEn = addressNameEn
        self.city = city
        self.inAddress = inAddress
        self.childrenInAddress = childrenInAddress
        self.validFrom = validFrom
        self.validTo = validTo
        self.isTemplate = isTemplate
        self.standsInForOrganizationInAddress = standsInForOrganizationInAddress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedNameSv = try container.decodeIfPresent(String.self, forKey: .nameSv) ?? ""
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? StableRecordID.legacy(prefix: "unit", name: decodedNameSv),
            parentUnitID: try container.decodeIfPresent(String.self, forKey: .parentUnitID),
            nameSv: decodedNameSv,
            nameEn: try container.decodeIfPresent(String.self, forKey: .nameEn) ?? "",
            abbreviation: try container.decodeIfPresent(String.self, forKey: .abbreviation) ?? "",
            addressNameEn: try container.decodeIfPresent(String.self, forKey: .addressNameEn) ?? "",
            city: try container.decodeIfPresent(String.self, forKey: .city) ?? "",
            inAddress: try container.decodeIfPresent(Bool.self, forKey: .inAddress) ?? true,
            childrenInAddress: try container.decodeIfPresent(Bool.self, forKey: .childrenInAddress) ?? true,
            validFrom: try container.decodeIfPresent(String.self, forKey: .validFrom) ?? "",
            validTo: try container.decodeIfPresent(String.self, forKey: .validTo) ?? "",
            isTemplate: try container.decodeIfPresent(Bool.self, forKey: .isTemplate) ?? false,
            standsInForOrganizationInAddress: try container.decodeIfPresent(
                Bool.self,
                forKey: .standsInForOrganizationInAddress
            ) ?? false
        )
    }

    mutating func normalize() {
        parentUnitID = parentUnitID?.trimmedOrNil
        if parentUnitID == id {
            parentUnitID = nil
        }
        nameSv = nameSv.trimmingCharacters(in: .whitespacesAndNewlines)
        nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        abbreviation = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        addressNameEn = addressNameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        validFrom = DateParsers.canonicalizedDayInput(validFrom.trimmingCharacters(in: .whitespacesAndNewlines))
        validTo = DateParsers.canonicalizedDayInput(validTo.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// False when the unit ends before it starts (both dates given).
    var hasValidDateRange: Bool {
        guard let start = OrganizationTree.rangeStart(validFrom),
              let end = OrganizationTree.rangeEnd(validTo) else {
            return true
        }
        return start <= end
    }

    /// Whether the unit exists on the given ISO day ("2026-09-28").
    func isValid(onDay day: String) -> Bool {
        guard hasValidDateRange else { return false }
        if let start = OrganizationTree.rangeStart(validFrom), day < start {
            return false
        }
        if let end = OrganizationTree.rangeEnd(validTo), day > end {
            return false
        }
        return true
    }

    /// The English name for a publication address.
    var addressName: String {
        addressNameEn.nonEmpty ?? nameEn.nonEmpty ?? nameSv
    }

    func displayName(language: AppLanguage) -> String {
        if language == .swedish {
            return nameSv.nonEmpty ?? nameEn
        }
        return nameEn.nonEmpty ?? nameSv
    }
}

extension OrganizationRecord {
    /// The English organization name used in publication addresses.
    var publicationAddressName: String {
        addressNameEn.nonEmpty ?? nameEn.nonEmpty ?? nameSv
    }

    func unit(withID unitID: String?) -> OrganizationUnit? {
        guard let unitID = unitID?.trimmedOrNil else { return nil }
        return units.first { $0.id == unitID }
    }

    /// Units directly below `parentUnitID` (nil = the top level), in stored order.
    func childUnits(of parentUnitID: String?) -> [OrganizationUnit] {
        units.filter { $0.parentUnitID == parentUnitID }
    }

    /// The unit and its ancestors, top level first and the unit last.
    /// Empty when the unit is not in this organization. Safe against loops.
    func unitPath(to unitID: String) -> [OrganizationUnit] {
        var path: [OrganizationUnit] = []
        var visited = Set<String>()
        var current = unit(withID: unitID)
        while let unit = current, visited.insert(unit.id).inserted {
            path.append(unit)
            current = self.unit(withID: unit.parentUnitID)
        }
        return path.reversed()
    }

    /// "Fakulteten / Institutionen för exempelvetenskap".
    func unitPathText(to unitID: String, language: AppLanguage = .swedish) -> String {
        unitPath(to: unitID).map { $0.displayName(language: language) }.joined(separator: " / ")
    }

    /// The unit that is written in a publication address for `unitID`:
    /// if an ancestor (or the unit itself) has `childrenInAddress == false`,
    /// the topmost such level is the starting point; from there the nearest
    /// level (itself or upwards) with `inAddress == true` is used. Nil when no
    /// level is printed (the address then names the organization only).
    func addressUnit(for unitID: String?) -> OrganizationUnit? {
        guard let unitID = unitID?.trimmedOrNil else { return nil }
        let path = unitPath(to: unitID)
        guard !path.isEmpty else { return nil }
        var startIndex = path.count - 1
        if let collapseIndex = path.firstIndex(where: { !$0.childrenInAddress }) {
            startIndex = collapseIndex
        }
        var index = startIndex
        while index >= 0 {
            if path[index].inAddress {
                return path[index]
            }
            index -= 1
        }
        return nil
    }

    /// One publication address line, for example
    /// "Department of Example Sciences, Example University, Exempelstad, Sweden".
    func publicationAddressLine(unit: OrganizationUnit?) -> String {
        OrganizationTree.publicationAddressLine(organization: self, unit: unit)
    }
}

enum OrganizationTree {
    /// Builds one publication address line: [unit's English address name,
    /// organization's English address name, city, country]. The unit is
    /// first moved to the level that is printed (see
    /// `OrganizationRecord.addressUnit(for:)`). The city is the address
    /// unit's, else the nearest parent's, else the organization's.
    static func publicationAddressLine(organization: OrganizationRecord, unit: OrganizationUnit?) -> String {
        let addressUnit: OrganizationUnit?
        var cityCandidates: [String] = []
        if let unit {
            if organization.unit(withID: unit.id) != nil {
                addressUnit = organization.addressUnit(for: unit.id)
                if let addressUnit {
                    cityCandidates = organization.unitPath(to: addressUnit.id).reversed().map(\.city)
                }
            } else {
                // A unit that is not stored in the organization (yet): use it as it is.
                addressUnit = unit.inAddress ? unit : nil
                cityCandidates = [unit.city]
            }
        } else {
            addressUnit = nil
        }
        let city = cityCandidates.compactMap(\.nonEmpty).first ?? organization.city.nonEmpty ?? ""
        // A unit that stands in for the organization (a university hospital
        // under its region) is written where the organization's name would be.
        let standIn: OrganizationUnit? = addressUnit.flatMap { printed in
            guard organization.unit(withID: printed.id) != nil else {
                return printed.standsInForOrganizationInAddress ? printed : nil
            }
            return organization.unitPath(to: printed.id).last(where: \.standsInForOrganizationInAddress)
        }
        let parts: [String]
        if let standIn {
            parts = [
                standIn.id == addressUnit?.id ? "" : (addressUnit?.addressName ?? ""),
                standIn.addressName,
                city,
                organization.country,
            ]
        } else {
            parts = [
                addressUnit?.addressName ?? "",
                organization.publicationAddressName,
                city,
                organization.country,
            ]
        }
        return joinedAddressParts(parts)
    }

    /// The researcher's publication address lines on the given day: one line
    /// per unit, from the affiliations and the employments that are ongoing
    /// that day. Rows that point to an organization use the tree; rows that
    /// are not linked yet use their text. Lines are unique and ordered by the
    /// organization's `addressOrder` (organizations without one last),
    /// otherwise in the order the rows are written.
    static func publicationAddressLines(
        for author: PublicationAuthor,
        organizations: [OrganizationRecord],
        asOf date: Date = Date()
    ) -> [String] {
        let day = dayString(from: date)
        let organizationsByID = Dictionary(organizations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        struct Entry {
            var key: String
            var line: String
            var order: Int?
            var position: Int
        }
        var entries: [Entry] = []
        var seenKeys = Set<String>()
        var seenLines = Set<String>()

        func add(organizationID: String?, unitID: String?, fallback: [String]) {
            let key: String
            let line: String
            let order: Int?
            if let organizationID, let organization = organizationsByID[organizationID] {
                let unit = organization.unit(withID: unitID)
                let addressUnitID = unit.flatMap { organization.addressUnit(for: $0.id)?.id } ?? ""
                key = "id|\(organization.id)|\(addressUnitID)"
                line = organization.publicationAddressLine(unit: unit)
                order = organization.addressOrder
            } else {
                line = joinedAddressParts(fallback)
                key = "text|\(matchKey(line))"
                order = nil
            }
            guard line.nonEmpty != nil else { return }
            let lineKey = matchKey(line)
            guard seenKeys.insert(key).inserted, seenLines.insert(lineKey).inserted else { return }
            entries.append(Entry(key: key, line: line, order: order, position: entries.count))
        }

        for affiliation in author.affiliations {
            add(
                organizationID: affiliation.organizationID,
                unitID: affiliation.unitID,
                fallback: [
                    affiliation.departmentEn.nonEmpty ?? affiliation.departmentSv,
                    affiliation.organizationEn.nonEmpty ?? affiliation.organizationSv,
                    affiliation.city,
                    affiliation.country,
                ]
            )
        }
        for employment in author.employments where isOngoing(employment, onDay: day) {
            add(
                organizationID: employment.organizationID,
                unitID: employment.unitID,
                fallback: [
                    employment.departmentEn.nonEmpty ?? employment.departmentSv,
                    employment.organizationEn.nonEmpty ?? employment.organizationSv,
                    employment.city,
                    employment.country,
                ]
            )
        }

        return entries
            .sorted { lhs, rhs in
                let left = lhs.order ?? Int.max
                let right = rhs.order ?? Int.max
                if left != right {
                    return left < right
                }
                return lhs.position < rhs.position
            }
            .map(\.line)
    }

    /// Whether an employment covers the given ISO day. An employment without
    /// a start day counts only when it is marked as ongoing.
    static func isOngoing(_ employment: PublicationAuthorEmployment, onDay day: String) -> Bool {
        guard employment.from.nonEmpty != nil || employment.isOngoing else { return false }
        if let start = rangeStart(employment.from), day < start {
            return false
        }
        if let end = rangeEnd(employment.to), day > end {
            return false
        }
        return true
    }

    static func dayString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04ld-%02ld-%02ld",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    /// First day of a period written as "2020", "2020-05" or "2020-05-03";
    /// nil for "". Other text is compared as written.
    static func rangeStart(_ value: String) -> String? {
        guard let trimmed = value.trimmedOrNil else { return nil }
        let canonical = DateParsers.canonicalizedDayInput(trimmed)
        if canonical.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
            return "\(canonical)-01-01"
        }
        if canonical.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil {
            return "\(canonical)-01"
        }
        return canonical
    }

    /// Last day of a period written as "2020", "2020-05" or "2020-05-03";
    /// nil for "". A month ends on "-31", which sorts after every real day.
    static func rangeEnd(_ value: String) -> String? {
        guard let trimmed = value.trimmedOrNil else { return nil }
        let canonical = DateParsers.canonicalizedDayInput(trimmed)
        if canonical.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
            return "\(canonical)-12-31"
        }
        if canonical.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil {
            return "\(canonical)-31"
        }
        return canonical
    }

    /// Comparison key for names: case, accents, punctuation and extra
    /// spaces are ignored ("Institutionen för hälsa, vård och miljö" →
    /// "institutionen for halsa vard och miljo").
    static func matchKey(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var result = ""
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace, !result.isEmpty {
                    result.append(" ")
                }
                pendingSpace = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        return result
    }

    /// Joins address parts with ", ", leaving out empty parts and a part that
    /// repeats the one before it.
    static func joinedAddressParts(_ parts: [String]) -> String {
        var result: [String] = []
        for part in parts {
            guard let trimmed = part.trimmedOrNil else { continue }
            if let last = result.last, matchKey(last) == matchKey(trimmed) {
                continue
            }
            result.append(trimmed)
        }
        return result.joined(separator: ", ")
    }
}

extension GrantDataStore {
    /// F21: the researcher's publication address lines on the given day
    /// (see `OrganizationTree.publicationAddressLines`).
    func publicationAddressLines(for author: PublicationAuthor, asOf date: Date = Date()) -> [String] {
        OrganizationTree.publicationAddressLines(for: author, organizations: organizations, asOf: date)
    }
}
