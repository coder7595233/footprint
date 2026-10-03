import Foundation

enum StableRecordID {
    static func legacy(prefix: String, name: String) -> String {
        let normalized = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9\-]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? "\(prefix)-\(UUID().uuidString)" : "\(prefix)-\(normalized)"
    }
}

struct GrantApplication: Identifiable, Codable, Hashable {
    var id: String
    var rowNumber: Int
    var organizationID: String?
    var organization: String
    var grantNameSv: String
    var grantNameEn: String
    var grantCategory: String?
    var currency: String?
    var maxAmount: String?
    var yearCount: String?
    var employmentPercentage: String?
    var employmentMonths: String?
    var salaryIncludesOverhead: Bool
    var approximateAmount: String?
    var approximateAmountValue: Double?
    var opensOn: String?
    var opensOnUncertain: Bool
    var closesOn: String?
    var closesOnUncertain: Bool
    var decisionExpectedOn: String?
    var decisionExpectedOnUncertain: Bool
    var firstDispositionOn: String?
    var firstDispositionOnUncertain: Bool
    var lastDispositionOn: String?
    var lastDispositionOnUncertain: Bool
    var projectID: String?
    var projectType: String?
    var dispositionYears: String?
    var applicantCriteria: String?
    var projectCriteria: String?
    var primaryLink: String?
    var secondaryLink: String?
    var appliedOn: String?
    var appliedOnUncertain: Bool
    var appliedCaseNumber: String?
    var appliedAmount: String?
    var appliedAmountValue: Double?
    var grantedOn: String?
    var grantedOnUncertain: Bool
    var deniedOn: String?
    var deniedOnUncertain: Bool
    var withdrawnOn: String?
    var withdrawnOnUncertain: Bool
    var notAppliedOn: String?
    var notAppliedOnUncertain: Bool
    var decisionOn: String?
    var decisionOnUncertain: Bool
    var grantedAmount: String?
    var grantedAmountValue: Double?
    var result: String?
    /// The case number the application got at the university ("Diarienummer").
    var institutionCaseNumber: String?
    var applicationManagerID: String?
    var applicationManager: String?
    var managerReason: String?
    var applicationTitle: String?
    var coApplicants: [String]
    var coApplicantAuthorIDs: [String]
    var appliedYear: String?
    var fundingSalary: Bool
    var fundingMaterials: Bool
    var fundingPhDStudents: Bool
    var receivedProjectNumber: String?
    var receivedDisplayName: String?
    var receivedPEOE: String?
    var receivedConsumedAmount: String?
    var receivedConsumedAmountValue: Double?
    var receivedConsumptionPeriods: [GrantConsumptionPeriod]
    var receivedUsageFrom: String?
    var receivedUsageFromUncertain: Bool
    var receivedUsageTo: String?
    var receivedUsageToUncertain: Bool
    var receivedRepaymentRequirement: String?
    var receivedRepaymentDueOn: String?
    var receivedRepaidOn: String?
    var isEditingLocked: Bool
    /// Round 10: "Finansiären godkänner OH, högst (%)" on this record (0–100;
    /// 100 = full OH). A copy of the funder's setting made when the funder or
    /// fund manager is chosen; editable, and never changed afterwards by the
    /// funder's setting. nil = not set (older records; the funder's setting
    /// counts, as before).
    var funderMaxOverheadPercent: Double?
    /// Round 10: "Förvaltaren tar ut OH (%)" on this record. A copy of the
    /// fund manager's setting, handled like `funderMaxOverheadPercent`.
    var managerOverheadPercent: Double?
    /// Round 10: "Förvaltaren samfinansierar": the fund manager's answer when
    /// it takes more OH than the funder accepts. nil = not asked.
    var cofundingDecision: GrantCofundingDecision?
    /// The day of that answer (ISO day).
    var cofundingDecisionOn: String?
    /// Round 10: true once either OH number has been typed in the record.
    /// Such numbers are never replaced by the organizations' defaults.
    var overheadNumbersSetByHand: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case rowNumber
        case organizationID
        case organization
        case grantName
        case grantNameSv
        case grantNameEn
        case grantCategory
        case currency
        case maxAmount
        case yearCount
        case employmentPercentage
        case employmentMonths
        case salaryIncludesOverhead
        case approximateAmount
        case approximateAmountValue
        case opensOn
        case opensOnUncertain
        case closesOn
        case closesOnUncertain
        case decisionExpectedOn
        case decisionExpectedOnUncertain
        case firstDispositionOn
        case firstDispositionOnUncertain
        case lastDispositionOn
        case lastDispositionOnUncertain
        case projectID
        case projectType
        case dispositionYears
        case applicantCriteria
        case projectCriteria
        case primaryLink
        case secondaryLink
        case appliedOn
        case appliedOnUncertain
        case appliedCaseNumber
        case appliedAmount
        case appliedAmountValue
        case grantedOn
        case grantedOnUncertain
        case deniedOn
        case deniedOnUncertain
        case withdrawnOn
        case withdrawnOnUncertain
        case notAppliedOn
        case notAppliedOnUncertain
        case decisionOn
        case decisionOnUncertain
        case grantedAmount
        case grantedAmountValue
        case result
        // Stored under its original key so existing data keeps loading.
        case institutionCaseNumber = "liuRegistered"
        case applicationManagerID
        case applicationManager
        case managerReason
        case applicationTitle
        case coApplicants
        case coApplicantAuthorIDs
        case appliedYear
        case fundingSalary
        case fundingMaterials
        case fundingPhDStudents
        case receivedProjectNumber
        case receivedDisplayName
        case receivedPEOE
        case receivedConsumedAmount
        case receivedConsumedAmountValue
        case receivedConsumptionPeriods
        case receivedUsageFrom
        case receivedUsageFromUncertain
        case receivedUsageTo
        case receivedUsageToUncertain
        case receivedRepaymentRequirement
        case receivedRepaymentDueOn
        case receivedRepaidOn
        case isEditingLocked
        case funderMaxOverheadPercent
        case managerOverheadPercent
        case cofundingDecision
        case cofundingDecisionOn
        case overheadNumbersSetByHand
    }

    init(
        id: String,
        rowNumber: Int,
        organizationID: String? = nil,
        organization: String,
        grantName: String,
        grantNameSv: String? = nil,
        grantNameEn: String? = nil,
        grantCategory: String? = nil,
        currency: String? = "SEK",
        maxAmount: String? = nil,
        yearCount: String? = nil,
        employmentPercentage: String? = nil,
        employmentMonths: String? = nil,
        salaryIncludesOverhead: Bool = true,
        approximateAmount: String? = nil,
        approximateAmountValue: Double? = nil,
        opensOn: String? = nil,
        opensOnUncertain: Bool = false,
        closesOn: String? = nil,
        closesOnUncertain: Bool = false,
        decisionExpectedOn: String? = nil,
        decisionExpectedOnUncertain: Bool = false,
        firstDispositionOn: String? = nil,
        firstDispositionOnUncertain: Bool = false,
        lastDispositionOn: String? = nil,
        lastDispositionOnUncertain: Bool = false,
        projectID: String? = nil,
        projectType: String? = nil,
        dispositionYears: String? = nil,
        applicantCriteria: String? = nil,
        projectCriteria: String? = nil,
        primaryLink: String? = nil,
        secondaryLink: String? = nil,
        appliedOn: String? = nil,
        appliedOnUncertain: Bool = false,
        appliedCaseNumber: String? = nil,
        appliedAmount: String? = nil,
        appliedAmountValue: Double? = nil,
        grantedOn: String? = nil,
        grantedOnUncertain: Bool = false,
        deniedOn: String? = nil,
        deniedOnUncertain: Bool = false,
        withdrawnOn: String? = nil,
        withdrawnOnUncertain: Bool = false,
        notAppliedOn: String? = nil,
        notAppliedOnUncertain: Bool = false,
        decisionOn: String? = nil,
        decisionOnUncertain: Bool = false,
        grantedAmount: String? = nil,
        grantedAmountValue: Double? = nil,
        result: String? = nil,
        institutionCaseNumber: String? = nil,
        applicationManagerID: String? = nil,
        applicationManager: String? = nil,
        managerReason: String? = nil,
        applicationTitle: String? = nil,
        coApplicants: [String] = [],
        coApplicantAuthorIDs: [String] = [],
        appliedYear: String? = nil,
        fundingSalary: Bool = false,
        fundingMaterials: Bool = false,
        fundingPhDStudents: Bool = false,
        receivedProjectNumber: String? = nil,
        receivedDisplayName: String? = nil,
        receivedPEOE: String? = nil,
        receivedConsumedAmount: String? = nil,
        receivedConsumedAmountValue: Double? = nil,
        receivedConsumptionPeriods: [GrantConsumptionPeriod] = [],
        receivedUsageFrom: String? = nil,
        receivedUsageFromUncertain: Bool = false,
        receivedUsageTo: String? = nil,
        receivedUsageToUncertain: Bool = false,
        receivedRepaymentRequirement: String? = nil,
        receivedRepaymentDueOn: String? = nil,
        receivedRepaidOn: String? = nil,
        isEditingLocked: Bool = false,
        funderMaxOverheadPercent: Double? = nil,
        managerOverheadPercent: Double? = nil,
        cofundingDecision: GrantCofundingDecision? = nil,
        cofundingDecisionOn: String? = nil,
        overheadNumbersSetByHand: Bool = false
    ) {
        self.id = id
        self.rowNumber = rowNumber
        self.organizationID = organizationID
        self.organization = organization
        self.grantNameSv = grantNameSv ?? grantName
        self.grantNameEn = grantNameEn ?? grantName
        self.grantCategory = grantCategory
        self.currency = currency
        self.maxAmount = maxAmount
        self.yearCount = yearCount
        self.employmentPercentage = employmentPercentage
        self.employmentMonths = employmentMonths
        self.salaryIncludesOverhead = salaryIncludesOverhead
        self.approximateAmount = approximateAmount
        self.approximateAmountValue = approximateAmountValue
        self.opensOn = opensOn
        self.opensOnUncertain = opensOnUncertain
        self.closesOn = closesOn
        self.closesOnUncertain = closesOnUncertain
        self.decisionExpectedOn = decisionExpectedOn
        self.decisionExpectedOnUncertain = decisionExpectedOnUncertain
        self.firstDispositionOn = firstDispositionOn
        self.firstDispositionOnUncertain = firstDispositionOnUncertain
        self.lastDispositionOn = lastDispositionOn
        self.lastDispositionOnUncertain = lastDispositionOnUncertain
        self.projectID = projectID
        self.projectType = projectType
        self.dispositionYears = dispositionYears
        self.applicantCriteria = applicantCriteria
        self.projectCriteria = projectCriteria
        self.primaryLink = primaryLink
        self.secondaryLink = secondaryLink
        self.appliedOn = appliedOn
        self.appliedOnUncertain = appliedOnUncertain
        self.appliedCaseNumber = appliedCaseNumber
        self.appliedAmount = appliedAmount
        self.appliedAmountValue = appliedAmountValue
        self.grantedOn = grantedOn
        self.grantedOnUncertain = grantedOnUncertain
        self.deniedOn = deniedOn
        self.deniedOnUncertain = deniedOnUncertain
        self.withdrawnOn = withdrawnOn
        self.withdrawnOnUncertain = withdrawnOnUncertain
        self.notAppliedOn = notAppliedOn
        self.notAppliedOnUncertain = notAppliedOnUncertain
        self.decisionOn = decisionOn
        self.decisionOnUncertain = decisionOnUncertain
        self.grantedAmount = grantedAmount
        self.grantedAmountValue = grantedAmountValue
        self.result = result
        self.institutionCaseNumber = institutionCaseNumber
        self.applicationManagerID = applicationManagerID
        self.applicationManager = applicationManager
        self.managerReason = managerReason
        self.applicationTitle = applicationTitle
        self.coApplicants = coApplicants
        self.coApplicantAuthorIDs = coApplicantAuthorIDs
        self.appliedYear = appliedYear
        self.fundingSalary = fundingSalary
        self.fundingMaterials = fundingMaterials
        self.fundingPhDStudents = fundingPhDStudents
        self.receivedProjectNumber = receivedProjectNumber
        self.receivedDisplayName = receivedDisplayName
        self.receivedPEOE = receivedPEOE
        self.receivedConsumedAmount = receivedConsumedAmount
        self.receivedConsumedAmountValue = receivedConsumedAmountValue
        self.receivedConsumptionPeriods = receivedConsumptionPeriods
        self.receivedUsageFrom = receivedUsageFrom
        self.receivedUsageFromUncertain = receivedUsageFromUncertain
        self.receivedUsageTo = receivedUsageTo
        self.receivedUsageToUncertain = receivedUsageToUncertain
        self.receivedRepaymentRequirement = receivedRepaymentRequirement
        self.receivedRepaymentDueOn = receivedRepaymentDueOn
        self.receivedRepaidOn = receivedRepaidOn
        self.isEditingLocked = isEditingLocked
        self.funderMaxOverheadPercent = funderMaxOverheadPercent
        self.managerOverheadPercent = managerOverheadPercent
        self.cofundingDecision = cofundingDecision
        self.cofundingDecisionOn = cofundingDecisionOn
        self.overheadNumbersSetByHand = overheadNumbersSetByHand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedResult = try container.decodeIfPresent(String.self, forKey: .result)
        let legacyDecisionOn = try container.decodeIfPresent(String.self, forKey: .decisionOn)
        let legacyDecisionOnUncertain = try container.decodeIfPresent(Bool.self, forKey: .decisionOnUncertain) ?? false
        let decodedGrantedOn = try container.decodeIfPresent(String.self, forKey: .grantedOn)
        let decodedGrantedOnUncertain = try container.decodeIfPresent(Bool.self, forKey: .grantedOnUncertain) ?? false
        let decodedDeniedOn = try container.decodeIfPresent(String.self, forKey: .deniedOn)
        let decodedDeniedOnUncertain = try container.decodeIfPresent(Bool.self, forKey: .deniedOnUncertain) ?? false
        let decodedWithdrawnOn = try container.decodeIfPresent(String.self, forKey: .withdrawnOn)
        let decodedWithdrawnOnUncertain = try container.decodeIfPresent(Bool.self, forKey: .withdrawnOnUncertain) ?? false
        let decodedNotAppliedOn = try container.decodeIfPresent(String.self, forKey: .notAppliedOn)
        let decodedNotAppliedOnUncertain = try container.decodeIfPresent(Bool.self, forKey: .notAppliedOnUncertain) ?? false

        var migratedGrantedOn = decodedGrantedOn ?? ((decodedResult == "Beviljat") ? legacyDecisionOn : nil)
        var migratedGrantedOnUncertain = decodedGrantedOn != nil ? decodedGrantedOnUncertain : ((decodedResult == "Beviljat") ? legacyDecisionOnUncertain : false)
        var migratedDeniedOn = decodedDeniedOn ?? ((decodedResult == "Avslag") ? legacyDecisionOn : nil)
        var migratedDeniedOnUncertain = decodedDeniedOn != nil ? decodedDeniedOnUncertain : ((decodedResult == "Avslag") ? legacyDecisionOnUncertain : false)
        var migratedWithdrawnOn = decodedWithdrawnOn ?? ((decodedResult == "Tillbakadragen") ? legacyDecisionOn : nil)
        var migratedWithdrawnOnUncertain = decodedWithdrawnOn != nil ? decodedWithdrawnOnUncertain : ((decodedResult == "Tillbakadragen") ? legacyDecisionOnUncertain : false)
        // An old record saved as "Beviljat", "Avslag" or "Tillbakadragen"
        // without any decision date used to turn into "Väntar svar" (it has
        // an applied date), and the next save then removed the granted
        // amount and the rest of the grant data. Such a record keeps its
        // result: the decision date becomes the expected decision date, the
        // applied date or the closing date, marked as uncertain.
        if [migratedGrantedOn, migratedDeniedOn, migratedWithdrawnOn].allSatisfy({ $0?.trimmedOrNil == nil }),
           let decided = decodedResult?.trimmedOrNil,
           ["Beviljat", "Avslag", "Tillbakadragen"].contains(decided) {
            let fallbackDay = [
                try container.decodeIfPresent(String.self, forKey: .decisionExpectedOn),
                try container.decodeIfPresent(String.self, forKey: .appliedOn),
                try container.decodeIfPresent(String.self, forKey: .closesOn),
            ]
            .lazy
            .compactMap { $0.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil }
            .first { DateParsers.isoDay.date(from: $0) != nil }
            if let fallbackDay {
                switch decided {
                case "Beviljat":
                    migratedGrantedOn = fallbackDay
                    migratedGrantedOnUncertain = true
                case "Avslag":
                    migratedDeniedOn = fallbackDay
                    migratedDeniedOnUncertain = true
                default:
                    migratedWithdrawnOn = fallbackDay
                    migratedWithdrawnOnUncertain = true
                }
            }
        }
        let migratedNotAppliedOn = decodedNotAppliedOn ?? ((decodedResult == "Ej sökt") ? legacyDecisionOn : nil)
        let migratedNotAppliedOnUncertain = decodedNotAppliedOn != nil ? decodedNotAppliedOnUncertain : ((decodedResult == "Ej sökt") ? legacyDecisionOnUncertain : false)

        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            rowNumber: try container.decodeIfPresent(Int.self, forKey: .rowNumber) ?? 0,
            organizationID: try container.decodeIfPresent(String.self, forKey: .organizationID),
            organization: try container.decodeIfPresent(String.self, forKey: .organization) ?? "",
            grantName: try container.decodeIfPresent(String.self, forKey: .grantName) ?? "",
            grantNameSv: try container.decodeIfPresent(String.self, forKey: .grantNameSv),
            grantNameEn: try container.decodeIfPresent(String.self, forKey: .grantNameEn),
            grantCategory: try container.decodeIfPresent(String.self, forKey: .grantCategory),
            currency: try container.decodeIfPresent(String.self, forKey: .currency) ?? "SEK",
            maxAmount: try container.decodeIfPresent(String.self, forKey: .maxAmount),
            yearCount: try container.decodeIfPresent(String.self, forKey: .yearCount),
            employmentPercentage: try container.decodeIfPresent(String.self, forKey: .employmentPercentage),
            employmentMonths: try container.decodeIfPresent(String.self, forKey: .employmentMonths),
            salaryIncludesOverhead: try container.decodeIfPresent(Bool.self, forKey: .salaryIncludesOverhead) ?? true,
            approximateAmount: try container.decodeIfPresent(String.self, forKey: .approximateAmount),
            approximateAmountValue: try container.decodeIfPresent(Double.self, forKey: .approximateAmountValue),
            opensOn: try container.decodeIfPresent(String.self, forKey: .opensOn),
            opensOnUncertain: try container.decodeIfPresent(Bool.self, forKey: .opensOnUncertain) ?? false,
            closesOn: try container.decodeIfPresent(String.self, forKey: .closesOn),
            closesOnUncertain: try container.decodeIfPresent(Bool.self, forKey: .closesOnUncertain) ?? false,
            decisionExpectedOn: try container.decodeIfPresent(String.self, forKey: .decisionExpectedOn),
            decisionExpectedOnUncertain: try container.decodeIfPresent(Bool.self, forKey: .decisionExpectedOnUncertain) ?? false,
            firstDispositionOn: try container.decodeIfPresent(String.self, forKey: .firstDispositionOn),
            firstDispositionOnUncertain: try container.decodeIfPresent(Bool.self, forKey: .firstDispositionOnUncertain) ?? false,
            lastDispositionOn: try container.decodeIfPresent(String.self, forKey: .lastDispositionOn),
            lastDispositionOnUncertain: try container.decodeIfPresent(Bool.self, forKey: .lastDispositionOnUncertain) ?? false,
            projectID: try container.decodeIfPresent(String.self, forKey: .projectID),
            projectType: try container.decodeIfPresent(String.self, forKey: .projectType),
            dispositionYears: try container.decodeIfPresent(String.self, forKey: .dispositionYears),
            applicantCriteria: try container.decodeIfPresent(String.self, forKey: .applicantCriteria),
            projectCriteria: try container.decodeIfPresent(String.self, forKey: .projectCriteria),
            primaryLink: try container.decodeIfPresent(String.self, forKey: .primaryLink),
            secondaryLink: try container.decodeIfPresent(String.self, forKey: .secondaryLink),
            appliedOn: try container.decodeIfPresent(String.self, forKey: .appliedOn),
            appliedOnUncertain: try container.decodeIfPresent(Bool.self, forKey: .appliedOnUncertain) ?? false,
            appliedCaseNumber: try container.decodeIfPresent(String.self, forKey: .appliedCaseNumber),
            appliedAmount: try container.decodeIfPresent(String.self, forKey: .appliedAmount),
            appliedAmountValue: try container.decodeIfPresent(Double.self, forKey: .appliedAmountValue),
            grantedOn: migratedGrantedOn,
            grantedOnUncertain: migratedGrantedOnUncertain,
            deniedOn: migratedDeniedOn,
            deniedOnUncertain: migratedDeniedOnUncertain,
            withdrawnOn: migratedWithdrawnOn,
            withdrawnOnUncertain: migratedWithdrawnOnUncertain,
            notAppliedOn: migratedNotAppliedOn,
            notAppliedOnUncertain: migratedNotAppliedOnUncertain,
            decisionOn: legacyDecisionOn,
            decisionOnUncertain: legacyDecisionOnUncertain,
            grantedAmount: try container.decodeIfPresent(String.self, forKey: .grantedAmount),
            grantedAmountValue: try container.decodeIfPresent(Double.self, forKey: .grantedAmountValue),
            result: decodedResult,
            institutionCaseNumber: try container.decodeIfPresent(String.self, forKey: .institutionCaseNumber),
            applicationManagerID: try container.decodeIfPresent(String.self, forKey: .applicationManagerID),
            applicationManager: try container.decodeIfPresent(String.self, forKey: .applicationManager),
            managerReason: try container.decodeIfPresent(String.self, forKey: .managerReason),
            applicationTitle: try container.decodeIfPresent(String.self, forKey: .applicationTitle),
            coApplicants: try container.decodeIfPresent([String].self, forKey: .coApplicants) ?? [],
            coApplicantAuthorIDs: try container.decodeIfPresent([String].self, forKey: .coApplicantAuthorIDs) ?? [],
            appliedYear: try container.decodeIfPresent(String.self, forKey: .appliedYear),
            fundingSalary: try container.decodeIfPresent(Bool.self, forKey: .fundingSalary) ?? false,
            fundingMaterials: try container.decodeIfPresent(Bool.self, forKey: .fundingMaterials) ?? false,
            fundingPhDStudents: try container.decodeIfPresent(Bool.self, forKey: .fundingPhDStudents) ?? false,
            receivedProjectNumber: try container.decodeIfPresent(String.self, forKey: .receivedProjectNumber),
            receivedDisplayName: try container.decodeIfPresent(String.self, forKey: .receivedDisplayName),
            receivedPEOE: try container.decodeIfPresent(String.self, forKey: .receivedPEOE),
            receivedConsumedAmount: try container.decodeIfPresent(String.self, forKey: .receivedConsumedAmount),
            receivedConsumedAmountValue: try container.decodeIfPresent(Double.self, forKey: .receivedConsumedAmountValue),
            receivedConsumptionPeriods: try container.decodeIfPresent([GrantConsumptionPeriod].self, forKey: .receivedConsumptionPeriods) ?? [],
            receivedUsageFrom: try container.decodeIfPresent(String.self, forKey: .receivedUsageFrom),
            receivedUsageFromUncertain: try container.decodeIfPresent(Bool.self, forKey: .receivedUsageFromUncertain) ?? false,
            receivedUsageTo: try container.decodeIfPresent(String.self, forKey: .receivedUsageTo),
            receivedUsageToUncertain: try container.decodeIfPresent(Bool.self, forKey: .receivedUsageToUncertain) ?? false,
            receivedRepaymentRequirement: try container.decodeIfPresent(String.self, forKey: .receivedRepaymentRequirement),
            receivedRepaymentDueOn: try container.decodeIfPresent(String.self, forKey: .receivedRepaymentDueOn),
            receivedRepaidOn: try container.decodeIfPresent(String.self, forKey: .receivedRepaidOn),
            isEditingLocked: try container.decodeIfPresent(Bool.self, forKey: .isEditingLocked) ?? false,
            funderMaxOverheadPercent: try container.decodeIfPresent(Double.self, forKey: .funderMaxOverheadPercent),
            managerOverheadPercent: try container.decodeIfPresent(Double.self, forKey: .managerOverheadPercent),
            cofundingDecision: (try container.decodeIfPresent(String.self, forKey: .cofundingDecision))
                .flatMap(GrantCofundingDecision.init(rawValue:)),
            cofundingDecisionOn: try container.decodeIfPresent(String.self, forKey: .cofundingDecisionOn),
            overheadNumbersSetByHand: try container.decodeIfPresent(Bool.self, forKey: .overheadNumbersSetByHand) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(rowNumber, forKey: .rowNumber)
        try container.encodeIfPresent(organizationID, forKey: .organizationID)
        try container.encode(organization, forKey: .organization)
        try container.encode(grantName, forKey: .grantName)
        try container.encode(grantNameSv, forKey: .grantNameSv)
        try container.encode(grantNameEn, forKey: .grantNameEn)
        try container.encodeIfPresent(grantCategory, forKey: .grantCategory)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(maxAmount, forKey: .maxAmount)
        try container.encodeIfPresent(yearCount, forKey: .yearCount)
        try container.encodeIfPresent(employmentPercentage, forKey: .employmentPercentage)
        try container.encodeIfPresent(employmentMonths, forKey: .employmentMonths)
        try container.encode(salaryIncludesOverhead, forKey: .salaryIncludesOverhead)
        try container.encodeIfPresent(approximateAmount, forKey: .approximateAmount)
        try container.encodeIfPresent(approximateAmountValue, forKey: .approximateAmountValue)
        try container.encodeIfPresent(opensOn, forKey: .opensOn)
        try container.encode(opensOnUncertain, forKey: .opensOnUncertain)
        try container.encodeIfPresent(closesOn, forKey: .closesOn)
        try container.encode(closesOnUncertain, forKey: .closesOnUncertain)
        try container.encodeIfPresent(decisionExpectedOn, forKey: .decisionExpectedOn)
        try container.encode(decisionExpectedOnUncertain, forKey: .decisionExpectedOnUncertain)
        try container.encodeIfPresent(firstDispositionOn, forKey: .firstDispositionOn)
        try container.encode(firstDispositionOnUncertain, forKey: .firstDispositionOnUncertain)
        try container.encodeIfPresent(lastDispositionOn, forKey: .lastDispositionOn)
        try container.encode(lastDispositionOnUncertain, forKey: .lastDispositionOnUncertain)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(projectType, forKey: .projectType)
        try container.encodeIfPresent(dispositionYears, forKey: .dispositionYears)
        try container.encodeIfPresent(applicantCriteria, forKey: .applicantCriteria)
        try container.encodeIfPresent(projectCriteria, forKey: .projectCriteria)
        try container.encodeIfPresent(primaryLink, forKey: .primaryLink)
        try container.encodeIfPresent(secondaryLink, forKey: .secondaryLink)
        try container.encodeIfPresent(appliedOn, forKey: .appliedOn)
        try container.encode(appliedOnUncertain, forKey: .appliedOnUncertain)
        try container.encodeIfPresent(appliedCaseNumber, forKey: .appliedCaseNumber)
        try container.encodeIfPresent(appliedAmount, forKey: .appliedAmount)
        try container.encodeIfPresent(appliedAmountValue, forKey: .appliedAmountValue)
        try container.encodeIfPresent(grantedOn, forKey: .grantedOn)
        try container.encode(grantedOnUncertain, forKey: .grantedOnUncertain)
        try container.encodeIfPresent(deniedOn, forKey: .deniedOn)
        try container.encode(deniedOnUncertain, forKey: .deniedOnUncertain)
        try container.encodeIfPresent(withdrawnOn, forKey: .withdrawnOn)
        try container.encode(withdrawnOnUncertain, forKey: .withdrawnOnUncertain)
        try container.encodeIfPresent(notAppliedOn, forKey: .notAppliedOn)
        try container.encode(notAppliedOnUncertain, forKey: .notAppliedOnUncertain)
        try container.encodeIfPresent(decisionOn, forKey: .decisionOn)
        try container.encode(decisionOnUncertain, forKey: .decisionOnUncertain)
        try container.encodeIfPresent(grantedAmount, forKey: .grantedAmount)
        try container.encodeIfPresent(grantedAmountValue, forKey: .grantedAmountValue)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(institutionCaseNumber, forKey: .institutionCaseNumber)
        try container.encodeIfPresent(applicationManagerID, forKey: .applicationManagerID)
        try container.encodeIfPresent(applicationManager, forKey: .applicationManager)
        try container.encodeIfPresent(managerReason, forKey: .managerReason)
        try container.encodeIfPresent(applicationTitle, forKey: .applicationTitle)
        try container.encode(coApplicants, forKey: .coApplicants)
        if !coApplicantAuthorIDs.isEmpty {
            try container.encode(coApplicantAuthorIDs, forKey: .coApplicantAuthorIDs)
        }
        try container.encodeIfPresent(appliedYear, forKey: .appliedYear)
        try container.encode(fundingSalary, forKey: .fundingSalary)
        try container.encode(fundingMaterials, forKey: .fundingMaterials)
        try container.encode(fundingPhDStudents, forKey: .fundingPhDStudents)
        try container.encodeIfPresent(receivedProjectNumber, forKey: .receivedProjectNumber)
        try container.encodeIfPresent(receivedDisplayName, forKey: .receivedDisplayName)
        try container.encodeIfPresent(receivedPEOE, forKey: .receivedPEOE)
        try container.encodeIfPresent(receivedConsumedAmount, forKey: .receivedConsumedAmount)
        try container.encodeIfPresent(receivedConsumedAmountValue, forKey: .receivedConsumedAmountValue)
        try container.encode(receivedConsumptionPeriods, forKey: .receivedConsumptionPeriods)
        try container.encodeIfPresent(receivedUsageFrom, forKey: .receivedUsageFrom)
        try container.encode(receivedUsageFromUncertain, forKey: .receivedUsageFromUncertain)
        try container.encodeIfPresent(receivedUsageTo, forKey: .receivedUsageTo)
        try container.encode(receivedUsageToUncertain, forKey: .receivedUsageToUncertain)
        try container.encodeIfPresent(receivedRepaymentRequirement, forKey: .receivedRepaymentRequirement)
        try container.encodeIfPresent(receivedRepaymentDueOn, forKey: .receivedRepaymentDueOn)
        try container.encodeIfPresent(receivedRepaidOn, forKey: .receivedRepaidOn)
        try container.encode(isEditingLocked, forKey: .isEditingLocked)
        try container.encodeIfPresent(funderMaxOverheadPercent, forKey: .funderMaxOverheadPercent)
        try container.encodeIfPresent(managerOverheadPercent, forKey: .managerOverheadPercent)
        try container.encodeIfPresent(cofundingDecision?.rawValue, forKey: .cofundingDecision)
        try container.encodeIfPresent(cofundingDecisionOn, forKey: .cofundingDecisionOn)
        if overheadNumbersSetByHand {
            try container.encode(true, forKey: .overheadNumbersSetByHand)
        }
    }

    var displayTitle: String {
        switch (organization.nonEmpty, grantName.nonEmpty) {
        case let (.some(organization), .some(grant)):
            return "\(organization), \(grant)"
        case let (.some(organization), nil):
            return organization
        case let (nil, .some(grant)):
            return grant
        default:
            return ""
        }
    }

    var displaySubtitle: String {
        organization
    }

    var grantName: String {
        get { grantNameSv.nonEmpty ?? grantNameEn }
        set {
            grantNameSv = newValue
            grantNameEn = newValue
        }
    }

    func localizedGrantName(language: AppLanguage) -> String {
        if language == .swedish {
            return grantNameSv.nonEmpty ?? grantNameEn
        }
        return grantNameEn.nonEmpty ?? grantNameSv
    }

    mutating func setLocalizedGrantName(_ value: String, language: AppLanguage) {
        if language == .swedish {
            grantNameSv = value
        } else {
            grantNameEn = value
        }
    }

    var resultLabel: String {
        derivedResult ?? "Att söka"
    }

    var openDate: Date? {
        DateParsers.isoDay.date(from: opensOn ?? "")
    }

    var closeDate: Date? {
        DateParsers.isoDay.date(from: closesOn ?? "")
    }

    var applicationDate: Date? {
        DateParsers.isoDay.date(from: appliedOn ?? "")
    }

    var decisionDate: Date? {
        resolvedDecisionDateString.flatMap(DateParsers.isoDay.date(from:))
    }

    var grantedDate: Date? {
        DateParsers.isoDay.date(from: grantedOn ?? "")
    }

    var deniedDate: Date? {
        DateParsers.isoDay.date(from: deniedOn ?? "")
    }

    var withdrawnDate: Date? {
        DateParsers.isoDay.date(from: withdrawnOn ?? "")
    }

    var notAppliedDate: Date? {
        DateParsers.isoDay.date(from: notAppliedOn ?? "")
    }

    var decisionExpectedDate: Date? {
        DateParsers.isoDay.date(from: decisionExpectedOn ?? "")
    }

    var firstDispositionDate: Date? {
        DateParsers.isoDay.date(from: firstDispositionOn ?? "")
    }

    var lastDispositionDate: Date? {
        DateParsers.isoDay.date(from: lastDispositionOn ?? "")
    }

    var maximumAmountValue: Double? {
        GrantParsing.numericValue(from: maxAmount)
    }

    var maximumTotalAmountValue: Double? {
        guard let annual = maximumAmountValue else { return nil }
        let years = GrantParsing.largestNumber(in: yearCount) ?? 0
        guard years > 0 else { return annual }
        return annual * years
    }

    var isFullySpent: Bool {
        guard isGranted, let granted = grantedAmountValue, granted > 0, let consumed = receivedConsumedAmountValue else {
            return false
        }
        return consumed >= granted - 0.5
    }

    var remainingGrantedAmountValue: Double? {
        guard let granted = grantedAmountValue else { return nil }
        let consumed = receivedConsumedAmountValue ?? 0
        return max(0, granted - consumed)
    }

    var preferredBudgetAmountValue: Double? {
        // The salary calculator's estimate is always in SEK, so it only
        // stands in for the budget when the application is in SEK too;
        // otherwise it would be converted as if it were euros or dollars.
        let sekEstimate = currencyCode == "SEK" ? approximateAmountValue : nil
        return maximumTotalAmountValue ?? maximumAmountValue ?? sekEstimate ?? grantedAmountValue ?? appliedAmountValue
    }

    var sortOrganization: String { organization }
    var sortGrantName: String { grantName }
    var sortAppliedOn: String { appliedOn ?? "" }
    var sortOpensOn: String { opensOn ?? "" }
    var sortClosesOn: String { closesOn ?? "" }
    var sortProject: String { projectType ?? "" }
    var sortAppliedCaseNumber: String { appliedCaseNumber ?? "" }
    var sortMaximumAmount: Double { preferredBudgetAmountValue ?? 0 }

    var searchableBlob: String {
        [
            organization,
            grantName,
            grantCategory,
            result,
            projectType,
            applicationManager,
            managerReason,
            applicationTitle,
            coApplicants.joined(separator: " "),
            applicantCriteria,
            projectCriteria,
            maxAmount,
            appliedCaseNumber,
            employmentPercentage,
            employmentMonths,
            approximateAmount,
            receivedProjectNumber,
            receivedDisplayName,
            receivedPEOE,
            receivedConsumedAmount,
            receivedConsumptionPeriods.map(\.amount).joined(separator: " "),
            ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }

    var isGranted: Bool {
        // The status is one of the app's own fixed words, so a plain
        // case-insensitive match is enough. The localized variant follows the
        // Mac's region and is markedly slower under Swedish settings, which
        // matters here: this runs many times per application on every redraw.
        resultLabel.range(of: "Beviljat", options: .caseInsensitive) != nil
    }

    /// "<250 k", "250 k - 1 mil" or "≥1 mil" with the limits from Settings.
    var amountBucketLabel: String {
        WorkflowDefaultSettingsRegistry.current.amountBucketLabel(amountBucket)
    }

    var statsYear: String {
        if let appliedOn, appliedOn.count >= 4 {
            return String(appliedOn.prefix(4))
        }
        if let closesOn, closesOn.count >= 4 {
            return String(closesOn.prefix(4))
        }
        if let appliedYear = appliedYear?.nonEmpty {
            return appliedYear
        }
        return String(Calendar.current.component(.year, from: Date()))
    }

    var isToApplyStatus: Bool {
        let status = resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return status.isEmpty || status == "Att söka"
    }

    var isNotAppliedStatus: Bool {
        resultLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "Ej sökt"
    }

    var isNonGrantedForWorklists: Bool {
        !isGranted && !isNotAppliedStatus
    }

    mutating func refreshDerivedValues() {
        organizationID = organizationID?.trimmedOrNil
        grantCategory = grantCategory?.trimmedOrNil
        currency = currency?.trimmedOrNil ?? "SEK"
        opensOn = opensOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        closesOn = closesOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        maxAmount = maxAmount?.trimmedOrNil
        yearCount = yearCount?.trimmedOrNil
        employmentPercentage = employmentPercentage?.trimmedOrNil
        employmentMonths = employmentMonths?.trimmedOrNil
        approximateAmount = GrantParsing.formatAmountInput(approximateAmount)
        projectType = projectType?.trimmedOrNil
        dispositionYears = dispositionYears?.trimmedOrNil
        applicantCriteria = applicantCriteria?.trimmedOrNil
        projectCriteria = projectCriteria?.trimmedOrNil
        primaryLink = primaryLink?.trimmedOrNil
        secondaryLink = secondaryLink?.trimmedOrNil
        appliedOn = appliedOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        decisionExpectedOn = decisionExpectedOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        firstDispositionOn = firstDispositionOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        lastDispositionOn = lastDispositionOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        projectID = projectID?.trimmedOrNil
        grantedOn = grantedOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        deniedOn = deniedOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        withdrawnOn = withdrawnOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        notAppliedOn = notAppliedOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        appliedCaseNumber = appliedCaseNumber?.trimmedOrNil
        result = result?.trimmedOrNil
        institutionCaseNumber = institutionCaseNumber?.trimmedOrNil
        applicationManager = applicationManager?.trimmedOrNil
        managerReason = managerReason?.trimmedOrNil
        applicationTitle = applicationTitle?.trimmedOrNil
        coApplicants = Array(
            NSOrderedSet(array: coApplicants.compactMap(\.trimmedOrNil))
        ) as? [String] ?? []
        coApplicantAuthorIDs = Array(
            NSOrderedSet(array: coApplicantAuthorIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? []
        appliedYear = appliedYear?.trimmedOrNil
        appliedAmount = GrantParsing.formatAmountInput(appliedAmount)
        grantedAmount = GrantParsing.formatAmountInput(grantedAmount)
        appliedAmountValue = GrantParsing.numericValue(from: appliedAmount)
        grantedAmountValue = GrantParsing.numericValue(from: grantedAmount)
        approximateAmountValue = GrantParsing.numericValue(from: approximateAmount)
        applicationManagerID = applicationManagerID?.trimmedOrNil
        result = derivedResult
        decisionOn = resolvedDecisionDateString
        decisionOnUncertain = resolvedDecisionUncertainty

        if isGranted {
            receivedProjectNumber = receivedProjectNumber?.trimmedOrNil
            receivedDisplayName = receivedDisplayName?.trimmedOrNil
            receivedPEOE = receivedPEOE?.trimmedOrNil
            receivedConsumptionPeriods = receivedConsumptionPeriods
                .map {
                    GrantConsumptionPeriod(
                        id: $0.id,
                        from: DateParsers.canonicalizedDayInput($0.from),
                        to: DateParsers.canonicalizedDayInput($0.to),
                        amount: GrantParsing.formatAmountInput($0.amount) ?? ""
                    )
                }
            let consumedTotal = receivedConsumptionPeriods.compactMap(\.amountValue).reduce(0, +)
            if consumedTotal > 0 {
                receivedConsumedAmountValue = consumedTotal
                receivedConsumedAmount = GrantParsing.formatAmountInput(String(Int(consumedTotal.rounded())))
            } else {
                receivedConsumedAmount = nil
                receivedConsumedAmountValue = nil
            }
            receivedUsageFrom = receivedUsageFrom.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
            receivedUsageTo = receivedUsageTo.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
            receivedRepaymentRequirement = receivedRepaymentRequirement?.trimmedOrNil
            receivedRepaymentDueOn = receivedRepaymentDueOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
            receivedRepaidOn = receivedRepaidOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        } else {
            grantedAmount = nil
            grantedAmountValue = nil
            receivedProjectNumber = nil
            receivedDisplayName = nil
            receivedPEOE = nil
            receivedConsumedAmount = nil
            receivedConsumedAmountValue = nil
            receivedConsumptionPeriods = []
            receivedUsageFrom = nil
            receivedUsageTo = nil
            receivedRepaymentRequirement = nil
            receivedRepaymentDueOn = nil
            receivedRepaidOn = nil
        }
    }

    var derivedResult: String? {
        if let resolved = resolvedDecisionDateString {
            if resolved == grantedOn?.trimmedOrNil {
                return "Beviljat"
            }
            if resolved == deniedOn?.trimmedOrNil {
                return "Avslag"
            }
            if resolved == withdrawnOn?.trimmedOrNil {
                return "Tillbakadragen"
            }
        }
        if notAppliedOn?.trimmedOrNil != nil {
            return "Ej sökt"
        }
        if appliedOn?.trimmedOrNil != nil {
            return "Väntar svar"
        }
        let trimmedStored = result?.trimmedOrNil
        if trimmedStored == nil {
            return "Att söka"
        }
        if trimmedStored == "Väntar svar" {
            return "Att söka"
        }
        if trimmedStored == "Att söka" {
            return trimmedStored
        }
        return trimmedStored
    }

    var resolvedDecisionDateString: String? {
        let resolvedDates = [
            ("Beviljat", grantedOn?.trimmedOrNil, grantedDate),
            ("Avslag", deniedOn?.trimmedOrNil, deniedDate),
            ("Tillbakadragen", withdrawnOn?.trimmedOrNil, withdrawnDate),
        ]
        .compactMap { status, raw, parsed -> (String, String, Date?)? in
            guard let raw else { return nil }
            return (status, raw, parsed)
        }

        if let latestParsed = resolvedDates
            .compactMap({ entry -> (String, String, Date)? in
                guard let date = entry.2 else { return nil }
                return (entry.0, entry.1, date)
            })
            .max(by: { $0.2 < $1.2 }) {
            return latestParsed.1
        }

        return resolvedDates.first?.1 ?? decisionOn?.trimmedOrNil
    }

    var resolvedDecisionUncertainty: Bool {
        if let resolved = resolvedDecisionDateString {
            if resolved == grantedOn?.trimmedOrNil {
                return grantedOnUncertain
            }
            if resolved == deniedOn?.trimmedOrNil {
                return deniedOnUncertain
            }
            if resolved == withdrawnOn?.trimmedOrNil {
                return withdrawnOnUncertain
            }
        }
        return decisionOnUncertain
    }
}

enum OrganizationRole: String, Codable, Hashable, CaseIterable {
    case grantProvider
    case fundManager
    case employer
    case institution
    case association
    case company
}

enum ProjectLifecycleStatus: String, Codable, Hashable, CaseIterable {
    case planned
    case ongoing
    case completed
}

enum ProjectTaskReminder: String, Codable, Hashable, CaseIterable {
    case none
    case dataCollectionCompleted
    case publicationAdded
    case newFundsReceived
    case fundsRunOut
    case publicationPublished
    case manualFollowUp
    case grantCallOpens
    case applicationDeadline
    case decisionDate
    case reportingDeadline
    case finalReportDeadline
    case fundsReceived
    case internalBudgetDeadline
    case projectEndDate
    case employmentStart
    case employmentEnd
    case budgetPeriodStart
    case budgetPeriodEnd
    case salaryRevisionDate
    case termStart
    case termEnd
    case courseStart
    case courseEnd
    case examinationDate
    case congressStart
    case congressEnd
    case abstractDeadline
    case lateAbstractDeadline
    case membershipStart
    case membershipEnd
    case annualMeetingDate
}

struct ProjectEthicsApplication: Codable, Hashable, Identifiable {
    var id: String
    var appliedOn: String
    var grantedOn: String
    var caseNumber: String

    init(
        id: String = UUID().uuidString,
        appliedOn: String = "",
        grantedOn: String = "",
        caseNumber: String = ""
    ) {
        self.id = id
        self.appliedOn = appliedOn
        self.grantedOn = grantedOn
        self.caseNumber = caseNumber
    }

    var isEmpty: Bool {
        appliedOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && grantedOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && caseNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ProjectClinicalTrialRegistration: Codable, Hashable, Identifiable {
    var id: String
    var registeredOn: String
    var updatedOn: String
    var trialID: String

    init(
        id: String = UUID().uuidString,
        registeredOn: String = "",
        updatedOn: String = "",
        trialID: String = ""
    ) {
        self.id = id
        self.registeredOn = registeredOn
        self.updatedOn = updatedOn
        self.trialID = trialID
    }

    var isEmpty: Bool {
        registeredOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && updatedOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && trialID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ProjectPrincipalOrganization: Codable, Hashable, Identifiable {
    var id: String
    var organizationID: String?
    var organizationName: String
    var caseNumber: String

    init(
        id: String = UUID().uuidString,
        organizationID: String? = nil,
        organizationName: String = "",
        caseNumber: String = ""
    ) {
        self.id = id
        self.organizationID = organizationID
        self.organizationName = organizationName
        self.caseNumber = caseNumber
    }

    mutating func normalize() {
        organizationID = organizationID?.trimmedOrNil
        organizationName = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        caseNumber = caseNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        organizationID?.trimmedOrNil == nil
            && organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && caseNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ProjectDataCollection: Codable, Hashable {
    var id: String
    var from: String
    var to: String

    enum CodingKeys: String, CodingKey {
        case id
        case from
        case to
    }

    init(id: String = UUID().uuidString, from: String = "", to: String = "") {
        self.id = id
        self.from = from
        self.to = to
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.from = try container.decodeIfPresent(String.self, forKey: .from) ?? ""
        self.to = try container.decodeIfPresent(String.self, forKey: .to) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
    }

    var isEmpty: Bool {
        from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ProjectTaskItem: Codable, Hashable, Identifiable {
    var id: String
    var createdOn: String
    var updatedOn: String
    var deadline: String
    var reminder: ProjectTaskReminder
    var comment: String
    var note: String
    var participantNames: [String]
    /// Id links to the researchers in `participantNames`; the names stay as display text.
    var participantAuthorIDs: [String]
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
        case reminder
        case comment
        case note
        case participantNames
        case participantAuthorIDs
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
        reminder: ProjectTaskReminder = .none,
        comment: String = "",
        note: String = "",
        participantNames: [String] = [],
        participantAuthorIDs: [String] = [],
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
        self.reminder = reminder
        self.comment = comment
        self.note = note
        self.participantNames = participantNames
        self.participantAuthorIDs = participantAuthorIDs
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
        reminder = try container.decodeIfPresent(ProjectTaskReminder.self, forKey: .reminder) ?? .none
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        participantNames = try container.decodeIfPresent([String].self, forKey: .participantNames) ?? []
        participantAuthorIDs = try container.decodeIfPresent([String].self, forKey: .participantAuthorIDs) ?? []
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
        try container.encode(reminder, forKey: .reminder)
        try container.encode(comment, forKey: .comment)
        try container.encode(note, forKey: .note)
        try container.encode(participantNames, forKey: .participantNames)
        if !participantAuthorIDs.isEmpty {
            try container.encode(participantAuthorIDs, forKey: .participantAuthorIDs)
        }
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
        createdOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && updatedOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && deadline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && participantNames.isEmpty
            && publicationID?.trimmedOrNil == nil
            && applicationID?.trimmedOrNil == nil
            && reminder == .none
            && agendaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && protocolText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A first-class task shared by every workspace.  Legacy, host-owned task
/// collections are retained solely for backwards-compatible decoding while
/// existing data is migrated here without changing task identifiers.
enum TaskLinkKind: String, Codable, Hashable, CaseIterable {
    case project
    case organization
    case publication
    case application
    case teachingAssignment
    case teachingCourse
    case doctoralCandidate
    case congress
    case conferenceContribution
    case review
}

struct TaskLink: Codable, Hashable, Identifiable {
    var kind: TaskLinkKind
    var targetID: String
    /// Needed only for entities nested below another record, currently congresses.
    var ownerID: String?

    var id: String { "\(kind.rawValue)#\(ownerID ?? "")#\(targetID)" }

    init(kind: TaskLinkKind, targetID: String, ownerID: String? = nil) {
        self.kind = kind
        self.targetID = targetID
        self.ownerID = ownerID
    }

    func normalized() -> TaskLink? {
        guard let targetID = targetID.trimmedOrNil else { return nil }
        return TaskLink(kind: kind, targetID: targetID, ownerID: ownerID?.trimmedOrNil)
    }
}

struct TaskItem: Codable, Hashable, Identifiable {
    var id: String
    var createdOn: String
    var updatedOn: String
    /// The calendar date/deadline. A task without one remains visible only in its linked workspaces.
    var deadline: String
    /// Optional clock time ("HH:mm") on the deadline day; nil means the whole day.
    var deadlineTime: String?
    /// An optional event trigger which complements, rather than replaces, the deadline.
    var reminder: ProjectTaskReminder
    var comment: String
    var note: String
    var participantNames: [String]
    /// Id links to the researchers in `participantNames`; the names stay as display text.
    var participantAuthorIDs: [String]
    var links: [TaskLink]
    /// Set only by an explicit user action. Due/overdue status is derived separately.
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
        case deadlineTime
        case reminder
        case comment
        case note
        case participantNames
        case participantAuthorIDs
        case links
        case completedOn
        case agendaText
        case protocolText
    }

    init(
        id: String = UUID().uuidString,
        createdOn: String = "",
        updatedOn: String = "",
        deadline: String = "",
        deadlineTime: String? = nil,
        reminder: ProjectTaskReminder = .none,
        comment: String = "",
        note: String = "",
        participantNames: [String] = [],
        participantAuthorIDs: [String] = [],
        links: [TaskLink] = [],
        completedOn: String? = nil,
        agendaText: String = "",
        protocolText: String = ""
    ) {
        self.id = id
        self.createdOn = createdOn
        self.updatedOn = updatedOn
        self.deadline = deadline
        self.deadlineTime = deadlineTime
        self.reminder = reminder
        self.comment = comment
        self.note = note
        self.participantNames = participantNames
        self.participantAuthorIDs = participantAuthorIDs
        self.links = links
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
        deadlineTime = try container.decodeIfPresent(String.self, forKey: .deadlineTime)
        reminder = try container.decodeIfPresent(ProjectTaskReminder.self, forKey: .reminder) ?? .none
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        participantNames = try container.decodeIfPresent([String].self, forKey: .participantNames) ?? []
        participantAuthorIDs = try container.decodeIfPresent([String].self, forKey: .participantAuthorIDs) ?? []
        links = try container.decodeIfPresent([TaskLink].self, forKey: .links) ?? []
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
        try container.encodeIfPresent(deadlineTime, forKey: .deadlineTime)
        try container.encode(reminder, forKey: .reminder)
        try container.encode(comment, forKey: .comment)
        try container.encode(note, forKey: .note)
        try container.encode(participantNames, forKey: .participantNames)
        if !participantAuthorIDs.isEmpty {
            try container.encode(participantAuthorIDs, forKey: .participantAuthorIDs)
        }
        try container.encode(links, forKey: .links)
        try container.encodeIfPresent(completedOn, forKey: .completedOn)
        try container.encode(agendaText, forKey: .agendaText)
        try container.encode(protocolText, forKey: .protocolText)
    }

    mutating func normalize() {
        createdOn = DateParsers.canonicalizedDayInput(createdOn)
        updatedOn = DateParsers.canonicalizedDayInput(updatedOn)
        deadline = DateParsers.canonicalizedDayInput(deadline)
        deadlineTime = deadline.trimmedOrNil == nil ? nil : Self.normalizedDeadlineTime(deadlineTime)
        comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        participantNames = Array(NSOrderedSet(array: participantNames.compactMap(\.trimmedOrNil))) as? [String]
            ?? participantNames.compactMap(\.trimmedOrNil)
        participantAuthorIDs = Array(NSOrderedSet(array: participantAuthorIDs.compactMap(\.trimmedOrNil))) as? [String]
            ?? participantAuthorIDs.compactMap(\.trimmedOrNil)
        links = Array(Dictionary(firstWinsKeysWithValues: links.compactMap { $0.normalized() }.map { ($0.id, $0) }).values)
            .sorted { $0.id < $1.id }
        completedOn = completedOn.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        agendaText = agendaText.trimmingCharacters(in: .whitespacesAndNewlines)
        protocolText = protocolText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        comment.trimmedOrNil == nil
            && note.trimmedOrNil == nil
            && deadline.trimmedOrNil == nil
            && reminder == .none
            && links.isEmpty
            && agendaText.trimmedOrNil == nil
            && protocolText.trimmedOrNil == nil
    }

    var isCompleted: Bool { completedOn?.trimmedOrNil != nil }

    /// "9", "930", "9.30" and "09:30" become "09:30"; empty or unreadable input is nil.
    static func normalizedDeadlineTime(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmedOrNil else { return nil }
        return CalendarReminderSettings.normalizedTime(trimmed)
    }

    /// The deadline as shown in lists and exports: "2026-10-15" or "2026-10-15 14:00".
    var deadlineDisplayText: String {
        Self.deadlineDisplayText(day: deadline, time: deadlineTime)
    }

    /// The time shown beside the task in calendar lists: the deadline time,
    /// but only on the deadline day itself (not when an overdue task is
    /// carried over to today, or a completed task is shown on its done day).
    func calendarTimeText(displayDate: Date, calendar: Calendar) -> String {
        guard let time = Self.normalizedDeadlineTime(deadlineTime),
              let moment = deadlineMoment(calendar: calendar),
              calendar.isDate(moment, inSameDayAs: displayDate)
        else { return "" }
        return time
    }

    static func deadlineDisplayText(day: String, time: String?) -> String {
        let trimmedDay = day.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDay.isEmpty, let time = normalizedDeadlineTime(time) else { return trimmedDay }
        return "\(trimmedDay) \(time)"
    }

    /// The moment the deadline passes: the clock time on the deadline day when
    /// one is set, otherwise nil (the whole day counts).
    func deadlineMoment(calendar: Calendar = .current) -> Date? {
        guard let time = Self.normalizedDeadlineTime(deadlineTime),
              let value = CalendarReminderSettings.hourMinute(from: time)
        else { return nil }
        let parts = deadline.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-")
            .compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: value.hour,
            minute: value.minute
        ))
    }

    func hasLink(kind: TaskLinkKind, targetID: String, ownerID: String? = nil) -> Bool {
        links.contains { $0.kind == kind && $0.targetID == targetID && $0.ownerID == ownerID }
    }
}

struct OrganizationCongressFlight: Codable, Hashable, Identifiable {
    var id: String
    var mode: CalendarTravelMode
    var fromCity: String
    var fromCountry: String
    var toCity: String
    var toCountry: String
    var fromDate: String
    var fromTime: String
    var toDate: String
    var toTime: String

    enum CodingKeys: String, CodingKey {
        case id
        case mode
        case fromCity
        case fromCountry
        case toCity
        case toCountry
        case fromDate
        case fromTime
        case toDate
        case toTime
    }

    init(
        id: String = UUID().uuidString,
        mode: CalendarTravelMode = .flight,
        fromCity: String = "",
        fromCountry: String = "",
        toCity: String = "",
        toCountry: String = "",
        fromDate: String = "",
        fromTime: String = "",
        toDate: String = "",
        toTime: String = ""
    ) {
        self.id = id
        self.mode = mode
        self.fromCity = fromCity
        self.fromCountry = fromCountry
        self.toCity = toCity
        self.toCountry = toCountry
        self.fromDate = fromDate
        self.fromTime = fromTime
        self.toDate = toDate
        self.toTime = toTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        mode = try container.decodeIfPresent(CalendarTravelMode.self, forKey: .mode) ?? .flight
        fromCity = try container.decodeIfPresent(String.self, forKey: .fromCity) ?? ""
        fromCountry = try container.decodeIfPresent(String.self, forKey: .fromCountry) ?? ""
        toCity = try container.decodeIfPresent(String.self, forKey: .toCity) ?? ""
        toCountry = try container.decodeIfPresent(String.self, forKey: .toCountry) ?? ""
        fromDate = try container.decodeIfPresent(String.self, forKey: .fromDate) ?? ""
        fromTime = try container.decodeIfPresent(String.self, forKey: .fromTime) ?? ""
        toDate = try container.decodeIfPresent(String.self, forKey: .toDate) ?? ""
        toTime = try container.decodeIfPresent(String.self, forKey: .toTime) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if mode != .flight {
            try container.encode(mode, forKey: .mode)
        }
        if !fromCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(fromCity, forKey: .fromCity)
        }
        if !fromCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(fromCountry, forKey: .fromCountry)
        }
        if !toCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(toCity, forKey: .toCity)
        }
        if !toCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(toCountry, forKey: .toCountry)
        }
        if !fromDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(fromDate, forKey: .fromDate)
        }
        if !fromTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(fromTime, forKey: .fromTime)
        }
        if !toDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(toDate, forKey: .toDate)
        }
        if !toTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(toTime, forKey: .toTime)
        }
    }

    mutating func normalize() {
        id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            id = UUID().uuidString
        }
        fromCity = fromCity.trimmingCharacters(in: .whitespacesAndNewlines)
        fromCountry = fromCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        toCity = toCity.trimmingCharacters(in: .whitespacesAndNewlines)
        toCountry = toCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        fromDate = DateParsers.canonicalizedDayInput(fromDate)
        fromTime = normalizedCalendarTimeInput(fromTime)
        toDate = DateParsers.canonicalizedDayInput(toDate)
        toTime = normalizedCalendarTimeInput(toTime)
    }

    var isEmpty: Bool {
        fromCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fromCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && toCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && toCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fromDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fromTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && toDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && toTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct OrganizationCongressHotel: Codable, Hashable, Identifiable {
    var id: String
    var hotelName: String
    var fromDate: String
    var fromTime: String
    var toDate: String
    var toTime: String

    enum CodingKeys: String, CodingKey {
        case id
        case hotelName
        case fromDate
        case fromTime
        case toDate
        case toTime
    }

    init(
        id: String = UUID().uuidString,
        hotelName: String = "",
        fromDate: String = "",
        fromTime: String = "",
        toDate: String = "",
        toTime: String = ""
    ) {
        self.id = id
        self.hotelName = hotelName
        self.fromDate = fromDate
        self.fromTime = fromTime
        self.toDate = toDate
        self.toTime = toTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        hotelName = try container.decodeIfPresent(String.self, forKey: .hotelName) ?? ""
        fromDate = try container.decodeIfPresent(String.self, forKey: .fromDate) ?? ""
        fromTime = try container.decodeIfPresent(String.self, forKey: .fromTime) ?? ""
        toDate = try container.decodeIfPresent(String.self, forKey: .toDate) ?? ""
        toTime = try container.decodeIfPresent(String.self, forKey: .toTime) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if !hotelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(hotelName, forKey: .hotelName)
        }
        if !fromDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(fromDate, forKey: .fromDate)
        }
        if !fromTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(fromTime, forKey: .fromTime)
        }
        if !toDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(toDate, forKey: .toDate)
        }
        if !toTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(toTime, forKey: .toTime)
        }
    }

    mutating func normalize() {
        id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            id = UUID().uuidString
        }
        hotelName = hotelName.trimmingCharacters(in: .whitespacesAndNewlines)
        fromDate = DateParsers.canonicalizedDayInput(fromDate)
        fromTime = normalizedCalendarTimeInput(fromTime)
        toDate = DateParsers.canonicalizedDayInput(toDate)
        toTime = normalizedCalendarTimeInput(toTime)
    }

    var isEmpty: Bool {
        hotelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fromDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fromTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && toDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && toTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct OrganizationCongress: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var from: String
    var fromUncertain: Bool
    var to: String
    var toUncertain: Bool
    var abstractSubmissionDeadline: String
    var abstractSubmissionDeadlineUncertain: Bool
    var lateAbstractSubmissionDeadline: String
    var lateAbstractSubmissionDeadlineUncertain: Bool
    var venue: String
    var city: String
    var country: String
    var link: String
    var participantNames: [String]
    var participantAuthorIDs: [String]
    var isHiddenOnMap: Bool
    var travelFlights: [OrganizationCongressFlight]
    var travelHotels: [OrganizationCongressHotel]
    var hotelName: String
    var hotelFrom: String
    var hotelFromTime: String
    var hotelTo: String
    var hotelToTime: String
    var congressFeeSEK: String
    var congressFeePaid: Bool
    var fundingApplicationIDs: [String]
    var tasks: [ProjectTaskItem]
    var isEditingLocked: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case from
        case fromUncertain
        case to
        case toUncertain
        case abstractSubmissionDeadline
        case abstractSubmissionDeadlineUncertain
        case lateAbstractSubmissionDeadline
        case lateAbstractSubmissionDeadlineUncertain
        case venue
        case city
        case country
        case link
        case participantNames
        case participantAuthorIDs
        case isHiddenOnMap
        case travelFlights
        case travelHotels
        case hotelName
        case hotelFrom
        case hotelFromTime
        case hotelTo
        case hotelToTime
        case congressFeeSEK
        case congressFeePaid
        case fundingApplicationIDs
        case tasks
        case isEditingLocked
    }

    init(
        id: String = UUID().uuidString,
        title: String = "",
        from: String = "",
        fromUncertain: Bool = false,
        to: String = "",
        toUncertain: Bool = false,
        abstractSubmissionDeadline: String = "",
        abstractSubmissionDeadlineUncertain: Bool = false,
        lateAbstractSubmissionDeadline: String = "",
        lateAbstractSubmissionDeadlineUncertain: Bool = false,
        venue: String = "",
        city: String = "",
        country: String = "",
        link: String = "",
        participantNames: [String] = [],
        participantAuthorIDs: [String] = [],
        isHiddenOnMap: Bool = false,
        travelFlights: [OrganizationCongressFlight] = [],
        travelHotels: [OrganizationCongressHotel] = [],
        hotelName: String = "",
        hotelFrom: String = "",
        hotelFromTime: String = "",
        hotelTo: String = "",
        hotelToTime: String = "",
        congressFeeSEK: String = "",
        congressFeePaid: Bool = false,
        fundingApplicationIDs: [String] = [],
        tasks: [ProjectTaskItem] = [],
        isEditingLocked: Bool = false
    ) {
        self.id = id
        self.title = title
        self.from = from
        self.fromUncertain = fromUncertain
        self.to = to
        self.toUncertain = toUncertain
        self.abstractSubmissionDeadline = abstractSubmissionDeadline
        self.abstractSubmissionDeadlineUncertain = abstractSubmissionDeadlineUncertain
        self.lateAbstractSubmissionDeadline = lateAbstractSubmissionDeadline
        self.lateAbstractSubmissionDeadlineUncertain = lateAbstractSubmissionDeadlineUncertain
        self.venue = venue
        self.city = city
        self.country = country
        self.link = link
        self.participantNames = participantNames
        self.participantAuthorIDs = participantAuthorIDs
        self.isHiddenOnMap = isHiddenOnMap
        self.travelFlights = travelFlights
        self.travelHotels = travelHotels
        self.hotelName = hotelName
        self.hotelFrom = hotelFrom
        self.hotelFromTime = hotelFromTime
        self.hotelTo = hotelTo
        self.hotelToTime = hotelToTime
        self.congressFeeSEK = congressFeeSEK
        self.congressFeePaid = congressFeePaid
        self.fundingApplicationIDs = fundingApplicationIDs
        self.tasks = tasks
        self.isEditingLocked = isEditingLocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        from = try container.decodeIfPresent(String.self, forKey: .from) ?? ""
        fromUncertain = try container.decodeIfPresent(Bool.self, forKey: .fromUncertain) ?? false
        to = try container.decodeIfPresent(String.self, forKey: .to) ?? ""
        toUncertain = try container.decodeIfPresent(Bool.self, forKey: .toUncertain) ?? false
        abstractSubmissionDeadline = try container.decodeIfPresent(String.self, forKey: .abstractSubmissionDeadline) ?? ""
        abstractSubmissionDeadlineUncertain = try container.decodeIfPresent(Bool.self, forKey: .abstractSubmissionDeadlineUncertain) ?? false
        lateAbstractSubmissionDeadline = try container.decodeIfPresent(String.self, forKey: .lateAbstractSubmissionDeadline) ?? ""
        lateAbstractSubmissionDeadlineUncertain = try container.decodeIfPresent(Bool.self, forKey: .lateAbstractSubmissionDeadlineUncertain) ?? false
        venue = try container.decodeIfPresent(String.self, forKey: .venue) ?? ""
        city = try container.decodeIfPresent(String.self, forKey: .city) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        participantNames = try container.decodeIfPresent([String].self, forKey: .participantNames) ?? []
        participantAuthorIDs = try container.decodeIfPresent([String].self, forKey: .participantAuthorIDs) ?? []
        isHiddenOnMap = try container.decodeIfPresent(Bool.self, forKey: .isHiddenOnMap) ?? false
        travelFlights = try container.decodeIfPresent([OrganizationCongressFlight].self, forKey: .travelFlights) ?? []
        travelHotels = try container.decodeIfPresent([OrganizationCongressHotel].self, forKey: .travelHotels) ?? []
        hotelName = try container.decodeIfPresent(String.self, forKey: .hotelName) ?? ""
        hotelFrom = try container.decodeIfPresent(String.self, forKey: .hotelFrom) ?? ""
        hotelFromTime = try container.decodeIfPresent(String.self, forKey: .hotelFromTime) ?? ""
        hotelTo = try container.decodeIfPresent(String.self, forKey: .hotelTo) ?? ""
        hotelToTime = try container.decodeIfPresent(String.self, forKey: .hotelToTime) ?? ""
        congressFeeSEK = try container.decodeIfPresent(String.self, forKey: .congressFeeSEK) ?? ""
        congressFeePaid = try container.decodeIfPresent(Bool.self, forKey: .congressFeePaid) ?? false
        fundingApplicationIDs = try container.decodeIfPresent([String].self, forKey: .fundingApplicationIDs) ?? []
        tasks = try container.decodeIfPresent([ProjectTaskItem].self, forKey: .tasks) ?? []
        isEditingLocked = try container.decodeIfPresent(Bool.self, forKey: .isEditingLocked) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(from, forKey: .from)
        try container.encode(fromUncertain, forKey: .fromUncertain)
        try container.encode(to, forKey: .to)
        try container.encode(toUncertain, forKey: .toUncertain)
        try container.encode(abstractSubmissionDeadline, forKey: .abstractSubmissionDeadline)
        try container.encode(abstractSubmissionDeadlineUncertain, forKey: .abstractSubmissionDeadlineUncertain)
        try container.encode(lateAbstractSubmissionDeadline, forKey: .lateAbstractSubmissionDeadline)
        try container.encode(lateAbstractSubmissionDeadlineUncertain, forKey: .lateAbstractSubmissionDeadlineUncertain)
        if !venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(venue, forKey: .venue)
        }
        try container.encode(city, forKey: .city)
        try container.encode(country, forKey: .country)
        try container.encode(link, forKey: .link)
        if !participantNames.isEmpty {
            try container.encode(participantNames, forKey: .participantNames)
        }
        if !participantAuthorIDs.isEmpty {
            try container.encode(participantAuthorIDs, forKey: .participantAuthorIDs)
        }
        if isHiddenOnMap {
            try container.encode(isHiddenOnMap, forKey: .isHiddenOnMap)
        }
        if !travelFlights.isEmpty {
            try container.encode(travelFlights, forKey: .travelFlights)
        }
        if !travelHotels.isEmpty {
            try container.encode(travelHotels, forKey: .travelHotels)
        }
        if !hotelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(hotelName, forKey: .hotelName)
        }
        if !hotelFrom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(hotelFrom, forKey: .hotelFrom)
        }
        if !hotelFromTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(hotelFromTime, forKey: .hotelFromTime)
        }
        if !hotelTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(hotelTo, forKey: .hotelTo)
        }
        if !hotelToTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(hotelToTime, forKey: .hotelToTime)
        }
        if !congressFeeSEK.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(congressFeeSEK, forKey: .congressFeeSEK)
        }
        if congressFeePaid {
            try container.encode(congressFeePaid, forKey: .congressFeePaid)
        }
        if !fundingApplicationIDs.isEmpty {
            try container.encode(fundingApplicationIDs, forKey: .fundingApplicationIDs)
        }
        if !tasks.isEmpty {
            try container.encode(tasks, forKey: .tasks)
        }
        if isEditingLocked {
            try container.encode(isEditingLocked, forKey: .isEditingLocked)
        }
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && abstractSubmissionDeadline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && lateAbstractSubmissionDeadline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && participantNames.compactMap(\.trimmedOrNil).isEmpty
            && participantAuthorIDs.compactMap(\.trimmedOrNil).isEmpty
            && travelFlights.filter { !$0.isEmpty }.isEmpty
            && travelHotels.filter { !$0.isEmpty }.isEmpty
            && hotelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hotelFrom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hotelFromTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hotelTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hotelToTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && congressFeeSEK.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !congressFeePaid
            && fundingApplicationIDs.compactMap(\.trimmedOrNil).isEmpty
            && tasks.filter { !$0.isEmpty }.isEmpty
    }
}

