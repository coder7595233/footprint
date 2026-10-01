import SwiftUI

enum CalendarLinkedEventScope {
    case researcher(String)
    case project(String)
    case application(String)
    case publication(String)
    /// Round 7: by id only. Activities whose doctoral candidate links contain
    /// the candidate, and tasks linked to the candidate.
    case doctoralCandidate(String)
    /// Activities and tasks linked to the teaching assignment.
    case teachingAssignment(String)
    /// Activities and tasks linked to the course, or to one of its
    /// teaching assignments.
    case teachingCourse(String)
}

struct CalendarLinkedEventRow: Identifiable, Equatable {
    let id: String
    let source: CalendarWorkspaceEventSource
    let displayDate: Date
    let primaryText: String
    let secondaryText: String
}

private let linkedCalendarSomalilandToken = "[[SOMALILAND_FLAG]]"

@MainActor
func calendarLinkedEventRows(
    store: GrantDataStore,
    language: AppLanguage,
    scope: CalendarLinkedEventScope,
    includesTasks: Bool = false,
    includesPastEvents: Bool = false
) -> [CalendarLinkedEventRow] {
    let calendar = footprintCalendar(for: language, weekStart: store.calendarWeekdayChoice)
    let index = store.cachedCalendarLinkedEventIndex()
    switch scope {
    case let .researcher(name):
        return calendarLinkedResearcherEventRows(
            store: store,
            index: index,
            language: language,
            calendar: calendar,
            researcherName: name,
            upcomingOnly: !includesPastEvents
        )
    case let .project(projectID):
        return calendarLinkedProjectEventRows(
            store: store,
            index: index,
            language: language,
            calendar: calendar,
            projectID: projectID,
            upcomingOnly: !includesPastEvents
        )
        .filter { includesTasks || $0.source.taskKind == nil }
    case let .application(applicationID):
        return calendarLinkedApplicationEventRows(
            store: store,
            index: index,
            language: language,
            calendar: calendar,
            applicationID: applicationID
        )
        .filter { includesTasks || $0.source.taskKind == nil }
    case let .publication(publicationID):
        return calendarLinkedPublicationEventRows(
            store: store,
            index: index,
            language: language,
            calendar: calendar,
            publicationID: publicationID,
            upcomingOnly: !includesPastEvents
        )
        .filter { includesTasks || $0.source.taskKind == nil }
    case .doctoralCandidate, .teachingAssignment, .teachingCourse:
        let links = calendarLinkedIDScopeLinks(store: store, scope: scope)
        return calendarLinkedIDEventRows(
            store: store,
            language: language,
            calendar: calendar,
            links: links,
            upcomingOnly: !includesPastEvents
        )
        .filter { includesTasks || $0.source.taskKind == nil }
    }
}

/// Round 7: which ids a doctoral candidate, teaching assignment or course
/// scope matches. Only explicit id links count; names and projects do not.
struct CalendarLinkedIDScopeLinks: Equatable {
    var doctoralCandidateIDs: Set<String> = []
    var teachingAssignmentIDs: Set<String> = []
    var teachingCourseIDs: Set<String> = []

    func matches(task: TaskItem) -> Bool {
        task.links.contains { link in
            let id = link.targetID.trimmingCharacters(in: .whitespacesAndNewlines)
            switch link.kind {
            case .doctoralCandidate: return doctoralCandidateIDs.contains(id)
            case .teachingAssignment: return teachingAssignmentIDs.contains(id)
            case .teachingCourse: return teachingCourseIDs.contains(id)
            default: return false
            }
        }
    }

    func matches(meeting: CalendarMeetingRecord) -> Bool {
        calendarMeetingDoctoralCandidateIDs(meeting).contains(where: { doctoralCandidateIDs.contains($0) })
            || calendarMeetingTeachingAssignmentIDs(meeting).contains(where: { teachingAssignmentIDs.contains($0) })
            || meeting.teachingCourseIDs.compactMap(\.trimmedOrNil).contains(where: { teachingCourseIDs.contains($0) })
    }
}

/// The id links a scope stands for. A course also stands for its teaching
/// assignments.
@MainActor
func calendarLinkedIDScopeLinks(store: GrantDataStore, scope: CalendarLinkedEventScope) -> CalendarLinkedIDScopeLinks {
    switch scope {
    case let .doctoralCandidate(id):
        return CalendarLinkedIDScopeLinks(doctoralCandidateIDs: [id])
    case let .teachingAssignment(id):
        return CalendarLinkedIDScopeLinks(teachingAssignmentIDs: [id])
    case let .teachingCourse(id):
        let assignmentIDs = store.teachingAssignments
            .filter { $0.contextID?.trimmedOrNil == id }
            .map(\.id)
        return CalendarLinkedIDScopeLinks(teachingAssignmentIDs: Set(assignmentIDs), teachingCourseIDs: [id])
    default:
        return CalendarLinkedIDScopeLinks()
    }
}

/// Activities and shared tasks that carry one of the scope's id links.
@MainActor
private func calendarLinkedIDEventRows(
    store: GrantDataStore,
    language: AppLanguage,
    calendar: Calendar,
    links: CalendarLinkedIDScopeLinks,
    upcomingOnly: Bool
) -> [CalendarLinkedEventRow] {
    let today = calendar.startOfDay(for: Date())
    var candidates: [CalendarLinkedEventCandidate] = []

    candidates.append(contentsOf: store.taskItems.compactMap { task -> CalendarLinkedEventCandidate? in
        guard !task.isEmpty,
              let comment = task.comment.nonEmpty,
              let deadline = DateParsers.isoDay.date(from: task.deadline),
              links.matches(task: task) else {
            return nil
        }
        let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
        return CalendarLinkedEventCandidate(
            id: "teaching-task:\(task.id)",
            source: .teachingTask(taskID: task.id),
            displayDate: effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            ),
            timeText: "",
            kind: .taskDeadline,
            primaryText: calendarLinkedComposePrimaryText(
                title: comment,
                associationText: participantText,
                placeText: nil
            )
        )
    })

    candidates.append(contentsOf: store.calendarMeetingRecords.compactMap { meeting -> CalendarLinkedEventCandidate? in
        guard links.matches(meeting: meeting),
              let date = DateParsers.isoDay.date(from: meeting.date) else {
            return nil
        }
        let participantText = meeting.participantNames.joined(separator: ", ").trimmedOrNil
        let placeText: String? = {
            if CalendarMeetingMode(rawValue: meeting.meetingMode) == .online {
                return language.text("Online", "Online")
            }
            return formattedCalendarPlace(
                city: meeting.place,
                country: meeting.country,
                language: language,
                countryDisplayMode: store.calendarCountryDisplayMode
            )
            .trimmedOrNil
        }()
        return CalendarLinkedEventCandidate(
            id: "meeting:\(meeting.id)",
            source: .meeting(meeting.id),
            displayDate: calendar.startOfDay(for: date),
            timeText: timeRangeText(start: meeting.startTime, end: meeting.endTime),
            kind: .meeting,
            primaryText: calendarLinkedComposePrimaryText(
                title: meeting.title.nonEmpty ?? language.text("Activity", "Aktivitet"),
                associationText: participantText,
                placeText: placeText
            )
        )
    })

    return calendarLinkedRows(
        from: candidates,
        language: language,
        calendar: calendar,
        upcomingOnly: upcomingOnly
    )
}

