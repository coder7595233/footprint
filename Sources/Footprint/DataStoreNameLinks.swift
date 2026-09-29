import Foundation

/// F13c: the Data view's "Names to link" list. Every person name written in a
/// record (a co-applicant, a meeting participant, a publication author, a
/// supervisor, …) that does not match any researcher becomes one row, with
/// how many records use it and where. The name can then be linked to an
/// existing researcher (it becomes one of the researcher's name variants),
/// turned into a new researcher, or hidden.
extension GrantDataStore {
    struct UnlinkedPersonName: Identifiable, Equatable {
        enum UsageKind: String, CaseIterable {
            case application
            case project
            case organization
            case congress
            case meeting
            case task
            case publication
            case conferenceContribution
            case doctoralCandidate
            case teachingAssignment

            /// "3 applications" / "3 ansökningar".
            func countText(_ count: Int, language: AppLanguage) -> String {
                let isOne = count == 1
                switch self {
                case .application:
                    return isOne
                        ? language.text("1 application", "1 ansökan")
                        : language.text("\(count) applications", "\(count) ansökningar")
                case .project:
                    return isOne
                        ? language.text("1 project", "1 projekt")
                        : language.text("\(count) projects", "\(count) projekt")
                case .organization:
                    return isOne
                        ? language.text("1 organization", "1 organisation")
                        : language.text("\(count) organizations", "\(count) organisationer")
                case .congress:
                    return isOne
                        ? language.text("1 congress", "1 kongress")
                        : language.text("\(count) congresses", "\(count) kongresser")
                case .meeting:
                    return isOne
                        ? language.text("1 meeting", "1 möte")
                        : language.text("\(count) meetings", "\(count) möten")
                case .task:
                    return isOne
                        ? language.text("1 task", "1 uppgift")
                        : language.text("\(count) tasks", "\(count) uppgifter")
                case .publication:
                    return isOne
                        ? language.text("1 publication", "1 publikation")
                        : language.text("\(count) publications", "\(count) publikationer")
                case .conferenceContribution:
                    return isOne
                        ? language.text("1 conference contribution", "1 konferensbidrag")
                        : language.text("\(count) conference contributions", "\(count) konferensbidrag")
                case .doctoralCandidate:
                    return isOne
                        ? language.text("1 doctoral student", "1 doktorand")
                        : language.text("\(count) doctoral students", "\(count) doktorander")
                case .teachingAssignment:
                    return isOne
                        ? language.text("1 teaching assignment", "1 undervisningsuppdrag")
                        : language.text("\(count) teaching assignments", "\(count) undervisningsuppdrag")
                }
            }
        }

        /// How many records of one kind use the name, and the first of them
        /// (opened when the usage is clicked; nil when it has no page).
        struct Usage: Equatable {
            let kind: UsageKind
            let count: Int
            let destination: AppRoute.Destination?
            let routeRecordID: String
        }

        /// The name as it is written in the first record that uses it.
        let name: String
        /// The trimmed, lowercased name the rows are grouped by.
        let key: String
        /// One entry per kind of record, in `UsageKind` order.
        let usages: [Usage]

        /// Also the key a hidden row is remembered by.
        var id: String { "name-link|\(key)" }

        var totalCount: Int {
            usages.reduce(0) { $0 + $1.count }
        }

        /// "3 applications, 1 project".
        func usageSummary(language: AppLanguage) -> String {
            usages
                .map { $0.kind.countText($0.count, language: language) }
                .joined(separator: ", ")
        }
    }

    /// All person names that no researcher answers to. Hidden rows are left
    /// out unless asked for. The Data view asks for this list on every redraw,
    /// so it is built once and kept until the data changes.
    func unlinkedPersonNames(includeHidden: Bool = false) -> [UnlinkedPersonName] {
        let all: [UnlinkedPersonName]
        if let cached = cachedUnlinkedPersonNames {
            all = cached
        } else {
            all = buildUnlinkedPersonNames()
            cachedUnlinkedPersonNames = all
        }
        return includeHidden ? all : all.filter { !isDataQualityWarningHidden($0) }
    }

