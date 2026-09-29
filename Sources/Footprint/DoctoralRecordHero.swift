import AppKit
import SwiftUI

/// The doctoral record page's hero: a project-style timeline (milestones,
/// activities, papers, courses, supervision) with progress rings to the right.
/// Milestone nodes open a popover for date + status editing; papers and
/// activity markers open their underlying records. The layout rules (label
/// lanes, grouping of close activities, the year axis) live in
/// `DoctoralTimelineLayout` so they can be tested.
struct DoctoralRecordHeroView: View {
    @ObservedObject var store: GrantDataStore
    let candidate: DoctoralCandidateRecord
    let isLocked: Bool
    let language: AppLanguage

    @Binding var admissionDate: String
    @Binding var admissionPreliminary: Bool
    @Binding var admissionOutcomeRaw: String?
    @Binding var planningSeminarDate: String
    @Binding var planningSeminarPreliminary: Bool
    @Binding var planningSeminarOutcomeRaw: String?
    @Binding var halftimeDate: String
    @Binding var halftimePreliminary: Bool
    @Binding var halftimeOutcomeRaw: String?
    @Binding var estimatedHalftimeDate: String
    @Binding var disputationDate: String
    @Binding var disputationPreliminary: Bool
    @Binding var disputationOutcomeRaw: String?
    @Binding var plannedDisputationDate: String

    @State private var activeMilestone: DoctoralHeroMilestone.Kind?
    @State private var activeActivityGroupID: String?
    @State private var plotWidth: CGFloat = 0

    private static let todayMarkerColor = Color(red: 0.98, green: 0.08, blue: 0.08)
    private static let laneLabelWidth: CGFloat = 100
    private static let ringsColumnWidth: CGFloat = 236
    private static let yearLabelHeight: CGFloat = 24
    private static let courseCreditGoal: Double = 30
    private static let publicationGoal = 4
    private static let milestoneNodeSize: CGFloat = 18
    private static let activityDotSize: CGFloat = 12
    private static let activityGroupSize: CGFloat = 24
    /// Activities closer than this (in points) share one marker with a count.
    private static let activityGroupWindow: Double = 2 * Double(activityGroupSize + 4)

    // MARK: - Data

