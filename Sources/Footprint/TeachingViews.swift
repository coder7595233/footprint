import AppKit
import SwiftUI

enum TeachingFormatDeletionPersistence {
    static func shouldSuppress(deleteRequested: Bool, recordStillExists: Bool) -> Bool {
        deleteRequested && !recordStillExists
    }
}

private enum TeachingAssignmentStatusKind: String, Codable, Hashable {
    case none
    case ongoing
    case completed
}

private struct TeachingAssignmentFilterState: Codable, Equatable {
    var searchText = ""
    var minimumYearValue: Double = 0
    var maximumYearValue: Double = 0
    var kindRawValues: [String] = []
    var statusRawValues: [String] = []
    var institutionBranches: [String] = []
    var programBranches: [String] = []
    var contextBranchIDs: [String] = []
}

private enum TeachingAssignmentFilterPersistence {
    private static let defaultsKey = "TeachingAssignmentsFilterState.v1"

    static func load() -> TeachingAssignmentFilterState {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let state = try? JSONDecoder().decode(TeachingAssignmentFilterState.self, from: data) else {
            return TeachingAssignmentFilterState()
        }
        return state
    }

    static func save(_ state: TeachingAssignmentFilterState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

private struct TeachingAssignmentDirectoryRow: Identifiable {
    let assignment: TeachingAssignment
    let kind: TeachingAssignmentKind
    let kindLabel: String
    let activityName: String
    let contextName: String
    let roleLabel: String
    let yearLabel: String
    let statusLabel: String
    let statusRank: Int
    let hoursValue: Double
    let hoursLabel: String
    let studentLabel: String
    let retendoState: TeachingRetendoState
    let yearValues: [Int]
    let searchBlob: String
    let normalizedSearchBlob: String

    var id: String { assignment.id }
}

struct TeachingAssignmentRowDependencyRevision: Equatable {
    let assignment: TeachingAssignment
    let context: TeachingCourse?
    let component: TeachingComponent?
    let language: AppLanguage
    let selectedProgramBranch: String?
}

enum TeachingAssignmentRowCachePolicy {
    static func IDsRequiringRebuild(
        previous: [String: TeachingAssignmentRowDependencyRevision],
        current: [String: TeachingAssignmentRowDependencyRevision]
    ) -> Set<String> {
        Set(current.compactMap { id, revision in
            previous[id] == revision ? nil : id
        })
    }
}

private enum TeachingRetendoState {
    /// No periods, so nothing to confirm.
    case none
    /// Periods, none of them confirmed in Retendo.
    case unconfirmed
    case partial
    case full

    /// Marked with a red bar in the list: something is left to confirm.
    var needsConfirmation: Bool {
        self == .unconfirmed || self == .partial
    }
}

@MainActor
@ViewBuilder
private func teachingMenuField<Value: Hashable>(
    selection: Binding<Value>,
    options: [(label: String, value: Value)],
    width: CGFloat,
    placeholder: String? = nil
) -> some View {
    if AppRuntime.usesRenewedChrome {
        AppMenuSelectionField(selection: selection, options: options, placeholder: placeholder)
            .frame(width: width, alignment: .leading)
    } else {
        Picker("", selection: selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Text(option.label).tag(option.value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: width, alignment: .leading)
        .formKeyboardNavigable()
    }
}

private enum TeachingCatalogLayout {
    static let outerHorizontalPadding: CGFloat = 14
    static let outerTopPadding: CGFloat = 14
    static let columnSpacing: CGFloat = 8

    static let organizationWidth: CGFloat = 200
    static let courseNameMinWidth: CGFloat = 280
    static let courseTypeWidth: CGFloat = 140
    static let courseProgramMinWidth: CGFloat = 180
    static let courseTermWidth: CGFloat = 90
    static let courseCodeWidth: CGFloat = 100
    static let courseLevelWidth: CGFloat = 110
    static let courseLanguageWidth: CGFloat = 90
    static let courseCreditsWidth: CGFloat = 60

    static let momentNameMinWidth: CGFloat = 340
    static let momentFormWidth: CGFloat = 220
    static let momentParticipantsWidth: CGFloat = 160
    static let momentContextsWidth: CGFloat = 220

    static let trailingActionWidth: CGFloat = 24

    struct CourseColumns {
        let organization: CGFloat
        let name: CGFloat
        let type: CGFloat
        let program: CGFloat
        let term: CGFloat
        let courseCode: CGFloat
        let level: CGFloat
        let language: CGFloat
        let credits: CGFloat
        let action: CGFloat

        var totalWidth: CGFloat {
            organization + name + type + program + term + courseCode + level + language + credits + action + (8 * TeachingCatalogLayout.columnSpacing)
        }
    }

    struct MomentColumns {
        let organization: CGFloat
        let name: CGFloat
        let form: CGFloat
        let participants: CGFloat
        let contexts: CGFloat
        let action: CGFloat

        var totalWidth: CGFloat {
            organization + name + form + participants + contexts + action + (5 * TeachingCatalogLayout.columnSpacing)
        }
    }

    struct FormatColumns {
        let name: CGFloat
        let participants: CGFloat
        let action: CGFloat

        var totalWidth: CGFloat {
            name + participants + action + (2 * TeachingCatalogLayout.columnSpacing)
        }
    }

    static func courseColumns(courses: [TeachingCourse], language: AppLanguage) -> CourseColumns {
        let organization = measuredColumnWidth(
            header: language.text("Organization", "Organisation"),
            values: courses.map(\.institution),
            minimum: 120,
            chrome: 34
        )
        let name = measuredColumnWidth(
            header: language.text("Name", "Namn"),
            values: courses.map { $0.localizedName(language: language) },
            minimum: 160,
            chrome: 24
        )
        let type = measuredColumnWidth(
            header: language.text("Type", "Typ"),
            values: TeachingContextType.allCases.map { $0.displayName(language: language) } + courses.compactMap { $0.contextType?.displayName(language: language) },
            minimum: 90,
            chrome: 34
        )
        let program = measuredColumnWidth(
            header: language.text("Program", "Program"),
            values: courses.map { $0.localizedProgram(language: language) },
            minimum: 90,
            chrome: 24
        )
        let term = measuredColumnWidth(
            header: language.text("Semester", "Termin"),
            values: courses.map { $0.localizedTerm(language: language).nonEmpty ?? $0.localizedTermFallback },
            minimum: 72,
            chrome: 24
        )
        let courseCode = measuredColumnWidth(
            header: language.text("Course code", "Kurskod"),
            values: courses.map(\.courseCode),
            minimum: 88,
            chrome: 24
        )
        let level = measuredColumnWidth(
            header: language.text("Level", "Nivå"),
            values: TeachingCourseLevel.allCases.map { $0.displayName(language: language) } + courses.compactMap { $0.level?.displayName(language: language) },
            minimum: 90,
            chrome: 34
        )
        let teachingLanguage = measuredColumnWidth(
            header: language.text("Language", "Språk"),
            values: [
                fixedDropdownText("teachingLanguage.swedish", language: language, english: "Swedish", swedish: "svenska"),
                fixedDropdownText("teachingLanguage.english", language: language, english: "English", swedish: "engelska")
            ],
            minimum: 96,
            chrome: 34
        )
        let credits = measuredColumnWidth(
            header: language.text("Credits", "Hp"),
            values: courses.map(\.credits),
            minimum: 70,
            chrome: 24
        )
        return CourseColumns(
            organization: organization,
            name: name,
            type: type,
            program: program,
            term: term,
            courseCode: courseCode,
            level: level,
            language: teachingLanguage,
            credits: credits,
            action: trailingActionWidth
        )
    }

    static func momentColumns(components: [TeachingComponent], language: AppLanguage) -> MomentColumns {
        let organization = measuredColumnWidth(
            header: language.text("Organization", "Organisation"),
            values: components.map(\.institution),
            minimum: 120,
            chrome: 34
        )
        let name = measuredColumnWidth(
            header: language.text("Name", "Namn"),
            values: components.map { $0.localizedName(language: language) },
            minimum: 180,
            chrome: 24
        )
        let form = measuredColumnWidth(
            header: language.text("Form", "Form"),
            values: components.map { normalizedMomentFormLabel($0.activityTypeName, language: language) } + storeableMomentFormExamples(language: language),
            minimum: 100,
            chrome: 34
        )
        let participants = measuredColumnWidth(
            header: language.text("Participants", "Deltagare"),
            values: TeachingAssignmentCategory.allCases.map { $0.displayName(language: language) } + components.compactMap { $0.participantForm?.displayName(language: language) },
            minimum: 100,
            chrome: 34
        )
        let contexts = measuredColumnWidth(
            header: language.text("Structure lock", "Strukturlåsning"),
            values: [language.text("All courses", "Alla kurser"), language.text("1 selected", "1 vald"), language.text("2 selected", "2 valda")],
            minimum: momentContextsWidth,
            chrome: 34
        )
        return MomentColumns(
            organization: organization,
            name: name,
            form: form,
            participants: participants,
            contexts: contexts,
            action: trailingActionWidth
        )
    }

    static func formatColumns(formats: [TeachingFormatOption], language: AppLanguage) -> FormatColumns {
        FormatColumns(
            name: measuredColumnWidth(
                header: language.text("Name", "Namn"),
                values: formats.map { $0.localizedName(language: language) },
                minimum: 180,
                chrome: 24
            ),
            participants: measuredColumnWidth(
                header: language.text("Participants", "Deltagare"),
                values: TeachingAssignmentCategory.allCases.map { $0.displayName(language: language) } + formats.compactMap { $0.category?.displayName(language: language) },
                minimum: 100,
                chrome: 34
            ),
            action: trailingActionWidth
        )
    }
}

enum TeachingAutocompleteIndex {
    enum CourseScope {
        case all
        case leafOnly
        case programTracksOnly
    }

    static func deduplicatedValues(_ values: [String]) -> [String] {
        var seen: [String: String] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = PublicationDerivation.normalizedName(trimmed)
            if seen[key] == nil {
                seen[key] = trimmed
            }
        }
        return Array(seen.values).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func programOptions(
        courses: [TeachingCourse],
        language: AppLanguage,
        institution: String?
    ) -> [String] {
        deduplicatedValues(
            filteredCourses(
                courses,
                language: language,
                institution: institution,
                program: nil,
                scope: .all
            )
            .map { $0.localizedProgram(language: language) }
        )
    }

    static func courseNameOptions(
        courses: [TeachingCourse],
        language: AppLanguage,
        institution: String?,
        program: String?,
        scope: CourseScope
    ) -> [String] {
        deduplicatedValues(
            filteredCourses(
                courses,
                language: language,
                institution: institution,
                program: program,
                scope: scope
            )
            .map { $0.localizedName(language: language) }
        )
    }

    static func termOptions(
        courses: [TeachingCourse],
        language: AppLanguage,
        institution: String?,
        program: String?,
        scope: CourseScope
    ) -> [String] {
        deduplicatedValues(
            filteredCourses(
                courses,
                language: language,
                institution: institution,
                program: program,
                scope: scope
            )
            .map { $0.localizedTerm(language: language).nonEmpty ?? $0.localizedTermFallback }
        )
    }

    private static func filteredCourses(
        _ courses: [TeachingCourse],
        language: AppLanguage,
        institution: String?,
        program: String?,
        scope: CourseScope
    ) -> [TeachingCourse] {
        let normalizedInstitutionFilter = institution?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            .map(PublicationDerivation.normalizedName)
        let institutionHasExactMatch = normalizedInstitutionFilter.map { filter in
            courses.contains { PublicationDerivation.normalizedName($0.institution) == filter }
        } ?? false

        let institutionFiltered = courses.filter {
            matches(
                $0.institution,
                filter: institution,
                prefersExactMatch: institutionHasExactMatch
            )
        }

        let normalizedProgramFilter = program?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            .map(PublicationDerivation.normalizedName)
        let programHasExactMatch = normalizedProgramFilter.map { filter in
            institutionFiltered.contains { PublicationDerivation.normalizedName($0.localizedProgram(language: language)) == filter }
        } ?? false

        return institutionFiltered.filter { course in
            guard matches(
                course.localizedProgram(language: language),
                filter: program,
                prefersExactMatch: programHasExactMatch
            ) else { return false }

            switch scope {
            case .all:
                return true
            case .leafOnly:
                return course.contextType != .programTrack
            case .programTracksOnly:
                return course.contextType == .programTrack
            }
        }
    }

    private static func matches(
        _ candidate: String,
        filter: String?,
        prefersExactMatch: Bool
    ) -> Bool {
        guard let trimmedFilter = filter?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
            return true
        }

        let normalizedCandidate = PublicationDerivation.normalizedName(candidate)
        let normalizedFilter = PublicationDerivation.normalizedName(trimmedFilter)
        if prefersExactMatch {
            return normalizedCandidate == normalizedFilter
        }
        return normalizedCandidate == normalizedFilter
            || normalizedCandidate.contains(normalizedFilter)
    }
}

private func measuredColumnWidth(
    header: String,
    values: [String],
    minimum: CGFloat,
    chrome: CGFloat
) -> CGFloat {
    let candidates = [header] + values.compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
    let textWidth = candidates.map { measuredTableTextWidth($0) }.max() ?? 0
    return max(minimum, ceil(textWidth + chrome))
}

private func measuredTableTextWidth(_ text: String, fontSize: CGFloat = 13, weight: NSFont.Weight = .regular) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight)
    ]
    return (text as NSString).size(withAttributes: attributes).width
}

private func normalizedMomentFormLabel(_ raw: String, language: AppLanguage) -> String {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "grupphandledning",
         "individuell handledning",
         "doktorandhandledning",
         "handledning examensarbete",
         "handledning fördjupningsarbete",
         "handledning doktorandarbete",
         "supervision",
         "degree project supervision",
         "in-depth project supervision",
         "doctoral supervision":
        return language.text("Supervision", "Handledning")
    default:
        return raw
    }
}

private func storeableMomentFormExamples(language: AppLanguage) -> [String] {
    [
        language.text("Supervision", "Handledning"),
        language.text("Seminar", "Seminarium"),
        language.text("Lecture", "Föreläsning")
    ]
}




private enum TeachingAssignmentListSortColumn: String, Hashable {
    case type
    case context
    case assignment
    case role
    case year
    case status
    case hours
    case student

    var defaultAscending: Bool {
        switch self {
        case .type, .context, .assignment, .role, .year, .status, .student:
            return true
        case .hours:
            return false
        }
    }
}

private struct TeachingAssignmentListSortCriterion: AppListSortCriterion {
    let column: TeachingAssignmentListSortColumn
    var ascending: Bool
}

struct TeachingWorkspaceView: View {
    let store: GrantDataStore
    let newRecordTrigger: Int
    let isActive: Bool

    @State private var selectedAssignmentID: String?
    @State private var assignmentSortHistory = ListSortPersistence.load(
        defaultsKey: "TeachingAssignmentsListSort",
        defaultValue: [
            TeachingAssignmentListSortCriterion(column: .context, ascending: true),
            TeachingAssignmentListSortCriterion(column: .assignment, ascending: true),
        ]
    )
    @State private var searchText: String
    @State private var minimumYearValue: Double
    @State private var maximumYearValue: Double
    @State private var selectedKindFilters: Set<TeachingAssignmentKind>
    @State private var selectedStatusFilters: Set<TeachingAssignmentStatusKind>
    @State private var selectedInstitutionBranches: Set<String>
    @State private var selectedProgramBranches: Set<String>
    @State private var selectedContextBranchIDs: Set<String>
    @State private var assignmentRows: [TeachingAssignmentDirectoryRow] = []
    @State private var filteredAssignmentRows: [TeachingAssignmentDirectoryRow] = []
    @State private var availableYearValues: [Int] = []
    @State private var assignmentRowCache: [String: TeachingAssignmentDirectoryRow] = [:]
    @State private var assignmentRowRevisions: [String: TeachingAssignmentRowDependencyRevision] = [:]
    @State private var pendingSelectionMeasurementID: String?
    @State private var pendingSelectionStartedAt: CFAbsoluteTime?
    @State private var assignmentRowsRebuildTask: DispatchWorkItem?
    @State private var assignmentFilterRebuildTask: DispatchWorkItem?
    @State private var needsRowsRebuildWhenActive = false
    @State private var needsFilterRebuildWhenActive = false
    @State private var pendingRouteAssignmentID: String?
    @State private var assignmentSelectionCoordinator = AppSelectionCoordinator<String>()

    init(store: GrantDataStore, newRecordTrigger: Int, isActive: Bool = true) {
        self.store = store
        self.newRecordTrigger = newRecordTrigger
        self.isActive = isActive
        let savedFilters = TeachingAssignmentFilterPersistence.load()
        _searchText = State(initialValue: savedFilters.searchText)
        _minimumYearValue = State(initialValue: savedFilters.minimumYearValue)
        _maximumYearValue = State(initialValue: savedFilters.maximumYearValue)
        _selectedKindFilters = State(initialValue: Set(savedFilters.kindRawValues.compactMap(TeachingAssignmentKind.init(rawValue:))))
        _selectedStatusFilters = State(initialValue: Set(savedFilters.statusRawValues.compactMap(TeachingAssignmentStatusKind.init(rawValue:))))
        _selectedInstitutionBranches = State(initialValue: Set(savedFilters.institutionBranches))
        _selectedProgramBranches = State(initialValue: Set(savedFilters.programBranches))
        _selectedContextBranchIDs = State(initialValue: Set(savedFilters.contextBranchIDs))
    }

    private var language: AppLanguage { store.language }

