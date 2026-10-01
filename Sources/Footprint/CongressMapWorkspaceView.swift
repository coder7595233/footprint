import AppKit
import CoreLocation
import MapKit
import SwiftUI

struct CongressMapRow: Identifiable, Hashable {
    let id: String
    let organizationID: String
    let congressID: String
    let title: String
    let organizationName: String
    let city: String
    let country: String
    let placeText: String
    let locationQuery: String?
    let locationCacheKey: String?
    let startDate: Date
    let endDate: Date
    let startDateText: String
    let dateText: String
    let link: String
    let hasUncertainDate: Bool
    let currentUserParticipates: Bool
    let hasLinkedAbstractOrContribution: Bool
    let abstractSubmissionDeadline: Date?
    let abstractSubmissionDeadlineUncertain: Bool
    let lateAbstractSubmissionDeadline: Date?
    let lateAbstractSubmissionDeadlineUncertain: Bool
    let isHiddenOnMap: Bool
}

enum CongressMapModel {
    static func upcomingCongressRows(
        organizations: [OrganizationRecord],
        conferenceContributions: [CVConferenceContribution] = [],
        language: AppLanguage,
        currentUserAuthor: PublicationAuthor? = nil,
        monthsFrom: Int? = nil,
        monthsAhead: Int? = nil,
        hidesPassedAbstractDeadlines: Bool = false,
        showsParticipatedCongressesOnly: Bool = false,
        showsHiddenCongresses: Bool = false,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [CongressMapRow] {
        let todayStart = calendar.startOfDay(for: today)
        let lowerBound = monthsFrom.flatMap { months in
            calendar.date(byAdding: .month, value: max(0, months), to: todayStart)
        }.map { calendar.startOfDay(for: $0) }
        let effectiveLowerBound = lowerBound ?? todayStart
        let upperBound = monthsAhead.flatMap { months in
            calendar.date(byAdding: .month, value: max(0, months), to: todayStart)
        }.map { calendar.startOfDay(for: $0) }
        let contributionsByCongress = Dictionary(grouping: conferenceContributions) { contribution in
            congressContributionKey(
                organizationID: contribution.congressOrganizationID,
                congressID: contribution.congressID
            )
        }
        return organizations.flatMap { organization in
            organization.congresses.compactMap { congress -> CongressMapRow? in
                let linkedContributions = contributionsByCongress[
                    congressContributionKey(
                        organizationID: organization.id,
                        congressID: congress.id
                    )
                ] ?? []
                let hasLinkedAbstractOrContribution = hasAbstractOrContributionData(in: linkedContributions)
                let currentUserParticipates = CongressesWorkspaceView.congressCurrentUserParticipates(
                    congress,
                    currentUserAuthor: currentUserAuthor
                )
                if showsParticipatedCongressesOnly,
                   !currentUserParticipates,
                   !hasLinkedAbstractOrContribution {
                    return nil
                }
                if congress.isHiddenOnMap && !showsHiddenCongresses {
                    return nil
                }
                let parsedStart = congress.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                let parsedEnd = congress.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                guard let start = parsedStart ?? parsedEnd else { return nil }
                let end = parsedEnd ?? parsedStart ?? start
                let range = start <= end ? (start: start, end: end) : (start: end, end: start)
                if !showsParticipatedCongressesOnly {
                    guard calendar.startOfDay(for: range.end) >= effectiveLowerBound else { return nil }
                    if let upperBound, calendar.startOfDay(for: range.start) > upperBound {
                        return nil
                    }
                }
                let abstractSubmissionDeadline = congress.abstractSubmissionDeadline.nonEmpty
                    .flatMap(DateParsers.isoDay.date(from:))
                let lateAbstractSubmissionDeadline = congress.lateAbstractSubmissionDeadline.nonEmpty
                    .flatMap(DateParsers.isoDay.date(from:))
                if hidesPassedAbstractDeadlines,
                   !showsParticipatedCongressesOnly,
                   congressHasPassedAbstractDeadline(congress, on: todayStart, calendar: calendar) {
                    return nil
                }

                let city = congress.city.trimmedOrNil ?? ""
                let country = congress.country.trimmedOrNil ?? ""
                let locationParts = [city.nonEmpty, country.nonEmpty].compactMap { $0 }
                let locationQuery = locationParts.isEmpty ? nil : locationParts.joined(separator: ", ")
                let title = congress.title.nonEmpty ?? organization.displayName(for: language)

                return CongressMapRow(
                    id: "\(organization.id):\(congress.id)",
                    organizationID: organization.id,
                    congressID: congress.id,
                    title: title,
                    organizationName: organization.displayName(for: language),
                    city: city,
                    country: country,
                    placeText: locationQuery ?? "",
                    locationQuery: locationQuery,
                    locationCacheKey: locationQuery.map(normalizedLocationCacheKey),
                    startDate: range.start,
                    endDate: range.end,
                    startDateText: compactDateRangeText(
                        start: range.start,
                        end: range.start,
                        language: language,
                        calendar: calendar
                    ),
                    dateText: compactDateRangeText(start: range.start, end: range.end, language: language, calendar: calendar),
                    link: congress.link,
                    hasUncertainDate: congress.fromUncertain || congress.toUncertain,
                    currentUserParticipates: currentUserParticipates,
                    hasLinkedAbstractOrContribution: hasLinkedAbstractOrContribution,
                    abstractSubmissionDeadline: abstractSubmissionDeadline,
                    abstractSubmissionDeadlineUncertain: congress.abstractSubmissionDeadlineUncertain,
                    lateAbstractSubmissionDeadline: lateAbstractSubmissionDeadline,
                    lateAbstractSubmissionDeadlineUncertain: congress.lateAbstractSubmissionDeadlineUncertain,
                    isHiddenOnMap: congress.isHiddenOnMap
                )
            }
        }
        .sorted {
            if $0.startDate != $1.startDate {
                return $0.startDate < $1.startDate
            }
            if $0.title != $1.title {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.organizationName.localizedStandardCompare($1.organizationName) == .orderedAscending
        }
    }

    static func normalizedLocationCacheKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func hasAbstractOrContributionData(in contributions: [CVConferenceContribution]) -> Bool {
        contributions.contains { contribution in
            contribution.localizedTitle(language: .swedish).trimmedOrNil != nil
                || contribution.localizedTitle(language: .english).trimmedOrNil != nil
                || contribution.localizedName(language: .swedish).trimmedOrNil != nil
                || contribution.localizedName(language: .english).trimmedOrNil != nil
                || contribution.contributorNames.contains(where: { $0.trimmedOrNil != nil })
                || contribution.submissionAppliedOn.trimmedOrNil != nil
                || contribution.submissionDecisionOn.trimmedOrNil != nil
                || contribution.submissionOutcome != nil
                || contribution.status == .presented
        }
    }

    private static func congressContributionKey(
        organizationID: String?,
        congressID: String?
    ) -> String {
        "\(organizationID ?? "")\u{1F}\(congressID ?? "")"
    }

    static func compactDateRangeText(
        start: Date,
        end: Date,
        language: AppLanguage,
        calendar: Calendar = .current
    ) -> String {
        let startComponents = calendar.dateComponents([.day, .month, .year], from: start)
        let endComponents = calendar.dateComponents([.day, .month, .year], from: end)
        guard let startDay = startComponents.day,
              let startMonth = startComponents.month,
              let startYear = startComponents.year,
              let endDay = endComponents.day,
              let endMonth = endComponents.month,
              let endYear = endComponents.year else {
            return "\(DateParsers.isoDay.string(from: start)) - \(DateParsers.isoDay.string(from: end))"
        }

        if startDay == endDay && startMonth == endMonth && startYear == endYear {
            return compactDateText(start, includesYear: true, language: language, calendar: calendar)
        }

        if startMonth == endMonth && startYear == endYear {
            return "\(startDay)-\(endDay) \(monthName(startMonth, language: language)) \(startYear)"
        }

        if startYear == endYear {
            return "\(startDay) \(monthName(startMonth, language: language))-\(endDay) \(monthName(endMonth, language: language)) \(startYear)"
        }

        return [
            compactDateText(start, includesYear: true, language: language, calendar: calendar),
            compactDateText(end, includesYear: true, language: language, calendar: calendar)
        ].joined(separator: "-")
    }

    static func mapRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else { return defaultMapRegion }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLatitude = latitudes.min() ?? first.latitude
        let maxLatitude = latitudes.max() ?? first.latitude
        let minLongitude = longitudes.min() ?? first.longitude
        let maxLongitude = longitudes.max() ?? first.longitude
        let latitudeDelta = max(2.2, (maxLatitude - minLatitude) * 1.35)
        let longitudeDelta = max(2.2, (maxLongitude - minLongitude) * 1.35)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: min(120, latitudeDelta),
                longitudeDelta: min(160, longitudeDelta)
            )
        )
    }

    static var defaultMapRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 54.5, longitude: 15.0),
            span: MKCoordinateSpan(latitudeDelta: 45.0, longitudeDelta: 55.0)
        )
    }

    private static func compactDateText(
        _ date: Date,
        includesYear: Bool,
        language: AppLanguage,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents([.day, .month, .year], from: date)
        guard let day = components.day,
              let month = components.month,
              let year = components.year else {
            return DateParsers.isoDay.string(from: date)
        }
        let base = "\(day) \(monthName(month, language: language))"
        return includesYear ? "\(base) \(year)" : base
    }

    private static func monthName(_ month: Int, language: AppLanguage) -> String {
        switch (language, month) {
        case (.swedish, 1): return "jan"
        case (.swedish, 2): return "feb"
        case (.swedish, 3): return "mars"
        case (.swedish, 4): return "apr"
        case (.swedish, 5): return "maj"
        case (.swedish, 6): return "juni"
        case (.swedish, 7): return "juli"
        case (.swedish, 8): return "aug"
        case (.swedish, 9): return "sep"
        case (.swedish, 10): return "okt"
        case (.swedish, 11): return "nov"
        case (.swedish, 12): return "dec"
        case (.english, 1): return "Jan"
        case (.english, 2): return "Feb"
        case (.english, 3): return "Mar"
        case (.english, 4): return "Apr"
        case (.english, 5): return "May"
        case (.english, 6): return "Jun"
        case (.english, 7): return "Jul"
        case (.english, 8): return "Aug"
        case (.english, 9): return "Sep"
        case (.english, 10): return "Oct"
        case (.english, 11): return "Nov"
        case (.english, 12): return "Dec"
        default: return "\(month)"
        }
    }
}

struct CongressMapAdaptiveLayoutItem: Identifiable {
    let id: String
    let point: CGPoint
    let locationCacheKey: String?
    let city: String
    let placeText: String
    let startDate: Date
    let currentUserParticipates: Bool
}

enum CongressMapAdaptiveLabelKind: Equatable {
    case congress
    case cluster(count: Int, placeText: String?)
}

struct CongressMapAdaptiveLabelPlan: Identifiable, Equatable {
    let id: String
    let representativeID: String
    let memberIDs: [String]
    let kind: CongressMapAdaptiveLabelKind
    let isSelected: Bool
    let currentUserParticipates: Bool
    let startDate: Date
}

enum CongressMapAdaptiveLayout {
    private struct GridCell: Hashable {
        let column: Int
        let row: Int
    }

    static func labelPlans(
        items: [CongressMapAdaptiveLayoutItem],
        selectedID: String?,
        capacity: Int,
        horizontalThreshold: CGFloat = 164,
        verticalThreshold: CGFloat = 96
    ) -> [CongressMapAdaptiveLabelPlan] {
        guard !items.isEmpty, capacity > 0 else { return [] }

        let groups = connectedGroups(
            items: items,
            horizontalThreshold: horizontalThreshold,
            verticalThreshold: verticalThreshold
        )
        var plans: [CongressMapAdaptiveLabelPlan] = []

        for group in groups {
            var remaining = group
            if let selectedID,
               let selectedIndex = remaining.firstIndex(where: { $0.id == selectedID }) {
                let selected = remaining.remove(at: selectedIndex)
                plans.append(
                    CongressMapAdaptiveLabelPlan(
                        id: selected.id,
                        representativeID: selected.id,
                        memberIDs: [selected.id],
                        kind: .congress,
                        isSelected: true,
                        currentUserParticipates: selected.currentUserParticipates,
                        startDate: selected.startDate
                    )
                )
            }

            guard !remaining.isEmpty else { continue }
            let representative = preferredRepresentative(in: remaining)
            if remaining.count == 1 {
                plans.append(
                    CongressMapAdaptiveLabelPlan(
                        id: representative.id,
                        representativeID: representative.id,
                        memberIDs: [representative.id],
                        kind: .congress,
                        isSelected: false,
                        currentUserParticipates: representative.currentUserParticipates,
                        startDate: representative.startDate
                    )
                )
            } else {
                let sharedLocationKey = remaining.first?.locationCacheKey.flatMap { firstKey in
                    remaining.allSatisfy { $0.locationCacheKey == firstKey } ? firstKey : nil
                }
                let sharedPlaceText: String?
                if sharedLocationKey != nil {
                    sharedPlaceText = representative.city.nonEmpty ?? representative.placeText.nonEmpty
                } else {
                    sharedPlaceText = nil
                }
                plans.append(
                    CongressMapAdaptiveLabelPlan(
                        id: "cluster:\(remaining.map(\.id).sorted().joined(separator: "|"))",
                        representativeID: representative.id,
                        memberIDs: remaining.map(\.id),
                        kind: .cluster(count: remaining.count, placeText: sharedPlaceText),
                        isSelected: false,
                        currentUserParticipates: remaining.contains(where: \.currentUserParticipates),
                        startDate: remaining.map(\.startDate).min() ?? representative.startDate
                    )
                )
            }
        }

        return Array(plans.sorted(by: labelPrioritySort).prefix(capacity))
    }

    private static func connectedGroups(
        items: [CongressMapAdaptiveLayoutItem],
        horizontalThreshold: CGFloat,
        verticalThreshold: CGFloat
    ) -> [[CongressMapAdaptiveLayoutItem]] {
        let horizontalCellSize = max(horizontalThreshold, 1)
        let verticalCellSize = max(verticalThreshold, 1)
        func cell(for point: CGPoint) -> GridCell {
            GridCell(
                column: Int(floor(point.x / horizontalCellSize)),
                row: Int(floor(point.y / verticalCellSize))
            )
        }

        var indexesByCell: [GridCell: [Int]] = [:]
        for index in items.indices {
            indexesByCell[cell(for: items[index].point), default: []].append(index)
        }

        var groups: [[CongressMapAdaptiveLayoutItem]] = []
        var remainingIndexes = Set(items.indices)

        while let startIndex = remainingIndexes.min() {
            remainingIndexes.remove(startIndex)
            var groupIndexes = [startIndex]
            var queue = [startIndex]
            var queueCursor = 0

            while queueCursor < queue.count {
                let currentIndex = queue[queueCursor]
                queueCursor += 1
                let current = items[currentIndex]
                let currentCell = cell(for: current.point)

                for columnOffset in -1...1 {
                    for rowOffset in -1...1 {
                        let neighborCell = GridCell(
                            column: currentCell.column + columnOffset,
                            row: currentCell.row + rowOffset
                        )
                        for candidateIndex in indexesByCell[neighborCell] ?? [] {
                            guard remainingIndexes.contains(candidateIndex) else { continue }
                            let candidate = items[candidateIndex]
                            guard abs(current.point.x - candidate.point.x) <= horizontalThreshold,
                                  abs(current.point.y - candidate.point.y) <= verticalThreshold else {
                                continue
                            }
                            remainingIndexes.remove(candidateIndex)
                            groupIndexes.append(candidateIndex)
                            queue.append(candidateIndex)
                        }
                    }
                }
            }

            groups.append(groupIndexes.map { items[$0] })
        }

        return groups
    }

    private static func preferredRepresentative(
        in items: [CongressMapAdaptiveLayoutItem]
    ) -> CongressMapAdaptiveLayoutItem {
        items.sorted {
            if $0.currentUserParticipates != $1.currentUserParticipates {
                return $0.currentUserParticipates && !$1.currentUserParticipates
            }
            if $0.startDate != $1.startDate {
                return $0.startDate < $1.startDate
            }
            return $0.id < $1.id
        }
        .first ?? items[0]
    }

    private static func labelPrioritySort(
        _ lhs: CongressMapAdaptiveLabelPlan,
        _ rhs: CongressMapAdaptiveLabelPlan
    ) -> Bool {
        if lhs.isSelected != rhs.isSelected {
            return lhs.isSelected && !rhs.isSelected
        }
        if lhs.currentUserParticipates != rhs.currentUserParticipates {
            return lhs.currentUserParticipates && !rhs.currentUserParticipates
        }
        let leftClusterCount = clusterCount(for: lhs.kind)
        let rightClusterCount = clusterCount(for: rhs.kind)
        if leftClusterCount != rightClusterCount {
            return leftClusterCount > rightClusterCount
        }
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        return lhs.id < rhs.id
    }

    private static func clusterCount(for kind: CongressMapAdaptiveLabelKind) -> Int {
        guard case let .cluster(count, _) = kind else { return 0 }
        return count
    }
}

private enum CongressMapRegionPreset: String, CaseIterable, Identifiable {
    case northAmerica
    case centralAmerica
    case southAmerica
    case europe
    case africa
    case middleEast
    case asia
    case oceania

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .northAmerica:
            return language.text("North America", "Nordamerika")
        case .centralAmerica:
            return language.text("Central America", "Centralamerika")
        case .southAmerica:
            return language.text("South America", "Sydamerika")
        case .europe:
            return language.text("Europe", "Europa")
        case .africa:
            return language.text("Africa", "Afrika")
        case .middleEast:
            return language.text("Middle East", "Mellanöstern")
        case .asia:
            return language.text("Asia", "Asien")
        case .oceania:
            return language.text("Oceania & Pacific", "Oceanien (inkl. Stilla havsområdet)")
        }
    }

    var region: MKCoordinateRegion {
        switch self {
        case .northAmerica:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 48, longitude: -103),
                span: MKCoordinateSpan(latitudeDelta: 56, longitudeDelta: 90)
            )
        case .centralAmerica:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 15, longitude: -86),
                span: MKCoordinateSpan(latitudeDelta: 24, longitudeDelta: 36)
            )
        case .southAmerica:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: -20, longitude: -61),
                span: MKCoordinateSpan(latitudeDelta: 58, longitudeDelta: 54)
            )
        case .europe:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 54, longitude: 16),
                span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 46)
            )
        case .africa:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 1, longitude: 20),
                span: MKCoordinateSpan(latitudeDelta: 74, longitudeDelta: 70)
            )
        case .middleEast:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 29, longitude: 45),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 40)
            )
        case .asia:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 34, longitude: 95),
                span: MKCoordinateSpan(latitudeDelta: 72, longitudeDelta: 112)
            )
        case .oceania:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: -17, longitude: 162),
                span: MKCoordinateSpan(latitudeDelta: 70, longitudeDelta: 154)
            )
        }
    }
}

private enum CongressMapPreferences {
    private static let visibleMonthsFromKey = AppRuntime.scopedDefaultsKey("CongressMapVisibleMonthsFrom")
    private static let visibleMonthsKey = AppRuntime.scopedDefaultsKey("CongressMapVisibleMonthsAhead")
    private static let hidePassedAbstractDeadlineKey = AppRuntime.scopedDefaultsKey("CongressMapHidePassedAbstractDeadline")
    private static let showParticipatedCongressesOnlyKey = AppRuntime.scopedDefaultsKey("CongressMapShowParticipatedCongressesOnly")
    private static let showHiddenCongressesKey = AppRuntime.scopedDefaultsKey("CongressMapShowHiddenCongresses")

    static let defaultVisibleMonthsFrom = 0.0
    static let defaultVisibleMonthsAhead = 24.0
    static let defaultHidesPassedAbstractDeadlines = true
    static let defaultShowsParticipatedCongressesOnly = false
    static let defaultShowsHiddenCongresses = false

