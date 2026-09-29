import SwiftUI

/// Records which run-loop mode the main thread last ran in and when. The lag
/// watchdog measures MAIN QUEUE scheduling delay, and the main queue is
/// starved while the run loop spins in event-tracking mode (scrolling, menu
/// tracking) even though the app is fully responsive — those "stalls" end
/// exactly at the next user input. Tagging each lag line with the observed
/// run-loop state separates such phantoms from genuinely blocked main threads.
final class MainRunLoopModeProbe: @unchecked Sendable {
    static let shared = MainRunLoopModeProbe()

    private let lock = NSLock()
    private var lastMode = "unknown"
    private var lastActivityAt: CFAbsoluteTime = 0
    private var lastTrackingActivityAt: CFAbsoluteTime = 0
    private var isInstalled = false

    func installOnMainRunLoop() {
        lock.lock()
        let alreadyInstalled = isInstalled
        isInstalled = true
        lock.unlock()
        guard !alreadyInstalled else { return }

        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeSources.rawValue
                | CFRunLoopActivity.beforeWaiting.rawValue
                | CFRunLoopActivity.afterWaiting.rawValue,
            true,
            0
        ) { [self] _, _ in
            let mode = CFRunLoopCopyCurrentMode(CFRunLoopGetCurrent()).map { $0.rawValue as String } ?? "unknown"
            let shortMode = Self.shortModeName(mode)
            let now = CFAbsoluteTimeGetCurrent()
            lock.lock()
            lastMode = shortMode
            lastActivityAt = now
            if shortMode == "tracking" || shortMode == "modal" {
                lastTrackingActivityAt = now
            }
            lock.unlock()
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// mode/idleMs: last observed run-loop mode and milliseconds since the
    /// run loop last showed life. trackingGapMs: milliseconds since the loop
    /// last ran in a queue-starving mode (event tracking / modal panel);
    /// -1 when that never happened.
    func snapshot() -> (mode: String, idleMs: Double, trackingGapMs: Double) {
        lock.lock()
        defer { lock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        let idleMs = lastActivityAt > 0 ? (now - lastActivityAt) * 1000 : -1
        let trackingGapMs = lastTrackingActivityAt > 0 ? (now - lastTrackingActivityAt) * 1000 : -1
        return (lastMode, idleMs, trackingGapMs)
    }

    private static func shortModeName(_ mode: String) -> String {
        switch mode {
        case "kCFRunLoopDefaultMode": return "default"
        case "NSEventTrackingRunLoopMode": return "tracking"
        case "NSModalPanelRunLoopMode": return "modal"
        default: return mode
        }
    }
}

struct PerformanceReadyReporter: View {
    let onReady: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                DispatchQueue.main.async {
                    onReady()
                }
            }
    }
}

struct PerformanceReadyTriggerReporter<Trigger: Equatable>: View {
    let trigger: Trigger
    let onReady: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                DispatchQueue.main.async {
                    onReady()
                }
            }
            .onChange(of: trigger) { _, _ in
                DispatchQueue.main.async {
                    onReady()
                }
            }
    }
}

private struct PerformanceScopeProbeModifier: ViewModifier {
    let store: GrantDataStore
    let scope: String
    let identifier: String?
    let restartOnIdentifierChange: Bool

    @State private var appearedAt: CFAbsoluteTime?
    @State private var readyReported = false
    @State private var sessionToken = UUID()
    @State private var activeIdentifier: String?

    func body(content: Content) -> some View {
        content
            .background(
                PerformanceReadyTriggerReporter(
                    trigger: restartOnIdentifierChange ? (identifier ?? "-") : "__static__"
                ) {
                    reportReadyIfNeeded()
                }
            )
            .onAppear {
                startSession(identifier: identifier)
            }
            .onChange(of: identifier) { oldValue, newValue in
                guard restartOnIdentifierChange, oldValue != newValue else { return }
                reportDisappearIfNeeded(identifier: activeIdentifier ?? oldValue)
                startSession(identifier: newValue)
            }
            .onDisappear {
                reportDisappearIfNeeded(identifier: activeIdentifier ?? identifier)
                sessionToken = UUID()
                appearedAt = nil
                readyReported = false
                activeIdentifier = nil
            }
    }

    private func reportReadyIfNeeded() {
        guard !readyReported, let appearedAt else { return }
        readyReported = true
        let duration = (CFAbsoluteTimeGetCurrent() - appearedAt) * 1000
        store.appendPerformanceDiagnostic(
            String(
                format: "view-ready scope=%@ id=%@ ready_ms=%.2f",
                scope,
                identifier ?? "-",
                duration
            )
        )
    }

    private func startSession(identifier: String?) {
        let token = UUID()
        sessionToken = token
        readyReported = false
        activeIdentifier = identifier
        let now = CFAbsoluteTimeGetCurrent()
        appearedAt = now
        store.appendPerformanceDiagnostic(
            String(
                format: "view-appear scope=%@ id=%@",
                scope,
                identifier ?? "-"
            )
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard sessionToken == token, let appearedAt else { return }
            let duration = (CFAbsoluteTimeGetCurrent() - appearedAt) * 1000
            store.appendPerformanceDiagnostic(
                String(
                    format: "view-settled scope=%@ id=%@ settle_ms=%.2f",
                    scope,
                    identifier ?? "-",
                    duration
                )
            )
        }
    }

    private func reportDisappearIfNeeded(identifier: String?) {
        guard let appearedAt else { return }
        let duration = (CFAbsoluteTimeGetCurrent() - appearedAt) * 1000
        store.appendPerformanceDiagnostic(
            String(
                format: "view-disappear scope=%@ id=%@ visible_ms=%.2f",
                scope,
                identifier ?? "-",
                duration
            )
        )
    }
}

extension View {
    func performanceScopeProbe(
        store: GrantDataStore,
        scope: String,
        identifier: String? = nil,
        restartOnIdentifierChange: Bool = false
    ) -> some View {
        modifier(
            PerformanceScopeProbeModifier(
                store: store,
                scope: scope,
                identifier: identifier,
                restartOnIdentifierChange: restartOnIdentifierChange
            )
        )
    }
}
