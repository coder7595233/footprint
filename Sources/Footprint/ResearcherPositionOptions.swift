import Foundation

// Befattningar och examina för forskare som listor (Inställningar > Listor).
// Forskaren sparar bara valens id, så att ett namnbyte i listan syns överallt.
// De gamla fritextfälten (befattning, examen, titel) ligger kvar orörda och
// används som reserv när inget val är gjort.

// MARK: - Befattningar

enum ResearcherPositionGroup: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case academic
    case clinical
    case other

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        self = ResearcherPositionGroup(rawValue: rawValue) ?? .other
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .academic:
            return language.text("Academic", "Akademisk")
        case .clinical:
            return language.text("Clinical", "Klinisk")
        case .other:
            return language.text("Other", "Övrigt")
        }
    }
}

struct ResearcherPositionOption: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var nameSv: String
    var nameEn: String
    var group: ResearcherPositionGroup
    var isHidden: Bool
    var sortOrder: Int
    /// Karriärsteget som befattningen talar för; nil = ingen ledtråd.
    var careerStageHint: PublicationAuthorCareerStage?
    /// Befattningen ger titeln Professor (inte biträdande professor).
    var givesProfessorTitle: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case nameSv
        case nameEn
        case group
        case isHidden
        case sortOrder
        case careerStageHint
        case givesProfessorTitle
    }

    init(
        id: String = UUID().uuidString,
        nameSv: String = "",
        nameEn: String = "",
        group: ResearcherPositionGroup = .academic,
        isHidden: Bool = false,
        sortOrder: Int = 0,
        careerStageHint: PublicationAuthorCareerStage? = nil,
        givesProfessorTitle: Bool = false
    ) {
        self.id = id
        self.nameSv = nameSv
        self.nameEn = nameEn
        self.group = group
        self.isHidden = isHidden
        self.sortOrder = sortOrder
        self.careerStageHint = careerStageHint
        self.givesProfessorTitle = givesProfessorTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedHint = try? container.decodeIfPresent(String.self, forKey: .careerStageHint)
        self.init(
            id: (try? container.decodeIfPresent(String.self, forKey: .id))?.trimmedOrNil ?? UUID().uuidString,
            nameSv: (try? container.decodeIfPresent(String.self, forKey: .nameSv)) ?? "",
            nameEn: (try? container.decodeIfPresent(String.self, forKey: .nameEn)) ?? "",
            group: (try? container.decodeIfPresent(ResearcherPositionGroup.self, forKey: .group)) ?? .other,
            isHidden: (try? container.decodeIfPresent(Bool.self, forKey: .isHidden)) ?? false,
            sortOrder: (try? container.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0,
            careerStageHint: storedHint.flatMap { PublicationAuthorCareerStage.storedStage(from: $0) },
            givesProfessorTitle: (try? container.decodeIfPresent(Bool.self, forKey: .givesProfessorTitle)) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nameSv, forKey: .nameSv)
        try container.encode(nameEn, forKey: .nameEn)
        try container.encode(group, forKey: .group)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(careerStageHint, forKey: .careerStageHint)
        try container.encode(givesProfessorTitle, forKey: .givesProfessorTitle)
    }

    func localizedName(language: AppLanguage) -> String {
        researcherOptionLocalizedText(language: language, swedish: nameSv, english: nameEn)
    }

    var isEmpty: Bool {
        nameSv.trimmedOrNil == nil && nameEn.trimmedOrNil == nil
    }

    /// Fasta id:n för de inbyggda befattningarna (används av flytten från fritext).
    enum BuiltInID {
        static let professor = "position-professor"
        static let adjunctProfessor = "position-adjunct-professor"
        static let seniorProfessor = "position-senior-professor"
        static let professorEmeritus = "position-professor-emeritus"
        static let associateProfessor = "position-associate-professor"
        static let seniorLecturer = "position-senior-lecturer"
        static let assistantProfessor = "position-assistant-professor"
        static let adjunctSeniorLecturer = "position-adjunct-senior-lecturer"
        static let lecturer = "position-lecturer"
        static let adjunctLecturer = "position-adjunct-lecturer"
        static let postdoc = "position-postdoc"
        static let researcher = "position-researcher"
        static let affiliatedResearcher = "position-affiliated-researcher"
        static let visitingResearcher = "position-visiting-researcher"
        static let researchEngineer = "position-research-engineer"
        static let researchAssistant = "position-research-assistant"
        static let seniorResearcher = "position-senior-researcher"
        static let directorOfResearch = "position-director-of-research"
        static let phdStudent = "position-phd-student"
        static let medicalStudent = "position-medical-student"
        static let internPhysician = "position-intern-physician"
        static let residentPhysician = "position-resident-physician"
        static let specialistPhysician = "position-specialist-physician"
        static let seniorConsultant = "position-senior-consultant"
        static let registeredNurse = "position-registered-nurse"
        static let specialistNurse = "position-specialist-nurse"
        static let researchNurse = "position-research-nurse"
        static let biomedicalScientist = "position-biomedical-scientist"
        static let pharmacist = "position-pharmacist"
        static let psychologist = "position-psychologist"
        static let occupationalTherapist = "position-occupational-therapist"
        static let statistician = "position-statistician"
        static let headOfDepartment = "position-head-of-department"
    }

    static let builtInOptions: [ResearcherPositionOption] = {
        let rows: [(String, String, String, ResearcherPositionGroup, PublicationAuthorCareerStage?, Bool)] = [
            (BuiltInID.professor, "Professor", "Professor", .academic, .categoryA, true),
            (BuiltInID.adjunctProfessor, "Adjungerad professor", "Adjunct Professor", .academic, .categoryA, true),
            (BuiltInID.seniorProfessor, "Seniorprofessor", "Senior Professor", .academic, .categoryA, true),
            (BuiltInID.professorEmeritus, "Professor emeritus", "Professor Emeritus", .academic, .categoryA, true),
            (BuiltInID.associateProfessor, "Biträdande professor", "Associate Professor", .academic, .categoryB, false),
            (BuiltInID.seniorLecturer, "Universitetslektor", "Senior Lecturer", .academic, .categoryB, false),
            (BuiltInID.assistantProfessor, "Biträdande universitetslektor", "Assistant Professor", .academic, .categoryC, false),
            (BuiltInID.adjunctSeniorLecturer, "Adjungerad universitetslektor", "Adjunct Senior Lecturer", .academic, .categoryB, false),
            (BuiltInID.lecturer, "Universitetsadjunkt", "Lecturer", .academic, nil, false),
            (BuiltInID.adjunctLecturer, "Adjungerad adjunkt", "Adjunct Lecturer", .academic, nil, false),
            (BuiltInID.postdoc, "Postdoktor", "Postdoctoral Researcher", .academic, .categoryC, false),
            (BuiltInID.researcher, "Forskare", "Researcher", .academic, .categoryC, false),
            (BuiltInID.affiliatedResearcher, "Affilierad forskare", "Affiliated Researcher", .academic, .categoryC, false),
            (BuiltInID.visitingResearcher, "Gästforskare", "Visiting Researcher", .academic, .categoryC, false),
            (BuiltInID.directorOfResearch, "Forskningschef", "Director of Research", .academic, .categoryA, false),
            (BuiltInID.seniorResearcher, "Seniorforskare", "Senior Researcher", .academic, .categoryB, false),
            (BuiltInID.researchEngineer, "Forskningsingenjör", "Research Engineer", .academic, nil, false),
            (BuiltInID.researchAssistant, "Forskningsassistent", "Research Assistant", .academic, .categoryD, false),
            (BuiltInID.phdStudent, "Doktorand", "PhD Student", .academic, .categoryD, false),
            (BuiltInID.medicalStudent, "Läkarstudent", "Medical Student", .clinical, nil, false),
            (BuiltInID.internPhysician, "AT-läkare", "Intern Physician", .clinical, nil, false),
            (BuiltInID.residentPhysician, "ST-läkare", "Resident Physician", .clinical, nil, false),
            (BuiltInID.specialistPhysician, "Specialistläkare", "Specialist Physician", .clinical, nil, false),
            (BuiltInID.seniorConsultant, "Överläkare", "Senior Consultant", .clinical, nil, false),
            (BuiltInID.registeredNurse, "Sjuksköterska", "Registered Nurse", .clinical, nil, false),
            (BuiltInID.specialistNurse, "Specialistsjuksköterska", "Specialist Nurse", .clinical, nil, false),
            (BuiltInID.researchNurse, "Forskningssjuksköterska", "Research Nurse", .clinical, nil, false),
            (BuiltInID.biomedicalScientist, "Biomedicinsk analytiker", "Biomedical Scientist", .clinical, nil, false),
            (BuiltInID.pharmacist, "Apotekare", "Pharmacist", .clinical, nil, false),
            (BuiltInID.psychologist, "Psykolog", "Psychologist", .clinical, nil, false),
            (BuiltInID.occupationalTherapist, "Arbetsterapeut", "Occupational Therapist", .clinical, nil, false),
            (BuiltInID.statistician, "Statistiker", "Statistician", .other, nil, false),
            (BuiltInID.headOfDepartment, "Verksamhetschef", "Head of Department", .other, nil, false),
        ]
        return rows.enumerated().map { index, row in
            ResearcherPositionOption(
                id: row.0,
                nameSv: row.1,
                nameEn: row.2,
                group: row.3,
                isHidden: false,
                sortOrder: index,
                careerStageHint: row.4,
                givesProfessorTitle: row.5
            )
        }
    }()

    /// Listan som gäller: den sparade om den finns, annars den inbyggda.
    /// Tomma rader och dubbla id:n tas bort; ordningen följer `sortOrder`.
    static func resolvedOptions(_ stored: [ResearcherPositionOption]?) -> [ResearcherPositionOption] {
        normalizedList(stored ?? builtInOptions)
    }

    static func normalizedList(_ options: [ResearcherPositionOption]) -> [ResearcherPositionOption] {
        var seen = Set<String>()
        let cleaned = options.compactMap { option -> ResearcherPositionOption? in
            var option = option
            option.id = option.id.trimmedOrNil ?? UUID().uuidString
            option.nameSv = option.nameSv.trimmingCharacters(in: .whitespacesAndNewlines)
            option.nameEn = option.nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !option.isEmpty, seen.insert(option.id).inserted else { return nil }
            return option
        }
        return cleaned
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.sortOrder != rhs.element.sortOrder {
                    return lhs.element.sortOrder < rhs.element.sortOrder
                }
                return lhs.offset < rhs.offset
            }
            .enumerated()
            .map { index, pair in
                var option = pair.element
                option.sortOrder = index
                return option
            }
    }
}