@MainActor
func calendarLinkedMeetingRecords(
    store: GrantDataStore,
    rows: [CalendarLinkedEventRow]
) -> [CalendarMeetingRecord] {
    let index = store.cachedCalendarLinkedEventIndex()
    return rows.compactMap { row in
        guard case let .meeting(id) = row.source else { return nil }
        return index.meetingsByID[id]
    }
}

@MainActor
private extension GrantDataStore {
    func cachedCalendarLinkedEventIndex() -> CalendarLinkedEventIndex {
        if let cache = calendarLinkedEventIndexCache,
           cache.generation == calendarContentGeneration {
            return cache.index
        }
        let index = CalendarLinkedEventIndex(store: self)
        calendarLinkedEventIndexBuildCount += 1
        calendarLinkedEventIndexCache = (calendarContentGeneration, index)
        return index
    }
}

private extension CalendarWorkspaceEventSource {
    var taskKind: Void? {
        switch self {
        case .organizationTask, .projectTask, .publicationTask, .teachingTask:
            return ()
        default:
            return nil
        }
    }
}

private struct CalendarLinkedEventCandidate {
    let id: String
    let source: CalendarWorkspaceEventSource
    let displayDate: Date
    let timeText: String
    let kind: CalendarWorkspaceEventKind
    let primaryText: String
}

func calendarLinkedDictionary<Value>(
    _ values: [Value],
    keyedBy key: (Value) -> String
) -> [String: Value] {
    values.reduce(into: [:]) { result, value in
        let id = key(value)
        if result[id] == nil {
            result[id] = value
        }
    }
}

struct CalendarLinkedEventIndex {
    struct ProjectTaskReference {
        let ownerID: String
        let task: ProjectTaskItem
    }

    struct PublicationTaskReference {
        let ownerID: String
        let task: PublicationTaskItem
    }

    let projectsByID: [String: ProjectRecord]
    let applicationsByID: [String: GrantApplication]
    let publicationsByID: [String: PublicationRecord]
    let meetingsByID: [String: CalendarMeetingRecord]
    let mediaAppearancesByID: [String: CVMediaAppearance]
    let teachingTasksByID: [String: PublicationTaskItem]
    let projectTasksByKey: [String: ProjectTaskItem]
    let organizationTasksByKey: [String: ProjectTaskItem]
    let publicationTasksByKey: [String: PublicationTaskItem]

    let projectTasksByApplicationID: [String: [ProjectTaskReference]]
    let organizationTasksByApplicationID: [String: [ProjectTaskReference]]
    let publicationTasksByApplicationID: [String: [PublicationTaskReference]]
    let teachingTasksByApplicationID: [String: [PublicationTaskItem]]
    let publicationsByProjectID: [String: [PublicationRecord]]

    @MainActor
    init(store: GrantDataStore) {
        projectsByID = calendarLinkedDictionary(store.projects, keyedBy: \.id)
        applicationsByID = calendarLinkedDictionary(store.applications, keyedBy: \.id)
        publicationsByID = calendarLinkedDictionary(store.publications, keyedBy: \.id)
        meetingsByID = calendarLinkedDictionary(store.calendarMeetingRecords, keyedBy: \.id)
        mediaAppearancesByID = calendarLinkedDictionary(store.cvMediaAppearances, keyedBy: \.id)
        // A task edited centrally supersedes the legacy copy on the record;
        // without this filter the linked lists showed stale dates and their
        // row clicks revealed calendar days that no longer hold the task.
        let centralTaskIDs = Set(store.taskItems.map(\.id))
        let legacyTeachingTasks = store.teachingWorkspaceTasks
            .filter { !centralTaskIDs.contains($0.id) }
        teachingTasksByID = calendarLinkedDictionary(legacyTeachingTasks, keyedBy: \.id)
        let projectReferences = store.projects.flatMap { project in
            project.projectTasks
                .filter { !centralTaskIDs.contains($0.id) }
                .map { ProjectTaskReference(ownerID: project.id, task: $0) }
        }
        let organizationReferences = store.organizations.flatMap { organization in
            organization.projectTasks
                .filter { !centralTaskIDs.contains($0.id) }
                .map { ProjectTaskReference(ownerID: organization.id, task: $0) }
        }
        let publicationReferences = store.publications.flatMap { publication in
            publication.publicationTasks
                .filter { !centralTaskIDs.contains($0.id) }
                .map { PublicationTaskReference(ownerID: publication.id, task: $0) }
        }

        projectTasksByKey = calendarLinkedDictionary(projectReferences) {
            Self.taskKey(ownerID: $0.ownerID, taskID: $0.task.id)
        }
        .mapValues(\.task)
        organizationTasksByKey = calendarLinkedDictionary(organizationReferences) {
            Self.taskKey(ownerID: $0.ownerID, taskID: $0.task.id)
        }
        .mapValues(\.task)
        publicationTasksByKey = calendarLinkedDictionary(publicationReferences) {
            Self.taskKey(ownerID: $0.ownerID, taskID: $0.task.id)
        }
        .mapValues(\.task)
        projectTasksByApplicationID = Dictionary(
            grouping: projectReferences.compactMap { reference in
                reference.task.applicationID?.trimmedOrNil.map { ($0, reference) }
            },
            by: \.0
        )
        .mapValues { $0.map(\.1) }
        organizationTasksByApplicationID = Dictionary(
            grouping: organizationReferences.compactMap { reference in
                reference.task.applicationID?.trimmedOrNil.map { ($0, reference) }
            },
            by: \.0
        )
        .mapValues { $0.map(\.1) }
        publicationTasksByApplicationID = Dictionary(
            grouping: publicationReferences.compactMap { reference in
                reference.task.applicationID?.trimmedOrNil.map { ($0, reference) }
            },
            by: \.0
        )
        .mapValues { $0.map(\.1) }
        teachingTasksByApplicationID = Dictionary(
            grouping: legacyTeachingTasks.compactMap { task in
                task.applicationID?.trimmedOrNil.map { ($0, task) }
            },
            by: \.0
        )
        .mapValues { $0.map(\.1) }
        publicationsByProjectID = Dictionary(
            grouping: store.publications.compactMap { publication in
                publication.projectID?.trimmedOrNil.map { ($0, publication) }
            },
            by: \.0
        )
        .mapValues { $0.map(\.1) }
    }

