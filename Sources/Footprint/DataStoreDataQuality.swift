import AppKit
import Foundation

extension GrantDataStore {
    /// Words that mark a value as wrong rather than missing: dates in the wrong
    /// order, invalid formats, overlaps. Shared by the Data view's severity and
    /// by the check after saving (F19).
    nonisolated static let criticalDataQualityFragments: [String] = [
        " before ",
        " after ",
        " före ",
        " efter ",
        "conflicting",
        "motstrid",
        "invalid",
        "ogiltig",
        "not numeric",
        "inte numeriskt",
        "duplicate years",
        "dubbla år",
        "out of order",
        "fel ordning",
        "overlaps",
        "överlappar",
        "not a real country",
        "inte ett riktigt land",
    ]

    /// Case is ignored, but å, ä and ö are kept: folded, "före" would also
    /// match "företag". "före" and "efter" count as whole words only.
    nonisolated static func isCriticalDataQualityField(_ field: String) -> Bool {
        let candidate = " \(field.lowercased()) "
        return criticalDataQualityFragments.contains(where: { candidate.contains($0) })
    }

    /// "8:15", "0815" and "08:15" all read as 495; anything else is nil.
    nonisolated static func dataQualityMinutesOfDay(_ raw: String) -> Int? {
        let parts = normalizedCalendarTimeInput(raw).split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              (0..<24).contains(hours),
              (0..<60).contains(minutes) else {
            return nil
        }
        return hours * 60 + minutes
    }

    /// F19: an end time earlier than the start time on the same day. An end
    /// at 00:00 means midnight and is not flagged.
    nonisolated static func dataQualityTimeEndsBeforeStart(start: String, end: String) -> Bool {
        guard let startMinutes = dataQualityMinutesOfDay(start),
              let endMinutes = dataQualityMinutesOfDay(end),
              endMinutes != 0 else {
            return false
        }
        return endMinutes < startMinutes
    }

