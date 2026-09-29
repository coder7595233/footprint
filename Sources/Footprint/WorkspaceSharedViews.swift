import AppKit
import SwiftUI

enum ResearcherNameFieldMetrics {
    static let compactWidth: CGFloat = 260
}

enum FloatingWorkspacePanelKind {
    case statistics
    case document
}

struct FloatingStatisticsContentConfiguration: @unchecked Sendable {
    let scopeID: String?
    let id: String
    let title: String
    let isAvailable: Bool
    let kind: FloatingWorkspacePanelKind
    let content: () -> AnyView
}

struct FloatingStatisticsContentPreferenceKey: PreferenceKey {
    static let defaultValue: [FloatingStatisticsContentConfiguration] = []

    static func reduce(
        value: inout [FloatingStatisticsContentConfiguration],
        nextValue: () -> [FloatingStatisticsContentConfiguration]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private struct FloatingStatisticsScopeIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var floatingStatisticsScopeID: String? {
        get { self[FloatingStatisticsScopeIDKey.self] }
        set { self[FloatingStatisticsScopeIDKey.self] = newValue }
    }
}

extension View {
    func floatingStatisticsContent<StatisticsContent: View>(
        id: String,
        title: String,
        isAvailable: Bool = true,
        @ViewBuilder content: @escaping () -> StatisticsContent
    ) -> some View {
        modifier(
            FloatingStatisticsContentModifier(
                id: id,
                title: title,
                isAvailable: isAvailable,
                kind: .statistics,
                statisticsContent: { AnyView(content()) }
            )
        )
    }

    /// The document twin of `floatingStatisticsContent`: publishes a document
    /// preview for the floating document button next to the statistics button.
    func floatingDocumentContent<DocumentContent: View>(
        id: String,
        title: String,
        isAvailable: Bool = true,
        @ViewBuilder content: @escaping () -> DocumentContent
    ) -> some View {
        modifier(
            FloatingStatisticsContentModifier(
                id: id,
                title: title,
                isAvailable: isAvailable,
                kind: .document,
                statisticsContent: { AnyView(content()) }
            )
        )
    }

    func onEscapeKey(isEnabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        background(AppEscapeKeyHandler(isEnabled: isEnabled, action: action))
    }

    func sidebarSearchFieldLayout(minWidth: CGFloat = 88) -> some View {
        self
            .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
    }

    func appReminderCountBadge(_ count: Int, inset: CGFloat = 2, help: String? = nil) -> some View {
        overlay(alignment: .topTrailing) {
            if count > 0 {
                AppReminderCountBadge(count: count, help: help)
                    .padding(.top, inset)
                    .padding(.trailing, inset)
            }
        }
    }

    func appReminderListBadge(_ count: Int, trailingInset: CGFloat = 6, help: String? = nil) -> some View {
        overlay(alignment: .trailing) {
            if count > 0 {
                AppReminderCountBadge(count: count, help: help)
                    .padding(.trailing, trailingInset)
            }
        }
    }

    func appReminderDot(_ isVisible: Bool, inset: CGFloat = 2) -> some View {
        overlay(alignment: .topTrailing) {
            if isVisible {
                AppReminderDot()
                    .padding(.top, inset)
                    .padding(.trailing, inset)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct AppReminderCountBadge: View {
    let count: Int
    var help: String? = nil

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(minWidth: 15, minHeight: 15)
            .padding(.horizontal, count >= 10 ? 2 : 0)
            // #D50000 clears WCAG AA for the 9 pt white label; the previous
            // brighter red sat just below 4.5:1.
            .background(Capsule().fill(Color(red: 0.84, green: 0.0, blue: 0.0)))
            .overlay(Capsule().stroke(Color.white.opacity(0.92), lineWidth: 1))
            .help(help ?? "")
            .accessibilityLabel(help ?? "\(count)")
    }
}

struct AppReminderDot: View {
    var body: some View {
        Circle()
            .fill(Color(red: 0.96, green: 0.03, blue: 0.07))
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.white.opacity(0.92), lineWidth: 1))
    }
}

private struct AppEscapeKeyHandler: NSViewRepresentable {
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isEnabled: isEnabled, action: action)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        private var monitor: Any?
        private var action: (() -> Void)?
        private var isEnabled = false

        deinit {
            removeMonitor()
        }

