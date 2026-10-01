import AppKit
import SwiftUI

/// A togglable top-level heading of a record document; the floating panel
/// shows one checkbox per case.
protocol RecordDocumentSection: RawRepresentable, CaseIterable, Identifiable, Hashable where RawValue == String {
    func title(language: AppLanguage) -> String
}

extension ProjectDocumentSection: RecordDocumentSection {}
extension ApplicationDocumentSection: RecordDocumentSection {}
extension PublicationDocumentSection: RecordDocumentSection {}

/// Zero-size view that publishes the project document preview to the floating
/// document button in the app shell (the document twin of
/// `ContributorCompositionPopoverButton`).
struct ProjectDocumentContentAnchor: View {
    @ObservedObject var store: GrantDataStore
    let projectID: String
    let title: String

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .floatingDocumentContent(
                id: "project-document-\(projectID)",
                title: title
            ) {
                ProjectDocumentPanelContent(store: store, projectID: projectID)
            }
    }
}

struct ProjectDocumentPanelContent: View {
    @ObservedObject var store: GrantDataStore
    let projectID: String

    var body: some View {
        RecordDocumentPanelContent<ProjectDocumentSection>(
            store: store,
            excludedSectionsKey: "ProjectDocumentExcludedSections",
            missingRecordText: { $0.text("No project selected.", "Inget projekt valt.") },
            fileStem: { language in
                store.projects.first(where: { $0.id == projectID }).map {
                    "\(language.text("Project", "Projekt")) \($0.displayName(for: language))"
                }
            },
            buildDocument: { sections, language in
                store.projects.first(where: { $0.id == projectID }).map {
                    store.projectSummaryDocument(for: $0, exportLanguage: language, includedSections: sections)
                }
            },
            exportWord: { sections, destinationURL in
                guard let project = store.projects.first(where: { $0.id == projectID }) else { return }
                store.exportProjectDocumentAsync(project: project, includedSections: sections, to: destinationURL)
            }
        )
    }
}

struct ApplicationDocumentPanelContent: View {
    @ObservedObject var store: GrantDataStore
    let applicationID: String

    var body: some View {
        RecordDocumentPanelContent<ApplicationDocumentSection>(
            store: store,
            excludedSectionsKey: "ApplicationDocumentExcludedSections",
            missingRecordText: { $0.text("No grant selected.", "Inget anslag valt.") },
            fileStem: { language in
                store.application(id: applicationID).map {
                    let name = store.localizedGrantName(for: $0, language: language).nonEmpty ?? $0.displayTitle
                    return "\(language.text("Grant", "Anslag")) \(String(name.prefix(60)))"
                }
            },
            buildDocument: { sections, language in
                store.application(id: applicationID).map {
                    store.applicationSummaryDocument(for: $0, exportLanguage: language, includedSections: sections)
                }
            },
            exportWord: { sections, destinationURL in
                guard let application = store.application(id: applicationID) else { return }
                store.exportApplicationDocumentAsync(application: application, includedSections: sections, to: destinationURL)
            }
        )
    }
}

struct PublicationDocumentPanelContent: View {
    @ObservedObject var store: GrantDataStore
    let publicationID: String

    var body: some View {
        RecordDocumentPanelContent<PublicationDocumentSection>(
            store: store,
            excludedSectionsKey: "PublicationDocumentExcludedSections",
            missingRecordText: { $0.text("No publication selected.", "Ingen publikation vald.") },
            fileStem: { language in
                store.publication(id: publicationID).map {
                    "\(language.text("Publication", "Publikation")) \(String($0.title.prefix(60)))"
                }
            },
            buildDocument: { sections, language in
                store.publication(id: publicationID).map {
                    store.publicationSummaryDocument(for: $0, exportLanguage: language, includedSections: sections)
                }
            },
            exportWord: { sections, destinationURL in
                guard let publication = store.publication(id: publicationID) else { return }
                store.exportPublicationDocumentAsync(publication: publication, includedSections: sections, to: destinationURL)
            }
        )
    }
}