    static func taskKey(ownerID: String, taskID: String) -> String {
        "\(ownerID)\u{1F}\(taskID)"
    }
}

@MainActor
private func calendarLinkedResearcherEventRows(
    store: GrantDataStore,
    index: CalendarLinkedEventIndex,
    language: AppLanguage,
    calendar: Calendar,
    researcherName: String,
    upcomingOnly: Bool = true
) -> [CalendarLinkedEventRow] {
    let today = calendar.startOfDay(for: Date())
    let normalizedResearcherName = researcherName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedResearcherName.isEmpty else { return [] }
    // F13d: the researcher link first, the written name as fallback, so a
    // record written with an older spelling still belongs to the researcher.
    let researcherID = store.researcherID(forPresentedName: normalizedResearcherName)
    func involvesResearcher(ids: [String], names: [String]) -> Bool {
        store.personList(
            ids: ids,
            names: names,
            includesResearcherID: researcherID,
            orName: normalizedResearcherName
        )
    }

    // A task edited centrally supersedes the legacy copy on the record.
    let centralTaskIDs = Set(store.taskItems.map(\.id))
    var candidates: [CalendarLinkedEventCandidate] = []

    candidates.append(contentsOf: store.taskItems.compactMap { task -> CalendarLinkedEventCandidate? in
        guard !task.isEmpty,
              let comment = task.comment.nonEmpty,
              let deadline = DateParsers.isoDay.date(from: task.deadline),
              involvesResearcher(ids: task.participantAuthorIDs, names: task.participantNames) else {
            return nil
        }
        let displayDate = effectiveCalendarTaskDate(
            deadline: deadline,
            completedOn: task.completedOn,
            isCompleted: task.isCompleted,
            today: today,
            calendar: calendar,
            policy: .rollOverPastDue
        )
        let projectText = centralTaskProjectLabels(task: task, index: index, language: language)
            .joined(separator: ", ")
            .trimmedOrNil
        return CalendarLinkedEventCandidate(
            id: "teaching-task:\(task.id)",
            source: .teachingTask(taskID: task.id),
            displayDate: displayDate,
            timeText: "",
            kind: .taskDeadline,
            primaryText: calendarLinkedComposePrimaryText(
                title: comment,
                associationText: projectText,
                placeText: nil
            )
        )
    })

    candidates.append(contentsOf: store.applications.compactMap { application in
        guard calendarShowsApplicationDeadline(application),
              involvesResearcher(ids: application.coApplicantAuthorIDs, names: application.coApplicants),
              let deadline = application.closeDate else {
            return nil
        }
        let projectText = application.projectID
            .flatMap { projectID in
                index.projectsByID[projectID]?.displayName(for: language)
            }
            ?? application.projectType?.trimmedOrNil
        let funder = store.organizationLabel(for: application, language: language)
        let associationText = [
            language.text("Grant deadline", "Ansökningsfrist"),
            projectText
        ]
        .compactMap { $0?.trimmedOrNil }
        .joined(separator: ", ")
        .trimmedOrNil
        return CalendarLinkedEventCandidate(
            id: "application:\(application.id)",
            source: .application(application.id),
            displayDate: calendar.startOfDay(for: deadline),
            timeText: "",
            kind: .applicationDeadline,
            primaryText: calendarLinkedComposePrimaryText(
                title: funder,
                associationText: associationText,
                placeText: nil
            )
        )
    })

    candidates.append(contentsOf: store.projects.flatMap { project in
        let projectLabel = project.displayName(for: language)
        return project.projectTasks.compactMap { task -> CalendarLinkedEventCandidate? in
            guard !centralTaskIDs.contains(task.id),
                  !task.isEmpty,
                  let comment = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                return nil
            }
            guard involvesResearcher(ids: task.participantAuthorIDs, names: task.participantNames) else {
                return nil
            }
            let displayDate = effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            )
            return CalendarLinkedEventCandidate(
                id: "project-task:\(project.id):\(task.id)",
                source: .projectTask(projectID: project.id, taskID: task.id),
                displayDate: displayDate,
                timeText: "",
                kind: .taskDeadline,
                primaryText: calendarLinkedComposePrimaryText(
                    title: comment,
                    associationText: projectLabel,
                    placeText: nil
                )
            )
        }
    })

    candidates.append(contentsOf: store.organizations.flatMap { organization in
        let organizationLabel = organization.displayName(for: language)
        return organization.projectTasks.compactMap { task -> CalendarLinkedEventCandidate? in
            guard !centralTaskIDs.contains(task.id),
                  !task.isEmpty,
                  let comment = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline),
                  involvesResearcher(ids: task.participantAuthorIDs, names: task.participantNames) else {
                return nil
            }
            let displayDate = effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            )
            return CalendarLinkedEventCandidate(
                id: "organization-task:\(organization.id):\(task.id)",
                source: .organizationTask(organizationID: organization.id, taskID: task.id),
                displayDate: displayDate,
                timeText: "",
                kind: .taskDeadline,
                primaryText: calendarLinkedComposePrimaryText(
                    title: comment,
                    associationText: organizationLabel,
                    placeText: nil
                )
            )
        }
    })

    candidates.append(contentsOf: store.publications.flatMap { publication in
        let projectText = publication.projectID.flatMap { projectID in
            index.projectsByID[projectID]?.displayName(for: language)
        }
        return publication.publicationTasks.compactMap { task -> CalendarLinkedEventCandidate? in
            guard !centralTaskIDs.contains(task.id),
                  !task.isEmpty,
                  let comment = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                return nil
            }
            guard involvesResearcher(ids: task.participantAuthorIDs, names: task.participantNames) else {
                return nil
            }
            let displayDate = effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            )
            return CalendarLinkedEventCandidate(
                id: "publication-task:\(publication.id):\(task.id)",
                source: .publicationTask(publicationID: publication.id, taskID: task.id),
                displayDate: displayDate,
                timeText: "",
                kind: .taskDeadline,
                primaryText: calendarLinkedComposePrimaryText(
                    title: comment,
                    associationText: projectText,
                    placeText: nil
                )
            )
        }
    })

    candidates.append(contentsOf: store.teachingWorkspaceTasks.compactMap { task in
        guard !centralTaskIDs.contains(task.id),
              !task.isEmpty,
              let comment = task.comment.nonEmpty,
              let deadline = DateParsers.isoDay.date(from: task.deadline),
              involvesResearcher(ids: task.participantAuthorIDs, names: task.participantNames) else {
            return nil
        }
        let displayDate = effectiveCalendarTaskDate(
            deadline: deadline,
            completedOn: task.completedOn,
            isCompleted: task.isCompleted,
            today: today,
            calendar: calendar,
            policy: .rollOverPastDue
        )
        let projectText = calendarLinkedTeachingTaskProjectLabels(task: task, index: index, language: language)
            .joined(separator: ", ")
            .trimmedOrNil
        return CalendarLinkedEventCandidate(
            id: "teaching-task:\(task.id)",
            source: .teachingTask(taskID: task.id),
            displayDate: displayDate,
            timeText: "",
            kind: .taskDeadline,
            primaryText: calendarLinkedComposePrimaryText(
                title: comment,
                associationText: projectText,
                placeText: nil
            )
        )
    })

    candidates.append(contentsOf: store.calendarMeetingRecords.compactMap { meeting -> CalendarLinkedEventCandidate? in
        guard involvesResearcher(ids: meeting.participantAuthorIDs, names: meeting.participantNames),
              let date = DateParsers.isoDay.date(from: meeting.date) else {
            return nil
        }
        let projectText = calendarLinkedMeetingProjectLabels(meeting: meeting, index: index, language: language)
            .joined(separator: ", ")
            .trimmedOrNil
        let placeText: String? = {
            if CalendarMeetingMode(rawValue: meeting.meetingMode) == .online {
                return language.text("Online", "Online")
            }
            return formattedCalendarPlace(
                city: meeting.place,
                country: meeting.country,
                language: language,
                countryDisplayMode: store.calendarCountryDisplayMode
            )
            .trimmedOrNil
        }()
        return CalendarLinkedEventCandidate(
            id: "meeting:\(meeting.id)",
            source: .meeting(meeting.id),
            displayDate: calendar.startOfDay(for: date),
            timeText: timeRangeText(start: meeting.startTime, end: meeting.endTime),
            kind: .meeting,
            primaryText: calendarLinkedComposePrimaryText(
                title: meeting.title.nonEmpty ?? language.text("Activity", "Aktivitet"),
                associationText: projectText,
                placeText: placeText
            )
        )
    })

    return calendarLinkedRows(
        from: candidates,
        language: language,
        calendar: calendar,
        upcomingOnly: upcomingOnly
    )
}

