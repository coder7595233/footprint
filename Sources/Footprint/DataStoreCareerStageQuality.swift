import Foundation

extension GrantDataStore {
    /// Datakvalitet: karriärsteg (Frascati) som inte stämmer med doktorsexamen.
    /// - Steg D (doktorand) men forskaren har doktorsexamen.
    /// - Steg A–C kräver doktorsexamen men den saknas.
    /// Forskare utan karriärsteg (nil) kontrolleras inte.
    /// Dessutom:
    /// - karriärsteget skiljer sig från det som befattningen talar för;
    /// - befattning eller examen som inte finns i listorna (Inställningar > Listor).
    /// Id:t bygger bara på forskarens id och regeln, inte på språket, så att en
    /// dold varning förblir dold även när appens språk byts.
    func dataQualityCareerStageIssues() -> [IntegrityIssue] {
        let destination = AppRoute.Destination.people
        let destinationKey = Self.dataQualityDestinationKey(destination)
        let kind = IntegrityIssue.Kind.semantic
        let positionOptions = researcherPositionOptions
        let degreeOptions = researcherDegreeOptions
        var issues: [IntegrityIssue] = []

        func append(_ author: PublicationAuthor, ruleKey: String, subtitle: String, details: String) {
            issues.append(
                IntegrityIssue(
                    id: "\(kind.rawValue)-\(destinationKey)-\(author.id)-\(ruleKey)",
                    kind: kind,
                    destination: destination,
                    recordID: author.id,
                    title: author.displayName,
                    subtitle: subtitle,
                    details: details
                )
            )
        }

        for author in publicationAuthors {
            if let stage = author.careerStage {
                switch stage {
                case .categoryD where author.hasPhD:
                    append(
                        author,
                        ruleKey: "careerStage-D-hasPhD",
                        subtitle: language.text(
                            "Career stage D (doctoral student) but has a PhD",
                            "Karriärsteg D (doktorand) men har doktorsexamen"
                        ),
                        details: phdDetails(stage: stage, hasPhD: author.hasPhD)
                    )
                case .categoryA, .categoryB, .categoryC:
                    if !author.hasPhD {
                        append(
                            author,
                            ruleKey: "careerStage-\(stage.rawValue)-missingPhD",
                            subtitle: language.text(
                                "Career stages A–C require a PhD but the PhD is missing",
                                "Karriärsteg A–C kräver doktorsexamen men doktorsexamen saknas"
                            ),
                            details: phdDetails(stage: stage, hasPhD: author.hasPhD)
                        )
                    }
                default:
                    break
                }

                // The stage chosen differs from what the positions suggest.
                if let suggestion = author.careerStageSuggestion(options: positionOptions), suggestion != stage {
                    append(
                        author,
                        ruleKey: "careerStageSuggestion",
                        subtitle: language.text(
                            "Career stage \(stage.rawValue) does not match the position (suggested: \(suggestion.rawValue))",
                            "Karriärsteg \(stage.rawValue) stämmer inte med befattningen (förslag: \(suggestion.rawValue))"
                        ),
                        details: author.displayPosition(language: language, options: positionOptions)
                    )
                }
            }

            // Text that could not be matched to the lists (kept as "other").
            let otherPosition = author.localizedPositionOther(language: language)
            if let otherPosition = otherPosition.trimmedOrNil {
                append(
                    author,
                    ruleKey: "positionOutsideList",
                    subtitle: language.text(
                        "Position not in the list: \(otherPosition)",
                        "Befattning utanför listan: \(otherPosition)"
                    ),
                    details: language.text(
                        "Choose the position from the list, add it under Settings > Lists, or hide this warning.",
                        "Välj befattningen i listan, lägg till den under Inställningar > Listor eller dölj varningen."
                    )
                )
            }

            let otherDegrees = author.degreeEntries
                .filter { entry in
                    guard let optionID = entry.optionID else { return true }
                    return !degreeOptions.contains { $0.id == optionID }
                }
                .compactMap { $0.otherText.trimmedOrNil }
                .uniqued()
            if !otherDegrees.isEmpty {
                let text = otherDegrees.joined(separator: ", ")
                append(
                    author,
                    ruleKey: "degreeOutsideList",
                    subtitle: language.text(
                        "Degree not in the list: \(text)",
                        "Examen utanför listan: \(text)"
                    ),
                    details: language.text(
                        "Choose the degree from the list, add it under Settings > Lists, or hide this warning.",
                        "Välj examen i listan, lägg till den under Inställningar > Listor eller dölj varningen."
                    )
                )
            }
        }

        return issues
    }

    private func phdDetails(stage: PublicationAuthorCareerStage, hasPhD: Bool) -> String {
        let phdText = hasPhD
            ? language.text("has PhD", "har doktorsexamen")
            : language.text("no PhD", "saknar doktorsexamen")
        return "\(language.text("Career stage", "Karriärsteg")) \(stage.rawValue), \(phdText)"
    }
}
