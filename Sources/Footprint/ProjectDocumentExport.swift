import Foundation

/// One dated protocol entry aggregated from the calendar activities and tasks
/// linked to a record, rendered under the document's "Protokoll" heading and
/// in the inline protocol section of the project detail view.
struct ProjectProtocolEntry: Identifiable {
    /// The record the protocol text lives on, so the inline section can open
    /// its editor when the entry's date is clicked.
    enum Source: Equatable {
        case meeting(String)
        case centralTask(String)
        case projectTask(String)
        case publicationTask(String)
    }

    let sortKey: String
    let dateText: String
    let title: String
    let participantNames: [String]
    let linkedRecordLines: [String]
    let protocolText: String
    let source: Source

    var id: String { "\(sortKey)|\(title)|\(protocolText.hashValue)" }
}

/// The togglable top-level headings of the project document. The preview
/// panel shows one checkbox per case.
enum ProjectDocumentSection: String, CaseIterable, Identifiable {
    case summary
    case statistics
    case collaborators
    case applications
    case publications
    case conferenceContributions
    case calendar
    case tasks
    case protocolEntries

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .summary:
            return language.text("Summary", "Sammanfattning")
        case .statistics:
            return language.text("Statistics", "Statistik")
        case .collaborators:
            return language.text("Collaborators", "Medarbetare")
        case .applications:
            return language.text("Applications", "Ansökningar")
        case .publications:
            return language.text("Publications", "Publikationer")
        case .conferenceContributions:
            return language.text("Conference contributions", "Konferensbidrag")
        case .calendar:
            return language.text("Calendar events", "Kalenderhändelser")
        case .tasks:
            return language.text("Tasks", "Uppgifter")
        case .protocolEntries:
            return language.text("Protocol", "Protokoll")
        }
    }
}

/// The togglable top-level headings of the grant document.
enum ApplicationDocumentSection: String, CaseIterable, Identifiable {
    case summary
    case publications
    case calendar
    case tasks
    case protocolEntries

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .summary:
            return language.text("Summary", "Sammanfattning")
        case .publications:
            return language.text("Publications", "Publikationer")
        case .calendar:
            return language.text("Calendar events", "Kalenderhändelser")
        case .tasks:
            return language.text("Tasks", "Uppgifter")
        case .protocolEntries:
            return language.text("Protocol", "Protokoll")
        }
    }
}

/// The togglable top-level headings of the publication document.
enum PublicationDocumentSection: String, CaseIterable, Identifiable {
    case summary
    case reference
    case funding
    case calendar
    case tasks
    case protocolEntries

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .summary:
            return language.text("Summary", "Sammanfattning")
        case .reference:
            return language.text("Reference", "Referens")
        case .funding:
            return language.text("Funding", "Finansiering")
        case .calendar:
            return language.text("Calendar events", "Kalenderhändelser")
        case .tasks:
            return language.text("Tasks", "Uppgifter")
        case .protocolEntries:
            return language.text("Protocol", "Protokoll")
        }
    }
}

extension GrantDataStore {
    /// The full summary document for a project: master data, statistics,
    /// collaborators, applications, publications, calendar events, tasks and —
    /// as its own top-level heading — every linked activity/task with a
    /// filled-in protocol, oldest first. Rendered in-app as HTML and exported
    /// through the shared CV document pipeline (Word) or WKWebView (PDF).
    func projectSummaryDocument(
        for project: ProjectRecord,
        exportLanguage: AppLanguage,
        includedSections: Set<ProjectDocumentSection> = Set(ProjectDocumentSection.allCases)
    ) -> CVExportDocument {
        let viewData = projectViewData(forProjectName: project.nameSv, language: exportLanguage)
        let relatedApplications = viewData?.relatedApplications
            ?? applications.filter { $0.projectID?.trimmedOrNil == project.id }
        let relatedPublications = viewData?.relatedPublications
            ?? publicationRecords.filter { $0.projectID?.trimmedOrNil == project.id }
        let conferenceContributions = cvConferenceContributions.filter { contributionBelongs($0, to: project) }
        let meetings = calendarMeetingRecords
            .filter { calendarMeetingProjectIDs(for: $0, store: self).contains(project.id) }
            .sorted { ($0.date, $0.startTime, $0.title) < ($1.date, $1.startTime, $1.title) }
        let taskRecords = projectTaskWorkbookRecords(
            project: project,
            applications: relatedApplications,
            publications: relatedPublications,
            conferenceContributions: conferenceContributions,
            language: exportLanguage
        )
        let protocolEntries = projectProtocolEntries(
            meetings: meetings,
            taskRecords: taskRecords,
            language: exportLanguage
        )
        let initialsByNameKey = projectCollaboratorInitials(project.collaboratorNames)

        let fullName = exportLanguage == .swedish
            ? (project.fullNameSv.nonEmpty ?? project.fullNameEn)
            : (project.fullNameEn.nonEmpty ?? project.fullNameSv)

        var sections: [CVExportSection] = []
        if includedSections.contains(.summary) {
            sections.append(
                projectDocumentSummarySection(
                    project: project,
                    applications: relatedApplications,
                    publications: relatedPublications,
                    conferenceContributions: conferenceContributions,
                    meetings: meetings,
                    taskRecords: taskRecords,
                    protocolEntryCount: protocolEntries.count,
                    language: exportLanguage
                )
            )
        }
        if includedSections.contains(.statistics) {
            sections.append(
                projectDocumentStatisticsSection(
                    project: project,
                    applications: relatedApplications,
                    collaboratorNames: project.collaboratorNames,
                    language: exportLanguage
                )
            )
        }
        if includedSections.contains(.collaborators) {
            sections.append(projectDocumentCollaboratorSection(project.collaboratorNames, language: exportLanguage))
        }
        if includedSections.contains(.applications) {
            sections.append(projectDocumentApplicationSection(relatedApplications, language: exportLanguage))
        }
        if includedSections.contains(.publications) {
            sections.append(publicationCitationSection(relatedPublications, language: exportLanguage))
        }
        if includedSections.contains(.conferenceContributions) {
            sections.append(
                CVExportSection(
                    title: exportLanguage.text("Conference contributions", "Konferensbidrag"),
                    items: conferenceContributions.map { contribution in
                        [
                            contribution.localizedTitle(language: exportLanguage).nonEmpty ?? contribution.displayTitle,
                            contribution.localizedName(language: exportLanguage).nonEmpty,
                            (contribution.to.nonEmpty ?? contribution.from).nonEmpty,
                        ]
                        .compactMap { $0 }
                        .joined(separator: ". ")
                    }
                )
            )
        }
        if includedSections.contains(.calendar) {
            sections.append(
                projectDocumentCalendarSection(meetings, initialsByNameKey: initialsByNameKey, language: exportLanguage)
            )
        }
        if includedSections.contains(.tasks) {
            sections.append(
                projectDocumentTaskSection(taskRecords, initialsByNameKey: initialsByNameKey, language: exportLanguage)
            )
        }

        var filteredSections = sections.filter {
            !$0.rows.isEmpty || !$0.items.isEmpty || !$0.paragraphs.isEmpty || !$0.subsections.isEmpty
        }
        if includedSections.contains(.protocolEntries) {
            filteredSections.append(
                projectDocumentProtocolSection(protocolEntries, language: exportLanguage)
            )
        }

        return CVExportDocument(
            style: CVDocumentExportStyle.own.rawValue,
            exportLanguage: exportLanguage.rawValue,
            highlightName: currentUserAuthor()?.name.nonEmpty ?? "",
            title: project.displayName(for: exportLanguage),
            subtitle: fullName.nonEmpty ?? "",
            titleTrailingText: DateParsers.isoDay.string(from: Date()),
            summaryLines: [],
            sections: filteredSections,
            compactTables: true
        )
    }