@MainActor
private func calendarLinkedProjectEventRows(
    store: GrantDataStore,
    index: CalendarLinkedEventIndex,
    language: AppLanguage,
    calendar: Calendar,
    projectID: String,
    upcomingOnly: Bool = true
) -> [CalendarLinkedEventRow] {
    let today = calendar.startOfDay(for: Date())
    let project = index.projectsByID[projectID]
    // A task edited centrally supersedes the legacy copy on the record.
    let centralTaskIDs = Set(store.taskItems.map(\.id))
    var candidates: [CalendarLinkedEventCandidate] = []

    candidates.append(contentsOf: store.taskItems.compactMap { task -> CalendarLinkedEventCandidate? in
        guard !task.isEmpty,
              let comment = task.comment.nonEmpty,
              let deadline = DateParsers.isoDay.date(from: task.deadline),
              centralTaskLinkedProjectIDs(task: task, index: index).contains(projectID) else {
            return nil
        }
        let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
        return CalendarLinkedEventCandidate(
            id: "teaching-task:\(task.id)",
            source: .teachingTask(taskID: task.id),
            displayDate: effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            ),
            timeText: "",
            kind: .taskDeadline,
            primaryText: calendarLinkedComposePrimaryText(
                title: comment,
                associationText: participantText,
                placeText: nil
            )
        )
    })

    candidates.append(contentsOf: store.applications.compactMap { application in
        // "Alla kopplingar via id": the application's project link decides;
        // the written project name only for applications without one.
        let matchesProject = project.map { store.applicationBelongs(application, to: $0) }
            ?? (application.projectID == projectID)
        guard matchesProject,
              calendarShowsApplicationDeadline(application),
              let deadline = application.closeDate else {
            return nil
        }
        let funder = store.organizationLabel(for: application, language: language)
        return CalendarLinkedEventCandidate(
            id: "application:\(application.id)",
            source: .application(application.id),
            displayDate: calendar.startOfDay(for: deadline),
            timeText: "",
            kind: .applicationDeadline,
            primaryText: calendarLinkedComposePrimaryText(
                title: funder,
                associationText: language.text("Grant deadline", "Ansökningsfrist"),
                placeText: nil
            )
        )
    })

    if let project {
        candidates.append(contentsOf: project.projectTasks.compactMap { task -> CalendarLinkedEventCandidate? in
            guard !centralTaskIDs.contains(task.id),
                  !task.isEmpty,
                  let comment = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                return nil
            }
            let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
            return CalendarLinkedEventCandidate(
                id: "project-task:\(project.id):\(task.id)",
                source: .projectTask(projectID: project.id, taskID: task.id),
                displayDate: effectiveCalendarTaskDate(
                    deadline: deadline,
                    completedOn: task.completedOn,
                    isCompleted: task.isCompleted,
                    today: today,
                    calendar: calendar,
                    policy: .rollOverPastDue
                ),
                timeText: "",
                kind: .taskDeadline,
                primaryText: calendarLinkedComposePrimaryText(
                    title: comment,
                    associationText: participantText,
                    placeText: nil
                )
            )
        })
    }

    candidates.append(contentsOf: store.organizations.flatMap { organization in
        organization.projectTasks.compactMap { task -> CalendarLinkedEventCandidate? in
            let linkedProjectIDs = calendarLinkedProjectIDs(from: task, index: index)
            guard !centralTaskIDs.contains(task.id),
                  !task.isEmpty,
                  linkedProjectIDs.contains(projectID),
                  let comment = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                return nil
            }
            let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
            return CalendarLinkedEventCandidate(
                id: "organization-task:\(organization.id):\(task.id)",
                source: .organizationTask(organizationID: organization.id, taskID: task.id),
                displayDate: effectiveCalendarTaskDate(
                    deadline: deadline,
                    completedOn: task.completedOn,
                    isCompleted: task.isCompleted,
                    today: today,
                    calendar: calendar,
                    policy: .rollOverPastDue
                ),
                timeText: "",
                kind: .taskDeadline,
                primaryText: calendarLinkedComposePrimaryText(
                    title: comment,
                    associationText: participantText,
                    placeText: nil
                )
            )
        }
    })

    candidates.append(contentsOf: (index.publicationsByProjectID[projectID] ?? [])
        .flatMap { publication in
            publication.publicationTasks.compactMap { task -> CalendarLinkedEventCandidate? in
                guard !centralTaskIDs.contains(task.id),
                      !task.isEmpty,
                      let comment = task.comment.nonEmpty,
                      let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                    return nil
                }
                let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
                return CalendarLinkedEventCandidate(
                    id: "publication-task:\(publication.id):\(task.id)",
                    source: .publicationTask(publicationID: publication.id, taskID: task.id),
                    displayDate: effectiveCalendarTaskDate(
                        deadline: deadline,
                        completedOn: task.completedOn,
                        isCompleted: task.isCompleted,
                        today: today,
                        calendar: calendar,
                        policy: .rollOverPastDue
                    ),
                    timeText: "",
                    kind: .taskDeadline,
                    primaryText: calendarLinkedComposePrimaryText(
                        title: comment,
                        associationText: participantText,
                        placeText: nil
                    )
                )
            }
        })

    candidates.append(contentsOf: store.teachingWorkspaceTasks.compactMap { task -> CalendarLinkedEventCandidate? in
        guard !centralTaskIDs.contains(task.id),
              !task.isEmpty,
              let comment = task.comment.nonEmpty,
              let deadline = DateParsers.isoDay.date(from: task.deadline),
              calendarLinkedTeachingTaskProjectIDs(task: task, index: index).contains(projectID) else {
            return nil
        }
        let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
        return CalendarLinkedEventCandidate(
            id: "teaching-task:\(task.id)",
            source: .teachingTask(taskID: task.id),
            displayDate: effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            ),
            timeText: "",
            kind: .taskDeadline,
            primaryText: calendarLinkedComposePrimaryText(
                title: comment,
                associationText: participantText,
                placeText: nil
            )
        )
    })

    candidates.append(contentsOf: store.calendarMeetingRecords.compactMap { meeting -> CalendarLinkedEventCandidate? in
        guard calendarLinkedMeetingProjectIDs(meeting: meeting, index: index).contains(projectID),
              let date = DateParsers.isoDay.date(from: meeting.date) else {
            return nil
        }
        let participantText = meeting.participantNames.joined(separator: ", ").trimmedOrNil
        let placeText: String? = {
            if CalendarMeetingMode(rawValue: meeting.meetingMode) == .online {
                return language.text("Online", "Online")
            }
            return formattedCalendarPlace(
                city: meeting.place,
                country: meeting.country,
                language: language,
                countryDisplayMode: store.calendarCountryDisplayMode
            )
            .trimmedOrNil
        }()
        return CalendarLinkedEventCandidate(
            id: "meeting:\(meeting.id)",
            source: .meeting(meeting.id),
            displayDate: calendar.startOfDay(for: date),
            timeText: timeRangeText(start: meeting.startTime, end: meeting.endTime),
            kind: .meeting,
            primaryText: calendarLinkedComposePrimaryText(
                title: meeting.title.nonEmpty ?? language.text("Activity", "Aktivitet"),
                associationText: participantText,
                placeText: placeText
            )
        )
    })

    return calendarLinkedRows(
        from: candidates,
        language: language,
        calendar: calendar,
        upcomingOnly: upcomingOnly
    )
}