        func update(isEnabled: Bool, action: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.action = action

            if isEnabled {
                installMonitorIfNeeded()
            } else {
                removeMonitor()
            }
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled else { return event }
                let pressedModifiers = event.modifierFlags.intersection(
                    NSEvent.ModifierFlags([.command, .control, .option, .shift])
                )
                guard event.keyCode == 53, pressedModifiers.isEmpty else { return event }
                self.action?()
                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

struct AppSidebarSearchField: View {
    let placeholder: String
    let text: Binding<String>
    var minWidth: CGFloat = 88

    var body: some View {
        TextField(placeholder, text: text)
            .appTextInputChrome()
            .sidebarSearchFieldLayout(minWidth: minWidth)
    }
}

struct AppFilterCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppFilterChip: View {
    let label: String
    var systemImage: String? = nil
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.tail)
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isEnabled ? (isSelected ? AppPalette.appText : .primary) : .secondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 28, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? AppPalette.activeTabSurface.opacity(0.24)
                            : AppPalette.fieldSurface.opacity(isEnabled ? 1 : 0.38)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isSelected
                            ? AppPalette.activeTabSurface.opacity(0.78)
                            : AppPalette.border.opacity(isEnabled ? 0.45 : 0.24),
                        lineWidth: 1
                    )
            )
            .opacity(isEnabled ? 1 : 0.58)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct AppEmptyStateView: View {
    let title: String
    let subtitle: String
    var systemImage: String = "tray"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var fillsBackground = false
    var isCompact = false

    var body: some View {
        VStack {
            VStack(spacing: isCompact ? 8 : 14) {
                Image(systemName: systemImage)
                    .font(.system(size: isCompact ? 15 : 24, weight: .semibold))
                    .foregroundStyle(AppPalette.vividBlue)
                    .frame(width: isCompact ? 30 : 52, height: isCompact ? 30 : 52)
                    .background(Circle().fill(AppPalette.emptyStateIconSurface))

                if isCompact {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    AppPanelHeadingText(text: title)
                        .multilineTextAlignment(.center)
                }

                if !subtitle.isEmpty {
                    AppRecordSubtitleText(text: subtitle)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: isCompact ? 260 : 360)
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .tint(AppPalette.actionSave)
                }
            }
            .frame(maxWidth: isCompact ? 320 : 440)
            .padding(.horizontal, isCompact ? 14 : 28)
            .padding(.vertical, isCompact ? 14 : 30)
            .background(
                RoundedRectangle(cornerRadius: AppPalette.largeCornerRadius, style: .continuous)
                    .fill(AppPalette.emptyStateSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.largeCornerRadius, style: .continuous)
                    .stroke(AppPalette.subtleBorder, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: isCompact ? nil : .infinity)
        .padding(isCompact ? 0 : 40)
        .background(fillsBackground ? AppPalette.detailPanelSurface : Color.clear)
    }
}

enum AppWorkspaceEmptyStateKind {
    case generic
    case applications
    case organizations
    case projects
    case publications
    case cv
    case teaching
    case congresses

    var systemImage: String {
        switch self {
        case .generic:
            return "tray"
        case .applications:
            return "doc.text"
        case .organizations:
            return "building.2"
        case .projects:
            return "folder"
        case .publications:
            return "books.vertical"
        case .cv:
            return "doc.text"
        case .teaching:
            return "graduationcap"
        case .congresses:
            return "mappin.and.ellipse"
        }
    }
}

struct AppWorkspaceEmptyStateView: View {
    let title: String
    let subtitle: String
    var kind: AppWorkspaceEmptyStateKind = .generic
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var fillsBackground = false
    var isCompact = false

    var body: some View {
        AppEmptyStateView(
            title: title,
            subtitle: subtitle,
            systemImage: kind.systemImage,
            actionTitle: actionTitle,
            action: action,
            fillsBackground: fillsBackground,
            isCompact: isCompact
        )
    }
}

private struct FloatingStatisticsContentModifier: ViewModifier {
    @Environment(\.floatingStatisticsScopeID) private var scopeID

    let id: String
    let title: String
    let isAvailable: Bool
    let kind: FloatingWorkspacePanelKind
    let statisticsContent: () -> AnyView

    func body(content base: Content) -> some View {
        // transformPreference, not preference: a plain .preference on an
        // ancestor REPLACES whatever the subtree published for the key, so a
        // chained document modifier would silently swallow the statistics
        // configuration underneath it (this regressed the grant/publication
        // statistics panels once). Appending keeps every publisher visible.
        base.transformPreference(FloatingStatisticsContentPreferenceKey.self) { value in
            value.append(
                FloatingStatisticsContentConfiguration(
                    scopeID: scopeID,
                    id: id,
                    title: title,
                    isAvailable: isAvailable,
                    kind: kind,
                    content: statisticsContent
                )
            )
        }
    }
}

enum AppLinkDestinationKind {
    case app
    case web
    case pdf
    case file
    case map
    case email

    func title(language: AppLanguage) -> String {
        switch self {
        case .app:
            return "app"
        case .web:
            return language.text("web", "webb")
        case .pdf:
            return "pdf"
        case .file:
            return language.text("file", "fil")
        case .map:
            return language.text("map", "karta")
        case .email:
            return language.text("e-mail", "e-post")
        }
    }

    var systemImage: String {
        switch self {
        case .app:
            return "arrow.up.right.square"
        case .web:
            return "link"
        case .pdf:
            return "doc.richtext.fill"
        case .file:
            return "doc"
        case .map:
            return "map"
        case .email:
            return "envelope.badge.plus"
        }
    }
}

struct AppLinkDestinationLabel: View {
    let kind: AppLinkDestinationKind
    let language: AppLanguage
    var fontSize: CGFloat = 12
    var weight: Font.Weight = .semibold
    var fixedSize = true
    var tint: Color = AppPalette.linkAction
    var showsTitle = true

    private var usesTitle: Bool {
        showsTitle && kind.showsInlineTitle
    }

    @ViewBuilder
    var body: some View {
        if usesTitle {
            Label(kind.title(language: language), systemImage: kind.systemImage)
                .font(.system(size: fontSize, weight: weight))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize(horizontal: fixedSize, vertical: false)
                .foregroundStyle(tint)
                .help(kind.helpTitle(language: language))
        } else {
            Label(kind.title(language: language), systemImage: kind.systemImage)
                .font(.system(size: fontSize, weight: weight))
                .labelStyle(.iconOnly)
                .lineLimit(1)
                .fixedSize(horizontal: fixedSize, vertical: false)
                .foregroundStyle(tint)
                .help(kind.helpTitle(language: language))
        }
    }
}

struct AppDestinationActionButton: View {
    let kind: AppLinkDestinationKind
    let language: AppLanguage
    var title: String? = nil
    var fontSize: CGFloat = 12
    var showsTitle = false
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var tint: Color = AppPalette.linkAction
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppLinkDestinationLabel(
                kind: kind,
                language: language,
                fontSize: fontSize,
                tint: tint,
                showsTitle: showsTitle
            )
            .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .disabled(!isEnabled)
        .help(resolvedTitle)
        .accessibilityLabel(resolvedTitle)
    }

    private var resolvedTitle: String {
        title ?? kind.helpTitle(language: language)
    }
}

struct AppDestinationURLLink: View {
    let kind: AppLinkDestinationKind
    let language: AppLanguage
    let destination: URL
    var title: String? = nil
    var fontSize: CGFloat = 12
    var showsTitle = false
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var tint: Color = AppPalette.linkAction

    @ViewBuilder
    var body: some View {
        if let safeDestination = safeExternalURL(destination) {
            Link(destination: safeDestination) {
                linkLabel
            }
            .buttonStyle(.plain)
            .foregroundStyle(tint)
            .help(resolvedTitle)
            .accessibilityLabel(resolvedTitle)
        } else {
            linkLabel
                .foregroundStyle(.secondary)
                .help(resolvedTitle)
                .accessibilityLabel(resolvedTitle)
                .accessibilityHint(language.text("Invalid or unsupported link", "Ogiltig eller ej stödd länk"))
        }
    }

    private var linkLabel: some View {
        AppLinkDestinationLabel(
            kind: kind,
            language: language,
            fontSize: fontSize,
            tint: tint,
            showsTitle: showsTitle
        )
        .frame(width: width, height: height)
    }

    private var resolvedTitle: String {
        title ?? kind.helpTitle(language: language)
    }
}

struct AppDestinationPlaceholder: View {
    var width: CGFloat? = nil
    var height: CGFloat? = nil

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
    }
}

private extension AppLinkDestinationKind {
    var showsInlineTitle: Bool {
        switch self {
        case .app, .email:
            return false
        case .web, .pdf, .file, .map:
            return true
        }
    }

    func helpTitle(language: AppLanguage) -> String {
        switch self {
        case .app:
            return language.text("Open in app", "Öppna i appen")
        case .pdf:
            return language.text("Open PDF", "Öppna PDF")
        case .web:
            return language.text("Open web link", "Öppna webblänk")
        case .file:
            return language.text("Open file", "Öppna fil")
        case .map:
            return language.text("Open map", "Öppna karta")
        case .email:
            return language.text("Create e-mail", "Skapa e-post")
        }
    }
}

struct AttachmentWarningIcon: View {
    var size: CGFloat = 16
    var tint: Color = AppPalette.vividOrange
    var help: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "doc")
                .font(.system(size: size, weight: .semibold))
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: max(12, size * 0.58), weight: .bold))
                .background(
                    Circle()
                        .fill(AppPalette.cardSurface)
                        .frame(width: max(9, size * 0.68), height: max(9, size * 0.68))
                )
                .offset(x: size * 0.18, y: size * 0.16)
        }
        .foregroundStyle(tint)
        .frame(width: size + 4, height: size + 4)
        .help(help)
    }
}

enum AppPDFAttachmentControlStyle {
    case compact
    case prominent
}

