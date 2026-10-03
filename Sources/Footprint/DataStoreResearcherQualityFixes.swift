import Foundation

/// Datakvalitet > Integritet: forskarnas varningar om karriärsteg,
/// doktorsexamen och text utanför listorna kan rättas direkt i raden.
/// Alla ändringar sparas genom forskarens vanliga autosave, så att Ångra
/// fungerar och varningen försvinner när listan räknas om.
extension GrantDataStore {
    /// En "annan examen"-rad som ligger utanför listan.
    struct ResearcherDegreeOutsideList: Equatable, Identifiable {
        let id: String
        let text: String
    }

    /// Vad en forskarvarning behöver för att rättas i raden.
    enum ResearcherIntegrityFix: Equatable {
        /// Karriärsteget skiljer sig från förslaget ur befattningen.
        case careerStageSuggestion(current: PublicationAuthorCareerStage?, suggestion: PublicationAuthorCareerStage)
        /// Karriärsteget stämmer inte med doktorsexamen.
        case careerStagePhD(current: PublicationAuthorCareerStage?, hasPhD: Bool)
        /// Delar av "annan befattning" som inte finns i listan.
        case positionOutsideList(parts: [String])
        /// "Annan examen"-rader som inte finns i listan.
        case degreeOutsideList(entries: [ResearcherDegreeOutsideList])
    }

    /// Nil för alla andra varningar (de visas som förut).
    func researcherIntegrityFix(for issue: IntegrityIssue) -> ResearcherIntegrityFix? {
        guard issue.destination == .people,
              let author = publicationAuthor(id: issue.recordID) else {
            return nil
        }
        let prefix = "\(IntegrityIssue.Kind.semantic.rawValue)-\(Self.dataQualityDestinationKey(.people))-\(author.id)-"
        guard issue.id.hasPrefix(prefix) else { return nil }
        let rule = String(issue.id.dropFirst(prefix.count))
        switch rule {
        case "careerStageSuggestion":
            guard let suggestion = author.careerStageSuggestion(options: researcherPositionOptions) else { return nil }
            return .careerStageSuggestion(current: author.careerStage, suggestion: suggestion)
        case "positionOutsideList":
            let parts = ResearcherLegacyFieldMapping.otherPositionParts(author.localizedPositionOther(language: language))
            guard !parts.isEmpty else { return nil }
            return .positionOutsideList(parts: parts)
        case "degreeOutsideList":
            let entries = researcherDegreesOutsideList(author)
            guard !entries.isEmpty else { return nil }
            return .degreeOutsideList(entries: entries)
        default:
            if rule.hasPrefix("careerStage-") && (rule.hasSuffix("-hasPhD") || rule.hasSuffix("-missingPhD")) {
                return .careerStagePhD(current: author.careerStage, hasPhD: author.hasPhD)
            }
            return nil
        }
    }

    /// Samma rader som varningen "Examen utanför listan" räknar.
    func researcherDegreesOutsideList(_ author: PublicationAuthor) -> [ResearcherDegreeOutsideList] {
        let options = researcherDegreeOptions
        var result: [ResearcherDegreeOutsideList] = []
        for entry in author.degreeEntries {
            if let optionID = entry.optionID, options.contains(where: { $0.id == optionID }) {
                continue
            }
            guard let text = entry.otherText.trimmedOrNil else { continue }
            result.append(ResearcherDegreeOutsideList(id: entry.id, text: text))
        }
        return result
    }

    // MARK: Karriärsteg och doktorsexamen

    /// Sätter karriärsteget (nil = inget steg).
    @discardableResult
    func setResearcherCareerStageFromDataQuality(authorID: String, stage: PublicationAuthorCareerStage?) -> Bool {
        guard var author = publicationAuthor(id: authorID), author.careerStage != stage else { return false }
        author.careerStage = stage
        autosavePublicationAuthor(author, previousName: author.name)
        return true
    }

    /// Använder karriärsteget som befattningen talar för.
    @discardableResult
    func applyResearcherCareerStageSuggestion(authorID: String) -> Bool {
        guard let author = publicationAuthor(id: authorID),
              let suggestion = author.careerStageSuggestion(options: researcherPositionOptions) else {
            return false
        }
        return setResearcherCareerStageFromDataQuality(authorID: authorID, stage: suggestion)
    }

