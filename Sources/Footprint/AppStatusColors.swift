import AppKit
import SwiftUI

/// Round 16 (user decisions 2026-10-01): one colour source for every status in
/// the app. Each status maps to exactly one tone, everywhere (lists, detail
/// views, statistics, calendar, badges):
/// - done: finished with a positive result (green)
/// - pending: in progress or waiting for someone else (yellow)
/// - warning: needs the user's action soon (orange)
/// - negative: negative outcome or a passed deadline (red)
/// - inactive: nothing to do now: ended, withdrawn, declined, spent (grey)
/// - none: future without a status yet (no fill, "white")
/// - notOpen: like none, with paler text (calls not open yet)
/// Blue is no longer a status colour.
enum AppStatusTone: String, CaseIterable, Sendable {
    case done
    case pending
    case warning
    case negative
    case inactive
    case none
    case notOpen

    /// False for the two tones drawn without a fill.
    var hasFill: Bool {
        switch self {
        case .none, .notOpen: return false
        default: return true
        }
    }
}

private func statusHexNSColor(_ hex: Int) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

extension AppPalette {
    /// The fill for a status. Green, yellow and red follow the semantic colours
    /// chosen in Settings (light and dark); orange and grey are fixed. Clear for
    /// `none` and `notOpen`. Re-evaluated whenever light/dark mode changes.
    static func statusFill(_ tone: AppStatusTone) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in
            statusFillNSColor(tone, dark: AppAppearanceRegistry.usesDarkPalette())
        })
    }

    static func statusFillNSColor(_ tone: AppStatusTone, dark: Bool) -> NSColor {
        switch tone {
        case .done:
            return AppAppearanceRegistry.semanticColor(.positive, shaded: false, useDarkPalette: dark)
        case .pending:
            let color = AppAppearanceRegistry.semanticColor(.inProgress, shaded: false, useDarkPalette: dark)
            // The built-in dark yellow (#A97119) is too light for white text
            // (4.1:1); it is drawn slightly darker (#956212, 5.2:1).
            if dark, color.usingColorSpace(.sRGB).map({ Int(($0.redComponent * 255).rounded()) == 0xA9 && Int(($0.greenComponent * 255).rounded()) == 0x71 && Int(($0.blueComponent * 255).rounded()) == 0x19 }) == true {
                return statusHexNSColor(0x956212)
            }
            return color
        case .warning:
            return statusHexNSColor(dark ? 0xB5541A : 0xF5B971)
        case .negative:
            return AppAppearanceRegistry.semanticColor(.negative, shaded: false, useDarkPalette: dark)
        case .inactive:
            return statusHexNSColor(dark ? 0x4A5058 : 0xD9DCDF)
        case .none, .notOpen:
            return .clear
        }
    }

    /// Text and symbols drawn on a status fill: dark in light mode, white in
    /// dark mode (at least 4.5:1 on every fill).
    static var statusOnFill: Color {
        Color(nsColor: NSColor(name: nil) { _ in
            AppAppearanceRegistry.usesDarkPalette() ? .white : statusHexNSColor(0x1F2328)
        })
    }

    /// Text and symbols in a status colour on the ordinary background (never
    /// the pale fill colours, which are too light to read as text).
    static func statusText(_ tone: AppStatusTone) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in
            statusTextNSColor(tone, dark: AppAppearanceRegistry.usesDarkPalette())
        })
    }

    static func statusTextNSColor(_ tone: AppStatusTone, dark: Bool) -> NSColor {
        switch tone {
        case .done: return statusHexNSColor(dark ? 0x7FD1B9 : 0x2F6B3B)
        case .pending: return statusHexNSColor(dark ? 0xE8C35A : 0x7A5C00)
        case .warning: return statusHexNSColor(dark ? 0xF2A65A : 0x9A4A00)
        case .negative: return statusHexNSColor(dark ? 0xF28B82 : 0xA3341E)
        case .inactive: return statusHexNSColor(dark ? 0xA3AAB2 : 0x5B6168)
        case .none: return statusHexNSColor(dark ? 0xE6E8EA : 0x1F2328)
        case .notOpen: return statusHexNSColor(dark ? 0x8B939A : 0x6E747A)
        }
    }

    /// The "today" line in timelines and the calendar.
    static var todayMarker: Color { statusText(.negative) }
}