struct AppPDFAttachmentControl: View {
    let language: AppLanguage
    var filename: String?
    /// F1b: name built from the record (see `AttachmentLabels`). When set,
    /// it is shown instead of `filename`, and the original file name is the
    /// tooltip.
    var displayLabel: String? = nil
    var placeholder: String
    var hasAttachment: Bool
    var isAvailable = true
    var isEditingLocked = false
    var style: AppPDFAttachmentControlStyle = .compact
    var showsLeadingIcon = false
    var showsFilename = true
    var addTitle: String? = nil
    var replaceTitle: String? = nil
    var openTitle: String? = nil
    var removeTitle: String? = nil
    var previewTitle: String? = nil
    var isPreviewDisabled = false
    var chooseAction: (() -> Void)? = nil
    var openAction: (() -> Void)? = nil
    var removeAction: (() -> Void)? = nil
    var previewAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: style == .compact ? 8 : 10) {
            if showsLeadingIcon {
                attachmentIcon(size: style == .compact ? 15 : 17, fontSize: style == .compact ? 12 : 13)
            }

            if showsFilename {
                Text(displayName)
                    .font(.system(size: style == .compact ? 12 : 13, weight: style == .compact ? .regular : .medium))
                    .foregroundStyle(filename == nil && resolvedDisplayLabel == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(originalFilenameHelp)
            }

            if !isEditingLocked, let chooseAction {
                chooseButton(action: chooseAction)
            }

            if hasAttachment {
                if let previewTitle, let previewAction {
                    Button(previewTitle, action: previewAction)
                        .buttonStyle(.bordered)
                        .disabled(isPreviewDisabled)
                }

                if let openAction {
                    openButton(action: openAction)
                }

                if !isEditingLocked, let removeAction {
                    removeButton(action: removeAction)
                }
            }
        }
    }

    private var resolvedDisplayLabel: String? {
        guard hasAttachment else { return nil }
        return displayLabel?.trimmedOrNil
    }

    private var displayName: String {
        resolvedDisplayLabel ?? filename?.trimmedOrNil ?? placeholder
    }

    private var originalFilenameHelp: String {
        guard resolvedDisplayLabel != nil, let original = filename?.trimmedOrNil else { return "" }
        return language.text("Original file name: \(original)", "Ursprungligt filnamn: \(original)")
    }

    private var missingHelp: String {
        language.text("The linked PDF file could not be found.", "Den länkade PDF-filen kunde inte hittas.")
    }

    private var chooseHelp: String {
        hasAttachment
            ? (replaceTitle ?? language.text("Replace PDF", "Byt PDF"))
            : (addTitle ?? language.text("Add PDF", "Lägg till PDF"))
    }

    private var resolvedOpenTitle: String {
        openTitle ?? language.text("Open PDF", "Öppna PDF")
    }

    private var resolvedRemoveTitle: String {
        removeTitle ?? language.text("Remove PDF", "Ta bort PDF")
    }

    @ViewBuilder
    private func attachmentIcon(size: CGFloat, fontSize: CGFloat) -> some View {
        if hasAttachment && !isAvailable {
            AttachmentWarningIcon(size: size, help: missingHelp)
        } else {
            AppLinkDestinationLabel(kind: .pdf, language: language, fontSize: fontSize, showsTitle: false)
        }
    }

    @ViewBuilder
    private func chooseButton(action: @escaping () -> Void) -> some View {
        switch style {
        case .compact:
            Button(action: action) {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppPalette.linkAction)
            .help(chooseHelp)
            .accessibilityLabel(chooseHelp)
        case .prominent:
            Button(chooseHelp, action: action)
                .appAddButtonStyle()
        }
    }

    @ViewBuilder
    private func openButton(action: @escaping () -> Void) -> some View {
        switch style {
        case .compact:
            Button(action: action) {
                if !isAvailable && !showsLeadingIcon {
                    AttachmentWarningIcon(
                        size: 15,
                        tint: Color.secondary.opacity(0.7),
                        help: missingHelp
                    )
                } else {
                    AppLinkDestinationLabel(
                        kind: .pdf,
                        language: language,
                        fontSize: 12,
                        tint: isAvailable ? AppPalette.linkAction : Color.secondary.opacity(0.55)
                    )
                }
            }
            .buttonStyle(.borderless)
            .disabled(!isAvailable)
            .help(resolvedOpenTitle)
        case .prominent:
            Button(action: action) {
                AppLinkDestinationLabel(
                    kind: .pdf,
                    language: language,
                    fontSize: 12,
                    tint: isAvailable ? AppPalette.linkAction : Color.secondary.opacity(0.55)
                )
            }
            .buttonStyle(.bordered)
            .disabled(!isAvailable)
            .help(resolvedOpenTitle)
        }
    }

    @ViewBuilder
    private func removeButton(action: @escaping () -> Void) -> some View {
        switch style {
        case .compact:
            Button(role: .destructive, action: action) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(AppPalette.actionDelete)
            }
            .buttonStyle(.borderless)
            .help(resolvedRemoveTitle)
            .accessibilityLabel(resolvedRemoveTitle)
        case .prominent:
            Button(role: .destructive, action: action) {
                Label(language.text("Remove", "Ta bort"), systemImage: "trash")
            }
            .appDeleteButtonStyle()
            .help(resolvedRemoveTitle)
        }
    }
}

struct SelectedListRowBackground: View {
    var cornerRadius: CGFloat = 8
    var indicatorFill: Color? = nil

    private var resolvedIndicatorFill: Color {
        indicatorFill ?? AppPalette.vividBlue
    }

    private var indicatorWidth: CGFloat {
        indicatorFill == nil ? 4 : 8
    }

    private var indicatorLeadingPadding: CGFloat {
        indicatorFill == nil ? 4 : 0
    }

    private var indicatorVerticalPadding: CGFloat {
        indicatorFill == nil ? 5 : 0
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppPalette.activeTabSurface.opacity(0.26))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppPalette.activeTabSurface.opacity(0.6), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(resolvedIndicatorFill)
                    .frame(width: indicatorWidth)
                    .padding(.vertical, indicatorVerticalPadding)
                    .padding(.leading, indicatorLeadingPadding)
            }
            .shadow(color: AppPalette.activeTabSurface.opacity(0.12), radius: 3, y: 1)
    }
}

struct StatusIndicatorListRowBackground: View {
    let fill: Color
    var indicatorWidth: CGFloat = 8
    var leadingPadding: CGFloat = 0
    var verticalPadding: CGFloat = 0
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(fill)
                    .frame(width: indicatorWidth)
                    .padding(.vertical, verticalPadding)
                    .padding(.leading, leadingPadding)
            }
    }
}

struct AppListRowBackground: View {
    let isSelected: Bool
    var toneFill: Color? = nil
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if isSelected {
                SelectedListRowBackground(cornerRadius: cornerRadius, indicatorFill: toneFill)
            } else if let toneFill {
                StatusIndicatorListRowBackground(fill: toneFill, cornerRadius: cornerRadius)
            } else {
                Color.clear
            }
        }
    }
}

struct AppListRowButton<Background: View, Content: View>: View {
    var width: CGFloat? = nil
    var minWidth: CGFloat? = nil
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 4
    let action: () -> Void
    let background: Background
    let content: Content

