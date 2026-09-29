import AppKit
import Foundation

extension GrantDataStore {
    func publicationCustomPreviewDocument(
        configuration: PublicationCustomExportConfiguration,
        layout: ExportDocumentLayoutOptions
    ) -> PublicationAMAExportDocument {
        let options = publicationExportOptions(
            from: configuration.options,
            underlineDoctoralMainSupervisor: configuration.underlineDoctoralMainSupervisor,
            underlineDoctoralCoSupervisor: configuration.underlineDoctoralCoSupervisor
        )
        return publicationAMAPreviewDocument(
            title: language.text("Publications list", "Publikationslista"),
            options: options,
            includedSections: configuration.includedSections,
            exportLanguage: language,
            layout: layout
        )
    }

    func publicationAMAPreviewDocument(
        title: String,
        options: PublicationExportOptions,
        includedSections: Set<PublicationExportSectionKey>,
        exportLanguage: AppLanguage,
        layout: ExportDocumentLayoutOptions
    ) -> PublicationAMAExportDocument {
        let (headerText, footerText) = layoutHeaderFooterTexts(layout, exportLanguage: exportLanguage)
        let underlinedNames = resolvedUnderlinedPublicationNames(options: options)
        return PublicationAMAExportDocument(
            title: title,
            highlightName: options.boldOwnName ? (currentUserAuthor()?.name ?? "") : "",
            underlinedNames: underlinedNames,
            sections: amaSections(
                exportLanguage: exportLanguage,
                options: options,
                includedSections: includedSections
            ),
            headerText: headerText,
            footerText: footerText,
            includePageNumbers: layout.includePageNumbers
        )
    }

    func teachingMeritsPreviewDocument() -> TeachingMeritsExportDocument {
        teachingMeritsExportDocument()
    }

    nonisolated static func teachingMeritsTemplateURL() -> URL? {
        let configuredSources = [
            ProcessInfo.processInfo.environment["FOOTPRINT_TEACHING_MERITS_TEMPLATE"],
            UserDefaults.standard.string(forKey: AppRuntime.scopedDefaultsKey("TeachingMeritsTemplatePath")),
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for path in configuredSources where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let bundledCandidates = [
            "TeachingMeritsTemplate.docx",
            "Mall för pedagogiska meriter docentur_befordran.docx",
        ]
        for fileName in bundledCandidates {
            if let bundledURL = try? Self.bundledResourceURL(named: fileName) {
                return bundledURL
            }
        }

        return nil
    }

    func customCVPreviewDocument(
        configuration: CVCustomExportConfiguration,
        layout: ExportDocumentLayoutOptions
    ) -> CVExportDocument {
        var payload = cvExportDocument(
            style: configuration.style,
            exportLanguage: configuration.exportLanguage,
            includedSections: configuration.includedSections,
            publicationOptions: configuration.publicationOptions,
            includeCollaboratorGrants: configuration.includeCollaboratorGrants,
            underlineDoctoralMainSupervisor: configuration.underlineDoctoralMainSupervisor,
            underlineDoctoralCoSupervisor: configuration.underlineDoctoralCoSupervisor
        )
        applyLayout(layout, to: &payload, exportLanguage: configuration.exportLanguage)
        return payload
    }

    func publicationVetenskapsradetPreviewDocument(
        selectedOutputs: [CVVRSelectedOutput],
        layout: ExportDocumentLayoutOptions
    ) -> CVExportDocument {
        var payload = cvVetenskapsradetExportDocument(
            language: language,
            selectedOutputs: selectedOutputs
        )
        applyLayout(layout, to: &payload, exportLanguage: language)
        return payload
    }
}
