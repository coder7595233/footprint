import Foundation

enum FootprintDataExchangeFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case databasePackage
    case excelWorkbook

    var id: String { rawValue }

    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .databasePackage:
            return language.text("Footprint database", "Footprint-databas")
        case .excelWorkbook:
            return language.text("Excel safety workbook", "Excel-säkerhetskopia")
        }
    }

}

enum FootprintDataExchangeScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case entireApp
    case selectedCategories

    var id: String { rawValue }

    static func availableCases(for format: FootprintDataExchangeFormat) -> [FootprintDataExchangeScope] {
        switch format {
        case .databasePackage:
            return [.entireApp, .selectedCategories]
        case .excelWorkbook:
            return [.entireApp]
        }
    }

    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .entireApp:
            return language.text("Entire app", "Hela appen")
        case .selectedCategories:
            return language.text("Selected data", "Valda data")
        }
    }
}

enum FootprintDataExchangeCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case applications
    case projects
    case organizations
    case fundManagers
    case researchers
    case journals
    case publications
    case teaching
    case doctoralCandidates
    case calendar
    case cv
    case salary
    case dataQuality
    case appSettings

    var id: String { rawValue }

    var supportsSelectiveDatabaseTransfer: Bool {
        switch self {
        case .applications, .projects, .organizations, .researchers, .journals, .teaching:
            return true
        case .fundManagers, .publications, .doctoralCandidates, .calendar, .cv, .salary, .dataQuality, .appSettings:
            return false
        }
    }

    static func selectableCases(for format: FootprintDataExchangeFormat) -> [FootprintDataExchangeCategory] {
        switch format {
        case .databasePackage:
            return allCases.filter(\.supportsSelectiveDatabaseTransfer)
        case .excelWorkbook:
            return []
        }
    }

    static func defaultSelection(for format: FootprintDataExchangeFormat) -> Set<FootprintDataExchangeCategory> {
        Set(selectableCases(for: format))
    }

    static func dependencyClosure(
        for selectedCategories: Set<FootprintDataExchangeCategory>
    ) -> Set<FootprintDataExchangeCategory> {
        var resolved = selectedCategories
        var pending = Array(selectedCategories)
        while let category = pending.popLast() {
            for dependency in category.selectiveTransferDependencies where resolved.insert(dependency).inserted {
                pending.append(dependency)
            }
        }
        return resolved
    }

    private var selectiveTransferDependencies: Set<FootprintDataExchangeCategory> {
        switch self {
        case .applications:
            return [.organizations, .projects, .researchers]
        case .projects:
            return [.organizations, .researchers]
        case .organizations:
            // Congress participation and organization contacts may retain researcher IDs.
            return [.researchers]
        case .researchers:
            // Researcher affiliations retain raw organization names even when an ID
            // cannot be resolved, while transferring organizations preserves links
            // that can be resolved.
            return [.organizations]
        case .teaching:
            return [.organizations, .researchers]
        case .journals:
            return []
        case .fundManagers, .publications, .doctoralCandidates, .calendar, .cv,
             .salary, .dataQuality, .appSettings:
            return []
        }
    }

    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .applications:
            return language.text("Applications", "Ansökningar")
        case .projects:
            return language.text("Projects", "Projekt")
        case .organizations:
            return language.text("Organizations", "Organisationer")
        case .fundManagers:
            return language.text("Fund managers", "Medelsförvaltare")
        case .researchers:
            return language.text("Researchers", "Forskare")
        case .journals:
            return language.text("Journals", "Tidskrifter")
        case .publications:
            return language.text("Publications", "Publikationer")
        case .teaching:
            return language.text("Teaching", "Undervisning")
        case .doctoralCandidates:
            return language.text("Doctoral candidates", "Doktorander")
        case .calendar:
            return language.text("Calendar", "Kalender")
        case .cv:
            return "CV"
        case .salary:
            return language.text("Salary", "Lön")
        case .dataQuality:
            return language.text("Data quality", "Datakvalitet")
        case .appSettings:
            return language.text("App settings", "Appinställningar")
        }
    }

}

struct FootprintDatabaseExportDescriptor: Codable, Equatable, Sendable {
    static let currentFormatVersion = 2
    static let supportedFormatVersions = 1...currentFormatVersion

    let formatVersion: Int
    let exportedAt: String
    let categories: [FootprintDataExchangeCategory]
    let isCompleteDatabase: Bool
    let payloadDirectoryName: String
}

extension PublicationJournal {
    func transferIdentityMatchScore(with other: PublicationJournal) -> Int {
        var score = 0
        if Self.transferIdentityNameKey(name).nonEmpty != nil,
           Self.transferIdentityNameKey(name) == Self.transferIdentityNameKey(other.name) {
            score += 1
        }
        if Self.transferIdentityISSNKey(issn).nonEmpty != nil,
           Self.transferIdentityISSNKey(issn) == Self.transferIdentityISSNKey(other.issn) {
            score += 1
        }
        if Self.transferIdentityISSNKey(eissn).nonEmpty != nil,
           Self.transferIdentityISSNKey(eissn) == Self.transferIdentityISSNKey(other.eissn) {
            score += 1
        }
        return score
    }

    func replacingTransferIdentity(withLocalID localID: String) -> PublicationJournal {
        var copy = self
        copy.id = localID
        return copy
    }

    private static func transferIdentityNameKey(_ value: String) -> String {
        let canonical = switch value.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Ateriosclerosis, Thrombosis, and Vascular Biology":
            "Arteriosclerosis, Thrombosis, and Vascular Biology"
        default:
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return canonical
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func transferIdentityISSNKey(_ value: String) -> String {
        value
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