    init(
        width: CGFloat? = nil,
        minWidth: CGFloat? = nil,
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 4,
        action: @escaping () -> Void,
        @ViewBuilder background: () -> Background,
        @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.minWidth = minWidth
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.action = action
        self.background = background()
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .font(.system(size: 12))
                .padding(.leading, horizontalPadding + 4)
                .padding(.trailing, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(width: width, alignment: .leading)
                .frame(minWidth: minWidth, alignment: .leading)
                .contentShape(Rectangle())
                .background(background)
        }
        .buttonStyle(.plain)
    }
}

struct AppWorkspaceSidebar<Content: View>: View {
    var padding: CGFloat = 14
    let content: Content

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppPalette.sidebarPanelSurface)
    }
}

struct AppWorkspaceSidebarHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        AppWorkspaceTitleBar(title: title, spacing: 10, horizontalPadding: 0, verticalPadding: 0) {
            if let actionTitle, let action {
                Spacer(minLength: 0)
                Button(actionTitle, action: action)
                    .appAddButtonStyle()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

struct AppWorkspaceTitleBar<Trailing: View>: View {
    let title: String
    var spacing: CGFloat = 14
    var horizontalPadding: CGFloat = 24
    var verticalPadding: CGFloat = 14
    let trailing: Trailing

    init(
        title: String,
        spacing: CGFloat = 14,
        horizontalPadding: CGFloat = 24,
        verticalPadding: CGFloat = 14,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: spacing) {
            Text(title)
                .appTypography(.pageTitle)
            trailing
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }
}

struct AppListTable<Header: View, Rows: View>: View {
    private let horizontalEdgeBleed: CGFloat = 14
    let contentWidth: CGFloat?
    let contentMinWidth: CGFloat?
    let header: Header
    let usesScrollViewReader: Bool
    let rows: (ScrollViewProxy?) -> Rows

    init(
        contentWidth: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder rows: @escaping () -> Rows
    ) {
        self.contentWidth = contentWidth
        self.contentMinWidth = nil
        self.header = header()
        self.usesScrollViewReader = false
        self.rows = { _ in rows() }
    }

    init(
        contentWidth: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder rowsWithProxy: @escaping (ScrollViewProxy) -> Rows
    ) {
        self.contentWidth = contentWidth
        self.contentMinWidth = nil
        self.header = header()
        self.usesScrollViewReader = true
        self.rows = { proxy in
            guard let proxy else { fatalError("AppListTable expected a ScrollViewProxy") }
            return rowsWithProxy(proxy)
        }
    }

    init(
        contentMinWidth: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder rows: @escaping () -> Rows
    ) {
        self.contentWidth = nil
        self.contentMinWidth = contentMinWidth
        self.header = header()
        self.usesScrollViewReader = false
        self.rows = { _ in rows() }
    }

    init(
        contentMinWidth: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder rowsWithProxy: @escaping (ScrollViewProxy) -> Rows
    ) {
        self.contentWidth = nil
        self.contentMinWidth = contentMinWidth
        self.header = header()
        self.usesScrollViewReader = true
        self.rows = { proxy in
            guard let proxy else { fatalError("AppListTable expected a ScrollViewProxy") }
            return rowsWithProxy(proxy)
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                Divider()

                if usesScrollViewReader {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            rows(proxy)
                        }
                    }
                } else {
                    ScrollView(.vertical) {
                        rows(nil)
                    }
                }
            }
            .frame(width: contentWidth, alignment: .leading)
            .frame(minWidth: contentMinWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .padding(.horizontal, -horizontalEdgeBleed)
    }
}

struct FilterClearButton: View {
    let action: () -> Void

    var body: some View {
        AppFilterResetButton(help: "Ta bort filter", action: action)
    }
}

struct MultiSelectFilterMenu: View {
    let title: String
    let emptyLabel: String
    let options: [String]
    @Binding var selectedOptions: Set<String>
    var display: (String) -> String = { $0 }
    var popoverWidth: CGFloat = 280
    @State private var isPresented = false

    private var buttonLabel: String {
        switch selectedOptions.count {
        case 0:
            return emptyLabel
        case 1:
            return selectedOptions.first.map(display) ?? emptyLabel
        default:
            return "\(selectedOptions.count)"
        }
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(buttonLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appMenuChrome(
            horizontalPadding: AppPalette.textFieldHorizontalPadding,
            verticalPadding: AppPalette.textFieldVerticalPadding
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .contentShape(Rectangle())
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(emptyLabel)
                        .appTypography(.panelTitle)
                    Spacer()
                    Button(title) {
                        selectedOptions.removeAll()
                    }
                    .disabled(selectedOptions.isEmpty)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(options, id: \.self) { option in
                            Toggle(isOn: Binding(
                                get: { selectedOptions.contains(option) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedOptions.insert(option)
                                    } else {
                                        selectedOptions.remove(option)
                                    }
                                }
                            )) {
                                Text(display(option))
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .appCheckboxStyle()
                        }
                    }
                }
                .frame(width: popoverWidth, height: min(CGFloat(max(options.count, 1)) * 28, 320))
            }
            .padding(12)
        }
    }
}

struct AppFilterResetButton: View {
    var help: String
    var size: CGFloat = 24
    var fontSize: CGFloat = 12
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(AppPalette.actionDelete)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct AppResetButton: View {
    let title: String
    var systemImage: String? = nil
    var style: Style = .bordered
    let action: () -> Void

    enum Style {
        case bordered
        case plain
    }

    var body: some View {
        switch style {
        case .bordered:
            Button(action: action) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .buttonStyle(.bordered)
            .help(title)
            .accessibilityLabel(title)
        case .plain:
            Button(action: action) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityLabel(title)
        }
    }
}

struct AppFilterRow<Content: View>: View {
    let showsClearButton: Bool
    let clearAction: () -> Void
    let content: Content

    init(
        showsClearButton: Bool,
        clearAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.showsClearButton = showsClearButton
        self.clearAction = clearAction
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if showsClearButton {
                FilterClearButton(action: clearAction)
            }
        }
    }
}

struct AppFilterClearAllRow: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            if isVisible {
                FilterClearButton(action: action)
            }
        }
    }
}