    private var sortOrder: [KeyPathComparator<TeachingAssignmentDirectoryRow>] {
        var columns = assignmentSortHistory.map(\.column)
        for fallbackColumn in [TeachingAssignmentListSortColumn.context, .assignment] where !columns.contains(fallbackColumn) {
            columns.append(fallbackColumn)
        }
        return columns.flatMap { column -> [KeyPathComparator<TeachingAssignmentDirectoryRow>] in
            let ascending = assignmentSortHistory.first(where: { $0.column == column })?.ascending ?? column.defaultAscending
            let order: SortOrder = ascending ? .forward : .reverse
            switch column {
            case .type:
                return [KeyPathComparator(\.kindLabel, order: order)]
            case .context:
                return [
                    KeyPathComparator(\.contextName, order: order),
                    KeyPathComparator(\.activityName, order: .forward)
                ]
            case .assignment:
                return [
                    KeyPathComparator(\.activityName, order: order),
                    KeyPathComparator(\.contextName, order: .forward)
                ]
            case .role:
                return [
                    KeyPathComparator(\.roleLabel, order: order),
                    KeyPathComparator(\.activityName, order: .forward)
                ]
            case .year:
                return [
                    KeyPathComparator(\.yearLabel, order: order),
                    KeyPathComparator(\.activityName, order: .forward)
                ]
            case .status:
                return [
                    KeyPathComparator(\.statusRank, order: order),
                    KeyPathComparator(\.activityName, order: .forward)
                ]
            case .hours:
                return [
                    KeyPathComparator(\.hoursValue, order: order),
                    KeyPathComparator(\.activityName, order: .forward)
                ]
            case .student:
                return [
                    KeyPathComparator(\.studentLabel, order: order),
                    KeyPathComparator(\.activityName, order: .forward)
                ]
            }
        }
    }

    private var yearBounds: ClosedRange<Double> {
        let currentYear = Double(Calendar.current.component(.year, from: Date()))
        let lower = Double(availableYearValues.first ?? Int(currentYear))
        let upper = Double(availableYearValues.last ?? Int(currentYear))
        return lower...upper
    }

    private var hasAdjustableYearRange: Bool {
        yearBounds.lowerBound < yearBounds.upperBound
    }

    private var hasActiveFilters: Bool {
        searchText.nonEmpty != nil
            || !selectedKindFilters.isEmpty
            || !selectedStatusFilters.isEmpty
            || minimumYearValue != yearBounds.lowerBound
            || maximumYearValue != yearBounds.upperBound
            || !selectedInstitutionBranches.isEmpty
            || !selectedProgramBranches.isEmpty
            || !selectedContextBranchIDs.isEmpty
    }

    private var persistedFilterState: TeachingAssignmentFilterState {
        TeachingAssignmentFilterState(
            searchText: searchText,
            minimumYearValue: minimumYearValue,
            maximumYearValue: maximumYearValue,
            kindRawValues: selectedKindFilters.map(\.rawValue).sorted(),
            statusRawValues: selectedStatusFilters.map(\.rawValue).sorted(),
            institutionBranches: selectedInstitutionBranches.sorted(),
            programBranches: selectedProgramBranches.sorted(),
            contextBranchIDs: selectedContextBranchIDs.sorted()
        )
    }

    private var totalDisplayedHours: Double {
        filteredAssignmentRows.reduce(0) { $0 + $1.hoursValue }
    }

    private var availableInstitutionBranches: [String] {
        deduplicatedBranchValues(
            store.teachingCourses.map { store.teachingInstitutionKey(for: $0) }
                + store.teachingComponents.map { store.teachingInstitutionKey(for: $0) }
        )
    }

    private var availableProgramBranches: [String] {
        let courses = store.teachingCourses.filter {
            selectedInstitutionBranches.isEmpty || selectedInstitutionBranches.contains(store.teachingInstitutionKey(for: $0))
        }
        return deduplicatedBranchValues(courses.map { $0.localizedProgram(language: language) })
    }

    private var availableContextBranches: [TeachingCourse] {
        return store.teachingCourses.filter { course in
            guard course.contextType != .programTrack else { return false }
            let matchesInstitution = selectedInstitutionBranches.isEmpty || selectedInstitutionBranches.contains(store.teachingInstitutionKey(for: course))
            let matchesProgram = selectedProgramBranches.isEmpty || selectedProgramBranches.contains(course.localizedProgram(language: language))
            return matchesInstitution && matchesProgram
        }
        .sorted {
            teachingStructureLeafLabel($0, language: language).localizedStandardCompare(teachingStructureLeafLabel($1, language: language)) == .orderedAscending
        }
    }

    private var selectedInstitutionBranch: String? {
        selectedInstitutionBranches.count == 1 ? selectedInstitutionBranches.first?.trimmedOrNil : nil
    }

    private var selectedProgramBranch: String? {
        selectedProgramBranches.count == 1 ? selectedProgramBranches.first?.trimmedOrNil : nil
    }

    private var selectedContextBranchID: String? {
        selectedContextBranchIDs.count == 1 ? selectedContextBranchIDs.first?.trimmedOrNil : nil
    }

    private var selectedBranchContext: TeachingCourse? {
        guard let selectedContextBranchID else { return nil }
        return store.teachingCourses.first(where: { $0.id == selectedContextBranchID })
    }

    private var selectedProgramBranchCourse: TeachingCourse? {
        guard let institution = selectedInstitutionBranch?.trimmedOrNil,
              let program = selectedProgramBranch?.trimmedOrNil else { return nil }
        let normalizedInstitution = PublicationDerivation.normalizedName(institution)
        let normalizedProgram = PublicationDerivation.normalizedName(program)
        // F6: match on either language. A programme row keeps the Swedish name
        // in both fields until it is translated, so matching only the current
        // language left the row unreachable and its English name uneditable.
        return store.teachingCourses.first(where: { course in
            guard course.contextType == .programTrack,
                  PublicationDerivation.normalizedName(store.teachingInstitutionKey(for: course)) == normalizedInstitution else {
                return false
            }
            let sv = PublicationDerivation.normalizedName(course.programSv)
            let en = PublicationDerivation.normalizedName(course.programEn)
            return sv == normalizedProgram || en == normalizedProgram
        })
    }

    private var selectedEditableBranch: TeachingCourse? {
        if let selectedBranchContext {
            return selectedBranchContext
        }
        return selectedProgramBranchCourse
    }

    private enum PrimaryCreationAction {
        case none
        case program
        case context
        case assignment
    }

    private var primaryCreationAction: PrimaryCreationAction {
        if selectedContextBranchID != nil {
            return .assignment
        }
        if selectedInstitutionBranch != nil && selectedProgramBranch != nil {
            return .context
        }
        if selectedInstitutionBranch != nil {
            return .program
        }
        return .none
    }

    private func deduplicatedBranchValues(_ values: [String]) -> [String] {
        var seen: [String: String] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = PublicationDerivation.normalizedName(trimmed)
            if seen[key] == nil {
                seen[key] = trimmed
            }
        }
        return Array(seen.values).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func contextFilterLabel(for contextID: String) -> String {
        guard let context = store.teachingCourses.first(where: { $0.id == contextID }) else {
            return contextID
        }
        let leaf = teachingStructureLeafLabel(context, language: language).nonEmpty ?? context.localizedName(language: language)
        guard selectedProgramBranches.count != 1,
              let program = context.localizedProgram(language: language).trimmedOrNil else {
            return leaf
        }
        return "\(program) · \(leaf)"
    }

    private func pruneTeachingStructureFilters() {
        let programs = Set(availableProgramBranches)
        let contexts = Set(availableContextBranches.map(\.id))
        let nextPrograms = selectedProgramBranches.filter { programs.contains($0) }
        let nextContexts = selectedContextBranchIDs.filter { contexts.contains($0) }
        if nextPrograms != selectedProgramBranches {
            selectedProgramBranches = nextPrograms
        }
        if nextContexts != selectedContextBranchIDs {
            selectedContextBranchIDs = nextContexts
        }
    }

    @discardableResult
    private func ensureProgramBranchRecord(institution: String, program: String) -> TeachingCourse? {
        if let existing = selectedProgramBranchCourse {
            return existing
        }
        let id = store.addTeachingCourse(institution: institution)
        guard let created = store.teachingCourses.first(where: { $0.id == id }) else { return nil }
        var updated = created
        updated.contextType = .programTrack
        updated.nameSv = ""
        updated.nameEn = ""
        updated.programSv = program
        updated.programEn = program
        updated.termSv = ""
        updated.termEn = ""
        updated.term = ""
        updated.courseCode = ""
        updated.credits = ""
        updated.teachingLanguage = ""
        updated.level = nil
        store.saveTeachingCourse(updated)
        return store.teachingCourses.first(where: { $0.id == id }) ?? updated
    }

    private var primaryCreationButtonTitle: String {
        switch primaryCreationAction {
        case .program:
            return language.text("New programme / area", "Nytt program / område")
        case .context:
            return language.text("New course / track", "Ny kurs / spår")
        case .assignment:
            return language.text("New assignment", "Nytt uppdrag")
        case .none:
            return language.text("Select organization", "Välj organisation")
        }
    }

    var body: some View {
        teachingLifecycleView
    }

    private var teachingLifecycleView: some View {
        teachingSelectionObservationView
            .onAppear(perform: handleWorkspaceAppear)
            .onChange(of: store.route) { _, route in
                handleTeachingRouteChange(route)
            }
            .onChange(of: newRecordTrigger) { _, _ in
                guard isActive else { return }
                performPrimaryCreationAction()
            }
            .onChange(of: isActive) { oldValue, active in
                handleActiveStateChange(oldValue, active)
            }
            .onDisappear(perform: cancelWorkspaceTasks)
    }

    private var teachingSelectionObservationView: some View {
        teachingFilterObservationView
            .onChange(of: persistedFilterState) { _, state in
                TeachingAssignmentFilterPersistence.save(state)
            }
            .onChange(of: assignmentRows.map(\.id)) { _, ids in
                handleAssignmentRowIDsChange(ids)
            }
            .onChange(of: selectedAssignmentID) { _, id in
                handleSelectedAssignmentChange(id)
            }
    }

    private var teachingFilterObservationView: some View {
        teachingBranchObservationView
            .onChange(of: searchText) { _, _ in scheduleFilterRebuildIfActive() }
            .onChange(of: minimumYearValue) { _, _ in scheduleFilterRebuildIfActive() }
            .onChange(of: maximumYearValue) { _, _ in scheduleFilterRebuildIfActive() }
            .onChange(of: selectedKindFilters) { _, _ in scheduleFilterRebuildIfActive() }
            .onChange(of: selectedStatusFilters) { _, _ in scheduleFilterRebuildIfActive() }
            .onChange(of: assignmentSortHistory) { _, _ in scheduleFilterRebuildIfActive() }
    }

    private var teachingBranchObservationView: some View {
        teachingStoreObservationView
            .onChange(of: selectedInstitutionBranches) { _, _ in
                pruneTeachingStructureFilters()
                scheduleRowsRebuildIfActive()
            }
            .onChange(of: selectedProgramBranches) { _, _ in
                pruneTeachingStructureFilters()
                scheduleRowsRebuildIfActive()
            }
            .onChange(of: selectedContextBranchIDs) { _, _ in
                scheduleRowsRebuildIfActive()
            }
    }

    private var teachingStoreObservationView: some View {
        teachingWorkspaceBody
            .onChange(of: store.teachingAssignments) { _, _ in
                scheduleRowsRebuildIfActive(resetYearBounds: true)
            }
            .onChange(of: store.teachingCourses) { _, _ in
                scheduleRowsRebuildIfActive()
            }
            .onChange(of: store.teachingComponents) { _, _ in
                scheduleRowsRebuildIfActive()
            }
            .onChange(of: store.language) { _, _ in
                scheduleRowsRebuildIfActive()
            }
    }

    private func scheduleRowsRebuildIfActive(resetYearBounds: Bool = false) {
        guard isActive else {
            needsRowsRebuildWhenActive = true
            needsFilterRebuildWhenActive = true
            return
        }
        scheduleAssignmentRowsRebuild(resetYearBounds: resetYearBounds)
    }

    private func scheduleFilterRebuildIfActive() {
        guard isActive else {
            needsFilterRebuildWhenActive = true
            return
        }
        scheduleFilteredAssignmentRowsRebuild()
    }

    private func handleActiveStateChange(_ oldValue: Bool, _ active: Bool) {
        if active {
            if needsRowsRebuildWhenActive {
                rebuildAssignmentRows()
                resetYearBoundsIfNeeded()
                needsRowsRebuildWhenActive = false
            }
            if needsFilterRebuildWhenActive {
                rebuildFilteredAssignmentRows()
                needsFilterRebuildWhenActive = false
            }
            if let pendingRouteAssignmentID {
                applyTeachingRouteSelection(pendingRouteAssignmentID)
                store.consumeRoute()
                self.pendingRouteAssignmentID = nil
            } else if let route = store.route, route.destination == .teaching {
                applyTeachingRouteSelection(route.recordID)
                store.consumeRoute()
            }
        } else {
            clearTeachingFiltersForDeactivationIfNeeded()
            assignmentRowsRebuildTask?.cancel()
            assignmentFilterRebuildTask?.cancel()
        }
    }

    @ViewBuilder
    private var teachingWorkspaceBody: some View {
        PersistentSplitView(layout: .teachingAssignments) {
            sidebar
        } detail: {
            detail
        }
    }

    private var allRecordIDs: [String] {
        filteredAssignmentRows.map(\.id)
    }

    private var defaultSelection: String? {
        filteredAssignmentRows.first?.id
    }

    private func selection(for id: String) -> String? {
        filteredAssignmentRows.contains(where: { $0.id == id }) ? id : nil
    }

    private func rebuildAssignmentRows() {
        var nextRows: [TeachingAssignmentDirectoryRow] = []
        var nextCache = assignmentRowCache
        var nextRevisions: [String: TeachingAssignmentRowDependencyRevision] = [:]
        var rebuiltIDs: [String] = []

        for assignment in store.teachingAssignments {
            let revision = assignmentRowRevision(assignment)
            let row: TeachingAssignmentDirectoryRow
            if assignmentRowRevisions[assignment.id] == revision,
               let cached = assignmentRowCache[assignment.id] {
                row = cached
            } else {
                row = buildAssignmentRow(for: assignment)
                rebuiltIDs.append(assignment.id)
            }
            nextRows.append(row)
            nextCache[assignment.id] = row
            nextRevisions[assignment.id] = revision
        }

        let liveIDs = Set(store.teachingAssignments.map(\.id))
        nextCache = nextCache.filter { liveIDs.contains($0.key) }
        nextRevisions = nextRevisions.filter { liveIDs.contains($0.key) }

        assignmentRows = nextRows
        assignmentRowCache = nextCache
        assignmentRowRevisions = nextRevisions
        availableYearValues = Array(Set(nextRows.flatMap(\.yearValues))).sorted()
        if !rebuiltIDs.isEmpty {
            store.appendPerformanceDiagnostic(
                "teaching-row-cache total=\(nextRows.count) rebuilt=\(rebuiltIDs.count) reused=\(nextRows.count - rebuiltIDs.count) ids=\(rebuiltIDs.prefix(12).joined(separator: ","))"
            )
        }
    }

    private func buildAssignmentRow(for assignment: TeachingAssignment) -> TeachingAssignmentDirectoryRow {
        let kind = resolvedKind(for: assignment)
        let activityName = localizedActivityName(for: assignment.activityName)
        let contextName = assignmentStructureSummary(assignment)
        let roleLabel = assignmentRoleLabel(assignment)
        let studentLabel = assignmentStudentLabel(assignment)
        let yearValues = yearValues(for: assignment)

        let searchBlob = [
            activityName,
            contextName,
            kind.displayName(language: language),
            roleLabel,
            studentLabel,
            assignment.comment,
        ].joined(separator: " ")
        return TeachingAssignmentDirectoryRow(
            assignment: assignment,
            kind: kind,
            kindLabel: kind.displayName(language: language),
            activityName: activityName,
            contextName: contextName,
            roleLabel: roleLabel,
            yearLabel: assignmentYearLabel(assignment),
            statusLabel: assignmentStatusText(assignment, language: language),
            statusRank: assignmentStatusRank(assignment),
            hoursValue: assignmentTotalHoursValue(assignment),
            hoursLabel: assignmentTotalHoursText(assignment),
            studentLabel: studentLabel,
            retendoState: assignmentRetendoState(assignment),
            yearValues: yearValues,
            searchBlob: searchBlob,
            normalizedSearchBlob: normalizedSearchFilterText(searchBlob)
        )
    }

