import Combine
import Foundation
import SwiftUI

/// Staged observation boundary for large workspaces. GrantDataStore remains the
/// compatibility facade and mutation owner; views can observe one projection
/// while retaining a non-observed reference to the facade for commands.
@MainActor
final class DataStoreDomainProjection: ObservableObject {
    enum Domain: String, CaseIterable, Sendable {
        case applications
        case projects
        case organizations
        case publications
        case cv
        case calendar
        case teaching
        case congresses
        case navigation
        case status
    }

    let domain: Domain
    let store: GrantDataStore
    @Published private(set) var revision: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()

    init(store: GrantDataStore, domain: Domain) {
        self.store = store
        self.domain = domain
        publisher(for: domain, store: store)
            .sink { [weak self] in
                guard let self else { return }
                revision &+= 1
            }
            .store(in: &cancellables)
    }

    /// Call once from a migrated workspace body. It is intentionally
    /// non-publishing so instrumentation cannot itself cause a render.
    func recordBodyEvaluation() {
        #if DEBUG
        DataStoreBodyUpdateInstrumentation.record(domain)
        #endif
    }

    private func publisher(
        for domain: Domain,
        store: GrantDataStore
    ) -> AnyPublisher<Void, Never> {
        var publishers: [AnyPublisher<Void, Never>]
        switch domain {
        case .applications:
            publishers = [
                store.$applicationRowSnapshotGeneration.voidPublisherAfterInitial,
                store.$organizationRowSnapshotGeneration.voidPublisherAfterInitial,
                store.$projectRowSnapshotGeneration.voidPublisherAfterInitial,
                store.$workspaceSearchGeneration.voidPublisherAfterInitial,
            ]
        case .projects:
            publishers = [
                store.$projectRowSnapshotGeneration.voidPublisherAfterInitial,
                store.$projectViewCacheGeneration.voidPublisherAfterInitial,
                store.$applicationRowSnapshotGeneration.voidPublisherAfterInitial,
                store.$publicationAuthorRowSnapshotGeneration.voidPublisherAfterInitial,
                store.$workspaceSearchGeneration.voidPublisherAfterInitial,
            ]
        case .organizations:
            publishers = [
                store.$organizationRowSnapshotGeneration.voidPublisherAfterInitial,
                store.$applicationRowSnapshotGeneration.voidPublisherAfterInitial,
                store.$projectRowSnapshotGeneration.voidPublisherAfterInitial,
                store.$workspaceSearchGeneration.voidPublisherAfterInitial,
            ]
        case .publications:
            publishers = [
                store.$publicationAuthorRowSnapshotGeneration.voidPublisherAfterInitial,
                store.$publicationJournalRowSnapshotGeneration.voidPublisherAfterInitial,
                store.$publicationJournalRankingGeneration.voidPublisherAfterInitial,
                store.$workspaceSearchGeneration.voidPublisherAfterInitial,
            ]
        case .cv:
            publishers = [
                store.$cvPersonalResume.voidPublisherAfterInitial,
                store.$cvConferenceContributions.voidPublisherAfterInitial,
                store.$cvMediaAppearances.voidPublisherAfterInitial,
                store.$cvReviewEntries.voidPublisherAfterInitial,
                store.$cvOtherPublications.voidPublisherAfterInitial,
                // The CV export preview renders applications, publications,
                // teaching and doctoral data too; without these it stayed
                // stale while the CV tab was frontmost.
                store.$applications.voidPublisherAfterInitial,
                store.$publicationRecords.voidPublisherAfterInitial,
                store.$teachingAssignments.voidPublisherAfterInitial,
                store.$teachingCourses.voidPublisherAfterInitial,
                store.$doctoralCandidates.voidPublisherAfterInitial,
            ]
        case .calendar:
            publishers = [
                store.$calendarContentGeneration.voidPublisherAfterInitial,
                store.$calendarContentUpdate.voidPublisherAfterInitial,
                store.$calendarTaskReminderBadgeEntries.voidPublisherAfterInitial,
            ]
        case .teaching:
            publishers = [
                store.$teachingCourses.voidPublisherAfterInitial,
                store.$teachingComponents.voidPublisherAfterInitial,
                store.$teachingFormats.voidPublisherAfterInitial,
                store.$teachingAssignments.voidPublisherAfterInitial,
                store.$doctoralCandidates.voidPublisherAfterInitial,
            ]
        case .congresses:
            publishers = [
                store.$organizations.voidPublisherAfterInitial,
                store.$calendarContentGeneration.voidPublisherAfterInitial,
                store.$workspaceSearchGeneration.voidPublisherAfterInitial,
            ]
        case .navigation:
            publishers = [
                store.$route.voidPublisherAfterInitial,
                store.$pendingCongressRouteToken.voidPublisherAfterInitial,
                store.$pendingCalendarOpenRequest.voidPublisherAfterInitial,
                store.$pendingCalendarRevealToken.voidPublisherAfterInitial,
                store.$pendingCalendarRevealRequest.voidPublisherAfterInitial,
                store.$undoRevealRequest.voidPublisherAfterInitial,
                // The deletion-confirmation alert is hosted on ContentView,
                // whose only store observation is this projection. Without
                // this publisher the alert stayed invisible until an
                // unrelated render (e.g. a tab switch) — with the deletion
                // silently pending behind it.
                store.$deletionImpactWarning.voidPublisherAfterInitial,
                // The floating undo panel and the footer status bar are also
                // ContentView-level UI; both went stale until an unrelated
                // navigation render without these.
                store.$undoStateGeneration.voidPublisherAfterInitial,
                store.$metadata
                    .map(\.showsFooterStatusBar)
                    .removeDuplicates()
                    .voidPublisherAfterInitial,
            ]
        case .status:
            publishers = [
                store.$loadError.voidPublisherAfterInitial,
                store.$notice.voidPublisherAfterInitial,
                store.$backgroundActivityMessage.voidPublisherAfterInitial,
                store.$persistenceStatus.voidPublisherAfterInitial,
                store.$undoStateGeneration.voidPublisherAfterInitial,
            ]
        }
        publishers.append(
            store.$metadata
                .map(\.interfaceLanguage)
                .removeDuplicates()
                .voidPublisherAfterInitial
        )
        return Publishers.MergeMany(publishers).eraseToAnyPublisher()
    }
}