/// Events linked to one publication: central tasks with a publication link,
/// the publication's own legacy tasks, and calendar activities that carry the
/// publication id.
@MainActor
private func calendarLinkedPublicationEventRows(
    store: GrantDataStore,
    index: CalendarLinkedEventIndex,
    language: AppLanguage,
    calendar: Calendar,
    publicationID: String,
    upcomingOnly: Bool = true
) -> [CalendarLinkedEventRow] {
    let today = calendar.startOfDay(for: Date())
    let centralTaskIDs = Set(store.taskItems.map(\.id))
    var candidates: [CalendarLinkedEventCandidate] = []

    candidates.append(contentsOf: store.taskItems.compactMap { task -> CalendarLinkedEventCandidate? in
        guard !task.isEmpty,
              let comment = task.comment.nonEmpty,
              let deadline = DateParsers.isoDay.date(from: task.deadline),
              task.links.contains(where: { $0.kind == .publication && $0.targetID == publicationID }) else {
            return nil
        }
        let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
        return CalendarLinkedEventCandidate(
            id: "teaching-task:\(task.id)",
            source: .teachingTask(taskID: task.id),
            displayDate: effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            ),
            timeText: "",
            kind: .taskDeadline,
            primaryText: calendarLinkedComposePrimaryText(
                title: comment,
                associationText: participantText,
                placeText: nil
            )
        )
    })

    if let publication = index.publicationsByID[publicationID] {
        candidates.append(contentsOf: publication.publicationTasks.compactMap { task -> CalendarLinkedEventCandidate? in
            guard !centralTaskIDs.contains(task.id),
                  !task.isEmpty,
                  let comment = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                return nil
            }
            let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
            return CalendarLinkedEventCandidate(
                id: "publication-task:\(publication.id):\(task.id)",
                source: .publicationTask(publicationID: publication.id, taskID: task.id),
                displayDate: effectiveCalendarTaskDate(
                    deadline: deadline,
                    completedOn: task.completedOn,
                    isCompleted: task.isCompleted,
                    today: today,
                    calendar: calendar,
                    policy: .rollOverPastDue
                ),
                timeText: "",
                kind: .taskDeadline,
                primaryText: calendarLinkedComposePrimaryText(
                    title: comment,
                    associationText: participantText,
                    placeText: nil
                )
            )
        })
    }

    candidates.append(contentsOf: store.calendarMeetingRecords.compactMap { meeting -> CalendarLinkedEventCandidate? in
        guard meeting.publicationIDs.compactMap(\.trimmedOrNil).contains(publicationID),
              let date = DateParsers.isoDay.date(from: meeting.date) else {
            return nil
        }
        let participantText = meeting.participantNames.joined(separator: ", ").trimmedOrNil
        let placeText: String? = {
            if CalendarMeetingMode(rawValue: meeting.meetingMode) == .online {
                return language.text("Online", "Online")
            }
            return formattedCalendarPlace(
                city: meeting.place,
                country: meeting.country,
                language: language,
                countryDisplayMode: store.calendarCountryDisplayMode
            )
            .trimmedOrNil
        }()
        return CalendarLinkedEventCandidate(
            id: "meeting:\(meeting.id)",
            source: .meeting(meeting.id),
            displayDate: calendar.startOfDay(for: date),
            timeText: timeRangeText(start: meeting.startTime, end: meeting.endTime),
            kind: .meeting,
            primaryText: calendarLinkedComposePrimaryText(
                title: meeting.title.nonEmpty ?? language.text("Activity", "Aktivitet"),
                associationText: participantText,
                placeText: placeText
            )
        )
    })

    return calendarLinkedRows(
        from: candidates,
        language: language,
        calendar: calendar,
        upcomingOnly: upcomingOnly
    )
}