struct StoredCongressRecord: Codable, Hashable, Identifiable {
    var id: String
    var organizationID: String
    var organizationName: String
    var congress: OrganizationCongress

    init(
        id: String,
        organizationID: String,
        organizationName: String,
        congress: OrganizationCongress
    ) {
        self.id = id
        self.organizationID = organizationID
        self.organizationName = organizationName
        self.congress = congress
    }

    init(organization: OrganizationRecord, congress: OrganizationCongress) {
        self.id = Self.recordID(organizationID: organization.id, congressID: congress.id)
        self.organizationID = organization.id
        self.organizationName = organization.nameSv.nonEmpty ?? organization.nameEn
        self.congress = congress
    }

    static func recordID(organizationID: String, congressID: String) -> String {
        "\(organizationID)#\(congressID)"
    }
}

struct RelationalCoreSnapshot: Codable, Hashable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var generatedAt: String
    var congresses: [RelationalCongressRecord]
    var congressParticipants: [RelationalCongressParticipant]
    var congressFunding: [RelationalCongressFunding]
    var congressTravel: [RelationalCongressTravel]
    var congressAccommodation: [RelationalCongressAccommodation]
    var conferenceContributionCongresses: [RelationalConferenceContributionCongress]
    var conferenceContributionAuthors: [RelationalConferenceContributionAuthor]
    var calendarMeetingProjects: [RelationalCalendarMeetingProject]
    var calendarMeetingOrganizations: [RelationalCalendarMeetingOrganization]
    var calendarMeetingApplications: [RelationalCalendarMeetingApplication]
    var calendarMeetingPublications: [RelationalCalendarMeetingPublication]
}

