import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WorkspaceMountPolicy {
    /// Keep every workspace that the user has opened mounted. Reconstructing a
    /// complete workspace on every tab switch is substantially more expensive
    /// than keeping its existing SwiftUI tree alive.
    static let maximumMountedWorkspaceCount = Int.max
}

/// Keeps a tab selection transaction lightweight. The actual workspace is
/// mounted on the following main-loop turn, matching the scheduling boundary
/// used before the workspace observation refactor.
private struct DeferredWorkspaceShell<Content: View>: View {
    @State private var isContentReady = false
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Group {
            if isContentReady {
                content()
            } else {
                AppPalette.detailPanelSurface
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !isContentReady else { return }
            DispatchQueue.main.async {
                isContentReady = true
            }
        }
    }
}

struct TabPerformanceReporter: View {
    let isActive: Bool
    let onReady: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard isActive else { return }
                DispatchQueue.main.async {
                    onReady()
                }
            }
            .onChange(of: isActive) { _, active in
                guard active else { return }
                DispatchQueue.main.async {
                    onReady()
                }
            }
    }
}

extension View {
    @ViewBuilder
    func formKeyboardNavigable() -> some View {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            self.focusable(true, interactions: .activate)
        } else {
            self.focusable()
        }
        #else
        self
        #endif
    }
}

struct ContentView: View {
    private struct WorkspaceProjectionInputKey: Equatable {
        let isActive: Bool
        var newRecordTrigger = 0
    }

    private struct ApplicationProjectionInputKey: Equatable {
        let isActive: Bool
        let newRecordTrigger: Int
        let exportApplicationIDs: [String]?
        let preset: ApplicationListPreset?
        let pendingDirectSelectionID: String?
    }

    private struct PublicationProjectionInputKey: Equatable {
        let isActive: Bool
        let newRecordTrigger: Int
        let preset: PublicationListPreset?
    }

    let store: GrantDataStore
    @StateObject private var navigationProjection: DataStoreDomainProjection
    @StateObject private var clipboardPreviewProjection: ClipboardPreviewProjection
    @State private var selectedTab: AppTab = .calendar
    @State private var activatedTabs: Set<AppTab>
    @State private var activatedTabOrder: [AppTab]
    @State private var exportApplicationIDs: [String]?
    @State private var applicationListPreset: ApplicationListPreset?
    @State private var publicationListPreset: PublicationListPreset?
    @State private var newRecordTrigger = 0
    @State private var isCommandPalettePresented = false
    @State private var dataWorkspaceSection: DataWorkspaceSection = .quality
    @State private var pendingTabMeasurement: AppTab?
    @State private var pendingTabMeasurementStartedAt: CFAbsoluteTime?
    @State private var pendingTabMeasurementToken: UInt = 0
    @State private var hasRestoredInitialWorkspace = false
    @State private var pendingApplicationSelectionFromSalaryID: String?
    @State private var undoStatusPanelExpanded = false
    @State private var floatingDocumentPanelExpanded = false

    init(store: GrantDataStore) {
        self.store = store
        _navigationProjection = StateObject(
            wrappedValue: DataStoreDomainProjection(store: store, domain: .navigation)
        )
        _clipboardPreviewProjection = StateObject(
            wrappedValue: ClipboardPreviewProjection(store: store)
        )
        let initialTab = Self.initialSelectedTab(from: store)
        _selectedTab = State(initialValue: initialTab)
        _activatedTabs = State(initialValue: [initialTab])
        _activatedTabOrder = State(initialValue: [initialTab])
    }

