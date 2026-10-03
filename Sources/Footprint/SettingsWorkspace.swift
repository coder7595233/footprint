import AppKit
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

private enum SettingsWorkspaceSection: String, CaseIterable, Identifiable {
    case appearance
    case homeOrganization
    case calendar
    case applications
    case export
    case data
    case listFilters
    case translations
    case mediaLanguages
    case teachingTerminology
    case researcherLists

    var id: String { rawValue }
}

private struct EditableCalendarMeetingCategory: Identifiable, Hashable {
    let id: String = UUID().uuidString
    var originalName: String? = nil
    var name: String = ""
    var lightColorHex: String = "#000000"
    var darkColorHex: String = "#000000"
    var colorSourceID: String?
    /// "Do not count in meeting statistics", "Clinical time" and "Leave".
    var excludedFromMeetingStatistics: Bool = false
    var isClinicalTime: Bool = false
    var isLeave: Bool = false
}

private struct EditableCalendarCategoryColors: Hashable {
    var lightHex: String = "#000000"
    var darkHex: String = "#000000"
}

private struct EditableCalendarDayHighlightColors: Hashable {
    var lightTextHex: String = "#000000"
    var lightBackgroundHex: String = "#000000"
    var darkTextHex: String = "#000000"
    var darkBackgroundHex: String = "#000000"
}

private struct PendingCalendarMeetingCategoryDeletion: Identifiable, Hashable {
    var id: String { rowID }
    let rowID: String
    let sourceCategoryName: String
    let usageCount: Int
    var replacementCategoryName: String = ""
}

private enum CalendarDayHighlightColorRole {
    case text
    case background
}

struct SettingsWorkspaceView: View {
    @ObservedObject var store: GrantDataStore
    let dismiss: () -> Void

    @State private var selectedSection: SettingsWorkspaceSection = .appearance
    @State private var copyExportEnabled = FootprintExportWriter.isSwitchedOn
    @State private var copyExportFolderPath = FootprintExportWriter.chosenFolder?.path ?? ""
    @State private var lightModeStartsAt: String = ""
    @State private var darkModeStartsAt: String = ""
    @State private var selectedHolidayCountries: Set<HolidayCountry> = []
    @State private var selectedCalendarWeekday: CalendarWeekdayChoice = .monday
    @State private var selectedCalendarCountryDisplayMode: CalendarCountryDisplayMode = .flags
    @State private var calendarUsesCompactEventColorBands = false
    @State private var calendarUsesCompactDayHighlightBands = false
    @State private var calendarTaskRemindersEnabled = false
    @State private var reminderSettings: CalendarReminderSettings = .standard
    @State private var workingHours: CalendarWorkingHoursSettings = .standard
    @State private var homeCountry: String = HomeOrganizationDefaults.homeCountry
    @State private var homeRegionOrganizationID: String = ""
    @State private var defaultFundManagerOrganizationID: String = ""
    /// The values shown when the window opened; home organization settings
    /// are stored only when one of them is changed.
    @State private var loadedHomeOrganizationValues: [String] = []
    @State private var loadedCalendarCategoryBehaviors: [CalendarCategoryBehaviorSetting] = []
    @State private var listFilterRetentionPreferences: [String: Bool] = [:]
    @State private var dropdownTranslationsSv: [String: String] = [:]
    @State private var dropdownTranslationsEn: [String: String] = [:]
    @State private var customMediaLanguageOptions: [MediaLanguageOption] = []
    @State private var newMediaLanguageCode = ""
    @State private var newMediaLanguageNameSv = ""
    @State private var newMediaLanguageNameEn = ""
    @State private var appChromeScheme: AppChromeScheme = .standard
    @State private var appChromeColors: AppChromeColorSettings = .builtIn
    @State private var typographySettings: AppTypographySettings = .default
    @State private var lightSemanticColors: AppSemanticColorSettings = .default
    @State private var darkSemanticColors: AppSemanticColorSettings = .darkDefault
    @State private var calendarDayHighlightColors: [CalendarDayHighlightKind: EditableCalendarDayHighlightColors] = [:]
    @State private var calendarDayHighlightColorPresets: [CalendarDayHighlightColorPreset] = []
    @State private var selectedCalendarDayHighlightColorPresetID: String = ""
    @State private var fixedCalendarCategoryColors: [CalendarFixedCategory: EditableCalendarCategoryColors] = [:]
    @State private var activityCategoryColors: [CalendarActivityColorRole: EditableCalendarCategoryColors] = [:]
    @State private var defaultNewActivityCategoryColors: EditableCalendarCategoryColors = .init(
        lightHex: AppSemanticColorSettings.default.neutral.solidHex,
        darkHex: AppSemanticColorSettings.darkDefault.neutral.solidHex
    )
    @State private var editableCalendarMeetingCategories: [EditableCalendarMeetingCategory] = []
    @State private var calendarCategoryColorPresets: [CalendarCategoryColorPreset] = []
    @State private var selectedCalendarCategoryColorPresetID: String = ""
    @State private var lightSemanticColorPresets: [AppSemanticColorPreset] = []
    @State private var selectedLightSemanticColorPresetID: String = ""
    @State private var darkSemanticColorPresets: [AppSemanticColorPreset] = []
    @State private var selectedDarkSemanticColorPresetID: String = ""
    @State private var backupSnapshots: [GrantDataStore.BackupSnapshot] = []
    @State private var selectedBackupURL: URL?
    @State private var selectedBackupPreview: String = ""
    @State private var backupHealthSummaryText: String = ""
    @State private var performanceDiagnosticsSummaryText: String = ""
    @State private var performanceDiagnosticsStatusItems: [GrantDataStore.PerformanceDiagnosticsStatusItem] = []
    @State private var pendingRestoreBackupURL: URL?
    @State private var restoreConfirmationAcknowledged = false
    @State private var pendingCalendarMeetingCategoryDeletion: PendingCalendarMeetingCategoryDeletion?
    @State private var autosaveTask: DispatchWorkItem?
    @FocusState private var focusedCalendarMeetingCategoryID: String?
    private let translationUsageColumnWidth: CGFloat = 300
    private let legacyCustomCalendarCategoryColorSourceID = "__custom-saved-color__"
    private let semanticToneColumnWidth: CGFloat = 170
    private let semanticFieldColumnWidth: CGFloat = 154
    private let semanticMatrixHeaderHeight: CGFloat = 34
    private let semanticMatrixRowHeight: CGFloat = 42

    private var translationSections: [(title: String, items: [DropdownTranslationDefinition])] {
        let grouped = Dictionary(grouping: editableDropdownTranslationDefinitions.filter { !$0.shouldLiveInTeachingTerminology }) {
            store.language == .english ? $0.sectionEn : $0.sectionSv
        }
        return grouped.keys.sorted().map { ($0, grouped[$0]?.sorted { $0.labelEn.localizedStandardCompare($1.labelEn) == .orderedAscending } ?? []) }
    }

    private var visibleTeachingTerminologyDefinitions: [DropdownTranslationDefinition] {
        editableDropdownTranslationDefinitions.filter(\.shouldLiveInTeachingTerminology).filter {
            !$0.key.hasPrefix("teachingRole.")
                && !$0.key.hasPrefix("teachingKind.")
                && !$0.key.hasPrefix("teachingContext.")
                && !$0.key.hasPrefix("teachingReport.")
        }
    }

    private var teachingTerminologySections: [(title: String, items: [DropdownTranslationDefinition])] {
        let definitions = visibleTeachingTerminologyDefinitions
        let grouped = Dictionary(grouping: definitions) { definition in
            switch true {
            case definition.key.hasPrefix("teachingRole."):
                return store.language.text("Teaching roles", "Undervisningsroller")
            case definition.key.hasPrefix("teachingParticipant."):
                return store.language.text("Participant forms", "Deltagarformer")
            case definition.key.hasPrefix("teachingDelivery."):
                return store.language.text("Delivery modes", "Genomförandeformer")
            default:
                return store.language.text("Teaching", "Undervisning")
            }
        }
        return grouped.keys.sorted().map { ($0, grouped[$0]?.sorted { $0.labelEn.localizedStandardCompare($1.labelEn) == .orderedAscending } ?? []) }
    }

