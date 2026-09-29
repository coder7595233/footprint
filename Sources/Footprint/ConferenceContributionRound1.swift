import Foundation

extension CVConferenceContribution {
    /// F2: status follows the submission outcome and the meeting dates.
    func derivedStatus(today: String = DateParsers.isoDay.string(from: Date())) -> CVConferenceContributionStatus {
        switch submissionOutcome {
        case .declined:
            return .rejected
        case .granted:
            let end = to.trimmedOrNil ?? from.trimmedOrNil
            if let end, end < today {
                return .presented
            }
            return .accepted
        case nil:
            return status
        }
    }
}
