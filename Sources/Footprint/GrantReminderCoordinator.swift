import AppKit
import Foundation
import UserNotifications

/// The kinds of reminder the app sends about an application.
enum GrantReminderKind: String, Hashable {
    case opens
    case closingSoon
    case decisionOverdue
    case dispositionEndingSoon
    case dispositionEnded
    case repaymentOverdue
    /// The day after closing, when the call is still "Att söka": did you
    /// apply? Clicking the notification asks the question.
    case closedUnanswered
}

/// One planned reminder: which application, what kind and when it is sent.
struct GrantReminderSchedule: Hashable {
    let id: String
    let kind: GrantReminderKind
    let fireDate: Date
    let applicationID: String
}

final class GrantReminderCoordinator: NSObject, @unchecked Sendable {
    private struct ReminderPlan {
        let id: String
        let fireDate: Date
        let title: String
        let body: String
        let applicationID: String
        let primaryLink: String?
        let shouldFireImmediatelyIfOverdue: Bool
    }

    private weak var store: GrantDataStore?
    private var center: UNUserNotificationCenter?
    private let sentDefaultsKey = AppRuntime.sentReminderDefaultsKey
    private let scheduledDefaultsKey = AppRuntime.scheduledReminderDefaultsKey

    @MainActor
    func configure(store: GrantDataStore, notificationCenter: UNUserNotificationCenter) {
        self.store = store
        center = notificationCenter
        requestAuthorizationIfNeeded()
        refresh(applications: store.applications, language: store.language)
    }

    /// Removes the reminders this coordinator has scheduled and stops
    /// scheduling new ones (used when notifications are turned off).
    @MainActor
    func disableNotifications() {
        guard let center else { return }
        let ids = UserDefaults.standard.stringArray(forKey: scheduledDefaultsKey) ?? []
        center.removePendingNotificationRequests(withIdentifiers: ids)
        UserDefaults.standard.removeObject(forKey: scheduledDefaultsKey)
        self.center = nil
    }

    @MainActor
    func refresh(applications: [GrantApplication], language: AppLanguage) {
        guard let center else { return }
        // Settings > Calendar > Reminders (on/off, lead days and time of day).
        let settings = store?.calendarReminderSettings ?? .standard
        guard settings.grantRemindersEnabled else {
            // Switched off: remove what is waiting, keep the list of sent
            // reminders so nothing is sent again when switched back on.
            let oldScheduledIDs = UserDefaults.standard.stringArray(forKey: scheduledDefaultsKey) ?? []
            center.removePendingNotificationRequests(withIdentifiers: oldScheduledIDs)
            UserDefaults.standard.set([String](), forKey: scheduledDefaultsKey)
            return
        }
        let plans = reminderPlans(for: applications, language: language, settings: settings)
        let now = Date()
        let futurePlans = plans.filter { $0.fireDate > now.addingTimeInterval(60) }
        let overdueWindowStart = Self.overdueWindowStart(now: now)
        let overduePlans = plans.filter {
            $0.fireDate <= now && $0.fireDate >= overdueWindowStart && $0.shouldFireImmediatelyIfOverdue
        }

        let oldScheduledIDs = Set(UserDefaults.standard.stringArray(forKey: scheduledDefaultsKey) ?? [])
        // Round 12: an immediate reminder already handed over is never
        // removed again (two quick refreshes lost it).
        let pendingRemovalIDs = Array(oldScheduledIDs.union(futurePlans.map(\.id)))
        center.removePendingNotificationRequests(withIdentifiers: pendingRemovalIDs)

        for plan in futurePlans {
            scheduleCalendarNotification(for: plan)
        }

        var sentIDs = Set(UserDefaults.standard.stringArray(forKey: sentDefaultsKey) ?? [])
        // Round 12: a reminder handed to the system earlier whose time has now
        // passed has been delivered; it is not sent a second time as overdue.
        sentIDs.formUnion(plans.filter { oldScheduledIDs.contains($0.id) && $0.fireDate <= now.addingTimeInterval(60) }.map(\.id))
        for plan in overduePlans where !sentIDs.contains(plan.id) {
            scheduleImmediateNotification(for: plan)
            sentIDs.insert(plan.id)
        }

        // Forget sent reminders whose plan is gone, but not while the grants
        // are not loaded yet (they would all be sent again later).
        if !applications.isEmpty {
            let activePlanIDs = Set(plans.map(\.id))
            sentIDs = sentIDs.intersection(activePlanIDs)
        }

        UserDefaults.standard.set(Array(Set(futurePlans.map(\.id))), forKey: scheduledDefaultsKey)
        UserDefaults.standard.set(Array(sentIDs), forKey: sentDefaultsKey)
    }