    var body: some View {
        // ContentView intentionally does not observe the complete store. Keep
        // this narrow navigation boundary alive so route-only link clicks can
        // switch workspaces even when no content-domain value changed.
        let _ = navigationProjection.revision
        let language = store.language
        let root = AnyView(
            rootContent(language: language)
                .overlayPreferenceValue(FloatingStatisticsContentPreferenceKey.self) { configurations in
                    floatingWorkspaceUtilities(
                        language: language,
                        customDocument: activeFloatingDocumentContent(from: configurations)
                    )
                    .zIndex(2)
                }
                .autocompleteOverlayHost()
        )

        root
            .closeFloatingStatisticsOnExit(
                isEnabled: floatingDocumentPanelExpanded,
                close: closeFloatingDocumentPanel
            )
            .onEscapeKey(
                isEnabled: floatingDocumentPanelExpanded,
                perform: closeFloatingDocumentPanel
            )
            .onChange(of: store.route) { _, route in
                guard let route else { return }
                selectedTab = selectedTab(for: route)
            }
            .onChange(of: store.undoRevealRequest?.id) { _, _ in
                revealLastUndoRedoTarget()
            }
            .onAppear {
                activateTab(normalizedSelectedTab)
                store.startMainThreadLagMonitorIfNeeded()
                restoreInitialWorkspaceIfNeeded()
                DispatchQueue.main.async {
                    store.runDeferredLaunchMaintenanceIfNeeded()
                }
                updateWindowTitle()
            }
            .onChange(of: store.language) { _, _ in
                updateWindowTitle()
            }
            .onChange(of: selectedTab) { oldValue, tab in
                store.prioritizeUserInteraction()
                store.clearActiveListKeyboardNavigation()
                activateTab(tab)
                restoreInitialWorkspaceIfNeeded()
                updateWindowTitle()
                store.appendPerformanceDiagnostic(
                    "selected-tab \(oldValue.rawValue)->\(tab.rawValue)"
                )
                store.rememberLastSelectedTab(tab.rawValue)
                store.appendPerformanceDiagnostic(
                    String(
                        format: "tab-switch-start from=%@ to=%@",
                        oldValue.rawValue,
                        tab.rawValue
                    )
                )
                pendingTabMeasurement = tab
                pendingTabMeasurementStartedAt = CFAbsoluteTimeGetCurrent()
                pendingTabMeasurementToken &+= 1
                let token = pendingTabMeasurementToken
                scheduleTabSwitchPulse(for: tab, token: token, stage: "frame-1", delay: 0.016)
                scheduleTabSwitchPulse(for: tab, token: token, stage: "frame-8", delay: 0.132)
                scheduleTabSwitchPulse(for: tab, token: token, stage: "frame-36", delay: 0.600)
                scheduleTabSwitchPulse(for: tab, token: token, stage: "frame-90", delay: 1.500)
            }
            .onReceive(NotificationCenter.default.publisher(for: .footprintCreateNewRecord)) { _ in
                guard selectedTab != .statistics && selectedTab != .calendar && selectedTab != .congresses && selectedTab != .salary else { return }
                newRecordTrigger += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .footprintOpenSalaryCalculator)) { _ in
                selectedTab = .organizations
            }
            .onReceive(NotificationCenter.default.publisher(for: .footprintShowCommandPalette)) { _ in
                isCommandPalettePresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .footprintShowDataWorkspace)) { notification in
                if let raw = notification.object as? String,
                   let section = DataWorkspaceSection(rawValue: raw) {
                    dataWorkspaceSection = section
                }
                selectedTab = .dataQuality
            }
            .onChange(of: store.pendingCalendarOpenRequest) { _, request in
                guard request != nil else { return }
                selectedTab = .calendar
            }
            .onChange(of: store.pendingCalendarRevealToken) { _, token in
                guard token != nil else { return }
                selectedTab = .calendar
            }
            .onChange(of: store.pendingCalendarRevealRequest) { _, request in
                guard request != nil else { return }
                selectedTab = .calendar
            }
            .alert(
                store.deletionImpactWarning?.title ?? language.text("Delete linked object?", "Ta bort länkat objekt?"),
                isPresented: Binding(
                    get: { store.deletionImpactWarning != nil },
                    set: { isPresented in
                        if !isPresented {
                            store.cancelDeletionImpactWarning()
                        }
                    }
                ),
                actions: {
                    Button(language.text("Cancel", "Avbryt"), role: .cancel) {
                        store.cancelDeletionImpactWarning()
                    }
                    Button(store.deletionImpactWarning?.confirmTitle ?? language.text("Delete anyway", "Ta bort ändå"), role: .destructive) {
                        store.confirmDeletionImpactWarning()
                    }
                },
                message: {
                    if let warning = store.deletionImpactWarning {
                        Text(([warning.message] + warning.details.map { "• \($0)" }).joined(separator: "\n"))
                    }
                }
            )
            .modifier(StartupReportAlertModifier(store: store, language: language))
            .modifier(AppliedQuestionAlertModifier(store: store, language: language))
            .modifier(ProjectOngoingQuestionAlertModifier(store: store, language: language))
    }

    private func rootContent(language: AppLanguage) -> some View {
        ZStack {
            HStack(spacing: 0) {
                WorkspaceNavigationBar(
                    store: store,
                    selectedTab: $selectedTab,
                    language: language,
                    showSearch: { isCommandPalettePresented = true }
                )
                .zIndex(10)

                VStack(spacing: 0) {
                    ZStack {
                        ForEach(Self.retainedWorkspaceOrder, id: \.self) { tab in
                            if activatedTabs.contains(tab) {
                                DeferredWorkspaceShell {
                                    instrumentedTabContent(tab, isActive: normalizedSelectedTab == tab) {
                                        tabContent(for: tab)
                                            .environment(\.floatingStatisticsScopeID, tab.rawValue)
                                    }
                                }
                                .opacity(normalizedSelectedTab == tab ? 1 : 0)
                                .allowsHitTesting(normalizedSelectedTab == tab)
                                .accessibilityHidden(normalizedSelectedTab != tab)
                                .zIndex(normalizedSelectedTab == tab ? 1 : 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if store.showsFooterStatusBar {
                        Divider()
                        FooterStatusBar(store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(
                minWidth: AppResponsiveLayout.mainMinimumWidth,
                minHeight: AppResponsiveLayout.mainMinimumHeight
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [AppPalette.canvasTop, AppPalette.canvasBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .ignoresSafeArea(.container, edges: .top)
            if let preview = clipboardPreviewProjection.payload {
                ClipboardPreviewOverlay(text: preview.text)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(100)
            }
            if isCommandPalettePresented {
                CommandPaletteOverlay(
                    store: store,
                    selectedTab: normalizedSelectedTab,
                    dismiss: { isCommandPalettePresented = false },
                    selectTab: { selectedTab = $0 },
                    createNewRecord: createRecordFromPalette,
                    openManagerSalaryCalculator: openManagerSalaryCalculatorFromPalette
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
    }
    private func updateWindowTitle() {
        (NSApplication.shared.mainWindow ?? NSApplication.shared.keyWindow)?.title = store.language.appName
    }

    @ViewBuilder
    private func instrumentedTabContent<Content: View>(_ tab: AppTab, isActive: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .performanceScopeProbe(store: store, scope: "tab", identifier: tab.rawValue)
            .background(
                TabPerformanceReporter(isActive: isActive) {
                    reportTabReadyIfNeeded(for: tab)
                }
            )
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
            case .calendar:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .calendar,
                    inputKey: WorkspaceProjectionInputKey(isActive: normalizedSelectedTab == .calendar)
                ) { store in
                    CalendarWorkspaceView(
                        store: store,
                        isActive: normalizedSelectedTab == .calendar
                    )
                }
                .equatable()
            case .congresses:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .congresses,
                    inputKey: WorkspaceProjectionInputKey(isActive: normalizedSelectedTab == .congresses)
                ) { store in
                    CongressesWorkspaceView(
                        store: store,
                        isActive: normalizedSelectedTab == .congresses
                    )
                }
                .equatable()
            case .cv:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .cv,
                    inputKey: WorkspaceProjectionInputKey(isActive: normalizedSelectedTab == .cv)
                ) { store in
                    CVExportWorkspaceView(store: store)
                }
                .equatable()
            case .dissemination:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .cv,
                    inputKey: WorkspaceProjectionInputKey(
                        isActive: normalizedSelectedTab == .dissemination,
                        newRecordTrigger: newRecordTrigger
                    )
                ) { store in
                    DisseminationWorkspaceView(
                        store: store,
                        newRecordTrigger: newRecordTrigger,
                        isActive: normalizedSelectedTab == .dissemination
                    )
                }
                .equatable()
            case .projects:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .projects,
                    inputKey: WorkspaceProjectionInputKey(
                        isActive: normalizedSelectedTab == .projects,
                        newRecordTrigger: newRecordTrigger
                    )
                ) { store in
                    ProjectsWorkspaceView(
                        store: store,
                        newRecordTrigger: newRecordTrigger,
                        isActive: normalizedSelectedTab == .projects
                    )
                }
                .equatable()
            case .teaching:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .teaching,
                    inputKey: WorkspaceProjectionInputKey(
                        isActive: normalizedSelectedTab == .teaching,
                        newRecordTrigger: newRecordTrigger
                    )
                ) { store in
                    TeachingWorkspaceView(
                        store: store,
                        newRecordTrigger: newRecordTrigger,
                        isActive: normalizedSelectedTab == .teaching
                    )
                }
                .equatable()
            case .doctoralCandidates:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .teaching,
                    inputKey: WorkspaceProjectionInputKey(
                        isActive: normalizedSelectedTab == .doctoralCandidates,
                        newRecordTrigger: newRecordTrigger
                    )
                ) { store in
                    DoctoralCandidatesWorkspaceView(
                        store: store,
                        newRecordTrigger: newRecordTrigger,
                        isActive: normalizedSelectedTab == .doctoralCandidates
                    )
                }
                .equatable()
            case .expertAssignments:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .cv,
                    inputKey: WorkspaceProjectionInputKey(
                        isActive: normalizedSelectedTab == .expertAssignments,
                        newRecordTrigger: newRecordTrigger
                    )
                ) { store in
                    ExpertAssignmentsWorkspaceView(
                        store: store,
                        newRecordTrigger: newRecordTrigger,
                        isActive: normalizedSelectedTab == .expertAssignments
                    )
                }
                .equatable()
            case .applications:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .applications,
                    inputKey: ApplicationProjectionInputKey(
                        isActive: normalizedSelectedTab == .applications,
                        newRecordTrigger: newRecordTrigger,
                        exportApplicationIDs: exportApplicationIDs,
                        preset: applicationListPreset,
                        pendingDirectSelectionID: pendingApplicationSelectionFromSalaryID
                    )
                ) { store in
                    ApplicationsView(
                        store: store,
                        exportApplicationIDs: $exportApplicationIDs,
                        preset: $applicationListPreset,
                        pendingDirectSelectionID: $pendingApplicationSelectionFromSalaryID,
                        isActive: normalizedSelectedTab == .applications,
                        newRecordTrigger: newRecordTrigger
                    )
                }
                .equatable()
            case .salary:
                SalaryWorkspaceView(
                    store: store,
                    isActive: normalizedSelectedTab == .salary,
                    openApplicationAction: { applicationID in
                        openApplicationFromSalary(applicationID: applicationID)
                    }
                )
            case .statistics:
                StatisticsView(store: store, isActive: normalizedSelectedTab == .statistics)
            case .dataQuality:
                DataMaintenanceWorkspaceView(
                    store: store,
                    section: $dataWorkspaceSection,
                    dismiss: {},
                    isActive: normalizedSelectedTab == .dataQuality
                )
            case .organizations:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .organizations,
                    inputKey: WorkspaceProjectionInputKey(
                        isActive: normalizedSelectedTab == .organizations,
                        newRecordTrigger: newRecordTrigger
                    )
                ) { store in
                    OrganizationsDirectoryView(
                        store: store,
                        newRecordTrigger: newRecordTrigger,
                        isActive: normalizedSelectedTab == .organizations
                    )
                }
                .equatable()
            case .coauthors:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .publications,
                    inputKey: WorkspaceProjectionInputKey(
                        isActive: normalizedSelectedTab == .coauthors,
                        newRecordTrigger: newRecordTrigger
                    )
                ) { store in
                    PublicationAuthorsView(
                        store: store,
                        newRecordTrigger: newRecordTrigger,
                        isActive: normalizedSelectedTab == .coauthors
                    )
                }
                .equatable()
            case .journals:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .publications,
                    inputKey: WorkspaceProjectionInputKey(
                        isActive: normalizedSelectedTab == .journals,
                        newRecordTrigger: newRecordTrigger
                    )
                ) { store in
                    PublicationJournalsView(
                        store: store,
                        newRecordTrigger: newRecordTrigger,
                        isActive: normalizedSelectedTab == .journals
                    )
                }
                .equatable()
            case .publications:
                DataStoreDomainProjectionHost(
                    store: store,
                    domain: .publications,
                    inputKey: PublicationProjectionInputKey(
                        isActive: normalizedSelectedTab == .publications,
                        newRecordTrigger: newRecordTrigger,
                        preset: publicationListPreset
                    )
                ) { store in
                    PublicationsWorkspaceView(
                        store: store,
                        preset: $publicationListPreset,
                        newRecordTrigger: newRecordTrigger,
                        isActive: normalizedSelectedTab == .publications
                    )
                }
                .equatable()
        }
    }

    private func reportTabReadyIfNeeded(for tab: AppTab) {
        guard pendingTabMeasurement == tab,
              let pendingTabMeasurementStartedAt else { return }
        let duration = (CFAbsoluteTimeGetCurrent() - pendingTabMeasurementStartedAt) * 1000
        store.appendPerformanceDiagnostic(
            String(
                format: "tab-switch tab=%@ ready_ms=%.2f",
                tab.rawValue,
                duration
            )
        )
        pendingTabMeasurement = nil
        self.pendingTabMeasurementStartedAt = nil
    }

    private func scheduleTabSwitchPulse(for tab: AppTab, token: UInt, stage: String, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard pendingTabMeasurementToken == token,
                  pendingTabMeasurement == tab,
                  let pendingTabMeasurementStartedAt else { return }
            let elapsed = (CFAbsoluteTimeGetCurrent() - pendingTabMeasurementStartedAt) * 1000
            store.appendPerformanceDiagnostic(
                String(
                    format: "tab-switch-pulse tab=%@ stage=%@ elapsed_ms=%.2f",
                    tab.rawValue,
                    stage,
                    elapsed
                )
            )
        }
    }

    private func activateTab(_ tab: AppTab) {
        activatedTabs.insert(tab)
        activatedTabOrder.removeAll { $0 == tab }
        activatedTabOrder.append(tab)

        // Retain visited workspaces so tab switches can reuse their existing
        // SwiftUI trees instead of reconstructing complete editors and lists.
        let maxRetainedTabs = WorkspaceMountPolicy.maximumMountedWorkspaceCount
        guard activatedTabs.count > maxRetainedTabs else { return }

        var retained: Set<AppTab> = [tab]
        for candidate in activatedTabOrder.reversed() {
            retained.insert(candidate)
            if retained.count >= maxRetainedTabs {
                break
            }
        }

        activatedTabs = activatedTabs.intersection(retained)
        activatedTabOrder = activatedTabOrder.filter { retained.contains($0) }
    }

    private func applyGrantPreset(_ preset: ApplicationListPreset) {
        applicationListPreset = preset
        selectedTab = .applications
    }

    private func applyPublicationPreset(_ preset: PublicationListPreset) {
        publicationListPreset = preset
        selectedTab = .publications
    }

    private func createRecordFromPalette(for tab: AppTab) {
        switch tab {
        case .applications:
            let newID = store.addApplication()
            selectedTab = .applications
            store.route = AppRoute(recordID: newID, destination: .applications)
        case .cv:
            selectedTab = .cv
        case .dissemination:
            let newID = store.addCVMediaAppearance()
            selectedTab = .dissemination
            store.route = AppRoute(recordID: "mediaAppearance:\(newID)", destination: .cv)
        case .projects:
            let newID = store.addProject()
            selectedTab = .projects
            store.route = AppRoute(recordID: newID, destination: .projects)
        case .teaching:
            let newID = store.addTeachingCourse()
            selectedTab = .teaching
            store.route = AppRoute(recordID: newID, destination: .teaching)
        case .doctoralCandidates:
            let newID = store.addDoctoralCandidate()
            selectedTab = .doctoralCandidates
            store.route = AppRoute(recordID: newID, destination: .doctoralCandidates)
        case .expertAssignments:
            let newID = store.addCVReviewEntry()
            selectedTab = .expertAssignments
            store.route = AppRoute(recordID: "review:\(newID)", destination: .expertAssignments)
        case .organizations:
            let newID = store.addOrganization()
            selectedTab = .organizations
            store.route = AppRoute(recordID: newID, destination: .organizations)
        case .coauthors:
            let newID = store.addPublicationAuthor()
            selectedTab = .coauthors
            store.route = AppRoute(recordID: newID, destination: .people)
        case .journals:
            let newID = store.addPublicationJournal()
            selectedTab = .journals
            store.route = AppRoute(recordID: newID, destination: .journals)
        case .publications:
            let newID = store.addPublication()
            selectedTab = .publications
            store.route = AppRoute(recordID: newID, destination: .publications)
        case .calendar, .congresses, .salary, .statistics, .dataQuality:
            selectedTab = tab
        }
    }

    private func openManagerSalaryCalculatorFromPalette(id: String) {
        selectedTab = .organizations
        NotificationCenter.default.post(name: .footprintOpenSalaryCalculator, object: id)
    }

    private func openApplicationFromSalary(applicationID: String) {
        store.appendPerformanceDiagnostic("salary-open-application-start id=\(applicationID)")
        pendingApplicationSelectionFromSalaryID = applicationID
        store.appendPerformanceDiagnostic("salary-open-application-pending id=\(applicationID)")
        selectedTab = .applications
    }

    private static func initialSelectedTab(from store: GrantDataStore) -> AppTab {
        // Developer convenience: FOOTPRINT_INITIAL_TAB forces the starting tab,
        // used by headless screenshot verification.
        if let override = ProcessInfo.processInfo.environment["FOOTPRINT_INITIAL_TAB"],
           let tab = AppTab(rawValue: override) {
            return tab
        }
        guard let rawTab = store.lastSelectedTabRaw?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
            return .calendar
        }
        guard let savedTab = AppTab(rawValue: rawTab) else { return .calendar }
        return savedTab
    }

    private var normalizedSelectedTab: AppTab {
        selectedTab
    }

    private var shouldShowUndoStatusPanel: Bool {
        _ = store.undoStateGeneration
        return store.undoManager.canUndo
            || store.undoManager.canRedo
            || store.undoRevealRequest != nil
    }

    private var floatingUtilitiesBottomPadding: CGFloat {
        store.showsFooterStatusBar ? 44 : 18
    }

    private func floatingStatisticsPanelWidth(for availableWidth: CGFloat) -> CGFloat {
        let availableAfterSidebar = max(420, availableWidth - 360)
        return min(max(availableWidth * 0.58, 672), availableAfterSidebar)
    }

    private func floatingStatisticsPanelHeight(for availableHeight: CGFloat) -> CGFloat {
        let maximumVisibleHeight = max(0, availableHeight - floatingUtilitiesBottomPadding - 18)
        return max(280, maximumVisibleHeight)
    }

    private func activeFloatingDocumentContent(
        from configurations: [FloatingStatisticsContentConfiguration]
    ) -> FloatingStatisticsContentConfiguration? {
        for configuration in configurations.reversed() {
            if configuration.kind == .document,
               configuration.scopeID == normalizedSelectedTab.rawValue,
               configuration.isAvailable {
                return configuration
            }
        }
        return nil
    }

    private func floatingWorkspaceUtilities(
        language: AppLanguage,
        customDocument: FloatingStatisticsContentConfiguration?
    ) -> some View {
        GeometryReader { proxy in
            let statisticsPanelWidth = floatingStatisticsPanelWidth(for: proxy.size.width)
            let statisticsPanelHeight = floatingStatisticsPanelHeight(for: proxy.size.height)

            ZStack(alignment: .bottomTrailing) {
                if floatingDocumentPanelExpanded, let customDocument {
                    FloatingDocumentCurtainPanel(
                        store: store,
                        customDocument: customDocument,
                        close: closeFloatingDocumentPanel
                    )
                    .frame(width: statisticsPanelWidth, height: statisticsPanelHeight, alignment: .topLeading)
                    .padding(.trailing, 18)
                    .padding(.bottom, floatingUtilitiesBottomPadding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    if shouldShowUndoStatusPanel {
                        UndoStatusPanel(
                            store: store,
                            isExpanded: $undoStatusPanelExpanded,
                            revealLastChange: revealLastUndoRedoTarget
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if customDocument != nil {
                        FloatingDocumentToggleButton(
                            language: language,
                            isExpanded: $floatingDocumentPanelExpanded
                        )
                    }
                }
                .padding(.trailing, 18)
                .padding(.bottom, floatingUtilitiesBottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: floatingDocumentPanelExpanded)
            .animation(.easeInOut(duration: 0.16), value: shouldShowUndoStatusPanel)
            .onChange(of: customDocument == nil) { _, isUnavailable in
                if isUnavailable {
                    floatingDocumentPanelExpanded = false
                }
            }
        }
    }

    private func closeFloatingDocumentPanel() {
        guard floatingDocumentPanelExpanded else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            floatingDocumentPanelExpanded = false
        }
    }


    private func revealLastUndoRedoTarget() {
        guard let request = store.undoRevealRequest else { return }
        switch request.target.destination {
        case .route(let route):
            selectedTab = selectedTab(for: route)
            store.route = route
        case .calendar(let dayString, let eventSource):
            selectedTab = .calendar
            if let date = DateParsers.isoDay.date(from: dayString) {
                store.revealCalendarWorkspace(on: date, eventSource: eventSource)
            } else {
                store.revealCalendarWorkspace()
            }
        }
    }

    private static let retainedWorkspaceOrder: [AppTab] = [
        .calendar,
        .congresses,
        .cv,
        .dissemination,
        .expertAssignments,
        .projects,
        .teaching,
        .doctoralCandidates,
        .applications,
        .salary,
        .statistics,
        .dataQuality,
        .organizations,
        .coauthors,
        .journals,
        .publications
    ]

    private func restoreInitialWorkspaceIfNeeded() {
        guard !hasRestoredInitialWorkspace else { return }
        hasRestoredInitialWorkspace = true

        let initialTab = Self.initialSelectedTab(from: store)
        if selectedTab != initialTab {
            selectedTab = initialTab
        }

        guard store.route == nil,
              let destination = initialRouteDestination(for: initialTab),
              let recordID = store.lastSelectedRecordID(for: destination)
        else {
            return
        }

        store.route = AppRoute(recordID: recordID, destination: destination)
    }

    private func initialRouteDestination(for tab: AppTab) -> AppRoute.Destination? {
        switch tab {
        case .applications:
            return .applications
        case .projects:
            return .projects
        case .teaching:
            return .teaching
        case .doctoralCandidates:
            return nil
        case .organizations:
            return .organizations
        case .coauthors:
            return .people
        case .journals:
            return .journals
        case .publications:
            return .publications
        case .expertAssignments:
            return .expertAssignments
        case .calendar, .congresses, .cv, .dissemination, .salary, .statistics, .dataQuality:
            return nil
        }
    }

    private func selectedTab(for route: AppRoute) -> AppTab {
        appTabForRoute(route)
    }
}

/// CV-area routes use prefixed record tokens that land in other tabs;
/// extracted from the shell view so the mapping is unit-testable.
func appTabForRoute(_ route: AppRoute) -> AppTab {
    switch route.destination {
    case .applications:
        return .applications
    case .congresses:
        return .congresses
    case .cv:
        if route.recordID.hasPrefix("review:") {
            return .expertAssignments
        }
        if route.recordID.hasPrefix("conferenceContribution:") {
            return .congresses
        }
        if route.recordID.hasPrefix("organizationCongress:") {
            return .congresses
        }
        if route.recordID.hasPrefix("mediaAppearance:") {
            return .dissemination
        }
        if route.recordID.hasPrefix("otherPublication:") {
            return .dissemination
        }
        return .cv
    case .expertAssignments:
        return .expertAssignments
    case .publications:
        return .publications
    case .projects:
        return .projects
    case .teaching:
        return .teaching
    case .doctoralCandidates:
        return .doctoralCandidates
    case .organizations:
        return .organizations
    case .people:
        return .coauthors
    case .journals:
        return .journals
    }
}

private struct UndoStatusPanel: View {
    @ObservedObject var store: GrantDataStore
    @Binding var isExpanded: Bool
    let revealLastChange: () -> Void

    private var language: AppLanguage { store.language }

    private var undoTitle: String {
        let action = store.undoManager.undoActionName.trimmedOrNil
        return action ?? language.text("latest change", "senaste ändringen")
    }

    private var redoTitle: String {
        let action = store.undoManager.redoActionName.trimmedOrNil
        return action ?? language.text("latest undone change", "senast ångrade ändring")
    }

    var body: some View {
        let _ = store.undoStateGeneration
        VStack(alignment: .trailing, spacing: 8) {
            if isExpanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(collapsedTitle)
                        .appTypography(.tableHeader)
                        .lineLimit(1)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(AppPalette.appText)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppPalette.cardSurface.opacity(0.96))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(AppPalette.subtleBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .help(language.text("Show undo status", "Visa ångra-status"))
        }
    }

    private var collapsedTitle: String {
        if store.undoManager.canUndo {
            return language.text("Undo available", "Ångra finns")
        }
        if store.undoManager.canRedo {
            return language.text("Redo available", "Gör om finns")
        }
        return language.text("Last change", "Senaste ändring")
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(AppPalette.linkAction)
                Text(language.text("Undo status", "Ångra-status"))
                    .appTypography(.panelTitle)
                Spacer()
            }

            undoRedoRow(
                title: language.text("Next undo", "Nästa ångra"),
                value: undoTitle,
                systemImage: "arrow.uturn.backward",
                isEnabled: store.undoManager.canUndo
            ) {
                store.undoManager.undo()
            }

            undoRedoRow(
                title: language.text("Next redo", "Nästa gör om"),
                value: redoTitle,
                systemImage: "arrow.uturn.forward",
                isEnabled: store.undoManager.canRedo
            ) {
                store.undoManager.redo()
            }

            if let request = store.undoRevealRequest {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(request.isRedo ? language.text("Last redone", "Senast gjord om") : language.text("Last undone", "Senast ångrad"))
                            .appTypography(.fieldLabel)
                        Text(request.actionName)
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        revealLastChange()
                    } label: {
                        Label(language.text("Show record", "Visa post"), systemImage: "arrow.forward.circle")
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppPalette.cardSurface.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 8)
    }

    private func undoRedoRow(
        title: String,
        value: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appTypography(.fieldLabel)
                Text(value)
                    .appTypography(.secondary)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: action) {
                Image(systemName: systemImage)
            }
            .controlSize(.small)
            .disabled(!isEnabled)
            .help(title)
            .accessibilityLabel(title)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppPalette.secondaryCardSurface)
        )
    }
}