struct AppFilterRangeControl: View {
    let title: String
    let lowerValue: Binding<Double>
    let upperValue: Binding<Double>
    let bounds: ClosedRange<Double>
    var step: Double = 1
    var maxWidth: CGFloat? = nil
    var unavailableText: String? = nil
    var lowerLabel: String? = nil
    var upperLabel: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.system(size: 12, weight: .medium))

            if bounds.lowerBound < bounds.upperBound {
                if lowerLabel != nil || upperLabel != nil {
                    HStack(alignment: .top, spacing: 10) {
                        if let lowerLabel {
                            AppMetadataLabel(text: lowerLabel, style: .micro)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let upperLabel {
                            AppMetadataLabel(text: upperLabel, style: .micro)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                AppRangeSlider(
                    lowerValue: lowerValue,
                    upperValue: upperValue,
                    bounds: bounds,
                    step: step,
                    lowerLabel: lowerLabel ?? "Min",
                    upperLabel: upperLabel ?? "Max"
                )
            } else {
                Text(verbatim: unavailableText ?? String(Int(bounds.lowerBound)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
        .layoutPriority(1)
    }
}

struct AppRangeSlider: View {
    let lowerValue: Binding<Double>
    let upperValue: Binding<Double>
    let bounds: ClosedRange<Double>
    var step: Double = 1
    var selectionFill: Color = AppPalette.linkAction
    var thumbSize: CGFloat = 22
    var trackHeight: CGFloat = 4
    var lowerLabel: String = "Min"
    var upperLabel: String = "Max"
    @State private var activeThumb: Thumb?

    private enum Thumb {
        case lower
        case upper
    }

    var body: some View {
        GeometryReader { proxy in
            let thumbRadius = thumbSize / 2
            let trackWidth = max(proxy.size.width - thumbSize, 1)
            let lowerX = thumbRadius + normalizedPosition(for: lowerValue.wrappedValue) * trackWidth
            let upperX = thumbRadius + normalizedPosition(for: upperValue.wrappedValue) * trackWidth
            let selectionStart = min(lowerX, upperX)
            let selectionWidth = abs(upperX - lowerX)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(AppPalette.subtleBorder.opacity(0.55))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbRadius)

                Capsule(style: .continuous)
                    .fill(selectionFill)
                    .frame(width: selectionWidth, height: trackHeight)
                    .offset(x: selectionStart)

                sliderThumb(isActive: activeThumb == .lower)
                    .offset(x: lowerX - thumbRadius)
                    .zIndex(activeThumb == .lower ? 2 : 1)

                sliderThumb(isActive: activeThumb == .upper)
                    .offset(x: upperX - thumbRadius)
                    .zIndex(activeThumb == .upper ? 2 : 1)
            }
            .frame(maxWidth: .infinity, minHeight: thumbSize, maxHeight: thumbSize, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let thumb = activeThumb ?? nearestThumb(
                            to: value.startLocation.x,
                            lowerX: lowerX,
                            upperX: upperX
                        )
                        activeThumb = thumb
                        update(thumb, with: value.location.x, thumbRadius: thumbRadius, trackWidth: trackWidth)
                    }
                    .onEnded { _ in
                        activeThumb = nil
                    }
            )
        }
        .frame(height: thumbSize)
        // The drawn thumbs are invisible to VoiceOver and have no keyboard
        // path; expose the range as two standard sliders instead. Both use the
        // full bounds — value-dependent sub-ranges crashed on stale persisted
        // filter values and on single-year data (degenerate ranges).
        .accessibilityRepresentation {
            if bounds.upperBound > bounds.lowerBound {
                VStack {
                    Slider(value: lowerValue, in: bounds, step: step > 0 ? step : 1) {
                        Text(lowerLabel)
                    }
                    Slider(value: upperValue, in: bounds, step: step > 0 ? step : 1) {
                        Text(upperLabel)
                    }
                }
            } else {
                Text("\(lowerLabel) – \(upperLabel)")
            }
        }
    }

    private func sliderThumb(isActive: Bool) -> some View {
        Circle()
            .fill(AppPalette.cardSurface)
            .frame(width: thumbSize, height: thumbSize)
            .shadow(color: Color.black.opacity(isActive ? 0.20 : 0.14), radius: isActive ? 4 : 3, y: 1)
            .overlay(
                Circle()
                    .stroke(isActive ? selectionFill : AppPalette.subtleBorder, lineWidth: isActive ? 1.4 : 1)
            )
    }

    private func nearestThumb(to locationX: CGFloat, lowerX: CGFloat, upperX: CGFloat) -> Thumb {
        let lowerDistance = abs(locationX - lowerX)
        let upperDistance = abs(locationX - upperX)
        if lowerDistance == upperDistance {
            return locationX <= lowerX ? .lower : .upper
        }
        return lowerDistance < upperDistance ? .lower : .upper
    }

    private func update(_ thumb: Thumb, with locationX: CGFloat, thumbRadius: CGFloat, trackWidth: CGFloat) {
        let nextValue = snappedValue(for: locationX, thumbRadius: thumbRadius, trackWidth: trackWidth)
        switch thumb {
        case .lower:
            lowerValue.wrappedValue = min(nextValue, upperValue.wrappedValue)
        case .upper:
            upperValue.wrappedValue = max(nextValue, lowerValue.wrappedValue)
        }
    }

    private func normalizedPosition(for value: Double) -> CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 0 }
        let clampedValue = min(max(value, bounds.lowerBound), bounds.upperBound)
        return CGFloat((clampedValue - bounds.lowerBound) / span)
    }

    private func snappedValue(for locationX: CGFloat, thumbRadius: CGFloat, trackWidth: CGFloat) -> Double {
        let fraction = min(max((locationX - thumbRadius) / trackWidth, 0), 1)
        let rawValue = bounds.lowerBound + (Double(fraction) * (bounds.upperBound - bounds.lowerBound))
        guard step > 0 else {
            return min(max(rawValue, bounds.lowerBound), bounds.upperBound)
        }
        let steppedValue = bounds.lowerBound + (round((rawValue - bounds.lowerBound) / step) * step)
        return min(max(steppedValue, bounds.lowerBound), bounds.upperBound)
    }
}

struct AppWorkspacePanel<Content: View>: View {
    let title: String
    var titleStyle: TitleStyle = .heading
    var contentPadding: CGFloat = AppPalette.sectionPadding
    var contentSpacing: CGFloat = AppPalette.titleSpacing + 4
    var fill: Color = AppPalette.secondaryCardSurface
    var stroke: Color = AppPalette.subtleBorder
    var usesInnerSurface = true
    var clearBackgroundInDarkNew = false
    var titleActionTitle: String? = nil
    var titleAction: (() -> Void)? = nil
    let content: Content

    enum TitleStyle {
        case heading
        case divider
        case none
    }

