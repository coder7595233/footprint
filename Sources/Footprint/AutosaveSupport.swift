import AppKit
import Combine
import SwiftUI

enum AutosaveCoordinator {
    private static let minimumInteractiveDelay: TimeInterval = 0.45

    static func schedule(
        _ task: inout DispatchWorkItem?,
        after delay: TimeInterval,
        action: @escaping () -> Void
    ) {
        task?.cancel()
        let workItem = DispatchWorkItem(block: action)
        task = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, minimumInteractiveDelay), execute: workItem)
    }

    static func requestImmediate(
        _ task: inout DispatchWorkItem?,
        after delay: TimeInterval = 0,
        action: @escaping () -> Void
    ) {
        task?.cancel()
        let workItem = DispatchWorkItem(block: action)
        task = workItem
        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    static func flush(
        _ task: inout DispatchWorkItem?,
        action: () -> Void
    ) {
        task?.cancel()
        task = nil
        action()
    }
}

extension View {
    func flushPendingAutosaveOnTextEnd(_ action: @escaping () -> Void) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: NSControl.textDidEndEditingNotification)) { _ in
                action()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSText.didEndEditingNotification)) { _ in
                action()
            }
    }
}
