import SwiftUI




/// Lightweight editor for the canonical, cross-workspace task collection.
/// It is deliberately link-scoped: the same task may be visible from several
/// workspaces but has one ID and one editable record.
struct CentralTaskListSection: View {
    @ObservedObject var store: GrantDataStore
    let linkKind: TaskLinkKind
    let targetID: String
    var ownerID: String? = nil
    let language: AppLanguage
    var reminderOptions: [ProjectTaskReminder] = ProjectTaskReminder.allCases
    var isReadOnly = false
    var showsAddButton = true
    @State private var showsCompleted = false

    private var visibleTasks: [TaskItem] {
        store.taskItems(linkedTo: linkKind, targetID: targetID, ownerID: ownerID)
            .filter { !$0.isCompleted || showsCompleted || isReadOnly }
            .sorted {
                // Same day: a task with a time before one without.
                let left = ($0.deadline.trimmedOrNil ?? "9999-12-31") + " " + ($0.deadlineTime ?? "99:99")
                let right = ($1.deadline.trimmedOrNil ?? "9999-12-31") + " " + ($1.deadlineTime ?? "99:99")
                return left == right ? $0.comment.localizedStandardCompare($1.comment) == .orderedAscending : left < right
            }
    }

    static func addTask(
        store: GrantDataStore,
        linkKind: TaskLinkKind,
        targetID: String,
        ownerID: String? = nil
    ) {
        let today = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
        store.saveTaskItem(
            TaskItem(
                createdOn: today,
                updatedOn: today,
                links: [TaskLink(kind: linkKind, targetID: targetID, ownerID: ownerID)]
            )
        )
    }

    static func hasIncompleteTasks(
        store: GrantDataStore,
        linkKind: TaskLinkKind,
        targetID: String,
        ownerID: String? = nil
    ) -> Bool {
        store.taskItems(linkedTo: linkKind, targetID: targetID, ownerID: ownerID)
            .contains { !$0.isCompleted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(visibleTasks) { task in
                CentralTaskRowEditor(
                    store: store,
                    taskID: task.id,
                    language: language,
                    reminderOptions: reminderOptions,
                    isReadOnly: isReadOnly
                )
            }

            if !isReadOnly {
                HStack(spacing: 12) {
                    if showsAddButton {
                        Button {
                            Self.addTask(store: store, linkKind: linkKind, targetID: targetID, ownerID: ownerID)
                        } label: {
                            Label(language.text("Add task", "Lägg till uppgift"), systemImage: "plus")
                        }
                        .appAddButtonStyle()
                    }

                    if store.taskItems(linkedTo: linkKind, targetID: targetID, ownerID: ownerID).contains(where: \.isCompleted) {
                        Toggle(language.text("Show completed", "Visa slutförda"), isOn: $showsCompleted)
                            .appCheckboxStyle()
                    }
                }
                .padding(.top, showsAddButton ? 4 : 0)
            }
        }
    }
}

private struct CentralTaskRowEditor: View {
    @ObservedObject var store: GrantDataStore
    let taskID: String
    let language: AppLanguage
    let reminderOptions: [ProjectTaskReminder]
    let isReadOnly: Bool