    static func loadVisibleMonthsFrom() -> Double {
        guard UserDefaults.standard.object(forKey: visibleMonthsFromKey) != nil else {
            return defaultVisibleMonthsFrom
        }
        return normalizedVisibleMonthValue(UserDefaults.standard.double(forKey: visibleMonthsFromKey))
    }

    static func loadVisibleMonthsAhead() -> Double {
        guard UserDefaults.standard.object(forKey: visibleMonthsKey) != nil else {
            return defaultVisibleMonthsAhead
        }
        return normalizedVisibleMonthValue(UserDefaults.standard.double(forKey: visibleMonthsKey))
    }

    static func loadHidesPassedAbstractDeadlines() -> Bool {
        guard UserDefaults.standard.object(forKey: hidePassedAbstractDeadlineKey) != nil else {
            return defaultHidesPassedAbstractDeadlines
        }
        return UserDefaults.standard.bool(forKey: hidePassedAbstractDeadlineKey)
    }

    static func loadShowsHiddenCongresses() -> Bool {
        guard UserDefaults.standard.object(forKey: showHiddenCongressesKey) != nil else {
            return defaultShowsHiddenCongresses
        }
        return UserDefaults.standard.bool(forKey: showHiddenCongressesKey)
    }

    static func loadShowsParticipatedCongressesOnly() -> Bool {
        guard UserDefaults.standard.object(forKey: showParticipatedCongressesOnlyKey) != nil else {
            return defaultShowsParticipatedCongressesOnly
        }
        return UserDefaults.standard.bool(forKey: showParticipatedCongressesOnlyKey)
    }

    static func save(
        visibleMonthsFrom: Double,
        visibleMonthsAhead: Double,
        hidesPassedAbstractDeadlines: Bool,
        showsParticipatedCongressesOnly: Bool,
        showsHiddenCongresses: Bool
    ) {
        let normalizedRange = normalizedVisibleMonthRange(
            from: visibleMonthsFrom,
            through: visibleMonthsAhead
        )
        UserDefaults.standard.set(normalizedRange.from, forKey: visibleMonthsFromKey)
        UserDefaults.standard.set(normalizedRange.through, forKey: visibleMonthsKey)
        UserDefaults.standard.set(hidesPassedAbstractDeadlines, forKey: hidePassedAbstractDeadlineKey)
        UserDefaults.standard.set(showsParticipatedCongressesOnly, forKey: showParticipatedCongressesOnlyKey)
        UserDefaults.standard.set(showsHiddenCongresses, forKey: showHiddenCongressesKey)
    }

    static func normalizedVisibleMonthsAhead(_ value: Double) -> Double {
        normalizedVisibleMonthValue(value)
    }

    static func normalizedVisibleMonthsFrom(_ value: Double) -> Double {
        normalizedVisibleMonthValue(value)
    }

    static func normalizedVisibleMonthRange(from: Double, through: Double) -> (from: Double, through: Double) {
        let normalizedFrom = normalizedVisibleMonthValue(from)
        let normalizedThrough = normalizedVisibleMonthValue(through)
        return (
            from: min(normalizedFrom, normalizedThrough),
            through: max(normalizedFrom, normalizedThrough)
        )
    }

    private static func normalizedVisibleMonthValue(_ value: Double) -> Double {
        min(60, max(0, value.rounded()))
    }
}

struct CongressMapWorkspaceView: View {
    @ObservedObject var store: GrantDataStore
    let isActive: Bool

    @State private var referenceDate = Date()
    @State private var selectedCongressID: String?
    @State private var selectedCongressDetailPoint: CGPoint?
    @State private var resolvedCoordinates: [String: CongressMapCoordinate] = [:]
    @State private var failedLocationKeys: Set<String> = []
    @State private var geocodingTask: Task<Void, Never>?
    @State private var geocodingGeneration: UInt = 0
    @State private var hasLoadedCoordinateCache = false
    @State private var hasSetInitialMapRegion = false
    @State private var geocodingLocationCount = 0
    @State private var visibleMonthsFrom = CongressMapPreferences.defaultVisibleMonthsFrom
    @State private var visibleMonthsAhead = CongressMapPreferences.defaultVisibleMonthsAhead
    @State private var hidesPassedAbstractDeadlines = CongressMapPreferences.defaultHidesPassedAbstractDeadlines
    @State private var showsParticipatedCongressesOnly = CongressMapPreferences.defaultShowsParticipatedCongressesOnly
    @State private var showsHiddenCongresses = CongressMapPreferences.defaultShowsHiddenCongresses
    @State private var visibleMapRegion: MKCoordinateRegion = CongressMapModel.defaultMapRegion
    @State private var requestedMapRegion: MKCoordinateRegion = CongressMapModel.defaultMapRegion
    @State private var mapRegionRequestID = 0
    @State private var mapViewportSize: CGSize = .zero
    @State private var showsCongressList = false
    @State private var cachedUnfilteredRows: [CongressMapRow] = []
    @State private var cachedRows: [CongressMapRow] = []
    @State private var searchText = ""

    private var language: AppLanguage {
        store.language
    }

    private var unfilteredRows: [CongressMapRow] {
        cachedUnfilteredRows
    }

    private func rebuildCachedMapRows() {
        let nextRows = CongressMapModel.upcomingCongressRows(
            organizations: store.organizationsForCongressRead,
            conferenceContributions: store.cvConferenceContributions,
            language: language,
            currentUserAuthor: store.currentUserAuthor(),
            monthsFrom: Int(visibleMonthsFrom.rounded()),
            monthsAhead: Int(visibleMonthsAhead.rounded()),
            hidesPassedAbstractDeadlines: hidesPassedAbstractDeadlines,
            showsParticipatedCongressesOnly: showsParticipatedCongressesOnly,
            showsHiddenCongresses: showsHiddenCongresses,
            today: referenceDate
        )
        cachedUnfilteredRows = nextRows
        cachedRows = filteredMapRows(from: nextRows, searchText: searchText)
    }

    private var rows: [CongressMapRow] {
        cachedRows
    }

    private func refreshCachedSearchRows() {
        cachedRows = filteredMapRows(from: cachedUnfilteredRows, searchText: searchText)
    }

    private func filteredMapRows(
        from unfilteredRows: [CongressMapRow],
        searchText: String
    ) -> [CongressMapRow] {
        let query = SearchFilterQuery(raw: searchText)
        guard !query.isEmpty else { return unfilteredRows }
        return unfilteredRows.filter { row in
            query.matches(
                haystack: [
                    row.title,
                    row.organizationName,
                    row.city,
                    row.country,
                    row.placeText,
                    row.dateText
                ]
                .joined(separator: " ")
            )
        }
    }

    private var positionedRows: [PositionedCongressMapRow] {
        rows.compactMap { row in
            guard let key = row.locationCacheKey,
                  let coordinate = resolvedCoordinates[key]?.coordinate else { return nil }
            return PositionedCongressMapRow(row: row, coordinate: coordinate)
        }
    }

    private var positionedAnnotations: [PositionedCongressMapAnnotation] {
        let screenRows = positionedRows.compactMap { positioned -> ScreenPositionedCongressMapRow? in
            guard let screenPoint = screenPoint(for: positioned.coordinate) else { return nil }
            return ScreenPositionedCongressMapRow(positioned: positioned, screenPoint: screenPoint)
        }

        guard screenRows.count == positionedRows.count else {
            return positionedRows.map { positioned in
                PositionedCongressMapAnnotation(
                    row: positioned.row,
                    coordinate: positioned.coordinate,
                    placement: .defaultPlacement
                )
            }
        }

        let placements = sideAnnotationPlacements(for: screenRows)
        return screenRows.map { screenRow in
            return PositionedCongressMapAnnotation(
                row: screenRow.positioned.row,
                coordinate: screenRow.positioned.coordinate,
                placement: placements[screenRow.positioned.id] ?? .defaultPlacement
            )
        }
    }

    private var currentUserAffiliationLocations: [CongressMapAffiliationLocation] {
        guard let author = store.currentUserAuthor() else { return [] }
        let populatedAffiliations = author.affiliations.filter { !$0.isEmpty }
        guard !populatedAffiliations.isEmpty else { return [] }

        let primaryAffiliation = author.primaryAffiliation ?? populatedAffiliations.first
        let secondaryAffiliation = populatedAffiliations.first { affiliation in
            affiliation.id != primaryAffiliation?.id && !affiliation.isPrimary
        } ?? populatedAffiliations.first { affiliation in
            affiliation.id != primaryAffiliation?.id
        }

        var locations: [CongressMapAffiliationLocation] = []
        if let primaryAffiliation,
           let location = affiliationLocation(kind: .primary, affiliation: primaryAffiliation) {
            locations.append(location)
        }
        if let secondaryAffiliation,
           let location = affiliationLocation(kind: .secondary, affiliation: secondaryAffiliation) {
            locations.append(location)
        }

        var seenIDs: Set<String> = []
        return locations.filter { seenIDs.insert($0.id).inserted }
    }

    private var positionedAffiliationAnnotations: [PositionedCongressMapAffiliationAnnotation] {
        let positioned = currentUserAffiliationLocations.compactMap { location -> (location: CongressMapAffiliationLocation, coordinate: CLLocationCoordinate2D)? in
            guard let coordinate = resolvedCoordinates[location.cacheKey]?.coordinate else { return nil }
            return (location, coordinate)
        }
        let countsByLocationKey = positioned.reduce(into: [String: Int]()) { counts, item in
            counts[item.location.cacheKey, default: 0] += 1
        }
        var indexesByLocationKey: [String: Int] = [:]
        return positioned.map { item in
            let index = indexesByLocationKey[item.location.cacheKey, default: 0]
            indexesByLocationKey[item.location.cacheKey] = index + 1
            return PositionedCongressMapAffiliationAnnotation(
                location: item.location,
                coordinate: item.coordinate,
                stackIndex: index,
                stackCount: countsByLocationKey[item.location.cacheKey, default: 1]
            )
        }
    }

    private var rowsWithoutCoordinates: [CongressMapRow] {
        rows.filter { row in
            guard let key = row.locationCacheKey else { return true }
            return resolvedCoordinates[key] == nil
        }
    }

    private var currentUserAffiliationLocation: CongressMapAffiliationLocation? {
        currentUserAffiliationLocations.first(where: { $0.kind == .primary }) ?? currentUserAffiliationLocations.first
    }

    private func affiliationLocation(
        kind: CongressMapAffiliationKind,
        affiliation: PublicationAffiliation
    ) -> CongressMapAffiliationLocation? {
        let rawOrganizationText = affiliation.localizedOrganization(language: language).trimmedOrNil
            ?? affiliation.organization.trimmedOrNil
        // "Alla kopplingar via id": the linked organization first.
        let matchedOrganization = affiliation.organizationID.flatMap { store.organization(id: $0) }
            ?? rawOrganizationText.flatMap { store.organization(matchingName: $0) }
            ?? store.organization(matchingName: affiliation.organization)
        let city = affiliation.city.trimmedOrNil ?? matchedOrganization?.city.trimmedOrNil
        let country = affiliation.country.trimmedOrNil ?? matchedOrganization?.country.trimmedOrNil
        let locationParts = [city, country].compactMap { $0 }
        guard !locationParts.isEmpty else { return nil }
        let query = locationParts.joined(separator: ", ")
        return CongressMapAffiliationLocation(
            id: "affiliation:\(kind.rawValue):\(affiliation.id)",
            kind: kind,
            placeText: query,
            displayText: city ?? query,
            query: query,
            cacheKey: CongressMapModel.normalizedLocationCacheKey(query)
        )
    }

