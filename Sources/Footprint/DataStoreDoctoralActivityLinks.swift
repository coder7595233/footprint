import Foundation

// Round 7 (user decision): the doctoral candidate page used to find its
// activities through the candidate's project and written name. It now uses
// only the explicit doctoral candidate links on the activities. Activities
// that the old rule found but that carry no such link are suggested under
// Data quality, "Aktiviteter att koppla till doktorand", where each can be
// linked ("Koppla") or hidden ("Dölj"). Nothing is linked automatically.

/// One activity that the old name/project rule attached to a doctoral
/// candidate, without an id link to the candidate.
struct DoctoralActivityLinkSuggestion: Identifiable, Hashable {
    let meetingID: String
    let candidateID: String
    let date: String
    let title: String
    let candidateName: String
    /// Why the old rule found it: through the candidate's project, the
    /// candidate's name among the participants, or both.
    let matchedByProject: Bool
    let matchedByName: Bool

    /// Also the key that remembers a hidden suggestion.
    var id: String { "doctoral-activity-link|\(meetingID)|\(candidateID)" }
}

/// The suggestions, newest activity first. `meetingProjectIDs` gives an
/// activity's projects (directly or through its grants, publications and
/// media); `candidateTakesPart` says whether the candidate is among the
/// activity's participants (by researcher id or written name). An activity
/// already linked to the candidate is never suggested.
func computeDoctoralActivityLinkSuggestions(
    candidates: [DoctoralCandidateRecord],
    meetings: [CalendarMeetingRecord],
    meetingProjectIDs: (CalendarMeetingRecord) -> [String],
    candidateTakesPart: (CalendarMeetingRecord, DoctoralCandidateRecord) -> Bool
) -> [DoctoralActivityLinkSuggestion] {
    let candidatesWithRule = candidates.filter {
        $0.linkedProjectID?.trimmedOrNil != nil || $0.candidateName.trimmedOrNil != nil
    }
    guard !candidatesWithRule.isEmpty else { return [] }
    let usesProjects = candidatesWithRule.contains { $0.linkedProjectID?.trimmedOrNil != nil }

    var suggestions: [DoctoralActivityLinkSuggestion] = []
    for meeting in meetings {
        let linkedCandidateIDs = Set(calendarMeetingDoctoralCandidateIDs(meeting))
        let projectIDs = usesProjects ? Set(meetingProjectIDs(meeting)) : []
        for candidate in candidatesWithRule where !linkedCandidateIDs.contains(candidate.id) {
            let byProject = candidate.linkedProjectID?.trimmedOrNil.map { projectIDs.contains($0) } ?? false
            let byName = candidate.candidateName.trimmedOrNil != nil && candidateTakesPart(meeting, candidate)
            guard byProject || byName else { continue }
            suggestions.append(
                DoctoralActivityLinkSuggestion(
                    meetingID: meeting.id,
                    candidateID: candidate.id,
                    date: meeting.date,
                    title: meeting.title,
                    candidateName: candidate.candidateName,
                    matchedByProject: byProject,
                    matchedByName: byName
                )
            )
        }
    }
    return suggestions.sorted { lhs, rhs in
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.candidateName != rhs.candidateName {
            return lhs.candidateName.localizedStandardCompare(rhs.candidateName) == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}

extension GrantDataStore {
    /// The activities to suggest for linking to a doctoral candidate, with
    /// the same rule the candidate page used before (project, or the name
    /// among the participants). Hidden suggestions are left out unless asked.
    func doctoralActivityLinkSuggestions(includeHidden: Bool = false) -> [DoctoralActivityLinkSuggestion] {
        let candidates = doctoralCandidates
        guard !candidates.isEmpty else { return [] }
        var researcherIDByCandidateID: [String: String] = [:]
        for candidate in candidates {
            if let researcherID = researcherID(forPresentedName: candidate.candidateName) {
                researcherIDByCandidateID[candidate.id] = researcherID
            }
        }
        let suggestions = computeDoctoralActivityLinkSuggestions(
            candidates: candidates,
            meetings: calendarMeetingRecords,
            meetingProjectIDs: { calendarMeetingProjectIDs(for: $0, store: self) },
            candidateTakesPart: { meeting, candidate in
                personList(
                    ids: meeting.participantAuthorIDs,
                    names: meeting.participantNames,
                    includesResearcherID: researcherIDByCandidateID[candidate.id],
                    orName: candidate.candidateName
                )
            }
        )
        guard !includeHidden else { return suggestions }
        return suggestions.filter { !isDataQualityWarningHidden($0) }
    }

    /// "Koppla": adds the candidate to the activity's doctoral candidate
    /// links. Saved like an edit in the activity editor, so it can be undone.
    /// Returns false when the activity is gone or already linked.
    @discardableResult
    func linkSuggestedDoctoralActivity(_ suggestion: DoctoralActivityLinkSuggestion) -> Bool {
        var meetings = calendarMeetingRecords
        guard let index = meetings.firstIndex(where: { $0.id == suggestion.meetingID }),
              doctoralCandidates.contains(where: { $0.id == suggestion.candidateID }) else {
            return false
        }
        let linkedIDs = calendarMeetingDoctoralCandidateIDs(meetings[index])
        guard !linkedIDs.contains(suggestion.candidateID) else { return false }
        meetings[index].doctoralCandidateIDs = linkedIDs + [suggestion.candidateID]
        meetings[index].doctoralCandidateID = meetings[index].doctoralCandidateIDs.first
        autosaveCalendarMeetingRecords(meetings)
        return true
    }
}
