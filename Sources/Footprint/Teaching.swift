import Foundation

private func localizedTeachingContentValue(language: AppLanguage, swedish: String, english: String) -> String {
    let swedishValue = swedish.trimmingCharacters(in: .whitespacesAndNewlines)
    let englishValue = english.trimmingCharacters(in: .whitespacesAndNewlines)
    if language == .swedish {
        return swedishValue.nonEmpty ?? englishValue
    }
    return englishValue.nonEmpty ?? swedishValue
}

private func derivedTeachingProgramArea(
    nameSv: String,
    nameEn: String,
    contextType: TeachingContextType?,
    level: TeachingCourseLevel?,
    isClinicalTeaching: Bool,
    courseCode: String = "",
    credits: String = "",
    termSv: String = "",
    termEn: String = ""
) -> (sv: String, en: String)? {
    let normalizedSv = nameSv.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    let normalizedEn = nameEn.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    let hasNamedTerm = termSv.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty != nil
        || termEn.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty != nil

    let settings = WorkflowDefaultSettingsRegistry.current
    if hasNamedTerm {
        return (settings.resolvedDefaultTeachingProgramSv, settings.resolvedDefaultTeachingProgramEn)
    }

    if contextType == .courseAdministration {
        return ("Administration och utveckling", "Administration and development")
    }

    if contextType == .clinicalTeaching || isClinicalTeaching {
        return ("Klinisk undervisning", "Clinical teaching")
    }

    if contextType == .doctoralEducation
        || level == .doctoral
        || normalizedSv.contains("forskar")
        || normalizedEn.contains("doctoral")
        || normalizedEn.contains("phd") {
        return ("Forskarutbildning", "Doctoral education")
    }

    if contextType == .programTrack {
        return ("Program och spår", "Programmes and tracks")
    }

    if contextType == .course || courseCode.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty != nil || credits.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty != nil {
        return ("Fristående kurser", "Standalone courses")
    }

    if contextType == .other {
        return ("Administration och utveckling", "Administration and development")
    }

    return nil
}

func localizedTeachingProgramArea(
    language: AppLanguage,
    programSv: String,
    programEn: String,
    nameSv: String,
    nameEn: String,
    contextType: TeachingContextType?,
    level: TeachingCourseLevel?,
    isClinicalTeaching: Bool,
    courseCode: String = "",
    credits: String = "",
    termSv: String = "",
    termEn: String = ""
) -> String {
    let explicit = localizedTeachingContentValue(language: language, swedish: programSv, english: programEn)
    if explicit.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty != nil {
        return explicit
    }
    let fallback = derivedTeachingProgramArea(
        nameSv: nameSv,
        nameEn: nameEn,
        contextType: contextType,
        level: level,
        isClinicalTeaching: isClinicalTeaching,
        courseCode: courseCode,
        credits: credits,
        termSv: termSv,
        termEn: termEn
    )
    return language == .swedish ? (fallback?.sv ?? "") : (fallback?.en ?? "")
}

func localizedTeachingTermLabel(_ raw: String, language: AppLanguage) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.nonEmpty != nil else { return "" }
    if Int(trimmed) != nil {
        return language.text("Term \(trimmed)", "Termin \(trimmed)")
    }
    return trimmed
}

func teachingStructureLeafLabel(_ course: TeachingCourse, language: AppLanguage) -> String {
    let name = course.localizedName(language: language).trimmingCharacters(in: .whitespacesAndNewlines)
    let term = localizedTeachingTermLabel(course.localizedTerm(language: language).nonEmpty ?? course.localizedTermFallback, language: language)
    switch (name.nonEmpty, term.nonEmpty) {
    case let (name?, term?):
        return "\(term) (\(name))"
    case let (name?, nil):
        return name
    case let (nil, term?):
        return term
    default:
        return ""
    }
}

func teachingStructureBreadcrumb(_ course: TeachingCourse, language: AppLanguage) -> [String] {
    [
        course.institution.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
        course.localizedProgram(language: language).trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
        teachingStructureLeafLabel(course, language: language).trimmedOrNil
    ].compactMap { $0 }
}

enum TeachingCourseLevel: String, Codable, Hashable, CaseIterable, Identifiable {
    case undergraduate = "Undergraduate"
    case advanced = "Advanced"
    case doctoral = "Doctoral"

    var id: String { rawValue }
}

enum TeachingContextType: String, Codable, Hashable, CaseIterable, Identifiable {
    case course = "Course"
    case programTrack = "Program / track"
    case doctoralEducation = "Doctoral education"
    case clinicalTeaching = "Clinical teaching"
    case courseAdministration = "Course administration / development"
    case other = "Other"

    var id: String { rawValue }
}

enum TeachingAssignmentKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case teaching = "Teaching"
    case supervision = "Supervision"
    case clinical = "Clinical teaching"
    case development = "Development work"

    var id: String { rawValue }

    var translationKey: String {
        switch self {
        case .teaching:
            return "teachingKind.teaching"
        case .supervision:
            return "teachingKind.supervision"
        case .clinical:
            return "teachingKind.clinical"
        case .development:
            return "teachingKind.development"
        }
    }

    var defaultEnglishName: String {
        switch self {
        case .teaching:
            return "Teaching"
        case .supervision:
            return "Supervision"
        case .clinical:
            return "Clinical teaching"
        case .development:
            return "Development work"
        }
    }

    var defaultSwedishName: String {
        switch self {
        case .teaching:
            return "Undervisning"
        case .supervision:
            return "Handledning"
        case .clinical:
            return "Klinisk undervisning"
        case .development:
            return "Utvecklingsarbete"
        }
    }
}

struct TeachingAssignmentRole: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = Self.canonicalID(for: rawValue)
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var id: String { rawValue }

    static let facilitator = Self("facilitator")
    static let contributor = Self("contributor")
    static let supervisor = Self("supervisor")
    static let examiner = Self("examiner")
    static let lecturer = Self("lecturer")
    static let invitedSpeaker = Self("invitedSpeaker")
    static let seminarLeader = Self("seminarLeader")
    static let principalSupervisor = Self("principalSupervisor")
    static let assistantSupervisor = Self("assistantSupervisor")
    static let opponent = Self("opponent")
    static let gradingCommittee = Self("gradingCommittee")

    static let builtInRoles: [TeachingAssignmentRole] = [
        .contributor,
        .facilitator,
        .supervisor,
        .examiner,
        .lecturer,
        .invitedSpeaker,
        .seminarLeader,
        .principalSupervisor,
        .assistantSupervisor,
        .opponent,
        .gradingCommittee,
    ]

    static func canonicalID(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let aliases: [String: String] = [
            "facilitator": "facilitator",
            "contributor": "contributor",
            "supervisor": "supervisor",
            "examiner": "examiner",
            "lecturer": "lecturer",
            "invited speaker": "invitedSpeaker",
            "invitedspeaker": "invitedSpeaker",
            "seminar leader": "seminarLeader",
            "seminarleader": "seminarLeader",
            "principal supervisor": "principalSupervisor",
            "principalsupervisor": "principalSupervisor",
            "assistant supervisor": "assistantSupervisor",
            "assistantsupervisor": "assistantSupervisor",
            "co-supervisor": "assistantSupervisor",
            "cosupervisor": "assistantSupervisor",
            "opponent": "opponent",
            "grading committee": "gradingCommittee",
            "gradingcommittee": "gradingCommittee",
        ]

        let lowered = trimmed.lowercased()
        if let alias = aliases[lowered] {
            return alias
        }

        let compact = lowered.replacingOccurrences(of: " ", with: "")
        if let alias = aliases[compact] {
            return alias
        }

        return trimmed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct TeachingRoleOption: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var nameSv: String
    var nameEn: String

    init(
        id: String = UUID().uuidString,
        nameSv: String = "",
        nameEn: String = ""
    ) {
        self.id = TeachingAssignmentRole.canonicalID(for: id)
        self.nameSv = nameSv
        self.nameEn = nameEn
    }

    var name: String {
        nameSv.nonEmpty ?? nameEn.nonEmpty ?? ""
    }

    func localizedName(language: AppLanguage) -> String {
        if language == .swedish {
            return nameSv.nonEmpty ?? nameEn
        }
        return nameEn.nonEmpty ?? nameSv
    }

    mutating func normalize() {
        id = TeachingAssignmentRole.canonicalID(for: id)
        nameSv = nameSv.trimmingCharacters(in: .whitespacesAndNewlines)
        nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            let fallback = nameEn.nonEmpty ?? nameSv.nonEmpty ?? StableRecordID.legacy(prefix: "teaching-role", name: UUID().uuidString)
            id = TeachingAssignmentRole.canonicalID(for: fallback)
        }
    }

    var isEmpty: Bool {
        nameSv.nonEmpty == nil && nameEn.nonEmpty == nil
    }

    static let builtInOptions: [TeachingRoleOption] = [
        .init(id: TeachingAssignmentRole.contributor.rawValue, nameSv: "Medarbetare", nameEn: "Contributor"),
        .init(id: TeachingAssignmentRole.facilitator.rawValue, nameSv: "Facilitator", nameEn: "Facilitator"),
        .init(id: TeachingAssignmentRole.supervisor.rawValue, nameSv: "Handledare", nameEn: "Supervisor"),
        .init(id: TeachingAssignmentRole.examiner.rawValue, nameSv: "Examinator", nameEn: "Examiner"),
        .init(id: TeachingAssignmentRole.lecturer.rawValue, nameSv: "Föreläsare", nameEn: "Lecturer"),
        .init(id: TeachingAssignmentRole.invitedSpeaker.rawValue, nameSv: "Inbjuden talare", nameEn: "Invited speaker"),
        .init(id: TeachingAssignmentRole.seminarLeader.rawValue, nameSv: "Seminarieledare", nameEn: "Seminar leader"),
        .init(id: TeachingAssignmentRole.principalSupervisor.rawValue, nameSv: "Huvudhandledare", nameEn: "Principal supervisor"),
        .init(id: TeachingAssignmentRole.assistantSupervisor.rawValue, nameSv: "Bihandledare", nameEn: "Co-supervisor"),
        .init(id: TeachingAssignmentRole.opponent.rawValue, nameSv: "Opponent", nameEn: "Opponent"),
        .init(id: TeachingAssignmentRole.gradingCommittee.rawValue, nameSv: "Betygskommitté", nameEn: "Grading committee"),
    ]
}

