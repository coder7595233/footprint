import AppKit
import Foundation

extension GrantDataStore {
    private enum BackgroundExportOpenBehavior {
        case none
        case standard
        case heartLungfonden
    }

    private func beginBackgroundActivity(_ message: String) {
        backgroundActivityCount += 1
        backgroundActivityMessage = message
        loadError = nil
    }

    private func endBackgroundActivity() {
        backgroundActivityCount = max(0, backgroundActivityCount - 1)
        if backgroundActivityCount == 0 {
            backgroundActivityMessage = nil
        }
    }

    func performBackgroundOperation<Result: Sendable>(
        startMessage: String,
        failureMessage: String,
        work: @escaping @Sendable () throws -> Result,
        onSuccess: @escaping @MainActor @Sendable (Result) -> Void
    ) {
        beginBackgroundActivity(startMessage)
        let finishActivity: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.endBackgroundActivity()
        }
        let handleFailure: @MainActor @Sendable (String) -> Void = { [weak self, failureMessage] errorDescription in
            guard let self else { return }
            self.endBackgroundActivity()
            self.loadError = errorDescription
            let normalizedDescription = errorDescription
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let visibleDescription = String(normalizedDescription.prefix(800))
            let message = visibleDescription.isEmpty
                ? failureMessage
                : failureMessage + " " + self.language.text("Error:", "Fel:") + " " + visibleDescription
            self.notice = StoreNotice(message: message, tone: .error)
        }
        Task.detached(priority: .utility) {
            do {
                let result = try work()
                await finishActivity()
                await onSuccess(result)
            } catch {
                await handleFailure(error.localizedDescription)
            }
        }
    }

    private func performBackgroundExport(
        startMessage: String,
        successMessage: String,
        failureMessage: String,
        destinationURL: URL,
        openBehavior: BackgroundExportOpenBehavior = .standard,
        work: @escaping @Sendable () throws -> Void
    ) {
        performBackgroundOperation(
            startMessage: startMessage,
            failureMessage: failureMessage,
            work: work
        ) { (_: Void) in
            self.loadError = nil
            let openedAutomatically: Bool
            switch openBehavior {
            case .none:
                openedAutomatically = true
            case .standard:
                openedAutomatically = self.openExportedFileIfAvailable(destinationURL)
            case .heartLungfonden:
                openedAutomatically = self.openHeartLungfondenExportedFileIfAvailable(destinationURL)
            }
            var message = successMessage + " " + self.language.text(
                "Saved in: \(destinationURL.deletingLastPathComponent().path).",
                "Sparad i: \(destinationURL.deletingLastPathComponent().path)."
            )
            if !openedAutomatically {
                message += " " + self.language.text(
                    "The file was created, but macOS could not open it automatically. It has been selected in Finder.",
                    "Filen skapades, men macOS kunde inte öppna den automatiskt. Den har markerats i Finder."
                )
            }
            self.notice = StoreNotice(message: message, tone: .success)
        }
    }

    nonisolated private static func withTemporaryWorkspace<Result>(
        prefix: String,
        body: (TemporaryWorkspaceDirectory) throws -> Result
    ) throws -> Result {
        let workspace = try TemporaryWorkspaceDirectory(prefix: prefix)
        defer { workspace.cleanup() }
        return try body(workspace)
    }

    nonisolated private static func encodePayloadAndRunPython<T: Encodable>(
        _ payload: T,
        payloadFileName: String,
        workspacePrefix: String,
        scriptName: String,
        destinationURL: URL,
        arguments: (TemporaryWorkspaceDirectory, URL, URL) throws -> [String]
    ) throws {
        try withTemporaryWorkspace(prefix: workspacePrefix) { workspace in
            let payloadURL = workspace.url.appendingPathComponent(payloadFileName)
            try Self.encode(payload, to: payloadURL)
            let scriptURL = try Self.supportScriptURL(named: scriptName)
            // The script writes inside the private workspace; the destination is
            // only replaced after a fully successful run, so a failed or killed
            // export can never overwrite a previously good file with a torn one.
            let stagedOutputURL = workspace.url
                .appendingPathComponent("staged-output", isDirectory: true)
                .appendingPathComponent(destinationURL.lastPathComponent)
            try FileManager.default.createDirectory(
                at: stagedOutputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = try Self.runPython(
                scriptURL: scriptURL,
                arguments: try arguments(workspace, payloadURL, stagedOutputURL)
            )
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: stagedOutputURL.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [
                    NSFilePathErrorKey: destinationURL.path,
                ])
            }
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagedOutputURL)
            } else {
                try fileManager.moveItem(at: stagedOutputURL, to: destinationURL)
            }
        }
    }

    nonisolated static func renderApplicationsWorkbook(_ applications: [GrantApplication], to destinationURL: URL) throws {
        try encodePayloadAndRunPython(
            applications,
            payloadFileName: "applications.json",
            workspacePrefix: "FootprintExport",
            scriptName: "export_grants.py",
            destinationURL: destinationURL
        ) { workspace, _, stagedOutputURL in
            [
                "--input-dir",
                workspace.url.path,
                "--output",
                stagedOutputURL.path,
            ]
        }
    }

    nonisolated static func renderGenericWorkbook(
        _ sheets: [WorkbookExportSheet],
        to destinationURL: URL,
        workspacePrefix: String
    ) throws {
        try encodePayloadAndRunPython(
            sheets,
            payloadFileName: "sheets.json",
            workspacePrefix: workspacePrefix,
            scriptName: "export_generic_workbook.py",
            destinationURL: destinationURL
        ) { _, payloadURL, stagedOutputURL in
            [
                "--input",
                payloadURL.path,
                "--output",
                stagedOutputURL.path,
            ]
        }
    }

    nonisolated static func renderSalaryCoverageWorkbook(_ rows: [SalaryCoverageExportRow], to destinationURL: URL) throws {
        try encodePayloadAndRunPython(
            rows,
            payloadFileName: "salary_coverage.json",
            workspacePrefix: "FootprintSalaryExport",
            scriptName: "export_salary_coverage.py",
            destinationURL: destinationURL
        ) { _, payloadURL, stagedOutputURL in
            [
                "--input",
                payloadURL.path,
                "--output",
                stagedOutputURL.path,
            ]
        }
    }

    nonisolated static func renderPublicationDocument(_ payload: PublicationAMAExportDocument, to destinationURL: URL) throws {
        try encodePayloadAndRunPython(
            payload,
            payloadFileName: "publications_ama.json",
            workspacePrefix: "FootprintAMA",
            scriptName: "export_publications_ama.py",
            destinationURL: destinationURL
        ) { _, payloadURL, stagedOutputURL in
            [
                "--input-json",
                payloadURL.path,
                "--output",
                stagedOutputURL.path,
            ]
        }
    }

    nonisolated static func renderSubmissionWorkbook(_ payload: SubmissionAuthorWorkbookPayload, to destinationURL: URL) throws {
        try encodePayloadAndRunPython(
            payload,
            payloadFileName: "submission_authors.json",
            workspacePrefix: "FootprintSubmission",
            scriptName: "export_submission_authors.py",
            destinationURL: destinationURL
        ) { _, payloadURL, stagedOutputURL in
            [
                "--input-json",
                payloadURL.path,
                "--output",
                stagedOutputURL.path,
            ]
        }
    }

    nonisolated static func renderTeachingMeritsDocument(_ payload: TeachingMeritsExportDocument, to destinationURL: URL) throws {
        try encodePayloadAndRunPython(
            payload,
            payloadFileName: "teaching_merits.json",
            workspacePrefix: "FootprintTeachingMerits",
            scriptName: "export_teaching_merits_docx.py",
            destinationURL: destinationURL
        ) { _, payloadURL, stagedOutputURL in
            var arguments = [
                "--input-json",
                payloadURL.path,
                "--output",
                stagedOutputURL.path,
            ]
            if let templateURL = Self.teachingMeritsTemplateURL() {
                arguments.append(contentsOf: ["--template", templateURL.path])
            }
            return arguments
        }
    }

    nonisolated static func renderCVDocument(_ payload: CVExportDocument, to destinationURL: URL) throws {
        try encodePayloadAndRunPython(
            payload,
            payloadFileName: "cv_export.json",
            workspacePrefix: "FootprintCV",
            scriptName: "export_cv_docx.py",
            destinationURL: destinationURL
        ) { _, payloadURL, stagedOutputURL in
            [
                "--input-json",
                payloadURL.path,
                "--output",
                stagedOutputURL.path,
            ]
        }
    }

    nonisolated static func renderHeartLungfondenDocument(_ payload: PublicationTemplateExportDocument, to destinationURL: URL) throws {
        try encodePayloadAndRunPython(
            payload,
            payloadFileName: "publications_hjart_lungfonden.json",
            workspacePrefix: "FootprintHeartLungfonden",
            scriptName: "export_publications_ama.py",
            destinationURL: destinationURL
        ) { _, payloadURL, stagedOutputURL in
            [
                "--input-json",
                payloadURL.path,
                "--output",
                stagedOutputURL.path,
            ]
        }
    }

    func exportEntireAppWorkbookToDefaultLocation() {
        let destinationURL = exportDestinationURL(fileName: language.text("Entire app data", "All appdata") + ".xlsx")
        let sheets = entireAppWorkbookSheets()
        let startMessage = language.text("Exporting all app data…", "Exporterar all appdata…")
        let successMessage = language.text(
            "Exported all app data to \(destinationURL.lastPathComponent).",
            "Exporterade all appdata till \(destinationURL.lastPathComponent)."
        )
        let failureMessage = language.text("Full-app export failed.", "Export av all appdata misslyckades.")

        performBackgroundExport(
            startMessage: startMessage,
            successMessage: successMessage,
            failureMessage: failureMessage,
            destinationURL: destinationURL
        ) {
            try Self.renderGenericWorkbook(
                sheets,
                to: destinationURL,
                workspacePrefix: "FootprintAllData"
            )
        }
    }

    func exportProjectWorkbookToDefaultLocation(for project: ProjectRecord) {
        exportProjectWorkbookToDefaultLocation(for: project, language: language)
    }

    func exportProjectWorkbookToDefaultLocation(for project: ProjectRecord, language exportLanguage: AppLanguage) {
        let stem = (project.displayName(for: exportLanguage).nonEmpty ?? exportLanguage.text("Untitled project", "Namnlöst projekt"))
            .replacingOccurrences(of: #"[\\/:*?\"<>|]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationURL = exportDestinationURL(
            fileName: "\(stem), \(exportLanguage.text("complete project export", "komplett projektexport")).xlsx"
        )
        let sheets = projectWorkbookSheets(for: project, language: exportLanguage)
        let startMessage = language.text("Exporting project to Excel…", "Exporterar projekt till Excel…")
        let successMessage = language.text(
            "Exported the complete project to \(destinationURL.lastPathComponent).",
            "Exporterade hela projektet till \(destinationURL.lastPathComponent)."
        )
        let failureMessage = language.text("Project export failed.", "Projektexport misslyckades.")

        performBackgroundExport(
            startMessage: startMessage,
            successMessage: successMessage,
            failureMessage: failureMessage,
            destinationURL: destinationURL
        ) {
            try Self.renderGenericWorkbook(
                sheets,
                to: destinationURL,
                workspacePrefix: "FootprintProjectExport"
            )
        }
    }

    func exportSalaryCoverageWorkbookToDefaultLocation() {
        let destinationURL = exportDestinationURL(fileName: "Lön export.xlsx")
        let rows = salaryCoverageExportRows(language: .swedish)
        let startMessage = language.text("Exporting salary plan…", "Exporterar löneplan…")
        let successMessage = language.text(
            "Exported salary plan to \(destinationURL.lastPathComponent).",
            "Exporterade löneplan till \(destinationURL.lastPathComponent)."
        )
        let failureMessage = language.text("Export failed.", "Export misslyckades.")

        performBackgroundExport(
            startMessage: startMessage,
            successMessage: successMessage,
            failureMessage: failureMessage,
            destinationURL: destinationURL
        ) {
            try Self.renderSalaryCoverageWorkbook(rows, to: destinationURL)
        }
    }

    func exportPublicationsAMADocumentToDefaultLocation() {
        if !confirmProceedingAfterValidation(
            title: language.text("AMA export", "AMA-export"),
            issues: publicationRecords.isEmpty ? [language.text("There are no publications to export.", "Det finns inga publikationer att exportera.")] : []
        ) {
            notice = StoreNotice(message: language.text("Cancelled export.", "Export avbröts."), tone: .info)
            loadError = nil
            return
        }

        let destinationURL = exportDestinationURL(fileName: "AMA.docx")
        exportPublicationsCustomDocumentAsync(
            configuration: PublicationCustomExportConfiguration(),
            layout: ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false),
            to: destinationURL
        )
    }

    func exportPublicationsCustomDocumentToDefaultLocation(configuration: PublicationCustomExportConfiguration) {
        if !confirmProceedingAfterValidation(
            title: language.text("Custom publication export", "Skräddarsydd publikationsexport"),
            issues: publicationRecords.isEmpty ? [language.text("There are no publications to export.", "Det finns inga publikationer att exportera.")] : []
        ) {
            notice = StoreNotice(message: language.text("Cancelled export.", "Export avbröts."), tone: .info)
            loadError = nil
            return
        }

        let destinationURL = exportDestinationURL(
            fileName: language.text("Publications custom", "Publikationer skräddarsydd") + ".docx"
        )
        exportPublicationsCustomDocumentAsync(
            configuration: configuration,
            layout: ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false),
            to: destinationURL
        )
    }

    func exportSubmissionWorkbookToDefaultLocation(
        for publication: PublicationRecord,
        configuration: SubmissionAuthorExportConfiguration = .standard
    ) {
        if !confirmProceedingAfterValidation(
            title: language.text("Author details export", "Export av författaruppgifter"),
            issues: publicationSubmissionValidationIssues(for: publication)
        ) {
            notice = StoreNotice(message: language.text("Cancelled export.", "Export avbröts."), tone: .info)
            loadError = nil
            return
        }

        let stem = publication.title
            .replacingOccurrences(of: #"[\\/:*?"<>|]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultStem: String = {
            guard stem.isEmpty else { return stem }
            return configuration.effectiveExportLanguage == .swedish ? "Namnlös artikel" : "Untitled article"
        }()
        let suffix: String = {
            switch configuration.mode {
            case .standard:
                return configuration.effectiveExportLanguage == .swedish ? "författarlista" : "author list"
            case .editorialManager:
                return "Editorial Manager"
            case .custom:
                return configuration.effectiveExportLanguage == .swedish ? "författarlista custom" : "author list custom"
            }
        }()
        let destinationURL = exportDestinationURL(fileName: "\(defaultStem), \(suffix).xlsx")
        exportSubmissionWorkbookAsync(
            for: publication,
            configuration: configuration,
            to: destinationURL
        )
    }

    func exportSubmissionWorkbookToDefaultLocation(
        for project: ProjectRecord,
        configuration: SubmissionAuthorExportConfiguration = .standard
    ) {
        if !confirmProceedingAfterValidation(
            title: language.text("Author details export", "Export av författaruppgifter"),
            issues: projectSubmissionValidationIssues(for: project)
        ) {
            notice = StoreNotice(message: language.text("Cancelled export.", "Export avbröts."), tone: .info)
            loadError = nil
            return
        }

        let stem = (project.nameSv.nonEmpty ?? project.nameEn.nonEmpty ?? "")
            .replacingOccurrences(of: #"[\\/:*?"<>|]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultStem: String = {
            guard stem.isEmpty else { return stem }
            return configuration.effectiveExportLanguage == .swedish ? "Namnlöst projekt" : "Untitled project"
        }()
        let suffix: String = {
            switch configuration.mode {
            case .standard:
                return configuration.effectiveExportLanguage == .swedish ? "författarlista" : "author list"
            case .editorialManager:
                return "Editorial Manager"
            case .custom:
                return configuration.effectiveExportLanguage == .swedish ? "författarlista custom" : "author list custom"
            }
        }()
        let destinationURL = exportDestinationURL(fileName: "\(defaultStem), \(suffix).xlsx")
        exportSubmissionWorkbookAsync(
            for: project,
            configuration: configuration,
            to: destinationURL
        )
    }

    func exportTeachingMeritsDocumentToDefaultLocation() {
        if !confirmProceedingAfterValidation(
            title: language.text("Teaching merits export", "Export av pedagogiska meriter"),
            issues: teachingExportValidationIssues()
        ) {
            notice = StoreNotice(message: language.text("Cancelled export.", "Export avbröts."), tone: .info)
            loadError = nil
            return
        }

        let destinationURL = exportDestinationURL(
            fileName: language.text("Teaching merits", "Pedagogiska meriter") + ".docx"
        )
        exportTeachingMeritsDocumentAsync(
            document: teachingMeritsExportDocument(),
            to: destinationURL
        )
    }

    func exportCVDocumentToDefaultLocation(style: CVDocumentExportStyle, exportLanguage: AppLanguage) {
        if !confirmProceedingAfterValidation(
            title: style == .liu
                ? language.text("LiU CV export", "LiU-CV-export")
                : language.text("CV export", "CV-export"),
            issues: cvExportValidationIssues(style: style)
        ) {
            notice = StoreNotice(message: language.text("Cancelled export.", "Export avbröts."), tone: .info)
            loadError = nil
            return
        }

        let destinationURL = exportDestinationURL(
            fileName: preferredCVExportFileName(for: style, exportLanguage: exportLanguage)
        )
        exportCVDocumentAsync(
            style: style,
            exportLanguage: exportLanguage,
            layout: ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false),
            to: destinationURL
        )
    }

    func exportVetenskapsradetCVDocumentToDefaultLocation(selectedOutputs: [CVVRSelectedOutput]) {
        if !confirmProceedingAfterValidation(
            title: language.text("Vetenskapsrådet CV export", "Export av Vetenskapsrådets CV"),
            issues: cvExportValidationIssues(style: .vetenskapsradet)
        ) {
            notice = StoreNotice(message: language.text("Cancelled export.", "Export avbröts."), tone: .info)
            loadError = nil
            return
        }

        let destinationURL = exportDestinationURL(
            fileName: preferredCVExportFileName(for: .vetenskapsradet, exportLanguage: language)
        )
        exportVetenskapsradetCVDocumentAsync(
            selectedOutputs: selectedOutputs,
            layout: ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false),
            to: destinationURL
        )
    }

    func exportCustomCVDocumentToDefaultLocation(configuration: CVCustomExportConfiguration) {
        if !confirmProceedingAfterValidation(
            title: language.text("Custom CV export", "Skräddarsydd CV-export"),
            issues: cvExportValidationIssues(style: configuration.style)
        ) {
            notice = StoreNotice(message: language.text("Cancelled export.", "Export avbröts."), tone: .info)
            loadError = nil
            return
        }

        let destinationURL = exportDestinationURL(
            fileName: preferredCVExportFileName(
                for: configuration.style,
                exportLanguage: configuration.exportLanguage
            )
        )
        exportCustomCVDocumentAsync(
            configuration: configuration,
            layout: ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false),
            to: destinationURL
        )
    }

    func exportPublicationsCustomDocumentAsync(
        configuration: PublicationCustomExportConfiguration,
        layout: ExportDocumentLayoutOptions,
        to destinationURL: URL,
        openOnSuccess: Bool = true
    ) {
        let payload = publicationCustomPreviewDocument(configuration: configuration, layout: layout)
        let startMessage = language.text("Exporting publications…", "Exporterar publikationer…")
        let successMessage = language.text(
            "Exported publication document to \(destinationURL.lastPathComponent).",
            "Exporterade publikationsdokument till \(destinationURL.lastPathComponent)."
        )
        let failureMessage = language.text("Publication export failed.", "Publikationsexport misslyckades.")

        performBackgroundExport(
            startMessage: startMessage,
            successMessage: successMessage,
            failureMessage: failureMessage,
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .standard : .none
        ) {
            try Self.renderPublicationDocument(payload, to: destinationURL)
        }
    }

    func exportSubmissionWorkbookAsync(
        for publication: PublicationRecord,
        configuration: SubmissionAuthorExportConfiguration = .standard,
        to destinationURL: URL,
        openOnSuccess: Bool = true
    ) {
        let rows = submissionAuthorRows(for: publication)
        let payload = submissionAuthorWorkbookPayload(from: rows, configuration: configuration)
        let successMessage = language.text(
            "Exported submission workbook to \(destinationURL.lastPathComponent).",
            "Exporterade submission-arbetsbok till \(destinationURL.lastPathComponent)."
        )

        performBackgroundExport(
            startMessage: language.text("Exporting author details…", "Exporterar författaruppgifter…"),
            successMessage: successMessage,
            failureMessage: language.text("Submission export failed.", "Submission-export misslyckades."),
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .standard : .none
        ) {
            try Self.renderSubmissionWorkbook(payload, to: destinationURL)
        }
    }

    func exportSubmissionWorkbookAsync(
        for project: ProjectRecord,
        configuration: SubmissionAuthorExportConfiguration = .standard,
        to destinationURL: URL,
        openOnSuccess: Bool = true
    ) {
        let rows = submissionAuthorRows(for: project)
        let payload = submissionAuthorWorkbookPayload(from: rows, configuration: configuration)
        let successMessage = language.text(
            "Exported author details for \(project.nameSv.nonEmpty ?? project.nameEn.nonEmpty ?? project.id).",
            "Exporterade författaruppgifter för \(project.nameSv.nonEmpty ?? project.nameEn.nonEmpty ?? project.id)."
        )

        performBackgroundExport(
            startMessage: language.text("Exporting author details…", "Exporterar författaruppgifter…"),
            successMessage: successMessage,
            failureMessage: language.text("Author details export failed.", "Export av författaruppgifter misslyckades."),
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .standard : .none
        ) {
            try Self.renderSubmissionWorkbook(payload, to: destinationURL)
        }
    }

    func exportTeachingMeritsDocumentAsync(
        document: TeachingMeritsExportDocument,
        to destinationURL: URL,
        openOnSuccess: Bool = true
    ) {
        let startMessage = language.text("Exporting teaching merits…", "Exporterar pedagogiska meriter…")
        let successMessage = language.text(
            "Exported teaching merits document to \(destinationURL.lastPathComponent).",
            "Exporterade pedagogiska meriter till \(destinationURL.lastPathComponent)."
        )
        let failureMessage = language.text(
            "Teaching merits export failed.",
            "Export av pedagogiska meriter misslyckades."
        )

        performBackgroundExport(
            startMessage: startMessage,
            successMessage: successMessage,
            failureMessage: failureMessage,
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .standard : .none
        ) {
            try Self.renderTeachingMeritsDocument(document, to: destinationURL)
        }
    }

    func exportCVDocumentAsync(
        style: CVDocumentExportStyle,
        exportLanguage: AppLanguage,
        layout: ExportDocumentLayoutOptions,
        to destinationURL: URL,
        openOnSuccess: Bool = true
    ) {
        var layoutPayload = cvExportDocument(style: style, exportLanguage: exportLanguage)
        applyLayout(layout, to: &layoutPayload, exportLanguage: exportLanguage)
        let renderedPayload = layoutPayload

        let successMessage = style == .liu
            ? language.text("Exported LiU CV document to \(destinationURL.lastPathComponent).", "Exporterade LiU-CV till \(destinationURL.lastPathComponent).")
            : style == .vetenskapsradet
            ? language.text("Exported Vetenskapsrådet CV to \(destinationURL.lastPathComponent).", "Exporterade Vetenskapsrådets CV till \(destinationURL.lastPathComponent).")
            : language.text("Exported CV document to \(destinationURL.lastPathComponent).", "Exporterade CV till \(destinationURL.lastPathComponent).")
        let failureMessage = style == .liu
            ? language.text("LiU CV export failed.", "Export av LiU-CV misslyckades.")
            : style == .vetenskapsradet
            ? language.text("Vetenskapsrådet CV export failed.", "Export av Vetenskapsrådets CV misslyckades.")
            : language.text("CV export failed.", "CV-export misslyckades.")

        performBackgroundExport(
            startMessage: language.text("Exporting CV…", "Exporterar CV…"),
            successMessage: successMessage,
            failureMessage: failureMessage,
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .standard : .none
        ) {
            try Self.renderCVDocument(renderedPayload, to: destinationURL)
        }
    }

    func exportVetenskapsradetCVDocumentAsync(
        selectedOutputs: [CVVRSelectedOutput],
        layout: ExportDocumentLayoutOptions,
        to destinationURL: URL,
        openOnSuccess: Bool = true
    ) {
        let payload = publicationVetenskapsradetPreviewDocument(
            selectedOutputs: selectedOutputs,
            layout: layout
        )

        performBackgroundExport(
            startMessage: language.text("Exporting Vetenskapsrådet CV…", "Exporterar Vetenskapsrådets CV…"),
            successMessage: language.text(
                "Exported Vetenskapsrådet CV to \(destinationURL.lastPathComponent).",
                "Exporterade Vetenskapsrådets CV till \(destinationURL.lastPathComponent)."
            ),
            failureMessage: language.text(
                "Vetenskapsrådet CV export failed.",
                "Export av Vetenskapsrådets CV misslyckades."
            ),
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .standard : .none
        ) {
            try Self.renderCVDocument(payload, to: destinationURL)
        }
    }

    func exportCustomCVDocumentAsync(
        configuration: CVCustomExportConfiguration,
        layout: ExportDocumentLayoutOptions,
        to destinationURL: URL,
        openOnSuccess: Bool = true
    ) {
        let payload = customCVPreviewDocument(configuration: configuration, layout: layout)

        performBackgroundExport(
            startMessage: language.text("Exporting custom CV…", "Exporterar skräddarsytt CV…"),
            successMessage: language.text(
                "Exported custom CV to \(destinationURL.lastPathComponent).",
                "Exporterade skräddarsytt CV till \(destinationURL.lastPathComponent)."
            ),
            failureMessage: language.text(
                "Custom CV export failed.",
                "Skräddarsydd CV-export misslyckades."
            ),
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .standard : .none
        ) {
            try Self.renderCVDocument(payload, to: destinationURL)
        }
    }

    func exportAnnualReportDocumentAsync(
        year: Int,
        exportLanguage: AppLanguage,
        includeCoApplicantGrants: Bool = false,
        layout: ExportDocumentLayoutOptions,
        to destinationURL: URL,
        openOnSuccess: Bool = true
    ) {
        let payload = annualReportPreviewDocument(
            year: year,
            exportLanguage: exportLanguage,
            includeCoApplicantGrants: includeCoApplicantGrants,
            layout: layout
        )

        performBackgroundExport(
            startMessage: language.text("Exporting annual report…", "Exporterar årsrapport…"),
            successMessage: language.text(
                "Exported annual report to \(destinationURL.lastPathComponent).",
                "Exporterade årsrapport till \(destinationURL.lastPathComponent)."
            ),
            failureMessage: language.text(
                "Annual report export failed.",
                "Export av årsrapport misslyckades."
            ),
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .standard : .none
        ) {
            try Self.renderCVDocument(payload, to: destinationURL)
        }
    }

    func exportProjectDocumentAsync(
        project: ProjectRecord,
        includedSections: Set<ProjectDocumentSection> = Set(ProjectDocumentSection.allCases),
        to destinationURL: URL,
        openOnSuccess: Bool = true
    ) {
        let payload = projectSummaryDocument(
            for: project,
            exportLanguage: language,
            includedSections: includedSections
        )

        performBackgroundExport(
            startMessage: language.text("Exporting project document…", "Exporterar projektdokument…"),
            successMessage: language.text(
                "Exported project document to \(destinationURL.lastPathComponent).",
                "Exporterade projektdokument till \(destinationURL.lastPathComponent)."
            ),
            failureMessage: language.text(
                "Project document export failed.",
                "Export av projektdokument misslyckades."
            ),
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .standard : .none
        ) {
            try Self.renderCVDocument(payload, to: destinationURL)
        }
    }

    func exportApplicationDocumentAsync(
        application: GrantApplication,
        includedSections: Set<ApplicationDocumentSection> = Set(ApplicationDocumentSection.allCases),
        to destinationURL: URL,
        openOnSuccess: Bool = true
    ) {
        let payload = applicationSummaryDocument(
            for: application,
            exportLanguage: language,
            includedSections: includedSections
        )

        performBackgroundExport(
            startMessage: language.text("Exporting grant document…", "Exporterar anslagsdokument…"),
            successMessage: language.text(
                "Exported grant document to \(destinationURL.lastPathComponent).",
                "Exporterade anslagsdokument till \(destinationURL.lastPathComponent)."
            ),
            failureMessage: language.text(
                "Grant document export failed.",
                "Export av anslagsdokument misslyckades."
            ),
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .standard : .none
        ) {
            try Self.renderCVDocument(payload, to: destinationURL)
        }
    }

    func exportPublicationDocumentAsync(
        publication: PublicationRecord,
        includedSections: Set<PublicationDocumentSection> = Set(PublicationDocumentSection.allCases),
        to destinationURL: URL,
        openOnSuccess: Bool = true
    ) {
        let payload = publicationSummaryDocument(
            for: publication,
            exportLanguage: language,
            includedSections: includedSections
        )

        performBackgroundExport(
            startMessage: language.text("Exporting publication document…", "Exporterar publikationsdokument…"),
            successMessage: language.text(
                "Exported publication document to \(destinationURL.lastPathComponent).",
                "Exporterade publikationsdokument till \(destinationURL.lastPathComponent)."
            ),
            failureMessage: language.text(
                "Publication document export failed.",
                "Export av publikationsdokument misslyckades."
            ),
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .standard : .none
        ) {
            try Self.renderCVDocument(payload, to: destinationURL)
        }
    }

    func exportPublicationsHeartLungfondenDocumentToDefaultLocation(
        configuration: PublicationHeartLungfondenExportConfiguration
    ) {
        let payload = publicationHeartLungfondenPreviewDocument(configuration: configuration)
        let itemCount = payload.sections.reduce(into: 0) { partialResult, section in
            partialResult += section.items.count
        }

        guard itemCount > 0 else {
            notice = StoreNotice(
                message: language.text(
                    "There are no published or accepted publications within the selected Hjärt-Lungfonden period.",
                    "Det finns inga publicerade eller accepterade publikationer inom vald Hjärt-Lungfonden-period."
                ),
                tone: .info
            )
            loadError = nil
            return
        }

        let dateRangeDescription = heartLungfondenDateRangeDescription(configuration: configuration)
            .replacingOccurrences(of: " - ", with: " till ")
        let destinationURL = heartLungfondenExportDestinationURL(
            fileName: "Publikationsförteckning Hjärt-Lungfonden \(dateRangeDescription).docx"
        )
        exportPublicationsHeartLungfondenDocumentAsync(
            configuration: configuration,
            to: destinationURL
        )
    }

    func exportPublicationsHeartLungfondenDocumentAsync(
        configuration: PublicationHeartLungfondenExportConfiguration,
        to destinationURL: URL,
        layout: ExportDocumentLayoutOptions = ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false),
        openOnSuccess: Bool = true
    ) {
        let payload = publicationHeartLungfondenPreviewDocument(
            configuration: configuration,
            layout: layout
        )
        let sections = payload.sections
        let hasItems = sections.contains { !$0.items.isEmpty }

        guard hasItems else {
            notice = StoreNotice(
                message: language.text(
                    "There are no eligible publications for the selected Hjärt-Lungfonden period.",
                    "Det finns inga publikationer som kan exporteras för vald Hjärt-Lungfonden-period."
                ),
                tone: .info
            )
            loadError = nil
            return
        }

        performBackgroundExport(
            startMessage: language.text(
                "Exporting Hjärt-Lungfonden list…",
                "Exporterar Hjärt-Lungfonden-lista…"
            ),
            successMessage: language.text(
                "Exported Hjärt-Lungfonden publication document to \(destinationURL.lastPathComponent).",
                "Exporterade Hjärt-Lungfonden-publikationsdokument till \(destinationURL.lastPathComponent)."
            ),
            failureMessage: language.text(
                "Hjärt-Lungfonden publication export failed.",
                "Export av Hjärt-Lungfonden-publikationslista misslyckades."
            ),
            destinationURL: destinationURL,
            openBehavior: openOnSuccess ? .heartLungfonden : .none
        ) {
            try Self.renderHeartLungfondenDocument(payload, to: destinationURL)
        }
    }
}
