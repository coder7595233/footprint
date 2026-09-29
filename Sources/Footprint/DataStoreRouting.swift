import Foundation

extension GrantDataStore {
    func revealCalendarWorkspace() {
        pendingCalendarOpenRequest = nil
        pendingCalendarRevealRequest = nil
        pendingCalendarRevealToken = UUID()
    }

    func revealCalendarWorkspace(on date: Date, eventSource: CalendarWorkspaceEventSource? = nil) {
        pendingCalendarOpenRequest = nil
        pendingCalendarRevealRequest = CalendarRevealRequest(
            dayString: DateParsers.isoDay.string(from: date),
            eventSource: eventSource
        )
        pendingCalendarRevealToken = UUID()
    }

    func openCalendarLinkedEvent(source: CalendarWorkspaceEventSource) {
        switch source {
        case let .meeting(meetingID):
            if let date = calendarMeetingRecords.first(where: { $0.id == meetingID })?.date,
               let parsedDate = DateParsers.isoDay.date(from: date) {
                revealCalendarWorkspace(on: parsedDate, eventSource: source)
            }
        case let .mediaAppearance(appearanceID):
            if let date = cvMediaAppearances.first(where: { $0.id == appearanceID })?.date,
               let parsedDate = DateParsers.isoDay.date(from: date) {
                revealCalendarWorkspace(on: parsedDate, eventSource: source)
            }
        case let .travel(travelID):
            if let date = calendarTravelRecords.first(where: { $0.id == travelID })?.date,
               let parsedDate = DateParsers.isoDay.date(from: date) {
                revealCalendarWorkspace(on: parsedDate, eventSource: source)
            }
        case let .accommodation(accommodationID):
            if let date = calendarAccommodationRecords.first(where: { $0.id == accommodationID })?.checkInDate,
               let parsedDate = DateParsers.isoDay.date(from: date) {
                revealCalendarWorkspace(on: parsedDate, eventSource: source)
            }
        case let .projectTask(projectID, taskID):
            pendingCalendarOpenRequest = CalendarOpenRequest(
                kind: .projectTask(projectID: projectID),
                recordID: taskID
            )
        case let .publicationTask(publicationID, taskID):
            pendingCalendarOpenRequest = CalendarOpenRequest(
                kind: .publicationTask(publicationID: publicationID),
                recordID: taskID
            )
        case let .teachingTask(taskID):
            pendingCalendarOpenRequest = CalendarOpenRequest(
                kind: .todo,
                recordID: taskID
            )
        case let .reviewDeadline(reviewID):
            guard let review = cvReviewEntries.first(where: { $0.id == reviewID }) else { return }
            openRoute(for: review)
        case let .application(applicationID):
            guard let application = application(id: applicationID) else { return }
            openRoute(for: application)
        case let .organizationTask(organizationID, _):
            guard let organization = organization(id: organizationID) else { return }
            openRoute(for: organization)
        case let .congress(organizationID, congressID):
            openRouteToCongress(organizationID: organizationID, congressID: congressID)
        case .holiday:
            break
        }
    }

    /// Opens the editor holding a protocol entry's text (calendar activity or
    /// task sheet) — used by the inline Protokoll sections' clickable dates.
    func openProtocolEntryEditor(_ source: ProjectProtocolEntry.Source) {
        switch source {
        case let .meeting(meetingID):
            pendingCalendarOpenRequest = CalendarOpenRequest(kind: .meeting, recordID: meetingID)
        case let .centralTask(taskID):
            pendingCalendarOpenRequest = CalendarOpenRequest(kind: .todo, recordID: taskID)
        case let .projectTask(taskID):
            guard let project = projects.first(where: { project in
                project.projectTasks.contains { $0.id == taskID }
            }) else { return }
            pendingCalendarOpenRequest = CalendarOpenRequest(
                kind: .projectTask(projectID: project.id),
                recordID: taskID
            )
        case let .publicationTask(taskID):
            guard let publication = publicationRecords.first(where: { publication in
                publication.publicationTasks.contains { $0.id == taskID }
            }) else { return }
            pendingCalendarOpenRequest = CalendarOpenRequest(
                kind: .publicationTask(publicationID: publication.id),
                recordID: taskID
            )
        }
    }

    func consumeCalendarOpenRequest() {
        pendingCalendarOpenRequest = nil
    }

    func consumeCalendarRevealRequest() {
        pendingCalendarRevealRequest = nil
    }

    func openRoute(for application: GrantApplication) {
        route = AppRoute(
            recordID: applicationSelectionID(for: application),
            destination: .applications
        )
    }

    func openRoute(for author: PublicationAuthor) {
        route = AppRoute(
            recordID: author.id,
            destination: .people
        )
    }

    func openRoute(for organization: OrganizationRecord) {
        let resolvedOrganization =
            organizations.first(where: { $0.id == organization.id }) ??
            self.organization(matchingName: organization.nameSv) ??
            self.organization(matchingName: organization.nameEn)

        route = AppRoute(
            recordID: resolvedOrganization?.id ?? organization.id,
            destination: .organizations
        )
    }