    private var rowsSignature: String {
        let congressSignature = rows.map { "\($0.id)|\($0.locationCacheKey ?? "-")|\($0.startDate.timeIntervalSinceReferenceDate)|\($0.isHiddenOnMap)" }
            .joined(separator: "||")
        let affiliationSignature = currentUserAffiliationLocations.map { "\($0.id)|\($0.cacheKey)|\($0.displayText)" }
            .joined(separator: "||")
        return [congressSignature, affiliationSignature].joined(separator: "##")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                if showsCongressList {
                    sidebar
                        .frame(width: 360)
                        .background(AppPalette.cardSurface.opacity(0.82))
                    Divider()
                }
                mapContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.canvasBottom)
        .onAppear {
            referenceDate = Date()
            loadMapPreferences()
            rebuildCachedMapRows()
            loadCoordinateCacheIfNeeded()
            startGeocodingIfNeeded()
            fitMapToAnnotationsIfNeeded()
        }
        .onChange(of: isActive) { _, active in
            guard active else { return }
            referenceDate = Date()
            rebuildCachedMapRows()
            startGeocodingIfNeeded()
            fitMapToAnnotationsIfNeeded()
        }
        .onReceive(store.$organizationRowSnapshotGeneration.dropFirst()) { _ in
            rebuildCachedMapRows()
        }
        .onReceive(store.$cvConferenceContributions.dropFirst()) { _ in
            // Deferred: @Published emits at willSet and the rebuild reads
            // the store's committed state.
            DispatchQueue.main.async {
                rebuildCachedMapRows()
            }
        }
        .onReceive(store.$publicationAuthorRowSnapshotGeneration.dropFirst()) { _ in
            rebuildCachedMapRows()
        }
        .onChange(of: store.language) { _, _ in
            rebuildCachedMapRows()
        }
        .onChange(of: searchText) { _, _ in
            refreshCachedSearchRows()
        }
        .onChange(of: selectedCongressID) { _, selectedID in
            if selectedID == nil {
                selectedCongressDetailPoint = nil
            }
        }
        .onChange(of: rowsSignature) { _, _ in
            if let selectedCongressID,
               rows.contains(where: { $0.id == selectedCongressID }) == false {
                self.selectedCongressID = nil
            }
            hasSetInitialMapRegion = false
            startGeocodingIfNeeded()
            fitMapToAnnotationsIfNeeded()
        }
        .onChange(of: visibleMonthsFrom) { _, newValue in
            let normalizedValue = min(
                CongressMapPreferences.normalizedVisibleMonthsFrom(newValue),
                visibleMonthsAhead
            )
            if normalizedValue != newValue {
                visibleMonthsFrom = normalizedValue
                return
            }
            persistMapPreferences()
            rebuildCachedMapRows()
        }
        .onChange(of: visibleMonthsAhead) { _, newValue in
            let normalizedValue = max(
                CongressMapPreferences.normalizedVisibleMonthsAhead(newValue),
                visibleMonthsFrom
            )
            if normalizedValue != newValue {
                visibleMonthsAhead = normalizedValue
                return
            }
            persistMapPreferences()
            rebuildCachedMapRows()
        }
        .onChange(of: hidesPassedAbstractDeadlines) { _, _ in
            persistMapPreferences()
            rebuildCachedMapRows()
        }
        .onChange(of: showsParticipatedCongressesOnly) { _, _ in
            persistMapPreferences()
            rebuildCachedMapRows()
        }
        .onChange(of: showsHiddenCongresses) { _, _ in
            persistMapPreferences()
            rebuildCachedMapRows()
        }
        .onDisappear {
            geocodingGeneration &+= 1
            geocodingTask?.cancel()
            geocodingTask = nil
            geocodingLocationCount = 0
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Text(language.text("Map", "Karta"))
                    .appTypography(.pageTitle)

                Button {
                    showsCongressList.toggle()
                } label: {
                    Label(
                        showsCongressList
                            ? language.text("Hide congress list", "Dölj kongresslista")
                            : language.text("Show congress list", "Visa kongresslista"),
                        systemImage: "sidebar.left"
                    )
                }
                .controlSize(.small)
                .help(
                    showsCongressList
                        ? language.text("Hide the congress list and give the map more space", "Dölj kongresslistan och ge kartan mer utrymme")
                        : language.text("Show the congress list", "Visa kongresslistan")
                )

                Spacer(minLength: 0)

                if geocodingLocationCount > 0 {
                    ProgressView()
                        .controlSize(.small)
                    Text(language.text("Placing locations", "Placerar platser"))
                        .font(appFont(.body).weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .center, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CongressMapRegionPreset.allCases) { preset in
                            Button {
                                zoom(to: preset.region)
                            } label: {
                                Text(preset.title(language: language))
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                AppSidebarSearchField(
                    placeholder: language.text("Search congresses", "Sök kongresser"),
                    text: $searchText,
                    minWidth: 160
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("Months: \(Int(visibleMonthsFrom))–\(Int(visibleMonthsAhead))", "Månader: \(Int(visibleMonthsFrom))–\(Int(visibleMonthsAhead))"))
                        .font(appFont(.body).weight(.semibold))
                        .foregroundStyle(AppPalette.appText)
                    AppRangeSlider(
                        lowerValue: visibleMonthsFromBinding,
                        upperValue: visibleMonthsAheadBinding,
                        bounds: 0...60,
                        step: 1
                    )
                }
                .frame(minWidth: 160, maxWidth: 240, alignment: .leading)
                .layoutPriority(1)

                Toggle(
                    language.text("Hide congresses with passed abstract date", "Dölj kongresser med passerad abstractfrist"),
                    isOn: $hidesPassedAbstractDeadlines
                )
                .appCheckboxStyle()
                .font(appFont(.body).weight(.medium))
                .fixedSize()

                Toggle(
                    language.text("Show congresses you participated in", "Visa kongresser du medverkat i"),
                    isOn: $showsParticipatedCongressesOnly
                )
                .appCheckboxStyle()
                .font(appFont(.body).weight(.medium))
                .fixedSize()

                Toggle(
                    language.text("Show hidden congresses", "Visa dolda kongresser"),
                    isOn: $showsHiddenCongresses
                )
                .appCheckboxStyle()
                .font(appFont(.body).weight(.medium))
                .fixedSize()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(AppPalette.cardSurface.opacity(0.72))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.text("Upcoming congresses", "Kommande kongresser"))
                    .font(appFont(.panelTitle))
                Spacer()
                Text("\(rows.count)")
                    .font(appFont(.secondary).weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if rows.isEmpty {
                AppWorkspaceEmptyStateView(
                    title: language.text("No upcoming congresses", "Inga kommande kongresser"),
                    subtitle: language.text("Add congress dates in an organization to show them here.", "Lägg till kongressdatum i en organisation för att visa dem här."),
                    kind: .congresses
                )
                .padding(18)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            congressListRow(row)
                            if row.id != rows.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }

                if !rowsWithoutCoordinates.isEmpty {
                    Divider()
                    Text(missingLocationText)
                        .font(appFont(.secondary).weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private var missingLocationText: String {
        let count = rowsWithoutCoordinates.count
        return language.text(
            "\(count) congresses need a resolved city/country before they can be placed.",
            "\(count) kongresser behöver ort/land innan de kan placeras."
        )
    }

    private var visibleMonthsFromBinding: Binding<Double> {
        Binding(
            get: { visibleMonthsFrom },
            set: { newValue in
                visibleMonthsFrom = min(newValue, visibleMonthsAhead)
            }
        )
    }

    private var visibleMonthsAheadBinding: Binding<Double> {
        Binding(
            get: { visibleMonthsAhead },
            set: { newValue in
                visibleMonthsAhead = max(newValue, visibleMonthsFrom)
            }
        )
    }

    private func congressListRow(_ row: CongressMapRow) -> some View {
        let isSelected = selectedCongressID == row.id
        return Button {
            selectedCongressID = row.id
            selectedCongressDetailPoint = fallbackCongressDetailPoint
            if let positioned = positionedRows.first(where: { $0.id == row.id }) {
                let region = MKCoordinateRegion(
                    center: positioned.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 6.5, longitudeDelta: 6.5)
                )
                zoom(to: region)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.dateText)
                        .font(appFont(.secondary).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(AppPalette.appText)
                    if row.hasUncertainDate {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    if row.isHiddenOnMap {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(row.title)
                    .font(appFont(.body).weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(AppPalette.appText)

                Text([row.placeText.nonEmpty, row.organizationName.nonEmpty].compactMap { $0 }.joined(separator: " - "))
                    .font(appFont(.secondary))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppPalette.activeTabSurface.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hoverText(for: row))
        .contextMenu {
            congressVisibilityMenuButton(for: row)
        }
    }

    private var mapContent: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                styledMap
                    .ignoresSafeArea(edges: .bottom)

                if let selectedRow {
                    let detailOrigin = selectedCongressDetailPoint ?? fallbackCongressDetailPoint
                    selectedCongressPanel(row: selectedRow)
                        .offset(
                            x: detailOrigin.x,
                            y: detailOrigin.y
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                        .zIndex(10)
                }
            }
            .animation(.easeOut(duration: 0.16), value: selectedCongressID)
            .onAppear {
                updateMapViewportSize(proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                updateMapViewportSize(newSize)
            }
        }
    }

    private var fallbackCongressDetailPoint: CGPoint {
        CGPoint(
            x: max(18, mapViewportSize.width - 378),
            y: 18
        )
    }

    private var styledMap: some View {
        rawMap
    }

    private var rawMap: some View {
        CongressMapNativeView(
            congresses: positionedRows.map {
                CongressMapNativeItem(row: $0.row, coordinate: $0.coordinate)
            },
            affiliations: positionedAffiliationAnnotations.map {
                CongressMapNativeAffiliationItem(
                    location: $0.location,
                    coordinate: $0.coordinate
                )
            },
            selectedCongressID: $selectedCongressID,
            requestedRegion: requestedMapRegion,
            regionRequestID: mapRegionRequestID,
            language: language,
            onRegionChange: { region in
                visibleMapRegion = region
            },
            visibilityAction: { row in
                setCongressMapHidden(!row.isHiddenOnMap, row: row)
            },
            selectionAction: { congressID, point in
                selectedCongressDetailPoint = point
                selectedCongressID = congressID
            },
            clearSelectionAction: {
                selectedCongressID = nil
                selectedCongressDetailPoint = nil
            }
        )
    }

    private func adaptiveMapLabelOverlay(proxy: MapProxy) -> some View {
        let labels = adaptiveMapLabels(proxy: proxy)
        return ZStack(alignment: .topLeading) {
            ForEach(labels) { label in
                if let connector = label.connector {
                    CongressMapOverlayConnector(
                        start: connector.start,
                        end: connector.end
                    )
                    .stroke(
                        AppPalette.actionSave.opacity(0.72),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .allowsHitTesting(false)
                }

                CongressMapAdaptiveCalloutLabel(
                    row: label.row,
                    language: language,
                    kind: label.plan.kind,
                    isSelected: label.plan.isSelected
                ) {
                    activateAdaptiveLabel(label)
                } visibilityAction: {
                    setCongressMapHidden(!label.row.isHiddenOnMap, row: label.row)
                }
                .position(
                    x: label.screenPoint.x + label.placement.calloutOffset.width,
                    y: label.screenPoint.y + label.placement.calloutOffset.height
                )
            }
        }
        .frame(
            width: mapViewportSize.width,
            height: mapViewportSize.height,
            alignment: .topLeading
        )
    }

    private func adaptiveMapLabels(proxy: MapProxy) -> [PositionedCongressMapAdaptiveLabel] {
        guard mapViewportSize.width > 1, mapViewportSize.height > 1 else { return [] }
        let visibleRect = CGRect(
            x: -CongressMapAnnotationMetrics.starProtectionSize,
            y: -CongressMapAnnotationMetrics.starProtectionSize,
            width: mapViewportSize.width + CongressMapAnnotationMetrics.starProtectionSize * 2,
            height: mapViewportSize.height + CongressMapAnnotationMetrics.starProtectionSize * 2
        )
        let allScreenRows = positionedRows.compactMap { positioned -> ScreenPositionedCongressMapRow? in
            guard let point = proxy.convert(positioned.coordinate, to: .local),
                  point.x.isFinite,
                  point.y.isFinite else {
                return nil
            }
            return ScreenPositionedCongressMapRow(positioned: positioned, screenPoint: point)
        }
        let visibleScreenRows = allScreenRows.filter { visibleRect.contains($0.screenPoint) }
        guard !visibleScreenRows.isEmpty else { return [] }

        let items = visibleScreenRows.map { screenRow in
            CongressMapAdaptiveLayoutItem(
                id: screenRow.positioned.id,
                point: screenRow.screenPoint,
                locationCacheKey: screenRow.positioned.row.locationCacheKey,
                city: screenRow.positioned.row.city,
                placeText: screenRow.positioned.row.placeText,
                startDate: screenRow.positioned.row.startDate,
                currentUserParticipates: screenRow.positioned.row.currentUserParticipates
            )
        }
        let plans = CongressMapAdaptiveLayout.labelPlans(
            items: items,
            selectedID: selectedCongressID,
            capacity: adaptiveLabelCapacity
        )
        let screenRowsByID = Dictionary(firstWinsKeysWithValues: visibleScreenRows.map { ($0.positioned.id, $0) })
        let labelScreenRows = plans.compactMap { screenRowsByID[$0.representativeID] }
        let placements = optimizedAnnotationPlacements(
            for: labelScreenRows,
            protectedScreenRows: allScreenRows
        )
        let plansByRepresentativeID = Dictionary(
            firstWinsKeysWithValues: plans.map { ($0.representativeID, $0) }
        )

        return labelScreenRows.compactMap { screenRow in
            guard let plan = plansByRepresentativeID[screenRow.positioned.id],
                  let placement = placements[screenRow.positioned.id] else {
                return nil
            }
            return PositionedCongressMapAdaptiveLabel(
                plan: plan,
                row: screenRow.positioned.row,
                screenPoint: screenRow.screenPoint,
                placement: placement,
                connector: placement.showsConnector
                    ? screenConnector(for: screenRow.screenPoint, offset: placement.calloutOffset)
                    : nil
            )
        }
    }

    private var adaptiveLabelCapacity: Int {
        let columns = max(
            1,
            Int(mapViewportSize.width / (CongressMapAnnotationMetrics.calloutWidth + 18))
        )
        let rows = max(
            1,
            Int(mapViewportSize.height / (CongressMapAnnotationMetrics.calloutHeight + 14))
        )
        return max(1, columns * rows)
    }

    private func activateAdaptiveLabel(_ label: PositionedCongressMapAdaptiveLabel) {
        selectedCongressID = label.row.id
        guard case .cluster = label.plan.kind else { return }
        let memberIDs = Set(label.plan.memberIDs)
        let coordinates = positionedRows
            .filter { memberIDs.contains($0.id) }
            .map(\.coordinate)
        guard !coordinates.isEmpty else { return }
        zoom(to: CongressMapModel.mapRegion(for: coordinates))
    }

    private var selectedRow: CongressMapRow? {
        guard let selectedCongressID else { return nil }
        return rows.first(where: { $0.id == selectedCongressID })
    }

    private struct AbstractDeadlineLink: Identifiable {
        let id: String
        let date: Date
        let text: String
    }

    private func selectedCongressPanel(row: CongressMapRow) -> some View {
        let accentColor = Color(NSColor.systemBlue)
        let deadlines = abstractDeadlines(for: row)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(row.title)
                            .font(appFont(.body).weight(.semibold))
                            .foregroundStyle(.black)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = normalizedWebLinkURL(row.link) {
                            Button { NSWorkspace.shared.open(url) } label: {
                                Image(systemName: "link")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(accentColor)
                            .help(language.text("Open congress website", "Öppna kongressens webbplats"))
                            .accessibilityLabel(language.text("Open congress website", "Öppna kongressens webbplats"))
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(row.dateText)
                            .font(appFont(.secondary).weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.black.opacity(0.82))
                        calendarLink(
                            for: row,
                            date: row.startDate,
                            accessibilityText: language.text("Show congress in calendar", "Visa kongress i kalender")
                        )
                    }
                }
                Spacer(minLength: 0)
                Button {
                    selectedCongressID = nil
                    selectedCongressDetailPoint = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accentColor)
            }

            Divider()

            if row.isHiddenOnMap {
                Label(language.text("Hidden on map", "Dold på kartan"), systemImage: "eye.slash")
                    .font(appFont(.secondary).weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let placeText = row.placeText.nonEmpty {
                Text(placeText)
                    .font(appFont(.body))
                    .foregroundStyle(Color.black.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !row.organizationName.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(row.organizationName)
                        .font(appFont(.body))
                        .foregroundStyle(Color.black.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        store.route = AppRoute(recordID: row.organizationID, destination: .organizations)
                    } label: {
                        Image(systemName: "building.columns")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accentColor)
                    .help(language.text("Open organization", "Öppna organisation"))
                    .accessibilityLabel(language.text("Open organization", "Öppna organisation"))
                }
            }

            if !deadlines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(deadlines.enumerated()), id: \.offset) { _, deadline in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(deadline.text)
                                .font(appFont(.secondary).weight(.medium))
                                .foregroundStyle(Color.black.opacity(0.86))
                            calendarLink(
                                for: row,
                                date: deadline.date,
                                accessibilityText: language.text("Show abstract deadline in calendar", "Visa abstractdeadline i kalender")
                            )
                        }
                    }
                }
                .padding(.top, 2)
            }

            if let timeZoneDifferenceText = timeZoneDifferenceText(for: row) {
                Text(timeZoneDifferenceText)
                    .font(appFont(.secondary).weight(.medium))
                    .foregroundStyle(Color.black.opacity(0.68))
                    .padding(.top, 2)
            }

        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(accentColor.opacity(0.95), lineWidth: 2)
        )
        .help(hoverText(for: row))
        .contextMenu {
            congressVisibilityMenuButton(for: row)
        }
    }

    private func hoverText(for row: CongressMapRow) -> String {
        [
            row.title,
            row.dateText,
            row.placeText.nonEmpty,
            row.organizationName
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    @ViewBuilder
    private func calendarLink(
        for row: CongressMapRow,
        date: Date,
        accessibilityText: String
    ) -> some View {
        Button {
            store.revealCalendarWorkspace(
                on: date,
                eventSource: .congress(organizationID: row.organizationID, congressID: row.congressID)
            )
        } label: {
            Image(systemName: "calendar")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(NSColor.systemBlue))
        .help(language.text("Show in calendar", "Visa i kalender"))
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func congressVisibilityMenuButton(for row: CongressMapRow) -> some View {
        Button {
            setCongressMapHidden(!row.isHiddenOnMap, row: row)
        } label: {
            Label(
                row.isHiddenOnMap
                    ? language.text("Show", "Visa")
                    : language.text("Hide", "Dölj"),
                systemImage: row.isHiddenOnMap ? "eye" : "eye.slash"
            )
        }
    }

    private func setCongressMapHidden(_ isHidden: Bool, row: CongressMapRow) {
        guard let organization = store.organization(id: row.organizationID) else { return }
        var congresses = organization.congresses
        guard let index = congresses.firstIndex(where: { $0.id == row.congressID }),
              congresses[index].isHiddenOnMap != isHidden else { return }

        congresses[index].isHiddenOnMap = isHidden
        let persistedCongresses = persistedOrganizationCongresses(from: congresses)
        guard persistedCongresses != organization.congresses else { return }

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
            congresses: persistedCongresses,
            projectTasks: organization.projectTasks,
            salaryCalculator: organization.salaryCalculator
        )

        if isHidden && !showsHiddenCongresses && selectedCongressID == row.id {
            selectedCongressID = nil
        }
    }

    private func abstractDeadlines(for row: CongressMapRow) -> [AbstractDeadlineLink] {
        let deadlines: [(String, String, Date?, Bool)] = [
            ("abstract", language.text("Abstract deadline", "Abstractdeadline"), row.abstractSubmissionDeadline, row.abstractSubmissionDeadlineUncertain),
            ("late-abstract", language.text("Late abstract deadline", "Sen abstractdeadline"), row.lateAbstractSubmissionDeadline, row.lateAbstractSubmissionDeadlineUncertain)
        ]
        return deadlines.compactMap { id, title, date, isUncertain in
            guard let date else { return nil }
            let dateText = CongressMapModel.compactDateRangeText(
                start: date,
                end: date,
                language: language
            )
            return AbstractDeadlineLink(
                id: id,
                date: date,
                text: "\(title): \(dateText)\(uncertainDateSuffix(isUncertain))"
            )
        }
    }

    private func uncertainDateSuffix(_ isUncertain: Bool) -> String {
        isUncertain ? " (\(language.text("uncertain date", "osäkert datum")))" : ""
    }

    private func timeZoneDifferenceText(for row: CongressMapRow) -> String? {
        guard let affiliationLocation = currentUserAffiliationLocation,
              row.locationCacheKey != nil else {
            return nil
        }
        guard let congressTimeZone = timeZone(forLocationCacheKey: row.locationCacheKey) else {
            return language.text(
                "Calculating time zone for \(row.placeText)…",
                "Beräknar tidszon för \(row.placeText)…"
            )
        }
        guard let affiliationTimeZone = timeZone(forLocationCacheKey: affiliationLocation.cacheKey) else {
            return language.text(
                "Calculating time zone difference from \(affiliationLocation.placeText)…",
                "Beräknar tidszonsskillnad mot \(affiliationLocation.placeText)…"
            )
        }

        let startDifference = timeZoneHourDifference(
            from: affiliationTimeZone,
            to: congressTimeZone,
            at: row.startDate
        )
        let endDifference = timeZoneHourDifference(
            from: affiliationTimeZone,
            to: congressTimeZone,
            at: row.endDate
        )
        let differenceText = startDifference == endDifference
            ? formattedTimeZoneDifference(startDifference)
            : "\(formattedTimeZoneDifference(startDifference))-\(formattedTimeZoneDifference(endDifference))"

        return language.text(
            "\(differenceText) compared with \(affiliationLocation.displayText)",
            "\(differenceText) jämfört med \(affiliationLocation.displayText)"
        )
    }

    private func timeZone(forLocationCacheKey cacheKey: String?) -> TimeZone? {
        guard let cacheKey,
              let identifier = resolvedCoordinates[cacheKey]?.timeZoneIdentifier else { return nil }
        return TimeZone(identifier: identifier)
    }

    private func timeZoneHourDifference(from referenceTimeZone: TimeZone, to targetTimeZone: TimeZone, at date: Date) -> Double {
        let referenceSeconds = referenceTimeZone.secondsFromGMT(for: date)
        let targetSeconds = targetTimeZone.secondsFromGMT(for: date)
        return Double(targetSeconds - referenceSeconds) / 3600
    }

    private func formattedTimeZoneDifference(_ hours: Double) -> String {
        if abs(hours) < 0.01 {
            return "0 h"
        }
        let sign = hours > 0 ? "+" : "-"
        let absoluteHours = abs(hours)
        let roundedHours = absoluteHours.rounded()
        if abs(absoluteHours - roundedHours) < 0.01 {
            return "\(sign) \(Int(roundedHours)) h"
        }
        let value = String(format: "%.1f", absoluteHours).replacingOccurrences(of: ".", with: ",")
        return "\(sign) \(value) h"
    }

    private func loadCoordinateCacheIfNeeded() {
        guard !hasLoadedCoordinateCache else { return }
        hasLoadedCoordinateCache = true
        guard let data = UserDefaults.standard.data(forKey: CongressMapCoordinate.cacheDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: CongressMapCoordinate].self, from: data) else {
            return
        }
        resolvedCoordinates.merge(decoded) { current, _ in current }
    }

    private func persistCoordinateCache() {
        guard let encoded = try? JSONEncoder().encode(resolvedCoordinates) else { return }
        UserDefaults.standard.set(encoded, forKey: CongressMapCoordinate.cacheDefaultsKey)
    }

    private func loadMapPreferences() {
        let normalizedRange = CongressMapPreferences.normalizedVisibleMonthRange(
            from: CongressMapPreferences.loadVisibleMonthsFrom(),
            through: CongressMapPreferences.loadVisibleMonthsAhead()
        )
        visibleMonthsFrom = normalizedRange.from
        visibleMonthsAhead = normalizedRange.through
        hidesPassedAbstractDeadlines = CongressMapPreferences.loadHidesPassedAbstractDeadlines()
        showsParticipatedCongressesOnly = CongressMapPreferences.loadShowsParticipatedCongressesOnly()
        showsHiddenCongresses = CongressMapPreferences.loadShowsHiddenCongresses()
    }

    private func persistMapPreferences() {
        CongressMapPreferences.save(
            visibleMonthsFrom: visibleMonthsFrom,
            visibleMonthsAhead: visibleMonthsAhead,
            hidesPassedAbstractDeadlines: hidesPassedAbstractDeadlines,
            showsParticipatedCongressesOnly: showsParticipatedCongressesOnly,
            showsHiddenCongresses: showsHiddenCongresses
        )
    }

    private func startGeocodingIfNeeded() {
        geocodingGeneration &+= 1
        let generation = geocodingGeneration
        geocodingTask?.cancel()
        let requests = uniquePendingLocationRequests()
        geocodingLocationCount = requests.count
        guard !requests.isEmpty else {
            geocodingTask = nil
            return
        }

        geocodingTask = Task {
            var resolvedSinceLastWrite = 0
            for request in requests {
                if Task.isCancelled { break }
                let coordinate = await geocodeLocation(query: request.query)
                guard !Task.isCancelled else { break }
                let didResolve = await MainActor.run {
                    guard geocodingGeneration == generation else { return false }
                    switch coordinate {
                    case let .resolved(coordinate):
                        resolvedCoordinates[request.cacheKey] = coordinate
                        failedLocationKeys.remove(request.cacheKey)
                    case .notFound:
                        failedLocationKeys.insert(request.cacheKey)
                    case .retryableFailure:
                        break
                    }
                    geocodingLocationCount = max(0, geocodingLocationCount - 1)
                    fitMapToAnnotationsIfNeeded()
                    if case .resolved = coordinate {
                        return true
                    }
                    return false
                }
                if didResolve {
                    resolvedSinceLastWrite += 1
                    if resolvedSinceLastWrite >= 10 {
                        await MainActor.run {
                            if geocodingGeneration == generation {
                                persistCoordinateCache()
                            }
                        }
                        resolvedSinceLastWrite = 0
                    }
                }
                do {
                    try await Task.sleep(nanoseconds: 180_000_000)
                } catch {
                    break
                }
            }
            if resolvedSinceLastWrite > 0 {
                await MainActor.run {
                    if geocodingGeneration == generation {
                        persistCoordinateCache()
                    }
                }
            }
            await MainActor.run {
                if geocodingGeneration == generation {
                    geocodingTask = nil
                    geocodingLocationCount = 0
                }
            }
        }
    }

    private func uniquePendingLocationRequests() -> [CongressMapLocationRequest] {
        var seen = Set<String>()
        var requests = rows.compactMap { row -> CongressMapLocationRequest? in
            guard let query = row.locationQuery,
                  let cacheKey = row.locationCacheKey,
                  needsResolvedLocation(cacheKey: cacheKey),
                  failedLocationKeys.contains(cacheKey) == false,
                  seen.insert(cacheKey).inserted else { return nil }
            return CongressMapLocationRequest(cacheKey: cacheKey, query: query)
        }
        for affiliationLocation in currentUserAffiliationLocations
            where needsResolvedLocation(cacheKey: affiliationLocation.cacheKey)
                && failedLocationKeys.contains(affiliationLocation.cacheKey) == false
                && seen.insert(affiliationLocation.cacheKey).inserted {
            requests.append(
                CongressMapLocationRequest(
                    cacheKey: affiliationLocation.cacheKey,
                    query: affiliationLocation.query
                )
            )
        }
        return requests
    }

    private func needsResolvedLocation(cacheKey: String) -> Bool {
        guard let resolved = resolvedCoordinates[cacheKey] else { return true }
        return resolved.timeZoneIdentifier == nil
    }

    private func geocodeLocation(query: String) async -> CongressMapGeocodeOutcome {
        for attempt in 0..<2 {
            guard !Task.isCancelled else { return .retryableFailure }
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.geocodeAddressString(query)
                guard let placemark = placemarks.first,
                      let coordinate = placemark.location?.coordinate else {
                    return .notFound
                }
                return .resolved(
                    CongressMapCoordinate(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        timeZoneIdentifier: placemark.timeZone?.identifier
                    )
                )
            } catch let error as CLError {
                guard !Task.isCancelled, error.code != .geocodeCanceled else {
                    return .retryableFailure
                }
                if error.code == .geocodeFoundNoResult {
                    return .notFound
                }
            } catch {
                guard !Task.isCancelled else { return .retryableFailure }
            }
            if attempt == 0 {
                do {
                    try await Task.sleep(nanoseconds: 650_000_000)
                } catch {
                    return .retryableFailure
                }
            }
        }
        return .retryableFailure
    }

    private func updateMapViewportSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1, mapViewportSize != size else { return }
        mapViewportSize = size
    }

    private func screenPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint? {
        guard mapViewportSize.width > 1,
              mapViewportSize.height > 1,
              visibleMapRegion.span.latitudeDelta > 0,
              visibleMapRegion.span.longitudeDelta > 0 else { return nil }

        let longitudeOffset = normalizedLongitudeOffset(
            from: visibleMapRegion.center.longitude,
            to: coordinate.longitude
        )
        let latitudeOffset = coordinate.latitude - visibleMapRegion.center.latitude
        return CGPoint(
            x: mapViewportSize.width * (0.5 + longitudeOffset / visibleMapRegion.span.longitudeDelta),
            y: mapViewportSize.height * (0.5 - latitudeOffset / visibleMapRegion.span.latitudeDelta)
        )
    }

    private func normalizedLongitudeOffset(from centerLongitude: CLLocationDegrees, to longitude: CLLocationDegrees) -> CLLocationDegrees {
        var offset = longitude - centerLongitude
        while offset > 180 { offset -= 360 }
        while offset < -180 { offset += 360 }
        return offset
    }

    private func sideAnnotationPlacements(
        for screenRows: [ScreenPositionedCongressMapRow]
    ) -> [String: CongressMapAnnotationPlacement] {
        var occupiedRects: [CGRect] = []
        var placements: [String: CongressMapAnnotationPlacement] = [:]
        let groups = groupedSideAnnotationRows(screenRows)
            .sorted { lhs, rhs in
                guard let left = lhs.first, let right = rhs.first else { return lhs.count > rhs.count }
                return annotationScreenRowSort(left, right)
            }

        for group in groups {
            if group.count > 1 {
                let groupPlacements = stackedSideAnnotationPlacements(
                    for: group,
                    occupiedRects: &occupiedRects
                )
                placements.merge(groupPlacements) { current, _ in current }
            } else if let screenRow = group.first {
                let placement = sideAnnotationPlacement(
                    for: screenRow.screenPoint,
                    occupiedRects: &occupiedRects
                )
                placements[screenRow.positioned.id] = placement
            }
        }

        return placements
    }

    private func groupedSideAnnotationRows(
        _ screenRows: [ScreenPositionedCongressMapRow]
    ) -> [[ScreenPositionedCongressMapRow]] {
        var groups: [[ScreenPositionedCongressMapRow]] = []
        for screenRow in screenRows.sorted(by: annotationScreenRowSort) {
            if let groupIndex = groups.firstIndex(where: { group in
                guard let representative = group.first else { return false }
                return sideAnnotationRowsShareLocation(screenRow, representative)
            }) {
                groups[groupIndex].append(screenRow)
            } else {
                groups.append([screenRow])
            }
        }
        return groups
    }

    private func sideAnnotationRowsShareLocation(
        _ lhs: ScreenPositionedCongressMapRow,
        _ rhs: ScreenPositionedCongressMapRow
    ) -> Bool {
        if let leftKey = lhs.positioned.row.locationCacheKey,
           let rightKey = rhs.positioned.row.locationCacheKey,
           leftKey == rightKey {
            return true
        }

        let lhsLocation = CLLocation(
            latitude: lhs.positioned.coordinate.latitude,
            longitude: lhs.positioned.coordinate.longitude
        )
        let rhsLocation = CLLocation(
            latitude: rhs.positioned.coordinate.latitude,
            longitude: rhs.positioned.coordinate.longitude
        )
        return lhsLocation.distance(from: rhsLocation) <= 5_000
    }

    private func stackedSideAnnotationPlacements(
        for group: [ScreenPositionedCongressMapRow],
        occupiedRects: inout [CGRect]
    ) -> [String: CongressMapAnnotationPlacement] {
        let sortedGroup = group.sorted(by: sideAnnotationStackSort)
        guard let anchor = sortedGroup.first?.screenPoint else { return [:] }
        let stackStep = CongressMapAnnotationMetrics.calloutHeight + 4
        let sideOffset = CongressMapAnnotationMetrics.calloutWidth / 2
            + CongressMapAnnotationMetrics.starProtectionSize / 2
            + 12
        let rightFirst = anchor.x < mapViewportSize.width / 2
        let sideOffsets = rightFirst ? [sideOffset, -sideOffset] : [-sideOffset, sideOffset]
        let topOffsets: [CGFloat] = [0, -42, 42, -84, 84, -126]
        let candidateStacks = topOffsets.flatMap { topOffset in
            sideOffsets.map { sideOffset in (sideOffset: sideOffset, topOffset: topOffset) }
        }

        var bestStack = candidateStacks.first ?? (sideOffset: sideOffset, topOffset: CGFloat(0))
        var bestRects: [CGRect] = []
        var bestScore = CGFloat.greatestFiniteMagnitude

        for stack in candidateStacks {
            let rects = sortedGroup.indices.map { index in
                calloutRect(
                    center: CGPoint(
                        x: anchor.x + stack.sideOffset,
                        y: anchor.y + stack.topOffset + CGFloat(index) * stackStep
                    )
                )
            }
            let offsets = sortedGroup.enumerated().map { index, screenRow in
                CGSize(
                    width: anchor.x + stack.sideOffset - screenRow.screenPoint.x,
                    height: anchor.y + stack.topOffset + CGFloat(index) * stackStep - screenRow.screenPoint.y
                )
            }
            let score = stackedSideAnnotationPlacementScore(
                rects: rects,
                offsets: offsets,
                occupiedRects: occupiedRects
            )
            if score < bestScore {
                bestScore = score
                bestStack = stack
                bestRects = rects
            }
        }

        if bestRects.isEmpty {
            bestRects = sortedGroup.indices.map { index in
                calloutRect(
                    center: CGPoint(
                        x: anchor.x + bestStack.sideOffset,
                        y: anchor.y + bestStack.topOffset + CGFloat(index) * stackStep
                    )
                )
            }
        }

        var placements: [String: CongressMapAnnotationPlacement] = [:]
        for (index, screenRow) in sortedGroup.enumerated() {
            let offset = CGSize(
                width: anchor.x + bestStack.sideOffset - screenRow.screenPoint.x,
                height: anchor.y + bestStack.topOffset + CGFloat(index) * stackStep - screenRow.screenPoint.y
            )
            placements[screenRow.positioned.id] = CongressMapAnnotationPlacement(
                calloutOffset: offset,
                showsConnector: false
            )
        }
        occupiedRects.append(contentsOf: bestRects.map { $0.insetBy(dx: -8, dy: -8) })
        return placements
    }

    private func sideAnnotationStackSort(
        _ lhs: ScreenPositionedCongressMapRow,
        _ rhs: ScreenPositionedCongressMapRow
    ) -> Bool {
        if lhs.positioned.row.startDate != rhs.positioned.row.startDate {
            return lhs.positioned.row.startDate < rhs.positioned.row.startDate
        }
        return lhs.positioned.row.title.localizedStandardCompare(rhs.positioned.row.title) == .orderedAscending
    }

    private func stackedSideAnnotationPlacementScore(
        rects: [CGRect],
        offsets: [CGSize],
        occupiedRects: [CGRect]
    ) -> CGFloat {
        var score = CGFloat(0)
        for (rect, offset) in zip(rects, offsets) {
            score += sideAnnotationPlacementScore(
                rect: rect,
                offset: offset,
                occupiedRects: occupiedRects
            )
        }
        return score
    }

    private func sideAnnotationPlacement(
        for screenPoint: CGPoint,
        occupiedRects: inout [CGRect]
    ) -> CongressMapAnnotationPlacement {
        let sideOffset = CongressMapAnnotationMetrics.calloutWidth / 2
            + CongressMapAnnotationMetrics.starProtectionSize / 2
            + 12
        let verticalOffsets: [CGFloat] = [0, -42, 42, -84, 84]
        let rightFirst = screenPoint.x < mapViewportSize.width / 2
        let sideOffsets = rightFirst ? [sideOffset, -sideOffset] : [-sideOffset, sideOffset]
        let offsets = verticalOffsets.flatMap { y in
            sideOffsets.map { x in CGSize(width: x, height: y) }
        }

        var bestOffset = offsets.first ?? CGSize(width: sideOffset, height: 0)
        var bestRect = calloutRect(
            center: CGPoint(
                x: screenPoint.x + bestOffset.width,
                y: screenPoint.y + bestOffset.height
            )
        )
        var bestScore = CGFloat.greatestFiniteMagnitude

        for offset in offsets {
            let rect = calloutRect(
                center: CGPoint(
                    x: screenPoint.x + offset.width,
                    y: screenPoint.y + offset.height
                )
            )
            let score = sideAnnotationPlacementScore(
                rect: rect,
                offset: offset,
                occupiedRects: occupiedRects
            )
            if score < bestScore {
                bestScore = score
                bestOffset = offset
                bestRect = rect
            }
        }

        occupiedRects.append(bestRect.insetBy(dx: -8, dy: -8))
        return CongressMapAnnotationPlacement(
            calloutOffset: bestOffset,
            showsConnector: false
        )
    }

    private func sideAnnotationPlacementScore(
        rect: CGRect,
        offset: CGSize,
        occupiedRects: [CGRect]
    ) -> CGFloat {
        let overlapPenalty = occupiedRects.reduce(CGFloat(0)) { partialResult, occupiedRect in
            guard rect.intersects(occupiedRect) else { return partialResult }
            let intersection = rect.intersection(occupiedRect)
            guard !intersection.isNull else { return partialResult }
            return partialResult + 6_000 + intersection.width * intersection.height
        }
        let viewportInset: CGFloat = 10
        let outOfBoundsPenalty =
            max(0, viewportInset - rect.minX)
            + max(0, viewportInset - rect.minY)
            + max(0, rect.maxX - (mapViewportSize.width - viewportInset))
            + max(0, rect.maxY - (mapViewportSize.height - viewportInset))
        let distancePenalty = abs(offset.height) * 3 + abs(offset.width) * 0.01
        return overlapPenalty + outOfBoundsPenalty * 800 + distancePenalty
    }

    private func optimizedAnnotationPlacements(
        for screenRows: [ScreenPositionedCongressMapRow],
        protectedScreenRows: [ScreenPositionedCongressMapRow]
    ) -> [String: CongressMapAnnotationPlacement] {
        guard mapViewportSize.width > 1,
              mapViewportSize.height > 1,
              screenRows.isEmpty == false else {
            return [:]
        }

        let viewportRect = CGRect(
            x: 10,
            y: 10,
            width: mapViewportSize.width - 20,
            height: mapViewportSize.height - 20
        )
        let activeRect = viewportRect.insetBy(dx: -120, dy: -120)
        let activeRows = screenRows.filter { activeRect.contains($0.screenPoint) }
        let layoutRows = activeRows.isEmpty ? screenRows : activeRows
        let starObstacles = protectedScreenRows.map { screenRow in
            CongressMapStarObstacle(
                id: screenRow.positioned.id,
                rect: starProtectionRect(center: screenRow.screenPoint).insetBy(dx: -6, dy: -6)
            )
        }
        let gridCenters = annotationGridCenters(in: viewportRect)
        let candidateLists = layoutRows.reduce(into: [String: [CongressMapAnnotationCandidate]]()) { result, screenRow in
            let candidates = annotationCandidates(
                for: screenRow,
                viewportRect: viewportRect,
                starObstacles: starObstacles,
                gridCenters: gridCenters
            )
            result[screenRow.positioned.id] = candidates
        }

        return greedyAnnotationLayout(
            orderedRows: layoutRows,
            candidateLists: candidateLists
        )
        .placements
    }

    private func annotationGridCenters(in viewportRect: CGRect) -> [CGPoint] {
        let halfWidth = CongressMapAnnotationMetrics.calloutWidth / 2
        let halfHeight = CongressMapAnnotationMetrics.calloutHeight / 2
        let stepX = CongressMapAnnotationMetrics.calloutWidth + 14
        let stepY = CongressMapAnnotationMetrics.calloutHeight + 12
        let minX = viewportRect.minX + halfWidth
        let maxX = viewportRect.maxX - halfWidth
        let minY = viewportRect.minY + halfHeight
        let maxY = viewportRect.maxY - halfHeight
        guard maxX >= minX, maxY >= minY else { return [] }

        var xPositions: [CGFloat] = []
        var x = minX
        while x <= maxX + 0.5 {
            xPositions.append(x)
            x += stepX
        }
        if let last = xPositions.last, maxX - last > stepX * 0.35 {
            xPositions.append(maxX)
        }

        var yPositions: [CGFloat] = []
        var y = minY
        while y <= maxY + 0.5 {
            yPositions.append(y)
            y += stepY
        }
        if let last = yPositions.last, maxY - last > stepY * 0.35 {
            yPositions.append(maxY)
        }

        return yPositions.flatMap { y in
            xPositions.map { x in CGPoint(x: x, y: y) }
        }
    }

    private func annotationCandidates(
        for screenRow: ScreenPositionedCongressMapRow,
        viewportRect: CGRect,
        starObstacles: [CongressMapStarObstacle],
        gridCenters: [CGPoint]
    ) -> [CongressMapAnnotationCandidate] {
        let localCenters = localAnnotationCandidateCenters(for: screenRow.screenPoint)
        let centers = uniqueAnnotationCenters(localCenters + gridCenters)
        let candidates = centers.compactMap { center -> CongressMapAnnotationCandidate? in
            let rect = calloutRect(center: center)
            guard viewportRect.contains(rect) else { return nil }
            guard starObstacles.contains(where: { rect.intersects($0.rect) }) == false else { return nil }

            let offset = CGSize(
                width: center.x - screenRow.screenPoint.x,
                height: center.y - screenRow.screenPoint.y
            )
            let connector = screenConnector(for: screenRow.screenPoint, offset: offset)
            if let connector {
                let crossesStar = starObstacles.contains { obstacle in
                    obstacle.id != screenRow.positioned.id
                        && lineSegmentIntersectsRect(
                            start: connector.start,
                            end: connector.end,
                            rect: obstacle.rect
                        )
                }
                guard crossesStar == false else { return nil }
            }

            let lineLength = connector?.length ?? 0
            return CongressMapAnnotationCandidate(
                offset: offset,
                rect: rect,
                connector: connector,
                lineLength: lineLength,
                baseScore: lineLength + hypot(offset.width, offset.height) * 0.015
            )
        }

        let sortedCandidates = candidates.sorted {
            if abs($0.baseScore - $1.baseScore) > 0.5 {
                return $0.baseScore < $1.baseScore
            }
            return $0.rect.minY < $1.rect.minY
        }
        if sortedCandidates.isEmpty {
            return []
        }
        return Array(sortedCandidates.prefix(90))
    }

    private func localAnnotationCandidateCenters(for screenPoint: CGPoint) -> [CGPoint] {
        let halfWidth = CongressMapAnnotationMetrics.calloutWidth / 2
        let halfHeight = CongressMapAnnotationMetrics.calloutHeight / 2
        let baseX = halfWidth + CongressMapAnnotationMetrics.starProtectionSize / 2 + 18
        let baseY = halfHeight + CongressMapAnnotationMetrics.starProtectionSize / 2 + 18
        var centers = [
            CGPoint(
                x: screenPoint.x + CongressMapAnnotationPlacement.defaultOffset.width,
                y: screenPoint.y + CongressMapAnnotationPlacement.defaultOffset.height
            )
        ]

        for ring in 0..<4 {
            let x = baseX + CGFloat(ring) * (CongressMapAnnotationMetrics.calloutWidth * 0.46)
            let y = baseY + CGFloat(ring) * (CongressMapAnnotationMetrics.calloutHeight * 0.76)
            centers += [
                CGPoint(x: screenPoint.x, y: screenPoint.y - y),
                CGPoint(x: screenPoint.x, y: screenPoint.y + y),
                CGPoint(x: screenPoint.x - x, y: screenPoint.y),
                CGPoint(x: screenPoint.x + x, y: screenPoint.y),
                CGPoint(x: screenPoint.x - x, y: screenPoint.y - y),
                CGPoint(x: screenPoint.x + x, y: screenPoint.y - y),
                CGPoint(x: screenPoint.x - x, y: screenPoint.y + y),
                CGPoint(x: screenPoint.x + x, y: screenPoint.y + y)
            ]
        }

        return centers
    }

    private func uniqueAnnotationCenters(_ centers: [CGPoint]) -> [CGPoint] {
        centers.reduce(into: [CGPoint]()) { result, center in
            guard result.contains(where: { abs($0.x - center.x) < 1 && abs($0.y - center.y) < 1 }) == false else {
                return
            }
            result.append(center)
        }
    }

    private func optimizedAnnotationOrders(
        for screenRows: [ScreenPositionedCongressMapRow],
        candidateLists: [String: [CongressMapAnnotationCandidate]]
    ) -> [[ScreenPositionedCongressMapRow]] {
        let fewestCandidates = screenRows.sorted {
            let leftCount = candidateLists[$0.positioned.id]?.count ?? 0
            let rightCount = candidateLists[$1.positioned.id]?.count ?? 0
            if leftCount != rightCount {
                return leftCount < rightCount
            }
            return annotationScreenRowSort($0, $1)
        }
        let highestDensity = screenRows.sorted {
            let leftDensity = nearbyAnnotationCount(for: $0.screenPoint, in: screenRows)
            let rightDensity = nearbyAnnotationCount(for: $1.screenPoint, in: screenRows)
            if leftDensity != rightDensity {
                return leftDensity > rightDensity
            }
            return annotationScreenRowSort($0, $1)
        }
        let topToBottom = screenRows.sorted(by: annotationScreenRowSort)
        let bottomToTop = topToBottom.reversed()
        let leftToRight = screenRows.sorted {
            if abs($0.screenPoint.x - $1.screenPoint.x) > 1 {
                return $0.screenPoint.x < $1.screenPoint.x
            }
            return annotationScreenRowSort($0, $1)
        }
        let rightToLeft = leftToRight.reversed()
        return [
            Array(fewestCandidates),
            Array(highestDensity),
            Array(topToBottom),
            Array(bottomToTop),
            Array(leftToRight),
            Array(rightToLeft)
        ]
    }

    private func nearbyAnnotationCount(
        for screenPoint: CGPoint,
        in screenRows: [ScreenPositionedCongressMapRow]
    ) -> Int {
        screenRows.filter { other in
            other.screenPoint != screenPoint
                && abs(other.screenPoint.x - screenPoint.x) < CongressMapAnnotationMetrics.calloutWidth
                && abs(other.screenPoint.y - screenPoint.y) < CongressMapAnnotationMetrics.calloutHeight * 2.4
        }
        .count
    }

    private func greedyAnnotationLayout(
        orderedRows: [ScreenPositionedCongressMapRow],
        candidateLists: [String: [CongressMapAnnotationCandidate]]
    ) -> CongressMapAnnotationLayoutSolution {
        var placed: [CongressMapPlacedAnnotation] = []
        var placements: [String: CongressMapAnnotationPlacement] = [:]
        var totalLineLength: CGFloat = 0

        for screenRow in orderedRows {
            let candidates = candidateLists[screenRow.positioned.id] ?? []
            let compatibleCandidates = candidates.filter { candidate in
                annotationCandidate(candidate, isCompatibleWith: placed)
            }
            guard let chosenCandidate = compatibleCandidates.min(by: { $0.baseScore < $1.baseScore }) else {
                continue
            }

            placed.append(
                CongressMapPlacedAnnotation(
                    id: screenRow.positioned.id,
                    candidate: chosenCandidate
                )
            )
            placements[screenRow.positioned.id] = CongressMapAnnotationPlacement(
                calloutOffset: chosenCandidate.offset,
                showsConnector: chosenCandidate.connector != nil
            )
            totalLineLength += chosenCandidate.lineLength
        }

        return CongressMapAnnotationLayoutSolution(
            placements: placements,
            score: totalLineLength
        )
    }

    private func annotationCandidate(
        _ candidate: CongressMapAnnotationCandidate,
        isCompatibleWith placedAnnotations: [CongressMapPlacedAnnotation]
    ) -> Bool {
        annotationConflictPenalty(for: candidate, against: placedAnnotations) < 0.5
    }

    private func annotationConflictPenalty(
        for candidate: CongressMapAnnotationCandidate,
        against placedAnnotations: [CongressMapPlacedAnnotation]
    ) -> CGFloat {
        placedAnnotations.reduce(CGFloat(0)) { penalty, placed in
            let placedCandidate = placed.candidate
            let rectOverlap = candidate.rect
                .insetBy(dx: -8, dy: -8)
                .intersects(placedCandidate.rect.insetBy(dx: -8, dy: -8))
            let connectorOnPlacedRect = candidate.connector.map { connector in
                lineSegmentIntersectsRect(
                    start: connector.start,
                    end: connector.end,
                    rect: placedCandidate.rect.insetBy(dx: -8, dy: -8)
                )
            } ?? false
            let placedConnectorOnCandidateRect = placedCandidate.connector.map { connector in
                lineSegmentIntersectsRect(
                    start: connector.start,
                    end: connector.end,
                    rect: candidate.rect.insetBy(dx: -8, dy: -8)
                )
            } ?? false
            let connectorOverlap: Bool
            if let connector = candidate.connector,
               let placedConnector = placedCandidate.connector {
                connectorOverlap = lineSegmentsIntersect(
                    connector.start,
                    connector.end,
                    placedConnector.start,
                    placedConnector.end
                )
            } else {
                connectorOverlap = false
            }

            return penalty
                + (rectOverlap ? 1_500_000 : 0)
                + (connectorOnPlacedRect ? 1_000_000 : 0)
                + (placedConnectorOnCandidateRect ? 1_000_000 : 0)
                + (connectorOverlap ? 300_000 : 0)
        }
    }

    private func columnarAnnotationPlacements(
        for screenRows: [ScreenPositionedCongressMapRow]
    ) -> [String: CongressMapAnnotationPlacement] {
        guard mapViewportSize.width > 1,
              mapViewportSize.height > 1,
              screenRows.isEmpty == false else {
            return [:]
        }

        let visibleRect = CGRect(
            x: -CongressMapAnnotationMetrics.calloutWidth,
            y: -CongressMapAnnotationMetrics.calloutHeight,
            width: mapViewportSize.width + CongressMapAnnotationMetrics.calloutWidth * 2,
            height: mapViewportSize.height + CongressMapAnnotationMetrics.calloutHeight * 2
        )
        let visibleRows = screenRows.filter { visibleRect.contains($0.screenPoint) }
        let layoutRows = visibleRows.isEmpty ? screenRows : visibleRows
        let clusterBounds = bounds(for: layoutRows.map(\.screenPoint))
            .insetBy(dx: -44, dy: -44)
            .standardized

        let verticalInset: CGFloat = 18
        let minY = CongressMapAnnotationMetrics.calloutHeight / 2 + verticalInset
        let maxY = mapViewportSize.height - CongressMapAnnotationMetrics.calloutHeight / 2 - verticalInset
        guard maxY > minY else {
            return screenRows.reduce(into: [String: CongressMapAnnotationPlacement]()) { result, screenRow in
                result[screenRow.positioned.id] = .defaultPlacement
            }
        }

        let rowStep = CongressMapAnnotationMetrics.calloutHeight + 12
        let columnCapacity = Swift.max(1, Int(floor((maxY - minY + 12) / rowStep)))
        let columns = annotationColumnCenters(clusterBounds: clusterBounds)
        var leftRows: [ScreenPositionedCongressMapRow] = []
        var rightRows: [ScreenPositionedCongressMapRow] = []
        let leftCapacity = columnCapacity * columns.left.count
        let rightCapacity = columnCapacity * columns.right.count

        for screenRow in layoutRows.sorted(by: annotationScreenRowSort) {
            let prefersLeft = screenRow.screenPoint.x <= clusterBounds.midX
            if prefersLeft {
                if leftRows.count < leftCapacity || rightRows.count >= rightCapacity {
                    leftRows.append(screenRow)
                } else {
                    rightRows.append(screenRow)
                }
            } else if rightRows.count < rightCapacity || leftRows.count >= leftCapacity {
                rightRows.append(screenRow)
            } else {
                leftRows.append(screenRow)
            }
        }

        var placements: [String: CongressMapAnnotationPlacement] = [:]
        applyColumnarPlacements(
            rows: leftRows,
            columnXs: columns.left,
            minY: minY,
            maxY: maxY,
            columnCapacity: columnCapacity,
            placements: &placements
        )
        applyColumnarPlacements(
            rows: rightRows,
            columnXs: columns.right,
            minY: minY,
            maxY: maxY,
            columnCapacity: columnCapacity,
            placements: &placements
        )

        for screenRow in screenRows where placements[screenRow.positioned.id] == nil {
            placements[screenRow.positioned.id] = .defaultPlacement
        }
        return placements
    }

    private func annotationColumnCenters(
        clusterBounds: CGRect
    ) -> (left: [CGFloat], right: [CGFloat]) {
        let calloutWidth = CongressMapAnnotationMetrics.calloutWidth
        let horizontalInset: CGFloat = 18
        let minX = calloutWidth / 2 + horizontalInset
        let maxX = mapViewportSize.width - calloutWidth / 2 - horizontalInset
        guard maxX > minX else {
            let center = mapViewportSize.width / 2
            return ([center], [center])
        }

        let step = calloutWidth + 16
        var allXs: [CGFloat] = []
        var x = minX
        while x <= maxX + 0.5 {
            allXs.append(x)
            x += step
        }
        if let last = allXs.last, maxX - last > step * 0.35 {
            allXs.append(maxX)
        }

        let splitX = clamped(clusterBounds.midX, lowerBound: minX, upperBound: maxX)
        var left = allXs.filter { $0 <= splitX }.sorted(by: >)
        var right = allXs.filter { $0 > splitX }.sorted()
        if left.isEmpty {
            left = [minX]
        }
        if right.isEmpty {
            right = [maxX]
        }
        return (left, right)
    }

    private func applyColumnarPlacements(
        rows: [ScreenPositionedCongressMapRow],
        columnXs: [CGFloat],
        minY: CGFloat,
        maxY: CGFloat,
        columnCapacity: Int,
        placements: inout [String: CongressMapAnnotationPlacement]
    ) {
        guard rows.isEmpty == false, columnXs.isEmpty == false else { return }
        let sortedRows = rows.sorted(by: annotationScreenRowSort)
        var startIndex = 0
        var columnIndex = 0

        while startIndex < sortedRows.count {
            let endIndex = Swift.min(startIndex + columnCapacity, sortedRows.count)
            let chunkRows = Array(sortedRows[startIndex..<endIndex])
            let x = columnXs[Swift.min(columnIndex, columnXs.count - 1)]
            let yCenters = stackedAnnotationYCenters(
                desiredCenters: chunkRows.map { $0.screenPoint.y },
                minY: minY,
                maxY: maxY
            )

            for (screenRow, y) in zip(chunkRows, yCenters) {
                let offset = CGSize(
                    width: x - screenRow.screenPoint.x,
                    height: y - screenRow.screenPoint.y
                )
                placements[screenRow.positioned.id] = CongressMapAnnotationPlacement(
                    calloutOffset: offset,
                    showsConnector: true
                )
            }

            startIndex = endIndex
            columnIndex += 1
        }
    }

    private func stackedAnnotationYCenters(
        desiredCenters: [CGFloat],
        minY: CGFloat,
        maxY: CGFloat
    ) -> [CGFloat] {
        guard desiredCenters.isEmpty == false else { return [] }
        let step = CongressMapAnnotationMetrics.calloutHeight + 12
        var centers = desiredCenters.map { clamped($0, lowerBound: minY, upperBound: maxY) }

        for index in centers.indices.dropFirst() {
            centers[index] = Swift.max(centers[index], centers[index - 1] + step)
        }

        if let last = centers.last, last > maxY {
            let shift = last - maxY
            centers = centers.map { $0 - shift }
        }

        if centers.count > 1 {
            for index in stride(from: centers.count - 2, through: 0, by: -1) {
                centers[index] = Swift.min(centers[index], centers[index + 1] - step)
            }
        }

        if let first = centers.first, first < minY {
            let shift = minY - first
            centers = centers.map { $0 + shift }
        }

        return centers
    }

    private func annotationScreenRowSort(
        _ lhs: ScreenPositionedCongressMapRow,
        _ rhs: ScreenPositionedCongressMapRow
    ) -> Bool {
        if abs(lhs.screenPoint.y - rhs.screenPoint.y) > 1 {
            return lhs.screenPoint.y < rhs.screenPoint.y
        }
        return lhs.positioned.row.title.localizedStandardCompare(rhs.positioned.row.title) == .orderedAscending
    }

    private func annotationPlacement(
        for screenPoint: CGPoint,
        clusterBounds: CGRect,
        protectedStarRects: [CGRect],
        occupiedCalloutRects: inout [CGRect],
        occupiedConnectors: inout [CongressMapScreenConnector]
    ) -> CongressMapAnnotationPlacement {
        let candidates = annotationCandidateOffsets(
            for: screenPoint,
            clusterBounds: clusterBounds
        )
        var bestOffset = candidates.first ?? CongressMapAnnotationPlacement.defaultOffset
        var bestRect = calloutRect(center: CGPoint(x: screenPoint.x + bestOffset.width, y: screenPoint.y + bestOffset.height))
        var bestConnector = screenConnector(for: screenPoint, offset: bestOffset)
        var bestScore = CGFloat.greatestFiniteMagnitude

        for offset in candidates {
            let rect = calloutRect(center: CGPoint(x: screenPoint.x + offset.width, y: screenPoint.y + offset.height))
            let connector = screenConnector(for: screenPoint, offset: offset)
            let score = annotationPlacementScore(
                screenPoint: screenPoint,
                rect: rect,
                offset: offset,
                connector: connector,
                protectedStarRects: protectedStarRects,
                occupiedCalloutRects: occupiedCalloutRects,
                occupiedConnectors: occupiedConnectors
            )
            if score < bestScore {
                bestScore = score
                bestOffset = offset
                bestRect = rect
                bestConnector = connector
                if score < 0.01 {
                    break
                }
            }
        }

        occupiedCalloutRects.append(bestRect.insetBy(dx: -10, dy: -10))
        if let bestConnector {
            occupiedConnectors.append(bestConnector)
        }
        return CongressMapAnnotationPlacement(
            calloutOffset: bestOffset,
            showsConnector: bestOffset != CongressMapAnnotationPlacement.defaultOffset
        )
    }

    private func nearbyAnnotationClusterBounds(
        for screenPoint: CGPoint,
        in screenRows: [ScreenPositionedCongressMapRow]
    ) -> CGRect {
        guard let startIndex = screenRows.firstIndex(where: { $0.screenPoint == screenPoint }) else {
            return CGRect(x: screenPoint.x, y: screenPoint.y, width: 1, height: 1)
                .insetBy(dx: -28, dy: -28)
        }

        var visitedIndexes: Set<Int> = [startIndex]
        var queue = [startIndex]

        while let currentIndex = queue.first {
            queue.removeFirst()
            for index in screenRows.indices where !visitedIndexes.contains(index) {
                if annotationPointsBelongToSameCluster(
                    screenRows[currentIndex].screenPoint,
                    screenRows[index].screenPoint
                ) {
                    visitedIndexes.insert(index)
                    queue.append(index)
                }
            }
        }

        let points = visitedIndexes.map { screenRows[$0].screenPoint }
        return bounds(for: points).insetBy(dx: -28, dy: -28)
    }

    private func annotationPointsBelongToSameCluster(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        let dx = abs(lhs.x - rhs.x)
        let dy = abs(lhs.y - rhs.y)
        if dx <= CongressMapAnnotationMetrics.calloutWidth * 0.95,
           dy <= CongressMapAnnotationMetrics.calloutHeight * 2.2 {
            return true
        }

        let lhsDefaultRect = calloutRect(
            center: CGPoint(
                x: lhs.x + CongressMapAnnotationPlacement.defaultOffset.width,
                y: lhs.y + CongressMapAnnotationPlacement.defaultOffset.height
            )
        )
        .insetBy(dx: -18, dy: -18)
        let rhsDefaultRect = calloutRect(
            center: CGPoint(
                x: rhs.x + CongressMapAnnotationPlacement.defaultOffset.width,
                y: rhs.y + CongressMapAnnotationPlacement.defaultOffset.height
            )
        )
        .insetBy(dx: -18, dy: -18)
        return lhsDefaultRect.intersects(rhsDefaultRect)
    }

    private func bounds(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        let minX = points.reduce(first.x) { min($0, $1.x) }
        let maxX = points.reduce(first.x) { max($0, $1.x) }
        let minY = points.reduce(first.y) { min($0, $1.y) }
        let maxY = points.reduce(first.y) { max($0, $1.y) }
        return CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
    }

    private func annotationCandidateOffsets(
        for screenPoint: CGPoint,
        clusterBounds: CGRect
    ) -> [CGSize] {
        let calloutWidth = CongressMapAnnotationMetrics.calloutWidth
        let calloutHeight = CongressMapAnnotationMetrics.calloutHeight
        let laneGap: CGFloat = 12
        let edgeGap: CGFloat = 18
        let horizontalStep = calloutWidth + laneGap
        let verticalStep = calloutHeight + laneGap
        let cluster = clusterBounds.standardized

        var centers = [
            CGPoint(
                x: screenPoint.x + CongressMapAnnotationPlacement.defaultOffset.width,
                y: screenPoint.y + CongressMapAnnotationPlacement.defaultOffset.height
            )
        ]

        let horizontalCenters = expandedLanePositions(
            base: distributedLanePositions(
                lowerBound: cluster.minX,
                upperBound: cluster.maxX,
                step: horizontalStep,
                fallback: cluster.midX
            ),
            fallback: cluster.midX,
            step: horizontalStep,
            shouldExpand: cluster.width < horizontalStep
        )
        let anchoredHorizontalCenters = uniqueLanePositions(
            horizontalCenters + [clamped(screenPoint.x, lowerBound: cluster.minX, upperBound: cluster.maxX)]
        )

        let verticalCenters = expandedLanePositions(
            base: distributedLanePositions(
                lowerBound: cluster.minY,
                upperBound: cluster.maxY,
                step: verticalStep,
                fallback: cluster.midY
            ),
            fallback: cluster.midY,
            step: verticalStep,
            shouldExpand: cluster.height < verticalStep
        )
        let anchoredVerticalCenters = uniqueLanePositions(
            verticalCenters + [clamped(screenPoint.y, lowerBound: cluster.minY, upperBound: cluster.maxY)]
        )

        let topBaseY = cluster.minY - edgeGap - calloutHeight / 2
        let bottomBaseY = cluster.maxY + edgeGap + calloutHeight / 2
        for row in 0..<3 {
            let rowOffset = CGFloat(row) * verticalStep
            for x in anchoredHorizontalCenters {
                centers.append(CGPoint(x: x, y: topBaseY - rowOffset))
                centers.append(CGPoint(x: x, y: bottomBaseY + rowOffset))
            }
        }

        let leftX = cluster.minX - edgeGap - calloutWidth / 2
        let rightX = cluster.maxX + edgeGap + calloutWidth / 2
        for y in anchoredVerticalCenters {
            centers.append(CGPoint(x: leftX, y: y))
            centers.append(CGPoint(x: rightX, y: y))
        }

        let uniqueCenters = centers.reduce(into: [CGPoint]()) { result, center in
            guard result.contains(where: { abs($0.x - center.x) < 1 && abs($0.y - center.y) < 1 }) == false else {
                return
            }
            result.append(center)
        }

        let offsets = uniqueCenters.map { center in
            CGSize(width: center.x - screenPoint.x, height: center.y - screenPoint.y)
        }
        let defaultOffset = CongressMapAnnotationPlacement.defaultOffset
        let rest = offsets
            .filter { abs($0.width - defaultOffset.width) >= 1 || abs($0.height - defaultOffset.height) >= 1 }
            .sorted {
                hypot($0.width, $0.height) < hypot($1.width, $1.height)
            }
        return [defaultOffset] + rest
    }

    private func distributedLanePositions(
        lowerBound: CGFloat,
        upperBound: CGFloat,
        step: CGFloat,
        fallback: CGFloat
    ) -> [CGFloat] {
        let span = upperBound - lowerBound
        guard span >= step else { return [fallback] }
        let count = Swift.min(6, Swift.max(2, Int(floor(span / step)) + 1))
        guard count > 1 else { return [fallback] }
        return (0..<count).map { index in
            lowerBound + CGFloat(index) * span / CGFloat(count - 1)
        }
    }

    private func expandedLanePositions(
        base: [CGFloat],
        fallback: CGFloat,
        step: CGFloat,
        shouldExpand: Bool
    ) -> [CGFloat] {
        guard shouldExpand else { return base }
        return [fallback, fallback - step, fallback + step]
    }

    private func uniqueLanePositions(_ positions: [CGFloat]) -> [CGFloat] {
        positions.sorted().reduce(into: [CGFloat]()) { result, position in
            guard result.contains(where: { abs($0 - position) < 1 }) == false else { return }
            result.append(position)
        }
    }

    private func clamped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }

    private func screenConnector(
        for screenPoint: CGPoint,
        offset: CGSize
    ) -> CongressMapScreenConnector? {
        guard offset != CongressMapAnnotationPlacement.defaultOffset else { return nil }
        let placement = CongressMapAnnotationPlacement(calloutOffset: offset, showsConnector: true)
        let endpoint = placement.connectorEndpoint
        let length = hypot(endpoint.width, endpoint.height)
        guard length > 1 else { return nil }
        let unitX = endpoint.width / length
        let unitY = endpoint.height / length
        return CongressMapScreenConnector(
            start: CGPoint(x: screenPoint.x + endpoint.width, y: screenPoint.y + endpoint.height),
            end: CGPoint(
                x: screenPoint.x + unitX * CongressMapAnnotationMetrics.starRadius,
                y: screenPoint.y + unitY * CongressMapAnnotationMetrics.starRadius
            )
        )
    }

    private func annotationPlacementScore(
        screenPoint: CGPoint,
        rect: CGRect,
        offset: CGSize,
        connector: CongressMapScreenConnector?,
        protectedStarRects: [CGRect],
        occupiedCalloutRects: [CGRect],
        occupiedConnectors: [CongressMapScreenConnector]
    ) -> CGFloat {
        let occupiedRects = protectedStarRects + occupiedCalloutRects
        let overlapPenalty = occupiedRects.reduce(CGFloat(0)) { partialResult, occupiedRect in
            guard rect.intersects(occupiedRect) else { return partialResult }
            let intersection = rect.intersection(occupiedRect)
            guard !intersection.isNull else { return partialResult }
            return partialResult + 35_000 + intersection.width * intersection.height * 1.4
        }
        let connectorPenalty = connector.map { connector in
            connectorCollisionPenalty(
                connector,
                screenPoint: screenPoint,
                protectedStarRects: protectedStarRects,
                occupiedCalloutRects: occupiedCalloutRects,
                occupiedConnectors: occupiedConnectors
            )
        } ?? 0
        let existingConnectorCoveredPenalty = occupiedConnectors.reduce(CGFloat(0)) { partialResult, occupiedConnector in
            lineSegmentIntersectsRect(
                start: occupiedConnector.start,
                end: occupiedConnector.end,
                rect: rect.insetBy(dx: -8, dy: -8)
            )
            ? partialResult + 70_000
            : partialResult
        }
        let viewportInset: CGFloat = 12
        let outOfBoundsPenalty =
            max(0, viewportInset - rect.minX)
            + max(0, viewportInset - rect.minY)
            + max(0, rect.maxX - (mapViewportSize.width - viewportInset))
            + max(0, rect.maxY - (mapViewportSize.height - viewportInset))
        let distancePenalty = hypot(offset.width, offset.height) * 0.02
        return overlapPenalty
            + connectorPenalty
            + existingConnectorCoveredPenalty
            + outOfBoundsPenalty * 90
            + distancePenalty
    }

    private func connectorCollisionPenalty(
        _ connector: CongressMapScreenConnector,
        screenPoint: CGPoint,
        protectedStarRects: [CGRect],
        occupiedCalloutRects: [CGRect],
        occupiedConnectors: [CongressMapScreenConnector]
    ) -> CGFloat {
        let calloutPenalty = occupiedCalloutRects.reduce(CGFloat(0)) { partialResult, occupiedRect in
            lineSegmentIntersectsRect(
                start: connector.start,
                end: connector.end,
                rect: occupiedRect.insetBy(dx: -8, dy: -8)
            )
            ? partialResult + 90_000
            : partialResult
        }
        let starPenalty = protectedStarRects.reduce(CGFloat(0)) { partialResult, starRect in
            guard starRect.contains(screenPoint) == false else { return partialResult }
            return lineSegmentIntersectsRect(
                start: connector.start,
                end: connector.end,
                rect: starRect.insetBy(dx: -5, dy: -5)
            )
            ? partialResult + 8_000
            : partialResult
        }
        let connectorCrossingPenalty = occupiedConnectors.reduce(CGFloat(0)) { partialResult, occupiedConnector in
            lineSegmentsIntersect(
                connector.start,
                connector.end,
                occupiedConnector.start,
                occupiedConnector.end
            )
            ? partialResult + 12_000
            : partialResult
        }
        return calloutPenalty + starPenalty + connectorCrossingPenalty
    }

    private func lineSegmentIntersectsRect(start: CGPoint, end: CGPoint, rect: CGRect) -> Bool {
        let rect = rect.standardized
        if rect.contains(start) || rect.contains(end) {
            return true
        }
        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        return lineSegmentsIntersect(start, end, topLeft, topRight)
            || lineSegmentsIntersect(start, end, topRight, bottomRight)
            || lineSegmentsIntersect(start, end, bottomRight, bottomLeft)
            || lineSegmentsIntersect(start, end, bottomLeft, topLeft)
    }

    private func lineSegmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ q1: CGPoint, _ q2: CGPoint) -> Bool {
        let d1 = direction(q1, q2, p1)
        let d2 = direction(q1, q2, p2)
        let d3 = direction(p1, p2, q1)
        let d4 = direction(p1, p2, q2)

        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)),
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }

        return isApproximatelyZero(d1) && point(p1, liesOnSegmentFrom: q1, to: q2)
            || isApproximatelyZero(d2) && point(p2, liesOnSegmentFrom: q1, to: q2)
            || isApproximatelyZero(d3) && point(q1, liesOnSegmentFrom: p1, to: p2)
            || isApproximatelyZero(d4) && point(q2, liesOnSegmentFrom: p1, to: p2)
    }

    private func direction(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)
    }

    private func isApproximatelyZero(_ value: CGFloat) -> Bool {
        abs(value) < 0.001
    }

    private func point(_ point: CGPoint, liesOnSegmentFrom start: CGPoint, to end: CGPoint) -> Bool {
        point.x >= Swift.min(start.x, end.x) - 0.001
            && point.x <= Swift.max(start.x, end.x) + 0.001
            && point.y >= Swift.min(start.y, end.y) - 0.001
            && point.y <= Swift.max(start.y, end.y) + 0.001
    }

    private func calloutRect(center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - CongressMapAnnotationMetrics.calloutWidth / 2,
            y: center.y - CongressMapAnnotationMetrics.calloutHeight / 2,
            width: CongressMapAnnotationMetrics.calloutWidth,
            height: CongressMapAnnotationMetrics.calloutHeight
        )
    }

    private func starProtectionRect(center: CGPoint) -> CGRect {
        let size = CongressMapAnnotationMetrics.starProtectionSize
        return CGRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )
    }

    private func fitMapToAnnotationsIfNeeded(force: Bool = false) {
        guard force || !hasSetInitialMapRegion else { return }
        let coordinates = positionedRows.map(\.coordinate) + positionedAffiliationAnnotations.map(\.coordinate)
        guard !coordinates.isEmpty else { return }
        let region = CongressMapModel.mapRegion(for: coordinates)
        requestMapRegion(region)
        hasSetInitialMapRegion = true
    }

    private func zoom(to region: MKCoordinateRegion) {
        requestMapRegion(region)
        hasSetInitialMapRegion = true
    }

    private func requestMapRegion(_ region: MKCoordinateRegion) {
        requestedMapRegion = region
        visibleMapRegion = region
        mapRegionRequestID &+= 1
    }
}

