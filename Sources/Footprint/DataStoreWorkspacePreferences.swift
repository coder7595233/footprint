import Foundation

extension GrantDataStore {
    private func persistMetadataUserChange(
        _ updated: DataSourceMetadata,
        englishAction: String,
        swedishAction: String,
        includeBackup: Bool = true
    ) {
        persistMetadataSilently(
            updated,
            includeBackup: includeBackup,
            undoActionName: language.text(englishAction, swedishAction)
        )
    }

    func autosaveAutomaticVisualSchedule(lightStartsAt: String, darkStartsAt: String) {
        var updated = editableMetadataSnapshot
        updated.lightModeStartsAt = Self.normalizedTimeInput(lightStartsAt)
        updated.darkModeStartsAt = Self.normalizedTimeInput(darkStartsAt)
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit visual schedule", swedishAction: "Redigera visuellt schema")
    }

    func setExportDirectory(_ url: URL?) {
        var updated = editableMetadataSnapshot
        updated.exportDirectoryPath = normalizedExportDirectoryPath(url)
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit export folder", swedishAction: "Redigera exportmapp")
    }

    func autosaveDropdownTranslationOverrides(swedish: [String: String], english: [String: String]) {
        var updated = editableMetadataSnapshot
        updated.dropdownTranslationsSv = Self.normalizedDropdownOverrides(swedish, language: .swedish)
        updated.dropdownTranslationsEn = Self.normalizedDropdownOverrides(english, language: .english)
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit dropdown translations", swedishAction: "Redigera rullistöversättningar")
    }

    var mediaLanguageOptions: [MediaLanguageOption] {
        MediaLanguageOption.allOptions(custom: editableMetadataSnapshot.mediaLanguageOptions)
    }

    func autosaveMediaLanguageOptions(_ options: [MediaLanguageOption]) {
        var updated = editableMetadataSnapshot
        updated.mediaLanguageOptions = MediaLanguageOption.normalizedCustomOptions(options)
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit media languages", swedishAction: "Redigera mediaspråk")
    }

    func shouldRetainListFilters(for key: ListFilterPersistenceKey) -> Bool {
        metadata.listFilterRetentionPreferences?[key.rawValue] ?? true
    }

    func listFilterRetentionPreferenceSnapshot() -> [String: Bool] {
        Dictionary(firstWinsKeysWithValues: ListFilterPersistenceKey.allCases.map {
            ($0.rawValue, shouldRetainListFilters(for: $0))
        })
    }

    func autosaveListFilterRetentionPreferences(_ preferences: [String: Bool]) {
        var normalized: [String: Bool] = [:]
        for key in ListFilterPersistenceKey.allCases {
            let shouldRetain = preferences[key.rawValue] ?? true
            if !shouldRetain {
                normalized[key.rawValue] = false
            }
        }

        var updated = editableMetadataSnapshot
        updated.listFilterRetentionPreferences = normalized.isEmpty ? nil : normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit filter retention", swedishAction: "Redigera filterminne")
    }

    func setPersonIncompleteDataFilterSilently(_ filter: PersonIncompleteDataFilter) {
        var updated = editableMetadataSnapshot
        updated.personIncompleteDataFilter = filter == .none ? nil : filter.rawValue
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataSilently(updated, includeBackup: false, invalidateStorageDiagnosticsOnWrite: false)
    }

    func autosaveHolidayCountries(_ countries: [HolidayCountry]) {
        var updated = editableMetadataSnapshot
        updated.calendarHolidayCountries = HolidayCalendarBuilder.normalized(countries).map(\.rawValue)
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit holiday countries", swedishAction: "Redigera helgländer")
    }

    func autosaveCalendarWeekday(_ weekday: CalendarWeekdayChoice) {
        var updated = editableMetadataSnapshot
        updated.calendarFirstWeekday = weekday.rawValue
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit calendar week start", swedishAction: "Redigera kalenderns veckostart")
    }

    func autosaveCalendarCountryDisplayMode(_ mode: CalendarCountryDisplayMode) {
        var updated = editableMetadataSnapshot
        updated.calendarCountryDisplayMode = mode == .flags ? nil : mode.rawValue
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit calendar country display", swedishAction: "Redigera kalenderns landsvisning")
    }

