import AppKit
import Foundation
import UniformTypeIdentifiers

extension GrantDataStore {
    enum MissingAttachmentTarget {
        case publication(String)
        case reviewEntry(String)
    }

    /// F18: which record a "missing file" integrity issue belongs to, when the file can be chosen again.
    func missingAttachmentTarget(for issue: IntegrityIssue) -> MissingAttachmentTarget? {
        guard issue.kind == .brokenLink else { return nil }
        if issue.recordID.hasPrefix("review:"),
           issue.subtitle == language.text("Missing review certificate file", "Saknar reviewintygsfil") {
            return .reviewEntry(String(issue.recordID.dropFirst("review:".count)))
        }
        if issue.destination == .publications,
           issue.subtitle == language.text("Missing linked PDF file", "Saknar länkad PDF-fil") {
            return .publication(issue.recordID)
        }
        return nil
    }

    /// F18: lets the user pick the file for a missing attachment; it is stored under the record's id.
    func chooseFileForMissingAttachment(_ issue: IntegrityIssue) {
        guard let target = missingAttachmentTarget(for: issue) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = language.text("Choose PDF", "Välj PDF")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try loadPDFDataForUserAction(from: url)
            switch target {
            case .publication(let id):
                guard var publication = publicationRecords.first(where: { $0.id == id }) else { return }
                let managedURL = try Self.persistManagedPublicationPDF(data: data, forPublicationID: id)
                publication.finalPDFFilename = url.lastPathComponent
                publication.finalPDFPath = Self.portableAttachmentPath(for: managedURL)
                savePublication(publication, silently: true)
            case .reviewEntry(let id):
                guard var entry = cvReviewEntries.first(where: { $0.id == id }) else { return }
                let managedURL = try Self.persistManagedCVReviewCertificatePDF(data: data, forReviewEntryID: id)
                entry.certificateFilename = url.lastPathComponent
                entry.certificatePath = Self.portableAttachmentPath(for: managedURL)
                entry.certificatePDFData = nil
                autosaveCVReviewEntry(entry)
            }
        } catch {
            reportFileActionFailure(
                language.text("Could not attach the PDF file.", "Kunde inte bifoga PDF-filen."),
                error: error
            )
        }
    }
}
