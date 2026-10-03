import SwiftUI

/// Forskarkortet: befattningar som rader, i samma stil som examensraderna:
/// ett val ur listan per rad (akademiska först, sedan kliniska, sist övrigt),
/// en läkarspecialitet för ST-läkare, Specialistläkare och Överläkare, en
/// sjuksköterskespecialitet för Specialistsjuksköterska, och
/// "Annan befattning…" för en befattning som inte finns i listan.
struct ResearcherPositionPickerField: View {
    @Binding var positionIDs: [String]
    @Binding var otherText: String
    @Binding var specialtyIDs: [String: String]
    let options: [ResearcherPositionOption]
    let specialtyOptions: [ResearcherSpecialtyOption]
    /// Den gamla fritexten, visas som hjälp när den skiljer sig från valen.
    let legacyText: String
    let language: AppLanguage
    let isDisabled: Bool
    /// Anropas när "annan"-texten ändras med en knapp eller ett menyval
    /// (texten som skrivs sparas när rutan lämnas).
    let onChoiceChange: () -> Void

    @State private var showsOtherRow = false

    private static let otherValue = "__other__"
    private static let noSpecialtyValue = "__no-specialty__"

    private var selectedOptions: [ResearcherPositionOption] {
        let selected: [ResearcherPositionOption] = positionIDs.compactMap { id in options.first(where: { $0.id == id }) }
        return ResearcherPositionOption.displaySorted(selected)
    }

