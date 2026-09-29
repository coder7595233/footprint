import Foundation

struct SearchFilterQuery {
    let raw: String
    let includedTerms: [String]
    let excludedTerms: [String]

    init(raw: String) {
        self.raw = raw
        var includedTerms: [String] = []
        var excludedTerms: [String] = []

        let normalizedRaw = String(raw.map(Self.canonicalDash))
        let scanner = normalizedRaw.unicodeScalars
        var tokenScalars: [UnicodeScalar] = []

        func flushToken() {
            guard !tokenScalars.isEmpty else { return }
            let token = String(String.UnicodeScalarView(tokenScalars))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            tokenScalars.removeAll(keepingCapacity: true)
            guard !token.isEmpty else { return }

            if let first = token.first, Self.isDash(first) {
                let excludedRaw = String(token.drop(while: Self.isDash))
                let excluded = normalizedSearchFilterToken(excludedRaw, stripLeadingDash: true)
                if !excluded.isEmpty {
                    excludedTerms.append(excluded)
                }
            } else {
                let included = normalizedSearchFilterToken(token, stripLeadingDash: false)
                if !included.isEmpty {
                    includedTerms.append(included)
                }
            }
        }

        for scalar in scanner {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                flushToken()
            } else {
                tokenScalars.append(scalar)
            }
        }
        flushToken()

        self.includedTerms = includedTerms
        self.excludedTerms = excludedTerms
    }

    var isEmpty: Bool {
        includedTerms.isEmpty && excludedTerms.isEmpty
    }

    func isNarrowing(over previous: SearchFilterQuery) -> Bool {
        guard includedTerms.count >= previous.includedTerms.count,
              excludedTerms.count >= previous.excludedTerms.count else {
            return false
        }
        let currentIncluded = Set(includedTerms)
        let currentExcluded = Set(excludedTerms)
        return Set(previous.includedTerms).isSubset(of: currentIncluded)
            && Set(previous.excludedTerms).isSubset(of: currentExcluded)
            && (currentIncluded != Set(previous.includedTerms) || currentExcluded != Set(previous.excludedTerms))
    }

    func matches(normalizedHaystack: String) -> Bool {
        guard excludedTerms.allSatisfy({ !normalizedHaystack.contains($0) }) else {
            return false
        }
        return includedTerms.allSatisfy { normalizedHaystack.contains($0) }
    }

    func matches(haystack: String) -> Bool {
        matches(normalizedHaystack: normalizedSearchFilterText(haystack))
    }

    private static func isDash(_ character: Character) -> Bool {
        switch character {
        case "-", "‐", "‑", "‒", "–", "—", "―", "−", "﹘", "﹣", "－":
            return true
        default:
            return false
        }
    }

    private static func canonicalDash(_ character: Character) -> Character {
        isDash(character) ? "-" : character
    }
}

// Collapses whitespace runs to single spaces and trims the ends in one
// scalar pass. The `\s+` NSRegularExpression it replaces ran tens of
// thousands of times per publication index refresh. ASCII fast path
// first: constructing/consulting CharacterSet per scalar is slower than
// the regex was.
func collapsingWhitespaceRuns(_ value: String) -> String {
    var result = String.UnicodeScalarView()
    result.reserveCapacity(value.unicodeScalars.count)
    var pendingSpace = false
    for scalar in value.unicodeScalars {
        let isWhitespace = scalar.value == 0x20
            || (scalar.value >= 0x09 && scalar.value <= 0x0D)
            || (scalar.value > 0x7F && scalar.properties.isWhitespace)
        if isWhitespace {
            pendingSpace = !result.isEmpty
        } else {
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.append(scalar)
        }
    }
    return String(result)
}

func normalizedSearchFilterText(_ value: String) -> String {
    collapsingWhitespaceRuns(
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    )
}

private func normalizedSearchFilterToken(_ value: String, stripLeadingDash: Bool) -> String {
    let normalized = normalizedSearchFilterText(value)
    let scalarsToTrim = CharacterSet.punctuationCharacters
        .union(.symbols)
        .subtracting(CharacterSet(charactersIn: "-"))
    let trimmed = normalized.trimmingCharacters(in: scalarsToTrim)
    if stripLeadingDash {
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
    return trimmed
}