    private func assignmentRowRevision(_ assignment: TeachingAssignment) -> TeachingAssignmentRowDependencyRevision {
        TeachingAssignmentRowDependencyRevision(
            assignment: assignment,
            context: context(for: assignment),
            component: activityComponent(for: assignment),
            language: store.language,
            selectedProgramBranch: selectedProgramBranch?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func assignmentStructureSummary(_ assignment: TeachingAssignment) -> String {
        guard let context = context(for: assignment) else {
            return assignment.programName
        }
        let breadcrumb = teachingStructureBreadcrumb(context, language: language)
        var visible = Array(breadcrumb.dropFirst())
        let selectedProgram = selectedProgramBranch?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selectedProgram,
           visible.first?.trimmingCharacters(in: .whitespacesAndNewlines) == selectedProgram {
            visible.removeFirst()
        }
        if !visible.isEmpty {
            return visible.joined(separator: " › ")
        }
        return teachingStructureLeafLabel(context, language: language).nonEmpty
            ?? assignment.programName
    }

    private func resetYearBoundsIfNeeded() {
        let bounds = yearBounds
        if minimumYearValue == 0 && maximumYearValue == 0 {
            minimumYearValue = bounds.lowerBound
            maximumYearValue = bounds.upperBound
            return
        }
        minimumYearValue = max(minimumYearValue, bounds.lowerBound)
        maximumYearValue = min(maximumYearValue, bounds.upperBound)
    }

    private func rebuildFilteredAssignmentRows() {
        filteredAssignmentRows = assignmentRows
            .filter { row in
                matchesStructureFilter(row.assignment)
                    && matchesSearchFilter(row)
                    && matchesYearFilter(row)
                    && matchesKindFilter(row)
                    && matchesStatusFilter(row)
            }
            .sorted(using: sortOrder)
    }

    private func matchesStructureFilter(_ assignment: TeachingAssignment) -> Bool {
        guard !selectedInstitutionBranches.isEmpty || !selectedProgramBranches.isEmpty || !selectedContextBranchIDs.isEmpty else {
            return true
        }
        guard let context = context(for: assignment) else { return false }
        if !selectedInstitutionBranches.isEmpty,
           !selectedInstitutionBranches.contains(store.teachingInstitutionKey(for: context)) {
            return false
        }
        if !selectedProgramBranches.isEmpty,
           !selectedProgramBranches.contains(context.localizedProgram(language: language)) {
            return false
        }
        if !selectedContextBranchIDs.isEmpty,
           !selectedContextBranchIDs.contains(context.id) {
            return false
        }
        return true
    }

    private func scheduleAssignmentRowsRebuild(resetYearBounds: Bool = false) {
        assignmentRowsRebuildTask?.cancel()
        let task = DispatchWorkItem {
            rebuildAssignmentRows()
            if resetYearBounds {
                resetYearBoundsIfNeeded()
            }
            rebuildFilteredAssignmentRows()
        }
        assignmentRowsRebuildTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: task)
    }

    private func scheduleFilteredAssignmentRowsRebuild() {
        assignmentFilterRebuildTask?.cancel()
        let task = DispatchWorkItem {
            rebuildFilteredAssignmentRows()
        }
        assignmentFilterRebuildTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppWorkspaceTitleBar(
                title: language.text("Teaching assignments", "Undervisningsuppdrag"),
                spacing: 10,
                horizontalPadding: 0,
                verticalPadding: 0
            ) {
                Spacer()
                Menu {
                    Button(language.text("New programme / area", "Nytt program / område")) { createProgramBranch() }
                        .disabled(selectedInstitutionBranch == nil)
                    Button(language.text("New course / track", "Ny kurs / spår")) { createContextBranch() }
                        .disabled(selectedInstitutionBranch == nil || selectedProgramBranch == nil)
                    Button(language.text("New assignment", "Nytt uppdrag")) { createAssignment() }
                        .disabled(selectedContextBranchID == nil)
                    if primaryCreationAction == .none {
                        Divider()
                        Text(language.text("Select an organization in the tree first", "Välj först en organisation i trädet"))
                    }
                } label: {
                    Text(language.text("New", "Nytt"))
                        .font(appFont(.body).weight(.semibold))
                }
                .menuStyle(.borderedButton)
                .controlSize(.regular)
                .help(primaryCreationButtonTitle)
            }

            filterBar

            teachingAssignmentList

            HStack(spacing: 10) {
                AppTableHeaderText(text: language.text("Total hours", "Totala timmar"))
                Spacer()
            Text("\(formattedHours(totalDisplayedHours))")
                    .appTypography(.tableHeader)
            }
            .appCardChrome(
                horizontalPadding: 12,
                verticalPadding: 10,
                fill: AppPalette.listContentSurface,
                stroke: AppPalette.border.opacity(0.7),
                cornerRadius: 16
            )

        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppPalette.sidebarPanelSurface)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedAssignmentID,
           let assignment = filteredAssignmentRows.first(where: { $0.id == id })?.assignment {
            TeachingAssignmentDetailView(
                store: store,
                assignment: assignment,
                lockedContextID: selectedContextBranchID
            )
                .id(assignment.id)
                .undoRevealPulse(
                    triggerID: store.undoRevealRequest?.id,
                    isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: .teaching, recordID: assignment.id) == true
                )
                .performanceScopeProbe(store: store, scope: "teaching-detail", identifier: assignment.id)
                .background(
                    PerformanceReadyReporter {
                        guard pendingSelectionMeasurementID == assignment.id,
                              let pendingSelectionStartedAt else { return }
                        let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                        store.appendPerformanceDiagnostic(
                            String(
                                format: "teaching-selection-ready assignment=%@ ready_ms=%.2f",
                                assignment.activityName,
                                duration
                            )
                        )
                        self.pendingSelectionMeasurementID = nil
                        self.pendingSelectionStartedAt = nil
                    }
                )
        } else if let branch = selectedEditableBranch {
            TeachingStructureBranchDetailView(
                store: store,
                course: branch,
                language: language
            )
                .id("branch-\(branch.id)")
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        AppWorkspaceEmptyStateView(
            title: language.text("No teaching post selected", "Ingen undervisningspost vald"),
            subtitle: language.text("Select a branch and then a post.", "Välj först en gren och sedan en post."),
            kind: .teaching
        )
    }

    private var filterBar: some View {
        let lowerYear = Int(min(minimumYearValue, maximumYearValue))
        let upperYear = Int(max(minimumYearValue, maximumYearValue))
        let yearRangeText = "\(language.text("Year", "År")): \(lowerYear)–\(upperYear)"

        return AppFilterCard {
            VStack(alignment: .leading, spacing: 8) {
                AppFilterRow(
                    showsClearButton: searchText.nonEmpty != nil,
                    clearAction: { searchText = "" }
                ) {
                    AppSidebarSearchField(
                        placeholder: language.text("Search teaching", "Sök undervisning"),
                        text: $searchText
                    )
                }

                teachingStructureFilters

                AppFilterRow(
                    showsClearButton: !selectedStatusFilters.isEmpty,
                    clearAction: { selectedStatusFilters.removeAll() }
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([TeachingAssignmentStatusKind.ongoing, .completed, .none], id: \.self) { status in
                                AppFilterChip(
                                    label: statusFilterLabel(for: status),
                                    isSelected: selectedStatusFilters.contains(status)
                                ) {
                                    toggleStatusFilter(status)
                                }
                            }
                        }
                    }
                }

                AppFilterRow(
                    showsClearButton: !selectedKindFilters.isEmpty,
                    clearAction: { selectedKindFilters.removeAll() }
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TeachingAssignmentKind.allCases) { kind in
                                AppFilterChip(
                                    label: kind.displayName(language: language),
                                    isSelected: selectedKindFilters.contains(kind)
                                ) {
                                    toggleKindFilter(kind)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    AppFilterRangeControl(
                        title: yearRangeText,
                        lowerValue: $minimumYearValue,
                        upperValue: $maximumYearValue,
                        bounds: yearBounds,
                        unavailableText: language.text("Only one year available", "Endast ett år tillgängligt")
                    )

                    AppFilterChip(
                        label: language.text("Current year", "Aktuellt år"),
                        isSelected: isCurrentTeachingYearFilterActive
                    ) {
                        toggleCurrentTeachingYearFilter()
                    }

                    if minimumYearValue != yearBounds.lowerBound || maximumYearValue != yearBounds.upperBound {
                        FilterClearButton {
                            minimumYearValue = yearBounds.lowerBound
                            maximumYearValue = yearBounds.upperBound
                        }
                    }
                    Spacer()
                }

                AppFilterClearAllRow(isVisible: hasActiveFilters) {
                    searchText = ""
                    minimumYearValue = yearBounds.lowerBound
                    maximumYearValue = yearBounds.upperBound
                    selectedKindFilters.removeAll()
                    selectedStatusFilters.removeAll()
                    selectedInstitutionBranches.removeAll()
                    selectedProgramBranches.removeAll()
                    selectedContextBranchIDs.removeAll()
                }
            }
        }
    }

    private var teachingStructureFilters: some View {
        VStack(alignment: .leading, spacing: 6) {
            AppFilterRow(
                showsClearButton: !selectedInstitutionBranches.isEmpty,
                clearAction: { selectedInstitutionBranches.removeAll() }
            ) {
                teachingStructureFilterRow(title: language.text("Organization", "Organisation")) {
                    MultiSelectFilterMenu(
                        title: language.text("All", "Alla"),
                        emptyLabel: language.text("All organizations", "Alla organisationer"),
                        options: availableInstitutionBranches,
                        selectedOptions: $selectedInstitutionBranches
                    )
                }
            }

            AppFilterRow(
                showsClearButton: !selectedProgramBranches.isEmpty,
                clearAction: { selectedProgramBranches.removeAll() }
            ) {
                teachingStructureFilterRow(title: language.text("Programme / area", "Program / område")) {
                    MultiSelectFilterMenu(
                        title: language.text("All", "Alla"),
                        emptyLabel: language.text("All programmes / areas", "Alla program / områden"),
                        options: availableProgramBranches,
                        selectedOptions: $selectedProgramBranches
                    )
                }
            }

            AppFilterRow(
                showsClearButton: !selectedContextBranchIDs.isEmpty,
                clearAction: { selectedContextBranchIDs.removeAll() }
            ) {
                teachingStructureFilterRow(title: language.text("Course / track", "Kurs / spår")) {
                    MultiSelectFilterMenu(
                        title: language.text("All", "Alla"),
                        emptyLabel: language.text("All courses / tracks", "Alla kurser / spår"),
                        options: availableContextBranches.map(\.id),
                        selectedOptions: $selectedContextBranchIDs,
                        display: { contextID in
                            contextFilterLabel(for: contextID)
                        },
                        popoverWidth: 460
                    )
                }
            }
        }
    }

    private func teachingStructureFilterRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .appTypography(.tableHeader)
                .lineLimit(1)
                .frame(width: 118, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
    }

    private func createProgramBranch() {
        guard let institution = selectedInstitutionBranch?.trimmedOrNil else { return }
        let id = store.addTeachingCourse(institution: institution)
        guard let created = store.teachingCourses.first(where: { $0.id == id }) else { return }
        var updated = created
        let base = language.text("New programme / area", "Nytt program / område")
        let existingPrograms = Set(
            store.teachingCourses
                .filter { store.teachingInstitutionKey(for: $0) == institution }
                .map { $0.localizedProgram(language: language) }
        )
        var candidate = base
        var suffix = 2
        while existingPrograms.contains(candidate) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        updated.nameSv = ""
        updated.nameEn = ""
        updated.programSv = candidate
        updated.programEn = candidate
        updated.termSv = ""
        updated.termEn = ""
        updated.term = ""
        updated.contextType = .programTrack
        store.saveTeachingCourse(updated)
        selectedProgramBranches = [candidate]
        selectedContextBranchIDs.removeAll()
        setSelectedAssignmentID(nil)
        scheduleAssignmentRowsRebuild()
    }

    private func createContextBranch() {
        guard let institution = selectedInstitutionBranch?.trimmedOrNil,
              let program = selectedProgramBranch?.trimmedOrNil else { return }
        let id = store.addTeachingCourse(institution: institution)
        guard let created = store.teachingCourses.first(where: { $0.id == id }) else { return }
        var updated = created
        updated.programSv = program
        updated.programEn = program
        updated.contextType = .course
        store.saveTeachingCourse(updated)
        selectedContextBranchIDs = [id]
        setSelectedAssignmentID(nil)
        scheduleAssignmentRowsRebuild()
    }

    private func performPrimaryCreationAction() {
        switch primaryCreationAction {
        case .program:
            createProgramBranch()
        case .context:
            createContextBranch()
        case .assignment:
            createAssignment()
        case .none:
            break
        }
    }

    private var teachingAssignmentList: some View {
        let typeWidth: CGFloat = 120
        let contextWidth: CGFloat = 210
        let momentWidth: CGFloat = 190
        let roleWidth: CGFloat = 130
        let yearWidth: CGFloat = 82
        let statusWidth: CGFloat = 90
        let hoursWidth: CGFloat = 80
        let studentWidth: CGFloat = 140
        let tableContentWidth = typeWidth
            + contextWidth
            + momentWidth
            + roleWidth
            + yearWidth
            + statusWidth
            + hoursWidth
            + studentWidth
            + 20
        let orderedIDs = filteredAssignmentRows.map(\.id)
        let reminderCounts = calendarTaskReminderBadgeCounts(entries: store.calendarTaskReminderBadgeEntries)

        return AppListTable(contentWidth: tableContentWidth) {
            HStack(spacing: 0) {
                teachingListHeader(language.text("Type", "Typ"), width: typeWidth, column: .type)
                teachingListHeader(language.text("Course / context", "Kurs / sammanhang"), width: contextWidth, column: .context)
                teachingListHeader(language.text("Teaching assignment", "Undervisningsuppdrag"), width: momentWidth, column: .assignment)
                teachingListHeader(language.text("Role", "Roll"), width: roleWidth, column: .role)
                teachingListHeader(language.text("Year", "År"), width: yearWidth, column: .year)
                teachingListHeader(language.text("Status", "Status"), width: statusWidth, column: .status)
                teachingListHeader(language.text("Hours", "Timmar"), width: hoursWidth, alignment: .trailing, column: .hours)
                teachingListHeader(language.text("Student", "Student"), width: studentWidth, column: .student)
            }
        } rows: {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredAssignmentRows) { row in
                    let reminderCount = reminderCounts.teachingAssignmentCounts[row.id] ?? 0
                    let reminderHelp = calendarTaskReminderBadgeHelp(entries: reminderCounts.entries, language: language) {
                        $0.badgeTargets.contains(.teachingAssignment(row.id))
                    }
                    AppListRowButton(
                        width: tableContentWidth,
                        action: { handleAssignmentSelectionCandidate(row.id) },
                        background: { teachingListRowBackground(for: row) }
                    ) {
                        HStack(spacing: 0) {
                            TeachingAssignmentDirectoryCell(
                                text: row.kindLabel,
                                alignment: .leading
                            )
                            .padding(.trailing, reminderCount > 0 ? 34 : 0)
                            .frame(width: typeWidth, alignment: .leading)
                            .appReminderListBadge(reminderCount, help: reminderHelp)
                            teachingListCell(assignmentStructureSummary(row.assignment).nonEmpty ?? "—", width: contextWidth)
                            teachingListCell(row.activityName, width: momentWidth)
                            teachingListCell(row.roleLabel.nonEmpty ?? "—", width: roleWidth)
                            teachingListCell(row.yearLabel.nonEmpty ?? "—", width: yearWidth)
                            teachingListCell(row.statusLabel.nonEmpty ?? "—", width: statusWidth)
                            teachingListCell(row.hoursLabel, width: hoursWidth, alignment: .trailing)
                            teachingListCell(row.studentLabel.nonEmpty ?? "—", width: studentWidth)
                        }
                    }
                    .id(row.id)

                    if row.id != filteredAssignmentRows.last?.id {
                        Divider()
                    }
                }
            }
        }
        .appListKeyboardNavigation(
            store: store,
            destination: .teaching,
            isEnabled: isActive,
            orderedIDs: orderedIDs,
            selectedID: selectedAssignmentID,
            onSelect: handleAssignmentSelectionCandidate
        )
    }

    private func teachingListHeader(
        _ title: String,
        width: CGFloat,
        alignment: Alignment = .leading,
        column: TeachingAssignmentListSortColumn
    ) -> some View {
        let criterion = assignmentSortHistory.first(where: { $0.column == column })
        let sortIndex = assignmentSortHistory.firstIndex(where: { $0.column == column })
        return Button {
            toggleAssignmentSort(column)
        } label: {
            SortableListHeaderLabel(title: title, ascending: criterion?.ascending, sortIndex: sortIndex)
                .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(language.text("Reset", "Återställ")) {
                resetAssignmentSort()
            }
        }
    }

    private func toggleAssignmentSort(_ column: TeachingAssignmentListSortColumn) {
        if let existingIndex = assignmentSortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                assignmentSortHistory[0].ascending.toggle()
            } else {
                let criterion = assignmentSortHistory.remove(at: existingIndex)
                assignmentSortHistory.insert(criterion, at: 0)
            }
        } else {
            assignmentSortHistory.insert(TeachingAssignmentListSortCriterion(column: column, ascending: column.defaultAscending), at: 0)
        }
        ListSortPersistence.save(assignmentSortHistory, defaultsKey: "TeachingAssignmentsListSort")
    }

    private func resetAssignmentSort() {
        assignmentSortHistory = [
            TeachingAssignmentListSortCriterion(column: .context, ascending: true),
            TeachingAssignmentListSortCriterion(column: .assignment, ascending: true),
        ]
        ListSortPersistence.save(assignmentSortHistory, defaultsKey: "TeachingAssignmentsListSort")
    }

    private func teachingListCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .leading
    ) -> some View {
        TeachingAssignmentDirectoryCell(text: text, alignment: alignment)
            .frame(width: width, alignment: alignment)
    }

    /// Same marking as the other lists: a selected row is filled blue, and
    /// an assignment that is not (or only partly) confirmed in Retendo gets
    /// a red bar on the left, which stays visible when the row is selected.
    private func teachingListRowBackground(for row: TeachingAssignmentDirectoryRow) -> some View {
        AppListRowBackground(
            isSelected: row.id == selectedAssignmentID,
            toneFill: row.retendoState.needsConfirmation ? AppPalette.vividRed : nil
        )
    }

    private func localizedActivityName(for canonicalName: String) -> String {
        if let component = store.teachingComponents.first(where: { $0.nameSv == canonicalName || $0.nameEn == canonicalName }) {
            return component.localizedName(language: language)
        }
        return canonicalName.nonEmpty ?? "—"
    }

    private func context(for assignment: TeachingAssignment) -> TeachingCourse? {
        store.teachingCourses.first(where: { $0.id == assignment.contextID })
    }

    private func assignmentStatusRank(_ assignment: TeachingAssignment) -> Int {
        switch assignmentStatusKind(assignment) {
        case .ongoing:
            return 0
        case .completed:
            return 1
        case .none:
            return 2
        }
    }

    private func assignmentHoursValue(_ assignment: TeachingAssignment) -> Double {
        assignmentTotalHoursValue(assignment)
    }

    private func assignmentStudentLabel(_ assignment: TeachingAssignment) -> String {
        let participantForm = effectiveParticipantFormForList(assignment)
        if participantForm == .individual || participantForm == .groupAndIndividual {
            return assignment.studentName.nonEmpty ?? ""
        }
        if participantForm == .group {
            return language.text("Group", "Grupp")
        }
        return ""
    }

    private func assignmentRetendoState(_ assignment: TeachingAssignment) -> TeachingRetendoState {
        let periods = assignment.periods.filter { !$0.isEmpty }
        guard !periods.isEmpty else { return .none }
        let confirmedCount = periods.filter(\.confirmedInRetendo).count
        if confirmedCount == 0 { return .unconfirmed }
        if confirmedCount == periods.count { return .full }
        return .partial
    }

    private func formattedHours(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private func matchesSearchFilter(_ row: TeachingAssignmentDirectoryRow) -> Bool {
        let searchQuery = SearchFilterQuery(raw: searchText)
        guard !searchQuery.isEmpty else { return true }
        return searchQuery.matches(normalizedHaystack: row.normalizedSearchBlob)
    }

    private func matchesYearFilter(_ row: TeachingAssignmentDirectoryRow) -> Bool {
        let lower = Int(min(minimumYearValue, maximumYearValue))
        let upper = Int(max(minimumYearValue, maximumYearValue))
        guard !row.yearValues.isEmpty else { return true }
        return row.yearValues.contains { $0 >= lower && $0 <= upper }
    }

    private func matchesKindFilter(_ row: TeachingAssignmentDirectoryRow) -> Bool {
        guard !selectedKindFilters.isEmpty else { return true }
        return selectedKindFilters.contains(row.kind)
    }

    private func matchesStatusFilter(_ row: TeachingAssignmentDirectoryRow) -> Bool {
        guard !selectedStatusFilters.isEmpty else { return true }
        return selectedStatusFilters.contains(assignmentStatusKind(row.assignment))
    }

    private var currentTeachingYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var isCurrentTeachingYearFilterActive: Bool {
        let current = Double(currentTeachingYear)
        return minimumYearValue == current && maximumYearValue == current
    }

    private func toggleCurrentTeachingYearFilter() {
        if isCurrentTeachingYearFilterActive {
            minimumYearValue = yearBounds.lowerBound
            maximumYearValue = yearBounds.upperBound
            return
        }
        let current = Double(currentTeachingYear)
        let clamped = min(max(current, yearBounds.lowerBound), yearBounds.upperBound)
        minimumYearValue = clamped
        maximumYearValue = clamped
    }

    private func yearValues(for assignment: TeachingAssignment) -> [Int] {
        let periods = assignment.periods.filter { !$0.isEmpty }
        var values = Set<Int>()
        for period in periods {
            let startYear = period.from.nonEmpty.flatMap(yearComponent)
            let endYear = period.to.nonEmpty.flatMap(yearComponent)
            switch (startYear, endYear) {
            case let (start?, end?):
                for year in min(start, end)...max(start, end) {
                    values.insert(year)
                }
            case let (start?, nil):
                values.insert(start)
            case let (nil, end?):
                values.insert(end)
            case (nil, nil):
                break
            }
        }
        return values.sorted()
    }

    private func toggleStatusFilter(_ status: TeachingAssignmentStatusKind) {
        if selectedStatusFilters.contains(status) {
            selectedStatusFilters.remove(status)
        } else {
            selectedStatusFilters.insert(status)
        }
    }

    private func toggleKindFilter(_ kind: TeachingAssignmentKind) {
        if selectedKindFilters.contains(kind) {
            selectedKindFilters.remove(kind)
        } else {
            selectedKindFilters.insert(kind)
        }
    }

    private func clearTeachingFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .teaching) else { return }
        guard hasActiveFilters else { return }
        searchText = ""
        minimumYearValue = yearBounds.lowerBound
        maximumYearValue = yearBounds.upperBound
        selectedKindFilters.removeAll()
        selectedStatusFilters.removeAll()
        selectedInstitutionBranches.removeAll()
        selectedProgramBranches.removeAll()
        selectedContextBranchIDs.removeAll()
        needsFilterRebuildWhenActive = true
    }

    private func statusFilterLabel(for status: TeachingAssignmentStatusKind) -> String {
        switch status {
        case .ongoing:
            return language.text("Ongoing", "Pågående")
        case .completed:
            return language.text("Completed", "Avslutat")
        case .none:
            return language.text("No status", "Ingen status")
        }
    }

    private func effectiveParticipantFormForList(_ assignment: TeachingAssignment) -> TeachingAssignmentCategory? {
        if let participantForm = assignment.participantForm {
            return participantForm
        }
        return activityComponent(for: assignment)?.participantForm
    }

    private func activityComponent(for assignment: TeachingAssignment) -> TeachingComponent? {
        if let activityID = assignment.activityID,
           let matched = store.teachingComponents.first(where: { $0.id == activityID }) {
            return matched
        }
        return store.teachingComponents.first(where: { $0.nameSv == assignment.activityName || $0.nameEn == assignment.activityName })
    }

    private func resolvedKind(for assignment: TeachingAssignment) -> TeachingAssignmentKind {
        assignment.kind ?? inferredTeachingAssignmentKind(assignment: assignment, context: context(for: assignment))
    }

    private func assignmentRoleLabel(_ assignment: TeachingAssignment) -> String {
        assignment.roles.map { store.teachingRoleDisplayName($0, language: language) }.joined(separator: ", ")
    }

    private func createAssignment() {
        let id = store.addTeachingAssignment(kind: nil)
        if let assignment = store.teachingAssignments.first(where: { $0.id == id }) {
            var updated = assignment
            if let selectedContextBranchID {
                updated.contextID = selectedContextBranchID
                if let context = store.teachingCourses.first(where: { $0.id == selectedContextBranchID }) {
                    updated.programName = context.localizedProgram(language: language)
                }
                store.saveTeachingAssignment(updated)
            }
        }
        setSelectedAssignmentID(id, armLock: true)
    }

    private func cancelWorkspaceTasks() {
        assignmentRowsRebuildTask?.cancel()
        assignmentFilterRebuildTask?.cancel()
        assignmentSelectionCoordinator.clear()
    }

    private func handleTeachingRouteChange(_ route: AppRoute?) {
        guard let route, route.destination == .teaching else { return }
        guard isActive else {
            pendingRouteAssignmentID = route.recordID
            store.appendPerformanceDiagnostic("teaching-route-deferred id=\(route.recordID)")
            return
        }
        applyTeachingRouteSelection(route.recordID)
        store.consumeRoute()
    }

    private func applyTeachingRouteSelection(_ recordID: String) {
        if store.teachingAssignments.contains(where: { $0.id == recordID }) {
            setSelectedAssignmentID(selection(for: recordID) ?? recordID, armLock: true)
            return
        }
        guard let course = store.teachingCourses.first(where: { $0.id == recordID }) else {
            setSelectedAssignmentID(recordID, armLock: true)
            return
        }
        selectedInstitutionBranches = Set([store.teachingInstitutionKey(for: course)].compactMap(\.trimmedOrNil))
        selectedProgramBranches = Set([course.localizedProgram(language: language)].compactMap(\.trimmedOrNil))
        selectedContextBranchIDs = [course.id]
        setSelectedAssignmentID(nil)
        scheduleAssignmentRowsRebuild()
    }

    private func handleAssignmentRowIDsChange(_ ids: [String]) {
        guard let selectedAssignmentID else {
            setSelectedAssignmentID(defaultSelection, resignFirstResponder: false)
            return
        }
        if !ids.contains(selectedAssignmentID) {
            setSelectedAssignmentID(defaultSelection, resignFirstResponder: false)
        }
    }

    private func handleSelectedAssignmentChange(_ id: String?) {
        if let id,
           filteredAssignmentRows.contains(where: { $0.id == id }) == false,
           let assignment = store.teachingAssignments.first(where: { $0.id == id }) {
            synchronizeBranchSelection(with: assignment)
        }
        store.rememberSelection(id: id, for: .teaching)
        pendingSelectionMeasurementID = id
        pendingSelectionStartedAt = CFAbsoluteTimeGetCurrent()
        store.appendPerformanceDiagnostic(
            String(
                format: "teaching-selection-start id=%@",
                id ?? "-"
            )
        )
    }

    private func handleWorkspaceAppear() {
        guard isActive else {
            needsRowsRebuildWhenActive = true
            needsFilterRebuildWhenActive = true
            return
        }
        rebuildAssignmentRows()
        resetYearBoundsIfNeeded()
        rebuildFilteredAssignmentRows()
        if let route = store.route, route.destination == .teaching {
            applyTeachingRouteSelection(route.recordID)
            store.consumeRoute()
            return
        }
        guard selectedAssignmentID == nil else { return }
        if let saved = store.lastSelectedRecordID(for: .teaching) {
            setSelectedAssignmentID(selection(for: saved))
        }
        if selectedAssignmentID == nil {
            let fallbackSelection = defaultSelection
            setSelectedAssignmentID(fallbackSelection)
        }
    }

    private func handleAssignmentSelectionCandidate(_ newValue: String?) {
        guard assignmentSelectionCoordinator.accepts(candidate: newValue) else { return }
        setSelectedAssignmentID(newValue, armLock: newValue != nil)
    }

    private func setSelectedAssignmentID(_ newValue: String?, armLock: Bool = false, resignFirstResponder: Bool = true) {
        guard selectedAssignmentID != newValue else {
            if armLock, let newValue {
                armAssignmentSelectionLock(for: newValue)
            }
            return
        }
        if resignFirstResponder {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        let previousID = selectedAssignmentID
        selectedAssignmentID = newValue
        if armLock, let newValue {
            assignmentSelectionCoordinator.arm(newValue, previousID: previousID)
        } else if newValue == nil {
            assignmentSelectionCoordinator.clear()
        }
    }

    private func armAssignmentSelectionLock(for id: String) {
        assignmentSelectionCoordinator.arm(
            id,
            previousID: assignmentSelectionCoordinator.previousID
        )
    }

    private func synchronizeBranchSelection(with assignment: TeachingAssignment) {
        guard let context = context(for: assignment) else { return }
        selectedInstitutionBranches = Set([store.teachingInstitutionKey(for: context)].compactMap(\.trimmedOrNil))
        selectedProgramBranches = Set([context.localizedProgram(language: language)].compactMap(\.trimmedOrNil))
        selectedContextBranchIDs = [context.id]
        scheduleFilteredAssignmentRowsRebuild()
    }
}



