import AppKit
import SwiftUI

// MARK: - View mode

/// How the calendar shows its days: the long list or one week as a grid.
/// The choice is remembered on this Mac between launches.
enum CalendarWorkspaceViewMode: String, CaseIterable, Identifiable {
    case list
    case week

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .list:
            return language.text("List", "Lista")
        case .week:
            return language.text("Week", "Vecka")
        }
    }
}

// MARK: - Pure helpers (tested in CalendarWeekViewTests)

let calendarWeekViewMinutesPerDay = 24 * 60
/// A task with a deadline time is drawn as a short block of this length.
let calendarWeekViewTaskBlockMinutes = 30
/// A timed event with a start but no end time is drawn this long.
let calendarWeekViewDefaultEventMinutes = 60

/// The first day of the week that contains `date`, following the calendar's
/// own week start (the app's week-start setting).
func calendarWeekViewWeekStart(for date: Date, calendar: Calendar) -> Date {
    let day = calendar.startOfDay(for: date)
    guard let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return day }
    return calendar.startOfDay(for: start)
}

/// The last day (start of day) of the week that contains `date`.
func calendarWeekViewWeekEnd(for date: Date, calendar: Calendar) -> Date {
    let start = calendarWeekViewWeekStart(for: date, calendar: calendar)
    return calendar.date(byAdding: .day, value: 6, to: start) ?? start
}

/// The seven days of the week starting at `weekStart`.
func calendarWeekViewDays(weekStart: Date, calendar: Calendar) -> [Date] {
    let start = calendar.startOfDay(for: weekStart)
    return (0..<7).compactMap { offset in
        calendar.date(byAdding: .day, value: offset, to: start).map { calendar.startOfDay(for: $0) }
    }
}

/// The week title above the grid, e.g. "Vecka 41 · 5–11 okt 2026",
/// "Vecka 40 · 28 sep–4 okt 2026" or "Vecka 53 · 28 dec 2026–3 jan 2027".
/// The week number follows the same ISO rule as the list's week rows; it is
/// taken from the middle of the week so a Sunday week start still gets the
/// number of the week most of its days belong to.
func calendarWeekViewTitle(weekStart: Date, calendar: Calendar, language: AppLanguage) -> String {
    let start = calendar.startOfDay(for: weekStart)
    let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
    var weekNumberCalendar = Calendar(identifier: .iso8601)
    weekNumberCalendar.timeZone = calendar.timeZone
    weekNumberCalendar.locale = calendar.locale
    let middle = calendar.date(byAdding: .day, value: 3, to: start) ?? start
    let weekNumber = weekNumberCalendar.component(.weekOfYear, from: middle)

    let startParts = calendar.dateComponents([.day, .month, .year], from: start)
    let endParts = calendar.dateComponents([.day, .month, .year], from: end)
    let startDay = startParts.day ?? 1
    let endDay = endParts.day ?? 1
    let startMonth = calendarListMonthAbbreviation(startParts.month ?? 1, language: language)
    let endMonth = calendarListMonthAbbreviation(endParts.month ?? 1, language: language)
    let startYear = startParts.year ?? 0
    let endYear = endParts.year ?? 0

    let range: String
    if startYear != endYear {
        range = "\(startDay) \(startMonth) \(startYear)–\(endDay) \(endMonth) \(endYear)"
    } else if startParts.month != endParts.month {
        range = "\(startDay) \(startMonth)–\(endDay) \(endMonth) \(endYear)"
    } else {
        range = "\(startDay)–\(endDay) \(endMonth) \(endYear)"
    }
    return "\(language.text("Week", "Vecka")) \(weekNumber) · \(range)"
}

