import SwiftUI

struct AppSplitLayout: Equatable {
    let defaultsKey: String
    let defaultFraction: CGFloat
    let sidebarMinimumWidth: CGFloat
    let sidebarMaximumWidth: CGFloat?
    let detailMinimumWidth: CGFloat

    static let applications = AppSplitLayout(
        defaultsKey: "ApplicationsSplitFractionV7",
        defaultFraction: 0.38,
        sidebarMinimumWidth: 320,
        sidebarMaximumWidth: 620,
        detailMinimumWidth: 520
    )

    static let organizations = AppSplitLayout(
        defaultsKey: "OrganizationsSplitFractionV5",
        defaultFraction: 0.52,
        sidebarMinimumWidth: 420,
        sidebarMaximumWidth: 560,
        detailMinimumWidth: 520
    )

    static let projects = AppSplitLayout(
        defaultsKey: "ProjectsSplitFractionV8",
        defaultFraction: 0.52,
        sidebarMinimumWidth: 420,
        sidebarMaximumWidth: 468,
        detailMinimumWidth: 520
    )

    static let publications = AppSplitLayout(
        defaultsKey: "PublicationsSplitFractionV6",
        defaultFraction: 0.52,
        sidebarMinimumWidth: 420,
        sidebarMaximumWidth: 972,
        detailMinimumWidth: 520
    )

    static let congresses = AppSplitLayout(
        defaultsKey: "CongressesSplitFractionV1",
        defaultFraction: 0.52,
        sidebarMinimumWidth: 420,
        sidebarMaximumWidth: 857,
        detailMinimumWidth: 520
    )

    static let publicationAuthors = AppSplitLayout(
        defaultsKey: "PublicationAuthorsSplitFractionV5",
        defaultFraction: 0.52,
        sidebarMinimumWidth: 420,
        sidebarMaximumWidth: 1058,
        detailMinimumWidth: 520
    )

    static let salary = AppSplitLayout(
        defaultsKey: "SalarySplitFractionV1",
        defaultFraction: 0.34,
        sidebarMinimumWidth: 320,
        sidebarMaximumWidth: 420,
        detailMinimumWidth: 560
    )

    static let publicationJournals = AppSplitLayout(
        defaultsKey: "PublicationJournalsSplitFractionV5",
        defaultFraction: 0.52,
        sidebarMinimumWidth: 420,
        sidebarMaximumWidth: 768,
        detailMinimumWidth: 520
    )

    static let doctoralCandidates = AppSplitLayout(
        defaultsKey: "DoctoralCandidatesSplitFractionV4",
        defaultFraction: 0.52,
        sidebarMinimumWidth: 420,
        sidebarMaximumWidth: 820,
        detailMinimumWidth: 520
    )

    static let expertAssignments = AppSplitLayout(
        defaultsKey: "ExpertAssignmentsSplitFractionV1",
        defaultFraction: 0.44,
        sidebarMinimumWidth: 360,
        sidebarMaximumWidth: 620,
        detailMinimumWidth: 560
    )

    static let teachingAssignments = AppSplitLayout(
        defaultsKey: "TeachingAssignmentsSplitFractionV1",
        defaultFraction: 0.48,
        sidebarMinimumWidth: 440,
        sidebarMaximumWidth: 720,
        detailMinimumWidth: 540
    )

    static let cvExport = AppSplitLayout(
        defaultsKey: "CVExportWorkspaceSplitFractionV3",
        defaultFraction: 0.52,
        sidebarMinimumWidth: 420,
        sidebarMaximumWidth: nil,
        detailMinimumWidth: 520
    )
}

enum AppWorkspaceLayout {
    static let detailOuterPadding: CGFloat = 14
    static let detailTrailingPadding: CGFloat = 26
}

enum AppLockedFieldVisibility {
    static func shouldShow(isLocked: Bool, value: String?) -> Bool {
        !isLocked || value?.trimmedOrNil != nil
    }

    static func shouldShow(isLocked: Bool, values: [String?]) -> Bool {
        !isLocked || values.contains { $0?.trimmedOrNil != nil }
    }

    static func shouldShow(isLocked: Bool, isRelevant: Bool) -> Bool {
        !isLocked || isRelevant
    }

    static func visibleItems<Item>(
        _ items: [Item],
        isLocked: Bool,
        isEmpty: (Item) -> Bool
    ) -> [Item] {
        isLocked ? items.filter { !isEmpty($0) } : items
    }
}

extension View {
    func appDetailWorkspacePadding() -> some View {
        self
            .padding(.leading, AppWorkspaceLayout.detailOuterPadding)
            .padding(.top, AppWorkspaceLayout.detailOuterPadding)
            .padding(.bottom, AppWorkspaceLayout.detailOuterPadding)
            .padding(.trailing, AppWorkspaceLayout.detailTrailingPadding)
    }
}

struct AppDetailToolbarRow<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            Spacer(minLength: 0)
            content
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
