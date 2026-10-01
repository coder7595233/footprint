import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private enum ExportWorkspaceKind: String, CaseIterable, Identifiable {
    case cv
    case annualReport
    case teachingMerits
    case publications

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .cv:
            "CV"
        case .annualReport:
            language.text("Annual", "Årsrapport")
        case .teachingMerits:
            language.text("Teaching", "Pedagogik")
        case .publications:
            language.text("Publications", "Publikationer")
        }
    }

    var systemImage: String {
        switch self {
        case .cv: "doc.text"
        case .annualReport: "doc.text.image"
        case .teachingMerits: "person.2"
        case .publications: "text.book.closed"
        }
    }
}

private enum PublicationWorkspaceTemplate: String, CaseIterable, Identifiable {
    case ama
    case own
    case vetenskapsradet
    case heartLungfonden

    var id: String { rawValue }
}

private enum ExportOutputFormat: String, CaseIterable, Identifiable {
    case word
    case pdf

    var id: String { rawValue }
}

private enum ExportPreviewDocument {
    case cv(CVExportDocument)
    case teachingMerits(TeachingMeritsExportDocument)
    case publications(PublicationAMAExportDocument)
    case publicationTemplate(PublicationTemplateExportDocument)
}

private enum TeachingMeritsSectionKey: String, CaseIterable, Identifiable {
    case summary
    case groupTeaching
    case supervision
    case courseAdministration

    var id: String { rawValue }
}

private struct TeachingMeritsWorkspaceConfiguration {
    var includedSections: Set<TeachingMeritsSectionKey> = Set(TeachingMeritsSectionKey.allCases)
}

private enum CVWorkspacePanel: String, CaseIterable, Identifiable {
    case documentSetup
    case profileEditor

    var id: String { rawValue }
}

private struct CVPreviewSourceLinkSection: Identifiable {
    let id: String
    let title: String
    let links: [CVPreviewSourceLink]
}

private struct CVPreviewSourceLink: Identifiable {
    enum Destination {
        case profileEditor
        case route(AppRoute)
    }

    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let matchTerms: [String]
    let destination: Destination

    init(
        id: String,
        title: String,
        subtitle: String?,
        systemImage: String,
        matchTerms: [String] = [],
        destination: Destination
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.matchTerms = matchTerms
        self.destination = destination
    }
}

private let cvPreviewSourceLinkURLScheme = "footprint-cv-source"

private extension CVPreviewSourceLink {
    var previewURLString: String {
        var components = URLComponents()
        components.scheme = cvPreviewSourceLinkURLScheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url?.absoluteString ?? "\(cvPreviewSourceLinkURLScheme)://open"
    }
}

private struct ExportPreviewTypography {
    let titleFont: String
    let subtitleFont: String
    let bodyFont: String
    let sectionFont: String
    let subsectionFont: String
    let headerFooterFont: String
    let citationIndentEm: Double
    let citationSpacingEm: Double
}

enum ExportPreviewAppearance {
    case standard
    case darkCVPreview

    var shellBackgroundCSS: String {
        switch self {
        case .standard:
            return "#eef1ee"
        case .darkCVPreview:
            return "#050608"
        }
    }

    var paperBackgroundCSS: String {
        switch self {
        case .standard:
            return "#ffffff"
        case .darkCVPreview:
            return "#050608"
        }
    }

    var textColorCSS: String {
        switch self {
        case .standard:
            return "#1f2328"
        case .darkCVPreview:
            return "#f5f7f8"
        }
    }

    var mutedTextColorCSS: String {
        switch self {
        case .standard:
            return "#6b7280"
        case .darkCVPreview:
            return "#c3ccd5"
        }
    }

    var secondaryTextColorCSS: String {
        switch self {
        case .standard:
            return "#4b5563"
        case .darkCVPreview:
            return "#d7dee5"
        }
    }

    var noteTextColorCSS: String {
        switch self {
        case .standard:
            return "#374151"
        case .darkCVPreview:
            return "#e1e7ec"
        }
    }

    var borderColorCSS: String {
        switch self {
        case .standard:
            return "rgba(40, 45, 40, 0.08)"
        case .darkCVPreview:
            return "rgba(255, 255, 255, 0.16)"
        }
    }

    var shadowColorCSS: String {
        switch self {
        case .standard:
            return "rgba(20, 25, 20, 0.12)"
        case .darkCVPreview:
            return "rgba(0, 0, 0, 0.42)"
        }
    }
}

@MainActor
final class HTMLPDFExportCoordinator: NSObject, ObservableObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var destinationURL: URL?
    private var completion: ((Result<URL, Error>) -> Void)?

    func export(html: String, to destinationURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        self.destinationURL = destinationURL
        self.completion = completion

        let config = WKWebViewConfiguration()
        // The page is the app's own HTML: scripts inside it are never needed.
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        self.webView = webView
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Only the app's own page loads; any other navigation is stopped.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        decisionHandler(url == nil || url?.scheme == "about" ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak webView] in
            guard let self, let webView, let destinationURL = self.destinationURL else { return }
            let configuration = WKPDFConfiguration()
            webView.createPDF(configuration: configuration) { result in
                do {
                    let data = try result.get()
                    try data.write(to: destinationURL, options: .atomic)
                    self.completion?(.success(destinationURL))
                } catch {
                    self.completion?(.failure(error))
                }
                self.webView = nil
                self.destinationURL = nil
                self.completion = nil
            }
        }
    }
}

struct HTMLPreviewScrollRequest {
    let id = UUID()
    let targetHeadings: [String]
}

struct HTMLPreviewWebView: NSViewRepresentable {
    let html: String
    var scrollRequest: HTMLPreviewScrollRequest?
    var onOpenURL: (URL) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenURL: onOpenURL)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Scripts in the page are off; the app's own scroll script still
        // runs (it is injected by the app, not part of the page).
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastHTML = html
        context.coordinator.pendingScrollRequest = scrollRequest
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onOpenURL = onOpenURL
        context.coordinator.pendingScrollRequest = scrollRequest
        guard context.coordinator.lastHTML != html else {
            context.coordinator.performScrollIfNeeded(in: nsView, request: scrollRequest)
            return
        }
        context.coordinator.lastHTML = html
        nsView.loadHTMLString(html, baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""
        var pendingScrollRequest: HTMLPreviewScrollRequest?
        private var lastHandledScrollRequestID: UUID?
        var onOpenURL: (URL) -> Void

        init(onOpenURL: @escaping (URL) -> Void) {
            self.onOpenURL = onOpenURL
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            performScrollIfNeeded(in: webView, request: pendingScrollRequest)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            // WKWebView's synthetic initial document load must be allowed.
            if navigationAction.navigationType == .other,
               url.scheme == "about" || url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
            if url.scheme == cvPreviewSourceLinkURLScheme {
                onOpenURL(url)
            } else if let externalURL = safeExternalURL(url) {
                NSWorkspace.shared.open(externalURL)
            }
        }

        func performScrollIfNeeded(in webView: WKWebView, request: HTMLPreviewScrollRequest?) {
            guard let request,
                  request.id != lastHandledScrollRequestID,
                  !request.targetHeadings.isEmpty else { return }
            lastHandledScrollRequestID = request.id
            webView.evaluateJavaScript(Self.scrollScript(for: request), completionHandler: nil)
        }

        private static func scrollScript(for request: HTMLPreviewScrollRequest) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: request.targetHeadings, options: [])) ?? Data("[]".utf8)
            let candidatesJSON = String(data: data, encoding: .utf8) ?? "[]"
            return """
            (function() {
              const candidates = \(candidatesJSON);
              window.setTimeout(function() {
                const normalize = function(value) {
                  return (value || '').replace(/\\s+/g, ' ').trim().toLocaleLowerCase();
                };
                const targets = candidates.map(normalize).filter(Boolean);
                if (!targets.length) { return; }
                const headings = Array.from(document.querySelectorAll('h2, h3'));
                let element = null;
                for (const target of targets) {
                  element = headings.find(function(heading) {
                    return normalize(heading.textContent) === target;
                  });
                  if (element) { break; }
                }
                if (!element) {
                  for (const target of targets) {
                    element = headings.find(function(heading) {
                      return normalize(heading.textContent).includes(target);
                    });
                    if (element) { break; }
                  }
                }
                if (!element) { return; }
                const top = Math.max(0, window.scrollY + element.getBoundingClientRect().top - 8);
                window.scrollTo({ top: top, left: 0, behavior: 'auto' });
              }, 80);
            })();
            """
        }
    }
}

struct CVExportWorkspaceView: View {
    let store: GrantDataStore

    @State private var workspaceKind: ExportWorkspaceKind = .cv
    @State private var cvConfiguration = CVCustomExportConfiguration()
    @State private var annualReportYear = Calendar.current.component(.year, from: Date())
    @State private var annualReportLanguage: AppLanguage = .swedish
    /// Round 12: grants where the user is only co-applicant are left out
    /// unless chosen here.
    @State private var annualReportIncludeCoApplicantGrants = false
    @State private var teachingMeritsConfiguration = TeachingMeritsWorkspaceConfiguration()
    @State private var publicationTemplate: PublicationWorkspaceTemplate = .own
    @State private var publicationConfiguration = PublicationCustomExportConfiguration()
    @State private var heartLungfondenConfiguration = PublicationHeartLungfondenExportConfiguration()
    @State private var layoutOptions = ExportDocumentLayoutOptions()
    @State private var outputFormat: ExportOutputFormat = .word
    @State private var cvWorkspacePanel: CVWorkspacePanel = .documentSetup
    @State private var vrSearchText = ""
    @State private var vrMinimumImpactFactorText = ""
    @State private var vrIncludeNorwegianLevel1 = false
    @State private var vrIncludeNorwegianLevel2 = false
    @State private var vrSelectedCandidateIDs = Set<String>()
    @State private var vrNotesByCandidateID: [String: String] = [:]
    @State private var previewScrollRequest: HTMLPreviewScrollRequest?
    @StateObject private var pdfExporter = HTMLPDFExportCoordinator()

    private let maxSelectedOutputs = 10

    private var language: AppLanguage { store.language }

    private var effectiveUsesDarkAppearance: Bool {
        if let preferredMode = currentVisualModePreference() ?? store.visualMode {
            return preferredMode.usesDarkAppearance
        }
        return AppAppearanceRegistry.usesDarkPalette()
    }

    private var livePreviewAppearance: ExportPreviewAppearance {
        usesCVStyledPreview && effectiveUsesDarkAppearance ? .darkCVPreview : .standard
    }

    private var usesCVStyledPreview: Bool {
        workspaceKind == .cv || workspaceKind == .annualReport
    }

    private var vrCandidates: [CVVROutputCandidate] {
        store.vetenskapsradetOutputCandidates()
            .filter { $0.sourceKind == .publication && $0.category == .peerReviewedOriginalArticle }
    }

    private var vrFilterOptions: CVVROutputFilterOptions {
        CVVROutputFilterOptions(
            searchText: vrSearchText,
            minimumImpactFactor: parsedImpactFactorFilter(vrMinimumImpactFactorText),
            includedNorwegianLevels: vrNorwegianLevelFilters
        )
    }

    private var vrNorwegianLevelFilters: Set<Int> {
        var filters = Set<Int>()
        if vrIncludeNorwegianLevel1 {
            filters.insert(1)
        }
        if vrIncludeNorwegianLevel2 {
            filters.insert(2)
        }
        return filters
    }

    private var filteredVRCandidates: [CVVROutputCandidate] {
        vrCandidates.filter { vrFilterOptions.matches($0) }
    }

    private var selectedVROutputs: [CVVRSelectedOutput] {
        vrCandidates
            .filter { vrSelectedCandidateIDs.contains($0.id) }
            .map { candidate in
                CVVRSelectedOutput(
                    candidate: candidate,
                    note: vrNotesByCandidateID[candidate.id, default: candidate.noteSuggestion]
                )
            }
    }

