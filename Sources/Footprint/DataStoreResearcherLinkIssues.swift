import Foundation

extension GrantDataStore {
    /// F43: id links to researchers that point to a researcher who no longer
    /// exists: co-applicants, project members, publication authors and the
    /// corresponding author, task and calendar participants. The details show
    /// the name written in the record when it is known, otherwise the stored
    /// id. Part of the F19 link pass, so a save that introduces one is warned
    /// about.
    ///
    /// Kinds that already have their own row are not repeated here:
    /// teaching students are always left to the existing "Student ID" row of
    /// the link pass. Conference contributors and presenters, congress
    /// participants, doctoral candidates and supervisors have their own rows
    /// in the Data view's full list but not in the check after saving, so
    /// they are included only when `includesKindsReportedElsewhere` is true
    /// (the check after saving), never in the Data view list.
    func dataQualityMissingResearcherLinkIssues(
        validAuthorIDs: Set<String>,
        includesKindsReportedElsewhere: Bool = false
    ) -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        let subtitle = language.text(
            "Linked to a researcher who no longer exists",
            "Kopplad till en forskare som inte finns"
        )
        // A task edited centrally supersedes the legacy copy on a record.
        let centralTaskIDs = Set(taskItems.map(\.id))

        func append(
            _ details: [String],
            destination: AppRoute.Destination,
            recordID: String,
            title: String,
            calendarRevealDayString: String? = nil,
            calendarEventSource: CalendarWorkspaceEventSource? = nil
        ) {
            var seen: Set<String> = []
            for detail in details where seen.insert(detail).inserted {
                let kind = IntegrityIssue.Kind.brokenLink
                issues.append(
                    IntegrityIssue(
                        id: "\(kind.rawValue)-\(Self.dataQualityDestinationKey(destination))-\(recordID)-\(detail)",
                        kind: kind,
                        destination: destination,
                        recordID: recordID,
                        title: title,
                        subtitle: subtitle,
                        details: detail,
                        calendarRevealDayString: calendarRevealDayString,
                        calendarEventSource: calendarEventSource
                    )
                )
            }
        }

        /// The names (or ids) behind the missing links of a name list. The
        /// ids line up with the names only when every name got an id.
        func missingInList(ids: [String], names: [String]) -> [String] {
            let isAligned = !ids.isEmpty && ids.count == names.count
            var seen: Set<String> = []
            var result: [String] = []
            for (index, raw) in ids.enumerated() {
                guard let id = raw.trimmedOrNil,
                      !validAuthorIDs.contains(id),
                      seen.insert(id).inserted else { continue }
                let name = isAligned ? names[index].trimmedOrNil : nil
                result.append(name ?? id)
            }
            return result
        }

        func missingSingle(id: String?, name: String?) -> [String] {
            guard let id = id?.trimmedOrNil, !validAuthorIDs.contains(id) else { return [] }
            return [name?.trimmedOrNil ?? id]
        }

        for application in applications {
            append(
                missingInList(ids: application.coApplicantAuthorIDs, names: application.coApplicants),
                destination: .applications,
                recordID: application.id,
                title: displayTitle(for: application, language: language)
            )
        }

        for project in projects {
            let title = project.nameSv.nonEmpty ?? project.nameEn.nonEmpty ?? project.id
            append(
                missingInList(ids: project.collaboratorAuthorIDs, names: project.collaboratorNames),
                destination: .projects,
                recordID: project.id,
                title: title
            )
            for task in project.projectTasks where !centralTaskIDs.contains(task.id) {
                append(
                    missingInList(ids: task.participantAuthorIDs, names: task.participantNames),
                    destination: .projects,
                    recordID: project.id,
                    title: title,
                    calendarRevealDayString: task.deadline.trimmedOrNil,
                    calendarEventSource: .projectTask(projectID: project.id, taskID: task.id)
                )
            }
        }

