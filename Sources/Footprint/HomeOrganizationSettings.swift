import Foundation

// MARK: - Home organization

/// Defaults for Settings > Home organization. The app knows no organization
/// by name: the home region and the organization used for the salary
/// calculator are chosen by the user and stored in the data.
enum HomeOrganizationDefaults {
    static let homeCountry = "Sweden"
}

/// True when both texts name the same country ("Sverige" and "Sweden" match).
/// An empty text never matches.
func countryNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
    let left = GrantParsing.canonicalCountryName(lhs)
    let right = GrantParsing.canonicalCountryName(rhs)
    guard !left.isEmpty, !right.isEmpty else { return false }
    return left.caseInsensitiveCompare(right) == .orderedSame
}

// MARK: - Reminder settings (Settings > Calendar)

/// When grant and task reminders are sent. The defaults are the times and
/// lead days the app used before they became settings.
struct CalendarReminderSettings: Codable, Hashable {
    static let standard = CalendarReminderSettings()

    /// Reminder "closing soon" this many days before an application closes.
    var grantClosingLeadDays: Int
    /// Reminder this many days after the expected decision date has passed.
    var grantDecisionFollowUpDays: Int
    /// Reminder this many months before the disposition time ends.
    var grantDispositionEndLeadMonths: Int
    /// Time of day (HH:MM) grant reminders are sent.
    var grantReminderTime: String
    /// Time of day (HH:MM) the daily task notification is sent.
    var taskNotificationTime: String
    /// A task is marked "due soon" (yellow) this many days before its deadline.
    var taskDueSoonDays: Int
    /// Reminders about applications are sent (on unless switched off).
    var grantRemindersEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case grantClosingLeadDays
        case grantDecisionFollowUpDays
        case grantDispositionEndLeadMonths
        case grantReminderTime
        case taskNotificationTime
        case taskDueSoonDays
        case grantRemindersEnabled
    }

    init(
        grantClosingLeadDays: Int = 7,
        grantDecisionFollowUpDays: Int = 7,
        grantDispositionEndLeadMonths: Int = 3,
        grantReminderTime: String = "09:00",
        taskNotificationTime: String = "12:00",
        taskDueSoonDays: Int = 7,
        grantRemindersEnabled: Bool = true
    ) {
        self.grantClosingLeadDays = grantClosingLeadDays
        self.grantDecisionFollowUpDays = grantDecisionFollowUpDays
        self.grantDispositionEndLeadMonths = grantDispositionEndLeadMonths
        self.grantReminderTime = grantReminderTime
        self.taskNotificationTime = taskNotificationTime
        self.taskDueSoonDays = taskDueSoonDays
        self.grantRemindersEnabled = grantRemindersEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CalendarReminderSettings()
        self.init(
            grantClosingLeadDays: try container.decodeIfPresent(Int.self, forKey: .grantClosingLeadDays) ?? defaults.grantClosingLeadDays,
            grantDecisionFollowUpDays: try container.decodeIfPresent(Int.self, forKey: .grantDecisionFollowUpDays) ?? defaults.grantDecisionFollowUpDays,
            grantDispositionEndLeadMonths: try container.decodeIfPresent(Int.self, forKey: .grantDispositionEndLeadMonths) ?? defaults.grantDispositionEndLeadMonths,
            grantReminderTime: try container.decodeIfPresent(String.self, forKey: .grantReminderTime) ?? defaults.grantReminderTime,
            taskNotificationTime: try container.decodeIfPresent(String.self, forKey: .taskNotificationTime) ?? defaults.taskNotificationTime,
            taskDueSoonDays: try container.decodeIfPresent(Int.self, forKey: .taskDueSoonDays) ?? defaults.taskDueSoonDays,
            grantRemindersEnabled: try container.decodeIfPresent(Bool.self, forKey: .grantRemindersEnabled) ?? defaults.grantRemindersEnabled
        )
    }

    /// Numbers kept within sensible limits and times written as HH:MM; an
    /// unreadable time falls back to the default time.
    func normalized() -> CalendarReminderSettings {
        let defaults = CalendarReminderSettings()
        return CalendarReminderSettings(
            grantClosingLeadDays: min(max(grantClosingLeadDays, 0), 365),
            grantDecisionFollowUpDays: min(max(grantDecisionFollowUpDays, 0), 365),
            grantDispositionEndLeadMonths: min(max(grantDispositionEndLeadMonths, 0), 60),
            grantReminderTime: Self.normalizedTime(grantReminderTime) ?? defaults.grantReminderTime,
            taskNotificationTime: Self.normalizedTime(taskNotificationTime) ?? defaults.taskNotificationTime,
            taskDueSoonDays: min(max(taskDueSoonDays, 0), 365),
            grantRemindersEnabled: grantRemindersEnabled
        )
    }

    var grantReminderHourMinute: (hour: Int, minute: Int) {
        Self.hourMinute(from: grantReminderTime) ?? (9, 0)
    }

    var taskNotificationHourMinute: (hour: Int, minute: Int) {
        Self.hourMinute(from: taskNotificationTime) ?? (12, 0)
    }

    /// "9", "9:5", "0930" and "09:30" are read; anything else is nil.
    static func hourMinute(from raw: String) -> (hour: Int, minute: Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hour: Int?
        let minute: Int?
        if trimmed.contains(":") || trimmed.contains(".") {
            let parts = trimmed.split(whereSeparator: { $0 == ":" || $0 == "." }).map(String.init)
            guard parts.count == 2 else { return nil }
            hour = Int(parts[0])
            minute = Int(parts[1])
        } else if trimmed.count <= 2 {
            hour = Int(trimmed)
            minute = 0
        } else if trimmed.count <= 4, trimmed.allSatisfy(\.isNumber) {
            hour = Int(trimmed.dropLast(2))
            minute = Int(trimmed.suffix(2))
        } else {
            return nil
        }
        guard let hour, let minute, (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }

    static func normalizedTime(_ raw: String) -> String? {
        guard let value = hourMinute(from: raw) else { return nil }
        return String(format: "%02d:%02d", value.hour, value.minute)
    }
}

