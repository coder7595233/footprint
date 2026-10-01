import AppKit
import SwiftUI

enum AppResponsiveLayout {
    static let mainMinimumWidth: CGFloat = 960
    static let mainMinimumHeight: CGFloat = 640
    static let settingsMinimumWidth: CGFloat = 920
    static let settingsMinimumHeight: CGFloat = 680
    static let dialogMinimumWidth: CGFloat = 420
    static let dialogMinimumHeight: CGFloat = 360

    static func clampedDialogMinimum(
        idealWidth: CGFloat,
        idealHeight: CGFloat,
        minimumWidth: CGFloat = dialogMinimumWidth,
        minimumHeight: CGFloat = dialogMinimumHeight
    ) -> CGSize {
        CGSize(
            width: min(max(0, minimumWidth), max(0, idealWidth)),
            height: min(max(0, minimumHeight), max(0, idealHeight))
        )
    }
}

extension View {
    func appResponsiveDialogFrame(
        idealWidth: CGFloat,
        idealHeight: CGFloat,
        minimumWidth: CGFloat = AppResponsiveLayout.dialogMinimumWidth,
        minimumHeight: CGFloat = AppResponsiveLayout.dialogMinimumHeight
    ) -> some View {
        let minimum = AppResponsiveLayout.clampedDialogMinimum(
            idealWidth: idealWidth,
            idealHeight: idealHeight,
            minimumWidth: minimumWidth,
            minimumHeight: minimumHeight
        )
        return frame(
            minWidth: minimum.width,
            idealWidth: idealWidth,
            maxWidth: idealWidth,
            minHeight: minimum.height,
            idealHeight: idealHeight,
            maxHeight: idealHeight
        )
    }
}

struct AppFieldLabelText: View {
    let text: String
    var help: String? = nil

