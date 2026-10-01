import SwiftUI


struct ProjectGrantTimelineView: View, @preconcurrency Equatable {
    let snapshot: GrantDataStore.ProjectTimelineSnapshot
    let style: ProjectTimelineStyle
    let language: AppLanguage
    let openAction: (GrantDataStore.ProjectTimelineSnapshot.GrantBar) -> Void
    let openPublicationAction: (String) -> Void

    static func == (lhs: ProjectGrantTimelineView, rhs: ProjectGrantTimelineView) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.style == rhs.style
            && lhs.language == rhs.language
    }

    private let headerHeight: CGFloat = 30
    private let rowLabelWidth: CGFloat = 0

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

    private var years: [Int] {
        snapshot.years
    }

    private var totalTimelineWidth: CGFloat {
        CGFloat(years.count) * yearColumnWidth
    }

    private var timelineBodyHeight: CGFloat {
        CGFloat(snapshot.grantBars.count) * rowHeight
            + CGFloat(auxiliaryRowCount) * rowHeight
            + CGFloat(publicationRowCount) * rowHeight
    }

    private var auxiliaryRowCount: Int {
        var count = 0
        if !snapshot.ethicsRows.isEmpty { count += snapshot.ethicsRows.count }
        if !snapshot.dataCollectionRows.isEmpty { count += snapshot.dataCollectionRows.count }
        return count
    }

    private var publicationRowCount: Int {
        snapshot.publicationMarkers.isEmpty ? 0 : 1
    }

    private var totalHeight: CGFloat {
        headerHeight + timelineBodyHeight
    }

    var body: some View {
        if snapshot.grantBars.isEmpty && snapshot.ethicsRows.isEmpty && snapshot.dataCollectionRows.isEmpty && snapshot.publicationMarkers.isEmpty {
            Text(language.text(
                "No granted or submitted applications have timeline data yet.",
                "Inga beviljade eller sökta anslag har tidsdata ännu."
            ))
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 0) {
                        Color.clear
                            .frame(width: rowLabelWidth, height: headerHeight)
                        ForEach(years, id: \.self) { year in
                            Text(String(year))
                                .font(appFont(.body).weight(.medium))
                                .foregroundStyle(.primary)
                                .frame(width: yearColumnWidth, height: headerHeight, alignment: .bottom)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 0) {
                            if !snapshot.ethicsRows.isEmpty {
                                ForEach(Array(snapshot.ethicsRows.enumerated()), id: \.offset) { _, row in
                                    ZStack(alignment: .leading) {
                                        Color.clear
                                            .frame(width: rowLabelWidth + totalTimelineWidth, height: rowHeight)
                                        ForEach(row) { bar in
                                            auxiliaryBar(for: bar)
                                        }
                                    }
                                    .frame(width: rowLabelWidth + totalTimelineWidth, height: rowHeight, alignment: .leading)
                                }
                            }

                            if !snapshot.dataCollectionRows.isEmpty {
                                ForEach(Array(snapshot.dataCollectionRows.enumerated()), id: \.offset) { _, row in
                                    ZStack(alignment: .leading) {
                                        Color.clear
                                            .frame(width: rowLabelWidth + totalTimelineWidth, height: rowHeight)
                                        ForEach(row) { bar in
                                            auxiliaryBar(for: bar)
                                        }
                                    }
                                    .frame(width: rowLabelWidth + totalTimelineWidth, height: rowHeight, alignment: .leading)
                                }
                            }

                            ForEach(snapshot.grantBars) { bar in
                                Button(action: {
                                    openAction(bar)
                                }) {
                                    ZStack(alignment: .leading) {
                                        Color.clear
                                            .frame(width: rowLabelWidth + totalTimelineWidth, height: rowHeight)
                                        timelineBar(for: bar)
                                        decisionMarker(for: bar)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .help(bar.hoverText)
                                .buttonStyle(.plain)
                                .frame(width: rowLabelWidth + totalTimelineWidth, height: rowHeight, alignment: .leading)
                            }

                            if !snapshot.publicationMarkers.isEmpty {
                                ZStack(alignment: .leading) {
                                    Color.clear
                                        .frame(width: rowLabelWidth + totalTimelineWidth, height: rowHeight)
                                    ForEach(snapshot.publicationMarkers) { marker in
                                        publicationMarker(for: marker)
                                    }
                                }
                                .frame(width: rowLabelWidth + totalTimelineWidth, height: rowHeight, alignment: .leading)
                            }
                        }

                        if years.count > 1 {
                            ForEach(Array(years.dropFirst().enumerated()), id: \.offset) { offset, _ in
                                Rectangle()
                                    .fill(AppPalette.border.opacity(0.38))
                                    .frame(width: 0.8, height: timelineBodyHeight)
                                    .offset(x: rowLabelWidth + CGFloat(offset + 1) * yearColumnWidth)
                            }
                        }

                        if let todayMarkerX {
                            Rectangle()
                                .fill(AppPalette.todayMarker)
                                .frame(width: markerWidth, height: timelineBodyHeight)
                                .offset(x: rowLabelWidth + todayMarkerX - markerWidth / 2)
                        }
                    }
                }
                .frame(width: rowLabelWidth + totalTimelineWidth, height: totalHeight, alignment: .topLeading)
            }
            .frame(height: totalHeight)
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

    @ViewBuilder
    private func timelineBar(for entry: GrantDataStore.ProjectTimelineSnapshot.GrantBar) -> some View {
        if let visibleStart = timelineStartDate,
           let visibleEndExclusive = timelineEndDateExclusive {
            let barStartDate = max(entry.start, visibleStart)
            let barEndDate = min(Calendar.current.date(byAdding: .day, value: 1, to: entry.end) ?? entry.end, visibleEndExclusive)
            let startX = xOffset(for: barStartDate)
            let endX = xOffset(for: barEndDate)
            let width = max(endX - startX, 140)
            let text = entry.barText

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: entry.isGranted
                                ? [AppPalette.timelineBarEnd, AppPalette.timelineBarStart]
                                : [AppPalette.timelinePendingBarEnd, AppPalette.timelinePendingBarStart],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Rectangle()
                            .stroke(
                                entry.isGranted ? AppPalette.timelineBarStroke : AppPalette.timelinePendingBarStroke,
                                style: StrokeStyle(lineWidth: 1, dash: entry.hasUncertainOutline ? [5, 3] : [])
                            )
                    )
                    .frame(width: width, height: barHeight)
                    .offset(x: rowLabelWidth + startX, y: max((rowHeight - barHeight) / 2, 0))

                spentOverlay(for: entry, visibleBarStart: barStartDate, visibleBarEnd: barEndDate)

                Text(text)
                    .font(appFont(.secondary).weight(.semibold))
                    .foregroundStyle(AppPalette.statusOnFill)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: max(width - 16, 24), height: barHeight, alignment: .leading)
                    .padding(.leading, 8)
                    .offset(x: rowLabelWidth + startX, y: max((rowHeight - barHeight) / 2, 0))
            }
        }
    }

    @ViewBuilder
    private func spentOverlay(
        for entry: GrantDataStore.ProjectTimelineSnapshot.GrantBar,
        visibleBarStart: Date,
        visibleBarEnd: Date
    ) -> some View {
        if entry.isGranted,
           let fullySpentDate = entry.fullySpentDate {
            let overlayStartDate = max(fullySpentDate, visibleBarStart)
            let overlayStartX = xOffset(for: overlayStartDate)
            let overlayEndX = xOffset(for: visibleBarEnd)
            let overlayWidth = max(overlayEndX - overlayStartX, 0)

            if overlayStartDate < visibleBarEnd, overlayWidth > 0 {
                // Round 17: a fully spent grant stays green, only paler
                // (it used to get grey stripes).
                Rectangle()
                    .fill(AppPalette.statusFillPale(.done))
                    .overlay(
                        Rectangle()
                            .stroke(AppPalette.statusEdge(.done), lineWidth: 1)
                    )
                    .frame(width: overlayWidth, height: barHeight)
                    .offset(x: rowLabelWidth + overlayStartX, y: max((rowHeight - barHeight) / 2, 0))
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func decisionMarker(for entry: GrantDataStore.ProjectTimelineSnapshot.GrantBar) -> some View {
        if let decisionDate = entry.decisionMarkerDate,
           let visibleStart = timelineStartDate,
           let visibleEndExclusive = timelineEndDateExclusive,
           decisionDate >= visibleStart,
           decisionDate < visibleEndExclusive {
            Circle()
                .fill(entry.isGranted ? AppPalette.timelineGrantedMarkerFill : AppPalette.timelineDecisionMarkerFill)
                .overlay(
                    Circle()
                        .stroke(
                            entry.isGranted ? AppPalette.timelineGrantedMarkerStroke : AppPalette.timelineDecisionMarkerStroke,
                            lineWidth: 1
                        )
                )
                .frame(width: 8, height: 8)
                .position(x: rowLabelWidth + xOffset(for: decisionDate), y: rowHeight / 2)
        }
    }

    @ViewBuilder
    private func publicationMarker(for marker: GrantDataStore.ProjectTimelineSnapshot.PublicationMarker) -> some View {
        if let visibleStart = timelineStartDate,
           let visibleEndExclusive = timelineEndDateExclusive,
           marker.date >= visibleStart,
           marker.date < visibleEndExclusive {
            Button(action: {
                openPublicationAction(marker.publicationID)
            }) {
                // Round 17: the Publications tab symbol instead of an emoji.
                Image(systemName: AppTab.publications.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.appText)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(marker.hoverText)
            .position(x: rowLabelWidth + xOffset(for: marker.date), y: rowHeight / 2)
        }
    }

    @ViewBuilder
    private func auxiliaryBar(for bar: GrantDataStore.ProjectTimelineSnapshot.AuxiliaryBar) -> some View {
        if let visibleStart = timelineStartDate,
           let visibleEndExclusive = timelineEndDateExclusive {
            let barStartDate = max(bar.start, visibleStart)
            let barEndDate = min(Calendar.current.date(byAdding: .day, value: 1, to: bar.end) ?? bar.end, visibleEndExclusive)
            let startX = xOffset(for: barStartDate)
            let endX = xOffset(for: barEndDate)
            let width = max(endX - startX, 1)
            let verticalInset = max((rowHeight - barHeight) / 2, 0)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(LinearGradient(colors: auxiliaryColors(for: bar.kind), startPoint: .leading, endPoint: .trailing))
                    .overlay(
                        Rectangle()
                            .stroke(auxiliaryStrokeColor(for: bar.kind), lineWidth: 1)
                    )
                    .frame(width: width, height: barHeight)

                if width >= 56 {
                    Text(bar.title)
                        .font(appFont(.secondary).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: width - 12, height: barHeight, alignment: .leading)
                        .padding(.leading, 6)
                        .clipped()
                }
            }
            .help(bar.title)
            .offset(x: rowLabelWidth + startX, y: verticalInset)
        }
    }

    private func auxiliaryColors(for kind: GrantDataStore.ProjectTimelineSnapshot.AuxiliaryKind) -> [Color] {
        switch kind {
        case .ethics, .dataCollection:
            return [AppPalette.vividBlue, AppPalette.shadeBlue]
        }
    }

    private func auxiliaryStrokeColor(for kind: GrantDataStore.ProjectTimelineSnapshot.AuxiliaryKind) -> Color {
        switch kind {
        case .ethics, .dataCollection:
            return AppPalette.shadeBlue
        }
    }
}

struct StripedTimelineOverlay: View {
    let color: Color
    let lineWidth: CGFloat
    let spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .opacity(0.9)
    }
}
