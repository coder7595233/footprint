import CryptoKit
import Foundation

/// Pure privacy boundary for diagnostics that are persisted outside the
/// encrypted/canonical application data.
enum PerformanceDiagnosticPrivacy {
    private static let sensitiveKeyExpression = try! NSRegularExpression(
        pattern: #"(?i)\b(id|author|project|publication|journal|organization|application|candidate|student|title|name|raw)=.*?(?=\s+[A-Za-z][A-Za-z0-9_-]*=|$)"#
    )
    private static let uuidExpression = try! NSRegularExpression(
        pattern: #"[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[1-5][A-Fa-f0-9]{3}-[89ABab][A-Fa-f0-9]{3}-[A-Fa-f0-9]{12}"#
    )
    private static let emailExpression = try! NSRegularExpression(
        pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive]
    )

    static func redact(_ message: String) -> String {
        var redacted = message
        redacted = replacingMatches(
            in: redacted,
            expression: sensitiveKeyExpression
        ) { match in
            let key = String(match.prefix { $0 != "=" })
            let value = match.dropFirst(key.count + 1)
            return "\(key)=redacted-\(digest(String(value)))"
        }
        redacted = replacingMatches(
            in: redacted,
            expression: uuidExpression
        ) { "redacted-\(digest($0))" }
        redacted = replacingMatches(
            in: redacted,
            expression: emailExpression
        ) { "redacted-\(digest($0))" }
        return redacted
    }

    private static func replacingMatches(
        in value: String,
        expression: NSRegularExpression,
        replacement: (String) -> String
    ) -> String {
        var result = value
        let matches = expression.matches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        )
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let matchedValue = String(result[range])
            result.replaceSubrange(range, with: replacement(matchedValue))
        }
        return result
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
