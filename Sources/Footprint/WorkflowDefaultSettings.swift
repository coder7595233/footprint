import Foundation

/// User-editable defaults for new applications, teaching and exports.
///
/// Every field is optional. `nil` always means "the built-in value", so data
/// saved before these settings existed decodes unchanged, and nothing in the
/// app changes until the user edits a value in Settings.
struct WorkflowDefaultSettings: Codable, Hashable {
    // MARK: New applications
    var newApplicationOpensAfterMonths: Int?
    var newApplicationClosesAfterMonths: Int?
    var newApplicationCurrency: String?
    var newApplicationStatus: String?
    var currencyOptions: [String]?
    var amountBucketLowerLimit: Double?
    var amountBucketUpperLimit: Double?

    // MARK: Teaching
    var defaultTeachingProgramSv: String?
    var defaultTeachingProgramEn: String?
    /// No longer shown in Settings (round 7, user decision): each course now has
    /// the checkbox "Klinisk undervisning". Still read so saved settings load, and
    /// used once by the migration that ticks the checkbox for the courses the
    /// old word rule placed under clinical teaching.
    var clinicalTeachingOrganizationWords: [String]?
    var teachingTermWordSv: String?
    var teachingTermWordEn: String?

    // MARK: Teaching merits export
    /// The contact e-mail that earlier versions stored here was removed (the
    /// application is sent through a web form). An old stored value is simply
    /// ignored when the settings are read.
    var teachingMeritsFacultyName: String?
    var principalSupervisionMonths: Int?
    var principalSupervisionHours: Double?
    var principalSupervisionMaxHours: Double?
    var assistantSupervisionMonths: Int?
    var assistantSupervisionHours: Double?
    var assistantSupervisionMaxHours: Double?

    // MARK: Statement templates
    var fundingStatementTemplateEn: String?
    var fundingStatementTemplateSv: String?
    var ethicsHelsinkiTemplateEn: String?
    var ethicsHelsinkiTemplateSv: String?
    var ethicsApprovalTemplateEn: String?
    var ethicsApprovalTemplateSv: String?
    var ethicsTrialTemplateEn: String?
    var ethicsTrialTemplateSv: String?

    init() {}

    static let builtIn = WorkflowDefaultSettings()

    // MARK: Built-in values (today's behaviour)

    static let defaultOpensAfterMonths = 1
    static let defaultClosesAfterMonths = 3
    static let defaultCurrency = "SEK"
    static let defaultStatus = "Att söka"
    /// "Väntar svar" is left out: without an application date the app shows such
    /// an application as "Att söka" anyway, because the status follows the dates.
    static let selectableStatusOptions = GrantParsing.statusOptions.filter { $0 != "Väntar svar" }
    static let defaultCurrencyOptions = GrantParsing.currencyOptions
    static let defaultAmountBucketLowerLimit: Double = 250_000
    static let defaultAmountBucketUpperLimit: Double = 1_000_000
    /// Neutral names; the user's own programme is stored in the settings.
    static let defaultTeachingProgramSv = "Programmet"
    static let defaultTeachingProgramEn = "The programme"
    static let defaultClinicalTeachingOrganizationWords = ["region"]
    static let defaultTeachingTermWordSv = "Termin"
    static let defaultTeachingTermWordEn = "Semester"
    /// Empty: the heading then names no faculty. The user's own faculty is
    /// stored in the settings.
    static let defaultTeachingMeritsFacultyName = ""
    static let defaultPrincipalSupervisionMonths = 6
    static let defaultPrincipalSupervisionHours: Double = 40
    static let defaultPrincipalSupervisionMaxHours: Double = 320
    static let defaultAssistantSupervisionMonths = 12
    static let defaultAssistantSupervisionHours: Double = 40
    static let defaultAssistantSupervisionMaxHours: Double = 160
    static let defaultFundingStatementTemplateEn = "The study was funded by {funders}."
    static let defaultFundingStatementTemplateSv = "Studien finansierades av {funders}."
    static let defaultEthicsHelsinkiTemplateEn = "The study complied with the declaration of Helsinki."
    static let defaultEthicsHelsinkiTemplateSv = "Studien följde Helsingforsdeklarationen."
    static let defaultEthicsApprovalTemplateEn = "The study complied with the declaration of Helsinki and was approved by the Swedish Ethical Review Authority (Dnr {dnr}). All participants gave written, informed consent prior to participation."
    static let defaultEthicsApprovalTemplateSv = "Studien följde Helsingforsdeklarationen och godkändes av Etikprövningsmyndigheten (Dnr {dnr}). Samtliga deltagare lämnade skriftligt informerat samtycke före deltagande."
    static let defaultEthicsTrialTemplateEn = "Prior to commencement, the study was registered at ClinicalTrials.gov (registration number {trial})."
    static let defaultEthicsTrialTemplateSv = "Före studiestart registrerades studien på ClinicalTrials.gov (registreringsnummer {trial})."

