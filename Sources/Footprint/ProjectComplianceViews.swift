import SwiftUI

private let projectComplianceColumnSpacing: CGFloat = 18

func editableProjectClinicalTrialRegistrations(
    _ registrations: [ProjectClinicalTrialRegistration]
) -> [ProjectClinicalTrialRegistration] {
    registrations.isEmpty ? [ProjectClinicalTrialRegistration()] : registrations
}

struct ProjectEthicsAndDataCollectionSection: View {
    @Binding var ethicsBaseApplication: ProjectEthicsApplication
    @Binding var ethicsAmendments: [ProjectEthicsApplication]
    let ethicsAuthorityURL: URL?
    @Binding var clinicalTrialRegistrations: [ProjectClinicalTrialRegistration]
    @Binding var principalOrganizations: [ProjectPrincipalOrganization]
    @Binding var dataCollections: [ProjectDataCollection]
    let organizations: [OrganizationRecord]
    var openOrganization: ((OrganizationRecord) -> Void)? = nil
    var isEditingLocked = false
    let language: AppLanguage

    private var visibleClinicalTrialRegistrations: [ProjectClinicalTrialRegistration] {
        isEditingLocked ? clinicalTrialRegistrations.filter { !$0.isEmpty } : clinicalTrialRegistrations
    }

    private var visibleEthicsAmendments: [ProjectEthicsApplication] {
        isEditingLocked ? ethicsAmendments.filter { !$0.isEmpty } : ethicsAmendments
    }

    private var visiblePrincipalOrganizations: [ProjectPrincipalOrganization] {
        isEditingLocked ? principalOrganizations.filter { !$0.isEmpty } : principalOrganizations
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !isEditingLocked || !visiblePrincipalOrganizations.isEmpty {
                ProjectDetailLabeledRow(
                    title: language.text("Research principals", "Forskningshuvudmän"),
                    titleTopPadding: isEditingLocked ? 0 : 6
                ) {
                    ProjectPrincipalOrganizationsEditor(
                        principalOrganizations: $principalOrganizations,
                        organizations: organizations,
                        openOrganization: openOrganization,
                        language: language,
                        isEditingLocked: isEditingLocked
                    )
                }
            }

            if !isEditingLocked || !ethicsBaseApplication.isEmpty {
                ProjectDetailLabeledRow(
                    title: language.text("Ethics approval, base application", "Etiktillstånd, grundansökan"),
                    titleTopPadding: isEditingLocked ? 0 : 6
                ) {
                    VStack(alignment: .leading, spacing: isEditingLocked ? 0 : 2) {
                        ProjectEthicsApplicationHeader(language: language, isEditingLocked: isEditingLocked)
                        ProjectEthicsApplicationEditor(
                            application: $ethicsBaseApplication,
                            language: language,
                            linkURL: ethicsAuthorityURL,
                            showsFieldTitles: false,
                            onRemove: {
                                ethicsBaseApplication = ProjectEthicsApplication()
                            },
                            isEditingLocked: isEditingLocked
                        )
                    }
                }
            }

            if !isEditingLocked || !visibleEthicsAmendments.isEmpty {
                ProjectDetailLabeledRow(title: language.text("Ethics approval, amendment", "Etiktillstånd, tilläggsansökan"), titleTopPadding: 0) {
                    VStack(alignment: .leading, spacing: isEditingLocked ? 0 : 2) {
                        if isEditingLocked {
                            ForEach(visibleEthicsAmendments) { amendment in
                                ProjectEthicsApplicationEditor(
                                    application: .constant(amendment),
                                    language: language,
                                    showsFieldTitles: false,
                                    isEditingLocked: true
                                )
                            }
                        } else {
                            // Rows are tied to their id, not their position:
                            // an emptied row moves to the end, and a row bound
                            // by position then let typing land in the next one.
                            ForEach($ethicsAmendments) { $amendment in
                                ProjectEthicsApplicationEditor(
                                    application: $amendment,
                                    language: language,
                                    showsFieldTitles: false,
                                    onRemove: amendment.id == ethicsAmendments.last?.id && amendment.isEmpty
                                        ? nil
                                        : {
                                            ethicsAmendments.removeAll { $0.id == amendment.id }
                                        }
                                )
                            }
                        }
                    }
                }
            }

            if !isEditingLocked || !visibleClinicalTrialRegistrations.isEmpty {
                ProjectDetailLabeledRow(title: "Clinicaltrials.gov", titleTopPadding: isEditingLocked ? 0 : 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        if isEditingLocked {
                            ForEach(visibleClinicalTrialRegistrations) { registration in
                                ProjectClinicalTrialRegistrationEditor(
                                    registration: .constant(registration),
                                    language: language,
                                    isEditingLocked: true
                                )
                            }
                        } else {
                            ForEach($clinicalTrialRegistrations) { $registration in
                                ProjectClinicalTrialRegistrationEditor(
                                    registration: $registration,
                                    language: language,
                                    onRemove: {
                                        clinicalTrialRegistrations.removeAll { $0.id == registration.id }
                                        if clinicalTrialRegistrations.isEmpty {
                                            clinicalTrialRegistrations = [ProjectClinicalTrialRegistration()]
                                        }
                                    }
                                )
                            }

                            Button {
                                clinicalTrialRegistrations.append(ProjectClinicalTrialRegistration())
                            } label: {
                                Label(
                                    language.text("Add clinical trial registration", "Lägg till clinicaltrials-registrering"),
                                    systemImage: "plus"
                                )
                            }
                            .buttonStyle(.borderless)
                            .disabled(clinicalTrialRegistrations.contains(where: \.isEmpty))
                            .padding(.leading, 10)
                        }
                    }
                }
            }

