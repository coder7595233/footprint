import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    private enum ApplicationListFilter: Equatable {
        case all
        case awaiting
        case rejected
        case granted
    }

    private struct RelatedViewState: Equatable {
        var projectID: String
        var relatedApplications: [GrantApplication]
        var relatedPublications: [PublicationRecord]
        var relatedConferenceContributions: [CVConferenceContribution]
        var grantedApplications: [GrantApplication]
        var awaitingDecisionApplications: [GrantApplication]
        var rejectedApplications: [GrantApplication]
        var projectApplicationsForList: [GrantApplication]
        var projectPublications: [PublicationRecord]
        var calendarEvents: [CalendarLinkedEventRow]
        var orderedTimelineApplications: [GrantApplication]
        var timelineSnapshot: GrantDataStore.ProjectTimelineSnapshot
        var ownedTimelineSnapshot: GrantDataStore.ProjectTimelineSnapshot
        var meetingStatistics: CalendarMeetingHoursSummary?
        var isReady: Bool

        static func empty(projectID: String) -> RelatedViewState {
            RelatedViewState(
                projectID: projectID,
                relatedApplications: [],
                relatedPublications: [],
                relatedConferenceContributions: [],
                grantedApplications: [],
                awaitingDecisionApplications: [],
                rejectedApplications: [],
                projectApplicationsForList: [],
                projectPublications: [],
                calendarEvents: [],
                orderedTimelineApplications: [],
                timelineSnapshot: .empty,
                ownedTimelineSnapshot: .empty,
                meetingStatistics: nil,
                isReady: false
            )
        }
    }

    private struct ProjectEditorState: Equatable {
        var nameSv: String
        var nameEn: String
        var fullNameSv: String
        var fullNameEn: String
        var collaboratorNames: [String]
        var projectStatus: ProjectLifecycleStatus
        var hasDataCollection: Bool
        var isEditingLocked: Bool
        var ethicsBaseApplication: ProjectEthicsApplication
        var ethicsAmendments: [ProjectEthicsApplication]
        var ethicsLink: String
        var clinicalTrialRegistrations: [ProjectClinicalTrialRegistration]
        var principalOrganizations: [ProjectPrincipalOrganization]
        var dataCollections: [ProjectDataCollection]
        var projectTasks: [ProjectTaskItem]
    }

    private final class ProjectDetailStateStore: ObservableObject {
        @Published var relatedViewState: RelatedViewState

        init(relatedViewState: RelatedViewState) {
            self.relatedViewState = relatedViewState
        }
    }

    let store: GrantDataStore
    let project: ProjectRecord
    let isActive: Bool
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var projectProjection: DataStoreDomainProjection
    @StateObject private var calendarProjection: DataStoreDomainProjection

    @State private var editorState: ProjectEditorState
    @State private var collaboratorIdentity: StableStringDraftListState
    @State private var showsAuthorExportSheet = false
    @State private var authorExportConfiguration = SubmissionAuthorExportConfiguration.standard
    @AppStorage("FootprintShowsInlineStatistics") private var showsInlineStatistics = true
    @State private var collaboratorsExpanded = true
    @State private var tasksExpanded = true
    @State private var activitiesOverviewExpanded = true
    @State private var protocolEntriesExpanded = true
    @State private var ethicsExpanded = true
    @State private var showCompletedProjectTasks = false
    @State private var applicationsExpanded = true
    @State private var publicationsExpanded = true
    @State private var pendingCollaboratorName = ""
    @State private var draggedCollaboratorName: String?
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var isLoadingProjectState = false
    @StateObject private var projectDetailState: ProjectDetailStateStore
    @State private var showsCollaboratorGrantsInTimeline: Bool
    @State private var activeApplicationListFilter: ApplicationListFilter = .all
    @State private var projectScrollTarget: String?
    @State private var needsRelatedRefreshWhenActive = false
    @State private var showsDeferredProjectSections = true
    @State private var calendarRefreshToken: UInt = 0

    private let addNewToken = "__add_new__"
    init(store: GrantDataStore, project: ProjectRecord, isActive: Bool = true) {
        self.store = store
        self.project = project
        self.isActive = isActive
        _projectProjection = StateObject(
            wrappedValue: DataStoreDomainProjection(store: store, domain: .projects)
        )
        _calendarProjection = StateObject(
            wrappedValue: DataStoreDomainProjection(store: store, domain: .calendar)
        )
        _projectDetailState = StateObject(
            wrappedValue: ProjectDetailStateStore(
                relatedViewState: .empty(projectID: project.id)
            )
        )
        _editorState = State(initialValue: ProjectEditorState(
            nameSv: project.nameSv,
            nameEn: project.nameEn,
            fullNameSv: project.fullNameSv,
            fullNameEn: project.fullNameEn,
            collaboratorNames: project.collaboratorNames,
            projectStatus: project.projectStatus,
            hasDataCollection: project.hasDataCollection,
            isEditingLocked: project.isEditingLocked,
            ethicsBaseApplication: project.ethicsBaseApplication,
            ethicsAmendments: project.ethicsAmendments + [ProjectEthicsApplication()],
            ethicsLink: project.ethicsLink ?? "",
            clinicalTrialRegistrations: editableProjectClinicalTrialRegistrations(project.clinicalTrialRegistrations),
            principalOrganizations: project.principalOrganizations + [ProjectPrincipalOrganization()],
            dataCollections: project.dataCollections + [ProjectDataCollection()],
            projectTasks: normalizedProjectTaskItems(project.projectTasks)
        ))
        _collaboratorIdentity = State(initialValue: StableStringDraftListState(values: project.collaboratorNames))
        _showsCollaboratorGrantsInTimeline = State(
            initialValue: store.includesCollaboratorGrantsInProjectTimelineByDefault(for: project)
        )
    }

    private var nameSv: String { get { editorState.nameSv } nonmutating set { editorState.nameSv = newValue } }
    private var nameEn: String { get { editorState.nameEn } nonmutating set { editorState.nameEn = newValue } }
    private var fullNameSv: String { get { editorState.fullNameSv } nonmutating set { editorState.fullNameSv = newValue } }
    private var fullNameEn: String { get { editorState.fullNameEn } nonmutating set { editorState.fullNameEn = newValue } }
    private var collaboratorNames: [String] { get { editorState.collaboratorNames } nonmutating set { editorState.collaboratorNames = newValue } }
    private var projectStatus: ProjectLifecycleStatus { get { editorState.projectStatus } nonmutating set { editorState.projectStatus = newValue } }
    private var hasDataCollection: Bool { get { editorState.hasDataCollection } nonmutating set { editorState.hasDataCollection = newValue } }
    private var isEditingLocked: Bool { get { editorState.isEditingLocked } nonmutating set { editorState.isEditingLocked = newValue } }
    private var ethicsBaseApplication: ProjectEthicsApplication { get { editorState.ethicsBaseApplication } nonmutating set { editorState.ethicsBaseApplication = newValue } }
    private var ethicsAmendments: [ProjectEthicsApplication] { get { editorState.ethicsAmendments } nonmutating set { editorState.ethicsAmendments = newValue } }
    private var ethicsLink: String { get { editorState.ethicsLink } nonmutating set { editorState.ethicsLink = newValue } }
    private var clinicalTrialRegistrations: [ProjectClinicalTrialRegistration] { get { editorState.clinicalTrialRegistrations } nonmutating set { editorState.clinicalTrialRegistrations = newValue } }
    private var principalOrganizations: [ProjectPrincipalOrganization] { get { editorState.principalOrganizations } nonmutating set { editorState.principalOrganizations = newValue } }
    private var dataCollections: [ProjectDataCollection] { get { editorState.dataCollections } nonmutating set { editorState.dataCollections = newValue } }
    private var projectTasks: [ProjectTaskItem] { get { editorState.projectTasks } nonmutating set { editorState.projectTasks = newValue } }
    private var relatedViewState: RelatedViewState {
        get { projectDetailState.relatedViewState }
        nonmutating set { projectDetailState.relatedViewState = newValue }
    }

    private var applications: [GrantApplication] {
        relatedViewState.relatedApplications
    }

    private var grantedApplications: [GrantApplication] {
        relatedViewState.grantedApplications
    }

    private var grantedAndPendingTimelineApplications: [GrantApplication] {
        relatedViewState.orderedTimelineApplications
    }

    private var pendingAndRejectedApplications: [GrantApplication] {
        nonGrantedWorklist(from: applications)
    }

    private var awaitingDecisionApplications: [GrantApplication] {
        relatedViewState.awaitingDecisionApplications
    }

    private var rejectedApplications: [GrantApplication] {
        relatedViewState.rejectedApplications
    }

    private var projectPublications: [PublicationRecord] {
        relatedViewState.projectPublications
    }

    private var projectConferenceContributions: [CVConferenceContribution] {
        relatedViewState.relatedConferenceContributions
    }

    private var isLoadingProjectDerivedData: Bool {
        !relatedViewState.isReady
    }

    private var hasVisibleProjectTasks: Bool {
        projectTasks.contains { !$0.isEmpty }
    }

    private var shouldShowProjectTaskList: Bool {
        !isEditingLocked || CentralTaskListSection.hasIncompleteTasks(
            store: store,
            linkKind: .project,
            targetID: project.id
        )
    }

    private func projectApplicationStatusPriority(_ status: String) -> Int {
        switch status {
        case "", "Att söka":
            return 0
        case "Väntar svar":
            return 1
        case "Beviljat":
            return 2
        case "Tillbakadragen":
            return 3
        case "Avslag":
            return 4
        case "Ej sökt":
            return 5
        default:
            return 6
        }
    }

    private var projectApplicationsForList: [GrantApplication] {
        switch activeApplicationListFilter {
        case .all:
            return relatedViewState.projectApplicationsForList
        case .awaiting:
            return relatedViewState.awaitingDecisionApplications
        case .rejected:
            return relatedViewState.rejectedApplications
        case .granted:
            return relatedViewState.grantedApplications
        }
    }

    var body: some View {
        let _ = projectProjection.revision
        let _ = calendarProjection.revision
        return applyProjectSyncModifiers(
            to: applyProjectAutosaveModifiers(
                to: applyProjectLifecycleModifiers(to: projectDetailBody)
            )
        )
    }

    /// Shared width for the inline statistics blocks (Medarbetare,
    /// Ansökningar, Aktiviteter) so all three line up at the same right edge.
    private let projectInlineStatisticsWidth: CGFloat = 480

    private var projectDetailBody: some View {
        let language = store.language

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                let localizedShortName = language == .swedish ? nameSv : nameEn
                                let localizedFullName = language == .swedish ? fullNameSv : fullNameEn

                                if isEditingLocked {
                                    Text(localizedShortName.trimmedOrNil ?? language.text("Project", "Projekt"))
                                        .font(appFont(.pageTitle))
                                        .foregroundStyle(AppPalette.appText)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .layoutPriority(2)

                                    if let fullName = localizedFullName.trimmedOrNil {
                                        Text(fullName)
                                            .font(appFont(.body).weight(.medium))
                                            .foregroundStyle(AppPalette.appText)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                } else {
                                    AppInlineTitleTextField(
                                        placeholder: language.text("Short name", "Kortnamn"),
                                        text: language == .swedish ? $editorState.nameSv : $editorState.nameEn,
                                        font: appNSFont(.pageTitle),
                                        minHeight: 30
                                    )
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .layoutPriority(2)

                                    AppInlineTitleTextField(
                                        placeholder: language.text("Full name", "Fullständigt namn"),
                                        text: language == .swedish ? $editorState.fullNameSv : $editorState.fullNameEn,
                                        font: appNSFont(.body),
                                        textColor: .secondaryLabelColor,
                                        minHeight: 18
                                    )
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 10) {
                                ProjectDocumentContentAnchor(
                                    store: store,
                                    projectID: project.id,
                                    title: language.text("Project document", "Projektdokument")
                                )

                                projectEditorLockButton(language: language)

                                if !isEditingLocked {
                                    DeleteActionButton(
                                        title: language.text("Delete", "Ta bort"),
                                        cancelTitle: language.text("Cancel", "Avbryt")
                                    ) {
                                        store.deleteProject(id: project.id)
                                    }
                                }
                            }
                        }

                    }

                    // Status row directly under the header; the export menus
                    // stack to its right instead of reserving their own band.
                    HStack(alignment: .top, spacing: 16) {
                        if !isEditingLocked {
                            if AppRuntime.usesRenewedChrome {
                                AppMenuSelectionField(
                                    selection: $editorState.projectStatus,
                                    options: ProjectLifecycleStatus.allCases.map { ($0.displayName(language: language), $0) },
                                    placeholder: nil
                                )
                                .frame(width: 180, alignment: .leading)
                            } else {
                                Picker("", selection: $editorState.projectStatus) {
                                    ForEach(ProjectLifecycleStatus.allCases, id: \.self) { status in
                                        Text(status.displayName(language: language)).tag(status)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .formKeyboardNavigable()
                                .frame(width: 180, alignment: .leading)
                            }

                            Toggle(language.text("Data collection", "Datainsamling"), isOn: $editorState.hasDataCollection)
                                .appCheckboxStyle()
                                .appTypography(.tableHeader)
                        }

                        Spacer(minLength: 16)

                        projectExportStrip(language: language)
                    }

                    if showsDeferredProjectSections {
                        grantedApplicationsAndTimelineContent(language: language)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .id("project-timeline-section")

                        collapsibleDetailSection(title: language.text("Collaborators", "Medarbetare"), isExpanded: $collaboratorsExpanded) {
                            HStack(alignment: .top, spacing: 24) {
                                collaboratorPickerArea(language: language)

                                // Compact one-line composition rows to the
                                // right of the name list — same fixed width
                                // and right edge as the Ansökningar and
                                // Aktiviteter statistics.
                                if showsInlineStatistics {
                                    Spacer(minLength: 28)
                                    ContributorCompositionInlineSection(
                                        store: store,
                                        contributorNames: collaboratorNames,
                                        language: language
                                    )
                                    .frame(width: projectInlineStatisticsWidth, alignment: .topLeading)
                                }
                            }
                        }

                        if hasDataCollection {
                            collapsibleDetailSection(title: language.text("Ethics and data collection", "Etik och datainsamling"), isExpanded: $ethicsExpanded) {
                                ProjectEthicsAndDataCollectionSection(
                                    ethicsBaseApplication: $editorState.ethicsBaseApplication,
                                    ethicsAmendments: $editorState.ethicsAmendments,
                                    ethicsAuthorityURL: ethicsAuthorityURL,
                                    clinicalTrialRegistrations: $editorState.clinicalTrialRegistrations,
                                    principalOrganizations: $editorState.principalOrganizations,
                                    dataCollections: $editorState.dataCollections,
                                    organizations: store.organizations,
                                    openOrganization: { organization in
                                        store.openRoute(for: organization)
                                    },
                                    isEditingLocked: isEditingLocked,
                                    language: language
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }

                        collapsibleDetailSection(title: language.text("Applications", "Ansökningar"), isExpanded: $applicationsExpanded) {
                            HStack(alignment: .top, spacing: 24) {
                                projectApplicationsContent(language: language)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)

                                if showsInlineStatistics {
                                    projectApplicationsCompactStatistics(language: language)
                                        .frame(width: projectInlineStatisticsWidth, alignment: .topLeading)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .id("project-applications-section")

                        collapsibleDetailSection(title: language.text("Publications", "Publikationer"), isExpanded: $publicationsExpanded) {
                            projectPublicationsContent(language: language)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        if shouldShowProjectTaskList {
                            collapsibleDetailSection(
                                title: language.text("Tasks", "Uppgifter"),
                                isExpanded: $tasksExpanded,
                                trailingActionTitle: isEditingLocked ? nil : language.text("Add task", "Lägg till uppgift"),
                                trailingAction: {
                                    CentralTaskListSection.addTask(store: store, linkKind: .project, targetID: project.id)
                                }
                            ) {
                                CentralTaskListSection(
                                    store: store,
                                    linkKind: .project,
                                    targetID: project.id,
                                    language: language,
                                    reminderOptions: ProjectTaskReminder.projectOptions,
                                    isReadOnly: isEditingLocked,
                                    showsAddButton: false
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }

                        collapsibleDetailSection(
                            title: language.text("Activities", "Aktiviteter"),
                            isExpanded: $activitiesOverviewExpanded
                        ) {
                            projectActivitiesOverviewContent(language: language)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        collapsibleDetailSection(
                            title: language.text("Protocol", "Protokoll"),
                            isExpanded: $protocolEntriesExpanded
                        ) {
                            projectProtocolContent(language: language)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .appDetailWorkspacePadding()
            }
            .sheet(isPresented: $showsAuthorExportSheet) {
                let exportTarget = project
                AuthorExportCustomSheet(
                    store: store,
                    configuration: $authorExportConfiguration,
                    exportAction: { configuration in
                        store.exportSubmissionWorkbookToDefaultLocation(for: exportTarget, configuration: configuration)
                    }
                )
            }
            .onChange(of: projectScrollTarget) { _, target in
                guard let target else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    projectScrollTarget = nil
                }
            }
        }
    }

    private func projectEditorLockButton(language: AppLanguage) -> some View {
        AppEditorLockButton(isLocked: isEditingLocked, language: language) {
            let nextValue = !isEditingLocked
            if nextValue {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            isEditingLocked = nextValue
            requestImmediatePersist()
        }
    }

    private func lockedProjectValueText(_ value: String?) -> some View {
        AppLockedFieldValueText(text: value)
    }

    private func applyProjectLifecycleModifiers<V: View>(to view: V) -> some View {
        view
            .background(AppPalette.detailPanelSurface)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                guard isActive else {
                    needsRelatedRefreshWhenActive = true
                    return
                }
                scheduleDeferredProjectSections()
                scheduleRelatedProjectDataRefresh(for: project.nameSv)
            }
            .flushPendingAutosaveOnTextEnd(requestImmediatePersist)
            .onDisappear(perform: handleProjectDisappear)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    requestImmediatePersist()
                }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    if needsRelatedRefreshWhenActive {
                        scheduleRelatedProjectDataRefresh(for: project.nameSv)
                        needsRelatedRefreshWhenActive = false
                    }
                } else {
                    needsRelatedRefreshWhenActive = true
                }
            }
            .onChange(of: activitiesOverviewExpanded) { _, expanded in
                guard expanded, isActive else { return }
                if relatedViewState.calendarEvents.isEmpty {
                    scheduleProjectCalendarEventsRefresh(delay: 0.05)
                }
            }
            // onReceive, not onChange: the subscription delivers every bump
            // even when the body does not re-evaluate around the mutation
            // (the stale-linked-list class of bug).
            .onReceive(store.$calendarContentGeneration.dropFirst()) { _ in
                guard isActive else { return }
                scheduleProjectCalendarEventsRefresh()
            }
    }

    private func applyProjectAutosaveModifiers<V: View>(to view: V) -> some View {
        view
            .onChange(of: editorState) { _, newValue in
                guard !isLoadingProjectState else { return }
                var normalized = newValue
                normalized.ethicsAmendments = normalizedEthicsAmendments(newValue.ethicsAmendments)
                normalized.principalOrganizations = normalizedPrincipalOrganizations(newValue.principalOrganizations)
                normalized.dataCollections = normalizedDataCollections(newValue.dataCollections)
                normalized.projectTasks = normalizedProjectTasks(newValue.projectTasks)
                if normalized != newValue {
                    editorState = normalized
                    return
                }
                scheduleAutosave()
            }
    }

    private func applyProjectSyncModifiers<V: View>(to view: V) -> some View {
        view
            .onChange(of: project) { oldValue, newValue in
                if oldValue.id == newValue.id {
                    // The same project changed elsewhere (undo, a calendar
                    // task, a data fix) while text typed here was not saved
                    // yet. Reloading used to throw that text away. The typed
                    // fields are saved on top of the new version instead,
                    // and the editor keeps them.
                    let localDraft = currentProjectDraft(base: oldValue)
                    if localDraft != oldValue, currentProjectDraft(base: newValue) != newValue {
                        autosaveTask?.cancel()
                        forcedPersistTask?.cancel()
                        persistAutosaveIfNeeded(baseline: newValue)
                        return
                    }
                }
                autosaveTask?.cancel()
                forcedPersistTask?.cancel()
                if oldValue.id != newValue.id {
                    persistAutosaveIfNeeded(baseline: oldValue)
                }
                loadProjectState(from: newValue)
            }
            .onReceive(store.$projectViewCacheGeneration.dropFirst()) { _ in
                scheduleRelatedProjectDataRefresh(for: project.nameSv)
            }
    }

    private func amountSummary(for applications: [GrantApplication], value keyPath: KeyPath<GrantApplication, Double?>) -> String {
        store.formattedGrantAmountSummaryInSEK(for: applications, value: keyPath)
    }

    private func projectGrantOutcomeStatisticRows(language: AppLanguage) -> [ContributorStatisticRow] {
        let relevantApplications = applications.filter { !$0.isToApplyStatus }
        guard !relevantApplications.isEmpty else { return [] }

        let snapshot = GrantOutcomeDistributionSnapshot.build(
            applications: relevantApplications,
            language: language,
            amountValue: { application, amount in
                store.grantStatisticsAmountInSEK(for: application, amount: amount)
            },
            remainingAmount: { application in
                store.effectiveRemainingGrantedAmountValue(for: application)
            }
        )

        return snapshot.segments.map { segment in
            ContributorStatisticRow(
                label: segment.kind.title(language: language),
                value: segment.amountText,
                detail: "\(segment.percentageText) • \(segment.countText)"
            )
        }
    }

    private func remainingFundsSummary(for applications: [GrantApplication]) -> String {
        CurrencyFormatter.format(
            applications.reduce(0) { total, application in
                total + store.grantStatisticsAmountInSEK(
                    for: application,
                    amount: store.effectiveRemainingGrantedAmountValue(for: application)
                )
            },
            code: "SEK",
            language: store.language
        ) + store.unconvertedAmountSuffix(
            for: applications.map { ($0, store.effectiveRemainingGrantedAmountValue(for: $0)) }
        )
    }

    private func grantedAmountDetail(for application: GrantApplication) -> String {
        let granted = store.formattedGrantAmountWithSEKApproximation(application.grantedAmountValue, for: application)
        let remaining = store.formattedGrantAmountWithSEKApproximation(store.effectiveRemainingGrantedAmountValue(for: application), for: application)
        return "\(granted) \(store.language.text("of which", "varav")) \(remaining) \(store.language.text("remains", "återstår"))"
    }

    private func dispositionStatus(for application: GrantApplication) -> String {
        if store.isEffectivelyFullySpent(application) {
            return store.language.text("0 SEK remaining to dispose", "0 kr kvar att disponera")
        }
        let remaining = store.formattedGrantAmountWithSEKApproximation(store.effectiveRemainingGrantedAmountValue(for: application), for: application)
        guard let deadline = application.lastDispositionDate ?? application.receivedUsageTo.flatMap({ DateParsers.isoDay.date(from: $0) }) else {
            return "\(remaining) \(store.language.text("remaining to dispose", "kvar att disponera"))"
        }
        let months = Calendar.current.dateComponents([.month], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: deadline)).month ?? 0
        let dateText = DateParsers.isoDay.string(from: deadline)
        if months < 0 {
            return "\(remaining) \(store.language.text("remaining to dispose by", "kvar att disponera senast")) \(dateText)"
        }
        let monthText = months == 1 ? store.language.text("in 1 month", "om 1 mån") : store.language.text("in \(months) months", "om \(months) mån")
        return "\(remaining) \(store.language.text("remaining to dispose by", "kvar att disponera senast")) \(dateText) (\(monthText))"
    }

    private func dispositionStatusColor(for application: GrantApplication) -> Color {
        // Round 16: shared disposition thresholds, readable text colours.
        if store.isEffectivelyFullySpent(application) {
            return .secondary
        }
        return AppPalette.dispositionDeadlineText(application.dispositionDeadlineDate)
    }

    private func nonGrantedWorklist(from applications: [GrantApplication]) -> [GrantApplication] {
        applications
            .filter(\.isNonGrantedForWorklists)
            .sorted {
                if $0.isToApplyStatus != $1.isToApplyStatus {
                    return $0.isToApplyStatus && !$1.isToApplyStatus
                }
                let leftDate = $0.applicationDate ?? .distantPast
                let rightDate = $1.applicationDate ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                return store.displayTitle(for: $0, language: store.language) < store.displayTitle(for: $1, language: store.language)
            }
    }

    private func publicationStatusTone(for publication: PublicationRecord) -> BadgeTone {
        BadgeTone(AppStatusTones.publication(storedStatus: publication.statusLabel))
    }

    @ViewBuilder
    private func grantedApplicationsAndTimelineContent(language: AppLanguage) -> some View {
        if isLoadingProjectDerivedData {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let timelineSnapshot = visibleProjectTimelineSnapshot
            VStack(alignment: .leading, spacing: 6) {
                if timelineSnapshot.grantBars.isEmpty
                    && timelineSnapshot.ethicsRows.isEmpty
                    && timelineSnapshot.dataCollectionRows.isEmpty
                    && timelineSnapshot.publicationMarkers.isEmpty {
                    AppCompactEmptyListLabel(title: language.text("No records", "Inga poster"))
                    projectTimelineFooter(language: language, showsLegend: false)
                } else {
                    ProjectGrantTimelineView(
                        snapshot: timelineSnapshot,
                        style: store.projectTimelineStyle,
                        language: language,
                        openAction: { bar in
                            openProjectTimelineApplication(for: bar)
                        },
                        openPublicationAction: { publicationID in
                            if let publication = store.publication(id: publicationID) {
                                store.openRoute(for: publication)
                            }
                        }
                    )
                    .equatable()
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    projectTimelineFooter(language: language, showsLegend: true)
                }
            }
        }
    }

    /// The project's export corner — the same icon strip as the publication
    /// editor: hover flags for one-click language choice, dialog for the
    /// author details.
    private func projectExportStrip(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AppTableHeaderText(text: language.text("Export", "Exportera"))

            HStack(spacing: 0) {
                ExportIconSegment(
                    systemImage: "person.2",
                    title: language.text("Author details", "Författaruppgifter"),
                    help: language.text("Export author details…", "Exportera författaruppgifter…")
                ) {
                    showsAuthorExportSheet = true
                }

                Divider().frame(height: 34)
                ExportIconSegment(
                    systemImage: "banknote",
                    title: language.text("Funding", "Finansiering"),
                    help: language.text(
                        "Copy the funding statement, largest funding first — hover for language",
                        "Kopiera funding statement, största funding först — hovra för språk"
                    ),
                    isEnabled: !grantedApplications.isEmpty,
                    flagAction: { exportProjectFundingStatement(language: $0) }
                ) {
                    exportProjectFundingStatement(language: store.language)
                }

                Divider().frame(height: 34)
                ExportIconSegment(
                    systemImage: "tablecells",
                    title: "Excel",
                    help: language.text(
                        "Export the complete project workbook — hover for language, click for the app language",
                        "Exportera komplett projektexport — hovra för språk, klicka för appens språk"
                    ),
                    flagAction: { exportProjectWorkbook(language: $0) }
                ) {
                    exportProjectWorkbook(language: store.language)
                }
            }
            .background(AppPalette.fieldSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppPalette.subtleBorder, lineWidth: 1)
            )
        }
        .fixedSize()
    }

    private func exportProjectFundingStatement(language: AppLanguage) {
        store.copyFundingStatement(
            for: grantedApplications,
            languageMode: language == .swedish ? .swedish : .english,
            sortMode: .largestFundingFirst
        )
    }

    private func exportProjectWorkbook(language: AppLanguage) {
        store.exportProjectWorkbookToDefaultLocation(for: project, language: language)
    }

    private func projectTimelineFooter(language: AppLanguage, showsLegend: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Toggle(
                language.text("Also show collaborators' grants", "Visa även medarbetares anslag"),
                isOn: $showsCollaboratorGrantsInTimeline
            )
            .appCheckboxStyle()
            .appTypography(.fieldLabel)

            Spacer(minLength: 16)

            if showsLegend {
                projectTimelineLegend(language: language)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(appFont(.secondary))
    }

    private func projectTimelineLegend(language: AppLanguage) -> some View {
        HStack(spacing: 18) {
            timelineLegendItem(
                color: projectAuxiliaryTimelineColors(),
                text: language.text("Ethics applications and data collection", "Etikansökningar och datainsamling")
            )
            timelineLegendItem(
                color: [AppPalette.timelineBarEnd, AppPalette.timelineBarStart],
                text: language.text("Granted applications", "Beviljade anslag")
            )
            timelineLegendItem(
                color: [AppPalette.timelinePendingBarEnd, AppPalette.timelinePendingBarStart],
                text: language.text("Applications awaiting decision", "Ansökningar som väntar svar")
            )
            HStack(spacing: 6) {
                Text("📄")
                    .font(.system(size: 12))
                    .frame(width: 22, height: 12)
                Text(language.text("Publications", "Publikationer"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var visibleProjectTimelineApplications: [GrantApplication] {
        showsCollaboratorGrantsInTimeline
            ? relatedViewState.orderedTimelineApplications
            : relatedViewState.orderedTimelineApplications.filter { store.isCurrentUserFirstApplicant($0) }
    }

    private var visibleProjectTimelineSnapshot: GrantDataStore.ProjectTimelineSnapshot {
        showsCollaboratorGrantsInTimeline
            ? relatedViewState.timelineSnapshot
            : relatedViewState.ownedTimelineSnapshot
    }

    private func openProjectTimelineApplication(for bar: GrantDataStore.ProjectTimelineSnapshot.GrantBar) {
        let visibleApplications = visibleProjectTimelineApplications
        guard let application = visibleApplications.first(where: { store.applicationSelectionID(for: $0) == bar.selectionID }) else {
            store.appendPerformanceDiagnostic(
                String(
                    format: "project-timeline-open-blocked project=%@ selection_id=%@ application_id=%@ bar=%@ visible_ids=%@",
                    project.nameSv,
                    bar.selectionID,
                    bar.applicationID,
                    bar.barText,
                    visibleApplications.map(\.id).joined(separator: ",")
                )
            )
            return
        }

        store.appendPerformanceDiagnostic(
            String(
                format: "project-timeline-open project=%@ application_id=%@ title=%@ bar=%@",
                project.nameSv,
                application.id,
                store.displayTitle(for: application, language: store.language),
                bar.barText
            )
        )
        // Every AppRoute carries a fresh request identity, so a repeated click
        // is observable without clearing and replaying later.  A deferred
        // replay could otherwise overwrite a newer navigation request.
        store.route = AppRoute(
            recordID: store.applicationSelectionID(for: application),
            destination: .applications
        )
    }

    private func projectAuxiliaryTimelineColors() -> [Color] {
        [AppPalette.shadeBlue, AppPalette.vividBlue]
    }

    @ViewBuilder
    private func timelineLegendItem(color: [Color], text: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(LinearGradient(colors: color, startPoint: .leading, endPoint: .trailing))
                .overlay(Rectangle().stroke(AppPalette.border, lineWidth: 0.8))
                .frame(width: 22, height: 12)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private func isAwaitingDecision(_ application: GrantApplication) -> Bool {
        let status = application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return status == "Väntar svar"
    }

    private func timelineStatusText(for application: GrantApplication) -> String {
        if application.isGranted {
            return dispositionStatus(for: application)
        }
        guard let decisionDate = application.decisionExpectedDate else {
            return store.language.text("Decision date missing", "Beslutsdatum saknas")
        }
        return "\(store.language.text("Decision expected by", "Beslut väntas senast")) \(DateParsers.isoDay.string(from: decisionDate))"
    }

    private func timelineStatusColor(for application: GrantApplication) -> Color {
        application.isGranted ? dispositionStatusColor(for: application) : AppPalette.statusText(.pending)
    }

    @ViewBuilder
    private func grantedApplicationsPanel(language: AppLanguage) -> some View {
        DetailGroup(title: language.text("Granted applications", "Beviljade anslag"), showsSurface: false) {
            VStack(alignment: .leading, spacing: 8) {
                if activeApplicationListFilter == .granted {
                    HStack(spacing: 8) {
                        Text(language.text("Filtered: ", "Filtrerat: ") + ApplicationOutcome.granted.heading(language))
                            .font(appFont(.secondary).weight(.semibold))
                            .foregroundStyle(.secondary)
                        Button(language.text("Show all", "Visa alla")) {
                            activeApplicationListFilter = .all
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppPalette.linkAction)
                        Spacer()
                    }
                }
                AppCompactReferenceList(isEmpty: grantedApplications.isEmpty, emptyTitle: language.text("No records", "Inga poster")) {
                    ForEach(grantedApplications) { application in
                        AppCompactReferenceRowButton(action: { store.openRoute(for: application) }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(application.projectTitleWithOrganization(store: store, language: language))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(dispositionStatus(for: application))
                                        .font(appFont(.secondary).weight(.medium))
                                        .foregroundStyle(dispositionStatusColor(for: application))
                                        .lineLimit(2)
                                }
                                Text(language.localizedStatus(application.resultLabel))
                                    .font(appFont(.secondary).weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(projectApplicationStatusColor(for: application))
                                    )
                            }
                        }
                        if application.id != grantedApplications.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func projectApplicationsContent(language: AppLanguage) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                if activeApplicationListFilter != .all {
                    HStack(spacing: 8) {
                        Text(filteredApplicationsLabel(language: language))
                            .font(appFont(.secondary).weight(.semibold))
                            .foregroundStyle(.secondary)
                        Button(language.text("Show all", "Visa alla")) {
                            activeApplicationListFilter = .all
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppPalette.linkAction)
                        Spacer()
                    }
                }
                if isLoadingProjectDerivedData {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    AppCompactReferenceList(isEmpty: projectApplicationsForList.isEmpty, emptyTitle: language.text("No records", "Inga poster"), rowSpacing: 0) {
                        ForEach(projectApplicationsForList) { application in
                            Button(action: { store.openRoute(for: application) }) {
                                AppLinkedStatusRow(
                                    fill: projectApplicationStatusShadeColor(for: application),
                                    help: language.localizedStatus(application.resultLabel)
                                ) {
                                    AppLinkedTitleTrailingRow(
                                        title: store.displayTitle(for: application, language: language),
                                        trailingText: projectApplicationAmountText(for: application)
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            if application.id != projectApplicationsForList.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
    }

    private func filteredApplicationsLabel(language: AppLanguage) -> String {
        switch activeApplicationListFilter {
        case .all:
            return ""
        case .awaiting:
            return language.text("Filtered: ", "Filtrerat: ") + ApplicationOutcome.awaitingDecision.heading(language)
        case .rejected:
            return language.text("Filtered: ", "Filtrerat: ") + ApplicationOutcome.declined.heading(language)
        case .granted:
            return language.text("Filtered: ", "Filtrerat: ") + ApplicationOutcome.granted.heading(language)
        }
    }

    private func grantSummaryPrimaryLine(for application: GrantApplication) -> String {
        let organization = store.organizationLabel(for: application, language: store.language)
        let amount = store.formattedGrantAmountWithSEKApproximation(
            application.isGranted ? application.grantedAmountValue : application.appliedAmountValue,
            for: application
        )
        return "\(organization), \(amount)"
    }

    private func grantSummarySecondaryLine(for application: GrantApplication) -> String {
        if application.isGranted {
            return dispositionStatus(for: application)
        }
        guard let decisionDate = application.decisionExpectedDate else {
            return store.language.text("Decision date missing", "Beslutsdatum saknas")
        }
        return "\(store.language.text("Decision expected", "Beslut väntas")) \(DateParsers.isoDay.string(from: decisionDate)) (\(monthsRemainingText(until: decisionDate)))"
    }

    private func applicationPrimaryLine(for application: GrantApplication) -> String {
        let organization = store.organizationLabel(for: application, language: store.language)
        let applied = store.formattedGrantAmountWithSEKApproximation(application.appliedAmountValue, for: application)
        let maxAmount = store.formattedGrantAmountWithSEKApproximation(GrantParsing.numericValue(from: application.maxAmount), for: application)
        if let rawMax = application.maxAmount?.trimmedOrNil, !rawMax.isEmpty, maxAmount != "—" {
            return "\(organization), \(applied) / max \(maxAmount)"
        }
        return "\(organization), \(applied)"
    }

    private func projectApplicationAmountText(for application: GrantApplication) -> String {
        let value = application.isGranted
            ? application.grantedAmountValue ?? application.appliedAmountValue
            : application.appliedAmountValue ?? application.preferredBudgetAmountValue
        return store.formattedGrantAmountWithSEKApproximation(value, for: application)
    }

    private func monthsRemainingText(until date: Date) -> String {
        let months = Calendar.current.dateComponents([.month], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).month ?? 0
        if months == 1 {
            return store.language.text("in 1 month", "om 1 mån")
        }
        return store.language.text("in \(months) months", "om \(months) mån")
    }

    @ViewBuilder
    private func projectPublicationsContent(language: AppLanguage) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                if isLoadingProjectDerivedData {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    AppCompactReferenceList(
                        isEmpty: projectPublications.isEmpty && projectConferenceContributions.isEmpty,
                        emptyTitle: language.text("No records", "Inga poster"),
                        rowSpacing: 0
                    ) {
                        ForEach(projectPublications) { publication in
                            let status = PublicationStatus.fromStored(publication.statusLabel)
                            Button(action: { store.openRoute(for: publication) }) {
                                AppLinkedStatusRow(
                                    fill: projectPublicationStatusShadeColor(for: status),
                                    help: status.displayName(language: language)
                                ) {
                                    AppLinkedTitleTrailingRow(
                                        title: publication.title,
                                        trailingText: publication.year
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            if publication.id != projectPublications.last?.id {
                                Divider()
                            }
                        }

                        if !projectConferenceContributions.isEmpty {
                            if !projectPublications.isEmpty {
                                Divider()
                            }
                            AppCompactListSectionLabel(title: language.text("Abstracts", "Abstracts"))
                            ForEach(projectConferenceContributions) { contribution in
                                Button(action: { store.openRoute(for: contribution) }) {
                                    AppLinkedStatusRow(
                                        fill: projectContributionStatusShadeColor(for: contribution.status),
                                        help: contribution.status.displayName(language: language)
                                    ) {
                                        AppLinkedTitleTrailingRow(
                                            title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                                            trailingText: contribution.publicationYear.nonEmpty ?? contribution.to.nonEmpty ?? contribution.from
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                                if contribution.id != projectConferenceContributions.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
    }

    /// Compact statistics for the project's applications: the outcome mix
    /// and, for the granted amounts, spent vs remaining.
    @ViewBuilder
    private func projectApplicationsCompactStatistics(language: AppLanguage) -> some View {
        GrantOutcomeCompactRows(store: store, applications: applications, language: language)
    }

    /// The task list plus upcoming and completed activities/tasks on the
    /// left, the compact activity statistics rows on the right.
    @ViewBuilder
    private func projectActivitiesOverviewContent(language: AppLanguage) -> some View {
        let rows = calendarLinkedEventRows(
            store: store,
            language: language,
            scope: .project(project.id),
            includesTasks: true,
            includesPastEvents: true
        )
        let todayStart = Calendar.current.startOfDay(for: Date())
        let upcoming = rows
            .filter { $0.displayDate >= todayStart }
            .sorted { $0.displayDate < $1.displayDate }
        let past = rows
            .filter { $0.displayDate < todayStart }
            .sorted { $0.displayDate > $1.displayDate }

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                if !upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        AppFieldLabelText(text: language.text("Upcoming", "Kommande"))
                        CalendarLinkedEventList(
                            store: store,
                            language: language,
                            rows: upcoming,
                            usesSingleLineRows: true,
                            usesCompactResearcherRows: true
                        )
                    }
                }

                if !past.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        AppFieldLabelText(text: language.text("Completed", "Genomförda"))
                        CalendarLinkedEventList(
                            store: store,
                            language: language,
                            rows: past,
                            usesSingleLineRows: true,
                            usesCompactResearcherRows: true
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if showsInlineStatistics, let meetingStatistics = relatedViewState.meetingStatistics {
                CalendarMeetingCompactStatisticsSection(
                    summary: meetingStatistics,
                    language: language
                )
                .frame(width: projectInlineStatisticsWidth, alignment: .topLeading)
            }
        }
    }

    /// The project's protocol entries rendered inline — same aggregation and
    /// order as the Protokoll section of the project document.
    @ViewBuilder
    private func projectProtocolContent(language: AppLanguage) -> some View {
        let entries = store.projectProtocolEntryList(for: project, language: language)
        if entries.isEmpty {
            Text(language.text(
                "No linked events or tasks have a protocol yet.",
                "Inga kopplade händelser eller uppgifter har något protokoll ännu."
            ))
            .font(appFont(.body))
            .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text([entry.dateText.nonEmpty, entry.title.nonEmpty].compactMap { $0 }.joined(separator: " – "))
                                .font(appFont(.panelTitle).weight(.bold))
                            Button {
                                store.openProtocolEntryEditor(entry.source)
                            } label: {
                                AppLinkDestinationLabel(kind: .app, language: language, fontSize: 12)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppPalette.linkAction)
                        }
                        if !entry.participantNames.isEmpty {
                            (Text(language.text("Participants: ", "Deltagare: ")).bold()
                                + Text(entry.participantNames.joined(separator: ", ")))
                                .font(appFont(.secondary))
                        }
                        ForEach(entry.linkedRecordLines, id: \.self) { line in
                            Text(line)
                                .font(appFont(.secondary))
                                .foregroundStyle(.secondary)
                        }
                        projectProtocolRichTextView(entry.protocolText)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    /// Protocol markup (bold/italic/underline, bullet levels) rendered one
    /// paragraph per row so bullet lines get a true hanging indent: wrapped
    /// lines continue under the text, not under the bullet glyph.
    @ViewBuilder
    private func projectProtocolRichTextView(_ markup: String) -> some View {
        let document = ProtocolMarkup.document(from: markup)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(document.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                let plainText = paragraph.runs.map(\.text).joined()
                if let level = ProtocolMarkup.bulletLevel(ofLine: plainText) {
                    let prefix = ProtocolMarkup.bulletPrefix(forLevel: level)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(String(prefix.trimmingCharacters(in: .whitespaces)))
                            .font(appFont(.body))
                            .frame(width: 14, alignment: .leading)
                        projectProtocolRunsText(paragraph, droppingPrefix: prefix)
                            .font(appFont(.body))
                    }
                    .padding(.leading, CGFloat(level - 1) * 14)
                } else if plainText.isEmpty {
                    // Deliberately empty paragraph — keep the blank line.
                    Text(verbatim: " ")
                        .font(appFont(.body))
                } else {
                    projectProtocolRunsText(paragraph, droppingPrefix: nil)
                        .font(appFont(.body))
                }
            }
        }
    }

    /// One paragraph's runs as concatenated Text, optionally with the bullet
    /// prefix removed from the start of the paragraph.
    private func projectProtocolRunsText(_ paragraph: CVRichTextParagraph, droppingPrefix prefix: String?) -> Text {
        var remainingPrefix = prefix ?? ""
        var result = Text(verbatim: "")
        for run in paragraph.runs {
            var runText = run.text
            if !remainingPrefix.isEmpty {
                let dropCount = min(remainingPrefix.count, runText.count)
                if runText.hasPrefix(String(remainingPrefix.prefix(dropCount))) {
                    runText = String(runText.dropFirst(dropCount))
                    remainingPrefix = String(remainingPrefix.dropFirst(dropCount))
                } else {
                    remainingPrefix = ""
                }
            }
            guard !runText.isEmpty else { continue }
            var text = Text(runText)
            if run.bold { text = text.bold() }
            if run.italic { text = text.italic() }
            if run.underline { text = text.underline() }
            result = result + text
        }
        return result
    }

    // Round 16: the shared status tones.
    private func projectApplicationStatusColor(for application: GrantApplication) -> Color {
        AppPalette.statusCapsuleFill(store.applicationStatusTone(application))
    }

    private func projectApplicationStatusShadeColor(for application: GrantApplication) -> Color? {
        AppPalette.statusRowFill(store.applicationStatusTone(application))
    }

    private func projectPublicationStatusShadeColor(for status: PublicationStatus) -> Color? {
        AppPalette.statusRowFill(AppStatusTones.publication(status))
    }

    private func projectContributionStatusShadeColor(for status: CVConferenceContributionStatus) -> Color? {
        AppPalette.statusRowFill(AppStatusTones.conferenceContribution(status))
    }

    private func projectPublicationSortOrder(_ lhs: PublicationRecord, _ rhs: PublicationRecord) -> Bool {
        let leftStatus = PublicationStatus.fromStored(lhs.statusLabel)
        let rightStatus = PublicationStatus.fromStored(rhs.statusLabel)
        let leftBucket = projectPublicationStatusBucket(for: leftStatus)
        let rightBucket = projectPublicationStatusBucket(for: rightStatus)

        if leftBucket != rightBucket {
            return leftBucket < rightBucket
        }

        switch leftBucket {
        case 0:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case 1:
            let leftDate = firstSubmittedDate(for: lhs) ?? .distantPast
            let rightDate = firstSubmittedDate(for: rhs) ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        default:
            let leftDate = publishedDate(for: lhs) ?? .distantPast
            let rightDate = publishedDate(for: rhs) ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func projectPublicationStatusBucket(for status: PublicationStatus) -> Int {
        switch status {
        case .inPreparation:
            return 0
        case .submitted:
            return 1
        default:
            return 2
        }
    }

    private func firstSubmittedDate(for publication: PublicationRecord) -> Date? {
        publication.statusTimeline
            .filter { PublicationStatus.fromStored($0.status).isSubmittedFamily }
            .compactMap { $0.date.flatMap(DateParsers.isoDay.date(from:)) }
            .min()
    }

    private func publishedDate(for publication: PublicationRecord) -> Date? {
        publication.statusTimeline
            .filter { PublicationStatus.fromStored($0.status) == .published }
            .compactMap { $0.date.flatMap(DateParsers.isoDay.date(from:)) }
            .max()
    }

    private var ethicsAuthorityURL: URL? {
        normalizedWebLinkURL(ethicsLink)
    }

    private var primaryClinicalTrialsURL: URL? {
        guard let trialID = clinicalTrialRegistrations.first(where: { !$0.trialID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trialID.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return URL(string: "https://clinicaltrials.gov/study/\(trialID)")
    }

    private func normalizedEthicsAmendments(_ amendments: [ProjectEthicsApplication]) -> [ProjectEthicsApplication] {
        let emptyRow = amendments.first(where: \.isEmpty) ?? ProjectEthicsApplication()
        return amendments.filter { !$0.isEmpty } + [emptyRow]
    }

    private func normalizedDataCollections(_ collections: [ProjectDataCollection]) -> [ProjectDataCollection] {
        let emptyRow = collections.first(where: \.isEmpty) ?? ProjectDataCollection()
        return collections.filter { !$0.isEmpty } + [emptyRow]
    }

    private func normalizedPrincipalOrganizations(_ organizations: [ProjectPrincipalOrganization]) -> [ProjectPrincipalOrganization] {
        let emptyRow = organizations.first(where: \.isEmpty) ?? ProjectPrincipalOrganization()
        return organizations.compactMap { row -> ProjectPrincipalOrganization? in
            var copy = row
            copy.normalize()
            copy = resolvedPrincipalOrganizationReference(copy)
            return copy.isEmpty ? nil : copy
        } + [emptyRow]
    }

    private func resolvedPrincipalOrganizationReference(_ principal: ProjectPrincipalOrganization) -> ProjectPrincipalOrganization {
        var copy = principal
        if let id = copy.organizationID?.trimmedOrNil,
           let organization = store.organization(id: id) {
            copy.organizationID = organization.id
            copy.organizationName = organization.displayName(for: store.language)
        } else if let organization = store.organization(matchingName: copy.organizationName) {
            copy.organizationID = organization.id
            copy.organizationName = organization.displayName(for: store.language)
        } else {
            copy.organizationID = nil
        }
        copy.normalize()
        return copy
    }

    private func normalizedProjectTasks(_ tasks: [ProjectTaskItem]) -> [ProjectTaskItem] {
        var emptyRow: ProjectTaskItem?
        let normalized = tasks.compactMap { task -> ProjectTaskItem? in
            var copy = task
            copy.normalize()
            if copy.isEmpty {
                if emptyRow == nil {
                    emptyRow = copy
                }
                return nil
            }
            return copy
        }
        return normalized + [emptyRow ?? ProjectTaskItem()]
    }

    /// The editor's fields on top of `base`, the record they belong to.
    /// Round 13: when the selection changes, `project` is already the newly
    /// selected record, so the record being left is passed in (before, the
    /// previous project got the next one's note, website and people links).
    private func currentProjectDraft(base: ProjectRecord? = nil) -> ProjectRecord {
        let project = base ?? self.project
        return ProjectRecord(
            id: project.id,
            nameSv: nameSv,
            nameEn: nameEn,
            fullNameSv: fullNameSv,
            fullNameEn: fullNameEn,
            collaboratorNames: collaboratorNames,
            collaboratorAuthorIDs: project.collaboratorAuthorIDs,
            note: project.note,
            websiteURL: project.websiteURL,
            projectStatus: projectStatus,
            hasDataCollection: hasDataCollection,
            ethicsBaseApplication: ethicsBaseApplication,
            ethicsAmendments: ethicsAmendments.filter { !$0.isEmpty },
            ethicsLink: ethicsLink.trimmedOrNil,
            clinicalTrialRegistrations: clinicalTrialRegistrations.filter { !$0.isEmpty },
            principalOrganizations: principalOrganizations.filter { !$0.isEmpty },
            dataCollections: dataCollections.filter { !$0.isEmpty },
            projectTasks: projectTasks.filter { !$0.isEmpty },
            suppressedSeedProjectTaskComments: project.suppressedSeedProjectTaskComments,
            isArchived: projectStatus == .completed,
            isEditingLocked: isEditingLocked
        )
    }

    private func loadProjectState(from project: ProjectRecord) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        isLoadingProjectState = true
        defer { isLoadingProjectState = false }
        collaboratorIdentity.reconcileExternal(project.collaboratorNames)
        editorState = ProjectEditorState(
            nameSv: project.nameSv,
            nameEn: project.nameEn,
            fullNameSv: project.fullNameSv,
            fullNameEn: project.fullNameEn,
            collaboratorNames: project.collaboratorNames,
            projectStatus: project.projectStatus,
            hasDataCollection: project.hasDataCollection,
            isEditingLocked: project.isEditingLocked,
            ethicsBaseApplication: project.ethicsBaseApplication,
            ethicsAmendments: normalizedEthicsAmendments(project.ethicsAmendments),
            ethicsLink: project.ethicsLink ?? "",
            clinicalTrialRegistrations: editableProjectClinicalTrialRegistrations(project.clinicalTrialRegistrations),
            principalOrganizations: normalizedPrincipalOrganizations(project.principalOrganizations),
            dataCollections: normalizedDataCollections(project.dataCollections),
            projectTasks: normalizedProjectTaskItems(project.projectTasks)
        )
        activeApplicationListFilter = .all
        relatedViewState = .empty(projectID: project.id)
        if isActive {
            scheduleDeferredProjectSections()
            scheduleRelatedProjectDataRefresh(for: project.nameSv)
        } else {
            needsRelatedRefreshWhenActive = true
        }
        let stateDuration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        store.appendPerformanceDiagnostic(String(format: "project-state project=%@ state_ms=%.2f", project.nameSv, stateDuration))
    }

    private func persistChanges() {
        autosaveTask?.cancel()
        let draft = currentProjectDraft()
        let currentStoredProject = store.project(id: project.id) ?? project
        guard draft != currentStoredProject else { return }
        store.autosaveProjectRecord(draft, previousID: project.id, completePendingSelection: true)
    }

    private func persistAutosaveIfNeeded(baseline: ProjectRecord) {
        let draft = currentProjectDraft(base: baseline)
        guard draft != baseline else { return }
        store.autosaveProjectRecord(draft, previousID: baseline.id, completePendingSelection: true)
    }

    private func scheduleAutosave() {
        guard !isLoadingProjectState else { return }
        autosaveTask?.cancel()
        let task = DispatchWorkItem { persistChanges() }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }

    private func requestImmediatePersist() {
        forcedPersistTask?.cancel()
        let task = DispatchWorkItem {
            persistChanges()
        }
        forcedPersistTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
    }

    private func handleProjectDisappear() {
        autosaveTask?.cancel()
        forcedPersistTask?.cancel()
        persistChanges()
    }

    private func scheduleDeferredProjectSections() {
        showsDeferredProjectSections = true
    }

    private func scheduleRelatedProjectDataRefresh(for projectName: String) {
        let projectID = project.id
        DispatchQueue.main.async {
            guard isActive, project.id == projectID else { return }
            refreshRelatedProjectData(for: projectName)
            if relatedViewState.calendarEvents.isEmpty {
                scheduleProjectCalendarEventsRefresh()
            }
        }
    }

    private func scheduleProjectCalendarEventsRefresh(delay: TimeInterval = 0.75) {
        let projectID = project.id
        calendarRefreshToken &+= 1
        let token = calendarRefreshToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isActive,
                  project.id == projectID,
                  calendarRefreshToken == token else { return }
            refreshProjectCalendarEvents()
        }
    }

    private func refreshRelatedProjectData(for projectName: String) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard isActive,
              let currentProject = store.project(id: project.id) ?? store.project(named: projectName) else { return }
        let snapshot = Self.makeRelatedViewState(
            store: store,
            project: currentProject,
            includesCalendarEvents: false
        )
        guard snapshot.projectID == project.id else { return }
        guard snapshot != relatedViewState else { return }
        relatedViewState = snapshot
        let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        store.appendPerformanceDiagnostic(
            String(
                format: "project-snapshot-ready project=%@ total_ms=%.2f applications=%ld publications=%ld grantBars=%ld",
                projectName,
                duration,
                snapshot.relatedApplications.count,
                snapshot.relatedPublications.count,
                snapshot.timelineSnapshot.grantBars.count
            )
        )
    }

    private func refreshProjectCalendarEvents() {
        let projectID = project.id
        guard isActive else { return }
        let rows = calendarLinkedEventRows(
            store: store,
            language: store.language,
            scope: .project(projectID)
        )
        var updated = relatedViewState
        updated.calendarEvents = rows
        updated.meetingStatistics = Self.projectMeetingStatistics(store: store, projectID: projectID)
        if updated != relatedViewState {
            relatedViewState = updated
        }
    }

    @MainActor
    private static func makeRelatedViewState(
        store: GrantDataStore,
        project: ProjectRecord,
        includesCalendarEvents: Bool = true
    ) -> RelatedViewState {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let projectDataStartedAt = CFAbsoluteTimeGetCurrent()
        guard let data = store.projectViewData(
            forProjectName: project.nameSv,
            language: store.language
        ) else {
            return .empty(projectID: project.id)
        }
        let projectDataDuration = (CFAbsoluteTimeGetCurrent() - projectDataStartedAt) * 1000
        let conferenceStartedAt = CFAbsoluteTimeGetCurrent()
        let conferenceContributions = store.publishedConferenceContributions(forProjectName: project.nameSv)
        let conferenceDuration = (CFAbsoluteTimeGetCurrent() - conferenceStartedAt) * 1000
        let calendarStartedAt = CFAbsoluteTimeGetCurrent()
        let calendarEvents = includesCalendarEvents
            ? calendarLinkedEventRows(
                store: store,
                language: store.language,
                scope: .project(project.id)
            )
            : []
        let calendarDuration = (CFAbsoluteTimeGetCurrent() - calendarStartedAt) * 1000
        let meetingStartedAt = CFAbsoluteTimeGetCurrent()
        let meetingStatistics = includesCalendarEvents
            ? projectMeetingStatistics(store: store, projectID: project.id)
            : nil
        let meetingDuration = (CFAbsoluteTimeGetCurrent() - meetingStartedAt) * 1000
        let result = RelatedViewState(
            projectID: project.id,
            relatedApplications: data.relatedApplications,
            relatedPublications: data.relatedPublications,
            relatedConferenceContributions: conferenceContributions,
            grantedApplications: data.grantedApplications,
            awaitingDecisionApplications: data.awaitingDecisionApplications,
            rejectedApplications: data.rejectedApplications,
            projectApplicationsForList: data.projectApplicationsForList,
            projectPublications: data.projectPublications,
            calendarEvents: calendarEvents,
            orderedTimelineApplications: data.orderedTimelineApplications,
            timelineSnapshot: data.timelineSnapshot,
            ownedTimelineSnapshot: data.ownedTimelineSnapshot,
            meetingStatistics: meetingStatistics,
            isReady: true
        )
        store.appendPerformanceDiagnostic(
            String(
                format: "project-related-state project=%@ project_data_ms=%.2f conference_ms=%.2f calendar_ms=%.2f meetings_ms=%.2f total_ms=%.2f",
                project.nameSv,
                projectDataDuration,
                conferenceDuration,
                calendarDuration,
                meetingDuration,
                (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            )
        )
        return result
    }

    @MainActor
    private static func projectMeetingStatistics(
        store: GrantDataStore,
        projectID: String
    ) -> CalendarMeetingHoursSummary {
        calendarMeetingHoursSummary(store: store, scope: .project(projectID))
    }

    nonisolated private static func projectApplicationStatusPriority(_ status: String) -> Int {
        switch status {
        case "", "Att söka":
            return 0
        case "Väntar svar":
            return 1
        case "Beviljat":
            return 2
        case "Tillbakadragen":
            return 3
        case "Avslag":
            return 4
        case "Ej sökt":
            return 5
        default:
            return 6
        }
    }

    nonisolated private static func projectPublicationSortOrder(_ lhs: PublicationRecord, _ rhs: PublicationRecord) -> Bool {
        let leftStatus = PublicationStatus.fromStored(lhs.statusLabel)
        let rightStatus = PublicationStatus.fromStored(rhs.statusLabel)
        let leftBucket = projectPublicationStatusBucket(for: leftStatus)
        let rightBucket = projectPublicationStatusBucket(for: rightStatus)

        if leftBucket != rightBucket {
            return leftBucket < rightBucket
        }

        switch leftBucket {
        case 0:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case 1:
            let leftDate = firstSubmittedDate(for: lhs) ?? .distantPast
            let rightDate = firstSubmittedDate(for: rhs) ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        default:
            let leftDate = publishedDate(for: lhs) ?? .distantPast
            let rightDate = publishedDate(for: rhs) ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    nonisolated private static func projectPublicationStatusBucket(for status: PublicationStatus) -> Int {
        switch status {
        case .inPreparation:
            return 0
        case .submitted:
            return 1
        default:
            return 2
        }
    }

    nonisolated private static func firstSubmittedDate(for publication: PublicationRecord) -> Date? {
        publication.statusTimeline
            .filter { PublicationStatus.fromStored($0.status).isSubmittedFamily }
            .compactMap { $0.date.flatMap(DateParsers.isoDay.date(from:)) }
            .min()
    }

    nonisolated private static func publishedDate(for publication: PublicationRecord) -> Date? {
        publication.statusTimeline
            .filter { PublicationStatus.fromStored($0.status) == .published }
            .compactMap { $0.date.flatMap(DateParsers.isoDay.date(from:)) }
            .max()
    }

    nonisolated private static func grantTimelineDateRange(for application: GrantApplication) -> (start: Date, end: Date)? {
        let startDate = application.firstDispositionDate ?? application.receivedUsageFrom.flatMap { DateParsers.isoDay.date(from: $0) }
        let endDate = application.lastDispositionDate ?? application.receivedUsageTo.flatMap { DateParsers.isoDay.date(from: $0) }
        guard let start = startDate ?? endDate ?? application.decisionDate ?? application.applicationDate else { return nil }
        let end = endDate ?? startDate ?? start
        return start <= end ? (start, end) : (end, start)
    }

    private var collaboratorOptions: [String] {
        store.orderedCoauthorPresentedNames()
    }

    @ViewBuilder
    private func collaboratorPickerArea(language: AppLanguage) -> some View {
        if isEditingLocked {
            lockedProjectCollaboratorList(language: language)
        } else {
            let collaboratorNameFieldWidth: CGFloat = ResearcherNameFieldMetrics.compactWidth
            let options = collaboratorOptions
            VStack(alignment: .leading, spacing: AutocompleteSelectionMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: AutocompleteSelectionMetrics.rowSpacing) {
                    ForEach(collaboratorIdentity.rows(for: collaboratorNames)) { row in
                        let index = row.index
                        HStack(spacing: 8) {
                            ReorderHandle(itemID: row.id, draggedItemID: $draggedCollaboratorName, language: language)
                            AutocompleteSelectionField(
                                text: collaboratorBinding(at: index),
                                options: options,
                                excludedOptions: Set(collaboratorNames.enumerated().compactMap { $0.offset == index ? nil : $0.element }),
                                placeholder: language.text("Select collaborator", "Välj medarbetare"),
                                addNewTitle: language.text("Add new", "Lägg till ny"),
                                display: { collaboratorLabel(for: $0, language: language) },
                                onCommit: {
                                    scheduleAutosave()
                                },
                                onAddNew: {
                                    store.beginAddingProjectCollaborator(fromProjectID: project.id, at: index)
                                }
                            )
                            .frame(width: collaboratorNameFieldWidth, alignment: .leading)

                            if let author = store.publicationAuthor(matchingPresentedName: collaboratorNames[index]) {
                                Button(action: { store.openRoute(for: author) }) {
                                    AppLinkDestinationLabel(kind: .app, language: language, fontSize: 12)
                                        .frame(width: 42, alignment: .center)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(AppPalette.linkAction)
                            } else {
                                Color.clear
                                    .frame(width: 42, height: 20)
                            }

                            inlineTrashButton {
                                collaboratorIdentity.remove(at: index)
                                collaboratorNames.remove(at: index)
                            }
                        }
                        .onDrop(of: [UTType.plainText], delegate: StableStringReorderDropDelegate(
                            targetID: row.id,
                            items: $editorState.collaboratorNames,
                            identity: collaboratorIdentity,
                            draggedItemID: $draggedCollaboratorName
                        ))
                    }
                }

                HStack(spacing: 8) {
                    Color.clear
                        .frame(width: 20, height: 20)

                    AutocompleteSelectionField(
                        text: $pendingCollaboratorName,
                        options: options,
                        excludedOptions: Set(collaboratorNames),
                        placeholder: language.text("Add collaborator", "Lägg till medarbetare"),
                        addNewTitle: language.text("Add new", "Lägg till ny"),
                        display: { collaboratorLabel(for: $0, language: language) },
                        onCommit: {
                            commitPendingCollaborator()
                        },
                        onSelect: { selectedName in
                            commitPendingCollaborator(selectedName)
                        },
                        onAddNew: {
                            store.beginAddingProjectCollaborator(fromProjectID: project.id, at: collaboratorNames.count)
                        }
                    )
                    .frame(width: collaboratorNameFieldWidth, alignment: .leading)

                    GroupMailButton(
                        addresses: store.groupMailAddresses(presentedNames: collaboratorNames),
                        language: language
                    )

                    Color.clear
                        .frame(width: 42, height: 20)

                    Color.clear
                        .frame(width: 28, height: 20)
                }

            }
        }
    }

    private func lockedProjectCollaboratorList(language: AppLanguage) -> some View {
        let collaboratorNameFieldWidth: CGFloat = ResearcherNameFieldMetrics.compactWidth
        return VStack(alignment: .leading, spacing: 2) {
            if collaboratorNames.isEmpty {
                AppCompactEmptyListLabel(title: language.text("No records", "Inga poster"))
            } else {
                ForEach(Array(collaboratorNames.enumerated()), id: \.offset) { _, name in
                    HStack(spacing: 8) {
                        AppPersonNameText(
                            name: name,
                            isCurrentUser: store.isCurrentUserPresentedName(name)
                        )
                            .frame(width: collaboratorNameFieldWidth, alignment: .leading)
                            .frame(minHeight: 18, alignment: .leading)
                        if let author = store.publicationAuthor(matchingPresentedName: name) {
                            Button(action: { store.openRoute(for: author) }) {
                                AppLinkDestinationLabel(kind: .app, language: language, fontSize: 12)
                                    .frame(width: 42, height: 18, alignment: .center)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppPalette.linkAction)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                GroupMailButton(
                    addresses: store.groupMailAddresses(presentedNames: collaboratorNames),
                    language: language
                )
            }
        }
    }

    private func inlineTrashButton(action: @escaping () -> Void) -> some View {
        AppIconDeleteButton(
            title: store.language.text("Delete", "Ta bort"),
            font: .system(size: 12, weight: .semibold),
            width: 28,
            action: action
        )
    }

    private func collaboratorBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard collaboratorNames.indices.contains(index) else { return "" }
                return collaboratorNames[index]
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if collaboratorNames.indices.contains(index) {
                    if trimmed == addNewToken {
                        store.beginAddingProjectCollaborator(fromProjectID: project.id, at: index)
                        return
                    }
                    if trimmed.isEmpty {
                        collaboratorIdentity.remove(at: index)
                        collaboratorNames.remove(at: index)
                    } else {
                        collaboratorIdentity.updateValue(at: index, to: trimmed)
                        collaboratorNames[index] = trimmed
                    }
                }
            }
        )
    }

    private func commitPendingCollaborator(_ selectedName: String? = nil) {
        let trimmed = (selectedName ?? pendingCollaboratorName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !collaboratorNames.contains(where: {
            PublicationDerivation.normalizedName($0) == PublicationDerivation.normalizedName(trimmed)
        }) else {
            pendingCollaboratorName = ""
            return
        }
        collaboratorIdentity.append(value: trimmed)
        collaboratorNames.append(trimmed)
        pendingCollaboratorName = ""
        scheduleAutosave()
    }

    private func collaboratorLabel(for name: String, language: AppLanguage) -> String {
        return name
    }

    @ViewBuilder
    private func collapsibleDetailSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        trailingActionTitle: String? = nil,
        trailingAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Color.clear
                    .frame(height: 22)
            } else {
                CollapsibleSectionHeader(
                    title: title,
                    isExpanded: isExpanded,
                    showsDivider: true,
                    trailingActionTitle: trailingActionTitle,
                    trailingAction: trailingAction
                )
            }
            if isExpanded.wrappedValue {
                content()
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                            .fill(Color.clear)
                    )
            }
        }
    }
}

private struct StatusStatisticChipModel: Identifiable {
    let id = UUID()
    let text: String
    let backgroundColor: Color
}







enum GrantOutcomeSegmentKind: CaseIterable {
    case rejected
    case waiting
    case granted

    func title(language: AppLanguage) -> String {
        switch self {
        case .rejected:
            return ApplicationOutcome.declined.heading(language)
        case .waiting:
            return ApplicationOutcome.awaitingDecision.heading(language)
        case .granted:
            return ApplicationOutcome.granted.heading(language)
        }
    }

    var startColor: Color {
        switch self {
        case .rejected:
            return AppPalette.statsCardDeclinedStart
        case .waiting:
            return AppPalette.statsCardPendingStart
        case .granted:
            return AppPalette.statsCardGrantedStart
        }
    }

    var endColor: Color {
        switch self {
        case .rejected:
            return AppPalette.statsCardDeclinedEnd
        case .waiting:
            return AppPalette.statsCardPendingEnd
        case .granted:
            return AppPalette.statsCardGrantedEnd
        }
    }
}

private struct GrantOutcomeDistributionSegment: Identifiable {
    let kind: GrantOutcomeSegmentKind
    let applications: [GrantApplication]
    let referenceAmount: Double
    let amountText: String
    let percentageText: String
    let countText: String
    let remainingText: String?

    var id: GrantOutcomeSegmentKind { kind }
}

private struct GrantOutcomeDistributionSnapshot {
    let totalRequestedAmount: Double
    let segments: [GrantOutcomeDistributionSegment]

    static func build(
        applications: [GrantApplication],
        language: AppLanguage,
        amountValue: ((GrantApplication, Double?) -> Double)? = nil,
        remainingAmount: ((GrantApplication) -> Double?)? = nil
    ) -> GrantOutcomeDistributionSnapshot {
        // "Ej sökt" has no segment here; counting its applied amount in the
        // total made the shares add up to less than 100 %.
        let relevant = applications.filter { !$0.isToApplyStatus && !$0.isNotAppliedStatus }
        let rejected = relevant.filter {
            let status = $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return status == "Avslag" || status == "Tillbakadragen"
        }
        let waiting = relevant.filter { $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "Väntar svar" }
        let granted = relevant.filter(\.isGranted)

        func resolvedAmount(_ application: GrantApplication, _ value: Double?) -> Double {
            amountValue?(application, value) ?? value ?? 0
        }

        func resolvedRemainingAmount(_ application: GrantApplication) -> Double? {
            remainingAmount?(application) ?? application.remainingGrantedAmountValue
        }

        let totalRequestedAmount = relevant.reduce(0) { $0 + resolvedAmount($1, $1.appliedAmountValue) }

        func requestedAmount(for applications: [GrantApplication]) -> Double {
            applications.reduce(0) { $0 + resolvedAmount($1, $1.appliedAmountValue) }
        }

        func amountSummary(for applications: [GrantApplication], value keyPath: KeyPath<GrantApplication, Double?>) -> String {
            let rows = applications.filter { $0[keyPath: keyPath] != nil }
            guard !rows.isEmpty else { return "—" }
            if amountValue != nil {
                return CurrencyFormatter.format(rows.reduce(0) { $0 + resolvedAmount($1, $1[keyPath: keyPath]) }, code: "SEK", language: language)
            }
            let grouped = Dictionary(grouping: rows, by: { $0.currency ?? "SEK" })
            return grouped.keys.sorted().map { currency in
                CurrencyFormatter.format(grouped[currency]?.compactMap { $0[keyPath: keyPath] }.reduce(0, +), code: currency, language: language)
            }.joined(separator: " • ")
        }

        func countText(_ count: Int) -> String {
            let label = count == 1 ? language.text("application", "ansökan") : language.text("applications", "ansökningar")
            return "\(count) \(label)"
        }

        func percentageText(for amount: Double) -> String {
            guard totalRequestedAmount > 0 else { return "0 %" }
            return "\(Int((amount / totalRequestedAmount * 100).rounded())) %"
        }

        func remainingText(for grantedApplications: [GrantApplication]) -> String? {
            let rows = grantedApplications.filter { resolvedRemainingAmount($0) != nil }
            guard !rows.isEmpty else { return nil }
            let text: String
            if amountValue != nil {
                text = CurrencyFormatter.format(rows.reduce(0) { $0 + resolvedAmount($1, resolvedRemainingAmount($1)) }, code: "SEK", language: language)
            } else {
                let grouped = Dictionary(grouping: rows, by: { $0.currency ?? "SEK" })
                text = grouped.keys.sorted().map { currency in
                    CurrencyFormatter.format(grouped[currency]?.compactMap { resolvedRemainingAmount($0) }.reduce(0, +), code: currency, language: language)
                }.joined(separator: " • ")
            }
            return language.text("Of which \(text) remains.", "Varav \(text) kvarvarande medel.")
        }

        return GrantOutcomeDistributionSnapshot(
            totalRequestedAmount: totalRequestedAmount,
            segments: [
                GrantOutcomeDistributionSegment(
                    kind: .rejected,
                    applications: rejected,
                    referenceAmount: requestedAmount(for: rejected),
                    amountText: amountSummary(for: rejected, value: \.appliedAmountValue),
                    percentageText: percentageText(for: requestedAmount(for: rejected)),
                    countText: countText(rejected.count),
                    remainingText: nil
                ),
                GrantOutcomeDistributionSegment(
                    kind: .waiting,
                    applications: waiting,
                    referenceAmount: requestedAmount(for: waiting),
                    amountText: amountSummary(for: waiting, value: \.appliedAmountValue),
                    percentageText: percentageText(for: requestedAmount(for: waiting)),
                    countText: countText(waiting.count),
                    remainingText: nil
                ),
                GrantOutcomeDistributionSegment(
                    kind: .granted,
                    applications: granted,
                    referenceAmount: requestedAmount(for: granted),
                    amountText: amountSummary(for: granted, value: \.grantedAmountValue),
                    percentageText: percentageText(for: requestedAmount(for: granted)),
                    countText: countText(granted.count),
                    remainingText: remainingText(for: granted)
                )
            ]
        )
    }
}

struct GrantOutcomeDistributionCard: View {
    let applications: [GrantApplication]
    let language: AppLanguage
    var amountValue: ((GrantApplication, Double?) -> Double)? = nil
    var remainingAmount: ((GrantApplication) -> Double?)? = nil
    var applicationTitle: ((GrantApplication) -> String)? = nil
    var compactAmountOnly = false
    var showsFooter = true
    var segmentTapAction: ((GrantOutcomeSegmentKind) -> Void)? = nil

    private var segmentHeight: CGFloat { showsFooter ? 52 : 38 }

    private var snapshot: GrantOutcomeDistributionSnapshot {
        GrantOutcomeDistributionSnapshot.build(
            applications: applications,
            language: language,
            amountValue: amountValue,
            remainingAmount: remainingAmount
        )
    }

    var body: some View {
        let segments = snapshot.segments
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let totalWidth = max(proxy.size.width, 1)
                let segmentWidths = widths(totalWidth: totalWidth)
                let contentWidth = max(totalWidth, segmentWidths.reduce(0, +))

                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            segmentView(segment, showsTrailingDivider: index < segments.count - 1)
                                .frame(width: segmentWidths[index], height: segmentHeight)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppPalette.border, lineWidth: 1)
                )
            }
            .frame(height: segmentHeight)

        }
    }

    private func widths(totalWidth: CGFloat) -> [CGFloat] {
        guard !snapshot.segments.isEmpty else { return [] }
        let count = snapshot.segments.count
        let minimumWidths = snapshot.segments.map(minimumReadableWidth(for:))
        let minimumTotalWidth = minimumWidths.reduce(0, +)

        guard snapshot.totalRequestedAmount > 0 else {
            if totalWidth >= minimumTotalWidth {
                let evenWidth = totalWidth / CGFloat(count)
                return minimumWidths.map { max(evenWidth, $0) }
            }
            return minimumWidths
        }

        let proportionalWidths = snapshot.segments.map { segment in
            totalWidth * CGFloat(segment.referenceAmount / snapshot.totalRequestedAmount)
        }

        guard totalWidth >= minimumTotalWidth else {
            return zip(proportionalWidths, minimumWidths).map { max($0.0, $0.1) }
        }

        var widths = minimumWidths
        let extraSpace = totalWidth - minimumTotalWidth
        let extraNeeds = zip(proportionalWidths, minimumWidths).map { max($0.0 - $0.1, 0) }
        let totalExtraNeed = extraNeeds.reduce(0, +)

        guard totalExtraNeed > 0, extraSpace > 0 else {
            return widths
        }

        for index in widths.indices {
            widths[index] += extraSpace * (extraNeeds[index] / totalExtraNeed)
        }
        return widths
    }

    private func minimumReadableWidth(for segment: GrantOutcomeDistributionSegment) -> CGFloat {
        if compactAmountOnly {
            let horizontalPadding: CGFloat = 28
            let amountWidth = measuredWidth("\(segment.amountText) (\(segment.percentageText))", size: 11, weight: .bold)
            return max(amountWidth + horizontalPadding, 140)
        }

        let horizontalPadding: CGFloat = 20
        let titleWidth = measuredWidth(segment.kind.title(language: language), size: 12, weight: .semibold)
        let amountWidth = measuredWidth("\(segment.amountText) (\(segment.percentageText))", size: 11, weight: .bold)
        let footerWidth = showsFooter ? measuredWidth(footerText(for: segment), size: 11, weight: .medium) : 0
        let measuredMinimum = max(titleWidth, amountWidth, footerWidth) + horizontalPadding
        let floorWidth: CGFloat
        switch segment.kind {
        case .rejected, .waiting:
            floorWidth = 160
        case .granted:
            floorWidth = 200
        }
        return max(measuredMinimum, floorWidth)
    }

    private func measuredWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    @ViewBuilder
    private func segmentView(_ segment: GrantOutcomeDistributionSegment, showsTrailingDivider: Bool) -> some View {
        if let action = segmentTapAction {
            Button(action: { action(segment.kind) }) {
                segmentContent(segment, showsTrailingDivider: showsTrailingDivider)
            }
            .buttonStyle(.plain)
            .help(hoverText(for: segment))
        } else {
            segmentContent(segment, showsTrailingDivider: showsTrailingDivider)
                .help(hoverText(for: segment))
        }
    }

    private func segmentContent(_ segment: GrantOutcomeDistributionSegment, showsTrailingDivider: Bool) -> some View {
        segmentLabel(segment)
            .padding(.horizontal, 12)
            .padding(.vertical, compactAmountOnly ? 4 : 6)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(
                LinearGradient(
                    colors: [segment.kind.startColor, segment.kind.endColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .trailing) {
                if showsTrailingDivider {
                    Rectangle()
                        .fill(AppPalette.border.opacity(0.65))
                        .frame(width: 1)
                }
            }
    }

    @ViewBuilder
    private func segmentLabel(_ segment: GrantOutcomeDistributionSegment) -> some View {
        if compactAmountOnly {
            Text("\(segment.amountText) (\(segment.percentageText))")
                .font(appFont(.secondary).weight(.bold))
                .foregroundStyle(AppPalette.semanticOnColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            VStack(alignment: .center, spacing: 0) {
                Text(segment.kind.title(language: language))
                    .font(appFont(.secondary).weight(.semibold))
                    .foregroundStyle(AppPalette.semanticOnColor.opacity(0.92))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("\(segment.amountText) (\(segment.percentageText))")
                    .font(appFont(.secondary).weight(.bold))
                    .foregroundStyle(AppPalette.semanticOnColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .center)

                if showsFooter {
                    Text(footerText(for: segment))
                        .font(appFont(.secondary).weight(.medium))
                        .foregroundStyle(AppPalette.semanticOnColor.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private func footerText(for segment: GrantOutcomeDistributionSegment) -> String {
        if let remainingText = segment.remainingText, !remainingText.isEmpty {
            return "\(segment.countText) · \(remainingText)"
        }
        return segment.countText
    }

    private func hoverText(for segment: GrantOutcomeDistributionSegment) -> String {
        var lines = [
            segment.kind.title(language: language),
            "\(segment.amountText) (\(segment.percentageText))"
        ]

        if segment.kind == .granted, let remainingText = segment.remainingText?.nonEmpty {
            lines.append(remainingText)
        }

        if segment.applications.isEmpty {
            lines.append(language.text("No grants in this category.", "Inga anslag i den här kategorin."))
        } else {
            lines.append(language.text("Included grants:", "Anslag som ingår:"))
            lines += segment.applications
                .sorted {
                    resolvedApplicationTitle($0).localizedStandardCompare(resolvedApplicationTitle($1)) == .orderedAscending
                }
                .map { "- \(resolvedApplicationTitle($0))" }
        }

        return lines.joined(separator: "\n")
    }

    private func resolvedApplicationTitle(_ application: GrantApplication) -> String {
        if let title = applicationTitle?(application).nonEmpty {
            return title
        }
        if let title = application.localizedGrantName(language: language).nonEmpty {
            return title
        }
        if let title = application.displayTitle.nonEmpty {
            return title
        }
        return language.text("Untitled grant", "Namnlöst anslag")
    }
}

func normalizedProjectTaskItems(_ tasks: [ProjectTaskItem]) -> [ProjectTaskItem] {
    let sortedTasks = tasks
        .map {
            var copy = $0
            copy.normalize()
            return copy
        }
        .filter { !$0.isEmpty }
        .sorted { lhs, rhs in
            let leftDeadline = DateParsers.isoDay.date(from: lhs.deadline)
            let rightDeadline = DateParsers.isoDay.date(from: rhs.deadline)

            switch (leftDeadline, rightDeadline) {
            case let (left?, right?):
                if left != right {
                    return left < right
                }
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                let leftReminderRank = projectTaskReminderSortRank(lhs.reminder)
                let rightReminderRank = projectTaskReminderSortRank(rhs.reminder)
                if leftReminderRank != rightReminderRank {
                    return leftReminderRank < rightReminderRank
                }
            }

            let leftUpdated = DateParsers.isoDay.date(from: lhs.updatedOn)
                ?? DateParsers.isoDay.date(from: lhs.createdOn)
                ?? .distantPast
            let rightUpdated = DateParsers.isoDay.date(from: rhs.updatedOn)
                ?? DateParsers.isoDay.date(from: rhs.createdOn)
                ?? .distantPast
            if leftUpdated != rightUpdated {
                return leftUpdated > rightUpdated
            }

            let leftComment = lhs.comment.trimmingCharacters(in: .whitespacesAndNewlines)
            let rightComment = rhs.comment.trimmingCharacters(in: .whitespacesAndNewlines)
            let comparison = leftComment.localizedStandardCompare(rightComment)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }

            return lhs.id < rhs.id
        }

    let activeTasks = sortedTasks.filter { !$0.isCompleted }
    let completedTasks = sortedTasks.filter { $0.isCompleted }
    return activeTasks + completedTasks + [ProjectTaskItem()]
}

private func projectTaskReminderSortRank(_ reminder: ProjectTaskReminder?) -> Int {
    switch reminder ?? .none {
    case .newFundsReceived:
        return 0
    case .dataCollectionCompleted:
        return 1
    case .publicationAdded:
        return 2
    case .publicationPublished:
        return 3
    case .fundsRunOut:
        return 4
    case .manualFollowUp:
        return 5
    case .grantCallOpens:
        return 6
    case .applicationDeadline:
        return 7
    case .decisionDate:
        return 8
    case .reportingDeadline:
        return 9
    case .finalReportDeadline:
        return 10
    case .fundsReceived:
        return 11
    case .internalBudgetDeadline:
        return 12
    case .projectEndDate:
        return 13
    case .employmentStart:
        return 14
    case .employmentEnd:
        return 15
    case .budgetPeriodStart:
        return 16
    case .budgetPeriodEnd:
        return 17
    case .salaryRevisionDate:
        return 18
    case .termStart:
        return 19
    case .termEnd:
        return 20
    case .courseStart:
        return 21
    case .courseEnd:
        return 22
    case .examinationDate:
        return 23
    case .congressStart:
        return 24
    case .congressEnd:
        return 25
    case .abstractDeadline:
        return 26
    case .lateAbstractDeadline:
        return 27
    case .membershipStart:
        return 28
    case .membershipEnd:
        return 29
    case .annualMeetingDate:
        return 30
    case .none:
        return 31
    }
}

private extension ProjectLifecycleStatus {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .planned:
            return fixedDropdownText("projectLifecycle.planned", language: language, english: "Planned", swedish: "Planerat")
        case .ongoing:
            return fixedDropdownText("projectLifecycle.ongoing", language: language, english: "Ongoing", swedish: "Pågående")
        case .completed:
            return fixedDropdownText("projectLifecycle.completed", language: language, english: "Completed", swedish: "Avslutat")
        }
    }
}

extension ProjectEthicsApplication {
    func ethicsStatusLabel(language: AppLanguage) -> String {
        if grantedOn.nonEmpty != nil {
            return language.text("Approved", "Godkänd")
        }
        if appliedOn.nonEmpty != nil {
            return language.text("Applied", "Ansökt")
        }
        return "—"
    }
}

private extension Array where Element == ProjectDataCollection {
    func statusLabel(language: AppLanguage) -> String {
        let latestStarted = self
            .compactMap { collection -> (Date, ProjectDataCollection)? in
                guard let start = collection.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) else { return nil }
                return (start, collection)
            }
            .max { $0.0 < $1.0 }?
            .1

        guard let latestStarted else {
            return ""
        }
        return latestStarted.to.nonEmpty != nil
            ? language.text("Completed", "Slutförd")
            : language.text("Ongoing", "Pågående")
    }
}

extension ProjectDataCollection {
    func statusLabel(language: AppLanguage) -> String {
        let hasFrom = from.nonEmpty != nil
        let hasTo = to.nonEmpty != nil

        guard hasFrom || hasTo else {
            return ""
        }
        if hasTo {
            return language.text("Completed", "Slutförd")
        }
        return language.text("Ongoing", "Pågående")
    }
}

extension ProjectTaskReminder {
    static let projectOptions: [ProjectTaskReminder] = [
        .none,
        .dataCollectionCompleted,
        .publicationAdded,
        .newFundsReceived,
        .fundsRunOut,
        .publicationPublished
    ]

    static func organizationOptions(for roles: Set<OrganizationRole>) -> [ProjectTaskReminder] {
        var options: [ProjectTaskReminder] = [.none, .manualFollowUp]

        if roles.contains(.grantProvider) {
            options += [.grantCallOpens, .applicationDeadline, .decisionDate, .reportingDeadline, .finalReportDeadline]
        }
        if roles.contains(.fundManager) {
            options += [.fundsReceived, .internalBudgetDeadline, .reportingDeadline, .finalReportDeadline, .projectEndDate]
        }
        if roles.contains(.employer) {
            options += [.employmentStart, .employmentEnd, .budgetPeriodStart, .budgetPeriodEnd, .salaryRevisionDate]
        }
        if roles.contains(.institution) {
            options += [.termStart, .termEnd, .courseStart, .courseEnd, .examinationDate]
        }
        if roles.contains(.association) {
            options += [.congressStart, .congressEnd, .abstractDeadline, .lateAbstractDeadline, .membershipStart, .membershipEnd, .annualMeetingDate]
        }

        var seen = Set<ProjectTaskReminder>()
        return options.filter { seen.insert($0).inserted }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .none:
            return fixedDropdownText("projectReminder.none", language: language, english: "None", swedish: "Ingen")
        case .dataCollectionCompleted:
            return fixedDropdownText("projectReminder.dataCollectionCompleted", language: language, english: "When data collection is completed", swedish: "När datainsamling är avslutad")
        case .publicationAdded:
            return fixedDropdownText("projectReminder.publicationAdded", language: language, english: "When a publication is added", swedish: "När publikation läggs till")
        case .newFundsReceived:
            return fixedDropdownText("projectReminder.newFundsReceived", language: language, english: "When new funds are received", swedish: "När nya medel erhålls")
        case .fundsRunOut:
            return fixedDropdownText("projectReminder.fundsRunOut", language: language, english: "When funds run out", swedish: "När medel tar slut")
        case .publicationPublished:
            return fixedDropdownText("projectReminder.publicationPublished", language: language, english: "When a publication is published", swedish: "När publikation publiceras")
        case .manualFollowUp:
            return fixedDropdownText("projectReminder.manualFollowUp", language: language, english: "Manual follow-up", swedish: "Följ upp manuellt")
        case .grantCallOpens:
            return fixedDropdownText("projectReminder.grantCallOpens", language: language, english: "Grant call opens", swedish: "Utlysning öppnar")
        case .applicationDeadline:
            return fixedDropdownText("projectReminder.applicationDeadline", language: language, english: "Application deadline", swedish: "Ansökningsdeadline")
        case .decisionDate:
            return fixedDropdownText("projectReminder.decisionDate", language: language, english: "Decision date", swedish: "Beslutsdatum")
        case .reportingDeadline:
            return fixedDropdownText("projectReminder.reportingDeadline", language: language, english: "Reporting deadline", swedish: "Rapporteringsdeadline")
        case .finalReportDeadline:
            return fixedDropdownText("projectReminder.finalReportDeadline", language: language, english: "Final reporting deadline", swedish: "Slutredovisningsdeadline")
        case .fundsReceived:
            return fixedDropdownText("projectReminder.fundsReceived", language: language, english: "Funds received", swedish: "Medel mottagna")
        case .internalBudgetDeadline:
            return fixedDropdownText("projectReminder.internalBudgetDeadline", language: language, english: "Internal budget deadline", swedish: "Intern budgetdeadline")
        case .projectEndDate:
            return fixedDropdownText("projectReminder.projectEndDate", language: language, english: "Project end date", swedish: "Projekt slutdatum")
        case .employmentStart:
            return fixedDropdownText("projectReminder.employmentStart", language: language, english: "Employment start", swedish: "Anställningsstart")
        case .employmentEnd:
            return fixedDropdownText("projectReminder.employmentEnd", language: language, english: "Employment end", swedish: "Anställningsslut")
        case .budgetPeriodStart:
            return fixedDropdownText("projectReminder.budgetPeriodStart", language: language, english: "Budget period start", swedish: "Budgetperiod start")
        case .budgetPeriodEnd:
            return fixedDropdownText("projectReminder.budgetPeriodEnd", language: language, english: "Budget period end", swedish: "Budgetperiod slut")
        case .salaryRevisionDate:
            return fixedDropdownText("projectReminder.salaryRevisionDate", language: language, english: "Salary revision date", swedish: "Lönerevision datum")
        case .termStart:
            return fixedDropdownText("projectReminder.termStart", language: language, english: "Term start", swedish: "Terminsstart")
        case .termEnd:
            return fixedDropdownText("projectReminder.termEnd", language: language, english: "Term end", swedish: "Terminsslut")
        case .courseStart:
            return fixedDropdownText("projectReminder.courseStart", language: language, english: "Course start", swedish: "Kursstart")
        case .courseEnd:
            return fixedDropdownText("projectReminder.courseEnd", language: language, english: "Course end", swedish: "Kursavslut")
        case .examinationDate:
            return fixedDropdownText("projectReminder.examinationDate", language: language, english: "Examination date", swedish: "Examinationsdatum")
        case .congressStart:
            return fixedDropdownText("projectReminder.congressStart", language: language, english: "Congress start", swedish: "Kongress start")
        case .congressEnd:
            return fixedDropdownText("projectReminder.congressEnd", language: language, english: "Congress end", swedish: "Kongress slut")
        case .abstractDeadline:
            return fixedDropdownText("projectReminder.abstractDeadline", language: language, english: "Abstract deadline", swedish: "Abstractdeadline")
        case .lateAbstractDeadline:
            return fixedDropdownText("projectReminder.lateAbstractDeadline", language: language, english: "Late abstract deadline", swedish: "Sen abstractdeadline")
        case .membershipStart:
            return fixedDropdownText("projectReminder.membershipStart", language: language, english: "Membership start", swedish: "Medlemskap start")
        case .membershipEnd:
            return fixedDropdownText("projectReminder.membershipEnd", language: language, english: "Membership end", swedish: "Medlemskap slut")
        case .annualMeetingDate:
            return fixedDropdownText("projectReminder.annualMeetingDate", language: language, english: "Annual meeting date", swedish: "Årsmötesdatum")
        }
    }

    func displayName(language: AppLanguage, marksUncertainDate: Bool) -> String {
        let base = displayName(language: language)
        guard marksUncertainDate else { return base }
        return "\(base) (\(language.text("uncertain date", "osäkert datum")))"
    }

    static func uncertainOrganizationReminderOptions(in congresses: [OrganizationCongress]) -> Set<ProjectTaskReminder> {
        var options = Set<ProjectTaskReminder>()
        for congress in congresses {
            if congress.from.trimmedOrNil != nil, congress.fromUncertain {
                options.insert(.congressStart)
            }
            if congress.to.trimmedOrNil != nil, congress.toUncertain {
                options.insert(.congressEnd)
            }
            if congress.abstractSubmissionDeadline.trimmedOrNil != nil, congress.abstractSubmissionDeadlineUncertain {
                options.insert(.abstractDeadline)
            }
            if congress.lateAbstractSubmissionDeadline.trimmedOrNil != nil, congress.lateAbstractSubmissionDeadlineUncertain {
                options.insert(.lateAbstractDeadline)
            }
        }
        return options
    }

    func dependencySubtitle(language: AppLanguage) -> String? {
        guard self != .none else { return nil }
        let text = displayName(language: language)
        guard let firstCharacter = text.first else { return nil }
        return firstCharacter.lowercased() + text.dropFirst()
    }
}
