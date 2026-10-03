import Foundation

// Läkarspecialiteter (Inställningar > Listor) för befattningarna
// ST-läkare, Specialistläkare och Överläkare. Forskaren sparar bara
// specialitetens id per befattning, så att ett namnbyte syns överallt.

struct ResearcherSpecialtyOption: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var nameSv: String
    var nameEn: String
    var isHidden: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case nameSv
        case nameEn
        case isHidden
        case sortOrder
    }

    init(
        id: String = UUID().uuidString,
        nameSv: String = "",
        nameEn: String = "",
        isHidden: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.nameSv = nameSv
        self.nameEn = nameEn
        self.isHidden = isHidden
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? container.decodeIfPresent(String.self, forKey: .id))?.trimmedOrNil ?? UUID().uuidString,
            nameSv: (try? container.decodeIfPresent(String.self, forKey: .nameSv)) ?? "",
            nameEn: (try? container.decodeIfPresent(String.self, forKey: .nameEn)) ?? "",
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
    }

    /// Specialiteter för läkare (i stil med HSLF-FS 2021:8).
    static let builtInOptions: [ResearcherSpecialtyOption] = {
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

    static func resolvedOptions(_ stored: [ResearcherSpecialtyOption]?) -> [ResearcherSpecialtyOption] {
        normalizedList(stored ?? builtInOptions)
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

    var takesSpecialty: Bool {
        Self.specialtyPositionIDs.contains(id)
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
    /// "Specialistläkare i allmänmedicin" / "Specialist Physician, General Practice".
    func displayName(specialty: ResearcherSpecialtyOption?, language: AppLanguage) -> String {
        let name = localizedName(language: language)
        guard takesSpecialty,
              let specialty,
              let specialtyName = specialty.localizedName(language: language).trimmedOrNil,
              name.trimmedOrNil != nil else {
            return name
        }
        if language == .swedish {
            return "\(name) i \(ResearcherSpecialtyOption.inlineSwedishName(specialtyName))"
        }
        return "\(name), \(specialtyName)"
    }
}
