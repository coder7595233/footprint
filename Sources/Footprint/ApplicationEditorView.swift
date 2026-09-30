import AppKit
import SwiftUI
import UniformTypeIdentifiers

func applicationOrganizationAutocompleteOptions(
    organizations: [OrganizationRecord],
    applications: [GrantApplication],
    selectedOrganizationID: String?,
    selectedOrganizationName: String?,
    language: AppLanguage
) -> [String] {
    let matchingOrganizations = organizations.filter { organization in
        organization.roles.contains(.grantProvider)
            || organization.id == selectedOrganizationID
            || organization.nameSv == selectedOrganizationName
    }

    let baseOrganizations = matchingOrganizations.isEmpty ? organizations : matchingOrganizations
    var optionsByKey: [String: String] = [:]

    func add(_ value: String?) {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return }
        let key = PublicationDerivation.normalizedName(trimmed)
        if optionsByKey[key] == nil {
            optionsByKey[key] = trimmed
        }
    }

    for organization in baseOrganizations {
        add(organization.displayName(for: language))
    }

    for application in applications {
        if let matched = organizations.first(where: { $0.nameSv == application.organization }) {
            add(matched.displayName(for: language))
        } else {
            add(application.organization)
        }
    }

    add(selectedOrganizationName)

    return optionsByKey.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

struct GrantSalaryApproximationYearAmount: Equatable, Identifiable {
    let year: Int
    let amount: Double

    var id: Int { year }
}

struct GrantSalaryApproximationBreakdown: Equatable {
    let yearlyAmounts: [GrantSalaryApproximationYearAmount]
    /// "Behov av samfinansiering": the fund manager's full OH minus the OH
    /// that counts, on the same salary base, for the whole period. 0 when
    /// the grant provider accepts the full OH or overhead is not included.
    var cofundingAmount: Double = 0

    var totalAmount: Double {
        yearlyAmounts.reduce(0) { $0 + $1.amount }
    }
}

func calculateGrantSalaryApproximation(
    calculator: ManagerSalaryCalculator,
    percentageText: String?,
    monthsText: String?,
    startMonth: Date?,
    includesOverhead: Bool,
    maxOverheadPercent: Double? = nil,
    overheadPlan: GrantOverheadPlan? = nil
) -> GrantSalaryApproximationBreakdown? {
    guard let percentage = GrantParsing.numericValue(from: percentageText),
          let months = GrantParsing.numericValue(from: monthsText),
          let startMonth,
          percentage > 0,
          months > 0 else {
        return nil
    }

    let allocationFraction = max(0, min(1, percentage / 100))
    let totalMonths = max(0, months)
    let fullMonths = Int(totalMonths.rounded(.down))
    let partialMonth = totalMonths - Double(fullMonths)
    let calendar = Calendar.current
    // Without a plan, the earlier single "Max OH (%)" (nil = no cap) counts.
    let plan = overheadPlan ?? GrantOverheadPlan(legacyMaxOverheadPercent: maxOverheadPercent)
    var yearlyAmounts: [Int: Double] = [:]
    var cofundingAmount: Double = 0

    for monthOffset in 0..<fullMonths {
        guard let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: startMonth) else { continue }
        let year = calendar.component(.year, from: monthDate)
        let vacationDays = grantVacationDays(for: year, calculator: calculator)
        let cost = grantMonthlySalaryCost(
            on: monthDate,
            calculator: calculator,
            vacationDays: vacationDays,
            includesOverhead: includesOverhead,
            plan: plan
        )
        yearlyAmounts[year, default: 0] += cost.amount * allocationFraction
        cofundingAmount += cost.cofunding * allocationFraction
    }

    if partialMonth > 0,
       let partialMonthDate = calendar.date(byAdding: .month, value: fullMonths, to: startMonth) {
        let year = calendar.component(.year, from: partialMonthDate)
        let vacationDays = grantVacationDays(for: year, calculator: calculator)
        let cost = grantMonthlySalaryCost(
            on: partialMonthDate,
            calculator: calculator,
            vacationDays: vacationDays,
            includesOverhead: includesOverhead,
            plan: plan
        )
        yearlyAmounts[year, default: 0] += cost.amount * allocationFraction * partialMonth
        cofundingAmount += cost.cofunding * allocationFraction * partialMonth
    }

    let rows = yearlyAmounts.keys.sorted().map {
        GrantSalaryApproximationYearAmount(year: $0, amount: yearlyAmounts[$0] ?? 0)
    }
    guard !rows.isEmpty else { return nil }
    return GrantSalaryApproximationBreakdown(yearlyAmounts: rows, cofundingAmount: cofundingAmount)
}

func applyingGrantConsumptionPeriodEdit(
    _ period: GrantConsumptionPeriod,
    keyPath: WritableKeyPath<GrantConsumptionPeriod, String>,
    value: String
) -> GrantConsumptionPeriod {
    var updated = period
    updated[keyPath: keyPath] = value
    return updated
}

func applyingGrantTimelineDateEdit(
    _ application: GrantApplication,
    keyPath: WritableKeyPath<GrantApplication, String?>,
    value: String
) -> GrantApplication {
    var updated = application
    updated[keyPath: keyPath] = DateParsers.canonicalizedDayInput(value).trimmedOrNil
    return updated
}

/// The overhead rate (a fraction, 0.2 = 20 %) after a cap in percent
/// ("Högst __ %" in the grant provider's OH rule): nil = no cap, 0 = no
/// overhead.
func grantOverheadRate(_ rate: Double, cappedAtPercent maxOverheadPercent: Double?) -> Double {
    guard let maxOverheadPercent else { return rate }
    return min(rate, max(0, maxOverheadPercent) / 100)
}

/// The OH rates (fractions, 0.2 = 20 %) in one month: the fund manager's
/// full OH and the OH that counts after the grant provider's rule.
struct GrantOverheadRates: Equatable {
    let manager: Double
    let effective: Double
}

/// The fund manager's full OH in a month: its own OH periods when any are
/// filled in, otherwise "Förvaltarens fulla OH (%)", otherwise (no fund
/// manager, or nothing entered on it) the OH periods of the salary
/// calculator used for applications, as before. Then the grant provider's
/// rule gives the OH that counts.
func grantOverheadRates(on date: Date, calculator: ManagerSalaryCalculator, plan: GrantOverheadPlan) -> GrantOverheadRates {
    let managerRate: Double
    if grantHasUsableSalaryPeriods(plan.managerOverheadPeriods) {
        managerRate = grantResolvedSalaryPercentage(on: date, from: plan.managerOverheadPeriods)
    } else if let percent = plan.managerOverheadPercent {
        managerRate = percent / 100
    } else {
        managerRate = grantResolvedSalaryPercentage(on: date, from: calculator.overheadPeriods)
    }
    let manager = max(0, managerRate)
    return GrantOverheadRates(manager: manager, effective: plan.rule.effectiveRate(managerRate: manager))
}

private func grantHasUsableSalaryPeriods(_ periods: [SalaryCalculatorPeriod]) -> Bool {
    periods.contains { period in
        GrantParsing.numericValue(from: period.value) != nil
            && DateParsers.isoDay.date(from: period.from) != nil
            && DateParsers.isoDay.date(from: period.to) != nil
    }
}

private struct GrantMonthlySalaryCost {
    let amount: Double
    let cofunding: Double
}

private func grantMonthlySalaryCost(
    on monthDate: Date,
    calculator: ManagerSalaryCalculator,
    vacationDays: Int,
    includesOverhead: Bool,
    plan: GrantOverheadPlan
) -> GrantMonthlySalaryCost {
    let monthlySalary = grantResolvedSalaryPeriodValue(
        on: monthDate,
        from: calculator.monthlySalaryPeriods,
        growFutureValues: true,
        annualIncreasePercentText: calculator.annualIncreaseAfterCurrentYearPercent
    )
    let employerRate = grantResolvedSalaryPercentage(on: monthDate, from: calculator.employerFeePeriods)
    let regionalRate = grantResolvedSalaryPercentage(on: monthDate, from: calculator.regionalCostPeriods)
    let rates = includesOverhead
        ? grantOverheadRates(on: monthDate, calculator: calculator, plan: plan)
        : GrantOverheadRates(manager: 0, effective: 0)

    let vacationSupplement = monthlySalary * calculator.vacationSupplementRatePerDay * Double(vacationDays) / 12
    let salaryWithVacation = monthlySalary + vacationSupplement
    let salaryWithSocialCosts = salaryWithVacation * (1 + employerRate + regionalRate)
    return GrantMonthlySalaryCost(
        amount: salaryWithSocialCosts * (1 + rates.effective),
        cofunding: salaryWithSocialCosts * max(0, rates.manager - rates.effective)
    )
}

private func grantVacationDays(for year: Int, calculator: ManagerSalaryCalculator) -> Int {
    guard let birthDate = DateParsers.isoDay.date(from: calculator.birthDate),
          let yearEnd = Calendar.current.date(from: DateComponents(year: year, month: 12, day: 31)) else {
        return calculator.vacationDays(atAge: nil)
    }
    let age = Calendar.current.dateComponents([.year], from: birthDate, to: yearEnd).year ?? 0
    return calculator.vacationDays(atAge: age)
}

private func grantResolvedSalaryPercentage(on date: Date, from periods: [SalaryCalculatorPeriod]) -> Double {
    grantResolvedSalaryPeriodValue(on: date, from: periods, growFutureValues: false) / 100
}

private func grantResolvedSalaryPeriodValue(
    on date: Date,
    from periods: [SalaryCalculatorPeriod],
    growFutureValues: Bool,
    annualIncreasePercentText: String = "3"
) -> Double {
    let validPeriods = periods.compactMap { period -> (start: Date, end: Date, value: Double)? in
        guard let value = GrantParsing.numericValue(from: period.value),
              let start = DateParsers.isoDay.date(from: period.from),
              let end = DateParsers.isoDay.date(from: period.to) else {
            return nil
        }
        return start <= end ? (start, end, value) : (end, start, value)
    }
    .sorted { $0.start < $1.start }

    guard !validPeriods.isEmpty else { return 0 }

    if let exact = validPeriods.first(where: { date >= $0.start && date <= $0.end }) {
        return exact.value
    }

    if let latestPast = validPeriods.last(where: { $0.end < date }) {
        guard growFutureValues else { return latestPast.value }
        let latestYear = Calendar.current.component(.year, from: latestPast.end)
        let targetYear = Calendar.current.component(.year, from: date)
        let yearsAhead = max(0, targetYear - latestYear)
        let annualIncreaseRate = max(
            0,
            (GrantParsing.numericValue(from: annualIncreasePercentText) ?? 3) / 100
        )
        return latestPast.value * pow(1 + annualIncreaseRate, Double(yearsAhead))
    }

    return validPeriods.first?.value ?? 0
}

struct ApplicationEditorView: View {
    @ObservedObject var store: GrantDataStore
    let application: GrantApplication
    let initialSelectionID: String
    let isActive: Bool
    let focusGrantedSection: Bool
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("FootprintShowsInlineStatistics") private var showsInlineStatistics = true
    @State private var draft: GrantApplication
    @State private var currentSelectionID: String
    @State private var criteriaText: String
    @State private var pendingCoApplicantName = ""
    @State private var draggedCoApplicantName: String?
    @State private var coApplicantIdentity: StableStringDraftListState
    @State private var autosaveTask: DispatchWorkItem?
    @State private var cachedCalendarEvents: [CalendarLinkedEventRow] = []
    @State private var showsDeferredSections = true
    @State private var calendarRefreshToken: UInt = 0

    private let addNewToken = "__add_new__"

    private var coApplicantOptions: [String] {
        store.orderedCoauthorPresentedNames()
    }

    private var currentUserBirthDate: String? {
        store.currentUserAuthor()?.birthDate.nonEmpty
    }

    private var linkedProject: ProjectRecord? {
        draft.projectID.flatMap { store.project(id: $0) }
            ?? draft.projectType.flatMap { store.project(named: $0) }
    }

    private var linkedProjectCollaboratorNames: [String] {
        uniquedApplicantNames(linkedProject?.collaboratorNames ?? [])
    }

    private var hasMissingProjectCollaborators: Bool {
        let currentNames = Set(
            draft.coApplicants
                .map(normalizedApplicantName)
                .filter { !$0.isEmpty }
        )
        return linkedProjectCollaboratorNames.contains { !currentNames.contains(normalizedApplicantName($0)) }
    }

    init(
        store: GrantDataStore,
        application: GrantApplication,
        selectionID: String? = nil,
        isActive: Bool = true,
        focusGrantedSection: Bool = false
    ) {
        self.store = store
        self.application = application
        self.initialSelectionID = selectionID ?? application.id
        self.isActive = isActive
        self.focusGrantedSection = focusGrantedSection
        _draft = State(initialValue: application)
        _coApplicantIdentity = State(initialValue: StableStringDraftListState(values: application.coApplicants))
        _currentSelectionID = State(initialValue: selectionID ?? application.id)
        _criteriaText = State(initialValue: application.applicantCriteria ?? application.projectCriteria ?? "")
    }

    private var hasChanges: Bool {
        pendingDraft != application
    }

    private var isMarkedNotApplied: Bool {
        draft.isNotAppliedStatus
    }

    private var showsApplicationSpecificSections: Bool {
        !isMarkedNotApplied
    }

    private func undoRevealIsActive(fieldKey: String) -> Bool {
        store.undoRevealRequest?.target.matchesField(
            routeDestination: .applications,
            recordID: application.id,
            fieldKey: fieldKey
        ) == true
    }

    private var pendingDraft: GrantApplication {
        var pending = draft
        pending.applicantCriteria = criteriaText
        pending.projectCriteria = nil
        // The salary estimate is worked out only while the record is open
        // and not yet applied for. A locked or applied record keeps the
        // amount it has, so opening it never changes it.
        if !draft.isEditingLocked, draft.isNotYetApplied {
            pending.approximateAmountValue = approximateAmountComputedValue
            pending.approximateAmount = approximateAmountComputedValue.flatMap { GrantParsing.formatAmountInput(String(Int($0.rounded()))) }
        }
        return pending
    }

    private var approximateAmountBreakdown: GrantSalaryApproximationBreakdown? {
        guard let calculator = applicationSalaryCalculator() else { return nil }
        return calculateGrantSalaryApproximation(
            calculator: calculator,
            percentageText: draft.employmentPercentage,
            monthsText: draft.employmentMonths,
            startMonth: approximationStartMonth,
            includesOverhead: draft.salaryIncludesOverhead,
            // Round 8: the grant provider's OH rule for the application's
            // fund manager, both found by id first.
            overheadPlan: applicationOverheadPlan
        )
    }

    private var applicationOverheadPlan: GrantOverheadPlan {
        store.overheadPlan(for: draft)
    }

    private var approximateAmountComputedValue: Double? {
        approximateAmountBreakdown?.totalAmount
    }

    private var maximumFundingRowShouldShowWhenLocked: Bool {
        !draft.isEditingLocked
            || draft.maxAmount?.trimmedOrNil != nil
            || draft.yearCount?.trimmedOrNil != nil
            || draft.maximumTotalAmountValue != nil
    }

    private var salaryFundingRowShouldShowWhenLocked: Bool {
        !draft.isEditingLocked
            || draft.employmentPercentage?.trimmedOrNil != nil
            || draft.employmentMonths?.trimmedOrNil != nil
            || salaryOverheadShouldShowWhenLocked
            || approximateAmountBreakdown != nil
    }

    private var salaryOverheadShouldShowWhenLocked: Bool {
        draft.salaryIncludesOverhead
            && (
                draft.employmentPercentage?.trimmedOrNil != nil
                    || draft.employmentMonths?.trimmedOrNil != nil
                    || approximateAmountBreakdown != nil
            )
    }

    private var shouldShowFundingAndCriteriaSection: Bool {
        !draft.isEditingLocked
            || maximumFundingRowShouldShowWhenLocked
            || salaryFundingRowShouldShowWhenLocked
            || draft.fundingSalary
            || draft.fundingMaterials
            || draft.fundingPhDStudents
            || criteriaText.trimmedOrNil != nil
    }

    private var applicationLinksRowShouldShowWhenLocked: Bool {
        !draft.isEditingLocked
    }

    private struct ApproximateAmountMetric: Identifiable {
        let id: String
        let label: String
        let value: String
        let emphasized: Bool
    }

    private func applicationCategoryStatusSummary(language: AppLanguage) -> String {
        let category = draft.organizationCategoryDisplay(in: store, language: language).trimmingCharacters(in: .whitespacesAndNewlines)
        let status = store.language.localizedStatus(draft.resultLabel).trimmingCharacters(in: .whitespacesAndNewlines)
        switch (category.isEmpty, status.isEmpty) {
        case (false, false):
            return "\(category). \(status)."
        case (false, true):
            return "\(category)."
        case (true, false):
            return "\(status)."
        case (true, true):
            return ""
        }
    }

    private var consumedAmountFromPeriodsValue: Double {
        draft.receivedConsumptionPeriods.compactMap(\.amountValue).reduce(0, +)
    }

    private var applicationCurrencyCode: String {
        draft.currency?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "SEK"
    }

    private var consumedAmountDisplay: String {
        store.formattedGrantAmountWithSEKApproximation(consumedAmountFromPeriodsValue, for: draft)
    }

