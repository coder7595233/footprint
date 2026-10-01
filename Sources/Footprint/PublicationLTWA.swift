import Foundation

enum PublicationLTWA {
    static func shortName(for title: String) -> String {
        PublicationLTWAStore.shared.shortName(for: title)
    }

    /// Loads the shared LTWA rule store. The first access otherwise happens
    /// inside the journal/Excel export paths, where the bundled lexicon's cold
    /// read can block the main thread for seconds under endpoint-security
    /// scanning — call this from a background task during launch instead.
    static func prewarmSharedStore() {
        _ = PublicationLTWAStore.shared
    }
}

extension PublicationJournal {
    var resolvedISSNLTWAAbbreviatedName: String {
        issnLTWAAbbreviatedName.nonEmpty ?? PublicationLTWA.shortName(for: name)
    }
}

private struct PublicationLTWAEntry: Decodable {
    let word: String
    let abbreviation: String
}

private struct PublicationLTWARule {
    let word: String
    let key: String
    let abbreviation: String
}

private struct PublicationLTWATitleToken {
    enum Kind {
        case word
        case acronym
        case punctuation
    }

    let kind: Kind
    let text: String
}

private struct PublicationLTWAWordInfo {
    let tokenIndex: Int
    let wordIndex: Int
    let text: String
    let key: String
    let isAcronym: Bool
}

private final class PublicationLTWAStore: @unchecked Sendable {
    static let shared = PublicationLTWAStore()

    private let exactRules: [String: PublicationLTWARule]
    private let prefixRules: [PublicationLTWARule]
    private let suffixRules: [PublicationLTWARule]
    private let infixRules: [PublicationLTWARule]
    private let cacheLock = NSLock()
    private var shortNameCache: [String: String] = [:]
    private let articleWords: Set<String> = [
        "a", "an", "den", "der", "des", "el", "la", "las", "le", "les", "los", "the"
    ]
    private let conjunctionWords: Set<String> = [
        "and", "et", "nor", "or", "und"
    ]
    private let prepositionWords: Set<String> = [
        "as", "at", "by", "de", "for", "from", "in", "into", "of", "on", "per",
        "sans", "to", "van", "via", "von", "with", "without"
    ]
    private let properNameParticles: Set<String> = [
        "de", "del", "den", "der", "des", "di", "el", "la", "las", "le", "les",
        "los", "van", "von"
    ]
    private let protectedPrepositionPhrases: Set<[String]> = [
        ["in", "situ"],
        ["in", "utero"],
        ["in", "vitro"],
        ["in", "vivo"]
    ]

    private init() {
        let entries = Self.loadEntries()
        var exactRules: [String: PublicationLTWARule] = [:]
        var prefixRules: [PublicationLTWARule] = []
        var suffixRules: [PublicationLTWARule] = []
        var infixRules: [PublicationLTWARule] = []

        for entry in entries {
            let word = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            let abbreviation = entry.abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
            if word.hasPrefix("-"), word.hasSuffix("-"), word.count > 2 {
                infixRules.append(Self.rule(word: String(word.dropFirst().dropLast()), abbreviation: abbreviation))
            } else if word.hasSuffix("-") {
                prefixRules.append(Self.rule(word: String(word.dropLast()), abbreviation: abbreviation))
            } else if word.hasPrefix("-") {
                suffixRules.append(Self.rule(word: String(word.dropFirst()), abbreviation: abbreviation))
            } else {
                let rule = Self.rule(word: word, abbreviation: abbreviation)
                exactRules[rule.key] = rule
            }
        }

        self.exactRules = exactRules
        self.prefixRules = prefixRules.sorted { $0.key.count > $1.key.count }
        self.suffixRules = suffixRules.sorted { $0.key.count > $1.key.count }
        self.infixRules = infixRules.sorted { $0.key.count > $1.key.count }
    }

    func shortName(for title: String) -> String {
        let normalizedTitle = Self.titleForGeneration(title)
        cacheLock.lock()
        if let cached = shortNameCache[normalizedTitle] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let titleTokens = tokenize(normalizedTitle)
        let wordInfos = Self.wordInfos(in: titleTokens)
        let wordInfoByTokenIndex = Dictionary(firstWinsKeysWithValues: wordInfos.map { ($0.tokenIndex, $0) })
        let protectedWordIndices = protectedSingleTitleWordIndices(in: titleTokens, wordInfos: wordInfos)

        let outputTokens = titleTokens
            .enumerated()
            .compactMap { tokenIndex, token -> PublicationLTWATitleToken? in
                switch token.kind {
                case .punctuation:
                    return outputPunctuationToken(for: token)
                case .word, .acronym:
                    guard let wordInfo = wordInfoByTokenIndex[tokenIndex] else {
                        return nil
                    }
                    guard !shouldOmit(wordInfo, in: wordInfos) else { return nil }
                    if wordInfo.isAcronym || protectedWordIndices.contains(wordInfo.tokenIndex) {
                        return PublicationLTWATitleToken(kind: .word, text: token.text)
                    }
                    guard let abbreviation = abbreviation(for: token.text, key: wordInfo.key) else {
                        return PublicationLTWATitleToken(kind: .word, text: token.text)
                    }
                    let text = abbreviation.isEmpty
                        ? token.text
                        : Self.matchCapitalization(of: abbreviation, to: token.text)
                    return PublicationLTWATitleToken(kind: .word, text: text)
                }
            }

        let result = Self.join(outputTokens)
        cacheLock.lock()
        shortNameCache[normalizedTitle] = result
        cacheLock.unlock()
        return result
    }