    // MARK: Resolved values

    var resolvedOpensAfterMonths: Int {
        Self.clampedMonths(newApplicationOpensAfterMonths) ?? Self.defaultOpensAfterMonths
    }

    var resolvedClosesAfterMonths: Int {
        Self.clampedMonths(newApplicationClosesAfterMonths) ?? Self.defaultClosesAfterMonths
    }

    var resolvedCurrency: String {
        Self.normalizedCurrencyCode(newApplicationCurrency) ?? Self.defaultCurrency
    }

    var resolvedStatus: String {
        guard let status = newApplicationStatus?.trimmedOrNil,
              Self.selectableStatusOptions.contains(status) else {
            return Self.defaultStatus
        }
        return status
    }

    var resolvedCurrencyOptions: [String] {
        let custom = Self.normalizedCurrencyList(currencyOptions)
        return custom.isEmpty ? Self.defaultCurrencyOptions : custom
    }

    /// The currency list offered in the application editor: the saved list, plus
    /// the default currency and the application's own value when those are missing
    /// from it, so an existing value is never hidden.
    func currencyPickerOptions(including current: String?) -> [String] {
        var options = resolvedCurrencyOptions
        for extra in [resolvedCurrency, Self.normalizedCurrencyCode(current)].compactMap({ $0 })
            where !options.contains(extra) {
            options.append(extra)
        }
        return options
    }

    var resolvedAmountBucketLowerLimit: Double {
        guard let value = amountBucketLowerLimit, value.isFinite, value > 0 else {
            return Self.defaultAmountBucketLowerLimit
        }
        return value
    }

    var resolvedAmountBucketUpperLimit: Double {
        let lower = resolvedAmountBucketLowerLimit
        guard let value = amountBucketUpperLimit, value.isFinite, value > lower else {
            return max(Self.defaultAmountBucketUpperLimit, lower)
        }
        return value
    }

    var resolvedDefaultTeachingProgramSv: String {
        defaultTeachingProgramSv?.trimmedOrNil ?? Self.defaultTeachingProgramSv
    }

    var resolvedDefaultTeachingProgramEn: String {
        defaultTeachingProgramEn?.trimmedOrNil ?? Self.defaultTeachingProgramEn
    }

    var resolvedClinicalTeachingOrganizationWords: [String] {
        guard let words = clinicalTeachingOrganizationWords else {
            return Self.defaultClinicalTeachingOrganizationWords
        }
        return Self.normalizedWordList(words)
    }

    var resolvedTeachingTermWordSv: String {
        teachingTermWordSv?.trimmedOrNil ?? Self.defaultTeachingTermWordSv
    }

    var resolvedTeachingTermWordEn: String {
        teachingTermWordEn?.trimmedOrNil ?? Self.defaultTeachingTermWordEn
    }

    var resolvedTeachingMeritsFacultyName: String {
        teachingMeritsFacultyName?.trimmedOrNil ?? Self.defaultTeachingMeritsFacultyName
    }

    var resolvedPrincipalSupervisionMonths: Int {
        Self.positiveMonths(principalSupervisionMonths) ?? Self.defaultPrincipalSupervisionMonths
    }

    var resolvedPrincipalSupervisionHours: Double {
        Self.positiveHours(principalSupervisionHours) ?? Self.defaultPrincipalSupervisionHours
    }

    var resolvedPrincipalSupervisionMaxHours: Double {
        Self.positiveHours(principalSupervisionMaxHours) ?? Self.defaultPrincipalSupervisionMaxHours
    }

    var resolvedAssistantSupervisionMonths: Int {
        Self.positiveMonths(assistantSupervisionMonths) ?? Self.defaultAssistantSupervisionMonths
    }

    var resolvedAssistantSupervisionHours: Double {
        Self.positiveHours(assistantSupervisionHours) ?? Self.defaultAssistantSupervisionHours
    }