enum TeachingAssignmentCategory: String, Codable, Hashable, CaseIterable, Identifiable {
    case individual = "Individual"
    case group = "Group"
    case groupAndIndividual = "Group and individual"
    case notTeachingWork = "Not teaching work"

    var id: String { rawValue }
}

enum TeachingReportCategory: String, Codable, Hashable, CaseIterable, Identifiable {
    case groupTeaching = "Group teaching / practical teaching"
    case lecture = "Lecture"
    case doctoralCourseTeaching = "Doctoral course teaching"
    case thesisSupervision = "Thesis / in-depth project supervision"
    case doctoralPrincipalSupervision = "Doctoral supervision (principal)"
    case doctoralAssistantSupervision = "Doctoral supervision (assistant)"
    case courseAdministration = "Course administration / development"
    case otherPedagogicalWork = "Other pedagogical work"

    var id: String { rawValue }
}

enum TeachingDeliveryMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case onSite = "On-site"
    case hybrid = "Hybrid"
    case online = "Online"

    var id: String { rawValue }
}

enum TeachingDefaultFormat: String, Codable, Hashable, CaseIterable, Identifiable {
    case lectureHybrid = "Lecture (hybrid)"
    case lectureOnSite = "Lecture (on-site)"
    case lectureOnline = "Lecture (online)"
    case workshop = "Workshop"
    case seminar = "Seminar"
    case practicalTeaching = "Practical teaching"
    case supervision = "Supervision"
    case thesisSupervision = "Degree project supervision"
    case inDepthProjectSupervision = "In-depth project supervision"
    case doctoralSupervision = "Doctoral supervision"

    var id: String { rawValue }
}

struct TeachingComponent: Codable, Hashable, Identifiable {
    var id: String
    var nameSv: String
    var nameEn: String
    var institution: String
    /// F13: the organization by id; `institution` is its name, kept for display.
    var institutionID: String?
    var activityTypeID: String?
    var activityTypeName: String
    var participantForm: TeachingAssignmentCategory?
    var allowedContextIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameSv
        case nameEn
        case institution
        case institutionID
        case activityTypeID
        case activityTypeName
        case participantForm
        case allowedContextIDs
    }

    init(
        id: String = UUID().uuidString,
        name: String = "",
        nameSv: String? = nil,
        nameEn: String? = nil,
        institution: String = "",
        institutionID: String? = nil,
        activityTypeID: String? = nil,
        activityTypeName: String = "",
        participantForm: TeachingAssignmentCategory? = nil,
        allowedContextIDs: [String] = []
    ) {
        self.id = id
        self.nameSv = nameSv ?? name
        self.nameEn = nameEn ?? name
        self.institution = institution
        self.institutionID = institutionID
        self.activityTypeID = activityTypeID
        self.activityTypeName = activityTypeName
        self.participantForm = participantForm
        self.allowedContextIDs = allowedContextIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            name: legacy,
            nameSv: try container.decodeIfPresent(String.self, forKey: .nameSv),
            nameEn: try container.decodeIfPresent(String.self, forKey: .nameEn),
            institution: try container.decodeIfPresent(String.self, forKey: .institution) ?? "",
            institutionID: try container.decodeIfPresent(String.self, forKey: .institutionID),
            activityTypeID: try container.decodeIfPresent(String.self, forKey: .activityTypeID),
            activityTypeName: try container.decodeIfPresent(String.self, forKey: .activityTypeName) ?? "",
            participantForm: try container.decodeIfPresent(TeachingAssignmentCategory.self, forKey: .participantForm),
            allowedContextIDs: try container.decodeIfPresent([String].self, forKey: .allowedContextIDs) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nameSv, forKey: .nameSv)
        try container.encode(nameEn, forKey: .nameEn)
        try container.encode(institution, forKey: .institution)
        try container.encodeIfPresent(institutionID, forKey: .institutionID)
        try container.encodeIfPresent(activityTypeID, forKey: .activityTypeID)
        try container.encode(activityTypeName, forKey: .activityTypeName)
        try container.encodeIfPresent(participantForm, forKey: .participantForm)
        try container.encode(allowedContextIDs, forKey: .allowedContextIDs)
    }

    mutating func normalize() {
        nameSv = nameSv.trimmingCharacters(in: .whitespacesAndNewlines)
        nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        institution = institution.trimmingCharacters(in: .whitespacesAndNewlines)
        institutionID = institutionID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        activityTypeID = activityTypeID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        activityTypeName = activityTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if activityTypeName.nonEmpty == nil,
           let fallback = localizedTeachingContentValue(language: .swedish, swedish: nameSv, english: nameEn).nonEmpty {
            activityTypeName = fallback
        }
        allowedContextIDs = Array(NSOrderedSet(array: allowedContextIDs.compactMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        })) as? [String] ?? allowedContextIDs
    }

    var name: String {
        get { nameSv }
        set {
            nameSv = newValue
            nameEn = newValue
        }
    }

    func localizedName(language: AppLanguage) -> String {
        localizedTeachingContentValue(language: language, swedish: nameSv, english: nameEn)
    }

    mutating func setLocalizedName(_ value: String, language: AppLanguage) {
        if language == .swedish {
            nameSv = value
        } else {
            nameEn = value
        }
    }
}

struct TeachingFormatOption: Codable, Hashable, Identifiable {
    var id: String
    var nameSv: String
    var nameEn: String
    var category: TeachingAssignmentCategory?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameSv
        case nameEn
        case category
    }

    init(
        id: String = UUID().uuidString,
        name: String = "",
        nameSv: String? = nil,
        nameEn: String? = nil,
        category: TeachingAssignmentCategory? = nil
    ) {
        self.id = id
        self.nameSv = nameSv ?? name
        self.nameEn = nameEn ?? name
        self.category = category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            name: legacy,
            nameSv: try container.decodeIfPresent(String.self, forKey: .nameSv),
            nameEn: try container.decodeIfPresent(String.self, forKey: .nameEn),
            category: try container.decodeIfPresent(TeachingAssignmentCategory.self, forKey: .category)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nameSv, forKey: .nameSv)
        try container.encode(nameEn, forKey: .nameEn)
        try container.encodeIfPresent(category, forKey: .category)
    }

    mutating func normalize() {
        nameSv = nameSv.trimmingCharacters(in: .whitespacesAndNewlines)
        nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var name: String {
        get { nameSv }
        set {
            nameSv = newValue
            nameEn = newValue
        }
    }

    func localizedName(language: AppLanguage) -> String {
        localizedTeachingContentValue(language: language, swedish: nameSv, english: nameEn)
    }

    mutating func setLocalizedName(_ value: String, language: AppLanguage) {
        if language == .swedish {
            nameSv = value
        } else {
            nameEn = value
        }
    }
}

struct TeachingAssignmentPeriod: Codable, Hashable, Identifiable {
    var id: String
    var from: String
    var to: String
    var hoursPerTerm: String
    var confirmedInRetendo: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case from
        case to
        case hoursPerTerm
        case confirmedInRetendo
    }

    init(
        id: String = UUID().uuidString,
        from: String = "",
        to: String = "",
        hoursPerTerm: String = "",
        confirmedInRetendo: Bool = false
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.hoursPerTerm = hoursPerTerm
        self.confirmedInRetendo = confirmedInRetendo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            from: try container.decodeIfPresent(String.self, forKey: .from) ?? "",
            to: try container.decodeIfPresent(String.self, forKey: .to) ?? "",
            hoursPerTerm: try container.decodeIfPresent(String.self, forKey: .hoursPerTerm) ?? "",
            confirmedInRetendo: try container.decodeIfPresent(Bool.self, forKey: .confirmedInRetendo) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(hoursPerTerm, forKey: .hoursPerTerm)
        try container.encode(confirmedInRetendo, forKey: .confirmedInRetendo)
    }

    mutating func normalize() {
        from = DateParsers.canonicalizedDayInput(from)
        to = DateParsers.canonicalizedDayInput(to)
        hoursPerTerm = hoursPerTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        from.nonEmpty == nil && to.nonEmpty == nil && hoursPerTerm.nonEmpty == nil && !confirmedInRetendo
    }
}

struct DoctoralSupervisionPeriod: Codable, Hashable, Identifiable {
    var id: String
    var semesterLabel: String
    var from: String
    var to: String
    var hoursPerSemester: String
    var confirmedInRetendo: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case semesterLabel
        case semester
        case from
        case to
        case hoursPerSemester
        case hoursPerTerm
        case confirmedInRetendo
    }

    init(
        id: String = UUID().uuidString,
        semesterLabel: String = "",
        from: String = "",
        to: String = "",
        hoursPerSemester: String = "",
        confirmedInRetendo: Bool = false
    ) {
        self.id = id
        self.semesterLabel = semesterLabel
        self.from = from
        self.to = to
        self.hoursPerSemester = hoursPerSemester
        self.confirmedInRetendo = confirmedInRetendo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            semesterLabel: try container.decodeIfPresent(String.self, forKey: .semesterLabel)
                ?? container.decodeIfPresent(String.self, forKey: .semester)
                ?? "",
            from: try container.decodeIfPresent(String.self, forKey: .from) ?? "",
            to: try container.decodeIfPresent(String.self, forKey: .to) ?? "",
            hoursPerSemester: try container.decodeIfPresent(String.self, forKey: .hoursPerSemester)
                ?? container.decodeIfPresent(String.self, forKey: .hoursPerTerm)
                ?? "",
            confirmedInRetendo: try container.decodeIfPresent(Bool.self, forKey: .confirmedInRetendo) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(semesterLabel, forKey: .semesterLabel)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(hoursPerSemester, forKey: .hoursPerSemester)
        try container.encode(confirmedInRetendo, forKey: .confirmedInRetendo)
    }

    mutating func normalize() {
        from = DateParsers.canonicalizedDayInput(from)
        to = DateParsers.canonicalizedDayInput(to)
        semesterLabel = semesterLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if semesterLabel.isEmpty {
            semesterLabel = doctoralSemesterLabel(from: from, to: to)
        }
        hoursPerSemester = hoursPerSemester.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        semesterLabel.nonEmpty == nil &&
            from.nonEmpty == nil &&
            to.nonEmpty == nil &&
            hoursPerSemester.nonEmpty == nil &&
            !confirmedInRetendo
    }
}