private struct CongressMapNativeItem {
    let row: CongressMapRow
    let coordinate: CLLocationCoordinate2D
}

private struct CongressMapNativeAffiliationItem {
    let location: CongressMapAffiliationLocation
    let coordinate: CLLocationCoordinate2D
}

private final class CongressMapNativeAnnotation: NSObject, MKAnnotation {
    let id: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    @objc dynamic var title: String?
    @objc dynamic var subtitle: String?
    var row: CongressMapRow

    init(item: CongressMapNativeItem) {
        id = item.row.id
        coordinate = item.coordinate
        title = item.row.title
        subtitle = [item.row.dateText, item.row.placeText.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
        row = item.row
        super.init()
    }

    func update(with item: CongressMapNativeItem) {
        coordinate = item.coordinate
        title = item.row.title
        subtitle = [item.row.dateText, item.row.placeText.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
        row = item.row
    }
}

private final class CongressMapNativeAffiliationAnnotation: NSObject, MKAnnotation {
    let id: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    @objc dynamic var title: String?
    var location: CongressMapAffiliationLocation

    init(item: CongressMapNativeAffiliationItem) {
        id = item.location.id
        coordinate = item.coordinate
        title = item.location.displayText
        location = item.location
        super.init()
    }

    func update(with item: CongressMapNativeAffiliationItem) {
        coordinate = item.coordinate
        title = item.location.displayText
        location = item.location
    }
}

private final class CongressMapNativeLabelPill: NSView {
    private static let titleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    private static let dateFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)
    private static let horizontalPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 4
    private static let lineSpacing: CGFloat = 2
    private let titleField = NSTextField(wrappingLabelWithString: "")
    private let dateField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.8
        titleField.font = Self.titleFont
        titleField.textColor = .black
        titleField.lineBreakMode = .byWordWrapping
        titleField.maximumNumberOfLines = 0
        titleField.alignment = .left
        dateField.font = Self.dateFont
        dateField.textColor = NSColor.black.withAlphaComponent(0.82)
        dateField.lineBreakMode = .byClipping
        dateField.maximumNumberOfLines = 1
        dateField.alignment = .left
        addSubview(titleField)
        addSubview(dateField)
    }