    func openRouteToCongress(organizationID: String, congressID: String) {
        guard let organization = organizations.first(where: { $0.id == organizationID }),
              organization.congresses.contains(where: { $0.id == congressID }) else { return }
        let targetRoute = AppRoute(
            recordID: "organizationCongress:\(organizationID):\(congressID)",
            destination: .congresses
        )
        pendingCongressRoute = targetRoute
        pendingCongressRouteToken = UUID()
        // AppRoute has a fresh request identity for every navigation.  Do not
        // clear and replay asynchronously: a delayed replay can overwrite a
        // newer click and open the wrong congress.
        route = targetRoute
    }

    func consumePendingCongressRoute(_ consumedRoute: AppRoute) {
        guard pendingCongressRoute?.requestID == consumedRoute.requestID else { return }
        pendingCongressRoute = nil
    }

    func openRoute(for manager: ManagerOption) {
        // "Alla kopplingar via id": the organization with the manager's id
        // first; the name only when no organization has that id.
        guard let organization = organizations.first(where: { $0.id == manager.id })
            ?? organizations.first(where: { $0.nameSv == manager.nameSv }) else { return }
        route = AppRoute(recordID: organization.id, destination: .organizations)
    }

    func openRoute(for journal: PublicationJournal) {
        route = AppRoute(
            recordID: journal.id,
            destination: .journals
        )
    }

    func openRoute(for project: ProjectRecord) {
        let resolvedProject =
            projects.first(where: { $0.id == project.id }) ??
            self.project(named: project.nameSv) ??
            self.project(named: project.nameEn)

        route = AppRoute(
            recordID: resolvedProject?.id ?? project.id,
            destination: .projects
        )
    }

    func openRoute(for publication: PublicationRecord) {
        route = AppRoute(
            recordID: publication.id,
            destination: .publications
        )
    }

    func openRoute(for conferenceContribution: CVConferenceContribution) {
        route = AppRoute(
            recordID: "conferenceContribution:\(conferenceContribution.id)",
            destination: .cv
        )
    }

    func openRoute(for reviewEntry: CVReviewEntry) {
        route = AppRoute(
            recordID: "review:\(reviewEntry.id)",
            destination: .expertAssignments
        )
    }

    func openRoute(for mediaAppearance: CVMediaAppearance) {
        route = AppRoute(
            recordID: "mediaAppearance:\(mediaAppearance.id)",
            destination: .cv
        )
    }

    func openRoute(for assignment: TeachingAssignment) {
        route = AppRoute(
            recordID: assignment.id,
            destination: .teaching
        )
    }

    func openRoute(for candidate: DoctoralCandidateRecord) {
        route = AppRoute(
            recordID: candidate.id,
            destination: .doctoralCandidates
        )
    }

    func consumeRoute() {
        route = nil
    }

    func openIssue(destination: AppRoute.Destination, recordID: String) {
        route = AppRoute(recordID: recordID, destination: destination)
    }

    func handlePendingSelectionReturnIfNeeded(for recordID: String?, in destination: AppRoute.Destination) {
        guard let pending = pendingSelectionReturn else { return }
        guard pendingSelectionMatchesWorkspace(pending, destination: destination) else { return }
        guard let recordID else {
            pendingSelectionReturn = nil
            return
        }
        if pending.entityID == recordID {
            return
        }
        if finalizePendingSelectionIfPossible(for: pending, selectedRecordID: recordID) {
            return
        }
        if pendingSelectionSourceRecordID(for: pending) != recordID {
            pendingSelectionReturn = nil
        }
    }

    private func pendingSelectionSourceRecordID(for pending: PendingSelectionReturn) -> String {
        switch pending.destination {
        case let .application(recordID, _):
            return recordID
        case let .publication(recordID, _):
            return recordID
        case let .project(recordID, _):
            return recordID
        }
    }

    private func pendingSelectionMatchesWorkspace(
        _ pending: PendingSelectionReturn,
        destination: AppRoute.Destination
    ) -> Bool {
        switch destination {
        case .applications:
            if case .application = pending.destination {
                return true
            }
            return false
        case .publications:
            if case .publication = pending.destination {
                return true
            }
            return false
        case .organizations:
            return pending.entityKind == .organization || pending.entityKind == .manager
        case .projects:
            if case .project = pending.destination {
                return true
            }
            return pending.entityKind == .project
        case .people:
            return pending.entityKind == .author
        case .journals:
            return pending.entityKind == .journal
        case .congresses, .cv, .expertAssignments, .teaching, .doctoralCandidates:
            return false
        }
    }