    // Field labels never hyphenate or wrap — they always take the one line
    // they need, even when the field below is narrower than the label.
    @ViewBuilder
    var body: some View {
        if let help {
            Text(text)
                .appTypography(.fieldLabel)
                .foregroundStyle(AppPalette.appText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .help(help)
        } else {
            Text(text)
                .appTypography(.fieldLabel)
                .foregroundStyle(AppPalette.appText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct AppTableHeaderText: View {
    let text: String

    var body: some View {
        // Round 16: table headers use the table-header role; the leading
        // padding keeps them aligned with the field text below.
        Text(text)
            .font(appFont(.tableHeader))
            .padding(.leading, AppPalette.fieldHorizontalPadding)
            .foregroundStyle(AppPalette.appText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct AppFieldAlignedTableHeaderText: View {
    let text: String

    var body: some View {
        AppTableHeaderText(text: text)
            .frame(maxWidth: .infinity, minHeight: AppPalette.fieldMinHeight, alignment: .leading)
    }
}

struct AppPanelHeadingText: View {
    let text: String

    var body: some View {
        Text(text)
            .appTypography(.panelTitle)
            .foregroundStyle(AppPalette.appText)
    }
}

struct AppSectionDividerHeading: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .appTypography(.sectionTitle)
                .foregroundStyle(AppPalette.appText)
            Rectangle()
                .fill(AppPalette.subtleBorder.opacity(AppRuntime.usesRenewedChrome ? 0.9 : 1))
                .frame(height: 1)
        }
        .padding(.top, AppRuntime.usesRenewedChrome ? 3 : 0)
        .padding(.bottom, AppRuntime.usesRenewedChrome ? 1 : 0)
    }
}

struct AppMetadataText: View {
    let text: String

    var body: some View {
        Text(text)
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
    }
}

struct AppRecordSubtitleText: View {
    let text: String
    var lineLimit: Int? = 2

    var body: some View {
        Text(text)
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
    }
}

struct AppLockedValueText: View {
    let text: String?
    var lineLimit: Int? = 2
    var isInvalid = false
    var help: String? = nil
    var reservesFieldHeight = false
    var language: AppLanguage = .swedish

    var body: some View {
        let state: AppFieldVisualState = isInvalid ? .invalid(help) : .locked
        Text(displayText)
            .font(appFont(.body))
            .monospacedDigit()
            .foregroundStyle(AppPalette.appText)
            .lineLimit(lineLimit)
            .textSelection(.enabled)
            .padding(.horizontal, reservesFieldHeight || isInvalid ? AppPalette.textFieldHorizontalPadding : 0)
            .padding(.vertical, isInvalid ? AppPalette.textFieldVerticalPadding : 0)
            .frame(minHeight: reservesFieldHeight || isInvalid ? AppPalette.fieldMinHeight : 18, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                    .fill(isInvalid ? state.fill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                    .stroke(isInvalid ? state.stroke : Color.clear, lineWidth: 1)
            )
            .help(state.helpText ?? "")
            .contextMenu {
                Button(language.text("Copy", "Kopiera")) {
                    copyTextToPasteboard()
                }
                .disabled(copyableText == nil)
            }
    }

    private var displayText: String {
        copyableText ?? "–"
    }

    private var copyableText: String? {
        text?.trimmedOrNil
    }

private func copyTextToPasteboard() {
        guard let copyableText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyableText, forType: .string)
    }
}

struct AppLockedFieldValueText: View {
    let text: String?
    var lineLimit: Int? = 2
    var isInvalid = false
    var help: String? = nil

    var body: some View {
        AppLockedValueText(
            text: text,
            lineLimit: lineLimit,
            isInvalid: isInvalid,
            help: help,
            reservesFieldHeight: true
        )
    }
}

struct AppLockedInlineValueText: View {
    let text: String?
    var lineLimit: Int? = 2
    var isInvalid = false
    var help: String? = nil
    var alignsWithFieldLabel = true

    var body: some View {
        AppLockedValueText(
            text: text,
            lineLimit: lineLimit,
            isInvalid: isInvalid,
            help: help,
            reservesFieldHeight: false
        )
        .padding(.leading, alignsWithFieldLabel && !isInvalid ? AppPalette.fieldHorizontalPadding : 0)
    }
}

enum AppLockedFieldPresentation {
    case field
    case inline
}

struct AppLockableField<EditingContent: View>: View {
    let isLocked: Bool
    let lockedText: String?
    var lockedLineLimit: Int? = 2
    var state: AppFieldVisualState = .normal
    var lockedPresentation: AppLockedFieldPresentation = .field
    let editingContent: EditingContent

    init(
        isLocked: Bool,
        lockedText: String?,
        lockedLineLimit: Int? = 2,
        state: AppFieldVisualState = .normal,
        lockedPresentation: AppLockedFieldPresentation = .field,
        @ViewBuilder editingContent: () -> EditingContent
    ) {
        self.isLocked = isLocked
        self.lockedText = lockedText
        self.lockedLineLimit = lockedLineLimit
        self.state = state
        self.lockedPresentation = lockedPresentation
        self.editingContent = editingContent()
    }

    @ViewBuilder
    var body: some View {
        if isLocked {
            switch lockedPresentation {
            case .field:
                AppLockedFieldValueText(
                    text: lockedText,
                    lineLimit: lockedLineLimit,
                    isInvalid: state.isInvalid,
                    help: state.helpText
                )
            case .inline:
                AppLockedInlineValueText(
                    text: lockedText,
                    lineLimit: lockedLineLimit,
                    isInvalid: state.isInvalid,
                    help: state.helpText
                )
            }
        } else {
            editingContent
        }
    }
}


struct AppLabeledContentRow<Content: View>: View {
    let title: String
    var titleWidth: CGFloat = 220
    var titleTopPadding: CGFloat = 6
    var spacing: CGFloat = 12
    var titleLineLimit: Int = 2
    let content: Content

    init(
        title: String,
        titleWidth: CGFloat = 220,
        titleTopPadding: CGFloat = 6,
        spacing: CGFloat = 12,
        titleLineLimit: Int = 2,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleWidth = titleWidth
        self.titleTopPadding = titleTopPadding
        self.spacing = spacing
        self.titleLineLimit = titleLineLimit
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            AppCompactRowTitleText(text: title, lineLimit: titleLineLimit)
                .frame(width: titleWidth, alignment: .leading)
                .padding(.top, titleTopPadding)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AppLabeledField<Content: View, Accessory: View>: View {
    let title: String
    var help: String? = nil
    var compact = false
    var width: CGFloat? = nil
    var fillsAvailableWidth = true
    let accessory: Accessory
    let content: Content

    init(
        title: String,
        help: String? = nil,
        compact: Bool = false,
        width: CGFloat? = nil,
        fillsAvailableWidth: Bool = true,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.title = title
        self.help = help
        self.compact = compact
        self.width = width
        self.fillsAvailableWidth = fillsAvailableWidth
        self.accessory = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        help: String? = nil,
        compact: Bool = false,
        width: CGFloat? = nil,
        fillsAvailableWidth: Bool = true,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.help = help
        self.compact = compact
        self.width = width
        self.fillsAvailableWidth = fillsAvailableWidth
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: visibleTitle == nil ? 0 : (compact ? 2 : 6)) {
            if let visibleTitle {
                HStack(spacing: 6) {
                    AppFieldLabelText(text: visibleTitle, help: help)
                    accessory
                }
            }
            content
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil && fillsAvailableWidth ? .infinity : nil, alignment: .leading)
    }

    private var visibleTitle: String? {
        title.trimmedOrNil
    }
}

struct AppCompactField<Content: View>: View {
    let title: String
    var width: CGFloat? = nil
    var help: String? = nil
    var fillsAvailableWidth = false
    let content: Content

    init(
        _ title: String,
        width: CGFloat? = nil,
        help: String? = nil,
        fillsAvailableWidth: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.width = width
        self.help = help
        self.fillsAvailableWidth = fillsAvailableWidth
        self.content = content()
    }

    var body: some View {
        AppLabeledField(
            title: title,
            help: help,
            compact: true,
            width: width,
            fillsAvailableWidth: fillsAvailableWidth
        ) {
            content
        }
    }
}

struct AppOptionalCompactField<Content: View>: View {
    let title: String?
    var width: CGFloat? = nil
    var help: String? = nil
    var fillsAvailableWidth = false
    var contentTopPaddingWhenUntitled: CGFloat = 6
    let content: Content

    init(
        _ title: String?,
        width: CGFloat? = nil,
        help: String? = nil,
        fillsAvailableWidth: Bool = false,
        contentTopPaddingWhenUntitled: CGFloat = 6,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.width = width
        self.help = help
        self.fillsAvailableWidth = fillsAvailableWidth
        self.contentTopPaddingWhenUntitled = contentTopPaddingWhenUntitled
        self.content = content()
    }

    var body: some View {
        AppCompactField(
            title ?? "",
            width: width,
            help: help,
            fillsAvailableWidth: fillsAvailableWidth
        ) {
            content
                .padding(.top, title == nil ? contentTopPaddingWhenUntitled : 0)
        }
    }
}

struct AppPanelSurface<Content: View>: View {
    var padding: CGFloat = AppPalette.sectionPadding
    var cornerRadius: CGFloat = AppPalette.mediumCornerRadius
    var fill: Color = AppPalette.secondaryCardSurface
    var stroke: Color = AppPalette.subtleBorder
    var usesRenewedChromeStroke = true
    var clearBackgroundInDarkNew = false
    let content: Content

    init(
        padding: CGFloat = AppPalette.sectionPadding,
        cornerRadius: CGFloat = AppPalette.mediumCornerRadius,
        fill: Color = AppPalette.secondaryCardSurface,
        stroke: Color = AppPalette.subtleBorder,
        usesRenewedChromeStroke: Bool = true,
        clearBackgroundInDarkNew: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.fill = fill
        self.stroke = stroke
        self.usesRenewedChromeStroke = usesRenewedChromeStroke
        self.clearBackgroundInDarkNew = clearBackgroundInDarkNew
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(resolvedFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(resolvedStroke, lineWidth: 1)
            )
    }

    private var resolvedFill: Color {
        clearBackgroundInDarkNew && currentVisualModePreference() == .darkNew ? Color.clear : fill
    }

    private var resolvedStroke: Color {
        usesRenewedChromeStroke && AppRuntime.usesRenewedChrome ? stroke : Color.clear
    }
}

struct AppTodayDateButton: View {
    var title: String = "Idag"
    var fill: Color = AppPalette.cardSurface
    var horizontalPadding: CGFloat? = nil
    var isCompact = false
    var minWidth: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Group {
            if AppRuntime.usesRenewedChrome {
                Button(title, action: action)
                    // Same look as .appTypography(.fieldLabel) but WITHOUT its
                    // asymmetric leading label padding, which pushed the text
                    // off-center inside the capsule.
                    .font(appFont(.fieldLabel))
                    .foregroundStyle(AppPalette.appText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, horizontalPadding ?? (isCompact ? 0 : 8))
                    .padding(.vertical, isCompact ? 1 : 6)
                    .frame(minWidth: minWidth ?? (isCompact ? 32 : 50))
                    .background(
                        Capsule(style: .continuous)
                            .fill(fill)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppPalette.subtleBorder, lineWidth: 1)
                    )
                    .buttonStyle(.plain)
            } else {
                Button(title, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .lineLimit(1)
                    .frame(minWidth: minWidth ?? 50)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

struct AppCommitTextField: View {
    let placeholder: String
    let text: Binding<String>
    var formatter: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    var updatesContinuously = true
    var width: CGFloat? = nil
    var fillsWidth = true
    var state: AppFieldVisualState = .normal
    var liveVisualState: ((String) -> AppFieldVisualState)? = nil
    var textAlignment: NSTextAlignment = .left
    var horizontalPadding: CGFloat = AppPalette.textFieldHorizontalPadding
    var verticalPadding: CGFloat = AppPalette.textFieldVerticalPadding
    var minHeight: CGFloat = AppPalette.fieldMinHeight
    var fill: Color = AppPalette.fieldSurface
    var stroke: Color = AppPalette.subtleBorder

    var body: some View {
        CommitFormattingTextField(
            placeholder: placeholder,
            text: text,
            formatter: formatter,
            updatesContinuously: updatesContinuously,
            showsRenewedSurface: false,
            isBordered: false,
            textAlignment: textAlignment,
            visualState: state,
            liveVisualState: liveVisualState
        )
        .frame(minHeight: 18)
        .appTextInputChrome(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            minHeight: minHeight,
            fillsWidth: fillsWidth && width == nil,
            fill: resolvedFill,
            stroke: resolvedStroke
        )
        .appExplicitInvalidFieldChrome(effectiveState)
        .help(effectiveState.helpText ?? "")
        .frame(width: width, alignment: .leading)
    }

    private var effectiveState: AppFieldVisualState {
        liveVisualState?(text.wrappedValue) ?? state
    }

    private var resolvedFill: Color {
        effectiveState == .normal ? fill : effectiveState.fill
    }

    private var resolvedStroke: Color {
        effectiveState == .normal ? stroke : effectiveState.stroke
    }
}

struct AppInlineTitleTextField: View {
    let placeholder: String
    let text: Binding<String>
    var formatter: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    var font: NSFont = appNSFont(.pageTitle)
    var textColor: NSColor = .labelColor
    var placeholderColor: NSColor? = .secondaryLabelColor
    var minHeight: CGFloat = 30

    var body: some View {
        CommitFormattingTextField(
            placeholder: placeholder,
            text: text,
            formatter: formatter,
            updatesContinuously: true,
            showsRenewedSurface: false,
            isBordered: false,
            focusRingType: .none,
            font: font,
            textColor: textColor,
            placeholderColor: placeholderColor
        )
        .frame(minHeight: minHeight)
    }
}


struct AppTextEditorField: View {
    let title: String?
    let text: Binding<String>
    var placeholder: String? = nil
    var minimumHeight: CGFloat = 86
    var maximumHeight: CGFloat? = nil
    var fill: Color = AppPalette.fieldSurface
    var stroke: Color = AppPalette.subtleBorder
    var state: AppFieldVisualState = .normal
    var showsResizeHandle = false
    var usesPlainTextEditor = false

    @State private var editorHeight: CGFloat?
    @State private var dragStartHeight: CGFloat = 0
    @State private var compactEditorIsFocused = false
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppPalette.titleSpacing) {
            if let title {
                AppFieldLabelText(text: title)
            }
            ZStack(alignment: .bottomTrailing) {
                ZStack(alignment: editorContentAlignment) {
                    if usesCompactCommitField {
                        CommitFormattingTextField(
                            placeholder: placeholder ?? "",
                            text: text,
                            formatter: { $0 },
                            updatesContinuously: true,
                            showsRenewedSurface: false,
                            isBordered: false,
                            focusRingType: .none,
                            onFocusChange: { compactEditorIsFocused = $0 }
                        )
                        .focused($isEditorFocused)
                        .frame(height: editorTextHeight, alignment: .center)
                    } else if usesPlainTextEditor {
                        TextEditor(text: text)
                            .focused($isEditorFocused)
                            .font(appFont(.body))
                            .scrollContentBackground(.hidden)
                            .frame(height: editorTextHeight, alignment: .topLeading)
                    } else {
                        TextField("", text: text, axis: .vertical)
                            .focused($isEditorFocused)
                            .textFieldStyle(.plain)
                            .appTypography(.body)
                            .lineLimit(1...24)
                            .multilineTextAlignment(.leading)
                            .frame(height: editorTextHeight, alignment: .topLeading)
                    }

                    if !usesCompactCommitField, text.wrappedValue.isEmpty, let placeholder {
                        Text(placeholder)
                            .appTypography(.body)
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                            .padding(.top, usesPlainTextEditor ? 8 : 0)
                    }
                }
                .padding(.horizontal, editorHorizontalPadding)
                .padding(.vertical, editorVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                        .fill(resolvedFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                        .stroke(resolvedStroke, lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .appKeyboardFocusPulse(
                    isFocused: isEditorFocused || compactEditorIsFocused,
                    cornerRadius: AppPalette.mediumCornerRadius
                )
                .help(state.helpText ?? "")

                if showsResizeHandle {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        // Symbol geometry intentionally follows the resize handle,
                        // rather than user-facing text typography.
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.trailing, 10)
                        .padding(.bottom, 10)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if dragStartHeight == 0 {
                                        dragStartHeight = resolvedHeight
                                    }
                                    editorHeight = clampedHeight(dragStartHeight + value.translation.height)
                                }
                                .onEnded { _ in
                                    dragStartHeight = resolvedHeight
                                }
                        )
                }
            }
        }
    }

    private var resolvedHeight: CGFloat {
        clampedHeight(editorHeight ?? minimumHeight)
    }

    private var editorHorizontalPadding: CGFloat {
        AppPalette.textFieldHorizontalPadding
    }

    private var editorVerticalPadding: CGFloat {
        AppPalette.textFieldVerticalPadding
    }

    private var usesCompactCommitField: Bool {
        !usesPlainTextEditor
            && !showsResizeHandle
            && minimumHeight <= AppPalette.fieldMinHeight + 0.5
    }

    private var editorContentAlignment: Alignment {
        usesCompactCommitField ? .leading : .topLeading
    }

    private var editorTextHeight: CGFloat {
        max(24, resolvedHeight - editorVerticalPadding * 2)
    }

    private func clampedHeight(_ height: CGFloat) -> CGFloat {
        max(minimumHeight, min(height, maximumHeight ?? 320))
    }

    private var resolvedFill: Color {
        state == .normal ? fill : state.fill
    }

    private var resolvedStroke: Color {
        state == .normal ? stroke : state.stroke
    }
}

struct AppIdentifierField: View {
    let kind: AppIdentifierKind
    let text: Binding<String>
    var language: AppLanguage = .swedish
    var width: CGFloat? = nil

    var body: some View {
        CommitFormattingTextField(
            placeholder: placeholder,
            text: text,
            formatter: formatter,
            updatesContinuously: false,
            showsRenewedSurface: false,
            isBordered: false,
            visualState: validationState,
            liveVisualState: validator
        )
        .frame(minHeight: 18)
        .appTextInputChrome(
            fillsWidth: width == nil,
            fill: validationState.fill,
            stroke: validationState.stroke
        )
        .appExplicitInvalidFieldChrome(validationState)
        .help(validationState.helpText ?? "")
        .frame(width: width, alignment: .leading)
    }

    private var placeholder: String {
        switch kind {
        case .doi:
            return "DOI"
        case .pmid:
            return "PMID"
        case .orcid:
            return "ORCID"
        }
    }

    private var formatter: (String) -> String {
        switch kind {
        case .doi:
            return AppFieldParsers.canonicalDOI
        case .pmid:
            return AppFieldParsers.canonicalPMID
        case .orcid:
            return AppFieldParsers.canonicalORCID
        }
    }

    private var validationState: AppFieldVisualState {
        validator(text.wrappedValue)
    }

    private var validator: (String) -> AppFieldVisualState {
        switch kind {
        case .doi:
            return { AppFieldValidators.optionalDOI($0, language: language).state }
        case .pmid:
            return { AppFieldValidators.optionalPMID($0, language: language).state }
        case .orcid:
            return { AppFieldValidators.optionalORCID($0, language: language).state }
        }
    }
}

struct AppYearField: View {
    let text: Binding<String>
    var language: AppLanguage = .swedish
    var width: CGFloat? = nil

    var body: some View {
        CommitFormattingTextField(
            placeholder: language.text("Year", "År"),
            text: text,
            formatter: AppFieldParsers.canonicalYear,
            updatesContinuously: false,
            showsRenewedSurface: false,
            isBordered: false,
            visualState: validationState,
            liveVisualState: yearValidator
        )
        .frame(minHeight: 18)
        .appTextInputChrome(
            fillsWidth: width == nil,
            fill: validationState.fill,
            stroke: validationState.stroke
        )
        .appExplicitInvalidFieldChrome(validationState)
        .help(validationState.helpText ?? "")
        .frame(width: width, alignment: .leading)
    }

    private var validationState: AppFieldVisualState {
        yearValidator(text.wrappedValue)
    }

    private var yearValidator: (String) -> AppFieldVisualState {
        { AppFieldValidators.optionalYear($0, language: language).state }
    }
}

extension View {
    @ViewBuilder
    func appExplicitInvalidFieldChrome(_ state: AppFieldVisualState) -> some View {
        if state.isInvalid {
            self
                .background(
                    RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                        .fill(state.fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                        .stroke(state.stroke, lineWidth: 1.4)
                )
        } else {
            self
        }
    }
}

private struct AppPlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        configure(textView)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        configure(textView)

        if !context.coordinator.isEditing,
           !context.coordinator.isApplyingExternalText,
           textView.string != text {
            let selection = textView.selectedRange()
            context.coordinator.isApplyingExternalText = true
            textView.string = text
            let location = min(selection.location, textView.string.utf16.count)
            let length = min(selection.length, max(0, textView.string.utf16.count - location))
            textView.setSelectedRange(NSRange(location: location, length: length))
            context.coordinator.isApplyingExternalText = false
        }
    }

    private func configure(_ textView: NSTextView) {
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.font = appNSFont(.body)
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: textView.enclosingScrollView?.contentSize.width ?? 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        AppTextEditingSupport.prepareEditor(textView, menu: textView.menu)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AppPlainTextEditor
        var isEditing = false
        var isApplyingExternalText = false

        init(_ parent: AppPlainTextEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText,
                  let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

struct AppCompactCheckboxCell: View {
    let title: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack {
            Toggle(isOn: isOn) {
                EmptyView()
            }
                .appCheckboxStyle()
                .help(title)
                .accessibilityLabel(Text(title))
        }
        .frame(maxWidth: .infinity, minHeight: AppPalette.fieldMinHeight, alignment: .center)
    }
}

struct AppCompactRowTitleText: View {
    let text: String
    var lineLimit: Int? = 1

    var body: some View {
        Text(text)
            .appTypography(.tableHeader)
            .foregroundStyle(AppPalette.appText)
            .lineLimit(lineLimit)
    }
}

struct AppBadgeText: View {
    enum Size {
        case compact
        case normal

        var fontSize: CGFloat {
            switch self {
            case .compact:
                return 11
            case .normal:
                return 12
            }
        }
    }

    let text: String
    var size: Size = .normal
    var foreground: Color = AppPalette.appText

    var body: some View {
        Text(text)
            .font(appFont(.secondary).weight(.semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
}

struct AppToneBadge: View {
    let text: String
    var size: AppBadgeText.Size = .normal
    var foreground: Color = AppPalette.appText
    var background: Color = AppPalette.pillSurface
    var stroke: Color = AppPalette.border
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 4
    var showsIndicator = false
    var indicatorColor: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            if showsIndicator {
                Circle()
                    .fill(indicatorColor ?? foreground.opacity(0.9))
                    .frame(width: 5, height: 5)
            }
            AppBadgeText(text: text, size: size, foreground: foreground)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(Capsule(style: .continuous).fill(background))
        .overlay(Capsule(style: .continuous).stroke(stroke, lineWidth: 1))
    }
}

struct AppTextPill: View {
    let text: String
    var size: AppBadgeText.Size = .normal
    var foreground: Color = AppPalette.pillText
    var background: Color = AppPalette.pillSurface.opacity(0.9)
    var stroke: Color = Color.clear
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 5

    var body: some View {
        AppToneBadge(
            text: text,
            size: size,
            foreground: foreground,
            background: background,
            stroke: stroke,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
    }
}

struct AppCountBadge: View {
    let count: Int
    var maximumVisibleCount = 99
    var foreground: Color = .white
    var background: Color = AppPalette.vividRed
    var stroke: Color = AppPalette.border.opacity(0.35)

    private var label: String {
        count > maximumVisibleCount ? "\(maximumVisibleCount)+" : String(count)
    }

    var body: some View {
        AppToneBadge(
            text: label,
            size: .compact,
            foreground: foreground,
            background: background,
            stroke: stroke,
            horizontalPadding: 6,
            verticalPadding: 2
        )
        .fixedSize()
        .accessibilityLabel(label)
    }
}

struct AppInlineLinkLabel: View {
    let title: String
    var systemImage = "link"
    var fontSize: CGFloat = 12
    var weight: Font.Weight = .semibold
    var fixedSize = true
    var tint: Color = AppPalette.linkAction

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(appFont(fontSize < 12.5 ? .secondary : .body).weight(weight))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize(horizontal: fixedSize, vertical: false)
            .foregroundStyle(tint)
    }
}

struct AppTimelineStepText: View {
    let text: String
    var lineLimit: Int? = 1
    var foreground: Color = AppPalette.appText

    var body: some View {
        Text(text)
            .appTypography(.tableHeader)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.82)
    }
}

struct AppTimelineMarker: View {
    let isCompleted: Bool
    var iconName: String? = "checkmark"
    var completedColor: Color = AppPalette.vividGreen
    var pendingFill: Color = AppPalette.cardSurface
    var pendingStroke: Color = Color.primary.opacity(0.35)
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(isCompleted ? completedColor : pendingFill)
            Circle()
                .stroke(isCompleted ? completedColor : pendingStroke, lineWidth: isCompleted ? 1.8 : 2.5)
            if isCompleted, let iconName {
                Image(systemName: iconName)
                    .font(.system(size: max(12, size * 0.39), weight: .bold))
                    .foregroundStyle(AppPalette.semanticOnColor)
            }
        }
        .frame(width: size, height: size)
    }
}

struct AppTimelineNodeModel<ID: Hashable>: Identifiable {
    let id: ID
    var width: CGFloat
    var anchorDate: Date?
    var hasDefinedDate: Bool
    var isCompleted: Bool
    var isDeemphasized: Bool
    var completedColor: Color
    var completedStrokeColor: Color
    var completedIconColor: Color
    var iconName: String?

    init(
        id: ID,
        width: CGFloat,
        anchorDate: Date? = nil,
        hasDefinedDate: Bool,
        isCompleted: Bool,
        isDeemphasized: Bool = false,
        completedColor: Color = AppPalette.vividGreen,
        completedStrokeColor: Color = AppPalette.vividGreen,
        completedIconColor: Color = AppPalette.semanticOnColor,
        iconName: String? = "checkmark"
    ) {
        self.id = id
        self.width = width
        self.anchorDate = anchorDate
        self.hasDefinedDate = hasDefinedDate
        self.isCompleted = isCompleted
        self.isDeemphasized = isDeemphasized
        self.completedColor = completedColor
        self.completedStrokeColor = completedStrokeColor
        self.completedIconColor = completedIconColor
        self.iconName = iconName
    }
}

struct AppTimelineStrip<ID: Hashable, NodeContent: View>: View {
    let nodes: [AppTimelineNodeModel<ID>]
    var horizontalInset: CGFloat = 62
    var markerSize: CGFloat = 24
    var markerCenterY: CGFloat = 18
    var height: CGFloat = 156
    var nodeSpacing: CGFloat = 9
    var showsTodayMarker: Bool = true
    var today: Date = Calendar.current.startOfDay(for: Date())
    var segmentProgressColor: (Int) -> Color = { _ in AppPalette.vividBlue }
    var segmentProgressFraction: ((Int) -> CGFloat?)? = nil
    var nodeContent: (AppTimelineNodeModel<ID>) -> NodeContent

    private var inactiveGray: Color {
        AppTimelineStrip.inactiveGray
    }

    private var futureGray: Color {
        AppTimelineStrip.futureGray
    }

    var body: some View {
        GeometryReader { geometry in
            let centers = circleCenters(width: geometry.size.width)

            ZStack(alignment: .topLeading) {
                if nodes.count > 1 {
                    ForEach(0..<(nodes.count - 1), id: \.self) { index in
                        segmentView(index: index, centers: centers)
                    }
                }

                if showsTodayMarker, let markerX = todayMarkerX(centers: centers) {
                    Path { path in
                        path.move(to: CGPoint(x: markerX, y: 0))
                        path.addLine(to: CGPoint(x: markerX, y: markerCenterY * 2))
                    }
                    .stroke(AppPalette.vividRed, lineWidth: 3)
                }

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    nodeView(node, centerX: centers[index])
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    static var inactiveGray: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(calibratedWhite: 0.46, alpha: 1)
            default:
                return NSColor(calibratedWhite: 0.76, alpha: 1)
            }
        })
    }

    static var futureGray: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(calibratedWhite: 0.52, alpha: 1)
            default:
                return NSColor(calibratedWhite: 0.66, alpha: 1)
            }
        })
    }

    private func circleCenters(width: CGFloat) -> [CGFloat] {
        guard nodes.count > 1 else {
            let nodeWidth = nodes.first?.width ?? horizontalInset
            return [max(width / 2, nodeWidth / 2)]
        }
        let leadingInset = max(horizontalInset, (nodes.first?.width ?? 0) / 2)
        let trailingInset = max(horizontalInset, (nodes.last?.width ?? 0) / 2)
        let usableWidth = max(width - leadingInset - trailingInset, 1)
        let lastIndex = max(nodes.count - 1, 1)
        return nodes.indices.map { index in
            leadingInset + (usableWidth * CGFloat(index) / CGFloat(lastIndex))
        }
    }

    @ViewBuilder
    private func segmentView(index: Int, centers: [CGFloat]) -> some View {
        let startX = centers[index]
        let endX = centers[index + 1]
        let base = segmentBaseStyle(index: index)

        if base.dashed {
            Path { path in
                path.move(to: CGPoint(x: startX, y: markerCenterY))
                path.addLine(to: CGPoint(x: endX, y: markerCenterY))
            }
            .stroke(
                base.leadingColor,
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 5])
            )
        } else {
            timelineGradientLine(
                startX: startX,
                endX: endX,
                lineWidth: 2.5,
                colors: [base.leadingColor, base.trailingColor]
            )
        }

        if let fraction = segmentProgressFraction?(index), fraction > 0 {
            timelineGradientLine(
                startX: startX,
                endX: endX,
                lineWidth: 3,
                colors: [base.leadingColor, base.trailingColor],
                visibleFraction: fraction
            )
        }
    }

