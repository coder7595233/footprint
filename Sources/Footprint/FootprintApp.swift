import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

extension Notification.Name {
    static let footprintCreateNewRecord = Notification.Name("FootprintCreateNewRecord")
    static let footprintOpenSalaryCalculator = Notification.Name("FootprintOpenSalaryCalculator")
    static let footprintShowCommandPalette = Notification.Name("FootprintShowCommandPalette")
    static let footprintShowDataWorkspace = Notification.Name("FootprintShowDataWorkspace")
    static let footprintSelectedTabChanged = Notification.Name("FootprintSelectedTabChanged")
    static let footprintMoveSelectionUp = Notification.Name("FootprintMoveSelectionUp")
    static let footprintMoveSelectionDown = Notification.Name("FootprintMoveSelectionDown")
    static let footprintCalendarTaskReminderPreferenceChanged = Notification.Name("FootprintCalendarTaskReminderPreferenceChanged")
    /// Posted when macOS notification permission was just given, so the
    /// application reminders can be scheduled without asking a second time.
    static let footprintNotificationAuthorizationGranted = Notification.Name("FootprintNotificationAuthorizationGranted")
    static let footprintCalendarMeetingDidSave = Notification.Name("FootprintCalendarMeetingDidSave")
}

@MainActor
private final class FootprintWindow: NSWindow {
    let providedUndoManager: UndoManager

    init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool, undoManager: UndoManager) {
        self.providedUndoManager = undoManager
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
    }

    override var undoManager: UndoManager? {
        providedUndoManager
    }
}