    /// Kryssar i eller ur doktorsexamen. Karriärsteget ändras inte.
    @discardableResult
    func setResearcherPhDFromDataQuality(authorID: String, hasPhD: Bool) -> Bool {
        guard var author = publicationAuthor(id: authorID), author.hasPhD != hasPhD else { return false }
        author.hasPhD = hasPhD
        autosavePublicationAuthor(author, previousName: author.name)
        return true
    }

    // MARK: Befattning utanför listan

    /// Väljer en befattning ur listan för en del av "annan"-texten: valet
    /// läggs till och just den delen tas bort ur texten. Har en läkar-
    /// befattning en specialitet i delen ("… i geriatrik") blir den vald.
    @discardableResult
    func chooseResearcherPositionForOutsideText(authorID: String, part: String, optionID: String) -> Bool {
        guard var author = publicationAuthor(id: authorID),
              let option = researcherPositionOptions.first(where: { $0.id == optionID }) else {
            return false
        }
        if !author.positionIDs.contains(option.id) {
            author.positionIDs.append(option.id)
        }
        if option.takesSpecialty,
           author.positionSpecialtyIDs[option.id] == nil,
           let found = ResearcherLegacyFieldMapping.specialtyMatch(in: part) {
            author.positionSpecialtyIDs[option.id] = found.specialtyID
        }
        Self.removeOtherPositionPart(from: &author, part: part, language: language, alignedPartIsUsed: false) { candidate in
            ResearcherLegacyFieldMapping.positionPart(candidate, isExplainedBy: option)
        }
        autosavePublicationAuthor(author, previousName: author.name)
        return true
    }

    /// Lägger till delen av "annan"-texten som en ny befattning i listan
    /// (Inställningar > Listor) i den valda gruppen och väljer den. Finns
    /// redan en befattning med samma namn väljs den i stället.
    @discardableResult
    func addResearcherPositionToListFromDataQuality(authorID: String, part: String, group: ResearcherPositionGroup) -> Bool {
        guard var author = publicationAuthor(id: authorID),
              let trimmedPart = part.trimmedOrNil else {
            return false
        }
        let source = Self.otherPositionSource(of: author, language: language)
        let sourceParts = ResearcherLegacyFieldMapping.otherPositionParts(source.isSwedish ? author.positionOtherSv : author.positionOtherEn)
        let otherParts = ResearcherLegacyFieldMapping.otherPositionParts(source.isSwedish ? author.positionOtherEn : author.positionOtherSv)
        let partKey = ResearcherLegacyFieldMapping.normalizedKey(trimmedPart)
        let index = sourceParts.firstIndex { ResearcherLegacyFieldMapping.normalizedKey($0) == partKey }
        var aligned: String? = nil
        if let index, otherParts.count == sourceParts.count, otherParts.indices.contains(index) {
            aligned = otherParts[index]
        }
        let swedishName = source.isSwedish ? trimmedPart : (aligned ?? "")
        let englishName = source.isSwedish ? (aligned ?? "") : trimmedPart

        let optionID: String
        if let existing = researcherPositionOptions.first(where: { option in
            ResearcherLegacyFieldMapping.normalizedKey(option.nameSv) == partKey
                || ResearcherLegacyFieldMapping.normalizedKey(option.nameEn) == partKey
        }) {
            optionID = existing.id
        } else {
            var list = researcherPositionOptions
            let newOption = ResearcherPositionOption(
                nameSv: swedishName,
                nameEn: englishName,
                group: group,
                sortOrder: list.count
            )
            list.append(newOption)
            autosaveResearcherPositionOptions(list)
            guard researcherPositionOptions.contains(where: { $0.id == newOption.id }) else { return false }
            optionID = newOption.id
        }

        if !author.positionIDs.contains(optionID) {
            author.positionIDs.append(optionID)
        }
        let alignedKey = aligned.map { ResearcherLegacyFieldMapping.normalizedKey($0) }
        Self.removeOtherPositionPart(from: &author, part: trimmedPart, language: language, alignedPartIsUsed: aligned != nil) { candidate in
            guard let alignedKey else { return false }
            return ResearcherLegacyFieldMapping.normalizedKey(candidate) == alignedKey
        }
        autosavePublicationAuthor(author, previousName: author.name)
        return true
    }

    /// Vilket fält "annan"-texten visas från på appens språk (samma regel
    /// som `localizedPositionOther`).
    nonisolated static func otherPositionSource(of author: PublicationAuthor, language: AppLanguage) -> (isSwedish: Bool, text: String) {
        if language == .swedish {
            if author.positionOtherSv.trimmedOrNil != nil {
                return (true, author.positionOtherSv)
            }
            return (false, author.positionOtherEn)
        }
        if author.positionOtherEn.trimmedOrNil != nil {
            return (false, author.positionOtherEn)
        }
        return (true, author.positionOtherSv)
    }

