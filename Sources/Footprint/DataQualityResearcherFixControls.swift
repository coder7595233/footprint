import SwiftUI

/// Datakvalitet > Integritet: små kontroller under en forskarvarning, så att
/// karriärsteg, doktorsexamen och text utanför listorna kan rättas direkt i
/// raden (samma utseende som rutorna under "Saknade fält"). Allt sparas
/// genom forskarens vanliga autosave, så Ångra fungerar.
struct DataQualityResearcherFixControls: View {
    let store: GrantDataStore
    let authorID: String
    let fix: GrantDataStore.ResearcherIntegrityFix
    let language: AppLanguage

    var body: some View {
        switch fix {
        case .careerStageSuggestion(let current, let suggestion):
            stageSuggestionControls(current: current, suggestion: suggestion)
        case .careerStagePhD(let current, let hasPhD):
            phdControls(current: current, hasPhD: hasPhD)
        case .positionOutsideList(let parts):
            positionControls(parts: parts)
        case .degreeOutsideList(let entries):
            degreeControls(entries: entries)
        }
    }

    // MARK: Karriärsteg

    private func stageSuggestionControls(
        current: PublicationAuthorCareerStage?,
        suggestion: PublicationAuthorCareerStage
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                _ = store.applyResearcherCareerStageSuggestion(authorID: authorID)
            } label: {
                Text(language.text("Use \(suggestion.rawValue)", "Använd \(suggestion.rawValue)"))
                    .font(appFont(.secondary).weight(.semibold))
                    .frame(height: 22)
            }
            .buttonStyle(.borderless)
            .help(language.text(
                "Set the career stage the position suggests",
                "Sätt karriärsteget som befattningen talar för"
            ))
            stageSelector(current: current)
        }
    }

    private func phdControls(current: PublicationAuthorCareerStage?, hasPhD: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle(language.text("PhD", "Doktorsexamen"), isOn: phdBinding(hasPhD: hasPhD))
                .appCheckboxStyle()
                .fixedSize()
                .help(language.text("The researcher has a PhD", "Forskaren har doktorsexamen"))
            stageSelector(current: current)
        }
    }

    private func phdBinding(hasPhD: Bool) -> Binding<Bool> {
        Binding(
            get: { hasPhD },
            set: { newValue in
                _ = store.setResearcherPhDFromDataQuality(authorID: authorID, hasPhD: newValue)
            }
        )
    }

    private func stageSelector(current: PublicationAuthorCareerStage?) -> some View {
        HStack(spacing: 6) {
            Text(language.text("Career stage", "Karriärsteg"))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
            DataQualityCareerStageSelector(selection: current, language: language) { stage in
                _ = store.setResearcherCareerStageFromDataQuality(authorID: authorID, stage: stage)
            }
        }
    }

    // MARK: Befattning utanför listan

    private func positionControls(parts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { item in
                positionPartRow(part: item.element, showsPart: parts.count > 1)
            }
        }
    }

    private func positionPartRow(part: String, showsPart: Bool) -> some View {
        HStack(spacing: 10) {
            if showsPart {
                Text(part)
                    .appTypography(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            choosePositionMenu(part: part)
            addPositionMenu(part: part)
        }
    }

    private func choosePositionMenu(part: String) -> some View {
        Menu {
            ForEach(ResearcherPositionGroup.displayOrder) { group in
                positionMenuSection(group: group, part: part)
            }
        } label: {
            Text(language.text("Choose position", "Välj befattning"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(appFont(.secondary).weight(.semibold))
        .help(language.text(
            "Choose the position from the list; the text \"\(part)\" is then removed from the other position",
            "Välj befattningen ur listan; texten \"\(part)\" tas då bort ur annan befattning"
        ))
    }

    @ViewBuilder
    private func positionMenuSection(group: ResearcherPositionGroup, part: String) -> some View {
        let groupOptions: [ResearcherPositionOption] = store.researcherPositionOptions.filter { option in
            option.group == group && !option.isHidden
        }
        if !groupOptions.isEmpty {
            Section(group.displayName(language: language)) {
                ForEach(groupOptions) { option in
                    Button(option.localizedName(language: language)) {
                        _ = store.chooseResearcherPositionForOutsideText(authorID: authorID, part: part, optionID: option.id)
                    }
                }
            }
        }
    }

    private func addPositionMenu(part: String) -> some View {
        Menu {
            Section(language.text("Add to the list in group", "Lägg till i listan i gruppen")) {
                ForEach(ResearcherPositionGroup.displayOrder) { group in
                    Button(group.displayName(language: language)) {
                        _ = store.addResearcherPositionToListFromDataQuality(authorID: authorID, part: part, group: group)
                    }
                }
            }
        } label: {
            Text(language.text("Add to list", "Lägg till i listan"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(appFont(.secondary).weight(.semibold))
        .help(language.text(
            "Add \"\(part)\" as a new position under Settings > Lists and choose it",
            "Lägg till \"\(part)\" som ny befattning under Inställningar > Listor och välj den"
        ))
    }

    // MARK: Examen utanför listan

    private func degreeControls(entries: [GrantDataStore.ResearcherDegreeOutsideList]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entries) { entry in
                degreeEntryRow(entry: entry, showsText: entries.count > 1)
            }
        }
    }

    private func degreeEntryRow(entry: GrantDataStore.ResearcherDegreeOutsideList, showsText: Bool) -> some View {
        HStack(spacing: 10) {
            if showsText {
                Text(entry.text)
                    .appTypography(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            chooseDegreeMenu(entry: entry)
            Button {
                _ = store.addResearcherDegreeToListFromDataQuality(authorID: authorID, entryID: entry.id)
            } label: {
                Text(language.text("Add to list", "Lägg till i listan"))
                    .font(appFont(.secondary).weight(.semibold))
                    .frame(height: 22)
            }
            .buttonStyle(.borderless)
            .help(language.text(
                "Add \"\(entry.text)\" as a new degree under Settings > Lists and choose it",
                "Lägg till \"\(entry.text)\" som ny examen under Inställningar > Listor och välj den"
            ))
        }
    }

    private func chooseDegreeMenu(entry: GrantDataStore.ResearcherDegreeOutsideList) -> some View {
        let degreeOptions: [ResearcherDegreeOption] = store.researcherDegreeOptions.filter { !$0.isHidden }
        return Menu {
            ForEach(degreeOptions) { option in
                Button(degreeLabel(option)) {
                    _ = store.chooseResearcherDegreeForOutsideText(authorID: authorID, entryID: entry.id, optionID: option.id)
                }
            }
        } label: {
            Text(language.text("Choose degree", "Välj examen"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(appFont(.secondary).weight(.semibold))
        .help(language.text(
            "Choose the degree from the list. For a degree with a subject the text becomes the subject; text that is not explained by the choice is kept.",
            "Välj examen ur listan. För en examen med ämne blir texten ämnet; text som inte förklaras av valet sparas."
        ))
    }

    private func degreeLabel(_ option: ResearcherDegreeOption) -> String {
        let name = option.localizedName(language: language)
        guard let abbreviation = option.abbreviation.trimmedOrNil else { return name }
        return "\(name) (\(abbreviation))"
    }
}

/// D, C, B, A som små knappar; ett klick på det valda steget tar bort det
/// (inget karriärsteg), precis som på forskarkortet.
struct DataQualityCareerStageSelector: View {
    let selection: PublicationAuthorCareerStage?
    let language: AppLanguage
    let onSelect: (PublicationAuthorCareerStage?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PublicationAuthorCareerStage.editorDisplayOrder) { stage in
                segment(stage)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppPalette.fieldSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.text("Career stage", "Karriärsteg"))
    }

    private func segment(_ stage: PublicationAuthorCareerStage) -> some View {
        let isSelected: Bool = selection == stage
        let textColor: Color = isSelected ? AppPalette.appText : AppPalette.appText.opacity(0.75)
        let fillColor: Color = isSelected ? AppPalette.vividBlue.opacity(0.22) : Color.clear
        return Button {
            onSelect(isSelected ? nil : stage)
        } label: {
            Text(stage.rawValue)
                .font(appFont(.secondary).weight(.semibold))
                .foregroundStyle(textColor)
                .frame(width: 26, height: 20)
                .background(fillColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isSelected
            ? language.text("Click again to clear the career stage", "Klicka igen för att ta bort karriärsteget")
            : stage.helpText)
    }
}