/// One half-year (VT = Jan–Jun, HT = Jul–Dec) that a supervision period
/// covers, and how large a share of it (by days).
struct DoctoralSupervisionTermShare: Equatable {
    let year: Int
    /// 1 = spring (Jan–Jun), 2 = autumn (Jul–Dec).
    let half: Int
    /// Share of the half-year's days the period covers (0...1).
    let fraction: Double
    /// Share of the half-year's days the period covers up to and including
    /// the reference date (0...fraction).
    let fractionUntilReference: Double
    /// Last day of the half-year.
    let termEnd: Date
}

/// Round 7 (user decision): the hours on a supervision period are hours per
/// term. Round 12 (user decision 2026-09-30): the hours are counted in
/// proportion to days, per half-year: a whole VT or HT gives the full hours
/// per term, half of its days half the hours. Every view and export uses
/// this one rule.
extension DoctoralSupervisionPeriod {
    /// The half-years a period covers, from `from` to `to` (both days
    /// included). An empty `to` counts to the reference date. Empty when
    /// `from` is missing or later than the end.
    static func termShares(from rawFrom: String, to rawTo: String, referenceDate: Date) -> [DoctoralSupervisionTermShare] {
        let formatter = DateParsers.isoDay
        guard let rawStart = rawFrom.trimmedOrNil.flatMap({ formatter.date(from: $0) }) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone ?? TimeZone.current
        let reference = calendar.startOfDay(for: referenceDate)
        let start = calendar.startOfDay(for: rawStart)
        let end = calendar.startOfDay(for: rawTo.trimmedOrNil.flatMap({ formatter.date(from: $0) }) ?? reference)
        guard end >= start else { return [] }
        func dayCount(_ first: Date, _ last: Date) -> Int {
            (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        }
        var year = calendar.component(.year, from: start)
        var half = calendar.component(.month, from: start) <= 6 ? 1 : 2
        var shares: [DoctoralSupervisionTermShare] = []
        while shares.count < 400 {
            guard let termStart = calendar.date(from: DateComponents(year: year, month: half == 1 ? 1 : 7, day: 1)),
                  let termEnd = calendar.date(from: DateComponents(year: year, month: half == 1 ? 6 : 12, day: half == 1 ? 30 : 31)),
                  termStart <= end else { break }
            let first = max(start, termStart)
            let last = min(end, termEnd)
            let termDays = Double(dayCount(termStart, termEnd))
            let coveredUntilReference = min(last, reference) < first ? 0 : Double(dayCount(first, min(last, reference)))
            shares.append(DoctoralSupervisionTermShare(
                year: year,
                half: half,
                fraction: Double(dayCount(first, last)) / termDays,
                fractionUntilReference: coveredUntilReference / termDays,
                termEnd: termEnd
            ))
            if half == 1 {
                half = 2
            } else {
                half = 1
                year += 1
            }
        }
        return shares
    }

    /// Terms supervised so far: the shares of each half-year up to the
    /// reference date, rounded to one decimal. Zero when `from` is missing or
    /// later than the reference date.
    static func accruedTerms(from rawFrom: String, to rawTo: String, referenceDate: Date) -> Double {
        let terms = termShares(from: rawFrom, to: rawTo, referenceDate: referenceDate)
            .reduce(0) { $0 + $1.fractionUntilReference }
        return (terms * 10).rounded() / 10
    }

    /// Hours for this period by the one rule, optionally only in one
    /// calendar year and/or only up to the reference date. Zero without
    /// hours per term.
    func supervisionHours(inYear year: Int? = nil, untilReferenceDate: Bool, referenceDate: Date = Date()) -> Double {
        guard let hoursPerTerm = hoursPerTermValue else { return 0 }
        return Self.termShares(from: from, to: to, referenceDate: referenceDate)
            .filter { year == nil || $0.year == year }
            .reduce(0) { $0 + (untilReferenceDate ? $1.fractionUntilReference : $1.fraction) * hoursPerTerm }
    }

    /// Round 12 (user decision 2026-09-30): a period that is not confirmed in
    /// Retendo is marked red, whether it has ended, is running or lies ahead.
    var needsRetendoConfirmation: Bool {
        !isEmpty && !confirmedInRetendo
    }

    /// The hours per term as a number, or nil when none (or not a positive number) is entered.
    var hoursPerTermValue: Double? {
        guard let value = GrantParsing.numericValue(from: hoursPerSemester), value > 0 else { return nil }
        return value
    }

    /// Hours so far for this period, rounded to whole hours. Nil when no hours
    /// per term are entered; zero when the start date is missing or in the future.
    func accruedSupervisionHours(referenceDate: Date = Date()) -> Double? {
        guard hoursPerTermValue != nil else { return nil }
        return supervisionHours(untilReferenceDate: true, referenceDate: referenceDate).rounded()
    }

    /// True when the count for this period stops at the reference date
    /// (no end date, or an end date later than the reference date).
    func accruesUntilReferenceDate(_ referenceDate: Date = Date()) -> Bool {
        guard let end = to.trimmedOrNil.flatMap({ DateParsers.isoDay.date(from: $0) }) else { return true }
        return end > referenceDate
    }
}

extension DoctoralCandidateRecord {
    /// The user's supervision hours so far: the sum over all periods with
    /// hours per term. Nil when no period has hours per term entered.
    func accruedSupervisionHours(referenceDate: Date = Date()) -> Double? {
        let values = supervisionPeriods
            .filter { !$0.isEmpty }
            .compactMap { $0.accruedSupervisionHours(referenceDate: referenceDate) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }
}

struct DoctoralSupervisorLink: Codable, Hashable, Identifiable {
    var id: String
    var authorID: String?
    var name: String
    var from: String
    var to: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorID
        case name
        case from
        case to
    }

    init(
        id: String = UUID().uuidString,
        authorID: String? = nil,
        name: String = "",
        from: String = "",
        to: String = ""
    ) {
        self.id = id
        self.authorID = authorID
        self.name = name
        self.from = from
        self.to = to
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            authorID: try container.decodeIfPresent(String.self, forKey: .authorID),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            from: try container.decodeIfPresent(String.self, forKey: .from) ?? "",
            to: try container.decodeIfPresent(String.self, forKey: .to) ?? ""
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(authorID, forKey: .authorID)
        try container.encode(name, forKey: .name)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
    }

    mutating func normalize() {
        authorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        from = DateParsers.canonicalizedDayInput(from)
        to = DateParsers.canonicalizedDayInput(to)
    }

    var isEmpty: Bool {
        authorID == nil &&
            name.nonEmpty == nil &&
            from.nonEmpty == nil &&
            to.nonEmpty == nil
    }
}

struct DoctoralCandidateRecord: Codable, Hashable, Identifiable {
    var id: String
    var candidateAuthorID: String?
    var candidateName: String
    var doctoralProjectName: String
    var institutionID: String?
    var institution: String
    var admissionDate: String
    var admissionDatePreliminary: Bool
    /// "Genomfört" for the admission, chosen in the timeline popover. Nil
    /// means not marked (preliminary or booked, see the preliminary flag).
    var admissionOutcomeRaw: String?
    var planningSeminarDate: String
    var planningSeminarDatePreliminary: Bool
    /// "Genomfört" for the planning seminar, chosen in the timeline popover.
    var planningSeminarOutcomeRaw: String?
    var estimatedHalftimeDate: String
    var estimatedHalftimeDatePreliminary: Bool
    var halftimeDate: String
    var halftimeDatePreliminary: Bool
    var halftimeOutcomeRaw: String?
    var disputationDate: String
    var disputationDatePreliminary: Bool
    var plannedDisputationDate: String
    var plannedDisputationDatePreliminary: Bool
    var plannedDisputationOutcomeRaw: String?
    var linkedProjectID: String?
    var linkedPublicationIDs: [String]
    var eISPLink: String
    var documents: [DoctoralCandidateDocument]
    var courses: [DoctoralCandidateCourse]
    var supervisors: [DoctoralSupervisorLink]
    var supervisionPeriods: [DoctoralSupervisionPeriod]
    var tasks: [ProjectTaskItem]
    var notes: String
    var sourceAssignmentIDs: [String]
    var isEditingLocked: Bool
    /// No longer used (round 7, user decision): the teaching merits export sums
    /// the hours per term on the supervision periods instead. Still read so
    /// data saved by the earlier version loads; cleared on normalize, so it is
    /// dropped the next time the candidate is saved.
    var teachingMeritSupervisionHours: String?

    enum CodingKeys: String, CodingKey {
        case id
        case candidateAuthorID
        case candidateName
        case studentName
        case doctoralProjectName
        case institutionID
        case institution
        case admissionDate
        case admissionDatePreliminary
        case admissionOutcomeRaw
        case planningSeminarDate
        case planningSeminarDatePreliminary
        case planningSeminarOutcomeRaw
        case estimatedHalftimeDate
        case estimatedHalftimeDatePreliminary
        case halftimeDate
        case halftimeDatePreliminary
        case halftimeOutcomeRaw
        case disputationDate
        case disputationDatePreliminary
        case plannedDisputationDate
        case plannedDisputationDatePreliminary
        case plannedDisputationOutcomeRaw
        case linkedProjectID
        case linkedPublicationIDs
        case eISPLink
        case documents
        case courses
        case supervisors
        case supervisionPeriods
        case tasks
        case notes
        case sourceAssignmentIDs
        case isEditingLocked
        case teachingMeritSupervisionHours
    }

