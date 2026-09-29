import Foundation

extension PublicationAuthor {
    /// F11: "https://orcid.org/", spaces and lower-case x are normalized away.
    static func normalizedORCID(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://orcid.org/", "http://orcid.org/", "orcid.org/"] where value.lowercased().hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        let compact = value.replacingOccurrences(of: " ", with: "")
        let digits = compact.replacingOccurrences(of: "-", with: "")
        guard digits.count == 16, digits.dropLast().allSatisfy(\.isNumber),
              let last = digits.last, last.isNumber || last == "x" || last == "X" else {
            return value
        }
        let upper = digits.uppercased()
        return stride(from: 0, to: 16, by: 4).map { start in
            let s = upper.index(upper.startIndex, offsetBy: start)
            return String(upper[s..<upper.index(s, offsetBy: 4)])
        }.joined(separator: "-")
    }

    /// ISO 7064 MOD 11-2 check digit.
    static func isValidORCID(_ value: String) -> Bool {
        let digits = value.replacingOccurrences(of: "-", with: "")
        guard digits.count == 16 else { return false }
        var total = 0
        for character in digits.dropLast() {
            guard let d = character.wholeNumberValue else { return false }
            total = (total + d) * 2
        }
        let remainder = total % 11
        let result = (12 - remainder) % 11
        let expected: Character = result == 10 ? "X" : Character(String(result))
        return digits.last == expected
    }
}
