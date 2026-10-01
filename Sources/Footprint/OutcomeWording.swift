import Foundation

/// The one place that decides how an application outcome is worded on screen
/// and in exported documents. Stored values (the raw values below, kept in
/// `resultLabel`) never change; only the displayed words come from here.
///
/// Rules: "Declined/Avslag" is used only for applications, "Rejected/Refuserad"
/// only for publications (see `PublicationOutcomeWording`), and
/// "Accepted/Accepterad" is never used for granted applications.
enum ApplicationOutcome: String, CaseIterable, Sendable {
    case toApply = "Att söka"
    case awaitingDecision = "Väntar svar"
    case granted = "Beviljat"
    case declined = "Avslag"
    case withdrawn = "Tillbakadragen"
    case notApplied = "Ej sökt"

    /// Matches a stored status string (surrounding whitespace ignored).
    init?(storedValue: String) {
        self.init(rawValue: storedValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Singular word used on a single record (chips, pickers, editor, list cells).
    func label(_ language: AppLanguage) -> String {
        switch self {
        case .toApply: return language.text("To apply", "Att söka")
        case .awaitingDecision: return language.text("Awaiting decision", "Väntar svar")
        case .granted: return language.text("Granted", "Beviljat")
        case .declined: return language.text("Declined", "Avslag")
        case .withdrawn: return language.text("Withdrawn", "Tillbakadragen")
        case .notApplied: return language.text("Not applied", "Ej sökt")
        }
    }

    /// Plural word used for headings, groups and statistics rows.
    func heading(_ language: AppLanguage) -> String {
        switch self {
        case .toApply: return language.text("To apply", "Att söka")
        case .awaitingDecision: return language.text("Awaiting decision", "Väntar svar")
        case .granted: return language.text("Granted", "Beviljade")
        case .declined: return language.text("Declined", "Avslagna")
        case .withdrawn: return language.text("Withdrawn", "Tillbakadragna")
        case .notApplied: return language.text("Not applied", "Ej sökta")
        }
    }
}

/// Wording for publication outcomes that share a word with applications.
enum PublicationOutcomeWording {
    static func rejectedLabel(_ language: AppLanguage) -> String {
        language.text("Rejected", "Refuserad")
    }

    static func rejectedHeading(_ language: AppLanguage) -> String {
        language.text("Rejected", "Refuserade")
    }
}