struct RelationalCongressRecord: Codable, Hashable, Identifiable {
    var id: String
    var organizationID: String
    var title: String
    var from: String
    var to: String
}

struct RelationalCongressParticipant: Codable, Hashable, Identifiable {
    var id: String
    var organizationID: String
    var congressID: String
    var authorID: String
}

struct RelationalCongressFunding: Codable, Hashable, Identifiable {
    var id: String
    var organizationID: String
    var congressID: String
    var applicationID: String
}

struct RelationalCongressTravel: Codable, Hashable, Identifiable {
    var id: String
    var organizationID: String
    var congressID: String
    var travelID: String
}

struct RelationalCongressAccommodation: Codable, Hashable, Identifiable {
    var id: String
    var organizationID: String
    var congressID: String
    var accommodationID: String
}

struct RelationalConferenceContributionCongress: Codable, Hashable, Identifiable {
    var id: String
    var contributionID: String
    var organizationID: String
    var congressID: String
}

struct RelationalConferenceContributionAuthor: Codable, Hashable, Identifiable {
    var id: String
    var contributionID: String
    var authorID: String
    var role: String
}

struct RelationalCalendarMeetingProject: Codable, Hashable, Identifiable {
    var id: String
    var meetingID: String
    var projectID: String
}

struct RelationalCalendarMeetingOrganization: Codable, Hashable, Identifiable {
    var id: String
    var meetingID: String
    var organizationID: String
}

struct RelationalCalendarMeetingApplication: Codable, Hashable, Identifiable {
    var id: String
    var meetingID: String
    var applicationID: String
}

struct RelationalCalendarMeetingPublication: Codable, Hashable, Identifiable {
    var id: String
    var meetingID: String
    var publicationID: String
}

struct RelationalSQLiteSnapshot: Codable, Hashable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var generatedAt: String
    var organizations: [RelationalSQLiteOrganizationRecord]
    var projects: [RelationalSQLiteProjectRecord]
    var applications: [RelationalSQLiteApplicationRecord]
    var authors: [RelationalSQLiteAuthorRecord]
    var publications: [RelationalSQLitePublicationRecord]
    var calendarTravel: [RelationalSQLiteCalendarTravelRecord]
    var calendarAccommodation: [RelationalSQLiteCalendarAccommodationRecord]
    var calendarMeetings: [RelationalSQLiteCalendarMeetingRecord]
    var conferenceContributions: [RelationalSQLiteConferenceContributionRecord]
    var relations: RelationalCoreSnapshot
}

struct RelationalSQLiteOrganizationRecord: Codable, Hashable, Identifiable {
    var id: String
    var nameSv: String
    var nameEn: String
}

struct RelationalSQLiteProjectRecord: Codable, Hashable, Identifiable {
    var id: String
    var nameSv: String
    var nameEn: String
}

struct RelationalSQLiteApplicationRecord: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var organizationID: String?
    var projectID: String?
    var status: String
}

struct RelationalSQLiteAuthorRecord: Codable, Hashable, Identifiable {
    var id: String
    var displayName: String
}

struct RelationalSQLitePublicationRecord: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var projectID: String?
    var journal: String
    var year: String
}

struct RelationalSQLiteCalendarTravelRecord: Codable, Hashable, Identifiable {
    var id: String
    var date: String
    var arrivalDate: String
    var departureTime: String
    var arrivalTime: String
    var mode: String
    var fromCity: String
    var fromCountry: String
    var toCity: String
    var toCountry: String
    var congressOrganizationID: String?
    var congressID: String?
}

struct RelationalSQLiteCalendarAccommodationRecord: Codable, Hashable, Identifiable {
    var id: String
    var hotelName: String
    var checkInDate: String
    var checkInTime: String
    var checkOutDate: String
    var checkOutTime: String
    var city: String
    var country: String
    var congressOrganizationID: String?
    var congressID: String?
}

struct RelationalSQLiteCalendarMeetingRecord: Codable, Hashable, Identifiable {
    var id: String
    var date: String
    var startTime: String
    var endTime: String
    var title: String
    var meetingType: String
}

struct RelationalSQLiteConferenceContributionRecord: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var status: String
    var from: String
    var to: String
    var congressOrganizationID: String?
    var congressID: String?
}

struct DataRelationshipMetrics: Codable, Hashable {
    var applicationCount: Int
    var projectCount: Int
    var organizationCount: Int
    var authorCount: Int
    var congressCount: Int
    var calendarMeetingCount: Int
    var calendarTravelCount: Int
    var calendarAccommodationCount: Int
    var conferenceContributionCount: Int
    var brokenCalendarProjectReferences: Int
    var brokenCongressReferences: Int
    var unresolvedCongressParticipantNames: Int
    var unresolvedConferenceContributorNames: Int
}

struct DataMigrationVerificationCheck: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var passed: Bool
    var details: String
}

struct DataMigrationVerificationReport: Codable, Hashable, Identifiable {
    var id: String
    var generatedAt: String
    var phase: String
    var passed: Bool
    var before: DataRelationshipMetrics
    var after: DataRelationshipMetrics
    var checks: [DataMigrationVerificationCheck]
}

protocol LocalizedNamedRecord: Codable, Hashable, Identifiable {
    var nameSv: String { get set }
    var nameEn: String { get set }
}

