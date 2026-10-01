import Foundation

/// Writes a readable copy of Footprint's data to a folder the user chooses
/// in Settings > Storage (for example a Google Drive or OneDrive folder):
///
///   data/          one JSON document per area and _manifest.json
///   attachments/   copies of the app's attachments (PDFs etc.), one subfolder per kind
///
/// Called after every successful save (see DataStore.exportToFootprintExportAfterWrite).
/// Runs on its own queue and can never stop or delay the save; errors are only logged.
/// Nothing is deleted in the export: an attachment removed in the app stays in attachments/.
///
/// Round 14 (user decision 2026-10-01): off unless switched on in Settings,
/// and only to the folder chosen there. It used to be on by default (only an
/// Info.plist key turned it off) and wrote to ~/Google Drive/footprint_export,
/// or to a folder named by an environment variable.
final class FootprintExportWriter: @unchecked Sendable {
    static let shared = FootprintExportWriter()

    static var enabledDefaultsKey: String { AppRuntime.scopedDefaultsKey("FootprintExport.Enabled") }
    static var folderDefaultsKey: String { AppRuntime.scopedDefaultsKey("FootprintExport.FolderPath") }

    /// Dokument som aldrig exporteras (appinställningar, inte data).
    static let excludedKeys: Set<String> = ["app_settings"]

    /// Fält som tas bort ur ett dokument före export, per dokument. Tomt = allt exporteras.
    static let strippedFields: [String: Set<String>] = [:]

    /// Undermappar i appens lagringsmapp som är bilagor: namn som slutar på " PDFs" eller " Files",
    /// utom säkerhetskopior.
    static let excludedStorageFolders: Set<String> = ["Backups", "ManualBackups"]

    private let queue = DispatchQueue(label: "footprint.export", qos: .utility)
    private let lock = NSLock()
    private var didFullExport = false

