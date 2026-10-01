import Foundation

func safeExternalURL(_ url: URL?) -> URL? {
    guard let url,
          let scheme = url.scheme?.lowercased() else {
        return nil
    }

    switch scheme {
    case "http", "https":
        guard url.host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
    case "mailto":
        let recipient = String(url.absoluteString.dropFirst("mailto:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decodedRecipient = recipient.removingPercentEncoding ?? recipient
        // No "?": a query part can add hidden recipients (bcc) or a body.
        guard !recipient.isEmpty,
              !decodedRecipient.contains("?"),
              !decodedRecipient.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0)
                      || CharacterSet.controlCharacters.contains($0)
              }) else {
            return nil
        }
    default:
        return nil
    }
    return url
}

func normalizedWebLinkURL(_ rawValue: String?) -> URL? {
    guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }

    let normalized = trimmed
        .replacingOccurrences(of: #"[\u{200B}\u{200C}\u{200D}]"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let lowercased = normalized.lowercased()

    if lowercased.hasPrefix("doi:") || lowercased.hasPrefix("10.") {
        return safeExternalURL(normalizedIdentifierURL(raw: normalized, kind: .doi))
    }

    if lowercased.hasPrefix("orcid.org/")
        || lowercased.hasPrefix("https://orcid.org/")
        || lowercased.hasPrefix("http://orcid.org/") {
        return safeExternalURL(normalizedIdentifierURL(raw: normalized, kind: .orcid))
    }

    if let direct = URL(string: normalized), direct.scheme != nil {
        return safeExternalURL(direct)
    }

    return safeExternalURL(URL(string: "https://\(normalized)"))
}