struct OrganizationRecord: Codable, Hashable, Identifiable, LocalizedNamedRecord {
    var id: String
    var nameSv: String
    var nameEn: String
    var addressLine: String
    var postalCode: String
    var city: String
    var country: String
    var category: String?
    var roles: [OrganizationRole]
    var note: String?
    var websiteURL: String
    var phoneNumber: String
    var organizationNumber: String
    var vatNumber: String
    var employerContacts: [OrganizationEmployerContact]
    var flag: String
    var membershipFrom: String
    var membershipTo: String
    var congresses: [OrganizationCongress]
    var salaryCalculator: ManagerSalaryCalculator?
    var projectTasks: [ProjectTaskItem]
    var isArchived: Bool
    /// F21: the organization's units (faculties, departments, clinics, …) in
    /// any number of levels. A unit without a parent sits directly under the
    /// organization. Empty for organizations without a tree.
    var units: [OrganizationUnit]
    /// F21: the English name used in publication addresses ("" = use `nameEn`).
    var addressNameEn: String
    /// F21: order of this organization's line in a publication address
    /// (for example the university 1, the region 2); nil = after the others.
    var addressOrder: Int?
    /// "Use as salary calculator for applications": this organization's salary
    /// calculator is the budget source in the application editor and follows
    /// your birth date. Stored only when ticked.
    var usesAsApplicationSalaryCalculator: Bool
    /// The earlier grant provider setting "Max OH (%)" (nil = no cap, 0 = no
    /// overhead). Still read from older data, where it becomes `overheadRule`
    /// ("Högst value %", 0 = "Ingen OH"); the one-time round 8 step then
    /// clears it. It is no longer written and no longer used in calculations.
    var legacyMaxOverheadPercent: Double?
    /// Grant provider setting "OH-regel": the fund manager's full OH (nil =
    /// the standard), at most a percent, or no OH. Stored only when set.
    var overheadRule: FunderOverheadRule?
    /// Grant provider exceptions "När [medelsförvaltare] förvaltar: …", found
    /// by the fund manager organization's id. Stored only when there are any.
    var overheadRuleExceptions: [FunderOverheadRuleException]?
    /// Fund manager setting "OH som tas ut (%)" (round 10; earlier
    /// "Förvaltarens fulla OH"). Copied into new records as the fund manager's
    /// OH. Stored only when set.
    var managerOverheadPercent: Double?
    /// Round 10, grant provider setting "Prioriterad förvaltare": the fund
    /// manager organization (by id) chosen for new records to this funder.
    /// nil = the default fund manager in Settings.
    var preferredFundManagerID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case nameSv
        case nameEn
        case addressLine
        case postalCode
        case city
        case country
        case category
        case roles
        case note
        case websiteURL
        case phoneNumber
        case organizationNumber
        case vatNumber
        case employerContacts
        case flag
        case membershipFrom
        case membershipTo
        case congresses
        case salaryCalculator
        case projectTasks
        case isArchived
        case units
        case addressNameEn
        case addressOrder
        case usesAsApplicationSalaryCalculator
        /// The earlier "Max OH (%)": read from older data, not written.
        case legacyMaxOverheadPercent = "maxOverheadPercent"
        case overheadRule
        case overheadRuleExceptions
        case managerOverheadPercent
        case preferredFundManagerID
    }

    init(
        id: String = UUID().uuidString,
        nameSv: String,
        nameEn: String,
        addressLine: String = "",
        postalCode: String = "",
        city: String = "",
        country: String = "",
        category: String? = nil,
        roles: [OrganizationRole] = [],
        note: String? = nil,
        websiteURL: String = "",
        phoneNumber: String = "",
        organizationNumber: String = "",
        vatNumber: String = "",
        employerContacts: [OrganizationEmployerContact] = [],
        flag: String = "",
        membershipFrom: String = "",
        membershipTo: String = "",
        congresses: [OrganizationCongress] = [],
        salaryCalculator: ManagerSalaryCalculator? = nil,
        projectTasks: [ProjectTaskItem] = [],
        isArchived: Bool = false,
        units: [OrganizationUnit] = [],
        addressNameEn: String = "",
        addressOrder: Int? = nil,
        usesAsApplicationSalaryCalculator: Bool = false,
        legacyMaxOverheadPercent: Double? = nil,
        overheadRule: FunderOverheadRule? = nil,
        overheadRuleExceptions: [FunderOverheadRuleException]? = nil,
        managerOverheadPercent: Double? = nil,
        preferredFundManagerID: String? = nil
    ) {
        self.id = id
        self.nameSv = nameSv
        self.nameEn = nameEn
        self.addressLine = addressLine
        self.postalCode = postalCode
        self.city = city
        self.country = country
        self.category = category
        self.roles = roles
        self.note = note
        self.websiteURL = websiteURL
        self.phoneNumber = phoneNumber
        self.organizationNumber = organizationNumber
        self.vatNumber = vatNumber
        self.employerContacts = employerContacts
        self.flag = flag
        self.membershipFrom = membershipFrom
        self.membershipTo = membershipTo
        self.congresses = congresses
        self.salaryCalculator = salaryCalculator
        self.projectTasks = projectTasks
        self.isArchived = isArchived
        self.units = units
        self.addressNameEn = addressNameEn
        self.addressOrder = addressOrder
        self.usesAsApplicationSalaryCalculator = usesAsApplicationSalaryCalculator
        self.legacyMaxOverheadPercent = legacyMaxOverheadPercent
        self.overheadRule = overheadRule
        self.overheadRuleExceptions = overheadRuleExceptions
        self.managerOverheadPercent = managerOverheadPercent
        self.preferredFundManagerID = preferredFundManagerID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedNameSv = try container.decodeIfPresent(String.self, forKey: .nameSv) ?? ""
        let decodedLegacyMaxOverheadPercent = try container.decodeIfPresent(Double.self, forKey: .legacyMaxOverheadPercent)
        let decodedExceptions = try container.decodeIfPresent([FunderOverheadRuleException].self, forKey: .overheadRuleExceptions)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? StableRecordID.legacy(prefix: "organization", name: decodedNameSv),
            nameSv: decodedNameSv,
            nameEn: try container.decodeIfPresent(String.self, forKey: .nameEn) ?? decodedNameSv,
            addressLine: try container.decodeIfPresent(String.self, forKey: .addressLine) ?? "",
            postalCode: try container.decodeIfPresent(String.self, forKey: .postalCode) ?? "",
            city: try container.decodeIfPresent(String.self, forKey: .city) ?? "",
            country: try container.decodeIfPresent(String.self, forKey: .country) ?? "",
            category: try container.decodeIfPresent(String.self, forKey: .category),
            roles: try container.decodeIfPresent([OrganizationRole].self, forKey: .roles) ?? [],
            note: try container.decodeIfPresent(String.self, forKey: .note),
            websiteURL: try container.decodeIfPresent(String.self, forKey: .websiteURL) ?? "",
            phoneNumber: try container.decodeIfPresent(String.self, forKey: .phoneNumber) ?? "",
            organizationNumber: try container.decodeIfPresent(String.self, forKey: .organizationNumber) ?? "",
            vatNumber: try container.decodeIfPresent(String.self, forKey: .vatNumber) ?? "",
            employerContacts: try container.decodeIfPresent([OrganizationEmployerContact].self, forKey: .employerContacts) ?? [],
            flag: try container.decodeIfPresent(String.self, forKey: .flag) ?? "",
            membershipFrom: try container.decodeIfPresent(String.self, forKey: .membershipFrom) ?? "",
            membershipTo: try container.decodeIfPresent(String.self, forKey: .membershipTo) ?? "",
            congresses: try container.decodeIfPresent([OrganizationCongress].self, forKey: .congresses) ?? [],
            salaryCalculator: try container.decodeIfPresent(ManagerSalaryCalculator.self, forKey: .salaryCalculator),
            projectTasks: try container.decodeIfPresent([ProjectTaskItem].self, forKey: .projectTasks) ?? [],
            isArchived: try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false,
            units: try container.decodeIfPresent([OrganizationUnit].self, forKey: .units) ?? [],
            addressNameEn: try container.decodeIfPresent(String.self, forKey: .addressNameEn) ?? "",
            addressOrder: try container.decodeIfPresent(Int.self, forKey: .addressOrder),
            usesAsApplicationSalaryCalculator: try container.decodeIfPresent(Bool.self, forKey: .usesAsApplicationSalaryCalculator) ?? false,
            legacyMaxOverheadPercent: decodedLegacyMaxOverheadPercent,
            // Older data with only "Max OH (%)" gets the same rule at once, so
            // nothing is lost even before the one-time step has run.
            overheadRule: try container.decodeIfPresent(FunderOverheadRule.self, forKey: .overheadRule)
                ?? FunderOverheadRule.migrated(fromLegacyMaxOverheadPercent: decodedLegacyMaxOverheadPercent),
            overheadRuleExceptions: (decodedExceptions?.isEmpty ?? true) ? nil : decodedExceptions,
            managerOverheadPercent: try container.decodeIfPresent(Double.self, forKey: .managerOverheadPercent),
            preferredFundManagerID: (try container.decodeIfPresent(String.self, forKey: .preferredFundManagerID))?.trimmedOrNil
        )
    }

    /// Same shape as the synthesized encoder; the salary calculator flag is
    /// written only when ticked so unchanged organizations keep their stored form.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nameSv, forKey: .nameSv)
        try container.encode(nameEn, forKey: .nameEn)
        try container.encode(addressLine, forKey: .addressLine)
        try container.encode(postalCode, forKey: .postalCode)
        try container.encode(city, forKey: .city)
        try container.encode(country, forKey: .country)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(roles, forKey: .roles)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(websiteURL, forKey: .websiteURL)
        try container.encode(phoneNumber, forKey: .phoneNumber)
        try container.encode(organizationNumber, forKey: .organizationNumber)
        try container.encode(vatNumber, forKey: .vatNumber)
        try container.encode(employerContacts, forKey: .employerContacts)
        try container.encode(flag, forKey: .flag)
        try container.encode(membershipFrom, forKey: .membershipFrom)
        try container.encode(membershipTo, forKey: .membershipTo)
        try container.encode(congresses, forKey: .congresses)
        try container.encodeIfPresent(salaryCalculator, forKey: .salaryCalculator)
        try container.encode(projectTasks, forKey: .projectTasks)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(units, forKey: .units)
        try container.encode(addressNameEn, forKey: .addressNameEn)
        try container.encodeIfPresent(addressOrder, forKey: .addressOrder)
        if usesAsApplicationSalaryCalculator {
            try container.encode(true, forKey: .usesAsApplicationSalaryCalculator)
        }
        // The earlier "Max OH (%)" (legacyMaxOverheadPercent) is not written.
        try container.encodeIfPresent(overheadRule, forKey: .overheadRule)
        if let overheadRuleExceptions, !overheadRuleExceptions.isEmpty {
            try container.encode(overheadRuleExceptions, forKey: .overheadRuleExceptions)
        }
        try container.encodeIfPresent(managerOverheadPercent, forKey: .managerOverheadPercent)
        try container.encodeIfPresent(preferredFundManagerID?.trimmedOrNil, forKey: .preferredFundManagerID)
    }

    init(legacy: LocalizedOption) {
        self.init(
            id: StableRecordID.legacy(prefix: "organization", name: legacy.nameSv),
            nameSv: legacy.nameSv,
            nameEn: legacy.nameEn,
            addressLine: legacy.addressLine,
            postalCode: legacy.postalCode,
            city: legacy.city,
            country: legacy.country,
            category: legacy.category,
            roles: legacy.roles,
            note: legacy.note,
            websiteURL: legacy.websiteURL,
            phoneNumber: legacy.phoneNumber,
            organizationNumber: legacy.organizationNumber,
            vatNumber: legacy.vatNumber,
            employerContacts: legacy.employerContacts,
            flag: legacy.flag,
            membershipFrom: legacy.membershipFrom,
            membershipTo: legacy.membershipTo,
            congresses: legacy.congresses,
            salaryCalculator: legacy.salaryCalculator,
            projectTasks: legacy.projectTasks,
            isArchived: legacy.isArchived
        )
    }
}

struct ProjectRecord: Codable, Hashable, Identifiable, LocalizedNamedRecord {
    var id: String
    var nameSv: String
    var nameEn: String
    var fullNameSv: String
    var fullNameEn: String
    var collaboratorNames: [String]
    /// Id links to the researchers in `collaboratorNames`; the names stay as display text.
    var collaboratorAuthorIDs: [String]
    var note: String?
    var websiteURL: String
    var projectStatus: ProjectLifecycleStatus
    var hasDataCollection: Bool
    var ethicsBaseApplication: ProjectEthicsApplication
    var ethicsAmendments: [ProjectEthicsApplication]
    var ethicsLink: String?
    var clinicalTrialRegistrations: [ProjectClinicalTrialRegistration]
    var principalOrganizations: [ProjectPrincipalOrganization]
    var dataCollections: [ProjectDataCollection]
    var projectTasks: [ProjectTaskItem]
    var suppressedSeedProjectTaskComments: [String]
    var isArchived: Bool
    var isEditingLocked: Bool
    /// Round 16: events (granted funds, data collection start, ethics dates)
    /// for which "Ska projektet ändras till Pågående?" was answered "Inte
    /// nu". Optional so older files load unchanged; nil = none.
    var dismissedOngoingPromptKeys: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case nameSv
        case nameEn
        case fullNameSv
        case fullNameEn
        case collaboratorNames
        case collaboratorAuthorIDs
        case note
        case websiteURL
        case projectStatus
        case hasDataCollection
        case ethicsBaseApplication
        case ethicsAmendments
        case ethicsLink
        case clinicalTrialRegistrations
        case principalOrganizations
        case dataCollections
        case projectTasks
        case suppressedSeedProjectTaskComments
        case isArchived
        case isEditingLocked
        case dismissedOngoingPromptKeys
    }

    init(
        id: String = UUID().uuidString,
        nameSv: String,
        nameEn: String,
        fullNameSv: String = "",
        fullNameEn: String = "",
        collaboratorNames: [String] = [],
        collaboratorAuthorIDs: [String] = [],
        note: String? = nil,
        websiteURL: String = "",
        projectStatus: ProjectLifecycleStatus = .ongoing,
        hasDataCollection: Bool = false,
        ethicsBaseApplication: ProjectEthicsApplication = ProjectEthicsApplication(),
        ethicsAmendments: [ProjectEthicsApplication] = [],
        ethicsLink: String? = nil,
        clinicalTrialRegistrations: [ProjectClinicalTrialRegistration] = [],
        principalOrganizations: [ProjectPrincipalOrganization] = [],
        dataCollections: [ProjectDataCollection] = [],
        projectTasks: [ProjectTaskItem] = [],
        suppressedSeedProjectTaskComments: [String] = [],
        isArchived: Bool = false,
        isEditingLocked: Bool = false,
        dismissedOngoingPromptKeys: [String]? = nil
    ) {
        self.id = id
        self.nameSv = nameSv
        self.nameEn = nameEn
        self.fullNameSv = fullNameSv
        self.fullNameEn = fullNameEn
        self.collaboratorNames = collaboratorNames
        self.collaboratorAuthorIDs = collaboratorAuthorIDs
        self.note = note
        self.websiteURL = websiteURL
        self.projectStatus = isArchived ? .completed : projectStatus
        self.hasDataCollection = hasDataCollection
        self.ethicsBaseApplication = ethicsBaseApplication
        self.ethicsAmendments = ethicsAmendments
        self.ethicsLink = ethicsLink
        self.clinicalTrialRegistrations = clinicalTrialRegistrations
        self.principalOrganizations = principalOrganizations
        self.dataCollections = dataCollections
        self.projectTasks = projectTasks
        self.suppressedSeedProjectTaskComments = suppressedSeedProjectTaskComments
        self.isArchived = self.projectStatus == .completed
        self.isEditingLocked = isEditingLocked
        self.dismissedOngoingPromptKeys = dismissedOngoingPromptKeys?.isEmpty == true ? nil : dismissedOngoingPromptKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedNameSv = try container.decodeIfPresent(String.self, forKey: .nameSv) ?? ""
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? StableRecordID.legacy(prefix: "project", name: decodedNameSv),
            nameSv: decodedNameSv,
            nameEn: try container.decodeIfPresent(String.self, forKey: .nameEn) ?? decodedNameSv,
            fullNameSv: try container.decodeIfPresent(String.self, forKey: .fullNameSv) ?? "",
            fullNameEn: try container.decodeIfPresent(String.self, forKey: .fullNameEn) ?? "",
            collaboratorNames: try container.decodeIfPresent([String].self, forKey: .collaboratorNames) ?? [],
            collaboratorAuthorIDs: try container.decodeIfPresent([String].self, forKey: .collaboratorAuthorIDs) ?? [],
            note: try container.decodeIfPresent(String.self, forKey: .note),
            websiteURL: try container.decodeIfPresent(String.self, forKey: .websiteURL) ?? "",
            projectStatus: try container.decodeIfPresent(ProjectLifecycleStatus.self, forKey: .projectStatus) ?? .ongoing,
            hasDataCollection: try container.decodeIfPresent(Bool.self, forKey: .hasDataCollection) ?? false,
            ethicsBaseApplication: try container.decodeIfPresent(ProjectEthicsApplication.self, forKey: .ethicsBaseApplication) ?? ProjectEthicsApplication(),
            ethicsAmendments: try container.decodeIfPresent([ProjectEthicsApplication].self, forKey: .ethicsAmendments) ?? [],
            ethicsLink: try container.decodeIfPresent(String.self, forKey: .ethicsLink),
            clinicalTrialRegistrations: try container.decodeIfPresent([ProjectClinicalTrialRegistration].self, forKey: .clinicalTrialRegistrations) ?? [],
            principalOrganizations: try container.decodeIfPresent([ProjectPrincipalOrganization].self, forKey: .principalOrganizations) ?? [],
            dataCollections: try container.decodeIfPresent([ProjectDataCollection].self, forKey: .dataCollections) ?? [],
            projectTasks: try container.decodeIfPresent([ProjectTaskItem].self, forKey: .projectTasks) ?? [],
            suppressedSeedProjectTaskComments: try container.decodeIfPresent([String].self, forKey: .suppressedSeedProjectTaskComments) ?? [],
            isArchived: try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false,
            isEditingLocked: try container.decodeIfPresent(Bool.self, forKey: .isEditingLocked) ?? false,
            dismissedOngoingPromptKeys: try container.decodeIfPresent([String].self, forKey: .dismissedOngoingPromptKeys)
        )
    }

    init(legacy: LocalizedOption) {
        self.init(
            id: StableRecordID.legacy(prefix: "project", name: legacy.nameSv),
            nameSv: legacy.nameSv,
            nameEn: legacy.nameEn,
            collaboratorNames: legacy.collaboratorNames,
            note: legacy.note,
            websiteURL: legacy.websiteURL,
            projectStatus: legacy.projectStatus,
            hasDataCollection: legacy.hasDataCollection,
            ethicsBaseApplication: legacy.ethicsBaseApplication,
            ethicsAmendments: legacy.ethicsAmendments,
            ethicsLink: legacy.ethicsLink,
            clinicalTrialRegistrations: legacy.clinicalTrialRegistrations,
            principalOrganizations: legacy.principalOrganizations,
            dataCollections: legacy.dataCollections,
            projectTasks: legacy.projectTasks,
            suppressedSeedProjectTaskComments: legacy.suppressedSeedProjectTaskComments,
            isArchived: legacy.isArchived
        )
    }
}

// Legacy migration-only record. Keep decode support, but do not use this model for new features.
struct LocalizedOption: Codable, Hashable, Identifiable {
    var nameSv: String
    var nameEn: String
    var addressLine: String
    var postalCode: String
    var city: String
    var country: String
    var category: String?
    var collaboratorNames: [String]
    var roles: [OrganizationRole]
    var note: String?
    var websiteURL: String
    var phoneNumber: String
    var organizationNumber: String
    var vatNumber: String
    var employerContacts: [OrganizationEmployerContact]
    var flag: String
    var membershipFrom: String
    var membershipTo: String
    var congresses: [OrganizationCongress]
    var salaryCalculator: ManagerSalaryCalculator?
    var projectStatus: ProjectLifecycleStatus
    var hasDataCollection: Bool
    var ethicsBaseApplication: ProjectEthicsApplication
    var ethicsAmendments: [ProjectEthicsApplication]
    var ethicsLink: String?
    var clinicalTrialRegistrations: [ProjectClinicalTrialRegistration]
    var principalOrganizations: [ProjectPrincipalOrganization]
    var dataCollections: [ProjectDataCollection]
    var projectTasks: [ProjectTaskItem]
    var suppressedSeedProjectTaskComments: [String]
    var isArchived: Bool

    var id: String { nameSv }

    init(
        nameSv: String,
        nameEn: String,
        addressLine: String = "",
        postalCode: String = "",
        city: String = "",
        country: String = "",
        category: String? = nil,
        collaboratorNames: [String] = [],
        roles: [OrganizationRole] = [],
        note: String? = nil,
        websiteURL: String = "",
        phoneNumber: String = "",
        organizationNumber: String = "",
        vatNumber: String = "",
        employerContacts: [OrganizationEmployerContact] = [],
        flag: String = "",
        membershipFrom: String = "",
        membershipTo: String = "",
        congresses: [OrganizationCongress] = [],
        salaryCalculator: ManagerSalaryCalculator? = nil,
        projectStatus: ProjectLifecycleStatus = .ongoing,
        hasDataCollection: Bool = false,
        ethicsBaseApplication: ProjectEthicsApplication = ProjectEthicsApplication(),
        ethicsAmendments: [ProjectEthicsApplication] = [],
        ethicsLink: String? = nil,
        clinicalTrialRegistrations: [ProjectClinicalTrialRegistration] = [],
        principalOrganizations: [ProjectPrincipalOrganization] = [],
        dataCollections: [ProjectDataCollection] = [],
        projectTasks: [ProjectTaskItem] = [],
        suppressedSeedProjectTaskComments: [String] = [],
        isArchived: Bool = false
    ) {
        self.nameSv = nameSv
        self.nameEn = nameEn
        self.addressLine = addressLine
        self.postalCode = postalCode
        self.city = city
        self.country = country
        self.category = category
        self.collaboratorNames = collaboratorNames
        self.roles = roles
        self.note = note
        self.websiteURL = websiteURL
        self.phoneNumber = phoneNumber
        self.organizationNumber = organizationNumber
        self.vatNumber = vatNumber
        self.employerContacts = employerContacts
        self.flag = flag
        self.membershipFrom = membershipFrom
        self.membershipTo = membershipTo
        self.congresses = congresses
        self.salaryCalculator = salaryCalculator
        self.projectStatus = isArchived ? .completed : projectStatus
        self.hasDataCollection = hasDataCollection
        self.ethicsBaseApplication = ethicsBaseApplication
        self.ethicsAmendments = ethicsAmendments
        self.ethicsLink = ethicsLink
        self.clinicalTrialRegistrations = clinicalTrialRegistrations
        self.principalOrganizations = principalOrganizations
        self.dataCollections = dataCollections
        self.projectTasks = projectTasks
        self.suppressedSeedProjectTaskComments = suppressedSeedProjectTaskComments
        self.isArchived = self.projectStatus == .completed
    }

    enum CodingKeys: String, CodingKey {
        case nameSv
        case nameEn
        case addressLine
        case postalCode
        case city
        case country
        case category
        case collaboratorNames
        case roles
        case note
        case websiteURL
        case phoneNumber
        case organizationNumber
        case vatNumber
        case employerContacts
        case flag
        case membershipFrom
        case membershipTo
        case congresses
        case salaryCalculator
        case projectStatus
        case hasDataCollection
        case ethicsBaseApplication
        case ethicsAmendments
        case ethicsLink
        case clinicalTrialRegistrations
        case principalOrganizations
        case dataCollections
        case dataCollection
        case projectTasks
        case suppressedSeedProjectTaskComments
        case isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nameSv = try container.decode(String.self, forKey: .nameSv)
        self.nameEn = try container.decodeIfPresent(String.self, forKey: .nameEn) ?? self.nameSv
        self.addressLine = try container.decodeIfPresent(String.self, forKey: .addressLine) ?? ""
        self.postalCode = try container.decodeIfPresent(String.self, forKey: .postalCode) ?? ""
        self.city = try container.decodeIfPresent(String.self, forKey: .city) ?? ""
        self.country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        self.category = try container.decodeIfPresent(String.self, forKey: .category)
        self.collaboratorNames = try container.decodeIfPresent([String].self, forKey: .collaboratorNames) ?? []
        self.roles = try container.decodeIfPresent([OrganizationRole].self, forKey: .roles) ?? []
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
        self.websiteURL = try container.decodeIfPresent(String.self, forKey: .websiteURL) ?? ""
        self.phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber) ?? ""
        self.organizationNumber = try container.decodeIfPresent(String.self, forKey: .organizationNumber) ?? ""
        self.vatNumber = try container.decodeIfPresent(String.self, forKey: .vatNumber) ?? ""
        self.employerContacts = try container.decodeIfPresent([OrganizationEmployerContact].self, forKey: .employerContacts) ?? []
        self.flag = try container.decodeIfPresent(String.self, forKey: .flag) ?? ""
        self.membershipFrom = try container.decodeIfPresent(String.self, forKey: .membershipFrom) ?? ""
        self.membershipTo = try container.decodeIfPresent(String.self, forKey: .membershipTo) ?? ""
        self.congresses = try container.decodeIfPresent([OrganizationCongress].self, forKey: .congresses) ?? []
        self.salaryCalculator = try container.decodeIfPresent(ManagerSalaryCalculator.self, forKey: .salaryCalculator)
        let archived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        self.projectStatus = try container.decodeIfPresent(ProjectLifecycleStatus.self, forKey: .projectStatus) ?? (archived ? .completed : .ongoing)
        self.hasDataCollection = try container.decodeIfPresent(Bool.self, forKey: .hasDataCollection) ?? false
        self.ethicsBaseApplication = try container.decodeIfPresent(ProjectEthicsApplication.self, forKey: .ethicsBaseApplication) ?? ProjectEthicsApplication()
        self.ethicsAmendments = try container.decodeIfPresent([ProjectEthicsApplication].self, forKey: .ethicsAmendments) ?? []
        self.ethicsLink = try container.decodeIfPresent(String.self, forKey: .ethicsLink)
        self.clinicalTrialRegistrations = try container.decodeIfPresent([ProjectClinicalTrialRegistration].self, forKey: .clinicalTrialRegistrations) ?? []
        self.principalOrganizations = try container.decodeIfPresent([ProjectPrincipalOrganization].self, forKey: .principalOrganizations) ?? []
        self.dataCollections = try container.decodeIfPresent([ProjectDataCollection].self, forKey: .dataCollections)
            ?? (try container.decodeIfPresent(ProjectDataCollection.self, forKey: .dataCollection).map { [$0] } ?? [])
        self.projectTasks = try container.decodeIfPresent([ProjectTaskItem].self, forKey: .projectTasks) ?? []
        self.suppressedSeedProjectTaskComments = try container.decodeIfPresent([String].self, forKey: .suppressedSeedProjectTaskComments) ?? []
        self.isArchived = self.projectStatus == .completed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nameSv, forKey: .nameSv)
        try container.encode(nameEn, forKey: .nameEn)
        try container.encode(addressLine, forKey: .addressLine)
        try container.encode(postalCode, forKey: .postalCode)
        try container.encode(city, forKey: .city)
        try container.encode(country, forKey: .country)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(collaboratorNames, forKey: .collaboratorNames)
        try container.encode(roles, forKey: .roles)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(websiteURL, forKey: .websiteURL)
        try container.encode(phoneNumber, forKey: .phoneNumber)
        try container.encode(organizationNumber, forKey: .organizationNumber)
        try container.encode(vatNumber, forKey: .vatNumber)
        try container.encode(employerContacts, forKey: .employerContacts)
        try container.encode(flag, forKey: .flag)
        try container.encode(membershipFrom, forKey: .membershipFrom)
        try container.encode(membershipTo, forKey: .membershipTo)
        try container.encode(congresses, forKey: .congresses)
        try container.encodeIfPresent(salaryCalculator, forKey: .salaryCalculator)
        try container.encode(projectStatus, forKey: .projectStatus)
        try container.encode(hasDataCollection, forKey: .hasDataCollection)
        try container.encode(ethicsBaseApplication, forKey: .ethicsBaseApplication)
        try container.encode(ethicsAmendments, forKey: .ethicsAmendments)
        try container.encodeIfPresent(ethicsLink, forKey: .ethicsLink)
        try container.encode(clinicalTrialRegistrations, forKey: .clinicalTrialRegistrations)
        try container.encode(principalOrganizations, forKey: .principalOrganizations)
        try container.encode(dataCollections, forKey: .dataCollections)
        try container.encode(projectTasks, forKey: .projectTasks)
        try container.encode(suppressedSeedProjectTaskComments, forKey: .suppressedSeedProjectTaskComments)
        try container.encode(isArchived, forKey: .isArchived)
    }
}

