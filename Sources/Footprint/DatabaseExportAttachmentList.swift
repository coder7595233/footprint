import Foundation

/// F1b: one line in the attachment list ("bilagor.csv") written next to the
/// payload in a database export package. It says which record each attached
/// file belongs to, where the file lies in the package and whether it is
/// really there. The list is for people only: import never reads it.
struct DatabaseExportAttachmentListRow: Equatable, Sendable {
    let register: String
    let recordID: String
    let label: String
    let originalFilename: String
    let packagePath: String
    let fileExists: Bool
}

extension GrantDataStore {
    nonisolated static let databaseExportAttachmentListFileName = "bilagor.csv"

    /// Builds the rows from the exported records and the attachment folders
    /// already copied into `payloadDirectory`. Paths in the rows are relative
    /// to the package folder (they start with `payloadDirectoryName`).
    nonisolated static func databaseExportAttachmentListRows(
        snapshot: Snapshot,
        payloadDirectory: URL,
        payloadDirectoryName: String,
        language: AppLanguage
    ) -> [DatabaseExportAttachmentListRow] {
        var rows: [DatabaseExportAttachmentListRow] = []

        func managedRow(
            register: String,
            directoryName: String,
            id: String,
            label: String?,
            originalFilename: String?
        ) -> DatabaseExportAttachmentListRow {
            let directory = payloadDirectory.appendingPathComponent(directoryName, isDirectory: true)
            let candidates = [
                "\(managedAttachmentFileStem(for: id)).pdf",
                "\(legacyUnsafeAttachmentFileStem(for: id)).pdf",
            ]
            let found = candidates.first { name in
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
            }
            let fileName = found ?? candidates[0]
            let original = originalFilename?.trimmedOrNil ?? ""
            return DatabaseExportAttachmentListRow(
                register: register,
                recordID: id,
                label: label ?? original.nonEmpty ?? id,
                originalFilename: original,
                packagePath: [payloadDirectoryName, directoryName, fileName].joined(separator: "/"),
                fileExists: found != nil
            )
        }

        let publicationRegister = language.text("Publications", "Publikationer")
        for publication in snapshot.publicationRecords
        where publication.finalPDFPath?.trimmedOrNil != nil || publication.finalPDFFilename?.trimmedOrNil != nil {
            rows.append(managedRow(
                register: publicationRegister,
                directoryName: "Publication PDFs",
                id: publication.id,
                label: AttachmentLabels.publication(publication, language: language),
                originalFilename: publication.finalPDFFilename
                    ?? publication.finalPDFPath.map { URL(fileURLWithPath: $0).lastPathComponent }
            ))
        }

        let reviewRegister = language.text("Review certificates", "Granskningsintyg")
        for entry in snapshot.cvReviewEntries
        where entry.certificatePath?.trimmedOrNil != nil
            || entry.certificateFilename?.trimmedOrNil != nil
            || entry.certificatePDFData != nil {
            rows.append(managedRow(
                register: reviewRegister,
                directoryName: "Review Certificate PDFs",
                id: entry.id,
                label: AttachmentLabels.reviewCertificate(entry, language: language),
                originalFilename: entry.certificateFilename
                    ?? entry.certificatePath.map { URL(fileURLWithPath: $0).lastPathComponent }
            ))
        }

        let contributionRegister = language.text("Conference contributions", "Konferensbidrag")
        for contribution in snapshot.cvConferenceContributions
        where contribution.pdfPath?.trimmedOrNil != nil || contribution.pdfFilename?.trimmedOrNil != nil {
            rows.append(managedRow(
                register: contributionRegister,
                directoryName: "Conference Contribution PDFs",
                id: contribution.id,
                label: AttachmentLabels.conferenceContribution(contribution, language: language),
                originalFilename: contribution.pdfFilename
                    ?? contribution.pdfPath.map { URL(fileURLWithPath: $0).lastPathComponent }
            ))
        }

        let mediaRegister = language.text("Media", "Media")
        for appearance in snapshot.cvMediaAppearances {
            let label = AttachmentLabels.mediaAppearance(appearance, language: language)
            if appearance.pdfPath?.trimmedOrNil != nil || appearance.pdfFilename?.trimmedOrNil != nil {
                rows.append(managedRow(
                    register: mediaRegister,
                    directoryName: "Media Appearance PDFs",
                    id: appearance.id,
                    label: label,
                    originalFilename: appearance.pdfFilename
                        ?? appearance.pdfPath.map { URL(fileURLWithPath: $0).lastPathComponent }
                ))
            }
            // Older media rows kept their files under a stored name of their own.
            for attachment in appearance.attachments {
                let storedName = attachment.storedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
                let isPlainName = !storedName.isEmpty
                    && storedName != "."
                    && storedName != ".."
                    && !storedName.contains("/")
                    && !storedName.contains("\\")
                let directoryName = "Media Appearance Files"
                let exists = isPlainName && FileManager.default.fileExists(
                    atPath: payloadDirectory
                        .appendingPathComponent(directoryName, isDirectory: true)
                        .appendingPathComponent(storedName)
                        .path
                )
                rows.append(DatabaseExportAttachmentListRow(
                    register: mediaRegister,
                    recordID: appearance.id,
                    label: label ?? attachment.filename.trimmedOrNil ?? appearance.id,
                    originalFilename: attachment.filename.trimmedOrNil ?? "",
                    packagePath: [payloadDirectoryName, directoryName, storedName].joined(separator: "/"),
                    fileExists: exists
                ))
            }
        }

        let doctoralRegister = language.text("Doctoral candidates", "Doktorander")
        for candidate in snapshot.doctoralCandidates {
            for document in candidate.documents
            where document.path?.trimmedOrNil != nil || document.filename?.trimmedOrNil != nil {
                rows.append(managedRow(
                    register: doctoralRegister,
                    directoryName: "Doctoral Candidate PDFs",
                    id: document.id,
                    label: AttachmentLabels.doctoralDocument(
                        document,
                        candidateName: candidate.candidateName,
                        language: language
                    ),
                    originalFilename: document.filename
                        ?? document.path.map { URL(fileURLWithPath: $0).lastPathComponent }
                ))
            }
        }

        return rows
    }