    required init?(coder: NSCoder) {
        nil
    }

    @discardableResult
    func configure(
        title: String,
        date: String,
        accentColor: NSColor,
        maximumWidth: CGFloat = 260
    ) -> CGSize {
        titleField.stringValue = title
        dateField.stringValue = date
        let measurement = Self.measurement(
            title: title,
            date: date,
            maximumWidth: maximumWidth
        )
        frame.size = measurement.size
        dateField.frame = CGRect(
            x: Self.horizontalPadding,
            y: Self.verticalPadding,
            width: measurement.contentWidth,
            height: measurement.dateHeight
        )
        titleField.frame = CGRect(
            x: Self.horizontalPadding,
            y: Self.verticalPadding + measurement.dateHeight + Self.lineSpacing,
            width: measurement.contentWidth,
            height: measurement.titleHeight
        )
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.borderColor = accentColor.withAlphaComponent(0.95).cgColor
        layer?.borderWidth = 2
        toolTip = "\(title)\n\(date)"
        return measurement.size
    }

    static func measuredSize(
        title: String,
        date: String,
        maximumWidth: CGFloat = 260
    ) -> CGSize {
        measurement(title: title, date: date, maximumWidth: maximumWidth).size
    }

    private static func measurement(
        title: String,
        date: String,
        maximumWidth: CGFloat
    ) -> (size: CGSize, contentWidth: CGFloat, titleHeight: CGFloat, dateHeight: CGFloat) {
        let maximumContentWidth = max(1, maximumWidth - 2 * horizontalPadding)
        let titleSingleLineWidth = ceil(
            (title as NSString).size(withAttributes: [.font: titleFont]).width
        )
        let dateWidth = ceil(
            (date as NSString).size(withAttributes: [.font: dateFont]).width
        )
        let contentWidth = min(
            maximumContentWidth,
            max(1, max(titleSingleLineWidth, dateWidth))
        )
        let titleRect = (title as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: titleFont]
        )
        let titleHeight = max(
            ceil(titleFont.ascender - titleFont.descender),
            ceil(titleRect.height)
        ) + 1
        let dateHeight = ceil(dateFont.ascender - dateFont.descender) + 1
        let size = CGSize(
            width: contentWidth + 2 * horizontalPadding,
            height: verticalPadding * 2 + titleHeight + lineSpacing + dateHeight
        )
        return (size, contentWidth, titleHeight, dateHeight)
    }
}

