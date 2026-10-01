import AppKit
import SwiftUI

struct DataExchangeExportCenterView: View {
    @ObservedObject var store: GrantDataStore
    let dismiss: () -> Void

    @State private var format: FootprintDataExchangeFormat = .databasePackage
    @State private var scope: FootprintDataExchangeScope = .entireApp
    @State private var selectedCategories = FootprintDataExchangeCategory.defaultSelection(for: .databasePackage)
    @State private var categoryFilter = ""

    var body: some View {
        let language = store.language

        FootprintDialogFrame(
            title: language.text("Export", "Exportera"),
            subtitle: language.text(
                "Create an importable, verified database package or a complete one-way Excel safety workbook.",
                "Skapa ett importerbart, verifierat databaspaket eller en komplett enkelriktad Excel-säkerhetskopia."
            ),
            closeAction: dismiss
        ) {
            VStack(alignment: .leading, spacing: 20) {
                ExportStepIndicator(
                    steps: [
                        language.text("Format", "Format"),
                        language.text("Scope", "Omfattning"),
                        language.text("Data", "Data"),
                        language.text("Export", "Export"),
                    ],
                    activeIndex: scope == .selectedCategories ? 2 : 3
                )

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        ExportOptionCard(
                            title: language.text("Format", "Format"),
                            subtitle: language.text(
                                "Database packages can be imported. Excel workbooks are safety exports only.",
                                "Databaspaket kan importeras. Excel-arbetsböcker är endast säkerhetsexporter."
                            )
                        ) {
                            Picker("", selection: $format) {
                                ForEach(FootprintDataExchangeFormat.allCases) { option in
                                    Text(option.displayName(language)).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        ExportOptionCard(
                            title: language.text("Scope", "Omfattning"),
                            subtitle: language.text(
                                "Export the complete database or selected safe, self-contained categories.",
                                "Exportera hela databasen eller valda säkra, fristående kategorier."
                            )
                        ) {
                            Picker("", selection: $scope) {
                                ForEach(FootprintDataExchangeScope.availableCases(for: format)) { option in
                                    Text(option.displayName(language)).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    .frame(width: 330, alignment: .topLeading)

                    ExportOptionCard(
                        title: language.text("Data", "Data"),
                        subtitle: language.text(
                            "Selective import is additive. Required linked categories are included automatically so IDs remain resolvable.",
                            "Selektiv import är additiv. Nödvändiga länkade kategorier inkluderas automatiskt så att ID:n kan lösas."
                        )
                    ) {
                        HStack(spacing: 10) {
                            TextField(language.text("Filter categories", "Filtrera kategorier"), text: $categoryFilter)
                                .appTextInputChrome()
                                .disabled(scope != .selectedCategories)

                            Button {
                                selectedCategories = Set(filteredCategories)
                            } label: {
                                Image(systemName: "checkmark.circle")
                            }
                            .help(language.text("Select all visible", "Markera alla synliga"))
                            .accessibilityLabel(language.text("Select all visible", "Markera alla synliga"))
                            .disabled(scope != .selectedCategories || filteredCategories.isEmpty)

                            Button {
                                for category in filteredCategories {
                                    selectedCategories.remove(category)
                                }
                            } label: {
                                Image(systemName: "circle")
                            }
                            .help(language.text("Clear visible", "Avmarkera synliga"))
                            .accessibilityLabel(language.text("Clear visible", "Avmarkera synliga"))
                            .disabled(scope != .selectedCategories || filteredCategories.isEmpty)
                        }

                        ScrollView {
                            if selectableCategories.isEmpty {
                                ContentUnavailableView {
                                    Label(
                                        language.text("Complete workbook", "Komplett arbetsbok"),
                                        systemImage: "tablecells"
                                    )
                                } description: {
                                    Text(
                                        language.text(
                                            "The Excel safety export always includes all current app data and cannot be imported.",
                                            "Excel-säkerhetsexporten innehåller alltid all aktuell appdata och kan inte importeras."
                                        )
                                    )
                                }
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(filteredCategories) { category in
                                        categoryRow(category, language: language)
                                        if category != filteredCategories.last {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 280)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppPalette.secondaryCardSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppPalette.subtleBorder, lineWidth: 1)
                        )
                        .opacity(scope == .selectedCategories ? 1 : 0.55)
                    }
                }

            }
        } footer: {
            Label(summaryText(language), systemImage: "doc.text.magnifyingglass")
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 16)
            FootprintDialogActions(
                cancelTitle: language.text("Cancel", "Avbryt"),
                primaryTitle: language.text("Export", "Exportera"),
                primarySystemImage: "square.and.arrow.up",
                includesLeadingSpacer: false,
                cancelAction: { dismiss() },
                primaryAction: { exportSelection() }
            )
        }
        .frame(minWidth: 920, minHeight: 640)
        .onChange(of: format) { _, newFormat in
            if !FootprintDataExchangeScope.availableCases(for: newFormat).contains(scope) {
                scope = .entireApp
            }
            selectedCategories = selectedCategories
                .intersection(Set(FootprintDataExchangeCategory.selectableCases(for: newFormat)))
            if selectedCategories.isEmpty {
                selectedCategories = FootprintDataExchangeCategory.defaultSelection(for: newFormat)
            }
        }
    }

    private var selectableCategories: [FootprintDataExchangeCategory] {
        FootprintDataExchangeCategory.selectableCases(for: format)
    }

    private var filteredCategories: [FootprintDataExchangeCategory] {
        let needle = categoryFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return selectableCategories }
        return selectableCategories.filter {
            $0.displayName(store.language).localizedStandardContains(needle)
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: FootprintDataExchangeCategory, language: AppLanguage) -> some View {
        Toggle(
            isOn: Binding(
                get: { selectedCategories.contains(category) },
                set: { isSelected in
                    if isSelected {
                        selectedCategories.insert(category)
                    } else {
                        selectedCategories.remove(category)
                    }
                }
            )
        ) {
            HStack {
                Text(category.displayName(language))
                    .font(appFont(.body).weight(.medium))
                Spacer()
                if automaticallyIncludedCategories.contains(category) {
                    Text(language.text("Required dependency", "Nödvändigt beroende"))
                        .font(appFont(.secondary))
                        .foregroundStyle(.secondary)
                }
                Text(countText(for: category, language: language))
                    .font(appFont(.secondary))
                    .foregroundStyle(.secondary)
            }
        }
        .appCheckboxStyle()
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            effectiveSelectedCategories.contains(category) && scope == .selectedCategories
                ? AppPalette.activeTabSurface.opacity(0.12)
                : Color.clear
        )
        .disabled(scope != .selectedCategories)
    }

    private func countText(for category: FootprintDataExchangeCategory, language: AppLanguage) -> String {
        let count = store.dataExchangeCategoryItemCount(category)
        return language.text("\(count) items", "\(count) poster")
    }

    private func summaryText(_ language: AppLanguage) -> String {
        let scopeName = scope.displayName(language)
        let formatName = format.displayName(language)
        if scope == .selectedCategories {
            let dependencyCount = automaticallyIncludedCategories.count
            if dependencyCount > 0 {
                return language.text(
                    "\(selectedCategories.count) selected + \(dependencyCount) required dependencies, \(formatName)",
                    "\(selectedCategories.count) valda + \(dependencyCount) nödvändiga beroenden, \(formatName)"
                )
            }
            return language.text(
                "\(selectedCategories.count) categories, \(formatName)",
                "\(selectedCategories.count) kategorier, \(formatName)"
            )
        }
        return "\(scopeName), \(formatName)"
    }

    private var effectiveSelectedCategories: Set<FootprintDataExchangeCategory> {
        FootprintDataExchangeCategory.dependencyClosure(for: selectedCategories)
    }

    private var automaticallyIncludedCategories: Set<FootprintDataExchangeCategory> {
        effectiveSelectedCategories.subtracting(selectedCategories)
    }

    private func exportSelection() {
        switch format {
        case .databasePackage:
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.nameFieldStringValue = store.language.text("Footprint database", "Footprint-databas") + ".footprintdb"
            panel.title = store.language.text("Export Footprint database", "Exportera Footprint-databas")
            panel.prompt = store.language.text("Export", "Exportera")
            guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
            store.exportDatabasePackage(to: destinationURL, scope: scope, categories: selectedCategories)
            dismiss()
        case .excelWorkbook:
            store.exportEntireAppWorkbookToDefaultLocation()
            dismiss()
        }
    }
}

private struct ExportStepIndicator: View {
    let steps: [String]
    let activeIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 7) {
                    Text("\(index + 1)")
                        .font(appBadgeFont())
                        .foregroundStyle(index <= activeIndex ? AppPalette.activeTabText : .secondary)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(index <= activeIndex ? AppPalette.activeTabSurface : AppPalette.fieldSurface)
                        )
                    Text(title)
                        .appTypography(.secondary)
                        .foregroundStyle(index <= activeIndex ? AppPalette.appText : .secondary)
                }
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(AppPalette.subtleBorder)
                        .frame(height: 1)
                }
            }
        }
        .appCardChrome(
            padding: 12,
            fill: AppPalette.cardSurface,
            stroke: AppPalette.subtleBorder,
            cornerRadius: 12
        )
    }
}

private struct ExportOptionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appTypography(.sectionTitle)
                Text(subtitle)
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .appCardChrome(
            padding: 16,
            fill: AppPalette.cardSurface,
            stroke: AppPalette.subtleBorder,
            cornerRadius: 12
        )
    }
}
