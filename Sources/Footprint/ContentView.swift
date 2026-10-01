import AppKit
import SwiftUI
import UniformTypeIdentifiers


struct HomeTypographySettings {
    let design: Font.Design
    let statTitleSize: Double
    let statTitleBold: Bool
    let statTitleColor: Color
    let statValueSize: Double
    let statValueBold: Bool
    let statValueColor: Color
    let columnTitleSize: Double
    let columnTitleBold: Bool
    let columnTitleColor: Color
    let itemTitleSize: Double
    let itemTitleBold: Bool
    let itemTitleColor: Color
    let itemSubtitleSize: Double
    let itemSubtitleBold: Bool
    let itemSubtitleColor: Color
    let itemDetailSize: Double
    let itemDetailBold: Bool
    let itemDetailColor: Color

    static let `default` = HomeTypographySettings(
        design: .default,
        statTitleSize: 16,
        statTitleBold: true,
        statTitleColor: AppPalette.semanticOnColor,
        statValueSize: 25,
        statValueBold: true,
        statValueColor: AppPalette.semanticOnColor,
        columnTitleSize: 20,
        columnTitleBold: true,
        columnTitleColor: AppPalette.semanticOnColor,
        itemTitleSize: 15,
        itemTitleBold: true,
        itemTitleColor: AppPalette.semanticOnColor,
        itemSubtitleSize: 13,
        itemSubtitleBold: false,
        itemSubtitleColor: AppPalette.semanticOnColor,
        itemDetailSize: 13,
        itemDetailBold: false,
        itemDetailColor: AppPalette.semanticOnColor
    )
}


struct DashboardListItem: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let detail: String
    let status: String
    let tone: BadgeTone
    let detailDate: Date?
    let detailDateStyle: DeadlineRingStyle
    let plainStatusColor: Color?
    let action: (() -> Void)?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        detail: String,
        status: String,
        tone: BadgeTone = .outline,
        detailDate: Date? = nil,
        detailDateStyle: DeadlineRingStyle = .closingSoon,
        plainStatusColor: Color? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.status = status
        self.tone = tone
        self.detailDate = detailDate
        self.detailDateStyle = detailDateStyle
        self.plainStatusColor = plainStatusColor
        self.action = action
    }
}

enum DeadlineRingStyle {
    case closingSoon
    case applicationClosing
    case repaymentDue
    case remainingFunds
    case taskDeadline

    /// Round 16: one set of deadline thresholds everywhere (see
    /// `AppStatusTones.closingDeadline` / `dispositionDeadline`).
    func tone(forDaysRemaining days: Int) -> AppStatusTone {
        switch self {
        case .closingSoon, .applicationClosing, .taskDeadline:
            return AppStatusTones.closingDeadline(daysRemaining: days)
        case .repaymentDue, .remainingFunds:
            return AppStatusTones.dispositionDeadline(daysRemaining: days)
        }
    }

    func color(forDaysRemaining days: Int) -> Color {
        AppPalette.statusFill(tone(forDaysRemaining: days))
    }
}

@MainActor

enum BadgeTone: Equatable {
    case positive
    case positiveMuted
    case negative
    case pending
    case outline
    // Round 16: the remaining status tones.
    case warning
    case inactive
    case notOpen

    nonisolated init(_ tone: AppStatusTone) {
        switch tone {
        case .done: self = .positive
        case .pending: self = .pending
        case .warning: self = .warning
        case .negative: self = .negative
        case .inactive: self = .inactive
        case .none: self = .outline
        case .notOpen: self = .notOpen
        }
    }

    /// Round 16: every badge colour comes from the shared status palette.
    /// `positiveMuted` (old "spent" green) is now grey.
    nonisolated var statusTone: AppStatusTone {
        switch self {
        case .positive: return .done
        case .positiveMuted, .inactive: return .inactive
        case .negative: return .negative
        case .pending: return .pending
        case .warning: return .warning
        case .outline: return .none
        case .notOpen: return .notOpen
        }
    }

    var colors: (foreground: Color, background: Color) {
        let tone = statusTone
        switch tone {
        case .none:
            return (AppPalette.pillText, AppPalette.pillSurface)
        case .notOpen:
            return (AppPalette.statusText(.notOpen), AppPalette.pillSurface)
        default:
            return (AppPalette.statusOnFill, AppPalette.statusFill(tone))
        }
    }
}

struct StatusBadge: View {
    let text: String
    let tone: BadgeTone
    var showsIndicator = true

    var body: some View {
        let colors = tone.colors
        AppToneBadge(
            text: text,
            foreground: colors.foreground,
            background: colors.background,
            stroke: AppPalette.border,
            showsIndicator: showsIndicator,
            indicatorColor: colors.foreground.opacity(tone == .outline ? 0.42 : 0.9)
        )
    }
}



