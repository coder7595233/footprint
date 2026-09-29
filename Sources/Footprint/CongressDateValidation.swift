import Foundation

enum CongressDateValidationFieldKey {
    static let from = "from"
    static let to = "to"
    static let abstractSubmissionDeadline = "abstractSubmissionDeadline"
    static let lateAbstractSubmissionDeadline = "lateAbstractSubmissionDeadline"
}

func latestCongressAbstractDeadline(for congress: OrganizationCongress) -> Date? {
    [
        congress.abstractSubmissionDeadline.trimmedOrNil.flatMap(DateParsers.isoDay.date(from:)),
        congress.lateAbstractSubmissionDeadline.trimmedOrNil.flatMap(DateParsers.isoDay.date(from:)),
    ]
    .compactMap { $0 }
    .max()
}

func congressHasPassedAbstractDeadline(
    _ congress: OrganizationCongress,
    on referenceDate: Date = Date(),
    calendar: Calendar = .current
) -> Bool {
    guard let latestDeadline = latestCongressAbstractDeadline(for: congress) else {
        return false
    }
    return calendar.startOfDay(for: latestDeadline) < calendar.startOfDay(for: referenceDate)
}

func illogicalCongressDateFieldKeys(for congress: OrganizationCongress) -> Set<String> {
    var fieldKeys: Set<String> = []

    let fromDate = parsedValidationDate(congress.from)
    let toDate = parsedValidationDate(congress.to)
    let abstractDeadline = parsedValidationDate(congress.abstractSubmissionDeadline)
    let lateAbstractDeadline = parsedValidationDate(congress.lateAbstractSubmissionDeadline)

    if let fromDate, let toDate, toDate < fromDate {
        fieldKeys.insert(CongressDateValidationFieldKey.from)
        fieldKeys.insert(CongressDateValidationFieldKey.to)
    }

    if let abstractDeadline, let fromDate, abstractDeadline > fromDate {
        fieldKeys.insert(CongressDateValidationFieldKey.abstractSubmissionDeadline)
        fieldKeys.insert(CongressDateValidationFieldKey.from)
    }

    if let abstractDeadline, let lateAbstractDeadline, lateAbstractDeadline < abstractDeadline {
        fieldKeys.insert(CongressDateValidationFieldKey.abstractSubmissionDeadline)
        fieldKeys.insert(CongressDateValidationFieldKey.lateAbstractSubmissionDeadline)
    }

    return fieldKeys
}

enum ApplicationDateValidationFieldKey {
    static let opensOn = "opensOn"
    static let closesOn = "closesOn"
    static let appliedOn = "appliedOn"
    static let grantedOn = "grantedOn"
    static let deniedOn = "deniedOn"
    static let withdrawnOn = "withdrawnOn"
    static let decisionExpectedOn = "decisionExpectedOn"
    static let firstDispositionOn = "firstDispositionOn"
    static let lastDispositionOn = "lastDispositionOn"
}

func illogicalApplicationDateFieldKeys(for application: GrantApplication) -> Set<String> {
    var fieldKeys: Set<String> = []

    let openDate = parsedValidationDate(application.opensOn)
    let closeDate = parsedValidationDate(application.closesOn)
    let appliedDate = parsedValidationDate(application.appliedOn)
    let grantedDate = parsedValidationDate(application.grantedOn)
    let deniedDate = parsedValidationDate(application.deniedOn)
    let withdrawnDate = parsedValidationDate(application.withdrawnOn)
    let firstDispositionDate = parsedValidationDate(application.firstDispositionOn)
    let lastDispositionDate = parsedValidationDate(application.lastDispositionOn)

    if let openDate, let closeDate, closeDate < openDate {
        fieldKeys.insert(ApplicationDateValidationFieldKey.opensOn)
        fieldKeys.insert(ApplicationDateValidationFieldKey.closesOn)
    }
    if let openDate, let appliedDate, appliedDate < openDate {
        fieldKeys.insert(ApplicationDateValidationFieldKey.opensOn)
        fieldKeys.insert(ApplicationDateValidationFieldKey.appliedOn)
    }
    if let closeDate, let appliedDate, appliedDate > closeDate {
        fieldKeys.insert(ApplicationDateValidationFieldKey.closesOn)
        fieldKeys.insert(ApplicationDateValidationFieldKey.appliedOn)
    }
    if let firstDispositionDate, let lastDispositionDate, lastDispositionDate < firstDispositionDate {
        fieldKeys.insert(ApplicationDateValidationFieldKey.firstDispositionOn)
        fieldKeys.insert(ApplicationDateValidationFieldKey.lastDispositionOn)
    }
    if let appliedDate, let grantedDate, grantedDate < appliedDate {
        fieldKeys.insert(ApplicationDateValidationFieldKey.appliedOn)
        fieldKeys.insert(ApplicationDateValidationFieldKey.grantedOn)
    }
    if let appliedDate, let deniedDate, deniedDate < appliedDate {
        fieldKeys.insert(ApplicationDateValidationFieldKey.appliedOn)
        fieldKeys.insert(ApplicationDateValidationFieldKey.deniedOn)
    }
    if let appliedDate, let withdrawnDate, withdrawnDate < appliedDate {
        fieldKeys.insert(ApplicationDateValidationFieldKey.appliedOn)
        fieldKeys.insert(ApplicationDateValidationFieldKey.withdrawnOn)
    }
    if let grantedDate, let firstDispositionDate, firstDispositionDate < grantedDate {
        fieldKeys.insert(ApplicationDateValidationFieldKey.grantedOn)
        fieldKeys.insert(ApplicationDateValidationFieldKey.firstDispositionOn)
    }
    if let grantedDate, let lastDispositionDate, lastDispositionDate < grantedDate {
        fieldKeys.insert(ApplicationDateValidationFieldKey.grantedOn)
        fieldKeys.insert(ApplicationDateValidationFieldKey.lastDispositionOn)
    }
    return fieldKeys
}