private struct FloatingDocumentToggleButton: View {
    let language: AppLanguage
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "doc.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppPalette.appText)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(AppPalette.cardSurface.opacity(0.96))
                )
                .overlay(
                    Circle()
                        .stroke(isExpanded ? AppPalette.linkAction.opacity(0.72) : AppPalette.subtleBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .help(isExpanded ? language.text("Hide document", "Dölj dokument") : language.text("Show document", "Visa dokument"))
        .accessibilityLabel(Text(language.text("Document", "Dokument")))
    }
}

private struct FloatingDocumentCurtainPanel: View {
    @ObservedObject var store: GrantDataStore
    let customDocument: FloatingStatisticsContentConfiguration
    let close: () -> Void

    private var language: AppLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppPalette.linkAction)

                Text(customDocument.title)
                    .appTypography(.panelTitle)

                Spacer(minLength: 12)

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(AppPalette.cardSurface.opacity(0.96))
                        )
                        .overlay(
                            Circle()
                                .stroke(AppPalette.subtleBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(language.text("Hide document", "Dölj dokument"))
                .accessibilityLabel(language.text("Hide document", "Dölj dokument"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppPalette.sidebarPanelSurface)

            Divider()

            // The document content hosts its own scrolling web view; no outer
            // ScrollView, unlike the statistics curtain.
            customDocument.content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppPalette.sidebarPanelSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 24, x: 0, y: 10)
    }
}