            if !isEditingLocked || dataCollections.contains(where: { !$0.isEmpty }) {
                ProjectDetailLabeledRow(
                    title: language.text("Data collection", "Datainsamling"),
                    titleTopPadding: isEditingLocked ? 0 : 6
                ) {
                    ProjectDataCollectionEditor(
                        dataCollections: $dataCollections,
                        language: language,
                        isEditingLocked: isEditingLocked
                    )
                }
            }
        }
    }
}

@ViewBuilder
private func projectComplianceHeaderText(_ text: String, compact: Bool) -> some View {
    if compact {
        AppTableHeaderText(text: text)
            .frame(minHeight: 18, alignment: .leading)
    } else {
        AppFieldAlignedTableHeaderText(text: text)
    }
}

private struct ProjectDetailLabeledRow<Content: View>: View {
    let title: String
    var titleWidth: CGFloat = 220
    var titleTopPadding: CGFloat = 2
    let content: Content

    init(title: String, titleWidth: CGFloat = 220, titleTopPadding: CGFloat = 6, @ViewBuilder content: () -> Content) {
        self.title = title
        self.titleWidth = titleWidth
        self.titleTopPadding = titleTopPadding
        self.content = content()
    }

    var body: some View {
        AppLabeledContentRow(
            title: title,
            titleWidth: titleWidth,
            titleTopPadding: titleTopPadding
        ) {
            content
        }
    }
}

private struct ProjectEthicsApplicationHeader: View {
    let language: AppLanguage
    var isEditingLocked = false
    private let identifierFieldWidth: CGFloat = 160
    private let trailingAccessoryWidth: CGFloat = 94

    var body: some View {
        HStack(spacing: projectComplianceColumnSpacing) {
            projectComplianceHeaderText(language.text("Status", "Status"), compact: isEditingLocked)
                .frame(width: 120, alignment: .leading)
            projectComplianceHeaderText(language.text("Applied", "Ansökt"), compact: isEditingLocked)
                .frame(width: 170, alignment: .leading)
            projectComplianceHeaderText(language.text("Approved", "Godkänd"), compact: isEditingLocked)
                .frame(width: 170, alignment: .leading)
            projectComplianceHeaderText(language.text("Case number", "Diarienummer"), compact: isEditingLocked)
                .frame(width: identifierFieldWidth, alignment: .leading)
            Color.clear.frame(width: trailingAccessoryWidth)
        }
        .padding(.horizontal, 10)
    }
}

