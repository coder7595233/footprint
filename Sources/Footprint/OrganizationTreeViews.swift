import AppKit
import SwiftUI

// F21: the screens for the organization tree.
//  - OrganizationPublicationAddressFields: the organization's English
//    address name and address order (organization page, general fields).
//  - OrganizationUnitsSection: the "Enheter" section on the organization page.
//  - OrganizationUnitPickerMenu: "Enhet: …" on researcher rows.
//  - ResearcherPublicationAddressPanel: "Publikationsadress" on the researcher page.

private let organizationUnitIndentWidth: CGFloat = 24

/// Leading spaces for a unit in a drop-down menu, one step per level.
private func organizationUnitMenuIndent(_ depth: Int) -> String {
    String(repeating: "\u{2003}", count: max(depth, 0))
}

// MARK: - Organization page: publication address settings

struct OrganizationPublicationAddressFields: View {
    @ObservedObject var store: GrantDataStore
    let organizationID: String
    let language: AppLanguage

    var body: some View {
        let organization = store.organization(id: organizationID)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                AppFieldLabelText(
                    text: language.text("English name in publication address", "Engelskt namn i publikationsadress"),
                    help: language.text(
                        "Leave empty to use the English name.",
                        "Lämna tomt för att använda det engelska namnet."
                    )
                )
                CommitFormattingTextField(
                    placeholder: organization?.nameEn.nonEmpty ?? language.text("Same as the English name", "Samma som det engelska namnet"),
                    text: addressNameBinding,
                    formatter: { $0 },
                    updatesContinuously: false
                )
                .appTextInputChrome()
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: 360, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                AppFieldLabelText(
                    text: language.text("Order in publication address", "Ordning i publikationsadress"),
                    help: language.text(
                        "Address lines are written in this order, for example the university 1 and the region 2. Organizations without an order come last.",
                        "Adressraderna skrivs i den här ordningen, till exempel universitetet 1 och regionen 2. Organisationer utan ordning kommer sist."
                    )
                )
                AppMenuSelectionField(
                    selection: addressOrderBinding,
                    options: addressOrderOptions
                )
            }
            .frame(width: 220, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    private var addressOrderOptions: [(label: String, value: Int?)] {
        [
            (label: language.text("None", "Ingen"), value: nil),
            (label: "1", value: 1),
            (label: "2", value: 2),
            (label: "3", value: 3),
        ]
    }

    private var addressNameBinding: Binding<String> {
        Binding(
            get: { store.organization(id: organizationID)?.addressNameEn ?? "" },
            set: { newValue in
                guard let organization = store.organization(id: organizationID) else { return }
                store.updateOrganizationAddressSettings(
                    organizationID: organizationID,
                    addressNameEn: newValue,
                    addressOrder: organization.addressOrder
                )
            }
        )
    }

    private var addressOrderBinding: Binding<Int?> {
        Binding(
            get: { store.organization(id: organizationID)?.addressOrder },
            set: { newValue in
                guard let organization = store.organization(id: organizationID) else { return }
                store.updateOrganizationAddressSettings(
                    organizationID: organizationID,
                    addressNameEn: organization.addressNameEn,
                    addressOrder: newValue
                )
            }
        )
    }
}

// MARK: - Organization page: units

struct OrganizationUnitsSection: View {
    @ObservedObject var store: GrantDataStore
    let organizationID: String
    let language: AppLanguage
    @State private var isExpanded: Bool
    @State private var pendingRemovalUnitID: String?
    /// The unit shown in the editor on the right.
    @State private var selectedUnitID: String?
    /// Units whose sub-units are shown in the list; all are closed at first.
    @State private var expandedUnitIDs: Set<String> = []
    @State private var searchText = ""

    private static let treeRowHeight: CGFloat = 24
    private static let treeMaxHeight: CGFloat = 520

    init(store: GrantDataStore, organizationID: String, language: AppLanguage) {
        self.store = store
        self.organizationID = organizationID
        self.language = language
        _isExpanded = State(initialValue: !(store.organization(id: organizationID)?.units.isEmpty ?? true))
    }

    private var pendingRemovalUnit: OrganizationUnit? {
        store.organization(id: organizationID)?.unit(withID: pendingRemovalUnitID)
    }

    private var removalDialogIsPresented: Binding<Bool> {
        Binding(
            get: { pendingRemovalUnitID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRemovalUnitID = nil
                }
            }
        )
    }