    func autosaveCalendarHiddenColumnKeys(_ keys: Set<String>) {
        let normalized = Set(keys.compactMap(\.trimmedOrNil))
        var updated = editableMetadataSnapshot
        updated.calendarHiddenColumnKeys = normalized.isEmpty ? nil : normalized.sorted()
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit calendar columns", swedishAction: "Redigera kalenderkolumner")
    }

    func autosaveCalendarHiddenAutomaticEventKeys(_ keys: Set<String>) {
        let normalized = Set(keys.compactMap(\.trimmedOrNil))
        var updated = editableMetadataSnapshot
        updated.calendarHiddenAutomaticEventKeys = normalized.isEmpty ? nil : normalized.sorted()
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit hidden calendar events", swedishAction: "Redigera dolda kalenderhändelser")
    }

    func setAutomaticCalendarEventHidden(_ key: String, hidden: Bool) {
        guard let normalizedKey = key.trimmedOrNil else { return }
        var keys = calendarHiddenAutomaticEventKeys
        if hidden {
            keys.insert(normalizedKey)
        } else {
            keys.remove(normalizedKey)
        }
        autosaveCalendarHiddenAutomaticEventKeys(keys)
    }

    func autosaveCalendarHiddenTaskBadgeIDs(_ ids: Set<String>) {
        let normalized = Set(ids.compactMap(\.trimmedOrNil))
        var updated = editableMetadataSnapshot
        updated.calendarHiddenTaskBadgeIDs = normalized.isEmpty ? nil : normalized.sorted()
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit hidden task badges", swedishAction: "Redigera dolda uppgiftsbadges")
    }

    func setCalendarTaskBadgeHidden(_ id: String, hidden: Bool) {
        guard let normalizedID = id.trimmedOrNil else { return }
        var ids = calendarHiddenTaskBadgeIDs
        if hidden {
            ids.insert(normalizedID)
        } else {
            ids.remove(normalizedID)
        }
        autosaveCalendarHiddenTaskBadgeIDs(ids)
    }

    func autosaveCalendarColorLayoutOptions(
        usesCompactEventColorBands: Bool,
        usesCompactDayHighlightBands: Bool
    ) {
        var updated = editableMetadataSnapshot
        updated.calendarUsesCompactEventColorBands = usesCompactEventColorBands ? true : nil
        updated.calendarUsesCompactDayHighlightBands = usesCompactDayHighlightBands ? true : nil
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit calendar color layout", swedishAction: "Redigera kalenderns färglayout")
    }

    func autosaveCalendarDayHighlightColors(_ settings: [CalendarDayHighlightColorSetting]) {
        let normalized = Self.normalizedCalendarDayHighlightColorSettings(settings)
        var updated = editableMetadataSnapshot
        updated.calendarDayHighlightColors = normalized.isEmpty ? nil : normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit day highlight colors", swedishAction: "Redigera dagmarkeringar")
    }

    func autosaveCalendarDayHighlightColorPresets(_ presets: [CalendarDayHighlightColorPreset]) {
        let normalized = Self.normalizedCalendarDayHighlightColorPresets(presets)
        var updated = editableMetadataSnapshot
        updated.calendarDayHighlightColorPresets = normalized.isEmpty ? nil : normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit day highlight presets", swedishAction: "Redigera dagmarkeringsmallar")
    }