    /// Every protocol entry linked to the project — the same aggregation the
    /// project document renders — for the inline protocol section in the
    /// project detail view. Oldest first.
    func projectProtocolEntryList(
        for project: ProjectRecord,
        language: AppLanguage
    ) -> [ProjectProtocolEntry] {
        let viewData = projectViewData(forProjectName: project.nameSv, language: language)
        let relatedApplications = viewData?.relatedApplications
            ?? applications.filter { $0.projectID?.trimmedOrNil == project.id }
        let relatedPublications = viewData?.relatedPublications
            ?? publicationRecords.filter { $0.projectID?.trimmedOrNil == project.id }
        let conferenceContributions = cvConferenceContributions.filter { contributionBelongs($0, to: project) }
        let meetings = calendarMeetingRecords
            .filter { calendarMeetingProjectIDs(for: $0, store: self).contains(project.id) }
            .sorted { ($0.date, $0.startTime, $0.title) < ($1.date, $1.startTime, $1.title) }
        let taskRecords = projectTaskWorkbookRecords(
            project: project,
            applications: relatedApplications,
            publications: relatedPublications,
            conferenceContributions: conferenceContributions,
            language: language
        )
        return projectProtocolEntries(
            meetings: meetings,
            taskRecords: taskRecords,
            language: language
        )
    }

    /// The grant twin of `projectSummaryDocument`: master data, funded
    /// publications, calendar events, tasks and protocol entries for one
    /// application.
    func applicationSummaryDocument(
        for application: GrantApplication,
        exportLanguage: AppLanguage,
        includedSections: Set<ApplicationDocumentSection> = Set(ApplicationDocumentSection.allCases)
    ) -> CVExportDocument {
        let meetings = calendarMeetingRecords
            .filter { $0.applicationIDs.compactMap(\.trimmedOrNil).contains(application.id) }
            .sorted { ($0.date, $0.startTime, $0.title) < ($1.date, $1.startTime, $1.title) }
        let taskRecords = documentTaskRecords(
            language: exportLanguage,
            matchesCentral: { task in
                task.links.contains { $0.kind == .application && $0.targetID == application.id }
            },
            matchesLegacy: { applicationID, _ in applicationID?.trimmedOrNil == application.id }
        )
        let protocolEntries = projectProtocolEntries(
            meetings: meetings,
            taskRecords: taskRecords,
            language: exportLanguage
        )
        let fundedPublications = publicationRecords.filter { publication in
            grantedApplications(for: publication).contains { $0.id == application.id }
        }
        let initialsByNameKey = projectCollaboratorInitials(application.coApplicants)
        let grantName = localizedGrantName(for: application, language: exportLanguage).nonEmpty
            ?? application.displayTitle

        var sections: [CVExportSection] = []
        if includedSections.contains(.summary) {
            let appliedSEK = application.appliedAmountValue.map {
                grantStatisticsAmountInSEK(for: application, amount: $0)
            }
            let grantedSEK = application.isGranted
                ? (application.grantedAmountValue ?? application.appliedAmountValue).map {
                    grantStatisticsAmountInSEK(for: application, amount: $0)
                }
                : nil
            let spentSEK: Double? = application.grantedAmountValue.map { grantedAmount in
                let remaining = effectiveRemainingGrantedAmountValue(for: application) ?? grantedAmount
                return grantStatisticsAmountInSEK(for: application, amount: max(0, grantedAmount - remaining))
            }
            var rows: [[String]] = []
            func appendRow(_ label: String, _ value: String?) {
                guard let value = value?.trimmedOrNil else { return }
                rows.append([label, value])
            }
            appendRow(exportLanguage.text("Funder", "Finansiär"), organizationLabel(for: application, language: exportLanguage))
            appendRow(exportLanguage.text("Status", "Status"), application.resultLabel.nonEmpty ?? "–")
            appendRow(
                exportLanguage.text("Project", "Projekt"),
                projects.first(where: { $0.id == application.projectID })?.displayName(for: exportLanguage)
            )
            if application.appliedOn?.trimmedOrNil != nil {
                appendRow(exportLanguage.text("Applied on", "Ansökt"), projectDocumentNonBreakingDate(application.appliedOn))
            }
            if projectDocumentApplicationDate(application).trimmedOrNil != nil {
                appendRow(exportLanguage.text("Decision", "Beslut"), projectDocumentNonBreakingDate(projectDocumentApplicationDate(application)))
            }
            appendRow(
                exportLanguage.text("Applied amount (SEK)", "Sökt belopp (SEK)"),
                appliedSEK.map { projectDocumentSEKText($0, language: exportLanguage) }
            )
            appendRow(
                exportLanguage.text("Granted amount (SEK)", "Beviljat belopp (SEK)"),
                grantedSEK.map { projectDocumentSEKText($0, language: exportLanguage) }
            )
            if application.isGranted, let spentSEK, spentSEK > 0 {
                appendRow(
                    exportLanguage.text("Spent of granted (SEK)", "Förbrukat av beviljat (SEK)"),
                    projectDocumentSEKText(spentSEK, language: exportLanguage)
                )
            }
            appendRow(
                exportLanguage.text("Co-applicants", "Medsökande"),
                application.coApplicants.compactMap(\.trimmedOrNil).joined(separator: ", ").nonEmpty
            )
            rows.append(contentsOf: [
                [exportLanguage.text("Publications", "Publikationer"), "\(fundedPublications.count)"],
                [exportLanguage.text("Calendar events", "Kalenderhändelser"), "\(meetings.count)"],
                [exportLanguage.text("Tasks", "Uppgifter"), "\(taskRecords.count)"],
                [exportLanguage.text("Protocol entries", "Protokollförda poster"), "\(protocolEntries.count)"],
            ])
            sections.append(
                CVExportSection(
                    title: exportLanguage.text("Summary", "Sammanfattning"),
                    headers: [exportLanguage.text("Field", "Fält"), exportLanguage.text("Value", "Värde")],
                    rows: rows
                )
            )
        }
        if includedSections.contains(.publications) {
            sections.append(publicationCitationSection(fundedPublications, language: exportLanguage))
        }
        if includedSections.contains(.calendar) {
            sections.append(
                projectDocumentCalendarSection(meetings, initialsByNameKey: initialsByNameKey, language: exportLanguage)
            )
        }
        if includedSections.contains(.tasks) {
            sections.append(
                projectDocumentTaskSection(taskRecords, initialsByNameKey: initialsByNameKey, language: exportLanguage)
            )
        }

        var filteredSections = sections.filter {
            !$0.rows.isEmpty || !$0.items.isEmpty || !$0.paragraphs.isEmpty || !$0.subsections.isEmpty
        }
        if includedSections.contains(.protocolEntries) {
            filteredSections.append(
                projectDocumentProtocolSection(protocolEntries, language: exportLanguage)
            )
        }

        return CVExportDocument(
            style: CVDocumentExportStyle.own.rawValue,
            exportLanguage: exportLanguage.rawValue,
            highlightName: currentUserAuthor()?.name.nonEmpty ?? "",
            title: grantName,
            subtitle: organizationLabel(for: application, language: exportLanguage).trimmedOrNil ?? "",
            titleTrailingText: DateParsers.isoDay.string(from: Date()),
            summaryLines: [],
            sections: filteredSections,
            compactTables: true
        )
    }

