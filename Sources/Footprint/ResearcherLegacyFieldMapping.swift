import Foundation

/// Engångsflytten från de gamla fritextfälten (befattning, examen) till
/// listvalen. Rena funktioner utan sidoeffekter, så att reglerna kan testas.
///
/// Regler:
/// - Texten delas vid komma, semikolon, snedstreck och (för befattningar)
///   orden "och", "and", "samt". Text inom parentes delas inte.
/// - Varje del jämförs utan hänsyn till stora/små bokstäver, accenter,
///   punkter och bindestreck mot en lista med svenska och engelska namn.
///   En del som börjar med ett känt namn följt av t.ex. "i", "in", "of"
///   ("Specialistläkare i allmänmedicin") räknas också.
/// - Delar som inte känns igen sparas som "annan" text och flaggas i
///   Datakvalitet. Den gamla texten ändras aldrig.
enum ResearcherLegacyFieldMapping {
    // MARK: Resultat

    struct PositionResult: Equatable {
        var positionIDs: [String] = []
        var isDocent = false
        var unmappedParts: [String] = []
    }

    struct DegreeMatch: Equatable {
        var optionID: String
        var subject: String
    }

    struct DegreeResult: Equatable {
        var matches: [DegreeMatch] = []
        var unmappedParts: [String] = []
    }

    // MARK: Synonymer

    private struct PositionSynonym {
        let phrase: String
        let ids: [String]
        let docent: Bool
    }

