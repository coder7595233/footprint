import Foundation

// Round 7 ("Aktiviteter och uppgifter kopplas likadant"): the activity editor
// and the task editor share one multi-row link picker. This file holds the
// parts that do not draw anything, so they can be tested: turning row texts
// into ids and back, replacing the task links of one kind, and the
// "Undervisning" list where each course is followed by its assignments.

/// One choice in a link picker row.
struct CalendarLinkOption: Hashable {
    let id: String
    let label: String
    /// 0 for a top-level choice, 1 for a choice listed under the one above
    /// (a teaching assignment under its course).
    var indentLevel: Int = 0
}

/// The ids for the texts in a picker's rows, in row order, each id once.
/// A text that names no option is left out (as before in the activity editor).
func calendarLinkIDs(forLabels labels: [String], options: [CalendarLinkOption]) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    for label in labels {
        guard let trimmed = label.trimmedOrNil else { continue }
        let match = options.first(where: { $0.label == trimmed })
            ?? options.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame })
        guard let id = match?.id, seen.insert(id).inserted else { continue }
        result.append(id)
    }
    return result
}

/// The row texts for stored ids, in order. An id without an option (a removed
/// record) gets no row.
func calendarLinkLabels(forIDs ids: [String], options: [CalendarLinkOption]) -> [String] {
    var seen = Set<String>()
    return ids.compactMap { id in
        guard let id = id.trimmedOrNil, seen.insert(id).inserted else { return nil }
        return options.first(where: { $0.id == id })?.label
    }
}

/// Replaces every task link of `kind` with one link per id (in order), and
/// keeps the links of every other kind exactly as they are.
func calendarTaskLinksReplacingKind(
    in links: [TaskLink],
    kind: TaskLinkKind,
    targetIDs: [String]
) -> [TaskLink] {
    var kept = links.filter { $0.kind != kind }
    var seen = Set<String>()
    for targetID in targetIDs {
        guard let targetID = targetID.trimmedOrNil, seen.insert(targetID).inserted else { continue }
        kept.append(TaskLink(kind: kind, targetID: targetID))
    }
    return kept
}

/// The ids of a task's links of one kind, in stored order.
func calendarTaskLinkTargetIDs(_ links: [TaskLink], kind: TaskLinkKind) -> [String] {
    var seen = Set<String>()
    return links
        .filter { $0.kind == kind }
        .compactMap { $0.targetID.trimmedOrNil }
        .filter { seen.insert($0).inserted }
}

// MARK: - "Undervisning": courses and their assignments in one list

private let calendarTeachingCourseOptionPrefix = "course:"
private let calendarTeachingAssignmentOptionPrefix = "assignment:"

/// Option id for a course in the "Undervisning" list.
func calendarTeachingCourseOptionID(_ courseID: String) -> String {
    calendarTeachingCourseOptionPrefix + courseID
}

/// Option id for a teaching assignment in the "Undervisning" list.
func calendarTeachingAssignmentOptionID(_ assignmentID: String) -> String {
    calendarTeachingAssignmentOptionPrefix + assignmentID
}

/// Splits the chosen "Undervisning" option ids into course ids and
/// assignment ids.
func calendarTeachingSelection(fromOptionIDs optionIDs: [String]) -> (courseIDs: [String], assignmentIDs: [String]) {
    var courseIDs: [String] = []
    var assignmentIDs: [String] = []
    for optionID in optionIDs {
        if optionID.hasPrefix(calendarTeachingCourseOptionPrefix) {
            if let id = String(optionID.dropFirst(calendarTeachingCourseOptionPrefix.count)).trimmedOrNil,
               !courseIDs.contains(id) {
                courseIDs.append(id)
            }
        } else if optionID.hasPrefix(calendarTeachingAssignmentOptionPrefix) {
            if let id = String(optionID.dropFirst(calendarTeachingAssignmentOptionPrefix.count)).trimmedOrNil,
               !assignmentIDs.contains(id) {
                assignmentIDs.append(id)
            }
        }
    }
    return (courseIDs, assignmentIDs)
}

