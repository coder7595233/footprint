import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppMenuSelectionField<Value: Hashable>: View {
    let selection: Binding<Value>
    let options: [(label: String, value: Value)]
    let placeholder: String?
    let clearValue: Value?
    let fill: Color
    let stroke: Color
    let foregroundColor: Color?
    let minHeight: CGFloat
    let verticalPadding: CGFloat
    let horizontalPadding: CGFloat
    @State private var isFocused = false

    init(
        selection: Binding<Value>,
        options: [(label: String, value: Value)],
        placeholder: String? = nil,
        clearValue: Value? = nil,
        fill: Color = AppPalette.fieldSurface,
        stroke: Color = AppPalette.subtleBorder,
        foregroundColor: Color? = nil,
        minHeight: CGFloat = AppPalette.fieldMinHeight,
        verticalPadding: CGFloat = AppPalette.textFieldVerticalPadding,
        horizontalPadding: CGFloat = AppPalette.textFieldHorizontalPadding
    ) {
        self.selection = selection
        self.options = options
        self.placeholder = placeholder
        self.clearValue = clearValue
        self.fill = fill
        self.stroke = stroke
        self.foregroundColor = foregroundColor
        self.minHeight = minHeight
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
    }

    private var showsPlaceholder: Bool {
        options.first(where: { $0.value == selection.wrappedValue }) == nil && placeholder != nil
    }

    private var pickerOptions: [(label: String, value: Value)] {
        if showsPlaceholder {
            return [(placeholder ?? "", selection.wrappedValue)] + options
        }
        return options
    }

    private var selectedIndex: Int {
        if showsPlaceholder {
            guard let optionIndex = options.firstIndex(where: { $0.value == selection.wrappedValue }) else {
                return 0
            }
            return optionIndex + 1
        }
        return options.firstIndex(where: { $0.value == selection.wrappedValue }) ?? 0
    }

    var body: some View {
        let resolvedTextColor = foregroundColor.flatMap { NSColor($0) } ?? .labelColor
        let displayLabel = pickerOptions[safe: selectedIndex]?.label ?? placeholder ?? ""
        ZStack(alignment: .leading) {
            HStack(spacing: 8) {
                Text(displayLabel)
                    // Match the app body typography — the SwiftUI default
                    // (13 pt) diverges as soon as the user sets another size.
                    .font(appFont(.body))
                    .lineLimit(1)
                    .foregroundStyle(Color(nsColor: showsPlaceholder ? .secondaryLabelColor : resolvedTextColor))
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: showsPlaceholder ? .secondaryLabelColor : resolvedTextColor).opacity(0.85))
            }
            .allowsHitTesting(false)
        }
        .appMenuChrome(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            minHeight: minHeight,
            fill: fill,
            stroke: stroke
        )
        .overlay {
            AppPopupSelectionField(
                labels: pickerOptions.map(\.label),
                selectedIndex: selectedIndex,
                showsPlaceholder: showsPlaceholder,
                textColor: resolvedTextColor,
                onSelect: { index in
                    guard pickerOptions.indices.contains(index) else { return }
                    selection.wrappedValue = pickerOptions[index].value
                },
                onClear: clearValue.map { clearValue in
                    {
                        selection.wrappedValue = clearValue
                    }
                },
                onFocusChange: { isFocused = $0 }
            )
            // The popup is made nearly invisible on the AppKit side instead of
            // with SwiftUI's .opacity(), which stops the click from reaching it.
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .appKeyboardFocusPulse(isFocused: isFocused)
    }
}