    init(
        id: String = UUID().uuidString,
        candidateAuthorID: String? = nil,
        candidateName: String = "",
        doctoralProjectName: String = "",
        institutionID: String? = nil,
        institution: String = "",
        admissionDate: String = "",
        admissionDatePreliminary: Bool = false,
        admissionOutcomeRaw: String? = nil,
        planningSeminarDate: String = "",
        planningSeminarDatePreliminary: Bool = false,
        planningSeminarOutcomeRaw: String? = nil,
        estimatedHalftimeDate: String = "",
        estimatedHalftimeDatePreliminary: Bool = false,
        halftimeDate: String = "",
        halftimeDatePreliminary: Bool = false,
        halftimeOutcomeRaw: String? = nil,
        disputationDate: String = "",
        disputationDatePreliminary: Bool = false,
        plannedDisputationDate: String = "",
        plannedDisputationDatePreliminary: Bool = false,
        plannedDisputationOutcomeRaw: String? = nil,
        linkedProjectID: String? = nil,
        linkedPublicationIDs: [String] = [],
        eISPLink: String = "",
        documents: [DoctoralCandidateDocument] = [],
        courses: [DoctoralCandidateCourse] = [],
        supervisors: [DoctoralSupervisorLink] = [],
        supervisionPeriods: [DoctoralSupervisionPeriod] = [],
        tasks: [ProjectTaskItem] = [],
        notes: String = "",
        sourceAssignmentIDs: [String] = [],
        isEditingLocked: Bool = false,
        teachingMeritSupervisionHours: String? = nil
    ) {
        self.id = id
        self.candidateAuthorID = candidateAuthorID
        self.candidateName = candidateName
        self.doctoralProjectName = doctoralProjectName
        self.institutionID = institutionID
        self.institution = institution
        self.admissionDate = admissionDate
        self.admissionDatePreliminary = admissionDatePreliminary
        self.admissionOutcomeRaw = admissionOutcomeRaw
        self.planningSeminarDate = planningSeminarDate
        self.planningSeminarDatePreliminary = planningSeminarDatePreliminary
        self.planningSeminarOutcomeRaw = planningSeminarOutcomeRaw
        self.estimatedHalftimeDate = estimatedHalftimeDate
        self.estimatedHalftimeDatePreliminary = estimatedHalftimeDatePreliminary
        self.halftimeDate = halftimeDate
        self.halftimeDatePreliminary = halftimeDatePreliminary
        self.halftimeOutcomeRaw = halftimeOutcomeRaw
        self.disputationDate = disputationDate
        self.disputationDatePreliminary = disputationDatePreliminary
        self.plannedDisputationDate = plannedDisputationDate
        self.plannedDisputationDatePreliminary = plannedDisputationDatePreliminary
        self.plannedDisputationOutcomeRaw = plannedDisputationOutcomeRaw
        self.linkedProjectID = linkedProjectID
        self.linkedPublicationIDs = linkedPublicationIDs
        self.eISPLink = eISPLink
        self.documents = documents
        self.courses = courses
        self.supervisors = supervisors
        self.supervisionPeriods = supervisionPeriods
        self.tasks = tasks
        self.notes = notes
        self.sourceAssignmentIDs = sourceAssignmentIDs
        self.isEditingLocked = isEditingLocked
        self.teachingMeritSupervisionHours = teachingMeritSupervisionHours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedHalftimeDate = try container.decodeIfPresent(String.self, forKey: .halftimeDate) ?? ""
        let decodedHalftimeOutcomeRaw = try container.decodeIfPresent(String.self, forKey: .halftimeOutcomeRaw)
        let decodedEstimatedHalftimeDate = try container.decodeIfPresent(String.self, forKey: .estimatedHalftimeDate)
        let migratedEstimatedHalftimeDate = decodedEstimatedHalftimeDate
            ?? (decodedHalftimeOutcomeRaw == nil ? decodedHalftimeDate : "")
        let migratedHalftimeDate = decodedEstimatedHalftimeDate == nil && decodedHalftimeOutcomeRaw == nil
            ? ""
            : decodedHalftimeDate

        let decodedPlannedDisputationDate = try container.decodeIfPresent(String.self, forKey: .plannedDisputationDate) ?? ""
        let decodedDisputationDate = try container.decodeIfPresent(String.self, forKey: .disputationDate)
        let decodedDisputationOutcomeRaw = try container.decodeIfPresent(String.self, forKey: .plannedDisputationOutcomeRaw)
        let migratedDisputationDate = decodedDisputationDate
            ?? (decodedDisputationOutcomeRaw == nil ? "" : decodedPlannedDisputationDate)
        let migratedPlannedDisputationDate = decodedDisputationDate == nil && decodedDisputationOutcomeRaw != nil
            ? ""
            : decodedPlannedDisputationDate

        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            candidateAuthorID: try container.decodeIfPresent(String.self, forKey: .candidateAuthorID),
            candidateName: try container.decodeIfPresent(String.self, forKey: .candidateName)
                ?? container.decodeIfPresent(String.self, forKey: .studentName)
                ?? "",
            doctoralProjectName: try container.decodeIfPresent(String.self, forKey: .doctoralProjectName) ?? "",
            institutionID: try container.decodeIfPresent(String.self, forKey: .institutionID),
            institution: try container.decodeIfPresent(String.self, forKey: .institution) ?? "",
            admissionDate: try container.decodeIfPresent(String.self, forKey: .admissionDate) ?? "",
            admissionDatePreliminary: try container.decodeIfPresent(Bool.self, forKey: .admissionDatePreliminary) ?? false,
            admissionOutcomeRaw: try container.decodeIfPresent(String.self, forKey: .admissionOutcomeRaw),
            planningSeminarDate: try container.decodeIfPresent(String.self, forKey: .planningSeminarDate) ?? "",
            planningSeminarDatePreliminary: try container.decodeIfPresent(Bool.self, forKey: .planningSeminarDatePreliminary) ?? false,
            planningSeminarOutcomeRaw: try container.decodeIfPresent(String.self, forKey: .planningSeminarOutcomeRaw),
            estimatedHalftimeDate: migratedEstimatedHalftimeDate,
            estimatedHalftimeDatePreliminary: try container.decodeIfPresent(Bool.self, forKey: .estimatedHalftimeDatePreliminary)
                ?? (decodedEstimatedHalftimeDate == nil ? (try container.decodeIfPresent(Bool.self, forKey: .halftimeDatePreliminary) ?? false) : false),
            halftimeDate: migratedHalftimeDate,
            halftimeDatePreliminary: try container.decodeIfPresent(Bool.self, forKey: .halftimeDatePreliminary) ?? false,
            halftimeOutcomeRaw: decodedHalftimeOutcomeRaw,
            disputationDate: migratedDisputationDate,
            disputationDatePreliminary: try container.decodeIfPresent(Bool.self, forKey: .disputationDatePreliminary) ?? false,
            plannedDisputationDate: migratedPlannedDisputationDate,
            plannedDisputationDatePreliminary: try container.decodeIfPresent(Bool.self, forKey: .plannedDisputationDatePreliminary) ?? false,
            plannedDisputationOutcomeRaw: decodedDisputationOutcomeRaw,
            linkedProjectID: try container.decodeIfPresent(String.self, forKey: .linkedProjectID),
            linkedPublicationIDs: try container.decodeIfPresent([String].self, forKey: .linkedPublicationIDs) ?? [],
            eISPLink: try container.decodeIfPresent(String.self, forKey: .eISPLink) ?? "",
            documents: try container.decodeIfPresent([DoctoralCandidateDocument].self, forKey: .documents) ?? [],
            courses: try container.decodeIfPresent([DoctoralCandidateCourse].self, forKey: .courses) ?? [],
            supervisors: try container.decodeIfPresent([DoctoralSupervisorLink].self, forKey: .supervisors) ?? [],
            supervisionPeriods: try container.decodeIfPresent([DoctoralSupervisionPeriod].self, forKey: .supervisionPeriods) ?? [],
            tasks: try container.decodeIfPresent([ProjectTaskItem].self, forKey: .tasks) ?? [],
            notes: try container.decodeIfPresent(String.self, forKey: .notes) ?? "",
            sourceAssignmentIDs: try container.decodeIfPresent([String].self, forKey: .sourceAssignmentIDs) ?? [],
            isEditingLocked: try container.decodeIfPresent(Bool.self, forKey: .isEditingLocked) ?? false,
            teachingMeritSupervisionHours: try container.decodeIfPresent(String.self, forKey: .teachingMeritSupervisionHours)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(candidateAuthorID, forKey: .candidateAuthorID)
        try container.encode(candidateName, forKey: .candidateName)
        try container.encode(doctoralProjectName, forKey: .doctoralProjectName)
        try container.encodeIfPresent(institutionID, forKey: .institutionID)
        try container.encode(institution, forKey: .institution)
        try container.encode(admissionDate, forKey: .admissionDate)
        try container.encode(admissionDatePreliminary, forKey: .admissionDatePreliminary)
        try container.encodeIfPresent(admissionOutcomeRaw, forKey: .admissionOutcomeRaw)
        try container.encode(planningSeminarDate, forKey: .planningSeminarDate)
        try container.encode(planningSeminarDatePreliminary, forKey: .planningSeminarDatePreliminary)
        try container.encodeIfPresent(planningSeminarOutcomeRaw, forKey: .planningSeminarOutcomeRaw)
        try container.encode(estimatedHalftimeDate, forKey: .estimatedHalftimeDate)
        try container.encode(estimatedHalftimeDatePreliminary, forKey: .estimatedHalftimeDatePreliminary)
        try container.encode(halftimeDate, forKey: .halftimeDate)
        try container.encode(halftimeDatePreliminary, forKey: .halftimeDatePreliminary)
        try container.encodeIfPresent(halftimeOutcomeRaw, forKey: .halftimeOutcomeRaw)
        try container.encode(disputationDate, forKey: .disputationDate)
        try container.encode(disputationDatePreliminary, forKey: .disputationDatePreliminary)
        try container.encode(plannedDisputationDate, forKey: .plannedDisputationDate)
        try container.encode(plannedDisputationDatePreliminary, forKey: .plannedDisputationDatePreliminary)
        try container.encodeIfPresent(plannedDisputationOutcomeRaw, forKey: .plannedDisputationOutcomeRaw)
        try container.encodeIfPresent(linkedProjectID, forKey: .linkedProjectID)
        try container.encode(linkedPublicationIDs, forKey: .linkedPublicationIDs)
        if !eISPLink.isEmpty {
            try container.encode(eISPLink, forKey: .eISPLink)
        }
        if !documents.isEmpty {
            try container.encode(documents, forKey: .documents)
        }
        if !courses.isEmpty {
            try container.encode(courses, forKey: .courses)
        }
        try container.encode(supervisors, forKey: .supervisors)
        try container.encode(supervisionPeriods, forKey: .supervisionPeriods)
        // `tasks` was never exposed in the course UI. Keep decoding it so an
        // older database can be migrated, but do not write this obsolete
        // host-owned list back after the central task migration.
        try container.encode(notes, forKey: .notes)
        try container.encode(sourceAssignmentIDs, forKey: .sourceAssignmentIDs)
        try container.encode(isEditingLocked, forKey: .isEditingLocked)
        try container.encodeIfPresent(teachingMeritSupervisionHours, forKey: .teachingMeritSupervisionHours)
    }