    private var remainingGrantedDisplay: String {
        let granted = draft.grantedAmountValue ?? 0
        return store.formattedGrantAmountWithSEKApproximation(max(0, granted - consumedAmountFromPeriodsValue), for: draft)
    }

    private var showsGrantedFollowUpPanel: Bool {
        draft.isGranted
    }

    private var showsFullGrantedFollowUpPanel: Bool {
        draft.isGranted && store.isCurrentUserFirstApplicant(draft)
    }

    private var approximationStartMonth: Date? {
        let calendar = Calendar.current
        if let firstDispositionDate = draft.firstDispositionDate {
            return calendar.date(from: calendar.dateComponents([.year, .month], from: firstDispositionDate))
        }
        return calendar.date(from: DateComponents(year: fallbackApproximationYear + 1, month: 1, day: 1))
    }

    private var fallbackApproximationYear: Int {
        if let year = draft.applicationDate.map({ Calendar.current.component(.year, from: $0) }) {
            return year
        }
        if let appliedYear = Int(draft.appliedYear?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") {
            return appliedYear
        }
        if let statsYear = Int(draft.statsYear) {
            return statsYear
        }
        return Calendar.current.component(.year, from: Date())
    }

    private func applicationSalaryCalculator() -> ManagerSalaryCalculator? {
        // The organization with "Use as salary calculator for applications"
        // ticked (Organizations > the organization > Employer).
        let current = store.applicationSalaryCalculatorOrganization?.salaryCalculator ?? .empty
        var merged = mergedSalaryCalculator(current: current)
        if let currentUserBirthDate {
            merged.birthDate = currentUserBirthDate
        }
        return merged
    }