    private var linkedPublications: [PublicationRecord] {
        candidate.linkedPublicationIDs
            .compactMap(store.publication(id:))
            .sorted {
                if $0.sortYear != $1.sortYear { return $0.sortYear < $1.sortYear }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    private var yearlyRows: [DoctoralStatisticsYearRow] {
        doctoralStatisticsYearRows(
            candidate: candidate,
            publications: linkedPublications,
            journalForPublication: { store.linkedJournal(of: $0) }
        )
    }

    /// Every activity and task linked to the candidate, earlier ones included.
    /// Round 7 ("alla kopplingar via id"): only the explicit doctoral candidate
    /// links count. Activities the old rule found through the candidate's
    /// project or name are suggested for linking under Data quality instead.
    private var activityRows: [CalendarLinkedEventRow] {
        calendarLinkedEventRows(
            store: store,
            language: language,
            scope: .doctoralCandidate(candidate.id),
            includesTasks: true,
            includesPastEvents: true
        )
        .sorted { $0.displayDate < $1.displayDate }
    }

    private var grantApplications: [GrantApplication] {
        guard let project = store.project(id: candidate.linkedProjectID) else { return [] }
        return store.applications(forProjectName: project.nameSv.nonEmpty ?? project.nameEn.nonEmpty)
    }

    private var milestones: [DoctoralHeroMilestone] {
        var result: [DoctoralHeroMilestone] = []
        func resolved(_ actual: String, _ fallback: String?) -> (String, Bool)? {
            if let date = actual.trimmedOrNil { return (date, false) }
            if let fallback, let date = fallback.trimmedOrNil { return (date, true) }
            return nil
        }
        if let (date, _) = resolved(admissionDate, nil) {
            result.append(DoctoralHeroMilestone(
                kind: .admission,
                title: language.text("Admission", "Antagning"),
                dateText: date,
                isEstimated: false,
                status: .current(preliminary: admissionPreliminary, outcomeRaw: admissionOutcomeRaw)
            ))
        }
        if let (date, _) = resolved(planningSeminarDate, nil) {
            result.append(DoctoralHeroMilestone(
                kind: .planningSeminar,
                title: language.text("Planning seminar", "Planeringsseminarium"),
                dateText: date,
                isEstimated: false,
                status: .current(preliminary: planningSeminarPreliminary, outcomeRaw: planningSeminarOutcomeRaw)
            ))
        }
        if let (date, isEstimated) = resolved(halftimeDate, estimatedHalftimeDate) {
            result.append(DoctoralHeroMilestone(
                kind: .halftime,
                title: language.text("Halftime", "Halvtid"),
                dateText: date,
                isEstimated: isEstimated,
                status: .current(preliminary: halftimePreliminary || isEstimated, outcomeRaw: halftimeOutcomeRaw)
            ))
        }
        if let (date, isEstimated) = resolved(disputationDate, plannedDisputationDate) {
            result.append(DoctoralHeroMilestone(
                kind: .disputation,
                title: language.text("Doctoral defence", "Disputation"),
                dateText: date,
                isEstimated: isEstimated,
                status: .current(preliminary: disputationPreliminary || isEstimated, outcomeRaw: disputationOutcomeRaw)
            ))
        }
        return result
    }

    private static func courseBars(_ rows: [DoctoralStatisticsYearRow]) -> [DoctoralHeroBar] {
        rows.filter { $0.courseCredits > 0 }.map { DoctoralHeroBar(year: $0.year, value: $0.courseCredits) }
    }

    private static func supervisionBars(_ rows: [DoctoralStatisticsYearRow]) -> [DoctoralHeroBar] {
        rows.filter { $0.supervisionHours > 0 }.map { DoctoralHeroBar(year: $0.year, value: $0.supervisionHours) }
    }

    private var todayFraction: Double {
        doctoralHeroYearFraction(of: Date())
    }

    /// Everything the timeline draws, read once per update.
    private struct HeroData {
        var milestones: [DoctoralHeroMilestone]
        var activities: [CalendarLinkedEventRow]
        var publications: [PublicationRecord]
        var courseBars: [DoctoralHeroBar]
        var supervisionBars: [DoctoralHeroBar]
        var yearlyRows: [DoctoralStatisticsYearRow]
        var yearRange: ClosedRange<Int>?
    }

    private func paperYearFraction(_ publication: PublicationRecord) -> Double {
        publication.yearValue.map { Double($0) + 0.5 } ?? todayFraction
    }

    private var heroData: HeroData {
        let rows = self.yearlyRows
        let publications = self.linkedPublications
        let milestones = self.milestones
        let activities = self.activityRows
        let courseBars = Self.courseBars(rows)
        let supervisionBars = Self.supervisionBars(rows)
        var years: [Int] = []
        years += milestones.compactMap { doctoralHeroYearFraction(from: $0.dateText).map { Int($0) } }
        years += courseBars.map(\.year)
        years += supervisionBars.map(\.year)
        years += activities.map { Calendar.current.component(.year, from: $0.displayDate) }
        years += publications.map { Int(paperYearFraction($0)) }
        return HeroData(
            milestones: milestones,
            activities: activities,
            publications: publications,
            courseBars: courseBars,
            supervisionBars: supervisionBars,
            yearlyRows: rows,
            yearRange: DoctoralTimelineLayout.axisYears(years)
        )
    }

    // MARK: - Body

    var body: some View {
        let data = heroData
        if let yearRange = data.yearRange {
            HStack(alignment: .top, spacing: 22) {
                timeline(data: data, yearRange: yearRange)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                ringsColumn(data: data)
                    .frame(width: Self.ringsColumnWidth, alignment: .topLeading)
                    .padding(.top, Self.yearLabelHeight)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(AppPalette.subtleBorder)
                            .frame(width: 1)
                            .padding(.vertical, 6)
                    }
            }
        } else {
            Text(language.text(
                "Set the admission, halftime and defence dates to draw the timeline.",
                "Ange datum för antagning, halvtid och disputation för att rita tidslinjen."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Rings

    private func ringsColumn(data: HeroData) -> some View {
        let rows = data.yearlyRows
        let publications = data.publications
        let completedCredits = rows.map(\.completedCourseCredits).reduce(0, +)
        let creditGoal = max(Self.courseCreditGoal, rows.map(\.courseCredits).reduce(0, +))
        let publishedCount = publications.filter(\.isPublished).count
        let publicationGoal = max(Self.publicationGoal, publications.count)
        let completedHours = rows.map(\.completedSupervisionHours).reduce(0, +)
        let totalHours = rows.map(\.supervisionHours).reduce(0, +)

        return VStack(alignment: .leading, spacing: 6) {
            DoctoralHeroRingRow(
                label: language.text("Course credits", "Högskolepoäng"),
                value: doctoralStatisticsNumber(completedCredits, language: language),
                sub: language.text(
                    "of \(doctoralStatisticsNumber(creditGoal, language: language)) cr",
                    "av \(doctoralStatisticsNumber(creditGoal, language: language)) hp"
                ),
                color: StatisticsEditorialStyle.paletteGreen,
                fraction: creditGoal > 0 ? completedCredits / creditGoal : 0
            )
            DoctoralHeroRingRow(
                label: language.text("Papers", "Delarbeten"),
                value: "\(publishedCount)",
                sub: publishedCount == publications.count
                    ? language.text("published of \(publicationGoal)", "publicerade av \(publicationGoal)")
                    : language.text(
                        "published of \(publicationGoal) · \(publications.count) linked",
                        "publicerade av \(publicationGoal) · \(publications.count) länkade"
                    ),
                color: StatisticsEditorialStyle.paletteOrange,
                fraction: Double(publishedCount) / Double(publicationGoal)
            )
            DoctoralHeroRingRow(
                label: language.text("Supervision", "Handledning"),
                value: doctoralStatisticsNumber(completedHours, language: language),
                sub: language.text(
                    "h done of \(doctoralStatisticsNumber(totalHours, language: language)) h",
                    "h genomförda av \(doctoralStatisticsNumber(totalHours, language: language)) h"
                ),
                color: StatisticsEditorialStyle.palettePurple,
                fraction: totalHours > 0 ? completedHours / totalHours : 0
            )
            grantRow
        }
        .padding(.leading, 22)
    }

    private var grantRow: some View {
        let applications = grantApplications
        let granted = applications.filter { $0.derivedResult == "Beviljat" }
        let grantedTotal = granted.compactMap(\.grantedAmountValue).reduce(0, +)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(language.text("Grants", "Anslag"))
                .font(appFont(.secondary).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: DoctoralHeroRingRow.labelWidth, alignment: .trailing)
            if applications.isEmpty {
                Text(language.text("None", "Inga"))
                    .appTypography(.body)
                    .foregroundStyle(AppPalette.appText)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(doctoralStatisticsNumber(grantedTotal / 1_000_000, language: language) + " mkr")
                        .font(appFont(.body).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppPalette.appText)
                    Text(language.text(
                        "\(granted.count) awarded of \(applications.count)",
                        "\(granted.count) beviljade av \(applications.count)"
                    ))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Timeline geometry

    private struct MilestonePlacement: Identifiable {
        let milestone: DoctoralHeroMilestone
        let x: CGFloat
        let labelStart: CGFloat
        let labelWidth: CGFloat
        let anchorsTrailing: Bool
        let lane: Int

        var id: DoctoralHeroMilestone.Kind { milestone.kind }
    }

    private struct PaperPlacement: Identifiable {
        let publication: PublicationRecord
        let label: String
        let x: CGFloat
        let lane: Int

        var id: String { publication.id }
    }

    private struct ActivityMarker: Identifiable {
        let id: String
        let x: CGFloat
        let rows: [CalendarLinkedEventRow]
        let doneCount: Int

        var isGroup: Bool { rows.count > 1 }
        var allDone: Bool { doneCount == rows.count }
        var noneDone: Bool { doneCount == 0 }
    }

    private struct TimelineGeometry {
        var milestones: [MilestonePlacement] = []
        var milestoneRowY: CGFloat = 0
        var labelHeight: CGFloat = 0
        var labelBlock: CGFloat = 0
        var activitiesY: CGFloat?
        var activityMarkers: [ActivityMarker] = []
        var papers: [PaperPlacement] = []
        var papersTopY: CGFloat?
        var paperLaneHeight: CGFloat = 0
        var coursesBase: CGFloat?
        var coursesHeight: CGFloat = 72
        var supervisionBase: CGFloat?
        var supervisionHeight: CGFloat = 58
        var height: CGFloat = 60

        /// Top edge of a milestone label. Even lanes go below the node row,
        /// odd lanes above it, so labels alternate instead of colliding.
        func labelTop(lane: Int) -> CGFloat {
            let row = CGFloat(lane / 2)
            let gap = DoctoralRecordHeroView.milestoneNodeSize / 2 + 4
            if lane % 2 == 0 {
                return milestoneRowY + gap + row * labelBlock
            }
            return milestoneRowY - gap - row * labelBlock - labelHeight
        }
    }

    private static var milestoneTitleNSFont: NSFont {
        NSFont.systemFont(ofSize: appNSFont(.body).pointSize, weight: .semibold)
    }

    private static var captionNSFont: NSFont {
        appNSFont(.secondary)
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func xPosition(_ fraction: Double, yearRange: ClosedRange<Int>, width: CGFloat) -> CGFloat {
        let span = Double(yearRange.upperBound + 1 - yearRange.lowerBound)
        let clamped = min(max(fraction, Double(yearRange.lowerBound)), Double(yearRange.upperBound + 1))
        return CGFloat((clamped - Double(yearRange.lowerBound)) / span) * width
    }

    private func timelineGeometry(data: HeroData, yearRange: ClosedRange<Int>, width: CGFloat) -> TimelineGeometry {
        func x(_ fraction: Double) -> CGFloat {
            Self.xPosition(fraction, yearRange: yearRange, width: width)
        }
        var geometry = TimelineGeometry()
        let titleFont = Self.milestoneTitleNSFont
        let captionFont = Self.captionNSFont
        geometry.labelHeight = ceil(titleFont.pointSize * 1.3 + captionFont.pointSize * 1.3) + 2
        geometry.labelBlock = geometry.labelHeight + 6

        // Milestones: nodes on one row, labels in lanes that never overlap.
        let nodeInset = Double(Self.milestoneNodeSize / 2)
        let prepared = data.milestones.compactMap { milestone -> (DoctoralHeroMilestone, CGFloat, CGFloat)? in
            guard let fraction = doctoralHeroYearFraction(from: milestone.dateText) else { return nil }
            let labelWidth = max(
                Self.textWidth(milestone.title, font: titleFont),
                Self.textWidth(milestoneDateCaption(milestone), font: captionFont)
            ) + 6
            return (milestone, x(fraction), labelWidth)
        }
        let spans = prepared.map { item in
            DoctoralTimelineLayout.labelSpan(
                nodeX: Double(item.1),
                labelWidth: Double(item.2),
                plotWidth: Double(width),
                inset: nodeInset
            )
        }
        let lanes = DoctoralTimelineLayout.lanes(for: spans.map { $0.span }, gap: 12)
        let maxLane = lanes.max() ?? 0
        let rowsAbove = CGFloat((maxLane + 1) / 2)
        let rowsBelow = CGFloat(maxLane / 2 + 1)
        let nodeHalf = Self.milestoneNodeSize / 2
        geometry.milestoneRowY = 6 + rowsAbove * geometry.labelBlock + nodeHalf + (rowsAbove > 0 ? 4 : 0)
        geometry.milestones = prepared.indices.map { index in
            MilestonePlacement(
                milestone: prepared[index].0,
                x: prepared[index].1,
                labelStart: CGFloat(spans[index].span.lowerBound),
                labelWidth: prepared[index].2,
                anchorsTrailing: spans[index].anchorsTrailing,
                lane: lanes[index]
            )
        }
        var y = geometry.milestoneRowY + nodeHalf + 4 + rowsBelow * geometry.labelBlock

        // Activities: close ones share one marker with a count.
        if !data.activities.isEmpty {
            geometry.activitiesY = y + 16
            let today = Calendar.current.startOfDay(for: Date())
            let positions = data.activities.map { Double(x(doctoralHeroYearFraction(of: $0.displayDate))) }
            let groups = DoctoralTimelineLayout.clusters(positions: positions, window: Self.activityGroupWindow)
            geometry.activityMarkers = groups.map { group in
                let rows = group.map { data.activities[$0] }
                let groupPositions = group.map { positions[$0] }
                let center = (groupPositions.min()! + groupPositions.max()!) / 2
                return ActivityMarker(
                    id: rows.map(\.id).joined(separator: "|"),
                    x: CGFloat(center),
                    rows: rows,
                    doneCount: rows.filter { $0.displayDate < today }.count
                )
            }
            y += 36
        }

        // Papers: markers that would overlap stack in lanes.
        if !data.publications.isEmpty {
            let labelFont = NSFont.systemFont(ofSize: captionFont.pointSize, weight: .semibold)
            let items: [(PublicationRecord, String, CGFloat)] = data.publications.enumerated().map { item in
                (item.element, "P\(item.offset + 1)", x(paperYearFraction(item.element)))
            }
            let paperSpans = items.map { item -> ClosedRange<Double> in
                let half = Double(max(16, Self.textWidth(item.1, font: labelFont)) / 2 + 3)
                return (Double(item.2) - half)...(Double(item.2) + half)
            }
            let paperLanes = DoctoralTimelineLayout.lanes(for: paperSpans, gap: 4)
            geometry.paperLaneHeight = 16 + ceil(captionFont.pointSize * 1.3) + 6
            geometry.papersTopY = y + 4
            geometry.papers = items.indices.map { index in
                PaperPlacement(
                    publication: items[index].0,
                    label: items[index].1,
                    x: items[index].2,
                    lane: paperLanes[index]
                )
            }
            y += 4 + CGFloat((paperLanes.max() ?? 0) + 1) * geometry.paperLaneHeight + 4
        }

        if !data.courseBars.isEmpty {
            y += geometry.coursesHeight
            geometry.coursesBase = y
            y += 8
        }
        if !data.supervisionBars.isEmpty {
            y += geometry.supervisionHeight
            geometry.supervisionBase = y
            y += 4
        }
        geometry.height = max(y, 60)
        return geometry
    }

    // MARK: - Timeline

    private func timeline(data: HeroData, yearRange: ClosedRange<Int>) -> some View {
        let width = plotWidth > 0 ? plotWidth : 640
        let geometry = timelineGeometry(data: data, yearRange: yearRange, width: width)
        let totalHeight = Self.yearLabelHeight + geometry.height
        return HStack(alignment: .top, spacing: 8) {
            laneLabels(geometry: geometry)
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: totalHeight)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { plotWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, newWidth in
                                plotWidth = newWidth
                            }
                    }
                )
                .overlay(alignment: .topLeading) {
                    timelinePlot(data: data, width: width, yearRange: yearRange, geometry: geometry)
                }
        }
    }

    private func laneLabels(geometry: TimelineGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            laneLabel(language.text("Milestones", "Milstolpar"), y: geometry.milestoneRowY)
            if let y = geometry.activitiesY {
                laneLabel(language.text("Activities", "Aktiviteter"), y: y)
            }
            if let top = geometry.papersTopY {
                laneLabel(language.text("Papers", "Delarbeten"), y: top + geometry.paperLaneHeight / 2)
            }
            if let base = geometry.coursesBase {
                laneLabel(language.text("Courses", "Kurser"), y: base - 14)
            }
            if let base = geometry.supervisionBase {
                laneLabel(language.text("Supervision", "Handledning"), y: base - 14)
            }
        }
        .frame(width: Self.laneLabelWidth, height: Self.yearLabelHeight + geometry.height)
    }

    private func laneLabel(_ text: String, y: CGFloat) -> some View {
        Text(text)
            .appTypography(.body)
            .foregroundStyle(AppPalette.appText)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: Self.laneLabelWidth, alignment: .leading)
            .position(x: Self.laneLabelWidth / 2, y: Self.yearLabelHeight + y)
    }

    private func timelinePlot(
        data: HeroData,
        width: CGFloat,
        yearRange: ClosedRange<Int>,
        geometry: TimelineGeometry
    ) -> some View {
        func x(_ fraction: Double) -> CGFloat {
            Self.xPosition(fraction, yearRange: yearRange, width: width)
        }
        func yearSpanX(_ year: Int, inset: Double) -> (CGFloat, CGFloat) {
            (x(Double(year) + inset), x(Double(year) + 1 - inset))
        }
        let top = Self.yearLabelHeight

        return ZStack(alignment: .topLeading) {
            // Fixes the drawing area; no fill of its own, so the timeline
            // sits on the same background as the rest of the page.
            Color.clear
                .frame(width: width, height: top + geometry.height)

            // Year labels and a thin line under them
            ForEach(yearRange, id: \.self) { year in
                Text(String(year))
                    .font(appFont(.secondary).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .position(x: x(Double(year) + 0.5), y: top / 2 - 2)
            }
            Rectangle()
                .fill(AppPalette.subtleBorder)
                .frame(width: width, height: 1)
                .offset(y: top - 1)

            // Today marker (same red as the project timeline), behind the markers
            if todayFraction > Double(yearRange.lowerBound), todayFraction < Double(yearRange.upperBound + 1) {
                Rectangle()
                    .fill(Self.todayMarkerColor)
                    .frame(width: 2.4, height: geometry.height)
                    .offset(x: x(todayFraction) - 1.2, y: top)
                    .allowsHitTesting(false)
            }

            // Courses
            if let base = geometry.coursesBase {
                let maxCredits = data.courseBars.map(\.value).max() ?? 1
                ForEach(data.courseBars) { bar in
                    let (xa, xb) = yearSpanX(bar.year, inset: 0.08)
                    let h = max(8, CGFloat(bar.value / max(maxCredits, 1)) * (geometry.coursesHeight - 24))
                    Rectangle()
                        .fill(LinearGradient(colors: [AppPalette.timelineBarEnd, AppPalette.timelineBarStart], startPoint: .bottom, endPoint: .top))
                        .overlay(Rectangle().stroke(AppPalette.timelineBarStroke, lineWidth: 1))
                        .frame(width: xb - xa, height: h)
                        .offset(x: xa, y: top + base - h)
                    Text(doctoralStatisticsNumber(bar.value, language: language) + " hp")
                        .font(appFont(.secondary).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppPalette.appText)
                        .fixedSize()
                        .position(x: (xa + xb) / 2, y: top + base - h - 10)
                }
            }

            // Supervision blocks
            if let base = geometry.supervisionBase {
                let maxHours = data.supervisionBars.map(\.value).max() ?? 1
                ForEach(data.supervisionBars) { bar in
                    let (xa, xb) = yearSpanX(bar.year, inset: 0.08)
                    let h = max(9, CGFloat(bar.value / max(maxHours, 1)) * (geometry.supervisionHeight - 16))
                    let hoursText = doctoralStatisticsNumber(bar.value, language: language) + " h"
                    ZStack {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [StatisticsEditorialStyle.palettePurple.opacity(0.45), StatisticsEditorialStyle.palettePurple],
                                startPoint: .bottom,
                                endPoint: .top
                            ))
                            .overlay(Rectangle().stroke(StatisticsEditorialStyle.palettePurple.opacity(0.9), lineWidth: 1))
                        if h >= 18 {
                            Text(hoursText)
                                .font(appFont(.secondary).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(AppPalette.appText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(width: xb - xa, height: h)
                    .help(hoursText)
                    .offset(x: xa, y: top + base - h)
                }
            }

            // Activities (single dots, or one marker with a count for close ones)
            if let rowY = geometry.activitiesY {
                ForEach(geometry.activityMarkers) { marker in
                    activityMarkerView(marker)
                        .position(x: marker.x, y: top + rowY)
                }
            }

            // Paper markers
            if let papersTop = geometry.papersTopY {
                ForEach(geometry.papers) { paper in
                    paperMarkerView(paper)
                        .position(
                            x: paper.x,
                            y: top + papersTop + CGFloat(paper.lane) * geometry.paperLaneHeight + geometry.paperLaneHeight / 2
                        )
                }
            }

            // Milestones: nodes on one row, labels in their own lanes.
            ForEach(geometry.milestones) { placement in
                milestoneLabelButton(placement, geometry: geometry)
                    .offset(x: placement.labelStart, y: top + geometry.labelTop(lane: placement.lane))
                milestoneNode(placement.milestone)
                    .position(x: placement.x, y: top + geometry.milestoneRowY)
            }
        }
        .frame(width: width, height: top + geometry.height, alignment: .topLeading)
    }

    // MARK: - Milestones

    private func milestoneNode(_ milestone: DoctoralHeroMilestone) -> some View {
        let isDone = milestone.status == .completed
        let isEndedBefore = milestone.status == .endedBefore
        let isTentative = milestone.status == .preliminary || milestone.isEstimated
        return Button {
            guard !isLocked else { return }
            activeMilestone = milestone.kind
        } label: {
            ZStack {
                if isDone || isEndedBefore {
                    Circle()
                        .fill(isEndedBefore ? AppPalette.vividRed : AppPalette.vividGreen)
                    Image(systemName: isEndedBefore ? "xmark" : "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .fill(AppPalette.detailPanelSurface)
                    Circle()
                        .stroke(
                            Color.secondary.opacity(0.8),
                            style: isTentative
                                ? StrokeStyle(lineWidth: 1.5, dash: [3, 2.4])
                                : StrokeStyle(lineWidth: 1.5)
                        )
                }
            }
            .frame(width: Self.milestoneNodeSize, height: Self.milestoneNodeSize)
            .contentShape(Circle().scale(1.6))
        }
        .buttonStyle(.plain)
        .help(milestoneHelpText(milestone))
        .popover(isPresented: milestonePopoverBinding(milestone.kind), arrowEdge: .bottom) {
            DoctoralMilestonePopover(
                title: milestone.title,
                date: milestoneDateBinding(milestone.kind),
                preliminary: milestonePreliminaryBinding(milestone.kind),
                outcomeRaw: milestoneOutcomeBinding(milestone.kind),
                allowsEndedBefore: milestone.kind == .halftime || milestone.kind == .disputation,
                language: language
            )
        }
    }

    private func milestoneLabelButton(_ placement: MilestonePlacement, geometry: TimelineGeometry) -> some View {
        let milestone = placement.milestone
        let horizontal: HorizontalAlignment = placement.anchorsTrailing ? .trailing : .leading
        let isAbove = placement.lane % 2 == 1
        let frameAlignment: Alignment
        switch (placement.anchorsTrailing, isAbove) {
        case (false, false): frameAlignment = .topLeading
        case (false, true): frameAlignment = .bottomLeading
        case (true, false): frameAlignment = .topTrailing
        case (true, true): frameAlignment = .bottomTrailing
        }
        return Button {
            guard !isLocked else { return }
            activeMilestone = milestone.kind
        } label: {
            VStack(alignment: horizontal, spacing: 1) {
                Text(milestone.title)
                    .font(appFont(.body).weight(.semibold))
                    .foregroundStyle(AppPalette.appText)
                Text(milestoneDateCaption(milestone))
                    .appTypography(.secondary)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize()
            // Covers the red today line behind the text.
            .background(AppPalette.detailPanelSurface)
            .frame(width: placement.labelWidth, height: geometry.labelHeight, alignment: frameAlignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(milestoneHelpText(milestone))
    }

    /// Written status next to the date: Preliminärt, Bokat, Genomfört,
    /// Avslutat innan, or Beräknat for a date that is only an estimate.
    private func milestoneStatusWord(_ milestone: DoctoralHeroMilestone) -> String {
        if milestone.isEstimated, milestone.status == .preliminary {
            return language.text("Estimated", "Beräknat")
        }
        return milestone.status.title(language: language)
    }

    private func milestoneDateCaption(_ milestone: DoctoralHeroMilestone) -> String {
        milestone.dateText + " · " + milestoneStatusWord(milestone)
    }

    private func milestoneHelpText(_ milestone: DoctoralHeroMilestone) -> String {
        var text = milestone.title + " · " + milestone.dateText + " · " + milestoneStatusWord(milestone)
        if !isLocked {
            text += " — " + language.text("click to change date or status", "klicka för att ändra datum eller status")
        }
        return text
    }

    // MARK: - Milestone bindings

    private func milestonePopoverBinding(_ kind: DoctoralHeroMilestone.Kind) -> Binding<Bool> {
        Binding(
            get: { activeMilestone == kind },
            set: { newValue in
                if newValue {
                    activeMilestone = kind
                } else if activeMilestone == kind {
                    activeMilestone = nil
                }
            }
        )
    }

    /// The popover edits the actual date fields; when only an estimated date
    /// exists it is used as the starting value.
    private func milestoneDateBinding(_ kind: DoctoralHeroMilestone.Kind) -> Binding<String> {
        switch kind {
        case .admission:
            return $admissionDate
        case .planningSeminar:
            return $planningSeminarDate
        case .halftime:
            return Binding(
                get: { halftimeDate.trimmedOrNil ?? estimatedHalftimeDate },
                set: { halftimeDate = $0 }
            )
        case .disputation:
            return Binding(
                get: { disputationDate.trimmedOrNil ?? plannedDisputationDate },
                set: { disputationDate = $0 }
            )
        }
    }

    private func milestonePreliminaryBinding(_ kind: DoctoralHeroMilestone.Kind) -> Binding<Bool> {
        switch kind {
        case .admission:
            return $admissionPreliminary
        case .planningSeminar:
            return $planningSeminarPreliminary
        case .halftime:
            return $halftimePreliminary
        case .disputation:
            return $disputationPreliminary
        }
    }

    /// Every milestone has its own stored outcome. (Before, admission and
    /// planning seminar had none, so "Genomfört" was silently dropped.)
    private func milestoneOutcomeBinding(_ kind: DoctoralHeroMilestone.Kind) -> Binding<String?> {
        switch kind {
        case .admission:
            return $admissionOutcomeRaw
        case .planningSeminar:
            return $planningSeminarOutcomeRaw
        case .halftime:
            return $halftimeOutcomeRaw
        case .disputation:
            return $disputationOutcomeRaw
        }
    }

    // MARK: - Activities

    private func activityStatusWord(_ row: CalendarLinkedEventRow) -> String {
        row.displayDate < Calendar.current.startOfDay(for: Date())
            ? language.text("Done", "Genomförd")
            : language.text("Planned", "Planerad")
    }

    private func activityHelpText(_ row: CalendarLinkedEventRow) -> String {
        [row.primaryText, DateParsers.isoDay.string(from: row.displayDate), activityStatusWord(row)]
            .joined(separator: " · ")
    }

    private func activityGroupHelpText(_ marker: ActivityMarker) -> String {
        let planned = marker.rows.count - marker.doneCount
        return language.text(
            "\(marker.rows.count) activities: \(marker.doneCount) done, \(planned) planned — click to list them",
            "\(marker.rows.count) aktiviteter: \(marker.doneCount) genomförda, \(planned) planerade — klicka för att visa dem"
        )
    }

    private func activityGroupBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { activeActivityGroupID == id },
            set: { newValue in
                if newValue {
                    activeActivityGroupID = id
                } else if activeActivityGroupID == id {
                    activeActivityGroupID = nil
                }
            }
        )
    }

    @ViewBuilder
    private func activityMarkerView(_ marker: ActivityMarker) -> some View {
        let blue = StatisticsEditorialStyle.paletteBlue
        if marker.isGroup {
            Button {
                activeActivityGroupID = marker.id
            } label: {
                ZStack {
                    Circle()
                        .fill(marker.allDone ? blue : (marker.noneDone ? AppPalette.detailPanelSurface : blue.opacity(0.35)))
                    Circle()
                        .stroke(blue, lineWidth: 1.4)
                    Text("\(marker.rows.count)")
                        .font(appFont(.secondary).weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(AppPalette.appText)
                        .padding(.horizontal, 2)
                }
                .frame(width: Self.activityGroupSize, height: Self.activityGroupSize)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(activityGroupHelpText(marker))
            .popover(isPresented: activityGroupBinding(marker.id), arrowEdge: .bottom) {
                activityGroupPopover(marker)
            }
        } else if let row = marker.rows.first {
            Button {
                store.openCalendarLinkedEvent(source: row.source)
            } label: {
                Circle()
                    .fill(marker.allDone ? blue : AppPalette.detailPanelSurface)
                    .overlay(Circle().stroke(blue, lineWidth: 1.4))
                    .frame(width: Self.activityDotSize, height: Self.activityDotSize)
                    .contentShape(Circle().scale(1.8))
            }
            .buttonStyle(.plain)
            .help(activityHelpText(row))
        }
    }

    private func activityGroupPopover(_ marker: ActivityMarker) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("\(marker.rows.count) activities", "\(marker.rows.count) aktiviteter"))
                .font(appFont(.body).weight(.semibold))
                .foregroundStyle(AppPalette.appText)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(marker.rows) { row in
                        Button {
                            activeActivityGroupID = nil
                            store.openCalendarLinkedEvent(source: row.source)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(DateParsers.isoDay.string(from: row.displayDate))
                                    .appTypography(.secondary)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                                Text(row.primaryText)
                                    .appTypography(.body)
                                    .foregroundStyle(AppPalette.appText)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(activityStatusWord(row))
                                    .appTypography(.secondary)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(language.text("Open in the calendar", "Öppna i kalendern"))
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(14)
        .frame(width: 380)
    }

    // MARK: - Papers

    private func paperStatusWord(_ publication: PublicationRecord) -> String {
        publication.isPublished
            ? language.text("Published", "Publicerat")
            : language.text("Not yet published", "Ej publicerat")
    }

    private func paperMarkerView(_ paper: PaperPlacement) -> some View {
        Button {
            store.openRoute(for: paper.publication)
        } label: {
            VStack(spacing: 3) {
                Group {
                    if paper.publication.isPublished {
                        Rectangle()
                            .fill(AppPalette.timelineBarEnd)
                            .overlay(Rectangle().stroke(AppPalette.timelineBarStroke, lineWidth: 1.2))
                    } else {
                        Rectangle()
                            .fill(AppPalette.detailPanelSurface)
                            .overlay(Rectangle().stroke(
                                Color.secondary,
                                style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2])
                            ))
                    }
                }
                .frame(width: 11, height: 11)
                .rotationEffect(.degrees(45))
                .padding(.top, 2)
                Text(paper.label)
                    .font(appFont(.secondary).weight(.semibold))
                    .foregroundStyle(AppPalette.appText)
                    .fixedSize()
                    .padding(.horizontal, 2)
                    .background(AppPalette.detailPanelSurface)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help([paper.label, paper.publication.title.nonEmpty, paperStatusWord(paper.publication)]
            .compactMap { $0 }
            .joined(separator: " · "))
    }
}

// MARK: - Supporting types

struct DoctoralHeroBar: Identifiable {
    let year: Int
    let value: Double

    var id: Int { year }
}

struct DoctoralHeroMilestone: Identifiable {
    enum Kind: Hashable {
        case admission
        case planningSeminar
        case halftime
        case disputation
    }

    let kind: Kind
    let title: String
    let dateText: String
    let isEstimated: Bool
    let status: DoctoralMilestoneStatus

    var id: Kind { kind }
}

/// Popover for one milestone: date editor plus the status choices
/// Preliminärt / Bokat / Genomfört (/ Avslutat innan for halftime and defence).
struct DoctoralMilestonePopover: View {
    let title: String
    @Binding var date: String
    @Binding var preliminary: Bool
    @Binding var outcomeRaw: String?
    let allowsEndedBefore: Bool
    let language: AppLanguage

    private var currentStatus: DoctoralMilestoneStatus {
        .current(preliminary: preliminary, outcomeRaw: outcomeRaw)
    }

    private var availableStatuses: [DoctoralMilestoneStatus] {
        allowsEndedBefore ? DoctoralMilestoneStatus.allCases : [.preliminary, .booked, .completed]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(appFont(.body).weight(.semibold))
                .foregroundStyle(AppPalette.appText)
            AppTimelineDateEditor(
                text: $date,
                uncertain: $preliminary,
                isHiddenFromCalendar: false,
                isIllogical: false,
                showsCountdown: false,
                mutedColor: nil,
                hiddenCalendarMenuTitle: nil,
                toggleHiddenCalendarVisibility: nil,
                language: language
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(language.text("Status", "Status"))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                ForEach(availableStatuses, id: \.self) { status in
                    statusRow(status)
                }
            }
        }
        .padding(14)
        .frame(width: 250)
    }

    private func statusRow(_ status: DoctoralMilestoneStatus) -> some View {
        let isSelected = currentStatus == status
        return Button {
            apply(status)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppPalette.linkAction : Color.secondary.opacity(0.6), lineWidth: 1.4)
                        .frame(width: 14, height: 14)
                    if isSelected {
                        Circle()
                            .fill(AppPalette.linkAction)
                            .frame(width: 7, height: 7)
                    }
                }
                Text(status.title(language: language))
                    .appTypography(.body)
                    .foregroundStyle(AppPalette.appText)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func apply(_ status: DoctoralMilestoneStatus) {
        let values = status.storedValues
        preliminary = values.preliminary
        outcomeRaw = values.outcomeRaw
        if status == .completed || status == .endedBefore {
            fillDateIfEmpty()
        }
    }

    /// A milestone marked as done keeps the date that is shown: today when
    /// there is none, and an estimated date becomes the actual date.
    private func fillDateIfEmpty() {
        if let shown = date.trimmedOrNil {
            date = shown
        } else {
            date = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
        }
    }
}

/// Compact progress ring with its label (and the "of …" text) to the LEFT so
/// the rings column stays short next to the timeline.
struct DoctoralHeroRingRow: View {
    static let labelWidth: CGFloat = 112

    let label: String
    let value: String
    let sub: String
    let color: Color
    let fraction: Double

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(label)
                    .font(appFont(.secondary).weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(sub)
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.trailing)
            .frame(width: Self.labelWidth, alignment: .trailing)
            ZStack {
                Circle()
                    .stroke(StatisticsEditorialStyle.hairline, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0, min(1, fraction)))
                    .stroke(color, style: StrokeStyle(lineWidth: 7))
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .appTypography(.panelTitle)
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.appText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            }
            .frame(width: 64, height: 64)
        }
        .help("\(label): \(value) \(sub)")
    }
}

/// Setup sheet shown for brand-new doctoral candidates: the three key dates.
struct DoctoralMilestoneSetupSheet: View {
    @Binding var admissionDate: String
    @Binding var estimatedHalftimeDate: String
    @Binding var plannedDisputationDate: String
    let language: AppLanguage
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.text("New doctoral candidate", "Ny doktorand"))
                    .appTypography(.pageTitle)
                Text(language.text(
                    "Set the three key dates — they draw the timeline at the top of the page. All of them can be changed later by clicking the milestones.",
                    "Ange de tre nyckeldatumen — de ritar tidslinjen högst upp på sidan. Alla går att ändra senare genom att klicka på milstolparna."
                ))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            setupRow(language.text("Admission", "Antagning"), date: $admissionDate)
            setupRow(language.text("Estimated halftime", "Beräknad halvtid"), date: $estimatedHalftimeDate)
            setupRow(language.text("Estimated defence", "Beräknad disputation"), date: $plannedDisputationDate)
            HStack {
                Spacer()
                Button(language.text("Done", "Klar"), action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.actionSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430)
    }

    private func setupRow(_ title: String, date: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: 170, alignment: .leading)
            TextField("YYYY-MM-DD", text: date)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .frame(width: 130)
                .onSubmit {
                    date.wrappedValue = DateParsers.canonicalizedDayInput(date.wrappedValue)
                }
            Button(language.text("Today", "Idag")) {
                date.wrappedValue = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}


// MARK: - Helpers

private func doctoralHeroYearFraction(of date: Date) -> Double {
    let calendar = Calendar.current
    let year = calendar.component(.year, from: date)
    let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
    return Double(year) + Double(day - 1) / 365.0
}

private func doctoralHeroYearFraction(from raw: String) -> Double? {
    let canonical = DateParsers.canonicalizedDayInput(raw)
    if let date = DateParsers.isoDay.date(from: canonical) {
        return doctoralHeroYearFraction(of: date)
    }
    if let year = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4)) {
        return Double(year) + 0.5
    }
    return nil
}

private func doctoralHeroIsPastOrToday(_ rawDate: String) -> Bool {
    guard let date = rawDate.trimmedOrNil.flatMap(DateParsers.isoDay.date(from:)) else { return false }
    return Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: Date())
}
