import Foundation

struct CalendarMeetingHoursSummary: Equatable {
    var completedMeetingCount: Int = 0
    var completedMinutes: Int = 0
    var completedMeetings: [CalendarMeetingStatisticsMeeting] = []
    var completedMeetingsWithoutDurationCount: Int = 0
    var plannedMeetingCount: Int = 0
    var plannedMinutes: Int = 0
    var plannedMeetings: [CalendarMeetingStatisticsMeeting] = []
    var plannedMeetingsWithoutDurationCount: Int = 0
    var activityMinutes: [String: Int] = [:]
    var meetingModeMinutes: [String: Int] = [:]

    var meetingsWithoutDurationCount: Int {
        completedMeetingsWithoutDurationCount + plannedMeetingsWithoutDurationCount
    }
}

struct CalendarMeetingStatisticsMeeting: Equatable, Identifiable {
    let id: String
    let source: CalendarWorkspaceEventSource
    let title: String
    let activityType: String
    let meetingMode: String
    let participantNames: [String]
    let displayDate: Date
    let startTime: String
    let endTime: String
    let durationMinutes: Int?
}

enum CalendarMeetingStatisticsScope {
    case project(String)
    case publication(String)
    case application(String)
    case researcher(PublicationAuthor)
}

@MainActor
func calendarMeetingHoursSummary(
    store: GrantDataStore,
    scope: CalendarMeetingStatisticsScope,
    referenceDate: Date = Date()
) -> CalendarMeetingHoursSummary {
    calendarMeetingHoursSummary(
        meetings: store.calendarMeetingRecords,
        referenceDate: referenceDate
    ) { meeting in
        switch scope {
        case let .project(projectID):
            return calendarMeetingProjectIDs(for: meeting, store: store).contains(projectID)
        case let .publication(publicationID):
            let normalizedPublicationID = publicationID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPublicationID.isEmpty else { return false }
            return meeting.publicationIDs.compactMap(\.trimmedOrNil).contains(normalizedPublicationID)
        case let .application(applicationID):
            let normalizedApplicationID = applicationID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedApplicationID.isEmpty else { return false }
            return meeting.applicationIDs.compactMap(\.trimmedOrNil).contains(normalizedApplicationID)
        case let .researcher(author):
            if store.isCurrentUserAuthor(author) {
                return !store.calendarCategoryIsExcludedFromMeetingStatistics(named: meeting.meetingType)
            }
            if meeting.researcherID?.trimmedOrNil == author.id {
                return true
            }
            // F13d: the participant link first, the written name as fallback.
            if meeting.participantAuthorIDs.contains(where: { $0.trimmedOrNil == author.id }) {
                return true
            }
            let nameKeys = Set(author.presentedNameCandidates.map(calendarMeetingStatisticsNameKey).filter { !$0.isEmpty })
            guard !nameKeys.isEmpty else { return false }
            return meeting.participantNames.contains { participant in
                nameKeys.contains(calendarMeetingStatisticsNameKey(participant))
            }
        }
    }
}