    /// Semicolon-separated with a byte order mark so that Excel with Swedish
    /// settings opens it directly with åäö intact.
    nonisolated static func databaseExportAttachmentListCSV(
        rows: [DatabaseExportAttachmentListRow],
        language: AppLanguage
    ) -> String {
        let header = [
            language.text("Register", "Register"),
            language.text("Record id", "Post-id"),
            language.text("Record label", "Postens etikett"),
            language.text("Original file name", "Ursprungligt filnamn"),
            language.text("File in package", "Fil i paketet"),
            language.text("File exists", "Filen finns"),
        ]
        let yes = language.text("yes", "ja")
        let no = language.text("no", "nej")
        var lines = [header.map(csvField).joined(separator: ";")]
        for row in rows {
            lines.append([
                row.register,
                row.recordID,
                row.label,
                row.originalFilename,
                row.packagePath,
                row.fileExists ? yes : no,
            ].map(csvField).joined(separator: ";"))
        }
        return "\u{FEFF}" + lines.joined(separator: "\n") + "\n"
    }

    nonisolated private static func csvField(_ value: String) -> String {
        let needsQuotes = value.contains(";")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    nonisolated static func writeDatabaseExportAttachmentList(
        snapshot: Snapshot,
        packageDirectory: URL,
        payloadDirectoryName: String,
        language: AppLanguage
    ) throws {
        let rows = databaseExportAttachmentListRows(
            snapshot: snapshot,
            payloadDirectory: packageDirectory.appendingPathComponent(payloadDirectoryName, isDirectory: true),
            payloadDirectoryName: payloadDirectoryName,
            language: language
        )
        let csv = databaseExportAttachmentListCSV(rows: rows, language: language)
        try Data(csv.utf8).write(
            to: packageDirectory.appendingPathComponent(databaseExportAttachmentListFileName),
            options: .atomic
        )
    }
}
