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
        /// Läkarspecialitet per befattning (befattningens id -> specialitetens id).
        var specialtyIDs: [String: String] = [:]
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

    /// Befattningar ur texten. En läkarbefattning med specialitet
    /// ("Överläkare i dermatologi och venereologi") får specialiteten; ett
    /// ensamt specialistord ("geriatriker", "Kirurg") ger specialiteten till
    /// textens enda läkarbefattning utan specialitet, eller, när texten inte
    /// har någon läkarbefattning, Specialistläkare med den specialiteten.
    static func mapPositionText(_ text: String) -> PositionResult {
        var result = PositionResult()
        let synonyms = positionSynonyms()
        let protected = protectingSpecialtyNames(text)
        var outcomes: [String?] = []
        var pendingLoose: [(index: Int, part: String, match: SpecialtyMatch)] = []
        for rawPart in splitParts(protected.text, splitsOnWords: true) {
            let part = restoringSpecialtyNames(rawPart, placeholders: protected.placeholders)
            let key = normalizedKey(part)
            guard !key.isEmpty else { continue }
            guard let synonym = synonyms.first(where: { match($0.phrase, in: key, allowsAnyRemainder: false) != nil }) else {
                if let loose = looseSpecialty(in: part) {
                    pendingLoose.append((index: outcomes.count, part: part, match: loose))
                    outcomes.append(nil)
                } else {
                    outcomes.append(part)
                }
                continue
            }
            outcomes.append(nil)
            for id in synonym.ids where !result.positionIDs.contains(id) {
                result.positionIDs.append(id)
            }
            if synonym.docent {
                result.isDocent = true
            }
            let physicianIDs = synonym.ids.filter { ResearcherPositionOption.specialtyPositionIDs.contains($0) }
            if !physicianIDs.isEmpty, let found = specialtyMatch(in: part) {
                for id in physicianIDs where result.specialtyIDs[id] == nil {
                    result.specialtyIDs[id] = found.specialtyID
                }
            }
        }
        for loose in pendingLoose {
            let physicians = result.positionIDs.filter { ResearcherPositionOption.specialtyPositionIDs.contains($0) }
            let lacking = physicians.filter { result.specialtyIDs[$0] == nil }
            if lacking.count == 1 {
                result.specialtyIDs[lacking[0]] = loose.match.specialtyID
            } else if physicians.isEmpty && loose.match.impliesSpecialist {
                let specialistID = ResearcherPositionOption.BuiltInID.specialistPhysician
                result.positionIDs.append(specialistID)
                result.specialtyIDs[specialistID] = loose.match.specialtyID
            } else {
                outcomes[loose.index] = loose.part
            }
        }
        result.unmappedParts = outcomes.compactMap { $0 }
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
            var specialties: [String: String] = [:]
            for id in ids {
                if let specialtyID = swedish.specialtyIDs[id] ?? english.specialtyIDs[id] {
                    specialties[id] = specialtyID
                }
            }
            updated.positionSpecialtyIDs = specialties
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

// MARK: - Läkarspecialiteter

extension ResearcherLegacyFieldMapping {
    /// En specialitet som hittats i en text. `impliesSpecialist` gäller ord
    /// som betyder en specialistläkare ("kirurg", "geriatriker").
    struct SpecialtyMatch: Equatable {
        var specialtyID: String
        var impliesSpecialist: Bool
    }

    private struct SpecialtySynonym: Sendable {
        let tokens: [String]
        let specialtyID: String
        let impliesSpecialist: Bool
    }

    private static let cachedSpecialtySynonyms: [SpecialtySynonym] = specialtySynonyms()

    /// Namn och ord för specialiteterna: listans svenska och engelska namn,
    /// andra stavningar, och ord för specialistläkaren själv.
    private static func specialtySynonyms() -> [SpecialtySynonym] {
        typealias S = ResearcherSpecialtyOption.BuiltInID
        var rows: [(String, String, Bool)] = []
        for option in ResearcherSpecialtyOption.builtInOptions {
            rows.append((option.nameSv, option.id, false))
            rows.append((option.nameEn, option.id, false))
        }
        let names: [(String, String)] = [
            ("family medicine", S.generalPractice),
            ("akutmedicin", S.emergencyMedicine),
            ("emergency care", S.emergencyMedicine),
            ("anestesiologi", S.anaesthesia),
            ("anestesi", S.anaesthesia),
            ("anesthesiology", S.anaesthesia),
            ("anaesthesiology", S.anaesthesia),
            ("anesthesia and intensive care", S.anaesthesia),
            ("anaesthesia", S.anaesthesia),
            ("anesthesia", S.anaesthesia),
            ("arbetsmedicin", S.occupationalMedicine),
            ("occupational medicine", S.occupationalMedicine),
            ("pediatrik", S.paediatrics),
            ("barnmedicin", S.paediatrics),
            ("pediatrics", S.paediatrics),
            ("barnpsykiatri", S.childPsychiatry),
            ("child psychiatry", S.childPsychiatry),
            ("dermatologi", S.dermatology),
            ("dermatology", S.dermatology),
            ("endokrinologi", S.endocrinology),
            ("endocrinology", S.endocrinology),
            ("diabetologi", S.endocrinology),
            ("diabetology", S.endocrinology),
            ("geriatric medicine", S.geriatrics),
            ("gastroenterologi", S.gastroenterology),
            ("gastroenterology", S.gastroenterology),
            ("hematology", S.haematology),
            ("infektionsmedicin", S.infectiousDiseases),
            ("infectious disease", S.infectiousDiseases),
            ("invärtesmedicin", S.internalMedicine),
            ("allmänkirurgi", S.surgery),
            ("general surgery", S.surgery),
            ("lungmedicin", S.respiratoryMedicine),
            ("pulmonology", S.respiratoryMedicine),
            ("pulmonary medicine", S.respiratoryMedicine),
            ("nefrologi", S.nephrology),
            ("obstetrics and gynecology", S.obstetrics),
            ("obstetrik", S.obstetrics),
            ("gynekologi", S.obstetrics),
            ("gynecology", S.obstetrics),
            ("gynaecology", S.obstetrics),
            ("orthopedics", S.orthopaedics),
            ("ortopedisk kirurgi", S.orthopaedics),
            ("orthopaedic surgery", S.orthopaedics),
            ("orthopedic surgery", S.orthopaedics),
            ("cardiothoracic surgery", S.thoracicSurgery),
            ("oftalmologi", S.ophthalmology),
            ("ögonmedicin", S.ophthalmology),
            ("öron näs hals", S.otorhinolaryngology),
            ("önh", S.otorhinolaryngology),
            ("otolaryngology", S.otorhinolaryngology),
            ("ear nose and throat", S.otorhinolaryngology),
            ("patologi", S.clinicalPathology),
            ("pathology", S.clinicalPathology),
        ]
        for name in names {
            rows.append((name.0, name.1, false))
        }
        let nouns: [(String, String)] = [
            ("allmänläkare", S.generalPractice),
            ("distriktsläkare", S.generalPractice),
            ("general practitioner", S.generalPractice),
            ("family physician", S.generalPractice),
            ("akutläkare", S.emergencyMedicine),
            ("emergency physician", S.emergencyMedicine),
            ("anestesiolog", S.anaesthesia),
            ("anestesiläkare", S.anaesthesia),
            ("anaesthetist", S.anaesthesia),
            ("anesthetist", S.anaesthesia),
            ("anesthesiologist", S.anaesthesia),
            ("anaesthesiologist", S.anaesthesia),
            ("barnläkare", S.paediatrics),
            ("pediatriker", S.paediatrics),
            ("pediatrician", S.paediatrics),
            ("paediatrician", S.paediatrics),
            ("barnpsykiater", S.childPsychiatry),
            ("child psychiatrist", S.childPsychiatry),
            ("dermatolog", S.dermatology),
            ("hudläkare", S.dermatology),
            ("dermatologist", S.dermatology),
            ("endokrinolog", S.endocrinology),
            ("endocrinologist", S.endocrinology),
            ("diabetolog", S.endocrinology),
            ("geriatriker", S.geriatrics),
            ("geriatrician", S.geriatrics),
            ("gastroenterolog", S.gastroenterology),
            ("gastroenterologist", S.gastroenterology),
            ("hematolog", S.haematology),
            ("hematologist", S.haematology),
            ("haematologist", S.haematology),
            ("infektionsläkare", S.infectiousDiseases),
            ("internmedicinare", S.internalMedicine),
            ("internist", S.internalMedicine),
            ("kardiolog", S.cardiology),
            ("cardiologist", S.cardiology),
            ("kirurg", S.surgery),
            ("surgeon", S.surgery),
            ("lungläkare", S.respiratoryMedicine),
            ("pulmonologist", S.respiratoryMedicine),
            ("neurolog", S.neurology),
            ("neurologist", S.neurology),
            ("nefrolog", S.nephrology),
            ("njurläkare", S.nephrology),
            ("nephrologist", S.nephrology),
            ("gynekolog", S.obstetrics),
            ("obstetriker", S.obstetrics),
            ("gynecologist", S.obstetrics),
            ("gynaecologist", S.obstetrics),
            ("obstetrician", S.obstetrics),
            ("onkolog", S.oncology),
            ("oncologist", S.oncology),
            ("ortoped", S.orthopaedics),
            ("orthopaedic surgeon", S.orthopaedics),
            ("orthopedic surgeon", S.orthopaedics),
            ("psykiater", S.psychiatry),
            ("psychiatrist", S.psychiatry),
            ("radiolog", S.radiology),
            ("radiologist", S.radiology),
            ("reumatolog", S.rheumatology),
            ("rheumatologist", S.rheumatology),
            ("thoraxkirurg", S.thoracicSurgery),
            ("thoracic surgeon", S.thoracicSurgery),
            ("urolog", S.urology),
            ("urologist", S.urology),
            ("ögonläkare", S.ophthalmology),
            ("ophthalmologist", S.ophthalmology),
            ("öronläkare", S.otorhinolaryngology),
            ("önh läkare", S.otorhinolaryngology),
            ("otolaryngologist", S.otorhinolaryngology),
            ("otorhinolaryngologist", S.otorhinolaryngology),
            ("patolog", S.clinicalPathology),
            ("pathologist", S.clinicalPathology),
        ]
        for noun in nouns {
            rows.append((noun.0, noun.1, true))
        }
        return rows
            .map { SpecialtySynonym(tokens: specialtyTokens($0.0), specialtyID: $0.1, impliesSpecialist: $0.2) }
            .filter { !$0.tokens.isEmpty }
            .sorted { lhs, rhs in
                if lhs.tokens.count != rhs.tokens.count {
                    return lhs.tokens.count > rhs.tokens.count
                }
                return lhs.tokens.joined().count > rhs.tokens.joined().count
            }
    }

    /// Orden i jämförelseform, utan skiljetecken och parenteser.
    private static func specialtyTokens(_ text: String) -> [String] {
        normalizedKey(text)
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",;:()[]/")) }
            .filter { !$0.isEmpty }
    }

    private static func containsSequence(_ needle: [String], in haystack: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return true
            }
        }
        return false
    }

    /// Första specialitet som nämns någonstans i texten (hela ord).
    static func specialtyMatch(in text: String) -> SpecialtyMatch? {
        let tokens = specialtyTokens(text)
        guard !tokens.isEmpty else { return nil }
        for synonym in cachedSpecialtySynonyms where containsSequence(synonym.tokens, in: tokens) {
            return SpecialtyMatch(specialtyID: synonym.specialtyID, impliesSpecialist: synonym.impliesSpecialist)
        }
        return nil
    }

    /// En text som bara är en specialitet ("geriatriker", "Kirurg",
    /// "i allmänmedicin") och inget annat; annars nil.
    static func looseSpecialty(in text: String) -> SpecialtyMatch? {
        var tokens = specialtyTokens(text)
        while let first = tokens.first, connectorWords.contains(first) {
            tokens.removeFirst()
        }
        guard !tokens.isEmpty else { return nil }
        for synonym in cachedSpecialtySynonyms where synonym.tokens == tokens {
            return SpecialtyMatch(specialtyID: synonym.specialtyID, impliesSpecialist: synonym.impliesSpecialist)
        }
        return nil
    }

    /// Specialitetsnamn med "och", "and" eller komma ("Obstetrik och
    /// gynekologi", "Öron-, näs- och halssjukdomar") byts mot en markör
    /// innan texten delas, så att namnet inte delas mitt i.
    static func protectingSpecialtyNames(_ text: String) -> (text: String, placeholders: [(marker: String, original: String)]) {
        var names: [String] = []
        for option in ResearcherSpecialtyOption.builtInOptions {
            names.append(option.nameSv)
            names.append(option.nameEn)
        }
        names.append("ear, nose and throat")
        names.append("ear nose and throat")
        names.append("obstetrics and gynecology")
        names.append("anesthesia and intensive care")
        let splitting: [String] = names
            .filter { name in
                let lowered = name.lowercased()
                return lowered.contains(" och ") || lowered.contains(" and ") || lowered.contains(",") || lowered.contains("/")
            }
            .sorted { $0.count > $1.count }
        var result = text
        var placeholders: [(marker: String, original: String)] = []
        for name in splitting {
            while let range = result.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) {
                let marker = "\u{E000}\(placeholders.count)\u{E001}"
                placeholders.append((marker: marker, original: String(result[range])))
                result.replaceSubrange(range, with: marker)
            }
        }
        return (text: result, placeholders: placeholders)
    }

    static func restoringSpecialtyNames(_ text: String, placeholders: [(marker: String, original: String)]) -> String {
        guard !placeholders.isEmpty else { return text }
        var result = text
        for placeholder in placeholders {
            result = result.replacingOccurrences(of: placeholder.marker, with: placeholder.original)
        }
        return result
    }

    /// "Annan"-texten för befattning delad i delar (vid komma, semikolon,
    /// snedstreck), utan att dela specialitetsnamn.
    static func otherPositionParts(_ text: String) -> [String] {
        let protected = protectingSpecialtyNames(text)
        return splitParts(protected.text, splitsOnWords: false)
            .map { restoringSpecialtyNames($0, placeholders: protected.placeholders) }
    }

    /// Engångssteget "round20b": forskare som redan har en läkarbefattning
    /// (ST-läkare, Specialistläkare, Överläkare) utan specialitet får den ur
    /// den gamla befattningstexten eller ur "annan"-texten. En del av
    /// "annan"-texten som är helt förklarad av det nya valet ("geriatriker",
    /// "Kirurg") flyttas ut därifrån; annat lämnas orört. Står ett
    /// specialistord ensamt i "annan"-texten och forskaren saknar
    /// läkarbefattning, blir det Specialistläkare med den specialiteten (som
    /// vid flytten från fritext). Den gamla texten, karriärsteget och
    /// doktorsexamen ändras aldrig. Att köra den igen ändrar ingenting.
    static func migratedSpecialties(_ author: PublicationAuthor) -> PublicationAuthor {
        let physicianSet = ResearcherPositionOption.specialtyPositionIDs
        var updated = author
        var newlyAssigned = Set<String>()

        func physicians() -> [String] {
            updated.positionIDs.filter { physicianSet.contains($0) }
        }
        func lacking() -> [String] {
            physicians().filter { updated.positionSpecialtyIDs[$0]?.trimmedOrNil == nil }
        }

        // 1. The old position text, e.g. "Specialistläkare i allmänmedicin".
        if !lacking().isEmpty {
            let swedishText = author.positionSv.trimmingCharacters(in: .whitespacesAndNewlines)
            let englishText = author.positionEn.trimmingCharacters(in: .whitespacesAndNewlines)
            var findings: [String: String] = mapPositionText(swedishText).specialtyIDs
            if normalizedKey(englishText) != normalizedKey(swedishText) {
                for (positionID, specialtyID) in mapPositionText(englishText).specialtyIDs where findings[positionID] == nil {
                    findings[positionID] = specialtyID
                }
            }
            for positionID in lacking() {
                if let specialtyID = findings[positionID] {
                    updated.positionSpecialtyIDs[positionID] = specialtyID
                    newlyAssigned.insert(specialtyID)
                }
            }
        }

        // 2. The "other" text: a part that is only a specialty.
        for isSwedish in [true, false] {
            let original = isSwedish ? updated.positionOtherSv : updated.positionOtherEn
            guard original.trimmedOrNil != nil else { continue }
            var kept: [String] = []
            var removedAny = false
            for part in otherPositionParts(original) {
                guard let loose = looseSpecialty(in: part) else {
                    kept.append(part)
                    continue
                }
                let currentLacking = lacking()
                let currentPhysicians = physicians()
                let alreadyExplained = newlyAssigned.contains(loose.specialtyID)
                    && currentPhysicians.contains(where: { updated.positionSpecialtyIDs[$0] == loose.specialtyID })
                if currentLacking.count == 1 {
                    updated.positionSpecialtyIDs[currentLacking[0]] = loose.specialtyID
                    newlyAssigned.insert(loose.specialtyID)
                    removedAny = true
                } else if currentLacking.isEmpty && alreadyExplained {
                    // Already explained by the specialty chosen in this step.
                    removedAny = true
                } else if currentPhysicians.isEmpty && loose.impliesSpecialist {
                    let specialistID = ResearcherPositionOption.BuiltInID.specialistPhysician
                    updated.positionIDs.append(specialistID)
                    updated.positionSpecialtyIDs[specialistID] = loose.specialtyID
                    newlyAssigned.insert(loose.specialtyID)
                    removedAny = true
                } else {
                    kept.append(part)
                }
            }
            if removedAny {
                let rebuilt = kept.joined(separator: ", ")
                if isSwedish {
                    updated.positionOtherSv = rebuilt
                } else {
                    updated.positionOtherEn = rebuilt
                }
            }
        }
        return updated
    }
}

