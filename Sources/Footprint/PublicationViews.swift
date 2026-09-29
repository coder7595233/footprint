import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

private extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1
        )
    }
}

struct PublicationCompactPanel<Content: View>: View {
    let title: String
    let usesInnerSurface: Bool
    let isCollapsed: Binding<Bool>?
    let titleTopPadding: CGFloat
    let titleContentSpacing: CGFloat
    let titleActionTitle: String?
    let titleAction: (() -> Void)?
    let content: Content

    init(
        title: String,
        usesInnerSurface: Bool = true,
        isCollapsed: Binding<Bool>? = nil,
        titleTopPadding: CGFloat = 8,
        titleContentSpacing: CGFloat = 4,
        titleActionTitle: String? = nil,
        titleAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.usesInnerSurface = usesInnerSurface
        self.isCollapsed = isCollapsed
        self.titleTopPadding = titleTopPadding
        self.titleContentSpacing = titleContentSpacing
        self.titleActionTitle = titleActionTitle
        self.titleAction = titleAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: titleContentSpacing) {
            if let title = title.nonEmpty {
                if let isCollapsed {
                    PublicationSectionTitle(
                        title: title,
                        isCollapsible: true,
                        isCollapsed: isCollapsed.wrappedValue
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isCollapsed.wrappedValue.toggle()
                        }
                    }
                } else {
                    PublicationSectionTitle(
                        title: title,
                        titleActionTitle: titleActionTitle,
                        titleAction: titleAction
                    )
                }
            }
            if isCollapsed?.wrappedValue != true {
                AppWorkspacePanel(
                    title: "",
                    titleStyle: .none,
                    fill: usesInnerSurface ? AppPalette.secondaryCardSurface : Color.clear,
                    stroke: usesInnerSurface ? AppPalette.subtleBorder : Color.clear,
                    usesInnerSurface: true
                ) {
                    content
                }
            }
        }
        .padding(.top, title.nonEmpty == nil ? 0 : titleTopPadding)
    }
}

private struct PublicationSectionTitle: View {
    let title: String
    var isCollapsible: Bool = false
    var isCollapsed: Bool = false
    var onToggle: (() -> Void)? = nil
    var titleActionTitle: String? = nil
    var titleAction: (() -> Void)? = nil

    var body: some View {
        Group {
            if isCollapsible, let onToggle {
                Button(action: onToggle) {
                    HStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppPalette.appText)
                                .frame(width: 10)
                            Text(title)
                                .appTypography(.sectionTitle)
                                .foregroundStyle(AppPalette.appText)
                        }
                        Rectangle()
                            .fill(AppPalette.subtleBorder)
                            .frame(height: 1)
                            .padding(.leading, 10)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .formKeyboardNavigable()
            } else {
                HStack(spacing: 12) {
                    Text(title)
                        .appTypography(.sectionTitle)
                        .foregroundStyle(AppPalette.appText)
                    if let titleActionTitle, let titleAction {
                        AppIconAddButton(title: titleActionTitle, action: titleAction)
                    }
                    Rectangle()
                        .fill(AppPalette.subtleBorder.opacity(AppRuntime.usesRenewedChrome ? 0.9 : 1))
                        .frame(height: 1)
                }
            }
        }
        .padding(.top, AppRuntime.usesRenewedChrome ? 2 : 0)
    }
}





enum PublicationBadgeTone {
    case neutral
    case good
    case warning
    case caution
    case low

    var background: Color {
        switch self {
        case .neutral:
            AppPalette.fieldSurface
        case .good:
            AppPalette.vividGreen
        case .warning:
            AppPalette.vividYellow
        case .caution:
            AppPalette.vividOrange
        case .low:
            AppPalette.vividRed
        }
    }

    var foreground: Color {
        switch self {
        case .neutral:
            .primary
        case .good:
            AppPalette.semanticOnColor
        case .warning:
            AppPalette.semanticOnColor
        case .caution:
            AppPalette.semanticOnColor
        case .low:
            AppPalette.semanticOnColor
        }
    }

    var stroke: Color {
        switch self {
        case .neutral:
            AppPalette.border
        case .good:
            AppPalette.vividGreen.opacity(0.78)
        case .warning:
            AppPalette.vividYellow.opacity(0.82)
        case .caution:
            AppPalette.vividOrange.opacity(0.82)
        case .low:
            AppPalette.vividRed.opacity(0.78)
        }
    }
}

struct PublicationMetricValueBadge: View {
    let metric: PublicationMetricValue?
    var backgroundColor: Color? = nil
    var isCompact = false

    var body: some View {
        AppToneBadge(
            text: displayText,
            size: isCompact ? .compact : .normal,
            foreground: backgroundColor == nil ? tone.foreground : AppPalette.semanticOnColor,
            background: backgroundColor ?? tone.background,
            stroke: (backgroundColor ?? tone.stroke).opacity(backgroundColor == nil ? 1 : 0.92),
            horizontalPadding: isCompact ? 6 : 8,
            verticalPadding: isCompact ? 1 : 4
        )
        .minimumScaleFactor(0.75)
    }