    mutating func normalize() {
        candidateAuthorID = candidateAuthorID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        candidateName = candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        doctoralProjectName = doctoralProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        institutionID = institutionID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        institution = institution.trimmingCharacters(in: .whitespacesAndNewlines)
        admissionDate = DateParsers.canonicalizedDayInput(admissionDate)
        admissionOutcomeRaw = DoctoralMilestoneOutcome(rawValue: admissionOutcomeRaw ?? "")?.rawValue
        planningSeminarDate = DateParsers.canonicalizedDayInput(planningSeminarDate)
        planningSeminarOutcomeRaw = DoctoralMilestoneOutcome(rawValue: planningSeminarOutcomeRaw ?? "")?.rawValue
        estimatedHalftimeDate = DateParsers.canonicalizedDayInput(estimatedHalftimeDate)
        halftimeDate = DateParsers.canonicalizedDayInput(halftimeDate)
        halftimeOutcomeRaw = DoctoralMilestoneOutcome(rawValue: halftimeOutcomeRaw ?? "")?.rawValue
        disputationDate = DateParsers.canonicalizedDayInput(disputationDate)
        plannedDisputationDate = DateParsers.canonicalizedDayInput(plannedDisputationDate)
        plannedDisputationOutcomeRaw = DoctoralMilestoneOutcome(rawValue: plannedDisputationOutcomeRaw ?? "")?.rawValue
        linkedProjectID = linkedProjectID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        linkedPublicationIDs = Array(NSOrderedSet(array: linkedPublicationIDs.compactMap { $0.trimmedOrNil })) as? [String] ?? linkedPublicationIDs
        eISPLink = eISPLink.trimmingCharacters(in: .whitespacesAndNewlines)
        documents = documents
            .map {
                var document = $0
                document.normalize()
                return document
            }
            .filter { !$0.isEmpty }
        courses = courses
            .map {
                var course = $0
                course.normalize()
                return course
            }
            .filter { !$0.isEmpty }
            .sorted(by: doctoralCandidateCourseSortOrder)
        supervisors = supervisors
            .map {
                var supervisor = $0
                supervisor.normalize()
                return supervisor
            }
            .filter { !$0.isEmpty }
        supervisionPeriods = supervisionPeriods
            .map {
                var period = $0
                period.normalize()
                return period
            }
            .filter { !$0.isEmpty }
            .sorted(by: doctoralSupervisionPeriodSortOrder)
        tasks = tasks
            .map { task in
                var copy = task
                copy.createdOn = DateParsers.canonicalizedDayInput(copy.createdOn)
                copy.updatedOn = DateParsers.canonicalizedDayInput(copy.updatedOn)
                copy.deadline = DateParsers.canonicalizedDayInput(copy.deadline)
                copy.comment = copy.comment.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.completedOn = copy.completedOn
                    .map(DateParsers.canonicalizedDayInput(_:))
                    .flatMap { $0.trimmedOrNil }
                if copy.completedOn == nil {
                    copy.completedOn = nil
                }
                return copy
            }
            .filter { !$0.isEmpty }
        notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceAssignmentIDs = Array(NSOrderedSet(array: sourceAssignmentIDs.compactMap { $0.trimmedOrNil })) as? [String] ?? sourceAssignmentIDs
        teachingMeritSupervisionHours = nil
    }

    var hasAllHardMilestones: Bool {
        admissionDate.nonEmpty != nil &&
            halftimeDate.nonEmpty != nil &&
            disputationDate.nonEmpty != nil
    }
}

struct DoctoralCandidateDocument: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var date: String
    var filename: String?
    var path: String?

    init(
        id: String = UUID().uuidString,
        title: String = "",
        date: String = "",
        filename: String? = nil,
        path: String? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.filename = filename
        self.path = path
    }

    mutating func normalize() {
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        date = DateParsers.canonicalizedDayInput(date)
        filename = filename?.trimmedOrNil
        path = path?.trimmedOrNil
    }

    var isEmpty: Bool {
        title.trimmedOrNil == nil &&
            date.trimmedOrNil == nil &&
            filename?.trimmedOrNil == nil &&
            path?.trimmedOrNil == nil
    }
}

struct DoctoralCandidateCourse: Codable, Hashable, Identifiable {
    var id: String
    var year: String
    var title: String
    var credits: String
    var completedOn: String?

    init(
        id: String = UUID().uuidString,
        year: String = "",
        title: String = "",
        credits: String = "",
        completedOn: String? = nil
    ) {
        self.id = id
        self.year = year
        self.title = title
        self.credits = credits
        self.completedOn = completedOn
    }

    mutating func normalize() {
        year = year.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        credits = AppFieldParsers.canonicalDecimal(credits)
        completedOn = completedOn
            .map(DateParsers.canonicalizedDayInput(_:))
            .flatMap(\.trimmedOrNil)
    }

    var isEmpty: Bool {
        year.trimmedOrNil == nil &&
            title.trimmedOrNil == nil &&
            credits.trimmedOrNil == nil &&
            completedOn?.trimmedOrNil == nil
    }
}

func doctoralCandidateCourseSortOrder(
    _ lhs: DoctoralCandidateCourse,
    _ rhs: DoctoralCandidateCourse
) -> Bool {
    let lhsYear = Int(lhs.year.trimmingCharacters(in: .whitespacesAndNewlines))
    let rhsYear = Int(rhs.year.trimmingCharacters(in: .whitespacesAndNewlines))

    switch (lhsYear, rhsYear) {
    case let (lhsYear?, rhsYear?) where lhsYear != rhsYear:
        return lhsYear < rhsYear
    case (_?, nil):
        return true
    case (nil, _?):
        return false
    default:
        break
    }

    let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
    if titleOrder != .orderedSame {
        return titleOrder == .orderedAscending
    }
    return lhs.id < rhs.id
}

func doctoralCandidateCoursesRestoringProvisionalRows(
    normalizedCourses: [DoctoralCandidateCourse],
    draftCourses: [DoctoralCandidateCourse],
    provisionalCourseIDs: Set<String>
) -> [DoctoralCandidateCourse] {
    var restored = normalizedCourses
    let existingIDs = Set(restored.map(\.id))
    restored.append(contentsOf: draftCourses.filter {
        provisionalCourseIDs.contains($0.id)
            && $0.isEmpty
            && !existingIDs.contains($0.id)
    })
    return restored.sorted(by: doctoralCandidateCourseSortOrder)
}

enum DoctoralMilestoneOutcome: String, Codable, Hashable, CaseIterable, Identifiable {
    case completed
    case endedBefore

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .completed:
            return language.text("Completed", "Genomfört")
        case .endedBefore:
            return language.text("Ended before", "Avslutat innan")
        }
    }
}

func doctoralSupervisionPeriodSortOrder(_ lhs: DoctoralSupervisionPeriod, _ rhs: DoctoralSupervisionPeriod) -> Bool {
    let lhsFrom = lhs.from.nonEmpty ?? "9999-12-31"
    let rhsFrom = rhs.from.nonEmpty ?? "9999-12-31"
    if lhsFrom != rhsFrom { return lhsFrom < rhsFrom }
    let lhsTo = lhs.to.nonEmpty ?? "9999-12-31"
    let rhsTo = rhs.to.nonEmpty ?? "9999-12-31"
    if lhsTo != rhsTo { return lhsTo < rhsTo }
    let lhsSemester = lhs.semesterLabel.nonEmpty ?? "ZZZZ"
    let rhsSemester = rhs.semesterLabel.nonEmpty ?? "ZZZZ"
    if lhsSemester != rhsSemester { return lhsSemester.localizedStandardCompare(rhsSemester) == .orderedAscending }
    return lhs.id < rhs.id
}

func doctoralSemesterLabel(from rawFrom: String, to rawTo: String) -> String {
    let from = rawFrom.trimmingCharacters(in: .whitespacesAndNewlines)
    let to = rawTo.trimmingCharacters(in: .whitespacesAndNewlines)
    let anchor = from.nonEmpty ?? to
    guard anchor.count >= 7 else { return "" }
    let year = String(anchor.prefix(4))
    let monthText = String(anchor.dropFirst(5).prefix(2))
    guard let month = Int(monthText) else { return year }
    return month <= 6 ? "VT \(year)" : "HT \(year)"
}


/// F7 step 1: a course code with a validity period. Nothing uses it yet; the
/// editor and the lookup arrive in step 2, once the stored records are verified
/// to survive the added fields.
struct TeachingCourseCodeEntry: Codable, Hashable, Identifiable {
    var id: String
    var code: String
    /// ISO day, inclusive. Empty means "since always".
    var validFrom: String
    /// ISO day, inclusive. Empty means "still valid".
    var validTo: String

    init(id: String = UUID().uuidString, code: String = "", validFrom: String = "", validTo: String = "") {
        self.id = id
        self.code = code
        self.validFrom = validFrom
        self.validTo = validTo
    }