    init(
        title: String,
        titleStyle: TitleStyle = .heading,
        contentPadding: CGFloat = AppPalette.sectionPadding,
        contentSpacing: CGFloat = AppPalette.titleSpacing + 4,
        fill: Color = AppPalette.secondaryCardSurface,
        stroke: Color = AppPalette.subtleBorder,
        usesInnerSurface: Bool = true,
        clearBackgroundInDarkNew: Bool = false,
        titleActionTitle: String? = nil,
        titleAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleStyle = titleStyle
        self.contentPadding = contentPadding
        self.contentSpacing = contentSpacing
        self.fill = fill
        self.stroke = stroke
        self.usesInnerSurface = usesInnerSurface
        self.clearBackgroundInDarkNew = clearBackgroundInDarkNew
        self.titleActionTitle = titleActionTitle
        self.titleAction = titleAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            if let visibleTitle = title.nonEmpty {
                switch titleStyle {
                case .heading:
                    HStack(spacing: 6) {
                        AppPanelHeadingText(text: visibleTitle)
                        titleActionButton
                        Spacer(minLength: 0)
                    }
                case .divider:
                    HStack(spacing: 12) {
                        Text(visibleTitle)
                            .appTypography(.sectionTitle)
                            .foregroundStyle(AppPalette.appText)
                        titleActionButton
                        Rectangle()
                            .fill(AppPalette.subtleBorder.opacity(AppRuntime.usesRenewedChrome ? 0.9 : 1))
                            .frame(height: 1)
                    }
                case .none:
                    EmptyView()
                }
            }

            if usesInnerSurface {
                AppPanelSurface(
                    padding: contentPadding,
                    fill: fill,
                    stroke: stroke,
                    clearBackgroundInDarkNew: clearBackgroundInDarkNew
                ) {
                    content
                }
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var titleActionButton: some View {
        if let titleActionTitle, let titleAction {
            AppIconAddButton(title: titleActionTitle, action: titleAction)
        }
    }
}

struct AppDividerPanel<Content: View>: View {
    let title: String
    var contentSpacing: CGFloat = 12
    var titleActionTitle: String? = nil
    var titleAction: (() -> Void)? = nil
    let content: Content

    init(
        title: String,
        contentSpacing: CGFloat = 12,
        titleActionTitle: String? = nil,
        titleAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.contentSpacing = contentSpacing
        self.titleActionTitle = titleActionTitle
        self.titleAction = titleAction
        self.content = content()
    }

    var body: some View {
        AppWorkspacePanel(
            title: title,
            titleStyle: .divider,
            contentSpacing: contentSpacing,
            usesInnerSurface: false,
            titleActionTitle: titleActionTitle,
            titleAction: titleAction
        ) {
            content
        }
    }
}

struct AppCompactReferenceTable<Header: View, Rows: View>: View {
    let title: String?
    let isEmpty: Bool
    var emptyTitle: String
    var emptySubtitle: String = ""
    let contentMinWidth: CGFloat
    let header: Header
    let rows: Rows

    init(
        title: String? = nil,
        isEmpty: Bool,
        emptyTitle: String,
        emptySubtitle: String = "",
        contentMinWidth: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder rows: () -> Rows
    ) {
        self.title = title
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.contentMinWidth = contentMinWidth
        self.header = header()
        self.rows = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let heading = title?.nonEmpty {
                Text(heading)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if isEmpty {
                AppCompactEmptyListLabel(title: emptyTitle, subtitle: emptySubtitle)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        Divider()
                        rows
                    }
                    .frame(minWidth: contentMinWidth, maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct AppCompactEmptyListLabel: View {
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let subtitle = subtitle.nonEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
    }
}

struct AppCompactListSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

struct AppPersonNameText: View {
    let name: String
    var details: [String] = []
    var isCurrentUser = false
    var lineLimit: Int? = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(name)
                .fontWeight(isCurrentUser ? .semibold : .regular)
                .foregroundStyle(AppPalette.appText)
                .lineLimit(lineLimit)
                .truncationMode(.tail)

            if !details.isEmpty {
                Text("(\(details.joined(separator: ", ")))")
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
                    .lineLimit(lineLimit)
                    .truncationMode(.tail)
            }
        }
        .appTypography(.body)
    }
}

struct AppStatusDot: View {
    let fill: Color
    var stroke: Color = AppPalette.subtleBorder
    var label: String? = nil
    var size: CGFloat = 14
    var lineWidth: CGFloat = 1
    var help: String? = nil
    var maxWidth: CGFloat? = nil

    var body: some View {
        let dot = Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(stroke, lineWidth: lineWidth)
            )

        Group {
            if let maxWidth {
                dot.frame(maxWidth: maxWidth, alignment: .center)
            } else {
                dot
            }
        }
        .help(accessibilityText)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        help ?? label ?? ""
    }
}

struct AppCompactReferenceRowButton<Content: View>: View {
    var action: () -> Void
    let content: Content

    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AppCompactReferenceList<Content: View>: View {
    let isEmpty: Bool
    let emptyTitle: String
    var emptySubtitle: String = ""
    var rowSpacing: CGFloat = 8
    let content: Content

    init(
        isEmpty: Bool,
        emptyTitle: String,
        emptySubtitle: String = "",
        rowSpacing: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.rowSpacing = rowSpacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            if isEmpty {
                AppCompactEmptyListLabel(title: emptyTitle, subtitle: emptySubtitle)
            } else {
                content
            }
        }
    }
}

struct AppEditablePersonTable<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
    }
}

struct AppPublicationJournalStatusTable<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(8)
    }
}

struct ListCountFootnote: View {
    let displayedCount: Int
    let totalCount: Int
    let language: AppLanguage

    var body: some View {
        if displayedCount != totalCount {
            Text(footerText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footerText: String {
        if language == .swedish {
            return "Visar \(displayedCount) av \(totalCount) poster"
        }
        return "Showing \(displayedCount) of \(totalCount) records"
    }
}

struct AppActiveFilterChip: View {
    let title: String
    var systemImage: String = "line.3.horizontal.decrease.circle"
    // Names the clear action for tooltip/VoiceOver; the chip title alone
    // reads as the filter itself, not as "remove this filter".
    var clearTitle: String? = nil
    var clearAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let clearAction {
                Button(action: clearAction) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(clearTitle ?? title)
                .accessibilityLabel(clearTitle ?? title)
            }
        }
        .foregroundStyle(AppPalette.appText.opacity(0.86))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(AppPalette.pillSurface.opacity(0.86))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
        .help(title)
    }
}

struct AppInlineDataQualityIssue: Identifiable, Equatable {
    let id: String
    let title: String
    let details: String
    let severity: GrantDataStore.MissingFieldIssue.Severity
}

struct AppInlineDataQualityPanel: View {
    let title: String
    let issues: [AppInlineDataQualityIssue]
    let openTitle: String
    var openAction: (() -> Void)? = nil

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: containsCriticalIssue ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(containsCriticalIssue ? AppPalette.vividRed : AppPalette.vividOrange)
                    Text(title)
                        .appTypography(.tableHeader)
                    Spacer()
                    if let openAction {
                        Button(openTitle, action: openAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                ForEach(issues.prefix(4)) { issue in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(issue.severity == .critical ? AppPalette.vividRed : AppPalette.vividOrange)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            if !issue.details.isEmpty {
                                Text(issue.details)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                if issues.count > 4 {
                    Text("+\(issues.count - 4)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(containsCriticalIssue ? AppPalette.shadeRed.opacity(0.16) : AppPalette.pillSurface.opacity(0.58))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke((containsCriticalIssue ? AppPalette.vividRed : AppPalette.vividOrange).opacity(0.42), lineWidth: 1)
            )
        }
    }

    private var containsCriticalIssue: Bool {
        issues.contains { $0.severity == .critical }
    }
}


struct FootprintMetadataChip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected = false
    var action: (() -> Void)? = nil

    init(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    chipLabel
                }
                .buttonStyle(.plain)
            } else {
                chipLabel
            }
        }
        .help(title)
    }

    private var chipLabel: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? AppPalette.activeTabText : AppPalette.appText.opacity(0.82))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? AppPalette.activeTabSurface : AppPalette.fieldSurface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isSelected ? AppPalette.activeTabSurface.opacity(0.36) : AppPalette.subtleBorder, lineWidth: 1)
        )
    }
}


enum AppMetadataLabelStyle {
    case normal
    case count
    case micro
    case monospaced
}

struct AppMetadataLabel: View {
    let text: String
    var style: AppMetadataLabelStyle = .normal
    var foreground: Color = .secondary
    var lineLimit: Int = 1

