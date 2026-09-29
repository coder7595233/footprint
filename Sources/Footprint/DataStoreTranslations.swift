import Foundation

/// F12: the Data view's "Missing translations" list. Every bilingual field
/// that is empty on one side, or (where the text is an ordinary word) the
/// same on both sides, becomes one row with Swedish on the left and English
/// on the right, editable in place.
extension GrantDataStore {
    struct TranslationIssue: Identifiable, Equatable {
        enum Kind: String, CaseIterable {
            case organization
            case project
            case manager
            case teachingCourse
            case teachingComponent
            case teachingFormat
            case researcher
            case conferenceContribution
            case mediaAppearance
            case otherPublication
        }

        enum Field: String, CaseIterable {
            case name
            case fullName
            case program
            case term
            case title
            case position
            case degree
        }

        enum Reason: String {
            case missingEnglish
            case missingSwedish
            case identical
        }

        let kind: Kind
        let recordID: String
        let field: Field
        let reason: Reason
        /// The record's name as the list shows it.
        let recordTitle: String
        let valueSv: String
        let valueEn: String
        /// Where clicking the record title goes; nil when the record has no
        /// page of its own to open.
        let destination: AppRoute.Destination?
        let routeRecordID: String

        /// Organization, project and manager names keep the key the list used
        /// before F12, so names already marked as intentionally identical stay
        /// hidden.
        var id: String {
            switch (kind, field) {
            case (.organization, .name), (.project, .name), (.manager, .name):
                return "untranslated:v1|\(kind.rawValue)|\(recordID)"
            default:
                return "untranslated:v1|\(kind.rawValue)|\(recordID)|\(field.rawValue)"
            }
        }

        /// Kept for callers written before the list covered more than names.
        var nameSv: String { valueSv }
        var nameEn: String { valueEn }

        func kindTitle(language: AppLanguage) -> String {
            switch kind {
            case .organization:
                return language.text("Organization", "Organisation")
            case .project:
                return language.text("Project", "Projekt")
            case .manager:
                return language.text("Manager", "Handläggare")
            case .teachingCourse:
                return language.text("Course", "Kurs")
            case .teachingComponent:
                return language.text("Teaching activity", "Undervisningsaktivitet")
            case .teachingFormat:
                return language.text("Teaching format", "Undervisningsformat")
            case .researcher:
                return language.text("Researcher", "Forskare")
            case .conferenceContribution:
                return language.text("Conference contribution", "Konferensbidrag")
            case .mediaAppearance:
                return language.text("Media appearance", "Medverkan i media")
            case .otherPublication:
                return language.text("Other publication", "Övrig publikation")
            }
        }

        func fieldLabel(language: AppLanguage) -> String {
            switch field {
            case .name:
                return language.text("Name", "Namn")
            case .fullName:
                return language.text("Full name", "Fullständigt namn")
            case .program:
                return language.text("Programme name", "Programnamn")
            case .term:
                return language.text("Term", "Termin")
            case .title:
                return language.text("Title", "Titel")
            case .position:
                return language.text("Position", "Befattning")
            case .degree:
                return language.text("Degree", "Examen")
            }
        }

        func reasonText(language: AppLanguage) -> String {
            switch reason {
            case .missingEnglish:
                return language.text("English missing", "Engelska saknas")
            case .missingSwedish:
                return language.text("Swedish missing", "Svenska saknas")
            case .identical:
                return language.text("English same as Swedish", "Engelskan är samma som svenskan")
            }
        }
    }

    /// All bilingual fields that still need a translation. Hidden rows
    /// (marked as intentionally identical) are left out unless asked for.
    /// The Data view asks for this list on every redraw (the section summary
    /// and the rows), so it is built once per change and language.
    func translationIssues(includeHidden: Bool = false) -> [TranslationIssue] {
        let all: [TranslationIssue]
        if let cached = cachedTranslationIssues, cached.language == language {
            all = cached.issues
        } else {
            all = buildTranslationIssues()
            cachedTranslationIssues = (language, all)
        }
        return includeHidden ? all : all.filter { !isDataQualityWarningHidden($0) }
    }