    mutating func normalize() {
        id = id.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? UUID().uuidString
        code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        validFrom = validFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        validTo = validTo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func covers(day: String) -> Bool {
        let day = day.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !day.isEmpty else { return validTo.isEmpty }
        if !validFrom.isEmpty, day < validFrom { return false }
        if !validTo.isEmpty, day > validTo { return false }
        return true
    }
}

struct TeachingCourse: Codable, Hashable, Identifiable {
    var id: String
    var nameSv: String
    var nameEn: String
    var contextType: TeachingContextType?
    var programSv: String
    var programEn: String
    var termSv: String
    var termEn: String
    var term: String
    var courseCode: String
    /// F7: every code the course has had. courseCode stays the current one.
    var courseCodes: [TeachingCourseCodeEntry]
    /// F4: the programme row's id. Filled in by the migration in step 2.
    var programID: String?
    /// F4: validity of the catalogue row itself (ISO days; empty = open).
    var validFrom: String
    var validTo: String
    var institutionID: String?
    var institution: String
    var credits: String
    var teachingLanguage: String
    var level: TeachingCourseLevel?
    var defaultAssignmentKind: TeachingAssignmentKind?
    var defaultRoles: [TeachingAssignmentRole]
    var defaultDeliveryMode: TeachingDeliveryMode?
    var defaultPeriods: [TeachingAssignmentPeriod]
    var tasks: [PublicationTaskItem]
    /// Round 7 (user decision): the checkbox "Klinisk undervisning". A course
    /// without its own programme and term is placed under "Klinisk
    /// undervisning". Replaces the old rule that looked for a word ("region")
    /// in the organization name.
    var isClinicalTeaching: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameSv
        case nameEn
        case contextType
        case program
        case programSv
        case programEn
        case termSv
        case termEn
        case term
        case courseCode
        case courseCodes
        case programID
        case validFrom
        case validTo
        case institutionID
        case institution
        case credits
        case teachingLanguage
        case level
        case defaultAssignmentKind
        case defaultRoles
        case defaultDeliveryMode
        case defaultPeriods
        case tasks
        case isClinicalTeaching
    }

    init(
        id: String = UUID().uuidString,
        name: String = "",
        nameSv: String? = nil,
        nameEn: String? = nil,
        contextType: TeachingContextType? = nil,
        programSv: String? = nil,
        programEn: String? = nil,
        termSv: String? = nil,
        termEn: String? = nil,
        term: String = "",
        courseCode: String = "",
        courseCodes: [TeachingCourseCodeEntry] = [],
        programID: String? = nil,
        validFrom: String = "",
        validTo: String = "",
        institutionID: String? = nil,
        institution: String = "",
        credits: String = "",
        teachingLanguage: String = "",
        level: TeachingCourseLevel? = nil,
        defaultAssignmentKind: TeachingAssignmentKind? = nil,
        defaultRoles: [TeachingAssignmentRole] = [],
        defaultDeliveryMode: TeachingDeliveryMode? = nil,
        defaultPeriods: [TeachingAssignmentPeriod] = [],
        tasks: [PublicationTaskItem] = [],
        isClinicalTeaching: Bool = false
    ) {
        self.id = id
        self.nameSv = nameSv ?? name
        self.nameEn = nameEn ?? name
        self.contextType = contextType
        self.programSv = programSv ?? ""
        self.programEn = programEn ?? ""
        self.termSv = termSv ?? term
        self.termEn = termEn ?? term
        self.term = termSv ?? term
        self.courseCode = courseCode
        self.courseCodes = courseCodes
        self.programID = programID
        self.validFrom = validFrom
        self.validTo = validTo
        self.institutionID = institutionID
        self.institution = institution
        self.credits = credits
        self.teachingLanguage = teachingLanguage
        self.level = level
        self.defaultAssignmentKind = defaultAssignmentKind
        self.defaultRoles = defaultRoles
        self.defaultDeliveryMode = defaultDeliveryMode
        self.defaultPeriods = defaultPeriods
        self.tasks = tasks
        self.isClinicalTeaching = isClinicalTeaching
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let legacyProgram = try container.decodeIfPresent(String.self, forKey: .program) ?? ""
        let programSv = try container.decodeIfPresent(String.self, forKey: .programSv) ?? legacyProgram
        let programEn = try container.decodeIfPresent(String.self, forKey: .programEn) ?? legacyProgram
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            name: legacy,
            nameSv: try container.decodeIfPresent(String.self, forKey: .nameSv),
            nameEn: try container.decodeIfPresent(String.self, forKey: .nameEn),
            contextType: try container.decodeIfPresent(TeachingContextType.self, forKey: .contextType),
            programSv: programSv,
            programEn: programEn,
            termSv: try container.decodeIfPresent(String.self, forKey: .termSv),
            termEn: try container.decodeIfPresent(String.self, forKey: .termEn),
            term: try container.decodeIfPresent(String.self, forKey: .term) ?? "",
            courseCode: try container.decodeIfPresent(String.self, forKey: .courseCode) ?? "",
            courseCodes: try container.decodeIfPresent([TeachingCourseCodeEntry].self, forKey: .courseCodes) ?? [],
            programID: try container.decodeIfPresent(String.self, forKey: .programID),
            validFrom: try container.decodeIfPresent(String.self, forKey: .validFrom) ?? "",
            validTo: try container.decodeIfPresent(String.self, forKey: .validTo) ?? "",
            institutionID: try container.decodeIfPresent(String.self, forKey: .institutionID),
            institution: try container.decodeIfPresent(String.self, forKey: .institution) ?? "",
            credits: try container.decodeIfPresent(String.self, forKey: .credits) ?? "",
            teachingLanguage: try container.decodeIfPresent(String.self, forKey: .teachingLanguage) ?? "",
            level: try container.decodeIfPresent(TeachingCourseLevel.self, forKey: .level),
            defaultAssignmentKind: try container.decodeIfPresent(TeachingAssignmentKind.self, forKey: .defaultAssignmentKind),
            defaultRoles: try container.decodeIfPresent([TeachingAssignmentRole].self, forKey: .defaultRoles) ?? [],
            defaultDeliveryMode: try container.decodeIfPresent(TeachingDeliveryMode.self, forKey: .defaultDeliveryMode),
            defaultPeriods: try container.decodeIfPresent([TeachingAssignmentPeriod].self, forKey: .defaultPeriods) ?? [],
            tasks: try container.decodeIfPresent([PublicationTaskItem].self, forKey: .tasks) ?? [],
            isClinicalTeaching: try container.decodeIfPresent(Bool.self, forKey: .isClinicalTeaching) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nameSv, forKey: .nameSv)
        try container.encode(nameEn, forKey: .nameEn)
        try container.encodeIfPresent(contextType, forKey: .contextType)
        try container.encode(programSv, forKey: .programSv)
        try container.encode(programEn, forKey: .programEn)
        try container.encode(termSv, forKey: .termSv)
        try container.encode(termEn, forKey: .termEn)
        try container.encode(term, forKey: .term)
        try container.encode(courseCode, forKey: .courseCode)
        try container.encode(courseCodes, forKey: .courseCodes)
        try container.encodeIfPresent(programID, forKey: .programID)
        try container.encode(validFrom, forKey: .validFrom)
        try container.encode(validTo, forKey: .validTo)
        try container.encodeIfPresent(institutionID, forKey: .institutionID)
        try container.encode(institution, forKey: .institution)
        try container.encode(credits, forKey: .credits)
        try container.encode(teachingLanguage, forKey: .teachingLanguage)
        try container.encode(level, forKey: .level)
        try container.encodeIfPresent(defaultAssignmentKind, forKey: .defaultAssignmentKind)
        try container.encode(defaultRoles, forKey: .defaultRoles)
        try container.encodeIfPresent(defaultDeliveryMode, forKey: .defaultDeliveryMode)
        try container.encode(defaultPeriods, forKey: .defaultPeriods)
        try container.encode(tasks, forKey: .tasks)
        if isClinicalTeaching {
            try container.encode(isClinicalTeaching, forKey: .isClinicalTeaching)
        }
    }

    mutating func normalize() {
        nameSv = nameSv.trimmingCharacters(in: .whitespacesAndNewlines)
        nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        institutionID = institutionID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        institution = institution.trimmingCharacters(in: .whitespacesAndNewlines)
        if contextType == nil && hasDerivedContextInputs {
            contextType = derivedTeachingContextType(
                nameSv: nameSv,
                nameEn: nameEn,
                term: termSv,
                courseCode: courseCode,
                credits: credits,
                level: level
            )
        }
        programSv = programSv.trimmingCharacters(in: .whitespacesAndNewlines)
        programEn = programEn.trimmingCharacters(in: .whitespacesAndNewlines)
        termSv = termSv.trimmingCharacters(in: .whitespacesAndNewlines)
        termEn = termEn.trimmingCharacters(in: .whitespacesAndNewlines)
        term = termSv
        courseCode = courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        programID = programID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        validFrom = validFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        validTo = validTo.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in courseCodes.indices {
            courseCodes[index].normalize()
        }
        courseCodes.removeAll { $0.code.isEmpty }
        // The current code is the open-ended one, and mirrors courseCode.
        if courseCodes.isEmpty, !courseCode.isEmpty {
            courseCodes = [TeachingCourseCodeEntry(id: id, code: courseCode)]
        } else if let current = courseCodes.first(where: { $0.validTo.isEmpty }) {
            courseCode = current.code
        }
        credits = credits.trimmingCharacters(in: .whitespacesAndNewlines)
        teachingLanguage = canonicalTeachingLanguage(teachingLanguage)
        defaultRoles = Array(NSOrderedSet(array: defaultRoles.map { TeachingAssignmentRole($0.rawValue) })) as? [TeachingAssignmentRole] ?? defaultRoles
        defaultPeriods = defaultPeriods.map {
            var period = $0
            period.normalize()
            return period
        }
        .filter { !$0.isEmpty }
        .sorted(by: teachingPeriodSortOrder)
        tasks = tasks.map {
            var task = $0
            task.normalize()
            return task
        }
    }

    var isEmpty: Bool {
        nameSv.nonEmpty == nil &&
            nameEn.nonEmpty == nil &&
            effectiveContextTypeForEmptiness == nil &&
            programSv.nonEmpty == nil &&
            programEn.nonEmpty == nil &&
            termSv.nonEmpty == nil &&
            termEn.nonEmpty == nil &&
            courseCode.nonEmpty == nil &&
            credits.nonEmpty == nil &&
            teachingLanguage.nonEmpty == nil &&
            level == nil &&
            defaultAssignmentKind == nil &&
            defaultRoles.isEmpty &&
            defaultDeliveryMode == nil &&
            defaultPeriods.isEmpty &&
            tasks.filter { !$0.isEmpty }.isEmpty
    }

    private var hasDerivedContextInputs: Bool {
        nameSv.nonEmpty != nil ||
            nameEn.nonEmpty != nil ||
            termSv.nonEmpty != nil ||
            termEn.nonEmpty != nil ||
            courseCode.nonEmpty != nil ||
            credits.nonEmpty != nil ||
            level != nil
    }

    private var effectiveContextTypeForEmptiness: TeachingContextType? {
        guard let contextType else { return nil }
        let hasOtherContent =
            nameSv.nonEmpty != nil ||
            nameEn.nonEmpty != nil ||
            programSv.nonEmpty != nil ||
            programEn.nonEmpty != nil ||
            termSv.nonEmpty != nil ||
            termEn.nonEmpty != nil ||
            courseCode.nonEmpty != nil ||
            credits.nonEmpty != nil ||
            teachingLanguage.nonEmpty != nil ||
            level != nil ||
            defaultAssignmentKind != nil ||
            !defaultRoles.isEmpty ||
            defaultDeliveryMode != nil ||
            !defaultPeriods.isEmpty ||
            tasks.contains(where: { !$0.isEmpty })
        if contextType == .other && !hasOtherContent {
            return nil
        }
        return contextType
    }

    var name: String {
        get { nameSv }
        set {
            nameSv = newValue
            nameEn = newValue
        }
    }

    var localizedTermFallback: String {
        termSv.nonEmpty ?? termEn
    }

    func localizedName(language: AppLanguage) -> String {
        localizedTeachingContentValue(language: language, swedish: nameSv, english: nameEn)
    }

    func localizedProgram(language: AppLanguage) -> String {
        localizedTeachingProgramArea(
            language: language,
            programSv: programSv,
            programEn: programEn,
            nameSv: nameSv,
            nameEn: nameEn,
            contextType: contextType,
            level: level,
            isClinicalTeaching: isClinicalTeaching,
            courseCode: courseCode,
            credits: credits,
            termSv: termSv,
            termEn: termEn
        )
    }

    /// True when this course is placed under "Klinisk undervisning" only by the
    /// old word rule (a word from the settings, "region" by default, in the
    /// organization name): the word matches, and ticking the checkbox changes
    /// the programme shown (so the course has no programme or term of its own
    /// and is not already clinical teaching by its type). Used by the one-time
    /// round 7 migration that ticks the checkbox for these courses, so nothing moves.
    func resolvesToClinicalTeachingByInstitutionWord(settings: WorkflowDefaultSettings) -> Bool {
        guard !isClinicalTeaching, settings.institutionIndicatesClinicalTeaching(institution) else { return false }
        var ticked = self
        ticked.isClinicalTeaching = true
        return ticked.localizedProgram(language: .swedish) != localizedProgram(language: .swedish)
            || ticked.localizedProgram(language: .english) != localizedProgram(language: .english)
    }

    mutating func setLocalizedName(_ value: String, language: AppLanguage) {
        if language == .swedish {
            nameSv = value
        } else {
            nameEn = value
        }
    }

    mutating func setLocalizedProgram(_ value: String, language: AppLanguage) {
        if language == .swedish {
            programSv = value
        } else {
            programEn = value
        }
    }

    func localizedTerm(language: AppLanguage) -> String {
        localizedTeachingContentValue(language: language, swedish: termSv, english: termEn)
    }

    mutating func setLocalizedTerm(_ value: String, language: AppLanguage) {
        if language == .swedish {
            termSv = value
        } else {
            termEn = value
        }
        term = termSv
    }
}