private struct AppPopupSelectionField: NSViewRepresentable {
    let labels: [String]
    let selectedIndex: Int
    let showsPlaceholder: Bool
    let textColor: NSColor
    let onSelect: (Int) -> Void
    let onClear: (() -> Void)?
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onClear: onClear, onFocusChange: onFocusChange)
    }

    func makeNSView(context: Context) -> PopupContainerView {
        let popup = FocusablePopUpButton(frame: .zero, pullsDown: false)
        popup.autoenablesItems = false
        popup.isBordered = false
        popup.bezelStyle = .regularSquare
        popup.focusRingType = .none
        popup.font = .systemFont(ofSize: 13)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionDidChange(_:))
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        popup.appearance = NSAppearance.currentDrawing()
        // Nearly transparent, but still clickable: AppKit hit-testing ignores
        // alphaValue, while SwiftUI's .opacity() swallowed the mouse click.
        popup.alphaValue = 0.02
        if let cell = popup.cell as? NSPopUpButtonCell {
            cell.isBordered = false
        }
        return PopupContainerView(popup: popup)
    }

    func updateNSView(_ container: PopupContainerView, context: Context) {
        let popup = container.popup
        context.coordinator.onSelect = onSelect
        context.coordinator.onClear = onClear
        context.coordinator.onFocusChange = onFocusChange
        popup.onClearKey = onClear
        popup.onFocusChange = onFocusChange

        let labelsChanged = context.coordinator.cachedLabels != labels
        if labelsChanged {
            popup.removeAllItems()
            popup.addItems(withTitles: labels)
            context.coordinator.cachedLabels = labels
        }

        let textColorChanged = context.coordinator.cachedTextColor?.isEqual(textColor) != true
        if labelsChanged || context.coordinator.cachedShowsPlaceholder != showsPlaceholder || textColorChanged {
            for (index, item) in popup.itemArray.enumerated() {
                item.isEnabled = !(showsPlaceholder && index == 0)
                item.attributedTitle = NSAttributedString(
                    string: item.title,
                    attributes: [
                        .foregroundColor: showsPlaceholder && index == 0 ? NSColor.secondaryLabelColor : textColor,
                        .font: NSFont.systemFont(ofSize: 13)
                    ]
                )
            }
            context.coordinator.cachedShowsPlaceholder = showsPlaceholder
            context.coordinator.cachedTextColor = textColor
        }

        let clampedIndex = min(max(0, selectedIndex), max(0, labels.count - 1))
        if popup.indexOfSelectedItem != clampedIndex {
            popup.selectItem(at: clampedIndex)
        }
        let selectedLabel = labels.indices.contains(clampedIndex) ? labels[clampedIndex] : ""
        let selectedTitle = NSAttributedString(
            string: selectedLabel,
            attributes: [
                .foregroundColor: showsPlaceholder && clampedIndex == 0 ? NSColor.secondaryLabelColor : textColor,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
            ]
        )
        popup.attributedTitle = selectedTitle
        popup.contentTintColor = nil
        popup.toolTip = labels.indices.contains(clampedIndex) ? labels[clampedIndex] : nil
    }

    final class FocusablePopUpButton: NSPopUpButton {
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }
        var onClearKey: (() -> Void)?
        var onFocusChange: ((Bool) -> Void)?

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted {
                onFocusChange?(true)
                AppFocusPulse.setFocused(true, on: self)
            }
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted {
                onFocusChange?(false)
                AppFocusPulse.setFocused(false, on: self)
            }
            return accepted
        }

        override func layout() {
            super.layout()
            AppFocusPulse.updateLayout(on: self)
        }

        override func insertTab(_ sender: Any?) {
            AppFormKeyboardRouting.moveFocus(from: self, direction: .forward)
        }

        override func insertBacktab(_ sender: Any?) {
            AppFormKeyboardRouting.moveFocus(from: self, direction: .backward)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 48 {
                let direction: AppFormFocusDirection = event.modifierFlags.contains(.shift) ? .backward : .forward
                AppFormKeyboardRouting.moveFocus(from: self, direction: direction)
                return
            }
            if onClearKey != nil, event.keyCode == 51 || event.keyCode == 117 {
                onClearKey?()
                return
            }
            super.keyDown(with: event)
        }
    }

    final class PopupContainerView: NSView {
        let popup: FocusablePopUpButton

        init(popup: FocusablePopUpButton) {
            self.popup = popup
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            popup.translatesAutoresizingMaskIntoConstraints = false
            addSubview(popup)
            NSLayoutConstraint.activate([
                popup.leadingAnchor.constraint(equalTo: leadingAnchor),
                popup.trailingAnchor.constraint(equalTo: trailingAnchor),
                popup.topAnchor.constraint(equalTo: topAnchor),
                popup.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { false }
        override var canBecomeKeyView: Bool { false }

        /// Every click inside the field belongs to the popup, wherever it lands.
        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            return bounds.contains(local) ? popup : nil
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void
        var onClear: (() -> Void)?
        var onFocusChange: (Bool) -> Void
        var cachedLabels: [String] = []
        var cachedShowsPlaceholder = false
        var cachedTextColor: NSColor?

        init(onSelect: @escaping (Int) -> Void, onClear: (() -> Void)?, onFocusChange: @escaping (Bool) -> Void) {
            self.onSelect = onSelect
            self.onClear = onClear
            self.onFocusChange = onFocusChange
        }

        @objc func selectionDidChange(_ sender: NSPopUpButton) {
            onSelect(sender.indexOfSelectedItem)
        }
    }
}

struct CommitFormattingTextFieldContextMenuItem {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void
}

struct CommitFormattingTextField: View {
    let placeholder: String
    @Binding var text: String
    let formatter: (String) -> String
    var updatesContinuously: Bool = true
    var clearBackgroundInDarkNew: Bool = false
    var showsRenewedSurface: Bool = true
    var isBordered: Bool = true
    var focusRingType: NSFocusRingType = .default
    var textAlignment: NSTextAlignment = .left
    var font: NSFont = appNSFont(.body)
    var textColor: NSColor = .labelColor
    var placeholderColor: NSColor? = nil
    var visualState: AppFieldVisualState = .normal
    var liveVisualState: ((String) -> AppFieldVisualState)? = nil
    var contextMenuItems: [CommitFormattingTextFieldContextMenuItem] = []
    var onFocusChange: ((Bool) -> Void)? = nil

    @State private var isFocused = false

    var body: some View {
        CommitFormattingTextFieldRepresentable(
            placeholder: placeholder,
            text: $text,
            formatter: formatter,
            updatesContinuously: updatesContinuously,
            clearBackgroundInDarkNew: clearBackgroundInDarkNew,
            showsRenewedSurface: showsRenewedSurface,
            isBordered: isBordered,
            focusRingType: focusRingType,
            textAlignment: textAlignment,
            font: font,
            textColor: textColor,
            placeholderColor: placeholderColor,
            visualState: visualState,
            liveVisualState: liveVisualState,
            contextMenuItems: contextMenuItems,
            onFocusChange: { focused in
                isFocused = focused
                onFocusChange?(focused)
            }
        )
        .preference(key: AppFieldFocusPreferenceKey.self, value: isFocused)
    }
}

// NSView-backed fields already publish their real AppKit focus state. Using the
// SwiftUI FocusState reporter as well creates a second keyboard focus stop around
// the same visible control. Route their chrome through the native reporter only.
extension CommitFormattingTextField {
    func appTextInputChrome(
        horizontalPadding: CGFloat = AppPalette.textFieldHorizontalPadding,
        verticalPadding: CGFloat = AppPalette.textFieldVerticalPadding,
        minHeight: CGFloat = AppPalette.fieldMinHeight,
        fillsWidth: Bool = true,
        fill: Color = AppPalette.fieldSurface,
        stroke: Color = AppPalette.subtleBorder
    ) -> some View {
        self.appTextInputChrome(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            minHeight: minHeight,
            fillsWidth: fillsWidth,
            fill: fill,
            stroke: stroke,
            tracksFocus: false
        )
    }
}

private struct CommitFormattingTextFieldRepresentable: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let formatter: (String) -> String
    var updatesContinuously: Bool = true
    var clearBackgroundInDarkNew: Bool = false
    var showsRenewedSurface: Bool = true
    var isBordered: Bool = true
    var focusRingType: NSFocusRingType = .default
    var textAlignment: NSTextAlignment = .left
    var font: NSFont = appNSFont(.body)
    var textColor: NSColor = .labelColor
    var placeholderColor: NSColor? = nil
    var visualState: AppFieldVisualState = .normal
    var liveVisualState: ((String) -> AppFieldVisualState)? = nil
    var contextMenuItems: [CommitFormattingTextFieldContextMenuItem] = []
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = CommitFormattingNSTextField(string: text)
        field.delegate = context.coordinator
        field.customMenuProvider = { [weak coordinator = context.coordinator] in
            coordinator?.contextMenu()
        }
        AppTextEditingSupport.configureTextField(field, menu: context.coordinator.contextMenu())
        applyChrome(to: field)
        field.focusRingType = effectiveFocusRingType
        field.alignment = textAlignment
        field.font = font
        field.textColor = textColor
        field.lineBreakMode = .byTruncatingTail
        applyPlaceholder(to: field)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        let isEditing = nsView.currentEditor() != nil
        if !isEditing && nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let field = nsView as? CommitFormattingNSTextField {
            field.customMenuProvider = { [weak coordinator = context.coordinator] in
                coordinator?.contextMenu()
            }
        }
        let menu = context.coordinator.contextMenu()
        nsView.menu = menu
        nsView.currentEditor()?.menu = menu
        applyChrome(to: nsView)
        nsView.focusRingType = effectiveFocusRingType
        nsView.alignment = textAlignment
        nsView.font = font
        nsView.textColor = textColor
        applyPlaceholder(to: nsView)
    }

    private func applyChrome(to field: NSTextField) {
        applyChrome(to: field, state: effectiveVisualState(for: field.stringValue))
    }

    private func applyChrome(to field: NSTextField, state: AppFieldVisualState) {
        let usesClearBackground = clearBackgroundInDarkNew && currentVisualModePreference() == .darkNew
        let usesNativeBorder = !AppRuntime.usesRenewedChrome && !usesClearBackground && isBordered
        field.isBordered = usesNativeBorder
        field.drawsBackground = state.isInvalid
        field.backgroundColor = state.isInvalid ? NSColor(state.fill) : .clear
        field.wantsLayer = true
        field.layer?.cornerRadius = AppPalette.smallCornerRadius
        field.layer?.masksToBounds = true
        if state == .normal {
            field.layer?.backgroundColor = NSColor.clear.cgColor
            field.layer?.borderWidth = 0
        } else {
            field.layer?.backgroundColor = NSColor(state.fill).cgColor
            field.layer?.borderColor = NSColor(state.stroke).cgColor
            field.layer?.borderWidth = state.isInvalid ? 1.6 : 1
        }
    }

    private var effectiveFocusRingType: NSFocusRingType {
        (AppRuntime.usesRenewedChrome || !isBordered) ? .none : focusRingType
    }

    private func effectiveVisualState(for rawValue: String) -> AppFieldVisualState {
        liveVisualState?(rawValue) ?? visualState
    }

    private func applyPlaceholder(to field: NSTextField) {
        if let placeholderColor {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = textAlignment
            field.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: placeholderColor,
                    .font: font,
                    .paragraphStyle: paragraph
                ]
            )
        } else {
            field.placeholderAttributedString = nil
            field.placeholderString = placeholder
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommitFormattingTextFieldRepresentable

        init(_ parent: CommitFormattingTextFieldRepresentable) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if parent.updatesContinuously {
                parent.text = field.stringValue
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.onFocusChange(true)
            AppFocusPulse.setFocused(true, on: field)
            if let editor = field.currentEditor() {
                AppTextEditingSupport.prepareEditor(editor, menu: contextMenu())
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let formatted = parent.formatter(field.stringValue)
            field.stringValue = formatted
            parent.text = formatted
            parent.applyChrome(to: field, state: parent.effectiveVisualState(for: formatted))
            parent.onFocusChange(false)
            AppFocusPulse.setFocused(false, on: field)
        }

        func contextMenu() -> NSMenu {
            var additionalItems: [NSMenuItem] = []
            for (index, item) in parent.contextMenuItems.enumerated() {
                let menuItem = NSMenuItem(
                    title: item.title,
                    action: #selector(performContextMenuItem(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = index
                menuItem.isEnabled = item.isEnabled
                additionalItems.append(menuItem)
            }
            return AppTextEditingSupport.standardContextMenu(additionalItems: additionalItems)
        }

        @objc private func performContextMenuItem(_ sender: NSMenuItem) {
            guard
                let index = sender.representedObject as? Int,
                parent.contextMenuItems.indices.contains(index),
                parent.contextMenuItems[index].isEnabled
            else { return }
            parent.contextMenuItems[index].action()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let field = control as? NSTextField else { return false }
            return AppTextEditingSupport.handleCommitFieldCommand(
                commandSelector,
                field: field,
                textView: textView,
                commit: { [weak self] field in self?.commit(field) },
                cancel: { [weak self] field in self?.cancel(field) }
            )
        }

        private func commit(_ field: NSTextField) {
            let formatted = parent.formatter(field.stringValue)
            field.stringValue = formatted
            parent.text = formatted
            parent.applyChrome(to: field, state: parent.effectiveVisualState(for: formatted))
        }

        private func cancel(_ field: NSTextField) {
            field.stringValue = parent.text
            parent.applyChrome(to: field, state: parent.effectiveVisualState(for: parent.text))
            field.window?.makeFirstResponder(nil)
        }
    }
}

private final class CommitFormattingNSTextField: NSTextField {
    var customMenuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        customMenuProvider?() ?? super.menu(for: event)
    }

    override func layout() {
        super.layout()
        AppFocusPulse.updateLayout(on: self)
    }

}