private struct FloatingStatisticsExitCommandModifier: ViewModifier {
    let isEnabled: Bool
    let close: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.onExitCommand(perform: close)
        } else {
            content
        }
    }
}

private extension View {
    func closeFloatingStatisticsOnExit(isEnabled: Bool, close: @escaping () -> Void) -> some View {
        modifier(FloatingStatisticsExitCommandModifier(isEnabled: isEnabled, close: close))
    }
}

enum ApplicationListPreset: Equatable {
    case all
    case granted
    case pending
}

enum PublicationListPreset: Equatable {
    case all
    case originalPublished
    case originalSubmitted
    case originalPublishedIndependentLeadAfterPhD
    case originalSubmittedIndependentLeadAfterPhD
}

private struct CommandPaletteItem: Identifiable {
    enum Kind: Int {
        case action
        case section
        case record
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let symbolName: String
    let searchTerms: [String]
    let action: @MainActor () -> Void
}

@MainActor
private enum WorkspaceSearchModel {
    static func buildItems(
        store: GrantDataStore,
        language: AppLanguage,
        selectTab: @MainActor @escaping (AppTab) -> Void,
        createNewRecord: @MainActor @escaping (AppTab) -> Void,
        openManagerSalaryCalculator: @MainActor @escaping (String) -> Void
    ) -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        func sectionItem(id: String, title: String, subtitle: String, symbol: String, tab: AppTab, extraTerms: [String] = []) {
            items.append(
                CommandPaletteItem(
                    id: "section-\(id)",
                    kind: .section,
                    title: title,
                    subtitle: subtitle,
                    symbolName: symbol,
                    searchTerms: [title, subtitle] + extraTerms,
                    action: { selectTab(tab) }
                )
            )
        }

        func actionItem(id: String, title: String, subtitle: String, symbol: String, terms: [String] = [], action: @MainActor @escaping () -> Void) {
            items.append(
                CommandPaletteItem(
                    id: "action-\(id)",
                    kind: .action,
                    title: title,
                    subtitle: subtitle,
                    symbolName: symbol,
                    searchTerms: [title, subtitle] + terms,
                    action: action
                )
            )
        }

        sectionItem(
            id: "calendar",
            title: language.text("Calendar", "Kalender"),
            subtitle: language.text("Compact event list by month", "Kompakt händelselista per månad"),
            symbol: AppTab.calendar.symbolName,
            tab: .calendar
        )
        sectionItem(
            id: "congresses",
            title: language.text("Congresses", "Kongresser"),
            subtitle: language.text("Congress list and planning map", "Kongresslista och planeringskarta"),
            symbol: AppTab.congresses.symbolName,
            tab: .congresses,
            extraTerms: [
                language.text("Map", "Karta"),
                language.text("Plan", "Planera")
            ]
        )
        sectionItem(
            id: "projects",
            title: language.text("Projects", "Projekt"),
            subtitle: language.text("Projects and timelines", "Projekt och tidslinjer"),
            symbol: AppTab.projects.symbolName,
            tab: .projects
        )
        sectionItem(
            id: "researchers",
            title: language.text("Researchers", "Forskare"),
            subtitle: language.text("People and affiliations", "Forskare och affilieringar"),
            symbol: AppTab.coauthors.symbolName,
            tab: .coauthors,
            extraTerms: [language.text("People", "Personer")]
        )
        sectionItem(
            id: "organizations",
            title: language.text("Organizations", "Organisationer"),
            subtitle: language.text("Funders, employers and fund managers", "Anslagsgivare, arbetsgivare och medelsförvaltare"),
            symbol: AppTab.organizations.symbolName,
            tab: .organizations
        )
        sectionItem(
            id: "cv",
            title: "CV",
            subtitle: language.text("Preview and export CVs and publication lists", "Förhandsvisa och exportera CV och publikationslistor"),
            symbol: AppTab.cv.symbolName,
            tab: .cv
        )
        sectionItem(
            id: "data-quality",
            title: language.text("Data quality", "Datakvalitet"),
            subtitle: language.text("Review and correct data by category", "Granska och korrigera data per kategori"),
            symbol: AppTab.dataQuality.symbolName,
            tab: .dataQuality,
            extraTerms: [
                language.text("Data maintenance", "Datavård"),
                language.text("Missing fields", "Saknade fält"),
                language.text("Duplicates", "Dubletter"),
                language.text("Archive", "Arkiv"),
            ]
        )
        sectionItem(
            id: "expert-assignments",
            title: language.text("Expert assignments", "Sakkunniguppdrag"),
            subtitle: language.text("Reviews and expert work", "Reviews och sakkunnigarbete"),
            symbol: AppTab.expertAssignments.symbolName,
            tab: .expertAssignments
        )
        sectionItem(
            id: "teaching",
            title: language.text("Teaching", "Undervisning"),
            subtitle: language.text("Courses and teaching assignments", "Kurser och undervisningsuppdrag"),
            symbol: AppTab.teaching.symbolName,
            tab: .teaching
        )
        sectionItem(
            id: "doctoral-candidates",
            title: language.text("Doctoral candidates", "Doktorander"),
            subtitle: language.text("Supervision, milestones and timeline", "Handledning, milstolpar och tidslinje"),
            symbol: AppTab.doctoralCandidates.symbolName,
            tab: .doctoralCandidates
        )
        sectionItem(
            id: "salary",
            title: language.text("Salary planning", "Löneplanering"),
            subtitle: language.text("Salary plan", "Löneplan"),
            symbol: AppTab.salary.symbolName,
            tab: .salary
        )
        sectionItem(
            id: "applications",
            title: language.text("Calls and grants", "Utlysningar och anslag"),
            subtitle: language.text("Calls, applications and grants", "Utlysningar, ansökningar och anslag"),
            symbol: AppTab.applications.symbolName,
            tab: .applications
        )
        sectionItem(
            id: "journals",
            title: language.text("Journals", "Tidskrifter"),
            subtitle: language.text("Journal records", "Tidskrifter"),
            symbol: AppTab.journals.symbolName,
            tab: .journals
        )
        sectionItem(
            id: "publications",
            title: language.text("Publications", "Publikationer"),
            subtitle: language.text("Publication records", "Publikationer"),
            symbol: AppTab.publications.symbolName,
            tab: .publications
        )
        sectionItem(
            id: "statistics",
            title: language.text("Statistics", "Statistik"),
            subtitle: language.text("Overview and metrics", "Översikt och statistik"),
            symbol: AppTab.statistics.symbolName,
            tab: .statistics
        )

        actionItem(
            id: "new-cv-media",
            title: language.text("New media appearance", "Ny medverkan i media"),
            subtitle: language.text("Create and open a new media appearance", "Skapa och öppna ny medverkan i media"),
            symbol: "plus.rectangle.on.rectangle"
        ) {
            let newID = store.addCVMediaAppearance()
            selectTab(.cv)
            store.route = AppRoute(recordID: "mediaAppearance:\(newID)", destination: .cv)
        }
        actionItem(
            id: "new-cv-review",
            title: language.text("New expert assignment", "Nytt sakkunniguppdrag"),
            subtitle: language.text("Create and open a new review entry", "Skapa och öppna ett nytt sakkunniguppdrag"),
            symbol: "plus.rectangle.on.rectangle"
        ) {
            createNewRecord(.expertAssignments)
        }
        actionItem(
            id: "new-application",
            title: language.text("New call", "Ny utlysning"),
            subtitle: language.text("Create and open a new call record", "Skapa och öppna en ny post för en utlysning"),
            symbol: "plus.rectangle.on.rectangle",
            terms: [language.text("Create", "Skapa"), language.text("Grant", "Anslag")]
        ) {
            createNewRecord(.applications)
        }
        actionItem(
            id: "new-project",
            title: language.text("New project", "Nytt projekt"),
            subtitle: language.text("Create and open a new project", "Skapa och öppna ett nytt projekt"),
            symbol: "plus.rectangle.on.folder"
        ) {
            createNewRecord(.projects)
        }
        actionItem(
            id: "new-researcher",
            title: language.text("New researcher", "Ny forskare"),
            subtitle: language.text("Create and open a new researcher", "Skapa och öppna en ny forskare"),
            symbol: "person.crop.circle.badge.plus"
        ) {
            createNewRecord(.coauthors)
        }
        actionItem(
            id: "new-organization",
            title: language.text("New organization", "Ny organisation"),
            subtitle: language.text("Create and open a new organization", "Skapa och öppna en ny organisation"),
            symbol: "plus.rectangle.on.rectangle.angled"
        ) {
            createNewRecord(.organizations)
        }
        actionItem(
            id: "new-course",
            title: language.text("New course", "Ny kurs"),
            subtitle: language.text("Create and open a new teaching course", "Skapa och öppna en ny kurs"),
            symbol: "plus.rectangle.on.rectangle.badge.person.crop"
        ) {
            createNewRecord(.teaching)
        }
        actionItem(
            id: "new-doctoral-candidate",
            title: language.text("New doctoral candidate", "Ny doktorand"),
            subtitle: language.text("Create and open a new doctoral candidate", "Skapa och öppna en ny doktorand"),
            symbol: "person.crop.circle.badge.plus"
        ) {
            createNewRecord(.doctoralCandidates)
        }
        actionItem(
            id: "new-journal",
            title: language.text("New journal", "Ny tidskrift"),
            subtitle: language.text("Create and open a new journal", "Skapa och öppna en ny tidskrift"),
            symbol: "plus.rectangle.on.book.closed"
        ) {
            createNewRecord(.journals)
        }
        actionItem(
            id: "new-publication",
            title: language.text("New publication", "Ny publikation"),
            subtitle: language.text("Create and open a new publication", "Skapa och öppna en ny publikation"),
            symbol: "plus.rectangle.on.text.rectangle"
        ) {
            createNewRecord(.publications)
        }

