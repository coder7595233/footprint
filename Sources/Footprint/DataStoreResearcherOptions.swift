import Foundation

/// Inställningar > Listor: befattningar och examina för forskare.
/// Listorna sparas i appens metadata först när de ändras; fram till dess
/// gäller de inbyggda listorna.
extension GrantDataStore {
    var researcherPositionOptions: [ResearcherPositionOption] {
        ResearcherPositionOption.resolvedOptions(metadata.researcherPositionOptions)
    }

    var researcherDegreeOptions: [ResearcherDegreeOption] {
        ResearcherDegreeOption.resolvedOptions(metadata.researcherDegreeOptions)
    }

    /// Hur många forskare som har varje befattning vald (id → antal).
    func researcherPositionOptionUsageCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for author in publicationAuthors {
            for id in Set(author.positionIDs) {
                counts[id, default: 0] += 1
            }
        }
        return counts
    }

    /// Hur många forskare som har varje examen vald (id → antal).
    func researcherDegreeOptionUsageCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for author in publicationAuthors {
            for id in Set(author.degreeEntries.compactMap(\.optionID)) {
                counts[id, default: 0] += 1
            }
        }
        return counts
    }

    /// Sparar befattningslistan (kan ångras). En befattning som någon forskare
    /// har vald tas aldrig bort, även om den saknas i den nya listan.
    func autosaveResearcherPositionOptions(_ options: [ResearcherPositionOption]) {
        var normalized = ResearcherPositionOption.normalizedList(options)
        let usage = researcherPositionOptionUsageCounts()
        for option in researcherPositionOptions where (usage[option.id] ?? 0) > 0 {
            if !normalized.contains(where: { $0.id == option.id }) {
                var kept = option
                kept.sortOrder = normalized.count
                normalized.append(kept)
            }
        }
        guard normalized != researcherPositionOptions else { return }
        var updated = editableMetadataSnapshot
        updated.researcherPositionOptions = normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit positions list", "Redigera listan med befattningar")
        )
    }

    /// Sparar examenslistan (kan ångras). En examen som någon forskare har
    /// vald tas aldrig bort, även om den saknas i den nya listan.
    func autosaveResearcherDegreeOptions(_ options: [ResearcherDegreeOption]) {
        var normalized = ResearcherDegreeOption.normalizedList(options)
        let usage = researcherDegreeOptionUsageCounts()
        for option in researcherDegreeOptions where (usage[option.id] ?? 0) > 0 {
            if !normalized.contains(where: { $0.id == option.id }) {
                var kept = option
                kept.sortOrder = normalized.count
                normalized.append(kept)
            }
        }
        guard normalized != researcherDegreeOptions else { return }
        var updated = editableMetadataSnapshot
        updated.researcherDegreeOptions = normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit degrees list", "Redigera listan med examina")
        )
    }
}

/// Inställningar > Listor: läkarspecialiteter (för ST-läkare, Specialistläkare
/// och Överläkare) och sjuksköterskespecialiteter (för Specialistsjuksköterska),
/// i en gemensam lista där varje specialitet har sin sort. Samma mönster som
/// befattningar och examina.
extension GrantDataStore {
    var researcherSpecialtyOptions: [ResearcherSpecialtyOption] {
        ResearcherSpecialtyOption.resolvedOptions(metadata.researcherSpecialtyOptions)
    }

    /// Hur många forskare som har varje specialitet vald (id → antal).
    func researcherSpecialtyOptionUsageCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for author in publicationAuthors {
            for id in Set(author.positionSpecialtyIDs.values) {
                counts[id, default: 0] += 1
            }
        }
        return counts
    }

    /// Sparar specialitetslistan (kan ångras). En specialitet som någon
    /// forskare har vald tas aldrig bort, även om den saknas i den nya listan.
    func autosaveResearcherSpecialtyOptions(_ options: [ResearcherSpecialtyOption]) {
        var normalized = ResearcherSpecialtyOption.normalizedList(options)
        let usage = researcherSpecialtyOptionUsageCounts()
        for option in researcherSpecialtyOptions where (usage[option.id] ?? 0) > 0 {
            if !normalized.contains(where: { $0.id == option.id }) {
                var kept = option
                kept.sortOrder = normalized.count
                normalized.append(kept)
            }
        }
        guard normalized != researcherSpecialtyOptions else { return }
        var updated = editableMetadataSnapshot
        updated.researcherSpecialtyOptions = normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit specialties list", "Redigera listan med specialiteter")
        )
    }
}
