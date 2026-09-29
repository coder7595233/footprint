import Foundation

extension GrantDataStore {
    /// F44: one timing line per main-thread step of a calendar change, so the
    /// performance log shows where the time after an edit or a deletion goes.
    /// The step goes in `phase=` because the log throttle keeps lines with a
    /// different phase apart; lines with the same first word and no phase
    /// would hide each other when they come less than 80 ms apart.
    func appendCalendarChangeDiagnosticIfSlow(
        phase: String,
        startedAt: CFAbsoluteTime,
        details: String = "",
        thresholdMs: Double = 12
    ) {
        let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        guard duration >= thresholdMs else { return }
        let suffix = details.isEmpty ? "" : " \(details)"
        appendPerformanceDiagnostic(
            String(format: "calendar-change phase=%@ total_ms=%.2f", phase, duration) + suffix
        )
    }

    /// F44: the automatic backup after a write is only made when the newest
    /// verified backup is at least 15 minutes old (see
    /// writePeriodicBackupSnapshotIfNeeded). Before the background check can
    /// say so, the main thread used to read the archived records and the
    /// received-grant data from the database on every single save. When the
    /// backups already known in memory show a verified backup younger than
    /// that, the background check would do nothing but tidy old backups, so
    /// the whole round is skipped; the next due backup tidies as before.
    func hasRecentVerifiedPeriodicBackupInMemory(now: Date = Date()) -> Bool {
        guard let snapshots = backupSnapshotsCache,
              let newest = snapshots.filter(\.isVerified).max(by: { $0.date < $1.date }) else {
            return false
        }
        let age = now.timeIntervalSince(newest.date)
        return age >= 0 && age < 15 * 60
    }
}
