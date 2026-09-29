import Foundation

/// Lightweight inline markup for the protocol free-text field: `**bold**`,
/// `*italic*`, `__underline__`, backslash escapes, and literal "• " line
/// prefixes for bullet lists. The field keeps its plain-String storage —
/// legacy texts contain no markers and parse unchanged — while the editor
/// works on a `CVRichTextDocument` and the project document renders real
/// rich-text runs in both the HTML preview/PDF and the Word export.
enum ProtocolMarkup {
    static let bulletPrefix = "• "

    /// One prefix per list level; the glyph encodes the level so nesting
    /// survives the plain-String storage and renders everywhere.
    static let bulletPrefixes = ["• ", "◦ ", "▪ "]

    static var maxBulletLevel: Int { bulletPrefixes.count }

    /// 1-based bullet level of a line, or nil for non-bulleted lines.
    static func bulletLevel(ofLine line: String) -> Int? {
        for (index, prefix) in bulletPrefixes.enumerated() where line.hasPrefix(prefix) {
            return index + 1
        }
        return nil
    }

    static func bulletPrefix(forLevel level: Int) -> String {
        bulletPrefixes[max(0, min(bulletPrefixes.count - 1, level - 1))]
    }

    static func document(from markup: String) -> CVRichTextDocument {
        var paragraphs = markup
            .components(separatedBy: "\n")
            .map { CVRichTextParagraph(runs: runs(fromLine: $0)) }
        if paragraphs.isEmpty {
            paragraphs = [CVRichTextParagraph()]
        }
        return CVRichTextDocument(paragraphs: paragraphs)
    }

    static func markup(from document: CVRichTextDocument) -> String {
        document.paragraphs.map { paragraph in
            paragraph.runs.map { run -> String in
                let escaped = escape(run.text)
                guard !escaped.isEmpty else { return "" }
                var prefix = ""
                var suffix = ""
                if run.bold {
                    prefix += "**"
                    suffix = "**" + suffix
                }
                if run.italic {
                    prefix += "*"
                    suffix = "*" + suffix
                }
                if run.underline {
                    prefix += "__"
                    suffix = "__" + suffix
                }
                return prefix + escaped + suffix
            }
            .joined()
        }
        .joined(separator: "\n")
    }

    static func exportParagraphs(from markup: String) -> [CVExportRichTextParagraph] {
        document(from: markup).paragraphs.map { paragraph in
            CVExportRichTextParagraph(
                runs: paragraph.runs.map { run in
                    CVExportRichTextRun(
                        text: run.text,
                        bold: run.bold,
                        italic: run.italic,
                        underline: run.underline
                    )
                }
            )
        }
    }

    private static func runs(fromLine line: String) -> [CVRichTextRun] {
        var runs: [CVRichTextRun] = []
        var current = ""
        var bold = false
        var italic = false
        var underline = false

        func flush() {
            guard !current.isEmpty else { return }
            runs.append(CVRichTextRun(text: current, bold: bold, italic: italic, underline: underline))
            current = ""
        }

        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)
            if character == "\\", next < line.endIndex {
                current.append(line[next])
                index = line.index(after: next)
                continue
            }
            if character == "*" {
                if next < line.endIndex, line[next] == "*" {
                    flush()
                    bold.toggle()
                    index = line.index(after: next)
                } else {
                    flush()
                    italic.toggle()
                    index = next
                }
                continue
            }
            if character == "_", next < line.endIndex, line[next] == "_" {
                flush()
                underline.toggle()
                index = line.index(after: next)
                continue
            }
            current.append(character)
            index = next
        }
        flush()
        return runs
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "__", with: "_\\_")
    }
}
