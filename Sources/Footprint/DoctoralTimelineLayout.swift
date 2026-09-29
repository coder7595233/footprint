import Foundation

/// Pure layout rules for the timeline at the top of the doctoral record page
/// (no drawing here, so the rules can be tested): label lanes that never
/// overlap, grouping of activities that lie close together, the year axis and
/// the milestone status choices.
enum DoctoralTimelineLayout {
    /// Gives every span (a label's left and right edge, in points) a lane so
    /// that two spans in the same lane never overlap and keep at least `gap`
    /// between them. Lane 0 is used first; a new lane is opened only when no
    /// existing lane has room. The result is in the same order as `spans`.
    static func lanes(for spans: [ClosedRange<Double>], gap: Double) -> [Int] {
        let order = spans.indices.sorted { lhs, rhs in
            if spans[lhs].lowerBound != spans[rhs].lowerBound {
                return spans[lhs].lowerBound < spans[rhs].lowerBound
            }
            return lhs < rhs
        }
        var laneEnds: [Double] = []
        var result = Array(repeating: 0, count: spans.count)
        for index in order {
            let span = spans[index]
            if let lane = laneEnds.firstIndex(where: { $0 + gap <= span.lowerBound }) {
                laneEnds[lane] = span.upperBound
                result[index] = lane
            } else {
                laneEnds.append(span.upperBound)
                result[index] = laneEnds.count - 1
            }
        }
        return result
    }

    /// Groups positions (in points, any order) that lie within `window` of
    /// the first position of their group. Each group is a list of indices
    /// into `positions`, sorted by position; the groups are sorted too.
    /// Because a group never reaches further than `window` from its first
    /// member, the middles of two neighbouring groups are always at least
    /// `window / 2` apart, so markers narrower than that never touch.
    static func clusters(positions: [Double], window: Double) -> [[Int]] {
        let order = positions.indices.sorted { lhs, rhs in
            if positions[lhs] != positions[rhs] {
                return positions[lhs] < positions[rhs]
            }
            return lhs < rhs
        }
        var groups: [[Int]] = []
        var anchor = -Double.infinity
        for index in order {
            if !groups.isEmpty, positions[index] - anchor < window {
                groups[groups.count - 1].append(index)
            } else {
                groups.append([index])
                anchor = positions[index]
            }
        }
        return groups
    }

    /// Where a label of `labelWidth` goes next to a node at `nodeX`: it starts
    /// just left of the node and runs to the right, or, when it would run past
    /// the right edge of the plot, it ends just right of the node instead.
    static func labelSpan(
        nodeX: Double,
        labelWidth: Double,
        plotWidth: Double,
        inset: Double
    ) -> (span: ClosedRange<Double>, anchorsTrailing: Bool) {
        let leadingStart = nodeX - inset
        if leadingStart + labelWidth <= plotWidth || nodeX + inset - labelWidth < 0 {
            return (leadingStart...(leadingStart + labelWidth), false)
        }
        let trailingEnd = nodeX + inset
        return ((trailingEnd - labelWidth)...trailingEnd, true)
    }

    /// The years the axis shows: from the earliest to the latest year that
    /// has something to draw. A range longer than `maxSpan` years keeps the
    /// latest years (older items are drawn at the left edge) instead of
    /// hiding the timeline. Nil when there is nothing to draw.
    static func axisYears(_ years: [Int], maxSpan: Int = 25) -> ClosedRange<Int>? {
        let usable = years.filter { (1990...2200).contains($0) }
        guard let first = usable.min(), let last = usable.max() else { return nil }
        return max(first, last - maxSpan)...last
    }
}

/// The status choices in a milestone's popover: Preliminärt / Bokat /
/// Genomfört (and Avslutat innan for halftime and defence). A status is kept
/// in two stored values: the preliminary flag and the outcome.
enum DoctoralMilestoneStatus: CaseIterable, Hashable {
    case preliminary
    case booked
    case completed
    case endedBefore

    static func current(preliminary: Bool, outcomeRaw: String?) -> DoctoralMilestoneStatus {
        switch outcomeRaw.flatMap(DoctoralMilestoneOutcome.init(rawValue:)) {
        case .completed?:
            return .completed
        case .endedBefore?:
            return .endedBefore
        case nil:
            return preliminary ? .preliminary : .booked
        }
    }

    /// The stored values that mean this status.
    var storedValues: (preliminary: Bool, outcomeRaw: String?) {
        switch self {
        case .preliminary:
            return (true, nil)
        case .booked:
            return (false, nil)
        case .completed:
            return (false, DoctoralMilestoneOutcome.completed.rawValue)
        case .endedBefore:
            return (false, DoctoralMilestoneOutcome.endedBefore.rawValue)
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .preliminary:
            return language.text("Preliminary", "Preliminärt")
        case .booked:
            return language.text("Booked", "Bokat")
        case .completed:
            return DoctoralMilestoneOutcome.completed.title(language: language)
        case .endedBefore:
            return DoctoralMilestoneOutcome.endedBefore.title(language: language)
        }
    }
}
