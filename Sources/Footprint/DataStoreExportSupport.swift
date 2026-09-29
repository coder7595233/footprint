import AppKit
import Foundation

extension GrantDataStore {
    func confirmProceedingAfterValidation(title: String, issues: [String]) -> Bool {
        let deduplicated = Array(NSOrderedSet(array: issues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })) as? [String] ?? []
        guard !deduplicated.isEmpty else { return true }

        let alert = NSAlert()
        alert.messageText = language.text("Check before export", "Kontroll före export")
        let visibleIssues = deduplicated.prefix(12).map { "• \($0)" }.joined(separator: "\n")
        let moreText = deduplicated.count > 12
            ? "\n\n\(language.text("More issues exist in addition to those shown.", "Fler avvikelser finns utöver de som visas här."))"
            : ""
        alert.informativeText = "\(title)\n\n\(visibleIssues)\(moreText)\n\n\(language.text("Continue anyway?", "Fortsätta ändå?"))"
        alert.alertStyle = .warning
        alert.addButton(withTitle: language.text("Continue export", "Fortsätt export"))
        alert.addButton(withTitle: language.text("Cancel", "Avbryt"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func cvExportValidationIssues(style: CVDocumentExportStyle) -> [String] {
        guard let author = currentUserAuthor() else {
            return [language.text("No personal card is selected as your own profile.", "Ingen personlig profil är markerad som ditt eget personkort.")]
        }

        var issues: [String] = []
        if author.name.trimmedOrNil == nil {
            issues.append(language.text("Your name is missing in the personal card.", "Ditt namn saknas i personkortet."))
        }
        if author.phoneNumber.trimmedOrNil == nil && author.phoneNumberSecondary.trimmedOrNil == nil {
            issues.append(language.text("Phone number is missing in the personal card.", "Telefonnummer saknas i personkortet."))
        }
        if author.primaryAffiliation?.organization.trimmedOrNil == nil {
            issues.append(language.text("Primary affiliation organization is missing.", "Organisation saknas i primär affiliering."))
        }
        if author.primaryAffiliation?.email.trimmedOrNil == nil {
            issues.append(language.text("Primary affiliation email is missing.", "E-post saknas i primär affiliering."))
        }
        if author.primaryAffiliation?.country.trimmedOrNil == nil {
            issues.append(language.text("Primary affiliation country is missing.", "Land saknas i primär affiliering."))
        }
        if style == .liu {
            if author.birthDate.trimmedOrNil == nil {
                issues.append(language.text("Birth date is missing for the LiU CV.", "Födelsedatum saknas för LiU-CV."))
            }
            if author.homeAddress.trimmedOrNil == nil {
                issues.append(language.text("Home address is missing for the LiU CV.", "Hemadress saknas för LiU-CV."))
            }
            if author.employments.isEmpty {
                issues.append(language.text("Employment history is empty.", "Anställningshistorik saknas."))
            }
            if author.educationEntries.isEmpty {
                issues.append(language.text("Education entries are empty.", "Utbildningsposter saknas."))
            }
        }

        let incompleteConferenceCount = cvConferenceContributions.filter {
            ($0.localizedTitle(language: language).trimmedOrNil ?? $0.displayTitle.trimmedOrNil) == nil ||
            (($0.from.trimmedOrNil ?? $0.to.trimmedOrNil) == nil)
        }.count
        if incompleteConferenceCount > 0 {
            issues.append(language.text(
                "\(incompleteConferenceCount) conference contributions are missing title or date.",
                "\(incompleteConferenceCount) konferensbidrag saknar titel eller datum."
            ))
        }

        let incompleteMediaCount = cvMediaAppearances.filter {
            ($0.localizedDescription(language: language).trimmedOrNil ?? $0.localizedTitle(language: language).trimmedOrNil ?? $0.displayTitle.trimmedOrNil) == nil ||
            $0.date.trimmedOrNil == nil
        }.count
        if incompleteMediaCount > 0 {
            issues.append(language.text(
                "\(incompleteMediaCount) media appearances are missing title or completion date.",
                "\(incompleteMediaCount) poster under Medverkan i media saknar titel eller genomförandedatum."
            ))
        }

        let incompleteReviewCount = cvReviewEntries.filter {
            $0.date.trimmedOrNil == nil || $0.reference.trimmedOrNil == nil || $0.journalName.trimmedOrNil == nil
        }.count
        if incompleteReviewCount > 0 {
            issues.append(language.text(
                "\(incompleteReviewCount) reviews are missing date, journal, or reference.",
                "\(incompleteReviewCount) reviews saknar datum, tidskrift eller referens."
            ))
        }

        return issues
    }

    func teachingExportValidationIssues() -> [String] {
        guard !teachingAssignments.isEmpty else {
            return [language.text("There are no teaching assignments to export.", "Det finns inga undervisningsuppdrag att exportera.")]
        }

        var issues: [String] = []
        let missingCategoryCount = teachingAssignments.filter { $0.reportCategory == nil }.count
        if missingCategoryCount > 0 {
            issues.append(language.text(
                "\(missingCategoryCount) teaching assignments are missing report category.",
                "\(missingCategoryCount) undervisningsuppdrag saknar rapportkategori."
            ))
        }
        let missingContextCount = teachingAssignments.filter { $0.contextID == nil }.count
        if missingContextCount > 0 {
            issues.append(language.text(
                "\(missingContextCount) teaching assignments are missing context.",
                "\(missingContextCount) undervisningsuppdrag saknar sammanhang."
            ))
        }
        let missingActivityCount = teachingAssignments.filter { $0.activityName.trimmedOrNil == nil }.count
        if missingActivityCount > 0 {
            issues.append(language.text(
                "\(missingActivityCount) teaching assignments are missing activity.",
                "\(missingActivityCount) undervisningsuppdrag saknar aktivitet."
            ))
        }
        let incompletePeriodCount = teachingAssignments.reduce(into: 0) { total, assignment in
            total += assignment.periods.filter { $0.from.trimmedOrNil == nil || $0.hoursPerTerm.trimmedOrNil == nil }.count
        }
        if incompletePeriodCount > 0 {
            issues.append(language.text(
                "\(incompletePeriodCount) teaching periods are missing start date or hours per term.",
                "\(incompletePeriodCount) undervisningsperioder saknar startdatum eller timmar per termin."
            ))
        }
        return issues
    }

    func publicationSubmissionValidationIssues(for publication: PublicationRecord) -> [String] {
        var issues: [String] = []
        if publication.title.trimmedOrNil == nil {
            issues.append(language.text("Publication title is missing.", "Publikationstitel saknas."))
        }
        if publication.authorNames.isEmpty {
            issues.append(language.text("The publication has no authors.", "Publikationen saknar författare."))
        }
        if publication.journal.trimmedOrNil == nil {
            issues.append(language.text("Journal is missing.", "Tidskrift saknas."))
        }

        let authors = publication.authorNames.compactMap { publicationAuthor(matchingPresentedName: $0) }
        let missingOrganizationCount = authors.filter { $0.primaryAffiliation?.organization.trimmedOrNil == nil }.count
        let missingCityCount = authors.filter { $0.primaryAffiliation?.city.trimmedOrNil == nil }.count
        let missingCountryCount = authors.filter { $0.primaryAffiliation?.country.trimmedOrNil == nil }.count
        let missingEmailCount = authors.filter { $0.primaryAffiliation?.email.trimmedOrNil == nil }.count
        if missingOrganizationCount > 0 {
            issues.append(language.text(
                "\(missingOrganizationCount) authors are missing affiliation organization.",
                "\(missingOrganizationCount) författare saknar affilieringsorganisation."
            ))
        }
        if missingCityCount > 0 {
            issues.append(language.text(
                "\(missingCityCount) authors are missing affiliation city.",
                "\(missingCityCount) författare saknar ort i affiliering."
            ))
        }
        if missingCountryCount > 0 {
            issues.append(language.text(
                "\(missingCountryCount) authors are missing affiliation country.",
                "\(missingCountryCount) författare saknar land i affiliering."
            ))
        }
        if missingEmailCount > 0 {
            issues.append(language.text(
                "\(missingEmailCount) authors are missing email.",
                "\(missingEmailCount) författare saknar e-post."
            ))
        }
        return issues
    }

    func projectSubmissionValidationIssues(for project: ProjectRecord) -> [String] {
        let collaboratorNames = normalizedProjectSubmissionCollaboratorNames(for: project)
        let authors = collaboratorNames.compactMap { publicationAuthor(matchingPresentedName: $0) }

        var issues: [String] = []
        if collaboratorNames.isEmpty {
            issues.append(language.text(
                "The project has no collaborators.",
                "Projektet saknar medarbetare."
            ))
        }
        if !collaboratorNames.isEmpty && authors.isEmpty {
            issues.append(language.text(
                "The project collaborators do not resolve to any researcher profiles.",
                "Projektets medarbetare går inte att matcha mot några forskarprofiler."
            ))
        }

        let missingOrganizationCount = authors.filter { $0.primaryAffiliation?.organization.trimmedOrNil == nil }.count
        let missingCityCount = authors.filter { $0.primaryAffiliation?.city.trimmedOrNil == nil }.count
        let missingCountryCount = authors.filter { $0.primaryAffiliation?.country.trimmedOrNil == nil }.count
        let missingEmailCount = authors.filter { $0.primaryAffiliation?.email.trimmedOrNil == nil }.count
        if missingOrganizationCount > 0 {
            issues.append(language.text(
                "\(missingOrganizationCount) researchers are missing affiliation organization.",
                "\(missingOrganizationCount) forskare saknar affilieringsorganisation."
            ))
        }
        if missingCityCount > 0 {
            issues.append(language.text(
                "\(missingCityCount) researchers are missing affiliation city.",
                "\(missingCityCount) forskare saknar ort i affiliering."
            ))
        }
        if missingCountryCount > 0 {
            issues.append(language.text(
                "\(missingCountryCount) researchers are missing affiliation country.",
                "\(missingCountryCount) forskare saknar land i affiliering."
            ))
        }
        if missingEmailCount > 0 {
            issues.append(language.text(
                "\(missingEmailCount) researchers are missing email.",
                "\(missingEmailCount) forskare saknar e-post."
            ))
        }

        if project.nameSv.trimmedOrNil == nil && project.nameEn.trimmedOrNil == nil {
            issues.append(language.text(
                "Project name is missing.",
                "Projektnamn saknas."
            ))
        }

        return issues
    }

    func publicationWorkbookValidationIssues() -> [String] {
        guard let selectedID = metadata.lastSelectedPublicationID,
              let selected = publication(id: selectedID) else {
            return publicationRecords.isEmpty
                ? [language.text("There are no publications in the current view.", "Det finns inga publikationer i den aktuella vyn.")]
                : []
        }
        return publicationSubmissionValidationIssues(for: selected)
    }

    func currentViewWorkbookValidationIssues() -> [String] {
        switch lastSelectedTabRaw ?? "home" {
        case "teaching":
            return teachingExportValidationIssues()
        case "cv":
            return cvExportValidationIssues(style: .own)
        case "publications":
            return publicationWorkbookValidationIssues()
        default:
            return []
        }
    }

    func applyLayout(_ layout: ExportDocumentLayoutOptions, to payload: inout CVExportDocument, exportLanguage: AppLanguage) {
        guard payload.style != CVDocumentExportStyle.liu.rawValue else {
            payload.headerText = ""
            payload.footerText = ""
            payload.includePageNumbers = false
            return
        }

        let (headerText, footerText) = layoutHeaderFooterTexts(layout, exportLanguage: exportLanguage)
        payload.headerText = headerText
        payload.footerText = footerText
        payload.includePageNumbers = layout.includePageNumbers
    }

    func layoutHeaderFooterTexts(_ layout: ExportDocumentLayoutOptions, exportLanguage: AppLanguage) -> (String, String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: exportLanguage == .swedish ? "sv_SE" : "en_US")
        formatter.dateStyle = .long
        let currentDateText = formatter.string(from: Date())
        switch layout.currentDatePlacement {
        case .none:
            return ("", "")
        case .header:
            return (currentDateText, "")
        case .footer:
            return ("", currentDateText)
        }
    }

    func preferredCVExportFileName(for style: CVDocumentExportStyle, exportLanguage: AppLanguage) -> String {
        let authorName = sanitizedFileNameComponent(currentUserAuthor()?.name.nonEmpty ?? language.text("CV", "CV"))
        let languageSuffix = exportLanguage == .swedish ? "svenska" : "English"
        let stem: String = {
            switch style {
            case .vetenskapsradet:
                return "Vetenskapsrådet CV \(authorName)"
            case .liu, .own:
                return "CV \(authorName) (\(languageSuffix))"
            }
        }()
        return "\(stem) \(cvExportTimestampString()).docx"
    }

    func cvExportTimestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return formatter.string(from: Date())
    }