    /// The folder chosen in Settings, or nil when none is chosen.
    static var chosenFolder: URL? {
        guard let raw = UserDefaults.standard.string(forKey: folderDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    static var isSwitchedOn: Bool {
        UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    var isEnabled: Bool {
        // F34: a test run never exports, whatever started it.
        if TestProcessDetection.isRunningTests { return false }
        return Self.isSwitchedOn && Self.chosenFolder != nil
    }

    /// Saves the choice from Settings. A new folder or switching on gets a
    /// full export at the next save.
    func configure(enabled: Bool, folder: URL?) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
        if let folder {
            UserDefaults.standard.set(folder.standardizedFileURL.path, forKey: Self.folderDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.folderDefaultsKey)
        }
        lock.lock(); didFullExport = false; lock.unlock()
    }

    var rootDirectory: URL {
        Self.chosenFolder ?? FileManager.default.temporaryDirectory.appendingPathComponent("footprint_export_unset", isDirectory: true)
    }

    var dataDirectory: URL { rootDirectory.appendingPathComponent("data", isDirectory: true) }
    var attachmentsDirectory: URL { rootDirectory.appendingPathComponent("attachments", isDirectory: true) }

    /// Sant tills en fullständig export har gjorts i den här körningen av appen.
    var needsFullExport: Bool {
        lock.lock(); defer { lock.unlock() }
        return !didFullExport
    }

    /// Exporterar dokumenten och speglar bilagorna från appens lagringsmapp.
    func export(_ documents: [(key: String, data: Data)], full: Bool, storageDirectory: URL?) {
        guard isEnabled else { return }
        let canonical = Set(FootprintStorageContract.canonicalDocumentKeys)
        let selected = documents.filter { canonical.contains($0.key) && !Self.excludedKeys.contains($0.key) }
        if full {
            lock.lock(); didFullExport = true; lock.unlock()
        }
        let dataDirectory = self.dataDirectory
        let attachmentsDirectory = self.attachmentsDirectory
        queue.async {
            do {
                if !selected.isEmpty {
                    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
                    for document in selected {
                        let url = dataDirectory.appendingPathComponent("\(document.key).json")
                        try Self.prettyPrinted(document.data, stripping: Self.strippedFields[document.key] ?? [])
                            .write(to: url, options: .atomic)
                    }
                }
                var attachmentSummary: [[String: Any]] = []
                if let storageDirectory {
                    attachmentSummary = try Self.mirrorAttachments(from: storageDirectory, to: attachmentsDirectory)
                }
                if !selected.isEmpty || !attachmentSummary.isEmpty {
                    try Self.writeManifest(in: dataDirectory, attachments: attachmentSummary)
                }
            } catch {
                NSLog("Footprint export failed: %@", error.localizedDescription)
            }
        }
    }

    /// "Publication PDFs" -> "publication_pdfs"
    static func folderSlug(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    static func isAttachmentFolder(_ name: String) -> Bool {
        !excludedStorageFolders.contains(name) && (name.hasSuffix(" PDFs") || name.hasSuffix(" Files"))
    }

    /// Kopierar nya och ändrade bilagor (jämför storlek). Returnerar en sammanställning per mapp.
    private static func mirrorAttachments(from storage: URL, to target: URL) throws -> [[String: Any]] {
        let fileManager = FileManager.default
        let folders = (try? fileManager.contentsOfDirectory(
            at: storage,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var summary: [[String: Any]] = []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDirectory = (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory, isAttachmentFolder(folder.lastPathComponent) else { continue }
            let destinationFolder = target.appendingPathComponent(folderSlug(folder.lastPathComponent), isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            let folderPath = folder.standardizedFileURL.path
            var fileCount = 0
            var byteCount = 0
            var copiedCount = 0
            for case let file as URL in enumerator {
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true else { continue }
                let size = values?.fileSize ?? 0
                let filePath = file.standardizedFileURL.path
                let relative = filePath.hasPrefix(folderPath + "/")
                    ? String(filePath.dropFirst(folderPath.count + 1))
                    : file.lastPathComponent
                let destination = destinationFolder.appendingPathComponent(relative)
                fileCount += 1
                byteCount += size
                if let existing = try? destination.resourceValues(forKeys: [.fileSizeKey]), existing.fileSize == size {
                    continue
                }
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: file, to: destination)
                copiedCount += 1
            }
            summary.append([
                "folder": folderSlug(folder.lastPathComponent),
                "source": folder.lastPathComponent,
                "files": fileCount,
                "bytes": byteCount,
                "copiedThisRun": copiedCount,
            ])
        }
        return summary
    }

    private static func prettyPrinted(_ data: Data, stripping fields: Set<String>) -> Data {
        guard var object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return fields.isEmpty ? data : Data("{}".utf8)
        }
        if !fields.isEmpty, var dictionary = object as? [String: Any] {
            for field in fields { dictionary.removeValue(forKey: field) }
            object = dictionary
        }
        guard
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
              )
        else { return fields.isEmpty ? data : Data("{}".utf8) }
        return pretty
    }

    private static func writeManifest(in directory: URL, attachments: [[String: Any]]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        let formatter = ISO8601DateFormatter()
        var entries: [[String: Any]] = []
        for url in files where url.pathExtension == "json" && url.lastPathComponent != "_manifest.json" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            entries.append([
                "document": url.deletingPathExtension().lastPathComponent,
                "bytes": values?.fileSize ?? 0,
                "modified": values?.contentModificationDate.map { formatter.string(from: $0) } ?? "",
            ])
        }
        entries.sort { ($0["document"] as? String ?? "") < ($1["document"] as? String ?? "") }
        let manifest: [String: Any] = [
            "exportedAt": formatter.string(from: Date()),
            "storageContract": FootprintStorageContract.version,
            "documents": entries,
            "attachments": attachments,
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("_manifest.json"), options: .atomic)
    }
}