    private func timelineGradientLine(
        startX: CGFloat,
        endX: CGFloat,
        lineWidth: CGFloat,
        colors: [Color],
        visibleFraction: CGFloat = 1
    ) -> some View {
        let width = max(endX - startX, 1)
        let clampedFraction = max(0, min(1, visibleFraction))
        return Capsule(style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: lineWidth)
            .mask(alignment: .leading) {
                Rectangle()
                    .frame(width: width * clampedFraction, height: lineWidth)
            }
            .position(x: startX + (width / 2), y: markerCenterY)
    }

    private func segmentBaseStyle(index: Int) -> (leadingColor: Color, trailingColor: Color, dashed: Bool) {
        let left = nodes[index]
        let right = nodes[index + 1]
        if left.isDeemphasized || right.isDeemphasized {
            return (segmentEndpointColor(left), segmentEndpointColor(right), false)
        }
        if left.isCompleted && right.isCompleted {
            return (segmentEndpointColor(left), segmentEndpointColor(right), false)
        }
        if left.hasDefinedDate || right.hasDefinedDate {
            return (segmentEndpointColor(left), segmentEndpointColor(right), false)
        }
        return (segmentEndpointColor(left), segmentEndpointColor(right), true)
    }

    private func segmentEndpointColor(_ node: AppTimelineNodeModel<ID>) -> Color {
        if node.isCompleted && !node.isDeemphasized {
            return node.completedStrokeColor
        }
        if node.hasDefinedDate && !node.isDeemphasized {
            return futureGray
        }
        return inactiveGray
    }

