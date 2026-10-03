import SwiftUI

/// Forskarkortet: befattningar valda ur listan (flera går att välja) och en
/// fri text för en befattning som inte finns i listan.
struct ResearcherPositionPickerField: View {
    @Binding var positionIDs: [String]
    @Binding var otherText: String
    let options: [ResearcherPositionOption]
    /// Den gamla fritexten, visas som hjälp när den skiljer sig från valen.
    let legacyText: String
    let language: AppLanguage
    let isDisabled: Bool

    private var selectedOptions: [ResearcherPositionOption] {
        positionIDs.compactMap { id in options.first(where: { $0.id == id }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(selectedOptions) { option in
                selectedRow(option)
            }
            HStack(spacing: 8) {
                addMenu
                TextField(
                    language.text("Other position…", "Annan befattning…"),
                    text: $otherText
                )
                .appTextInputChrome()
                .disabled(isDisabled)
                .help(language.text(
                    "A position that is not in the list (shown after the chosen ones and flagged in Data quality)",
                    "En befattning som inte finns i listan (visas efter de valda och flaggas i Datakvalitet)"
                ))
            }
            if let hint = legacyHint {
                Text(hint)
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var legacyHint: String? {
        guard let legacy = legacyText.trimmedOrNil else { return nil }
        let chosen = (selectedOptions.map { $0.localizedName(language: language) } + [otherText.trimmedOrNil].compactMap { $0 })
            .joined(separator: ", ")
        guard legacy != chosen else { return nil }
        return language.text("Previously written: \(legacy)", "Tidigare text: \(legacy)")
    }

    private func selectedRow(_ option: ResearcherPositionOption) -> some View {
        HStack(spacing: 6) {
            Text(option.localizedName(language: language))
                .appTypography(.body)
                .lineLimit(1)
            if let hint = option.careerStageHint {
                Text(hint.rawValue)
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                    .help(language.text("Career stage this position suggests", "Karriärsteg som befattningen talar för"))
            }
            Spacer(minLength: 4)
            Button {
                positionIDs.removeAll { $0 == option.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .help(language.text("Remove this position", "Ta bort befattningen"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppPalette.fieldSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
    }

    private var addMenu: some View {
        Menu {
            ForEach(ResearcherPositionGroup.allCases) { group in
                let groupOptions = options.filter { option in
                    option.group == group && (!option.isHidden || positionIDs.contains(option.id))
                }
                if !groupOptions.isEmpty {
                    Section(group.displayName(language: language)) {
                        ForEach(groupOptions) { option in
                            Button {
                                toggle(option.id)
                            } label: {
                                if positionIDs.contains(option.id) {
                                    Label(option.localizedName(language: language), systemImage: "checkmark")
                                } else {
                                    Text(option.localizedName(language: language))
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Label(language.text("Add position", "Lägg till befattning"), systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(appFont(.secondary).weight(.semibold))
        .disabled(isDisabled)
        .help(language.text(
            "Choose one or more positions. The list is edited under Settings > Lists.",
            "Välj en eller flera befattningar. Listan ändras under Inställningar > Listor."
        ))
    }

    private func toggle(_ id: String) {
        if positionIDs.contains(id) {
            positionIDs.removeAll { $0 == id }
        } else {
            positionIDs.append(id)
        }
    }
}

/// Forskarkortet: examina som rader med val ur listan, ämne när examen har
/// ämne, och "Annan examen" som fri text.
struct ResearcherDegreeListField: View {
    @Binding var entries: [ResearcherDegreeEntry]
    let options: [ResearcherDegreeOption]
    let legacyText: String
    let language: AppLanguage
    let isDisabled: Bool
    /// Anropas när ett val i en meny ändras (texten sparas när rutan lämnas).
    let onChoiceChange: () -> Void

    private static let otherValue = "__other__"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                entryRow(index: index, entry: entry)
            }
            addMenu
            if let hint = legacyHint {
                Text(hint)
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var legacyHint: String? {
        guard let legacy = legacyText.trimmedOrNil else { return nil }
        let chosen = entries
            .map { $0.displayText(options: options, language: language) }
            .compactMap(\.trimmedOrNil)
            .joined(separator: ", ")
        guard legacy != chosen else { return nil }
        return language.text("Previously written: \(legacy)", "Tidigare text: \(legacy)")
    }

    private func pickerOptions(selectedID: String?) -> [(label: String, value: String)] {
        var result: [(label: String, value: String)] = []
        for option in options where !option.isHidden || option.id == selectedID {
            let name = option.localizedName(language: language)
            let label = option.abbreviation.trimmedOrNil.map { "\(name) (\($0))" } ?? name
            result.append((label: label, value: option.id))
        }
        result.append((label: language.text("Other degree…", "Annan examen…"), value: Self.otherValue))
        return result
    }

    private func entryRow(index: Int, entry: ResearcherDegreeEntry) -> some View {
        let option = entry.optionID.flatMap { id in options.first(where: { $0.id == id }) }
        return HStack(spacing: 6) {
            AppMenuSelectionField(
                selection: optionBinding(index: index),
                options: pickerOptions(selectedID: entry.optionID)
            )
            .frame(width: 190)
            .disabled(isDisabled)
            if let option {
                if option.takesSubject {
                    TextField(
                        language.text("Subject, e.g. Epidemiology", "Ämne, t.ex. epidemiologi"),
                        text: subjectBinding(index: index)
                    )
                    .appTextInputChrome()
                    .disabled(isDisabled)
                } else {
                    Spacer(minLength: 0)
                }
            } else {
                TextField(
                    language.text("Degree not in the list", "Examen som inte finns i listan"),
                    text: otherTextBinding(index: index)
                )
                .appTextInputChrome()
                .disabled(isDisabled)
            }
            Button {
                remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .help(language.text("Remove this degree", "Ta bort examen"))
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(options.filter { !$0.isHidden }) { option in
                Button(option.localizedName(language: language)) {
                    entries.append(ResearcherDegreeEntry(optionID: option.id))
                    onChoiceChange()
                }
            }
            Divider()
            Button(language.text("Other degree…", "Annan examen…")) {
                entries.append(ResearcherDegreeEntry())
            }
        } label: {
            Label(language.text("Add degree", "Lägg till examen"), systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(appFont(.secondary).weight(.semibold))
        .disabled(isDisabled)
        .help(language.text(
            "Add a degree from the list. The list is edited under Settings > Lists.",
            "Lägg till en examen ur listan. Listan ändras under Inställningar > Listor."
        ))
    }

    private func remove(at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        onChoiceChange()
    }

    private func optionBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                guard entries.indices.contains(index) else { return Self.otherValue }
                return entries[index].optionID ?? Self.otherValue
            },
            set: { newValue in
                guard entries.indices.contains(index) else { return }
                let newID: String? = newValue == Self.otherValue ? nil : newValue
                guard entries[index].optionID != newID else { return }
                entries[index].optionID = newID
                onChoiceChange()
            }
        )
    }

    private func subjectBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                guard entries.indices.contains(index) else { return "" }
                return language == .swedish ? entries[index].subjectSv : entries[index].subjectEn
            },
            set: { newValue in
                guard entries.indices.contains(index) else { return }
                entries[index].setLocalizedSubject(newValue, language: language)
            }
        )
    }

    private func otherTextBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                guard entries.indices.contains(index) else { return "" }
                return entries[index].otherText
            },
            set: { newValue in
                guard entries.indices.contains(index) else { return }
                entries[index].otherText = newValue
            }
        )
    }
}
