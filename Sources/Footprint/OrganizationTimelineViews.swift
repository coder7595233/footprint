import SwiftUI

struct OrganizationTimelineView: View {
    let snapshot: GrantDataStore.OrganizationTimelineSnapshot
    let style: ProjectTimelineStyle
    let language: AppLanguage
    let openApplicationAction: (String) -> Void
    let openCongressAction: (String) -> Void

    private static let todayAnchorID = "organization-timeline-today-anchor"

    private let headerHeight: CGFloat = 30
    private let rowLabelWidth: CGFloat = 170
    private let groupSpacing: CGFloat = 8

    private var yearColumnWidth: CGFloat {
        max(CGFloat(style.yearColumnWidth), 320)
    }

    private var rowHeight: CGFloat {
        max(CGFloat(style.rowHeight) * 0.82, 34)
    }

    private var barHeight: CGFloat {
        max(min(CGFloat(style.barHeight), rowHeight - 6), 20)
    }

    private var markerWidth: CGFloat {
        CGFloat(style.markerWidth)
    }

    private var deadlineMarkerSize: CGFloat {
        max(min(CGFloat(style.markerWidth) * 1.9, 12), 9)
    }

    private var minimumVisibleBarWidth: CGFloat {
        6
    }

    private var years: [Int] {
        snapshot.years
    }

    private var totalTimelineWidth: CGFloat {
        CGFloat(years.count) * yearColumnWidth
    }

    private var totalRowCount: Int {
        snapshot.groups.reduce(0) { $0 + $1.rows.count }
    }

    private var bodyHeight: CGFloat {
        CGFloat(totalRowCount) * rowHeight
            + CGFloat(max(snapshot.groups.count - 1, 0)) * groupSpacing
    }

    private var totalHeight: CGFloat {
        headerHeight + bodyHeight
    }

    private var scrollSignature: String {
        let yearSignature = years.map(String.init).joined(separator: ",")
        let groupSignature = snapshot.groups
            .map { group in
                let barSignature = group.bars.map(\.id).joined(separator: ",")
                return "\(group.id):\(barSignature)"
            }
            .joined(separator: "|")
        return "\(yearSignature)#\(groupSignature)"
    }