struct TeachingAssignment: Codable, Hashable, Identifiable {
    var id: String
    var authorID: String?
    var kind: TeachingAssignmentKind?
    var periods: [TeachingAssignmentPeriod]
    var contextID: String?
    var activityID: String?
    var activityName: String
    var reportCategory: TeachingReportCategory?
    /// F13: the teaching format by id; `activityTypeName` is its name, kept for display.
    var activityTypeID: String?
    var activityTypeName: String
    var roles: [TeachingAssignmentRole]
    /// F13: the student as a researcher, when the student is one; `studentName`
    /// stays the text shown and is the only value for everyone else.
    var studentAuthorID: String?
    var studentName: String
    var programName: String
    var participantForm: TeachingAssignmentCategory?
    var deliveryMode: TeachingDeliveryMode?
    var deliveryModes: [TeachingDeliveryMode]
    var comment: String
    var tasks: [PublicationTaskItem]

    enum CodingKeys: String, CodingKey {
        case id
        case authorID
        case kind
        case contextID
        case activityID
        case activityName
        case participantForm
        case from
        case to
        case isOngoing
        case confirmedInRetendo
        case periods
        case courseID
        case componentName
        case reportCategory
        case activityTypeID
        case activityTypeName
        case roles
        case studentAuthorID
        case studentName
        case programName
        case category
        case deliveryMode
        case deliveryModes
        case formats
        case hoursPerTerm
        case comment
        case tasks
    }

    init(
        id: String = UUID().uuidString,
        authorID: String? = nil,
        kind: TeachingAssignmentKind? = nil,
        periods: [TeachingAssignmentPeriod] = [],
        contextID: String? = nil,
        activityID: String? = nil,
        activityName: String = "",
        reportCategory: TeachingReportCategory? = nil,
        activityTypeID: String? = nil,
        activityTypeName: String = "",
        roles: [TeachingAssignmentRole] = [],
        studentAuthorID: String? = nil,
        studentName: String = "",
        programName: String = "",
        participantForm: TeachingAssignmentCategory? = nil,
        deliveryMode: TeachingDeliveryMode? = nil,
        deliveryModes: [TeachingDeliveryMode] = [],
        comment: String = "",
        tasks: [PublicationTaskItem] = []
    ) {
        self.id = id
        self.authorID = authorID
        self.kind = kind
        self.periods = periods
        self.contextID = contextID
        self.activityID = activityID
        self.activityName = activityName
        self.reportCategory = reportCategory
        self.activityTypeID = activityTypeID
        self.activityTypeName = activityTypeName
        self.roles = roles
        self.studentAuthorID = studentAuthorID
        self.studentName = studentName
        self.programName = programName
        self.participantForm = participantForm
        self.deliveryMode = deliveryMode
        self.deliveryModes = deliveryModes
        self.comment = comment
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyFormats = (try? container.decodeIfPresent([TeachingDefaultFormat].self, forKey: .formats))?.map(\.rawValue) ?? []
        let legacyFrom = try container.decodeIfPresent(String.self, forKey: .from) ?? ""
        let legacyTo = try container.decodeIfPresent(String.self, forKey: .to) ?? ""
        let legacyHoursPerTerm = try container.decodeIfPresent(String.self, forKey: .hoursPerTerm) ?? ""
        let legacyConfirmedInRetendo = try container.decodeIfPresent(Bool.self, forKey: .confirmedInRetendo) ?? false
        let decodedPeriods = try container.decodeIfPresent([TeachingAssignmentPeriod].self, forKey: .periods) ?? []
        let fallbackPeriods = (legacyFrom.trimmedOrNil != nil || legacyTo.trimmedOrNil != nil || legacyHoursPerTerm.trimmedOrNil != nil)
            ? [TeachingAssignmentPeriod(from: legacyFrom, to: legacyTo, hoursPerTerm: legacyHoursPerTerm, confirmedInRetendo: legacyConfirmedInRetendo)]
            : []
        var migratedPeriods = (decodedPeriods.isEmpty ? fallbackPeriods : decodedPeriods).map { period in
            guard period.hoursPerTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return period }
            var updated = period
            updated.hoursPerTerm = legacyHoursPerTerm
            return updated
        }
        if legacyConfirmedInRetendo && migratedPeriods.contains(where: { !$0.confirmedInRetendo }) && !migratedPeriods.contains(where: \.confirmedInRetendo) {
            migratedPeriods = migratedPeriods.map { period in
                var updated = period
                updated.confirmedInRetendo = true
                return updated
            }
        }
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            authorID: try container.decodeIfPresent(String.self, forKey: .authorID),
            kind: try container.decodeIfPresent(TeachingAssignmentKind.self, forKey: .kind),
            periods: migratedPeriods,
            contextID: try container.decodeIfPresent(String.self, forKey: .contextID)
                ?? container.decodeIfPresent(String.self, forKey: .courseID),
            activityID: try container.decodeIfPresent(String.self, forKey: .activityID),
            activityName: try container.decodeIfPresent(String.self, forKey: .activityName)
                ?? container.decodeIfPresent(String.self, forKey: .componentName)
                ?? "",
            reportCategory: try container.decodeIfPresent(TeachingReportCategory.self, forKey: .reportCategory),
            activityTypeID: try container.decodeIfPresent(String.self, forKey: .activityTypeID),
            activityTypeName: try container.decodeIfPresent(String.self, forKey: .activityTypeName) ?? ((try? container.decodeIfPresent([String].self, forKey: .formats)) ?? legacyFormats).first ?? "",
            roles: try container.decodeIfPresent([TeachingAssignmentRole].self, forKey: .roles) ?? [],
            studentAuthorID: try container.decodeIfPresent(String.self, forKey: .studentAuthorID),
            studentName: try container.decodeIfPresent(String.self, forKey: .studentName) ?? "",
            programName: try container.decodeIfPresent(String.self, forKey: .programName) ?? "",
            participantForm: try container.decodeIfPresent(TeachingAssignmentCategory.self, forKey: .participantForm)
                ?? container.decodeIfPresent(TeachingAssignmentCategory.self, forKey: .category),
            deliveryMode: try container.decodeIfPresent(TeachingDeliveryMode.self, forKey: .deliveryMode),
            deliveryModes: try container.decodeIfPresent([TeachingDeliveryMode].self, forKey: .deliveryModes) ?? [],
            comment: try container.decodeIfPresent(String.self, forKey: .comment) ?? "",
            tasks: try container.decodeIfPresent([PublicationTaskItem].self, forKey: .tasks) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(authorID, forKey: .authorID)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encode(periods, forKey: .periods)
        try container.encodeIfPresent(contextID, forKey: .contextID)
        try container.encodeIfPresent(activityID, forKey: .activityID)
        try container.encode(activityName, forKey: .activityName)
        try container.encodeIfPresent(reportCategory, forKey: .reportCategory)
        try container.encodeIfPresent(activityTypeID, forKey: .activityTypeID)
        try container.encode(activityTypeName, forKey: .activityTypeName)
        try container.encode(roles, forKey: .roles)
        try container.encodeIfPresent(studentAuthorID, forKey: .studentAuthorID)
        try container.encode(studentName, forKey: .studentName)
        try container.encode(programName, forKey: .programName)
        try container.encodeIfPresent(participantForm, forKey: .participantForm)
        try container.encodeIfPresent(deliveryMode, forKey: .deliveryMode)
        try container.encode(deliveryModes, forKey: .deliveryModes)
        try container.encode(comment, forKey: .comment)
        try container.encode(tasks, forKey: .tasks)
    }

    mutating func normalize() {
        periods = periods.map {
            var period = $0
            period.normalize()
            return period
        }
        .filter { !$0.isEmpty }
        .sorted(by: teachingPeriodSortOrder)

        authorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        contextID = contextID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        activityID = activityID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        activityName = activityName.trimmingCharacters(in: .whitespacesAndNewlines)
        activityTypeID = activityTypeID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        activityTypeName = activityTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
        roles = Array(NSOrderedSet(array: roles.map { TeachingAssignmentRole($0.rawValue) })) as? [TeachingAssignmentRole] ?? roles
        studentAuthorID = studentAuthorID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        studentName = studentName.trimmingCharacters(in: .whitespacesAndNewlines)
        programName = programName.trimmingCharacters(in: .whitespacesAndNewlines)
        deliveryModes = TeachingDeliveryMode.allCases.filter {
            deliveryModes.contains($0) || ($0 == deliveryMode && !deliveryModes.contains($0))
        }
        if deliveryMode == nil, deliveryModes.count == 1 {
            deliveryMode = deliveryModes.first
        }
        comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks = tasks.map {
            var task = $0
            task.normalize()
            return task
        }
    }

    var isEmpty: Bool {
        periods.filter { !$0.isEmpty }.isEmpty &&
            kind == nil &&
            contextID == nil &&
            activityID == nil &&
            activityName.nonEmpty == nil &&
            reportCategory == nil &&
            activityTypeName.nonEmpty == nil &&
            roles.isEmpty &&
            studentName.nonEmpty == nil &&
            programName.nonEmpty == nil &&
            participantForm == nil &&
            deliveryMode == nil &&
            deliveryModes.isEmpty &&
            comment.nonEmpty == nil &&
            tasks.filter { !$0.isEmpty }.isEmpty
    }

    var courseID: String? {
        get { contextID }
        set { contextID = newValue }
    }

    var componentName: String {
        get { activityName }
        set { activityName = newValue }
    }

    var category: TeachingAssignmentCategory? {
        get { participantForm }
        set { participantForm = newValue }
    }

    var from: String {
        periods.compactMap(\.from.nonEmpty).sorted().first ?? ""
    }

    var to: String {
        periods.compactMap(\.to.nonEmpty).sorted().last ?? ""
    }

    var isOngoing: Bool {
        periods.contains { $0.from.nonEmpty != nil && $0.to.nonEmpty == nil }
    }

    var confirmedInRetendo: Bool {
        periods.contains(where: \.confirmedInRetendo)
    }

    var formats: [String] {
        activityTypeName.nonEmpty.map { [$0] } ?? []
    }

    var hoursPerTerm: String {
        let distinctHours = Array(NSOrderedSet(array: periods.compactMap(\.hoursPerTerm.nonEmpty))) as? [String] ?? []
        return distinctHours.count == 1 ? (distinctHours.first ?? "") : ""
    }
}