    @ViewBuilder
    var body: some View {
        if style == .count || style == .monospaced {
            Text(text)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(foreground)
                .lineLimit(lineLimit)
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(foreground)
                .lineLimit(lineLimit)
        }
    }

    private var font: Font {
        switch style {
        case .normal:
            return .system(size: 11, weight: .semibold)
        case .count:
            return .system(size: 11, weight: .bold)
        case .micro:
            return .system(size: 10, weight: .semibold)
        case .monospaced:
            return .system(size: 11, weight: .semibold, design: .monospaced)
        }
    }
}


struct AppStatisticCardModifier: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous).fill(AppPalette.cardSurface))
            .overlay(RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous).stroke(AppPalette.subtleBorder, lineWidth: 1))
    }
}

struct AppOutcomeBarItem: Identifiable {
    let id: String
    let title: String
    let count: Int
    let total: Int
    let tint: Color
    var fillOpacity: Double = 0.84
}

struct AppOutcomeBars: View {
    let items: [AppOutcomeBarItem]
    var labelWidth: CGFloat = 76
    var countWidth: CGFloat = 66

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                let denominator = max(item.total, 1)
                let fraction = Double(item.count) / Double(denominator)
                HStack(spacing: 10) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .leading)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(AppPalette.fieldSurface)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(item.tint.opacity(item.fillOpacity))
                                .frame(width: max(0, proxy.size.width * fraction))
                        }
                    }
                    .frame(height: 10)

                    Text("\(item.count) (\(Int((fraction * 100).rounded())) %)")
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(AppPalette.appText)
                        .frame(width: countWidth, alignment: .trailing)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppPalette.secondaryCardSurface))
    }
}

struct AppStatisticListRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    var titleLineLimit = 1
    var subtitleLineLimit = 1
    let leading: Leading
    let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        titleLineLimit: Int = 1,
        subtitleLineLimit: Int = 1,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.appText)
                    .lineLimit(titleLineLimit)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(subtitleLineLimit)
            }

            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppPalette.fieldSurface))
    }
}

struct SortableListHeaderLabel: View {
    let title: String
    let ascending: Bool?
    var sortIndex: Int? = nil
    var fontSize: CGFloat = 12
    var foreground: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if let ascending {
                Image(systemName: ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                if let sortIndex {
                    Text("\(sortIndex + 1)")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
        }
        .font(.system(size: fontSize, weight: .semibold))
        .foregroundStyle(foreground)
        .contentShape(Rectangle())
    }
}

struct AppSortableListHeader: View {
    let title: String
    let ascending: Bool?
    var sortIndex: Int? = nil
    var width: CGFloat? = nil
    var minWidth: CGFloat? = nil
    var maxWidth: CGFloat? = nil
    var alignment: Alignment = .leading
    var fontSize: CGFloat = 12
    var foreground: Color = .secondary
    let resetTitle: String
    let onToggle: () -> Void
    var onReset: (() -> Void)? = nil

    var body: some View {
        Button(action: onToggle) {
            SortableListHeaderLabel(
                title: title,
                ascending: ascending,
                sortIndex: sortIndex,
                fontSize: fontSize,
                foreground: foreground
            )
                .frame(width: width, alignment: alignment)
                .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: alignment)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onReset {
                Button(resetTitle, action: onReset)
            }
        }
    }
}

struct FootprintDialogFrame<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    var closeAction: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .appTypography(.pageTitle)
                    if let subtitle {
                        Text(subtitle)
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 16)
                if let closeAction {
                    Button(action: closeAction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppPalette.fieldSurface)
                    )
                }
            }

            content()

            HStack(spacing: 12) {
                footer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppPalette.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppPalette.subtleBorder, lineWidth: 1)
            )
        }
        .padding(24)
        .background(AppPalette.secondaryCardSurface)
    }
}

struct FootprintDialogActions: View {
    let cancelTitle: String
    let primaryTitle: String
    var primarySystemImage: String? = nil
    var primaryTint: Color = AppPalette.actionSave
    var isPrimaryDisabled = false
    var includesLeadingSpacer = true
    let cancelAction: () -> Void
    let primaryAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if includesLeadingSpacer {
                Spacer(minLength: 0)
            }
            Button(cancelTitle, action: cancelAction)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button(action: primaryAction) {
                if let primarySystemImage {
                    Label(primaryTitle, systemImage: primarySystemImage)
                } else {
                    Text(primaryTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(primaryTint)
            .keyboardShortcut(.defaultAction)
            .disabled(isPrimaryDisabled)
        }
    }
}

struct DeleteActionButton: View {
    let title: String
    var systemImage = "trash"
    var confirmationTitle: String? = nil
    var confirmationMessage: String? = nil
    // No default: an English "Cancel" would leak into the Swedish UI.
    let cancelTitle: String
    let action: () -> Void

    @State private var showsConfirmation = false

    var body: some View {
        Button(role: .destructive) {
            showsConfirmation = true
        } label: {
            Label(title, systemImage: systemImage)
        }
        .appDeleteButtonStyle()
        .confirmationDialog(
            confirmationTitle ?? title,
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button(title, role: .destructive, action: action)
            Button(cancelTitle, role: .cancel) {}
        } message: {
            if let confirmationMessage {
                Text(confirmationMessage)
            }
        }
    }
}

struct AppDestructiveActionButton: View {
    let title: String
    var systemImage = "trash"
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: systemImage)
        }
        .appDeleteButtonStyle()
        .help(help ?? title)
        .accessibilityLabel(help ?? title)
    }
}

struct AppIconDeleteButton: View {
    let title: String
    var systemImage = "trash"
    var font: Font = .system(size: 13, weight: .semibold)
    var width: CGFloat? = nil
    var action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: systemImage)
                .font(font)
                .foregroundStyle(AppPalette.actionDelete)
                .frame(width: width, alignment: .center)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(AppPalette.actionDelete)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct AppInlineDeleteButton: View {
    let title: String
    var font: Font = .system(size: 13, weight: .semibold)
    var width: CGFloat? = nil
    var action: () -> Void

    var body: some View {
        AppIconDeleteButton(title: title, font: font, width: width, action: action)
            .accessibilityLabel(title)
    }
}

struct AppIconAddButton: View {
    let title: String
    var systemImage = "plus.circle"
    var font: Font = .system(size: 13, weight: .semibold)
    var width: CGFloat? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(font)
                .foregroundStyle(AppPalette.linkAction)
                .frame(width: width, alignment: .center)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}


struct AppRouteLinkButton: View {
    let title: String
    let language: AppLanguage
    var fontSize: CGFloat = 12
    var showsTitle = false
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        AppDestinationActionButton(
            kind: .app,
            language: language,
            title: title,
            fontSize: fontSize,
            showsTitle: showsTitle,
            width: width,
            height: height,
            isEnabled: true,
            action: action
        )
    }
}

struct AppTaskCompletionToggle: View {
    let isCompleted: Binding<Bool>

    var body: some View {
        Toggle("", isOn: isCompleted)
            .labelsHidden()
            .appCheckboxStyle()
    }
}

struct AppBadgeColors {
    let foreground: Color
    let background: Color
    let stroke: Color

