import AppKit
import Foundation
import UserNotifications

enum CalendarTaskReminderBadgeTarget: Hashable {
    case project(String)
    case organization(String)
    case publication(String)
    case application(String)
    case teachingAssignment(String)
    /// Round 7: tasks linked to a course or a doctoral candidate count on the
    /// teaching tab like tasks linked to a teaching assignment.
    case teachingCourse(String)
    case doctoralCandidate(String)
}

func calendarTeachingAssignmentTaskReminderID(assignmentID: String, taskID: String) -> String {
    "teaching-assignment-task:\(assignmentID):\(taskID)"
}

func calendarTaskReminderID(for source: CalendarWorkspaceEventSource?) -> String? {
    switch source {
    case let .projectTask(projectID, taskID):
        return "project-task:\(projectID):\(taskID)"
    case let .organizationTask(organizationID, taskID):
        return "organization-task:\(organizationID):\(taskID)"
    case let .publicationTask(publicationID, taskID):
        return "publication-task:\(publicationID):\(taskID)"
    case let .teachingTask(taskID):
        return "teaching-task:\(taskID)"
    default:
        return nil
    }
}

struct CalendarTaskReminderBadgeRouter {
    let validProjectIDs: Set<String>
    let validOrganizationIDs: Set<String>
    let validPublicationIDs: Set<String>
    let validApplicationIDs: Set<String>
    let validTeachingAssignmentIDs: Set<String>
    let validTeachingCourseIDs: Set<String>
    let validDoctoralCandidateIDs: Set<String>

    @MainActor
    init(store: GrantDataStore) {
        validProjectIDs = Set(store.projects.map(\.id))
        validOrganizationIDs = Set(store.organizations.map(\.id))
        validPublicationIDs = Set(store.publications.map(\.id))
        validApplicationIDs = Set(store.applications.map(\.id))
        validTeachingAssignmentIDs = Set(store.teachingAssignments.map(\.id))
        validTeachingCourseIDs = Set(store.teachingCourses.map(\.id))
        validDoctoralCandidateIDs = Set(store.doctoralCandidates.map(\.id))
    }

    func targets(
        source: CalendarWorkspaceEventSource? = nil,
        teachingAssignmentID: String? = nil,
        linkedProjectID: String? = nil,
        linkedPublicationID: String? = nil,
        linkedApplicationID: String? = nil
    ) -> Set<CalendarTaskReminderBadgeTarget> {
        var targets: Set<CalendarTaskReminderBadgeTarget> = []

        switch source {
        case let .projectTask(projectID, _):
            insert(projectID, ifPresentIn: validProjectIDs, as: CalendarTaskReminderBadgeTarget.project, into: &targets)
        case let .organizationTask(organizationID, _):
            insert(organizationID, ifPresentIn: validOrganizationIDs, as: CalendarTaskReminderBadgeTarget.organization, into: &targets)
        case let .publicationTask(publicationID, _):
            insert(publicationID, ifPresentIn: validPublicationIDs, as: CalendarTaskReminderBadgeTarget.publication, into: &targets)
        default:
            break
        }

        insert(linkedProjectID, ifPresentIn: validProjectIDs, as: CalendarTaskReminderBadgeTarget.project, into: &targets)
        insert(linkedPublicationID, ifPresentIn: validPublicationIDs, as: CalendarTaskReminderBadgeTarget.publication, into: &targets)
        insert(linkedApplicationID, ifPresentIn: validApplicationIDs, as: CalendarTaskReminderBadgeTarget.application, into: &targets)
        insert(teachingAssignmentID, ifPresentIn: validTeachingAssignmentIDs, as: CalendarTaskReminderBadgeTarget.teachingAssignment, into: &targets)
        return targets
    }

