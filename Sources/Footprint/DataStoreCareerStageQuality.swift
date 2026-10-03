import Foundation

extension GrantDataStore {
    /// Datakvalitet: karriärsteg (Frascati) som inte stämmer med doktorsexamen.
    /// - Steg D (doktorand) men forskaren har doktorsexamen.
    /// - Steg A–C kräver doktorsexamen men den saknas.
    /// Forskare utan karriärsteg (nil) kontrolleras inte.
    /// Id:t bygger bara på forskarens id och regeln, inte på språket, så att en
    /// dold varning förblir dold även när appens språk byts.
    func dataQualityCareerStageIssues() -> [IntegrityIssue] {
        let destination = AppRoute.Destination.people
        let destinationKey = Self.dataQualityDestinationKey(destination)
        var issues: [IntegrityIssue] = []

        for author in publicationAuthors {
            guard let stage = author.careerStage else { continue }

            let ruleKey: String
            let subtitle: String
            switch stage {
            case .categoryD:
                guard author.hasPhD else { continue }
                ruleKey = "careerStage-D-hasPhD"
                subtitle = language.text(
                    "Career stage D (doctoral student) but has a PhD",
                    "Karriärsteg D (doktorand) men har doktorsexamen"
                )
            case .categoryA, .categoryB, .categoryC:
                guard !author.hasPhD else { continue }
                ruleKey = "careerStage-\(stage.rawValue)-missingPhD"
                subtitle = language.text(
                    "Career stages A–C require a PhD but the PhD is missing",
                    "Karriärsteg A–C kräver doktorsexamen men doktorsexamen saknas"
                )
            }

            let phdText = author.hasPhD
                ? language.text("has PhD", "har doktorsexamen")
                : language.text("no PhD", "saknar doktorsexamen")
            let details = "\(language.text("Career stage", "Karriärsteg")) \(stage.rawValue), \(phdText)"
            let kind = IntegrityIssue.Kind.semantic
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

        return issues
    }
}