private func congressMapLeaderPath(from start: CGPoint, to end: CGPoint) -> CGPath {
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    let firstControl: CGPoint
    let secondControl: CGPoint
    if abs(deltaX) >= abs(deltaY) {
        firstControl = CGPoint(x: start.x + deltaX * 0.42, y: start.y)
        secondControl = CGPoint(x: end.x - deltaX * 0.18, y: end.y)
    } else {
        firstControl = CGPoint(x: start.x, y: start.y + deltaY * 0.42)
        secondControl = CGPoint(x: end.x, y: end.y - deltaY * 0.18)
    }
    let path = CGMutablePath()
    path.move(to: start)
    path.addCurve(to: end, control1: firstControl, control2: secondControl)
    return path
}

private final class CongressMapNativeCongressView: MKMarkerAnnotationView {
    private let labelPill = CongressMapNativeLabelPill(frame: .zero)
    private let leaderLineHaloLayer = CAShapeLayer()
    private let leaderLineLayer = CAShapeLayer()
    private var labelSize: CGSize = .zero
    private var labelOriginOffset: CGPoint = .zero
    private var isLabelSuppressed = false
    private var isLabelInsideMap = true

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        wantsLayer = true
        layer?.masksToBounds = false
        leaderLineHaloLayer.fillColor = NSColor.clear.cgColor
        leaderLineHaloLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        leaderLineHaloLayer.lineWidth = 4.6
        leaderLineHaloLayer.lineCap = .round
        leaderLineHaloLayer.lineJoin = .round
        leaderLineLayer.fillColor = NSColor.clear.cgColor
        leaderLineLayer.strokeColor = NSColor.systemBlue.cgColor
        leaderLineLayer.lineWidth = 2.4
        leaderLineLayer.lineCap = .round
        leaderLineLayer.lineJoin = .round
        layer?.addSublayer(leaderLineHaloLayer)
        layer?.addSublayer(leaderLineLayer)
        addSubview(labelPill)
        canShowCallout = false
        collisionMode = .none
        titleVisibility = .hidden
        subtitleVisibility = .hidden
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        menu = nil
        toolTip = nil
        leaderLineHaloLayer.path = nil
        leaderLineLayer.path = nil
    }

    override func layout() {
        super.layout()
        let anchor = coordinateAnchorPoint
        labelPill.frame.origin = CGPoint(
            x: anchor.x + labelOriginOffset.x,
            y: anchor.y + labelOriginOffset.y
        )
        updateLeaderLine(from: anchor, to: labelPill.frame)
    }

    func configure(
        row: CongressMapRow,
        markerColor: NSColor,
        selected: Bool,
        sharesLocationWithAnotherCongress: Bool
    ) {
        labelSize = labelPill.configure(
            title: row.title,
            date: row.startDateText,
            accentColor: markerColor,
            maximumWidth: 260
        )
        isLabelSuppressed = selected
        labelOriginOffset = CGPoint(
            x: -labelSize.width / 2,
            y: -labelSize.height - 8
        )
        markerTintColor = markerColor
        leaderLineLayer.strokeColor = markerColor.withAlphaComponent(0.98).cgColor
        glyphTintColor = .white
        glyphImage = nil
        glyphText = nil
        // Varje kongress får en egen etikett, även vid samma koordinat. Då kan
        // layoutmotorn placera dem åt olika håll och rita en egen ledlinje.
        clusteringIdentifier = nil
        collisionMode = .none
        displayPriority = .required
        toolTip = [row.title, row.dateText, row.placeText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        setAccessibilityLabel("\(row.title), \(row.startDateText)")
        updateLabelVisibility()
        needsLayout = true
    }

    var labelLayoutSize: CGSize {
        labelSize
    }

    func labelHitFrame(in view: NSView) -> CGRect {
        guard !labelPill.isHidden else { return .null }
        return convert(labelPill.frame, to: view)
    }

    func markerHitFrame(in view: NSView) -> CGRect {
        convert(bounds, to: view).insetBy(dx: -4, dy: -4)
    }

    func setLabelVisible(_ isVisible: Bool) {
        isLabelInsideMap = isVisible
        updateLabelVisibility()
    }

    private func updateLabelVisibility() {
        let shouldShow = isLabelInsideMap && !isLabelSuppressed
        guard labelPill.isHidden == shouldShow else { return }
        labelPill.isHidden = !shouldShow
        if shouldShow {
            needsLayout = true
        } else {
            leaderLineHaloLayer.path = nil
            leaderLineLayer.path = nil
        }
    }

    func placeLabel(originOffset: CGPoint) {
        labelOriginOffset = originOffset
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private var coordinateAnchorPoint: CGPoint {
        CGPoint(
            x: bounds.midX - centerOffset.x,
            y: bounds.midY - centerOffset.y
        )
    }

    private func updateLeaderLine(from anchor: CGPoint, to labelFrame: CGRect) {
        let endpoint = CGPoint(
            x: min(max(anchor.x, labelFrame.minX), labelFrame.maxX),
            y: min(max(anchor.y, labelFrame.minY), labelFrame.maxY)
        )
        let distance = hypot(endpoint.x - anchor.x, endpoint.y - anchor.y)
        guard distance > 14 else {
            leaderLineHaloLayer.path = nil
            leaderLineLayer.path = nil
            return
        }
        let path = congressMapLeaderPath(from: anchor, to: endpoint)
        leaderLineHaloLayer.path = path
        leaderLineLayer.path = path
    }
}

private final class CongressMapNativeClusterView: MKAnnotationView {
    enum LayoutMode {
        case compact
        case oneColumn
        case twoColumns
    }

    private let markerView = NSView(frame: .zero)
    private let countField = NSTextField(labelWithString: "")
    private let leaderLineHaloLayer = CAShapeLayer()
    private let leaderLineLayer = CAShapeLayer()
    private var labelPills: [CongressMapNativeLabelPill] = []
    private var congressIDs: [String] = []
    private var suppressedCongressID: String?
    private var labelsAreInsideMap = true
    private var labelRelativeOrigins: [CGPoint] = []
    private var labelGroupSize: CGSize = .zero
    private var labelGroupOriginOffset: CGPoint = .zero

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        wantsLayer = true
        layer?.masksToBounds = false
        leaderLineHaloLayer.fillColor = NSColor.clear.cgColor
        leaderLineHaloLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        leaderLineHaloLayer.lineWidth = 4.8
        leaderLineHaloLayer.lineCap = .round
        leaderLineHaloLayer.lineJoin = .round
        leaderLineLayer.fillColor = NSColor.clear.cgColor
        leaderLineLayer.strokeColor = NSColor.systemBlue.cgColor
        leaderLineLayer.lineWidth = 2.5
        leaderLineLayer.lineCap = .round
        leaderLineLayer.lineJoin = .round
        layer?.addSublayer(leaderLineHaloLayer)
        layer?.addSublayer(leaderLineLayer)
        markerView.wantsLayer = true
        markerView.layer?.backgroundColor = NSColor.systemBlue.cgColor
        markerView.layer?.cornerRadius = 18
        markerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        markerView.layer?.borderWidth = 1.5
        countField.font = .systemFont(ofSize: 11.5, weight: .bold)
        countField.textColor = .white
        countField.alignment = .center
        markerView.addSubview(countField)
        addSubview(markerView)
        canShowCallout = false
        collisionMode = .none
        displayPriority = .required
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        clearLabels()
        toolTip = nil
        leaderLineHaloLayer.path = nil
        leaderLineLayer.path = nil
    }

    func configure(
        rows: [CongressMapRow],
        mode: LayoutMode,
        selectedCongressID: String?
    ) {
        clearLabels()
        congressIDs = rows.map(\.id)
        suppressedCongressID = selectedCongressID
        countField.stringValue = "\(rows.count)"

        switch mode {
        case .compact:
            configureCompact(count: rows.count)
        case .oneColumn:
            configureExpanded(rows: rows, usesTwoColumns: false)
        case .twoColumns:
            configureExpanded(rows: rows, usesTwoColumns: true)
        }

        toolTip = rows.map { "\($0.title)\n\($0.startDateText)" }.joined(separator: "\n\n")
        setAccessibilityLabel(toolTip ?? "")
        updatePillVisibility()
    }

    private func configureCompact(count: Int) {
        let markerSize: CGFloat = 36
        labelGroupSize = .zero
        labelGroupOriginOffset = .zero
        bounds = CGRect(x: 0, y: 0, width: markerSize, height: markerSize)
        centerOffset = .zero
        markerView.frame = bounds
        countField.frame = CGRect(x: 3, y: 9, width: markerSize - 6, height: 17)
    }

    private func configureExpanded(
        rows: [CongressMapRow],
        usesTwoColumns: Bool
    ) {
        let markerSize: CGFloat = 36
        let markerGap: CGFloat = 6
        let columnGap: CGFloat = 8
        let rowGap: CGFloat = 5
        let pills = rows.map { row -> CongressMapNativeLabelPill in
            let pill = CongressMapNativeLabelPill(frame: .zero)
            pill.configure(
                title: row.title,
                date: row.startDateText,
                accentColor: .systemBlue,
                maximumWidth: 240
            )
            addSubview(pill)
            labelPills.append(pill)
            return pill
        }

        if usesTwoColumns {
            let leftPills = pills.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
            let rightPills = pills.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)
            let leftWidth = leftPills.map { $0.frame.width }.max() ?? 0
            let rightWidth = rightPills.map { $0.frame.width }.max() ?? 0
            let leftHeight = columnHeight(leftPills, rowGap: rowGap)
            let rightHeight = columnHeight(rightPills, rowGap: rowGap)
            let labelsHeight = max(leftHeight, rightHeight)
            let labelsWidth = leftWidth + columnGap + rightWidth
            let width = max(markerSize, labelsWidth)
            let height = markerSize + markerGap + labelsHeight
            let labelsX = (width - labelsWidth) / 2
            let markerX = (width - markerSize) / 2
            let markerY = labelsHeight + markerGap
            bounds = CGRect(x: 0, y: 0, width: width, height: height)
            centerOffset = CGPoint(
                x: bounds.midX - (markerX + markerSize / 2),
                y: bounds.midY - (markerY + markerSize / 2)
            )
            markerView.frame = CGRect(
                x: markerX,
                y: markerY,
                width: markerSize,
                height: markerSize
            )
            layoutColumn(
                leftPills,
                x: labelsX,
                topY: labelsHeight,
                columnWidth: leftWidth,
                rowGap: rowGap
            )
            layoutColumn(
                rightPills,
                x: labelsX + leftWidth + columnGap,
                topY: labelsHeight,
                columnWidth: rightWidth,
                rowGap: rowGap
            )
        } else {
            let labelWidth = pills.map { $0.frame.width }.max() ?? 0
            let labelsHeight = columnHeight(pills, rowGap: rowGap)
            let width = max(markerSize, labelWidth)
            let height = markerSize + markerGap + labelsHeight
            let labelX = (width - labelWidth) / 2
            let markerX = (width - markerSize) / 2
            let markerY = labelsHeight + markerGap
            bounds = CGRect(x: 0, y: 0, width: width, height: height)
            centerOffset = CGPoint(
                x: bounds.midX - (markerX + markerSize / 2),
                y: bounds.midY - (markerY + markerSize / 2)
            )
            markerView.frame = CGRect(
                x: markerX,
                y: markerY,
                width: markerSize,
                height: markerSize
            )
            layoutColumn(
                pills,
                x: labelX,
                topY: labelsHeight,
                columnWidth: labelWidth,
                rowGap: rowGap
            )
        }

        countField.frame = CGRect(x: 3, y: 9, width: markerSize - 6, height: 17)
        captureLabelLayout()
    }

    private func layoutColumn(
        _ pills: [CongressMapNativeLabelPill],
        x: CGFloat,
        topY: CGFloat,
        columnWidth: CGFloat,
        rowGap: CGFloat
    ) {
        var nextY = topY
        for pill in pills {
            nextY -= pill.frame.height
            pill.frame.origin = CGPoint(
                x: x + (columnWidth - pill.frame.width) / 2,
                y: nextY
            )
            nextY -= rowGap
        }
    }

    private func columnHeight(
        _ pills: [CongressMapNativeLabelPill],
        rowGap: CGFloat
    ) -> CGFloat {
        guard !pills.isEmpty else { return 0 }
        return pills.reduce(0) { $0 + $1.frame.height }
            + CGFloat(pills.count - 1) * rowGap
    }

    private func clearLabels() {
        for pill in labelPills {
            pill.removeFromSuperview()
        }
        labelPills.removeAll(keepingCapacity: true)
        congressIDs.removeAll(keepingCapacity: true)
        suppressedCongressID = nil
        labelRelativeOrigins.removeAll(keepingCapacity: true)
        labelGroupSize = .zero
        leaderLineHaloLayer.path = nil
        leaderLineLayer.path = nil
    }

    var labelLayoutSize: CGSize {
        labelGroupSize
    }

    func congressID(at point: CGPoint, in view: NSView) -> String? {
        for (index, pill) in labelPills.enumerated().reversed() {
            guard congressIDs.indices.contains(index), !pill.isHidden else { continue }
            if convert(pill.frame, to: view).contains(point) {
                return congressIDs[index]
            }
        }
        return nil
    }

    func labelHitFrame(for congressID: String, in view: NSView) -> CGRect {
        guard let index = congressIDs.firstIndex(of: congressID),
              labelPills.indices.contains(index),
              !labelPills[index].isHidden else {
            return .null
        }
        return convert(labelPills[index].frame, to: view)
    }

    func markerHitFrame(in view: NSView) -> CGRect {
        convert(markerView.frame, to: view).insetBy(dx: -4, dy: -4)
    }

    func setLabelsVisible(_ isVisible: Bool) {
        labelsAreInsideMap = isVisible
        updatePillVisibility()
        if isVisible, labelPills.contains(where: { !$0.isHidden }) {
            applyLabelPlacement()
        } else {
            leaderLineHaloLayer.path = nil
            leaderLineLayer.path = nil
        }
    }

    private func updatePillVisibility() {
        for (index, pill) in labelPills.enumerated() {
            let isSuppressed = congressIDs.indices.contains(index)
                && congressIDs[index] == suppressedCongressID
            pill.isHidden = !labelsAreInsideMap || isSuppressed
        }
        if labelPills.allSatisfy(\.isHidden) {
            leaderLineHaloLayer.path = nil
            leaderLineLayer.path = nil
        }
    }

    func placeLabelGroup(originOffset: CGPoint) {
        guard labelPills.count == labelRelativeOrigins.count,
              labelGroupSize.width > 0,
              labelGroupSize.height > 0 else {
            return
        }
        labelGroupOriginOffset = originOffset
        applyLabelPlacement()
    }

    private var coordinateAnchorPoint: CGPoint {
        CGPoint(
            x: bounds.midX - centerOffset.x,
            y: bounds.midY - centerOffset.y
        )
    }

    private func captureLabelLayout() {
        guard let first = labelPills.first else { return }
        let union = labelPills.dropFirst().reduce(first.frame) { result, pill in
            result.union(pill.frame)
        }
        labelGroupSize = union.size
        labelRelativeOrigins = labelPills.map {
            CGPoint(x: $0.frame.minX - union.minX, y: $0.frame.minY - union.minY)
        }
        let anchor = coordinateAnchorPoint
        labelGroupOriginOffset = CGPoint(
            x: union.minX - anchor.x,
            y: union.minY - anchor.y
        )
        applyLabelPlacement()
    }

    private func applyLabelPlacement() {
        let anchor = coordinateAnchorPoint
        let groupOrigin = CGPoint(
            x: anchor.x + labelGroupOriginOffset.x,
            y: anchor.y + labelGroupOriginOffset.y
        )
        for (pill, relativeOrigin) in zip(labelPills, labelRelativeOrigins) {
            pill.frame.origin = CGPoint(
                x: groupOrigin.x + relativeOrigin.x,
                y: groupOrigin.y + relativeOrigin.y
            )
        }
        let groupFrame = CGRect(origin: groupOrigin, size: labelGroupSize)
        let endpoint = CGPoint(
            x: min(max(anchor.x, groupFrame.minX), groupFrame.maxX),
            y: min(max(anchor.y, groupFrame.minY), groupFrame.maxY)
        )
        let distance = hypot(endpoint.x - anchor.x, endpoint.y - anchor.y)
        guard distance > 14 else {
            leaderLineHaloLayer.path = nil
            leaderLineLayer.path = nil
            return
        }
        let path = congressMapLeaderPath(from: anchor, to: endpoint)
        leaderLineHaloLayer.path = path
        leaderLineLayer.path = path
    }
}