    func targets(
        source: CalendarWorkspaceEventSource? = nil,
        links: [TaskLink]
    ) -> Set<CalendarTaskReminderBadgeTarget> {
        var targets = targets(source: source)
        for link in links {
            switch link.kind {
            case .project:
                insert(link.targetID, ifPresentIn: validProjectIDs, as: CalendarTaskReminderBadgeTarget.project, into: &targets)
            case .organization:
                insert(link.targetID, ifPresentIn: validOrganizationIDs, as: CalendarTaskReminderBadgeTarget.organization, into: &targets)
            case .publication:
                insert(link.targetID, ifPresentIn: validPublicationIDs, as: CalendarTaskReminderBadgeTarget.publication, into: &targets)
            case .application:
                insert(link.targetID, ifPresentIn: validApplicationIDs, as: CalendarTaskReminderBadgeTarget.application, into: &targets)
            case .teachingAssignment:
                insert(link.targetID, ifPresentIn: validTeachingAssignmentIDs, as: CalendarTaskReminderBadgeTarget.teachingAssignment, into: &targets)
            case .teachingCourse:
                insert(link.targetID, ifPresentIn: validTeachingCourseIDs, as: CalendarTaskReminderBadgeTarget.teachingCourse, into: &targets)
            case .doctoralCandidate:
                insert(link.targetID, ifPresentIn: validDoctoralCandidateIDs, as: CalendarTaskReminderBadgeTarget.doctoralCandidate, into: &targets)
            default:
                continue
            }
        }
        return targets
    }

    private func insert(
        _ id: String?,
        ifPresentIn validIDs: Set<String>,
        as target: (String) -> CalendarTaskReminderBadgeTarget,
        into targets: inout Set<CalendarTaskReminderBadgeTarget>
    ) {
        guard let id = id?.trimmedOrNil, validIDs.contains(id) else { return }
        targets.insert(target(id))
    }
}

struct CalendarTaskReminderEntry: Hashable, Identifiable {
    let id: String
    let source: CalendarWorkspaceEventSource?
    let displayDate: Date
    let title: String
    let context: String
    let badgeTargets: Set<CalendarTaskReminderBadgeTarget>

    init(
        id: String,
        source: CalendarWorkspaceEventSource? = nil,
        displayDate: Date,
        title: String,
        context: String,
        badgeTargets: Set<CalendarTaskReminderBadgeTarget> = []
    ) {
        self.id = id
        self.source = source
        self.displayDate = displayDate
        self.title = title
        self.context = context
        self.badgeTargets = badgeTargets
    }
}

struct CalendarTaskReminderPlan: Identifiable {
    let id: String
    let dayString: String
    let fireDate: Date
    let title: String
    let body: String
    let entries: [CalendarTaskReminderEntry]
}

struct CalendarTaskReminderBadgeCounts: Equatable {
    let entries: [CalendarTaskReminderEntry]
    let projectCounts: [String: Int]
    let organizationCounts: [String: Int]
    let publicationCounts: [String: Int]
    let applicationCounts: [String: Int]
    let teachingAssignmentCounts: [String: Int]
    let teachingCourseCounts: [String: Int]
    let doctoralCandidateCounts: [String: Int]

    var totalCount: Int { entries.count }
    var calendarBadgeCount: Int { entries.lazy.filter { $0.source != nil }.count }
    var projectBadgeCount: Int { projectCounts.count }
    var organizationBadgeCount: Int { organizationCounts.count }
    var publicationBadgeCount: Int { publicationCounts.count }
    var applicationBadgeCount: Int { applicationCounts.count }
    /// Assignments, courses and doctoral candidates with a due task.
    var teachingBadgeCount: Int {
        teachingAssignmentCounts.count + teachingCourseCounts.count + doctoralCandidateCounts.count
    }

    func contains(source: CalendarWorkspaceEventSource) -> Bool {
        entries.contains { $0.source == source }
    }
}