    private static func positionSynonyms() -> [PositionSynonym] {
        typealias P = ResearcherPositionOption.BuiltInID
        let rows: [(String, [String], Bool)] = [
            ("professor", [P.professor], false),
            ("full professor", [P.professor], false),
            ("adjungerad professor", [P.adjunctProfessor], false),
            ("adjunct professor", [P.adjunctProfessor], false),
            ("seniorprofessor", [P.seniorProfessor], false),
            ("senior professor", [P.seniorProfessor], false),
            ("professor emeritus", [P.professorEmeritus], false),
            ("professor emerita", [P.professorEmeritus], false),
            ("emeritus professor", [P.professorEmeritus], false),
            ("biträdande professor", [P.associateProfessor], false),
            ("universitetslektor", [P.seniorLecturer], false),
            ("lektor", [P.seniorLecturer], false),
            ("senior lecturer", [P.seniorLecturer], false),
            ("associate professor", [P.seniorLecturer], true),
            ("senior associate professor", [P.seniorLecturer], true),
            ("biträdande universitetslektor", [P.assistantProfessor], false),
            ("assistant professor", [P.assistantProfessor], false),
            ("adjungerad universitetslektor", [P.adjunctSeniorLecturer], false),
            ("adjungerad lektor", [P.adjunctSeniorLecturer], false),
            ("adjunct senior lecturer", [P.adjunctSeniorLecturer], false),
            ("adjunct associate professor", [P.adjunctSeniorLecturer], true),
            ("universitetsadjunkt", [P.lecturer], false),
            ("adjunkt", [P.lecturer], false),
            ("lecturer", [P.lecturer], false),
            ("adjungerad adjunkt", [P.adjunctLecturer], false),
            ("adjunct lecturer", [P.adjunctLecturer], false),
            ("postdoktor", [P.postdoc], false),
            ("postdoc", [P.postdoc], false),
            ("post doc", [P.postdoc], false),
            ("postdoctoral researcher", [P.postdoc], false),
            ("postdoctoral fellow", [P.postdoc], false),
            ("post doctoral researcher", [P.postdoc], false),
            ("post doctoral fellow", [P.postdoc], false),
            ("forskare", [P.researcher], false),
            ("researcher", [P.researcher], false),
            ("affilierad forskare", [P.affiliatedResearcher], false),
            ("affiliated researcher", [P.affiliatedResearcher], false),
            ("affiliated to research", [P.affiliatedResearcher], false),
            ("anknuten till forskning", [P.affiliatedResearcher], false),
            ("gästforskare", [P.visitingResearcher], false),
            ("visiting researcher", [P.visitingResearcher], false),
            ("guest researcher", [P.visitingResearcher], false),
            ("forskningsingenjör", [P.researchEngineer], false),
            ("research engineer", [P.researchEngineer], false),
            ("forskningsassistent", [P.researchAssistant], false),
            ("research assistant", [P.researchAssistant], false),
            ("seniorforskare", [P.seniorResearcher], false),
            ("senior researcher", [P.seniorResearcher], false),
            ("forskningschef", [P.directorOfResearch], false),
            ("director of research", [P.directorOfResearch], false),
            ("research director", [P.directorOfResearch], false),
            ("doktorand", [P.phdStudent], false),
            ("phd student", [P.phdStudent], false),
            ("phd candidate", [P.phdStudent], false),
            ("doctoral student", [P.phdStudent], false),
            ("doctoral candidate", [P.phdStudent], false),
            ("läkarstudent", [P.medicalStudent], false),
            ("medical student", [P.medicalStudent], false),
            ("medicine student", [P.medicalStudent], false),
            ("at läkare", [P.internPhysician], false),
            ("intern physician", [P.internPhysician], false),
            ("st läkare", [P.residentPhysician], false),
            ("resident physician", [P.residentPhysician], false),
            ("resident", [P.residentPhysician], false),
            ("specialistläkare", [P.specialistPhysician], false),
            ("specialist physician", [P.specialistPhysician], false),
            ("specialist i allmänmedicin", [P.specialistPhysician], false),
            ("specialist in general practice", [P.specialistPhysician], false),
            ("specialist in family medicine", [P.specialistPhysician], false),
            ("allmänläkare", [P.specialistPhysician], false),
            ("distriktsläkare", [P.specialistPhysician], false),
            ("general practitioner", [P.specialistPhysician], false),
            ("överläkare", [P.seniorConsultant], false),
            ("senior consultant", [P.seniorConsultant], false),
            ("consultant physician", [P.seniorConsultant], false),
            ("sjuksköterska", [P.registeredNurse], false),
            ("registered nurse", [P.registeredNurse], false),
            ("specialistsjuksköterska", [P.specialistNurse], false),
            ("specialist nurse", [P.specialistNurse], false),
            ("forskningssjuksköterska", [P.researchNurse], false),
            ("research nurse", [P.researchNurse], false),
            ("biomedicinsk analytiker", [P.biomedicalScientist], false),
            ("biomedical scientist", [P.biomedicalScientist], false),
            ("apotekare", [P.pharmacist], false),
            ("pharmacist", [P.pharmacist], false),
            ("psykolog", [P.psychologist], false),
            ("leg psykolog", [P.psychologist], false),
            ("psychologist", [P.psychologist], false),
            ("arbetsterapeut", [P.occupationalTherapist], false),
            ("occupational therapist", [P.occupationalTherapist], false),
            ("statistiker", [P.statistician], false),
            ("statistician", [P.statistician], false),
            ("biostatistiker", [P.statistician], false),
            ("biostatistician", [P.statistician], false),
            ("verksamhetschef", [P.headOfDepartment], false),
            ("head of department", [P.headOfDepartment], false),
            ("docent", [], true),
        ]
        return rows.map { PositionSynonym(phrase: normalizedKey($0.0), ids: $0.1, docent: $0.2) }
            .sorted { $0.phrase.count > $1.phrase.count }
    }

    private struct DegreeSynonym {
        let phrase: String
        let id: String
        let takesSubject: Bool
    }

