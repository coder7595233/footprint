import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum CalendarWorkspaceEventSource: Hashable {
    case holiday(String)
    case application(String)
    case organizationTask(organizationID: String, taskID: String)
    case projectTask(projectID: String, taskID: String)
    case publicationTask(publicationID: String, taskID: String)
    case teachingTask(taskID: String)
    case reviewDeadline(String)
    case congress(organizationID: String, congressID: String)
    case travel(String)
    case accommodation(String)
    case meeting(String)
    case mediaAppearance(String)
}

struct CalendarWorkspaceEvent: Identifiable {
    let id: String
    let source: CalendarWorkspaceEventSource
    var automaticHideKey: String? = nil
    var isHiddenFromCalendar: Bool = false
    let displayDate: Date
    var rangeStartDate: Date? = nil
    var rangeEndDate: Date? = nil
    var isRolledOverPastDue: Bool = false
    var isDateUncertain: Bool = false
    let title: String
    let subtitle: String
    let detail: String
    let place: String
    let timeText: String
    let kind: CalendarWorkspaceEventKind
    var meetingCategoryName: String? = nil
    var travelMode: CalendarTravelMode? = nil
    /// The calendar list's own title: a meeting's title without the
    /// participants that `title` carries in parentheses. Nil when the list
    /// shows `title` as it is.
    var listTitle: String? = nil
    /// The people the calendar list shows on their own line under the title.
    var participantNames: [String] = []
    /// The organisation the calendar list can show in parentheses after the
    /// title ("Intervju (Påhittat universitet)").
    var organizationName: String? = nil
    /// The calendar list's detail line split into its parts, so the
    /// "Visa i raden" settings can leave parts out. Nil: the list shows
    /// `detail` as one part. Participants and the organisation are not
    /// repeated here; the list shows them on their own.
    var detailParts: [CalendarWorkspaceDetailPart]? = nil
    let completedOn: String?
    let action: (() -> Void)?
    let toggleCompletion: ((Bool) -> Void)?

    var isCompleted: Bool {
        completedOn?.trimmedOrNil != nil
    }

    var isTask: Bool {
        toggleCompletion != nil
    }
}

private func uncertainCalendarDateLabel(_ raw: String, uncertain: Bool, language: AppLanguage) -> String? {
    guard let normalized = raw.nonEmpty else { return nil }
    guard uncertain else { return normalized }
    return "\(normalized) (\(language.text("uncertain date", "osäkert datum")))"
}

private func uncertainCalendarText(_ text: String, uncertain: Bool, language: AppLanguage) -> String {
    guard uncertain else { return text }
    return "\(text) (\(language.text("uncertain date", "osäkert datum")))"
}

/// Short month name for the calendar list: "okt" in Swedish, "Oct" in English.
/// `month` is 1–12.
func calendarListMonthAbbreviation(_ month: Int, language: AppLanguage) -> String {
    let swedish = ["jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
    let english = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    let index = min(max(month, 1), 12) - 1
    return language == .swedish ? swedish[index] : english[index]
}

/// Short weekday name for the calendar list: "Fre" / "Fri".
/// `weekday` follows `Calendar`: 1 is Sunday, 7 is Saturday.
func calendarListWeekdayAbbreviation(_ weekday: Int, language: AppLanguage) -> String {
    let swedish = ["Sön", "Mån", "Tis", "Ons", "Tor", "Fre", "Lör"]
    let english = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    let index = min(max(weekday, 1), 7) - 1
    return language == .swedish ? swedish[index] : english[index]
}

/// The merged day column in the calendar list: "Fre 2 okt" / "Fri 2 Oct".
func calendarListShortDayLabel(weekday: Int, day: Int, month: Int, language: AppLanguage) -> String {
    "\(calendarListWeekdayAbbreviation(weekday, language: language)) \(day) \(calendarListMonthAbbreviation(month, language: language))"
}

/// The week header row in the calendar list, e.g.
/// "Vecka 40 · 28 sep – 4 okt 2026" / "Week 40 · 28 Sep – 4 Oct 2026".
/// `weekNumber` is nil when the week number is hidden; the year is left out
/// when `showsYear` is false.
func calendarListWeekHeaderLabel(
    weekNumber: Int?,
    startDay: Int,
    startMonth: Int,
    startYear: Int,
    endDay: Int,
    endMonth: Int,
    endYear: Int,
    showsYear: Bool,
    language: AppLanguage
) -> String {
    let startMonthText = calendarListMonthAbbreviation(startMonth, language: language)
    let endMonthText = calendarListMonthAbbreviation(endMonth, language: language)
    let range: String
    if showsYear, startYear != endYear {
        range = "\(startDay) \(startMonthText) \(startYear) – \(endDay) \(endMonthText) \(endYear)"
    } else {
        let start = startMonth == endMonth ? "\(startDay)" : "\(startDay) \(startMonthText)"
        let end = "\(endDay) \(endMonthText)"
        range = showsYear ? "\(start) – \(end) \(endYear)" : "\(start) – \(end)"
    }
    guard let weekNumber else { return range }
    return "\(language.text("Week", "Vecka")) \(weekNumber) · \(range)"
}

/// The category icon for a meeting row: a camera for online meetings, a
/// phone for phone meetings and two people for meetings in person. Uses the
/// same "Online" place text the list used to show as a wifi icon.
func calendarMeetingCategoryIconName(place: String) -> String {
    let cleaned = place.trimmingCharacters(in: .whitespacesAndNewlines)
    if calendarPlaceIsOnline(cleaned) {
        return "video"
    }
    if cleaned.caseInsensitiveCompare("Telefon") == .orderedSame
        || cleaned.caseInsensitiveCompare("Phone") == .orderedSame {
        return "phone"
    }
    return "person.2"
}

func calendarPlaceIsOnline(_ place: String) -> Bool {
    place.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Online") == .orderedSame
}

/// The parts a calendar list row can show besides its title. Each one has a
/// checkbox under "Visa i raden" in the calendar sidebar.
enum CalendarListDetailKind: String, CaseIterable, Hashable, Identifiable {
    case participants
    case organization
    case publication
    case application
    case teaching
    case doctoralCandidate
    case congress
    case media
    case note
    case reference

    var id: String { rawValue }

    /// Stored among the calendar's hidden column keys, with a prefix so it
    /// never clashes with a column name.
    var hiddenStorageKey: String { "rowDetail.\(rawValue)" }

    func title(language: AppLanguage) -> String {
        switch self {
        case .participants:
            return language.text("Participants", "Deltagare")
        case .organization:
            return language.text("Organisation", "Organisation")
        case .publication:
            return language.text("Publication", "Publikation")
        case .application:
            return language.text("Application", "Ansökan")
        case .teaching:
            return language.text("Teaching", "Undervisning")
        case .doctoralCandidate:
            return language.text("Doctoral candidate", "Doktorand")
        case .congress:
            return language.text("Congress", "Kongress")
        case .media:
            return language.text("Media", "Media")
        case .note:
            return language.text("Notes", "Anteckningar")
        case .reference:
            return language.text("Booking reference", "Bokningsreferens")
        }
    }
}

/// One part of a calendar list row's grey detail line. Parts without a kind
/// (an uncertain date, "Hybrid", a deadline's own dates) always show.
struct CalendarWorkspaceDetailPart: Hashable {
    let kind: CalendarListDetailKind?
    let text: String

    init(_ kind: CalendarListDetailKind?, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

/// The detail parts that have text, in order. Builders pass optional texts
/// and keep only the ones that are there.
func calendarDetailParts(_ parts: [(CalendarListDetailKind?, String?)]) -> [CalendarWorkspaceDetailPart] {
    parts.compactMap { part -> CalendarWorkspaceDetailPart? in
        guard let text = part.1?.trimmedOrNil else { return nil }
        return CalendarWorkspaceDetailPart(part.0, text)
    }
}

/// The title on a calendar list row: the title, then the organisation in
/// parentheses when one is given and it is not already the title itself,
/// e.g. "Intervju postdoc (Påhittat universitet)". Pass nil as the
/// organisation when the Organisation setting is off.
func calendarListTitleText(title: String, organization: String?) -> String {
    let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedTitle.isEmpty,
          let organization = organization?.trimmedOrNil,
          cleanedTitle.caseInsensitiveCompare(organization) != .orderedSame,
          !cleanedTitle.hasSuffix("(\(organization))") else {
        return cleanedTitle
    }
    return "\(cleanedTitle) (\(organization))"
}

/// The participants line under a calendar list row's title: "Anna, Bertil".
func calendarListParticipantsText(_ names: [String]) -> String {
    var seen = Set<String>()
    return names
        .compactMap(\.trimmedOrNil)
        .filter { seen.insert($0).inserted }
        .joined(separator: ", ")
}

/// A meeting's title in two forms: `title` with the participants in
/// parentheses ("Möte (Anna, Bertil)"), as the rest of the app shows it, and
/// `listTitle` with `participantNames` apart, for the calendar list.
/// Categories marked "Leave" show no title and no participants.
struct CalendarMeetingTitleParts: Equatable {
    let title: String
    let listTitle: String
    let participantNames: [String]
}

func calendarMeetingTitleParts(
    title rawTitle: String,
    participantNames: [String],
    isLeave: Bool,
    language: AppLanguage
) -> CalendarMeetingTitleParts {
    // Categories marked "Leave" in Settings > Calendar categories show no title.
    guard !isLeave else {
        return CalendarMeetingTitleParts(title: "", listTitle: "", participantNames: [])
    }
    let base = rawTitle.nonEmpty ?? language.text("Activity", "Aktivitet")
    let title = participantNames.isEmpty
        ? base
        : "\(base) (\(participantNames.joined(separator: ", ")))"
    return CalendarMeetingTitleParts(
        title: title,
        listTitle: base,
        participantNames: participantNames.compactMap(\.trimmedOrNil)
    )
}

/// What a link button next to a calendar list title opens. It decides the
/// button's symbol: the same symbol as the page the link opens.
enum CalendarListLinkTarget: Hashable {
    case project
    case publication
    case application
    case organization
    case congress
    case doctoralCandidate
    case teaching
    case web
}

func calendarListLinkSymbolName(for target: CalendarListLinkTarget) -> String {
    switch target {
    case .project:
        return AppTab.projects.symbolName
    case .publication:
        return AppTab.publications.symbolName
    case .application:
        return AppTab.applications.symbolName
    case .organization:
        return AppTab.organizations.symbolName
    case .congress:
        return AppTab.congresses.symbolName
    case .doctoralCandidate:
        return AppTab.doctoralCandidates.symbolName
    case .teaching:
        return AppTab.teaching.symbolName
    case .web:
        return "link"
    }
}

/// The grey detail line of a calendar list row, with the parts the
/// "Visa i raden" settings hide left out. Rows without split parts show
/// their whole detail text as before.
func calendarListVisibleDetailText(
    for event: CalendarWorkspaceEvent,
    hiddenKinds: Set<CalendarListDetailKind>,
    language: AppLanguage
) -> String {
    guard let parts = event.detailParts else {
        return calendarWorkspaceVisibleDetailText(for: event, language: language)
    }
    let uncertainText: String? = event.isDateUncertain ? language.text("Uncertain date", "Osäkert datum") : nil
    let shownParts: [String] = parts
        .filter { part in part.kind.map { !hiddenKinds.contains($0) } ?? true }
        .map(\.text)
    return ([uncertainText] + shownParts.map { Optional($0) })
        .compactMap { $0?.trimmedOrNil }
        .joined(separator: " · ")
}

func calendarWorkspaceVisibleDetailText(for event: CalendarWorkspaceEvent, language: AppLanguage) -> String {
    let uncertainText = event.isDateUncertain ? language.text("Uncertain date", "Osäkert datum") : nil
    let isCongressDeadline: Bool = {
        if case .congress = event.source {
            return event.kind == .applicationDeadline
        }
        return false
    }()

    if isCongressDeadline {
        return uncertainText ?? ""
    }

    return [
        uncertainText,
        event.detail.nonEmpty
    ]
    .compactMap { $0 }
    .joined(separator: " · ")
}

enum CalendarWorkspaceEventKind {
    case holiday
    case congress
    case travel
    case accommodation
    case meeting
    case applicationDeadline
    case taskDeadline

    var sortRank: Int {
        switch self {
        case .holiday:
            return 0
        case .travel:
            return 1
        case .accommodation:
            return 2
        case .taskDeadline:
            return 3
        case .meeting:
            return 4
        case .applicationDeadline:
            return 5
        case .congress:
            return 6
        }
    }

    var background: Color {
        switch self {
        case .holiday:
            return AppPalette.vividRed.opacity(0.92)
        case .congress:
            return AppPalette.vividBlue.opacity(0.86)
        case .travel:
            return AppPalette.vividGreen.opacity(0.86)
        case .accommodation:
            return AppPalette.vividGreen.opacity(0.86)
        case .meeting:
            return AppPalette.vividBlue.opacity(0.86)
        case .applicationDeadline:
            return AppPalette.vividBlue.opacity(0.86)
        case .taskDeadline:
            return AppPalette.vividOrange.opacity(0.86)
        }
    }

    var foreground: Color {
        AppPalette.semanticOnColor
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .holiday:
            return language.text("Holiday", "Helgdag")
        case .congress:
            return language.text("Congress", "Kongress")
        case .travel:
            return language.text("Travel", "Resa")
        case .accommodation:
            return language.text("Accommodation", "Boende")
        case .meeting:
            return language.text("Activity", "Aktivitet")
        case .applicationDeadline:
            return language.text("Application deadline", "Ansökningsfrist")
        case .taskDeadline:
            return language.text("Task", "Uppgift")
        }
    }

    func filterTitle(language: AppLanguage) -> String {
        switch self {
        case .holiday:
            return language.text("Holidays", "Helgdagar")
        case .congress:
            return language.text("Congresses", "Kongresser")
        case .travel:
            return language.text("Travel", "Resor")
        case .accommodation:
            return language.text("Accommodation", "Boende")
        case .meeting:
            return language.text("Activities", "Aktiviteter")
        case .applicationDeadline:
            return language.text("Deadlines", "Deadlines")
        case .taskDeadline:
            return language.text("Tasks", "Uppgifter")
        }
    }

    var filterStorageKey: String {
        switch self {
        case .holiday:
            return "holiday"
        case .congress:
            return "congress"
        case .travel:
            return "travel"
        case .accommodation:
            return "accommodation"
        case .meeting:
            return "meeting"
        case .applicationDeadline:
            return "application"
        case .taskDeadline:
            return "task"
        }
    }
}

private enum CalendarWorkspaceColumn: String, CaseIterable, Hashable, Identifiable {
    case weekday
    case date
    case time
    case category
    case project
    case title
    case completion
    case details
    case place
    case dayLocation
    case conferences

    var id: String { rawValue }

    var width: CGFloat {
        switch self {
        case .weekday:
            return 92
        case .date:
            return 88
        case .time:
            return 76
        case .category:
            return 104
        case .project:
            return 170
        case .title:
            return 210
        case .completion:
            // Room for the "Klar"/"Done" header; the ring sits centred.
            return 42
        case .details:
            return 280
        case .place:
            return 190
        case .dayLocation:
            return 120
        case .conferences:
            return 88
        }
    }

    var trailingSpacing: CGFloat {
        switch self {
        case .completion:
            return 6
        case .conferences:
            return 8
        case .weekday, .date, .time, .category:
            return 10
        case .project, .title, .details, .place, .dayLocation:
            return 12
        }
    }

    var gridItem: GridItem {
        switch self {
        case .title:
            return GridItem(.flexible(minimum: width), spacing: trailingSpacing, alignment: .leading)
        case .details:
            return GridItem(.flexible(minimum: width), spacing: trailingSpacing, alignment: .leading)
        case .completion:
            return GridItem(.fixed(width), spacing: trailingSpacing, alignment: .center)
        default:
            return GridItem(.fixed(width), spacing: trailingSpacing, alignment: .leading)
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .weekday:
            return language.text("Day", "Veckodag")
        case .date:
            return language.text("Date", "Datum")
        case .time:
            return language.text("Time", "Tid")
        case .category:
            return language.text("Category", "Kategori")
        case .project:
            return language.text("Project", "Projekt")
        case .title:
            return language.text("Title", "Rubrik")
        case .completion:
            return language.text("Done", "Klar")
        case .details:
            return language.text("Details", "Detaljer")
        case .place:
            return language.text("Place", "Plats")
        case .dayLocation:
            return language.text("Your location", "Din plats")
        case .conferences:
            return language.text("Conferences", "Konferenser")
        }
    }
}

private enum CalendarWorkspaceMarkerColumn: String, CaseIterable, Hashable, Identifiable {
    case year = "year"
    case weekNumber = "weekNumber"

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .year:
            return language.text("Year", "År")
        case .weekNumber:
            return language.text("Week number", "Veckonummer")
        }
    }
}

private struct CalendarWorkspaceDayGroup: Identifiable {
    let id: String
    let date: Date
    let events: [CalendarWorkspaceEvent]
    let conferenceEvents: [CalendarWorkspaceEvent]
    let holidays: [HolidayDefinition]
    let dateLabel: String
    let weekdayLabel: String
    let dayEndLocation: String
    let isPast: Bool
    let topSpacing: CGFloat
    /// True for the first shown day of a week; that day carries the week's
    /// header row ("Vecka 40 · 28 sep – 4 okt 2026").
    var startsWeek: Bool = false
}

private struct CalendarDayLocation: Hashable {
    let key: String
    let label: String
}

private struct CalendarDetailLinkPresentation {
    let visibleText: String
    let urls: [URL]
}

/// What the calendar list shows of a row's details: the grey line under the
/// title and the link arrows next to it.
private struct CalendarListRowDetail {
    let visibleText: String
    let congressLink: CalendarDetailRecordLink?
    let recordLinks: [CalendarDetailRecordLink]
    let urls: [URL]
    let helpText: String

    var hasTextLine: Bool {
        congressLink != nil || !visibleText.isEmpty
    }

    var hasLinkButtons: Bool {
        !recordLinks.isEmpty || !urls.isEmpty
    }
}

private enum CalendarDetailLinkParser {
    static let expression = try? NSRegularExpression(
        pattern: #"(?i)\b((?:https?://|www\.)\S+)"#
    )
}

private func calendarDetailLinkPresentation(from rawText: String) -> CalendarDetailLinkPresentation {
    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let expression = CalendarDetailLinkParser.expression else {
        return CalendarDetailLinkPresentation(visibleText: trimmed, urls: [])
    }

    let nsText = trimmed as NSString
    let matches = expression.matches(
        in: trimmed,
        range: NSRange(location: 0, length: nsText.length)
    )

    guard !matches.isEmpty else {
        return CalendarDetailLinkPresentation(visibleText: trimmed, urls: [])
    }

    var urls: [URL] = []
    var seen = Set<String>()
    let mutableText = NSMutableString(string: trimmed)

    for match in matches.reversed() {
        let rawLink = nsText.substring(with: match.range)
        let cleanedLink = calendarDetailLinkString(from: rawLink)
        if let url = normalizedWebLinkURL(cleanedLink) {
            let key = url.absoluteString
            if seen.insert(key).inserted {
                urls.insert(url, at: 0)
            }
        }
        mutableText.replaceCharacters(in: match.range, with: "")
    }

    return CalendarDetailLinkPresentation(
        visibleText: calendarDetailTextAfterRemovingLinks(String(mutableText)),
        urls: urls
    )
}

private func calendarDetailLinkString(from rawLink: String) -> String {
    var cleaned = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
    let trailingCharacters = CharacterSet(charactersIn: ".,;!?)\"]}")
    while let last = cleaned.unicodeScalars.last,
          trailingCharacters.contains(last) {
        cleaned.removeLast()
    }
    return cleaned
}

private func calendarDetailTextAfterRemovingLinks(_ rawText: String) -> String {
    let collapsedInlineWhitespace = rawText
        .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)

    return collapsedInlineWhitespace
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func calendarSearchableFieldText<Value: Encodable>(_ value: Value) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let object = try? JSONSerialization.jsonObject(with: data) else {
        return ""
    }

    var values: [String] = []

    func appendValues(from object: Any) {
        switch object {
        case let value as String:
            if let value = value.trimmedOrNil {
                values.append(value)
            }
        case let valuesByKey as [String: Any]:
            for key in valuesByKey.keys.sorted() {
                if let value = valuesByKey[key] {
                    appendValues(from: value)
                }
            }
        case let array as [Any]:
            array.forEach(appendValues)
        default:
            break
        }
    }

    appendValues(from: object)
    return values.joined(separator: " ")
}

func calendarFilteredCandidateDates(
    _ dates: Set<Date>,
    isSearchActive: Bool,
    isInsideRenderedWindow: (Date) -> Bool
) -> [Date] {
    dates
        .filter { isSearchActive || isInsideRenderedWindow($0) }
        .sorted()
}

private struct CalendarWorkspaceCache {
    var allDates: [Date] = []
    var events: [CalendarWorkspaceEvent] = []
    var holidaysByDay: [String: [HolidayDefinition]] = [:]
    var dayEndLocations: [String: CalendarDayLocation] = [:]
    var dateLabelsByDay: [String: String] = [:]
    var weekdayLabelsByDay: [String: String] = [:]
    var projectReferencesByEventID: [String: [(id: String, label: String)]] = [:]
    var visibleDetailTextByEventID: [String: String] = [:]
    var detailLinkPresentationByEventID: [String: CalendarDetailLinkPresentation] = [:]
    /// The list row's detail line for rows split into parts, with the parts
    /// hidden under "Visa i raden" left out.
    var listDetailPresentationByEventID: [String: CalendarDetailLinkPresentation] = [:]
    var searchTextByEventID: [String: String] = [:]
    var projectOptions: [(id: String, label: String)] = []
    var researcherOptions: [String] = []
    var applicationsByID: [String: GrantApplication] = [:]
    var organizationsByID: [String: OrganizationRecord] = [:]
    var projectsByID: [String: ProjectRecord] = [:]
    var publicationsByID: [String: PublicationRecord] = [:]
    var teachingAssignmentsByID: [String: TeachingAssignment] = [:]
    var teachingCoursesByID: [String: TeachingCourse] = [:]
    var doctoralCandidatesByID: [String: DoctoralCandidateRecord] = [:]
    var teachingTasksByID: [String: PublicationTaskItem] = [:]
    var reviewEntriesByID: [String: CVReviewEntry] = [:]
    var publicationAuthorsByID: [String: PublicationAuthor] = [:]
    var travelRecordsByID: [String: CalendarTravelRecord] = [:]
    var accommodationRecordsByID: [String: CalendarAccommodationRecord] = [:]
    var meetingRecordsByID: [String: CalendarMeetingRecord] = [:]
    var rangeStart: Date? = nil
    var rangeEnd: Date? = nil
    var isWindowScoped: Bool = false
}

private struct CalendarWorkspaceCacheSignature: Equatable {
    let value: Int
}

private struct CalendarWorkspaceEventSourceIndexSignature: Equatable {
    let value: Int
}

private enum CalendarWorkspaceCacheBuildScope {
    case visibleWindow
    case full
}

private struct CalendarWorkspaceDerivedDataSignature: Equatable {
    let value: Int
}

private struct CalendarRenderedDateWindow: Equatable {
    let start: Date
    let end: Date

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= start && day <= end
    }
}

private struct CalendarWorkspaceDerivedData {
    var dayGroups: [CalendarWorkspaceDayGroup] = []
    var projectFilterOptions: [(id: String, label: String)] = []
    var researcherFilterOptions: [String] = []
    var dayLocationFilterOptions: [(String, String)] = []
    var meetingCategoryFilterOptions: [CalendarMeetingCategoryFilterOption] = []
}

struct CalendarVisibleWindowSnapshot: Equatable {
    let startDay: String
    let endDay: String
    let dayCount: Int
    let eventCount: Int
    let conferenceEventCount: Int

    static let empty = CalendarVisibleWindowSnapshot(
        startDay: "",
        endDay: "",
        dayCount: 0,
        eventCount: 0,
        conferenceEventCount: 0
    )
}

private func calendarVisibleWindowSnapshot(from groups: [CalendarWorkspaceDayGroup]) -> CalendarVisibleWindowSnapshot {
    guard let first = groups.first, let last = groups.last else {
        return .empty
    }
    return CalendarVisibleWindowSnapshot(
        startDay: first.id,
        endDay: last.id,
        dayCount: groups.count,
        eventCount: groups.reduce(0) { $0 + $1.events.count },
        conferenceEventCount: groups.reduce(0) { $0 + $1.conferenceEvents.count }
    )
}


private struct CalendarDayPosition: Equatable {
    let date: Date
    let minY: CGFloat
    let maxY: CGFloat
}

private struct CalendarDayPositionPreferenceKey: PreferenceKey {
    static let defaultValue: [CalendarDayPosition] = []

    static func reduce(value: inout [CalendarDayPosition], nextValue: () -> [CalendarDayPosition]) {
        value.append(contentsOf: nextValue())
    }
}

private struct CalendarWorkspaceSheet: Identifiable {
    enum Kind {
        case todo
        case travel
        case accommodation
        case congressFlight(organizationID: String, congressID: String, flightID: String)
        case meeting
        case projectTask(projectID: String)
        case publicationTask(publicationID: String)
    }

    let kind: Kind
    let recordID: String?
    let initialDateString: String?

    init(kind: Kind, recordID: String?, initialDateString: String? = nil) {
        self.kind = kind
        self.recordID = recordID
        self.initialDateString = initialDateString
    }

    private var presentationRecordID: String {
        recordID ?? initialDateString ?? "new"
    }

    var id: String {
        switch kind {
        case .todo:
            return "todo:\(presentationRecordID)"
        case .travel:
            return "travel:\(presentationRecordID)"
        case .accommodation:
            return "accommodation:\(presentationRecordID)"
        case let .congressFlight(organizationID, congressID, flightID):
            return "congressFlight:\(organizationID):\(congressID):\(flightID)"
        case .meeting:
            return "meeting:\(presentationRecordID)"
        case let .projectTask(projectID):
            return "projectTask:\(projectID):\(presentationRecordID)"
        case let .publicationTask(publicationID):
            return "publicationTask:\(publicationID):\(presentationRecordID)"
        }
    }
}

private struct CalendarEventCopyRequest: Identifiable {
    let id: String = UUID().uuidString
    let source: CalendarWorkspaceEventSource
    let title: String
    var date: String
    var startTime: String
    var endTime: String
    let allowsTimeEditing: Bool
}

private struct CalendarEventDetailSelection: Identifiable {
    let eventID: String

    var id: String { eventID }
}

private struct CalendarDetailRecordLink: Identifiable {
    enum Destination {
        case application(String)
        case publication(String)
        case congress(organizationID: String, congressID: String)
        case teachingAssignment(String)
        case teachingCourse(String)
        case doctoralCandidate(String)
    }

    let id: String
    let title: String
    let systemImage: String
    let destination: Destination

    /// What the link opens; decides its symbol in the list rows.
    var linkTarget: CalendarListLinkTarget {
        switch destination {
        case .application:
            return .application
        case .publication:
            return .publication
        case .congress:
            return .congress
        case .teachingAssignment, .teachingCourse:
            return .teaching
        case .doctoralCandidate:
            return .doctoralCandidate
        }
    }

    /// The "Visa i raden" setting that shows or hides the link in the rows.
    var detailKind: CalendarListDetailKind {
        switch destination {
        case .application:
            return .application
        case .publication:
            return .publication
        case .congress:
            return .congress
        case .teachingAssignment, .teachingCourse:
            return .teaching
        case .doctoralCandidate:
            return .doctoralCandidate
        }
    }
}

private struct CalendarViewportRestoreSnapshot {
    let verticalScrollOffset: CGFloat
    let topVisibleDate: Date
}

private struct PendingCalendarTargetedScroll: Equatable {
    let targetDate: Date
    let animated: Bool
    var attempts: Int = 0
    var scrollAttempts: Int = 0
}

private struct CalendarGrantSelectionOption: Identifiable, Hashable {
    let id: String
    let label: String
}

private struct CalendarCongressSelectionOption: Identifiable, Hashable {
    let organizationID: String
    let congressID: String
    let title: String
    let organizationName: String
    let dateText: String

    var id: String {
        calendarCongressSelectionKey(organizationID: organizationID, congressID: congressID)
    }

    var menuTitle: String {
        [title.nonEmpty, dateText.nonEmpty, organizationName.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private let calendarCongressSelectionKeySeparator = "\u{1F}"

private func calendarCongressSelectionKey(organizationID: String, congressID: String) -> String {
    [organizationID, congressID].joined(separator: calendarCongressSelectionKeySeparator)
}

private func calendarCongressSelectionIDs(from key: String) -> (organizationID: String, congressID: String)? {
    let parts = key.components(separatedBy: calendarCongressSelectionKeySeparator)
    guard parts.count == 2,
          let organizationID = parts[0].trimmedOrNil,
          let congressID = parts[1].trimmedOrNil else {
        return nil
    }
    return (organizationID, congressID)
}

private struct CalendarMeetingCategoryFilterOption: Identifiable, Hashable {
    let rawName: String
    let title: String

    var id: String {
        calendarMeetingCategoryFilterKey(for: rawName)
    }
}

private struct CalendarItalicTextModifier: ViewModifier {
    let isItalic: Bool

    func body(content: Content) -> some View {
        if isItalic {
            content.italic()
        } else {
            content
        }
    }
}

/// No calendar text is smaller than this (details, headers and labels
/// included).
private let calendarMinimumFontSize: Double = 13

private func calendarTextStyle(for role: AppTypographyRole) -> AppTextStyleSetting {
    let typography = AppAppearanceRegistry.typography()
    switch role {
    case .pageTitle:
        return typography.pageTitle
    case .sectionTitle:
        return typography.sectionTitle
    case .panelTitle:
        return typography.panelTitle
    case .tableHeader:
        return typography.tableHeader
    case .fieldLabel:
        return typography.fieldLabel
    case .body:
        return typography.body
    case .secondary:
        return typography.secondary
    case .statTitle:
        return typography.statTitle
    case .statValue:
        return typography.statValue
    }
}

private func calendarAppFont(_ role: AppTypographyRole) -> Font {
    let style = calendarTextStyle(for: role)
    return .system(
        size: max(style.size, calendarMinimumFontSize),
        weight: style.weight.swiftUIWeight,
        design: style.family.swiftUIDesign
    )
}

/// The week header row's font: semibold, 2 pt larger than the secondary
/// text size (14 pt with the standard 12 pt secondary size), never under
/// the calendar's minimum size.
private func calendarWeekHeaderFont() -> Font {
    let style = calendarTextStyle(for: .secondary)
    return .system(
        size: max(style.size + 2, calendarMinimumFontSize),
        weight: .semibold,
        design: style.family.swiftUIDesign
    )
}

private extension View {
    @ViewBuilder
    func calendarTypography(_ role: AppTypographyRole) -> some View {
        switch role {
        case .fieldLabel:
            self
                .font(calendarAppFont(role))
                .foregroundStyle(AppPalette.appText)
                .padding(.leading, AppPalette.fieldHorizontalPadding)
        default:
            self.font(calendarAppFont(role))
        }
    }
}

func calendarClampedVerticalScrollOffset(
    _ desiredOffset: CGFloat,
    contentHeight: CGFloat,
    viewportHeight: CGFloat
) -> CGFloat {
    let maxOffset = max(0, contentHeight - viewportHeight)
    return min(max(0, desiredOffset), maxOffset)
}

func calendarShouldRestoreSavedScrollOffset(
    didAttachNewScrollView: Bool,
    lastAppliedToken: Int?,
    restoreToken: Int
) -> Bool {
    restoreToken > 0 && lastAppliedToken != restoreToken
}

func calendarShouldUseDefaultOpenPosition(
    pendingOpenRequest: CalendarOpenRequest?,
    pendingRevealRequest: CalendarRevealRequest?
) -> Bool {
    pendingOpenRequest == nil && pendingRevealRequest == nil
}

func calendarShouldRestorePersistedViewport(
    hasPersistedViewport: Bool,
    pendingOpenRequest: CalendarOpenRequest?,
    pendingRevealRequest: CalendarRevealRequest?
) -> Bool {
    hasPersistedViewport
        && pendingOpenRequest == nil
        && pendingRevealRequest == nil
}

func calendarDefaultOpenDate(
    today: Date,
    calendar: Calendar = .current
) -> Date {
    let startOfToday = calendar.startOfDay(for: today)
    // Calendar navigation is always anchored at the Monday of the current
    // week. This is deliberately independent of a user's display-week setting:
    // “Today” should expose the whole working week above the current day.
    let weekday = calendar.component(.weekday, from: startOfToday)
    let daysSinceMonday = (weekday + 5) % 7 // Monday = 2 in Calendar.weekday.
    return calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfToday) ?? startOfToday
}

func calendarShouldUseStoredViewportSnapshot(
    verticalScrollOffset: CGFloat,
    topVisibleDate: Date?,
    today: Date,
    calendar: Calendar = .current
) -> Bool {
    if verticalScrollOffset > 0.5 {
        return true
    }
    guard let topVisibleDate else { return false }
    return calendar.isDate(topVisibleDate, inSameDayAs: today)
        || calendar.isDate(
            topVisibleDate,
            inSameDayAs: calendarDefaultOpenDate(today: today, calendar: calendar)
        )
}

func calendarShouldRefreshViewportRestoreToken(
    verticalScrollOffset: CGFloat,
    topVisibleDate: Date,
    today: Date,
    pendingOpenRequest: CalendarOpenRequest?,
    pendingRevealRequest: CalendarRevealRequest?,
    pendingDefaultOpenDate: Date?,
    calendar: Calendar = .current
) -> Bool {
    guard pendingOpenRequest == nil,
          pendingRevealRequest == nil,
          pendingDefaultOpenDate == nil else {
        return false
    }

    // During the first open, the list has not yet reported its real scroll offset.
    // Avoid restoring an implicit "top" position until we've either moved away from
    // the default open date or captured a non-zero offset from the rendered calendar.
    let defaultOpenDate = calendarDefaultOpenDate(today: today, calendar: calendar)
    return verticalScrollOffset > 0.5
        || !calendar.isDate(topVisibleDate, inSameDayAs: defaultOpenDate)
}

func calendarShouldPersistViewportSnapshot(
    verticalScrollOffset: CGFloat,
    topVisibleDate: Date,
    today: Date,
    pendingOpenRequest: CalendarOpenRequest?,
    pendingRevealRequest: CalendarRevealRequest?,
    pendingDefaultOpenDate: Date?,
    pendingPersistedViewportRestore: Bool,
    calendar: Calendar = .current
) -> Bool {
    guard !pendingPersistedViewportRestore,
          pendingOpenRequest == nil,
          pendingRevealRequest == nil,
          pendingDefaultOpenDate == nil else {
        return false
    }

    let defaultOpenDate = calendarDefaultOpenDate(today: today, calendar: calendar)
    return verticalScrollOffset > 0.5
        || calendar.isDate(topVisibleDate, inSameDayAs: defaultOpenDate)
}

func calendarShouldPreserveViewportOnResize(
    oldSize: CGSize,
    newSize: CGSize,
    didInitialLoad: Bool,
    pendingOpenRequest: CalendarOpenRequest?,
    pendingRevealRequest: CalendarRevealRequest?,
    pendingDefaultOpenDate: Date?,
    pendingPersistedViewportRestore: Bool,
    minimumSizeDelta: CGFloat = 0.5
) -> Bool {
    guard didInitialLoad,
          oldSize.width > 1,
          oldSize.height > 1,
          newSize.width > 1,
          newSize.height > 1,
          pendingOpenRequest == nil,
          pendingRevealRequest == nil,
          pendingDefaultOpenDate == nil,
          !pendingPersistedViewportRestore else {
        return false
    }

    return abs(oldSize.width - newSize.width) > minimumSizeDelta
        || abs(oldSize.height - newSize.height) > minimumSizeDelta
}

func calendarRevealTargetDate(
    request: CalendarRevealRequest,
    events: [CalendarWorkspaceEvent],
    calendar: Calendar = .current
) -> Date? {
    guard let requestedDate = DateParsers.isoDay.date(from: request.dayString) else { return nil }
    let normalizedRequestedDate = calendar.startOfDay(for: requestedDate)
    guard let eventSource = request.eventSource else {
        return normalizedRequestedDate
    }

    let matchingEvents = events.filter { $0.source == eventSource }
    guard !matchingEvents.isEmpty else {
        return normalizedRequestedDate
    }
    if let exactEvent = matchingEvents.first(where: {
        calendar.isDate($0.displayDate, inSameDayAs: normalizedRequestedDate)
    }) {
        return calendar.startOfDay(for: exactEvent.displayDate)
    }
    if let nextEvent = matchingEvents
        .filter({ calendar.startOfDay(for: $0.displayDate) >= normalizedRequestedDate })
        .min(by: { $0.displayDate < $1.displayDate }) {
        return calendar.startOfDay(for: nextEvent.displayDate)
    }
    return matchingEvents
        .max(by: { $0.displayDate < $1.displayDate })
        .map { calendar.startOfDay(for: $0.displayDate) }
        ?? normalizedRequestedDate
}

func calendarPreferredDateForFilterChange(
    topVisibleDate: Date,
    defaultOpenDate: Date,
    pendingDefaultOpenDate: Date?,
    isStabilizingDefaultOpen: Bool,
    calendar: Calendar = .current
) -> Date {
    if let pendingDefaultOpenDate {
        return calendar.startOfDay(for: pendingDefaultOpenDate)
    }
    if isStabilizingDefaultOpen {
        return calendar.startOfDay(for: defaultOpenDate)
    }
    return calendar.startOfDay(for: topVisibleDate)
}

func calendarShouldPreserveViewportAfterFilterChange(
    hasPendingTargetedScroll: Bool
) -> Bool {
    !hasPendingTargetedScroll
}

func calendarHasVisibleDate(
    _ targetDate: Date?,
    in availableDates: [Date],
    calendar: Calendar = .current
) -> Bool {
    guard let targetDate else { return false }
    return availableDates.contains { calendar.isDate($0, inSameDayAs: targetDate) }
}

private struct CalendarVerticalScrollOffsetBridge: NSViewRepresentable {
    @Binding var offsetY: CGFloat
    let restoreToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(offsetY: $offsetY)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        DispatchQueue.main.async {
            let didAttach = context.coordinator.attachIfNeeded(from: view)
            context.coordinator.updateRestoreToken(restoreToken)
            context.coordinator.restoreOffsetIfNeeded(didAttachNewScrollView: didAttach)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateRestoreToken(restoreToken)
        DispatchQueue.main.async {
            let didAttach = context.coordinator.attachIfNeeded(from: nsView)
            context.coordinator.restoreOffsetIfNeeded(didAttachNewScrollView: didAttach)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding private var offsetY: CGFloat
        weak var scrollView: NSScrollView?
        private var isUpdating = false
        private var restoreToken: Int = 0
        private var lastAppliedRestoreToken: Int?
        private var pendingObservedOffset: CGFloat?
        private var scheduledOffsetUpdate: DispatchWorkItem?
        private let minimumPublishedOffsetDelta: CGFloat = 24

        init(offsetY: Binding<CGFloat>) {
            self._offsetY = offsetY
        }

        func updateRestoreToken(_ token: Int) {
            restoreToken = token
        }

        func attachIfNeeded(from view: NSView) -> Bool {
            guard let enclosingScrollView = view.enclosingScrollView else { return false }
            if scrollView === enclosingScrollView {
                return false
            }

            detachObserver()
            scrollView = enclosingScrollView
            enclosingScrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBoundsChangeNotification(_:)),
                name: NSView.boundsDidChangeNotification,
                object: enclosingScrollView.contentView
            )
            return true
        }

        func restoreOffsetIfNeeded(didAttachNewScrollView: Bool) {
            guard let scrollView else { return }
            guard calendarShouldRestoreSavedScrollOffset(
                didAttachNewScrollView: didAttachNewScrollView,
                lastAppliedToken: lastAppliedRestoreToken,
                restoreToken: restoreToken
            ) else { return }

            let contentHeight = scrollView.documentView?.frame.height ?? 0
            let viewportHeight = scrollView.contentView.bounds.height
            let targetOffset = calendarClampedVerticalScrollOffset(
                offsetY,
                contentHeight: contentHeight,
                viewportHeight: viewportHeight
            )

            isUpdating = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetOffset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isUpdating = false

            if abs(offsetY - targetOffset) > 0.5 {
                offsetY = targetOffset
            }
            lastAppliedRestoreToken = restoreToken
        }

        @objc private func handleBoundsChangeNotification(_ notification: Notification) {
            updateObservedOffset()
        }

        private func updateObservedOffset() {
            guard let scrollView, !isUpdating else { return }
            let newOffset = scrollView.contentView.bounds.origin.y
            guard abs(offsetY - newOffset) > minimumPublishedOffsetDelta else { return }
            pendingObservedOffset = newOffset
            scheduleObservedOffsetPublish()
        }

        private func scheduleObservedOffsetPublish() {
            guard scheduledOffsetUpdate == nil else { return }
            let task = DispatchWorkItem { [weak self] in
                self?.publishPendingObservedOffset()
            }
            scheduledOffsetUpdate = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: task)
        }

        private func publishPendingObservedOffset() {
            scheduledOffsetUpdate = nil
            guard let newOffset = pendingObservedOffset else { return }
            pendingObservedOffset = nil
            guard abs(offsetY - newOffset) > 0.5 else { return }
            offsetY = newOffset
        }

        private func detachObserver() {
            scheduledOffsetUpdate?.cancel()
            scheduledOffsetUpdate = nil
            pendingObservedOffset = nil
            if let scrollView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView
                )
            }
            scrollView = nil
        }
    }
}

func calendarExclusiveCategorySelection(
    for kind: CalendarWorkspaceEventKind,
    meetingCategoryKeys: Set<String> = []
) -> (selectedKinds: Set<CalendarWorkspaceEventKind>, selectedMeetingCategoryKeys: Set<String>) {
    if kind == .meeting {
        return ([.meeting], meetingCategoryKeys)
    }
    return ([kind], [])
}

func calendarExclusiveMeetingCategorySelection(
    for key: String
) -> (selectedKinds: Set<CalendarWorkspaceEventKind>, selectedMeetingCategoryKeys: Set<String>) {
    ([.meeting], [key])
}

@MainActor
private func calendarGrantSelectionOptions(
    store: GrantDataStore,
    language: AppLanguage
) -> [CalendarGrantSelectionOption] {
    store.applicationsForRead
        .map { application in
            CalendarGrantSelectionOption(
                id: application.id,
                label: calendarGrantSelectionLabel(
                    application: application,
                    store: store,
                    language: language
                )
            )
        }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
}

@MainActor
private func calendarGrantSelectionLabel(
    application: GrantApplication,
    store: GrantDataStore,
    language: AppLanguage
) -> String {
    let funder = store.organizationLabel(for: application, language: language).trimmedOrNil
    let grant = store.localizedGrantName(for: application, language: language).trimmedOrNil
    let linkedProject = application.projectID
        .flatMap { id in store.projectsForRead.first(where: { $0.id == id })?.displayName(for: language) }
    let project = linkedProject?.trimmedOrNil
        ?? application.projectType?.trimmedOrNil
    let caseNumber = application.appliedCaseNumber?.trimmedOrNil

    let base = [funder, grant, project]
        .compactMap { $0 }
        .joined(separator: ", ")

    if let caseNumber {
        return base.isEmpty ? "(\(caseNumber))" : "\(base) (\(caseNumber))"
    }
    return base
}

private func resolvedCalendarGrantID(
    for label: String,
    in options: [CalendarGrantSelectionOption]
) -> String? {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return options.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame })?.id
}

private func resolvedCalendarGrantLabel(
    for id: String?,
    in options: [CalendarGrantSelectionOption]
) -> String {
    guard let id, let match = options.first(where: { $0.id == id }) else { return "" }
    return match.label
}

@MainActor
private func calendarTeachingAssignmentLabel(
    _ assignment: TeachingAssignment,
    store: GrantDataStore,
    language: AppLanguage
) -> String {
    let component = assignment.activityID.flatMap { id in
        store.teachingComponents.first(where: { $0.id == id })
    }
    let activity = component?.localizedName(language: language).nonEmpty
        ?? assignment.activityName.nonEmpty
        ?? assignment.comment.nonEmpty
        ?? language.text("Untitled teaching assignment", "Namnlöst undervisningsuppdrag")
    let context = assignment.contextID.flatMap { id in
        store.teachingCourses.first(where: { $0.id == id })
    }
    var details = [
        context?.localizedName(language: language).nonEmpty,
        assignment.studentName.nonEmpty,
        assignment.programName.nonEmpty,
        store.organizationLabel(forCourse: context, language: language).nonEmpty
    ]
    .compactMap { $0 }
    var seen = Set<String>()
    details = details.filter { seen.insert($0).inserted }
    guard !details.isEmpty else { return activity }
    return "\(activity) (\(details.joined(separator: " · ")))"
}

private func calendarCongressDateRangeSuffix(
    congress: OrganizationCongress,
    language: AppLanguage,
    calendar: Calendar
) -> String? {
    let text = publicationAuthorLinkedDateRangeText(
        from: congress.from,
        to: congress.to,
        language: language,
        emptyText: ""
    )
    return text.nonEmpty
}

private func calendarCongressDeadlineTitle(
    congress: OrganizationCongress,
    organization: OrganizationRecord,
    language: AppLanguage,
    calendar: Calendar
) -> String {
    let title = congress.title.nonEmpty ?? organization.displayName(for: language)
    guard let dateRange = calendarCongressDateRangeSuffix(
        congress: congress,
        language: language,
        calendar: calendar
    ) else {
        return title
    }
    return "\(title) (\(dateRange))"
}

private func resolvedCalendarGrantLabel(
    for label: String,
    in options: [CalendarGrantSelectionOption]
) -> String {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    return options.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame })?.label ?? trimmed
}

private struct CalendarGrantSelectionField: View {
    let language: AppLanguage
    @Binding var text: String
    let options: [CalendarGrantSelectionOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.text("Grant", "Anslag"))
                .calendarTypography(.fieldLabel)
            AutocompleteSelectionField(
                text: $text,
                options: options.map(\.label),
                placeholder: language.text("Grant", "Anslag"),
                onCommit: {
                    text = resolvedCalendarGrantLabel(for: text, in: options)
                },
                onSelect: { selected in
                    text = selected
                },
                showsSuggestionsWithoutQuery: true
            )
        }
    }
}

private struct CalendarTaskCompletionDateField: View {
    let language: AppLanguage
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.text("Completion date", "Genomförandedatum"))
                .calendarTypography(.fieldLabel)
            CalendarDateInputField(placeholder: language.datePlaceholder, text: $text)
        }
    }
}

private struct CalendarRichTextNoteField: View {
    let language: AppLanguage
    let title: String
    var minHeight: CGFloat = 110
    @Binding var text: String

    @StateObject private var editorController = CVRichTextEditorController()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .calendarTypography(.fieldLabel)

                Spacer(minLength: 8)

                CVRichTextFormatButton(title: "B") { editorController.toggleBold() }
                    .help(language.text("Bold", "Fetstil"))
                CVRichTextFormatButton(title: "I") { editorController.toggleItalic() }
                    .help(language.text("Italic", "Kursiv"))
                CVRichTextFormatButton(title: "U") { editorController.toggleUnderline() }
                    .help(language.text("Underline", "Understruken"))
                CVRichTextFormatButton(title: "•") { editorController.toggleBulletList() }
                    .help(language.text("Bullet list", "Punktlista"))
                CVRichTextFormatButton(title: "⇤") { editorController.changeBulletLevel(by: -1) }
                    .help(language.text("Decrease list level", "Minska listnivå"))
                CVRichTextFormatButton(title: "⇥") { editorController.changeBulletLevel(by: 1) }
                    .help(language.text("Increase list level", "Öka listnivå"))
            }

            CVRichTextEditorRepresentable(
                document: documentBinding,
                controller: editorController
            )
            .frame(minHeight: minHeight, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                    .fill(AppPalette.fieldSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                    .stroke(AppPalette.subtleBorder, lineWidth: 1)
            )
        }
    }

    private var documentBinding: Binding<CVRichTextDocument> {
        Binding(
            get: { ProtocolMarkup.document(from: text) },
            set: { text = ProtocolMarkup.markup(from: $0) }
        )
    }
}

/// The activity/task editors split 100:80 — the base fields keep 100 parts
/// of the width and the Dagordning/Protokoll column gets 80, regardless of
/// how the responsive dialog frame clamps the total.
private func calendarEditorSideColumnWidth(for dialogWidth: CGFloat) -> CGFloat {
    // 22 pt padding on each side plus the 20 pt column spacing.
    let contentWidth = max(0, dialogWidth - 64)
    return max(320, contentWidth * (80.0 / 180.0))
}

/// Shared dialog chrome for the calendar activity/task editors: the width is
/// fixed (and identical for all of them) while the height hugs the measured
/// content, so the sheet is never taller than its fields require. Content
/// taller than the ceiling (or the window) scrolls.
private struct CalendarEditorDialogSurface<Content: View>: View {
    @ViewBuilder let content: (_ dialogWidth: CGFloat) -> Content

    @State private var dialogWidth: CGFloat = Self.idealWidth
    @State private var contentHeight: CGFloat = 0

    static var idealWidth: CGFloat { 1656 }
    static var minimumWidth: CGFloat { 980 }
    static var maximumHeight: CGFloat { 1040 }
    static var minimumHeight: CGFloat { 320 }

    private var boundedHeight: CGFloat {
        guard contentHeight > 0 else { return Self.maximumHeight }
        return min(Self.maximumHeight, max(Self.minimumHeight, contentHeight))
    }

    var body: some View {
        ScrollView {
            content(dialogWidth)
                .padding(22)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { contentHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, newHeight in
                                contentHeight = newHeight
                            }
                    }
                )
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { dialogWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        dialogWidth = newWidth
                    }
            }
        )
        .frame(
            minWidth: Self.minimumWidth,
            idealWidth: Self.idealWidth,
            maxWidth: Self.idealWidth,
            idealHeight: boundedHeight,
            maxHeight: boundedHeight
        )
    }
}

/// The Dagordning + Protokoll pair that fills the right-hand column of the
/// calendar activity/task editors, each taking half the available height.
private struct CalendarAgendaProtocolColumn: View {
    let language: AppLanguage
    var fieldMinHeight: CGFloat = 220
    @Binding var agendaText: String
    @Binding var protocolText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CalendarRichTextNoteField(
                language: language,
                title: language.text("Agenda", "Dagordning"),
                minHeight: fieldMinHeight,
                text: $agendaText
            )
            CalendarRichTextNoteField(
                language: language,
                title: language.text("Minutes", "Protokoll"),
                minHeight: fieldMinHeight,
                text: $protocolText
            )
        }
    }
}

private let somalilandFlagToken = "[[SOMALILAND_FLAG]]"
private let somalilandFlagImage: NSImage? = {
    guard let url = try? GrantDataStore.bundledResourceURL(named: "SomalilandFlag.png") else {
        return nil
    }
    return NSImage(contentsOf: url)
}()
private let somalilandFlagDisplayWidth: CGFloat = 14
private let somalilandFlagDisplayHeight: CGFloat = 10
private let somalilandMenuFlagImage: NSImage? = {
    guard let source = somalilandFlagImage else { return nil }
    let size = NSSize(width: somalilandFlagDisplayWidth, height: somalilandFlagDisplayHeight)
    let image = NSImage(size: size)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(
        in: NSRect(origin: .zero, size: size),
        from: NSRect(origin: .zero, size: source.size),
        operation: .sourceOver,
        fraction: 1
    )
    image.unlockFocus()
    return image
}()

func footprintCalendar(for language: AppLanguage, weekStart: CalendarWeekdayChoice? = nil) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = language == .swedish ? Locale(identifier: "sv_SE") : Locale(identifier: "en_US")
    calendar.firstWeekday = weekStart?.calendarWeekday ?? (language == .swedish ? 2 : 1)
    return calendar
}

func footprintMonthStart(for date: Date, calendar: Calendar) -> Date {
    calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
}

struct CalendarWorkspaceOrganizationTaskSource {
    let organization: OrganizationRecord
    let task: ProjectTaskItem
    let deadline: Date
    let displayDate: Date
}

struct CalendarWorkspaceProjectTaskSource {
    let project: ProjectRecord
    let task: ProjectTaskItem
    let deadline: Date
    let displayDate: Date
}

struct CalendarWorkspacePublicationTaskSource {
    let publication: PublicationRecord
    let task: PublicationTaskItem
    let deadline: Date
    let displayDate: Date
}

struct CalendarWorkspaceTeachingTaskSource {
    let task: PublicationTaskItem
    let deadline: Date
    let displayDate: Date
}

struct CalendarWorkspaceCongressSource {
    let organization: OrganizationRecord
    let congress: OrganizationCongress
}

struct CalendarWorkspaceIndexedEventSources {
    let applications: [GrantApplication]
    let reviewEntries: [CVReviewEntry]
    let organizationTasks: [CalendarWorkspaceOrganizationTaskSource]
    let projectTasks: [CalendarWorkspaceProjectTaskSource]
    let publicationTasks: [CalendarWorkspacePublicationTaskSource]
    let teachingTasks: [CalendarWorkspaceTeachingTaskSource]
    let congresses: [CalendarWorkspaceCongressSource]
    let travelRecords: [CalendarTravelRecord]
    let accommodationRecords: [CalendarAccommodationRecord]
    let meetingRecords: [CalendarMeetingRecord]

    var diagnosticSummary: String {
        "applications=\(applications.count) reviews=\(reviewEntries.count) organization_tasks=\(organizationTasks.count) project_tasks=\(projectTasks.count) publication_tasks=\(publicationTasks.count) teaching_tasks=\(teachingTasks.count) congresses=\(congresses.count) travel=\(travelRecords.count) accommodation=\(accommodationRecords.count) meetings=\(meetingRecords.count)"
    }
}

struct CalendarDatedValue<Value> {
    let day: Date
    let value: Value
}

struct CalendarRangedValue<Value> {
    let start: Date
    let end: Date
    let value: Value
}

struct CalendarWorkspaceEventSourceIndex {
    var visibleRange: ClosedRange<Date>
    var applications: [CalendarDatedValue<GrantApplication>] = []
    var reviewEntries: [CalendarDatedValue<CVReviewEntry>] = []
    var organizationTasks: [CalendarDatedValue<CalendarWorkspaceOrganizationTaskSource>] = []
    var projectTasks: [CalendarDatedValue<CalendarWorkspaceProjectTaskSource>] = []
    var publicationTasks: [CalendarDatedValue<CalendarWorkspacePublicationTaskSource>] = []
    var teachingTasks: [CalendarDatedValue<CalendarWorkspaceTeachingTaskSource>] = []
    var congresses: [CalendarRangedValue<CalendarWorkspaceCongressSource>] = []
    var travelRecords: [CalendarDatedValue<CalendarTravelRecord>] = []
    var accommodationRecords: [CalendarRangedValue<CalendarAccommodationRecord>] = []
    var meetingRecords: [CalendarDatedValue<CalendarMeetingRecord>] = []

    static func empty(today: Date) -> CalendarWorkspaceEventSourceIndex {
        CalendarWorkspaceEventSourceIndex(visibleRange: today...today)
    }

    var diagnosticSummary: String {
        "applications=\(applications.count) reviews=\(reviewEntries.count) organization_tasks=\(organizationTasks.count) project_tasks=\(projectTasks.count) publication_tasks=\(publicationTasks.count) teaching_tasks=\(teachingTasks.count) congresses=\(congresses.count) travel=\(travelRecords.count) accommodation=\(accommodationRecords.count) meetings=\(meetingRecords.count)"
    }

    func slice(from start: Date, to end: Date) -> CalendarWorkspaceIndexedEventSources {
        CalendarWorkspaceIndexedEventSources(
            applications: calendarIndexedValues(applications, from: start, to: end),
            reviewEntries: calendarIndexedValues(reviewEntries, from: start, to: end),
            organizationTasks: calendarIndexedValues(organizationTasks, from: start, to: end),
            projectTasks: calendarIndexedValues(projectTasks, from: start, to: end),
            publicationTasks: calendarIndexedValues(publicationTasks, from: start, to: end),
            teachingTasks: calendarIndexedValues(teachingTasks, from: start, to: end),
            congresses: calendarRangedValues(congresses, from: start, to: end),
            travelRecords: calendarUniqueIdentifiedValues(calendarIndexedValues(travelRecords, from: start, to: end)),
            accommodationRecords: calendarRangedValues(accommodationRecords, from: start, to: end),
            meetingRecords: calendarIndexedValues(meetingRecords, from: start, to: end)
        )
    }

    /// Replaces one dated collection's entries with a delta computed against
    /// the new records instead of rebuilding every source: entries for
    /// unchanged records are kept as-is, changed/added records re-derive
    /// their entries, removed records drop theirs. Returns false when the
    /// update cannot be expressed incrementally (a new entry falls outside
    /// the current visible range, which would require re-deriving the range
    /// from every source) — the caller falls back to a full rebuild.
    mutating func applyDatedDelta<Value: Identifiable & Equatable>(
        to keyPath: WritableKeyPath<Self, [CalendarDatedValue<Value>]>,
        records: [Value],
        entriesFor: (Value) -> [CalendarDatedValue<Value>]
    ) -> Bool where Value.ID == String {
        let old = self[keyPath: keyPath]
        var oldByID: [String: Value] = [:]
        oldByID.reserveCapacity(old.count)
        for entry in old {
            oldByID[entry.value.id] = entry.value
        }
        let newIDs = Set(records.map(\.id))
        let changed = records.filter { oldByID[$0.id] != $0 }
        let removedIDs = oldByID.keys.filter { !newIDs.contains($0) }
        if changed.isEmpty, removedIDs.isEmpty { return true }

        var staleIDs = Set(changed.map(\.id))
        staleIDs.formUnion(removedIDs)
        var updated = old.filter { !staleIDs.contains($0.value.id) }
        for record in changed {
            for entry in entriesFor(record) {
                guard visibleRange.contains(entry.day) else { return false }
                updated.append(entry)
            }
        }
        updated.sort { $0.day < $1.day }
        self[keyPath: keyPath] = updated
        return true
    }

    /// Ranged-collection counterpart of applyDatedDelta.
    mutating func applyRangedDelta<Value: Identifiable & Equatable>(
        to keyPath: WritableKeyPath<Self, [CalendarRangedValue<Value>]>,
        records: [Value],
        entriesFor: (Value) -> [CalendarRangedValue<Value>]
    ) -> Bool where Value.ID == String {
        let old = self[keyPath: keyPath]
        var oldByID: [String: Value] = [:]
        oldByID.reserveCapacity(old.count)
        for entry in old {
            oldByID[entry.value.id] = entry.value
        }
        let newIDs = Set(records.map(\.id))
        let changed = records.filter { oldByID[$0.id] != $0 }
        let removedIDs = oldByID.keys.filter { !newIDs.contains($0) }
        if changed.isEmpty, removedIDs.isEmpty { return true }

        var staleIDs = Set(changed.map(\.id))
        staleIDs.formUnion(removedIDs)
        var updated = old.filter { !staleIDs.contains($0.value.id) }
        for record in changed {
            for entry in entriesFor(record) {
                guard visibleRange.contains(entry.start), visibleRange.contains(entry.end) else { return false }
                updated.append(entry)
            }
        }
        updated.sort { $0.start < $1.start }
        self[keyPath: keyPath] = updated
        return true
    }
}

private func calendarIndexedValues<Value>(
    _ values: [CalendarDatedValue<Value>],
    from start: Date,
    to end: Date
) -> [Value] {
    guard !values.isEmpty else { return [] }
    var lower = 0
    var upper = values.count
    while lower < upper {
        let middle = (lower + upper) / 2
        if values[middle].day < start {
            lower = middle + 1
        } else {
            upper = middle
        }
    }

    var result: [Value] = []
    var index = lower
    while index < values.count, values[index].day <= end {
        result.append(values[index].value)
        index += 1
    }
    return result
}

private func calendarRangedValues<Value>(
    _ values: [CalendarRangedValue<Value>],
    from start: Date,
    to end: Date
) -> [Value] {
    values.compactMap { entry in
        entry.end >= start && entry.start <= end ? entry.value : nil
    }
}

private func calendarUniqueIdentifiedValues<Value: Identifiable>(
    _ values: [Value]
) -> [Value] where Value.ID: Hashable {
    var seen = Set<Value.ID>()
    return values.filter { seen.insert($0.id).inserted }
}

@MainActor
private func buildCalendarWorkspaceEventSourceIndex(
    store: GrantDataStore,
    calendar: Calendar,
    today: Date,
    travelRecords: [CalendarTravelRecord],
    accommodationRecords: [CalendarAccommodationRecord],
    meetingRecords: [CalendarMeetingRecord],
    additionalDates: [Date] = []
) -> CalendarWorkspaceEventSourceIndex {
    let fallbackStart = calendar.date(byAdding: .year, value: -1, to: today) ?? today
    let fallbackEnd = calendar.date(byAdding: .year, value: 1, to: today) ?? today
    var candidateDates: [Date] = [fallbackStart, fallbackEnd]
    candidateDates.append(contentsOf: additionalDates.map { calendar.startOfDay(for: $0) })

    var index = CalendarWorkspaceEventSourceIndex(visibleRange: fallbackStart...fallbackEnd)

    // Include central task dates in the calendar range even when a task has no
    // legacy host-owned counterpart.
    for task in store.taskItems where !task.isEmpty {
        if let day = DateParsers.isoDay.date(from: task.deadline).map({ calendar.startOfDay(for: $0) }) {
            candidateDates.append(day)
        }
    }

    for application in store.applicationsForRead where calendarShowsApplicationDeadline(application) {
        guard let day = application.closeDate.map({ calendar.startOfDay(for: $0) }) else { continue }
        candidateDates.append(day)
        index.applications.append(CalendarDatedValue(day: day, value: application))
    }

    for review in store.cvReviewEntries where !review.isCompleted {
        guard let day = review.deadlineDay(calendar: calendar) else { continue }
        candidateDates.append(day)
        index.reviewEntries.append(CalendarDatedValue(day: calendar.startOfDay(for: day), value: review))
    }

    for organization in store.organizationsForCongressRead {
        for task in organization.projectTasks {
            guard let source = calendarOrganizationTaskSource(
                organization: organization,
                task: task,
                today: today,
                calendar: calendar
            ) else { continue }
            candidateDates.append(source.displayDate)
            index.organizationTasks.append(CalendarDatedValue(day: source.displayDate, value: source))
        }

        for congress in organization.congresses {
            guard let range = calendarCongressIndexedRange(
                congress: congress,
                calendar: calendar
            ) else { continue }
            candidateDates.append(range.start)
            candidateDates.append(range.end)
            index.congresses.append(
                CalendarRangedValue(
                    start: range.start,
                    end: range.end,
                    value: CalendarWorkspaceCongressSource(organization: organization, congress: congress)
                )
            )
        }
    }

    for project in store.projectsForRead {
        for task in project.projectTasks {
            guard let source = calendarProjectTaskSource(
                project: project,
                task: task,
                today: today,
                calendar: calendar
            ) else { continue }
            candidateDates.append(source.displayDate)
            index.projectTasks.append(CalendarDatedValue(day: source.displayDate, value: source))
        }
    }

    for publication in store.publicationRecordsForRead {
        for task in publication.publicationTasks {
            guard let source = calendarPublicationTaskSource(
                publication: publication,
                task: task,
                today: today,
                calendar: calendar
            ) else { continue }
            candidateDates.append(source.displayDate)
            index.publicationTasks.append(CalendarDatedValue(day: source.displayDate, value: source))
        }
    }

    for task in store.teachingWorkspaceTasks {
        guard let source = calendarTeachingTaskSource(
            task: task,
            today: today,
            calendar: calendar
        ) else { continue }
        candidateDates.append(source.displayDate)
        index.teachingTasks.append(CalendarDatedValue(day: source.displayDate, value: source))
    }

    for travel in travelRecords {
        let days = [
            DateParsers.isoDay.date(from: travel.date),
            DateParsers.isoDay.date(from: travel.resolvedArrivalDateString())
        ]
        .compactMap { $0.map { calendar.startOfDay(for: $0) } }
        guard !days.isEmpty else { continue }
        candidateDates.append(contentsOf: days)
        for day in Set(days) {
            index.travelRecords.append(CalendarDatedValue(day: day, value: travel))
        }
    }

    for accommodation in accommodationRecords {
        let days = [
            accommodation.checkInDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
            accommodation.checkOutDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
        ]
        .compactMap { $0.map { calendar.startOfDay(for: $0) } }
        guard let start = days.min(), let end = days.max() else { continue }
        candidateDates.append(start)
        candidateDates.append(end)
        index.accommodationRecords.append(CalendarRangedValue(start: start, end: end, value: accommodation))
    }

    for meeting in meetingRecords {
        guard let day = DateParsers.isoDay.date(from: meeting.date).map({ calendar.startOfDay(for: $0) }) else {
            continue
        }
        candidateDates.append(day)
        index.meetingRecords.append(CalendarDatedValue(day: day, value: meeting))
    }

    for appearance in store.cvMediaAppearances {
        guard let day = DateParsers.isoDay.date(from: appearance.date).map({ calendar.startOfDay(for: $0) }) else {
            continue
        }
        candidateDates.append(day)
    }

    index.applications.sort { $0.day < $1.day }
    index.reviewEntries.sort { $0.day < $1.day }
    index.organizationTasks.sort { $0.day < $1.day }
    index.projectTasks.sort { $0.day < $1.day }
    index.publicationTasks.sort { $0.day < $1.day }
    index.teachingTasks.sort { $0.day < $1.day }
    index.congresses.sort { $0.start < $1.start }
    index.travelRecords.sort { $0.day < $1.day }
    index.accommodationRecords.sort { $0.start < $1.start }
    index.meetingRecords.sort { $0.day < $1.day }

    let earliestDate = candidateDates.min() ?? fallbackStart
    let latestDate = candidateDates.max() ?? fallbackEnd
    let startOfEarliestYear =
        calendar.date(from: calendar.dateComponents([.year], from: earliestDate))
        ?? earliestDate
    let startOfLatestYear =
        calendar.date(from: calendar.dateComponents([.year], from: latestDate))
        ?? latestDate
    let endOfLatestYear =
        calendar.date(byAdding: DateComponents(year: 1, day: -1), to: startOfLatestYear)
        ?? latestDate

    index.visibleRange = startOfEarliestYear...endOfLatestYear
    return index
}

private func calendarOrganizationTaskSource(
    organization: OrganizationRecord,
    task: ProjectTaskItem,
    today: Date,
    calendar: Calendar
) -> CalendarWorkspaceOrganizationTaskSource? {
    guard !task.isEmpty,
          task.comment.nonEmpty != nil,
          let deadline = DateParsers.isoDay.date(from: task.deadline) else {
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
    return CalendarWorkspaceOrganizationTaskSource(
        organization: organization,
        task: task,
        deadline: deadline,
        displayDate: displayDate
    )
}

private func calendarProjectTaskSource(
    project: ProjectRecord,
    task: ProjectTaskItem,
    today: Date,
    calendar: Calendar
) -> CalendarWorkspaceProjectTaskSource? {
    guard !task.isEmpty,
          task.comment.nonEmpty != nil,
          let deadline = DateParsers.isoDay.date(from: task.deadline) else {
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
    return CalendarWorkspaceProjectTaskSource(
        project: project,
        task: task,
        deadline: deadline,
        displayDate: displayDate
    )
}

private func calendarPublicationTaskSource(
    publication: PublicationRecord,
    task: PublicationTaskItem,
    today: Date,
    calendar: Calendar
) -> CalendarWorkspacePublicationTaskSource? {
    guard !task.isEmpty,
          task.comment.nonEmpty != nil,
          let deadline = DateParsers.isoDay.date(from: task.deadline) else {
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
    return CalendarWorkspacePublicationTaskSource(
        publication: publication,
        task: task,
        deadline: deadline,
        displayDate: displayDate
    )
}

private func calendarTeachingTaskSource(
    task: PublicationTaskItem,
    today: Date,
    calendar: Calendar
) -> CalendarWorkspaceTeachingTaskSource? {
    guard !task.isEmpty,
          task.comment.nonEmpty != nil,
          let deadline = DateParsers.isoDay.date(from: task.deadline) else {
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
    return CalendarWorkspaceTeachingTaskSource(
        task: task,
        deadline: deadline,
        displayDate: displayDate
    )
}

func calendarCentralTaskTargetIDs(
    _ task: TaskItem,
    kind: TaskLinkKind
) -> [String] {
    let targetIDs = task.links
        .filter { $0.kind == kind }
        .compactMap { $0.targetID.trimmedOrNil }
    return Array(NSOrderedSet(array: targetIDs)) as? [String] ?? targetIDs
}

func calendarCentralTaskProjectIDs(
    _ task: TaskItem,
    applicationsByID: [String: GrantApplication],
    publicationsByID: [String: PublicationRecord]
) -> [String] {
    var projectIDs = calendarCentralTaskTargetIDs(task, kind: .project)

    for link in task.links {
        guard let targetID = link.targetID.trimmedOrNil else { continue }
        switch link.kind {
        case .application:
            if let projectID = applicationsByID[targetID]?.projectID?.trimmedOrNil {
                projectIDs.append(projectID)
            }
        case .publication:
            if let projectID = publicationsByID[targetID]?.projectID?.trimmedOrNil {
                projectIDs.append(projectID)
            }
        default:
            continue
        }
    }

    return Array(NSOrderedSet(array: projectIDs)) as? [String] ?? projectIDs
}

func calendarCentralTaskResearcherNames(
    _ task: TaskItem,
    projectsByID: [String: ProjectRecord],
    applicationsByID: [String: GrantApplication],
    publicationsByID: [String: PublicationRecord]
) -> [String] {
    var names = task.participantNames.compactMap(\.trimmedOrNil)
    for projectID in calendarCentralTaskTargetIDs(task, kind: .project) {
        names.append(contentsOf: projectsByID[projectID]?.collaboratorNames ?? [])
    }
    for applicationID in calendarCentralTaskTargetIDs(task, kind: .application) {
        names.append(contentsOf: applicationsByID[applicationID]?.coApplicants ?? [])
    }
    for publicationID in calendarCentralTaskTargetIDs(task, kind: .publication) {
        names.append(contentsOf: publicationsByID[publicationID]?.authorNames ?? [])
    }
    let normalized = names.compactMap(\.trimmedOrNil)
    return Array(NSOrderedSet(array: normalized)) as? [String] ?? normalized
}

/// F13d: the researcher links that go with `calendarCentralTaskResearcherNames`.
func calendarCentralTaskResearcherIDs(
    _ task: TaskItem,
    projectsByID: [String: ProjectRecord],
    applicationsByID: [String: GrantApplication],
    publicationsByID: [String: PublicationRecord]
) -> [String] {
    var ids = task.participantAuthorIDs
    for projectID in calendarCentralTaskTargetIDs(task, kind: .project) {
        ids.append(contentsOf: projectsByID[projectID]?.collaboratorAuthorIDs ?? [])
    }
    for applicationID in calendarCentralTaskTargetIDs(task, kind: .application) {
        ids.append(contentsOf: applicationsByID[applicationID]?.coApplicantAuthorIDs ?? [])
    }
    for publicationID in calendarCentralTaskTargetIDs(task, kind: .publication) {
        ids.append(contentsOf: publicationsByID[publicationID]?.authorIDs ?? [])
    }
    return ids.compactMap(\.trimmedOrNil)
}

/// F44: the calendar content signals that arrive in one main-thread turn
/// (a generation bump from the metadata change and the update that names the
/// edited record), handled with a single rebuild.
struct CalendarPendingContentRefresh: Equatable {
    var generationBumps = 0
    var updates: [CalendarContentUpdate] = []

    /// The one record to update on its own. Only when the turn carried a
    /// single update that names its record, and at most the one generation
    /// bump that update's own metadata change caused; anything else (several
    /// changes, or a change from elsewhere) rebuilds every source as before.
    var incrementalSource: CalendarWorkspaceEventSource? {
        guard updates.count == 1, generationBumps <= 1 else { return nil }
        return updates[0].source
    }

    /// The record that gets the short highlight: the last edited one that
    /// still exists.
    var pulseSource: CalendarWorkspaceEventSource? {
        updates.last(where: { $0.pulses && $0.source != nil })?.source
    }
}

func duplicatedCalendarCentralTask(
    _ original: TaskItem,
    id: String = UUID().uuidString,
    deadline: String,
    todayString: String
) -> TaskItem {
    var copy = original
    copy.id = id
    copy.createdOn = todayString
    copy.updatedOn = todayString
    copy.deadline = deadline
    copy.completedOn = nil
    copy.normalize()
    return copy
}

private func calendarCongressIndexedRange(
    congress: OrganizationCongress,
    calendar: Calendar
) -> (start: Date, end: Date)? {
    let dates = [
        congress.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
        congress.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
        congress.abstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
        congress.lateAbstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
    ]
    .compactMap { $0.map { calendar.startOfDay(for: $0) } }
    guard let start = dates.min(), let end = dates.max() else { return nil }
    return (start, end)
}

@MainActor
func buildFootprintCalendarEvents(
    store: GrantDataStore,
    language: AppLanguage,
    displayedMonthStart: Date,
    displayedMonthEnd: Date,
    calendar: Calendar,
    travelRecords: [CalendarTravelRecord]? = nil,
    accommodationRecords: [CalendarAccommodationRecord]? = nil,
    meetingRecords: [CalendarMeetingRecord]? = nil,
    taskDisplayPolicy: CalendarTaskDisplayPolicy = .scheduled,
    indexedSources: CalendarWorkspaceIndexedEventSources? = nil
) -> [CalendarWorkspaceEvent] {
    let today = calendar.startOfDay(for: Date())
    var events: [CalendarWorkspaceEvent] = []
    let resolvedApplications = indexedSources?.applications ?? store.applicationsForRead
    let resolvedProjects = store.projectsForRead
    let resolvedPublications = store.publicationRecordsForRead
    let resolvedReviewEntries = indexedSources?.reviewEntries ?? store.cvReviewEntries
    let resolvedOrganizations = store.organizationsForCongressRead
    let resolvedTravelRecords = travelRecords ?? store.calendarTravelRecordsForRead
    let resolvedAccommodationRecords = accommodationRecords ?? store.calendarAccommodationRecordsForRead
    let resolvedMeetingRecords = meetingRecords ?? store.calendarMeetingRecords
    let applicationsByID = calendarLookupByID(store.applicationsForRead)
    let organizationsByID = calendarLookupByID(resolvedOrganizations)
    let publicationsByID = calendarLookupByID(store.publicationRecordsForRead)
    let teachingAssignmentsByID = calendarLookupByID(store.teachingAssignments)
    let centralTaskIDs = Set(store.taskItems.map(\.id))

    let holidayEvents = holidaysInCalendarRange(
        from: displayedMonthStart,
        to: displayedMonthEnd,
        countries: store.holidayCountries,
        calendar: calendar
    )
    .map { holiday in
        CalendarWorkspaceEvent(
            id: "holiday:\(holiday.id)",
            source: .holiday(holiday.id),
            displayDate: calendar.startOfDay(for: holiday.date),
            title: holiday.localizedTitle(language: language),
            subtitle: "",
            detail: "",
            place: "",
            timeText: "",
            kind: .holiday,
            completedOn: nil,
            action: nil,
            toggleCompletion: nil
        )
    }

    let applicationEvents = resolvedApplications
        .filter(calendarShowsApplicationDeadline)
        .compactMap { application -> CalendarWorkspaceEvent? in
            guard let deadline = application.closeDate else {
                return nil
            }
            let displayDate = calendar.startOfDay(for: deadline)
            guard displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd else {
                return nil
            }

            let grantTitle = store.localizedGrantName(for: application, language: language).nonEmpty
                ?? store.organizationLabel(for: application, language: language)
            let organization = store.organizationLabel(for: application, language: language)
            let hideKey = CalendarAutomaticEventHideKey.applicationDeadline(applicationID: application.id)

            return CalendarWorkspaceEvent(
                id: "application:\(application.id)",
                source: .application(application.id),
                automaticHideKey: hideKey,
                isHiddenFromCalendar: store.isAutomaticCalendarEventHidden(hideKey),
                displayDate: displayDate,
                isDateUncertain: application.closesOnUncertain,
                title: grantTitle,
                subtitle: organization,
                detail: organization,
                place: "",
                timeText: "",
                kind: .applicationDeadline,
                // The list shows the funder after the title, not underneath.
                organizationName: organization,
                detailParts: [],
                completedOn: nil,
                action: { store.openRoute(for: application) },
                toggleCompletion: nil
            )
        }

    // A call whose closing date has passed while it is still "Att söka"
    // is asked about on today's date every day until "Sökt" or "Ej sökt"
    // is answered. It cannot be hidden. Clicking it asks the question.
    let appliedQuestionEvents: [CalendarWorkspaceEvent] = (today >= displayedMonthStart && today <= displayedMonthEnd)
        ? store.applicationsAwaitingAppliedAnswer().map { application in
            let grantTitle = store.localizedGrantName(for: application, language: language).nonEmpty
                ?? store.organizationLabel(for: application, language: language)
            let organization = store.organizationLabel(for: application, language: language)
            let closing = application.closesOn?.trimmedOrNil ?? ""
            return CalendarWorkspaceEvent(
                id: "application-applied-question:\(application.id)",
                source: .application(application.id),
                displayDate: today,
                isRolledOverPastDue: true,
                title: language.text("Did you apply? ", "Sökt eller inte sökt? ") + grantTitle,
                subtitle: organization,
                detail: language.text("Closed \(closing)", "Stängde \(closing)"),
                place: "",
                timeText: "",
                kind: .applicationDeadline,
                completedOn: nil,
                action: { store.askAppliedQuestion(applicationID: application.id) },
                toggleCompletion: nil
            )
        }
        : []

    let reviewDeadlineEvents = resolvedReviewEntries.compactMap { review -> CalendarWorkspaceEvent? in
        guard !review.isCompleted,
              let deadline = review.deadlineDay(calendar: calendar) else {
            return nil
        }
        guard deadline >= displayedMonthStart, deadline <= displayedMonthEnd else {
            return nil
        }

        let title = review.listTitle.nonEmpty ?? review.displayTitle
        let acceptedText = review.acceptedDate.trimmedOrNil
            .map { "\(language.text("Accepted", "Accepterat")): \($0)" }
        let deadlineText = review.deadlineDate.trimmedOrNil
            .map { "\(language.text("Deadline", "Tidsfrist")): \($0)" }

        return CalendarWorkspaceEvent(
            id: "review-deadline:\(review.id)",
            source: .reviewDeadline(review.id),
            displayDate: deadline,
            title: title,
            subtitle: review.category.localizedTitle(language),
            detail: [acceptedText, deadlineText].compactMap { $0 }.joined(separator: " · "),
            place: "",
            timeText: "",
            kind: .applicationDeadline,
            completedOn: nil,
            action: { store.openRoute(for: review) },
            toggleCompletion: nil
        )
    }

    let organizationTaskSources = indexedSources?.organizationTasks
        ?? resolvedOrganizations.flatMap { organization in
            organization.projectTasks.compactMap { task in
                calendarOrganizationTaskSource(organization: organization, task: task, today: today, calendar: calendar)
            }
        }
    let organizationTaskEvents = organizationTaskSources.filter { !centralTaskIDs.contains($0.task.id) }.compactMap { source -> CalendarWorkspaceEvent? in
        let organization = source.organization
        let task = source.task
        guard let comment = task.comment.nonEmpty else { return nil }
        let displayDate = taskDisplayPolicy == .rollOverPastDue
            ? source.displayDate
            : effectiveCalendarTaskDate(
                deadline: source.deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: taskDisplayPolicy
            )
        let isRolledOverPastDue = calendarTaskIsRolledOverPastDue(
            deadline: source.deadline,
            displayDate: displayDate,
            isCompleted: task.isCompleted,
            today: today,
            calendar: calendar,
            policy: taskDisplayPolicy
        )
        guard displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd else {
            return nil
        }

        let detailParts = calendarTaskDetailParts(
            note: task.note,
            publicationID: task.publicationID,
            applicationID: task.applicationID,
            publicationsByID: publicationsByID,
            applicationsByID: applicationsByID,
            store: store,
            language: language
        )
        let organizationName = organization.displayName(for: language)

        return CalendarWorkspaceEvent(
            id: "organization-task:\(organization.id):\(task.id)",
            source: .organizationTask(organizationID: organization.id, taskID: task.id),
            displayDate: displayDate,
            isRolledOverPastDue: isRolledOverPastDue,
            title: comment,
            subtitle: organizationName,
            detail: detailParts.map(\.text).joined(separator: " · "),
            place: formattedCalendarPlace(
                city: organization.city,
                country: organization.country,
                language: language,
                countryDisplayMode: store.calendarCountryDisplayMode
            ),
            timeText: "",
            kind: .taskDeadline,
            organizationName: organizationName,
            detailParts: detailParts,
            completedOn: task.completedOn,
            action: { store.openRoute(for: organization) },
            toggleCompletion: { isCompleted in
                store.toggleOrganizationTaskCompletion(
                    organizationID: organization.id,
                    taskID: task.id,
                    isCompleted: isCompleted
                )
            }
        )
    }

    let projectTaskSources = indexedSources?.projectTasks
        ?? resolvedProjects.flatMap { project in
            project.projectTasks.compactMap { task in
                calendarProjectTaskSource(project: project, task: task, today: today, calendar: calendar)
            }
        }
    let projectTaskEvents = projectTaskSources.filter { !centralTaskIDs.contains($0.task.id) }.compactMap { source -> CalendarWorkspaceEvent? in
        let project = source.project
        let task = source.task
        guard let comment = task.comment.nonEmpty else { return nil }
        let displayDate = taskDisplayPolicy == .rollOverPastDue
            ? source.displayDate
            : effectiveCalendarTaskDate(
                deadline: source.deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: taskDisplayPolicy
            )
        let isRolledOverPastDue = calendarTaskIsRolledOverPastDue(
            deadline: source.deadline,
            displayDate: displayDate,
            isCompleted: task.isCompleted,
            today: today,
            calendar: calendar,
            policy: taskDisplayPolicy
        )
        guard displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd else {
            return nil
        }

        let detailParts = calendarTaskDetailParts(
            note: task.note,
            publicationID: task.publicationID,
            applicationID: task.applicationID,
            publicationsByID: publicationsByID,
            applicationsByID: applicationsByID,
            store: store,
            language: language
        )

        return CalendarWorkspaceEvent(
            id: "project-task:\(project.id):\(task.id)",
            source: .projectTask(projectID: project.id, taskID: task.id),
            displayDate: displayDate,
            isRolledOverPastDue: isRolledOverPastDue,
            title: comment,
            subtitle: project.displayName(for: language),
            detail: detailParts.map(\.text).joined(separator: " · "),
            place: "",
            timeText: "",
            kind: .taskDeadline,
            detailParts: detailParts,
            completedOn: task.completedOn,
            action: {
                store.route = AppRoute(recordID: project.id, destination: .projects)
            },
            toggleCompletion: { isCompleted in
                store.toggleProjectTaskCompletion(projectID: project.id, taskID: task.id, isCompleted: isCompleted)
            }
        )
    }

    let publicationTaskSources = indexedSources?.publicationTasks
        ?? resolvedPublications.flatMap { publication in
            publication.publicationTasks.compactMap { task in
                calendarPublicationTaskSource(publication: publication, task: task, today: today, calendar: calendar)
            }
        }
    let publicationTaskEvents = publicationTaskSources.filter { !centralTaskIDs.contains($0.task.id) }.compactMap { source -> CalendarWorkspaceEvent? in
        let publication = source.publication
        let task = source.task
        guard let comment = task.comment.nonEmpty else { return nil }
        let displayDate = taskDisplayPolicy == .rollOverPastDue
            ? source.displayDate
            : effectiveCalendarTaskDate(
                deadline: source.deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: taskDisplayPolicy
            )
        let isRolledOverPastDue = calendarTaskIsRolledOverPastDue(
            deadline: source.deadline,
            displayDate: displayDate,
            isCompleted: task.isCompleted,
            today: today,
            calendar: calendar,
            policy: taskDisplayPolicy
        )
        guard displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd else {
            return nil
        }

        // The task's own publication is the row's context, not a detail.
        let detailParts = calendarTaskDetailParts(
            note: task.note,
            publicationID: nil,
            applicationID: task.applicationID,
            publicationsByID: publicationsByID,
            applicationsByID: applicationsByID,
            store: store,
            language: language
        )

        return CalendarWorkspaceEvent(
            id: "publication-task:\(publication.id):\(task.id)",
            source: .publicationTask(publicationID: publication.id, taskID: task.id),
            displayDate: displayDate,
            isRolledOverPastDue: isRolledOverPastDue,
            title: comment,
            subtitle: publication.title.nonEmpty ?? language.text("Untitled", "Utan titel"),
            detail: detailParts.map(\.text).joined(separator: " · "),
            place: "",
            timeText: "",
            kind: .taskDeadline,
            detailParts: detailParts,
            completedOn: task.completedOn,
            action: { store.openRoute(for: publication) },
            toggleCompletion: { isCompleted in
                store.togglePublicationTaskCompletion(publicationID: publication.id, taskID: task.id, isCompleted: isCompleted)
            }
        )
    }

    let teachingTaskSources = indexedSources?.teachingTasks
        ?? store.teachingWorkspaceTasks.compactMap { task in
            calendarTeachingTaskSource(task: task, today: today, calendar: calendar)
        }
    let teachingTaskEvents = teachingTaskSources.filter { !centralTaskIDs.contains($0.task.id) }.compactMap { source -> CalendarWorkspaceEvent? in
        let task = source.task
        guard let comment = task.comment.nonEmpty else { return nil }
        let displayDate = taskDisplayPolicy == .rollOverPastDue
            ? source.displayDate
            : effectiveCalendarTaskDate(
                deadline: source.deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: taskDisplayPolicy
            )
        let isRolledOverPastDue = calendarTaskIsRolledOverPastDue(
            deadline: source.deadline,
            displayDate: displayDate,
            isCompleted: task.isCompleted,
            today: today,
            calendar: calendar,
            policy: taskDisplayPolicy
        )
        guard displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd else {
            return nil
        }

        let detailParts = calendarTaskDetailParts(
            note: task.note,
            publicationID: task.publicationID,
            applicationID: task.applicationID,
            publicationsByID: publicationsByID,
            applicationsByID: applicationsByID,
            store: store,
            language: language
        )

        return CalendarWorkspaceEvent(
            id: "teaching-task:\(task.id)",
            source: .teachingTask(taskID: task.id),
            displayDate: displayDate,
            isRolledOverPastDue: isRolledOverPastDue,
            title: comment,
            subtitle: "",
            detail: detailParts.map(\.text).joined(separator: " · "),
            place: "",
            timeText: "",
            kind: .taskDeadline,
            detailParts: detailParts,
            completedOn: task.completedOn,
            action: nil,
            toggleCompletion: { isCompleted in
                store.toggleTeachingWorkspaceTaskCompletion(taskID: task.id, isCompleted: isCompleted)
            }
        )
    }

    let centralTaskEvents = store.taskItems.compactMap { task -> CalendarWorkspaceEvent? in
        guard !task.isEmpty,
              let title = task.comment.nonEmpty,
              let deadline = DateParsers.isoDay.date(from: task.deadline) else {
            return nil
        }
        let displayDate = effectiveCalendarTaskDate(
            deadline: deadline,
            completedOn: task.completedOn,
            isCompleted: task.isCompleted,
            today: today,
            calendar: calendar,
            policy: taskDisplayPolicy
        )
        guard displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd else { return nil }
        return CalendarWorkspaceEvent(
            id: "central-task:\(task.id)",
            source: .teachingTask(taskID: task.id),
            displayDate: displayDate,
            isRolledOverPastDue: calendarTaskIsRolledOverPastDue(
                deadline: deadline,
                displayDate: displayDate,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: taskDisplayPolicy,
                deadlineMoment: task.deadlineMoment(calendar: calendar)
            ),
            title: title,
            subtitle: "",
            detail: task.note,
            place: "",
            // Only the single deadline time (no range); it also sorts the
            // task among the day's timed events.
            timeText: task.calendarTimeText(displayDate: displayDate, calendar: calendar),
            kind: .taskDeadline,
            detailParts: calendarDetailParts([(.note, task.note)]),
            completedOn: task.completedOn,
            action: nil,
            toggleCompletion: { store.toggleTaskItemCompletion(taskID: task.id, isCompleted: $0) }
        )
    }

    let congressSources = indexedSources?.congresses
        ?? resolvedOrganizations
            .filter { !$0.congresses.isEmpty }
            .flatMap { organization in
                organization.congresses.map { congress in
                    CalendarWorkspaceCongressSource(organization: organization, congress: congress)
                }
            }
    let congressEvents = congressSources.flatMap { source in
        var rows: [CalendarWorkspaceEvent] = calendarCongressDateEvents(
            congress: source.congress,
            organization: source.organization,
            store: store,
            language: language,
            displayedMonthStart: displayedMonthStart,
            displayedMonthEnd: displayedMonthEnd,
            calendar: calendar
        )
        rows.append(
            contentsOf: calendarCongressDeadlineEvents(
                congress: source.congress,
                organization: source.organization,
                store: store,
                language: language,
                displayedMonthStart: displayedMonthStart,
                displayedMonthEnd: displayedMonthEnd,
                calendar: calendar
            )
        )
        return rows
        }

    let travelEvents = resolvedTravelRecords.compactMap { travel -> CalendarWorkspaceEvent? in
        guard let date = DateParsers.isoDay.date(from: travel.date) else { return nil }
        let displayDate = calendar.startOfDay(for: date)
        guard displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd else {
            return nil
        }

        let fromPlace = formattedCalendarPlace(
            city: travel.fromCity,
            country: travel.fromCountry,
            language: language,
            countryDisplayMode: store.calendarCountryDisplayMode
        )
        let toPlace = formattedCalendarPlace(
            city: travel.toCity,
            country: travel.toCountry,
            language: language,
            countryDisplayMode: store.calendarCountryDisplayMode
        )
        let title = travel.mode.localizedName(language: language)
        let congressDetail = calendarTravelCongressDetail(
            travel: travel,
            organizationsByID: organizationsByID,
            language: language
        )
        let detail = [
            congressDetail,
            travel.reference.nonEmpty
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let travelDetailParts = calendarDetailParts([
            (.congress, congressDetail),
            (.reference, travel.reference)
        ])

        return CalendarWorkspaceEvent(
            id: "travel:\(travel.id)",
            source: .travel(travel.id),
            displayDate: displayDate,
            title: title,
            subtitle: toPlace.nonEmpty ?? fromPlace,
            detail: detail,
            place: [fromPlace.nonEmpty, toPlace.nonEmpty].compactMap { $0 }.joined(separator: " → "),
            timeText: timeRangeText(
                start: travel.departureTime,
                end: travel.arrivalTime,
                startUncertain: travel.departureTimeUncertain,
                endUncertain: travel.arrivalTimeUncertain
            ),
            kind: .travel,
            travelMode: travel.mode,
            detailParts: travelDetailParts,
            completedOn: nil,
            action: nil,
            toggleCompletion: nil
        )
    }

    let accommodationEvents = resolvedAccommodationRecords.flatMap { accommodation -> [CalendarWorkspaceEvent] in
        let place = formattedCalendarPlace(
            city: accommodation.city,
            country: accommodation.country,
            language: language,
            countryDisplayMode: store.calendarCountryDisplayMode
        )
        let congressDetail = calendarAccommodationCongressDetail(
            accommodation: accommodation,
            organizationsByID: organizationsByID,
            language: language
        )
        let detail = [
            congressDetail,
            accommodation.reference.nonEmpty
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let accommodationDetailParts = calendarDetailParts([
            (.congress, congressDetail),
            (.reference, accommodation.reference)
        ])
        let eventPlace = [accommodation.hotelName.nonEmpty, place.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
        var rows: [CalendarWorkspaceEvent] = []

        if let checkInDate = accommodation.checkInDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) {
            let displayDate = calendar.startOfDay(for: checkInDate)
            if displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd {
                rows.append(
                    CalendarWorkspaceEvent(
                        id: "accommodation:\(accommodation.id):check-in",
                        source: .accommodation(accommodation.id),
                        displayDate: displayDate,
                        title: language.text("Hotel check-in", "Hotell incheckning"),
                        subtitle: accommodation.hotelName,
                        detail: detail,
                        place: eventPlace,
                        timeText: normalizedCalendarTimeInput(accommodation.checkInTime),
                        kind: .accommodation,
                        detailParts: accommodationDetailParts,
                        completedOn: nil,
                        action: nil,
                        toggleCompletion: nil
                    )
                )
            }
        }

        if let checkInDate = accommodation.checkInDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
           let checkOutDate = accommodation.checkOutDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
           let firstStayDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: checkInDate)),
           firstStayDate < calendar.startOfDay(for: checkOutDate),
           let lastStayDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: checkOutDate)) {
            for stayDate in calendarDates(from: firstStayDate, to: lastStayDate, calendar: calendar) {
                guard stayDate >= displayedMonthStart, stayDate <= displayedMonthEnd else { continue }
                rows.append(
                    CalendarWorkspaceEvent(
                        id: "accommodation:\(accommodation.id):stay:\(DateParsers.isoDay.string(from: stayDate))",
                        source: .accommodation(accommodation.id),
                        displayDate: stayDate,
                        title: language.text("Hotel", "Hotell"),
                        subtitle: accommodation.hotelName,
                        detail: detail,
                        place: eventPlace,
                        timeText: "",
                        kind: .accommodation,
                        detailParts: accommodationDetailParts,
                        completedOn: nil,
                        action: nil,
                        toggleCompletion: nil
                    )
                )
            }
        }

        if let checkOutDate = accommodation.checkOutDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) {
            let displayDate = calendar.startOfDay(for: checkOutDate)
            if displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd {
                rows.append(
                    CalendarWorkspaceEvent(
                        id: "accommodation:\(accommodation.id):check-out",
                        source: .accommodation(accommodation.id),
                        displayDate: displayDate,
                        title: language.text("Hotel check-out", "Hotell utcheckning"),
                        subtitle: accommodation.hotelName,
                        detail: detail,
                        place: eventPlace,
                        timeText: normalizedCalendarTimeInput(accommodation.checkOutTime),
                        kind: .accommodation,
                        detailParts: accommodationDetailParts,
                        completedOn: nil,
                        action: nil,
                        toggleCompletion: nil
                    )
                )
            }
        }

        return rows
    }

    let meetingEvents = resolvedMeetingRecords.compactMap { meeting -> CalendarWorkspaceEvent? in
        guard let date = DateParsers.isoDay.date(from: meeting.date) else { return nil }
        let displayDate = calendar.startOfDay(for: date)
        guard displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd else {
            return nil
        }

        let meetingOrganizationIDs = meeting.organizationIDs.isEmpty
            ? (meeting.organizationID.map { [$0] } ?? [])
            : meeting.organizationIDs
        let organizationText = meetingOrganizationIDs
            .compactMap { id in organizationsByID[id]?.displayName(for: language) }
            .joined(separator: ", ")
            .nonEmpty
        let applicationText = meeting.applicationIDs
            .compactMap { id in
                applicationsByID[id].map { application in
                    store.localizedGrantName(for: application, language: language).nonEmpty
                        ?? store.organizationLabel(for: application, language: language)
                }
            }
            .joined(separator: ", ")
            .nonEmpty
            .map { "\(language.text("Grant", "Anslag")): \($0)" }
        let publicationText = meeting.publicationIDs
            .compactMap { id in
                publicationsByID[id]?.title.nonEmpty
            }
            .joined(separator: ", ")
            .nonEmpty
            .map { "\(language.text("Publication", "Publikation")): \($0)" }
        let mediaText = meeting.mediaAppearanceIDs
            .compactMap { id in
                store.cvMediaAppearances.first(where: { $0.id == id }).map { appearance in
                    appearance.localizedTitle(language: language).nonEmpty ?? appearance.displayTitle
                }
            }
            .joined(separator: ", ")
            .nonEmpty
            .map { "\(language.text("Media", "Media")): \($0)" }
        let teachingAssignmentText = calendarMeetingTeachingAssignmentIDs(meeting)
            .compactMap { teachingAssignmentsByID[$0] }
            .map { calendarTeachingAssignmentLabel($0, store: store, language: language) }
            .joined(separator: ", ")
            .nonEmpty
            .map { "\(language.text("Teaching assignment", "Undervisningsuppdrag")): \($0)" }
        let meetingMode = CalendarMeetingMode(rawValue: meeting.meetingMode)
        let detailMode = meetingMode == .hybrid ? meetingMode?.localizedName(language: language) : nil
        let detail = [
            detailMode?.nonEmpty,
            meeting.detail.nonEmpty,
            teachingAssignmentText,
            organizationText,
            applicationText,
            publicationText,
            mediaText
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let isLeave = store.calendarCategoryIsLeave(named: meeting.meetingType)
        // The rest of the app shows the participants in the title; the
        // calendar list shows them on their own line and the organisation
        // after the title, so they are kept apart here too.
        let titleParts = calendarMeetingTitleParts(
            title: meeting.title,
            participantNames: meeting.participantNames,
            isLeave: isLeave,
            language: language
        )
        let listDetailParts = calendarDetailParts([
            (nil, detailMode),
            (.note, meeting.detail),
            (.teaching, teachingAssignmentText),
            // A leave row has no title to put the organisation after.
            (.organization, isLeave ? organizationText : nil),
            (.application, applicationText),
            (.publication, publicationText),
            (.media, mediaText)
        ])
        let meetingPlace = meetingMode == .online
            ? language.text("Online", "Online")
            : formattedCalendarPlace(
                city: meeting.place,
                country: meeting.country,
                language: language,
                countryDisplayMode: store.calendarCountryDisplayMode
            )

        return CalendarWorkspaceEvent(
            id: "meeting:\(meeting.id)",
            source: .meeting(meeting.id),
            displayDate: displayDate,
            title: titleParts.title,
            subtitle: organizationText ?? "",
            detail: detail,
            place: meetingPlace,
            timeText: timeRangeText(start: meeting.startTime, end: meeting.endTime),
            kind: .meeting,
            listTitle: titleParts.listTitle,
            participantNames: titleParts.participantNames,
            organizationName: isLeave ? nil : organizationText,
            detailParts: listDetailParts,
            completedOn: nil,
            action: nil,
            toggleCompletion: nil
        )
    }

    let mediaAppearanceEvents = store.cvMediaAppearances.compactMap { appearance -> CalendarWorkspaceEvent? in
        guard let date = DateParsers.isoDay.date(from: appearance.date) else { return nil }
        let displayDate = calendar.startOfDay(for: date)
        guard displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd else { return nil }

        let researcherNames = appearance.authorIDs.compactMap { authorID in
            store.publicationAuthor(id: authorID)?.displayName
        }
        let title = appearance.localizedTitle(language: language).nonEmpty
            ?? appearance.displayTitle
        let detail = [
            appearance.comment.nonEmpty,
            researcherNames.isEmpty ? nil : researcherNames.joined(separator: ", ")
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let appearanceMode = CalendarMeetingMode.allCases.first {
            $0.rawValue.caseInsensitiveCompare(appearance.meetingMode) == .orderedSame
        }
        let appearancePlace = appearanceMode == .online
            ? language.text("Online", "Online")
            : formattedCalendarPlace(
                city: appearance.place,
                country: appearance.country,
                language: language,
                countryDisplayMode: store.calendarCountryDisplayMode
            )

        return CalendarWorkspaceEvent(
            id: "media-appearance:\(appearance.id)",
            source: .mediaAppearance(appearance.id),
            displayDate: displayDate,
            title: title,
            subtitle: language.text("Media appearance", "Medverkan i media"),
            detail: detail,
            place: appearancePlace,
            timeText: timeRangeText(start: appearance.startTime, end: appearance.endTime),
            kind: .meeting,
            meetingCategoryName: "Övrigt",
            // The list shows the researchers on the participants line.
            participantNames: researcherNames,
            detailParts: calendarDetailParts([(.note, appearance.comment)]),
            completedOn: nil,
            action: { store.openRoute(for: appearance) },
            toggleCompletion: nil
        )
    }

    events.append(contentsOf: holidayEvents)
    events.append(contentsOf: congressEvents)
    events.append(contentsOf: travelEvents)
    events.append(contentsOf: accommodationEvents)
    events.append(contentsOf: meetingEvents)
    events.append(contentsOf: mediaAppearanceEvents)
    events.append(contentsOf: applicationEvents)
    events.append(contentsOf: appliedQuestionEvents)
    events.append(contentsOf: reviewDeadlineEvents)
    events.append(contentsOf: organizationTaskEvents)
    events.append(contentsOf: projectTaskEvents)
    events.append(contentsOf: publicationTaskEvents)
    events.append(contentsOf: teachingTaskEvents)
    events.append(contentsOf: centralTaskEvents)
    return events
}

/// A task row's detail parts: the note, the linked publication and the
/// linked grant. Joined with " · " they are the task's detail text.
@MainActor
private func calendarTaskDetailParts(
    note: String,
    publicationID: String?,
    applicationID: String?,
    publicationsByID: [String: PublicationRecord],
    applicationsByID: [String: GrantApplication],
    store: GrantDataStore,
    language: AppLanguage
) -> [CalendarWorkspaceDetailPart] {
    let publicationText: String? = publicationID
        .flatMap { id in publicationsByID[id]?.title.nonEmpty }
        .map { title in "\(language.text("Publication", "Publikation")): \(title)" }
    let applicationText: String? = applicationID
        .flatMap { id in applicationsByID[id] }
        .map { application in
            let grantTitle = store.localizedGrantName(for: application, language: language).nonEmpty
                ?? store.organizationLabel(for: application, language: language)
            return "\(language.text("Grant", "Anslag")): \(grantTitle)"
        }
    return calendarDetailParts([
        (.note, note),
        (.publication, publicationText),
        (.application, applicationText)
    ])
}

/// The older one-string form of a meeting title. The calendar now builds
/// meeting titles with `calendarMeetingTitleParts`, which gives the same
/// title and keeps the participants apart for the list.
private func calendarMeetingEventTitle(
    _ meeting: CalendarMeetingRecord,
    participantText: String?,
    isLeave: Bool,
    language: AppLanguage
) -> String {
    // Categories marked "Leave" in Settings > Calendar categories show no title.
    guard !isLeave else { return "" }

    let base = meeting.title.nonEmpty ?? language.text("Activity", "Aktivitet")
    if let participantText {
        return "\(base) (\(participantText))"
    }
    return base
}

func calendarShowsApplicationDeadline(_ application: GrantApplication) -> Bool {
    application.closeDate != nil && application.isToApplyStatus
}

private func holidaysInCalendarRange(
    from startDate: Date,
    to endDate: Date,
    countries: [HolidayCountry],
    calendar: Calendar
) -> [HolidayDefinition] {
    guard !countries.isEmpty else { return [] }
    let startYear = calendar.component(.year, from: startDate)
    let endYear = calendar.component(.year, from: endDate)
    var holidays: [HolidayDefinition] = []
    for year in startYear...endYear {
        holidays.append(contentsOf: HolidayCalendarBuilder.holidays(for: countries, year: year, calendar: calendar))
    }
    return holidays
        .filter { holiday in
            let normalized = calendar.startOfDay(for: holiday.date)
            return normalized >= startDate && normalized <= endDate
        }
        .sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            if lhs.country != rhs.country {
                return lhs.country.rawValue < rhs.country.rawValue
            }
            return lhs.titleSv.localizedStandardCompare(rhs.titleSv) == .orderedAscending
        }
}

func effectiveCalendarTaskDate(
    deadline: Date,
    completedOn: String? = nil,
    isCompleted: Bool,
    today: Date,
    calendar: Calendar,
    policy: CalendarTaskDisplayPolicy
) -> Date {
    if isCompleted,
       let completedDate = normalizedTaskCompletionDate(completedOn, calendar: calendar) {
        return completedDate
    }
    let normalizedDeadline = calendar.startOfDay(for: deadline)
    guard policy == .rollOverPastDue, !isCompleted, normalizedDeadline < today else {
        return normalizedDeadline
    }
    return today
}

func calendarTaskIsRolledOverPastDue(
    deadline: Date,
    displayDate: Date,
    isCompleted: Bool,
    today: Date,
    calendar: Calendar,
    policy: CalendarTaskDisplayPolicy,
    deadlineMoment: Date? = nil,
    now: Date = Date()
) -> Bool {
    guard policy == .rollOverPastDue, !isCompleted else {
        return false
    }
    let normalizedDeadline = calendar.startOfDay(for: deadline)
    if normalizedDeadline < today {
        return calendar.isDate(displayDate, inSameDayAs: today)
    }
    // A task with a clock time is overdue once that time has passed on the
    // deadline day itself.
    if let deadlineMoment,
       calendar.isDate(normalizedDeadline, inSameDayAs: today),
       calendar.isDate(displayDate, inSameDayAs: today) {
        return deadlineMoment <= now
    }
    return false
}

func normalizedTaskCompletionDate(_ raw: String?, calendar: Calendar = .current) -> Date? {
    guard let normalized = raw
        .map(DateParsers.canonicalizedDayInput(_:))
        .flatMap(\.trimmedOrNil),
          let parsed = DateParsers.isoDay.date(from: normalized) else {
        return nil
    }
    return calendar.startOfDay(for: parsed)
}

func taskCompletionDateAfterToggle(
    existingCompletedOn: String?,
    isCompleted: Bool,
    todayString: String
) -> String? {
    guard isCompleted else { return nil }
    return existingCompletedOn
        .map(DateParsers.canonicalizedDayInput(_:))
        .flatMap(\.trimmedOrNil)
        ?? todayString
}

enum CalendarWorkspaceTodayProgressBucket: Int {
    case handled
    case scheduledRemaining
    case unscheduledRemaining
}

func calendarWorkspaceTodayProgressBucket(
    displayDate: Date,
    today: Date,
    now: Date,
    calendar: Calendar,
    isCompleted: Bool,
    cutoffDate: Date?
) -> CalendarWorkspaceTodayProgressBucket? {
    guard calendar.isDate(displayDate, inSameDayAs: today) else {
        return nil
    }
    if isCompleted {
        return .handled
    }
    if let cutoffDate {
        return cutoffDate <= now ? .handled : .scheduledRemaining
    }
    return .unscheduledRemaining
}

func calendarWorkspaceSortTimeKey(_ timeText: String) -> String? {
    let trimmed = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let separators = CharacterSet(charactersIn: "–—-")
    let start = trimmed.components(separatedBy: separators).first ?? trimmed
    return start.replacingOccurrences(of: "?", with: "")
}

func calendarWorkspaceEventSort(
    _ lhs: CalendarWorkspaceEvent,
    _ rhs: CalendarWorkspaceEvent,
    today: Date,
    now: Date,
    calendar: Calendar,
    cutoffDateProvider: (CalendarWorkspaceEvent) -> Date?
) -> Bool {
    if lhs.displayDate != rhs.displayDate {
        return lhs.displayDate < rhs.displayDate
    }

    let leftBucket = calendarWorkspaceTodayProgressBucket(
        displayDate: lhs.displayDate,
        today: today,
        now: now,
        calendar: calendar,
        isCompleted: lhs.isCompleted,
        cutoffDate: cutoffDateProvider(lhs)
    )
    let rightBucket = calendarWorkspaceTodayProgressBucket(
        displayDate: rhs.displayDate,
        today: today,
        now: now,
        calendar: calendar,
        isCompleted: rhs.isCompleted,
        cutoffDate: cutoffDateProvider(rhs)
    )
    if let leftBucket, let rightBucket, leftBucket != rightBucket {
        return leftBucket.rawValue < rightBucket.rawValue
    }

    let leftTime = calendarWorkspaceSortTimeKey(lhs.timeText)
    let rightTime = calendarWorkspaceSortTimeKey(rhs.timeText)
    switch (leftTime, rightTime) {
    case let (left?, right?):
        if left != right {
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    case (.some, nil):
        return true
    case (nil, .some):
        return false
    case (nil, nil):
        break
    }
    // A task with a deadline time comes after other events at the same time.
    if leftTime != nil, rightTime != nil, (lhs.kind == .taskDeadline) != (rhs.kind == .taskDeadline) {
        return rhs.kind == .taskDeadline
    }
    if lhs.kind == .taskDeadline, rhs.kind == .taskDeadline, lhs.isCompleted != rhs.isCompleted {
        return lhs.isCompleted && !rhs.isCompleted
    }
    if lhs.kind.sortRank != rhs.kind.sortRank {
        return lhs.kind.sortRank < rhs.kind.sortRank
    }
    let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
    if titleComparison != .orderedSame {
        return titleComparison == .orderedAscending
    }
    return lhs.id < rhs.id
}

@MainActor
func calendarVisibleDateRange(
    store: GrantDataStore,
    calendar: Calendar,
    today: Date,
    travelRecords: [CalendarTravelRecord]? = nil,
    accommodationRecords: [CalendarAccommodationRecord]? = nil,
    meetingRecords: [CalendarMeetingRecord]? = nil,
    additionalDates: [Date] = []
) -> ClosedRange<Date> {
    let fallbackStart = calendar.date(byAdding: .year, value: -1, to: today) ?? today
    let fallbackEnd = calendar.date(byAdding: .year, value: 1, to: today) ?? today
    var candidateDates: [Date] = [fallbackStart, fallbackEnd]
    let resolvedTravelRecords = travelRecords ?? store.calendarTravelRecordsForRead
    let resolvedAccommodationRecords = accommodationRecords ?? store.calendarAccommodationRecordsForRead
    let resolvedMeetingRecords = meetingRecords ?? store.calendarMeetingRecords
    candidateDates.append(contentsOf: additionalDates.map { calendar.startOfDay(for: $0) })

    candidateDates.append(contentsOf: store.applicationsForRead.compactMap { application in
        guard calendarShowsApplicationDeadline(application) else { return nil }
        return application.closeDate.map { calendar.startOfDay(for: $0) }
    })

    candidateDates.append(contentsOf: store.cvReviewEntries.compactMap { review in
        guard !review.isCompleted else { return nil }
        return review.deadlineDay(calendar: calendar)
    })

    candidateDates.append(contentsOf: store.organizationsForCongressRead.flatMap { organization in
        organization.projectTasks.compactMap { task in
            guard let deadline = DateParsers.isoDay.date(from: task.deadline) else { return nil }
            return effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            )
        }
    })

    candidateDates.append(contentsOf: store.projectsForRead.flatMap { project in
        project.projectTasks.compactMap { task in
            guard let deadline = DateParsers.isoDay.date(from: task.deadline) else { return nil }
            return effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            )
        }
    })

    candidateDates.append(contentsOf: store.publicationRecordsForRead.flatMap { publication in
        publication.publicationTasks.compactMap { task in
            guard let deadline = DateParsers.isoDay.date(from: task.deadline) else { return nil }
            return effectiveCalendarTaskDate(
                deadline: deadline,
                completedOn: task.completedOn,
                isCompleted: task.isCompleted,
                today: today,
                calendar: calendar,
                policy: .rollOverPastDue
            )
        }
    })

    candidateDates.append(contentsOf: store.teachingWorkspaceTasks.compactMap { task in
        guard let deadline = DateParsers.isoDay.date(from: task.deadline) else { return nil }
        return effectiveCalendarTaskDate(
            deadline: deadline,
            completedOn: task.completedOn,
            isCompleted: task.isCompleted,
            today: today,
            calendar: calendar,
            policy: .rollOverPastDue
        )
    })

    let congressCalendarDates = store.organizationsForCongressRead.flatMap { organization -> [Date] in
        organization.congresses.flatMap { congress -> [Date] in
            let rawDates: [Date?] = [
                congress.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
                congress.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
                congress.abstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
                congress.lateAbstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
            ]
            return rawDates.compactMap { $0.map { calendar.startOfDay(for: $0) } }
        }
    }
    candidateDates.append(contentsOf: congressCalendarDates)

    candidateDates.append(contentsOf: resolvedTravelRecords.compactMap { record in
        DateParsers.isoDay.date(from: record.date).map { calendar.startOfDay(for: $0) }
    })

    candidateDates.append(contentsOf: resolvedTravelRecords.compactMap { record in
        DateParsers.isoDay.date(from: record.resolvedArrivalDateString()).map { calendar.startOfDay(for: $0) }
    })

    candidateDates.append(contentsOf: resolvedAccommodationRecords.flatMap { record -> [Date] in
        [
            record.checkInDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
            record.checkOutDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
        ]
        .compactMap { $0.map { calendar.startOfDay(for: $0) } }
    })

    candidateDates.append(contentsOf: resolvedMeetingRecords.compactMap { record in
        DateParsers.isoDay.date(from: record.date).map { calendar.startOfDay(for: $0) }
    })

    let earliestDate = candidateDates.min() ?? fallbackStart
    let latestDate = candidateDates.max() ?? fallbackEnd
    let startOfEarliestYear =
        calendar.date(from: calendar.dateComponents([.year], from: earliestDate))
        ?? earliestDate
    let startOfLatestYear =
        calendar.date(from: calendar.dateComponents([.year], from: latestDate))
        ?? latestDate
    let endOfLatestYear =
        calendar.date(byAdding: DateComponents(year: 1, day: -1), to: startOfLatestYear)
        ?? latestDate

    return startOfEarliestYear...endOfLatestYear
}

@MainActor
private func calendarCongressDateEvents(
    congress: OrganizationCongress,
    organization: OrganizationRecord,
    store: GrantDataStore,
    language: AppLanguage,
    displayedMonthStart: Date,
    displayedMonthEnd: Date,
    calendar: Calendar
) -> [CalendarWorkspaceEvent] {
    let today = calendar.startOfDay(for: Date())
    let startDate = congress.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
    let endDate = congress.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) ?? startDate
    guard let startDate = startDate ?? endDate else { return [] }

    let normalizedStart = calendar.startOfDay(for: startDate)
    let normalizedEnd = calendar.startOfDay(for: endDate ?? startDate)
    guard normalizedEnd >= today else { return [] }
    guard normalizedEnd >= displayedMonthStart, normalizedStart <= displayedMonthEnd else {
        return []
    }

    let visibleStart = max(normalizedStart, max(displayedMonthStart, today))
    let visibleEnd = min(normalizedEnd, displayedMonthEnd)
    let place = formattedCalendarPlace(
        city: congress.city,
        country: congress.country,
        language: language,
        countryDisplayMode: store.calendarCountryDisplayMode
    )
    let title = congress.title.nonEmpty ?? organization.displayName(for: language)

    return calendarDates(from: visibleStart, to: visibleEnd, calendar: calendar).map { date in
            CalendarWorkspaceEvent(
                id: "congress:\(organization.id):\(congress.id):\(DateParsers.isoDay.string(from: date))",
                source: .congress(organizationID: organization.id, congressID: congress.id),
                displayDate: date,
                rangeStartDate: normalizedStart,
                rangeEndDate: normalizedEnd,
                isDateUncertain: congress.fromUncertain || congress.toUncertain,
                title: title,
                subtitle: place,
                detail: "",
            place: place,
            timeText: "",
            kind: .congress,
            completedOn: nil,
            action: {
                store.openRouteToCongress(organizationID: organization.id, congressID: congress.id)
            },
            toggleCompletion: nil
        )
    }
}

@MainActor
private func calendarCongressDeadlineEvents(
    congress: OrganizationCongress,
    organization: OrganizationRecord,
    store: GrantDataStore,
    language: AppLanguage,
    displayedMonthStart: Date,
    displayedMonthEnd: Date,
    calendar: Calendar
) -> [CalendarWorkspaceEvent] {
    let deadlineCandidates: [(String, Date?, Bool, String)] = [
        (
            language.text("Abstract deadline", "Abstractfrist"),
            congress.abstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
            congress.abstractSubmissionDeadlineUncertain,
            CalendarAutomaticEventHideKey.congressAbstractDeadline(organizationID: organization.id, congressID: congress.id)
        ),
        (
            language.text("Late abstract deadline", "Sen abstractfrist"),
            congress.lateAbstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
            congress.lateAbstractSubmissionDeadlineUncertain,
            CalendarAutomaticEventHideKey.congressLateAbstractDeadline(organizationID: organization.id, congressID: congress.id)
        )
    ]

    let place = formattedCalendarPlace(
        city: congress.city,
        country: congress.country,
        language: language,
        countryDisplayMode: store.calendarCountryDisplayMode
    )
    let title = calendarCongressDeadlineTitle(
        congress: congress,
        organization: organization,
        language: language,
        calendar: calendar
    )

    return deadlineCandidates.compactMap { label, date, isUncertain, hideKey -> CalendarWorkspaceEvent? in
        guard let date else { return nil }
        let normalized = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        guard normalized >= today else { return nil }
        guard normalized >= displayedMonthStart, normalized <= displayedMonthEnd else { return nil }
        let displayLabel = uncertainCalendarText(label, uncertain: isUncertain, language: language)
        return CalendarWorkspaceEvent(
            id: "congress-deadline:\(hideKey):\(DateParsers.isoDay.string(from: normalized))",
            source: .congress(organizationID: organization.id, congressID: congress.id),
            automaticHideKey: hideKey,
            isHiddenFromCalendar: store.isAutomaticCalendarEventHidden(hideKey),
            displayDate: normalized,
            isDateUncertain: isUncertain,
            title: title,
            subtitle: displayLabel,
            detail: displayLabel,
            place: place,
            timeText: "",
            kind: .applicationDeadline,
            completedOn: nil,
            action: {
                store.openRouteToCongress(organizationID: organization.id, congressID: congress.id)
            },
            toggleCompletion: nil
        )
    }
}

@MainActor
private func calendarCongressTravelEvents(
    congress: OrganizationCongress,
    organization: OrganizationRecord,
    store: GrantDataStore,
    language: AppLanguage,
    displayedMonthStart: Date,
    displayedMonthEnd: Date,
    calendar: Calendar
) -> [CalendarWorkspaceEvent] {
    let title = congress.title.nonEmpty ?? organization.displayName(for: language)
    let congressDetail = "\(language.text("Congress", "Kongress")): \(title)"
    let congressPlace = formattedCalendarPlace(
        city: congress.city,
        country: congress.country,
        language: language,
        countryDisplayMode: store.calendarCountryDisplayMode
    )

    let standaloneTravelIDs = Set(store.calendarTravelRecordsForRead.map(\.id))
    let flightEvents = congress.travelFlights.compactMap { flight -> CalendarWorkspaceEvent? in
        guard !standaloneTravelIDs.contains(flight.id) else { return nil }
        guard let date = (flight.fromDate.nonEmpty ?? flight.toDate.nonEmpty).flatMap(DateParsers.isoDay.date(from:)) else {
            return nil
        }
        let displayDate = calendar.startOfDay(for: date)
        guard displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd else {
            return nil
        }

        let fromPlace = formattedCalendarPlace(
            city: flight.fromCity,
            country: flight.fromCountry,
            language: language,
            countryDisplayMode: store.calendarCountryDisplayMode
        )
        let toPlace = formattedCalendarPlace(
            city: flight.toCity,
            country: flight.toCountry,
            language: language,
            countryDisplayMode: store.calendarCountryDisplayMode
        )
        let hideKey = CalendarAutomaticEventHideKey.congressFlight(
            organizationID: organization.id,
            congressID: congress.id,
            flightID: flight.id
        )

        return CalendarWorkspaceEvent(
            id: "congress-flight:\(organization.id):\(congress.id):\(flight.id)",
            source: .congress(organizationID: organization.id, congressID: congress.id),
            automaticHideKey: hideKey,
            isHiddenFromCalendar: store.isAutomaticCalendarEventHidden(hideKey),
            displayDate: displayDate,
            title: flight.mode.localizedName(language: language),
            subtitle: title,
            detail: congressDetail,
            place: [fromPlace.nonEmpty, toPlace.nonEmpty].compactMap { $0 }.joined(separator: " → "),
            timeText: timeRangeText(start: flight.fromTime, end: flight.toTime),
            kind: .travel,
            travelMode: flight.mode,
            detailParts: calendarDetailParts([(.congress, congressDetail)]),
            completedOn: nil,
            action: {
                store.openRouteToCongress(organizationID: organization.id, congressID: congress.id)
            },
            toggleCompletion: nil
        )
    }

    var hotelEvents: [CalendarWorkspaceEvent] = []
    for hotel in organizationCongressHotelsForPersistence(congress) {
        if let checkInDate = hotel.fromDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) {
            let displayDate = calendar.startOfDay(for: checkInDate)
            if displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd {
                let usesLegacyHotelKey = hotel.id == "primary"
                let hideKey = usesLegacyHotelKey
                    ? CalendarAutomaticEventHideKey.congressHotelCheckIn(organizationID: organization.id, congressID: congress.id)
                    : CalendarAutomaticEventHideKey.congressHotelCheckIn(organizationID: organization.id, congressID: congress.id, hotelID: hotel.id)
                hotelEvents.append(
                    CalendarWorkspaceEvent(
                        id: usesLegacyHotelKey
                            ? "congress-hotel-check-in:\(organization.id):\(congress.id)"
                            : "congress-hotel-check-in:\(organization.id):\(congress.id):\(hotel.id)",
                        source: .congress(organizationID: organization.id, congressID: congress.id),
                        automaticHideKey: hideKey,
                        isHiddenFromCalendar: store.isAutomaticCalendarEventHidden(hideKey),
                        displayDate: displayDate,
                        title: language.text("Hotel check-in", "Hotell incheckning"),
                        subtitle: title,
                        detail: congressDetail,
                        place: [hotel.hotelName.nonEmpty, congressPlace.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                        timeText: normalizedCalendarTimeInput(hotel.fromTime),
                        kind: .accommodation,
                        detailParts: calendarDetailParts([(.congress, congressDetail)]),
                        completedOn: nil,
                        action: {
                            store.openRouteToCongress(organizationID: organization.id, congressID: congress.id)
                        },
                        toggleCompletion: nil
                    )
                )
            }
        }
        if let checkInDate = hotel.fromDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
           let checkOutDate = hotel.toDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
           let firstStayDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: checkInDate)),
           firstStayDate < calendar.startOfDay(for: checkOutDate) {
            let usesLegacyHotelKey = hotel.id == "primary"
            let eventHotelID = usesLegacyHotelKey ? "primary" : hotel.id
            for stayDate in calendarDates(from: firstStayDate, to: calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: checkOutDate)) ?? firstStayDate, calendar: calendar) {
                guard stayDate >= displayedMonthStart, stayDate <= displayedMonthEnd else { continue }
                let dayString = DateParsers.isoDay.string(from: stayDate)
                let hideKey = CalendarAutomaticEventHideKey.congressHotelStay(
                    organizationID: organization.id,
                    congressID: congress.id,
                    hotelID: eventHotelID,
                    dayString: dayString
                )
                hotelEvents.append(
                    CalendarWorkspaceEvent(
                        id: "congress-hotel-stay:\(organization.id):\(congress.id):\(eventHotelID):\(dayString)",
                        source: .congress(organizationID: organization.id, congressID: congress.id),
                        automaticHideKey: hideKey,
                        isHiddenFromCalendar: store.isAutomaticCalendarEventHidden(hideKey),
                        displayDate: stayDate,
                        title: language.text("Hotel", "Hotell"),
                        subtitle: title,
                        detail: congressDetail,
                        place: [hotel.hotelName.nonEmpty, congressPlace.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                        timeText: "",
                        kind: .accommodation,
                        detailParts: calendarDetailParts([(.congress, congressDetail)]),
                        completedOn: nil,
                        action: {
                            store.openRouteToCongress(organizationID: organization.id, congressID: congress.id)
                        },
                        toggleCompletion: nil
                    )
                )
            }
        }
        if let checkOutDate = hotel.toDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) {
            let displayDate = calendar.startOfDay(for: checkOutDate)
            if displayDate >= displayedMonthStart, displayDate <= displayedMonthEnd {
                let usesLegacyHotelKey = hotel.id == "primary"
                let hideKey = usesLegacyHotelKey
                    ? CalendarAutomaticEventHideKey.congressHotelCheckOut(organizationID: organization.id, congressID: congress.id)
                    : CalendarAutomaticEventHideKey.congressHotelCheckOut(organizationID: organization.id, congressID: congress.id, hotelID: hotel.id)
                hotelEvents.append(
                    CalendarWorkspaceEvent(
                        id: usesLegacyHotelKey
                            ? "congress-hotel-check-out:\(organization.id):\(congress.id)"
                            : "congress-hotel-check-out:\(organization.id):\(congress.id):\(hotel.id)",
                        source: .congress(organizationID: organization.id, congressID: congress.id),
                        automaticHideKey: hideKey,
                        isHiddenFromCalendar: store.isAutomaticCalendarEventHidden(hideKey),
                        displayDate: displayDate,
                        title: language.text("Hotel check-out", "Hotell utcheckning"),
                        subtitle: title,
                        detail: congressDetail,
                        place: [hotel.hotelName.nonEmpty, congressPlace.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                        timeText: normalizedCalendarTimeInput(hotel.toTime),
                        kind: .accommodation,
                        detailParts: calendarDetailParts([(.congress, congressDetail)]),
                        completedOn: nil,
                        action: {
                            store.openRouteToCongress(organizationID: organization.id, congressID: congress.id)
                        },
                        toggleCompletion: nil
                    )
                )
            }
        }
    }

    return flightEvents + hotelEvents
}

private func calendarDates(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
    guard start <= end else { return [] }
    let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0
    return (0...dayCount).compactMap { offset in
        calendar.date(byAdding: .day, value: offset, to: start).map { calendar.startOfDay(for: $0) }
    }
}

private func uncertainCalendarTimeText(_ raw: String, uncertain: Bool) -> String? {
    let normalized = normalizedCalendarTimeInput(raw).trimmedOrNil
    guard let normalized else { return nil }
    return uncertain ? "\(normalized)?" : normalized
}

func timeRangeText(start: String, end: String, startUncertain: Bool = false, endUncertain: Bool = false) -> String {
    let normalizedStart = uncertainCalendarTimeText(start, uncertain: startUncertain)
    let normalizedEnd = uncertainCalendarTimeText(end, uncertain: endUncertain)
    switch (normalizedStart, normalizedEnd) {
    case let (start?, end?):
        return "\(start)–\(end)"
    case let (start?, nil):
        return start
    case let (nil, end?):
        return end
    case (nil, nil):
        return ""
    }
}

private func calendarTravelCongressDetail(
    travel: CalendarTravelRecord,
    organizationsByID: [String: OrganizationRecord],
    language: AppLanguage
) -> String? {
    guard let organization = organizationsByID[travel.congressOrganizationID],
          let congress = organization.congresses.first(where: { $0.id == travel.congressID }) else {
        return nil
    }
    let title = congress.title.nonEmpty ?? organization.displayName(for: language)
    return "\(language.text("Congress", "Kongress")): \(title)"
}

private func calendarAccommodationCongressDetail(
    accommodation: CalendarAccommodationRecord,
    organizationsByID: [String: OrganizationRecord],
    language: AppLanguage
) -> String? {
    guard let organization = organizationsByID[accommodation.congressOrganizationID],
          let congress = organization.congresses.first(where: { $0.id == accommodation.congressID }) else {
        return nil
    }
    let title = congress.title.nonEmpty ?? organization.displayName(for: language)
    return "\(language.text("Congress", "Kongress")): \(title)"
}

private func calendarFlagEmoji(for countryName: String) -> String? {
    let trimmed = GrantParsing.canonicalCountryName(countryName).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.caseInsensitiveCompare("Somaliland") == .orderedSame {
        return somalilandFlagToken
    }

    let explicitCodes: [String: String] = [
        "Sweden": "SE", "Sverige": "SE",
        "United Kingdom": "GB", "UK": "GB", "U.K.": "GB", "England": "GB", "Storbritannien": "GB",
        "Norway": "NO", "Norge": "NO",
        "Denmark": "DK", "Danmark": "DK",
        "Finland": "FI",
        "Germany": "DE", "Tyskland": "DE",
        "France": "FR", "Frankrike": "FR",
        "Netherlands": "NL", "Nederländerna": "NL",
        "Belgium": "BE", "Belgien": "BE",
        "Switzerland": "CH", "Schweiz": "CH",
        "Austria": "AT", "Österrike": "AT",
        "Italy": "IT", "Italien": "IT",
        "Spain": "ES", "Spanien": "ES",
        "Australia": "AU", "Australien": "AU",
        "United States": "US", "USA": "US", "Förenta staterna": "US"
    ]

    let uppercased = trimmed.uppercased()
    let regionCode =
        (uppercased.count == 2 ? uppercased : nil)
        ?? explicitCodes[trimmed]
        ?? Locale.Region.isoRegions.first(where: {
            let english = Locale(identifier: "en_US").localizedString(forRegionCode: $0.identifier)
            let swedish = Locale(identifier: "sv_SE").localizedString(forRegionCode: $0.identifier)
            return english == trimmed || swedish == trimmed
        })?.identifier

    guard let regionCode else { return nil }
    return regionCode
        .unicodeScalars
        .compactMap { UnicodeScalar(127397 + $0.value) }
        .map(String.init)
        .joined()
}

private func localizedCalendarCountry(_ countryName: String, language: AppLanguage) -> String? {
    let canonical = GrantParsing.canonicalCountryName(countryName).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !canonical.isEmpty else { return nil }
    if GrantParsing.countryOptions.contains(canonical) {
        return language.localizedCountry(canonical)
    }
    return canonical
}

private func normalizedCalendarLocationKeyComponent(_ raw: String?) -> String? {
    raw?
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sv_SE"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .nonEmpty
}

private func calendarDayLocationKey(city: String, country: String, countryDisplayMode: CalendarCountryDisplayMode) -> String {
    let normalizedCity = normalizedCalendarLocationKeyComponent(city)
    let normalizedCountry = normalizedCalendarLocationKeyComponent(GrantParsing.canonicalCountryName(country))
    switch countryDisplayMode {
    case .hidden:
        return normalizedCity ?? ""
    case .text, .flags:
        return [normalizedCity, normalizedCountry].compactMap { $0 }.joined(separator: "|")
    }
}

func formattedCalendarPlace(
    city: String,
    country: String,
    language: AppLanguage,
    countryDisplayMode: CalendarCountryDisplayMode
) -> String {
    let resolvedCity = city.trimmedOrNil
    let resolvedCountry: String?
    switch countryDisplayMode {
    case .text:
        resolvedCountry = localizedCalendarCountry(country, language: language)
    case .flags:
        resolvedCountry = calendarFlagEmoji(for: country)
    case .hidden:
        resolvedCountry = nil
    }

    switch (resolvedCity, resolvedCountry) {
    case let (city?, country?):
        if countryDisplayMode == .text {
            return "\(city), \(country)"
        }
        return "\(city) \(country)"
    case let (city?, nil):
        return city
    case let (nil, country?):
        return country
    case (nil, nil):
        return ""
    }
}

private func calendarDayLocation(
    city: String,
    country: String,
    language: AppLanguage,
    countryDisplayMode: CalendarCountryDisplayMode
) -> CalendarDayLocation? {
    let label = formattedCalendarPlace(
        city: city,
        country: country,
        language: language,
        countryDisplayMode: countryDisplayMode
    )
    let key = calendarDayLocationKey(city: city, country: country, countryDisplayMode: countryDisplayMode)
    guard let resolvedLabel = label.nonEmpty,
          let resolvedKey = key.nonEmpty else {
        return nil
    }
    return CalendarDayLocation(key: resolvedKey, label: resolvedLabel)
}

private func displayCalendarPlaceText(_ raw: String) -> String {
    let withoutSomalilandToken = raw.replacingOccurrences(of: somalilandFlagToken, with: "")
    let withoutFlags = String(
        String.UnicodeScalarView(
            withoutSomalilandToken.unicodeScalars.filter { !(127462...127487 ~= $0.value) }
        )
    )
    return withoutFlags
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func calendarLookupByID<Record: Identifiable>(_ records: [Record]) -> [Record.ID: Record] {
    records.reduce(into: [Record.ID: Record]()) { result, record in
        if result[record.id] == nil {
            result[record.id] = record
        }
    }
}

struct CalendarWorkspaceView: View {
    let store: GrantDataStore
    let isActive: Bool

    init(store: GrantDataStore, isActive: Bool) {
        self.store = store
        self.isActive = isActive

        let calendar = footprintCalendar(for: store.language, weekStart: store.calendarWeekdayChoice)
        let today = calendar.startOfDay(for: Date())
        let initialTopVisibleDate = calendarDefaultOpenDate(today: today, calendar: calendar)
        let initialVerticalScrollOffset: CGFloat = 0

        _topVisibleDate = State(initialValue: initialTopVisibleDate)
        _lastFocusedCalendarDate = State(initialValue: initialTopVisibleDate)
        _verticalScrollOffset = State(initialValue: initialVerticalScrollOffset)
        _pendingPersistedScrollOffset = State(initialValue: nil)
        _pendingPersistedViewportRestore = State(initialValue: false)
        _isStabilizingDefaultOpen = State(initialValue: true)
        _visibleCalendarColumns = State(initialValue: Self.initialVisibleCalendarColumns(hiddenColumnKeys: store.calendarHiddenColumnKeys))
        _visibleCalendarMarkerColumns = State(initialValue: Self.initialVisibleCalendarMarkerColumns(hiddenColumnKeys: store.calendarHiddenColumnKeys))
        _hiddenCalendarRowDetailKinds = State(initialValue: Self.initialHiddenCalendarRowDetailKinds(hiddenColumnKeys: store.calendarHiddenColumnKeys))
    }

    /// The "Visa i raden" choices are stored with the hidden columns, each
    /// as "rowDetail.<part>". Everything shows by default.
    private static func initialHiddenCalendarRowDetailKinds(hiddenColumnKeys: Set<String>) -> Set<CalendarListDetailKind> {
        Set(CalendarListDetailKind.allCases.filter { hiddenColumnKeys.contains($0.hiddenStorageKey) })
    }

    private static func initialVisibleCalendarColumns(hiddenColumnKeys: Set<String>) -> Set<CalendarWorkspaceColumn> {
        let hiddenColumns = Set(hiddenColumnKeys.compactMap(CalendarWorkspaceColumn.init(rawValue:)))
        let visibleColumns = Set(CalendarWorkspaceColumn.allCases.filter { !hiddenColumns.contains($0) })
        return visibleColumns.isEmpty ? Set(CalendarWorkspaceColumn.allCases) : visibleColumns
    }

    private static func initialVisibleCalendarMarkerColumns(hiddenColumnKeys: Set<String>) -> Set<CalendarWorkspaceMarkerColumn> {
        let hiddenColumns = Set(hiddenColumnKeys.compactMap(CalendarWorkspaceMarkerColumn.init(rawValue:)))
        return Set(CalendarWorkspaceMarkerColumn.allCases.filter { !hiddenColumns.contains($0) })
    }

    @State private var presentedSheet: CalendarWorkspaceSheet?
    @State private var presentedCopyRequest: CalendarEventCopyRequest?
    @State private var presentedEventDetail: CalendarEventDetailSelection?
    @State private var pendingDeletionEventID: String?
    @State private var selectedKinds: Set<CalendarWorkspaceEventKind> = Set([
        .taskDeadline,
        .congress,
        .applicationDeadline,
        .travel,
        .accommodation,
        .meeting
    ])
    @State private var selectedMeetingCategoryKeys: Set<String> = []
    @State private var knownMeetingCategoryFilterKeys: Set<String> = []
    @State private var includeEmptyDays = true
    @State private var showsCalendarHistory = true
    @State private var showsHiddenCalendarEvents = false
    @State private var calendarSearchText = ""
    @State private var isCalendarFilterSidebarVisible = true
    @State private var visibleCalendarColumns: Set<CalendarWorkspaceColumn> = Set(CalendarWorkspaceColumn.allCases)
    @State private var visibleCalendarMarkerColumns: Set<CalendarWorkspaceMarkerColumn> = Set(CalendarWorkspaceMarkerColumn.allCases)
    /// The row parts turned off under "Visa i raden" (participants,
    /// organisation, publication and so on).
    @State private var hiddenCalendarRowDetailKinds: Set<CalendarListDetailKind> = []
    @State private var selectedProjectID: String = ""
    @State private var selectedResearcherName: String = ""
    @State private var selectedDayLocation: String = ""
    @State private var expandedProjectDayID: String?
    @State private var cache = CalendarWorkspaceCache()
    @State private var cacheSignature: CalendarWorkspaceCacheSignature?
    @State private var eventSourceIndex = CalendarWorkspaceEventSourceIndex.empty(today: Date())
    @State private var eventSourceIndexSignature: CalendarWorkspaceEventSourceIndexSignature?
    @State private var eventSourceIndexEnvironment: Int?
    @State private var derivedDataSignature: CalendarWorkspaceDerivedDataSignature?
    @State private var filterMetadataSignature: CalendarWorkspaceDerivedDataSignature?
    @State private var cachedProjectFilterOptions: [(id: String, label: String)] = []
    @State private var cachedResearcherFilterOptions: [String] = []
    @State private var cachedDayLocationFilterOptions: [(String, String)] = []
    @State private var cachedMeetingCategoryFilterOptions: [CalendarMeetingCategoryFilterOption] = []
    @State private var derivedData = CalendarWorkspaceDerivedData()
    @State private var visibleWindowSnapshot = CalendarVisibleWindowSnapshot.empty
    @State private var renderedDateWindow: CalendarRenderedDateWindow?
    @State private var topVisibleDate: Date
    @State private var lastFocusedCalendarDate: Date
    @State private var verticalScrollOffset: CGFloat
    @State private var lastObservedVerticalScrollOffset: CGFloat?
    @State private var hasUserScrolledRenderedCalendarWindow = false
    @State private var lastRenderedWindowExpansionAt: CFAbsoluteTime = 0
    @State private var visibleDayPositions: [CalendarDayPosition] = []
    @State private var pendingVisibleDayPositions: [CalendarDayPosition]?
    @State private var pendingVisibleDayPositionTask: DispatchWorkItem?
    @State private var lastVisibleDayPositionPublishAt: CFAbsoluteTime = 0
    @State private var lastVisibleDayPositionSignature = ""
    @State private var verticalScrollRestoreToken = 0
    @State private var didInitialLoad = false
    @State private var pendingDefaultOpenDate: Date?
    @State private var pendingRebuildTask: DispatchWorkItem?
    @State private var currentTimeMarkerDate: Date = Date()
    @State private var lastPeriodicCalendarCheckDate: Date = Date.distantPast
    @State private var pendingPersistedScrollOffset: CGFloat?
    @State private var pendingPersistedViewportRestore: Bool
    @State private var isStabilizingDefaultOpen: Bool
    @State private var isRestoringCalendarFocus = true
    @State private var pendingDataChangeViewportRestore: CalendarViewportRestoreSnapshot?
    @State private var pendingSidebarViewportRestore: CalendarViewportRestoreSnapshot?
    @State private var pendingResizeViewportRestore: CalendarViewportRestoreSnapshot?
    @State private var pendingResizeViewportRestoreTask: DispatchWorkItem?
    @State private var isGoToDatePopoverPresented = false
    @State private var goToDateText = ""
    @State private var goToDateYear: Int = Calendar.current.component(.year, from: Date())
    @State private var pinnedCalendarNavigationDate: Date?
    @State private var pendingTargetedCalendarScroll: PendingCalendarTargetedScroll?
    @State private var highlightedCalendarEventSource: CalendarWorkspaceEventSource?
    @State private var calendarRevealPulseToken: UUID?
    /// F44: content signals of the current main-thread turn, refreshed once.
    @State private var pendingCalendarContentRefresh: CalendarPendingContentRefresh?
    /// List or week view, remembered on this Mac like the congress map's
    /// view settings (kept out of the data file on purpose).
    @AppStorage(AppRuntime.scopedDefaultsKey("CalendarWorkspaceViewMode"))
    private var calendarViewMode: CalendarWorkspaceViewMode = .list
    /// The day whose week the week view shows; nil follows the list's top day.
    @State private var calendarWeekAnchorDate: Date?
    @State private var calendarWeekModel: CalendarWeekViewModel?
    @State private var calendarWeekModelSignature: Int?
    @State private var calendarWeekWindowRequestKey: String?
    /// Bumped each time the filtered day groups are rebuilt.
    @State private var calendarDerivedDataRevision = 0
    /// Settings > Calendar > Working hours, kept in step with the store
    /// while the week view is shown.
    @State private var calendarWeekWorkingHours = CalendarWorkingHoursSettings.standard

    private let listHorizontalPadding: CGFloat = 22
    private let calendarFilterSidebarWidth: CGFloat = 244
    private let calendarHeaderScrollAlignmentInset: CGFloat = 14
    private let currentTimeRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let periodicCalendarCheckInterval: TimeInterval = 15 * 60
    private let targetedCalendarScrollMaximumAttempts = 10
    private let targetedCalendarScrollMaximumCommitAttempts = 8

    private var language: AppLanguage { store.language }
    private var visibleCalendarColumnList: [CalendarWorkspaceColumn] {
        CalendarWorkspaceColumn.allCases.filter { visibleCalendarColumns.contains($0) }
    }
    /// Weekday and date share one column ("Fre 2 okt") when both are on.
    private var calendarMergesDayAndDate: Bool {
        visibleCalendarColumns.contains(.weekday) && visibleCalendarColumns.contains(.date)
    }
    private var calendarShowsCompletionRing: Bool {
        visibleCalendarColumns.contains(.completion)
    }
    private var calendarShowsDetailLine: Bool {
        visibleCalendarColumns.contains(.details)
    }
    /// The day column that carries the small "Idag" tag.
    private var calendarTodayTagColumn: CalendarWorkspaceColumn? {
        if visibleCalendarColumns.contains(.date) { return .date }
        if visibleCalendarColumns.contains(.weekday) { return .weekday }
        return nil
    }
    /// The columns the list draws. The details sit under the title, so
    /// Detaljer has no column of its own; its setting still decides whether
    /// the detail line shows. Klar is its own narrow column between Rubrik
    /// and Plats.
    private var calendarLayoutColumnList: [CalendarWorkspaceColumn] {
        let mergesDayAndDate = calendarMergesDayAndDate
        let showsTitleColumn = visibleCalendarColumns.contains(.title) || calendarShowsDetailLine
        return CalendarWorkspaceColumn.allCases.filter { column in
            switch column {
            case .weekday:
                return visibleCalendarColumns.contains(.weekday) && !mergesDayAndDate
            case .title:
                return showsTitleColumn
            case .completion:
                return calendarShowsCompletionRing
            case .details:
                return false
            default:
                return visibleCalendarColumns.contains(column)
            }
        }
    }
    private func calendarLayoutWidth(for column: CalendarWorkspaceColumn) -> CGFloat {
        switch column {
        case .date where calendarMergesDayAndDate:
            return 136
        case .date, .weekday:
            return column.width + (calendarTodayTagColumn == column ? 44 : 0)
        case .title:
            return calendarShowsDetailLine ? CalendarWorkspaceColumn.details.width : column.width
        default:
            return column.width
        }
    }
    /// Cells sit at the top of the row so a title with a detail line under
    /// it does not push the other columns down to its middle.
    private func calendarLayoutGridItem(for column: CalendarWorkspaceColumn) -> GridItem {
        let width = calendarLayoutWidth(for: column)
        if column == .title {
            return GridItem(.flexible(minimum: width), spacing: column.trailingSpacing, alignment: .topLeading)
        }
        if column == .completion {
            return GridItem(.fixed(width), spacing: column.trailingSpacing, alignment: .top)
        }
        return GridItem(.fixed(width), spacing: column.trailingSpacing, alignment: .topLeading)
    }
    private func calendarLayoutColumnTitle(_ column: CalendarWorkspaceColumn) -> String {
        switch column {
        case .title where !visibleCalendarColumns.contains(.title):
            return CalendarWorkspaceColumn.details.title(language: language)
        default:
            return column.title(language: language)
        }
    }
    private var visibleCompactGrid: [GridItem] {
        calendarLayoutColumnList.map { calendarLayoutGridItem(for: $0) }
    }
    private var calendarGridContentWidth: CGFloat {
        calendarLayoutColumnList.reduce(CGFloat(0)) { width, column in
            width + calendarLayoutWidth(for: column) + column.trailingSpacing
        }
    }
    private var calendarContentMinimumWidth: CGFloat {
        listHorizontalPadding * 2
            + calendarGridContentWidth
            + calendarRowLeadingPadding
            + calendarRowTrailingPadding
    }
    /// Room at the row's left edge for the category colour strip.
    private let calendarRowLeadingPadding: CGFloat = 16
    private let calendarRowTrailingPadding: CGFloat = 12

    private var workspaceCalendar: Calendar {
        footprintCalendar(for: language, weekStart: store.calendarWeekdayChoice)
    }
    private var weekNumberCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = workspaceCalendar.locale
        return calendar
    }
    private var today: Date { workspaceCalendar.startOfDay(for: currentTimeMarkerDate) }
    private var defaultOpenDate: Date {
        calendarDefaultOpenDate(today: today, calendar: workspaceCalendar)
    }
    private var todayGroupID: String {
        DateParsers.isoDay.string(from: today)
    }
    private var meetingCategoryFilterOptions: [CalendarMeetingCategoryFilterOption] {
        derivedData.meetingCategoryFilterOptions
    }
    private var defaultSelectedKinds: Set<CalendarWorkspaceEventKind> {
        [.travel, .accommodation, .meeting, .taskDeadline, .applicationDeadline, .congress]
    }
    private var defaultMeetingCategoryFilterKeys: Set<String> {
        Set(meetingCategoryFilterOptions.map(\.id))
    }
    private var totalSelectedEventCategoryFilterCount: Int {
        selectedKinds.subtracting([.meeting]).count + selectedMeetingCategoryKeys.count
    }
    private var filterStateKey: String {
        let kinds = selectedKinds
            .map(\.filterStorageKey)
            .sorted()
            .joined(separator: ",")
        let meetingCategories = selectedMeetingCategoryKeys
            .sorted()
            .joined(separator: ",")
        return "\(kinds)|\(meetingCategories)|\(includeEmptyDays)|\(showsCalendarHistory)|\(showsHiddenCalendarEvents)|\(calendarSearchText)|\(selectedProjectID)|\(selectedResearcherName)|\(selectedDayLocation)"
    }
    private var hasActiveCalendarFilters: Bool {
        return selectedKinds != defaultSelectedKinds
            || selectedMeetingCategoryKeys != defaultMeetingCategoryFilterKeys
            || !includeEmptyDays
            || !showsCalendarHistory
            || showsHiddenCalendarEvents
            || calendarSearchText.trimmedOrNil != nil
            || selectedProjectID.trimmedOrNil != nil
            || selectedResearcherName.trimmedOrNil != nil
            || selectedDayLocation.trimmedOrNil != nil
    }
    private var projectFilterOptions: [(id: String, label: String)] {
        derivedData.projectFilterOptions
    }
    private var researcherFilterOptions: [String] {
        derivedData.researcherFilterOptions
    }

    private var dayLocationFilterOptions: [(String, String)] {
        derivedData.dayLocationFilterOptions
    }

    private func offsetBeforeCalendarColumn(_ targetColumn: CalendarWorkspaceColumn) -> CGFloat {
        var offset: CGFloat = 0
        for column in calendarLayoutColumnList {
            guard column != targetColumn else { return offset }
            offset += calendarLayoutWidth(for: column) + column.trailingSpacing
        }
        return 0
    }

    private func centerBetweenCalendarColumns(
        _ leftColumn: CalendarWorkspaceColumn,
        and rightColumn: CalendarWorkspaceColumn
    ) -> CGFloat? {
        guard visibleCalendarColumns.contains(leftColumn),
              visibleCalendarColumns.contains(rightColumn) else {
            return nil
        }
        return calendarRowLeadingPadding + offsetBeforeCalendarColumn(rightColumn) - leftColumn.trailingSpacing / 2
    }

    private func persistCalendarColumnVisibility(
        _ visibleColumns: Set<CalendarWorkspaceColumn>,
        markerColumns visibleMarkerColumns: Set<CalendarWorkspaceMarkerColumn>? = nil,
        hiddenRowDetailKinds: Set<CalendarListDetailKind>? = nil
    ) {
        let markerColumns = visibleMarkerColumns ?? visibleCalendarMarkerColumns
        let hiddenDetailKinds = hiddenRowDetailKinds ?? hiddenCalendarRowDetailKinds
        let hiddenKeys = Set(CalendarWorkspaceColumn.allCases.filter { !visibleColumns.contains($0) }.map(\.rawValue))
            .union(CalendarWorkspaceMarkerColumn.allCases.filter { !markerColumns.contains($0) }.map(\.rawValue))
            .union(hiddenDetailKinds.map(\.hiddenStorageKey))
        store.autosaveCalendarHiddenColumnKeys(hiddenKeys)
    }

    var body: some View {
        Group {
            if !isActive {
                Color.clear
                    .onAppear {
                        guard renderedDateWindow == nil else { return }
                        currentTimeMarkerDate = Date()
                        lastPeriodicCalendarCheckDate = currentTimeMarkerDate
                        resetRenderedDateWindow(centeredOn: defaultOpenDate)
                        scheduleCalendarCacheRebuild(skipIfUnchanged: true, delay: 0.75, scope: .visibleWindow)
                    }
            } else {
                calendarContent(dayGroups: derivedData.dayGroups)
            }
        }
        // Keep the deactivation observer outside the conditional content. An
        // observer attached to calendarContent disappears in the same render
        // pass that replaces the calendar with Color.clear, so it is not a
        // reliable place to capture the final viewport.
        .onChange(of: isActive) { _, active in
            guard !active else { return }
            deactivateCalendarWorkspace()
        }
    }

    private func calendarContent(dayGroups: [CalendarWorkspaceDayGroup]) -> some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                calendarFilterSidebar()
                    .layoutPriority(2)

                GeometryReader { calendarGeometry in
                    let contentWidth = max(calendarGeometry.size.width, calendarContentMinimumWidth)
                    ZStack(alignment: .topTrailing) {
                        if calendarViewMode == .week {
                            calendarWeekContent()
                                .frame(width: calendarGeometry.size.width, height: calendarGeometry.size.height, alignment: .topLeading)
                        } else {
                            ScrollView(.horizontal) {
                                VStack(spacing: 0) {
                                    stickyCalendarToolbar()

                                    ZStack(alignment: .topLeading) {
                                        ScrollView(.vertical) {
                                            CalendarVerticalScrollOffsetBridge(
                                                offsetY: $verticalScrollOffset,
                                                restoreToken: verticalScrollRestoreToken
                                            )
                                            .frame(height: 0)

                                            LazyVStack(alignment: .leading, spacing: 0) {
                                                ForEach(dayGroups) { group in
                                                    VStack(alignment: .leading, spacing: 0) {
                                                        if group.startsWeek {
                                                            calendarWeekHeaderRow(for: group)
                                                        }
                                                        // The position reader measures the day
                                                        // itself, not the week header above it.
                                                        dayGroupCard(group)
                                                            .background(dayPositionReader(for: group.date))
                                                    }
                                                    .id(group.id)
                                                    .padding(.top, group.topSpacing)
                                                }
                                            }
                                            .padding(.horizontal, listHorizontalPadding)
                                            .padding(.top, 6)
                                            .padding(.bottom, 28)
                                        }
                                        .coordinateSpace(name: "CalendarListSpace")
                                        .onPreferenceChange(CalendarDayPositionPreferenceKey.self) { positions in
                                            handleCalendarDayPositionsChange(
                                                normalizedDayPositions(positions),
                                                using: proxy
                                            )
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    }
                                    .background(AppPalette.calendarWorkspaceSurface)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                }
                                .background(AppPalette.calendarWorkspaceSurface)
                                .frame(width: contentWidth, height: calendarGeometry.size.height, alignment: .topLeading)
                            }
                            .background(AppPalette.calendarWorkspaceSurface)
                            .frame(width: calendarGeometry.size.width, height: calendarGeometry.size.height, alignment: .topLeading)
                            .clipped()
                        }

                        floatingCalendarJumpControls(proxy: proxy)
                    }
                    .background(AppPalette.calendarWorkspaceSurface)
                    .frame(width: calendarGeometry.size.width, height: calendarGeometry.size.height, alignment: .topLeading)
                    .onChange(of: calendarGeometry.size) { oldSize, newSize in
                        handleCalendarViewportResize(from: oldSize, to: newSize, using: proxy)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AppPalette.calendarWorkspaceSurface)
                // Round 17: while a filter is on, the calendar says so above
                // the days, also when the filter panel is collapsed.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let calendarFilterSummaryText {
                        AppActiveFiltersBanner(
                            summary: calendarFilterSummaryText,
                            language: language,
                            clearAction: resetFilters
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppPalette.calendarWorkspaceSurface)
                    }
                }
                .layoutPriority(0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sheet(item: $presentedSheet) { sheet in
                switch sheet.kind {
                case .todo:
                    CalendarTodoSheet(store: store, taskID: sheet.recordID, initialDateString: sheet.initialDateString)
                case .travel:
                    CalendarTravelSheet(store: store, travelID: sheet.recordID, initialDateString: sheet.initialDateString)
                case .accommodation:
                    CalendarAccommodationSheet(store: store, accommodationID: sheet.recordID, initialDateString: sheet.initialDateString)
                case let .congressFlight(organizationID, congressID, flightID):
                    CalendarTravelSheet(
                        store: store,
                        travelID: nil,
                        congressFlightContext: CalendarCongressFlightEditContext(
                            organizationID: organizationID,
                            congressID: congressID,
                            flightID: flightID
                        )
                    )
                case .meeting:
                    CalendarMeetingSheet(store: store, meetingID: sheet.recordID, initialDateString: sheet.initialDateString)
                case let .projectTask(projectID):
                    CalendarProjectTaskSheet(store: store, projectID: projectID, taskID: sheet.recordID)
                case let .publicationTask(publicationID):
                    CalendarPublicationTaskSheet(store: store, publicationID: publicationID, taskID: sheet.recordID)
                }
            }
            .sheet(item: $presentedCopyRequest) { request in
                CalendarEventCopySheet(language: language, request: request) { updatedRequest in
                    duplicateEvent(for: updatedRequest)
                }
            }
            .sheet(item: $presentedEventDetail) { selection in
                if let event = calendarEvent(for: selection.eventID) {
                    calendarEventDetailSheet(for: event)
                } else {
                    FootprintDialogFrame(
                        title: language.text("Calendar event", "Kalenderhändelse"),
                        subtitle: language.text("This event is no longer available.", "Den här händelsen finns inte längre."),
                        closeAction: { presentedEventDetail = nil }
                    ) {
                        EmptyView()
                    } footer: {
                        Button(language.text("Close", "Stäng")) {
                            presentedEventDetail = nil
                        }
                    }
                    .frame(width: 520)
                }
            }
            .confirmationDialog(
                language.text("Delete calendar event?", "Ta bort kalenderhändelse?"),
                isPresented: Binding(
                    get: { pendingDeletionEventID != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDeletionEventID = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(language.text("Delete", "Ta bort"), role: .destructive) {
                    guard let eventID = pendingDeletionEventID,
                          let event = calendarEvent(for: eventID) else {
                        pendingDeletionEventID = nil
                        return
                    }
                    pendingDeletionEventID = nil
                    deleteEvent(source: event.source)
                }
                Button(language.text("Cancel", "Avbryt"), role: .cancel) {
                    pendingDeletionEventID = nil
                }
            } message: {
                Text(language.text(
                    "The event will be removed. You can undo this action from the Edit menu.",
                    "Händelsen tas bort. Du kan ångra åtgärden från menyn Redigera."
                ))
            }
            .onReceive(currentTimeRefreshTimer) { newValue in
                currentTimeMarkerDate = newValue
                rebuildCalendarCacheAfterPeriodicCheckIfNeeded(at: newValue)
            }
            .onChange(of: verticalScrollOffset) { oldValue, newValue in
                handleCalendarVerticalScrollOffsetChange(from: oldValue, to: newValue)
            }
            .onAppear {
                if didInitialLoad {
                    reactivateCalendarWorkspace(using: proxy)
                    return
                }
                didInitialLoad = true
                isStabilizingDefaultOpen = true
                hasUserScrolledRenderedCalendarWindow = false
                currentTimeMarkerDate = Date()
                lastPeriodicCalendarCheckDate = currentTimeMarkerDate
                resetRenderedDateWindow(centeredOn: defaultOpenDate)
                let hasPrewarmedCache = !cache.allDates.isEmpty
                scheduleCalendarCacheRebuild(
                    skipIfUnchanged: hasPrewarmedCache,
                    delay: hasPrewarmedCache ? 0.03 : 0.12,
                    scope: .visibleWindow
                ) {
                    applyPendingCalendarOpenRequestIfNeeded()
                    if !applyPendingCalendarRevealRequestIfNeeded(using: proxy, animated: false),
                       !pendingPersistedViewportRestore {
                        requestDefaultCalendarOpenIfNeeded(using: proxy, animated: false)
                    }
                }
            }
            // onReceive, not onChange: the subscription delivers every bump
            // even when the body does not re-evaluate around the mutation
            // (the stale-list class of bug). The generations bump after
            // their underlying data is committed, so reading the store
            // synchronously here is safe.
            //
            // F44: one calendar edit sends two signals in the same turn: the
            // generation bump from the metadata change, then the update that
            // names the edited record. Each used to rebuild the calendar, the
            // first one rebuilding every source. Both are now collected and
            // handled by a single rebuild at the end of the turn, which can
            // then update just the named record.
            .onReceive(store.$calendarContentGeneration.dropFirst()) { _ in
                guard isActive || cache.allDates.isEmpty else { return }
                enqueueCalendarContentRefresh(update: nil, using: proxy)
            }
            .onReceive(store.$calendarContentUpdate.dropFirst()) { update in
                guard isActive, let update else { return }
                enqueueCalendarContentRefresh(update: update, using: proxy)
            }
            .onReceive(
                store.$metadata.map(\.calendarCountryDisplayMode).removeDuplicates().dropFirst()
            ) { _ in
                selectedDayLocation = ""
            }
            .onChange(of: store.pendingCalendarOpenRequest) { _, _ in
                applyPendingCalendarOpenRequestIfNeeded()
            }
            .onChange(of: store.pendingCalendarRevealToken) { _, token in
                guard token != nil else { return }
                presentedSheet = nil
                presentedCopyRequest = nil
                presentedEventDetail = nil
            }
            .onChange(of: store.pendingCalendarRevealRequest) { _, _ in
                _ = applyPendingCalendarRevealRequestIfNeeded(using: proxy, animated: true)
            }
            .onChange(of: derivedData.dayGroups.map(\.id)) { _, _ in
                if attemptTargetedCalendarScrollIfNeeded(using: proxy) {
                    return
                }
                if !restorePersistedCalendarViewportIfNeeded(using: proxy) {
                    if !restoreCalendarViewportAfterDataChangeIfNeeded(using: proxy) {
                        applyPendingDefaultCalendarOpenIfNeeded(using: proxy)
                    }
                }
            }
            .onChange(of: filterStateKey) { _, _ in
                guard pendingTargetedCalendarScroll == nil else {
                    rebuildCalendarDataForFilterChange()
                    _ = attemptTargetedCalendarScrollIfNeeded(using: proxy)
                    return
                }
                let preferredDate = calendarPreferredDateForFilterChange(
                    topVisibleDate: topVisibleDate,
                    defaultOpenDate: defaultOpenDate,
                    pendingDefaultOpenDate: pendingDefaultOpenDate,
                    isStabilizingDefaultOpen: isStabilizingDefaultOpen,
                    calendar: workspaceCalendar
                )
                rebuildCalendarDataForFilterChange()
                DispatchQueue.main.async {
                    guard calendarShouldPreserveViewportAfterFilterChange(
                        hasPendingTargetedScroll: pendingTargetedCalendarScroll != nil
                    ) else {
                        return
                    }
                    preserveVisibleDate(using: proxy, preferredDate: preferredDate)
                }
            }
            .onChange(of: isCalendarFilterSidebarVisible) { _, _ in
                restoreCalendarViewportAfterSidebarChangeIfNeeded()
            }
            .onChange(of: verticalScrollOffset) { _, newValue in
                guard pendingTargetedCalendarScroll == nil else { return }
                guard pendingResizeViewportRestore == nil else { return }
                guard calendarShouldPersistViewportSnapshot(
                    verticalScrollOffset: newValue,
                    topVisibleDate: topVisibleDate,
                    today: today,
                    pendingOpenRequest: store.pendingCalendarOpenRequest,
                    pendingRevealRequest: store.pendingCalendarRevealRequest,
                    pendingDefaultOpenDate: pendingDefaultOpenDate,
                    pendingPersistedViewportRestore: pendingPersistedViewportRestore,
                    calendar: workspaceCalendar
                ) else { return }
                store.calendarWorkspaceViewportSnapshot.verticalScrollOffset = newValue
            }
            .onChange(of: topVisibleDate) { _, newValue in
                guard pendingTargetedCalendarScroll == nil else { return }
                guard pendingResizeViewportRestore == nil else { return }
                guard calendarShouldPersistViewportSnapshot(
                    verticalScrollOffset: verticalScrollOffset,
                    topVisibleDate: newValue,
                    today: today,
                    pendingOpenRequest: store.pendingCalendarOpenRequest,
                    pendingRevealRequest: store.pendingCalendarRevealRequest,
                    pendingDefaultOpenDate: pendingDefaultOpenDate,
                    pendingPersistedViewportRestore: pendingPersistedViewportRestore,
                    calendar: workspaceCalendar
                ) else { return }
                store.calendarWorkspaceViewportSnapshot.topVisibleDayString = DateParsers.isoDay.string(
                    from: workspaceCalendar.startOfDay(for: newValue)
                )
            }
            .onDisappear {
                cancelPendingVisibleDayPositionPublish()
            }
        }
    }

    private func calendarEvent(for eventID: String) -> CalendarWorkspaceEvent? {
        cache.events.first(where: { $0.id == eventID })
    }

    private func presentCalendarEventDetail(_ event: CalendarWorkspaceEvent) {
        presentedEventDetail = CalendarEventDetailSelection(eventID: event.id)
    }

    private func calendarEventDetailSheet(for event: CalendarWorkspaceEvent) -> some View {
        let categoryTitle = eventCategoryTitle(for: event)
        let action = eventTapAction(for: event)
        let copyRequest = copyRequest(for: event)
        let deleteAction = deleteAction(for: event)

        return FootprintDialogFrame(
            title: event.title,
            subtitle: calendarEventDateLine(for: event, categoryTitle: categoryTitle),
            closeAction: { presentedEventDetail = nil }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 126), spacing: 8, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    FootprintMetadataChip(title: categoryTitle, systemImage: calendarEventIconName(for: event))
                    if let timeText = event.timeText.nonEmpty {
                        FootprintMetadataChip(title: timeText, systemImage: "clock")
                    }
                    // Round 16: status facts are passive labels, not selected (clickable-looking) chips.
                    if event.isRolledOverPastDue {
                        FootprintMetadataChip(title: language.text("Overdue", "Försenad"), systemImage: "exclamationmark.triangle")
                    }
                    if event.isDateUncertain {
                        FootprintMetadataChip(title: language.text("Uncertain date", "Osäkert datum"), systemImage: "questionmark.circle")
                    }
                    if event.isHiddenFromCalendar {
                        FootprintMetadataChip(title: language.text("Hidden from calendar", "Gömd från kalendern"), systemImage: "eye.slash")
                    }
                    if event.isCompleted {
                        FootprintMetadataChip(title: language.text("Completed", "Klar"), systemImage: "checkmark.circle")
                    }
                    if let place = event.place.nonEmpty {
                        FootprintMetadataChip(title: place, systemImage: "mappin.and.ellipse")
                    }
                }

                calendarEventDetailBlock(title: language.text("Linked records", "Länkade poster")) {
                    calendarEventRelationshipChips(for: event)
                }

                if detailText(for: event).nonEmpty != nil || !detailRecordLinks(for: event).isEmpty {
                    calendarEventDetailBlock(title: language.text("Details", "Detaljer")) {
                        calendarEventDetailTextView(
                            detailLinkPresentation(for: event),
                            color: detailTextColor(for: event),
                            recordLinks: detailRecordLinks(for: event)
                        )
                    }
                }

                if let subtitle = event.subtitle.nonEmpty, subtitle != event.title {
                    calendarEventDetailBlock(title: language.text("Context", "Sammanhang")) {
                        Text(subtitle)
                            .calendarTypography(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } footer: {
            if deleteAction != nil {
                Button(role: .destructive) {
                    presentedEventDetail = nil
                    requestCalendarEventDeletion(event)
                } label: {
                    Label(language.text("Delete", "Ta bort"), systemImage: "trash")
                }
                .appDeleteButtonStyle()
            }
            if let copyRequest {
                Button(language.text("Copy", "Kopiera")) {
                    presentedEventDetail = nil
                    presentedCopyRequest = copyRequest
                }
            }
            if let hideKey = event.automaticHideKey {
                Button(event.isHiddenFromCalendar ? language.text("✓ Hidden from calendar", "✓ Gömd från kalendern") : language.text("Hidden from calendar", "Gömd från kalendern")) {
                    presentedEventDetail = nil
                    store.setAutomaticCalendarEventHidden(hideKey, hidden: !event.isHiddenFromCalendar)
                }
            }
            if let action {
                Button {
                    presentedEventDetail = nil
                    DispatchQueue.main.async {
                        action()
                    }
                } label: {
                    Label(calendarEventPrimaryActionTitle(for: event), systemImage: calendarEventPrimaryActionIcon(for: event))
                }
                .appSaveButtonStyle()
            }
            Button(language.text("Close", "Stäng")) {
                presentedEventDetail = nil
            }
        }
        .frame(width: 640)
    }

    private func calendarEventDetailBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .calendarTypography(.fieldLabel)
                .foregroundStyle(AppPalette.appText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calendarEventDetailTextView(
        _ presentation: CalendarDetailLinkPresentation,
        color: Color,
        recordLinks: [CalendarDetailRecordLink] = []
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !presentation.visibleText.isEmpty {
                Text(presentation.visibleText)
                    .calendarTypography(.body)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !recordLinks.isEmpty {
                HStack(spacing: 8) {
                    ForEach(recordLinks) { link in
                        calendarDetailRecordLinkButton(link, compact: false)
                    }
                }
            }
            if !presentation.urls.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(presentation.urls.enumerated()), id: \.offset) { _, url in
                        calendarDetailLinkButton(url, compact: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func calendarDetailLinkButton(_ url: URL, compact: Bool) -> some View {
        if compact {
            // In the list rows the link buttons are grey so they don't
            // compete with the text, and show what they open.
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                calendarRowLinkIcon(.web)
            }
            .buttonStyle(.plain)
            .help(language.text("Open link", "Öppna länk"))
            .accessibilityLabel(language.text("Open link", "Öppna länk"))
        } else {
            // The detail sheet keeps the link colour.
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                AppLinkDestinationLabel(
                    kind: .web,
                    language: language,
                    fontSize: 13,
                    tint: AppPalette.linkAction,
                    showsTitle: false
                )
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(language.text("Open link", "Öppna länk"))
        }
    }

    @ViewBuilder
    private func calendarDetailRecordLinkButton(_ link: CalendarDetailRecordLink, compact: Bool) -> some View {
        if compact {
            Button {
                openDetailRecordLink(link)
            } label: {
                calendarRowLinkIcon(link.linkTarget)
            }
            .buttonStyle(.plain)
            .help(link.title)
            .accessibilityLabel(link.title)
        } else {
            Button {
                openDetailRecordLink(link)
            } label: {
                AppLinkDestinationLabel(
                    kind: .app,
                    language: language,
                    fontSize: 13,
                    tint: AppPalette.linkAction,
                    showsTitle: false
                )
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(link.title)
        }
    }

    /// A list row's link button: the symbol of the page it opens (a folder
    /// for a project, a book for a publication, a link for a web address),
    /// in grey.
    private func calendarRowLinkIcon(_ target: CalendarListLinkTarget) -> some View {
        Image(systemName: calendarListLinkSymbolName(for: target))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.secondary)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }

    private func calendarInlineDetailRecordLinkButton(
        _ link: CalendarDetailRecordLink,
        compact: Bool,
        italic: Bool,
        typography: AppTypographyRole = .body
    ) -> some View {
        Button {
            openDetailRecordLink(link)
        } label: {
            Text(link.title)
                .calendarTypography(typography)
                .modifier(CalendarItalicTextModifier(isItalic: italic))
                .foregroundStyle(AppPalette.linkAction)
                .lineLimit(compact ? 2 : nil)
                .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(link.title)
    }

    private func calendarEventDateLine(for event: CalendarWorkspaceEvent, categoryTitle: String) -> String {
        let day = "\(weekdayText(for: event.displayDate)), \(dateText(for: event.displayDate))"
        return [categoryTitle, day, event.timeText.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func calendarEventPrimaryActionTitle(for event: CalendarWorkspaceEvent) -> String {
        switch event.source {
        case .projectTask, .publicationTask, .teachingTask, .meeting, .travel:
            return language.text("Edit", "Redigera")
        default:
            return language.text("Open linked record", "Öppna länkad post")
        }
    }

    private func calendarEventPrimaryActionIcon(for event: CalendarWorkspaceEvent) -> String {
        switch event.source {
        case .projectTask, .publicationTask, .teachingTask, .meeting, .travel:
            return "pencil"
        default:
            return "arrow.up.forward.square"
        }
    }

    private func calendarEventIconName(for kind: CalendarWorkspaceEventKind) -> String {
        switch kind {
        case .holiday:
            return "flag"
        case .congress:
            return AppTab.congresses.symbolName
        case .travel:
            return "airplane"
        case .accommodation:
            return "bed.double"
        case .meeting:
            return "calendar.badge.clock"
        case .applicationDeadline:
            return "doc.text"
        case .taskDeadline:
            return "checklist"
        }
    }

    private func calendarEventIconName(for event: CalendarWorkspaceEvent) -> String {
        if event.kind == .travel, let travelMode = event.travelMode {
            return travelMode.calendarSystemImageName
        }
        if event.kind == .meeting {
            return calendarMeetingCategoryIconName(place: event.place)
        }
        return calendarEventIconName(for: event.kind)
    }

    @ViewBuilder
    private func calendarEventRelationshipChips(for event: CalendarWorkspaceEvent) -> some View {
        let projectReferences = projectReferences(for: event)
        let organizationReferences = organizationReferences(for: event)
        let applicationReferences = applicationReferences(for: event)
        let publicationReferences = publicationReferences(for: event)
        let teachingAssignmentReferences = teachingAssignmentReferences(for: event)
        let researcherReferences = researcherReferences(for: event)
        let hasRelationships = !projectReferences.isEmpty
            || !organizationReferences.isEmpty
            || !applicationReferences.isEmpty
            || !publicationReferences.isEmpty
            || !teachingAssignmentReferences.isEmpty
            || !researcherReferences.isEmpty

        if hasRelationships {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 135), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(projectReferences, id: \.id) { project in
                    FootprintMetadataChip(title: project.label, systemImage: "folder") {
                        store.route = AppRoute(recordID: project.id, destination: .projects)
                    }
                }
                ForEach(organizationReferences, id: \.id) { organization in
                    FootprintMetadataChip(title: organization.label, systemImage: AppTab.organizations.symbolName) {
                        store.route = AppRoute(recordID: organization.id, destination: .organizations)
                    }
                }
                ForEach(applicationReferences, id: \.id) { application in
                    FootprintMetadataChip(title: application.label, systemImage: "doc.text") {
                        store.route = AppRoute(recordID: application.id, destination: .applications)
                    }
                }
                ForEach(publicationReferences, id: \.id) { publication in
                    FootprintMetadataChip(title: publication.label, systemImage: "text.book.closed") {
                        store.route = AppRoute(recordID: publication.id, destination: .publications)
                    }
                }
                ForEach(teachingAssignmentReferences, id: \.id) { assignment in
                    FootprintMetadataChip(title: assignment.label, systemImage: "graduationcap") {
                        store.route = AppRoute(recordID: assignment.id, destination: .teaching)
                    }
                }
                ForEach(Array(researcherReferences.prefix(12)), id: \.self) { name in
                    if let author = store.publicationAuthor(matchingPresentedName: name) {
                        FootprintMetadataChip(title: author.displayName, systemImage: "person") {
                            store.route = AppRoute(recordID: author.id, destination: .people)
                        }
                    } else {
                        FootprintMetadataChip(title: name, systemImage: "person")
                    }
                }
            }
        } else {
            Text(language.text("No linked records", "Inga länkade poster"))
                .calendarTypography(.secondary)
                .foregroundStyle(.secondary)
        }
    }

    private func stickyCalendarToolbar() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            compactHeaderRow
        }
        .padding(.horizontal, listHorizontalPadding)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .background(AppPalette.calendarHeaderSurface)
        .shadow(
            color: Color.black.opacity(effectiveUsesDarkAppearance ? 0.26 : 0.12),
            radius: 10,
            x: 0,
            y: 4
        )
        .overlay(
            Rectangle()
                .fill(AppPalette.subtleBorder.opacity(effectiveUsesDarkAppearance ? 0.78 : 0.7))
                .frame(height: 1),
            alignment: .bottom
        )
        .zIndex(2)
    }

    private func floatingCalendarJumpControls(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            calendarViewModePicker(proxy: proxy)

            Button {
                prepareGoToDatePopover()
                isGoToDatePopoverPresented.toggle()
            } label: {
                Label(language.text("Go to …", "Gå till …"), systemImage: "calendar")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .popover(isPresented: $isGoToDatePopoverPresented, arrowEdge: .bottom) {
                CalendarGoToDatePopover(
                    language: language,
                    calendar: workspaceCalendar,
                    selectedDate: topVisibleDate,
                    dateText: $goToDateText,
                    displayedYear: $goToDateYear
                ) { date in
                    isGoToDatePopoverPresented = false
                    if calendarViewMode == .week {
                        showCalendarWeek(containing: date)
                    } else {
                        goToCalendarDate(date, using: proxy)
                    }
                }
            }
            .help(language.text("Go to date", "Gå till datum"))

            Button {
                if calendarViewMode == .week {
                    showCalendarWeek(containing: today)
                } else {
                    scrollToToday(using: proxy, animated: true)
                }
            } label: {
                Label(language.text("Today", "Idag"), systemImage: "sun.max")
            }
            .appSaveButtonStyle()
            .controlSize(.regular)
            // ⌘T goes to today in both the list and the week view.
            .keyboardShortcut("t", modifiers: .command)
            .help(language.text("Go to today (⌘T)", "Gå till idag (⌘T)"))
        }
        .padding(.top, 10)
        .padding(.trailing, 14)
        .background(AppPalette.calendarHeaderSurface)
        .shadow(
            color: Color.black.opacity(effectiveUsesDarkAppearance ? 0.28 : 0.16),
            radius: 8,
            x: 0,
            y: 3
        )
        .zIndex(4)
    }

    private var compactHeaderRow: some View {
        LazyVGrid(columns: visibleCompactGrid, alignment: .leading, spacing: 12) {
            ForEach(calendarLayoutColumnList) { column in
                headerCell(
                    calendarLayoutColumnTitle(column),
                    alignment: column == .completion ? .center : .leading
                )
            }
        }
        .padding(.leading, calendarRowLeadingPadding)
        .padding(.trailing, calendarRowTrailingPadding)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(x: calendarHeaderScrollAlignmentInset)
    }

    @ViewBuilder
    private func calendarFilterSidebar() -> some View {
        if isCalendarFilterSidebarVisible {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    AppSidebarSearchField(
                        placeholder: language.text("Search calendar", "Sök i kalendern"),
                        text: $calendarSearchText
                    )

                    HStack(spacing: 10) {
                        Label(language.text("Filters", "Filter"), systemImage: "line.3.horizontal.decrease")
                            .calendarTypography(.panelTitle)
                            .foregroundStyle(AppPalette.appText)
                        Spacer()
                        Button {
                            setCalendarFilterSidebarVisible(false)
                        } label: {
                            Image(systemName: "sidebar.leading")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.borderless)
                        .help(language.text("Hide filters", "Dölj filter"))
                        .accessibilityLabel(language.text("Hide filters", "Dölj filter"))
                    }

                    if let calendarFilterSummaryText {
                        Text(calendarFilterSummaryText)
                            .calendarTypography(.secondary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        AppFilterResetButton(
                            help: language.text("Clear filters", "Rensa filter")
                        ) {
                            resetFilters()
                        }
                        .disabled(!hasActiveCalendarFilters)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    calendarSidebarSection(title: language.text("Add", "Lägg till")) {
                        calendarCreationButtons()
                    }

                    calendarSidebarSection(title: language.text("Event types", "Händelsetyper")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach([
                                CalendarWorkspaceEventKind.travel,
                                .accommodation,
                                .meeting,
                                .taskDeadline,
                                .applicationDeadline,
                                .congress
                            ], id: \.self) { kind in
                                categoryFilterToggle(kind)
                            }
                            Toggle(isOn: $includeEmptyDays) {
                                calendarColoredFilterLabel(
                                    title: language.text("Empty days", "Tomma dagar"),
                                    systemImage: "square.dashed",
                                    color: AppPalette.subtleBorder,
                                    isSelected: includeEmptyDays
                                )
                            }
                            .appCheckboxStyle()
                        }
                    }

                    if !meetingCategoryFilterOptions.isEmpty {
                        calendarSidebarSection(title: language.text("Activity categories", "Aktivitetskategorier")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(meetingCategoryFilterOptions) { option in
                                    meetingCategoryFilterToggle(option)
                                }
                            }
                        }
                    }

                    calendarSidebarSection(title: language.text("Calendar filters", "Kalenderfilter")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $showsCalendarHistory) {
                                Label(language.text("History", "Historik"), systemImage: "clock.arrow.circlepath")
                                    .calendarTypography(.body)
                            }
                            .appCheckboxStyle()
                            .help(language.text("Show past calendar days", "Visa tidigare kalenderdagar"))

                            filterPicker(
                                title: language.text("Project", "Projekt"),
                                selection: $selectedProjectID,
                                options: [("", language.text("All projects", "Alla projekt"))] + projectFilterOptions
                            )

                            filterPicker(
                                title: language.text("Researcher", "Forskare"),
                                selection: $selectedResearcherName,
                                options: [("", language.text("All researchers", "Alla forskare"))] + researcherFilterOptions.map { ("\($0)", $0) }
                            )

                            filterPicker(
                                title: language.text("Your location", "Din plats"),
                                selection: $selectedDayLocation,
                                options: [("", language.text("All locations", "Alla platser"))] + dayLocationFilterOptions
                            )
                        }
                    }

                    calendarSidebarSection(title: language.text("Columns", "Kolumner")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(CalendarWorkspaceMarkerColumn.allCases) { column in
                                calendarMarkerColumnToggle(column)
                            }
                            ForEach(CalendarWorkspaceColumn.allCases) { column in
                                calendarColumnToggle(column)
                            }
                            Button(language.text("Show all columns", "Visa alla kolumner")) {
                                let allColumns = Set(CalendarWorkspaceColumn.allCases)
                                let allMarkerColumns = Set(CalendarWorkspaceMarkerColumn.allCases)
                                let conferencesWereHidden = !visibleCalendarColumns.contains(.conferences)
                                visibleCalendarColumns = allColumns
                                visibleCalendarMarkerColumns = allMarkerColumns
                                persistCalendarColumnVisibility(allColumns, markerColumns: allMarkerColumns)
                                if conferencesWereHidden {
                                    rebuildDerivedCalendarData()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(
                                visibleCalendarColumns.count == CalendarWorkspaceColumn.allCases.count
                                    && visibleCalendarMarkerColumns.count == CalendarWorkspaceMarkerColumn.allCases.count
                            )
                            .padding(.top, 4)
                        }
                    }

                    calendarSidebarSection(title: language.text("Show in row", "Visa i raden")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(CalendarListDetailKind.allCases) { kind in
                                calendarRowDetailToggle(kind)
                            }
                            Button(language.text("Show all", "Visa alla")) {
                                setHiddenCalendarRowDetailKinds([])
                            }
                            .buttonStyle(.bordered)
                            .disabled(hiddenCalendarRowDetailKinds.isEmpty)
                            .padding(.top, 4)
                        }
                    }

                    Divider()

                    Toggle(isOn: $showsHiddenCalendarEvents) {
                        Label(
                            language.text("Show hidden activities", "Visa gömda aktiviteter"),
                            systemImage: "eye"
                        )
                        .calendarTypography(.body)
                    }
                    .appCheckboxStyle()
                    .help(language.text("Show calendar activities hidden from automatic deadlines.", "Visa kalenderaktiviteter som gömts från automatiska deadlines."))
                }
                .padding(14)
                .frame(width: calendarFilterSidebarWidth, alignment: .topLeading)
            }
            .frame(width: calendarFilterSidebarWidth)
            .background(AppPalette.calendarFilterSurface)
            .overlay(
                Rectangle()
                    .fill(AppPalette.subtleBorder)
                    .frame(width: 1),
                alignment: .trailing
            )
            .shadow(
                color: Color.black.opacity(effectiveUsesDarkAppearance ? 0.28 : 0.12),
                radius: 12,
                x: 4,
                y: 0
            )
            .zIndex(2)
            .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            VStack(spacing: 10) {
                Button {
                    setCalendarFilterSidebarVisible(true)
                } label: {
                    Image(systemName: "sidebar.leading")
                        .frame(width: 22, height: 22)
                        // Round 17: a small dot while a filter is on.
                        .overlay(alignment: .topTrailing) {
                            if hasActiveCalendarFilters {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
                .buttonStyle(.borderless)
                .help(hasActiveCalendarFilters
                    ? language.text("Show filters (filters are on)", "Visa filter (filter är på)")
                    : language.text("Show filters", "Visa filter"))
                .accessibilityLabel(hasActiveCalendarFilters
                    ? language.text("Show filters (filters are on)", "Visa filter (filter är på)")
                    : language.text("Show filters", "Visa filter"))

                Text(language.text("Filters", "Filter"))
                    .calendarTypography(.tableHeader)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .frame(width: 28, height: 72)
            }
            .padding(.top, 18)
            .frame(width: 36)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(AppPalette.calendarFilterSurface)
            .overlay(
                Rectangle()
                    .fill(AppPalette.subtleBorder)
                    .frame(width: 1),
                alignment: .trailing
            )
            .shadow(
                color: Color.black.opacity(effectiveUsesDarkAppearance ? 0.28 : 0.12),
                radius: 12,
                x: 4,
                y: 0
            )
            .zIndex(2)
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    private func setCalendarFilterSidebarVisible(_ isVisible: Bool) {
        guard isCalendarFilterSidebarVisible != isVisible else { return }
        pendingSidebarViewportRestore = CalendarViewportRestoreSnapshot(
            verticalScrollOffset: verticalScrollOffset,
            topVisibleDate: workspaceCalendar.startOfDay(for: topVisibleDate)
        )
        isCalendarFilterSidebarVisible = isVisible
    }

    private func restoreCalendarViewportAfterSidebarChangeIfNeeded() {
        guard pendingTargetedCalendarScroll == nil else {
            pendingSidebarViewportRestore = nil
            return
        }
        guard let snapshot = pendingSidebarViewportRestore else { return }
        pendingSidebarViewportRestore = nil

        DispatchQueue.main.async {
            restoreCalendarViewportAfterSidebarChange(snapshot)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            restoreCalendarViewportAfterSidebarChange(snapshot)
        }
    }

    private func restoreCalendarViewportAfterSidebarChange(_ snapshot: CalendarViewportRestoreSnapshot) {
        guard isActive else { return }
        topVisibleDate = snapshot.topVisibleDate
        verticalScrollOffset = snapshot.verticalScrollOffset
        verticalScrollRestoreToken &+= 1
    }

    private func handleCalendarViewportResize(
        from oldSize: CGSize,
        to newSize: CGSize,
        using proxy: ScrollViewProxy
    ) {
        guard pendingTargetedCalendarScroll == nil else { return }
        guard calendarShouldPreserveViewportOnResize(
            oldSize: oldSize,
            newSize: newSize,
            didInitialLoad: didInitialLoad,
            pendingOpenRequest: store.pendingCalendarOpenRequest,
            pendingRevealRequest: store.pendingCalendarRevealRequest,
            pendingDefaultOpenDate: pendingDefaultOpenDate,
            pendingPersistedViewportRestore: pendingPersistedViewportRestore
        ) else { return }

        if pendingResizeViewportRestore == nil {
            pendingResizeViewportRestore = CalendarViewportRestoreSnapshot(
                verticalScrollOffset: verticalScrollOffset,
                topVisibleDate: workspaceCalendar.startOfDay(for: topVisibleDate)
            )
        }

        guard let snapshot = pendingResizeViewportRestore else { return }
        restoreCalendarViewportAfterResize(snapshot, using: proxy)
        pendingResizeViewportRestoreTask?.cancel()
        let task = DispatchWorkItem {
            restoreCalendarViewportAfterResize(snapshot, using: proxy)
            pendingResizeViewportRestore = nil
            pendingResizeViewportRestoreTask = nil
        }
        pendingResizeViewportRestoreTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: task)
    }

    private func restoreCalendarViewportAfterResize(
        _ snapshot: CalendarViewportRestoreSnapshot,
        using proxy: ScrollViewProxy
    ) {
        guard !derivedData.dayGroups.isEmpty else { return }
        preserveVisibleDate(using: proxy, preferredDate: snapshot.topVisibleDate)
    }

    private func calendarSidebarSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .calendarTypography(.fieldLabel)
                .foregroundStyle(AppPalette.appText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calendarCreationButtons() -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible())
            ],
            alignment: .leading,
            spacing: 8
        ) {
            calendarCreationButton(
                title: language.text("Activity", "Aktivitet"),
                systemImage: "calendar.badge.plus",
                kind: .meeting
            )
            calendarCreationButton(
                title: language.text("Task", "Uppgift"),
                systemImage: "checklist",
                kind: .todo
            )
            calendarCreationButton(
                title: language.text("Travel", "Resa"),
                systemImage: "airplane",
                kind: .travel
            )
            calendarCreationButton(
                title: language.text("Accommodation", "Boende"),
                systemImage: "bed.double",
                kind: .accommodation
            )
        }
    }

    private func calendarCreationButton(
        title: String,
        systemImage: String,
        kind: CalendarWorkspaceSheet.Kind
    ) -> some View {
        Button {
            presentedSheet = CalendarWorkspaceSheet(kind: kind, recordID: nil)
        } label: {
            Label(title, systemImage: systemImage)
                .calendarTypography(.tableHeader)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appSaveButtonStyle()
    }

    private var calendarFilterSummaryText: String? {
        if !hasActiveCalendarFilters {
            return nil
        }

        var parts: [String] = []
        if selectedKinds != defaultSelectedKinds || selectedMeetingCategoryKeys != defaultMeetingCategoryFilterKeys {
            parts.append(language.text("\(totalSelectedEventCategoryFilterCount) event filters", "\(totalSelectedEventCategoryFilterCount) händelsefilter"))
        }
        if let search = calendarSearchText.trimmedOrNil {
            parts.append(language.text("search: \(search)", "sökning: \(search)"))
        }
        if selectedProjectID.nonEmpty != nil {
            parts.append(language.text("project", "projekt"))
        }
        if selectedResearcherName.nonEmpty != nil {
            parts.append(language.text("researcher", "forskare"))
        }
        if selectedDayLocation.nonEmpty != nil {
            parts.append(language.text("location", "plats"))
        }
        if !includeEmptyDays {
            parts.append(language.text("empty days hidden", "tomma dagar dolda"))
        }
        if !showsCalendarHistory {
            parts.append(language.text("future only", "bara framtid"))
        }
        if showsHiddenCalendarEvents {
            parts.append(language.text("hidden activities shown", "gömda aktiviteter visas"))
        }
        return parts.isEmpty ? language.text("Custom calendar filters are active.", "Anpassade kalenderfilter är aktiva.") : language.text(
            "Active filters: \(parts.joined(separator: ", "))",
            "Aktiva filter: \(parts.joined(separator: ", "))"
        )
    }

    private func categoryFilterToggle(_ kind: CalendarWorkspaceEventKind) -> some View {
        Toggle(
            isOn: Binding(
                get: { selectedKinds.contains(kind) },
                set: { isSelected in
                    setEventTypeFilter(kind, selected: isSelected)
                }
            )
        ) {
            calendarColoredFilterLabel(
                title: kind.filterTitle(language: language),
                systemImage: calendarEventIconName(for: kind),
                color: eventRowAccentColor(for: kind),
                isSelected: selectedKinds.contains(kind)
            )
        }
        .appCheckboxStyle()
        .disabled(selectedKinds.contains(kind) && totalSelectedEventCategoryFilterCount <= 1)
        .contextMenu {
            Button(language.text("Show only this", "Visa endast denna")) {
                showOnlyCategory(kind)
            }
        }
    }

    private func setEventTypeFilter(_ kind: CalendarWorkspaceEventKind, selected isSelected: Bool) {
        if kind == .meeting {
            if isSelected {
                selectedKinds.insert(.meeting)
                selectedMeetingCategoryKeys = defaultMeetingCategoryFilterKeys
                knownMeetingCategoryFilterKeys = defaultMeetingCategoryFilterKeys
            } else if totalSelectedEventCategoryFilterCount > 1 {
                selectedKinds.remove(.meeting)
                selectedMeetingCategoryKeys = []
            }
            return
        }

        if isSelected {
            selectedKinds.insert(kind)
        } else if totalSelectedEventCategoryFilterCount > 1 {
            selectedKinds.remove(kind)
        }
    }

    private func meetingCategoryFilterToggle(_ option: CalendarMeetingCategoryFilterOption) -> some View {
        Toggle(
            isOn: Binding(
                get: { selectedMeetingCategoryKeys.contains(option.id) },
                set: { isSelected in
                    if isSelected {
                        selectedKinds.insert(.meeting)
                        selectedMeetingCategoryKeys.insert(option.id)
                    } else if totalSelectedEventCategoryFilterCount > 1 {
                        selectedMeetingCategoryKeys.remove(option.id)
                        if selectedMeetingCategoryKeys.isEmpty {
                            selectedKinds.remove(.meeting)
                        }
                    }
                }
            )
        ) {
            calendarColoredFilterLabel(
                title: option.title,
                systemImage: "tag",
                color: configuredMeetingCategoryColor(named: option.rawName),
                isSelected: selectedMeetingCategoryKeys.contains(option.id)
            )
        }
        .appCheckboxStyle()
        .disabled(selectedMeetingCategoryKeys.contains(option.id) && totalSelectedEventCategoryFilterCount <= 1)
        .contextMenu {
            Button(language.text("Show only this", "Visa endast denna")) {
                showOnlyMeetingCategory(option)
            }
        }
    }

    private func calendarColoredFilterLabel(
        title: String,
        systemImage: String,
        color: Color,
        isSelected: Bool
    ) -> some View {
        Label {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
        }
        .calendarTypography(.body)
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(isSelected ? 0.26 : 0.11))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(color.opacity(isSelected ? 0.78 : 0.38), lineWidth: 1)
        )
        .opacity(isSelected ? 1 : 0.66)
    }

    private func calendarColumnToggle(_ column: CalendarWorkspaceColumn) -> some View {
        Toggle(
            isOn: Binding(
                get: { visibleCalendarColumns.contains(column) },
                set: { isVisible in
                    var nextVisibleColumns = visibleCalendarColumns
                    if isVisible {
                        nextVisibleColumns.insert(column)
                    } else if nextVisibleColumns.count > 1 {
                        nextVisibleColumns.remove(column)
                    }
                    guard nextVisibleColumns != visibleCalendarColumns else { return }
                    visibleCalendarColumns = nextVisibleColumns
                    persistCalendarColumnVisibility(nextVisibleColumns)
                    if column == .conferences {
                        // Congresses move between their column and the rows.
                        rebuildDerivedCalendarData()
                    }
                }
            )
        ) {
            Text(column.title(language: language))
                .calendarTypography(.body)
        }
        .appCheckboxStyle()
        .disabled(visibleCalendarColumns.contains(column) && visibleCalendarColumns.count <= 1)
    }

    private func calendarMarkerColumnToggle(_ column: CalendarWorkspaceMarkerColumn) -> some View {
        Toggle(
            isOn: Binding(
                get: { visibleCalendarMarkerColumns.contains(column) },
                set: { isVisible in
                    var nextVisibleMarkerColumns = visibleCalendarMarkerColumns
                    if isVisible {
                        nextVisibleMarkerColumns.insert(column)
                    } else {
                        nextVisibleMarkerColumns.remove(column)
                    }
                    guard nextVisibleMarkerColumns != visibleCalendarMarkerColumns else { return }
                    visibleCalendarMarkerColumns = nextVisibleMarkerColumns
                    persistCalendarColumnVisibility(visibleCalendarColumns, markerColumns: nextVisibleMarkerColumns)
                }
            )
        ) {
            Text(column.title(language: language))
                .calendarTypography(.body)
        }
        .appCheckboxStyle()
    }

    /// A "Visa i raden" checkbox: shows or hides one part of the rows
    /// (participants, organisation, publication and so on), both its text
    /// and its link buttons.
    private func calendarRowDetailToggle(_ kind: CalendarListDetailKind) -> some View {
        Toggle(
            isOn: Binding(
                get: { !hiddenCalendarRowDetailKinds.contains(kind) },
                set: { isVisible in
                    var nextHiddenKinds = hiddenCalendarRowDetailKinds
                    if isVisible {
                        nextHiddenKinds.remove(kind)
                    } else {
                        nextHiddenKinds.insert(kind)
                    }
                    setHiddenCalendarRowDetailKinds(nextHiddenKinds)
                }
            )
        ) {
            Text(kind.title(language: language))
                .calendarTypography(.body)
        }
        .appCheckboxStyle()
    }

    private func setHiddenCalendarRowDetailKinds(_ hiddenKinds: Set<CalendarListDetailKind>) {
        guard hiddenKinds != hiddenCalendarRowDetailKinds else { return }
        hiddenCalendarRowDetailKinds = hiddenKinds
        persistCalendarColumnVisibility(visibleCalendarColumns, hiddenRowDetailKinds: hiddenKinds)
        rebuildCalendarListDetailCache(hiddenKinds: hiddenKinds)
    }

    private func categoryChip(_ kind: CalendarWorkspaceEventKind) -> some View {
        let isSelected = selectedKinds.contains(kind)
        return Button {
            setEventTypeFilter(kind, selected: !isSelected)
        } label: {
            Label(kind.filterTitle(language: language), systemImage: calendarEventIconName(for: kind))
                .calendarTypography(.body)
                .foregroundStyle(isSelected ? AppPalette.semanticOnColor : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? eventRowAccentColor(for: kind).opacity(0.92) : AppPalette.secondaryCardSurface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? eventRowAccentColor(for: kind).opacity(0.92) : AppPalette.subtleBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(language.text("Show only this", "Visa endast denna")) {
                showOnlyCategory(kind)
            }
        }
    }

    private func meetingCategoryChip(_ option: CalendarMeetingCategoryFilterOption) -> some View {
        let isSelected = selectedMeetingCategoryKeys.contains(option.id)
        return Button {
            if isSelected, totalSelectedEventCategoryFilterCount > 1 {
                selectedMeetingCategoryKeys.remove(option.id)
                if selectedMeetingCategoryKeys.isEmpty {
                    selectedKinds.remove(.meeting)
                }
            } else {
                selectedKinds.insert(.meeting)
                selectedMeetingCategoryKeys.insert(option.id)
            }
        } label: {
            Label(option.title, systemImage: "tag")
                .calendarTypography(.body)
                .foregroundStyle(isSelected ? AppPalette.semanticOnColor : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? configuredMeetingCategoryColor(named: option.rawName).opacity(0.92) : AppPalette.secondaryCardSurface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? configuredMeetingCategoryColor(named: option.rawName).opacity(0.92) : AppPalette.subtleBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(language.text("Show only this", "Visa endast denna")) {
                showOnlyMeetingCategory(option)
            }
        }
    }

    private var emptyDayChip: some View {
        Button {
            includeEmptyDays.toggle()
        } label: {
            Label(language.text("Empty days", "Tomma dagar"), systemImage: "square.dashed")
                .calendarTypography(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(includeEmptyDays ? AppPalette.subtleBorder.opacity(0.45) : AppPalette.fieldSurface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(includeEmptyDays ? AppPalette.activeTabSurface : AppPalette.subtleBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func filterPicker(
        title _: String,
        selection: Binding<String>,
        options: [(String, String)]
    ) -> some View {
        let selectedIndex = options.firstIndex(where: { $0.0 == selection.wrappedValue }) ?? 0
        let selectedLabel = options.indices.contains(selectedIndex) ? options[selectedIndex].1 : ""
        return ZStack(alignment: .leading) {
            HStack(spacing: 8) {
                calendarMenuOptionLabel(selectedLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: AppPalette.fieldMinHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                .fill(AppPalette.secondaryCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                .stroke(AppPalette.subtleBorder.opacity(0.72), lineWidth: 1)
        )
        .overlay {
            CalendarFilterPopupField(
                labels: options.map(\.1),
                selectedIndex: selectedIndex,
                onSelect: { index in
                    guard options.indices.contains(index) else { return }
                    selection.wrappedValue = options[index].0
                }
            )
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .help(calendarMenuPlainTitle(selectedLabel))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func calendarMenuOptionLabel(_ text: String) -> some View {
        if text.contains(somalilandFlagToken) {
            HStack(alignment: .center, spacing: 4) {
                let segments = text.components(separatedBy: somalilandFlagToken)
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Text(segment)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if index < segments.count - 1 {
                        somalilandFlagView
                    }
                }
            }
        } else {
            Text(text)
        }
    }

    private func dayGroupCard(_ group: CalendarWorkspaceDayGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if group.events.isEmpty {
                emptyDayRow(group: group)
            } else {
                ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                    compactEventRow(
                        event,
                        group: group,
                        showsDateColumns: index == 0
                    )
                }
            }
        }
        // Calm rows: one plain surface per day, a clear 1 pt line between
        // days and no lines between the rows of a day. Today is marked in the
        // day column, not with an outline round the whole day.
        .background(Rectangle().fill(dayGroupFill(for: group)))
        .overlay(alignment: .top) {
            if !group.startsWeek {
                Rectangle()
                    .fill(AppPalette.border)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            guard !hovering, expandedProjectDayID == group.id else { return }
            expandedProjectDayID = nil
        }
        .contextMenu {
            dayCreationContextMenu(for: group.date)
        }
    }

    /// The faint band at the start of each week:
    /// "Vecka 40 · 28 sep – 4 okt 2026". It replaces the old vertical
    /// week and year text in the left margin.
    private func calendarWeekHeaderRow(for group: CalendarWorkspaceDayGroup) -> some View {
        Text(calendarWeekHeaderText(for: group))
            .font(calendarWeekHeaderFont())
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.leading, calendarRowLeadingPadding)
            .padding(.trailing, calendarRowTrailingPadding)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Rectangle()
                    .fill(AppPalette.appText.opacity(effectiveUsesDarkAppearance ? 0.07 : 0.045))
            )
            .accessibilityAddTraits(.isHeader)
    }

    private func calendarWeekHeaderText(for group: CalendarWorkspaceDayGroup) -> String {
        // The same week rule that decides where a new week starts in the list.
        let calendar = weekNumberCalendar
        let start = calendar.dateInterval(of: .weekOfYear, for: group.date)?.start ?? group.date
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let startParts = calendar.dateComponents([.day, .month, .year], from: start)
        let endParts = calendar.dateComponents([.day, .month, .year], from: end)
        let weekNumber: Int? = visibleCalendarMarkerColumns.contains(.weekNumber)
            ? calendar.component(.weekOfYear, from: group.date)
            : nil
        return calendarListWeekHeaderLabel(
            weekNumber: weekNumber,
            startDay: startParts.day ?? 1,
            startMonth: startParts.month ?? 1,
            startYear: startParts.year ?? 0,
            endDay: endParts.day ?? 1,
            endMonth: endParts.month ?? 1,
            endYear: endParts.year ?? 0,
            showsYear: visibleCalendarMarkerColumns.contains(.year),
            language: language
        )
    }

    private func dayPositionReader(for date: Date) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("CalendarListSpace"))
            Color.clear.preference(
                key: CalendarDayPositionPreferenceKey.self,
                value: [
                    CalendarDayPosition(
                        date: workspaceCalendar.startOfDay(for: date),
                        minY: frame.minY,
                        maxY: frame.maxY
                    )
                ]
            )
        }
    }

    private func presentNewCalendarSheet(_ kind: CalendarWorkspaceSheet.Kind, on date: Date) {
        presentedSheet = CalendarWorkspaceSheet(
            kind: kind,
            recordID: nil,
            initialDateString: DateParsers.isoDay.string(from: workspaceCalendar.startOfDay(for: date))
        )
    }

    @ViewBuilder
    private func dayCreationContextMenu(for date: Date) -> some View {
        Button(language.text("Add task", "Lägg till uppgift")) {
            presentNewCalendarSheet(.todo, on: date)
        }
        Button(language.text("Add travel", "Lägg till resa")) {
            presentNewCalendarSheet(.travel, on: date)
        }
        Button(language.text("Add activity", "Lägg till aktivitet")) {
            presentNewCalendarSheet(.meeting, on: date)
        }
    }

    private func emptyDayRow(group: CalendarWorkspaceDayGroup) -> some View {
        LazyVGrid(columns: visibleCompactGrid, alignment: .leading, spacing: 12) {
            ForEach(calendarLayoutColumnList) { column in
                emptyDayColumn(column, group: group)
            }
        }
        .padding(.leading, calendarRowLeadingPadding)
        .padding(.trailing, calendarRowTrailingPadding)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func emptyDayColumn(_ column: CalendarWorkspaceColumn, group: CalendarWorkspaceDayGroup) -> some View {
        switch column {
        case .weekday, .date:
            calendarDayCell(column, group: group, showsDateColumns: true)
        case .time, .category, .project, .title, .completion, .details, .place:
            rowCell("")
        case .dayLocation:
            placeCell(group.dayEndLocation, foreground: dayForegroundColor(for: group, base: .primary))
        case .conferences:
            conferenceCell(for: group, showsDateColumns: true)
        }
    }

    private func compactEventRow(
        _ event: CalendarWorkspaceEvent,
        group: CalendarWorkspaceDayGroup,
        showsDateColumns: Bool,
        usesSubtleDateColumns: Bool = false
    ) -> some View {
        let usesItalicStyle = eventUsesItalicStyle(event)
        let textColor = eventBodyTextColor(for: event)
        return LazyVGrid(columns: visibleCompactGrid, alignment: .leading, spacing: 12) {
            ForEach(calendarLayoutColumnList) { column in
                eventColumn(
                    column,
                    event: event,
                    group: group,
                    showsDateColumns: showsDateColumns,
                    usesSubtleDateColumns: usesSubtleDateColumns,
                    usesItalicStyle: usesItalicStyle,
                    textColor: textColor
                )
            }
        }
        .padding(.leading, calendarRowLeadingPadding)
        .padding(.trailing, calendarRowTrailingPadding)
        .padding(.vertical, 5)
        .background(alignment: .leading) {
            eventCategoryStrip(for: event, group: group)
        }
        .undoRevealPulse(
            triggerID: eventRevealPulseTriggerID(for: event),
            isActive: eventRevealPulseIsActive(for: event),
            cornerRadius: 10
        )
        .contentShape(Rectangle())
        .contextMenu {
            calendarEventContextMenu(for: event, on: group.date)
        }
    }

    /// The category colour as a solid strip down the row's left edge – the
    /// same strip other lists use for status – instead of a colour wash over
    /// the category cell. Follows the Kategori column setting.
    @ViewBuilder
    private func eventCategoryStrip(for event: CalendarWorkspaceEvent, group: CalendarWorkspaceDayGroup) -> some View {
        if visibleCalendarColumns.contains(.category) {
            StatusIndicatorListRowBackground(
                fill: eventRowHighlightColor(for: event)
                    .opacity(eventForegroundOpacity(for: event, group: group))
            )
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func calendarEventContextMenu(for event: CalendarWorkspaceEvent, on date: Date) -> some View {
        let primaryAction = eventTapAction(for: event)
        let copyRequest = copyRequest(for: event)
        let deleteAction = deleteAction(for: event)
        let hasEventActions = primaryAction != nil
            || event.automaticHideKey != nil
            || copyRequest != nil
            || deleteAction != nil

        if let primaryAction {
            Button(calendarEventPrimaryActionTitle(for: event)) {
                primaryAction()
            }
        }
        if event.automaticHideKey != nil {
            calendarAutomaticVisibilityContextMenuItem(for: event)
        }
        if let taskBadgeID = calendarTaskReminderID(for: event.source) {
            Button(store.isCalendarTaskBadgeHidden(taskBadgeID) ? language.text("Show badge", "Visa badge") : language.text("Hide badge", "Dölj badge")) {
                store.setCalendarTaskBadgeHidden(taskBadgeID, hidden: !store.isCalendarTaskBadgeHidden(taskBadgeID))
            }
        }
        if let copyRequest {
            Button(language.text("Copy", "Kopiera")) {
                presentedCopyRequest = copyRequest
            }
        }
        if deleteAction != nil {
            Button(language.text("Delete", "Ta bort"), role: .destructive) {
                requestCalendarEventDeletion(event)
            }
        }
        if hasEventActions {
            Divider()
        }
        dayCreationContextMenu(for: date)
    }

    @ViewBuilder
    private func eventColumn(
        _ column: CalendarWorkspaceColumn,
        event: CalendarWorkspaceEvent,
        group: CalendarWorkspaceDayGroup,
        showsDateColumns: Bool,
        usesSubtleDateColumns: Bool,
        usesItalicStyle: Bool,
        textColor: Color
    ) -> some View {
        switch column {
        case .weekday, .date:
            calendarDayCell(
                column,
                group: group,
                showsDateColumns: showsDateColumns,
                isRepeated: usesSubtleDateColumns
            )
        case .time:
            eventTimeCell(event, group: group, textColor: textColor)
        case .category:
            eventCategoryCell(event, group: group, italic: usesItalicStyle)
        case .project:
            projectCell(for: event, group: group)
        case .title:
            eventTitleCell(event, group: group)
        case .completion:
            eventCompletionCell(event, group: group)
        case .details:
            // Never laid out: the details sit under the title.
            EmptyView()
        case .place:
            placeCell(
                event.place,
                italic: usesItalicStyle,
                foreground: eventForegroundColor(for: event, group: group, base: eventBodyTextColor(for: event))
            )
        case .dayLocation:
            placeCell(group.dayEndLocation, foreground: dayForegroundColor(for: group, base: .primary))
        case .conferences:
            conferenceCell(for: group, showsDateColumns: showsDateColumns)
        }
    }

    /// The time column: only the time (a task shows its deadline time).
    private func eventTimeCell(
        _ event: CalendarWorkspaceEvent,
        group: CalendarWorkspaceDayGroup,
        textColor: Color
    ) -> some View {
        let timeText = event.timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Text(timeText)
            .calendarTypography(.body)
            .monospacedDigit()
            .foregroundStyle(timeText.isEmpty ? Color.clear : eventForegroundColor(for: event, group: group, base: textColor))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The narrow Klar column between Rubrik and Plats: the ring for rows
    /// that can be ticked off, empty for the others.
    @ViewBuilder
    private func eventCompletionCell(_ event: CalendarWorkspaceEvent, group: CalendarWorkspaceDayGroup) -> some View {
        if event.toggleCompletion != nil {
            completionToggle(for: event, group: group)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Color.clear
                .frame(width: 20, height: 18)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHidden(true)
        }
    }

    private func completionToggle(for event: CalendarWorkspaceEvent, group: CalendarWorkspaceDayGroup) -> some View {
        Button {
            event.toggleCompletion?(!event.isCompleted)
        } label: {
            Image(systemName: completionIconName(for: event))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(eventForegroundColor(for: event, group: group, base: completionTint(for: event)))
                .frame(width: 20, height: 18)
                .overlay {
                    if eventNeedsAttentionRing(event) {
                        Circle()
                            .stroke(Color(nsColor: .systemRed), lineWidth: 2)
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(event.isRolledOverPastDue ? language.text("Overdue", "Försenad") : "")
        .accessibilityLabel(
            event.isCompleted
                ? language.text("Mark as not done", "Markera som inte klar")
                : language.text("Mark as done", "Markera som klar")
        )
    }

    private func calendarListRowDetail(for event: CalendarWorkspaceEvent) -> CalendarListRowDetail {
        // Parts turned off under "Visa i raden" are left out of the text
        // (already in the cached line) and of the link buttons.
        let hiddenKinds = hiddenCalendarRowDetailKinds
        let presentation = listDetailLinkPresentation(for: event)
        let congressLink = hiddenKinds.contains(.congress) ? nil : congressDetailRecordLink(for: event)
        let visibleText = detailTextByRemovingInlineRecordLink(
            presentation.visibleText,
            linkTitle: congressLink?.title
        )
        let recordLinks = detailRecordLinks(for: event).filter { !hiddenKinds.contains($0.detailKind) }
        let helpText = [
            presentation.visibleText.nonEmpty,
            recordLinks.map(\.title).joined(separator: "\n").nonEmpty
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        .nonEmpty ?? language.text("Open link", "Öppna länk")
        return CalendarListRowDetail(
            visibleText: visibleText,
            congressLink: congressLink,
            recordLinks: recordLinks,
            urls: presentation.urls,
            helpText: helpText
        )
    }

    /// The small grey link arrows for a row's details.
    @ViewBuilder
    private func calendarRowDetailLinkButtons(_ detail: CalendarListRowDetail) -> some View {
        ForEach(detail.recordLinks) { link in
            calendarDetailRecordLinkButton(link, compact: true)
        }
        ForEach(Array(detail.urls.enumerated()), id: \.offset) { _, url in
            calendarDetailLinkButton(url, compact: true)
        }
    }

    private func detailTextByRemovingInlineRecordLink(_ text: String, linkTitle: String?) -> String {
        guard let linkTitle,
              text.hasPrefix(linkTitle) else {
            return text
        }
        var remaining = String(text.dropFirst(linkTitle.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if remaining.hasPrefix("·") {
            remaining = String(remaining.dropFirst())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return remaining
    }

    /// The weekday and date columns. With both on they share one column
    /// ("Fre 2 okt", semibold) on the day's first row. Today is blue with a
    /// small "Idag" tag; weekends and holidays get red date text.
    @ViewBuilder
    private func calendarDayCell(
        _ column: CalendarWorkspaceColumn,
        group: CalendarWorkspaceDayGroup,
        showsDateColumns: Bool,
        isRepeated: Bool = false
    ) -> some View {
        if showsDateColumns {
            let isToday = group.id == todayGroupID
            let isMerged = column == .date && calendarMergesDayAndDate
            let label: String = isMerged
                ? calendarShortDayLabel(for: group.date)
                : (column == .weekday ? group.weekdayLabel : group.dateLabel)
            let baseColor: Color = isToday ? Color(nsColor: .systemBlue) : dateAccentTextColor(for: group)
            HStack(spacing: 6) {
                Text(label)
                    .font(isMerged ? calendarAppFont(.body).weight(.semibold) : calendarAppFont(.body))
                    .foregroundStyle(dayForegroundColor(for: group, base: baseColor))
                    .opacity(isRepeated ? 0.5 : 1)
                    .lineLimit(1)
                if isToday, !isRepeated, calendarTodayTagColumn == column {
                    calendarTodayTag
                }
                if column == .date, !group.holidays.isEmpty, !isRepeated {
                    holidayDotView(holidays: group.holidays)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            rowCell("")
        }
    }

    private func calendarShortDayLabel(for date: Date) -> String {
        let parts = workspaceCalendar.dateComponents([.weekday, .day, .month], from: date)
        return calendarListShortDayLabel(
            weekday: parts.weekday ?? 1,
            day: parts.day ?? 1,
            month: parts.month ?? 1,
            language: language
        )
    }

    private var calendarTodayTag: some View {
        Text(language.text("Today", "Idag"))
            .font(calendarAppFont(.secondary).weight(.semibold))
            .foregroundStyle(Color(nsColor: .systemBlue))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .systemBlue).opacity(0.14))
            )
            .fixedSize()
    }

    /// Category icon and name in normal text colour; the colour itself is
    /// the strip at the row's left edge. Online and in-person meetings have
    /// different icons.
    private func eventCategoryCell(
        _ event: CalendarWorkspaceEvent,
        group: CalendarWorkspaceDayGroup,
        italic: Bool
    ) -> some View {
        let foreground = eventForegroundColor(for: event, group: group, base: .primary)
        let onlineText: String? = event.kind == .meeting && calendarPlaceIsOnline(event.place)
            ? language.text("Online", "Online")
            : nil
        return HStack(spacing: 7) {
            Image(systemName: calendarEventIconName(for: event))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 16)
                .help(onlineText ?? "")
                .accessibilityLabel(onlineText ?? "")
                .accessibilityHidden(onlineText == nil)
            Text(eventCategoryTitle(for: event))
                .calendarTypography(.body)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .modifier(CalendarItalicTextModifier(isItalic: italic))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func holidayDotView(holidays: [HolidayDefinition]) -> some View {
        let colors = resolvedCalendarDayHighlightColors(for: .holiday)
        return HolidayDotStack(
            holidays: holidays,
            language: language,
            textColor: colors.text,
            backgroundColor: colors.background
        )
    }

    private func isStandaloneCongressEvent(_ event: CalendarWorkspaceEvent) -> Bool {
        if case .congress = event.source {
            return event.kind == .congress
        }
        return false
    }

    private func isCongressDeadlineEvent(_ event: CalendarWorkspaceEvent) -> Bool {
        if case .congress = event.source {
            return event.kind == .applicationDeadline
        }
        return false
    }

    private func eventCategoryTitle(for event: CalendarWorkspaceEvent) -> String {
        if let categoryName = event.meetingCategoryName {
            return calendarMeetingCategoryDisplayName(categoryName, language: language)
        }
        switch event.source {
        case let .meeting(meetingID):
            return calendarMeetingCategoryDisplayName(
                cache.meetingRecordsByID[meetingID]?.meetingType ?? "",
                language: language
            )
        case .congress:
            if isCongressDeadlineEvent(event) {
                return event.detail
            }
            return event.kind.title(language: language)
        default:
            return event.kind.title(language: language)
        }
    }

    private func configuredCalendarColor(hex: String?, fallback: Color) -> Color {
        guard let hex, hex.trimmedOrNil != nil else { return fallback }
        let normalized = normalizedCalendarCategoryHexColor(hex)
        let value = String(normalized.dropFirst())
        guard let rgb = Int(value, radix: 16) else { return fallback }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }

    private var effectiveUsesDarkAppearance: Bool {
        if let preferredMode = currentVisualModePreference() ?? store.visualMode {
            return preferredMode.usesDarkAppearance
        }
        return AppAppearanceRegistry.usesDarkPalette()
    }

    private func calendarDayHighlightKind(
        for date: Date,
        holidays: [HolidayDefinition]
    ) -> CalendarDayHighlightKind? {
        if !holidays.isEmpty {
            return .holiday
        }

        switch workspaceCalendar.component(.weekday, from: date) {
        case 7:
            return .saturday
        case 1:
            return .sunday
        default:
            return nil
        }
    }

    private func configuredCalendarDayHighlightTextColor(_ kind: CalendarDayHighlightKind) -> Color {
        configuredCalendarColor(
            hex: store.calendarDayHighlightTextHex(kind, usesDarkAppearance: effectiveUsesDarkAppearance),
            fallback: AppPalette.vividRed
        )
    }

    private func configuredCalendarDayHighlightBackgroundColor(_ kind: CalendarDayHighlightKind) -> Color {
        configuredCalendarColor(
            hex: store.calendarDayHighlightBackgroundHex(kind, usesDarkAppearance: effectiveUsesDarkAppearance),
            fallback: AppPalette.vividRed
        )
    }

    private func resolvedCalendarDayHighlightColors(
        for kind: CalendarDayHighlightKind
    ) -> (text: Color, background: Color) {
        (
            text: configuredCalendarDayHighlightTextColor(kind),
            background: configuredCalendarDayHighlightBackgroundColor(kind)
        )
    }

    private func configuredFixedCategoryColor(_ category: CalendarFixedCategory) -> Color {
        let fallback: Color
        switch category {
        case .travel:
            fallback = AppPalette.vividGreen
        case .task:
            fallback = AppPalette.vividOrange
        case .deadline:
            fallback = AppPalette.vividRed
        case .uncategorized:
            fallback = AppPalette.vividBlue
        }
        return configuredCalendarColor(
            hex: store.calendarFixedCategoryColorHex(category, usesDarkAppearance: effectiveUsesDarkAppearance),
            fallback: fallback
        )
    }

    private func configuredMeetingCategoryColor(named name: String) -> Color {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return configuredFixedCategoryColor(.uncategorized) }
        let fallback = store.calendarCategoryIsClinicalTime(named: trimmed) ? AppPalette.vividOrange : AppPalette.vividBlue
        return configuredCalendarColor(
            hex: store.calendarMeetingCategoryColorHex(named: trimmed, usesDarkAppearance: effectiveUsesDarkAppearance),
            fallback: fallback
        )
    }

    private func configuredEventCategoryColor(for event: CalendarWorkspaceEvent) -> Color? {
        if event.kind == .applicationDeadline || isCongressDeadlineEvent(event) {
            return configuredFixedCategoryColor(.deadline)
        }
        if let meeting = meetingRecord(for: event) {
            return configuredMeetingCategoryColor(named: meeting.meetingType)
        }
        if let categoryName = event.meetingCategoryName {
            return configuredMeetingCategoryColor(named: categoryName)
        }
        switch event.kind {
        case .travel, .accommodation:
            return configuredFixedCategoryColor(.travel)
        case .taskDeadline:
            return configuredFixedCategoryColor(.task)
        default:
            return nil
        }
    }

    private func eventRowAccentColor(for event: CalendarWorkspaceEvent) -> Color {
        configuredEventCategoryColor(for: event) ?? eventRowAccentColor(for: event.kind)
    }

    private func eventRowAccentColor(for kind: CalendarWorkspaceEventKind) -> Color {
        switch kind {
        case .holiday:
            return configuredCalendarDayHighlightBackgroundColor(.holiday)
        case .congress:
            return AppPalette.vividBlue
        case .travel:
            return configuredFixedCategoryColor(.travel)
        case .accommodation:
            return configuredFixedCategoryColor(.travel)
        case .meeting:
            return AppPalette.vividBlue
        case .applicationDeadline:
            return configuredFixedCategoryColor(.deadline)
        case .taskDeadline:
            return configuredFixedCategoryColor(.task)
        }
    }

    private func eventCategoryTextColor(for event: CalendarWorkspaceEvent) -> Color {
        effectiveUsesDarkAppearance ? .white : .black
    }

    private func meetingRecord(for event: CalendarWorkspaceEvent) -> CalendarMeetingRecord? {
        guard case let .meeting(meetingID) = event.source else { return nil }
        return cache.meetingRecordsByID[meetingID]
    }

    private func eventBodyTextColor(for event: CalendarWorkspaceEvent) -> Color {
        if event.kind == .holiday {
            return configuredCalendarDayHighlightTextColor(.holiday)
        }
        return eventUsesItalicStyle(event) ? Color.secondary : Color.primary
    }

    private func eventRowHighlightColor(for event: CalendarWorkspaceEvent) -> Color {
        if let categoryColor = configuredEventCategoryColor(for: event) {
            return categoryColor
        }
        switch event.kind {
        case .holiday:
            return configuredCalendarDayHighlightBackgroundColor(.holiday)
        case .congress:
            return AppPalette.shadeBlue
        case .travel:
            return configuredFixedCategoryColor(.travel)
        case .accommodation:
            return configuredFixedCategoryColor(.travel)
        case .meeting:
            return AppPalette.shadeBlue
        case .applicationDeadline:
            return configuredFixedCategoryColor(.deadline)
        case .taskDeadline:
            return configuredFixedCategoryColor(.task)
        }
    }

    @ViewBuilder
    private func conferenceCell(for group: CalendarWorkspaceDayGroup, showsDateColumns: Bool) -> some View {
        if !showsDateColumns || group.conferenceEvents.isEmpty {
            Color.clear.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(group.conferenceEvents) { event in
                    CalendarConferenceLabel(
                        title: event.title,
                        hoverText: conferenceHoverText(for: event),
                        isDateUncertain: event.isDateUncertain,
                        language: language,
                        action: event.action
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func conferenceHoverText(for event: CalendarWorkspaceEvent) -> String {
        guard case let .congress(organizationID, congressID) = event.source,
              let organization = cache.organizationsByID[organizationID],
              let congress = organization.congresses.first(where: { $0.id == congressID }) else {
            return event.title
        }

        let dateLine = [
            uncertainCalendarDateLabel(congress.from, uncertain: congress.fromUncertain, language: language).map { "\(language.text("From", "Från")): \($0)" },
            uncertainCalendarDateLabel(congress.to, uncertain: congress.toUncertain, language: language).map { "\(language.text("To", "Till")): \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        let deadlineLine = [
            uncertainCalendarDateLabel(congress.abstractSubmissionDeadline, uncertain: congress.abstractSubmissionDeadlineUncertain, language: language).map { "\(language.text("Abstract deadline", "Abstractdeadline")): \($0)" },
            uncertainCalendarDateLabel(congress.lateAbstractSubmissionDeadline, uncertain: congress.lateAbstractSubmissionDeadlineUncertain, language: language).map { "\(language.text("Late abstract deadline", "Sen abstractdeadline")): \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        return [
            congress.title.nonEmpty ?? event.title,
            organization.displayName(for: language),
            dateLine.nonEmpty,
            deadlineLine.nonEmpty,
            formattedCalendarPlace(
                city: congress.city,
                country: congress.country,
                language: language,
                countryDisplayMode: store.calendarCountryDisplayMode
            )
            .nonEmpty
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    /// The title (with the organisation in parentheses), the row's link
    /// buttons right after it, the participants on a grey line underneath
    /// and then the details as a smaller grey line (the Detaljer setting
    /// decides whether that line shows; "Visa i raden" decides which parts).
    private func eventTitleCell(_ event: CalendarWorkspaceEvent, group: CalendarWorkspaceDayGroup) -> some View {
        let showsTitle = visibleCalendarColumns.contains(.title)
        let detail: CalendarListRowDetail? = calendarShowsDetailLine ? calendarListRowDetail(for: event) : nil
        let hiddenKinds = hiddenCalendarRowDetailKinds
        let titleText = calendarListTitleText(
            title: event.listTitle ?? event.title,
            organization: hiddenKinds.contains(.organization) ? nil : event.organizationName
        )
        let participantsText = hiddenKinds.contains(.participants)
            ? ""
            : calendarListParticipantsText(event.participantNames)
        let usesItalicStyle = eventUsesItalicStyle(event)
        let foreground = eventForegroundColor(for: event, group: group, base: eventBodyTextColor(for: event))
        let detailItalic = detailUsesItalicStyle(for: event)
        let detailForeground = eventForegroundColor(
            for: event,
            group: group,
            base: event.isRolledOverPastDue ? AppPalette.lateText : Color.secondary
        )
        let primaryAction = eventTapAction(for: event)
        return VStack(alignment: .leading, spacing: 2) {
            if showsTitle {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Button {
                        if let primaryAction {
                            primaryAction()
                        } else {
                            presentCalendarEventDetail(event)
                        }
                    } label: {
                        Text(titleText)
                            .calendarTypography(.body)
                            .modifier(CalendarItalicTextModifier(isItalic: usesItalicStyle))
                            .foregroundStyle(foreground)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        calendarEventContextMenu(for: event, on: group.date)
                    }
                    if let detail {
                        calendarRowDetailLinkButtons(detail)
                    }
                    Spacer(minLength: 0)
                }
            }
            if !participantsText.isEmpty {
                Text(participantsText)
                    .calendarTypography(.secondary)
                    .modifier(CalendarItalicTextModifier(isItalic: usesItalicStyle))
                    .foregroundStyle(eventForegroundColor(for: event, group: group, base: Color.secondary))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .help(participantsText)
            }
            if let detail, detail.hasTextLine || (!showsTitle && detail.hasLinkButtons) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let congressLink = detail.congressLink {
                        calendarInlineDetailRecordLinkButton(
                            congressLink,
                            compact: true,
                            italic: detailItalic,
                            typography: .secondary
                        )
                    }
                    if !detail.visibleText.isEmpty {
                        Text(detail.visibleText)
                            .calendarTypography(.secondary)
                            .modifier(CalendarItalicTextModifier(isItalic: detailItalic))
                            .foregroundStyle(detailForeground)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    if !showsTitle {
                        calendarRowDetailLinkButtons(detail)
                    }
                    Spacer(minLength: 0)
                }
                .help(detail.helpText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Overdue or reminding tasks get a clear red ring around the "Klar"
    /// circle instead of a dot after the title.
    private func eventNeedsAttentionRing(_ event: CalendarWorkspaceEvent) -> Bool {
        guard !event.isCompleted else { return false }
        return event.isRolledOverPastDue
            || store.calendarTaskReminderBadgeEntries.contains { $0.source == event.source }
    }

    @ViewBuilder
    private func calendarAutomaticVisibilityContextMenuItem(for event: CalendarWorkspaceEvent) -> some View {
        if let hideKey = event.automaticHideKey {
            Button(event.isHiddenFromCalendar ? language.text("✓ Hidden from calendar", "✓ Gömd från kalendern") : language.text("Hidden from calendar", "Gömd från kalendern")) {
                store.setAutomaticCalendarEventHidden(hideKey, hidden: !event.isHiddenFromCalendar)
            }
        }
    }

    private func eventTapAction(for event: CalendarWorkspaceEvent) -> (() -> Void)? {
        switch event.source {
        case let .organizationTask(organizationID, _):
            return {
                store.route = AppRoute(recordID: organizationID, destination: .organizations)
            }
        case let .projectTask(projectID, taskID):
            return {
                presentedSheet = CalendarWorkspaceSheet(kind: .projectTask(projectID: projectID), recordID: taskID)
            }
        case let .publicationTask(publicationID, taskID):
            return {
                presentedSheet = CalendarWorkspaceSheet(kind: .publicationTask(publicationID: publicationID), recordID: taskID)
            }
        case let .teachingTask(taskID):
            return {
                presentedSheet = CalendarWorkspaceSheet(kind: .todo, recordID: taskID)
            }
        case let .meeting(meetingID):
            return {
                presentedSheet = CalendarWorkspaceSheet(kind: .meeting, recordID: meetingID)
            }
        case let .travel(travelID):
            return {
                presentedSheet = CalendarWorkspaceSheet(kind: .travel, recordID: travelID)
            }
        case let .accommodation(accommodationID):
            return {
                presentedSheet = CalendarWorkspaceSheet(kind: .accommodation, recordID: accommodationID)
            }
        case let .congress(organizationID, congressID) where event.kind == .travel:
            if let flightID = congressFlightID(from: event) {
                return {
                    presentedSheet = CalendarWorkspaceSheet(
                        kind: .congressFlight(
                            organizationID: organizationID,
                            congressID: congressID,
                            flightID: flightID
                        ),
                        recordID: nil
                    )
                }
            }
            return event.action
        default:
            return event.action
        }
    }

    private func congressFlightID(from event: CalendarWorkspaceEvent) -> String? {
        let parts = event.id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "congress-flight" else { return nil }
        return parts[3].trimmedOrNil
    }

    private func headerCell(_ title: String, alignment: Alignment = .leading) -> some View {
        Text(title)
            .calendarTypography(.tableHeader)
            .foregroundStyle(AppPalette.appText.opacity(effectiveUsesDarkAppearance ? 0.84 : 0.82))
            .multilineTextAlignment(.leading)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func rowCell(
        _ text: String,
        italic: Bool = false,
        foreground: Color = .primary,
        alignment: Alignment = .leading,
        textAlignment: TextAlignment = .leading
    ) -> some View {
        Text(text)
            .calendarTypography(.body)
            .modifier(CalendarItalicTextModifier(isItalic: italic))
            .foregroundStyle(text.isEmpty ? .clear : foreground)
            .multilineTextAlignment(textAlignment)
            .frame(maxWidth: .infinity, alignment: alignment)
            .lineLimit(2)
    }

    @ViewBuilder
    private func placeCell(_ text: String, italic: Bool = false, foreground: Color = .primary) -> some View {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            rowCell("")
        } else if calendarPlaceIsOnline(cleaned) {
            // Online meetings show a camera icon in the category column, so
            // the place stays empty; with that column hidden the word shows.
            if visibleCalendarColumns.contains(.category) {
                rowCell("")
            } else {
                rowCell(cleaned, italic: italic, foreground: foreground)
            }
        } else if cleaned.caseInsensitiveCompare("Telefon") == .orderedSame
            || cleaned.caseInsensitiveCompare("Phone") == .orderedSame {
            Image(systemName: "phone.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(cleaned)
                .accessibilityLabel(cleaned)
        } else if cleaned.contains(somalilandFlagToken) {
            let segments = cleaned.components(separatedBy: somalilandFlagToken)
            HStack(alignment: .center, spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Text(segment)
                            .calendarTypography(.body)
                            .modifier(CalendarItalicTextModifier(isItalic: italic))
                            .foregroundStyle(foreground)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if index < segments.count - 1 {
                        somalilandFlagView
                            .fixedSize()
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(cleaned)
                .calendarTypography(.body)
                .modifier(CalendarItalicTextModifier(isItalic: italic))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
    }

    private var somalilandFlagView: some View {
        Group {
            if let somalilandFlagImage {
                Image(nsImage: somalilandFlagImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppPalette.vividRed.opacity(0.25))
            }
        }
        .frame(width: somalilandFlagDisplayWidth, height: somalilandFlagDisplayHeight)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }

    private func eventUsesItalicStyle(_ event: CalendarWorkspaceEvent) -> Bool {
        isStandaloneCongressEvent(event)
    }

    private func calendarMeetingProjectIDs(_ meeting: CalendarMeetingRecord) -> [String] {
        let projectIDs = meeting.projectIDs.isEmpty ? (meeting.projectID.map { [$0] } ?? []) : meeting.projectIDs
        return Array(NSOrderedSet(array: projectIDs.compactMap(\.trimmedOrNil))) as? [String]
            ?? projectIDs.compactMap(\.trimmedOrNil)
    }

    private func calendarMeetingOrganizationIDs(_ meeting: CalendarMeetingRecord) -> [String] {
        let organizationIDs = meeting.organizationIDs.isEmpty
            ? (meeting.organizationID.map { [$0] } ?? [])
            : meeting.organizationIDs
        return Array(NSOrderedSet(array: organizationIDs.compactMap(\.trimmedOrNil))) as? [String]
            ?? organizationIDs.compactMap(\.trimmedOrNil)
    }

    private func calendarMeetingReferencedProjectIDs(_ meeting: CalendarMeetingRecord) -> [String] {
        var projectIDs = calendarMeetingProjectIDs(meeting)
        for applicationID in meeting.applicationIDs.compactMap(\.trimmedOrNil) {
            if let projectID = cache.applicationsByID[applicationID]?.projectID?.trimmedOrNil {
                projectIDs.append(projectID)
            }
        }
        for publicationID in meeting.publicationIDs.compactMap(\.trimmedOrNil) {
            if let projectID = cache.publicationsByID[publicationID]?.projectID?.trimmedOrNil {
                projectIDs.append(projectID)
            }
        }
        for appearanceID in meeting.mediaAppearanceIDs.compactMap(\.trimmedOrNil) {
            projectIDs.append(contentsOf: store.cvMediaAppearances
                .first(where: { $0.id == appearanceID })?
                .projectIDs ?? [])
        }
        return Array(NSOrderedSet(array: projectIDs)) as? [String] ?? projectIDs
    }

    private func projectReferences(for event: CalendarWorkspaceEvent) -> [(id: String, label: String)] {
        cache.projectReferencesByEventID[event.id] ?? uncachedProjectReferences(for: event)
    }

    private func calendarProjectID(from task: ProjectTaskItem) -> String? {
        task.publicationID.flatMap { cache.publicationsByID[$0]?.projectID }
            ?? task.applicationID.flatMap { cache.applicationsByID[$0]?.projectID }
    }

    private func centralTaskItem(for taskID: String) -> TaskItem? {
        store.taskItems.first(where: { $0.id == taskID })
    }

    private func uncachedProjectReferences(for event: CalendarWorkspaceEvent) -> [(id: String, label: String)] {
        switch event.source {
        case let .organizationTask(organizationID, taskID):
            guard let task = cache.organizationsByID[organizationID]?.projectTasks.first(where: { $0.id == taskID }),
                  let projectID = calendarProjectID(from: task),
                  let project = cache.projectsByID[projectID] else { return [] }
            return [(project.id, project.displayName(for: language))]
        case let .projectTask(projectID, _):
            guard let project = cache.projectsByID[projectID] else { return [] }
            return [(project.id, project.displayName(for: language))]
        case let .application(applicationID):
            guard let application = cache.applicationsByID[applicationID] else { return [] }
            let project = application.projectID
                .flatMap { id in cache.projectsByID[id] }
                ?? application.projectType?.trimmedOrNil.flatMap(store.project(named:))
            guard let project else { return [] }
            return [(project.id, project.displayName(for: language))]
        case let .publicationTask(publicationID, _):
            guard let projectID = cache.publicationsByID[publicationID]?.projectID,
                  let project = cache.projectsByID[projectID] else { return [] }
            return [(project.id, project.displayName(for: language))]
        case let .meeting(meetingID):
            guard let meeting = cache.meetingRecordsByID[meetingID] else { return [] }
            return calendarMeetingReferencedProjectIDs(meeting).compactMap { id in
                cache.projectsByID[id].map { (id: $0.id, label: $0.displayName(for: language)) }
            }
        case let .mediaAppearance(appearanceID):
            guard let appearance = store.cvMediaAppearances.first(where: { $0.id == appearanceID }) else { return [] }
            return appearance.projectIDs.compactMap { id in
                cache.projectsByID[id].map { (id: $0.id, label: $0.displayName(for: language)) }
            }
        case let .teachingTask(taskID):
            if let task = centralTaskItem(for: taskID) {
                return calendarCentralTaskProjectIDs(
                    task,
                    applicationsByID: cache.applicationsByID,
                    publicationsByID: cache.publicationsByID
                )
                .compactMap { id in
                    cache.projectsByID[id].map { (id: $0.id, label: $0.displayName(for: language)) }
                }
            }
            guard let task = cache.teachingTasksByID[taskID] else { return [] }
            var projectIDs: [String] = []
            if let directProjectID = task.projectID?.trimmedOrNil {
                projectIDs.append(directProjectID)
            }
            if let publicationID = task.publicationID?.trimmedOrNil,
               let publicationProjectID = cache.publicationsByID[publicationID]?.projectID {
                projectIDs.append(publicationProjectID)
            }
            if let applicationID = task.applicationID?.trimmedOrNil,
               let applicationProjectID = cache.applicationsByID[applicationID]?.projectID {
                projectIDs.append(applicationProjectID)
            }
            let uniqueProjectIDs = Array(NSOrderedSet(array: projectIDs)) as? [String] ?? projectIDs
            return uniqueProjectIDs.compactMap { id in
                cache.projectsByID[id].map { (id: $0.id, label: $0.displayName(for: language)) }
            }
        default:
            return []
        }
    }

    /// The projects as plain grey text (no box, no folder icon), each on
    /// its own line; the row grows to fit them. Clicking a name still opens
    /// the project.
    @ViewBuilder
    private func projectCell(for event: CalendarWorkspaceEvent, group: CalendarWorkspaceDayGroup) -> some View {
        let references = projectReferences(for: event)
        let foreground = eventForegroundColor(for: event, group: group, base: .secondary)
        if references.isEmpty {
            rowCell("")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(references, id: \.id) { project in
                    calendarProjectLink(id: project.id, label: project.label, foreground: foreground)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(references.map(\.label).joined(separator: "\n"))
        }
    }

    private func calendarProjectLink(id: String, label: String, foreground: Color) -> some View {
        Button {
            store.route = AppRoute(recordID: id, destination: .projects)
        } label: {
            Text(label)
                .calendarTypography(.body)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .buttonStyle(.plain)
        .accessibilityHint(language.text("Opens the project", "Öppnar projektet"))
    }

    private func projectOverflowIndicator(onExpand: @escaping () -> Void) -> some View {
        CalendarProjectOverflowIndicator(onExpand: onExpand)
    }

    private func detailText(for event: CalendarWorkspaceEvent) -> String {
        cache.visibleDetailTextByEventID[event.id]
            ?? calendarWorkspaceVisibleDetailText(for: event, language: language)
    }

    private func detailLinkPresentation(for event: CalendarWorkspaceEvent) -> CalendarDetailLinkPresentation {
        cache.detailLinkPresentationByEventID[event.id]
            ?? calendarDetailLinkPresentation(from: detailText(for: event))
    }

    private func detailUsesItalicStyle(for event: CalendarWorkspaceEvent) -> Bool {
        event.isRolledOverPastDue || eventUsesItalicStyle(event)
    }

    private func detailTextColor(for event: CalendarWorkspaceEvent) -> Color {
        event.isRolledOverPastDue ? AppPalette.lateText : eventBodyTextColor(for: event)
    }

    private func dateAccentTextColor(for group: CalendarWorkspaceDayGroup) -> Color {
        if let kind = calendarDayHighlightKind(for: group.date, holidays: group.holidays) {
            return configuredCalendarDayHighlightTextColor(kind)
        }
        return .primary
    }

    private func dayForegroundOpacity(for group: CalendarWorkspaceDayGroup) -> Double {
        group.isPast ? 0.6 : 1
    }

    private func dayForegroundColor(for group: CalendarWorkspaceDayGroup, base: Color) -> Color {
        base.opacity(dayForegroundOpacity(for: group))
    }

    private func dayGroupFill(for group: CalendarWorkspaceDayGroup) -> Color {
        AppPalette.calendarDayRowSurface
    }

    private func eventForegroundOpacity(for event: CalendarWorkspaceEvent, group: CalendarWorkspaceDayGroup) -> Double {
        if event.isCompleted {
            return 0.56
        }
        return eventIsPast(event, group: group) ? 0.6 : 1
    }

    private func eventForegroundColor(
        for event: CalendarWorkspaceEvent,
        group: CalendarWorkspaceDayGroup,
        base: Color
    ) -> Color {
        base.opacity(eventForegroundOpacity(for: event, group: group))
    }

    private func eventIsPast(_ event: CalendarWorkspaceEvent, group: CalendarWorkspaceDayGroup) -> Bool {
        if group.date < today {
            return true
        }
        if group.date > today {
            return false
        }
        guard let cutoff = eventPastCutoffDate(for: event) else {
            return false
        }
        return cutoff < Date()
    }

    private func eventPastCutoffDate(for event: CalendarWorkspaceEvent) -> Date? {
        switch event.source {
        case let .meeting(meetingID):
            guard let meeting = cache.meetingRecordsByID[meetingID] else { return nil }
            return calendarDateTime(
                dayString: meeting.date,
                timeString: meeting.endTime.nonEmpty ?? meeting.startTime
            )
        case let .travel(travelID):
            guard let travel = cache.travelRecordsByID[travelID] else { return nil }
            return calendarDateTime(
                dayString: travel.resolvedArrivalDateString(),
                timeString: travel.arrivalTime.nonEmpty ?? travel.departureTime
            )
        case let .accommodation(accommodationID):
            guard let accommodation = cache.accommodationRecordsByID[accommodationID] else { return nil }
            return calendarDateTime(
                dayString: accommodation.checkOutDate,
                timeString: accommodation.checkOutTime.nonEmpty ?? accommodation.checkInTime
            )
        case let .mediaAppearance(appearanceID):
            guard let appearance = store.cvMediaAppearances.first(where: { $0.id == appearanceID }) else { return nil }
            return calendarDateTime(
                dayString: appearance.date,
                timeString: appearance.endTime.nonEmpty ?? appearance.startTime
            )
        default:
            return nil
        }
    }

    private func calendarDateTime(dayString: String, timeString: String?) -> Date? {
        guard let day = DateParsers.isoDay.date(from: dayString) else { return nil }
        guard let time = timeString?.trimmedOrNil else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return workspaceCalendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: workspaceCalendar.startOfDay(for: day)
        )
    }

    private func researcherReferences(for event: CalendarWorkspaceEvent) -> [String] {
        switch event.source {
        case let .meeting(meetingID):
            return cache.meetingRecordsByID[meetingID]?.participantNames ?? []
        case let .mediaAppearance(appearanceID):
            guard let appearance = store.cvMediaAppearances.first(where: { $0.id == appearanceID }) else { return [] }
            return appearance.authorIDs.compactMap { cache.publicationAuthorsByID[$0]?.displayName }
        case let .organizationTask(organizationID, taskID):
            return cache.organizationsByID[organizationID]?.projectTasks.first(where: { $0.id == taskID })?.participantNames ?? []
        case let .projectTask(projectID, _):
            return cache.projectsByID[projectID]?.collaboratorNames ?? []
        case let .application(applicationID):
            return cache.applicationsByID[applicationID]?.coApplicants ?? []
        case let .publicationTask(publicationID, _):
            return cache.publicationsByID[publicationID]?.authorNames ?? []
        case let .teachingTask(taskID):
            if let task = centralTaskItem(for: taskID) {
                return calendarCentralTaskResearcherNames(
                    task,
                    projectsByID: cache.projectsByID,
                    applicationsByID: cache.applicationsByID,
                    publicationsByID: cache.publicationsByID
                )
            }
            return cache.teachingTasksByID[taskID]?.participantNames ?? []
        case let .reviewDeadline(reviewID):
            guard let authorID = cache.reviewEntriesByID[reviewID]?.authorID,
                  let author = cache.publicationAuthorsByID[authorID] else {
                return []
            }
            return [author.name]
        default:
            return []
        }
    }

    /// F13d: the researcher links behind `researcherReferences(for:)`, used
    /// so the researcher filter finds a record even when it was written with
    /// an older spelling of the name.
    private func researcherIDReferences(for event: CalendarWorkspaceEvent) -> [String] {
        switch event.source {
        case let .meeting(meetingID):
            return cache.meetingRecordsByID[meetingID]?.participantAuthorIDs ?? []
        case let .mediaAppearance(appearanceID):
            return store.cvMediaAppearances.first(where: { $0.id == appearanceID })?.authorIDs ?? []
        case let .organizationTask(organizationID, taskID):
            return cache.organizationsByID[organizationID]?.projectTasks.first(where: { $0.id == taskID })?.participantAuthorIDs ?? []
        case let .projectTask(projectID, _):
            return cache.projectsByID[projectID]?.collaboratorAuthorIDs ?? []
        case let .application(applicationID):
            return cache.applicationsByID[applicationID]?.coApplicantAuthorIDs ?? []
        case let .publicationTask(publicationID, _):
            return cache.publicationsByID[publicationID]?.authorIDs ?? []
        case let .teachingTask(taskID):
            if let task = centralTaskItem(for: taskID) {
                return calendarCentralTaskResearcherIDs(
                    task,
                    projectsByID: cache.projectsByID,
                    applicationsByID: cache.applicationsByID,
                    publicationsByID: cache.publicationsByID
                )
            }
            return cache.teachingTasksByID[taskID]?.participantAuthorIDs ?? []
        case let .reviewDeadline(reviewID):
            guard let authorID = cache.reviewEntriesByID[reviewID]?.authorID?.trimmedOrNil else { return [] }
            return [authorID]
        default:
            return []
        }
    }

    private func organizationReferences(for event: CalendarWorkspaceEvent) -> [(id: String, label: String)] {
        switch event.source {
        case let .organizationTask(organizationID, _):
            guard let organization = cache.organizationsByID[organizationID] else { return [] }
            return [(organization.id, organization.displayName(for: language))]
        case let .application(applicationID):
            guard let application = cache.applicationsByID[applicationID],
                  let organizationID = application.organizationID,
                  let organization = cache.organizationsByID[organizationID] else { return [] }
            return [(organization.id, organization.displayName(for: language))]
        case let .congress(organizationID, _):
            guard let organization = cache.organizationsByID[organizationID] else { return [] }
            return [(organization.id, organization.displayName(for: language))]
        case let .travel(travelID):
            guard let travel = cache.travelRecordsByID[travelID],
                  let organization = cache.organizationsByID[travel.congressOrganizationID] else { return [] }
            return [(organization.id, organization.displayName(for: language))]
        case let .accommodation(accommodationID):
            guard let accommodation = cache.accommodationRecordsByID[accommodationID],
                  let organization = cache.organizationsByID[accommodation.congressOrganizationID] else { return [] }
            return [(organization.id, organization.displayName(for: language))]
        case let .meeting(meetingID):
            guard let meeting = cache.meetingRecordsByID[meetingID] else { return [] }
            return calendarMeetingOrganizationIDs(meeting).compactMap { organizationID in
                cache.organizationsByID[organizationID].map { (id: $0.id, label: $0.displayName(for: language)) }
            }
        case let .teachingTask(taskID):
            guard let task = centralTaskItem(for: taskID) else { return [] }
            return calendarCentralTaskTargetIDs(task, kind: .organization).compactMap { organizationID in
                cache.organizationsByID[organizationID].map { (id: $0.id, label: $0.displayName(for: language)) }
            }
        default:
            return []
        }
    }

    private func applicationReferences(for event: CalendarWorkspaceEvent) -> [(id: String, label: String)] {
        if case let .meeting(meetingID) = event.source {
            guard let meeting = cache.meetingRecordsByID[meetingID] else { return [] }
            return meeting.applicationIDs.compactMap(\.trimmedOrNil).compactMap { applicationID in
                guard let application = cache.applicationsByID[applicationID] else { return nil }
                let label = store.localizedGrantName(for: application, language: language).nonEmpty
                    ?? store.organizationLabel(for: application, language: language)
                return (id: application.id, label: label)
            }
        }

        if case let .teachingTask(taskID) = event.source,
           let task = centralTaskItem(for: taskID) {
            return calendarCentralTaskTargetIDs(task, kind: .application).compactMap { applicationID in
                guard let application = cache.applicationsByID[applicationID] else { return nil }
                let label = store.localizedGrantName(for: application, language: language).nonEmpty
                    ?? store.organizationLabel(for: application, language: language)
                return (id: application.id, label: label)
            }
        }

        let applicationID: String?
        switch event.source {
        case let .application(id):
            applicationID = id
        case let .organizationTask(organizationID, taskID):
            applicationID = cache.organizationsByID[organizationID]?.projectTasks.first(where: { $0.id == taskID })?.applicationID
        case let .projectTask(projectID, taskID):
            applicationID = cache.projectsByID[projectID]?.projectTasks.first(where: { $0.id == taskID })?.applicationID
        case let .publicationTask(publicationID, taskID):
            applicationID = cache.publicationsByID[publicationID]?.publicationTasks.first(where: { $0.id == taskID })?.applicationID
        case let .teachingTask(taskID):
            applicationID = cache.teachingTasksByID[taskID]?.applicationID
        default:
            applicationID = nil
        }
        guard let applicationID,
              let application = cache.applicationsByID[applicationID] else { return [] }
        let label = store.localizedGrantName(for: application, language: language).nonEmpty
            ?? store.organizationLabel(for: application, language: language)
        return [(id: application.id, label: label)]
    }

    private func publicationReferences(for event: CalendarWorkspaceEvent) -> [(id: String, label: String)] {
        if case let .meeting(meetingID) = event.source {
            guard let meeting = cache.meetingRecordsByID[meetingID] else { return [] }
            return meeting.publicationIDs.compactMap(\.trimmedOrNil).compactMap { publicationID in
                guard let publication = cache.publicationsByID[publicationID] else { return nil }
                return (id: publication.id, label: publication.title.nonEmpty ?? language.text("Untitled publication", "Namnlös publikation"))
            }
        }

        if case let .teachingTask(taskID) = event.source,
           let task = centralTaskItem(for: taskID) {
            return calendarCentralTaskTargetIDs(task, kind: .publication).compactMap { publicationID in
                guard let publication = cache.publicationsByID[publicationID] else { return nil }
                return (
                    id: publication.id,
                    label: publication.title.nonEmpty
                        ?? language.text("Untitled publication", "Namnlös publikation")
                )
            }
        }

        let publicationID: String?
        switch event.source {
        case let .publicationTask(id, _):
            publicationID = id
        case let .organizationTask(organizationID, taskID):
            publicationID = cache.organizationsByID[organizationID]?.projectTasks.first(where: { $0.id == taskID })?.publicationID
        case let .projectTask(projectID, taskID):
            publicationID = cache.projectsByID[projectID]?.projectTasks.first(where: { $0.id == taskID })?.publicationID
        case let .teachingTask(taskID):
            publicationID = cache.teachingTasksByID[taskID]?.publicationID
        default:
            publicationID = nil
        }
        guard let publicationID,
              let publication = cache.publicationsByID[publicationID] else { return [] }
        return [(id: publication.id, label: publication.title.nonEmpty ?? language.text("Untitled publication", "Namnlös publikation"))]
    }

    private func teachingAssignmentReferences(for event: CalendarWorkspaceEvent) -> [(id: String, label: String)] {
        if case let .teachingTask(taskID) = event.source,
           let task = centralTaskItem(for: taskID) {
            return calendarCentralTaskTargetIDs(task, kind: .teachingAssignment).compactMap { assignmentID in
                guard let assignment = cache.teachingAssignmentsByID[assignmentID] else { return nil }
                return (
                    id: assignment.id,
                    label: calendarTeachingAssignmentLabel(assignment, store: store, language: language)
                )
            }
        }

        guard case let .meeting(meetingID) = event.source,
              let meeting = cache.meetingRecordsByID[meetingID] else {
            return []
        }
        return calendarMeetingTeachingAssignmentIDs(meeting).compactMap { assignmentID in
            guard let assignment = cache.teachingAssignmentsByID[assignmentID] else { return nil }
            return (id: assignment.id, label: calendarTeachingAssignmentLabel(assignment, store: store, language: language))
        }
    }

    /// Round 7: the courses an activity or a task is linked to as a whole.
    private func teachingCourseReferences(for event: CalendarWorkspaceEvent) -> [(id: String, label: String)] {
        let courseIDs: [String]
        switch event.source {
        case let .teachingTask(taskID):
            guard let task = centralTaskItem(for: taskID) else { return [] }
            courseIDs = calendarCentralTaskTargetIDs(task, kind: .teachingCourse)
        case let .meeting(meetingID):
            guard let meeting = cache.meetingRecordsByID[meetingID] else { return [] }
            courseIDs = meeting.teachingCourseIDs.compactMap(\.trimmedOrNil)
        default:
            return []
        }
        return courseIDs.compactMap { courseID in
            guard let course = cache.teachingCoursesByID[courseID] else { return nil }
            return (id: course.id, label: calendarTeachingCourseLabel(course, language: language))
        }
    }

    /// Round 7: the doctoral candidates an activity or a task is linked to.
    private func doctoralCandidateReferences(for event: CalendarWorkspaceEvent) -> [(id: String, label: String)] {
        let candidateIDs: [String]
        switch event.source {
        case let .teachingTask(taskID):
            guard let task = centralTaskItem(for: taskID) else { return [] }
            candidateIDs = calendarCentralTaskTargetIDs(task, kind: .doctoralCandidate)
        case let .meeting(meetingID):
            guard let meeting = cache.meetingRecordsByID[meetingID] else { return [] }
            candidateIDs = calendarMeetingDoctoralCandidateIDs(meeting)
        default:
            return []
        }
        return candidateIDs.compactMap { candidateID in
            guard let candidate = cache.doctoralCandidatesByID[candidateID] else { return nil }
            let name = candidate.candidateName.nonEmpty
                ?? language.text("Unnamed doctoral candidate", "Namnlös doktorand")
            return (id: candidate.id, label: "\(language.text("Doctoral candidate", "Doktorand")): \(name)")
        }
    }

    private func detailRecordLinks(for event: CalendarWorkspaceEvent) -> [CalendarDetailRecordLink] {
        // The grant's own deadline event already navigates to the grant; only linked grants get a chip.
        let applicationLinks: [CalendarDetailRecordLink]
        if case .application = event.source {
            applicationLinks = []
        } else {
            applicationLinks = applicationReferences(for: event).map { application in
                CalendarDetailRecordLink(
                    id: "application:\(application.id)",
                    title: application.label,
                    systemImage: "doc.text",
                    destination: .application(application.id)
                )
            }
        }
        let publicationLinks = publicationReferences(for: event).map { publication in
            CalendarDetailRecordLink(
                id: "publication:\(publication.id)",
                title: publication.label,
                systemImage: "text.book.closed",
                destination: .publication(publication.id)
            )
        }
        let teachingAssignmentLinks = teachingAssignmentReferences(for: event).map { assignment in
            CalendarDetailRecordLink(
                id: "teachingAssignment:\(assignment.id)",
                title: assignment.label,
                systemImage: "graduationcap",
                destination: .teachingAssignment(assignment.id)
            )
        }
        let teachingCourseLinks = teachingCourseReferences(for: event).map { course in
            CalendarDetailRecordLink(
                id: "teachingCourse:\(course.id)",
                title: course.label,
                systemImage: "graduationcap",
                destination: .teachingCourse(course.id)
            )
        }
        let doctoralCandidateLinks = doctoralCandidateReferences(for: event).map { candidate in
            CalendarDetailRecordLink(
                id: "doctoralCandidate:\(candidate.id)",
                title: candidate.label,
                systemImage: AppTab.doctoralCandidates.symbolName,
                destination: .doctoralCandidate(candidate.id)
            )
        }
        return applicationLinks + publicationLinks + teachingCourseLinks + teachingAssignmentLinks + doctoralCandidateLinks
    }

    private func congressDetailRecordLink(for event: CalendarWorkspaceEvent) -> CalendarDetailRecordLink? {
        switch event.source {
        case let .travel(travelID):
            guard let travel = cache.travelRecordsByID[travelID],
                  let organization = cache.organizationsByID[travel.congressOrganizationID],
                  let congress = organization.congresses.first(where: { $0.id == travel.congressID }) else {
                return nil
            }
            let title = "\(language.text("Congress", "Kongress")): \(congress.title.nonEmpty ?? organization.displayName(for: language))"
            return CalendarDetailRecordLink(
                id: "congress:\(organization.id):\(congress.id)",
                title: title,
                systemImage: AppTab.congresses.symbolName,
                destination: .congress(organizationID: organization.id, congressID: congress.id)
            )
        case let .accommodation(accommodationID):
            guard let accommodation = cache.accommodationRecordsByID[accommodationID],
                  let organization = cache.organizationsByID[accommodation.congressOrganizationID],
                  let congress = organization.congresses.first(where: { $0.id == accommodation.congressID }) else {
                return nil
            }
            let title = "\(language.text("Congress", "Kongress")): \(congress.title.nonEmpty ?? organization.displayName(for: language))"
            return CalendarDetailRecordLink(
                id: "congress:\(organization.id):\(congress.id)",
                title: title,
                systemImage: AppTab.congresses.symbolName,
                destination: .congress(organizationID: organization.id, congressID: congress.id)
            )
        case let .congress(organizationID, congressID) where event.kind == .travel || event.kind == .accommodation:
            guard let organization = cache.organizationsByID[organizationID],
                  let congress = organization.congresses.first(where: { $0.id == congressID }) else {
                return nil
            }
            let title = "\(language.text("Congress", "Kongress")): \(congress.title.nonEmpty ?? organization.displayName(for: language))"
            return CalendarDetailRecordLink(
                id: "congress:\(organization.id):\(congress.id)",
                title: title,
                systemImage: AppTab.congresses.symbolName,
                destination: .congress(organizationID: organization.id, congressID: congress.id)
            )
        default:
            return nil
        }
    }

    private func openDetailRecordLink(_ link: CalendarDetailRecordLink) {
        switch link.destination {
        case let .application(applicationID):
            store.route = AppRoute(recordID: applicationID, destination: .applications)
        case let .publication(publicationID):
            store.route = AppRoute(recordID: publicationID, destination: .publications)
        case let .congress(organizationID, congressID):
            store.openRouteToCongress(organizationID: organizationID, congressID: congressID)
        case let .teachingAssignment(assignmentID):
            store.route = AppRoute(recordID: assignmentID, destination: .teaching)
        case let .teachingCourse(courseID):
            // The teaching page selects a course when it gets a course id.
            store.route = AppRoute(recordID: courseID, destination: .teaching)
        case let .doctoralCandidate(candidateID):
            store.route = AppRoute(recordID: candidateID, destination: .doctoralCandidates)
        }
    }

    private func matchesHiddenCalendarFilter(_ event: CalendarWorkspaceEvent) -> Bool {
        showsHiddenCalendarEvents || !event.isHiddenFromCalendar
    }

    private func matchesCalendarSearchFilter(_ event: CalendarWorkspaceEvent) -> Bool {
        matchesCalendarSearchFilter(event, query: SearchFilterQuery(raw: calendarSearchText))
    }

    private func matchesCalendarSearchFilter(
        _ event: CalendarWorkspaceEvent,
        query: SearchFilterQuery
    ) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = cache.searchTextByEventID[event.id] ?? calendarSearchText(for: event)
        return query.matches(haystack: haystack)
    }

    private func calendarSearchText(
        for event: CalendarWorkspaceEvent,
        projectReferences: [(id: String, label: String)]? = nil,
        sourceFieldText: String? = nil
    ) -> String {
        [
            event.title,
            event.subtitle,
            event.detail,
            event.place,
            event.timeText,
            event.kind.title(language: language),
            event.kind.filterTitle(language: language),
            (projectReferences ?? self.projectReferences(for: event)).map(\.label).joined(separator: " "),
            researcherReferences(for: event).joined(separator: " "),
            sourceFieldText ?? calendarSourceFieldSearchText(for: event),
        ]
        .joined(separator: " ")
    }

    private func calendarSourceFieldSearchText(for event: CalendarWorkspaceEvent) -> String {
        switch event.source {
        case .holiday:
            return ""
        case let .application(applicationID):
            return cache.applicationsByID[applicationID].map(calendarSearchableFieldText) ?? ""
        case let .organizationTask(organizationID, taskID):
            return cache.organizationsByID[organizationID]?
                .projectTasks
                .first(where: { $0.id == taskID })
                .map(calendarSearchableFieldText) ?? ""
        case let .projectTask(projectID, taskID):
            return cache.projectsByID[projectID]?
                .projectTasks
                .first(where: { $0.id == taskID })
                .map(calendarSearchableFieldText) ?? ""
        case let .publicationTask(publicationID, taskID):
            return cache.publicationsByID[publicationID]?
                .publicationTasks
                .first(where: { $0.id == taskID })
                .map(calendarSearchableFieldText) ?? ""
        case let .teachingTask(taskID):
            if let task = centralTaskItem(for: taskID) {
                return calendarSearchableFieldText(task)
            }
            return cache.teachingTasksByID[taskID].map(calendarSearchableFieldText) ?? ""
        case let .reviewDeadline(reviewID):
            return cache.reviewEntriesByID[reviewID].map(calendarSearchableFieldText) ?? ""
        case let .congress(organizationID, congressID):
            return cache.organizationsByID[organizationID]?
                .congresses
                .first(where: { $0.id == congressID })
                .map(calendarSearchableFieldText) ?? ""
        case let .travel(travelID):
            return cache.travelRecordsByID[travelID].map(calendarSearchableFieldText) ?? ""
        case let .accommodation(accommodationID):
            return cache.accommodationRecordsByID[accommodationID].map(calendarSearchableFieldText) ?? ""
        case let .meeting(meetingID):
            guard let meeting = cache.meetingRecordsByID[meetingID] else { return "" }
            return [
                calendarSearchableFieldText(meeting),
                calendarMeetingCategoryDisplayName(meeting.meetingType, language: language),
                CalendarMeetingMode(rawValue: meeting.meetingMode)?.localizedName(language: language) ?? "",
            ]
            .joined(separator: " ")
        case let .mediaAppearance(appearanceID):
            guard let appearance = store.cvMediaAppearances.first(where: { $0.id == appearanceID }) else { return "" }
            return [
                appearance.date,
                appearance.startTime,
                appearance.endTime,
                appearance.titleSv,
                appearance.titleEn,
                appearance.descriptionSv,
                appearance.descriptionEn,
                appearance.link,
                appearance.languageSv,
                appearance.languageEn,
                appearance.languages.joined(separator: " "),
                appearance.comment,
                appearance.projectIDs.compactMap { cache.projectsByID[$0]?.displayName(for: language) }.joined(separator: " "),
                appearance.publicationIDs.compactMap {
                    cache.publicationsByID[$0]?.title
                }.joined(separator: " "),
                appearance.applicationIDs.compactMap {
                    cache.applicationsByID[$0].map { store.localizedGrantName(for: $0, language: language) }
                }.joined(separator: " "),
                appearance.authorIDs.compactMap { cache.publicationAuthorsByID[$0]?.displayName }.joined(separator: " "),
            ]
            .joined(separator: " ")
        }
    }

    private func matchesKindFilter(_ event: CalendarWorkspaceEvent) -> Bool {
        switch event.kind {
        case .meeting:
            return selectedKinds.contains(.meeting)
                && selectedMeetingCategoryKeys.contains(meetingCategoryFilterKey(for: event))
        default:
            return selectedKinds.contains(event.kind)
        }
    }

    private func meetingCategoryFilterKey(for event: CalendarWorkspaceEvent) -> String {
        calendarMeetingCategoryFilterKey(
            for: event.meetingCategoryName ?? meetingRecord(for: event)?.meetingType ?? ""
        )
    }

    private func matchesProjectFilter(_ event: CalendarWorkspaceEvent) -> Bool {
        guard !selectedProjectID.isEmpty else { return true }
        return projectReferences(for: event).contains { $0.id == selectedProjectID }
    }

    private func matchesResearcherFilter(_ event: CalendarWorkspaceEvent) -> Bool {
        guard let selectedName = selectedResearcherName.trimmedOrNil else { return true }
        // F13d: the researcher link first, the written name as fallback.
        if let selectedID = store.researcherID(forPresentedName: selectedName),
           researcherIDReferences(for: event).contains(selectedID) {
            return true
        }
        return researcherReferences(for: event).contains { sameCalendarName($0, selectedName) }
    }

    private func matchesDayLocationFilter(_ event: CalendarWorkspaceEvent) -> Bool {
        guard let selectedLocation = selectedDayLocation.trimmedOrNil else { return true }
        let key = DateParsers.isoDay.string(from: workspaceCalendar.startOfDay(for: event.displayDate))
        return cache.dayEndLocations[key]?.key == selectedLocation
    }

    private func sameCalendarName(_ lhs: String?, _ rhs: String?) -> Bool {
        (lhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(
            (rhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        ) == .orderedSame
    }

    private func completionIconName(for event: CalendarWorkspaceEvent) -> String {
        event.isCompleted ? "checkmark.circle.fill" : "circle"
    }

    private func completionTint(for event: CalendarWorkspaceEvent) -> Color {
        guard let completedOn = event.completedOn?.trimmedOrNil,
              let completedDate = DateParsers.isoDay.date(from: completedOn)
        else {
            return .secondary
        }
        let completedToday = workspaceCalendar.isDate(completedDate, inSameDayAs: today)
        return completedToday ? AppPalette.statusText(AppStatusTones.task(isCompleted: true, isOverdue: false)) : .secondary
    }

    private func calendarDateLabelFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = workspaceCalendar
        formatter.locale = workspaceCalendar.locale
        formatter.dateFormat = format
        return formatter
    }

    private func dateText(for date: Date, formatter: DateFormatter? = nil) -> String {
        let formatter = formatter ?? calendarDateLabelFormatter(format: "d MMMM")
        return formatter.string(from: date).capitalized
    }

    private func weekdayText(for date: Date, formatter: DateFormatter? = nil) -> String {
        let formatter = formatter ?? calendarDateLabelFormatter(format: "EEEE")
        return formatter.string(from: date).capitalized
    }

    private func calendarMetricPill(title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .calendarTypography(.secondary)
            Text("\(value)")
                .calendarTypography(.fieldLabel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.18))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(color.opacity(0.34), lineWidth: 1)
        )
    }

    private func calendarEventSort(_ lhs: CalendarWorkspaceEvent, _ rhs: CalendarWorkspaceEvent) -> Bool {
        calendarWorkspaceEventSort(
            lhs,
            rhs,
            today: today,
            now: currentTimeMarkerDate,
            calendar: workspaceCalendar,
            cutoffDateProvider: currentTimeDividerCutoffDate(for:)
        )
    }

    private func weekNumberText(for date: Date) -> String {
        String(weekNumberCalendar.component(.weekOfYear, from: date))
    }

    private func weekSpacingBeforeGroup(current: Date, previous: Date?) -> CGFloat {
        guard let previous else { return 0 }
        let currentWeek = weekNumberCalendar.component(.weekOfYear, from: current)
        let previousWeek = weekNumberCalendar.component(.weekOfYear, from: previous)
        let currentYear = weekNumberCalendar.component(.yearForWeekOfYear, from: current)
        let previousYear = weekNumberCalendar.component(.yearForWeekOfYear, from: previous)
        return (currentWeek != previousWeek || currentYear != previousYear) ? 16 : 0
    }

    private func parsedDividerCutoffDate(timeText: String, on date: Date) -> Date? {
        let trimmed = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let separators = CharacterSet(charactersIn: "–—-")
        let components = trimmed.components(separatedBy: separators).filter { !$0.isEmpty }
        let timeComponent = components.last ?? trimmed
        let cleaned = timeComponent
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        return workspaceCalendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: workspaceCalendar.startOfDay(for: date)
        )
    }

    private func currentTimeDividerCutoffDate(for event: CalendarWorkspaceEvent) -> Date? {
        if let cutoff = eventPastCutoffDate(for: event) {
            return cutoff
        }

        return parsedDividerCutoffDate(
            timeText: event.timeText,
            on: event.displayDate
        )
    }

    private func normalizedDayPositions(_ positions: [CalendarDayPosition]) -> [CalendarDayPosition] {
        var map: [String: CalendarDayPosition] = [:]
        for position in positions {
            map[DateParsers.isoDay.string(from: position.date)] = position
        }
        return Array(map.values)
    }

    private func handleCalendarDayPositionsChange(_ positions: [CalendarDayPosition], using proxy: ScrollViewProxy) {
        guard isActive else { return }
        let signature = visibleDayPositionSignature(for: positions)
        guard signature != lastVisibleDayPositionSignature else { return }

        pendingVisibleDayPositions = positions
        let now = CFAbsoluteTimeGetCurrent()
        let minimumInterval: CFAbsoluteTime = 0.09
        let elapsed = now - lastVisibleDayPositionPublishAt
        if elapsed >= minimumInterval {
            publishPendingVisibleDayPositions(using: proxy)
            return
        }

        guard pendingVisibleDayPositionTask == nil else { return }
        let task = DispatchWorkItem {
            publishPendingVisibleDayPositions(using: proxy)
        }
        pendingVisibleDayPositionTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + (minimumInterval - elapsed), execute: task)
    }

    private func publishPendingVisibleDayPositions(using proxy: ScrollViewProxy) {
        pendingVisibleDayPositionTask?.cancel()
        pendingVisibleDayPositionTask = nil
        guard isActive else {
            pendingVisibleDayPositions = nil
            return
        }
        guard let positions = pendingVisibleDayPositions else { return }
        pendingVisibleDayPositions = nil

        let signature = visibleDayPositionSignature(for: positions)
        guard signature != lastVisibleDayPositionSignature else { return }
        lastVisibleDayPositionSignature = signature
        lastVisibleDayPositionPublishAt = CFAbsoluteTimeGetCurrent()
        visibleDayPositions = positions
        handleCalendarDayPositions(positions, using: proxy)
    }

    private func cancelPendingVisibleDayPositionPublish() {
        pendingVisibleDayPositionTask?.cancel()
        pendingVisibleDayPositionTask = nil
        pendingVisibleDayPositions = nil
    }

    private func deactivateCalendarWorkspace() {
        // Prefer the newest geometry sample that was waiting to be published.
        // At tab exit the active calendar is still on screen, so this is the
        // last trustworthy opportunity to derive the day at the top edge.
        let positions = pendingVisibleDayPositions ?? visibleDayPositions
        let geometryFocusedDate = positions
            .filter { $0.maxY > 0 }
            .min(by: { $0.minY < $1.minY })?
            .date
        let focusedDate = workspaceCalendar.startOfDay(
            for: geometryFocusedDate ?? lastFocusedCalendarDate
        )

        topVisibleDate = focusedDate
        lastFocusedCalendarDate = focusedDate
        store.calendarWorkspaceLastFocusedDate = focusedDate
        store.calendarWorkspaceViewportSnapshot.topVisibleDayString = DateParsers.isoDay.string(from: focusedDate)

        pendingTargetedCalendarScroll = nil
        pendingDefaultOpenDate = nil
        pendingRebuildTask?.cancel()
        pendingRebuildTask = nil
        cancelQueuedCalendarViewportRestoresForTargetedNavigation()
        isRestoringCalendarFocus = true
        cancelPendingVisibleDayPositionPublish()

        // A vertical pixel offset only has meaning for the exact rendered date
        // window that produced it. The active branch removes that ScrollView,
        // and reactivation builds a new window around focusedDate. Reset the
        // restore token so the new AppKit bridge cannot replay an offset from
        // the old window after the date-based scroll has completed.
        verticalScrollRestoreToken = 0
    }

    private func reactivateCalendarWorkspace(using proxy: ScrollViewProxy) {
        // calendarContent is removed while another workspace is active, so its
        // onAppear is the reliable re-entry signal and has the new ScrollViewProxy.
        let focusedDate = workspaceCalendar.startOfDay(
            for: store.calendarWorkspaceLastFocusedDate ?? lastFocusedCalendarDate
        )
        topVisibleDate = focusedDate
        lastFocusedCalendarDate = focusedDate
        store.calendarWorkspaceLastFocusedDate = focusedDate
        isStabilizingDefaultOpen = false
        isRestoringCalendarFocus = true
        hasUserScrolledRenderedCalendarWindow = false
        currentTimeMarkerDate = Date()
        lastPeriodicCalendarCheckDate = currentTimeMarkerDate
        verticalScrollRestoreToken = 0
        resetVisibleDayPositions()

        // Rebuild the virtualized window around the saved day. Restoration is
        // intentionally date-only; absolute offsets from the removed list are
        // not transferable to this new list.
        resetRenderedDateWindow(centeredOn: focusedDate)
        let hasUsableCache = !cache.allDates.isEmpty
        scheduleCalendarCacheRebuild(
            skipIfUnchanged: true,
            delay: hasUsableCache ? 0.03 : 0.12,
            scope: .visibleWindow
        ) {
            applyPendingCalendarOpenRequestIfNeeded()
            if !applyPendingCalendarRevealRequestIfNeeded(using: proxy, animated: true) {
                scheduleTargetedCalendarScroll(to: focusedDate, using: proxy, animated: false)
            }
        }
    }

    private func resetVisibleDayPositions() {
        cancelPendingVisibleDayPositionPublish()
        visibleDayPositions = []
        lastVisibleDayPositionSignature = ""
        lastVisibleDayPositionPublishAt = 0
    }

    private func visibleDayPositionSignature(for positions: [CalendarDayPosition]) -> String {
        positions
            .sorted { $0.date < $1.date }
            .map { position in
                let day = DateParsers.isoDay.string(from: position.date)
                let minBucket = Int((position.minY / 12).rounded())
                let maxBucket = Int((position.maxY / 12).rounded())
                return "\(day):\(minBucket):\(maxBucket)"
            }
            .joined(separator: "|")
    }

    private func handleCalendarDayPositions(_ positions: [CalendarDayPosition], using proxy: ScrollViewProxy) {
        updateTopVisibleDate(from: positions)
        expandRenderedDateWindowIfNeeded(from: positions, using: proxy)
    }

    private func handleCalendarVerticalScrollOffsetChange(from oldValue: CGFloat, to newValue: CGFloat) {
        defer { lastObservedVerticalScrollOffset = newValue }
        guard didInitialLoad else { return }
        guard pendingTargetedCalendarScroll == nil else { return }
        guard pendingResizeViewportRestore == nil else { return }
        guard !isStabilizingDefaultOpen else { return }
        let previous = lastObservedVerticalScrollOffset ?? oldValue
        guard abs(newValue - previous) >= 28 else { return }
        hasUserScrolledRenderedCalendarWindow = true
    }

    private func updateTopVisibleDate(from positions: [CalendarDayPosition]) {
        guard isActive else { return }
        guard !isRestoringCalendarFocus else { return }
        guard pendingTargetedCalendarScroll == nil else { return }
        guard pendingResizeViewportRestore == nil else { return }
        var candidate: CalendarDayPosition?
        for position in positions where position.maxY > 0 {
            let currentMinY = candidate?.minY ?? .greatestFiniteMagnitude
            if position.minY < currentMinY {
                candidate = position
            }
        }
        guard let candidate else { return }
        let normalizedCandidate = workspaceCalendar.startOfDay(for: candidate.date)
        guard !workspaceCalendar.isDate(normalizedCandidate, inSameDayAs: topVisibleDate) else { return }
        topVisibleDate = normalizedCandidate
        lastFocusedCalendarDate = normalizedCandidate
        store.calendarWorkspaceLastFocusedDate = normalizedCandidate
        if isStabilizingDefaultOpen,
           workspaceCalendar.isDate(normalizedCandidate, inSameDayAs: defaultOpenDate) {
            isStabilizingDefaultOpen = false
        }
    }

    private func initialRenderedDateWindow(centeredOn date: Date) -> CalendarRenderedDateWindow {
        let center = workspaceCalendar.startOfDay(for: date)
        let weekStart = workspaceCalendar.dateInterval(of: .weekOfYear, for: center)?.start ?? center
        let weekEnd = workspaceCalendar.date(byAdding: DateComponents(day: 6), to: weekStart) ?? center
        let start = workspaceCalendar.startOfDay(
            for: workspaceCalendar.date(byAdding: .day, value: -14, to: weekStart) ?? weekStart
        )
        let end = workspaceCalendar.startOfDay(
            for: workspaceCalendar.date(byAdding: .day, value: 56, to: weekEnd) ?? weekEnd
        )
        return clippedRenderedDateWindow(start: start, end: end)
    }

    private func clippedRenderedDateWindow(start: Date, end: Date) -> CalendarRenderedDateWindow {
        let normalizedStart = workspaceCalendar.startOfDay(for: start)
        let normalizedEnd = workspaceCalendar.startOfDay(for: end)
        let cacheStart = cache.rangeStart.map { workspaceCalendar.startOfDay(for: $0) }
        let cacheEnd = cache.rangeEnd.map { workspaceCalendar.startOfDay(for: $0) }
        if cache.isWindowScoped {
            return CalendarRenderedDateWindow(start: normalizedStart, end: normalizedEnd)
        }
        return CalendarRenderedDateWindow(
            start: cacheStart.map { max(normalizedStart, $0) } ?? normalizedStart,
            end: cacheEnd.map { min(normalizedEnd, $0) } ?? normalizedEnd
        )
    }

    private func resetRenderedDateWindow(centeredOn date: Date) {
        renderedDateWindow = initialRenderedDateWindow(centeredOn: date)
        derivedDataSignature = nil
        resetVisibleDayPositions()
        hasUserScrolledRenderedCalendarWindow = false
    }

    private func ensureRenderedDateWindow(centeredOn date: Date) {
        guard renderedDateWindow == nil else { return }
        resetRenderedDateWindow(centeredOn: date)
    }

    private func ensureRenderedDateWindow(including date: Date) {
        let target = workspaceCalendar.startOfDay(for: date)
        guard let window = renderedDateWindow else {
            resetRenderedDateWindow(centeredOn: target)
            return
        }
        guard !window.contains(target, calendar: workspaceCalendar) else { return }
        renderedDateWindow = clippedRenderedDateWindow(
            start: min(window.start, target),
            end: max(window.end, target)
        )
        derivedDataSignature = nil
    }

    private func isDateInsideRenderedWindow(_ date: Date) -> Bool {
        guard let renderedDateWindow else { return true }
        return renderedDateWindow.contains(date, calendar: workspaceCalendar)
    }

    private func expandRenderedDateWindowIfNeeded(from positions: [CalendarDayPosition], using proxy: ScrollViewProxy) {
        guard pendingTargetedCalendarScroll == nil else { return }
        guard pendingResizeViewportRestore == nil else { return }
        guard let window = renderedDateWindow else { return }
        guard !positions.isEmpty else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRenderedWindowExpansionAt >= 0.35 else { return }

        let sortedPositions = positions.sorted { $0.date < $1.date }
        guard let firstVisible = sortedPositions.first(where: { $0.maxY > 0 }),
              let lastVisible = sortedPositions.last(where: { $0.minY < 0 || $0.maxY > 0 }) else {
            return
        }

        let edgeThresholdDays = 3
        let expansionDays = 168
        let firstDay = workspaceCalendar.startOfDay(for: firstVisible.date)
        let lastDay = workspaceCalendar.startOfDay(for: lastVisible.date)
        let previousTopVisibleDate = workspaceCalendar.startOfDay(for: topVisibleDate)
        let renderedGroupDates = derivedData.dayGroups.map { workspaceCalendar.startOfDay(for: $0.date) }
        let isAtFirstRenderedGroup = renderedGroupDates.first.map { workspaceCalendar.isDate(firstDay, inSameDayAs: $0) } ?? false
        let isAtLastRenderedGroup = renderedGroupDates.last.map { workspaceCalendar.isDate(lastDay, inSameDayAs: $0) } ?? false
        let isAtRenderedEdge = isAtFirstRenderedGroup || isAtLastRenderedGroup
        guard hasUserScrolledRenderedCalendarWindow || (!isStabilizingDefaultOpen && isAtRenderedEdge) else { return }

        let shouldExpandBackward = firstDay <= (workspaceCalendar.date(byAdding: .day, value: edgeThresholdDays, to: window.start) ?? window.start)
            || isAtFirstRenderedGroup
        let shouldExpandForward = lastDay >= (workspaceCalendar.date(byAdding: .day, value: -edgeThresholdDays, to: window.end) ?? window.end)
            || isAtLastRenderedGroup
        guard shouldExpandBackward || shouldExpandForward else { return }

        let expandedStart = shouldExpandBackward
            ? earlierRenderedWindowStart(from: window.start, fallbackDays: expansionDays)
            : window.start
        let expandedEnd = shouldExpandForward
            ? laterRenderedWindowEnd(from: window.end, fallbackDays: expansionDays)
            : window.end
        let expanded = clippedRenderedDateWindow(start: expandedStart, end: expandedEnd)
        guard expanded != window else { return }

        lastRenderedWindowExpansionAt = now
        renderedDateWindow = expanded
        derivedDataSignature = nil
        if cache.isWindowScoped {
            rebuildCalendarCache(skipIfUnchanged: false, scope: .visibleWindow)
        } else {
            rebuildDerivedCalendarData(skipIfUnchanged: false)
        }
        store.appendPerformanceDiagnostic(
            String(
                format: "calendar-window-expand backward=%@ forward=%@ from_days=%ld to_days=%ld",
                shouldExpandBackward ? "yes" : "no",
                shouldExpandForward ? "yes" : "no",
                renderedDateCount(in: window),
                renderedDateCount(in: expanded)
            )
        )
        DispatchQueue.main.async {
            preserveVisibleDate(using: proxy, preferredDate: previousTopVisibleDate)
        }
    }

    private func renderedDateCount(in window: CalendarRenderedDateWindow) -> Int {
        let components = workspaceCalendar.dateComponents([.day], from: window.start, to: window.end)
        return max((components.day ?? 0) + 1, 0)
    }

    private func scrollToToday(using proxy: ScrollViewProxy, animated: Bool) {
        goToCalendarDate(defaultOpenDate, using: proxy, animated: animated)
    }

    private func prepareGoToDatePopover() {
        let normalizedDate = workspaceCalendar.startOfDay(for: topVisibleDate)
        goToDateText = DateParsers.isoDay.string(from: normalizedDate)
        goToDateYear = workspaceCalendar.component(.year, from: normalizedDate)
    }

    private func goToCalendarDate(
        _ date: Date,
        using proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
        let targetDate = workspaceCalendar.startOfDay(for: date)
        pinnedCalendarNavigationDate = targetDate
        pendingDefaultOpenDate = nil
        isStabilizingDefaultOpen = false
        cancelQueuedCalendarViewportRestoresForTargetedNavigation()
        resetRenderedDateWindow(centeredOn: targetDate)
        rebuildCalendarCache(skipIfUnchanged: false, scope: .visibleWindow)
        scheduleTargetedCalendarScroll(to: targetDate, using: proxy, animated: animated)
    }

    private func requestDefaultCalendarOpenIfNeeded(using proxy: ScrollViewProxy, animated: Bool) {
        guard calendarShouldUseDefaultOpenPosition(
            pendingOpenRequest: store.pendingCalendarOpenRequest,
            pendingRevealRequest: store.pendingCalendarRevealRequest
        ) else {
            pendingDefaultOpenDate = nil
            return
        }

        let targetDate = defaultOpenDate
        isStabilizingDefaultOpen = true
        pendingDefaultOpenDate = targetDate
        scheduleTargetedCalendarScroll(to: targetDate, using: proxy, animated: animated)
        DispatchQueue.main.async {
            applyPendingDefaultCalendarOpenIfNeeded(using: proxy)
        }
    }

    @discardableResult
    private func restorePersistedCalendarViewportIfNeeded(using proxy: ScrollViewProxy) -> Bool {
        guard pendingTargetedCalendarScroll == nil else { return true }
        guard pendingPersistedViewportRestore else { return false }
        guard calendarShouldRestorePersistedViewport(
            hasPersistedViewport: store.calendarWorkspaceViewportSnapshot.hasSavedPosition,
            pendingOpenRequest: store.pendingCalendarOpenRequest,
            pendingRevealRequest: store.pendingCalendarRevealRequest
        ) else {
            pendingPersistedViewportRestore = false
            pendingPersistedScrollOffset = nil
            return false
        }
        guard !derivedData.dayGroups.isEmpty else { return true }

        if let pendingPersistedScrollOffset {
            verticalScrollOffset = pendingPersistedScrollOffset
            verticalScrollRestoreToken &+= 1
        } else if calendarHasVisibleDate(
            topVisibleDate,
            in: derivedData.dayGroups.map(\.date),
            calendar: workspaceCalendar
        ) {
            preserveVisibleDate(using: proxy, preferredDate: topVisibleDate)
        }

        pendingPersistedViewportRestore = false
        pendingPersistedScrollOffset = nil
        return true
    }

    private func captureCalendarViewportForDataChangeIfNeeded() {
        guard pendingTargetedCalendarScroll == nil,
              store.pendingCalendarOpenRequest == nil,
              store.pendingCalendarRevealRequest == nil,
              pendingDefaultOpenDate == nil,
              !pendingPersistedViewportRestore else {
            pendingDataChangeViewportRestore = nil
            return
        }

        pendingDataChangeViewportRestore = CalendarViewportRestoreSnapshot(
            verticalScrollOffset: verticalScrollOffset,
            topVisibleDate: workspaceCalendar.startOfDay(for: topVisibleDate)
        )
    }

    private func earlierRenderedWindowStart(from start: Date, fallbackDays: Int) -> Date {
        let fallback = workspaceCalendar.date(byAdding: .day, value: -fallbackDays, to: start) ?? start
        guard !includeEmptyDays, let previousEventDate = nearestMatchingCalendarEventDate(before: start) else {
            return fallback
        }
        return min(fallback, previousEventDate)
    }

    private func laterRenderedWindowEnd(from end: Date, fallbackDays: Int) -> Date {
        let fallback = workspaceCalendar.date(byAdding: .day, value: fallbackDays, to: end) ?? end
        guard !includeEmptyDays, let nextEventDate = nearestMatchingCalendarEventDate(after: end) else {
            return fallback
        }
        return max(fallback, nextEventDate)
    }

    private func nearestMatchingCalendarEventDate(before date: Date) -> Date? {
        let boundary = workspaceCalendar.startOfDay(for: date)
        let cachedDate = cache.events
            .lazy
            .filter(matchesRenderedCalendarEventFilters)
            .map { workspaceCalendar.startOfDay(for: $0.displayDate) }
            .filter { $0 < boundary }
            .max()
        let rawMeetingDate = nearestMatchingRawMeetingDate(before: boundary)
        return [cachedDate, rawMeetingDate].compactMap { $0 }.max()
    }

    private func nearestMatchingCalendarEventDate(after date: Date) -> Date? {
        let boundary = workspaceCalendar.startOfDay(for: date)
        let cachedDate = cache.events
            .lazy
            .filter(matchesRenderedCalendarEventFilters)
            .map { workspaceCalendar.startOfDay(for: $0.displayDate) }
            .filter { $0 > boundary }
            .min()
        let rawMeetingDate = nearestMatchingRawMeetingDate(after: boundary)
        return [cachedDate, rawMeetingDate].compactMap { $0 }.min()
    }

    private func matchesRenderedCalendarEventFilters(_ event: CalendarWorkspaceEvent) -> Bool {
        matchesHiddenCalendarFilter(event)
            && matchesKindFilter(event)
            && matchesProjectFilter(event)
            && matchesResearcherFilter(event)
            && matchesDayLocationFilter(event)
            && matchesCalendarSearchFilter(event)
    }

    private func nearestMatchingRawMeetingDate(before boundary: Date) -> Date? {
        guard selectedKinds.contains(.meeting) else { return nil }
        return store.calendarMeetingRecords
            .lazy
            .filter(matchesRawMeetingFilters)
            .compactMap { DateParsers.isoDay.date(from: $0.date).map { workspaceCalendar.startOfDay(for: $0) } }
            .filter { $0 < boundary }
            .max()
    }

    private func nearestMatchingRawMeetingDate(after boundary: Date) -> Date? {
        guard selectedKinds.contains(.meeting) else { return nil }
        return store.calendarMeetingRecords
            .lazy
            .filter(matchesRawMeetingFilters)
            .compactMap { DateParsers.isoDay.date(from: $0.date).map { workspaceCalendar.startOfDay(for: $0) } }
            .filter { $0 > boundary }
            .min()
    }

    private func matchesRawMeetingFilters(_ meeting: CalendarMeetingRecord) -> Bool {
        guard selectedMeetingCategoryKeys.contains(calendarMeetingCategoryFilterKey(for: meeting.meetingType)) else {
            return false
        }
        guard let meetingDate = DateParsers.isoDay.date(from: meeting.date).map({ workspaceCalendar.startOfDay(for: $0) }) else {
            return false
        }
        if !showsCalendarHistory, meetingDate < today {
            return false
        }
        if let selectedLocation = selectedDayLocation.trimmedOrNil {
            let dayKey = DateParsers.isoDay.string(from: meetingDate)
            guard cache.dayEndLocations[dayKey]?.key == selectedLocation else {
                return false
            }
        }
        if !selectedProjectID.isEmpty,
           !rawMeetingReferencedProjectIDs(meeting).contains(selectedProjectID) {
            return false
        }
        if let selectedName = selectedResearcherName.trimmedOrNil,
           !meeting.participantNames.contains(where: { sameCalendarName($0, selectedName) }) {
            return false
        }
        return matchesRawMeetingSearchFilter(meeting)
    }

    private func rawMeetingReferencedProjectIDs(_ meeting: CalendarMeetingRecord) -> [String] {
        var projectIDs = calendarMeetingProjectIDs(meeting)
        for applicationID in meeting.applicationIDs.compactMap(\.trimmedOrNil) {
            if let projectID = cache.applicationsByID[applicationID]?.projectID?.trimmedOrNil {
                projectIDs.append(projectID)
            }
        }
        for publicationID in meeting.publicationIDs.compactMap(\.trimmedOrNil) {
            if let projectID = cache.publicationsByID[publicationID]?.projectID?.trimmedOrNil {
                projectIDs.append(projectID)
            }
        }
        for appearanceID in meeting.mediaAppearanceIDs.compactMap(\.trimmedOrNil) {
            projectIDs.append(contentsOf: store.cvMediaAppearances
                .first(where: { $0.id == appearanceID })?
                .projectIDs ?? [])
        }
        return Array(NSOrderedSet(array: projectIDs)) as? [String] ?? projectIDs
    }

    private func matchesRawMeetingSearchFilter(_ meeting: CalendarMeetingRecord) -> Bool {
        let query = SearchFilterQuery(raw: calendarSearchText)
        guard !query.isEmpty else { return true }
        let projectLabels = rawMeetingReferencedProjectIDs(meeting)
            .compactMap { cache.projectsByID[$0]?.displayName(for: language) }
            .joined(separator: " ")
        let haystack = [
            meeting.title,
            meeting.detail,
            meeting.place,
            meeting.country,
            meeting.meetingType,
            calendarMeetingCategoryDisplayName(meeting.meetingType, language: language),
            timeRangeText(start: meeting.startTime, end: meeting.endTime),
            meeting.participantNames.joined(separator: " "),
            projectLabels
        ]
        .joined(separator: " ")
        return query.matches(haystack: haystack)
    }

    @discardableResult
    private func restoreCalendarViewportAfterDataChangeIfNeeded(using proxy: ScrollViewProxy) -> Bool {
        guard pendingTargetedCalendarScroll == nil else { return true }
        guard let snapshot = pendingDataChangeViewportRestore else { return false }
        pendingDataChangeViewportRestore = nil

        guard store.pendingCalendarOpenRequest == nil,
              store.pendingCalendarRevealRequest == nil,
              pendingDefaultOpenDate == nil,
              !pendingPersistedViewportRestore else {
            return false
        }

        guard !derivedData.dayGroups.isEmpty else { return false }
        preserveVisibleDate(using: proxy, preferredDate: snapshot.topVisibleDate)
        return true
    }

    private func applyPendingDefaultCalendarOpenIfNeeded(using proxy: ScrollViewProxy) {
        guard calendarHasVisibleDate(
            pendingDefaultOpenDate,
            in: derivedData.dayGroups.map(\.date),
            calendar: workspaceCalendar
        ),
        let targetDate = pendingDefaultOpenDate else {
            return
        }

        pendingDefaultOpenDate = nil
        scheduleTargetedCalendarScroll(to: targetDate, using: proxy, animated: false)
        isStabilizingDefaultOpen = false
    }

    private func preserveVisibleDate(using proxy: ScrollViewProxy, preferredDate: Date) {
        let previousWindow = renderedDateWindow
        ensureRenderedDateWindow(including: preferredDate)
        if previousWindow != renderedDateWindow {
            // The visible-window cache only contains events and dates from its
            // previous bounds. Rebuilding derived data alone would leave the
            // requested day absent and make the fallback below jump backwards
            // to the last old day after a tab reactivation.
            if cache.isWindowScoped {
                rebuildCalendarCache(skipIfUnchanged: false, scope: .visibleWindow)
            } else {
                rebuildDerivedCalendarData(skipIfUnchanged: false)
            }
        }
        let visibleDates = derivedData.dayGroups.map(\.date)
        guard !visibleDates.isEmpty else { return }
        // Never substitute an older date when the desired focus is temporarily
        // unavailable. That would overwrite the remembered focus and cause a
        // progressively older position on each return to the calendar.
        guard let targetDate = visibleDates.first(where: { $0 >= preferredDate }) else { return }
        scrollToDate(targetDate, using: proxy, animated: false)
    }

    private func cancelQueuedCalendarViewportRestoresForTargetedNavigation() {
        pendingPersistedViewportRestore = false
        pendingPersistedScrollOffset = nil
        pendingDataChangeViewportRestore = nil
        pendingSidebarViewportRestore = nil
        pendingResizeViewportRestore = nil
        pendingResizeViewportRestoreTask?.cancel()
        pendingResizeViewportRestoreTask = nil
    }

    private func scheduleTargetedCalendarScroll(to date: Date, using proxy: ScrollViewProxy, animated: Bool) {
        let targetDate = workspaceCalendar.startOfDay(for: date)
        pendingTargetedCalendarScroll = PendingCalendarTargetedScroll(
            targetDate: targetDate,
            animated: animated
        )
        attemptTargetedCalendarScrollIfNeeded(using: proxy)
    }

    @discardableResult
    private func attemptTargetedCalendarScrollIfNeeded(using proxy: ScrollViewProxy) -> Bool {
        guard var pending = pendingTargetedCalendarScroll else { return false }
        let visibleDates = derivedData.dayGroups.map(\.date)
        if calendarHasVisibleDate(pending.targetDate, in: visibleDates, calendar: workspaceCalendar) {
            guard pending.scrollAttempts < targetedCalendarScrollMaximumCommitAttempts else {
                pendingTargetedCalendarScroll = nil
                return true
            }

            pending.attempts = 0
            pending.scrollAttempts += 1
            pendingTargetedCalendarScroll = pending
            scrollToDate(
                pending.targetDate,
                using: proxy,
                animated: pending.animated && pending.scrollAttempts == 1
            )
            let delay = targetedCalendarScrollCommitDelay(for: pending.scrollAttempts)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if pendingTargetedCalendarScroll?.targetDate == pending.targetDate {
                    _ = attemptTargetedCalendarScrollIfNeeded(using: proxy)
                }
            }
            return true
        }

        guard pending.attempts < targetedCalendarScrollMaximumAttempts else {
            pendingTargetedCalendarScroll = nil
            return true
        }

        pending.attempts += 1
        pendingTargetedCalendarScroll = pending
        let delay = 0.035 * Double(pending.attempts)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if pendingTargetedCalendarScroll?.targetDate == pending.targetDate {
                rebuildDerivedCalendarData()
                _ = attemptTargetedCalendarScrollIfNeeded(using: proxy)
            }
        }
        return true
    }

    private func targetedCalendarScrollCommitDelay(for attempt: Int) -> TimeInterval {
        switch attempt {
        case 1: return 0.04
        case 2: return 0.07
        case 3: return 0.12
        case 4: return 0.20
        case 5: return 0.32
        case 6: return 0.50
        default: return 0.80
        }
    }

    private func scrollToDate(_ date: Date, using proxy: ScrollViewProxy, animated: Bool) {
        let targetDate = workspaceCalendar.startOfDay(for: date)
        let targetID = DateParsers.isoDay.string(from: targetDate)
        let scrollAction = {
            proxy.scrollTo(targetID, anchor: .top)
        }
        DispatchQueue.main.async {
            guard isActive else { return }
            topVisibleDate = targetDate
            lastFocusedCalendarDate = targetDate
            store.calendarWorkspaceLastFocusedDate = targetDate
            isRestoringCalendarFocus = false
            if isStabilizingDefaultOpen,
               workspaceCalendar.isDate(targetDate, inSameDayAs: defaultOpenDate) {
                isStabilizingDefaultOpen = false
            }
            if animated {
                withAnimation(.easeInOut(duration: 0.18)) {
                    scrollAction()
                }
            } else {
                scrollAction()
            }
        }
    }

    @discardableResult
    private func applyPendingCalendarRevealRequestIfNeeded(using proxy: ScrollViewProxy, animated: Bool) -> Bool {
        guard isActive, let request = store.pendingCalendarRevealRequest else { return false }
        isStabilizingDefaultOpen = false
        pendingDefaultOpenDate = nil
        cancelQueuedCalendarViewportRestoresForTargetedNavigation()
        presentedSheet = nil
        presentedCopyRequest = nil
        if let date = calendarRevealTargetDate(
            request: request,
            events: cache.events,
            calendar: workspaceCalendar
        ) {
            triggerCalendarRevealPulse(for: request.eventSource, token: request.id)
            let targetDate = workspaceCalendar.startOfDay(for: date)
            pinnedCalendarNavigationDate = targetDate
            resetRenderedDateWindow(centeredOn: targetDate)
            rebuildCalendarCache(skipIfUnchanged: false, scope: .visibleWindow)
            revealCalendarEventThroughFiltersIfNeeded(request.eventSource)
            scheduleTargetedCalendarScroll(to: targetDate, using: proxy, animated: animated)
        }
        store.consumeCalendarRevealRequest()
        return true
    }

    /// Round 16: "Visa i kalendern" must show the target. When the active
    /// filters hide it, they are reset (and hidden events shown when the
    /// target itself is hidden from the calendar) before the pulse.
    private func revealCalendarEventThroughFiltersIfNeeded(_ eventSource: CalendarWorkspaceEventSource?) {
        guard let eventSource else { return }
        let matchingEvents = cache.events.filter { $0.source == eventSource }
        guard !matchingEvents.isEmpty,
              !matchingEvents.contains(where: calendarEventPassesActiveFilters) else { return }
        resetFilters()
        if matchingEvents.allSatisfy(\.isHiddenFromCalendar) {
            showsHiddenCalendarEvents = true
        }
    }

    private func calendarEventPassesActiveFilters(_ event: CalendarWorkspaceEvent) -> Bool {
        matchesHiddenCalendarFilter(event)
            && matchesKindFilter(event)
            && matchesProjectFilter(event)
            && matchesResearcherFilter(event)
            && matchesDayLocationFilter(event)
            && matchesCalendarSearchFilter(event)
    }

    private func triggerCalendarRevealPulse(for eventSource: CalendarWorkspaceEventSource?, token: UUID) {
        guard let eventSource else {
            highlightedCalendarEventSource = nil
            calendarRevealPulseToken = nil
            return
        }
        highlightedCalendarEventSource = eventSource
        calendarRevealPulseToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard calendarRevealPulseToken == token else { return }
            highlightedCalendarEventSource = nil
            calendarRevealPulseToken = nil
        }
    }

    /// F44: collects the content signals of this main-thread turn and runs
    /// one refresh for all of them when the turn is over.
    private func enqueueCalendarContentRefresh(
        update: CalendarContentUpdate?,
        using proxy: ScrollViewProxy
    ) {
        let isFirstSignalOfTurn = pendingCalendarContentRefresh == nil
        var pending = pendingCalendarContentRefresh ?? CalendarPendingContentRefresh()
        if let update {
            pending.updates.append(update)
        } else {
            pending.generationBumps += 1
        }
        pendingCalendarContentRefresh = pending
        guard isFirstSignalOfTurn else { return }
        DispatchQueue.main.async {
            guard let collected = pendingCalendarContentRefresh else { return }
            pendingCalendarContentRefresh = nil
            let startedAt = CFAbsoluteTimeGetCurrent()
            refreshCalendarImmediatelyAfterContentUpdate(
                source: collected.incrementalSource,
                pulseSource: collected.pulseSource,
                using: proxy
            )
            let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            if duration >= 12 {
                store.appendPerformanceDiagnostic(
                    String(
                        format: "calendar-change phase=view-refresh total_ms=%.2f generation_bumps=%ld updates=%ld single_record=%@",
                        duration,
                        collected.generationBumps,
                        collected.updates.count,
                        collected.incrementalSource == nil ? "no" : "yes"
                    )
                )
            }
        }
    }

    private func refreshCalendarImmediatelyAfterContentUpdate(
        source: CalendarWorkspaceEventSource? = nil,
        pulseSource: CalendarWorkspaceEventSource? = nil,
        using proxy: ScrollViewProxy
    ) {
        // Keep the reader anchored to its current day while replacing the visible
        // event cache. This is intentionally separate from a reveal request: a
        // normal edit must not navigate the user to the event's new date.
        captureCalendarViewportForDataChangeIfNeeded()
        pendingRebuildTask?.cancel()
        pendingRebuildTask = nil
        rebuildCalendarCache(skipIfUnchanged: false, scope: .visibleWindow, incrementalUpdateSource: source)
        _ = restoreCalendarViewportAfterDataChangeIfNeeded(using: proxy)
        if let pulseSource {
            triggerCalendarRevealPulse(for: pulseSource, token: UUID())
        }
    }

    private func eventRevealPulseIsActive(for event: CalendarWorkspaceEvent) -> Bool {
        highlightedCalendarEventSource == event.source
            || store.undoRevealRequest?.target.matches(calendarSource: event.source) == true
    }

    private func eventRevealPulseTriggerID(for event: CalendarWorkspaceEvent) -> UUID? {
        if highlightedCalendarEventSource == event.source {
            return calendarRevealPulseToken
        }
        return store.undoRevealRequest?.id
    }

    private func rebuildCalendarDataForFilterChange() {
        if calendarSearchText.trimmedOrNil != nil {
            if cache.isWindowScoped {
                rebuildCalendarCache(skipIfUnchanged: false, scope: .full)
            } else {
                rebuildDerivedCalendarData()
            }
        } else if !cache.isWindowScoped {
            rebuildCalendarCache(skipIfUnchanged: false, scope: .visibleWindow)
        } else {
            rebuildDerivedCalendarData()
        }
    }

    private func currentCalendarCacheSignature(scope: CalendarWorkspaceCacheBuildScope) -> CalendarWorkspaceCacheSignature {
        var hasher = Hasher()
        hasher.combine(scope == .visibleWindow ? "visible-window" : "full")
        hasher.combine(language.rawValue)
        hasher.combine(store.calendarWeekdayChoice.rawValue)
        hasher.combine(store.calendarCountryDisplayMode.rawValue)
        hasher.combine(store.holidayCountries.map(\.rawValue))
        hasher.combine(store.calendarMeetingTypeOptions)
        hasher.combine(store.calendarHiddenAutomaticEventKeys.sorted())
        hasher.combine(DateParsers.isoDay.string(from: today))
        hasher.combine(store.calendarContentGeneration)
        hasher.combine(pinnedCalendarNavigationDate.map(DateParsers.isoDay.string(from:)))
        if scope == .visibleWindow {
            hasher.combine(renderedDateWindow.map { DateParsers.isoDay.string(from: $0.start) })
            hasher.combine(renderedDateWindow.map { DateParsers.isoDay.string(from: $0.end) })
        }
        return CalendarWorkspaceCacheSignature(value: hasher.finalize())
    }

    private func currentCalendarEventSourceIndexSignature() -> CalendarWorkspaceEventSourceIndexSignature {
        var hasher = Hasher()
        hasher.combine(store.calendarContentGeneration)
        hasher.combine(DateParsers.isoDay.string(from: today))
        hasher.combine(pinnedCalendarNavigationDate.map(DateParsers.isoDay.string(from:)))
        return CalendarWorkspaceEventSourceIndexSignature(value: hasher.finalize())
    }

    /// The date environment the index entries were derived under. Task display
    /// dates depend on `today` and the range on the pinned date, so an
    /// incremental record delta is only valid while both are unchanged.
    private func currentCalendarEventSourceIndexEnvironment() -> Int {
        var hasher = Hasher()
        hasher.combine(DateParsers.isoDay.string(from: today))
        hasher.combine(pinnedCalendarNavigationDate.map(DateParsers.isoDay.string(from:)))
        return hasher.finalize()
    }

    /// Applies a single record edit to the source index without rebuilding
    /// every source. Only the record kinds the calendar autosaves publish are
    /// handled; anything else falls back to the full rebuild.
    private func applyIncrementalCalendarSourceIndexUpdate(
        source: CalendarWorkspaceEventSource,
        travelRecords: [CalendarTravelRecord],
        accommodationRecords: [CalendarAccommodationRecord],
        meetingRecords: [CalendarMeetingRecord]
    ) -> Bool {
        let calendar = workspaceCalendar
        switch source {
        case .meeting:
            return eventSourceIndex.applyDatedDelta(to: \.meetingRecords, records: meetingRecords) { meeting in
                guard let day = DateParsers.isoDay.date(from: meeting.date).map({ calendar.startOfDay(for: $0) }) else {
                    return []
                }
                return [CalendarDatedValue(day: day, value: meeting)]
            }
        case .travel:
            return eventSourceIndex.applyDatedDelta(to: \.travelRecords, records: travelRecords) { travel in
                let days = [
                    DateParsers.isoDay.date(from: travel.date),
                    DateParsers.isoDay.date(from: travel.resolvedArrivalDateString())
                ]
                .compactMap { $0.map { calendar.startOfDay(for: $0) } }
                return Set(days).map { CalendarDatedValue(day: $0, value: travel) }
            }
        case .accommodation:
            return eventSourceIndex.applyRangedDelta(to: \.accommodationRecords, records: accommodationRecords) { accommodation in
                let days = [
                    accommodation.checkInDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
                    accommodation.checkOutDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                ]
                .compactMap { $0.map { calendar.startOfDay(for: $0) } }
                guard let start = days.min(), let end = days.max() else { return [] }
                return [CalendarRangedValue(start: start, end: end, value: accommodation)]
            }
        case let .teachingTask(taskID):
            // Central tasks contribute no index entries, only their deadline
            // to the visible range; the events themselves are built from
            // store.taskItems per window. A deleted or dateless task can only
            // shrink the range, which is safe to ignore.
            guard let task = store.taskItems.first(where: { $0.id == taskID }),
                  !task.isEmpty,
                  let day = DateParsers.isoDay.date(from: task.deadline).map({ calendar.startOfDay(for: $0) }) else {
                return true
            }
            return eventSourceIndex.visibleRange.contains(day)
        default:
            return false
        }
    }

    private func currentCalendarDerivedDataSignature() -> CalendarWorkspaceDerivedDataSignature {
        var hasher = Hasher()
        hasher.combine(cacheSignature?.value ?? 0)
        hasher.combine(filterStateKey)
        hasher.combine(visibleCalendarColumns.contains(.conferences))
        hasher.combine(DateParsers.isoDay.string(from: today))
        hasher.combine(renderedDateWindow.map { DateParsers.isoDay.string(from: $0.start) })
        hasher.combine(renderedDateWindow.map { DateParsers.isoDay.string(from: $0.end) })
        return CalendarWorkspaceDerivedDataSignature(value: hasher.finalize())
    }

    private func currentCalendarFilterMetadataSignature() -> CalendarWorkspaceDerivedDataSignature {
        var hasher = Hasher()
        hasher.combine(cacheSignature?.value ?? 0)
        hasher.combine(selectedKinds.map(\.filterStorageKey).sorted())
        hasher.combine(selectedMeetingCategoryKeys.sorted())
        hasher.combine(showsHiddenCalendarEvents)
        hasher.combine(selectedProjectID)
        hasher.combine(selectedResearcherName)
        hasher.combine(selectedDayLocation)
        hasher.combine(DateParsers.isoDay.string(from: today))
        return CalendarWorkspaceDerivedDataSignature(value: hasher.finalize())
    }

    private func rebuildCalendarCache(
        skipIfUnchanged: Bool = false,
        scope: CalendarWorkspaceCacheBuildScope = .full,
        incrementalUpdateSource: CalendarWorkspaceEventSource? = nil
    ) {
        let activityLabel = scope == .visibleWindow ? "calendar-cache-visible-window" : "calendar-cache-full"
        let startedAt = store.beginMainThreadActivity(activityLabel)
        if let pinnedCalendarNavigationDate {
            ensureRenderedDateWindow(including: pinnedCalendarNavigationDate)
        } else {
            ensureRenderedDateWindow(centeredOn: pendingDefaultOpenDate ?? defaultOpenDate)
        }
        let signature = currentCalendarCacheSignature(scope: scope)
        if skipIfUnchanged, cacheSignature == signature, !cache.allDates.isEmpty {
            store.endMainThreadActivity(activityLabel, startedAt: startedAt)
            return
        }
        cacheSignature = signature

        let inputsStartedAt = CFAbsoluteTimeGetCurrent()
        let travelRecords = store.calendarTravelRecordsForRead
        let afterTravelInput = CFAbsoluteTimeGetCurrent()
        let accommodationRecords = store.calendarAccommodationRecordsForRead
        let afterAccommodationInput = CFAbsoluteTimeGetCurrent()
        let meetingRecords = store.calendarMeetingRecords
        let afterInputs = CFAbsoluteTimeGetCurrent()

        let sourceIndexStartedAt = CFAbsoluteTimeGetCurrent()
        let nextSourceIndexSignature = currentCalendarEventSourceIndexSignature()
        let nextIndexEnvironment = currentCalendarEventSourceIndexEnvironment()
        let sourceIndexRebuildLabel: String
        if eventSourceIndexSignature != nextSourceIndexSignature {
            // A single edited calendar record does not need the whole index
            // (every source, ~2000 date parses) rebuilt: when the changed
            // source is known and the date environment (today, pinned date)
            // is unchanged, only that record's entries are re-derived.
            var appliedIncremental = false
            if let incrementalUpdateSource,
               eventSourceIndexEnvironment == nextIndexEnvironment,
               !cache.allDates.isEmpty {
                appliedIncremental = applyIncrementalCalendarSourceIndexUpdate(
                    source: incrementalUpdateSource,
                    travelRecords: travelRecords,
                    accommodationRecords: accommodationRecords,
                    meetingRecords: meetingRecords
                )
            }
            if !appliedIncremental {
                eventSourceIndex = buildCalendarWorkspaceEventSourceIndex(
                    store: store,
                    calendar: workspaceCalendar,
                    today: today,
                    travelRecords: travelRecords,
                    accommodationRecords: accommodationRecords,
                    meetingRecords: meetingRecords,
                    additionalDates: pinnedCalendarNavigationDate.map { [$0] } ?? []
                )
                eventSourceIndexEnvironment = nextIndexEnvironment
            }
            eventSourceIndexSignature = nextSourceIndexSignature
            sourceIndexRebuildLabel = appliedIncremental ? "incremental" : "yes"
        } else {
            sourceIndexRebuildLabel = "no"
        }
        let afterSourceIndex = CFAbsoluteTimeGetCurrent()

        let visibleRange = eventSourceIndex.visibleRange
        let fullRangeStart = visibleRange.lowerBound
        let fullRangeEnd = visibleRange.upperBound
        var rangeStart: Date
        var rangeEnd: Date
        if scope == .visibleWindow, let renderedDateWindow {
            rangeStart = max(fullRangeStart, renderedDateWindow.start)
            rangeEnd = min(fullRangeEnd, renderedDateWindow.end)
        } else {
            rangeStart = fullRangeStart
            rangeEnd = fullRangeEnd
        }
        if rangeStart > rangeEnd {
            rangeStart = fullRangeStart
            rangeEnd = fullRangeEnd
        }
        let allDates = calendarDates(from: rangeStart, to: rangeEnd, calendar: workspaceCalendar)
        let indexedSources = eventSourceIndex.slice(from: rangeStart, to: rangeEnd)
        let afterSourceSlice = CFAbsoluteTimeGetCurrent()
        let rebuiltEvents = buildFootprintCalendarEvents(
            store: store,
            language: language,
            displayedMonthStart: rangeStart,
            displayedMonthEnd: rangeEnd,
            calendar: workspaceCalendar,
            travelRecords: indexedSources.travelRecords,
            accommodationRecords: indexedSources.accommodationRecords,
            meetingRecords: indexedSources.meetingRecords,
            taskDisplayPolicy: .rollOverPastDue,
            indexedSources: indexedSources
        )
        .filter { $0.kind != .holiday }
        .sorted(by: calendarEventSort)
        let afterEvents = CFAbsoluteTimeGetCurrent()

        let rebuiltHolidaysByDay = Dictionary(grouping: holidaysInCalendarRange(
            from: rangeStart,
            to: rangeEnd,
            countries: store.holidayCountries,
            calendar: workspaceCalendar
        )) { holiday in
            DateParsers.isoDay.string(from: workspaceCalendar.startOfDay(for: holiday.date))
        }
        let afterHolidays = CFAbsoluteTimeGetCurrent()

        let allTravelDays = travelRecords
            .compactMap { record -> (record: CalendarTravelRecord, sortDate: Date, day: Date, location: CalendarDayLocation)? in
                guard let sortDate = record.resolvedArrivalDateTime(calendar: workspaceCalendar) else { return nil }
                guard let location = calendarDayLocation(
                    city: record.toCity,
                    country: record.toCountry,
                    language: language,
                    countryDisplayMode: store.calendarCountryDisplayMode
                ) else { return nil }
                return (record, sortDate, workspaceCalendar.startOfDay(for: sortDate), location)
            }
            .sorted {
                calendarTravelLocationSort($0.record, $1.record, calendar: workspaceCalendar)
            }
        var rebuiltDayEndLocations: [String: CalendarDayLocation] = [:]
        var lastKnownLocation: CalendarDayLocation? = nil
        var travelIndex = 0

        for date in allDates {
            while travelIndex < allTravelDays.count, allTravelDays[travelIndex].day <= date {
                lastKnownLocation = allTravelDays[travelIndex].location
                travelIndex += 1
            }
            if let lastKnownLocation {
                rebuiltDayEndLocations[DateParsers.isoDay.string(from: date)] = lastKnownLocation
            }
        }
        let afterLocations = CFAbsoluteTimeGetCurrent()

        let dateFormatter = calendarDateLabelFormatter(format: "d MMMM")
        let weekdayFormatter = calendarDateLabelFormatter(format: "EEEE")
        var rebuiltDateLabelsByDay: [String: String] = [:]
        var rebuiltWeekdayLabelsByDay: [String: String] = [:]
        rebuiltDateLabelsByDay.reserveCapacity(allDates.count)
        rebuiltWeekdayLabelsByDay.reserveCapacity(allDates.count)
        for date in allDates {
            let key = DateParsers.isoDay.string(from: date)
            rebuiltDateLabelsByDay[key] = dateText(for: date, formatter: dateFormatter)
            rebuiltWeekdayLabelsByDay[key] = weekdayText(for: date, formatter: weekdayFormatter)
        }
        let afterDateLabels = CFAbsoluteTimeGetCurrent()

        cache = CalendarWorkspaceCache(
            allDates: allDates,
            events: rebuiltEvents,
            holidaysByDay: rebuiltHolidaysByDay,
            dayEndLocations: rebuiltDayEndLocations,
            dateLabelsByDay: rebuiltDateLabelsByDay,
            weekdayLabelsByDay: rebuiltWeekdayLabelsByDay,
            projectOptions: store.projectsForRead
                .map { ($0.id, $0.displayName(for: language)) }
                .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending },
            researcherOptions: store.publicationAuthorsForRead
                .map(\.displayName)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            applicationsByID: calendarLookupByID(store.applicationsForRead),
            organizationsByID: calendarLookupByID(store.organizationsForCongressRead),
            projectsByID: calendarLookupByID(store.projectsForRead),
            publicationsByID: calendarLookupByID(store.publicationRecordsForRead),
            teachingAssignmentsByID: calendarLookupByID(store.teachingAssignments),
            teachingCoursesByID: calendarLookupByID(store.teachingCourses),
            doctoralCandidatesByID: calendarLookupByID(store.doctoralCandidates),
            teachingTasksByID: calendarLookupByID(store.teachingWorkspaceTasks),
            reviewEntriesByID: calendarLookupByID(store.cvReviewEntries),
            publicationAuthorsByID: calendarLookupByID(store.publicationAuthorsForRead),
            travelRecordsByID: calendarLookupByID(travelRecords),
            accommodationRecordsByID: calendarLookupByID(accommodationRecords),
            meetingRecordsByID: calendarLookupByID(meetingRecords),
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            isWindowScoped: scope == .visibleWindow
        )
        store.recordCacheProfile(
            scope: "calendar",
            cacheName: scope == .visibleWindow ? "visible-window-input" : "workspace",
            itemCount: rebuiltEvents.count,
            startedAt: startedAt,
            detail: "dates=\(allDates.count) index_rebuilt=\(sourceIndexRebuildLabel) slice={\(indexedSources.diagnosticSummary)}"
        )
        let afterCacheAssign = CFAbsoluteTimeGetCurrent()
        rebuildCalendarRenderMetadataCache()
        let afterRenderMetadata = CFAbsoluteTimeGetCurrent()
        rebuildDerivedCalendarData(skipIfUnchanged: false)
        let afterDerived = CFAbsoluteTimeGetCurrent()
        store.endMainThreadActivity(activityLabel, startedAt: startedAt)
        let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        if duration >= 80 {
            store.appendPerformanceDiagnostic(
                String(
                    format: "calendar-cache-rebuild scope=%@ events=%ld dates=%ld index_rebuilt=%@ source_index_ms=%.2f source_slice_ms=%.2f inputs_ms=%.2f events_ms=%.2f holidays_ms=%.2f locations_ms=%.2f labels_ms=%.2f assign_ms=%.2f render_meta_ms=%.2f derived_ms=%.2f total_ms=%.2f source_index={%@} slice={%@} inputs={travel_ms=%.2f accommodation_ms=%.2f meetings_ms=%.2f}",
                    scope == .visibleWindow ? "visible-window" : "full",
                    rebuiltEvents.count,
                    allDates.count,
                    sourceIndexRebuildLabel,
                    (afterSourceIndex - sourceIndexStartedAt) * 1000,
                    (afterSourceSlice - afterSourceIndex) * 1000,
                    (afterInputs - inputsStartedAt) * 1000,
                    (afterEvents - afterSourceSlice) * 1000,
                    (afterHolidays - afterEvents) * 1000,
                    (afterLocations - afterHolidays) * 1000,
                    (afterDateLabels - afterLocations) * 1000,
                    (afterCacheAssign - afterDateLabels) * 1000,
                    (afterRenderMetadata - afterCacheAssign) * 1000,
                    (afterDerived - afterRenderMetadata) * 1000,
                    duration,
                    eventSourceIndex.diagnosticSummary,
                    indexedSources.diagnosticSummary,
                    (afterTravelInput - inputsStartedAt) * 1000,
                    (afterAccommodationInput - afterTravelInput) * 1000,
                    (afterInputs - afterAccommodationInput) * 1000
                )
            )
        }
    }

    private func rebuildCalendarRenderMetadataCache() {
        var projectReferencesByEventID: [String: [(id: String, label: String)]] = [:]
        var visibleDetailTextByEventID: [String: String] = [:]
        var detailLinkPresentationByEventID: [String: CalendarDetailLinkPresentation] = [:]
        var searchTextByEventID: [String: String] = [:]
        var sourceFieldTextBySource: [CalendarWorkspaceEventSource: String] = [:]

        for event in cache.events {
            let projectReferences = uncachedProjectReferences(for: event)
            projectReferencesByEventID[event.id] = projectReferences

            let visibleDetailText = calendarWorkspaceVisibleDetailText(for: event, language: language)
            visibleDetailTextByEventID[event.id] = visibleDetailText
            detailLinkPresentationByEventID[event.id] = calendarDetailLinkPresentation(from: visibleDetailText)
            let sourceFieldText: String
            if let cachedSourceFieldText = sourceFieldTextBySource[event.source] {
                sourceFieldText = cachedSourceFieldText
            } else {
                sourceFieldText = calendarSourceFieldSearchText(for: event)
                sourceFieldTextBySource[event.source] = sourceFieldText
            }
            searchTextByEventID[event.id] = calendarSearchText(
                for: event,
                projectReferences: projectReferences,
                sourceFieldText: sourceFieldText
            )
        }

        cache.projectReferencesByEventID = projectReferencesByEventID
        cache.visibleDetailTextByEventID = visibleDetailTextByEventID
        cache.detailLinkPresentationByEventID = detailLinkPresentationByEventID
        cache.searchTextByEventID = searchTextByEventID
        rebuildCalendarListDetailCache()
    }

    /// The list rows' detail lines for rows split into parts. Rebuilt with
    /// the other row texts and when a "Visa i raden" setting changes, so the
    /// rows themselves only look the text up.
    private func rebuildCalendarListDetailCache(hiddenKinds newHiddenKinds: Set<CalendarListDetailKind>? = nil) {
        var listDetailPresentationByEventID: [String: CalendarDetailLinkPresentation] = [:]
        let hiddenKinds = newHiddenKinds ?? hiddenCalendarRowDetailKinds
        for event in cache.events where event.detailParts != nil {
            listDetailPresentationByEventID[event.id] = calendarDetailLinkPresentation(
                from: calendarListVisibleDetailText(for: event, hiddenKinds: hiddenKinds, language: language)
            )
        }
        cache.listDetailPresentationByEventID = listDetailPresentationByEventID
    }

    private func listDetailLinkPresentation(for event: CalendarWorkspaceEvent) -> CalendarDetailLinkPresentation {
        guard event.detailParts != nil else {
            return detailLinkPresentation(for: event)
        }
        return cache.listDetailPresentationByEventID[event.id]
            ?? calendarDetailLinkPresentation(
                from: calendarListVisibleDetailText(
                    for: event,
                    hiddenKinds: hiddenCalendarRowDetailKinds,
                    language: language
                )
            )
    }

    private func rebuildDerivedCalendarData(skipIfUnchanged: Bool = true) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        if let pinnedNavigationDate = pinnedCalendarNavigationDate {
            ensureRenderedDateWindow(including: pinnedNavigationDate)
        } else {
            ensureRenderedDateWindow(centeredOn: pendingDefaultOpenDate ?? defaultOpenDate)
        }
        let signature = currentCalendarDerivedDataSignature()
        if skipIfUnchanged, derivedDataSignature == signature {
            return
        }
        derivedDataSignature = signature

        let meetingOptionsStartedAt = CFAbsoluteTimeGetCurrent()
        let mediaCategoryNames = store.cvMediaAppearances.contains(where: { $0.date.trimmedOrNil != nil })
            ? ["Övrigt"]
            : []
        let meetingOptions = calendarMeetingCategoryFilterNames(
            from: store.calendarKnownMeetingCategories + mediaCategoryNames
        ).map { rawName in
            CalendarMeetingCategoryFilterOption(
                rawName: rawName,
                title: calendarMeetingCategoryDisplayName(rawName, language: language)
            )
        }
        synchronizeMeetingCategoryFilters(availableKeys: Set(meetingOptions.map(\.id)))
        let afterMeetingOptions = CFAbsoluteTimeGetCurrent()

        let visibleKindEvents = cache.events
            .filter(matchesHiddenCalendarFilter)
            .filter(matchesKindFilter)
        let afterKindFilter = CFAbsoluteTimeGetCurrent()

        let metadataSignature = currentCalendarFilterMetadataSignature()
        let projectOptions: [(id: String, label: String)]
        let researcherOptions: [String]
        let dayLocationOptions: [(String, String)]
        let resolvedMeetingOptions: [CalendarMeetingCategoryFilterOption]
        let reusedFilterMetadata: Bool
        if filterMetadataSignature == metadataSignature {
            projectOptions = cachedProjectFilterOptions
            researcherOptions = cachedResearcherFilterOptions
            dayLocationOptions = cachedDayLocationFilterOptions
            resolvedMeetingOptions = cachedMeetingCategoryFilterOptions
            reusedFilterMetadata = true
        } else {
            let projectCandidates = visibleKindEvents
                .filter(matchesResearcherFilter)
                .filter(matchesDayLocationFilter)
                .flatMap(projectReferences(for:))
            var seenProjects = Set<String>()
            projectOptions = projectCandidates
                .filter { seenProjects.insert($0.id).inserted }
                .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }

            let researcherCandidates = visibleKindEvents
                .filter(matchesProjectFilter)
                .filter(matchesDayLocationFilter)
                .flatMap(researcherReferences(for:))
            var seenResearchers = Set<String>()
            researcherOptions = researcherCandidates
                .filter { seenResearchers.insert($0).inserted }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

            dayLocationOptions = Array(Set(cache.dayEndLocations.values))
                .sorted { displayCalendarPlaceText($0.label).localizedStandardCompare(displayCalendarPlaceText($1.label)) == .orderedAscending }
                .map { ($0.key, $0.label) }
            resolvedMeetingOptions = meetingOptions
            filterMetadataSignature = metadataSignature
            cachedProjectFilterOptions = projectOptions
            cachedResearcherFilterOptions = researcherOptions
            cachedDayLocationFilterOptions = dayLocationOptions
            cachedMeetingCategoryFilterOptions = resolvedMeetingOptions
            reusedFilterMetadata = false
        }
        let afterMetadata = CFAbsoluteTimeGetCurrent()

        let searchQuery = SearchFilterQuery(raw: calendarSearchText)
        let filteredEvents = visibleKindEvents
            .filter(matchesProjectFilter)
            .filter(matchesResearcherFilter)
            .filter(matchesDayLocationFilter)
            .filter { matchesCalendarSearchFilter($0, query: searchQuery) }
        let afterFilters = CFAbsoluteTimeGetCurrent()
        let groupedByDay = Dictionary(grouping: filteredEvents) { event in
            workspaceCalendar.startOfDay(for: event.displayDate)
        }
        let afterGrouping = CFAbsoluteTimeGetCurrent()

        let pinnedNavigationDate = pinnedCalendarNavigationDate.map { workspaceCalendar.startOfDay(for: $0) }
        let pendingDefaultNavigationDate = pendingDefaultOpenDate.map { workspaceCalendar.startOfDay(for: $0) }
        // A day with only congresses is empty when the Conferences column is hidden.
        let showsConferenceColumn = visibleCalendarColumns.contains(.conferences)
        let shouldIncludeEmptyDays = includeEmptyDays && calendarSearchText.trimmedOrNil == nil
        let candidateDates: [Date]
        if shouldIncludeEmptyDays {
            var uniqueDates = Set(cache.allDates.filter(isDateInsideRenderedWindow))
            if let pendingDefaultNavigationDate {
                uniqueDates.insert(pendingDefaultNavigationDate)
            }
            if let pinnedNavigationDate {
                uniqueDates.insert(pinnedNavigationDate)
            }
            candidateDates = uniqueDates.sorted()
        } else {
            var uniqueDates = Set(groupedByDay.keys)
            if let pinnedNavigationDate {
                uniqueDates.insert(pinnedNavigationDate)
            }
            if let pendingDefaultNavigationDate {
                uniqueDates.insert(pendingDefaultNavigationDate)
            }
            candidateDates = calendarFilteredCandidateDates(
                uniqueDates,
                isSearchActive: calendarSearchText.trimmedOrNil != nil,
                isInsideRenderedWindow: isDateInsideRenderedWindow
            )
        }
        var previousVisibleDate: Date?
        let dayGroups = candidateDates.compactMap { date -> CalendarWorkspaceDayGroup? in
            let isPinnedNavigationDate = pinnedNavigationDate.map {
                workspaceCalendar.isDate(date, inSameDayAs: $0)
            } ?? false
            let isPendingDefaultNavigationDate = pendingDefaultNavigationDate.map {
                workspaceCalendar.isDate(date, inSameDayAs: $0)
            } ?? false
            let isNavigationAnchorDate = isPinnedNavigationDate || isPendingDefaultNavigationDate
            if !isNavigationAnchorDate, !showsCalendarHistory, date < today {
                return nil
            }
            let key = DateParsers.isoDay.string(from: date)
            let groupedEvents = groupedByDay[date, default: []]
            // Congresses belong in the Conferences column; when the user hides
            // that column they are hidden too (round 16's "show as rows" undone).
            let separatedEvents = groupedEvents.reduce(into: (events: [CalendarWorkspaceEvent](), conferenceEvents: [CalendarWorkspaceEvent]())) { result, event in
                if isStandaloneCongressEvent(event) {
                    result.conferenceEvents.append(event)
                } else {
                    result.events.append(event)
                }
            }
            let holidays = cache.holidaysByDay[key, default: []]
            let dayEndLocation = cache.dayEndLocations[key]?.label ?? ""
            let hasVisibleContent = !separatedEvents.events.isEmpty
                || (showsConferenceColumn && !separatedEvents.conferenceEvents.isEmpty)
            if !isNavigationAnchorDate, !hasVisibleContent, !shouldIncludeEmptyDays {
                return nil
            }
            if let selectedLocation = selectedDayLocation.trimmedOrNil,
               cache.dayEndLocations[key]?.key != selectedLocation,
               !isNavigationAnchorDate,
               !hasVisibleContent {
                return nil
            }
            let topSpacing = weekSpacingBeforeGroup(current: date, previous: previousVisibleDate)
            let startsWeek = previousVisibleDate == nil || topSpacing > 0
            previousVisibleDate = date
            return CalendarWorkspaceDayGroup(
                id: key,
                date: date,
                events: separatedEvents.events,
                conferenceEvents: separatedEvents.conferenceEvents,
                holidays: holidays,
                dateLabel: cache.dateLabelsByDay[key] ?? dateText(for: date),
                weekdayLabel: cache.weekdayLabelsByDay[key] ?? weekdayText(for: date),
                dayEndLocation: dayEndLocation,
                isPast: date < today,
                topSpacing: topSpacing,
                startsWeek: startsWeek
            )
        }
        let afterDayGroups = CFAbsoluteTimeGetCurrent()

        derivedData = CalendarWorkspaceDerivedData(
            dayGroups: dayGroups,
            projectFilterOptions: projectOptions,
            researcherFilterOptions: researcherOptions,
            dayLocationFilterOptions: dayLocationOptions,
            meetingCategoryFilterOptions: resolvedMeetingOptions
        )
        calendarDerivedDataRevision &+= 1
        let afterAssign = CFAbsoluteTimeGetCurrent()
        let snapshot = calendarVisibleWindowSnapshot(from: dayGroups)
        visibleWindowSnapshot = snapshot
        store.recordCacheProfile(
            scope: "calendar",
            cacheName: "visible-window",
            itemCount: snapshot.eventCount + snapshot.conferenceEventCount,
            startedAt: startedAt,
            detail: "days=\(snapshot.dayCount) range=\(snapshot.startDay)...\(snapshot.endDay)"
        )
        let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        if duration >= 24 {
            store.appendPerformanceDiagnostic(
                String(
                    format: "calendar-derived-rebuild events=%ld visible_kind=%ld filtered=%ld days=%ld empty=%@ history=%@ metadata_reused=%@ meeting_options_ms=%.2f kind_filter_ms=%.2f metadata_ms=%.2f filters_ms=%.2f grouping_ms=%.2f day_groups_ms=%.2f assign_ms=%.2f window=%@ total_ms=%.2f",
                    cache.events.count,
                    visibleKindEvents.count,
                    filteredEvents.count,
                    dayGroups.count,
                    includeEmptyDays ? "yes" : "no",
                    showsCalendarHistory ? "yes" : "no",
                    reusedFilterMetadata ? "yes" : "no",
                    (afterMeetingOptions - meetingOptionsStartedAt) * 1000,
                    (afterKindFilter - afterMeetingOptions) * 1000,
                    (afterMetadata - afterKindFilter) * 1000,
                    (afterFilters - afterMetadata) * 1000,
                    (afterGrouping - afterFilters) * 1000,
                    (afterDayGroups - afterGrouping) * 1000,
                    (afterAssign - afterDayGroups) * 1000,
                    renderedDateWindow.map {
                        "\(DateParsers.isoDay.string(from: $0.start))...\(DateParsers.isoDay.string(from: $0.end))"
                    } ?? "nil",
                    duration
                )
            )
        }
    }

    private func copyRequest(for event: CalendarWorkspaceEvent) -> CalendarEventCopyRequest? {
        switch event.source {
        case let .travel(travelID):
            guard let record = cache.travelRecordsByID[travelID] else { return nil }
            return CalendarEventCopyRequest(
                source: event.source,
                title: event.title,
                date: copiedDateString(from: record.date),
                startTime: record.departureTime,
                endTime: record.arrivalTime,
                allowsTimeEditing: true
            )
        case let .accommodation(accommodationID):
            guard let record = cache.accommodationRecordsByID[accommodationID] else { return nil }
            return CalendarEventCopyRequest(
                source: event.source,
                title: event.title,
                date: copiedDateString(from: record.checkInDate),
                startTime: record.checkInTime,
                endTime: record.checkOutTime,
                allowsTimeEditing: true
            )
        case let .meeting(meetingID):
            guard let record = cache.meetingRecordsByID[meetingID] else { return nil }
            return CalendarEventCopyRequest(
                source: event.source,
                title: event.title,
                date: copiedDateString(from: record.date),
                startTime: record.startTime,
                endTime: record.endTime,
                allowsTimeEditing: true
            )
        case let .teachingTask(taskID):
            let deadline = centralTaskItem(for: taskID)?.deadline
                ?? cache.teachingTasksByID[taskID]?.deadline
            guard let deadline else { return nil }
            return CalendarEventCopyRequest(
                source: event.source,
                title: event.title,
                date: copiedDateString(from: deadline),
                startTime: "",
                endTime: "",
                allowsTimeEditing: false
            )
        case let .organizationTask(_, taskID):
            guard let task = organizationTaskItem(for: taskID) else { return nil }
            return CalendarEventCopyRequest(
                source: event.source,
                title: event.title,
                date: copiedDateString(from: task.deadline),
                startTime: "",
                endTime: "",
                allowsTimeEditing: false
            )
        case let .projectTask(_, taskID):
            guard let task = projectTaskItem(for: taskID) else { return nil }
            return CalendarEventCopyRequest(
                source: event.source,
                title: event.title,
                date: copiedDateString(from: task.deadline),
                startTime: "",
                endTime: "",
                allowsTimeEditing: false
            )
        case let .publicationTask(_, taskID):
            guard let task = publicationTaskItem(for: taskID) else { return nil }
            return CalendarEventCopyRequest(
                source: event.source,
                title: event.title,
                date: copiedDateString(from: task.deadline),
                startTime: "",
                endTime: "",
                allowsTimeEditing: false
            )
        default:
            return nil
        }
    }

    private func copiedDateString(from raw: String) -> String {
        let fallback = workspaceCalendar.date(byAdding: .day, value: 7, to: today) ?? today
        guard let date = DateParsers.isoDay.date(from: raw),
              let shifted = workspaceCalendar.date(byAdding: .day, value: 7, to: date) else {
            return DateParsers.isoDay.string(from: fallback)
        }
        return DateParsers.isoDay.string(from: shifted)
    }

    private func duplicateEvent(for request: CalendarEventCopyRequest) {
        let todayString = DateParsers.isoDay.string(from: workspaceCalendar.startOfDay(for: Date()))
        switch request.source {
        case let .travel(travelID):
            guard let original = cache.travelRecordsByID[travelID] else { return }
            var records = store.calendarTravelRecords
            var copy = original
            copy.id = UUID().uuidString
            copy.date = request.date
            copy.arrivalDate = ""
            copy.departureTime = request.startTime
            copy.arrivalTime = request.endTime
            copy.normalize()
            records.append(copy)
            store.autosaveCalendarTravelRecords(records)
            store.syncCalendarTravelWithCongressPlan(previous: nil, current: copy)
        case let .accommodation(accommodationID):
            guard let original = cache.accommodationRecordsByID[accommodationID] else { return }
            var records = store.calendarAccommodationRecords
            var copy = original
            copy.id = UUID().uuidString
            let originalStart = DateParsers.isoDay.date(from: original.checkInDate)
            let originalEnd = DateParsers.isoDay.date(from: original.checkOutDate)
            copy.checkInDate = request.date
            if let originalStart,
               let originalEnd,
               let newStart = DateParsers.isoDay.date(from: request.date),
               let newEnd = workspaceCalendar.date(
                    byAdding: .day,
                    value: workspaceCalendar.dateComponents([.day], from: originalStart, to: originalEnd).day ?? 0,
                    to: newStart
               ) {
                copy.checkOutDate = DateParsers.isoDay.string(from: newEnd)
            } else {
                copy.checkOutDate = request.date
            }
            copy.checkInTime = request.startTime
            copy.checkOutTime = request.endTime
            copy.normalize()
            records.append(copy)
            store.autosaveCalendarAccommodationRecords(records)
            if let organizationID = copy.congressOrganizationID.trimmedOrNil,
               let congressID = copy.congressID.trimmedOrNil {
                store.markCongressAsAttendingIfNeeded(
                    organizationID: organizationID,
                    congressID: congressID
                )
            }
        case let .meeting(meetingID):
            guard let original = cache.meetingRecordsByID[meetingID] else { return }
            var records = store.calendarMeetingRecords
            var copy = original
            copy.id = UUID().uuidString
            copy.date = request.date
            copy.startTime = request.startTime
            copy.endTime = request.endTime
            copy.normalize()
            records.append(copy)
            store.autosaveCalendarMeetingRecords(records)
        case let .teachingTask(taskID):
            if let original = centralTaskItem(for: taskID) {
                store.saveTaskItem(duplicatedCalendarCentralTask(
                    original,
                    deadline: request.date,
                    todayString: todayString
                ))
                return
            }
            guard let original = store.teachingWorkspaceTasks.first(where: { $0.id == taskID }) else { return }
            var tasks = store.teachingWorkspaceTasks
            var copy = original
            copy.id = UUID().uuidString
            copy.createdOn = todayString
            copy.updatedOn = todayString
            copy.deadline = request.date
            copy.completedOn = nil
            copy.normalize()
            tasks.append(copy)
            store.autosaveTeachingWorkspaceTasks(tasks)
        case let .organizationTask(organizationID, taskID):
            guard var organization = store.organizations.first(where: { $0.id == organizationID }),
                  let original = organization.projectTasks.first(where: { $0.id == taskID }) else { return }
            var copy = original
            copy.id = UUID().uuidString
            copy.createdOn = todayString
            copy.updatedOn = todayString
            copy.deadline = request.date
            copy.completedOn = nil
            copy.normalize()
            organization.projectTasks = (organization.projectTasks + [copy])
                .map {
                    var normalized = $0
                    normalized.normalize()
                    return normalized
                }
                .filter { !$0.isEmpty }
            store.autosaveOrganizationProjectTasks(organization)
        case let .projectTask(projectID, taskID):
            guard var project = store.projects.first(where: { $0.id == projectID }),
                  !project.isEditingLocked,
                  let original = project.projectTasks.first(where: { $0.id == taskID }) else { return }
            var copy = original
            copy.id = UUID().uuidString
            copy.createdOn = todayString
            copy.updatedOn = todayString
            copy.deadline = request.date
            copy.completedOn = nil
            copy.normalize()
            project.projectTasks = (project.projectTasks + [copy])
                .map {
                    var normalized = $0
                    normalized.normalize()
                    return normalized
                }
                .filter { !$0.isEmpty }
            store.autosaveProjectRecord(project, previousID: projectID)
        case let .publicationTask(publicationID, taskID):
            guard var publication = store.publications.first(where: { $0.id == publicationID }),
                  !publication.isEditingLocked,
                  let original = publication.publicationTasks.first(where: { $0.id == taskID }) else { return }
            var copy = original
            copy.id = UUID().uuidString
            copy.createdOn = todayString
            copy.updatedOn = todayString
            copy.deadline = request.date
            copy.completedOn = nil
            copy.normalize()
            publication.publicationTasks = normalizedPublicationTaskItems(publication.publicationTasks + [copy])
                .filter { !$0.isEmpty }
            store.autosavePublication(publication)
        default:
            break
        }
    }

    private func deleteAction(for event: CalendarWorkspaceEvent) -> (() -> Void)? {
        switch event.source {
        case .meeting, .travel, .accommodation, .teachingTask, .organizationTask, .projectTask, .publicationTask:
            return {
                deleteEvent(source: event.source)
            }
        default:
            return nil
        }
    }

    private func deleteEvent(source: CalendarWorkspaceEventSource) {
        store.deleteCalendarEvent(source: source)
    }

    private func requestCalendarEventDeletion(_ event: CalendarWorkspaceEvent) {
        guard deleteAction(for: event) != nil else { return }
        pendingDeletionEventID = event.id
    }

    private func organizationTaskItem(for taskID: String) -> ProjectTaskItem? {
        store.organizations.lazy.compactMap { organization in
            organization.projectTasks.first(where: { $0.id == taskID })
        }
        .first
    }

    private func projectTaskItem(for taskID: String) -> ProjectTaskItem? {
        store.projects.lazy.compactMap { project in
            project.projectTasks.first(where: { $0.id == taskID })
        }.first
    }

    private func publicationTaskItem(for taskID: String) -> PublicationTaskItem? {
        store.publications.lazy.compactMap { publication in
            publication.publicationTasks.first(where: { $0.id == taskID })
        }.first
    }

    private func resetFilters() {
        selectedKinds = defaultSelectedKinds
        selectedMeetingCategoryKeys = defaultMeetingCategoryFilterKeys
        knownMeetingCategoryFilterKeys = defaultMeetingCategoryFilterKeys
        includeEmptyDays = true
        showsCalendarHistory = true
        showsHiddenCalendarEvents = false
        calendarSearchText = ""
        selectedProjectID = ""
        selectedResearcherName = ""
        selectedDayLocation = ""
    }

    private func showOnlyCategory(_ kind: CalendarWorkspaceEventKind) {
        let selection = calendarExclusiveCategorySelection(
            for: kind,
            meetingCategoryKeys: defaultMeetingCategoryFilterKeys
        )
        selectedKinds = selection.selectedKinds
        selectedMeetingCategoryKeys = selection.selectedMeetingCategoryKeys
        includeEmptyDays = false
    }

    private func showOnlyMeetingCategory(_ option: CalendarMeetingCategoryFilterOption) {
        let selection = calendarExclusiveMeetingCategorySelection(for: option.id)
        selectedKinds = selection.selectedKinds
        selectedMeetingCategoryKeys = selection.selectedMeetingCategoryKeys
        includeEmptyDays = false
    }

    private func synchronizeMeetingCategoryFilters(availableKeys: Set<String>? = nil) {
        let availableKeys = availableKeys ?? defaultMeetingCategoryFilterKeys
        guard !availableKeys.isEmpty else {
            selectedMeetingCategoryKeys = []
            knownMeetingCategoryFilterKeys = []
            return
        }
        guard selectedKinds.contains(.meeting) else {
            selectedMeetingCategoryKeys = []
            knownMeetingCategoryFilterKeys = availableKeys
            return
        }

        let hadAllPreviousCategoriesSelected =
            !knownMeetingCategoryFilterKeys.isEmpty
            && selectedMeetingCategoryKeys == knownMeetingCategoryFilterKeys

        let updatedSelection: Set<String>
        if knownMeetingCategoryFilterKeys.isEmpty || selectedMeetingCategoryKeys.isEmpty || hadAllPreviousCategoriesSelected {
            updatedSelection = availableKeys
        } else {
            let retained = selectedMeetingCategoryKeys.intersection(availableKeys)
            updatedSelection = retained.isEmpty ? availableKeys : retained
        }

        selectedMeetingCategoryKeys = updatedSelection
        knownMeetingCategoryFilterKeys = availableKeys
    }

    private func applyPendingCalendarOpenRequestIfNeeded() {
        guard isActive, let request = store.pendingCalendarOpenRequest else { return }
        isStabilizingDefaultOpen = false
        pendingDefaultOpenDate = nil
        switch request.kind {
        case .todo:
            presentedSheet = CalendarWorkspaceSheet(kind: .todo, recordID: request.recordID)
        case .travel:
            presentedSheet = CalendarWorkspaceSheet(kind: .travel, recordID: request.recordID)
        case .accommodation:
            presentedSheet = CalendarWorkspaceSheet(kind: .accommodation, recordID: request.recordID)
        case .meeting:
            presentedSheet = CalendarWorkspaceSheet(kind: .meeting, recordID: request.recordID)
        case let .projectTask(projectID):
            presentedSheet = CalendarWorkspaceSheet(kind: .projectTask(projectID: projectID), recordID: request.recordID)
        case let .publicationTask(publicationID):
            presentedSheet = CalendarWorkspaceSheet(kind: .publicationTask(publicationID: publicationID), recordID: request.recordID)
        }
        store.consumeCalendarOpenRequest()
    }

    private func scheduleCalendarCacheRebuild(
        skipIfUnchanged: Bool = true,
        delay: TimeInterval = 0.2,
        scope: CalendarWorkspaceCacheBuildScope = .visibleWindow,
        afterRebuild: (() -> Void)? = nil
    ) {
        pendingRebuildTask?.cancel()
        let task = DispatchWorkItem {
            pendingRebuildTask = nil
            rebuildCalendarCache(skipIfUnchanged: skipIfUnchanged, scope: scope)
            afterRebuild?()
        }
        pendingRebuildTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func rebuildCalendarCacheAfterPeriodicCheckIfNeeded(at date: Date) {
        guard isActive else { return }
        guard date.timeIntervalSince(lastPeriodicCalendarCheckDate) >= periodicCalendarCheckInterval else { return }
        lastPeriodicCalendarCheckDate = date
        scheduleCalendarCacheRebuild()
    }
}

// MARK: - Week view

/// The week view (CalendarWeekView.swift) reads the same filtered day groups
/// as the list and reuses the list's colours, icons, rings, detail sheet and
/// context menus. Its model is rebuilt only when the shown week or the
/// filtered data changes.
extension CalendarWorkspaceView {
    /// The first day of the week the week view shows.
    private var calendarShownWeekStart: Date {
        calendarWeekViewWeekStart(for: calendarWeekAnchorDate ?? topVisibleDate, calendar: workspaceCalendar)
    }

    private var calendarWeekModelSignatureValue: Int {
        var hasher = Hasher()
        hasher.combine(DateParsers.isoDay.string(from: calendarShownWeekStart))
        hasher.combine(calendarDerivedDataRevision)
        hasher.combine(DateParsers.isoDay.string(from: today))
        hasher.combine(visibleCalendarColumns.contains(.conferences))
        hasher.combine(visibleCalendarColumns.contains(.completion))
        hasher.combine(effectiveUsesDarkAppearance)
        hasher.combine(language.rawValue)
        hasher.combine(store.calendarWeekdayChoice.rawValue)
        hasher.combine(store.holidayCountries.map(\.rawValue))
        hasher.combine(store.calendarTaskReminderBadgeEntries.map(\.id))
        return hasher.finalize()
    }

    /// "Lista | Vecka" next to "Gå till …" and "Idag".
    private func calendarViewModePicker(proxy: ScrollViewProxy) -> some View {
        Picker(language.text("View", "Visning"), selection: $calendarViewMode) {
            ForEach(CalendarWorkspaceViewMode.allCases) { mode in
                Text(mode.title(language: language))
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help(language.text(
            "Show the calendar as a list or one week at a time",
            "Visa kalendern som lista eller en vecka i taget"
        ))
        .onChange(of: calendarViewMode) { oldMode, newMode in
            handleCalendarViewModeChange(from: oldMode, to: newMode, using: proxy)
        }
    }

    private func handleCalendarViewModeChange(
        from oldMode: CalendarWorkspaceViewMode,
        to newMode: CalendarWorkspaceViewMode,
        using proxy: ScrollViewProxy
    ) {
        guard oldMode != newMode else { return }
        switch newMode {
        case .week:
            // The week of the day at the top of the list.
            showCalendarWeek(containing: topVisibleDate)
        case .list:
            // The list opens at the week that was shown.
            let weekStart = calendarShownWeekStart
            DispatchQueue.main.async {
                goToCalendarDate(weekStart, using: proxy, animated: false)
            }
        }
    }

    private func calendarWeekContent() -> some View {
        Group {
            if let model = calendarWeekModel {
                CalendarWeekView(
                    model: model,
                    language: language,
                    usesDarkAppearance: effectiveUsesDarkAppearance,
                    workingHours: calendarWeekWorkingHours,
                    onPreviousWeek: { moveCalendarWeek(by: -1) },
                    onNextWeek: { moveCalendarWeek(by: 1) },
                    // Same as clicking the title in the list: open the editor when
                    // the event has one, otherwise the detail sheet.
                    onSelectEvent: { event in
                        if let primaryAction = eventTapAction(for: event) {
                            primaryAction()
                        } else {
                            presentCalendarEventDetail(event)
                        }
                    },
                    eventContextMenu: { event, date in calendarEventContextMenu(for: event, on: date) },
                    dayContextMenu: { date in dayCreationContextMenu(for: date) }
                )
            } else {
                AppPalette.calendarWorkspaceSurface
            }
        }
        .onAppear {
            if calendarWeekAnchorDate == nil {
                calendarWeekAnchorDate = calendarWeekViewWeekStart(for: topVisibleDate, calendar: workspaceCalendar)
            }
            calendarWeekWindowRequestKey = nil
            refreshCalendarWeekModelIfNeeded(force: true)
        }
        .onChange(of: calendarWeekModelSignatureValue) { _, _ in
            refreshCalendarWeekModelIfNeeded()
        }
        // The current value arrives at once, then each change made in
        // Settings, so the grey shading follows the working hours directly.
        .onReceive(
            store.$metadata
                .map { ($0.calendarWorkingHours ?? CalendarWorkingHoursSettings.standard).normalized() }
                .removeDuplicates()
        ) { workingHours in
            calendarWeekWorkingHours = workingHours
        }
        .onChange(of: pinnedCalendarNavigationDate) { _, newValue in
            // "Show in calendar" from another workspace pins the target day;
            // the week view then opens that week.
            guard let newValue else { return }
            showCalendarWeek(containing: newValue)
        }
    }

    /// "Idag", "Gå till …" and the arrows in week mode.
    private func showCalendarWeek(containing date: Date) {
        let weekStart = calendarWeekViewWeekStart(for: date, calendar: workspaceCalendar)
        calendarWeekAnchorDate = weekStart
        pendingTargetedCalendarScroll = nil
        pendingDefaultOpenDate = nil
        isStabilizingDefaultOpen = false
        cancelQueuedCalendarViewportRestoresForTargetedNavigation()
        // Keep the remembered day in step, so a tab switch or a return to
        // the list comes back to this week.
        topVisibleDate = weekStart
        lastFocusedCalendarDate = weekStart
        store.calendarWorkspaceLastFocusedDate = weekStart
        refreshCalendarWeekModelIfNeeded()
    }

    private func moveCalendarWeek(by weeks: Int) {
        let weekStart = calendarShownWeekStart
        let target = workspaceCalendar.date(byAdding: .day, value: 7 * weeks, to: weekStart) ?? weekStart
        showCalendarWeek(containing: target)
    }

    private func refreshCalendarWeekModelIfNeeded(force: Bool = false) {
        let weekStart = calendarShownWeekStart
        loadCalendarWeekIfNeeded(weekStart: weekStart)
        let signature = calendarWeekModelSignatureValue
        guard force || calendarWeekModel == nil || calendarWeekModelSignature != signature else { return }
        calendarWeekModelSignature = signature
        calendarWeekModel = makeCalendarWeekModel(weekStart: weekStart)
    }

    /// The list builds its day groups for a window of dates around the day
    /// in view. When the shown week falls outside that window, the window is
    /// moved to the week. It asks once per week and window, so a week the
    /// window cannot reach does not rebuild over and over.
    private func loadCalendarWeekIfNeeded(weekStart: Date) {
        // The first load is still running; its rebuild refreshes the week.
        guard !cache.allDates.isEmpty else { return }
        let weekEnd = calendarWeekViewWeekEnd(for: weekStart, calendar: workspaceCalendar)
        guard !isDateInsideRenderedWindow(weekStart) || !isDateInsideRenderedWindow(weekEnd) else { return }
        let requestKey = [
            DateParsers.isoDay.string(from: weekStart),
            renderedDateWindow.map { DateParsers.isoDay.string(from: $0.start) } ?? "",
            renderedDateWindow.map { DateParsers.isoDay.string(from: $0.end) } ?? ""
        ].joined(separator: "|")
        guard calendarWeekWindowRequestKey != requestKey else { return }
        calendarWeekWindowRequestKey = requestKey
        resetRenderedDateWindow(centeredOn: weekStart)
        if cache.isWindowScoped {
            rebuildCalendarCache(skipIfUnchanged: false, scope: .visibleWindow)
        } else {
            rebuildDerivedCalendarData(skipIfUnchanged: false)
        }
    }

    private func makeCalendarWeekModel(weekStart: Date) -> CalendarWeekViewModel {
        let calendar = workspaceCalendar
        let weekDayKeys = Set(
            calendarWeekViewDays(weekStart: weekStart, calendar: calendar)
                .map { DateParsers.isoDay.string(from: $0) }
        )
        // Congresses follow the Conferences column, as in the list.
        let showsConferences = visibleCalendarColumns.contains(.conferences)
        var eventsByDay: [String: [CalendarWorkspaceEvent]] = [:]
        for group in derivedData.dayGroups where weekDayKeys.contains(group.id) {
            eventsByDay[group.id] = showsConferences ? group.events + group.conferenceEvents : group.events
        }
        let weekEnd = calendarWeekViewWeekEnd(for: weekStart, calendar: calendar)
        let holidays = holidaysInCalendarRange(
            from: weekStart,
            to: weekEnd,
            countries: store.holidayCountries,
            calendar: calendar
        )
        let holidaysByDay = Dictionary(grouping: holidays) { holiday in
            DateParsers.isoDay.string(from: calendar.startOfDay(for: holiday.date))
        }
        return makeCalendarWeekViewModel(
            weekStart: weekStart,
            today: today,
            calendar: calendar,
            language: language,
            eventsByDay: eventsByDay,
            holidaysByDay: holidaysByDay,
            showsCompletionRing: calendarShowsCompletionRing,
            dayHighlightColor: { date, dayHolidays in
                calendarDayHighlightKind(for: date, holidays: dayHolidays)
                    .map { configuredCalendarDayHighlightTextColor($0) }
            },
            eventStyle: { event in
                CalendarWeekViewEventStyle(
                    accentColor: eventRowHighlightColor(for: event),
                    iconName: calendarEventIconName(for: event),
                    opacity: calendarWeekEventOpacity(event),
                    needsAttentionRing: eventNeedsAttentionRing(event),
                    completionTint: completionTint(for: event),
                    isItalic: eventUsesItalicStyle(event)
                )
            }
        )
    }

    /// The list's dimming rule without a day group: done tasks and events
    /// that are over are drawn fainter.
    private func calendarWeekEventOpacity(_ event: CalendarWorkspaceEvent) -> Double {
        if event.isCompleted {
            return 0.56
        }
        let day = workspaceCalendar.startOfDay(for: event.displayDate)
        if day < today {
            return 0.6
        }
        if day > today {
            return 1
        }
        guard let cutoff = eventPastCutoffDate(for: event) else { return 1 }
        return cutoff < Date() ? 0.6 : 1
    }
}

private func calendarMenuPlainTitle(_ text: String) -> String {
    text.replacingOccurrences(of: somalilandFlagToken, with: "Somaliland")
}

private func calendarMenuAttributedTitle(
    _ text: String,
    font: NSFont,
    color: NSColor
) -> NSAttributedString {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    guard text.contains(somalilandFlagToken) else {
        return NSAttributedString(string: text, attributes: attributes)
    }

    let output = NSMutableAttributedString()
    let segments = text.components(separatedBy: somalilandFlagToken)
    for (index, segment) in segments.enumerated() {
        if !segment.isEmpty {
            output.append(NSAttributedString(string: segment, attributes: attributes))
        }
        if index < segments.count - 1 {
            if let image = somalilandMenuFlagImage {
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(
                    x: 0,
                    y: -1,
                    width: somalilandFlagDisplayWidth,
                    height: somalilandFlagDisplayHeight
                )
                output.append(NSAttributedString(attachment: attachment))
            } else {
                output.append(NSAttributedString(string: "Somaliland", attributes: attributes))
            }
        }
    }
    return output
}

private struct CalendarFilterPopupField: View {
    let labels: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    @State private var isFocused = false

    var body: some View {
        CalendarFilterPopupRepresentable(
            labels: labels,
            selectedIndex: selectedIndex,
            onSelect: onSelect,
            onFocusChange: { isFocused = $0 }
        )
        // F33: made nearly invisible on the AppKit side (see makeNSView), as
        // in AppFormControls; SwiftUI's .opacity() swallowed the click.
        .contentShape(Rectangle())
        .appKeyboardFocusPulse(isFocused: isFocused)
    }
}

private struct CalendarFilterPopupRepresentable: NSViewRepresentable {
    let labels: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onFocusChange: onFocusChange)
    }

    func makeNSView(context: Context) -> PopupContainerView {
        let popup = FocusablePopUpButton(frame: .zero, pullsDown: false)
        popup.autoenablesItems = false
        popup.isBordered = false
        popup.bezelStyle = .regularSquare
        popup.focusRingType = .none
        popup.font = .systemFont(ofSize: 13)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionDidChange(_:))
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Nearly transparent, but still clickable: AppKit hit-testing ignores
        // alphaValue. The visible label is drawn by SwiftUI underneath.
        popup.alphaValue = 0.02
        if let cell = popup.cell as? NSPopUpButtonCell {
            cell.isBordered = false
        }
        return PopupContainerView(popup: popup)
    }

    func updateNSView(_ container: PopupContainerView, context: Context) {
        let popup = container.popup
        context.coordinator.onSelect = onSelect
        context.coordinator.onFocusChange = onFocusChange
        popup.onFocusChange = onFocusChange
        let font = NSFont.systemFont(ofSize: 13)
        let selectedFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let textColor = NSColor.labelColor

        if context.coordinator.cachedLabels != labels {
            popup.removeAllItems()
            for label in labels {
                popup.addItem(withTitle: calendarMenuPlainTitle(label))
                popup.lastItem?.attributedTitle = calendarMenuAttributedTitle(label, font: font, color: textColor)
            }
            context.coordinator.cachedLabels = labels
        } else {
            for (index, label) in labels.enumerated() where popup.itemArray.indices.contains(index) {
                popup.itemArray[index].attributedTitle = calendarMenuAttributedTitle(label, font: font, color: textColor)
            }
        }

        guard !labels.isEmpty else { return }
        let clampedIndex = min(max(0, selectedIndex), labels.count - 1)
        if popup.indexOfSelectedItem != clampedIndex {
            popup.selectItem(at: clampedIndex)
        }
        popup.attributedTitle = calendarMenuAttributedTitle(
            labels[clampedIndex],
            font: selectedFont,
            color: textColor
        )
        popup.contentTintColor = nil
        popup.toolTip = calendarMenuPlainTitle(labels[clampedIndex])
    }

    final class FocusablePopUpButton: NSPopUpButton {
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }
        var onFocusChange: ((Bool) -> Void)?

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted {
                onFocusChange?(true)
                AppFocusPulse.setFocused(true, on: self)
            }
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted {
                onFocusChange?(false)
                AppFocusPulse.setFocused(false, on: self)
            }
            return accepted
        }

        override func layout() {
            super.layout()
            AppFocusPulse.updateLayout(on: self)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 48 {
                let direction: AppFormFocusDirection = event.modifierFlags.contains(.shift) ? .backward : .forward
                AppFormKeyboardRouting.moveFocus(from: self, direction: direction)
                return
            }
            super.keyDown(with: event)
        }

        override func insertTab(_ sender: Any?) {
            AppFormKeyboardRouting.moveFocus(from: self, direction: .forward)
        }

        override func insertBacktab(_ sender: Any?) {
            AppFormKeyboardRouting.moveFocus(from: self, direction: .backward)
        }

    }

    final class PopupContainerView: NSView {
        let popup: FocusablePopUpButton

        init(popup: FocusablePopUpButton) {
            self.popup = popup
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            popup.translatesAutoresizingMaskIntoConstraints = false
            addSubview(popup)
            NSLayoutConstraint.activate([
                popup.leadingAnchor.constraint(equalTo: leadingAnchor),
                popup.trailingAnchor.constraint(equalTo: trailingAnchor),
                popup.topAnchor.constraint(equalTo: topAnchor),
                popup.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { false }
        override var canBecomeKeyView: Bool { false }

        /// Every click inside the field belongs to the popup, wherever it lands.
        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            return bounds.contains(local) ? popup : nil
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void
        var onFocusChange: (Bool) -> Void
        var cachedLabels: [String] = []

        init(onSelect: @escaping (Int) -> Void, onFocusChange: @escaping (Bool) -> Void) {
            self.onSelect = onSelect
            self.onFocusChange = onFocusChange
        }

        @objc func selectionDidChange(_ sender: NSPopUpButton) {
            onSelect(sender.indexOfSelectedItem)
        }
    }
}

private struct HolidayDotStack: View {
    let holidays: [HolidayDefinition]
    let language: AppLanguage
    let textColor: Color
    let backgroundColor: Color

    @State private var showingPopover = false

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(holidays.prefix(3).enumerated()), id: \.element.id) { index, _ in
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 8, height: 8)
                    .offset(x: CGFloat(index) * 4)
            }
        }
        .frame(width: 16 + CGFloat(max(holidays.count - 1, 0)) * 4, height: 10, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            showingPopover = hovering
        }
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(holidays) { holiday in
                    Text("\(holiday.localizedTitle(language: language)) · \(holiday.country.localizedName(language: language))")
                        .calendarTypography(.tableHeader)
                        .foregroundStyle(textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(backgroundColor)
                        )
                }
            }
            .padding(12)
        }
    }
}

private struct CalendarConferenceLabel: View {
    let title: String
    let hoverText: String
    let isDateUncertain: Bool
    let language: AppLanguage
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    label
                }
                .buttonStyle(.plain)
            } else {
                label
            }
        }
        .contentShape(Rectangle())
        .help(hoverText)
    }

    private var label: some View {
        Text(uncertainCalendarText(title, uncertain: isDateUncertain, language: language))
            .calendarTypography(.secondary)
            .italic()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CalendarProjectOverflowIndicator: View {
    let onExpand: () -> Void

    var body: some View {
        // Plain grey "…" like the project names next to it (no box).
        Text("…")
            .font(appFont(.secondary).weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .fixedSize()
            .onHover { hovering in
                guard hovering else { return }
                onExpand()
            }
    }
}

private struct CalendarDateInputField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        AppDateField(
            placeholder: placeholder,
            text: $text,
            showsCalendarPicker: true,
            language: .swedish
        )
    }
}

private struct CalendarGoToDatePopover: View {
    let language: AppLanguage
    let calendar: Calendar
    let selectedDate: Date
    @Binding var dateText: String
    @Binding var displayedYear: Int
    let onSelect: (Date) -> Void

    @State private var showsInvalidDate = false

    // Day cells must be wide enough for two-digit numbers at 12pt — 14pt
    // cells truncated them to "…".
    private let monthColumns = Array(repeating: GridItem(.fixed(152), spacing: 10), count: 4)
    private let dayColumns = Array(repeating: GridItem(.fixed(20), spacing: 2), count: 7)

    private var normalizedSelectedDate: Date {
        calendar.startOfDay(for: selectedDate)
    }

    private var normalizedToday: Date {
        calendar.startOfDay(for: Date())
    }

    private var weekdayLabels: [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        let symbols = formatter.veryShortWeekdaySymbols ?? []
        guard !symbols.isEmpty else { return [] }
        let startIndex = min(max(calendar.firstWeekday - 1, 0), symbols.count - 1)
        return Array(symbols[startIndex..<symbols.count]) + Array(symbols[0..<startIndex])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AppDateField(
                    placeholder: language.datePlaceholder,
                    text: $dateText,
                    width: 132,
                    language: language,
                    state: showsInvalidDate ? .invalid(language.text("Enter a date as YYYY-MM-DD.", "Ange datum som ÅÅÅÅ-MM-DD.")) : .normal
                )

                Button(language.text("Go", "Gå")) {
                    submitTypedDate()
                }
                .appSaveButtonStyle()
                .controlSize(.small)

                Spacer()

                Button {
                    displayedYear -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(language.text("Previous year", "Föregående år"))
                .accessibilityLabel(language.text("Previous year", "Föregående år"))

                Text(String(displayedYear))
                    .calendarTypography(.panelTitle)
                    .monospacedDigit()
                    .frame(width: 54)

                Button {
                    displayedYear += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(language.text("Next year", "Nästa år"))
                .accessibilityLabel(language.text("Next year", "Nästa år"))
            }

            if showsInvalidDate {
                Text(language.text("Enter a date as YYYY-MM-DD.", "Ange datum som ÅÅÅÅ-MM-DD."))
                    .calendarTypography(.secondary)
                    .foregroundStyle(AppPalette.statusText(.negative))
            }

            LazyVGrid(columns: monthColumns, alignment: .leading, spacing: 12) {
                ForEach(1...12, id: \.self) { month in
                    monthView(month)
                }
            }
        }
        .padding(14)
        .frame(width: 4 * 152 + 3 * 10 + 28, alignment: .topLeading)
        .onChange(of: dateText) { _, _ in
            showsInvalidDate = false
        }
    }

    private func submitTypedDate() {
        let normalized = DateParsers.canonicalizedDayInput(dateText)
        guard let parsedDate = DateParsers.isoDay.date(from: normalized) else {
            dateText = normalized
            showsInvalidDate = true
            return
        }
        selectDate(parsedDate)
    }

    private func selectDate(_ date: Date) {
        let normalized = calendar.startOfDay(for: date)
        dateText = DateParsers.isoDay.string(from: normalized)
        displayedYear = calendar.component(.year, from: normalized)
        showsInvalidDate = false
        onSelect(normalized)
    }

    private func monthView(_ month: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(monthTitle(month))
                .font(appFont(.secondary).weight(.semibold))
                .foregroundStyle(AppPalette.appText)
                .lineLimit(1)

            LazyVGrid(columns: dayColumns, alignment: .center, spacing: 2) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(appFont(.secondary).weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 12)
                }

                ForEach(Array(daySlots(for: month).enumerated()), id: \.offset) { _, date in
                    dayCell(date)
                }
            }
        }
        .frame(width: 152, alignment: .topLeading)
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            Button {
                selectDate(date)
            } label: {
                Text(String(calendar.component(.day, from: date)))
                    .font(appFont(.secondary).weight(isSelected(date) ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(dayTextColor(date))
                    .frame(width: 20, height: 17)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(dayFillColor(date))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(dayStrokeColor(date), lineWidth: isToday(date) ? 1 : 0)
                    )
            }
            .buttonStyle(.plain)
            .help(DateParsers.isoDay.string(from: calendar.startOfDay(for: date)))
        } else {
            Color.clear
                .frame(width: 20, height: 17)
        }
    }

    private func monthTitle(_ month: Int) -> String {
        guard let date = date(year: displayedYear, month: month, day: 1) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date).capitalized(with: calendar.locale)
    }

    private func daySlots(for month: Int) -> [Date?] {
        guard let firstDay = date(year: displayedYear, month: month, day: 1),
              let dayRange = calendar.range(of: .day, in: .month, for: firstDay) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingEmptyCells = (firstWeekday - calendar.firstWeekday + 7) % 7
        var slots = Array<Date?>(repeating: nil, count: leadingEmptyCells)

        for day in dayRange {
            slots.append(date(year: displayedYear, month: month, day: day))
        }
        while slots.count % 7 != 0 {
            slots.append(nil)
        }
        while slots.count < 42 {
            slots.append(nil)
        }
        return slots
    }

    private func date(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
    }

    private func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: normalizedSelectedDate)
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: normalizedToday)
    }

    private func dayFillColor(_ date: Date) -> Color {
        if isSelected(date) {
            return AppPalette.actionSave.opacity(0.95)
        }
        return Color.clear
    }

    // Round 17: today is marked like in the timelines (red ring and red
    // text); the selected day stays the accent colour.
    private func dayStrokeColor(_ date: Date) -> Color {
        isToday(date) ? AppPalette.todayMarker : Color.clear
    }

    private func dayTextColor(_ date: Date) -> Color {
        if isSelected(date) {
            return .white
        }
        if isToday(date) {
            return AppPalette.todayMarker
        }
        return AppPalette.appText
    }
}

struct CalendarTimeInputField: View {
    let placeholder: String
    @Binding var text: String
    /// False writes the value only when editing ends (for fields that save
    /// straight to the store, so a half-typed time is not normalized).
    var updatesContinuously: Bool = true

    var body: some View {
        CommitFormattingTextField(
            placeholder: placeholder,
            text: $text,
            formatter: normalizedCalendarTimeInput,
            updatesContinuously: updatesContinuously
        )
        .frame(minHeight: 18)
        .appTextInputChrome()
    }
}

private struct CalendarEventCopySheet: View {
    let language: AppLanguage
    let request: CalendarEventCopyRequest
    let onSave: (CalendarEventCopyRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CalendarEventCopyRequest
    @State private var committedStartTimeForShift: String?

    init(
        language: AppLanguage,
        request: CalendarEventCopyRequest,
        onSave: @escaping (CalendarEventCopyRequest) -> Void
    ) {
        self.language = language
        self.request = request
        self.onSave = onSave
        _draft = State(initialValue: request)
        _committedStartTimeForShift = State(
            initialValue: committedCalendarTimeForRangeShift(request.startTime)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(language.text("Copy event", "Kopiera händelse"))
                .calendarTypography(.sectionTitle)

            Text(draft.title)
                .calendarTypography(.secondary)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Date", "Datum"))
                    .calendarTypography(.fieldLabel)
                CalendarDateInputField(placeholder: language.datePlaceholder, text: $draft.date)
            }

            if draft.allowsTimeEditing {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text("Start time", "Starttid"))
                            .calendarTypography(.fieldLabel)
                        CalendarTimeInputField(placeholder: "HH:MM", text: startTimeBinding)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text("End time", "Sluttid"))
                            .calendarTypography(.fieldLabel)
                        CalendarTimeInputField(placeholder: "HH:MM", text: $draft.endTime)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            FootprintDialogActions(
                cancelTitle: language.text("Cancel", "Avbryt"),
                primaryTitle: language.text("Copy", "Kopiera"),
                isPrimaryDisabled: draft.date.trimmedOrNil == nil,
                cancelAction: { dismiss() },
                primaryAction: {
                    draft.date = DateParsers.canonicalizedDayInput(draft.date)
                    draft.startTime = normalizedCalendarTimeInput(draft.startTime)
                    draft.endTime = normalizedCalendarTimeInput(draft.endTime)
                    onSave(draft)
                    dismiss()
                }
            )
        }
        .padding(22)
        .appResponsiveDialogFrame(
            idealWidth: 430,
            idealHeight: draft.allowsTimeEditing ? 260 : 210,
            minimumWidth: 360,
            minimumHeight: 210
        )
    }

    private var startTimeBinding: Binding<String> {
        Binding(
            get: { draft.startTime },
            set: { newValue in
                let update = updatingCommittedTimeRangeEnd(
                    previousCommittedStart: committedStartTimeForShift,
                    newInput: newValue,
                    currentEnd: draft.endTime
                )
                draft.startTime = newValue
                if let shiftedEndTime = update.shiftedEnd {
                    draft.endTime = shiftedEndTime
                }
                committedStartTimeForShift = update.committedStart
            }
        )
    }
}

private struct CalendarTodoParticipantDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
}


private func calendarSheetInitialDateString(_ initialDateString: String?) -> String {
    initialDateString?.trimmedOrNil
        ?? DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
}

func calendarTaskLinksReplacingPrimary(
    in links: [TaskLink],
    kind: TaskLinkKind,
    targetID: String?
) -> [TaskLink] {
    var updated = links
    let normalizedTargetID = targetID?.trimmedOrNil
    if let index = updated.firstIndex(where: { $0.kind == kind }) {
        guard updated[index].targetID != normalizedTargetID else { return updated }
        if let normalizedTargetID {
            updated[index] = TaskLink(kind: kind, targetID: normalizedTargetID)
        } else {
            updated.remove(at: index)
        }
    } else if let normalizedTargetID {
        updated.append(TaskLink(kind: kind, targetID: normalizedTargetID))
    }
    return updated
}

private struct CalendarTodoSheet: View {
    @ObservedObject var store: GrantDataStore
    let taskID: String?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var note: String = ""
    // Round 7: the same participant rows and link rows as the activity editor.
    @State private var participantRows: [CalendarMeetingParticipantDraft] = [.init()]
    @State private var projectIDs: [String] = []
    @State private var organizationIDs: [String] = []
    @State private var applicationIDs: [String] = []
    @State private var publicationIDs: [String] = []
    @State private var teachingOptionIDs: [String] = []
    @State private var doctoralCandidateIDs: [String] = []
    @State private var deadline: String
    /// Optional clock time on the deadline day ("HH:mm"); shared tasks only.
    @State private var deadlineTime: String = ""
    @State private var completionDate: String = ""
    @State private var agendaText: String = ""
    @State private var protocolText: String = ""
    @State private var didLoadExistingValues = false

    init(store: GrantDataStore, taskID: String?, initialDateString: String? = nil) {
        self.store = store
        self.taskID = taskID
        _deadline = State(initialValue: calendarSheetInitialDateString(initialDateString))
    }

    private var language: AppLanguage { store.language }
    private var todayString: String {
        DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
    }
    private var existingTask: PublicationTaskItem? {
        guard let taskID else { return nil }
        return store.teachingWorkspaceTasks.first(where: { $0.id == taskID })
    }

    private var existingCentralTask: TaskItem? {
        guard let taskID else { return nil }
        return store.taskItems.first(where: { $0.id == taskID })
    }

    /// An older task kept on the teaching list (not yet a shared task) can
    /// only hold one project, one publication and one grant.
    private var isLegacyTeachingTask: Bool {
        existingCentralTask == nil && existingTask != nil
    }

    private var participantOptions: [String] {
        calendarLinkParticipantOptions(store: store)
    }

    /// Locked projects and publications are offered only when the task
    /// already links to them, as before.
    private var retainedLockedIDs: Set<String> {
        var ids = Set<String>()
        if let existingCentralTask {
            ids.formUnion(calendarTaskLinkTargetIDs(existingCentralTask.links, kind: .project))
            ids.formUnion(calendarTaskLinkTargetIDs(existingCentralTask.links, kind: .publication))
        } else if let existingTask {
            if let projectID = existingTask.projectID?.trimmedOrNil { ids.insert(projectID) }
            if let publicationID = existingTask.publicationID?.trimmedOrNil { ids.insert(publicationID) }
        }
        return ids
    }

    private var linkOptions: CalendarLinkOptionSets {
        CalendarLinkOptionSets(store: store, language: language, keepingLockedIDs: retainedLockedIDs)
    }

    private var normalizedParticipants: [String] {
        let trimmed = participantRows.compactMap { $0.name.trimmedOrNil }
        return Array(NSOrderedSet(array: trimmed)) as? [String] ?? trimmed
    }

    private var linkSelection: CalendarTaskLinkSelection {
        let teaching = calendarTeachingSelection(fromOptionIDs: teachingOptionIDs)
        return CalendarTaskLinkSelection(
            projectIDs: projectIDs,
            organizationIDs: organizationIDs,
            applicationIDs: applicationIDs,
            publicationIDs: publicationIDs,
            teachingCourseIDs: teaching.courseIDs,
            teachingAssignmentIDs: teaching.assignmentIDs,
            doctoralCandidateIDs: doctoralCandidateIDs
        )
    }

    /// The records each link row offers, per link kind.
    private func listedLinkIDs(_ options: CalendarLinkOptionSets) -> [TaskLinkKind: Set<String>] {
        let teaching = calendarTeachingSelection(fromOptionIDs: options.teaching.map(\.id))
        return [
            .project: Set(options.projects.map(\.id)),
            .organization: Set(options.organizations.map(\.id)),
            .application: Set(options.applications.map(\.id)),
            .publication: Set(options.publications.map(\.id)),
            .teachingCourse: Set(teaching.courseIDs),
            .teachingAssignment: Set(teaching.assignmentIDs),
            .doctoralCandidate: Set(options.doctoralCandidates.map(\.id))
        ]
    }

    var body: some View {
        CalendarEditorDialogSurface { dialogWidth in
            VStack(alignment: .leading, spacing: 16) {
                Text(taskID == nil ? language.text("Add task", "Lägg till uppgift") : language.text("Edit task", "Redigera uppgift"))
                    .calendarTypography(.sectionTitle)

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Title", "Rubrik"))
                                .calendarTypography(.fieldLabel)
                            TextField(language.text("Task title", "Rubrik för uppgiften"), text: $title)
                                .appTextInputChrome()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Date", "Datum"))
                                .calendarTypography(.fieldLabel)
                            if isLegacyTeachingTask {
                                CalendarDateInputField(placeholder: language.datePlaceholder, text: $deadline)
                            } else {
                                HStack(alignment: .top, spacing: 8) {
                                    CalendarDateInputField(placeholder: language.datePlaceholder, text: $deadline)
                                    CalendarTimeInputField(placeholder: "hh:mm", text: $deadlineTime)
                                        .frame(width: 70)
                                        .disabled(deadline.trimmedOrNil == nil)
                                        .help(language.text("Optional time on the deadline day", "Valfritt klockslag på dagen"))
                                }
                            }
                        }
                        .onChange(of: deadline) { _, newValue in
                            // Clearing the date also clears the time.
                            if newValue.trimmedOrNil == nil {
                                deadlineTime = ""
                            }
                        }

                        CalendarLinkRowsSection(
                            language: language,
                            options: linkOptions,
                            projectIDs: $projectIDs,
                            organizationIDs: $organizationIDs,
                            applicationIDs: $applicationIDs,
                            publicationIDs: $publicationIDs,
                            teachingOptionIDs: $teachingOptionIDs,
                            doctoralCandidateIDs: $doctoralCandidateIDs,
                            showsAllKinds: !isLegacyTeachingTask
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Comment", "Kommentar"))
                                .calendarTypography(.fieldLabel)
                            TextField(language.text("Comment", "Kommentar"), text: $note)
                                .appTextInputChrome()
                        }

                        CalendarParticipantRowsField(
                            rows: $participantRows,
                            options: participantOptions,
                            language: language
                        )

                        CalendarTaskCompletionDateField(language: language, text: $completionDate)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    CalendarAgendaProtocolColumn(
                        language: language,
                        agendaText: $agendaText,
                        protocolText: $protocolText
                    )
                    .frame(width: calendarEditorSideColumnWidth(for: dialogWidth))
                }

                FootprintDialogActions(
                    cancelTitle: language.text("Cancel", "Avbryt"),
                    primaryTitle: language.text("Save", "Spara"),
                    isPrimaryDisabled: title.trimmedOrNil == nil,
                    cancelAction: { dismiss() },
                    primaryAction: { save() }
                )
            }
        }
        .autocompleteOverlayHost()
        .onAppear {
            loadExistingTaskIfNeeded()
        }
    }

    private func save() {
        let participants = normalizedParticipants
        let selection = linkSelection
        let listed = listedLinkIDs(linkOptions)

        if var task = existingCentralTask {
            task.deadline = deadline
            task.deadlineTime = deadline.trimmedOrNil == nil ? nil : TaskItem.normalizedDeadlineTime(deadlineTime)
            task.comment = title
            task.note = note
            task.participantNames = participants
            // Participants are linked to researchers by id, as on activities.
            task.participantAuthorIDs = store.synchronizedPersonAuthorIDs(
                existingIDs: task.participantAuthorIDs,
                names: participants
            )
            task.completedOn = completionDate.trimmedOrNil
            task.agendaText = agendaText
            task.protocolText = protocolText
            task.updatedOn = todayString
            if task.createdOn.isEmpty { task.createdOn = todayString }
            task.links = calendarTaskLinksApplyingSelection(task.links, selection: selection, listedIDs: listed)
            store.saveTaskItem(task)
            dismiss()
            return
        }

        if taskID == nil {
            var task = TaskItem(
                createdOn: todayString,
                updatedOn: todayString,
                deadline: deadline,
                deadlineTime: deadline.trimmedOrNil == nil ? nil : TaskItem.normalizedDeadlineTime(deadlineTime),
                comment: title,
                note: note,
                participantNames: participants,
                participantAuthorIDs: store.synchronizedPersonAuthorIDs(existingIDs: [], names: participants),
                links: calendarTaskLinksApplyingSelection([], selection: selection, listedIDs: listed),
                completedOn: completionDate.trimmedOrNil,
                agendaText: agendaText,
                protocolText: protocolText
            )
            task.normalize()
            store.saveTaskItem(task)
            dismiss()
            return
        }

        var tasks = store.teachingWorkspaceTasks
        if let taskID,
           let existingIndex = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[existingIndex].deadline = deadline
            tasks[existingIndex].comment = title
            tasks[existingIndex].note = note
            tasks[existingIndex].participantNames = participants
            tasks[existingIndex].participantAuthorIDs = store.synchronizedPersonAuthorIDs(
                existingIDs: tasks[existingIndex].participantAuthorIDs,
                names: participants
            )
            // An older teaching-list task holds one link of each kind.
            tasks[existingIndex].projectID = selection.projectIDs.first
            tasks[existingIndex].publicationID = selection.publicationIDs.first
            tasks[existingIndex].applicationID = selection.applicationIDs.first
            tasks[existingIndex].completedOn = completionDate
            tasks[existingIndex].agendaText = agendaText
            tasks[existingIndex].protocolText = protocolText
            tasks[existingIndex].updatedOn = todayString
            if tasks[existingIndex].createdOn.isEmpty {
                tasks[existingIndex].createdOn = todayString
            }
            tasks[existingIndex].normalize()
        }
        store.autosaveTeachingWorkspaceTasks(tasks)
        dismiss()
    }

    private func loadExistingTaskIfNeeded() {
        guard !didLoadExistingValues else { return }
        defer { didLoadExistingValues = true }
        if let existingCentralTask {
            title = existingCentralTask.comment
            note = existingCentralTask.note
            deadline = existingCentralTask.deadline
            deadlineTime = existingCentralTask.deadlineTime ?? ""
            participantRows = existingCentralTask.participantNames.map { CalendarMeetingParticipantDraft(name: $0) }
                + [CalendarMeetingParticipantDraft()]
            let selection = CalendarTaskLinkSelection(links: existingCentralTask.links)
            projectIDs = selection.projectIDs
            organizationIDs = selection.organizationIDs
            applicationIDs = selection.applicationIDs
            publicationIDs = selection.publicationIDs
            teachingOptionIDs = calendarTeachingOptionIDs(
                courseIDs: selection.teachingCourseIDs,
                assignmentIDs: selection.teachingAssignmentIDs
            )
            doctoralCandidateIDs = selection.doctoralCandidateIDs
            completionDate = existingCentralTask.completedOn ?? ""
            agendaText = existingCentralTask.agendaText
            protocolText = existingCentralTask.protocolText
            return
        }
        guard let existingTask else { return }
        title = existingTask.comment
        note = existingTask.note
        deadline = existingTask.deadline
        participantRows = existingTask.participantNames.map { CalendarMeetingParticipantDraft(name: $0) }
            + [CalendarMeetingParticipantDraft()]
        projectIDs = existingTask.projectID?.trimmedOrNil.map { [$0] } ?? []
        publicationIDs = existingTask.publicationID?.trimmedOrNil.map { [$0] } ?? []
        applicationIDs = existingTask.applicationID?.trimmedOrNil.map { [$0] } ?? []
        completionDate = existingTask.completedOn ?? ""
        agendaText = existingTask.agendaText
        protocolText = existingTask.protocolText
    }
}

struct CalendarProjectTaskSheet: View {
    @ObservedObject var store: GrantDataStore
    let projectID: String
    let taskID: String?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var participantRows: [CalendarTodoParticipantDraft] = [.init()]
    @State private var publicationLabel: String = ""
    @State private var applicationLabel: String = ""
    @State private var deadline: String = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
    @State private var reminder: ProjectTaskReminder = .none
    @State private var completionDate: String = ""
    @State private var agendaText: String = ""
    @State private var protocolText: String = ""
    @State private var didLoadExistingValues = false

    private var language: AppLanguage { store.language }
    private var todayString: String {
        DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
    }
    private var project: ProjectRecord? {
        store.projects.first(where: { $0.id == projectID })
    }
    private var existingTask: ProjectTaskItem? {
        project?.projectTasks.first(where: { $0.id == taskID })
    }
    private var participantOptions: [String] {
        Array(
            Set(
                store.publicationAuthors.map(\.displayName)
                    + (project?.projectTasks.flatMap(\.participantNames) ?? [])
            )
        )
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var retainedPublicationID: String? {
        existingTask?.publicationID?.trimmedOrNil
    }
    private var publicationOptions: [(id: String, label: String)] {
        store.publications
            .filter { !$0.isEditingLocked || $0.id == retainedPublicationID }
            .map { ($0.id, $0.title.nonEmpty ?? language.text("Untitled", "Utan titel")) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    private var applicationOptions: [CalendarGrantSelectionOption] {
        calendarGrantSelectionOptions(store: store, language: language)
    }
    private var normalizedParticipants: [String] {
        let trimmed = participantRows.compactMap { $0.name.trimmedOrNil }
        return Array(NSOrderedSet(array: trimmed)) as? [String] ?? trimmed
    }

    var body: some View {
        CalendarEditorDialogSurface { dialogWidth in
            VStack(alignment: .leading, spacing: 16) {
                Text(taskID == nil ? language.text("Add task", "Lägg till uppgift") : language.text("Edit task", "Redigera uppgift"))
                    .calendarTypography(.sectionTitle)

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Project", "Projekt"))
                                .calendarTypography(.fieldLabel)
                            Text(project?.displayName(for: language) ?? "")
                                .calendarTypography(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                                        .fill(AppPalette.secondaryCardSurface)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Title", "Rubrik"))
                                .calendarTypography(.fieldLabel)
                            TextField(language.text("Task title", "Rubrik för uppgiften"), text: $title)
                                .appTextInputChrome()
                        }

                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(language.text("Date", "Datum"))
                                    .calendarTypography(.fieldLabel)
                                CalendarDateInputField(placeholder: language.datePlaceholder, text: $deadline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(language.text("Reminder", "Händelse"))
                                    .calendarTypography(.fieldLabel)
                                AppMenuSelectionField(
                                    selection: $reminder,
                                    options: ProjectTaskReminder.projectOptions.map { ($0.displayName(language: language), $0) },
                                    placeholder: nil
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Comment", "Kommentar"))
                                .calendarTypography(.fieldLabel)
                            TextField(language.text("Comment", "Kommentar"), text: $note, axis: .vertical)
                                .appTextInputChrome()
                                .lineLimit(2...6)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(language.text("Participants", "Deltagare"))
                                .calendarTypography(.fieldLabel)
                            ForEach(Array(participantRows.enumerated()), id: \.element.id) { index, row in
                                HStack(spacing: 8) {
                                    AutocompleteSelectionField(
                                        text: participantBinding(at: index),
                                        options: participantOptions,
                                        placeholder: language.text("Participant", "Deltagare"),
                                        onCommit: { normalizeParticipantRows() },
                                        onSelect: { selected in
                                            guard participantRows.indices.contains(index) else { return }
                                            participantRows[index].name = selected
                                            normalizeParticipantRows()
                                        },
                                        showsSuggestionsWithoutQuery: true
                                    )

                                    if row.name.trimmedOrNil != nil {
                                        AppRowDeleteIconButton(
                                            title: language.text("Remove participant", "Ta bort deltagare"),
                                            cancelTitle: language.text("Cancel", "Avbryt"),
                                            confirmationTitle: language.text("Remove participant?", "Ta bort deltagare?")
                                        ) {
                                            guard participantRows.indices.contains(index) else { return }
                                            participantRows.remove(at: index)
                                            normalizeParticipantRows()
                                        }
                                    }
                                }
                            }
                        }

                        linkedSelectionField(
                            title: language.text("Publication", "Publikation"),
                            text: $publicationLabel,
                            options: publicationOptions.map(\.label),
                            placeholder: language.text("Publication", "Publikation")
                        )

                        CalendarGrantSelectionField(language: language, text: $applicationLabel, options: applicationOptions)
                        CalendarTaskCompletionDateField(language: language, text: $completionDate)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    CalendarAgendaProtocolColumn(
                        language: language,
                        agendaText: $agendaText,
                        protocolText: $protocolText
                    )
                    .frame(width: calendarEditorSideColumnWidth(for: dialogWidth))
                }

                FootprintDialogActions(
                    cancelTitle: language.text("Cancel", "Avbryt"),
                    primaryTitle: language.text("Save", "Spara"),
                    isPrimaryDisabled: title.trimmedOrNil == nil,
                    cancelAction: { dismiss() },
                    primaryAction: { save() }
                )
            }
        }
        .onAppear(perform: loadExistingTaskIfNeeded)
    }

    private func save() {
        guard var updatedProject = project,
              !updatedProject.isEditingLocked else {
            dismiss()
            return
        }

        var tasks = updatedProject.projectTasks
        if let taskID,
           let existingIndex = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[existingIndex].deadline = deadline
            tasks[existingIndex].reminder = reminder
            tasks[existingIndex].comment = title
            tasks[existingIndex].note = note
            tasks[existingIndex].participantNames = normalizedParticipants
            tasks[existingIndex].publicationID = resolvedID(for: publicationLabel, in: publicationOptions)
            tasks[existingIndex].applicationID = resolvedCalendarGrantID(for: applicationLabel, in: applicationOptions)
            tasks[existingIndex].completedOn = completionDate
            tasks[existingIndex].agendaText = agendaText
            tasks[existingIndex].protocolText = protocolText
            tasks[existingIndex].updatedOn = todayString
            if tasks[existingIndex].createdOn.isEmpty {
                tasks[existingIndex].createdOn = todayString
            }
            tasks[existingIndex].normalize()
        } else {
            var task = ProjectTaskItem(
                createdOn: todayString,
                updatedOn: todayString,
                deadline: deadline,
                reminder: reminder,
                comment: title,
                note: note,
                participantNames: normalizedParticipants,
                publicationID: resolvedID(for: publicationLabel, in: publicationOptions),
                applicationID: resolvedCalendarGrantID(for: applicationLabel, in: applicationOptions),
                completedOn: completionDate,
                agendaText: agendaText,
                protocolText: protocolText
            )
            task.normalize()
            tasks.append(task)
        }

        updatedProject.projectTasks = tasks
            .map {
                var copy = $0
                copy.normalize()
                return copy
            }
            .filter { !$0.isEmpty }
        store.autosaveProjectRecord(updatedProject, previousID: projectID)
        dismiss()
    }

    private func loadExistingTaskIfNeeded() {
        guard !didLoadExistingValues else { return }
        defer { didLoadExistingValues = true }
        guard let existingTask else { return }
        title = existingTask.comment
        note = existingTask.note
        deadline = existingTask.deadline
        reminder = existingTask.reminder
        participantRows = existingTask.participantNames.map { CalendarTodoParticipantDraft(name: $0) }
        normalizeParticipantRows()
        publicationLabel = resolvedLabel(for: existingTask.publicationID, in: publicationOptions)
        applicationLabel = resolvedCalendarGrantLabel(for: existingTask.applicationID, in: applicationOptions)
        completionDate = existingTask.completedOn ?? ""
        agendaText = existingTask.agendaText
        protocolText = existingTask.protocolText
    }

    private func participantBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { participantRows.indices.contains(index) ? participantRows[index].name : "" },
            set: { newValue in
                guard participantRows.indices.contains(index) else { return }
                participantRows[index].name = newValue
                normalizeParticipantRows()
            }
        )
    }

    private func normalizeParticipantRows() {
        let nonEmptyRows = participantRows.filter { $0.name.trimmedOrNil != nil }
        participantRows = nonEmptyRows + [CalendarTodoParticipantDraft()]
    }

    @ViewBuilder
    private func linkedSelectionField(
        title: String,
        text: Binding<String>,
        options: [String],
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .calendarTypography(.fieldLabel)
            AutocompleteSelectionField(
                text: text,
                options: options,
                placeholder: placeholder,
                onCommit: {
                    text.wrappedValue = resolvedLabel(for: text.wrappedValue, in: options)
                },
                onSelect: { selected in
                    text.wrappedValue = selected
                },
                showsSuggestionsWithoutQuery: true
            )
        }
    }

    private func resolvedID(for label: String, in options: [(id: String, label: String)]) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return options.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame })?.id
    }

    private func resolvedLabel(for id: String?, in options: [(id: String, label: String)]) -> String {
        guard let id, let match = options.first(where: { $0.id == id }) else { return "" }
        return match.label
    }

    private func resolvedLabel(for label: String, in options: [String]) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return options.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) ?? trimmed
    }
}

struct CalendarPublicationTaskSheet: View {
    @ObservedObject var store: GrantDataStore
    let publicationID: String
    let taskID: String?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var participantRows: [CalendarTodoParticipantDraft] = [.init()]
    @State private var applicationLabel: String = ""
    @State private var deadline: String = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
    @State private var completionDate: String = ""
    @State private var agendaText: String = ""
    @State private var protocolText: String = ""
    @State private var didLoadExistingValues = false

    private var language: AppLanguage { store.language }
    private var todayString: String {
        DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
    }
    private var publication: PublicationRecord? {
        store.publications.first(where: { $0.id == publicationID })
    }
    private var existingTask: PublicationTaskItem? {
        publication?.publicationTasks.first(where: { $0.id == taskID })
    }
    private var participantOptions: [String] {
        Array(
            Set(
                store.publicationAuthors.map(\.displayName)
                    + (publication?.publicationTasks.flatMap(\.participantNames) ?? [])
            )
        )
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var applicationOptions: [CalendarGrantSelectionOption] {
        calendarGrantSelectionOptions(store: store, language: language)
    }
    private var normalizedParticipants: [String] {
        let trimmed = participantRows.compactMap { $0.name.trimmedOrNil }
        return Array(NSOrderedSet(array: trimmed)) as? [String] ?? trimmed
    }

    var body: some View {
        CalendarEditorDialogSurface { dialogWidth in
            VStack(alignment: .leading, spacing: 16) {
                Text(taskID == nil ? language.text("Add task", "Lägg till uppgift") : language.text("Edit task", "Redigera uppgift"))
                    .calendarTypography(.sectionTitle)

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Publication", "Publikation"))
                                .calendarTypography(.fieldLabel)
                            Text(publication?.title.nonEmpty ?? language.text("Untitled", "Utan titel"))
                                .calendarTypography(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                                        .fill(AppPalette.secondaryCardSurface)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Title", "Rubrik"))
                                .calendarTypography(.fieldLabel)
                            TextField(language.text("Task title", "Rubrik för uppgiften"), text: $title)
                                .appTextInputChrome()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Date", "Datum"))
                                .calendarTypography(.fieldLabel)
                            CalendarDateInputField(placeholder: language.datePlaceholder, text: $deadline)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Comment", "Kommentar"))
                                .calendarTypography(.fieldLabel)
                            TextField(language.text("Comment", "Kommentar"), text: $note, axis: .vertical)
                                .appTextInputChrome()
                                .lineLimit(2...6)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(language.text("Participants", "Deltagare"))
                                .calendarTypography(.fieldLabel)
                            ForEach(Array(participantRows.enumerated()), id: \.element.id) { index, row in
                                HStack(spacing: 8) {
                                    AutocompleteSelectionField(
                                        text: participantBinding(at: index),
                                        options: participantOptions,
                                        placeholder: language.text("Participant", "Deltagare"),
                                        onCommit: { normalizeParticipantRows() },
                                        onSelect: { selected in
                                            guard participantRows.indices.contains(index) else { return }
                                            participantRows[index].name = selected
                                            normalizeParticipantRows()
                                        },
                                        showsSuggestionsWithoutQuery: true
                                    )

                                    if row.name.trimmedOrNil != nil {
                                        AppRowDeleteIconButton(
                                            title: language.text("Remove participant", "Ta bort deltagare"),
                                            cancelTitle: language.text("Cancel", "Avbryt"),
                                            confirmationTitle: language.text("Remove participant?", "Ta bort deltagare?")
                                        ) {
                                            guard participantRows.indices.contains(index) else { return }
                                            participantRows.remove(at: index)
                                            normalizeParticipantRows()
                                        }
                                    }
                                }
                            }
                        }

                        CalendarGrantSelectionField(language: language, text: $applicationLabel, options: applicationOptions)
                        CalendarTaskCompletionDateField(language: language, text: $completionDate)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    CalendarAgendaProtocolColumn(
                        language: language,
                        agendaText: $agendaText,
                        protocolText: $protocolText
                    )
                    .frame(width: calendarEditorSideColumnWidth(for: dialogWidth))
                }

                FootprintDialogActions(
                    cancelTitle: language.text("Cancel", "Avbryt"),
                    primaryTitle: language.text("Save", "Spara"),
                    isPrimaryDisabled: title.trimmedOrNil == nil,
                    cancelAction: { dismiss() },
                    primaryAction: { save() }
                )
            }
        }
        .onAppear(perform: loadExistingTaskIfNeeded)
    }

    private func save() {
        guard var updatedPublication = publication,
              !updatedPublication.isEditingLocked else {
            dismiss()
            return
        }

        var tasks = updatedPublication.publicationTasks
        if let taskID,
           let existingIndex = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[existingIndex].deadline = deadline
            tasks[existingIndex].comment = title
            tasks[existingIndex].note = note
            tasks[existingIndex].participantNames = normalizedParticipants
            tasks[existingIndex].applicationID = resolvedCalendarGrantID(for: applicationLabel, in: applicationOptions)
            tasks[existingIndex].completedOn = completionDate
            tasks[existingIndex].agendaText = agendaText
            tasks[existingIndex].protocolText = protocolText
            tasks[existingIndex].updatedOn = todayString
            if tasks[existingIndex].createdOn.isEmpty {
                tasks[existingIndex].createdOn = todayString
            }
            tasks[existingIndex].normalize()
        } else {
            var task = PublicationTaskItem(
                createdOn: todayString,
                updatedOn: todayString,
                deadline: deadline,
                comment: title,
                note: note,
                participantNames: normalizedParticipants,
                applicationID: resolvedCalendarGrantID(for: applicationLabel, in: applicationOptions),
                completedOn: completionDate,
                agendaText: agendaText,
                protocolText: protocolText
            )
            task.normalize()
            tasks.append(task)
        }

        updatedPublication.publicationTasks = normalizedPublicationTaskItems(tasks)
            .filter { !$0.isEmpty }
        store.autosavePublication(updatedPublication)
        dismiss()
    }

    private func loadExistingTaskIfNeeded() {
        guard !didLoadExistingValues else { return }
        defer { didLoadExistingValues = true }
        guard let existingTask else { return }
        title = existingTask.comment
        note = existingTask.note
        deadline = existingTask.deadline
        participantRows = existingTask.participantNames.map { CalendarTodoParticipantDraft(name: $0) }
        normalizeParticipantRows()
        applicationLabel = resolvedCalendarGrantLabel(for: existingTask.applicationID, in: applicationOptions)
        completionDate = existingTask.completedOn ?? ""
        agendaText = existingTask.agendaText
        protocolText = existingTask.protocolText
    }

    private func participantBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { participantRows.indices.contains(index) ? participantRows[index].name : "" },
            set: { newValue in
                guard participantRows.indices.contains(index) else { return }
                participantRows[index].name = newValue
                normalizeParticipantRows()
            }
        )
    }

    private func normalizeParticipantRows() {
        let nonEmptyRows = participantRows.filter { $0.name.trimmedOrNil != nil }
        participantRows = nonEmptyRows + [CalendarTodoParticipantDraft()]
    }

    private func resolvedID(for label: String, in options: [(id: String, label: String)]) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return options.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame })?.id
    }

    private func resolvedLabel(for id: String?, in options: [(id: String, label: String)]) -> String {
        guard let id, let match = options.first(where: { $0.id == id }) else { return "" }
        return match.label
    }

    private func resolvedLabel(for label: String, in options: [String]) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return options.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) ?? trimmed
    }
}

private struct CalendarCongressFlightEditContext: Hashable {
    let organizationID: String
    let congressID: String
    let flightID: String
}

private struct CalendarTravelSheet: View {
    @ObservedObject var store: GrantDataStore
    let travelID: String?
    let congressFlightContext: CalendarCongressFlightEditContext?
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CalendarTravelRecord
    @State private var didLoadExistingValues = false
    @State private var fromCountryText = ""
    @State private var toCountryText = ""
    @State private var congressText = ""
    @State private var committedDepartureTimeForShift: String?

    init(
        store: GrantDataStore,
        travelID: String?,
        initialDateString: String? = nil,
        congressFlightContext: CalendarCongressFlightEditContext? = nil
    ) {
        self.store = store
        self.travelID = travelID
        self.congressFlightContext = congressFlightContext
        let initialDate = calendarSheetInitialDateString(initialDateString)
        _draft = State(initialValue: CalendarTravelRecord(date: initialDate, arrivalDate: initialDate))
    }

    private var language: AppLanguage { store.language }
    private var existingRecord: CalendarTravelRecord? {
        if let congressFlightContext {
            return calendarTravelRecord(from: congressFlightContext)
        }
        guard let travelID else { return nil }
        return store.calendarTravelRecords.first(where: { $0.id == travelID })
    }

    private var congressOptions: [CalendarCongressSelectionOption] {
        store.organizationsForCongressRead.flatMap { organization in
            organization.congresses.compactMap { congress -> CalendarCongressSelectionOption? in
                guard !congress.isEmpty else { return nil }
                let title = congress.title.nonEmpty ?? organization.displayName(for: language)
                guard title.trimmedOrNil != nil else { return nil }
                return CalendarCongressSelectionOption(
                    organizationID: organization.id,
                    congressID: congress.id,
                    title: title,
                    organizationName: organization.displayName(for: language),
                    dateText: calendarCongressOptionDateText(congress)
                )
            }
        }
        .sorted { left, right in
            let leftDate = calendarCongressOptionSortDate(left)
            let rightDate = calendarCongressOptionSortDate(right)
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            return left.menuTitle.localizedStandardCompare(right.menuTitle) == .orderedAscending
        }
    }

    private var congressSelectionBinding: Binding<String> {
        Binding(
            get: {
                guard draft.congressOrganizationID.trimmedOrNil != nil,
                      draft.congressID.trimmedOrNil != nil else {
                    return ""
                }
                return calendarCongressSelectionKey(
                    organizationID: draft.congressOrganizationID,
                    congressID: draft.congressID
                )
            },
            set: { newValue in
                guard let selected = calendarCongressSelectionIDs(from: newValue) else {
                    draft.congressOrganizationID = ""
                    draft.congressID = ""
                    return
                }
                draft.congressOrganizationID = selected.organizationID
                draft.congressID = selected.congressID
            }
        )
    }

    private var congressOptionLabels: [String] {
        Array(NSOrderedSet(array: congressOptions.map(\.menuTitle))) as? [String] ?? congressOptions.map(\.menuTitle)
    }

    private var selectedCongressOption: CalendarCongressSelectionOption? {
        congressOptions.first {
            $0.organizationID == draft.congressOrganizationID && $0.congressID == draft.congressID
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(travelID == nil ? language.text("Add travel", "Lägg till resa") : language.text("Edit travel", "Redigera resa"))
                    .calendarTypography(.sectionTitle)

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(language.text("From", "Från"))
                            .calendarTypography(.fieldLabel)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Date", "Datum"))
                                .calendarTypography(.fieldLabel)
                            uncertainCalendarDateField(
                                text: departureDateBinding,
                                uncertain: $draft.dateUncertain
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Time", "Klockslag"))
                                .calendarTypography(.fieldLabel)
                            uncertainCalendarField(
                                placeholder: "HH:MM",
                                text: departureTimeBinding,
                                uncertain: $draft.departureTimeUncertain
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("City", "Ort"))
                                .calendarTypography(.fieldLabel)
                            TextField(language.text("City", "Ort"), text: $draft.fromCity)
                                .appTextInputChrome()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Country", "Land"))
                                .calendarTypography(.fieldLabel)
                            countryAutocompleteField(text: $fromCountryText, selection: $draft.fromCountry)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(language.text("To", "Till"))
                            .calendarTypography(.fieldLabel)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Date", "Datum"))
                                .calendarTypography(.fieldLabel)
                            CalendarDateInputField(placeholder: language.datePlaceholder, text: $draft.arrivalDate)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Time", "Klockslag"))
                                .calendarTypography(.fieldLabel)
                            uncertainCalendarField(
                                placeholder: "HH:MM",
                                text: $draft.arrivalTime,
                                uncertain: $draft.arrivalTimeUncertain
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("City", "Ort"))
                                .calendarTypography(.fieldLabel)
                            TextField(language.text("City", "Ort"), text: $draft.toCity)
                                .appTextInputChrome()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Country", "Land"))
                                .calendarTypography(.fieldLabel)
                            countryAutocompleteField(text: $toCountryText, selection: $draft.toCountry)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Mode", "Färdsätt"))
                        .calendarTypography(.fieldLabel)
                    HStack(spacing: 12) {
                        ForEach(CalendarTravelMode.allCases) { mode in
                            Toggle(
                                mode.localizedName(language: language),
                                isOn: travelModeCheckboxBinding(mode)
                            )
                            .appCheckboxStyle()
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .disabled(congressFlightContext != nil)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Congress", "Kongress"))
                        .calendarTypography(.fieldLabel)
                    AutocompleteSelectionField(
                        text: $congressText,
                        options: congressOptionLabels,
                        placeholder: language.text("Search congress", "Sök kongress"),
                        onCommit: commitCongressText,
                        onSelect: { selected in
                            selectCongressOption(matching: selected)
                        },
                        showsSuggestionsWithoutQuery: true
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Travel reference", "Färdreferens"))
                        .calendarTypography(.fieldLabel)
                    TextField(language.text("Reference", "Referens"), text: $draft.reference)
                        .appTextInputChrome()
                }

                FootprintDialogActions(
                    cancelTitle: language.text("Cancel", "Avbryt"),
                    primaryTitle: language.text("Save", "Spara"),
                    isPrimaryDisabled:
                        draft.date.trimmedOrNil == nil
                            || (congressFlightContext != nil && (
                                draft.congressOrganizationID.trimmedOrNil == nil
                                    || draft.congressID.trimmedOrNil == nil
                            )),
                    cancelAction: { dismiss() },
                    primaryAction: { save() }
                )
            }
            .padding(22)
        }
        .appResponsiveDialogFrame(idealWidth: 640, idealHeight: 620)
        .autocompleteOverlayHost()
        .onAppear {
            loadExistingTravelIfNeeded()
        }
        .onChange(of: draft.date) { oldValue, _ in
            synchronizeArrivalDateIfNeeded(previousDate: oldValue, previousDepartureTime: draft.departureTime, previousArrivalTime: draft.arrivalTime)
        }
        .onChange(of: draft.departureTime) { oldValue, _ in
            synchronizeArrivalDateIfNeeded(previousDate: draft.date, previousDepartureTime: oldValue, previousArrivalTime: draft.arrivalTime)
        }
        .onChange(of: draft.arrivalTime) { oldValue, _ in
            synchronizeArrivalDateIfNeeded(previousDate: draft.date, previousDepartureTime: draft.departureTime, previousArrivalTime: oldValue)
        }
    }

    private func save() {
        commitCongressText()
        draft.fromCountry = canonicalCalendarCountryName(fromCountryText)
        draft.toCountry = canonicalCalendarCountryName(toCountryText)
        var normalized = draft
        normalized.normalize()
        if let congressFlightContext {
            saveCongressFlight(context: congressFlightContext, travel: normalized)
            dismiss()
            return
        }
        let previousRecord = existingRecord
        var records = store.calendarTravelRecords
        if let travelID,
           let existingIndex = records.firstIndex(where: { $0.id == travelID }) {
            records[existingIndex] = normalized
        } else {
            records.append(normalized)
        }
        store.autosaveCalendarTravelRecords(records)
        store.syncCalendarTravelWithCongressPlan(previous: previousRecord, current: normalized)
        dismiss()
    }

    private func calendarTravelRecord(from context: CalendarCongressFlightEditContext) -> CalendarTravelRecord? {
        guard let organization = store.organization(id: context.organizationID),
              let congress = organization.congresses.first(where: { $0.id == context.congressID }),
              let flight = congress.travelFlights.first(where: { $0.id == context.flightID }) else {
            return nil
        }
        return CalendarTravelRecord(
            id: flight.id,
            date: flight.fromDate,
            arrivalDate: flight.toDate,
            departureTime: flight.fromTime,
            fromCity: flight.fromCity,
            fromCountry: flight.fromCountry,
            arrivalTime: flight.toTime,
            toCity: flight.toCity,
            toCountry: flight.toCountry,
            mode: flight.mode,
            congressOrganizationID: organization.id,
            congressID: congress.id
        )
    }

    private func saveCongressFlight(
        context: CalendarCongressFlightEditContext,
        travel: CalendarTravelRecord
    ) {
        guard let targetOrganizationID = travel.congressOrganizationID.trimmedOrNil,
              let targetCongressID = travel.congressID.trimmedOrNil,
              store.organization(id: targetOrganizationID) != nil else {
            return
        }
        var normalized = travel
        normalized.id = context.flightID
        normalized.normalize()
        guard !normalized.isEmpty else { return }

        var records = store.calendarTravelRecords
        if let index = records.firstIndex(where: { $0.id == normalized.id }) {
            records[index] = normalized
        } else {
            records.append(normalized)
        }
        store.autosaveCalendarTravelRecords(records)
        store.markCongressAsAttendingIfNeeded(
            organizationID: targetOrganizationID,
            congressID: targetCongressID
        )
    }

    private func autosaveOrganization(_ organization: OrganizationRecord, congresses: [OrganizationCongress]) {
        store.autosaveOrganization(
            id: organization.id,
            nameSv: organization.nameSv,
            nameEn: organization.nameEn,
            addressLine: organization.addressLine,
            postalCode: organization.postalCode,
            city: organization.city,
            country: organization.country,
            category: organization.category,
            roles: organization.roles,
            note: organization.note,
            websiteURL: organization.websiteURL,
            phoneNumber: organization.phoneNumber,
            organizationNumber: organization.organizationNumber,
            vatNumber: organization.vatNumber,
            employerContacts: organization.employerContacts,
            flag: organization.flag,
            membershipFrom: organization.membershipFrom,
            membershipTo: organization.membershipTo,
            congresses: congresses,
            projectTasks: organization.projectTasks,
            salaryCalculator: organization.salaryCalculator
        )
    }

    private var departureDateBinding: Binding<String> {
        Binding(
            get: { draft.date },
            set: { newValue in
                let previousDate = draft.date
                draft.date = newValue
                if let shiftedArrivalDate = shiftedDateRangeEnd(
                    previousStart: previousDate,
                    newStart: newValue,
                    currentEnd: draft.arrivalDate
                ) {
                    draft.arrivalDate = shiftedArrivalDate
                }
            }
        )
    }

    private var departureTimeBinding: Binding<String> {
        Binding(
            get: { draft.departureTime },
            set: { newValue in
                let update = updatingCommittedDateTimeRangeEnd(
                    previousCommittedStartDate: draft.date,
                    previousCommittedStartTime: committedDepartureTimeForShift,
                    newStartDate: draft.date,
                    newStartTimeInput: newValue,
                    currentEndDate: draft.arrivalDate,
                    currentEndTime: draft.arrivalTime
                )
                draft.departureTime = newValue
                if let shiftedArrival = update.shiftedEnd {
                    draft.arrivalDate = shiftedArrival.date
                    draft.arrivalTime = shiftedArrival.time
                }
                committedDepartureTimeForShift = update.committedStartTime
            }
        )
    }

    @ViewBuilder
    private func uncertainCalendarDateField(
        text: Binding<String>,
        uncertain: Binding<Bool>
    ) -> some View {
        let hasValue = text.wrappedValue.trimmedOrNil != nil
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 8) {
                CalendarDateInputField(placeholder: language.datePlaceholder, text: text)
            }
            .calendarDateStatusOutline(isUncertain: uncertain.wrappedValue)
            .contextMenu {
                if hasValue {
                    Button(
                        uncertain.wrappedValue
                            ? "✓ " + language.text("Uncertain date", "Osäkert datum")
                            : language.text("Uncertain date", "Osäkert datum")
                    ) {
                        uncertain.wrappedValue.toggle()
                    }
                } else {
                    Button(language.text("Uncertain date", "Osäkert datum")) {}
                        .disabled(true)
                }
            }

            if uncertain.wrappedValue {
                Text("?")
                    .font(appBadgeFont())
                    .foregroundStyle(AppPalette.statusText(.warning))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppPalette.canvasTop.opacity(0.96))
                    )
                    .offset(x: -6, y: 6)
            }
        }
    }

    @ViewBuilder
    private func uncertainCalendarField(
        placeholder: String,
        text: Binding<String>,
        uncertain: Binding<Bool>
    ) -> some View {
        let hasValue = text.wrappedValue.trimmedOrNil != nil
        ZStack(alignment: .topTrailing) {
            CalendarTimeInputField(placeholder: placeholder, text: text)
                .calendarDateStatusOutline(isUncertain: uncertain.wrappedValue)
                .contextMenu {
                    if hasValue {
                        Button(
                            uncertain.wrappedValue
                                ? "✓ " + language.text("Uncertain date", "Osäkert datum")
                                : language.text("Uncertain date", "Osäkert datum")
                        ) {
                            uncertain.wrappedValue.toggle()
                        }
                    } else {
                        Button(language.text("Uncertain date", "Osäkert datum")) {}
                            .disabled(true)
                    }
                }

            if uncertain.wrappedValue {
                Text("?")
                    .font(appBadgeFont())
                    .foregroundStyle(AppPalette.statusText(.warning))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppPalette.canvasTop.opacity(0.96))
                    )
                    .offset(x: -6, y: 6)
            }
        }
    }

    private func loadExistingTravelIfNeeded() {
        guard !didLoadExistingValues else { return }
        defer { didLoadExistingValues = true }
        guard let existingRecord else {
            if draft.arrivalDate.trimmedOrNil == nil {
                draft.arrivalDate = draft.date
            }
            fromCountryText = localizedCalendarCountryName(draft.fromCountry)
            toCountryText = localizedCalendarCountryName(draft.toCountry)
            refreshCongressTextFromDraft()
            committedDepartureTimeForShift = committedCalendarTimeForRangeShift(draft.departureTime)
            return
        }
        var normalized = existingRecord
        normalized.normalize()
        draft = normalized
        fromCountryText = localizedCalendarCountryName(normalized.fromCountry)
        toCountryText = localizedCalendarCountryName(normalized.toCountry)
        refreshCongressTextFromDraft()
        committedDepartureTimeForShift = committedCalendarTimeForRangeShift(normalized.departureTime)
    }

    private func commitCongressText() {
        guard congressText.trimmedOrNil != nil else {
            draft.congressOrganizationID = ""
            draft.congressID = ""
            congressText = ""
            return
        }
        guard selectCongressOption(matching: congressText) else {
            congressText = selectedCongressOption?.menuTitle ?? ""
            return
        }
    }

    @discardableResult
    private func selectCongressOption(matching text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let option = congressOptions.first(where: {
                  $0.menuTitle.caseInsensitiveCompare(trimmed) == .orderedSame
                      || $0.title.caseInsensitiveCompare(trimmed) == .orderedSame
                      || $0.id == trimmed
              }) else { return false }
        draft.congressOrganizationID = option.organizationID
        draft.congressID = option.congressID
        congressText = option.menuTitle
        return true
    }

    private func refreshCongressTextFromDraft() {
        congressText = selectedCongressOption?.menuTitle ?? ""
    }

    private func travelModeCheckboxBinding(_ mode: CalendarTravelMode) -> Binding<Bool> {
        Binding(
            get: { draft.mode == mode },
            set: { isSelected in
                if isSelected {
                    draft.mode = mode
                }
            }
        )
    }

    private func synchronizeArrivalDateIfNeeded(
        previousDate: String,
        previousDepartureTime: String,
        previousArrivalTime: String
    ) {
        var previousSnapshot = draft
        previousSnapshot.date = previousDate
        previousSnapshot.departureTime = previousDepartureTime
        previousSnapshot.arrivalTime = previousArrivalTime
        previousSnapshot.arrivalDate = ""
        let previousDerived = previousSnapshot.derivedArrivalDateString()
        let currentArrivalDate = draft.arrivalDate.trimmedOrNil
        guard currentArrivalDate == nil || currentArrivalDate == previousDerived else { return }

        var currentSnapshot = draft
        currentSnapshot.arrivalDate = ""
        draft.arrivalDate = currentSnapshot.derivedArrivalDateString()
    }

    private var localizedCountryOptions: [String] {
        GrantParsing.countryOptions
            .map { language.localizedCountry($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func calendarCongressOptionDateText(_ congress: OrganizationCongress) -> String {
        [congress.from.nonEmpty, congress.to.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private func calendarCongressOptionSortDate(_ option: CalendarCongressSelectionOption) -> Date {
        store.organization(id: option.organizationID)?
            .congresses
            .first(where: { $0.id == option.congressID })?
            .from
            .nonEmpty
            .flatMap(DateParsers.isoDay.date(from:))
            ?? .distantFuture
    }

    private func canonicalCalendarCountryName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let exact = GrantParsing.countryOptions.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact
        }
        if let localized = GrantParsing.countryOptions.first(where: {
            language.localizedCountry($0).caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return localized
        }
        let heuristic = GrantParsing.canonicalCountryName(trimmed)
        if let canonical = GrantParsing.countryOptions.first(where: { $0.caseInsensitiveCompare(heuristic) == .orderedSame }) {
            return canonical
        }
        return trimmed
    }

    private func localizedCalendarCountryName(_ raw: String) -> String {
        let canonical = canonicalCalendarCountryName(raw)
        guard !canonical.isEmpty else { return "" }
        return GrantParsing.countryOptions.contains(canonical) ? language.localizedCountry(canonical) : canonical
    }

    @ViewBuilder
    private func countryAutocompleteField(text: Binding<String>, selection: Binding<String>) -> some View {
        AutocompleteSelectionField(
            text: text,
            options: localizedCountryOptions,
            placeholder: language.text("Country", "Land"),
            onCommit: {
                let canonical = canonicalCalendarCountryName(text.wrappedValue)
                selection.wrappedValue = canonical
                text.wrappedValue = localizedCalendarCountryName(canonical)
            },
            onSelect: { selected in
                let canonical = canonicalCalendarCountryName(selected)
                selection.wrappedValue = canonical
                text.wrappedValue = localizedCalendarCountryName(canonical)
            },
            showsSuggestionsWithoutQuery: true
        )
        .frame(width: 220, alignment: .leading)
    }
}

private struct CalendarMeetingParticipantDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
}

// MARK: - Round 7: one set of link rows for activities and tasks

/// The researchers offered in the participant rows of both editors.
@MainActor
private func calendarLinkParticipantOptions(store: GrantDataStore) -> [String] {
    store.publicationAuthors
        .map(\.displayName)
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

/// The choices of every link row, built the same way for the activity
/// editor and the task editor.
private struct CalendarLinkOptionSets {
    var projects: [CalendarLinkOption]
    var organizations: [CalendarLinkOption]
    var applications: [CalendarLinkOption]
    var publications: [CalendarLinkOption]
    var mediaAppearances: [CalendarLinkOption]
    var teaching: [CalendarLinkOption]
    var doctoralCandidates: [CalendarLinkOption]

    /// `keepingLockedIDs`: when given, locked projects and publications are
    /// left out except these (the task editor's earlier behaviour).
    @MainActor
    init(store: GrantDataStore, language: AppLanguage, keepingLockedIDs: Set<String>? = nil) {
        func sorted(_ options: [CalendarLinkOption]) -> [CalendarLinkOption] {
            options.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }
        func isOffered(id: String, isLocked: Bool) -> Bool {
            guard let keepingLockedIDs else { return true }
            return !isLocked || keepingLockedIDs.contains(id)
        }
        projects = sorted(
            store.projects
                .filter { isOffered(id: $0.id, isLocked: $0.isEditingLocked) }
                .map { CalendarLinkOption(id: $0.id, label: $0.displayName(for: language)) }
        )
        organizations = sorted(
            store.organizations.map { CalendarLinkOption(id: $0.id, label: $0.displayName(for: language)) }
        )
        applications = sorted(
            store.applications.map { application in
                CalendarLinkOption(
                    id: application.id,
                    label: calendarLinkApplicationLabel(application, store: store, language: language)
                )
            }
        )
        publications = sorted(
            store.publications
                .filter { isOffered(id: $0.id, isLocked: $0.isEditingLocked) }
                .map { publication in
                    let title = publication.title.nonEmpty
                        ?? language.text("Untitled publication", "Namnlös publikation")
                    let detail = [publication.journal.nonEmpty, publication.year.nonEmpty]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    return CalendarLinkOption(id: publication.id, label: detail.isEmpty ? title : "\(title) (\(detail))")
                }
        )
        mediaAppearances = sorted(
            store.cvMediaAppearances.map { appearance in
                let title = appearance.localizedTitle(language: language).nonEmpty
                    ?? appearance.displayTitle
                let date = appearance.date.nonEmpty
                return CalendarLinkOption(id: appearance.id, label: date.map { "\(title) (\($0))" } ?? title)
            }
        )
        teaching = calendarTeachingLinkOptions(
            courses: store.teachingCourses,
            assignments: store.teachingAssignments,
            courseLabel: { calendarTeachingCourseLabel($0, language: language) },
            assignmentLabel: { calendarTeachingAssignmentLabel($0, store: store, language: language) }
        )
        doctoralCandidates = sorted(
            store.doctoralCandidates.map { candidate in
                let name = candidate.candidateName.nonEmpty
                    ?? language.text("Unnamed doctoral candidate", "Namnlös doktorand")
                let project = candidate.doctoralProjectName.nonEmpty
                return CalendarLinkOption(id: candidate.id, label: project.map { "\(name) · \($0)" } ?? name)
            }
        )
    }
}

/// "Grant (funder · year)", as the activity editor has always shown grants.
@MainActor
private func calendarLinkApplicationLabel(
    _ application: GrantApplication,
    store: GrantDataStore,
    language: AppLanguage
) -> String {
    let title = store.localizedGrantName(for: application, language: language).nonEmpty
        ?? application.grantName.nonEmpty
        ?? language.text("Untitled grant", "Namnlöst anslag")
    let organization = application.organization.nonEmpty.map {
        store.organizationLabel(for: $0, language: language)
    }
    func leadingYear(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmedOrNil, trimmed.count >= 4 else { return nil }
        let year = String(trimmed.prefix(4))
        return year.count == 4 && year.allSatisfy(\.isNumber) ? year : nil
    }
    let year = application.appliedYear?.trimmedOrNil
        ?? leadingYear(application.appliedOn)
        ?? leadingYear(application.closesOn)
        ?? leadingYear(application.grantedOn)
    let detail = [organization, year].compactMap { $0?.trimmedOrNil }.joined(separator: " · ")
    return detail.isEmpty ? title : "\(title) (\(detail))"
}

/// The written "Ta bort" button at the end of a filled link or participant row.
private struct CalendarLinkRowRemoveButton: View {
    static let width: CGFloat = 56

    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(language.text("Remove", "Ta bort"), action: action)
            .buttonStyle(.borderless)
            .font(appFont(.secondary).weight(.semibold))
            .foregroundStyle(AppPalette.actionDelete)
            .help(language.text("Remove this row", "Ta bort raden"))
            .frame(width: Self.width, alignment: .leading)
    }
}

private struct CalendarLinkRowDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var label: String = ""
}

/// One link kind as rows: a searchable field per linked record, a written
/// "Ta bort" button on filled rows, and always one empty row at the end for
/// the next link. The rows are kept as ids in `ids`.
private struct CalendarLinkRowsField: View {
    let title: String
    let placeholder: String
    let options: [CalendarLinkOption]
    @Binding var ids: [String]
    let language: AppLanguage
    var preservesOptionOrder = false

    @State private var rows: [CalendarLinkRowDraft] = [CalendarLinkRowDraft()]

    var body: some View {
        let labels = options.map(\.label)
        let indentedLabels = Set(options.filter { $0.indentLevel > 0 }.map(\.label))
        VStack(alignment: .leading, spacing: AutocompleteSelectionMetrics.rowSpacing) {
            Text(title)
                .calendarTypography(.fieldLabel)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 8) {
                    AutocompleteSelectionField(
                        text: rowBinding(at: index),
                        options: labels,
                        excludedOptions: Set(rows.enumerated().compactMap { rowIndex, other in
                            rowIndex == index ? nil : other.label.trimmedOrNil
                        }),
                        placeholder: placeholder,
                        display: { label in
                            indentedLabels.contains(label) ? "\u{2003}\u{2003}" + label : label
                        },
                        onCommit: {},
                        onSelect: { selected in
                            rowBinding(at: index).wrappedValue = selected
                        },
                        showsSuggestionsWithoutQuery: true,
                        preservesOptionOrder: preservesOptionOrder
                    )

                    if row.label.trimmedOrNil != nil {
                        CalendarLinkRowRemoveButton(language: language) {
                            removeRow(at: index)
                        }
                    } else {
                        Color.clear.frame(width: CalendarLinkRowRemoveButton.width, height: 18)
                    }
                }
            }
        }
        .onAppear {
            syncRows(from: ids, force: true)
        }
        .onChange(of: ids) { _, newIDs in
            syncRows(from: newIDs, force: false)
        }
    }

    private func rowBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard rows.indices.contains(index) else { return "" }
                return rows[index].label
            },
            set: { newValue in
                guard rows.indices.contains(index) else { return }
                rows[index].label = newValue
                ensureTrailingRow()
                publishIDs()
            }
        )
    }

    private func removeRow(at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
        ensureTrailingRow()
        publishIDs()
    }

    private func ensureTrailingRow() {
        let blankRow = rows.first(where: { $0.label.trimmedOrNil == nil }) ?? CalendarLinkRowDraft()
        rows = rows.filter { $0.label.trimmedOrNil != nil } + [blankRow]
    }

    private func publishIDs() {
        let resolved = calendarLinkIDs(forLabels: rows.map(\.label), options: options)
        if resolved != ids {
            ids = resolved
        }
    }

    /// Rebuilds the rows when the ids change from outside (the editor loads a
    /// record). A change the rows made themselves is left alone, so a row
    /// that is being typed is not cleared.
    private func syncRows(from newIDs: [String], force: Bool) {
        if !force, calendarLinkIDs(forLabels: rows.map(\.label), options: options) == newIDs {
            return
        }
        rows = calendarLinkLabels(forIDs: newIDs, options: options).map { CalendarLinkRowDraft(label: $0) }
            + [CalendarLinkRowDraft()]
    }
}

/// The participant rows of both editors: a researcher field per person
/// (free text is allowed), a drag handle to reorder, a written "Ta bort"
/// button, and one empty row at the end. The names are linked to researchers
/// by id when the record is saved.
private struct CalendarParticipantRowsField: View {
    @Binding var rows: [CalendarMeetingParticipantDraft]
    let options: [String]
    let language: AppLanguage

    @State private var draggedParticipantID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AutocompleteSelectionMetrics.rowSpacing) {
            Text(language.text("Participants", "Deltagare"))
                .calendarTypography(.fieldLabel)

            VStack(alignment: .leading, spacing: AutocompleteSelectionMetrics.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, participant in
                    let hasValue = participant.name.trimmedOrNil != nil
                    HStack(spacing: 8) {
                        if hasValue {
                            ReorderHandle(itemID: participant.id, draggedItemID: $draggedParticipantID, language: language)
                        } else {
                            Color.clear.frame(width: 20, height: 20)
                        }

                        AutocompleteSelectionField(
                            text: participantBinding(at: index),
                            options: options,
                            excludedOptions: Set(rows.enumerated().compactMap { rowIndex, row in
                                rowIndex == index ? nil : row.name.trimmedOrNil
                            }),
                            placeholder: language.text("Participant", "Deltagare"),
                            onCommit: {},
                            onSelect: { selected in
                                participantBinding(at: index).wrappedValue = selected
                            },
                            showsSuggestionsWithoutQuery: true
                        )

                        if hasValue {
                            CalendarLinkRowRemoveButton(language: language) {
                                removeParticipant(at: index)
                            }
                        } else {
                            Color.clear.frame(width: CalendarLinkRowRemoveButton.width, height: 18)
                        }
                    }
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: IdentifiedReorderDropDelegate(
                            targetID: participant.id,
                            items: $rows,
                            draggedItemID: $draggedParticipantID,
                            onReorder: ensureTrailingRow
                        )
                    )
                }
            }
        }
        .onAppear(perform: ensureTrailingRow)
    }

    private func participantBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard rows.indices.contains(index) else { return "" }
                return rows[index].name
            },
            set: { newValue in
                guard rows.indices.contains(index) else { return }
                rows[index].name = newValue
                ensureTrailingRow()
            }
        )
    }

    private func removeParticipant(at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
        ensureTrailingRow()
    }

    private func ensureTrailingRow() {
        let blankRow = rows.first(where: { $0.name.trimmedOrNil == nil }) ?? CalendarMeetingParticipantDraft()
        let filledRows = rows.filter { $0.name.trimmedOrNil != nil }
        let updated = filledRows + [blankRow]
        if updated != rows {
            rows = updated
        }
    }
}

/// The link rows both editors show, in the same order and layout:
/// Project and Organization, Teaching (courses with their assignments),
/// Doctoral candidate, then Grant and Publication.
private struct CalendarLinkRowsSection: View {
    let language: AppLanguage
    let options: CalendarLinkOptionSets
    @Binding var projectIDs: [String]
    @Binding var organizationIDs: [String]
    @Binding var applicationIDs: [String]
    @Binding var publicationIDs: [String]
    @Binding var teachingOptionIDs: [String]
    @Binding var doctoralCandidateIDs: [String]
    /// False for an older task kept on the teaching list, which can only
    /// hold a project, a publication and a grant.
    var showsAllKinds = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                CalendarLinkRowsField(
                    title: language.text("Project", "Projekt"),
                    placeholder: language.text("Project", "Projekt"),
                    options: options.projects,
                    ids: $projectIDs,
                    language: language
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsAllKinds {
                    CalendarLinkRowsField(
                        title: language.text("Organization", "Organisation"),
                        placeholder: language.text("Organization", "Organisation"),
                        options: options.organizations,
                        ids: $organizationIDs,
                        language: language
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if showsAllKinds {
                CalendarLinkRowsField(
                    title: language.text("Teaching", "Undervisning"),
                    placeholder: language.text("Course or teaching assignment", "Kurs eller undervisningsuppdrag"),
                    options: options.teaching,
                    ids: $teachingOptionIDs,
                    language: language,
                    preservesOptionOrder: true
                )

                CalendarLinkRowsField(
                    title: language.text("Doctoral candidate", "Doktorand"),
                    placeholder: language.text("Doctoral candidate", "Doktorand"),
                    options: options.doctoralCandidates,
                    ids: $doctoralCandidateIDs,
                    language: language
                )
            }

            HStack(alignment: .top, spacing: 16) {
                CalendarLinkRowsField(
                    title: language.text("Grant", "Anslag"),
                    placeholder: language.text("Grant", "Anslag"),
                    options: options.applications,
                    ids: $applicationIDs,
                    language: language
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                CalendarLinkRowsField(
                    title: language.text("Publication", "Publikation"),
                    placeholder: language.text("Publication", "Publikation"),
                    options: options.publications,
                    ids: $publicationIDs,
                    language: language
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct CalendarMeetingProjectDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var label: String = ""
}

private struct CalendarMeetingOrganizationDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var label: String = ""
}

private struct CalendarMeetingApplicationDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var label: String = ""
}

private struct CalendarMeetingPublicationDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var label: String = ""
}

private struct CalendarMeetingMediaAppearanceDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var label: String = ""
}

private struct CalendarMeetingTeachingAssignmentDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var label: String = ""
}

private struct CalendarMeetingDoctoralCandidateDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var label: String = ""
}

private struct CalendarMeetingTypeCatalogPopover: View {
    @ObservedObject var store: GrantDataStore
    let language: AppLanguage

    @State private var options: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("Categories", "Kategorier"))
                .calendarTypography(.panelTitle)

            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                HStack(spacing: 10) {
                    TextField(
                        language.text("Category", "Kategori"),
                        text: Binding(
                            get: {
                                guard options.indices.contains(index) else { return "" }
                                return options[index]
                            },
                            set: { newValue in
                                guard options.indices.contains(index) else { return }
                                options[index] = newValue
                                persist()
                            }
                        )
                    )
                    .appTextInputChrome()

                    if option.trimmedOrNil != nil {
                        AppRowDeleteIconButton(
                            title: language.text("Remove", "Ta bort"),
                            cancelTitle: language.text("Cancel", "Avbryt"),
                            confirmationTitle: language.text("Remove this option?", "Ta bort alternativet?")
                        ) {
                            guard options.indices.contains(index) else { return }
                            options.remove(at: index)
                            persist()
                        }
                    } else {
                        Color.clear.frame(width: 18, height: 18)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 420)
        .onAppear(perform: load)
    }

    private func load() {
        options = store.calendarMeetingTypeOptions
        ensureTrailingEmptyRow()
    }

    private func ensureTrailingEmptyRow() {
        if options.last?.trimmedOrNil != nil {
            options.append("")
        } else if options.isEmpty {
            options = [""]
        }
    }

    private func persist() {
        store.autosaveCalendarMeetingTypeOptions(options)
        options = store.calendarMeetingTypeOptions
        ensureTrailingEmptyRow()
    }
}

private struct CalendarAccommodationSheet: View {
    @ObservedObject var store: GrantDataStore
    let accommodationID: String?
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CalendarAccommodationRecord
    @State private var didLoadExistingValues = false
    @State private var countryText = ""

    init(store: GrantDataStore, accommodationID: String?, initialDateString: String? = nil) {
        self.store = store
        self.accommodationID = accommodationID
        let initialDate = calendarSheetInitialDateString(initialDateString)
        _draft = State(initialValue: CalendarAccommodationRecord(checkInDate: initialDate, checkOutDate: initialDate))
    }

    private var language: AppLanguage { store.language }

    private var existingRecord: CalendarAccommodationRecord? {
        guard let accommodationID else { return nil }
        return store.calendarAccommodationRecords.first(where: { $0.id == accommodationID })
    }

    private var localizedCountryOptions: [String] {
        GrantParsing.countryOptions
            .map { language.localizedCountry($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var congressOptions: [CalendarCongressSelectionOption] {
        store.organizationsForCongressRead.flatMap { organization in
            organization.congresses.compactMap { congress -> CalendarCongressSelectionOption? in
                guard !congress.isEmpty else { return nil }
                let title = congress.title.nonEmpty ?? organization.displayName(for: language)
                guard title.trimmedOrNil != nil else { return nil }
                return CalendarCongressSelectionOption(
                    organizationID: organization.id,
                    congressID: congress.id,
                    title: title,
                    organizationName: organization.displayName(for: language),
                    dateText: calendarCongressOptionDateText(congress)
                )
            }
        }
        .sorted { left, right in
            let leftDate = calendarCongressOptionSortDate(left)
            let rightDate = calendarCongressOptionSortDate(right)
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            return left.menuTitle.localizedStandardCompare(right.menuTitle) == .orderedAscending
        }
    }

    private var congressSelectionBinding: Binding<String> {
        Binding(
            get: {
                guard draft.congressOrganizationID.trimmedOrNil != nil,
                      draft.congressID.trimmedOrNil != nil else {
                    return ""
                }
                return calendarCongressSelectionKey(
                    organizationID: draft.congressOrganizationID,
                    congressID: draft.congressID
                )
            },
            set: { newValue in
                guard let selected = calendarCongressSelectionIDs(from: newValue) else {
                    draft.congressOrganizationID = ""
                    draft.congressID = ""
                    return
                }
                draft.congressOrganizationID = selected.organizationID
                draft.congressID = selected.congressID
                applyCongressPlaceIfNeeded(organizationID: selected.organizationID, congressID: selected.congressID)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(accommodationID == nil ? language.text("Add accommodation", "Lägg till boende") : language.text("Edit accommodation", "Redigera boende"))
                    .calendarTypography(.sectionTitle)

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Hotel", "Hotell"))
                        .calendarTypography(.fieldLabel)
                    TextField(language.text("Hotel name", "Hotellnamn"), text: $draft.hotelName)
                        .appTextInputChrome()
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(language.text("Check-in", "Incheckning"))
                            .calendarTypography(.fieldLabel)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Date", "Datum"))
                                .calendarTypography(.fieldLabel)
                            CalendarDateInputField(placeholder: language.datePlaceholder, text: checkInDateBinding)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Time", "Klockslag"))
                                .calendarTypography(.fieldLabel)
                            CalendarTimeInputField(placeholder: "HH:MM", text: $draft.checkInTime)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(language.text("Check-out", "Utcheckning"))
                            .calendarTypography(.fieldLabel)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Date", "Datum"))
                                .calendarTypography(.fieldLabel)
                            CalendarDateInputField(placeholder: language.datePlaceholder, text: $draft.checkOutDate)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Time", "Klockslag"))
                                .calendarTypography(.fieldLabel)
                            CalendarTimeInputField(placeholder: "HH:MM", text: $draft.checkOutTime)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text("City", "Ort"))
                            .calendarTypography(.fieldLabel)
                        TextField(language.text("City", "Ort"), text: $draft.city)
                            .appTextInputChrome()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text("Country", "Land"))
                            .calendarTypography(.fieldLabel)
                        countryAutocompleteField(text: $countryText, selection: $draft.country)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Congress", "Kongress"))
                        .calendarTypography(.fieldLabel)
                    AppMenuSelectionField(
                        selection: congressSelectionBinding,
                        options: [(language.text("No congress", "Ingen kongress"), "")]
                            + congressOptions.map { ($0.menuTitle, $0.id) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Accommodation reference", "Boendereferens"))
                        .calendarTypography(.fieldLabel)
                    TextField(language.text("Reference", "Referens"), text: $draft.reference)
                        .appTextInputChrome()
                }

                FootprintDialogActions(
                    cancelTitle: language.text("Cancel", "Avbryt"),
                    primaryTitle: language.text("Save", "Spara"),
                    isPrimaryDisabled: draft.checkInDate.trimmedOrNil == nil,
                    cancelAction: { dismiss() },
                    primaryAction: { save() }
                )
            }
            .padding(22)
        }
        .appResponsiveDialogFrame(idealWidth: 600, idealHeight: 600)
        .autocompleteOverlayHost()
        .onAppear {
            loadExistingAccommodationIfNeeded()
        }
    }

    private var checkInDateBinding: Binding<String> {
        Binding(
            get: { draft.checkInDate },
            set: { newValue in
                let previousDate = draft.checkInDate
                draft.checkInDate = newValue
                if let shiftedCheckOutDate = shiftedDateRangeEnd(
                    previousStart: previousDate,
                    newStart: newValue,
                    currentEnd: draft.checkOutDate
                ) {
                    draft.checkOutDate = shiftedCheckOutDate
                }
            }
        )
    }

    private func save() {
        draft.country = canonicalCalendarCountryName(countryText)
        var normalized = draft
        normalized.normalize()
        var records = store.calendarAccommodationRecords
        var previousRecord: CalendarAccommodationRecord?
        if let accommodationID,
           let existingIndex = records.firstIndex(where: { $0.id == accommodationID }) {
            previousRecord = records[existingIndex]
            records[existingIndex] = normalized
        } else {
            records.append(normalized)
        }
        store.autosaveCalendarAccommodationRecords(records)
        // Only when the stay is newly linked to this congress, so saving it
        // again does not put back a user who removed themselves.
        let linkIsNew = previousRecord?.congressOrganizationID.trimmedOrNil != normalized.congressOrganizationID.trimmedOrNil
            || previousRecord?.congressID.trimmedOrNil != normalized.congressID.trimmedOrNil
        if linkIsNew,
           let organizationID = normalized.congressOrganizationID.trimmedOrNil,
           let congressID = normalized.congressID.trimmedOrNil {
            store.markCongressAsAttendingIfNeeded(
                organizationID: organizationID,
                congressID: congressID
            )
        }
        dismiss()
    }

    private func loadExistingAccommodationIfNeeded() {
        guard !didLoadExistingValues else { return }
        defer { didLoadExistingValues = true }
        if let existingRecord {
            var normalized = existingRecord
            normalized.normalize()
            draft = normalized
        }
        countryText = localizedCalendarCountryName(draft.country)
    }

    private func applyCongressPlaceIfNeeded(organizationID: String, congressID: String) {
        guard let organization = store.organization(id: organizationID),
              let congress = organization.congresses.first(where: { $0.id == congressID }) else { return }
        if draft.city.trimmedOrNil == nil {
            draft.city = congress.city
        }
        if draft.country.trimmedOrNil == nil {
            draft.country = congress.country
            countryText = localizedCalendarCountryName(congress.country)
        }
    }

    private func calendarCongressOptionDateText(_ congress: OrganizationCongress) -> String {
        [congress.from.nonEmpty, congress.to.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private func calendarCongressOptionSortDate(_ option: CalendarCongressSelectionOption) -> Date {
        store.organization(id: option.organizationID)?
            .congresses
            .first(where: { $0.id == option.congressID })?
            .from
            .nonEmpty
            .flatMap(DateParsers.isoDay.date(from:))
            ?? .distantFuture
    }

    private func canonicalCalendarCountryName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let exact = GrantParsing.countryOptions.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact
        }
        if let localized = GrantParsing.countryOptions.first(where: {
            language.localizedCountry($0).caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return localized
        }
        let heuristic = GrantParsing.canonicalCountryName(trimmed)
        if let canonical = GrantParsing.countryOptions.first(where: { $0.caseInsensitiveCompare(heuristic) == .orderedSame }) {
            return canonical
        }
        return trimmed
    }

    private func localizedCalendarCountryName(_ raw: String) -> String {
        let canonical = canonicalCalendarCountryName(raw)
        guard !canonical.isEmpty else { return "" }
        return GrantParsing.countryOptions.contains(canonical) ? language.localizedCountry(canonical) : canonical
    }

    @ViewBuilder
    private func countryAutocompleteField(text: Binding<String>, selection: Binding<String>) -> some View {
        AutocompleteSelectionField(
            text: text,
            options: localizedCountryOptions,
            placeholder: language.text("Country", "Land"),
            onCommit: {
                let canonical = canonicalCalendarCountryName(text.wrappedValue)
                selection.wrappedValue = canonical
                text.wrappedValue = localizedCalendarCountryName(canonical)
            },
            onSelect: { selected in
                let canonical = canonicalCalendarCountryName(selected)
                selection.wrappedValue = canonical
                text.wrappedValue = localizedCalendarCountryName(canonical)
            },
            showsSuggestionsWithoutQuery: true
        )
        .frame(width: 220, alignment: .leading)
    }
}

private struct CalendarMeetingSheet: View {
    @ObservedObject var store: GrantDataStore
    let meetingID: String?
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CalendarMeetingRecord
    // Round 7: the links are edited as id lists by the shared link rows
    // (the same rows as in the task editor).
    @State private var projectIDs: [String] = []
    @State private var organizationIDs: [String] = []
    @State private var applicationIDs: [String] = []
    @State private var publicationIDs: [String] = []
    @State private var mediaAppearanceIDs: [String] = []
    @State private var teachingOptionIDs: [String] = []
    @State private var doctoralCandidateIDs: [String] = []
    @State private var countryText: String = ""
    @State private var participantRows: [CalendarMeetingParticipantDraft] = [.init()]
    @State private var showingMeetingTypeCatalog = false
    @State private var didLoadExistingValues = false
    @State private var committedStartTimeForShift: String?

    init(store: GrantDataStore, meetingID: String?, initialDateString: String? = nil) {
        self.store = store
        self.meetingID = meetingID
        _draft = State(initialValue: CalendarMeetingRecord(date: calendarSheetInitialDateString(initialDateString)))
    }

    private var language: AppLanguage { store.language }

    private var existingRecord: CalendarMeetingRecord? {
        guard let meetingID else { return nil }
        return store.calendarMeetingRecords.first(where: { $0.id == meetingID })
    }

    private var researcherOptions: [String] {
        calendarLinkParticipantOptions(store: store)
    }

    private var linkOptions: CalendarLinkOptionSets {
        CalendarLinkOptionSets(store: store, language: language)
    }

    private var meetingModeOptions: [(label: String, value: String)] {
        CalendarMeetingMode.allCases.map { mode in
            (mode.localizedName(language: language), mode.rawValue)
        }
    }

    private var localizedCountryOptions: [String] {
        GrantParsing.countryOptions
            .map { language.localizedCountry($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var selectedProjects: [ProjectRecord] {
        guard !projectIDs.isEmpty else { return [] }
        return store.projects.filter { projectIDs.contains($0.id) }
    }

    private var normalizedParticipants: [String] {
        let trimmed = participantRows.compactMap { $0.name.trimmedOrNil }
        return Array(NSOrderedSet(array: trimmed)) as? [String] ?? trimmed
    }

    private var hidesPlaceFields: Bool {
        draft.meetingMode.caseInsensitiveCompare(CalendarMeetingMode.online.rawValue) == .orderedSame
    }

    var body: some View {
        CalendarEditorDialogSurface { dialogWidth in
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    existingRecord == nil
                        ? language.text("Add activity", "Lägg till aktivitet")
                        : language.text("Edit activity", "Redigera aktivitet")
                )
                .calendarTypography(.sectionTitle)

                HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text("Date", "Datum"))
                            .calendarTypography(.fieldLabel)
                        CalendarDateInputField(placeholder: language.datePlaceholder, text: $draft.date)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text("Start time", "Starttid"))
                            .calendarTypography(.fieldLabel)
                        CalendarTimeInputField(placeholder: "HH:MM", text: meetingStartTimeBinding)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text("End time", "Sluttid"))
                            .calendarTypography(.fieldLabel)
                        CalendarTimeInputField(placeholder: "HH:MM", text: $draft.endTime)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Activity", "Aktivitet"))
                        .calendarTypography(.fieldLabel)
                    TextField(language.text("Activity", "Aktivitet"), text: $draft.title)
                        .appTextInputChrome()
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(language.text("Category", "Kategori"))
                                .calendarTypography(.fieldLabel)
                            Button {
                                showingMeetingTypeCatalog = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppPalette.linkAction)
                            }
                            .buttonStyle(.plain)
                        }

                        AutocompleteSelectionField(
                            text: $draft.meetingType,
                            options: store.calendarMeetingTypeOptions,
                            placeholder: CalendarFixedCategory.uncategorized.localizedName(language: language),
                            onCommit: {},
                            onSelect: { selected in
                                draft.meetingType = selected
                            },
                            showsSuggestionsWithoutQuery: true
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .popover(isPresented: $showingMeetingTypeCatalog, arrowEdge: .bottom) {
                        CalendarMeetingTypeCatalogPopover(store: store, language: language)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text("Format", "Genomförande"))
                            .calendarTypography(.fieldLabel)
                        AppMenuSelectionField(
                            selection: $draft.meetingMode,
                            options: meetingModeOptions,
                            placeholder: language.text("Choose format", "Välj genomförande"),
                            clearValue: ""
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !hidesPlaceFields {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Place", "Plats"))
                                .calendarTypography(.fieldLabel)
                            TextField(language.text("Place", "Plats"), text: $draft.place)
                                .appTextInputChrome()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Country", "Land"))
                                .calendarTypography(.fieldLabel)
                            countryAutocompleteField(text: $countryText, selection: $draft.country)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                CalendarLinkRowsSection(
                    language: language,
                    options: linkOptions,
                    projectIDs: $projectIDs,
                    organizationIDs: $organizationIDs,
                    applicationIDs: $applicationIDs,
                    publicationIDs: $publicationIDs,
                    teachingOptionIDs: $teachingOptionIDs,
                    doctoralCandidateIDs: $doctoralCandidateIDs
                )

                CalendarLinkRowsField(
                    title: language.text("Media", "Media"),
                    placeholder: language.text("Media appearance", "Medverkan i media"),
                    options: linkOptions.mediaAppearances,
                    ids: $mediaAppearanceIDs,
                    language: language
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Comment", "Kommentar"))
                        .calendarTypography(.fieldLabel)
                    TextField(language.text("Comment", "Kommentar"), text: $draft.detail, axis: .vertical)
                        .appTextInputChrome()
                        .lineLimit(2...6)
                }

                HStack(alignment: .top, spacing: 16) {
                    CalendarParticipantRowsField(
                        rows: $participantRows,
                        options: researcherOptions,
                        language: language
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !selectedProjects.isEmpty {
                        Button(language.text("Copy from project", "Kopiera från projekt")) {
                            copyParticipantsFromProject()
                        }
                        .appSaveButtonStyle()
                        .disabled(!selectedProjects.contains { !$0.collaboratorNames.isEmpty })
                        .padding(.top, 26)
                    }
                }

                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                CalendarAgendaProtocolColumn(
                    language: language,
                    fieldMinHeight: 400,
                    agendaText: $draft.agendaText,
                    protocolText: $draft.protocolText
                )
                .frame(width: calendarEditorSideColumnWidth(for: dialogWidth))
                }

                FootprintDialogActions(
                    cancelTitle: language.text("Cancel", "Avbryt"),
                    primaryTitle: language.text("Save", "Spara"),
                    isPrimaryDisabled: draft.date.trimmedOrNil == nil,
                    cancelAction: { dismiss() },
                    primaryAction: { save() }
                )
            }
        }
        .autocompleteOverlayHost()
        .onAppear(perform: loadExistingValuesIfNeeded)
        .onChange(of: draft.meetingMode) { _, newValue in
            if newValue.caseInsensitiveCompare(CalendarMeetingMode.online.rawValue) == .orderedSame {
                draft.place = ""
                draft.country = ""
                countryText = ""
            }
        }
    }

    private var meetingStartTimeBinding: Binding<String> {
        Binding(
            get: { draft.startTime },
            set: { newValue in
                let update = updatingCommittedTimeRangeEnd(
                    previousCommittedStart: committedStartTimeForShift,
                    newInput: newValue,
                    currentEnd: draft.endTime
                )
                draft.startTime = newValue
                if let shiftedEndTime = update.shiftedEnd {
                    draft.endTime = shiftedEndTime
                }
                committedStartTimeForShift = update.committedStart
            }
        )
    }

    private func selectionField(
        title: String,
        text: Binding<String>,
        options: [String],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        AutocompleteSelectionField(
            text: text,
            options: options,
            placeholder: title,
            onCommit: {
                onSelect(text.wrappedValue)
            },
            onSelect: { selected in
                text.wrappedValue = selected
                onSelect(selected)
            },
            showsSuggestionsWithoutQuery: true
        )
    }

    private func resolvedID(for label: String, in options: [(id: String, label: String)]) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return options.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame })?.id
    }

    private func resolvedLabel(for id: String?, in options: [(id: String, label: String)]) -> String {
        guard let id else { return "" }
        return options.first(where: { $0.id == id })?.label ?? ""
    }

    private func calendarMeetingApplicationLabel(_ application: GrantApplication) -> String {
        let title = store.localizedGrantName(for: application, language: language).nonEmpty
            ?? application.grantName.nonEmpty
            ?? language.text("Untitled grant", "Namnlöst anslag")
        let organization = application.organization.nonEmpty.map {
            store.organizationLabel(for: $0, language: language)
        }
        let year = application.appliedYear?.trimmedOrNil
            ?? leadingCalendarYear(application.appliedOn)
            ?? leadingCalendarYear(application.closesOn)
            ?? leadingCalendarYear(application.grantedOn)
        let detail = [organization, year].compactMap { $0?.trimmedOrNil }.joined(separator: " · ")
        return detail.isEmpty ? title : "\(title) (\(detail))"
    }

    private func calendarMeetingPublicationLabel(_ publication: PublicationRecord) -> String {
        let title = publication.title.nonEmpty ?? language.text("Untitled publication", "Namnlös publikation")
        let detail = [publication.journal.nonEmpty, publication.year.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
        return detail.isEmpty ? title : "\(title) (\(detail))"
    }

    private func leadingCalendarYear(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmedOrNil, trimmed.count >= 4 else { return nil }
        let year = String(trimmed.prefix(4))
        return year.count == 4 && year.allSatisfy(\.isNumber) ? year : nil
    }

    private func canonicalCalendarCountryName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let exact = GrantParsing.countryOptions.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact
        }
        if let localized = GrantParsing.countryOptions.first(where: {
            language.localizedCountry($0).caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return localized
        }
        let heuristic = GrantParsing.canonicalCountryName(trimmed)
        if let canonical = GrantParsing.countryOptions.first(where: { $0.caseInsensitiveCompare(heuristic) == .orderedSame }) {
            return canonical
        }
        return trimmed
    }

    private func localizedCalendarCountryName(_ raw: String) -> String {
        let canonical = canonicalCalendarCountryName(raw)
        guard !canonical.isEmpty else { return "" }
        return GrantParsing.countryOptions.contains(canonical) ? language.localizedCountry(canonical) : canonical
    }

    @ViewBuilder
    private func countryAutocompleteField(text: Binding<String>, selection: Binding<String>) -> some View {
        AutocompleteSelectionField(
            text: text,
            options: localizedCountryOptions,
            placeholder: language.text("Country", "Land"),
            onCommit: {
                let canonical = canonicalCalendarCountryName(text.wrappedValue)
                selection.wrappedValue = canonical
                text.wrappedValue = localizedCalendarCountryName(canonical)
            },
            onSelect: { selected in
                let canonical = canonicalCalendarCountryName(selected)
                selection.wrappedValue = canonical
                text.wrappedValue = localizedCalendarCountryName(canonical)
            },
            showsSuggestionsWithoutQuery: true
        )
    }

    private func loadExistingValuesIfNeeded() {
        guard !didLoadExistingValues else { return }
        defer { didLoadExistingValues = true }
        guard let existingRecord else {
            teachingOptionIDs = calendarTeachingOptionIDs(
                courseIDs: draft.teachingCourseIDs,
                assignmentIDs: calendarMeetingTeachingAssignmentIDs(draft)
            )
            doctoralCandidateIDs = calendarMeetingDoctoralCandidateIDs(draft)
            participantRows = [CalendarMeetingParticipantDraft()]
            countryText = localizedCalendarCountryName(draft.country)
            committedStartTimeForShift = committedCalendarTimeForRangeShift(draft.startTime)
            return
        }

        draft = existingRecord
        committedStartTimeForShift = committedCalendarTimeForRangeShift(existingRecord.startTime)
        projectIDs = existingRecord.projectIDs.isEmpty
            ? (existingRecord.projectID.map { [$0] } ?? [])
            : existingRecord.projectIDs
        organizationIDs = existingRecord.organizationIDs.isEmpty
            ? (existingRecord.organizationID.map { [$0] } ?? [])
            : existingRecord.organizationIDs
        applicationIDs = existingRecord.applicationIDs
        publicationIDs = existingRecord.publicationIDs
        mediaAppearanceIDs = existingRecord.mediaAppearanceIDs
        teachingOptionIDs = calendarTeachingOptionIDs(
            courseIDs: existingRecord.teachingCourseIDs,
            assignmentIDs: calendarMeetingTeachingAssignmentIDs(existingRecord)
        )
        doctoralCandidateIDs = calendarMeetingDoctoralCandidateIDs(existingRecord)
        countryText = localizedCalendarCountryName(existingRecord.country)
        participantRows = existingRecord.participantNames.map { CalendarMeetingParticipantDraft(name: $0) }
            + [CalendarMeetingParticipantDraft()]
    }

    private func save() {
        var record = draft
        if record.meetingMode.caseInsensitiveCompare(CalendarMeetingMode.online.rawValue) == .orderedSame {
            record.place = ""
            record.country = ""
            countryText = ""
        }
        let options = linkOptions
        let previous = existingRecord
        let previousProjectIDs: [String] = previous.map {
            $0.projectIDs.isEmpty ? ($0.projectID.map { [$0] } ?? []) : $0.projectIDs
        } ?? []
        let previousOrganizationIDs: [String] = previous.map {
            $0.organizationIDs.isEmpty ? ($0.organizationID.map { [$0] } ?? []) : $0.organizationIDs
        } ?? []
        let teaching = calendarTeachingSelection(fromOptionIDs: teachingOptionIDs)
        let listedTeaching = calendarTeachingSelection(fromOptionIDs: options.teaching.map(\.id))

        record.country = canonicalCalendarCountryName(countryText)
        record.participantNames = normalizedParticipants
        record.participantAuthorIDs = store.synchronizedPersonAuthorIDs(
            existingIDs: record.participantAuthorIDs,
            names: normalizedParticipants
        )
        // Every link the rows show is replaced by the rows; a stored link to a
        // record that is not in the list (a removed record) is kept.
        let savedProjectIDs = calendarLinkIDsKeepingUnlisted(
            selected: projectIDs,
            existing: previousProjectIDs,
            listedIDs: Set(options.projects.map(\.id))
        )
        record.projectIDs = savedProjectIDs
        record.projectID = savedProjectIDs.first
        let savedOrganizationIDs = calendarLinkIDsKeepingUnlisted(
            selected: organizationIDs,
            existing: previousOrganizationIDs,
            listedIDs: Set(options.organizations.map(\.id))
        )
        record.organizationIDs = savedOrganizationIDs
        record.organizationID = savedOrganizationIDs.first
        record.applicationIDs = calendarLinkIDsKeepingUnlisted(
            selected: applicationIDs,
            existing: previous?.applicationIDs ?? [],
            listedIDs: Set(options.applications.map(\.id))
        )
        record.publicationIDs = calendarLinkIDsKeepingUnlisted(
            selected: publicationIDs,
            existing: previous?.publicationIDs ?? [],
            listedIDs: Set(options.publications.map(\.id))
        )
        record.mediaAppearanceIDs = calendarLinkIDsKeepingUnlisted(
            selected: mediaAppearanceIDs,
            existing: previous?.mediaAppearanceIDs ?? [],
            listedIDs: Set(options.mediaAppearances.map(\.id))
        )
        let savedAssignmentIDs = calendarLinkIDsKeepingUnlisted(
            selected: teaching.assignmentIDs,
            existing: previous.map { calendarMeetingTeachingAssignmentIDs($0) } ?? [],
            listedIDs: Set(listedTeaching.assignmentIDs)
        )
        record.teachingAssignmentIDs = savedAssignmentIDs
        record.teachingAssignmentID = savedAssignmentIDs.first
        record.teachingCourseIDs = calendarLinkIDsKeepingUnlisted(
            selected: teaching.courseIDs,
            existing: previous?.teachingCourseIDs ?? [],
            listedIDs: Set(listedTeaching.courseIDs)
        )
        let savedCandidateIDs = calendarLinkIDsKeepingUnlisted(
            selected: doctoralCandidateIDs,
            existing: previous.map { calendarMeetingDoctoralCandidateIDs($0) } ?? [],
            listedIDs: Set(options.doctoralCandidates.map(\.id))
        )
        record.doctoralCandidateIDs = savedCandidateIDs
        record.doctoralCandidateID = savedCandidateIDs.first
        record.researcherID = nil
        record.normalize()

        var updatedRecords = store.calendarMeetingRecords
        if let meetingID,
           let index = updatedRecords.firstIndex(where: { $0.id == meetingID }) {
            updatedRecords[index] = record
        } else {
            updatedRecords.append(record)
        }

        store.autosaveCalendarMeetingRecords(updatedRecords)
        dismiss()
    }

    private func copyParticipantsFromProject() {
        guard !selectedProjects.isEmpty else { return }
        let projectParticipants = selectedProjects.reduce(into: [String]()) { result, project in
            result.append(contentsOf: project.collaboratorNames.compactMap(\.trimmedOrNil))
        }
        let merged = Array(
            NSOrderedSet(array: normalizedParticipants + projectParticipants)
        ) as? [String] ?? (normalizedParticipants + projectParticipants)
        participantRows = merged.map { CalendarMeetingParticipantDraft(name: $0) } + [CalendarMeetingParticipantDraft()]
    }
}

@MainActor
private func twoColumnRow(
    leftTitle: String,
    leftField: AnyView,
    rightTitle: String,
    rightField: AnyView
) -> some View {
    HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
            Text(leftTitle)
                .calendarTypography(.fieldLabel)
            leftField
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 6) {
            Text(rightTitle)
                .calendarTypography(.fieldLabel)
            rightField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