func calendarMeetingHoursSummary(
    meetings: [CalendarMeetingRecord],
    calendar: Calendar = Calendar.current,
    referenceDate: Date = Date(),
    matchingMeeting: (CalendarMeetingRecord) -> Bool
) -> CalendarMeetingHoursSummary {
    var summary = CalendarMeetingHoursSummary()
    for meeting in meetings where matchingMeeting(meeting) {
        let durationMinutes = calendarMeetingStatisticsDurationMinutes(meeting)
        let bucket = calendarMeetingStatisticsBucket(for: meeting, calendar: calendar, referenceDate: referenceDate)
        let displayDate = calendarMeetingStatisticsDate(meeting.date, calendar: calendar)
        let row = displayDate.map { date in
            CalendarMeetingStatisticsMeeting(
                id: meeting.id,
                source: .meeting(meeting.id),
                title: meeting.title.trimmingCharacters(in: .whitespacesAndNewlines),
                activityType: meeting.meetingType.trimmingCharacters(in: .whitespacesAndNewlines),
                meetingMode: meeting.meetingMode.trimmingCharacters(in: .whitespacesAndNewlines),
                participantNames: meeting.participantNames.compactMap(\.trimmedOrNil),
                displayDate: calendar.startOfDay(for: date),
                startTime: normalizedCalendarTimeInput(meeting.startTime),
                endTime: normalizedCalendarTimeInput(meeting.endTime),
                durationMinutes: durationMinutes
            )
        }

        if let durationMinutes, durationMinutes > 0 {
            let activityType = meeting.meetingType.trimmedOrNil ?? ""
            summary.activityMinutes[activityType, default: 0] += durationMinutes
            if calendarMeetingStatisticsIsMeetingCategory(activityType) {
                let mode = meeting.meetingMode.trimmedOrNil ?? ""
                summary.meetingModeMinutes[mode, default: 0] += durationMinutes
            }
        }

        switch bucket {
        case .completed:
            summary.completedMeetingCount += 1
            summary.completedMinutes += durationMinutes ?? 0
            if durationMinutes == nil {
                summary.completedMeetingsWithoutDurationCount += 1
            }
            if let row {
                summary.completedMeetings.append(row)
            }
        case .planned:
            summary.plannedMeetingCount += 1
            summary.plannedMinutes += durationMinutes ?? 0
            if durationMinutes == nil {
                summary.plannedMeetingsWithoutDurationCount += 1
            }
            if let row {
                summary.plannedMeetings.append(row)
            }
        case .unknown:
            break
        }
    }

    summary.completedMeetings.sort {
        calendarMeetingStatisticsMeetingSort($0, $1, newestFirst: true)
    }
    summary.plannedMeetings.sort {
        calendarMeetingStatisticsMeetingSort($0, $1, newestFirst: false)
    }
    return summary
}

private func calendarMeetingStatisticsIsMeetingCategory(_ rawType: String) -> Bool {
    let key = normalizedCalendarCategoryLookupKey(rawType)
    return key == normalizedCalendarCategoryLookupKey("Möte")
        || key == normalizedCalendarCategoryLookupKey("Meeting")
}

func teachingAssignmentCalendarActivityMinutesByPeriodID(
    assignmentID: String,
    periods: [TeachingAssignmentPeriod],
    meetings: [CalendarMeetingRecord],
    calendar: Calendar = Calendar.current
) -> [String: Int] {
    let normalizedAssignmentID = assignmentID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedAssignmentID.isEmpty else { return [:] }

    var minutesByPeriodID: [String: Int] = [:]
    let linkedMeetings = meetings.compactMap { meeting -> (meeting: CalendarMeetingRecord, assignmentIDs: [String])? in
        let assignmentIDs = calendarMeetingTeachingAssignmentIDs(meeting)
        guard assignmentIDs.contains(normalizedAssignmentID) else { return nil }
        return (meeting, assignmentIDs)
    }
    guard !linkedMeetings.isEmpty else { return [:] }

    for period in periods where !period.isEmpty {
        var normalizedPeriod = period
        normalizedPeriod.normalize()
        guard let bounds = teachingAssignmentCalendarActivityBounds(for: normalizedPeriod, calendar: calendar) else {
            continue
        }
        var totalMinutes = 0
        for linkedMeeting in linkedMeetings {
            guard let meetingDate = calendarMeetingStatisticsDate(linkedMeeting.meeting.date, calendar: calendar),
                  meetingDate >= bounds.start,
                  meetingDate <= bounds.end,
                  let durationMinutes = calendarMeetingStatisticsDurationMinutes(linkedMeeting.meeting) else {
                continue
            }
            totalMinutes += calendarMeetingStatisticsAllocatedMinutes(
                durationMinutes,
                assignmentID: normalizedAssignmentID,
                linkedAssignmentIDs: linkedMeeting.assignmentIDs
            )
        }
        if totalMinutes > 0 {
            minutesByPeriodID[normalizedPeriod.id] = totalMinutes
        }
    }
    return minutesByPeriodID
}

func doctoralSupervisionCalendarActivityMinutesByPeriodID(
    candidate: DoctoralCandidateRecord,
    periods: [DoctoralSupervisionPeriod],
    meetings: [CalendarMeetingRecord],
    calendar: Calendar = Calendar.current
) -> [String: Int] {
    let linkedMeetings = meetings.filter { meeting in
        calendarMeetingDoctoralCandidateIDs(meeting).contains(candidate.id)
    }
    guard !linkedMeetings.isEmpty else { return [:] }

    var minutesByPeriodID: [String: Int] = [:]
    for period in periods where !period.isEmpty {
        var normalizedPeriod = period
        normalizedPeriod.normalize()
        guard let bounds = doctoralSupervisionCalendarActivityBounds(for: normalizedPeriod, calendar: calendar) else {
            continue
        }
        var totalMinutes = 0
        for meeting in linkedMeetings {
            guard let meetingDate = calendarMeetingStatisticsDate(meeting.date, calendar: calendar),
                  meetingDate >= bounds.start,
                  meetingDate <= bounds.end,
                  let durationMinutes = calendarMeetingStatisticsDurationMinutes(meeting) else {
                continue
            }
            totalMinutes += durationMinutes
        }
        if totalMinutes > 0 {
            minutesByPeriodID[normalizedPeriod.id] = totalMinutes
        }
    }
    return minutesByPeriodID
}