@MainActor
private func teachingCatalogHeaderButton(
    title: String,
    ascending: Bool?,
    sortIndex: Int?,
    width: CGFloat,
    resetTitle: String,
    onToggle: @escaping () -> Void,
    onReset: @escaping () -> Void
) -> some View {
    AppSortableListHeader(
        title: title,
        ascending: ascending,
        sortIndex: sortIndex,
        width: width,
        foreground: AppPalette.appText,
        resetTitle: resetTitle,
        onToggle: onToggle,
        onReset: onReset
    )
}





private struct TeachingAssignmentDetailView: View {
    @ObservedObject var store: GrantDataStore
    let assignment: TeachingAssignment
    let lockedContextID: String?
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: TeachingAssignment
    @State private var taskRows: [PublicationTaskItem]
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var hasPendingLocalEdits = false
    @State private var cachedInstitutionOptions: [String] = []
    @State private var cachedProgramOptions: [String] = []
    @State private var cachedContextOptions: [String] = []
    @State private var cachedFilteredContextCourses: [TeachingCourse] = []
    @State private var cachedActivityCandidates: [TeachingComponent] = []
    @State private var cachedActivityOptions: [String] = []
    @State private var cachedStudentOptions: [String] = []
    @State private var selectedInstitutionFilter = ""
    @State private var selectedProgramFilter = ""
    @State private var showingKindManager = false
    @State private var showingReportCategoryManager = false
    @State private var showingRoleManager = false

    init(store: GrantDataStore, assignment: TeachingAssignment, lockedContextID: String? = nil) {
        self.store = store
        self.assignment = assignment
        self.lockedContextID = lockedContextID
        _draft = State(initialValue: assignment)
        _taskRows = State(initialValue: Self.normalizedTasks(assignment.tasks))
    }

    private var language: AppLanguage { store.language }

    private var institutionOptions: [String] { cachedInstitutionOptions }

    private var effectiveSelectedInstitution: String {
        selectedInstitutionFilter.trimmedOrNil
            ?? currentContext.map { store.teachingInstitutionKey(for: $0) }?.nonEmpty
            ?? ""
    }

    private var effectiveSelectedProgram: String {
        selectedProgramFilter.trimmedOrNil
            ?? draft.programName.trimmedOrNil
            ?? currentContext?.localizedProgram(language: language).trimmedOrNil
            ?? ""
    }

    private var programOptions: [String] { cachedProgramOptions }

    private var filteredContextCourses: [TeachingCourse] { cachedFilteredContextCourses }

    private var contextOptions: [String] {
        cachedContextOptions
    }

    private var activityOptions: [String] {
        cachedActivityOptions
    }

    private var studentOptions: [String] {
        cachedStudentOptions
    }

    private var selectedActivity: TeachingComponent? {
        if let activityID = draft.activityID,
           let matched = activityCandidates.first(where: { $0.id == activityID }) ?? store.teachingComponents.first(where: { $0.id == activityID }) {
            return matched
        }
        return activityCandidates.first(where: { $0.nameSv == draft.activityName || $0.nameEn == draft.activityName })
            ?? store.teachingComponents.first(where: { $0.nameSv == draft.activityName || $0.nameEn == draft.activityName })
    }

    private var currentInstitution: String? {
        guard let contextID = lockedContextID ?? draft.contextID else { return nil }
        return store.teachingCourses.first(where: { $0.id == contextID }).map { store.teachingInstitutionKey(for: $0) }?.nonEmpty
    }

    private var activityCandidates: [TeachingComponent] { cachedActivityCandidates }

    private var participantFormBinding: Binding<TeachingAssignmentCategory?> {
        Binding(
            get: { draft.participantForm },
            set: { draft.participantForm = $0 }
        )
    }

    private var institutionTextBinding: Binding<String> {
        Binding(
            get: { effectiveSelectedInstitution },
            set: { newValue in
                selectedInstitutionFilter = newValue
            }
        )
    }