    private var displayText: String {
        guard let metric else { return "–" }
        if metric.kind == .clarivateEsciJIF {
            return "\(formattedRankingMetricValue(metric))?"
        }
        let displayValue = formattedRankingMetricValue(metric)
        return metric.flagsUncertainty ? "\(displayValue)?" : displayValue
    }

    private var tone: PublicationBadgeTone {
        guard let metric else { return .neutral }
        if metric.kind == .norwegianList {
            switch metric.value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            case "2":
                return .good
            case "1":
                return .warning
            case "0", "X":
                return .low
            default:
                return .neutral
            }
        }
        guard let numeric = metric.numericValue else { return .neutral }
        switch numeric {
        case ..<2:
            return .low
        case ..<4:
            return .caution
        case ..<10:
            return .warning
        default:
            return .good
        }
    }
}

struct PublicationQuartileBadge: View {
    let metric: PublicationMetricValue?
    var isCompact = false

    var body: some View {
        AppBadgeText(text: displayText, size: isCompact ? .compact : .normal)
            .frame(minWidth: isCompact ? 30 : 34)
            .padding(.horizontal, isCompact ? 5 : 6)
            .padding(.vertical, isCompact ? 1 : 4)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 6 : 8, style: .continuous)
                    .fill(quartileFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? 6 : 8, style: .continuous)
                    .stroke(quartileStrokeColor, lineWidth: 1)
            )
            .foregroundStyle(quartileForegroundColor)
    }

    private var displayText: String {
        normalizedQuartile.isEmpty ? "–" : normalizedQuartile
    }

    private var normalizedQuartile: String {
        metric?.quartile.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    }

    private var quartileFillColor: Color {
        switch normalizedQuartile {
        case "Q1":
            return AppPalette.vividGreen
        case "Q2":
            return AppPalette.vividYellow
        case "Q3", "Q4":
            return AppPalette.vividRed
        default:
            return AppPalette.fieldSurface.opacity(metric == nil ? 0.12 : 0.9)
        }
    }

    private var quartileColor: Color {
        switch normalizedQuartile {
        case "Q1":
            AppPalette.vividGreen
        case "Q2":
            AppPalette.vividYellow
        case "Q3":
            AppPalette.vividRed
        case "Q4":
            AppPalette.vividRed
        default:
            AppPalette.fieldSurface
        }
    }

    private var quartileStrokeColor: Color {
        switch normalizedQuartile {
        case "Q1", "Q2", "Q3", "Q4":
            return quartileColor.opacity(0.95)
        default:
            return AppPalette.subtleBorder.opacity(0.9)
        }
    }

    private var quartileForegroundColor: Color {
        if metric == nil {
            return .secondary
        }
        switch normalizedQuartile {
        case "Q1", "Q2", "Q3", "Q4":
            return AppPalette.semanticOnColor
        default:
            return AppPalette.appText
        }
    }
}



@MainActor
@ViewBuilder
func compactField<Content: View>(
    _ title: String,
    width: CGFloat? = nil,
    helpText: String? = nil,
    @ViewBuilder content: () -> Content
) -> some View {
    AppCompactField(title, width: width, help: helpText) {
        content()
    }
}


extension PublicationStatus {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .planned:
            return fixedDropdownText("publicationStatus.planned", language: language, english: "Planned", swedish: "Planerad")
        case .inPreparation:
            return fixedDropdownText("publicationStatus.inPreparation", language: language, english: "In preparation", swedish: "Under arbete")
        case .submitted:
            return fixedDropdownText("publicationStatus.submitted", language: language, english: "Submitted", swedish: "Inskickad")
        case .accepted:
            return fixedDropdownText("publicationStatus.accepted", language: language, english: "Accepted", swedish: "Accepterad")
        case .rejected:
            return fixedDropdownText("publicationStatus.rejected", language: language, english: "Rejected", swedish: "Refuserad")
        case .published:
            return fixedDropdownText("publicationStatus.published", language: language, english: "Published", swedish: "Publicerad")
        }
    }
}

extension PublicationWorkflowStatus {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .dataCollection:
            return fixedDropdownText("publicationWorkflow.dataCollection", language: language, english: "Data collection", swedish: "Datainsamling")
        case .dataProcessing:
            return fixedDropdownText("publicationWorkflow.dataProcessing", language: language, english: "Data processing", swedish: "Databearbetning")
        case .manuscriptWriting:
            return fixedDropdownText("publicationWorkflow.manuscriptWriting", language: language, english: "Manuscript writing", swedish: "Manusskrivande")
        case .withCoauthors:
            return fixedDropdownText("publicationWorkflow.withCoauthors", language: language, english: "With co-authors", swedish: "Hos medförfattare")
        }
    }
}