        for manager in store.managers {
            let title = manager.displayName(for: language)
            let alternate = manager.alternateDisplayName(for: language)
            items.append(
                CommandPaletteItem(
                    id: "manager-salary-\(manager.id)",
                    kind: .action,
                    title: "\(language.text("Salary calculator", "Lönekalkyl")): \(title)",
                    subtitle: alternate ?? language.text("Open salary calculator", "Öppna lönekalkyl"),
                    symbolName: "function",
                    searchTerms: [title, alternate ?? "", language.text("Salary calculator", "Lönekalkyl"), language.text("Fund manager", "Medelsförvaltare")],
                    action: { openManagerSalaryCalculator(manager.id) }
                )
            )
        }

        items.append(contentsOf: store.projects.map { project in
            let title = project.displayName(for: language)
            return CommandPaletteItem(
                id: "project-\(project.id)",
                kind: .record,
                title: title,
                subtitle: project.collaboratorNames.prefix(3).joined(separator: ", "),
                symbolName: "folder",
                searchTerms: [title, project.nameSv, project.nameEn, project.collaboratorNames.joined(separator: " ")],
                action: {
                    selectTab(.projects)
                    store.route = AppRoute(recordID: project.id, destination: .projects)
                }
            )
        })

        items += store.applications.map { application in
            let title = store.displayTitle(for: application, language: language)
            let organization = store.organizationLabel(for: application, language: language)
            let project = store.projectLabel(for: application, language: language) ?? ""
            let status = language.localizedStatus(application.resultLabel)
            return CommandPaletteItem(
                id: "application-\(application.id)",
                kind: .record,
                title: title,
                subtitle: [organization, project.nonEmpty, status.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                symbolName: "doc.text",
                searchTerms: [
                    title,
                    organization,
                    project,
                    application.applicationTitle ?? "",
                    store.localizedGrantName(for: application, language: language),
                    application.appliedCaseNumber ?? "",
                    application.receivedProjectNumber ?? ""
                ],
                action: {
                    selectTab(.applications)
                    store.openRoute(for: application)
                }
            )
        }

        items.append(contentsOf: store.organizations.map { organization in
            let title = organization.displayName(for: language)
            let subtitle = organization.roleSummaryText(language: language)
            return CommandPaletteItem(
                id: "organization-\(organization.id)",
                kind: .record,
                title: title,
                subtitle: subtitle,
                symbolName: "building.columns",
                searchTerms: [title, organization.nameSv, organization.nameEn, organization.category ?? "", subtitle],
                action: {
                    selectTab(.organizations)
                    store.route = AppRoute(recordID: organization.id, destination: .organizations)
                }
            )
        })

        items.append(contentsOf: store.coauthors.map { author in
            let title = author.displayName
            let subtitle = [author.primaryAffiliation?.organization.nonEmpty, author.title.nonEmpty].compactMap { $0 }.joined(separator: " · ")
            return CommandPaletteItem(
                id: "author-\(author.id)",
                kind: .record,
                title: title,
                subtitle: subtitle,
                symbolName: "person",
                searchTerms: [title, author.name, author.firstName, author.lastName, author.primaryAffiliation?.organization ?? "", author.orcid],
                action: {
                    selectTab(.coauthors)
                    store.openRoute(for: author)
                }
            )
        })

        items.append(contentsOf: store.journals.map { journal in
            CommandPaletteItem(
                id: "journal-\(journal.id)",
                kind: .record,
                title: journal.name,
                subtitle: [journal.publisher.nonEmpty, journal.issn.nonEmpty, journal.eissn.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                symbolName: "book.closed",
                searchTerms: [journal.name, journal.abbreviatedName, journal.publisher, journal.issn, journal.eissn, journal.country],
                action: {
                    selectTab(.journals)
                    store.openRoute(for: journal)
                }
            )
        })

        items.append(contentsOf: store.publications.map { publication in
            let status = PublicationStatus.fromStored(publication.statusLabel).displayName(language: language)
            return CommandPaletteItem(
                id: "publication-\(publication.id)",
                kind: .record,
                title: publication.title.nonEmpty ?? publication.number,
                subtitle: [publication.journal.nonEmpty, status.nonEmpty, publication.projectName.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                symbolName: "text.book.closed",
                searchTerms: [publication.title, publication.journal, publication.projectName ?? "", publication.number, publication.authorNames.joined(separator: " ")],
                action: {
                    selectTab(.publications)
                    store.openRoute(for: publication)
                }
            )
        })

        return items
    }

    static func results(for query: String, items: [CommandPaletteItem], defaultLimit: Int = 12, filteredLimit: Int = 24) -> [CommandPaletteItem] {
        let searchQuery = SearchFilterQuery(raw: query)
        guard !searchQuery.isEmpty else {
            return Array(items.prefix(defaultLimit))
        }

        return items
            .compactMap { item -> (CommandPaletteItem, Int)? in
                guard let score = score(item: item, query: searchQuery) else { return nil }
                return (item, score)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.0.kind.rawValue != $1.0.kind.rawValue {
                    return $0.0.kind.rawValue < $1.0.kind.rawValue
                }
                return $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending
            }
            .map(\.0)
            .prefix(filteredLimit)
            .map { $0 }
    }

    private static func score(item: CommandPaletteItem, query: SearchFilterQuery) -> Int? {
        let title = normalizedText(item.title)
        let subtitle = normalizedText(item.subtitle)
        let haystacks = ([title, subtitle] + item.searchTerms.map(normalizedText))
            .filter { !$0.isEmpty }
        guard !haystacks.isEmpty else { return nil }

        guard query.excludedTerms.allSatisfy({ token in
            haystacks.allSatisfy { !$0.contains(token) }
        }) else {
            return nil
        }

        var score = 0
        for token in query.includedTerms {
            guard let best = haystacks.compactMap({ scoreToken(token, in: $0) }).max() else {
                return nil
            }
            score += best
        }

        score += max(0, 30 - item.title.count / 3)
        return score
    }

    private static func scoreToken(_ token: String, in haystack: String) -> Int? {
        guard let range = haystack.range(of: token) else { return nil }
        if range.lowerBound == haystack.startIndex {
            return 180
        }
        let previous = haystack[haystack.index(before: range.lowerBound)]
        if previous == " " {
            return 140
        }
        return 100
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct CommandPaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    let onMoveSelection: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = PaletteSearchField()
        field.delegate = context.coordinator
        field.placeholderString = "Search"
        field.font = appNSFont(.body)
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.onMoveSelection = onMoveSelection
        field.onSubmit = onSubmit
        field.onCancel = onCancel
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let field = nsView as? PaletteSearchField {
            field.onMoveSelection = onMoveSelection
            field.onSubmit = onSubmit
            field.onCancel = onCancel
        }
        if nsView.window?.firstResponder !== nsView.currentEditor() {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: CommandPaletteSearchField

        init(_ parent: CommandPaletteSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
    }

    private final class PaletteSearchField: NSSearchField {
        var onMoveSelection: ((Int) -> Void)?
        var onSubmit: (() -> Void)?
        var onCancel: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 125:
                onMoveSelection?(1)
            case 126:
                onMoveSelection?(-1)
            case 36, 76:
                onSubmit?()
            case 53:
                onCancel?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}

private struct CommandPaletteOverlay: View {
    @ObservedObject var store: GrantDataStore
    let selectedTab: AppTab
    let dismiss: () -> Void
    let selectTab: (AppTab) -> Void
    let createNewRecord: (AppTab) -> Void
    let openManagerSalaryCalculator: (String) -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var cachedItems: [CommandPaletteItem] = []

    private var results: [CommandPaletteItem] {
        WorkspaceSearchModel.results(for: query, items: cachedItems, defaultLimit: 20, filteredLimit: 60)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    CommandPaletteSearchField(
                        text: $query,
                        onMoveSelection: moveSelection,
                        onSubmit: submitSelection,
                        onCancel: dismiss
                    )
                    .frame(height: 34)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if results.isEmpty {
                                Text(store.language.text("No matches", "Inga träffar"))
                                    .appTypography(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(18)
                            } else {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                    Button {
                                        selectedIndex = index
                                        trigger(item)
                                    } label: {
                                        HStack(alignment: .center, spacing: 12) {
                                            Image(systemName: item.symbolName)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(iconTint(for: item.kind))
                                                .frame(width: 18)

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.title)
                                                    .appTypography(.panelTitle)
                                                    .foregroundStyle(.primary)
                                                    .multilineTextAlignment(.leading)
                                                if let subtitle = item.subtitle.nonEmpty {
                                                    Text(subtitle)
                                                        .appTypography(.secondary)
                                                        .foregroundStyle(.secondary)
                                                        .multilineTextAlignment(.leading)
                                                }
                                            }
                                            Spacer(minLength: 8)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 11)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            Rectangle()
                                                .fill(index == selectedIndex ? AppPalette.activeTabSurface.opacity(0.14) : Color.clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .id(item.id)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 440)
                    .onChange(of: selectedIndex) { _, newValue in
                        guard results.indices.contains(newValue) else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(results[newValue].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(width: 760)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppPalette.cardSurface)
                    .shadow(color: Color.black.opacity(0.22), radius: 26, x: 0, y: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppPalette.border.opacity(0.6), lineWidth: 1)
            )
        }
        .onAppear {
            selectedIndex = 0
            cachedItems = buildItems()
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: store.workspaceSearchGeneration) { _, _ in
            cachedItems = buildItems()
            selectedIndex = min(selectedIndex, max(results.count - 1, 0))
        }
    }

    private func trigger(_ item: CommandPaletteItem) {
        dismiss()
        item.action()
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    private func submitSelection() {
        guard results.indices.contains(selectedIndex) else { return }
        trigger(results[selectedIndex])
    }

    private func iconTint(for kind: CommandPaletteItem.Kind) -> Color {
        switch kind {
        case .action:
            return AppPalette.linkAction
        case .section:
            return .secondary
        case .record:
            return .primary
        }
    }

    private func buildItems() -> [CommandPaletteItem] {
        WorkspaceSearchModel.buildItems(
            store: store,
            language: store.language,
            selectTab: { tab in selectTab(tab) },
            createNewRecord: { tab in createNewRecord(tab) },
            openManagerSalaryCalculator: { managerID in
                openManagerSalaryCalculator(managerID)
            }
        )
    }
}


private struct WorkspaceNavigationBar: View {
    @ObservedObject var store: GrantDataStore
    @Binding var selectedTab: AppTab
    let language: AppLanguage
    let showSearch: () -> Void
    @State private var isNavigationHovered = false
    @State private var dataQualityIssueCount = 0
    @State private var dataQualityIssueRefreshTask: DispatchWorkItem?
    @AppStorage("WorkspaceNavigationLocksCollapsed") private var locksNavigationCollapsed = false
    @AppStorage("FootprintShowsInlineStatistics") private var showsInlineStatistics = true
    private let collapsedNavigationWidth: CGFloat = 96
    private let expandedNavigationWidth: CGFloat = 216

    private var isDarkModeSelected: Bool {
        navigationVisualMode.usesDarkAppearance
    }

    private var navigationVisualMode: AppVisualMode {
        currentVisualModePreference() ?? store.visualMode ?? .lightClean
    }

    private var navigationChromeGradientColors: [Color] {
        [
            AppPalette.chromeTopColor(for: navigationVisualMode),
            AppPalette.chromeBottomColor(for: navigationVisualMode)
        ]
    }

    private var isNavigationExpanded: Bool {
        isNavigationHovered && !locksNavigationCollapsed
    }

    var body: some View {
        sideNavigationBody
            .onAppear {
                scheduleDataQualityIssueCountRefresh(reason: "appear")
            }
            .onDisappear {
                dataQualityIssueRefreshTask?.cancel()
                dataQualityIssueRefreshTask = nil
            }
            .onChange(of: store.dataQualityIssueCountGeneration) { _, _ in
                scheduleDataQualityIssueCountRefresh(reason: "data-change")
            }
    }

    private var sideNavigationBody: some View {
        let reminderCounts = calendarTaskReminderBadgeCounts(entries: store.calendarTaskReminderBadgeEntries)
        return VStack(alignment: .leading, spacing: 0) {
            WindowTrafficLightAnchor()
                .frame(width: 66, height: 24)
                .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(primaryNavigationItems) { item in
                    navigationButton(
                        for: item,
                        reminderBadgeCount: reminderBadgeCount(for: item.tab, counts: reminderCounts),
                        reminderBadgeHelp: reminderBadgeHelp(for: item.tab, counts: reminderCounts)
                    )
                        .padding(.top, item.topPadding)
                }
            }

            Spacer(minLength: 18)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(bottomNavigationItems) { item in
                    navigationButton(for: item)
                }

                navigationSearchButton
                    .padding(.top, 2)

                Rectangle()
                    .fill(AppPalette.border.opacity(0.72))
                    .frame(height: 1)
                    .padding(.vertical, 10)

                CleanShellUnderlineToggleRow(options: languageToggleOptions, keepsIconOnlyWhenExpanded: true)
                    .environment(\.cleanShellNavigationExpanded, isNavigationExpanded)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)

                CleanShellIconToggleRow(options: statisticsToggleOptions)
                    .environment(\.cleanShellNavigationExpanded, isNavigationExpanded)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.top, 8)

                CleanShellIconToggleRow(options: appearanceToggleOptions)
                    .environment(\.cleanShellNavigationExpanded, isNavigationExpanded)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.top, 8)

                CollapsedNavigationLockToggle(
                    isLocked: $locksNavigationCollapsed,
                    isExpanded: isNavigationExpanded,
                    language: language
                )
                .frame(maxWidth: .infinity, alignment: isNavigationExpanded ? .leading : .center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: isNavigationExpanded ? expandedNavigationWidth : collapsedNavigationWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.16), value: isNavigationExpanded)
        .animation(.easeInOut(duration: 0.16), value: locksNavigationCollapsed)
        .onHover { isNavigationHovered = $0 }
        .background(alignment: .trailing) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: navigationChromeGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(AppPalette.border)
                        .frame(width: 1)
                }
                .overlay(alignment: .trailing) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(navigationVisualMode.usesDarkAppearance ? 0.18 : 0.08),
                            Color.black.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 14)
                    .offset(x: 14)
                }
        }
    }

    private func navigationButton(
        for item: CleanShellItem,
        reminderBadgeCount: Int = 0,
        reminderBadgeHelp: String? = nil
    ) -> some View {
        RenewedRailTabButton(
            title: item.title,
            symbolName: item.symbolName,
            badgeCount: item.tab == .dataQuality ? dataQualityIssueCount : nil,
            reminderBadgeCount: reminderBadgeCount,
            reminderBadgeHelp: reminderBadgeHelp,
            isExpanded: isNavigationExpanded,
            isSelected: selectedTab == item.tab,
            action: { selectedTab = item.tab }
        )
        .modifier(OptionalKeyboardShortcut(shortcut: item.shortcut))
    }

    private func reminderBadgeCount(for tab: AppTab, counts: CalendarTaskReminderBadgeCounts) -> Int {
        switch tab {
        case .calendar:
            return counts.calendarBadgeCount
        case .projects:
            return counts.projectBadgeCount
        case .organizations:
            return counts.organizationBadgeCount
        case .publications:
            return counts.publicationBadgeCount
        case .applications:
            return counts.applicationBadgeCount
        case .teaching:
            return counts.teachingBadgeCount
        default:
            return 0
        }
    }

    private func reminderBadgeHelp(for tab: AppTab, counts: CalendarTaskReminderBadgeCounts) -> String? {
        calendarTaskReminderBadgeHelp(entries: counts.entries, language: language) { entry in
            switch tab {
            case .calendar:
                return entry.source != nil
            case .projects:
                return entry.badgeTargets.contains { if case .project = $0 { return true }; return false }
            case .organizations:
                return entry.badgeTargets.contains { if case .organization = $0 { return true }; return false }
            case .publications:
                return entry.badgeTargets.contains { if case .publication = $0 { return true }; return false }
            case .applications:
                return entry.badgeTargets.contains { if case .application = $0 { return true }; return false }
            case .teaching:
                return entry.badgeTargets.contains {
                    switch $0 {
                    case .teachingAssignment, .teachingCourse, .doctoralCandidate: return true
                    default: return false
                    }
                }
            default:
                return false
            }
        }
    }

    private var navigationSearchButton: some View {
        Button(action: showSearch) {
            HStack(spacing: isNavigationExpanded ? 8 : 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.appText.opacity(0.78))
                    .frame(width: 18, height: 18)

                if isNavigationExpanded {
                    Text(language.text("Search", "Sök"))
                        .appTypography(.body)
                        .foregroundStyle(AppPalette.appText.opacity(0.86))
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: isNavigationExpanded ? .leading : .center)
            .padding(.horizontal, isNavigationExpanded ? 10 : 0)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isNavigationExpanded ? AppPalette.cardSurface.opacity(0.42) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isNavigationExpanded ? AppPalette.subtleBorder.opacity(0.8) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: isNavigationExpanded ? .leading : .center)
        .help(language.text("Search", "Sök"))
        .accessibilityLabel(language.text("Search", "Sök"))
        .keyboardShortcut("k", modifiers: .command)
    }

    private var primaryNavigationItems: [CleanShellItem] {
        [
            .init(title: language.text("Calendar", "Kalender"), symbolName: AppTab.calendar.symbolName, tab: .calendar, shortcut: nil),
            .init(title: language.text("Organizations", "Organisationer"), symbolName: AppTab.organizations.symbolName, tab: .organizations, shortcut: "2"),
            .init(title: language.text("Salary planning", "Löneplanering"), symbolName: AppTab.salary.symbolName, tab: .salary, shortcut: "0"),
            .init(title: language.text("Teaching", "Undervisning"), symbolName: AppTab.teaching.symbolName, tab: .teaching, shortcut: "5"),
            .init(title: language.text("Doctoral candidates", "Doktorander"), symbolName: AppTab.doctoralCandidates.symbolName, tab: .doctoralCandidates, shortcut: nil),
            .init(title: language.text("Researchers", "Forskare"), symbolName: AppTab.coauthors.symbolName, tab: .coauthors, shortcut: "3", topPadding: 29),
            .init(title: language.text("Journals", "Tidskrifter"), symbolName: AppTab.journals.symbolName, tab: .journals, shortcut: "4"),
            .init(title: language.text("Projects", "Projekt"), symbolName: AppTab.projects.symbolName, tab: .projects, shortcut: "6"),
            .init(title: language.text("Grants", "Anslag"), symbolName: AppTab.applications.symbolName, tab: .applications, shortcut: "7"),
            .init(title: language.text("Publications", "Publikationer"), symbolName: AppTab.publications.symbolName, tab: .publications, shortcut: "8"),
            .init(title: language.text("Congresses", "Kongresser"), symbolName: AppTab.congresses.symbolName, tab: .congresses, shortcut: nil),
            .init(title: language.text("Expert assignments", "Sakkunniguppdrag"), symbolName: AppTab.expertAssignments.symbolName, tab: .expertAssignments, shortcut: nil),
            .init(title: language.text("Media", "Media"), symbolName: AppTab.dissemination.symbolName, tab: .dissemination, shortcut: nil),
        ]
    }

    private var bottomNavigationItems: [CleanShellItem] {
        [
            .init(title: "CV", symbolName: AppTab.cv.symbolName, tab: .cv, shortcut: nil),
            .init(title: language.text("Statistics", "Statistik"), symbolName: AppTab.statistics.symbolName, tab: .statistics, shortcut: nil),
            .init(title: language.text("Data quality", "Datakvalitet"), symbolName: AppTab.dataQuality.symbolName, tab: .dataQuality, shortcut: nil),
        ]
    }

    private var languageToggleOptions: [CleanShellUnderlineToggleOption] {
        [
            .init(
                title: language.text("Swedish", "Svenska"),
                iconText: "🇸🇪",
                isSelected: store.language == .swedish,
                action: { store.setLanguage(.swedish) }
            ),
            .init(
                title: language.text("English", "Engelska"),
                iconText: "🇬🇧",
                isSelected: store.language == .english,
                action: { store.setLanguage(.english) }
            ),
        ]
    }

    private var statisticsToggleOptions: [CleanShellUnderlineToggleOption] {
        [
            .init(
                title: store.language.text("Show statistics", "Visa statistik"),
                systemImage: "chart.pie",
                isSelected: showsInlineStatistics,
                action: { showsInlineStatistics = true }
            ),
            .init(
                title: store.language.text("Hide statistics", "Dölj statistik"),
                systemImage: "chart.pie",
                slashed: true,
                isSelected: !showsInlineStatistics,
                action: { showsInlineStatistics = false }
            ),
        ]
    }

    private var appearanceToggleOptions: [CleanShellUnderlineToggleOption] {
        [
            .init(
                title: store.language.text("Light appearance", "Ljust läge"),
                systemImage: "sun.max",
                isSelected: !isDarkModeSelected,
                action: { store.setVisualMode(.lightClean) }
            ),
            .init(
                title: store.language.text("Dark appearance", "Mörkt läge"),
                systemImage: "moon",
                isSelected: isDarkModeSelected,
                action: { store.setVisualMode(.darkNew) }
            ),
        ]
    }

    private func scheduleDataQualityIssueCountRefresh(reason: String) {
        dataQualityIssueRefreshTask?.cancel()
        let startedAt = CFAbsoluteTimeGetCurrent()
        let issueCount = store.cachedDataQualityIssueCountForNavigation()
        let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        dataQualityIssueCount = issueCount
        store.appendPerformanceDiagnostic(
            String(
                format: "nav-data-quality-count reason=%@ count=%ld total_ms=%.2f",
                reason,
                issueCount,
                duration
            )
        )
        dataQualityIssueRefreshTask = nil
    }
}