    /// The lowercased, trimmed form names are grouped (and hidden) by.
    static func unlinkedPersonNameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func buildUnlinkedPersonNames() -> [UnlinkedPersonName] {
        // Every name a researcher answers to, in the same normalized form
        // `publicationAuthor(matchingPresentedName:)` compares. Built once per
        // list so each written name is a single set lookup.
        var researcherNameKeys = Set<String>()
        for author in publicationAuthors {
            for candidate in author.presentedNameCandidates + [author.name, author.displayName] {
                let key = normalizedPersonLookupName(candidate)
                if !key.isEmpty {
                    researcherNameKeys.insert(key)
                }
            }
        }
        var isLinkedByWrittenName: [String: Bool] = [:]

        struct Group {
            var name: String
            var recordIDsByKind: [UnlinkedPersonName.UsageKind: Set<String>] = [:]
            var firstRecordByKind: [UnlinkedPersonName.UsageKind: (destination: AppRoute.Destination?, routeRecordID: String)] = [:]
        }
        var groups: [String: Group] = [:]

        func note(
            _ rawName: String,
            kind: UnlinkedPersonName.UsageKind,
            recordID: String,
            destination: AppRoute.Destination?,
            routeRecordID: String? = nil
        ) {
            let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let isLinked: Bool
            if let known = isLinkedByWrittenName[trimmed] {
                isLinked = known
            } else {
                let lookupKey = normalizedPersonLookupName(trimmed)
                isLinked = lookupKey.isEmpty || researcherNameKeys.contains(lookupKey)
                isLinkedByWrittenName[trimmed] = isLinked
            }
            guard !isLinked else { return }
            let key = Self.unlinkedPersonNameKey(trimmed)
            var group = groups[key] ?? Group(name: trimmed)
            var recordIDs = group.recordIDsByKind[kind] ?? []
            if recordIDs.insert(recordID).inserted {
                group.recordIDsByKind[kind] = recordIDs
                if group.firstRecordByKind[kind] == nil {
                    group.firstRecordByKind[kind] = (destination: destination, routeRecordID: routeRecordID ?? recordID)
                }
            }
            groups[key] = group
        }

        for application in applications {
            for name in application.coApplicants {
                note(name, kind: .application, recordID: application.id, destination: .applications)
            }
        }

        // Tasks can sit in several places; one task is counted once.
        for project in projects {
            for name in project.collaboratorNames {
                note(name, kind: .project, recordID: project.id, destination: .projects)
            }
            for task in project.projectTasks {
                for name in task.participantNames {
                    note(name, kind: .task, recordID: task.id, destination: .projects, routeRecordID: project.id)
                }
            }
        }

        for organization in organizations {
            for task in organization.projectTasks {
                for name in task.participantNames {
                    note(name, kind: .task, recordID: task.id, destination: .organizations, routeRecordID: organization.id)
                }
            }
            for congress in organization.congresses {
                for name in congress.participantNames {
                    note(
                        name,
                        kind: .congress,
                        recordID: "\(organization.id):\(congress.id)",
                        destination: .congresses,
                        routeRecordID: "organizationCongress:\(organization.id):\(congress.id)"
                    )
                }
            }
        }

        for meeting in calendarMeetingRecords {
            for name in meeting.participantNames {
                note(name, kind: .meeting, recordID: meeting.id, destination: nil)
            }
        }

        for task in taskItems {
            for name in task.participantNames {
                note(name, kind: .task, recordID: task.id, destination: nil)
            }
        }

        for publication in publicationRecords {
            for name in publication.authorNames {
                note(name, kind: .publication, recordID: publication.id, destination: .publications)
            }
            for task in publication.publicationTasks {
                for name in task.participantNames {
                    note(name, kind: .task, recordID: task.id, destination: .publications, routeRecordID: publication.id)
                }
            }
        }

        for contribution in cvConferenceContributions {
            let routeRecordID = "conferenceContribution:\(contribution.id)"
            for name in contribution.contributorNames + [contribution.presentedBy] {
                note(name, kind: .conferenceContribution, recordID: contribution.id, destination: .cv, routeRecordID: routeRecordID)
            }
        }

        for candidate in doctoralCandidates {
            for name in [candidate.candidateName] + candidate.supervisors.map(\.name) {
                note(name, kind: .doctoralCandidate, recordID: candidate.id, destination: .doctoralCandidates)
            }
        }

        for assignment in teachingAssignments {
            note(assignment.studentName, kind: .teachingAssignment, recordID: assignment.id, destination: .teaching)
        }

        var rows: [UnlinkedPersonName] = []
        rows.reserveCapacity(groups.count)
        for (key, group) in groups {
            var usages: [UnlinkedPersonName.Usage] = []
            for kind in UnlinkedPersonName.UsageKind.allCases {
                guard let recordIDs = group.recordIDsByKind[kind], !recordIDs.isEmpty,
                      let first = group.firstRecordByKind[kind] else { continue }
                usages.append(
                    UnlinkedPersonName.Usage(
                        kind: kind,
                        count: recordIDs.count,
                        destination: first.destination,
                        routeRecordID: first.routeRecordID
                    )
                )
            }
            rows.append(UnlinkedPersonName(name: group.name, key: key, usages: usages))
        }
        // Most used first: those are the links that matter most.
        return rows.sorted { lhs, rhs in
            let lhsCount = lhs.totalCount
            let rhsCount = rhs.totalCount
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.key < rhs.key
        }
    }

    /// Links a written name to an existing researcher by adding it as one of
    /// the researcher's name variants, through the same autosave the
    /// researcher's own editor uses (undo and saving included). From then on
    /// the name resolves to that researcher everywhere.
    func linkPersonName(_ name: String, toAuthorID authorID: String) {
        guard let trimmed = name.trimmedOrNil,
              let author = publicationAuthor(id: authorID) else { return }
        var updated = author
        updated.addNameVariants([trimmed])
        autosavePublicationAuthor(updated, previousName: author.name)
    }

    /// Creates a researcher with the written name through the ordinary
    /// "add researcher" path (one undoable step; the very first researcher
    /// still becomes the current user). Returns the new researcher's id.
    @discardableResult
    func createResearcher(forUnlinkedName name: String) -> String? {
        guard let trimmed = name.trimmedOrNil else { return nil }
        return addPublicationAuthor(name: trimmed)
    }
}