/// Narrow observation boundary for the transient clipboard confirmation. The
/// root view intentionally does not observe the complete store, so this keeps
/// the overlay responsive without invalidating every retained workspace.
@MainActor
final class ClipboardPreviewProjection: ObservableObject {
    @Published private(set) var payload: ClipboardPreviewPayload?
    private var cancellable: AnyCancellable?

    init(store: GrantDataStore) {
        payload = store.clipboardPreview
        cancellable = store.$clipboardPreview
            .sink { [weak self] payload in
                self?.payload = payload
            }
    }
}

private extension Publisher where Failure == Never {
    var voidPublisherAfterInitial: AnyPublisher<Void, Never> {
        dropFirst().map { _ in () }.eraseToAnyPublisher()
    }
}

/// Lightweight test/debug instrumentation for verifying that a domain
/// projection did not invalidate unrelated workspace bodies.
enum DataStoreBodyUpdateInstrumentation {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts: [DataStoreDomainProjection.Domain: Int] = [:]

    static func record(_ domain: DataStoreDomainProjection.Domain) {
        lock.lock()
        counts[domain, default: 0] += 1
        lock.unlock()
    }

    static func count(for domain: DataStoreDomainProjection.Domain) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[domain, default: 0]
    }

    static func reset() {
        lock.lock()
        counts.removeAll()
        lock.unlock()
    }
}

/// Equatable boundary used by ContentView while it remains a compatibility
/// observer of the full store. Unrelated parent invalidations stop here; the
/// hosted workspace redraws only when its explicit input key or its domain
/// projection changes.
struct DataStoreDomainProjectionHost<InputKey: Equatable, Content: View>: View, @preconcurrency Equatable {
    let store: GrantDataStore
    let domain: DataStoreDomainProjection.Domain
    let inputKey: InputKey
    private let content: (GrantDataStore) -> Content
    @StateObject private var projection: DataStoreDomainProjection
    @StateObject private var navigationProjection: DataStoreDomainProjection

    init(
        store: GrantDataStore,
        domain: DataStoreDomainProjection.Domain,
        inputKey: InputKey,
        @ViewBuilder content: @escaping (GrantDataStore) -> Content
    ) {
        self.store = store
        self.domain = domain
        self.inputKey = inputKey
        self.content = content
        _projection = StateObject(
            wrappedValue: DataStoreDomainProjection(store: store, domain: domain)
        )
        _navigationProjection = StateObject(
            wrappedValue: DataStoreDomainProjection(store: store, domain: .navigation)
        )
    }

    var body: some View {
        let _ = projection.revision
        // Route changes must reach the mounted workspace even when the target
        // tab is already selected and its content-domain data did not change.
        let _ = navigationProjection.revision
        let _ = projection.recordBodyEvaluation()
        content(store)
    }

    static func == (
        lhs: DataStoreDomainProjectionHost<InputKey, Content>,
        rhs: DataStoreDomainProjectionHost<InputKey, Content>
    ) -> Bool {
        guard lhs.store === rhs.store else { return false }
        guard lhs.domain == rhs.domain else { return false }
        return lhs.inputKey == rhs.inputKey
    }
}