    /// The publication twin of `projectSummaryDocument`: master data, the AMA
    /// citation, funding grants, calendar events, tasks and protocol entries
    /// for one publication.
    func publicationSummaryDocument(
        for publication: PublicationRecord,
        exportLanguage: AppLanguage,
        includedSections: Set<PublicationDocumentSection> = Set(PublicationDocumentSection.allCases)
    ) -> CVExportDocument {
        let meetings = calendarMeetingRecords
            .filter { $0.publicationIDs.compactMap(\.trimmedOrNil).contains(publication.id) }
            .sorted { ($0.date, $0.startTime, $0.title) < ($1.date, $1.startTime, $1.title) }
        let taskRecords = documentTaskRecords(
            language: exportLanguage,
            matchesCentral: { task in
                task.links.contains { $0.kind == .publication && $0.targetID == publication.id }
            },
            matchesLegacy: { _, publicationID in publicationID?.trimmedOrNil == publication.id },
            ownPublicationID: publication.id
        )
        let protocolEntries = projectProtocolEntries(
            meetings: meetings,
            taskRecords: taskRecords,
            language: exportLanguage
        )
        let fundingApplications = grantedApplications(for: publication)
        let initialsByNameKey = projectCollaboratorInitials(publication.authorNames)

        var sections: [CVExportSection] = []
        if includedSections.contains(.summary) {
            var rows: [[String]] = []
            func appendRow(_ label: String, _ value: String?) {
                guard let value = value?.trimmedOrNil else { return }
                rows.append([label, value])
            }
            appendRow(exportLanguage.text("Journal", "Tidskrift"), publication.journal)
            appendRow(exportLanguage.text("Year", "År"), publication.year)
            appendRow(exportLanguage.text("Status", "Status"), publication.statusLabel)
            appendRow("DOI", publication.doi)
            appendRow(exportLanguage.text("Project", "Projekt"), projectLabel(for: publication, language: exportLanguage))
            appendRow(
                exportLanguage.text("Authors", "Författare"),
                publication.authorNames.compactMap(\.trimmedOrNil).joined(separator: ", ").nonEmpty
            )
            rows.append(contentsOf: [
                [exportLanguage.text("Funding grants", "Finansierande anslag"), "\(fundingApplications.count)"],
                [exportLanguage.text("Calendar events", "Kalenderhändelser"), "\(meetings.count)"],
                [exportLanguage.text("Tasks", "Uppgifter"), "\(taskRecords.count)"],
                [exportLanguage.text("Protocol entries", "Protokollförda poster"), "\(protocolEntries.count)"],
            ])
            sections.append(
                CVExportSection(
                    title: exportLanguage.text("Summary", "Sammanfattning"),
                    headers: [exportLanguage.text("Field", "Fält"), exportLanguage.text("Value", "Värde")],
                    rows: rows
                )
            )
        }
        if includedSections.contains(.reference) {
            sections.append(
                publicationCitationSection(
                    [publication],
                    title: exportLanguage.text("Reference", "Referens"),
                    language: exportLanguage
                )
            )
        }
        if includedSections.contains(.funding) {
            sections.append(
                projectDocumentApplicationSection(
                    fundingApplications,
                    title: exportLanguage.text("Funding", "Finansiering"),
                    language: exportLanguage
                )
            )
        }
        if includedSections.contains(.calendar) {
            sections.append(
                projectDocumentCalendarSection(meetings, initialsByNameKey: initialsByNameKey, language: exportLanguage)
            )
        }
        if includedSections.contains(.tasks) {
            sections.append(
                projectDocumentTaskSection(taskRecords, initialsByNameKey: initialsByNameKey, language: exportLanguage)
            )
        }

        var filteredSections = sections.filter {
            !$0.rows.isEmpty || !$0.items.isEmpty || !$0.paragraphs.isEmpty || !$0.subsections.isEmpty
        }
        if includedSections.contains(.protocolEntries) {
            filteredSections.append(
                projectDocumentProtocolSection(protocolEntries, language: exportLanguage)
            )
        }

        return CVExportDocument(
            style: CVDocumentExportStyle.own.rawValue,
            exportLanguage: exportLanguage.rawValue,
            highlightName: currentUserAuthor()?.name.nonEmpty ?? "",
            title: publication.title.nonEmpty ?? exportLanguage.text("Publication", "Publikation"),
            subtitle: [publication.journal.nonEmpty, publication.year.nonEmpty]
                .compactMap { $0 }
                .joined(separator: ", "),
            titleTrailingText: DateParsers.isoDay.string(from: Date()),
            summaryLines: [],
            sections: filteredSections,
            compactTables: true
        )
    }

