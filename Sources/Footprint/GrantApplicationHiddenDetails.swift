import Foundation

// MARK: - Hidden application details (round 11)
//
// A record marked "Ej sökt" hides the whole application part, but what was
// written there is kept. The editor lists which fields hold something, so
// nothing sits there unseen (user decision 2026-09-30).

extension GrantApplication {
    /// Names of the filled fields in the hidden application part, in the
    /// order they appear in the editor. `hasOtherApplicants` is true when
    /// someone besides the user is listed as applicant.
    func hiddenApplicationDetailTitles(hasOtherApplicants: Bool, language: AppLanguage) -> [String] {
        var titles: [String] = []
        func add(_ value: String?, _ english: String, _ swedish: String) {
            if value?.trimmedOrNil != nil { titles.append(language.text(english, swedish)) }
        }
        if hasOtherApplicants { titles.append(language.text("Co-applicants", "Medsökande")) }
        add(projectID, "Project", "Projekt")
        add(applicationTitle, "Application title", "Ansökningstitel")
        add(appliedAmount, "Applied amount", "Sökt belopp")
        add(appliedCaseNumber, "Grant number", "Ansökningsnummer")
        add(applicationManagerID ?? applicationManager, "Fund manager", "Medelsförvaltare")
        add(managerReason, "Reason for fund manager", "Skäl till medelsförvaltare")
        add(institutionCaseNumber, "Case number", "Diarienummer")
        add(primaryLink, "Link to grant call", "Länk till utlysningen")
        add(secondaryLink, "Link to application", "Länk till ansökan")
        return titles
    }
}