enum ConferenceContributionDateValidationFieldKey {
    static let from = "from"
    static let to = "to"
    static let submissionAppliedOn = "submissionAppliedOn"
    static let submissionClosesOn = "submissionClosesOn"
    static let submissionDecisionExpectedOn = "submissionDecisionExpectedOn"
    static let submissionDecisionOn = "submissionDecisionOn"
}

func illogicalConferenceContributionDateFieldKeys(for contribution: CVConferenceContribution) -> Set<String> {
    var fieldKeys: Set<String> = []

    let fromDate = parsedValidationDate(contribution.from)
    let toDate = parsedValidationDate(contribution.to)
    let appliedDate = parsedValidationDate(contribution.submissionAppliedOn)
    let closesDate = parsedValidationDate(contribution.submissionClosesOn)
    let expectedDate = parsedValidationDate(contribution.submissionDecisionExpectedOn)
    let decisionDate = parsedValidationDate(contribution.submissionDecisionOn)

    if let fromDate, let toDate, toDate < fromDate {
        fieldKeys.insert(ConferenceContributionDateValidationFieldKey.from)
        fieldKeys.insert(ConferenceContributionDateValidationFieldKey.to)
    }
    if let appliedDate, let closesDate, closesDate < appliedDate {
        fieldKeys.insert(ConferenceContributionDateValidationFieldKey.submissionAppliedOn)
        fieldKeys.insert(ConferenceContributionDateValidationFieldKey.submissionClosesOn)
    }
    if let appliedDate, let expectedDate, expectedDate < appliedDate {
        fieldKeys.insert(ConferenceContributionDateValidationFieldKey.submissionAppliedOn)
        fieldKeys.insert(ConferenceContributionDateValidationFieldKey.submissionDecisionExpectedOn)
    }
    if let appliedDate, let decisionDate, decisionDate < appliedDate {
        fieldKeys.insert(ConferenceContributionDateValidationFieldKey.submissionAppliedOn)
        fieldKeys.insert(ConferenceContributionDateValidationFieldKey.submissionDecisionOn)
    }

    return fieldKeys
}

enum PublicationDateValidationFieldKey {
    static let workflowStatusDate = "workflowStatusDate"
    static let currentSubmissionDate = "currentSubmissionDate"
}

func illogicalPublicationDateFieldKeys(
    for publication: PublicationRecord,
    workflowStatusDate: String? = nil
) -> Set<String> {
    var fieldKeys: Set<String> = []

    let currentSubmissionDate = parsedValidationDate(publication.currentSubmissionDate)
    let workflowDate = parsedValidationDate(workflowStatusDate ?? publication.workflowStatusDate)
    if let currentSubmissionDate, let workflowDate, workflowDate < currentSubmissionDate {
        fieldKeys.insert(PublicationDateValidationFieldKey.currentSubmissionDate)
        fieldKeys.insert(PublicationDateValidationFieldKey.workflowStatusDate)
    }

    return fieldKeys
}

enum PublicationSubmissionDateValidationFieldKey {
    static let submittedDate = "submittedDate"
    static let rejectedDate = "rejectedDate"
    static let acceptedDate = "acceptedDate"
    static let publishedDate = "publishedDate"
}