    func autosaveCalendarTravelRecords(_ records: [CalendarTravelRecord]) {
        let changeStartedAt = CFAbsoluteTimeGetCurrent()
        var normalized = records
            .map {
                var copy = $0
                copy.normalize()
                return copy
            }
            .filter { !$0.isEmpty }
        normalized = calendarTravelRecordsSortedChronologically(normalized)

        // One snapshot build per save: editableMetadataSnapshot runs a full
        // sanitize pass, and the change guard compares only the collection
        // this autosave can change instead of the whole metadata struct.
        let previous = editableMetadataSnapshot
        guard normalized != (previous.calendarTravelRecords ?? []) else { return }
        let changedRecordID = calendarChangedRecordID(from: previous.calendarTravelRecords ?? [], to: normalized)
        var updated = previous
        updated.calendarTravelRecords = normalized
        let beforePersist = CFAbsoluteTimeGetCurrent()
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit travel", "Redigera resa")
        )
        let afterPersist = CFAbsoluteTimeGetCurrent()
        publishCalendarContentUpdate(source: changedRecordID.map(CalendarWorkspaceEventSource.travel))
        appendCalendarChangeDiagnosticIfSlow(
            phase: "autosave-travel",
            startedAt: changeStartedAt,
            details: String(
                format: "prepare_ms=%.2f persist_ms=%.2f publish_update_ms=%.2f",
                (beforePersist - changeStartedAt) * 1000,
                (afterPersist - beforePersist) * 1000,
                (CFAbsoluteTimeGetCurrent() - afterPersist) * 1000
            )
        )
    }

    func autosaveCalendarAccommodationRecords(_ records: [CalendarAccommodationRecord]) {
        let changeStartedAt = CFAbsoluteTimeGetCurrent()
        var normalized = records
            .map {
                var copy = $0
                copy.normalize()
                return copy
            }
            .filter { !$0.isEmpty }
        normalized.sort(by: calendarAccommodationSort)

        let previous = editableMetadataSnapshot
        guard normalized != (previous.calendarAccommodationRecords ?? []) else { return }
        let changedRecordID = calendarChangedRecordID(from: previous.calendarAccommodationRecords ?? [], to: normalized)
        var updated = previous
        updated.calendarAccommodationRecords = normalized
        let beforePersist = CFAbsoluteTimeGetCurrent()
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit hotel stay", "Redigera hotellvistelse")
        )
        let afterPersist = CFAbsoluteTimeGetCurrent()
        publishCalendarContentUpdate(source: changedRecordID.map(CalendarWorkspaceEventSource.accommodation))
        appendCalendarChangeDiagnosticIfSlow(
            phase: "autosave-accommodation",
            startedAt: changeStartedAt,
            details: String(
                format: "prepare_ms=%.2f persist_ms=%.2f publish_update_ms=%.2f",
                (beforePersist - changeStartedAt) * 1000,
                (afterPersist - beforePersist) * 1000,
                (CFAbsoluteTimeGetCurrent() - afterPersist) * 1000
            )
        )
    }

    func autosaveCalendarMeetingRecords(_ records: [CalendarMeetingRecord]) {
        let changeStartedAt = CFAbsoluteTimeGetCurrent()
        // Same result as normalizing every meeting; unchanged meetings reuse
        // the previous save's result.
        let normalization = calendarMeetingRecordsNormalizedForSave(records)
        var normalized = normalization.records
        let afterNormalize = CFAbsoluteTimeGetCurrent()
        // F13b: participants are also kept by id; the names stay as display text.
        synchronizeMeetingParticipantAuthorIDs(&normalized)
        let afterParticipants = CFAbsoluteTimeGetCurrent()
        // Same order as before; dates and start times are read once per
        // meeting instead of twice per comparison (was ~200 ms here).
        normalized = calendarMeetingRecordsSortedChronologically(normalized)
        let afterSort = CFAbsoluteTimeGetCurrent()

        let previous = editableMetadataSnapshot
        guard normalized != (previous.calendarMeetingRecords ?? []) else { return }
        let changedRecordID = calendarChangedRecordID(from: previous.calendarMeetingRecords ?? [], to: normalized)
        let afterCompare = CFAbsoluteTimeGetCurrent()
        var updated = previous
        updated.calendarMeetingRecords = normalized
        let beforePersist = CFAbsoluteTimeGetCurrent()
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit activity", "Redigera aktivitet")
        )
        let afterPersist = CFAbsoluteTimeGetCurrent()
        publishCalendarContentUpdate(source: changedRecordID.map(CalendarWorkspaceEventSource.meeting))
        appendCalendarChangeDiagnosticIfSlow(
            phase: "autosave-meetings",
            startedAt: changeStartedAt,
            details: String(
                format: "prepare_ms=%.2f normalize_ms=%.2f reused=%ld/%ld participants_ms=%.2f sort_ms=%.2f compare_ms=%.2f persist_ms=%.2f publish_update_ms=%.2f",
                (beforePersist - changeStartedAt) * 1000,
                (afterNormalize - changeStartedAt) * 1000,
                normalization.reused,
                records.count,
                (afterParticipants - afterNormalize) * 1000,
                (afterSort - afterParticipants) * 1000,
                (afterCompare - afterSort) * 1000,
                (afterPersist - beforePersist) * 1000,
                (CFAbsoluteTimeGetCurrent() - afterPersist) * 1000
            )
        )
    }

    private func calendarChangedRecordID<Record: Identifiable & Equatable>(
        from previous: [Record],
        to current: [Record]
    ) -> String? where Record.ID == String {
        let previousByID = previous.reduce(into: [String: Record]()) { result, record in
            // Preserve the first canonical occurrence rather than crashing on
            // malformed legacy/imported duplicate IDs.
            if result[record.id] == nil {
                result[record.id] = record
            }
        }
        if let changed = current.first(where: { previousByID[$0.id] != $0 }) {
            return changed.id
        }
        let currentIDs = Set(current.map(\.id))
        return previous.first(where: { !currentIDs.contains($0.id) })?.id
    }

    /// `pulses` is false when the source no longer exists (a deletion): the
    /// calendar then only uses the source to update that one record.
    func publishCalendarContentUpdate(source: CalendarWorkspaceEventSource?, pulses: Bool = true) {
        calendarContentUpdate = CalendarContentUpdate(source: source, pulses: pulses)
    }

    func autosaveCalendarMeetingTypeOptions(_ options: [String]) {
        let normalized = Self.normalizedCalendarMeetingTypeOptions(options)
        var updated = editableMetadataSnapshot
        updated.calendarMeetingTypeOptions = normalized == Self.defaultCalendarMeetingTypeOptions ? nil : normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit activity types", swedishAction: "Redigera aktivitetstyper")
    }

    func autosaveCalendarCategoryColors(_ settings: [CalendarCategoryColorSetting]) {
        let normalized = Self.normalizedCalendarCategoryColorSettings(settings)
        var updated = editableMetadataSnapshot
        updated.calendarCategoryColors = normalized.isEmpty ? nil : normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit calendar category colors", swedishAction: "Redigera kalenderkategorifärger")
    }

    func autosaveCalendarCategoryColorPresets(_ presets: [CalendarCategoryColorPreset]) {
        let builtInPresets = Dictionary(firstWinsKeysWithValues: Self.standardCalendarCategoryColorPresets().map { ($0.id, $0) })
        let normalized = Self.normalizedCalendarCategoryColorPresets(presets).compactMap { preset -> CalendarCategoryColorPreset? in
            guard Self.isEditableCalendarCategoryColorPresetID(preset.id),
                  let builtInPreset = builtInPresets[preset.id] else {
                return nil
            }

            let resolvedSettings = Self.resolvedCalendarFixedCategoryPresetSettings(
                preset.settings,
                fallback: builtInPreset.settings
            )
            guard resolvedSettings != builtInPreset.settings else { return nil }

            return CalendarCategoryColorPreset(
                id: builtInPreset.id,
                name: builtInPreset.name,
                settings: resolvedSettings
            )
        }
        var updated = editableMetadataSnapshot
        updated.calendarCategoryColorPresets = normalized.isEmpty ? nil : normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit calendar color presets", swedishAction: "Redigera kalenderfärgmallar")
    }

    func autosaveAppAppearance(
        chromeScheme: AppChromeScheme,
        chromeColors: AppChromeColorSettings,
        typography: AppTypographySettings,
        lightSemanticColors: AppSemanticColorSettings,
        darkSemanticColors: AppSemanticColorSettings
    ) {
        var updated = editableMetadataSnapshot
        updated.appChromeScheme = chromeScheme == .standard ? nil : chromeScheme.rawValue
        updated.appChromeColors = chromeColors == .builtIn ? nil : chromeColors
        updated.appTypography = typography == .default ? nil : typography
        updated.appSemanticColors = nil
        updated.appSemanticColorsLight = lightSemanticColors == .default ? nil : lightSemanticColors
        updated.appSemanticColorsDark = darkSemanticColors == .darkDefault ? nil : darkSemanticColors
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit appearance", swedishAction: "Redigera utseende")
    }

    func autosaveAppSemanticColorPresets(light: [AppSemanticColorPreset], dark: [AppSemanticColorPreset]) {
        let builtInLight = Dictionary(firstWinsKeysWithValues: Self.standardAppSemanticColorPresets(useDarkAppearance: false).map { ($0.id, $0) })
        let builtInDark = Dictionary(firstWinsKeysWithValues: Self.standardAppSemanticColorPresets(useDarkAppearance: true).map { ($0.id, $0) })
        let normalizedLight = Self.normalizedAppSemanticColorPresets(light, fallbackName: "Standard").compactMap { preset -> AppSemanticColorPreset? in
            guard Self.isEditableAppSemanticColorPresetID(preset.id),
                  let builtInPreset = builtInLight[preset.id],
                  preset.colors != builtInPreset.colors else {
                return nil
            }
            return AppSemanticColorPreset(id: builtInPreset.id, name: builtInPreset.name, colors: preset.colors)
        }
        let normalizedDark = Self.normalizedAppSemanticColorPresets(dark, fallbackName: "Standard").compactMap { preset -> AppSemanticColorPreset? in
            guard Self.isEditableAppSemanticColorPresetID(preset.id),
                  let builtInPreset = builtInDark[preset.id],
                  preset.colors != builtInPreset.colors else {
                return nil
            }
            return AppSemanticColorPreset(id: builtInPreset.id, name: builtInPreset.name, colors: preset.colors)
        }
        var updated = editableMetadataSnapshot
        updated.appSemanticColorPresetsLight = normalizedLight.isEmpty ? nil : normalizedLight
        updated.appSemanticColorPresetsDark = normalizedDark.isEmpty ? nil : normalizedDark
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit color presets", swedishAction: "Redigera färgmallar")
    }

    func autosaveTeachingWorkspaceTasks(_ tasks: [PublicationTaskItem]) {
        var updated = editableMetadataSnapshot
        var linkedTasks = tasks.filter { !$0.isEmpty }
        // F13b: participants are also kept by id; the names stay as display text.
        synchronizeTaskParticipantAuthorIDs(&linkedTasks)
        updated.teachingWorkspaceTasks = linkedTasks
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit teaching task list", "Redigera undervisningsuppgiftslista")
        )
        refreshCalendarTaskReminderBadgesImmediately()
    }

    func autosaveTaskItems(_ tasks: [TaskItem]) {
        let changeStartedAt = CFAbsoluteTimeGetCurrent()
        var normalized = tasks
        for index in normalized.indices {
            normalized[index].normalize()
        }
        normalized = normalized.filter { !$0.isEmpty }
        // F13b: participants are also kept by id; the names stay as display text.
        synchronizeTaskParticipantAuthorIDs(&normalized)
        let previous = editableMetadataSnapshot
        guard normalized != (previous.taskItems ?? []) else { return }
        let changedTaskID = calendarChangedRecordID(from: previous.taskItems ?? [], to: normalized)
        var updated = previous
        updated.taskItems = normalized
        let beforePersist = CFAbsoluteTimeGetCurrent()
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit task list", "Redigera uppgiftslista")
        )
        let afterPersist = CFAbsoluteTimeGetCurrent()
        publishCalendarContentUpdate(source: changedTaskID.map { .teachingTask(taskID: $0) })
        appendCalendarChangeDiagnosticIfSlow(
            phase: "autosave-tasks",
            startedAt: changeStartedAt,
            details: String(
                format: "prepare_ms=%.2f persist_ms=%.2f publish_update_ms=%.2f",
                (beforePersist - changeStartedAt) * 1000,
                (afterPersist - beforePersist) * 1000,
                (CFAbsoluteTimeGetCurrent() - afterPersist) * 1000
            )
        )
        refreshCalendarTaskReminderBadgesImmediately()
    }

    /// Keeps the navigation badges in step with a committed task edit. The app
    /// delegate also refreshes the Dock badge and notification schedule, but its
    /// Combine delivery is deferred to the next run-loop turn.
    private func refreshCalendarTaskReminderBadgesImmediately() {
        let entries = calendarTaskDockBadgeEntries(
            store: self,
            language: language,
            calendar: .current
        )
        updateCalendarTaskReminderBadgeEntries(entries)
    }

    func saveTaskItem(_ task: TaskItem) {
        var task = task
        task.normalize()
        guard !task.isEmpty else { return }
        var tasks = taskItems
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        autosaveTaskItems(tasks)
    }

    func removeTaskItem(id: String) {
        autosaveTaskItems(taskItems.filter { $0.id != id })
    }

    func toggleTaskItemCompletion(taskID: String, isCompleted: Bool) {
        var tasks = taskItems
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let today = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
        tasks[index].completedOn = taskCompletionDateAfterToggle(
            existingCompletedOn: tasks[index].completedOn,
            isCompleted: isCompleted,
            todayString: today
        )
        tasks[index].updatedOn = today
        autosaveTaskItems(tasks)
    }

    func taskItems(linkedTo kind: TaskLinkKind, targetID: String, ownerID: String? = nil) -> [TaskItem] {
        taskItems.filter { $0.hasLink(kind: kind, targetID: targetID, ownerID: ownerID) }
    }

    func toggleTeachingWorkspaceTaskCompletion(taskID: String, isCompleted: Bool) {
        var tasks = teachingWorkspaceTasks
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let today = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
        tasks[index].completedOn = taskCompletionDateAfterToggle(
            existingCompletedOn: tasks[index].completedOn,
            isCompleted: isCompleted,
            todayString: today
        )
        tasks[index].updatedOn = today
        autosaveTeachingWorkspaceTasks(tasks)
    }

    func toggleProjectTaskCompletion(projectID: String, taskID: String, isCompleted: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        var updated = projects[index]
        guard let taskIndex = updated.projectTasks.firstIndex(where: { $0.id == taskID }) else { return }
        let today = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
        updated.projectTasks[taskIndex].completedOn = taskCompletionDateAfterToggle(
            existingCompletedOn: updated.projectTasks[taskIndex].completedOn,
            isCompleted: isCompleted,
            todayString: today
        )
        updated.projectTasks[taskIndex].updatedOn = today
        autosaveProjectRecord(updated, previousID: projectID)
    }

    func toggleOrganizationTaskCompletion(organizationID: String, taskID: String, isCompleted: Bool) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        var updated = organizations[index]
        guard let taskIndex = updated.projectTasks.firstIndex(where: { $0.id == taskID }) else { return }
        let today = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
        updated.projectTasks[taskIndex].completedOn = taskCompletionDateAfterToggle(
            existingCompletedOn: updated.projectTasks[taskIndex].completedOn,
            isCompleted: isCompleted,
            todayString: today
        )
        updated.projectTasks[taskIndex].updatedOn = today
        autosaveOrganization(
            id: updated.id,
            nameSv: updated.nameSv,
            nameEn: updated.nameEn,
            addressLine: updated.addressLine,
            postalCode: updated.postalCode,
            city: updated.city,
            country: updated.country,
            category: updated.category,
            roles: updated.roles,
            note: updated.note,
            websiteURL: updated.websiteURL,
            phoneNumber: updated.phoneNumber,
            organizationNumber: updated.organizationNumber,
            vatNumber: updated.vatNumber,
            employerContacts: updated.employerContacts,
            flag: updated.flag,
            membershipFrom: updated.membershipFrom,
            membershipTo: updated.membershipTo,
            congresses: updated.congresses,
            projectTasks: updated.projectTasks,
            salaryCalculator: updated.salaryCalculator
        )
    }

    func togglePublicationTaskCompletion(publicationID: String, taskID: String, isCompleted: Bool) {
        guard let index = publicationRecords.firstIndex(where: { $0.id == publicationID }) else { return }
        var updated = publicationRecords[index]
        guard let taskIndex = updated.publicationTasks.firstIndex(where: { $0.id == taskID }) else { return }
        let today = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
        updated.publicationTasks[taskIndex].completedOn = taskCompletionDateAfterToggle(
            existingCompletedOn: updated.publicationTasks[taskIndex].completedOn,
            isCompleted: isCompleted,
            todayString: today
        )
        updated.publicationTasks[taskIndex].updatedOn = today
        autosavePublication(updated)
    }

    func setProjectTimelineStyle(_ style: ProjectTimelineStyle) {
        var updated = editableMetadataSnapshot
        updated.projectTimelineYearColumnWidth = style.yearColumnWidth
        updated.projectTimelineRowHeight = style.rowHeight
        updated.projectTimelineBarHeight = style.barHeight
        updated.projectTimelineMarkerWidth = style.markerWidth
        updated.projectTimelineBarCornerRadius = style.barCornerRadius
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit project timeline style", swedishAction: "Redigera projekttidslinje")
    }

    func resetProjectTimelineStyle() {
        var updated = editableMetadataSnapshot
        updated.projectTimelineYearColumnWidth = nil
        updated.projectTimelineRowHeight = nil
        updated.projectTimelineBarHeight = nil
        updated.projectTimelineMarkerWidth = nil
        updated.projectTimelineBarCornerRadius = nil
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Reset project timeline style", swedishAction: "Återställ projekttidslinje")
    }

    func rememberLastSelectedTab(_ rawValue: String) {
        guard lastSelectedTabRaw != rawValue else { return }
        lastSelectedTabOverride = rawValue
        pendingLastSelectedTabPersistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistRememberedLastSelectedTab(rawValue)
        }
        pendingLastSelectedTabPersistenceWorkItem = workItem
        appendPerformanceDiagnostic(
            String(
                format: "tab-preference-deferred tab=%@ delay_s=%.2f",
                rawValue,
                Self.lastSelectedTabPersistenceDelay
            )
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lastSelectedTabPersistenceDelay, execute: workItem)
        NotificationCenter.default.post(name: .footprintSelectedTabChanged, object: rawValue)
    }

    func persistRememberedLastSelectedTab(_ rawValue: String) {
        pendingLastSelectedTabPersistenceWorkItem = nil
        var updated = editableMetadataSnapshot
        guard updated.lastSelectedTab != rawValue else { return }
        updated.lastSelectedTab = rawValue
        appendPerformanceDiagnostic("tab-preference-persist tab=\(rawValue)")
        persistMetadataSilently(
            updated,
            publishImmediately: false,
            publishStatusUpdates: false,
            includeBackup: false,
            invalidateStorageDiagnosticsOnWrite: false
        )
    }

    func updateSalaryWorkspace(sources: [SalarySource], periods: [SalaryCoveragePeriod]) {
        var updated = editableMetadataSnapshot
        updated.salarySources = sources
        updated.salaryCoveragePeriods = periods
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(updated, englishAction: "Edit salary workspace", swedishAction: "Redigera lönearbetsyta")
    }

    func lastSelectedRecordID(for destination: AppRoute.Destination) -> String? {
        if let override = lastSelectionOverrides[destination] {
            return override?.nonEmpty
        }
        switch destination {
        case .applications:
            return metadata.lastSelectedApplicationID?.nonEmpty
        case .congresses:
            return nil
        case .cv:
            return metadata.lastSelectedCVID?.nonEmpty
        case .expertAssignments:
            return metadata.lastSelectedCVID?.nonEmpty
        case .publications:
            return metadata.lastSelectedPublicationID?.nonEmpty
        case .projects:
            return metadata.lastSelectedProjectID?.nonEmpty
        case .teaching:
            return metadata.lastSelectedTeachingID?.nonEmpty
        case .doctoralCandidates:
            return metadata.lastSelectedDoctoralCandidateID?.nonEmpty
        case .organizations:
            return metadata.lastSelectedOrganizationID?.nonEmpty
        case .people:
            return metadata.lastSelectedPersonID?.nonEmpty
        case .journals:
            return metadata.lastSelectedJournalID?.nonEmpty
        }
    }

    func rememberSelection(id: String?, for destination: AppRoute.Destination) {
        let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let current = lastSelectedRecordID(for: destination)
        guard current != normalized else { return }

        lastSelectionOverrides[destination] = normalized

        var updated = editableMetadataSnapshot
        switch destination {
        case .applications:
            updated.lastSelectedApplicationID = normalized
        case .congresses:
            return
        case .cv:
            updated.lastSelectedCVID = normalized
        case .expertAssignments:
            updated.lastSelectedCVID = normalized
        case .publications:
            updated.lastSelectedPublicationID = normalized
        case .projects:
            updated.lastSelectedProjectID = normalized
        case .teaching:
            updated.lastSelectedTeachingID = normalized
        case .doctoralCandidates:
            updated.lastSelectedDoctoralCandidateID = normalized
        case .organizations:
            updated.lastSelectedOrganizationID = normalized
        case .people:
            updated.lastSelectedPersonID = normalized
        case .journals:
            updated.lastSelectedJournalID = normalized
        }
        persistMetadataSilently(
            updated,
            publishImmediately: false,
            publishStatusUpdates: false,
            includeBackup: false,
            invalidateStorageDiagnosticsOnWrite: false
        )
    }

    func activateListKeyboardNavigation(for destination: AppRoute.Destination) {
        activeListKeyboardNavigationDestination = destination
    }

    func deactivateListKeyboardNavigation(for destination: AppRoute.Destination) {
        guard activeListKeyboardNavigationDestination == destination else { return }
        activeListKeyboardNavigationDestination = nil
    }

    func clearActiveListKeyboardNavigation() {
        activeListKeyboardNavigationDestination = nil
    }

    func migrateRememberedSelectionID(
        from oldID: String,
        to newID: String,
        destinations: [AppRoute.Destination]
    ) {
        guard oldID != newID else { return }

        var updated = editableMetadataSnapshot
        var didChangeMetadata = false

        for destination in destinations {
            if lastSelectionOverrides[destination] == oldID {
                lastSelectionOverrides[destination] = newID
            }

            switch destination {
            case .applications:
                if updated.lastSelectedApplicationID == oldID {
                    updated.lastSelectedApplicationID = newID
                    didChangeMetadata = true
                }
            case .congresses:
                break
            case .cv:
                if updated.lastSelectedCVID == oldID {
                    updated.lastSelectedCVID = newID
                    didChangeMetadata = true
                }
            case .publications:
                if updated.lastSelectedPublicationID == oldID {
                    updated.lastSelectedPublicationID = newID
                    didChangeMetadata = true
                }
            case .projects:
                if updated.lastSelectedProjectID == oldID {
                    updated.lastSelectedProjectID = newID
                    didChangeMetadata = true
                }
            case .teaching:
                if updated.lastSelectedTeachingID == oldID {
                    updated.lastSelectedTeachingID = newID
                    didChangeMetadata = true
                }
            case .expertAssignments:
                if updated.lastSelectedCVID == oldID {
                    updated.lastSelectedCVID = newID
                    didChangeMetadata = true
                }
            case .people:
                if updated.lastSelectedPersonID == oldID {
                    updated.lastSelectedPersonID = newID
                    didChangeMetadata = true
                }
            case .journals:
                if updated.lastSelectedJournalID == oldID {
                    updated.lastSelectedJournalID = newID
                    didChangeMetadata = true
                }
            case .doctoralCandidates:
                if updated.lastSelectedDoctoralCandidateID == oldID {
                    updated.lastSelectedDoctoralCandidateID = newID
                    didChangeMetadata = true
                }
            case .organizations:
                if updated.lastSelectedOrganizationID == oldID {
                    updated.lastSelectedOrganizationID = newID
                    didChangeMetadata = true
                }
            }
        }

        if let currentRoute = route,
           destinations.contains(currentRoute.destination),
           currentRoute.recordID == oldID {
            route = AppRoute(recordID: newID, destination: currentRoute.destination)
        }

        if didChangeMetadata {
            persistMetadataSilently(
                updated,
                publishImmediately: false,
                publishStatusUpdates: false,
                includeBackup: false,
                invalidateStorageDiagnosticsOnWrite: false
            )
        }
    }

    var showsFooterStatusBar: Bool {
        metadata.showsFooterStatusBar ?? false
    }

    func setFooterStatusBarVisible(_ isVisible: Bool) {
        var updated = editableMetadataSnapshot
        updated.showsFooterStatusBar = isVisible ? true : nil
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataUserChange(
            updated,
            englishAction: "Edit footer status bar",
            swedishAction: "Redigera statusrad",
            includeBackup: false
        )
    }
}
