import SwiftUI

/// Inställningar > Listor: befattningar och examina som går att välja på
/// forskarkortet. Forskarna sparar valens id, så ett nytt namn här syns
/// överallt. Ett val kan bara raderas när ingen forskare använder det.
struct ResearcherOptionListsSettingsPanel: View {
    @ObservedObject var store: GrantDataStore

    @State private var positions: [ResearcherPositionOption] = []
    @State private var degrees: [ResearcherDegreeOption] = []
    @State private var specialties: [ResearcherSpecialtyOption] = []
    @State private var hasLoaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var pendingPositionDeletionID: String?
    @State private var pendingDegreeDeletionID: String?
    @State private var pendingSpecialtyDeletionID: String?

    private var language: AppLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            positionsCard
            degreesCard
            specialtiesSection
        }
        .onAppear(perform: load)
        .onChange(of: positions) { _, _ in scheduleSave() }
        .onChange(of: degrees) { _, _ in scheduleSave() }
        .onChange(of: specialties) { _, _ in scheduleSave() }
        .onDisappear {
            saveTask?.cancel()
            if hasLoaded {
                saveNow()
            }
        }
        .alert(
            language.text("Delete position?", "Radera befattningen?"),
            isPresented: Binding(
                get: { pendingPositionDeletionID != nil },
                set: { if !$0 { pendingPositionDeletionID = nil } }
            ),
            actions: {
                Button(language.text("Cancel", "Avbryt"), role: .cancel) {
                    pendingPositionDeletionID = nil
                }
                Button(language.text("Delete", "Radera"), role: .destructive) {
                    if let id = pendingPositionDeletionID {
                        deletePosition(id: id)
                    }
                    pendingPositionDeletionID = nil
                }
            },
            message: {
                Text(language.text(
                    "No researcher uses this position. It is removed from the list.",
                    "Ingen forskare har den här befattningen. Den tas bort ur listan."
                ))
            }
        )
        .alert(
            language.text("Delete degree?", "Radera examen?"),
            isPresented: Binding(
                get: { pendingDegreeDeletionID != nil },
                set: { if !$0 { pendingDegreeDeletionID = nil } }
            ),
            actions: {
                Button(language.text("Cancel", "Avbryt"), role: .cancel) {
                    pendingDegreeDeletionID = nil
                }
                Button(language.text("Delete", "Radera"), role: .destructive) {
                    if let id = pendingDegreeDeletionID {
                        deleteDegree(id: id)
                    }
                    pendingDegreeDeletionID = nil
                }
            },
            message: {
                Text(language.text(
                    "No researcher uses this degree. It is removed from the list.",
                    "Ingen forskare har den här examen. Den tas bort ur listan."
                ))
            }
        )
    }

    // MARK: Befattningar

    private var positionsCard: some View {
        let usage = store.researcherPositionOptionUsageCounts()
        return AppSettingsCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("Positions", "Befattningar"))
                    .appTypography(.sectionTitle)
                SettingsEffectNote(language.text(
                    "Affects: the positions you can choose on a researcher's card, how they are written in lists and exports (Swedish or English name), the suggested career stage (A–D) and the title Professor. Renaming changes the text everywhere, since researchers store the choice, not the text. Hidden positions are not offered for new choices but stay on researchers who have them. A position can only be deleted when no researcher has it.",
                    "Påverkar: vilka befattningar du kan välja på ett forskarkort, hur de skrivs i listor och exporter (svenskt eller engelskt namn), föreslaget karriärsteg (A–D) och titeln Professor. Ett nytt namn ändrar texten överallt, eftersom forskarna sparar valet och inte texten. Dolda befattningar erbjuds inte för nya val men ligger kvar på forskare som har dem. En befattning kan bara raderas när ingen forskare har den."
                ))
                positionHeaderRow
                ForEach(Array(positions.enumerated()), id: \.element.id) { index, option in
                    positionRow(index: index, option: option, usageCount: usage[option.id] ?? 0)
                }
                Button {
                    positions.append(ResearcherPositionOption(group: .academic, sortOrder: positions.count))
                } label: {
                    Label(language.text("Add position", "Lägg till befattning"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var positionHeaderRow: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 44)
            columnHeader(language.text("Swedish", "Svenska"), width: 200)
            columnHeader(language.text("English", "Engelska"), width: 200)
            columnHeader(language.text("Group", "Grupp"), width: 130)
            columnHeader(language.text("Stage", "Steg"), width: 80)
            columnHeader(language.text("Title", "Titel"), width: 90)
            columnHeader(language.text("Hidden", "Dold"), width: 50)
            columnHeader(language.text("Used by", "Används av"), width: 80)
            Spacer(minLength: 0)
        }
    }

    private func positionRow(index: Int, option: ResearcherPositionOption, usageCount: Int) -> some View {
        HStack(spacing: 8) {
            moveButtons(
                canMoveUp: index > 0,
                canMoveDown: index < positions.count - 1,
                moveUp: { movePosition(from: index, by: -1) },
                moveDown: { movePosition(from: index, by: 1) }
            )
            TextField(language.text("Swedish name", "Svenskt namn"), text: positionTextBinding(index: index, keyPath: \.nameSv))
                .appTextInputChrome()
                .frame(width: 200)
            TextField(language.text("English name", "Engelskt namn"), text: positionTextBinding(index: index, keyPath: \.nameEn))
                .appTextInputChrome()
                .frame(width: 200)
            AppMenuSelectionField(
                selection: positionGroupBinding(index: index),
                options: ResearcherPositionGroup.allCases.map { ($0.displayName(language: language), $0) }
            )
            .frame(width: 130)
            AppMenuSelectionField(
                selection: positionStageBinding(index: index),
                options: stageOptions
            )
            .frame(width: 80)
            .help(language.text(
                "Career stage this position suggests (Universitetslektor with Docent becomes B)",
                "Karriärsteg som befattningen talar för (docent lyfter till minst B)"
            ))
            Toggle("Professor", isOn: positionFlagBinding(index: index, keyPath: \.givesProfessorTitle))
                .appCheckboxStyle()
                .frame(width: 90, alignment: .leading)
                .help(language.text("Gives the title Professor", "Ger titeln Professor"))
            Toggle("", isOn: positionFlagBinding(index: index, keyPath: \.isHidden))
                .appCheckboxStyle()
                .labelsHidden()
                .frame(width: 50, alignment: .leading)
                .help(language.text("Hide from new choices", "Dölj för nya val"))
            usageText(usageCount)
            deleteButton(usageCount: usageCount) {
                pendingPositionDeletionID = option.id
            }
            Spacer(minLength: 0)
        }
    }

    private var stageOptions: [(label: String, value: String)] {
        var result: [(label: String, value: String)] = [(label: language.text("None", "Inget"), value: "")]
        for stage in PublicationAuthorCareerStage.allCases {
            result.append((label: stage.rawValue, value: stage.rawValue))
        }
        return result
    }

    private func positionTextBinding(index: Int, keyPath: WritableKeyPath<ResearcherPositionOption, String>) -> Binding<String> {
        Binding(
            get: { positions.indices.contains(index) ? positions[index][keyPath: keyPath] : "" },
            set: { newValue in
                guard positions.indices.contains(index) else { return }
                positions[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func positionFlagBinding(index: Int, keyPath: WritableKeyPath<ResearcherPositionOption, Bool>) -> Binding<Bool> {
        Binding(
            get: { positions.indices.contains(index) ? positions[index][keyPath: keyPath] : false },
            set: { newValue in
                guard positions.indices.contains(index) else { return }
                positions[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func positionGroupBinding(index: Int) -> Binding<ResearcherPositionGroup> {
        Binding(
            get: { positions.indices.contains(index) ? positions[index].group : .other },
            set: { newValue in
                guard positions.indices.contains(index) else { return }
                positions[index].group = newValue
            }
        )
    }

    private func positionStageBinding(index: Int) -> Binding<String> {
        Binding(
            get: { positions.indices.contains(index) ? (positions[index].careerStageHint?.rawValue ?? "") : "" },
            set: { newValue in
                guard positions.indices.contains(index) else { return }
                positions[index].careerStageHint = PublicationAuthorCareerStage(rawValue: newValue)
            }
        )
    }

    private func movePosition(from index: Int, by offset: Int) {
        let target = index + offset
        guard positions.indices.contains(index), positions.indices.contains(target) else { return }
        positions.swapAt(index, target)
        for position in positions.indices {
            positions[position].sortOrder = position
        }
    }

    private func deletePosition(id: String) {
        // Only an option nobody uses can be deleted (checked again here).
        guard (store.researcherPositionOptionUsageCounts()[id] ?? 0) == 0 else { return }
        positions.removeAll { $0.id == id }
        for position in positions.indices {
            positions[position].sortOrder = position
        }
    }

    // MARK: Examina

    private var degreesCard: some View {
        let usage = store.researcherDegreeOptionUsageCounts()
        return AppSettingsCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("Degrees", "Examina"))
                    .appTypography(.sectionTitle)
                SettingsEffectNote(language.text(
                    "Affects: the degrees you can choose on a researcher's card and how they are written in lists and exports. The abbreviation is used when it is set (e.g. MD); a degree with a subject is written as e.g. MSc (Epidemiology). Renaming changes the text everywhere. A degree can only be deleted when no researcher has it.",
                    "Påverkar: vilka examina du kan välja på ett forskarkort och hur de skrivs i listor och exporter. Förkortningen används när den finns (t.ex. MD); en examen med ämne skrivs t.ex. MSc (Epidemiology). Ett nytt namn ändrar texten överallt. En examen kan bara raderas när ingen forskare har den."
                ))
                degreeHeaderRow
                ForEach(Array(degrees.enumerated()), id: \.element.id) { index, option in
                    degreeRow(index: index, option: option, usageCount: usage[option.id] ?? 0)
                }
                Button {
                    degrees.append(ResearcherDegreeOption(sortOrder: degrees.count))
                } label: {
                    Label(language.text("Add degree", "Lägg till examen"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var degreeHeaderRow: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 44)
            columnHeader(language.text("Swedish", "Svenska"), width: 220)
            columnHeader(language.text("English", "Engelska"), width: 220)
            columnHeader(language.text("Abbreviation", "Förkortning"), width: 110)
            columnHeader(language.text("Subject", "Ämne"), width: 60)
            columnHeader(language.text("Hidden", "Dold"), width: 50)
            columnHeader(language.text("Used by", "Används av"), width: 80)
            Spacer(minLength: 0)
        }
    }

    private func degreeRow(index: Int, option: ResearcherDegreeOption, usageCount: Int) -> some View {
        HStack(spacing: 8) {
            moveButtons(
                canMoveUp: index > 0,
                canMoveDown: index < degrees.count - 1,
                moveUp: { moveDegree(from: index, by: -1) },
                moveDown: { moveDegree(from: index, by: 1) }
            )
            TextField(language.text("Swedish name", "Svenskt namn"), text: degreeTextBinding(index: index, keyPath: \.nameSv))
                .appTextInputChrome()
                .frame(width: 220)
            TextField(language.text("English name", "Engelskt namn"), text: degreeTextBinding(index: index, keyPath: \.nameEn))
                .appTextInputChrome()
                .frame(width: 220)
            TextField(language.text("e.g. MD", "t.ex. MD"), text: degreeTextBinding(index: index, keyPath: \.abbreviation))
                .appTextInputChrome()
                .frame(width: 110)
            Toggle("", isOn: degreeFlagBinding(index: index, keyPath: \.takesSubject))
                .appCheckboxStyle()
                .labelsHidden()
                .frame(width: 60, alignment: .leading)
                .help(language.text("The degree has a subject, e.g. MSc (Epidemiology)", "Examen har ett ämne, t.ex. MSc (Epidemiology)"))
            Toggle("", isOn: degreeFlagBinding(index: index, keyPath: \.isHidden))
                .appCheckboxStyle()
                .labelsHidden()
                .frame(width: 50, alignment: .leading)
                .help(language.text("Hide from new choices", "Dölj för nya val"))
            usageText(usageCount)
            deleteButton(usageCount: usageCount) {
                pendingDegreeDeletionID = option.id
            }
            Spacer(minLength: 0)
        }
    }

    private func degreeTextBinding(index: Int, keyPath: WritableKeyPath<ResearcherDegreeOption, String>) -> Binding<String> {
        Binding(
            get: { degrees.indices.contains(index) ? degrees[index][keyPath: keyPath] : "" },
            set: { newValue in
                guard degrees.indices.contains(index) else { return }
                degrees[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func degreeFlagBinding(index: Int, keyPath: WritableKeyPath<ResearcherDegreeOption, Bool>) -> Binding<Bool> {
        Binding(
            get: { degrees.indices.contains(index) ? degrees[index][keyPath: keyPath] : false },
            set: { newValue in
                guard degrees.indices.contains(index) else { return }
                degrees[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func moveDegree(from index: Int, by offset: Int) {
        let target = index + offset
        guard degrees.indices.contains(index), degrees.indices.contains(target) else { return }
        degrees.swapAt(index, target)
        for position in degrees.indices {
            degrees[position].sortOrder = position
        }
    }

    private func deleteDegree(id: String) {
        guard (store.researcherDegreeOptionUsageCounts()[id] ?? 0) == 0 else { return }
        degrees.removeAll { $0.id == id }
        for position in degrees.indices {
            degrees[position].sortOrder = position
        }
    }

    // MARK: Läkarspecialiteter

    private var specialtiesSection: some View {
        specialtiesCard
            .alert(
                language.text("Delete specialty?", "Radera specialiteten?"),
                isPresented: specialtyDeletionAlertBinding,
                actions: {
                    Button(language.text("Cancel", "Avbryt"), role: .cancel) {
                        pendingSpecialtyDeletionID = nil
                    }
                    Button(language.text("Delete", "Radera"), role: .destructive) {
                        if let id = pendingSpecialtyDeletionID {
                            deleteSpecialty(id: id)
                        }
                        pendingSpecialtyDeletionID = nil
                    }
                },
                message: {
                    Text(language.text(
                        "No researcher uses this specialty. It is removed from the list.",
                        "Ingen forskare har den här specialiteten. Den tas bort ur listan."
                    ))
                }
            )
    }

    private var specialtyDeletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingSpecialtyDeletionID != nil },
            set: { if !$0 { pendingSpecialtyDeletionID = nil } }
        )
    }

    private var specialtiesCard: some View {
        let usage: [String: Int] = store.researcherSpecialtyOptionUsageCounts()
        return AppSettingsCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("Physician specialties", "Läkarspecialiteter"))
                    .appTypography(.sectionTitle)
                SettingsEffectNote(language.text(
                    "Affects: the specialty you can choose for the positions Resident Physician, Specialist Physician and Senior Consultant, and how the position is written in lists and exports (e.g. Specialist Physician, General Practice). Renaming changes the text everywhere. Hidden specialties are not offered for new choices but stay on researchers who have them. A specialty can only be deleted when no researcher has it.",
                    "Påverkar: vilken specialitet du kan välja för befattningarna ST-läkare, Specialistläkare och Överläkare, och hur befattningen skrivs i listor och exporter (t.ex. Specialistläkare i allmänmedicin). Ett nytt namn ändrar texten överallt. Dolda specialiteter erbjuds inte för nya val men ligger kvar på forskare som har dem. En specialitet kan bara raderas när ingen forskare har den."
                ))
                specialtyHeaderRow
                ForEach(Array(specialties.enumerated()), id: \.element.id) { index, option in
                    specialtyRow(index: index, option: option, usageCount: usage[option.id] ?? 0)
                }
                Button {
                    specialties.append(ResearcherSpecialtyOption(sortOrder: specialties.count))
                } label: {
                    Label(language.text("Add specialty", "Lägg till specialitet"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var specialtyHeaderRow: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 44)
            columnHeader(language.text("Swedish", "Svenska"), width: 260)
            columnHeader(language.text("English", "Engelska"), width: 260)
            columnHeader(language.text("Hidden", "Dold"), width: 50)
            columnHeader(language.text("Used by", "Används av"), width: 80)
            Spacer(minLength: 0)
        }
    }

    private func specialtyRow(index: Int, option: ResearcherSpecialtyOption, usageCount: Int) -> some View {
        HStack(spacing: 8) {
            moveButtons(
                canMoveUp: index > 0,
                canMoveDown: index < specialties.count - 1,
                moveUp: { moveSpecialty(from: index, by: -1) },
                moveDown: { moveSpecialty(from: index, by: 1) }
            )
            TextField(language.text("Swedish name", "Svenskt namn"), text: specialtyTextBinding(index: index, keyPath: \.nameSv))
                .appTextInputChrome()
                .frame(width: 260)
            TextField(language.text("English name", "Engelskt namn"), text: specialtyTextBinding(index: index, keyPath: \.nameEn))
                .appTextInputChrome()
                .frame(width: 260)
            Toggle("", isOn: specialtyHiddenBinding(index: index))
                .appCheckboxStyle()
                .labelsHidden()
                .frame(width: 50, alignment: .leading)
                .help(language.text("Hide from new choices", "Dölj för nya val"))
            usageText(usageCount)
            deleteButton(usageCount: usageCount) {
                pendingSpecialtyDeletionID = option.id
            }
            Spacer(minLength: 0)
        }
    }

    private func specialtyTextBinding(index: Int, keyPath: WritableKeyPath<ResearcherSpecialtyOption, String>) -> Binding<String> {
        Binding(
            get: { specialties.indices.contains(index) ? specialties[index][keyPath: keyPath] : "" },
            set: { newValue in
                guard specialties.indices.contains(index) else { return }
                specialties[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func specialtyHiddenBinding(index: Int) -> Binding<Bool> {
        Binding(
            get: { specialties.indices.contains(index) ? specialties[index].isHidden : false },
            set: { newValue in
                guard specialties.indices.contains(index) else { return }
                specialties[index].isHidden = newValue
            }
        )
    }

    private func moveSpecialty(from index: Int, by offset: Int) {
        let target = index + offset
        guard specialties.indices.contains(index), specialties.indices.contains(target) else { return }
        specialties.swapAt(index, target)
        for position in specialties.indices {
            specialties[position].sortOrder = position
        }
    }

    private func deleteSpecialty(id: String) {
        guard (store.researcherSpecialtyOptionUsageCounts()[id] ?? 0) == 0 else { return }
        specialties.removeAll { $0.id == id }
        for position in specialties.indices {
            specialties[position].sortOrder = position
        }
    }

    // MARK: Delade delar

    private func columnHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .appTypography(.tableHeader)
            .frame(width: width, alignment: .leading)
    }

    private func moveButtons(
        canMoveUp: Bool,
        canMoveDown: Bool,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Button(action: moveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)
            .help(language.text("Move up", "Flytta upp"))
            Button(action: moveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)
            .help(language.text("Move down", "Flytta ned"))
        }
        .frame(width: 44)
    }

    private func usageText(_ count: Int) -> some View {
        Text(language.text("\(count) researchers", "\(count) forskare"))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
            .frame(width: 80, alignment: .leading)
    }

    private func deleteButton(usageCount: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .disabled(usageCount > 0)
        .help(usageCount > 0
            ? language.text("Used by researchers; hide it instead", "Används av forskare; dölj den i stället")
            : language.text("Delete (asks first)", "Radera (frågar först)"))
    }

    // MARK: Spara

    private func load() {
        positions = store.researcherPositionOptions
        degrees = store.researcherDegreeOptions
        specialties = store.researcherSpecialtyOptions
        hasLoaded = true
    }

    private func scheduleSave() {
        guard hasLoaded else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        store.autosaveResearcherPositionOptions(positions)
        store.autosaveResearcherDegreeOptions(degrees)
        store.autosaveResearcherSpecialtyOptions(specialties)
    }
}