    private func abbreviation(for token: String, key: String) -> String? {
        if let exactRule = exactRules[key] {
            return exactRule.abbreviation
        }
        if let prefixRule = prefixRules.first(where: { key.hasPrefix($0.key) }) {
            return prefixRule.abbreviation
        }
        if let suffixRule = suffixRules.first(where: { key.hasSuffix($0.key) }) {
            return suffixRule.abbreviation.isEmpty ? token : suffixRule.abbreviation
        }
        if let infixRule = infixRules.first(where: { key.contains($0.key) }) {
            return infixRule.abbreviation
        }
        return nil
    }

    private func protectedSingleTitleWordIndices(
        in tokens: [PublicationLTWATitleToken],
        wordInfos: [PublicationLTWAWordInfo]
    ) -> Set<Int> {
        let retainedWords = wordInfos.filter { !shouldOmit($0, in: wordInfos) }
        guard !retainedWords.isEmpty else { return [] }

        let baseDelimiterIndex = tokens.firstIndex { token in
            token.kind == .punctuation && ["(", ".", ":"].contains(token.text)
        }
        let baseWords = baseDelimiterIndex.map { delimiterIndex in
            retainedWords.filter { $0.tokenIndex < delimiterIndex }
        } ?? retainedWords
        let coreWords = baseWords.filter { isCoreTitleWord($0, in: wordInfos) }

        guard coreWords.count == 1 else { return [] }
        return Set((baseDelimiterIndex == nil ? retainedWords : baseWords).map(\.tokenIndex))
    }

    private func isCoreTitleWord(_ wordInfo: PublicationLTWAWordInfo, in wordInfos: [PublicationLTWAWordInfo]) -> Bool {
        if prepositionWords.contains(wordInfo.key) {
            return false
        }
        if articleWords.contains(wordInfo.key) || conjunctionWords.contains(wordInfo.key) {
            return false
        }
        if isProperNameParticle(wordInfo, in: wordInfos) {
            return false
        }
        return true
    }

    private func outputPunctuationToken(for token: PublicationLTWATitleToken) -> PublicationLTWATitleToken? {
        switch token.text {
        case ",", "&", "+", "…":
            return nil
        case ".":
            return PublicationLTWATitleToken(kind: .punctuation, text: ",")
        default:
            return token
        }
    }

    private func shouldOmit(_ wordInfo: PublicationLTWAWordInfo, in wordInfos: [PublicationLTWAWordInfo]) -> Bool {
        guard isStopWord(wordInfo.key) else { return false }
        if isInitialRetainedPreposition(wordInfo) {
            return false
        }
        if isProtectedPrepositionPhrase(wordInfo, in: wordInfos) {
            return false
        }
        if isProperNameParticle(wordInfo, in: wordInfos) {
            return false
        }
        return true
    }

    private func isStopWord(_ key: String) -> Bool {
        articleWords.contains(key) || conjunctionWords.contains(key) || prepositionWords.contains(key)
    }

    private func isInitialRetainedPreposition(_ wordInfo: PublicationLTWAWordInfo) -> Bool {
        wordInfo.wordIndex == 0 && prepositionWords.contains(wordInfo.key)
    }

    private func isProtectedPrepositionPhrase(
        _ wordInfo: PublicationLTWAWordInfo,
        in wordInfos: [PublicationLTWAWordInfo]
    ) -> Bool {
        for phrase in protectedPrepositionPhrases {
            guard phrase.count == 2 else { continue }
            if wordInfo.key == phrase[0],
               wordInfo.wordIndex + 1 < wordInfos.count,
               wordInfos[wordInfo.wordIndex + 1].key == phrase[1] {
                return true
            }
            if wordInfo.key == phrase[1],
               wordInfo.wordIndex > 0,
               wordInfos[wordInfo.wordIndex - 1].key == phrase[0] {
                return true
            }
        }
        return false
    }

    private func isProperNameParticle(
        _ wordInfo: PublicationLTWAWordInfo,
        in wordInfos: [PublicationLTWAWordInfo]
    ) -> Bool {
        guard properNameParticles.contains(wordInfo.key),
              wordInfo.wordIndex + 1 < wordInfos.count,
              Self.startsWithUppercaseLetter(wordInfos[wordInfo.wordIndex + 1].text) else {
            return false
        }
        return Self.startsWithUppercaseLetter(wordInfo.text)
            || (wordInfo.wordIndex > 0 && Self.startsWithUppercaseLetter(wordInfos[wordInfo.wordIndex - 1].text))
    }