private struct CleanShellItem: Identifiable {
    // Identity must be stable across body evaluations; a fresh UUID per
    // evaluation forced full ForEach re-diffs and defeated animations.
    var id: AppTab { tab }
    let title: String
    let symbolName: String
    let tab: AppTab
    let shortcut: Character?
    var topPadding: CGFloat = 0
}

private struct WindowTrafficLightAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowTrafficLightAnchorView {
        WindowTrafficLightAnchorView()
    }

    func updateNSView(_ nsView: WindowTrafficLightAnchorView, context: Context) {
        nsView.scheduleButtonLayout()
    }
}

private final class WindowTrafficLightAnchorView: NSView {
    private let buttonSpacing: CGFloat = 20

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleButtonLayout()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleButtonLayout()
    }

    override func layout() {
        super.layout()
        scheduleButtonLayout()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        scheduleButtonLayout()
    }

    func scheduleButtonLayout() {
        DispatchQueue.main.async { [weak self] in
            self?.layoutWindowButtons()
        }
    }

    private func layoutWindowButtons() {
        guard let window,
              let closeButton = window.standardWindowButton(.closeButton),
              let minimizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let buttonSuperview = closeButton.superview else { return }

        let anchorRectInWindow = convert(bounds, to: nil)
        let anchorRect = buttonSuperview.convert(anchorRectInWindow, from: nil)
        let buttons = [closeButton, minimizeButton, zoomButton]
        let maxButtonHeight = buttons.map(\.frame.height).max() ?? closeButton.frame.height
        let startX = anchorRect.minX
        let y = anchorRect.midY - maxButtonHeight / 2

        for (index, button) in buttons.enumerated() {
            button.setFrameOrigin(NSPoint(x: startX + CGFloat(index) * buttonSpacing, y: y))
        }
    }
}