// MARK: - Calendar category behaviour (Settings > Calendar categories)

/// What a calendar category means to the app. Replaces the fixed category
/// names ("Klinik", "Resa", "Semester", …) the app used to look for.
struct CalendarCategoryBehaviorSetting: Codable, Hashable {
    var categoryName: String
    /// Activities in this category are left out of your own meeting statistics.
    var excludedFromMeetingStatistics: Bool
    /// Clinical time: the activity is placed at the home region (in the home
    /// country) and is shown as an in-person activity.
    var isClinicalTime: Bool
    /// Leave: the calendar shows only the category, not the activity's title.
    var isLeave: Bool

    enum CodingKeys: String, CodingKey {
        case categoryName
        case excludedFromMeetingStatistics
        case isClinicalTime
        case isLeave
    }

    init(
        categoryName: String,
        excludedFromMeetingStatistics: Bool = false,
        isClinicalTime: Bool = false,
        isLeave: Bool = false
    ) {
        self.categoryName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.excludedFromMeetingStatistics = excludedFromMeetingStatistics
        self.isClinicalTime = isClinicalTime
        self.isLeave = isLeave
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            categoryName: try container.decodeIfPresent(String.self, forKey: .categoryName) ?? "",
            excludedFromMeetingStatistics: try container.decodeIfPresent(Bool.self, forKey: .excludedFromMeetingStatistics) ?? false,
            isClinicalTime: try container.decodeIfPresent(Bool.self, forKey: .isClinicalTime) ?? false,
            isLeave: try container.decodeIfPresent(Bool.self, forKey: .isLeave) ?? false
        )
    }

    var lookupKey: String {
        normalizedCalendarCategoryLookupKey(categoryName)
    }

    var hasAnyFlag: Bool {
        excludedFromMeetingStatistics || isClinicalTime || isLeave
    }

    /// The meaning the app gave fixed category names before these became
    /// settings. Used only until the categories' settings have been stored
    /// (the one-time startup step stores them for the existing categories).
    static func legacyDefault(forCategoryNamed name: String) -> CalendarCategoryBehaviorSetting {
        let key = normalizedCalendarCategoryLookupKey(name)
        let clinical = ["Klinik", "Clinic"].map(normalizedCalendarCategoryLookupKey).contains(key)
        let travel = ["Resa", "Travel"].map(normalizedCalendarCategoryLookupKey).contains(key)
        let leave = ["Semester", "Vacation"].map(normalizedCalendarCategoryLookupKey).contains(key)
        return CalendarCategoryBehaviorSetting(
            categoryName: name,
            excludedFromMeetingStatistics: clinical || travel,
            isClinicalTime: clinical,
            isLeave: leave
        )
    }

    /// One entry per category (first one wins), without empty names, in the
    /// given order. Entries without any flag are kept: a stored list means the
    /// user's choices count, also when a box is unticked.
    static func normalizedList(_ settings: [CalendarCategoryBehaviorSetting]) -> [CalendarCategoryBehaviorSetting] {
        var seen = Set<String>()
        var result: [CalendarCategoryBehaviorSetting] = []
        for setting in settings {
            let normalized = CalendarCategoryBehaviorSetting(
                categoryName: setting.categoryName,
                excludedFromMeetingStatistics: setting.excludedFromMeetingStatistics,
                isClinicalTime: setting.isClinicalTime,
                isLeave: setting.isLeave
            )
            let key = normalized.lookupKey
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(normalized)
        }
        return result
    }
}