    var resolvedAssistantSupervisionMaxHours: Double {
        Self.positiveHours(assistantSupervisionMaxHours) ?? Self.defaultAssistantSupervisionMaxHours
    }

    func resolvedFundingStatementTemplate(english: Bool) -> String {
        english
            ? (fundingStatementTemplateEn?.trimmedOrNil ?? Self.defaultFundingStatementTemplateEn)
            : (fundingStatementTemplateSv?.trimmedOrNil ?? Self.defaultFundingStatementTemplateSv)
    }

    func resolvedEthicsHelsinkiTemplate(english: Bool) -> String {
        english
            ? (ethicsHelsinkiTemplateEn?.trimmedOrNil ?? Self.defaultEthicsHelsinkiTemplateEn)
            : (ethicsHelsinkiTemplateSv?.trimmedOrNil ?? Self.defaultEthicsHelsinkiTemplateSv)
    }

    func resolvedEthicsApprovalTemplate(english: Bool) -> String {
        english
            ? (ethicsApprovalTemplateEn?.trimmedOrNil ?? Self.defaultEthicsApprovalTemplateEn)
            : (ethicsApprovalTemplateSv?.trimmedOrNil ?? Self.defaultEthicsApprovalTemplateSv)
    }

    func resolvedEthicsTrialTemplate(english: Bool) -> String {
        english
            ? (ethicsTrialTemplateEn?.trimmedOrNil ?? Self.defaultEthicsTrialTemplateEn)
            : (ethicsTrialTemplateSv?.trimmedOrNil ?? Self.defaultEthicsTrialTemplateSv)
    }

    // MARK: Text builders

    /// "The study was funded by A and B." with the user's template.
    func fundingStatement(fundersText: String, english: Bool) -> String {
        resolvedFundingStatementTemplate(english: english)
            .replacingOccurrences(of: "{funders}", with: fundersText)
    }

    /// The ethics statement: the Helsinki sentence when no approval is known,
    /// otherwise the approval sentence, followed by the trial sentence when a
    /// ClinicalTrials.gov number exists.
    func ethicsStatement(caseNumbers: [String], trialIDs: [String], english: Bool) -> String {
        var parts: [String] = []
        if caseNumbers.isEmpty {
            parts.append(resolvedEthicsHelsinkiTemplate(english: english))
        } else {
            parts.append(
                resolvedEthicsApprovalTemplate(english: english)
                    .replacingOccurrences(of: "{dnr}", with: caseNumbers.joined(separator: ", "))
            )
        }
        if !caseNumbers.isEmpty, !trialIDs.isEmpty {
            parts.append(
                resolvedEthicsTrialTemplate(english: english)
                    .replacingOccurrences(of: "{trial}", with: trialIDs.joined(separator: ", "))
            )
        }
        return parts.compactMap(\.trimmedOrNil).joined(separator: " ")
    }

    /// The table heading for doctoral supervision in the teaching merits export.
    func doctoralSupervisionTitle(principal: Bool) -> String {
        let role = principal ? "huvudhandledare" : "bihandledare"
        let months = principal ? resolvedPrincipalSupervisionMonths : resolvedAssistantSupervisionMonths
        let hours = principal ? resolvedPrincipalSupervisionHours : resolvedAssistantSupervisionHours
        let maximum = principal ? resolvedPrincipalSupervisionMaxHours : resolvedAssistantSupervisionMaxHours
        return "Handledning av studerande på forskarnivå - \(role) (\(months) månader på heltid (100%) motsvarar \(Self.hoursText(hours)) timmar; max \(Self.hoursText(maximum)) timmar/doktorand kan redovisas)"
    }

    /// Fills an English term from a Swedish one ("Termin 6" becomes "Semester 6").
    /// Returns nil when the Swedish term does not start with the Swedish word.
    func translatedTeachingTerm(fromSwedish swedishTerm: String) -> String? {
        let trimmed = swedishTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = resolvedTeachingTermWordSv + " "
        guard trimmed.hasPrefix(prefix) else { return nil }
        guard let suffix = String(trimmed.dropFirst(prefix.count)).trimmedOrNil else { return nil }
        return "\(resolvedTeachingTermWordEn) \(suffix)"
    }

    /// True when the institution name contains one of the clinical-teaching words.
    /// Only used by the one-time round 7 migration to the course checkbox.
    func institutionIndicatesClinicalTeaching(_ institution: String) -> Bool {
        let normalizedInstitution = Self.folded(institution)
        guard !normalizedInstitution.isEmpty else { return false }
        return resolvedClinicalTeachingOrganizationWords.contains { word in
            normalizedInstitution.contains(Self.folded(word))
        }
    }