func teachingPeriodSortOrder(_ lhs: TeachingAssignmentPeriod, _ rhs: TeachingAssignmentPeriod) -> Bool {
    let lhsFrom = lhs.from.nonEmpty ?? "9999-12-31"
    let rhsFrom = rhs.from.nonEmpty ?? "9999-12-31"
    if lhsFrom != rhsFrom { return lhsFrom < rhsFrom }

    let lhsTo = lhs.to.nonEmpty ?? "9999-12-31"
    let rhsTo = rhs.to.nonEmpty ?? "9999-12-31"
    if lhsTo != rhsTo { return lhsTo < rhsTo }

    return lhs.id < rhs.id
}

func derivedTeachingContextType(
    nameSv: String,
    nameEn: String,
    term: String,
    courseCode: String,
    credits: String,
    level: TeachingCourseLevel?
) -> TeachingContextType {
    let name = "\(nameSv) \(nameEn)".lowercased()
    if name.contains("klinisk verksamhet") {
        return .clinicalTeaching
    }
    if name.contains("utvecklingsarbete") {
        return .courseAdministration
    }
    if name.contains("forskarutbildning") {
        return .doctoralEducation
    }
    if name.contains("forskarlinjen") || name.contains("research track") {
        return .programTrack
    }
    if courseCode.trimmedOrNil != nil || term.trimmedOrNil != nil || credits.trimmedOrNil != nil || level != nil {
        return .course
    }
    return .other
}

func inferredTeachingAssignmentKind(
    assignment: TeachingAssignment,
    context: TeachingCourse?
) -> TeachingAssignmentKind {
    let activity = assignment.activityName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let activityType = assignment.activityTypeName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let contextName = context?.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let contextType = context?.contextType

    if contextType == .courseAdministration ||
        assignment.reportCategory == .courseAdministration ||
        activity.contains("utvecklingsarbete") ||
        activityType.contains("utvecklingsarbete") {
        return .development
    }

    if contextType == .clinicalTeaching {
        return .clinical
    }

    if assignment.reportCategory == .thesisSupervision ||
        assignment.reportCategory == .doctoralPrincipalSupervision ||
        assignment.reportCategory == .doctoralAssistantSupervision {
        return .supervision
    }

    if assignment.roles.contains(.principalSupervisor) ||
        assignment.roles.contains(.assistantSupervisor) ||
        activity.contains("examensarbete") ||
        activity.contains("fältstud") ||
        activity.contains("doktorand") ||
        contextName.contains("examensarbete") ||
        contextName.contains("forskar-at") ||
        contextName.contains("forskarlinjen") ||
        contextName.contains("forskningsförberedande") ||
        contextType == .doctoralEducation {
        return .supervision
    }

    return .teaching
}

func researcherDetailTeachingAssignmentIsListable(
    _ assignment: TeachingAssignment,
    courses: [TeachingCourse],
    components: [TeachingComponent],
    formats: [TeachingFormatOption]
) -> Bool {
    if researcherDetailTeachingAssignmentIsIndividual(
        assignment,
        components: components,
        formats: formats
    ) {
        return true
    }

    return researcherDetailTeachingAssignmentIsDoctoralStudent(
        assignment,
        courses: courses,
        components: components
    )
}

private func researcherDetailTeachingAssignmentIsIndividual(
    _ assignment: TeachingAssignment,
    components: [TeachingComponent],
    formats: [TeachingFormatOption]
) -> Bool {
    if assignment.studentName.trimmedOrNil != nil {
        return true
    }

    switch researcherDetailTeachingAssignmentCategory(
        assignment,
        components: components,
        formats: formats
    ) {
    case .individual, .groupAndIndividual:
        return true
    case .group, .notTeachingWork, nil:
        return false
    }
}

private func researcherDetailTeachingAssignmentIsDoctoralStudent(
    _ assignment: TeachingAssignment,
    courses: [TeachingCourse],
    components: [TeachingComponent]
) -> Bool {
    if assignment.reportCategory == .doctoralPrincipalSupervision ||
        assignment.reportCategory == .doctoralAssistantSupervision {
        return true
    }

    guard assignment.studentName.trimmedOrNil != nil else { return false }

    let context = courses.first(where: { $0.id == assignment.contextID })
    let component = researcherDetailTeachingComponent(for: assignment, components: components)
    let activityType = (assignment.activityTypeName.nonEmpty ?? component?.activityTypeName.nonEmpty ?? "").lowercased()
    let searchableText = [
        assignment.activityName,
        activityType,
        context?.nameSv ?? "",
        context?.nameEn ?? "",
        context?.programSv ?? "",
        context?.programEn ?? ""
    ]
    .joined(separator: " ")
    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    .lowercased()

    let hasDoctoralKeyword =
        searchableText.contains("doktorand") ||
        searchableText.contains("doctoral supervision") ||
        searchableText.contains("phd")
    let contextLooksDoctoral =
        context?.contextType == .doctoralEducation ||
        context?.level == .doctoral
    let hasDoctoralSupervisorRole =
        assignment.roles.contains(.principalSupervisor) ||
        assignment.roles.contains(.assistantSupervisor)

    return hasDoctoralKeyword || (hasDoctoralSupervisorRole && contextLooksDoctoral)
}

private func researcherDetailTeachingAssignmentCategory(
    _ assignment: TeachingAssignment,
    components: [TeachingComponent],
    formats: [TeachingFormatOption]
) -> TeachingAssignmentCategory? {
    if let participantForm = assignment.participantForm {
        return participantForm
    }
    let component = researcherDetailTeachingComponent(for: assignment, components: components)
    if let participantForm = component?.participantForm {
        return participantForm
    }
    let activityType = assignment.activityTypeName.nonEmpty ?? component?.activityTypeName.nonEmpty ?? ""
    return formats.first(where: {
        $0.nameSv == activityType || $0.nameEn == activityType || $0.name == activityType
    })?.category
}

private func researcherDetailTeachingComponent(
    for assignment: TeachingAssignment,
    components: [TeachingComponent]
) -> TeachingComponent? {
    components.first(where: { $0.id == assignment.activityID }) ??
        components.first(where: { $0.nameSv == assignment.activityName || $0.nameEn == assignment.activityName })
}

func canonicalTeachingLanguage(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalized {
    case "sv", "svenska", "swedish":
        return "sv"
    case "en", "engelska", "english":
        return "en"
    default:
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