    /// The standard CV citation format: numbered, all co-authors, italic
    /// journal, own name highlighted; newest first.
    private func publicationCitationSection(
        _ publications: [PublicationRecord],
        title: String? = nil,
        language: AppLanguage
    ) -> CVExportSection {
        var publicationOptions = PublicationExportOptions()
        publicationOptions.authorCountBeforeEtAl = 10_000
        let sortedPublications = publications.sorted {
            ($0.yearValue ?? 0) == ($1.yearValue ?? 0)
                ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                : ($0.yearValue ?? 0) > ($1.yearValue ?? 0)
        }
        let amaItems = numberedAMAItems(
            sortedPublications.map { amaCitationItem(for: $0, options: publicationOptions) }
        )
        return CVExportSection(
            title: title ?? language.text("Publications", "Publikationer"),
            layoutKind: "publicationList",
            subsections: amaItems.isEmpty ? [] : [CVExportSubsection(title: "", amaItems: amaItems)]
        )
    }

    /// The context column values for a central task: the display names of
    /// every linked record. Shared by the project workbook export and the
    /// record document builders.
    func documentTaskContexts(for task: TaskItem, language: AppLanguage) -> [String] {
        task.links.compactMap { link -> String? in
            switch link.kind {
            case .project:
                return projects.first(where: { $0.id == link.targetID })?.displayName(for: language)
            case .application:
                return application(id: link.targetID).map { localizedGrantName(for: $0, language: language) }
            case .publication:
                return publication(id: link.targetID)?.title
            case .organization:
                return organization(id: link.targetID).map { language == .swedish ? $0.nameSv : ($0.nameEn.nonEmpty ?? $0.nameSv) }
            case .doctoralCandidate:
                return doctoralCandidates.first(where: { $0.id == link.targetID }).map { $0.candidateName.nonEmpty ?? $0.doctoralProjectName }
            case .teachingAssignment:
                return teachingAssignments.first(where: { $0.id == link.targetID })?.activityName
            case .conferenceContribution:
                return cvConferenceContributions.first(where: { $0.id == link.targetID })?.localizedTitle(language: language)
            case .review:
                return cvReviewEntries.first(where: { $0.id == link.targetID })?.displayTitle
            case .congress, .teachingCourse:
                return nil
            }
        }
    }

    /// Task records linked to one application or publication, across the
    /// central task store and every legacy task array, deduplicated by id
    /// (central copies win, like `projectTaskWorkbookRecords`).
    private func documentTaskRecords(
        language: AppLanguage,
        matchesCentral: (TaskItem) -> Bool,
        matchesLegacy: (_ applicationID: String?, _ publicationID: String?) -> Bool,
        ownPublicationID: String? = nil
    ) -> [ProjectTaskWorkbookExportRecord] {
        var seenIDs = Set<String>()
        var records: [ProjectTaskWorkbookExportRecord] = []

        func append(
            source: String,
            context: String,
            id: String,
            projectTask: ProjectTaskItem? = nil,
            publicationTask: PublicationTaskItem? = nil,
            centralTask: TaskItem? = nil
        ) {
            guard seenIDs.insert(id).inserted else { return }
            records.append(
                ProjectTaskWorkbookExportRecord(
                    source: source,
                    context: context,
                    projectTask: projectTask,
                    publicationTask: publicationTask,
                    centralTask: centralTask
                )
            )
        }

        for task in taskItems where matchesCentral(task) {
            append(
                source: language.text("Central task", "Central uppgift"),
                context: documentTaskContexts(for: task, language: language)
                    .compactMap(\.trimmedOrNil)
                    .joined(separator: "; "),
                id: task.id,
                centralTask: task
            )
        }
        for project in projects {
            for task in project.projectTasks where !task.isEmpty && matchesLegacy(task.applicationID, task.publicationID) {
                append(source: language.text("Project", "Projekt"), context: project.displayName(for: language), id: task.id, projectTask: task)
            }
        }
        for publication in publicationRecords {
            for task in publication.publicationTasks where !task.isEmpty
                && (publication.id == ownPublicationID || matchesLegacy(task.applicationID, task.publicationID)) {
                append(source: language.text("Publication", "Publikation"), context: publication.title, id: task.id, publicationTask: task)
            }
        }
        for contribution in cvConferenceContributions {
            for task in contribution.tasks where !task.isEmpty && matchesLegacy(task.applicationID, task.publicationID) {
                append(
                    source: language.text("Conference contribution", "Konferensbidrag"),
                    context: contribution.localizedTitle(language: language),
                    id: task.id,
                    publicationTask: task
                )
            }
        }
        for organization in organizations {
            for task in organization.projectTasks where !task.isEmpty && matchesLegacy(task.applicationID, task.publicationID) {
                let organizationName = language == .swedish ? organization.nameSv : (organization.nameEn.nonEmpty ?? organization.nameSv)
                append(source: language.text("Organization", "Organisation"), context: organizationName, id: task.id, projectTask: task)
            }
        }
        for task in teachingWorkspaceTasks where !task.isEmpty && matchesLegacy(task.applicationID, task.publicationID) {
            append(source: language.text("Teaching", "Undervisning"), context: "", id: task.id, publicationTask: task)
        }

        return records.sorted {
            let lhsDeadline = $0.centralTask?.deadline ?? $0.projectTask?.deadline ?? $0.publicationTask?.deadline ?? ""
            let rhsDeadline = $1.centralTask?.deadline ?? $1.projectTask?.deadline ?? $1.publicationTask?.deadline ?? ""
            return lhsDeadline == rhsDeadline
                ? $0.source.localizedStandardCompare($1.source) == .orderedAscending
                : lhsDeadline.localizedStandardCompare(rhsDeadline) == .orderedAscending
        }
    }

    private func projectDocumentCollaboratorSection(
        _ collaboratorNames: [String],
        language: AppLanguage
    ) -> CVExportSection {
        let rows = collaboratorNames.compactMap(\.trimmedOrNil).map { presentedName -> [String] in
            let author = publicationAuthor(matchingPresentedName: presentedName)
            let affiliation = author?.primaryAffiliation.map { primary in
                [
                    primary.localizedDepartment(language: language).nonEmpty,
                    primary.localizedOrganization(language: language).nonEmpty,
                ]
                .compactMap { $0 }
                .joined(separator: ", ")
            }
            return [
                author?.displayName.nonEmpty ?? presentedName,
                affiliation?.nonEmpty ?? "–",
            ]
        }
        return CVExportSection(
            title: language.text("Collaborators", "Medarbetare"),
            headers: [
                language.text("Name", "Namn"),
                language.text("Affiliation", "Tillhörighet"),
            ],
            rows: rows
        )
    }