    // MARK: Amount buckets

    func amountBucket(for amount: Double) -> ApplicationAmountBucket {
        if amount < resolvedAmountBucketLowerLimit {
            return .below
        }
        if amount < resolvedAmountBucketUpperLimit {
            return .between
        }
        return .above
    }

    func amountBucketLabel(_ bucket: ApplicationAmountBucket) -> String {
        let lower = Self.amountLimitText(resolvedAmountBucketLowerLimit)
        let upper = Self.amountLimitText(resolvedAmountBucketUpperLimit)
        switch bucket {
        case .below:
            return "<\(lower)"
        case .between:
            return "\(lower) - \(upper)"
        case .above:
            return "≥\(upper)"
        }
    }

    // MARK: Normalization

    /// Trims values and drops everything that equals the built-in value, so the
    /// stored settings only hold what the user actually changed.
    func normalized() -> WorkflowDefaultSettings {
        var copy = self
        copy.newApplicationOpensAfterMonths = Self.nonDefault(Self.clampedMonths(newApplicationOpensAfterMonths), Self.defaultOpensAfterMonths)
        copy.newApplicationClosesAfterMonths = Self.nonDefault(Self.clampedMonths(newApplicationClosesAfterMonths), Self.defaultClosesAfterMonths)
        let currency = resolvedCurrency
        copy.newApplicationCurrency = currency == Self.defaultCurrency ? nil : currency
        let status = resolvedStatus
        copy.newApplicationStatus = status == Self.defaultStatus ? nil : status
        let currencies = Self.normalizedCurrencyList(currencyOptions)
        copy.currencyOptions = currencies.isEmpty || currencies == Self.defaultCurrencyOptions ? nil : currencies
        copy.amountBucketLowerLimit = Self.nonDefault(Self.positiveHours(amountBucketLowerLimit), Self.defaultAmountBucketLowerLimit)
        copy.amountBucketUpperLimit = Self.nonDefault(Self.positiveHours(amountBucketUpperLimit), Self.defaultAmountBucketUpperLimit)
        copy.defaultTeachingProgramSv = Self.customText(defaultTeachingProgramSv, default: Self.defaultTeachingProgramSv)
        copy.defaultTeachingProgramEn = Self.customText(defaultTeachingProgramEn, default: Self.defaultTeachingProgramEn)
        if let words = clinicalTeachingOrganizationWords {
            let normalizedWords = Self.normalizedWordList(words)
            copy.clinicalTeachingOrganizationWords = normalizedWords == Self.defaultClinicalTeachingOrganizationWords ? nil : normalizedWords
        }
        copy.teachingTermWordSv = Self.customText(teachingTermWordSv, default: Self.defaultTeachingTermWordSv)
        copy.teachingTermWordEn = Self.customText(teachingTermWordEn, default: Self.defaultTeachingTermWordEn)
        copy.teachingMeritsFacultyName = Self.customText(teachingMeritsFacultyName, default: Self.defaultTeachingMeritsFacultyName)
        copy.principalSupervisionMonths = Self.nonDefault(Self.positiveMonths(principalSupervisionMonths), Self.defaultPrincipalSupervisionMonths)
        copy.principalSupervisionHours = Self.nonDefault(Self.positiveHours(principalSupervisionHours), Self.defaultPrincipalSupervisionHours)
        copy.principalSupervisionMaxHours = Self.nonDefault(Self.positiveHours(principalSupervisionMaxHours), Self.defaultPrincipalSupervisionMaxHours)
        copy.assistantSupervisionMonths = Self.nonDefault(Self.positiveMonths(assistantSupervisionMonths), Self.defaultAssistantSupervisionMonths)
        copy.assistantSupervisionHours = Self.nonDefault(Self.positiveHours(assistantSupervisionHours), Self.defaultAssistantSupervisionHours)
        copy.assistantSupervisionMaxHours = Self.nonDefault(Self.positiveHours(assistantSupervisionMaxHours), Self.defaultAssistantSupervisionMaxHours)
        copy.fundingStatementTemplateEn = Self.customText(fundingStatementTemplateEn, default: Self.defaultFundingStatementTemplateEn)
        copy.fundingStatementTemplateSv = Self.customText(fundingStatementTemplateSv, default: Self.defaultFundingStatementTemplateSv)
        copy.ethicsHelsinkiTemplateEn = Self.customText(ethicsHelsinkiTemplateEn, default: Self.defaultEthicsHelsinkiTemplateEn)
        copy.ethicsHelsinkiTemplateSv = Self.customText(ethicsHelsinkiTemplateSv, default: Self.defaultEthicsHelsinkiTemplateSv)
        copy.ethicsApprovalTemplateEn = Self.customText(ethicsApprovalTemplateEn, default: Self.defaultEthicsApprovalTemplateEn)
        copy.ethicsApprovalTemplateSv = Self.customText(ethicsApprovalTemplateSv, default: Self.defaultEthicsApprovalTemplateSv)
        copy.ethicsTrialTemplateEn = Self.customText(ethicsTrialTemplateEn, default: Self.defaultEthicsTrialTemplateEn)
        copy.ethicsTrialTemplateSv = Self.customText(ethicsTrialTemplateSv, default: Self.defaultEthicsTrialTemplateSv)
        return copy
    }