func calendarTaskReminderBadgeCounts(
    entries: [CalendarTaskReminderEntry]
) -> CalendarTaskReminderBadgeCounts {
    var projectCounts: [String: Int] = [:]
    var organizationCounts: [String: Int] = [:]
    var publicationCounts: [String: Int] = [:]
    var applicationCounts: [String: Int] = [:]
    var teachingAssignmentCounts: [String: Int] = [:]
    var teachingCourseCounts: [String: Int] = [:]
    var doctoralCandidateCounts: [String: Int] = [:]

    for entry in entries {
        for target in entry.badgeTargets {
            switch target {
            case let .project(id): projectCounts[id, default: 0] += 1
            case let .organization(id): organizationCounts[id, default: 0] += 1
            case let .publication(id): publicationCounts[id, default: 0] += 1
            case let .application(id): applicationCounts[id, default: 0] += 1
            case let .teachingAssignment(id): teachingAssignmentCounts[id, default: 0] += 1
            case let .teachingCourse(id): teachingCourseCounts[id, default: 0] += 1
            case let .doctoralCandidate(id): doctoralCandidateCounts[id, default: 0] += 1
            }
        }
    }

    return CalendarTaskReminderBadgeCounts(
        entries: entries,
        projectCounts: projectCounts,
        organizationCounts: organizationCounts,
        publicationCounts: publicationCounts,
        applicationCounts: applicationCounts,
        teachingAssignmentCounts: teachingAssignmentCounts,
        teachingCourseCounts: teachingCourseCounts,
        doctoralCandidateCounts: doctoralCandidateCounts
    )
}

func calendarTaskReminderBadgeHelp(
    entries: [CalendarTaskReminderEntry],
    language: AppLanguage,
    matching predicate: (CalendarTaskReminderEntry) -> Bool
) -> String? {
    let matchingEntries = entries
        .filter(predicate)
        .sorted { $0.displayDate < $1.displayDate }
    guard let first = matchingEntries.first else { return nil }

    let count = matchingEntries.count
    let countText = language.text(
        count == 1 ? "1 active reminder" : "\(count) active reminders",
        count == 1 ? "1 aktiv påminnelse" : "\(count) aktiva påminnelser"
    )
    let dateText = DateParsers.isoDay.string(from: first.displayDate)
    let context = first.context.trimmedOrNil.map { " – \($0)" } ?? ""
    let additionalText = count > 1
        ? language.text(" (+\(count - 1) more)", " (+\(count - 1) till)")
        : ""
    return "\(countText): \(first.title) (\(dateText))\(context)\(additionalText)"
}

func calendarTaskShowsActiveBadge(
    deadline: String,
    title: String,
    isCompleted: Bool,
    isBadgeHidden: Bool = false,
    calendar: Calendar = .current,
    now: Date = Date()
) -> Bool {
    let today = calendar.startOfDay(for: now)
    guard !isBadgeHidden,
          !isCompleted,
          title.nonEmpty != nil,
          let deadlineDate = DateParsers.isoDay.date(from: deadline) else {
        return false
    }
    let displayDate = effectiveCalendarTaskDate(
        deadline: deadlineDate,
        completedOn: nil,
        isCompleted: false,
        today: today,
        calendar: calendar,
        policy: .rollOverPastDue
    )
    return calendar.isDate(displayDate, inSameDayAs: today)
}

func calendarTaskIsOverdue(
    deadline: String,
    title: String,
    isCompleted: Bool,
    calendar: Calendar = .current,
    now: Date = Date()
) -> Bool {
    guard !isCompleted,
          title.nonEmpty != nil,
          let deadlineDate = DateParsers.isoDay.date(from: deadline) else {
        return false
    }
    return calendar.startOfDay(for: deadlineDate) < calendar.startOfDay(for: now)
}