struct CommitDateFieldWithTodayButton: View {
    let placeholder: String
    let text: Binding<String>
    let formatter: (String) -> String
    var updatesContinuously: Bool = false
    var clearBackgroundInDarkNew: Bool = false
    var width: CGFloat
    var height: CGFloat = AppRuntime.usesRenewedChrome ? AppPalette.fieldMinHeight : 22
    var showsTodayButton: Bool = true
    var showsCalendarPicker: Bool = false
    var language: AppLanguage = .swedish
    var fill: Color = AppPalette.fieldSurface
    var stroke: Color = AppPalette.subtleBorder
    var state: AppFieldVisualState = .normal
    var textAlignment: NSTextAlignment = .left
    var contextMenuItems: [CommitFormattingTextFieldContextMenuItem] = []

    @State private var showingPicker = false

    private var selectedDate: Date {
        DateParsers.isoDay.date(from: text.wrappedValue) ?? Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        HStack(spacing: 6) {
            CommitFormattingTextField(
                placeholder: placeholder,
                text: text,
                formatter: formatter,
                updatesContinuously: updatesContinuously,
                clearBackgroundInDarkNew: clearBackgroundInDarkNew,
                showsRenewedSurface: false,
                isBordered: false,
                textAlignment: textAlignment,
                font: appDateNSFont(),
                contextMenuItems: contextMenuItems
            )
            .frame(minHeight: 18)
            .appTextInputChrome(
                horizontalPadding: AppPalette.textFieldHorizontalPadding,
                verticalPadding: AppPalette.textFieldVerticalPadding,
                minHeight: height,
                fillsWidth: false,
                fill: resolvedFill,
                stroke: resolvedStroke
            )
            .help(state.helpText ?? "")
            .frame(width: width, alignment: .leading)

            if showsTodayButton {
                AppTodayDateButton {
                    text.wrappedValue = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
                }
            }

            if showsCalendarPicker {
                Button {
                    showingPicker.toggle()
                } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(AppPalette.vividBlue)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppPalette.secondaryCardSurface)
                        )
                }
                .buttonStyle(.plain)
                .help(language.text("Choose date", "Välj datum"))
                .accessibilityLabel(language.text("Choose date", "Välj datum"))
                .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { selectedDate },
                            set: { newValue in
                                text.wrappedValue = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: newValue))
                            }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(14)
                    .frame(width: 280)
                }
            }
        }
    }

    private var resolvedFill: Color {
        state == .normal ? fill : state.fill
    }

    private var resolvedStroke: Color {
        state == .normal ? stroke : state.stroke
    }
}