    func sanitizedFileNameComponent(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let pieces = raw.components(separatedBy: forbidden)
        let joined = pieces.joined(separator: " ")
        let collapsed = joined.replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedExportDirectoryPath(_ url: URL?) -> String? {
        guard let url else { return nil }
        let standardized = url.standardizedFileURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !standardized.isEmpty else { return nil }
        let downloads = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL.path
        return standardized == downloads ? nil : standardized
    }

    static func normalizedDropdownOverrides(_ values: [String: String], language: AppLanguage) -> [String: String]? {
        let definitionsByKey = Dictionary(uniqueKeysWithValues: editableDropdownTranslationDefinitions.map { ($0.key, $0) })
        let normalized = values.reduce(into: [String: String]()) { partialResult, entry in
            guard let definition = definitionsByKey[entry.key] else { return }
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let defaultValue = language == .english ? definition.defaultEn : definition.defaultSv
            guard trimmed != defaultValue else { return }
            partialResult[entry.key] = trimmed
        }
        return normalized.isEmpty ? nil : normalized
    }

    func exportDestinationURL(fileName: String) -> URL {
        let directory = exportDirectoryURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(sanitizedFileNameComponent(fileName))
    }

    /// True while the code runs inside the XCTest runner. Automatic
    /// open-after-export must stay off there: tests that drive the real
    /// export pipeline would otherwise launch Excel/Word on every test run.
    nonisolated static var suppressesAutomaticExportOpening: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    @discardableResult
    func openExportedFileIfAvailable(_ url: URL) -> Bool {
        guard !Self.suppressesAutomaticExportOpening else { return true }
        guard loadError == nil, FileManager.default.fileExists(atPath: url.path) else { return false }
        guard NSWorkspace.shared.open(url) else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return false
        }
        return true
    }
}