    private func tokenize(_ title: String) -> [PublicationLTWATitleToken] {
        var tokens: [PublicationLTWATitleToken] = []
        var index = title.startIndex

        while index < title.endIndex {
            let character = title[index]
            if Self.isWhitespace(character) {
                index = title.index(after: index)
                continue
            }
            if let acronym = Self.dottedAcronym(in: title, from: index) {
                tokens.append(PublicationLTWATitleToken(kind: .acronym, text: acronym.text))
                index = acronym.endIndex
                continue
            }
            if Self.isWordCharacter(character) {
                var endIndex = title.index(after: index)
                while endIndex < title.endIndex, Self.isWordCharacter(title[endIndex]) {
                    endIndex = title.index(after: endIndex)
                }
                let text = String(title[index..<endIndex])
                tokens.append(PublicationLTWATitleToken(
                    kind: Self.isCompactAcronym(text) ? .acronym : .word,
                    text: text
                ))
                index = endIndex
            } else {
                tokens.append(PublicationLTWATitleToken(kind: .punctuation, text: String(character)))
                index = title.index(after: index)
            }
        }
        return tokens
    }

    private static func wordInfos(in tokens: [PublicationLTWATitleToken]) -> [PublicationLTWAWordInfo] {
        var infos: [PublicationLTWAWordInfo] = []
        for (tokenIndex, token) in tokens.enumerated() where token.kind == .word || token.kind == .acronym {
            infos.append(PublicationLTWAWordInfo(
                tokenIndex: tokenIndex,
                wordIndex: infos.count,
                text: token.text,
                key: normalizedKey(token.text),
                isAcronym: token.kind == .acronym || isCompactAcronym(token.text)
            ))
        }
        return infos
    }

    private static func rule(word: String, abbreviation: String) -> PublicationLTWARule {
        PublicationLTWARule(word: word, key: normalizedKey(word), abbreviation: abbreviation)
    }

    private static func titleForGeneration(_ title: String) -> String {
        title
            .replacingOccurrences(of: #"\[[^\]]+\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&", with: " and ")
    }

    private static func matchCapitalization(of abbreviation: String, to token: String) -> String {
        guard let firstAbbreviation = abbreviation.first,
              firstAbbreviation.isLowercase,
              token.first?.isUppercase == true else {
            return abbreviation
        }
        return String(firstAbbreviation).uppercased() + String(abbreviation.dropFirst())
    }

    private static func join(_ tokens: [PublicationLTWATitleToken]) -> String {
        var result = ""
        var previous: PublicationLTWATitleToken?

        for token in tokens where !token.text.isEmpty {
            if result.isEmpty {
                result = token.text
            } else if shouldJoinWithoutSpace(previous: previous, current: token) {
                result += token.text
            } else {
                result += " " + token.text
            }
            previous = token
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldJoinWithoutSpace(
        previous: PublicationLTWATitleToken?,
        current: PublicationLTWATitleToken
    ) -> Bool {
        if current.kind == .punctuation,
           [")", "]", "}", ",", ";", ":", "!", "?", "-", "/"].contains(current.text) {
            return true
        }
        if previous?.kind == .punctuation,
           let previousText = previous?.text,
           ["(", "[", "{", "-", "/"].contains(previousText) {
            return true
        }
        return false
    }

    private static func dottedAcronym(
        in title: String,
        from startIndex: String.Index
    ) -> (text: String, endIndex: String.Index)? {
        var index = startIndex
        var text = ""
        var componentCount = 0

        while index < title.endIndex {
            let character = title[index]
            guard isAcronymComponent(character) else { break }

            let nextIndex = title.index(after: index)
            if nextIndex < title.endIndex, title[nextIndex] == "." {
                text.append(character)
                text.append(".")
                componentCount += 1
                index = title.index(after: nextIndex)
            } else if componentCount > 0 {
                text.append(character)
                componentCount += 1
                index = nextIndex
                break
            } else {
                break
            }
        }

        guard componentCount >= 2 else { return nil }
        return (text, index)
    }

    private static func isCompactAcronym(_ text: String) -> Bool {
        let scalars = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let letters = scalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty, scalars.count <= 5 else { return false }
        guard !scalars.contains(where: { CharacterSet.lowercaseLetters.contains($0) }) else { return false }
        return letters.count >= 2 || scalars.contains(where: { CharacterSet.decimalDigits.contains($0) })
    }

    private static func isAcronymComponent(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.uppercaseLetters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func startsWithUppercaseLetter(_ text: String) -> Bool {
        guard let firstScalar = text.unicodeScalars.first else { return false }
        return CharacterSet.uppercaseLetters.contains(firstScalar)
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    private static func loadEntries() -> [PublicationLTWAEntry] {
        guard let url = try? GrantDataStore.bundledResourceURL(named: "issn_ltwa_abbreviations.json") else {
            return []
        }
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([PublicationLTWAEntry].self, from: data)) ?? []
    }
}