    private var task: TaskItem? { store.taskItems.first(where: { $0.id == taskID }) }
    private var today: String { DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date())) }

    /// Same leading status indicator as the record lists (e.g. Projects):
    /// urgent shade for overdue tasks, middle shade for tasks due within a
    /// week, safe shade for completed tasks, and no indicator further out.
    private var statusStripeColor: Color? {
        guard let task else { return nil }
        // Round 16: shared task tones (done green, overdue orange).
        if task.isCompleted {
            return AppPalette.statusFill(AppStatusTones.task(isCompleted: true, isOverdue: false))
        }
        guard let deadlineText = task.deadline.trimmedOrNil,
              let deadlineDay = DateParsers.isoDay.date(from: deadlineText) else {
            return nil
        }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        // A task with a clock time is overdue once that time has passed.
        if deadlineDay < todayStart || (task.deadlineMoment(calendar: calendar).map { $0 <= Date() } ?? false) {
            // Round 17: overdue tasks use the strong "late" red-orange
            // (the same as the calendar's overdue dots).
            return AppPalette.lateMark
        }
        // Settings > Calendar: "due soon" this many days ahead (default 7).
        if let weekAhead = calendar.date(byAdding: .day, value: store.calendarReminderSettings.taskDueSoonDays, to: todayStart),
           deadlineDay <= weekAhead {
            return AppPalette.statusFill(.pending)
        }
        return nil
    }

    var body: some View {
        if let task {
            HStack(alignment: .top, spacing: 10) {
                if isReadOnly {
                    AppLockedFieldValueText(text: task.comment, lineLimit: nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(language.text("Task", "Uppgift"), text: stringBinding(\.comment))
                        .appTextInputChrome()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isReadOnly {
                    // Locked records show the time after the date.
                    AppLockedFieldValueText(text: task.deadlineDisplayText)
                        .frame(width: task.deadlineTime == nil ? 120 : 160, alignment: .leading)
                } else {
                    CommitDateFieldWithTodayButton(
                        placeholder: language.datePlaceholder,
                        text: deadlineBinding(),
                        formatter: DateParsers.canonicalizedDayInput,
                        clearBackgroundInDarkNew: true,
                        width: 120
                    )

                    CalendarTimeInputField(placeholder: "hh:mm", text: deadlineTimeBinding(), updatesContinuously: false)
                        .frame(width: 70)
                        .disabled(task.deadline.trimmedOrNil == nil)
                        .help(language.text("Optional time on the deadline day", "Valfritt klockslag på dagen"))
                }

                if !isReadOnly {
                    AppMenuSelectionField(
                        selection: reminderBinding(),
                        options: reminderOptions.map { ($0.displayName(language: language), $0) },
                        placeholder: nil
                    )
                    .frame(width: 190, height: AppPalette.fieldMinHeight)
                }

                AppTaskCompletionToggle(isCompleted: Binding(
                    get: { task.isCompleted },
                    set: { store.toggleTaskItemCompletion(taskID: taskID, isCompleted: $0) }
                ))
                .padding(.top, 7)

                if !isReadOnly {
                    AppIconDeleteButton(
                        title: language.text("Delete task", "Ta bort uppgift"),
                        width: 18,
                        cancelTitle: language.text("Cancel", "Avbryt"),
                        confirmationTitle: language.text("Delete task?", "Ta bort uppgiften?")
                    ) {
                        store.removeTaskItem(id: taskID)
                    }
                    .padding(.top, 7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background {
                if let statusStripeColor {
                    // Cancels the row's vertical padding so the indicator
                    // matches the height of the text field itself.
                    StatusIndicatorListRowBackground(fill: statusStripeColor, verticalPadding: 3)
                }
            }
            .appReminderDot(
                calendarTaskShowsActiveBadge(
                    deadline: task.deadline,
                    title: task.comment,
                    isCompleted: task.isCompleted,
                    // Badge hiding is stored under calendarTaskReminderID ids
                    // ("teaching-task:<id>" for central tasks), not the
                    // calendar event id ("central-task:<id>").
                    isBadgeHidden: calendarTaskReminderID(for: .teachingTask(taskID: task.id))
                        .map(store.isCalendarTaskBadgeHidden) ?? false
                )
            )
        }
    }

    private func stringBinding(_ keyPath: WritableKeyPath<TaskItem, String>) -> Binding<String> {
        Binding(
            get: { task?[keyPath: keyPath] ?? "" },
            set: { value in update { $0[keyPath: keyPath] = value } }
        )
    }

    /// Clearing the date also clears the time.
    private func deadlineBinding() -> Binding<String> {
        Binding(
            get: { task?.deadline ?? "" },
            set: { value in
                update {
                    $0.deadline = value
                    if value.trimmedOrNil == nil {
                        $0.deadlineTime = nil
                    }
                }
            }
        )
    }

    private func deadlineTimeBinding() -> Binding<String> {
        Binding(
            get: { task?.deadlineTime ?? "" },
            set: { value in update { $0.deadlineTime = TaskItem.normalizedDeadlineTime(value) } }
        )
    }

    private func reminderBinding() -> Binding<ProjectTaskReminder> {
        Binding(
            get: { task?.reminder ?? .none },
            set: { value in update { $0.reminder = value } }
        )
    }

    private func update(_ body: (inout TaskItem) -> Void) {
        guard var updated = task else { return }
        body(&updated)
        updated.updatedOn = today
        store.saveTaskItem(updated)
    }
}