    private var hasValidVRSelection: Bool {
        let count = vrSelectedCandidateIDs.count
        guard (1...maxSelectedOutputs).contains(count) else { return false }
        return selectedVROutputs.allSatisfy { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var previewDocument: ExportPreviewDocument? {
        switch workspaceKind {
        case .cv:
            if cvConfiguration.style == .vetenskapsradet {
                guard hasValidVRSelection else { return nil }
                return .cv(store.publicationVetenskapsradetPreviewDocument(selectedOutputs: selectedVROutputs, layout: layoutOptions))
            }
            return .cv(store.customCVPreviewDocument(configuration: cvConfiguration, layout: layoutOptions))
        case .annualReport:
            return .cv(
                store.annualReportPreviewDocument(
                    year: annualReportYear,
                    exportLanguage: annualReportLanguage,
                    includeCoApplicantGrants: annualReportIncludeCoApplicantGrants,
                    layout: layoutOptions
                )
            )
        case .teachingMerits:
            return .teachingMerits(filteredTeachingMeritsDocument())
        case .publications:
            switch publicationTemplate {
            case .ama:
                return .publications(
                    store.publicationCustomPreviewDocument(
                        configuration: PublicationCustomExportConfiguration(),
                        layout: layoutOptions
                    )
                )
            case .own:
                return .publications(store.publicationCustomPreviewDocument(configuration: publicationConfiguration, layout: layoutOptions))
            case .vetenskapsradet:
                guard hasValidVRSelection else { return nil }
                return .cv(store.publicationVetenskapsradetPreviewDocument(selectedOutputs: selectedVROutputs, layout: layoutOptions))
            case .heartLungfonden:
                let payload = store.publicationHeartLungfondenPreviewDocument(configuration: heartLungfondenConfiguration, layout: layoutOptions)
                return payload.sections.contains(where: { !$0.items.isEmpty }) ? .publicationTemplate(payload) : nil
            }
        }
    }

    private var livePreviewHTML: String {
        previewHTML(for: livePreviewAppearance, includeSourceLinks: true)
    }

    private var exportHTML: String {
        previewHTML(for: .standard, includeSourceLinks: false)
    }

    private func previewHTML(
        for appearance: ExportPreviewAppearance,
        includeSourceLinks: Bool = false
    ) -> String {
        guard let previewDocument else {
            return previewEmptyHTML(
                title: language.text("Nothing to preview yet", "Inget att förhandsvisa ännu"),
                message: language.text(
                    "Choose export settings on the left. Vetenskapsrådet exports also need 1-10 selected outputs with notes.",
                    "Välj exportinställningar till vänster. Vetenskapsrådets export kräver också 1-10 valda outputs med kommentarer."
                ),
                appearance: usesCVStyledPreview ? appearance : .standard
            )
        }
        switch previewDocument {
        case .cv(let document):
            let sourceLinksByItemKey = includeSourceLinks
                ? previewSourceLinksByItemKey(language: language)
                : [:]
            return htmlPreview(
                for: document,
                appearance: usesCVStyledPreview ? appearance : .standard,
                sourceLinksByItemKey: sourceLinksByItemKey,
                sourceLinkActionTitle: language.text("Edit", "Redigera")
            )
        case .teachingMerits(let document):
            return htmlPreview(for: document, typography: .timesDocument)
        case .publications(let document):
            let sourceLinksByItemKey = includeSourceLinks
                ? previewSourceLinksByItemKey(language: language)
                : [:]
            return htmlPreview(
                for: document,
                typography: .timesDocument,
                sourceLinksByItemKey: sourceLinksByItemKey,
                sourceLinkActionTitle: language.text("Edit", "Redigera")
            )
        case .publicationTemplate(let document):
            let sourceLinksByItemKey = includeSourceLinks
                ? previewSourceLinksByItemKey(language: language)
                : [:]
            return htmlPreview(
                for: document,
                typography: .timesDocument,
                sourceLinksByItemKey: sourceLinksByItemKey,
                sourceLinkActionTitle: language.text("Edit", "Redigera")
            )
        }
    }

    private var canExport: Bool {
        previewDocument != nil
    }

    private var isShowingCVProfileEditor: Bool {
        workspaceKind == .cv && cvWorkspacePanel == .profileEditor
    }

    private var workspaceHeaderTitle: String {
        switch workspaceKind {
        case .cv:
            return language.text("CV", "CV")
        case .annualReport:
            return language.text("Annual report", "Årsrapport")
        case .teachingMerits:
            return language.text("Teaching merits", "Pedagogiska meriter")
        case .publications:
            return language.text("Publications list", "Publikationslista")
        }
    }

    private var workspaceHeaderDescription: String {
        ""
    }

    private func segmentedControl<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        options: [(String, Value)],
        labelWidth: CGFloat = 170,
        isDisabled: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AppFieldLabelText(text: title)
                .frame(width: labelWidth, alignment: .leading)
            Picker(title, selection: selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Text(option.0).tag(option.1)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isDisabled)
    }

    private func outputFormatPicker(language: AppLanguage) -> some View {
        Picker(language.text("Export format", "Exportformat"), selection: $outputFormat) {
            Text("Word").tag(ExportOutputFormat.word)
            Text("PDF").tag(ExportOutputFormat.pdf)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        let language = store.language

        PersistentSplitView(layout: .cvExport) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    documentTypeSelector(language: language)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workspaceHeaderTitle)
                                .appTypography(.pageTitle)
                            if !workspaceHeaderDescription.isEmpty {
                                Text(workspaceHeaderDescription)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                    }

                    controlPanel(language: language)
                }
                .padding(16)
            }
        } detail: {
            if isShowingCVProfileEditor {
                CVProfileEditorDetailView(store: store)
                    .padding(16)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspaceKind == .cv ? previewSubtitle(language: language) : previewTitle(language: language))
                                .appTypography(.sectionTitle)
                                .foregroundStyle(AppPalette.appText)
                            if workspaceKind != .cv {
                                AppRecordSubtitleText(text: previewSubtitle(language: language))
                            }
                        }
                        Spacer()
                        outputFormatPicker(language: language)
                        Button(language.text("Export", "Exportera")) {
                            performExport()
                        }
                        .appSaveButtonStyle()
                        .disabled(!canExport)
                        Button(language.text("Open export folder", "Öppna exportmapp")) {
                            NSWorkspace.shared.open(store.exportDirectoryURL)
                        }
                        .buttonStyle(.bordered)
                    }

                    HTMLPreviewWebView(
                        html: livePreviewHTML,
                        scrollRequest: previewScrollRequest,
                        onOpenURL: handleCVPreviewSourceURL
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppPalette.border, lineWidth: 1)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppPalette.secondaryCardSurface)
                        )
                }
                .padding(16)
            }
        }
        .onAppear {
            handleCVProfileEditorRouteIfNeeded(store.route)
        }
        .onChange(of: store.route) { _, route in
            handleCVProfileEditorRouteIfNeeded(route)
        }
        .onChange(of: workspaceKind) { _, newValue in
            if newValue != .cv {
                cvWorkspacePanel = .documentSetup
            }
        }
        .onChange(of: cvConfiguration.publicationOptions) { _, _ in
            requestPreviewScrollToPublicationSection()
        }
    }

    @ViewBuilder
    private func controlPanel(language: AppLanguage) -> some View {
        if !isShowingCVProfileEditor {
            let documentSetupLabelWidth: CGFloat = 120
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if workspaceKind == .cv {
                        segmentedControl(
                            title: language.text("Style", "Stil"),
                            selection: $cvConfiguration.style,
                            options: [
                                (language.text("Own", "Egen"), .own),
                                ("LiU", .liu),
                                ("VR", .vetenskapsradet),
                            ],
                            labelWidth: documentSetupLabelWidth
                        )

                        segmentedControl(
                            title: language.text("Language", "Språk"),
                            selection: $cvConfiguration.exportLanguage,
                            options: [
                                (language.text("English", "Engelska"), .english),
                                (language.text("Swedish", "Svenska"), .swedish),
                            ],
                            labelWidth: documentSetupLabelWidth,
                            isDisabled: cvConfiguration.style == .vetenskapsradet
                        )
                    } else if workspaceKind == .annualReport {
                        Stepper(
                            "\(language.text("Year", "År")): \(annualReportYear)",
                            value: $annualReportYear,
                            in: 1990...2100
                        )

                        segmentedControl(
                            title: language.text("Language", "Språk"),
                            selection: $annualReportLanguage,
                            options: [
                                (language.text("English", "Engelska"), .english),
                                (language.text("Swedish", "Svenska"), .swedish),
                            ],
                            labelWidth: documentSetupLabelWidth
                        )

                        segmentedControl(
                            title: language.text("Grants", "Anslag"),
                            selection: $annualReportIncludeCoApplicantGrants,
                            options: [
                                (language.text("Mine", "Mina"), false),
                                (language.text("Mine + co-applicant", "Mina + medsökande"), true),
                            ],
                            labelWidth: documentSetupLabelWidth
                        )
                    } else if workspaceKind == .publications {
                        segmentedControl(
                            title: language.text("Template", "Mall"),
                            selection: $publicationTemplate,
                            options: [
                                ("AMA", .ama),
                                (language.text("Own template", "Egen mall"), .own),
                                ("Vetenskapsrådet", .vetenskapsradet),
                                ("Hjärt-Lungfonden", .heartLungfonden),
                            ],
                            labelWidth: documentSetupLabelWidth
                        )
                    }

                    if workspaceKind != .teachingMerits {
                        segmentedControl(
                            title: language.text("Current date", "Aktuellt datum"),
                            selection: $layoutOptions.currentDatePlacement,
                            options: [
                                (language.text("None", "Inget"), .none),
                                (language.text("Header", "Sidhuvud"), .header),
                                (language.text("Footer", "Sidfot"), .footer),
                            ],
                            labelWidth: documentSetupLabelWidth
                        )

                        Toggle(language.text("Show page numbers", "Visa sidnummer"), isOn: $layoutOptions.includePageNumbers)
                            .appCheckboxStyle()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            } label: {
                AppPanelHeadingText(text: language.text("Document setup", "Dokumentupplägg"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if workspaceKind == .cv, cvConfiguration.style != .vetenskapsradet {
                cvOptionsPanel(language: language)
            }

            if workspaceKind == .teachingMerits {
                teachingMeritsOptionsPanel(language: language)
            }

            if workspaceKind == .publications {
                switch publicationTemplate {
                case .own:
                    publicationOptionsPanel(language: language)
                case .heartLungfonden:
                    heartLungfondenPanel(language: language)
                case .ama, .vetenskapsradet:
                    EmptyView()
                }
            }

            if needsVROutputSelector {
                vrSelectionPanel(language: language)
            }
        }
    }

    private func documentTypeSelector(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AppPanelHeadingText(text: language.text("Documents", "Dokument"))

            ForEach(ExportWorkspaceKind.allCases) { kind in
                documentTypeNavigationButton(kind, language: language)
            }

            if workspaceKind == .cv {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CV")
                        .appTypography(.sectionTitle)
                        .foregroundStyle(AppPalette.appText)
                        .padding(.top, 6)

                    cvWorkspaceModeSelector(language: language)
                }
                .padding(.leading, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func documentTypeNavigationButton(
        _ kind: ExportWorkspaceKind,
        language: AppLanguage
    ) -> some View {
        let isSelected = workspaceKind == kind
        return Button {
            workspaceKind = kind
        } label: {
            HStack(spacing: 8) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                    .frame(width: 18, height: 18)
                Text(kind.title(language: language))
                    .font(appFont(.panelTitle).weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? AppPalette.mainMenuSelectionText : AppPalette.appText)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppPalette.mainMenuSelectionSurface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? AppPalette.mainMenuSelectionStroke : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(kind.title(language: language))
    }

    private func cvWorkspaceModeSelector(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cvWorkspaceModeButton(
                title: language.text("Create CV", "Skapa CV"),
                systemImage: "doc.badge.plus",
                isSelected: cvWorkspacePanel == .documentSetup
            ) {
                cvWorkspacePanel = .documentSetup
            }

            cvWorkspaceModeButton(
                title: language.text(
                    "Edit resume, education, and employment",
                    "Redigera resumé, utbildningar och anställningar"
                ),
                systemImage: "person.text.rectangle",
                isSelected: cvWorkspacePanel == .profileEditor
            ) {
                cvWorkspacePanel = .profileEditor
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cvWorkspaceModeButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(appFont(.body).weight(isSelected ? .semibold : .medium))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? AppPalette.mainMenuSelectionText : AppPalette.appText.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? AppPalette.mainMenuSelectionSurface.opacity(0.78) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func cvPreviewSourceLinksPanel(language: AppLanguage) -> some View {
        let sections = cvPreviewSourceLinkSections(language: language)
        return VStack(alignment: .leading, spacing: 10) {
            AppPanelHeadingText(text: language.text("Edit source records", "Redigera underlag"))

            if sections.allSatisfy({ $0.links.isEmpty }) {
                Text(language.text("No linked source records are included in this preview.", "Inga länkade underlag ingår i den här förhandsvisningen."))
                    .font(appFont(.secondary))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(sections.filter { !$0.links.isEmpty }) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                AppTableHeaderText(text: section.title)
                                ForEach(section.links) { link in
                                    cvPreviewSourceLinkButton(link)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppPalette.secondaryCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        )
    }

    private func cvPreviewSourceLinkButton(_ link: CVPreviewSourceLink) -> some View {
        Button {
            openCVPreviewSourceLink(link)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: link.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.linkAction)
                    .frame(width: 16, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title)
                        .appTypography(.tableHeader)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let subtitle = link.subtitle?.trimmedOrNil {
                        Text(subtitle)
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppPalette.fieldSurface)
            )
        }
        .buttonStyle(.plain)
    }

    private func openCVPreviewSourceLink(_ link: CVPreviewSourceLink) {
        switch link.destination {
        case .profileEditor:
            cvWorkspacePanel = .profileEditor
        case .route(let route):
            store.route = route
        }
    }

    private func handleCVProfileEditorRouteIfNeeded(_ route: AppRoute?) {
        guard let route,
              route.destination == .cv,
              route.recordID.hasPrefix("mediaAppearance:")
        else { return }
        workspaceKind = .cv
        cvWorkspacePanel = .profileEditor
        store.consumeRoute()
    }

    private func handleCVPreviewSourceURL(_ url: URL) {
        guard url.scheme == cvPreviewSourceLinkURLScheme else { return }
        let linkID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "id" })?
            .value
        guard
            let linkID,
            let link = cvPreviewSourceLink(forID: linkID, language: language)
        else { return }
        openCVPreviewSourceLink(link)
    }

    private func cvPreviewSourceLink(forID id: String, language: AppLanguage) -> CVPreviewSourceLink? {
        previewSourceLinkSections(language: language)
            .flatMap(\.links)
            .first { $0.id == id }
    }

    private func previewSourceLinksByItemKey(language: AppLanguage) -> [String: CVPreviewSourceLink] {
        let links = previewSourceLinkSections(language: language).flatMap(\.links)
        var linksByItemKey: [String: CVPreviewSourceLink] = [:]

        for link in links {
            let key = cvPreviewSourceItemKey(link.id)
            guard !key.isEmpty else { continue }
            linksByItemKey[key] = link
        }

        return linksByItemKey
    }

    private func previewSourceLinkSections(language: AppLanguage) -> [CVPreviewSourceLinkSection] {
        switch workspaceKind {
        case .cv:
            return cvPreviewSourceLinkSections(language: language)
        case .annualReport:
            return annualReportPreviewSourceLinkSections(year: annualReportYear, language: annualReportLanguage)
        case .publications:
            return publicationPreviewSourceLinkSections(language: language)
        case .teachingMerits:
            return []
        }
    }

    private func bestCVPreviewSourceLink(
        for text: String,
        links: [CVPreviewSourceLink],
        usedLinkIDs: Set<String>
    ) -> CVPreviewSourceLink? {
        links
            .filter { !usedLinkIDs.contains($0.id) }
            .compactMap { link -> (link: CVPreviewSourceLink, score: Int)? in
                let score = cvPreviewSourceMatchScore(text: text, link: link)
                return score > 0 ? (link, score) : nil
            }
            .max { $0.score < $1.score }?
            .link
    }

    private func cvPreviewSourceSectionIDs(title: String, layoutKind: String) -> [String] {
        let key = cvPreviewSourceSearchText([title, layoutKind].joined(separator: " "))
        var ids: [String] = []

        func append(_ id: String) {
            if !ids.contains(id) {
                ids.append(id)
            }
        }

        if key.contains("doctoral thesis") || key.contains("doktorsavhandling") {
            append("doctoral-thesis")
            append("other-publications")
            append("publications")
            return ids
        }
        if key.contains("grant") || key.contains("anslag") || key.contains("beviljade anslag") {
            append("grants")
        }
        if key.contains("review") || key.contains("sakkunnig") || key.contains("refereeuppdrag") {
            append("reviews")
        }
        if key.contains("conference") || key.contains("konferens") {
            append("conference")
        }
        if key.contains("association") || key.contains("foreningsmedlemskap") || key.contains("medlemskap") || key.contains("organisation") {
            append("organizations")
        }
        if key.contains("media") {
            append("media")
        }
        if key.contains("teaching") || key.contains("undervisning") || key.contains("handledning") || key.contains("pedagogiska") {
            append("teaching")
            append("doctoral")
        }
        if key.contains("doctoral") || key.contains("doktorand") || key.contains("forskarutbildning") {
            append("doctoral")
        }
        if key.contains("publication") || key.contains("publikation") || key.contains("article") || key.contains("artikel") || key.contains("manuscript") || key.contains("manuskript") {
            append("doctoral-thesis")
            append("publications")
            append("other-publications")
        }

        return ids
    }

    private func cvPreviewGrantMatchTerms(for application: GrantApplication, language: AppLanguage) -> [String] {
        let caseNumber = application.appliedCaseNumber ?? ""
        return [
            store.localizedGrantName(for: application, language: language),
            application.localizedGrantName(language: .swedish),
            application.localizedGrantName(language: .english),
            application.grantName,
            application.displayTitle,
            application.applicationTitle ?? "",
            application.organization,
            caseNumber,
            caseNumber.isEmpty ? "" : "(\(caseNumber))",
            application.appliedAmount ?? "",
            application.grantedAmount ?? "",
            application.approximateAmount ?? "",
            application.maxAmount ?? "",
            application.receivedProjectNumber ?? "",
            application.receivedDisplayName ?? "",
            cvPreviewYearString(from: application.grantedOn ?? application.appliedOn ?? "")
        ].compactMap(\.nonEmpty)
    }

    private func cvPreviewReviewMatchTerms(for review: CVReviewEntry) -> [String] {
        [
            review.displayTitle,
            review.listTitle,
            review.journalName,
            review.organizationName,
            review.programName,
            review.subjectTitle,
            review.personName,
            review.roleName,
            review.reference,
            review.date,
            cvPreviewYearString(from: review.date)
        ].compactMap(\.nonEmpty)
    }

    private func cvPreviewYearString(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return "" }
        let year = String(trimmed.prefix(4))
        return year.allSatisfy(\.isNumber) ? year : ""
    }

    private func cvPreviewTeachingMatchTerms(for assignment: TeachingAssignment, language: AppLanguage) -> [String] {
        let context = assignment.contextID.flatMap { contextID in
            store.teachingCourses.first { $0.id == contextID }
        }
        let roleTerms = assignment.roles.flatMap(cvPreviewTeachingRoleMatchTerms)
        let periodTerms = assignment.periods.flatMap { period in
            [
                period.from,
                period.to,
                cvPreviewYearString(from: period.from),
                cvPreviewYearString(from: period.to)
            ]
        }

        return ([
            assignment.activityName,
            assignment.activityTypeName,
            assignment.programName,
            assignment.studentName,
            assignment.comment,
            context?.localizedName(language: language) ?? "",
            context?.nameSv ?? "",
            context?.nameEn ?? "",
            context?.localizedProgram(language: language) ?? "",
            context?.programSv ?? "",
            context?.programEn ?? "",
            context?.termSv ?? "",
            context?.termEn ?? "",
            context?.courseCode ?? "",
            context?.institution ?? ""
        ] + roleTerms + periodTerms).compactMap(\.nonEmpty)
    }

    private func cvPreviewTeachingRoleMatchTerms(_ role: TeachingAssignmentRole) -> [String] {
        switch role {
        case .contributor:
            return ["Medarbetare", "Contributor", role.rawValue]
        case .facilitator:
            return ["Facilitator", role.rawValue]
        case .supervisor:
            return ["Handledare", "Supervisor", role.rawValue]
        case .examiner:
            return ["Examinator", "Examiner", role.rawValue]
        case .lecturer:
            return ["Föreläsare", "Lecturer", role.rawValue]
        case .invitedSpeaker:
            return ["Inbjuden talare", "Invited speaker", role.rawValue]
        case .seminarLeader:
            return ["Seminarieledare", "Seminar leader", role.rawValue]
        case .principalSupervisor:
            return ["Huvudhandledare", "Principal supervisor", role.rawValue]
        case .assistantSupervisor:
            return ["Bihandledare", "Co-supervisor", role.rawValue]
        case .opponent:
            return ["Opponent", role.rawValue]
        case .gradingCommittee:
            return ["Betygskommitté", "Grading committee", role.rawValue]
        default:
            return [role.rawValue]
        }
    }

    private func cvPreviewDoctoralCandidateMatchTerms(for candidate: DoctoralCandidateRecord) -> [String] {
        let supervisorTerms = candidate.supervisors.flatMap { supervisor in
            [supervisor.name, supervisor.from, supervisor.to, cvPreviewYearString(from: supervisor.from), cvPreviewYearString(from: supervisor.to)]
        }
        let periodTerms = candidate.supervisionPeriods.flatMap { period in
            [period.from, period.to, cvPreviewYearString(from: period.from), cvPreviewYearString(from: period.to)]
        }
        return ([
            candidate.candidateName,
            candidate.doctoralProjectName,
            candidate.institution,
            candidate.admissionDate,
            candidate.planningSeminarDate,
            candidate.halftimeDate,
            candidate.plannedDisputationDate,
            candidate.notes
        ] + supervisorTerms + periodTerms).compactMap(\.nonEmpty)
    }

    private func cvPreviewSourceLinkSections(language: AppLanguage) -> [CVPreviewSourceLinkSection] {
        guard let currentUser = store.currentUserAuthor() else { return [] }
        let currentAuthorID = currentUser.id
        let included = cvConfiguration.includedSections

        var sections: [CVPreviewSourceLinkSection] = [
            CVPreviewSourceLinkSection(
                id: "profile",
                title: language.text("Profile", "Profil"),
                links: [
                    CVPreviewSourceLink(
                        id: "profile-editor",
                        title: language.text("Resume, education, and employment", "Resumé, utbildningar och anställningar"),
                        subtitle: nil,
                        systemImage: "person.text.rectangle",
                        matchTerms: [
                            currentUser.localizedHomeAddress(language: language),
                            language.text("Personal resume", "Personlig resumé"),
                            language.text("Home address", "Hemadress")
                        ].compactMap(\.nonEmpty),
                        destination: .profileEditor
                    ),
                    CVPreviewSourceLink(
                        id: "author-\(currentUser.id)",
                        title: currentUser.displayName,
                        subtitle: language.text("Person card", "Personkort"),
                        systemImage: "person",
                        matchTerms: [
                            currentUser.name,
                            currentUser.firstName,
                            currentUser.lastName,
                            currentUser.primaryAffiliation?.email ?? "",
                            currentUser.primaryAffiliation?.localizedDepartment(language: language) ?? "",
                            currentUser.primaryAffiliation?.localizedOrganization(language: language) ?? "",
                            currentUser.primaryAffiliation?.city ?? "",
                            currentUser.primaryAffiliation?.country ?? "",
                            currentUser.phoneNumber,
                            currentUser.phoneNumberSecondary,
                            language.text("Work address", "Arbetsadress"),
                            "E-mail"
                        ].compactMap(\.nonEmpty),
                        destination: .route(AppRoute(recordID: currentUser.id, destination: .people))
                    )
                ]
            )
        ]

        if included.contains(.grants) {
            let grants = store.applications(forPersonID: currentAuthorID)
                .filter(\.isGranted)
                .filter { cvConfiguration.includeCollaboratorGrants || store.isCurrentUserFirstApplicant($0) }
                .sorted {
                    let leftDate = DateParsers.isoDay.date(from: $0.grantedOn ?? $0.appliedOn ?? "") ?? .distantPast
                    let rightDate = DateParsers.isoDay.date(from: $1.grantedOn ?? $1.appliedOn ?? "") ?? .distantPast
                    if leftDate != rightDate {
                        return leftDate > rightDate
                    }
                    return $0.grantName.localizedStandardCompare($1.grantName) == .orderedAscending
                }
            sections.append(
                CVPreviewSourceLinkSection(
                    id: "grants",
                    title: language.text("Grants", "Anslag"),
                    links: grants.map { application in
                        CVPreviewSourceLink(
                            id: "application-\(application.id)",
                            title: store.localizedGrantName(for: application, language: language).nonEmpty ?? application.displayTitle,
                            subtitle: store.funderName(for: application).nonEmpty,
                            systemImage: "doc.text",
                            matchTerms: cvPreviewGrantMatchTerms(for: application, language: language),
                            destination: .route(AppRoute(recordID: application.id, destination: .applications))
                        )
                    }
                )
            )
        }

        if cvIncludesPublicationLinks {
            sections.append(
                CVPreviewSourceLinkSection(
                    id: "publications",
                    title: language.text("Publications", "Publikationer"),
                    links: cvPreviewPublicationLinks(authorID: currentAuthorID, language: language)
                )
            )
        }

        if included.contains(.currentAssociationMemberships) {
            sections.append(
                CVPreviewSourceLinkSection(
                    id: "organizations",
                    title: language.text("Organizations", "Organisationer"),
                    links: store.organizations
                        .filter { $0.roles.contains(.association) }
                        .map { organization in
                            let title = language == .swedish ? organization.nameSv : (organization.nameEn.nonEmpty ?? organization.nameSv)
                            return CVPreviewSourceLink(
                                id: "organization-\(organization.id)",
                                title: title,
                                subtitle: organization.city.nonEmpty,
                                systemImage: "building.2",
                                matchTerms: [
                                    organization.nameSv,
                                    organization.nameEn,
                                    organization.city,
                                    organization.country,
                                    organization.websiteURL
                                ].compactMap(\.nonEmpty),
                                destination: .route(AppRoute(recordID: organization.id, destination: .organizations))
                            )
                        }
                )
            )
        }

        if included.contains(.doctoralThesis) {
            sections.append(
                CVPreviewSourceLinkSection(
                    id: "doctoral-thesis",
                    title: language.text("Doctoral thesis", "Doktorsavhandling"),
                    links: store.cvOtherPublications
                        .filter(\.isDoctoralThesis)
                        .map { entry in
                            CVPreviewSourceLink(
                                id: "other-publication-\(entry.id)",
                                title: entry.localizedTitle(language: language).nonEmpty ?? entry.displayTitle,
                                subtitle: entry.date.nonEmpty ?? entry.localizedOutlet(language: language).nonEmpty,
                                systemImage: "doc.richtext",
                                matchTerms: cvPreviewOtherPublicationMatchTerms(for: entry, language: language),
                                destination: .route(AppRoute(recordID: "otherPublication:\(entry.id)", destination: .cv))
                            )
                        }
                )
            )
        }

        if included.contains(.conferenceContributions) {
            sections.append(
                CVPreviewSourceLinkSection(
                    id: "conference",
                    title: language.text("Conference contributions", "Konferensbidrag"),
                    links: store.cvConferenceContributions.filter { !$0.isRejected }.map { contribution in
                        CVPreviewSourceLink(
                            id: "conference-\(contribution.id)",
                            title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                            subtitle: contribution.localizedMeeting(language: language).nonEmpty ?? contribution.publicationYear.nonEmpty,
                            systemImage: "person.3",
                            matchTerms: [
                                contribution.localizedName(language: language),
                                contribution.localizedTitle(language: language),
                                contribution.localizedMeeting(language: language),
                                contribution.localizedProjectName(language: language),
                                contribution.meetingCity,
                                contribution.meetingCountry,
                                contribution.publicationYear,
                                contribution.presentedBy
                            ].compactMap(\.nonEmpty),
                            destination: .route(AppRoute(recordID: "conferenceContribution:\(contribution.id)", destination: .cv))
                        )
                    }
                )
            )
        }

        if included.contains(.media) {
            sections.append(
                CVPreviewSourceLinkSection(
                    id: "media",
                    title: language.text("Media", "Media"),
                    links: store.cvMediaAppearances.filter(store.mediaAppearanceIncludesCurrentUser).map { appearance in
                        CVPreviewSourceLink(
                            id: "media-\(appearance.id)",
                            title: appearance.localizedTitle(language: language).nonEmpty ?? appearance.displayTitle,
                            subtitle: appearance.publicationDate.nonEmpty,
                            systemImage: "megaphone",
                            matchTerms: [
                                appearance.localizedDescription(language: language),
                                appearance.localizedTitle(language: language),
                                appearance.localizedLanguage(language: language),
                                appearance.publicationDate,
                                cvPreviewYearString(from: appearance.publicationDate),
                                appearance.link
                            ].compactMap(\.nonEmpty),
                            destination: .profileEditor
                        )
                    }
                )
            )
        }

        if included.contains(.reviews) {
            sections.append(
                CVPreviewSourceLinkSection(
                    id: "reviews",
                    title: language.text("Expert assignments", "Sakkunniguppdrag"),
                    links: store.cvReviewEntries.map { review in
                        CVPreviewSourceLink(
                            id: "review-\(review.id)",
                            title: review.displayTitle,
                            subtitle: review.date.nonEmpty,
                            systemImage: "checkmark.seal",
                            matchTerms: cvPreviewReviewMatchTerms(for: review),
                            destination: .route(AppRoute(recordID: "review:\(review.id)", destination: .expertAssignments))
                        )
                    }
                )
            )
        }

        if included.contains(.teaching) {
            sections.append(
                CVPreviewSourceLinkSection(
                    id: "teaching",
                    title: language.text("Teaching", "Undervisning"),
                    links: store.teachingAssignments.map { assignment in
                        CVPreviewSourceLink(
                            id: "teaching-\(assignment.id)",
                            title: assignment.activityName.nonEmpty ?? assignment.studentName.nonEmpty ?? language.text("Teaching assignment", "Undervisningspost"),
                            subtitle: assignment.programName.nonEmpty,
                            systemImage: "graduationcap",
                            matchTerms: cvPreviewTeachingMatchTerms(for: assignment, language: language),
                            destination: .route(AppRoute(recordID: assignment.id, destination: .teaching))
                        )
                    }
                )
            )
        }

        if included.contains(.doctoralThesis) || included.contains(.teaching) {
            sections.append(
                CVPreviewSourceLinkSection(
                    id: "doctoral",
                    title: language.text("Doctoral candidates", "Doktorander"),
                    links: store.doctoralCandidatesForCurrentUser().map { candidate in
                        CVPreviewSourceLink(
                            id: "doctoral-\(candidate.id)",
                            title: candidate.candidateName.nonEmpty ?? language.text("Doctoral candidate", "Doktorand"),
                            subtitle: candidate.doctoralProjectName.nonEmpty,
                            systemImage: "person.crop.rectangle.stack",
                            matchTerms: cvPreviewDoctoralCandidateMatchTerms(for: candidate),
                            destination: .route(AppRoute(recordID: candidate.id, destination: .doctoralCandidates))
                        )
                    }
                )
            )
        }

        if included.contains(.otherPublications) {
            sections.append(
                CVPreviewSourceLinkSection(
                    id: "other-publications",
                    title: language.text("Other publications", "Övriga publikationer"),
                    links: store.cvOtherPublications
                        .filter { !$0.isDoctoralThesis }
                        .map { entry in
                            CVPreviewSourceLink(
                                id: "other-publication-\(entry.id)",
                                title: entry.localizedTitle(language: language).nonEmpty ?? entry.displayTitle,
                                subtitle: entry.date.nonEmpty ?? entry.localizedOutlet(language: language).nonEmpty,
                                systemImage: "doc.richtext",
                                matchTerms: cvPreviewOtherPublicationMatchTerms(for: entry, language: language),
                                destination: .route(AppRoute(recordID: "otherPublication:\(entry.id)", destination: .cv))
                            )
                        }
                )
            )
        }

        return sections
    }

    private func annualReportPreviewSourceLinkSections(year: Int, language: AppLanguage) -> [CVPreviewSourceLinkSection] {
        let currentAuthorID = store.currentUserAuthor()?.id
        let grants = store.applications.filter { application in
            annualReportPreviewYearValue(application.statsYear) == year &&
                annualReportPreviewHasReportableGrantStatus(application) &&
                store.isCurrentUserAmong(ids: application.coApplicantAuthorIDs, names: application.coApplicants) &&
                (annualReportIncludeCoApplicantGrants || store.isCurrentUserFirstApplicant(application))
        }
        let publications = store.publications.filter { publication in
            store.isCurrentUserAmong(ids: publication.authorIDs, names: publication.authorNames)
        }
        let conferences = store.cvConferenceContributions.filter {
            $0.isCVReportable && annualReportPreviewYearValue($0.to.nonEmpty ?? $0.from) == year
        }
        let mediaAppearances = store.cvMediaAppearances.filter {
            annualReportPreviewYearValue($0.publicationDate) == year &&
                store.mediaAppearanceIncludesCurrentUser($0)
        }
        let reviews = store.cvReviewEntries.filter {
            annualReportPreviewYearValue($0.date) == year &&
                ($0.authorID?.trimmedOrNil == nil || $0.authorID == currentAuthorID)
        }

        return [
            CVPreviewSourceLinkSection(
                id: "grants",
                title: language.text("Grants", "Anslag"),
                links: grants.map { application in
                    CVPreviewSourceLink(
                        id: "application-\(application.id)",
                        title: store.localizedGrantName(for: application, language: language).nonEmpty ?? application.displayTitle,
                        subtitle: store.funderName(for: application).nonEmpty,
                        systemImage: "doc.text",
                        matchTerms: cvPreviewGrantMatchTerms(for: application, language: language),
                        destination: .route(AppRoute(recordID: application.id, destination: .applications))
                    )
                }
            ),
            CVPreviewSourceLinkSection(
                id: "publications",
                title: language.text("Publications", "Publikationer"),
                links: previewPublicationSourceLinks(publications, language: language)
            ),
            CVPreviewSourceLinkSection(
                id: "teaching",
                title: language.text("Teaching", "Undervisning"),
                links: store.teachingAssignments.map { assignment in
                    CVPreviewSourceLink(
                        id: "teaching-\(assignment.id)",
                        title: assignment.activityName.nonEmpty ?? assignment.studentName.nonEmpty ?? language.text("Teaching assignment", "Undervisningspost"),
                        subtitle: assignment.programName.nonEmpty,
                        systemImage: "graduationcap",
                        matchTerms: cvPreviewTeachingMatchTerms(for: assignment, language: language),
                        destination: .route(AppRoute(recordID: assignment.id, destination: .teaching))
                    )
                }
            ),
            CVPreviewSourceLinkSection(
                id: "doctoral",
                title: language.text("Doctoral candidates", "Doktorander"),
                links: store.doctoralCandidatesForCurrentUser().map { candidate in
                    CVPreviewSourceLink(
                        id: "doctoral-\(candidate.id)",
                        title: candidate.candidateName.nonEmpty ?? language.text("Doctoral candidate", "Doktorand"),
                        subtitle: candidate.doctoralProjectName.nonEmpty,
                        systemImage: "person.crop.rectangle.stack",
                        matchTerms: cvPreviewDoctoralCandidateMatchTerms(for: candidate),
                        destination: .route(AppRoute(recordID: candidate.id, destination: .doctoralCandidates))
                    )
                }
            ),
            CVPreviewSourceLinkSection(
                id: "conference",
                title: language.text("Conference contributions", "Konferensbidrag"),
                links: conferences.map { contribution in
                    CVPreviewSourceLink(
                        id: "conference-\(contribution.id)",
                        title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                        subtitle: contribution.localizedMeeting(language: language).nonEmpty ?? contribution.publicationYear.nonEmpty,
                        systemImage: "person.3",
                        matchTerms: [
                            contribution.localizedName(language: language),
                            contribution.localizedTitle(language: language),
                            contribution.localizedMeeting(language: language),
                            contribution.localizedProjectName(language: language),
                            contribution.meetingCity,
                            contribution.meetingCountry,
                            contribution.publicationYear,
                            contribution.presentedBy
                        ].compactMap(\.nonEmpty),
                        destination: .route(AppRoute(recordID: "conferenceContribution:\(contribution.id)", destination: .cv))
                    )
                }
            ),
            CVPreviewSourceLinkSection(
                id: "media",
                title: language.text("Media", "Media"),
                links: mediaAppearances.map { appearance in
                    CVPreviewSourceLink(
                        id: "media-\(appearance.id)",
                        title: appearance.localizedTitle(language: language).nonEmpty ?? appearance.displayTitle,
                        subtitle: appearance.publicationDate.nonEmpty,
                        systemImage: "megaphone",
                        matchTerms: [
                            appearance.localizedDescription(language: language),
                            appearance.localizedTitle(language: language),
                            appearance.localizedLanguage(language: language),
                            appearance.publicationDate,
                            cvPreviewYearString(from: appearance.publicationDate),
                            appearance.link
                        ].compactMap(\.nonEmpty),
                        destination: .route(AppRoute(recordID: "mediaAppearance:\(appearance.id)", destination: .cv))
                    )
                }
            ),
            CVPreviewSourceLinkSection(
                id: "reviews",
                title: language.text("Expert assignments", "Sakkunniguppdrag"),
                links: reviews.map { review in
                    CVPreviewSourceLink(
                        id: "review-\(review.id)",
                        title: review.displayTitle,
                        subtitle: review.date.nonEmpty,
                        systemImage: "checkmark.seal",
                        matchTerms: cvPreviewReviewMatchTerms(for: review),
                        destination: .route(AppRoute(recordID: "review:\(review.id)", destination: .expertAssignments))
                    )
                }
            ),
        ]
    }

    private func publicationPreviewSourceLinkSections(language: AppLanguage) -> [CVPreviewSourceLinkSection] {
        [
            CVPreviewSourceLinkSection(
                id: "publications",
                title: language.text("Publications", "Publikationer"),
                links: previewPublicationSourceLinks(store.publicationRecords, language: language)
            )
        ]
    }

    private var cvIncludesPublicationLinks: Bool {
        let publicationSections: Set<CVExportSectionKey> = [
            .originalArticles,
            .reviewArticles,
            .protocolArticles,
            .manuscriptsInWriting,
            .submittedManuscripts,
            .acceptedManuscripts
        ]
        return !cvConfiguration.includedSections.isDisjoint(with: publicationSections)
            || cvConfiguration.style == .vetenskapsradet
    }

    private func cvPreviewPublicationLinks(authorID: String, language: AppLanguage) -> [CVPreviewSourceLink] {
        let publications: [PublicationRecord]
        if cvConfiguration.style == .vetenskapsradet {
            publications = store.publications(forAuthorID: authorID)
        } else {
            publications = store.publications(forAuthorID: authorID)
        }
        return previewPublicationSourceLinks(publications, language: language)
    }

    private func previewPublicationSourceLinks(_ publications: [PublicationRecord], language: AppLanguage) -> [CVPreviewSourceLink] {
        var seenIDs = Set<String>()
        return publications.compactMap { publication in
            guard seenIDs.insert(publication.id).inserted else { return nil }
            return CVPreviewSourceLink(
                id: "publication-\(publication.id)",
                title: publication.title.nonEmpty ?? language.text("Untitled publication", "Namnlös publikation"),
                subtitle: [publication.journal.nonEmpty, publication.year.nonEmpty].compactMap { $0 }.joined(separator: " · ").nonEmpty,
                systemImage: "text.book.closed",
                matchTerms: [
                    publication.title,
                    publication.journal,
                    publication.year,
                    publication.doi,
                    publication.pmid
                ].compactMap(\.nonEmpty),
                destination: .route(AppRoute(recordID: publication.id, destination: .publications))
            )
        }
    }

    private func annualReportPreviewHasReportableGrantStatus(_ application: GrantApplication) -> Bool {
        switch application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Väntar svar", "Beviljat", "Avslag":
            return true
        default:
            return false
        }
    }

    private func annualReportPreviewYearValue(_ raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let value = Int(raw) {
            return value
        }
        if let date = DateParsers.isoDay.date(from: raw) {
            return Calendar.current.component(.year, from: date)
        }
        return nil
    }

    private func cvPreviewOtherPublicationMatchTerms(for entry: CVOtherPublicationEntry, language: AppLanguage) -> [String] {
        let otherLanguage: AppLanguage = language == .swedish ? .english : .swedish
        return [
            entry.localizedCategory(language: language),
            entry.localizedCategory(language: otherLanguage),
            entry.categorySv,
            entry.categoryEn,
            entry.localizedTitle(language: language),
            entry.localizedTitle(language: otherLanguage),
            entry.titleSv,
            entry.titleEn,
            entry.localizedOutlet(language: language),
            entry.localizedOutlet(language: otherLanguage),
            entry.outletSv,
            entry.outletEn,
            entry.localizedPublicationData(language: language),
            entry.localizedPublicationData(language: otherLanguage),
            entry.publicationDataSv,
            entry.publicationDataEn,
            entry.authors,
            entry.publisherShortName,
            entry.city,
            entry.doi,
            entry.localizedLanguage(language: language),
            entry.localizedLanguage(language: otherLanguage),
            entry.languageSv,
            entry.languageEn,
            entry.mainSupervisor,
            entry.coSupervisor,
            entry.date,
            cvPreviewYearString(from: entry.date)
        ].compactMap(\.nonEmpty)
    }

    private func cvOtherPublicationBelongsToCurrentUser(
        _ entry: CVOtherPublicationEntry,
        currentUser: PublicationAuthor
    ) -> Bool {
        let userNames = currentUser.presentedNameCandidates.map { $0.lowercased() }.filter { !$0.isEmpty }
        let searchable = [
            entry.authors,
            entry.mainSupervisor,
            entry.coSupervisor
        ]
        .joined(separator: " ")
        .lowercased()
        return userNames.contains { searchable.contains($0) }
    }

    private var needsVROutputSelector: Bool {
        (workspaceKind == .cv && cvConfiguration.style == .vetenskapsradet)
            || (workspaceKind == .publications && publicationTemplate == .vetenskapsradet)
    }

    @ViewBuilder
    private func cvOptionsPanel(language: AppLanguage) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                segmentedControl(
                    title: language.text("Chronological order", "Kronologisk ordning"),
                    selection: $cvConfiguration.publicationOptions.sortOrder,
                    options: [
                        (language.text("Newest first", "Senast först"), .newestFirst),
                        (language.text("Oldest first", "Äldst först"), .oldestFirst),
                    ]
                )

                segmentedControl(
                    title: language.text("Journal names", "Tidskriftsnamn"),
                    selection: $cvConfiguration.publicationOptions.journalNameMode,
                    options: [
                        (language.text("Abbreviated", "Förkortade"), .abbreviated),
                        (language.text("Full", "Hela"), .full),
                    ]
                )

                if cvConfiguration.publicationOptions.journalNameMode == .abbreviated {
                    segmentedControl(
                        title: language.text("Short name source", "Kortnamnskälla"),
                        selection: $cvConfiguration.publicationOptions.journalShortNameStyle,
                        options: [
                            ("NLM", .nlm),
                            ("ISSN LTWA", .issnLTWA),
                        ]
                    )
                }

                Stepper(
                    "\(language.text("Author names before et al", "Författarnamn före et al")): \(cvConfiguration.publicationOptions.authorCountBeforeEtAl)",
                    value: $cvConfiguration.publicationOptions.authorCountBeforeEtAl,
                    in: 1...20
                )

                Toggle(
                    language.text("Always show my name", "Visa alltid mitt namn"),
                    isOn: $cvConfiguration.publicationOptions.alwaysShowOwnName
                )
                .appCheckboxStyle()

                Toggle(language.text("Include PMID", "Inkludera PMID"), isOn: $cvConfiguration.publicationOptions.includePMID)
                    .appCheckboxStyle()
                Toggle(language.text("Include DOI", "Inkludera DOI"), isOn: $cvConfiguration.publicationOptions.includeDOI)
                    .appCheckboxStyle()
                Toggle(language.text("Include Epub date", "Inkludera Epub-datum"), isOn: $cvConfiguration.publicationOptions.includeEpubDate)
                    .appCheckboxStyle()
                Toggle(language.text("Include publication date", "Inkludera publikationsdatum"), isOn: $cvConfiguration.publicationOptions.includePublicationDate)
                    .appCheckboxStyle()

                JournalMetricsSourceRow(options: $cvConfiguration.publicationOptions, language: language)

                PublicationMetricYearOptionRow(
                    title: language.text("Include Clarivate JIF (SCIE/ESCI)", "Inkludera Clarivate JIF (SCIE/ESCI)"),
                    isOn: $cvConfiguration.publicationOptions.includeClarivateSCIEJIF,
                    yearMode: $cvConfiguration.publicationOptions.impactFactorYearMode,
                    language: language
                )
                PublicationMetricYearOptionRow(
                    title: language.text("Include quartile", "Inkludera kvartil"),
                    isOn: $cvConfiguration.publicationOptions.includeQuartile,
                    yearMode: $cvConfiguration.publicationOptions.quartileYearMode,
                    language: language
                )
                PublicationMetricYearOptionRow(
                    title: language.text("Include Norwegian list", "Inkludera norska listan"),
                    isOn: $cvConfiguration.publicationOptions.includeNorwegianList,
                    yearMode: $cvConfiguration.publicationOptions.norwegianListYearMode,
                    language: language
                )
                Toggle(language.text("Include citations", "Inkludera citations"), isOn: $cvConfiguration.publicationOptions.includeCitations)
                    .appCheckboxStyle()

                Toggle(language.text("Bold my name", "Fetmarkera mitt namn"), isOn: $cvConfiguration.publicationOptions.boldOwnName)
                    .appCheckboxStyle()
                Toggle(language.text("Underline doctoral thesis main supervisor", "Stryk under huvudhandledare i doktorsavhandling"), isOn: $cvConfiguration.underlineDoctoralMainSupervisor)
                    .appCheckboxStyle()
                Toggle(language.text("Underline doctoral thesis co-supervisor", "Stryk under bihandledare i doktorsavhandling"), isOn: $cvConfiguration.underlineDoctoralCoSupervisor)
                    .appCheckboxStyle()

                Divider()

                AppPanelHeadingText(text: language.text("Sections", "Innehåll"))

                ForEach(CVExportSectionKey.allCases) { key in
                    cvSectionToggleRow(for: key, language: language)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            AppPanelHeadingText(text: language.text("CV content", "CV-innehåll"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cvSectionToggleRow(for key: CVExportSectionKey, language: AppLanguage) -> some View {
        if key == .grants {
            HStack(alignment: .center, spacing: 12) {
                Toggle(cvSectionLabel(for: key, language: language), isOn: cvSectionBinding(for: key))
                    .appCheckboxStyle()
                if cvConfiguration.includedSections.contains(.grants) {
                    Picker(language.text("Grants in CV", "Anslag i CV"), selection: $cvConfiguration.includeCollaboratorGrants) {
                        Text(language.text("Mine", "Mina")).tag(false)
                        Text(language.text("Mine + co-applicant", "Mina + medsökande")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                }
                Spacer(minLength: 0)
            }
        } else {
            Toggle(cvSectionLabel(for: key, language: language), isOn: cvSectionBinding(for: key))
                .appCheckboxStyle()
        }
    }

    @ViewBuilder
    private func publicationOptionsPanel(language: AppLanguage) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                segmentedControl(
                    title: language.text("Chronological order", "Kronologisk ordning"),
                    selection: $publicationConfiguration.options.sortOrder,
                    options: [
                        (language.text("Newest first", "Senast först"), .newestFirst),
                        (language.text("Oldest first", "Äldst först"), .oldestFirst),
                    ]
                )

                segmentedControl(
                    title: language.text("Journal names", "Tidskriftsnamn"),
                    selection: $publicationConfiguration.options.journalNameMode,
                    options: [
                        (language.text("Abbreviated", "Förkortade"), .abbreviated),
                        (language.text("Full", "Hela"), .full),
                    ]
                )

                if publicationConfiguration.options.journalNameMode == .abbreviated {
                    segmentedControl(
                        title: language.text("Short name source", "Kortnamnskälla"),
                        selection: $publicationConfiguration.options.journalShortNameStyle,
                        options: [
                            ("NLM", .nlm),
                            ("ISSN LTWA", .issnLTWA),
                        ]
                    )
                }

                Stepper(
                    "\(language.text("Author names before et al", "Författarnamn före et al")): \(publicationConfiguration.options.authorCountBeforeEtAl)",
                    value: $publicationConfiguration.options.authorCountBeforeEtAl,
                    in: 1...20
                )

                Toggle(
                    language.text("Always show my name", "Visa alltid mitt namn"),
                    isOn: $publicationConfiguration.options.alwaysShowOwnName
                )
                .appCheckboxStyle()

                Toggle(language.text("Include PMID", "Inkludera PMID"), isOn: $publicationConfiguration.options.includePMID)
                    .appCheckboxStyle()
                Toggle(language.text("Include DOI", "Inkludera DOI"), isOn: $publicationConfiguration.options.includeDOI)
                    .appCheckboxStyle()
                Toggle(language.text("Include Epub date", "Inkludera Epub-datum"), isOn: $publicationConfiguration.options.includeEpubDate)
                    .appCheckboxStyle()
                Toggle(language.text("Include publication date", "Inkludera publikationsdatum"), isOn: $publicationConfiguration.options.includePublicationDate)
                    .appCheckboxStyle()

                JournalMetricsSourceRow(options: $publicationConfiguration.options, language: language)

                PublicationMetricYearOptionRow(
                    title: language.text("Include Clarivate JIF (SCIE/ESCI)", "Inkludera Clarivate JIF (SCIE/ESCI)"),
                    isOn: $publicationConfiguration.options.includeClarivateSCIEJIF,
                    yearMode: $publicationConfiguration.options.impactFactorYearMode,
                    language: language
                )
                PublicationMetricYearOptionRow(
                    title: language.text("Include quartile", "Inkludera kvartil"),
                    isOn: $publicationConfiguration.options.includeQuartile,
                    yearMode: $publicationConfiguration.options.quartileYearMode,
                    language: language
                )
                PublicationMetricYearOptionRow(
                    title: language.text("Include Norwegian list", "Inkludera norska listan"),
                    isOn: $publicationConfiguration.options.includeNorwegianList,
                    yearMode: $publicationConfiguration.options.norwegianListYearMode,
                    language: language
                )
                Toggle(language.text("Include citations", "Inkludera citations"), isOn: $publicationConfiguration.options.includeCitations)
                    .appCheckboxStyle()

                Toggle(language.text("Bold my name", "Fetmarkera mitt namn"), isOn: $publicationConfiguration.options.boldOwnName)
                    .appCheckboxStyle()
                Toggle(language.text("Underline doctoral thesis main supervisor", "Stryk under huvudhandledare i doktorsavhandling"), isOn: $publicationConfiguration.underlineDoctoralMainSupervisor)
                    .appCheckboxStyle()
                Toggle(language.text("Underline doctoral thesis co-supervisor", "Stryk under bihandledare i doktorsavhandling"), isOn: $publicationConfiguration.underlineDoctoralCoSupervisor)
                    .appCheckboxStyle()

                Divider()

                AppPanelHeadingText(text: language.text("Sections", "Innehåll"))

                ForEach(PublicationExportSectionKey.allCases) { key in
                    Toggle(publicationSectionLabel(for: key, language: language), isOn: publicationSectionBinding(for: key))
                        .appCheckboxStyle()
                }
            }
            .padding(8)
        } label: {
            AppPanelHeadingText(text: language.text("Publication content", "Publikationsinnehåll"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func heartLungfondenPanel(language: AppLanguage) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Stepper(
                    language.text(
                        "Years in the period: \(heartLungfondenConfiguration.baseYearWindow)",
                        "Antal år i perioden: \(heartLungfondenConfiguration.baseYearWindow)"
                    ),
                    value: $heartLungfondenConfiguration.baseYearWindow,
                    in: PublicationHeartLungfondenExportConfiguration.baseYearWindowRange
                )

                Toggle(
                    language.text(
                        "Add one year for compensable time (\(heartLungfondenConfiguration.baseYearWindow + 1) years)",
                        "Lägg till ett år vid avräkningsbar tid (\(heartLungfondenConfiguration.baseYearWindow + 1) år)"
                    ),
                    isOn: $heartLungfondenConfiguration.includeCompensableTime
                )
                .appCheckboxStyle()

                segmentedControl(
                    title: language.text("Chronological order", "Kronologisk ordning"),
                    selection: $heartLungfondenConfiguration.sortOrder,
                    options: [
                        (language.text("Newest first", "Senast först"), .newestFirst),
                        (language.text("Oldest first", "Äldst först"), .oldestFirst),
                    ]
                )

                HStack {
                    Text(language.text("Period", "Period"))
                    Spacer()
                    Text(store.heartLungfondenDateRangeDescription(configuration: heartLungfondenConfiguration))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        } label: {
            AppPanelHeadingText(text: "Hjärt-Lungfonden")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func vrSelectionPanel(language: AppLanguage) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    language.text(
                        "Choose 1-10 original articles and write a short note for each selected output.",
                        "Välj 1-10 originalartiklar och skriv en kort kommentar för varje vald output."
                    )
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                AppSidebarSearchField(
                    placeholder: language.text("Filter original articles", "Filtrera originalartiklar"),
                    text: $vrSearchText
                )

                HStack(alignment: .center, spacing: 12) {
                    Text(language.text("Min IF", "Min IF"))
                        .appTypography(.fieldLabel)
                        .foregroundStyle(AppPalette.appText)
                    TextField("0", text: $vrMinimumImpactFactorText)
                        .appTextInputChrome(fillsWidth: false)
                        .frame(width: 70)
                    Toggle(language.text("Norwegian 1", "Norska 1"), isOn: $vrIncludeNorwegianLevel1)
                        .appCheckboxStyle()
                    Toggle(language.text("Norwegian 2", "Norska 2"), isOn: $vrIncludeNorwegianLevel2)
                        .appCheckboxStyle()
                    Spacer(minLength: 0)
                }

                Text(
                    language.text(
                        "\(vrSelectedCandidateIDs.count) of \(maxSelectedOutputs) selected",
                        "\(vrSelectedCandidateIDs.count) av \(maxSelectedOutputs) valda"
                    )
                )
                .appTypography(.tableHeader)

                ForEach(filteredVRCandidates) { candidate in
                    let isSelected = vrSelectedCandidateIDs.contains(candidate.id)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: vrSelectionBinding(for: candidate)) {
                            VStack(alignment: .leading, spacing: 4) {
                                AppMetadataText(text: candidate.authorsText)
                                    .lineLimit(2)
                                AppCompactRowTitleText(text: candidate.title, lineLimit: 3)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                AppMetadataText(text: candidate.journalText)
                                    .italic()
                                    .lineLimit(1)
                                if let rankingSummary = candidate.rankingSummary(language: language) {
                                    AppMetadataText(text: rankingSummary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading)
                        }
                        .appCheckboxStyle()

                        if isSelected {
                            VStack(alignment: .leading, spacing: 6) {
                                AppTextEditorField(
                                    title: language.text("Comment for the selected output", "Kommentar för vald output"),
                                    text: vrNoteBinding(for: candidate),
                                    minimumHeight: 72,
                                    maximumHeight: 92
                                )
                            }
                            .padding(.leading, 28)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppPalette.secondaryCardSurface)
                    )
                }

                if filteredVRCandidates.isEmpty {
                    Text(language.text("No original articles matched the filters.", "Inga originalartiklar matchade filtren."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
            .padding(8)
        } label: {
            AppPanelHeadingText(text: "Vetenskapsrådet")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parsedImpactFactorFilter(_ raw: String) -> Double {
        Double(
            raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
        ) ?? 0
    }

    private func previewTitle(language: AppLanguage) -> String {
        switch previewDocument {
        case .cv(let document):
            return document.title
        case .teachingMerits(let document):
            return document.title
        case .publications(let document):
            return document.title
        case .publicationTemplate(let document):
            return document.title
        case nil:
            return language.text("Preview", "Förhandsvisning")
        }
    }

    private func previewSubtitle(language: AppLanguage) -> String {
        let formatText = outputFormat == .word ? "Word" : "PDF"
        return language.text(
            "Live preview of the current export setup (\(formatText)).",
            "Liveförhandsvisning av aktuell exportuppsättning (\(formatText))."
        )
    }

    private func requestPreviewScrollToPublicationSection() {
        guard workspaceKind == .cv else { return }
        previewScrollRequest = HTMLPreviewScrollRequest(targetHeadings: cvPublicationPreviewTargetHeadings())
    }

    private func requestPreviewScrollToCVSection(_ key: CVExportSectionKey) {
        guard workspaceKind == .cv else { return }
        previewScrollRequest = HTMLPreviewScrollRequest(targetHeadings: cvPreviewTargetHeadings(for: key))
    }

    private func cvPublicationPreviewTargetHeadings() -> [String] {
        [
            "Original articles",
            "Originalartiklar",
            "Originalartiklar (Original articles)",
            "3.3 Publikationslista",
            "3.3.1 Vetenskapliga publikationer i vetenskapliga tidskrifter",
            cvSectionLabel(for: .originalArticles, language: language),
            cvSectionLabel(for: .reviewArticles, language: language),
            cvSectionLabel(for: .protocolArticles, language: language),
            cvSectionLabel(for: .manuscriptsInWriting, language: language),
            cvSectionLabel(for: .submittedManuscripts, language: language),
            cvSectionLabel(for: .acceptedManuscripts, language: language),
            cvSectionLabel(for: .otherPublications, language: language),
        ]
    }

    private func cvPreviewTargetHeadings(for key: CVExportSectionKey) -> [String] {
        var headings = [cvSectionLabel(for: key, language: language)]
        switch key {
        case .contactDetails:
            headings += ["Contact details", "Kontaktuppgifter", "1.0 Personuppgifter", "1.1 Namn"]
        case .personalResume:
            headings += ["Personal resume", "Personlig resumé"]
        case .doctoralThesis:
            headings += ["Doctoral thesis", "Doktorsavhandling", "3.3.2 Övriga publikationer"]
        case .degreesAndLicenses:
            headings += ["Degrees and licenses", "Examina och legitimationer", "2.0 Examina", "2.1 Högskoleexamina"]
        case .courses:
            headings += ["Courses", "Kurser"]
        case .currentPositions:
            headings += ["Current positions", "Nuvarande anställningar", "1.5 Nuvarande anställning"]
        case .pastPositions:
            headings += [
                "Past positions (selected)",
                "Tidigare anställningar (urval)",
                "1.6 Tidigare anställningar",
                "1.7 Vistelse som gästforskare"
            ]
        case .teaching:
            headings += [
                "Supervision and teaching activities",
                "Handledning och undervisning",
                "4.0 Pedagogiska meriter",
                "4.1 Beskrivning av egen pedagogisk verksamhet"
            ]
        case .grants:
            headings += ["Grants", "Anslag", "3.4 Beviljade anslag"]
        case .originalArticles:
            headings += cvPublicationPreviewTargetHeadings()
        case .reviewArticles:
            headings += ["Review articles", "Översiktsartiklar", "3.3 Publikationslista", "3.3.1 Vetenskapliga publikationer"]
        case .protocolArticles:
            headings += ["Protocol articles", "Protokollartiklar", "3.3 Publikationslista", "3.3.1 Vetenskapliga publikationer"]
        case .manuscriptsInWriting:
            headings += ["Manuscripts in writing", "Manuskript under skrivande", "3.3 Publikationslista"]
        case .submittedManuscripts:
            headings += ["Submitted manuscripts", "Inskickade manuskript", "3.3 Publikationslista"]
        case .acceptedManuscripts:
            headings += ["Accepted manuscripts", "Accepterade manuskript", "3.3 Publikationslista"]
        case .otherPublications:
            headings += ["Other publications", "Övriga publikationer", "3.3.2 Övriga publikationer"]
        case .conferenceContributions:
            headings += ["Conference contributions", "Konferensbidrag", "3.5 Aktivt deltagande i konferenser"]
        case .media:
            headings += ["Media", "3.6 Övrig vetenskaplig meritering"]
        case .reviews:
            headings += ["Reviews", "Sakkunniguppdrag", "3.5.4 Refereeuppdrag för tidskrifter"]
        case .currentAssociationMemberships:
            headings += ["Current association memberships", "Aktuella föreningsmedlemskap"]
        }
        var seen = Set<String>()
        return headings.compactMap(\.nonEmpty).filter { seen.insert($0).inserted }
    }

    private func cvSectionBinding(for key: CVExportSectionKey) -> Binding<Bool> {
        Binding(
            get: { cvConfiguration.includedSections.contains(key) },
            set: { isOn in
                let wasIncluded = cvConfiguration.includedSections.contains(key)
                if isOn {
                    cvConfiguration.includedSections.insert(key)
                    if !wasIncluded {
                        requestPreviewScrollToCVSection(key)
                    }
                } else {
                    cvConfiguration.includedSections.remove(key)
                }
            }
        )
    }

    private func publicationSectionBinding(for key: PublicationExportSectionKey) -> Binding<Bool> {
        Binding(
            get: { publicationConfiguration.includedSections.contains(key) },
            set: { isOn in
                if isOn {
                    publicationConfiguration.includedSections.insert(key)
                } else {
                    publicationConfiguration.includedSections.remove(key)
                }
            }
        )
    }

    private func vrSelectionBinding(for candidate: CVVROutputCandidate) -> Binding<Bool> {
        Binding(
            get: { vrSelectedCandidateIDs.contains(candidate.id) },
            set: { isOn in
                if isOn {
                    guard vrSelectedCandidateIDs.count < maxSelectedOutputs || vrSelectedCandidateIDs.contains(candidate.id) else { return }
                    vrSelectedCandidateIDs.insert(candidate.id)
                    if vrNotesByCandidateID[candidate.id] == nil, !candidate.noteSuggestion.isEmpty {
                        vrNotesByCandidateID[candidate.id] = candidate.noteSuggestion
                    }
                } else {
                    vrSelectedCandidateIDs.remove(candidate.id)
                }
            }
        )
    }

    private func vrNoteBinding(for candidate: CVVROutputCandidate) -> Binding<String> {
        Binding(
            get: { vrNotesByCandidateID[candidate.id, default: candidate.noteSuggestion] },
            set: { vrNotesByCandidateID[candidate.id] = $0 }
        )
    }

    private func cvSectionLabel(for key: CVExportSectionKey, language: AppLanguage) -> String {
        switch key {
        case .contactDetails: return language.text("Contact details", "Kontaktuppgifter")
        case .personalResume: return language.text("Personal resume", "Personlig resumé")
        case .doctoralThesis: return language.text("Doctoral thesis", "Doktorsavhandling")
        case .degreesAndLicenses: return language.text("Degrees and licenses", "Examina och legitimationer")
        case .courses: return language.text("Courses", "Kurser")
        case .currentPositions: return language.text("Current positions", "Nuvarande anställningar")
        case .pastPositions: return language.text("Past positions", "Tidigare anställningar")
        case .teaching: return language.text("Teaching", "Undervisning")
        case .grants: return language.text("Grants", "Anslag")
        case .originalArticles: return language.text("Original articles", "Originalartiklar")
        case .reviewArticles: return language.text("Review articles", "Översiktsartiklar")
        case .protocolArticles: return language.text("Protocol articles", "Protokollartiklar")
        case .manuscriptsInWriting: return language.text("Manuscripts in writing", "Manuskript under skrivande")
        case .submittedManuscripts: return language.text("Submitted manuscripts", "Inskickade manuskript")
        case .acceptedManuscripts: return language.text("Accepted manuscripts", "Accepterade manuskript")
        case .otherPublications: return language.text("Other publications", "Övriga publikationer")
        case .conferenceContributions: return language.text("Conference contributions", "Konferensbidrag")
        case .media: return language.text("Media", "Media")
        case .reviews: return language.text("Reviews", "Sakkunniguppdrag")
        case .currentAssociationMemberships: return language.text("Current association memberships", "Aktuella föreningsmedlemskap")
        }
    }

    private func publicationSectionLabel(for key: PublicationExportSectionKey, language: AppLanguage) -> String {
        switch key {
        case .publishedOriginalArticles:
            return language.text("Published original articles", "Publicerade originalartiklar")
        case .publishedReviewArticles:
            return language.text("Published review articles", "Publicerade översiktsartiklar")
        case .publishedProtocolArticles:
            return language.text("Published protocol articles", "Publicerade protokollartiklar")
        case .publishedNonPeerReviewedPublications:
            return language.text("Other publications, non-peer-reviewed", "Övriga publikationer, ej expertgranskade")
        case .articlesInReview:
            return language.text("Articles in review", "Artiklar under granskning")
        case .articlesInWriting:
            return language.text("Articles in writing", "Artiklar under arbete")
        }
    }

    private func performExport() {
        guard canExport else { return }
        let destinationURL = exportDestinationURL()

        switch outputFormat {
        case .word:
            performWordExport(to: destinationURL)
        case .pdf:
            pdfExporter.export(html: exportHTML, to: destinationURL) { result in
                switch result {
                case .success(let url):
                    store.notice = StoreNotice(
                        message: language.text("Exported PDF to \(url.lastPathComponent).", "Exporterade PDF till \(url.lastPathComponent)."),
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

    private func performWordExport(to destinationURL: URL) {
        switch workspaceKind {
        case .cv:
            if cvConfiguration.style == .vetenskapsradet {
                store.exportVetenskapsradetCVDocumentAsync(
                    selectedOutputs: selectedVROutputs,
                    layout: layoutOptions,
                    to: destinationURL
                )
                return
            }
            store.exportCustomCVDocumentAsync(
                configuration: cvConfiguration,
                layout: layoutOptions,
                to: destinationURL
            )
            return
        case .annualReport:
            store.exportAnnualReportDocumentAsync(
                year: annualReportYear,
                exportLanguage: annualReportLanguage,
                includeCoApplicantGrants: annualReportIncludeCoApplicantGrants,
                layout: layoutOptions,
                to: destinationURL
            )
            return
        case .teachingMerits:
            store.exportTeachingMeritsDocumentAsync(
                document: filteredTeachingMeritsDocument(forExport: true),
                to: destinationURL
            )
            return
        case .publications:
            switch publicationTemplate {
            case .ama:
                store.exportPublicationsCustomDocumentAsync(
                    configuration: PublicationCustomExportConfiguration(),
                    layout: layoutOptions,
                    to: destinationURL
                )
                return
            case .own:
                store.exportPublicationsCustomDocumentAsync(
                    configuration: publicationConfiguration,
                    layout: layoutOptions,
                    to: destinationURL
                )
                return
            case .vetenskapsradet:
                store.exportVetenskapsradetCVDocumentAsync(
                    selectedOutputs: selectedVROutputs,
                    layout: layoutOptions,
                    to: destinationURL
                )
                return
            case .heartLungfonden:
                store.exportPublicationsHeartLungfondenDocumentAsync(
                    configuration: heartLungfondenConfiguration,
                    to: destinationURL,
                    layout: layoutOptions
                )
                return
            }
        }
    }

    private func exportDestinationURL() -> URL {
        let fileExtension = outputFormat == .word ? "docx" : "pdf"
        let fileName: String
        switch workspaceKind {
        case .cv:
            let style = cvConfiguration.style == .vetenskapsradet ? CVDocumentExportStyle.vetenskapsradet : cvConfiguration.style
            let exportLanguage = cvConfiguration.exportLanguage
            fileName = preferredCVExportFileName(for: style, exportLanguage: exportLanguage, fileExtension: fileExtension)
        case .annualReport:
            let authorName = sanitizedFileName(store.currentUserAuthor()?.name.nonEmpty ?? language.text("CV profile", "CV-profil"))
            fileName = "\(language.text("Annual report", "Årsrapport")) \(annualReportYear) \(authorName) \(timestampString()).\(fileExtension)"
        case .teachingMerits:
            fileName = "\(language.text("Teaching merits", "Pedagogiska meriter")) \(timestampString()).\(fileExtension)"
        case .publications:
            let timestamp = timestampString()
            switch publicationTemplate {
            case .ama:
                fileName = "AMA \(timestamp).\(fileExtension)"
            case .own:
                fileName = "\(language.text("Publications list custom", "Publikationslista skräddarsydd")) \(timestamp).\(fileExtension)"
            case .vetenskapsradet:
                fileName = "Vetenskapsradet publications \(timestamp).\(fileExtension)"
            case .heartLungfonden:
                fileName = "Publikationsförteckning Hjärt-Lungfonden \(store.heartLungfondenDateRangeDescription(configuration: heartLungfondenConfiguration)) \(timestamp).\(fileExtension)"
            }
        }
        return store.exportDirectoryURL.appendingPathComponent(sanitizedFileName(fileName))
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return formatter.string(from: Date())
    }

    private func sanitizedFileName(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let pieces = raw.components(separatedBy: forbidden)
        return pieces.joined(separator: " ").replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preferredCVExportFileName(
        for style: CVDocumentExportStyle,
        exportLanguage: AppLanguage,
        fileExtension: String
    ) -> String {
        let authorName = sanitizedFileName(
            store.currentUserAuthor()?.name.nonEmpty ?? language.text("CV", "CV")
        )
        let languageSuffix = exportLanguage == .swedish ? "svenska" : "English"
        let stem: String = {
            switch style {
            case .vetenskapsradet:
                return "Vetenskapsrådet CV \(authorName)"
            case .liu, .own:
                return "CV \(authorName) (\(languageSuffix))"
            }
        }()
        return "\(stem) \(timestampString()).\(fileExtension)"
    }

    @ViewBuilder
    private func teachingMeritsOptionsPanel(language: AppLanguage) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(TeachingMeritsSectionKey.allCases) { key in
                    Toggle(teachingMeritsSectionLabel(for: key, language: language), isOn: teachingMeritsSectionBinding(for: key))
                        .appCheckboxStyle()
                }
            }
            .padding(8)
        } label: {
            AppPanelHeadingText(text: language.text("Teaching merits content", "Innehåll för pedagogiska meriter"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func teachingMeritsSectionBinding(for key: TeachingMeritsSectionKey) -> Binding<Bool> {
        Binding(
            get: { teachingMeritsConfiguration.includedSections.contains(key) },
            set: { isOn in
                if isOn {
                    teachingMeritsConfiguration.includedSections.insert(key)
                } else {
                    teachingMeritsConfiguration.includedSections.remove(key)
                }
            }
        )
    }

    private func teachingMeritsSectionLabel(for key: TeachingMeritsSectionKey, language: AppLanguage) -> String {
        switch key {
        case .summary:
            return language.text("Summary", "Summering")
        case .groupTeaching:
            return language.text("Group teaching", "Gruppundervisning")
        case .supervision:
            return language.text("Supervision", "Handledning")
        case .courseAdministration:
            return language.text("Course administration", "Kursadministration")
        }
    }

    /// The preview and the exported file show the same doctoral supervision
    /// hours (summed from the hours per term on the supervision periods).
    private func filteredTeachingMeritsDocument(forExport: Bool = false) -> TeachingMeritsExportDocument {
        let source = forExport ? store.teachingMeritsExportDocument() : store.teachingMeritsPreviewDocument()
        let included = teachingMeritsConfiguration.includedSections
        let groups = source.groups.filter { group in
            switch group.title {
            case "Gruppundervisning":
                return included.contains(.groupTeaching)
            case "Handledning":
                return included.contains(.supervision)
            case "Kursadministration":
                return included.contains(.courseAdministration)
            default:
                return false
            }
        }
        let summaryRows = included.contains(.summary) ? source.summaryRows : []
        return TeachingMeritsExportDocument(
            title: source.title,
            groups: groups,
            summaryHeaders: source.summaryHeaders,
            summaryRows: summaryRows,
            facultyName: source.facultyName
        )
    }
}

private struct CVProfileEditorDetailView: View {
    @ObservedObject var store: GrantDataStore

    private var language: AppLanguage { store.language }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    AppPanelHeadingText(text: language.text("Edit resume, education, and employment", "Redigera resumé, utbildningar och anställningar"))
                    AppRecordSubtitleText(text: language.text("Changes save automatically.", "Ändringar sparas automatiskt."))
                }

                if store.currentUserAuthor() != nil {
                    CVProfileAuthorDataEditor(store: store) {
                        CVProfileResumeEditor(store: store)
                    }
                    CVProfileDoctoralThesisEditor(store: store)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        AppPanelHeadingText(text: language.text("No personal profile is selected yet.", "Ingen personlig profil är vald ännu."))
                        AppRecordSubtitleText(text: language.text("Choose a CV profile under Preferences > CV exports to edit the CV source here.", "Välj CV-profil under Inställningar > CV-exporter för att redigera CV-underlaget här."))
                    }
                    .appCardChrome(fill: AppPalette.secondaryCardSurface, stroke: AppPalette.subtleBorder)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CVProfileAuthorDataEditor: View {
    @ObservedObject var store: GrantDataStore

    @State private var draft: PublicationAuthor?
    @State private var autosaveTask: DispatchWorkItem?
    private let insertedContent: AnyView

    init(
        store: GrantDataStore,
        @ViewBuilder insertedContent: () -> some View = { EmptyView() }
    ) {
        self.store = store
        _draft = State(initialValue: store.currentUserAuthor())
        self.insertedContent = AnyView(insertedContent())
    }

    private var language: AppLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let draft {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        CVProfileFieldBlock(title: language.text("Home address", "Hemadress")) {
                            TextField(language.text("Home address", "Hemadress"), text: homeAddressBinding)
                                .appTextInputChrome()
                        }

                        CVProfileFieldBlock(title: language.text("Date of birth", "Födelsedatum"), width: 180) {
                            AppDateField(
                                placeholder: language.datePlaceholder,
                                text: birthDateBinding,
                                width: 180,
                                language: language
                            )
                        }
                    }
                    .padding(8)
                } label: {
                    AppPanelHeadingText(text: language.text("Personal details", "Personuppgifter"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                insertedContent

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        if draft.employments.isEmpty {
                            Text(language.text("No employments added yet.", "Inga anställningar tillagda ännu."))
                                .foregroundStyle(.secondary)
                        } else {
                            employmentHeaderRow
                            ForEach(draft.employments) { employment in
                                if let binding = employmentBinding(for: employment.id) {
                                    CVProfileEmploymentRow(
                                        employment: binding,
                                        language: language,
                                        organizations: store.organizations,
                                        onDelete: { deleteEmployment(id: employment.id) }
                                    )
                                }
                            }
                        }

                        Button(language.text("Add employment", "Lägg till anställning")) {
                            guard var snapshot = self.draft else { return }
                            snapshot.employments.append(PublicationAuthorEmployment())
                            self.draft = snapshot
                        }
                        .appAddButtonStyle()
                    }
                    .padding(8)
                } label: {
                    AppPanelHeadingText(text: language.text("Employments", "Anställningar"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        if draft.educationEntries.isEmpty {
                            Text(language.text("No education or courses added yet.", "Inga utbildningar eller kurser tillagda ännu."))
                                .foregroundStyle(.secondary)
                        } else {
                            educationHeaderRow
                            ForEach(draft.educationEntries) { entry in
                                if let binding = educationBinding(for: entry.id) {
                                    CVProfileEducationRow(
                                        entry: binding,
                                        language: language,
                                        organizations: store.organizations,
                                        onDelete: { deleteEducation(id: entry.id) }
                                    )
                                }
                            }
                        }

                        Button(language.text("Add education or course", "Lägg till utbildning eller kurs")) {
                            guard var snapshot = self.draft else { return }
                            snapshot.educationEntries.append(PublicationAuthorEducation())
                            self.draft = snapshot
                        }
                        .appAddButtonStyle()
                    }
                    .padding(8)
                } label: {
                    AppPanelHeadingText(text: language.text("Education and courses", "Utbildningar och kurser"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            refreshFromStore(force: true)
        }
        .onChange(of: store.publicationAuthors) { _, _ in
            refreshFromStore(force: false)
        }
        .onChange(of: draft) { oldValue, newValue in
            guard oldValue != newValue, let newValue else { return }
            scheduleAutosave(for: newValue)
        }
        .onDisappear {
            persistAutosaveIfNeeded()
        }
    }

    private var homeAddressBinding: Binding<String> {
        Binding(
            get: { draft?.localizedHomeAddress(language: language) ?? "" },
            set: { value in
                guard var snapshot = draft else { return }
                snapshot.setLocalizedHomeAddress(value, language: language)
                draft = snapshot
            }
        )
    }

    private var birthDateBinding: Binding<String> {
        Binding(
            get: { draft?.birthDate ?? "" },
            set: { value in
                guard var snapshot = draft else { return }
                snapshot.birthDate = value
                draft = snapshot
            }
        )
    }

    private var employmentHeaderRow: some View {
        HStack(alignment: .center, spacing: 12) {
            CVProfileColumnHeader(title: language.text("From", "Från"), width: 120)
            CVProfileColumnHeader(title: language.text("To", "Till"), width: 120)
            CVProfileColumnHeader(title: language.text("Title", "Titel"), width: 220)
            CVProfileColumnHeader(title: language.text("Organization", "Organisation"), width: 250)
            CVProfileColumnHeader(title: language.text("Unit", "Enhet"), width: 180)
            CVProfileColumnHeader(title: language.text("Department", "Avdelning"))
            Color.clear.frame(width: 28)
        }
    }

    private var educationHeaderRow: some View {
        HStack(alignment: .center, spacing: 12) {
            CVProfileColumnHeader(title: language.text("From", "Från"), width: 120)
            CVProfileColumnHeader(title: language.text("To", "Till"), width: 120)
            CVProfileColumnHeader(title: language.text("Degree / course", "Utbildning / kurs"), width: 260)
            CVProfileColumnHeader(title: language.text("Organization", "Organisation"), width: 250)
            CVProfileColumnHeader(title: language.text("Unit", "Enhet"), width: 180)
            CVProfileColumnHeader(title: language.text("Level", "Nivå"), width: 190)
            Color.clear.frame(width: 28)
        }
    }

    private func employmentBinding(for employmentID: String) -> Binding<PublicationAuthorEmployment>? {
        guard draft?.employments.contains(where: { $0.id == employmentID }) == true else { return nil }
        return Binding(
            get: {
                draft?.employments.first(where: { $0.id == employmentID }) ?? PublicationAuthorEmployment(id: employmentID)
            },
            set: { updated in
                guard var snapshot = draft,
                      let index = snapshot.employments.firstIndex(where: { $0.id == employmentID }) else { return }
                snapshot.employments[index] = updated
                draft = snapshot
            }
        )
    }

    private func educationBinding(for entryID: String) -> Binding<PublicationAuthorEducation>? {
        guard draft?.educationEntries.contains(where: { $0.id == entryID }) == true else { return nil }
        return Binding(
            get: {
                draft?.educationEntries.first(where: { $0.id == entryID }) ?? PublicationAuthorEducation(id: entryID)
            },
            set: { updated in
                guard var snapshot = draft,
                      let index = snapshot.educationEntries.firstIndex(where: { $0.id == entryID }) else { return }
                snapshot.educationEntries[index] = updated
                draft = snapshot
            }
        )
    }

    private func deleteEmployment(id: String) {
        guard var snapshot = draft else { return }
        snapshot.employments.removeAll { $0.id == id }
        draft = snapshot
    }

    private func deleteEducation(id: String) {
        guard var snapshot = draft else { return }
        snapshot.educationEntries.removeAll { $0.id == id }
        draft = snapshot
    }

    private func refreshFromStore(force: Bool) {
        let current = store.currentUserAuthor()
        if force || current != draft {
            draft = current
        }
    }

    private func scheduleAutosave(for snapshot: PublicationAuthor) {
        autosaveTask?.cancel()
        let persistedName = store.currentUserAuthor()?.name ?? snapshot.name
        let task = DispatchWorkItem {
            store.autosavePublicationAuthor(snapshot, previousName: persistedName)
        }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func persistAutosaveIfNeeded() {
        autosaveTask?.cancel()
        guard let snapshot = draft,
              snapshot != store.currentUserAuthor() else { return }
        store.autosavePublicationAuthor(snapshot, previousName: store.currentUserAuthor()?.name ?? snapshot.name)
        autosaveTask = nil
    }
}


private struct CVProfileDoctoralThesisEditor: View {
    @ObservedObject var store: GrantDataStore

    @State private var draft: CVOtherPublicationEntry
    @State private var autosaveTask: DispatchWorkItem?

    init(store: GrantDataStore) {
        self.store = store
        _draft = State(initialValue: Self.initialDraft(from: store))
    }

    private var language: AppLanguage { store.language }
    private var currentUserName: String? { store.currentUserAuthor()?.name.nonEmpty }
    private var researcherOptions: [String] {
        store.coauthors
            .map(\.name)
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    CVProfileFieldBlock(title: language.text("Year", "År"), width: 120) {
                        AppYearField(text: binding(\.date), language: language, width: 120)
                    }

                    CVProfileFieldBlock(title: language.text("Language", "Språk"), width: 180) {
                        TextField(language.text("Language", "Språk"), text: localizedLanguageBinding)
                            .appTextInputChrome()
                    }

                    CVProfileFieldBlock(title: "DOI") {
                        AppIdentifierField(kind: .doi, text: binding(\.doi), language: language)
                    }

                    if let doiURL = draft.doiURL {
                        Link("DOI", destination: doiURL)
                            .font(appFont(.secondary).weight(.semibold))
                            .foregroundStyle(AppPalette.linkAction)
                            .padding(.top, 24)
                    }
                }

                CVProfileFieldBlock(title: language.text("Title", "Titel")) {
                    TextField(language == .swedish ? "Titel (svenska)" : "Title (English)", text: localizedTitleBinding)
                        .appTextInputChrome()
                }

                HStack(alignment: .top, spacing: 12) {
                    CVProfileFieldBlock(title: language.text("Publisher / series", "Förlag / serie")) {
                        TextField(language == .swedish ? "Publikation / outlet (svenska)" : "Publication / outlet (English)", text: localizedOutletBinding)
                            .appTextInputChrome()
                    }

                    CVProfileFieldBlock(title: language.text("Short name", "Kortnamn"), width: 180) {
                        TextField(language.text("Short name", "Kortnamn"), text: binding(\.publisherShortName))
                            .appTextInputChrome()
                    }

                    CVProfileFieldBlock(title: language.text("City", "Stad"), width: 180) {
                        TextField(language.text("City", "Stad"), text: binding(\.city))
                            .appTextInputChrome()
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    CVProfileFieldBlock(title: language.text("Main supervisor", "Huvudhandledare")) {
                        AutocompleteSelectionField(
                            text: binding(\.mainSupervisor),
                            options: researcherOptions,
                            placeholder: language.text("Main supervisor", "Huvudhandledare"),
                            addNewTitle: language.text("Add new", "Lägg till ny"),
                            display: { $0 },
                            onCommit: {}
                        )
                    }

                    CVProfileFieldBlock(title: language.text("Co-supervisor", "Bihandledare")) {
                        AutocompleteSelectionField(
                            text: binding(\.coSupervisor),
                            options: researcherOptions,
                            placeholder: language.text("Co-supervisor", "Bihandledare"),
                            addNewTitle: language.text("Add new", "Lägg till ny"),
                            display: { $0 },
                            onCommit: {}
                        )
                    }
                }
            }
            .padding(8)
        } label: {
            AppPanelHeadingText(text: language.text("Doctoral thesis", "Doktorsavhandling"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            refreshFromStore()
        }
        .onChange(of: store.cvOtherPublications) { _, _ in
            refreshFromStore()
        }
        .onChange(of: draft) { oldValue, newValue in
            guard oldValue != newValue else { return }
            scheduleAutosave(for: newValue)
        }
        .onDisappear {
            persistAutosaveIfNeeded()
        }
    }

    private static func initialDraft(from store: GrantDataStore) -> CVOtherPublicationEntry {
        store.cvOtherPublications.first(where: \.isDoctoralThesis)
            ?? CVOtherPublicationEntry(category: "Doktorsavhandling")
    }

    private var localizedTitleBinding: Binding<String> {
        Binding(
            get: { draft.localizedTitle(language: language) },
            set: { draft.setLocalizedTitle($0, language: language) }
        )
    }

    private var localizedOutletBinding: Binding<String> {
        Binding(
            get: { draft.localizedOutlet(language: language) },
            set: { draft.setLocalizedOutlet($0, language: language) }
        )
    }

    private var localizedLanguageBinding: Binding<String> {
        Binding(
            get: { draft.localizedLanguage(language: language) },
            set: { draft.setLocalizedLanguage($0, language: language) }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<CVOtherPublicationEntry, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func refreshFromStore() {
        guard let thesis = store.cvOtherPublications.first(where: \.isDoctoralThesis) else { return }
        if thesis != draft {
            draft = thesis
        }
    }

    private func scheduleAutosave(for entry: CVOtherPublicationEntry) {
        autosaveTask?.cancel()
        var snapshot = entry
        snapshot.categorySv = "Doktorsavhandling"
        snapshot.categoryEn = "Doctoral thesis"
        if let currentUserName {
            snapshot.authors = currentUserName
        }
        let task = DispatchWorkItem {
            store.autosaveCVOtherPublication(snapshot)
        }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func persistAutosaveIfNeeded() {
        autosaveTask?.cancel()
        var snapshot = draft
        snapshot.categorySv = "Doktorsavhandling"
        snapshot.categoryEn = "Doctoral thesis"
        if let currentUserName {
            snapshot.authors = currentUserName
        }
        let current = store.cvOtherPublications.first(where: \.isDoctoralThesis)
        guard current != snapshot else { return }
        store.autosaveCVOtherPublication(snapshot)
        autosaveTask = nil
    }
}

private struct CVProfileResumeEditor: View {
    @ObservedObject var store: GrantDataStore

    @State private var draft: CVPersonalResume
    @State private var autosaveTask: DispatchWorkItem?
    @StateObject private var editorController = CVRichTextEditorController()

    init(store: GrantDataStore) {
        self.store = store
        _draft = State(initialValue: store.cvPersonalResume)
    }

    private var language: AppLanguage { store.language }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    CVRichTextFormatButton(title: "B") { editorController.toggleBold() }
                    CVRichTextFormatButton(title: "I") { editorController.toggleItalic() }
                    CVRichTextFormatButton(title: "U") { editorController.toggleUnderline() }
                    Spacer()
                    Text(language == .swedish ? "Svensk version" : "English version")
                        .font(appFont(.secondary))
                        .foregroundStyle(.secondary)
                }

                CVRichTextEditorRepresentable(
                    document: localizedDocumentBinding,
                    controller: editorController
                )
                .frame(minHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppPalette.fieldSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppPalette.subtleBorder, lineWidth: 1)
                )
            }
            .padding(8)
        } label: {
            AppPanelHeadingText(text: language.text("Personal resume", "Personlig resumé"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: store.cvPersonalResume) { _, newValue in
            draft = newValue
        }
        .onDisappear {
            persistAutosaveIfNeeded()
        }
    }

    private var localizedDocumentBinding: Binding<CVRichTextDocument> {
        Binding(
            get: { draft.localizedContent(language: language) },
            set: { newValue in
                draft.setLocalizedContent(newValue, language: language)
                scheduleAutosave()
            }
        )
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let snapshot = draft
        let task = DispatchWorkItem {
            store.autosaveCVPersonalResume(snapshot)
        }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }

    private func persistAutosaveIfNeeded() {
        autosaveTask?.cancel()
        guard draft != store.cvPersonalResume else { return }
        store.autosaveCVPersonalResume(draft)
        autosaveTask = nil
    }
}

private struct CVProfileEmploymentRow: View {
    @Binding var employment: PublicationAuthorEmployment
    let language: AppLanguage
    let organizations: [OrganizationRecord]
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CVProfileRowField(width: 120) {
                AppDateField(placeholder: language.datePlaceholder, text: $employment.from, width: 120, language: language)
            }

            CVProfileRowField(width: 120) {
                AppDateField(placeholder: language.datePlaceholder, text: $employment.to, width: 120, language: language)
            }

            CVProfileRowField(width: 220) {
                TextField(language.text("Title", "Titel"), text: localizedTitleBinding)
                    .appTextInputChrome()
            }

            CVProfileRowField(width: 250) {
                TextField(language.text("Organization", "Organisation"), text: localizedOrganizationBinding)
                    .appTextInputChrome()
            }

            CVProfileRowField(width: 180) {
                OrganizationUnitPickerMenu(
                    organization: treeOrganization,
                    unitID: employment.unitID,
                    language: language,
                    width: 180
                ) { unit in
                    selectUnit(unit)
                }
            }

            CVProfileRowField {
                TextField(language.text("Department", "Avdelning"), text: localizedDepartmentBinding)
                    .appTextInputChrome()
            }

            AppIconDeleteButton(title: language.text("Delete", "Ta bort"), action: onDelete)
            .padding(.top, 6)
        }
    }

    private var localizedTitleBinding: Binding<String> {
        Binding(
            get: { employment.localizedTitle(language: language) },
            set: { employment.setLocalizedTitle($0, language: language) }
        )
    }

    private var localizedOrganizationBinding: Binding<String> {
        Binding(
            get: { employment.localizedOrganization(language: language) },
            set: { newValue in
                let previousText = employment.localizedOrganization(language: language)
                var updated = employment
                updated.setLocalizedOrganization(newValue, language: language)
                // F21: another organization means another tree; the unit is
                // kept only when it belongs to the new organization.
                let linked = OrganizationTree.relinkedIDs(
                    organizationID: updated.organizationID,
                    unitID: updated.unitID,
                    previousOrganizationText: previousText,
                    newOrganizationText: newValue,
                    organizations: organizations
                )
                updated.organizationID = linked.organizationID
                updated.unitID = linked.unitID
                employment = updated
            }
        )
    }

    /// F21: the organization whose units the unit picker lists.
    private var treeOrganization: OrganizationRecord? {
        OrganizationTree.rowOrganization(
            organizationID: employment.organizationID,
            organizationTexts: [employment.organizationSv, employment.organizationEn],
            organizations: organizations
        )
    }

    /// F21: points the employment to a unit and writes the unit's name as
    /// the department text; "no unit" keeps the text as it is.
    private func selectUnit(_ unit: OrganizationUnit?) {
        guard let organization = treeOrganization else { return }
        var updated = employment
        updated.organizationID = organization.id
        updated.unitID = unit?.id
        if let unit {
            updated.departmentSv = unit.nameSv.nonEmpty ?? unit.nameEn
            updated.departmentEn = unit.nameEn.nonEmpty ?? unit.nameSv
        }
        employment = updated
    }

    private var localizedDepartmentBinding: Binding<String> {
        Binding(
            get: { employment.localizedDepartment(language: language) },
            set: { employment.setLocalizedDepartment($0, language: language) }
        )
    }
}

private struct CVProfileEducationRow: View {
    @Binding var entry: PublicationAuthorEducation
    let language: AppLanguage
    let organizations: [OrganizationRecord]
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CVProfileRowField(width: 120) {
                AppDateField(placeholder: language.datePlaceholder, text: $entry.from, width: 120, language: language)
            }

            CVProfileRowField(width: 120) {
                AppDateField(placeholder: language.datePlaceholder, text: $entry.to, width: 120, language: language)
            }

            CVProfileRowField(width: 260) {
                TextField(language.text("Degree / course", "Utbildning / kurs"), text: localizedDegreeBinding)
                    .appTextInputChrome()
            }

            CVProfileRowField(width: 250) {
                TextField(language.text("Organization", "Organisation"), text: localizedOrganizationBinding)
                    .appTextInputChrome()
            }

            CVProfileRowField(width: 180) {
                OrganizationUnitPickerMenu(
                    organization: treeOrganization,
                    unitID: entry.unitID,
                    language: language,
                    width: 180
                ) { unit in
                    selectUnit(unit)
                }
            }

            CVProfileRowField(width: 190) {
                AppMenuSelectionField(
                    selection: $entry.level,
                    options: [("—", Optional<PublicationAuthorEducationLevel>.none)]
                        + PublicationAuthorEducationLevel.allCases.map { ($0.displayName(language: language), Optional($0)) }
                )
            }

            AppIconDeleteButton(title: language.text("Delete", "Ta bort"), action: onDelete)
            .padding(.top, 6)
        }
    }

    private var localizedDegreeBinding: Binding<String> {
        Binding(
            get: { entry.localizedDegree(language: language) },
            set: { entry.setLocalizedDegree($0, language: language) }
        )
    }

    private var localizedOrganizationBinding: Binding<String> {
        Binding(
            get: { entry.localizedOrganization(language: language) },
            set: { newValue in
                let previousText = entry.localizedOrganization(language: language)
                var updated = entry
                updated.setLocalizedOrganization(newValue, language: language)
                // F21: another organization means another tree; the unit is
                // kept only when it belongs to the new organization.
                let linked = OrganizationTree.relinkedIDs(
                    organizationID: updated.organizationID,
                    unitID: updated.unitID,
                    previousOrganizationText: previousText,
                    newOrganizationText: newValue,
                    organizations: organizations
                )
                updated.organizationID = linked.organizationID
                updated.unitID = linked.unitID
                entry = updated
            }
        )
    }

    /// F21: the organization whose units the unit picker lists.
    private var treeOrganization: OrganizationRecord? {
        OrganizationTree.rowOrganization(
            organizationID: entry.organizationID,
            organizationTexts: [entry.organizationSv, entry.organizationEn],
            organizations: organizations
        )
    }

    /// F21: points the education entry to a unit (education rows have no
    /// department text to fill in).
    private func selectUnit(_ unit: OrganizationUnit?) {
        guard let organization = treeOrganization else { return }
        var updated = entry
        updated.organizationID = organization.id
        updated.unitID = unit?.id
        entry = updated
    }
}


private struct CVProfileColumnHeader: View {
    let title: String
    var width: CGFloat? = nil

    var body: some View {
        AppTableHeaderText(text: title)
            .frame(width: width, alignment: .leading)
    }
}

private struct CVProfileRowField<Content: View>: View {
    var width: CGFloat? = nil
    let content: Content

    init(width: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: width, alignment: .leading)
    }
}

private struct CVProfileFieldBlock<Content: View>: View {
    let title: String
    var width: CGFloat? = nil
    let content: Content

    init(title: String, width: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.width = width
        self.content = content()
    }

    var body: some View {
        AppCompactField(title, width: width) {
            content
        }
    }
}

private extension PublicationAuthorEducationLevel {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .basicEducation:
            return language.text("Basic education", "Grundutbildning")
        case .standaloneCourse:
            return language.text("Course", "Kurs")
        case .bachelor:
            return language.text("Bachelor", "Kandidat")
        case .master:
            return language.text("Master", "Master")
        case .doctoral:
            return language.text("Doctoral education", "Forskarutbildning")
        case .other:
            return language.text("Other", "Övrigt")
        }
    }
}

private func cvPreviewSourceItemKey(_ text: String) -> String {
    cvPreviewSourceSearchText(text)
}

private func cvPreviewSourceSearchText(_ text: String) -> String {
    text
        .replacingOccurrences(of: #"[\[\]\(\),.;:/"'’`´]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func cvPreviewSectionUsesProfileEditor(_ title: String) -> Bool {
    let key = cvPreviewSourceSearchText(title)
    let fragments = [
        "personal resume",
        "personlig resume",
        "degrees and licenses",
        "examina och legitimationer",
        "hogskoleexamina",
        "courses",
        "kurser",
        "current positions",
        "nuvarande anstallningar",
        "nuvarande anstallning",
        "past positions",
        "tidigare anstallningar",
        "tidigare anstallning",
        "vistelse som gastforskare"
    ]
    return fragments.contains { key.contains($0) }
}

private func cvPreviewSectionUsesPersonCard(_ title: String) -> Bool {
    let key = cvPreviewSourceSearchText(title)
    let fragments = [
        "contact details",
        "kontaktuppgifter",
        "personuppgifter",
        "namn",
        "personnummer",
        "bostadsadress",
        "adress och telefonnummer",
        "epostadress"
    ]
    return fragments.contains { key.contains($0) }
}

private func cvPreviewSourceMatchScore(text: String, link: CVPreviewSourceLink) -> Int {
    let itemText = cvPreviewSourceSearchText(text)
    guard !itemText.isEmpty else { return 0 }

    let phrases = [(link.title, 1_000)]
        + link.matchTerms.map { ($0, 900) }
        + [(link.subtitle ?? "", 650)]
    return phrases.reduce(0) { best, phrase in
        let candidate = cvPreviewSourceSearchText(phrase.0)
        guard candidate.count >= 4 else { return best }
        if itemText.contains(candidate) {
            return max(best, phrase.1 + candidate.count)
        }
        if candidate.contains(itemText), itemText.count >= 12 {
            return max(best, phrase.1 + itemText.count)
        }
        return best
    }
}

private func previewEmptyHTML(
    title: String,
    message: String,
    appearance: ExportPreviewAppearance = .standard
) -> String {
    """
    <html>
    <head>\(exportPreviewCSS(typography: .timesDocument, appearance: appearance))</head>
    <body>
      <div class="preview-shell">
        <div class="paper paper-empty">
          <div class="empty-state">
            <h1>\(title.htmlEscaped)</h1>
            <p>\(message.htmlEscaped)</p>
          </div>
        </div>
      </div>
    </body>
    </html>
    """
}

/// Internal entry point for previewing a `CVExportDocument` outside this
/// file (the project document panel); the full-parameter overload below
/// stays private because its parameter types are.
func htmlPreview(for document: CVExportDocument) -> String {
    htmlPreview(for: document, appearance: .standard)
}

private func htmlPreview(
    for document: CVExportDocument,
    appearance: ExportPreviewAppearance = .standard,
    sourceLinksByItemKey: [String: CVPreviewSourceLink] = [:],
    sourceLinkActionTitle: String = "Edit"
) -> String {
    if document.style == CVDocumentExportStyle.liu.rawValue {
        return htmlPreviewForLiUDocument(
            document,
            appearance: appearance,
            sourceLinksByItemKey: sourceLinksByItemKey,
            sourceLinkActionTitle: sourceLinkActionTitle
        )
    }

    let summaryHTML = document.summaryLines.map { "<p class=\"summary-line\">\($0.htmlEscaped)</p>" }.joined()
    let richSummary = document.summaryRichParagraphs.map(cvRichParagraphHTML).joined()
    let sectionsHTML = document.sections.map {
        cvSectionHTML(
            $0,
            highlightName: document.highlightName,
            underlinedNames: [],
            sourceLinksByItemKey: sourceLinksByItemKey,
            sourceLinkActionTitle: sourceLinkActionTitle
        )
    }.joined()
    let titleRowHTML: String
    if document.titleTrailingText.isEmpty {
        titleRowHTML = "<h1>\(document.title.htmlEscaped)</h1>"
    } else {
        titleRowHTML = """
        <div class="hero-title-row">
          <h1>\(document.title.htmlEscaped)</h1>
          <span class="hero-trailing">\(document.titleTrailingText.htmlEscaped)</span>
        </div>
        """
    }
    let bodyHTML = """
    <div class="hero">
      \(titleRowHTML)
      \(document.subtitle.isEmpty ? "" : "<p class=\"subtitle\">\(document.subtitle.htmlEscaped)</p>")
    </div>
    \(summaryHTML)\(richSummary)\(sectionsHTML)
    """
    return exportHTMLDocument(
        title: document.title,
        subtitle: document.subtitle,
        headerText: document.headerText,
        footerText: document.footerText,
        includePageNumbers: document.includePageNumbers,
        typography: .forCVStyle(document.style),
        appearance: appearance,
        showsSourceLinks: !sourceLinksByItemKey.isEmpty,
        body: document.compactTables ? "<div class=\"compact-tables\">\(bodyHTML)</div>" : bodyHTML
    )
}

private func htmlPreviewForLiUDocument(
    _ document: CVExportDocument,
    appearance: ExportPreviewAppearance,
    sourceLinksByItemKey: [String: CVPreviewSourceLink] = [:],
    sourceLinkActionTitle: String = "Edit"
) -> String {
    let sectionsHTML = document.sections.map {
        liuCVSectionHTML(
            $0,
            sourceLinksByItemKey: sourceLinksByItemKey,
            sourceLinkActionTitle: sourceLinkActionTitle
        )
    }.joined()
    return exportHTMLDocument(
        title: document.title,
        subtitle: "",
        headerText: "",
        footerText: "",
        includePageNumbers: false,
        typography: .liu,
        appearance: appearance,
        showsSourceLinks: !sourceLinksByItemKey.isEmpty,
        additionalCSS: liuCVPreviewCSS(),
        body: sectionsHTML
    )
}

private func htmlPreview(
    for document: PublicationAMAExportDocument,
    typography: ExportPreviewTypography,
    sourceLinksByItemKey: [String: CVPreviewSourceLink] = [:],
    sourceLinkActionTitle: String = "Edit"
) -> String {
    let sectionsHTML = document.sections.map { section in
        """
        <section class="doc-section">
          <h2>\(section.title.htmlEscaped)</h2>
          \(section.items.isEmpty ? "<p class=\"muted\">None</p>" : section.items.map {
            publicationItemHTML(
                $0,
                highlightName: document.highlightName,
                underlinedNames: document.underlinedNames,
                sourceLinksByItemKey: sourceLinksByItemKey,
                sourceLinkActionTitle: sourceLinkActionTitle
            )
          }.joined())
        </section>
        """
    }.joined()
    return exportHTMLDocument(
        title: document.title,
        subtitle: "",
        headerText: document.headerText,
        footerText: document.footerText,
        includePageNumbers: document.includePageNumbers,
        typography: typography,
        showsSourceLinks: !sourceLinksByItemKey.isEmpty,
        body: """
        <div class="hero">
          <h1>\(document.title.htmlEscaped)</h1>
        </div>
        \(sectionsHTML)
        """
    )
}

private func htmlPreview(
    for document: PublicationTemplateExportDocument,
    typography: ExportPreviewTypography,
    sourceLinksByItemKey: [String: CVPreviewSourceLink] = [:],
    sourceLinkActionTitle: String = "Edit"
) -> String {
    let sectionsHTML = document.sections.map { section in
        """
        <section class="doc-section">
          <h2>\(section.title.htmlEscaped)</h2>
          \(section.items.isEmpty ? "<p class=\"muted\">None</p>" : section.items.map {
            publicationItemHTML(
                $0,
                highlightName: document.highlightName,
                underlinedNames: document.underlinedNames,
                sourceLinksByItemKey: sourceLinksByItemKey,
                sourceLinkActionTitle: sourceLinkActionTitle
            )
          }.joined())
        </section>
        """
    }.joined()
    return exportHTMLDocument(
        title: document.title,
        subtitle: "",
        headerText: document.headerText,
        footerText: document.footerText,
        includePageNumbers: document.includePageNumbers,
        typography: typography,
        showsSourceLinks: !sourceLinksByItemKey.isEmpty,
        additionalCSS: publicationTemplatePreviewCSS(for: document),
        body: """
        <div class="hero">
          <h1>\(document.title.htmlEscaped)</h1>
        </div>
        \(sectionsHTML)
        """
    )
}

private func publicationTemplatePreviewCSS(for document: PublicationTemplateExportDocument) -> String {
    let bodySize = cssPointSize(document.fontSizeHalfPoints, fallbackHalfPoints: 24)
    let titleSize = cssPointSize(
        document.titleFontSizeHalfPoints ?? document.fontSizeHalfPoints,
        fallbackHalfPoints: 32
    )
    let sectionSize = cssPointSize(
        document.sectionFontSizeHalfPoints ?? document.fontSizeHalfPoints,
        fallbackHalfPoints: 26
    )
    let headerFooterSize = cssPointSize(
        document.headerFooterFontSizeHalfPoints ?? document.fontSizeHalfPoints,
        fallbackHalfPoints: 20
    )
    let fontFamily = cssFontFamily(document.fontFamily, fallback: "\"Times New Roman\", Times, serif")

    return """
    .page-content {
      font-family: \(fontFamily);
      font-size: \(bodySize);
    }
    .hero h1 {
      font-family: \(fontFamily);
      font-size: \(titleSize);
    }
    .doc-section h2 {
      font-family: \(fontFamily);
      font-size: \(sectionSize);
    }
    .publication-citation,
    .doc-section p,
    .muted {
      font-size: \(bodySize);
    }
    .page-header,
    .page-footer {
      font-family: \(fontFamily);
      font-size: \(headerFooterSize);
    }
    """
}

private func cssPointSize(_ halfPoints: Int?, fallbackHalfPoints: Int) -> String {
    let effectiveHalfPoints = max(1, halfPoints ?? fallbackHalfPoints)
    if effectiveHalfPoints.isMultiple(of: 2) {
        return "\(effectiveHalfPoints / 2)pt"
    }
    return String(format: "%.1fpt", Double(effectiveHalfPoints) / 2.0)
}

private func cssFontFamily(_ fontFamily: String, fallback: String) -> String {
    let trimmed = fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return fallback }
    let escaped = trimmed
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\", Times, serif"
}

private func htmlPreview(for document: TeachingMeritsExportDocument, typography: ExportPreviewTypography) -> String {
    let facultyName = document.facultyName?.trimmedOrNil ?? WorkflowDefaultSettings.defaultTeachingMeritsFacultyName.trimmedOrNil
    let headingText = facultyName.map { "Redovisning av pedagogiska meriter för vid \($0)" } ?? "Redovisning av pedagogiska meriter"
    let introHTML = """
    <section class="teaching-merits-intro">
      <h1>\(headingText.htmlEscaped)</h1>
      <p>Fyll i tabellerna nedan med relevant erfarenhet för din docenturansökan. Fokusera på de senaste 6 åren och redovisa dem med senast utfört högst upp i respektive tabell. Har du äldre pedagogiska meriter du vill inkludera, kan du göra det på en övergripande nivå (t ex "40% av min tid bestod av undervisning under åren 2010-2015").</p>
      <p>För undervisningstid går det utmärkt att använda Retendo-utdrag för antal timmar. I de fall dina uppdrag inte finns i Retendo, ska undervisningstid redovisas. Förberedelsetid och faktisk undervisningstid räknas in i detta.</p>
      <p>Ta bort exemplena i kursiv stil när du fyller i dina meriter. Behöver du fler rader kan du själv lägga till dessa.</p>
    </section>
    """

    let groupsHTML = document.groups.map { group in
        let tablesHTML = group.tables.map { table in
            let headerHTML = "<tr class=\"tm-header-row\">" + table.headers.map { "<th>\($0.htmlEscaped)</th>" }.joined() + "</tr>"
            let rowsHTML = table.rows.map { row in
                "<tr>" + row.map { "<td>\($0.htmlEscaped)</td>" }.joined() + "</tr>"
            }.joined()
            let paddedRows = table.rows.count >= 6 ? "" : Array(
                repeating: "<tr class=\"tm-empty-row\">\(Array(repeating: "<td>&nbsp;</td>", count: max(table.headers.count, 1)).joined())</tr>",
                count: 6 - table.rows.count
            ).joined()
            let sumHTML = "<tr class=\"tm-sum-row\"><td colspan=\"\(max(table.headers.count - 1, 1))\"><strong>\(table.sumLabel.htmlEscaped)</strong></td><td>\(table.sumValue.htmlEscaped)</td></tr>"
            return """
            <div class="doc-subsection">
              <table class="doc-table teaching-merits-table">
                <tr class="tm-title-row"><th colspan="\(max(table.headers.count, 1))">\(table.title.htmlEscaped)</th></tr>
                \(headerHTML)
                \(rowsHTML)\(paddedRows)
                \(sumHTML)
              </table>
            </div>
            """
        }.joined()
        return """
        <section class="doc-section teaching-merits-section">
          <h2>\(group.title.htmlEscaped)</h2>
          \(tablesHTML)
        </section>
        """
    }.joined()

    let summaryHTML: String
    if document.summaryRows.isEmpty {
        summaryHTML = ""
    } else {
        let summaryBodyRows = Array(document.summaryRows.dropLast())
        let summarySum = document.summaryRows.last ?? []
        let headerHTML = "<tr class=\"tm-header-row\">" + document.summaryHeaders.map { "<th>\($0.htmlEscaped)</th>" }.joined() + "</tr>"
        let rowsHTML = summaryBodyRows.map { row in
            "<tr>" + row.map { "<td>\($0.htmlEscaped)</td>" }.joined() + "</tr>"
        }.joined()
        let paddedRows = summaryBodyRows.count >= 7 ? "" : Array(
            repeating: "<tr class=\"tm-empty-row\">\(Array(repeating: "<td>&nbsp;</td>", count: max(document.summaryHeaders.count, 1)).joined())</tr>",
            count: 7 - summaryBodyRows.count
        ).joined()
        let sumHTML = "<tr class=\"tm-sum-row\"><td><strong>\((summarySum.first ?? "Summa").htmlEscaped)</strong></td><td>\((summarySum.dropFirst().first ?? "").htmlEscaped)</td></tr>"
        summaryHTML = """
        <section class="doc-section teaching-merits-section">
          <h2>Sammanställning</h2>
          <table class="doc-table teaching-merits-table">
            \(headerHTML)
            \(rowsHTML)\(paddedRows)
            \(sumHTML)
          </table>
        </section>
        """
    }

    return exportHTMLDocument(
        title: document.title,
        subtitle: "",
        headerText: "",
        footerText: "",
        includePageNumbers: false,
        typography: typography,
        landscape: true,
        additionalCSS: teachingMeritsTemplatePreviewCSS(),
        body: """
        \(introHTML)
        \(groupsHTML)
        \(summaryHTML)
        """
    )
}

private func exportHTMLDocument(
    title: String,
    subtitle: String,
    headerText: String,
    footerText: String,
    includePageNumbers: Bool,
    typography: ExportPreviewTypography,
    appearance: ExportPreviewAppearance = .standard,
    landscape: Bool = false,
    showsSourceLinks: Bool = false,
    additionalCSS: String = "",
    body: String
) -> String {
    let shellClass = showsSourceLinks ? "preview-shell has-source-links" : "preview-shell"
    return """
    <html>
    <head>
      \(exportPreviewCSS(typography: typography, appearance: appearance, landscape: landscape, additionalCSS: additionalCSS))
    </head>
    <body>
      <div class="\(shellClass)">
        <article class="paper">
          <header class="page-header">
            <span>\(headerText.htmlEscaped)</span>
            <span class="doc-title-small">\(title.htmlEscaped)</span>
          </header>
          <main class="page-content">
            \(body)
          </main>
          <footer class="page-footer">
            <span>\(footerText.htmlEscaped)</span>
            <span>\(includePageNumbers ? "Page 1" : "")</span>
          </footer>
        </article>
      </div>
    </body>
    </html>
    """
}

private func cvSectionHTML(
    _ section: CVExportSection,
    highlightName: String,
    underlinedNames: [String],
    sourceLinksByItemKey: [String: CVPreviewSourceLink] = [:],
    sourceLinkActionTitle: String = "Edit"
) -> String {
    let sectionClass: String
    switch section.layoutKind {
    case "pageBreakBefore":
        sectionClass = "doc-section page-break-before"
    case "protocol":
        sectionClass = "doc-section page-break-before protocol-section"
    default:
        sectionClass = "doc-section"
    }
    let headersHTML = section.headers.isEmpty ? "" : "<tr>" + section.headers.map { "<th>\($0.htmlEscaped)</th>" }.joined() + "</tr>"
    let rowsHTML = cvTableRowsHTML(
        section.rows,
        itemSourceIDs: section.itemSourceIDs,
        sourceLinksByItemKey: sourceLinksByItemKey,
        sourceLinkActionTitle: sourceLinkActionTitle
    )
    let defaultSourceID = cvPreviewDefaultSourceID(for: section.title, in: sourceLinksByItemKey)
    let itemsHTML = cvItemsHTML(
        section.items,
        itemSourceIDs: section.itemSourceIDs,
        defaultSourceID: defaultSourceID,
        layoutKind: section.layoutKind,
        highlightName: highlightName,
        underlinedNames: underlinedNames,
        sourceLinksByItemKey: sourceLinksByItemKey,
        sourceLinkActionTitle: sourceLinkActionTitle
    )
    let paragraphsHTML = section.paragraphs.map { "<p>\(inlineExportHTML($0, highlightName: highlightName, underlinedNames: underlinedNames))</p>" }.joined()
    let richHTML = cvRichParagraphsHTML(
        section.richParagraphs,
        sourceID: defaultSourceID,
        sourceLinksByItemKey: sourceLinksByItemKey,
        sourceLinkActionTitle: sourceLinkActionTitle
    )
    let subsectionsHTML = section.subsections.map {
        cvSubsectionHTML(
            $0,
            parentTitle: section.title,
            parentLayoutKind: section.layoutKind,
            highlightName: highlightName,
            underlinedNames: underlinedNames,
            sourceLinksByItemKey: sourceLinksByItemKey,
            sourceLinkActionTitle: sourceLinkActionTitle
        )
    }.joined()
    let tableHTML = section.rows.isEmpty ? "" : "<table class=\"doc-table\">\(headersHTML)\(rowsHTML)</table>"
    return """
    <section class="\(sectionClass)">
      <h2>\(section.title.htmlEscaped)</h2>
      \(paragraphsHTML)
      \(richHTML)
      \(itemsHTML)
      \(tableHTML)
      \(subsectionsHTML)
    </section>
    """
}

private func cvTableRowsHTML(
    _ rows: [[String]],
    itemSourceIDs: [String]? = nil,
    sourceLinksByItemKey: [String: CVPreviewSourceLink],
    sourceLinkActionTitle: String
) -> String {
    rows.enumerated().map { index, row in
        let sourceID = cvPreviewItemSourceID(at: index, in: itemSourceIDs)
        let link = cvPreviewSourceLink(
            forCandidates: row,
            sourceID: sourceID,
            in: sourceLinksByItemKey
        )
        let lastCellIndex = row.indices.last
        let cellsHTML = row.enumerated().map { cellIndex, value in
            let isLastCell = lastCellIndex.map { cellIndex == $0 } ?? false
            let linkHTML = isLastCell
                ? cvPreviewSourceAnchorHTML(link: link, actionTitle: sourceLinkActionTitle)
                : ""
            let classAttribute = isLastCell && link != nil ? " class=\"cv-source-table-cell\"" : ""
            return "<td\(classAttribute)>\(value.htmlEscaped)\(linkHTML)</td>"
        }.joined()
        let rowClass = link == nil ? "" : " class=\"cv-source-table-row\""
        return "<tr\(rowClass)>\(cellsHTML)</tr>"
    }.joined()
}

private func liuCVSectionHTML(
    _ section: CVExportSection,
    sourceLinksByItemKey: [String: CVPreviewSourceLink] = [:],
    sourceLinkActionTitle: String = "Edit"
) -> String {
    let defaultSourceID = cvPreviewDefaultSourceID(for: section.title, in: sourceLinksByItemKey)
    let sectionItemsHTML = section.items.enumerated().map { index, item in
        cvPreviewLinkedBlockHTML(
            blockHTML: "<p class=\"liu-content\">\(liuHTMLText(item))</p>",
            rawCandidates: [item],
            sourceID: cvPreviewItemSourceID(at: index, in: section.itemSourceIDs) ?? defaultSourceID,
            sourceLinksByItemKey: sourceLinksByItemKey,
            actionTitle: sourceLinkActionTitle
        )
    }.joined()
    let sectionParagraphsHTML = section.paragraphs.map { "<p class=\"liu-instruction\">\($0.htmlEscaped)</p>" }.joined()
    let subsectionsHTML = section.subsections.map {
        liuCVSubsectionHTML(
            $0,
            parentTitle: section.title,
            sourceLinksByItemKey: sourceLinksByItemKey,
            sourceLinkActionTitle: sourceLinkActionTitle
        )
    }.joined()
    return """
    <section class="doc-section liu-section">
      <h2>\(section.title.htmlEscaped)</h2>
      \(sectionParagraphsHTML)
      \(sectionItemsHTML)
      \(subsectionsHTML)
    </section>
    """
}

private func liuCVSubsectionHTML(
    _ subsection: CVExportSubsection,
    parentTitle: String,
    sourceLinksByItemKey: [String: CVPreviewSourceLink] = [:],
    sourceLinkActionTitle: String = "Edit"
) -> String {
    let paragraphsHTML = subsection.paragraphs.map { "<p class=\"liu-instruction\">\($0.htmlEscaped)</p>" }.joined()
    let defaultSourceID = cvPreviewDefaultSourceID(for: subsection.title.nonEmpty ?? parentTitle, in: sourceLinksByItemKey)
    let itemsHTML = subsection.items.enumerated().map { index, item in
        cvPreviewLinkedBlockHTML(
            blockHTML: "<p class=\"liu-content\">\(liuHTMLText(item))</p>",
            rawCandidates: [item],
            sourceID: cvPreviewItemSourceID(at: index, in: subsection.itemSourceIDs) ?? defaultSourceID,
            sourceLinksByItemKey: sourceLinksByItemKey,
            actionTitle: sourceLinkActionTitle
        )
    }.joined()
    let amaHTML = subsection.amaItems.map { item in
        let segments = [item.authors, item.title, item.journal, item.tail, item.note]
            .map(liuCleanHTMLText)
            .filter { !$0.isEmpty }
        var citation = segments.joined(separator: ". ")
        if !citation.isEmpty && !citation.hasSuffix(".") {
            citation += "."
        }
        return cvPreviewLinkedBlockHTML(
            blockHTML: "<p class=\"liu-content\">\(liuHTMLText(citation))</p>",
            rawCandidates: [item.plain, item.title, item.authors, item.journal],
            sourceID: item.sourceID,
            sourceLinksByItemKey: sourceLinksByItemKey,
            actionTitle: sourceLinkActionTitle
        )
    }.joined()
    return """
    <div class="doc-subsection liu-subsection">
      \(subsection.title.isEmpty ? "" : "<h3>\(subsection.title.htmlEscaped)</h3>")
      \(paragraphsHTML)
      \(amaHTML)
      \(itemsHTML)
    </div>
    """
}

private func liuHTMLText(_ text: String) -> String {
    inlineExportHTML(liuCleanHTMLText(text))
}

private func liuCleanHTMLText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "[[PUBDATA]]", with: "")
        .replacingOccurrences(of: "[[/PUBDATA]]", with: "")
        .replacingOccurrences(of: "[PUBDATA]", with: "")
        .replacingOccurrences(of: "[/PUBDATA]", with: "")
        .replacingOccurrences(of: "\t", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func cvSubsectionHTML(
    _ subsection: CVExportSubsection,
    parentTitle: String,
    parentLayoutKind: String,
    highlightName: String,
    underlinedNames: [String],
    sourceLinksByItemKey: [String: CVPreviewSourceLink] = [:],
    sourceLinkActionTitle: String = "Edit"
) -> String {
    let paragraphHTML = subsection.paragraphs.map { "<p>\(inlineExportHTML($0, highlightName: highlightName, underlinedNames: underlinedNames))</p>" }.joined()
    let richParagraphHTML = subsection.richParagraphs.map(cvRichParagraphHTML).joined()
    let barsHTML = subsection.bars.isEmpty ? "" : """
    <div class="stat-bars">
      \(subsection.bars.map { bar in
          let width = max(0, min(100, bar.fraction * 100))
          return """
          <div class="stat-bar-row">
            <span class="stat-bar-label">\(bar.label.htmlEscaped)</span>
            <span class="stat-bar-track"><span class="stat-bar-fill" style="width: \(String(format: "%.1f", width))%; background-color: #\(bar.colorHex);"></span></span>
            <span class="stat-bar-value">\(bar.valueText.htmlEscaped)</span>
          </div>
          """
      }.joined())
    </div>
    """
    let defaultSourceID = cvPreviewDefaultSourceID(for: subsection.title.nonEmpty ?? parentTitle, in: sourceLinksByItemKey)
    let itemsHTML = cvItemsHTML(
        subsection.items,
        itemSourceIDs: subsection.itemSourceIDs,
        defaultSourceID: defaultSourceID,
        layoutKind: parentLayoutKind,
        highlightName: highlightName,
        underlinedNames: underlinedNames,
        sourceLinksByItemKey: sourceLinksByItemKey,
        sourceLinkActionTitle: sourceLinkActionTitle
    )
    let amaHTML = subsection.amaItems.isEmpty ? "" : subsection.amaItems.map {
        publicationItemHTML(
            $0,
            layoutKind: parentLayoutKind,
            highlightName: highlightName,
            underlinedNames: underlinedNames,
            sourceLinksByItemKey: sourceLinksByItemKey,
            sourceLinkActionTitle: sourceLinkActionTitle
        )
    }.joined()
    let vrHTML = subsection.vrItems.isEmpty ? "" : subsection.vrItems.map { item in
        let itemHTML = """
        <div class="vr-item">
          <div class="vr-citation">\(inlineExportHTML(item.citation, highlightName: highlightName, underlinedNames: underlinedNames, preserveTabs: true))</div>
          \(item.note.isEmpty ? "" : "<div class=\"vr-note\">\(inlineExportHTML(item.note, highlightName: highlightName, underlinedNames: underlinedNames))</div>")
        </div>
        """
        return cvPreviewLinkedBlockHTML(
            blockHTML: itemHTML,
            rawCandidates: [item.citation],
            sourceID: item.sourceID,
            sourceLinksByItemKey: sourceLinksByItemKey,
            actionTitle: sourceLinkActionTitle
        )
    }.joined()
    return """
    <div class="doc-subsection">
      \(subsection.title.isEmpty ? "" : "<h3>\(subsection.title.htmlEscaped)</h3>")
      \(paragraphHTML)
      \(richParagraphHTML)
      \(barsHTML)
      \(itemsHTML)
      \(amaHTML)
      \(vrHTML)
    </div>
    """
}

private func cvItemsHTML(
    _ items: [String],
    itemSourceIDs: [String]? = nil,
    defaultSourceID: String? = nil,
    layoutKind: String,
    highlightName: String,
    underlinedNames: [String],
    sourceLinksByItemKey: [String: CVPreviewSourceLink] = [:],
    sourceLinkActionTitle: String = "Edit"
) -> String {
    guard !items.isEmpty else { return "" }
    return items.enumerated().map { index, item in
        cvItemHTML(
            item,
            sourceID: cvPreviewItemSourceID(at: index, in: itemSourceIDs) ?? defaultSourceID,
            layoutKind: layoutKind,
            highlightName: highlightName,
            underlinedNames: underlinedNames,
            sourceLinksByItemKey: sourceLinksByItemKey,
            sourceLinkActionTitle: sourceLinkActionTitle
        )
    }.joined()
}

private func cvItemHTML(
    _ text: String,
    sourceID: String? = nil,
    layoutKind: String,
    highlightName: String,
    underlinedNames: [String],
    sourceLinksByItemKey: [String: CVPreviewSourceLink] = [:],
    sourceLinkActionTitle: String = "Edit"
) -> String {
    let itemClass = switch layoutKind {
    case "conferenceContributions", "grants", "reviews", "media", "publicationList":
        "cv-item short"
    default:
        "cv-item standard"
    }

    if let tabRange = text.range(of: "\t") {
        let lead = String(text[..<tabRange.lowerBound])
        let body = String(text[tabRange.upperBound...])
        let paragraphHTML = """
        <p class="\(itemClass)">
          <span class="item-lead">\(inlineExportHTML(lead, highlightName: highlightName, underlinedNames: underlinedNames))</span>
          <span class="item-body">\(inlineExportHTML(body, highlightName: highlightName, underlinedNames: underlinedNames))</span>
        </p>
        """
        return cvPreviewLinkedBlockHTML(
            blockHTML: paragraphHTML,
            rawCandidates: [text],
            sourceID: sourceID,
            sourceLinksByItemKey: sourceLinksByItemKey,
            actionTitle: sourceLinkActionTitle
        )
    }

    let paragraphHTML = """
    <p class="\(itemClass) single">\(inlineExportHTML(text, highlightName: highlightName, underlinedNames: underlinedNames))</p>
    """
    return cvPreviewLinkedBlockHTML(
        blockHTML: paragraphHTML,
        rawCandidates: [text],
        sourceID: sourceID,
        sourceLinksByItemKey: sourceLinksByItemKey,
        actionTitle: sourceLinkActionTitle
    )
}

private func cvPreviewLinkedBlockHTML(
    blockHTML: String,
    rawCandidates: [String],
    sourceID: String? = nil,
    sourceLinksByItemKey: [String: CVPreviewSourceLink],
    actionTitle: String
) -> String {
    guard let link = cvPreviewSourceLink(forCandidates: rawCandidates, sourceID: sourceID, in: sourceLinksByItemKey) else {
        return blockHTML
    }
    return """
    <div class="cv-source-row">
      <div class="cv-source-content">\(blockHTML)</div>
      \(cvPreviewSourceAnchorHTML(link: link, actionTitle: actionTitle))
    </div>
    """
}

private func cvPreviewSourceAnchorHTML(
    link: CVPreviewSourceLink?,
    actionTitle: String
) -> String {
    guard let link else { return "" }
    let tooltip = "\(actionTitle): \(link.title)"
    return """
    <a class="cv-source-link" href="\(link.previewURLString.htmlEscaped)" title="\(tooltip.htmlEscaped)">\(actionTitle.htmlEscaped)</a>
    """
}

private func cvPreviewSourceLink(
    forCandidates candidates: [String],
    sourceID: String? = nil,
    in sourceLinksByItemKey: [String: CVPreviewSourceLink]
) -> CVPreviewSourceLink? {
    if let sourceID {
        let key = cvPreviewSourceItemKey(sourceID)
        if let link = sourceLinksByItemKey[key] {
            return link
        }
        if !key.isEmpty {
            return nil
        }
    }
    for candidate in candidates {
        let key = cvPreviewSourceItemKey(candidate)
        if let link = sourceLinksByItemKey[key] {
            return link
        }
    }
    return nil
}

private func cvPreviewItemSourceID(at index: Int, in sourceIDs: [String]?) -> String? {
    guard let sourceIDs, sourceIDs.indices.contains(index) else { return nil }
    return sourceIDs[index].nonEmpty
}

private func cvPreviewDefaultSourceID(for title: String, in sourceLinksByItemKey: [String: CVPreviewSourceLink]) -> String? {
    if cvPreviewSectionUsesPersonCard(title) {
        return sourceLinksByItemKey.values.first { $0.id.hasPrefix("author-") }?.id
    }
    if cvPreviewSectionUsesProfileEditor(title) {
        return "profile-editor"
    }
    return nil
}

private func cvRichParagraphsHTML(
    _ paragraphs: [CVExportRichTextParagraph],
    sourceID: String? = nil,
    sourceLinksByItemKey: [String: CVPreviewSourceLink],
    sourceLinkActionTitle: String
) -> String {
    let contentParagraphs = paragraphs.filter {
        !cvRichParagraphPlainText($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !contentParagraphs.isEmpty else { return "" }
    if let sourceID {
        return cvPreviewLinkedBlockHTML(
            blockHTML: contentParagraphs.map(cvRichParagraphHTML).joined(),
            rawCandidates: contentParagraphs.map(cvRichParagraphPlainText),
            sourceID: sourceID,
            sourceLinksByItemKey: sourceLinksByItemKey,
            actionTitle: sourceLinkActionTitle
        )
    }
    return contentParagraphs.map { paragraph in
        cvPreviewLinkedBlockHTML(
            blockHTML: cvRichParagraphHTML(paragraph),
            rawCandidates: [cvRichParagraphPlainText(paragraph)],
            sourceLinksByItemKey: sourceLinksByItemKey,
            actionTitle: sourceLinkActionTitle
        )
    }.joined()
}

private func cvRichParagraphHTML(_ paragraph: CVExportRichTextParagraph) -> String {
    let runs = paragraph.runs.map { run in
        let tagOpen = run.bold ? "<strong>" : ""
        let tagClose = run.bold ? "</strong>" : ""
        let italicOpen = run.italic ? "<em>" : ""
        let italicClose = run.italic ? "</em>" : ""
        let underlineOpen = run.underline ? "<span class=\"underlined\">" : ""
        let underlineClose = run.underline ? "</span>" : ""
        return "\(underlineOpen)\(italicOpen)\(tagOpen)\(run.text.htmlEscaped)\(tagClose)\(italicClose)\(underlineClose)"
    }.joined()
    // Deliberately empty paragraphs must keep their line: an empty <p>
    // collapses to zero height, so give it a non-breaking space.
    guard !runs.isEmpty else { return "<p>&nbsp;</p>" }
    guard let level = ProtocolMarkup.bulletLevel(ofLine: cvRichParagraphPlainText(paragraph)) else {
        return "<p>\(runs)</p>"
    }
    let levelClass = level > 1 ? " bullet-level-\(level)" : ""
    return "<p class=\"bullet-paragraph\(levelClass)\">\(runs)</p>"
}

private func cvRichParagraphPlainText(_ paragraph: CVExportRichTextParagraph) -> String {
    paragraph.runs.map(\.text).joined()
}

private func publicationItemHTML(
    _ item: PublicationAMAItem,
    layoutKind: String = "publicationList",
    highlightName: String,
    underlinedNames: [String],
    sourceLinksByItemKey: [String: CVPreviewSourceLink] = [:],
    sourceLinkActionTitle: String = "Edit"
) -> String {
    let title = inlineExportHTML(item.title, highlightName: highlightName, underlinedNames: underlinedNames)
    let journal = inlineExportHTML(item.journal, highlightName: highlightName, underlinedNames: underlinedNames)
    let tail = inlineExportHTML(item.tail, highlightName: highlightName, underlinedNames: underlinedNames)
    let note = inlineExportHTML(item.note, highlightName: highlightName, underlinedNames: underlinedNames)

    let citationClass = layoutKind == "publicationList" ? "citation-short" : "citation-long"

    func joinedCitationHTML(_ segments: [(raw: String, html: String)]) -> String {
        let visibleSegments = segments.filter {
            !$0.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.html.isEmpty
        }
        var joined = ""
        var previousRaw: String?

        for segment in visibleSegments {
            if let previousRaw {
                joined += PublicationCitationFormatting.separator(after: previousRaw)
            }
            joined += segment.html
            previousRaw = segment.raw
        }

        if let previousRaw,
           !PublicationCitationFormatting.hasTerminalPunctuation(previousRaw) {
            joined += "."
        }
        return joined
    }

    if let tabRange = item.authors.range(of: "\t") {
        let lead = String(item.authors[..<tabRange.lowerBound])
        let authorBody = String(item.authors[tabRange.upperBound...])
        let authors = inlineExportHTML(authorBody, highlightName: highlightName, underlinedNames: underlinedNames)

        let joined = joinedCitationHTML([
            (raw: authorBody, html: authors),
            (raw: item.title, html: title),
            (raw: item.journal, html: "<em>\(journal)</em>"),
            (raw: item.tail, html: tail),
            (raw: item.note, html: "<span class=\"citation-note\">\(note)</span>"),
        ])

        let paragraphHTML = """
        <p class="publication-citation \(citationClass) tabbed">
          <span class="citation-lead">\(inlineExportHTML(lead, highlightName: highlightName, underlinedNames: underlinedNames))</span>
          <span class="citation-body">\(joined)</span>
        </p>
        """
        return cvPreviewLinkedBlockHTML(
            blockHTML: paragraphHTML,
            rawCandidates: [item.plain, item.title, item.authors, item.journal],
            sourceID: item.sourceID,
            sourceLinksByItemKey: sourceLinksByItemKey,
            actionTitle: sourceLinkActionTitle
        )
    }

    let authors = inlineExportHTML(item.authors, highlightName: highlightName, underlinedNames: underlinedNames)
    let joined = joinedCitationHTML([
        (raw: item.authors, html: authors),
        (raw: item.title, html: title),
        (raw: item.journal, html: "<em>\(journal)</em>"),
        (raw: item.tail, html: tail),
        (raw: item.note, html: "<span class=\"citation-note\">\(note)</span>"),
    ])

    let paragraphHTML = "<p class=\"publication-citation \(citationClass) plain\">\(joined)</p>"
    return cvPreviewLinkedBlockHTML(
        blockHTML: paragraphHTML,
        rawCandidates: [item.plain, item.title, item.authors, item.journal],
        sourceID: item.sourceID,
        sourceLinksByItemKey: sourceLinksByItemKey,
        actionTitle: sourceLinkActionTitle
    )
}

private struct InlineExportRun {
    var text: String
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var superscript: Bool = false
}

private func inlineExportHTML(
    _ text: String,
    highlightName: String = "",
    underlinedNames: [String] = [],
    preserveTabs: Bool = false
) -> String {
    let parsedRuns = parseInlineExportRuns(text)
    let decoratedRuns = parsedRuns.flatMap { run in
        decorateInlineRun(run, highlightName: highlightName, underlinedNames: underlinedNames)
    }
    return decoratedRuns.map { run in
        var content = run.text.htmlEscaped
        if preserveTabs {
            content = content.replacingOccurrences(of: "\t", with: "&nbsp;&nbsp;&nbsp;")
        }
        if run.underline {
            content = "<span class=\"underlined\">\(content)</span>"
        }
        if run.superscript {
            content = "<sup>\(content)</sup>"
        }
        if run.italic {
            content = "<em>\(content)</em>"
        }
        if run.bold {
            content = "<strong>\(content)</strong>"
        }
        return content
    }.joined()
}

private func parseInlineExportRuns(_ text: String) -> [InlineExportRun] {
    let tagMap: [(String, (inout InlineExportRun) -> Void)] = [
        ("[[PUBDATA]]", { $0.italic = true }),
        ("[[/PUBDATA]]", { $0.italic = false }),
        ("[PUBDATA]", { $0.italic = true }),
        ("[/PUBDATA]", { $0.italic = false }),
        ("[[ITALIC]]", { $0.italic = true }),
        ("[[/ITALIC]]", { $0.italic = false }),
        ("[[BOLD]]", { $0.bold = true }),
        ("[[/BOLD]]", { $0.bold = false }),
        ("[[UNDERLINE]]", { $0.underline = true }),
        ("[[/UNDERLINE]]", { $0.underline = false }),
        ("[[SUP]]", { $0.superscript = true }),
        ("[[/SUP]]", { $0.superscript = false }),
    ]

    var current = InlineExportRun(text: "")
    var runs: [InlineExportRun] = []
    var index = text.startIndex

    func flushCurrent() {
        guard !current.text.isEmpty else { return }
        runs.append(current)
        current.text = ""
    }

    while index < text.endIndex {
        if let tag = tagMap.first(where: { text[index...].hasPrefix($0.0) }) {
            flushCurrent()
            tag.1(&current)
            index = text.index(index, offsetBy: tag.0.count)
            continue
        }
        current.text.append(text[index])
        index = text.index(after: index)
    }

    flushCurrent()
    return runs
}

private func decorateInlineRun(
    _ run: InlineExportRun,
    highlightName: String,
    underlinedNames: [String]
) -> [InlineExportRun] {
    let highlight = highlightName.trimmingCharacters(in: .whitespacesAndNewlines)
    let underlineTargets = underlinedNames
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    let highlightTargets = nameHighlightPhrases(highlight).map { ($0, true, false) }
    let underlineVariants = underlineTargets.flatMap(nameHighlightPhrases)
    let targets = (highlightTargets + underlineVariants.map { ($0, false, true) })
        .sorted { $0.0.count > $1.0.count }

    guard !targets.isEmpty, !run.text.isEmpty else { return [run] }

    var output: [InlineExportRun] = []
    var cursor = run.text.startIndex
    let lowercased = run.text.lowercased()

    while cursor < run.text.endIndex {
        let searchStart = lowercased.distance(from: lowercased.startIndex, to: cursor)
        var bestMatch: (range: Range<String.Index>, bold: Bool, underline: Bool)?

        for (target, addBold, addUnderline) in targets {
            guard let found = lowercased.range(
                of: target.lowercased(),
                options: [],
                range: lowercased.index(lowercased.startIndex, offsetBy: searchStart)..<lowercased.endIndex
            ) else { continue }
            if bestMatch.map({ found.lowerBound < $0.range.lowerBound }) ?? true {
                bestMatch = (found, addBold, addUnderline)
            }
        }

        guard let match = bestMatch else {
            var tail = run
            tail.text = String(run.text[cursor...])
            output.append(tail)
            break
        }

        if match.range.lowerBound > cursor {
            var prefix = run
            prefix.text = String(run.text[cursor..<match.range.lowerBound])
            output.append(prefix)
        }

        var highlighted = run
        highlighted.text = String(run.text[match.range])
        highlighted.bold = run.bold || match.bold
        highlighted.underline = run.underline || match.underline
        output.append(highlighted)
        cursor = match.range.upperBound
    }

    return output
}

private func nameHighlightPhrases(_ phrase: String) -> [String] {
    let full = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !full.isEmpty else { return [] }

    var variants = [full]
    let particles = Set(["af", "av", "de", "del", "der", "van", "von", "la", "le", "da", "di"])
    let words = full.split(whereSeparator: \.isWhitespace).map(String.init)
    if words.count >= 2 {
        var surnameWords = [words[words.count - 1]]
        if words.count >= 3, particles.contains(words[words.count - 2].lowercased()) {
            surnameWords = [words[words.count - 2], words[words.count - 1]]
        }
        let surname = surnameWords.joined(separator: " ")
        let givenWords = Array(words.dropLast(surnameWords.count))
        let initials = givenWords.compactMap { word -> String? in
            guard let first = word.first, first.isLetter else { return nil }
            return String(first)
        }.joined()
        if !surname.isEmpty, !initials.isEmpty {
            variants.append("\(surname) \(initials)")
            variants.append("\(surname), \(initials)")
        }
    }

    var seen: Set<String> = []
    let ordered = variants
        .sorted { $0.count > $1.count }
        .filter { value in
            let lowered = value.lowercased()
            if seen.contains(lowered) { return false }
            seen.insert(lowered)
            return true
        }
    return ordered
}

private extension String {
    var htmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "<br/>")
    }
}

private extension ExportPreviewTypography {
    static let timesDocument = ExportPreviewTypography(
        titleFont: "Arial, Helvetica, sans-serif",
        subtitleFont: "Arial, Helvetica, sans-serif",
        bodyFont: "\"Times New Roman\", Times, serif",
        sectionFont: "\"Times New Roman\", Times, serif",
        subsectionFont: "\"Times New Roman\", Times, serif",
        headerFooterFont: "\"Times New Roman\", Times, serif",
        citationIndentEm: 2.35,
        citationSpacingEm: 0.42
    )

    static let vetenskapsradet = ExportPreviewTypography(
        titleFont: "Arial, Helvetica, sans-serif",
        subtitleFont: "Arial, Helvetica, sans-serif",
        bodyFont: "Arial, Helvetica, sans-serif",
        sectionFont: "Arial, Helvetica, sans-serif",
        subsectionFont: "Arial, Helvetica, sans-serif",
        headerFooterFont: "Arial, Helvetica, sans-serif",
        citationIndentEm: 1.55,
        citationSpacingEm: 0.36
    )

    static let liu = ExportPreviewTypography(
        titleFont: "\"Courier New\", Courier, monospace",
        subtitleFont: "\"Courier New\", Courier, monospace",
        bodyFont: "\"Courier New\", Courier, monospace",
        sectionFont: "\"Times New Roman\", Times, serif",
        subsectionFont: "\"Courier New\", Courier, monospace",
        headerFooterFont: "\"Times New Roman\", Times, serif",
        citationIndentEm: 1.55,
        citationSpacingEm: 0.36
    )

    static func forCVStyle(_ style: String) -> ExportPreviewTypography {
        switch style {
        case CVDocumentExportStyle.liu.rawValue:
            return .liu
        case CVDocumentExportStyle.vetenskapsradet.rawValue:
            return .vetenskapsradet
        default:
            return .timesDocument
        }
    }
}

private func exportPreviewCSS(
    typography: ExportPreviewTypography,
    appearance: ExportPreviewAppearance = .standard,
    landscape: Bool = false,
    additionalCSS: String = ""
) -> String {
    let longIndentCM = 2.5
    let shortIndentCM = 1.0
    let paperWidth = landscape ? 1120 : 820
    let paperHeight = landscape ? 760 : 1080
    let pageRule = landscape ? "@page { size: A4 landscape; margin: 14mm; }" : "@page { size: A4 portrait; margin: 14mm; }"
    return """
<style>
\(pageRule)
:root {
  --preview-shell-background: \(appearance.shellBackgroundCSS);
  --preview-paper-background: \(appearance.paperBackgroundCSS);
  --preview-text-color: \(appearance.textColorCSS);
  --preview-muted-text-color: \(appearance.mutedTextColorCSS);
  --preview-secondary-text-color: \(appearance.secondaryTextColorCSS);
  --preview-note-text-color: \(appearance.noteTextColorCSS);
  --preview-border-color: \(appearance.borderColorCSS);
  --preview-shadow-color: \(appearance.shadowColorCSS);
}
html, body {
  margin: 0;
  padding: 0;
  background: var(--preview-shell-background);
  color: var(--preview-text-color);
  font-family: \(typography.bodyFont);
}
.preview-shell {
  padding: 28px;
}
.preview-shell.has-source-links {
  min-width: \(paperWidth + 240)px;
  padding-right: 190px;
}
.paper {
  width: \(paperWidth)px;
  min-height: \(paperHeight)px;
  margin: 0 auto;
  background: var(--preview-paper-background);
  border-radius: 22px;
  box-shadow: 0 18px 42px var(--preview-shadow-color);
  border: 1px solid var(--preview-border-color);
  display: flex;
  flex-direction: column;
}
.paper-empty {
  min-height: 620px;
}
.page-header, .page-footer {
  padding: 18px 40px;
  color: var(--preview-muted-text-color);
  font-size: 12px;
  font-family: \(typography.headerFooterFont);
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.page-header {
  border-bottom: 1px solid var(--preview-border-color);
}
.page-footer {
  border-top: 1px solid var(--preview-border-color);
  margin-top: auto;
}
.page-content {
  padding: 34px 52px 46px;
  font-family: \(typography.bodyFont);
  color: var(--preview-text-color);
}
.hero h1 {
  margin: 0;
  font-size: 38px;
  line-height: 1.08;
  font-family: \(typography.titleFont);
}
.subtitle {
  margin: 8px 0 0;
  color: var(--preview-muted-text-color);
  font-size: 16px;
  font-family: \(typography.subtitleFont);
}
.doc-section {
  margin-top: 30px;
}
.doc-section.page-break-before {
  break-before: page;
  page-break-before: always;
}
.doc-section h2 {
  margin: 0 0 14px;
  font-size: 21px;
  line-height: 1.2;
  font-family: \(typography.sectionFont);
}
.doc-subsection {
  margin-top: 16px;
}
.doc-subsection h3 {
  margin: 0 0 10px;
  font-size: 15px;
  color: var(--preview-secondary-text-color);
  font-family: \(typography.subsectionFont);
}
.cv-item {
  margin: 0 0 \(typography.citationSpacingEm)em 0;
  line-height: 1.24;
}
.cv-item.standard {
  display: grid;
  grid-template-columns: \(longIndentCM)cm minmax(0, 1fr);
  column-gap: 0;
  align-items: start;
}
.cv-item.short {
  display: grid;
  grid-template-columns: \(shortIndentCM)cm minmax(0, 1fr);
  column-gap: 0;
  align-items: start;
}
.cv-item.single {
  display: block;
}
.cv-item .item-lead {
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}
.cv-item .item-body {
  min-width: 0;
}
.cv-source-row {
  position: relative;
  margin: 0 0 \(typography.citationSpacingEm)em 0;
  min-height: 20px;
}
.cv-source-row .cv-item,
.cv-source-row .publication-citation,
.cv-source-row .liu-content,
.cv-source-row .vr-item {
  margin-bottom: 0;
}
.cv-source-content {
  min-width: 0;
}
.cv-source-link {
  position: absolute;
  top: 50%;
  left: calc(100% + 78px);
  transform: translateY(-50%);
  z-index: 2;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 62px;
  min-height: 17px;
  padding: 1px 7px 2px;
  border: 1px solid rgba(37, 99, 235, 0.34);
  border-radius: 999px;
  color: #2563eb;
  background: rgba(37, 99, 235, 0.06);
  font-family: Arial, Helvetica, sans-serif;
  font-size: 12px;
  font-weight: 700;
  line-height: 1;
  text-decoration: none;
  white-space: nowrap;
}
.cv-source-link:hover {
  background: rgba(37, 99, 235, 0.12);
  border-color: rgba(37, 99, 235, 0.5);
}
.doc-table {
  width: 100%;
  border-collapse: collapse;
  margin-top: 10px;
}
.doc-table th, .doc-table td {
  border-bottom: 1px solid var(--preview-border-color);
  padding: 8px 10px;
  text-align: left;
  vertical-align: top;
}
.hero-title-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
}
.hero-trailing {
  white-space: nowrap;
  color: var(--preview-muted-color, #6b7280);
}
.compact-tables .doc-table th, .compact-tables .doc-table td {
  padding: 1px 8px;
  line-height: 1.2;
  white-space: pre-line;
}
.protocol-section .doc-subsection h3 {
  font-size: 14pt;
  font-weight: 700;
  color: #000;
  margin: 9pt 0 3pt;
}
.protocol-section .doc-subsection p {
  font-size: 12pt;
  color: #000;
  line-height: 1.2;
  margin: 0 0 3pt;
}
.bullet-paragraph {
  padding-left: 0.62em;
  text-indent: -0.62em;
}
.bullet-paragraph.bullet-level-2 {
  padding-left: 1.86em;
}
.bullet-paragraph.bullet-level-3 {
  padding-left: 3.1em;
}
.stat-bars {
  margin: 4px 0 10px;
}
.stat-bar-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 0 0 5px;
}
.stat-bar-label {
  flex: 0 0 170px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.stat-bar-track {
  flex: 1 1 auto;
  height: 12px;
  background: #E5E7EB;
  border-radius: 6px;
  overflow: hidden;
}
.stat-bar-fill {
  display: block;
  height: 100%;
  border-radius: 6px;
}
.stat-bar-value {
  flex: 0 0 9.5em;
  text-align: right;
  white-space: nowrap;
  color: #374151;
}
.doc-table td.cv-source-table-cell {
  position: relative;
}
.vr-item {
  margin: 0.7em 0 0.9em;
  font-family: \(typography.bodyFont);
}
.publication-citation {
  margin: 0 0 \(typography.citationSpacingEm)em 0;
  line-height: 1.24;
}
.publication-citation.plain.citation-short {
  padding: 0 0 0 \(shortIndentCM)cm;
  text-indent: -\(shortIndentCM)cm;
}
.publication-citation.plain.citation-long {
  padding: 0 0 0 \(longIndentCM)cm;
  text-indent: -\(longIndentCM)cm;
}
.publication-citation.tabbed {
  display: grid;
  align-items: start;
}
.publication-citation.tabbed.citation-short {
  grid-template-columns: \(shortIndentCM)cm minmax(0, 1fr);
  column-gap: 0;
}
.publication-citation.tabbed.citation-long {
  grid-template-columns: \(longIndentCM)cm minmax(0, 1fr);
  column-gap: 0;
}
.publication-citation .citation-lead {
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}
.publication-citation .citation-body {
  min-width: 0;
}
.citation-note, .vr-note {
  color: var(--preview-note-text-color);
}
.muted {
  color: var(--preview-muted-text-color);
}
.empty-state {
  margin: auto;
  padding: 48px;
  text-align: center;
}
.underlined {
  text-decoration: underline;
}
sup {
  font-size: 12px;
  vertical-align: super;
  line-height: 0;
}
\(additionalCSS)
</style>
"""
}

private func teachingMeritsTemplatePreviewCSS() -> String {
    """
    .page-content {
      padding: 28px 34px 34px;
      font-family: Calibri, Arial, sans-serif;
      font-size: 14px;
    }
    .teaching-merits-intro h1 {
      margin: 0 0 10px;
      font-size: 26px;
      line-height: 1.15;
      font-family: Arial, sans-serif;
      font-weight: 700;
    }
    .teaching-merits-intro p {
      margin: 0 0 8px;
      line-height: 1.28;
    }
    .teaching-merits-section {
      margin-top: 22px;
    }
    .teaching-merits-section h2 {
      margin: 0 0 10px;
      font-size: 22px;
      line-height: 1.15;
      font-family: Arial, sans-serif;
      font-weight: 700;
    }
    .teaching-merits-table {
      margin-top: 8px;
      table-layout: fixed;
    }
    .teaching-merits-table th,
    .teaching-merits-table td {
      border: 1px solid #c5d3df;
      padding: 6px 8px;
      font-family: Calibri, Arial, sans-serif;
      font-size: 14px;
      vertical-align: top;
    }
    .teaching-merits-table .tm-title-row th {
      background: #a5c9eb;
      color: #000;
      text-align: left;
      font-family: Arial, sans-serif;
      font-weight: 700;
    }
    .teaching-merits-table .tm-header-row th {
      background: #dae9f7;
      color: #000;
      font-family: Arial, sans-serif;
      font-weight: 700;
    }
    .teaching-merits-table .tm-sum-row td {
      background: #dae9f7;
    }
    .teaching-merits-table .tm-sum-row td:first-child {
      text-align: right;
    }
    .teaching-merits-table .tm-empty-row td {
      height: 28px;
    }
    """
}

private func liuCVPreviewCSS() -> String {
    """
    .page-header,
    .page-footer {
      display: none;
    }
    .page-content {
      padding: 58px 60px 58px;
      font-size: 12pt;
      line-height: 1.15;
    }
    .liu-section {
      margin-top: 18px;
    }
    .liu-section:first-child {
      margin-top: 0;
    }
    .liu-section h2 {
      margin: 0 0 22px;
      font-family: "Times New Roman", Times, serif;
      font-size: 12pt;
      font-weight: 700;
      color: var(--preview-text-color);
    }
    .liu-subsection {
      margin-top: 14px;
    }
    .liu-subsection h3,
    .liu-instruction {
      margin: 0;
      font-family: "Courier New", Courier, monospace;
      font-size: 12pt;
      font-weight: 700;
      color: var(--preview-text-color);
      line-height: 1.15;
    }
    .liu-content {
      margin: 0;
      font-family: "Times New Roman", Times, serif;
      font-size: 12pt;
      font-style: italic;
      line-height: 1.15;
    }
    """
}