    private var programTextBinding: Binding<String> {
        Binding(
            get: { effectiveSelectedProgram },
            set: { newValue in
                selectedProgramFilter = newValue
                draft.programName = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
    }

    private var contextTextBinding: Binding<String> {
        Binding(
            get: { currentContext.map { teachingStructureLeafLabel($0, language: language) } ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let selected = filteredContextCourses.first(where: {
                    teachingStructureLeafLabel($0, language: language) == trimmed
                        || $0.localizedName(language: language) == trimmed
                        || $0.nameSv == trimmed
                        || $0.nameEn == trimmed
                }) {
                    applySelectedContext(selected)
                } else {
                    draft.contextID = nil
                }
            }
        )
    }

    private var activityTextBinding: Binding<String> {
        Binding(
            get: { draft.activityName },
            set: { newValue in
                draft.activityID = nil
                draft.activityName = newValue
            }
        )
    }

    private var activitySelectionField: some View {
        AutocompleteSelectionField(
            text: activityTextBinding,
            options: activityOptions,
            placeholder: activityFieldTitle,
            onCommit: {
                selectActivity(draft.activityName)
                requestImmediatePersist()
            },
            onSelect: {
                applySelectedActivityAndPersist($0)
            },
            updatesTextContinuously: true
        )
    }

    private var studentBinding: Binding<String> {
        Binding(
            get: {
                draft.studentName
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let matched = store.publicationAuthor(matchingPresentedName: trimmed) {
                    draft.studentName = matched.name
                } else {
                    draft.studentName = trimmed
                }
            }
        )
    }

    private var kindBinding: Binding<TeachingAssignmentKind> {
        Binding(
            get: { resolvedKind },
            set: { draft.kind = $0 }
        )
    }

    private var meritReportCategoryBinding: Binding<TeachingReportCategory> {
        Binding(
            get: { draft.reportCategory ?? inferredReportCategory(for: draft) },
            set: { draft.reportCategory = $0 }
        )
    }

    private var resolvedKind: TeachingAssignmentKind {
        draft.kind ?? inferredTeachingAssignmentKind(assignment: draft, context: currentContext)
    }

    private var currentContext: TeachingCourse? {
        guard let contextID = lockedContextID ?? draft.contextID else { return nil }
        return store.teachingCourses.first(where: { $0.id == contextID })
    }

    private var showsEmbeddedStructureFields: Bool {
        lockedContextID == nil
    }

    private var contextFieldTitle: String {
        language.text("Course / track", "Kurs / spår")
    }

    private var institutionFieldTitle: String {
        language.text("Organization", "Organisation")
    }

    private var programFieldTitle: String {
        language.text("Programme / area", "Program / område")
    }

    private var activityFieldTitle: String {
        language.text("Teaching assignment", "Undervisningsuppdrag")
    }

    private var activityFieldAccessory: some View {
        teachingManagementButton(language: language) {
            createActivityOptionFromCurrentDraft()
        }
        .help(language.text("Add teaching assignment option", "Lägg till undervisningsuppdrag"))
    }

    private var availableRoles: [TeachingAssignmentRole] {
        let storedRoles = store.teachingRoleOptions.map { TeachingAssignmentRole($0.id) }
        let merged = Array(NSOrderedSet(array: storedRoles + draft.roles)) as? [TeachingAssignmentRole] ?? (storedRoles + draft.roles)
        return merged.sorted {
            store.teachingRoleDisplayName($0, language: language)
                .localizedStandardCompare(store.teachingRoleDisplayName($1, language: language)) == .orderedAscending
        }
    }

    private var hasRestrictedActivityCandidates: Bool {
        draft.contextID != nil && activityCandidates.contains { !$0.allowedContextIDs.isEmpty }
    }

    private var activityRestrictionHint: String? {
        guard draft.contextID != nil, hasRestrictedActivityCandidates else { return nil }
        if activityCandidates.isEmpty {
            return language.text(
                "No teaching assignments are unlocked for the selected breadcrumb branch.",
                "Inga undervisningsuppdrag är upplåsta för vald breadcrumb-gren."
            )
        }
        return language.text(
            "Only teaching assignments unlocked for the selected breadcrumb branch are shown.",
            "Bara undervisningsuppdrag som är upplåsta för vald breadcrumb-gren visas."
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                TeachingPanel(
                    title: language.text("Teaching assignment details", "Undervisningsuppdragsdetaljer"),
                    titleStyle: .divider,
                    fill: .clear,
                    stroke: .clear
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        if showsEmbeddedStructureFields {
                            HStack(alignment: .top, spacing: 12) {
                                TeachingLabeledField(
                                    title: activityFieldTitle,
                                    accessory: {
                                        activityFieldAccessory
                                    }
                                ) {
                                    activitySelectionField
                                }
                                TeachingLabeledField(
                                    title: language.text("Type", "Typ"),
                                    accessory: {
                                        teachingManagementButton(language: language) {
                                            showingKindManager = true
                                        }
                                        .popover(isPresented: $showingKindManager, arrowEdge: .bottom) {
                                            TeachingAssignmentKindsPopover(store: store, language: language)
                                        }
                                    }
                                ) {
                                    teachingMenuField(
                                        selection: kindBinding,
                                        options: TeachingAssignmentKind.allCases.map { ($0.displayName(language: language), $0) },
                                        width: 240,
                                        placeholder: language.text("Type", "Typ")
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                TeachingLabeledField(title: language.text("Participant form", "Deltagarform")) {
                                    teachingMenuField(
                                        selection: participantFormBinding,
                                        options: [(language.text("Participant form", "Deltagarform"), TeachingAssignmentCategory?.none)]
                                            + TeachingAssignmentCategory.allCases.map { ($0.displayName(language: language), Optional($0)) },
                                        width: 220,
                                        placeholder: language.text("Participant form", "Deltagarform")
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                TeachingLabeledField(
                                    title: language.text("Merit report categorization", "Kategorisering för meritrapport"),
                                    accessory: {
                                        teachingManagementButton(language: language) {
                                            showingReportCategoryManager = true
                                        }
                                        .popover(isPresented: $showingReportCategoryManager, arrowEdge: .bottom) {
                                            TeachingReportCategoriesPopover(store: store, language: language)
                                        }
                                    }
                                ) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        teachingMenuField(
                                            selection: meritReportCategoryBinding,
                                            options: TeachingReportCategory.allCases.map { ($0.displayName(language: language), $0) },
                                            width: 280
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        Text(language.text("This decides which table the assignment ends up in when you export pedagogical merits.", "Detta avgör i vilken tabell uppdraget hamnar när du exporterar pedagogiska meriter."))
                                            .appTypography(.secondary)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            HStack(alignment: .top, spacing: 12) {
                                TeachingLabeledField(title: institutionFieldTitle) {
                                    AutocompleteSelectionField(
                                        text: institutionTextBinding,
                                        options: institutionOptions,
                                        placeholder: institutionFieldTitle,
                                        onCommit: {
                                            let typed = institutionTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                            selectedInstitutionFilter = typed
                                            clearIncompatibleContextSelection()
                                            requestImmediatePersist()
                                        },
                                        onSelect: { selected in
                                            selectedInstitutionFilter = selected
                                            clearIncompatibleContextSelection()
                                            requestImmediatePersist()
                                        },
                                        updatesTextContinuously: true
                                    )
                                }
                                TeachingLabeledField(title: programFieldTitle) {
                                    AutocompleteSelectionField(
                                        text: programTextBinding,
                                        options: programOptions,
                                        placeholder: programFieldTitle,
                                        onCommit: {
                                            let typed = programTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                            selectedProgramFilter = typed
                                            draft.programName = typed
                                            clearIncompatibleContextSelection()
                                            requestImmediatePersist()
                                        },
                                        onSelect: { selected in
                                            selectedProgramFilter = selected
                                            draft.programName = selected
                                            clearIncompatibleContextSelection()
                                            requestImmediatePersist()
                                        },
                                        updatesTextContinuously: true
                                    )
                                }
                                TeachingLabeledField(title: contextFieldTitle) {
                                    AutocompleteSelectionField(
                                        text: contextTextBinding,
                                        options: contextOptions,
                                        placeholder: contextFieldTitle,
                                        onCommit: {
                                            let typed = contextTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if let selected = filteredContextCourses.first(where: {
                                                teachingStructureLeafLabel($0, language: language) == typed
                                                    || $0.localizedName(language: language) == typed
                                            }) {
                                                applySelectedContext(selected)
                                            } else {
                                                draft.contextID = nil
                                            }
                                            requestImmediatePersist()
                                        },
                                        onSelect: { selected in
                                            if let course = filteredContextCourses.first(where: { teachingStructureLeafLabel($0, language: language) == selected || $0.localizedName(language: language) == selected }) {
                                                applySelectedContext(course)
                                            } else {
                                                draft.contextID = nil
                                            }
                                            requestImmediatePersist()
                                        },
                                        updatesTextContinuously: true
                                    )
                                }
                            }
                        } else {
                            HStack(alignment: .top, spacing: 12) {
                                TeachingLabeledField(
                                    title: activityFieldTitle,
                                    accessory: {
                                        activityFieldAccessory
                                    }
                                ) {
                                    activitySelectionField
                                }
                                TeachingLabeledField(
                                    title: language.text("Type", "Typ"),
                                    accessory: {
                                        teachingManagementButton(language: language) {
                                            showingKindManager = true
                                        }
                                        .popover(isPresented: $showingKindManager, arrowEdge: .bottom) {
                                            TeachingAssignmentKindsPopover(store: store, language: language)
                                        }
                                    }
                                ) {
                                    teachingMenuField(
                                        selection: kindBinding,
                                        options: TeachingAssignmentKind.allCases.map { ($0.displayName(language: language), $0) },
                                        width: 240,
                                        placeholder: language.text("Type", "Typ")
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                TeachingLabeledField(title: language.text("Participant form", "Deltagarform")) {
                                    teachingMenuField(
                                        selection: participantFormBinding,
                                        options: [(language.text("Participant form", "Deltagarform"), TeachingAssignmentCategory?.none)]
                                            + TeachingAssignmentCategory.allCases.map { ($0.displayName(language: language), Optional($0)) },
                                        width: 220,
                                        placeholder: language.text("Participant form", "Deltagarform")
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                TeachingLabeledField(
                                    title: language.text("Merit report categorization", "Kategorisering för meritrapport"),
                                    accessory: {
                                        teachingManagementButton(language: language) {
                                            showingReportCategoryManager = true
                                        }
                                        .popover(isPresented: $showingReportCategoryManager, arrowEdge: .bottom) {
                                            TeachingReportCategoriesPopover(store: store, language: language)
                                        }
                                    }
                                ) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        teachingMenuField(
                                            selection: meritReportCategoryBinding,
                                            options: TeachingReportCategory.allCases.map { ($0.displayName(language: language), $0) },
                                            width: 280
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        Text(language.text("This decides which table the assignment ends up in when you export pedagogical merits.", "Detta avgör i vilken tabell uppdraget hamnar när du exporterar pedagogiska meriter."))
                                            .appTypography(.secondary)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            TeachingLabeledField(title: language.text("Mode", "Läge")) {
                                HStack(spacing: 20) {
                                    Toggle(language.text("On-site", "Fysiskt"), isOn: onSiteModeBinding)
                                        .appCheckboxStyle()
                                    Toggle(language.text("Online", "Online"), isOn: onlineModeBinding)
                                        .appCheckboxStyle()
                                    Toggle(language.text("Hybrid", "Hybrid"), isOn: hybridModeBinding)
                                        .appCheckboxStyle()
                                }
                            }
                        }

                        TeachingLabeledField(
                            title: language.text("Role", "Roll"),
                            accessory: {
                                teachingManagementButton(language: language) {
                                    showingRoleManager = true
                                }
                                .popover(isPresented: $showingRoleManager, arrowEdge: .bottom) {
                                    TeachingRolesCatalogPopover(store: store, language: language)
                                }
                            }
                        ) {
                            TeachingCheckGrid(items: availableRoles, columns: 5) { role in
                                Binding(
                                    get: { draft.roles.contains(role) },
                                    set: { isOn in
                                        if isOn {
                                            if !draft.roles.contains(role) {
                                                draft.roles.append(role)
                                            }
                                        } else {
                                            draft.roles.removeAll { $0 == role }
                                        }
                                    }
                                )
                            } label: { role in
                                store.teachingRoleDisplayName(role, language: language)
                            }
                        }

                        if showsStudentField(for: draft) {
                            TeachingLabeledField(title: language.text("Student / doctoral student", "Student / doktorand")) {
                                AutocompleteSelectionField(
                                    text: studentBinding,
                                    options: studentOptions,
                                    placeholder: language.text("Select person", "Välj person"),
                                    onCommit: {
                                        requestImmediatePersist()
                                    },
                                    onSelect: { selected in
                                        studentBinding.wrappedValue = selected
                                        requestImmediatePersist()
                                    },
                                    updatesTextContinuously: true
                                )
                            }
                        }

                        TeachingLabeledField(title: language.text("Comment", "Kommentar")) {
                            TextField(language.text("Comment", "Kommentar"), text: binding(\.comment), axis: .vertical)
                                .appTextInputChrome()
                                .lineLimit(2...8)
                        }
                    }
                }

                TeachingPanel(
                    title: language.text("Execution", "Genomförande"),
                    titleStyle: .divider,
                    fill: .clear,
                    stroke: .clear
                ) {
                    TeachingAssignmentPeriodsEditor(
                        periods: periodsBinding,
                        language: language,
                        calendarActivityMinutesByPeriodID: calendarActivityMinutesByPeriodID
                    )
                }

                TeachingPanel(
                    title: language.text("Task list", "Uppgiftslista"),
                    titleStyle: .divider,
                    fill: .clear,
                    stroke: .clear,
                    titleActionTitle: language.text("Add task", "Lägg till uppgift"),
                    titleAction: {
                        CentralTaskListSection.addTask(store: store, linkKind: .teachingAssignment, targetID: assignment.id)
                    }
                ) {
                    CentralTaskListSection(
                        store: store,
                        linkKind: .teachingAssignment,
                        targetID: assignment.id,
                        language: language,
                        reminderOptions: ProjectTaskReminder.allCases,
                        isReadOnly: false,
                        showsAddButton: false
                    )
                }

                // Round 7: activities and tasks linked to this assignment by id.
                TeachingPanel(
                    title: language.text("Linked activities and tasks", "Kopplade aktiviteter och uppgifter"),
                    titleStyle: .divider,
                    fill: .clear,
                    stroke: .clear
                ) {
                    CalendarLinkedActivitiesAndTasksList(
                        store: store,
                        language: language,
                        scope: .teachingAssignment(assignment.id)
                    )
                }
            }
            .padding(14)
        }
        .onAppear {
            synchronizeStructureSelectionsFromDraft()
            refreshCachedOptions()
        }
        .onChange(of: draft) { _, _ in scheduleAutosave() }
        .flushPendingAutosaveOnTextEnd(requestImmediatePersist)
        .onDisappear {
            NSApp.keyWindow?.makeFirstResponder(nil)
            forcedPersistTask?.cancel()
            persist()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                requestImmediatePersist()
            }
        }
        .onChange(of: taskRows) { _, newValue in
            let normalized = Self.normalizedTasks(newValue)
            if normalized != newValue {
                taskRows = normalized
            }
            scheduleAutosave()
        }
        .onChange(of: draft.contextID) { _, _ in
            synchronizeStructureSelectionsFromDraft()
            refreshCachedOptions()
            clearIncompatibleActivityIfNeeded()
        }
        .onChange(of: selectedInstitutionFilter) { _, _ in
            refreshCachedOptions()
        }
        .onChange(of: draft.programName) { _, _ in
            refreshCachedOptions()
        }
        .onChange(of: store.organizationRowSnapshotGeneration) { _, _ in
            refreshCachedOptions()
        }
        .onChange(of: store.teachingCourses) { _, _ in
            synchronizeStructureSelectionsFromDraft()
            refreshCachedOptions()
        }
        .onChange(of: store.teachingComponents) { _, _ in
            refreshCachedOptions()
        }
        .onChange(of: store.publicationAuthorRowSnapshotGeneration) { _, _ in
            refreshCachedOptions()
        }
        .onChange(of: store.language) { _, _ in
            synchronizeStructureSelectionsFromDraft()
            refreshCachedOptions()
        }
        .onChange(of: assignment) { oldValue, newValue in
            if oldValue.id != newValue.id {
                AutosaveCoordinator.flush(&autosaveTask) {
                    autosave(baseline: oldValue)
                }
                hasPendingLocalEdits = false
                draft = newValue
                taskRows = Self.normalizedTasks(newValue.tasks)
                synchronizeStructureSelectionsFromDraft()
                refreshCachedOptions()
                return
            }
            let normalizedDraft = preparedForPersistence(from: draft)
            if hasPendingLocalEdits {
                if normalizedDraft == newValue {
                    hasPendingLocalEdits = false
                } else {
                    refreshCachedOptions()
                    return
                }
            }
            autosaveTask?.cancel()
            draft = newValue
            taskRows = Self.normalizedTasks(newValue.tasks)
            synchronizeStructureSelectionsFromDraft()
            refreshCachedOptions()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(assignmentTitle) \(summaryText)")
                    .appTypography(.pageTitle)
                Text([resolvedKind.displayName(language: language), contextName.nonEmpty, draft.studentName.nonEmpty].compactMap { $0 }.joined(separator: " · "))
                    .appTypography(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TeachingDeleteButton(
                title: language.text("Delete", "Ta bort"),
                cancelTitle: language.text("Cancel", "Avbryt")
            ) {
                store.deleteTeachingAssignment(id: assignment.id)
            }
        }
    }

    private var contextName: String {
        if let context = currentContext {
            return Array(teachingStructureBreadcrumb(context, language: language).dropFirst()).joined(separator: " › ")
        }
        return draft.programName
    }

    private var localizedActivityName: String {
        selectedActivity?.localizedName(language: language) ?? draft.activityName
    }

    private var assignmentTitle: String {
        localizedActivityName.nonEmpty
            ?? language.text("Teaching assignment", "Undervisningsuppdrag")
    }

    private var summaryText: String {
        let terms = assignmentTermCount(draft)
        let termsLabel = language.text(terms == 1 ? "1 term" : "\(terms) terms", terms == 1 ? "1 termin" : "\(terms) terminer")
        let totalHours = totalHoursText(draft)
        let hoursLabel = language.text(totalHours == "1" ? "1 hour" : "\(totalHours) hours", totalHours == "1" ? "1 timme" : "\(totalHours) timmar")
        let status = assignmentStatusText(draft, language: language).lowercased()
        if status.isEmpty {
            return "(\(termsLabel), \(hoursLabel))"
        }
        return "(\(termsLabel), \(hoursLabel), \(status))"
    }

    private var periodsBinding: Binding<[TeachingAssignmentPeriod]> {
        Binding(
            get: { normalizedPeriods(draft.periods) },
            set: {
                draft.periods = normalizedPeriods(
                    $0,
                    placeholderID: draft.periods.first(where: { $0.isEmpty })?.id
                )
            }
        )
    }

    private var calendarActivityMinutesByPeriodID: [String: Int] {
        teachingAssignmentCalendarActivityMinutesByPeriodID(
            assignmentID: draft.id,
            periods: normalizedPeriods(draft.periods),
            meetings: store.calendarMeetingRecords
        )
    }

    private func binding(_ keyPath: WritableKeyPath<TeachingAssignment, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private var onSiteModeBinding: Binding<Bool> {
        Binding(
            get: { draft.deliveryModes.contains(.onSite) || draft.deliveryMode == .onSite || draft.deliveryMode == .hybrid },
            set: { isOn in
                if isOn {
                    if !draft.deliveryModes.contains(.onSite) {
                        draft.deliveryModes.append(.onSite)
                    }
                } else {
                    draft.deliveryModes.removeAll { $0 == .onSite }
                }
                draft.deliveryMode = draft.deliveryModes.count == 1 ? draft.deliveryModes.first : nil
            }
        )
    }

    private var onlineModeBinding: Binding<Bool> {
        Binding(
            get: { draft.deliveryModes.contains(.online) || draft.deliveryMode == .online || draft.deliveryMode == .hybrid },
            set: { isOn in
                if isOn {
                    if !draft.deliveryModes.contains(.online) {
                        draft.deliveryModes.append(.online)
                    }
                } else {
                    draft.deliveryModes.removeAll { $0 == .online }
                }
                draft.deliveryMode = draft.deliveryModes.count == 1 ? draft.deliveryModes.first : nil
            }
        )
    }

    private var hybridModeBinding: Binding<Bool> {
        Binding(
            get: { draft.deliveryModes.contains(.hybrid) || draft.deliveryMode == .hybrid },
            set: { isOn in
                if isOn {
                    if !draft.deliveryModes.contains(.hybrid) {
                        draft.deliveryModes.append(.hybrid)
                    }
                } else {
                    draft.deliveryModes.removeAll { $0 == .hybrid }
                }
                draft.deliveryMode = draft.deliveryModes.count == 1 ? draft.deliveryModes.first : nil
            }
        )
    }

    private func selectActivity(_ selected: String) {
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        if let component = activityComponent(matching: trimmed) {
            draft.activityID = component.id
            draft.activityName = component.nameSv
        } else {
            draft.activityID = nil
            draft.activityName = trimmed
        }
    }

    private func applySelectedActivityAndPersist(_ selected: String) {
        selectActivity(selected)
        requestImmediatePersist()
        DispatchQueue.main.async {
            selectActivity(draft.activityName)
            requestImmediatePersist()
        }
    }

    private func activityComponent(matching rawName: String) -> TeachingComponent? {
        let normalized = PublicationDerivation.normalizedName(rawName)
        guard !normalized.isEmpty else { return nil }
        let allCandidates = activityCandidates + store.teachingComponents
        var seen = Set<String>()
        return allCandidates.first { component in
            guard seen.insert(component.id).inserted else { return false }
            return component.id == rawName
                || PublicationDerivation.normalizedName(component.localizedName(language: language)) == normalized
                || PublicationDerivation.normalizedName(component.nameSv) == normalized
                || PublicationDerivation.normalizedName(component.nameEn) == normalized
        }
    }

    private func createActivityOptionFromCurrentDraft() {
        let context = currentContext
        let institution = context?.institution.nonEmpty ?? effectiveSelectedInstitution.trimmedOrNil ?? ""
        let proposedName = draft.activityName.trimmedOrNil
            ?? language.text("New assignment", "Nytt uppdrag")
        let name = uniqueActivityOptionName(base: proposedName)
        let id = store.addTeachingComponent(institution: institution)
        guard let component = store.teachingComponents.first(where: { $0.id == id }) else { return }
        var updated = component
        updated.setLocalizedName(name, language: language)
        if updated.institution.trimmedOrNil == nil {
            updated.institution = institution
        }
        if let contextID = draft.contextID?.trimmedOrNil {
            updated.allowedContextIDs = [contextID]
        }
        updated.participantForm = draft.participantForm ?? inferredParticipantForm(for: draft)
        updated.activityTypeName = draft.activityTypeName.nonEmpty ?? inferredActivityTypeName(for: draft)
        store.saveTeachingComponent(updated)
        draft.activityID = updated.id
        draft.activityName = updated.nameSv
        refreshCachedOptions()
        requestImmediatePersist()
    }

    private func uniqueActivityOptionName(base: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? language.text("New assignment", "Nytt uppdrag")
        let existing = Set(store.teachingComponents.flatMap { component in
            [
                PublicationDerivation.normalizedName(component.nameSv),
                PublicationDerivation.normalizedName(component.nameEn),
                PublicationDerivation.normalizedName(component.localizedName(language: language))
            ]
        })
        let normalizedBase = PublicationDerivation.normalizedName(trimmedBase)
        guard existing.contains(normalizedBase) else { return trimmedBase }
        var index = 2
        while true {
            let candidate = "\(trimmedBase) \(index)"
            if !existing.contains(PublicationDerivation.normalizedName(candidate)) {
                return candidate
            }
            index += 1
        }
    }

    private func applySelectedContext(_ course: TeachingCourse) {
        draft.contextID = course.id
        draft.programName = course.localizedProgram(language: language)
        selectedInstitutionFilter = store.teachingInstitutionKey(for: course)
        selectedProgramFilter = course.localizedProgram(language: language)
    }

    private func clearIncompatibleContextSelection() {
        guard let context = currentContext else { return }
        let matchesInstitution = selectedInstitutionFilter.trimmedOrNil == nil || store.teachingInstitutionKey(for: context) == selectedInstitutionFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchesProgram = selectedProgramFilter.trimmedOrNil == nil || context.localizedProgram(language: language) == selectedProgramFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matchesInstitution && matchesProgram else {
            draft.contextID = nil
            draft.activityID = nil
            draft.activityName = ""
            return
        }
    }

    private func persist() {
        AutosaveCoordinator.flush(&autosaveTask) {
            let normalized = preparedForPersistence(from: draft)
            // Nothing to save means nothing is pending either; a flag left
            // on made the editor ignore later outside changes and write the
            // old text back when it was closed.
            guard normalized != assignment else { hasPendingLocalEdits = false; return }
            store.saveTeachingAssignment(normalized)
            hasPendingLocalEdits = false
        }
    }

    private func autosave() {
        autosave(baseline: assignment)
    }

    private func autosave(baseline: TeachingAssignment) {
        let normalized = preparedForPersistence(from: draft)
        guard normalized != baseline else { hasPendingLocalEdits = false; return }
        store.autosaveTeachingAssignment(normalized)
        hasPendingLocalEdits = false
    }

    private func scheduleAutosave() {
        hasPendingLocalEdits = true
        AutosaveCoordinator.schedule(&autosaveTask, after: 0.55) { autosave() }
    }

    private func requestImmediatePersist() {
        AutosaveCoordinator.requestImmediate(&forcedPersistTask, after: 0.05) {
            persist()
        }
    }

    private func totalHoursText(_ assignment: TeachingAssignment) -> String {
        assignmentTotalHoursText(assignment)
    }

    private static func normalizedTasks(_ tasks: [PublicationTaskItem]) -> [PublicationTaskItem] {
        normalizedPublicationTaskItems(tasks)
    }

    private func refreshCachedOptions() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let organizationNames = store.organizations.map {
            language == .swedish
                ? ($0.nameSv.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? $0.nameEn)
                : ($0.nameEn.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? $0.nameSv)
        }
        let teachingCourses = store.teachingCourses
        let teachingComponents = store.teachingComponents
        let courseInstitutions = teachingCourses.map { store.teachingInstitutionKey(for: $0) }
        let componentInstitutions = teachingComponents.map { store.teachingInstitutionKey(for: $0) }
        let combinedInstitutions = organizationNames + courseInstitutions + componentInstitutions
        cachedInstitutionOptions = Set(combinedInstitutions)
            .compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        let selectedInstitution = effectiveSelectedInstitution.trimmedOrNil
        let institutionFilteredCourses = selectedInstitution == nil
            ? teachingCourses
            : teachingCourses.filter { store.teachingInstitutionKey(for: $0) == selectedInstitution }
        cachedProgramOptions = Set(institutionFilteredCourses.map { $0.localizedProgram(language: language) })
            .compactMap { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).nonEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        let selectedProgram = effectiveSelectedProgram.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedFilteredContextCourses = institutionFilteredCourses
            .filter { course in
                let courseProgram = course.localizedProgram(language: language).trimmingCharacters(in: .whitespacesAndNewlines)
                return selectedProgram.isEmpty
                    || courseProgram == selectedProgram
                    || courseProgram.localizedCaseInsensitiveContains(selectedProgram)
            }
            .sorted {
                teachingStructureLeafLabel($0, language: language).localizedStandardCompare(teachingStructureLeafLabel($1, language: language)) == .orderedAscending
            }

        cachedContextOptions = cachedFilteredContextCourses
            .map { teachingStructureLeafLabel($0, language: language) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        cachedActivityCandidates = compatibleActivityCandidates(for: draft, within: teachingCourses, components: teachingComponents)
        cachedActivityOptions = Array(
            Set(
                cachedActivityCandidates.map { $0.localizedName(language: language) }
                + defaultTeachingAssignmentActivityNames(language: language)
            )
        )
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        cachedStudentOptions = Array(Set(
            store.publicationAuthors.map(\.name)
                + store.teachingAssignments.compactMap(\.studentName.nonEmpty)
        ))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        if duration > 12 {
            store.appendPerformanceDiagnostic(
                String(
                    format: "teaching-options-refresh assignment=%@ total_ms=%.2f contexts=%ld activities=%ld students=%ld",
                    assignment.id,
                    duration,
                    cachedContextOptions.count,
                    cachedActivityOptions.count,
                    cachedStudentOptions.count
                )
            )
        }
    }

    private func compatibleActivityCandidates(
        for assignment: TeachingAssignment,
        within teachingCourses: [TeachingCourse],
        components teachingComponents: [TeachingComponent]
    ) -> [TeachingComponent] {
        let institutionFiltered: [TeachingComponent]
        if let contextID = assignment.contextID,
           let institution = teachingCourses.first(where: { $0.id == contextID }).map({ store.teachingInstitutionKey(for: $0) })?.nonEmpty {
            institutionFiltered = teachingComponents.filter { store.teachingInstitutionKey(for: $0) == institution }
        } else if let institution = effectiveSelectedInstitution.trimmedOrNil {
            institutionFiltered = teachingComponents.filter { store.teachingInstitutionKey(for: $0) == institution }
        } else {
            institutionFiltered = teachingComponents
        }

        guard let contextID = assignment.contextID else {
            return institutionFiltered
        }

        return institutionFiltered.filter { component in
            component.allowedContextIDs.isEmpty || component.allowedContextIDs.contains(contextID)
        }
    }

    private func clearIncompatibleActivityIfNeeded() {
        guard hasRestrictedActivityCandidates else { return }
        guard draft.activityID != nil || draft.activityName.trimmedOrNil != nil else { return }
        let candidates = activityCandidates
        let normalizedCurrent = PublicationDerivation.normalizedName(draft.activityName)
        let isCompatible = candidates.contains { component in
            component.id == draft.activityID
                || PublicationDerivation.normalizedName(component.nameSv) == normalizedCurrent
                || PublicationDerivation.normalizedName(component.nameEn) == normalizedCurrent
        }
        guard !isCompatible else { return }
        if draft.activityID != nil {
            draft.activityID = nil
        }
    }

    private func synchronizeStructureSelectionsFromDraft() {
        if let context = currentContext {
            selectedInstitutionFilter = store.teachingInstitutionKey(for: context)
            selectedProgramFilter = context.localizedProgram(language: language)
        } else {
            if selectedInstitutionFilter.trimmedOrNil == nil {
                selectedInstitutionFilter = ""
            }
            if selectedProgramFilter.trimmedOrNil == nil {
                selectedProgramFilter = draft.programName
            }
        }
    }

    private func normalizedPeriods(_ periods: [TeachingAssignmentPeriod], placeholderID: String? = nil) -> [TeachingAssignmentPeriod] {
        let retainedPlaceholderID = periods.first(where: { $0.isEmpty })?.id ?? placeholderID ?? UUID().uuidString
        return periods.filter { !$0.isEmpty } + [TeachingAssignmentPeriod(id: retainedPlaceholderID)]
    }

    private func preparedForPersistence(from draft: TeachingAssignment) -> TeachingAssignment {
        var normalized = draft
        normalized.kind = resolvedKind
        normalized.tasks = taskRows.filter { !$0.isEmpty }
        if normalized.programName.nonEmpty == nil {
            normalized.programName = currentContext?.localizedProgram(language: language) ?? ""
        }
        if let selectedActivity = activityComponent(for: normalized) {
            normalized.activityID = selectedActivity.id
            normalized.activityName = selectedActivity.nameSv
            if normalized.participantForm == nil {
                normalized.participantForm = selectedActivity.participantForm ?? inferredParticipantForm(for: normalized)
            }
            if normalized.activityTypeName.nonEmpty == nil {
                normalized.activityTypeName = selectedActivity.activityTypeName.nonEmpty ?? inferredActivityTypeName(for: normalized)
            }
        } else {
            if normalized.participantForm == nil {
                normalized.participantForm = inferredParticipantForm(for: normalized)
            }
            if normalized.activityTypeName.nonEmpty == nil {
                normalized.activityTypeName = inferredActivityTypeName(for: normalized)
            }
        }
        normalized.reportCategory = normalized.reportCategory ?? inferredReportCategory(for: normalized)
        normalized.normalize()
        return normalized
    }

    private func effectiveAssignmentCategory(for assignment: TeachingAssignment) -> TeachingAssignmentCategory? {
        if let explicit = selectedActivityCategory(for: assignment) {
            return explicit
        }
        return assignment.participantForm ?? legacyActivityTypeCategory(for: assignment) ?? inferredParticipantForm(for: assignment)
    }

    private func effectiveActivityTypeName(for assignment: TeachingAssignment) -> String {
        if let fromActivity = selectedActivityType(for: assignment) {
            return fromActivity
        }
        if let explicit = assignment.activityTypeName.nonEmpty {
            return explicit
        }
        return inferredActivityTypeName(for: assignment)
    }

    private func effectiveActivityTypeLabel(for assignment: TeachingAssignment) -> String {
        let name = effectiveActivityTypeName(for: assignment)
        guard let nonEmpty = name.nonEmpty else { return "" }
        if let stored = store.teachingFormats.first(where: { $0.nameSv == nonEmpty || $0.nameEn == nonEmpty || $0.name == nonEmpty }) {
            return stored.localizedName(language: language)
        }
        return localizedTeachingFormatName(nonEmpty, language: language)
    }

    private func selectedActivityType(for assignment: TeachingAssignment) -> String? {
        activityComponent(for: assignment)?.activityTypeName.nonEmpty
    }

    private func selectedActivityCategory(for assignment: TeachingAssignment) -> TeachingAssignmentCategory? {
        assignment.participantForm ?? activityComponent(for: assignment)?.participantForm
    }

    private func activityComponent(for assignment: TeachingAssignment) -> TeachingComponent? {
        if let activityID = assignment.activityID,
           let matched = activityCandidates.first(where: { $0.id == activityID }) ?? store.teachingComponents.first(where: { $0.id == activityID }) {
            return matched
        }
        return activityCandidates.first(where: { $0.nameSv == assignment.activityName || $0.nameEn == assignment.activityName })
            ?? store.teachingComponents.first(where: { $0.nameSv == assignment.activityName || $0.nameEn == assignment.activityName })
    }

    private func legacyActivityTypeCategory(for assignment: TeachingAssignment) -> TeachingAssignmentCategory? {
        if let explicit = teachingFormatCategory(for: assignment.activityTypeName, formats: store.teachingFormats) {
            return explicit
        }
        return nil
    }

    private func inferredParticipantForm(for assignment: TeachingAssignment) -> TeachingAssignmentCategory {
        if let selected = selectedActivityCategory(for: assignment) {
            return selected
        }
        switch assignment.kind ?? resolvedKind {
        case .development:
            return .notTeachingWork
        case .supervision:
            return .individual
        case .clinical:
            return .group
        case .teaching:
            return assignment.studentName.nonEmpty == nil ? .group : .individual
        }
    }

    private func inferredActivityTypeName(for assignment: TeachingAssignment) -> String {
        if let selected = selectedActivityType(for: assignment) {
            return selected
        }

        let kind = assignment.kind ?? resolvedKind
        switch kind {
        case .development:
            return "Utvecklingsarbete"
        case .supervision:
            return "Handledning"
        case .clinical:
            if assignment.roles.contains(.examiner) {
                return "Examination"
            }
            if assignment.roles.contains(.lecturer) || assignment.roles.contains(.invitedSpeaker) {
                return "Föreläsning"
            }
            if assignment.roles.contains(.seminarLeader) {
                return "Seminarium"
            }
            return "Handledning"
        case .teaching:
            if assignment.roles.contains(.examiner) {
                return "Examination"
            }
            if assignment.roles.contains(.lecturer) || assignment.roles.contains(.invitedSpeaker) {
                return "Föreläsning"
            }
            if assignment.roles.contains(.seminarLeader) {
                return "Seminarium"
            }
            if assignment.studentName.nonEmpty != nil || assignment.roles.contains(.supervisor) {
                return "Handledning"
            }
            return "Undervisning"
        }
    }

    private func showsStudentField(for assignment: TeachingAssignment) -> Bool {
        let category = effectiveAssignmentCategory(for: assignment)
        return category == .individual || category == .groupAndIndividual
    }

    private func inferredReportCategory(for assignment: TeachingAssignment) -> TeachingReportCategory {
        let activityType = effectiveActivityTypeName(for: assignment).lowercased()
        let activity = assignment.activityName.lowercased()
        let context = store.teachingCourses.first(where: { $0.id == assignment.contextID })
        let contextName = (context?.localizedName(language: language) ?? "").lowercased()
        let contextType = context?.contextType
        let kind = assignment.kind ?? inferredTeachingAssignmentKind(assignment: assignment, context: context)

        switch kind {
        case .development:
            return .courseAdministration
        case .clinical:
            return .groupTeaching
        case .supervision:
            if assignment.roles.contains(.principalSupervisor) && contextType == .doctoralEducation {
                return .doctoralPrincipalSupervision
            }
            if assignment.roles.contains(.assistantSupervisor) && contextType == .doctoralEducation {
                return .doctoralAssistantSupervision
            }
            return .thesisSupervision
        case .teaching:
            break
        }

        if contextType == .courseAdministration || activityType.contains("utvecklingsarbete") || activity.contains("utvecklingsarbete") {
            return .courseAdministration
        }
        if assignment.roles.contains(.principalSupervisor) && (contextType == .doctoralEducation || activityType.contains("doktorand")) {
            return .doctoralPrincipalSupervision
        }
        if assignment.roles.contains(.assistantSupervisor) && (contextType == .doctoralEducation || activityType.contains("doktorand")) {
            return .doctoralAssistantSupervision
        }
        if contextType == .doctoralEducation && (assignment.roles.contains(.lecturer) || assignment.roles.contains(.invitedSpeaker) || assignment.roles.contains(.seminarLeader) || activityType.contains("föreläs") || activityType.contains("semin")) {
            return .doctoralCourseTeaching
        }
        if activity.contains("examensarbete") || contextName.contains("examensarbete") || contextName.contains("forskar-at-projekt") || contextName.contains("forskningslinjen") {
            return .thesisSupervision
        }
        if assignment.roles.contains(.lecturer) || activityType.contains("föreläs") {
            return .lecture
        }
        if assignment.roles.contains(.seminarLeader) || assignment.roles.contains(.supervisor) || assignment.roles.contains(.examiner) || activityType.contains("semin") || activityType.contains("handled") || activityType.contains("examin") {
            return .groupTeaching
        }
        return .otherPedagogicalWork
    }
}

private struct TeachingAssignmentPeriodsEditor: View {
    @Binding var periods: [TeachingAssignmentPeriod]
    let language: AppLanguage
    var calendarActivityMinutesByPeriodID: [String: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(periods.indices), id: \.self) { index in
                HStack(alignment: .center, spacing: 10) {
                    TeachingDateField(
                        title: index == 0 ? language.text("From", "Från") : nil,
                        text: Binding(
                            get: { periods[index].from },
                            set: { newValue in
                                let previousFrom = periods[index].from
                                periods[index].from = newValue
                                if let shiftedTo = shiftedDateRangeEnd(
                                    previousStart: previousFrom,
                                    newStart: newValue,
                                    currentEnd: periods[index].to
                                ) {
                                    periods[index].to = shiftedTo
                                }
                            }
                        ),
                        showsTitle: index == 0,
                        language: language
                    )
                    TeachingDateField(
                        title: index == 0 ? language.text("To", "Till") : nil,
                        text: Binding(
                            get: { periods[index].to },
                            set: { periods[index].to = $0 }
                        ),
                        showsTitle: index == 0,
                        language: language
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        if index == 0 {
                            AppTableHeaderText(text: language.text("Hours per term", "Timmar per termin"))
                        }
                        TextField(
                            language.text("Hours per term", "Timmar per termin"),
                            text: Binding(
                                get: { periods[index].hoursPerTerm },
                                set: { periods[index].hoursPerTerm = $0 }
                            )
                        )
                        .appTextInputChrome()
                    }
                    .frame(width: 150, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        if index == 0 {
                            AppTableHeaderText(text: language.text("Retendo", "Retendo"))
                        }
                        Toggle(
                            language.text("Confirmed in Retendo", "Bekräftad i Retendo"),
                            isOn: Binding(
                                get: { periods[index].confirmedInRetendo },
                                set: { periods[index].confirmedInRetendo = $0 }
                            )
                        )
                            .appCheckboxStyle()
                    }
                    .frame(width: 180, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        if index == 0 {
                            AppTableHeaderText(text: language.text("Activity hours", "Aktivitetstimmar"))
                        }
                        Text(calendarActivityHoursText(for: periods[index]))
                            .appTypography(.body)
                            .foregroundStyle(calendarActivityMinutesByPeriodID[periods[index].id, default: 0] > 0 ? AppPalette.appText : .secondary)
                            .frame(height: AppPalette.fieldMinHeight, alignment: .center)
                    }
                    .frame(width: 132, alignment: .leading)
                }
            }
        }
        .onChange(of: periods) { oldValue, newValue in
            let normalized = normalizedPeriods(newValue, placeholderID: oldValue.first(where: { $0.isEmpty })?.id)
            if normalized != newValue {
                periods = normalized
            }
        }
    }

    private func normalizedPeriods(_ periods: [TeachingAssignmentPeriod], placeholderID: String? = nil) -> [TeachingAssignmentPeriod] {
        let retainedPlaceholderID = periods.first(where: { $0.isEmpty })?.id ?? placeholderID ?? UUID().uuidString
        return periods
            .map {
                var period = $0
                period.normalize()
                return period
            }
            .filter { !$0.isEmpty }
            + [TeachingAssignmentPeriod(id: retainedPlaceholderID)]
    }

    private func calendarActivityHoursText(for period: TeachingAssignmentPeriod) -> String {
        guard !period.isEmpty,
              let minutes = calendarActivityMinutesByPeriodID[period.id],
              minutes > 0 else {
            return "-"
        }
        let hours = Double(minutes) / 60.0
        if hours.rounded() == hours {
            return "\(Int(hours)) h"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = language == .english ? "." : ","
        return "\(formatter.string(from: NSNumber(value: hours)) ?? String(format: "%.1f", hours)) h"
    }
}

private struct TeachingAssignmentDirectoryCell: View {
    let text: String
    var alignment: Alignment = .leading

    var body: some View {
        Text(text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

private struct TeachingCheckGrid<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let columns: Int
    let binding: (Item) -> Binding<Bool>
    let label: (Item) -> String

    init(
        items: [Item],
        columns: Int,
        binding: @escaping (Item) -> Binding<Bool>,
        label: @escaping (Item) -> String
    ) {
        self.items = items
        self.columns = columns
        self.binding = binding
        self.label = label
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 160), spacing: 10), count: columns), alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                Toggle(label(item), isOn: binding(item))
                    .appCheckboxStyle()
            }
        }
    }
}

private typealias TeachingPanel<Content: View> = AppWorkspacePanel<Content>
private typealias TeachingLabeledField<Content: View, Accessory: View> = AppLabeledField<Content, Accessory>

@MainActor
private func teachingManagementButton(language: AppLanguage, action: @escaping () -> Void) -> some View {
    AppIconAddButton(title: language.text("Add", "Lägg till"), action: action)
}

private struct TeachingAssignmentKindsPopover: View {
    @ObservedObject var store: GrantDataStore
    let language: AppLanguage

    @State private var swedishValues: [String: String] = [:]
    @State private var englishValues: [String: String] = [:]

    private var kinds: [TeachingAssignmentKind] {
        TeachingAssignmentKind.allCases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("Assignment types", "Uppdragstyper"))
                .appTypography(.panelTitle)

            Text(language.text("These are the four base types the app uses internally. You can rename them here without going to settings.", "Det här är appens fyra grundtyper. Du kan byta namn på dem här utan att gå till inställningar."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            ForEach(kinds) { kind in
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.displayName(language: language))
                        .appTypography(.fieldLabel)
                    HStack(spacing: 10) {
                        AppCommitTextField(
                            placeholder: language.text("Swedish", "Svenska"),
                            text: Binding(
                                get: { swedishValues[kind.translationKey] ?? kind.defaultSwedishName },
                                set: { newValue in
                                    swedishValues[kind.translationKey] = newValue
                                    persist()
                                }
                            )
                        )

                        AppCommitTextField(
                            placeholder: language.text("English", "Engelska"),
                            text: Binding(
                                get: { englishValues[kind.translationKey] ?? kind.defaultEnglishName },
                                set: { newValue in
                                    englishValues[kind.translationKey] = newValue
                                    persist()
                                }
                            )
                        )
                    }
                }
            }

            HStack {
                Spacer()
                AppResetButton(title: language.text("Reset", "Återställ")) {
                    for kind in kinds {
                        swedishValues[kind.translationKey] = kind.defaultSwedishName
                        englishValues[kind.translationKey] = kind.defaultEnglishName
                    }
                    persist()
                }
            }
        }
        .padding(14)
        .frame(width: 560)
        .onAppear(perform: load)
    }

    private func load() {
        for kind in kinds {
            swedishValues[kind.translationKey] = fixedDropdownText(
                kind.translationKey,
                language: .swedish,
                english: kind.defaultEnglishName,
                swedish: kind.defaultSwedishName
            )
            englishValues[kind.translationKey] = fixedDropdownText(
                kind.translationKey,
                language: .english,
                english: kind.defaultEnglishName,
                swedish: kind.defaultSwedishName
            )
        }
    }

    private func persist() {
        var swedish = Dictionary(firstWinsKeysWithValues: editableDropdownTranslationDefinitions.map { definition in
            (definition.key, store.dropdownTranslationText(for: definition, language: .swedish))
        })
        var english = Dictionary(firstWinsKeysWithValues: editableDropdownTranslationDefinitions.map { definition in
            (definition.key, store.dropdownTranslationText(for: definition, language: .english))
        })

        for kind in kinds {
            swedish[kind.translationKey] = swedishValues[kind.translationKey] ?? kind.defaultSwedishName
            english[kind.translationKey] = englishValues[kind.translationKey] ?? kind.defaultEnglishName
        }

        store.autosaveDropdownTranslationOverrides(swedish: swedish, english: english)
    }
}

private struct TeachingReportCategoriesPopover: View {
    @ObservedObject var store: GrantDataStore
    let language: AppLanguage

    @State private var swedishValues: [String: String] = [:]
    @State private var englishValues: [String: String] = [:]

    private var categories: [TeachingReportCategory] {
        TeachingReportCategory.allCases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("Merit report categories", "Kategorier för meritrapport"))
                .appTypography(.panelTitle)

            Text(language.text("These are the sections used by the pedagogical merits template. Rename them here if you want different wording in the app and in exports.", "Detta är sektionerna som används i mallen för pedagogiska meriter. Byt namn här om du vill ha annan formulering i appen och i exporter."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            ForEach(categories) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.displayName(language: language))
                        .appTypography(.fieldLabel)
                    HStack(spacing: 10) {
                        AppCommitTextField(
                            placeholder: language.text("Swedish", "Svenska"),
                            text: Binding(
                                get: { swedishValues[category.translationKey] ?? category.defaultSwedishName },
                                set: { newValue in
                                    swedishValues[category.translationKey] = newValue
                                    persist()
                                }
                            )
                        )

                        AppCommitTextField(
                            placeholder: language.text("English", "Engelska"),
                            text: Binding(
                                get: { englishValues[category.translationKey] ?? category.defaultEnglishName },
                                set: { newValue in
                                    englishValues[category.translationKey] = newValue
                                    persist()
                                }
                            )
                        )
                    }
                }
            }

            HStack {
                Spacer()
                AppResetButton(title: language.text("Reset", "Återställ")) {
                    for category in categories {
                        swedishValues[category.translationKey] = category.defaultSwedishName
                        englishValues[category.translationKey] = category.defaultEnglishName
                    }
                    persist()
                }
            }
        }
        .padding(14)
        .frame(width: 620)
        .onAppear(perform: load)
    }

    private func load() {
        for category in categories {
            swedishValues[category.translationKey] = fixedDropdownText(
                category.translationKey,
                language: .swedish,
                english: category.defaultEnglishName,
                swedish: category.defaultSwedishName
            )
            englishValues[category.translationKey] = fixedDropdownText(
                category.translationKey,
                language: .english,
                english: category.defaultEnglishName,
                swedish: category.defaultSwedishName
            )
        }
    }

    private func persist() {
        var swedish = Dictionary(firstWinsKeysWithValues: editableDropdownTranslationDefinitions.map { definition in
            (definition.key, store.dropdownTranslationText(for: definition, language: .swedish))
        })
        var english = Dictionary(firstWinsKeysWithValues: editableDropdownTranslationDefinitions.map { definition in
            (definition.key, store.dropdownTranslationText(for: definition, language: .english))
        })

        for category in categories {
            swedish[category.translationKey] = swedishValues[category.translationKey] ?? category.defaultSwedishName
            english[category.translationKey] = englishValues[category.translationKey] ?? category.defaultEnglishName
        }

        store.autosaveDropdownTranslationOverrides(swedish: swedish, english: english)
    }
}

private struct TeachingRolesCatalogPopover: View {
    @ObservedObject var store: GrantDataStore
    let language: AppLanguage

    @State private var options: [TeachingRoleOption] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("Roles", "Roller"))
                .appTypography(.panelTitle)

            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                HStack(spacing: 10) {
                    AppCommitTextField(
                        placeholder: language.text("Swedish", "Svenska"),
                        text: Binding(
                            get: {
                                guard options.indices.contains(index) else { return "" }
                                return options[index].nameSv
                            },
                            set: { newValue in
                                guard options.indices.contains(index) else { return }
                                options[index].nameSv = newValue
                                persist()
                            }
                        )
                    )

                    AppCommitTextField(
                        placeholder: language.text("English", "Engelska"),
                        text: Binding(
                            get: {
                                guard options.indices.contains(index) else { return "" }
                                return options[index].nameEn
                            },
                            set: { newValue in
                                guard options.indices.contains(index) else { return }
                                options[index].nameEn = newValue
                                persist()
                            }
                        )
                    )

                    if !option.isEmpty {
                        AppInlineDeleteButton(
                            title: language.text("Delete option", "Ta bort alternativ")
                        ) {
                            guard options.indices.contains(index) else { return }
                            options.remove(at: index)
                            persist()
                        }
                    } else {
                        Color.clear.frame(width: 18, height: 18)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 560)
        .onAppear(perform: load)
    }

    private func load() {
        options = store.teachingRoleOptions
        ensureTrailingEmptyRow()
    }

    private func ensureTrailingEmptyRow() {
        if options.last?.isEmpty != true {
            options.append(TeachingRoleOption())
        }
    }

    private func persist() {
        let normalized = options.filter { !$0.isEmpty }
        store.saveTeachingRoleOptions(normalized)
        options = store.teachingRoleOptions
        ensureTrailingEmptyRow()
    }
}




private struct TeachingStructureBranchDetailView: View {
    @ObservedObject var store: GrantDataStore
    let course: TeachingCourse
    let language: AppLanguage
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: TeachingCourse
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var hasPendingLocalEdits = false

    init(store: GrantDataStore, course: TeachingCourse, language: AppLanguage) {
        self.store = store
        self.course = course
        self.language = language
        _draft = State(initialValue: course)
    }

    private var institutionOptions: [String] {
        TeachingAutocompleteIndex.deduplicatedValues(
            store.organizations.map(\.nameSv)
            + store.teachingCourses.map(\.institution)
            + store.teachingComponents.map(\.institution)
        )
    }

    private var programOptions: [String] {
        TeachingAutocompleteIndex.programOptions(
            courses: store.teachingCourses,
            language: language,
            institution: draft.institution
        )
    }

    private var courseNameOptions: [String] {
        TeachingAutocompleteIndex.courseNameOptions(
            courses: store.teachingCourses,
            language: language,
            institution: draft.institution,
            program: localizedProgramBinding.wrappedValue,
            scope: .leafOnly
        )
    }

    private var termOptions: [String] {
        TeachingAutocompleteIndex.termOptions(
            courses: store.teachingCourses,
            language: language,
            institution: draft.institution,
            program: localizedProgramBinding.wrappedValue,
            scope: .leafOnly
        )
    }

    private var localizedNameBinding: Binding<String> {
        Binding(
            get: { language == .swedish ? draft.nameSv : draft.nameEn },
            set: { draft.setLocalizedName($0, language: language) }
        )
    }

    private var localizedProgramBinding: Binding<String> {
        Binding(
            get: { language == .swedish ? draft.programSv : draft.programEn },
            set: { draft.setLocalizedProgram($0, language: language) }
        )
    }

    private var localizedTermBinding: Binding<String> {
        Binding(
            get: { language == .swedish ? draft.termSv : draft.termEn },
            set: { draft.setLocalizedTerm($0, language: language) }
        )
    }

    private var titleText: String {
        switch draft.contextType {
        case .programTrack:
            return language.text("Programme / area details", "Program-/områdesdetaljer")
        default:
            return language.text("Course / track details", "Kurs-/spårdetaljer")
        }
    }

    private var showsLeafFields: Bool {
        draft.contextType != .programTrack
    }

    private var canDelete: Bool {
        store.teachingCourses.contains(where: { $0.id == draft.id })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(titleText)
                            .appTypography(.pageTitle)
                    }
                    Spacer()
                    if canDelete {
                        TeachingDeleteButton(
                            title: language.text("Delete", "Ta bort"),
                            cancelTitle: language.text("Cancel", "Avbryt")
                        ) {
                            store.deleteTeachingCourse(id: draft.id)
                        }
                    }
                }

                TeachingPanel(title: language.text("Branch details", "Grendetaljer"), clearBackgroundInDarkNew: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        if showsLeafFields {
                            HStack(alignment: .top, spacing: 12) {
                                TeachingLabeledField(title: language.text("Organization", "Organisation")) {
                                    AutocompleteSelectionField(
                                        text: Binding(
                                            get: { draft.institution },
                                            set: { draft.institution = $0 }
                                        ),
                                        options: institutionOptions,
                                        placeholder: language.text("Organization", "Organisation"),
                                        onCommit: { requestImmediatePersist() },
                                        onSelect: {
                                            draft.institution = $0
                                            requestImmediatePersist()
                                        },
                                        updatesTextContinuously: true
                                    )
                                }
                                TeachingLabeledField(title: language.text("Programme / area", "Program / område")) {
                                    AutocompleteSelectionField(
                                        text: localizedProgramBinding,
                                        options: programOptions,
                                        placeholder: language.text("Programme / area", "Program / område"),
                                        onCommit: { requestImmediatePersist() },
                                        onSelect: { _ in requestImmediatePersist() },
                                        updatesTextContinuously: true
                                    )
                                }
                            }
                        } else {
                            TeachingLabeledField(title: language.text("Programme / area", "Program / område")) {
                                AutocompleteSelectionField(
                                    text: localizedProgramBinding,
                                    options: programOptions,
                                    placeholder: language.text("Programme / area", "Program / område"),
                                    onCommit: { requestImmediatePersist() },
                                    onSelect: { _ in requestImmediatePersist() },
                                    updatesTextContinuously: true
                                )
                            }
                        }

                        // F4: how long the row itself applies. Empty = still valid.
                        HStack(alignment: .top, spacing: 12) {
                            TeachingLabeledField(title: language.text("Valid from", "Giltig från")) {
                                TextField(language.text("Valid from", "Giltig från"), text: Binding(
                                    get: { draft.validFrom },
                                    set: { draft.validFrom = $0 }
                                ))
                                .appTextInputChrome()
                                .frame(width: 140)
                            }
                            TeachingLabeledField(title: language.text("Valid to", "Giltig till")) {
                                TextField(language.text("Valid to", "Giltig till"), text: Binding(
                                    get: { draft.validTo },
                                    set: { draft.validTo = $0 }
                                ))
                                .appTextInputChrome()
                                .frame(width: 140)
                            }
                            if !showsLeafFields {
                                // F5: the level applies to programme rows too.
                                TeachingLabeledField(title: language.text("Level", "Nivå")) {
                                    teachingMenuField(
                                        selection: Binding<TeachingCourseLevel?>(
                                            get: { draft.level },
                                            set: { draft.level = $0 }
                                        ),
                                        options: [(language.text("Level", "Nivå"), TeachingCourseLevel?.none)]
                                            + TeachingCourseLevel.allCases.map { ($0.displayName(language: language), Optional($0)) },
                                        width: 180,
                                        placeholder: language.text("Level", "Nivå")
                                    )
                                }
                            }
                            Spacer()
                        }

                        if showsLeafFields {
                            HStack(alignment: .top, spacing: 12) {
                                TeachingLabeledField(title: language.text("Course / track", "Kurs / spår")) {
                                    AutocompleteSelectionField(
                                        text: localizedNameBinding,
                                        options: courseNameOptions,
                                        placeholder: language.text("Course / track", "Kurs / spår"),
                                        onCommit: { requestImmediatePersist() },
                                        onSelect: { _ in requestImmediatePersist() },
                                        updatesTextContinuously: true
                                    )
                                }
                                TeachingLabeledField(title: language.text("Semester", "Termin")) {
                                    AutocompleteSelectionField(
                                        text: localizedTermBinding,
                                        options: termOptions,
                                        placeholder: language.text("Semester", "Termin"),
                                        onCommit: { requestImmediatePersist() },
                                        onSelect: { _ in requestImmediatePersist() },
                                        updatesTextContinuously: true
                                    )
                                }
                            }

                            HStack(alignment: .top, spacing: 12) {
                                TeachingLabeledField(title: language.text("Course code", "Kurskod")) {
                                    // F7: one row per code, each with its validity.
                                    TeachingCourseCodeRows(
                                        entries: Binding(
                                            get: {
                                                if draft.courseCodes.isEmpty, !draft.courseCode.isEmpty {
                                                    return [TeachingCourseCodeEntry(id: draft.id, code: draft.courseCode)]
                                                }
                                                return draft.courseCodes
                                            },
                                            set: { rows in
                                                draft.courseCodes = rows
                                                draft.courseCode = rows.first(where: { $0.validTo.trimmedOrNil == nil })?.code
                                                    ?? rows.last?.code
                                                    ?? ""
                                            }
                                        ),
                                        language: language,
                                        onCommit: { requestImmediatePersist() }
                                    )
                                }
                                TeachingLabeledField(title: language.text("Level", "Nivå")) {
                                    teachingMenuField(
                                        selection: Binding<TeachingCourseLevel?>(
                                            get: { draft.level },
                                            set: { draft.level = $0 }
                                        ),
                                        options: [(language.text("Level", "Nivå"), TeachingCourseLevel?.none)]
                                            + TeachingCourseLevel.allCases.map { ($0.displayName(language: language), Optional($0)) },
                                        width: 180,
                                        placeholder: language.text("Level", "Nivå")
                                    )
                                }
                                TeachingLabeledField(title: language.text("Language", "Språk")) {
                                    teachingMenuField(
                                        selection: Binding(
                                            get: { draft.teachingLanguage },
                                            set: { draft.teachingLanguage = $0 }
                                        ),
                                        options: [
                                            (language.text("Language", "Språk"), ""),
                                            (fixedDropdownText("teachingLanguage.swedish", language: language, english: "Swedish", swedish: "svenska"), "sv"),
                                            (fixedDropdownText("teachingLanguage.english", language: language, english: "English", swedish: "engelska"), "en")
                                        ],
                                        width: 180,
                                        placeholder: language.text("Language", "Språk")
                                    )
                                }
                                TeachingLabeledField(title: language.text("Credits", "Hp")) {
                                    TextField(language.text("Credits", "Hp"), text: Binding(
                                        get: { draft.credits },
                                        set: { draft.credits = $0 }
                                    ))
                                    .appTextInputChrome()
                                }
                            }
                        }

                        // Round 7 (user decision): clinical teaching is a checkbox
                        // on the course instead of a word in the organization name.
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(
                                language.text("Clinical teaching", "Klinisk undervisning"),
                                isOn: Binding(
                                    get: { draft.isClinicalTeaching },
                                    set: {
                                        draft.isClinicalTeaching = $0
                                        requestImmediatePersist()
                                    }
                                )
                            )
                            .appCheckboxStyle()
                            Text(language.text(
                                "When the course has no programme or term of its own, it is placed under Clinical teaching in the teaching view and in the teaching merits and CV exports.",
                                "När kursen saknar eget program och egen termin placeras den under Klinisk undervisning i undervisningsvyn och i exporterna av pedagogiska meriter och CV."
                            ))
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                // Round 7: tasks for the course as a whole, like the task
                // list on a teaching assignment.
                TeachingPanel(
                    title: language.text("Task list", "Uppgiftslista"),
                    titleStyle: .divider,
                    fill: .clear,
                    stroke: .clear,
                    titleActionTitle: language.text("Add task", "Lägg till uppgift"),
                    titleAction: {
                        CentralTaskListSection.addTask(store: store, linkKind: .teachingCourse, targetID: course.id)
                    }
                ) {
                    CentralTaskListSection(
                        store: store,
                        linkKind: .teachingCourse,
                        targetID: course.id,
                        language: language,
                        reminderOptions: ProjectTaskReminder.allCases,
                        isReadOnly: false,
                        showsAddButton: false
                    )
                }

                // Activities and tasks linked to the course or to one of its
                // teaching assignments, by id.
                TeachingPanel(
                    title: language.text("Linked activities and tasks", "Kopplade aktiviteter och uppgifter"),
                    titleStyle: .divider,
                    fill: .clear,
                    stroke: .clear
                ) {
                    CalendarLinkedActivitiesAndTasksList(
                        store: store,
                        language: language,
                        scope: .teachingCourse(course.id)
                    )
                }
            }
            .padding(14)
        }
        .onAppear {
            draft = course
        }
        .onChange(of: draft) { _, _ in
            hasPendingLocalEdits = true
            scheduleAutosave()
        }
        .flushPendingAutosaveOnTextEnd(requestImmediatePersist)
        .onDisappear {
            NSApp.keyWindow?.makeFirstResponder(nil)
            forcedPersistTask?.cancel()
            persist()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                requestImmediatePersist()
            }
        }
        .onChange(of: course) { _, newValue in
            if hasPendingLocalEdits, preparedForPersistence(from: draft) != newValue {
                return
            }
            draft = newValue
            hasPendingLocalEdits = false
        }
    }

    private func preparedForPersistence(from source: TeachingCourse) -> TeachingCourse {
        var normalized = source
        normalized.normalize()
        if normalized.contextType == nil {
            normalized.contextType = showsLeafFields ? .course : .programTrack
        }
        return normalized
    }

    private func persist() {
        AutosaveCoordinator.flush(&autosaveTask) {
            let normalized = preparedForPersistence(from: draft)
            // See the assignment editor: no change means nothing pending.
            guard normalized != course else { hasPendingLocalEdits = false; return }
            store.saveTeachingCourse(normalized)
            hasPendingLocalEdits = false
        }
    }

    private func autosave() {
        let normalized = preparedForPersistence(from: draft)
        guard normalized != course else { hasPendingLocalEdits = false; return }
        store.autosaveTeachingCourse(normalized)
        hasPendingLocalEdits = false
    }

    private func scheduleAutosave() {
        AutosaveCoordinator.schedule(&autosaveTask, after: 0.45) {
            autosave()
        }
    }

    private func requestImmediatePersist() {
        AutosaveCoordinator.requestImmediate(&forcedPersistTask, after: 0.05) {
            persist()
        }
    }

}

