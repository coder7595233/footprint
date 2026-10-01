import Foundation

struct PublicationAMAItem: Codable, Hashable {
    let authors: String
    let title: String
    let journal: String
    let tail: String
    let note: String
    let plain: String
    var sourceID: String? = nil
}

struct PublicationAMASection: Codable {
    let title: String
    let items: [PublicationAMAItem]
}

struct PublicationAMAExportDocument: Codable {
    let title: String
    let highlightName: String
    let underlinedNames: [String]
    let sections: [PublicationAMASection]
    let headerText: String
    let footerText: String
    let includePageNumbers: Bool
}

enum PublicationCitationFormatting {
    private static let terminalPunctuation: Set<Character> = [".", "?", "!"]
    private static let trailingClosers: Set<Character> = ["\"", "'", ")", "]", "}"]

    static func separator(after segment: String) -> String {
        hasTerminalPunctuation(segment) ? " " : ". "
    }

    static func joinedSegments(_ segments: [String]) -> String {
        let cleaned = segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard var result = cleaned.first else { return "" }
        var previous = result

        for segment in cleaned.dropFirst() {
            result += separator(after: previous)
            result += segment
            previous = segment
        }

        return result
    }

    static func terminated(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return hasTerminalPunctuation(trimmed) ? trimmed : trimmed + "."
    }

    static func hasTerminalPunctuation(_ text: String) -> Bool {
        var characters = text.trimmingCharacters(in: .whitespacesAndNewlines).reversed().makeIterator()
        while let character = characters.next() {
            if trailingClosers.contains(character) {
                continue
            }
            return terminalPunctuation.contains(character)
        }
        return false
    }
}

struct TeachingMeritsExportTable: Codable {
    let title: String
    let headers: [String]
    let rows: [[String]]
    let sumLabel: String
    let sumValue: String
}

struct TeachingMeritsExportGroup: Codable {
    let title: String
    let tables: [TeachingMeritsExportTable]
}

struct TeachingMeritsExportDocument: Codable {
    let title: String
    let groups: [TeachingMeritsExportGroup]
    let summaryHeaders: [String]
    let summaryRows: [[String]]
    /// Shown in the heading ("... vid <faculty>"); nil or empty leaves the
    /// faculty out of the heading.
    var facultyName: String? = nil
}

struct PublicationJournalRowSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let categories: [String]
    let categorySet: Set<String>
    let filterSearchBlob: String
    let normalizedFilterSearchBlob: String
    let extendedFilterSearchBlob: String
    let normalizedExtendedFilterSearchBlob: String
    let latestImpactFactorValue: Double
    let latestNorwegianLevelValue: Double
    let hasPreviousSubmission: Bool
    let hasPreviousPublication: Bool
    let jifMetric: PublicationMetricValue?
    let norwegianMetric: PublicationMetricValue?
    let acceptanceText: String
    let acceptanceSortValue: Double

    static func == (lhs: PublicationJournalRowSnapshot, rhs: PublicationJournalRowSnapshot) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.subtitle == rhs.subtitle &&
        lhs.categories == rhs.categories &&
        lhs.filterSearchBlob == rhs.filterSearchBlob &&
        lhs.normalizedFilterSearchBlob == rhs.normalizedFilterSearchBlob &&
        lhs.extendedFilterSearchBlob == rhs.extendedFilterSearchBlob &&
        lhs.normalizedExtendedFilterSearchBlob == rhs.normalizedExtendedFilterSearchBlob &&
        lhs.latestImpactFactorValue == rhs.latestImpactFactorValue &&
        lhs.latestNorwegianLevelValue == rhs.latestNorwegianLevelValue &&
        lhs.hasPreviousSubmission == rhs.hasPreviousSubmission &&
        lhs.hasPreviousPublication == rhs.hasPreviousPublication &&
        lhs.jifMetric?.value == rhs.jifMetric?.value &&
        lhs.jifMetric?.quartile == rhs.jifMetric?.quartile &&
        lhs.jifMetric?.kind == rhs.jifMetric?.kind &&
        lhs.norwegianMetric?.value == rhs.norwegianMetric?.value &&
        lhs.norwegianMetric?.quartile == rhs.norwegianMetric?.quartile &&
        lhs.norwegianMetric?.kind == rhs.norwegianMetric?.kind &&
        lhs.acceptanceText == rhs.acceptanceText &&
        lhs.acceptanceSortValue == rhs.acceptanceSortValue
    }
}