func calendarMeetingTeachingAssignmentIDs(_ meeting: CalendarMeetingRecord) -> [String] {
    let combined = meeting.teachingAssignmentIDs + [meeting.teachingAssignmentID].compactMap { $0 }
    return Array(NSOrderedSet(array: combined.compactMap(\.trimmedOrNil))) as? [String]
        ?? combined.compactMap(\.trimmedOrNil)
}

func calendarMeetingDoctoralCandidateIDs(_ meeting: CalendarMeetingRecord) -> [String] {
    let combined = meeting.doctoralCandidateIDs + [meeting.doctoralCandidateID].compactMap { $0 }
    return Array(NSOrderedSet(array: combined.compactMap(\.trimmedOrNil))) as? [String]
        ?? combined.compactMap(\.trimmedOrNil)
}

private func doctoralSupervisionCalendarActivityBounds(
    for period: DoctoralSupervisionPeriod,
    calendar: Calendar
) -> (start: Date, end: Date)? {
    let start = period.from.nonEmpty
        .flatMap(DateParsers.isoDay.date(from:))
        .map { calendar.startOfDay(for: $0) }
    let end = period.to.nonEmpty
        .flatMap(DateParsers.isoDay.date(from:))
        .map { calendar.startOfDay(for: $0) }

    switch (start, end) {
    case let (start?, end?):
        guard start <= end else { return nil }
        return (start, end)
    case let (start?, nil):
        return (start, .distantFuture)
    case let (nil, end?):
        return (.distantPast, end)
    case (nil, nil):
        return nil
    }
}

private func teachingAssignmentCalendarActivityBounds(
    for period: TeachingAssignmentPeriod,
    calendar: Calendar
) -> (start: Date, end: Date)? {
    let start = period.from.nonEmpty
        .flatMap(DateParsers.isoDay.date(from:))
        .map { calendar.startOfDay(for: $0) }
    let end = period.to.nonEmpty
        .flatMap(DateParsers.isoDay.date(from:))
        .map { calendar.startOfDay(for: $0) }

    switch (start, end) {
    case let (start?, end?):
        guard start <= end else { return nil }
        return (start, end)
    case let (start?, nil):
        return (start, .distantFuture)
    case let (nil, end?):
        return (.distantPast, end)
    case (nil, nil):
        return nil
    }
}

private enum CalendarMeetingStatisticsBucket {
    case completed
    case planned
    case unknown
}

private func calendarMeetingStatisticsBucket(
    for meeting: CalendarMeetingRecord,
    calendar: Calendar,
    referenceDate: Date
) -> CalendarMeetingStatisticsBucket {
    guard let day = calendarMeetingStatisticsDate(meeting.date, calendar: calendar) else { return .unknown }
    let meetingDay = calendar.startOfDay(for: day)
    let referenceDay = calendar.startOfDay(for: referenceDate)

    if meetingDay < referenceDay {
        return .completed
    }
    if meetingDay > referenceDay {
        return .planned
    }

    if let endDate = calendarMeetingStatisticsDateTime(day: day, time: meeting.endTime, calendar: calendar) {
        return endDate <= referenceDate ? .completed : .planned
    }
    if let startDate = calendarMeetingStatisticsDateTime(day: day, time: meeting.startTime, calendar: calendar) {
        return startDate < referenceDate ? .completed : .planned
    }
    return .planned
}

private func calendarMeetingStatisticsDurationMinutes(_ meeting: CalendarMeetingRecord) -> Int? {
    guard let startMinutes = calendarMeetingStatisticsTimeMinutes(meeting.startTime),
          let endMinutes = calendarMeetingStatisticsTimeMinutes(meeting.endTime),
          endMinutes > startMinutes else {
        return nil
    }
    return endMinutes - startMinutes
}

