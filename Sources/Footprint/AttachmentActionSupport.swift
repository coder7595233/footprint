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

    @discardableResult
    func openFileForUserAction(_ url: URL, failureMessage: String) -> Bool {
        guard NSWorkspace.shared.open(url) else {
            reportFileActionFailure(failureMessage, error: AttachmentActionError.fileCouldNotBeOpened)
            return false
        }
        loadError = nil
        return true
    }
}
