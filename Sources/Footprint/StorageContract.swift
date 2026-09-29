import Foundation

enum FootprintStorageContract {
    static let version = "2026-05-sqlite-lock-v2"
    static let canonicalStore = "footprint.sqlite"
    static let backupFormat = "SQLite"

    /// Canonical, editable records. Derived relation/search documents are
    /// intentionally excluded because they can be rebuilt from these records.
    static let canonicalDocumentKeys: [String] = [
        "metadata",
        "app_settings",
        "applications",
        "organizations",
        "projects",
        "teaching_courses",
        "teaching_components",
        "teaching_formats",
        "teaching_assignments",
        "doctoral_candidates",
        "cv_personal_resume",
        "cv_conference_contributions",
        "cv_media_appearances",
        "cv_review_entries",
        "cv_other_publications",
        "publication_authors",
        "publication_journals",
        "publication_records",
        "congresses",
        "calendar_travel_records",
        "calendar_accommodation_records",
        "calendar_meeting_records",
    ]

    /// Every SQLite document required for a complete current installation.
    /// The two relational snapshots are included here because the bootstrap
    /// verifies their presence, even though they are derived rather than
    /// canonical editable data.
    static let requiredSQLiteDocumentKeys: [String] = canonicalDocumentKeys + [
        "relational_core",
        "relational_sqlite_snapshot",
    ]

}
