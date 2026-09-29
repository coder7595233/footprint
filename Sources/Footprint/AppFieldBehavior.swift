import Foundation
import SwiftUI

enum AppFieldVisualState: Equatable {
    case normal
    case focused
    case dirty
    case invalid(String?)
    case missing(String?)
    case locked
    case readOnly

    var fill: Color {
        switch self {
        case .invalid, .missing, .dirty:
            // State is communicated through the border and help text. Editable
            // fields always retain the same surface, independent of their state.
            return AppPalette.fieldSurface
        case .locked, .readOnly:
            return Color.clear
        case .focused:
            return AppPalette.fieldSurface
        case .normal:
            return AppPalette.fieldSurface
        }
    }

    var stroke: Color {
        switch self {
        case .invalid, .missing:
            return AppPalette.vividRed.opacity(0.68)
        case .dirty:
            return AppPalette.linkAction.opacity(0.62)
        case .focused:
            return AppPalette.linkAction.opacity(0.78)
        case .locked, .readOnly:
            return Color.clear
        case .normal:
            return AppPalette.subtleBorder
        }
    }

    var helpText: String? {
        switch self {
        case .invalid(let message), .missing(let message):
            return message
        default:
            return nil
        }
    }

    var isInvalid: Bool {
        switch self {
        case .invalid, .missing:
            return true
        default:
            return false
        }
    }
}

struct AppFieldValidationResult: Equatable {
    var state: AppFieldVisualState

    static let valid = AppFieldValidationResult(state: .normal)
    static func invalid(_ message: String) -> AppFieldValidationResult {
        AppFieldValidationResult(state: .invalid(message))
    }
    static func missing(_ message: String) -> AppFieldValidationResult {
        AppFieldValidationResult(state: .missing(message))
    }
}

enum AppFieldParsers {
    static func canonicalDate(_ raw: String) -> String {
        DateParsers.canonicalizedDayInput(raw)
    }

    static func canonicalAmount(_ raw: String) -> String {
        GrantParsing.formatAmountInput(raw) ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canonicalDecimal(_ raw: String, maximumFractionDigits: Int = 2) -> String {
        guard let value = GrantParsing.numericValue(from: raw) else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canonicalPercentage(_ raw: String) -> String {
        canonicalDecimal(raw, maximumFractionDigits: 1)
    }

    static func canonicalHours(_ raw: String) -> String {
        canonicalDecimal(raw, maximumFractionDigits: 2)
    }

    static func canonicalHexColor(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return "#\(stripped.uppercased())"
    }

    static func canonicalYear(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
            return trimmed
        }
        if let match = trimmed.range(of: #"^\d{4}(?=-\d{2}-\d{2}$)"#, options: .regularExpression) {
            return String(trimmed[match])
        }
        return trimmed
    }

    static func canonicalORCID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://orcid.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://orcid.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "orcid.org/", with: "", options: .caseInsensitive)
    }

    static func canonicalDOI(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "https://dx.doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://dx.doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "dx.doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "doi:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canonicalPMID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://pubmed.ncbi.nlm.nih.gov/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://pubmed.ncbi.nlm.nih.gov/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "pubmed.ncbi.nlm.nih.gov/", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t"))
    }
}

enum AppFieldValidators {
    static func optionalDate(_ value: String, language: AppLanguage = .swedish) -> AppFieldValidationResult {
        let normalized = AppFieldParsers.canonicalDate(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .valid }
        guard normalized.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              DateParsers.isoDay.date(from: normalized) != nil else {
            return .invalid(language.text("Invalid date format", "Ogiltigt datumformat"))
        }
        return .valid
    }

    static func optionalDateRange(from: String?, to: String?, language: AppLanguage = .swedish) -> AppFieldValidationResult {
        validationDateRangeIsIllogical(from: from, to: to)
            ? .invalid(language.text("Illogical date combination", "Ologisk datumkombination"))
            : .valid
    }

    static func optionalURL(_ value: String?, language: AppLanguage = .swedish) -> AppFieldValidationResult {
        guard value?.trimmedOrNil != nil else { return .valid }
        return normalizedWebLinkURL(value) == nil
            ? .invalid(language.text("Invalid link", "Ogiltig länk"))
            : .valid
    }

    static func optionalORCID(_ value: String?, language: AppLanguage = .swedish) -> AppFieldValidationResult {
        guard let value = value?.trimmedOrNil else { return .valid }
        let cleaned = AppFieldParsers.canonicalORCID(value)
        let pattern = #"^\d{4}-\d{4}-\d{4}-\d{3}[\dX]$"#
        return cleaned.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil
            ? .invalid(language.text("Invalid ORCID format", "Ogiltigt ORCID-format"))
            : .valid
    }

    static func optionalDOI(_ value: String?, language: AppLanguage = .swedish) -> AppFieldValidationResult {
        guard let value = value?.trimmedOrNil else { return .valid }
        let cleaned = AppFieldParsers.canonicalDOI(value)
        return cleaned.range(of: #"^10\.\S+/\S+$"#, options: .regularExpression) == nil
            ? .invalid(language.text("Invalid DOI format", "Ogiltigt DOI-format"))
            : .valid
    }

    static func optionalPMID(_ value: String?, language: AppLanguage = .swedish) -> AppFieldValidationResult {
        guard let value = value?.trimmedOrNil else { return .valid }
        let cleaned = AppFieldParsers.canonicalPMID(value)
        return cleaned.range(of: #"^\d+$"#, options: .regularExpression) == nil
            ? .invalid(language.text("Invalid PMID format", "Ogiltigt PMID-format"))
            : .valid
    }

    static func optionalNumeric(_ value: String?, language: AppLanguage = .swedish) -> AppFieldValidationResult {
        guard value?.trimmedOrNil != nil else { return .valid }
        return GrantParsing.numericValue(from: value) == nil
            ? .invalid(language.text("Invalid number", "Ogiltigt tal"))
            : .valid
    }

    static func optionalHexColor(_ value: String?, language: AppLanguage = .swedish) -> AppFieldValidationResult {
        guard let value = value?.trimmedOrNil else { return .valid }
        let cleaned = AppFieldParsers.canonicalHexColor(value)
        return cleaned.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) == nil
            ? .invalid(language.text("Use #RRGGBB", "Använd #RRGGBB"))
            : .valid
    }

    static func optionalYear(_ value: String?, language: AppLanguage = .swedish) -> AppFieldValidationResult {
        guard let value = value?.trimmedOrNil else { return .valid }
        let cleaned = AppFieldParsers.canonicalYear(value)
        return cleaned.range(of: #"^\d{4}$"#, options: .regularExpression) == nil
            ? .invalid(language.text("Use four digits", "Använd fyra siffror"))
            : .valid
    }
}

func normalizedIdentifierURL(raw: String?, kind: AppIdentifierKind) -> URL? {
    guard let raw = raw?.trimmedOrNil else { return nil }
    switch kind {
    case .doi:
        let cleaned = AppFieldParsers.canonicalDOI(raw)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "https://doi.org/\(cleaned)")
    case .pmid:
        let cleaned = AppFieldParsers.canonicalPMID(raw)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(cleaned)/")
    case .orcid:
        let cleaned = AppFieldParsers.canonicalORCID(raw)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "https://orcid.org/\(cleaned)")
    }
}

enum AppIdentifierKind {
    case doi
    case pmid
    case orcid
}
