import AppKit
import SwiftUI

enum AutocompleteSelectionMetrics {
    static var fieldMinHeight: CGFloat {
        max(24, AppPalette.fieldMinHeight - 2)
    }

    static let rowSpacing: CGFloat = 6
}

struct AutocompleteSelectionField: View {
    @Binding var text: String
    let options: [String]
    let excludedOptions: Set<String>
    let placeholder: String
    let addNewTitle: String?
    let display: (String) -> String
    let onCommit: () -> Void
    let onSelect: ((String) -> Void)?
    let onAddNew: (() -> Void)?
    let usesTransparentFieldStyle: Bool
    let updatesTextContinuously: Bool
    let showsSuggestionsWithoutQuery: Bool
    let appliesChrome: Bool
    let textFont: NSFont?
    let chromeHorizontalPadding: CGFloat
    let chromeVerticalPadding: CGFloat
    let chromeMinHeight: CGFloat
    let chromeFill: Color?
    let chromeStroke: Color?
    /// Keeps the options in the given order (a course followed by its
    /// assignments) instead of sorting them alphabetically.
    let preservesOptionOrder: Bool

    @State private var isFocused = false
    @State private var draftText: String
    @State private var highlightedIndex = 0
    @State private var showSuggestions = false
    @State private var filteredOptionsCache: [String]
    @State private var suppressNextBlurCommit = false
    @State private var overlayID = UUID()
    @State private var blurDismissTask: DispatchWorkItem?

    init(
        text: Binding<String>,
        options: [String],
        excludedOptions: Set<String> = [],
        placeholder: String,
        addNewTitle: String? = nil,
        display: @escaping (String) -> String = { $0 },
        onCommit: @escaping () -> Void,
        onSelect: ((String) -> Void)? = nil,
        onAddNew: (() -> Void)? = nil,
        usesTransparentFieldStyle: Bool = false,
        updatesTextContinuously: Bool = false,
        showsSuggestionsWithoutQuery: Bool = false,
        appliesChrome: Bool = true,
        textFont: NSFont? = nil,
        chromeHorizontalPadding: CGFloat? = nil,
        chromeVerticalPadding: CGFloat? = nil,
        chromeMinHeight: CGFloat = AutocompleteSelectionMetrics.fieldMinHeight,
        chromeFill: Color? = nil,
        chromeStroke: Color? = nil,
        preservesOptionOrder: Bool = false
    ) {
        _text = text
        _draftText = State(initialValue: text.wrappedValue)
        _filteredOptionsCache = State(initialValue: [])
        self.options = options
        self.excludedOptions = excludedOptions
        self.placeholder = placeholder
        self.addNewTitle = addNewTitle
        self.display = display
        self.onCommit = onCommit
        self.onSelect = onSelect
        self.onAddNew = onAddNew
        self.usesTransparentFieldStyle = usesTransparentFieldStyle
        self.updatesTextContinuously = updatesTextContinuously
        self.showsSuggestionsWithoutQuery = showsSuggestionsWithoutQuery
        self.appliesChrome = appliesChrome
        self.textFont = textFont
        self.chromeHorizontalPadding = chromeHorizontalPadding ?? AppPalette.textFieldHorizontalPadding
        self.chromeVerticalPadding = chromeVerticalPadding ?? AppPalette.textFieldVerticalPadding
        self.chromeMinHeight = chromeMinHeight
        self.chromeFill = chromeFill
        self.chromeStroke = chromeStroke
        self.preservesOptionOrder = preservesOptionOrder
    }

    private func filteredOptions(for queryText: String) -> [String] {
        filteredAutocompleteOptions(
            options: options,
            excludedOptions: excludedOptions,
            queryText: queryText,
            showsSuggestionsWithoutQuery: showsSuggestionsWithoutQuery,
            display: display,
            preservesOrder: preservesOptionOrder
        )
    }

    private func makeFilteredOptions() -> [String] {
        filteredOptions(for: draftText)
    }

