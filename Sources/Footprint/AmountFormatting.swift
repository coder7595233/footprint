import Foundation

/// Round 16: one formatter for amounts shown in Swedish kronor.
/// Swedish text uses "kr" and "mkr", English text uses "SEK" and "MSEK".
/// Digits are grouped with a space in both languages; the decimal separator
/// follows the language ("," in Swedish, "." in English). A missing amount is
/// shown as a dash, never as "N/A".
enum AmountFormatter {
    /// Shown when there is no amount.
    static let missing = "–"

    static func sekUnit(_ language: AppLanguage) -> String {
        language.text("SEK", "kr")
    }

    static func millionsUnit(_ language: AppLanguage) -> String {
        language.text("MSEK", "mkr")
    }

    /// Whole number with space grouping, e.g. "1 250 000".
    static func groupedInteger(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value.rounded()))
    }

    /// Number with up to `maximumFractionDigits` decimals in the language's style.
    static func decimal(_ value: Double, language: AppLanguage, maximumFractionDigits: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.decimalSeparator = language == .english ? "." : ","
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// "1 250 000 kr" / "1 250 000 SEK"; nil gives a dash.
    static func sek(_ value: Double?, language: AppLanguage) -> String {
        guard let value else { return missing }
        return "\(groupedInteger(value)) \(sekUnit(language))"
    }

    /// Amount in millions: "1,3 mkr" / "1.3 MSEK"; nil gives a dash.
    static func millions(_ valueInSEK: Double?, language: AppLanguage, maximumFractionDigits: Int = 1) -> String {
        guard let valueInSEK else { return missing }
        let text = decimal(valueInSEK / 1_000_000, language: language, maximumFractionDigits: maximumFractionDigits)
        return "\(text) \(millionsUnit(language))"
    }

    /// Unit to put after an already formatted number for a currency code:
    /// Swedish kronor follow the language, other currencies keep their code.
    static func unit(forCurrencyCode code: String, language: AppLanguage) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "SEK" ? sekUnit(language) : code
    }
}