    private func buildTranslationIssues() -> [TranslationIssue] {
        var issues: [TranslationIssue] = []

        func title(_ sv: String, _ en: String, fallback: String) -> String {
            language.text(
                en.nonEmpty ?? sv.nonEmpty ?? fallback,
                sv.nonEmpty ?? en.nonEmpty ?? fallback
            )
        }

        func check(
            _ kind: TranslationIssue.Kind,
            recordID: String,
            recordTitle: String,
            destination: AppRoute.Destination?,
            routeRecordID: String? = nil,
            field: TranslationIssue.Field,
            sv valueSv: String,
            en valueEn: String,
            flagIdentical: Bool
        ) {
            let sv = valueSv.trimmingCharacters(in: .whitespacesAndNewlines)
            let en = valueEn.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason: TranslationIssue.Reason
            if !sv.isEmpty && en.isEmpty {
                reason = .missingEnglish
            } else if sv.isEmpty && !en.isEmpty {
                reason = .missingSwedish
            } else if flagIdentical && !sv.isEmpty && sv == en {
                reason = .identical
            } else {
                return
            }
            let issue = TranslationIssue(
                kind: kind,
                recordID: recordID,
                field: field,
                reason: reason,
                recordTitle: recordTitle,
                valueSv: valueSv,
                valueEn: valueEn,
                destination: destination,
                routeRecordID: routeRecordID ?? recordID
            )
            issues.append(issue)
        }

        // Organization, project and manager names: checked as before F12,
        // including names that are the same in both languages. Names that
        // legitimately are the same are dismissed with the hide button.
        var listedOrganizationIDs = Set<String>()
        for organization in organizations where !organization.isArchived {
            listedOrganizationIDs.insert(organization.id)
            check(
                .organization,
                recordID: organization.id,
                recordTitle: title(organization.nameSv, organization.nameEn, fallback: organization.id),
                destination: .organizations,
                field: .name,
                sv: organization.nameSv,
                en: organization.nameEn,
                flagIdentical: true
            )
        }
        for project in projects {
            let projectTitle = title(project.nameSv, project.nameEn, fallback: project.id)
            check(
                .project,
                recordID: project.id,
                recordTitle: projectTitle,
                destination: .projects,
                field: .name,
                sv: project.nameSv,
                en: project.nameEn,
                flagIdentical: true
            )
            if !project.isArchived {
                check(
                    .project,
                    recordID: project.id,
                    recordTitle: projectTitle,
                    destination: .projects,
                    field: .fullName,
                    sv: project.fullNameSv,
                    en: project.fullNameEn,
                    flagIdentical: false
                )
            }
        }
        // Managers are organizations too; one row per name is enough.
        for manager in managers where !listedOrganizationIDs.contains(manager.id) {
            check(
                .manager,
                recordID: manager.id,
                recordTitle: title(manager.nameSv, manager.nameEn, fallback: manager.id),
                destination: nil,
                field: .name,
                sv: manager.nameSv,
                en: manager.nameEn,
                flagIdentical: true
            )
        }

        // Teaching names are ordinary words and should be translated, so an
        // English text identical to the Swedish one is flagged there. Terms
        // are often numbers, and courses inherit their programme's name, so
        // the "same as the Swedish" check is limited to course names and to
        // the programme row itself.
        for course in teachingCourses {
            let courseTitle = course.localizedName(language: language).nonEmpty
                ?? course.localizedProgram(language: language).nonEmpty
                ?? course.id
            check(.teachingCourse, recordID: course.id, recordTitle: courseTitle, destination: .teaching,
                  field: .name, sv: course.nameSv, en: course.nameEn, flagIdentical: true)
            check(.teachingCourse, recordID: course.id, recordTitle: courseTitle, destination: .teaching,
                  field: .program, sv: course.programSv, en: course.programEn,
                  flagIdentical: course.contextType == .programTrack)
            check(.teachingCourse, recordID: course.id, recordTitle: courseTitle, destination: .teaching,
                  field: .term, sv: course.termSv, en: course.termEn, flagIdentical: false)
        }
        for component in teachingComponents {
            check(.teachingComponent, recordID: component.id,
                  recordTitle: title(component.nameSv, component.nameEn, fallback: component.id),
                  destination: .teaching,
                  field: .name, sv: component.nameSv, en: component.nameEn, flagIdentical: false)
        }
        for format in teachingFormats {
            check(.teachingFormat, recordID: format.id,
                  recordTitle: title(format.nameSv, format.nameEn, fallback: format.id),
                  destination: .teaching,
                  field: .name, sv: format.nameSv, en: format.nameEn, flagIdentical: true)
        }

        for author in publicationAuthors {
            let authorTitle = author.displayName
            check(.researcher, recordID: author.id, recordTitle: authorTitle, destination: .people,
                  field: .title, sv: author.titleSv, en: author.titleEn, flagIdentical: false)
            check(.researcher, recordID: author.id, recordTitle: authorTitle, destination: .people,
                  field: .position, sv: author.positionSv, en: author.positionEn, flagIdentical: false)
            check(.researcher, recordID: author.id, recordTitle: authorTitle, destination: .people,
                  field: .degree, sv: author.degreeSv, en: author.degreeEn, flagIdentical: false)
        }

        for contribution in cvConferenceContributions {
            check(.conferenceContribution, recordID: contribution.id,
                  recordTitle: title(contribution.titleSv, contribution.titleEn, fallback: contribution.id),
                  destination: .cv, routeRecordID: "conferenceContribution:\(contribution.id)",
                  field: .title, sv: contribution.titleSv, en: contribution.titleEn, flagIdentical: false)
        }
        for media in cvMediaAppearances {
            check(.mediaAppearance, recordID: media.id,
                  recordTitle: title(media.titleSv, media.titleEn, fallback: media.id),
                  destination: .cv, routeRecordID: "mediaAppearance:\(media.id)",
                  field: .title, sv: media.titleSv, en: media.titleEn, flagIdentical: false)
        }
        for other in cvOtherPublications {
            check(.otherPublication, recordID: other.id,
                  recordTitle: title(other.titleSv, other.titleEn, fallback: other.id),
                  destination: .cv, routeRecordID: "otherPublication:\(other.id)",
                  field: .title, sv: other.titleSv, en: other.titleEn, flagIdentical: false)
        }

        let kindOrder = Dictionary(uniqueKeysWithValues: TranslationIssue.Kind.allCases.enumerated().map { ($0.element, $0.offset) })
        let fieldOrder = Dictionary(uniqueKeysWithValues: TranslationIssue.Field.allCases.enumerated().map { ($0.element, $0.offset) })
        return issues.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return (kindOrder[lhs.kind] ?? 0) < (kindOrder[rhs.kind] ?? 0)
            }
            let titleOrder = lhs.recordTitle.localizedStandardCompare(rhs.recordTitle)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            if lhs.recordID != rhs.recordID {
                return lhs.recordID < rhs.recordID
            }
            return (fieldOrder[lhs.field] ?? 0) < (fieldOrder[rhs.field] ?? 0)
        }
    }

    /// Saves one translated field from the Data view through the same
    /// autosave flow the record's own editor uses, so undo, renamed
    /// references and saving to disk work the same way.
    func saveTranslation(for issue: TranslationIssue, sv: String, en: String) {
        switch issue.kind {
        case .organization:
            guard let organization = organizations.first(where: { $0.id == issue.recordID }) else { return }
            autosaveOrganization(
                id: organization.id,
                nameSv: sv,
                nameEn: en,
                addressLine: organization.addressLine,
                postalCode: organization.postalCode,
                city: organization.city,
                country: organization.country,
                category: organization.category,
                roles: organization.roles,
                note: organization.note,
                websiteURL: organization.websiteURL,
                phoneNumber: organization.phoneNumber,
                organizationNumber: organization.organizationNumber,
                vatNumber: organization.vatNumber,
                employerContacts: organization.employerContacts,
                flag: organization.flag,
                membershipFrom: organization.membershipFrom,
                membershipTo: organization.membershipTo,
                congresses: organization.congresses,
                projectTasks: organization.projectTasks,
                salaryCalculator: organization.salaryCalculator,
                actionName: language.text("Translate name", "Översätt namn")
            )
        case .manager:
            guard let manager = managers.first(where: { $0.id == issue.recordID }) else { return }
            autosaveManager(
                id: manager.id,
                nameSv: sv,
                nameEn: en,
                reason: manager.reason,
                calculator: manager.salaryCalculator
            )
        case .project:
            guard var project = projects.first(where: { $0.id == issue.recordID }) else { return }
            let previousID = project.id
            switch issue.field {
            case .fullName:
                project.fullNameSv = sv
                project.fullNameEn = en
            default:
                project.nameSv = sv
                project.nameEn = en
            }
            autosaveProjectRecord(project, previousID: previousID)
        case .teachingCourse:
            guard var course = teachingCourses.first(where: { $0.id == issue.recordID }) else { return }
            switch issue.field {
            case .program:
                course.programSv = sv
                course.programEn = en
            case .term:
                course.termSv = sv
                course.termEn = en
            default:
                course.nameSv = sv
                course.nameEn = en
            }
            autosaveTeachingCourse(course)
        case .teachingComponent:
            guard var component = teachingComponents.first(where: { $0.id == issue.recordID }) else { return }
            component.nameSv = sv
            component.nameEn = en
            autosaveTeachingComponent(component)
        case .teachingFormat:
            guard var format = teachingFormats.first(where: { $0.id == issue.recordID }) else { return }
            format.nameSv = sv
            format.nameEn = en
            autosaveTeachingFormat(format)
        case .researcher:
            guard var author = publicationAuthors.first(where: { $0.id == issue.recordID }) else { return }
            let previousName = author.name
            switch issue.field {
            case .position:
                author.positionSv = sv
                author.positionEn = en
            case .degree:
                author.degreeSv = sv
                author.degreeEn = en
            default:
                author.titleSv = sv
                author.titleEn = en
            }
            autosavePublicationAuthor(author, previousName: previousName)
        case .conferenceContribution:
            guard var contribution = cvConferenceContributions.first(where: { $0.id == issue.recordID }) else { return }
            contribution.titleSv = sv
            contribution.titleEn = en
            autosaveCVConferenceContribution(contribution)
        case .mediaAppearance:
            guard var media = cvMediaAppearances.first(where: { $0.id == issue.recordID }) else { return }
            media.titleSv = sv
            media.titleEn = en
            autosaveCVMediaAppearance(media)
        case .otherPublication:
            guard var other = cvOtherPublications.first(where: { $0.id == issue.recordID }) else { return }
            other.titleSv = sv
            other.titleEn = en
            autosaveCVOtherPublication(other)
        }
    }
}