    private func projectDocumentSummarySection(
        project: ProjectRecord,
        applications: [GrantApplication],
        publications: [PublicationRecord],
        conferenceContributions: [CVConferenceContribution],
        meetings: [CalendarMeetingRecord],
        taskRecords: [ProjectTaskWorkbookExportRecord],
        protocolEntryCount: Int,
        language: AppLanguage
    ) -> CVExportSection {
        let grantedApplications = applications.filter(\.isGranted)
        let grantedSEK = grantedApplications.reduce(0.0) { total, application in
            total + grantStatisticsAmountInSEK(for: application, amount: application.grantedAmountValue)
        }
        var rows: [[String]] = [
            [language.text("Status", "Status"), localizedProjectStatus(project.projectStatus, language: language)],
            [language.text("Collaborators", "Medarbetare"), "\(project.collaboratorNames.compactMap(\.trimmedOrNil).count)"],
            [language.text("Applications", "Ansökningar"), "\(applications.count)"],
            [language.text("Granted applications", "Beviljade ansökningar"), "\(grantedApplications.count)"],
        ]
        let unconvertedGranted = unconvertedAmountText(for: grantedApplications.map { ($0, $0.grantedAmountValue) })
        if grantedSEK > 0 || !unconvertedGranted.isEmpty {
            let suffix = unconvertedGranted.isEmpty ? "" : " (\(unconvertedGranted))"
            rows.append([language.text("Granted amount (SEK)", "Beviljat belopp (SEK)"), projectDocumentSEKText(grantedSEK, language: language) + suffix])
        }
        rows.append(contentsOf: [
            [language.text("Publications", "Publikationer"), "\(publications.count)"],
            [language.text("Conference contributions", "Konferensbidrag"), "\(conferenceContributions.count)"],
            [language.text("Calendar events", "Kalenderhändelser"), "\(meetings.count)"],
            [language.text("Tasks", "Uppgifter"), "\(taskRecords.count)"],
            [language.text("Protocol entries", "Protokollförda poster"), "\(protocolEntryCount)"],
        ])
        return CVExportSection(
            title: language.text("Summary", "Sammanfattning"),
            headers: [language.text("Field", "Fält"), language.text("Value", "Värde")],
            rows: rows
        )
    }