    func dataQualityMissingFieldIssues() -> [MissingFieldIssue] {
        var issues: [MissingFieldIssue] = []
        // A task edited centrally supersedes the legacy copy on the record.
        let centralTaskIDs = Set(taskItems.map(\.id))
        func parsedDay(_ value: String?) -> Date? {
            guard let value = value?.trimmedOrNil else { return nil }
            return DateParsers.isoDay.date(from: value)
        }
        func numericAmount(_ value: String?) -> Double? {
            guard let value = value?.trimmedOrNil else { return nil }
            return GrantParsing.numericValue(from: value)
        }
        func looksLikeWebURL(_ value: String?) -> Bool {
            guard let trimmed = value?.trimmedOrNil else { return true }
            let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false else {
                return false
            }
            return true
        }
        func looksLikeEmail(_ value: String?) -> Bool {
            guard let trimmed = value?.trimmedOrNil else { return true }
            let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
            return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        func looksLikeDOI(_ value: String?) -> Bool {
            guard let trimmed = value?.trimmedOrNil else { return true }
            let cleaned = trimmed
                .replacingOccurrences(of: "https://doi.org/", with: "")
                .replacingOccurrences(of: "http://doi.org/", with: "")
                .replacingOccurrences(of: "doi.org/", with: "")
            let pattern = #"^10\.\d{4,9}/\S+$"#
            return cleaned.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        func looksLikePMID(_ value: String?) -> Bool {
            guard let trimmed = value?.trimmedOrNil else { return true }
            return trimmed.allSatisfy(\.isNumber)
        }
        func looksLikeORCID(_ value: String?) -> Bool {
            guard let trimmed = value?.trimmedOrNil else { return true }
            let cleaned = trimmed
                .replacingOccurrences(of: "https://orcid.org/", with: "")
                .replacingOccurrences(of: "http://orcid.org/", with: "")
                .replacingOccurrences(of: "orcid.org/", with: "")
            let pattern = #"^\d{4}-\d{4}-\d{4}-\d{3}[\dX]$"#
            return cleaned.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        func visibleDispositionStart(for application: GrantApplication) -> Date? {
            application.firstDispositionDate ?? parsedDay(application.receivedUsageFrom)
        }
        func visibleDispositionEnd(for application: GrantApplication) -> Date? {
            application.lastDispositionDate ?? parsedDay(application.receivedUsageTo)
        }
        func latestPublicationTimelineEntry(for publication: PublicationRecord) -> PublicationStatusEntry? {
            publicationEffectiveStatusEntry(from: publicationDerivedSubmissionRows(from: publication.statusTimeline))
        }
        func isKnownCountry(_ value: String?) -> Bool {
            guard let trimmed = value?.trimmedOrNil else { return true }
            let canonical = GrantParsing.canonicalCountryName(trimmed)
            return GrantParsing.countryOptions.contains(canonical)
        }
        func shouldTreatAsCritical(_ fields: [String]) -> Bool {
            fields.contains(where: Self.isCriticalDataQualityField)
        }
        func reasonText(for fields: [String]) -> String {
            let joined = fields.joined(separator: ", ")
            if shouldTreatAsCritical(fields) {
                return language.text(
                    "This record is flagged because one or more critical values are invalid or logically inconsistent: \(joined).",
                    "Den här posten är flaggad eftersom ett eller flera kritiska värden är ogiltiga eller logiskt orimliga: \(joined)."
                )
            }
            return language.text(
                "This record is flagged because required or expected information is missing: \(joined).",
                "Den här posten är flaggad eftersom obligatorisk eller förväntad information saknas: \(joined)."
            )
        }
        func suggestedFixText(for fields: [String]) -> String {
            let joined = fields.joined(separator: ", ")
            if shouldTreatAsCritical(fields) {
                return language.text(
                    "Open the record and correct these values so the format and date order are valid: \(joined).",
                    "Öppna posten och rätta dessa värden så att format och datumordning blir giltiga: \(joined)."
                )
            }
            return language.text(
                "Open the record and fill in or complete these fields: \(joined).",
                "Öppna posten och fyll i eller komplettera dessa fält: \(joined)."
            )
        }
        func enrichedIssue(_ issue: MissingFieldIssue) -> MissingFieldIssue {
            MissingFieldIssue(
                id: issue.id,
                entityKind: issue.entityKind,
                recordID: issue.recordID,
                destination: issue.destination,
                title: issue.title,
                subtitle: issue.subtitle,
                missingFields: issue.missingFields,
                severity: shouldTreatAsCritical(issue.missingFields) ? .critical : .warning,
                whyFlagged: reasonText(for: issue.missingFields),
                suggestedFix: suggestedFixText(for: issue.missingFields)
            )
        }

        for application in applications {
            // A call that is still open is not expected to be filled in yet,
            // so only wrong values (dates in the wrong order, invalid
            // amounts) are listed for it, never missing fields.
            let isOpenCall = application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "Att söka"
                && (application.closeDate.map { $0 >= Calendar.current.startOfDay(for: Date()) } ?? false)
            var missing: [String] = []
            if application.organization.trimmedOrNil == nil {
                missing.append(language.text("Funder", "Anslagsgivare"))
            }
            if application.derivedResult?.trimmedOrNil == nil {
                missing.append(language.text("Status", "Status"))
            }
            let trimmedStatus = application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStatus != "Ej sökt" {
                if application.projectType?.trimmedOrNil == nil {
                    missing.append(language.text("Project", "Projekt"))
                }
                if application.applicationTitle?.trimmedOrNil == nil {
                    missing.append(language.text("Application title", "Ansökningstitel"))
                }
            }
            if trimmedStatus == "Att söka" || trimmedStatus == "Väntar svar" {
                if application.closesOn?.trimmedOrNil == nil {
                    missing.append(language.text("Closing date", "Stängningsdatum"))
                }
            }
            if application.isGranted {
                if application.grantedAmount?.trimmedOrNil == nil {
                    missing.append(language.text("Granted amount", "Beviljat belopp"))
                }
                if application.firstDispositionOn?.trimmedOrNil == nil {
                    missing.append(language.text("First disposition", "Första disponering"))
                }
                if application.lastDispositionOn?.trimmedOrNil == nil {
                    missing.append(language.text("Last disposition", "Sista disponering"))
                }
            }
            if ["Väntar svar", "Beviljat", "Avslag", "Tillbakadragen"].contains(trimmedStatus),
               application.appliedOn?.trimmedOrNil == nil {
                missing.append(language.text("Application date", "Ansökningsdatum"))
            }
            if trimmedStatus == "Beviljat", application.grantedOn?.trimmedOrNil == nil {
                missing.append(language.text("Granted", "Beviljandedatum"))
            }
            if trimmedStatus == "Avslag", application.deniedOn?.trimmedOrNil == nil {
                missing.append(language.text("Declined", "Avslagsdatum"))
            }
            if trimmedStatus == "Tillbakadragen", application.withdrawnOn?.trimmedOrNil == nil {
                missing.append(language.text("Withdrawn", "Tillbakadragen"))
            }
            if trimmedStatus != "Ej sökt", application.coApplicants.isEmpty {
                missing.append(language.text("Applicant", "Sökande"))
            }
            if let openDate = application.openDate,
               let closeDate = application.closeDate,
               closeDate < openDate {
                missing.append(language.text("Closing date before opening date", "Stängningsdatum före öppningsdatum"))
            }
            if let appliedDate = parsedDay(application.appliedOn),
               let openDate = application.openDate,
               appliedDate < openDate {
                missing.append(language.text("Application date before opening date", "Ansökningsdatum före öppningsdatum"))
            }
            if let appliedDate = parsedDay(application.appliedOn),
               let closeDate = application.closeDate,
               appliedDate > closeDate {
                missing.append(language.text("Application date after closing date", "Ansökningsdatum efter stängningsdatum"))
            }
            if let firstDisposition = application.firstDispositionDate,
               let lastDisposition = application.lastDispositionDate,
               lastDisposition < firstDisposition {
                missing.append(language.text("Last disposition before first disposition", "Sista disponering före första disponering"))
            }
            if let appliedDate = parsedDay(application.appliedOn),
               let grantedDate = parsedDay(application.grantedOn),
               grantedDate < appliedDate {
                missing.append(language.text("Granted date before application date", "Beviljandedatum före ansökningsdatum"))
            }
            if let appliedDate = parsedDay(application.appliedOn),
               let deniedDate = parsedDay(application.deniedOn),
               deniedDate < appliedDate {
                missing.append(language.text("Declined date before application date", "Avslagsdatum före ansökningsdatum"))
            }
            if let appliedDate = parsedDay(application.appliedOn),
               let withdrawnDate = parsedDay(application.withdrawnOn),
               withdrawnDate < appliedDate {
                missing.append(language.text("Withdrawn date before application date", "Tillbakadraget-datum före ansökningsdatum"))
            }
            let outcomeDates = [
                application.grantedOn?.trimmedOrNil,
                application.deniedOn?.trimmedOrNil,
                application.withdrawnOn?.trimmedOrNil
            ]
            .compactMap { $0 }
            if outcomeDates.count > 1 {
                missing.append(language.text("Conflicting application outcomes", "Motstridiga ansökningsutfall"))
            }
            if let appliedAmount = application.appliedAmountValue ?? numericAmount(application.appliedAmount),
               let grantedAmount = application.grantedAmountValue ?? numericAmount(application.grantedAmount),
               grantedAmount > appliedAmount {
                missing.append(language.text("Granted amount exceeds applied amount", "Beviljat belopp överstiger sökt belopp"))
            }
            if application.appliedAmount?.trimmedOrNil != nil,
               (application.appliedAmountValue ?? numericAmount(application.appliedAmount)) == nil {
                missing.append(language.text("Applied amount is not numeric", "Sökt belopp är inte numeriskt"))
            }
            if application.grantedAmount?.trimmedOrNil != nil,
               (application.grantedAmountValue ?? numericAmount(application.grantedAmount)) == nil {
                missing.append(language.text("Granted amount is not numeric", "Beviljat belopp är inte numeriskt"))
            }
            if application.receivedConsumedAmount?.trimmedOrNil != nil,
               (application.receivedConsumedAmountValue ?? numericAmount(application.receivedConsumedAmount)) == nil {
                missing.append(language.text("Consumed amount is not numeric", "Förbrukat belopp är inte numeriskt"))
            }
            if application.receivedConsumptionPeriods.contains(where: {
                if let from = parsedDay($0.from), let to = parsedDay($0.to) {
                    return to < from
                }
                return false
            }) {
                missing.append(language.text("Consumption period ends before it starts", "Förbrukningsperiod slutar före den börjar"))
            }
            if let usageFrom = visibleDispositionStart(for: application),
               application.receivedConsumptionPeriods.contains(where: {
                   guard let periodFrom = parsedDay($0.from) else { return false }
                   return periodFrom < usageFrom
               }) {
                missing.append(language.text("Consumption starts before disposition start", "Förbrukning startar före första disponering"))
            }
            if let usageTo = visibleDispositionEnd(for: application),
               application.receivedConsumptionPeriods.contains(where: {
                   guard let periodTo = parsedDay($0.to) else { return false }
                   return periodTo > usageTo
               }) {
                missing.append(language.text("Consumption ends after disposition end", "Förbrukning slutar efter sista disponering"))
            }
            if isOpenCall {
                missing = missing.filter(Self.isCriticalDataQualityField)
            }
            if !missing.isEmpty {
                issues.append(
                    MissingFieldIssue(
                        id: "application-\(application.id)",
                        entityKind: .application,
                        recordID: application.id,
                        destination: .applications,
                        title: displayTitle(for: application, language: language),
                        subtitle: [
                            organizationLabel(for: application, language: language).nonEmpty,
                            projectLabel(for: application, language: language).flatMap { $0.nonEmpty }
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · "),
                        missingFields: missing
                    )
                )
            }
        }

        for project in projects where !project.isArchived {
            var missing: [String] = []
            if project.nameSv.trimmedOrNil == nil {
                missing.append(language.text("Swedish name", "Svenskt namn"))
            }
            if project.collaboratorNames.isEmpty {
                missing.append(language.text("Collaborators", "Medarbetare"))
            }
            // F12: a missing English name is listed under "Missing translations".
            let ethicsApplications = [project.ethicsBaseApplication] + project.ethicsAmendments
            if ethicsApplications.contains(where: {
                if let applied = parsedDay($0.appliedOn), let granted = parsedDay($0.grantedOn) {
                    return granted < applied
                }
                return false
            }) {
                missing.append(language.text("Ethics granted date before application date", "Etikgodkännande före ansökningsdatum"))
            }
            if project.dataCollections.contains(where: {
                if let from = parsedDay($0.from), let to = parsedDay($0.to) {
                    return to < from
                }
                return false
            }) {
                missing.append(language.text("Data collection ends before it starts", "Datainsamling slutar före den börjar"))
            }
            if project.ethicsBaseApplication.isEmpty == true && !project.ethicsAmendments.filter({ !$0.isEmpty }).isEmpty {
                missing.append(language.text("Ethics amendment without base application", "Etikändring utan basansökan"))
            }
            if project.clinicalTrialRegistrations.contains(where: {
                if let registered = parsedDay($0.registeredOn), let updated = parsedDay($0.updatedOn) {
                    return updated < registered
                }
                return false
            }) {
                missing.append(language.text("Clinical trial update before registration", "Clinical trial-uppdatering före registrering"))
            }
            if project.clinicalTrialRegistrations.contains(where: {
                $0.trialID.trimmedOrNil == nil && ($0.registeredOn.trimmedOrNil != nil || $0.updatedOn.trimmedOrNil != nil)
            }) {
                missing.append(language.text("Clinical trial ID missing", "Clinical trial-ID saknas"))
            }
            if !missing.isEmpty {
                issues.append(
                    MissingFieldIssue(
                        id: "project-\(project.id)",
                        entityKind: .project,
                        recordID: project.id,
                        destination: .projects,
                        title: dataQualityLocalizedOptionDisplayName(project),
                        subtitle: language.text("Project", "Projekt"),
                        missingFields: missing
                    )
                )
            }
        }

        for organization in organizations {
            var missing: [String] = []
            if organization.roles.contains(.grantProvider), organization.category?.trimmedOrNil == nil {
                missing.append(language.text("Category", "Kategori"))
            }
            if let membershipFrom = Int(organization.membershipFrom),
               let membershipTo = Int(organization.membershipTo),
               membershipTo < membershipFrom {
                missing.append(language.text("Membership end year before start year", "Medlemskapets slutår före startår"))
            }
            if organization.congresses.contains(where: {
                if let from = parsedDay($0.from), let to = parsedDay($0.to) {
                    return to < from
                }
                return false
            }) {
                missing.append(language.text("Congress end date before start date", "Kongressens slutdatum före startdatum"))
            }
            if organization.congresses.contains(where: {
                if let deadline = parsedDay($0.abstractSubmissionDeadline), let start = parsedDay($0.from) {
                    return deadline > start
                }
                return false
            }) {
                missing.append(language.text("Abstract deadline after congress start", "Abstractdeadline efter kongressstart"))
            }
            if organization.congresses.contains(where: {
                if let deadline = parsedDay($0.abstractSubmissionDeadline), let lateDeadline = parsedDay($0.lateAbstractSubmissionDeadline) {
                    return lateDeadline < deadline
                }
                return false
            }) {
                missing.append(language.text("Late abstract deadline before regular deadline", "Sen abstractdeadline före ordinarie deadline"))
            }
            if organization.congresses.contains(where: {
                $0.title.trimmedOrNil == nil &&
                (
                    $0.from.trimmedOrNil != nil ||
                    $0.to.trimmedOrNil != nil ||
                    $0.abstractSubmissionDeadline.trimmedOrNil != nil ||
                    $0.lateAbstractSubmissionDeadline.trimmedOrNil != nil
                )
            }) {
                missing.append(language.text("Congress title missing", "Kongresstitel saknas"))
            }
            if organization.country.trimmedOrNil != nil && !isKnownCountry(organization.country) {
                missing.append(language.text("Organization country is not a real country", "Organisationens land är inte ett riktigt land"))
            }
            if !looksLikeWebURL(organization.websiteURL) {
                missing.append(language.text("Website URL is invalid", "Hemsidelänk är ogiltig"))
            }
            if !missing.isEmpty {
                issues.append(
                    MissingFieldIssue(
                        id: "organization-\(organization.id)",
                        entityKind: .organization,
                        recordID: organization.id,
                        destination: .organizations,
                        title: dataQualityLocalizedOptionDisplayName(organization),
                        subtitle: language.text("Funder", "Anslagsgivare"),
                        missingFields: missing
                    )
                )
            }
        }

        for author in publicationAuthors {
            var missing: [String] = []
            if author.firstName.trimmedOrNil == nil {
                missing.append(language.text("First name", "Förnamn"))
            }
            if author.lastName.trimmedOrNil == nil {
                missing.append(language.text("Last name", "Efternamn"))
            }
            if author.title.trimmedOrNil == nil {
                missing.append(language.text("Title", "Titel"))
            }
            if author.position.trimmedOrNil == nil {
                missing.append(language.text("Position", "Position"))
            }
            if author.degree.trimmedOrNil == nil {
                missing.append(language.text("Degree", "Examen"))
            }
            if author.orcid.trimmedOrNil == nil {
                missing.append("ORCID")
            }
            if author.primaryAffiliation?.organization.trimmedOrNil == nil {
                missing.append(language.text("Primary affiliation organization", "Primär affilieringsorganisation"))
            }
            if author.primaryAffiliation?.country.trimmedOrNil == nil {
                missing.append(language.text("Primary affiliation country", "Primärt land"))
            }
            if author.primaryAffiliation?.email.trimmedOrNil == nil {
                missing.append(language.text("Primary affiliation email", "Primär e-post"))
            }
            if author.gender == .unspecified {
                missing.append(language.text("Gender", "Kön"))
            }
            if !looksLikeORCID(author.orcid) {
                missing.append(language.text("ORCID format is invalid", "ORCID-formatet är ogiltigt"))
            } else if let orcid = author.orcid.trimmedOrNil,
                      !PublicationAuthor.isValidORCID(PublicationAuthor.normalizedORCID(orcid)) {
                // F19: the right shape but a mistyped digit; the last
                // character is a check digit computed from the others.
                missing.append(language.text("ORCID check digit is invalid", "ORCID har ogiltig kontrollsiffra"))
            }
            if !author.affiliations.isEmpty && author.affiliations.filter(\.isPrimary).count > 1 {
                missing.append(language.text("Multiple primary affiliations", "Flera primära affilieringar"))
            }
            if author.affiliations.contains(where: { $0.country.trimmedOrNil != nil && !isKnownCountry($0.country) }) {
                missing.append(language.text("Affiliation country is not a real country", "Affilieringsland är inte ett riktigt land"))
            }
            if author.affiliations.contains(where: { !looksLikeEmail($0.email) }) {
                missing.append(language.text("Affiliation email is invalid", "Affilierings-e-post är ogiltig"))
            }
            if author.employments.contains(where: {
                if let from = parsedDay($0.from), let to = parsedDay($0.to) {
                    return to < from
                }
                return false
            }) {
                missing.append(language.text("Employment ends before it starts", "Anställning slutar före den börjar"))
            }
            if author.educationEntries.contains(where: {
                if let from = parsedDay($0.from), let to = parsedDay($0.to) {
                    return to < from
                }
                return false
            }) {
                missing.append(language.text("Education ends before it starts", "Utbildning slutar före den börjar"))
            }
            if !missing.isEmpty {
                issues.append(
                    MissingFieldIssue(
                        id: "author-\(author.id)",
                        entityKind: .researcher,
                        recordID: author.id,
                        destination: .people,
                        title: author.displayName,
                        subtitle: [author.title.nonEmpty, author.primaryAffiliation?.organization.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                        missingFields: missing
                    )
                )
            }
        }

        // The journal rows only depend on the journals and the language, so
        // they are kept until one of them changes (see
        // dataQualityJournalMissingFieldMemo).
        let journalsGeneration = publicationJournalsContentGeneration
        if let memo = dataQualityJournalMissingFieldMemo,
           memo.journalsGeneration == journalsGeneration,
           memo.language == language {
            issues.append(contentsOf: memo.issues)
            dataQualityJournalMissingFieldMemoReuseCount += 1
        } else {
            var journalIssues: [MissingFieldIssue] = []
            for journal in publicationJournals {
                var missing: [String] = []
                if journal.name.trimmedOrNil == nil {
                    missing.append(language.text("Name", "Namn"))
                }
                if journal.issn.trimmedOrNil == nil && journal.eissn.trimmedOrNil == nil {
                    missing.append(language.text("ISSN or eISSN", "ISSN eller eISSN"))
                }
                if journal.country.trimmedOrNil != nil && !isKnownCountry(journal.country) {
                    missing.append(language.text("Country is not a real country", "Land är inte ett riktigt land"))
                }
                if !looksLikeWebURL(journal.journalURL) {
                    missing.append(language.text("Journal URL is invalid", "Tidskriftslänk är ogiltig"))
                }
                if !looksLikeWebURL(journal.submissionPortalURL) {
                    missing.append(language.text("Submission portal URL is invalid", "Inskicksportalens länk är ogiltig"))
                }
                if journal.rankingRows.contains(where: { $0.yearlyMetrics.isEmpty }) {
                    missing.append(language.text("Ranking row has no year values", "Rankingrad saknar årsvärden"))
                }
                if journal.rankingRows.contains(where: { Dictionary(grouping: $0.yearlyMetrics, by: \.year).contains { $0.value.count > 1 } }) {
                    missing.append(language.text("Ranking row contains duplicate years", "Rankingrad innehåller dubbla år"))
                }
                if !missing.isEmpty {
                    journalIssues.append(
                        MissingFieldIssue(
                            id: "journal-\(journal.id)",
                            entityKind: .journal,
                            recordID: journal.id,
                            destination: .journals,
                            title: journal.name,
                            subtitle: [journal.publisher.nonEmpty, journal.issn.nonEmpty, journal.eissn.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                            missingFields: missing
                        )
                    )
                }
            }
            dataQualityJournalMissingFieldMemo = (
                journalsGeneration: journalsGeneration,
                language: language,
                issues: journalIssues
            )
            issues.append(contentsOf: journalIssues)
        }

        for publication in publicationRecords {
            var missing: [String] = []
            if publication.title.trimmedOrNil == nil {
                missing.append(language.text("Title", "Titel"))
            }
            if publication.statusLabel.trimmedOrNil == nil {
                missing.append(language.text("Status", "Status"))
            }
            if publication.journal.trimmedOrNil == nil {
                let status = PublicationStatus.fromStored(publication.statusLabel)
                if status == .submitted || status == .accepted || status == .published {
                    missing.append(language.text("Journal", "Tidskrift"))
                }
            }
            if PublicationStatus.fromStored(publication.statusLabel) == .submitted,
               publication.currentSubmissionDate?.trimmedOrNil == nil {
                missing.append(language.text("Submission date", "Inskicksdatum"))
            }
            if PublicationStatus.fromStored(publication.statusLabel) == .published,
               publication.year.trimmedOrNil == nil {
                missing.append(language.text("Year", "År"))
            }
            if publication.authorNames.isEmpty {
                missing.append(language.text("Authors", "Författare"))
            }
            if publication.projectName?.trimmedOrNil == nil {
                missing.append(language.text("Project", "Projekt"))
            }
            if let submissionDate = parsedDay(publication.currentSubmissionDate),
               let workflowDate = parsedDay(publication.workflowStatusDate),
               workflowDate < submissionDate {
                missing.append(language.text("Workflow date before submission date", "Workflow-datum före inskicksdatum"))
            }
            if PublicationStatus.fromStored(publication.statusLabel) == .accepted,
               publication.statusDate?.trimmedOrNil == nil {
                missing.append(language.text("Acceptance date", "Acceptdatum"))
            }
            if publication.statusDate?.trimmedOrNil != nil,
               latestPublicationTimelineEntry(for: publication)?.date?.trimmedOrNil != publication.statusDate?.trimmedOrNil {
                missing.append(language.text("Current status date differs from publication history", "Nuvarande statusdatum skiljer sig från publikationshistoriken"))
            }
            if !looksLikeDOI(publication.doi) {
                missing.append(language.text("DOI format is invalid", "DOI-formatet är ogiltigt"))
            }
            if publication.epubDate.trimmedOrNil != nil, parsedDay(publication.epubDate) == nil {
                missing.append(language.text("Epub date format is invalid", "Epub-datumformatet är ogiltigt"))
            }
            if !looksLikePMID(publication.pmid) {
                missing.append(language.text("PMID format is invalid", "PMID-formatet är ogiltigt"))
            }
            if publication.statusTimeline.count > 1 {
                for pair in zip(publication.statusTimeline, publication.statusTimeline.dropFirst()) {
                    let leftDate = parsedDay(pair.0.date)
                    let rightDate = parsedDay(pair.1.date)
                    if let leftDate, let rightDate, rightDate > leftDate {
                        missing.append(language.text("Publication history out of order", "Publikationshistorik i fel ordning"))
                        break
                    }
                }
            }
            if publication.previousAttempts.contains(where: {
                if let submitted = parsedDay($0.submittedOn), let rejected = parsedDay($0.rejectedOn) {
                    return rejected < submitted
                }
                return false
            }) {
                missing.append(language.text("Previous attempt response before submission", "Tidigare försök har svar före inskick"))
            }
            if let earliestCurrentSubmission = parsedDay(publication.currentSubmissionDate),
               publication.previousAttempts.contains(where: {
                   guard let rejected = parsedDay($0.rejectedOn) else { return false }
                   return rejected > earliestCurrentSubmission
               }) {
                missing.append(language.text("Previous attempt overlaps current submission", "Tidigare försök överlappar aktuell inskickning"))
            }
            if publication.publicationTasks.contains(where: {
                guard !centralTaskIDs.contains($0.id) else { return false }
                if let created = parsedDay($0.createdOn), let completed = parsedDay($0.completedOn) {
                    return completed < created
                }
                return false
            }) {
                missing.append(language.text("Task completed before it was created", "Uppgift slutförd före den skapades"))
            }
            if !missing.isEmpty {
                issues.append(
                    MissingFieldIssue(
                        id: "publication-\(publication.id)",
                        entityKind: .publication,
                        recordID: publication.id,
                        destination: .publications,
                        title: publication.title.nonEmpty ?? publication.number,
                        subtitle: [publication.journal.nonEmpty, publication.projectName.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                        missingFields: missing
                    )
                )
            }
        }

        for course in teachingCourses {
            var missing: [String] = []
            let displayName = course.localizedName(language: language).trimmedOrNil
            let displayProgram = course.localizedProgram(language: language).trimmedOrNil
            let hasVisibleTeachingLabel: Bool
            switch course.contextType {
            case .programTrack, .doctoralEducation, .clinicalTeaching:
                hasVisibleTeachingLabel = displayName != nil || displayProgram != nil
            default:
                hasVisibleTeachingLabel = displayName != nil
            }

            if !hasVisibleTeachingLabel {
                missing.append(language.text("Course name", "Kursnamn"))
            }
            if course.institution.trimmedOrNil == nil {
                missing.append(language.text("Organization", "Organisation"))
            }
            if course.credits.trimmedOrNil != nil && numericAmount(course.credits) == nil {
                missing.append(language.text("Credits are not numeric", "Hp är inte numeriskt"))
            }
            if course.teachingLanguage.trimmedOrNil != nil && course.teachingLanguage.count < 2 {
                missing.append(language.text("Teaching language is too short", "Undervisningsspråk är för kort"))
            }
            if let from = parsedDay(course.validFrom), let to = parsedDay(course.validTo), to < from {
                missing.append(language.text("Validity ends before it starts", "Giltighet slutar före den börjar"))
            }
            if course.courseCodes.contains(where: {
                if let from = parsedDay($0.validFrom), let to = parsedDay($0.validTo) {
                    return to < from
                }
                return false
            }) {
                missing.append(language.text("Course code validity ends before it starts", "Kurskodens giltighet slutar före den börjar"))
            }
            if !missing.isEmpty {
                issues.append(
                    MissingFieldIssue(
                        id: "teaching-course-\(course.id)",
                        entityKind: .teaching,
                        recordID: course.id,
                        destination: .teaching,
                        title: displayName ?? displayProgram ?? course.id,
                        subtitle: [course.institution.nonEmpty, course.courseCode.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                        missingFields: missing
                    )
                )
            }
        }

        for assignment in teachingAssignments {
            var missing: [String] = []
            if assignment.periods.contains(where: {
                if let from = parsedDay($0.from), let to = parsedDay($0.to) {
                    return to < from
                }
                return false
            }) {
                missing.append(language.text("Period ends before it starts", "Period slutar före den börjar"))
            }
            if assignment.contextID == nil,
               assignment.activityName.nonEmpty != nil,
               assignment.activityID != nil {
                missing.append(language.text("Missing teaching context", "Saknar undervisningskontext"))
            }
            if !assignment.roles.isEmpty && assignment.periods.isEmpty {
                missing.append(language.text("Teaching periods", "Undervisningsperioder"))
            }
            if !missing.isEmpty {
                let contextName = assignment.contextID.flatMap { contextID in
                    teachingCourses.first(where: { $0.id == contextID })?.name
                }
                issues.append(
                    MissingFieldIssue(
                        id: "teaching-\(assignment.id)",
                        entityKind: .teaching,
                        recordID: assignment.id,
                        destination: .teaching,
                        title: assignment.activityName.nonEmpty ?? assignment.comment.nonEmpty ?? assignment.id,
                        subtitle: [contextName, assignment.studentName.nonEmpty, assignment.programName.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                        missingFields: missing
                    )
                )
            }
        }

        for candidate in doctoralCandidates {
            var missing: [String] = []
            if candidate.candidateName.trimmedOrNil == nil {
                missing.append(language.text("Doctoral candidate name", "Doktorandnamn"))
            }
            if candidate.institution.trimmedOrNil == nil {
                missing.append(language.text("University", "Lärosäte"))
            }
            if candidate.supervisors.isEmpty {
                missing.append(language.text("Supervisor", "Handledare"))
            }
            if candidate.linkedPublicationIDs.isEmpty {
                missing.append(language.text("Linked publication", "Kopplad publikation"))
            }
            if let admission = parsedDay(candidate.admissionDate),
               let planning = parsedDay(candidate.planningSeminarDate),
               planning < admission {
                missing.append(language.text("Planning seminar before admission", "Planeringsseminarium före antagning"))
            }
            if let planning = parsedDay(candidate.planningSeminarDate),
               let halftime = parsedDay(candidate.halftimeDate),
               halftime < planning {
                missing.append(language.text("Halftime before planning seminar", "Halvtid före planeringsseminarium"))
            }
            if let admission = parsedDay(candidate.admissionDate),
               let halftime = parsedDay(candidate.halftimeDate),
               halftime < admission {
                missing.append(language.text("Halftime before admission", "Halvtid före antagning"))
            }
            if let halftime = parsedDay(candidate.halftimeDate),
               let disputation = parsedDay(candidate.plannedDisputationDate),
               disputation < halftime {
                missing.append(language.text("Disputation before halftime", "Disputation före halvtid"))
            }
            if candidate.supervisors.contains(where: {
                if let from = parsedDay($0.from), let to = parsedDay($0.to) {
                    return to < from
                }
                return false
            }) {
                missing.append(language.text("Supervisor period ends before it starts", "Handledarperiod slutar före den börjar"))
            }
            if candidate.supervisionPeriods.contains(where: {
                if let from = parsedDay($0.from), let to = parsedDay($0.to) {
                    return to < from
                }
                return false
            }) {
                missing.append(language.text("Supervision period ends before it starts", "Handledarinsats slutar före den börjar"))
            }
            if candidate.supervisionPeriods.contains(where: {
                if let hours = numericAmount($0.hoursPerSemester) {
                    return hours < 0
                }
                return false
            }) {
                missing.append(language.text("Supervision hours are negative", "Handledningstimmar är negativa"))
            }
            if !missing.isEmpty {
                issues.append(
                    MissingFieldIssue(
                        id: "doctoral-\(candidate.id)",
                        entityKind: .teaching,
                        recordID: candidate.id,
                        destination: .doctoralCandidates,
                        title: candidate.candidateName.nonEmpty ?? candidate.id,
                        subtitle: [candidate.institution.nonEmpty, candidate.doctoralProjectName.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                        missingFields: missing
                    )
                )
            }
        }

        for contribution in cvConferenceContributions {
            var missing: [String] = []
            if contribution.localizedTitle(language: language).trimmedOrNil == nil {
                missing.append(language.text("Title", "Titel"))
            }
            if contribution.status == .presented,
               contribution.from.trimmedOrNil == nil,
               contribution.to.trimmedOrNil == nil {
                missing.append(language.text("Congress date", "Kongressdatum"))
            }
            if contribution.submissionOutcome != nil && contribution.submissionDecisionOn.trimmedOrNil == nil {
                missing.append(language.text("Decision date", "Beslutsdatum"))
            }
            if contribution.submissionDecisionOn.trimmedOrNil != nil && contribution.submissionOutcome == nil {
                missing.append(language.text("Submission outcome", "Submissionutfall"))
            }
            // F19: the decision on a submitted abstract comes before the
            // congress. The contribution's own dates are used first, then
            // those of the linked congress.
            if let decision = parsedDay(contribution.submissionDecisionOn) {
                var congressEnd = parsedDay(contribution.to) ?? parsedDay(contribution.from)
                if congressEnd == nil,
                   let organizationID = contribution.congressOrganizationID?.trimmedOrNil,
                   let congressID = contribution.congressID?.trimmedOrNil,
                   let congress = organization(id: organizationID)?.congresses.first(where: { $0.id == congressID }) {
                    congressEnd = parsedDay(congress.to) ?? parsedDay(congress.from)
                }
                if let congressEnd, decision > congressEnd {
                    missing.append(language.text("Decision after the congress", "Beslut efter kongressen"))
                }
            }
            if !looksLikeDOI(contribution.journalDOI) {
                missing.append(language.text("DOI format is invalid", "DOI-formatet är ogiltigt"))
            }
            if !looksLikePMID(contribution.journalPMID) {
                missing.append(language.text("PMID format is invalid", "PMID-formatet är ogiltigt"))
            }
            if !missing.isEmpty {
                issues.append(
                    MissingFieldIssue(
                        id: "cv-conference-\(contribution.id)",
                        entityKind: .publication,
                        recordID: "conferenceContribution:\(contribution.id)",
                        destination: .cv,
                        title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                        subtitle: [contribution.localizedMeeting(language: language).nonEmpty, contribution.presentedBy.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                        missingFields: missing
                    )
                )
            }
        }

        for media in cvMediaAppearances {
            var missing: [String] = []
            if media.localizedTitle(language: language).trimmedOrNil == nil {
                missing.append(language.text("Title", "Titel"))
            }
            if media.date.trimmedOrNil == nil {
                missing.append(language.text("Completion date", "Genomförandedatum"))
            }
            if !looksLikeWebURL(media.link) {
                missing.append(language.text("Link is invalid", "Länken är ogiltig"))
            }
            if Self.dataQualityTimeEndsBeforeStart(start: media.startTime, end: media.endTime) {
                missing.append(language.text("End time before start time", "Sluttid före starttid"))
            }
            if !missing.isEmpty {
                issues.append(
                    MissingFieldIssue(
                        id: "cv-media-\(media.id)",
                        entityKind: .publication,
                        recordID: "mediaAppearance:\(media.id)",
                        destination: .cv,
                        title: media.localizedTitle(language: language).nonEmpty ?? media.displayTitle,
                        subtitle: media.localizedDescription(language: language),
                        missingFields: missing
                    )
                )
            }
        }

        for review in cvReviewEntries {
            var missing: [String] = []
            if review.date.trimmedOrNil == nil {
                missing.append(language.text("Date", "Datum"))
            }
            switch review.category {
            case .journalReview:
                if review.journalName.trimmedOrNil == nil {
                    missing.append(language.text("Journal", "Tidskrift"))
                }
            case .grantProposalReview, .doctoralExamination, .otherExpertAssignment:
                if review.organizationName.trimmedOrNil == nil {
                    missing.append(language.text("Organization", "Organisation"))
                }
            }
            if !missing.isEmpty {
                issues.append(
                    MissingFieldIssue(
                        id: "cv-review-\(review.id)",
                        entityKind: .publication,
                        recordID: "review:\(review.id)",
                        destination: .cv,
                        title: review.displayTitle,
                        subtitle: review.reference,
                        missingFields: missing
                    )
                )
            }
        }

        for other in cvOtherPublications {
            var missing: [String] = []
            if other.localizedCategory(language: language).trimmedOrNil == nil {
                missing.append(language.text("Category", "Kategori"))
            }
            if other.localizedTitle(language: language).trimmedOrNil == nil {
                missing.append(language.text("Title", "Titel"))
            }
            if other.localizedOutlet(language: language).trimmedOrNil == nil {
                missing.append(language.text("Outlet", "Utgivare / outlet"))
            }
            if other.authors.trimmedOrNil == nil {
                missing.append(language.text("Authors", "Författare"))
            }
            if !looksLikeDOI(other.doi) {
                missing.append(language.text("DOI format is invalid", "DOI-formatet är ogiltigt"))
            }
            if !missing.isEmpty {
                issues.append(
                    MissingFieldIssue(
                        id: "cv-other-\(other.id)",
                        entityKind: .publication,
                        recordID: "otherPublication:\(other.id)",
                        destination: .cv,
                        title: other.localizedTitle(language: language).nonEmpty ?? other.id,
                        subtitle: [other.localizedOutlet(language: language).nonEmpty, other.authors.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                        missingFields: missing
                    )
                )
            }
        }

        // F12: language gaps (one language missing, or English the same as
        // Swedish) are listed in their own section, "Missing translations",
        // with both languages side by side: see translationIssues().

        return issues
            .map(enrichedIssue)
            .sorted {
                if $0.entityKind.rawValue != $1.entityKind.rawValue {
                    return $0.entityKind.rawValue.localizedStandardCompare($1.entityKind.rawValue) == .orderedAscending
                }
                if $0.severity != $1.severity {
                    return $0.severity == .critical
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func dataQualityIntegrityIssues() -> [IntegrityIssue] {
        // A task edited in the central collection supersedes any legacy
        // copy left on records; legacy-only reads produced phantom
        // warnings for already-rescheduled tasks.
        let dataQualityCentralTaskIDs = Set(taskItems.map(\.id))
        var issues: [IntegrityIssue] = []

        func destinationKey(_ destination: AppRoute.Destination) -> String {
            switch destination {
            case .applications: return "applications"
            case .congresses: return "congresses"
            case .cv: return "cv"
            case .expertAssignments: return "expertAssignments"
            case .publications: return "publications"
            case .projects: return "projects"
            case .teaching: return "teaching"
            case .doctoralCandidates: return "doctoralCandidates"
            case .organizations: return "organizations"
            case .people: return "people"
            case .journals: return "journals"
            }
        }

        func appendIssue(
            kind: IntegrityIssue.Kind,
            destination: AppRoute.Destination,
            recordID: String,
            title: String,
            subtitle: String,
            details: String,
            calendarRevealDayString: String? = nil,
            calendarEventSource: CalendarWorkspaceEventSource? = nil
        ) {
            issues.append(
                IntegrityIssue(
                    id: "\(kind.rawValue)-\(destinationKey(destination))-\(recordID)-\(details)",
                    kind: kind,
                    destination: destination,
                    recordID: recordID,
                    title: title,
                    subtitle: subtitle,
                    details: details,
                    calendarRevealDayString: calendarRevealDayString,
                    calendarEventSource: calendarEventSource
                )
            )
        }

        func parsedDay(_ value: String?) -> Date? {
            guard let value = value?.trimmedOrNil else { return nil }
            return DateParsers.isoDay.date(from: value)
        }
        func looksLikeWebURL(_ value: String?) -> Bool {
            guard let trimmed = value?.trimmedOrNil else { return true }
            let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false else {
                return false
            }
            return true
        }
        func looksLikeEmail(_ value: String?) -> Bool {
            guard let trimmed = value?.trimmedOrNil else { return true }
            let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
            return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        func latestPublicationTimelineEntry(for publication: PublicationRecord) -> PublicationStatusEntry? {
            publicationEffectiveStatusEntry(from: publicationDerivedSubmissionRows(from: publication.statusTimeline))
        }
        func obviousOrganizationMatch(for rawName: String?) -> OrganizationRecord? {
            guard let rawName = rawName?.trimmedOrNil else { return nil }
            if let matched = organization(matchingName: rawName) {
                return matched
            }
            let normalized = rawName
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty else { return nil }
            let candidates = organizations.filter {
                let leftSv = $0.nameSv
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let leftEn = $0.nameEn
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return leftSv == normalized || leftEn == normalized
            }
            return candidates.count == 1 ? candidates.first : nil
        }
        func resolvedPublicationPDFURL(for publication: PublicationRecord) -> URL? {
            Self.resolvePublicationPDFURL(
                publicationID: publication.id,
                finalPDFPath: publication.finalPDFPath,
                finalPDFFilename: publication.finalPDFFilename
            )
        }
        func dateDetail(_ title: String, _ value: String?) -> String? {
            guard let value = value?.trimmedOrNil else { return nil }
            return "\(title): \(value)"
        }
        func timelineDetails(_ parts: [String?]) -> String {
            parts.compactMap { $0 }.joined(separator: " · ")
        }
        func appendApplicationTimelineIssue(
            _ application: GrantApplication,
            subtitle: String,
            details: String
        ) {
            appendIssue(
                kind: .semantic,
                destination: .applications,
                recordID: application.id,
                title: displayTitle(for: application, language: language),
                subtitle: subtitle,
                details: details
            )
        }

        let todayStart = Calendar.current.startOfDay(for: Date())
        let validProjectIDs = Set(projects.map(\.id))
        let validOrganizationIDs = Set(organizations.map(\.id))
        let validManagerIDs = Set(managers.map(\.id)).union(validOrganizationIDs)
        let validApplicationIDs = Set(applications.map(\.id))
        let validPublicationIDs = Set(publicationRecords.map(\.id))
        let validAuthorIDs = Set(publicationAuthors.map(\.id))
        let validTeachingAssignmentIDs = Set(teachingAssignments.map(\.id))
        let validDoctoralCandidateIDs = Set(doctoralCandidates.map(\.id))
        let congressEntries = organizations.flatMap { organization in
            persistedOrganizationCongresses(from: organization.congresses).map { congress in
                (organization: organization, congress: congress)
            }
        }
        let congressesByID = Dictionary(grouping: congressEntries) { $0.congress.id }
        for (congressID, entries) in congressesByID where congressID.trimmedOrNil != nil && entries.count > 1 {
            appendIssue(
                kind: .semantic,
                destination: .cv,
                recordID: "organizationCongress:\(entries[0].organization.id):\(congressID)",
                title: entries.first?.congress.title.nonEmpty ?? language.text("Congress", "Kongress"),
                subtitle: language.text("Duplicate congress ID", "Dubblett av kongress-ID"),
                details: entries.map { "\($0.organization.nameSv.nonEmpty ?? $0.organization.nameEn): \($0.congress.title.nonEmpty ?? $0.congress.id)" }.joined(separator: " · ")
            )
        }
        for meeting in calendarMeetingRecords {
            let title = meeting.title.nonEmpty ?? language.text("Calendar event", "Kalenderhändelse")
            let meetingProjectIDs = Set((meeting.projectIDs + [meeting.projectID].compactMap { $0 }).compactMap(\.trimmedOrNil))
            for projectID in meetingProjectIDs where !validProjectIDs.contains(projectID) {
                appendIssue(
                    kind: .staleReference,
                    destination: .projects,
                    recordID: projectID,
                    title: title,
                    subtitle: language.text("Calendar event links to missing project", "Kalenderhändelse länkar till saknat projekt"),
                    details: [meeting.date.nonEmpty, projectID.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                    calendarRevealDayString: meeting.date,
                    calendarEventSource: .meeting(meeting.id)
                )
            }

            let meetingOrganizationIDs = Set((meeting.organizationIDs + [meeting.organizationID].compactMap { $0 }).compactMap(\.trimmedOrNil))
            for organizationID in meetingOrganizationIDs where !validOrganizationIDs.contains(organizationID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .organizations,
                    recordID: organizationID,
                    title: title,
                    subtitle: language.text("Calendar event links to missing organization", "Kalenderhändelse länkar till saknad organisation"),
                    details: [meeting.date.nonEmpty, organizationID.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                    calendarRevealDayString: meeting.date,
                    calendarEventSource: .meeting(meeting.id)
                )
            }

            for applicationID in Set(meeting.applicationIDs.compactMap(\.trimmedOrNil)) where !validApplicationIDs.contains(applicationID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .applications,
                    recordID: applicationID,
                    title: title,
                    subtitle: language.text("Calendar event links to missing grant", "Kalenderhändelse länkar till saknat anslag"),
                    details: [meeting.date.nonEmpty, applicationID.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                    calendarRevealDayString: meeting.date,
                    calendarEventSource: .meeting(meeting.id)
                )
            }

            for publicationID in Set(meeting.publicationIDs.compactMap(\.trimmedOrNil)) where !validPublicationIDs.contains(publicationID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .publications,
                    recordID: publicationID,
                    title: title,
                    subtitle: language.text("Calendar event links to missing publication", "Kalenderhändelse länkar till saknad publikation"),
                    details: [meeting.date.nonEmpty, publicationID.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                    calendarRevealDayString: meeting.date,
                    calendarEventSource: .meeting(meeting.id)
                )
            }
            if let researcherID = meeting.researcherID?.trimmedOrNil,
               !validAuthorIDs.contains(researcherID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .people,
                    recordID: researcherID,
                    title: title,
                    subtitle: language.text("Calendar event links to missing researcher", "Kalenderhändelse länkar till saknad forskare"),
                    details: [meeting.date.nonEmpty, researcherID.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                    calendarRevealDayString: meeting.date,
                    calendarEventSource: .meeting(meeting.id)
                )
            }
            for teachingAssignmentID in Set(calendarMeetingTeachingAssignmentIDs(meeting))
                where !validTeachingAssignmentIDs.contains(teachingAssignmentID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .teaching,
                    recordID: teachingAssignmentID,
                    title: title,
                    subtitle: language.text("Calendar event links to missing teaching assignment", "Kalenderhändelse länkar till saknat undervisningsuppdrag"),
                    details: [meeting.date.nonEmpty, teachingAssignmentID.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                    calendarRevealDayString: meeting.date,
                    calendarEventSource: .meeting(meeting.id)
                )
            }
            for doctoralCandidateID in Set(calendarMeetingDoctoralCandidateIDs(meeting))
                where !validDoctoralCandidateIDs.contains(doctoralCandidateID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .doctoralCandidates,
                    recordID: doctoralCandidateID,
                    title: title,
                    subtitle: language.text("Calendar event links to missing doctoral candidate", "Kalenderhändelse länkar till saknad doktorand"),
                    details: [meeting.date.nonEmpty, doctoralCandidateID.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                    calendarRevealDayString: meeting.date,
                    calendarEventSource: .meeting(meeting.id)
                )
            }
        }

        for travel in calendarTravelRecords {
            guard let organizationID = travel.congressOrganizationID.trimmedOrNil,
                  let congressID = travel.congressID.trimmedOrNil else { continue }
            let title = [
                travel.mode.localizedName(language: language),
                travel.date.nonEmpty,
                travel.fromCity.nonEmpty,
                travel.toCity.nonEmpty
            ].compactMap { $0 }.joined(separator: " · ")
            if let organization = organization(id: organizationID) {
                if organization.congresses.contains(where: { $0.id == congressID }) == false {
                    appendIssue(
                        kind: .brokenLink,
                        destination: .cv,
                        recordID: "organizationCongress:\(organizationID):\(congressID)",
                        title: title.nonEmpty ?? language.text("Travel", "Resa"),
                        subtitle: language.text("Travel links to missing congress", "Resa länkar till saknad kongress"),
                        details: congressID
                    )
                }
            } else {
                appendIssue(
                    kind: .brokenLink,
                    destination: .organizations,
                    recordID: organizationID,
                    title: title.nonEmpty ?? language.text("Travel", "Resa"),
                    subtitle: language.text("Travel links to missing congress organization", "Resa länkar till saknad kongressorganisation"),
                    details: organizationID
                )
            }
        }

        for accommodation in calendarAccommodationRecords {
            guard let organizationID = accommodation.congressOrganizationID.trimmedOrNil,
                  let congressID = accommodation.congressID.trimmedOrNil else { continue }
            let title = [
                accommodation.hotelName.nonEmpty,
                accommodation.checkInDate.nonEmpty,
                accommodation.city.nonEmpty
            ].compactMap { $0 }.joined(separator: " · ")
            if let organization = organization(id: organizationID) {
                if organization.congresses.contains(where: { $0.id == congressID }) == false {
                    appendIssue(
                        kind: .brokenLink,
                        destination: .cv,
                        recordID: "organizationCongress:\(organizationID):\(congressID)",
                        title: title.nonEmpty ?? language.text("Accommodation", "Boende"),
                        subtitle: language.text("Accommodation links to missing congress", "Boende länkar till saknad kongress"),
                        details: congressID
                    )
                }
            } else {
                appendIssue(
                    kind: .brokenLink,
                    destination: .organizations,
                    recordID: organizationID,
                    title: title.nonEmpty ?? language.text("Accommodation", "Boende"),
                    subtitle: language.text("Accommodation links to missing congress organization", "Boende länkar till saknad kongressorganisation"),
                    details: organizationID
                )
            }
        }

        for application in applications {
            if let organizationID = application.organizationID?.trimmedOrNil,
               !validOrganizationIDs.contains(organizationID) {
                appendIssue(
                    kind: .staleReference,
                    destination: .applications,
                    recordID: application.id,
                    title: displayTitle(for: application, language: language),
                    subtitle: language.text("Funder ID links to missing organization", "Anslagsgivar-ID länkar till saknad organisation"),
                    details: organizationID
                )
            }
            if let projectID = application.projectID?.trimmedOrNil,
               !validProjectIDs.contains(projectID) {
                appendIssue(
                    kind: .staleReference,
                    destination: .applications,
                    recordID: application.id,
                    title: displayTitle(for: application, language: language),
                    subtitle: language.text("Project ID links to missing project", "Projekt-ID länkar till saknat projekt"),
                    details: projectID
                )
            }
            if let managerID = application.applicationManagerID?.trimmedOrNil,
               !validManagerIDs.contains(managerID) {
                appendIssue(
                    kind: .staleReference,
                    destination: .applications,
                    recordID: application.id,
                    title: displayTitle(for: application, language: language),
                    subtitle: language.text("Fund manager ID links to missing manager", "Medelsförvaltar-ID länkar till saknad medelsförvaltare"),
                    details: managerID
                )
            }
            if let organizationName = application.organization.trimmedOrNil,
               linkedFunder(of: application) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .applications,
                    recordID: application.id,
                    title: displayTitle(for: application, language: language),
                    subtitle: language.text("Missing linked funder", "Saknar länkad anslagsgivare"),
                    details: organizationName
                )
            }
            if let projectName = application.projectType?.trimmedOrNil,
               linkedProject(of: application) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .applications,
                    recordID: application.id,
                    title: displayTitle(for: application, language: language),
                    subtitle: language.text("Missing linked project", "Saknar länkat projekt"),
                    details: projectName
                )
            }
            if let managerName = application.applicationManager?.trimmedOrNil,
               linkedFundManager(of: application) == nil,
               !dataQualityHasManager(named: managerName) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .applications,
                    recordID: application.id,
                    title: displayTitle(for: application, language: language),
                    subtitle: language.text("Missing linked manager", "Saknar länkad medelsförvaltare"),
                    details: managerName
                )
            }
            let trimmedStatus = application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let outcomeDates = [
                application.grantedOn?.trimmedOrNil,
                application.deniedOn?.trimmedOrNil,
                application.withdrawnOn?.trimmedOrNil
            ]
            .compactMap { $0 }
            if outcomeDates.count > 1 {
                appendIssue(
                    kind: .semantic,
                    destination: .applications,
                    recordID: application.id,
                    title: displayTitle(for: application, language: language),
                    subtitle: language.text("Conflicting application outcomes", "Motstridiga ansökningsutfall"),
                    details: outcomeDates.joined(separator: ", ")
                )
            }
            if application.isGranted, trimmedStatus != "Beviljat" {
                appendIssue(
                    kind: .semantic,
                    destination: .applications,
                    recordID: application.id,
                    title: displayTitle(for: application, language: language),
                    subtitle: language.text("Application result does not match granted state", "Ansökningsutfall stämmer inte med beviljat läge"),
                    details: trimmedStatus
                )
            }
            let unresolvedStatus = application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if let decisionExpected = application.decisionExpectedDate,
               decisionExpected < todayStart,
               (unresolvedStatus.isEmpty || unresolvedStatus == "Väntar svar") {
                appendIssue(
                    kind: .semantic,
                    destination: .applications,
                    recordID: application.id,
                    title: displayTitle(for: application, language: language),
                    subtitle: language.text("Expected decision date passed without registered outcome", "Förväntat beslutsdatum passerat utan registrerat utfall"),
                    details: application.decisionExpectedOn ?? ""
                )
            }

            if let grantedDate = parsedDay(application.grantedOn),
               let firstDispositionDate = application.firstDispositionDate,
               firstDispositionDate < grantedDate {
                appendApplicationTimelineIssue(
                    application,
                    subtitle: language.text("First disposition before granted date", "Första disponering före beviljandedatum"),
                    details: timelineDetails([
                        dateDetail(language.text("Granted", "Beviljandedatum"), application.grantedOn),
                        dateDetail(language.text("First disposition", "Första disponering"), application.firstDispositionOn)
                    ])
                )
            }

            if let grantedDate = parsedDay(application.grantedOn),
               let lastDispositionDate = application.lastDispositionDate,
               lastDispositionDate < grantedDate {
                appendApplicationTimelineIssue(
                    application,
                    subtitle: language.text("Last disposition before granted date", "Sista disponering före beviljandedatum"),
                    details: timelineDetails([
                        dateDetail(language.text("Granted", "Beviljandedatum"), application.grantedOn),
                        dateDetail(language.text("Last disposition", "Sista disponering"), application.lastDispositionOn)
                    ])
                )
            }

            if let firstDispositionDate = application.firstDispositionDate,
               let lastDispositionDate = application.lastDispositionDate,
               lastDispositionDate < firstDispositionDate {
                appendApplicationTimelineIssue(
                    application,
                    subtitle: language.text("Last disposition before first disposition", "Sista disponering före första disponering"),
                    details: timelineDetails([
                        dateDetail(language.text("First disposition", "Första disponering"), application.firstDispositionOn),
                        dateDetail(language.text("Last disposition", "Sista disponering"), application.lastDispositionOn)
                    ])
                )
            }

            if application.decisionDate == nil,
               let decisionExpectedDate = application.decisionExpectedDate,
               let firstDispositionDate = application.firstDispositionDate,
               firstDispositionDate < decisionExpectedDate {
                appendApplicationTimelineIssue(
                    application,
                    subtitle: language.text("First disposition before expected decision", "Första disponering före förväntat beslut"),
                    details: timelineDetails([
                        dateDetail(language.text("Decision expected", "Beslut väntas"), application.decisionExpectedOn),
                        dateDetail(language.text("First disposition", "Första disponering"), application.firstDispositionOn)
                    ])
                )
            }

        }

        for publication in publicationRecords {
            if let projectID = publication.projectID?.trimmedOrNil,
               !validProjectIDs.contains(projectID) {
                appendIssue(
                    kind: .staleReference,
                    destination: .publications,
                    recordID: publication.id,
                    title: publication.title.nonEmpty ?? publication.number,
                    subtitle: language.text("Project ID links to missing project", "Projekt-ID länkar till saknat projekt"),
                    details: projectID
                )
            }
            if let projectName = publication.projectName?.trimmedOrNil,
               linkedProject(of: publication) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .publications,
                    recordID: publication.id,
                    title: publication.title.nonEmpty ?? publication.number,
                    subtitle: language.text("Missing linked project", "Saknar länkat projekt"),
                    details: projectName
                )
            }
            if let journalName = publication.journal.trimmedOrNil,
               linkedJournal(of: publication) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .publications,
                    recordID: publication.id,
                    title: publication.title.nonEmpty ?? publication.number,
                    subtitle: language.text("Missing linked journal", "Saknar länkad tidskrift"),
                    details: journalName
                )
            }
            let missingAuthors = publication.authorNames.compactMap(\.trimmedOrNil).filter { publicationAuthor(named: $0) == nil }
            if !missingAuthors.isEmpty {
                appendIssue(
                    kind: .brokenLink,
                    destination: .publications,
                    recordID: publication.id,
                    title: publication.title.nonEmpty ?? publication.number,
                    subtitle: language.text("Missing linked researchers", "Saknar länkade forskare"),
                    details: missingAuthors.joined(separator: ", ")
                )
            }
            if publication.finalPDFPath?.trimmedOrNil != nil || publication.finalPDFFilename?.trimmedOrNil != nil,
               resolvedPublicationPDFURL(for: publication) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .publications,
                    recordID: publication.id,
                    title: publication.title.nonEmpty ?? publication.number,
                    subtitle: language.text("Missing linked PDF file", "Saknar länkad PDF-fil"),
                    details: publication.finalPDFFilename ?? publication.finalPDFPath ?? ""
                )
            }
            if let latestTimeline = latestPublicationTimelineEntry(for: publication),
               PublicationStatus.normalizedRawValue(latestTimeline.status) != publication.statusLabel {
                appendIssue(
                    kind: .semantic,
                    destination: .publications,
                    recordID: publication.id,
                    title: publication.title.nonEmpty ?? publication.number,
                    subtitle: language.text("Current status differs from publication history", "Nuvarande status skiljer sig från publikationshistoriken"),
                    details: "\(publication.statusLabel) / \(latestTimeline.status)"
                )
            }
            if PublicationStatus.fromStored(publication.statusLabel) == .published,
               publication.statusDate?.trimmedOrNil == nil {
                appendIssue(
                    kind: .semantic,
                    destination: .publications,
                    recordID: publication.id,
                    title: publication.title.nonEmpty ?? publication.number,
                    subtitle: language.text("Published publication lacks publication date", "Publicerad publikation saknar publiceringsdatum"),
                    details: publication.journal
                )
            }
            if let overdueTask = publication.publicationTasks.first(where: {
                !dataQualityCentralTaskIDs.contains($0.id)
                    && !$0.isCompleted && (parsedDay($0.deadline).map { $0 < todayStart } ?? false)
            }) {
                // Legacy publication tasks are shown in the calendar, not in
                // the publication editor — reveal the task there instead of
                // opening a record that shows nothing.
                appendIssue(
                    kind: .semantic,
                    destination: .publications,
                    recordID: publication.id,
                    title: publication.title.nonEmpty ?? publication.number,
                    subtitle: language.text("Overdue publication task", "Försenad publikationsuppgift"),
                    details: overdueTask.comment,
                    calendarRevealDayString: overdueTask.deadline,
                    calendarEventSource: .publicationTask(publicationID: publication.id, taskID: overdueTask.id)
                )
            }

            let statusTimeline = publication.statusTimeline.sorted {
                (parsedDay($0.date) ?? .distantPast) < (parsedDay($1.date) ?? .distantPast)
            }
            for pair in zip(statusTimeline, statusTimeline.dropFirst()) {
                if let leftDate = parsedDay(pair.0.date),
                   let rightDate = parsedDay(pair.1.date),
                   rightDate < leftDate {
                    appendIssue(
                        kind: .semantic,
                        destination: .publications,
                        recordID: publication.id,
                        title: publication.title.nonEmpty ?? publication.number,
                        subtitle: language.text("Publication history out of order", "Publikationshistorik i fel ordning"),
                        details: "\(pair.0.status) / \(pair.1.status)"
                    )
                    break
                }
            }
            for attempt in publication.previousAttempts {
                if let submitted = parsedDay(attempt.submittedOn),
                   let rejected = parsedDay(attempt.rejectedOn),
                   rejected < submitted {
                    appendIssue(
                        kind: .semantic,
                        destination: .publications,
                        recordID: publication.id,
                        title: publication.title.nonEmpty ?? publication.number,
                        subtitle: language.text("Previous attempt response precedes submission", "Tidigare försök har svar före inskick"),
                        details: attempt.journal
                    )
                    break
                }
            }
        }

        for candidate in doctoralCandidates {
            let title = candidate.candidateName.nonEmpty ?? candidate.doctoralProjectName.nonEmpty ?? candidate.id
            if let authorID = candidate.candidateAuthorID?.trimmedOrNil,
               !validAuthorIDs.contains(authorID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .doctoralCandidates,
                    recordID: candidate.id,
                    title: title,
                    subtitle: language.text("Doctoral candidate ID links to missing researcher", "Doktorand-ID länkar till saknad forskare"),
                    details: authorID
                )
            }
            if let institutionID = candidate.institutionID?.trimmedOrNil,
               !validOrganizationIDs.contains(institutionID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .doctoralCandidates,
                    recordID: candidate.id,
                    title: title,
                    subtitle: language.text("Institution ID links to missing organization", "Institutions-ID länkar till saknad organisation"),
                    details: institutionID
                )
            }
            if let projectID = candidate.linkedProjectID?.trimmedOrNil,
               !validProjectIDs.contains(projectID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .doctoralCandidates,
                    recordID: candidate.id,
                    title: title,
                    subtitle: language.text("Doctoral project ID links to missing project", "Doktorandprojekt-ID länkar till saknat projekt"),
                    details: projectID
                )
            }
            for publicationID in Set(candidate.linkedPublicationIDs.compactMap(\.trimmedOrNil)) where !validPublicationIDs.contains(publicationID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .doctoralCandidates,
                    recordID: candidate.id,
                    title: title,
                    subtitle: language.text("Linked publication ID is missing", "Kopplad publikations-ID saknas"),
                    details: publicationID
                )
            }
            for supervisor in candidate.supervisors {
                guard let authorID = supervisor.authorID?.trimmedOrNil,
                      !validAuthorIDs.contains(authorID) else { continue }
                appendIssue(
                    kind: .brokenLink,
                    destination: .doctoralCandidates,
                    recordID: candidate.id,
                    title: title,
                    subtitle: language.text("Supervisor ID links to missing researcher", "Handledar-ID länkar till saknad forskare"),
                    details: authorID
                )
            }
        }

        for contribution in cvConferenceContributions {
            if let presentedBy = contribution.presentedBy.trimmedOrNil,
               publicationAuthor(matchingPresentedName: presentedBy) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Missing linked presenter", "Saknar länkad presentatör"),
                    details: presentedBy
                )
            }
            // The record to fix is always the CONTRIBUTION (its stored
            // name/ID no longer resolves); routing to .people with a
            // non-researcher ID landed on an unrelated researcher.
            if let presentedByAuthorID = contribution.presentedByAuthorID?.trimmedOrNil,
               !validAuthorIDs.contains(presentedByAuthorID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Presenter ID links to missing researcher", "Presentatörs-id länkar till saknad forskare"),
                    details: presentedByAuthorID
                )
            }
            for contributorAuthorID in contribution.contributorAuthorIDs.compactMap(\.trimmedOrNil) where !validAuthorIDs.contains(contributorAuthorID) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Contributor ID links to missing researcher", "Bidragsförfattar-id länkar till saknad forskare"),
                    details: contributorAuthorID
                )
            }
            let missingContributors = contribution.contributorNames.compactMap(\.trimmedOrNil).filter {
                publicationAuthor(matchingPresentedName: $0) == nil
            }
            if !missingContributors.isEmpty {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Missing linked contributors", "Saknar länkade bidragsförfattare"),
                    details: missingContributors.joined(separator: ", ")
                )
            }
            if let journalName = contribution.journalName.trimmedOrNil,
               linkedJournal(of: contribution) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Missing linked journal", "Saknar länkad tidskrift"),
                    details: journalName
                )
            }
            if let projectName = contribution.projectNameSv.trimmedOrNil,
               linkedProject(of: contribution) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Missing linked project", "Saknar länkat projekt"),
                    details: projectName
                )
            }
            if let congressOrganizationID = contribution.congressOrganizationID?.trimmedOrNil,
               organization(id: congressOrganizationID) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Missing linked congress organization", "Saknar länkad kongressorganisation"),
                    details: congressOrganizationID
                )
            }
            if let congressOrganizationID = contribution.congressOrganizationID?.trimmedOrNil,
               let congressID = contribution.congressID?.trimmedOrNil,
               let organization = organization(id: congressOrganizationID),
               organization.congresses.contains(where: { $0.id == congressID }) == false {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Missing linked congress", "Saknar länkad kongress"),
                    details: congressID
                )
            }
            if let fromDate = parsedDay(contribution.from),
               let toDate = parsedDay(contribution.to),
               toDate < fromDate {
                appendIssue(
                    kind: .semantic,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Congress end date before start date", "Kongressens slutdatum före startdatum"),
                    details: contribution.localizedMeeting(language: language)
                )
            }
            if let appliedDate = parsedDay(contribution.submissionAppliedOn),
               let closesDate = parsedDay(contribution.submissionClosesOn),
               closesDate < appliedDate {
                appendIssue(
                    kind: .semantic,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Submission deadline before submission date", "Deadline för inskick före inskicksdatum"),
                    details: contribution.localizedMeeting(language: language)
                )
            }
            if let appliedDate = parsedDay(contribution.submissionAppliedOn),
               let expectedDate = parsedDay(contribution.submissionDecisionExpectedOn),
               expectedDate < appliedDate {
                appendIssue(
                    kind: .semantic,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Expected decision date before submission date", "Förväntat beslutsdatum före inskicksdatum"),
                    details: contribution.localizedMeeting(language: language)
                )
            }
            if let appliedDate = parsedDay(contribution.submissionAppliedOn),
               let decisionDate = parsedDay(contribution.submissionDecisionOn),
               decisionDate < appliedDate {
                appendIssue(
                    kind: .semantic,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Decision date before submission date", "Beslutsdatum före inskicksdatum"),
                    details: contribution.localizedMeeting(language: language)
                )
            }
            if contribution.submissionOutcome != nil && contribution.submissionDecisionOn.trimmedOrNil == nil {
                appendIssue(
                    kind: .semantic,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Submission outcome without decision date", "Submissionutfall utan beslutsdatum"),
                    details: contribution.localizedMeeting(language: language)
                )
            }
            if contribution.submissionDecisionOn.trimmedOrNil != nil && contribution.submissionOutcome == nil {
                appendIssue(
                    kind: .semantic,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Decision date without submission outcome", "Beslutsdatum utan submissionutfall"),
                    details: contribution.localizedMeeting(language: language)
                )
            }
            if contribution.status == .presented &&
               contribution.from.trimmedOrNil == nil &&
               contribution.to.trimmedOrNil == nil {
                appendIssue(
                    kind: .semantic,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: language.text("Presented contribution without congress date", "Presenterat bidrag utan kongressdatum"),
                    details: contribution.localizedMeeting(language: language)
                )
            }
        }

        for media in cvMediaAppearances {
            if !looksLikeWebURL(media.link) {
                appendIssue(
                    kind: .semantic,
                    destination: .cv,
                    recordID: "mediaAppearance:\(media.id)",
                    title: media.localizedTitle(language: language).nonEmpty ?? media.displayTitle,
                    subtitle: language.text("Invalid media link", "Ogiltig medielänk"),
                    details: media.link
                )
            }
            if media.pdfFilename?.trimmedOrNil != nil || media.pdfPath?.trimmedOrNil != nil,
               GrantDataStore.resolveCVMediaAppearancePDFURL(
                   mediaAppearanceID: media.id,
                   pdfPath: media.pdfPath,
                   pdfFilename: media.pdfFilename,
                   legacyStoredFilenames: media.attachments.map(\.storedFilename)
               ) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "mediaAppearance:\(media.id)",
                    title: media.localizedTitle(language: language).nonEmpty ?? media.displayTitle,
                    subtitle: language.text("Missing linked PDF file", "Saknar länkad PDF-fil"),
                    details: media.pdfFilename ?? media.pdfPath ?? ""
                )
            }
        }

        for review in cvReviewEntries {
            if let journalName = review.journalName.trimmedOrNil,
               linkedJournal(of: review) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "review:\(review.id)",
                    title: review.displayTitle,
                    subtitle: language.text("Missing linked journal", "Saknar länkad tidskrift"),
                    details: journalName
                )
            }
            if review.certificatePDFData == nil,
               review.certificateFilename?.trimmedOrNil != nil || review.certificatePath?.trimmedOrNil != nil,
               GrantDataStore.resolveCVReviewCertificatePDFURL(
                   reviewEntryID: review.id,
                   certificatePath: review.certificatePath,
                   certificateFilename: review.certificateFilename
               ) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "review:\(review.id)",
                    title: review.displayTitle,
                    subtitle: language.text("Missing review certificate file", "Saknar reviewintygsfil"),
                    details: review.certificatePath ?? review.certificateFilename ?? ""
                )
            }
        }

        for other in cvOtherPublications {
            if !looksLikeWebURL(other.doi.isEmpty ? nil : "https://doi.org/\(other.doi)") && other.doi.trimmedOrNil != nil {
                appendIssue(
                    kind: .semantic,
                    destination: .cv,
                    recordID: "otherPublication:\(other.id)",
                    title: other.localizedTitle(language: language).nonEmpty ?? other.id,
                    subtitle: language.text("Invalid DOI", "Ogiltig DOI"),
                    details: other.doi
                )
            }
        }

        for organization in organizations {
            if let overdueTask = organization.projectTasks.first(where: {
                !dataQualityCentralTaskIDs.contains($0.id)
                    && !$0.isCompleted && (parsedDay($0.deadline).map { $0 < todayStart } ?? false)
            }) {
                // Legacy organization tasks are shown in the calendar, not in
                // the organization editor — reveal the task there instead of
                // opening a record that shows nothing.
                appendIssue(
                    kind: .semantic,
                    destination: .organizations,
                    recordID: organization.id,
                    title: dataQualityLocalizedOptionDisplayName(organization),
                    subtitle: language.text("Overdue organization task", "Försenad organisationsuppgift"),
                    details: overdueTask.comment,
                    calendarRevealDayString: overdueTask.deadline,
                    calendarEventSource: .organizationTask(organizationID: organization.id, taskID: overdueTask.id)
                )
            }
            for congress in organization.congresses {
                let fields: [(String, Bool, String)] = [
                    (language.text("Congress start", "Kongressstart"), congress.fromUncertain, congress.from),
                    (language.text("Congress end", "Kongressslut"), congress.toUncertain, congress.to),
                    (language.text("Abstract deadline", "Abstractdeadline"), congress.abstractSubmissionDeadlineUncertain, congress.abstractSubmissionDeadline),
                    (language.text("Late abstract deadline", "Sen abstractdeadline"), congress.lateAbstractSubmissionDeadlineUncertain, congress.lateAbstractSubmissionDeadline)
                ]

                for (label, isUncertain, value) in fields {
                    guard isUncertain, let parsed = parsedDay(value), parsed < todayStart else { continue }
                    appendIssue(
                        kind: .semantic,
                        destination: .organizations,
                        recordID: organization.id,
                        title: dataQualityLocalizedOptionDisplayName(organization),
                        subtitle: language.text("Uncertain congress date lies in the past", "Osäkert kongressdatum ligger i det förgångna"),
                        details: [congress.title.nonEmpty, label, value.trimmedOrNil].compactMap { $0 }.joined(separator: " · ")
                    )
                }
                if congress.country.trimmedOrNil != nil,
                   GrantParsing.countryOptions.contains(congress.country) == false {
                    appendIssue(
                        kind: .semantic,
                        destination: .organizations,
                        recordID: organization.id,
                        title: dataQualityLocalizedOptionDisplayName(organization),
                        subtitle: language.text("Congress country is not a real country", "Kongressland är inte ett riktigt land"),
                        details: [congress.title.nonEmpty, congress.country.nonEmpty].compactMap { $0 }.joined(separator: " · ")
                    )
                }
                for applicationID in congress.fundingApplicationIDs.compactMap(\.trimmedOrNil) where !validApplicationIDs.contains(applicationID) {
                    appendIssue(
                        kind: .brokenLink,
                        destination: .cv,
                        recordID: "organizationCongress:\(organization.id):\(congress.id)",
                        title: congress.title.nonEmpty ?? dataQualityLocalizedOptionDisplayName(organization),
                        subtitle: language.text("Congress funding links to missing grant", "Kongressfinansiering länkar till saknat anslag"),
                        details: applicationID
                    )
                }
                for participantAuthorID in congress.participantAuthorIDs.compactMap(\.trimmedOrNil) where !validAuthorIDs.contains(participantAuthorID) {
                    appendIssue(
                        kind: .brokenLink,
                        destination: .cv,
                        recordID: "organizationCongress:\(organization.id):\(congress.id)",
                        title: congress.title.nonEmpty ?? dataQualityLocalizedOptionDisplayName(organization),
                        subtitle: language.text("Congress participant ID links to missing researcher", "Kongressdeltagar-id länkar till saknad forskare"),
                        details: participantAuthorID
                    )
                }
                let unresolvedParticipantNames = congress.participantNames.compactMap(\.trimmedOrNil).filter {
                    publicationAuthor(matchingPresentedName: $0) == nil
                }
                if !unresolvedParticipantNames.isEmpty {
                    appendIssue(
                        kind: .brokenLink,
                        destination: .cv,
                        recordID: "organizationCongress:\(organization.id):\(congress.id)",
                        title: congress.title.nonEmpty ?? dataQualityLocalizedOptionDisplayName(organization),
                        subtitle: language.text("Missing linked congress participants", "Saknar länkade kongressdeltagare"),
                        details: unresolvedParticipantNames.joined(separator: ", ")
                    )
                }
            }
        }

        for project in projects {
            let overdueTask = project.projectTasks.first(where: {
                !dataQualityCentralTaskIDs.contains($0.id)
                    && !$0.isCompleted
                    && (parsedDay($0.deadline).map { $0 < todayStart } ?? false)
            })
            if let overdueTask {
                // Project tasks are shown in the calendar (on their
                // deadline day), not in the project detail view — reveal
                // the task there instead of opening an empty-looking record.
                appendIssue(
                    kind: .semantic,
                    destination: .projects,
                    recordID: project.id,
                    title: dataQualityLocalizedOptionDisplayName(project),
                    subtitle: language.text("Overdue project task", "Försenad projektuppgift"),
                    details: overdueTask.comment,
                    calendarRevealDayString: overdueTask.deadline,
                    calendarEventSource: .projectTask(projectID: project.id, taskID: overdueTask.id)
                )
            }
        }

        // Central tasks are the source of truth and get their own overdue
        // findings; the calendar tags their rows as .teachingTask.
        for task in taskItems {
            guard task.completedOn?.trimmedOrNil == nil,
                  let deadlineDay = parsedDay(task.deadline),
                  deadlineDay < todayStart,
                  let taskTitle = task.comment.trimmedOrNil else { continue }
            let linkedProject = task.links
                .first(where: { $0.kind == .project })
                .flatMap { link in projects.first(where: { $0.id == link.targetID }) }
            appendIssue(
                kind: .semantic,
                destination: .projects,
                recordID: linkedProject?.id ?? task.id,
                title: linkedProject.map(dataQualityLocalizedOptionDisplayName) ?? taskTitle,
                subtitle: language.text("Overdue task", "Försenad uppgift"),
                details: taskTitle,
                calendarRevealDayString: task.deadline,
                calendarEventSource: .teachingTask(taskID: task.id)
            )
        }
        for task in taskItems {
            guard let created = parsedDay(task.createdOn),
                  let completed = task.completedOn.flatMap(parsedDay),
                  completed < created,
                  let taskTitle = task.comment.trimmedOrNil else { continue }
            appendIssue(
                kind: .semantic,
                destination: .projects,
                recordID: task.id,
                title: taskTitle,
                subtitle: language.text("Task completed before it was created", "Uppgift slutförd före den skapades"),
                details: "\(task.completedOn ?? "") / \(task.createdOn)",
                calendarRevealDayString: task.deadline.trimmedOrNil,
                calendarEventSource: .teachingTask(taskID: task.id)
            )
        }

        for author in publicationAuthors {
            if author.affiliations.filter(\.isPrimary).count > 1 {
                appendIssue(
                    kind: .semantic,
                    destination: .people,
                    recordID: author.id,
                    title: author.displayName,
                    subtitle: language.text("Multiple primary affiliations", "Flera primära affilieringar"),
                    details: author.affiliations.filter(\.isPrimary).map(\.organization).joined(separator: ", ")
                )
            }
            if author.affiliations.contains(where: { !looksLikeEmail($0.email) }) {
                appendIssue(
                    kind: .semantic,
                    destination: .people,
                    recordID: author.id,
                    title: author.displayName,
                    subtitle: language.text("Invalid affiliation email", "Ogiltig affilierings-e-post"),
                    details: author.affiliations.first(where: { !looksLikeEmail($0.email) })?.email ?? ""
                )
            }
            if let affiliation = author.affiliations.first(where: { $0.organization.trimmedOrNil != nil && linkedOrganization(id: $0.organizationID, name: $0.organization) == nil }),
               let matchedOrganization = obviousOrganizationMatch(for: affiliation.organization) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .people,
                    recordID: author.id,
                    title: author.displayName,
                    subtitle: language.text("Affiliation could be linked to an existing organization", "Affiliering kan kopplas till en befintlig organisation"),
                    details: "\(affiliation.organization) → \(dataQualityLocalizedOptionDisplayName(matchedOrganization))"
                )
            }
            if let employment = author.employments.first(where: { $0.organization.trimmedOrNil != nil && linkedOrganization(id: $0.organizationID, name: $0.organization) == nil }),
               let matchedOrganization = obviousOrganizationMatch(for: employment.organization) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .people,
                    recordID: author.id,
                    title: author.displayName,
                    subtitle: language.text("Employment could be linked to an existing organization", "Anställning kan kopplas till en befintlig organisation"),
                    details: "\(employment.organization) → \(dataQualityLocalizedOptionDisplayName(matchedOrganization))"
                )
            }
            if let education = author.educationEntries.first(where: { $0.organization.trimmedOrNil != nil && linkedOrganization(id: $0.organizationID, name: $0.organization) == nil }),
               let matchedOrganization = obviousOrganizationMatch(for: education.organization) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .people,
                    recordID: author.id,
                    title: author.displayName,
                    subtitle: language.text("Education could be linked to an existing organization", "Utbildning kan kopplas till en befintlig organisation"),
                    details: "\(education.organization) → \(dataQualityLocalizedOptionDisplayName(matchedOrganization))"
                )
            }
        }

        for assignment in teachingAssignments {
            if let contextID = assignment.contextID,
               teachingCourses.contains(where: { $0.id == contextID }) == false {
                appendIssue(
                    kind: .brokenLink,
                    destination: .teaching,
                    recordID: assignment.id,
                    title: assignment.activityName.nonEmpty ?? assignment.comment.nonEmpty ?? assignment.id,
                    subtitle: language.text("Missing linked teaching context", "Saknar länkad undervisningskontext"),
                    details: contextID
                )
            }
            if let activityID = assignment.activityID,
               dataQualityTeachingComponent(id: activityID) == nil {
                appendIssue(
                    kind: .brokenLink,
                    destination: .teaching,
                    recordID: assignment.id,
                    title: assignment.activityName.nonEmpty ?? assignment.comment.nonEmpty ?? assignment.id,
                    subtitle: language.text("Missing linked teaching assignment option", "Saknar länkat undervisningsuppdragsalternativ"),
                    details: activityID
                )
            }
        }

        // F19: links to records that no longer exist, and times in the wrong
        // order. Kept in their own pass so the check after saving can run
        // them without the rest of this list.
        issues.append(contentsOf: dataQualityLinkAndTimeIssues())

        return issues.sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue.localizedStandardCompare($1.kind.rawValue) == .orderedAscending
            }
            if $0.title != $1.title {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.details.localizedStandardCompare($1.details) == .orderedAscending
        }
    }

    nonisolated static func dataQualityDestinationKey(_ destination: AppRoute.Destination) -> String {
        switch destination {
        case .applications: return "applications"
        case .congresses: return "congresses"
        case .cv: return "cv"
        case .expertAssignments: return "expertAssignments"
        case .publications: return "publications"
        case .projects: return "projects"
        case .teaching: return "teaching"
        case .doctoralCandidates: return "doctoralCandidates"
        case .organizations: return "organizations"
        case .people: return "people"
        case .journals: return "journals"
        }
    }

    /// F19: stored ids that point to a record that no longer exists, and
    /// end times or end dates before their start. Every lookup goes through
    /// a set of ids built once, so the pass is linear in the number of
    /// records and cheap enough to run after every save.
    /// F43: `forSaveCheck` is true for the check after saving. Only then are
    /// researcher links of the five kinds that the Data view already reports
    /// with their own rows (doctoral candidate, supervisor, presenter,
    /// contributor, congress participant) included, so the Data view never
    /// shows the same broken link twice.
    func dataQualityLinkAndTimeIssues(forSaveCheck: Bool = false) -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []

        func appendIssue(
            kind: IntegrityIssue.Kind,
            destination: AppRoute.Destination,
            recordID: String,
            title: String,
            subtitle: String,
            details: String,
            calendarRevealDayString: String? = nil,
            calendarEventSource: CalendarWorkspaceEventSource? = nil
        ) {
            issues.append(
                IntegrityIssue(
                    id: "\(kind.rawValue)-\(Self.dataQualityDestinationKey(destination))-\(recordID)-\(details)",
                    kind: kind,
                    destination: destination,
                    recordID: recordID,
                    title: title,
                    subtitle: subtitle,
                    details: details,
                    calendarRevealDayString: calendarRevealDayString,
                    calendarEventSource: calendarEventSource
                )
            )
        }
        func parsedDay(_ value: String?) -> Date? {
            guard let value = value?.trimmedOrNil else { return nil }
            return DateParsers.isoDay.date(from: value)
        }
        func sameCountry(_ left: String, _ right: String) -> Bool {
            let canonicalLeft = GrantParsing.canonicalCountryName(left).trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalRight = GrantParsing.canonicalCountryName(right).trimmingCharacters(in: .whitespacesAndNewlines)
            return canonicalLeft.caseInsensitiveCompare(canonicalRight) == .orderedSame
        }
        /// Ids that are set but not found among `valid`, each reported once.
        func dangling(_ ids: [String?], in valid: Set<String>) -> [String] {
            var seen: Set<String> = []
            var result: [String] = []
            for raw in ids {
                guard let id = raw?.trimmedOrNil, !valid.contains(id), seen.insert(id).inserted else { continue }
                result.append(id)
            }
            return result
        }

        let validProjectIDs = Set(projects.map(\.id))
        let validOrganizationIDs = Set(organizations.map(\.id))
        let validApplicationIDs = Set(applications.map(\.id))
        let validPublicationIDs = Set(publicationRecords.map(\.id))
        let validAuthorIDs = Set(publicationAuthors.map(\.id))
        let validJournalIDs = Set(publicationJournals.map(\.id))
        let validCourseIDs = Set(teachingCourses.map(\.id))
        let validFormatIDs = Set(teachingFormats.map(\.id))
        let validMediaIDs = Set(cvMediaAppearances.map(\.id))

        // MARK: Links

        for assignment in teachingAssignments {
            let title = assignment.activityName.nonEmpty ?? assignment.comment.nonEmpty ?? assignment.id
            for id in dangling([assignment.activityTypeID], in: validFormatIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .teaching,
                    recordID: assignment.id,
                    title: title,
                    subtitle: language.text("Teaching format ID links to missing format", "Undervisningsform-ID länkar till saknad undervisningsform"),
                    details: id
                )
            }
            for id in dangling([assignment.studentAuthorID], in: validAuthorIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .teaching,
                    recordID: assignment.id,
                    title: title,
                    subtitle: language.text("Student ID links to missing researcher", "Student-ID länkar till saknad forskare"),
                    details: id
                )
            }
            for id in dangling([assignment.authorID], in: validAuthorIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .teaching,
                    recordID: assignment.id,
                    title: title,
                    subtitle: language.text("Teacher ID links to missing researcher", "Lärar-ID länkar till saknad forskare"),
                    details: id
                )
            }
        }

        for component in teachingComponents {
            let title = component.nameSv.nonEmpty ?? component.nameEn.nonEmpty ?? component.id
            for id in dangling([component.institutionID], in: validOrganizationIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .teaching,
                    recordID: component.id,
                    title: title,
                    subtitle: language.text("Institution ID links to missing organization", "Institutions-ID länkar till saknad organisation"),
                    details: id
                )
            }
            for id in dangling([component.activityTypeID], in: validFormatIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .teaching,
                    recordID: component.id,
                    title: title,
                    subtitle: language.text("Teaching format ID links to missing format", "Undervisningsform-ID länkar till saknad undervisningsform"),
                    details: id
                )
            }
            for id in dangling(component.allowedContextIDs.map(Optional.some), in: validCourseIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .teaching,
                    recordID: component.id,
                    title: title,
                    subtitle: language.text("Allowed course ID links to missing course", "Tillåten kurs-ID länkar till saknad kurs"),
                    details: id
                )
            }
        }

        for course in teachingCourses {
            let title = course.localizedName(language: language).nonEmpty
                ?? course.localizedProgram(language: language).nonEmpty
                ?? course.id
            for id in dangling([course.programID], in: validCourseIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .teaching,
                    recordID: course.id,
                    title: title,
                    subtitle: language.text("Programme ID links to missing programme", "Program-ID länkar till saknat program"),
                    details: id
                )
            }
            for id in dangling([course.institutionID], in: validOrganizationIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .teaching,
                    recordID: course.id,
                    title: title,
                    subtitle: language.text("Institution ID links to missing organization", "Institutions-ID länkar till saknad organisation"),
                    details: id
                )
            }
        }

        for publication in publicationRecords {
            let title = publication.title.nonEmpty ?? publication.number
            for id in dangling([publication.journalID] + publication.previousAttempts.map(\.journalID), in: validJournalIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .publications,
                    recordID: publication.id,
                    title: title,
                    subtitle: language.text("Journal ID links to missing journal", "Tidskrifts-ID länkar till saknad tidskrift"),
                    details: id
                )
            }
        }

        for review in cvReviewEntries {
            for id in dangling([review.journalID], in: validJournalIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "review:\(review.id)",
                    title: review.displayTitle,
                    subtitle: language.text("Journal ID links to missing journal", "Tidskrifts-ID länkar till saknad tidskrift"),
                    details: id
                )
            }
            for id in dangling([review.organizationID], in: validOrganizationIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "review:\(review.id)",
                    title: review.displayTitle,
                    subtitle: language.text("Organization ID links to missing organization", "Organisations-ID länkar till saknad organisation"),
                    details: id
                )
            }
            for id in dangling([review.authorID], in: validAuthorIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "review:\(review.id)",
                    title: review.displayTitle,
                    subtitle: language.text("Reviewer ID links to missing researcher", "Granskar-ID länkar till saknad forskare"),
                    details: id
                )
            }
        }

        for contribution in cvConferenceContributions {
            let title = contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle
            for id in dangling([contribution.projectID], in: validProjectIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: title,
                    subtitle: language.text("Project ID links to missing project", "Projekt-ID länkar till saknat projekt"),
                    details: id
                )
            }
            for id in dangling([contribution.journalID], in: validJournalIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: "conferenceContribution:\(contribution.id)",
                    title: title,
                    subtitle: language.text("Journal ID links to missing journal", "Tidskrifts-ID länkar till saknad tidskrift"),
                    details: id
                )
            }
        }

        for media in cvMediaAppearances {
            let title = media.localizedTitle(language: language).nonEmpty ?? media.displayTitle
            let recordID = "mediaAppearance:\(media.id)"
            for id in dangling([media.authorID] + media.authorIDs.map(Optional.some), in: validAuthorIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: recordID,
                    title: title,
                    subtitle: language.text("Researcher ID links to missing researcher", "Forskar-ID länkar till saknad forskare"),
                    details: id
                )
            }
            for id in dangling(media.projectIDs.map(Optional.some), in: validProjectIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: recordID,
                    title: title,
                    subtitle: language.text("Project ID links to missing project", "Projekt-ID länkar till saknat projekt"),
                    details: id
                )
            }
            for id in dangling(media.publicationIDs.map(Optional.some), in: validPublicationIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: recordID,
                    title: title,
                    subtitle: language.text("Publication ID links to missing publication", "Publikations-ID länkar till saknad publikation"),
                    details: id
                )
            }
            for id in dangling(media.applicationIDs.map(Optional.some), in: validApplicationIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: recordID,
                    title: title,
                    subtitle: language.text("Grant ID links to missing grant", "Anslags-ID länkar till saknat anslag"),
                    details: id
                )
            }
        }

        for project in projects {
            let title = project.nameSv.nonEmpty ?? project.nameEn.nonEmpty ?? project.id
            for id in dangling(project.principalOrganizations.map(\.organizationID), in: validOrganizationIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .projects,
                    recordID: project.id,
                    title: title,
                    subtitle: language.text("Principal organization ID links to missing organization", "Huvudmans-ID länkar till saknad organisation"),
                    details: id
                )
            }
        }

        // MARK: Calendar links and times

        for meeting in calendarMeetingRecords {
            let title = meeting.title.nonEmpty ?? language.text("Calendar event", "Kalenderhändelse")
            for id in dangling(meeting.mediaAppearanceIDs.map(Optional.some), in: validMediaIDs) {
                appendIssue(
                    kind: .brokenLink,
                    destination: .cv,
                    recordID: meeting.id,
                    title: title,
                    subtitle: language.text("Calendar event links to missing media appearance", "Kalenderhändelse länkar till saknat mediaframträdande"),
                    details: [meeting.date.nonEmpty, id.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                    calendarRevealDayString: meeting.date,
                    calendarEventSource: .meeting(meeting.id)
                )
            }
            if Self.dataQualityTimeEndsBeforeStart(start: meeting.startTime, end: meeting.endTime) {
                appendIssue(
                    kind: .semantic,
                    destination: .projects,
                    recordID: meeting.id,
                    title: title,
                    subtitle: language.text("Calendar event ends before it starts", "Kalenderhändelse slutar före den börjar"),
                    details: [meeting.date.nonEmpty, "\(meeting.startTime)–\(meeting.endTime)"].compactMap { $0 }.joined(separator: " · "),
                    calendarRevealDayString: meeting.date,
                    calendarEventSource: .meeting(meeting.id)
                )
            }
        }

        for travel in calendarTravelRecords {
            let title = [
                travel.mode.localizedName(language: language),
                travel.date.nonEmpty,
                travel.fromCity.nonEmpty,
                travel.toCity.nonEmpty
            ].compactMap { $0 }.joined(separator: " · ")
            let departure = parsedDay(travel.date)
            let arrival = parsedDay(travel.arrivalDate)
            if let departure, let arrival, arrival < departure {
                appendIssue(
                    kind: .semantic,
                    destination: .congresses,
                    recordID: travel.id,
                    title: title.nonEmpty ?? language.text("Travel", "Resa"),
                    subtitle: language.text("Travel arrives before it departs", "Resa kommer fram före avresan"),
                    details: "\(travel.date) → \(travel.arrivalDate)",
                    calendarRevealDayString: travel.date,
                    calendarEventSource: .travel(travel.id)
                )
            } else if let departure, let arrival, arrival == departure,
                      // Local times: across a time-zone border an earlier
                      // arrival clock time can be correct.
                      sameCountry(travel.fromCountry, travel.toCountry),
                      Self.dataQualityTimeEndsBeforeStart(start: travel.departureTime, end: travel.arrivalTime) {
                appendIssue(
                    kind: .semantic,
                    destination: .congresses,
                    recordID: travel.id,
                    title: title.nonEmpty ?? language.text("Travel", "Resa"),
                    subtitle: language.text("Travel arrival time before departure time", "Resans ankomsttid före avgångstid"),
                    details: "\(travel.date) · \(travel.departureTime)–\(travel.arrivalTime)",
                    calendarRevealDayString: travel.date,
                    calendarEventSource: .travel(travel.id)
                )
            }
        }

        for accommodation in calendarAccommodationRecords {
            let title = [
                accommodation.hotelName.nonEmpty,
                accommodation.checkInDate.nonEmpty,
                accommodation.city.nonEmpty
            ].compactMap { $0 }.joined(separator: " · ")
            let checkIn = parsedDay(accommodation.checkInDate)
            let checkOut = parsedDay(accommodation.checkOutDate)
            let endsEarly: Bool
            if let checkIn, let checkOut {
                endsEarly = checkOut < checkIn
                    || (checkOut == checkIn
                        && Self.dataQualityTimeEndsBeforeStart(start: accommodation.checkInTime, end: accommodation.checkOutTime))
            } else {
                endsEarly = false
            }
            if endsEarly {
                appendIssue(
                    kind: .semantic,
                    destination: .congresses,
                    recordID: accommodation.id,
                    title: title.nonEmpty ?? language.text("Accommodation", "Boende"),
                    subtitle: language.text("Check-out before check-in", "Utcheckning före incheckning"),
                    details: "\(accommodation.checkInDate) \(accommodation.checkInTime) → \(accommodation.checkOutDate) \(accommodation.checkOutTime)",
                    calendarRevealDayString: accommodation.checkInDate,
                    calendarEventSource: .accommodation(accommodation.id)
                )
            }
        }

        // MARK: Links to researchers (F43)

        issues.append(contentsOf: dataQualityMissingResearcherLinkIssues(
            validAuthorIDs: validAuthorIDs,
            includesKindsReportedElsewhere: forSaveCheck
        ))

        return issues
    }

    func dataQualityDuplicateIssues() -> [DuplicateIssue] {
        var issues: [DuplicateIssue] = []

        func normalize(_ value: String) -> String {
            value
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        func normalizedIdentifier(_ value: String) -> String {
            normalize(value)
                .replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^(orcid\.org/|doi\.org/|dx\.doi\.org/)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^(doi:|pmid:)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\?.*$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"[^a-z0-9x]+"#, with: "", options: .regularExpression)
        }

        func normalizedEmail(_ value: String) -> String {
            normalize(value)
                .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        }

        func appendGroup(
            kind: DuplicateIssue.GroupKind,
            title: String,
            destination: AppRoute.Destination,
            rows: [(id: String, name: String, subtitle: String)]
        ) {
            let grouped = Dictionary(grouping: rows) { normalize($0.name) }
            for (key, values) in grouped where !key.isEmpty && values.count > 1 {
                let entries = values.sorted {
                    if $0.name != $1.name {
                        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                    return $0.subtitle.localizedStandardCompare($1.subtitle) == .orderedAscending
                }
                .map {
                    DuplicateEntry(
                        id: "\(kind.rawValue)-\($0.id)",
                        recordID: $0.id,
                        destination: destination,
                        title: $0.name,
                        subtitle: $0.subtitle
                    )
                }

                issues.append(
                    DuplicateIssue(
                        id: "\(kind.rawValue)-\(key)",
                        groupKind: kind,
                        normalizedKey: key,
                        title: title,
                        entries: entries
                    )
                )
            }
        }

        func appendKeyedGroup(
            kind: DuplicateIssue.GroupKind,
            title: String,
            destination: AppRoute.Destination,
            keyPrefix: String,
            rows: [(key: String, id: String, name: String, subtitle: String)]
        ) {
            let grouped = Dictionary(grouping: rows) { normalize($0.key) }
            for (key, values) in grouped where !key.isEmpty {
                let uniqueValues = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
                guard uniqueValues.count > 1 else { continue }

                let entries = uniqueValues.sorted {
                    if $0.name != $1.name {
                        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                    return $0.subtitle.localizedStandardCompare($1.subtitle) == .orderedAscending
                }
                .map {
                    DuplicateEntry(
                        id: "\(kind.rawValue)-\(keyPrefix)-\($0.id)",
                        recordID: $0.id,
                        destination: destination,
                        title: $0.name,
                        subtitle: $0.subtitle
                    )
                }

                let issueNormalizedKey = "\(keyPrefix):\(key)"
                issues.append(
                    DuplicateIssue(
                        id: "\(kind.rawValue)-\(keyPrefix)-\(key)",
                        groupKind: kind,
                        normalizedKey: issueNormalizedKey,
                        title: title,
                        entries: entries
                    )
                )
            }
        }

        func researcherSubtitle(_ author: PublicationAuthor) -> String {
            [author.title.nonEmpty, author.primaryAffiliation?.organization.nonEmpty]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        func journalSubtitle(_ journal: PublicationJournal) -> String {
            [journal.issn.nonEmpty, journal.eissn.nonEmpty]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        func publicationSubtitle(_ publication: PublicationRecord) -> String {
            [publication.journal.nonEmpty, publication.year.nonEmpty]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        appendGroup(
            kind: .researchers,
            title: language.text("Possible duplicate researchers", "Möjliga dubbla forskare"),
            destination: .people,
            rows: publicationAuthors.map { ($0.id, $0.displayName, researcherSubtitle($0)) }
        )

        appendKeyedGroup(
            kind: .researchers,
            title: language.text("Possible duplicate researchers (ORCID)", "Möjliga dubbla forskare (ORCID)"),
            destination: .people,
            keyPrefix: "orcid",
            rows: publicationAuthors.compactMap { author -> (key: String, id: String, name: String, subtitle: String)? in
                guard let key = normalizedIdentifier(author.orcid).nonEmpty else { return nil }
                return (key, author.id, author.displayName, researcherSubtitle(author))
            }
        )

        appendKeyedGroup(
            kind: .researchers,
            title: language.text("Possible duplicate researchers (Scopus ID)", "Möjliga dubbla forskare (Scopus ID)"),
            destination: .people,
            keyPrefix: "scopus",
            rows: publicationAuthors.compactMap { author -> (key: String, id: String, name: String, subtitle: String)? in
                guard let key = normalizedIdentifier(author.scopus).nonEmpty else { return nil }
                return (key, author.id, author.displayName, researcherSubtitle(author))
            }
        )

        appendKeyedGroup(
            kind: .researchers,
            title: language.text("Possible duplicate researchers (ResearcherID)", "Möjliga dubbla forskare (ResearcherID)"),
            destination: .people,
            keyPrefix: "researcherid",
            rows: publicationAuthors.compactMap { author -> (key: String, id: String, name: String, subtitle: String)? in
                guard let key = normalizedIdentifier(author.researcherID).nonEmpty else { return nil }
                return (key, author.id, author.displayName, researcherSubtitle(author))
            }
        )

        appendKeyedGroup(
            kind: .researchers,
            title: language.text("Possible duplicate researchers (email)", "Möjliga dubbla forskare (e-post)"),
            destination: .people,
            keyPrefix: "email",
            rows: publicationAuthors.flatMap { author -> [(key: String, id: String, name: String, subtitle: String)] in
                Set(author.affiliations.compactMap { normalizedEmail($0.email).nonEmpty }).map {
                    (key: $0, id: author.id, name: author.displayName, subtitle: researcherSubtitle(author))
                }
            }
        )

        appendGroup(
            kind: .journals,
            title: language.text("Possible duplicate journals", "Möjliga dubbla tidskrifter"),
            destination: .journals,
            rows: publicationJournals.map { ($0.id, $0.name, journalSubtitle($0)) }
        )

        appendKeyedGroup(
            kind: .journals,
            title: language.text("Possible duplicate journals (ISSN/eISSN)", "Möjliga dubbla tidskrifter (ISSN/eISSN)"),
            destination: .journals,
            keyPrefix: "issn",
            rows: publicationJournals.flatMap { journal -> [(key: String, id: String, name: String, subtitle: String)] in
                Set([journal.issn, journal.eissn].compactMap { normalizedIdentifier($0).nonEmpty }).map {
                    (key: $0, id: journal.id, name: journal.name, subtitle: journalSubtitle(journal))
                }
            }
        )

        appendGroup(
            kind: .funders,
            title: language.text("Possible duplicate funders", "Möjliga dubbla anslagsgivare"),
            destination: .organizations,
            rows: organizations.map { ($0.id, dataQualityLocalizedOptionDisplayName($0), $0.category.map(language.localizedGrantCategory) ?? "") }
        )

        appendGroup(
            kind: .projects,
            title: language.text("Possible duplicate projects", "Möjliga dubbla projekt"),
            destination: .projects,
            rows: projects.map { ($0.id, dataQualityLocalizedOptionDisplayName($0), $0.collaboratorNames.prefix(3).joined(separator: ", ")) }
        )

        appendGroup(
            kind: .publications,
            title: language.text("Possible duplicate publications", "Möjliga dubbla publikationer"),
            destination: .publications,
            rows: publicationRecords.map { ($0.id, $0.title.nonEmpty ?? $0.number, publicationSubtitle($0)) }
        )

        appendKeyedGroup(
            kind: .publications,
            title: language.text("Possible duplicate publications (DOI)", "Möjliga dubbla publikationer (DOI)"),
            destination: .publications,
            keyPrefix: "doi",
            rows: publicationRecords.compactMap { publication -> (key: String, id: String, name: String, subtitle: String)? in
                guard let key = normalizedIdentifier(publication.doi).nonEmpty else { return nil }
                return (key, publication.id, publication.title.nonEmpty ?? publication.number, publicationSubtitle(publication))
            }
        )

        appendKeyedGroup(
            kind: .publications,
            title: language.text("Possible duplicate publications (PMID)", "Möjliga dubbla publikationer (PMID)"),
            destination: .publications,
            keyPrefix: "pmid",
            rows: publicationRecords.compactMap { publication -> (key: String, id: String, name: String, subtitle: String)? in
                guard let key = normalizedIdentifier(publication.pmid).nonEmpty else { return nil }
                return (key, publication.id, publication.title.nonEmpty ?? publication.number, publicationSubtitle(publication))
            }
        )

        return issues.sorted {
            if $0.groupKind.rawValue != $1.groupKind.rawValue {
                return $0.groupKind.rawValue.localizedStandardCompare($1.groupKind.rawValue) == .orderedAscending
            }
            return ($0.entries.first?.title ?? "").localizedStandardCompare($1.entries.first?.title ?? "") == .orderedAscending
        }
    }

    func dataQualityArchivedRecordSummaries() -> [ArchivedRecordSummary] {
        let archived: [ArchivedRecordEnvelope]
        do {
            archived = try loadArchivedRecords()
        } catch {
            loadError = error.localizedDescription
            notice = StoreNotice(
                message: language.text("The archive could not be read.", "Arkivet kunde inte läsas."),
                tone: .error
            )
            return []
        }
        let formatter = ISO8601DateFormatter()
        return archived.map { record in
            let date = formatter.date(from: record.deletedAt)
            let payloadFieldLines = dataQualityArchivedFieldLines(from: record.payload)
            let relatedDocuments = (record.relatedDocumentStates ?? []).map { state in
                ArchivedRecordSummary.RelatedDocumentSummary(
                    id: state.storageKey,
                    title: dataQualityArchivedStorageKeyTitle(state.storageKey),
                    fieldLines: dataQualityArchivedFieldLines(from: state.data)
                )
            }
            return ArchivedRecordSummary(
                id: record.id,
                kind: record.kind,
                localizedKind: dataQualityLocalizedArchivedKind(record.kind),
                title: record.title,
                deletedAt: date,
                deletedAtText: date.map { DateParsers.isoDay.string(from: $0) } ?? record.deletedAt,
                fieldLines: payloadFieldLines,
                relatedDocuments: relatedDocuments
            )
        }
        .sorted {
            ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
        }
    }

    func dataQualityArchivedStorageKeyTitle(_ storageKey: String) -> String {
        switch storageKey {
        case "applications": return language.text("Related grants", "Relaterade anslag")
        case "organizations": return language.text("Related organizations", "Relaterade organisationer")
        case "congresses": return language.text("Related congresses", "Relaterade kongresser")
        case "relational_core": return language.text("Related relationship index", "Relaterat relationsindex")
        case "calendar_travel_records": return language.text("Related calendar travel", "Relaterade kalenderresor")
        case "calendar_accommodation_records": return language.text("Related accommodation", "Relaterat boende")
        case "calendar_meeting_records": return language.text("Related calendar meetings", "Relaterade kalenderhändelser")
        case "calendar_vertical_note_records": return language.text("Related calendar notes", "Relaterade kalendernoteringar")
        case "managers": return language.text("Related fund managers", "Relaterade medelsförvaltare")
        case "projects": return language.text("Related projects", "Relaterade projekt")
        case "publication_authors": return language.text("Related researchers", "Relaterade forskare")
        case "publication_journals": return language.text("Related journals", "Relaterade tidskrifter")
        case "publication_records": return language.text("Related publications", "Relaterade publikationer")
        case "teaching_courses": return language.text("Related courses", "Relaterade kurser")
        case "teaching_assignments": return language.text("Related teaching assignments", "Relaterade undervisningsuppdrag")
        case "doctoral_candidates": return language.text("Related doctoral candidates", "Relaterade doktorander")
        case "teaching_components": return language.text("Related components", "Relaterade moment")
        case "teaching_formats", "teaching_activity_types": return language.text("Related activity types", "Relaterade aktivitetstyper")
        case "cv_conference_contributions": return language.text("Related conference contributions", "Relaterade konferensbidrag")
        case "cv_media_appearances": return language.text("Related media appearances", "Relaterad medverkan i media")
        case "cv_review_entries": return language.text("Related reviews", "Relaterade sakkunniguppdrag")
        case "cv_other_publications": return language.text("Related other publications", "Relaterade övriga publikationer")
        default: return storageKey
        }
    }

    func dataQualityArchivedFieldLines(from data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var lines: [String] = []

        func appendLines(from value: Any, prefix: String? = nil) {
            switch value {
            case let dictionary as [String: Any]:
                for key in dictionary.keys.sorted() {
                    guard let child = dictionary[key] else { continue }
                    let nextPrefix = prefix.map { "\($0).\(key)" } ?? key
                    appendLines(from: child, prefix: nextPrefix)
                }
            case let array as [Any]:
                if array.isEmpty { return }
                for (index, child) in array.enumerated() {
                    let nextPrefix = prefix.map { "\($0)[\(index)]" } ?? "[\(index)]"
                    appendLines(from: child, prefix: nextPrefix)
                }
            case let string as String:
                guard let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else { return }
                lines.append("\(prefix ?? "value"): \(trimmed)")
            case let number as NSNumber:
                lines.append("\(prefix ?? "value"): \(number)")
            case _ as NSNull:
                break
            default:
                lines.append("\(prefix ?? "value"): \(String(describing: value))")
            }
        }

        appendLines(from: object)
        return lines
    }

    func dataQualityLocalizedArchivedKind(_ kind: String) -> String {
        switch kind {
        case "application":
            return language.text("Application", "Ansökan")
        case "organization":
            return language.text("Funder", "Anslagsgivare")
        case "manager":
            return language.text("Fund manager", "Medelsförvaltare")
        case "project":
            return language.text("Project", "Projekt")
        case "teaching_course":
            return language.text("Course", "Kurs")
        case "teaching_component":
            return language.text("Teaching component", "Undervisningsmoment")
        case "teaching_format":
            return language.text("Teaching format", "Undervisningsform")
        case "teaching_assignment":
            return language.text("Assignment", "Uppdrag")
        case "doctoral_candidate":
            return language.text("Doctoral candidate", "Doktorand")
        case "publication_author":
            return language.text("Researcher", "Forskare")
        case "publication_journal":
            return language.text("Journal", "Tidskrift")
        case "publication_record":
            return language.text("Publication", "Publikation")
        case "cv_conference_contribution":
            return language.text("Conference contribution", "Konferensbidrag")
        case "cv_media_appearance":
            return language.text("Media appearance", "Medverkan i media")
        case "cv_review_entry":
            return language.text("Review", "Sakkunniguppdrag")
        case "cv_other_publication":
            return language.text("Other publication", "Övrig publikation")
        default:
            return kind
        }
    }

    func dataQualityHasManager(named name: String) -> Bool {
        for manager in managers {
            if manager.nameSv == name || manager.nameEn == name {
                return true
            }
        }
        return false
    }

    func dataQualityTeachingComponent(id: String?) -> TeachingComponent? {
        guard let id else { return nil }
        return teachingComponents.first(where: { $0.id == id })
    }

    func dataQualityLocalizedManagerDisplayName(_ manager: ManagerOption) -> String {
        language == .swedish ? manager.nameSv : (manager.nameEn.nonEmpty ?? manager.nameSv)
    }

    func dataQualityLocalizedOptionDisplayName<T: LocalizedNamedRecord>(_ option: T) -> String {
        language == .swedish ? option.nameSv : (option.nameEn.nonEmpty ?? option.nameSv)
    }
}