// MARK: - Datakvalitet: rätta text utanför listorna

extension ResearcherLegacyFieldMapping {
    /// True när delen av "annan"-texten helt motsvarar befattningen: samma
    /// namn som i listan, eller exakt ett känt namn för den.
    static func positionPart(_ part: String, isExplainedBy option: ResearcherPositionOption) -> Bool {
        let key = normalizedKey(part)
        guard !key.isEmpty else { return false }
        if key == normalizedKey(option.nameSv) || key == normalizedKey(option.nameEn) {
            return true
        }
        return positionSynonyms().contains { $0.phrase == key && $0.ids == [option.id] }
    }

    /// True när texten helt motsvarar examen: samma namn eller förkortning
    /// som i listan, eller exakt en känd examen utan rest.
    static func degreeText(_ text: String, isExplainedBy option: ResearcherDegreeOption) -> Bool {
        let key = normalizedKey(text)
        guard !key.isEmpty else { return false }
        let names = [option.nameSv, option.nameEn, option.abbreviation]
            .map { normalizedKey($0) }
            .filter { !$0.isEmpty }
        if names.contains(key) {
            return true
        }
        let mapped = mapDegreeText(text)
        return mapped.unmappedParts.isEmpty
            && mapped.matches.count == 1
            && mapped.matches[0].optionID == option.id
    }

