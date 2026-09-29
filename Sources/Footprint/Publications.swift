import Foundation

private func localizedContentValue(language: AppLanguage, swedish: String, english: String) -> String {
    let swedishValue = swedish.trimmingCharacters(in: .whitespacesAndNewlines)
    let englishValue = english.trimmingCharacters(in: .whitespacesAndNewlines)

    if language == .swedish {
        return swedishValue.nonEmpty ?? englishValue
    }
    return englishValue.nonEmpty ?? swedishValue
}

func normalizedJournalCategory(_ value: String?) -> String? {
    guard let trimmed = value?.trimmedOrNil else { return nil }
    let normalizedAmpersand = trimmed.replacingOccurrences(of: "&", with: "and")
    let collapsedWhitespace = normalizedAmpersand.replacingOccurrences(
        of: #"\s+"#,
        with: " ",
        options: .regularExpression
    )
    let lowercased = collapsedWhitespace.lowercased()
    return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
}

func mergedJournalFilterCategory(_ value: String?) -> String? {
    guard let normalized = normalizedJournalCategory(value) else { return nil }
    switch normalized {
    case "Medicine",
         "Medicine (miscellaneous)",
         "Medicine, general and internal",
         "Internal medicine",
         "General and internal",
         "Multidisciplinary sciences",
         "Multidisciplinary":
        return "General medicine"

    case "Public health, environmental and occupational health",
         "Public, environmental and occupational health",
         "Health policy":
        return "Public health"

    case "Neuroscience",
         "Neurosciences",
         "Clinical neurology",
         "Neurology",
         "Neurology (clinical)",
         "Neuroscience (miscellaneous)":
        return "Neurology and neuroscience"

    case "Genetics (clinical)":
        return "Genetics"

    case "Cardiology and cardiovascular medicine",
         "Cardiac and cardiovascular systems",
         "Cardiovascular",
         "Peripheral vascular disease":
        return "Cardiovascular"

    case "Immunology",
         "Immunology and microbiology",
         "Microbiology",
         "Microbiology (medical)",
         "Infectious diseases",
         "Virology":
        return "Immunology and infection"

    case "Immunology and allergy",
         "Allergy",
         "Rheumatology":
        return "Rheumatology and allergy"

    case "Endocrinology",
         "Endocrinology and metabolism",
         "Endocrinology, diabetes and metabolism":
        return "Endocrinology and metabolism"

    case "Endocrine and autonomic systems":
        return "Endocrinology and metabolism"

    case "Gastroenterology",
         "Gastroenterology and hepatology",
         "Hepatology":
        return "Gastroenterology and hepatology"

    case "Pharmacology",
         "Pharmacology (medical)",
         "Pharmacology, toxicology and pharmaceutics",
         "Toxicology",
         "Drug discovery":
        return "Pharmacology and toxicology"

    case "Psychiatry and mental health",
         "Psychology",
         "Clinical psychology":
        return "Mental health and psychology"

    case "Gerontology",
         "Geriatrics and gerontology",
         "Aging":
        return "Geriatrics and gerontology"

    case "Rehabilitation",
         "Physical therapy, sports therapy and rehabilitation":
        return "Sports medicine and rehabilitation"

    case "Andrology",
         "Urology and nephrology",
         "Urology",
         "Nephrology":
        return "Urology and nephrology"

    case "Radiology, nuclear medicine and imaging",
         "Radiological and ultrasound technology",
         "Medical laboratory technology":
        return "Imaging and diagnostics"

    case "Pulmonary and respiratory medicine",
         "Respiratory system",
         "Respiratory",
         "Respiratory care":
        return "Pulmonary and respiratory medicine"

    case "Emergency medicine",
         "Emergency medical services":
        return "Critical care and anesthesiology"

    case "Foods and nutrition",
         "Food science",
         "Nutrition and dietetics",
         "Plant science",
         "Plant sciences":
        return "Nutrition and dietetics"

    case "Applied microbiology and biotechnology",
         "Immunology and microbiology (miscellaneous)",
         "Parasitology":
        return "Immunology and infection"

    case "Clinical biochemistry",
         "Pathology and forensic medicine":
        return "Pathology and laboratory medicine"

    case "Orthopedics and sports medicine",
         "Podiatry",
         "Occupational therapy":
        return "Musculoskeletal and rehabilitation"

    case "Behavioral neuroscience",
         "Biological psychiatry",
         "Cognitive neuroscience",
         "Developmental and educational psychology":
        return "Behavioral and cognitive sciences"

    case "Obstetrics and gynecology",
         "Reproductive medicine":
        return "Obstetrics and gynecology"

    case "Reviews",
         "Reviews and references (medical)":
        return "Reviews"

    case "Primary health care",
         "Family practice",
         "Community and home care",
         "Primary care":
        return "General medicine"

    case "Critical care",
         "Critical care and intensive care medicine",
         "Anesthesiology and pain medicine":
        return "Critical care and anesthesiology"

    default:
        return normalized
    }
}

struct PublicationAffiliation: Codable, Hashable, Identifiable {
    var id: String
    var organizationSv: String
    var organizationEn: String
    var departmentSv: String
    var departmentEn: String
    var city: String
    var country: String
    var email: String
    var isPrimary: Bool
    /// F21: the organization this row points to (the text above stays as
    /// the display fallback); nil = not linked yet.
    var organizationID: String?
    /// F21: the unit in the organization's tree; nil = the organization itself.
    var unitID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case organization
        case organizationSv
        case organizationEn
        case department
        case departmentSv
        case departmentEn
        case city
        case country
        case email
        case isPrimary
        case organizationID
        case unitID
    }

    init(
        id: String = UUID().uuidString,
        organization: String = "",
        organizationSv: String? = nil,
        organizationEn: String? = nil,
        department: String = "",
        departmentSv: String? = nil,
        departmentEn: String? = nil,
        city: String = "",
        country: String = "",
        email: String = "",
        isPrimary: Bool = false,
        organizationID: String? = nil,
        unitID: String? = nil
    ) {
        self.id = id
        self.organizationSv = organizationSv ?? organization
        self.organizationEn = organizationEn ?? organization
        self.departmentSv = departmentSv ?? department
        self.departmentEn = departmentEn ?? department
        self.city = city
        self.country = country
        self.email = email
        self.isPrimary = isPrimary
        self.organizationID = organizationID
        self.unitID = unitID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            organization: try container.decodeIfPresent(String.self, forKey: .organization) ?? "",
            organizationSv: try container.decodeIfPresent(String.self, forKey: .organizationSv),
            organizationEn: try container.decodeIfPresent(String.self, forKey: .organizationEn),
            department: try container.decodeIfPresent(String.self, forKey: .department) ?? "",
            departmentSv: try container.decodeIfPresent(String.self, forKey: .departmentSv),
            departmentEn: try container.decodeIfPresent(String.self, forKey: .departmentEn),
            city: try container.decodeIfPresent(String.self, forKey: .city) ?? "",
            country: try container.decodeIfPresent(String.self, forKey: .country) ?? "",
            email: try container.decodeIfPresent(String.self, forKey: .email) ?? "",
            isPrimary: try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false,
            organizationID: try container.decodeIfPresent(String.self, forKey: .organizationID),
            unitID: try container.decodeIfPresent(String.self, forKey: .unitID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(organizationSv, forKey: .organization)
        try container.encode(organizationSv, forKey: .organizationSv)
        try container.encode(organizationEn, forKey: .organizationEn)
        try container.encode(department, forKey: .department)
        try container.encode(departmentSv, forKey: .departmentSv)
        try container.encode(departmentEn, forKey: .departmentEn)
        try container.encode(city, forKey: .city)
        try container.encode(country, forKey: .country)
        try container.encode(email, forKey: .email)
        try container.encode(isPrimary, forKey: .isPrimary)
        try container.encodeIfPresent(organizationID, forKey: .organizationID)
        try container.encodeIfPresent(unitID, forKey: .unitID)
    }

    mutating func normalize() {
        organizationSv = organizationSv.trimmingCharacters(in: .whitespacesAndNewlines)
        organizationEn = organizationEn.trimmingCharacters(in: .whitespacesAndNewlines)
        departmentSv = departmentSv.trimmingCharacters(in: .whitespacesAndNewlines)
        departmentEn = departmentEn.trimmingCharacters(in: .whitespacesAndNewlines)
        city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        if country.uppercased() == "SWEDEN" {
            country = "Sweden"
        }
        email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        organizationID = organizationID?.trimmedOrNil
        unitID = organizationID == nil ? nil : unitID?.trimmedOrNil
    }

    var isEmpty: Bool {
        organization.nonEmpty == nil &&
            department.nonEmpty == nil &&
            city.nonEmpty == nil &&
            country.nonEmpty == nil &&
            email.nonEmpty == nil
    }

    var displayLine: String {
        [organization.nonEmpty, department.nonEmpty, city.nonEmpty, country.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var organization: String {
        get { organizationSv.nonEmpty ?? organizationEn }
        set {
            organizationSv = newValue
            organizationEn = newValue
        }
    }

    var department: String {
        get { departmentSv.nonEmpty ?? departmentEn }
        set {
            departmentSv = newValue
            departmentEn = newValue
        }
    }

    func localizedDepartment(language: AppLanguage) -> String {
        localizedContentValue(language: language, swedish: departmentSv, english: departmentEn)
    }

    func localizedOrganization(language: AppLanguage) -> String {
        localizedContentValue(language: language, swedish: organizationSv, english: organizationEn)
    }

    mutating func setLocalizedOrganization(_ value: String, language: AppLanguage) {
        if language == .swedish {
            organizationSv = value
        } else {
            organizationEn = value
        }
    }

    mutating func setLocalizedDepartment(_ value: String, language: AppLanguage) {
        if language == .swedish {
            departmentSv = value
        } else {
            departmentEn = value
        }
    }
}

struct PublicationAuthorContribution: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var count: Int

    init(id: String = UUID().uuidString, title: String, count: Int) {
        self.id = id
        self.title = title
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTitle = try container.decode(String.self, forKey: .title)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? StableRecordID.legacy(prefix: "publication-contribution", name: decodedTitle),
            title: decodedTitle,
            count: try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        )
    }
}

enum PublicationAuthorEducationLevel: String, Codable, Hashable, CaseIterable {
    case basicEducation
    case standaloneCourse
    case bachelor
    case master
    case doctoral
    case other
}

enum PublicationAuthorGender: String, Codable, Hashable, CaseIterable, Identifiable {
    case unspecified
    case female
    case male

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch rawValue {
        case "female", "woman", "kvinna", "f":
            self = .female
        case "male", "man", "m":
            self = .male
        default:
            self = .unspecified
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .unspecified:
            return language.text("Not set", "Ej angivet")
        case .female:
            return language.text("Woman", "Kvinna")
        case .male:
            return language.text("Man", "Man")
        }
    }
}

enum PublicationAuthorCareerStage: String, Codable, Hashable, CaseIterable, Identifiable {
    case categoryA = "A"
    case categoryB = "B"
    case categoryC = "C"
    case categoryD = "D"

    var id: String { rawValue }

    static var editorDisplayOrder: [PublicationAuthorCareerStage] {
        [.categoryD, .categoryC, .categoryB, .categoryA]
    }

    static let overviewHelpText = """
    A: Highest career stage, e.g., full professor
    B: Intermediate stage between C and A, e.g., associate professor
    C: First post after PhD, e.g., assistant professor or postdoctoral researcher
    D: Doctoral student researcher
    """

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch rawValue {
        case "a", "categorya", "category a":
            self = .categoryA
        case "b", "categoryb", "category b":
            self = .categoryB
        case "c", "categoryc", "category c":
            self = .categoryC
        case "d", "categoryd", "category d":
            self = .categoryD
        default:
            self = .categoryB
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    func shortLabel(language: AppLanguage) -> String {
        switch self {
        case .categoryA:
            return language.text("Top", "Topp")
        case .categoryB:
            return language.text("Senior", "Senior")
        case .categoryC:
            return language.text("Entry", "Ingång")
        case .categoryD:
            return language.text("No PhD", "Ej PhD")
        }
    }

    var helpText: String {
        switch self {
        case .categoryA:
            return "Highest career stage, e.g., full professor"
        case .categoryB:
            return "Intermediate stage between C and A, e.g., associate professor"
        case .categoryC:
            return "First post after PhD, e.g., assistant professor or postdoctoral researcher"
        case .categoryD:
            return "Doctoral student researcher"
        }
    }
}

struct PublicationAuthorEmployment: Codable, Hashable, Identifiable {
    var id: String
    var from: String
    var to: String
    var isOngoing: Bool
    var titleSv: String
    var titleEn: String
    var organizationSv: String
    var organizationEn: String
    var departmentSv: String
    var departmentEn: String
    var city: String
    var country: String
    /// F21: the organization this row points to (the text above stays as
    /// the display fallback); nil = not linked yet.
    var organizationID: String?
    /// F21: the unit in the organization's tree; nil = the organization itself.
    var unitID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case from
        case to
        case isOngoing
        case title
        case titleSv
        case titleEn
        case organization
        case organizationSv
        case organizationEn
        case department
        case departmentSv
        case departmentEn
        case city
        case country
        case organizationID
        case unitID
    }