enum AppUndoRedoRouting {
    @MainActor
    static func shouldUseNativeTextUndoRedo(
        isEditableTextResponder: Bool,
        textUndoManager: UndoManager?,
        storeUndoManager: UndoManager,
        isRedo: Bool
    ) -> Bool {
        guard isEditableTextResponder,
              let textUndoManager,
              textUndoManager !== storeUndoManager else {
            return false
        }
        return isRedo ? textUndoManager.canRedo : textUndoManager.canUndo
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var dataExchangeWindow: NSWindow?
    private let store = GrantDataStore.loadFromBundle()
    private lazy var reminderCoordinator = GrantReminderCoordinator()
    private lazy var calendarTaskReminderCoordinator = CalendarTaskReminderCoordinator()
    private let notificationRouter = AppNotificationRouter()
    // Notification-center access is opt-in because legacy per-account state can
    // terminate the process before the API returns: application reminders are
    // only scheduled after notifications are turned on under Settings >
    // Calendar > Task notifications, and they can be switched off separately
    // under Reminder times (CalendarReminderSettings.grantRemindersEnabled).
    private let grantRemindersEnabled = true
    private var cancellables = Set<AnyCancellable>()
    private var lastRenderedVisualModeRaw: String?
    private var newRecordMenuItem: NSMenuItem?
    private var commandPaletteMenuItem: NSMenuItem?
    private var undoMenuItem: NSMenuItem?
    private var redoMenuItem: NSMenuItem?
    private var footerStatusBarMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?
    private var salaryCalculatorMenuItem: NSMenuItem?
    private var salaryCalculatorSubmenu: NSMenu?
    private var dataMenuItem: NSMenuItem?
    private var importDatabaseMenuItem: NSMenuItem?
    private var exportDataMenuItem: NSMenuItem?
    private var fillMissingFieldsMenuItem: NSMenuItem?
    private var archiveMenuItem: NSMenuItem?
    private var openActiveDataFolderMenuItem: NSMenuItem?
    private var lightModeMenuItem: NSMenuItem?
    private var darkModeMenuItem: NSMenuItem?
    private var lightCleanModeMenuItem: NSMenuItem?
    private var darkCleanModeMenuItem: NSMenuItem?
    private var darkNewModeMenuItem: NSMenuItem?
    private var incompleteDataMenuItems: [PersonIncompleteDataFilter: NSMenuItem] = [:]
    private var visualModeTimer: Timer?
    private var reminderRefreshTask: DispatchWorkItem?
    private var calendarTaskReminderRefreshTask: DispatchWorkItem?
    private var selectionNavigationEventMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if runCommandLineBenchmarkIfRequested() {
            return
        }

        AppAppearanceRegistry.updateSystemAppearancePreference()
        restoreInitialWorkspaceRoute()

        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu()
        applicationMenu.addItem(
            withTitle: "Hide \(store.language.appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let preferencesItem = NSMenuItem(
            title: store.language.text("Preferences…", "Inställningar…"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        applicationMenu.addItem(preferencesItem)
        settingsMenuItem = preferencesItem
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Quit \(store.language.appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)

        let fileMenuItem = NSMenuItem(title: store.language.text("File", "Arkiv"), action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: store.language.text("File", "Arkiv"))
        let newRecordItem = NSMenuItem(title: newRecordTitle(), action: #selector(createNewRecord), keyEquivalent: "n")
        newRecordItem.target = self
        fileMenu.addItem(newRecordItem)
        newRecordMenuItem = newRecordItem
        let commandPaletteItem = NSMenuItem(
            title: store.language.text("Command palette…", "Kommandopalett…"),
            action: #selector(showCommandPalette),
            keyEquivalent: "k"
        )
        commandPaletteItem.target = self
        fileMenu.addItem(commandPaletteItem)
        commandPaletteMenuItem = commandPaletteItem
        fileMenu.addItem(.separator())
        let footerStatusBarItem = NSMenuItem(
            title: footerStatusBarMenuTitle(),
            action: #selector(toggleFooterStatusBar),
            keyEquivalent: ""
        )
        footerStatusBarItem.target = self
        fileMenu.addItem(footerStatusBarItem)
        footerStatusBarMenuItem = footerStatusBarItem
        let salaryCalculatorItem = NSMenuItem(title: store.language.text("Salary calculator", "Lönekalkyl"), action: nil, keyEquivalent: "")
        let salaryCalculatorMenu = NSMenu(title: store.language.text("Salary calculator", "Lönekalkyl"))
        salaryCalculatorItem.submenu = salaryCalculatorMenu
        fileMenu.addItem(salaryCalculatorItem)
        salaryCalculatorMenuItem = salaryCalculatorItem
        salaryCalculatorSubmenu = salaryCalculatorMenu
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem(title: store.language.text("Edit", "Redigera"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: store.language.text("Edit", "Redigera"))
        let undoItem = NSMenuItem(title: undoMenuTitle(), action: #selector(performUndo(_:)), keyEquivalent: "z")
        undoItem.target = self
        editMenu.addItem(undoItem)
        undoMenuItem = undoItem
        let redoItem = NSMenuItem(title: redoMenuTitle(), action: #selector(performRedo(_:)), keyEquivalent: "Z")
        redoItem.target = self
        editMenu.addItem(redoItem)
        redoMenuItem = redoItem
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: store.language.text("Cut", "Klipp ut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: store.language.text("Copy", "Kopiera"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: store.language.text("Paste", "Klistra in"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: store.language.text("Select All", "Markera allt"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let selectionsMenuItem = NSMenuItem(title: store.language.text("Selections", "Urval"), action: nil, keyEquivalent: "")
        let selectionsMenu = NSMenu(title: store.language.text("Selections", "Urval"))
        let incompleteDataMenuItem = NSMenuItem(title: store.language.text("Filter by incomplete data", "Filtrera ofullständiga data"), action: nil, keyEquivalent: "")
        let incompleteDataMenu = NSMenu(title: store.language.text("Filter by incomplete data", "Filtrera ofullständiga data"))
        let incompleteItems: [(PersonIncompleteDataFilter, String)] = [
            (.none, store.language.text("None", "Ingen")),
            (.any, store.language.text("Any", "Alla")),
            (.orcid, store.language.text("Missing ORCID", "Saknar ORCID")),
            (.email, store.language.text("Missing email", "Saknar e-post")),
            (.organization, store.language.text("Missing primary affiliation organization", "Saknar primär affiliationsorganisation")),
            (.country, store.language.text("Missing primary affiliation country", "Saknar primärt affiliationsland")),
            (.title, store.language.text("Missing title", "Saknar titel")),
        ]
        for (filter, title) in incompleteItems {
            let item = NSMenuItem(title: title, action: #selector(selectIncompleteDataFilter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = filter.rawValue
            incompleteDataMenu.addItem(item)
            incompleteDataMenuItems[filter] = item
        }
        incompleteDataMenuItem.submenu = incompleteDataMenu
        selectionsMenu.addItem(incompleteDataMenuItem)
        selectionsMenuItem.submenu = selectionsMenu
        mainMenu.addItem(selectionsMenuItem)

        let dataMenuItem = NSMenuItem(title: store.language.text("Data", "Data"), action: nil, keyEquivalent: "")
        let dataMenu = NSMenu(title: store.language.text("Data", "Data"))
        let importItem = NSMenuItem(
            title: store.language.text("Import Footprint database…", "Importera Footprint-databas…"),
            action: #selector(importDatabasePackage),
            keyEquivalent: "i"
        )
        importItem.target = self
        dataMenu.addItem(importItem)
        importDatabaseMenuItem = importItem
        let exportDataItem = NSMenuItem(title: store.language.text("Export…", "Exportera…"), action: #selector(showDataExportCenter), keyEquivalent: "e")
        exportDataItem.target = self
        dataMenu.addItem(exportDataItem)
        exportDataMenuItem = exportDataItem
        dataMenu.addItem(.separator())
        let fillMissingItem = NSMenuItem(title: store.language.text("Fill in missing fields…", "Fyll i saknade fält…"), action: #selector(showFillMissingFields), keyEquivalent: "f")
        fillMissingItem.target = self
        fillMissingItem.keyEquivalentModifierMask = [.command, .shift]
        dataMenu.addItem(fillMissingItem)
        fillMissingFieldsMenuItem = fillMissingItem
        let archiveItem = NSMenuItem(title: store.language.text("Archive…", "Arkiv…"), action: #selector(showArchiveWorkspace), keyEquivalent: "a")
        archiveItem.target = self
        archiveItem.keyEquivalentModifierMask = [.command, .shift]
        dataMenu.addItem(archiveItem)
        archiveMenuItem = archiveItem
        let openDataFolderItem = NSMenuItem(title: store.language.text("Open active data folder", "Öppna aktiv datamapp"), action: #selector(openActiveDataFolder), keyEquivalent: "")
        openDataFolderItem.target = self
        dataMenu.addItem(openDataFolderItem)
        openActiveDataFolderMenuItem = openDataFolderItem
        dataMenuItem.submenu = dataMenu
        mainMenu.addItem(dataMenuItem)
        self.dataMenuItem = dataMenuItem

        NSApplication.shared.mainMenu = mainMenu
        bindStoreState()
        installSelectionNavigationEventMonitor()
        store.refreshCurrencyExchangeRatesIfNeeded()
        calendarTaskReminderCoordinator.configure(store: store)
        activateUserNotificationsIfEnabled()
        let resolvedVisualMode = effectiveVisualMode()
        applyVisualMode(resolvedVisualMode)
        refreshVisualMenuState()
        refreshSelectionsMenuState()
        refreshFooterStatusBarMenuState()
        refreshApplicationMenuTitle()
        refreshSalaryCalculatorMenu()
        scheduleVisualModeTimer()

        let window = FootprintWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1380, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false,
            undoManager: store.undoManager
        )
        window.title = store.language.appName
        window.contentMinSize = NSSize(width: 960, height: 640)
        configureMainWindowChrome(window)
        applyVisualMode(resolvedVisualMode, to: window)
        if !window.setFrameUsingName(AppRuntime.mainWindowAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(AppRuntime.mainWindowAutosaveName)
        window.contentView = NSHostingView(rootView: ContentView(store: store))
        lastRenderedVisualModeRaw = resolvedVisualMode.rawValue
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        self.window = window
    }

    private func configureMainWindowChrome(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.isMovableByWindowBackground = false
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Expedite, never wait: the synchronous flushes here blocked the main
        // thread for the full metadata write (~1 s with backup) on every
        // cmd-tab away. The app keeps running in the background, so kicking
        // the queued writes is enough; the blocking flush remains in
        // applicationWillTerminate where it must complete before exit.
        store.expeditePendingPersistence()
        store.expeditePendingMetadataPersistence()
        store.trimTransientCachesForBackgrounding()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        calendarTaskReminderCoordinator.refreshFromStore()
    }

    private func restoreInitialWorkspaceRoute() {
        // Developer convenience: FOOTPRINT_INITIAL_ROUTE="<tab>:<recordID>"
        // opens a specific record at launch, used by headless verification.
        if let raw = ProcessInfo.processInfo.environment["FOOTPRINT_INITIAL_ROUTE"],
           let separator = raw.firstIndex(of: ":"),
           let destination = initialWorkspaceDestination(from: String(raw[..<separator])) {
            store.route = AppRoute(recordID: String(raw[raw.index(after: separator)...]), destination: destination)
            return
        }
        guard store.route == nil,
              let destination = initialWorkspaceDestination(from: store.lastSelectedTabRaw),
              let recordID = store.lastSelectedRecordID(for: destination) else { return }
        store.route = AppRoute(recordID: recordID, destination: destination)
    }

    private func initialWorkspaceDestination(from rawTab: String?) -> AppRoute.Destination? {
        switch rawTab?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
        case "applications":
            return .applications
        case "projects":
            return .projects
        case "teaching":
            return .teaching
        case "organizations":
            return .organizations
        case "managers":
            return .organizations
        case "coauthors":
            return .people
        case "journals":
            return .journals
        case "publications":
            return .publications
        case "doctoralCandidates":
            return .doctoralCandidates
        default:
            return nil
        }
    }

    private func runCommandLineBenchmarkIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let benchmarkIndex = arguments.firstIndex(of: "--benchmark-project-open") else {
            return false
        }

        let projectName = arguments.dropFirst(benchmarkIndex + 1).first ?? "Example project"
        let report = store.benchmarkProjectOpen(projectName: projectName, language: store.language)
        FileHandle.standardOutput.write(Data((report + "\n").utf8))
        exit(0)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let selectionNavigationEventMonitor {
            NSEvent.removeMonitor(selectionNavigationEventMonitor)
            self.selectionNavigationEventMonitor = nil
        }
        visualModeTimer?.invalidate()
        visualModeTimer = nil
        store.flushPendingPersistenceIfNeeded()
        store.flushPendingMetadataPersistenceIfNeeded()
        // Bounded: an unbounded wait here let a stalled backup operation hang
        // quit forever. The data writes above have already completed; only
        // the redundant periodic backup is at stake after the timeout.
        _ = store.waitForPendingPeriodicBackup(timeout: 30)
    }

    @objc private func selectEnglish() {
        store.setLanguage(.english)
        refreshApplicationMenuTitle()
    }

    @objc private func selectSwedish() {
        store.setLanguage(.swedish)
        refreshApplicationMenuTitle()
    }

    @objc private func selectLightCleanMode() {
        store.setVisualMode(.lightClean)
    }

    @objc private func selectDarkCleanMode() {
        store.setVisualMode(.darkClean)
    }

    @objc private func selectDarkNewMode() {
        store.setVisualMode(.darkNew)
    }

    @objc private func createNewRecord() {
        NotificationCenter.default.post(name: .footprintCreateNewRecord, object: nil)
    }

    @objc private func showCommandPalette() {
        NotificationCenter.default.post(name: .footprintShowCommandPalette, object: nil)
    }

    @objc private func toggleFooterStatusBar() {
        store.setFooterStatusBarVisible(!store.showsFooterStatusBar)
        refreshFooterStatusBarMenuState()
    }

    @objc private func showSettings() {
        openSettingsWindow()
    }

    @objc private func openSalaryCalculator(_ sender: NSMenuItem) {
        guard let managerID = sender.representedObject as? String else { return }
        NotificationCenter.default.post(name: .footprintOpenSalaryCalculator, object: managerID)
    }

    @objc private func selectIncompleteDataFilter(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = PersonIncompleteDataFilter(rawValue: rawValue) else { return }
        store.setPersonIncompleteDataFilter(filter)
    }

    @objc private func showDataQualitySummary() {
        NotificationCenter.default.post(name: .footprintShowDataWorkspace, object: "quality")
    }

    @objc private func importDatabasePackage() {
        let language = store.language
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = language.text("Import", "Importera")
        panel.title = language.text("Import Footprint database", "Importera Footprint-databas")
        panel.message = language.text(
            "Choose a .footprintdb package or a verified Footprint backup folder.",
            "Välj ett .footprintdb-paket eller en verifierad mapp med Footprint-säkerhetskopior."
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = language.text("Import this Footprint database?", "Importera denna Footprint-databas?")
        confirmation.informativeText = language.text(
            "Footprint verifies the package and creates a complete safety backup first. A full package replaces the current database; a selective package merges only its listed categories.",
            "Footprint verifierar paketet och skapar först en komplett säkerhetskopia. Ett fullständigt paket ersätter den aktuella databasen; ett selektivt paket sammanfogar endast de angivna kategorierna."
        )
        confirmation.addButton(withTitle: language.text("Import", "Importera"))
        confirmation.addButton(withTitle: language.text("Cancel", "Avbryt"))
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        store.importDatabasePackage(from: url)
    }

    @objc private func showDataExportCenter() {
        openDataExchangeWindow()
    }

    @objc private func performUndo(_ sender: Any?) {
        performUndoRedo(isRedo: false)
    }

    @objc private func performRedo(_ sender: Any?) {
        performUndoRedo(isRedo: true)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performUndo(_:)) {
            menuItem.title = undoMenuTitle()
            return store.undoManager.canUndo || activeEditableTextResponderCanUndo()
        }
        if menuItem.action == #selector(performRedo(_:)) {
            menuItem.title = redoMenuTitle()
            return store.undoManager.canRedo || activeEditableTextResponderCanRedo()
        }
        return true
    }

    private func performUndoRedo(isRedo: Bool) {
        if performNativeTextUndoRedoIfAvailable(isRedo: isRedo) {
            updateUndoRedoMenuItems()
            return
        }
        window?.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if isRedo {
                guard self.store.undoManager.canRedo else {
                    self.updateUndoRedoMenuItems()
                    return
                }
                self.store.undoManager.redo()
            } else {
                guard self.store.undoManager.canUndo else {
                    self.updateUndoRedoMenuItems()
                    return
                }
                self.store.undoManager.undo()
            }
            self.updateUndoRedoMenuItems()
        }
    }

    private func performNativeTextUndoRedoIfAvailable(isRedo: Bool) -> Bool {
        guard let textView = window?.firstResponder as? NSTextView,
              textView.isEditable,
              let nativeUndoManager = textView.undoManager else {
            return false
        }
        guard AppUndoRedoRouting.shouldUseNativeTextUndoRedo(
            isEditableTextResponder: textView.isEditable,
            textUndoManager: nativeUndoManager,
            storeUndoManager: store.undoManager,
            isRedo: isRedo
        ) else {
            return false
        }
        if isRedo {
            nativeUndoManager.redo()
            return true
        }
        nativeUndoManager.undo()
        return true
    }

    private func activeEditableTextResponderCanUndo() -> Bool {
        guard let textView = window?.firstResponder as? NSTextView else { return false }
        return AppUndoRedoRouting.shouldUseNativeTextUndoRedo(
            isEditableTextResponder: textView.isEditable,
            textUndoManager: textView.undoManager,
            storeUndoManager: store.undoManager,
            isRedo: false
        )
    }

    private func activeEditableTextResponderCanRedo() -> Bool {
        guard let textView = window?.firstResponder as? NSTextView else { return false }
        return AppUndoRedoRouting.shouldUseNativeTextUndoRedo(
            isEditableTextResponder: textView.isEditable,
            textUndoManager: textView.undoManager,
            storeUndoManager: store.undoManager,
            isRedo: true
        )
    }

    private func updateUndoRedoMenuItems() {
        undoMenuItem?.title = undoMenuTitle()
        redoMenuItem?.title = redoMenuTitle()
    }

    private func undoMenuTitle() -> String {
        if let textView = window?.firstResponder as? NSTextView,
           AppUndoRedoRouting.shouldUseNativeTextUndoRedo(
            isEditableTextResponder: textView.isEditable,
            textUndoManager: textView.undoManager,
            storeUndoManager: store.undoManager,
            isRedo: false
           ) {
            return store.language.text("Undo text editing", "Ångra textredigering")
        }
        return actionMenuTitle(
            actionName: store.undoManager.undoActionName,
            englishPrefix: "Undo",
            swedishPrefix: "Ångra",
            fallbackEnglish: "Undo",
            fallbackSwedish: "Ångra"
        )
    }

    private func redoMenuTitle() -> String {
        if let textView = window?.firstResponder as? NSTextView,
           AppUndoRedoRouting.shouldUseNativeTextUndoRedo(
            isEditableTextResponder: textView.isEditable,
            textUndoManager: textView.undoManager,
            storeUndoManager: store.undoManager,
            isRedo: true
           ) {
            return store.language.text("Redo text editing", "Gör om textredigering")
        }
        return actionMenuTitle(
            actionName: store.undoManager.redoActionName,
            englishPrefix: "Redo",
            swedishPrefix: "Gör om",
            fallbackEnglish: "Redo",
            fallbackSwedish: "Gör om"
        )
    }

    private func actionMenuTitle(
        actionName: String,
        englishPrefix: String,
        swedishPrefix: String,
        fallbackEnglish: String,
        fallbackSwedish: String
    ) -> String {
        guard let action = actionName.trimmedOrNil else {
            return store.language.text(fallbackEnglish, fallbackSwedish)
        }
        return store.language.text("\(englishPrefix) \(action)", "\(swedishPrefix) \(action)")
    }

    @objc private func openBackupsFolder() {
        NSWorkspace.shared.open(store.backupsDirectoryURL)
    }

    @objc private func openActiveDataFolder() {
        NSWorkspace.shared.open(store.storageDirectoryURL)
    }

    @objc private func showFillMissingFields() {
        NotificationCenter.default.post(name: .footprintShowDataWorkspace, object: "missing")
    }

    @objc private func showDataQualityWorkspace() {
        NotificationCenter.default.post(name: .footprintShowDataWorkspace, object: "quality")
    }

    @objc private func showArchiveWorkspace() {
        NotificationCenter.default.post(name: .footprintShowDataWorkspace, object: "archive")
    }

    @objc private func verifyBackupHealth() {
        store.loadBackupHealthSummaryAsync { [weak self] summary in
            guard let self else { return }
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = self.store.language.text("Backup health", "Säkerhetskopiornas skick")
            alert.informativeText = summary
            alert.addButton(withTitle: self.store.language.text("OK", "OK"))
            alert.runModal()
        }
    }

    @objc private func restoreBackup() {
        let language = store.language
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.backupsDirectoryURL
        panel.prompt = language.text("Restore", "Återställ")
        panel.title = language.text("Choose a backup folder to restore", "Välj en mapp med säkerhetskopior att återställa")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.loadBackupRestorePreviewSummaryAsync(for: url) { [weak self] summary in
            guard let self else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = language.text("Restore backup?", "Återställ säkerhetskopia?")
            alert.informativeText = summary
            alert.addButton(withTitle: language.text("Restore", "Återställ"))
            alert.addButton(withTitle: language.text("Cancel", "Avbryt"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            self.store.restoreFromBackupAsync(directoryURL: url)
        }
    }

    private func refreshApplicationMenuTitle() {
        window?.title = store.language.appName
        settingsWindow?.title = store.language.text("Preferences", "Inställningar")
        dataExchangeWindow?.title = store.language.text("Export", "Exportera")
        refreshMenuLocalization()
        settingsMenuItem?.title = store.language.text("Preferences…", "Inställningar…")
        newRecordMenuItem?.title = newRecordTitle()
        commandPaletteMenuItem?.title = store.language.text("Command palette…", "Kommandopalett…")
        refreshFooterStatusBarMenuState()
        salaryCalculatorMenuItem?.title = store.language.text("Salary calculator", "Lönekalkyl")
        salaryCalculatorSubmenu?.title = store.language.text("Salary calculator", "Lönekalkyl")
        dataMenuItem?.title = store.language.text("Data", "Data")
        dataMenuItem?.submenu?.title = store.language.text("Data", "Data")
        importDatabaseMenuItem?.title = store.language.text("Import Footprint database…", "Importera Footprint-databas…")
        exportDataMenuItem?.title = store.language.text("Export…", "Exportera…")
        fillMissingFieldsMenuItem?.title = store.language.text("Fill in missing fields…", "Fyll i saknade fält…")
        archiveMenuItem?.title = store.language.text("Archive…", "Arkiv…")
        openActiveDataFolderMenuItem?.title = store.language.text("Open active data folder", "Öppna aktiv datamapp")
        lightCleanModeMenuItem?.title = AppVisualMode.lightClean.displayName(store.language)
        darkNewModeMenuItem?.title = AppVisualMode.darkNew.displayName(store.language)
        refreshSalaryCalculatorMenu()
    }

    private func refreshMenuLocalization() {
        let language = store.language
        let mainMenu = NSApplication.shared.mainMenu

        let applicationMenu = menuItem(in: mainMenu, at: 0)?.submenu
        menuItem(in: applicationMenu, at: 0)?.title = language.text("Hide \(language.appName)", "Dölj \(language.appName)")
        menuItem(in: applicationMenu, at: 2)?.title = language.text("Quit \(language.appName)", "Avsluta \(language.appName)")

        let fileMenuItem = menuItem(in: mainMenu, at: 1)
        fileMenuItem?.title = language.text("File", "Arkiv")
        fileMenuItem?.submenu?.title = language.text("File", "Arkiv")

        let editMenu = menuItem(in: mainMenu, at: 2)
        editMenu?.title = language.text("Edit", "Redigera")
        editMenu?.submenu?.title = language.text("Edit", "Redigera")
        updateUndoRedoMenuItems()
        menuItem(in: editMenu?.submenu, at: 3)?.title = language.text("Cut", "Klipp ut")
        menuItem(in: editMenu?.submenu, at: 4)?.title = language.text("Copy", "Kopiera")
        menuItem(in: editMenu?.submenu, at: 5)?.title = language.text("Paste", "Klistra in")
        menuItem(in: editMenu?.submenu, at: 6)?.title = language.text("Select All", "Markera allt")

        let selectionsMenu = menuItem(in: mainMenu, at: 3)
        selectionsMenu?.title = language.text("Selections", "Urval")
        selectionsMenu?.submenu?.title = language.text("Selections", "Urval")
        menuItem(in: selectionsMenu?.submenu, at: 0)?.title = language.text("Filter by incomplete data", "Filtrera ofullständiga data")
        let incompleteMenu = menuItem(in: selectionsMenu?.submenu, at: 0)?.submenu
        menuItem(in: incompleteMenu, at: 0)?.title = language.text("None", "Ingen")
        menuItem(in: incompleteMenu, at: 1)?.title = language.text("Any", "Alla")
        menuItem(in: incompleteMenu, at: 2)?.title = language.text("Missing ORCID", "Saknar ORCID")
        menuItem(in: incompleteMenu, at: 3)?.title = language.text("Missing email", "Saknar e-post")
        menuItem(in: incompleteMenu, at: 4)?.title = language.text("Missing primary affiliation organization", "Saknar primär affiliationsorganisation")
        menuItem(in: incompleteMenu, at: 5)?.title = language.text("Missing primary affiliation country", "Saknar primärt affiliationsland")
        menuItem(in: incompleteMenu, at: 6)?.title = language.text("Missing title", "Saknar titel")

    }

    private func menuItem(in menu: NSMenu?, at index: Int) -> NSMenuItem? {
        guard let menu, menu.items.indices.contains(index) else { return nil }
        return menu.items[index]
    }

    private func newRecordTitle() -> String {
        let language = store.language
        switch store.lastSelectedTabRaw {
        case "home":
            return language.text("New", "Ny")
        case "projects":
            return language.text("New project", "Nytt projekt")
        case "applications":
            return language.text("New call", "Ny utlysning")
        case "organizations":
            return language.text("New organization", "Ny organisation")
        case "managers":
            return language.text("New organization", "Ny organisation")
        case "coauthors":
            return language.text("New researcher", "Ny forskare")
        case "journals":
            return language.text("New journal", "Ny tidskrift")
        case "publications":
            return language.text("New publication", "Ny publikation")
        case "statistics":
            return language.text("New", "Ny")
        default:
            return language.text("New", "Ny")
        }
    }

    private func bindStoreState() {
        store.$metadata
            .receive(on: RunLoop.main)
            .sink { [weak self] metadata in
                guard let self else { return }
                let resolvedMode = self.effectiveVisualMode()
                self.applyVisualMode(resolvedMode)
                self.refreshRootViewIfNeeded(for: resolvedMode)
                self.refreshVisualMenuState()
                self.refreshSelectionsMenuState()
                self.refreshFooterStatusBarMenuState()
                self.refreshApplicationMenuTitle()
            }
            .store(in: &cancellables)

        store.$managers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshSalaryCalculatorMenu()
            }
            .store(in: &cancellables)

        store.$applications
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleReminderRefresh()
            }
            .store(in: &cancellables)

        store.$metadata
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleReminderRefresh()
                self?.scheduleCalendarTaskReminderRefresh()
            }
            .store(in: &cancellables)

        store.$projects
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleCalendarTaskReminderRefresh()
            }
            .store(in: &cancellables)

        store.$organizations
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleCalendarTaskReminderRefresh()
            }
            .store(in: &cancellables)

        store.$publicationRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleCalendarTaskReminderRefresh()
            }
            .store(in: &cancellables)

        store.$teachingAssignments
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleCalendarTaskReminderRefresh()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .footprintSelectedTabChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshApplicationMenuTitle()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .footprintCalendarTaskReminderPreferenceChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.activateUserNotificationsIfEnabled()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .footprintNotificationAuthorizationGranted)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleReminderRefresh()
            }
            .store(in: &cancellables)
    }

    private func installSelectionNavigationEventMonitor() {
        selectionNavigationEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleGlobalFormTabNavigation(for: event) {
                return nil
            }
            guard let notificationName = self.globalSelectionNavigationNotification(for: event) else {
                return event
            }
            NotificationCenter.default.post(name: notificationName, object: nil)
            return nil
        }
    }

    private func handleGlobalFormTabNavigation(for event: NSEvent) -> Bool {
        guard event.keyCode == 48 else { return false }
        let pressedModifiers = event.modifierFlags.intersection(
            NSEvent.ModifierFlags([.command, .control, .option, .shift])
        )
        guard pressedModifiers.isEmpty || pressedModifiers == [.shift] else { return false }
        return AppFormKeyboardRouting.moveFocusFromCurrentNonTextFormResponder(
            direction: pressedModifiers.contains(.shift) ? .backward : .forward
        )
    }

    private func globalSelectionNavigationNotification(for event: NSEvent) -> Notification.Name? {
        guard store.activeListKeyboardNavigationDestination != nil else { return nil }
        let pressedModifiers = event.modifierFlags.intersection(
            NSEvent.ModifierFlags([.command, .control, .option, .shift])
        )
        guard pressedModifiers.isEmpty else { return nil }
        guard shouldUseGlobalSelectionNavigation() else { return nil }

        switch event.keyCode {
        case 125:
            return .footprintMoveSelectionDown
        case 126:
            return .footprintMoveSelectionUp
        default:
            return nil
        }
    }

    private func shouldUseGlobalSelectionNavigation() -> Bool {
        // Only the main window's lists own the arrows. Without this guard,
        // pressing up/down inside a sheet or the Settings window moved the
        // selection of the list hidden behind it.
        guard let window, NSApp.keyWindow === window else { return false }
        guard let firstResponder = window.firstResponder else { return true }
        // Arrow keys belong to the focused control, not list navigation,
        // for every control that consumes them itself — not just text views.
        if firstResponder is NSTextView { return false }
        var responderView: NSView? = firstResponder as? NSView
        if responderView == nil, let cellEditor = firstResponder as? NSText {
            responderView = cellEditor.delegate as? NSView
        }
        while let view = responderView {
            if view is NSDatePicker || view is NSPopUpButton || view is NSComboBox
                || view is NSSlider || view is NSStepper {
                return false
            }
            responderView = view.superview
        }
        return true
    }

    private func scheduleReminderRefresh() {
        guard grantRemindersEnabled else { return }
        reminderRefreshTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reminderCoordinator.refresh(applications: self.store.applications, language: self.store.language)
        }
        reminderRefreshTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }

    private func scheduleCalendarTaskReminderRefresh() {
        // Keep navigation and Dock badges in sync with a committed task edit.
        // The full refresh below remains debounced because it may also replace
        // scheduled user notifications.
        calendarTaskReminderCoordinator.refreshBadgeEntriesFromStore()
        calendarTaskReminderRefreshTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.calendarTaskReminderCoordinator.refresh(store: self.store, language: self.store.language)
        }
        calendarTaskReminderRefreshTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }

    private func activateUserNotificationsIfEnabled() {
        guard UserDefaults.standard.bool(forKey: AppRuntime.calendarTaskRemindersEnabledDefaultsKey),
              Bundle.main.bundleIdentifier?.nonEmpty != nil else {
            calendarTaskReminderCoordinator.disableNotifications()
            reminderCoordinator.disableNotifications()
            return
        }
        let center = UNUserNotificationCenter.current()
        notificationRouter.configure(store: store, center: center)
        migrateLegacyOwnedNotificationsIfNeeded()
        calendarTaskReminderCoordinator.configure(store: store, notificationCenter: center)
        if grantRemindersEnabled {
            reminderCoordinator.configure(store: store, notificationCenter: center)
        }
    }

    private func migrateLegacyOwnedNotificationsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: AppRuntime.legacyNotificationMigrationDefaultsKey) else { return }
        let ownedIDs = Set(
            (UserDefaults.standard.stringArray(forKey: AppRuntime.scheduledCalendarTaskReminderDefaultsKey) ?? [])
                + (UserDefaults.standard.stringArray(forKey: AppRuntime.scheduledReminderDefaultsKey) ?? [])
        )
        if !ownedIDs.isEmpty {
            let center = UNUserNotificationCenter.current()
            let identifiers = Array(ownedIDs)
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
        UserDefaults.standard.set(true, forKey: AppRuntime.legacyNotificationMigrationDefaultsKey)
    }

    private func applyVisualMode(_ mode: AppVisualMode?, to window: NSWindow? = nil) {
        UserDefaults.standard.set(mode?.rawValue, forKey: AppRuntime.visualModeDefaultsKey)
        let appearance: NSAppearance? = switch mode {
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        case .lightClean:
            NSAppearance(named: .aqua)
        case .darkClean, .darkNew:
            NSAppearance(named: .darkAqua)
        case nil:
            nil
        }

        if let window {
            window.appearance = appearance
        } else {
            NSApplication.shared.appearance = appearance
            self.window?.appearance = appearance
            self.settingsWindow?.appearance = appearance
            self.dataExchangeWindow?.appearance = appearance
        }
        AppAppearanceRegistry.updateSystemAppearancePreference()
    }

    private func refreshVisualMenuState() {
        let effectiveMode = effectiveVisualMode()
        lightCleanModeMenuItem?.state = effectiveMode == .lightClean ? .on : .off
        darkCleanModeMenuItem?.state = effectiveMode == .darkClean ? .on : .off
        darkNewModeMenuItem?.state = effectiveMode == .darkNew ? .on : .off
    }

    private func scheduleVisualModeTimer() {
        visualModeTimer?.invalidate()
        visualModeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyAutomaticVisualModeIfNeeded()
            }
        }
    }

    private func desiredAutomaticVisualMode(at date: Date = Date()) -> AppVisualMode {
        let calendar = Calendar.current
        let currentMinutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let lightMinutes = minutesSinceMidnight(store.lightModeStartsAt) ?? 6 * 60
        let darkMinutes = minutesSinceMidnight(store.darkModeStartsAt) ?? 20 * 60

        if lightMinutes == darkMinutes {
            return .lightClean
        }

        if lightMinutes < darkMinutes {
            return (currentMinutes >= lightMinutes && currentMinutes < darkMinutes) ? .lightClean : .darkNew
        }

        return (currentMinutes >= darkMinutes && currentMinutes < lightMinutes) ? .darkNew : .lightClean
    }

    private func applyAutomaticVisualModeIfNeeded() {
        guard store.visualMode == nil else { return }
        let desiredMode = desiredAutomaticVisualMode()
        applyVisualMode(desiredMode)
        refreshRootViewIfNeeded(for: desiredMode)
        refreshVisualMenuState()
    }

    private func minutesSinceMidnight(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              (0...23).contains(hours),
              (0...59).contains(minutes) else { return nil }
        return hours * 60 + minutes
    }

    private func refreshRootViewIfNeeded(for mode: AppVisualMode) {
        let raw = mode.rawValue
        guard raw != lastRenderedVisualModeRaw else { return }
        lastRenderedVisualModeRaw = raw
        // Replacing the hosting views here (the previous approach) destroyed
        // every @State in the app — scroll positions, expanded sections,
        // unsaved editor drafts — and the automatic day/night timer could
        // trigger that mid-edit. Palette colors resolve against the stored
        // visual mode at draw time, so a repaint is all that is needed.
        forceAppearanceRefresh(window)
        forceAppearanceRefresh(settingsWindow)
        forceAppearanceRefresh(dataExchangeWindow)
    }

    // Mode switches that stay within one system appearance (for example
    // darkClean -> darkNew) would not repaint on their own. Both
    // assignments land in the same runloop turn, so the intermediate
    // appearance never paints, but the change forces AppKit and SwiftUI
    // to re-resolve every dynamic color against the new stored mode.
    private func forceAppearanceRefresh(_ window: NSWindow?) {
        guard let window else { return }
        let target = window.appearance
        let oppositeName: NSAppearance.Name = target?.name == .darkAqua ? .aqua : .darkAqua
        window.appearance = NSAppearance(named: oppositeName)
        window.appearance = target
    }

    private func openSettingsWindow() {
        let mode = effectiveVisualMode()
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            applyVisualMode(mode, to: settingsWindow)
            return
        }

        let closeWindow: () -> Void = { [weak self] in
            self?.settingsWindow?.close()
        }
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1260, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = store.language.text("Preferences", "Inställningar")
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.minSize = NSSize(width: 920, height: 680)
        settingsWindow.setFrameAutosaveName("FootprintSettingsWindow")
        settingsWindow.delegate = self
        settingsWindow.center()
        settingsWindow.contentView = NSHostingView(
            rootView: SettingsWorkspaceView(store: store, dismiss: closeWindow)
        )
        applyVisualMode(mode, to: settingsWindow)
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.settingsWindow = settingsWindow
    }

    private func openDataExchangeWindow() {
        let mode = effectiveVisualMode()
        if let dataExchangeWindow {
            dataExchangeWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            applyVisualMode(mode, to: dataExchangeWindow)
            return
        }

        let closeWindow: () -> Void = { [weak self] in
            self?.dataExchangeWindow?.close()
        }
        let dataExchangeWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        dataExchangeWindow.title = store.language.text("Export", "Exportera")
        dataExchangeWindow.isReleasedWhenClosed = false
        dataExchangeWindow.minSize = NSSize(width: 720, height: 560)
        dataExchangeWindow.setFrameAutosaveName("FootprintDataExchangeWindow")
        dataExchangeWindow.delegate = self
        dataExchangeWindow.center()
        dataExchangeWindow.contentView = NSHostingView(
            rootView: DataExchangeExportCenterView(store: store, dismiss: closeWindow)
        )
        applyVisualMode(mode, to: dataExchangeWindow)
        dataExchangeWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.dataExchangeWindow = dataExchangeWindow
    }

    func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow,
           closingWindow == settingsWindow {
            settingsWindow = nil
        }
        if let closingWindow = notification.object as? NSWindow,
           closingWindow == dataExchangeWindow {
            dataExchangeWindow = nil
        }
    }

    private func effectiveVisualMode() -> AppVisualMode {
        store.visualMode ?? desiredAutomaticVisualMode()
    }

    private func refreshSelectionsMenuState() {
        for (filter, item) in incompleteDataMenuItems {
            item.state = store.personIncompleteDataFilter == filter ? .on : .off
        }
    }

    private func footerStatusBarMenuTitle() -> String {
        store.language.text("Show status bar", "Visa statusrad")
    }

    private func refreshFooterStatusBarMenuState() {
        footerStatusBarMenuItem?.title = footerStatusBarMenuTitle()
        footerStatusBarMenuItem?.state = store.showsFooterStatusBar ? .on : .off
    }

    private func refreshSalaryCalculatorMenu() {
        guard let submenu = salaryCalculatorSubmenu else { return }
        submenu.removeAllItems()

        let managers = store.managers.sorted {
            managerMenuTitle(for: $0).localizedStandardCompare(managerMenuTitle(for: $1)) == .orderedAscending
        }

        if managers.isEmpty {
            let item = NSMenuItem(title: store.language.text("No fund managers", "Inga medelsförvaltare"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
            return
        }

        for manager in managers {
            let item = NSMenuItem(title: managerMenuTitle(for: manager), action: #selector(openSalaryCalculator(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = manager.id
            submenu.addItem(item)
        }
    }

    private func managerMenuTitle(for manager: ManagerOption) -> String {
        store.language == .swedish ? manager.nameSv : (manager.nameEn.nonEmpty ?? manager.nameSv)
    }

}

@main
struct FootprintApp {
    @MainActor
    private static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
    }
}
