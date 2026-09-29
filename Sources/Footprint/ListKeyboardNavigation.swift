import SwiftUI

enum AppListKeyboardNavigation {
    static func adjacentID(from currentID: String?, in orderedIDs: [String], direction: MoveCommandDirection) -> String? {
        guard !orderedIDs.isEmpty else { return nil }

        let step: Int
        switch direction {
        case .up:
            step = -1
        case .down:
            step = 1
        default:
            return nil
        }

        guard let currentID,
              let currentIndex = orderedIDs.firstIndex(of: currentID) else {
            return step > 0 ? orderedIDs.first : orderedIDs.last
        }

        let nextIndex = currentIndex + step
        guard orderedIDs.indices.contains(nextIndex) else { return currentID }
        return orderedIDs[nextIndex]
    }
}

private struct AppListKeyboardNavigationModifier: ViewModifier {
    let store: GrantDataStore
    let destination: AppRoute.Destination
    let isEnabled: Bool
    let orderedIDs: [String]
    let selectedID: String?
    let onSelect: (String) -> Void

    func body(content: Content) -> some View {
        content
            .formKeyboardNavigable()
            .onMoveCommand { direction in
                guard isEnabled else { return }
                moveSelection(direction)
            }
            .onReceive(NotificationCenter.default.publisher(for: .footprintMoveSelectionUp)) { _ in
                handleGlobalSelectionMove(.up)
            }
            .onReceive(NotificationCenter.default.publisher(for: .footprintMoveSelectionDown)) { _ in
                handleGlobalSelectionMove(.down)
            }
            .onAppear {
                refreshKeyboardNavigationActivation()
            }
            .onChange(of: isEnabled) { _, _ in
                refreshKeyboardNavigationActivation()
            }
            // A click anywhere in the list is a genuine claim on arrow keys.
            .simultaneousGesture(TapGesture().onEnded {
                refreshKeyboardNavigationActivation()
            })
            // Data-driven changes must never STEAL arrow keys from the list
            // the user is actually navigating: any mounted list whose rows
            // re-sorted after an autosave used to grab global up/down.
            .onChange(of: selectedID) { _, _ in
                guard store.activeListKeyboardNavigationDestination == destination
                    || store.activeListKeyboardNavigationDestination == nil else { return }
                refreshKeyboardNavigationActivation()
            }
            .onChange(of: orderedIDs) { old, new in
                guard store.activeListKeyboardNavigationDestination == destination
                    || (store.activeListKeyboardNavigationDestination == nil && old.isEmpty && !new.isEmpty) else { return }
                refreshKeyboardNavigationActivation()
            }
            .onDisappear {
                deactivateKeyboardNavigationIfNeeded()
            }
    }

    private func handleGlobalSelectionMove(_ direction: MoveCommandDirection) {
        guard isEnabled,
              store.activeListKeyboardNavigationDestination == destination else { return }
        moveSelection(direction)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let nextID = AppListKeyboardNavigation.adjacentID(
            from: selectedID,
            in: orderedIDs,
            direction: direction
        ) else { return }
        refreshKeyboardNavigationActivation()
        onSelect(nextID)
    }

    private func refreshKeyboardNavigationActivation() {
        guard isEnabled, selectedID != nil || !orderedIDs.isEmpty else {
            deactivateKeyboardNavigationIfNeeded()
            return
        }
        store.activateListKeyboardNavigation(for: destination)
    }

    private func deactivateKeyboardNavigationIfNeeded() {
        store.deactivateListKeyboardNavigation(for: destination)
    }
}

extension View {
    func appListKeyboardNavigation(
        store: GrantDataStore,
        destination: AppRoute.Destination,
        isEnabled: Bool = true,
        orderedIDs: [String],
        selectedID: String?,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        modifier(
            AppListKeyboardNavigationModifier(
                store: store,
                destination: destination,
                isEnabled: isEnabled,
                orderedIDs: orderedIDs,
                selectedID: selectedID,
                onSelect: onSelect
            )
        )
    }
}