    private func mergedSalaryCalculator(current: ManagerSalaryCalculator) -> ManagerSalaryCalculator {
        let baseline = ManagerSalaryCalculator.defaultSalaryCalculatorTemplate
        var merged = current
        if merged.birthDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.birthDate = baseline.birthDate
        }
        if merged.annualIncreaseAfterCurrentYearPercent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.annualIncreaseAfterCurrentYearPercent = baseline.annualIncreaseAfterCurrentYearPercent
        }
        merged.monthlySalaryPeriods = mergeSalaryPeriods(current: current.monthlySalaryPeriods, defaults: baseline.monthlySalaryPeriods)
        merged.employerFeePeriods = mergeSalaryPeriods(current: current.employerFeePeriods, defaults: baseline.employerFeePeriods)
        merged.regionalCostPeriods = mergeSalaryPeriods(current: current.regionalCostPeriods, defaults: baseline.regionalCostPeriods)
        merged.overheadPeriods = mergeSalaryPeriods(current: current.overheadPeriods, defaults: baseline.overheadPeriods)
        return merged
    }

    private func mergeSalaryPeriods(current: [SalaryCalculatorPeriod], defaults: [SalaryCalculatorPeriod]) -> [SalaryCalculatorPeriod] {
        var merged = current.filter {
            $0.value.nonEmpty != nil || $0.from.nonEmpty != nil || $0.to.nonEmpty != nil
        }
        if merged.isEmpty {
            return defaults
        }
        for defaultPeriod in defaults {
            if let existingIndex = merged.firstIndex(where: { $0.id == defaultPeriod.id || ($0.from == defaultPeriod.from && $0.to == defaultPeriod.to) }) {
                if merged[existingIndex].value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    merged[existingIndex].value = defaultPeriod.value
                }
            } else {
                merged.append(defaultPeriod)
            }
        }
        return merged.sorted {
            let leftDate = DateParsers.isoDay.date(from: $0.from) ?? .distantFuture
            let rightDate = DateParsers.isoDay.date(from: $1.from) ?? .distantFuture
            return leftDate < rightDate
        }
    }

    var body: some View {
        let language = store.language

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    header(language: language)
                    inlineDataQualityPanel(language: language)

                    VStack(alignment: .leading, spacing: 2) {
                        ApplicationTimelineStepper(store: store, application: $draft, language: language)
                            .padding(.top, 10)
                            .padding(.bottom, -8)
                            .allowsHitTesting(!draft.isEditingLocked)
                    }

                    if showsDeferredSections {
                        if showsApplicationSpecificSections {
                            DetailGroup(title: language.text("Applicants", "Sökande"), showsSurface: false) {
                                HStack(alignment: .top, spacing: 24) {
                                    coApplicantPickerArea(language: language)

                                    // Composition of the applicant group; never
                                    // shown when the user is the sole applicant.
                                    // Fixed width and ≥1 cm of air on its left,
                                    // mirroring the publication editor.
                                    if showsInlineStatistics, applicantStatisticsNames.count > 1 {
                                        Spacer(minLength: 28)
                                        ContributorCompositionInlineSection(
                                            store: store,
                                            contributorNames: applicantStatisticsNames,
                                            language: language
                                        )
                                        .frame(width: 480, alignment: .topLeading)
                                    }
                                }
                            }
                        }

                        Group {
                        if shouldShowFundingAndCriteriaSection {
                            DetailGroup(title: language.text("Call", "Utlysning"), showsSurface: false) {
                            VStack(alignment: .leading, spacing: 10) {
                                if maximumFundingRowShouldShowWhenLocked {
                                    HStack(alignment: .top, spacing: 12) {
                                        compactField(
                                            title: language.text("Maximum amount per year", "Maxbelopp per år"),
                                            fieldKey: "maxAmount",
                                            width: 240,
                                            content: AnyView(amountFieldWithCurrency(amountBinding(\.maxAmount), language: language))
                                        )
                                        compactField(
                                            title: language.text("Number of years", "Antal år"),
                                            fieldKey: "yearCount",
                                            width: 110,
                                            content: AnyView(textField(optionalBinding(\.yearCount), label: language.text("Number of years", "Antal år")))
                                        )
                                        compactField(
                                            title: language.text("Maximum total", "Max totalt"),
                                            fieldKey: "maximumTotalAmount",
                                            width: 240,
                                            content: AnyView(
                                                AppLockableField(
                                                    isLocked: draft.isEditingLocked,
                                                    lockedText: store.formattedGrantAmountWithSEKApproximation(
                                                        draft.maximumTotalAmountValue,
                                                        for: draft
                                                    )
                                                ) {
                                                    ReadOnlyValue(
                                                        text: store.formattedGrantAmountWithSEKApproximation(
                                                            draft.maximumTotalAmountValue,
                                                            for: draft
                                                        )
                                                    )
                                                }
                                            )
                                        )
                                        Spacer(minLength: 0)
                                    }
                                }

                                if salaryFundingRowShouldShowWhenLocked {
                                    HStack(alignment: .top, spacing: 12) {
                                        compactField(
                                            title: language.text("Employment percentage", "Sysselsättningsgrad"),
                                            fieldKey: "employmentPercentage",
                                            width: 180,
                                            content: AnyView(textField(optionalBinding(\.employmentPercentage), label: language.text("Employment percentage", "Sysselsättningsgrad")))
                                        )
                                        compactField(
                                            title: language.text("Number of months", "Antal månader"),
                                            fieldKey: "employmentMonths",
                                            width: 140,
                                            content: AnyView(textField(optionalBinding(\.employmentMonths), label: language.text("Number of months", "Antal månader")))
                                        )
                                        compactField(
                                            title: "OH",
                                            fieldKey: "salaryIncludesOverhead",
                                            width: 74,
                                            content: AnyView(
                                                AppCompactCheckboxCell(
                                                    title: language.text("Includes overhead", "Inkluderar OH"),
                                                    isOn: boolBinding(\.salaryIncludesOverhead)
                                                )
                                            )
                                        )
                                        if !draft.isEditingLocked || approximateAmountBreakdown != nil {
                                            approximateAmountBreakdownView(language: language)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    overheadRuleSummaryView(language: language)
                                }

                                if !draft.isEditingLocked || draft.fundingSalary || draft.fundingMaterials || draft.fundingPhDStudents {
                                    formFieldTitle(language.text("Funds can be used for:", "Medel kan användas till:"))

                                    HStack(spacing: 14) {
                                        if draft.isEditingLocked {
                                            if draft.fundingSalary {
                                                lockedApplicationValueText(language.text("Salary", "Lönemedel"))
                                            }
                                            if draft.fundingMaterials {
                                                lockedApplicationValueText(language.text("Materials", "Material"))
                                            }
                                            if draft.fundingPhDStudents {
                                                lockedApplicationValueText(language.text("PhD students", "Doktorander"))
                                            }
                                        } else {
                                            Toggle(language.text("Salary", "Lönemedel"), isOn: boolBinding(\.fundingSalary))
                                                .appCheckboxStyle()
                                            Toggle(language.text("Materials", "Material"), isOn: boolBinding(\.fundingMaterials))
                                                .appCheckboxStyle()
                                            Toggle(language.text("PhD students", "Doktorander"), isOn: boolBinding(\.fundingPhDStudents))
                                                .appCheckboxStyle()
                                        }
                                        Spacer()
                                    }
                                }

                                if !draft.isEditingLocked || criteriaText.trimmedOrNil != nil {
                                    if draft.isEditingLocked {
                                        VStack(alignment: .leading, spacing: 6) {
                                            formFieldTitle(language.text("Criteria", "Kriterier"))
                                            lockedApplicationValueText(criteriaText)
                                                .lineLimit(nil)
                                        }
                                    } else {
                                        EditableTextArea(
                                            title: language.text("Criteria", "Kriterier"),
                                            text: Binding(
                                                get: { criteriaText },
                                                set: { criteriaText = $0 }
                                            ),
                                            minimumHeight: 86
                                        )
                                        .undoRevealPulse(
                                            triggerID: store.undoRevealRequest?.id,
                                            isActive: undoRevealIsActive(fieldKey: "criteria")
                                        )
                                    }
                                }
                            }
                        }
                        }

                        if showsApplicationSpecificSections {
                            DetailGroup(title: language.text("Application details", "Ansökningsdetaljer"), showsSurface: false) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .top, spacing: 14) {
                                        compactField(
                                            title: language.text("Project", "Projekt"),
                                            fieldKey: "project",
                                            width: 240,
                                            content: AnyView(projectPicker(language: language))
                                        )
                                        compactField(
                                            title: language.text("Application title", "Ansökningstitel"),
                                            fieldKey: "applicationTitle",
                                            width: nil,
                                            content: AnyView(textField(optionalBinding(\.applicationTitle), label: language.text("Application title", "Ansökningstitel")))
                                        )
                                    }
                                    HStack(alignment: .top, spacing: 14) {
                                        compactField(
                                            title: language.text("Applied amount", "Sökt belopp"),
                                            fieldKey: "appliedAmount",
                                            width: 240,
                                            help: store.currencyConversionHelpText(
                                                for: draft.appliedAmountValue,
                                                application: draft,
                                                language: language
                                            ),
                                            content: AnyView(amountFieldWithCurrency(amountBinding(\.appliedAmount), language: language))
                                        )
                                        compactField(title: language.text("Grant number", "Ansökningsnummer"), fieldKey: "appliedCaseNumber", width: nil, content: AnyView(textField(optionalBinding(\.appliedCaseNumber), label: language.text("Grant number", "Ansökningsnummer"))))
                                    }
                                    HStack(alignment: .top, spacing: 14) {
                                        compactField(title: language.text("Fund manager", "Medelsförvaltare"), fieldKey: "applicationManager", width: nil, content: AnyView(managerPicker(language: language)))
                                        compactField(title: language.text("Reason for fund manager", "Skäl till medelsförvaltare"), fieldKey: "managerReason", width: nil, content: AnyView(textField(optionalBinding(\.managerReason), label: language.text("Reason for fund manager", "Skäl till medelsförvaltare"))))
                                        compactField(title: language.text("Case number", "Diarienummer"), fieldKey: "institutionCaseNumber", width: nil, content: AnyView(textField(optionalBinding(\.institutionCaseNumber), label: language.text("Case number", "Diarienummer"))))
                                    }
                                    overheadNumbersRow(language: language)
                                    if applicationLinksRowShouldShowWhenLocked {
                                        HStack(alignment: .top, spacing: 14) {
                                            compactField(
                                                title: language.text("Link to grant call", "Länk till utlysningen"),
                                                fieldKey: "primaryLink",
                                                width: nil,
                                                content: AnyView(textField(optionalBinding(\.primaryLink), label: language.text("Link to grant call", "Länk till utlysningen")))
                                            )
                                            compactField(
                                                title: language.text("Link to application", "Länk till ansökan"),
                                                fieldKey: "secondaryLink",
                                                width: nil,
                                                content: AnyView(textField(optionalBinding(\.secondaryLink), label: language.text("Link to application", "Länk till ansökan")))
                                            )
                                        }
                                    }
                                }
                            }
                        }

                        if !showsApplicationSpecificSections {
                            hiddenApplicationDetailsNote(language: language)
                        }

                        if showsGrantedFollowUpPanel {
                            DetailGroup(title: language.text("Grant", "Anslag"), showsSurface: false) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top, spacing: 14) {
                                        compactField(
                                            title: language.text("Displayed as", "Anges som"),
                                            fieldKey: "receivedDisplayName",
                                            width: nil,
                                            content: AnyView(textField(optionalBinding(\.receivedDisplayName), label: language.text("Displayed as", "Anges som")))
                                        )
                                        compactField(
                                            title: language.text("Project number", "Projektnummer"),
                                            fieldKey: "receivedProjectNumber",
                                            width: nil,
                                            content: AnyView(textField(optionalBinding(\.receivedProjectNumber), label: language.text("Project number", "Projektnummer")))
                                        )
                                        compactField(
                                            title: "PEOE",
                                            fieldKey: "receivedPEOE",
                                            width: nil,
                                            content: AnyView(textField(optionalBinding(\.receivedPEOE), label: "PEOE"))
                                        )
                                    }

                                    HStack(alignment: .top, spacing: 14) {
                                        compactField(
                                            title: language.text("Granted amount", "Beviljat belopp"),
                                            fieldKey: "grantedAmount",
                                            width: nil,
                                            content: AnyView(amountFieldWithStaticCurrencySuffix(amountBinding(\.grantedAmount), code: applicationCurrencyCode, language: language))
                                        )
                                        if showsFullGrantedFollowUpPanel {
                                            compactField(
                                                title: language.text("Amount consumed", "Förbrukat belopp"),
                                                width: nil,
                                                content: AnyView(ReadOnlyValue(text: consumedAmountDisplay))
                                            )
                                            compactField(
                                                title: language.text("Remaining amount", "Kvarvarande belopp"),
                                                width: nil,
                                                content: AnyView(ReadOnlyValue(text: remainingGrantedDisplay))
                                            )
                                        }
                                    }

                                    if showsFullGrantedFollowUpPanel {
                                        grantConsumptionPeriodsSection(language: language)
                                    }

                                    HStack(alignment: .top, spacing: 14) {
                                        if showsFullGrantedFollowUpPanel {
                                            compactField(
                                                title: language.text("Repayment", "Återgälda"),
                                                fieldKey: "receivedRepaymentRequirement",
                                                width: nil,
                                                content: AnyView(
                                                    AppTextEditorField(
                                                        title: nil,
                                                        text: optionalTextAreaBinding(\.receivedRepaymentRequirement),
                                                        minimumHeight: 58
                                                    )
                                                )
                                            )
                                            compactField(
                                                title: language.text("Report by", "Återrapporteras senast"),
                                                fieldKey: "receivedRepaymentDueOn",
                                                width: 190,
                                                content: AnyView(
                                                    CommitDateFieldWithTodayButton(
                                                        placeholder: "YYYY-MM-DD",
                                                        text: optionalBinding(\.receivedRepaymentDueOn),
                                                        formatter: normalizeSalaryDateInput,
                                                        updatesContinuously: false,
                                                        width: 120
                                                    )
                                                )
                                            )
                                            compactField(
                                                title: language.text("Reported on", "Återrapporterat"),
                                                fieldKey: "receivedRepaidOn",
                                                width: 150,
                                                content: AnyView(
                                                    CommitDateFieldWithTodayButton(
                                                        placeholder: "YYYY-MM-DD",
                                                        text: optionalBinding(\.receivedRepaidOn),
                                                        formatter: normalizeSalaryDateInput,
                                                        updatesContinuously: false,
                                                        width: 120
                                                    )
                                                )
                                            )
                                        }
                                    }
                                }
                                .id("granted-section")
                            }
                        }

                        if !draft.isEditingLocked || CentralTaskListSection.hasIncompleteTasks(
                            store: store,
                            linkKind: .application,
                            targetID: draft.id
                        ) {
                            DetailGroup(
                                title: language.text("Task list", "Uppgiftslista"),
                                showsSurface: false,
                                titleActionTitle: draft.isEditingLocked ? nil : language.text("Add task", "Lägg till uppgift"),
                                titleAction: {
                                    CentralTaskListSection.addTask(store: store, linkKind: .application, targetID: draft.id)
                                }
                            ) {
                                centralTaskList(language: language)
                            }
                        }

                        applicationActivitiesSection(language: language)

                        applicationStatisticsSection(language: language)
                    }
                    }
                }
                .padding(AppPalette.sectionPadding)
            }
            .onAppear {
                scheduleDeferredSections {
                    scheduleCalendarEventsRefresh()
                    if focusGrantedSection, showsGrantedFollowUpPanel {
                        proxy.scrollTo("granted-section", anchor: .top)
                    }
                }
            }
        }
        .background(AppPalette.detailPanelSurface)
        .floatingDocumentContent(
            id: "application-document-\(draft.id)",
            title: language.text("Grant document", "Anslagsdokument")
        ) {
            ApplicationDocumentPanelContent(store: store, applicationID: draft.id)
        }
        .flushPendingAutosaveOnTextEnd(requestImmediateAutosave)
        .onChange(of: application) { _, newValue in
            if newValue.id != draft.id {
                autosaveTask?.cancel()
                persistDraftIfNeeded()
                coApplicantIdentity.reconcileExternal(newValue.coApplicants)
                draft = newValue
                currentSelectionID = initialSelectionID
                criteriaText = newValue.applicantCriteria ?? newValue.projectCriteria ?? ""
                pendingCoApplicantName = ""
                scheduleDeferredSections(forceReset: true) {
                    scheduleCalendarEventsRefresh()
                }
                return
            }
            if newValue == pendingDraft {
                autosaveTask?.cancel()
                return
            }
            if hasChanges {
                return
            }
            autosaveTask?.cancel()
            coApplicantIdentity.reconcileExternal(newValue.coApplicants)
            draft = newValue
            criteriaText = newValue.applicantCriteria ?? newValue.projectCriteria ?? ""
            scheduleCalendarEventsRefresh()
        }
        .onChange(of: draft) { oldValue, newValue in
            // Round 10: the OH rules in force on the application day count
            // for the whole period; they are read once, when the record gets
            // its application date, and then stay as they are.
            if oldValue.id == newValue.id,
               oldValue.appliedOn?.trimmedOrNil == nil,
               newValue.appliedOn?.trimmedOrNil != nil {
                copyOverheadDefaultsForApplicationDay()
            }
            scheduleAutosave()
        }
        .onChange(of: criteriaText) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: initialSelectionID) { _, newValue in
            currentSelectionID = newValue
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                persistDraftIfNeeded()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                scheduleDeferredSections {
                    scheduleCalendarEventsRefresh()
                }
            } else {
                persistDraftIfNeeded()
            }
        }
        .onReceive(store.$calendarContentGeneration.dropFirst()) { _ in scheduleCalendarEventsRefresh() }
        .onDisappear {
            persistDraftIfNeeded()
        }
    }

    @ViewBuilder
    private func centralTaskList(language: AppLanguage) -> some View {
        CentralTaskListSection(
            store: store,
            linkKind: .application,
            targetID: draft.id,
            language: language,
            reminderOptions: ProjectTaskReminder.allCases,
            isReadOnly: draft.isEditingLocked,
            showsAddButton: false
        )
    }

    private func refreshCalendarEvents() {
        guard isActive else { return }
        cachedCalendarEvents = calendarLinkedEventRows(
            store: store,
            language: store.language,
            scope: .application(draft.id)
        )
    }

    private func scheduleDeferredSections(
        forceReset: Bool = false,
        completion: @escaping () -> Void = {}
    ) {
        showsDeferredSections = true
        completion()
    }

    private func scheduleCalendarEventsRefresh(delay: TimeInterval = 0.25) {
        let applicationID = draft.id
        calendarRefreshToken &+= 1
        let token = calendarRefreshToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isActive,
                  draft.id == applicationID,
                  calendarRefreshToken == token else { return }
            refreshCalendarEvents()
        }
    }

    private var applicationGrantStatisticsIsAvailable: Bool {
        draft.organization.trimmedOrNil != nil
            || draft.organizationID?.trimmedOrNil != nil
            || draft.projectType?.trimmedOrNil != nil
            || draft.projectID?.trimmedOrNil != nil
    }

    /// The applicant group for the composition statistics: the user plus
    /// every co-applicant. A single name means the user applies alone and
    /// the statistics stay hidden.
    private var applicantStatisticsNames: [String] {
        var names = draft.coApplicants.compactMap(\.trimmedOrNil)
        if let currentUser = store.currentUserAuthor()?.name.trimmedOrNil,
           !names.contains(where: { $0.caseInsensitiveCompare(currentUser) == .orderedSame }) {
            names.insert(currentUser, at: 0)
        }
        return names
    }

    /// Upcoming and completed activities linked to the grant, with the
    /// compact activity statistics to the right — same layout as the
    /// publication editor's Aktiviteter section.
    @ViewBuilder
    private func applicationActivitiesSection(language: AppLanguage) -> some View {
        let meetingSummary = calendarMeetingHoursSummary(
            store: store,
            scope: .application(draft.id)
        )
        let hasMeetings = meetingSummary.completedMeetingCount + meetingSummary.plannedMeetingCount > 0
        let todayStart = Calendar.current.startOfDay(for: Date())
        let upcoming = cachedCalendarEvents
            .filter { $0.displayDate >= todayStart }
            .sorted { $0.displayDate < $1.displayDate }
        let past = cachedCalendarEvents
            .filter { $0.displayDate < todayStart }
            .sorted { $0.displayDate > $1.displayDate }

        if !cachedCalendarEvents.isEmpty || hasMeetings {
            DetailGroup(title: language.text("Activities", "Aktiviteter"), showsSurface: false) {
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

                    if showsInlineStatistics, hasMeetings {
                        CalendarMeetingCompactStatisticsSection(
                            summary: meetingSummary,
                            language: language
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
    }

    /// Compact inline statistics at the bottom of the editor: the outcome
    /// bars for the project's grants and for the funder's grants (including
    /// this one). Both categories always render — with an explicit "no
    /// previous grants" note when one is empty. Hidden entirely by the
    /// navigation-rail statistics toggle.
    @ViewBuilder
    private func applicationStatisticsSection(language: AppLanguage) -> some View {
        if showsInlineStatistics, applicationGrantStatisticsIsAvailable {
            let projectApplications = store.applications.filter(editorApplicationMatchesProject)
            let funderApplications = store.applications.filter(editorApplicationMatchesFunder)
            DetailGroup(title: language.text("Statistics", "Statistik"), showsSurface: false) {
                VStack(alignment: .leading, spacing: 12) {
                    applicationOutcomeStatistics(
                        projectApplications,
                        title: language.text("The project's grants", "Projektets anslag"),
                        language: language
                    )
                    applicationOutcomeStatistics(
                        funderApplications,
                        title: language.text("The funder's grants", "Anslagsgivarens anslag"),
                        language: language
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func applicationOutcomeStatistics(
        _ applications: [GrantApplication],
        title: String,
        language: AppLanguage
    ) -> some View {
        if applications.contains(where: { !$0.isToApplyStatus }) {
            GrantOutcomeCompactRows(
                store: store,
                applications: applications,
                language: language,
                title: title
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.bottom, 2)
                Text(language.text("There are no previous grants.", "Inga tidigare anslag finns."))
                    .font(appFont(.body))
                    .foregroundStyle(.secondary)
            }
            .inlineStatisticsSurface()
        }
    }

    private func editorApplicationMatchesProject(_ row: GrantApplication) -> Bool {
        let currentProjectID = draft.projectID?.trimmedOrNil
        let rowProjectID = row.projectID?.trimmedOrNil
        if let currentProjectID, let rowProjectID, currentProjectID == rowProjectID {
            return true
        }
        let currentProjectName = draft.projectType?.trimmedOrNil
        let rowProjectName = row.projectType?.trimmedOrNil
        guard let currentProjectName, let rowProjectName else { return false }
        return normalizedApplicationGrantStatisticsKey(currentProjectName) == normalizedApplicationGrantStatisticsKey(rowProjectName)
    }

    private func editorApplicationMatchesFunder(_ row: GrantApplication) -> Bool {
        let currentOrganizationID = draft.organizationID?.trimmedOrNil
        let rowOrganizationID = row.organizationID?.trimmedOrNil
        if let currentOrganizationID, let rowOrganizationID, currentOrganizationID == rowOrganizationID {
            return true
        }
        let currentOrganizationName = draft.organization.trimmedOrNil
        let rowOrganizationName = row.organization.trimmedOrNil
        guard let currentOrganizationName, let rowOrganizationName else { return false }
        return normalizedApplicationGrantStatisticsKey(currentOrganizationName) == normalizedApplicationGrantStatisticsKey(rowOrganizationName)
    }

    private func header(language: AppLanguage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if draft.isEditingLocked {
                    Text(store.organizationLabel(for: draft, language: language).trimmedOrNil ?? language.text("Funder", "Anslagsgivare"))
                        .appTypography(.pageTitle)
                        .foregroundStyle(AppPalette.appText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    organizationPicker(language: language)
                        .undoRevealPulse(
                            triggerID: store.undoRevealRequest?.id,
                            isActive: undoRevealIsActive(fieldKey: "organization")
                        )
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if draft.isEditingLocked {
                        Text(draft.localizedGrantName(language: language).trimmedOrNil ?? language.text("Grant title", "Anslagstitel"))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppPalette.appText)
                    } else {
                        AppInlineTitleTextField(
                            placeholder: language.text("Grant title", "Anslagstitel"),
                            text: localizedGrantNameBinding,
                            font: .systemFont(ofSize: 24, weight: .bold),
                            minHeight: 30
                        )
                        .undoRevealPulse(
                            triggerID: store.undoRevealRequest?.id,
                            isActive: undoRevealIsActive(fieldKey: "grantName")
                        )
                    }

                    titleLinks(language: language)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            copyToNextYearButton(language: language)
            applicationEditorLockButton(language: language)

            if !draft.isEditingLocked {
                DeleteActionButton(
                    title: language.text("Delete", "Ta bort"),
                    cancelTitle: language.text("Cancel", "Avbryt")
                ) {
                    store.deleteApplication(id: application.id)
                }
            }
        }
        .zIndex(20)
    }

    /// "Kopiera till nästa år": next year's record for the same call, with
    /// every date one year later; opens the copy. Works on locked records too.
    private func copyToNextYearButton(language: AppLanguage) -> some View {
        Button {
            persistDraftIfNeeded()
            guard let newID = store.copyApplicationToNextYear(id: application.id),
                  let copy = store.applications.first(where: { $0.id == newID }) else { return }
            store.openRoute(for: copy)
        } label: {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppPalette.linkAction)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(language.text(
            "Copy to next year: a new record for the same call with every date one year later",
            "Kopiera till nästa år: en ny post för samma utlysning med alla datum ett år senare"
        ))
        .accessibilityLabel(language.text("Copy to next year", "Kopiera till nästa år"))
    }

    private func applicationEditorLockButton(language: AppLanguage) -> some View {
        AppEditorLockButton(isLocked: draft.isEditingLocked, language: language) {
            setEditingLocked(!draft.isEditingLocked)
        }
    }

    private func setEditingLocked(_ isLocked: Bool) {
        if isLocked {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        draft.isEditingLocked = isLocked
        persistDraftIfNeeded()
    }

    @ViewBuilder
    private func inlineDataQualityPanel(language: AppLanguage) -> some View {
        let issues = store.missingFieldIssues()
            .filter { $0.destination == .applications && $0.recordID == draft.id }
            .map {
                AppInlineDataQualityIssue(
                    id: $0.id,
                    title: $0.missingFields.joined(separator: ", "),
                    details: $0.suggestedFix.nonEmpty ?? $0.whyFlagged,
                    severity: $0.severity
                )
            }

        AppInlineDataQualityPanel(
            title: language.text("This record has data quality notes", "Den här posten har datakvalitetsnotiser"),
            issues: issues,
            openTitle: language.text("Open", "Öppna"),
            openAction: {
                store.openIssue(destination: .applications, recordID: draft.id)
            }
        )
        .padding(.top, 8)
    }

    @ViewBuilder
    private func titleLinks(language: AppLanguage) -> some View {
        if let url = normalizedWebLinkURL(draft.primaryLink?.nonEmpty) {
            Link(destination: url) {
                titleLinkLabel(language.text("call", "utlysning"))
            }
            .foregroundStyle(AppPalette.linkAction)
            .help(language.text("Open call link on the web", "Öppna utlysningslänk på webben"))
        }
        if let url = normalizedWebLinkURL(draft.secondaryLink?.nonEmpty) {
            Link(destination: url) {
                titleLinkLabel(language.text("application", "ansökan"))
            }
            .foregroundStyle(AppPalette.linkAction)
            .help(language.text("Open application link on the web", "Öppna ansökningslänk på webben"))
        }
    }

    private func titleLinkLabel(_ title: String) -> some View {
        AppInlineLinkLabel(title: title, systemImage: AppLinkDestinationKind.web.systemImage, fontSize: 13)
    }

    private func organizationPicker(language: AppLanguage) -> some View {
        AutocompleteSelectionField(
            text: organizationTextBinding(language: language),
            options: organizationOptionsForApplications(language: language),
            placeholder: language.text("Funder", "Anslagsgivare"),
            addNewTitle: language.text("Add new", "Lägg till ny"),
            display: { $0 },
            onCommit: {
                commitOrganizationSelection(language: language)
            },
            onSelect: { selectedName in
                applyOrganizationSelection(selectedName, language: language)
            },
            onAddNew: {
                store.beginAddingOrganization(fromApplicationID: draft.id)
            },
            usesTransparentFieldStyle: false,
            showsSuggestionsWithoutQuery: true,
            appliesChrome: false,
            textFont: appNSFont(.pageTitle)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func organizationOptionsForApplications(language: AppLanguage) -> [String] {
        applicationOrganizationAutocompleteOptions(
            organizations: store.organizations,
            applications: store.applications,
            selectedOrganizationID: draft.organizationID,
            selectedOrganizationName: draft.organization,
            language: language
        )
    }

    private func projectPicker(language: AppLanguage) -> some View {
        let selectedProject = draft.projectID.flatMap { store.project(id: $0) }
            ?? draft.projectType.flatMap { store.project(named: $0) }
        return HStack(spacing: 6) {
            if draft.isEditingLocked {
                lockedApplicationValueText(selectedProject?.displayName(for: language) ?? draft.projectType)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                AutocompleteSelectionField(
                    text: projectTextBinding(language: language),
                    options: projectOptionsForCurrentOpenDate().map { $0.displayName(for: language) },
                    placeholder: language.text("Project", "Projekt"),
                    addNewTitle: language.text("Add new", "Lägg till ny"),
                    display: { $0 },
                    onCommit: {
                        commitProjectSelection(language: language)
                    },
                    onSelect: { selectedName in
                        applyProjectSelection(selectedName, language: language)
                    },
                    onAddNew: {
                        store.beginAddingProject(fromApplicationID: draft.id)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !draft.isEditingLocked || selectedProject != nil {
                AppDestinationActionButton(
                    kind: .app,
                    language: language,
                    title: language.text("Open project", "Öppna projekt"),
                    fontSize: 12,
                    tint: selectedProject == nil ? Color.secondary.opacity(0.55) : AppPalette.linkAction,
                    isEnabled: selectedProject != nil
                ) {
                    guard let selectedProject else { return }
                    store.openRoute(for: selectedProject)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func organizationTextBinding(language: AppLanguage) -> Binding<String> {
        Binding(
            get: {
                if let option = draft.organizationID.flatMap({ store.organization(id: $0) })
                    ?? store.organization(matchingName: draft.organization) {
                    return option.displayName(for: language)
                }
                return draft.organization
            },
            set: { newValue in
                applyOrganizationSelection(newValue, language: language)
            }
        )
    }

    private func projectTextBinding(language: AppLanguage) -> Binding<String> {
        Binding(
            get: {
                guard draft.projectID != nil || draft.projectType != nil else { return "" }
                if let option = draft.projectID.flatMap({ store.project(id: $0) })
                    ?? draft.projectType.flatMap({ store.project(named: $0) }) {
                    return option.displayName(for: language)
                }
                return draft.projectType ?? ""
            },
            set: { newValue in
                applyProjectSelection(newValue, language: language)
            }
        )
    }

    private func commitOrganizationSelection(language: AppLanguage) {
        applyOrganizationSelection(organizationTextBinding(language: language).wrappedValue, language: language)
    }

    private func applyOrganizationSelection(_ value: String, language: AppLanguage) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousFunderID = draft.organizationID
        guard !trimmed.isEmpty else {
            draft.organizationID = nil
            draft.organization = ""
            draft.grantCategory = nil
            return
        }

        if let option = store.organizations.first(where: { organizationMatches($0, trimmed: trimmed, language: language) }) {
            draft.organizationID = option.id
            draft.organization = option.nameSv
        } else {
            draft.organizationID = nil
            draft.organization = trimmed
        }
        if draft.organizationID != previousFunderID {
            applyPreferredFundManagerIfEmpty()
            copyOverheadDefaultsIntoDraft()
        }
    }

    /// Round 10: a record without a fund manager gets the funder's
    /// "Prioriterad förvaltare" (or the default in Settings).
    private func applyPreferredFundManagerIfEmpty() {
        guard !draft.isEditingLocked,
              draft.applicationManagerID?.trimmedOrNil == nil,
              draft.applicationManager?.trimmedOrNil == nil,
              let preferred = store.preferredFundManagerOrganization(forFunderID: draft.organizationID) else { return }
        draft.applicationManagerID = preferred.id
        draft.applicationManager = preferred.nameSv
    }

    /// Round 10: when the funder or the fund manager is chosen, the record
    /// gets copies of their OH numbers. They can be changed afterwards, and a
    /// later change on the organizations never reaches this record.
    private func copyOverheadDefaultsIntoDraft() {
        guard !draft.isEditingLocked, draft.isNotYetApplied else { return }
        let managerID = store.linkedFundManager(of: draft)?.id
        draft.applyOverheadDefaults(store.overheadDefaults(forFunderID: draft.organizationID, managerID: managerID))
    }

    /// When the record gets its application date: the numbers in force that
    /// day, unless they were typed by hand. After this they never change.
    private func copyOverheadDefaultsForApplicationDay() {
        guard !draft.isEditingLocked else { return }
        let managerID = store.linkedFundManager(of: draft)?.id
        draft.applyOverheadDefaults(store.overheadDefaults(
            forFunderID: draft.organizationID,
            managerID: managerID,
            on: draft.overheadDefaultsDate
        ))
    }

    private func commitProjectSelection(language: AppLanguage) {
        applyProjectSelection(projectTextBinding(language: language).wrappedValue, language: language)
    }

    private func applyProjectSelection(_ value: String, language: AppLanguage) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft.projectID = nil
            draft.projectType = nil
            return
        }

        if let option = projectOptionsForCurrentOpenDate().first(where: { projectMatches($0, trimmed: trimmed, language: language) }) {
            draft.projectID = option.id
            draft.projectType = option.nameSv
            if draft.coApplicants.isEmpty,
               !option.collaboratorNames.isEmpty {
                coApplicantIdentity.reconcileExternal(option.collaboratorNames)
                draft.coApplicants = option.collaboratorNames
            }
        } else {
            draft.projectID = nil
            draft.projectType = trimmed
        }
    }

    private func organizationMatches(_ option: OrganizationRecord, trimmed: String, language: AppLanguage) -> Bool {
        if option.displayName(for: language).localizedCaseInsensitiveCompare(trimmed) == .orderedSame {
            return true
        }
        if option.nameSv.localizedCaseInsensitiveCompare(trimmed) == .orderedSame {
            return true
        }
        if let nameEn = option.nameEn.nonEmpty,
           nameEn.localizedCaseInsensitiveCompare(trimmed) == .orderedSame {
            return true
        }
        return false
    }

    private func projectMatches(_ option: ProjectRecord, trimmed: String, language: AppLanguage) -> Bool {
        if option.displayName(for: language).localizedCaseInsensitiveCompare(trimmed) == .orderedSame {
            return true
        }
        if option.nameSv.localizedCaseInsensitiveCompare(trimmed) == .orderedSame {
            return true
        }
        if let nameEn = option.nameEn.nonEmpty,
           nameEn.localizedCaseInsensitiveCompare(trimmed) == .orderedSame {
            return true
        }
        return false
    }

    private func projectOptionsForCurrentOpenDate() -> [ProjectRecord] {
        guard let openDate = draft.openDate else {
            return store.projects
        }
        let today = Calendar.current.startOfDay(for: Date())
        let openDay = Calendar.current.startOfDay(for: openDate)
        guard openDay > today else {
            return store.projects
        }
        return store.projects.filter { !$0.isArchived }
    }

    @ViewBuilder
    private func renewedMenuField<Value: Hashable>(
        selection: Binding<Value>,
        options: [(label: String, value: Value)],
        placeholder: String? = nil
    ) -> some View {
        if draft.isEditingLocked {
            lockedApplicationValueText(options.first(where: { $0.value == selection.wrappedValue })?.label ?? placeholder)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
        AppMenuSelectionField(
            selection: selection,
            options: options,
            placeholder: placeholder
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func grantCategoryPicker(language: AppLanguage) -> some View {
        let selection = Binding<String?>(get: { draft.grantCategory }, set: { draft.grantCategory = $0 })
        if draft.isEditingLocked {
            lockedApplicationValueText(draft.grantCategory.map { language.localizedGrantCategory($0) })
        } else if AppRuntime.usesRenewedChrome {
            renewedMenuField(
                selection: selection,
                options: [(language.text("Select category", "Välj kategori"), String?.none)]
                    + GrantParsing.grantCategoryOptions.map { (language.localizedGrantCategory($0), Optional($0)) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Picker("", selection: selection) {
                Text(language.text("Select category", "Välj kategori")).tag(String?.none)
                ForEach(GrantParsing.grantCategoryOptions, id: \.self) { value in
                    Text(language.localizedGrantCategory(value)).tag(Optional(value))
                }
            }
            .pickerStyle(.menu)
            .formKeyboardNavigable()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func managerPicker(language: AppLanguage) -> some View {
        let selection = Binding<String?>(
            // "Alla kopplingar via id": the linked fund manager's current name.
            get: { draft.applicationManagerID.flatMap { store.manager(id: $0)?.nameSv } ?? draft.applicationManager },
            set: { newValue in
                guard newValue != addNewToken else {
                    store.beginAddingManager(fromApplicationID: draft.id)
                    return
                }
                let previousManagerID = draft.applicationManagerID
                draft.applicationManagerID = newValue.flatMap { store.manager(matchingName: $0)?.id }
                draft.applicationManager = newValue
                if draft.applicationManagerID != previousManagerID {
                    copyOverheadDefaultsIntoDraft()
                }
            }
        )
        let selectedManager = draft.applicationManagerID.flatMap { store.manager(id: $0) }
            ?? draft.applicationManager.flatMap { store.manager(matchingName: $0) }

        HStack(spacing: 6) {
            if draft.isEditingLocked {
                lockedApplicationValueText(selectedManager?.displayName(for: language) ?? draft.applicationManager)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if AppRuntime.usesRenewedChrome {
                renewedMenuField(
                    selection: selection,
                    options: [(language.text("Select fund manager", "Välj medelsförvaltare"), String?.none),
                              (language.text("Add new", "Lägg till ny"), Optional(addNewToken))]
                        + store.managers.map { ($0.displayName(for: language), Optional($0.nameSv)) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("", selection: selection) {
                    Text(language.text("Select fund manager", "Välj medelsförvaltare")).tag(String?.none)
                    Text(language.text("Add new", "Lägg till ny")).tag(Optional(addNewToken))
                    ForEach(store.managers) { manager in
                        Text(manager.displayName(for: language)).tag(Optional(manager.nameSv))
                    }
                }
                .pickerStyle(.menu)
                .formKeyboardNavigable()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !draft.isEditingLocked || selectedManager != nil {
                AppDestinationActionButton(
                    kind: .app,
                    language: language,
                    title: language.text("Open manager", "Öppna ansvarig"),
                    fontSize: 12,
                    tint: selectedManager == nil ? Color.secondary.opacity(0.55) : AppPalette.linkAction,
                    isEnabled: selectedManager != nil
                ) {
                    guard let selectedManager else { return }
                    store.openRoute(for: selectedManager)
                }
            }
        }
    }

    @ViewBuilder
    private func coApplicantPickerArea(language: AppLanguage) -> some View {
        let applicantFieldWidth: CGFloat = ResearcherNameFieldMetrics.compactWidth * 0.8
        let applicantHandleWidth: CGFloat = 20
        let options = coApplicantOptions

        if draft.isEditingLocked {
            lockedCoApplicantList(language: language)
        } else {
        VStack(alignment: .leading, spacing: AppPalette.titleSpacing) {
            VStack(alignment: .leading, spacing: AutocompleteSelectionMetrics.rowSpacing) {
                ForEach(coApplicantIdentity.rows(for: draft.coApplicants)) { row in
                    let index = row.index
                    HStack(spacing: 8) {
                        ReorderHandle(itemID: row.id, draggedItemID: $draggedCoApplicantName, language: language)
                        AutocompleteSelectionField(
                            text: coApplicantBinding(at: index),
                            options: options,
                            excludedOptions: Set(draft.coApplicants.enumerated().compactMap { $0.offset == index ? nil : $0.element }),
                            placeholder: language.text("Select applicant", "Välj sökande"),
                            addNewTitle: language.text("Add new", "Lägg till ny"),
                            display: { coApplicantLabel(for: $0, language: language) },
                            onCommit: {
                                scheduleAutosave()
                            },
                            onAddNew: {
                                store.beginAddingApplicant(fromApplicationID: draft.id, at: index)
                            }
                        )
                        .frame(width: applicantFieldWidth, alignment: .leading)

                        if let author = store.publicationAuthor(matchingPresentedName: draft.coApplicants[index]) {
                            AppRouteLinkButton(
                                title: language.text("Open researcher", "Öppna forskare"),
                                language: language,
                                width: 34
                            ) {
                                store.openRoute(for: author)
                            }
                        }

                        inlineTrashButton {
                            coApplicantIdentity.remove(at: index)
                            draft.coApplicants.remove(at: index)
                        }
                    }
                    .onDrop(of: [UTType.plainText], delegate: StableStringReorderDropDelegate(
                        targetID: row.id,
                        items: $draft.coApplicants,
                        identity: coApplicantIdentity,
                        draggedItemID: $draggedCoApplicantName
                    ))
                }
            }

            HStack(spacing: 8) {
                Color.clear
                    .frame(width: applicantHandleWidth, height: 20)

                AutocompleteSelectionField(
                    text: $pendingCoApplicantName,
                    options: options,
                    excludedOptions: Set(draft.coApplicants),
                    placeholder: language.text("Add applicant", "Lägg till sökande"),
                    addNewTitle: language.text("Add new", "Lägg till ny"),
                    display: { coApplicantLabel(for: $0, language: language) },
                    onCommit: {
                        commitPendingCoApplicant()
                    },
                    onSelect: { selectedName in
                        commitPendingCoApplicant(selectedName)
                    },
                    onAddNew: {
                        store.beginAddingApplicant(fromApplicationID: draft.id, at: draft.coApplicants.count)
                    }
                )
                .frame(width: applicantFieldWidth, alignment: .leading)
            }

            HStack(spacing: 8) {
                Color.clear
                    .frame(width: applicantHandleWidth, height: 20)

                Button(language.text("Replace with…", "Ersätt med…")) {
                    replaceCoApplicantsWithProjectCollaborators()
                }
                .buttonStyle(.bordered)
                .disabled(linkedProject == nil)
                .help(language.text("Replace with project collaborators", "Ersätt med projektmedarbetare"))

                Button(language.text("Complete with project collaborators", "Komplettera med projektmedarbetare")) {
                    appendMissingCoApplicantsFromProjectCollaborators()
                }
                .buttonStyle(.bordered)
                .disabled(linkedProject == nil || !hasMissingProjectCollaborators)

                GroupMailButton(
                    addresses: store.groupMailAddresses(presentedNames: draft.coApplicants),
                    language: language
                )
            }
        }
        .undoRevealPulse(
            triggerID: store.undoRevealRequest?.id,
            isActive: undoRevealIsActive(fieldKey: "coApplicants")
        )
        }
    }

    private func lockedCoApplicantList(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: AutocompleteSelectionMetrics.rowSpacing) {
            if draft.coApplicants.isEmpty {
                AppCompactEmptyListLabel(title: language.text("No records", "Inga poster"))
            } else {
                ForEach(Array(draft.coApplicants.enumerated()), id: \.offset) { _, name in
                    HStack(spacing: 8) {
                        AppPersonNameText(
                            name: name,
                            isCurrentUser: store.isCurrentUserPresentedName(name)
                        )
                            .frame(width: ResearcherNameFieldMetrics.compactWidth * 1.2, alignment: .leading)
                            .frame(minHeight: 22, alignment: .leading)
                        if let author = store.publicationAuthor(matchingPresentedName: name) {
                            AppRouteLinkButton(
                                title: language.text("Open researcher", "Öppna forskare"),
                                language: language,
                                width: 34
                            ) {
                                store.openRoute(for: author)
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                GroupMailButton(
                    addresses: store.groupMailAddresses(presentedNames: draft.coApplicants),
                    language: language
                )
            }
        }
    }

    @ViewBuilder
    private func currencyPicker(language: AppLanguage) -> some View {
        let selection = Binding(get: { draft.currency ?? "SEK" }, set: { draft.currency = $0 })
        let currencyOptions = store.workflowDefaultSettings.currencyPickerOptions(including: draft.currency ?? "SEK")
        if AppRuntime.usesRenewedChrome {
            renewedMenuField(
                selection: selection,
                options: currencyOptions.map { ($0, $0) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Picker("", selection: selection) {
                ForEach(currencyOptions, id: \.self) { currency in
                    Text(currency).tag(currency)
                }
            }
            .pickerStyle(.menu)
            .formKeyboardNavigable()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inlineTrashButton(action: @escaping () -> Void) -> some View {
        AppIconDeleteButton(
            title: "Ta bort",
            font: .system(size: 12, weight: .semibold),
            width: 28,
            action: action
        )
    }

    private func badgeTone(for result: String) -> BadgeTone {
        statusTone(for: result)
    }

    private func textField(_ binding: Binding<String>, label: String) -> some View {
        AppLockableField(isLocked: draft.isEditingLocked, lockedText: binding.wrappedValue) {
            if AppRuntime.usesRenewedChrome {
                CommitFormattingTextField(
                    placeholder: label,
                    text: binding,
                    formatter: { $0 },
                    updatesContinuously: false,
                    showsRenewedSurface: false,
                    isBordered: false
                )
                .frame(minHeight: 18)
                .appTextInputChrome(fillsWidth: true)
            } else {
                CommitFormattingTextField(
                    placeholder: label,
                    text: binding,
                    formatter: { $0 },
                    updatesContinuously: false
                )
                .frame(height: AppPalette.fieldMinHeight)
            }
        }
    }

    private func requiredBinding(_ keyPath: WritableKeyPath<GrantApplication, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<GrantApplication, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.trimmedOrNil }
        )
    }

    private func optionalTextAreaBinding(_ keyPath: WritableKeyPath<GrantApplication, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { newValue in
                draft[keyPath: keyPath] = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private func amountBinding(_ keyPath: WritableKeyPath<GrantApplication, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = GrantParsing.formatAmountInput($0) }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<GrantApplication, Bool>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func coApplicantBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.coApplicants.indices.contains(index) else { return "" }
                return draft.coApplicants[index]
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if draft.coApplicants.indices.contains(index) {
                    if trimmed.isEmpty {
                        coApplicantIdentity.remove(at: index)
                        draft.coApplicants.remove(at: index)
                    } else {
                        coApplicantIdentity.updateValue(at: index, to: trimmed)
                        draft.coApplicants[index] = trimmed
                    }
                }
            }
        )
    }

    private func commitPendingCoApplicant(_ selectedName: String? = nil) {
        let trimmed = (selectedName ?? pendingCoApplicantName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !draft.coApplicants.contains(where: {
            normalizedApplicantName($0) == normalizedApplicantName(trimmed)
        }) else {
            pendingCoApplicantName = ""
            return
        }
        coApplicantIdentity.append(value: trimmed)
        draft.coApplicants.append(trimmed)
        pendingCoApplicantName = ""
        flushAutosaveNow()
    }

    private func normalizedApplicantName(_ name: String) -> String {
        PublicationDerivation.normalizedName(name)
    }

    private func uniquedApplicantNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.compactMap(\.trimmedOrNil).filter { name in
            let normalized = normalizedApplicantName(name)
            guard !normalized.isEmpty else { return false }
            return seen.insert(normalized).inserted
        }
    }

    private func replaceCoApplicantsWithProjectCollaborators() {
        guard linkedProject != nil else { return }
        let updated = linkedProjectCollaboratorNames
        guard draft.coApplicants != updated else { return }
        pendingCoApplicantName = ""
        coApplicantIdentity.reconcileExternal(updated)
        draft.coApplicants = updated
        flushAutosaveNow()
    }

    private func appendMissingCoApplicantsFromProjectCollaborators() {
        guard linkedProject != nil else { return }
        let existingNames = Set(
            draft.coApplicants
                .map(normalizedApplicantName)
                .filter { !$0.isEmpty }
        )
        let missingNames = linkedProjectCollaboratorNames.filter {
            !existingNames.contains(normalizedApplicantName($0))
        }
        guard !missingNames.isEmpty else { return }
        pendingCoApplicantName = ""
        missingNames.forEach { coApplicantIdentity.append(value: $0) }
        draft.coApplicants += missingNames
        flushAutosaveNow()
    }

    private func coApplicantLabel(for name: String, language: AppLanguage) -> String {
        return name
    }

    private func optionalDateStringBinding(_ keyPath: WritableKeyPath<GrantApplication, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = DateParsers.canonicalizedDayInput($0).trimmedOrNil }
        )
    }

    @ViewBuilder
    private func localizedOptionPicker<T: LocalizedNamedRecord>(selection: Binding<String>, options: [T], placeholder: String, language: AppLanguage) -> some View {
        if AppRuntime.usesRenewedChrome {
            renewedMenuField(
                selection: selection,
                options: [(placeholder, "")]
                    + options.map { ($0.displayName(for: language), $0.nameSv) },
                placeholder: placeholder
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Picker("", selection: selection) {
                Text(placeholder).tag("")
                ForEach(options) { option in
                    Text(option.displayName(for: language)).tag(option.nameSv)
                }
            }
            .pickerStyle(.menu)
            .formKeyboardNavigable()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func localizedOptionPicker<T: LocalizedNamedRecord>(selection: Binding<String>, options: [T], placeholder: String, language: AppLanguage, label: @escaping (T) -> String) -> some View {
        if AppRuntime.usesRenewedChrome {
            renewedMenuField(
                selection: selection,
                options: [(placeholder, "")]
                    + options.map { (label($0), $0.nameSv) },
                placeholder: placeholder
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Picker("", selection: selection) {
                Text(placeholder).tag("")
                ForEach(options) { option in
                    Text(label(option)).tag(option.nameSv)
                }
            }
            .pickerStyle(.menu)
            .formKeyboardNavigable()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func localizedOptionPicker<T: LocalizedNamedRecord>(selection: Binding<String?>, options: [T], placeholder: String, language: AppLanguage) -> some View {
        if AppRuntime.usesRenewedChrome {
            renewedMenuField(
                selection: selection,
                options: [(placeholder, String?.none)]
                    + options.map { ($0.displayName(for: language), Optional($0.nameSv)) },
                placeholder: placeholder
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Picker("", selection: selection) {
                Text(placeholder).tag(String?.none)
                ForEach(options) { option in
                    Text(option.displayName(for: language)).tag(Optional(option.nameSv))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func amountFieldWithCurrency(_ amount: Binding<String>, language: AppLanguage) -> some View {
        HStack(spacing: AppRuntime.usesRenewedChrome ? 8 : 10) {
            if draft.isEditingLocked {
                lockedApplicationValueText(amount.wrappedValue)
            } else if AppRuntime.usesRenewedChrome {
                CommitFormattingTextField(
                    placeholder: language.text("Amount", "Belopp"),
                    text: amount,
                    formatter: { $0 },
                    updatesContinuously: false,
                    showsRenewedSurface: false,
                    isBordered: false
                )
                .frame(minHeight: 18)
                .appTextInputChrome(fillsWidth: true)
            } else {
                CommitFormattingTextField(
                    placeholder: language.text("Amount", "Belopp"),
                    text: amount,
                    formatter: { $0 },
                    updatesContinuously: false
                )
                .frame(height: AppPalette.fieldMinHeight)
            }
            if draft.isEditingLocked {
                lockedApplicationValueText(applicationCurrencyCode)
                    .frame(width: 90, alignment: .leading)
            } else {
                currencyPicker(language: language)
                    .frame(width: 90)
            }
        }
    }

    private func amountFieldWithStaticCurrencySuffix(
        _ amount: Binding<String>,
        code: String,
        language: AppLanguage,
        respectsApplicationLock: Bool = true
    ) -> some View {
        HStack(spacing: AppRuntime.usesRenewedChrome ? 8 : 10) {
            if draft.isEditingLocked && respectsApplicationLock {
                lockedApplicationValueText(amount.wrappedValue)
            } else if AppRuntime.usesRenewedChrome {
                CommitFormattingTextField(
                    placeholder: language.text("Amount", "Belopp"),
                    text: amount,
                    formatter: { $0 },
                    updatesContinuously: false,
                    showsRenewedSurface: false,
                    isBordered: false
                )
                .frame(minHeight: 18)
                .appTextInputChrome(fillsWidth: true)
            } else {
                CommitFormattingTextField(
                    placeholder: language.text("Amount", "Belopp"),
                    text: amount,
                    formatter: { $0 },
                    updatesContinuously: false
                )
                .frame(height: AppPalette.fieldMinHeight)
            }

            Text(code)
                .appTypography(.tableHeader)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var localizedGrantNameBinding: Binding<String> {
        Binding(
            get: { draft.localizedGrantName(language: store.language) },
            set: { newValue in
                draft.setLocalizedGrantName(newValue, language: store.language)
            }
        )
    }

    @ViewBuilder
    private func compactField(title: String, fieldKey: String? = nil, width: CGFloat?, help: String? = nil, content: AnyView) -> some View {
        if draft.isEditingLocked,
           let fieldKey,
           !lockedApplicationFieldShouldShow(fieldKey) {
            EmptyView()
        } else {
            let field = AppCompactField(title, width: width, help: help, fillsAvailableWidth: width == nil) {
                content
            }
            .undoRevealPulse(
                triggerID: store.undoRevealRequest?.id,
                isActive: fieldKey.map { undoRevealIsActive(fieldKey: $0) } ?? false
            )
            field
        }
    }

    private func lockedApplicationValueText(_ value: String?) -> some View {
        AppLockedFieldValueText(text: value)
    }

    private var criteriaTextAreaMinimumHeight: CGFloat {
        let text = criteriaText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 54 }
        let estimatedCharactersPerLine = 105
        let estimatedLineCount = text
            .components(separatedBy: .newlines)
            .reduce(0) { partial, line in
                partial + max(1, Int(ceil(Double(line.count) / Double(estimatedCharactersPerLine))))
            }
        return max(54, CGFloat(estimatedLineCount) * 20 + 34)
    }

    private func lockedApplicationFieldShouldShow(_ fieldKey: String) -> Bool {
        switch fieldKey {
        case "organization":
            return draft.organization.trimmedOrNil != nil
        case "grantName":
            return draft.grantName.trimmedOrNil != nil
        case "maxAmount":
            return draft.maxAmount?.trimmedOrNil != nil
        case "yearCount":
            return draft.yearCount?.trimmedOrNil != nil
        case "maximumTotalAmount":
            return draft.maximumTotalAmountValue != nil
        case "employmentPercentage":
            return draft.employmentPercentage?.trimmedOrNil != nil
        case "employmentMonths":
            return draft.employmentMonths?.trimmedOrNil != nil
        case "salaryIncludesOverhead":
            return salaryOverheadShouldShowWhenLocked
        case "primaryLink":
            return draft.primaryLink?.trimmedOrNil != nil
        case "secondaryLink":
            return draft.secondaryLink?.trimmedOrNil != nil
        case "project":
            return draft.projectID?.trimmedOrNil != nil || draft.projectType?.trimmedOrNil != nil
        case "applicationTitle":
            return draft.applicationTitle?.trimmedOrNil != nil
        case "appliedAmount":
            return draft.appliedAmount?.trimmedOrNil != nil
        case "appliedCaseNumber":
            return draft.appliedCaseNumber?.trimmedOrNil != nil
        case "applicationManager":
            return draft.applicationManager?.trimmedOrNil != nil
        case "managerReason":
            return draft.managerReason?.trimmedOrNil != nil
        case "funderMaxOverheadPercent":
            return draft.funderMaxOverheadPercent != nil
        case "managerOverheadPercent":
            return draft.managerOverheadPercent != nil
        case "cofundingDecision":
            return draft.cofundingDecision != nil
        case "institutionCaseNumber":
            return draft.institutionCaseNumber?.trimmedOrNil != nil
        case "receivedDisplayName":
            return draft.receivedDisplayName?.trimmedOrNil != nil
        case "receivedProjectNumber":
            return draft.receivedProjectNumber?.trimmedOrNil != nil
        case "receivedPEOE":
            return draft.receivedPEOE?.trimmedOrNil != nil
        case "grantedAmount":
            return draft.grantedAmount?.trimmedOrNil != nil
        case "receivedRepaymentRequirement":
            return draft.receivedRepaymentRequirement?.trimmedOrNil != nil
        case "receivedRepaymentDueOn":
            return draft.receivedRepaymentDueOn?.trimmedOrNil != nil
        case "receivedRepaidOn":
            return draft.receivedRepaidOn?.trimmedOrNil != nil
        default:
            return true
        }
    }

    private func approximateAmountBreakdownView(language: AppLanguage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(approximateAmountMetrics(language: language)) { metric in
                VStack(alignment: .leading, spacing: AppRuntime.usesRenewedChrome ? 8 : 6) {
                    Text(metric.label)
                        .appTypography(.fieldLabel)
                        .foregroundStyle(metric.emphasized ? Color.primary : Color.secondary)
                    if draft.isEditingLocked {
                        lockedApplicationValueText(metric.value)
                    } else {
                        ReadOnlyValue(text: metric.value)
                    }
                }
                .frame(
                    minWidth: metric.emphasized ? 164 : 136,
                    idealWidth: metric.emphasized ? 180 : 148,
                    maxWidth: metric.emphasized ? 200 : 164,
                    alignment: .leading
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct OverheadRuleSummaryLine {
        let text: String
        let cofundingText: String?
    }

    /// Round 8: "OH: X % (förvaltarens Y %, anslagsgivarens tak Z %)" for
    /// the budget's first month, and "Behov av samfinansiering: N kr" when
    /// the grant provider pays less OH than the fund manager's full OH.
    /// Shown only when the salary budget includes OH.
    private func overheadRuleSummaryLine(language: AppLanguage) -> OverheadRuleSummaryLine? {
        guard draft.salaryIncludesOverhead,
              let breakdown = approximateAmountBreakdown,
              let calculator = applicationSalaryCalculator(),
              let startMonth = approximationStartMonth else {
            return nil
        }
        let plan = applicationOverheadPlan
        let rates = grantOverheadRates(on: startMonth, calculator: calculator, plan: plan)
        let text = grantOverheadSummaryText(
            managerPercent: rates.manager * 100,
            effectivePercent: rates.effective * 100,
            rule: plan.rule,
            language: language
        )
        let cofundingText: String? = breakdown.cofundingAmount >= 0.5
            ? language.text("Co-funding needed: ", "Behov av samfinansiering: ")
                + CurrencyFormatter.format(breakdown.cofundingAmount, code: "SEK")
            : nil
        return OverheadRuleSummaryLine(text: text, cofundingText: cofundingText)
    }

    // MARK: Round 10: the record's OH numbers and co-funding

    private func percentBinding(_ keyPath: WritableKeyPath<GrantApplication, Double?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath].map { formatOverheadPercentInput(String($0)) } ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let previous = draft[keyPath: keyPath]
                if trimmed.isEmpty {
                    draft[keyPath: keyPath] = nil
                } else if let value = GrantParsing.numericValue(from: trimmed) {
                    draft[keyPath: keyPath] = min(100, max(0, value))
                }
                // A number typed here is kept: the defaults never replace it.
                if draft[keyPath: keyPath] != previous {
                    draft.overheadNumbersSetByHand = true
                }
            }
        )
    }

    private func percentInputField(_ keyPath: WritableKeyPath<GrantApplication, Double?>, placeholder: String) -> some View {
        let binding = percentBinding(keyPath)
        return AppLockableField(isLocked: draft.isEditingLocked, lockedText: binding.wrappedValue) {
            CommitFormattingTextField(
                placeholder: placeholder,
                text: binding,
                formatter: formatOverheadPercentInput,
                updatesContinuously: false
            )
            .appTextInputChrome()
        }
    }

    /// "Förvaltaren samfinansierar": Inte frågat / Ja / Nej, with the day.
    private func cofundingDecisionField(language: AppLanguage) -> some View {
        let notAsked = language.text("Not asked", "Inte frågat")
        return AppLockableField(
            isLocked: draft.isEditingLocked,
            lockedText: [draft.cofundingDecision?.title(language: language) ?? notAsked, draft.cofundingDecisionOn?.trimmedOrNil]
                .compactMap { $0 }
                .joined(separator: ", ")
        ) {
            HStack(spacing: 8) {
                Picker("", selection: Binding<GrantCofundingDecision?>(
                    get: { draft.cofundingDecision },
                    set: { newValue in
                        draft.cofundingDecision = newValue
                        if newValue != nil, draft.cofundingDecisionOn?.trimmedOrNil == nil {
                            draft.cofundingDecisionOn = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
                        }
                    }
                )) {
                    Text(notAsked).tag(GrantCofundingDecision?.none)
                    ForEach(GrantCofundingDecision.allCases, id: \.self) { decision in
                        Text(decision.title(language: language)).tag(Optional(decision))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
                if draft.cofundingDecision != nil {
                    AppDateField(
                        placeholder: "YYYY-MM-DD",
                        text: Binding(
                            get: { draft.cofundingDecisionOn ?? "" },
                            set: { draft.cofundingDecisionOn = $0.trimmedOrNil }
                        ),
                        width: 110
                    )
                }
            }
        }
    }

    /// Shown when the record's numbers leave a gap, and also when the kr
    /// line under the salary budget shows a co-funding need (records whose
    /// numbers are not filled in), so the two never disagree.
    private var showsCofundingQuestion: Bool {
        draft.cofundingOverheadGapPercent > 0
            || (approximateAmountBreakdown?.cofundingAmount ?? 0) >= 0.5
            || draft.cofundingDecision != nil
    }

    private func cofundingExplanation(language: AppLanguage) -> String? {
        guard let manager = draft.managerOverheadPercent,
              let funder = draft.funderMaxOverheadPercent,
              manager > funder else { return nil }
        let managerText = grantFormattedPercent(manager)
        let funderText = grantFormattedPercent(funder)
        let gapText = grantFormattedPercent(manager - funder).replacingOccurrences(of: " %", with: "")
        switch draft.cofundingDecision {
        case .yes?:
            return language.text(
                "The fund manager takes \(managerText) and the funder accepts at most \(funderText). The fund manager co-funds the difference (\(gapText) percentage points).",
                "Förvaltaren tar ut \(managerText) och finansiären godkänner högst \(funderText). Förvaltaren samfinansierar skillnaden (\(gapText) procentenheter)."
            )
        case .no?:
            return language.text(
                "The fund manager takes \(managerText) and the funder accepts at most \(funderText). The fund manager does not co-fund the difference: apply with the region as fund manager and write the reason.",
                "Förvaltaren tar ut \(managerText) och finansiären godkänner högst \(funderText). Förvaltaren samfinansierar inte skillnaden: sök med regionen som förvaltare och skriv skälet."
            )
        case nil:
            return language.text(
                "The fund manager takes \(managerText) but the funder accepts at most \(funderText). The difference (\(gapText) percentage points) needs co-funding: ask the fund manager.",
                "Förvaltaren tar ut \(managerText) men finansiären godkänner högst \(funderText). Skillnaden (\(gapText) procentenheter) behöver samfinansieras: fråga förvaltaren."
            )
        }
    }

    @ViewBuilder
    private func overheadNumbersRow(language: AppLanguage) -> some View {
        let showsNumbers = !draft.isEditingLocked
            || draft.funderMaxOverheadPercent != nil
            || draft.managerOverheadPercent != nil
            || draft.cofundingDecision != nil
        if showsNumbers {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 14) {
                    compactField(
                        title: language.text("Funder accepts OH, at most", "Finansiären godkänner OH, högst"),
                        fieldKey: "funderMaxOverheadPercent",
                        width: 230,
                        help: language.text(
                            "Copied from the funder when the funder or fund manager is chosen. 100 = full OH, 0 = no OH. A later change on the funder does not change this record.",
                            "Kopieras från finansiären när finansiär eller förvaltare väljs. 100 = full OH, 0 = ingen OH. En senare ändring hos finansiären ändrar inte den här posten."
                        ),
                        content: AnyView(percentInputField(\.funderMaxOverheadPercent, placeholder: language.text("Not set", "Inte angiven")))
                    )
                    compactField(
                        title: language.text("Fund manager takes OH", "Förvaltaren tar ut OH"),
                        fieldKey: "managerOverheadPercent",
                        width: 230,
                        help: language.text(
                            "Copied from the fund manager when it is chosen. A later change on the fund manager does not change this record.",
                            "Kopieras från förvaltaren när den väljs. En senare ändring hos förvaltaren ändrar inte den här posten."
                        ),
                        content: AnyView(percentInputField(\.managerOverheadPercent, placeholder: language.text("Not set", "Inte angiven")))
                    )
                    if showsCofundingQuestion {
                        compactField(
                            title: language.text("Fund manager co-funds", "Förvaltaren samfinansierar"),
                            fieldKey: "cofundingDecision",
                            width: nil,
                            content: AnyView(cofundingDecisionField(language: language))
                        )
                    }
                    Spacer(minLength: 0)
                }
                if let explanation = cofundingExplanation(language: language) {
                    Text(explanation)
                        .appTypography(.secondary)
                        .foregroundStyle(draft.cofundingDecision == nil ? AppPalette.vividRed : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// "Ej sökt" hides the application part; this says what is kept there.
    @ViewBuilder
    private func hiddenApplicationDetailsNote(language: AppLanguage) -> some View {
        let otherApplicants = draft.coApplicants.count > (store.isCurrentUserFirstApplicant(draft) ? 1 : 0)
        let titles = draft.hiddenApplicationDetailTitles(hasOtherApplicants: otherApplicants, language: language)
        if !titles.isEmpty {
            Label {
                Text(language.text(
                    "Hidden details from the application part: \(titles.joined(separator: ", ")). They are kept and show again if you change the status.",
                    "Dolda uppgifter från ansökningsdelen: \(titles.joined(separator: ", ")). De finns kvar och visas igen om du ändrar statusen."
                ))
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "eye.slash")
            }
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func overheadRuleSummaryView(language: AppLanguage) -> some View {
        if let summary = overheadRuleSummaryLine(language: language) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.text)
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                if let cofundingText = summary.cofundingText {
                    Text(cofundingText)
                        .appTypography(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func approximateAmountMetrics(language: AppLanguage) -> [ApproximateAmountMetric] {
        // A locked or applied record shows the amount it was saved with, not
        // a new estimate from today's salary calculator.
        if draft.isEditingLocked || !draft.isNotYetApplied {
            return [
                ApproximateAmountMetric(
                    id: "total",
                    label: language.text("Total", "Totalt"),
                    value: draft.approximateAmountValue.map { CurrencyFormatter.format($0, code: "SEK") } ?? "—",
                    emphasized: true
                )
            ]
        }
        guard let approximateAmountBreakdown else {
            return [
                ApproximateAmountMetric(
                    id: "total",
                    label: language.text("Total", "Totalt"),
                    value: "—",
                    emphasized: true
                )
            ]
        }

        let yearlyMetrics = approximateAmountBreakdown.yearlyAmounts.map { row in
            ApproximateAmountMetric(
                id: String(row.year),
                label: String(row.year),
                value: CurrencyFormatter.format(row.amount, code: "SEK"),
                emphasized: false
            )
        }

        return yearlyMetrics + [
            ApproximateAmountMetric(
                id: "total",
                label: language.text("Total", "Totalt"),
                value: CurrencyFormatter.format(approximateAmountBreakdown.totalAmount, code: "SEK"),
                emphasized: true
            )
        ]
    }

    private func formFieldTitle(_ title: String) -> some View {
        AppFieldLabelText(text: title)
    }

    @ViewBuilder
    private func grantConsumptionPeriodsSection(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AppFieldAlignedTableHeaderText(text: language.text("From", "Från"))
                    .frame(width: 120, alignment: .leading)
                AppFieldAlignedTableHeaderText(text: language.text("To", "Till"))
                    .frame(width: 120, alignment: .leading)
                AppFieldAlignedTableHeaderText(text: language.text("Amount", "Belopp"))
                    .frame(width: 180, alignment: .leading)
                Spacer()
            }

            ForEach(sortedConsumptionPeriodIDs, id: \.self) { id in
                HStack(spacing: 10) {
                    CommitDateFieldWithTodayButton(
                        placeholder: "YYYY-MM-DD",
                        text: consumptionPeriodFieldBinding(for: id, keyPath: \.from),
                        formatter: normalizeSalaryDateInput,
                        updatesContinuously: false,
                        width: 120
                    )

                    CommitDateFieldWithTodayButton(
                        placeholder: "YYYY-MM-DD",
                        text: consumptionPeriodFieldBinding(for: id, keyPath: \.to),
                        formatter: normalizeSalaryDateInput,
                        updatesContinuously: false,
                        width: 120
                    )

                    amountFieldWithStaticCurrencySuffix(
                        Binding(
                            get: { consumptionPeriodBinding(for: id).wrappedValue.amount },
                            set: { consumptionPeriodBinding(for: id).wrappedValue.amount = GrantParsing.formatAmountInput($0) ?? "" }
                        ),
                        code: applicationCurrencyCode,
                        language: language,
                        respectsApplicationLock: false
                    )
                    .frame(width: 264)

                    inlineTrashButton {
                        draft.receivedConsumptionPeriods.removeAll { $0.id == id }
                    }
                    Spacer()
                }
            }

            Button(language.text("Add period", "Lägg till period")) {
                draft.receivedConsumptionPeriods.append(GrantConsumptionPeriod())
            }
            .appAddButtonStyle()
        }
    }

    private var sortedConsumptionPeriodIDs: [String] {
        draft.receivedConsumptionPeriods
            .sorted {
                let lhsStart = DateParsers.isoDay.date(from: normalizeSalaryDateInput($0.from)) ?? .distantFuture
                let rhsStart = DateParsers.isoDay.date(from: normalizeSalaryDateInput($1.from)) ?? .distantFuture
                if lhsStart != rhsStart { return lhsStart < rhsStart }
                let lhsEnd = DateParsers.isoDay.date(from: normalizeSalaryDateInput($0.to)) ?? .distantFuture
                let rhsEnd = DateParsers.isoDay.date(from: normalizeSalaryDateInput($1.to)) ?? .distantFuture
                if lhsEnd != rhsEnd { return lhsEnd < rhsEnd }
                let lhsAmount = GrantParsing.numericValue(from: $0.amount) ?? 0
                let rhsAmount = GrantParsing.numericValue(from: $1.amount) ?? 0
                return lhsAmount > rhsAmount
            }
            .map(\.id)
    }

    private func consumptionPeriodBinding(for id: String) -> Binding<GrantConsumptionPeriod> {
        Binding(
            get: {
                draft.receivedConsumptionPeriods.first(where: { $0.id == id }) ?? GrantConsumptionPeriod(id: id)
            },
            set: { updated in
                guard let index = draft.receivedConsumptionPeriods.firstIndex(where: { $0.id == id }) else { return }
                draft.receivedConsumptionPeriods[index] = updated
            }
        )
    }

    private func consumptionPeriodFieldBinding(
        for id: String,
        keyPath: WritableKeyPath<GrantConsumptionPeriod, String>
    ) -> Binding<String> {
        Binding(
            get: { consumptionPeriodBinding(for: id).wrappedValue[keyPath: keyPath] },
            set: { newValue in
                let period = applyingGrantConsumptionPeriodEdit(
                    consumptionPeriodBinding(for: id).wrappedValue,
                    keyPath: keyPath,
                    value: newValue
                )
                consumptionPeriodBinding(for: id).wrappedValue = period
            }
        )
    }

    private func persistDraftIfNeeded() {
        autosaveTask?.cancel()
        let pending = pendingDraft
        guard pending != application else { return }
        store.autosave(application: pending, selectionID: currentSelectionID)
        currentSelectionID = store.applicationSelectionID(for: pending)
    }

    private func flushAutosaveNow() {
        autosaveTask?.cancel()
        persistDraftIfNeeded()
    }

    // Runs the flush one runloop turn after the blur, matching the other
    // editors (Doctoral/Teaching/CV/Projects): the whole-collection encode
    // then happens after focus has landed and painted, not between Tab and
    // the next field acquiring first responder.
    private func requestImmediateAutosave() {
        AutosaveCoordinator.requestImmediate(&autosaveTask) {
            persistDraftIfNeeded()
        }
    }

    private func scheduleAutosave() {
        AutosaveCoordinator.schedule(&autosaveTask, after: 1.8) {
            persistDraftIfNeeded()
        }
    }

    private func persistDraftWithUndoIfNeeded() {
        autosaveTask?.cancel()
        let pending = pendingDraft
        guard pending != application else { return }
        store.save(application: pending, selectionID: currentSelectionID)
        currentSelectionID = store.applicationSelectionID(for: pending)
    }
}

private enum ApplicationDecisionChoice: CaseIterable {
    case granted
    case denied
    case withdrawn

    var dateKeyPath: WritableKeyPath<GrantApplication, String?> {
        switch self {
        case .granted:
            return \.grantedOn
        case .denied:
            return \.deniedOn
        case .withdrawn:
            return \.withdrawnOn
        }
    }

    var uncertaintyKeyPath: WritableKeyPath<GrantApplication, Bool> {
        switch self {
        case .granted:
            return \.grantedOnUncertain
        case .denied:
            return \.deniedOnUncertain
        case .withdrawn:
            return \.withdrawnOnUncertain
        }
    }

    var validationFieldKey: String {
        switch self {
        case .granted:
            return ApplicationDateValidationFieldKey.grantedOn
        case .denied:
            return ApplicationDateValidationFieldKey.deniedOn
        case .withdrawn:
            return ApplicationDateValidationFieldKey.withdrawnOn
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .granted:
            return language.text("Granted", "Beviljad")
        case .denied:
            return language.text("Declined", "Avslagen")
        case .withdrawn:
            return language.text("Withdrawn", "Tillbakadragen")
        }
    }

    static func resolve(for application: GrantApplication) -> ApplicationDecisionChoice? {
        if let resolved = application.resolvedDecisionDateString {
            if resolved == application.grantedOn?.trimmedOrNil {
                return .granted
            }
            if resolved == application.deniedOn?.trimmedOrNil {
                return .denied
            }
            if resolved == application.withdrawnOn?.trimmedOrNil {
                return .withdrawn
            }
        }
        if application.grantedOn?.trimmedOrNil != nil {
            return .granted
        }
        if application.deniedOn?.trimmedOrNil != nil {
            return .denied
        }
        if application.withdrawnOn?.trimmedOrNil != nil {
            return .withdrawn
        }
        return nil
    }
}

private enum ApplicationSubmissionChoice: CaseIterable {
    case applied
    case notApplied

    var dateKeyPath: WritableKeyPath<GrantApplication, String?> {
        switch self {
        case .applied:
            return \.appliedOn
        case .notApplied:
            return \.notAppliedOn
        }
    }

    var uncertaintyKeyPath: WritableKeyPath<GrantApplication, Bool> {
        switch self {
        case .applied:
            return \.appliedOnUncertain
        case .notApplied:
            return \.notAppliedOnUncertain
        }
    }

    var validationFieldKey: String? {
        switch self {
        case .applied:
            return ApplicationDateValidationFieldKey.appliedOn
        case .notApplied:
            return nil
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .applied:
            return language.text("Applied", "Ansökt")
        case .notApplied:
            return language.text("Not applied", "Ej sökt")
        }
    }

    static func resolve(for application: GrantApplication) -> ApplicationSubmissionChoice? {
        if application.notAppliedOn?.trimmedOrNil != nil || application.isNotAppliedStatus {
            return .notApplied
        }
        if application.appliedOn?.trimmedOrNil != nil {
            return .applied
        }
        return nil
    }
}

private enum ApplicationTimelineStep: Int, CaseIterable {
    case opens
    case applied
    case closes
    case decision
    case decisionExpected
    case firstDisposition
    case lastDisposition

    var index: Int { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .opens:
            return language.text("Opens", "Öppnar")
        case .applied:
            return language.text("Applied", "Ansökt")
        case .closes:
            return language.text("Closes", "Stänger")
        case .decision:
            return language.text("Decision", "Beslut")
        case .decisionExpected:
            return language.text("Decision expected", "Beslut väntas")
        case .firstDisposition:
            return language.text("First disposition", "Första disponering")
        case .lastDisposition:
            return language.text("Last disposition", "Sista disponering")
        }
    }

    var dateKeyPath: WritableKeyPath<GrantApplication, String?>? {
        switch self {
        case .opens:
            return \.opensOn
        case .applied:
            return \.appliedOn
        case .closes:
            return \.closesOn
        case .decision:
            return nil
        case .decisionExpected:
            return \.decisionExpectedOn
        case .firstDisposition:
            return \.firstDispositionOn
        case .lastDisposition:
            return \.lastDispositionOn
        }
    }

    var uncertaintyKeyPath: WritableKeyPath<GrantApplication, Bool>? {
        switch self {
        case .opens:
            return \.opensOnUncertain
        case .applied:
            return \.appliedOnUncertain
        case .closes:
            return \.closesOnUncertain
        case .decision:
            return nil
        case .decisionExpected:
            return \.decisionExpectedOnUncertain
        case .firstDisposition:
            return \.firstDispositionOnUncertain
        case .lastDisposition:
            return \.lastDispositionOnUncertain
        }
    }

    var validationFieldKey: String? {
        switch self {
        case .opens:
            return ApplicationDateValidationFieldKey.opensOn
        case .applied:
            return ApplicationDateValidationFieldKey.appliedOn
        case .closes:
            return ApplicationDateValidationFieldKey.closesOn
        case .decision:
            return nil
        case .decisionExpected:
            return ApplicationDateValidationFieldKey.decisionExpectedOn
        case .firstDisposition:
            return ApplicationDateValidationFieldKey.firstDispositionOn
        case .lastDisposition:
            return ApplicationDateValidationFieldKey.lastDispositionOn
        }
    }
}

private struct ApplicationTimelineStepper: View {
    @ObservedObject var store: GrantDataStore
    @Binding var application: GrantApplication
    let language: AppLanguage

    private let horizontalInset: CGFloat = 62
    private let circleSize: CGFloat = 24
    private let timelineHeight: CGFloat = 156
    private let markerCenterY: CGFloat = 18
    private let inactiveGray = AppTimelineStrip<ApplicationTimelineStep, EmptyView>.inactiveGray
    private let futureGray = AppTimelineStrip<ApplicationTimelineStep, EmptyView>.futureGray

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var applicationDeadlineHideKey: String {
        CalendarAutomaticEventHideKey.applicationDeadline(applicationID: application.id)
    }

    private var decisionChoice: ApplicationDecisionChoice? {
        ApplicationDecisionChoice.resolve(for: application)
    }

    private var submissionChoice: ApplicationSubmissionChoice? {
        ApplicationSubmissionChoice.resolve(for: application)
    }

    private var illogicalDateFieldKeys: Set<String> {
        illogicalApplicationDateFieldKeys(for: application)
    }

    private func undoRevealIsActive(fieldKey: String?) -> Bool {
        guard let fieldKey else { return false }
        return store.undoRevealRequest?.target.matchesField(
            routeDestination: .applications,
            recordID: application.id,
            fieldKey: fieldKey
        ) == true
    }

    private var allSteps: [ApplicationTimelineStep] {
        return ApplicationTimelineStep.allCases
    }

    private var isRejectedOutcome: Bool {
        guard let choice = decisionChoice else { return false }
        return choice == .denied || choice == .withdrawn
    }

    private var isNotAppliedOutcome: Bool {
        submissionChoice == .notApplied || application.isNotAppliedStatus
    }

    var body: some View {
        GeometryReader { geometry in
            let centers = circleCenters(width: geometry.size.width)

            ZStack(alignment: .topLeading) {
                ForEach(0..<(allSteps.count - 1), id: \.self) { index in
                    segmentView(index: index, centers: centers)
                }

                if let markerX = todayMarkerX(centers: centers) {
                    Path { path in
                        path.move(to: CGPoint(x: markerX, y: 0))
                        path.addLine(to: CGPoint(x: markerX, y: markerCenterY * 2))
                    }
                    .stroke(Color.red, lineWidth: 3)
                }

                ForEach(Array(allSteps.enumerated()), id: \.element) { index, step in
                    stepView(step, centerX: centers[index], width: stepWidth(for: step))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: timelineHeight)
    }

    private func circleCenters(width: CGFloat) -> [CGFloat] {
        let leadingInset = max(horizontalInset, stepWidth(for: allSteps.first ?? .applied) / 2)
        let trailingInset = max(horizontalInset, stepWidth(for: allSteps.last ?? .lastDisposition) / 2)
        let usableWidth = max(width - leadingInset - trailingInset, 1)
        let lastIndex = max(allSteps.count - 1, 1)
        return allSteps.indices.map { index in
            leadingInset + (usableWidth * CGFloat(index) / CGFloat(lastIndex))
        }
    }

    @ViewBuilder
    private func segmentView(index: Int, centers: [CGFloat]) -> some View {
        let startX = centers[index]
        let endX = centers[index + 1]
        let base = segmentBaseStyle(index: index)

        if base.dashed {
            Path { path in
                path.move(to: CGPoint(x: startX, y: markerCenterY))
                path.addLine(to: CGPoint(x: endX, y: markerCenterY))
            }
            .stroke(
                base.leadingColor,
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 5])
            )
        } else {
            timelineGradientLine(
                startX: startX,
                endX: endX,
                lineWidth: 2.5,
                colors: [base.leadingColor, base.trailingColor]
            )
        }

        if let fraction = segmentProgressFraction(index: index), fraction > 0 {
            timelineGradientLine(
                startX: startX,
                endX: endX,
                lineWidth: 3,
                colors: [base.leadingColor, base.trailingColor],
                visibleFraction: fraction
            )
        }
    }

    private func timelineGradientLine(
        startX: CGFloat,
        endX: CGFloat,
        lineWidth: CGFloat,
        colors: [Color],
        visibleFraction: CGFloat = 1
    ) -> some View {
        let width = max(endX - startX, 1)
        let clampedFraction = max(0, min(1, visibleFraction))
        return Capsule(style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: lineWidth)
            .mask(alignment: .leading) {
                Rectangle()
                    .frame(width: width * clampedFraction, height: lineWidth)
            }
            .position(x: startX + (width / 2), y: markerCenterY)
    }

    private func segmentBaseStyle(index: Int) -> (leadingColor: Color, trailingColor: Color, dashed: Bool) {
        let leftStep = allSteps[index]
        let rightStep = allSteps[index + 1]
        if isStepDeemphasized(leftStep) || isStepDeemphasized(rightStep) {
            return (segmentEndpointColor(for: leftStep), segmentEndpointColor(for: rightStep), false)
        }

        if isStepCompleted(leftStep) && isStepCompleted(rightStep) {
            return (segmentEndpointColor(for: leftStep), segmentEndpointColor(for: rightStep), false)
        }
        if stepHasDefinedDate(leftStep) || stepHasDefinedDate(rightStep) {
            return (segmentEndpointColor(for: leftStep), segmentEndpointColor(for: rightStep), false)
        }
        return (segmentEndpointColor(for: leftStep), segmentEndpointColor(for: rightStep), true)
    }

    private func segmentEndpointColor(for step: ApplicationTimelineStep) -> Color {
        if isStepCompleted(step), !isStepDeemphasized(step), !(isRejectedOutcome && step.rawValue > ApplicationTimelineStep.decision.index) {
            return completedColor(for: step).solid
        }
        if stepHasDefinedDate(step), !isStepDeemphasized(step), !(isRejectedOutcome && step.rawValue > ApplicationTimelineStep.decision.index) {
            return futureGray
        }
        return inactiveGray
    }

    @ViewBuilder
    private func stepView(_ step: ApplicationTimelineStep, centerX: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 9) {
            markerView(for: step)
            labelBlock(for: step)
        }
        .padding(.top, markerCenterY - (circleSize / 2))
        .frame(width: width, height: timelineHeight, alignment: .top)
        .contentShape(Rectangle())
        .contextMenu {
            stepContextMenu(for: step)
        }
        .position(x: centerX, y: timelineHeight / 2)
    }

    private func markerView(for step: ApplicationTimelineStep) -> some View {
        let style = markerStyle(for: step)

        return ZStack {
            Circle()
                .fill(style.fill)
            Circle()
                .stroke(style.stroke, lineWidth: style.lineWidth)

            if let icon = style.icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(style.iconColor)
            }
        }
        .frame(width: circleSize, height: circleSize)
    }

    @ViewBuilder
    private func labelBlock(for step: ApplicationTimelineStep) -> some View {
        switch step {
        case .applied:
            submissionBlock
        case .decision:
            decisionBlock
        default:
            standardStepBlock(step)
        }
    }

    private var decisionBlock: some View {
        let isDeemphasized = isStepDeemphasized(.decision)
        return VStack(spacing: 6) {
            if let choice = decisionChoice {
                AppTimelineStepText(
                    text: choice.title(language: language),
                    lineLimit: 2,
                    foreground: isDeemphasized ? inactiveGray : AppPalette.appText
                )

                AppTimelineDateEditor(
                    text: decisionDateBinding(for: choice),
                    uncertain: decisionUncertaintyBinding(for: choice),
                    isHiddenFromCalendar: false,
                    isReadOnly: application.isEditingLocked,
                    isIllogical: illogicalDateFieldKeys.contains(choice.validationFieldKey),
                    showsCountdown: !isStepDeemphasized(.decision),
                    mutedColor: isDeemphasized ? inactiveGray : nil,
                    hiddenCalendarMenuTitle: nil,
                    toggleHiddenCalendarVisibility: nil,
                    language: language
                )
                .undoRevealPulse(
                    triggerID: store.undoRevealRequest?.id,
                    isActive: undoRevealIsActive(fieldKey: choice.validationFieldKey)
                )
            } else {
                ForEach(ApplicationDecisionChoice.allCases, id: \.self) { option in
                    Button(option.title(language: language)) {
                        selectDecision(option)
                    }
                    .buttonStyle(.plain)
                    .appTypography(.tableHeader)
                    .foregroundStyle(isDeemphasized ? inactiveGray : AppPalette.appText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var submissionBlock: some View {
        let isDeemphasized = isStepDeemphasized(.applied)
        return VStack(spacing: 6) {
            if let choice = submissionChoice {
                AppTimelineStepText(
                    text: choice.title(language: language),
                    lineLimit: 2,
                    foreground: isDeemphasized ? inactiveGray : AppPalette.appText
                )

                AppTimelineDateEditor(
                    text: submissionDateBinding(for: choice),
                    uncertain: submissionUncertaintyBinding(for: choice),
                    isHiddenFromCalendar: false,
                    isReadOnly: application.isEditingLocked,
                    isIllogical: choice.validationFieldKey.map { illogicalDateFieldKeys.contains($0) } ?? false,
                    showsCountdown: !isStepDeemphasized(.applied),
                    mutedColor: isDeemphasized ? inactiveGray : nil,
                    hiddenCalendarMenuTitle: nil,
                    toggleHiddenCalendarVisibility: nil,
                    language: language
                )
                .undoRevealPulse(
                    triggerID: store.undoRevealRequest?.id,
                    isActive: undoRevealIsActive(fieldKey: choice.validationFieldKey)
                )
            } else {
                ForEach(ApplicationSubmissionChoice.allCases, id: \.self) { option in
                    Button(option.title(language: language)) {
                        selectSubmission(option)
                    }
                    .buttonStyle(.plain)
                    .appTypography(.tableHeader)
                    .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func stepContextMenu(for step: ApplicationTimelineStep) -> some View {
        if step == .applied {
            ForEach(ApplicationSubmissionChoice.allCases, id: \.self) { option in
                Button(option.title(language: language)) {
                    selectSubmission(option)
                }
            }

            if let choice = submissionChoice {
                Divider()

                Button(language.text("Today", "Idag")) {
                    submissionDateBinding(for: choice).wrappedValue = DateParsers.isoDay.string(from: today)
                }

                Button(submissionUncertaintyBinding(for: choice).wrappedValue ? "✓ " + language.text("Uncertain date", "Osäkert datum") : language.text("Uncertain date", "Osäkert datum")) {
                    toggleSubmissionUncertainty(choice)
                }
                .disabled(submissionDateBinding(for: choice).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Divider()

                Button(language.text("Clear", "Rensa"), role: .destructive) {
                    clearSubmission()
                }
            }
        } else if step == .decision {
            ForEach(ApplicationDecisionChoice.allCases, id: \.self) { option in
                Button(option.title(language: language)) {
                    selectDecision(option)
                }
            }

            if let choice = decisionChoice {
                Divider()

                Button(language.text("Today", "Idag")) {
                    decisionDateBinding(for: choice).wrappedValue = DateParsers.isoDay.string(from: today)
                }

                Button(decisionUncertaintyBinding(for: choice).wrappedValue ? "✓ " + language.text("Uncertain date", "Osäkert datum") : language.text("Uncertain date", "Osäkert datum")) {
                    toggleDecisionUncertainty(choice)
                }
                .disabled(decisionDateBinding(for: choice).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Divider()

                Button(language.text("Clear decision", "Rensa beslut"), role: .destructive) {
                    clearDecision()
                }
            }
        } else if let text = dateBinding(for: step),
                  let uncertain = uncertaintyBinding(for: step) {
            Button(language.text("Today", "Idag")) {
                text.wrappedValue = DateParsers.isoDay.string(from: today)
            }

            Button(uncertain.wrappedValue ? "✓ " + language.text("Uncertain date", "Osäkert datum") : language.text("Uncertain date", "Osäkert datum")) {
                toggleUncertainty(for: step)
            }
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if step == .closes, text.wrappedValue.trimmedOrNil != nil {
                let isHidden = store.isAutomaticCalendarEventHidden(applicationDeadlineHideKey)
                Divider()
                Button(isHidden ? language.text("Don't hide", "Göm inte") : language.text("Hide", "Göm")) {
                    store.setAutomaticCalendarEventHidden(applicationDeadlineHideKey, hidden: !isHidden)
                }
            }
        }
    }

    private func standardStepBlock(_ step: ApplicationTimelineStep) -> some View {
        let isDeemphasized = isStepDeemphasized(step)
        return VStack(spacing: 5) {
            AppTimelineStepText(
                text: step.title(language: language),
                foreground: isDeemphasized ? inactiveGray : AppPalette.appText
            )

            if let text = dateBinding(for: step),
               let uncertain = uncertaintyBinding(for: step) {
                AppTimelineDateEditor(
                    text: text,
                    uncertain: uncertain,
                    isHiddenFromCalendar: isHiddenCalendarDate(for: step),
                    isReadOnly: application.isEditingLocked,
                    isIllogical: step.validationFieldKey.map { illogicalDateFieldKeys.contains($0) } ?? false,
                    showsCountdown: !isStepDeemphasized(step),
                    mutedColor: isDeemphasized ? inactiveGray : nil,
                    hiddenCalendarMenuTitle: hiddenCalendarMenuTitle(for: step),
                    toggleHiddenCalendarVisibility: { toggleHiddenCalendarVisibility(for: step) },
                    language: language
                )
                .undoRevealPulse(
                    triggerID: store.undoRevealRequest?.id,
                    isActive: undoRevealIsActive(fieldKey: step.validationFieldKey)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func markerStyle(for step: ApplicationTimelineStep) -> (stroke: Color, fill: Color, icon: String?, iconColor: Color, lineWidth: CGFloat) {
        if isStepDeemphasized(step) {
            return (
                inactiveGray,
                AppPalette.fieldSurface,
                nil,
                .clear,
                1.7
            )
        }

        if isRejectedOutcome && step.rawValue > ApplicationTimelineStep.decision.index {
            return (
                inactiveGray,
                AppPalette.fieldSurface,
                nil,
                .clear,
                1.7
            )
        }

        if isStepCompleted(step) {
            let color = completedColor(for: step)
            return (color.solid, color.shade, "checkmark", color.solid, 2.2)
        }

        if stepHasDefinedDate(step) {
            return (futureGray, AppPalette.fieldSurface, nil, .clear, 1.9)
        }

        return (inactiveGray, AppPalette.fieldSurface, nil, .clear, 1.7)
    }

    private func completedColor(for step: ApplicationTimelineStep) -> (shade: Color, solid: Color) {
        switch step {
        case .decision, .decisionExpected, .firstDisposition, .lastDisposition:
            if isRejectedOutcome && step == .decision {
                return (AppPalette.shadeRed, AppPalette.vividRed)
            }
            if decisionChoice == .granted {
                return (AppPalette.shadeGreen, AppPalette.vividGreen)
            }
            return (AppPalette.shadeBlue, AppPalette.vividBlue)
        case .opens, .applied, .closes:
            return (AppPalette.shadeBlue, AppPalette.vividBlue)
        }
    }

    private func isStepCompleted(_ step: ApplicationTimelineStep) -> Bool {
        switch step {
        case .opens:
            return dateHasPassed(application.openDate)
        case .applied:
            if submissionChoice == .notApplied {
                return dateHasPassed(application.notAppliedDate)
            }
            return dateHasPassed(application.applicationDate)
        case .closes:
            return dateHasPassed(application.closeDate)
        case .decision:
            return decisionChoice != nil
        case .decisionExpected:
            return decisionChoice != nil
        case .firstDisposition:
            guard decisionChoice == .granted else { return false }
            return dateHasPassed(application.firstDispositionDate)
        case .lastDisposition:
            guard decisionChoice == .granted else { return false }
            return dateHasPassed(application.lastDispositionDate)
        }
    }

    private func dateHasPassed(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.startOfDay(for: date) <= today
    }

    private func segmentProgressFraction(index: Int) -> CGFloat? {
        let leftStep = allSteps[index]
        let rightStep = allSteps[index + 1]
        if isStepDeemphasized(leftStep) || isStepDeemphasized(rightStep) {
            return nil
        }
        guard let leftDate = anchorDate(for: leftStep),
              let rightDate = anchorDate(for: rightStep),
              rightDate > leftDate else {
            return nil
        }
        if today <= leftDate { return 0 }
        if today >= rightDate { return 1 }
        let total = rightDate.timeIntervalSince(leftDate)
        let raw = today.timeIntervalSince(leftDate) / total
        return CGFloat(max(0, min(1, raw)))
    }

    private func segmentProgressColor(index: Int) -> Color {
        if let choice = decisionChoice {
            switch choice {
            case .granted:
                if index >= ApplicationTimelineStep.decision.index {
                    return AppPalette.vividGreen
                }
            case .denied, .withdrawn:
                if index >= ApplicationTimelineStep.decision.index {
                    return AppPalette.vividRed
                }
            }
        }
        return AppPalette.vividBlue
    }

    private func anchorDate(for step: ApplicationTimelineStep) -> Date? {
        switch step {
        case .opens:
            return application.openDate
        case .applied:
            if submissionChoice == .notApplied {
                return application.notAppliedDate
            }
            return application.applicationDate
        case .closes:
            return application.closeDate
        case .decision:
            if let decisionDate = application.decisionDate {
                return decisionDate
            }
            if let closeDate = application.closeDate,
               let expectedDate = application.decisionExpectedDate,
               expectedDate > closeDate {
                return closeDate.addingTimeInterval(expectedDate.timeIntervalSince(closeDate) / 2)
            }
            return application.decisionExpectedDate
        case .decisionExpected:
            return application.decisionExpectedDate
        case .firstDisposition:
            return application.firstDispositionDate
        case .lastDisposition:
            return application.lastDispositionDate
        }
    }

    private func todayMarkerX(centers: [CGFloat]) -> CGFloat? {
        let datedSteps = allSteps.enumerated().compactMap { visibleIndex, step -> (step: ApplicationTimelineStep, date: Date, x: CGFloat)? in
            guard let date = anchorDate(for: step) else { return nil }
            guard centers.indices.contains(visibleIndex) else { return nil }
            return (step, date, centers[visibleIndex])
        }
        .sorted { $0.date < $1.date }

        guard datedSteps.count >= 2 else {
            return nil
        }

        guard let nextIndex = datedSteps.firstIndex(where: { today <= $0.date }) else {
            return nil
        }

        if nextIndex == 0 {
            return Calendar.current.isDate(datedSteps[0].date, inSameDayAs: today) ? datedSteps[0].x : nil
        }

        let previous = datedSteps[nextIndex - 1]
        let next = datedSteps[nextIndex]

        if Calendar.current.isDate(previous.date, inSameDayAs: today) {
            return previous.x
        }
        if Calendar.current.isDate(next.date, inSameDayAs: today) {
            return next.x
        }

        let interval = next.date.timeIntervalSince(previous.date)
        guard interval > 0 else {
            return (previous.x + next.x) / 2
        }

        let fraction = max(0, min(1, today.timeIntervalSince(previous.date) / interval))
        return previous.x + ((next.x - previous.x) * CGFloat(fraction))
    }

    private func isStepDeemphasized(_ step: ApplicationTimelineStep) -> Bool {
        if isNotAppliedOutcome {
            return step != .opens && step != .applied
        }
        if decisionChoice == .granted, step == .decisionExpected {
            return true
        }
        if isRejectedOutcome {
            return step == .decisionExpected || step == .firstDisposition || step == .lastDisposition
        }
        return false
    }

    private func stepWidth(for step: ApplicationTimelineStep) -> CGFloat {
        switch step {
        case .decision:
            return 160
        case .decisionExpected:
            return 126
        case .firstDisposition, .lastDisposition:
            return 156
        default:
            return 110
        }
    }

    private func dateBinding(for step: ApplicationTimelineStep) -> Binding<String>? {
        guard let keyPath = step.dateKeyPath else { return nil }
        return Binding(
            get: { application[keyPath: keyPath] ?? "" },
            set: { newValue in
                application = applyingGrantTimelineDateEdit(
                    application,
                    keyPath: keyPath,
                    value: newValue
                )
            }
        )
    }

    private func uncertaintyBinding(for step: ApplicationTimelineStep) -> Binding<Bool>? {
        guard let keyPath = step.uncertaintyKeyPath else { return nil }
        return Binding(
            get: { application[keyPath: keyPath] },
            set: { application[keyPath: keyPath] = $0 }
        )
    }

    private func decisionDateBinding(for choice: ApplicationDecisionChoice) -> Binding<String> {
        Binding(
            get: { application[keyPath: choice.dateKeyPath] ?? "" },
            set: { newValue in
                application[keyPath: choice.dateKeyPath] = DateParsers.canonicalizedDayInput(newValue).trimmedOrNil
            }
        )
    }

    private func decisionUncertaintyBinding(for choice: ApplicationDecisionChoice) -> Binding<Bool> {
        Binding(
            get: { application[keyPath: choice.uncertaintyKeyPath] },
            set: { application[keyPath: choice.uncertaintyKeyPath] = $0 }
        )
    }

    private func submissionDateBinding(for choice: ApplicationSubmissionChoice) -> Binding<String> {
        Binding(
            get: { application[keyPath: choice.dateKeyPath] ?? "" },
            set: { newValue in
                application[keyPath: choice.dateKeyPath] = DateParsers.canonicalizedDayInput(newValue).trimmedOrNil
                if choice == .notApplied {
                    application.result = application[keyPath: choice.dateKeyPath]?.trimmedOrNil == nil ? "Att söka" : "Ej sökt"
                } else if application.isNotAppliedStatus {
                    application.result = nil
                }
            }
        )
    }

    private func submissionUncertaintyBinding(for choice: ApplicationSubmissionChoice) -> Binding<Bool> {
        Binding(
            get: { application[keyPath: choice.uncertaintyKeyPath] },
            set: { application[keyPath: choice.uncertaintyKeyPath] = $0 }
        )
    }

    private func selectSubmission(_ choice: ApplicationSubmissionChoice) {
        let todayString = DateParsers.isoDay.string(from: today)

        for option in ApplicationSubmissionChoice.allCases {
            if option == choice {
                if application[keyPath: option.dateKeyPath]?.trimmedOrNil == nil {
                    application[keyPath: option.dateKeyPath] = todayString
                }
            } else {
                application[keyPath: option.dateKeyPath] = nil
                application[keyPath: option.uncertaintyKeyPath] = false
            }
        }
        application.result = choice == .notApplied ? "Ej sökt" : nil
    }

    private func selectDecision(_ choice: ApplicationDecisionChoice) {
        let todayString = DateParsers.isoDay.string(from: today)

        for option in ApplicationDecisionChoice.allCases {
            if option == choice {
                if application[keyPath: option.dateKeyPath]?.trimmedOrNil == nil {
                    application[keyPath: option.dateKeyPath] = todayString
                }
            } else {
                application[keyPath: option.dateKeyPath] = nil
                application[keyPath: option.uncertaintyKeyPath] = false
            }
        }
    }

    private func clearDecision() {
        for option in ApplicationDecisionChoice.allCases {
            application[keyPath: option.dateKeyPath] = nil
            application[keyPath: option.uncertaintyKeyPath] = false
        }
        // The old decision date and status went with the decision; without
        // this the record stayed "Beviljat" and kept the old date.
        application.decisionOn = nil
        application.decisionOnUncertain = false
        application.result = application.appliedOn?.trimmedOrNil == nil ? "Att söka" : "Väntar svar"
    }

    private func clearSubmission() {
        for option in ApplicationSubmissionChoice.allCases {
            application[keyPath: option.dateKeyPath] = nil
            application[keyPath: option.uncertaintyKeyPath] = false
        }
        if application.isNotAppliedStatus {
            application.result = "Att söka"
        }
    }

    private func toggleUncertainty(for step: ApplicationTimelineStep) {
        guard let text = dateBinding(for: step),
              let uncertain = uncertaintyBinding(for: step),
              text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }
        uncertain.wrappedValue.toggle()
    }

    private func toggleDecisionUncertainty(_ choice: ApplicationDecisionChoice) {
        let text = decisionDateBinding(for: choice)
        let uncertain = decisionUncertaintyBinding(for: choice)
        guard text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        uncertain.wrappedValue.toggle()
    }

    private func toggleSubmissionUncertainty(_ choice: ApplicationSubmissionChoice) {
        let text = submissionDateBinding(for: choice)
        let uncertain = submissionUncertaintyBinding(for: choice)
        guard text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        uncertain.wrappedValue.toggle()
    }

    private func isHiddenCalendarDate(for step: ApplicationTimelineStep) -> Bool {
        guard step == .closes,
              dateBinding(for: step)?.wrappedValue.trimmedOrNil != nil else {
            return false
        }
        return store.isAutomaticCalendarEventHidden(applicationDeadlineHideKey)
    }

    private func hiddenCalendarMenuTitle(for step: ApplicationTimelineStep) -> String? {
        guard step == .closes,
              dateBinding(for: step)?.wrappedValue.trimmedOrNil != nil else {
            return nil
        }
        // F27: ✓-form, like the other context-menu toggles.
        return store.isAutomaticCalendarEventHidden(applicationDeadlineHideKey)
            ? language.text("✓ Hidden from calendar", "✓ Gömd från kalendern")
            : language.text("Hidden from calendar", "Gömd från kalendern")
    }

    private func toggleHiddenCalendarVisibility(for step: ApplicationTimelineStep) {
        guard step == .closes,
              dateBinding(for: step)?.wrappedValue.trimmedOrNil != nil else {
            return
        }
        let isHidden = store.isAutomaticCalendarEventHidden(applicationDeadlineHideKey)
        store.setAutomaticCalendarEventHidden(applicationDeadlineHideKey, hidden: !isHidden)
    }

    private func stepHasDefinedDate(_ step: ApplicationTimelineStep) -> Bool {
        anchorDate(for: step) != nil
    }
}

struct AppTimelineDateEditor: View {
    let text: Binding<String>
    let uncertain: Binding<Bool>
    let isHiddenFromCalendar: Bool
    var isReadOnly = false
    var isIllogical: Bool = false
    var showsCountdown: Bool = true
    var mutedColor: Color? = nil
    let hiddenCalendarMenuTitle: String?
    let toggleHiddenCalendarVisibility: (() -> Void)?
    let language: AppLanguage

    private var parsedDate: Date? {
        DateParsers.isoDay.date(from: text.wrappedValue)
    }

    private var futureDaysRemaining: Int? {
        guard let parsedDate else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: parsedDate)
        let days = Calendar.current.dateComponents([.day], from: today, to: target).day ?? 0
        return days > 0 ? days : nil
    }

    var body: some View {
        VStack(spacing: 4) {
            if isReadOnly {
                Text(text.wrappedValue.trimmedOrNil ?? "–")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(mutedColor ?? AppPalette.appText)
                    .textSelection(.enabled)
                    .frame(minHeight: 18)
                    .frame(width: 118)
                    .help(isIllogical ? language.text("Illogical date combination", "Ologisk datumkombination") : "")
            } else {
                CommitFormattingTextField(
                    placeholder: "YYYY-MM-DD",
                    text: Binding(
                        get: { text.wrappedValue },
                        set: { newValue in
                            let normalized = normalizeSalaryDateInput(newValue)
                            text.wrappedValue = normalized
                            if normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                uncertain.wrappedValue = false
                            }
                        }
                    ),
                    formatter: normalizeSalaryDateInput,
                    updatesContinuously: false,
                    isBordered: false,
                    focusRingType: .none,
                    textAlignment: .center,
                    font: .systemFont(ofSize: 13, weight: .semibold),
                    textColor: mutedColor.map(NSColor.init) ?? .labelColor,
                    placeholderColor: NSColor.tertiaryLabelColor
                )
                .frame(minHeight: 18)
                .textFieldStyle(.plain)
                .appFieldChrome(
                    minHeight: AppPalette.fieldMinHeight,
                    horizontalPadding: 8,
                    verticalPadding: 4,
                    fillsWidth: false,
                    fill: AppPalette.fieldSurface,
                    stroke: isIllogical ? AppPalette.vividRed.opacity(0.68) : Color.clear
                )
                .frame(width: 118)
                .help(isIllogical ? language.text("Illogical date combination", "Ologisk datumkombination") : "")
                .calendarDateStatusOutline(
                    isUncertain: uncertain.wrappedValue,
                    isHiddenFromCalendar: isHiddenFromCalendar,
                    uncertaintyColor: mutedColor ?? AppPalette.vividOrange
                )
                .contextMenu {
                    if text.wrappedValue.trimmedOrNil != nil {
                        Button(uncertain.wrappedValue ? "✓ " + language.text("Uncertain date", "Osäkert datum") : language.text("Uncertain date", "Osäkert datum")) {
                            uncertain.wrappedValue.toggle()
                        }
                        if let hiddenCalendarMenuTitle, let toggleHiddenCalendarVisibility {
                            Divider()
                            Button(hiddenCalendarMenuTitle) {
                                toggleHiddenCalendarVisibility()
                            }
                        }
                    } else {
                        Button(language.text("Uncertain date", "Osäkert datum")) {}
                            .disabled(true)
                    }
                }
            }

            if showsCountdown, let days = futureDaysRemaining {
                StatusBadge(
                    text: language == .swedish ? "Om \(days) d" : "In \(days) days",
                    tone: countdownTone(for: days)
                )
                .scaleEffect(0.82)
            }

        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func countdownTone(for days: Int) -> BadgeTone {
        if days <= 7 { return .negative }
        if days <= 30 { return .pending }
        return .outline
    }
}

private enum ApplicationGrantStatisticsOutcome: String, CaseIterable, Identifiable {
    case granted
    case rejected
    case waiting

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .granted:
            return AppPalette.shadeGreen
        case .rejected:
            return AppPalette.vividRed
        case .waiting:
            return AppPalette.shadeYellow
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .granted:
            return language.text("Accepted", "Beviljade")
        case .rejected:
            return language.text("Rejected", "Avslagna")
        case .waiting:
            return language.text("Pending", "Väntar")
        }
    }
}

private struct ApplicationGrantStatisticsRow: Identifiable {
    let application: GrantApplication
    let outcome: ApplicationGrantStatisticsOutcome
    let projectTitle: String
    let funderTitle: String
    let grantTitle: String
    let year: String
    let amountText: String

    var id: String { application.id }
}

private struct ApplicationGrantStatisticsProjectSummary: Identifiable {
    let id: String
    let title: String
    let rows: [ApplicationGrantStatisticsRow]

    var latestYear: String {
        rows.map(\.year).max() ?? ""
    }
}

private struct ApplicationGrantStatisticsView: View {
    @ObservedObject var store: GrantDataStore
    let application: GrantApplication
    let language: AppLanguage

    private var projectTitle: String {
        store.projectLabel(for: application, language: language)
            ?? language.text("No project", "Saknar projekt")
    }

    private var funderTitle: String {
        store.organizationLabel(for: application, language: language)
    }

    private var projectRows: [ApplicationGrantStatisticsRow] {
        statisticsRows(matching: matchesCurrentProject)
    }

    private var funderRows: [ApplicationGrantStatisticsRow] {
        statisticsRows(matching: matchesCurrentFunder)
    }

    private var funderProjectSummaries: [ApplicationGrantStatisticsProjectSummary] {
        let grouped = Dictionary(grouping: funderRows, by: { normalizedApplicationGrantStatisticsKey($0.projectTitle) })
        return grouped.values
            .map { rows in
                ApplicationGrantStatisticsProjectSummary(
                    id: rows.first?.projectTitle ?? UUID().uuidString,
                    title: rows.first?.projectTitle ?? language.text("No project", "Saknar projekt"),
                    rows: rows.sorted(by: rowSort)
                )
            }
            .sorted {
                if $0.latestYear != $1.latestYear {
                    return $0.latestYear > $1.latestYear
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text(language.text("Earlier outcomes for this grant context", "Tidigare utfall för anslagets kontext"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                ApplicationGrantStatisticsCard(
                    title: language.text("Project history", "Projektets historik"),
                    subtitle: projectTitle,
                    rows: projectRows,
                    emptyText: language.text(
                        "No earlier decided or pending applications for this project.",
                        "Inga tidigare beslutade eller väntande ansökningar för detta projekt."
                    ),
                    language: language,
                    listTitle: language.text("Earlier applications in the project", "Tidigare ansökningar i projektet")
                )

                ApplicationGrantStatisticsCard(
                    title: language.text("Funder history", "Anslagsgivarens historik"),
                    subtitle: funderTitle,
                    rows: funderRows,
                    emptyText: language.text(
                        "No earlier decided or pending applications for this funder.",
                        "Inga tidigare beslutade eller väntande ansökningar hos denna anslagsgivare."
                    ),
                    language: language,
                    listTitle: language.text("Earlier applications to the funder", "Tidigare ansökningar till anslagsgivaren")
                )

                if !funderProjectSummaries.isEmpty {
                    ApplicationGrantStatisticsProjectsCard(
                        title: language.text("Projects previously used with this funder", "Projekt som tidigare varit aktuella hos anslagsgivaren"),
                        projects: funderProjectSummaries,
                        language: language
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(AppPalette.detailPanelSurface)
    }

    private func statisticsRows(matching predicate: (GrantApplication) -> Bool) -> [ApplicationGrantStatisticsRow] {
        store.applications
            .filter { $0.id != application.id }
            .filter(predicate)
            .compactMap { row in
                guard let outcome = applicationGrantStatisticsOutcome(for: row) else { return nil }
                return ApplicationGrantStatisticsRow(
                    application: row,
                    outcome: outcome,
                    projectTitle: store.projectLabel(for: row, language: language)
                        ?? language.text("No project", "Saknar projekt"),
                    funderTitle: store.organizationLabel(for: row, language: language),
                    grantTitle: store.localizedGrantName(for: row, language: language).nonEmpty
                        ?? language.text("Untitled grant", "Namnlöst anslag"),
                    year: row.statsYear,
                    amountText: amountText(for: row)
                )
            }
            .sorted(by: rowSort)
    }

    private func rowSort(_ left: ApplicationGrantStatisticsRow, _ right: ApplicationGrantStatisticsRow) -> Bool {
        if left.year != right.year {
            return left.year > right.year
        }
        if left.projectTitle != right.projectTitle {
            return left.projectTitle.localizedStandardCompare(right.projectTitle) == .orderedAscending
        }
        return left.grantTitle.localizedStandardCompare(right.grantTitle) == .orderedAscending
    }

    private func amountText(for row: GrantApplication) -> String {
        let amount: Double?
        switch applicationGrantStatisticsOutcome(for: row) {
        case .granted:
            amount = row.grantedAmountValue ?? row.appliedAmountValue ?? row.preferredBudgetAmountValue
        case .rejected, .waiting:
            amount = row.appliedAmountValue ?? row.preferredBudgetAmountValue
        case .none:
            amount = row.preferredBudgetAmountValue
        }
        return store.formattedGrantAmountWithSEKApproximation(amount, for: row)
    }

    private func matchesCurrentProject(_ row: GrantApplication) -> Bool {
        // "Alla kopplingar via id": when either application points to a
        // project, only the same project counts; free text is compared only
        // between applications that point to none.
        let currentProject = store.linkedProject(of: application)
        let rowProject = store.linkedProject(of: row)
        if currentProject != nil || rowProject != nil {
            return currentProject?.id == rowProject?.id
        }
        let currentProjectName = application.projectType?.trimmedOrNil
        let rowProjectName = row.projectType?.trimmedOrNil
        guard let currentProjectName, let rowProjectName else { return false }
        return normalizedApplicationGrantStatisticsKey(currentProjectName) == normalizedApplicationGrantStatisticsKey(rowProjectName)
    }

    private func matchesCurrentFunder(_ row: GrantApplication) -> Bool {
        // "Alla kopplingar via id": same rule as for the project.
        let currentFunder = store.linkedFunder(of: application)
        let rowFunder = store.linkedFunder(of: row)
        if currentFunder != nil || rowFunder != nil {
            return currentFunder?.id == rowFunder?.id
        }
        let currentOrganizationName = application.organization.trimmedOrNil
        let rowOrganizationName = row.organization.trimmedOrNil
        guard let currentOrganizationName, let rowOrganizationName else { return false }
        return normalizedApplicationGrantStatisticsKey(currentOrganizationName) == normalizedApplicationGrantStatisticsKey(rowOrganizationName)
    }
}

private struct ApplicationGrantStatisticsCard: View {
    let title: String
    let subtitle: String
    let rows: [ApplicationGrantStatisticsRow]
    let emptyText: String
    let language: AppLanguage
    let listTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppPalette.appText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if rows.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ApplicationGrantStatisticsOutcomeBars(rows: rows, language: language)

                VStack(alignment: .leading, spacing: 7) {
                    Text(listTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppPalette.appText)

                    ForEach(rows.prefix(10)) { row in
                        ApplicationGrantStatisticsApplicationRow(row: row, language: language)
                    }

                    if rows.count > 10 {
                        Text(language.text("+ \(rows.count - 10) more", "+ \(rows.count - 10) till"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .modifier(AppStatisticCardModifier())
    }
}

private struct ApplicationGrantStatisticsOutcomeBars: View {
    let rows: [ApplicationGrantStatisticsRow]
    let language: AppLanguage

    private var total: Int { max(rows.count, 1) }

    var body: some View {
        AppOutcomeBars(
            items: ApplicationGrantStatisticsOutcome.allCases.map { outcome in
                AppOutcomeBarItem(
                    id: outcome.id,
                    title: outcome.title(language: language),
                    count: rows.filter { $0.outcome == outcome }.count,
                    total: total,
                    tint: outcome.tint,
                    fillOpacity: 0.82
                )
            },
            labelWidth: 72
        )
    }
}

private struct ApplicationGrantStatisticsApplicationRow: View {
    let row: ApplicationGrantStatisticsRow
    let language: AppLanguage

    var body: some View {
        AppStatisticListRow(
            title: row.projectTitle,
            subtitle: [row.grantTitle, row.funderTitle, row.year].filter { !$0.isEmpty }.joined(separator: " · ")
        ) {
            Circle()
                .fill(row.outcome.tint)
                .frame(width: 8, height: 8)
        } trailing: {
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.outcome.title(language: language))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(row.outcome.tint)
                    .lineLimit(1)
                Text(row.amountText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct ApplicationGrantStatisticsProjectsCard: View {
    let title: String
    let projects: [ApplicationGrantStatisticsProjectSummary]
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppPalette.appText)

            ForEach(projects.prefix(12)) { project in
                AppStatisticListRow(
                    title: project.title,
                    subtitle: applicationGrantStatisticsProjectSummaryText(project.rows, language: language)
                ) {
                    EmptyView()
                } trailing: {
                    Text(project.latestYear)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .modifier(AppStatisticCardModifier())
    }
}

private func applicationGrantStatisticsOutcome(for application: GrantApplication) -> ApplicationGrantStatisticsOutcome? {
    let status = application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    if application.isGranted {
        return .granted
    }
    if status == "Väntar svar" {
        return .waiting
    }
    if status == "Avslag" || status == "Tillbakadragen" {
        return .rejected
    }
    return nil
}

private func normalizedApplicationGrantStatisticsKey(_ value: String) -> String {
    PublicationDerivation.normalizedName(value)
}

private func applicationGrantStatisticsProjectSummaryText(
    _ rows: [ApplicationGrantStatisticsRow],
    language: AppLanguage
) -> String {
    let granted = rows.filter { $0.outcome == .granted }.count
    let rejected = rows.filter { $0.outcome == .rejected }.count
    let waiting = rows.filter { $0.outcome == .waiting }.count
    return language.text(
        "\(rows.count) applications: \(granted) accepted, \(rejected) rejected, \(waiting) pending",
        "\(rows.count) ansökningar: \(granted) beviljade, \(rejected) avslagna, \(waiting) väntar"
    )
}