/// "13:05" → 785. A trailing "?" (uncertain time) is ignored; "24:00" is
/// the end of the day. Anything else returns nil.
func calendarWeekViewMinute(fromClockText text: String) -> Int? {
    let cleaned = text
        .replacingOccurrences(of: "?", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
          parts[0].count <= 2,
          parts[1].count == 2,
          let hour = Int(parts[0]),
          let minute = Int(parts[1]) else {
        return nil
    }
    if hour == 24, minute == 0 {
        return calendarWeekViewMinutesPerDay
    }
    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    return hour * 60 + minute
}

/// The start and (optional) end minute in an event's time text:
/// "09:00–10:30", "09:00?–10:30", "14:00" or "".
func calendarWeekViewClockRange(from timeText: String) -> (start: Int, end: Int?)? {
    let trimmed = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let parts = trimmed
        .components(separatedBy: CharacterSet(charactersIn: "–—-"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard let first = parts.first,
          let start = calendarWeekViewMinute(fromClockText: first),
          start < calendarWeekViewMinutesPerDay else {
        return nil
    }
    let end = parts.count > 1 ? calendarWeekViewMinute(fromClockText: parts[1]) : nil
    return (start, end)
}

/// A stretch of one day in minutes after midnight, end exclusive.
struct CalendarWeekTimeSpan: Equatable, Hashable {
    let startMinute: Int
    let endMinute: Int
}

/// Where an event goes in the week grid.
enum CalendarWeekViewPlacement: Equatable {
    /// In the strip above the hours.
    case allDay
    /// As a block in the hour grid.
    case timed(CalendarWeekTimeSpan)

    var span: CalendarWeekTimeSpan? {
        if case let .timed(span) = self {
            return span
        }
        return nil
    }
}

/// All-day or timed. Congresses, deadlines and accommodation always go in
/// the all-day strip. Tasks with a deadline time become a short block at
/// that time. Activities and travel with a start time become blocks; an end
/// time before the start (a trip that lands after midnight) is cut at
/// midnight, so each day only shows its own part. Everything without a
/// readable time goes in the all-day strip.
func calendarWeekViewPlacement(kind: CalendarWorkspaceEventKind, timeText: String) -> CalendarWeekViewPlacement {
    switch kind {
    case .holiday, .congress, .accommodation, .applicationDeadline:
        return .allDay
    case .taskDeadline:
        guard let range = calendarWeekViewClockRange(from: timeText) else { return .allDay }
        let end = min(range.start + calendarWeekViewTaskBlockMinutes, calendarWeekViewMinutesPerDay)
        return .timed(CalendarWeekTimeSpan(startMinute: range.start, endMinute: end))
    case .meeting, .travel:
        guard let range = calendarWeekViewClockRange(from: timeText) else { return .allDay }
        let end: Int
        if let rawEnd = range.end {
            end = rawEnd > range.start ? rawEnd : calendarWeekViewMinutesPerDay
        } else {
            end = min(range.start + calendarWeekViewDefaultEventMinutes, calendarWeekViewMinutesPerDay)
        }
        return .timed(CalendarWeekTimeSpan(startMinute: range.start, endMinute: end))
    }
}

/// Which side-by-side column an overlapping block takes, and how many
/// columns its group of overlapping blocks shares.
struct CalendarWeekColumnSlot: Equatable {
    let column: Int
    let columnCount: Int
}

/// Simple column packing for overlapping blocks. Blocks are taken in start
/// order (longer first on equal starts); each goes into the first column
/// that is free at its start. Blocks that overlap directly or through a
/// chain form one group and share that group's column count. Very short
/// blocks count as `minimumDuration` long, since they are drawn at least
/// that tall. The result is in the same order as `spans`.
func calendarWeekViewPackColumns(_ spans: [CalendarWeekTimeSpan], minimumDuration: Int = 0) -> [CalendarWeekColumnSlot] {
    guard !spans.isEmpty else { return [] }
    let order = spans.indices.sorted { lhs, rhs in
        let left = spans[lhs]
        let right = spans[rhs]
        if left.startMinute != right.startMinute {
            return left.startMinute < right.startMinute
        }
        if left.endMinute != right.endMinute {
            return left.endMinute > right.endMinute
        }
        return lhs < rhs
    }

    var columns = Array(repeating: 0, count: spans.count)
    var columnCounts = Array(repeating: 1, count: spans.count)
    var groupMembers: [Int] = []
    var columnEnds: [Int] = []
    var groupEnd = Int.min

    for index in order {
        let span = spans[index]
        let start = span.startMinute
        let end = max(span.endMinute, start + max(minimumDuration, 1))
        if !groupMembers.isEmpty, start >= groupEnd {
            for member in groupMembers {
                columnCounts[member] = max(columnEnds.count, 1)
            }
            groupMembers.removeAll()
            columnEnds.removeAll()
            groupEnd = Int.min
        }
        if let freeColumn = columnEnds.firstIndex(where: { $0 <= start }) {
            columns[index] = freeColumn
            columnEnds[freeColumn] = end
        } else {
            columns[index] = columnEnds.count
            columnEnds.append(end)
        }
        groupMembers.append(index)
        groupEnd = max(groupEnd, end)
    }
    for member in groupMembers {
        columnCounts[member] = max(columnEnds.count, 1)
    }

    return spans.indices.map { CalendarWeekColumnSlot(column: columns[$0], columnCount: columnCounts[$0]) }
}

/// The y position of a minute in the hour grid.
func calendarWeekViewYOffset(minute: Int, hourHeight: CGFloat) -> CGFloat {
    CGFloat(min(max(minute, 0), calendarWeekViewMinutesPerDay)) / 60 * hourHeight
}

struct CalendarWeekBlockFrame: Equatable {
    let y: CGFloat
    let height: CGFloat
}

/// Top and height of a block. Short blocks get `minimumHeight` so their
/// title fits; a block near midnight is moved up so it stays inside the day.
func calendarWeekViewBlockFrame(
    span: CalendarWeekTimeSpan,
    hourHeight: CGFloat,
    minimumHeight: CGFloat
) -> CalendarWeekBlockFrame {
    let dayHeight = CGFloat(24) * hourHeight
    let top = calendarWeekViewYOffset(minute: span.startMinute, hourHeight: hourHeight)
    let bottom = calendarWeekViewYOffset(minute: span.endMinute, hourHeight: hourHeight)
    let height = min(max(bottom - top, minimumHeight), dayHeight)
    let y = max(min(top, dayHeight - height), 0)
    return CalendarWeekBlockFrame(y: y, height: height)
}

/// One hour's height: about 07–19 fits the visible area, within sensible limits.
func calendarWeekViewHourHeight(viewportHeight: CGFloat) -> CGFloat {
    guard viewportHeight > 1 else { return 48 }
    return min(max(viewportHeight / 12.5, 36), 96)
}

func calendarWeekViewMinuteOfDay(for date: Date, calendar: Calendar) -> Int {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
}

func calendarWeekViewHourAnchorID(_ hour: Int) -> String {
    "calendar-week-hour-\(hour)"
}

/// The app's text style for a role, never smaller than `minimumSize`
/// (13 pt for body text in the week view).
func calendarWeekViewFont(
    _ role: AppTypographyRole,
    minimumSize: Double = 13,
    weight: Font.Weight? = nil
) -> Font {
    let typography = AppAppearanceRegistry.typography()
    let style: AppTextStyleSetting
    switch role {
    case .pageTitle:
        style = typography.pageTitle
    case .sectionTitle:
        style = typography.sectionTitle
    case .panelTitle:
        style = typography.panelTitle
    case .tableHeader:
        style = typography.tableHeader
    case .fieldLabel:
        style = typography.fieldLabel
    case .body:
        style = typography.body
    case .secondary:
        style = typography.secondary
    case .statTitle:
        style = typography.statTitle
    case .statValue:
        style = typography.statValue
    }
    return .system(
        size: max(style.size, minimumSize),
        weight: weight ?? style.weight.swiftUIWeight,
        design: style.family.swiftUIDesign
    )
}

// MARK: - Week model (built once per week change)

/// How one event looks; resolved by the calendar with the same helpers the
/// list uses for its colour strip, icon, ring and dimming.
struct CalendarWeekViewEventStyle {
    let accentColor: Color
    let iconName: String
    let opacity: Double
    let needsAttentionRing: Bool
    let completionTint: Color
    let isItalic: Bool
}

struct CalendarWeekViewItem: Identifiable {
    let event: CalendarWorkspaceEvent
    let style: CalendarWeekViewEventStyle
    /// Time and place, e.g. "09:00–10:00 · Online".
    let secondaryText: String
    let showsCompletionRing: Bool
    /// nil for the all-day strip.
    let span: CalendarWeekTimeSpan?
    var slot = CalendarWeekColumnSlot(column: 0, columnCount: 1)

    var id: String { event.id }

    var helpText: String {
        [event.title.nonEmpty, secondaryText.nonEmpty]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}

struct CalendarWeekViewDay: Identifiable {
    let id: String
    let date: Date
    /// "Mån 5 okt"
    let headerText: String
    let holidayNames: [String]
    let isToday: Bool
    /// The red-day text colour for weekends and holidays; nil on other days.
    let highlightColor: Color?
    let allDayItems: [CalendarWeekViewItem]
    let timedItems: [CalendarWeekViewItem]
}

struct CalendarWeekViewModel {
    let weekStart: Date
    let title: String
    let calendar: Calendar
    let days: [CalendarWeekViewDay]

    var maxAllDayItemCount: Int {
        days.map(\.allDayItems.count).max() ?? 0
    }
}

/// Builds the seven days of the week from the calendar's already filtered
/// events (keyed by ISO day). Only the week's own days are read.
func makeCalendarWeekViewModel(
    weekStart: Date,
    today: Date,
    calendar: Calendar,
    language: AppLanguage,
    eventsByDay: [String: [CalendarWorkspaceEvent]],
    holidaysByDay: [String: [HolidayDefinition]],
    showsCompletionRing: Bool,
    dayHighlightColor: (Date, [HolidayDefinition]) -> Color?,
    eventStyle: (CalendarWorkspaceEvent) -> CalendarWeekViewEventStyle
) -> CalendarWeekViewModel {
    let start = calendarWeekViewWeekStart(for: weekStart, calendar: calendar)
    var days: [CalendarWeekViewDay] = []
    for date in calendarWeekViewDays(weekStart: start, calendar: calendar) {
        let key = DateParsers.isoDay.string(from: date)
        let holidays = holidaysByDay[key] ?? []
        var seenHolidayNames = Set<String>()
        let holidayNames = holidays
            .map { $0.localizedTitle(language: language) }
            .filter { seenHolidayNames.insert($0).inserted }

        var allDayItems: [CalendarWeekViewItem] = []
        var timedItems: [CalendarWeekViewItem] = []
        for event in eventsByDay[key] ?? [] where event.kind != .holiday {
            let placement = calendarWeekViewPlacement(kind: event.kind, timeText: event.timeText)
            let item = CalendarWeekViewItem(
                event: event,
                style: eventStyle(event),
                secondaryText: [event.timeText.nonEmpty, event.place.nonEmpty]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                showsCompletionRing: showsCompletionRing && event.isTask,
                span: placement.span
            )
            if placement.span == nil {
                allDayItems.append(item)
            } else {
                timedItems.append(item)
            }
        }

        timedItems = timedItems.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.span ?? CalendarWeekTimeSpan(startMinute: 0, endMinute: 0)
                let right = rhs.element.span ?? CalendarWeekTimeSpan(startMinute: 0, endMinute: 0)
                if left.startMinute != right.startMinute {
                    return left.startMinute < right.startMinute
                }
                if left.endMinute != right.endMinute {
                    return left.endMinute > right.endMinute
                }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
        let slots = calendarWeekViewPackColumns(
            timedItems.compactMap(\.span),
            minimumDuration: calendarWeekViewTaskBlockMinutes
        )
        if slots.count == timedItems.count {
            for index in timedItems.indices {
                timedItems[index].slot = slots[index]
            }
        }

        let parts = calendar.dateComponents([.weekday, .day, .month], from: date)
        days.append(
            CalendarWeekViewDay(
                id: key,
                date: date,
                headerText: calendarListShortDayLabel(
                    weekday: parts.weekday ?? 1,
                    day: parts.day ?? 1,
                    month: parts.month ?? 1,
                    language: language
                ),
                holidayNames: holidayNames,
                isToday: calendar.isDate(date, inSameDayAs: today),
                highlightColor: dayHighlightColor(date, holidays),
                allDayItems: allDayItems,
                timedItems: timedItems
            )
        )
    }
    return CalendarWeekViewModel(
        weekStart: start,
        title: calendarWeekViewTitle(weekStart: start, calendar: calendar, language: language),
        calendar: calendar,
        days: days
    )
}

// MARK: - View

/// The calendar's week grid: a time column, seven day columns, an all-day
/// strip above the hours and timed blocks placed by their times. Clicking
/// an item opens the same detail as the list; right-click gives the same
/// menu as the list.
struct CalendarWeekView<EventMenu: View, DayMenu: View>: View {
    let model: CalendarWeekViewModel
    let language: AppLanguage
    let usesDarkAppearance: Bool
    let onPreviousWeek: () -> Void
    let onNextWeek: () -> Void
    let onSelectEvent: (CalendarWorkspaceEvent) -> Void
    let eventContextMenu: (CalendarWorkspaceEvent, Date) -> EventMenu
    let dayContextMenu: (Date) -> DayMenu

    init(
        model: CalendarWeekViewModel,
        language: AppLanguage,
        usesDarkAppearance: Bool,
        onPreviousWeek: @escaping () -> Void,
        onNextWeek: @escaping () -> Void,
        onSelectEvent: @escaping (CalendarWorkspaceEvent) -> Void,
        eventContextMenu: @escaping (CalendarWorkspaceEvent, Date) -> EventMenu,
        dayContextMenu: @escaping (Date) -> DayMenu
    ) {
        self.model = model
        self.language = language
        self.usesDarkAppearance = usesDarkAppearance
        self.onPreviousWeek = onPreviousWeek
        self.onNextWeek = onNextWeek
        self.onSelectEvent = onSelectEvent
        self.eventContextMenu = eventContextMenu
        self.dayContextMenu = dayContextMenu
    }

    private let timeColumnWidth: CGFloat = 52
    private let headerBarHeight: CGFloat = 50
    private let pillHeight: CGFloat = 22
    private let pillSpacing: CGFloat = 3
    private let maximumVisibleAllDayRows = 4
    private let minimumBlockHeight: CGFloat = 22
    private let firstVisibleHour = 7

    var body: some View {
        VStack(spacing: 0) {
            weekHeaderBar
            dayHeaderRow
            allDayStrip
            Rectangle()
                .fill(gridLineColor)
                .frame(height: 1)
            GeometryReader { geometry in
                let hourHeight = calendarWeekViewHourHeight(viewportHeight: geometry.size.height)
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        timeGrid(hourHeight: hourHeight)
                    }
                    .scrollIndicators(.never)
                    .onAppear {
                        scrollToFirstVisibleHour(using: proxy)
                    }
                    .onChange(of: hourHeight) { _, _ in
                        scrollToFirstVisibleHour(using: proxy)
                    }
                }
            }
        }
        .background(AppPalette.calendarWorkspaceSurface)
    }

    // MARK: Header

    private var weekHeaderBar: some View {
        HStack(spacing: 8) {
            Button(action: onPreviousWeek) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help(language.text("Previous week", "Föregående vecka"))
            .accessibilityLabel(language.text("Previous week", "Föregående vecka"))

            Button(action: onNextWeek) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help(language.text("Next week", "Nästa vecka"))
            .accessibilityLabel(language.text("Next week", "Nästa vecka"))

            Text(model.title)
                .font(calendarWeekViewFont(.panelTitle))
                .monospacedDigit()
                .foregroundStyle(AppPalette.appText)
                .lineLimit(1)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        .padding(.leading, 22)
        .padding(.trailing, 14)
        .frame(height: headerBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.calendarHeaderSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(gridLineColor)
                .frame(height: 1)
        }
    }

    private var dayHeaderRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear
                .frame(width: timeColumnWidth, height: 1)
            ForEach(model.days) { day in
                VStack(spacing: 1) {
                    Text(day.headerText)
                        .font(calendarWeekViewFont(.tableHeader, weight: day.isToday ? Font.Weight.bold : Font.Weight.semibold))
                        .foregroundStyle(headerTextColor(for: day))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    ForEach(day.holidayNames, id: \.self) { name in
                        Text(name)
                            .font(calendarWeekViewFont(.secondary, minimumSize: 11))
                            .foregroundStyle(day.highlightColor ?? Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)
                .background(columnTint(for: day))
                .overlay(alignment: .leading) {
                    columnSeparator
                }
                .contentShape(Rectangle())
                .help(day.holidayNames.joined(separator: "\n"))
                .contextMenu {
                    dayContextMenu(day.date)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: All-day strip

    private var allDayStrip: some View {
        let rows = max(min(model.maxAllDayItemCount, maximumVisibleAllDayRows), 1)
        let stripHeight = CGFloat(rows) * (pillHeight + pillSpacing) + pillSpacing
        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                Text(language.text("All day", "Heldag"))
                    .font(calendarWeekViewFont(.secondary, minimumSize: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: timeColumnWidth - 8, alignment: .trailing)
                    .padding(.trailing, 8)
                    .padding(.top, pillSpacing + 3)
                ForEach(model.days) { day in
                    VStack(alignment: .leading, spacing: pillSpacing) {
                        ForEach(day.allDayItems) { item in
                            allDayPill(item, day: day)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, pillSpacing)
                    .frame(maxWidth: .infinity, minHeight: stripHeight, alignment: .topLeading)
                    .background(columnTint(for: day))
                    .overlay(alignment: .leading) {
                        columnSeparator
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        dayContextMenu(day.date)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: stripHeight)
    }

    private func allDayPill(_ item: CalendarWeekViewItem, day: CalendarWeekViewDay) -> some View {
        HStack(spacing: 4) {
            if item.showsCompletionRing {
                CalendarWeekCompletionRing(item: item, language: language)
            }
            Image(systemName: item.style.iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.style.accentColor)
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(item.event.title)
                .font(calendarWeekViewFont(.body))
                .italic(item.style.isItalic)
                .foregroundStyle(AppPalette.appText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .frame(height: pillHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(eventBackground(for: item, cornerRadius: 4))
        .opacity(item.style.opacity)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectEvent(item.event)
        }
        .contextMenu {
            eventContextMenu(item.event, day.date)
        }
        .help(item.helpText)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Hour grid

    private func timeGrid(hourHeight: CGFloat) -> some View {
        let totalHeight = hourHeight * 24
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .font(calendarWeekViewFont(.secondary, minimumSize: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                        .padding(.trailing, 8)
                        .frame(width: timeColumnWidth, height: hourHeight, alignment: .topTrailing)
                        .id(calendarWeekViewHourAnchorID(hour))
                }
            }
            .frame(width: timeColumnWidth, height: totalHeight, alignment: .topLeading)

            ForEach(model.days) { day in
                dayColumn(day, hourHeight: hourHeight)
                    .frame(maxWidth: .infinity, minHeight: totalHeight, maxHeight: totalHeight, alignment: .topLeading)
            }
        }
        .frame(height: totalHeight, alignment: .topLeading)
        .background(alignment: .topLeading) {
            hourLines(hourHeight: hourHeight)
                .padding(.leading, timeColumnWidth)
                .allowsHitTesting(false)
        }
    }

    private func hourLines(hourHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { _ in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(gridLineColor)
                        .frame(height: 0.5)
                    Color.clear
                }
                .frame(height: hourHeight)
            }
        }
        .accessibilityHidden(true)
    }

    private func dayColumn(_ day: CalendarWeekViewDay, hourHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(columnTint(for: day))
                .contentShape(Rectangle())
                .contextMenu {
                    dayContextMenu(day.date)
                }

            GeometryReader { geometry in
                let usableWidth = max(geometry.size.width - 4, 0)
                ForEach(day.timedItems) { item in
                    if let span = item.span {
                        let blockFrame = calendarWeekViewBlockFrame(
                            span: span,
                            hourHeight: hourHeight,
                            minimumHeight: minimumBlockHeight
                        )
                        let columnWidth = usableWidth / CGFloat(max(item.slot.columnCount, 1))
                        eventBlock(item, day: day, height: blockFrame.height)
                            .frame(width: max(columnWidth - 2, 0), height: blockFrame.height, alignment: .topLeading)
                            .offset(x: 2 + columnWidth * CGFloat(item.slot.column), y: blockFrame.y)
                    }
                }
            }

            if day.isToday {
                nowLine(for: day, hourHeight: hourHeight)
            }
        }
        .overlay(alignment: .leading) {
            columnSeparator
        }
    }

    private func eventBlock(_ item: CalendarWeekViewItem, day: CalendarWeekViewDay, height: CGFloat) -> some View {
        let titleLineLimit = height >= 40 ? 2 : 1
        let showsSecondaryText = height >= 46 && !item.secondaryText.isEmpty
        return HStack(alignment: .top, spacing: 4) {
            if item.showsCompletionRing {
                CalendarWeekCompletionRing(item: item, language: language)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: item.style.iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.style.accentColor)
                        .accessibilityHidden(true)
                    Text(item.event.title)
                        .font(calendarWeekViewFont(.body, weight: .semibold))
                        .italic(item.style.isItalic)
                        .foregroundStyle(AppPalette.appText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(titleLineLimit)
                }
                if showsSecondaryText {
                    Text(item.secondaryText)
                        .font(calendarWeekViewFont(.secondary, minimumSize: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .padding(.top, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(eventBackground(for: item, cornerRadius: 5))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .opacity(item.style.opacity)
        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .onTapGesture {
            onSelectEvent(item.event)
        }
        .contextMenu {
            eventContextMenu(item.event, day.date)
        }
        .help(item.helpText)
        .accessibilityAddTraits(.isButton)
    }

    private func nowLine(for day: CalendarWeekViewDay, hourHeight: CGFloat) -> some View {
        TimelineView(.everyMinute) { context in
            if model.calendar.isDate(context.date, inSameDayAs: day.date) {
                let y = calendarWeekViewYOffset(
                    minute: calendarWeekViewMinuteOfDay(for: context.date, calendar: model.calendar),
                    hourHeight: hourHeight
                )
                HStack(spacing: 0) {
                    Circle()
                        .fill(nowLineColor)
                        .frame(width: 8, height: 8)
                    Rectangle()
                        .fill(nowLineColor)
                        .frame(height: 1.5)
                }
                .offset(x: -4, y: y - 4)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Colours and helpers

    private var gridLineColor: Color {
        AppPalette.subtleBorder.opacity(usesDarkAppearance ? 0.78 : 0.7)
    }

    private var nowLineColor: Color {
        Color(nsColor: .systemRed)
    }

    private var columnSeparator: some View {
        Rectangle()
            .fill(gridLineColor)
            .frame(width: 0.5)
            .accessibilityHidden(true)
    }

    private func headerTextColor(for day: CalendarWeekViewDay) -> Color {
        if day.isToday {
            return AppPalette.vividBlue
        }
        return day.highlightColor ?? AppPalette.appText
    }

    private func columnTint(for day: CalendarWeekViewDay) -> Color {
        if day.isToday {
            return AppPalette.vividBlue.opacity(usesDarkAppearance ? 0.12 : 0.06)
        }
        if let highlightColor = day.highlightColor {
            return highlightColor.opacity(usesDarkAppearance ? 0.08 : 0.045)
        }
        return Color.clear
    }

    private func eventBackground(for item: CalendarWeekViewItem, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(item.style.accentColor.opacity(usesDarkAppearance ? 0.26 : 0.15))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(item.style.accentColor)
                    .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func scrollToFirstVisibleHour(using proxy: ScrollViewProxy) {
        let anchorID = calendarWeekViewHourAnchorID(firstVisibleHour)
        DispatchQueue.main.async {
            proxy.scrollTo(anchorID, anchor: .top)
        }
    }
}

/// The "Klar" ring for tasks in the week view, with the same red attention
/// ring as the list when the task is overdue or reminding.
private struct CalendarWeekCompletionRing: View {
    let item: CalendarWeekViewItem
    let language: AppLanguage

    var body: some View {
        Button {
            item.event.toggleCompletion?(!item.event.isCompleted)
        } label: {
            Image(systemName: item.event.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.style.completionTint)
                .frame(width: 16, height: 16)
                .overlay {
                    if item.style.needsAttentionRing {
                        Circle()
                            .stroke(Color(nsColor: .systemRed), lineWidth: 2)
                            .frame(width: 17, height: 17)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.event.isRolledOverPastDue ? language.text("Overdue", "Försenad") : "")
        .accessibilityLabel(
            item.event.isCompleted
                ? language.text("Mark as not done", "Markera som inte klar")
                : language.text("Mark as done", "Markera som klar")
        )
    }
}
