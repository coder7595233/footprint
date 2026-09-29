import AppKit

enum AppTextEditingSupport {
    struct MenuLabels: Equatable {
        var cut: String
        var copy: String
        var paste: String
        var selectAll: String
    }

    struct StandardBehaviorCheck: Identifiable, Equatable {
        let id: String
        let title: String
        let isPassing: Bool
    }

    static var defaultMenuLabels: MenuLabels {
        let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferredLanguage.hasPrefix("sv") {
            return MenuLabels(cut: "Klipp ut", copy: "Kopiera", paste: "Klistra in", selectAll: "Markera allt")
        }
        return MenuLabels(cut: "Cut", copy: "Copy", paste: "Paste", selectAll: "Select All")
    }

    @MainActor
    static func standardContextMenu(
        isEditable: Bool = true,
        labels: MenuLabels = defaultMenuLabels,
        additionalItems: [NSMenuItem] = []
    ) -> NSMenu {
        let menu = NSMenu()
        if isEditable {
            menu.addItem(menuItem(title: labels.cut, action: #selector(NSText.cut(_:))))
        }
        menu.addItem(menuItem(title: labels.copy, action: #selector(NSText.copy(_:))))
        if isEditable {
            menu.addItem(menuItem(title: labels.paste, action: #selector(NSText.paste(_:))))
        }
        menu.addItem(menuItem(title: labels.selectAll, action: #selector(NSText.selectAll(_:))))
        if !additionalItems.isEmpty {
            menu.addItem(.separator())
            additionalItems.forEach(menu.addItem)
        }
        return menu
    }

    @MainActor
    static func standardBehaviorChecks(isEditable: Bool = true) -> [StandardBehaviorCheck] {
        let menuActions = standardContextMenu(isEditable: isEditable).items.compactMap(\.action)
        let field = NSTextField()
        configureTextField(field, isEditable: isEditable)
        let textView = NSTextView()
        textView.isEditable = isEditable
        textView.allowsUndo = false
        textView.isRichText = true
        textView.importsGraphics = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        prepareEditor(textView)
        let editorMenuActions = textView.menu?.items.compactMap(\.action) ?? []

        return [
            StandardBehaviorCheck(
                id: "copy",
                title: "Copy",
                isPassing: menuActions.contains(#selector(NSText.copy(_:)))
            ),
            StandardBehaviorCheck(
                id: "select-all",
                title: "Select all",
                isPassing: menuActions.contains(#selector(NSText.selectAll(_:)))
            ),
            StandardBehaviorCheck(
                id: "cut-policy",
                title: "Cut matches editability",
                isPassing: menuActions.contains(#selector(NSText.cut(_:))) == isEditable
            ),
            StandardBehaviorCheck(
                id: "paste-policy",
                title: "Paste matches editability",
                isPassing: menuActions.contains(#selector(NSText.paste(_:))) == isEditable
            ),
            StandardBehaviorCheck(
                id: "undo",
                title: "Undo enabled for field editors",
                isPassing: textView.allowsUndo
            ),
            StandardBehaviorCheck(
                id: "plain-text",
                title: "Plain text field editors",
                isPassing: !textView.isRichText && !textView.importsGraphics
            ),
            StandardBehaviorCheck(
                id: "smart-substitutions",
                title: "Smart substitutions disabled",
                isPassing: !textView.isAutomaticQuoteSubstitutionEnabled
                    && !textView.isAutomaticDashSubstitutionEnabled
                    && !textView.isAutomaticTextReplacementEnabled
                    && !textView.isAutomaticSpellingCorrectionEnabled
            ),
            StandardBehaviorCheck(
                id: "editor-menu",
                title: "Field editor menu matches editability",
                isPassing: editorMenuActions.contains(#selector(NSText.copy(_:)))
                    && editorMenuActions.contains(#selector(NSText.selectAll(_:)))
                    && (editorMenuActions.contains(#selector(NSText.cut(_:))) == isEditable)
                    && (editorMenuActions.contains(#selector(NSText.paste(_:))) == isEditable)
                    && field.menu?.items.compactMap(\.action).contains(#selector(NSText.copy(_:))) == true
            ),
        ]
    }

    @MainActor
    static func configureTextField(_ field: NSTextField, isEditable: Bool = true, menu: NSMenu? = nil) {
        field.allowsEditingTextAttributes = false
        field.importsGraphics = false
        field.allowsExpansionToolTips = true
        field.menu = menu ?? standardContextMenu(isEditable: isEditable)
    }

    @MainActor
    static func prepareEditor(_ textView: NSTextView, menu: NSMenu? = nil) {
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.menu = menu ?? standardContextMenu(isEditable: textView.isEditable)
    }

    @MainActor
    static func prepareEditor(_ editor: NSText, menu: NSMenu? = nil) {
        if let textView = editor as? NSTextView {
            prepareEditor(textView, menu: menu)
            return
        }
        editor.menu = menu ?? standardContextMenu(isEditable: editor.isEditable)
    }

    @MainActor
    static func handleCommitFieldCommand(
        _ commandSelector: Selector,
        field: NSTextField,
        textView: NSTextView,
        commit: (NSTextField) -> Void,
        cancel: (NSTextField) -> Void
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            commit(field)
            // Same filtered routing as Tab: the raw key-view loop could land
            // Return on decorative/non-editable views, looking like a no-op.
            AppFormKeyboardRouting.moveFocus(from: field, direction: .forward)
            return true
        case #selector(NSResponder.insertTab(_:)):
            commit(field)
            AppFormKeyboardRouting.moveFocus(from: field, direction: .forward)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            commit(field)
            AppFormKeyboardRouting.moveFocus(from: field, direction: .backward)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel(field)
            return true
        default:
            prepareEditor(textView, menu: textView.menu)
            return false
        }
    }

    @MainActor
    private static func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = nil
        return item
    }
}