func illogicalPublicationSubmissionDateFieldKeys(for row: PublicationSubmissionEditorRow) -> Set<String> {
    var fieldKeys: Set<String> = []

    if let submittedDate = parsedValidationDate(row.submittedDate),
       let rejectedDate = parsedValidationDate(row.rejectedDate),
       rejectedDate < submittedDate {
        fieldKeys.insert(PublicationSubmissionDateValidationFieldKey.submittedDate)
        fieldKeys.insert(PublicationSubmissionDateValidationFieldKey.rejectedDate)
    }
    if let submittedDate = parsedValidationDate(row.submittedDate),
       let acceptedDate = parsedValidationDate(row.acceptedDate),
       acceptedDate < submittedDate {
        fieldKeys.insert(PublicationSubmissionDateValidationFieldKey.submittedDate)
        fieldKeys.insert(PublicationSubmissionDateValidationFieldKey.acceptedDate)
    }
    if let acceptedDate = parsedValidationDate(row.acceptedDate),
       let publishedDate = parsedValidationDate(row.publishedDate),
       publishedDate < acceptedDate {
        fieldKeys.insert(PublicationSubmissionDateValidationFieldKey.acceptedDate)
        fieldKeys.insert(PublicationSubmissionDateValidationFieldKey.publishedDate)
    }
    if let submittedDate = parsedValidationDate(row.submittedDate),
       let publishedDate = parsedValidationDate(row.publishedDate),
       publishedDate < submittedDate {
        fieldKeys.insert(PublicationSubmissionDateValidationFieldKey.submittedDate)
        fieldKeys.insert(PublicationSubmissionDateValidationFieldKey.publishedDate)
    }

    return fieldKeys
}

enum DoctoralDateValidationFieldKey {
    static let admissionDate = "admissionDate"
    static let planningSeminarDate = "planningSeminarDate"
    static let estimatedHalftimeDate = "estimatedHalftimeDate"
    static let halftimeDate = "halftimeDate"
    static let disputationDate = "disputationDate"
    static let plannedDisputationDate = "plannedDisputationDate"
}

func illogicalDoctoralDateFieldKeys(for candidate: DoctoralCandidateRecord) -> Set<String> {
    var fieldKeys: Set<String> = []

    let admission = parsedValidationDate(candidate.admissionDate)
    let planning = parsedValidationDate(candidate.planningSeminarDate)
    let estimatedHalftime = parsedValidationDate(candidate.estimatedHalftimeDate)
    let halftime = parsedValidationDate(candidate.halftimeDate) ?? estimatedHalftime
    let disputation = parsedValidationDate(candidate.disputationDate) ?? parsedValidationDate(candidate.plannedDisputationDate)

    if let admission, let planning, planning < admission {
        fieldKeys.insert(DoctoralDateValidationFieldKey.admissionDate)
        fieldKeys.insert(DoctoralDateValidationFieldKey.planningSeminarDate)
    }
    if let planning, let halftime, halftime < planning {
        fieldKeys.insert(DoctoralDateValidationFieldKey.planningSeminarDate)
        fieldKeys.insert(candidate.halftimeDate.trimmedOrNil == nil ? DoctoralDateValidationFieldKey.estimatedHalftimeDate : DoctoralDateValidationFieldKey.halftimeDate)
    }
    if let admission, let halftime, halftime < admission {
        fieldKeys.insert(DoctoralDateValidationFieldKey.admissionDate)
        fieldKeys.insert(candidate.halftimeDate.trimmedOrNil == nil ? DoctoralDateValidationFieldKey.estimatedHalftimeDate : DoctoralDateValidationFieldKey.halftimeDate)
    }
    if let halftime, let disputation, disputation < halftime {
        fieldKeys.insert(candidate.halftimeDate.trimmedOrNil == nil ? DoctoralDateValidationFieldKey.estimatedHalftimeDate : DoctoralDateValidationFieldKey.halftimeDate)
        fieldKeys.insert(candidate.disputationDate.trimmedOrNil == nil ? DoctoralDateValidationFieldKey.plannedDisputationDate : DoctoralDateValidationFieldKey.disputationDate)
    }

    return fieldKeys
}

func validationDateRangeIsIllogical(from: String?, to: String?) -> Bool {
    guard let fromDate = parsedValidationDate(from),
          let toDate = parsedValidationDate(to) else {
        return false
    }
    return toDate < fromDate
}

private func parsedValidationDate(_ value: String?) -> Date? {
    value?.trimmedOrNil.flatMap(DateParsers.isoDay.date(from:))
}