        for organization in organizations {
            let organizationTitle = dataQualityLocalizedOptionDisplayName(organization)
            for task in organization.projectTasks where !centralTaskIDs.contains(task.id) {
                append(
                    missingInList(ids: task.participantAuthorIDs, names: task.participantNames),
                    destination: .organizations,
                    recordID: organization.id,
                    title: organizationTitle,
                    calendarRevealDayString: task.deadline.trimmedOrNil,
                    calendarEventSource: .organizationTask(organizationID: organization.id, taskID: task.id)
                )
            }
            for congress in organization.congresses where includesKindsReportedElsewhere {
                append(
                    missingInList(ids: congress.participantAuthorIDs, names: congress.participantNames),
                    destination: .cv,
                    recordID: "organizationCongress:\(organization.id):\(congress.id)",
                    title: congress.title.nonEmpty ?? organizationTitle
                )
            }
        }

        for publication in publicationRecords {
            let title = publication.title.nonEmpty ?? publication.number
            append(
                missingInList(ids: publication.authorIDs, names: publication.authorNames)
                    + missingSingle(id: publication.correspondingAuthorID, name: publication.correspondingAuthorName),
                destination: .publications,
                recordID: publication.id,
                title: title
            )
            for task in publication.publicationTasks where !centralTaskIDs.contains(task.id) {
                append(
                    missingInList(ids: task.participantAuthorIDs, names: task.participantNames),
                    destination: .publications,
                    recordID: publication.id,
                    title: title,
                    calendarRevealDayString: task.deadline.trimmedOrNil,
                    calendarEventSource: .publicationTask(publicationID: publication.id, taskID: task.id)
                )
            }
        }

        for task in taskItems {
            let taskTitle = task.comment.trimmedOrNil ?? language.text("Task", "Uppgift")
            let linkedProject = task.links
                .first(where: { $0.kind == .project })
                .flatMap { link in projects.first(where: { $0.id == link.targetID }) }
            append(
                missingInList(ids: task.participantAuthorIDs, names: task.participantNames),
                destination: .projects,
                recordID: linkedProject?.id ?? task.id,
                title: linkedProject.map(dataQualityLocalizedOptionDisplayName) ?? taskTitle,
                calendarRevealDayString: task.deadline.trimmedOrNil,
                calendarEventSource: .teachingTask(taskID: task.id)
            )
        }

        for task in teachingWorkspaceTasks where !centralTaskIDs.contains(task.id) {
            append(
                missingInList(ids: task.participantAuthorIDs, names: task.participantNames),
                destination: .teaching,
                recordID: task.id,
                title: task.comment.trimmedOrNil ?? language.text("Task", "Uppgift"),
                calendarRevealDayString: task.deadline.trimmedOrNil,
                calendarEventSource: .teachingTask(taskID: task.id)
            )
        }

        for meeting in calendarMeetingRecords {
            append(
                missingInList(ids: meeting.participantAuthorIDs, names: meeting.participantNames),
                destination: .projects,
                recordID: meeting.id,
                title: meeting.title.nonEmpty ?? language.text("Calendar event", "Kalenderhändelse"),
                calendarRevealDayString: meeting.date,
                calendarEventSource: .meeting(meeting.id)
            )
        }

        for contribution in cvConferenceContributions where includesKindsReportedElsewhere {
            append(
                missingInList(ids: contribution.contributorAuthorIDs, names: contribution.contributorNames)
                    + missingSingle(id: contribution.presentedByAuthorID, name: contribution.presentedBy),
                destination: .cv,
                recordID: "conferenceContribution:\(contribution.id)",
                title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle
            )
        }

        // Teaching students: reported by the link pass's own "Student ID
        // links to missing researcher" row, in the Data view and after saving.

        for candidate in doctoralCandidates where includesKindsReportedElsewhere {
            append(
                missingSingle(id: candidate.candidateAuthorID, name: candidate.candidateName)
                    + candidate.supervisors.flatMap { missingSingle(id: $0.authorID, name: $0.name) },
                destination: .doctoralCandidates,
                recordID: candidate.id,
                title: candidate.candidateName.nonEmpty ?? candidate.doctoralProjectName.nonEmpty ?? candidate.id
            )
        }

        return issues
    }
}