    /// Tar bort delen ur fältet den visas från. I det andra språkets fält
    /// tas bara en del bort som `otherLanguagePartIsExplained` godkänner
    /// (samma befattning, eller den motsvarande delen som blev det engelska
    /// eller svenska namnet); annan text lämnas orörd.
    nonisolated static func removeOtherPositionPart(
        from author: inout PublicationAuthor,
        part: String,
        language: AppLanguage,
        alignedPartIsUsed: Bool,
        otherLanguagePartIsExplained: (String) -> Bool
    ) {
        let source = otherPositionSource(of: author, language: language)
        let partKey = ResearcherLegacyFieldMapping.normalizedKey(part)
        var sourceParts = ResearcherLegacyFieldMapping.otherPositionParts(source.text)
        guard let index = sourceParts.firstIndex(where: { ResearcherLegacyFieldMapping.normalizedKey($0) == partKey }) else {
            return
        }
        let otherText = source.isSwedish ? author.positionOtherEn : author.positionOtherSv
        var otherParts = ResearcherLegacyFieldMapping.otherPositionParts(otherText)
        let partCountsMatch = otherParts.count == sourceParts.count
        sourceParts.remove(at: index)
        let rebuiltSource = sourceParts.joined(separator: ", ")

        var removedOther = false
        if alignedPartIsUsed, partCountsMatch, otherParts.indices.contains(index),
           otherLanguagePartIsExplained(otherParts[index]) {
            otherParts.remove(at: index)
            removedOther = true
        } else if !alignedPartIsUsed,
                  let otherIndex = otherParts.firstIndex(where: otherLanguagePartIsExplained) {
            otherParts.remove(at: otherIndex)
            removedOther = true
        }

        if source.isSwedish {
            author.positionOtherSv = rebuiltSource
            if removedOther {
                author.positionOtherEn = otherParts.joined(separator: ", ")
            }
        } else {
            author.positionOtherEn = rebuiltSource
            if removedOther {
                author.positionOtherSv = otherParts.joined(separator: ", ")
            }
        }
    }

    // MARK: Examen utanför listan

    /// Byter en "annan examen"-rad mot ett val ur listan (se
    /// `ResearcherLegacyFieldMapping.degreeEntry(_:choosing:)`).
    @discardableResult
    func chooseResearcherDegreeForOutsideText(authorID: String, entryID: String, optionID: String) -> Bool {
        guard var author = publicationAuthor(id: authorID),
              let option = researcherDegreeOptions.first(where: { $0.id == optionID }),
              let index = author.degreeEntries.firstIndex(where: { $0.id == entryID }) else {
            return false
        }
        author.degreeEntries[index] = ResearcherLegacyFieldMapping.degreeEntry(author.degreeEntries[index], choosing: option)
        autosavePublicationAuthor(author, previousName: author.name)
        return true
    }

    /// Lägger till texten som en ny examen i listan och väljer den på raden.
    /// Finns redan en examen med samma namn eller förkortning väljs den.
    @discardableResult
    func addResearcherDegreeToListFromDataQuality(authorID: String, entryID: String) -> Bool {
        guard var author = publicationAuthor(id: authorID),
              let index = author.degreeEntries.firstIndex(where: { $0.id == entryID }),
              let text = author.degreeEntries[index].otherText.trimmedOrNil else {
            return false
        }
        let key = ResearcherLegacyFieldMapping.normalizedKey(text)
        let option: ResearcherDegreeOption
        if let existing = researcherDegreeOptions.first(where: { candidate in
            [candidate.nameSv, candidate.nameEn, candidate.abbreviation]
                .map { ResearcherLegacyFieldMapping.normalizedKey($0) }
                .contains(key)
        }) {
            option = existing
        } else {
            var list = researcherDegreeOptions
            let newOption = ResearcherDegreeOption(
                nameSv: language == .swedish ? text : "",
                nameEn: language == .swedish ? "" : text,
                sortOrder: list.count
            )
            list.append(newOption)
            autosaveResearcherDegreeOptions(list)
            guard researcherDegreeOptions.contains(where: { $0.id == newOption.id }) else { return false }
            option = newOption
        }
        author.degreeEntries[index] = ResearcherLegacyFieldMapping.degreeEntry(author.degreeEntries[index], choosing: option)
        autosavePublicationAuthor(author, previousName: author.name)
        return true
    }
}
