import Foundation

// Snabbare, omgång 2: the doctoral candidate page shows calendar activity
// hours per supervision period. The page found them by going through every
// calendar activity (about 1,800) once per period and twice per drawn row,
// on every redraw. The linked activities are now indexed once per calendar
// change, and each candidate's result is kept until its periods or the
// calendar change.

/// One candidate's calendar activity minutes per supervision period, with
/// what they were computed from.
struct DoctoralSupervisionActivityMinutesMemoEntry {
    let calendarGeneration: Int
    let periods: [DoctoralSupervisionPeriod]
    let minutesByPeriodID: [String: Int]
}

extension GrantDataStore {
    /// The calendar activities linked to each doctoral candidate, in calendar
    /// order, rebuilt when the calendar content changes.
    func calendarMeetingsLinkedToDoctoralCandidates() -> [String: [CalendarMeetingRecord]] {
        if let cached = doctoralCandidateMeetingIndexCache, cached.generation == calendarContentGeneration {
            return cached.meetingsByCandidateID
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let meetings = calendarMeetingRecords
        var byCandidateID: [String: [CalendarMeetingRecord]] = [:]
        for meeting in meetings {
            for candidateID in calendarMeetingDoctoralCandidateIDs(meeting) {
                byCandidateID[candidateID, default: []].append(meeting)
            }
        }
        doctoralCandidateMeetingIndexCache = (generation: calendarContentGeneration, meetingsByCandidateID: byCandidateID)
        let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        if duration >= 8 {
            appendPerformanceDiagnostic(
                String(
                    format: "doctoral-meeting-index-build meetings=%ld candidates=%ld total_ms=%.2f",
                    meetings.count,
                    byCandidateID.count,
                    duration
                )
            )
        }
        return byCandidateID
    }

    /// Calendar activity minutes per supervision period for the candidate:
    /// the same result as doctoralSupervisionCalendarActivityMinutesByPeriodID
    /// over all meetings, kept until the periods or the calendar change.
    func doctoralSupervisionCalendarActivityMinutes(for candidate: DoctoralCandidateRecord) -> [String: Int] {
        let linkedMeetings = calendarMeetingsLinkedToDoctoralCandidates()[candidate.id] ?? []
        let generation = calendarContentGeneration
        if let memo = doctoralSupervisionActivityMinutesMemo[candidate.id],
           memo.calendarGeneration == generation,
           memo.periods == candidate.supervisionPeriods {
            return memo.minutesByPeriodID
        }
        let minutes = doctoralSupervisionCalendarActivityMinutesByPeriodID(
            candidate: candidate,
            periods: candidate.supervisionPeriods,
            meetings: linkedMeetings
        )
        doctoralSupervisionActivityMinutesMemo[candidate.id] = DoctoralSupervisionActivityMinutesMemoEntry(
            calendarGeneration: generation,
            periods: candidate.supervisionPeriods,
            minutesByPeriodID: minutes
        )
        return minutes
    }
}