private struct TeachingDateField: View {
    let title: String?
    let text: Binding<String>
    var isDisabled: Bool = false
    var width: CGFloat = 180
    var showsTitle = true
    var language: AppLanguage = .english

    var body: some View {
        AppLabeledField(title: showsTitle ? (title ?? "") : "", width: width, fillsAvailableWidth: false) {
            AppDateField(
                placeholder: language.datePlaceholder,
                text: text,
                width: 104,
                showsTodayButton: true,
                language: language,
                isDisabled: isDisabled
            )
            .frame(width: width, alignment: .leading)
        }
    }
}

private struct TeachingDeleteButton: View {
    let title: String
    let cancelTitle: String
    let action: () -> Void

    var body: some View {
        DeleteActionButton(title: title, cancelTitle: cancelTitle, action: action)
    }
}

private extension TeachingContextType {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .course:
            return fixedDropdownText("teachingContext.course", language: language, english: "Course", swedish: "Kurs")
        case .programTrack:
            return fixedDropdownText("teachingContext.programTrack", language: language, english: "Program / track", swedish: "Program / spår")
        case .doctoralEducation:
            return fixedDropdownText("teachingContext.doctoralEducation", language: language, english: "Doctoral education", swedish: "Forskarutbildning")
        case .clinicalTeaching:
            return fixedDropdownText("teachingContext.clinicalTeaching", language: language, english: "Clinical teaching", swedish: "Klinisk undervisning")
        case .courseAdministration:
            return fixedDropdownText("teachingContext.courseAdministration", language: language, english: "Course administration / development", swedish: "Kursadministration / kursutveckling")
        case .other:
            return fixedDropdownText("teachingContext.other", language: language, english: "Other", swedish: "Övrigt")
        }
    }
}

