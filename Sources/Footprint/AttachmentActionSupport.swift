import AppKit
import Foundation

enum AttachmentActionError: LocalizedError, Equatable {
    case unsupportedPDF
    case emptyFile
    case fileCouldNotBeOpened

    var errorDescription: String? {
        switch self {
        case .unsupportedPDF:
            return "The selected file is not a PDF."
        case .emptyFile:
            return "The selected PDF is empty."
        case .fileCouldNotBeOpened:
            return "macOS could not open the selected file."
        }
    }
}

/// A name for a temporary copy of an attached PDF: only the last part of the
/// stored name (no folders, so it cannot be written outside the temporary
/// folder), safe characters only, and always ending in ".pdf".
func safeTemporaryPDFFilename(_ stored: String?, fallback: String) -> String {
    let lastPart = stored.flatMap { URL(fileURLWithPath: $0).lastPathComponent.trimmedOrNil } ?? fallback
    let stem = (lastPart as NSString).deletingPathExtension
    let allowed = stem.unicodeScalars.map { scalar -> String in
        CharacterSet.alphanumerics.contains(scalar) || " -_.".unicodeScalars.contains(scalar) ? String(scalar) : "_"
    }.joined().trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    let fallbackStem = (fallback as NSString).deletingPathExtension
    return (allowed.isEmpty ? fallbackStem : String(allowed.prefix(120))) + ".pdf"
}

func loadPDFDataForUserAction(from url: URL) throws -> Data {
    guard url.pathExtension.lowercased() == "pdf" else {
        throw AttachmentActionError.unsupportedPDF
    }
    let data = try Data(contentsOf: url)
    guard !data.isEmpty else {
        throw AttachmentActionError.emptyFile
    }
    let headerWindow = data.prefix(1_024)
    guard headerWindow.range(of: Data("%PDF-".utf8)) != nil else {
        throw AttachmentActionError.unsupportedPDF
    }
    return data
}

extension GrantDataStore {
    func reportFileActionFailure(_ message: String, error: Error) {
        loadError = error.localizedDescription
        notice = StoreNotice(message: message, tone: .error)
    }

    /// Opens an attached PDF. Every attachment the app opens is a PDF, and
    /// the location can come from an imported database, so anything that is
    /// not a PDF (an app, a script, a web page) is refused instead of being
    /// handed to macOS to run.
    @discardableResult
    func openFileForUserAction(_ url: URL, failureMessage: String) -> Bool {
        do {
            _ = try loadPDFDataForUserAction(from: url)
        } catch {
            reportFileActionFailure(failureMessage, error: error)
            return false
        }
        guard NSWorkspace.shared.open(url) else {
            reportFileActionFailure(failureMessage, error: AttachmentActionError.fileCouldNotBeOpened)
            return false
        }
        loadError = nil
        return true
    }
}