    private var shouldShowSuggestions: Bool {
        let hasQuery = !normalizedAutocompleteTokens(from: draftText).isEmpty
        guard isFocused, hasQuery || showsSuggestionsWithoutQuery else { return false }
        return !filteredOptionsCache.isEmpty || (addNewTitle != nil && onAddNew != nil)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            let textField = AutocompleteTextField(
                text: $draftText,
                placeholder: placeholder,
                // Every editable value keeps its own field surface.  Row and panel
                // containers may be transparent, but the input itself must not be.
                usesTransparentFieldStyle: false,
                textFont: textFont,
                onFocusChange: { focused in
                    blurDismissTask?.cancel()
                    isFocused = focused
                    if focused {
                        showSuggestions = shouldShowSuggestions
                    } else {
                        let task = DispatchWorkItem {
                            highlightedIndex = 0
                            if suppressNextBlurCommit {
                                suppressNextBlurCommit = false
                            } else {
                                commitCurrentInput()
                            }
                            showSuggestions = false
                            blurDismissTask = nil
                        }
                        blurDismissTask = task
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: task)
                    }
                },
                onMoveUp: {
                    guard showSuggestions, !filteredOptionsCache.isEmpty else { return false }
                    highlightedIndex = max(highlightedIndex - 1, 0)
                    return true
                },
                onMoveDown: {
                    guard showSuggestions, !filteredOptionsCache.isEmpty else { return false }
                    highlightedIndex = min(highlightedIndex + 1, filteredOptionsCache.count - 1)
                    return true
                },
                onReturn: { currentInput in
                    if let acceptedText = acceptHighlightedSuggestion(currentInput: currentInput) {
                        return .handled(replacementText: acceptedText, movesFocus: false)
                    }
                    return .handled(replacementText: commitCurrentInput(currentInput: currentInput), movesFocus: false)
                },
                onTab: { currentInput in
                    if let acceptedText = acceptHighlightedSuggestion(currentInput: currentInput) {
                        return .handled(replacementText: acceptedText, movesFocus: true)
                    }
                    // Commit synchronously before focus moves; the previous
                    // .unhandled path left the commit to the 0.08 s blur
                    // task, firing the store autosave while the user was
                    // already typing in the next field.
                    return .handled(
                        replacementText: commitCurrentInput(currentInput: currentInput),
                        movesFocus: true
                    )
                },
                onBacktab: { currentInput in
                    showSuggestions = false
                    return .handled(
                        replacementText: commitCurrentInput(currentInput: currentInput),
                        movesFocus: true
                    )
                },
                onCancel: {
                    cancelCurrentInput()
                }
            )
            .onAppear {
                    recomputeFilteredOptions()
                }
            .onChange(of: draftText) { _, _ in
                    if updatesTextContinuously, text != draftText {
                        text = draftText
                    }
                    recomputeFilteredOptions()
                    highlightedIndex = 0
                    showSuggestions = shouldShowSuggestions
                }
            .onChange(of: options) { _, _ in
                    recomputeFilteredOptions()
                    showSuggestions = shouldShowSuggestions
                }
            .onChange(of: excludedOptions) { _, _ in
                    recomputeFilteredOptions()
                    showSuggestions = shouldShowSuggestions
                }
            .onChange(of: text) { _, newValue in
                    if !isFocused && newValue != draftText {
                        draftText = newValue
                        recomputeFilteredOptions()
                    }
                }
            if appliesChrome {
                textField
                    .appMenuChrome(
                        horizontalPadding: chromeHorizontalPadding,
                        verticalPadding: chromeVerticalPadding,
                        minHeight: chromeMinHeight,
                        fillsWidth: true,
                        fill: chromeFill ?? AppPalette.fieldSurface,
                        stroke: chromeStroke ?? AppPalette.subtleBorder
                    )
                    .zIndex(1)
            } else {
                textField
                    .zIndex(1)
            }
        }
        .appKeyboardFocusPulse(isFocused: isFocused)
        .zIndex(showSuggestions ? 100 : 0)
        .anchorPreference(key: AutocompleteOverlayPreferenceKey.self, value: .bounds) { bounds in
            guard showSuggestions else { return [] }
            return [
                AutocompleteOverlayEntry(
                    id: overlayID,
                    bounds: bounds,
                    content: AnyView(suggestionsOverlay)
                )
            ]
        }
    }

    private func acceptHighlightedSuggestion(currentInput: String) -> String? {
        guard showSuggestions,
              !normalizedAutocompleteTokens(from: currentInput).isEmpty else {
            return nil
        }
        let freshOptions = filteredOptions(for: currentInput)
        guard !freshOptions.isEmpty else { return nil }
        filteredOptionsCache = freshOptions
        let acceptedIndex = freshOptions.indices.contains(highlightedIndex) ? highlightedIndex : 0
        return choose(freshOptions[acceptedIndex])
    }

    @discardableResult
    private func choose(_ option: String) -> String {
        blurDismissTask?.cancel()
        suppressNextBlurCommit = true
        draftText = option
        text = option
        if let onSelect {
            onSelect(option)
        } else {
            onCommit()
        }
        draftText = text
        highlightedIndex = 0
        showSuggestions = false
        recomputeFilteredOptions()
        return text
    }

    @discardableResult
    private func commitCurrentInput(currentInput: String? = nil) -> String {
        if let currentInput, draftText != currentInput {
            draftText = currentInput
        }
        let didChange = text != draftText
        if didChange {
            text = draftText
            onCommit()
        }
        draftText = text
        recomputeFilteredOptions()
        return text
    }

    private func cancelCurrentInput() {
        draftText = text
        highlightedIndex = 0
        showSuggestions = false
        recomputeFilteredOptions()
    }

    private func recomputeFilteredOptions() {
        filteredOptionsCache = makeFilteredOptions()
    }

    private var suggestionsOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredOptionsCache.enumerated()), id: \.offset) { index, option in
                Button {
                    choose(option)
                } label: {
                    HStack {
                        Text(display(option))
                            .appTypography(.body)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, AppPalette.fieldHorizontalPadding)
                    .padding(.vertical, max(4, AppPalette.fieldVerticalPadding - 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(index == highlightedIndex ? AppPalette.activeTabSurface.opacity(0.18) : Color.clear)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        highlightedIndex = index
                    }
                }
            }

            if let addNewTitle, let onAddNew {
                Divider()
                    .padding(.vertical, 2)

                Button {
                    blurDismissTask?.cancel()
                    suppressNextBlurCommit = true
                    if text != draftText {
                        text = draftText
                    }
                    onAddNew()
                    showSuggestions = false
                } label: {
                    HStack(spacing: 6) {
                        Text(addNewTitle)
                            .appTypography(.body)
                        Spacer()
                    }
                    .padding(.horizontal, AppPalette.fieldHorizontalPadding)
                    .padding(.vertical, max(4, AppPalette.fieldVerticalPadding - 1))
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                .fill(AppPalette.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                        .stroke(AppPalette.border, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
        // A press held longer than the 0.08 s blur grace period used to let
        // the pending blur task commit the partial draft and tear down the
        // overlay before the row's action fired on mouse-up. Cancel the task
        // on mouse-down; if the press misses every row, finish the deferred
        // blur work after the row actions have had their turn.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    blurDismissTask?.cancel()
                    blurDismissTask = nil
                }
                .onEnded { _ in
                    DispatchQueue.main.async {
                        if showSuggestions, !isFocused {
                            commitCurrentInput()
                            highlightedIndex = 0
                            showSuggestions = false
                        }
                    }
                }
        )
    }
}

private struct AutocompleteOverlayEntry: Identifiable, @unchecked Sendable {
    let id: UUID
    let bounds: Anchor<CGRect>
    let content: AnyView
}

private struct AutocompleteOverlayPreferenceKey: PreferenceKey {
    static let defaultValue: [AutocompleteOverlayEntry] = []

    static func reduce(value: inout [AutocompleteOverlayEntry], nextValue: () -> [AutocompleteOverlayEntry]) {
        value.append(contentsOf: nextValue())
    }
}

private struct AutocompleteOverlayHostModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlayPreferenceValue(AutocompleteOverlayPreferenceKey.self) { entries in
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(entries) { entry in
                        let rect = proxy[entry.bounds]
                        entry.content
                            .frame(width: max(rect.width, 180), alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .offset(x: rect.minX, y: rect.maxY + 4)
                            .zIndex(1000)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

extension View {
    func autocompleteOverlayHost() -> some View {
        modifier(AutocompleteOverlayHostModifier())
    }
}

func filteredAutocompleteOptions(
    options: [String],
    excludedOptions: Set<String> = [],
    queryText: String,
    showsSuggestionsWithoutQuery: Bool,
    display: (String) -> String = { $0 },
    preservesOrder: Bool = false
) -> [String] {
    let filteredOptions = options.filter { !excludedOptions.contains($0) }
    let queryTokens = normalizedAutocompleteTokens(from: queryText)

    if preservesOrder {
        // A hierarchical list (a course followed by its assignments): the
        // given order is the meaning, so matches keep it.
        if queryTokens.isEmpty {
            guard showsSuggestionsWithoutQuery else { return [] }
            return Array(filteredOptions.prefix(12))
        }
        return Array(
            filteredOptions
                .filter { scoreAutocompleteMatch(option: display($0), queryTokens: queryTokens) != nil }
                .prefix(12)
        )
    }

    if queryTokens.isEmpty {
        guard showsSuggestionsWithoutQuery else { return [] }
        return filteredOptions
            .sorted { display($0).localizedStandardCompare(display($1)) == .orderedAscending }
            .prefix(12)
            .map { $0 }
    }

    return filteredOptions
        .map { option in
            (option, scoreAutocompleteMatch(option: display(option), queryTokens: queryTokens))
        }
        .filter { $0.1 != nil }
        .sorted { lhs, rhs in
            let left = lhs.1 ?? (Int.max, Int.max, lhs.0)
            let right = rhs.1 ?? (Int.max, Int.max, rhs.0)
            if left.0 != right.0 { return left.0 < right.0 }
            if left.1 != right.1 { return left.1 < right.1 }
            return display(lhs.0).localizedStandardCompare(display(rhs.0)) == .orderedAscending
        }
        .map(\.0)
        .prefix(12)
        .map { $0 }
}

private enum AutocompleteKeyActionResult {
    case handled(replacementText: String?, movesFocus: Bool)
    case unhandled
}

private struct AutocompleteTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let usesTransparentFieldStyle: Bool
    let textFont: NSFont?
    let onFocusChange: (Bool) -> Void
    let onMoveUp: () -> Bool
    let onMoveDown: () -> Bool
    let onReturn: (String) -> AutocompleteKeyActionResult
    let onTab: (String) -> AutocompleteKeyActionResult
    let onBacktab: (String) -> AutocompleteKeyActionResult
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onFocusChange: onFocusChange,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onReturn: onReturn,
            onTab: onTab,
            onBacktab: onBacktab,
            onCancel: onCancel
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = AutocompleteNSTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        let usesOuterRenewedChrome = AppRuntime.usesRenewedChrome
        field.isBordered = !usesTransparentFieldStyle && !usesOuterRenewedChrome
        field.isBezeled = !usesTransparentFieldStyle && !usesOuterRenewedChrome
        field.bezelStyle = .roundedBezel
        field.font = textFont ?? appNSFont(.body)
        field.focusRingType = (usesTransparentFieldStyle || usesOuterRenewedChrome) ? .none : .default
        field.drawsBackground = !usesTransparentFieldStyle && !usesOuterRenewedChrome
        field.backgroundColor = (usesTransparentFieldStyle || usesOuterRenewedChrome) ? .clear : NSColor.textBackgroundColor
        field.lineBreakMode = .byTruncatingTail
        AppTextEditingSupport.configureTextField(field)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        let isEditing = nsView.currentEditor() != nil
        if !isEditing && nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.update(
            text: $text,
            onFocusChange: onFocusChange,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onReturn: onReturn,
            onTab: onTab,
            onBacktab: onBacktab,
            onCancel: onCancel
        )
        nsView.placeholderString = placeholder
        let usesOuterRenewedChrome = AppRuntime.usesRenewedChrome
        nsView.isBordered = !usesTransparentFieldStyle && !usesOuterRenewedChrome
        nsView.isBezeled = !usesTransparentFieldStyle && !usesOuterRenewedChrome
        nsView.font = textFont ?? appNSFont(.body)
        nsView.focusRingType = (usesTransparentFieldStyle || usesOuterRenewedChrome) ? .none : .default
        nsView.drawsBackground = !usesTransparentFieldStyle && !usesOuterRenewedChrome
        nsView.backgroundColor = (usesTransparentFieldStyle || usesOuterRenewedChrome) ? .clear : NSColor.textBackgroundColor
        AppTextEditingSupport.configureTextField(nsView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate, NSControlTextEditingDelegate {
        @Binding private var text: String
        private var onFocusChange: (Bool) -> Void
        private var onMoveUp: () -> Bool
        private var onMoveDown: () -> Bool
        private var onReturn: (String) -> AutocompleteKeyActionResult
        private var onTab: (String) -> AutocompleteKeyActionResult
        private var onBacktab: (String) -> AutocompleteKeyActionResult
        private var onCancel: () -> Void

        init(
            text: Binding<String>,
            onFocusChange: @escaping (Bool) -> Void,
            onMoveUp: @escaping () -> Bool,
            onMoveDown: @escaping () -> Bool,
            onReturn: @escaping (String) -> AutocompleteKeyActionResult,
            onTab: @escaping (String) -> AutocompleteKeyActionResult,
            onBacktab: @escaping (String) -> AutocompleteKeyActionResult,
            onCancel: @escaping () -> Void
        ) {
            _text = text
            self.onFocusChange = onFocusChange
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onReturn = onReturn
            self.onTab = onTab
            self.onBacktab = onBacktab
            self.onCancel = onCancel
        }

        func update(
            text: Binding<String>,
            onFocusChange: @escaping (Bool) -> Void,
            onMoveUp: @escaping () -> Bool,
            onMoveDown: @escaping () -> Bool,
            onReturn: @escaping (String) -> AutocompleteKeyActionResult,
            onTab: @escaping (String) -> AutocompleteKeyActionResult,
            onBacktab: @escaping (String) -> AutocompleteKeyActionResult,
            onCancel: @escaping () -> Void
        ) {
            _text = text
            self.onFocusChange = onFocusChange
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onReturn = onReturn
            self.onTab = onTab
            self.onBacktab = onBacktab
            self.onCancel = onCancel
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                AppFocusPulse.setFocused(true, on: field)
                if let editor = field.currentEditor() {
                    AppTextEditingSupport.prepareEditor(editor)
                }
            }
            onFocusChange(true)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                AppFocusPulse.setFocused(false, on: field)
            }
            onFocusChange(false)
        }

        private func applyReplacement(_ replacementText: String?, to control: NSControl, textView: NSTextView) {
            guard let replacementText else { return }
            text = replacementText
            if let field = control as? NSTextField {
                field.stringValue = replacementText
            }
            textView.string = replacementText
            textView.setSelectedRange(NSRange(location: replacementText.utf16.count, length: 0))
        }

        private func handle(
            _ result: AutocompleteKeyActionResult,
            control: NSControl,
            textView: NSTextView,
            focusDirection: AppFormFocusDirection? = nil
        ) -> Bool {
            switch result {
            case let .handled(replacementText, movesFocus):
                applyReplacement(replacementText, to: control, textView: textView)
                if movesFocus, let focusDirection {
                    AppFormKeyboardRouting.moveFocus(from: control, direction: focusDirection)
                }
                return true
            case .unhandled:
                if let focusDirection {
                    AppFormKeyboardRouting.moveFocus(from: control, direction: focusDirection)
                    return true
                }
                return false
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                return onMoveUp()
            case #selector(NSResponder.moveDown(_:)):
                return onMoveDown()
            case #selector(NSResponder.insertNewline(_:)):
                return handle(onReturn(textView.string), control: control, textView: textView)
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                return handle(onReturn(textView.string), control: control, textView: textView)
            case #selector(NSResponder.insertLineBreak(_:)):
                return handle(onReturn(textView.string), control: control, textView: textView)
            case #selector(NSResponder.insertTab(_:)):
                guard AppFormKeyboardRouting.focusDirection(for: commandSelector) == .forward else { return false }
                return handle(onTab(textView.string), control: control, textView: textView, focusDirection: .forward)
            case #selector(NSResponder.insertBacktab(_:)):
                guard AppFormKeyboardRouting.focusDirection(for: commandSelector) == .backward else { return false }
                return handle(onBacktab(textView.string), control: control, textView: textView, focusDirection: .backward)
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
                return true
            default:
                AppTextEditingSupport.prepareEditor(textView)
                return false
            }
        }
    }
}

private final class AutocompleteNSTextField: NSTextField {
    override func layout() {
        super.layout()
        AppFocusPulse.updateLayout(on: self)
    }
}

func normalizedAutocompleteTokens(from text: String) -> [String] {
    text
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .split { !$0.isLetter && !$0.isNumber }
        .map(String.init)
        .filter { !$0.isEmpty }
}

func scoreAutocompleteMatch(option: String, queryTokens: [String]) -> (Int, Int, String)? {
    let normalizedOption = option
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
    let optionTokens = normalizedAutocompleteTokens(from: option)

    guard queryTokens.allSatisfy({ query in
        normalizedOption.contains(query) || optionTokens.contains(where: { $0.contains(query) })
    }) else {
        return nil
    }

    let prefixMatches = queryTokens.reduce(0) { partial, query in
        partial + (optionTokens.contains(where: { $0.hasPrefix(query) }) ? 1 : 0)
    }
    let positionScore = queryTokens.reduce(0) { partial, query in
        partial + (normalizedOption.range(of: query)?.lowerBound.utf16Offset(in: normalizedOption) ?? 10_000)
    }

    return (-prefixMatches, positionScore, normalizedOption)
}