// MARK: - Store accessors and saving

extension GrantDataStore {
    /// The home country as a canonical English country name (default Sweden).
    var homeCountryName: String {
        let stored = metadata.homeCountry?.trimmedOrNil ?? HomeOrganizationDefaults.homeCountry
        let canonical = GrantParsing.canonicalCountryName(stored)
        return canonical.isEmpty ? HomeOrganizationDefaults.homeCountry : canonical
    }

    /// True when the country text names the home country.
    func isHomeCountry(_ country: String) -> Bool {
        countryNamesMatch(country, homeCountryName)
    }

    /// The home region's organization id: the stored id when that
    /// organization exists. Nothing stored (or an empty value) means no home
    /// region; the app never picks one by name.
    var homeRegionOrganizationID: String? {
        resolvedHomeOrganizationID(stored: metadata.homeRegionOrganizationID)
    }

    /// Round 10: "Förvald medelsförvaltare" in Settings, when that
    /// organization exists.
    var defaultFundManagerOrganizationID: String? {
        resolvedHomeOrganizationID(stored: metadata.defaultFundManagerOrganizationID)
    }

    func resolvedHomeOrganizationID(stored: String?) -> String? {
        guard let id = stored?.trimmedOrNil else { return nil }
        return organization(id: id) == nil ? nil : id
    }

    var calendarReminderSettings: CalendarReminderSettings {
        (metadata.calendarReminderSettings ?? .standard).normalized()
    }

    /// Settings > Calendar > Working hours (week view shading).
    var calendarWorkingHours: CalendarWorkingHoursSettings {
        (metadata.calendarWorkingHours ?? .standard).normalized()
    }

    /// The organization whose salary calculator is used for applications
    /// (the one with "Use as salary calculator for applications" ticked).
    var applicationSalaryCalculatorOrganization: OrganizationRecord? {
        organizations.first(where: \.usesAsApplicationSalaryCalculator)
    }

    /// The old "Main employer" setting was removed (it had no effect). A value
    /// stored by an earlier version is left untouched in the data.
    func autosaveHomeOrganizationSettings(
        homeCountry: String,
        homeRegionOrganizationID: String,
        defaultFundManagerOrganizationID: String? = nil
    ) {
        var updated = editableMetadataSnapshot
        let canonicalCountry = GrantParsing.canonicalCountryName(homeCountry)
        updated.homeCountry = canonicalCountry.isEmpty
            || canonicalCountry.caseInsensitiveCompare(HomeOrganizationDefaults.homeCountry) == .orderedSame
            ? nil
            : canonicalCountry
        updated.homeRegionOrganizationID = homeRegionOrganizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        // nil = leave the default fund manager as it is; "" = none.
        if let defaultFundManagerOrganizationID {
            updated.defaultFundManagerOrganizationID = defaultFundManagerOrganizationID.trimmedOrNil
        }
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit home organization", "Redigera hemorganisation")
        )
    }

    func autosaveCalendarReminderSettings(_ settings: CalendarReminderSettings) {
        let normalized = settings.normalized()
        var updated = editableMetadataSnapshot
        updated.calendarReminderSettings = normalized == .standard ? nil : normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit reminder times", "Redigera påminnelsetider")
        )
    }

    func autosaveCalendarWorkingHours(_ settings: CalendarWorkingHoursSettings) {
        let normalized = settings.normalized()
        var updated = editableMetadataSnapshot
        updated.calendarWorkingHours = normalized == .standard ? nil : normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit working hours", "Redigera arbetstid")
        )
    }

    func autosaveCalendarCategoryBehaviors(_ settings: [CalendarCategoryBehaviorSetting]) {
        let normalized = CalendarCategoryBehaviorSetting.normalizedList(settings)
        var updated = editableMetadataSnapshot
        updated.calendarCategoryBehaviors = normalized
        guard updated != editableMetadataSnapshot else { return }
        persistMetadataSilently(
            updated,
            undoActionName: language.text("Edit calendar category settings", "Redigera inställningar för kalenderkategorier")
        )
    }
}