struct AppDateField: View {
    let placeholder: String
    let text: Binding<String>
    var width: CGFloat? = nil
    var height: CGFloat = AppPalette.fieldMinHeight
    var showsTodayButton = false
    var showsCalendarPicker = false
    var language: AppLanguage = .swedish
    var state: AppFieldVisualState = .normal
    var textAlignment: NSTextAlignment = .left
    var isDisabled = false
    var horizontalPadding: CGFloat = AppPalette.textFieldHorizontalPadding
    var verticalPadding: CGFloat = AppPalette.textFieldVerticalPadding
    var fill: Color = AppPalette.fieldSurface
    var stroke: Color = AppPalette.subtleBorder
    var todayButtonFill: Color? = nil
    var todayButtonHorizontalPadding: CGFloat? = nil
    var todayButtonIsCompact = false
    var todayButtonMinWidth: CGFloat? = nil

    @State private var showingPicker = false

    private var selectedDate: Date {
        DateParsers.isoDay.date(from: text.wrappedValue) ?? Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        HStack(spacing: 6) {
            CommitFormattingTextField(
                placeholder: placeholder,
                text: text,
                formatter: DateParsers.canonicalizedDayInput,
                updatesContinuously: false,
                showsRenewedSurface: false,
                isBordered: false,
                textAlignment: textAlignment,
                font: appDateNSFont()
            )
            .frame(minHeight: 18)
            .appTextInputChrome(
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                minHeight: height,
                fillsWidth: width == nil,
                fill: resolvedFill,
                stroke: resolvedStroke
            )
            .help(state.helpText ?? "")
            .frame(width: width, alignment: alignment)

            if showsTodayButton {
                AppTodayDateButton(
                    title: language.text("Today", "Idag"),
                    fill: todayButtonFill ?? fill,
                    horizontalPadding: todayButtonHorizontalPadding,
                    isCompact: todayButtonIsCompact,
                    minWidth: todayButtonMinWidth
                ) {
                    text.wrappedValue = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
                }
            }

            if showsCalendarPicker {
                Button {
                    showingPicker.toggle()
                } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(AppPalette.vividBlue)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppPalette.secondaryCardSurface)
                        )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { selectedDate },
                            set: { newValue in
                                text.wrappedValue = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: newValue))
                            }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(14)
                    .frame(width: 280)
                }
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }

    private var resolvedFill: Color {
        state == .normal ? fill : state.fill
    }

    private var resolvedStroke: Color {
        state == .normal ? stroke : state.stroke
    }

    private var alignment: Alignment {
        switch textAlignment {
        case .center:
            return .center
        case .right:
            return .trailing
        default:
            return .leading
        }
    }
}