    private static func degreeSynonyms() -> [DegreeSynonym] {
        typealias D = ResearcherDegreeOption.BuiltInID
        let rows: [(String, String, Bool)] = [
            ("md", D.medical, false),
            ("mbbs", D.medical, false),
            ("mb bs", D.medical, false),
            ("mbchb", D.medical, false),
            ("mb chb", D.medical, false),
            ("läkarexamen", D.medical, false),
            ("läkare", D.medical, false),
            ("leg läkare", D.medical, false),
            ("medical degree", D.medical, false),
            ("medical doctor", D.medical, false),
            ("doctor of medicine", D.medical, false),
            ("rn", D.nursing, false),
            ("sjuksköterskeexamen", D.nursing, false),
            ("sjuksköterska", D.nursing, false),
            ("leg sjuksköterska", D.nursing, false),
            ("registered nurse", D.nursing, false),
            ("nursing degree", D.nursing, false),
            ("specialistsjuksköterskeexamen", D.specialistNursing, false),
            ("specialistsjuksköterska", D.specialistNursing, false),
            ("apotekarexamen", D.pharmacy, false),
            ("apotekare", D.pharmacy, false),
            ("msc pharm", D.pharmacy, false),
            ("master of science in pharmacy", D.pharmacy, false),
            ("receptarieexamen", D.prescriptionist, false),
            ("receptarie", D.prescriptionist, false),
            ("biomedicinsk analytikerexamen", D.biomedicalScience, false),
            ("biomedicinsk analytiker", D.biomedicalScience, false),
            ("psykologexamen", D.psychology, false),
            ("psykolog", D.psychology, false),
            ("leg psykolog", D.psychology, false),
            ("arbetsterapeutexamen", D.occupationalTherapy, false),
            ("arbetsterapeut", D.occupationalTherapy, false),
            ("fysioterapeutexamen", D.physiotherapy, false),
            ("fysioterapeut", D.physiotherapy, false),
            ("sjukgymnast", D.physiotherapy, false),
            ("physiotherapist", D.physiotherapy, false),
            ("dietistexamen", D.dietetics, false),
            ("dietist", D.dietetics, false),
            ("civilingenjörsexamen", D.engineering, false),
            ("civilingenjör", D.engineering, false),
            ("civil engineer", D.engineering, false),
            ("msc eng", D.engineering, false),
            ("master of science in engineering", D.engineering, false),
            ("socionomexamen", D.socialWork, false),
            ("socionom", D.socialWork, false),
            ("kandidatexamen", D.bachelor, true),
            ("kandidat", D.bachelor, true),
            ("fil kand", D.bachelor, true),
            ("bachelor", D.bachelor, true),
            ("bachelor of science", D.bachelor, true),
            ("bachelor of arts", D.bachelor, true),
            ("bsc", D.bachelor, true),
            ("ba", D.bachelor, true),
            ("magisterexamen", D.magister, true),
            ("magister", D.magister, true),
            ("fil mag", D.magister, true),
            ("masterexamen", D.master, true),
            ("master", D.master, true),
            ("master of science", D.master, true),
            ("master of arts", D.master, true),
            ("msc", D.master, true),
            ("ma", D.master, true),
        ]
        return rows.map { DegreeSynonym(phrase: normalizedKey($0.0), id: $0.1, takesSubject: $0.2) }
            .sorted { $0.phrase.count > $1.phrase.count }
    }

    /// Ord som får stå mellan ett känt namn och resten ("i allmänmedicin").
    /// (Jämförs efter `normalizedKey`, alltså utan accenter: "för" = "for".)
    private static let connectorWords: Set<String> = ["i", "in", "of", "inom", "within", "for", "vid", "at", "pa"]

    // MARK: Textbehandling

    /// Jämförelsenyckel: små bokstäver, utan accenter, punkter och bindestreck.
    static func normalizedKey(_ text: String) -> String {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        return spacedWords(folded.replacingOccurrences(of: ".", with: ""))
    }

    /// Bindestreck blir mellanslag, parenteser får mellanslag runt sig.
    private static func spacedWords(_ text: String) -> String {
        text
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "(", with: " (")
            .replacingOccurrences(of: ")", with: ") ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " :,;"))
    }