private extension TeachingCourseLevel {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .undergraduate:
            return fixedDropdownText("teachingLevel.undergraduate", language: language, english: "Undergraduate", swedish: "Grundnivå")
        case .advanced:
            return fixedDropdownText("teachingLevel.advanced", language: language, english: "Advanced", swedish: "Avancerad nivå")
        case .doctoral:
            return fixedDropdownText("teachingLevel.doctoral", language: language, english: "Doctoral", swedish: "Forskarnivå")
        }
    }
}

private extension TeachingAssignmentKind {
    func displayName(language: AppLanguage) -> String {
        fixedDropdownText(
            translationKey,
            language: language,
            english: defaultEnglishName,
            swedish: defaultSwedishName
        )
    }
}

private extension TeachingAssignmentRole {
    func displayName(language: AppLanguage) -> String {
        switch rawValue {
        case TeachingAssignmentRole.contributor.rawValue:
            return fixedDropdownText("teachingRole.contributor", language: language, english: "Contributor", swedish: "Medarbetare")
        case TeachingAssignmentRole.facilitator.rawValue:
            return fixedDropdownText("teachingRole.facilitator", language: language, english: "Facilitator", swedish: "Facilitator")
        case TeachingAssignmentRole.supervisor.rawValue:
            return fixedDropdownText("teachingRole.supervisor", language: language, english: "Supervisor", swedish: "Handledare")
        case TeachingAssignmentRole.examiner.rawValue:
            return fixedDropdownText("teachingRole.examiner", language: language, english: "Examiner", swedish: "Examinator")
        case TeachingAssignmentRole.lecturer.rawValue:
            return fixedDropdownText("teachingRole.lecturer", language: language, english: "Lecturer", swedish: "Föreläsare")
        case TeachingAssignmentRole.invitedSpeaker.rawValue:
            return fixedDropdownText("teachingRole.invitedSpeaker", language: language, english: "Invited speaker", swedish: "Inbjuden talare")
        case TeachingAssignmentRole.seminarLeader.rawValue:
            return fixedDropdownText("teachingRole.seminarLeader", language: language, english: "Seminar leader", swedish: "Seminarieledare")
        case TeachingAssignmentRole.principalSupervisor.rawValue:
            return fixedDropdownText("teachingRole.principalSupervisor", language: language, english: "Principal supervisor", swedish: "Huvudhandledare")
        case TeachingAssignmentRole.assistantSupervisor.rawValue:
            return fixedDropdownText("teachingRole.assistantSupervisor", language: language, english: "Co-supervisor", swedish: "Bihandledare")
        case TeachingAssignmentRole.opponent.rawValue:
            return fixedDropdownText("teachingRole.opponent", language: language, english: "Opponent", swedish: "Opponent")
        case TeachingAssignmentRole.gradingCommittee.rawValue:
            return fixedDropdownText("teachingRole.gradingCommittee", language: language, english: "Grading committee", swedish: "Betygskommitté")
        default:
            return rawValue
        }
    }
}