    /// En "annan examen"-rad som får ett val ur listan. Texten tappas aldrig
    /// i tysthet: har examen ett ämne blir resten av texten ämnet (eller
    /// hela texten när det är osäkert); utan ämne töms texten bara när den
    /// helt motsvarar examen, annars ligger den kvar på raden (syns igen om
    /// raden görs till "Annan examen…").
    static func degreeEntry(_ entry: ResearcherDegreeEntry, choosing option: ResearcherDegreeOption) -> ResearcherDegreeEntry {
        var updated = entry
        updated.optionID = option.id
        let text = entry.otherText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return updated }
        let explained = degreeText(text, isExplainedBy: option)
        if option.takesSubject {
            var subject = text
            if explained {
                let mapped = mapDegreeText(text)
                subject = mapped.matches.first(where: { $0.optionID == option.id })?.subject ?? ""
            }
            if updated.subjectSv.trimmedOrNil == nil {
                updated.subjectSv = subject
            }
            if updated.subjectEn.trimmedOrNil == nil {
                updated.subjectEn = subject
            }
            let subjectKept = normalizedKey(updated.subjectSv) == normalizedKey(subject)
                || normalizedKey(updated.subjectEn) == normalizedKey(subject)
            if explained || subjectKept {
                updated.otherText = ""
            }
        } else if explained {
            updated.otherText = ""
        }
        return updated
    }
}