@MainActor
func calendarTaskReminderEntries(
    store: GrantDataStore,
    language: AppLanguage,
    calendar: Calendar,
    today: Date = Date(),
    through endDate: Date? = nil
) -> [CalendarTaskReminderEntry] {
    let todayStart = calendar.startOfDay(for: today)
    let end = endDate.map { calendar.startOfDay(for: $0) }
    let badgeRouter = CalendarTaskReminderBadgeRouter(store: store)
    var entries: [CalendarTaskReminderEntry] = []

    func include(displayDate: Date) -> Bool {
        let normalized = calendar.startOfDay(for: displayDate)
        guard normalized >= todayStart else { return false }
        if let end {
            return normalized <= end
        }
        return true
    }

    // A task edited centrally supersedes the legacy copy on the record;
    // reminding from both double-counted badges and fired on stale dates.
    let centralTaskIDs = Set(store.taskItems.map(\.id))
    for project in store.projects {
        let context = project.displayName(for: language)
        for task in project.projectTasks {
            guard !centralTaskIDs.contains(task.id),
                  !task.isEmpty,
                  !task.isCompleted,
                  let title = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                continue
            }
            let displayDate = effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: todayStart,
                calendar: calendar,
                policy: .rollOverPastDue
            )
            guard include(displayDate: displayDate) else { continue }
            entries.append(
                CalendarTaskReminderEntry(
                    id: "project-task:\(project.id):\(task.id)",
                    source: .projectTask(projectID: project.id, taskID: task.id),
                    displayDate: displayDate,
                    title: title,
                    context: context,
                    badgeTargets: badgeRouter.targets(
                        source: .projectTask(projectID: project.id, taskID: task.id),
                        linkedPublicationID: task.publicationID,
                        linkedApplicationID: task.applicationID
                    )
                )
            )
        }
    }

    for organization in store.organizations {
        let context = organization.displayName(for: language)
        for task in organization.projectTasks {
            guard !centralTaskIDs.contains(task.id),
                  !task.isEmpty,
                  !task.isCompleted,
                  let title = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                continue
            }
            let displayDate = effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: todayStart,
                calendar: calendar,
                policy: .rollOverPastDue
            )
            guard include(displayDate: displayDate) else { continue }
            entries.append(
                CalendarTaskReminderEntry(
                    id: "organization-task:\(organization.id):\(task.id)",
                    source: .organizationTask(organizationID: organization.id, taskID: task.id),
                    displayDate: displayDate,
                    title: title,
                    context: context,
                    badgeTargets: badgeRouter.targets(
                        source: .organizationTask(organizationID: organization.id, taskID: task.id),
                        linkedPublicationID: task.publicationID,
                        linkedApplicationID: task.applicationID
                    )
                )
            )
        }
    }

    for publication in store.publications {
        let context = publication.title.nonEmpty ?? language.text("Untitled publication", "Namnlös publikation")
        for task in publication.publicationTasks {
            guard !centralTaskIDs.contains(task.id),
                  !task.isEmpty,
                  !task.isCompleted,
                  let title = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                continue
            }
            let displayDate = effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: todayStart,
                calendar: calendar,
                policy: .rollOverPastDue
            )
            guard include(displayDate: displayDate) else { continue }
            entries.append(
                CalendarTaskReminderEntry(
                    id: "publication-task:\(publication.id):\(task.id)",
                    source: .publicationTask(publicationID: publication.id, taskID: task.id),
                    displayDate: displayDate,
                    title: title,
                    context: context,
                    badgeTargets: badgeRouter.targets(
                        source: .publicationTask(publicationID: publication.id, taskID: task.id),
                        linkedProjectID: task.projectID,
                        linkedPublicationID: task.publicationID,
                        linkedApplicationID: task.applicationID
                    )
                )
            )
        }
    }

    // Central tasks supersede legacy host-owned rows with the same identifier.
    // They must be included here as well as in CalendarWorkspaceView; otherwise
    // a moved central task can leave an obsolete badge behind in the sidebar.
    let centralTaskContext = language.text("General", "Allmänt")
    func linkedCentralTaskContext(for task: TaskItem) -> String {
        for link in task.links {
            switch link.kind {
            case .project:
                if let project = store.projects.first(where: { $0.id == link.targetID }) {
                    return project.displayName(for: language)
                }
            case .organization:
                if let organization = store.organizations.first(where: { $0.id == link.targetID }) {
                    return organization.displayName(for: language)
                }
            case .publication:
                if let title = store.publications.first(where: { $0.id == link.targetID })?.title.nonEmpty {
                    return title
                }
            case .teachingAssignment:
                if let assignment = store.teachingAssignments.first(where: { $0.id == link.targetID }),
                   let name = assignment.activityName.nonEmpty ?? assignment.programName.nonEmpty {
                    return name
                }
            case .teachingCourse:
                if let course = store.teachingCourses.first(where: { $0.id == link.targetID }) {
                    return calendarTeachingCourseLabel(course, language: language)
                }
            case .doctoralCandidate:
                if let name = store.doctoralCandidates.first(where: { $0.id == link.targetID })?.candidateName.nonEmpty {
                    return name
                }
            case .congress:
                if let title = store.organizations
                    .first(where: { $0.id == link.ownerID })?
                    .congresses.first(where: { $0.id == link.targetID })?
                    .title.nonEmpty {
                    return title
                }
            default:
                continue
            }
        }
        return centralTaskContext
    }
    for task in store.taskItems {
        guard !task.isEmpty,
              !task.isCompleted,
              let title = task.comment.nonEmpty,
              let deadline = DateParsers.isoDay.date(from: task.deadline) else {
            continue
        }
        let displayDate = effectiveCalendarTaskDate(
            deadline: deadline,
            completedOn: task.completedOn,
            isCompleted: task.isCompleted,
            today: todayStart,
            calendar: calendar,
            policy: .rollOverPastDue
        )
        guard include(displayDate: displayDate) else { continue }
        entries.append(
            CalendarTaskReminderEntry(
                id: "teaching-task:\(task.id)",
                source: .teachingTask(taskID: task.id),
                displayDate: displayDate,
                title: title,
                context: linkedCentralTaskContext(for: task),
                badgeTargets: badgeRouter.targets(
                    source: .teachingTask(taskID: task.id),
                    links: task.links
                )
            )
        )
    }

    let teachingContext = language.text("General", "Allmänt")
    for task in store.teachingWorkspaceTasks where !centralTaskIDs.contains(task.id) {
        guard !task.isEmpty,
              !task.isCompleted,
              let title = task.comment.nonEmpty,
              let deadline = DateParsers.isoDay.date(from: task.deadline) else {
            continue
        }
        let displayDate = effectiveCalendarTaskDate(
            deadline: deadline,
            completedOn: task.completedOn,
            isCompleted: task.isCompleted,
            today: todayStart,
            calendar: calendar,
            policy: .rollOverPastDue
        )
        guard include(displayDate: displayDate) else { continue }
        entries.append(
            CalendarTaskReminderEntry(
                id: "teaching-task:\(task.id)",
                source: .teachingTask(taskID: task.id),
                displayDate: displayDate,
                title: title,
                context: teachingContext,
                badgeTargets: badgeRouter.targets(
                    source: .teachingTask(taskID: task.id),
                    linkedProjectID: task.projectID,
                    linkedPublicationID: task.publicationID,
                    linkedApplicationID: task.applicationID
                )
            )
        )
    }

    for assignment in store.teachingAssignments {
        let context = assignment.activityName.nonEmpty
            ?? assignment.programName.nonEmpty
            ?? language.text("Teaching assignment", "Undervisningsuppdrag")
        for task in assignment.tasks {
            guard !centralTaskIDs.contains(task.id),
                  !task.isEmpty,
                  !task.isCompleted,
                  let title = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                continue
            }
            let displayDate = effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: todayStart,
                calendar: calendar,
                policy: .rollOverPastDue
            )
            guard include(displayDate: displayDate) else { continue }
            entries.append(
                CalendarTaskReminderEntry(
                    id: calendarTeachingAssignmentTaskReminderID(assignmentID: assignment.id, taskID: task.id),
                    displayDate: displayDate,
                    title: title,
                    context: context,
                    badgeTargets: badgeRouter.targets(
                        teachingAssignmentID: assignment.id,
                        linkedProjectID: task.projectID,
                        linkedPublicationID: task.publicationID,
                        linkedApplicationID: task.applicationID
                    )
                )
            )
        }
    }

    return entries.sorted { lhs, rhs in
        if lhs.displayDate != rhs.displayDate {
            return lhs.displayDate < rhs.displayDate
        }
        let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }
        let contextComparison = lhs.context.localizedStandardCompare(rhs.context)
        if contextComparison != .orderedSame {
            return contextComparison == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}