struct OrganizationEmployerContact: Codable, Hashable, Identifiable {
    var id: String
    var role: String
    var firstName: String
    var lastName: String
    var phone: String
    var email: String

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case firstName
        case lastName
        case name
        case phone
        case email
    }

    init(
        id: String = UUID().uuidString,
        role: String = "",
        firstName: String = "",
        lastName: String = "",
        phone: String = "",
        email: String = "",
        name: String? = nil
    ) {
        self.id = id
        self.role = role
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parts = name.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            self.firstName = parts.first ?? ""
            self.lastName = parts.dropFirst().joined(separator: " ")
        } else {
            self.firstName = firstName
            self.lastName = lastName
        }
        self.phone = phone
        self.email = email
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""

        let decodedFirstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        let decodedLastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        if decodedFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           decodedLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let legacyName = try container.decodeIfPresent(String.self, forKey: .name)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyName.isEmpty {
            let parts = legacyName.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            firstName = parts.first ?? ""
            lastName = parts.dropFirst().joined(separator: " ")
        } else {
            firstName = decodedFirstName
            lastName = decodedLastName
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try container.encode(fullName, forKey: .name)
        try container.encode(phone, forKey: .phone)
        try container.encode(email, forKey: .email)
    }

    var fullName: String {
        [firstName.trimmingCharacters(in: .whitespacesAndNewlines), lastName.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var isEmpty: Bool {
        role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ManagerOption: Codable, Hashable, Identifiable {
    var id: String
    var nameSv: String
    var nameEn: String
    var reason: String?
    var salaryCalculator: ManagerSalaryCalculator?

    enum CodingKeys: String, CodingKey {
        case id
        case nameSv
        case nameEn
        case reason
        case salaryCalculator
    }

    init(id: String = UUID().uuidString, nameSv: String, nameEn: String, reason: String?, salaryCalculator: ManagerSalaryCalculator? = nil) {
        self.id = id
        self.nameSv = nameSv
        self.nameEn = nameEn
        self.reason = reason
        self.salaryCalculator = salaryCalculator
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedNameSv = try container.decodeIfPresent(String.self, forKey: .nameSv) ?? ""
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? StableRecordID.legacy(prefix: "manager", name: decodedNameSv),
            nameSv: decodedNameSv,
            nameEn: try container.decodeIfPresent(String.self, forKey: .nameEn) ?? decodedNameSv,
            reason: try container.decodeIfPresent(String.self, forKey: .reason),
            salaryCalculator: try container.decodeIfPresent(ManagerSalaryCalculator.self, forKey: .salaryCalculator)
        )
    }
}

struct SalaryCalculatorPeriod: Codable, Hashable, Identifiable {
    var id: String
    var value: String
    var from: String
    var to: String

    init(id: String = UUID().uuidString, value: String = "", from: String = "", to: String = "") {
        self.id = id
        self.value = value
        self.from = from
        self.to = to
    }
}

struct ManagerSalaryCalculator: Codable, Hashable {
    var birthDate: String
    var monthlySalaryPeriods: [SalaryCalculatorPeriod]
    var employerFeePeriods: [SalaryCalculatorPeriod]
    var regionalCostPeriods: [SalaryCalculatorPeriod]
    var itInfrastructureFeePeriods: [SalaryCalculatorPeriod]
    var listedPatientCountPeriods: [SalaryCalculatorPeriod]
    var overheadPeriods: [SalaryCalculatorPeriod]
    var annualIncreaseAfterCurrentYearPercent: String
    var allocationPercent: String
    var allocationMonths: String
    /// The old checkbox that left overhead out of this calculator. It is
    /// still read from older data so the one-time round 8 migration can move
    /// it to the funder setting "OH-regel" (`OrganizationRecord.overheadRule`),
    /// but it no longer affects any calculation and is not written.
    var legacyExcludesOverhead: Bool
    /// Vacation days per year below the first age limit (default 25).
    var vacationDaysBase: String
    /// First age limit (default 40) and the vacation days from that age (31).
    var vacationFirstAgeLimit: String
    var vacationDaysFromFirstAge: String
    /// Second age limit (default 50) and the vacation days from that age (32).
    var vacationSecondAgeLimit: String
    var vacationDaysFromSecondAge: String
    /// Vacation supplement per vacation day, in percent of the monthly
    /// salary (default 0,605 %, the same as 0.00605).
    var vacationSupplementPercentPerDay: String

    static let defaultVacationDaysBase = "25"
    static let defaultVacationFirstAgeLimit = "40"
    static let defaultVacationDaysFromFirstAge = "31"
    static let defaultVacationSecondAgeLimit = "50"
    static let defaultVacationDaysFromSecondAge = "32"
    static let defaultVacationSupplementPercentPerDay = "0,605"

    enum CodingKeys: String, CodingKey {
        case birthDate
        case monthlySalaryPeriods
        case employerFeePeriods
        case regionalCostPeriods
        case itInfrastructureFeePeriods
        case listedPatientCountPeriods
        case overheadPeriods
        case annualIncreaseAfterCurrentYearPercent
        case allocationPercent
        case allocationMonths
        /// Stored key of the old checkbox; kept so older data still decodes.
        case legacyExcludesOverhead = "forssWithoutOverhead"
        case vacationDaysBase
        case vacationFirstAgeLimit
        case vacationDaysFromFirstAge
        case vacationSecondAgeLimit
        case vacationDaysFromSecondAge
        case vacationSupplementPercentPerDay
    }

    init(
        birthDate: String,
        monthlySalaryPeriods: [SalaryCalculatorPeriod],
        employerFeePeriods: [SalaryCalculatorPeriod],
        regionalCostPeriods: [SalaryCalculatorPeriod],
        itInfrastructureFeePeriods: [SalaryCalculatorPeriod],
        listedPatientCountPeriods: [SalaryCalculatorPeriod],
        overheadPeriods: [SalaryCalculatorPeriod],
        annualIncreaseAfterCurrentYearPercent: String,
        allocationPercent: String,
        allocationMonths: String,
        legacyExcludesOverhead: Bool = false,
        vacationDaysBase: String = ManagerSalaryCalculator.defaultVacationDaysBase,
        vacationFirstAgeLimit: String = ManagerSalaryCalculator.defaultVacationFirstAgeLimit,
        vacationDaysFromFirstAge: String = ManagerSalaryCalculator.defaultVacationDaysFromFirstAge,
        vacationSecondAgeLimit: String = ManagerSalaryCalculator.defaultVacationSecondAgeLimit,
        vacationDaysFromSecondAge: String = ManagerSalaryCalculator.defaultVacationDaysFromSecondAge,
        vacationSupplementPercentPerDay: String = ManagerSalaryCalculator.defaultVacationSupplementPercentPerDay
    ) {
        self.vacationDaysBase = vacationDaysBase
        self.vacationFirstAgeLimit = vacationFirstAgeLimit
        self.vacationDaysFromFirstAge = vacationDaysFromFirstAge
        self.vacationSecondAgeLimit = vacationSecondAgeLimit
        self.vacationDaysFromSecondAge = vacationDaysFromSecondAge
        self.vacationSupplementPercentPerDay = vacationSupplementPercentPerDay
        self.birthDate = birthDate
        self.monthlySalaryPeriods = monthlySalaryPeriods
        self.employerFeePeriods = employerFeePeriods
        self.regionalCostPeriods = regionalCostPeriods
        self.itInfrastructureFeePeriods = itInfrastructureFeePeriods
        self.listedPatientCountPeriods = listedPatientCountPeriods
        self.overheadPeriods = overheadPeriods
        self.annualIncreaseAfterCurrentYearPercent = annualIncreaseAfterCurrentYearPercent
        self.allocationPercent = allocationPercent
        self.allocationMonths = allocationMonths
        self.legacyExcludesOverhead = legacyExcludesOverhead
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            // A missing legacy value is unknown. Template defaults are applied
            // explicitly when a calculator is created and must not inject one
            // person's birth date while decoding another account's data.
            birthDate: try container.decodeIfPresent(String.self, forKey: .birthDate) ?? "",
            monthlySalaryPeriods: try container.decodeIfPresent([SalaryCalculatorPeriod].self, forKey: .monthlySalaryPeriods) ?? [],
            employerFeePeriods: try container.decodeIfPresent([SalaryCalculatorPeriod].self, forKey: .employerFeePeriods) ?? [],
            regionalCostPeriods: try container.decodeIfPresent([SalaryCalculatorPeriod].self, forKey: .regionalCostPeriods) ?? [],
            itInfrastructureFeePeriods: try container.decodeIfPresent([SalaryCalculatorPeriod].self, forKey: .itInfrastructureFeePeriods) ?? [],
            listedPatientCountPeriods: try container.decodeIfPresent([SalaryCalculatorPeriod].self, forKey: .listedPatientCountPeriods) ?? [],
            overheadPeriods: try container.decodeIfPresent([SalaryCalculatorPeriod].self, forKey: .overheadPeriods) ?? [],
            annualIncreaseAfterCurrentYearPercent: try container.decodeIfPresent(String.self, forKey: .annualIncreaseAfterCurrentYearPercent) ?? "3",
            allocationPercent: try container.decodeIfPresent(String.self, forKey: .allocationPercent) ?? "",
            allocationMonths: try container.decodeIfPresent(String.self, forKey: .allocationMonths) ?? "",
            legacyExcludesOverhead: try container.decodeIfPresent(Bool.self, forKey: .legacyExcludesOverhead) ?? false,
            vacationDaysBase: try container.decodeIfPresent(String.self, forKey: .vacationDaysBase) ?? Self.defaultVacationDaysBase,
            vacationFirstAgeLimit: try container.decodeIfPresent(String.self, forKey: .vacationFirstAgeLimit) ?? Self.defaultVacationFirstAgeLimit,
            vacationDaysFromFirstAge: try container.decodeIfPresent(String.self, forKey: .vacationDaysFromFirstAge) ?? Self.defaultVacationDaysFromFirstAge,
            vacationSecondAgeLimit: try container.decodeIfPresent(String.self, forKey: .vacationSecondAgeLimit) ?? Self.defaultVacationSecondAgeLimit,
            vacationDaysFromSecondAge: try container.decodeIfPresent(String.self, forKey: .vacationDaysFromSecondAge) ?? Self.defaultVacationDaysFromSecondAge,
            vacationSupplementPercentPerDay: try container.decodeIfPresent(String.self, forKey: .vacationSupplementPercentPerDay) ?? Self.defaultVacationSupplementPercentPerDay
        )
    }

    /// Same shape as the synthesized encoder; the vacation values are written
    /// only when they differ from the defaults, so unchanged calculators keep
    /// their stored form. The old overhead checkbox is read but not written.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(birthDate, forKey: .birthDate)
        try container.encode(monthlySalaryPeriods, forKey: .monthlySalaryPeriods)
        try container.encode(employerFeePeriods, forKey: .employerFeePeriods)
        try container.encode(regionalCostPeriods, forKey: .regionalCostPeriods)
        try container.encode(itInfrastructureFeePeriods, forKey: .itInfrastructureFeePeriods)
        try container.encode(listedPatientCountPeriods, forKey: .listedPatientCountPeriods)
        try container.encode(overheadPeriods, forKey: .overheadPeriods)
        try container.encode(annualIncreaseAfterCurrentYearPercent, forKey: .annualIncreaseAfterCurrentYearPercent)
        try container.encode(allocationPercent, forKey: .allocationPercent)
        try container.encode(allocationMonths, forKey: .allocationMonths)
        if vacationDaysBase != Self.defaultVacationDaysBase {
            try container.encode(vacationDaysBase, forKey: .vacationDaysBase)
        }
        if vacationFirstAgeLimit != Self.defaultVacationFirstAgeLimit {
            try container.encode(vacationFirstAgeLimit, forKey: .vacationFirstAgeLimit)
        }
        if vacationDaysFromFirstAge != Self.defaultVacationDaysFromFirstAge {
            try container.encode(vacationDaysFromFirstAge, forKey: .vacationDaysFromFirstAge)
        }
        if vacationSecondAgeLimit != Self.defaultVacationSecondAgeLimit {
            try container.encode(vacationSecondAgeLimit, forKey: .vacationSecondAgeLimit)
        }
        if vacationDaysFromSecondAge != Self.defaultVacationDaysFromSecondAge {
            try container.encode(vacationDaysFromSecondAge, forKey: .vacationDaysFromSecondAge)
        }
        if vacationSupplementPercentPerDay != Self.defaultVacationSupplementPercentPerDay {
            try container.encode(vacationSupplementPercentPerDay, forKey: .vacationSupplementPercentPerDay)
        }
    }

    /// Vacation days for a person of the given age at the end of the year.
    /// Without a known age the days below the first age limit are used.
    func vacationDays(atAge age: Int?) -> Int {
        let base = Self.wholeNumber(vacationDaysBase) ?? 25
        guard let age else { return base }
        let firstLimit = Self.wholeNumber(vacationFirstAgeLimit) ?? 40
        let firstDays = Self.wholeNumber(vacationDaysFromFirstAge) ?? 31
        let secondLimit = Self.wholeNumber(vacationSecondAgeLimit) ?? 50
        let secondDays = Self.wholeNumber(vacationDaysFromSecondAge) ?? 32
        if age >= secondLimit { return secondDays }
        if age >= firstLimit { return firstDays }
        return base
    }

    /// The vacation supplement per vacation day as a fraction of the monthly
    /// salary (0,605 % → 0.00605).
    var vacationSupplementRatePerDay: Double {
        (GrantParsing.numericValue(from: vacationSupplementPercentPerDay) ?? 0.605) / 100
    }

    private static func wholeNumber(_ text: String) -> Int? {
        GrantParsing.numericValue(from: text).map { Int($0.rounded()) }
    }

    /// Template ("Standardmall") for the calculator of the organization used
    /// for applications. It carries no cost rates of its own: the rates and
    /// the personal values (birth date, salary history) always come from the
    /// calculator stored on the organization. Only the yearly increase after
    /// the current year has a starting value.
    static let defaultSalaryCalculatorTemplate = ManagerSalaryCalculator(
        birthDate: "",
        monthlySalaryPeriods: [],
        employerFeePeriods: [],
        regionalCostPeriods: [],
        itInfrastructureFeePeriods: [],
        listedPatientCountPeriods: [],
        overheadPeriods: [],
        annualIncreaseAfterCurrentYearPercent: "3",
        allocationPercent: "",
        allocationMonths: ""
    )

    static let empty = ManagerSalaryCalculator(
        birthDate: "",
        monthlySalaryPeriods: [],
        employerFeePeriods: [],
        regionalCostPeriods: [],
        itInfrastructureFeePeriods: [],
        listedPatientCountPeriods: [],
        overheadPeriods: [],
        annualIncreaseAfterCurrentYearPercent: "3",
        allocationPercent: "",
        allocationMonths: ""
    )
}

struct DashboardSummary {
    let applicationCount: Int
    let grantedCount: Int
    let rejectedCount: Int
    let pendingCount: Int
    let totalRequested: Double
    let totalAwarded: Double
    /// Round 17: withdrawn applications, never counted as declined.
    var withdrawnCount: Int = 0
}

struct StoreNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let tone: NoticeTone
}

struct PersistenceStatus: Equatable {
    var isSaving = false
    var lastSavedAt: Date?
    var lastBackupAt: Date?
}

enum NoticeTone: Equatable {
    case success
    case error
    case info
}

enum AppFontFamily: String, Codable, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }
}

enum AppFontWeightSetting: String, Codable, CaseIterable, Identifiable {
    case regular
    case semibold
    case bold

    var id: String { rawValue }
}

enum AppTypographyRole: String, CaseIterable, Identifiable {
    case pageTitle
    case sectionTitle
    case panelTitle
    case tableHeader
    case fieldLabel
    case body
    case secondary
    case statTitle
    case statValue

    var id: String { rawValue }
}

enum AppSemanticTone: String, CaseIterable, Identifiable {
    case negative
    case inProgress
    case positive
    case neutral

    var id: String { rawValue }
}

struct AppTextStyleSetting: Codable, Hashable {
    var family: AppFontFamily
    var size: Double
    var weight: AppFontWeightSetting

    static func make(_ family: AppFontFamily, _ size: Double, _ weight: AppFontWeightSetting) -> AppTextStyleSetting {
        AppTextStyleSetting(family: family, size: size, weight: weight)
    }
}

struct AppTypographySettings: Codable, Hashable {
    var pageTitle: AppTextStyleSetting
    var sectionTitle: AppTextStyleSetting
    var panelTitle: AppTextStyleSetting
    var tableHeader: AppTextStyleSetting
    var fieldLabel: AppTextStyleSetting
    var body: AppTextStyleSetting
    var secondary: AppTextStyleSetting
    var statTitle: AppTextStyleSetting
    var statValue: AppTextStyleSetting

    static let `default` = AppTypographySettings(
        pageTitle: .make(.system, 24, .bold),
        sectionTitle: .make(.system, 20, .bold),
        panelTitle: .make(.system, 16, .semibold),
        tableHeader: .make(.system, 13, .semibold),
        fieldLabel: .make(.system, 12, .semibold),
        body: .make(.system, 13, .regular),
        secondary: .make(.system, 12, .regular),
        statTitle: .make(.system, 16, .semibold),
        statValue: .make(.system, 24, .bold)
    )

    static var runtimeDefault: AppTypographySettings {
        if AppRuntime.usesRenewedChrome {
            return AppTypographySettings(
                pageTitle: .make(.system, 24, .bold),
                sectionTitle: .make(.system, 16, .semibold),
                panelTitle: .make(.system, 14, .semibold),
                tableHeader: .make(.system, 12, .semibold),
                fieldLabel: .make(.system, 12, .semibold),
                body: .make(.system, 13, .regular),
                secondary: .make(.system, 12, .regular),
                statTitle: .make(.system, 14, .semibold),
                statValue: .make(.system, 22, .semibold)
            )
        }
        return .default
    }
}

struct AppSemanticToneSetting: Codable, Hashable {
    var solidHex: String
    var shadeHex: String

    static func make(_ solidHex: String, _ shadeHex: String) -> AppSemanticToneSetting {
        AppSemanticToneSetting(solidHex: solidHex, shadeHex: shadeHex)
    }
}

struct AppSemanticColorSettings: Codable, Hashable {
    var negative: AppSemanticToneSetting
    var inProgress: AppSemanticToneSetting
    var positive: AppSemanticToneSetting
    var neutral: AppSemanticToneSetting

    static let `default` = AppSemanticColorSettings(
        negative: .make("#F0926C", "#F1BB93"),
        inProgress: .make("#F1E08C", "#FFEFBD"),
        positive: .make("#B6D8A6", "#ADDDC6"),
        neutral: .make("#A1D1E6", "#B5DBED")
    )

    static let darkDefault = AppSemanticColorSettings(
        negative: .make("#97141D", "#AB2D32"),
        inProgress: .make("#A97119", "#D4A639"),
        positive: .make("#115651", "#306F69"),
        neutral: .make("#124680", "#3A72B3")
    )
}

struct AppSemanticColorPreset: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var colors: AppSemanticColorSettings
}

struct AppChromeModeColorSettings: Codable, Hashable {
    var menuHex: String
    var listHex: String
    var workspaceHex: String
    var calendarHex: String? = nil
    var calendarFilterHex: String? = nil
    var calendarHeaderHex: String? = nil
    var calendarWorkspaceHex: String? = nil
    var calendarDayRowHex: String? = nil
}

struct AppChromeColorSettings: Codable, Hashable {
    var standardLight: AppChromeModeColorSettings
    var standardDark: AppChromeModeColorSettings
    var contrastLight: AppChromeModeColorSettings
    var contrastDark: AppChromeModeColorSettings

    static let builtIn = AppChromeColorSettings(
        standardLight: AppChromeModeColorSettings(
            menuHex: "#F7F9F5",
            listHex: "#E8ECE7",
            workspaceHex: "#FBFBF9",
            calendarHex: "#FBFBF9",
            calendarFilterHex: "#E8ECE7",
            calendarHeaderHex: "#E8ECE7",
            calendarWorkspaceHex: "#FBFBF9",
            calendarDayRowHex: "#FFFFFF"
        ),
        standardDark: AppChromeModeColorSettings(
            menuHex: "#0E1012",
            listHex: "#0E1012",
            workspaceHex: "#0B0D0F",
            calendarHex: "#0B0D0F",
            calendarFilterHex: "#0E1012",
            calendarHeaderHex: "#0E1012",
            calendarWorkspaceHex: "#0B0D0F",
            calendarDayRowHex: "#1F2327"
        ),
        contrastLight: AppChromeModeColorSettings(
            menuHex: "#FBFCFA",
            listHex: "#E6EDE8",
            workspaceHex: "#FFFFFF",
            calendarHex: "#FFFFFF",
            calendarFilterHex: "#E6EDE8",
            calendarHeaderHex: "#E6EDE8",
            calendarWorkspaceHex: "#FFFFFF",
            calendarDayRowHex: "#FFFFFF"
        ),
        contrastDark: AppChromeModeColorSettings(
            menuHex: "#040608",
            listHex: "#0E141A",
            workspaceHex: "#171D24",
            calendarHex: "#171D24",
            calendarFilterHex: "#0E141A",
            calendarHeaderHex: "#0E141A",
            calendarWorkspaceHex: "#171D24",
            calendarDayRowHex: "#1F2327"
        )
    )

    static let legacyDarkLightMenuBuiltIn = AppChromeColorSettings(
        standardLight: AppChromeModeColorSettings(menuHex: "#263330", listHex: "#E8ECE7", workspaceHex: "#FBFBF9"),
        standardDark: AppChromeModeColorSettings(menuHex: "#0E1012", listHex: "#0E1012", workspaceHex: "#0B0D0F"),
        contrastLight: AppChromeModeColorSettings(menuHex: "#172624", listHex: "#E6EDE8", workspaceHex: "#FFFFFF"),
        contrastDark: AppChromeModeColorSettings(menuHex: "#040608", listHex: "#0E141A", workspaceHex: "#171D24")
    )

    func migratingLegacyDarkLightMenuDefaults() -> AppChromeColorSettings {
        var copy = self
        let legacy = Self.legacyDarkLightMenuBuiltIn
        if copy.standardLight == legacy.standardLight {
            copy.standardLight = Self.builtIn.standardLight
        }
        if copy.contrastLight == legacy.contrastLight {
            copy.contrastLight = Self.builtIn.contrastLight
        }
        copy.standardLight = copy.standardLight.replacingWithBuiltInIfOnlyCalendarDefaultsAreMissing(Self.builtIn.standardLight)
        copy.standardDark = copy.standardDark.replacingWithBuiltInIfOnlyCalendarDefaultsAreMissing(Self.builtIn.standardDark)
        copy.contrastLight = copy.contrastLight.replacingWithBuiltInIfOnlyCalendarDefaultsAreMissing(Self.builtIn.contrastLight)
        copy.contrastDark = copy.contrastDark.replacingWithBuiltInIfOnlyCalendarDefaultsAreMissing(Self.builtIn.contrastDark)
        return copy
    }
}

extension AppChromeModeColorSettings {
    func replacingWithBuiltInIfOnlyCalendarDefaultsAreMissing(
        _ builtIn: AppChromeModeColorSettings
    ) -> AppChromeModeColorSettings {
        guard menuHex == builtIn.menuHex,
              listHex == builtIn.listHex,
              workspaceHex == builtIn.workspaceHex else {
            return self
        }
        let calendarMatches = calendarHex == nil || calendarHex == builtIn.calendarHex || calendarHex == workspaceHex
        let filterMatches = calendarFilterHex == nil || calendarFilterHex == builtIn.calendarFilterHex || calendarFilterHex == listHex
        let headerMatches = calendarHeaderHex == nil || calendarHeaderHex == builtIn.calendarHeaderHex || calendarHeaderHex == listHex
        let workspaceMatches = calendarWorkspaceHex == nil || calendarWorkspaceHex == builtIn.calendarWorkspaceHex || calendarWorkspaceHex == calendarHex || calendarWorkspaceHex == workspaceHex
        let dayRowMatches = calendarDayRowHex == nil || calendarDayRowHex == builtIn.calendarDayRowHex
        return calendarMatches && filterMatches && headerMatches && workspaceMatches && dayRowMatches ? builtIn : self
    }
}

struct DataSchemaMigrationLogEntry: Codable, Hashable, Identifiable {
    var id: String
    var key: String
    var appliedAt: String
    var details: String
}

struct IDAliasRecord: Codable, Hashable, Identifiable {
    var entityType: String
    var oldID: String
    var newID: String
    var migratedAt: String

    var id: String { "\(entityType)#\(oldID)" }

    func normalized() -> IDAliasRecord? {
        guard let entityType = entityType.trimmedOrNil,
              let oldID = oldID.trimmedOrNil,
              let newID = newID.trimmedOrNil else {
            return nil
        }
        let canonicalNewID = UUID(uuidString: newID)?.uuidString ?? newID
        guard oldID != canonicalNewID else { return nil }
        return IDAliasRecord(
            entityType: entityType,
            oldID: oldID,
            newID: canonicalNewID,
            migratedAt: migratedAt.trimmedOrNil ?? "unknown"
        )
    }
}

struct MediaLanguageOption: Codable, Hashable, Identifiable {
    var id: String
    var nameSv: String
    var nameEn: String

    static let builtInOptions: [MediaLanguageOption] = [
        .init(id: "sv", nameSv: "Svenska", nameEn: "Swedish"),
        .init(id: "en", nameSv: "Engelska", nameEn: "English"),
        .init(id: "no", nameSv: "Norska", nameEn: "Norwegian"),
        .init(id: "da", nameSv: "Danska", nameEn: "Danish"),
        .init(id: "de", nameSv: "Tyska", nameEn: "German"),
        .init(id: "fr", nameSv: "Franska", nameEn: "French"),
        .init(id: "es", nameSv: "Spanska", nameEn: "Spanish")
    ]

    static func normalizedCustomOptions(_ values: [MediaLanguageOption]?) -> [MediaLanguageOption]? {
        var seen = Set<String>()
        let builtInIDs = Set(builtInOptions.map(\.id))
        let normalized = (values ?? []).compactMap { option -> MediaLanguageOption? in
            let id = option.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let nameSv = option.nameSv.trimmingCharacters(in: .whitespacesAndNewlines)
            let nameEn = option.nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !nameSv.isEmpty, !nameEn.isEmpty,
                  !builtInIDs.contains(id), seen.insert(id).inserted else { return nil }
            return MediaLanguageOption(id: id, nameSv: nameSv, nameEn: nameEn)
        }
        return normalized.isEmpty ? nil : normalized.sorted { $0.nameEn.localizedStandardCompare($1.nameEn) == .orderedAscending }
    }

    static func allOptions(custom: [MediaLanguageOption]?) -> [MediaLanguageOption] {
        builtInOptions + (normalizedCustomOptions(custom) ?? [])
    }

    static func canonicalCode(for value: String, options: [MediaLanguageOption]) -> String? {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return options.first { option in
            [option.id, option.nameSv, option.nameEn].contains { $0.lowercased() == key }
        }?.id
    }

    func localizedName(language: AppLanguage) -> String {
        language == .swedish ? nameSv : nameEn
    }
}

struct DataSourceMetadata: Codable, Hashable {
    static let currentSchemaVersion = 13

