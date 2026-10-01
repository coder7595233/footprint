import Foundation
import SwiftUI

/// Round 16: the one place where a record's status becomes a colour tone
/// (see `AppStatusTone`). Every list, badge, chart and timeline asks here,
/// so a status has the same colour everywhere.
enum AppStatusTones {

    // MARK: Applications

    /// Beviljat = done (grey once the funds are spent); Väntar svar = pending;
    /// "Stängd – sökt?" = warning; Avslag = negative; Tillbakadragen and
    /// Ej sökt = grey; Att söka = no fill (paler when the call is not open yet).
    static func application(
        resultLabel: String,
        isFullySpent: Bool,
        awaitsAppliedAnswer: Bool,
        isBeforeOpening: Bool
    ) -> AppStatusTone {
        let status = resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if awaitsAppliedAnswer {
            return .warning
        }
        if status.range(of: "Beviljat", options: .caseInsensitive) != nil {
            return isFullySpent ? .inactive : .done
        }
        if status.range(of: "Avslag", options: .caseInsensitive) != nil {
            return .negative
        }
        if status == "Tillbakadragen" || status == "Ej sökt" {
            return .inactive
        }
        if status.isEmpty || status == "Att söka" {
            return isBeforeOpening ? .notOpen : .none
        }
        return .pending
    }

    static func application(_ application: GrantApplication, isFullySpent: Bool? = nil, today: Date = Date()) -> AppStatusTone {
        let calendar = Calendar.current
        let isBeforeOpening = application.openDate.map {
            calendar.startOfDay(for: $0) > calendar.startOfDay(for: today)
        } ?? false
        return self.application(
            resultLabel: application.resultLabel,
            isFullySpent: isFullySpent ?? application.isFullySpent,
            awaitsAppliedAnswer: application.awaitsAppliedAnswer(today: today),
            isBeforeOpening: isBeforeOpening
        )
    }

    static func application(_ row: ApplicationRowSnapshot, today: Date = Date()) -> AppStatusTone {
        // The row has no lock flag; a passed closing date on "Att söka" is
        // the same "Stängd – sökt?" case as `awaitsAppliedAnswer()`.
        let calendar = Calendar.current
        let awaitsAnswer = row.isToApplyStatus && (row.closeDate.map {
            calendar.startOfDay(for: $0) < calendar.startOfDay(for: today)
        } ?? false)
        return application(
            resultLabel: row.resultLabel,
            isFullySpent: row.isFullySpent,
            awaitsAppliedAnswer: awaitsAnswer,
            isBeforeOpening: row.isBeforeOpening
        )
    }

    // MARK: Publications

    /// Publicerad = done; Inskickad and Accepterad = pending (waiting for the
    /// journal); Refuserad = negative; Planerad and Under arbete = no fill.
    static func publication(_ status: PublicationStatus) -> AppStatusTone {
        switch status {
        case .published: return .done
        case .submitted, .accepted: return .pending
        case .rejected: return .negative
        case .planned, .inPreparation: return .none
        }
    }

    static func publication(storedStatus: String?) -> AppStatusTone {
        publication(PublicationStatus.fromStored(storedStatus))
    }

    // MARK: Projects

    /// Completed = grey; ongoing with progress (a data collection, an ethics
    /// application or granted funds) = done; ongoing without progress or
    /// planned with progress = pending; planned without = no fill.
    static func project(status: ProjectLifecycleStatus, hasProgress: Bool) -> AppStatusTone {
        switch status {
        case .completed: return .inactive
        case .ongoing: return hasProgress ? .done : .pending
        case .planned: return hasProgress ? .pending : .none
        }
    }

    /// True when the project has a data collection or an ethics application.
    static func projectHasOwnProgress(_ project: ProjectRecord) -> Bool {
        if project.hasDataCollection { return true }
        if project.dataCollections.contains(where: { $0.from.trimmedOrNil != nil || $0.to.trimmedOrNil != nil }) {
            return true
        }
        if !project.ethicsBaseApplication.isEmpty { return true }
        return project.ethicsAmendments.contains { !$0.isEmpty }
    }

    // MARK: Doctoral candidates

    enum DoctoralPhase: Equatable {
        case planned
        case ongoing
        case completed
        case endedEarly
    }

    /// Ongoing = pending; Disputerad = done; ended early = grey; admitted but
    /// not started = no fill.
    static func doctoral(_ phase: DoctoralPhase) -> AppStatusTone {
        switch phase {
        case .planned: return .none
        case .ongoing: return .pending
        case .completed: return .done
        case .endedEarly: return .inactive
        }
    }

    static func doctoralPhase(_ candidate: DoctoralCandidateRecord, today: Date = Date()) -> DoctoralPhase {
        if DoctoralMilestoneOutcome(rawValue: candidate.halftimeOutcomeRaw ?? "") == .endedBefore ||
            DoctoralMilestoneOutcome(rawValue: candidate.plannedDisputationOutcomeRaw ?? "") == .endedBefore {
            return .endedEarly
        }
        if DoctoralMilestoneOutcome(rawValue: candidate.plannedDisputationOutcomeRaw ?? "") == .completed ||
            isPastOrToday(candidate.disputationDate, today: today) {
            return .completed
        }
        if isPastOrToday(candidate.admissionDate, today: today) {
            return .ongoing
        }
        return .planned
    }