struct ApplicationRowSnapshot: Identifiable, Equatable {
    let id: String
    let selectionID: String
    let organizationLabel: String
    let grantNameLabel: String
    let closesText: String
    let closeDate: Date?
    let closesOnUncertain: Bool
    let projectLabel: String
    /// F13b: the linked project's id and the written project name, used by
    /// the "by project" filter (id first, name only when there is no id).
    let projectID: String?
    let projectName: String?
    let appliedCaseNumber: String
    let maximumAmountText: String
    let resultLabel: String
    let isGranted: Bool
    let isFullySpent: Bool
    let isToApplyStatus: Bool
    let isBeforeOpening: Bool
    let isCurrentUserFirstApplicant: Bool
    /// Round 17: nil when the application has no year (it is no longer placed
    /// in the current year; see YearlessRecordRule).
    let applicationYear: Int?
    let budgetAmount: Double
    let sortOrganization: String
    let sortGrantName: String
    let sortClosesOn: String
    let sortProject: String
    let sortAppliedCaseNumber: String
    let sortMaximumAmount: Double
    let normalizedSearchBlob: String
    /// Round 16: shows a small lock on locked rows.
    var isEditingLocked: Bool = false
}

/// F13b: the grants list's "by project" filter. The menu lists projects by
/// their Swedish name; an application is matched by its project id, and by
/// its written project name only when it has no id that names a project.
/// This keeps the filter working when the list shows English project names.
struct ApplicationProjectFilter: Equatable {
    let selectedNames: Set<String>
    let selectedProjectIDs: Set<String>
    let knownProjectIDs: Set<String>

    func matches(projectID: String?, projectName: String?) -> Bool {
        guard !selectedNames.isEmpty else { return true }
        if let projectID = projectID?.trimmedOrNil, knownProjectIDs.contains(projectID) {
            return selectedProjectIDs.contains(projectID)
        }
        guard let projectName = projectName?.trimmedOrNil else { return false }
        return selectedNames.contains(projectName)
    }
}

struct PublicationAuthorRowSnapshot: Identifiable, Equatable {
    let id: String
    let sortName: String
    let sortOrganization: String
    let displayName: String
    let displaySubtitle: String
    let primaryOrganization: String
    let affiliationOrganizations: [String]
    let primaryCountry: String
    let countryFlags: [String]
    let isCurrentUser: Bool
    let projectCount: Int
    let grantCount: Int
    let publicationCount: Int
    let disseminationCount: Int
    let expertAssignmentCount: Int
    let teachingCount: Int
    let normalizedSearchBlob: String
    let missingORCID: Bool
    let missingEmail: Bool
    let missingPrimaryOrganization: Bool
    let missingPrimaryCountry: Bool
    let missingTitle: Bool
    /// Round 17: the researcher list's organization filter keys (organization
    /// id when the affiliation is linked, otherwise the written name).
    var affiliationOrganizationKeys: [String] = []
}

struct ProjectRowSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    let sortTitle: String
    let leaderName: String
    let sortLeaderName: String
    let collaboratorNames: [String]
    let collaboratorFlags: [String]
    let applicationCount: Int
    let grantedAmount: Double
    let hasRemainingGrantedFunds: Bool
    let publishedPublicationCount: Int
    let status: ProjectLifecycleStatus
    let hasDataCollection: Bool
    let hasActiveTasks: Bool
    let isLedByCurrentUser: Bool
    /// Round 16: the shared project status tone and the lock flag.
    var statusTone: AppStatusTone = .none
    var isEditingLocked: Bool = false

    var isPlannedOwn: Bool { status == .planned && isLedByCurrentUser }
    var isActiveOwn: Bool { status == .ongoing && isLedByCurrentUser }
    var isActiveParticipating: Bool { status != .completed && !isLedByCurrentUser }
    var isArchived: Bool { status == .completed }
}