private func calendarMeetingStatisticsAllocatedMinutes(
    _ totalMinutes: Int,
    assignmentID: String,
    linkedAssignmentIDs: [String]
) -> Int {
    let orderedIDs = Array(Set(linkedAssignmentIDs.compactMap(\.trimmedOrNil))).sorted()
    guard totalMinutes > 0,
          let index = orderedIDs.firstIndex(of: assignmentID),
          !orderedIDs.isEmpty else {
        return 0
    }
    let baseShare = totalMinutes / orderedIDs.count
    let remainder = totalMinutes % orderedIDs.count
    return baseShare + (index < remainder ? 1 : 0)
}

private func calendarMeetingStatisticsDate(_ raw: String, calendar: Calendar) -> Date? {
    let normalized = DateParsers.canonicalizedDayInput(raw)
    guard let parsed = DateParsers.isoDay.date(from: normalized) else { return nil }
    let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: parsed)
    return calendar.date(from: components)
}

private func calendarMeetingStatisticsDateTime(day: Date, time: String, calendar: Calendar) -> Date? {
    guard let minutes = calendarMeetingStatisticsTimeMinutes(time) else { return nil }
    return calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: day))
}

private func calendarMeetingStatisticsTimeMinutes(_ raw: String) -> Int? {
    let normalized = normalizedCalendarTimeInput(raw)
    let parts = normalized.split(separator: ":")
    guard parts.count == 2,
          let hours = Int(parts[0]),
          let minutes = Int(parts[1]),
          (0..<24).contains(hours),
          (0..<60).contains(minutes) else {
        return nil
    }
    return (hours * 60) + minutes
}

private func calendarMeetingStatisticsMeetingSort(
    _ lhs: CalendarMeetingStatisticsMeeting,
    _ rhs: CalendarMeetingStatisticsMeeting,
    newestFirst: Bool
) -> Bool {
    if lhs.displayDate != rhs.displayDate {
        return newestFirst ? lhs.displayDate > rhs.displayDate : lhs.displayDate < rhs.displayDate
    }
    let lhsStart = calendarMeetingStatisticsTimeMinutes(lhs.startTime) ?? Int.max
    let rhsStart = calendarMeetingStatisticsTimeMinutes(rhs.startTime) ?? Int.max
    if lhsStart != rhsStart {
        return lhsStart < rhsStart
    }
    if lhs.title.localizedCaseInsensitiveCompare(rhs.title) != .orderedSame {
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
    return lhs.id < rhs.id
}

@MainActor
func calendarMeetingProjectIDs(for meeting: CalendarMeetingRecord, store: GrantDataStore) -> [String] {
    var projectIDs = meeting.projectIDs.isEmpty ? (meeting.projectID.map { [$0] } ?? []) : meeting.projectIDs
    for applicationID in meeting.applicationIDs.compactMap(\.trimmedOrNil) {
        if let projectID = store.application(id: applicationID)?.projectID?.trimmedOrNil {
            projectIDs.append(projectID)
        }
    }
    for publicationID in meeting.publicationIDs.compactMap(\.trimmedOrNil) {
        if let projectID = store.publication(id: publicationID)?.projectID?.trimmedOrNil {
            projectIDs.append(projectID)
        }
    }
    for appearanceID in meeting.mediaAppearanceIDs.compactMap(\.trimmedOrNil) {
        if let appearance = store.cvMediaAppearances.first(where: { $0.id == appearanceID }) {
            projectIDs.append(contentsOf: appearance.projectIDs)
        }
    }
    return Array(NSOrderedSet(array: projectIDs.compactMap(\.trimmedOrNil))) as? [String]
        ?? projectIDs.compactMap(\.trimmedOrNil)
}

private func calendarMeetingStatisticsNameKey(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

/// No longer used: the statistics follow the category setting "Do not count
/// in meeting statistics" (Settings > Calendar categories). These were the
/// old fixed names, which are now only that setting's defaults.
private func calendarMeetingStatisticsIsExcludedCurrentUserCategory(_ raw: String) -> Bool {
    let key = normalizedCalendarCategoryLookupKey(raw)
    return key == normalizedCalendarCategoryLookupKey("Resa")
        || key == normalizedCalendarCategoryLookupKey("Travel")
        || key == normalizedCalendarCategoryLookupKey("Klinik")
        || key == normalizedCalendarCategoryLookupKey("Clinic")
}
