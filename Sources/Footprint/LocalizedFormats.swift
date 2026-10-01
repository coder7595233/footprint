import Foundation

/// Round 16: small shared texts and formats that depend on the interface language.
extension AppLanguage {
    /// Placeholder shown in empty date fields.
    var datePlaceholder: String {
        text("YYYY-MM-DD", "ÅÅÅÅ-MM-DD")
    }
}

enum AppTimestampFormatter {
    /// ISO date and 24-hour time ("2026-10-01 14:05") in both languages, used
    /// for backup and save times so they never show AM/PM or a month name.
    static func dateAndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// Round 17: day, short month and year ("1 okt. 2026" in Swedish,
    /// "1 Oct 2026" in English). The month follows the language's own rule:
    /// Swedish month names stay lowercase, English ones keep their capital.
    static func dayMonthYear(
        _ date: Date,
        locale: Locale?,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        if let locale {
            formatter.locale = locale
        }
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    static func dayMonthYear(_ date: Date, language: AppLanguage) -> String {
        dayMonthYear(date, locale: Locale(identifier: language == .swedish ? "sv_SE" : "en_US"))
    }

    /// 24-hour time ("14:05").
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