    private func projectDocumentStatisticsSection(
        project: ProjectRecord,
        applications: [GrantApplication],
        collaboratorNames: [String],
        language: AppLanguage
    ) -> CVExportSection {
        var subsections: [CVExportSubsection] = []

        let totalApplications = applications.count
        if totalApplications > 0 {
            let granted = applications.filter(\.isGranted)
            let waiting = applications.filter { $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "Väntar svar" }
            let rejected = applications.filter { $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "Avslag" }
            let others = applications.filter { application in
                !application.isGranted
                    && !["Väntar svar", "Avslag"].contains(application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            func appliedSEK(_ source: [GrantApplication]) -> Double {
                source.reduce(0.0) { $0 + grantStatisticsAmountInSEK(for: $1, amount: $1.appliedAmountValue ?? $1.preferredBudgetAmountValue) }
            }
            let grantedSEK = granted.reduce(0.0) { $0 + grantStatisticsAmountInSEK(for: $1, amount: $1.grantedAmountValue ?? $1.appliedAmountValue) }
            let waitingSEK = appliedSEK(waiting)
            let rejectedSEK = appliedSEK(rejected)
            let otherSEK = appliedSEK(others)
            let totalSEK = grantedSEK + waitingSEK + rejectedSEK + otherSEK
            let spentSEK = granted.reduce(0.0) { partial, application in
                guard let grantedAmount = application.grantedAmountValue else { return partial }
                let remaining = effectiveRemainingGrantedAmountValue(for: application) ?? grantedAmount
                return partial + grantStatisticsAmountInSEK(for: application, amount: max(0, grantedAmount - remaining))
            }
            func fraction(_ count: Int) -> Double { Double(count) / Double(totalApplications) }
            func valueText(_ count: Int, _ amountSEK: Double) -> String {
                amountSEK > 0
                    ? "\(count) · \(projectDocumentSEKText(amountSEK, language: language)) kr"
                    : "\(count)"
            }
            var bars: [CVExportStatisticBar] = [
                CVExportStatisticBar(
                    label: language.text("Granted", "Beviljade"),
                    valueText: valueText(granted.count, grantedSEK),
                    fraction: fraction(granted.count),
                    colorHex: "16A34A"
                ),
            ]
            if grantedSEK > 0 {
                bars.append(
                    CVExportStatisticBar(
                        label: language.text("Spent of granted", "Förbrukat av beviljat"),
                        valueText: "\(projectDocumentSEKText(spentSEK, language: language)) kr",
                        fraction: min(1, spentSEK / grantedSEK),
                        colorHex: "15803D"
                    )
                )
            }
            bars.append(contentsOf: [
                CVExportStatisticBar(
                    label: language.text("Pending decision", "Väntar beslut"),
                    valueText: valueText(waiting.count, waitingSEK),
                    fraction: fraction(waiting.count),
                    colorHex: "D97706"
                ),
                CVExportStatisticBar(
                    label: language.text("Declined", "Avslag"),
                    valueText: valueText(rejected.count, rejectedSEK),
                    fraction: fraction(rejected.count),
                    colorHex: "DC2626"
                ),
            ])
            if !others.isEmpty {
                bars.append(
                    CVExportStatisticBar(
                        label: language.text("Other", "Övriga"),
                        valueText: valueText(others.count, otherSEK),
                        fraction: fraction(others.count),
                        colorHex: "6B7280"
                    )
                )
            }
            bars.append(
                CVExportStatisticBar(
                    label: language.text("Total", "Totalt"),
                    valueText: valueText(totalApplications, totalSEK),
                    fraction: 1,
                    colorHex: "374151"
                )
            )
            subsections.append(
                CVExportSubsection(title: language.text("Grant outcome", "Anslagsutfall"), bars: bars)
            )
        }

        let trimmedCollaborators = collaboratorNames.compactMap(\.trimmedOrNil)
        if !trimmedCollaborators.isEmpty {
            let resolved = trimmedCollaborators.compactMap { publicationAuthor(matchingPresentedName: $0) }
            let women = resolved.filter { $0.gender == .female }.count
            let men = resolved.filter { $0.gender == .male }.count
            let unspecified = trimmedCollaborators.count - women - men
            let withPhD = resolved.filter(\.hasPhD).count
            func fraction(_ count: Int) -> Double { Double(count) / Double(trimmedCollaborators.count) }
            var bars: [CVExportStatisticBar] = []
            if women > 0 {
                bars.append(CVExportStatisticBar(label: language.text("Women", "Kvinnor"), valueText: "\(women)", fraction: fraction(women), colorHex: "7C3AED"))
            }
            if men > 0 {
                bars.append(CVExportStatisticBar(label: language.text("Men", "Män"), valueText: "\(men)", fraction: fraction(men), colorHex: "2563EB"))
            }
            if unspecified > 0 {
                bars.append(CVExportStatisticBar(label: language.text("Unspecified", "Ospecificerat"), valueText: "\(unspecified)", fraction: fraction(unspecified), colorHex: "9CA3AF"))
            }
            bars.append(CVExportStatisticBar(label: language.text("With PhD", "Disputerade"), valueText: "\(withPhD)", fraction: fraction(withPhD), colorHex: "0D9488"))
            subsections.append(
                CVExportSubsection(title: language.text("Contributor composition", "Medarbetarsammansättning"), bars: bars)
            )
        }

        let summary = calendarMeetingHoursSummary(store: self, scope: .project(project.id))
        let totalMeetings = summary.completedMeetingCount + summary.plannedMeetingCount
        if totalMeetings > 0 {
            func hoursText(_ minutes: Int) -> String {
                projectDocumentHoursText(Double(minutes) / 60, language: language)
            }
            subsections.append(
                CVExportSubsection(
                    title: language.text("Activities", "Aktiviteter"),
                    bars: [
                        CVExportStatisticBar(
                            label: language.text("Completed", "Genomförda"),
                            valueText: "\(summary.completedMeetingCount) · \(hoursText(summary.completedMinutes))",
                            fraction: Double(summary.completedMeetingCount) / Double(totalMeetings),
                            colorHex: "2563EB"
                        ),
                        CVExportStatisticBar(
                            label: language.text("Planned", "Planerade"),
                            valueText: "\(summary.plannedMeetingCount) · \(hoursText(summary.plannedMinutes))",
                            fraction: Double(summary.plannedMeetingCount) / Double(totalMeetings),
                            colorHex: "93C5FD"
                        ),
                    ]
                )
            )

            let totalModeMinutes = summary.meetingModeMinutes.values.reduce(0, +)
            if totalModeMinutes > 0 {
                let modeBars = summary.meetingModeMinutes
                    .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                    .map { key, minutes in
                        CVExportStatisticBar(
                            label: CalendarMeetingMode(rawValue: key)?.localizedName(language: language)
                                ?? (key.nonEmpty ?? language.text("Unspecified", "Ospecificerat")),
                            valueText: hoursText(minutes),
                            fraction: Double(minutes) / Double(totalModeMinutes),
                            colorHex: "0EA5E9"
                        )
                    }
                subsections.append(
                    CVExportSubsection(title: language.text("Time per meeting format", "Tid per mötesform"), bars: modeBars)
                )
            }

            let totalActivityMinutes = summary.activityMinutes.values.reduce(0, +)
            if totalActivityMinutes > 0 {
                let activityBars = summary.activityMinutes
                    .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                    .prefix(6)
                    .map { key, minutes in
                        CVExportStatisticBar(
                            label: key.nonEmpty ?? language.text("Unspecified", "Ospecificerat"),
                            valueText: hoursText(minutes),
                            fraction: Double(minutes) / Double(totalActivityMinutes),
                            colorHex: "6366F1"
                        )
                    }
                subsections.append(
                    CVExportSubsection(title: language.text("Time per activity type", "Tid per aktivitetstyp"), bars: Array(activityBars))
                )
            }
        }

        return CVExportSection(
            title: language.text("Statistics", "Statistik"),
            subsections: subsections
        )
    }

    private func projectDocumentApplicationSection(
        _ applications: [GrantApplication],
        title: String? = nil,
        language: AppLanguage
    ) -> CVExportSection {
        let rows = applications
            .sorted { projectDocumentApplicationDate($0) < projectDocumentApplicationDate($1) }
            .map { application -> [String] in
                let amountValue = application.isGranted
                    ? (application.grantedAmountValue ?? application.appliedAmountValue)
                    : application.appliedAmountValue
                let amountSEK = amountValue.map { grantStatisticsAmountInSEK(for: application, amount: $0) }
                let grantName = application.localizedGrantName(language: language).nonEmpty ?? application.displayTitle
                let funder = organizationLabel(for: application, language: language).trimmedOrNil
                let grantCell = funder.map { "\(grantName)\n\($0)" } ?? grantName
                let status = (application.resultLabel.nonEmpty ?? "–")
                    .replacingOccurrences(of: " ", with: "\u{00A0}")
                return [
                    projectDocumentNonBreakingDate(projectDocumentApplicationDate(application)),
                    grantCell,
                    status,
                    amountSEK.map { projectDocumentSEKText($0, language: language) } ?? "–",
                ]
            }
        return CVExportSection(
            title: title ?? language.text("Applications", "Ansökningar"),
            headers: [
                language.text("Date", "Datum"),
                language.text("Grant", "Anslag"),
                language.text("Status", "Status"),
                language.text("Amount (SEK)", "Belopp (SEK)"),
            ],
            rows: rows
        )
    }

    private func projectDocumentCalendarSection(
        _ meetings: [CalendarMeetingRecord],
        initialsByNameKey: [String: String],
        language: AppLanguage
    ) -> CVExportSection {
        let rows = meetings.map { meeting -> [String] in
            let time = [meeting.startTime.nonEmpty, meeting.endTime.nonEmpty]
                .compactMap { $0 }
                .joined(separator: "\u{2011}")
            return [
                projectDocumentNonBreakingDate(meeting.date),
                time.nonEmpty ?? "–",
                meeting.title.nonEmpty ?? meeting.meetingType.nonEmpty ?? "–",
                meeting.meetingType.nonEmpty ?? "–",
                projectDocumentParticipantText(meeting.participantNames, initialsByNameKey: initialsByNameKey),
            ]
        }
        return CVExportSection(
            title: language.text("Calendar events", "Kalenderhändelser"),
            headers: [
                language.text("Date", "Datum"),
                language.text("Time", "Tid"),
                language.text("Activity", "Aktivitet"),
                language.text("Type", "Typ"),
                language.text("Participants", "Deltagare"),
            ],
            rows: rows
        )
    }

    private func projectDocumentTaskSection(
        _ taskRecords: [ProjectTaskWorkbookExportRecord],
        initialsByNameKey: [String: String],
        language: AppLanguage
    ) -> CVExportSection {
        let rows = taskRecords.map { record -> [String] in
            let comment = record.centralTask?.comment ?? record.projectTask?.comment ?? record.publicationTask?.comment ?? ""
            let completedOn = record.centralTask?.completedOn ?? record.projectTask?.completedOn ?? record.publicationTask?.completedOn
            let deadline = record.centralTask?.deadline ?? record.projectTask?.deadline ?? record.publicationTask?.deadline ?? ""
            let participants = record.centralTask?.participantNames ?? record.projectTask?.participantNames ?? record.publicationTask?.participantNames ?? []
            return [
                comment.nonEmpty ?? "–",
                completedOn?.trimmedOrNil == nil ? language.text("Active", "Aktiv") : language.text("Completed", "Slutförd"),
                projectDocumentNonBreakingDate(deadline),
                projectDocumentNonBreakingDate(completedOn),
                projectDocumentParticipantText(participants, initialsByNameKey: initialsByNameKey),
            ]
        }
        return CVExportSection(
            title: language.text("Tasks", "Uppgifter"),
            headers: [
                language.text("Task", "Uppgift"),
                language.text("Status", "Status"),
                language.text("Deadline", "Tidsfrist"),
                language.text("Completed", "Genomförd"),
                language.text("Participants", "Deltagare"),
            ],
            rows: rows
        )
    }

    private func projectDocumentProtocolSection(
        _ entries: [ProjectProtocolEntry],
        language: AppLanguage
    ) -> CVExportSection {
        guard !entries.isEmpty else {
            return CVExportSection(
                title: language.text("Protocol", "Protokoll"),
                layoutKind: "protocol",
                paragraphs: [
                    language.text(
                        "No linked events or tasks have a protocol yet.",
                        "Inga kopplade händelser eller uppgifter har något protokoll ännu."
                    )
                ]
            )
        }
        let subsections = entries.map { entry -> CVExportSubsection in
            var richParagraphs: [CVExportRichTextParagraph] = []
            if !entry.participantNames.isEmpty {
                richParagraphs.append(
                    CVExportRichTextParagraph(runs: [
                        CVExportRichTextRun(text: "\(language.text("Participants", "Deltagare")): ", bold: true),
                        CVExportRichTextRun(text: entry.participantNames.joined(separator: ", ")),
                    ])
                )
            }
            richParagraphs.append(
                contentsOf: entry.linkedRecordLines.map {
                    CVExportRichTextParagraph(runs: [CVExportRichTextRun(text: $0)])
                }
            )
            richParagraphs.append(contentsOf: ProtocolMarkup.exportParagraphs(from: entry.protocolText))
            return CVExportSubsection(
                title: [entry.dateText.nonEmpty, entry.title.nonEmpty].compactMap { $0 }.joined(separator: " – "),
                richParagraphs: richParagraphs
            )
        }
        return CVExportSection(
            title: language.text("Protocol", "Protokoll"),
            layoutKind: "protocol",
            subsections: subsections
        )
    }

    private func projectProtocolEntries(
        meetings: [CalendarMeetingRecord],
        taskRecords: [ProjectTaskWorkbookExportRecord],
        language: AppLanguage
    ) -> [ProjectProtocolEntry] {
        var entries: [ProjectProtocolEntry] = []

        for meeting in meetings where meeting.protocolText.trimmedOrNil != nil {
            entries.append(
                ProjectProtocolEntry(
                    sortKey: meeting.date.trimmedOrNil ?? "9999-99-99",
                    dateText: meeting.date.trimmedOrNil ?? language.text("No date", "Datum saknas"),
                    title: meeting.title.nonEmpty
                        ?? meeting.meetingType.nonEmpty
                        ?? language.text("Activity", "Aktivitet"),
                    participantNames: meeting.participantNames.compactMap(\.trimmedOrNil),
                    linkedRecordLines: projectDocumentMeetingLinkedLines(meeting, language: language),
                    protocolText: meeting.protocolText,
                    source: .meeting(meeting.id)
                )
            )
        }

        for record in taskRecords {
            let protocolText = record.centralTask?.protocolText
                ?? record.projectTask?.protocolText
                ?? record.publicationTask?.protocolText
                ?? ""
            guard protocolText.trimmedOrNil != nil else { continue }
            let completedOn = record.centralTask?.completedOn ?? record.projectTask?.completedOn ?? record.publicationTask?.completedOn
            let deadline = record.centralTask?.deadline ?? record.projectTask?.deadline ?? record.publicationTask?.deadline ?? ""
            let date = completedOn?.trimmedOrNil ?? deadline.trimmedOrNil
            let comment = record.centralTask?.comment ?? record.projectTask?.comment ?? record.publicationTask?.comment ?? ""
            let participants = record.centralTask?.participantNames ?? record.projectTask?.participantNames ?? record.publicationTask?.participantNames ?? []
            let source: ProjectProtocolEntry.Source
            if let centralTask = record.centralTask {
                source = .centralTask(centralTask.id)
            } else if let projectTask = record.projectTask {
                source = .projectTask(projectTask.id)
            } else if let publicationTask = record.publicationTask {
                source = .publicationTask(publicationTask.id)
            } else {
                continue
            }
            entries.append(
                ProjectProtocolEntry(
                    sortKey: date ?? "9999-99-99",
                    dateText: date ?? language.text("No date", "Datum saknas"),
                    title: comment.nonEmpty ?? language.text("Task", "Uppgift"),
                    participantNames: participants.compactMap(\.trimmedOrNil),
                    linkedRecordLines: projectDocumentTaskLinkedLines(record, language: language),
                    protocolText: protocolText,
                    source: source
                )
            )
        }

        return entries.sorted {
            $0.sortKey == $1.sortKey
                ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                : $0.sortKey < $1.sortKey
        }
    }

    private func projectDocumentMeetingLinkedLines(
        _ meeting: CalendarMeetingRecord,
        language: AppLanguage
    ) -> [String] {
        var lines: [String] = []
        func appendLine(_ label: String, _ names: [String]) {
            let values = names.compactMap(\.trimmedOrNil)
            guard !values.isEmpty else { return }
            lines.append("\(label): \(values.joined(separator: ", "))")
        }
        appendLine(
            language.text("Organizations", "Organisationer"),
            meeting.organizationIDs.compactMap { organization(id: $0)?.displayName(for: language) }
        )
        appendLine(
            language.text("Grants", "Anslag"),
            meeting.applicationIDs.compactMap { application(id: $0).map { localizedGrantName(for: $0, language: language) } }
        )
        appendLine(
            language.text("Publications", "Publikationer"),
            meeting.publicationIDs.compactMap { publication(id: $0)?.title }
        )
        appendLine(
            language.text("Teaching assignments", "Undervisningsuppdrag"),
            meeting.teachingAssignmentIDs.compactMap { id in
                teachingAssignments.first(where: { $0.id == id })?.activityName
            }
        )
        appendLine(
            language.text("Doctoral candidates", "Doktorander"),
            meeting.doctoralCandidateIDs.compactMap { id in
                doctoralCandidates.first(where: { $0.id == id }).map { $0.candidateName.nonEmpty ?? $0.doctoralProjectName }
            }
        )
        appendLine(
            language.text("Media appearances", "Medieframträdanden"),
            meeting.mediaAppearanceIDs.compactMap { id in
                cvMediaAppearances.first(where: { $0.id == id })?.localizedTitle(language: language)
            }
        )
        return lines
    }

    private func projectDocumentTaskLinkedLines(
        _ record: ProjectTaskWorkbookExportRecord,
        language: AppLanguage
    ) -> [String] {
        var namesByLabel: [(label: String, names: [String])] = [
            (language.text("Grants", "Anslag"), []),
            (language.text("Publications", "Publikationer"), []),
            (language.text("Organizations", "Organisationer"), []),
        ]
        func appendName(_ name: String?, at index: Int) {
            guard let name = name?.trimmedOrNil else { return }
            namesByLabel[index].names.append(name)
        }

        if let centralTask = record.centralTask {
            for link in centralTask.links {
                switch link.kind {
                case .application:
                    appendName(application(id: link.targetID).map { localizedGrantName(for: $0, language: language) }, at: 0)
                case .publication:
                    appendName(publication(id: link.targetID)?.title, at: 1)
                case .organization:
                    appendName(organization(id: link.targetID)?.displayName(for: language), at: 2)
                default:
                    break
                }
            }
        } else {
            let applicationID = record.projectTask?.applicationID ?? record.publicationTask?.applicationID
            let publicationID = record.projectTask?.publicationID ?? record.publicationTask?.publicationID
            appendName(application(id: applicationID).map { localizedGrantName(for: $0, language: language) }, at: 0)
            appendName(publication(id: publicationID)?.title, at: 1)
        }

        return namesByLabel.compactMap { entry in
            entry.names.isEmpty ? nil : "\(entry.label): \(entry.names.joined(separator: ", "))"
        }
    }

    /// Unique initials for every project collaborator, keyed by every
    /// normalized presented-name variant. Starts with one letter of the first
    /// and last name each ("MS"); on collisions the first name is extended
    /// letter by letter, then the last name, until all initials differ
    /// ("PaG" vs "PeG").
    private func projectCollaboratorInitials(_ collaboratorNames: [String]) -> [String: String] {
        struct Person {
            let keys: Set<String>
            let firstName: String
            let lastName: String
        }
        let persons: [Person] = collaboratorNames.compactMap(\.trimmedOrNil).map { presentedName in
            let author = publicationAuthor(matchingPresentedName: presentedName)
            let parsed = parseName(author?.displayName.nonEmpty ?? presentedName)
            var keys: Set<String> = [normalizedPersonLookupName(presentedName)]
            if let author {
                for candidate in author.presentedNameCandidates {
                    keys.insert(normalizedPersonLookupName(candidate))
                }
            }
            keys.remove("")
            return Person(
                keys: keys,
                firstName: author?.firstName.nonEmpty ?? parsed.firstName,
                lastName: author?.lastName.nonEmpty ?? parsed.lastName
            )
        }
        guard !persons.isEmpty else { return [:] }

        var firstLengths = Array(repeating: 1, count: persons.count)
        var lastLengths = Array(repeating: 1, count: persons.count)
        func initials(at index: Int) -> String {
            String(persons[index].firstName.prefix(firstLengths[index]))
                + String(persons[index].lastName.prefix(lastLengths[index]))
        }

        var iteration = 0
        while iteration < 12 {
            iteration += 1
            let groups = Dictionary(grouping: persons.indices) { initials(at: $0).lowercased() }
            var extendedAny = false
            for indices in groups.values where indices.count > 1 {
                for index in indices {
                    if firstLengths[index] < persons[index].firstName.count {
                        firstLengths[index] += 1
                        extendedAny = true
                    } else if lastLengths[index] < persons[index].lastName.count {
                        lastLengths[index] += 1
                        extendedAny = true
                    }
                }
            }
            if !extendedAny { break }
        }

        var map: [String: String] = [:]
        for index in persons.indices {
            let value = initials(at: index)
            guard !value.isEmpty else { continue }
            for key in persons[index].keys {
                map[key] = value
            }
        }
        return map
    }

    /// Collaborators show as their unique initials; everyone else keeps
    /// their full name.
    private func projectDocumentParticipantText(
        _ participantNames: [String],
        initialsByNameKey: [String: String]
    ) -> String {
        let names = participantNames.compactMap(\.trimmedOrNil).map { name in
            initialsByNameKey[normalizedPersonLookupName(name)] ?? name
        }
        return names.joined(separator: ", ").nonEmpty ?? "–"
    }

    /// ISO dates with non-breaking hyphens (U+2011) never wrap inside a
    /// table column — both WebKit and Word then widen the column instead.
    private func projectDocumentNonBreakingDate(_ value: String?) -> String {
        guard let value = value?.trimmedOrNil else { return "–" }
        return value.replacingOccurrences(of: "-", with: "\u{2011}")
    }

    private func projectDocumentApplicationDate(_ application: GrantApplication) -> String {
        application.resolvedDecisionDateString.nonEmpty
            ?? application.grantedOn.nonEmpty
            ?? application.deniedOn.nonEmpty
            ?? application.appliedOn.nonEmpty
            ?? application.closesOn.nonEmpty
            ?? ""
    }

    private func projectDocumentSEKText(_ value: Double, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: language == .swedish ? "sv_SE" : "en_US")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value.rounded()))"
    }

    private func projectDocumentHoursText(_ value: Double, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: language == .swedish ? "sv_SE" : "en_US")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 1
        let text = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(text) h"
    }
}
