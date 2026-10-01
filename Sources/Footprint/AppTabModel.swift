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

extension AppTab {
    /// Round 16: one symbol per workspace, shared by the navigation, the
    /// empty states and the command palette.
    var symbolName: String {
        switch self {
        case .calendar: return "calendar"
        case .congresses: return "mappin.and.ellipse"
        case .dataQuality: return "checkmark.shield.fill"
        case .cv: return "doc.richtext.fill"
        case .dissemination: return "play.rectangle.fill"
        case .expertAssignments: return "checklist.unchecked"
        case .projects: return "folder.fill"
        case .teaching: return "graduationcap.fill"
        case .doctoralCandidates: return "person.fill"
        case .applications: return "doc.text.fill"
        case .salary: return "chart.bar.xaxis"
        case .statistics: return "chart.pie.fill"
        case .organizations: return "building.columns.fill"
        case .coauthors: return "person.2.fill"
        case .journals: return "books.vertical.fill"
        case .publications: return "text.book.closed.fill"
        }
    }
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