    var sourceDescription: String
    var lastImportedWorkbook: String?
    var lastImportedAt: String?
    var schemaVersion: Int?
    var migrationLog: [DataSchemaMigrationLogEntry]?
    var idAliases: [IDAliasRecord]?
    var lastMigrationVerificationReport: DataMigrationVerificationReport?
    var interfaceLanguage: String?
    var interfaceVisualMode: String?
    var appChromeScheme: String?
    var appChromeColors: AppChromeColorSettings?
    var showsFooterStatusBar: Bool?
    var lightModeStartsAt: String?
    var darkModeStartsAt: String?
    var exportDirectoryPath: String?
    var projectTimelineYearColumnWidth: Double?
    var projectTimelineRowHeight: Double?
    var projectTimelineBarHeight: Double?
    var projectTimelineMarkerWidth: Double?
    var projectTimelineBarCornerRadius: Double?
    var personIncompleteDataFilter: String?
    var listFilterRetentionPreferences: [String: Bool]?
    var hiddenDataQualityWarningKeys: [String]?
    var ignoredDuplicateWarningKeys: [String]?
    var lastSelectedTab: String?
    var currentUserAuthorID: String?
    var lastSelectedApplicationID: String?
    var lastSelectedProjectID: String?
    var lastSelectedOrganizationID: String?
    var lastSelectedManagerID: String?
    var lastSelectedPersonID: String?
    var lastSelectedJournalID: String?
    var lastSelectedPublicationID: String?
    var lastSelectedTeachingID: String?
    var lastSelectedDoctoralCandidateID: String?
    var lastSelectedCVID: String?
    var salarySources: [SalarySource]?
    var salaryCoveragePeriods: [SalaryCoveragePeriod]?
    /// Canonical store for tasks. Legacy host-owned task arrays are only read during migration.
    var taskItems: [TaskItem]?
    var centralTaskMigrationVersion: Int?
    var teachingWorkspaceTasks: [PublicationTaskItem]?
    var teachingRoleOptions: [TeachingRoleOption]?
    var calendarHolidayCountries: [String]?
    var calendarFirstWeekday: String?
    var calendarCountryDisplayMode: String?
    var calendarHiddenColumnKeys: [String]?
    var calendarHiddenAutomaticEventKeys: [String]?
    var calendarHiddenTaskBadgeIDs: [String]?
    var calendarUsesCompactEventColorBands: Bool?
    var calendarUsesCompactDayHighlightBands: Bool?
    var calendarDayHighlightColors: [CalendarDayHighlightColorSetting]?
    var calendarTravelRecords: [CalendarTravelRecord]?
    var calendarAccommodationRecords: [CalendarAccommodationRecord]?
    var calendarMeetingRecords: [CalendarMeetingRecord]?
    var calendarVerticalNoteRecords: [CalendarVerticalNoteRecord]?
    var calendarMeetingTypeOptions: [String]?
    var calendarCategoryColors: [CalendarCategoryColorSetting]?
    var calendarDayHighlightColorPresets: [CalendarDayHighlightColorPreset]?
    var calendarCategoryColorPresets: [CalendarCategoryColorPreset]?
    var dropdownTranslationsSv: [String: String]?
    var dropdownTranslationsEn: [String: String]?
    var mediaLanguageOptions: [MediaLanguageOption]?
    var appTypography: AppTypographySettings?
    var appSemanticColors: AppSemanticColorSettings?
    var appSemanticColorsLight: AppSemanticColorSettings?
    var appSemanticColorsDark: AppSemanticColorSettings?
    var appSemanticColorPresetsLight: [AppSemanticColorPreset]?
    var appSemanticColorPresetsDark: [AppSemanticColorPreset]?
    var workflowDefaults: WorkflowDefaultSettings?
    /// Settings > Home organization. nil = default (Sweden).
    var homeCountry: String? = nil
    /// Settings > Home organization. nil = not chosen yet (no home region);
    /// "" = none.
    var homeRegionOrganizationID: String? = nil
    /// Round 10, Settings > Home organization: the fund manager (by id) chosen
    /// for new records when the funder has no preferred fund manager.
    var defaultFundManagerOrganizationID: String? = nil
    /// No longer used or shown (the "Main employer" setting had no effect and
    /// was removed). Kept so data saved by earlier versions still loads and
    /// keeps its value.
    var mainEmployerOrganizationID: String? = nil
    /// Settings > Calendar, reminder times and lead days. nil = defaults.
    var calendarReminderSettings: CalendarReminderSettings? = nil
    /// Settings > Calendar categories: statistics, clinical time and leave per
    /// category. nil = not stored yet (the old fixed category names apply).
    var calendarCategoryBehaviors: [CalendarCategoryBehaviorSetting]? = nil
    /// Settings > Calendar, working hours shaded in the week view. nil = defaults.
    var calendarWorkingHours: CalendarWorkingHoursSettings? = nil
    /// Settings > Lists: the researchers' positions. nil = not changed yet
    /// (the built-in list applies; nothing is written until it is edited).
    var researcherPositionOptions: [ResearcherPositionOption]? = nil
    /// Settings > Lists: the researchers' degrees. nil = the built-in list.
    var researcherDegreeOptions: [ResearcherDegreeOption]? = nil
    /// Settings > Lists: physicians' specialties. nil = the built-in list.
    var researcherSpecialtyOptions: [ResearcherSpecialtyOption]? = nil

    static let bundledDefault = DataSourceMetadata(
        sourceDescription: "Bundled data from for app.xlsx",
        lastImportedWorkbook: "for app.xlsx",
        lastImportedAt: nil,
        schemaVersion: DataSourceMetadata.currentSchemaVersion,
        migrationLog: [
            DataSchemaMigrationLogEntry(
                id: "schema-v\(DataSourceMetadata.currentSchemaVersion)",
                key: "schema-v\(DataSourceMetadata.currentSchemaVersion)",
                appliedAt: "bundled",
                details: "Bundled default metadata schema."
            )
        ],
        idAliases: nil,
        lastMigrationVerificationReport: nil,
        interfaceLanguage: AppLanguage.english.rawValue,
        interfaceVisualMode: nil,
        appChromeScheme: nil,
        appChromeColors: nil,
        showsFooterStatusBar: nil,
        lightModeStartsAt: nil,
        darkModeStartsAt: nil,
        exportDirectoryPath: nil,
        projectTimelineYearColumnWidth: nil,
        projectTimelineRowHeight: nil,
        projectTimelineBarHeight: nil,
        projectTimelineMarkerWidth: nil,
        projectTimelineBarCornerRadius: nil,
        personIncompleteDataFilter: nil,
        listFilterRetentionPreferences: nil,
        hiddenDataQualityWarningKeys: nil,
        ignoredDuplicateWarningKeys: nil,
        lastSelectedTab: nil,
        currentUserAuthorID: nil,
        lastSelectedApplicationID: nil,
        lastSelectedProjectID: nil,
        lastSelectedOrganizationID: nil,
        lastSelectedManagerID: nil,
        lastSelectedPersonID: nil,
        lastSelectedJournalID: nil,
        lastSelectedPublicationID: nil,
        lastSelectedTeachingID: nil,
        lastSelectedDoctoralCandidateID: nil,
        lastSelectedCVID: nil,
        salarySources: nil,
        salaryCoveragePeriods: nil,
        taskItems: nil,
        centralTaskMigrationVersion: nil,
        teachingWorkspaceTasks: nil,
        teachingRoleOptions: nil,
        calendarHolidayCountries: nil,
        calendarFirstWeekday: nil,
        calendarCountryDisplayMode: nil,
        calendarHiddenColumnKeys: nil,
        calendarHiddenAutomaticEventKeys: nil,
        calendarHiddenTaskBadgeIDs: nil,
        calendarUsesCompactEventColorBands: nil,
        calendarUsesCompactDayHighlightBands: nil,
        calendarDayHighlightColors: nil,
        calendarTravelRecords: nil,
        calendarAccommodationRecords: nil,
        calendarMeetingRecords: nil,
        calendarVerticalNoteRecords: nil,
        calendarMeetingTypeOptions: nil,
        calendarCategoryColors: nil,
        calendarDayHighlightColorPresets: nil,
        calendarCategoryColorPresets: nil,
        dropdownTranslationsSv: nil,
        dropdownTranslationsEn: nil,
        mediaLanguageOptions: nil,
        appTypography: nil,
        appSemanticColors: nil,
        appSemanticColorsLight: nil,
        appSemanticColorsDark: nil,
        appSemanticColorPresetsLight: nil,
        appSemanticColorPresetsDark: nil
    )

    mutating func migrateLegacyFields() {
        if appSemanticColorsLight == nil, let legacy = appSemanticColors {
            appSemanticColorsLight = legacy
        }
        appSemanticColors = nil
        if let colors = appChromeColors?.migratingLegacyDarkLightMenuDefaults() {
            appChromeColors = colors == .builtIn ? nil : colors
        }

        let normalizedHiddenKeys = Set((hiddenDataQualityWarningKeys ?? []).compactMap(\.trimmedOrNil))
        let normalizedIgnoredKeys = Set((ignoredDuplicateWarningKeys ?? []).compactMap(\.trimmedOrNil))
        let combinedHiddenKeys = normalizedHiddenKeys.union(normalizedIgnoredKeys)
        hiddenDataQualityWarningKeys = combinedHiddenKeys.isEmpty ? nil : combinedHiddenKeys.sorted()
        ignoredDuplicateWarningKeys = normalizedIgnoredKeys.isEmpty ? nil : normalizedIgnoredKeys.sorted()

        let normalizedCalendarHiddenColumnKeys = Set((calendarHiddenColumnKeys ?? []).compactMap(\.trimmedOrNil))
        calendarHiddenColumnKeys = normalizedCalendarHiddenColumnKeys.isEmpty ? nil : normalizedCalendarHiddenColumnKeys.sorted()

        let normalizedCalendarHiddenAutomaticEventKeys = Set((calendarHiddenAutomaticEventKeys ?? []).compactMap(\.trimmedOrNil))
        calendarHiddenAutomaticEventKeys = normalizedCalendarHiddenAutomaticEventKeys.isEmpty ? nil : normalizedCalendarHiddenAutomaticEventKeys.sorted()

        let normalizedCalendarHiddenTaskBadgeIDs = Set((calendarHiddenTaskBadgeIDs ?? []).compactMap(\.trimmedOrNil))
        calendarHiddenTaskBadgeIDs = normalizedCalendarHiddenTaskBadgeIDs.isEmpty ? nil : normalizedCalendarHiddenTaskBadgeIDs.sorted()

        if let taskItems {
            var normalizedTasks: [TaskItem] = []
            var usedIDs = Set<String>()
            for var task in taskItems {
                task.normalize()
                guard !task.isEmpty else { continue }

                var normalizedID = task.id.trimmedOrNil ?? UUID().uuidString
                while !usedIDs.insert(normalizedID).inserted {
                    normalizedID = UUID().uuidString
                }
                task.id = normalizedID
                normalizedTasks.append(task)
            }
            self.taskItems = normalizedTasks.sorted { left, right in
                if left.createdOn != right.createdOn { return left.createdOn < right.createdOn }
                return left.id < right.id
            }
        }

        if let version = schemaVersion, version <= 0 {
            schemaVersion = nil
        }
        if let entries = migrationLog {
            var seenKeys = Set<String>()
            migrationLog = entries.compactMap { entry in
                guard let key = entry.key.trimmedOrNil else { return nil }
                guard seenKeys.insert(key).inserted else { return nil }
                return DataSchemaMigrationLogEntry(
                    id: entry.id.trimmedOrNil ?? key,
                    key: key,
                    appliedAt: entry.appliedAt.trimmedOrNil ?? "unknown",
                    details: entry.details.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            if migrationLog?.isEmpty == true {
                migrationLog = nil
            }
        }

        if let aliases = idAliases {
            var seenAliasKeys = Set<String>()
            idAliases = aliases.compactMap { alias in
                guard let normalized = alias.normalized() else { return nil }
                let key = "\(normalized.entityType)#\(normalized.oldID)"
                guard seenAliasKeys.insert(key).inserted else { return nil }
                return normalized
            }
            if idAliases?.isEmpty == true {
                idAliases = nil
            }
        }

        currentUserAuthorID = currentUserAuthorID?.trimmedOrNil
        mediaLanguageOptions = MediaLanguageOption.normalizedCustomOptions(mediaLanguageOptions)
    }
}

struct AppSettingsSnapshot: Codable, Hashable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var sourceMetadataSchemaVersion: Int?
    var interfaceLanguage: String?
    var interfaceVisualMode: String?
    var appChromeScheme: String?
    var appChromeColors: AppChromeColorSettings?
    var showsFooterStatusBar: Bool?
    var lightModeStartsAt: String?
    var darkModeStartsAt: String?
    var exportDirectoryPath: String?
    var projectTimelineYearColumnWidth: Double?
    var projectTimelineRowHeight: Double?
    var projectTimelineBarHeight: Double?
    var projectTimelineMarkerWidth: Double?
    var projectTimelineBarCornerRadius: Double?
    var personIncompleteDataFilter: String?
    var listFilterRetentionPreferences: [String: Bool]?
    var hiddenDataQualityWarningKeys: [String]?
    var ignoredDuplicateWarningKeys: [String]?
    var lastSelectedTab: String?
    var currentUserAuthorID: String?
    var lastSelectedApplicationID: String?
    var lastSelectedProjectID: String?
    var lastSelectedOrganizationID: String?
    var lastSelectedManagerID: String?
    var lastSelectedPersonID: String?
    var lastSelectedJournalID: String?
    var lastSelectedPublicationID: String?
    var lastSelectedTeachingID: String?
    var lastSelectedDoctoralCandidateID: String?
    var lastSelectedCVID: String?
    var calendarHolidayCountries: [String]?
    var calendarFirstWeekday: String?
    var calendarCountryDisplayMode: String?
    var calendarHiddenColumnKeys: [String]?
    var calendarHiddenAutomaticEventKeys: [String]?
    var calendarHiddenTaskBadgeIDs: [String]?
    var calendarUsesCompactEventColorBands: Bool?
    var calendarUsesCompactDayHighlightBands: Bool?
    var calendarDayHighlightColors: [CalendarDayHighlightColorSetting]?
    var calendarMeetingTypeOptions: [String]?
    var calendarCategoryColors: [CalendarCategoryColorSetting]?
    var calendarDayHighlightColorPresets: [CalendarDayHighlightColorPreset]?
    var calendarCategoryColorPresets: [CalendarCategoryColorPreset]?
    var dropdownTranslationsSv: [String: String]?
    var dropdownTranslationsEn: [String: String]?
    var mediaLanguageOptions: [MediaLanguageOption]?
    var appTypography: AppTypographySettings?
    var appSemanticColorsLight: AppSemanticColorSettings?
    var appSemanticColorsDark: AppSemanticColorSettings?
    var appSemanticColorPresetsLight: [AppSemanticColorPreset]?
    var appSemanticColorPresetsDark: [AppSemanticColorPreset]?
    var workflowDefaults: WorkflowDefaultSettings?
    var homeCountry: String? = nil
    var homeRegionOrganizationID: String? = nil
    var defaultFundManagerOrganizationID: String? = nil
    var mainEmployerOrganizationID: String? = nil
    var calendarReminderSettings: CalendarReminderSettings? = nil
    var calendarCategoryBehaviors: [CalendarCategoryBehaviorSetting]? = nil
    var calendarWorkingHours: CalendarWorkingHoursSettings? = nil

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        sourceMetadataSchemaVersion: Int? = nil,
        interfaceLanguage: String? = nil,
        interfaceVisualMode: String? = nil,
        appChromeScheme: String? = nil,
        appChromeColors: AppChromeColorSettings? = nil,
        showsFooterStatusBar: Bool? = nil,
        lightModeStartsAt: String? = nil,
        darkModeStartsAt: String? = nil,
        exportDirectoryPath: String? = nil,
        projectTimelineYearColumnWidth: Double? = nil,
        projectTimelineRowHeight: Double? = nil,
        projectTimelineBarHeight: Double? = nil,
        projectTimelineMarkerWidth: Double? = nil,
        projectTimelineBarCornerRadius: Double? = nil,
        personIncompleteDataFilter: String? = nil,
        listFilterRetentionPreferences: [String: Bool]? = nil,
        hiddenDataQualityWarningKeys: [String]? = nil,
        ignoredDuplicateWarningKeys: [String]? = nil,
        lastSelectedTab: String? = nil,
        currentUserAuthorID: String? = nil,
        lastSelectedApplicationID: String? = nil,
        lastSelectedProjectID: String? = nil,
        lastSelectedOrganizationID: String? = nil,
        lastSelectedManagerID: String? = nil,
        lastSelectedPersonID: String? = nil,
        lastSelectedJournalID: String? = nil,
        lastSelectedPublicationID: String? = nil,
        lastSelectedTeachingID: String? = nil,
        lastSelectedDoctoralCandidateID: String? = nil,
        lastSelectedCVID: String? = nil,
        calendarHolidayCountries: [String]? = nil,
        calendarFirstWeekday: String? = nil,
        calendarCountryDisplayMode: String? = nil,
        calendarHiddenColumnKeys: [String]? = nil,
        calendarHiddenAutomaticEventKeys: [String]? = nil,
        calendarHiddenTaskBadgeIDs: [String]? = nil,
        calendarUsesCompactEventColorBands: Bool? = nil,
        calendarUsesCompactDayHighlightBands: Bool? = nil,
        calendarDayHighlightColors: [CalendarDayHighlightColorSetting]? = nil,
        calendarMeetingTypeOptions: [String]? = nil,
        calendarCategoryColors: [CalendarCategoryColorSetting]? = nil,
        calendarDayHighlightColorPresets: [CalendarDayHighlightColorPreset]? = nil,
        calendarCategoryColorPresets: [CalendarCategoryColorPreset]? = nil,
        dropdownTranslationsSv: [String: String]? = nil,
        dropdownTranslationsEn: [String: String]? = nil,
        mediaLanguageOptions: [MediaLanguageOption]? = nil,
        appTypography: AppTypographySettings? = nil,
        appSemanticColorsLight: AppSemanticColorSettings? = nil,
        appSemanticColorsDark: AppSemanticColorSettings? = nil,
        appSemanticColorPresetsLight: [AppSemanticColorPreset]? = nil,
        appSemanticColorPresetsDark: [AppSemanticColorPreset]? = nil,
        workflowDefaults: WorkflowDefaultSettings? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sourceMetadataSchemaVersion = sourceMetadataSchemaVersion
        self.interfaceLanguage = interfaceLanguage
        self.interfaceVisualMode = interfaceVisualMode
        self.appChromeScheme = appChromeScheme
        self.appChromeColors = appChromeColors
        self.showsFooterStatusBar = showsFooterStatusBar
        self.lightModeStartsAt = lightModeStartsAt
        self.darkModeStartsAt = darkModeStartsAt
        self.exportDirectoryPath = exportDirectoryPath
        self.projectTimelineYearColumnWidth = projectTimelineYearColumnWidth
        self.projectTimelineRowHeight = projectTimelineRowHeight
        self.projectTimelineBarHeight = projectTimelineBarHeight
        self.projectTimelineMarkerWidth = projectTimelineMarkerWidth
        self.projectTimelineBarCornerRadius = projectTimelineBarCornerRadius
        self.personIncompleteDataFilter = personIncompleteDataFilter
        self.listFilterRetentionPreferences = listFilterRetentionPreferences
        self.hiddenDataQualityWarningKeys = hiddenDataQualityWarningKeys
        self.ignoredDuplicateWarningKeys = ignoredDuplicateWarningKeys
        self.lastSelectedTab = lastSelectedTab
        self.currentUserAuthorID = currentUserAuthorID
        self.lastSelectedApplicationID = lastSelectedApplicationID
        self.lastSelectedProjectID = lastSelectedProjectID
        self.lastSelectedOrganizationID = lastSelectedOrganizationID
        self.lastSelectedManagerID = lastSelectedManagerID
        self.lastSelectedPersonID = lastSelectedPersonID
        self.lastSelectedJournalID = lastSelectedJournalID
        self.lastSelectedPublicationID = lastSelectedPublicationID
        self.lastSelectedTeachingID = lastSelectedTeachingID
        self.lastSelectedDoctoralCandidateID = lastSelectedDoctoralCandidateID
        self.lastSelectedCVID = lastSelectedCVID
        self.calendarHolidayCountries = calendarHolidayCountries
        self.calendarFirstWeekday = calendarFirstWeekday
        self.calendarCountryDisplayMode = calendarCountryDisplayMode
        self.calendarHiddenColumnKeys = calendarHiddenColumnKeys
        self.calendarHiddenAutomaticEventKeys = calendarHiddenAutomaticEventKeys
        self.calendarHiddenTaskBadgeIDs = calendarHiddenTaskBadgeIDs
        self.calendarUsesCompactEventColorBands = calendarUsesCompactEventColorBands
        self.calendarUsesCompactDayHighlightBands = calendarUsesCompactDayHighlightBands
        self.calendarDayHighlightColors = calendarDayHighlightColors
        self.calendarMeetingTypeOptions = calendarMeetingTypeOptions
        self.calendarCategoryColors = calendarCategoryColors
        self.calendarDayHighlightColorPresets = calendarDayHighlightColorPresets
        self.calendarCategoryColorPresets = calendarCategoryColorPresets
        self.dropdownTranslationsSv = dropdownTranslationsSv
        self.dropdownTranslationsEn = dropdownTranslationsEn
        self.mediaLanguageOptions = mediaLanguageOptions
        self.appTypography = appTypography
        self.appSemanticColorsLight = appSemanticColorsLight
        self.appSemanticColorsDark = appSemanticColorsDark
        self.appSemanticColorPresetsLight = appSemanticColorPresetsLight
        self.appSemanticColorPresetsDark = appSemanticColorPresetsDark
        self.workflowDefaults = workflowDefaults
    }

    init(metadata: DataSourceMetadata) {
        self.init(
            sourceMetadataSchemaVersion: metadata.schemaVersion,
            interfaceLanguage: metadata.interfaceLanguage,
            interfaceVisualMode: metadata.interfaceVisualMode,
            appChromeScheme: metadata.appChromeScheme,
            appChromeColors: metadata.appChromeColors,
            showsFooterStatusBar: metadata.showsFooterStatusBar,
            lightModeStartsAt: metadata.lightModeStartsAt,
            darkModeStartsAt: metadata.darkModeStartsAt,
            exportDirectoryPath: metadata.exportDirectoryPath,
            projectTimelineYearColumnWidth: metadata.projectTimelineYearColumnWidth,
            projectTimelineRowHeight: metadata.projectTimelineRowHeight,
            projectTimelineBarHeight: metadata.projectTimelineBarHeight,
            projectTimelineMarkerWidth: metadata.projectTimelineMarkerWidth,
            projectTimelineBarCornerRadius: metadata.projectTimelineBarCornerRadius,
            personIncompleteDataFilter: metadata.personIncompleteDataFilter,
            listFilterRetentionPreferences: metadata.listFilterRetentionPreferences,
            hiddenDataQualityWarningKeys: metadata.hiddenDataQualityWarningKeys,
            ignoredDuplicateWarningKeys: metadata.ignoredDuplicateWarningKeys,
            lastSelectedTab: metadata.lastSelectedTab,
            currentUserAuthorID: metadata.currentUserAuthorID,
            lastSelectedApplicationID: metadata.lastSelectedApplicationID,
            lastSelectedProjectID: metadata.lastSelectedProjectID,
            lastSelectedOrganizationID: metadata.lastSelectedOrganizationID,
            lastSelectedManagerID: metadata.lastSelectedManagerID,
            lastSelectedPersonID: metadata.lastSelectedPersonID,
            lastSelectedJournalID: metadata.lastSelectedJournalID,
            lastSelectedPublicationID: metadata.lastSelectedPublicationID,
            lastSelectedTeachingID: metadata.lastSelectedTeachingID,
            lastSelectedDoctoralCandidateID: metadata.lastSelectedDoctoralCandidateID,
            lastSelectedCVID: metadata.lastSelectedCVID,
            calendarHolidayCountries: metadata.calendarHolidayCountries,
            calendarFirstWeekday: metadata.calendarFirstWeekday,
            calendarCountryDisplayMode: metadata.calendarCountryDisplayMode,
            calendarHiddenColumnKeys: metadata.calendarHiddenColumnKeys,
            calendarHiddenAutomaticEventKeys: metadata.calendarHiddenAutomaticEventKeys,
            calendarHiddenTaskBadgeIDs: metadata.calendarHiddenTaskBadgeIDs,
            calendarUsesCompactEventColorBands: metadata.calendarUsesCompactEventColorBands,
            calendarUsesCompactDayHighlightBands: metadata.calendarUsesCompactDayHighlightBands,
            calendarDayHighlightColors: metadata.calendarDayHighlightColors,
            calendarMeetingTypeOptions: metadata.calendarMeetingTypeOptions,
            calendarCategoryColors: metadata.calendarCategoryColors,
            calendarDayHighlightColorPresets: metadata.calendarDayHighlightColorPresets,
            calendarCategoryColorPresets: metadata.calendarCategoryColorPresets,
            dropdownTranslationsSv: metadata.dropdownTranslationsSv,
            dropdownTranslationsEn: metadata.dropdownTranslationsEn,
            mediaLanguageOptions: metadata.mediaLanguageOptions,
            appTypography: metadata.appTypography,
            appSemanticColorsLight: metadata.appSemanticColorsLight,
            appSemanticColorsDark: metadata.appSemanticColorsDark,
            appSemanticColorPresetsLight: metadata.appSemanticColorPresetsLight,
            appSemanticColorPresetsDark: metadata.appSemanticColorPresetsDark,
            workflowDefaults: metadata.workflowDefaults
        )
        homeCountry = metadata.homeCountry
        homeRegionOrganizationID = metadata.homeRegionOrganizationID
        defaultFundManagerOrganizationID = metadata.defaultFundManagerOrganizationID
        mainEmployerOrganizationID = metadata.mainEmployerOrganizationID
        calendarReminderSettings = metadata.calendarReminderSettings
        calendarCategoryBehaviors = metadata.calendarCategoryBehaviors
        calendarWorkingHours = metadata.calendarWorkingHours
    }

    func applying(to metadata: DataSourceMetadata) -> DataSourceMetadata {
        var updated = metadata
        updated.interfaceLanguage = interfaceLanguage
        updated.interfaceVisualMode = interfaceVisualMode
        updated.appChromeScheme = appChromeScheme
        updated.appChromeColors = appChromeColors
        updated.showsFooterStatusBar = showsFooterStatusBar
        updated.lightModeStartsAt = lightModeStartsAt
        updated.darkModeStartsAt = darkModeStartsAt
        updated.exportDirectoryPath = exportDirectoryPath
        updated.projectTimelineYearColumnWidth = projectTimelineYearColumnWidth
        updated.projectTimelineRowHeight = projectTimelineRowHeight
        updated.projectTimelineBarHeight = projectTimelineBarHeight
        updated.projectTimelineMarkerWidth = projectTimelineMarkerWidth
        updated.projectTimelineBarCornerRadius = projectTimelineBarCornerRadius
        updated.personIncompleteDataFilter = personIncompleteDataFilter
        updated.listFilterRetentionPreferences = listFilterRetentionPreferences
        updated.hiddenDataQualityWarningKeys = hiddenDataQualityWarningKeys
        updated.ignoredDuplicateWarningKeys = ignoredDuplicateWarningKeys
        updated.lastSelectedTab = lastSelectedTab
        updated.currentUserAuthorID = currentUserAuthorID
        updated.lastSelectedApplicationID = lastSelectedApplicationID
        updated.lastSelectedProjectID = lastSelectedProjectID
        updated.lastSelectedOrganizationID = lastSelectedOrganizationID
        updated.lastSelectedManagerID = lastSelectedManagerID
        updated.lastSelectedPersonID = lastSelectedPersonID
        updated.lastSelectedJournalID = lastSelectedJournalID
        updated.lastSelectedPublicationID = lastSelectedPublicationID
        updated.lastSelectedTeachingID = lastSelectedTeachingID
        updated.lastSelectedDoctoralCandidateID = lastSelectedDoctoralCandidateID
        updated.lastSelectedCVID = lastSelectedCVID
        updated.calendarHolidayCountries = calendarHolidayCountries
        updated.calendarFirstWeekday = calendarFirstWeekday
        updated.calendarCountryDisplayMode = calendarCountryDisplayMode
        updated.calendarHiddenColumnKeys = calendarHiddenColumnKeys
        updated.calendarHiddenAutomaticEventKeys = calendarHiddenAutomaticEventKeys
        updated.calendarHiddenTaskBadgeIDs = calendarHiddenTaskBadgeIDs
        updated.calendarUsesCompactEventColorBands = calendarUsesCompactEventColorBands
        updated.calendarUsesCompactDayHighlightBands = calendarUsesCompactDayHighlightBands
        updated.calendarDayHighlightColors = calendarDayHighlightColors
        updated.calendarMeetingTypeOptions = calendarMeetingTypeOptions
        updated.calendarCategoryColors = calendarCategoryColors
        updated.calendarDayHighlightColorPresets = calendarDayHighlightColorPresets
        updated.calendarCategoryColorPresets = calendarCategoryColorPresets
        updated.dropdownTranslationsSv = dropdownTranslationsSv
        updated.dropdownTranslationsEn = dropdownTranslationsEn
        updated.mediaLanguageOptions = mediaLanguageOptions
        updated.appTypography = appTypography
        updated.appSemanticColorsLight = appSemanticColorsLight
        updated.appSemanticColorsDark = appSemanticColorsDark
        updated.appSemanticColorPresetsLight = appSemanticColorPresetsLight
        updated.appSemanticColorPresetsDark = appSemanticColorPresetsDark
        updated.workflowDefaults = workflowDefaults
        updated.homeCountry = homeCountry
        updated.homeRegionOrganizationID = homeRegionOrganizationID
        updated.defaultFundManagerOrganizationID = defaultFundManagerOrganizationID
        updated.mainEmployerOrganizationID = mainEmployerOrganizationID
        updated.calendarReminderSettings = calendarReminderSettings
        updated.calendarCategoryBehaviors = calendarCategoryBehaviors
        updated.calendarWorkingHours = calendarWorkingHours
        return updated
    }
}

