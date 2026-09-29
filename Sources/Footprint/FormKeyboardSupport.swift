import SwiftUI

enum AppFormFocusDirection: Equatable {
    case forward
    case backward
}

enum AppFormKeyboardRouting {
    static func focusDirection(for commandSelector: Selector) -> AppFormFocusDirection? {
        switch commandSelector {
        case #selector(NSResponder.insertTab(_:)):
            return .forward
        case #selector(NSResponder.insertBacktab(_:)):
            return .backward
        default:
            return nil
        }
    }

    @MainActor
    @discardableResult
    static func moveFocus(from view: NSView, direction: AppFormFocusDirection) -> Bool {
        guard let window = view.window else { return false }
        window.recalculateKeyViewLoop()

        var candidate: NSView? = view
        for _ in 0..<256 {
            candidate = direction == .forward
                ? candidate?.nextValidKeyView
                : candidate?.previousValidKeyView
            guard let candidate, candidate !== view else { break }
            guard isEditableFormKeyView(candidate) else { continue }
            if window.makeFirstResponder(candidate) {
                return true
            }
        }
        return false
    }

    @MainActor
    static func moveFocusFromCurrentResponder(direction: AppFormFocusDirection) -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let anchor = formControl(for: window.firstResponder, in: window) else {
            return false
        }
        return moveFocus(from: anchor, direction: direction)
    }

    /// Routes Tab away from any non-text AppKit key view. SwiftUI can expose
    /// decorative and action buttons in its native key-view loop; using that
    /// view only as an anchor ensures one Tab always reaches the next editable
    /// form control. Text fields deliberately stay out of this path: their
    /// delegates need to commit/format their value, and autocomplete fields may
    /// use Tab to accept a suggestion first.
    @MainActor
    @discardableResult
    static func moveFocusFromCurrentNonTextFormResponder(direction: AppFormFocusDirection) -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let anchor = formControl(for: window.firstResponder, in: window),
              !(anchor is NSTextField) else {
            return false
        }
        return moveFocus(from: anchor, direction: direction)
    }

    @MainActor
    private static func formControl(for responder: NSResponder?, in window: NSWindow) -> NSView? {
        if let view = responder as? NSView, !(view is NSTextView) {
            return view
        }
        guard let editor = responder as? NSTextView else { return nil }
        return allSubviews(of: window.contentView).first { view in
            guard let field = view as? NSTextField else { return false }
            return field.currentEditor() === editor
        }
    }

    @MainActor
    private static func allSubviews(of root: NSView?) -> [NSView] {
        guard let root else { return [] }
        return [root] + root.subviews.flatMap { allSubviews(of: $0) }
    }

    @MainActor
    private static func isEditableFormKeyView(_ view: NSView) -> Bool {
        guard !view.isHidden, view.alphaValue > 0.001 else { return false }
        if let textField = view as? NSTextField {
            return textField.isEnabled && textField.isEditable
        }
        if let comboBox = view as? NSComboBox {
            return comboBox.isEnabled
        }
        if let popup = view as? NSPopUpButton {
            return popup.isEnabled
        }
        if let datePicker = view as? NSDatePicker {
            return datePicker.isEnabled
        }
        if let slider = view as? NSSlider {
            return slider.isEnabled
        }
        if let segmentedControl = view as? NSSegmentedControl {
            return segmentedControl.isEnabled
        }
        let typeName = String(describing: type(of: view))
        return typeName.contains("FocusableCheckboxButton") || typeName == "FocusView"
    }
}

private struct AppFormTabRoutingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { keyPress in
            guard keyPress.key == .tab else { return .ignored }
            let direction: AppFormFocusDirection = keyPress.modifiers.contains(EventModifiers.shift) ? .backward : .forward
            return AppFormKeyboardRouting.moveFocusFromCurrentResponder(direction: direction) ? .handled : .ignored
        }
    }
}

extension View {
    func appFormTabRouting() -> some View {
        modifier(AppFormTabRoutingModifier())
    }
}

/// Adds one real AppKit key-view node to a compound SwiftUI control without
/// making each of its visual child buttons a separate Tab stop.
struct AppCompoundFieldFocusBridge: NSViewRepresentable {
    let onFocusChange: (Bool) -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    var onActivate: () -> Void = {}

    func makeNSView(context: Context) -> FocusView {
        FocusView(
            onFocusChange: onFocusChange,
            onMoveLeft: onMoveLeft,
            onMoveRight: onMoveRight,
            onActivate: onActivate
        )
    }

    func updateNSView(_ view: FocusView, context: Context) {
        view.onFocusChange = onFocusChange
        view.onMoveLeft = onMoveLeft
        view.onMoveRight = onMoveRight
        view.onActivate = onActivate
    }

    final class FocusView: NSView {
        var onFocusChange: (Bool) -> Void
        var onMoveLeft: () -> Void
        var onMoveRight: () -> Void
        var onActivate: () -> Void

        init(
            onFocusChange: @escaping (Bool) -> Void,
            onMoveLeft: @escaping () -> Void,
            onMoveRight: @escaping () -> Void,
            onActivate: @escaping () -> Void
        ) {
            self.onFocusChange = onFocusChange
            self.onMoveLeft = onMoveLeft
            self.onMoveRight = onMoveRight
            self.onActivate = onActivate
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocusChange(true) }
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted { onFocusChange(false) }
            return accepted
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 48:
                interpretKeyEvents([event])
            case 123:
                onMoveLeft()
            case 124:
                onMoveRight()
            case 36, 49, 76:
                onActivate()
            default:
                super.keyDown(with: event)
            }
        }

        override func insertTab(_ sender: Any?) {
            AppFormKeyboardRouting.moveFocus(from: self, direction: .forward)
        }

        override func insertBacktab(_ sender: Any?) {
            AppFormKeyboardRouting.moveFocus(from: self, direction: .backward)
        }
    }
}

private struct FormSaveShortcutModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.background(alignment: .topLeading) {
            Button("", action: action)
                .keyboardShortcut(.return, modifiers: .command)
                .labelsHidden()
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .opacity(0.001)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    func formSaveShortcut(action: @escaping () -> Void) -> some View {
        modifier(FormSaveShortcutModifier(action: action))
    }
}
