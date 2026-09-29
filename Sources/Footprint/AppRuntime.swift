import Foundation

enum AppChromeStyle: String {
    case classic
    case renewed
}

enum AppPackageMode: String, CaseIterable {
    case development
    case localBootstrap = "local-bootstrap"
    case selfContained = "self-contained"
    case journalsOnly = "journals-only"
    case share

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .development:
            return language.text("Development", "Utveckling")
        case .localBootstrap:
            return language.text("Local bootstrap", "Lokal bootstrap")
        case .selfContained:
            return language.text("Self-contained", "Fristående paket")
        case .journalsOnly:
            return language.text("Journals only", "Endast tidskrifter")
        case .share:
            return language.text("Share mode", "Delningsläge")
        }
    }

    func detail(_ language: AppLanguage) -> String {
        switch self {
        case .development:
            return language.text("Runs with the current development configuration.", "Kör med den aktuella utvecklingskonfigurationen.")
        case .localBootstrap:
            return language.text("Initial data can be copied from another local Footprint storage folder.", "Initial data kan kopieras från en annan lokal Footprint-datamapp.")
        case .selfContained:
            return language.text("Uses only bundled data and its own live storage folder.", "Använder bara bundlad data och sin egen lagringsmapp.")
        case .journalsOnly:
            return language.text("Starts as a journals-only app with isolated storage.", "Startar som en tidskriftsapp med isolerad lagring.")
        case .share:
            return language.text("Runs in share mode with restricted writable data.", "Kör i delningsläge med begränsad skrivbar data.")
        }
    }
}

struct AppPackageIdentity: Equatable {
    let displayName: String
    let bundleIdentifier: String
    let defaultsPrefix: String
    let storageFolderName: String
    let bootstrapSourceFolderName: String?
    let isShareMode: Bool
    let mode: AppPackageMode
}

enum AppRuntime {
    #if DEBUG
    nonisolated(unsafe) static var chromeStyleOverrideForTesting: AppChromeStyle?
    #endif

    static var displayName: String {
        infoString(forKey: "FootprintAppName") ?? "Footprint"
    }

    static var defaultsPrefix: String {
        infoString(forKey: "FootprintDefaultsPrefix")
            ?? Bundle.main.bundleIdentifier
            ?? "com.codex.footprint"
    }

    static var visualModeDefaultsKey: String {
        scopedDefaultsKey("VisualModePreference")
    }

    static var sentReminderDefaultsKey: String {
        scopedDefaultsKey("SentGrantReminderIDs")
    }

    static var scheduledReminderDefaultsKey: String {
        scopedDefaultsKey("ScheduledGrantReminderIDs")
    }

    static var scheduledCalendarTaskReminderDefaultsKey: String {
        scopedDefaultsKey("ScheduledCalendarTaskReminderIDs")
    }

    static var calendarTaskRemindersEnabledDefaultsKey: String {
        scopedDefaultsKey("CalendarTaskRemindersEnabled")
    }

    static var legacyNotificationMigrationDefaultsKey: String {
        scopedDefaultsKey("LegacyNotificationMigrationV1")
    }

    static var mainWindowAutosaveName: String {
        infoString(forKey: "FootprintWindowAutosaveName") ?? scopedDefaultsKey("MainWindow")
    }

    static var storageFolderName: String {
        infoString(forKey: "FootprintStorageFolderName")
            ?? (isShareMode ? "Footprint Share" : "Footprint")
    }

    static var bootstrapSourceFolderName: String? {
        infoString(forKey: "FootprintBootstrapSourceFolderName")
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.codex.footprint"
    }

    static var isShareMode: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "FootprintShareMode") as? Bool) ?? false
    }

    static var packageMode: AppPackageMode {
        inferPackageMode(
            explicitModeRaw: infoString(forKey: "FootprintPackageMode"),
            isShareMode: isShareMode,
            storageFolderName: storageFolderName,
            bootstrapSourceFolderName: bootstrapSourceFolderName,
            defaultsPrefix: defaultsPrefix
        )
    }

    static var packageIdentity: AppPackageIdentity {
        AppPackageIdentity(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            defaultsPrefix: defaultsPrefix,
            storageFolderName: storageFolderName,
            bootstrapSourceFolderName: bootstrapSourceFolderName,
            isShareMode: isShareMode,
            mode: packageMode
        )
    }

    static var chromeStyle: AppChromeStyle {
        #if DEBUG
        if let chromeStyleOverrideForTesting {
            return chromeStyleOverrideForTesting
        }
        #endif
        guard let raw = infoString(forKey: "FootprintChromeStyle"),
              let style = AppChromeStyle(rawValue: raw) else {
            return .classic
        }
        return style
    }

    static var usesRenewedChrome: Bool {
        chromeStyle == .renewed
    }

    static var showsLayoutDiagnostics: Bool {
        UserDefaults.standard.bool(forKey: scopedDefaultsKey("ShowLayoutDiagnostics"))
    }

    static func scopedDefaultsKey(_ key: String) -> String {
        "\(defaultsPrefix).\(key)"
    }

    static func inferPackageMode(
        explicitModeRaw: String?,
        isShareMode: Bool,
        storageFolderName: String,
        bootstrapSourceFolderName: String?,
        defaultsPrefix: String
    ) -> AppPackageMode {
        if let explicitModeRaw,
           let explicit = AppPackageMode(rawValue: explicitModeRaw) {
            return explicit
        }
        if isShareMode {
            return .share
        }

        let normalizedStorage = storageFolderName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if bootstrapSourceFolderName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return .localBootstrap
        }
        if !normalizedStorage.isEmpty {
            return .selfContained
        }
        return .development
    }

    private static func infoString(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