    static func doctoral(_ candidate: DoctoralCandidateRecord, today: Date = Date()) -> AppStatusTone {
        // Supervision not yet confirmed in Retendo needs the user's action.
        if candidate.supervisionPeriods.contains(where: \.needsRetendoConfirmation) {
            return .warning
        }
        return doctoral(doctoralPhase(candidate, today: today))
    }

    // MARK: Expert assignments (reviews)

    /// Accepted = pending; overdue = warning; completed = done; no status =
    /// no fill. (Declined assignments are grey; the data has no such state yet.)
    static func review(_ status: CVReviewWorkflowStatus?, isDeclined: Bool = false) -> AppStatusTone {
        if isDeclined { return .inactive }
        switch status {
        case .completed: return .done
        case .accepted: return .pending
        case .overdue: return .warning
        case nil: return .none
        }
    }

    // MARK: Conference contributions

    static func conferenceContribution(_ status: AppConferenceContributionBadgeStatus) -> AppStatusTone {
        switch status {
        case .presented: return .done
        case .submitted, .accepted: return .pending
        case .rejected: return .negative
        case .planned: return .none
        }
    }

    static func conferenceContribution(_ status: CVConferenceContributionStatus) -> AppStatusTone {
        switch status {
        case .presented: return .done
        case .accepted: return .pending
        case .rejected: return .negative
        case .planned: return .none
        }
    }

    // MARK: Tasks

    /// Upcoming = no fill; overdue = warning; done = done.
    static func task(isCompleted: Bool, isOverdue: Bool) -> AppStatusTone {
        if isCompleted { return .done }
        return isOverdue ? .warning : .none
    }

    // MARK: Deadlines

    /// Closing dates: passed = negative, ≤ 7 days = warning, 8–30 days =
    /// pending, later = no fill. Never green for "far away".
    static func closingDeadline(daysRemaining days: Int) -> AppStatusTone {
        if days < 0 { return .negative }
        if days <= 7 { return .warning }
        if days <= 30 { return .pending }
        return .none
    }

    /// Last disposition dates (and other "spend before" dates): passed =
    /// negative, under 3 months = warning, 3–12 months = pending, later = no fill.
    static func dispositionDeadline(monthsRemaining months: Int, hasPassed: Bool) -> AppStatusTone {
        if hasPassed { return .negative }
        if months < 3 { return .warning }
        if months < 12 { return .pending }
        return .none
    }

    static func dispositionDeadline(_ date: Date, today: Date = Date(), calendar: Calendar = .current) -> AppStatusTone {
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: date)
        let months = calendar.dateComponents([.month], from: start, to: end).month ?? 0
        return dispositionDeadline(monthsRemaining: months, hasPassed: end < start)
    }

    /// The same disposition thresholds when only a day count is known.
    static func dispositionDeadline(daysRemaining days: Int) -> AppStatusTone {
        dispositionDeadline(monthsRemaining: days < 0 ? -1 : days / 30, hasPassed: days < 0)
    }

    static func closingDeadline(_ date: Date, today: Date = Date(), calendar: Calendar = .current) -> AppStatusTone {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: date)).day ?? 0
        return closingDeadline(daysRemaining: days)
    }

    private static func isPastOrToday(_ rawDate: String, today: Date) -> Bool {
        guard let date = rawDate.trimmedOrNil.flatMap(DateParsers.isoDay.date(from:)) else { return false }
        return Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: today)
    }
}

extension AppPalette {
    /// A list row's status strip: nil when the tone has no fill.
    static func statusRowFill(_ tone: AppStatusTone) -> Color? {
        tone.hasFill ? statusFill(tone) : nil
    }

    /// Text for a last disposition date on the ordinary background: the
    /// shared disposition thresholds in readable text colours; secondary
    /// when the date is missing or far away.
    static func dispositionDeadlineText(_ date: Date?, today: Date = Date()) -> Color {
        guard let date else { return .secondary }
        let tone = AppStatusTones.dispositionDeadline(date, today: today)
        return tone.hasFill ? statusText(tone) : .secondary
    }

    /// A status capsule's fill; the neutral pill surface when the tone has no fill.
    static func statusCapsuleFill(_ tone: AppStatusTone) -> Color {
        tone.hasFill ? statusFill(tone) : pillSurface
    }
}

extension GrantApplication {
    /// The date the granted funds must be spent by.
    var dispositionDeadlineDate: Date? {
        lastDispositionDate ?? receivedUsageTo.flatMap { DateParsers.isoDay.date(from: $0) }
    }
}

@MainActor
extension GrantDataStore {
    /// The project's status tone (see `AppStatusTones.project`). Granted
    /// funds count when a granted application is linked to the project.
    func projectStatusTone(_ project: ProjectRecord) -> AppStatusTone {
        AppStatusTones.project(status: project.projectStatus, hasProgress: projectHasProgress(project))
    }

    func projectHasProgress(_ project: ProjectRecord) -> Bool {
        if AppStatusTones.projectHasOwnProgress(project) { return true }
        return applicationsForRead.contains { $0.isGranted && applicationBelongs($0, to: project) }
    }

    /// The application's tone with the store's own "fully spent" rule.
    func applicationStatusTone(_ application: GrantApplication, today: Date = Date()) -> AppStatusTone {
        AppStatusTones.application(application, isFullySpent: isEffectivelyFullySpent(application), today: today)
    }
}

/// Shorthand used by views: `projectStatusTone(project, store: store)`.
@MainActor
func projectStatusTone(_ project: ProjectRecord, store: GrantDataStore) -> AppStatusTone {
    store.projectStatusTone(project)
}