/// The daily task notification is sent at the time in Settings > Calendar
/// (default 12:00).
func calendarTaskReminderFireDate(
    on day: Date,
    calendar: Calendar,
    settings: CalendarReminderSettings = .standard
) -> Date {
    let startOfDay = calendar.startOfDay(for: day)
    let time = settings.taskNotificationHourMinute
    return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: startOfDay) ?? startOfDay
}

/// Not used by the Dock badge: the badge counts today's tasks and is refreshed
/// at midnight and after every change, so there is no 18:00 time to set.
func calendarTaskBadgeDate(on day: Date, calendar: Calendar) -> Date {
    let startOfDay = calendar.startOfDay(for: day)
    return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: startOfDay) ?? startOfDay
}

@MainActor
func calendarTaskDockBadgeEntries(
    store: GrantDataStore,
    language: AppLanguage,
    calendar: Calendar,
    now: Date = Date()
) -> [CalendarTaskReminderEntry] {
    let today = calendar.startOfDay(for: now)
    return calendarTaskReminderEntries(
        store: store,
        language: language,
        calendar: calendar,
        today: today,
        through: today
    ).filter { !store.isCalendarTaskBadgeHidden($0.id) }
}

@MainActor
func calendarTaskReminderPlans(
    store: GrantDataStore,
    language: AppLanguage,
    calendar: Calendar,
    now: Date = Date(),
    horizonDays: Int = 366
) -> [CalendarTaskReminderPlan] {
    let today = calendar.startOfDay(for: now)
    let reminderSettings = store.calendarReminderSettings
    let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: today) ?? today
    let entries = calendarTaskReminderEntries(
        store: store,
        language: language,
        calendar: calendar,
        today: today,
        through: horizonEnd
    )
    let grouped = Dictionary(grouping: entries) { entry in
        DateParsers.isoDay.string(from: calendar.startOfDay(for: entry.displayDate))
    }

    return grouped.keys.sorted().compactMap { dayString in
        guard let day = DateParsers.isoDay.date(from: dayString) else { return nil }
        let dayEntries = (grouped[dayString] ?? []).sorted { lhs, rhs in
            if lhs.title != rhs.title {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
        guard !dayEntries.isEmpty else { return nil }
        let title = calendarTaskReminderTitle(count: dayEntries.count, language: language)
        let body = calendarTaskReminderBody(entries: dayEntries, language: language)
        return CalendarTaskReminderPlan(
            id: "calendar-task-reminder-\(dayString)",
            dayString: dayString,
            fireDate: calendarTaskReminderFireDate(on: day, calendar: calendar, settings: reminderSettings),
            title: title,
            body: body,
            entries: dayEntries
        )
    }
}

func calendarTaskReminderTitle(count: Int, language: AppLanguage) -> String {
    if count == 1 {
        return language.text("Unresolved task today", "Olöst uppgift idag")
    }
    return language.text("\(count) unresolved tasks today", "\(count) olösta uppgifter idag")
}

func calendarTaskReminderBody(entries: [CalendarTaskReminderEntry], language: AppLanguage) -> String {
    let visibleEntries = entries.prefix(4).map { entry in
        if entry.context.trimmedOrNil == nil {
            return entry.title
        }
        return "\(entry.title) (\(entry.context))"
    }
    let hiddenCount = entries.count - visibleEntries.count
    let suffix: [String]
    if hiddenCount > 0 {
        suffix = [language.text("+ \(hiddenCount) more", "+ \(hiddenCount) till")]
    } else {
        suffix = []
    }
    return (visibleEntries + suffix).joined(separator: "\n")
}

final class CalendarTaskReminderCoordinator: NSObject, @unchecked Sendable {
    private weak var store: GrantDataStore?
    private var center: UNUserNotificationCenter?
    private let scheduledDefaultsKey = AppRuntime.scheduledCalendarTaskReminderDefaultsKey
    private var badgeTimer: Timer?

    @MainActor
    func configure(store: GrantDataStore, notificationCenter: UNUserNotificationCenter? = nil) {
        self.store = store
        if let notificationCenter {
            center = notificationCenter
            requestAuthorizationIfNeeded()
        }
        refresh(store: store, language: store.language)
    }

    @MainActor
    func disableNotifications() {
        guard let center else { return }
        let ids = UserDefaults.standard.stringArray(forKey: scheduledDefaultsKey) ?? []
        center.removePendingNotificationRequests(withIdentifiers: ids)
        UserDefaults.standard.removeObject(forKey: scheduledDefaultsKey)
        self.center = nil
    }

    @MainActor
    func refresh(store: GrantDataStore, language: AppLanguage) {
        refreshScheduledNotifications(store: store, language: language)
        refreshDockBadge(store: store, language: language)
        scheduleNextBadgeRefresh(store: store)
    }

    @MainActor
    func refreshFromStore() {
        guard let store else {
            clearDockBadge()
            return
        }
        refresh(store: store, language: store.language)
    }

    /// Updates the in-app and Dock badge state without rescheduling notifications.
    ///
    /// Task edits should be reflected immediately; notification requests can still
    /// be coalesced separately while the user is editing related fields.
    @MainActor
    func refreshBadgeEntriesFromStore() {
        guard let store else {
            clearDockBadge()
            return
        }
        refreshDockBadge(store: store, language: store.language)
    }

    @MainActor
    func clearDockBadge() {
        store?.updateCalendarTaskReminderBadgeEntries([])
        NSApplication.shared.dockTile.badgeLabel = nil
    }

    @MainActor
    private func refreshScheduledNotifications(store: GrantDataStore, language: AppLanguage) {
        guard let center else { return }
        let now = Date()
        let plans = calendarTaskReminderPlans(
            store: store,
            language: language,
            calendar: Calendar.current,
            now: now
        )
        let futurePlans = plans.filter { $0.fireDate > now.addingTimeInterval(1) }
        let oldScheduledIDs = Set(UserDefaults.standard.stringArray(forKey: scheduledDefaultsKey) ?? [])
        let scheduledIDs = Set(futurePlans.map(\.id))

        center.removePendingNotificationRequests(withIdentifiers: Array(oldScheduledIDs.union(scheduledIDs)))
        UserDefaults.standard.removeObject(forKey: scheduledDefaultsKey)
        let group = DispatchGroup()
        let successfulIDs = LockedNotificationIdentifierSet()
        for plan in futurePlans {
            group.enter()
            scheduleNotification(for: plan) { error in
                if error == nil {
                    successfulIDs.insert(plan.id)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            UserDefaults.standard.set(Array(successfulIDs.values), forKey: self.scheduledDefaultsKey)
        }
    }

    @MainActor
    private func refreshDockBadge(store: GrantDataStore, language: AppLanguage) {
        let now = Date()
        let calendar = Calendar.current
        let entries = calendarTaskDockBadgeEntries(
            store: store,
            language: language,
            calendar: calendar,
            now: now
        )
        store.updateCalendarTaskReminderBadgeEntries(entries)
        NSApplication.shared.dockTile.badgeLabel = entries.isEmpty ? nil : "\(entries.count)"
    }

    @MainActor
    private func scheduleNextBadgeRefresh(store: GrantDataStore) {
        badgeTimer?.invalidate()
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(24 * 60 * 60)
        let nextFireDate = calendar.startOfDay(for: tomorrow)

        let timer = Timer(fire: nextFireDate, interval: 0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let store = self.store else { return }
                self.refresh(store: store, language: store.language)
            }
        }
        badgeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleNotification(
        for plan: CalendarTaskReminderPlan,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        guard let center else {
            completion(nil)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.userInfo = [
            "kind": "calendarTaskReminder",
            "dayString": plan.dayString,
        ]
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: plan.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(
            UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger),
            withCompletionHandler: completion
        )
    }

    private func requestAuthorizationIfNeeded() {
        guard let center else { return }
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                self.center?.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    guard granted else { return }
                    Task { @MainActor in
                        self.refreshFromStore()
                        // Application reminders reuse this permission.
                        NotificationCenter.default.post(name: .footprintNotificationAuthorizationGranted, object: nil)
                    }
                }
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in
                    self.refreshFromStore()
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }
}

private final class LockedNotificationIdentifierSet: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Set<String> = []

    func insert(_ value: String) {
        lock.lock()
        storage.insert(value)
        lock.unlock()
    }

    var values: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