final class FixedDropdownTranslationRegistry {
    nonisolated(unsafe) private static var swedishOverrides: [String: String] = [:]
    nonisolated(unsafe) private static var englishOverrides: [String: String] = [:]

    static func update(from metadata: DataSourceMetadata) {
        swedishOverrides = metadata.dropdownTranslationsSv ?? [:]
        englishOverrides = metadata.dropdownTranslationsEn ?? [:]
    }

    static func value(for key: String, language: AppLanguage) -> String? {
        switch language {
        case .english:
            return englishOverrides[key]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        case .swedish:
            return swedishOverrides[key]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
    }
}

func fixedDropdownText(_ key: String, language: AppLanguage, english: String, swedish: String) -> String {
    FixedDropdownTranslationRegistry.value(for: key, language: language) ?? language.text(english, swedish)
}

func fixedDropdownText(
    _ key: String,
    language: AppLanguage,
    definition: DropdownTranslationDefinition
) -> String {
    FixedDropdownTranslationRegistry.value(for: key, language: language)
        ?? (language == .english ? definition.defaultEn : definition.defaultSv)
}

struct DropdownTranslationDefinition: Identifiable, Hashable {
    let key: String
    let sectionEn: String
    let sectionSv: String
    let labelEn: String
    let labelSv: String
    let defaultEn: String
    let defaultSv: String

    var id: String { key }

    var shouldLiveInTeachingTerminology: Bool {
        key.hasPrefix("teachingContext.")
            || key.hasPrefix("teachingReport.")
            || key.hasPrefix("teachingRole.")
            || key.hasPrefix("teachingKind.")
            || key.hasPrefix("teachingParticipant.")
            || key.hasPrefix("teachingDelivery.")
    }

    func usageTitle(language: AppLanguage) -> String {
        switch key {
        case _ where key.hasPrefix("organizationRole."):
            return language.text("Organizations · type", "Organisationer · typ")
        case _ where key.hasPrefix("grantCategory."):
            return language.text("Applications · region", "Ansökningar · region")
        case _ where key.hasPrefix("projectLifecycle."):
            return language.text("Projects · status", "Projekt · status")
        case _ where key.hasPrefix("projectReminder."):
            return language.text("Projects · reminders", "Projekt · påminnelser")
        case _ where key.hasPrefix("applicationStatus."):
            return language.text("Applications · status", "Ansökningar · status")
        case _ where key.hasPrefix("salarySource."):
            return language.text("Salary · source", "Lön · källa")
        case _ where key.hasPrefix("teachingContext."):
            return language.text("Teaching · context", "Undervisning · sammanhang")
        case _ where key.hasPrefix("teachingLevel."):
            return language.text("Teaching · level", "Undervisning · nivå")
        case _ where key.hasPrefix("teachingLanguage."):
            return language.text("Teaching · language", "Undervisning · språk")
        case _ where key.hasPrefix("teachingKind."):
            return language.text("Teaching · assignment type", "Undervisning · uppdragstyp")
        case _ where key.hasPrefix("teachingParticipant."):
            return language.text("Teaching · participant form", "Undervisning · deltagarform")
        case _ where key.hasPrefix("teachingDelivery."):
            return language.text("Teaching · delivery mode", "Undervisning · genomförande")
        case _ where key.hasPrefix("teachingRole."):
            return language.text("Teaching · role", "Undervisning · roll")
        case _ where key.hasPrefix("teachingReport."):
            return language.text("Teaching · reporting category", "Undervisning · rapportkategori")
        case _ where key.hasPrefix("publicationStatus."):
            return language.text("Publications · status", "Publikationer · status")
        case _ where key.hasPrefix("publicationWorkflow."):
            return language.text("Publications · workflow", "Publikationer · arbetsflöde")
        case _ where key.hasPrefix("publicationEducation."):
            return language.text("Researchers · education", "Forskare · utbildning")
        case _ where key.hasPrefix("cvConferenceContribution.status."):
            return language.text("Dissemination · conference status", "Spridning · konferensstatus")
        case _ where key.hasPrefix("cvConferenceContribution.submissionOutcome."):
            return language.text("Dissemination · conference decision", "Spridning · konferensbeslut")
        default:
            return language == .english ? sectionEn : sectionSv
        }
    }