@MainActor
private func calendarLinkedApplicationEventRows(
    store: GrantDataStore,
    index: CalendarLinkedEventIndex,
    language: AppLanguage,
    calendar: Calendar,
    applicationID: String
) -> [CalendarLinkedEventRow] {
    let today = calendar.startOfDay(for: Date())
    guard let application = index.applicationsByID[applicationID] else { return [] }
    var candidates: [CalendarLinkedEventCandidate] = []

    if calendarShowsApplicationDeadline(application), let deadline = application.closeDate {
        let participantText = application.coApplicants.joined(separator: ", ").trimmedOrNil
        let funder = store.organizationLabel(for: application, language: language)
        let title = store.localizedGrantName(for: application, language: language).nonEmpty ?? funder
        candidates.append(
            CalendarLinkedEventCandidate(
                id: "application:\(application.id)",
                source: .application(application.id),
                displayDate: calendar.startOfDay(for: deadline),
                timeText: "",
                kind: .applicationDeadline,
                primaryText: calendarLinkedComposePrimaryText(
                    title: title,
                    associationText: participantText,
                    placeText: nil
                )
            )
        )
    }

    candidates.append(contentsOf: (index.projectTasksByApplicationID[applicationID] ?? []).compactMap { reference -> CalendarLinkedEventCandidate? in
            let projectID = reference.ownerID
            let task = reference.task
            guard !task.isEmpty,
                  let comment = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                return nil
            }
            let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
            return CalendarLinkedEventCandidate(
                id: "project-task:\(projectID):\(task.id)",
                source: .projectTask(projectID: projectID, taskID: task.id),
                displayDate: effectiveCalendarTaskDate(
                    deadline: deadline,
                    completedOn: task.completedOn,
                    isCompleted: task.isCompleted,
                    today: today,
                    calendar: calendar,
                    policy: .rollOverPastDue
                ),
                timeText: "",
                kind: .taskDeadline,
                primaryText: calendarLinkedComposePrimaryText(
                    title: comment,
                    associationText: participantText,
                    placeText: nil
                )
            )
    })

    candidates.append(contentsOf: (index.organizationTasksByApplicationID[applicationID] ?? []).compactMap { reference -> CalendarLinkedEventCandidate? in
            let organizationID = reference.ownerID
            let task = reference.task
            guard !task.isEmpty,
                  let comment = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                return nil
            }
            let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
            return CalendarLinkedEventCandidate(
                id: "organization-task:\(organizationID):\(task.id)",
                source: .organizationTask(organizationID: organizationID, taskID: task.id),
                displayDate: effectiveCalendarTaskDate(
                    deadline: deadline,
                    completedOn: task.completedOn,
                    isCompleted: task.isCompleted,
                    today: today,
                    calendar: calendar,
                    policy: .rollOverPastDue
                ),
                timeText: "",
                kind: .taskDeadline,
                primaryText: calendarLinkedComposePrimaryText(
                    title: comment,
                    associationText: participantText,
                    placeText: nil
                )
            )
    })

    candidates.append(contentsOf: (index.publicationTasksByApplicationID[applicationID] ?? []).compactMap { reference -> CalendarLinkedEventCandidate? in
            let publicationID = reference.ownerID
            let task = reference.task
            guard !task.isEmpty,
                  let comment = task.comment.nonEmpty,
                  let deadline = DateParsers.isoDay.date(from: task.deadline) else {
                return nil
            }
            let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
            return CalendarLinkedEventCandidate(
                id: "publication-task:\(publicationID):\(task.id)",
                source: .publicationTask(publicationID: publicationID, taskID: task.id),
                displayDate: effectiveCalendarTaskDate(
                    deadline: deadline,
                    completedOn: task.completedOn,
                    isCompleted: task.isCompleted,
                    today: today,
                    calendar: calendar,
                    policy: .rollOverPastDue
                ),
                timeText: "",
                kind: .taskDeadline,
                primaryText: calendarLinkedComposePrimaryText(
                    title: comment,
                    associationText: participantText,
                    placeText: nil
                )
            )
    })

    candidates.append(contentsOf: (index.teachingTasksByApplicationID[applicationID] ?? []).compactMap { task -> CalendarLinkedEventCandidate? in
        guard !task.isEmpty,
              let comment = task.comment.nonEmpty,
              let deadline = DateParsers.isoDay.date(from: task.deadline) else {
            return nil
        }
        let participantText = task.participantNames.joined(separator: ", ").trimmedOrNil
        return CalendarLinkedEventCandidate(
            id: "teaching-task:\(task.id)",
            source: .teachingTask(taskID: task.id),
            displayDate: effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            ),
            timeText: "",
            kind: .taskDeadline,
            primaryText: calendarLinkedComposePrimaryText(
                title: comment,
                associationText: participantText,
                placeText: nil
            )
        )
    })

    return calendarLinkedRows(from: candidates, language: language, calendar: calendar)
}

