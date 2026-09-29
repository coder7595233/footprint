import Foundation

/// F13d: readers that decide "is this me?" or "is this that researcher?"
/// from the researcher links (ids) first and from the written names second.
/// The names stay the display text; only the decision uses the ids. A name
/// match is kept as a fallback so records whose links are still empty (or
/// were written before researchers were loaded) behave exactly as before.
extension GrantDataStore {
    /// The researcher a written name belongs to, or nil when it matches
    /// nobody. Same lookup as the one used when the id links are built.
    func researcherID(forPresentedName name: String?) -> String? {
        guard let trimmed = name?.trimmedOrNil else { return nil }
        if let exact = publicationAuthor(named: trimmed) {
            return exact.id
        }
        return publicationAuthor(matchingPresentedName: trimmed)?.id
    }

    /// True when the given researcher is one of the people of a record:
    /// by id link first, by written name as fallback.
    func personList(
        ids: [String],
        names: [String],
        includesResearcherID researcherID: String?,
        orName researcherName: String?
    ) -> Bool {
        if let researcherID = researcherID?.trimmedOrNil,
           ids.contains(where: { $0.trimmedOrNil == researcherID }) {
            return true
        }
        guard let researcherName = researcherName?.trimmedOrNil else { return false }
        return names.contains { name in
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(researcherName) == .orderedSame
        }
    }

    /// True when the current user is one of the people of a record
    /// (co-applicants, project members, authors, participants).
    func isCurrentUserAmong(ids: [String], names: [String]) -> Bool {
        if let currentUserID = currentUserAuthor()?.id,
           ids.contains(where: { $0.trimmedOrNil == currentUserID }) {
            return true
        }
        return names.contains { isCurrentUserPresentedName($0) }
    }

    /// True when the current user is the first person of a record (main
    /// applicant, project leader, first author).
    func isCurrentUserFirstPerson(ids: [String], names: [String]) -> Bool {
        guard let firstName = names.first?.trimmedOrNil else { return false }
        if let currentUserID = currentUserAuthor()?.id,
           let firstID = firstPersonAuthorID(ids: ids, names: names) {
            return firstID == currentUserID
        }
        return isCurrentUserPresentedName(firstName)
    }

    /// The current user's place in a name list (for first/last author).
    /// The id link is used when every name got an id, because only then do
    /// the ids line up with the names; otherwise the written name decides.
    func currentUserPersonIndex(ids: [String], names: [String]) -> Int? {
        if let currentUserID = currentUserAuthor()?.id,
           !ids.isEmpty,
           ids.count == names.count,
           let index = ids.firstIndex(where: { $0.trimmedOrNil == currentUserID }) {
            return index
        }
        return names.firstIndex(where: { isCurrentUserPresentedName($0) })
    }
}