    var body: some View {
        let organization = store.organization(id: organizationID)
        let unitCount = organization?.units.count ?? 0
        VStack(alignment: .leading, spacing: 10) {
            CollapsibleSectionHeader(
                title: unitCount == 0
                    ? language.text("Units", "Enheter")
                    : language.text("Units (\(unitCount))", "Enheter (\(unitCount))"),
                isExpanded: $isExpanded
            )
            if isExpanded, let organization {
                expandedContent(organization: organization)
            }
        }
        .confirmationDialog(
            language.text("Remove the unit?", "Ta bort enheten?"),
            isPresented: removalDialogIsPresented,
            titleVisibility: .visible,
            presenting: pendingRemovalUnit
        ) { unit in
            removalButtons(for: unit)
        } message: { unit in
            Text(removalMessage(for: unit))
        }
        .onChange(of: organizationID) { _, newOrganizationID in
            selectedUnitID = nil
            expandedUnitIDs = []
            searchText = ""
            pendingRemovalUnitID = nil
            isExpanded = !(store.organization(id: newOrganizationID)?.units.isEmpty ?? true)
        }
        .onChange(of: searchText) { _, newSearchText in
            openUnitsAboveMatches(for: newSearchText)
        }
    }

    // MARK: Layout

    @ViewBuilder
    private func expandedContent(organization: OrganizationRecord) -> some View {
        let usageCounts = store.organizationUnitUsageCounts(organizationID: organization.id)
        VStack(alignment: .leading, spacing: 10) {
            Text(language.text(
                "Faculties, departments, centres, clinics and divisions in any number of levels. Choose a unit in the list to see and change it on the right. The researchers' affiliations, employments and education can point to a unit.",
                "Fakulteter, institutioner, centrum, kliniker och avdelningar i hur många nivåer som helst. Välj en enhet i listan för att se och ändra den till höger. Forskarnas affilieringar, anställningar och utbildningar kan peka på en enhet."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            toolbar(organization: organization)

            if organization.units.isEmpty {
                Text(language.text("No units yet.", "Inga enheter ännu."))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    treeList(organization: organization, usageCounts: usageCounts)
                        .frame(minWidth: 280, idealWidth: 380, maxWidth: 460, alignment: .topLeading)
                    editorPane(organization: organization, usageCounts: usageCounts)
                        .frame(minWidth: 320, maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private func toolbar(organization: OrganizationRecord) -> some View {
        HStack(spacing: 10) {
            TextField(language.text("Search unit", "Sök enhet"), text: $searchText)
                .appTextInputChrome()
                .frame(width: 240)
                .help(language.text(
                    "Shows the units whose name contains the text, with the units above them.",
                    "Visar enheterna vars namn innehåller texten, med enheterna ovanför."
                ))
            if !searchText.isEmpty {
                Button(language.text("Clear", "Rensa")) {
                    searchText = ""
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
            }
            Spacer(minLength: 0)
            Button(language.text("Add unit", "Lägg till enhet")) {
                addUnit(organizationID: organization.id, parentUnitID: nil)
            }
            .appAddButtonStyle()
        }
    }

    // MARK: Tree list (left)

    private func treeList(organization: OrganizationRecord, usageCounts: [String: Int]) -> some View {
        let rows = organization.visibleUnitTreeRows(expandedUnitIDs: expandedUnitIDs, searchText: searchText)
        let parentIDs = organization.unitIDsWithChildren()
        let contentHeight = CGFloat(max(rows.count, 1)) * Self.treeRowHeight + 8
        let listHeight = min(Self.treeMaxHeight, contentHeight)
        return ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    Text(language.text("No unit matches the search.", "Ingen enhet matchar sökningen."))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                        .frame(height: Self.treeRowHeight)
                        .padding(.leading, 8)
                }
                ForEach(rows) { row in
                    treeRow(
                        row,
                        hasChildren: parentIDs.contains(row.unit.id),
                        usageCount: usageCounts[row.unit.id] ?? 0
                    )
                }
            }
            .padding(4)
        }
        .frame(height: listHeight)
        .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
    }

    private func treeRow(_ row: OrganizationUnitTreeRow, hasChildren: Bool, usageCount: Int) -> some View {
        let unitID = row.unit.id
        let isSelected = unitID == selectedUnitID
        let isOpen = expandedUnitIDs.contains(unitID)
        return HStack(spacing: 4) {
            disclosureButton(unitID: unitID, hasChildren: hasChildren, isOpen: isOpen)
            Text(treeTitle(for: row.unit))
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(AppPalette.appText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if usageCount > 0 {
                Text("\(usageCount)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help(usageText(usageCount))
            }
        }
        .padding(.leading, 4 + CGFloat(row.depth) * 16)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.treeRowHeight)
        .background(AppListRowBackground(isSelected: isSelected, cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedUnitID = unitID
        }
        .help(treeTitle(for: row.unit))
    }

    @ViewBuilder
    private func disclosureButton(unitID: String, hasChildren: Bool, isOpen: Bool) -> some View {
        if hasChildren {
            Button {
                if isOpen {
                    expandedUnitIDs.remove(unitID)
                } else {
                    expandedUnitIDs.insert(unitID)
                }
            } label: {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen
                ? language.text("Hide the units below", "Dölj underenheterna")
                : language.text("Show the units below", "Visa underenheterna"))
        } else {
            Color.clear
                .frame(width: 16, height: 16)
        }
    }

    private func treeTitle(for unit: OrganizationUnit) -> String {
        let name = unit.displayName(language: language).nonEmpty ?? language.text("(no name)", "(utan namn)")
        return unit.isTemplate ? name + language.text(" (template)", " (mall)") : name
    }

    private func usageText(_ count: Int) -> String {
        language.text(
            count == 1 ? "Used by 1 researcher row" : "Used by \(count) researcher rows",
            count == 1 ? "Används av 1 rad hos forskarna" : "Används av \(count) rader hos forskarna"
        )
    }

    // MARK: Editor (right)

    @ViewBuilder
    private func editorPane(organization: OrganizationRecord, usageCounts: [String: Int]) -> some View {
        if let unit = organization.unit(withID: selectedUnitID) {
            VStack(alignment: .leading, spacing: 12) {
                OrganizationUnitEditorPane(
                    store: store,
                    organization: organization,
                    unit: unit,
                    hasChildren: organization.unitIDsWithChildren().contains(unit.id),
                    usageCount: usageCounts[unit.id] ?? 0,
                    language: language,
                    addChild: { addUnit(organizationID: organization.id, parentUnitID: unit.id) },
                    requestRemoval: { pendingRemovalUnitID = unit.id }
                )
                .id(unit.id)
                if (usageCounts[unit.id] ?? 0) > 0 {
                    OrganizationUnitResearcherList(
                        researchers: store.organizationUnitResearchers(organizationID: organization.id, unitID: unit.id),
                        language: language,
                        openResearcher: { store.openRoute(for: $0) }
                    )
                }
            }
        } else {
            Text(language.text(
                "Choose a unit in the list to see and change it here.",
                "Välj en enhet i listan för att se och ändra den här."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppPalette.subtleBorder, lineWidth: 1)
            )
        }
    }

    // MARK: Actions

    private func addUnit(organizationID: String, parentUnitID: String?) {
        guard let newUnitID = store.addOrganizationUnit(organizationID: organizationID, parentUnitID: parentUnitID) else {
            return
        }
        if let parentUnitID, let organization = store.organization(id: organizationID) {
            for unit in organization.unitPath(to: parentUnitID) {
                expandedUnitIDs.insert(unit.id)
            }
        }
        searchText = ""
        selectedUnitID = newUnitID
    }

    /// While searching, the units above the matches are opened so the
    /// matches can be seen (they stay open when the search is cleared).
    private func openUnitsAboveMatches(for text: String) {
        guard let organization = store.organization(id: organizationID) else { return }
        let matches = organization.unitIDsMatching(searchText: text)
        guard !matches.isEmpty else { return }
        expandedUnitIDs.formUnion(organization.ancestorUnitIDs(of: matches))
    }

    // MARK: Removing

    private func subunitCount(of unit: OrganizationUnit) -> Int {
        store.organization(id: organizationID)?.descendantUnitIDs(of: unit.id).count ?? 0
    }

    @ViewBuilder
    private func removalButtons(for unit: OrganizationUnit) -> some View {
        if subunitCount(of: unit) > 0 {
            Button(language.text("Remove with sub-units", "Ta bort med underenheter"), role: .destructive) {
                remove(unit, keepsChildren: false)
            }
            Button(language.text(
                "Remove only this one, move the sub-units up one level",
                "Ta bort bara den här, flytta underenheterna upp en nivå"
            )) {
                remove(unit, keepsChildren: true)
            }
        } else {
            Button(language.text("Remove", "Ta bort"), role: .destructive) {
                remove(unit, keepsChildren: true)
            }
        }
        Button(language.text("Cancel", "Avbryt"), role: .cancel) {
            pendingRemovalUnitID = nil
        }
    }

    private func remove(_ unit: OrganizationUnit, keepsChildren: Bool) {
        store.removeOrganizationUnit(organizationID: organizationID, unitID: unit.id, keepsChildren: keepsChildren)
        pendingRemovalUnitID = nil
        if let currentSelection = selectedUnitID,
           store.organization(id: organizationID)?.unit(withID: currentSelection) == nil {
            selectedUnitID = store.organization(id: organizationID)?.unit(withID: unit.parentUnitID)?.id
        }
    }

    private func removalMessage(for unit: OrganizationUnit) -> String {
        let name = unit.displayName(language: language)
        let counts = store.organizationUnitUsageCounts(organizationID: organizationID)
        let subunitIDs = store.organization(id: organizationID)?.descendantUnitIDs(of: unit.id) ?? Set<String>()
        let ownRows = counts[unit.id] ?? 0
        let subunitRows = subunitIDs.reduce(0) { total, subunitID in total + (counts[subunitID] ?? 0) }
        var parts: [String] = []

        if subunitIDs.isEmpty {
            parts.append(language.text(
                "“\(name)” is removed from the organization.",
                "”\(name)” tas bort från organisationen."
            ))
        } else {
            let count = subunitIDs.count
            parts.append(language.text(
                count == 1 ? "“\(name)” has 1 sub-unit." : "“\(name)” has \(count) sub-units.",
                count == 1 ? "”\(name)” har 1 underenhet." : "”\(name)” har \(count) underenheter."
            ))
        }

        if ownRows + subunitRows == 0 {
            parts.append(language.text(
                subunitIDs.isEmpty ? "No researcher row uses it." : "No researcher row uses it or its sub-units.",
                subunitIDs.isEmpty ? "Ingen rad hos forskarna använder den." : "Ingen rad hos forskarna använder den eller underenheterna."
            ))
        } else if subunitIDs.isEmpty {
            parts.append(language.text(
                ownRows == 1 ? "1 researcher row uses it." : "\(ownRows) researcher rows use it.",
                ownRows == 1 ? "1 rad hos forskarna använder den." : "\(ownRows) rader hos forskarna använder den."
            ))
            parts.append(language.text(
                "Those rows keep the organization but lose the unit.",
                "Raderna behåller organisationen men förlorar enheten."
            ))
        } else {
            parts.append(language.text(
                "Researcher rows that use it: \(ownRows); that use its sub-units: \(subunitRows).",
                "Rader hos forskarna som använder den: \(ownRows); som använder underenheterna: \(subunitRows)."
            ))
            parts.append(language.text(
                "Rows that point to a removed unit keep the organization but lose the unit. If the sub-units are moved up, their rows keep their unit.",
                "Rader som pekar på en enhet som tas bort behåller organisationen men förlorar enheten. Flyttas underenheterna upp behåller deras rader sin enhet."
            ))
        }
        parts.append(language.text("You can undo this.", "Det går att ångra."))
        return parts.joined(separator: " ")
    }
}

/// The researchers whose rows point to the chosen unit, shown under the
/// unit editor. Clicking a name opens the researcher.
private struct OrganizationUnitResearcherList: View {
    let researchers: [OrganizationUnitResearcher]
    let language: AppLanguage
    let openResearcher: (PublicationAuthor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.text("Researchers at the unit", "Forskare vid enheten"))
                .appTypography(.fieldLabel)
                .foregroundStyle(AppPalette.appText)
            ForEach(researchers) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button(entry.author.displayName) {
                        openResearcher(entry.author)
                    }
                    .buttonStyle(.link)
                    .help(language.text("Open the researcher", "Öppna forskaren"))
                    Text(entry.rowKinds.map { $0.title(language: language) }.joined(separator: ", "))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
    }
}

/// F21: the editor to the right of the unit list: names, city, the address
/// settings, the address line the unit gives, how many researcher rows use
/// it, and the actions (add a sub-unit, move, remove).
private struct OrganizationUnitEditorPane: View {
    let store: GrantDataStore
    let organization: OrganizationRecord
    let unit: OrganizationUnit
    let hasChildren: Bool
    let usageCount: Int
    let language: AppLanguage
    let addChild: () -> Void
    let requestRemoval: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            nameFields
            addressToggles
            addressPreview
            usageLine
            Divider()
            actions
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(unit.displayName(language: language).nonEmpty ?? language.text("(no name)", "(utan namn)"))
                .appTypography(.panelTitle)
                .fixedSize(horizontal: false, vertical: true)
            if unit.parentUnitID != nil {
                Text(organization.displayName(for: language) + " / " + organization.unitPathText(to: unit.id, language: language))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if unit.isTemplate {
                Text(language.text(
                    "Template: a pattern, not a real unit. It is not offered on researcher rows.",
                    "Mall: ett mönster, inte en riktig enhet. Den erbjuds inte på forskarnas rader."
                ))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var nameFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledField(
                label: language.text("Swedish name", "Svenskt namn"),
                help: nil,
                text: unitTextBinding(\.nameSv)
            )
            labeledField(
                label: language.text("English name", "Engelskt namn"),
                help: language.text(
                    "Also used in the publication address.",
                    "Används också i publikationsadressen."
                ),
                text: englishNameBinding
            )
            labeledField(
                label: language.text("City", "Ort"),
                help: language.text(
                    "Leave empty to use the city of the unit above or of the organization.",
                    "Lämna tomt för att använda orten för enheten ovanför eller för organisationen."
                ),
                text: unitTextBinding(\.city),
                fieldMaxWidth: 240
            )
        }
    }

    /// Label to the left of the field, so the editor takes less height.
    private func labeledField(
        label: String,
        help: String?,
        text: Binding<String>,
        fieldMaxWidth: CGFloat = .infinity
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            AppFieldLabelText(text: label, help: help)
                .frame(width: 110, alignment: .leading)
            CommitFormattingTextField(
                placeholder: label,
                text: text,
                formatter: { $0 },
                updatesContinuously: false
            )
            .appTextInputChrome()
            .frame(maxWidth: fieldMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addressToggles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                language.text("Included in the publication address", "Med i publikationsadressen"),
                isOn: unitBoolBinding(\.inAddress)
            )
            .appCheckboxStyle()
            .fixedSize()
            .help(language.text(
                "Faculties and centres are usually not written in an address.",
                "Fakulteter och centrum skrivs oftast inte i en adress."
            ))
            if hasChildren {
                Toggle(
                    language.text("Units below are not included in the address", "Avdelningar under ingår inte i adressen"),
                    isOn: childrenNotInAddressBinding
                )
                .appCheckboxStyle()
                .fixedSize()
                .help(language.text(
                    "A researcher at a unit below is written with this unit in the address (for example the divisions of a department).",
                    "En forskare vid en enhet under skrivs med den här enheten i adressen (till exempel avdelningarna vid en institution)."
                ))
            }
            Toggle(
                language.text("Written instead of the organization in the address", "Skrivs i stället för organisationen i adressen"),
                isOn: unitBoolBinding(\.standsInForOrganizationInAddress)
            )
            .appCheckboxStyle()
            .fixedSize()
            .help(language.text(
                "For example a university hospital that is written instead of the region: the hospital's name and not the region's name.",
                "Till exempel ett universitetssjukhus som skrivs i stället för regionen: sjukhusets namn och inte regionens namn."
            ))
        }
    }

    private var addressPreview: some View {
        let line = organization.publicationAddressLine(unit: storedUnit() ?? unit)
        return VStack(alignment: .leading, spacing: 4) {
            Text(language.text("The address becomes:", "Så blir adressen:"))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line.nonEmpty ?? language.text("(empty)", "(tomt)"))
                    .appTypography(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(language.text("Copy", "Kopiera")) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(line, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(line.nonEmpty == nil)
                .help(language.text("Copy the address line", "Kopiera adressraden"))
            }
        }
    }

    private var usageLine: some View {
        Text(usageDescription)
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
    }

    private var usageDescription: String {
        if usageCount == 0 {
            return language.text("No researcher row uses this unit", "Ingen rad hos forskarna använder enheten")
        }
        return language.text(
            usageCount == 1 ? "Used by 1 researcher row" : "Used by \(usageCount) researcher rows",
            usageCount == 1 ? "Används av 1 rad hos forskarna" : "Används av \(usageCount) rader hos forskarna"
        )
    }

    private var actions: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(language.text("Add sub-unit", "Lägg till underenhet")) {
                addChild()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            moveMenu
            Spacer(minLength: 8)
            Button(language.text("Remove the unit", "Ta bort enheten")) {
                requestRemoval()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppPalette.actionDelete)
            .help(language.text(
                "Asks first. You can undo the removal.",
                "Frågar först. Det går att ångra borttagningen."
            ))
        }
    }

    private var moveMenu: some View {
        Menu(language.text("Move to…", "Flytta till…")) {
            Button(language.text("Directly under the organization", "Direkt under organisationen")) {
                store.moveOrganizationUnit(organizationID: organization.id, unitID: unit.id, toParentUnitID: nil)
            }
            .disabled(unit.parentUnitID == nil)
            let targets = organization.moveTargets(forUnit: unit.id)
            if !targets.isEmpty {
                Divider()
            }
            ForEach(targets) { target in
                Button(organizationUnitMenuIndent(target.depth) + target.unit.displayName(language: language)) {
                    store.moveOrganizationUnit(organizationID: organization.id, unitID: unit.id, toParentUnitID: target.unit.id)
                }
                .disabled(target.unit.id == unit.parentUnitID)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.system(size: 12, weight: .semibold))
        .help(language.text(
            "Move the unit (with the units below it) to another place in the tree.",
            "Flytta enheten (med underenheterna) till en annan plats i trädet."
        ))
    }

    // MARK: Saving

    /// The latest stored unit (the value passed in may be one render old).
    private func storedUnit() -> OrganizationUnit? {
        store.organization(id: organization.id)?.unit(withID: unit.id)
    }

    private func save(_ change: (inout OrganizationUnit) -> Void) {
        guard var updated = storedUnit() else { return }
        let before = updated
        change(&updated)
        guard updated != before else { return }
        store.updateOrganizationUnit(organizationID: organization.id, unit: updated)
    }

    private func unitTextBinding(_ keyPath: WritableKeyPath<OrganizationUnit, String>) -> Binding<String> {
        Binding(
            get: { storedUnit()?[keyPath: keyPath] ?? unit[keyPath: keyPath] },
            set: { newValue in
                save { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    /// One English name: shows the address name when there is one, and
    /// saves the text as both the English name and the address name.
    private var englishNameBinding: Binding<String> {
        Binding(
            get: { (storedUnit() ?? unit).editableEnglishName },
            set: { newValue in
                save { $0.setEditableEnglishName(newValue) }
            }
        )
    }

    private func unitBoolBinding(_ keyPath: WritableKeyPath<OrganizationUnit, Bool>) -> Binding<Bool> {
        Binding(
            get: { storedUnit()?[keyPath: keyPath] ?? unit[keyPath: keyPath] },
            set: { newValue in
                save { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var childrenNotInAddressBinding: Binding<Bool> {
        Binding(
            get: { !(storedUnit()?.childrenInAddress ?? unit.childrenInAddress) },
            set: { newValue in
                save { $0.childrenInAddress = !newValue }
            }
        )
    }
}

/// The earlier editor that showed every unit as a full-width card with all
/// fields (abbreviation and validity dates included). Not shown since the
/// two-column layout (F21); kept, not deleted.
private struct OrganizationUnitRowEditor: View {
    let store: GrantDataStore
    let organization: OrganizationRecord
    let row: OrganizationUnitTreeRow
    let usageCount: Int
    let language: AppLanguage
    let requestRemoval: () -> Void

    private var unit: OrganizationUnit { row.unit }

    private var hasChildren: Bool {
        !organization.childUnits(of: unit.id).isEmpty
    }

    private var dateState: AppFieldVisualState {
        unit.hasValidDateRange
            ? .normal
            : .invalid(language.text("The unit ends before it starts", "Enheten slutar innan den börjar"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                unitTextField(language.text("Swedish name", "Svenskt namn"), \.nameSv, width: 250)
                unitTextField(language.text("English name", "Engelskt namn"), \.nameEn, width: 250)
                unitTextField(language.text("Abbreviation", "Förkortning"), \.abbreviation, width: 90)
                if unit.isTemplate {
                    Text(language.text("Template", "Mall"))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                        .help(language.text(
                            "A pattern, not a real unit. It is not offered on researcher rows.",
                            "Ett mönster, inte en riktig enhet. Den erbjuds inte på forskarnas rader."
                        ))
                }
                Spacer(minLength: 0)
                actionsMenu
            }
            HStack(alignment: .center, spacing: 8) {
                unitTextField(language.text("English name in address", "Engelskt namn i adress"), \.addressNameEn, width: 250)
                unitTextField(language.text("City", "Ort"), \.city, width: 120)
                Text(language.text("Valid", "Gäller"))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                AppDateField(
                    placeholder: language.text("From", "Från"),
                    text: unitTextBinding(\.validFrom),
                    width: 110,
                    language: language,
                    state: dateState
                )
                AppDateField(
                    placeholder: language.text("To", "Till"),
                    text: unitTextBinding(\.validTo),
                    width: 110,
                    language: language,
                    state: dateState
                )
                if !unit.hasValidDateRange {
                    Text(language.text("Ends before it starts", "Slutar innan den börjar"))
                        .appTypography(.secondary)
                        .foregroundStyle(AppPalette.chartRed)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .center, spacing: 14) {
                Toggle(
                    language.text("Included in publication address", "Ingår i publikationsadress"),
                    isOn: unitBoolBinding(\.inAddress)
                )
                .appCheckboxStyle()
                .fixedSize()
                .help(language.text(
                    "Faculties and centres are usually not written in an address.",
                    "Fakulteter och centrum skrivs oftast inte i en adress."
                ))
                if hasChildren || !unit.childrenInAddress {
                    Toggle(
                        language.text("Units below are not included in the address", "Avdelningar under ingår inte i adressen"),
                        isOn: childrenNotInAddressBinding
                    )
                    .appCheckboxStyle()
                    .fixedSize()
                    .help(language.text(
                        "A researcher at a unit below is written with this unit in the address (for example the divisions of a department).",
                        "En forskare vid en enhet under skrivs med den här enheten i adressen (till exempel avdelningarna vid en institution)."
                    ))
                }
                if usageCount > 0 {
                    Text(language.text(
                        usageCount == 1 ? "Used by 1 researcher row" : "Used by \(usageCount) researcher rows",
                        usageCount == 1 ? "Används av 1 rad hos forskarna" : "Används av \(usageCount) rader hos forskarna"
                    ))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 10 + CGFloat(row.depth) * organizationUnitIndentWidth)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .leading) {
            if row.depth > 0 {
                Rectangle()
                    .fill(AppPalette.subtleBorder)
                    .frame(width: 2)
                    .padding(.leading, CGFloat(row.depth) * organizationUnitIndentWidth - 6)
                    .padding(.vertical, 6)
            }
        }
    }

    private var actionsMenu: some View {
        Menu(language.text("Choose…", "Välj…")) {
            Button(language.text("Add unit below", "Lägg till underenhet")) {
                store.addOrganizationUnit(organizationID: organization.id, parentUnitID: unit.id)
            }
            Menu(language.text("Move to…", "Flytta till…")) {
                Button(language.text("Directly under the organization", "Direkt under organisationen")) {
                    store.moveOrganizationUnit(organizationID: organization.id, unitID: unit.id, toParentUnitID: nil)
                }
                .disabled(unit.parentUnitID == nil)
                let targets = organization.moveTargets(forUnit: unit.id)
                if !targets.isEmpty {
                    Divider()
                }
                ForEach(targets) { target in
                    Button(organizationUnitMenuIndent(target.depth) + target.unit.displayName(language: language)) {
                        store.moveOrganizationUnit(organizationID: organization.id, unitID: unit.id, toParentUnitID: target.unit.id)
                    }
                    .disabled(target.unit.id == unit.parentUnitID)
                }
            }
            Divider()
            if usageCount > 0 {
                Button(language.text(
                    usageCount == 1
                        ? "Cannot be removed: 1 researcher row uses this unit"
                        : "Cannot be removed: \(usageCount) researcher rows use this unit",
                    usageCount == 1
                        ? "Kan inte tas bort: 1 rad hos forskarna använder enheten"
                        : "Kan inte tas bort: \(usageCount) rader hos forskarna använder enheten"
                )) {}
                .disabled(true)
            } else if hasChildren {
                Button(language.text(
                    "Cannot be removed: move or remove the units below first",
                    "Kan inte tas bort: flytta eller ta bort underenheterna först"
                )) {}
                .disabled(true)
            } else {
                Button(language.text("Remove…", "Ta bort…"), role: .destructive) {
                    requestRemoval()
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.system(size: 12, weight: .semibold))
        .help(language.text(
            "Choices for this unit: add a unit below it, move it, or remove it (only when no researcher row uses it).",
            "Val för enheten: lägg till en underenhet, flytta den eller ta bort den (bara när ingen rad hos forskarna använder den)."
        ))
    }

    private func unitTextField(
        _ placeholder: String,
        _ keyPath: WritableKeyPath<OrganizationUnit, String>,
        width: CGFloat
    ) -> some View {
        CommitFormattingTextField(
            placeholder: placeholder,
            text: unitTextBinding(keyPath),
            formatter: { $0 },
            updatesContinuously: false
        )
        .appTextInputChrome()
        .frame(width: width)
        .help(placeholder)
    }

    /// The latest stored unit (the row value may be one render old).
    private func storedUnit() -> OrganizationUnit? {
        store.organization(id: organization.id)?.unit(withID: unit.id)
    }

    private func save(_ change: (inout OrganizationUnit) -> Void) {
        guard var updated = storedUnit() else { return }
        let before = updated
        change(&updated)
        guard updated != before else { return }
        store.updateOrganizationUnit(organizationID: organization.id, unit: updated)
    }

    private func unitTextBinding(_ keyPath: WritableKeyPath<OrganizationUnit, String>) -> Binding<String> {
        Binding(
            get: { storedUnit()?[keyPath: keyPath] ?? unit[keyPath: keyPath] },
            set: { newValue in
                save { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func unitBoolBinding(_ keyPath: WritableKeyPath<OrganizationUnit, Bool>) -> Binding<Bool> {
        Binding(
            get: { storedUnit()?[keyPath: keyPath] ?? unit[keyPath: keyPath] },
            set: { newValue in
                save { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var childrenNotInAddressBinding: Binding<Bool> {
        Binding(
            get: { !(storedUnit()?.childrenInAddress ?? unit.childrenInAddress) },
            set: { newValue in
                save { $0.childrenInAddress = !newValue }
            }
        )
    }
}

// MARK: - Researcher rows: unit picker

/// "Enhet: …" drop-down for an affiliation, employment or education row.
/// Lists the organization's units as an indented tree (all units, since
/// validity dates are not shown; templates never), plus "Ingen enhet".
struct OrganizationUnitPickerMenu: View {
    let organization: OrganizationRecord?
    let unitID: String?
    let language: AppLanguage
    var width: CGFloat? = nil
    let onSelect: (OrganizationUnit?) -> Void

    private var selectedUnit: OrganizationUnit? {
        organization?.unit(withID: unitID)
    }

    private var labelText: String {
        if organization == nil {
            return language.text("Unit: choose organization first", "Enhet: välj organisation först")
        }
        if let selectedUnit {
            return language.text("Unit: ", "Enhet: ") + selectedUnit.displayName(language: language)
        }
        return language.text("Unit: Choose…", "Enhet: Välj…")
    }

    private var helpText: String {
        if let organization, let selectedUnit {
            return organization.displayName(for: language) + " / " + organization.unitPathText(to: selectedUnit.id, language: language)
        }
        if organization == nil {
            return language.text(
                "Write or choose an organization that is in the Organizations list; then its units can be chosen here.",
                "Skriv eller välj en organisation som finns under Organisationer, så kan dess enheter väljas här."
            )
        }
        return language.text(
            "Choose the unit in the organization's tree. The department text is filled in from the unit.",
            "Välj enheten i organisationens träd. Avdelningstexten fylls i från enheten."
        )
    }

    var body: some View {
        Menu {
            Button(language.text("No unit", "Ingen enhet")) {
                onSelect(nil)
            }
            if let organization {
                let rows = organization.pickerUnitRows(
                    onDay: OrganizationTree.dayString(from: Date()),
                    // F21: validity dates are not shown in the app, so every
                    // unit is offered (templates still never are).
                    includeEnded: true,
                    selectedUnitID: unitID
                )
                if rows.isEmpty {
                    Divider()
                    Button(language.text("The organization has no units yet", "Organisationen har inga enheter ännu")) {}
                        .disabled(true)
                } else {
                    Divider()
                    ForEach(rows) { row in
                        Button(menuTitle(for: row)) {
                            onSelect(row.unit)
                        }
                    }
                }
            }
        } label: {
            Text(labelText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.borderlessButton)
        .font(.system(size: 12, weight: .semibold))
        .frame(width: width, alignment: .leading)
        .frame(minHeight: AppPalette.fieldMinHeight)
        .disabled(organization == nil)
        .help(helpText)
    }

    private func menuTitle(for row: OrganizationUnitTreeRow) -> String {
        var title = organizationUnitMenuIndent(row.depth) + row.unit.displayName(language: language)
        if row.unit.id == unitID {
            title += language.text(" – selected", " – vald")
        }
        return title
    }
}

// MARK: - Researcher page: publication address

struct ResearcherPublicationAddressPanel: View {
    let lines: [String]
    let language: AppLanguage

    var body: some View {
        PublicationCompactPanel(
            title: language.text("Publication address", "Publikationsadress"),
            usesInnerSurface: false
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if lines.isEmpty {
                    Text(language.text(
                        "No address lines yet. Add an affiliation and choose its organization and unit (under Unit) so the address is written the way the organization wants it.",
                        "Inga adressrader ännu. Lägg till en affiliering och välj organisation och enhet (under Enhet) så skrivs adressen som organisationen vill ha den."
                    ))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1).")
                                .appTypography(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .trailing)
                            Text(line)
                                .appTypography(.body)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button(language.text("Copy", "Kopiera")) {
                                copyToPasteboard(line)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .semibold))
                            .help(language.text("Copy this address line", "Kopiera den här adressraden"))
                        }
                    }
                    HStack(spacing: 10) {
                        Button(language.text("Copy all", "Kopiera alla")) {
                            copyToPasteboard(lines.joined(separator: "\n"))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(language.text("Copy all address lines, one per line", "Kopiera alla adressrader, en per rad"))
                        Text(language.text(
                            "Rows without a chosen organization are written from their text.",
                            "Rader utan vald organisation skrivs utifrån texten."
                        ))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