struct CalendarLinkedEventList: View {
    @ObservedObject var store: GrantDataStore
    let language: AppLanguage
    let rows: [CalendarLinkedEventRow]
    var usesSingleLineRows = false
    var usesCompactResearcherRows = false

    var body: some View {
        VStack(alignment: .leading, spacing: usesCompactResearcherRows ? 0 : 8) {
            if rows.isEmpty {
                AppCompactEmptyListLabel(title: language.text("No records", "Inga poster"))
            } else {
                ForEach(rows) { row in
                    Button {
                        store.revealCalendarWorkspace(on: row.displayDate, eventSource: row.source)
                    } label: {
                        if usesSingleLineRows {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(row.primaryText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .layoutPriority(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(row.secondaryText)
                                    .font(appFont(.secondary).weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .font(appFont(.secondary))
                            .foregroundStyle(AppPalette.appText)
                            .padding(.horizontal, usesCompactResearcherRows ? 8 : 0)
                            .padding(.vertical, usesCompactResearcherRows ? 3 : 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.primaryText)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(row.secondaryText)
                                    .font(appFont(.secondary))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .appReminderDot(
                        store.calendarTaskReminderBadgeEntries.contains { $0.source == row.source }
                    )

                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private func calendarLinkedRows(
    from candidates: [CalendarLinkedEventCandidate],
    language: AppLanguage,
    calendar: Calendar,
    upcomingOnly: Bool = false
) -> [CalendarLinkedEventRow] {
    let filteredCandidates: [CalendarLinkedEventCandidate]
    if upcomingOnly {
        filteredCandidates = candidates.filter {
            calendarLinkedCandidateIsUpcoming($0, calendar: calendar, now: Date())
        }
    } else {
        filteredCandidates = candidates
    }

    return filteredCandidates
        .sorted(by: calendarLinkedCandidateSort)
        .map { candidate in
            CalendarLinkedEventRow(
                id: candidate.id,
                source: candidate.source,
                displayDate: candidate.displayDate,
                primaryText: candidate.primaryText,
                secondaryText: calendarLinkedSecondaryText(
                    displayDate: candidate.displayDate,
                    timeText: candidate.timeText,
                    language: language,
                    calendar: calendar
                )
            )
        }
}

private func calendarLinkedCandidateIsUpcoming(
    _ candidate: CalendarLinkedEventCandidate,
    calendar: Calendar,
    now: Date
) -> Bool {
    let today = calendar.startOfDay(for: now)
    let displayDate = calendar.startOfDay(for: candidate.displayDate)
    if displayDate > today {
        return true
    }
    if displayDate < today {
        return false
    }
    guard let cutoff = calendarLinkedCandidateCutoffDate(candidate, calendar: calendar) else {
        return true
    }
    return cutoff >= now
}

private func calendarLinkedCandidateCutoffDate(
    _ candidate: CalendarLinkedEventCandidate,
    calendar: Calendar
) -> Date? {
    let rawTime = candidate.timeText
        .replacingOccurrences(of: "?", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawTime.isEmpty else { return nil }
    let separators = CharacterSet(charactersIn: "–-")
    let parts = rawTime.components(separatedBy: separators).map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let timeText = (parts.count > 1 ? parts.last : parts.first) ?? nil else { return nil }
    let clockParts = timeText.split(separator: ":")
    guard clockParts.count == 2,
          let hour = Int(clockParts[0]),
          let minute = Int(clockParts[1]) else {
        return nil
    }
    return calendar.date(
        bySettingHour: hour,
        minute: minute,
        second: 0,
        of: candidate.displayDate
    )
}


private func calendarLinkedCandidateSort(_ lhs: CalendarLinkedEventCandidate, _ rhs: CalendarLinkedEventCandidate) -> Bool {
    if lhs.displayDate != rhs.displayDate {
        return lhs.displayDate < rhs.displayDate
    }

    let leftHasTime = lhs.timeText.trimmedOrNil != nil
    let rightHasTime = rhs.timeText.trimmedOrNil != nil
    if leftHasTime != rightHasTime {
        return leftHasTime && !rightHasTime
    }

    let leftTime = lhs.timeText.trimmingCharacters(in: .whitespacesAndNewlines)
    let rightTime = rhs.timeText.trimmingCharacters(in: .whitespacesAndNewlines)
    if leftTime != rightTime {
        return leftTime.localizedStandardCompare(rightTime) == .orderedAscending
    }

    if lhs.kind.sortRank != rhs.kind.sortRank {
        return lhs.kind.sortRank < rhs.kind.sortRank
    }

    return lhs.primaryText.localizedStandardCompare(rhs.primaryText) == .orderedAscending
}



private func calendarLinkedSecondaryText(
    for event: CalendarWorkspaceEvent,
    language: AppLanguage,
    calendar: Calendar
) -> String {
    calendarLinkedSecondaryText(
        displayDate: event.displayDate,
        timeText: event.timeText,
        language: language,
        calendar: calendar
    )
}

private func calendarLinkedSecondaryText(
    displayDate: Date,
    timeText: String,
    language: AppLanguage,
    calendar: Calendar
) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = calendar.locale
    formatter.dateFormat = "d MMM yyyy"
    let dateText = formatter.string(from: displayDate).capitalized
    if let timeText = timeText.trimmedOrNil {
        return "\(dateText) (\(timeText))"
    }
    return dateText
}

private func calendarLinkedComposePrimaryText(
    title: String,
    associationText: String?,
    placeText: String?
) -> String {
    var line = title
    if let associationText, !associationText.isEmpty {
        line += " (\(associationText))"
    }
    if let placeText, !placeText.isEmpty {
        line += ", \(placeText)"
    }
    return line
}

private func calendarLinkedDisplayPlaceText(_ raw: String) -> String {
    let withoutSomalilandToken = raw.replacingOccurrences(of: linkedCalendarSomalilandToken, with: "")
    let withoutFlags = String(
        String.UnicodeScalarView(
            withoutSomalilandToken.unicodeScalars.filter { !(127462...127487 ~= $0.value) }
        )
    )
    return withoutFlags
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func calendarLinkedSameName(_ lhs: String?, _ rhs: String?) -> Bool {
    (lhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(
        (rhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    ) == .orderedSame
}





private func calendarLinkedMeetingProjectLabels(
    meeting: CalendarMeetingRecord,
    index: CalendarLinkedEventIndex,
    language: AppLanguage
) -> [String] {
    calendarLinkedMeetingProjectIDs(meeting: meeting, index: index).compactMap { id in
        index.projectsByID[id]?.displayName(for: language)
    }
}

private func calendarLinkedMeetingProjectIDs(
    meeting: CalendarMeetingRecord,
    index: CalendarLinkedEventIndex
) -> [String] {
    var projectIDs = meeting.projectIDs.isEmpty ? (meeting.projectID.map { [$0] } ?? []) : meeting.projectIDs
    for applicationID in meeting.applicationIDs.compactMap(\.trimmedOrNil) {
        if let projectID = index.applicationsByID[applicationID]?.projectID?.trimmedOrNil {
            projectIDs.append(projectID)
        }
    }
    for publicationID in meeting.publicationIDs.compactMap(\.trimmedOrNil) {
        if let projectID = index.publicationsByID[publicationID]?.projectID?.trimmedOrNil {
            projectIDs.append(projectID)
        }
    }
    for appearanceID in meeting.mediaAppearanceIDs.compactMap(\.trimmedOrNil) {
        projectIDs.append(contentsOf: index.mediaAppearancesByID[appearanceID]?.projectIDs ?? [])
    }
    return Array(NSOrderedSet(array: projectIDs.compactMap(\.trimmedOrNil))) as? [String]
        ?? projectIDs.compactMap(\.trimmedOrNil)
}

private func calendarLinkedTeachingTaskProjectLabels(
    task: PublicationTaskItem,
    index: CalendarLinkedEventIndex,
    language: AppLanguage
) -> [String] {
    calendarLinkedTeachingTaskProjectIDs(task: task, index: index).compactMap { id in
        index.projectsByID[id]?.displayName(for: language)
    }
}

private func calendarLinkedTeachingTaskProjectIDs(
    task: PublicationTaskItem,
    index: CalendarLinkedEventIndex
) -> [String] {
    var projectIDs: [String] = []
    if let directProjectID = task.projectID?.trimmedOrNil {
        projectIDs.append(directProjectID)
    }
    if let publicationID = task.publicationID?.trimmedOrNil,
       let publicationProjectID = index.publicationsByID[publicationID]?.projectID {
        projectIDs.append(publicationProjectID)
    }
    if let applicationID = task.applicationID?.trimmedOrNil,
       let applicationProjectID = index.applicationsByID[applicationID]?.projectID {
        projectIDs.append(applicationProjectID)
    }
    return Array(NSOrderedSet(array: projectIDs)) as? [String] ?? projectIDs
}

private func centralTaskLinkedProjectIDs(
    task: TaskItem,
    index: CalendarLinkedEventIndex
) -> [String] {
    var projectIDs: [String] = []
    for link in task.links {
        switch link.kind {
        case .project:
            projectIDs.append(link.targetID)
        case .publication:
            if let projectID = index.publicationsByID[link.targetID]?.projectID?.trimmedOrNil {
                projectIDs.append(projectID)
            }
        case .application:
            if let projectID = index.applicationsByID[link.targetID]?.projectID?.trimmedOrNil {
                projectIDs.append(projectID)
            }
        default:
            break
        }
    }
    return Array(NSOrderedSet(array: projectIDs.compactMap(\.trimmedOrNil))) as? [String]
        ?? projectIDs.compactMap(\.trimmedOrNil)
}

private func centralTaskProjectLabels(
    task: TaskItem,
    index: CalendarLinkedEventIndex,
    language: AppLanguage
) -> [String] {
    centralTaskLinkedProjectIDs(task: task, index: index).compactMap { id in
        index.projectsByID[id]?.displayName(for: language)
    }
}

private func calendarLinkedProjectIDs(
    from task: ProjectTaskItem,
    index: CalendarLinkedEventIndex
) -> [String] {
    var projectIDs: [String] = []
    if let publicationID = task.publicationID?.trimmedOrNil,
       let publicationProjectID = index.publicationsByID[publicationID]?.projectID {
        projectIDs.append(publicationProjectID)
    }
    if let applicationID = task.applicationID?.trimmedOrNil,
       let applicationProjectID = index.applicationsByID[applicationID]?.projectID {
        projectIDs.append(applicationProjectID)
    }
    return Array(NSOrderedSet(array: projectIDs)) as? [String] ?? projectIDs
}

/// Round 7: "Kopplade aktiviteter och uppgifter" on the doctoral candidate,
/// teaching assignment and course pages. Lists the calendar activities and
/// shared tasks that carry the page's id link (nothing is matched by name or
/// project), upcoming first, then earlier ones. Clicking a row opens it in
/// the calendar.
struct CalendarLinkedActivitiesAndTasksList: View {
    @ObservedObject var store: GrantDataStore
    let language: AppLanguage
    let scope: CalendarLinkedEventScope

    var body: some View {
        let rows = calendarLinkedEventRows(
            store: store,
            language: language,
            scope: scope,
            includesTasks: true,
            includesPastEvents: true
        )
        let todayStart = Calendar.current.startOfDay(for: Date())
        let upcoming = rows
            .filter { $0.displayDate >= todayStart }
            .sorted { $0.displayDate < $1.displayDate }
        let past = rows
            .filter { $0.displayDate < todayStart }
            .sorted { $0.displayDate > $1.displayDate }

        VStack(alignment: .leading, spacing: 12) {
            if rows.isEmpty {
                AppCompactEmptyListLabel(title: language.text(
                    "No activities or tasks are linked yet",
                    "Inga aktiviteter eller uppgifter är kopplade ännu"
                ))
            }
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    AppFieldLabelText(text: language.text("Upcoming", "Kommande"))
                    CalendarLinkedEventList(
                        store: store,
                        language: language,
                        rows: upcoming,
                        usesSingleLineRows: true,
                        usesCompactResearcherRows: true
                    )
                }
            }
            if !past.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    AppFieldLabelText(text: language.text("Earlier", "Tidigare"))
                    CalendarLinkedEventList(
                        store: store,
                        language: language,
                        rows: past,
                        usesSingleLineRows: true,
                        usesCompactResearcherRows: true
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