private struct ProjectEthicsApplicationEditor: View {
    @Binding var application: ProjectEthicsApplication
    let language: AppLanguage
    var linkURL: URL? = nil
    var showsFieldTitles = true
    var onRemove: (() -> Void)? = nil
    var isEditingLocked = false
    private let identifierFieldWidth: CGFloat = 160
    private let trailingAccessoryWidth: CGFloat = 94
    private var actionTopPadding: CGFloat {
        showsFieldTitles ? 22 : 5
    }

    var body: some View {
        let dateRangeState = AppFieldValidators.optionalDateRange(from: application.appliedOn, to: application.grantedOn, language: language).state
        HStack(alignment: .top, spacing: projectComplianceColumnSpacing) {
            ProjectFieldStack(title: showsFieldTitles ? language.text("Status", "Status") : "", width: 120) {
                if isEditingLocked {
                    lockedProjectComplianceValue(application.ethicsStatusLabel(language: language))
                } else {
                    // Not editable, so no field chrome — plain text aligned
                    // with the neighbouring date fields.
                    AppLockedFieldValueText(text: application.ethicsStatusLabel(language: language))
                }
            }
            ProjectFieldStack(title: showsFieldTitles ? language.text("Applied", "Ansökt") : "", width: 170) {
                if isEditingLocked {
                    lockedProjectComplianceValue(application.appliedOn, state: dateRangeState)
                } else {
                    CommitDateFieldWithTodayButton(
                        placeholder: language.datePlaceholder,
                        text: $application.appliedOn,
                        formatter: DateParsers.canonicalizedDayInput,
                        clearBackgroundInDarkNew: true,
                        width: 110,
                        state: dateRangeState
                    )
                }
            }
            ProjectFieldStack(title: showsFieldTitles ? language.text("Approved", "Godkänd") : "", width: 170) {
                if isEditingLocked {
                    lockedProjectComplianceValue(application.grantedOn, state: dateRangeState)
                } else {
                    CommitDateFieldWithTodayButton(
                        placeholder: language.datePlaceholder,
                        text: $application.grantedOn,
                        formatter: DateParsers.canonicalizedDayInput,
                        clearBackgroundInDarkNew: true,
                        width: 110,
                        state: dateRangeState
                    )
                }
            }
            ProjectFieldStack(title: showsFieldTitles ? language.text("Case number", "Diarienummer") : "", width: identifierFieldWidth) {
                if isEditingLocked {
                    lockedProjectComplianceValue(application.caseNumber)
                } else {
                    CommitFormattingTextField(
                        placeholder: "2025-00000-01",
                        text: $application.caseNumber,
                        formatter: { $0 },
                        showsRenewedSurface: false,
                        isBordered: false
                    )
                    .frame(minHeight: 18)
                    .appTextInputChrome(fillsWidth: true)
                }
            }
            if isEditingLocked {
                Group {
                    if let linkURL {
                        AppDestinationURLLink(
                            kind: .web,
                            language: language,
                            destination: linkURL,
                            fontSize: 12
                        )
                        .frame(width: 48, alignment: .trailing)
                    } else {
                        Color.clear.frame(width: 48, height: 18)
                    }
                }
                .frame(width: trailingAccessoryWidth, height: 18, alignment: .topLeading)
            } else {
                HStack(spacing: 8) {
                    Group {
                        if let linkURL {
                            AppDestinationURLLink(
                                kind: .web,
                                language: language,
                                destination: linkURL,
                                fontSize: 12
                            )
                        } else {
                            AppDestinationPlaceholder()
                        }
                    }
                    .frame(width: 48, alignment: .trailing)

                    Group {
                        if let onRemove {
                            AppInlineDeleteButton(title: language.text("Remove ethics row", "Ta bort etikrad")) {
                                onRemove()
                            }
                            .disabled(application.isEmpty)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 22, alignment: .center)
                }
                .frame(width: trailingAccessoryWidth, height: 28, alignment: .center)
                .padding(.top, actionTopPadding)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 0)
    }
}

private struct ProjectPrincipalOrganizationsEditor: View {
    @Binding var principalOrganizations: [ProjectPrincipalOrganization]
    let organizations: [OrganizationRecord]
    var openOrganization: ((OrganizationRecord) -> Void)?
    let language: AppLanguage
    var isEditingLocked = false
    // 308 puts the case-number column at the same x as the ethics rows'
    // Godkänd column (120 + 170 + two 18 pt gaps); the 170 pt filler after
    // it lands the link/trash accessories where the ethics rows have them.
    private let organizationWidth: CGFloat = 308
    private let caseNumberWidth: CGFloat = 160
    private let accessoryAlignmentFillerWidth: CGFloat = 170
    private let trailingAccessoryWidth: CGFloat = 42

    private var organizationOptions: [String] {
        organizations
            .map { $0.displayName(for: language) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var visibleRows: [ProjectPrincipalOrganization] {
        isEditingLocked ? principalOrganizations.filter { !$0.isEmpty } : principalOrganizations
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isEditingLocked ? 0 : 6) {
            if !isEditingLocked {
                HStack(spacing: projectComplianceColumnSpacing) {
                    projectComplianceHeaderText(language.text("Organization", "Organisation"), compact: false)
                        .frame(width: organizationWidth, alignment: .leading)
                    projectComplianceHeaderText(language.text("Case number", "Diarienummer"), compact: false)
                        .frame(width: caseNumberWidth, alignment: .leading)
                    Color.clear.frame(width: accessoryAlignmentFillerWidth)
                    Color.clear.frame(width: trailingAccessoryWidth)
                    Color.clear.frame(width: trailingAccessoryWidth)
                }
                .padding(.horizontal, 10)
            }

            ForEach(Array(visibleRows.enumerated()), id: \.element.id) { visibleIndex, row in
                let index = principalOrganizations.firstIndex { $0.id == row.id } ?? visibleIndex
                HStack(alignment: .top, spacing: projectComplianceColumnSpacing) {
                    if isEditingLocked {
                        lockedProjectComplianceValue(displayName(for: row))
                            .frame(width: organizationWidth, alignment: .leading)
                        lockedProjectComplianceValue(row.caseNumber)
                            .frame(width: caseNumberWidth, alignment: .leading)
                    } else if principalOrganizations.indices.contains(index) {
                        EditableProjectPrincipalOrganizationRow(
                            organizationName: $principalOrganizations[index].organizationName,
                            caseNumber: $principalOrganizations[index].caseNumber,
                            organizationOptions: organizationOptions,
                            selectedOrganization: selectedOrganization(for: principalOrganizations[index]),
                            isEmpty: principalOrganizations[index].isEmpty,
                            language: language,
                            organizationWidth: organizationWidth,
                            caseNumberWidth: caseNumberWidth,
                            accessoryAlignmentFillerWidth: accessoryAlignmentFillerWidth,
                            trailingAccessoryWidth: trailingAccessoryWidth,
                            onOrganizationCommit: {
                                if principalOrganizations.indices.contains(index) {
                                    reconcileOrganizationReference(at: index)
                                }
                            },
                            onOrganizationSelect: { selectedName in
                                if principalOrganizations.indices.contains(index) {
                                    applyOrganizationSelection(selectedName, at: index)
                                }
                            },
                            onOpenOrganization: openOrganization,
                            onDelete: {
                                if principalOrganizations.indices.contains(index) {
                                    principalOrganizations.remove(at: index)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, isEditingLocked ? 0 : 10)
                .padding(.vertical, isEditingLocked ? 1 : 0)
            }
        }
        .onChange(of: principalOrganizations) { oldValue, newValue in
            let normalized = normalizedRows(newValue, placeholderID: oldValue.first(where: { $0.isEmpty })?.id)
            if normalized != newValue {
                principalOrganizations = normalized
            }
        }
    }

    private func normalizedRows(_ rows: [ProjectPrincipalOrganization], placeholderID: String? = nil) -> [ProjectPrincipalOrganization] {
        let retainedPlaceholderID = rows.first(where: { $0.isEmpty })?.id ?? placeholderID ?? UUID().uuidString
        let filledRows = rows.compactMap { row -> ProjectPrincipalOrganization? in
            var copy = row
            copy.normalize()
            copy = resolvedOrganizationReference(copy)
            return copy.isEmpty ? nil : copy
        }
        return filledRows + [ProjectPrincipalOrganization(id: retainedPlaceholderID)]
    }

    private func displayName(for principal: ProjectPrincipalOrganization) -> String {
        selectedOrganization(for: principal)?.displayName(for: language)
            ?? principal.organizationName
    }

    private func selectedOrganization(for principal: ProjectPrincipalOrganization) -> OrganizationRecord? {
        if let id = principal.organizationID?.trimmedOrNil,
           let organization = organizations.first(where: { $0.id == id }) {
            return organization
        }
        return matchingOrganization(named: principal.organizationName)
    }

    private func matchingOrganization(named name: String?) -> OrganizationRecord? {
        guard let trimmed = name?.trimmedOrNil else { return nil }
        if let exactID = organizations.first(where: { $0.id == trimmed }) {
            return exactID
        }
        return organizations.first {
            $0.nameSv.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                || $0.nameEn.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                || $0.displayName(for: language).localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private func resolvedOrganizationReference(_ principal: ProjectPrincipalOrganization) -> ProjectPrincipalOrganization {
        var copy = principal
        if let organization = selectedOrganization(for: copy) {
            copy.organizationID = organization.id
            copy.organizationName = organization.displayName(for: language)
        } else if copy.organizationID?.trimmedOrNil != nil {
            copy.organizationID = nil
        }
        copy.normalize()
        return copy
    }

    private func reconcileOrganizationReference(at index: Int) {
        guard principalOrganizations.indices.contains(index) else { return }
        principalOrganizations[index] = resolvedOrganizationReference(principalOrganizations[index])
    }

    private func applyOrganizationSelection(_ selectedName: String, at index: Int) {
        guard principalOrganizations.indices.contains(index) else { return }
        principalOrganizations[index].organizationName = selectedName
        principalOrganizations[index] = resolvedOrganizationReference(principalOrganizations[index])
    }
}

private struct EditableProjectPrincipalOrganizationRow: View {
    @Binding var organizationName: String
    @Binding var caseNumber: String
    let organizationOptions: [String]
    let selectedOrganization: OrganizationRecord?
    let isEmpty: Bool
    let language: AppLanguage
    let organizationWidth: CGFloat
    let caseNumberWidth: CGFloat
    let accessoryAlignmentFillerWidth: CGFloat
    let trailingAccessoryWidth: CGFloat
    let onOrganizationCommit: () -> Void
    let onOrganizationSelect: (String) -> Void
    let onOpenOrganization: ((OrganizationRecord) -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: projectComplianceColumnSpacing) {
            AutocompleteSelectionField(
                text: $organizationName,
                options: organizationOptions,
                placeholder: language.text("Organization", "Organisation"),
                onCommit: onOrganizationCommit,
                onSelect: onOrganizationSelect
            )
            .frame(width: organizationWidth)
            .frame(minHeight: 18)

            CommitFormattingTextField(
                placeholder: language.text("Case number", "Diarienummer"),
                text: $caseNumber,
                formatter: { $0 },
                showsRenewedSurface: false,
                isBordered: false
            )
            .frame(minHeight: 18)
            .appTextInputChrome(fillsWidth: true)
            // The width cap must sit OUTSIDE the chrome: fillsWidth expands
            // the chrome to any width offered, pushing the accessories off
            // the ethics rows' position.
            .frame(width: caseNumberWidth)

            Color.clear.frame(width: accessoryAlignmentFillerWidth, height: 1)

            if let selectedOrganization {
                AppDestinationActionButton(
                    kind: .app,
                    language: language,
                    title: language.text("Open organization", "Öppna organisation"),
                    fontSize: 12,
                    width: trailingAccessoryWidth
                ) {
                    onOpenOrganization?(selectedOrganization)
                }
            } else {
                AppDestinationPlaceholder(width: trailingAccessoryWidth, height: 1)
            }

            if isEmpty {
                AppDestinationPlaceholder(width: trailingAccessoryWidth, height: 1)
            } else {
                AppInlineDeleteButton(
                    title: language.text("Remove research principal", "Ta bort forskningshuvudman"),
                    width: trailingAccessoryWidth
                ) {
                    onDelete()
                }
            }
        }
    }
}

private struct ProjectClinicalTrialRegistrationEditor: View {
    @Binding var registration: ProjectClinicalTrialRegistration
    let language: AppLanguage
    var onRemove: (() -> Void)? = nil
    var isEditingLocked = false
    private let identifierFieldWidth: CGFloat = 160
    private let trailingAccessoryWidth: CGFloat = 94

    private var linkURL: URL? {
        let trialID = registration.trialID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trialID.isEmpty else { return nil }
        return URL(string: "https://clinicaltrials.gov/study/\(trialID)")
    }

    var body: some View {
        let dateRangeState = AppFieldValidators.optionalDateRange(from: registration.registeredOn, to: registration.updatedOn, language: language).state
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: projectComplianceColumnSpacing) {
                Color.clear.frame(width: 120)
                projectComplianceHeaderText(language.text("Registered", "Registrerad"), compact: isEditingLocked)
                    .frame(width: 170, alignment: .leading)
                projectComplianceHeaderText(language.text("Last updated", "Senast uppdaterad"), compact: isEditingLocked)
                    .frame(width: 170, alignment: .leading)
                projectComplianceHeaderText("ID", compact: isEditingLocked)
                    .frame(width: identifierFieldWidth, alignment: .leading)
                Color.clear.frame(width: trailingAccessoryWidth)
            }
            .padding(.horizontal, 10)

            HStack(alignment: .top, spacing: projectComplianceColumnSpacing) {
                Color.clear.frame(width: 120)
                ProjectFieldStack(title: "", width: 170) {
                    if isEditingLocked {
                        lockedProjectComplianceValue(registration.registeredOn, state: dateRangeState)
                    } else {
                        CommitDateFieldWithTodayButton(
                            placeholder: language.datePlaceholder,
                            text: $registration.registeredOn,
                            formatter: DateParsers.canonicalizedDayInput,
                            clearBackgroundInDarkNew: true,
                            width: 110,
                            state: dateRangeState
                        )
                    }
                }
                ProjectFieldStack(title: "", width: 170) {
                    if isEditingLocked {
                        lockedProjectComplianceValue(registration.updatedOn, state: dateRangeState)
                    } else {
                        CommitDateFieldWithTodayButton(
                            placeholder: language.datePlaceholder,
                            text: $registration.updatedOn,
                            formatter: DateParsers.canonicalizedDayInput,
                            clearBackgroundInDarkNew: true,
                            width: 110,
                            state: dateRangeState
                        )
                    }
                }
                ProjectFieldStack(title: "", width: identifierFieldWidth) {
                    if isEditingLocked {
                        lockedProjectComplianceValue(registration.trialID)
                    } else {
                        CommitFormattingTextField(
                            placeholder: "NCT00000000",
                            text: $registration.trialID,
                            formatter: { $0 },
                            showsRenewedSurface: false,
                            isBordered: false
                        )
                        .frame(minHeight: 18)
                        .appTextInputChrome(fillsWidth: true)
                    }
                }
                HStack(spacing: 8) {
                    Group {
                        if let linkURL {
                            AppDestinationURLLink(
                                kind: .web,
                                language: language,
                                destination: linkURL,
                                fontSize: 12
                            )
                        } else {
                            AppDestinationPlaceholder()
                        }
                    }
                    .frame(width: 48, alignment: .trailing)

                    Group {
                        if !isEditingLocked, let onRemove {
                            AppInlineDeleteButton(
                                title: language.text("Remove clinical trial row", "Ta bort clinicaltrials-rad")
                            ) {
                                onRemove()
                            }
                            .disabled(registration.isEmpty)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 22, alignment: .center)
                }
                .frame(width: trailingAccessoryWidth, height: 28, alignment: .center)
                .padding(.top, 5)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 0)
    }
}

private struct ProjectDataCollectionEditor: View {
    @Binding var dataCollections: [ProjectDataCollection]
    let language: AppLanguage
    var isEditingLocked = false

    private var visibleDataCollections: [ProjectDataCollection] {
        isEditingLocked ? dataCollections.filter { !$0.isEmpty } : dataCollections
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: projectComplianceColumnSpacing) {
                projectComplianceHeaderText(language.text("Status", "Status"), compact: isEditingLocked)
                    .frame(width: 120, alignment: .leading)
                projectComplianceHeaderText(language.text("From", "Från"), compact: isEditingLocked)
                    .frame(width: 170, alignment: .leading)
                projectComplianceHeaderText(language.text("To", "Till"), compact: isEditingLocked)
                    .frame(width: 170, alignment: .leading)
                Color.clear.frame(width: 24)
            }
            .padding(.bottom, isEditingLocked ? 0 : 1)

            ForEach(Array(visibleDataCollections.enumerated()), id: \.element.id) { visibleIndex, collection in
                let index = dataCollections.firstIndex { $0.id == collection.id } ?? visibleIndex
                let dateRangeState = AppFieldValidators.optionalDateRange(from: collection.from, to: collection.to, language: language).state
                HStack(alignment: .top, spacing: projectComplianceColumnSpacing) {
                    ProjectFieldStack(title: "", width: 120) {
                        if isEditingLocked {
                            lockedProjectComplianceValue(collection.statusLabel(language: language))
                        } else {
                            AppLockedFieldValueText(text: dataCollections[index].statusLabel(language: language))
                        }
                    }
                    ProjectFieldStack(title: "", width: 170) {
                        if isEditingLocked {
                            lockedProjectComplianceValue(collection.from, state: dateRangeState)
                        } else {
                            CommitDateFieldWithTodayButton(
                                placeholder: language.datePlaceholder,
                                text: Binding(
                                    get: { dataCollections[index].from },
                                    set: { newValue in
                                        let previousFrom = dataCollections[index].from
                                        dataCollections[index].from = newValue
                                        if let shiftedTo = shiftedDateRangeEnd(
                                            previousStart: previousFrom,
                                            newStart: newValue,
                                            currentEnd: dataCollections[index].to
                                        ) {
                                            dataCollections[index].to = shiftedTo
                                        }
                                    }
                                ),
                                formatter: DateParsers.canonicalizedDayInput,
                                updatesContinuously: false,
                                clearBackgroundInDarkNew: true,
                                width: 110,
                                state: dateRangeState
                            )
                        }
                    }
                    ProjectFieldStack(title: "", width: 170) {
                        if isEditingLocked {
                            lockedProjectComplianceValue(collection.to, state: dateRangeState)
                        } else {
                            CommitDateFieldWithTodayButton(
                                placeholder: language.datePlaceholder,
                                text: $dataCollections[index].to,
                                formatter: DateParsers.canonicalizedDayInput,
                                updatesContinuously: false,
                                clearBackgroundInDarkNew: true,
                                width: 110,
                                state: dateRangeState
                            )
                        }
                    }
                    Group {
                        if isEditingLocked || (index == dataCollections.count - 1 && dataCollections[index].isEmpty) {
                            Color.clear.frame(width: 24, height: 18)
                        } else {
                            AppInlineDeleteButton(
                                title: language.text("Remove data collection row", "Ta bort datainsamlingsrad"),
                                width: 24
                            ) {
                                dataCollections.remove(at: index)
                            }
                        }
                    }
                    .frame(width: 24, alignment: .center)
                    .padding(.top, isEditingLocked ? 0 : 5)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isEditingLocked ? 0 : 3)
    }
}

private func lockedProjectComplianceValue(_ value: String?, state: AppFieldVisualState = .normal) -> some View {
    AppLockedInlineValueText(text: value, isInvalid: state.isInvalid, help: state.helpText)
        .frame(maxWidth: .infinity, alignment: .leading)
}