    private var isOtherRowVisible: Bool {
        showsOtherRow || otherText.trimmedOrNil != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(selectedOptions) { option in
                positionRow(option)
            }
            if isOtherRowVisible {
                otherRow
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
        var names: [String] = []
        for option in selectedOptions {
            names.append(option.displayName(specialty: specialty(forPositionID: option.id), language: language))
        }
        if let other = otherText.trimmedOrNil {
            names.append(other)
        }
        let chosen = names.joined(separator: ", ")
        guard legacy != chosen else { return nil }
        return language.text("Previously written: \(legacy)", "Tidigare text: \(legacy)")
    }

    private func specialty(forPositionID positionID: String) -> ResearcherSpecialtyOption? {
        guard let specialtyID = specialtyIDs[positionID]?.trimmedOrNil else { return nil }
        return specialtyOptions.first { $0.id == specialtyID }
    }

    // MARK: Rader

    private func positionRow(_ option: ResearcherPositionOption) -> some View {
        HStack(spacing: 6) {
            AppMenuSelectionField(
                selection: positionBinding(for: option.id),
                options: positionPickerOptions(currentID: option.id)
            )
            .frame(width: 190)
            .disabled(isDisabled)
            .help(positionHelp(option))
            if let kind = option.specialtyKind {
                AppMenuSelectionField(
                    selection: specialtyBinding(for: option.id),
                    options: specialtyPickerOptions(kind: kind, selectedID: specialtyIDs[option.id]),
                    placeholder: language.text("Specialty…", "Specialitet…"),
                    clearValue: ""
                )
                .frame(maxWidth: .infinity)
                .disabled(isDisabled)
                .help(specialtyHelp(kind))
            } else {
                Spacer(minLength: 0)
            }
            removeButton(help: language.text("Remove this position", "Ta bort befattningen")) {
                remove(option.id)
            }
        }
    }

    private var otherRow: some View {
        HStack(spacing: 6) {
            AppMenuSelectionField(
                selection: otherRowBinding,
                options: positionPickerOptions(currentID: nil)
            )
            .frame(width: 190)
            .disabled(isDisabled)
            TextField(
                language.text("Position not in the list", "Befattning som inte finns i listan"),
                text: $otherText
            )
            .appTextInputChrome()
            .disabled(isDisabled)
            .help(language.text(
                "A position that is not in the list (shown after the chosen ones and flagged in Data quality)",
                "En befattning som inte finns i listan (visas efter de valda och flaggas i Datakvalitet)"
            ))
            removeButton(help: language.text("Remove the other position", "Ta bort den andra befattningen")) {
                otherText = ""
                showsOtherRow = false
                onChoiceChange()
            }
        }
    }

    private func removeButton(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
    }

    private func positionHelp(_ option: ResearcherPositionOption) -> String {
        guard let hint = option.careerStageHint else {
            return option.group.displayName(language: language)
        }
        return language.text(
            "\(option.group.displayName(language: language)). Suggests career stage \(hint.rawValue).",
            "\(option.group.displayName(language: language)). Talar för karriärsteg \(hint.rawValue)."
        )
    }

    // MARK: Menyer

    /// Listans befattningar (akademiska, kliniska, övrigt) utom de som redan
    /// är valda på andra rader, och sist "Annan befattning…".
    private func positionPickerOptions(currentID: String?) -> [(label: String, value: String)] {
        var result: [(label: String, value: String)] = []
        for option in ResearcherPositionOption.displaySorted(options) {
            let isCurrent = option.id == currentID
            if !isCurrent && positionIDs.contains(option.id) { continue }
            if option.isHidden && !isCurrent { continue }
            result.append((label: option.localizedName(language: language), value: option.id))
        }
        result.append((label: language.text("Other position…", "Annan befattning…"), value: Self.otherValue))
        return result
    }

    private func specialtyHelp(_ kind: ResearcherSpecialtyKind) -> String {
        switch kind {
        case .physician:
            return language.text(
                "Physician specialty. The list is edited under Settings > Lists.",
                "Läkarspecialitet. Listan ändras under Inställningar > Listor."
            )
        case .nurse:
            return language.text(
                "Nurse specialty. The list is edited under Settings > Lists.",
                "Sjuksköterskespecialitet. Listan ändras under Inställningar > Listor."
            )
        }
    }

    /// Specialiteterna av befattningens sort (läkare eller sjuksköterska);
    /// en redan vald specialitet visas alltid, även om den är dold.
    private func specialtyPickerOptions(kind: ResearcherSpecialtyKind, selectedID: String?) -> [(label: String, value: String)] {
        var result: [(label: String, value: String)] = []
        let choices = ResearcherPositionPickerField.specialtyChoices(
            specialtyOptions,
            kind: kind,
            selectedID: selectedID
        )
        for option in choices {
            result.append((label: option.localizedName(language: language), value: option.id))
        }
        if selectedID?.trimmedOrNil != nil {
            result.append((label: language.text("No specialty", "Ingen specialitet"), value: Self.noSpecialtyValue))
        }
        return result
    }

    private var addMenu: some View {
        Menu {
            ForEach(ResearcherPositionGroup.displayOrder) { group in
                addMenuSection(group)
            }
            Divider()
            Button(language.text("Other position…", "Annan befattning…")) {
                showsOtherRow = true
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

    @ViewBuilder
    private func addMenuSection(_ group: ResearcherPositionGroup) -> some View {
        let groupOptions: [ResearcherPositionOption] = options.filter { option in
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

    // MARK: Ändringar

    private func toggle(_ id: String) {
        if positionIDs.contains(id) {
            remove(id)
        } else {
            positionIDs.append(id)
        }
    }

    private func remove(_ id: String) {
        if specialtyIDs[id] != nil {
            var map = specialtyIDs
            map.removeValue(forKey: id)
            specialtyIDs = map
        }
        positionIDs.removeAll { $0 == id }
    }

    /// Byter befattningen på en rad. En specialitet följer med när den nya
    /// befattningen kan ha samma sorts specialitet (t.ex. ST-läkare →
    /// Specialistläkare, men inte Specialistläkare → Specialistsjuksköterska).
    private func replace(_ currentID: String, with newID: String) {
        guard newID != currentID else { return }
        if newID == Self.otherValue {
            remove(currentID)
            showsOtherRow = true
            return
        }
        if let specialtyID = specialtyIDs[currentID] {
            var map = specialtyIDs
            map.removeValue(forKey: currentID)
            let oldKind = ResearcherPositionOption.specialtyKind(forPositionID: currentID)
            let newKind = ResearcherPositionOption.specialtyKind(forPositionID: newID)
            if newKind != nil && newKind == oldKind && map[newID] == nil {
                map[newID] = specialtyID
            }
            specialtyIDs = map
        }
        var ids = positionIDs
        if ids.contains(newID) {
            ids.removeAll { $0 == currentID }
        } else if let index = ids.firstIndex(of: currentID) {
            ids[index] = newID
        } else {
            ids.append(newID)
        }
        positionIDs = ids
    }

    private func positionBinding(for currentID: String) -> Binding<String> {
        Binding(
            get: { currentID },
            set: { newValue in replace(currentID, with: newValue) }
        )
    }

    /// "Annan befattning…"-raden: ett val ur listan gör texten till det
    /// valet (texten på appens språk töms; den andra språkets text lämnas).
    private var otherRowBinding: Binding<String> {
        Binding(
            get: { Self.otherValue },
            set: { newValue in
                guard newValue != Self.otherValue else { return }
                if !positionIDs.contains(newValue) {
                    positionIDs.append(newValue)
                }
                otherText = ""
                showsOtherRow = false
                onChoiceChange()
            }
        )
    }

    private func specialtyBinding(for positionID: String) -> Binding<String> {
        Binding(
            get: { specialtyIDs[positionID] ?? "" },
            set: { newValue in
                var map = specialtyIDs
                if newValue.isEmpty || newValue == Self.noSpecialtyValue {
                    map.removeValue(forKey: positionID)
                } else {
                    map[positionID] = newValue
                }
                guard map != specialtyIDs else { return }
                specialtyIDs = map
            }
        )
    }

    /// Specialiteterna som erbjuds för en befattning: de av rätt sort som
    /// inte är dolda, och den som redan är vald (även om den är dold eller
    /// av fel sort, så att valet syns).
    nonisolated static func specialtyChoices(
        _ options: [ResearcherSpecialtyOption],
        kind: ResearcherSpecialtyKind,
        selectedID: String?
    ) -> [ResearcherSpecialtyOption] {
        options.filter { option in
            if option.id == selectedID { return true }
            return option.kind == kind && !option.isHidden
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
