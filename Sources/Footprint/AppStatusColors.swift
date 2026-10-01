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

// MARK: - Round 17: edges, marks, pale fills and "late"

/// The sRGB value of a colour as 0xRRGGBB, or nil when it cannot be converted.
private func statusHexValue(_ color: NSColor) -> Int? {
    guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
    let red = Int((srgb.redComponent * 255).rounded())
    let green = Int((srgb.greenComponent * 255).rounded())
    let blue = Int((srgb.blueComponent * 255).rounded())
    return (red << 16) | (green << 8) | blue
}

/// Mixes a colour with black (light mode) or white (dark mode).
private func statusShiftedNSColor(_ color: NSColor, towardWhite: Bool, amount: CGFloat) -> NSColor {
    guard let srgb = color.usingColorSpace(.sRGB) else { return color }
    func shift(_ value: CGFloat) -> CGFloat {
        towardWhite ? value + (1 - value) * amount : value * (1 - amount)
    }
    return NSColor(
        srgbRed: shift(srgb.redComponent),
        green: shift(srgb.greenComponent),
        blue: shift(srgb.blueComponent),
        alpha: 1
    )
}

extension AppPalette {
    /// Circle borders and connecting lines in timelines: only slightly
    /// darker (light mode) or lighter (dark mode) than the fill, so yellow
    /// never turns brown. When the user changed a semantic colour in
    /// Settings, the edge is derived from that fill instead of the fixed value.
    static func statusEdge(_ tone: AppStatusTone) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in
            statusEdgeNSColor(tone, dark: AppAppearanceRegistry.usesDarkPalette())
        })
    }

    static func statusEdgeNSColor(_ tone: AppStatusTone, dark: Bool) -> NSColor {
        // The built-in fill(s) of the tone and the edge drawn with them.
        let builtInFills: [Int]
        let builtInEdge: Int
        switch tone {
        case .done:
            builtInFills = dark ? [0x115651] : [0xB6D8A6]
            builtInEdge = dark ? 0x2C7D75 : 0x8DBF78
        case .pending:
            builtInFills = dark ? [0xA97119, 0x956212] : [0xF1E08C]
            builtInEdge = dark ? 0xB8892C : 0xD6BF55
        case .negative:
            builtInFills = dark ? [0x97141D] : [0xF0926C]
            builtInEdge = dark ? 0xB8343A : 0xDB7350
        case .warning:
            return statusHexNSColor(dark ? 0xD06A2C : 0xE59A4C)
        case .inactive, .none, .notOpen:
            return statusHexNSColor(dark ? 0x636A73 : 0xB9BEC3)
        }
        let fill = statusFillNSColor(tone, dark: dark)
        if let value = statusHexValue(fill), builtInFills.contains(value) {
            return statusHexNSColor(builtInEdge)
        }
        // A colour changed in Settings: ~12 % darker (light) or lighter (dark).
        return statusShiftedNSColor(fill, towardWhite: dark, amount: 0.12)
    }

    /// Small marks (icons, dots, thin stripes): between the fill and the
    /// text colour, so the hue stays clearly green, yellow, orange or red.
    static func statusMark(_ tone: AppStatusTone) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in
            statusMarkNSColor(tone, dark: AppAppearanceRegistry.usesDarkPalette())
        })
    }

    static func statusMarkNSColor(_ tone: AppStatusTone, dark: Bool) -> NSColor {
        switch tone {
        case .done: return statusHexNSColor(dark ? 0x4FB39A : 0x5FA35A)
        case .pending: return statusHexNSColor(dark ? 0xE0B13E : 0xD4AE1F)
        case .warning: return statusHexNSColor(dark ? 0xF08A3A : 0xE5862B)
        case .negative: return statusHexNSColor(dark ? 0xEE6A5F : 0xDE5A3F)
        case .inactive, .none: return statusHexNSColor(dark ? 0x8B939A : 0x9AA0A6)
        case .notOpen: return statusHexNSColor(dark ? 0x6E747A : 0xB9BEC3)
        }
    }

    /// A paler version of a status fill, used for granted funds that are
    /// fully spent (still green, but quieter than a grant with money left).
    static func statusFillPale(_ tone: AppStatusTone) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in
            statusFillPaleNSColor(tone, dark: AppAppearanceRegistry.usesDarkPalette())
        })
    }

    static func statusFillPaleNSColor(_ tone: AppStatusTone, dark: Bool) -> NSColor {
        if tone == .done {
            let fill = statusFillNSColor(.done, dark: dark)
            if let value = statusHexValue(fill), value == (dark ? 0x115651 : 0xB6D8A6) {
                return statusHexNSColor(dark ? 0x0D3F3B : 0xDCEBD3)
            }
        }
        guard tone.hasFill else { return .clear }
        // Light: halfway to white. Dark: a quarter of the way to black.
        let fill = statusFillNSColor(tone, dark: dark)
        guard let srgb = fill.usingColorSpace(.sRGB) else { return fill }
        func pale(_ value: CGFloat) -> CGFloat {
            dark ? value * 0.75 : value + (1 - value) * 0.5
        }
        return NSColor(srgbRed: pale(srgb.redComponent), green: pale(srgb.greenComponent), blue: pale(srgb.blueComponent), alpha: 1)
    }

    /// Overdue tasks and reminders: a strong red-orange mark (dots, stripes).
    static var lateMark: Color {
        Color(nsColor: NSColor(name: nil) { _ in
            lateMarkNSColor(dark: AppAppearanceRegistry.usesDarkPalette())
        })
    }

    static func lateMarkNSColor(dark: Bool) -> NSColor {
        statusHexNSColor(dark ? 0xF2703A : 0xE8551F)
    }

    /// Text for overdue tasks on the ordinary background.
    static var lateText: Color {
        Color(nsColor: NSColor(name: nil) { _ in
            lateTextNSColor(dark: AppAppearanceRegistry.usesDarkPalette())
        })
    }

    static func lateTextNSColor(dark: Bool) -> NSColor {
        statusHexNSColor(dark ? 0xFF9C63 : 0xB8400F)
    }
}