// MARK: - Examina

struct ResearcherDegreeOption: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var nameSv: String
    var nameEn: String
    /// Förkortning som visas i stället för namnet, t.ex. "MD" eller "MSc".
    var abbreviation: String
    /// Examen har ett ämne, t.ex. "MSc (Epidemiology)".
    var takesSubject: Bool
    var isHidden: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case nameSv
        case nameEn
        case abbreviation
        case takesSubject
        case isHidden
        case sortOrder
    }

    init(
        id: String = UUID().uuidString,
        nameSv: String = "",
        nameEn: String = "",
        abbreviation: String = "",
        takesSubject: Bool = false,
        isHidden: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.nameSv = nameSv
        self.nameEn = nameEn
        self.abbreviation = abbreviation
        self.takesSubject = takesSubject
        self.isHidden = isHidden
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? container.decodeIfPresent(String.self, forKey: .id))?.trimmedOrNil ?? UUID().uuidString,
            nameSv: (try? container.decodeIfPresent(String.self, forKey: .nameSv)) ?? "",
            nameEn: (try? container.decodeIfPresent(String.self, forKey: .nameEn)) ?? "",
            abbreviation: (try? container.decodeIfPresent(String.self, forKey: .abbreviation)) ?? "",
            takesSubject: (try? container.decodeIfPresent(Bool.self, forKey: .takesSubject)) ?? false,
            isHidden: (try? container.decodeIfPresent(Bool.self, forKey: .isHidden)) ?? false,
            sortOrder: (try? container.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0
        )
    }

    func localizedName(language: AppLanguage) -> String {
        researcherOptionLocalizedText(language: language, swedish: nameSv, english: nameEn)
    }

    /// Det som står i listor och exporter: förkortningen om den finns, annars namnet.
    func shortText(language: AppLanguage) -> String {
        abbreviation.trimmedOrNil ?? localizedName(language: language)
    }

    var isEmpty: Bool {
        nameSv.trimmedOrNil == nil && nameEn.trimmedOrNil == nil && abbreviation.trimmedOrNil == nil
    }

    enum BuiltInID {
        static let medical = "degree-medical"
        static let nursing = "degree-nursing"
        static let specialistNursing = "degree-specialist-nursing"
        static let pharmacy = "degree-pharmacy"
        static let prescriptionist = "degree-prescriptionist"
        static let biomedicalScience = "degree-biomedical-science"
        static let psychology = "degree-psychology"
        static let occupationalTherapy = "degree-occupational-therapy"
        static let physiotherapy = "degree-physiotherapy"
        static let dietetics = "degree-dietetics"
        static let engineering = "degree-engineering"
        static let socialWork = "degree-social-work"
        static let bachelor = "degree-bachelor"
        static let magister = "degree-magister"
        static let master = "degree-master"
    }

    static let builtInOptions: [ResearcherDegreeOption] = {
        let rows: [(String, String, String, String, Bool)] = [
            (BuiltInID.medical, "Läkarexamen", "Medical degree", "MD", false),
            (BuiltInID.nursing, "Sjuksköterskeexamen", "Nursing degree", "RN", false),
            (BuiltInID.specialistNursing, "Specialistsjuksköterskeexamen", "Specialist nursing degree", "", false),
            (BuiltInID.pharmacy, "Apotekarexamen", "Pharmacy degree", "MSc Pharm", false),
            (BuiltInID.prescriptionist, "Receptarieexamen", "Prescriptionist degree", "", false),
            (BuiltInID.biomedicalScience, "Biomedicinsk analytikerexamen", "Biomedical scientist degree", "", false),
            (BuiltInID.psychology, "Psykologexamen", "Psychology degree", "", false),
            (BuiltInID.occupationalTherapy, "Arbetsterapeutexamen", "Occupational therapy degree", "", false),
            (BuiltInID.physiotherapy, "Fysioterapeutexamen", "Physiotherapy degree", "", false),
            (BuiltInID.dietetics, "Dietistexamen", "Dietetics degree", "", false),
            (BuiltInID.engineering, "Civilingenjörsexamen", "Master of Science in Engineering", "MSc Eng", false),
            (BuiltInID.socialWork, "Socionomexamen", "Social work degree", "", false),
            (BuiltInID.bachelor, "Kandidatexamen", "Bachelor", "BSc", true),
            (BuiltInID.magister, "Magisterexamen", "Master (one year)", "", true),
            (BuiltInID.master, "Masterexamen", "Master", "MSc", true),
        ]
        return rows.enumerated().map { index, row in
            ResearcherDegreeOption(
                id: row.0,
                nameSv: row.1,
                nameEn: row.2,
                abbreviation: row.3,
                takesSubject: row.4,
                isHidden: false,
                sortOrder: index
            )
        }
    }()

    static func resolvedOptions(_ stored: [ResearcherDegreeOption]?) -> [ResearcherDegreeOption] {
        normalizedList(stored ?? builtInOptions)
    }

    static func normalizedList(_ options: [ResearcherDegreeOption]) -> [ResearcherDegreeOption] {
        var seen = Set<String>()
        let cleaned = options.compactMap { option -> ResearcherDegreeOption? in
            var option = option
            option.id = option.id.trimmedOrNil ?? UUID().uuidString
            option.nameSv = option.nameSv.trimmingCharacters(in: .whitespacesAndNewlines)
            option.nameEn = option.nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
            option.abbreviation = option.abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !option.isEmpty, seen.insert(option.id).inserted else { return nil }
            return option
        }
        return cleaned
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.sortOrder != rhs.element.sortOrder {
                    return lhs.element.sortOrder < rhs.element.sortOrder
                }
                return lhs.offset < rhs.offset
            }
            .enumerated()
            .map { index, pair in
                var option = pair.element
                option.sortOrder = index
                return option
            }
    }
}