    init(
        id: String = UUID().uuidString,
        from: String = "",
        to: String = "",
        isOngoing: Bool = false,
        title: String = "",
        titleSv: String? = nil,
        titleEn: String? = nil,
        organization: String = "",
        organizationSv: String? = nil,
        organizationEn: String? = nil,
        department: String = "",
        departmentSv: String? = nil,
        departmentEn: String? = nil,
        city: String = "",
        country: String = "",
        organizationID: String? = nil,
        unitID: String? = nil
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.isOngoing = isOngoing
        self.titleSv = titleSv ?? title
        self.titleEn = titleEn ?? title
        self.organizationSv = organizationSv ?? organization
        self.organizationEn = organizationEn ?? organization
        self.departmentSv = departmentSv ?? department
        self.departmentEn = departmentEn ?? department
        self.city = city
        self.country = country
        self.organizationID = organizationID
        self.unitID = unitID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            from: try container.decodeIfPresent(String.self, forKey: .from) ?? "",
            to: try container.decodeIfPresent(String.self, forKey: .to) ?? "",
            isOngoing: try container.decodeIfPresent(Bool.self, forKey: .isOngoing) ?? false,
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            titleSv: try container.decodeIfPresent(String.self, forKey: .titleSv),
            titleEn: try container.decodeIfPresent(String.self, forKey: .titleEn),
            organization: try container.decodeIfPresent(String.self, forKey: .organization) ?? "",
            organizationSv: try container.decodeIfPresent(String.self, forKey: .organizationSv),
            organizationEn: try container.decodeIfPresent(String.self, forKey: .organizationEn),
            department: try container.decodeIfPresent(String.self, forKey: .department) ?? "",
            departmentSv: try container.decodeIfPresent(String.self, forKey: .departmentSv),
            departmentEn: try container.decodeIfPresent(String.self, forKey: .departmentEn),
            city: try container.decodeIfPresent(String.self, forKey: .city) ?? "",
            country: try container.decodeIfPresent(String.self, forKey: .country) ?? "",
            organizationID: try container.decodeIfPresent(String.self, forKey: .organizationID),
            unitID: try container.decodeIfPresent(String.self, forKey: .unitID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(isOngoing, forKey: .isOngoing)
        try container.encode(title, forKey: .title)
        try container.encode(titleSv, forKey: .titleSv)
        try container.encode(titleEn, forKey: .titleEn)
        try container.encode(organizationSv, forKey: .organization)
        try container.encode(organizationSv, forKey: .organizationSv)
        try container.encode(organizationEn, forKey: .organizationEn)
        try container.encode(department, forKey: .department)
        try container.encode(departmentSv, forKey: .departmentSv)
        try container.encode(departmentEn, forKey: .departmentEn)
        try container.encode(city, forKey: .city)
        try container.encode(country, forKey: .country)
        try container.encodeIfPresent(organizationID, forKey: .organizationID)
        try container.encodeIfPresent(unitID, forKey: .unitID)
    }

    mutating func normalize() {
        from = DateParsers.canonicalizedDayInput(from)
        to = DateParsers.canonicalizedDayInput(to)
        isOngoing = from.nonEmpty != nil && to.nonEmpty == nil
        titleSv = titleSv.trimmingCharacters(in: .whitespacesAndNewlines)
        titleEn = titleEn.trimmingCharacters(in: .whitespacesAndNewlines)
        organizationSv = organizationSv.trimmingCharacters(in: .whitespacesAndNewlines)
        organizationEn = organizationEn.trimmingCharacters(in: .whitespacesAndNewlines)
        departmentSv = departmentSv.trimmingCharacters(in: .whitespacesAndNewlines)
        departmentEn = departmentEn.trimmingCharacters(in: .whitespacesAndNewlines)
        city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        organizationID = organizationID?.trimmedOrNil
        unitID = organizationID == nil ? nil : unitID?.trimmedOrNil
    }

    var isEmpty: Bool {
        from.nonEmpty == nil &&
            to.nonEmpty == nil &&
            title.nonEmpty == nil &&
            organization.nonEmpty == nil &&
            department.nonEmpty == nil &&
            city.nonEmpty == nil &&
            country.nonEmpty == nil
    }

    var title: String {
        get { titleSv.nonEmpty ?? titleEn }
        set {
            titleSv = newValue
            titleEn = newValue
        }
    }

    var organization: String {
        get { organizationSv.nonEmpty ?? organizationEn }
        set {
            organizationSv = newValue
            organizationEn = newValue
        }
    }

    var department: String {
        get { departmentSv.nonEmpty ?? departmentEn }
        set {
            departmentSv = newValue
            departmentEn = newValue
        }
    }

    func localizedTitle(language: AppLanguage) -> String {
        localizedContentValue(language: language, swedish: titleSv, english: titleEn)
    }

    func localizedOrganization(language: AppLanguage) -> String {
        localizedContentValue(language: language, swedish: organizationSv, english: organizationEn)
    }

    func localizedDepartment(language: AppLanguage) -> String {
        localizedContentValue(language: language, swedish: departmentSv, english: departmentEn)
    }

    mutating func setLocalizedTitle(_ value: String, language: AppLanguage) {
        if language == .swedish {
            titleSv = value
        } else {
            titleEn = value
        }
    }

    mutating func setLocalizedOrganization(_ value: String, language: AppLanguage) {
        if language == .swedish {
            organizationSv = value
        } else {
            organizationEn = value
        }
    }

    mutating func setLocalizedDepartment(_ value: String, language: AppLanguage) {
        if language == .swedish {
            departmentSv = value
        } else {
            departmentEn = value
        }
    }
}

struct PublicationAuthorEducation: Codable, Hashable, Identifiable {
    var id: String
    var level: PublicationAuthorEducationLevel?
    var from: String
    var to: String
    var isOngoing: Bool
    var degreeSv: String
    var degreeEn: String
    var organizationSv: String
    var organizationEn: String
    var city: String
    var country: String
    /// F21: the organization this row points to (the text above stays as
    /// the display fallback); nil = not linked yet.
    var organizationID: String?
    /// F21: the unit in the organization's tree; nil = the organization itself.
    var unitID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case level
        case from
        case to
        case isOngoing
        case degree
        case degreeSv
        case degreeEn
        case organization
        case organizationSv
        case organizationEn
        case city
        case country
        case organizationID
        case unitID
    }

    init(
        id: String = UUID().uuidString,
        level: PublicationAuthorEducationLevel? = nil,
        from: String = "",
        to: String = "",
        isOngoing: Bool = false,
        degree: String = "",
        degreeSv: String? = nil,
        degreeEn: String? = nil,
        organization: String = "",
        organizationSv: String? = nil,
        organizationEn: String? = nil,
        city: String = "",
        country: String = "",
        organizationID: String? = nil,
        unitID: String? = nil
    ) {
        self.id = id
        self.level = level
        self.from = from
        self.to = to
        self.isOngoing = isOngoing
        self.degreeSv = degreeSv ?? degree
        self.degreeEn = degreeEn ?? degree
        self.organizationSv = organizationSv ?? organization
        self.organizationEn = organizationEn ?? organization
        self.city = city
        self.country = country
        self.organizationID = organizationID
        self.unitID = unitID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            level: try container.decodeIfPresent(PublicationAuthorEducationLevel.self, forKey: .level),
            from: try container.decodeIfPresent(String.self, forKey: .from) ?? "",
            to: try container.decodeIfPresent(String.self, forKey: .to) ?? "",
            isOngoing: try container.decodeIfPresent(Bool.self, forKey: .isOngoing) ?? false,
            degree: try container.decodeIfPresent(String.self, forKey: .degree) ?? "",
            degreeSv: try container.decodeIfPresent(String.self, forKey: .degreeSv),
            degreeEn: try container.decodeIfPresent(String.self, forKey: .degreeEn),
            organization: try container.decodeIfPresent(String.self, forKey: .organization) ?? "",
            organizationSv: try container.decodeIfPresent(String.self, forKey: .organizationSv),
            organizationEn: try container.decodeIfPresent(String.self, forKey: .organizationEn),
            city: try container.decodeIfPresent(String.self, forKey: .city) ?? "",
            country: try container.decodeIfPresent(String.self, forKey: .country) ?? "",
            organizationID: try container.decodeIfPresent(String.self, forKey: .organizationID),
            unitID: try container.decodeIfPresent(String.self, forKey: .unitID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(level, forKey: .level)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(isOngoing, forKey: .isOngoing)
        try container.encode(degree, forKey: .degree)
        try container.encode(degreeSv, forKey: .degreeSv)
        try container.encode(degreeEn, forKey: .degreeEn)
        try container.encode(organizationSv, forKey: .organization)
        try container.encode(organizationSv, forKey: .organizationSv)
        try container.encode(organizationEn, forKey: .organizationEn)
        try container.encode(city, forKey: .city)
        try container.encode(country, forKey: .country)
        try container.encodeIfPresent(organizationID, forKey: .organizationID)
        try container.encodeIfPresent(unitID, forKey: .unitID)
    }

    mutating func normalize() {
        from = DateParsers.canonicalizedDayInput(from)
        to = DateParsers.canonicalizedDayInput(to)
        isOngoing = from.nonEmpty != nil && to.nonEmpty == nil
        degreeSv = degreeSv.trimmingCharacters(in: .whitespacesAndNewlines)
        degreeEn = degreeEn.trimmingCharacters(in: .whitespacesAndNewlines)
        organizationSv = organizationSv.trimmingCharacters(in: .whitespacesAndNewlines)
        organizationEn = organizationEn.trimmingCharacters(in: .whitespacesAndNewlines)
        city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        organizationID = organizationID?.trimmedOrNil
        unitID = organizationID == nil ? nil : unitID?.trimmedOrNil
    }

    var isEmpty: Bool {
        level == nil &&
            from.nonEmpty == nil &&
            to.nonEmpty == nil &&
            degree.nonEmpty == nil &&
            organization.nonEmpty == nil &&
            city.nonEmpty == nil &&
            country.nonEmpty == nil
    }

    var degree: String {
        get { degreeSv.nonEmpty ?? degreeEn }
        set {
            degreeSv = newValue
            degreeEn = newValue
        }
    }

    var organization: String {
        get { organizationSv.nonEmpty ?? organizationEn }
        set {
            organizationSv = newValue
            organizationEn = newValue
        }
    }

    func localizedDegree(language: AppLanguage) -> String {
        localizedContentValue(language: language, swedish: degreeSv, english: degreeEn)
    }

    func localizedOrganization(language: AppLanguage) -> String {
        localizedContentValue(language: language, swedish: organizationSv, english: organizationEn)
    }

    mutating func setLocalizedDegree(_ value: String, language: AppLanguage) {
        if language == .swedish {
            degreeSv = value
        } else {
            degreeEn = value
        }
    }

    mutating func setLocalizedOrganization(_ value: String, language: AppLanguage) {
        if language == .swedish {
            organizationSv = value
        } else {
            organizationEn = value
        }
    }
}

struct PublicationAuthorNameVariant: Codable, Hashable {
    var firstName: String
    var lastName: String
    /// True when the person actually used this name earlier (for example
    /// before marriage); false for an alternative spelling of the name.
    var isFormerName: Bool
    /// Last day or year the former name was used ("" when unknown).
    var usedUntil: String

    enum CodingKeys: String, CodingKey {
        case firstName
        case lastName
        case isFormerName
        case usedUntil
    }

    init(firstName: String = "", lastName: String = "", isFormerName: Bool = false, usedUntil: String = "") {
        self.firstName = firstName
        self.lastName = lastName
        self.isFormerName = isFormerName
        self.usedUntil = usedUntil
        normalize()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            firstName: try container.decodeIfPresent(String.self, forKey: .firstName) ?? "",
            lastName: try container.decodeIfPresent(String.self, forKey: .lastName) ?? "",
            isFormerName: try container.decodeIfPresent(Bool.self, forKey: .isFormerName) ?? false,
            usedUntil: try container.decodeIfPresent(String.self, forKey: .usedUntil) ?? ""
        )
    }