struct OrganizationRowSnapshot: Identifiable, Equatable {
    let id: String
    let displayName: String
    let sortName: String
    let flag: String
    let icons: [String]
    let category: String
    let roles: [OrganizationRole]
    let roleSummary: String
    let applicationCount: Int
    let waitingCount: Int
    let grantedCount: Int
    let rejectedCount: Int
    let hasLinkedRecords: Bool
    let isGrantProvider: Bool
    let isStewardshipOrganization: Bool
    let isManagerOrganization: Bool

    var grantRateSortValue: Double {
        guard applicationCount > 0 else { return 0 }
        return Double(grantedCount) / Double(applicationCount)
    }

    var grantRateText: String {
        guard applicationCount > 0 else { return "0%" }
        return "\(Int((grantRateSortValue * 100).rounded()))%"
    }
}

struct SubmissionAuthorExportRow: Codable {
    let firstName: String
    let lastName: String
    let titleSv: String
    let titleEn: String
    let orcid: String
    let organizationSv: String
    let organizationEn: String
    let departmentSv: String
    let departmentEn: String
    let city: String
    let country: String
    let email: String
    let phoneLabel: String
    let phoneNumber: String
    let phoneLabelSecondary: String
    let phoneNumberSecondary: String
    let creditRoles: [String]
    let creditRoleContributions: [String: String]

    var title: String {
        titleSv.nonEmpty ?? titleEn
    }

    var organization: String {
        organizationSv.nonEmpty ?? organizationEn
    }

    var department: String {
        departmentSv.nonEmpty ?? departmentEn
    }

    func localizedTitle(language: AppLanguage) -> String {
        if language == .swedish {
            return titleSv.nonEmpty ?? titleEn
        }
        return titleEn.nonEmpty ?? titleSv
    }

    func localizedOrganization(language: AppLanguage) -> String {
        if language == .swedish {
            return organizationSv.nonEmpty ?? organizationEn
        }
        return organizationEn.nonEmpty ?? organizationSv
    }

    func localizedDepartment(language: AppLanguage) -> String {
        if language == .swedish {
            return departmentSv.nonEmpty ?? departmentEn
        }
        return departmentEn.nonEmpty ?? departmentSv
    }
}

enum PublicationCreditStatementNameFormat: String, Codable, Hashable, CaseIterable, Identifiable {
    case fullName
    case initials
    case firstInitialAndLastName

    var id: String { rawValue }
}

struct PublicationCreditStatementOptions: Hashable {
    var nameFormat: PublicationCreditStatementNameFormat = .fullName
    var includeContributionParentheses: Bool = false
}

struct CVCustomExportConfiguration: Hashable {
    var style: CVDocumentExportStyle = .own
    var exportLanguage: AppLanguage = .english
    var includedSections: Set<CVExportSectionKey> = CVExportSectionKey.defaultIncludedSections
    var publicationOptions = PublicationExportOptions()
    var includeCollaboratorGrants = false
    var underlineDoctoralMainSupervisor = false
    var underlineDoctoralCoSupervisor = false
}

struct PublicationCustomExportConfiguration: Hashable {
    var includedSections: Set<PublicationExportSectionKey> = Set(PublicationExportSectionKey.allCases)
    var options = PublicationExportOptions()
    var underlineDoctoralMainSupervisor = false
    var underlineDoctoralCoSupervisor = false
}

struct SalaryCoverageExportRow: Codable {
    let source: String
    let projectNumber: String
    let peoe: String
    let percentage: String
    let period: String
    let from: String
    let to: String
}

struct ClipboardPreviewPayload: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

enum FundingStatementLanguageMode {
    case english
    case swedish
}

enum FundingStatementSortMode {
    case firstFundingFirst
    case largestFundingFirst
}

enum SubmissionAuthorExportMode: String, Hashable, CaseIterable, Identifiable {
    case standard
    case editorialManager
    case custom