    /// Delar texten vid komma, semikolon, snedstreck, "&" och "+" utanför
    /// parenteser; med `splitsOnWords` också vid "och", "and" och "samt".
    static func splitParts(_ text: String, splitsOnWords: Bool) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            switch character {
            case "(", "[":
                depth += 1
                current.append(character)
            case ")", "]":
                depth = max(0, depth - 1)
                current.append(character)
            case ",", ";", "/", "&", "+", "\n":
                if depth == 0 {
                    parts.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
            default:
                current.append(character)
            }
        }
        parts.append(current)

        var result: [String] = []
        for part in parts {
            if splitsOnWords && !part.contains("(") {
                result.append(contentsOf: splitOnWords(part))
            } else {
                result.append(part)
            }
        }
        return result
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".:"))) }
            .filter { !$0.isEmpty }
    }

    private static func splitOnWords(_ text: String) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var parts: [String] = []
        var current: [String] = []
        for word in words {
            if ["och", "and", "samt"].contains(word.lowercased()) {
                parts.append(current.joined(separator: " "))
                current = []
            } else {
                current.append(word)
            }
        }
        parts.append(current.joined(separator: " "))
        return parts
    }

    /// Hur mycket av delen som ett känt namn täcker: hela (`exact`) eller
    /// början följd av ett bindeord/parentes (`prefix`, med resten).
    private enum PhraseMatch {
        case exact
        case prefix(remainderWordCount: Int)
    }

    private static func match(_ phrase: String, in key: String, allowsAnyRemainder: Bool) -> PhraseMatch? {
        if key == phrase { return .exact }
        guard key.hasPrefix(phrase + " ") else { return nil }
        let remainder = String(key.dropFirst(phrase.count + 1))
        let remainderWords = remainder.split(separator: " ").map(String.init)
        guard let first = remainderWords.first else { return .exact }
        if allowsAnyRemainder || connectorWords.contains(first) || first.hasPrefix("(") {
            return .prefix(remainderWordCount: remainderWords.count)
        }
        return nil
    }

    // MARK: Befattningar

    static func mapPositionText(_ text: String) -> PositionResult {
        var result = PositionResult()
        let synonyms = positionSynonyms()
        for part in splitParts(text, splitsOnWords: true) {
            let key = normalizedKey(part)
            guard !key.isEmpty else { continue }
            guard let synonym = synonyms.first(where: { match($0.phrase, in: key, allowsAnyRemainder: false) != nil }) else {
                result.unmappedParts.append(part)
                continue
            }
            for id in synonym.ids where !result.positionIDs.contains(id) {
                result.positionIDs.append(id)
            }
            if synonym.docent {
                result.isDocent = true
            }
        }
        return result
    }

    // MARK: Examina

    static func mapDegreeText(_ text: String) -> DegreeResult {
        var result = DegreeResult()
        let synonyms = degreeSynonyms()
        for part in splitParts(text, splitsOnWords: false) {
            let key = normalizedKey(part)
            guard !key.isEmpty else { continue }
            var found: (DegreeSynonym, PhraseMatch)? = nil
            for synonym in synonyms {
                if let phraseMatch = match(synonym.phrase, in: key, allowsAnyRemainder: synonym.takesSubject) {
                    found = (synonym, phraseMatch)
                    break
                }
            }
            guard let found else {
                result.unmappedParts.append(part)
                continue
            }
            let synonym = found.0
            let phraseMatch = found.1
            var subject = ""
            if synonym.takesSubject, case let .prefix(remainderWordCount) = phraseMatch {
                subject = subjectText(from: part, remainderWordCount: remainderWordCount)
            }
            result.matches.append(DegreeMatch(optionID: synonym.id, subject: subject))
        }
        return result
    }

    /// Ämnet ur originaltexten: de sista orden efter examensnamnet, utan
    /// inledande "in", "i", "of" och utan parenteser.
    static func subjectText(from part: String, remainderWordCount: Int) -> String {
        let words = spacedWords(part).split(separator: " ").map(String.init)
        guard remainderWordCount > 0, remainderWordCount <= words.count else { return "" }
        var remainder = Array(words.suffix(remainderWordCount))
        while let first = remainder.first, connectorWords.contains(normalizedKey(first)) {
            remainder.removeFirst()
        }
        let joined = remainder.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ()[],:;"))
            .replacingOccurrences(of: "( ", with: "(")
            .replacingOccurrences(of: " )", with: ")")
        return joined
    }

    // MARK: En forskare

    /// Fyller listvalen ur den gamla texten. Bara de nya fälten ändras, och
    /// bara när de är tomma; karriärsteg, doktorsexamen och den gamla texten
    /// lämnas orörda. Att köra den igen ändrar ingenting.
    static func migrated(_ author: PublicationAuthor) -> PublicationAuthor {
        var updated = author

        if !author.hasStructuredPosition {
            let swedishText = author.positionSv.trimmingCharacters(in: .whitespacesAndNewlines)
            let englishText = author.positionEn.trimmingCharacters(in: .whitespacesAndNewlines)
            let swedish = mapPositionText(swedishText)
            let english = normalizedKey(englishText) == normalizedKey(swedishText)
                ? PositionResult()
                : mapPositionText(englishText)

            var ids = swedish.positionIDs
            for id in english.positionIDs where !ids.contains(id) {
                ids.append(id)
            }
            // "Biträdande professor" på svenska heter "Associate Professor" på
            // engelska; då ska den engelska texten inte också ge universitetslektor.
            let associateProfessorID = ResearcherPositionOption.BuiltInID.associateProfessor
            let seniorLecturerID = ResearcherPositionOption.BuiltInID.seniorLecturer
            if ids.contains(associateProfessorID),
               ids.contains(seniorLecturerID),
               !swedish.positionIDs.contains(seniorLecturerID) {
                ids.removeAll { $0 == seniorLecturerID }
            }
            updated.positionIDs = ids
            updated.positionOtherSv = swedish.unmappedParts.joined(separator: ", ")
            updated.positionOtherEn = english.unmappedParts.joined(separator: ", ")
            if swedish.isDocent || english.isDocent {
                updated.isDocent = true
            }
        }

        // En gammal titel "Docent" betyder docent.
        if !updated.isDocent {
            let titleParts = splitParts(author.titleSv, splitsOnWords: true)
                + splitParts(author.titleEn, splitsOnWords: true)
            if titleParts.contains(where: { normalizedKey($0) == "docent" }) {
                updated.isDocent = true
            }
        }

        if !author.hasStructuredDegree {
            let swedishText = author.degreeSv.trimmingCharacters(in: .whitespacesAndNewlines)
            let englishText = author.degreeEn.trimmingCharacters(in: .whitespacesAndNewlines)
            let swedish = mapDegreeText(swedishText)
            let sameText = normalizedKey(englishText) == normalizedKey(swedishText)
            let english = sameText ? DegreeResult() : mapDegreeText(englishText)

            var entries: [ResearcherDegreeEntry] = []
            for match in swedish.matches {
                // When both fields hold the same text the subject is used for both.
                entries.append(ResearcherDegreeEntry(
                    optionID: match.optionID,
                    subjectSv: match.subject,
                    subjectEn: sameText ? match.subject : ""
                ))
            }
            for match in english.matches {
                if let index = entries.firstIndex(where: { $0.optionID == match.optionID && $0.subjectEn.isEmpty }) {
                    entries[index].subjectEn = match.subject
                } else {
                    entries.append(ResearcherDegreeEntry(optionID: match.optionID, subjectEn: match.subject))
                }
            }
            // Text that is not in the list is kept as "other degree" rows; the
            // English field's leftovers only when the Swedish field had none.
            let otherParts = swedish.unmappedParts.isEmpty && swedishText.isEmpty
                ? english.unmappedParts
                : swedish.unmappedParts
            for part in otherParts {
                entries.append(ResearcherDegreeEntry(otherText: part))
            }
            updated.degreeEntries = entries
        }

        updated.positionOtherSv = updated.positionOtherSv.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.positionOtherEn = updated.positionOtherEn.trimmingCharacters(in: .whitespacesAndNewlines)
        return updated
    }
}