    var isBuiltIn: Bool {
        normalized() == .builtIn
    }

    // MARK: Helpers

    static func normalizedCurrencyCode(_ value: String?) -> String? {
        value?.trimmedOrNil?.uppercased()
    }

    static func normalizedCurrencyList(_ values: [String]?) -> [String] {
        (values ?? []).compactMap { normalizedCurrencyCode($0) }.uniqued()
    }

    /// Splits "SEK, EUR; USD" or one code per line into a list.
    static func currencyList(fromText text: String) -> [String] {
        normalizedCurrencyList(text.components(separatedBy: CharacterSet(charactersIn: ",;\n ")))
    }

    static func wordList(fromText text: String) -> [String] {
        normalizedWordList(text.components(separatedBy: CharacterSet(charactersIn: ",;\n")))
    }

    static func normalizedWordList(_ values: [String]) -> [String] {
        values.compactMap(\.trimmedOrNil).uniqued()
    }

    private static func customText(_ value: String?, default defaultValue: String) -> String? {
        guard let trimmed = value?.trimmedOrNil, trimmed != defaultValue else { return nil }
        return trimmed
    }

    private static func nonDefault<Value: Equatable>(_ value: Value?, _ defaultValue: Value) -> Value? {
        guard let value, value != defaultValue else { return nil }
        return value
    }

    private static func clampedMonths(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), 120) }
    }

    private static func positiveMonths(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return min(value, 120)
    }

    private static func positiveHours(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func folded(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    static func hoursText(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    /// 250 000 becomes "250 k" and 1 000 000 becomes "1 mil".
    static func amountLimitText(_ value: Double) -> String {
        if value >= 1_000_000 {
            return compactNumberText(value / 1_000_000) + " mil"
        }
        if value >= 1_000 {
            return compactNumberText(value / 1_000) + " k"
        }
        return compactNumberText(value)
    }

    private static func compactNumberText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }
}

enum ApplicationAmountBucket: Hashable, CaseIterable {
    case below
    case between
    case above
}

/// The current settings for code that has no access to the data store (model
/// helpers such as teaching programme fallbacks and amount buckets). Updated
/// whenever the store's metadata changes, like `FixedDropdownTranslationRegistry`.
final class WorkflowDefaultSettingsRegistry {
    nonisolated(unsafe) private static var storedSettings: WorkflowDefaultSettings = .builtIn

    static var current: WorkflowDefaultSettings {
        storedSettings
    }

    static func update(from metadata: DataSourceMetadata) {
        storedSettings = metadata.workflowDefaults ?? .builtIn
    }

    static func replace(with settings: WorkflowDefaultSettings) {
        storedSettings = settings
    }
}

extension GrantApplication {
    var amountBucket: ApplicationAmountBucket {
        WorkflowDefaultSettingsRegistry.current.amountBucket(for: preferredBudgetAmountValue ?? 0)
    }
}

extension GrantDataStore {
    var workflowDefaultSettings: WorkflowDefaultSettings {
        metadata.workflowDefaults ?? .builtIn
    }

    func autosaveWorkflowDefaultSettings(_ settings: WorkflowDefaultSettings) {
        let normalized = settings.normalized()
        var updated = editableMetadataSnapshot
        updated.workflowDefaults = normalized.isBuiltIn ? nil : normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit default values", "Redigera standardvärden")
        )
    }
}