/// The "Undervisning" option ids for stored course and assignment links:
/// courses first, then assignments.
func calendarTeachingOptionIDs(courseIDs: [String], assignmentIDs: [String]) -> [String] {
    courseIDs.compactMap(\.trimmedOrNil).map(calendarTeachingCourseOptionID)
        + assignmentIDs.compactMap(\.trimmedOrNil).map(calendarTeachingAssignmentOptionID)
}

/// "Course name (term)" for a course in the "Undervisning" list.
func calendarTeachingCourseLabel(_ course: TeachingCourse, language: AppLanguage) -> String {
    let name = course.localizedName(language: language).trimmedOrNil
        ?? course.courseCode.trimmedOrNil
        ?? language.text("Untitled course", "Namnlös kurs")
    let term = course.localizedTerm(language: language).trimmedOrNil
        ?? course.localizedTermFallback.trimmedOrNil
    guard let term else { return name }
    return "\(name) (\(term))"
}

/// One list for the "Undervisning" row: each course (sorted by its label),
/// followed by its teaching assignments (sorted, indented). Assignments whose
/// course is unknown come last, not indented. Programme rows are listed only
/// when an assignment belongs to them. Labels are made unique so each text
/// names exactly one choice.
func calendarTeachingLinkOptions(
    courses: [TeachingCourse],
    assignments: [TeachingAssignment],
    courseLabel: (TeachingCourse) -> String,
    assignmentLabel: (TeachingAssignment) -> String
) -> [CalendarLinkOption] {
    let courseIDs = Set(courses.map(\.id))
    var assignmentsByCourseID: [String: [TeachingAssignment]] = [:]
    var looseAssignments: [TeachingAssignment] = []
    for assignment in assignments {
        if let courseID = assignment.contextID?.trimmedOrNil, courseIDs.contains(courseID) {
            assignmentsByCourseID[courseID, default: []].append(assignment)
        } else {
            looseAssignments.append(assignment)
        }
    }

    var assignmentLabelsByID: [String: String] = [:]
    for assignment in assignments {
        assignmentLabelsByID[assignment.id] = assignmentLabel(assignment)
    }
    func sortedAssignments(_ list: [TeachingAssignment]) -> [(TeachingAssignment, String)] {
        list.map { ($0, assignmentLabelsByID[$0.id] ?? "") }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }

    var usedLabels = Set<String>()
    func uniqueLabel(_ label: String) -> String {
        var candidate = label
        var number = 2
        while usedLabels.contains(candidate) {
            candidate = "\(label) [\(number)]"
            number += 1
        }
        usedLabels.insert(candidate)
        return candidate
    }

    var result: [CalendarLinkOption] = []
    let listedCourses = courses
        .filter { $0.contextType != .programTrack || assignmentsByCourseID[$0.id] != nil }
        .map { ($0, courseLabel($0)) }
        .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    for (course, label) in listedCourses {
        result.append(CalendarLinkOption(id: calendarTeachingCourseOptionID(course.id), label: uniqueLabel(label)))
        for (assignment, assignmentText) in sortedAssignments(assignmentsByCourseID[course.id] ?? []) {
            result.append(CalendarLinkOption(
                id: calendarTeachingAssignmentOptionID(assignment.id),
                label: uniqueLabel(assignmentText),
                indentLevel: 1
            ))
        }
    }
    for (assignment, assignmentText) in sortedAssignments(looseAssignments) {
        result.append(CalendarLinkOption(
            id: calendarTeachingAssignmentOptionID(assignment.id),
            label: uniqueLabel(assignmentText)
        ))
    }
    return result
}

/// The text shown for an option in the suggestion list: indented under its
/// course when it is an assignment.
func calendarLinkOptionDisplayText(_ label: String, options: [CalendarLinkOption]) -> String {
    guard let option = options.first(where: { $0.label == label }), option.indentLevel > 0 else { return label }
    return String(repeating: "\u{2003}\u{2003}", count: option.indentLevel) + label
}