    private func requestAuthorizationIfNeeded() {
        guard let center else { return }
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                // The calendar task reminders ask for permission (they are
                // set up first). The app refreshes these reminders again when
                // permission is given, so the user is asked only once.
                break
            case .authorized, .provisional, .ephemeral:
                Self.scheduleRefreshOnMain(self)
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    @MainActor
    private func refreshFromStore() {
        guard let store else { return }
        refresh(applications: store.applications, language: store.language)
    }

    private static func scheduleRefreshOnMain(_ coordinator: GrantReminderCoordinator) {
        Task { @MainActor in
            coordinator.refreshFromStore()
        }
    }

    private func scheduleCalendarNotification(for plan: ReminderPlan) {
        guard let center else { return }
        let content = notificationContent(for: plan)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger)
        center.add(request)
    }

    private func scheduleImmediateNotification(for plan: ReminderPlan) {
        guard let center else { return }
        let content = notificationContent(for: plan)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger)
        center.add(request)
    }

    private func notificationContent(for plan: ReminderPlan) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.userInfo = [
            "applicationID": plan.applicationID,
            "primaryLink": plan.primaryLink ?? "",
            "kind": plan.id.hasPrefix(Self.closedUnansweredIDPrefix) ? Self.closedUnansweredNotificationKind : "",
        ]
        return content
    }

    private func reminderPlans(
        for applications: [GrantApplication],
        language: AppLanguage,
        settings: CalendarReminderSettings
    ) -> [ReminderPlan] {
        applications.flatMap { application in
            plans(for: application, language: language, settings: settings)
        }
    }

    private func plans(
        for application: GrantApplication,
        language: AppLanguage,
        settings: CalendarReminderSettings
    ) -> [ReminderPlan] {
        let title = application.displayTitle.nonEmpty ?? language.text("Untitled grant", "Namnlöst anslag")
        return Self.reminderSchedule(for: application, settings: settings, calendar: Calendar.current).map { schedule in
            makePlan(
                id: schedule.id,
                fireDate: schedule.fireDate,
                title: Self.title(for: schedule.kind, settings: settings, language: language),
                body: title,
                application: application,
                immediate: true
            )
        }
    }

    /// Reminders that are already late are sent at once only when they were
    /// due within the last week, so old applications do not all send a
    /// notification the first time reminders are switched on.
    static let overdueWindowDays = 7

    static func overdueWindowStart(now: Date) -> Date {
        now.addingTimeInterval(-Double(overdueWindowDays) * 24 * 60 * 60)
    }

    static func title(for kind: GrantReminderKind, settings: CalendarReminderSettings, language: AppLanguage) -> String {
        switch kind {
        case .opens:
            return language.text("Grant opens today", "Anslag öppnar idag")
        case .closingSoon:
            return closingSoonTitle(days: settings.grantClosingLeadDays, language: language)
        case .decisionOverdue:
            return language.text("Expected decision date has passed", "Förväntat beslutsdatum har passerat")
        case .dispositionEndingSoon:
            return dispositionEndingTitle(months: settings.grantDispositionEndLeadMonths, language: language)
        case .dispositionEnded:
            return language.text("Disposition time has ended", "Disponeringstiden har passerat")
        case .repaymentOverdue:
            return language.text("Repayment date has passed", "Datum för återgäldande har passerat")
        case .closedUnanswered:
            return language.text("The call has closed – did you apply?", "Utlysningen har stängt – sökte du?")
        }
    }

    static let closedUnansweredIDPrefix = "grant-closed-unanswered"
    static let closedUnansweredNotificationKind = "grantClosedUnanswered"

    /// Which reminders an application gets and when. Nothing when reminders
    /// are switched off. Applications that were declined, withdrawn or not
    /// applied for get no reminders:
    /// - opens and closing soon: only applications still to apply for;
    /// - decision overdue: only applications waiting for a decision;
    /// - disposition time and repayment: only granted applications.
    static func reminderSchedule(
        for application: GrantApplication,
        settings: CalendarReminderSettings,
        calendar: Calendar
    ) -> [GrantReminderSchedule] {
        guard settings.grantRemindersEnabled else { return [] }
        var schedules: [GrantReminderSchedule] = []
        func add(_ kind: GrantReminderKind, idPrefix: String, anchor: Date, fireDay: Date) {
            schedules.append(
                GrantReminderSchedule(
                    id: "\(idPrefix)-\(application.id)-\(DateParsers.isoDay.string(from: anchor))",
                    kind: kind,
                    fireDate: reminderDate(on: fireDay, settings: settings, calendar: calendar),
                    applicationID: application.id
                )
            )
        }

        if application.isToApplyStatus, let opensDate = application.openDate {
            add(.opens, idPrefix: "grant-open", anchor: opensDate, fireDay: opensDate)
        }

        if application.isToApplyStatus,
           application.appliedOn?.trimmedOrNil == nil,
           let closeDate = application.closeDate,
           let closeReminderDate = calendar.date(byAdding: .day, value: -settings.grantClosingLeadDays, to: closeDate) {
            add(.closingSoon, idPrefix: "grant-close-soon", anchor: closeDate, fireDay: closeReminderDate)
        }

        if application.isToApplyStatus,
           application.appliedOn?.trimmedOrNil == nil,
           application.notAppliedOn?.trimmedOrNil == nil,
           let closeDate = application.closeDate,
           let dayAfterClosing = calendar.date(byAdding: .day, value: 1, to: closeDate) {
            add(.closedUnanswered, idPrefix: Self.closedUnansweredIDPrefix, anchor: closeDate, fireDay: dayAfterClosing)
        }

        if application.resultLabel == "Väntar svar",
           application.decisionDate == nil,
           let expectedDate = application.decisionExpectedDate,
           let overdueDate = calendar.date(byAdding: .day, value: settings.grantDecisionFollowUpDays, to: expectedDate) {
            add(.decisionOverdue, idPrefix: "grant-decision-overdue", anchor: expectedDate, fireDay: overdueDate)
        }

        if application.isGranted,
           (application.remainingGrantedAmountValue ?? 0) > 0,
           let lastDispositionDate = application.lastDispositionDate {
            let leadMonths = settings.grantDispositionEndLeadMonths
            if leadMonths > 0,
               let monthsBefore = calendar.date(byAdding: .month, value: -leadMonths, to: lastDispositionDate) {
                add(.dispositionEndingSoon, idPrefix: "grant-disposition-soon", anchor: lastDispositionDate, fireDay: monthsBefore)
            }
            add(.dispositionEnded, idPrefix: "grant-disposition-ended", anchor: lastDispositionDate, fireDay: lastDispositionDate)
        }

        if application.isGranted,
           let repaymentDue = application.receivedRepaymentDueOn.flatMap(DateParsers.isoDay.date(from:)),
           application.receivedRepaidOn?.trimmedOrNil == nil {
            add(.repaymentOverdue, idPrefix: "grant-repayment-overdue", anchor: repaymentDue, fireDay: repaymentDue)
        }

        return schedules
    }

    private func makePlan(
        id: String,
        fireDate: Date,
        title: String,
        body: String,
        application: GrantApplication,
        immediate: Bool
    ) -> ReminderPlan {
        ReminderPlan(
            id: id,
            fireDate: fireDate,
            title: title,
            body: body,
            applicationID: application.id,
            primaryLink: application.primaryLink,
            shouldFireImmediatelyIfOverdue: immediate
        )
    }

    private func reminderDate(on date: Date, settings: CalendarReminderSettings) -> Date {
        Self.reminderDate(on: date, settings: settings, calendar: Calendar.current)
    }

    /// The reminder is sent on the given day at the time in Settings >
    /// Calendar (default 09:00).
    static func reminderDate(on date: Date, settings: CalendarReminderSettings, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let time = settings.grantReminderHourMinute
        return calendar.date(byAdding: .minute, value: time.hour * 60 + time.minute, to: startOfDay) ?? startOfDay
    }

    static func closingSoonTitle(days: Int, language: AppLanguage) -> String {
        if days == 7 {
            return language.text("1 week left before closing", "1 vecka kvar innan stängning")
        }
        if days == 1 {
            return language.text("1 day left before closing", "1 dag kvar innan stängning")
        }
        return language.text("\(days) days left before closing", "\(days) dagar kvar innan stängning")
    }

    static func dispositionEndingTitle(months: Int, language: AppLanguage) -> String {
        if months == 1 {
            return language.text("1 month left of disposition time", "1 månad kvar av disponeringstid")
        }
        return language.text("\(months) months left of disposition time", "\(months) månader kvar av disponeringstid")
    }
}