    var id: String { rawValue }
}

enum SubmissionAuthorExportColumn: String, Hashable, CaseIterable, Identifiable {
    case title
    case firstName
    case lastName
    case email
    case orcid
    case organization
    case department
    case city
    case country
    case phoneLabel
    case phoneNumber
    case phoneLabelSecondary
    case phoneNumberSecondary
    case creditSummary
    case conceptualization
    case dataCuration
    case formalAnalysis
    case fundingAcquisition
    case investigation
    case methodology
    case projectAdministration
    case resources
    case software
    case supervision
    case validation
    case visualization
    case writingOriginalDraft
    case writingReviewEditing

    var id: String { rawValue }

    static var customSelectableColumns: [SubmissionAuthorExportColumn] {
        [
            .title,
            .firstName,
            .lastName,
            .email,
            .orcid,
            .organization,
            .department,
            .city,
            .country,
            .phoneLabel,
            .phoneNumber,
            .phoneLabelSecondary,
            .phoneNumberSecondary,
            .creditSummary,
        ]
    }

    /// The default column set/order in the author-export dialog — the
    /// WYSIWYG equivalent of the old "Standard" menu item.
    static var standardTemplateColumns: [SubmissionAuthorExportColumn] {
        [
            .firstName,
            .lastName,
            .title,
            .orcid,
            .organization,
            .department,
            .city,
            .country,
            .email,
            .phoneLabel,
            .phoneNumber,
            .phoneLabelSecondary,
            .phoneNumberSecondary,
            .creditSummary,
        ]
    }

    /// Column set/order applied by the dialog's "Mall: Editorial Manager"
    /// button — mirrors the old fixed Editorial Manager export.
    static var editorialManagerTemplateColumns: [SubmissionAuthorExportColumn] {
        [
            .title,
            .firstName,
            .lastName,
            .email,
            .orcid,
            .organization,
            .country,
            .creditSummary,
        ]
    }

    static var creditRoleColumns: [SubmissionAuthorExportColumn] {
        allCases.filter { $0.creditRole != nil }
    }

    var creditRole: PublicationCreditRole? {
        switch self {
        case .conceptualization:
            return .conceptualization
        case .dataCuration:
            return .dataCuration
        case .formalAnalysis:
            return .formalAnalysis
        case .fundingAcquisition:
            return .fundingAcquisition
        case .investigation:
            return .investigation
        case .methodology:
            return .methodology
        case .projectAdministration:
            return .projectAdministration
        case .resources:
            return .resources
        case .software:
            return .software
        case .supervision:
            return .supervision
        case .validation:
            return .validation
        case .visualization:
            return .visualization
        case .writingOriginalDraft:
            return .writingOriginalDraft
        case .writingReviewEditing:
            return .writingReviewEditing
        default:
            return nil
        }
    }
}

struct SubmissionAuthorExportConfiguration: Hashable {
    var mode: SubmissionAuthorExportMode = .standard
    var exportLanguage: AppLanguage = .english
    var includedColumns: Set<SubmissionAuthorExportColumn> = Set(SubmissionAuthorExportColumn.customSelectableColumns)
    /// Column order for custom exports; included columns render in this order.
    var columnOrder: [SubmissionAuthorExportColumn] = SubmissionAuthorExportColumn.customSelectableColumns

    static var standard: SubmissionAuthorExportConfiguration {
        SubmissionAuthorExportConfiguration(mode: .standard)
    }

    static func standard(language: AppLanguage) -> SubmissionAuthorExportConfiguration {
        SubmissionAuthorExportConfiguration(mode: .standard, exportLanguage: language)
    }

    static var editorialManager: SubmissionAuthorExportConfiguration {
        SubmissionAuthorExportConfiguration(mode: .editorialManager, exportLanguage: .english)
    }

    var effectiveExportLanguage: AppLanguage {
        mode == .editorialManager ? .english : exportLanguage
    }
}

struct SubmissionAuthorWorkbookPayload: Codable {
    let headers: [String]
    let rows: [[String]]
}
