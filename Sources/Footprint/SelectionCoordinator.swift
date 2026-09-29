import Foundation

/// Suppresses stale list-selection callbacks while a programmatic selection is
/// propagating through AppKit/SwiftUI. The protection lasts for event-loop
/// turns, not elapsed wall-clock time, so it behaves consistently under load.
@MainActor
final class AppSelectionCoordinator<ID: Equatable> {
    private(set) var lockedID: ID?
    private(set) var previousID: ID?

    private var generation: UInt = 0

    func accepts(candidate: ID?) -> Bool {
        if let lockedID,
           let previousID,
           candidate == previousID,
           candidate != lockedID {
            return false
        }
        return candidate != nil || lockedID == nil
    }

    func arm(_ id: ID, previousID: ID?) {
        generation &+= 1
        let armedGeneration = generation
        lockedID = id
        self.previousID = previousID
        releaseAfterEventLoopTurns(id: id, generation: armedGeneration, remainingTurns: 2)
    }

    func release(ifMatching id: ID) {
        guard lockedID == id else { return }
        clear()
    }

    func clear() {
        generation &+= 1
        lockedID = nil
        previousID = nil
    }

    private func releaseAfterEventLoopTurns(
        id: ID,
        generation armedGeneration: UInt,
        remainingTurns: Int
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.generation == armedGeneration,
                  self.lockedID == id else {
                return
            }
            if remainingTurns > 1 {
                self.releaseAfterEventLoopTurns(
                    id: id,
                    generation: armedGeneration,
                    remainingTurns: remainingTurns - 1
                )
            } else {
                self.clear()
            }
        }
    }
}