    var body: some View {
        if snapshot.isEmpty {
            AppCompactEmptyListLabel(title: language.text("No timed organization processes yet", "Inga tidsatta organisationsprocesser än"))
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        headerRow
                        ForEach(Array(snapshot.groups.enumerated()), id: \.element.id) { index, group in
                            groupRows(group)
                            if index < snapshot.groups.count - 1 {
                                Color.clear
                                    .frame(width: rowLabelWidth + totalTimelineWidth, height: groupSpacing)
                            }
                        }
                    }
                    .frame(width: rowLabelWidth + totalTimelineWidth, height: totalHeight, alignment: .topLeading)
                }
                .frame(height: totalHeight)
                .onAppear {
                    scrollToToday(using: proxy)
                }
                .onChange(of: scrollSignature) { _, _ in
                    scrollToToday(using: proxy)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Color.clear
                .frame(width: rowLabelWidth, height: headerHeight)
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year))
                            .font(appFont(.body).weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(width: yearColumnWidth, height: headerHeight, alignment: .bottom)
                    }
                }
                todayScrollAnchor
            }
            .frame(width: totalTimelineWidth, height: headerHeight, alignment: .bottomLeading)
        }
    }

    @ViewBuilder
    private var todayScrollAnchor: some View {
        if let todayMarkerX {
            let anchorX = min(max(todayMarkerX, 0), max(totalTimelineWidth - 1, 0))
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: anchorX, height: 1)
                Color.clear
                    .frame(width: 1, height: 1)
                    .id(Self.todayAnchorID)
                Spacer(minLength: 0)
            }
            .frame(width: totalTimelineWidth, height: 1, alignment: .leading)
        }
    }

    private func groupRows(_ group: GrantDataStore.OrganizationTimelineSnapshot.Group) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(group.rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(alignment: .top, spacing: 0) {
                    Text(rowIndex == 0 ? group.title : "")
                        .font(appFont(.secondary).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(width: rowLabelWidth - 12, height: rowHeight, alignment: .leading)
                        .padding(.trailing, 12)

                    ZStack(alignment: .leading) {
                        Color.clear
                            .frame(width: totalTimelineWidth, height: rowHeight)

                        yearDividers(height: rowHeight)

                        if let todayMarkerX {
                            Rectangle()
                                .fill(AppPalette.todayMarker)
                                .frame(width: markerWidth, height: rowHeight)
                                .offset(x: todayMarkerX - markerWidth / 2)
                        }

                        ForEach(row) { bar in
                            timelineBar(for: bar)
                            ForEach(bar.markers) { marker in
                                timelineMarker(for: marker)
                            }
                        }
                    }
                    .frame(width: totalTimelineWidth, height: rowHeight, alignment: .leading)
                }
                .frame(width: rowLabelWidth + totalTimelineWidth, height: rowHeight, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func timelineMarker(for marker: GrantDataStore.OrganizationTimelineSnapshot.Marker) -> some View {
        if let visibleStart = timelineStartDate,
           let visibleEndExclusive = timelineEndDateExclusive,
           marker.date >= visibleStart,
           marker.date <= visibleEndExclusive {
            let markerX = xOffset(for: marker.date)
            let hitSize = max(deadlineMarkerSize, 18)
            let leadingSpace = min(max(markerX - hitSize / 2, 0), max(totalTimelineWidth - hitSize, 0))
            HStack(alignment: .center, spacing: 0) {
                Color.clear
                    .frame(width: leadingSpace, height: rowHeight)
                    .allowsHitTesting(false)
                ZStack {
                    Color.clear
                        .frame(width: hitSize, height: hitSize)
                    Circle()
                        .fill(markerFillColor(for: marker))
                        .overlay(
                            Circle()
                                .stroke(
                                    markerStrokeColor(for: marker),
                                    style: StrokeStyle(
                                        lineWidth: markerStrokeWidth(for: marker),
                                        dash: marker.hasUncertainOutline ? [3, 2] : []
                                    )
                                )
                        )
                        .frame(width: deadlineMarkerSize, height: deadlineMarkerSize)
                }
                .contentShape(Rectangle())
                .help(marker.hoverText)
                Spacer(minLength: 0)
            }
            .frame(width: totalTimelineWidth, height: rowHeight, alignment: .leading)
        }
    }

    private func scrollToToday(using proxy: ScrollViewProxy) {
        guard todayMarkerX != nil else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(Self.todayAnchorID, anchor: .center)
        }
    }

    @ViewBuilder
    private func yearDividers(height: CGFloat) -> some View {
        if years.count > 1 {
            ForEach(Array(years.dropFirst().enumerated()), id: \.offset) { offset, _ in
                Rectangle()
                    .fill(AppPalette.border.opacity(0.38))
                    .frame(width: 0.8, height: height)
                    .offset(x: CGFloat(offset + 1) * yearColumnWidth)
            }
        }
    }

    @ViewBuilder
    private func timelineBar(for bar: GrantDataStore.OrganizationTimelineSnapshot.Bar) -> some View {
        if let visibleStart = timelineStartDate,
           let visibleEndExclusive = timelineEndDateExclusive {
            let barStartDate = max(bar.start, visibleStart)
            let inclusiveEnd = Calendar.current.date(byAdding: .day, value: 1, to: bar.end) ?? bar.end
            let barEndDate = min(inclusiveEnd, visibleEndExclusive)
            let startX = min(max(xOffset(for: barStartDate), 0), totalTimelineWidth)
            let endX = min(max(xOffset(for: barEndDate), 0), totalTimelineWidth)
            let availableWidth = max(totalTimelineWidth - startX, minimumVisibleBarWidth)
            let width = min(max(endX - startX, minimumVisibleBarWidth), availableWidth)

            HStack(alignment: .center, spacing: 0) {
                Color.clear
                    .frame(width: startX, height: rowHeight)
                    .allowsHitTesting(false)
                if let applicationID = bar.applicationID {
                    Button(action: { openApplicationAction(applicationID) }) {
                        barContent(
                            for: bar,
                            width: width,
                            visibleBarStart: barStartDate,
                            visibleBarEnd: barEndDate
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: width, height: barHeight)
                    .contentShape(Rectangle())
                    .help(bar.hoverText)
                } else if case .congress = bar.kind {
                    Button(action: { openCongressAction(congressID(from: bar)) }) {
                        barContent(
                            for: bar,
                            width: width,
                            visibleBarStart: barStartDate,
                            visibleBarEnd: barEndDate
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: width, height: barHeight)
                    .contentShape(Rectangle())
                    .help(bar.hoverText)
                } else {
                    barContent(
                        for: bar,
                        width: width,
                        visibleBarStart: barStartDate,
                        visibleBarEnd: barEndDate
                    )
                        .frame(width: width, height: barHeight)
                        .contentShape(Rectangle())
                        .help(bar.hoverText)
                }
                Spacer(minLength: 0)
            }
            .frame(width: totalTimelineWidth, height: rowHeight, alignment: .leading)
        }
    }

    private func congressID(from bar: GrantDataStore.OrganizationTimelineSnapshot.Bar) -> String {
        let prefix = "congress-"
        guard bar.id.hasPrefix(prefix) else { return bar.id }
        return String(bar.id.dropFirst(prefix.count))
    }

    private func barContent(
        for bar: GrantDataStore.OrganizationTimelineSnapshot.Bar,
        width: CGFloat,
        visibleBarStart: Date,
        visibleBarEnd: Date
    ) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(LinearGradient(colors: colors(for: bar), startPoint: .leading, endPoint: .trailing))
                .overlay(
                    Rectangle()
                        .stroke(
                            strokeColor(for: bar),
                            style: StrokeStyle(lineWidth: 1, dash: bar.hasUncertainOutline ? [5, 3] : [])
                        )
                )
                .frame(width: width, height: barHeight)

            spentOverlay(
                for: bar,
                visibleBarStart: visibleBarStart,
                visibleBarEnd: visibleBarEnd,
                visibleStartX: xOffset(for: visibleBarStart)
            )

            if width >= 44 {
                Text(bar.title)
                    .font(appFont(.secondary).weight(.semibold))
                    .foregroundStyle(textColor(for: bar))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: max(width - 16, 0), height: barHeight, alignment: .leading)
                    .padding(.leading, 8)
                    .clipped()
            }
        }
        .frame(width: width, height: barHeight, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func spentOverlay(
        for bar: GrantDataStore.OrganizationTimelineSnapshot.Bar,
        visibleBarStart: Date,
        visibleBarEnd: Date,
        visibleStartX: CGFloat
    ) -> some View {
        if isGrantedGrant(bar),
           let fullySpentDate = bar.fullySpentDate {
            let overlayStartDate = max(fullySpentDate, visibleBarStart)
            let overlayStartX = xOffset(for: overlayStartDate) - visibleStartX
            let overlayEndX = xOffset(for: visibleBarEnd) - visibleStartX
            let overlayWidth = max(overlayEndX - overlayStartX, 0)

            if overlayStartDate < visibleBarEnd, overlayWidth > 0 {
                StripedTimelineOverlay(color: AppPalette.statusText(.inactive), lineWidth: 2, spacing: 8)
                    .frame(width: overlayWidth, height: barHeight)
                    .offset(x: overlayStartX)
                    .allowsHitTesting(false)
            }
        }
    }

    private var todayMarkerX: CGFloat? {
        guard let timelineStartDate, let timelineEndDateExclusive else { return nil }
        let now = Date()
        guard now >= timelineStartDate && now <= timelineEndDateExclusive else { return nil }
        return xOffset(for: now)
    }

    private var timelineStartDate: Date? {
        years.first.flatMap { yearStart(for: $0) }
    }

    private var timelineEndDateExclusive: Date? {
        guard let lastYear = years.last else { return nil }
        return yearStart(for: lastYear + 1)
    }

    private func yearStart(for year: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1))
    }

    private func xOffset(for date: Date) -> CGFloat {
        guard let timelineStartDate, let timelineEndDateExclusive else { return 0 }
        let clamped = min(max(date, timelineStartDate), timelineEndDateExclusive)
        let duration = timelineEndDateExclusive.timeIntervalSince(timelineStartDate)
        guard duration > 0 else { return 0 }
        let progress = clamped.timeIntervalSince(timelineStartDate) / duration
        return CGFloat(progress) * totalTimelineWidth
    }

    private func colors(for bar: GrantDataStore.OrganizationTimelineSnapshot.Bar) -> [Color] {
        switch bar.kind {
        case .congress:
            return [AppPalette.vividBlue, AppPalette.shadeBlue]
        case .employment:
            return [AppPalette.vividBlue, AppPalette.shadeBlue]
        case .grantProviderGrant(let status), .fundManagerGrant(let status):
            return grantColors(for: status)
        }
    }

    private func grantColors(for status: GrantDataStore.OrganizationTimelineSnapshot.GrantStatus) -> [Color] {
        switch status {
        case .granted:
            return [AppPalette.timelineBarEnd, AppPalette.timelineBarStart]
        case .waiting:
            return [AppPalette.timelinePendingBarEnd, AppPalette.timelinePendingBarStart]
        case .rejected:
            return [AppPalette.statsCardDeclinedStart, AppPalette.statsCardDeclinedEnd]
        case .toApply:
            // Round 16: no status yet = no colour (blue is not a status).
            return [AppPalette.secondaryCardSurface, AppPalette.secondaryCardSurface]
        }
    }

    private func strokeColor(for bar: GrantDataStore.OrganizationTimelineSnapshot.Bar) -> Color {
        switch bar.kind {
        case .congress:
            return AppPalette.shadeBlue
        case .employment:
            return AppPalette.shadeBlue
        case .grantProviderGrant(let status), .fundManagerGrant(let status):
            switch status {
            case .granted:
                return AppPalette.timelineBarStroke
            case .waiting:
                return AppPalette.timelinePendingBarStroke
            case .rejected:
                return AppPalette.statsCardDeclinedStart
            case .toApply:
                return AppPalette.border
            }
        }
    }

    private func isGrantedGrant(_ bar: GrantDataStore.OrganizationTimelineSnapshot.Bar) -> Bool {
        switch bar.kind {
        case .grantProviderGrant(.granted), .fundManagerGrant(.granted):
            return true
        case .congress, .employment, .grantProviderGrant(_), .fundManagerGrant(_):
            return false
        }
    }

    private func textColor(for bar: GrantDataStore.OrganizationTimelineSnapshot.Bar) -> Color {
        switch bar.kind {
        case .grantProviderGrant(.toApply), .fundManagerGrant(.toApply):
            return AppPalette.appText
        default:
            return AppPalette.statusOnFill
        }
    }

    private func markerFillColor(for marker: GrantDataStore.OrganizationTimelineSnapshot.Marker) -> Color {
        switch marker.kind {
        case .congressAbstractDeadline, .congressLateAbstractDeadline:
            return AppPalette.vividBlue
        }
    }

    private func markerStrokeColor(for marker: GrantDataStore.OrganizationTimelineSnapshot.Marker) -> Color {
        switch marker.kind {
        case .congressAbstractDeadline:
            return AppPalette.shadeBlue
        case .congressLateAbstractDeadline:
            return AppPalette.statusText(.negative)
        }
    }

    private func markerStrokeWidth(for marker: GrantDataStore.OrganizationTimelineSnapshot.Marker) -> CGFloat {
        switch marker.kind {
        case .congressAbstractDeadline:
            return 1.4
        case .congressLateAbstractDeadline:
            return 2
        }
    }
}