private extension TeachingAssignmentCategory {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .individual:
            return fixedDropdownText("teachingParticipant.individual", language: language, english: "Individual", swedish: "Individuell")
        case .group:
            return fixedDropdownText("teachingParticipant.group", language: language, english: "Group", swedish: "Grupp")
        case .groupAndIndividual:
            return fixedDropdownText("teachingParticipant.groupAndIndividual", language: language, english: "Group and individual", swedish: "Grupp och individuellt")
        case .notTeachingWork:
            return fixedDropdownText("teachingParticipant.notTeachingWork", language: language, english: "Not teaching work", swedish: "Ej undervisningsarbete")
        }
    }
}

private extension TeachingReportCategory {
    var translationKey: String {
        switch self {
        case .groupTeaching:
            return "teachingReport.groupTeaching"
        case .lecture:
            return "teachingReport.lecture"
        case .doctoralCourseTeaching:
            return "teachingReport.doctoralCourseTeaching"
        case .thesisSupervision:
            return "teachingReport.thesisSupervision"
        case .doctoralPrincipalSupervision:
            return "teachingReport.doctoralPrincipalSupervision"
        case .doctoralAssistantSupervision:
            return "teachingReport.doctoralAssistantSupervision"
        case .courseAdministration:
            return "teachingReport.courseAdministration"
        case .otherPedagogicalWork:
            return "teachingReport.otherPedagogicalWork"
        }
    }

    var defaultEnglishName: String {
        switch self {
        case .groupTeaching:
            return "Group teaching / practical teaching"
        case .lecture:
            return "Lecture"
        case .doctoralCourseTeaching:
            return "Doctoral course teaching"
        case .thesisSupervision:
            return "Thesis / in-depth project supervision"
        case .doctoralPrincipalSupervision:
            return "Doctoral supervision (principal)"
        case .doctoralAssistantSupervision:
            return "Doctoral supervision (co-supervisor)"
        case .courseAdministration:
            return "Course administration / development"
        case .otherPedagogicalWork:
            return "Other pedagogical work"
        }
    }

    var defaultSwedishName: String {
        switch self {
        case .groupTeaching:
            return "Gruppundervisning / praktisk undervisning"
        case .lecture:
            return "Föreläsning"
        case .doctoralCourseTeaching:
            return "Undervisning på forskarutbildningskurs"
        case .thesisSupervision:
            return "Handledning av examensarbete / fördjupningsarbete"
        case .doctoralPrincipalSupervision:
            return "Doktorandhandledning (huvudhandledare)"
        case .doctoralAssistantSupervision:
            return "Doktorandhandledning (bihandledare)"
        case .courseAdministration:
            return "Kursadministration / kursutveckling"
        case .otherPedagogicalWork:
            return "Övrigt pedagogiskt arbete"
        }
    }

    func displayName(language: AppLanguage) -> String {
        fixedDropdownText(
            translationKey,
            language: language,
            english: defaultEnglishName,
            swedish: defaultSwedishName
        )
    }
}

private func teachingFormatCategory(for formatName: String, formats: [TeachingFormatOption]) -> TeachingAssignmentCategory? {
    formats.first {
        $0.nameSv == formatName || $0.nameEn == formatName || $0.name == formatName
    }?.category
}

private extension TeachingDeliveryMode {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .onSite:
            return fixedDropdownText("teachingDelivery.onSite", language: language, english: "On-site", swedish: "Fysiskt")
        case .hybrid:
            return fixedDropdownText("teachingDelivery.hybrid", language: language, english: "Hybrid", swedish: "Hybrid")
        case .online:
            return fixedDropdownText("teachingDelivery.online", language: language, english: "Online", swedish: "Online")
        }
    }
}

private func localizedTeachingFormatName(_ name: String, language: AppLanguage) -> String {
    guard let format = TeachingDefaultFormat(rawValue: name) else { return name }
    switch format {
    case .lectureHybrid:
        return fixedDropdownText("teachingDefaultFormat.lectureHybrid", language: language, english: "Lecture (hybrid)", swedish: "Föreläsning (hybrid)")
    case .lectureOnSite:
        return fixedDropdownText("teachingDefaultFormat.lectureOnSite", language: language, english: "Lecture (on-site)", swedish: "Föreläsning (fysisk)")
    case .lectureOnline:
        return fixedDropdownText("teachingDefaultFormat.lectureOnline", language: language, english: "Lecture (online)", swedish: "Föreläsning (online)")
    case .workshop:
        return fixedDropdownText("teachingDefaultFormat.workshop", language: language, english: "Workshop", swedish: "Workshop")
    case .seminar:
        return fixedDropdownText("teachingDefaultFormat.seminar", language: language, english: "Seminar", swedish: "Seminarium")
    case .practicalTeaching:
        return fixedDropdownText("teachingDefaultFormat.practicalTeaching", language: language, english: "Practical teaching", swedish: "Praktisk undervisning")
    case .supervision:
        return fixedDropdownText("teachingDefaultFormat.supervision", language: language, english: "Supervision", swedish: "Handledning")
    case .thesisSupervision:
        return fixedDropdownText("teachingDefaultFormat.thesisSupervision", language: language, english: "Degree project supervision", swedish: "Handledning examensarbete")
    case .inDepthProjectSupervision:
        return fixedDropdownText("teachingDefaultFormat.inDepthProjectSupervision", language: language, english: "In-depth project supervision", swedish: "Handledning fördjupningsarbete")
    case .doctoralSupervision:
        return fixedDropdownText("teachingDefaultFormat.doctoralSupervision", language: language, english: "Doctoral supervision", swedish: "Handledning doktorandarbete")
    }
}

private func defaultTeachingAssignmentActivityNames(language: AppLanguage) -> [String] {
    [
        language.text("Field study review", "Fältstudiegranskning"),
        language.text("Field study supervision", "Fältstudiehandledning"),
        language.text("Written regular examination", "Skriftlig ordinarie tentamen"),
        language.text("Maintenance work", "Underhållsarbete")
    ]
}

private func assignmentStatusKind(_ assignment: TeachingAssignment) -> TeachingAssignmentStatusKind {
    let periods = assignment.periods.filter { !$0.isEmpty }
    guard !periods.isEmpty else { return .none }

    let today = Calendar.current.startOfDay(for: Date())
    for period in periods {
        guard let startDate = period.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) else { continue }
        let endDate = period.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
        if startDate <= today && endDate.map({ $0 >= today }) ?? true {
            return .ongoing
        }
        if startDate > today || endDate == nil {
            return .ongoing
        }
    }
    return .completed
}

private func assignmentStatusText(_ assignment: TeachingAssignment, language: AppLanguage) -> String {
    switch assignmentStatusKind(assignment) {
    case .none:
        return ""
    case .ongoing:
        return language.text("Ongoing", "Pågående")
    case .completed:
        return language.text("Completed", "Avslutat")
    }
}

private func assignmentTermCount(_ assignment: TeachingAssignment) -> Int {
    var terms = Set<String>()
    let periods = assignment.periods.filter { !$0.isEmpty }
    guard !periods.isEmpty else { return 0 }

    for period in periods {
        guard let startDate = period.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) else { continue }
        let endDate = period.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) ?? Calendar.current.startOfDay(for: Date())
        collectAssignmentTerms(from: startDate, to: endDate, into: &terms)
    }
    return terms.count
}

private func assignmentTotalHoursText(_ assignment: TeachingAssignment) -> String {
    let total = assignmentTotalHoursValue(assignment)
    if total.rounded() == total {
        return String(Int(total))
    }
    return String(format: "%.1f", total)
}

private func assignmentTotalHoursValue(_ assignment: TeachingAssignment) -> Double {
    let relevantPeriods = assignment.periods.filter { !$0.isEmpty }
    guard !relevantPeriods.isEmpty else { return 0 }

    return relevantPeriods.reduce(0) { partial, period in
        guard let startDate = period.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) else {
            return partial
        }
        let endDate = period.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) ?? Calendar.current.startOfDay(for: Date())
        var terms = Set<String>()
        collectAssignmentTerms(from: startDate, to: endDate, into: &terms)
        let hoursPerTerm = GrantParsing.numericValue(from: period.hoursPerTerm) ?? 0
        return partial + (Double(terms.count) * hoursPerTerm)
    }
}

private func assignmentPeriodFirstDate(_ assignment: TeachingAssignment) -> String? {
    let dates = assignment.periods.compactMap { $0.from.nonEmpty }
    return dates.sorted().first
}

private func assignmentPeriodLastDate(_ assignment: TeachingAssignment) -> String? {
    let dates = assignment.periods.compactMap { $0.to.nonEmpty }
    return dates.sorted().last
}

private func assignmentYearLabel(_ assignment: TeachingAssignment) -> String {
    let filledPeriods = assignment.periods.filter { !$0.isEmpty }

    if assignmentStatusKind(assignment) == .ongoing {
        if let startYear = filledPeriods.first?.from.nonEmpty.flatMap(yearComponent) {
            return "\(startYear) – "
        }
    }

    guard !filledPeriods.isEmpty else { return "" }

    let firstFrom = filledPeriods.first?.from.nonEmpty
    let lastTo = filledPeriods.last?.to.nonEmpty
    return yearLabel(from: firstFrom, to: lastTo)
}

private func yearLabel(from startText: String?, to endText: String?) -> String {
    let startYear = startText.flatMap(yearComponent)
    let endYear = endText.flatMap(yearComponent)

    switch (startYear, endYear) {
    case let (start?, end?) where start != end:
        return "\(start)-\(end)"
    case let (start?, _):
        return "\(start)"
    case let (_, end?):
        return "\(end)"
    default:
        return ""
    }
}

private func yearComponent(from text: String) -> Int? {
    guard let date = DateParsers.isoDay.date(from: text) else { return nil }
    return Calendar.current.component(.year, from: date)
}

private func collectAssignmentTerms(from startDate: Date, to endDate: Date, into terms: inout Set<String>) {
    let start = min(startDate, endDate)
    let end = max(startDate, endDate)
    var cursor = start
    while cursor <= end {
        let year = Calendar.current.component(.year, from: cursor)
        let month = Calendar.current.component(.month, from: cursor)
        let half = month <= 6 ? 1 : 2
        terms.insert("\(year)-\(half)")
        guard let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: cursor) else { break }
        cursor = nextMonth
    }
}