struct ContentSectionTitleView: View {
    let title: String
    var trailingActionTitle: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .appTypography(.sectionTitle)
                .foregroundStyle(AppPalette.appText)
            if let trailingActionTitle, let trailingAction {
                AppIconAddButton(title: trailingActionTitle, action: trailingAction)
            }
            Rectangle()
                .fill(AppPalette.subtleBorder.opacity(AppRuntime.usesRenewedChrome ? 0.9 : 1))
                .frame(height: 1)
        }
        .padding(.top, AppRuntime.usesRenewedChrome ? 5 : 5)
    }
}

struct CollapsibleSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool
    var showsDivider = false
    var trailingActionTitle: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .appTypography(.sectionTitle)
                        .foregroundStyle(AppPalette.appText)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let trailingActionTitle, let trailingAction {
                AppIconAddButton(title: trailingActionTitle) {
                    trailingAction()
                }
            }

            if showsDivider {
                Rectangle()
                    .fill(AppPalette.subtleBorder.opacity(AppRuntime.usesRenewedChrome ? 0.9 : 1))
                    .frame(height: 1)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.top, AppRuntime.usesRenewedChrome ? 8 : 5)
        .padding(.bottom, 0)
    }
}


typealias ProjectFieldStack<Content: View> = AppLabeledField<Content, EmptyView>