    var body: some View {
        let language = store.language

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(language.text("Preferences", "Inställningar"))
                    .appTypography(.pageTitle)

                ForEach(SettingsWorkspaceSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        HStack {
                            Text(title(for: section, language: language))
                                .appTypography(.panelTitle)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .appSelectableOptionSurface(
                            isSelected: selectedSection == section,
                            fill: Color.clear,
                            selectedFill: AppPalette.activeTabSurface.opacity(0.18),
                            stroke: Color.clear,
                            selectedStroke: AppPalette.activeTabSurface.opacity(0.36),
                            cornerRadius: 10,
                            padding: 0
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(language.text("Close", "Stäng"), action: dismiss)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            .frame(width: 240, alignment: .topLeading)
            .background(AppPalette.cardSurface)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedSection {
                    case .appearance:
                        appearanceSection(language: language)
                    case .homeOrganization:
                        homeOrganizationSection(language: language)
                    case .calendar:
                        calendarSection(language: language)
                    case .applications:
                        WorkflowDefaultSettingsPanel(store: store, part: .applications)
                    case .export:
                        exportSection(language: language)
                    case .data:
                        dataSection(language: language)
                    case .listFilters:
                        listFilterSection(language: language)
                    case .translations:
                        translationsSection(language: language)
                    case .mediaLanguages:
                        mediaLanguagesSection(language: language)
                    case .teachingTerminology:
                        teachingTerminologySection(language: language)
                    case .researcherLists:
                        ResearcherOptionListsSettingsPanel(store: store)
                    }
                }
                .padding(20)
            }
        }
        .frame(
            minWidth: AppResponsiveLayout.settingsMinimumWidth,
            idealWidth: 1260,
            maxWidth: .infinity,
            minHeight: AppResponsiveLayout.settingsMinimumHeight,
            idealHeight: 860,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .onAppear {
            lightModeStartsAt = store.lightModeStartsAt
            darkModeStartsAt = store.darkModeStartsAt
            selectedHolidayCountries = Set(store.holidayCountries)
            selectedCalendarWeekday = store.calendarWeekdayChoice
            selectedCalendarCountryDisplayMode = store.calendarCountryDisplayMode
            calendarUsesCompactEventColorBands = store.calendarUsesCompactEventColorBands
            calendarUsesCompactDayHighlightBands = store.calendarUsesCompactDayHighlightBands
            calendarTaskRemindersEnabled = UserDefaults.standard.bool(
                forKey: AppRuntime.calendarTaskRemindersEnabledDefaultsKey
            )
            reminderSettings = store.calendarReminderSettings
            workingHours = store.calendarWorkingHours
            homeCountry = store.homeCountryName
            homeRegionOrganizationID = store.homeRegionOrganizationID ?? ""
            defaultFundManagerOrganizationID = store.defaultFundManagerOrganizationID ?? ""
            loadedHomeOrganizationValues = [homeCountry, homeRegionOrganizationID, defaultFundManagerOrganizationID]
            listFilterRetentionPreferences = store.listFilterRetentionPreferenceSnapshot()
            dropdownTranslationsSv = Dictionary(firstWinsKeysWithValues: editableDropdownTranslationDefinitions.map {
                ($0.key, store.dropdownTranslationText(for: $0, language: .swedish))
            })
            dropdownTranslationsEn = Dictionary(firstWinsKeysWithValues: editableDropdownTranslationDefinitions.map {
                ($0.key, store.dropdownTranslationText(for: $0, language: .english))
            })
            customMediaLanguageOptions = store.editableMetadataSnapshot.mediaLanguageOptions ?? []
            appChromeScheme = store.appChromeScheme
            appChromeColors = store.appChromeColorSettings
            typographySettings = store.appTypographySettings
            lightSemanticColors = store.appSemanticColorSettingsLight
            darkSemanticColors = store.appSemanticColorSettingsDark
            loadCalendarDayHighlightSettings()
            loadCalendarCategorySettings()
            loadColorPresetSettings()
            reloadBackupCenterState()
            refreshPerformanceDiagnosticsStatus()
        }
        .onChange(of: lightModeStartsAt) { _, _ in scheduleAutosave() }
        .onChange(of: darkModeStartsAt) { _, _ in scheduleAutosave() }
        .onChange(of: selectedHolidayCountries) { _, _ in scheduleAutosave() }
        .onChange(of: selectedCalendarWeekday) { _, _ in scheduleAutosave() }
        .onChange(of: selectedCalendarCountryDisplayMode) { _, _ in scheduleAutosave() }
        .onChange(of: calendarUsesCompactEventColorBands) { _, _ in scheduleAutosave() }
        .onChange(of: calendarUsesCompactDayHighlightBands) { _, _ in scheduleAutosave() }
        .onChange(of: customMediaLanguageOptions) { _, _ in scheduleAutosave() }
        .onChange(of: reminderSettings) { _, _ in scheduleAutosave() }
        .onChange(of: homeCountry) { _, _ in scheduleAutosave() }
        .onChange(of: homeRegionOrganizationID) { _, _ in scheduleAutosave() }
        .onChange(of: defaultFundManagerOrganizationID) { _, _ in scheduleAutosave() }
        .onChange(of: calendarTaskRemindersEnabled) { _, enabled in
            UserDefaults.standard.set(enabled, forKey: AppRuntime.calendarTaskRemindersEnabledDefaultsKey)
            NotificationCenter.default.post(name: .footprintCalendarTaskReminderPreferenceChanged, object: nil)
        }
        .onDisappear { persistSettingsIfNeeded() }
        .alert(
            language.text("Restore selected backup?", "Återställ vald säkerhetskopia?"),
            isPresented: Binding(
                get: { pendingRestoreBackupURL != nil },
                set: { newValue in
                    if !newValue {
                        pendingRestoreBackupURL = nil
                        restoreConfirmationAcknowledged = false
                    }
                }
            ),
            actions: {
                Button(language.text("Cancel", "Avbryt"), role: .cancel) {
                    pendingRestoreBackupURL = nil
                }
                Button(language.text("Restore", "Återställ"), role: .destructive) {
                    guard let pendingRestoreBackupURL else { return }
                    store.restoreFromBackupAsync(directoryURL: pendingRestoreBackupURL) {
                        reloadBackupCenterState(selecting: pendingRestoreBackupURL)
                    }
                    self.pendingRestoreBackupURL = nil
                    restoreConfirmationAcknowledged = false
                }
            },
            message: {
                Text(selectedBackupPreview)
            }
        )
        .sheet(item: $pendingCalendarMeetingCategoryDeletion) { _ in
            calendarMeetingCategoryDeletionSheet(language: language)
        }
    }

    @ViewBuilder
    private func appearanceSection(language: AppLanguage) -> some View {
        chromeSchemeSection(language: language)
        semanticColorsSection(language: language)
        typographySection(language: language)
    }

    private var homeCountryOptions: [(label: String, value: String)] {
        let swedish = Locale(identifier: "sv_SE")
        var options = GrantParsing.countryOptions
            .filter { $0 != "International" }
            .map { name -> (label: String, value: String) in
                guard settingsLanguage == .swedish,
                      let code = GrantParsing.countryRegionCodeByCanonicalName[name],
                      let swedishName = swedish.localizedString(forRegionCode: code) else {
                    return (name, name)
                }
                return (swedishName, name)
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        if !options.contains(where: { $0.value == homeCountry }) {
            options.insert((homeCountry, homeCountry), at: 0)
        }
        return options
    }

    private var settingsLanguage: AppLanguage { store.language }

    private var homeOrganizationOptions: [(label: String, value: String)] {
        let none = (label: settingsLanguage.text("None", "Ingen"), value: "")
        let organizations = store.organizations
            .filter { !$0.isArchived || $0.id == homeRegionOrganizationID }
            .map { organization -> (label: String, value: String) in
                let name = settingsLanguage == .english ? (organization.nameEn.nonEmpty ?? organization.nameSv) : organization.nameSv
                return (name, organization.id)
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return [none] + organizations
    }

    private var defaultFundManagerOptions: [(label: String, value: String)] {
        let none = (label: settingsLanguage.text("None", "Ingen"), value: "")
        let managers = store.fundManagerOrganizations
            .filter { !$0.isArchived || $0.id == defaultFundManagerOrganizationID }
            .map { organization -> (label: String, value: String) in
                (organization.displayName(for: settingsLanguage), organization.id)
            }
        return [none] + managers
    }

    @ViewBuilder
    private func homeOrganizationSection(language: AppLanguage) -> some View {
        settingsCard {
            Text(language.text("Home organization", "Hemorganisation"))
                .appTypography(.sectionTitle)

            Text(language.text(
                "These choices replace names that used to be built into the app. Nothing changes until you choose something else here.",
                "De här valen ersätter namn som tidigare var inbyggda i appen. Inget ändras förrän du väljer något annat här."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Home country", "Hemland"))
                    .appTypography(.fieldLabel)
                AppMenuSelectionField(selection: $homeCountry, options: homeCountryOptions)
                    .frame(maxWidth: 360)
                SettingsEffectNote(language.text(
                    "Affects: which countries get a flag in the Researchers and Projects lists (the home country gets none); whether a publication counts as National or International when it is saved (International when any linked author's main country is another country); and clinical-time activities in another country are not linked to the home region.",
                    "Påverkar: vilka länder som får flagga i listorna Forskare och Projekt (hemlandet får ingen); om en publikation räknas som nationell eller internationell när den sparas (internationell när någon kopplad författares huvudland är ett annat land); och att aktiviteter med Klinisk tid i ett annat land inte kopplas till hemregionen."
                ))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Home region", "Hemregion"))
                    .appTypography(.fieldLabel)
                AppMenuSelectionField(selection: $homeRegionOrganizationID, options: homeOrganizationOptions)
                    .frame(maxWidth: 360)
                SettingsEffectNote(language.text(
                    "Affects: calendar activities in a category marked Clinical time are linked to this organization when they take place in the home country or have no country. With None they are not linked to any organization.",
                    "Påverkar: kalenderaktiviteter i en kategori markerad som Klinisk tid kopplas till den här organisationen när de sker i hemlandet eller saknar land. Med Ingen kopplas de inte till någon organisation."
                ))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Default fund manager", "Förvald medelsförvaltare"))
                    .appTypography(.fieldLabel)
                AppMenuSelectionField(selection: $defaultFundManagerOrganizationID, options: defaultFundManagerOptions)
                    .frame(maxWidth: 360)
                SettingsEffectNote(language.text(
                    "Affects: the fund manager chosen for a record under Calls and grants when its funder has no preferred fund manager (set on the funder under Organizations). Records that already have a fund manager are not changed.",
                    "Påverkar: vilken medelsförvaltare som väljs för en post under Utlysningar och anslag när finansiären inte har någon prioriterad förvaltare (ställs in på finansiären under Organisationer). Poster som redan har en förvaltare ändras inte."
                ))
            }

        }
    }

    @ViewBuilder
    private func reminderSettingsCard(language: AppLanguage) -> some View {
        settingsCard {
            Text(language.text("Reminder times", "Påminnelsetider"))
                .appTypography(.sectionTitle)

            Text(language.text(
                "When grant and task reminders are sent. Changes apply to reminders that have not been sent yet.",
                "När påminnelser om anslag och uppgifter skickas. Ändringar gäller påminnelser som inte har skickats än."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    language.text("Reminders about applications", "Påminnelser om ansökningar"),
                    isOn: $reminderSettings.grantRemindersEnabled
                )
                .appCheckboxStyle()
                SettingsEffectNote(language.text(
                    "Affects: whether the app sends macOS notifications about your applications: when a call opens, before it closes, when a decision is late, before and when the disposition time ends, and when a repayment date has passed. Only applications still to apply for, waiting for a decision or granted get reminders; declined, withdrawn and not applied ones get none. Notifications must also be turned on under Task notifications above.",
                    "Påverkar: om appen skickar notiser i macOS om dina ansökningar: när en utlysning öppnar, innan den stänger, när ett beslut dröjer, innan och när disponeringstiden slutar och när ett datum för återbetalning har passerat. Bara ansökningar som ska sökas, väntar på beslut eller är beviljade får påminnelser; avslagna, tillbakadragna och ej sökta får inga. Notiser måste också vara påslagna under Uppgiftsnotiser ovan."
                ))
                Stepper(
                    value: $reminderSettings.grantClosingLeadDays,
                    in: 0...365
                ) {
                    Text(language.text(
                        "Closing soon: \(reminderSettings.grantClosingLeadDays) days before an application closes",
                        "Snart stängning: \(reminderSettings.grantClosingLeadDays) dagar innan en ansökan stänger"
                    ))
                }
                grantReminderEffectNote(language: language)
                Stepper(
                    value: $reminderSettings.grantDecisionFollowUpDays,
                    in: 0...365
                ) {
                    Text(language.text(
                        "Decision overdue: \(reminderSettings.grantDecisionFollowUpDays) days after the expected decision date",
                        "Beslut dröjer: \(reminderSettings.grantDecisionFollowUpDays) dagar efter förväntat beslutsdatum"
                    ))
                }
                grantReminderEffectNote(language: language)
                Stepper(
                    value: $reminderSettings.grantDispositionEndLeadMonths,
                    in: 0...60
                ) {
                    Text(language.text(
                        "Disposition time ending: \(reminderSettings.grantDispositionEndLeadMonths) months before it ends (0 = no reminder)",
                        "Disponeringstid slutar: \(reminderSettings.grantDispositionEndLeadMonths) månader innan den slutar (0 = ingen påminnelse)"
                    ))
                }
                grantReminderEffectNote(language: language)
                Stepper(
                    value: $reminderSettings.taskDueSoonDays,
                    in: 0...365
                ) {
                    Text(language.text(
                        "A task is marked as due soon (yellow) \(reminderSettings.taskDueSoonDays) days before its deadline",
                        "En uppgift markeras som snart förfallen (gul) \(reminderSettings.taskDueSoonDays) dagar före sin deadline"
                    ))
                }
                SettingsEffectNote(language.text(
                    "Affects: the yellow marker on tasks in the task lists of applications, conference contributions and review assignments.",
                    "Påverkar: den gula markeringen på uppgifter i uppgiftslistorna i ansökningar, konferensbidrag och granskningsuppdrag."
                ))
                HStack(spacing: 16) {
                    reminderTimeField(
                        title: language.text("Grant reminders at", "Anslagspåminnelser klockan"),
                        text: $reminderSettings.grantReminderTime
                    )
                    reminderTimeField(
                        title: language.text("Task notification at", "Uppgiftsnotis klockan"),
                        text: $reminderSettings.taskNotificationTime
                    )
                    Spacer()
                }
                SettingsEffectNote(language.text(
                    "Affects: Grant reminders at — the time of day the reminders about applications are sent. Task notification at — the time of the daily notification about the day's calendar tasks, when notifications are turned on under Task notifications.",
                    "Påverkar: Anslagspåminnelser klockan – klockslaget då påminnelserna om ansökningar skickas. Uppgiftsnotis klockan – klockslaget för den dagliga notisen om dagens kalenderuppgifter, när notiser är påslagna under Uppgiftsnotiser."
                ))
            }

            Text(language.text("Format: HH:MM.", "Format: HH:MM."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
        }
    }

    /// "Arbetstid": the working day shown in the calendar's week view.
    @ViewBuilder
    private func workingHoursCard(language: AppLanguage) -> some View {
        settingsCard {
            Text(language.text("Working hours", "Arbetstid"))
                .appTypography(.sectionTitle)

            Text(language.text(
                "Your normal working day. In the week view, the time outside it and all of Saturday and Sunday get a light grey background.",
                "Din vanliga arbetsdag. I veckovyn får tiden utanför den och hela lördagen och söndagen en ljusgrå bakgrund."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    language.text("Mark time outside working hours in the week view", "Markera tid utanför arbetstid i veckovyn"),
                    isOn: $workingHours.marksOutsideWorkingHours
                )
                .appCheckboxStyle()
                HStack(spacing: 16) {
                    reminderTimeField(
                        title: language.text("From", "Från"),
                        text: $workingHours.startTime
                    )
                    reminderTimeField(
                        title: language.text("To", "Till"),
                        text: $workingHours.endTime
                    )
                    Spacer()
                }
                .disabled(!workingHours.marksOutsideWorkingHours)
                if workingHours.marksOutsideWorkingHours, workingHours.workingSpan == nil {
                    Text(language.text(
                        "The start time must be before the end time. Until then nothing is marked.",
                        "Starttiden måste vara före sluttiden. Till dess markeras ingenting."
                    ))
                    .appTypography(.secondary)
                    .foregroundStyle(Color.orange)
                }
                SettingsEffectNote(language.text(
                    "Affects: only the background of the calendar's week view. Events, statistics and reminders are not changed.",
                    "Påverkar: bara bakgrunden i kalenderns veckovy. Händelser, statistik och påminnelser ändras inte."
                ))
            }

            Text(language.text("Format: HH:MM.", "Format: HH:MM."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
        }
        // Lives here rather than on body: body's modifier chain is at the type-checker's limit.
        .onChange(of: workingHours) { _, _ in scheduleAutosave() }
    }

    /// The lead days/months above decide when the reminders about
    /// applications are sent (GrantReminderCoordinator).
    private func grantReminderEffectNote(language: AppLanguage) -> some View {
        SettingsEffectNote(language.text(
            "Affects: the day the reminder about the application is sent, when Reminders about applications is on. Changes apply to reminders that have not been sent yet.",
            "Påverkar: vilken dag påminnelsen om ansökan skickas, när Påminnelser om ansökningar är påslaget. Ändringar gäller påminnelser som inte har skickats än."
        ))
    }

    private func reminderTimeField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appTypography(.fieldLabel)
            TextField("HH:MM", text: text)
                .appTextInputChrome(fillsWidth: false)
                .frame(width: 110)
        }
    }

    private var appearanceChromeSurfaces: [AppChromeSurface] {
        [.menu, .list, .workspace]
    }

    private var calendarChromeSurfaces: [AppChromeSurface] {
        [.calendarFilter, .calendarHeader, .calendarWorkspace, .calendarDayRow]
    }

    @ViewBuilder
    private func chromeSchemeSection(language: AppLanguage) -> some View {
        settingsCard {
            Text(language.text("Menus, lists, and workspace", "Menyer, listor och arbetsyta"))
                .appTypography(.sectionTitle)

            Text(language.text("Choose how clearly the app should separate the top menu, list views, and the main work area. Each preview shows menu, list, and workspace from left to right, in both light mode and dark mode.", "Välj hur tydligt appen ska skilja mellan huvudmenyn högst upp, listvyer och den huvudsakliga arbetsytan. Varje förhandsvisning visar meny, lista och arbetsyta från vänster till höger, i både ljust och mörkt läge."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            SettingsEffectNote(language.text(
                "Affects: the background colors of the top menu, the list column in each view and the work area, in light and dark mode. Use chooses the scheme; the color fields change that scheme's colors.",
                "Påverkar: bakgrundsfärgerna på huvudmenyn, listkolumnen i varje vy och arbetsytan, i ljust och mörkt läge. Använd väljer schemat; färgfälten ändrar det schemats färger."
            ))

            HStack(alignment: .top, spacing: 12) {
                ForEach(AppChromeScheme.allCases) { scheme in
                    chromeSchemeButton(scheme, language: language)
                }
            }
        }
    }

    @ViewBuilder
    private func semanticColorsSection(language: AppLanguage) -> some View {
        settingsCard {
            HStack {
                Text(language.text("Mode colors and schedule", "Lägesfärger och schema"))
                    .appTypography(.sectionTitle)
                Spacer()
                AppResetButton(title: language.text("Reset colors", "Återställ färger")) {
                    resetSemanticColorProfilesToBuiltInDefaults()
                }
            }

            Text(language.text("These colors drive status, charts, links, warnings, deadlines, and the built-in calendar themes. The light-mode colors are used from the light start time below, and the dark-mode colors from the dark start time below, until you manually choose another mode.", "Dessa färger styr status, diagram, länkar, varningar, deadlines och kalenderns färdiga teman. Färgerna för ljust läge används från starttiden för ljust läge nedan, och färgerna för mörkt läge från starttiden för mörkt läge nedan, tills du manuellt väljer ett annat läge."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                semanticModeConfigurationPanel(useDark: false, language: language)
                semanticModeConfigurationPanel(useDark: true, language: language)
            }

            Text(language.text("Format: HH:MM. Automatic switching is used only until you manually choose Light mode or Dark mode.", "Format: HH:MM. Automatisk växling används bara tills du manuellt väljer Ljust läge eller Mörkt läge."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            SettingsEffectNote(language.text(
                "Affects: Starts — the time the app switches to that mode by itself (checked every minute) while no mode is chosen by hand. Color profile and color fields — the colors of status badges (granted, rejected), warnings and deadlines, the task markers (overdue, due soon, done) and the calendar's built-in category colors.",
                "Påverkar: Börjar – klockslaget då appen själv byter till det läget (kontrolleras varje minut) så länge inget läge är valt för hand. Färgprofil och färgfält – färgerna på statusmärken (beviljat, avslag), varningar och deadlines, markeringarna på uppgifter (försenad, snart, klar) och kalenderns inbyggda kategorifärger."
            ))
        }
    }

    @ViewBuilder
    private func calendarSection(language: AppLanguage) -> some View {
        calendarViewColorsSection(language: language)

        settingsCard {
            Text(language.text("Task notifications", "Uppgiftsnotiser"))
                .appTypography(.sectionTitle)

            Toggle(
                language.text("Enable calendar task notifications", "Aktivera notiser för kalenderuppgifter"),
                isOn: $calendarTaskRemindersEnabled
            )
            .appCheckboxStyle()

            Text(language.text(
                "Notifications are off by default and are activated only after this choice. Dock badges continue to work without notification access.",
                "Notiser är avstängda som standard och aktiveras först efter detta val. Dockbrickan fortsätter fungera utan åtkomst till notiser."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            SettingsEffectNote(language.text(
                "Affects: whether the app sends macOS notifications about your calendar tasks, at the time chosen under Reminder times, and whether reminders about applications can be sent at all (they can be switched off separately under Reminder times). The Dock badge with today's tasks is shown either way.",
                "Påverkar: om appen skickar notiser i macOS om dina kalenderuppgifter, vid klockslaget under Påminnelsetider, och om påminnelser om ansökningar kan skickas alls (de kan stängas av separat under Påminnelsetider). Dockbrickan med dagens uppgifter visas oavsett."
            ))
        }

        reminderSettingsCard(language: language)

        workingHoursCard(language: language)

        settingsCard {
            Text(language.text("First day of week", "Första dag i veckan"))
                .appTypography(.sectionTitle)

            Text(language.text("Choose which weekday the calendar should start on.", "Välj vilken veckodag kalendern ska börja på."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            AppMenuSelectionField(
                selection: $selectedCalendarWeekday,
                options: CalendarWeekdayChoice.allCases.map { ($0.localizedName(language: language), $0) }
            )

            SettingsEffectNote(language.text(
                "Affects: which weekday comes first in the calendar's weeks, also in the calendar lists shown on other records. It is also written in the calendar settings sheet of Excel exports of the calendar.",
                "Påverkar: vilken veckodag som kommer först i kalenderns veckor, även i kalenderlistorna som visas på andra poster. Den skrivs också i fliken med kalenderinställningar i Excelexporter av kalendern."
            ))
        }

        settingsCard {
            Text(language.text("Country under Place and Your location", "Land under Plats och Din plats"))
                .appTypography(.sectionTitle)

            Text(language.text("Choose whether countries in the calendar should be shown as text, flags, or not at all.", "Välj om länder i kalendern ska visas som text, flaggor eller inte alls."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            AppMenuSelectionField(
                selection: $selectedCalendarCountryDisplayMode,
                options: CalendarCountryDisplayMode.allCases.map { ($0.localizedName(language: language), $0) }
            )

            SettingsEffectNote(language.text(
                "Affects: how the country is shown under Place and Your location on calendar events, in the calendar and in the calendar lists on other records.",
                "Påverkar: hur landet visas under Plats och Din plats på kalenderhändelser, i kalendern och i kalenderlistorna på andra poster."
            ))
        }

        settingsCard {
            Text(language.text("Calendar color areas", "Färgytor i kalendern"))
                .appTypography(.sectionTitle)

            Text(language.text("Choose how far category and day colors should extend in the calendar list.", "Välj hur långt kategori- och dagfärger ska sträcka sig i kalenderlistan."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    language.text("Show event colors only behind the category column", "Visa händelsefärg bara bakom kategorikolumnen"),
                    isOn: $calendarUsesCompactEventColorBands
                )
                .appCheckboxStyle()
                SettingsEffectNote(language.text(
                    "Affects: in the calendar list, only the category column gets the category color instead of the whole event row.",
                    "Påverkar: i kalenderlistan får bara kategorikolumnen kategorifärgen i stället för hela händelseraden."
                ))

                Toggle(
                    language.text("Show holiday/weekend colors only under weekday", "Visa färg för röda dagar/helger bara under veckodag"),
                    isOn: $calendarUsesCompactDayHighlightBands
                )
                .appCheckboxStyle()
                SettingsEffectNote(language.text(
                    "Affects: in the calendar list, holidays, Saturdays and Sundays are colored only under the weekday instead of across the whole date row.",
                    "Påverkar: i kalenderlistan färgas helgdagar, lördagar och söndagar bara under veckodagen i stället för över hela datumraden."
                ))
            }
        }

        settingsCard {
            Text(language.text("Calendar holidays", "Helgdagar i kalendern"))
                .appTypography(.sectionTitle)

            Text(language.text("Choose which countries should add public holidays to the calendar.", "Välj vilka länder som ska lägga in helgdagar i kalendern."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(HolidayCountry.allCases) { country in
                    Toggle(
                        country.localizedName(language: language),
                        isOn: Binding(
                            get: { selectedHolidayCountries.contains(country) },
                            set: { isSelected in
                                if isSelected {
                                    selectedHolidayCountries.insert(country)
                                } else {
                                    selectedHolidayCountries.remove(country)
                                }
                            }
                        )
                    )
                    .appCheckboxStyle()
                }
            }

            if selectedHolidayCountries.isEmpty {
                Text(language.text("No countries are selected, so no holidays will be shown in the calendar.", "Inga länder är valda, så inga helgdagar visas i kalendern."))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
            }

            SettingsEffectNote(language.text(
                "Affects: which public holidays are shown as events in the calendar and get the holiday day color below.",
                "Påverkar: vilka helgdagar som visas som händelser i kalendern och får helgdagsfärgen nedan."
            ))

            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("Day colors", "Dagfärger"))
                    .appTypography(.panelTitle)

                Text(language.text("Choose text and background colors for holidays, Saturdays, and Sundays in both light mode and dark mode. The built-in presets follow the same semantic scale as the rest of the app.", "Välj text- och bakgrundsfärger för helgdagar, lördagar och söndagar i både ljust och mörkt läge. De färdiga förinställningarna följer samma semantiska skala som resten av appen."))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)

                presetControls(
                    language: language,
                    selectedPresetID: $selectedCalendarDayHighlightColorPresetID,
                    options: calendarDayHighlightColorPresets.map { ($0.id, $0.name) },
                    presetName: selectedPresetNameBinding(
                        selectedPresetID: $selectedCalendarDayHighlightColorPresetID,
                        nameForID: calendarDayHighlightPresetName(for:),
                        setName: renameCalendarDayHighlightPreset
                    ),
                    description: language.text("Standard keeps your current colors. Built-in themes can be applied as a starting point, then saved as new presets.", "Standard behåller dina nuvarande färger. Färdiga teman kan användas som utgångspunkt och sedan sparas som nya förinställningar."),
                    applyAction: applySelectedCalendarDayHighlightPreset,
                    updateAction: { updateSelectedCalendarDayHighlightPreset(language: language) },
                    createAction: { createCurrentCalendarDayHighlightPreset(language: language) },
                    deleteAction: deleteSelectedCalendarDayHighlightPreset,
                    canDeleteSelected: canDeleteCalendarDayHighlightPreset(id: selectedCalendarDayHighlightColorPresetID)
                )

                SettingsEffectNote(language.text(
                    "Affects: the text and background color of holiday, Saturday and Sunday rows in the calendar list, in light and dark mode. Choosing a preset copies its colors into the fields.",
                    "Påverkar: text- och bakgrundsfärg på raderna för helgdagar, lördagar och söndagar i kalenderlistan, i ljust och mörkt läge. Att välja en förinställning kopierar dess färger till fälten."
                ))

                ForEach(CalendarDayHighlightKind.allCases) { kind in
                    calendarDayHighlightRow(kind, language: language)
                }
            }
            .padding(.top, 8)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppPalette.secondaryCardSurface)
            )
        }

        calendarCategoriesSection(language: language)
    }

    @ViewBuilder
    private func calendarViewColorsSection(language: AppLanguage) -> some View {
        settingsCard {
            Text(language.text("Calendar view backgrounds", "Kalendervyns bakgrunder"))
                .appTypography(.sectionTitle)

            Text(language.text("Choose separate backgrounds for the calendar filter list, column headers, calendar area, and date rows. Changes are shown directly in the app behind this settings window.", "Välj separata bakgrunder för kalenderns filterlista, kolumnrubriker, kalenderyta och datumrader. Ändringar visas direkt i appen bakom inställningsfönstret."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            SettingsEffectNote(language.text(
                "Affects: the backgrounds of the calendar view only (filter list, column headers, calendar area and date rows), for the menu scheme chosen under Appearance.",
                "Påverkar: bara kalendervyns bakgrunder (filterlistan, kolumnrubrikerna, kalenderytan och datumraderna), för det menyschema som är valt under Utseende."
            ))

            VStack(alignment: .leading, spacing: 10) {
                calendarChromePreviewRow(useDark: false, language: language)
                calendarChromePreviewRow(useDark: true, language: language)
            }
        }
    }

    @ViewBuilder
    private func calendarCategoriesSection(language: AppLanguage) -> some View {
        settingsCard {
            HStack {
                Text(language.text("Calendar categories", "Kalenderkategorier"))
                    .appTypography(.sectionTitle)
                Spacer()
                AppResetButton(title: language.text("Reset colors", "Återställ färger")) {
                    resetCalendarCategoryColors()
                }
            }

            Text(language.text("Choose which categories should be available when you add an activity, and which colors should be used in light mode and dark mode. Deadlines use urgent/near, tasks use middle distance, travel uses far away/safe, and uncategorized uses neutral unless you override them here.", "Välj vilka kategorier som ska finnas när du lägger till en aktivitet, och vilka färger som ska användas i ljust respektive mörkt läge. Tidsfrister använder brådskande/nära, uppgifter använder mittemellan, resor använder långt bort/tryggt och ej kategoriserat använder neutralt om du inte ändrar dem här."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("Fixed categories", "Fasta kategorier"))
                    .appTypography(.panelTitle)

                calendarFixedCategoryProfileControls(language: language)

                SettingsEffectNote(language.text(
                    "Affects: the color of application deadlines, tasks, travel and uncategorized events in the calendar. The reusable activity colors are the colors the activity categories below can choose from.",
                    "Påverkar: färgen på ansökningarnas sista dagar, uppgifter, resor och okategoriserade händelser i kalendern. De återanvändbara aktivitetsfärgerna är de färger som aktivitetskategorierna nedan kan välja mellan."
                ))

                ForEach(CalendarFixedCategory.allCases) { category in
                    fixedCalendarCategoryRow(category, language: language)
                }

                ForEach(CalendarActivityColorRole.allCases) { role in
                    activityCalendarCategoryColorRow(role, language: language)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppPalette.secondaryCardSurface)
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("Activity categories", "Aktivitetskategorier"))
                    .appTypography(.panelTitle)

                Text(language.text("Categories already used by saved activities are also shown here so you can color them without changing historical data.", "Kategorier som redan används i sparade aktiviteter visas också här så att du kan färgsätta dem utan att ändra historiska data."))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)

                Text(language.text("Use the arrows to choose the order these categories should appear in the app.", "Använd pilarna för att välja i vilken ordning dessa kategorier ska visas i appen."))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)

                SettingsEffectNote(language.text(
                    "Affects: Category — the names you can choose when you add or edit a calendar activity, in this order. Color — the activity's color in the calendar. Do not count in meeting statistics — the category's activities are left out of the meeting hours on your own researcher card. Clinical time — the activity is marked as in person and linked to the home region when it is in the home country. Leave — the calendar shows only the category name, not the activity's title.",
                    "Påverkar: Kategori – namnen du kan välja när du lägger till eller ändrar en kalenderaktivitet, i den här ordningen. Färg – aktivitetens färg i kalendern. Räkna inte i mötesstatistik – kategorins aktiviteter räknas inte in i mötestimmarna på ditt eget forskarkort. Klinisk tid – aktiviteten markeras som på plats och kopplas till hemregionen när den är i hemlandet. Ledighet – kalendern visar bara kategorins namn, inte aktivitetens titel."
                ))

                ForEach(Array(editableCalendarMeetingCategories.enumerated()), id: \.element.id) { index, category in
                    editableCalendarMeetingCategoryRow(index: index, category: category, language: language)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppPalette.secondaryCardSurface)
            )
        }
    }

    @ViewBuilder
    private func exportSection(language: AppLanguage) -> some View {
        settingsCard {
            Text(language.text("CV profile", "CV-profil"))
                .appTypography(.sectionTitle)

            Text(language.text("Choose which researcher card should be used as the source for CV exports.", "Välj vilket forskarkort som ska användas som källa för CV-exporter."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Researcher", "Forskare"))
                    .appTypography(.fieldLabel)
                AppMenuSelectionField(
                    selection: currentCVAuthorBinding(),
                    options: store.publicationAuthors.map {
                        ($0.name.nonEmpty ?? language.text("Unnamed researcher", "Namnlös forskare"), $0.id)
                    }
                )
                .disabled(store.publicationAuthors.isEmpty)
            }

            SettingsEffectNote(language.text(
                "Affects: who \"you\" are in the whole app — the CV exports and the annual report take their details from this card; your name is highlighted in author lists in exports; your author position on publications, projects you lead, your own meeting hours and doctoral students you supervise are worked out from it; and new organizations are suggested as Regional, National or International from its affiliations.",
                "Påverkar: vem som är \"du\" i hela appen – CV-exporterna och årsrapporten hämtar uppgifter från det här kortet; ditt namn markeras i författarlistor i exporter; din författarposition på publikationer, projekt du leder, dina egna mötestimmar och doktorander du handleder räknas fram utifrån det; och nya organisationer föreslås som regionala, nationella eller internationella utifrån kortets affilieringar."
            ))
        }

        settingsCard {
            Text(language.text("Export destination", "Exportplats"))
                .appTypography(.sectionTitle)

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Folder", "Mapp"))
                    .appTypography(.fieldLabel)
                Text(store.exportDirectoryPath)
                    .appTypography(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppPalette.secondaryCardSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppPalette.border, lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                Button(language.text("Choose folder…", "Välj mapp…")) {
                    chooseExportDirectory()
                }
                .appSaveButtonStyle()

                Button(language.text("Use Downloads", "Använd Hämtade filer")) {
                    store.setExportDirectory(nil)
                }
                .buttonStyle(.bordered)

                Button(language.text("Open folder", "Öppna mapp")) {
                    NSWorkspace.shared.open(store.exportDirectoryURL)
                }
                .buttonStyle(.bordered)
            }

            SettingsEffectNote(language.text(
                "Affects: where every export (CV, Excel, Word and the other exports) is saved. Exports are saved directly to this folder without asking for a location.",
                "Påverkar: var alla exporter (CV, Excel, Word och övriga exporter) sparas. De sparas direkt i den här mappen utan att appen frågar efter plats."
            ))
        }

        WorkflowDefaultSettingsPanel(store: store, part: .export)

        exportLanguageAuditSection(language: language)
    }

    private func currentCVAuthorBinding() -> Binding<String> {
        Binding(
            get: {
                store.currentUserAuthor()?.id ?? store.publicationAuthors.first?.id ?? ""
            },
            set: { newValue in
                guard !newValue.isEmpty else { return }
                store.setCurrentUserAuthor(id: newValue)
            }
        )
    }

    @ViewBuilder
    private func exportLanguageAuditSection(language: AppLanguage) -> some View {
        settingsCard {
            Text(language.text("Export language audit", "Språköversikt för export"))
                .appTypography(.sectionTitle)
            Text(language.text(
                "Use this as a quick check before exporting. Exports marked with a fixed language do not change when the app language changes.",
                "Använd detta som snabbkontroll före export. Exporter med fast språk ändras inte när appens språk ändras."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            SettingsEffectNote(language.text(
                "Affects: nothing — this is only an overview and has no settings.",
                "Påverkar: inget – det här är bara en översikt och har inga inställningar."
            ))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(exportLanguageAuditRows(language: language), id: \.0) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.0)
                            .appTypography(.fieldLabel)
                            .frame(width: 230, alignment: .leading)
                        Text(row.1)
                            .appTypography(.body)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppPalette.secondaryCardSurface)
                    )
                }
            }
        }
    }

    private func exportLanguageAuditRows(language: AppLanguage) -> [(String, String)] {
        [
            (
                language.text("Salary planning Excel", "Löneplanering Excel"),
                language.text("Fixed Swedish", "Fast svenska")
            ),
            (
                language.text("Current view Excel", "Aktuell vy Excel"),
                language.text("Follows app language", "Följer appens språk")
            ),
            (
                language.text("All app data Excel", "All appdata Excel"),
                language.text("Follows app language", "Följer appens språk")
            ),
            (
                language.text("CV exports", "CV-exporter"),
                language.text("Uses the selected export language", "Använder valt exportspråk")
            ),
            (
                language.text("Teaching merits", "Pedagogiska meriter"),
                language.text("Swedish template/content", "Svensk mall/innehåll")
            )
        ]
    }

    @ViewBuilder
    private func dataSection(language: AppLanguage) -> some View {
        copyExportSection(language: language)

        settingsCard {
            Text(language.text("Storage", "Lagring"))
                .appTypography(.sectionTitle)

            settingsInfoRow(
                title: language.text("Storage folder", "Lagringsmapp"),
                value: AppRuntime.storageFolderName
            )
            settingsInfoRow(
                title: language.text("Live data path", "Sökväg till live-data"),
                value: store.storageDirectoryURL.path
            )
            settingsInfoRow(
                title: language.text("Backups path", "Sökväg till säkerhetskopior"),
                value: store.backupsDirectoryURL.path
            )
            settingsInfoRow(
                title: language.text("Defaults prefix", "Defaults-prefix"),
                value: store.packageIdentity.defaultsPrefix
            )

            SettingsEffectNote(language.text(
                "Affects: nothing — the paths are shown for information. The buttons only open the folders in Finder.",
                "Påverkar: inget – sökvägarna visas som information. Knapparna öppnar bara mapparna i Finder."
            ))

            HStack(spacing: 10) {
                Button(language.text("Open active data folder", "Öppna aktiv datamapp")) {
                    NSWorkspace.shared.open(store.storageDirectoryURL)
                }
                .appSaveButtonStyle()

                Button(language.text("Open backups folder", "Öppna mappen med säkerhetskopior")) {
                    NSWorkspace.shared.open(store.backupsDirectoryURL)
                }
                .buttonStyle(.bordered)
            }
        }

        settingsCard {
            HStack {
                Text(language.text("Performance log", "Prestandalogg"))
                    .appTypography(.sectionTitle)
                Spacer()
                Button(language.text("Summarize latest log", "Sammanfatta senaste logg")) {
                    refreshPerformanceDiagnosticsStatus()
                    performanceDiagnosticsSummaryText = store.performanceDiagnosticsSummary()
                }
                .appSaveButtonStyle()
            }

            SettingsEffectNote(language.text(
                "Affects: nothing in your data — the button only summarizes the app's timing log so slow views can be found.",
                "Påverkar: inget i din data – knappen sammanfattar bara appens tidslogg så att långsamma vyer kan hittas."
            ))

            performanceDiagnosticsStatusGrid(language: language)

            settingsReadOnlyText(
                performanceDiagnosticsSummaryText.nonEmpty
                    ?? language.text("Click summarize to inspect the latest view, cache, freeze and persistence timings.", "Klicka på sammanfatta för att granska senaste vy-, cache-, låsnings- och persistenstiderna.")
            )
            .frame(minHeight: 220, alignment: .topLeading)
        }

        settingsCard {
            HStack {
                Text(language.text("Restore center", "Återställningscenter"))
                    .appTypography(.sectionTitle)
                Spacer()
                Button(language.text("Create snapshot now", "Skapa snapshot nu")) {
                    createManualBackupSnapshot()
                }
                .appSaveButtonStyle()

                Button(language.text("Reload", "Ladda om")) {
                    reloadBackupCenterState()
                }
                .buttonStyle(.bordered)
            }

            Text(language.text("Use this section to verify live data, inspect backup snapshots and restore the exact snapshot you choose.", "Använd denna del för att verifiera live-data, granska säkerhetskopior och återställa exakt den säkerhetskopia du väljer."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            SettingsEffectNote(language.text(
                "Affects: Create snapshot now saves a copy of all current data in the backups folder. Restore selected backup replaces all current data in the app with the chosen copy; the checkbox only unlocks that button.",
                "Påverkar: Skapa snapshot nu sparar en kopia av all aktuell data i mappen med säkerhetskopior. Återställ vald säkerhetskopia ersätter all aktuell data i appen med den valda kopian; kryssrutan låser bara upp den knappen."
            ))

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Live data summary", "Sammanfattning av live-data"))
                    .appTypography(.fieldLabel)
                settingsReadOnlyText(backupHealthSummaryText)
                    .frame(minHeight: 140, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(language.text("Available snapshots", "Tillgängliga snapshots"))
                        .appTypography(.fieldLabel)
                    Spacer()
                    Text("\(backupSnapshots.count)")
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                }

                if backupSnapshots.isEmpty {
                    Text(language.text("No backups were found in the active backups folder.", "Inga säkerhetskopior hittades i den aktiva mappen för säkerhetskopior."))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(backupSnapshots, id: \.url) { snapshot in
                                Button {
                                    selectBackupSnapshot(snapshot.url)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(snapshot.url.lastPathComponent)
                                                .appTypography(.fieldLabel)
                                                .foregroundStyle(.primary)
                                            Text(backupSnapshotDateText(snapshot.date))
                                                .appTypography(.secondary)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(selectedBackupURL == snapshot.url ? AppPalette.activeTabSurface.opacity(0.18) : AppPalette.secondaryCardSurface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(selectedBackupURL == snapshot.url ? AppPalette.actionSave.opacity(0.45) : AppPalette.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Selected backup preview", "Förhandsgranskning av vald säkerhetskopia"))
                    .appTypography(.fieldLabel)
                settingsReadOnlyText(selectedBackupPreview.nonEmpty ?? language.text("Select a backup snapshot to inspect it.", "Välj en säkerhetskopia för att granska den."))
                    .frame(minHeight: 200, alignment: .topLeading)
            }

            HStack(spacing: 10) {
                Button(language.text("Open selected backup", "Öppna vald säkerhetskopia")) {
                    guard let selectedBackupURL else { return }
                    NSWorkspace.shared.open(selectedBackupURL)
                }
                .buttonStyle(.bordered)
                .disabled(selectedBackupURL == nil)

                Toggle(
                    language.text("I understand that active data will be replaced", "Jag förstår att aktiv data ersätts"),
                    isOn: $restoreConfirmationAcknowledged
                )
                .appCheckboxStyle()
                .fixedSize()
                .disabled(selectedBackupURL == nil)

                Button(language.text("Restore selected backup", "Återställ vald säkerhetskopia")) {
                    pendingRestoreBackupURL = selectedBackupURL
                }
                .appDeleteButtonStyle()
                .disabled(selectedBackupURL == nil || !restoreConfirmationAcknowledged)
            }
        }
    }

    @ViewBuilder
    private func listFilterSection(language: AppLanguage) -> some View {
        settingsCard {
            Text(language.text("List filter memory", "Listfiltrens minne"))
                .appTypography(.sectionTitle)
            Text(language.text(
                "Choose which views keep their list filters. Kept filters stay when you switch views and also until the next time you open the app. A filtered list always says so above the list, shows how many records are visible and has a Clear filters button.",
                "Välj vilka vyer som ska behålla sina listfilter. Filter som behålls finns kvar när du växlar vy och även till nästa gång du öppnar appen. En filtrerad lista säger alltid det ovanför listan, visar hur många poster som syns och har knappen Rensa filter."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(ListFilterPersistenceKey.allCases) { key in
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: listFilterRetentionBinding(for: key)) {
                            Text(key.title(language: language))
                                .appTypography(.body)
                        }
                        .appCheckboxStyle()
                        SettingsEffectNote(language.text(
                            "Affects: the filters in the \(key.title(language: language)) list. On: they are kept when you leave the view and between sessions, and the list shows that it is filtered. Off: they are cleared when you leave the view.",
                            "Påverkar: filtren i listan \(key.title(language: language)). På: de finns kvar när du lämnar vyn och mellan gångerna du använder appen, och listan visar att den är filtrerad. Av: de nollställs när du lämnar vyn."
                        ))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func translationsSection(language: AppLanguage) -> some View {
        settingsCard {
            HStack {
                Text(language.text("Locked dropdown translations", "Översättningar för låsta dropdownfält"))
                    .appTypography(.sectionTitle)
                Spacer()
                AppResetButton(title: language.text("Reset to defaults", "Återställ standard")) {
                    for definition in editableDropdownTranslationDefinitions where !definition.shouldLiveInTeachingTerminology {
                        dropdownTranslationsSv[definition.key] = definition.defaultSv
                        dropdownTranslationsEn[definition.key] = definition.defaultEn
                    }
                    scheduleAutosave()
                }
                .buttonStyle(.bordered)
            }

            Text(language.text("These labels are locked elsewhere in the app. Change them here if you want different fixed wording.", "Dessa etiketter är låsta på andra ställen i appen. Ändra dem här om du vill ha annan fast formulering."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            SettingsEffectNote(language.text(
                "Affects: the text shown for that choice wherever the app shows it (menus, lists, filters and cards). The Swedish column is used when the app is in Swedish, the English column when it is in English. The stored value is not changed.",
                "Påverkar: texten som visas för valet överallt där appen visar det (menyer, listor, filter och kort). Svenska kolumnen används när appen är på svenska, engelska kolumnen när den är på engelska. Det sparade värdet ändras inte."
            ))

            ForEach(translationSections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title)
                        .appTypography(.panelTitle)
                    dropdownTranslationTable(items: section.items, language: language)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppPalette.secondaryCardSurface)
                )
            }
        }
    }

    @ViewBuilder
    private func mediaLanguagesSection(language: AppLanguage) -> some View {
        settingsCard {
            Text(language.text("Media languages", "Mediaspråk"))
                .appTypography(.sectionTitle)
            Text(language.text(
                "The standard languages are always available. Add custom languages with a stable code and names for both interface languages.",
                "Standardspråken finns alltid tillgängliga. Lägg till egna språk med en beständig kod och namn för båda gränssnittsspråken."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            SettingsEffectNote(language.text(
                "Affects: the languages you can choose under Language on a media appearance (Dissemination), and how the chosen languages are named there — Swedish name when the app is in Swedish, English name when it is in English. The code is what is stored on the appearance.",
                "Påverkar: vilka språk du kan välja under Språk på ett medieframträdande (Spridning), och vad de valda språken heter där – svenskt namn när appen är på svenska, engelskt när den är på engelska. Koden är det som sparas på framträdandet."
            ))

            VStack(alignment: .leading, spacing: SettingsBilingualLayout.rowSpacing) {
                SettingsBilingualColumnsHeader(language: language, labelTitle: language.text("Code", "Kod"))
                ForEach(MediaLanguageOption.builtInOptions) { option in
                    SettingsBilingualPairRow(
                        label: {
                            HStack(spacing: 8) {
                                Text(option.id)
                                    .appTypography(.fieldLabel)
                                Text(language.text("Standard", "Standard"))
                                    .appTypography(.secondary)
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        },
                        swedish: {
                            Text(option.nameSv)
                                .appTypography(.body)
                                .lineLimit(1)
                        },
                        english: {
                            Text(option.nameEn)
                                .appTypography(.body)
                                .lineLimit(1)
                        }
                    )
                }
                ForEach($customMediaLanguageOptions) { $option in
                    SettingsBilingualPairRow(
                        label: {
                            HStack(spacing: 8) {
                                TextField(language.text("Code", "Kod"), text: $option.id)
                                    .frame(width: 90)
                                    .appTextInputChrome(fillsWidth: false)
                                AppRowDeleteIconButton(
                                    title: language.text("Remove language", "Ta bort språk"),
                                    cancelTitle: language.text("Cancel", "Avbryt"),
                                    confirmationTitle: language.text("Remove language?", "Ta bort språket?")
                                ) {
                                    customMediaLanguageOptions.removeAll { $0.id == option.id }
                                    scheduleAutosave()
                                }
                            }
                        },
                        swedish: {
                            SettingsGrowingTextField(
                                placeholder: language.text("Swedish name", "Svenskt namn"),
                                text: $option.nameSv
                            )
                        },
                        english: {
                            SettingsGrowingTextField(
                                placeholder: language.text("English name", "Engelskt namn"),
                                text: $option.nameEn
                            )
                        }
                    )
                }
                SettingsBilingualPairRow(
                    label: {
                        HStack(spacing: 8) {
                            TextField(language.text("Code", "Kod"), text: $newMediaLanguageCode)
                                .frame(width: 90)
                                .appTextInputChrome(fillsWidth: false)
                            Button(language.text("Add", "Lägg till"), action: addCustomMediaLanguage)
                                .buttonStyle(.bordered)
                                .disabled(!canAddCustomMediaLanguage)
                        }
                    },
                    swedish: {
                        SettingsGrowingTextField(
                            placeholder: language.text("Swedish name", "Svenskt namn"),
                            text: $newMediaLanguageNameSv
                        )
                    },
                    english: {
                        SettingsGrowingTextField(
                            placeholder: language.text("English name", "Engelskt namn"),
                            text: $newMediaLanguageNameEn
                        )
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func teachingTerminologySection(language: AppLanguage) -> some View {
        settingsCard {
            HStack {
                Text(language.text("Teaching terminology", "Undervisningsbegrepp"))
                    .appTypography(.sectionTitle)
                Spacer()
                AppResetButton(title: language.text("Reset teaching terms", "Återställ undervisningsbegrepp")) {
                    for definition in visibleTeachingTerminologyDefinitions {
                        dropdownTranslationsSv[definition.key] = definition.defaultSv
                        dropdownTranslationsEn[definition.key] = definition.defaultEn
                    }
                    scheduleAutosave()
                }
            }

            Text(language.text("These are teaching-specific terms used in the teaching workspace. Terms used only by the pedagogical merit report are now managed directly inside each teaching assignment.", "Detta är undervisningsspecifika begrepp som används i undervisningsdelen. Begrepp som bara används för pedagogisk meritrapport hanteras nu direkt i varje undervisningsuppdrag."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            SettingsEffectNote(language.text(
                "Affects: the text shown for these choices in Teaching (menus, lists and filters). The Swedish column is used when the app is in Swedish, the English column when it is in English.",
                "Påverkar: texten som visas för de här valen i Undervisning (menyer, listor och filter). Svenska kolumnen används när appen är på svenska, engelska kolumnen när den är på engelska."
            ))

            ForEach(teachingTerminologySections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title)
                        .appTypography(.panelTitle)
                    dropdownTranslationTable(items: section.items, language: language)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppPalette.secondaryCardSurface)
                )
            }
        }

        WorkflowDefaultSettingsPanel(store: store, part: .teaching)
    }

    @ViewBuilder
    private func typographySection(language: AppLanguage) -> some View {
        settingsCard {
            HStack {
                Text(language.text("Typography", "Typografi"))
                    .appTypography(.sectionTitle)
                Spacer()
                AppResetButton(title: language.text("Reset typography", "Återställ typografi")) {
                    typographySettings = .default
                    scheduleAutosave()
                }
            }

            SettingsEffectNote(language.text(
                "Affects: font, size and weight of that kind of text everywhere in the app; for example Field label changes every label above a field. Exports are not affected.",
                "Påverkar: typsnitt, storlek och tjocklek för den sortens text i hela appen; till exempel ändrar Fältetikett alla etiketter ovanför fält. Exporter påverkas inte."
            ))

            ForEach(AppTypographyRole.allCases) { role in
                typographyRow(
                    title: title(for: role, language: language),
                    style: styleBinding(for: role)
                )
            }
        }
    }

    @ViewBuilder
    private func teachingActivityTypesSection(language: AppLanguage) -> some View {
        settingsCard {
            HStack {
                Text(language.text("Teaching activity types", "Undervisningens aktivitetstyper"))
                    .appTypography(.sectionTitle)
                Spacer()
            }

            Text(language.text("These activity types are shared across the app and used by all institutions.", "Dessa aktivitetstyper delas i hela appen och används av alla lärosäten."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            ForEach(store.teachingFormats + [TeachingFormatOption()]) { format in
                TeachingFormatSettingsRow(store: store, format: format, language: language)
            }
        }
    }

    /// Round 14: the readable copy of all data (JSON files and attachments)
    /// is off until switched on here, and goes to a folder chosen here.
    private func copyExportSection(language: AppLanguage) -> some View {
        settingsCard {
            Text(language.text("Copy of data to a folder", "Kopia av data till en mapp"))
                .appTypography(.sectionTitle)

            Toggle(isOn: Binding(
                get: { copyExportEnabled },
                set: { newValue in
                    if newValue, copyExportFolderPath.isEmpty {
                        guard let folder = chooseCopyExportFolder(language: language) else { return }
                        copyExportFolderPath = folder.path
                    }
                    copyExportEnabled = newValue
                    FootprintExportWriter.shared.configure(
                        enabled: newValue,
                        folder: copyExportFolderPath.isEmpty ? nil : URL(fileURLWithPath: copyExportFolderPath, isDirectory: true)
                    )
                }
            )) {
                Text(language.text("Copy all data to a folder after each save", "Kopiera all data till en mapp efter varje sparning"))
            }
            .toggleStyle(.switch)

            settingsInfoRow(
                title: language.text("Folder", "Mapp"),
                value: copyExportFolderPath.nonEmpty ?? language.text("No folder chosen", "Ingen mapp vald")
            )

            HStack(spacing: 10) {
                Button(language.text("Choose folder…", "Välj mapp…")) {
                    guard let folder = chooseCopyExportFolder(language: language) else { return }
                    copyExportFolderPath = folder.path
                    FootprintExportWriter.shared.configure(enabled: copyExportEnabled, folder: folder)
                }
                .buttonStyle(.bordered)
                if !copyExportFolderPath.isEmpty {
                    Button(language.text("Open folder", "Öppna mappen")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: copyExportFolderPath, isDirectory: true))
                    }
                    .buttonStyle(.bordered)
                }
            }

            SettingsEffectNote(language.text(
                "Affects: when switched on, every save also writes all data (salary included) as readable files, and copies of all attachments, to the chosen folder, for example a Google Drive or OneDrive folder. Nothing is deleted there when you delete something in the app. Off by default.",
                "Påverkar: när valet är på skrivs vid varje sparning all data (även lön) som läsbara filer, och kopior av alla bilagor, till den valda mappen, till exempel en mapp i Google Drive eller OneDrive. Ingenting raderas där när du tar bort något i appen. Avstängt från början."
            ))
        }
    }

    private func chooseCopyExportFolder(language: AppLanguage) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = language.text("Choose", "Välj")
        panel.message = language.text(
            "Choose the folder that gets a copy of all data.",
            "Välj mappen som ska få en kopia av all data."
        )
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        AppSettingsCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
        }
    }

    private func listFilterRetentionBinding(for key: ListFilterPersistenceKey) -> Binding<Bool> {
        Binding(
            get: {
                listFilterRetentionPreferences[key.rawValue] ?? true
            },
            set: { newValue in
                listFilterRetentionPreferences[key.rawValue] = newValue
                scheduleAutosave()
            }
        )
    }

    private func settingsTimeField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appTypography(.fieldLabel)
            AppCommitTextField(
                placeholder: "HH:MM",
                text: text,
                formatter: GrantDataStore.normalizedTimeInput,
                width: 120
            )
        }
    }

    private func chromeSchemeButton(_ scheme: AppChromeScheme, language: AppLanguage) -> some View {
        let isSelected = appChromeScheme == scheme

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(scheme.displayName(language))
                    .appTypography(.panelTitle)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Button(language.text("Selected", "Vald")) {
                        appChromeScheme = scheme
                        scheduleAutosave()
                    }
                    .appSaveButtonStyle()
                } else {
                    Button(language.text("Use", "Använd")) {
                        appChromeScheme = scheme
                        scheduleAutosave()
                    }
                    .buttonStyle(.bordered)
                    .tint(AppPalette.actionSave)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                chromeSchemePreviewRow(scheme, useDark: false, language: language)
                chromeSchemePreviewRow(scheme, useDark: true, language: language)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSelectableOptionSurface(
            isSelected: isSelected,
            fill: AppPalette.secondaryCardSurface,
            cornerRadius: 12,
            padding: 14
        )
        .help(language.text("Apply \(scheme.displayName(language))", "Använd \(scheme.displayName(language))"))
    }

    private func chromeSchemePreviewRow(
        _ scheme: AppChromeScheme,
        useDark: Bool,
        language: AppLanguage
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(useDark ? language.text("Dark mode", "Mörkt läge") : language.text("Light mode", "Ljust läge"))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(appearanceChromeSurfaces, id: \.self) { surface in
                    chromeColorField(
                        title: title(for: surface, language: language),
                        text: chromeColorBinding(scheme: scheme, surface: surface, useDark: useDark),
                        useDark: useDark
                    )
                }
            }
        }
    }

    private func calendarChromePreviewRow(
        useDark: Bool,
        language: AppLanguage
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(useDark ? language.text("Dark mode", "Mörkt läge") : language.text("Light mode", "Ljust läge"))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(calendarChromeSurfaces, id: \.self) { surface in
                    chromeColorField(
                        title: title(for: surface, language: language),
                        text: chromeColorBinding(scheme: appChromeScheme, surface: surface, useDark: useDark),
                        useDark: useDark
                    )
                }
            }
        }
    }

    private func title(for surface: AppChromeSurface, language: AppLanguage) -> String {
        switch surface {
        case .menu:
            return language.text("Menu", "Meny")
        case .list:
            return language.text("List", "Lista")
        case .workspace:
            return language.text("Workspace", "Arbetsyta")
        case .calendar:
            return language.text("Calendar area", "Kalenderyta")
        case .calendarFilter:
            return language.text("Filter background", "Bakgrund filter")
        case .calendarHeader:
            return language.text("Column header background", "Bakgrund kolumnrubriker")
        case .calendarWorkspace:
            return language.text("Calendar area background", "Bakgrund kalenderyta")
        case .calendarDayRow:
            return language.text("Date row background", "Bakgrund datumrader")
        }
    }

    private func chromeColorBinding(
        scheme: AppChromeScheme,
        surface: AppChromeSurface,
        useDark: Bool
    ) -> Binding<String> {
        Binding(
            get: {
                appChromeColors.hex(for: scheme, surface: surface, useDarkAppearance: useDark)
            },
            set: { newValue in
                var colors = appChromeColors.colors(for: scheme, useDarkAppearance: useDark)
                colors.setHex(normalizedHex(newValue), for: surface)
                appChromeColors.setColors(colors, for: scheme, useDarkAppearance: useDark)
                scheduleAutosave()
            }
        )
    }

    private func chromeColorField(title: String, text: Binding<String>, useDark: Bool) -> some View {
        let preview = previewColor(for: text.wrappedValue)
        let foreground: Color = previewBrightness(for: preview) < 0.58 ? .white : .black
        let state = hexFieldState(for: text.wrappedValue)
        let stroke = state == .normal ? (useDark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)) : state.stroke

        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(height: 30, alignment: .bottomLeading)
            HStack(spacing: 8) {
                CommitFormattingTextField(
                    placeholder: "#RRGGBB",
                    text: text,
                    formatter: AppFieldParsers.canonicalHexColor,
                    showsRenewedSurface: false,
                    isBordered: false,
                    focusRingType: .none,
                    textColor: NSColor(foreground),
                    placeholderColor: NSColor(foreground.opacity(0.72)),
                    visualState: state,
                    liveVisualState: { hexFieldState(for: $0) }
                )
                    .padding(.horizontal, 10)
                    .frame(width: 104, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(preview)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(stroke, lineWidth: 1)
                    )
                    .help(state.helpText ?? "")

                ColorPicker("", selection: colorPickerBinding(for: text), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28)
            }
        }
        .frame(width: 156, alignment: .leading)
    }

    private func semanticModeConfigurationPanel(useDark: Bool, language: AppLanguage) -> some View {
        let panelBackground = appChromeScheme.color(for: .workspace, useDarkAppearance: useDark)
        let panelStroke = useDark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
        let secondaryText = useDark ? Color.white.opacity(0.72) : Color.secondary
        let presets = useDark ? darkSemanticColorPresets : lightSemanticColorPresets
        let selectedID = useDark ? selectedDarkSemanticColorPresetID : selectedLightSemanticColorPresetID
        let selectedName = presets.first(where: { $0.id == selectedID })?.name.trimmedOrNil
            ?? language.text("selected profile", "vald profil")
        let updateTitle = language.text("Update \(selectedName)", "Uppdatera \(selectedName)")
        let timeBinding = useDark ? $darkModeStartsAt : $lightModeStartsAt

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(useDark ? language.text("Dark mode", "Mörkt läge") : language.text("Light mode", "Ljust läge"))
                        .appTypography(.panelTitle)
                    Text(useDark ? language.text("These colors turn on at this time.", "Dessa färger slås på vid denna tid.") : language.text("These colors turn on at this time.", "Dessa färger slås på vid denna tid."))
                        .appTypography(.secondary)
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                previewTimeField(
                    title: language.text("Starts", "Börjar"),
                    text: timeBinding,
                    useDark: useDark
                )
            }

            HStack(alignment: .firstTextBaseline) {
                Text(language.text("Color profile", "Färgprofil"))
                    .appTypography(.fieldLabel)
                    .foregroundStyle(useDark ? Color.white.opacity(0.92) : Color.primary)
                Spacer()
                Button {
                    updateSelectedSemanticColorPreset(useDark: useDark, language: language)
                } label: {
                    Label(updateTitle, systemImage: "arrow.triangle.2.circlepath")
                        .lineLimit(1)
                }
                .appSaveButtonStyle()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        semanticProfileOptionButton(
                            preset,
                            isSelected: preset.id == selectedID,
                            useDark: useDark,
                            language: language
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            semanticModeDetailControls(useDark: useDark, language: language)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(panelStroke, lineWidth: 1)
        )
        .environment(\.colorScheme, useDark ? .dark : .light)
    }

    private func semanticModeDetailControls(useDark: Bool, language: AppLanguage) -> some View {
        let stroke = useDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        let labelColor = useDark ? Color.white.opacity(0.92) : Color.primary

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .frame(width: semanticToneColumnWidth, height: semanticMatrixHeaderHeight)

                ForEach(AppSemanticTone.allCases) { tone in
                    Text(title(for: tone, language: language))
                        .appTypography(.fieldLabel)
                        .foregroundStyle(labelColor)
                        .frame(width: semanticToneColumnWidth, height: semanticMatrixRowHeight, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                semanticColorMatrixHeaders(useDark: useDark, language: language)

                ForEach(AppSemanticTone.allCases) { tone in
                    HStack(spacing: 12) {
                        compactColorHexField(
                            text: semanticToneColorBinding(tone: tone, useDark: useDark, shaded: false),
                            stroke: stroke
                        )
                        compactColorHexField(
                            text: semanticToneColorBinding(tone: tone, useDark: useDark, shaded: true),
                            stroke: stroke
                        )
                    }
                    .frame(height: semanticMatrixRowHeight)
                }
            }
        }
        .padding(.top, 8)
    }

    private func previewTimeField(
        title: String,
        text: Binding<String>,
        useDark: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .appTypography(.fieldLabel)
                    .foregroundStyle(useDark ? Color.white.opacity(0.72) : Color.secondary)

            CommitFormattingTextField(
                placeholder: "HH:MM",
                text: text,
                formatter: GrantDataStore.normalizedTimeInput,
                showsRenewedSurface: false,
                isBordered: false,
                focusRingType: .none
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 120)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(useDark ? Color.white.opacity(0.08) : Color.white.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(useDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func semanticProfileOptionButton(
        _ preset: AppSemanticColorPreset,
        isSelected: Bool,
        useDark: Bool,
        language: AppLanguage
    ) -> some View {
        let background = isSelected
            ? previewColor(for: preset.colors.neutral.solidHex).opacity(useDark ? 0.30 : 0.16)
            : (useDark ? Color.white.opacity(0.05) : Color.white.opacity(0.70))
        let stroke = isSelected
            ? previewColor(for: preset.colors.neutral.solidHex).opacity(0.74)
            : (useDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))

        return Button {
            if useDark {
                selectedDarkSemanticColorPresetID = preset.id
            } else {
                selectedLightSemanticColorPresetID = preset.id
            }
            applySemanticColorPreset(preset, useDark: useDark)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(preset.name)
                    .appTypography(.secondary)
                    .fontWeight(.semibold)
                    .foregroundStyle(useDark ? Color.white.opacity(0.94) : Color.primary)
                    .lineLimit(1)

                LazyVGrid(columns: [GridItem(.fixed(18), spacing: 4), GridItem(.fixed(18), spacing: 4)], spacing: 4) {
                    ForEach(Array(semanticPresetSwatches(for: preset.colors).enumerated()), id: \.offset) { _, hex in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(previewColor(for: hex))
                            .frame(width: 18, height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(useDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 1)
                            )
                    }
                }
            }
            .frame(width: 112, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(language.text("Apply \(preset.name)", "Använd \(preset.name)"))
    }

    private func semanticColorMatrix(language: AppLanguage) -> some View {
        let darkPanelBackground = appChromeScheme.color(for: .workspace, useDarkAppearance: true)
        let darkPanelStroke = Color.white.opacity(0.16)

        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .frame(width: semanticToneColumnWidth, height: semanticMatrixHeaderHeight)

                ForEach(AppSemanticTone.allCases) { tone in
                    Text(title(for: tone, language: language))
                        .appTypography(.fieldLabel)
                        .frame(width: semanticToneColumnWidth, height: semanticMatrixRowHeight, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                semanticColorMatrixHeaders(useDark: false, language: language)

                ForEach(AppSemanticTone.allCases) { tone in
                    HStack(spacing: 12) {
                        compactColorHexField(
                            text: semanticToneColorBinding(tone: tone, useDark: false, shaded: false),
                            stroke: Color.black.opacity(0.08)
                        )
                        compactColorHexField(
                            text: semanticToneColorBinding(tone: tone, useDark: false, shaded: true),
                            stroke: Color.black.opacity(0.08)
                        )
                    }
                    .frame(height: semanticMatrixRowHeight)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                semanticColorMatrixHeaders(useDark: true, language: language)

                ForEach(AppSemanticTone.allCases) { tone in
                    HStack(spacing: 12) {
                        compactColorHexField(
                            text: semanticToneColorBinding(tone: tone, useDark: true, shaded: false),
                            stroke: Color.white.opacity(0.14)
                        )
                        compactColorHexField(
                            text: semanticToneColorBinding(tone: tone, useDark: true, shaded: true),
                            stroke: Color.white.opacity(0.14)
                        )
                    }
                    .frame(height: semanticMatrixRowHeight)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(darkPanelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(darkPanelStroke, lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)
        }
    }

    private func semanticColorMatrixHeaders(useDark: Bool, language: AppLanguage) -> some View {
        HStack(spacing: 12) {
            Text(language.text("Solid", "Helfärg"))
                .appTypography(.secondary)
                .foregroundStyle(useDark ? Color.white.opacity(0.72) : Color.secondary)
                .frame(width: semanticFieldColumnWidth, alignment: .leading)
            Text(language.text("Shade", "Shade"))
                .appTypography(.secondary)
                .foregroundStyle(useDark ? Color.white.opacity(0.72) : Color.secondary)
                .frame(width: semanticFieldColumnWidth, alignment: .leading)
        }
        .frame(height: semanticMatrixHeaderHeight, alignment: .bottomLeading)
    }

    private func semanticToneColorBinding(
        tone: AppSemanticTone,
        useDark: Bool,
        shaded: Bool
    ) -> Binding<String> {
        Binding(
            get: {
                let setting = toneBinding(for: tone, useDark: useDark).wrappedValue
                return shaded ? setting.shadeHex : setting.solidHex
            },
            set: { newValue in
                var setting = toneBinding(for: tone, useDark: useDark).wrappedValue
                if shaded {
                    setting.shadeHex = normalizedHex(newValue)
                } else {
                    setting.solidHex = normalizedHex(newValue)
                }
                toneBinding(for: tone, useDark: useDark).wrappedValue = setting
                scheduleAutosave()
            }
        )
    }

    private func compactColorHexField(text: Binding<String>, stroke: Color) -> some View {
        let preview = previewColor(for: text.wrappedValue)
        let foreground: Color = previewBrightness(for: preview) < 0.58 ? .white : .black
        let state = hexFieldState(for: text.wrappedValue)
        let resolvedStroke = state == .normal ? stroke : state.stroke

        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(preview)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(resolvedStroke, lineWidth: state.isInvalid ? 1.4 : 1)
                CommitFormattingTextField(
                    placeholder: "#RRGGBB",
                    text: text,
                    formatter: AppFieldParsers.canonicalHexColor,
                    showsRenewedSurface: false,
                    isBordered: false,
                    focusRingType: .none,
                    textColor: NSColor(foreground),
                    placeholderColor: NSColor(foreground.opacity(0.72)),
                    visualState: state,
                    liveVisualState: { hexFieldState(for: $0) }
                )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
            }
            .frame(width: 118)
            .help(state.helpText ?? "")

            ColorPicker("", selection: colorPickerBinding(for: text), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28)
        }
        .frame(width: semanticFieldColumnWidth, alignment: .leading)
    }

    private func presetControls(
        language: AppLanguage,
        selectedPresetID: Binding<String>,
        options: [(String, String)],
        presetName: Binding<String>,
        description: String,
        applyAction: @escaping () -> Void,
        updateAction: @escaping () -> Void,
        createAction: @escaping () -> Void,
        deleteAction: @escaping () -> Void,
        canDeleteSelected: Bool
    ) -> some View {
        let hasSelectedPreset = options.contains { $0.0 == selectedPresetID.wrappedValue }
        let selectedName = (
            options.first(where: { $0.0 == selectedPresetID.wrappedValue })?.1
                ?? presetName.wrappedValue
        ).trimmedOrNil ?? language.text("selected", "vald")
        let updateTitle = language.text("Update preset \(selectedName)", "Uppdatera förinställningen \(selectedName)")

        return VStack(alignment: .leading, spacing: 10) {
            Text(language.text("Presets", "Förinställningar"))
                .appTypography(.fieldLabel)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Selected preset", "Vald förinställning"))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                    AppMenuSelectionField(
                        selection: selectedPresetID,
                        options: options.map { (label: $0.1, value: $0.0) }
                    )
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Preset name", "Namn på förinställning"))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                    TextField(language.text("Preset name", "Namn på förinställning"), text: presetName)
                        .appTextInputChrome()
                        .frame(width: 220)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(language.text("Use selected", "Använd vald")) {
                            applyAction()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hasSelectedPreset)

                        Button {
                            updateAction()
                        } label: {
                            Text(updateTitle)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .appSaveButtonStyle()
                        .disabled(!hasSelectedPreset)
                        .frame(maxWidth: 260)
                    }

                    HStack(spacing: 8) {
                        Button(language.text("Save as new", "Spara som ny")) {
                            createAction()
                        }
                        .buttonStyle(.bordered)

                        AppDestructiveActionButton(
                            title: language.text("Delete preset", "Ta bort förinställning"),
                            cancelTitle: language.text("Cancel", "Avbryt"),
                            confirmationTitle: language.text("Delete preset?", "Ta bort förinställning?")
                        ) {
                            deleteAction()
                        }
                        .disabled(!canDeleteSelected)
                    }
                }

                Spacer()
            }

            Text(description)
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppPalette.secondaryCardSurface)
        )
    }

    private func semanticProfileControls(useDark: Bool, language: AppLanguage) -> some View {
        let presets = useDark ? darkSemanticColorPresets : lightSemanticColorPresets
        let selectedID = useDark ? selectedDarkSemanticColorPresetID : selectedLightSemanticColorPresetID
        let hasSelectedPreset = presets.contains { $0.id == selectedID }
        let selectedName = presets.first(where: { $0.id == selectedID })?.name.trimmedOrNil
            ?? language.text("selected profile", "vald profil")
        let updateTitle = language.text("Update \(selectedName)", "Uppdatera \(selectedName)")

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("Color profile", "Färgprofil"))
                        .appTypography(.fieldLabel)
                    Text(language.text("Choose one of the four fixed profiles. Edit the colors below, then update the selected profile if you want to keep those values.", "Välj en av de fyra fasta profilerna. Ändra färgerna nedan och uppdatera sedan vald profil om du vill spara värdena."))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    updateSelectedSemanticColorPreset(useDark: useDark, language: language)
                } label: {
                    Label(updateTitle, systemImage: "arrow.triangle.2.circlepath")
                        .lineLimit(1)
                }
                .appSaveButtonStyle()
                .disabled(!hasSelectedPreset)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        semanticPresetButton(
                            preset,
                            isSelected: preset.id == selectedID,
                            useDark: useDark,
                            language: language
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppPalette.secondaryCardSurface)
        )
    }

    private func semanticPresetButton(
        _ preset: AppSemanticColorPreset,
        isSelected: Bool,
        useDark: Bool,
        language: AppLanguage
    ) -> some View {
        Button {
            if useDark {
                selectedDarkSemanticColorPresetID = preset.id
            } else {
                selectedLightSemanticColorPresetID = preset.id
            }
            applySemanticColorPreset(preset, useDark: useDark)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(preset.name)
                    .appTypography(.secondary)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    ForEach(Array(semanticPresetSwatches(for: preset.colors).enumerated()), id: \.offset) { _, hex in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(previewColor(for: hex))
                            .frame(width: 26, height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(AppPalette.subtleBorder.opacity(0.72), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .appSelectableOptionSurface(
                isSelected: isSelected,
                selectedStroke: AppPalette.activeTabSurface.opacity(0.7),
                cornerRadius: 8,
                padding: 0
            )
        }
        .buttonStyle(.plain)
        .help(language.text("Apply \(preset.name)", "Använd \(preset.name)"))
    }

    private func semanticPresetSwatches(for colors: AppSemanticColorSettings) -> [String] {
        [
            colors.negative.solidHex,
            colors.inProgress.solidHex,
            colors.positive.solidHex,
            colors.neutral.solidHex
        ]
    }

    private func calendarFixedCategoryProfileControls(language: AppLanguage) -> some View {
        let presets = calendarCategoryColorPresets
        let selectedID = selectedCalendarCategoryColorPresetID
        let hasSelectedPreset = presets.contains { $0.id == selectedID }
        let selectedName = presets.first(where: { $0.id == selectedID })?.name.trimmedOrNil
            ?? language.text("selected profile", "vald profil")
        let updateTitle = language.text("Update \(selectedName)", "Uppdatera \(selectedName)")

        return AppSettingsCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text("Color profile", "Färgprofil"))
                            .appTypography(.fieldLabel)
                        Text(language.text("These profiles define the fixed calendar colors and four reusable activity colors.", "Dessa profiler definierar kalenderns fasta färger och fyra återanvändbara aktivitetsfärger."))
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        updateSelectedCalendarCategoryColorPreset(language: language)
                    } label: {
                        Label(updateTitle, systemImage: "arrow.triangle.2.circlepath")
                            .lineLimit(1)
                    }
                    .appSaveButtonStyle()
                    .disabled(!hasSelectedPreset)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets) { preset in
                            calendarCategoryPresetButton(
                                preset,
                                isSelected: preset.id == selectedID,
                                language: language
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func calendarCategoryPresetButton(
        _ preset: CalendarCategoryColorPreset,
        isSelected: Bool,
        language: AppLanguage
    ) -> some View {
        Button {
            selectedCalendarCategoryColorPresetID = preset.id
            applyCalendarCategoryColorPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(preset.name)
                    .appTypography(.secondary)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    ForEach(Array(calendarCategoryPresetSwatches(for: preset).enumerated()), id: \.offset) { _, hex in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(previewColor(for: hex))
                            .frame(width: 22, height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(AppPalette.subtleBorder.opacity(0.72), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .appSelectableOptionSurface(
                isSelected: isSelected,
                selectedStroke: AppPalette.activeTabSurface.opacity(0.7),
                cornerRadius: 8,
                padding: 0
            )
        }
        .buttonStyle(.plain)
        .help(language.text("Apply \(preset.name)", "Använd \(preset.name)"))
    }

    private func calendarCategoryPresetSwatches(for preset: CalendarCategoryColorPreset) -> [String] {
        [
            CalendarCategoryColorSetting.fixedColorID(for: .deadline),
            CalendarCategoryColorSetting.fixedColorID(for: .task),
            CalendarCategoryColorSetting.fixedColorID(for: .travel),
            CalendarCategoryColorSetting.fixedColorID(for: .uncategorized),
            CalendarCategoryColorSetting.activityColorID(for: .activity1),
            CalendarCategoryColorSetting.activityColorID(for: .activity2),
            CalendarCategoryColorSetting.activityColorID(for: .activity3),
            CalendarCategoryColorSetting.activityColorID(for: .activity4)
        ].compactMap { id in
            preset.settings.first(where: { $0.id == id })?.lightHexColor
        }
    }

    private func selectedPresetNameBinding(
        selectedPresetID: Binding<String>,
        nameForID: @escaping (String) -> String,
        setName: @escaping (String, String) -> Void
    ) -> Binding<String> {
        Binding(
            get: { nameForID(selectedPresetID.wrappedValue) },
            set: { newValue in
                setName(selectedPresetID.wrappedValue, newValue)
            }
        )
    }

    private func typographyRow(title rowTitle: String, style: Binding<AppTextStyleSetting>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(rowTitle)
                .appTypography(.fieldLabel)
                .frame(width: 150, alignment: .leading)

            AppMenuSelectionField(
                selection: Binding(
                    get: { style.wrappedValue.family },
                    set: {
                        style.wrappedValue.family = $0
                        scheduleAutosave()
                    }
                ),
                options: AppFontFamily.allCases.map { (title(for: $0), $0) },
                placeholder: nil
            )
            .frame(width: 160)

            Stepper(value: Binding(
                get: { style.wrappedValue.size },
                set: {
                    style.wrappedValue.size = max(12, min(48, $0))
                    scheduleAutosave()
                }
            ), in: 12...48, step: 1) {
                Text("\(Int(style.wrappedValue.size)) pt")
                    .appTypography(.body)
            }
            .frame(width: 120)

            AppMenuSelectionField(
                selection: Binding(
                    get: { style.wrappedValue.weight },
                    set: {
                        style.wrappedValue.weight = $0
                        scheduleAutosave()
                    }
                ),
                options: AppFontWeightSetting.allCases.map { (title(for: $0), $0) },
                placeholder: nil
            )
            .frame(width: 140)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func semanticColorRow(title: String, tone: Binding<AppSemanticToneSetting>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .appTypography(.fieldLabel)
                .frame(width: 140, alignment: .leading)

            colorHexField(
                title: store.language.text("Solid", "Helfärg"),
                text: Binding(
                    get: { tone.wrappedValue.solidHex },
                    set: {
                        tone.wrappedValue.solidHex = $0
                        scheduleAutosave()
                    }
                )
            )

            colorHexField(
                title: store.language.text("Shade", "Shade"),
                text: Binding(
                    get: { tone.wrappedValue.shadeHex },
                    set: {
                        tone.wrappedValue.shadeHex = $0
                        scheduleAutosave()
                    }
                )
            )

            semanticPreviewSwatch(
                title: store.language.text("Solid sample", "Helfärgsexempel"),
                color: previewColor(for: tone.wrappedValue.solidHex),
                text: store.language.text("Solid", "Helfärg")
            )

            semanticPreviewSwatch(
                title: store.language.text("Shade sample", "Shade-exempel"),
                color: previewColor(for: tone.wrappedValue.shadeHex),
                text: store.language.text("Shade", "Shade")
            )

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func colorHexField(title: String, text: Binding<String>) -> some View {
        let preview = previewColor(for: text.wrappedValue)
        let foreground: Color = previewBrightness(for: preview) < 0.58 ? .white : .black
        let state = hexFieldState(for: text.wrappedValue)
        let stroke = state == .normal ? AppPalette.border : state.stroke
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(preview)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(stroke, lineWidth: state.isInvalid ? 1.4 : 1)
                    CommitFormattingTextField(
                        placeholder: "#RRGGBB",
                        text: text,
                        formatter: AppFieldParsers.canonicalHexColor,
                        showsRenewedSurface: false,
                        isBordered: false,
                        focusRingType: .none,
                        textColor: NSColor(foreground),
                        placeholderColor: NSColor(foreground.opacity(0.72)),
                        visualState: state,
                        liveVisualState: { hexFieldState(for: $0) }
                    )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                }
                .frame(width: 118)
                .help(state.helpText ?? "")

                ColorPicker("", selection: colorPickerBinding(for: text), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28)
            }
        }
    }

    private func calendarDayHighlightRow(_ kind: CalendarDayHighlightKind, language: AppLanguage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.localizedName(language: language))
                    .appTypography(.fieldLabel)
                Text(language.text("Calendar day styling", "Stil för kalenderdag"))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
            }
            .frame(width: translationUsageColumnWidth, alignment: .leading)

            colorHexField(
                title: language.text("Text (light mode)", "Text (ljust läge)"),
                text: calendarDayHighlightColorBinding(for: kind, role: .text, usesDarkAppearance: false)
            )

            colorHexField(
                title: language.text("Background (light mode)", "Bakgrund (ljust läge)"),
                text: calendarDayHighlightColorBinding(for: kind, role: .background, usesDarkAppearance: false)
            )

            colorHexField(
                title: language.text("Text (dark mode)", "Text (mörkt läge)"),
                text: calendarDayHighlightColorBinding(for: kind, role: .text, usesDarkAppearance: true)
            )

            colorHexField(
                title: language.text("Background (dark mode)", "Bakgrund (mörkt läge)"),
                text: calendarDayHighlightColorBinding(for: kind, role: .background, usesDarkAppearance: true)
            )

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                .fill(AppPalette.secondaryCardSurface.opacity(AppRuntime.usesRenewedChrome ? 0.92 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
    }

    private func loadCalendarDayHighlightSettings() {
        calendarDayHighlightColors = Dictionary(firstWinsKeysWithValues: CalendarDayHighlightKind.allCases.map { kind in
            let stored = store.calendarDayHighlightColorSetting(kind)
            return (
                kind,
                EditableCalendarDayHighlightColors(
                    lightTextHex: stored?.lightTextHexColor ?? defaultCalendarDayHighlightTextHex(for: kind, usesDarkAppearance: false),
                    lightBackgroundHex: stored?.lightBackgroundHexColor ?? defaultCalendarDayHighlightBackgroundHex(for: kind, usesDarkAppearance: false),
                    darkTextHex: stored?.darkTextHexColor ?? defaultCalendarDayHighlightTextHex(for: kind, usesDarkAppearance: true),
                    darkBackgroundHex: stored?.darkBackgroundHexColor ?? defaultCalendarDayHighlightBackgroundHex(for: kind, usesDarkAppearance: true)
                )
            )
        })
    }

    private func calendarDayHighlightColorBinding(
        for kind: CalendarDayHighlightKind,
        role: CalendarDayHighlightColorRole,
        usesDarkAppearance: Bool
    ) -> Binding<String> {
        Binding(
            get: {
                let colors = calendarDayHighlightColors[kind] ?? EditableCalendarDayHighlightColors(
                    lightTextHex: defaultCalendarDayHighlightTextHex(for: kind, usesDarkAppearance: false),
                    lightBackgroundHex: defaultCalendarDayHighlightBackgroundHex(for: kind, usesDarkAppearance: false),
                    darkTextHex: defaultCalendarDayHighlightTextHex(for: kind, usesDarkAppearance: true),
                    darkBackgroundHex: defaultCalendarDayHighlightBackgroundHex(for: kind, usesDarkAppearance: true)
                )
                switch (role, usesDarkAppearance) {
                case (.text, false):
                    return colors.lightTextHex
                case (.background, false):
                    return colors.lightBackgroundHex
                case (.text, true):
                    return colors.darkTextHex
                case (.background, true):
                    return colors.darkBackgroundHex
                }
            },
            set: { newValue in
                var colors = calendarDayHighlightColors[kind] ?? EditableCalendarDayHighlightColors(
                    lightTextHex: defaultCalendarDayHighlightTextHex(for: kind, usesDarkAppearance: false),
                    lightBackgroundHex: defaultCalendarDayHighlightBackgroundHex(for: kind, usesDarkAppearance: false),
                    darkTextHex: defaultCalendarDayHighlightTextHex(for: kind, usesDarkAppearance: true),
                    darkBackgroundHex: defaultCalendarDayHighlightBackgroundHex(for: kind, usesDarkAppearance: true)
                )
                let normalized = normalizedHex(newValue)
                switch (role, usesDarkAppearance) {
                case (.text, false):
                    colors.lightTextHex = normalized
                case (.background, false):
                    colors.lightBackgroundHex = normalized
                case (.text, true):
                    colors.darkTextHex = normalized
                case (.background, true):
                    colors.darkBackgroundHex = normalized
                }
                calendarDayHighlightColors[kind] = colors
                scheduleAutosave()
            }
        )
    }

    private func loadColorPresetSettings() {
        calendarDayHighlightColorPresets = store.calendarDayHighlightColorPresets
        selectedCalendarDayHighlightColorPresetID = calendarDayHighlightColorPresets.first?.id ?? ""

        calendarCategoryColorPresets = store.calendarCategoryColorPresets
        selectedCalendarCategoryColorPresetID = matchingCalendarCategoryColorPresetID(in: calendarCategoryColorPresets)
            ?? calendarCategoryColorPresets.first?.id
            ?? ""

        lightSemanticColorPresets = store.appSemanticColorPresetsLight
        selectedLightSemanticColorPresetID = matchingSemanticColorPresetID(
            for: lightSemanticColors,
            in: lightSemanticColorPresets
        ) ?? lightSemanticColorPresets.first?.id
            ?? ""

        darkSemanticColorPresets = store.appSemanticColorPresetsDark
        selectedDarkSemanticColorPresetID = matchingSemanticColorPresetID(
            for: darkSemanticColors,
            in: darkSemanticColorPresets
        ) ?? darkSemanticColorPresets.first?.id
            ?? ""
    }

    private func matchingSemanticColorPresetID(
        for colors: AppSemanticColorSettings,
        in presets: [AppSemanticColorPreset]
    ) -> String? {
        let normalizedColors = normalizedSemanticColors(colors)
        return presets.first(where: { normalizedSemanticColors($0.colors) == normalizedColors })?.id
    }

    private func matchingCalendarCategoryColorPresetID(
        in presets: [CalendarCategoryColorPreset]
    ) -> String? {
        let currentSettings = currentCalendarCategoryPresetSettings()
        return presets.first(where: {
            GrantDataStore.resolvedCalendarFixedCategoryPresetSettings(
                $0.settings,
                fallback: currentSettings
            ) == currentSettings
        })?.id
    }

    private func resetSemanticColorProfilesToBuiltInDefaults() {
        lightSemanticColorPresets = GrantDataStore.standardAppSemanticColorPresets(useDarkAppearance: false)
        darkSemanticColorPresets = GrantDataStore.standardAppSemanticColorPresets(useDarkAppearance: true)
        selectedLightSemanticColorPresetID = lightSemanticColorPresets.first?.id ?? ""
        selectedDarkSemanticColorPresetID = darkSemanticColorPresets.first?.id ?? ""
        lightSemanticColors = normalizedSemanticColors(lightSemanticColorPresets.first?.colors ?? .default)
        darkSemanticColors = normalizedSemanticColors(darkSemanticColorPresets.first?.colors ?? .darkDefault)
        scheduleAutosave()
    }

    private func nextPresetName(base: String, existingNames: [String]) -> String {
        let normalizedExisting = Set(existingNames.map {
            $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sv_SE"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        })
        if !normalizedExisting.contains(base.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sv_SE"))) {
            return base
        }

        var index = 2
        while true {
            let candidate = "\(base) \(index)"
            let normalizedCandidate = candidate.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sv_SE"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedExisting.contains(normalizedCandidate) {
                return candidate
            }
            index += 1
        }
    }

    private func currentCalendarDayHighlightPreset(
        id: String = UUID().uuidString,
        named name: String
    ) -> CalendarDayHighlightColorPreset {
        CalendarDayHighlightColorPreset(
            id: id,
            name: name,
            settings: persistedCalendarDayHighlightColorSettings()
        )
    }

    private func currentCalendarCategoryColorPreset(
        id: String = UUID().uuidString,
        named name: String
    ) -> CalendarCategoryColorPreset {
        CalendarCategoryColorPreset(
            id: id,
            name: name,
            settings: currentCalendarCategoryPresetSettings()
        )
    }

    private func currentCalendarCategoryPresetSettings() -> [CalendarCategoryColorSetting] {
        var settings = CalendarFixedCategory.allCases.map { category in
            let colors = fixedCalendarCategoryColors[category] ?? EditableCalendarCategoryColors(
                lightHex: defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: false),
                darkHex: defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: true)
            )
            return CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.fixedColorID(for: category),
                lightHexColor: normalizedHex(colors.lightHex),
                darkHexColor: normalizedHex(colors.darkHex)
            )
        }

        settings.append(contentsOf: CalendarActivityColorRole.allCases.map { role in
            let colors = activityCategoryColors[role] ?? EditableCalendarCategoryColors(
                lightHex: defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: false),
                darkHex: defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: true)
            )
            return CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.activityColorID(for: role),
                lightHexColor: normalizedHex(colors.lightHex),
                darkHexColor: normalizedHex(colors.darkHex)
            )
        })

        settings.append(
            CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.newActivityCategoryDefaultColorID,
                lightHexColor: normalizedHex(defaultNewActivityCategoryColors.lightHex),
                darkHexColor: normalizedHex(defaultNewActivityCategoryColors.darkHex),
                colorSourceID: CalendarCategoryColorSetting.activityColorID(for: .activity1)
            )
        )

        return GrantDataStore.normalizedCalendarCategoryColorSettings(settings)
    }

    private func currentSemanticColorPreset(
        id: String = UUID().uuidString,
        named name: String,
        useDark: Bool
    ) -> AppSemanticColorPreset {
        AppSemanticColorPreset(
            id: id,
            name: name,
            colors: normalizedSemanticColors(useDark ? darkSemanticColors : lightSemanticColors)
        )
    }

    private func calendarDayHighlightPresetName(for id: String) -> String {
        calendarDayHighlightColorPresets.first(where: { $0.id == id })?.name ?? ""
    }

    private func calendarCategoryPresetName(for id: String) -> String {
        calendarCategoryColorPresets.first(where: { $0.id == id })?.name ?? ""
    }

    private func lightSemanticPresetName(for id: String) -> String {
        lightSemanticColorPresets.first(where: { $0.id == id })?.name ?? ""
    }

    private func darkSemanticPresetName(for id: String) -> String {
        darkSemanticColorPresets.first(where: { $0.id == id })?.name ?? ""
    }

    private func renameCalendarDayHighlightPreset(_ id: String, _ newName: String) {
        guard let index = calendarDayHighlightColorPresets.firstIndex(where: { $0.id == id }) else { return }
        calendarDayHighlightColorPresets[index].name = newName
        scheduleAutosave()
    }

    private func renameCalendarCategoryPreset(_ id: String, _ newName: String) {
        guard let index = calendarCategoryColorPresets.firstIndex(where: { $0.id == id }) else { return }
        calendarCategoryColorPresets[index].name = newName
        scheduleAutosave()
    }

    private func renameLightSemanticPreset(_ id: String, _ newName: String) {
        guard let index = lightSemanticColorPresets.firstIndex(where: { $0.id == id }) else { return }
        lightSemanticColorPresets[index].name = newName
        scheduleAutosave()
    }

    private func renameDarkSemanticPreset(_ id: String, _ newName: String) {
        guard let index = darkSemanticColorPresets.firstIndex(where: { $0.id == id }) else { return }
        darkSemanticColorPresets[index].name = newName
        scheduleAutosave()
    }

    private func updateSelectedCalendarDayHighlightPreset(language _: AppLanguage) {
        guard let index = calendarDayHighlightColorPresets.firstIndex(where: { $0.id == selectedCalendarDayHighlightColorPresetID }) else {
            createCurrentCalendarDayHighlightPreset(language: store.language)
            return
        }
        let selectedID = calendarDayHighlightColorPresets[index].id
        let name = calendarDayHighlightColorPresets[index].name.trimmedOrNil ?? "Standard"
        calendarDayHighlightColorPresets[index] = currentCalendarDayHighlightPreset(id: selectedID, named: name)
        selectedCalendarDayHighlightColorPresetID = selectedID
        scheduleAutosave()
    }

    private func createCurrentCalendarDayHighlightPreset(language: AppLanguage) {
        let baseName = calendarDayHighlightPresetName(for: selectedCalendarDayHighlightColorPresetID).trimmedOrNil
            ?? language.text("New preset", "Ny förinställning")
        let name = nextPresetName(
            base: baseName,
            existingNames: calendarDayHighlightColorPresets.map(\.name)
        )
        let preset = currentCalendarDayHighlightPreset(named: name)
        calendarDayHighlightColorPresets.append(preset)
        selectedCalendarDayHighlightColorPresetID = preset.id
        scheduleAutosave()
    }

    private func canDeleteCalendarDayHighlightPreset(id: String) -> Bool {
        !isBuiltInColorPresetID(id) && calendarDayHighlightColorPresets.contains { $0.id == id }
    }

    private func deleteSelectedCalendarDayHighlightPreset() {
        guard canDeleteCalendarDayHighlightPreset(id: selectedCalendarDayHighlightColorPresetID),
              let index = calendarDayHighlightColorPresets.firstIndex(where: { $0.id == selectedCalendarDayHighlightColorPresetID }) else {
            return
        }

        calendarDayHighlightColorPresets.remove(at: index)
        if calendarDayHighlightColorPresets.isEmpty {
            let fallback = currentCalendarDayHighlightPreset(id: "default", named: "Standard")
            calendarDayHighlightColorPresets = [fallback]
            selectedCalendarDayHighlightColorPresetID = fallback.id
        } else {
            let nextIndex = min(index, calendarDayHighlightColorPresets.count - 1)
            selectedCalendarDayHighlightColorPresetID = calendarDayHighlightColorPresets[nextIndex].id
        }
        scheduleAutosave()
    }

    private func updateSelectedCalendarCategoryColorPreset(language _: AppLanguage) {
        guard let index = calendarCategoryColorPresets.firstIndex(where: { $0.id == selectedCalendarCategoryColorPresetID }) else {
            return
        }
        let selectedID = calendarCategoryColorPresets[index].id
        let name = calendarCategoryColorPresets[index].name.trimmedOrNil ?? "Standard"
        calendarCategoryColorPresets[index] = currentCalendarCategoryColorPreset(id: selectedID, named: name)
        selectedCalendarCategoryColorPresetID = selectedID
        scheduleAutosave()
    }

    private func createCurrentCalendarCategoryColorPreset(language: AppLanguage) {
        let baseName = calendarCategoryPresetName(for: selectedCalendarCategoryColorPresetID).trimmedOrNil
            ?? language.text("New preset", "Ny förinställning")
        let name = nextPresetName(
            base: baseName,
            existingNames: calendarCategoryColorPresets.map(\.name)
        )
        let preset = currentCalendarCategoryColorPreset(named: name)
        calendarCategoryColorPresets.append(preset)
        selectedCalendarCategoryColorPresetID = preset.id
        scheduleAutosave()
    }

    private func canDeleteCalendarCategoryColorPreset(id: String) -> Bool {
        !isBuiltInColorPresetID(id) && calendarCategoryColorPresets.contains { $0.id == id }
    }

    private func deleteSelectedCalendarCategoryColorPreset() {
        guard canDeleteCalendarCategoryColorPreset(id: selectedCalendarCategoryColorPresetID),
              let index = calendarCategoryColorPresets.firstIndex(where: { $0.id == selectedCalendarCategoryColorPresetID }) else {
            return
        }

        calendarCategoryColorPresets.remove(at: index)
        if calendarCategoryColorPresets.isEmpty {
            let fallback = currentCalendarCategoryColorPreset(id: "default", named: "Standard")
            calendarCategoryColorPresets = [fallback]
            selectedCalendarCategoryColorPresetID = fallback.id
        } else {
            let nextIndex = min(index, calendarCategoryColorPresets.count - 1)
            selectedCalendarCategoryColorPresetID = calendarCategoryColorPresets[nextIndex].id
        }
        scheduleAutosave()
    }

    private func updateSelectedSemanticColorPreset(useDark: Bool, language _: AppLanguage) {
        if useDark {
            guard let index = darkSemanticColorPresets.firstIndex(where: { $0.id == selectedDarkSemanticColorPresetID }) else {
                return
            }
            let selectedID = darkSemanticColorPresets[index].id
            let name = darkSemanticColorPresets[index].name.trimmedOrNil ?? "Standard"
            darkSemanticColorPresets[index] = currentSemanticColorPreset(id: selectedID, named: name, useDark: true)
            selectedDarkSemanticColorPresetID = selectedID
        } else {
            guard let index = lightSemanticColorPresets.firstIndex(where: { $0.id == selectedLightSemanticColorPresetID }) else {
                return
            }
            let selectedID = lightSemanticColorPresets[index].id
            let name = lightSemanticColorPresets[index].name.trimmedOrNil ?? "Standard"
            lightSemanticColorPresets[index] = currentSemanticColorPreset(id: selectedID, named: name, useDark: false)
            selectedLightSemanticColorPresetID = selectedID
        }
        scheduleAutosave()
    }

    private func createCurrentSemanticColorPreset(useDark: Bool, language: AppLanguage) {
        let presets = useDark ? darkSemanticColorPresets : lightSemanticColorPresets
        let selectedID = useDark ? selectedDarkSemanticColorPresetID : selectedLightSemanticColorPresetID
        let baseName = presets.first(where: { $0.id == selectedID })?.name.trimmedOrNil
            ?? language.text("New preset", "Ny förinställning")
        let existingNames = presets.map(\.name)
        let name = nextPresetName(
            base: baseName,
            existingNames: existingNames
        )
        let preset = currentSemanticColorPreset(named: name, useDark: useDark)
        if useDark {
            darkSemanticColorPresets.append(preset)
            selectedDarkSemanticColorPresetID = preset.id
        } else {
            lightSemanticColorPresets.append(preset)
            selectedLightSemanticColorPresetID = preset.id
        }
        scheduleAutosave()
    }

    private func canDeleteSemanticColorPreset(id: String, useDark: Bool) -> Bool {
        !isBuiltInColorPresetID(id) && (useDark ? darkSemanticColorPresets : lightSemanticColorPresets).contains { $0.id == id }
    }

    private func isBuiltInColorPresetID(_ id: String) -> Bool {
        GrantDataStore.isManagedAppSemanticColorPresetID(id)
    }

    private func deleteSelectedSemanticColorPreset(useDark: Bool) {
        if useDark {
            guard canDeleteSemanticColorPreset(id: selectedDarkSemanticColorPresetID, useDark: true),
                  let index = darkSemanticColorPresets.firstIndex(where: { $0.id == selectedDarkSemanticColorPresetID }) else {
                return
            }
            darkSemanticColorPresets.remove(at: index)
            if darkSemanticColorPresets.isEmpty {
                let fallback = currentSemanticColorPreset(id: "default", named: "Standard", useDark: true)
                darkSemanticColorPresets = [fallback]
                selectedDarkSemanticColorPresetID = fallback.id
            } else {
                let nextIndex = min(index, darkSemanticColorPresets.count - 1)
                selectedDarkSemanticColorPresetID = darkSemanticColorPresets[nextIndex].id
            }
        } else {
            guard canDeleteSemanticColorPreset(id: selectedLightSemanticColorPresetID, useDark: false),
                  let index = lightSemanticColorPresets.firstIndex(where: { $0.id == selectedLightSemanticColorPresetID }) else {
                return
            }
            lightSemanticColorPresets.remove(at: index)
            if lightSemanticColorPresets.isEmpty {
                let fallback = currentSemanticColorPreset(id: "default", named: "Standard", useDark: false)
                lightSemanticColorPresets = [fallback]
                selectedLightSemanticColorPresetID = fallback.id
            } else {
                let nextIndex = min(index, lightSemanticColorPresets.count - 1)
                selectedLightSemanticColorPresetID = lightSemanticColorPresets[nextIndex].id
            }
        }
        scheduleAutosave()
    }

    private func applySelectedCalendarDayHighlightPreset() {
        guard let preset = calendarDayHighlightColorPresets.first(where: { $0.id == selectedCalendarDayHighlightColorPresetID }) else { return }
        applyCalendarDayHighlightPreset(preset)
    }

    private func applyCalendarDayHighlightPreset(_ preset: CalendarDayHighlightColorPreset) {
        let settingsByID = Dictionary(firstWinsKeysWithValues: preset.settings.map { ($0.id, $0) })
        for kind in CalendarDayHighlightKind.allCases {
            let id = CalendarDayHighlightColorSetting.id(for: kind)
            guard let setting = settingsByID[id] else { continue }
            calendarDayHighlightColors[kind] = EditableCalendarDayHighlightColors(
                lightTextHex: setting.lightTextHexColor,
                lightBackgroundHex: setting.lightBackgroundHexColor,
                darkTextHex: setting.darkTextHexColor,
                darkBackgroundHex: setting.darkBackgroundHexColor
            )
        }
        scheduleAutosave()
    }

    private func applySelectedCalendarCategoryColorPreset() {
        guard let preset = calendarCategoryColorPresets.first(where: { $0.id == selectedCalendarCategoryColorPresetID }) else { return }
        applyCalendarCategoryColorPreset(preset)
    }

    private func applyCalendarCategoryColorPreset(_ preset: CalendarCategoryColorPreset) {
        let previousDefault = defaultNewActivityCategoryColors
        let settingsByID = Dictionary(firstWinsKeysWithValues: preset.settings.map { ($0.id, $0) })

        for category in CalendarFixedCategory.allCases {
            let id = CalendarCategoryColorSetting.fixedColorID(for: category)
            guard let setting = settingsByID[id] else { continue }
            fixedCalendarCategoryColors[category] = EditableCalendarCategoryColors(
                lightHex: setting.lightHexColor,
                darkHex: setting.darkHexColor
            )
        }

        for role in CalendarActivityColorRole.allCases {
            let id = CalendarCategoryColorSetting.activityColorID(for: role)
            guard let setting = settingsByID[id] else { continue }
            activityCategoryColors[role] = EditableCalendarCategoryColors(
                lightHex: setting.lightHexColor,
                darkHex: setting.darkHexColor
            )
        }

        let defaultSetting = settingsByID[CalendarCategoryColorSetting.newActivityCategoryDefaultColorID]
        defaultNewActivityCategoryColors = activityCategoryColors[.activity1]
            ?? EditableCalendarCategoryColors(
                lightHex: defaultSetting?.lightHexColor ?? defaultCalendarMeetingCategoryColorHex(for: "", usesDarkAppearance: false),
                darkHex: defaultSetting?.darkHexColor ?? defaultCalendarMeetingCategoryColorHex(for: "", usesDarkAppearance: true)
            )

        for index in editableCalendarMeetingCategories.indices {
            let category = editableCalendarMeetingCategories[index]
            let isBlankRow = category.name.trimmedOrNil == nil && category.originalName?.trimmedOrNil == nil
            let inheritedOldDefault = normalizedHex(category.lightColorHex) == normalizedHex(previousDefault.lightHex)
                && normalizedHex(category.darkColorHex) == normalizedHex(previousDefault.darkHex)
            if let colorSourceID = category.colorSourceID,
               let colors = editableCalendarCategoryColors(for: colorSourceID) {
                editableCalendarMeetingCategories[index].lightColorHex = colors.lightHex
                editableCalendarMeetingCategories[index].darkColorHex = colors.darkHex
            } else if isBlankRow || inheritedOldDefault {
                editableCalendarMeetingCategories[index].lightColorHex = defaultNewActivityCategoryColors.lightHex
                editableCalendarMeetingCategories[index].darkColorHex = defaultNewActivityCategoryColors.darkHex
                editableCalendarMeetingCategories[index].colorSourceID = CalendarCategoryColorSetting.activityColorID(for: .activity1)
            }
        }

        ensureTrailingEditableCalendarMeetingCategoryRow()
        scheduleAutosave()
    }

    private func calendarCategoryPresetSetting(
        named name: String,
        settingsByID: [String: CalendarCategoryColorSetting]
    ) -> CalendarCategoryColorSetting? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return settingsByID[CalendarCategoryColorSetting.fixedColorID(for: .uncategorized)]
        }

        let exactID = CalendarCategoryColorSetting.meetingColorID(for: trimmed)
        if let exact = settingsByID[exactID] {
            return exact
        }

        // A category with the role "Clinical time" or "Leave" borrows the
        // preset color of another category with the same role.
        let ownKey = normalizedCalendarCategoryLookupKey(trimmed)
        guard let row = editableCalendarMeetingCategories.first(where: {
            normalizedCalendarCategoryLookupKey($0.name) == ownKey
        }), row.isClinicalTime || row.isLeave else { return nil }
        for candidate in editableCalendarMeetingCategories {
            let candidateKey = normalizedCalendarCategoryLookupKey(candidate.name)
            guard !candidateKey.isEmpty, candidateKey != ownKey else { continue }
            let sharesRole = (row.isClinicalTime && candidate.isClinicalTime) || (row.isLeave && candidate.isLeave)
            guard sharesRole,
                  let fallback = settingsByID[CalendarCategoryColorSetting.meetingColorID(for: candidate.name)] else {
                continue
            }
            return fallback
        }
        return nil
    }

    private func applySelectedSemanticColorPreset(useDark: Bool) {
        let presets = useDark ? darkSemanticColorPresets : lightSemanticColorPresets
        let selectedID = useDark ? selectedDarkSemanticColorPresetID : selectedLightSemanticColorPresetID
        guard let preset = presets.first(where: { $0.id == selectedID }) else { return }
        applySemanticColorPreset(preset, useDark: useDark)
    }

    private func applySemanticColorPreset(_ preset: AppSemanticColorPreset, useDark: Bool) {
        if useDark {
            darkSemanticColors = normalizedSemanticColors(preset.colors)
        } else {
            lightSemanticColors = normalizedSemanticColors(preset.colors)
        }
        scheduleAutosave()
    }

    private func fixedCalendarCategoryRow(_ category: CalendarFixedCategory, language: AppLanguage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.localizedName(language: language))
                    .appTypography(.fieldLabel)
                Text(language.text("Fixed category", "Fast kategori"))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
            }
            .frame(width: translationUsageColumnWidth, alignment: .leading)

            colorHexField(
                title: language.text("Light mode", "Ljust läge"),
                text: fixedCalendarCategoryColorBinding(for: category, usesDarkAppearance: false)
            )

            colorHexField(
                title: language.text("Dark mode", "Mörkt läge"),
                text: fixedCalendarCategoryColorBinding(for: category, usesDarkAppearance: true)
            )

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                .fill(AppPalette.secondaryCardSurface.opacity(AppRuntime.usesRenewedChrome ? 0.92 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
    }

    private func activityCalendarCategoryColorRow(_ role: CalendarActivityColorRole, language: AppLanguage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(role.localizedName(language: language))
                    .appTypography(.fieldLabel)
                Text(language.text("Reusable activity color", "Återanvändbar aktivitetsfärg"))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
            }
            .frame(width: translationUsageColumnWidth, alignment: .leading)

            colorHexField(
                title: language.text("Light mode", "Ljust läge"),
                text: activityCalendarCategoryColorBinding(for: role, usesDarkAppearance: false)
            )

            colorHexField(
                title: language.text("Dark mode", "Mörkt läge"),
                text: activityCalendarCategoryColorBinding(for: role, usesDarkAppearance: true)
            )

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                .fill(AppPalette.secondaryCardSurface.opacity(AppRuntime.usesRenewedChrome ? 0.92 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
    }

    private func newActivityCategoryDefaultColorRow(language: AppLanguage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text("Default color for new activity categories", "Standardfärg för nya aktivitetskategorier"))
                    .appTypography(.fieldLabel)
                Text(language.text("Used for new activity categories and for existing categories without their own saved color.", "Används för nya aktivitetskategorier och för befintliga kategorier som saknar egen sparad färg."))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
            }
            .frame(width: translationUsageColumnWidth, alignment: .leading)

            colorHexField(
                title: language.text("Light mode", "Ljust läge"),
                text: newActivityCategoryDefaultColorBinding(usesDarkAppearance: false)
            )

            colorHexField(
                title: language.text("Dark mode", "Mörkt läge"),
                text: newActivityCategoryDefaultColorBinding(usesDarkAppearance: true)
            )

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                .fill(AppPalette.secondaryCardSurface.opacity(AppRuntime.usesRenewedChrome ? 0.92 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
    }

    private func editableCalendarMeetingCategoryRow(
        index: Int,
        category: EditableCalendarMeetingCategory,
        language: AppLanguage
    ) -> some View {
        let showsControls = category.name.trimmedOrNil != nil || category.originalName?.trimmedOrNil != nil
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Category", "Kategori"))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                TextField(
                    language.text("Category", "Kategori"),
                    text: editableCalendarMeetingCategoryNameBinding(at: index)
                )
                .focused($focusedCalendarMeetingCategoryID, equals: category.id)
                .appTextInputChrome(tracksFocus: false)
                .appKeyboardFocusPulse(isFocused: focusedCalendarMeetingCategoryID == category.id)
            }
            .frame(width: translationUsageColumnWidth, alignment: .leading)

            calendarMeetingCategoryColorSourceField(at: index, category: category, language: language)

            calendarMeetingCategorySourcePreview(category: category, usesDarkAppearance: false, language: language)

            calendarMeetingCategorySourcePreview(category: category, usesDarkAppearance: true, language: language)

            if showsControls {
                calendarMeetingCategoryFlagToggles(at: index, language: language)
            }

            if showsControls {
                VStack(spacing: 6) {
                    Button {
                        moveEditableCalendarMeetingCategory(at: index, delta: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveEditableCalendarMeetingCategory(at: index, delta: -1))

                    Button {
                        moveEditableCalendarMeetingCategory(at: index, delta: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveEditableCalendarMeetingCategory(at: index, delta: 1))
                }
                .foregroundStyle(AppPalette.appText)
                .padding(.top, 24)

                AppRowDeleteIconButton(
                    title: language.text("Remove category", "Ta bort kategori"),
                    cancelTitle: language.text("Cancel", "Avbryt"),
                    confirmationTitle: language.text("Remove category?", "Ta bort kategori?"),
                    action: { requestEditableCalendarMeetingCategoryRemoval(at: index) },
                    storeAsksFirst: { editableCalendarMeetingCategoryRemovalAsksFirst(at: index) }
                )
                .padding(.top, 24)
            } else {
                HStack(spacing: 12) {
                    Color.clear
                        .frame(width: 18, height: 42)
                    Color.clear
                        .frame(width: 18, height: 18)
                }
                    .padding(.top, 24)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                .fill(AppPalette.secondaryCardSurface.opacity(AppRuntime.usesRenewedChrome ? 0.92 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
    }

    private func calendarMeetingCategoryColorSourceField(
        at index: Int,
        category: EditableCalendarMeetingCategory,
        language: AppLanguage
    ) -> some View {
        let options = calendarCategoryColorSourceOptions(for: category, language: language)
        return VStack(alignment: .leading, spacing: 4) {
            Text(language.text("Color", "Färg"))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
            if AppRuntime.usesRenewedChrome {
                AppMenuSelectionField(
                    selection: calendarMeetingCategoryColorSourceBinding(at: index),
                    options: options,
                    placeholder: nil
                )
                .frame(width: 190)
            } else {
                Picker("", selection: calendarMeetingCategoryColorSourceBinding(at: index)) {
                    ForEach(options, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 190)
            }
        }
    }

    private func calendarMeetingCategorySourcePreview(
        category: EditableCalendarMeetingCategory,
        usesDarkAppearance: Bool,
        language: AppLanguage
    ) -> some View {
        let hex = resolvedCalendarCategoryColorHex(for: category, usesDarkAppearance: usesDarkAppearance)
        let preview = previewColor(for: hex)
        let foreground: Color = previewBrightness(for: preview) < 0.58 ? .white : .black
        return VStack(alignment: .leading, spacing: 4) {
            Text(usesDarkAppearance ? language.text("Dark mode", "Mörkt läge") : language.text("Light mode", "Ljust läge"))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
            Text(hex)
                .appTypography(.secondary)
                .foregroundStyle(foreground)
                .padding(.horizontal, 8)
                .frame(width: 118, height: 32, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(preview)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppPalette.border, lineWidth: 1)
                )
        }
    }

    private func calendarCategoryColorSourceOptions(
        for category: EditableCalendarMeetingCategory,
        language: AppLanguage
    ) -> [(label: String, value: String)] {
        var options: [(label: String, value: String)] = []
        if category.colorSourceID?.trimmedOrNil == nil {
            options.append((language.text("Saved custom color", "Sparad egen färg"), legacyCustomCalendarCategoryColorSourceID))
        }
        options.append(contentsOf: CalendarActivityColorRole.allCases.map { role in
            (role.localizedName(language: language), CalendarCategoryColorSetting.activityColorID(for: role))
        })
        options.append(contentsOf: CalendarFixedCategory.allCases.map { fixed in
            (fixed.localizedName(language: language), CalendarCategoryColorSetting.fixedColorID(for: fixed))
        })
        return options
    }

    private func resolvedCalendarCategoryColorHex(
        for category: EditableCalendarMeetingCategory,
        usesDarkAppearance: Bool
    ) -> String {
        if let colorSourceID = category.colorSourceID?.trimmedOrNil,
           let colors = editableCalendarCategoryColors(for: colorSourceID) {
            return usesDarkAppearance ? colors.darkHex : colors.lightHex
        }
        return usesDarkAppearance ? category.darkColorHex : category.lightColorHex
    }

    private func editableCalendarCategoryColors(for sourceID: String) -> EditableCalendarCategoryColors? {
        if let role = CalendarActivityColorRole.allCases.first(where: { CalendarCategoryColorSetting.activityColorID(for: $0) == sourceID }) {
            return activityCategoryColors[role]
        }
        if let fixed = CalendarFixedCategory.allCases.first(where: { CalendarCategoryColorSetting.fixedColorID(for: $0) == sourceID }) {
            return fixedCalendarCategoryColors[fixed]
        }
        return nil
    }

    private func loadCalendarCategorySettings() {
        fixedCalendarCategoryColors = Dictionary(firstWinsKeysWithValues: CalendarFixedCategory.allCases.map { category in
            let stored = store.calendarFixedCategoryColorSetting(category)
            return (
                category,
                EditableCalendarCategoryColors(
                    lightHex: stored?.lightHexColor ?? defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: false),
                    darkHex: stored?.darkHexColor ?? defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: true)
                )
            )
        })
        let settingsByID = Dictionary(firstWinsKeysWithValues: store.calendarCategoryColorSettings.map { ($0.id, $0) })
        activityCategoryColors = Dictionary(firstWinsKeysWithValues: CalendarActivityColorRole.allCases.map { role in
            let id = CalendarCategoryColorSetting.activityColorID(for: role)
            let stored = settingsByID[id]
            return (
                role,
                EditableCalendarCategoryColors(
                    lightHex: stored?.lightHexColor ?? defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: false),
                    darkHex: stored?.darkHexColor ?? defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: true)
                )
            )
        })
        defaultNewActivityCategoryColors = EditableCalendarCategoryColors(
            lightHex: store.calendarNewActivityCategoryDefaultColorHex(usesDarkAppearance: false)
                ?? activityCategoryColors[.activity1]?.lightHex
                ?? defaultCalendarActivityCategoryColorHex(for: .activity1, usesDarkAppearance: false),
            darkHex: store.calendarNewActivityCategoryDefaultColorHex(usesDarkAppearance: true)
                ?? activityCategoryColors[.activity1]?.darkHex
                ?? defaultCalendarActivityCategoryColorHex(for: .activity1, usesDarkAppearance: true)
        )
        editableCalendarMeetingCategories = store.calendarKnownMeetingCategories.map { name in
            let stored = store.calendarMeetingCategoryColorSetting(named: name)
            let lightHex = stored?.lightHexColor ?? defaultNewActivityCategoryColors.lightHex
            let darkHex = stored?.darkHexColor ?? defaultNewActivityCategoryColors.darkHex
            let behavior = store.calendarCategoryBehavior(named: name)
            return EditableCalendarMeetingCategory(
                originalName: name,
                name: name,
                lightColorHex: lightHex,
                darkColorHex: darkHex,
                colorSourceID: stored?.colorSourceID ?? matchingCalendarCategoryColorSourceID(lightHex: lightHex, darkHex: darkHex),
                excludedFromMeetingStatistics: behavior.excludedFromMeetingStatistics,
                isClinicalTime: behavior.isClinicalTime,
                isLeave: behavior.isLeave
            )
        }
        loadedCalendarCategoryBehaviors = persistedCalendarCategoryBehaviors()
        ensureTrailingEditableCalendarMeetingCategoryRow()
    }

    private func matchingCalendarCategoryColorSourceID(lightHex: String, darkHex: String) -> String? {
        let normalizedLight = normalizedHex(lightHex)
        let normalizedDark = normalizedHex(darkHex)
        for role in CalendarActivityColorRole.allCases {
            guard let colors = activityCategoryColors[role] else { continue }
            if normalizedHex(colors.lightHex) == normalizedLight,
               normalizedHex(colors.darkHex) == normalizedDark {
                return CalendarCategoryColorSetting.activityColorID(for: role)
            }
        }
        for category in CalendarFixedCategory.allCases {
            guard let colors = fixedCalendarCategoryColors[category] else { continue }
            if normalizedHex(colors.lightHex) == normalizedLight,
               normalizedHex(colors.darkHex) == normalizedDark {
                return CalendarCategoryColorSetting.fixedColorID(for: category)
            }
        }
        return nil
    }

    private func resetCalendarCategoryColors() {
        calendarCategoryColorPresets = GrantDataStore.standardCalendarCategoryColorPresets()
        selectedCalendarCategoryColorPresetID = calendarCategoryColorPresets.first?.id ?? ""
        for category in CalendarFixedCategory.allCases {
            fixedCalendarCategoryColors[category] = EditableCalendarCategoryColors(
                lightHex: defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: false),
                darkHex: defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: true)
            )
        }
        for role in CalendarActivityColorRole.allCases {
            activityCategoryColors[role] = EditableCalendarCategoryColors(
                lightHex: defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: false),
                darkHex: defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: true)
            )
        }
        let previousDefault = defaultNewActivityCategoryColors
        defaultNewActivityCategoryColors = activityCategoryColors[.activity1] ?? EditableCalendarCategoryColors(
            lightHex: defaultCalendarActivityCategoryColorHex(for: .activity1, usesDarkAppearance: false),
            darkHex: defaultCalendarActivityCategoryColorHex(for: .activity1, usesDarkAppearance: true)
        )
        for index in editableCalendarMeetingCategories.indices {
            let category = editableCalendarMeetingCategories[index]
            let isBlankRow = category.name.trimmedOrNil == nil && category.originalName?.trimmedOrNil == nil
            let inheritedOldDefault = normalizedHex(category.lightColorHex) == normalizedHex(previousDefault.lightHex)
                && normalizedHex(category.darkColorHex) == normalizedHex(previousDefault.darkHex)
            guard isBlankRow || inheritedOldDefault else { continue }
            editableCalendarMeetingCategories[index].lightColorHex = defaultNewActivityCategoryColors.lightHex
            editableCalendarMeetingCategories[index].darkColorHex = defaultNewActivityCategoryColors.darkHex
            editableCalendarMeetingCategories[index].colorSourceID = CalendarCategoryColorSetting.activityColorID(for: .activity1)
        }
        ensureTrailingEditableCalendarMeetingCategoryRow()
        scheduleAutosave()
    }

    private func ensureTrailingEditableCalendarMeetingCategoryRow() {
        let focusedID = focusedCalendarMeetingCategoryID
        editableCalendarMeetingCategories.removeAll { category in
            category.name.trimmedOrNil == nil
                && category.originalName == nil
                && category.id != focusedID
        }

        if let focusedID,
           let focusedIndex = editableCalendarMeetingCategories.firstIndex(where: { $0.id == focusedID }),
           editableCalendarMeetingCategories[focusedIndex].name.trimmedOrNil == nil,
           editableCalendarMeetingCategories[focusedIndex].originalName == nil,
           focusedIndex != editableCalendarMeetingCategories.count - 1 {
            let focusedCategory = editableCalendarMeetingCategories.remove(at: focusedIndex)
            editableCalendarMeetingCategories.append(focusedCategory)
        }

        guard !editableCalendarMeetingCategories.contains(where: { $0.name.trimmedOrNil == nil && $0.originalName == nil }) else {
            return
        }

        editableCalendarMeetingCategories.append(
            EditableCalendarMeetingCategory(
                originalName: nil,
                name: "",
                lightColorHex: defaultNewActivityCategoryColors.lightHex,
                darkColorHex: defaultNewActivityCategoryColors.darkHex,
                colorSourceID: CalendarCategoryColorSetting.activityColorID(for: .activity1)
            )
        )
    }

    private func removeEditableCalendarMeetingCategory(at index: Int) {
        guard editableCalendarMeetingCategories.indices.contains(index) else { return }
        editableCalendarMeetingCategories.remove(at: index)
        ensureTrailingEditableCalendarMeetingCategoryRow()
        scheduleAutosave()
    }

    private func canMoveEditableCalendarMeetingCategory(at index: Int, delta: Int) -> Bool {
        guard editableCalendarMeetingCategories.indices.contains(index) else { return false }
        guard editableCalendarMeetingCategories[index].name.trimmedOrNil != nil
                || editableCalendarMeetingCategories[index].originalName?.trimmedOrNil != nil else { return false }

        let movableCount = editableCalendarMeetingCategories.reduce(into: 0) { count, category in
            if category.name.trimmedOrNil != nil || category.originalName?.trimmedOrNil != nil {
                count += 1
            }
        }
        let destination = index + delta
        return destination >= 0 && destination < movableCount
    }

    private func moveEditableCalendarMeetingCategory(at index: Int, delta: Int) {
        guard canMoveEditableCalendarMeetingCategory(at: index, delta: delta) else { return }
        let destination = index + delta
        let category = editableCalendarMeetingCategories.remove(at: index)
        editableCalendarMeetingCategories.insert(category, at: destination)
        ensureTrailingEditableCalendarMeetingCategoryRow()
        scheduleAutosave()
    }

    /// Round 17: true when removing this category opens the "category in use"
    /// sheet, which already asks; the trash icon then skips its own question.
    private func editableCalendarMeetingCategoryRemovalAsksFirst(at index: Int) -> Bool {
        guard editableCalendarMeetingCategories.indices.contains(index) else { return false }
        let category = editableCalendarMeetingCategories[index]
        guard let sourceCategoryName = calendarMeetingCategoryDeletionSourceName(for: category) else {
            return false
        }
        return calendarMeetingCategoryUsageCount(in: store.calendarMeetingRecords, named: sourceCategoryName) > 0
    }

    private func requestEditableCalendarMeetingCategoryRemoval(at index: Int) {
        guard editableCalendarMeetingCategories.indices.contains(index) else { return }
        let category = editableCalendarMeetingCategories[index]
        guard let sourceCategoryName = calendarMeetingCategoryDeletionSourceName(for: category) else {
            removeEditableCalendarMeetingCategory(at: index)
            return
        }

        let usageCount = calendarMeetingCategoryUsageCount(in: store.calendarMeetingRecords, named: sourceCategoryName)
        guard usageCount > 0 else {
            removeEditableCalendarMeetingCategory(at: index)
            return
        }

        let replacementOptions = availableCalendarMeetingCategoryTransferTargets(
            excludingRowID: category.id,
            sourceCategoryName: sourceCategoryName
        )
        pendingCalendarMeetingCategoryDeletion = PendingCalendarMeetingCategoryDeletion(
            rowID: category.id,
            sourceCategoryName: sourceCategoryName,
            usageCount: usageCount,
            replacementCategoryName: replacementOptions.first ?? ""
        )
    }

    private func calendarMeetingCategoryDeletionSourceName(
        for category: EditableCalendarMeetingCategory
    ) -> String? {
        category.originalName?.trimmedOrNil ?? category.name.trimmedOrNil
    }

    private func availableCalendarMeetingCategoryTransferTargets(
        excludingRowID rowID: String,
        sourceCategoryName: String
    ) -> [String] {
        let sourceLookupKey = normalizedCalendarCategoryLookupKey(sourceCategoryName)
        return GrantDataStore.normalizedCalendarMeetingTypeOptions(
            editableCalendarMeetingCategories.compactMap { category in
                guard category.id != rowID else { return nil }
                return category.name.trimmedOrNil
            }
        )
        .filter { normalizedCalendarCategoryLookupKey($0) != sourceLookupKey }
    }

    private func pendingCalendarMeetingCategoryReplacementBinding() -> Binding<String> {
        Binding(
            get: { pendingCalendarMeetingCategoryDeletion?.replacementCategoryName ?? "" },
            set: { newValue in
                guard var pending = pendingCalendarMeetingCategoryDeletion else { return }
                pending.replacementCategoryName = newValue
                pendingCalendarMeetingCategoryDeletion = pending
            }
        )
    }

    private func confirmPendingCalendarMeetingCategoryDeletionTransfer() {
        guard let pending = pendingCalendarMeetingCategoryDeletion,
              let replacementCategoryName = pending.replacementCategoryName.trimmedOrNil else {
            return
        }
        applyPendingCalendarMeetingCategoryDeletion(replacementCategoryName: replacementCategoryName)
    }

    private func confirmPendingCalendarMeetingCategoryDeletionUncategorized() {
        applyPendingCalendarMeetingCategoryDeletion(replacementCategoryName: nil)
    }

    private func applyPendingCalendarMeetingCategoryDeletion(replacementCategoryName: String?) {
        guard let pending = pendingCalendarMeetingCategoryDeletion else { return }

        let updatedRecords = reassignCalendarMeetingCategory(
            in: store.calendarMeetingRecords,
            from: pending.sourceCategoryName,
            to: replacementCategoryName
        )
        store.autosaveCalendarMeetingRecords(updatedRecords)

        if let index = editableCalendarMeetingCategories.firstIndex(where: { $0.id == pending.rowID }) {
            editableCalendarMeetingCategories.remove(at: index)
            ensureTrailingEditableCalendarMeetingCategoryRow()
            persistSettingsIfNeeded()
        }

        pendingCalendarMeetingCategoryDeletion = nil
    }

    private func cancelPendingCalendarMeetingCategoryDeletion() {
        pendingCalendarMeetingCategoryDeletion = nil
    }

    private func calendarMeetingCategoryDeletionMessage(
        _ pending: PendingCalendarMeetingCategoryDeletion,
        language: AppLanguage
    ) -> String {
        let categoryName = calendarMeetingCategoryDisplayName(pending.sourceCategoryName, language: language)
        if language == .swedish {
            if pending.usageCount == 1 {
                return "Kategorin \(categoryName) används av 1 sparad aktivitet. Välj om aktiviteten ska flyttas till en annan kategori eller bli kategorilös innan kategorin tas bort."
            }
            return "Kategorin \(categoryName) används av \(pending.usageCount) sparade aktiviteter. Välj om aktiviteterna ska flyttas till en annan kategori eller bli kategorilösa innan kategorin tas bort."
        }

        if pending.usageCount == 1 {
            return "The category \(categoryName) is used by 1 saved activity. Choose whether the activity should move to another category or become uncategorized before the category is deleted."
        }
        return "The category \(categoryName) is used by \(pending.usageCount) saved activities. Choose whether the activities should move to another category or become uncategorized before the category is deleted."
    }

    @ViewBuilder
    private func calendarMeetingCategoryDeletionSheet(language: AppLanguage) -> some View {
        if let pending = pendingCalendarMeetingCategoryDeletion {
            let replacementOptions = availableCalendarMeetingCategoryTransferTargets(
                excludingRowID: pending.rowID,
                sourceCategoryName: pending.sourceCategoryName
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(language.text("Category in use", "Kategori används"))
                        .appTypography(.sectionTitle)

                    Text(calendarMeetingCategoryDeletionMessage(pending, language: language))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)

                    Text(language.text("No saved activities will be changed until you choose one of the options below.", "Inga sparade aktiviteter ändras förrän du väljer ett av alternativen nedan."))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(language.text("Move activities to another category", "Flytta aktiviteter till en annan kategori"))
                            .appTypography(.panelTitle)

                        if replacementOptions.isEmpty {
                            Text(language.text("There are no other activity categories available right now. Create another category first if you want to move the activities instead of making them uncategorized.", "Det finns inga andra aktivitetskategorier tillgängliga just nu. Skapa först en annan kategori om du vill flytta aktiviteterna i stället för att göra dem kategorilösa."))
                                .appTypography(.secondary)
                                .foregroundStyle(.secondary)
                        } else {
                            AppMenuSelectionField(
                                selection: pendingCalendarMeetingCategoryReplacementBinding(),
                                options: replacementOptions.map {
                                    (calendarMeetingCategoryDisplayName($0, language: language), $0)
                                }
                            )

                            Button(language.text("Move activities and delete category", "Flytta aktiviteterna och ta bort kategorin")) {
                                confirmPendingCalendarMeetingCategoryDeletionTransfer()
                            }
                            .appSaveButtonStyle()
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppPalette.secondaryCardSurface)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text(language.text("Make activities uncategorized", "Gör aktiviteterna kategorilösa"))
                            .appTypography(.panelTitle)

                        Text(language.text("This keeps the activities, but clears their category so they use the fixed Uncategorized category instead.", "Detta behåller aktiviteterna, men rensar deras kategori så att de i stället använder den fasta kategorin Ej kategoriserad."))
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)

                        Button(language.text("Make activities uncategorized and delete category", "Gör aktiviteterna kategorilösa och ta bort kategorin")) {
                            confirmPendingCalendarMeetingCategoryDeletionUncategorized()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppPalette.secondaryCardSurface)
                    )

                    HStack {
                        Spacer()
                        Button(language.text("Cancel", "Avbryt")) {
                            cancelPendingCalendarMeetingCategoryDeletion()
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 560, idealWidth: 600, minHeight: 360, idealHeight: 420)
            .presentationDetents([.medium, .large])
        }
    }

    private func fixedCalendarCategoryColorBinding(
        for category: CalendarFixedCategory,
        usesDarkAppearance: Bool
    ) -> Binding<String> {
        Binding(
            get: {
                let colors = fixedCalendarCategoryColors[category] ?? EditableCalendarCategoryColors(
                    lightHex: defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: false),
                    darkHex: defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: true)
                )
                return usesDarkAppearance ? colors.darkHex : colors.lightHex
            },
            set: { newValue in
                var colors = fixedCalendarCategoryColors[category] ?? EditableCalendarCategoryColors(
                    lightHex: defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: false),
                    darkHex: defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: true)
                )
                if usesDarkAppearance {
                    colors.darkHex = normalizedHex(newValue)
                } else {
                    colors.lightHex = normalizedHex(newValue)
                }
                fixedCalendarCategoryColors[category] = colors
                scheduleAutosave()
            }
        )
    }

    private func activityCalendarCategoryColorBinding(
        for role: CalendarActivityColorRole,
        usesDarkAppearance: Bool
    ) -> Binding<String> {
        Binding(
            get: {
                let colors = activityCategoryColors[role] ?? EditableCalendarCategoryColors(
                    lightHex: defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: false),
                    darkHex: defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: true)
                )
                return usesDarkAppearance ? colors.darkHex : colors.lightHex
            },
            set: { newValue in
                var colors = activityCategoryColors[role] ?? EditableCalendarCategoryColors(
                    lightHex: defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: false),
                    darkHex: defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: true)
                )
                if usesDarkAppearance {
                    colors.darkHex = normalizedHex(newValue)
                } else {
                    colors.lightHex = normalizedHex(newValue)
                }
                activityCategoryColors[role] = colors
                let sourceID = CalendarCategoryColorSetting.activityColorID(for: role)
                for index in editableCalendarMeetingCategories.indices where editableCalendarMeetingCategories[index].colorSourceID == sourceID {
                    editableCalendarMeetingCategories[index].lightColorHex = colors.lightHex
                    editableCalendarMeetingCategories[index].darkColorHex = colors.darkHex
                }
                if role == .activity1 {
                    defaultNewActivityCategoryColors = colors
                }
                scheduleAutosave()
            }
        )
    }

    private func editableCalendarMeetingCategoryNameBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard editableCalendarMeetingCategories.indices.contains(index) else { return "" }
                return editableCalendarMeetingCategories[index].name
            },
            set: { newValue in
                guard editableCalendarMeetingCategories.indices.contains(index) else { return }
                let wasEmptyNewCategory = editableCalendarMeetingCategories[index].name.trimmedOrNil == nil
                    && editableCalendarMeetingCategories[index].originalName == nil
                let wasTrailingRow = index == editableCalendarMeetingCategories.count - 1
                editableCalendarMeetingCategories[index].name = newValue
                let isEmptyNewCategory = editableCalendarMeetingCategories[index].name.trimmedOrNil == nil
                    && editableCalendarMeetingCategories[index].originalName == nil
                if wasEmptyNewCategory || isEmptyNewCategory || wasTrailingRow {
                    ensureTrailingEditableCalendarMeetingCategoryRow()
                }
                scheduleAutosave(delay: 0.8)
            }
        )
    }

    private func calendarMeetingCategoryColorSourceBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard editableCalendarMeetingCategories.indices.contains(index) else {
                    return CalendarCategoryColorSetting.activityColorID(for: .activity1)
                }
                return editableCalendarMeetingCategories[index].colorSourceID?.trimmedOrNil
                    ?? legacyCustomCalendarCategoryColorSourceID
            },
            set: { newValue in
                guard editableCalendarMeetingCategories.indices.contains(index) else { return }
                guard newValue != legacyCustomCalendarCategoryColorSourceID else { return }
                editableCalendarMeetingCategories[index].colorSourceID = newValue
                if let colors = editableCalendarCategoryColors(for: newValue) {
                    editableCalendarMeetingCategories[index].lightColorHex = colors.lightHex
                    editableCalendarMeetingCategories[index].darkColorHex = colors.darkHex
                }
                scheduleAutosave()
            }
        )
    }

    private func editableCalendarMeetingCategoryColorBinding(
        at index: Int,
        usesDarkAppearance: Bool
    ) -> Binding<String> {
        Binding(
            get: {
                guard editableCalendarMeetingCategories.indices.contains(index) else {
                    return usesDarkAppearance ? defaultNewActivityCategoryColors.darkHex : defaultNewActivityCategoryColors.lightHex
                }
                return usesDarkAppearance
                    ? editableCalendarMeetingCategories[index].darkColorHex
                    : editableCalendarMeetingCategories[index].lightColorHex
            },
            set: { newValue in
                guard editableCalendarMeetingCategories.indices.contains(index) else { return }
                if usesDarkAppearance {
                    editableCalendarMeetingCategories[index].darkColorHex = normalizedHex(newValue)
                } else {
                    editableCalendarMeetingCategories[index].lightColorHex = normalizedHex(newValue)
                }
                scheduleAutosave()
            }
        )
    }

    private func newActivityCategoryDefaultColorBinding(
        usesDarkAppearance: Bool
    ) -> Binding<String> {
        Binding(
            get: {
                usesDarkAppearance ? defaultNewActivityCategoryColors.darkHex : defaultNewActivityCategoryColors.lightHex
            },
            set: { newValue in
                let previousDefault = defaultNewActivityCategoryColors
                if usesDarkAppearance {
                    defaultNewActivityCategoryColors.darkHex = normalizedHex(newValue)
                } else {
                    defaultNewActivityCategoryColors.lightHex = normalizedHex(newValue)
                }

                for index in editableCalendarMeetingCategories.indices {
                    let category = editableCalendarMeetingCategories[index]
                    let isBlankRow = category.name.trimmedOrNil == nil && category.originalName?.trimmedOrNil == nil
                    let inheritedOldDefault = normalizedHex(category.lightColorHex) == normalizedHex(previousDefault.lightHex)
                        && normalizedHex(category.darkColorHex) == normalizedHex(previousDefault.darkHex)
                    guard isBlankRow || inheritedOldDefault else { continue }
                    editableCalendarMeetingCategories[index].lightColorHex = defaultNewActivityCategoryColors.lightHex
                    editableCalendarMeetingCategories[index].darkColorHex = defaultNewActivityCategoryColors.darkHex
                }

                ensureTrailingEditableCalendarMeetingCategoryRow()
                scheduleAutosave()
            }
        )
    }

    private func persistedCalendarCategoryBehaviors() -> [CalendarCategoryBehaviorSetting] {
        CalendarCategoryBehaviorSetting.normalizedList(
            editableCalendarMeetingCategories.compactMap { category in
                guard let name = category.name.trimmedOrNil else { return nil }
                return CalendarCategoryBehaviorSetting(
                    categoryName: name,
                    excludedFromMeetingStatistics: category.excludedFromMeetingStatistics,
                    isClinicalTime: category.isClinicalTime,
                    isLeave: category.isLeave
                )
            }
        )
    }

    private func editableCalendarMeetingCategoryFlagBinding(
        at index: Int,
        _ keyPath: WritableKeyPath<EditableCalendarMeetingCategory, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard editableCalendarMeetingCategories.indices.contains(index) else { return false }
                return editableCalendarMeetingCategories[index][keyPath: keyPath]
            },
            set: { newValue in
                guard editableCalendarMeetingCategories.indices.contains(index) else { return }
                editableCalendarMeetingCategories[index][keyPath: keyPath] = newValue
                scheduleAutosave()
            }
        )
    }

    private func calendarMeetingCategoryFlagToggles(at index: Int, language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                language.text("Do not count in meeting statistics", "Räkna inte i mötesstatistik"),
                isOn: editableCalendarMeetingCategoryFlagBinding(at: index, \.excludedFromMeetingStatistics)
            )
            .appCheckboxStyle()
            .help(language.text(
                "Activities in this category are left out of your own meeting hours.",
                "Aktiviteter i kategorin räknas inte in i dina egna mötestimmar."
            ))
            Toggle(
                language.text("Clinical time", "Klinisk tid"),
                isOn: editableCalendarMeetingCategoryFlagBinding(at: index, \.isClinicalTime)
            )
            .appCheckboxStyle()
            .help(language.text(
                "In-person activity placed at the home region (Settings > Home organization) when it is in the home country.",
                "Aktivitet på plats som kopplas till hemregionen (Inställningar > Hemorganisation) när den är i hemlandet."
            ))
            Toggle(
                language.text("Leave", "Ledighet"),
                isOn: editableCalendarMeetingCategoryFlagBinding(at: index, \.isLeave)
            )
            .appCheckboxStyle()
            .help(language.text(
                "The calendar shows only the category, not the activity's title.",
                "Kalendern visar bara kategorin, inte aktivitetens titel."
            ))
        }
        .padding(.top, 2)
    }

    private func persistedCalendarMeetingCategoryNames() -> [String] {
        GrantDataStore.normalizedCalendarMeetingTypeOptions(
            editableCalendarMeetingCategories.compactMap(\.name.trimmedOrNil)
        )
    }

    private func persistedCalendarDayHighlightColorSettings() -> [CalendarDayHighlightColorSetting] {
        var settingsByID = Dictionary(firstWinsKeysWithValues: store.calendarDayHighlightColorSettings.map { ($0.id, $0) })

        for kind in CalendarDayHighlightKind.allCases {
            let colors = calendarDayHighlightColors[kind] ?? EditableCalendarDayHighlightColors(
                lightTextHex: defaultCalendarDayHighlightTextHex(for: kind, usesDarkAppearance: false),
                lightBackgroundHex: defaultCalendarDayHighlightBackgroundHex(for: kind, usesDarkAppearance: false),
                darkTextHex: defaultCalendarDayHighlightTextHex(for: kind, usesDarkAppearance: true),
                darkBackgroundHex: defaultCalendarDayHighlightBackgroundHex(for: kind, usesDarkAppearance: true)
            )
            let lightTextHex = normalizedHex(colors.lightTextHex)
            let lightBackgroundHex = normalizedHex(colors.lightBackgroundHex)
            let darkTextHex = normalizedHex(colors.darkTextHex)
            let darkBackgroundHex = normalizedHex(colors.darkBackgroundHex)
            let id = CalendarDayHighlightColorSetting.id(for: kind)

            if lightTextHex == defaultCalendarDayHighlightTextHex(for: kind, usesDarkAppearance: false)
                && lightBackgroundHex == defaultCalendarDayHighlightBackgroundHex(for: kind, usesDarkAppearance: false)
                && darkTextHex == defaultCalendarDayHighlightTextHex(for: kind, usesDarkAppearance: true)
                && darkBackgroundHex == defaultCalendarDayHighlightBackgroundHex(for: kind, usesDarkAppearance: true) {
                settingsByID.removeValue(forKey: id)
            } else {
                settingsByID[id] = CalendarDayHighlightColorSetting(
                    id: id,
                    lightTextHexColor: lightTextHex,
                    lightBackgroundHexColor: lightBackgroundHex,
                    darkTextHexColor: darkTextHex,
                    darkBackgroundHexColor: darkBackgroundHex
                )
            }
        }

        return settingsByID.keys.sorted().map { id in
            settingsByID[id]
                ?? CalendarDayHighlightColorSetting(
                    id: id,
                    lightTextHexColor: "#000000",
                    lightBackgroundHexColor: "#000000",
                    darkTextHexColor: "#000000",
                    darkBackgroundHexColor: "#000000"
                )
        }
    }

    private func persistedCalendarCategoryColorSettings() -> [CalendarCategoryColorSetting] {
        var settingsByID = Dictionary(firstWinsKeysWithValues: store.calendarCategoryColorSettings.map { ($0.id, $0) })

        for category in CalendarFixedCategory.allCases {
            let colors = fixedCalendarCategoryColors[category] ?? EditableCalendarCategoryColors(
                lightHex: defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: false),
                darkHex: defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: true)
            )
            let lightHex = normalizedHex(colors.lightHex)
            let darkHex = normalizedHex(colors.darkHex)
            let id = CalendarCategoryColorSetting.fixedColorID(for: category)
            if lightHex == defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: false)
                && darkHex == defaultCalendarFixedCategoryColorHex(for: category, usesDarkAppearance: true) {
                settingsByID.removeValue(forKey: id)
            } else {
                settingsByID[id] = CalendarCategoryColorSetting(
                    id: id,
                    lightHexColor: lightHex,
                    darkHexColor: darkHex
                )
            }
        }

        for role in CalendarActivityColorRole.allCases {
            let colors = activityCategoryColors[role] ?? EditableCalendarCategoryColors(
                lightHex: defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: false),
                darkHex: defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: true)
            )
            let lightHex = normalizedHex(colors.lightHex)
            let darkHex = normalizedHex(colors.darkHex)
            let id = CalendarCategoryColorSetting.activityColorID(for: role)
            if lightHex == defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: false)
                && darkHex == defaultCalendarActivityCategoryColorHex(for: role, usesDarkAppearance: true) {
                settingsByID.removeValue(forKey: id)
            } else {
                settingsByID[id] = CalendarCategoryColorSetting(
                    id: id,
                    lightHexColor: lightHex,
                    darkHexColor: darkHex
                )
            }
        }

        for category in editableCalendarMeetingCategories {
            let lightHex = normalizedHex(category.lightColorHex)
            let darkHex = normalizedHex(category.darkColorHex)
            let sourceID = category.colorSourceID?.trimmedOrNil
            if let currentName = category.name.trimmedOrNil {
                let id = CalendarCategoryColorSetting.meetingColorID(for: currentName)
                if sourceID == nil
                    && lightHex == normalizedHex(defaultNewActivityCategoryColors.lightHex)
                    && darkHex == normalizedHex(defaultNewActivityCategoryColors.darkHex) {
                    settingsByID.removeValue(forKey: id)
                } else {
                    settingsByID[id] = CalendarCategoryColorSetting(
                        id: id,
                        lightHexColor: lightHex,
                        darkHexColor: darkHex,
                        colorSourceID: sourceID
                    )
                }
            }
            if let originalName = category.originalName?.trimmedOrNil {
                let id = CalendarCategoryColorSetting.meetingColorID(for: originalName)
                if sourceID == nil
                    && lightHex == normalizedHex(defaultNewActivityCategoryColors.lightHex)
                    && darkHex == normalizedHex(defaultNewActivityCategoryColors.darkHex) {
                    settingsByID.removeValue(forKey: id)
                } else {
                    settingsByID[id] = CalendarCategoryColorSetting(
                        id: id,
                        lightHexColor: lightHex,
                        darkHexColor: darkHex,
                        colorSourceID: sourceID
                    )
                }
            }
        }

        let defaultNewLightHex = normalizedHex(defaultNewActivityCategoryColors.lightHex)
        let defaultNewDarkHex = normalizedHex(defaultNewActivityCategoryColors.darkHex)
        if defaultNewLightHex == defaultCalendarSemanticColorHex(for: .neutral, usesDarkAppearance: false)
            && defaultNewDarkHex == defaultCalendarSemanticColorHex(for: .neutral, usesDarkAppearance: true) {
            settingsByID.removeValue(forKey: CalendarCategoryColorSetting.newActivityCategoryDefaultColorID)
        } else {
            settingsByID[CalendarCategoryColorSetting.newActivityCategoryDefaultColorID] = CalendarCategoryColorSetting(
                id: CalendarCategoryColorSetting.newActivityCategoryDefaultColorID,
                lightHexColor: defaultNewLightHex,
                darkHexColor: defaultNewDarkHex,
                colorSourceID: CalendarCategoryColorSetting.activityColorID(for: .activity1)
            )
        }

        return settingsByID.keys.sorted().map { id in
            settingsByID[id] ?? CalendarCategoryColorSetting(id: id, lightHexColor: "#000000", darkHexColor: "#000000")
        }
    }

    private func defaultCalendarDayHighlightTextHex(
        for kind: CalendarDayHighlightKind,
        usesDarkAppearance: Bool
    ) -> String {
        switch kind {
        case .holiday, .saturday, .sunday:
            return defaultCalendarSemanticColorHex(for: .negative, usesDarkAppearance: usesDarkAppearance)
        }
    }

    private func defaultCalendarDayHighlightBackgroundHex(
        for kind: CalendarDayHighlightKind,
        usesDarkAppearance: Bool
    ) -> String {
        switch kind {
        case .holiday, .saturday, .sunday:
            return defaultCalendarSemanticColorHex(for: .negative, usesDarkAppearance: usesDarkAppearance)
        }
    }

    private func defaultCalendarFixedCategoryColorHex(
        for category: CalendarFixedCategory,
        usesDarkAppearance: Bool
    ) -> String {
        switch category {
        case .travel:
            return defaultCalendarSemanticColorHex(for: .positive, usesDarkAppearance: usesDarkAppearance)
        case .task:
            return defaultCalendarSemanticColorHex(for: .inProgress, usesDarkAppearance: usesDarkAppearance)
        case .deadline:
            return defaultCalendarSemanticColorHex(for: .negative, usesDarkAppearance: usesDarkAppearance)
        case .uncategorized:
            return defaultCalendarSemanticColorHex(for: .neutral, usesDarkAppearance: usesDarkAppearance)
        }
    }

    private func defaultCalendarActivityCategoryColorHex(
        for role: CalendarActivityColorRole,
        usesDarkAppearance: Bool
    ) -> String {
        switch role {
        case .activity1:
            return defaultCalendarSemanticColorHex(for: .neutral, usesDarkAppearance: usesDarkAppearance)
        case .activity2:
            return defaultCalendarSemanticColorHex(for: .positive, usesDarkAppearance: usesDarkAppearance)
        case .activity3:
            return defaultCalendarSemanticColorHex(for: .inProgress, usesDarkAppearance: usesDarkAppearance)
        case .activity4:
            return defaultCalendarSemanticColorHex(for: .negative, usesDarkAppearance: usesDarkAppearance)
        }
    }

    private func defaultCalendarMeetingCategoryColorHex(
        for name: String,
        usesDarkAppearance: Bool
    ) -> String {
        normalizedHex(usesDarkAppearance ? defaultNewActivityCategoryColors.darkHex : defaultNewActivityCategoryColors.lightHex)
    }

    private func defaultCalendarSemanticColorHex(
        for tone: AppSemanticTone,
        usesDarkAppearance: Bool
    ) -> String {
        let source = usesDarkAppearance ? darkSemanticColors : lightSemanticColors
        let raw: String
        switch tone {
        case .negative:
            raw = source.negative.solidHex
        case .inProgress:
            raw = source.inProgress.solidHex
        case .positive:
            raw = source.positive.solidHex
        case .neutral:
            raw = source.neutral.solidHex
        }
        return normalizedHex(raw)
    }

    private func semanticPreviewSwatch(title: String, color: Color, text: String) -> some View {
        let foreground: Color = previewBrightness(for: color) < 0.58 ? .white : .black
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
            Text(text)
                .appTypography(.secondary)
                .foregroundStyle(foreground)
                .frame(width: 82, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppPalette.border, lineWidth: 1)
                )
        }
    }

    private func persistSettingsIfNeeded() {
        autosaveTask?.cancel()
        store.autosaveAutomaticVisualSchedule(lightStartsAt: lightModeStartsAt, darkStartsAt: darkModeStartsAt)
        store.autosaveHolidayCountries(HolidayCountry.allCases.filter(selectedHolidayCountries.contains))
        store.autosaveCalendarWeekday(selectedCalendarWeekday)
        store.autosaveCalendarCountryDisplayMode(selectedCalendarCountryDisplayMode)
        store.autosaveCalendarColorLayoutOptions(
            usesCompactEventColorBands: calendarUsesCompactEventColorBands,
            usesCompactDayHighlightBands: calendarUsesCompactDayHighlightBands
        )
        store.autosaveCalendarDayHighlightColors(persistedCalendarDayHighlightColorSettings())
        store.autosaveCalendarDayHighlightColorPresets(calendarDayHighlightColorPresets)
        store.autosaveCalendarMeetingTypeOptions(persistedCalendarMeetingCategoryNames())
        store.autosaveCalendarCategoryColors(persistedCalendarCategoryColorSettings())
        let categoryBehaviors = persistedCalendarCategoryBehaviors()
        if categoryBehaviors != loadedCalendarCategoryBehaviors {
            store.autosaveCalendarCategoryBehaviors(categoryBehaviors)
            loadedCalendarCategoryBehaviors = categoryBehaviors
        }
        store.autosaveCalendarReminderSettings(reminderSettings)
        store.autosaveCalendarWorkingHours(workingHours)
        if [homeCountry, homeRegionOrganizationID, defaultFundManagerOrganizationID] != loadedHomeOrganizationValues {
            store.autosaveHomeOrganizationSettings(
                homeCountry: homeCountry,
                homeRegionOrganizationID: homeRegionOrganizationID,
                defaultFundManagerOrganizationID: defaultFundManagerOrganizationID
            )
            loadedHomeOrganizationValues = [homeCountry, homeRegionOrganizationID, defaultFundManagerOrganizationID]
        }
        store.autosaveCalendarCategoryColorPresets(calendarCategoryColorPresets)
        store.autosaveListFilterRetentionPreferences(listFilterRetentionPreferences)
        store.autosaveDropdownTranslationOverrides(swedish: dropdownTranslationsSv, english: dropdownTranslationsEn)
        store.autosaveMediaLanguageOptions(customMediaLanguageOptions)
        store.autosaveAppAppearance(
            chromeScheme: appChromeScheme,
            chromeColors: appChromeColors,
            typography: typographySettings,
            lightSemanticColors: normalizedSemanticColors(lightSemanticColors),
            darkSemanticColors: normalizedSemanticColors(darkSemanticColors)
        )
        store.autosaveAppSemanticColorPresets(light: lightSemanticColorPresets, dark: darkSemanticColorPresets)
    }

    private func previewAppearanceMetadata() -> DataSourceMetadata {
        var updated = store.editableMetadataSnapshot
        let normalizedLightSemanticColors = normalizedSemanticColors(lightSemanticColors)
        let normalizedDarkSemanticColors = normalizedSemanticColors(darkSemanticColors)
        updated.appChromeScheme = appChromeScheme == .standard ? nil : appChromeScheme.rawValue
        updated.appChromeColors = appChromeColors == .builtIn ? nil : appChromeColors
        updated.appTypography = typographySettings == .default ? nil : typographySettings
        updated.appSemanticColors = nil
        updated.appSemanticColorsLight = normalizedLightSemanticColors == .default ? nil : normalizedLightSemanticColors
        updated.appSemanticColorsDark = normalizedDarkSemanticColors == .darkDefault ? nil : normalizedDarkSemanticColors
        return GrantDataStore.sanitizedMetadata(updated)
    }

    private func applyLiveAppearancePreview() {
        AppAppearanceRegistry.update(from: previewAppearanceMetadata())
        store.objectWillChange.send()
    }

    private func scheduleAutosave(delay: TimeInterval = 0.35) {
        applyLiveAppearancePreview()
        autosaveTask?.cancel()
        let task = DispatchWorkItem { persistSettingsIfNeeded() }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private var canAddCustomMediaLanguage: Bool {
        newMediaLanguageCode.trimmedOrNil != nil
            && newMediaLanguageNameSv.trimmedOrNil != nil
            && newMediaLanguageNameEn.trimmedOrNil != nil
    }

    private func addCustomMediaLanguage() {
        guard canAddCustomMediaLanguage else { return }
        let option = MediaLanguageOption(
            id: newMediaLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            nameSv: newMediaLanguageNameSv.trimmingCharacters(in: .whitespacesAndNewlines),
            nameEn: newMediaLanguageNameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !MediaLanguageOption.builtInOptions.contains(where: { $0.id == option.id }),
              !customMediaLanguageOptions.contains(where: { $0.id.caseInsensitiveCompare(option.id) == .orderedSame }) else { return }
        customMediaLanguageOptions.append(option)
        newMediaLanguageCode = ""
        newMediaLanguageNameSv = ""
        newMediaLanguageNameEn = ""
        scheduleAutosave()
    }

    private func chooseExportDirectory() {
        let language = store.language
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.exportDirectoryURL
        panel.prompt = language.text("Choose", "Välj")
        panel.title = language.text("Choose export folder", "Välj exportmapp")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setExportDirectory(url)
    }

    private func refreshPerformanceDiagnosticsStatus() {
        performanceDiagnosticsStatusItems = store.performanceDiagnosticsStatusItems()
    }

    private func performanceDiagnosticsStatusGrid(language: AppLanguage) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
            ForEach(performanceDiagnosticsStatusItems) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: performanceStatusSymbol(item.tone))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(performanceStatusColor(item.tone))
                        Text(item.title)
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(item.value)
                        .appTypography(.statValue)
                    Text(item.detail)
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                        .fill(AppPalette.secondaryCardSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                        .stroke(performanceStatusColor(item.tone).opacity(0.28), lineWidth: 1)
                )
            }
        }
    }

    private func performanceStatusColor(_ tone: String) -> Color {
        // Round 17: icons and thin strokes use the mark colours (clearly
        // green/orange/red, never the pale fills); "info" has no status and
        // is neutral grey.
        switch tone {
        case "ok":
            return AppPalette.statusMark(.done)
        case "warning":
            return AppPalette.statusMark(.warning)
        case "critical":
            return AppPalette.statusMark(.negative)
        default:
            return AppPalette.statusMark(.inactive)
        }
    }

    private func performanceStatusSymbol(_ tone: String) -> String {
        switch tone {
        case "ok":
            return "checkmark.circle.fill"
        case "warning":
            return "exclamationmark.circle.fill"
        case "critical":
            return "exclamationmark.triangle.fill"
        default:
            return "info.circle"
        }
    }

    private func runtimeBadge(title: String, language: AppLanguage) -> some View {
        Text(title)
            .appTypography(.secondary)
            .foregroundStyle(runtimeBadgeForegroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(runtimeBadgeBackgroundColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(runtimeBadgeBorderColor, lineWidth: 1)
            )
            .accessibilityLabel(language.text("Package mode", "Paketläge") + ": " + title)
    }

    private func settingsInfoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appTypography(.fieldLabel)
            settingsReadOnlyText(value)
        }
    }

    private func settingsReadOnlyText(_ value: String) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(value)
                .appTypography(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppPalette.secondaryCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        )
    }

    private var runtimeBadgeBackgroundColor: Color {
        switch store.packageIdentity.mode {
        case .journalsOnly:
            return Color(hex: 0x0D5F5B).opacity(0.16)
        case .selfContained:
            return Color(hex: 0x146C94).opacity(0.16)
        case .localBootstrap:
            return Color(hex: 0x8C5E00).opacity(0.16)
        case .share:
            return Color(hex: 0x7A2048).opacity(0.16)
        case .development:
            return AppPalette.activeTabSurface.opacity(0.16)
        }
    }

    private var runtimeBadgeBorderColor: Color {
        switch store.packageIdentity.mode {
        case .journalsOnly:
            return Color(hex: 0x0D5F5B).opacity(0.35)
        case .selfContained:
            return Color(hex: 0x146C94).opacity(0.35)
        case .localBootstrap:
            return Color(hex: 0x8C5E00).opacity(0.35)
        case .share:
            return Color(hex: 0x7A2048).opacity(0.35)
        case .development:
            return AppPalette.actionSave.opacity(0.35)
        }
    }

    private var runtimeBadgeForegroundColor: Color {
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

    private func reloadBackupCenterState(selecting preferredURL: URL? = nil) {
        store.backupSnapshotsCache = nil
        let snapshots = ((try? store.backupSnapshots()) ?? [])
            .sorted { $0.date > $1.date }
        backupSnapshots = snapshots
        backupHealthSummaryText = store.language.text("Loading backup health…", "Laddar säkerhetskopiornas skick…")

        let resolvedSelection = preferredURL
            ?? selectedBackupURL.flatMap { existing in snapshots.contains(where: { $0.url == existing }) ? existing : nil }
            ?? snapshots.first?.url
        if selectedBackupURL != resolvedSelection {
            restoreConfirmationAcknowledged = false
        }
        selectedBackupURL = resolvedSelection
        selectedBackupPreview = resolvedSelection == nil
            ? ""
            : store.language.text("Loading backup preview…", "Laddar förhandsvisning av säkerhetskopian…")

        store.loadBackupHealthSummaryAsync { summary in
            backupHealthSummaryText = summary
        }
        if let resolvedSelection {
            store.loadBackupRestorePreviewSummaryAsync(for: resolvedSelection) { summary in
                guard selectedBackupURL == resolvedSelection else { return }
                selectedBackupPreview = summary
            }
        }
    }

    private func selectBackupSnapshot(_ url: URL) {
        selectedBackupURL = url
        restoreConfirmationAcknowledged = false
        selectedBackupPreview = store.language.text("Loading backup preview…", "Laddar förhandsvisning av säkerhetskopian…")
        store.loadBackupRestorePreviewSummaryAsync(for: url) { summary in
            guard selectedBackupURL == url else { return }
            selectedBackupPreview = summary
        }
    }

    private func createManualBackupSnapshot() {
        do {
            try store.createForcedBackupSnapshot(prefix: "manual")
            store.notice = StoreNotice(
                message: store.language.text("Created backup snapshot.", "Skapade säkerhetskopia."),
                tone: .success
            )
            store.loadError = nil
            reloadBackupCenterState()
        } catch {
            store.loadError = error.localizedDescription
            store.notice = StoreNotice(
                message: store.language.text("Could not create backup snapshot.", "Kunde inte skapa säkerhetskopia."),
                tone: .error
            )
        }
    }

    private func backupSnapshotDateText(_ date: Date) -> String {
        // Round 16: ISO date and 24-hour time, whatever the system locale.
        AppTimestampFormatter.dateAndTime(date)
    }

    /// The items grouped by where they are used ("Teaching · participant
    /// form"), in their given order. The group name is written once, as the
    /// label column's heading, so each row needs only a one-line label.
    private func dropdownTranslationUsageGroups(
        _ items: [DropdownTranslationDefinition],
        language: AppLanguage
    ) -> [(title: String, items: [DropdownTranslationDefinition])] {
        var order: [String] = []
        var grouped: [String: [DropdownTranslationDefinition]] = [:]
        for item in items {
            let title = item.usageTitle(language: language)
            if grouped[title] == nil {
                order.append(title)
            }
            grouped[title, default: []].append(item)
        }
        return order.map { (title: $0, items: grouped[$0] ?? []) }
    }

    /// Compact Swedish/English table: one heading row per usage group
    /// ("Svenska" left, "Engelska" right) and one row per term.
    private func dropdownTranslationTable(items: [DropdownTranslationDefinition], language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(dropdownTranslationUsageGroups(items, language: language), id: \.title) { group in
                VStack(alignment: .leading, spacing: SettingsBilingualLayout.rowSpacing) {
                    SettingsBilingualColumnsHeader(language: language, labelTitle: group.title)
                    ForEach(group.items) { definition in
                        dropdownTranslationRow(definition: definition, language: language)
                    }
                }
            }
        }
    }

    private func dropdownTranslationRow(definition: DropdownTranslationDefinition, language: AppLanguage) -> some View {
        SettingsBilingualPairRow(title: definition.usageSubtitle(language: language)) {
            settingsTranslationEditor(
                placeholder: definition.defaultSv,
                text: Binding(
                    get: { dropdownTranslationsSv[definition.key] ?? definition.defaultSv },
                    set: { newValue in
                        dropdownTranslationsSv[definition.key] = newValue
                    }
                )
            )
        } english: {
            settingsTranslationEditor(
                placeholder: definition.defaultEn,
                text: Binding(
                    get: { dropdownTranslationsEn[definition.key] ?? definition.defaultEn },
                    set: { newValue in
                        dropdownTranslationsEn[definition.key] = newValue
                    }
                )
            )
        }
    }

    private func settingsTranslationEditor(placeholder: String, text: Binding<String>) -> some View {
        SettingsGrowingTextField(
            placeholder: placeholder,
            text: Binding(
                get: { text.wrappedValue },
                set: { newValue in
                    text.wrappedValue = newValue
                    scheduleAutosave()
                }
            )
        )
    }

    private func styleBinding(for role: AppTypographyRole) -> Binding<AppTextStyleSetting> {
        Binding(
            get: {
                switch role {
                case .pageTitle: return typographySettings.pageTitle
                case .sectionTitle: return typographySettings.sectionTitle
                case .panelTitle: return typographySettings.panelTitle
                case .tableHeader: return typographySettings.tableHeader
                case .fieldLabel: return typographySettings.fieldLabel
                case .body: return typographySettings.body
                case .secondary: return typographySettings.secondary
                case .statTitle: return typographySettings.statTitle
                case .statValue: return typographySettings.statValue
                }
            },
            set: { newValue in
                switch role {
                case .pageTitle: typographySettings.pageTitle = newValue
                case .sectionTitle: typographySettings.sectionTitle = newValue
                case .panelTitle: typographySettings.panelTitle = newValue
                case .tableHeader: typographySettings.tableHeader = newValue
                case .fieldLabel: typographySettings.fieldLabel = newValue
                case .body: typographySettings.body = newValue
                case .secondary: typographySettings.secondary = newValue
                case .statTitle: typographySettings.statTitle = newValue
                case .statValue: typographySettings.statValue = newValue
                }
            }
        )
    }

    private func toneBinding(for tone: AppSemanticTone, useDark: Bool) -> Binding<AppSemanticToneSetting> {
        Binding(
            get: {
                let source = useDark ? darkSemanticColors : lightSemanticColors
                switch tone {
                case .negative: return source.negative
                case .inProgress: return source.inProgress
                case .positive: return source.positive
                case .neutral: return source.neutral
                }
            },
            set: { newValue in
                if useDark {
                    switch tone {
                    case .negative: darkSemanticColors.negative = newValue
                    case .inProgress: darkSemanticColors.inProgress = newValue
                    case .positive: darkSemanticColors.positive = newValue
                    case .neutral: darkSemanticColors.neutral = newValue
                    }
                } else {
                    switch tone {
                    case .negative: lightSemanticColors.negative = newValue
                    case .inProgress: lightSemanticColors.inProgress = newValue
                    case .positive: lightSemanticColors.positive = newValue
                    case .neutral: lightSemanticColors.neutral = newValue
                    }
                }
            }
        )
    }

    private func normalizedSemanticColors(_ colors: AppSemanticColorSettings) -> AppSemanticColorSettings {
        AppSemanticColorSettings(
            negative: .make(normalizedHex(colors.negative.solidHex), normalizedHex(colors.negative.shadeHex)),
            inProgress: .make(normalizedHex(colors.inProgress.solidHex), normalizedHex(colors.inProgress.shadeHex)),
            positive: .make(normalizedHex(colors.positive.solidHex), normalizedHex(colors.positive.shadeHex)),
            neutral: .make(normalizedHex(colors.neutral.solidHex), normalizedHex(colors.neutral.shadeHex))
        )
    }

    private func previewColor(for value: String) -> Color {
        let normalized = normalizedHex(value)
        let hex = String(normalized.dropFirst())
        guard let rgb = Int(hex, radix: 16) else { return .clear }
        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    private func previewBrightness(for color: Color) -> Double {
        let ns = NSColor(color)
        let converted = ns.usingColorSpace(.deviceRGB) ?? ns
        return (0.299 * converted.redComponent) + (0.587 * converted.greenComponent) + (0.114 * converted.blueComponent)
    }

    private func colorPickerBinding(for text: Binding<String>) -> Binding<Color> {
        Binding(
            get: { previewColor(for: text.wrappedValue) },
            set: { newColor in
                text.wrappedValue = hexString(for: newColor)
                scheduleAutosave()
            }
        )
    }

    private func hexString(for color: Color) -> String {
        let ns = NSColor(color)
        let converted = ns.usingColorSpace(.deviceRGB) ?? ns
        let red = Int(round(converted.redComponent * 255))
        let green = Int(round(converted.greenComponent * 255))
        let blue = Int(round(converted.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func normalizedHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard cleaned.count == 6, cleaned.allSatisfy(\.isHexDigit) else { return "#000000" }
        return "#\(cleaned.uppercased())"
    }

    private func hexFieldState(for value: String) -> AppFieldVisualState {
        AppFieldValidators.optionalHexColor(value, language: store.language).state
    }

    private func title(for section: SettingsWorkspaceSection, language: AppLanguage) -> String {
        switch section {
        case .appearance:
            return language.text("Appearance", "Utseende")
        case .homeOrganization:
            return language.text("Home organization", "Hemorganisation")
        case .calendar:
            return language.text("Calendar", "Kalender")
        case .applications:
            return language.text("Applications", "Ansökningar")
        case .export:
            return language.text("Export target", "Exporttarget")
        case .data:
            return language.text("Data & backups", "Data och säkerhetskopior")
        case .listFilters:
            return language.text("List filters", "Listfilter")
        case .translations:
            return language.text("Translations", "Översättningar")
        case .mediaLanguages:
            return language.text("Media languages", "Mediaspråk")
        case .teachingTerminology:
            return language.text("Teaching terms", "Undervisningsbegrepp")
        case .researcherLists:
            return language.text("Lists", "Listor")
        }
    }

    private func title(for role: AppTypographyRole, language: AppLanguage) -> String {
        switch role {
        case .pageTitle: return language.text("Page title", "Sidrubrik")
        case .sectionTitle: return language.text("Section title", "Sektionsrubrik")
        case .panelTitle: return language.text("Panel title", "Panelrubrik")
        case .tableHeader: return language.text("Table header", "Tabellrubrik")
        case .fieldLabel: return language.text("Field label", "Fältetikett")
        case .body: return language.text("Body text", "Brödtext")
        case .secondary: return language.text("Secondary text", "Sekundär text")
        case .statTitle: return language.text("Stat title", "Statistikrubrik")
        case .statValue: return language.text("Stat value", "Statistikvärde")
        }
    }

    private func title(for tone: AppSemanticTone, language: AppLanguage) -> String {
        switch tone {
        case .negative: return language.text("Urgent / near", "Brådskande / nära")
        case .inProgress: return language.text("Middle distance", "Mittemellan")
        case .positive: return language.text("Far away / safe", "Långt bort / tryggt")
        case .neutral: return language.text("Neutral / unknown", "Neutralt / okänt")
        }
    }

    private func title(for family: AppFontFamily) -> String {
        switch family {
        case .system: return "SF Pro"
        case .rounded: return "SF Pro Rounded"
        case .serif: return "Serif"
        case .monospaced: return "Monospaced"
        }
    }

    private func title(for weight: AppFontWeightSetting) -> String {
        switch weight {
        case .regular: return "Normal"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        }
    }
}

private struct TeachingFormatSettingsRow: View {
    @ObservedObject var store: GrantDataStore
    let format: TeachingFormatOption
    let language: AppLanguage
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: TeachingFormatOption
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var createdFormatID: String?
    @State private var suppressPersistence = false

    init(store: GrantDataStore, format: TeachingFormatOption, language: AppLanguage) {
        self.store = store
        self.format = format
        self.language = language
        _draft = State(initialValue: format)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(currentPlaceholder, text: localizedNameBinding)
                    .appTextInputChrome()
                if canDelete {
                    AppRowDeleteIconButton(
                        title: language.text("Delete activity type", "Ta bort aktivitetstyp"),
                        cancelTitle: language.text("Cancel", "Avbryt"),
                        confirmationTitle: language.text("Delete activity type?", "Ta bort aktivitetstyp?"),
                        action: {
                            let targetID = createdFormatID ?? format.id
                            if !targetID.isEmpty {
                                suppressPersistence = true
                                autosaveTask?.cancel()
                                forcedPersistTask?.cancel()
                                store.deleteTeachingFormat(id: targetID)
                            }
                        },
                        storeAsksFirst: {
                            store.teachingFormatDeletionShowsImpactWarning(id: createdFormatID ?? format.id)
                        }
                    )
                }
            }
        }
        .onChange(of: draft) { _, _ in scheduleAutosave() }
        .flushPendingAutosaveOnTextEnd(requestImmediatePersist)
        .onDisappear {
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            guard !shouldSuppressPersistence else { return }
            persist()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                guard !shouldSuppressPersistence else { return }
                requestImmediatePersist()
            }
        }
        .onChange(of: format) { _, newValue in
            draft = newValue
        }
    }

    private var currentPlaceholder: String {
        return language == .swedish ? language.text("Swedish name", "Svenskt namn") : language.text("English name", "Engelskt namn")
    }

    private var localizedNameBinding: Binding<String> {
        Binding(
            get: { language == .swedish ? draft.nameSv : draft.nameEn },
            set: { newValue in
                draft.setLocalizedName(newValue, language: language)
            }
        )
    }

    private var canDelete: Bool {
        createdFormatID != nil || store.teachingFormats.contains(where: { $0.id == format.id })
    }

    private var shouldSuppressPersistence: Bool {
        let targetID = createdFormatID ?? format.id
        return TeachingFormatDeletionPersistence.shouldSuppress(
            deleteRequested: suppressPersistence,
            recordStillExists: store.teachingFormats.contains(where: { $0.id == targetID })
        )
    }

    private func persist() {
        guard !shouldSuppressPersistence else { return }
        autosaveTask?.cancel()
        var normalized = draft
        normalized.normalize()
        if createdFormatID == nil && store.teachingFormats.contains(where: { $0.id == format.id }) == false {
            guard normalized.nameSv.nonEmpty != nil || normalized.nameEn.nonEmpty != nil else { return }
            let newID = store.addTeachingFormat()
            createdFormatID = newID
            if let stored = store.teachingFormats.first(where: { $0.id == newID }) {
                normalized.id = stored.id
                store.autosaveTeachingFormat(normalized)
                draft = normalized
            }
            return
        }
        let targetID = createdFormatID ?? format.id
        normalized.id = targetID
        guard let existing = store.teachingFormats.first(where: { $0.id == targetID }) else { return }
        guard normalized != existing else { return }
        store.autosaveTeachingFormat(normalized)
    }

    private func scheduleAutosave() {
        guard !shouldSuppressPersistence else { return }
        autosaveTask?.cancel()
        let task = DispatchWorkItem { persist() }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func requestImmediatePersist() {
        guard !shouldSuppressPersistence else { return }
        forcedPersistTask?.cancel()
        let task = DispatchWorkItem {
            persist()
        }
        forcedPersistTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
    }
}
