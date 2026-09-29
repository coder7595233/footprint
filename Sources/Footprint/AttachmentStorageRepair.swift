import CryptoKit
import Foundation

extension GrantDataStore {
    struct AttachmentRepairReport {
        var renamed: [String] = []
        var duplicatesMoved: [String] = []
        var conflicts: [String] = []
        var missing: [String] = []
        var isEmpty: Bool { renamed.isEmpty && duplicatesMoved.isEmpty && conflicts.isEmpty && missing.isEmpty }
    }

    /// F1: files saved as "unsafe-id-<sha256>.pdf" (the former null-character
    /// check rejected every id) are renamed to "<id>.pdf". Byte-identical
    /// duplicates are moved to "Ersatta filer"; nothing is deleted.
    func repairAttachmentStorageIfNeeded() -> Bool {
        var report = AttachmentRepairReport()
        var jobs: [(directory: URL, id: String, label: String)] = []
        for publication in publicationRecords
        where publication.finalPDFPath?.trimmedOrNil != nil || publication.finalPDFFilename?.trimmedOrNil != nil {
            jobs.append((Self.publicationPDFsDirectory, publication.id, "Publikation: \(publication.title)"))
        }
        for entry in cvReviewEntries
        where entry.certificatePath?.trimmedOrNil != nil || entry.certificateFilename?.trimmedOrNil != nil {
            jobs.append((Self.reviewCertificatePDFsDirectory, entry.id, "Granskningsintyg: \(entry.displayTitle)"))
        }
        for contribution in cvConferenceContributions
        where contribution.pdfPath?.trimmedOrNil != nil || contribution.pdfFilename?.trimmedOrNil != nil {
            jobs.append((Self.conferenceContributionPDFsDirectory, contribution.id, "Konferensbidrag: \(contribution.displayTitle)"))
        }
        for appearance in cvMediaAppearances
        where appearance.pdfPath?.trimmedOrNil != nil || appearance.pdfFilename?.trimmedOrNil != nil {
            jobs.append((Self.mediaAppearancePDFsDirectory, appearance.id, "Media: \(appearance.displayTitle)"))
        }
        for candidate in doctoralCandidates {
            for document in candidate.documents {
                jobs.append((Self.doctoralCandidatePDFsDirectory, document.id, "Doktorandhandling: \(document.filename ?? document.title)"))
            }
        }

        let fileManager = FileManager.default
        let replacedDirectory = Self.storageDirectory
            .appendingPathComponent("Ersatta filer", isDirectory: true)
            .appendingPathComponent(DateParsers.isoDay.string(from: Date()), isDirectory: true)
        for job in jobs {
            // The target is the name the app itself looks for; for an id that
            // must keep its digest name there is nothing to rename.
            let stem = Self.managedAttachmentFileStem(for: job.id)
            let legacyStem = Self.legacyUnsafeAttachmentFileStem(for: job.id)
            guard stem != legacyStem else { continue }
            if job.id == jobs.first?.id {
                appendStartupDiagnostic("attachment-stem sample=\(job.id) stem=\(stem)")
            }
            let managed = job.directory.appendingPathComponent("\(stem).pdf")
            let unsafe = job.directory.appendingPathComponent("\(legacyStem).pdf")
            let hasManaged = fileManager.fileExists(atPath: managed.path)
            let hasUnsafe = fileManager.fileExists(atPath: unsafe.path)
            if hasUnsafe, !hasManaged {
                do {
                    try fileManager.moveItem(at: unsafe, to: managed)
                    report.renamed.append(job.label)
                } catch {
                    report.conflicts.append("\(job.label): \(error.localizedDescription)")
                }
            } else if hasUnsafe, hasManaged {
                let identical = (try? Data(contentsOf: unsafe)) == (try? Data(contentsOf: managed))
                if identical {
                    do {
                        try fileManager.createDirectory(at: replacedDirectory, withIntermediateDirectories: true)
                        try fileManager.moveItem(at: unsafe, to: replacedDirectory.appendingPathComponent(unsafe.lastPathComponent))
                        report.duplicatesMoved.append(job.label)
                    } catch {
                        report.conflicts.append("\(job.label): \(error.localizedDescription)")
                    }
                } else {
                    report.conflicts.append("\(job.label): två olika filer (\(managed.lastPathComponent) och \(unsafe.lastPathComponent))")
                }
            } else if !hasManaged {
                report.missing.append(job.label)
            }
        }
        writeAttachmentRepairReport(report)
        return !report.renamed.isEmpty || !report.duplicatesMoved.isEmpty
    }

    private func writeAttachmentRepairReport(_ report: AttachmentRepairReport) {
        var lines = ["Bilagekontroll \(DateParsers.isoDay.string(from: Date()))", ""]
        lines.append("Omdöpta till postens id: \(report.renamed.count)")
        lines += report.renamed.map { "  - \($0)" }
        lines.append("Dubbletter flyttade till Ersatta filer: \(report.duplicatesMoved.count)")
        lines += report.duplicatesMoved.map { "  - \($0)" }
        lines.append("Konflikter (inget ändrat): \(report.conflicts.count)")
        lines += report.conflicts.map { "  - \($0)" }
        lines.append("Fil saknades i appens lagring före kopiering: \(report.missing.count)")
        lines += report.missing.map { "  - \($0)" }
        let url = Self.storageDirectory.appendingPathComponent("attachment_repair.log")
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        appendStartupDiagnostic("attachment-repair renamed=\(report.renamed.count) duplicates=\(report.duplicatesMoved.count) conflicts=\(report.conflicts.count) missing=\(report.missing.count)")
        guard !report.isEmpty else { return }
        startupReport = lines.joined(separator: "\n")
        notice = StoreNotice(
            message: language.text(
                "Attachment check: \(report.renamed.count) renamed, \(report.duplicatesMoved.count) duplicates moved, \(report.conflicts.count) conflicts, \(report.missing.count) missing. Report: attachment_repair.log",
                "Bilagekontroll: \(report.renamed.count) omdöpta, \(report.duplicatesMoved.count) dubbletter flyttade, \(report.conflicts.count) konflikter, \(report.missing.count) saknas. Rapport: attachment_repair.log"
            ),
            tone: .info
        )
    }
}