struct DetailGroup<Content: View>: View {
    let title: String
    var showsSurface: Bool = true
    var titleActionTitle: String? = nil
    var titleAction: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: title.nonEmpty == nil ? AppPalette.titleSpacing + 4 : 4) {
            if let title = title.nonEmpty {
                ContentSectionTitleView(
                    title: title,
                    trailingActionTitle: titleActionTitle,
                    trailingAction: titleAction
                )
            }
            content
                .padding(AppPalette.sectionPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                        .fill(showsSurface ? AppPalette.secondaryCardSurface : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                        .stroke(showsSurface && AppRuntime.usesRenewedChrome ? AppPalette.subtleBorder : Color.clear, lineWidth: 1)
                )
        }
    }
}



struct EditableTextArea: View {
    let title: String
    let text: Binding<String>
    var minimumHeight: CGFloat = 86
    var showsResizeHandle: Bool = false
    var usesPlainTextEditor = false

    var body: some View {
        AppTextEditorField(
            title: title,
            text: text,
            minimumHeight: minimumHeight,
            showsResizeHandle: showsResizeHandle,
            usesPlainTextEditor: usesPlainTextEditor
        )
    }
}

struct ReadOnlyValue: View {
    let text: String
    var clearBackgroundInDarkNew = false
    var state: AppFieldVisualState = .readOnly

    var body: some View {
        Text(text)
            .appTypography(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppPalette.textFieldHorizontalPadding)
            .padding(.vertical, AppPalette.textFieldVerticalPadding)
            .frame(minHeight: AppPalette.fieldMinHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                    .fill(resolvedFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                    .stroke(resolvedStroke, lineWidth: 1)
            )
            .help(state.helpText ?? "")
    }

    private var resolvedFill: Color {
        if state != .readOnly {
            return state.fill
        }
        return clearBackgroundInDarkNew && currentVisualModePreference() == .darkNew ? Color.clear : AppPalette.fieldSurface
    }

    private var resolvedStroke: Color {
        if state != .readOnly {
            return state.stroke
        }
        return AppRuntime.usesRenewedChrome ? AppPalette.subtleBorder : Color.clear
    }
}


private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