    private func finalizePendingSelectionIfPossible(
        for pending: PendingSelectionReturn,
        selectedRecordID: String
    ) -> Bool {
        switch pending.entityKind {
        case .organization:
            guard organizations.contains(where: { $0.id == selectedRecordID }) else { return false }
            finalizePendingOrganizationSelection(id: selectedRecordID)
            return true
        case .project:
            guard projects.contains(where: { $0.id == selectedRecordID }) else { return false }
            finalizePendingProjectSelection(id: selectedRecordID)
            return true
        case .manager:
            guard organizations.contains(where: { $0.id == selectedRecordID })
                || managers.contains(where: { $0.id == selectedRecordID })
            else {
                return false
            }
            finalizePendingManagerSelection(id: selectedRecordID)
            return true
        case .author:
            guard publicationAuthors.contains(where: { $0.id == selectedRecordID }) else { return false }
            finalizePendingAuthorSelection(id: selectedRecordID)
            return true
        case .journal:
            guard publicationJournals.contains(where: { $0.id == selectedRecordID }) else { return false }
            finalizePendingJournalSelection(id: selectedRecordID)
            return true
        }
    }

    func beginAddingOrganization(fromApplicationID applicationID: String) {
        let newID = addOrganization()
        pendingSelectionReturn = PendingSelectionReturn(
            entityKind: .organization,
            entityID: newID,
            destination: .application(recordID: applicationID, field: .organization)
        )
        route = AppRoute(recordID: newID, destination: .organizations)
    }

    func beginAddingProject(fromApplicationID applicationID: String) {
        let newID = addProject()
        pendingSelectionReturn = PendingSelectionReturn(
            entityKind: .project,
            entityID: newID,
            destination: .application(recordID: applicationID, field: .project)
        )
        route = AppRoute(recordID: newID, destination: .projects)
    }

    func beginAddingProject(fromPublicationID publicationID: String) {
        let newID = addProject()
        pendingSelectionReturn = PendingSelectionReturn(
            entityKind: .project,
            entityID: newID,
            destination: .publication(recordID: publicationID, field: .project)
        )
        route = AppRoute(recordID: newID, destination: .projects)
    }

    func beginAddingManager(fromApplicationID applicationID: String) {
        let newID = addManager()
        pendingSelectionReturn = PendingSelectionReturn(
            entityKind: .manager,
            entityID: newID,
            destination: .application(recordID: applicationID, field: .manager)
        )
        route = AppRoute(recordID: newID, destination: .organizations)
    }

    func beginAddingApplicant(fromApplicationID applicationID: String, at index: Int) {
        let newID = addPublicationAuthor()
        pendingSelectionReturn = PendingSelectionReturn(
            entityKind: .author,
            entityID: newID,
            destination: .application(recordID: applicationID, field: .coApplicant(index: index))
        )
        route = AppRoute(recordID: newID, destination: .people)
    }

    func beginAddingPublicationAuthor(fromPublicationID publicationID: String, at index: Int) {
        let newID = addPublicationAuthor()
        pendingSelectionReturn = PendingSelectionReturn(
            entityKind: .author,
            entityID: newID,
            destination: .publication(recordID: publicationID, field: .author(index: index))
        )
        route = AppRoute(recordID: newID, destination: .people)
    }

    func beginAddingProjectCollaborator(fromProjectID projectID: String, at index: Int) {
        let newID = addPublicationAuthor()
        pendingSelectionReturn = PendingSelectionReturn(
            entityKind: .author,
            entityID: newID,
            destination: .project(recordID: projectID, field: .collaborator(index: index))
        )
        route = AppRoute(recordID: newID, destination: .people)
    }

    func beginAddingPublicationJournal(fromPublicationID publicationID: String, atStatusIndex index: Int) {
        let newID = addPublicationJournal()
        pendingSelectionReturn = PendingSelectionReturn(
            entityKind: .journal,
            entityID: newID,
            destination: .publication(recordID: publicationID, field: .journalStatus(index: index))
        )
        route = AppRoute(recordID: newID, destination: .journals)
    }

    func finalizePendingOrganizationSelection(id: String) {
        guard let option = organizations.first(where: { $0.id == id }) else { return }
        finalizePendingSelectionIfNeeded(for: .organization, entityID: option.id, canonicalValue: option.nameSv)
    }

    func finalizePendingProjectSelection(id: String) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        finalizePendingSelectionIfNeeded(for: .project, entityID: project.id, canonicalValue: project.nameSv)
    }

    func finalizePendingManagerSelection(id: String) {
        if let organization = organizations.first(where: { $0.id == id }) {
            finalizePendingSelectionIfNeeded(for: .manager, entityID: organization.id, canonicalValue: organization.nameSv)
            return
        }
        guard let manager = managers.first(where: { $0.id == id }) else { return }
        finalizePendingSelectionIfNeeded(for: .manager, entityID: manager.id, canonicalValue: manager.nameSv)
    }

    func finalizePendingAuthorSelection(id: String) {
        guard let author = publicationAuthors.first(where: { $0.id == id }) else { return }
        finalizePendingSelectionIfNeeded(for: .author, entityID: author.id, canonicalValue: author.name)
    }

    func finalizePendingJournalSelection(id: String) {
        guard let journal = publicationJournals.first(where: { $0.id == id }) else { return }
        finalizePendingSelectionIfNeeded(for: .journal, entityID: journal.id, canonicalValue: journal.name)
    }
}
