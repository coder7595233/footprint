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