    var displayName: String {
        [firstName.nonEmpty, lastName.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var isEmpty: Bool {
        firstName.trimmedOrNil == nil && lastName.trimmedOrNil == nil
    }

    mutating func normalize() {
        firstName = normalizedPublicationAuthorNamePart(firstName)
        lastName = normalizedPublicationAuthorNamePart(lastName)
        usedUntil = usedUntil.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PublicationAuthor: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var firstName: String
    var lastName: String
    var nameVariantRows: [PublicationAuthorNameVariant]
    var titleSv: String
    var titleEn: String
    var positionSv: String
    var positionEn: String
    var degreeSv: String
    var degreeEn: String
    var gender: PublicationAuthorGender
    var hasPhD: Bool
    var careerStage: PublicationAuthorCareerStage
    var university: String
    var phoneLabel: String
    var phoneNumber: String
    var phoneLabelSecondary: String
    var phoneNumberSecondary: String
    var homeAddressSv: String
    var homeAddressEn: String
    var birthDate: String
    var orcid: String
    var scopus: String
    var researcherID: String
    var institutionWebsite: String
    var ordinal: String
    var declaredTotal: String
    var affiliations: [PublicationAffiliation]
    var employments: [PublicationAuthorEmployment]
    var educationEntries: [PublicationAuthorEducation]
    var publications: [PublicationAuthorContribution]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case firstName
        case lastName
        case nameVariants
        case nameVariantRows
        case title
        case titleSv
        case titleEn
        case position
        case positionSv
        case positionEn
        case degree
        case degreeSv
        case degreeEn
        case gender
        case hasPhD
        case careerStage
        case university
        case phoneLabel
        case phoneNumber
        case phoneLabelSecondary
        case phoneNumberSecondary
        case phoneLabel2
        case phoneNumber2
        case homeAddress
        case homeAddressSv
        case homeAddressEn
        case birthDate
        case orcid
        case scopus
        case researcherID
        case institutionWebsite
        case ordinal
        case declaredTotal
        case affiliations
        case employments
        case educationEntries
        case publications
        case publicationCount
        case country
        case primaryAffiliation
        case secondaryAffiliation
        case email
    }

    init(
        id: String = UUID().uuidString,
        name: String = "",
        firstName: String = "",
        lastName: String = "",
        nameVariants: [String] = [],
        nameVariantRows: [PublicationAuthorNameVariant] = [],
        title: String = "",
        titleSv: String? = nil,
        titleEn: String? = nil,
        position: String = "",
        positionSv: String? = nil,
        positionEn: String? = nil,
        degree: String = "",
        degreeSv: String? = nil,
        degreeEn: String? = nil,
        gender: PublicationAuthorGender = .unspecified,
        hasPhD: Bool = false,
        careerStage: PublicationAuthorCareerStage? = nil,
        university: String = "",
        phoneLabel: String = "",
        phoneNumber: String = "",
        phoneLabelSecondary: String = "",
        phoneNumberSecondary: String = "",
        homeAddress: String = "",
        homeAddressSv: String? = nil,
        homeAddressEn: String? = nil,
        birthDate: String = "",
        orcid: String = "",
        scopus: String = "",
        researcherID: String = "",
        institutionWebsite: String = "",
        ordinal: String = "",
        declaredTotal: String = "",
        affiliations: [PublicationAffiliation] = [],
        employments: [PublicationAuthorEmployment] = [],
        educationEntries: [PublicationAuthorEducation] = [],
        publications: [PublicationAuthorContribution] = []
    ) {
        self.id = id
        self.name = name
        self.firstName = firstName
        self.lastName = lastName
        self.nameVariantRows = nameVariantRows + publicationAuthorNameVariantRows(from: nameVariants)
        self.titleSv = titleSv ?? title
        self.titleEn = titleEn ?? title
        self.positionSv = positionSv ?? position
        self.positionEn = positionEn ?? position
        self.degreeSv = degreeSv ?? degree
        self.degreeEn = degreeEn ?? degree
        self.gender = gender
        self.hasPhD = hasPhD
        self.careerStage = careerStage ?? Self.suggestedCareerStage(
            hasPhD: hasPhD,
            titleSv: titleSv ?? title,
            titleEn: titleEn ?? title,
            positionSv: positionSv ?? position,
            positionEn: positionEn ?? position
        )
        self.university = university
        self.phoneLabel = phoneLabel
        self.phoneNumber = phoneNumber
        self.phoneLabelSecondary = phoneLabelSecondary
        self.phoneNumberSecondary = phoneNumberSecondary
        self.homeAddressSv = homeAddressSv ?? homeAddress
        self.homeAddressEn = homeAddressEn ?? homeAddress
        self.birthDate = birthDate
        self.orcid = orcid
        self.scopus = scopus
        self.researcherID = researcherID
        self.institutionWebsite = institutionWebsite
        self.ordinal = ordinal
        self.declaredTotal = declaredTotal
        self.affiliations = affiliations
        self.employments = employments
        self.educationEntries = educationEntries
        self.publications = publications
        normalize()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let affiliations = try container.decodeIfPresent([PublicationAffiliation].self, forKey: .affiliations) ?? {
            let primary = PublicationAffiliation(
                organization: (try? container.decodeIfPresent(String.self, forKey: .primaryAffiliation)) ?? "",
                department: "",
                country: (try? container.decodeIfPresent(String.self, forKey: .country)) ?? "",
                email: (try? container.decodeIfPresent(String.self, forKey: .email)) ?? "",
                isPrimary: true
            )
            let secondary = PublicationAffiliation(
                organization: (try? container.decodeIfPresent(String.self, forKey: .secondaryAffiliation)) ?? "",
                department: "",
                country: "",
                email: "",
                isPrimary: false
            )
            return [primary, secondary].filter { !$0.isEmpty }
        }()

        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            firstName: try container.decodeIfPresent(String.self, forKey: .firstName) ?? "",
            lastName: try container.decodeIfPresent(String.self, forKey: .lastName) ?? "",
            nameVariants: try container.decodeIfPresent([String].self, forKey: .nameVariants) ?? [],
            nameVariantRows: try container.decodeIfPresent([PublicationAuthorNameVariant].self, forKey: .nameVariantRows) ?? [],
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            titleSv: try container.decodeIfPresent(String.self, forKey: .titleSv),
            titleEn: try container.decodeIfPresent(String.self, forKey: .titleEn),
            position: try container.decodeIfPresent(String.self, forKey: .position) ?? "",
            positionSv: try container.decodeIfPresent(String.self, forKey: .positionSv),
            positionEn: try container.decodeIfPresent(String.self, forKey: .positionEn),
            degree: try container.decodeIfPresent(String.self, forKey: .degree) ?? "",
            degreeSv: try container.decodeIfPresent(String.self, forKey: .degreeSv),
            degreeEn: try container.decodeIfPresent(String.self, forKey: .degreeEn),
            gender: try container.decodeIfPresent(PublicationAuthorGender.self, forKey: .gender) ?? .unspecified,
            hasPhD: try container.decodeIfPresent(Bool.self, forKey: .hasPhD) ?? false,
            careerStage: try container.decodeIfPresent(PublicationAuthorCareerStage.self, forKey: .careerStage),
            university: try container.decodeIfPresent(String.self, forKey: .university) ?? "",
            phoneLabel: try container.decodeIfPresent(String.self, forKey: .phoneLabel) ?? "",
            phoneNumber: try container.decodeIfPresent(String.self, forKey: .phoneNumber) ?? "",
            phoneLabelSecondary: (try? container.decodeIfPresent(String.self, forKey: .phoneLabelSecondary))
                ?? (try? container.decodeIfPresent(String.self, forKey: .phoneLabel2))
                ?? "",
            phoneNumberSecondary: (try? container.decodeIfPresent(String.self, forKey: .phoneNumberSecondary))
                ?? (try? container.decodeIfPresent(String.self, forKey: .phoneNumber2))
                ?? "",
            homeAddress: try container.decodeIfPresent(String.self, forKey: .homeAddress) ?? "",
            homeAddressSv: try container.decodeIfPresent(String.self, forKey: .homeAddressSv),
            homeAddressEn: try container.decodeIfPresent(String.self, forKey: .homeAddressEn),
            birthDate: try container.decodeIfPresent(String.self, forKey: .birthDate) ?? "",
            orcid: try container.decodeIfPresent(String.self, forKey: .orcid) ?? "",
            scopus: try container.decodeIfPresent(String.self, forKey: .scopus) ?? "",
            researcherID: try container.decodeIfPresent(String.self, forKey: .researcherID) ?? "",
            institutionWebsite: try container.decodeIfPresent(String.self, forKey: .institutionWebsite) ?? "",
            ordinal: try container.decodeIfPresent(String.self, forKey: .ordinal) ?? "",
            declaredTotal: try container.decodeIfPresent(String.self, forKey: .declaredTotal) ?? "",
            affiliations: affiliations,
            employments: try container.decodeIfPresent([PublicationAuthorEmployment].self, forKey: .employments) ?? [],
            educationEntries: try container.decodeIfPresent([PublicationAuthorEducation].self, forKey: .educationEntries) ?? [],
            publications: try container.decodeIfPresent([PublicationAuthorContribution].self, forKey: .publications) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        if !nameVariants.isEmpty {
            try container.encode(nameVariants, forKey: .nameVariants)
        }
        if !nameVariantRows.isEmpty {
            try container.encode(nameVariantRows, forKey: .nameVariantRows)
        }
        try container.encode(title, forKey: .title)
        try container.encode(titleSv, forKey: .titleSv)
        try container.encode(titleEn, forKey: .titleEn)
        try container.encode(position, forKey: .position)
        try container.encode(positionSv, forKey: .positionSv)
        try container.encode(positionEn, forKey: .positionEn)
        try container.encode(degree, forKey: .degree)
        try container.encode(degreeSv, forKey: .degreeSv)
        try container.encode(degreeEn, forKey: .degreeEn)
        try container.encode(gender, forKey: .gender)
        try container.encode(hasPhD, forKey: .hasPhD)
        try container.encode(careerStage, forKey: .careerStage)
        try container.encode(university, forKey: .university)
        try container.encode(phoneLabel, forKey: .phoneLabel)
        try container.encode(phoneNumber, forKey: .phoneNumber)
        try container.encode(phoneLabelSecondary, forKey: .phoneLabelSecondary)
        try container.encode(phoneNumberSecondary, forKey: .phoneNumberSecondary)
        try container.encode(homeAddress, forKey: .homeAddress)
        try container.encode(homeAddressSv, forKey: .homeAddressSv)
        try container.encode(homeAddressEn, forKey: .homeAddressEn)
        try container.encode(birthDate, forKey: .birthDate)
        try container.encode(orcid, forKey: .orcid)
        try container.encode(scopus, forKey: .scopus)
        try container.encode(researcherID, forKey: .researcherID)
        try container.encode(institutionWebsite, forKey: .institutionWebsite)
        try container.encode(ordinal, forKey: .ordinal)
        try container.encode(declaredTotal, forKey: .declaredTotal)
        try container.encode(affiliations, forKey: .affiliations)
        try container.encode(employments, forKey: .employments)
        try container.encode(educationEntries, forKey: .educationEntries)
        try container.encode(publications, forKey: .publications)
    }

    mutating func normalize() {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        titleSv = titleSv.trimmingCharacters(in: .whitespacesAndNewlines)
        titleEn = titleEn.trimmingCharacters(in: .whitespacesAndNewlines)
        positionSv = positionSv.trimmingCharacters(in: .whitespacesAndNewlines)
        positionEn = positionEn.trimmingCharacters(in: .whitespacesAndNewlines)
        degreeSv = degreeSv.trimmingCharacters(in: .whitespacesAndNewlines)
        degreeEn = degreeEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let (cleanedDegreeSv, detectedPhDSv) = Self.strippingPhD(from: degreeSv)
        degreeSv = cleanedDegreeSv
        let (cleanedDegreeEn, detectedPhDEn) = Self.strippingPhD(from: degreeEn)
        degreeEn = cleanedDegreeEn
        if detectedPhDSv || detectedPhDEn {
            hasPhD = true
        }
        university = university.trimmingCharacters(in: .whitespacesAndNewlines)
        phoneLabel = phoneLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        phoneNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        phoneLabelSecondary = phoneLabelSecondary.trimmingCharacters(in: .whitespacesAndNewlines)
        phoneNumberSecondary = phoneNumberSecondary.trimmingCharacters(in: .whitespacesAndNewlines)
        if phoneNumber.isEmpty {
            phoneLabel = ""
        }
        if phoneNumberSecondary.isEmpty {
            phoneLabelSecondary = ""
        }
        if phoneNumberSecondary == phoneNumber && phoneLabelSecondary == phoneLabel {
            phoneNumberSecondary = ""
            phoneLabelSecondary = ""
        }
        homeAddressSv = homeAddressSv.trimmingCharacters(in: .whitespacesAndNewlines)
        homeAddressEn = homeAddressEn.trimmingCharacters(in: .whitespacesAndNewlines)
        birthDate = DateParsers.canonicalizedDayInput(birthDate)
        orcid = PublicationAuthor.normalizedORCID(orcid)
        scopus = scopus.trimmingCharacters(in: .whitespacesAndNewlines)
        researcherID = researcherID.trimmingCharacters(in: .whitespacesAndNewlines)
        institutionWebsite = institutionWebsite.trimmingCharacters(in: .whitespacesAndNewlines)
        ordinal = ordinal.trimmingCharacters(in: .whitespacesAndNewlines)
        declaredTotal = declaredTotal.trimmingCharacters(in: .whitespacesAndNewlines)
        if firstName.isEmpty && lastName.isEmpty, let legacyName = name.nonEmpty {
            let parts = legacyName.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count > 1 {
                firstName = parts.dropLast().joined(separator: " ")
                lastName = String(parts.last ?? "")
            } else {
                firstName = legacyName
            }
        }
        let rebuiltName = [firstName.nonEmpty, lastName.nonEmpty].compactMap { $0 }.joined(separator: " ")
        if let rebuiltName = rebuiltName.nonEmpty {
            name = rebuiltName
        }
        nameVariantRows = normalizedPublicationAuthorNameVariantRows(
            nameVariantRows,
            currentFirstName: firstName,
            currentLastName: lastName,
            excluding: [name, displayName, rebuiltName]
        )
        affiliations = Array(affiliations.prefix(4))
        for index in affiliations.indices {
            affiliations[index].normalize()
        }
        affiliations.removeAll(where: \.isEmpty)
        for index in employments.indices {
            employments[index].normalize()
        }
        employments.removeAll(where: \.isEmpty)
        employments = Self.sortedEmploymentsForEditor(employments)
        for index in educationEntries.indices {
            educationEntries[index].normalize()
        }
        educationEntries.removeAll(where: \.isEmpty)
        educationEntries = Self.sortedEducationEntriesForEditor(educationEntries)
        if !affiliations.isEmpty, !affiliations.contains(where: \.isPrimary) {
            affiliations[0].isPrimary = true
        }
        if let primaryIndex = affiliations.firstIndex(where: \.isPrimary) {
            for index in affiliations.indices where index != primaryIndex {
                affiliations[index].isPrimary = false
            }
        }
    }

    private static func strippingPhD(from raw: String) -> (String, Bool) {
        let pattern = #"(?i)\bph\.?\s*d\.?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (raw, false)
        }
        let range = NSRange(raw.startIndex..., in: raw)
        let detected = regex.firstMatch(in: raw, options: [], range: range) != nil
        let removed = regex.stringByReplacingMatches(in: raw, options: [], range: range, withTemplate: "")
        let cleaned = removed
            .replacingOccurrences(of: #"\s*,\s*,+"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*,\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*,\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, detected)
    }

    var suggestedCareerStage: PublicationAuthorCareerStage {
        Self.suggestedCareerStage(
            hasPhD: hasPhD,
            titleSv: titleSv,
            titleEn: titleEn,
            positionSv: positionSv,
            positionEn: positionEn
        )
    }

    static func suggestedCareerStage(
        hasPhD: Bool,
        titleSv: String,
        titleEn: String,
        positionSv: String,
        positionEn: String
    ) -> PublicationAuthorCareerStage {
        guard hasPhD else { return .categoryA }
        return isTopCareerStage(
            titleSv: titleSv,
            titleEn: titleEn,
            positionSv: positionSv,
            positionEn: positionEn
        ) ? .categoryA : .categoryB
    }

    static func automaticCareerStageWhenEnablingPhD(
        from currentStage: PublicationAuthorCareerStage?
    ) -> PublicationAuthorCareerStage? {
        switch currentStage {
        case .none, .some(.categoryD):
            return .categoryC
        case .some:
            return nil
        }
    }

    private static func isTopCareerStage(
        titleSv: String,
        titleEn: String,
        positionSv: String,
        positionEn: String
    ) -> Bool {
        let combined = normalizedCareerStageText([
            titleSv,
            titleEn,
            positionSv,
            positionEn,
        ])
        guard !combined.isEmpty else { return false }

        let excludedProfessorMarkers = [
            "assistant professor",
            "associate professor",
            "adjunct professor",
            "visiting professor",
            "guest professor",
            "bitradande professor",
            "biträdande professor",
            "adjungerad professor",
            "gästprofessor",
            "postdoc",
            "post-doc",
            "postdoctoral",
            "post-doctoral",
        ]
        if excludedProfessorMarkers.contains(where: combined.contains) {
            return false
        }

        let topRoleMarkers = [
            "professor",
            "full professor",
            "professor emeritus",
            "director of research",
            "research director",
            "head of research",
            "research dean",
            "forskningsdirektor",
            "forskningsdirektör",
            "forskningschef",
            "forskningsledare",
            "dekan",
        ]
        return topRoleMarkers.contains(where: combined.contains)
    }

    private static func normalizedCareerStageText(_ values: [String]) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    var sortName: String {
        [lastName.nonEmpty, firstName.nonEmpty, name.nonEmpty].compactMap { $0 }.joined(separator: " ")
    }

    var displayName: String {
        [firstName.nonEmpty, lastName.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " ")
            .nonEmpty ?? name
    }

    var nameVariants: [String] {
        get {
            nameVariantRows
                .map(\.displayName)
                .compactMap(\.trimmedOrNil)
        }
        set {
            nameVariantRows = normalizedPublicationAuthorNameVariantRows(
                publicationAuthorNameVariantRows(from: newValue),
                currentFirstName: firstName,
                currentLastName: lastName,
                excluding: [name, displayName]
            )
        }
    }

    var presentedNameVariantRows: [PublicationAuthorNameVariant] {
        normalizedPublicationAuthorNameVariantRows(
            [
                PublicationAuthorNameVariant(firstName: firstName, lastName: lastName),
                PublicationAuthorNameVariant(firstName: name, lastName: "")
            ] + nameVariantRows
        )
    }

    var presentedNameCandidates: [String] {
        normalizedPublicationAuthorNameVariants(presentedNameVariantRows.map(\.displayName))
    }

    func presentedNameVariant(matching presentedName: String) -> PublicationAuthorNameVariant? {
        let targetKey = normalizedPublicationAuthorNameVariantKey(presentedName)
        guard !targetKey.isEmpty else { return nil }
        return presentedNameVariantRows.first {
            normalizedPublicationAuthorNameVariantKey($0.displayName) == targetKey
        }
    }

    mutating func addNameVariants(_ variants: [String]) {
        nameVariantRows = normalizedPublicationAuthorNameVariantRows(
            nameVariantRows + publicationAuthorNameVariantRows(from: variants),
            currentFirstName: firstName,
            currentLastName: lastName,
            excluding: [name, displayName]
        )
    }

    @discardableResult
    mutating func promoteNameVariant(_ variant: PublicationAuthorNameVariant) -> Bool {
        guard let promoted = normalizedPublicationAuthorNameVariantRows(
            [variant],
            currentFirstName: firstName,
            currentLastName: lastName,
            fillsMissingPartsFromCurrentName: true
        ).first else {
            return false
        }

        let currentName = PublicationAuthorNameVariant(firstName: firstName, lastName: lastName)
        let promotedKey = normalizedPublicationAuthorNameVariantKey(promoted.displayName)
        guard !promotedKey.isEmpty,
              promotedKey != normalizedPublicationAuthorNameVariantKey(currentName.displayName) else {
            return false
        }

        let normalizedExistingRows = normalizedPublicationAuthorNameVariantRows(
            nameVariantRows,
            currentFirstName: firstName,
            currentLastName: lastName,
            fillsMissingPartsFromCurrentName: true
        )
        let remainingRows = normalizedExistingRows.filter {
            normalizedPublicationAuthorNameVariantKey($0.displayName) != promotedKey
        }
        firstName = promoted.firstName
        lastName = promoted.lastName
        name = promoted.displayName
        nameVariantRows = normalizedPublicationAuthorNameVariantRows(
            remainingRows + [currentName],
            currentFirstName: firstName,
            currentLastName: lastName,
            excluding: [name, displayName]
        )
        normalize()
        return true
    }

    /// Names the person actually used earlier, as opposed to spelling
    /// variants of the current name.
    var formerNames: [PublicationAuthorNameVariant] {
        nameVariantRows.filter(\.isFormerName)
    }

    /// Stores the given name as a former name, used until the given day.
    /// An existing row with the same name is marked instead of duplicated.
    mutating func markFormerName(firstName: String, lastName: String, usedUntil: String) {
        let formerName = PublicationAuthorNameVariant(
            firstName: firstName,
            lastName: lastName,
            isFormerName: true,
            usedUntil: usedUntil
        )
        let targetKey = normalizedPublicationAuthorNameVariantKey(formerName.displayName)
        guard !targetKey.isEmpty else { return }
        if let index = nameVariantRows.firstIndex(where: {
            normalizedPublicationAuthorNameVariantKey($0.displayName) == targetKey
        }) {
            nameVariantRows[index].isFormerName = true
            nameVariantRows[index].usedUntil = formerName.usedUntil
            return
        }
        guard targetKey != normalizedPublicationAuthorNameVariantKey(displayName),
              targetKey != normalizedPublicationAuthorNameVariantKey(name) else {
            return
        }
        nameVariantRows.append(formerName)
    }

    var displaySubtitle: String {
        [position.nonEmpty, primaryAffiliation?.organization.nonEmpty].compactMap { $0 }.joined(separator: " · ")
    }

    var publicationCount: Int {
        publications.map(\.count).reduce(0, +)
    }

    var primaryAffiliation: PublicationAffiliation? {
        affiliations.first(where: \.isPrimary) ?? affiliations.first
    }

    var title: String {
        get { titleSv.nonEmpty ?? titleEn }
        set {
            titleSv = newValue
            titleEn = newValue
        }
    }

    var position: String {
        get { positionSv.nonEmpty ?? positionEn }
        set {
            positionSv = newValue
            positionEn = newValue
        }
    }

    var degree: String {
        get { degreeSv.nonEmpty ?? degreeEn }
        set {
            degreeSv = newValue
            degreeEn = newValue
        }
    }

    var homeAddress: String {
        get { homeAddressSv.nonEmpty ?? homeAddressEn }
        set {
            homeAddressSv = newValue
            homeAddressEn = newValue
        }
    }

    func localizedTitle(language: AppLanguage) -> String {
        localizedContentValue(language: language, swedish: titleSv, english: titleEn)
    }

    func localizedPosition(language: AppLanguage) -> String {
        localizedContentValue(language: language, swedish: positionSv, english: positionEn)
    }

    func localizedDegree(language: AppLanguage) -> String {
        localizedContentValue(language: language, swedish: degreeSv, english: degreeEn)
    }

    func localizedHomeAddress(language: AppLanguage) -> String {
        localizedContentValue(language: language, swedish: homeAddressSv, english: homeAddressEn)
    }

    mutating func setLocalizedTitle(_ value: String, language: AppLanguage) {
        if language == .swedish {
            titleSv = value
        } else {
            titleEn = value
        }
    }

    mutating func setLocalizedPosition(_ value: String, language: AppLanguage) {
        if language == .swedish {
            positionSv = value
        } else {
            positionEn = value
        }
    }

    mutating func setLocalizedDegree(_ value: String, language: AppLanguage) {
        if language == .swedish {
            degreeSv = value
        } else {
            degreeEn = value
        }
    }

    mutating func setLocalizedHomeAddress(_ value: String, language: AppLanguage) {
        if language == .swedish {
            homeAddressSv = value
        } else {
            homeAddressEn = value
        }
    }

    static func sortedEmploymentsForEditor(_ entries: [PublicationAuthorEmployment]) -> [PublicationAuthorEmployment] {
        entries
            .enumerated()
            .sorted { lhs, rhs in
                let leftDate = lhs.element.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                let rightDate = rhs.element.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                switch (leftDate, rightDate) {
                case let (left?, right?):
                    if left != right { return left < right }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func sortedEducationEntriesForEditor(_ entries: [PublicationAuthorEducation]) -> [PublicationAuthorEducation] {
        entries
            .enumerated()
            .sorted { lhs, rhs in
                let leftDate = lhs.element.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                let rightDate = rhs.element.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                switch (leftDate, rightDate) {
                case let (left?, right?):
                    if left != right { return left < right }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    var primaryCountry: String {
        primaryAffiliation?.country ?? ""
    }

    var primaryOrganization: String {
        primaryAffiliation?.organization ?? ""
    }

    var orcidURL: URL? {
        normalizedIdentifierURL(raw: orcid, kind: .orcid)
    }

    var webOfScienceURL: URL? {
        identifierURL(
            raw: researcherID,
            stripping: [
                "https://www.webofscience.com/wos/author/record/",
                "http://www.webofscience.com/wos/author/record/",
                "www.webofscience.com/wos/author/record/",
            ],
            prefix: "https://www.webofscience.com/wos/author/record/"
        )
    }

    var scopusURL: URL? {
        identifierURL(
            raw: scopus,
            stripping: [
                "http://www.scopus.com/inward/authorDetails.url?authorID=",
                "https://www.scopus.com/inward/authorDetails.url?authorID=",
                "www.scopus.com/inward/authorDetails.url?authorID=",
            ],
            prefix: "http://www.scopus.com/inward/authorDetails.url?authorID="
        )
        .map { url in
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
            let authorID = components.queryItems?.first(where: { $0.name == "authorID" })?.value
            components.queryItems = [
                URLQueryItem(name: "authorID", value: authorID),
                URLQueryItem(name: "partnerID", value: "MN8TOARS"),
            ]
            return components.url ?? url
        }
    }

    var institutionWebsiteURL: URL? {
        normalizedWebLinkURL(institutionWebsite)
    }

    var linkableIdentifiers: [(label: String, value: String)] {
        [
            ("ORCID", orcid),
            ("Scopus", scopus),
            ("ResearcherID", researcherID),
        ]
        .filter { $0.1.nonEmpty != nil }
    }

    private func identifierURL(raw: String, stripping prefixes: [String], prefix: String) -> URL? {
        guard var value = raw.trimmedOrNil else { return nil }
        for candidate in prefixes where value.lowercased().hasPrefix(candidate.lowercased()) {
            value = String(value.dropFirst(candidate.count))
            break
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return URL(string: prefix + value)
    }
}

enum JournalRankingKind: String, Codable, Hashable, CaseIterable {
    case clarivateScieJIF
    case clarivateScieJCI
    case clarivateEsciJIF
    case clarivateEsciJCI
    case scimagoSJR
    case norwegianList
}

struct JournalYearMetric: Codable, Hashable, Identifiable {
    var year: Int
    var value: String
    var quartile: String

    var id: String { "\(year)-\(quartile)-\(value)" }
}

struct JournalRankingRow: Codable, Hashable, Identifiable {
    var id: String
    var kind: JournalRankingKind
    var category: String?
    var yearlyMetrics: [JournalYearMetric]

    init(id: String = UUID().uuidString, kind: JournalRankingKind, category: String? = nil, yearlyMetrics: [JournalYearMetric] = []) {
        self.id = id
        self.kind = kind
        self.category = category
        self.yearlyMetrics = yearlyMetrics.sorted { $0.year > $1.year }
    }
}

struct PublicationMetricValue {
    let value: String
    let quartile: String
    let uncertain: Bool
    let flagsUncertainty: Bool
    let kind: JournalRankingKind

    var numericValue: Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }
}

struct PublicationJournal: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var abbreviatedName: String
    var issnLTWAAbbreviatedName: String
    var issn: String
    var eissn: String
    var language: String
    var openAccess: String
    var apcCharge: String
    var reviewProcess: String
    var country: String
    var publisher: String
    var journalURL: String
    var submissionPortalURL: String
    var npiArea: String
    var establishedYear: String
    var discontinuedYear: String
    var categories: [String]
    var rankingRows: [JournalRankingRow]
    var category: String
    var subcategory: String
    var jif21: String
    var jif22: String
    var jif23: String
    var jif24: String
    var trend: String
    var reviews: String
    var briefs: String
    var studyProtocols: String
    var underReview: String
    var acceptedPublished: String
    var rejected: String
    var norwegianLevel: String
    var sjrQuartile: String
    var metricsYear: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case abbreviatedName
        case issnLTWAAbbreviatedName
        case issn
        case eissn
        case language
        case openAccess
        case apcCharge
        case reviewProcess
        case country
        case publisher
        case journalURL
        case submissionPortalURL
        case npiArea
        case establishedYear
        case discontinuedYear
        case categories
        case rankingRows
        case category
        case subcategory
        case jif21
        case jif22
        case jif23
        case jif24
        case trend
        case reviews
        case briefs
        case studyProtocols
        case underReview
        case acceptedPublished
        case rejected
        case norwegianLevel
        case sjrQuartile
        case metricsYear
    }

    init(
        id: String = UUID().uuidString,
        name: String = "",
        abbreviatedName: String = "",
        issnLTWAAbbreviatedName: String = "",
        issn: String = "",
        eissn: String = "",
        language: String = "",
        openAccess: String = "",
        apcCharge: String = "",
        reviewProcess: String = "",
        country: String = "",
        publisher: String = "",
        journalURL: String = "",
        submissionPortalURL: String = "",
        npiArea: String = "",
        establishedYear: String = "",
        discontinuedYear: String = "",
        categories: [String] = [],
        rankingRows: [JournalRankingRow] = [],
        category: String = "",
        subcategory: String = "",
        jif21: String = "",
        jif22: String = "",
        jif23: String = "",
        jif24: String = "",
        trend: String = "",
        reviews: String = "",
        briefs: String = "",
        studyProtocols: String = "",
        underReview: String = "",
        acceptedPublished: String = "",
        rejected: String = "",
        norwegianLevel: String = "",
        sjrQuartile: String = "",
        metricsYear: String = "2024"
    ) {
        self.id = id
        self.name = name
        self.abbreviatedName = abbreviatedName
        self.issnLTWAAbbreviatedName = issnLTWAAbbreviatedName
        self.issn = issn
        self.eissn = eissn
        self.language = language
        self.openAccess = openAccess
        self.apcCharge = apcCharge
        self.reviewProcess = reviewProcess
        self.country = country
        self.publisher = publisher
        self.journalURL = journalURL
        self.submissionPortalURL = submissionPortalURL
        self.npiArea = npiArea
        self.establishedYear = establishedYear
        self.discontinuedYear = discontinuedYear
        self.categories = categories
        self.rankingRows = rankingRows.sorted { $0.kind.rawValue < $1.kind.rawValue }
        self.category = category
        self.subcategory = subcategory
        self.jif21 = jif21
        self.jif22 = jif22
        self.jif23 = jif23
        self.jif24 = jif24
        self.trend = trend
        self.reviews = reviews
        self.briefs = briefs
        self.studyProtocols = studyProtocols
        self.underReview = underReview
        self.acceptedPublished = acceptedPublished
        self.rejected = rejected
        self.norwegianLevel = norwegianLevel
        self.sjrQuartile = sjrQuartile
        self.metricsYear = metricsYear
        normalize()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            abbreviatedName: try container.decodeIfPresent(String.self, forKey: .abbreviatedName) ?? "",
            issnLTWAAbbreviatedName: try container.decodeIfPresent(String.self, forKey: .issnLTWAAbbreviatedName) ?? "",
            issn: try container.decodeIfPresent(String.self, forKey: .issn) ?? "",
            eissn: try container.decodeIfPresent(String.self, forKey: .eissn) ?? "",
            language: try container.decodeIfPresent(String.self, forKey: .language) ?? "",
            openAccess: try container.decodeIfPresent(String.self, forKey: .openAccess) ?? "",
            apcCharge: try container.decodeIfPresent(String.self, forKey: .apcCharge) ?? "",
            reviewProcess: try container.decodeIfPresent(String.self, forKey: .reviewProcess) ?? "",
            country: try container.decodeIfPresent(String.self, forKey: .country) ?? "",
            publisher: try container.decodeIfPresent(String.self, forKey: .publisher) ?? "",
            journalURL: try container.decodeIfPresent(String.self, forKey: .journalURL) ?? "",
            submissionPortalURL: try container.decodeIfPresent(String.self, forKey: .submissionPortalURL) ?? "",
            npiArea: try container.decodeIfPresent(String.self, forKey: .npiArea) ?? "",
            establishedYear: try container.decodeIfPresent(String.self, forKey: .establishedYear) ?? "",
            discontinuedYear: try container.decodeIfPresent(String.self, forKey: .discontinuedYear) ?? "",
            categories: try container.decodeIfPresent([String].self, forKey: .categories) ?? [],
            rankingRows: try container.decodeIfPresent([JournalRankingRow].self, forKey: .rankingRows) ?? [],
            category: try container.decodeIfPresent(String.self, forKey: .category) ?? "",
            subcategory: try container.decodeIfPresent(String.self, forKey: .subcategory) ?? "",
            jif21: try container.decodeIfPresent(String.self, forKey: .jif21) ?? "",
            jif22: try container.decodeIfPresent(String.self, forKey: .jif22) ?? "",
            jif23: try container.decodeIfPresent(String.self, forKey: .jif23) ?? "",
            jif24: try container.decodeIfPresent(String.self, forKey: .jif24) ?? "",
            trend: try container.decodeIfPresent(String.self, forKey: .trend) ?? "",
            reviews: try container.decodeIfPresent(String.self, forKey: .reviews) ?? "",
            briefs: try container.decodeIfPresent(String.self, forKey: .briefs) ?? "",
            studyProtocols: try container.decodeIfPresent(String.self, forKey: .studyProtocols) ?? "",
            underReview: try container.decodeIfPresent(String.self, forKey: .underReview) ?? "",
            acceptedPublished: try container.decodeIfPresent(String.self, forKey: .acceptedPublished) ?? "",
            rejected: try container.decodeIfPresent(String.self, forKey: .rejected) ?? "",
            norwegianLevel: try container.decodeIfPresent(String.self, forKey: .norwegianLevel) ?? "",
            sjrQuartile: try container.decodeIfPresent(String.self, forKey: .sjrQuartile) ?? "",
            metricsYear: try container.decodeIfPresent(String.self, forKey: .metricsYear) ?? "2024"
        )
    }

    mutating func normalize() {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        abbreviatedName = abbreviatedName.trimmingCharacters(in: .whitespacesAndNewlines)
        issnLTWAAbbreviatedName = issnLTWAAbbreviatedName.trimmingCharacters(in: .whitespacesAndNewlines)
        issn = normalizedJournalISSN(issn)
        eissn = normalizedJournalISSN(eissn)
        language = language.trimmingCharacters(in: .whitespacesAndNewlines)
        openAccess = openAccess.trimmingCharacters(in: .whitespacesAndNewlines)
        apcCharge = apcCharge.trimmingCharacters(in: .whitespacesAndNewlines)
        reviewProcess = reviewProcess.trimmingCharacters(in: .whitespacesAndNewlines)
        country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        publisher = publisher.trimmingCharacters(in: .whitespacesAndNewlines)
        journalURL = journalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        submissionPortalURL = submissionPortalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        npiArea = npiArea.trimmingCharacters(in: .whitespacesAndNewlines)
        establishedYear = establishedYear.trimmingCharacters(in: .whitespacesAndNewlines)
        discontinuedYear = discontinuedYear.trimmingCharacters(in: .whitespacesAndNewlines)
        category = normalizedJournalCategory(category) ?? ""
        subcategory = normalizedJournalCategory(subcategory) ?? ""
        categories = Array(
            Set(categories.compactMap(normalizedJournalCategory))
        )
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if category.isEmpty {
            category = categories.first ?? ""
        } else if !categories.contains(category) {
            categories.insert(category, at: 0)
        }
        rankingRows = mergedRankingRows(rankingRows)
        jif21 = jif21.trimmingCharacters(in: .whitespacesAndNewlines)
        jif22 = jif22.trimmingCharacters(in: .whitespacesAndNewlines)
        jif23 = jif23.trimmingCharacters(in: .whitespacesAndNewlines)
        jif24 = jif24.trimmingCharacters(in: .whitespacesAndNewlines)
        trend = trend.trimmingCharacters(in: .whitespacesAndNewlines)
        reviews = reviews.trimmingCharacters(in: .whitespacesAndNewlines)
        briefs = briefs.trimmingCharacters(in: .whitespacesAndNewlines)
        studyProtocols = studyProtocols.trimmingCharacters(in: .whitespacesAndNewlines)
        underReview = underReview.trimmingCharacters(in: .whitespacesAndNewlines)
        acceptedPublished = acceptedPublished.trimmingCharacters(in: .whitespacesAndNewlines)
        rejected = rejected.trimmingCharacters(in: .whitespacesAndNewlines)
        norwegianLevel = norwegianLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        sjrQuartile = sjrQuartile.trimmingCharacters(in: .whitespacesAndNewlines)
        metricsYear = metricsYear.trimmingCharacters(in: .whitespacesAndNewlines)
        if submissionPortalURL.isEmpty, let defaultPortal = Self.defaultSubmissionPortalURL(for: name) {
            submissionPortalURL = defaultPortal
        }
    }

    private func mergedRankingRows(_ rows: [JournalRankingRow]) -> [JournalRankingRow] {
        let grouped = Dictionary(grouping: rows) { row in
            "\(row.kind.rawValue)|\(normalizedJournalCategory(row.category) ?? "")"
        }
        return grouped.values.compactMap { group -> JournalRankingRow? in
            guard var base = group.first else { return nil }
            var metricsByYear: [Int: JournalYearMetric] = [:]
            for row in group {
                for metric in row.yearlyMetrics {
                    let existing = metricsByYear[metric.year]
                    if existing == nil || quartileRank(metric.quartile) < quartileRank(existing?.quartile ?? "") {
                        metricsByYear[metric.year] = JournalYearMetric(
                            year: metric.year,
                            value: metric.value.trimmingCharacters(in: .whitespacesAndNewlines),
                            quartile: metric.quartile.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                }
            }
            base.category = normalizedJournalCategory(base.category)
            base.yearlyMetrics = metricsByYear.values.sorted { $0.year > $1.year }
            return base
        }
        .sorted { ($0.kind.rawValue, $0.category ?? "") < ($1.kind.rawValue, $1.category ?? "") }
    }

    private func normalizedJournalISSN(_ raw: String) -> String {
        let cleaned = raw
            .uppercased()
            .replacingOccurrences(of: "[^0-9X]", with: "", options: .regularExpression)
        guard cleaned.count == 8 else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "\(cleaned.prefix(4))-\(cleaned.suffix(4))"
    }

    private func quartileRank(_ value: String) -> Int {
        switch value {
        case "Q1":
            1
        case "Q2":
            2
        case "Q3":
            3
        case "Q4":
            4
        default:
            99
        }
    }

    /// The newest year that has a registered value for one of `kinds`.
    func latestRegisteredYear(for kinds: [JournalRankingKind]) -> Int? {
        rankingRows
            .filter { kinds.contains($0.kind) }
            .flatMap(\.yearlyMetrics)
            .filter { $0.value.nonEmpty != nil || $0.quartile.nonEmpty != nil }
            .map(\.year)
            .max()
    }

    /// The newest year with any registered metric (including the older JIF
    /// fields). Replaces the stored `metricsYear` as a label for latest values.
    var latestRegisteredMetricsYear: Int? {
        let legacyJIFYears = [(2021, jif21), (2022, jif22), (2023, jif23), (2024, jif24)]
            .filter { $0.1.nonEmpty != nil }
            .map { $0.0 }
        let rankingYears = latestRegisteredYear(for: JournalRankingKind.allCases).map { [$0] } ?? []
        return (legacyJIFYears + rankingYears).max()
    }

    var allISSNs: Set<String> {
        Set(
            [issn, eissn]
                .flatMap { $0.components(separatedBy: ",") }
                .map { $0.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    var latestImpactFactor: String {
        latestMetric(for: [.clarivateScieJIF, .clarivateEsciJIF])?.value
            ?? roundedJIF([jif24, jif23, jif22, jif21].first(where: { $0.nonEmpty != nil }) ?? "")
    }

    var latestImpactFactorValue: Double {
        Double(latestImpactFactor.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var latestJCI: String {
        latestMetric(for: [.clarivateScieJCI, .clarivateEsciJCI])?.value ?? ""
    }

    var latestJCIValue: Double {
        Double(latestJCI.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var latestSJR: String {
        latestMetric(for: [.scimagoSJR])?.value ?? ""
    }

    var latestSJRValue: Double {
        Double(latestSJR.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var latestNorwegianLevel: String {
        latestMetric(for: [.norwegianList])?.value ?? norwegianLevel
    }

    var latestNorwegianLevelValue: Double {
        Self.norwegianRankValue(for: latestNorwegianLevel)
    }

    var journalHomeURL: URL? {
        normalizedWebLinkURL(journalURL)
    }

    var submissionPortalLinkURL: URL? {
        normalizedWebLinkURL(submissionPortalURL)
    }

    private static func defaultSubmissionPortalURL(for name: String) -> String? {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "plos one":
            return "https://www.editorialmanager.com/pone/default.aspx"
        case "european heart journal":
            return "https://www.editorialmanager.com/eurheartj/default2.aspx"
        case "jama cardiology":
            return "https://manuscripts.jamacardio.com/cgi-bin/main.plex"
        default:
            return nil
        }
    }

    func metric(for kind: JournalRankingKind, publicationYear: Int?) -> PublicationMetricValue? {
        let relevantRows = rankingRows.filter { $0.kind == kind }
        guard !relevantRows.isEmpty else { return nil }
        let chosenMetric = relevantRows.compactMap { row -> PublicationMetricValue? in
            metric(in: row, publicationYear: publicationYear)
        }.first
        return chosenMetric
    }

    func preferredMetric(for kinds: [JournalRankingKind], publicationYear: Int?) -> PublicationMetricValue? {
        for kind in kinds {
            if let metric = metric(for: kind, publicationYear: publicationYear) {
                return metric
            }
        }
        return nil
    }

    private func latestMetric(for preferredKinds: [JournalRankingKind]) -> PublicationMetricValue? {
        for kind in preferredKinds {
            if let metric = rankingRows.filter({ $0.kind == kind }).compactMap({ $0.yearlyMetrics.first }).first {
                return PublicationMetricValue(value: roundedJIF(metric.value), quartile: metric.quartile, uncertain: false, flagsUncertainty: false, kind: kind)
            }
        }
        return nil
    }

    private func metric(in row: JournalRankingRow, publicationYear: Int?) -> PublicationMetricValue? {
        guard !row.yearlyMetrics.isEmpty else { return nil }
        if let publicationYear, let exact = row.yearlyMetrics.first(where: { $0.year == publicationYear }) {
            return PublicationMetricValue(value: roundedValue(exact.value, for: row.kind), quartile: exact.quartile, uncertain: false, flagsUncertainty: false, kind: row.kind)
        }
        if let latest = row.yearlyMetrics.first {
            let isUncertain = publicationYear != nil && publicationYear != latest.year
            let shouldFlag = isUncertain && (row.kind == .clarivateEsciJIF || row.kind == .clarivateEsciJCI)
            return PublicationMetricValue(value: roundedValue(latest.value, for: row.kind), quartile: latest.quartile, uncertain: isUncertain, flagsUncertainty: shouldFlag, kind: row.kind)
        }
        return nil
    }

    func rankingSnapshot(for publicationYear: Int?) -> PublicationRankingSnapshot {
        // JIF values live both in the legacy jif21-jif24 fields and in
        // rankingRows (where bundled metric merges land newer years);
        // rankingRows wins for years both carry.
        var jifValuesByYear: [Int: String] = [:]
        for (year, value) in [(2021, jif21), (2022, jif22), (2023, jif23), (2024, jif24)]
        where value.nonEmpty != nil {
            jifValuesByYear[year] = value
        }
        for row in rankingRows where row.kind == .clarivateScieJIF || row.kind == .clarivateEsciJIF {
            for metric in row.yearlyMetrics where metric.value.nonEmpty != nil {
                jifValuesByYear[metric.year] = metric.value
            }
        }
        let jifByYear: [(Int, String)] = jifValuesByYear
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }

        // The publication year's value when one is registered, otherwise the
        // newest registered year, chosen per metric. No fixed year is assumed.
        let norwegianByYear = rankingRows
            .filter { $0.kind == .norwegianList }
            .flatMap(\.yearlyMetrics)
            .filter { $0.value.nonEmpty != nil }
            .sorted { $0.year > $1.year }
        let exactNorwegian = publicationYear.flatMap { year in
            norwegianByYear.first(where: { $0.year == year })?.value
        }
        let fallbackNorwegian = norwegianByYear.first?.value
        // referenceYear must be the year of the value actually chosen, so a
        // fallback value is flagged as uncertain.
        let exactJIF = publicationYear.flatMap { year in
            jifByYear.first(where: { $0.0 == year })
        }
        let chosenEntry = exactJIF ?? jifByYear.first
        let chosenJIF = roundedJIF(chosenEntry?.1 ?? "")
        let referenceYear = chosenEntry?.0 ?? publicationYear
        let uncertain = publicationYear != nil && referenceYear != publicationYear

        return PublicationRankingSnapshot(
            norwegian: exactNorwegian ?? fallbackNorwegian ?? norwegianLevel,
            sjr: sjrQuartile,
            jif: chosenJIF,
            uncertain: uncertain
        )
    }

    private func roundedValue(_ raw: String, for kind: JournalRankingKind) -> String {
        switch kind {
        case .clarivateScieJIF, .clarivateEsciJIF, .clarivateScieJCI, .clarivateEsciJCI, .scimagoSJR:
            return roundedJIF(raw)
        case .norwegianList:
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return trimmed == "X" ? "X" : trimmed
        }
    }

    static func norwegianRankValue(for raw: String) -> Double {
        let cleaned = raw
            .replacingOccurrences(of: " (uncertain)", with: "")
            .replacingOccurrences(of: " (osäkert)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if cleaned == "X" {
            return -1
        }
        return Double(cleaned.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func roundedJIF(_ raw: String) -> String {
        guard let value = Double(raw.replacingOccurrences(of: ",", with: ".")) else { return raw }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? raw
    }
}

struct PublicationAttempt: Codable, Hashable, Identifiable {
    var id: String
    var journal: String
    /// F13: the journal by id, when it is in the register.
    var journalID: String?
    var submittedOn: String?
    var rejectedOn: String?

    init(id: String = UUID().uuidString, journal: String = "", journalID: String? = nil, submittedOn: String? = nil, rejectedOn: String? = nil) {
        self.id = id
        self.journal = journal
        self.journalID = journalID
        self.submittedOn = submittedOn
        self.rejectedOn = rejectedOn
    }

    var dedupeKey: String {
        [journal.trimmingCharacters(in: .whitespacesAndNewlines), submittedOn ?? "", rejectedOn ?? ""].joined(separator: "|")
    }
}

struct PublicationStatusEntry: Codable, Hashable, Identifiable {
    var id: String
    var status: String
    var journal: String
    var date: String?

    init(id: String = UUID().uuidString, status: String = PublicationStatus.inPreparation.rawValue, journal: String = "", date: String? = nil) {
        self.id = id
        self.status = status
        self.journal = journal
        self.date = date
    }

    mutating func normalize() {
        status = PublicationStatus.normalizedRawValue(status)
        journal = journal.trimmingCharacters(in: .whitespacesAndNewlines)
        date = date?.trimmedOrNil
    }

    var isEmpty: Bool {
        status.nonEmpty == nil && journal.nonEmpty == nil && date?.nonEmpty == nil
    }

    var dedupeKey: String {
        [PublicationStatus.normalizedRawValue(status), journal.trimmingCharacters(in: .whitespacesAndNewlines), date ?? ""].joined(separator: "|")
    }
}

struct PublicationCitationYear: Codable, Hashable, Identifiable {
    var id: String
    var year: String
    var count: String
    var selfCitationCount: String

    enum CodingKeys: String, CodingKey {
        case id
        case year
        case count
        case selfCitationCount
    }

    init(id: String = UUID().uuidString, year: String = "", count: String = "", selfCitationCount: String = "") {
        self.id = id
        self.year = year
        self.count = count
        self.selfCitationCount = selfCitationCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            year: try container.decodeIfPresent(String.self, forKey: .year) ?? "",
            count: try container.decodeIfPresent(String.self, forKey: .count) ?? "",
            selfCitationCount: try container.decodeIfPresent(String.self, forKey: .selfCitationCount) ?? ""
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(year, forKey: .year)
        try container.encode(count, forKey: .count)
        if selfCitationCount.nonEmpty != nil {
            try container.encode(selfCitationCount, forKey: .selfCitationCount)
        }
    }

    mutating func normalize() {
        year = year.trimmingCharacters(in: .whitespacesAndNewlines)
        count = count.trimmingCharacters(in: .whitespacesAndNewlines)
        selfCitationCount = selfCitationCount.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        year.nonEmpty == nil && count.nonEmpty == nil && selfCitationCount.nonEmpty == nil
    }

    var yearValue: Int {
        Int(year) ?? 0
    }

    var countValue: Int {
        Int(count) ?? 0
    }

    var selfCitationCountValue: Int {
        Int(selfCitationCount) ?? 0
    }

    var totalCitationCountValue: Int {
        countValue + selfCitationCountValue
    }
}

enum PublicationWorkflowStatus: String, Codable, Hashable, CaseIterable, Identifiable {
    case dataCollection = "Data collection"
    case dataProcessing = "Data processing"
    case manuscriptWriting = "Manuscript writing"
    case withCoauthors = "With co-authors"

    var id: String { rawValue }

    var sortRank: Int {
        switch self {
        case .dataCollection:
            return 0
        case .dataProcessing:
            return 1
        case .manuscriptWriting:
            return 2
        case .withCoauthors:
            return 3
        }
    }
}

func normalizedCreditAuthorName(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
}

func normalizedPublicationAuthorNamePart(_ value: String) -> String {
    value
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func normalizedPublicationAuthorNameVariants(
    _ variants: [String],
    excluding excludedNames: [String] = []
) -> [String] {
    let excludedKeys = Set(excludedNames.map(normalizedPublicationAuthorNameVariantKey).filter { !$0.isEmpty })
    var seenKeys = Set<String>()
    var normalizedVariants: [String] = []

    for variant in variants {
        let cleaned = variant
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalizedPublicationAuthorNameVariantKey(cleaned)
        guard !cleaned.isEmpty,
              !excludedKeys.contains(key),
              seenKeys.insert(key).inserted else {
            continue
        }
        normalizedVariants.append(cleaned)
    }

    return normalizedVariants
}

func normalizedPublicationAuthorNameVariantRows(
    _ variants: [PublicationAuthorNameVariant],
    currentFirstName: String = "",
    currentLastName: String = "",
    excluding excludedNames: [String] = [],
    fillsMissingPartsFromCurrentName: Bool = false
) -> [PublicationAuthorNameVariant] {
    let currentFirstName = normalizedPublicationAuthorNamePart(currentFirstName)
    let currentLastName = normalizedPublicationAuthorNamePart(currentLastName)
    let excludedKeys = Set(excludedNames.map(normalizedPublicationAuthorNameVariantKey).filter { !$0.isEmpty })
    var seenKeys = Set<String>()
    var normalizedVariants: [PublicationAuthorNameVariant] = []

    for variant in variants {
        var cleaned = variant
        cleaned.normalize()
        if fillsMissingPartsFromCurrentName, cleaned.firstName.isEmpty {
            cleaned.firstName = currentFirstName
        }
        if fillsMissingPartsFromCurrentName, cleaned.lastName.isEmpty {
            cleaned.lastName = currentLastName
        }
        let key = normalizedPublicationAuthorNameVariantKey(cleaned.displayName)
        guard !cleaned.isEmpty,
              !key.isEmpty,
              !excludedKeys.contains(key),
              seenKeys.insert(key).inserted else {
            continue
        }
        normalizedVariants.append(cleaned)
    }

    return normalizedVariants
}

func parsedPublicationAuthorNameVariants(_ raw: String) -> [String] {
    let variants = raw
        .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return normalizedPublicationAuthorNameVariants(variants)
}

func publicationAuthorNameVariantRows(from names: [String]) -> [PublicationAuthorNameVariant] {
    names
        .compactMap(\.trimmedOrNil)
        .map(publicationAuthorNameVariantRow(from:))
}

private func publicationAuthorNameVariantRow(from fullName: String) -> PublicationAuthorNameVariant {
    let parts = fullName.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard parts.count > 1 else {
        return PublicationAuthorNameVariant(firstName: fullName, lastName: "")
    }

    let particles = Set(["af", "al", "da", "de", "del", "der", "di", "du", "la", "le", "van", "von"])
    var lastNameParts = [parts.last ?? ""]
    var index = parts.count - 2
    while index >= 0, particles.contains(parts[index].lowercased()) {
        lastNameParts.insert(parts[index], at: 0)
        index -= 1
    }

    let firstNameParts = Array(parts.prefix(index + 1))
    return PublicationAuthorNameVariant(
        firstName: firstNameParts.joined(separator: " "),
        lastName: lastNameParts.joined(separator: " ")
    )
}

func normalizedPublicationAuthorNameVariantKey(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

enum PublicationCreditRole: String, Codable, Hashable, CaseIterable, Identifiable {
    case conceptualization = "Conceptualization"
    case dataCuration = "Data curation"
    case formalAnalysis = "Formal analysis"
    case fundingAcquisition = "Funding acquisition"
    case investigation = "Investigation"
    case methodology = "Methodology"
    case projectAdministration = "Project administration"
    case resources = "Resources"
    case software = "Software"
    case supervision = "Supervision"
    case validation = "Validation"
    case visualization = "Visualization"
    case writingOriginalDraft = "Writing - original draft"
    case writingReviewEditing = "Writing - review & editing"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .conceptualization:
            return "Conceptualization"
        case .dataCuration:
            return "Data curation"
        case .formalAnalysis:
            return "Formal analysis"
        case .fundingAcquisition:
            return "Funding acq."
        case .investigation:
            return "Investigation"
        case .methodology:
            return "Methodology"
        case .projectAdministration:
            return "Project admin."
        case .resources:
            return "Resources"
        case .software:
            return "Software"
        case .supervision:
            return "Supervision"
        case .validation:
            return "Validation"
        case .visualization:
            return "Visualization"
        case .writingOriginalDraft:
            return "Writing - original"
        case .writingReviewEditing:
            return "Writing - review"
        }
    }

    var definition: String {
        switch self {
        case .conceptualization:
            return "Ideas; formulation or evolution of overarching research goals and aims."
        case .dataCuration:
            return "Management activities to annotate (produce metadata), scrub data and maintain research data (including software code, where it is necessary for interpreting the data itself) for initial use and later re-use."
        case .formalAnalysis:
            return "Application of statistical, mathematical, computational, or other formal techniques to analyse or synthesize study data."
        case .fundingAcquisition:
            return "Acquisition of the financial support for the project leading to this publication."
        case .investigation:
            return "Conducting a research and investigation process, specifically performing the experiments, or data/evidence collection."
        case .methodology:
            return "Development or design of methodology; creation of models."
        case .projectAdministration:
            return "Management and coordination responsibility for the research activity planning and execution."
        case .resources:
            return "Provision of study materials, reagents, materials, patients, laboratory samples, animals, instrumentation, computing resources, or other analysis tools."
        case .software:
            return "Programming, software development; designing computer programs; implementation of the computer code and supporting algorithms; testing of existing code components."
        case .supervision:
            return "Oversight and leadership responsibility for the research activity planning and execution, including mentorship external to the core team."
        case .validation:
            return "Verification, whether as a part of the activity or separate, of the overall replication/reproducibility of results/experiments and other research outputs."
        case .visualization:
            return "Preparation, creation and/or presentation of the published work, specifically visualization/data presentation."
        case .writingOriginalDraft:
            return "Preparation, creation and/or presentation of the published work, specifically writing the initial draft (including substantive translation)."
        case .writingReviewEditing:
            return "Preparation, creation and/or presentation of the published work by those from the original research group, specifically critical review, commentary or revision, including pre- or post-publication stages."
        }
    }

    var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

enum PublicationCreditRoleContribution: String, Codable, Hashable, CaseIterable, Identifiable {
    case lead
    case equal
    case supporting

    var id: String { rawValue }

    var exportValue: String { rawValue }

    var statementValue: String {
        switch self {
        case .lead:
            return "lead"
        case .equal:
            return "equal"
        case .supporting:
            return "sup."
        }
    }

    var sortPriority: Int {
        switch self {
        case .lead:
            0
        case .equal:
            1
        case .supporting:
            2
        }
    }
}

struct PublicationCreditRoleContributionEntry: Codable, Hashable {
    var role: PublicationCreditRole
    var contribution: PublicationCreditRoleContribution
}

struct PublicationCreditAssignment: Codable, Hashable, Identifiable {
    var authorName: String
    var roles: [PublicationCreditRole]
    var roleContributions: [PublicationCreditRoleContributionEntry]

    var id: String { authorName }
    var dedupeKey: String { normalizedCreditAuthorName(authorName) }

    enum CodingKeys: String, CodingKey {
        case authorName
        case roles
        case roleContributions
    }

    init(
        authorName: String = "",
        roles: [PublicationCreditRole] = [],
        roleContributions: [PublicationCreditRoleContributionEntry] = []
    ) {
        self.authorName = authorName
        self.roles = roles
        self.roleContributions = roleContributions
        normalize()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            authorName: try container.decodeIfPresent(String.self, forKey: .authorName) ?? "",
            roles: try container.decodeIfPresent([PublicationCreditRole].self, forKey: .roles) ?? [],
            roleContributions: try container.decodeIfPresent([PublicationCreditRoleContributionEntry].self, forKey: .roleContributions) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(authorName, forKey: .authorName)
        try container.encode(roles, forKey: .roles)
        try container.encode(roleContributions, forKey: .roleContributions)
    }

    mutating func normalize(validAuthorNames: Set<String>? = nil) {
        authorName = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedNames = validAuthorNames?.map(normalizedCreditAuthorName)
        if let allowedNames, !allowedNames.contains(normalizedCreditAuthorName(authorName)) {
            authorName = ""
        }
        roles = Array(Set(roles)).sorted { $0.sortIndex < $1.sortIndex }
        let allowedRoles = Set(roles)
        roleContributions = roleContributions
            .filter { allowedRoles.contains($0.role) }
            .uniqued(by: \.role)
            .sorted { lhs, rhs in
                lhs.role.sortIndex < rhs.role.sortIndex
            }
    }

    var isEmpty: Bool {
        authorName.isEmpty || roles.isEmpty
    }
}

struct PublicationTaskItem: Codable, Hashable, Identifiable {
    var id: String
    var createdOn: String
    var updatedOn: String
    var deadline: String
    var comment: String
    var note: String
    var participantNames: [String]
    /// Id links to the researchers in `participantNames`; the names stay as display text.
    var participantAuthorIDs: [String]
    var projectID: String?
    var publicationID: String?
    var applicationID: String?
    var completedOn: String?
    /// Meeting agenda; edited alongside the protocol in the calendar editors.
    var agendaText: String
    /// Meeting minutes; aggregated into the linked records' protocol documents.
    var protocolText: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdOn
        case updatedOn
        case deadline
        case comment
        case note
        case participantNames
        case participantAuthorIDs
        case projectID
        case publicationID
        case applicationID
        case completedOn
        case agendaText
        case protocolText
    }

    init(
        id: String = UUID().uuidString,
        createdOn: String = "",
        updatedOn: String = "",
        deadline: String = "",
        comment: String = "",
        note: String = "",
        participantNames: [String] = [],
        participantAuthorIDs: [String] = [],
        projectID: String? = nil,
        publicationID: String? = nil,
        applicationID: String? = nil,
        completedOn: String? = nil,
        agendaText: String = "",
        protocolText: String = ""
    ) {
        self.id = id
        self.createdOn = createdOn
        self.updatedOn = updatedOn
        self.deadline = deadline
        self.comment = comment
        self.note = note
        self.participantNames = participantNames
        self.participantAuthorIDs = participantAuthorIDs
        self.projectID = projectID
        self.publicationID = publicationID
        self.applicationID = applicationID
        self.completedOn = completedOn
        self.agendaText = agendaText
        self.protocolText = protocolText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        createdOn = try container.decodeIfPresent(String.self, forKey: .createdOn) ?? ""
        updatedOn = try container.decodeIfPresent(String.self, forKey: .updatedOn) ?? ""
        deadline = try container.decodeIfPresent(String.self, forKey: .deadline) ?? ""
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        participantNames = try container.decodeIfPresent([String].self, forKey: .participantNames) ?? []
        participantAuthorIDs = try container.decodeIfPresent([String].self, forKey: .participantAuthorIDs) ?? []
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        publicationID = try container.decodeIfPresent(String.self, forKey: .publicationID)
        applicationID = try container.decodeIfPresent(String.self, forKey: .applicationID)
        completedOn = try container.decodeIfPresent(String.self, forKey: .completedOn)
        agendaText = try container.decodeIfPresent(String.self, forKey: .agendaText) ?? ""
        protocolText = try container.decodeIfPresent(String.self, forKey: .protocolText) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdOn, forKey: .createdOn)
        try container.encode(updatedOn, forKey: .updatedOn)
        try container.encode(deadline, forKey: .deadline)
        try container.encode(comment, forKey: .comment)
        try container.encode(note, forKey: .note)
        try container.encode(participantNames, forKey: .participantNames)
        if !participantAuthorIDs.isEmpty {
            try container.encode(participantAuthorIDs, forKey: .participantAuthorIDs)
        }
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(publicationID, forKey: .publicationID)
        try container.encodeIfPresent(applicationID, forKey: .applicationID)
        try container.encodeIfPresent(completedOn, forKey: .completedOn)
        try container.encode(agendaText, forKey: .agendaText)
        try container.encode(protocolText, forKey: .protocolText)
    }

    mutating func normalize() {
        createdOn = DateParsers.canonicalizedDayInput(createdOn)
        updatedOn = DateParsers.canonicalizedDayInput(updatedOn)
        deadline = DateParsers.canonicalizedDayInput(deadline)
        comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        participantNames = Array(
            NSOrderedSet(array: participantNames.compactMap(\.trimmedOrNil))
        ) as? [String] ?? participantNames.compactMap(\.trimmedOrNil)
        participantAuthorIDs = Array(
            NSOrderedSet(array: participantAuthorIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? participantAuthorIDs.compactMap(\.trimmedOrNil)
        projectID = projectID?.trimmedOrNil
        publicationID = publicationID?.trimmedOrNil
        applicationID = applicationID?.trimmedOrNil
        completedOn = completedOn
            .map(DateParsers.canonicalizedDayInput(_:))
            .flatMap(\.trimmedOrNil)
        agendaText = agendaText.trimmingCharacters(in: .whitespacesAndNewlines)
        protocolText = protocolText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isCompleted: Bool {
        completedOn?.trimmedOrNil != nil
    }

    var isEmpty: Bool {
        deadline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && participantNames.isEmpty
            && projectID?.trimmedOrNil == nil
            && publicationID?.trimmedOrNil == nil
            && applicationID?.trimmedOrNil == nil
            && agendaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && protocolText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

func normalizedPublicationTaskItems(_ tasks: [PublicationTaskItem]) -> [PublicationTaskItem] {
    let normalized = tasks
        .map {
            var copy = $0
            copy.normalize()
            return copy
        }
        .filter { !$0.isEmpty }

    let active = normalized.filter { !$0.isCompleted }
    let completed = normalized.filter { $0.isCompleted }
    return active + completed + [PublicationTaskItem()]
}

struct PublicationRecord: Codable, Hashable, Identifiable {
    var id: String
    var projectID: String?
    var number: String
    var projectName: String?
    var title: String
    var journal: String
    /// F13: the journal by id; `journal` is its name, kept for display and for
    /// journals that are not in the register.
    var journalID: String?
    var status: String
    var statusDate: String?
    var doi: String
    var epubDate: String
    var pmid: String
    var volume: String
    var issue: String
    var pageRange: String
    var articleNumber: String
    var year: String
    var position: String
    var independence: String
    var geography: String
    var phdStage: String
    var publicationType: String
    var reviewRegistrationRegistry: String
    var reviewRegistrationID: String
    var reviewRegistrationDate: String
    var isPeerReviewed: Bool
    var citations: String
    var norwegianCurrent: String
    var norwegian2025: String
    var sjrCurrent: String
    var sjr2024: String
    var jifCurrent: String
    var jifQuartileCurrent: String
    var jif2024: String
    var category: String
    var authorNames: [String]
    /// Id links to the researchers in `authorNames`; the names stay as display text.
    var authorIDs: [String]
    var sharedFirstAuthorship: Bool
    var sharedLastAuthorship: Bool
    var correspondingAuthorName: String?
    /// Id link to the researcher in `correspondingAuthorName`.
    var correspondingAuthorID: String?
    var citationYears: [PublicationCitationYear]
    var statusTimeline: [PublicationStatusEntry]
    var currentSubmissionDate: String?
    var previousAttempts: [PublicationAttempt]
    var workflowStatus: PublicationWorkflowStatus?
    var workflowStatusDate: String?
    var publicationTasks: [PublicationTaskItem]
    var creditRoleAssignments: [PublicationCreditAssignment]
    var finalPDFFilename: String?
    var finalPDFPath: String?
    var isEditingLocked: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case projectID
        case number
        case projectName
        case title
        case journal
        case journalID
        case status
        case statusDate
        case doi
        case epubDate
        case pmid
        case volume
        case issue
        case pageRange
        case articleNumber
        case year
        case position
        case independence
        case geography
        case phdStage
        case publicationType
        case reviewRegistrationRegistry
        case reviewRegistrationID
        case reviewRegistrationDate
        case isPeerReviewed
        case citations
        case norwegianCurrent
        case norwegian2025
        case sjrCurrent
        case sjr2024
        case jifCurrent
        case jifQuartileCurrent
        case jif2024
        case category
        case authorNames
        case authorIDs
        case sharedFirstAuthorship
        case sharedLastAuthorship
        case correspondingAuthorName
        case correspondingAuthorID
        case authors
        case citationYears
        case statusTimeline
        case currentSubmissionDate
        case previousAttempts
        case workflowStatus
        case workflowStatusDate
        case publicationTasks
        case creditRoleAssignments
        case finalPDFFilename
        case finalPDFPath
        case isEditingLocked
        case originalPoints
        case reviewPoints
        case protocolPoints
        case sumPoints
    }

    init(
        id: String = UUID().uuidString,
        projectID: String? = nil,
        number: String = "",
        projectName: String? = nil,
        title: String = "",
        journal: String = "",
        journalID: String? = nil,
        status: String = PublicationStatus.inPreparation.rawValue,
        statusDate: String? = nil,
        doi: String = "",
        epubDate: String = "",
        pmid: String = "",
        volume: String = "",
        issue: String = "",
        pageRange: String = "",
        articleNumber: String = "",
        year: String = "",
        position: String = "",
        independence: String = "",
        geography: String = "",
        phdStage: String = "",
        publicationType: String = "",
        reviewRegistrationRegistry: String = "",
        reviewRegistrationID: String = "",
        reviewRegistrationDate: String = "",
        isPeerReviewed: Bool = true,
        citations: String = "",
        norwegianCurrent: String = "",
        norwegian2025: String = "",
        sjrCurrent: String = "",
        sjr2024: String = "",
        jifCurrent: String = "",
        jifQuartileCurrent: String = "",
        jif2024: String = "",
        category: String = "",
        authorNames: [String] = [],
        authorIDs: [String] = [],
        sharedFirstAuthorship: Bool = false,
        sharedLastAuthorship: Bool = false,
        correspondingAuthorName: String? = nil,
        correspondingAuthorID: String? = nil,
        citationYears: [PublicationCitationYear] = [],
        statusTimeline: [PublicationStatusEntry] = [],
        currentSubmissionDate: String? = nil,
        previousAttempts: [PublicationAttempt] = [],
        workflowStatus: PublicationWorkflowStatus? = nil,
        workflowStatusDate: String? = nil,
        publicationTasks: [PublicationTaskItem] = [],
        creditRoleAssignments: [PublicationCreditAssignment] = [],
        finalPDFFilename: String? = nil,
        finalPDFPath: String? = nil,
        isEditingLocked: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.number = number
        self.projectName = projectName
        self.title = title
        self.journal = journal
        self.journalID = journalID
        self.status = status
        self.statusDate = statusDate
        self.doi = doi
        self.epubDate = epubDate
        self.pmid = pmid
        self.volume = volume
        self.issue = issue
        self.pageRange = pageRange
        self.articleNumber = articleNumber
        self.year = year
        self.position = position
        self.independence = independence
        self.geography = geography
        self.phdStage = phdStage
        self.publicationType = publicationType
        self.reviewRegistrationRegistry = reviewRegistrationRegistry
        self.reviewRegistrationID = reviewRegistrationID
        self.reviewRegistrationDate = reviewRegistrationDate
        self.isPeerReviewed = isPeerReviewed
        self.citations = citations
        self.norwegianCurrent = norwegianCurrent
        self.norwegian2025 = norwegian2025
        self.sjrCurrent = sjrCurrent
        self.sjr2024 = sjr2024
        self.jifCurrent = jifCurrent
        self.jifQuartileCurrent = jifQuartileCurrent
        self.jif2024 = jif2024
        self.category = category
        self.authorNames = authorNames
        self.authorIDs = authorIDs
        self.sharedFirstAuthorship = sharedFirstAuthorship
        self.sharedLastAuthorship = sharedLastAuthorship
        self.correspondingAuthorName = correspondingAuthorName
        self.correspondingAuthorID = correspondingAuthorID
        self.citationYears = citationYears
        self.statusTimeline = statusTimeline
        self.currentSubmissionDate = currentSubmissionDate
        self.previousAttempts = previousAttempts
        self.workflowStatus = workflowStatus
        self.workflowStatusDate = workflowStatusDate
        self.publicationTasks = publicationTasks
        self.creditRoleAssignments = creditRoleAssignments
        self.finalPDFFilename = finalPDFFilename
        self.finalPDFPath = finalPDFPath
        self.isEditingLocked = isEditingLocked
        normalize()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let norwegianCurrent = try container.decodeIfPresent(String.self, forKey: .norwegianCurrent)
            ?? container.decodeIfPresent(String.self, forKey: .norwegian2025)
            ?? ""
        let sjrCurrent = try container.decodeIfPresent(String.self, forKey: .sjrCurrent)
            ?? container.decodeIfPresent(String.self, forKey: .sjr2024)
            ?? ""
        let jifCurrent = try container.decodeIfPresent(String.self, forKey: .jifCurrent)
            ?? container.decodeIfPresent(String.self, forKey: .jif2024)
            ?? ""
        let authorNames = try container.decodeIfPresent([String].self, forKey: .authorNames)
            ?? container.decodeIfPresent([String].self, forKey: .authors)
            ?? []
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            projectID: try container.decodeIfPresent(String.self, forKey: .projectID),
            number: try container.decodeIfPresent(String.self, forKey: .number) ?? "",
            projectName: try container.decodeIfPresent(String.self, forKey: .projectName),
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            journal: try container.decodeIfPresent(String.self, forKey: .journal) ?? "",
            journalID: try container.decodeIfPresent(String.self, forKey: .journalID),
            status: try container.decodeIfPresent(String.self, forKey: .status) ?? PublicationStatus.inPreparation.rawValue,
            statusDate: try container.decodeIfPresent(String.self, forKey: .statusDate),
            doi: try container.decodeIfPresent(String.self, forKey: .doi) ?? "",
            epubDate: try container.decodeIfPresent(String.self, forKey: .epubDate) ?? "",
            pmid: try container.decodeIfPresent(String.self, forKey: .pmid) ?? "",
            volume: try container.decodeIfPresent(String.self, forKey: .volume) ?? "",
            issue: try container.decodeIfPresent(String.self, forKey: .issue) ?? "",
            pageRange: try container.decodeIfPresent(String.self, forKey: .pageRange) ?? "",
            articleNumber: try container.decodeIfPresent(String.self, forKey: .articleNumber) ?? "",
            year: try container.decodeIfPresent(String.self, forKey: .year) ?? "",
            position: try container.decodeIfPresent(String.self, forKey: .position) ?? "",
            independence: try container.decodeIfPresent(String.self, forKey: .independence) ?? "",
            geography: try container.decodeIfPresent(String.self, forKey: .geography) ?? "",
            phdStage: try container.decodeIfPresent(String.self, forKey: .phdStage) ?? "",
            publicationType: try container.decodeIfPresent(String.self, forKey: .publicationType) ?? "",
            reviewRegistrationRegistry: try container.decodeIfPresent(String.self, forKey: .reviewRegistrationRegistry) ?? "",
            reviewRegistrationID: try container.decodeIfPresent(String.self, forKey: .reviewRegistrationID) ?? "",
            reviewRegistrationDate: try container.decodeIfPresent(String.self, forKey: .reviewRegistrationDate) ?? "",
            isPeerReviewed: try container.decodeIfPresent(Bool.self, forKey: .isPeerReviewed) ?? true,
            citations: try container.decodeIfPresent(String.self, forKey: .citations) ?? "",
            norwegianCurrent: norwegianCurrent,
            norwegian2025: try container.decodeIfPresent(String.self, forKey: .norwegian2025) ?? "",
            sjrCurrent: sjrCurrent,
            sjr2024: try container.decodeIfPresent(String.self, forKey: .sjr2024) ?? "",
            jifCurrent: jifCurrent,
            jifQuartileCurrent: try container.decodeIfPresent(String.self, forKey: .jifQuartileCurrent) ?? "",
            jif2024: try container.decodeIfPresent(String.self, forKey: .jif2024) ?? "",
            category: try container.decodeIfPresent(String.self, forKey: .category) ?? "",
            authorNames: authorNames,
            authorIDs: try container.decodeIfPresent([String].self, forKey: .authorIDs) ?? [],
            sharedFirstAuthorship: try container.decodeIfPresent(Bool.self, forKey: .sharedFirstAuthorship) ?? false,
            sharedLastAuthorship: try container.decodeIfPresent(Bool.self, forKey: .sharedLastAuthorship) ?? false,
            correspondingAuthorName: try container.decodeIfPresent(String.self, forKey: .correspondingAuthorName),
            correspondingAuthorID: try container.decodeIfPresent(String.self, forKey: .correspondingAuthorID),
            citationYears: try container.decodeIfPresent([PublicationCitationYear].self, forKey: .citationYears) ?? [],
            statusTimeline: try container.decodeIfPresent([PublicationStatusEntry].self, forKey: .statusTimeline) ?? [],
            currentSubmissionDate: try container.decodeIfPresent(String.self, forKey: .currentSubmissionDate),
            previousAttempts: try container.decodeIfPresent([PublicationAttempt].self, forKey: .previousAttempts) ?? [],
            workflowStatus: try container.decodeIfPresent(PublicationWorkflowStatus.self, forKey: .workflowStatus),
            workflowStatusDate: try container.decodeIfPresent(String.self, forKey: .workflowStatusDate),
            publicationTasks: try container.decodeIfPresent([PublicationTaskItem].self, forKey: .publicationTasks) ?? [],
            creditRoleAssignments: try container.decodeIfPresent([PublicationCreditAssignment].self, forKey: .creditRoleAssignments) ?? [],
            finalPDFFilename: try container.decodeIfPresent(String.self, forKey: .finalPDFFilename),
            finalPDFPath: try container.decodeIfPresent(String.self, forKey: .finalPDFPath),
            isEditingLocked: try container.decodeIfPresent(Bool.self, forKey: .isEditingLocked) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encode(number, forKey: .number)
        try container.encodeIfPresent(projectName, forKey: .projectName)
        try container.encode(title, forKey: .title)
        try container.encode(journal, forKey: .journal)
        try container.encodeIfPresent(journalID, forKey: .journalID)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(statusDate, forKey: .statusDate)
        try container.encode(doi, forKey: .doi)
        try container.encode(epubDate, forKey: .epubDate)
        try container.encode(pmid, forKey: .pmid)
        try container.encode(volume, forKey: .volume)
        try container.encode(issue, forKey: .issue)
        try container.encode(pageRange, forKey: .pageRange)
        try container.encode(articleNumber, forKey: .articleNumber)
        try container.encode(year, forKey: .year)
        try container.encode(position, forKey: .position)
        try container.encode(independence, forKey: .independence)
        try container.encode(geography, forKey: .geography)
        try container.encode(phdStage, forKey: .phdStage)
        try container.encode(publicationType, forKey: .publicationType)
        try container.encode(reviewRegistrationRegistry, forKey: .reviewRegistrationRegistry)
        try container.encode(reviewRegistrationID, forKey: .reviewRegistrationID)
        try container.encode(reviewRegistrationDate, forKey: .reviewRegistrationDate)
        try container.encode(isPeerReviewed, forKey: .isPeerReviewed)
        try container.encode(citations, forKey: .citations)
        try container.encode(norwegianCurrent, forKey: .norwegianCurrent)
        try container.encode(norwegian2025, forKey: .norwegian2025)
        try container.encode(sjrCurrent, forKey: .sjrCurrent)
        try container.encode(sjr2024, forKey: .sjr2024)
        try container.encode(jifCurrent, forKey: .jifCurrent)
        try container.encode(jifQuartileCurrent, forKey: .jifQuartileCurrent)
        try container.encode(jif2024, forKey: .jif2024)
        try container.encode(category, forKey: .category)
        try container.encode(authorNames, forKey: .authorNames)
        if !authorIDs.isEmpty {
            try container.encode(authorIDs, forKey: .authorIDs)
        }
        try container.encode(sharedFirstAuthorship, forKey: .sharedFirstAuthorship)
        try container.encode(sharedLastAuthorship, forKey: .sharedLastAuthorship)
        try container.encodeIfPresent(correspondingAuthorName, forKey: .correspondingAuthorName)
        try container.encodeIfPresent(correspondingAuthorID, forKey: .correspondingAuthorID)
        try container.encode(citationYears, forKey: .citationYears)
        try container.encode(statusTimeline, forKey: .statusTimeline)
        try container.encodeIfPresent(currentSubmissionDate, forKey: .currentSubmissionDate)
        try container.encode(previousAttempts, forKey: .previousAttempts)
        try container.encodeIfPresent(workflowStatus, forKey: .workflowStatus)
        try container.encodeIfPresent(workflowStatusDate, forKey: .workflowStatusDate)
        try container.encode(publicationTasks, forKey: .publicationTasks)
        try container.encode(creditRoleAssignments, forKey: .creditRoleAssignments)
        try container.encodeIfPresent(finalPDFFilename, forKey: .finalPDFFilename)
        try container.encodeIfPresent(finalPDFPath, forKey: .finalPDFPath)
        try container.encode(isEditingLocked, forKey: .isEditingLocked)
    }

    mutating func normalize() {
        projectID = projectID?.trimmedOrNil
        number = number.trimmingCharacters(in: .whitespacesAndNewlines)
        projectName = projectName?.trimmedOrNil
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        journal = journal.trimmingCharacters(in: .whitespacesAndNewlines)
        journalID = journalID?.trimmedOrNil
        status = status.trimmingCharacters(in: .whitespacesAndNewlines)
        statusDate = statusDate?.trimmedOrNil
        doi = doi.trimmingCharacters(in: .whitespacesAndNewlines)
        epubDate = DateParsers.canonicalizedDayInput(epubDate).trimmingCharacters(in: .whitespacesAndNewlines)
        pmid = pmid.trimmingCharacters(in: .whitespacesAndNewlines)
        volume = volume.trimmingCharacters(in: .whitespacesAndNewlines)
        issue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        pageRange = pageRange.trimmingCharacters(in: .whitespacesAndNewlines)
        articleNumber = articleNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        year = year.trimmingCharacters(in: .whitespacesAndNewlines)
        position = position.trimmingCharacters(in: .whitespacesAndNewlines)
        independence = independence.trimmingCharacters(in: .whitespacesAndNewlines)
        geography = geography.trimmingCharacters(in: .whitespacesAndNewlines)
        phdStage = phdStage.trimmingCharacters(in: .whitespacesAndNewlines)
        publicationType = publicationType.trimmingCharacters(in: .whitespacesAndNewlines)
        switch publicationType.lowercased() {
        case "review", "narrative review":
            publicationType = "Narrative review"
        case "systematic review":
            publicationType = "Systematic review"
        case "brief report":
            publicationType = "Brief report"
        case "research letter":
            publicationType = "Research letter"
        case "protocol article", "protocol":
            publicationType = "Protocol"
        case "original":
            publicationType = "Original"
        default:
            break
        }
        reviewRegistrationRegistry = PublicationReviewRegistrationRegistry.canonicalName(for: reviewRegistrationRegistry) ?? reviewRegistrationRegistry.trimmingCharacters(in: .whitespacesAndNewlines)
        reviewRegistrationID = reviewRegistrationID.trimmingCharacters(in: .whitespacesAndNewlines)
        reviewRegistrationDate = DateParsers.canonicalizedDayInput(reviewRegistrationDate).trimmingCharacters(in: .whitespacesAndNewlines)
        citations = citations.trimmingCharacters(in: .whitespacesAndNewlines)
        norwegianCurrent = norwegianCurrent.trimmingCharacters(in: .whitespacesAndNewlines)
        norwegian2025 = norwegian2025.trimmingCharacters(in: .whitespacesAndNewlines)
        sjrCurrent = sjrCurrent.trimmingCharacters(in: .whitespacesAndNewlines)
        sjr2024 = sjr2024.trimmingCharacters(in: .whitespacesAndNewlines)
        jifCurrent = jifCurrent.trimmingCharacters(in: .whitespacesAndNewlines)
        jifQuartileCurrent = jifQuartileCurrent.trimmingCharacters(in: .whitespacesAndNewlines)
        jif2024 = jif2024.trimmingCharacters(in: .whitespacesAndNewlines)
        category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        authorNames = authorNames.compactMap(\.trimmedOrNil)
        correspondingAuthorName = correspondingAuthorName?.trimmedOrNil
        if let correspondingAuthorName {
            let normalizedCorrespondingAuthor = normalizedCreditAuthorName(correspondingAuthorName)
            self.correspondingAuthorName = authorNames.first(where: {
                normalizedCreditAuthorName($0) == normalizedCorrespondingAuthor
            })
        }
        authorIDs = Array(NSOrderedSet(array: authorIDs.compactMap(\.trimmedOrNil))) as? [String]
            ?? authorIDs.compactMap(\.trimmedOrNil)
        correspondingAuthorID = self.correspondingAuthorName == nil ? nil : correspondingAuthorID?.trimmedOrNil
        if authorNames.count < 2 {
            sharedFirstAuthorship = false
            sharedLastAuthorship = false
        }
        citationYears = citationYears.map {
            var copy = $0
            copy.normalize()
            return copy
        }
        .filter { !$0.isEmpty }
        .sorted { $0.yearValue > $1.yearValue }
        if !citationYears.isEmpty {
            citations = String(citationYears.map(\.totalCitationCountValue).reduce(0, +))
        }
        var normalizedStatusTimeline = statusTimeline.enumerated().map { offset, entry -> (offset: Int, entry: PublicationStatusEntry) in
            var copy = entry
            copy.normalize()
            copy.status = PublicationStatus.normalizedRawValue(copy.status)
            return (offset, copy)
        }
        .filter { !$0.entry.isEmpty }

        var seenStatusTimelineKeys = Set<String>()
        normalizedStatusTimeline = normalizedStatusTimeline.filter { seenStatusTimelineKeys.insert($0.entry.dedupeKey).inserted }

        statusTimeline = normalizedStatusTimeline
            .sorted { lhs, rhs in
                let leftHasDate = lhs.entry.date?.trimmedOrNil != nil
                let rightHasDate = rhs.entry.date?.trimmedOrNil != nil
                if leftHasDate != rightHasDate {
                    return leftHasDate && !rightHasDate
                }
                if leftHasDate {
                    let leftDate = lhs.entry.date.flatMap { DateParsers.isoDay.date(from: $0) } ?? .distantPast
                    let rightDate = rhs.entry.date.flatMap { DateParsers.isoDay.date(from: $0) } ?? .distantPast
                    if leftDate != rightDate {
                        return leftDate > rightDate
                    }
                    let leftStatus = PublicationStatus.fromStored(lhs.entry.status)
                    let rightStatus = PublicationStatus.fromStored(rhs.entry.status)
                    let leftTieBreak = publicationCurrentStatusTieBreakRank(leftStatus)
                    let rightTieBreak = publicationCurrentStatusTieBreakRank(rightStatus)
                    if leftTieBreak != rightTieBreak {
                        return leftTieBreak > rightTieBreak
                    }
                }
                return lhs.offset < rhs.offset
            }
            .map(\.entry)
        if statusTimeline.isEmpty, status.nonEmpty != nil || journal.nonEmpty != nil || statusDate?.nonEmpty != nil {
            statusTimeline = [PublicationStatusEntry(status: status, journal: journal, date: statusDate)]
        }
        if let latest = publicationEffectiveStatusEntry(from: publicationDerivedSubmissionRows(from: statusTimeline)) {
            status = latest.status
            journal = latest.journal.nonEmpty ?? journal
            statusDate = latest.date
        } else if let latest = statusTimeline.first {
            status = latest.status
            journal = latest.journal.nonEmpty ?? journal
            statusDate = latest.date
        }
        workflowStatusDate = workflowStatusDate?.trimmedOrNil
        currentSubmissionDate = currentSubmissionDate?.trimmedOrNil
        previousAttempts = previousAttempts
            .map {
                var copy = $0
                copy.journal = copy.journal.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.submittedOn = copy.submittedOn?.trimmedOrNil
                copy.rejectedOn = copy.rejectedOn?.trimmedOrNil
                return copy
            }
            .filter { $0.journal.nonEmpty != nil || $0.submittedOn != nil || $0.rejectedOn != nil }
            .uniqued(by: \.dedupeKey)
        publicationTasks = publicationTasks
            .map {
                var copy = $0
                copy.normalize()
                return copy
            }
            .filter { !$0.isEmpty }
        creditRoleAssignments = creditRoleAssignments
            .map {
                var copy = $0
                copy.normalize(validAuthorNames: Set(authorNames))
                return copy
            }
            .filter { !$0.isEmpty }
            .uniqued(by: \.dedupeKey)
        finalPDFFilename = finalPDFFilename?.trimmedOrNil
        if let path = finalPDFPath?.trimmedOrNil,
           finalPDFFilename == nil {
            finalPDFFilename = URL(fileURLWithPath: path).lastPathComponent.nonEmpty
        }
        finalPDFPath = finalPDFPath?.trimmedOrNil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var yearValue: Int? {
        Int(year)
    }

    func isCorrespondingAuthor(named authorName: String) -> Bool {
        guard let correspondingAuthorName else { return false }
        return normalizedCreditAuthorName(correspondingAuthorName) == normalizedCreditAuthorName(authorName)
    }

    mutating func setCorrespondingAuthor(named authorName: String?, isSelected: Bool) {
        correspondingAuthorName = isSelected ? authorName?.trimmedOrNil : nil
        normalize()
    }

    func creditRoles(forAuthorName authorName: String) -> Set<PublicationCreditRole> {
        let normalizedAuthor = normalizedCreditAuthorName(authorName)
        guard !normalizedAuthor.isEmpty else { return [] }
        let roles = creditRoleAssignments.first {
            normalizedCreditAuthorName($0.authorName) == normalizedAuthor
        }?.roles ?? []
        return Set(roles)
    }

    func creditRoleContribution(
        forAuthorName authorName: String,
        role: PublicationCreditRole
    ) -> PublicationCreditRoleContribution? {
        let normalizedAuthor = normalizedCreditAuthorName(authorName)
        guard !normalizedAuthor.isEmpty else { return nil }
        guard let assignment = creditRoleAssignments.first(where: {
            normalizedCreditAuthorName($0.authorName) == normalizedAuthor
        }) else {
            return nil
        }
        return assignment.roleContributions.first(where: { $0.role == role })?.contribution
    }

    func creditRoleContributionMap(
        forAuthorName authorName: String
    ) -> [PublicationCreditRole: PublicationCreditRoleContribution] {
        let normalizedAuthor = normalizedCreditAuthorName(authorName)
        guard !normalizedAuthor.isEmpty else { return [:] }
        guard let assignment = creditRoleAssignments.first(where: {
            normalizedCreditAuthorName($0.authorName) == normalizedAuthor
        }) else {
            return [:]
        }
        return assignment.roleContributions.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.role] = entry.contribution
        }
    }

    mutating func setCreditRoles(_ roles: Set<PublicationCreditRole>, forAuthorName authorName: String) {
        let normalizedAuthor = normalizedCreditAuthorName(authorName)
        guard !normalizedAuthor.isEmpty else { return }

        let normalizedRoles = Array(roles).sorted { $0.sortIndex < $1.sortIndex }
        if let index = creditRoleAssignments.firstIndex(where: {
            normalizedCreditAuthorName($0.authorName) == normalizedAuthor
        }) {
            if normalizedRoles.isEmpty {
                creditRoleAssignments.remove(at: index)
            } else {
                creditRoleAssignments[index].authorName = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
                creditRoleAssignments[index].roles = normalizedRoles
                creditRoleAssignments[index].roleContributions.removeAll { !normalizedRoles.contains($0.role) }
            }
        } else if !normalizedRoles.isEmpty {
            creditRoleAssignments.append(
                PublicationCreditAssignment(
                    authorName: authorName,
                    roles: normalizedRoles
                )
            )
        }
        normalize()
    }

    mutating func setCreditRoleContribution(
        _ contribution: PublicationCreditRoleContribution?,
        forAuthorName authorName: String,
        role: PublicationCreditRole
    ) {
        let normalizedAuthor = normalizedCreditAuthorName(authorName)
        guard !normalizedAuthor.isEmpty else { return }

        if let index = creditRoleAssignments.firstIndex(where: {
            normalizedCreditAuthorName($0.authorName) == normalizedAuthor
        }) {
            var assignment = creditRoleAssignments[index]
            if !assignment.roles.contains(role), contribution != nil {
                assignment.roles.append(role)
            }
            assignment.roles = Array(Set(assignment.roles)).sorted { $0.sortIndex < $1.sortIndex }
            assignment.roleContributions.removeAll { $0.role == role }
            if let contribution {
                assignment.roleContributions.append(
                    PublicationCreditRoleContributionEntry(
                        role: role,
                        contribution: contribution
                    )
                )
            }
            assignment.normalize()
            if assignment.isEmpty {
                creditRoleAssignments.remove(at: index)
            } else {
                creditRoleAssignments[index] = assignment
            }
        } else if let contribution {
            creditRoleAssignments.append(
                PublicationCreditAssignment(
                    authorName: authorName,
                    roles: [role],
                    roleContributions: [
                        PublicationCreditRoleContributionEntry(
                            role: role,
                            contribution: contribution
                        )
                    ]
                )
            )
        }
        normalize()
    }

    var hasDefinedCreditRoles: Bool {
        creditRoleAssignments.contains { !$0.roles.isEmpty }
    }

    var citationsValue: Int {
        if !citationYears.isEmpty {
            return citationYears.map(\.totalCitationCountValue).reduce(0, +)
        }
        return Int(citations) ?? 0
    }

    var sortYear: Int {
        yearValue ?? 0
    }

    var norwegianSortableValue: Double {
        PublicationJournal.norwegianRankValue(for: norwegianCurrent)
    }

    var statusLabel: String {
        PublicationStatus.normalizedRawValue(status.nonEmpty)
    }

    var statusSortRank: Int {
        switch PublicationStatus.fromStored(statusLabel) {
        case .planned:
            return 0
        case .inPreparation:
            return 10 + (workflowStatus?.sortRank ?? PublicationWorkflowStatus.allCases.count)
        case .submitted:
            return 20
        case .accepted:
            return 30
        case .rejected:
            return 40
        case .published:
            return 50
        }
    }

    var isPublished: Bool {
        if PublicationStatus.fromStored(statusLabel) == .published {
            return true
        }
        return statusTimeline.contains { entry in
            PublicationStatus.fromStored(entry.status) == .published
        }
    }

    var jifSortableValue: Double {
        let cleaned = jifCurrent
            .replacingOccurrences(of: " (uncertain)", with: "")
            .replacingOccurrences(of: " (osäkert)", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    var jifQuartileSortRank: Int {
        switch jifQuartileCurrent {
        case "Q1":
            1
        case "Q2":
            2
        case "Q3":
            3
        case "Q4":
            4
        default:
            9
        }
    }

    var isSystematicReview: Bool {
        publicationType.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Systematic review") == .orderedSame
    }

    var hasReviewRegistrationMetadata: Bool {
        reviewRegistrationRegistry.trimmedOrNil != nil
            || reviewRegistrationID.trimmedOrNil != nil
            || reviewRegistrationDate.trimmedOrNil != nil
    }

    var reviewRegistrationURL: URL? {
        PublicationReviewRegistrationRegistry.url(
            registry: reviewRegistrationRegistry,
            identifier: reviewRegistrationID
        )
    }

    var doiURL: URL? {
        normalizedIdentifierURL(raw: doi, kind: .doi)
    }

    var pmidURL: URL? {
        normalizedIdentifierURL(raw: pmid, kind: .pmid)
    }
}

enum PublicationReviewRegistrationRegistry: String, CaseIterable, Identifiable {
    case prospero = "PROSPERO"
    case inplasy = "INPLASY"
    case osfRegistries = "OSF Registries"
    case researchRegistry = "Research Registry"
    case protocolsIO = "protocols.io"

    var id: String { rawValue }

    static func canonicalName(for raw: String) -> String? {
        let normalized = normalizedKey(raw)
        guard !normalized.isEmpty else { return nil }
        return allCases.first { normalizedKey($0.rawValue) == normalized }?.rawValue
    }

    static func url(registry rawRegistry: String, identifier rawIdentifier: String) -> URL? {
        guard let registryName = canonicalName(for: rawRegistry),
              let registry = Self(rawValue: registryName) else {
            return nil
        }
        let identifier = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return nil }
        if let directURL = directURL(from: identifier), registry.allowsDirectURLIdentifier {
            return directURL
        }

        switch registry {
        case .prospero:
            let withoutPrefix = identifier.replacingOccurrences(
                of: #"(?i)^CRD"#,
                with: "",
                options: .regularExpression
            )
            let digits = withoutPrefix.filter(\.isNumber)
            guard !digits.isEmpty else { return nil }
            return URL(string: "https://www.crd.york.ac.uk/prospero/display_record.php?RecordID=\(digits)")
        case .inplasy:
            guard let slug = inplasySlug(from: identifier) else { return nil }
            return URL(string: "https://inplasy.com/\(slug)/")
        case .osfRegistries:
            let code = identifier.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let encoded = encodedPathComponent(code) else { return nil }
            return URL(string: "https://osf.io/\(encoded)")
        case .researchRegistry:
            guard let encoded = encodedPathComponent(identifier) else {
                return URL(string: "https://www.researchregistry.com/browse-the-registry")
            }
            return URL(string: "https://www.researchregistry.com/browse-the-registry#home/registrationdetails/\(encoded)")
        case .protocolsIO:
            if let doi = normalizedDOI(from: identifier) {
                return URL(string: "https://doi.org/\(doi)")
            }
            guard let encoded = encodedPathComponent(identifier) else { return nil }
            return URL(string: "https://www.protocols.io/view/\(encoded)")
        }
    }

    private var allowsDirectURLIdentifier: Bool {
        switch self {
        case .osfRegistries, .protocolsIO:
            return true
        case .prospero, .inplasy, .researchRegistry:
            return false
        }
    }

    private static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    private static func directURL(from raw: String) -> URL? {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func inplasySlug(from raw: String) -> String? {
        let lowercased = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowercased.hasPrefix("inplasy-") {
            return lowercased
        }

        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(?i)^INPLASY"#, with: "", options: .regularExpression)
            .filter { $0.isLetter || $0.isNumber }
        guard cleaned.count > 4 else { return nil }
        let year = String(cleaned.prefix(4))
        let number = String(cleaned.dropFirst(4))
        guard year.allSatisfy(\.isNumber), !number.isEmpty else { return nil }
        return "inplasy-\(year)-\(number)"
    }

    private static func normalizedDOI(from raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: #"(?i)^doi:\s*"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)^https?://(dx\.)?doi\.org/"#, with: "", options: .regularExpression)
        guard value.range(of: #"^10\.\S+/.+"#, options: .regularExpression) != nil else { return nil }
        return value
    }

    private static func encodedPathComponent(_ raw: String) -> String? {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .trimmedOrNil
    }
}

struct PublicationRankingSnapshot {
    let norwegian: String
    let sjr: String
    let jif: String
    let uncertain: Bool
}

enum PublicationStatus: String, Codable, CaseIterable, Identifiable {
    case planned = "Planned"
    case inPreparation = "In preparation"
    case submitted = "Submitted"
    case accepted = "Accepted"
    case rejected = "Rejected"
    case published = "Published"

    var id: String { rawValue }

    static var selectableCases: [PublicationStatus] {
        [.inPreparation, .submitted, .accepted, .rejected, .published]
    }

    static func fromStored(_ raw: String?) -> PublicationStatus {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case nil, "":
            return .inPreparation
        case planned.rawValue:
            return .inPreparation
        case inPreparation.rawValue, "In writing":
            return .inPreparation
        case submitted.rawValue, "Submitted, with editor", "Submitted, in review":
            return .submitted
        case accepted.rawValue:
            return .accepted
        case rejected.rawValue:
            return .rejected
        case published.rawValue:
            return .published
        default:
            return .inPreparation
        }
    }

    static func normalizedRawValue(_ raw: String?) -> String {
        fromStored(raw).rawValue
    }

    var sortRank: Int {
        switch self {
        case .planned:
            0
        case .inPreparation:
            1
        case .submitted:
            2
        case .accepted:
            3
        case .rejected:
            4
        case .published:
            5
        }
    }

    var isSubmittedFamily: Bool {
        switch self {
        case .submitted:
            return true
        default:
            return false
        }
    }

    var showsProjectCollaboratorAuthorButtons: Bool {
        switch self {
        case .submitted, .accepted, .published:
            return false
        case .planned, .inPreparation, .rejected:
            return true
        }
    }
}

func publicationCurrentStatusTieBreakRank(_ status: PublicationStatus) -> Int {
    switch status {
    case .planned:
        return 0
    case .inPreparation:
        return 1
    case .rejected:
        return 2
    case .submitted:
        return 3
    case .accepted:
        return 4
    case .published:
        return 5
    }
}

enum PublicationDerivation {
    static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sv_SE"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func position(
        for authors: [String],
        currentUserNames: Set<String>,
        sharedFirstAuthorship: Bool = false,
        sharedLastAuthorship: Bool = false
    ) -> String {
        let normalizedCurrentUserNames = Set(currentUserNames.map(normalizedName).filter { !$0.isEmpty })
        guard !normalizedCurrentUserNames.isEmpty else { return "" }
        let normalized = authors.map(normalizedName)
        guard let index = normalized.firstIndex(where: normalizedCurrentUserNames.contains) else { return "" }
        if authors.count == 1 {
            return "Single"
        }
        if index == 0 || (sharedFirstAuthorship && index == 1 && authors.count >= 2) {
            return "First"
        }
        if index == authors.count - 1 || (sharedLastAuthorship && index == authors.count - 2 && authors.count >= 2) {
            return "Last"
        }
        return "Middle"
    }

    static func independence(for authors: [String], formerSupervisorNames: Set<String>) -> String {
        let normalizedSupervisorNames = Set(formerSupervisorNames.map(normalizedName).filter { !$0.isEmpty })
        guard !normalizedSupervisorNames.isEmpty else { return "" }
        let normalized = Set(authors.map(normalizedName))
        return normalizedSupervisorNames.contains(where: normalized.contains) ? "No" : "Yes"
    }

    /// "International" when any author's primary country is another country
    /// than the home country (Settings > Home organization; default Sweden).
    static func geography(
        for authors: [PublicationAuthor],
        homeCountry: String = HomeOrganizationDefaults.homeCountry
    ) -> String {
        let hasForeignPrimary = authors.contains { author in
            guard let country = author.primaryCountry.trimmedOrNil else { return false }
            return !countryNamesMatch(country, homeCountry)
        }
        return hasForeignPrimary ? "International" : "National"
    }

    static func phdStage(for referenceDate: Date?, phdDate: Date?) -> String {
        guard let referenceDate, let phdDate else { return "" }
        return referenceDate < phdDate ? "Before" : "After"
    }
}