struct RenewedRailTabButton: View {
    let title: String
    let symbolName: String
    var badgeCount: Int? = nil
    var reminderBadgeCount = 0
    var reminderBadgeHelp: String? = nil
    var isExpanded: Bool = true
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isExpanded ? 8 : 0) {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? AppPalette.mainMenuSelectionText : AppPalette.appText.opacity(0.78))
                    .frame(width: 18, height: 18)
                    .appReminderCountBadge(reminderBadgeCount, inset: -6, help: reminderBadgeHelp)
                if isExpanded {
                    Text(title)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    if let badgeCount, badgeCount > 0 {
                        NavigationIssueBadge(count: badgeCount)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .foregroundStyle(isSelected ? AppPalette.mainMenuSelectionText : AppPalette.appText)
            .padding(.horizontal, isExpanded ? 10 : 0)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppPalette.mainMenuSelectionSurface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? AppPalette.mainMenuSelectionStroke : Color.clear, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if !isExpanded, let badgeCount, badgeCount > 0 {
                    NavigationIssueBadge(count: badgeCount)
                        .offset(x: 4, y: -5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(accessibilityBadgeSummary)
    }

    // The rail is icon-only when collapsed (the default); VoiceOver needs
    // the workspace name and the badge counts the icons carry visually.
    private var accessibilityBadgeSummary: String {
        var parts: [String] = []
        if let badgeCount, badgeCount > 0 {
            parts.append("\(badgeCount)")
        }
        if reminderBadgeCount > 0, let reminderBadgeHelp {
            parts.append(reminderBadgeHelp)
        }
        return parts.joined(separator: ", ")
    }
}

private struct CollapsedNavigationLockToggle: View {
    @Binding var isLocked: Bool
    let isExpanded: Bool
    let language: AppLanguage

    private var title: String {
        language.text("Lock narrow menu", "Lås smal meny")
    }

    var body: some View {
        Button {
            isLocked.toggle()
        } label: {
            HStack(spacing: isExpanded ? 8 : 0) {
                ZStack(alignment: isLocked ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(isLocked ? AppPalette.linkAction.opacity(0.9) : AppPalette.subtleBorder.opacity(0.45))
                        .frame(width: 34, height: 18)

                    Circle()
                        .fill(AppPalette.cardSurface)
                        .frame(width: 14, height: 14)
                        .padding(.horizontal, 2)
                }

                if isExpanded {
                    Text(title)
                        .appTypography(.secondary)
                        .foregroundStyle(AppPalette.appText.opacity(0.78))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        // The hand-drawn switch has no accessibility contract of its own;
        // expose it as the toggle it is.
        .accessibilityRepresentation {
            Toggle(title, isOn: $isLocked)
        }
    }
}

private struct CleanShellUnderlineToggleOption: Identifiable {
    // Stable identity: a fresh UUID per body evaluation forced full
    // ForEach re-diffs and reset hover state on every rail render.
    var id: String { title ?? systemImage ?? iconText ?? "" }
    var title: String? = nil
    var systemImage: String? = nil
    var iconText: String? = nil
    /// Draws a diagonal strike over the system image (used for "off" states
    /// of symbols that have no .slash variant, like chart.pie).
    var slashed = false
    let isSelected: Bool
    let action: () -> Void
}

private struct CleanShellNavigationExpandedKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var cleanShellNavigationExpanded: Bool {
        get { self[CleanShellNavigationExpandedKey.self] }
        set { self[CleanShellNavigationExpandedKey.self] = newValue }
    }
}

private struct CleanShellUnderlineToggleRow: View {
    let options: [CleanShellUnderlineToggleOption]
    var keepsIconOnlyWhenExpanded = false
    @Environment(\.cleanShellNavigationExpanded) private var isExpanded

    var body: some View {
        HStack(spacing: isExpanded ? 20 : 10) {
            ForEach(options) { option in
                CleanShellUnderlineToggleButton(
                    option: option,
                    usesCompactWidth: !isExpanded || keepsIconOnlyWhenExpanded,
                    showsTitleInExpandedNavigation: !keepsIconOnlyWhenExpanded
                )
            }
        }
    }
}

private struct CleanShellIconToggleRow: View {
    let options: [CleanShellUnderlineToggleOption]
    @Environment(\.cleanShellNavigationExpanded) private var isExpanded

    var body: some View {
        HStack(spacing: isExpanded ? 16 : 10) {
            ForEach(options) { option in
                CleanShellUnderlineToggleButton(option: option, usesCompactWidth: true)
            }
        }
    }
}

private struct CleanShellUnderlineToggleButton: View {
    let option: CleanShellUnderlineToggleOption
    var usesCompactWidth = false
    var showsTitleInExpandedNavigation = true
    @Environment(\.cleanShellNavigationExpanded) private var isExpanded

    var body: some View {
        Button(action: option.action) {
            VStack(spacing: 6) {
                if let iconText = option.iconText {
                    HStack(spacing: 6) {
                        Text(iconText)
                            .font(.system(size: 15, weight: option.isSelected ? .semibold : .medium))
                        if isExpanded, showsTitleInExpandedNavigation, let title = option.title {
                            Text(title)
                                .font(.system(size: 16, weight: option.isSelected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(AppPalette.appText)
                } else if let systemImage = option.systemImage {
                    // Icon wins over title so options may carry a title
                    // purely for tooltip/VoiceOver without changing looks.
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(AppPalette.appText)
                        .overlay {
                            if option.slashed {
                                RoundedRectangle(cornerRadius: 1, style: .continuous)
                                    .fill(AppPalette.appText)
                                    .frame(width: 2, height: 27)
                                    .rotationEffect(.degrees(45))
                            }
                        }
                } else if let title = option.title {
                    if isExpanded {
                        Text(title)
                            .font(.system(size: 16, weight: option.isSelected ? .semibold : .medium))
                            .foregroundStyle(AppPalette.appText)
                            .lineLimit(1)
                    } else if let first = title.first {
                        Text(String(first))
                            .font(.system(size: 16, weight: option.isSelected ? .semibold : .medium))
                            .foregroundStyle(AppPalette.appText)
                    }
                }

                Rectangle()
                    .fill(option.isSelected ? AppPalette.linkAction : AppPalette.subtleBorder.opacity(0.18))
                    .frame(width: usesCompactWidth ? 20 : 38, height: 2)
            }
            .frame(minWidth: usesCompactWidth ? 24 : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.title ?? "")
        .accessibilityLabel(option.title ?? "")
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
    }
}

private struct NavigationIssueBadge: View {
    let count: Int

    var body: some View {
        AppCountBadge(count: count)
    }
}


private struct OptionalKeyboardShortcut: ViewModifier {
    let shortcut: Character?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
        } else {
            content
        }
    }
}



private struct ClipboardPreviewOverlay: View {
    let text: String

    var body: some View {
        VStack {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 18, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(40)
    }
}

private struct FooterStatusBar: View {
    @ObservedObject var store: GrantDataStore

    var body: some View {
        Group {
            if AppRuntime.usesRenewedChrome {
                HStack(spacing: 12) {
                    if let message = message {
                        Text(message)
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.packageIdentity.mode != .selfContained {
                        runtimeBadge(text: store.packageIdentity.mode.title(store.language), accent: modeAccentColor)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppPalette.footerSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppPalette.border.opacity(0.8), lineWidth: 1)
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else {
                HStack(spacing: 12) {
                    if let message = message {
                        Text(message)
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppPalette.footerSurface)
            }
        }
    }

    private var message: String? {
        if let error = store.loadError?.nonEmpty {
            return error
        }
        if let backgroundActivity = store.backgroundActivityMessage?.nonEmpty {
            return backgroundActivity
        }
        if let notice = store.notice {
            return notice.message
        }
        if store.persistenceStatus.isSaving {
            return store.language.text("Saving…", "Sparar…")
        }

        var parts: [String] = []
        if let lastSavedAt = store.persistenceStatus.lastSavedAt {
            parts.append(store.language.text("Saved", "Sparat") + " " + timeText(lastSavedAt))
        }
        if let lastBackupAt = store.persistenceStatus.lastBackupAt {
            parts.append(store.language.text("Backup", "Backup") + " " + timeText(lastBackupAt))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private var modeAccentColor: Color {
        switch store.packageIdentity.mode {
        case .journalsOnly:
            return Color(hex: 0x0D5F5B)
        case .selfContained:
            return Color(hex: 0x146C94)
        case .localBootstrap:
            return Color(hex: 0x8C5E00)
        case .share:
            return Color(hex: 0x7A2048)
        case .development:
            return AppPalette.actionSave
        }
    }

    private func runtimeBadge(text: String, accent: Color) -> some View {
        Text(text)
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(accent.opacity(0.28), lineWidth: 1)
            )
    }
}


enum PersistentSplitViewUpdateStrategy {
    case simultaneous
    case detailFirst
}

@MainActor


struct PersistentSplitView<Sidebar: View, Detail: View>: View {
    let defaultsKey: String
    let defaultFraction: CGFloat
    let sidebarMinimumWidth: CGFloat
    let sidebarMaximumWidth: CGFloat?
    let detailMinimumWidth: CGFloat
    let updateStrategy: PersistentSplitViewUpdateStrategy
    let sidebar: Sidebar
    let detail: Detail
    @State private var fraction: CGFloat
    @State private var dragStartSidebarWidth: CGFloat?
    @State private var dragStartTranslationWidth: CGFloat = 0
    @State private var activeDefaultsKey: String
    @State private var screenResolutionSignature: String
    @State private var isDividerHovered = false

    private let dividerWidth: CGFloat = 10

    init(
        defaultsKey: String,
        defaultFraction: CGFloat = 0.5,
        sidebarMinimumWidth: CGFloat = 420,
        sidebarMaximumWidth: CGFloat? = nil,
        detailMinimumWidth: CGFloat = 520,
        updateStrategy: PersistentSplitViewUpdateStrategy = .simultaneous,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.defaultsKey = AppRuntime.scopedDefaultsKey(defaultsKey)
        self.defaultFraction = defaultFraction
        self.sidebarMinimumWidth = sidebarMinimumWidth
        self.sidebarMaximumWidth = sidebarMaximumWidth
        self.detailMinimumWidth = detailMinimumWidth
        self.updateStrategy = updateStrategy
        self.sidebar = sidebar()
        self.detail = detail()
        let initialScreenResolutionSignature = Self.currentScreenResolutionSignature()
        let initialDefaultsKey = Self.resolutionScopedDefaultsKey(
            for: self.defaultsKey,
            screenResolutionSignature: initialScreenResolutionSignature
        )
        _screenResolutionSignature = State(initialValue: initialScreenResolutionSignature)
        _activeDefaultsKey = State(initialValue: initialDefaultsKey)
        _fraction = State(
            initialValue: Self.storedFraction(
                for: initialDefaultsKey,
                baseDefaultsKey: self.defaultsKey,
                defaultFraction: defaultFraction
            )
        )
    }

    init(
        layout: AppSplitLayout,
        updateStrategy: PersistentSplitViewUpdateStrategy = .simultaneous,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.defaultsKey = AppRuntime.scopedDefaultsKey(layout.defaultsKey)
        self.defaultFraction = layout.defaultFraction
        self.sidebarMinimumWidth = layout.sidebarMinimumWidth
        self.sidebarMaximumWidth = layout.sidebarMaximumWidth
        self.detailMinimumWidth = layout.detailMinimumWidth
        self.updateStrategy = updateStrategy
        self.sidebar = sidebar()
        self.detail = detail()
        let initialScreenResolutionSignature = Self.currentScreenResolutionSignature()
        let initialDefaultsKey = Self.resolutionScopedDefaultsKey(
            for: self.defaultsKey,
            screenResolutionSignature: initialScreenResolutionSignature
        )
        _screenResolutionSignature = State(initialValue: initialScreenResolutionSignature)
        _activeDefaultsKey = State(initialValue: initialDefaultsKey)
        _fraction = State(
            initialValue: Self.storedFraction(
                for: initialDefaultsKey,
                baseDefaultsKey: self.defaultsKey,
                defaultFraction: layout.defaultFraction
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let currentDefaultsKey = Self.resolutionScopedDefaultsKey(
                for: defaultsKey,
                screenResolutionSignature: screenResolutionSignature
            )
            let totalWidth = geometry.size.width
            let availableWidth = max(totalWidth - dividerWidth, 1)
            let bounds = sidebarBounds(availableWidth: availableWidth)
            let sidebarWidth = clampedSidebarWidth(availableWidth: availableWidth, bounds: bounds)
            let detailWidth = max(availableWidth - sidebarWidth, 0)

            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth, height: geometry.size.height, alignment: .topLeading)
                    .clipped()

                splitDivider(
                    availableWidth: availableWidth,
                    bounds: bounds,
                    currentSidebarWidth: sidebarWidth,
                    currentDefaultsKey: currentDefaultsKey
                )

                detail
                    .frame(width: detailWidth, height: geometry.size.height, alignment: .topLeading)
                    .clipped()
            }
            .frame(width: totalWidth, height: geometry.size.height, alignment: .topLeading)
            .onAppear {
                applyDefaultsKeyIfNeeded(currentDefaultsKey)
            }
            .onChange(of: currentDefaultsKey) { _, nextKey in
                applyDefaultsKeyIfNeeded(nextKey)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { _ in
                updateScreenResolutionSignature()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                updateScreenResolutionSignature()
            }
        }
    }

    private func sidebarBounds(availableWidth: CGFloat) -> ClosedRange<CGFloat> {
        let lower = min(sidebarMinimumWidth, availableWidth)
        let detailLimitedUpper = availableWidth - detailMinimumWidth
        let contentLimitedUpper = sidebarMaximumWidth.map { min(detailLimitedUpper, $0) } ?? detailLimitedUpper
        let upper = max(lower, contentLimitedUpper)
        return lower...upper
    }

    private func clampedSidebarWidth(availableWidth: CGFloat, bounds: ClosedRange<CGFloat>) -> CGFloat {
        min(max(availableWidth * fraction, bounds.lowerBound), bounds.upperBound)
    }

    private func clampedSidebarWidth(_ proposedWidth: CGFloat, bounds: ClosedRange<CGFloat>) -> CGFloat {
        min(max(proposedWidth, bounds.lowerBound), bounds.upperBound)
    }

    private func splitDivider(
        availableWidth: CGFloat,
        bounds: ClosedRange<CGFloat>,
        currentSidebarWidth: CGFloat,
        currentDefaultsKey: String
    ) -> some View {
        let isActive = isDividerHovered || dragStartSidebarWidth != nil
        return Rectangle()
            .fill(AppPalette.detailPanelSurface)
            .frame(width: dividerWidth)
            .overlay {
                LinearGradient(
                    colors: [
                        Color.black.opacity(isActive ? 0.16 : 0.10),
                        Color.black.opacity(isActive ? 0.07 : 0.04),
                        Color.black.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isDividerHovered = hovering
                // The 10 pt divider gave no resize affordance at all.
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .accessibilityElement()
            // PersistentSplitView is a language-agnostic layout component;
            // a bilingual literal avoids threading AppLanguage through all
            // thirteen call sites for one label.
            .accessibilityLabel("Sidofältsbredd / Sidebar width")
            .accessibilityValue("\(Int(fraction * 100)) %")
            .accessibilityAdjustableAction { direction in
                let step: CGFloat = direction == .increment ? 0.05 : -0.05
                let nextWidth = clampedSidebarWidth((fraction + step) * availableWidth, bounds: bounds)
                fraction = nextWidth / availableWidth
                activeDefaultsKey = currentDefaultsKey
                UserDefaults.standard.set(Double(fraction), forKey: currentDefaultsKey)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartSidebarWidth == nil {
                            dragStartSidebarWidth = currentSidebarWidth
                            dragStartTranslationWidth = value.translation.width
                        }

                        let startWidth = dragStartSidebarWidth ?? currentSidebarWidth
                        let translationDelta = value.translation.width - dragStartTranslationWidth
                        let proposedWidth = startWidth + translationDelta
                        let nextWidth = clampedSidebarWidth(proposedWidth, bounds: bounds)
                        fraction = nextWidth / availableWidth
                        activeDefaultsKey = currentDefaultsKey

                        if nextWidth != proposedWidth {
                            dragStartSidebarWidth = nextWidth
                            dragStartTranslationWidth = value.translation.width
                        }
                    }
                    .onEnded { value in
                        let startWidth = dragStartSidebarWidth ?? currentSidebarWidth
                        let translationDelta = value.translation.width - dragStartTranslationWidth
                        let proposedWidth = startWidth + translationDelta
                        let persistedWidth = clampedSidebarWidth(proposedWidth, bounds: bounds)
                        let persisted = persistedWidth / availableWidth
                        fraction = persisted
                        dragStartSidebarWidth = nil
                        dragStartTranslationWidth = 0
                        activeDefaultsKey = currentDefaultsKey
                        UserDefaults.standard.set(Double(persisted), forKey: currentDefaultsKey)
                    }
            )
    }

    private func applyDefaultsKeyIfNeeded(_ nextKey: String) {
        guard activeDefaultsKey != nextKey else { return }
        activeDefaultsKey = nextKey
        fraction = Self.storedFraction(
            for: nextKey,
            baseDefaultsKey: defaultsKey,
            defaultFraction: defaultFraction
        )
    }

    private func updateScreenResolutionSignature() {
        let nextSignature = Self.currentScreenResolutionSignature()
        guard screenResolutionSignature != nextSignature else { return }
        screenResolutionSignature = nextSignature
    }

    private static func storedFraction(
        for defaultsKey: String,
        baseDefaultsKey: String,
        defaultFraction: CGFloat
    ) -> CGFloat {
        if let stored = UserDefaults.standard.object(forKey: defaultsKey) as? Double {
            return CGFloat(stored)
        }
        if defaultsKey != baseDefaultsKey,
           let legacyStored = UserDefaults.standard.object(forKey: baseDefaultsKey) as? Double {
            return CGFloat(legacyStored)
        }
        return defaultFraction
    }

    private static func resolutionScopedDefaultsKey(
        for baseKey: String,
        screenResolutionSignature: String
    ) -> String {
        "\(baseKey).Screen.\(screenResolutionSignature)"
    }

    private static func currentScreenResolutionSignature() -> String {
        let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
        guard let screen else { return "unknown" }
        let scale = screen.backingScaleFactor
        let pixelWidth = Int((screen.frame.width * scale).rounded())
        let pixelHeight = Int((screen.frame.height * scale).rounded())
        let scalePercent = Int((scale * 100).rounded())
        return "\(pixelWidth)x\(pixelHeight)@\(scalePercent)"
    }
}

private extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