private struct CongressMapNativeView: NSViewRepresentable {
    let congresses: [CongressMapNativeItem]
    let affiliations: [CongressMapNativeAffiliationItem]
    @Binding var selectedCongressID: String?
    let requestedRegion: MKCoordinateRegion
    let regionRequestID: Int
    let language: AppLanguage
    let onRegionChange: (MKCoordinateRegion) -> Void
    let visibilityAction: (CongressMapRow) -> Void
    let selectionAction: (String, CGPoint) -> Void
    let clearSelectionAction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        let labelClickRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCongressLabelClick(_:))
        )
        labelClickRecognizer.delegate = context.coordinator
        mapView.addGestureRecognizer(labelClickRecognizer)
        mapView.preferredConfiguration = MKStandardMapConfiguration(
            elevationStyle: .realistic,
            emphasisStyle: .muted
        )
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsPitchControl = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.setRegion(requestedRegion, animated: false)
        context.coordinator.lastAppliedRegionRequestID = regionRequestID
        context.coordinator.synchronizeAnnotations(in: mapView)
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronizeAnnotations(in: mapView)
        context.coordinator.applyRequestedRegionIfNeeded(to: mapView)
        context.coordinator.synchronizeSelection(in: mapView)
        context.coordinator.refreshVisibleAnnotationViews(in: mapView)
    }

    static func dismantleNSView(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, NSGestureRecognizerDelegate {
        var parent: CongressMapNativeView
        var congressAnnotationsByID: [String: CongressMapNativeAnnotation] = [:]
        var affiliationAnnotationsByID: [String: CongressMapNativeAffiliationAnnotation] = [:]
        var lastAppliedRegionRequestID: Int?
        private var congressLocationCounts: [String: Int] = [:]
        private var labelLayoutScheduled = false

        private struct LabelLayoutTarget {
            let id: String
            let anchor: CGPoint
            let size: CGSize
            let priority: Int
            let place: (CGPoint) -> Void
        }

        init(parent: CongressMapNativeView) {
            self.parent = parent
        }

        func synchronizeAnnotations(in mapView: MKMapView) {
            synchronizeCongresses(in: mapView)
            synchronizeAffiliations(in: mapView)
        }

        private func synchronizeCongresses(in mapView: MKMapView) {
            congressLocationCounts = parent.congresses.reduce(into: [:]) { counts, item in
                counts[congressLocationKey(for: item.row), default: 0] += 1
            }
            let desiredIDs = Set(parent.congresses.map { $0.row.id })
            let staleAnnotations = congressAnnotationsByID.values.filter { !desiredIDs.contains($0.id) }
            if !staleAnnotations.isEmpty {
                mapView.removeAnnotations(staleAnnotations)
                for annotation in staleAnnotations {
                    congressAnnotationsByID.removeValue(forKey: annotation.id)
                }
            }

            var newAnnotations: [CongressMapNativeAnnotation] = []
            for item in parent.congresses {
                if let annotation = congressAnnotationsByID[item.row.id] {
                    annotation.update(with: item)
                } else {
                    let annotation = CongressMapNativeAnnotation(item: item)
                    congressAnnotationsByID[item.row.id] = annotation
                    newAnnotations.append(annotation)
                }
            }
            if !newAnnotations.isEmpty {
                mapView.addAnnotations(newAnnotations)
            }
        }

        private func synchronizeAffiliations(in mapView: MKMapView) {
            let desiredIDs = Set(parent.affiliations.map { $0.location.id })
            let staleAnnotations = affiliationAnnotationsByID.values.filter { !desiredIDs.contains($0.id) }
            if !staleAnnotations.isEmpty {
                mapView.removeAnnotations(staleAnnotations)
                for annotation in staleAnnotations {
                    affiliationAnnotationsByID.removeValue(forKey: annotation.id)
                }
            }

            var newAnnotations: [CongressMapNativeAffiliationAnnotation] = []
            for item in parent.affiliations {
                if let annotation = affiliationAnnotationsByID[item.location.id] {
                    annotation.update(with: item)
                } else {
                    let annotation = CongressMapNativeAffiliationAnnotation(item: item)
                    affiliationAnnotationsByID[item.location.id] = annotation
                    newAnnotations.append(annotation)
                }
            }
            if !newAnnotations.isEmpty {
                mapView.addAnnotations(newAnnotations)
            }
        }

        func applyRequestedRegionIfNeeded(to mapView: MKMapView) {
            guard lastAppliedRegionRequestID != parent.regionRequestID else { return }
            lastAppliedRegionRequestID = parent.regionRequestID
            mapView.setRegion(parent.requestedRegion, animated: true)
        }

        func synchronizeSelection(in mapView: MKMapView) {
            for selectedAnnotation in mapView.selectedAnnotations {
                mapView.deselectAnnotation(selectedAnnotation, animated: false)
            }
        }

        func refreshVisibleAnnotationViews(in mapView: MKMapView) {
            for annotation in congressAnnotationsByID.values {
                guard let view = mapView.view(for: annotation) as? CongressMapNativeCongressView else { continue }
                configureCongressView(view, annotation: annotation)
            }
            for annotation in affiliationAnnotationsByID.values {
                guard let view = mapView.view(for: annotation) as? MKMarkerAnnotationView else { continue }
                configureAffiliationView(view, annotation: annotation)
            }
            for cluster in mapView.annotations.compactMap({ $0 as? MKClusterAnnotation }) {
                guard let view = mapView.view(for: cluster) as? CongressMapNativeClusterView else { continue }
                configureClusterView(view, cluster: cluster, mapView: mapView)
            }
            layoutVisibleCongressLabels(in: mapView)
        }

        private func scheduleLabelLayout(in mapView: MKMapView) {
            guard !labelLayoutScheduled else { return }
            labelLayoutScheduled = true
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.labelLayoutScheduled = false
                self.layoutVisibleCongressLabels(in: mapView)
            }
        }

        private func updateLabelVisibility(in mapView: MKMapView) {
            let visibleBounds = mapView.bounds
            for annotation in congressAnnotationsByID.values {
                guard let view = mapView.view(for: annotation) as? CongressMapNativeCongressView else {
                    continue
                }
                let point = mapView.convert(annotation.coordinate, toPointTo: mapView)
                view.setLabelVisible(visibleBounds.contains(point))
            }
            for cluster in mapView.annotations.compactMap({ $0 as? MKClusterAnnotation }) {
                guard let view = mapView.view(for: cluster) as? CongressMapNativeClusterView else {
                    continue
                }
                let point = mapView.convert(cluster.coordinate, toPointTo: mapView)
                view.setLabelsVisible(visibleBounds.contains(point))
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            gestureRecognizer.view is MKMapView
        }

        func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handleCongressLabelClick(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended,
                  let mapView = recognizer.view as? MKMapView else {
                return
            }
            let point = recognizer.location(in: mapView)
            if let congressID = congressIDForLabel(at: point, in: mapView)
                ?? congressIDForMarker(at: point, in: mapView) {
                presentCongressDetails(congressID: congressID, at: point, in: mapView)
                return
            }
            parent.selectedCongressID = nil
            parent.clearSelectionAction()
            for selectedAnnotation in mapView.selectedAnnotations {
                mapView.deselectAnnotation(selectedAnnotation, animated: false)
            }
            scheduleLabelLayout(in: mapView)
        }

        private func presentCongressDetails(
            congressID: String,
            at point: CGPoint,
            in mapView: MKMapView
        ) {
            guard let annotation = congressAnnotationsByID[congressID] else { return }
            let labelFrame = labelHitFrame(for: congressID, in: mapView)
            let detailOrigin: CGPoint
            if labelFrame.isNull {
                let pinPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
                detailOrigin = CGPoint(
                    x: pinPoint.x,
                    y: mapView.isFlipped
                        ? pinPoint.y + 14
                        : mapView.bounds.height - pinPoint.y + 14
                )
            } else {
                detailOrigin = CGPoint(
                    x: labelFrame.minX,
                    y: mapView.isFlipped
                        ? labelFrame.minY
                        : mapView.bounds.height - labelFrame.maxY
                )
            }
            parent.selectedCongressID = congressID
            parent.selectionAction(congressID, detailOrigin)
            scheduleLabelLayout(in: mapView)
        }

        private func labelHitFrame(for congressID: String, in mapView: MKMapView) -> CGRect {
            if let annotation = congressAnnotationsByID[congressID],
               let view = mapView.view(for: annotation) as? CongressMapNativeCongressView {
                let frame = view.labelHitFrame(in: mapView)
                if !frame.isNull {
                    return frame
                }
            }
            for cluster in mapView.annotations.compactMap({ $0 as? MKClusterAnnotation }) {
                guard let view = mapView.view(for: cluster) as? CongressMapNativeClusterView else {
                    continue
                }
                let frame = view.labelHitFrame(for: congressID, in: mapView)
                if !frame.isNull {
                    return frame
                }
            }
            return .null
        }

        private func congressIDForLabel(
            at point: CGPoint,
            in mapView: MKMapView
        ) -> String? {
            for cluster in mapView.annotations.compactMap({ $0 as? MKClusterAnnotation }) {
                guard let view = mapView.view(for: cluster) as? CongressMapNativeClusterView,
                      !view.isHidden else {
                    continue
                }
                if let congressID = view.congressID(at: point, in: mapView) {
                    return congressID
                }
            }
            let visibleCongresses = congressAnnotationsByID.values.sorted {
                if $0.id == parent.selectedCongressID { return true }
                if $1.id == parent.selectedCongressID { return false }
                return $0.id < $1.id
            }
            for annotation in visibleCongresses {
                guard let view = mapView.view(for: annotation) as? CongressMapNativeCongressView,
                      !view.isHidden else {
                    continue
                }
                if view.labelHitFrame(in: mapView).contains(point) {
                    return annotation.id
                }
            }
            return nil
        }

        private func congressIDForMarker(
            at point: CGPoint,
            in mapView: MKMapView
        ) -> String? {
            for cluster in mapView.annotations.compactMap({ $0 as? MKClusterAnnotation }) {
                guard let view = mapView.view(for: cluster) as? CongressMapNativeClusterView,
                      !view.isHidden,
                      view.markerHitFrame(in: mapView).contains(point) else {
                    continue
                }
                return cluster.memberAnnotations
                    .compactMap { $0 as? CongressMapNativeAnnotation }
                    .sorted(by: congressAnnotationSort)
                    .first?.id
            }
            for annotation in congressAnnotationsByID.values {
                guard let view = mapView.view(for: annotation) as? CongressMapNativeCongressView,
                      !view.isHidden,
                      view.markerHitFrame(in: mapView).contains(point) else {
                    continue
                }
                return annotation.id
            }
            return nil
        }

        private func layoutVisibleCongressLabels(in mapView: MKMapView) {
            guard mapView.bounds.width > 120, mapView.bounds.height > 120 else { return }
            updateLabelVisibility(in: mapView)
            let mapBounds = mapView.bounds.insetBy(dx: 10, dy: 10)
            var targets: [LabelLayoutTarget] = []

            for annotation in mapView.annotations {
                if let cluster = annotation as? MKClusterAnnotation,
                   let view = mapView.view(for: cluster) as? CongressMapNativeClusterView,
                   !view.isHidden,
                   view.labelLayoutSize.width > 0,
                   view.labelLayoutSize.height > 0 {
                    let anchor = mapView.convert(cluster.coordinate, toPointTo: mapView)
                    guard mapView.bounds.contains(anchor) else { continue }
                    targets.append(
                        LabelLayoutTarget(
                            id: "cluster:\(cluster.memberAnnotations.count):\(anchor.x):\(anchor.y)",
                            anchor: anchor,
                            size: view.labelLayoutSize,
                            priority: 0,
                            place: { [weak view] offset in
                                view?.placeLabelGroup(originOffset: offset)
                            }
                        )
                    )
                } else if let congress = annotation as? CongressMapNativeAnnotation,
                          let view = mapView.view(for: congress) as? CongressMapNativeCongressView,
                          !view.isHidden,
                          view.labelLayoutSize.width > 0,
                          view.labelLayoutSize.height > 0 {
                    let anchor = mapView.convert(congress.coordinate, toPointTo: mapView)
                    guard mapView.bounds.contains(anchor) else { continue }
                    targets.append(
                        LabelLayoutTarget(
                            id: congress.id,
                            anchor: anchor,
                            size: view.labelLayoutSize,
                            priority: parent.selectedCongressID == congress.id ? 0 : 1,
                            place: { [weak view] offset in
                                view?.placeLabel(originOffset: offset)
                            }
                        )
                    )
                }
            }

            targets.sort {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                let lhsArea = $0.size.width * $0.size.height
                let rhsArea = $1.size.width * $1.size.height
                if lhsArea != rhsArea { return lhsArea > rhsArea }
                return $0.id < $1.id
            }

            var occupiedFrames = mapView.annotations.compactMap { annotation -> CGRect? in
                let point = mapView.convert(annotation.coordinate, toPointTo: mapView)
                guard mapBounds.insetBy(dx: -24, dy: -24).contains(point) else { return nil }
                return CGRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32)
            }

            for target in targets {
                let candidates = labelCandidates(
                    around: target.anchor,
                    size: target.size,
                    within: mapBounds
                )
                let nonOverlappingCandidates = candidates.filter {
                    labelFrame($0, isClearOf: occupiedFrames)
                }
                let fallbackCandidates = nonOverlappingCandidates.isEmpty
                    ? labelGridCandidates(size: target.size, within: mapBounds).filter {
                        labelFrame($0, isClearOf: occupiedFrames)
                    }
                    : nonOverlappingCandidates
                let candidatesToScore = fallbackCandidates.isEmpty
                    ? candidates
                    : fallbackCandidates
                guard let chosen = candidatesToScore.min(by: { lhs, rhs in
                    labelPlacementScore(lhs, anchor: target.anchor, occupiedFrames: occupiedFrames)
                        < labelPlacementScore(rhs, anchor: target.anchor, occupiedFrames: occupiedFrames)
                }) else {
                    continue
                }
                target.place(
                    CGPoint(
                        x: chosen.minX - target.anchor.x,
                        y: chosen.minY - target.anchor.y
                    )
                )
                occupiedFrames.append(chosen.insetBy(dx: -4, dy: -4))
            }
        }

        private func labelCandidates(
            around anchor: CGPoint,
            size: CGSize,
            within bounds: CGRect
        ) -> [CGRect] {
            let directions = (0..<16).map { index in
                let angle = CGFloat(index) * (.pi * 2 / 16) - .pi / 2
                return CGPoint(x: cos(angle), y: sin(angle))
            }
            let maximumClearance = hypot(bounds.width, bounds.height)
            let clearances: [CGFloat] = [8, 28, 54, 88, 132, 188, 252, 330, 420, 520]
                + stride(from: CGFloat(640), through: maximumClearance, by: 140).map { $0 }
            var candidates: [CGRect] = []
            candidates.reserveCapacity(directions.count * clearances.count + 96)

            for clearance in clearances {
                for direction in directions {
                    let projectedHalfSize = abs(direction.x) * size.width / 2
                        + abs(direction.y) * size.height / 2
                    let center = CGPoint(
                        x: anchor.x + direction.x * (clearance + projectedHalfSize),
                        y: anchor.y + direction.y * (clearance + projectedHalfSize)
                    )
                    candidates.append(
                        clampedLabelFrame(
                            CGRect(
                                x: center.x - size.width / 2,
                                y: center.y - size.height / 2,
                                width: size.width,
                                height: size.height
                            ),
                            to: bounds
                        )
                    )
                }
            }

            let verticalStep = max(24, min(56, size.height / 2))
            var y = bounds.minY
            while y <= bounds.maxY - size.height {
                candidates.append(CGRect(x: bounds.minX, y: y, width: size.width, height: size.height))
                candidates.append(CGRect(x: bounds.maxX - size.width, y: y, width: size.width, height: size.height))
                y += verticalStep
            }
            return candidates
        }

        private func labelGridCandidates(size: CGSize, within bounds: CGRect) -> [CGRect] {
            guard size.width <= bounds.width, size.height <= bounds.height else { return [] }
            let spacing = max(18, min(42, min(size.width, size.height) / 2))
            var candidates: [CGRect] = []
            var y = bounds.minY
            while y <= bounds.maxY - size.height {
                var x = bounds.minX
                while x <= bounds.maxX - size.width {
                    candidates.append(CGRect(origin: CGPoint(x: x, y: y), size: size).integral)
                    x += spacing
                }
                y += spacing
            }
            return candidates
        }

        private func labelFrame(_ frame: CGRect, isClearOf occupiedFrames: [CGRect]) -> Bool {
            occupiedFrames.allSatisfy { occupied in
                !frame.intersects(occupied)
            }
        }

        private func clampedLabelFrame(_ frame: CGRect, to bounds: CGRect) -> CGRect {
            CGRect(
                x: min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width)),
                y: min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height)),
                width: frame.width,
                height: frame.height
            ).integral
        }

        private func labelPlacementScore(
            _ frame: CGRect,
            anchor: CGPoint,
            occupiedFrames: [CGRect]
        ) -> CGFloat {
            let overlapArea = occupiedFrames.reduce(CGFloat.zero) { result, occupied in
                let intersection = frame.intersection(occupied)
                guard !intersection.isNull else { return result }
                return result + intersection.width * intersection.height
            }
            let distance = hypot(frame.midX - anchor.x, frame.midY - anchor.y)
            return overlapArea * 10_000 + distance
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            if let cluster = annotation as? MKClusterAnnotation {
                let reuseIdentifier = "CongressCluster"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? CongressMapNativeClusterView)
                    ?? CongressMapNativeClusterView(annotation: cluster, reuseIdentifier: reuseIdentifier)
                view.annotation = cluster
                configureClusterView(view, cluster: cluster, mapView: mapView)
                scheduleLabelLayout(in: mapView)
                return view
            }
            if let congress = annotation as? CongressMapNativeAnnotation {
                let reuseIdentifier = "CongressMarker"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? CongressMapNativeCongressView)
                    ?? CongressMapNativeCongressView(annotation: congress, reuseIdentifier: reuseIdentifier)
                view.annotation = congress
                configureCongressView(view, annotation: congress)
                scheduleLabelLayout(in: mapView)
                return view
            }
            if let affiliation = annotation as? CongressMapNativeAffiliationAnnotation {
                let reuseIdentifier = "CongressAffiliation"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: affiliation, reuseIdentifier: reuseIdentifier)
                view.annotation = affiliation
                configureAffiliationView(view, annotation: affiliation)
                return view
            }
            return nil
        }

        private func configureCongressView(
            _ view: CongressMapNativeCongressView,
            annotation: CongressMapNativeAnnotation
        ) {
            let isSelected = parent.selectedCongressID == annotation.id
            view.canShowCallout = false
            view.configure(
                row: annotation.row,
                markerColor: markerColor(for: annotation.row, isSelected: isSelected),
                selected: isSelected,
                sharesLocationWithAnotherCongress: congressLocationCounts[
                    congressLocationKey(for: annotation.row),
                    default: 0
                ] > 1
            )
            view.menu = visibilityMenu(for: annotation)
        }

        private func configureClusterView(
            _ view: CongressMapNativeClusterView,
            cluster: MKClusterAnnotation,
            mapView: MKMapView
        ) {
            let rows = cluster.memberAnnotations
                .compactMap { ($0 as? CongressMapNativeAnnotation)?.row }
                .sorted(by: congressRowSort)
            cluster.title = parent.language.text("\(rows.count) congresses", "\(rows.count) kongresser")
            view.clusteringIdentifier = nil
            view.configure(
                rows: rows,
                mode: clusterLayoutMode(for: rows, cluster: cluster, mapView: mapView),
                selectedCongressID: parent.selectedCongressID
            )
            view.menu = nil
        }

        private func configureAffiliationView(
            _ view: MKMarkerAnnotationView,
            annotation: CongressMapNativeAffiliationAnnotation
        ) {
            view.canShowCallout = false
            view.animatesWhenAdded = false
            view.clusteringIdentifier = nil
            view.collisionMode = .circle
            view.titleVisibility = .adaptive
            view.displayPriority = .required
            view.markerTintColor = .systemYellow
            view.glyphTintColor = .labelColor
            view.glyphImage = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)
            view.glyphText = nil
            view.menu = nil
        }

        private func markerColor(for row: CongressMapRow, isSelected: Bool) -> NSColor {
            if row.isHiddenOnMap {
                return .secondaryLabelColor
            }
            if isSelected {
                return .systemBlue
            }
            // Round 17: the shared congress rule (attending yellow, attended
            // green, not attending grey); a congress without status keeps
            // the blue (white in dark mode) pin.
            let isPast = Calendar.current.startOfDay(for: row.endDate) < Calendar.current.startOfDay(for: Date())
            let tone = AppStatusTones.congress(AppStatusTones.congressStatus(
                isAttending: row.currentUserParticipates,
                isPast: isPast,
                hasContribution: row.hasLinkedAbstractOrContribution,
                hasRejectedContribution: false
            ))
            let dark = AppAppearanceRegistry.usesDarkPalette()
            if tone.hasFill {
                return AppPalette.statusMarkNSColor(tone, dark: dark)
            }
            return dark ? .white : .controlAccentColor
        }

        private func congressLocationKey(for row: CongressMapRow) -> String {
            row.locationCacheKey ?? row.locationQuery ?? "congress:\(row.id)"
        }

        private func clusterLayoutMode(
            for rows: [CongressMapRow],
            cluster: MKClusterAnnotation,
            mapView: MKMapView
        ) -> CongressMapNativeClusterView.LayoutMode {
            guard rows.count > 1 else {
                return .compact
            }

            let labelSizes = rows.map { row in
                CongressMapNativeLabelPill.measuredSize(
                    title: row.title,
                    date: row.startDateText,
                    maximumWidth: 300
                )
            }
            let columnGap: CGFloat = 8
            let availableWidth = mapView.bounds.width * 0.9
            let leftSizes = labelSizes.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
            let rightSizes = labelSizes.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)
            let twoColumnWidth = (leftSizes.map(\.width).max() ?? 0)
                + columnGap
                + (rightSizes.map(\.width).max() ?? 0)
            if !rightSizes.isEmpty,
               twoColumnWidth <= availableWidth {
                return .twoColumns
            }
            return .oneColumn
        }

        private func congressRowSort(_ lhs: CongressMapRow, _ rhs: CongressMapRow) -> Bool {
            if lhs.currentUserParticipates != rhs.currentUserParticipates {
                return lhs.currentUserParticipates && !rhs.currentUserParticipates
            }
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            return lhs.id < rhs.id
        }

        private func visibilityMenu(for annotation: CongressMapNativeAnnotation) -> NSMenu {
            let menu = NSMenu()
            let title = annotation.row.isHiddenOnMap
                ? parent.language.text("Show", "Visa")
                : parent.language.text("Hide", "Dölj")
            let item = NSMenuItem(
                title: title,
                action: #selector(toggleCongressVisibility(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = annotation.id
            menu.addItem(item)
            return menu
        }

        @objc private func toggleCongressVisibility(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let annotation = congressAnnotationsByID[id] else {
                return
            }
            parent.visibilityAction(annotation.row)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let congressMembers = cluster.memberAnnotations.compactMap {
                    $0 as? CongressMapNativeAnnotation
                }
                if let first = congressMembers.sorted(by: congressAnnotationSort).first {
                    let point = mapView.convert(cluster.coordinate, toPointTo: mapView)
                    presentCongressDetails(congressID: first.id, at: point, in: mapView)
                }
                mapView.deselectAnnotation(cluster, animated: false)
                return
            }
            guard let annotation = view.annotation as? CongressMapNativeAnnotation else { return }
            let point = mapView.convert(annotation.coordinate, toPointTo: mapView)
            presentCongressDetails(congressID: annotation.id, at: point, in: mapView)
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            // Appens detaljläge styrs av explicita kartklick, inte av MapKits
            // tillfälliga markeringsstatus som kan ändras vid omklustring.
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            updateLabelVisibility(in: mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            refreshVisibleAnnotationViews(in: mapView)
            parent.onRegionChange(mapView.region)
        }

        private func congressMembersShareCoordinate(
            _ annotations: [CongressMapNativeAnnotation]
        ) -> Bool {
            guard let first = annotations.first else { return false }
            return annotations.dropFirst().allSatisfy {
                abs($0.coordinate.latitude - first.coordinate.latitude) < 0.000_001
                    && abs($0.coordinate.longitude - first.coordinate.longitude) < 0.000_001
            }
        }

        private func congressAnnotationSort(
            _ lhs: CongressMapNativeAnnotation,
            _ rhs: CongressMapNativeAnnotation
        ) -> Bool {
            if lhs.row.currentUserParticipates != rhs.row.currentUserParticipates {
                return lhs.row.currentUserParticipates && !rhs.row.currentUserParticipates
            }
            if lhs.row.startDate != rhs.row.startDate {
                return lhs.row.startDate < rhs.row.startDate
            }
            return lhs.id < rhs.id
        }
    }
}