/// The ids to save for one link kind: the ids chosen in the rows, plus any
/// stored id whose record is not offered in the rows at all (a removed or
/// hidden record), so saving never drops a link the user could not see.
func calendarLinkIDsKeepingUnlisted(
    selected: [String],
    existing: [String],
    listedIDs: Set<String>
) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    for id in selected + existing.filter({ !listedIDs.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
        guard let id = id.trimmedOrNil, seen.insert(id).inserted else { continue }
        result.append(id)
    }
    return result
}

/// What the task editor's link rows hold, per link kind.
struct CalendarTaskLinkSelection: Equatable {
    var projectIDs: [String] = []
    var organizationIDs: [String] = []
    var applicationIDs: [String] = []
    var publicationIDs: [String] = []
    var teachingCourseIDs: [String] = []
    var teachingAssignmentIDs: [String] = []
    var doctoralCandidateIDs: [String] = []

    /// The link kinds the task editor shows. Links of every other kind
    /// (congress, conference contribution, review) are never touched by it.
    static let editedKinds: [TaskLinkKind] = [
        .project, .organization, .application, .publication,
        .teachingCourse, .teachingAssignment, .doctoralCandidate
    ]

    init(
        projectIDs: [String] = [],
        organizationIDs: [String] = [],
        applicationIDs: [String] = [],
        publicationIDs: [String] = [],
        teachingCourseIDs: [String] = [],
        teachingAssignmentIDs: [String] = [],
        doctoralCandidateIDs: [String] = []
    ) {
        self.projectIDs = projectIDs
        self.organizationIDs = organizationIDs
        self.applicationIDs = applicationIDs
        self.publicationIDs = publicationIDs
        self.teachingCourseIDs = teachingCourseIDs
        self.teachingAssignmentIDs = teachingAssignmentIDs
        self.doctoralCandidateIDs = doctoralCandidateIDs
    }

    /// The selection a task's stored links give.
    init(links: [TaskLink]) {
        self.init(
            projectIDs: calendarTaskLinkTargetIDs(links, kind: .project),
            organizationIDs: calendarTaskLinkTargetIDs(links, kind: .organization),
            applicationIDs: calendarTaskLinkTargetIDs(links, kind: .application),
            publicationIDs: calendarTaskLinkTargetIDs(links, kind: .publication),
            teachingCourseIDs: calendarTaskLinkTargetIDs(links, kind: .teachingCourse),
            teachingAssignmentIDs: calendarTaskLinkTargetIDs(links, kind: .teachingAssignment),
            doctoralCandidateIDs: calendarTaskLinkTargetIDs(links, kind: .doctoralCandidate)
        )
    }

    func ids(for kind: TaskLinkKind) -> [String] {
        switch kind {
        case .project: return projectIDs
        case .organization: return organizationIDs
        case .application: return applicationIDs
        case .publication: return publicationIDs
        case .teachingCourse: return teachingCourseIDs
        case .teachingAssignment: return teachingAssignmentIDs
        case .doctoralCandidate: return doctoralCandidateIDs
        default: return []
        }
    }
}

/// Saves the task editor's rows into a task's links: every link of an edited
/// kind is replaced by the rows (keeping links to records the rows could not
/// show, see `calendarLinkIDsKeepingUnlisted`), and links of every other kind
/// stay exactly as they are.
func calendarTaskLinksApplyingSelection(
    _ links: [TaskLink],
    selection: CalendarTaskLinkSelection,
    listedIDs: [TaskLinkKind: Set<String>]
) -> [TaskLink] {
    var updated = links
    for kind in CalendarTaskLinkSelection.editedKinds {
        let ids = calendarLinkIDsKeepingUnlisted(
            selected: selection.ids(for: kind),
            existing: calendarTaskLinkTargetIDs(links, kind: kind),
            listedIDs: listedIDs[kind] ?? []
        )
        updated = calendarTaskLinksReplacingKind(in: updated, kind: kind, targetIDs: ids)
    }
    return updated
}
