import CryptoKit
import PDFKit
import SwiftUI

/// Shared PDF preview bridge with content-aware invalidation.
///
/// File previews include modification metadata so replacing a PDF at the same
/// path refreshes the view. In-memory PDFs use SHA-256 rather than a short
/// prefix, avoiding stale previews for equal-sized documents.
struct AppPDFDocumentView: NSViewRepresentable {
    let pdfURL: URL?
    let pdfData: Data?

    final class Coordinator {
        var lastSignature: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = AppRuntime.usesRenewedChrome ? .white : .windowBackgroundColor
        view.document = resolvedDocument()
        context.coordinator.lastSignature = contentSignature
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        let signature = contentSignature
        guard context.coordinator.lastSignature != signature else { return }
        context.coordinator.lastSignature = signature
        nsView.document = resolvedDocument()
    }

    private var contentSignature: String {
        if let pdfData {
            return "data:\(SHA256.hash(data: pdfData).description)"
        }
        guard let pdfURL else { return "empty" }
        let values = try? pdfURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
            .fileResourceIdentifierKey,
        ])
        return [
            "url",
            pdfURL.standardizedFileURL.path,
            values?.contentModificationDate?.timeIntervalSinceReferenceDate.description ?? "-",
            values?.fileSize.map(String.init) ?? "-",
            String(describing: values?.fileResourceIdentifier),
        ].joined(separator: ":")
    }

    private func resolvedDocument() -> PDFDocument? {
        if let pdfData {
            return PDFDocument(data: pdfData)
        }
        guard let pdfURL,
              FileManager.default.fileExists(atPath: pdfURL.path) else {
            return nil
        }
        return PDFDocument(url: pdfURL)
    }
}