    private func nodeView(_ node: AppTimelineNodeModel<ID>, centerX: CGFloat) -> some View {
        VStack(spacing: nodeSpacing) {
            markerView(for: node)
            nodeContent(node)
        }
        .padding(.top, markerCenterY - (markerSize / 2))
        .frame(width: node.width, height: height, alignment: .top)
        .position(x: centerX, y: height / 2)
    }

    private func markerView(for node: AppTimelineNodeModel<ID>) -> some View {
        let active = node.isCompleted && !node.isDeemphasized
        let filledPending = node.hasDefinedDate && !node.isDeemphasized
        let pendingStroke = filledPending ? futureGray : inactiveGray
        return ZStack {
            Circle()
                .fill(active ? node.completedColor : AppPalette.fieldSurface)
            Circle()
                .stroke(active ? node.completedStrokeColor : pendingStroke, lineWidth: active ? 2.2 : 1.8)
            if active, let iconName = node.iconName {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(node.completedIconColor)
            }
        }
        .frame(width: markerSize, height: markerSize)
    }

    private func todayMarkerX(centers: [CGFloat]) -> CGFloat? {
        let datedNodes = nodes.enumerated().compactMap { index, node -> (date: Date, x: CGFloat)? in
            guard let date = node.anchorDate else { return nil }
            guard centers.indices.contains(index) else { return nil }
            return (Calendar.current.startOfDay(for: date), centers[index])
        }
        .sorted { $0.date < $1.date }

        guard datedNodes.count >= 2 else { return nil }
        guard let nextIndex = datedNodes.firstIndex(where: { today <= $0.date }) else { return nil }
        if nextIndex == 0 {
            return Calendar.current.isDate(datedNodes[0].date, inSameDayAs: today) ? datedNodes[0].x : nil
        }

        let previous = datedNodes[nextIndex - 1]
        let next = datedNodes[nextIndex]
        if Calendar.current.isDate(previous.date, inSameDayAs: today) { return previous.x }
        if Calendar.current.isDate(next.date, inSameDayAs: today) { return next.x }

        let interval = next.date.timeIntervalSince(previous.date)
        guard interval > 0 else { return (previous.x + next.x) / 2 }
        let fraction = max(0, min(1, today.timeIntervalSince(previous.date) / interval))
        return previous.x + ((next.x - previous.x) * CGFloat(fraction))
    }
}