/// En examen på en forskare: ett val ur listan (med ämne när examen har
/// ämne) eller, utan val, en fri text ("annan examen").
struct ResearcherDegreeEntry: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var optionID: String?
    var subjectSv: String
    var subjectEn: String
    var otherText: String

    enum CodingKeys: String, CodingKey {
        case id
        case optionID
        case subjectSv
        case subjectEn
        case otherText
    }

    init(
        id: String = UUID().uuidString,
        optionID: String? = nil,
        subjectSv: String = "",
        subjectEn: String = "",
        otherText: String = ""
    ) {
        self.id = id
        self.optionID = optionID
        self.subjectSv = subjectSv
        self.subjectEn = subjectEn
        self.otherText = otherText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? container.decodeIfPresent(String.self, forKey: .id))?.trimmedOrNil ?? UUID().uuidString,
            optionID: (try? container.decodeIfPresent(String.self, forKey: .optionID))?.trimmedOrNil,
            subjectSv: (try? container.decodeIfPresent(String.self, forKey: .subjectSv)) ?? "",
            subjectEn: (try? container.decodeIfPresent(String.self, forKey: .subjectEn)) ?? "",
            otherText: (try? container.decodeIfPresent(String.self, forKey: .otherText)) ?? ""
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(optionID, forKey: .optionID)
        try container.encode(subjectSv, forKey: .subjectSv)
        try container.encode(subjectEn, forKey: .subjectEn)
        try container.encode(otherText, forKey: .otherText)
    }

    var isEmpty: Bool {
        optionID?.trimmedOrNil == nil && otherText.trimmedOrNil == nil
    }

    func localizedSubject(language: AppLanguage) -> String {
        researcherOptionLocalizedText(language: language, swedish: subjectSv, english: subjectEn)
    }

    mutating func setLocalizedSubject(_ value: String, language: AppLanguage) {
        if language == .swedish {
            subjectSv = value
        } else {
            subjectEn = value
        }
    }

    /// "MSc (Epidemiology)", "MD" eller den fria texten.
    func displayText(options: [ResearcherDegreeOption], language: AppLanguage) -> String {
        if let optionID = optionID?.trimmedOrNil {
            guard let option = options.first(where: { $0.id == optionID }) else {
                return otherText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let base = option.shortText(language: language)
            if option.takesSubject, let subject = localizedSubject(language: language).trimmedOrNil {
                return "\(base) (\(subject))"
            }
            return base
        }
        return otherText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func researcherOptionLocalizedText(language: AppLanguage, swedish: String, english: String) -> String {
    let swedishValue = swedish.trimmingCharacters(in: .whitespacesAndNewlines)
    let englishValue = english.trimmingCharacters(in: .whitespacesAndNewlines)
    if language == .swedish {
        return swedishValue.nonEmpty ?? englishValue
    }
    return englishValue.nonEmpty ?? swedishValue
}

// MARK: - Listorna som gäller just nu

/// Listorna som visningen använder när ingen lista skickas in (samma mönster
/// som `WorkflowDefaultSettingsRegistry`). Uppdateras när appens metadata ändras.
final class ResearcherOptionRegistry {
    nonisolated(unsafe) private static var storedPositionOptions: [ResearcherPositionOption] = ResearcherPositionOption.builtInOptions
    nonisolated(unsafe) private static var storedDegreeOptions: [ResearcherDegreeOption] = ResearcherDegreeOption.builtInOptions
    nonisolated(unsafe) private static var storedSpecialtyOptions: [ResearcherSpecialtyOption] = ResearcherSpecialtyOption.builtInOptions

    static var positionOptions: [ResearcherPositionOption] {
        storedPositionOptions
    }

    static var degreeOptions: [ResearcherDegreeOption] {
        storedDegreeOptions
    }

    static var specialtyOptions: [ResearcherSpecialtyOption] {
        storedSpecialtyOptions
    }

    static func update(from metadata: DataSourceMetadata) {
        storedPositionOptions = ResearcherPositionOption.resolvedOptions(metadata.researcherPositionOptions)
        storedDegreeOptions = ResearcherDegreeOption.resolvedOptions(metadata.researcherDegreeOptions)
        storedSpecialtyOptions = ResearcherSpecialtyOption.resolvedOptions(metadata.researcherSpecialtyOptions)
    }

    static func replace(
        positionOptions: [ResearcherPositionOption] = ResearcherPositionOption.builtInOptions,
        degreeOptions: [ResearcherDegreeOption] = ResearcherDegreeOption.builtInOptions,
        specialtyOptions: [ResearcherSpecialtyOption] = ResearcherSpecialtyOption.builtInOptions
    ) {
        storedPositionOptions = positionOptions
        storedDegreeOptions = degreeOptions
        storedSpecialtyOptions = specialtyOptions
    }
}

// MARK: - Karriärsteg och titel ur befattningarna

enum ResearcherCareerStageSuggestion {
    private static func rank(_ stage: PublicationAuthorCareerStage) -> Int {
        switch stage {
        case .categoryA: return 4
        case .categoryB: return 3
        case .categoryC: return 2
        case .categoryD: return 1
        }
    }

    /// Föreslaget karriärsteg:
    /// - det högsta steg som de valda befattningarna talar för (A högst, D lägst);
    /// - docent lyfter till minst B (t.ex. universitetslektor + docent = B),
    ///   och en disputerad docent utan akademisk befattning blir B;
    /// - doktorsexamen utan någon ledtråd ger inget förslag (nil), appen gissar inte.
    static func suggestedCareerStage(
        positions: [ResearcherPositionOption],
        isDocent: Bool,
        hasPhD: Bool
    ) -> PublicationAuthorCareerStage? {
        var best: PublicationAuthorCareerStage? = nil
        for stage in positions.compactMap(\.careerStageHint) {
            if let current = best, rank(current) >= rank(stage) { continue }
            best = stage
        }
        if isDocent && (hasPhD || best != nil) {
            if let current = best, rank(current) >= rank(.categoryB) {
                return current
            }
            return .categoryB
        }
        return best
    }

    /// Titel ur befattning, docentur och doktorsexamen: Professor, Docent, Dr eller tom.
    static func suggestedTitle(
        positions: [ResearcherPositionOption],
        isDocent: Bool,
        hasPhD: Bool,
        language: AppLanguage
    ) -> String {
        if positions.contains(where: \.givesProfessorTitle) {
            return "Professor"
        }
        if isDocent {
            return language.text("Associate Professor", "Docent")
        }
        if hasPhD {
            return "Dr"
        }
        return ""
    }
}

// MARK: - Visning på forskaren

extension PublicationAuthor {
    /// Befattning vald ur listan eller skriven som "annan".
    var hasStructuredPosition: Bool {
        !positionIDs.isEmpty || positionOtherSv.trimmedOrNil != nil || positionOtherEn.trimmedOrNil != nil
    }

    var hasStructuredDegree: Bool {
        degreeEntries.contains { !$0.isEmpty }
    }

    /// De valda befattningarna i visningsordning: akademiska, kliniska, övrigt.
    func selectedPositionOptions(
        options: [ResearcherPositionOption] = ResearcherOptionRegistry.positionOptions
    ) -> [ResearcherPositionOption] {
        let selected = positionIDs.compactMap { id in options.first(where: { $0.id == id }) }
        return ResearcherPositionOption.displaySorted(selected)
    }

    func localizedPositionOther(language: AppLanguage) -> String {
        researcherOptionLocalizedText(language: language, swedish: positionOtherSv, english: positionOtherEn)
    }

    mutating func setLocalizedPositionOther(_ value: String, language: AppLanguage) {
        if language == .swedish {
            positionOtherSv = value
        } else {
            positionOtherEn = value
        }
    }

    /// Valda befattningar på appens språk (med läkarspecialitet, t.ex.
    /// "Specialistläkare i allmänmedicin"), följda av "annan"-texten.
    func structuredPositionText(
        language: AppLanguage,
        options: [ResearcherPositionOption] = ResearcherOptionRegistry.positionOptions,
        specialtyOptions: [ResearcherSpecialtyOption] = ResearcherOptionRegistry.specialtyOptions
    ) -> String {
        let names = selectedPositionOptions(options: options)
            .map { positionDisplayName($0, language: language, specialtyOptions: specialtyOptions) }
            .compactMap(\.trimmedOrNil)
        let other = localizedPositionOther(language: language).trimmedOrNil
        return (names + [other].compactMap { $0 }).uniqued().joined(separator: ", ")
    }

    /// Befattningen som visas och exporteras: listvalen, annars den gamla texten.
    func displayPosition(
        language: AppLanguage,
        options: [ResearcherPositionOption] = ResearcherOptionRegistry.positionOptions,
        specialtyOptions: [ResearcherSpecialtyOption] = ResearcherOptionRegistry.specialtyOptions
    ) -> String {
        structuredPositionText(language: language, options: options, specialtyOptions: specialtyOptions).nonEmpty
            ?? localizedPosition(language: language)
    }

    func structuredDegreeText(
        language: AppLanguage,
        options: [ResearcherDegreeOption] = ResearcherOptionRegistry.degreeOptions
    ) -> String {
        degreeEntries
            .map { $0.displayText(options: options, language: language) }
            .compactMap(\.trimmedOrNil)
            .uniqued()
            .joined(separator: ", ")
    }

    /// Examen som visas och exporteras: listvalen, annars den gamla texten.
    func displayDegree(
        language: AppLanguage,
        options: [ResearcherDegreeOption] = ResearcherOptionRegistry.degreeOptions
    ) -> String {
        structuredDegreeText(language: language, options: options).nonEmpty
            ?? localizedDegree(language: language)
    }

    /// Titel räknad ur befattning, docentur och doktorsexamen.
    func suggestedTitle(
        language: AppLanguage,
        options: [ResearcherPositionOption] = ResearcherOptionRegistry.positionOptions
    ) -> String {
        ResearcherCareerStageSuggestion.suggestedTitle(
            positions: selectedPositionOptions(options: options),
            isDocent: isDocent,
            hasPhD: hasPhD,
            language: language
        )
    }

    /// Titeln som visas och exporteras. Med befattning ur listan (eller docent)
    /// gäller den räknade titeln, med den gamla texten som reserv. Utan sådana
    /// val gäller den gamla texten först, så att en sparad titel som
    /// "Professor" inte byts mot "Dr" innan befattningen är vald.
    func displayTitle(
        language: AppLanguage,
        options: [ResearcherPositionOption] = ResearcherOptionRegistry.positionOptions
    ) -> String {
        let derived = suggestedTitle(language: language, options: options)
        let legacy = localizedTitle(language: language)
        if hasStructuredPosition || isDocent {
            return derived.nonEmpty ?? legacy
        }
        return legacy.nonEmpty ?? derived
    }

    /// Karriärsteget som befattningar, docentur och doktorsexamen talar för.
    func careerStageSuggestion(
        options: [ResearcherPositionOption] = ResearcherOptionRegistry.positionOptions
    ) -> PublicationAuthorCareerStage? {
        ResearcherCareerStageSuggestion.suggestedCareerStage(
            positions: selectedPositionOptions(options: options),
            isDocent: isDocent,
            hasPhD: hasPhD
        )
    }
}
