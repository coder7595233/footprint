import Foundation

// Specialiteter (Inställningar > Listor): läkarspecialiteter för
// befattningarna ST-läkare, Specialistläkare och Överläkare, och
// sjuksköterskespecialiteter för Specialistsjuksköterska. Forskaren sparar
// bara specialitetens id per befattning, så att ett namnbyte syns överallt.

/// Vilken sorts specialitet: för läkare eller för specialistsjuksköterskor.
enum ResearcherSpecialtyKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case physician
    case nurse

    var id: String { rawValue }
}

struct ResearcherSpecialtyOption: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var nameSv: String
    var nameEn: String
    /// Läkar- eller sjuksköterskespecialitet. Sparade listor från före
    /// sjuksköterskespecialiteterna saknar värdet och blir läkarspecialiteter.
    var kind: ResearcherSpecialtyKind
    var isHidden: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case nameSv
        case nameEn
        case kind
        case isHidden
        case sortOrder
    }

    init(
        id: String = UUID().uuidString,
        nameSv: String = "",
        nameEn: String = "",
        kind: ResearcherSpecialtyKind = .physician,
        isHidden: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.nameSv = nameSv
        self.nameEn = nameEn
        self.kind = kind
        self.isHidden = isHidden
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind: String? = try? container.decodeIfPresent(String.self, forKey: .kind)
        self.init(
            id: (try? container.decodeIfPresent(String.self, forKey: .id))?.trimmedOrNil ?? UUID().uuidString,
            nameSv: (try? container.decodeIfPresent(String.self, forKey: .nameSv)) ?? "",
            nameEn: (try? container.decodeIfPresent(String.self, forKey: .nameEn)) ?? "",
            kind: rawKind.flatMap { ResearcherSpecialtyKind(rawValue: $0) } ?? .physician,
            isHidden: (try? container.decodeIfPresent(Bool.self, forKey: .isHidden)) ?? false,
            sortOrder: (try? container.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0
        )
    }

    func localizedName(language: AppLanguage) -> String {
        researcherOptionLocalizedText(language: language, swedish: nameSv, english: nameEn)
    }

    var isEmpty: Bool {
        nameSv.trimmedOrNil == nil && nameEn.trimmedOrNil == nil
    }

    /// Fasta id:n för de inbyggda specialiteterna.
    enum BuiltInID {
        static let generalPractice = "specialty-general-practice"
        static let emergencyMedicine = "specialty-emergency-medicine"
        static let anaesthesia = "specialty-anaesthesia-intensive-care"
        static let occupationalMedicine = "specialty-occupational-environmental-medicine"
        static let paediatrics = "specialty-paediatrics"
        static let childPsychiatry = "specialty-child-adolescent-psychiatry"
        static let dermatology = "specialty-dermatology-venereology"
        static let endocrinology = "specialty-endocrinology-diabetology"
        static let geriatrics = "specialty-geriatrics"
        static let gastroenterology = "specialty-gastroenterology-hepatology"
        static let haematology = "specialty-haematology"
        static let infectiousDiseases = "specialty-infectious-diseases"
        static let internalMedicine = "specialty-internal-medicine"
        static let cardiology = "specialty-cardiology"
        static let surgery = "specialty-surgery"
        static let clinicalPharmacology = "specialty-clinical-pharmacology"
        static let clinicalPhysiology = "specialty-clinical-physiology"
        static let clinicalGenetics = "specialty-clinical-genetics"
        static let clinicalChemistry = "specialty-clinical-chemistry"
        static let clinicalMicrobiology = "specialty-clinical-microbiology"
        static let clinicalPathology = "specialty-clinical-pathology"
        static let respiratoryMedicine = "specialty-respiratory-medicine"
        static let neurology = "specialty-neurology"
        static let nephrology = "specialty-nephrology"
        static let nuclearMedicine = "specialty-nuclear-medicine"
        static let obstetrics = "specialty-obstetrics-gynaecology"
        static let oncology = "specialty-oncology"
        static let orthopaedics = "specialty-orthopaedics"
        static let psychiatry = "specialty-psychiatry"
        static let radiology = "specialty-radiology"
        static let rehabilitationMedicine = "specialty-rehabilitation-medicine"
        static let rheumatology = "specialty-rheumatology"
        static let socialMedicine = "specialty-social-medicine"
        static let thoracicSurgery = "specialty-thoracic-surgery"
        static let urology = "specialty-urology"
        static let ophthalmology = "specialty-ophthalmology"
        static let otorhinolaryngology = "specialty-otorhinolaryngology"

        // Sjuksköterskespecialiteter (specialistsjuksköterskeexamen).
        static let nurseEmergencyCare = "nurse-specialty-emergency-care"
        static let nurseAmbulanceCare = "nurse-specialty-ambulance-care"
        static let nurseAnaesthesiaCare = "nurse-specialty-anaesthesia-care"
        static let nursePaediatricCare = "nurse-specialty-paediatric-care"
        static let nurseDistrictNursing = "nurse-specialty-district-nursing"
        static let nurseChildHealth = "nurse-specialty-child-adolescent-health"
        static let nurseIntensiveCare = "nurse-specialty-intensive-care"
        static let nurseSurgicalCare = "nurse-specialty-surgical-care"
        static let nurseMedicalCare = "nurse-specialty-medical-care"
        static let nurseOncologyCare = "nurse-specialty-oncology-care"
        static let nurseOperatingRoomCare = "nurse-specialty-operating-room-care"
        static let nursePsychiatricCare = "nurse-specialty-psychiatric-care"
        static let nurseOlderPeopleCare = "nurse-specialty-care-of-older-people"
        static let nurseDiabetesCare = "nurse-specialty-diabetes-care"
    }

    /// De inbyggda specialiteterna: först läkarnas, sedan sjuksköterskornas.
    static let builtInOptions: [ResearcherSpecialtyOption] = {
        let physicians = builtInPhysicianOptions
        let nurses = builtInNurseOptions.enumerated().map { index, option -> ResearcherSpecialtyOption in
            var option = option
            option.sortOrder = physicians.count + index
            return option
        }
        return physicians + nurses
    }()

    /// Inriktningar för specialistsjuksköterskeexamen.
    static let builtInNurseOptions: [ResearcherSpecialtyOption] = {
        let rows: [(String, String, String)] = [
            (BuiltInID.nurseEmergencyCare, "Akutsjukvård", "Emergency Care"),
            (BuiltInID.nurseAmbulanceCare, "Ambulanssjukvård", "Ambulance Care"),
            (BuiltInID.nurseAnaesthesiaCare, "Anestesisjukvård", "Anaesthesia Care"),
            (BuiltInID.nursePaediatricCare, "Barnsjukvård", "Paediatric Care"),
            (BuiltInID.nurseDistrictNursing, "Distriktssköterska", "District Nursing"),
            (BuiltInID.nurseChildHealth, "Hälso- och sjukvård för barn och ungdomar", "Child and Adolescent Health"),
            (BuiltInID.nurseIntensiveCare, "Intensivvård", "Intensive Care"),
            (BuiltInID.nurseSurgicalCare, "Kirurgisk vård", "Surgical Care"),
            (BuiltInID.nurseMedicalCare, "Medicinsk vård", "Medical Care"),
            (BuiltInID.nurseOncologyCare, "Onkologisk vård", "Oncology Care"),
            (BuiltInID.nurseOperatingRoomCare, "Operationssjukvård", "Operating Room Care"),
            (BuiltInID.nursePsychiatricCare, "Psykiatrisk vård", "Psychiatric Care"),
            (BuiltInID.nurseOlderPeopleCare, "Vård av äldre", "Care of Older People"),
            (BuiltInID.nurseDiabetesCare, "Diabetesvård", "Diabetes Care"),
        ]
        return rows.enumerated().map { index, row in
            ResearcherSpecialtyOption(
                id: row.0,
                nameSv: row.1,
                nameEn: row.2,
                kind: .nurse,
                isHidden: false,
                sortOrder: index
            )
        }
    }()

    /// Specialiteter för läkare (i stil med HSLF-FS 2021:8).
    static let builtInPhysicianOptions: [ResearcherSpecialtyOption] = {
        let rows: [(String, String, String)] = [
            (BuiltInID.generalPractice, "Allmänmedicin", "General Practice"),
            (BuiltInID.emergencyMedicine, "Akutsjukvård", "Emergency Medicine"),
            (BuiltInID.anaesthesia, "Anestesi och intensivvård", "Anaesthesia and Intensive Care"),
            (BuiltInID.occupationalMedicine, "Arbets- och miljömedicin", "Occupational and Environmental Medicine"),
            (BuiltInID.paediatrics, "Barn- och ungdomsmedicin", "Paediatrics"),
            (BuiltInID.childPsychiatry, "Barn- och ungdomspsykiatri", "Child and Adolescent Psychiatry"),
            (BuiltInID.dermatology, "Dermatologi och venereologi", "Dermatology and Venereology"),
            (BuiltInID.endocrinology, "Endokrinologi och diabetologi", "Endocrinology and Diabetology"),
            (BuiltInID.geriatrics, "Geriatrik", "Geriatrics"),
            (BuiltInID.gastroenterology, "Gastroenterologi och hepatologi", "Gastroenterology and Hepatology"),
            (BuiltInID.haematology, "Hematologi", "Haematology"),
            (BuiltInID.infectiousDiseases, "Infektionssjukdomar", "Infectious Diseases"),
            (BuiltInID.internalMedicine, "Internmedicin", "Internal Medicine"),
            (BuiltInID.cardiology, "Kardiologi", "Cardiology"),
            (BuiltInID.surgery, "Kirurgi", "Surgery"),
            (BuiltInID.clinicalPharmacology, "Klinisk farmakologi", "Clinical Pharmacology"),
            (BuiltInID.clinicalPhysiology, "Klinisk fysiologi", "Clinical Physiology"),
            (BuiltInID.clinicalGenetics, "Klinisk genetik", "Clinical Genetics"),
            (BuiltInID.clinicalChemistry, "Klinisk kemi", "Clinical Chemistry"),
            (BuiltInID.clinicalMicrobiology, "Klinisk mikrobiologi", "Clinical Microbiology"),
            (BuiltInID.clinicalPathology, "Klinisk patologi", "Clinical Pathology"),
            (BuiltInID.respiratoryMedicine, "Lungsjukdomar", "Respiratory Medicine"),
            (BuiltInID.neurology, "Neurologi", "Neurology"),
            (BuiltInID.nephrology, "Njurmedicin", "Nephrology"),
            (BuiltInID.nuclearMedicine, "Nuklearmedicin", "Nuclear Medicine"),
            (BuiltInID.obstetrics, "Obstetrik och gynekologi", "Obstetrics and Gynaecology"),
            (BuiltInID.oncology, "Onkologi", "Oncology"),
            (BuiltInID.orthopaedics, "Ortopedi", "Orthopaedics"),
            (BuiltInID.psychiatry, "Psykiatri", "Psychiatry"),
            (BuiltInID.radiology, "Radiologi", "Radiology"),
            (BuiltInID.rehabilitationMedicine, "Rehabiliteringsmedicin", "Rehabilitation Medicine"),
            (BuiltInID.rheumatology, "Reumatologi", "Rheumatology"),
            (BuiltInID.socialMedicine, "Socialmedicin", "Social Medicine"),
            (BuiltInID.thoracicSurgery, "Thoraxkirurgi", "Thoracic Surgery"),
            (BuiltInID.urology, "Urologi", "Urology"),
            (BuiltInID.ophthalmology, "Ögonsjukdomar", "Ophthalmology"),
            (BuiltInID.otorhinolaryngology, "Öron-, näs- och halssjukdomar", "Otorhinolaryngology"),
        ]
        return rows.enumerated().map { index, row in
            ResearcherSpecialtyOption(
                id: row.0,
                nameSv: row.1,
                nameEn: row.2,
                isHidden: false,
                sortOrder: index
            )
        }
    }()

    /// Listan som gäller. En sparad lista från före sjuksköterske-
    /// specialiteterna (utan någon sådan) får de inbyggda sjuksköterske-
    /// specialiteterna sist; det sparas först när listan ändras.
    static func resolvedOptions(_ stored: [ResearcherSpecialtyOption]?) -> [ResearcherSpecialtyOption] {
        guard let stored else { return normalizedList(builtInOptions) }
        var list = stored
        if !stored.contains(where: { $0.kind == .nurse }) {
            let existingIDs = Set(stored.map(\.id))
            var nextSortOrder = (stored.map(\.sortOrder).max() ?? -1) + 1
            for option in builtInNurseOptions where !existingIDs.contains(option.id) {
                var added = option
                added.sortOrder = nextSortOrder
                nextSortOrder += 1
                list.append(added)
            }
        }
        return normalizedList(list)
    }

    /// Specialiteterna av en sort, i listans ordning.
    static func options(
        _ options: [ResearcherSpecialtyOption],
        ofKind kind: ResearcherSpecialtyKind
    ) -> [ResearcherSpecialtyOption] {
        options.filter { $0.kind == kind }
    }

    static func normalizedList(_ options: [ResearcherSpecialtyOption]) -> [ResearcherSpecialtyOption] {
        var seen = Set<String>()
        let cleaned = options.compactMap { option -> ResearcherSpecialtyOption? in
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

    /// Specialitetens namn mitt i en mening på svenska: första bokstaven
    /// liten ("i allmänmedicin"), utom när namnet börjar med en förkortning.
    static func inlineSwedishName(_ name: String) -> String {
        guard let first = name.first else { return name }
        let rest = name.dropFirst()
        if let second = rest.first, second.isUppercase {
            return name
        }
        return first.lowercased() + String(rest)
    }
}

extension ResearcherPositionOption {
    /// Befattningarna som kan ha en läkarspecialitet.
    static let specialtyPositionIDs: Set<String> = [
        BuiltInID.residentPhysician,
        BuiltInID.specialistPhysician,
        BuiltInID.seniorConsultant,
    ]

    /// Befattningarna som kan ha en sjuksköterskespecialitet.
    static let nurseSpecialtyPositionIDs: Set<String> = [
        BuiltInID.specialistNurse,
    ]

    /// Vilken sorts specialitet befattningen kan ha (nil = ingen).
    static func specialtyKind(forPositionID positionID: String) -> ResearcherSpecialtyKind? {
        if specialtyPositionIDs.contains(positionID) { return .physician }
        if nurseSpecialtyPositionIDs.contains(positionID) { return .nurse }
        return nil
    }

    /// Befattningarna som kan ha en specialitet av sorten.
    static func specialtyPositionIDSet(for kind: ResearcherSpecialtyKind) -> Set<String> {
        switch kind {
        case .physician: return specialtyPositionIDs
        case .nurse: return nurseSpecialtyPositionIDs
        }
    }

    var specialtyKind: ResearcherSpecialtyKind? {
        Self.specialtyKind(forPositionID: id)
    }

    var takesSpecialty: Bool {
        specialtyKind != nil
    }
}

extension ResearcherPositionGroup {
    /// Ordningen befattningar visas i: akademiska först, sedan kliniska, sist övrigt.
    var displayRank: Int {
        switch self {
        case .academic: return 0
        case .clinical: return 1
        case .other: return 2
        }
    }

    static var displayOrder: [ResearcherPositionGroup] {
        [.academic, .clinical, .other]
    }
}

extension ResearcherPositionOption {
    /// Akademiska först, sedan kliniska, sist övrigt; inom gruppen listans ordning.
    static func displaySorted(_ options: [ResearcherPositionOption]) -> [ResearcherPositionOption] {
        options.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.group.displayRank != rhs.element.group.displayRank {
                    return lhs.element.group.displayRank < rhs.element.group.displayRank
                }
                if lhs.element.sortOrder != rhs.element.sortOrder {
                    return lhs.element.sortOrder < rhs.element.sortOrder
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

extension PublicationAuthor {
    /// Specialiteten som är vald för befattningen (nil = ingen).
    func specialtyOption(
        forPositionID positionID: String,
        specialtyOptions: [ResearcherSpecialtyOption] = ResearcherOptionRegistry.specialtyOptions
    ) -> ResearcherSpecialtyOption? {
        guard let specialtyID = positionSpecialtyIDs[positionID]?.trimmedOrNil else { return nil }
        return specialtyOptions.first { $0.id == specialtyID }
    }

    /// "Specialistläkare i allmänmedicin" / "Specialist Physician, General
    /// Practice"; utan specialitet bara befattningens namn.
    func positionDisplayName(
        _ option: ResearcherPositionOption,
        language: AppLanguage,
        specialtyOptions: [ResearcherSpecialtyOption] = ResearcherOptionRegistry.specialtyOptions
    ) -> String {
        option.displayName(
            specialty: specialtyOption(forPositionID: option.id, specialtyOptions: specialtyOptions),
            language: language
        )
    }
}

extension ResearcherPositionOption {
    /// Befattningens namn med specialitet när befattningen kan ha en:
    /// "Specialistläkare i allmänmedicin" / "Specialist Physician, General Practice",
    /// "Specialistsjuksköterska inom intensivvård" / "Specialist Nurse, Intensive
    /// Care"; för distriktssköterskor bara "Distriktssköterska" / "District Nurse".
    func displayName(specialty: ResearcherSpecialtyOption?, language: AppLanguage) -> String {
        let name = localizedName(language: language)
        guard let kind = specialtyKind,
              let specialty,
              let specialtyName = specialty.localizedName(language: language).trimmedOrNil,
              name.trimmedOrNil != nil else {
            return name
        }
        if kind == .nurse && specialty.id == ResearcherSpecialtyOption.BuiltInID.nurseDistrictNursing {
            if language == .swedish {
                return specialtyName
            }
            return specialtyName.caseInsensitiveCompare("District Nursing") == .orderedSame
                ? "District Nurse"
                : specialtyName
        }
        if language == .swedish {
            let preposition = kind == .nurse ? "inom" : "i"
            return "\(name) \(preposition) \(ResearcherSpecialtyOption.inlineSwedishName(specialtyName))"
        }
        return "\(name), \(specialtyName)"
    }
}