struct AppStatValueText: View {
    let text: String
    var size: CGFloat? = nil

    var body: some View {
        Text(text)
            .font(size.map { .system(size: $0, weight: .bold) } ?? appFont(.statValue))
            .foregroundStyle(AppPalette.appText)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }
}



struct AppSelectableOptionSurfaceModifier: ViewModifier {
    let isSelected: Bool
    var fill: Color = AppPalette.cardSurface
    var selectedFill: Color = AppPalette.activeTabSurface.opacity(0.16)
    var stroke: Color = AppPalette.subtleBorder
    var selectedStroke: Color = AppPalette.activeTabSurface.opacity(0.68)
    var cornerRadius: CGFloat = AppPalette.mediumCornerRadius
    var padding: CGFloat = AppPalette.sectionPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? selectedFill : fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isSelected ? selectedStroke : stroke, lineWidth: 1)
            )
    }
}

extension View {
    func appSelectableOptionSurface(
        isSelected: Bool,
        fill: Color = AppPalette.cardSurface,
        selectedFill: Color = AppPalette.activeTabSurface.opacity(0.16),
        stroke: Color = AppPalette.subtleBorder,
        selectedStroke: Color = AppPalette.activeTabSurface.opacity(0.68),
        cornerRadius: CGFloat = AppPalette.mediumCornerRadius,
        padding: CGFloat = AppPalette.sectionPadding
    ) -> some View {
        modifier(
            AppSelectableOptionSurfaceModifier(
                isSelected: isSelected,
                fill: fill,
                selectedFill: selectedFill,
                stroke: stroke,
                selectedStroke: selectedStroke,
                cornerRadius: cornerRadius,
                padding: padding
            )
        )
    }
}