/// The floating panel body shared by the project/grant/publication documents:
/// a section-picker settings column, Word/PDF export actions and an HTML
/// preview of the summary document. The same HTML drives the PDF export, so
/// the preview is exactly what the PDF will contain.
struct RecordDocumentPanelContent<Section: RecordDocumentSection>: View where Section.AllCases: RandomAccessCollection {
    @ObservedObject var store: GrantDataStore
    private let missingRecordText: (AppLanguage) -> String
    private let fileStem: (AppLanguage) -> String?
    private let buildDocument: (Set<Section>, AppLanguage) -> CVExportDocument?
    private let exportWord: (Set<Section>, URL) -> Void

    @StateObject private var pdfExporter = HTMLPDFExportCoordinator()
    @AppStorage private var excludedSectionsStorage: String

    init(
        store: GrantDataStore,
        excludedSectionsKey: String,
        missingRecordText: @escaping (AppLanguage) -> String,
        fileStem: @escaping (AppLanguage) -> String?,
        buildDocument: @escaping (Set<Section>, AppLanguage) -> CVExportDocument?,
        exportWord: @escaping (Set<Section>, URL) -> Void
    ) {
        self.store = store
        self.missingRecordText = missingRecordText
        self.fileStem = fileStem
        self.buildDocument = buildDocument
        self.exportWord = exportWord
        _excludedSectionsStorage = AppStorage(wrappedValue: "", excludedSectionsKey)
    }

    private var language: AppLanguage { store.language }

    private var includedSections: Set<Section> {
        Set(Section.allCases).subtracting(excludedSections)
    }

    private var excludedSections: Set<Section> {
        Set(
            excludedSectionsStorage
                .components(separatedBy: ",")
                .compactMap { Section(rawValue: $0) }
        )
    }

    var body: some View {
        if let document = buildDocument(includedSections, language) {
            let html = htmlPreview(for: document)
            HStack(spacing: 0) {
                settingsColumn

                Divider()

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)

                        Button(language.text("Export to Word", "Exportera till Word")) {
                            exportWordTapped()
                        }
                        .appSaveButtonStyle()

                        Button(language.text("Export to PDF", "Exportera till PDF")) {
                            exportPDF(html: html)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    HTMLPreviewWebView(html: html)
                }
            }
        } else {
            Text(missingRecordText(language))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var settingsColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text(language.text("Content", "Innehåll"))
                    .appTypography(.panelTitle)

                ForEach(Section.allCases) { section in
                    Toggle(isOn: sectionBinding(for: section)) {
                        Text(section.title(language: language))
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: 200)
    }

    private func sectionBinding(for section: Section) -> Binding<Bool> {
        Binding(
            get: { !excludedSections.contains(section) },
            set: { isIncluded in
                var excluded = Set(excludedSectionsStorage.components(separatedBy: ",").filter { !$0.isEmpty })
                if isIncluded {
                    excluded.remove(section.rawValue)
                } else {
                    excluded.insert(section.rawValue)
                }
                excludedSectionsStorage = excluded.sorted().joined(separator: ",")
            }
        )
    }

    private func exportFileName(stem: String, fileExtension: String) -> String {
        "\(stem) \(store.cvExportTimestampString()).\(fileExtension)"
    }

    private func exportWordTapped() {
        guard let stem = fileStem(language) else { return }
        let destinationURL = store.exportDestinationURL(
            fileName: exportFileName(stem: stem, fileExtension: "docx")
        )
        exportWord(includedSections, destinationURL)
    }

    private func exportPDF(html: String) {
        guard let stem = fileStem(language) else { return }
        let destinationURL = store.exportDestinationURL(
            fileName: exportFileName(stem: stem, fileExtension: "pdf")
        )
        pdfExporter.export(html: html, to: destinationURL) { result in
            switch result {
            case .success(let url):
                store.notice = StoreNotice(
                    message: language.text(
                        "Exported PDF to \(url.lastPathComponent).",
                        "Exporterade PDF till \(url.lastPathComponent)."
                    ),
                    tone: .success
                )
                store.loadError = nil
                NSWorkspace.shared.open(url)
            case .failure(let error):
                store.loadError = error.localizedDescription
                store.notice = StoreNotice(
                    message: language.text("PDF export failed.", "PDF-export misslyckades."),
                    tone: .error
                )
            }
        }
    }
}
