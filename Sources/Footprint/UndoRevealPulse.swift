import SwiftUI

extension UndoRevealTarget {
    func matches(routeDestination: AppRoute.Destination, recordID: String?) -> Bool {
        guard let recordID else { return false }
        guard case let .route(route) = destination else { return false }
        return route.destination == routeDestination && route.recordID == recordID
    }

    func matchesWholeRecord(routeDestination: AppRoute.Destination, recordID: String?) -> Bool {
        matches(routeDestination: routeDestination, recordID: recordID) && fieldKey == nil
    }

    func matchesField(routeDestination: AppRoute.Destination, recordID: String?, fieldKey: String) -> Bool {
        matches(routeDestination: routeDestination, recordID: recordID) && self.fieldKey == fieldKey
    }

    func matches(calendarSource: CalendarWorkspaceEventSource) -> Bool {
        guard case let .calendar(_, eventSource) = destination else { return false }
        return eventSource == calendarSource
    }
}

private struct UndoRevealPulseModifier: ViewModifier {
    let triggerID: UUID?
    let isActive: Bool
    let cornerRadius: CGFloat

    @State private var lastTriggeredID: UUID?
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppPalette.chartBlue.opacity(isPulsing ? 0.18 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(AppPalette.chartBlue.opacity(isPulsing ? 0.9 : 0), lineWidth: 2)
                    )
                    .allowsHitTesting(false)
            }
            .onAppear {
                triggerPulseIfNeeded()
            }
            .onChange(of: triggerID) { _, _ in
                triggerPulseIfNeeded()
            }
            .onChange(of: isActive) { _, active in
                guard active else { return }
                triggerPulseIfNeeded()
            }
    }

    private func triggerPulseIfNeeded() {
        guard isActive, let triggerID, triggerID != lastTriggeredID else { return }
        lastTriggeredID = triggerID
        isPulsing = false
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18).repeatCount(5, autoreverses: true)) {
                isPulsing = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            guard lastTriggeredID == triggerID else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isPulsing = false
            }
        }
    }
}

extension View {
    func undoRevealPulse(
        triggerID: UUID?,
        isActive: Bool,
        cornerRadius: CGFloat = AppPalette.mediumCornerRadius
    ) -> some View {
        modifier(
            UndoRevealPulseModifier(
                triggerID: triggerID,
                isActive: isActive,
                cornerRadius: cornerRadius
            )
        )
    }
}