struct AppSettingsCard<Content: View>: View {
    var padding: CGFloat = AppPalette.sectionPadding
    var fill: Color = AppPalette.cardSurface
    var stroke: Color = AppPalette.subtleBorder
    let content: Content

    init(
        padding: CGFloat = AppPalette.sectionPadding,
        fill: Color = AppPalette.cardSurface,
        stroke: Color = AppPalette.subtleBorder,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.fill = fill
        self.stroke = stroke
        self.content = content()
    }

    var body: some View {
        content.appCardChrome(padding: padding, fill: fill, stroke: stroke)
    }
}

struct AppFieldSurfaceCard<Content: View>: View {
    var padding: CGFloat = AppPalette.compactSpacing
    let content: Content

    init(padding: CGFloat = AppPalette.compactSpacing, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content.appInnerPanelChrome(padding: padding, fill: AppPalette.fieldSurface, stroke: AppPalette.subtleBorder)
    }
}

struct AppEditorLockButton: View {
    let isLocked: Bool
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isLocked ? AppPalette.actionDelete : AppPalette.linkAction)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            isLocked
                ? language.text("Unlock editing", "Lås upp redigering")
                : language.text("Lock editing", "Lås redigering")
        )
        .accessibilityLabel(
            isLocked
                ? language.text("Unlock editing", "Lås upp redigering")
                : language.text("Lock editing", "Lås redigering")
        )
    }
}

extension View {
    func appCardChrome(
        padding: CGFloat = AppPalette.sectionPadding,
        fill: Color = AppPalette.cardSurface,
        stroke: Color = AppPalette.border,
        cornerRadius: CGFloat = AppPalette.mediumCornerRadius
    ) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }

    func appCardChrome(
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        fill: Color = AppPalette.cardSurface,
        stroke: Color = AppPalette.border,
        cornerRadius: CGFloat = AppPalette.mediumCornerRadius
    ) -> some View {
        self
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }

    func appInnerPanelChrome(
        padding: CGFloat = 10,
        fill: Color = AppPalette.secondaryCardSurface,
        stroke: Color = AppPalette.subtleBorder
    ) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}