extension LocalizedNamedRecord {
    func displayName(for language: AppLanguage) -> String {
        language == .swedish ? (nameSv.nonEmpty ?? nameEn) : (nameEn.nonEmpty ?? nameSv)
    }
}

@MainActor
extension GrantApplication {
    func organizationCategoryDisplay(in store: GrantDataStore, language: AppLanguage) -> String {
        // "Alla kopplingar via id": the category of the linked grant provider.
        guard let category = store.linkedFunder(of: self)?.category?.trimmedOrNil else {
            return language.text("Choose an organization first", "Välj organisation först")
        }
        return language.localizedGrantCategory(category)
    }

    func projectTitleWithOrganization(store: GrantDataStore, language: AppLanguage) -> String {
        let project = store.projectLabel(for: self, language: language)?.nonEmpty ?? language.text("No project", "Saknar projekt")
        let organizationName = store.organizationLabel(for: self, language: language)
        let amount = isGranted ? grantedAmountValue : appliedAmountValue
        let suffix = CurrencyFormatter.format(amount, code: currency)
        return "\(project) (\(organizationName)), \(suffix)"
    }
}

extension ManagerOption {
    func displayName(for language: AppLanguage) -> String {
        language == .swedish ? nameSv : (nameEn.nonEmpty ?? nameSv)
    }

    func alternateDisplayName(for language: AppLanguage) -> String? {
        let alternate = language == .swedish ? nameEn.nonEmpty : nameSv.nonEmpty
        guard let alternate, alternate != displayName(for: language) else { return nil }
        return alternate
    }
}

private func flagEmoji(for countryName: String) -> String? {
    let trimmed = GrantParsing.canonicalCountryName(countryName).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.caseInsensitiveCompare("Somaliland") == .orderedSame {
        return "🏴"
    }

    let explicitCodes: [String: String] = [
        "Sweden": "SE", "Sverige": "SE",
        "United Kingdom": "GB", "UK": "GB", "U.K.": "GB", "England": "GB", "Storbritannien": "GB",
        "Norway": "NO", "Norge": "NO",
        "Denmark": "DK", "Danmark": "DK",
        "Finland": "FI",
        "Germany": "DE", "Tyskland": "DE",
        "France": "FR", "Frankrike": "FR",
        "Netherlands": "NL", "Nederländerna": "NL",
        "Belgium": "BE", "Belgien": "BE",
        "Switzerland": "CH", "Schweiz": "CH",
        "Austria": "AT", "Österrike": "AT",
        "Italy": "IT", "Italien": "IT",
        "Spain": "ES", "Spanien": "ES",
        "Australia": "AU", "Australien": "AU",
        "United States": "US", "USA": "US", "Förenta staterna": "US"
    ]

    let regionCode =
        explicitCodes[trimmed]
        ?? Locale.Region.isoRegions.first(where: {
            let english = Locale(identifier: "en_US").localizedString(forRegionCode: $0.identifier)
            let swedish = Locale(identifier: "sv_SE").localizedString(forRegionCode: $0.identifier)
            return english == trimmed || swedish == trimmed
        })?.identifier

    guard let regionCode else { return nil }
    return regionCode
        .unicodeScalars
        .compactMap { UnicodeScalar(127397 + $0.value) }
        .map(String.init)
        .joined()
}

private extension String {
    func displayDate(language: AppLanguage) -> String {
        guard let date = DateParsers.isoDay.date(from: self) else { return self }
        return DateParsers.isoDay.string(from: date)
    }
}

private extension GrantApplication {
    var sumBucketForLists: String {
        amountBucketLabel
    }
}

func statusTone(for result: String?) -> BadgeTone {
    // Round 16: the shared application mapping (no dates known here).
    BadgeTone(AppStatusTones.application(
        resultLabel: result ?? "",
        isFullySpent: false,
        awaitsAppliedAnswer: false,
        isBeforeOpening: false
    ))
}

func applicationTone(for application: GrantApplication) -> BadgeTone {
    BadgeTone(AppStatusTones.application(application))
}

private func applicationTone(for application: ApplicationRowSnapshot) -> BadgeTone {
    BadgeTone(AppStatusTones.application(application))
}

private func summarizedCounts(for applications: [GrantApplication]) -> (submitted: Int, rejected: Int, waiting: Int, granted: Int, toApply: Int) {
    let granted = applications.filter { $0.resultLabel == "Beviljat" }.count
    let rejected = applications.filter {
        let status = $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return status == "Avslag" || status == "Tillbakadragen"
    }.count
    let waiting = applications.filter { $0.resultLabel == "Väntar svar" }.count
    let toApply = applications.filter {
        let status = $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return status.isEmpty || status == "Att söka"
    }.count
    let submitted = applications.count - toApply
    return (submitted, rejected, waiting, granted, toApply)
}