    static let positiveSolid = AppBadgeColors(
        foreground: AppPalette.semanticOnColor,
        background: AppPalette.vividGreen,
        stroke: AppPalette.vividGreen.opacity(0.78)
    )

    static let positiveMuted = AppBadgeColors(
        foreground: .primary,
        background: AppPalette.shadeGreen,
        stroke: AppPalette.vividGreen
    )

    static let negativeMuted = AppBadgeColors(
        foreground: .primary,
        background: AppPalette.shadeRed,
        stroke: AppPalette.vividRed
    )

    static let pendingSolid = AppBadgeColors(
        foreground: AppPalette.semanticOnColor,
        background: AppPalette.vividYellow,
        stroke: AppPalette.vividYellow.opacity(0.82)
    )

    static let pendingMuted = AppBadgeColors(
        foreground: .primary,
        background: AppPalette.shadeYellow,
        stroke: AppPalette.vividYellow
    )

    static let neutralOutline = AppBadgeColors(
        foreground: .primary,
        background: AppPalette.fieldSurface,
        stroke: AppPalette.border
    )

    static let neutralCard = AppBadgeColors(
        foreground: AppPalette.appText,
        background: AppPalette.secondaryCardSurface,
        stroke: AppPalette.border.opacity(0.55)
    )

    static let saveSolid = AppBadgeColors(
        foreground: AppPalette.semanticOnColor,
        background: AppPalette.actionSave.opacity(0.86),
        stroke: AppPalette.border.opacity(0.55)
    )

    static func lifecycle(_ status: ProjectLifecycleStatus) -> AppBadgeColors {
        switch status {
        case .planned:
            return AppBadgeColors(foreground: AppPalette.semanticOnColor, background: AppPalette.vividYellow, stroke: .clear)
        case .ongoing:
            return AppBadgeColors(foreground: AppPalette.semanticOnColor, background: AppPalette.vividGreen, stroke: .clear)
        case .completed:
            return AppBadgeColors(foreground: AppPalette.semanticOnColor, background: AppPalette.chartRed, stroke: .clear)
        }
    }
}

struct AppSemanticStatusBadge: View {
    let text: String
    let colors: AppBadgeColors
    var size: AppBadgeText.Size = .normal
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 4
    var showsIndicator = false

    var body: some View {
        AppToneBadge(
            text: text,
            size: size,
            foreground: colors.foreground,
            background: colors.background,
            stroke: colors.stroke,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            showsIndicator: showsIndicator,
            indicatorColor: colors.foreground.opacity(0.9)
        )
    }
}

struct AppPublicationStatusTextBadge: View {
    let status: String
    let language: AppLanguage
    var verticalPadding: CGFloat = 5

    var body: some View {
        let resolvedStatus = PublicationStatus.fromStored(status)
        AppSemanticStatusBadge(
            text: resolvedStatus.displayName(language: language),
            colors: appPublicationStatusBadgeColors(for: resolvedStatus),
            verticalPadding: verticalPadding
        )
    }
}


enum AppConferenceContributionBadgeStatus {
    case planned
    case submitted
    case accepted
    case rejected
    case presented

    init(contribution: CVConferenceContribution, referenceDate: Date = Date()) {
        if contribution.submissionOutcome == .declined {
            self = .rejected
        } else if contribution.status == .presented || Self.congressHasPassed(contribution, referenceDate: referenceDate) {
            self = .presented
        } else if contribution.submissionOutcome == .granted {
            self = .accepted
        } else if contribution.submissionAppliedOn.nonEmpty != nil {
            self = .submitted
        } else {
            self = .planned
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .planned:
            return language.text("Planned", "Planerat")
        case .submitted:
            return language.text("Submitted", "Inskickat")
        case .accepted:
            return language.text("Accepted", "Accepterat")
        case .rejected:
            return language.text("Rejected", "Refuserat")
        case .presented:
            return language.text("Presented", "Presenterat")
        }
    }

    var badgeColors: AppBadgeColors {
        switch self {
        case .presented, .accepted:
            return .positiveMuted
        case .rejected:
            return .negativeMuted
        case .submitted:
            return .pendingMuted
        case .planned:
            return .neutralOutline
        }
    }

    private static func congressHasPassed(_ contribution: CVConferenceContribution, referenceDate: Date) -> Bool {
        let today = Calendar.current.startOfDay(for: referenceDate)
        if let end = parsedDay(contribution.to) {
            return end < today
        }
        if let start = parsedDay(contribution.from) {
            return start < today
        }
        return false
    }

    private static func parsedDay(_ value: String) -> Date? {
        guard let trimmed = value.nonEmpty else { return nil }
        return DateParsers.isoDay.date(from: trimmed)
    }
}

func appPublicationStatusBadgeColors(for status: PublicationStatus) -> AppBadgeColors {
    switch status {
    case .published, .accepted:
        return .positiveSolid
    case .submitted:
        return .pendingSolid
    case .rejected:
        return .negativeMuted
    case .planned, .inPreparation:
        return .pendingMuted
    }
}

enum PublicationStatusIndicatorStyle: Equatable {
    case neutralOutline
    case inProgressSolid
    case negativeSolid
    case positiveSolid
}

func publicationStatusIndicatorStyle(for status: PublicationStatus) -> PublicationStatusIndicatorStyle {
    switch status {
    case .published, .accepted:
        return .positiveSolid
    case .submitted:
        return .inProgressSolid
    case .rejected:
        return .negativeSolid
    case .planned, .inPreparation:
        return .neutralOutline
    }
}

func appPublicationStatusIndicatorColors(for status: PublicationStatus) -> (fill: Color, stroke: Color) {
    switch publicationStatusIndicatorStyle(for: status) {
    case .positiveSolid:
        return (AppPalette.vividGreen, AppPalette.vividGreen.opacity(0.84))
    case .inProgressSolid:
        return (AppPalette.vividYellow, AppPalette.vividYellow.opacity(0.86))
    case .negativeSolid:
        return (AppPalette.vividRed, AppPalette.vividRed.opacity(0.86))
    case .neutralOutline:
        return (.white, AppPalette.border.opacity(0.95))
    }
}

private struct AppDeleteButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        // No forced foreground color: borderedProminent adapts its label to
        // the bezel, including the desaturated bezel of an inactive window —
        // forced white there was unreadable on the near-white gray.
        content
            .font(.system(size: 13, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(AppPalette.actionDelete)
    }
}

private struct AppAddButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(AppPalette.linkAction)
    }
}

extension View {
    func appDeleteButtonStyle() -> some View {
        modifier(AppDeleteButtonModifier())
    }

    func appAddButtonStyle() -> some View {
        modifier(AppAddButtonModifier())
    }
}

// Shared "linked records" row primitives, used by the project and author
// detail panels alike.
struct AppLinkedStatusRow<Content: View>: View {
    let fill: Color?
    var help: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        let row = content
            .appTypography(.secondary)
            .foregroundStyle(AppPalette.appText)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if let fill {
                    StatusIndicatorListRowBackground(fill: fill, cornerRadius: 7)
                }
            }
            .contentShape(Rectangle())

        if let help, !help.isEmpty {
            row.help(help)
        } else {
            row
        }
    }
}

struct AppLinkedTitleTrailingRow: View {
    let title: String
    let trailingText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(trailingText)
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