private struct CongressMapLocationRequest: Hashable {
    let cacheKey: String
    let query: String
}

private enum CongressMapGeocodeOutcome {
    case resolved(CongressMapCoordinate)
    case notFound
    case retryableFailure
}

private struct CongressMapAffiliationLocation: Hashable {
    let id: String
    let kind: CongressMapAffiliationKind
    let placeText: String
    let displayText: String
    let query: String
    let cacheKey: String
}

private enum CongressMapAffiliationKind: String, Hashable {
    case primary
    case secondary
}

private struct CongressMapCoordinate: Codable, Equatable {
    static var cacheDefaultsKey: String {
        AppRuntime.scopedDefaultsKey("CongressMapCoordinateCacheV1")
    }

    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String?

    init(latitude: Double, longitude: Double, timeZoneIdentifier: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct PositionedCongressMapRow: Identifiable {
    let row: CongressMapRow
    let coordinate: CLLocationCoordinate2D

    var id: String { row.id }
    var connectorID: String { "\(row.id)-connector" }
}

private struct ScreenPositionedCongressMapRow {
    let positioned: PositionedCongressMapRow
    let screenPoint: CGPoint
}

private struct CongressMapScreenConnector {
    let start: CGPoint
    let end: CGPoint

    var length: CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}

private struct CongressMapStarObstacle {
    let id: String
    let rect: CGRect
}

private struct CongressMapAnnotationCandidate {
    let offset: CGSize
    let rect: CGRect
    let connector: CongressMapScreenConnector?
    let lineLength: CGFloat
    let baseScore: CGFloat
}

private struct CongressMapPlacedAnnotation {
    let id: String
    let candidate: CongressMapAnnotationCandidate
}

private struct CongressMapAnnotationLayoutSolution {
    let placements: [String: CongressMapAnnotationPlacement]
    let score: CGFloat
}

private struct PositionedCongressMapAnnotation: Identifiable {
    let row: CongressMapRow
    let coordinate: CLLocationCoordinate2D
    let placement: CongressMapAnnotationPlacement

    var id: String { row.id }
    var connectorID: String { "\(row.id)-connector" }
}

private struct PositionedCongressMapAdaptiveLabel: Identifiable {
    let plan: CongressMapAdaptiveLabelPlan
    let row: CongressMapRow
    let screenPoint: CGPoint
    let placement: CongressMapAnnotationPlacement
    let connector: CongressMapScreenConnector?

    var id: String { plan.id }
}

private struct PositionedCongressMapAffiliationAnnotation: Identifiable {
    let location: CongressMapAffiliationLocation
    let coordinate: CLLocationCoordinate2D
    let stackIndex: Int
    let stackCount: Int

    var id: String { location.id }

    var labelOffsetY: CGFloat {
        guard stackCount > 1 else { return 0 }
        return CGFloat(stackIndex) * 20 - CGFloat(stackCount - 1) * 10
    }
}

private enum CongressMapAnnotationMetrics {
    static let calloutWidth: CGFloat = 272
    static let calloutHeight: CGFloat = 78
    static let starSize: CGFloat = 28
    static let starRadius: CGFloat = 14
    static let starProtectionSize: CGFloat = 34
}

private struct CongressMapAnnotationPlacement: Equatable {
    static let defaultOffset = CGSize(width: 0, height: -78)
    static let defaultPlacement = CongressMapAnnotationPlacement(
        calloutOffset: defaultOffset,
        showsConnector: false
    )

    let calloutOffset: CGSize
    let showsConnector: Bool

    var connectorFrameSize: CGSize {
        let endpoint = connectorEndpoint
        return CGSize(
            width: max(620, abs(endpoint.width) * 2 + 90),
            height: max(420, abs(endpoint.height) * 2 + 90)
        )
    }

    var annotationFrameSize: CGSize {
        CGSize(
            width: max(
                CongressMapAnnotationMetrics.calloutWidth + 60,
                abs(calloutOffset.width) * 2 + CongressMapAnnotationMetrics.calloutWidth + 60
            ),
            height: max(
                CongressMapAnnotationMetrics.calloutHeight + 60,
                abs(calloutOffset.height) * 2 + CongressMapAnnotationMetrics.calloutHeight + 60
            )
        )
    }

    var connectorEndpoint: CGSize {
        let offset = calloutOffset
        let halfWidth = CongressMapAnnotationMetrics.calloutWidth / 2
        let halfHeight = CongressMapAnnotationMetrics.calloutHeight / 2
        let edgeOverlap: CGFloat = 3

        if abs(offset.width) >= abs(offset.height) {
            return CGSize(
                width: offset.width > 0 ? offset.width - halfWidth + edgeOverlap : offset.width + halfWidth - edgeOverlap,
                height: min(halfHeight - 10, max(-halfHeight + 10, offset.height))
            )
        }

        return CGSize(
            width: min(halfWidth - 10, max(-halfWidth + 10, offset.width)),
            height: offset.height > 0 ? offset.height - halfHeight + edgeOverlap : offset.height + halfHeight - edgeOverlap
        )
    }
}



private struct CongressMapOverlayConnector: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}


private struct CongressMapAdaptiveCalloutLabel: View {
    let row: CongressMapRow
    let language: AppLanguage
    let kind: CongressMapAdaptiveLabelKind
    let isSelected: Bool
    let action: () -> Void
    let visibilityAction: () -> Void

    var body: some View {
        Button(action: action) {
            callout
        }
        .buttonStyle(.plain)
        .help(helpText)
        .contextMenu {
            Button {
                visibilityAction()
            } label: {
                Label(
                    row.isHiddenOnMap
                        ? language.text("Show", "Visa")
                        : language.text("Hide", "Dölj"),
                    systemImage: row.isHiddenOnMap ? "eye" : "eye.slash"
                )
            }
        }
    }

    private var callout: some View {
        Group {
            switch kind {
            case .congress:
                VStack(alignment: .leading, spacing: 0) {
                    daysRemainingBox
                    congressBox
                }
            case let .cluster(count, placeText):
                clusterBox(count: count, placeText: placeText)
            }
        }
        .frame(width: CongressMapAnnotationMetrics.calloutWidth, alignment: .leading)
        .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 3)
    }

    private func clusterBox(count: Int, placeText: String?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppPalette.actionSave)

            VStack(alignment: .leading, spacing: 2) {
                Text(clusterTitle(count: count, placeText: placeText))
                    .font(appFont(.body).weight(.bold))
                    .lineLimit(1)
                Text(language.text("Click to show the nearest congress", "Klicka för att visa närmaste kongress"))
                    .font(appFont(.secondary).weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text("\(count)")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AppPalette.appText)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppPalette.activeTabSurface.opacity(0.18), in: Capsule())
        }
        .foregroundStyle(AppPalette.appText)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: CongressMapAnnotationMetrics.calloutWidth, alignment: .leading)
        .frame(minHeight: 58, alignment: .leading)
        .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppPalette.border.opacity(0.75), lineWidth: 1)
        )
    }

    private func clusterTitle(count: Int, placeText: String?) -> String {
        if let placeText {
            return "\(placeText) · \(count)"
        }
        return language.text("\(count) congresses nearby", "\(count) kongresser nära varandra")
    }

    private var helpText: String {
        switch kind {
        case .congress:
            return [
                row.title,
                daysRemainingText,
                dateAndPlaceText,
                row.organizationName
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        case let .cluster(count, placeText):
            return clusterTitle(count: count, placeText: placeText)
        }
    }

    private var congressBox: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(dateAndPlaceText)
                    .font(appFont(.secondary).weight(.bold))
                    .lineLimit(1)
                if row.hasUncertainDate {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                if row.isHiddenOnMap {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            Text(row.title)
                .font(appFont(.secondary).weight(.semibold))
                .lineLimit(2)
        }
        .foregroundStyle(AppPalette.appText)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: CongressMapAnnotationMetrics.calloutWidth, alignment: .leading)
        .frame(minHeight: 48, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: 8, bottomTrailing: 8, topTrailing: 0),
                style: .continuous
            )
            .fill(congressBackgroundStyle)
        )
        .overlay(
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: 8, bottomTrailing: 8, topTrailing: 0),
                style: .continuous
            )
                .stroke(isSelected ? AppPalette.actionSave : AppPalette.border.opacity(0.75), lineWidth: isSelected ? 2 : 1)
        )
    }

    private var dateAndPlaceText: String {
        [row.dateText, row.placeText.nonEmpty]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var congressBackgroundStyle: AnyShapeStyle {
        if row.currentUserParticipates {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [AppPalette.vividGreen, AppPalette.shadeGreen],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(AppPalette.cardSurface)
    }

    private var daysRemainingBox: some View {
        Text(daysRemainingText)
            .font(appFont(.secondary).weight(.bold))
            .foregroundStyle(AppPalette.appText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(topLeading: 8, bottomLeading: 0, bottomTrailing: 0, topTrailing: 8),
                    style: .continuous
                )
                    .fill(daysRemainingColor)
            )
            .overlay(
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(topLeading: 8, bottomLeading: 0, bottomTrailing: 0, topTrailing: 8),
                    style: .continuous
                )
                    .stroke(AppPalette.border.opacity(0.55), lineWidth: 1)
            )
    }

    private var daysRemainingText: String {
        let days = daysRemaining
        if language == .swedish {
            return days == 1 ? "1 dag kvar" : "\(days) dagar kvar"
        }
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    private var daysRemaining: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: row.startDate)
        return max(0, calendar.dateComponents([.day], from: today, to: start).day ?? 0)
    }

    private var daysRemainingColor: Color {
        if daysRemaining < 180 {
            return AppPalette.shadeRed
        }
        if daysRemaining < 360 {
            return AppPalette.shadeYellow
        }
        return AppPalette.shadeGreen
    }
}
