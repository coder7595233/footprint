import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppTab: String, Hashable {
    case calendar
    case congresses
    case dataQuality
    case cv
    case dissemination
    case expertAssignments
    case projects
    case teaching
    case doctoralCandidates
    case applications
    case salary
    case statistics
    case organizations
    case coauthors
    case journals
    case publications
}

private extension AppTab {
    var isPublicationWorkspace: Bool {
        switch self {
        case .coauthors, .journals, .publications:
            true
        default:
            false
        }
    }
}