    func usageSubtitle(language: AppLanguage) -> String {
        language == .english ? labelEn : labelSv
    }
}

let editableDropdownTranslationDefinitions: [DropdownTranslationDefinition] = [
    .init(key: "organizationRole.grantProvider", sectionEn: "Organizations", sectionSv: "Organisationer", labelEn: "Grant provider", labelSv: "Anslagsgivare", defaultEn: "Grant provider", defaultSv: "Anslagsgivare"),
    .init(key: "organizationRole.fundManager", sectionEn: "Organizations", sectionSv: "Organisationer", labelEn: "Fund manager", labelSv: "Medelsförvaltare", defaultEn: "Fund manager", defaultSv: "Medelsförvaltare"),
    .init(key: "organizationRole.employer", sectionEn: "Organizations", sectionSv: "Organisationer", labelEn: "Employer", labelSv: "Arbetsgivare", defaultEn: "Employer", defaultSv: "Arbetsgivare"),
    .init(key: "organizationRole.institution", sectionEn: "Organizations", sectionSv: "Organisationer", labelEn: "Higher education institution", labelSv: "Lärosäte", defaultEn: "Higher education institution", defaultSv: "Lärosäte"),
    .init(key: "organizationRole.association", sectionEn: "Organizations", sectionSv: "Organisationer", labelEn: "Association", labelSv: "Förening", defaultEn: "Association", defaultSv: "Förening"),
    .init(key: "organizationRole.company", sectionEn: "Organizations", sectionSv: "Organisationer", labelEn: "Company", labelSv: "Företag", defaultEn: "Company", defaultSv: "Företag"),

    .init(key: "grantCategory.national", sectionEn: "Grants", sectionSv: "Anslag", labelEn: "National", labelSv: "Nationell", defaultEn: "National", defaultSv: "Nationell"),
    .init(key: "grantCategory.regional", sectionEn: "Grants", sectionSv: "Anslag", labelEn: "Regional", labelSv: "Regional", defaultEn: "Regional", defaultSv: "Regional"),
    .init(key: "grantCategory.international", sectionEn: "Grants", sectionSv: "Anslag", labelEn: "International", labelSv: "Internationellt", defaultEn: "International", defaultSv: "Internationellt"),

    .init(key: "projectLifecycle.planned", sectionEn: "Projects", sectionSv: "Projekt", labelEn: "Planned", labelSv: "Planerat", defaultEn: "Planned", defaultSv: "Planerat"),
    .init(key: "projectLifecycle.ongoing", sectionEn: "Projects", sectionSv: "Projekt", labelEn: "Ongoing", labelSv: "Pågående", defaultEn: "Ongoing", defaultSv: "Pågående"),
    .init(key: "projectLifecycle.completed", sectionEn: "Projects", sectionSv: "Projekt", labelEn: "Completed", labelSv: "Avslutat", defaultEn: "Completed", defaultSv: "Avslutat"),

    .init(key: "projectReminder.none", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "None", labelSv: "Ingen", defaultEn: "None", defaultSv: "Ingen"),
    .init(key: "projectReminder.dataCollectionCompleted", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "When data collection is completed", labelSv: "När datainsamling är avslutad", defaultEn: "When data collection is completed", defaultSv: "När datainsamling är avslutad"),
    .init(key: "projectReminder.publicationAdded", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "When a publication is added", labelSv: "När publikation läggs till", defaultEn: "When a publication is added", defaultSv: "När publikation läggs till"),
    .init(key: "projectReminder.newFundsReceived", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "When new funds are received", labelSv: "När nya medel erhålls", defaultEn: "When new funds are received", defaultSv: "När nya medel erhålls"),
    .init(key: "projectReminder.fundsRunOut", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "When funds run out", labelSv: "När medel tar slut", defaultEn: "When funds run out", defaultSv: "När medel tar slut"),
    .init(key: "projectReminder.publicationPublished", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "When a publication is published", labelSv: "När publikation publiceras", defaultEn: "When a publication is published", defaultSv: "När publikation publiceras"),
    .init(key: "projectReminder.manualFollowUp", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Manual follow-up", labelSv: "Följ upp manuellt", defaultEn: "Manual follow-up", defaultSv: "Följ upp manuellt"),
    .init(key: "projectReminder.grantCallOpens", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Grant call opens", labelSv: "Utlysning öppnar", defaultEn: "Grant call opens", defaultSv: "Utlysning öppnar"),
    .init(key: "projectReminder.applicationDeadline", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Application deadline", labelSv: "Ansökningsdeadline", defaultEn: "Application deadline", defaultSv: "Ansökningsdeadline"),
    .init(key: "projectReminder.decisionDate", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Decision date", labelSv: "Beslutsdatum", defaultEn: "Decision date", defaultSv: "Beslutsdatum"),
    .init(key: "projectReminder.reportingDeadline", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Reporting deadline", labelSv: "Rapporteringsdeadline", defaultEn: "Reporting deadline", defaultSv: "Rapporteringsdeadline"),
    .init(key: "projectReminder.finalReportDeadline", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Final reporting deadline", labelSv: "Slutredovisningsdeadline", defaultEn: "Final reporting deadline", defaultSv: "Slutredovisningsdeadline"),
    .init(key: "projectReminder.fundsReceived", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Funds received", labelSv: "Medel mottagna", defaultEn: "Funds received", defaultSv: "Medel mottagna"),
    .init(key: "projectReminder.internalBudgetDeadline", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Internal budget deadline", labelSv: "Intern budgetdeadline", defaultEn: "Internal budget deadline", defaultSv: "Intern budgetdeadline"),
    .init(key: "projectReminder.projectEndDate", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Project end date", labelSv: "Projekt slutdatum", defaultEn: "Project end date", defaultSv: "Projekt slutdatum"),
    .init(key: "projectReminder.employmentStart", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Employment start", labelSv: "Anställningsstart", defaultEn: "Employment start", defaultSv: "Anställningsstart"),
    .init(key: "projectReminder.employmentEnd", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Employment end", labelSv: "Anställningsslut", defaultEn: "Employment end", defaultSv: "Anställningsslut"),
    .init(key: "projectReminder.budgetPeriodStart", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Budget period start", labelSv: "Budgetperiod start", defaultEn: "Budget period start", defaultSv: "Budgetperiod start"),
    .init(key: "projectReminder.budgetPeriodEnd", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Budget period end", labelSv: "Budgetperiod slut", defaultEn: "Budget period end", defaultSv: "Budgetperiod slut"),
    .init(key: "projectReminder.salaryRevisionDate", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Salary revision date", labelSv: "Lönerevision datum", defaultEn: "Salary revision date", defaultSv: "Lönerevision datum"),
    .init(key: "projectReminder.termStart", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Term start", labelSv: "Terminsstart", defaultEn: "Term start", defaultSv: "Terminsstart"),
    .init(key: "projectReminder.termEnd", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Term end", labelSv: "Terminsslut", defaultEn: "Term end", defaultSv: "Terminsslut"),
    .init(key: "projectReminder.courseStart", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Course start", labelSv: "Kursstart", defaultEn: "Course start", defaultSv: "Kursstart"),
    .init(key: "projectReminder.courseEnd", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Course end", labelSv: "Kursavslut", defaultEn: "Course end", defaultSv: "Kursavslut"),
    .init(key: "projectReminder.examinationDate", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Examination date", labelSv: "Examinationsdatum", defaultEn: "Examination date", defaultSv: "Examinationsdatum"),
    .init(key: "projectReminder.congressStart", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Congress start", labelSv: "Kongress start", defaultEn: "Congress start", defaultSv: "Kongress start"),
    .init(key: "projectReminder.congressEnd", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Congress end", labelSv: "Kongress slut", defaultEn: "Congress end", defaultSv: "Kongress slut"),
    .init(key: "projectReminder.abstractDeadline", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Abstract deadline", labelSv: "Abstractdeadline", defaultEn: "Abstract deadline", defaultSv: "Abstractdeadline"),
    .init(key: "projectReminder.lateAbstractDeadline", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Late abstract deadline", labelSv: "Sen abstractdeadline", defaultEn: "Late abstract deadline", defaultSv: "Sen abstractdeadline"),
    .init(key: "projectReminder.membershipStart", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Membership start", labelSv: "Medlemskap start", defaultEn: "Membership start", defaultSv: "Medlemskap start"),
    .init(key: "projectReminder.membershipEnd", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Membership end", labelSv: "Medlemskap slut", defaultEn: "Membership end", defaultSv: "Medlemskap slut"),
    .init(key: "projectReminder.annualMeetingDate", sectionEn: "Project reminders", sectionSv: "Projektpåminnelser", labelEn: "Annual meeting date", labelSv: "Årsmötesdatum", defaultEn: "Annual meeting date", defaultSv: "Årsmötesdatum"),

    .init(key: "applicationStatus.toApply", sectionEn: "Applications", sectionSv: "Ansökningar", labelEn: "To apply", labelSv: "Att söka", defaultEn: "To apply", defaultSv: "Att söka"),
    .init(key: "applicationStatus.awaitingResponse", sectionEn: "Applications", sectionSv: "Ansökningar", labelEn: "Awaiting decision", labelSv: "Väntar svar", defaultEn: "Awaiting decision", defaultSv: "Väntar svar"),
    .init(key: "applicationStatus.awarded", sectionEn: "Applications", sectionSv: "Ansökningar", labelEn: "Granted", labelSv: "Beviljat", defaultEn: "Granted", defaultSv: "Beviljat"),
    .init(key: "applicationStatus.declined", sectionEn: "Applications", sectionSv: "Ansökningar", labelEn: "Declined", labelSv: "Avslag", defaultEn: "Declined", defaultSv: "Avslag"),
    .init(key: "applicationStatus.withdrawn", sectionEn: "Applications", sectionSv: "Ansökningar", labelEn: "Withdrawn", labelSv: "Tillbakadragen", defaultEn: "Withdrawn", defaultSv: "Tillbakadragen"),
    .init(key: "applicationStatus.unknown", sectionEn: "Applications", sectionSv: "Ansökningar", labelEn: "Unknown", labelSv: "Okänd", defaultEn: "Unknown", defaultSv: "Okänd"),

    .init(key: "salarySource.clinic", sectionEn: "Salary", sectionSv: "Lön", labelEn: "Clinic", labelSv: "Klinik", defaultEn: "Clinic", defaultSv: "Klinik"),
    .init(key: "salarySource.teaching", sectionEn: "Salary", sectionSv: "Lön", labelEn: "Teaching", labelSv: "Undervisning", defaultEn: "Teaching", defaultSv: "Undervisning"),
    .init(key: "salarySource.research", sectionEn: "Salary", sectionSv: "Lön", labelEn: "Research", labelSv: "Forskning", defaultEn: "Research", defaultSv: "Forskning"),
    .init(key: "salarySource.other", sectionEn: "Salary", sectionSv: "Lön", labelEn: "Other", labelSv: "Övrigt", defaultEn: "Other", defaultSv: "Övrigt"),

    .init(key: "teachingContext.course", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Course", labelSv: "Kurs", defaultEn: "Course", defaultSv: "Kurs"),
    .init(key: "teachingContext.programTrack", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Program / track", labelSv: "Program / spår", defaultEn: "Program / track", defaultSv: "Program / spår"),
    .init(key: "teachingContext.doctoralEducation", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Doctoral education", labelSv: "Forskarutbildning", defaultEn: "Doctoral education", defaultSv: "Forskarutbildning"),
    .init(key: "teachingContext.clinicalTeaching", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Clinical teaching", labelSv: "Klinisk undervisning", defaultEn: "Clinical teaching", defaultSv: "Klinisk undervisning"),
    .init(key: "teachingContext.courseAdministration", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Course administration / development", labelSv: "Kursadministration / kursutveckling", defaultEn: "Course administration / development", defaultSv: "Kursadministration / kursutveckling"),
    .init(key: "teachingContext.other", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Other", labelSv: "Övrigt", defaultEn: "Other", defaultSv: "Övrigt"),

    .init(key: "teachingLevel.undergraduate", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Undergraduate", labelSv: "Grundnivå", defaultEn: "Undergraduate", defaultSv: "Grundnivå"),
    .init(key: "teachingLevel.advanced", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Advanced", labelSv: "Avancerad nivå", defaultEn: "Advanced", defaultSv: "Avancerad nivå"),
    .init(key: "teachingLevel.doctoral", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Doctoral", labelSv: "Forskarnivå", defaultEn: "Doctoral", defaultSv: "Forskarnivå"),

    .init(key: "teachingLanguage.swedish", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Swedish", labelSv: "svenska", defaultEn: "Swedish", defaultSv: "svenska"),
    .init(key: "teachingLanguage.english", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "English", labelSv: "engelska", defaultEn: "English", defaultSv: "engelska"),

    .init(key: "teachingKind.teaching", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Teaching", labelSv: "Undervisning", defaultEn: "Teaching", defaultSv: "Undervisning"),
    .init(key: "teachingKind.supervision", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Supervision", labelSv: "Handledning", defaultEn: "Supervision", defaultSv: "Handledning"),
    .init(key: "teachingKind.clinical", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Clinical teaching", labelSv: "Klinisk undervisning", defaultEn: "Clinical teaching", defaultSv: "Klinisk undervisning"),
    .init(key: "teachingKind.development", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Development work", labelSv: "Utvecklingsarbete", defaultEn: "Development work", defaultSv: "Utvecklingsarbete"),

    .init(key: "teachingParticipant.individual", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Individual", labelSv: "Individuell", defaultEn: "Individual", defaultSv: "Individuell"),
    .init(key: "teachingParticipant.group", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Group", labelSv: "Grupp", defaultEn: "Group", defaultSv: "Grupp"),
    .init(key: "teachingParticipant.groupAndIndividual", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Group and individual", labelSv: "Grupp och individuellt", defaultEn: "Group and individual", defaultSv: "Grupp och individuellt"),
    .init(key: "teachingParticipant.notTeachingWork", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Not teaching work", labelSv: "Ej undervisningsarbete", defaultEn: "Not teaching work", defaultSv: "Ej undervisningsarbete"),

    .init(key: "teachingDelivery.onSite", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "On-site", labelSv: "Fysiskt", defaultEn: "On-site", defaultSv: "Fysiskt"),
    .init(key: "teachingDelivery.hybrid", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Hybrid", labelSv: "Hybrid", defaultEn: "Hybrid", defaultSv: "Hybrid"),
    .init(key: "teachingDelivery.online", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Online", labelSv: "Online", defaultEn: "Online", defaultSv: "Online"),

    .init(key: "teachingRole.facilitator", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Facilitator", labelSv: "Facilitator", defaultEn: "Facilitator", defaultSv: "Facilitator"),
    .init(key: "teachingRole.supervisor", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Supervisor", labelSv: "Handledare", defaultEn: "Supervisor", defaultSv: "Handledare"),
    .init(key: "teachingRole.examiner", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Examiner", labelSv: "Examinator", defaultEn: "Examiner", defaultSv: "Examinator"),
    .init(key: "teachingRole.lecturer", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Lecturer", labelSv: "Föreläsare", defaultEn: "Lecturer", defaultSv: "Föreläsare"),
    .init(key: "teachingRole.invitedSpeaker", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Invited speaker", labelSv: "Inbjuden talare", defaultEn: "Invited speaker", defaultSv: "Inbjuden talare"),
    .init(key: "teachingRole.seminarLeader", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Seminar leader", labelSv: "Seminarieledare", defaultEn: "Seminar leader", defaultSv: "Seminarieledare"),
    .init(key: "teachingRole.principalSupervisor", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Principal supervisor", labelSv: "Huvudhandledare", defaultEn: "Principal supervisor", defaultSv: "Huvudhandledare"),
    .init(key: "teachingRole.assistantSupervisor", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Co-supervisor", labelSv: "Bihandledare", defaultEn: "Co-supervisor", defaultSv: "Bihandledare"),
    .init(key: "teachingRole.opponent", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Opponent", labelSv: "Opponent", defaultEn: "Opponent", defaultSv: "Opponent"),

    .init(key: "teachingReport.groupTeaching", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Group teaching / practical teaching", labelSv: "Gruppundervisning / praktisk undervisning", defaultEn: "Group teaching / practical teaching", defaultSv: "Gruppundervisning / praktisk undervisning"),
    .init(key: "teachingReport.lecture", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Lecture", labelSv: "Föreläsning", defaultEn: "Lecture", defaultSv: "Föreläsning"),
    .init(key: "teachingReport.doctoralCourseTeaching", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Doctoral course teaching", labelSv: "Undervisning på forskarutbildningskurs", defaultEn: "Doctoral course teaching", defaultSv: "Undervisning på forskarutbildningskurs"),
    .init(key: "teachingReport.thesisSupervision", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Thesis / in-depth project supervision", labelSv: "Handledning av examensarbete / fördjupningsarbete", defaultEn: "Thesis / in-depth project supervision", defaultSv: "Handledning av examensarbete / fördjupningsarbete"),
    .init(key: "teachingReport.doctoralPrincipalSupervision", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Doctoral supervision (principal)", labelSv: "Doktorandhandledning (huvudhandledare)", defaultEn: "Doctoral supervision (principal)", defaultSv: "Doktorandhandledning (huvudhandledare)"),
    .init(key: "teachingReport.doctoralAssistantSupervision", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Doctoral supervision (co-supervisor)", labelSv: "Doktorandhandledning (bihandledare)", defaultEn: "Doctoral supervision (co-supervisor)", defaultSv: "Doktorandhandledning (bihandledare)"),
    .init(key: "teachingReport.courseAdministration", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Course administration / development", labelSv: "Kursadministration / kursutveckling", defaultEn: "Course administration / development", defaultSv: "Kursadministration / kursutveckling"),
    .init(key: "teachingReport.otherPedagogicalWork", sectionEn: "Teaching", sectionSv: "Undervisning", labelEn: "Other pedagogical work", labelSv: "Övrigt pedagogiskt arbete", defaultEn: "Other pedagogical work", defaultSv: "Övrigt pedagogiskt arbete"),

    .init(key: "publicationStatus.planned", sectionEn: "Publications", sectionSv: "Publikationer", labelEn: "Planned", labelSv: "Planerad", defaultEn: "Planned", defaultSv: "Planerad"),
    .init(key: "publicationStatus.inPreparation", sectionEn: "Publications", sectionSv: "Publikationer", labelEn: "In preparation", labelSv: "Under arbete", defaultEn: "In preparation", defaultSv: "Under arbete"),
    .init(key: "publicationStatus.submitted", sectionEn: "Publications", sectionSv: "Publikationer", labelEn: "Submitted", labelSv: "Inskickad", defaultEn: "Submitted", defaultSv: "Inskickad"),
    .init(key: "publicationStatus.accepted", sectionEn: "Publications", sectionSv: "Publikationer", labelEn: "Accepted", labelSv: "Accepterad", defaultEn: "Accepted", defaultSv: "Accepterad"),
    .init(key: "publicationStatus.rejected", sectionEn: "Publications", sectionSv: "Publikationer", labelEn: "Rejected", labelSv: "Refuserad", defaultEn: "Rejected", defaultSv: "Refuserad"),
    .init(key: "publicationStatus.published", sectionEn: "Publications", sectionSv: "Publikationer", labelEn: "Published", labelSv: "Publicerad", defaultEn: "Published", defaultSv: "Publicerad"),

    .init(key: "publicationWorkflow.dataCollection", sectionEn: "Publications", sectionSv: "Publikationer", labelEn: "Data collection", labelSv: "Datainsamling", defaultEn: "Data collection", defaultSv: "Datainsamling"),
    .init(key: "publicationWorkflow.dataProcessing", sectionEn: "Publications", sectionSv: "Publikationer", labelEn: "Data processing", labelSv: "Databearbetning", defaultEn: "Data processing", defaultSv: "Databearbetning"),
    .init(key: "publicationWorkflow.manuscriptWriting", sectionEn: "Publications", sectionSv: "Publikationer", labelEn: "Manuscript writing", labelSv: "Manusskrivande", defaultEn: "Manuscript writing", defaultSv: "Manusskrivande"),
    .init(key: "publicationWorkflow.withCoauthors", sectionEn: "Publications", sectionSv: "Publikationer", labelEn: "With co-authors", labelSv: "Hos medförfattare", defaultEn: "With co-authors", defaultSv: "Hos medförfattare"),

    .init(key: "publicationEducation.basicEducation", sectionEn: "Researchers", sectionSv: "Forskare", labelEn: "Basic education", labelSv: "Grundutbildning", defaultEn: "Basic education", defaultSv: "Grundutbildning"),
    .init(key: "publicationEducation.standaloneCourse", sectionEn: "Researchers", sectionSv: "Forskare", labelEn: "Standalone course", labelSv: "Fristående kurs", defaultEn: "Standalone course", defaultSv: "Fristående kurs"),
    .init(key: "publicationEducation.bachelor", sectionEn: "Researchers", sectionSv: "Forskare", labelEn: "Bachelor", labelSv: "Kandidat", defaultEn: "Bachelor", defaultSv: "Kandidat"),
    .init(key: "publicationEducation.master", sectionEn: "Researchers", sectionSv: "Forskare", labelEn: "Master", labelSv: "Magister", defaultEn: "Master", defaultSv: "Magister"),
    .init(key: "publicationEducation.doctoral", sectionEn: "Researchers", sectionSv: "Forskare", labelEn: "Doctoral education", labelSv: "Forskarutbildning", defaultEn: "Doctoral education", defaultSv: "Forskarutbildning"),
    .init(key: "publicationEducation.other", sectionEn: "Researchers", sectionSv: "Forskare", labelEn: "Other", labelSv: "Övrigt", defaultEn: "Other", defaultSv: "Övrigt"),

    .init(key: "cvConferenceContribution.status.planned", sectionEn: "Dissemination", sectionSv: "Spridning", labelEn: "Conference contribution: planned", labelSv: "Konferensbidrag: planerat", defaultEn: "Planned", defaultSv: "Planerat"),
    .init(key: "cvConferenceContribution.status.presented", sectionEn: "Dissemination", sectionSv: "Spridning", labelEn: "Conference contribution: presented", labelSv: "Konferensbidrag: presenterad", defaultEn: "Presented", defaultSv: "Presenterad"),
    .init(key: "cvConferenceContribution.submissionOutcome.granted", sectionEn: "Dissemination", sectionSv: "Spridning", labelEn: "Conference contribution: accepted", labelSv: "Konferensbidrag: accepterad", defaultEn: "Accepted", defaultSv: "Accepterad"),
    .init(key: "cvConferenceContribution.submissionOutcome.declined", sectionEn: "Dissemination", sectionSv: "Spridning", labelEn: "Conference contribution: rejected", labelSv: "Konferensbidrag: refuserad", defaultEn: "Rejected", defaultSv: "Refuserad"),
]

enum SalarySourceCategory: String, Codable, CaseIterable, Hashable {
    case clinic = "Klinik"
    case teaching = "Undervisning"
    case research = "Forskning"
    case other = "Övrigt"
}

/// Round 7: the colour a salary source is drawn with in the salary plan,
/// chosen in the salary source editor. Three of the choices follow a
/// calendar colour (the "Klinik" meeting category, activity 2 or
/// activity 3), so changing that colour in the settings changes the salary
/// plan too.
enum SalarySourceColor: String, CaseIterable, Hashable {
    case clinicCalendarCategory = "clinic"
    case calendarActivity2 = "activity2"
    case calendarActivity3 = "activity3"
    case blue
    case red

    /// The colour a source gets when none has been chosen: by category.
    static func defaultColor(for category: SalarySourceCategory) -> SalarySourceColor {
        switch category {
        case .clinic:
            return .clinicCalendarCategory
        case .research:
            return .calendarActivity3
        case .teaching:
            return .blue
        case .other:
            return .red
        }
    }

    func localizedName(language: AppLanguage) -> String {
        switch self {
        case .clinicCalendarCategory:
            return language.text("Calendar color for Klinik meetings", "Kalenderns färg för Klinik-möten")
        case .calendarActivity2:
            return language.text("Calendar color for Activity 2", "Kalenderns färg för Aktivitet 2")
        case .calendarActivity3:
            return language.text("Calendar color for Activity 3", "Kalenderns färg för Aktivitet 3")
        case .blue:
            return language.text("Blue", "Blå")
        case .red:
            return language.text("Red", "Röd")
        }
    }
}

struct SalarySource: Identifiable, Codable, Hashable {
    var id: String
    var category: SalarySourceCategory
    var project: String
    var projectSv: String?
    var projectEn: String?
    var projectNumber: String?
    var peoe: String?
    /// Round 7: the chosen colour (a `SalarySourceColor` raw value); nil =
    /// the category's colour. Stored as text so an unknown value written by
    /// a newer version never stops the data from loading.
    var color: String?

    init(
        id: String = UUID().uuidString,
        category: SalarySourceCategory,
        project: String,
        projectSv: String? = nil,
        projectEn: String? = nil,
        projectNumber: String? = nil,
        peoe: String? = nil,
        color: SalarySourceColor? = nil
    ) {
        self.id = id
        self.category = category
        self.project = project
        self.projectSv = projectSv
        self.projectEn = projectEn
        self.projectNumber = projectNumber
        self.peoe = peoe
        self.color = color?.rawValue
    }

    /// The colour the source is drawn with: the chosen one, else the
    /// category's colour. Never depends on the source's name.
    var effectiveColor: SalarySourceColor {
        color.flatMap { SalarySourceColor(rawValue: $0) } ?? SalarySourceColor.defaultColor(for: category)
    }

    /// Starting list before the user has saved any salary sources. Only
    /// generic entries belong here; the user's own sources live in metadata.
    static let defaults: [SalarySource] = [
        SalarySource(category: .other, project: "Tjänstledighet", projectSv: "Tjänstledighet", projectEn: "On leave", color: .red),
    ]

    /// Round 7, one-time migration: gives every source without a chosen
    /// colour the colour it was drawn with until now, and writes the Swedish
    /// and English names that used to be built in for "Tjänstledighet", so
    /// nothing changes on screen now that the app no longer looks at the
    /// names. A source that already has a colour or a name keeps it; running
    /// it again changes nothing. (Special cases for the names of particular
    /// organizations were stored in the data by an earlier version and are no
    /// longer part of the app.)
    static func migratedForStoredColorsAndNames(_ sources: [SalarySource]) -> [SalarySource] {
        sources.map { source in
            var updated = source
            if updated.color?.trimmedOrNil == nil {
                // The colour rules the salary plan used before round 7.
                let legacyKey = source.projectSv?.nonEmpty ?? source.projectEn?.nonEmpty ?? source.project
                let legacyColor: SalarySourceColor
                if legacyKey == "Tjänstledighet" || legacyKey == "On leave" {
                    legacyColor = .red
                } else {
                    legacyColor = SalarySourceColor.defaultColor(for: source.category)
                }
                updated.color = legacyColor.rawValue
            }
            // The names that were shown when a language's name was missing.
            switch source.project {
            case "Tjänstledighet", "On leave":
                if updated.projectSv?.nonEmpty == nil { updated.projectSv = "Tjänstledighet" }
                if updated.projectEn?.nonEmpty == nil { updated.projectEn = "On leave" }
            default:
                break
            }
            return updated
        }
    }
}

struct SalaryCoveragePeriod: Identifiable, Codable, Hashable {
    var id: String
    var sourceReference: String
    var from: String
    var to: String
    var percentage: String

    init(
        id: String = UUID().uuidString,
        sourceReference: String = "",
        from: String = "",
        to: String = "",
        percentage: String = ""
    ) {
        self.id = id
        self.sourceReference = sourceReference
        self.from = from
        self.to = to
        self.percentage = percentage
    }
}

struct GrantConsumptionPeriod: Identifiable, Codable, Hashable {
    var id: String
    var from: String
    var to: String
    var amount: String

    init(id: String = UUID().uuidString, from: String = "", to: String = "", amount: String = "") {
        self.id = id
        self.from = from
        self.to = to
        self.amount = amount
    }

    var amountValue: Double? {
        GrantParsing.numericValue(from: amount)
    }
}

struct ProjectTimelineStyle: Codable, Hashable {
    var yearColumnWidth: Double
    var rowHeight: Double
    var barHeight: Double
    var markerWidth: Double
    var barCornerRadius: Double

    static let `default` = ProjectTimelineStyle(
        yearColumnWidth: 148,
        rowHeight: 36,
        barHeight: 28,
        markerWidth: 4,
        barCornerRadius: 0
    )
}

enum PersonIncompleteDataFilter: String, Codable, CaseIterable {
    case none
    case any
    case orcid
    case email
    case organization
    case country
    case title
}

enum ListFilterPersistenceKey: String, Codable, CaseIterable, Identifiable {
    case applications
    case teaching
    case doctoralCandidates
    case dissemination
    case expertAssignments
    case dataQuality
    case organizations
    case projects
    case researchers
    case journals
    case publications
    case congresses

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .applications:
            return language.text("Calls and grants", "Utlysningar och anslag")
        case .teaching:
            return language.text("Teaching", "Undervisning")
        case .doctoralCandidates:
            return language.text("Doctoral candidates", "Doktorander")
        case .dissemination:
            return language.text("Dissemination", "Spridning")
        case .expertAssignments:
            return language.text("Expert assignments", "Sakkunniguppdrag")
        case .dataQuality:
            return language.text("Data quality", "Datakvalitet")
        case .organizations:
            return language.text("Organizations", "Organisationer")
        case .projects:
            return language.text("Projects", "Projekt")
        case .researchers:
            return language.text("Researchers", "Forskare")
        case .journals:
            return language.text("Journals", "Tidskrifter")
        case .publications:
            return language.text("Publications", "Publikationer")
        case .congresses:
            return language.text("Congresses", "Kongresser")
        }
    }
}

struct StatisticsYearBlock: Identifiable {
    let id: String
    let year: String
    let resultRows: [StatisticsResultRow]
}

struct StatisticsResultRow: Identifiable {
    let id = UUID()
    let result: String
    let total: Int
    let below250k: Int
    let between250kAnd1m: Int
    let above1m: Int
}

struct AppRoute: Equatable, Identifiable {
    enum Destination: Equatable {
        case applications
        case congresses
        case cv
        case expertAssignments
        case publications
        case projects
        case teaching
        case doctoralCandidates
        case organizations
        case people
        case journals
    }

    let recordID: String
    let destination: Destination
    /// A navigation request is an event, not just a location.  Keeping an
    /// event identity means that opening the same record twice is observable
    /// by SwiftUI and cannot be mistaken for a stale, already handled route.
    let requestID: UUID

    init(recordID: String, destination: Destination, requestID: UUID = UUID()) {
        self.recordID = recordID
        self.destination = destination
        self.requestID = requestID
    }

    var id: String {
        requestID.uuidString
    }

    func targetsSameRecord(as other: AppRoute) -> Bool {
        recordID == other.recordID && destination == other.destination
    }
}

struct UndoRevealTarget: Equatable {
    enum Destination: Equatable {
        case route(AppRoute)
        case calendar(dayString: String, eventSource: CalendarWorkspaceEventSource?)
    }

    let destination: Destination
    var fieldKey: String? = nil
}

struct UndoRevealRequest: Identifiable, Equatable {
    let id = UUID()
    let target: UndoRevealTarget
    let actionName: String
    let isRedo: Bool
}

struct CalendarOpenRequest: Equatable, Identifiable {
    enum Kind: Equatable {
        case todo
        case travel
        case accommodation
        case meeting
        case projectTask(projectID: String)
        case publicationTask(publicationID: String)
    }

    let kind: Kind
    let recordID: String

    var id: String {
        switch kind {
        case .todo:
            return "calendar-todo:\(recordID)"
        case .travel:
            return "calendar-travel:\(recordID)"
        case .accommodation:
            return "calendar-accommodation:\(recordID)"
        case .meeting:
            return "calendar-meeting:\(recordID)"
        case let .projectTask(projectID):
            return "calendar-project-task:\(projectID):\(recordID)"
        case let .publicationTask(publicationID):
            return "calendar-publication-task:\(publicationID):\(recordID)"
        }
    }
}

struct CalendarRevealRequest: Equatable, Identifiable {
    let id = UUID()
    let dayString: String
    let eventSource: CalendarWorkspaceEventSource?

    init(dayString: String, eventSource: CalendarWorkspaceEventSource? = nil) {
        self.dayString = dayString
        self.eventSource = eventSource
    }
}

private final class StrictISODateFormatter: DateFormatter, @unchecked Sendable {
    override func date(from string: String) -> Date? {
        guard string.range(
            of: #"^\d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        guard let parsed = super.date(from: string) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: parsed)
        let expectedParts = string.split(separator: "-").compactMap { Int($0) }
        guard expectedParts.count == 3,
              components.year == expectedParts[0],
              components.month == expectedParts[1],
              components.day == expectedParts[2] else {
            return nil
        }
        return parsed
    }
}

enum DateParsers {
    private static let isoDayThreadKey = "Footprint.DateParsers.isoDay"
    private static let displayDayThreadKey = "Footprint.DateParsers.displayDay"

    static var isoDay: DateFormatter {
        threadLocalFormatter(key: isoDayThreadKey) {
            let formatter = StrictISODateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }
    }

    static var displayDay: DateFormatter {
        threadLocalFormatter(key: displayDayThreadKey) {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter
        }
    }

    private static func threadLocalFormatter(
        key: String,
        makeFormatter: () -> DateFormatter
    ) -> DateFormatter {
        let dictionary = Thread.current.threadDictionary
        if let formatter = dictionary[key] as? DateFormatter {
            return formatter
        }

        let formatter = makeFormatter()
        dictionary[key] = formatter
        return formatter
    }

    /// F10: a day that does not exist in the month becomes the month's last day.
    static func clampedDayOfMonth(year: String, month: String, day: String) -> String {
        guard let y = Int(year), let m = Int(month), let d = Int(day), (1...12).contains(m), d > 0 else { return day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let firstOfMonth = calendar.date(from: DateComponents(year: y, month: m, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return day }
        return String(format: "%02d", min(d, range.count))
    }

    static func canonicalizedDayInput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digitsOnly: String
        if trimmed.range(of: #"^\d{8}$"#, options: .regularExpression) != nil {
            digitsOnly = trimmed
        } else if trimmed.range(
            of: #"^\d{4}[-./]\d{2}[-./]\d{2}$"#,
            options: .regularExpression
        ) != nil {
            digitsOnly = trimmed.filter(\.isNumber)
        } else {
            return raw
        }
        guard digitsOnly.count == 8 else {
            return raw
        }
        let year = digitsOnly.prefix(4)
        let month = digitsOnly.dropFirst(4).prefix(2)
        let day = digitsOnly.dropFirst(6).prefix(2)
        return "\(year)-\(month)-\(clampedDayOfMonth(year: String(year), month: String(month), day: String(day)))"
    }
}

enum GrantParsing {
    static let statusOptions = ["Att söka", "Väntar svar", "Beviljat", "Avslag", "Tillbakadragen", "Ej sökt"]
    static let grantCategoryOptions = ["National", "Regional", "Local", "International"]
    static let currencyOptions = ["SEK", "EUR", "USD", "NOK"]
    static let countryRegions: [Locale.Region] = Locale.Region.isoRegions.filter { region in
        let identifier = region.identifier
        return identifier.count == 2 && identifier.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
    }
    static let countryOptions: [String] = {
        let locale = Locale(identifier: "en_US")
        let names = countryRegions
            .compactMap { locale.localizedString(forRegionCode: $0.identifier) }
            .map {
                canonicalCountryName(
                    $0.replacingOccurrences(of: "&", with: "and")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.isEmpty }
        return Array(Set(names + ["International", "Somaliland"])).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()
    static let countryRegionCodeByCanonicalName: [String: String] = {
        let locale = Locale(identifier: "en_US")
        var mapping: [String: String] = [:]
        for region in countryRegions {
            guard let englishName = locale.localizedString(forRegionCode: region.identifier) else { continue }
            let canonical = canonicalCountryName(
                englishName
                    .replacingOccurrences(of: "&", with: "and")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !canonical.isEmpty else { continue }
            mapping[canonical] = region.identifier
        }
        return mapping
    }()

    private static let countryAliases: [String: String] = [
        "international": "International",
        "internationell": "International",
        "somaliland": "Somaliland",
        "england": "United Kingdom",
        "scotland": "United Kingdom",
        "wales": "United Kingdom",
        "northern ireland": "United Kingdom",
        "great britain": "United Kingdom",
        "britain": "United Kingdom",
        "u.k.": "United Kingdom",
        "uk": "United Kingdom",
        "korea (south)": "South Korea",
        "republic of korea": "South Korea",
        "south korea": "South Korea",
        "sydkorea": "South Korea",
        "korea (north)": "North Korea",
        "north korea": "North Korea",
        "democratic people's republic of korea": "North Korea",
        "china": "China",
        "kina": "China",
        "people's republic of china": "China",
        "mainland china": "China",
        "china mainland": "China",
        "kina, fastlandet": "China",
        "united states of america": "United States",
        "usa": "United States",
        "u.s.a.": "United States",
        "u.s.": "United States"
    ]

    private static let canonicalCountryLookup: [String: String] = {
        let englishLocale = Locale(identifier: "en_US")
        let swedishLocale = Locale(identifier: "sv_SE")
        var lookup: [String: String] = [:]
        for region in countryRegions {
            guard let englishName = englishLocale.localizedString(forRegionCode: region.identifier) else { continue }
            lookup[normalizedCountryLookupKey(region.identifier)] = englishName
            lookup[normalizedCountryLookupKey(englishName)] = englishName
            if let swedishName = swedishLocale.localizedString(forRegionCode: region.identifier) {
                lookup[normalizedCountryLookupKey(swedishName)] = englishName
            }
        }
        for (alias, canonical) in countryAliases {
            lookup[alias] = canonical
        }
        return lookup
    }()

    private static func normalizedCountryLookupKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canonicalCountryName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        return canonicalCountryLookup[normalizedCountryLookupKey(trimmed)] ?? trimmed
    }

    static func numericValue(from raw: String?) -> Double? {
        guard let cleaned = raw?.replacingOccurrences(of: "\u{a0}", with: " ")
            .replacingOccurrences(of: "kr", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "SEK", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "%", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " ", with: "")
            .trimmedOrNil
        else {
            return nil
        }

        guard cleaned.range(of: #"^-?\d+([.,]\d+)?$"#, options: .regularExpression) != nil else {
            return nil
        }

        // A pasted account or reference number (20 digits or more) is not an
        // amount; turning it into a whole number made the app crash.
        guard let value = Double(cleaned.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, abs(value) < 1e15 else {
            return nil
        }
        return value
    }

    static func timestampNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    /// The largest number written in a free-text field ("2-3" gives 3,
    /// "1,5" gives 1.5). Nil when there is none. Used for "Antal år", where
    /// removing every non-digit used to turn "2-3" into 23.
    static func largestNumber(in raw: String?) -> Double? {
        guard let raw, let regex = try? NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?"#) else { return nil }
        let nsRaw = raw as NSString
        return regex.matches(in: raw, range: NSRange(location: 0, length: nsRaw.length))
            .compactMap { Double(nsRaw.substring(with: $0.range).replacingOccurrences(of: ",", with: ".")) }
            .max()
    }

    static func formatAmountInput(_ raw: String?) -> String? {
        guard let raw = raw?.trimmedOrNil else { return nil }
        let wholeUnits: Double
        if let parsed = parsedAmount(raw) {
            // Öre are dropped as before; the small margin keeps "1,15 M"
            // from becoming 1 149 999 through rounding in the multiplication.
            wholeUnits = (parsed + 0.001).rounded(.down)
        } else {
            // Unusual text ("ca 500 000"): keep the digits as before.
            let digits = raw.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            guard !digits.isEmpty else { return nil }
            return groupedDigits(digits)
        }
        guard wholeUnits.isFinite, wholeUnits >= 0, wholeUnits < 1e15 else { return nil }
        return groupedDigits(String(Int64(wholeUnits)))
    }

    /// Reads amounts such as "1 250 000", "1 250 000,50 kr", "1.5 M",
    /// "1,5 milj", "250 tkr" or "€ 40,000". Nil when the text is not a
    /// plain amount. Öre are kept as decimals; the caller drops them.
    static func parsedAmount(_ raw: String) -> Double? {
        var text = raw
            .replacingOccurrences(of: "\u{a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currencyPattern = #"(kr\.?|:-|sek|eur|usd|nok|dkk|gbp|€|\$|£)"#
        func stripCurrency() {
            text = text
                // Not after a letter, so "tkr" and "msek" keep their multiplier.
                .replacingOccurrences(of: #"\s*(?<![a-zåäö])"# + currencyPattern + #"\s*$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\s*"# + currencyPattern + #"\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        stripCurrency()
        var multiplier = 1.0
        let multipliers: [(pattern: String, factor: Double)] = [
            (#"(mkr|msek|meur|musd|miljoner|miljon|milj\.?|mn|millions?|m)"#, 1_000_000),
            (#"(tkr|tsek|ksek|keur|kusd|tusen|k)"#, 1_000),
        ]
        for candidate in multipliers {
            if let range = text.range(of: #"(?<=\d)\s*"# + candidate.pattern + #"$"#, options: .regularExpression) {
                text.removeSubrange(range)
                multiplier = candidate.factor
                break
            }
        }
        stripCurrency()
        let number = text.replacingOccurrences(of: " ", with: "")
        guard number.range(of: #"^\d[\d.,]*$"#, options: .regularExpression) != nil else { return nil }

        var integerPart = number
        var fractionPart = ""
        if let separator = number.lastIndex(where: { $0 == "," || $0 == "." }) {
            let tail = String(number[number.index(after: separator)...])
            let separatorCount = number.filter { $0 == "," || $0 == "." }.count
            // "1,5 M" and "1 250,50" have a decimal part; "1.250.000" and
            // "40,000" only group thousands.
            let isDecimal = !tail.isEmpty && (
                (multiplier > 1 && separatorCount == 1)
                    || tail.count <= 2
                    || (tail.count != 3 && separatorCount == 1)
            )
            if isDecimal {
                integerPart = String(number[..<separator])
                fractionPart = tail
            }
        }
        let integerDigits = integerPart.filter(\.isNumber)
        guard !integerDigits.isEmpty,
              let value = Double(integerDigits + "." + (fractionPart.isEmpty ? "0" : fractionPart))
        else { return nil }
        return value * multiplier
    }

    private static func groupedDigits(_ digits: String) -> String {
        var current = String(digits.drop(while: { $0 == "0" }))
        if current.isEmpty { current = "0" }
        var parts: [String] = []
        while current.count > 3 {
            parts.insert(String(current.suffix(3)), at: 0)
            current.removeLast(3)
        }
        parts.insert(current, at: 0)
        return parts.joined(separator: " ")
    }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case swedish = "sv"

    var id: String { rawValue }

    func text(_ english: String, _ swedish: String) -> String {
        switch self {
        case .english:
            return english
        case .swedish:
            return swedish
        }
    }

    var displayName: String {
        text("English", "Svenska")
    }

    func localizedSalarySourceCategory(_ category: SalarySourceCategory) -> String {
        switch category {
        case .clinic:
            return fixedDropdownText("salarySource.clinic", language: self, english: "Clinic", swedish: "Klinik")
        case .teaching:
            return fixedDropdownText("salarySource.teaching", language: self, english: "Teaching", swedish: "Undervisning")
        case .research:
            return fixedDropdownText("salarySource.research", language: self, english: "Research", swedish: "Forskning")
        case .other:
            return fixedDropdownText("salarySource.other", language: self, english: "Other", swedish: "Övrigt")
        }
    }

    var appName: String {
        AppRuntime.displayName
    }

    func localizedStatus(_ value: String) -> String {
        switch value {
        case "Att söka":
            return fixedDropdownText("applicationStatus.toApply", language: self, english: "To apply", swedish: "Att söka")
        case "Väntar svar":
            return fixedDropdownText("applicationStatus.awaitingResponse", language: self, english: "Awaiting decision", swedish: "Väntar svar")
        case "Beviljat":
            return fixedDropdownText("applicationStatus.awarded", language: self, english: "Granted", swedish: "Beviljat")
        case "Avslag":
            return fixedDropdownText("applicationStatus.declined", language: self, english: "Declined", swedish: "Avslag")
        case "Tillbakadragen":
            return fixedDropdownText("applicationStatus.withdrawn", language: self, english: "Withdrawn", swedish: "Tillbakadragen")
        case "Ej sökt":
            return fixedDropdownText("applicationStatus.notApplied", language: self, english: "Not applied", swedish: "Ej sökt")
        case "Unknown":
            return fixedDropdownText("applicationStatus.unknown", language: self, english: "Unknown", swedish: "Okänd")
        default:
            return value
        }
    }

    func localizedGrantCategory(_ value: String) -> String {
        switch value {
        case "National":
            return fixedDropdownText("grantCategory.national", language: self, english: "National", swedish: "Nationell")
        case "Regional":
            return fixedDropdownText("grantCategory.regional", language: self, english: "Regional", swedish: "Regional")
        case "Local":
            return fixedDropdownText("grantCategory.local", language: self, english: "Local", swedish: "Lokal")
        case "International":
            return fixedDropdownText("grantCategory.international", language: self, english: "International", swedish: "Internationellt")
        default:
            return value
        }
    }

    func localizedCountry(_ canonicalEnglishName: String) -> String {
        let normalized = GrantParsing.canonicalCountryName(canonicalEnglishName)
        guard !normalized.isEmpty else { return canonicalEnglishName }

        if normalized.caseInsensitiveCompare("International") == .orderedSame {
            return self == .swedish ? "Internationell" : "International"
        }
        if normalized.caseInsensitiveCompare("Somaliland") == .orderedSame {
            return "Somaliland"
        }

        let aliases: [String: String] = [
            "UK": "United Kingdom",
            "U.K.": "United Kingdom",
            "USA": "United States",
            "U.S.A.": "United States",
            "Sverige": "Sweden",
        ]
        let canonical = aliases[normalized] ?? normalized
        let locale = Locale(identifier: self == .swedish ? "sv_SE" : "en_US")

        if let regionCode = GrantParsing.countryRegionCodeByCanonicalName[GrantParsing.canonicalCountryName(canonical)],
           let localized = locale.localizedString(forRegionCode: regionCode) {
            return localized
        }

        return canonical
    }
}

enum AppVisualMode: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case lightClean
    case darkClean
    case darkNew

    var id: String { rawValue }

    var usesDarkAppearance: Bool {
        switch self {
        case .dark, .darkClean, .darkNew:
            return true
        case .light, .lightClean:
            return false
        }
    }

    var isClean: Bool {
        switch self {
        case .lightClean, .darkClean, .darkNew:
            return true
        case .light, .dark:
            return false
        }
    }

    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .light:
            return language.text("Light mode", "Ljust läge")
        case .dark:
            return language.text("Dark mode", "Mörkt läge")
        case .lightClean:
            return language.text("Light mode", "Ljust läge")
        case .darkClean:
            return language.text("Dark mode legacy", "Mörkt läge äldre")
        case .darkNew:
            return language.text("Dark mode", "Mörkt läge")
        }
    }
}

enum AppChromeScheme: String, Codable, CaseIterable, Identifiable {
    case standard
    case contrast

    var id: String { rawValue }

    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .standard:
            return language.text("Standard", "Standard")
        case .contrast:
            return language.text("Contrast", "Kontrast")
        }
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        self?.trimmedOrNil
    }
}

extension String {
    var nonEmpty: String? {
        trimmedOrNil
    }

    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

extension Dictionary {
    /// Like `init(uniqueKeysWithValues:)` but keeps the first value when a
    /// key repeats instead of stopping the app. Saved data can contain two
    /// records with the same name or id (imports, old versions), and a
    /// crash there would make the app impossible to open.
    init<S: Sequence>(firstWinsKeysWithValues pairs: S) where S.Element == (Key, Value) {
        self.init(pairs, uniquingKeysWith: { first, _ in first })
    }
}
