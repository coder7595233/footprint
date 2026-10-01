import AppKit
import QuartzCore
import SwiftUI

// MARK: - Dynamic Appearance

private extension NSAppearance {
    var usesDarkPalette: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

func currentVisualModePreference() -> AppVisualMode? {
    UserDefaults.standard.string(forKey: AppRuntime.visualModeDefaultsKey).flatMap(AppVisualMode.init(rawValue:))
}

@MainActor
enum AppFocusPulse {
    static let layerName = "FootprintKeyboardFocusPulse"

    static func setFocused(
        _ isFocused: Bool,
        on view: NSView,
        cornerRadius: CGFloat = AppPalette.smallCornerRadius
    ) {
        view.wantsLayer = true
        guard let hostLayer = view.layer else { return }

        let focusLayer: CAShapeLayer
        if let existing = hostLayer.sublayers?.first(where: { $0.name == layerName }) as? CAShapeLayer {
            focusLayer = existing
        } else {
            focusLayer = CAShapeLayer()
            focusLayer.name = layerName
            focusLayer.fillColor = NSColor.clear.cgColor
            focusLayer.strokeColor = NSColor(AppPalette.linkAction).cgColor
            focusLayer.lineWidth = 1
            focusLayer.zPosition = 10_000
            hostLayer.addSublayer(focusLayer)
        }

        updateLayout(on: view, cornerRadius: cornerRadius)
        focusLayer.isHidden = !isFocused
        focusLayer.removeAnimation(forKey: "focusPulse")
        guard isFocused else { return }

        focusLayer.opacity = 1
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.55
        pulse.toValue = 1.0
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        focusLayer.add(pulse, forKey: "focusPulse")
    }

    static func updateLayout(
        on view: NSView,
        cornerRadius: CGFloat = AppPalette.smallCornerRadius
    ) {
        guard let focusLayer = view.layer?.sublayers?.first(where: { $0.name == layerName }) as? CAShapeLayer else {
            return
        }
        focusLayer.frame = view.bounds
        focusLayer.path = CGPath(
            roundedRect: view.bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: max(0, cornerRadius - 0.5),
            cornerHeight: max(0, cornerRadius - 0.5),
            transform: nil
        )
    }
}

private struct AppKeyboardFocusPulseModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseIsBright = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppPalette.linkAction, lineWidth: 1)
                    .opacity(focusOpacity)
                    .allowsHitTesting(false)
            }
            .onAppear { updatePulse(isFocused: isFocused) }
            .onChange(of: isFocused) { _, focused in
                updatePulse(isFocused: focused)
            }
            .animation(
                isFocused && !reduceMotion
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .linear(duration: 0.1),
                value: pulseIsBright
            )
    }

    private var focusOpacity: Double {
        guard isFocused else { return 0 }
        if reduceMotion { return 1 }
        return pulseIsBright ? 1 : 0.55
    }

    private func updatePulse(isFocused: Bool) {
        pulseIsBright = false
        guard isFocused, !reduceMotion else { return }
        DispatchQueue.main.async {
            pulseIsBright = true
        }
    }
}

struct AppFieldFocusPreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct AppDirectFieldFocusReporterModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .preference(key: AppFieldFocusPreferenceKey.self, value: isFocused)
    }
}

private struct AppTextInputFocusChromeModifier: ViewModifier {
    @State private var descendantIsFocused = false

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(AppFieldFocusPreferenceKey.self) { focused in
                descendantIsFocused = focused
            }
            .appKeyboardFocusPulse(isFocused: descendantIsFocused)
    }
}

extension View {
    func appKeyboardFocusPulse(
        isFocused: Bool,
        cornerRadius: CGFloat = AppPalette.smallCornerRadius
    ) -> some View {
        modifier(AppKeyboardFocusPulseModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}

enum AppUIDensity: String, CaseIterable, Identifiable {
    case comfortable

    var id: String { rawValue }

    var scale: CGFloat { 1.0 }

    func title(language: AppLanguage) -> String {
        language.text("Comfortable", "Bekväm")
    }
}

enum AppDensityRegistry {
    static func current() -> AppUIDensity {
        .comfortable
    }
}

private func hexColor(_ hex: Int) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255
    let green = CGFloat((hex >> 8) & 0xFF) / 255
    let blue = CGFloat(hex & 0xFF) / 255
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
}

private func shaded(_ color: NSColor, by fraction: CGFloat) -> NSColor {
    color.blended(withFraction: fraction, of: .black) ?? color
}

private func contrastingTextColor(for color: NSColor) -> NSColor {
    let converted = color.usingColorSpace(.deviceRGB) ?? color
    let luminance = (0.299 * converted.redComponent) + (0.587 * converted.greenComponent) + (0.114 * converted.blueComponent)
    return luminance < 0.58 ? .white : .black
}

func dynamicColor(light: NSColor, dark: NSColor, lightClean: NSColor? = nil, darkClean: NSColor? = nil, darkNew: NSColor? = nil) -> Color {
    Color(
        nsColor: NSColor(name: nil) { appearance in
            switch currentVisualModePreference() {
            case .lightClean:
                return lightClean ?? light
            case .darkClean:
                return darkClean ?? dark
            case .darkNew:
                return darkNew ?? darkClean ?? dark
            case .light:
                return light
            case .dark:
                return dark
            case nil:
                return appearance.usesDarkPalette ? dark : light
            }
        }
    )
}

func chromeDynamicColor(
    light: NSColor,
    dark: NSColor,
    lightClean: NSColor? = nil,
    darkClean: NSColor? = nil,
    darkNew: NSColor? = nil,
    renewedLight: NSColor,
    renewedDark: NSColor,
    contrastRenewedLight: NSColor? = nil,
    contrastRenewedDark: NSColor? = nil
) -> Color {
    Color(
        nsColor: NSColor(name: nil) { appearance in
            if AppRuntime.usesRenewedChrome {
                let prefersDark: Bool
                switch currentVisualModePreference() {
                case .dark, .darkClean, .darkNew:
                    prefersDark = true
                case .light, .lightClean:
                    prefersDark = false
                case nil:
                    prefersDark = appearance.usesDarkPalette
                }
                let scheme = AppAppearanceRegistry.chromeScheme()
                let resolvedLight = scheme == .contrast ? (contrastRenewedLight ?? renewedLight) : renewedLight
                let resolvedDark = scheme == .contrast ? (contrastRenewedDark ?? renewedDark) : renewedDark
                return prefersDark ? resolvedDark : resolvedLight
            }

            switch currentVisualModePreference() {
            case .lightClean:
                return lightClean ?? light
            case .darkClean:
                return darkClean ?? dark
            case .darkNew:
                return darkNew ?? darkClean ?? dark
            case .light:
                return light
            case .dark:
                return dark
            case nil:
                return appearance.usesDarkPalette ? dark : light
            }
        }
    )
}

enum AppChromeSurface: CaseIterable, Hashable {
    case menu
    case list
    case workspace
    case calendar
    case calendarFilter
    case calendarHeader
    case calendarWorkspace
    case calendarDayRow
}

extension AppChromeScheme {
    func builtInNSColor(for surface: AppChromeSurface, useDarkAppearance: Bool) -> NSColor {
        switch (self, surface, useDarkAppearance) {
        case (.standard, .menu, false):
            return hexColor(0xF7F9F5)
        case (.standard, .list, false), (.standard, .calendarFilter, false), (.standard, .calendarHeader, false):
            return NSColor(calibratedRed: 0.91, green: 0.925, blue: 0.905, alpha: 1)
        case (.standard, .workspace, false), (.standard, .calendar, false), (.standard, .calendarWorkspace, false):
            return NSColor(calibratedRed: 0.985, green: 0.985, blue: 0.975, alpha: 1)
        case (.standard, .calendarDayRow, false):
            return NSColor(calibratedWhite: 1.0, alpha: 1)
        case (.standard, .menu, true):
            return hexColor(0x0E1012)
        case (.standard, .list, true), (.standard, .calendarFilter, true), (.standard, .calendarHeader, true):
            return hexColor(0x0E1012)
        case (.standard, .workspace, true), (.standard, .calendar, true), (.standard, .calendarWorkspace, true):
            return hexColor(0x0B0D0F)
        case (.standard, .calendarDayRow, true):
            return hexColor(0x1F2327)
        case (.contrast, .menu, false):
            return hexColor(0xFBFCFA)
        case (.contrast, .list, false), (.contrast, .calendarFilter, false), (.contrast, .calendarHeader, false):
            return NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.91, alpha: 1)
        case (.contrast, .workspace, false), (.contrast, .calendar, false), (.contrast, .calendarWorkspace, false), (.contrast, .calendarDayRow, false):
            return NSColor(calibratedWhite: 1.0, alpha: 1)
        case (.contrast, .menu, true):
            return hexColor(0x040608)
        case (.contrast, .list, true), (.contrast, .calendarFilter, true), (.contrast, .calendarHeader, true):
            return hexColor(0x0E141A)
        case (.contrast, .workspace, true), (.contrast, .calendar, true), (.contrast, .calendarWorkspace, true):
            return hexColor(0x171D24)
        case (.contrast, .calendarDayRow, true):
            return hexColor(0x1F2327)
        }
    }

    func nsColor(for surface: AppChromeSurface, useDarkAppearance: Bool) -> NSColor {
        AppAppearanceRegistry.chromeColor(for: self, surface: surface, useDarkAppearance: useDarkAppearance)
    }

    func color(for surface: AppChromeSurface, useDarkAppearance: Bool) -> Color {
        Color(nsColor: nsColor(for: surface, useDarkAppearance: useDarkAppearance))
    }
}

extension AppChromeModeColorSettings {
    func explicitHex(for surface: AppChromeSurface) -> String? {
        switch surface {
        case .menu:
            return menuHex
        case .list:
            return listHex
        case .workspace:
            return workspaceHex
        case .calendar:
            return calendarHex
        case .calendarFilter:
            return calendarFilterHex
        case .calendarHeader:
            return calendarHeaderHex
        case .calendarWorkspace:
            return calendarWorkspaceHex ?? calendarHex
        case .calendarDayRow:
            return calendarDayRowHex
        }
    }

    func hex(for surface: AppChromeSurface) -> String {
        switch surface {
        case .menu:
            return menuHex
        case .list:
            return listHex
        case .workspace:
            return workspaceHex
        case .calendar:
            return calendarHex ?? workspaceHex
        case .calendarFilter:
            return calendarFilterHex ?? listHex
        case .calendarHeader:
            return calendarHeaderHex ?? listHex
        case .calendarWorkspace:
            return calendarWorkspaceHex ?? calendarHex ?? workspaceHex
        case .calendarDayRow:
            return calendarDayRowHex ?? workspaceHex
        }
    }

    mutating func setHex(_ value: String, for surface: AppChromeSurface) {
        switch surface {
        case .menu:
            menuHex = value
        case .list:
            listHex = value
        case .workspace:
            workspaceHex = value
        case .calendar:
            calendarHex = value
        case .calendarFilter:
            calendarFilterHex = value
        case .calendarHeader:
            calendarHeaderHex = value
        case .calendarWorkspace:
            calendarWorkspaceHex = value
        case .calendarDayRow:
            calendarDayRowHex = value
        }
    }
}

extension AppChromeColorSettings {
    func colors(for scheme: AppChromeScheme, useDarkAppearance: Bool) -> AppChromeModeColorSettings {
        switch (scheme, useDarkAppearance) {
        case (.standard, false):
            return standardLight
        case (.standard, true):
            return standardDark
        case (.contrast, false):
            return contrastLight
        case (.contrast, true):
            return contrastDark
        }
    }

    mutating func setColors(_ value: AppChromeModeColorSettings, for scheme: AppChromeScheme, useDarkAppearance: Bool) {
        switch (scheme, useDarkAppearance) {
        case (.standard, false):
            standardLight = value
        case (.standard, true):
            standardDark = value
        case (.contrast, false):
            contrastLight = value
        case (.contrast, true):
            contrastDark = value
        }
    }

    func hex(for scheme: AppChromeScheme, surface: AppChromeSurface, useDarkAppearance: Bool) -> String {
        let colors = colors(for: scheme, useDarkAppearance: useDarkAppearance)
        if let explicitHex = colors.explicitHex(for: surface) {
            return explicitHex
        }

        switch surface {
        case .menu:
            return colors.menuHex
        case .list:
            return colors.listHex
        case .workspace:
            return colors.workspaceHex
        case .calendar, .calendarWorkspace:
            return colors.calendarHex ?? colors.workspaceHex
        case .calendarFilter, .calendarHeader:
            return colors.listHex
        case .calendarDayRow:
            return Self.builtIn.colors(for: scheme, useDarkAppearance: useDarkAppearance).calendarDayRowHex
                ?? (useDarkAppearance ? "#1F2327" : "#FFFFFF")
        }
    }
}

extension AppFontFamily {
    var swiftUIDesign: Font.Design {
        switch self {
        case .system:
            return .default
        case .rounded:
            return .rounded
        case .serif:
            return .serif
        case .monospaced:
            return .monospaced
        }
    }
}

extension AppFontWeightSetting {
    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular:
            return .regular
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }

    var nsFontWeight: NSFont.Weight {
        switch self {
        case .regular:
            return .regular
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }
}

private extension AppFontFamily {
    var appKitDesign: NSFontDescriptor.SystemDesign? {
        switch self {
        case .system:
            return nil
        case .rounded:
            return .rounded
        case .serif:
            return .serif
        case .monospaced:
            return .monospaced
        }
    }
}

// MARK: - Theme Registry

private extension AppTypographySettings {
    func style(for role: AppTypographyRole) -> AppTextStyleSetting {
        switch role {
        case .pageTitle: return pageTitle
        case .sectionTitle: return sectionTitle
        case .panelTitle: return panelTitle
        case .tableHeader: return tableHeader
        case .fieldLabel: return fieldLabel
        case .body: return body
        case .secondary: return secondary
        case .statTitle: return statTitle
        case .statValue: return statValue
        }
    }
}

private extension AppSemanticColorSettings {
    func tone(for semanticTone: AppSemanticTone) -> AppSemanticToneSetting {
        switch semanticTone {
        case .negative: return negative
        case .inProgress: return inProgress
        case .positive: return positive
        case .neutral: return neutral
        }
    }
}

private func normalizedHexString(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return fallback }
    let cleaned = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    guard cleaned.count == 6, cleaned.allSatisfy({ $0.isHexDigit }) else { return fallback }
    return "#\(cleaned.uppercased())"
}

private func nsColor(hexString value: String, fallback: Int) -> NSColor {
    let normalized = normalizedHexString(value, fallback: String(format: "#%06X", fallback))
    let hexPart = normalized.dropFirst()
    guard let intValue = Int(hexPart, radix: 16) else { return hexColor(fallback) }
    return hexColor(intValue)
}

final class AppAppearanceRegistry {
    nonisolated(unsafe) private static var typographySettings: AppTypographySettings = .runtimeDefault
    nonisolated(unsafe) private static var semanticColorSettingsLight: AppSemanticColorSettings = .default
    nonisolated(unsafe) private static var semanticColorSettingsDark: AppSemanticColorSettings = .darkDefault
    nonisolated(unsafe) private static var chromeSchemeSetting: AppChromeScheme = .standard
    nonisolated(unsafe) private static var chromeColorSettings: AppChromeColorSettings?
    nonisolated(unsafe) private static var systemUsesDarkPalette = false

    static func update(from metadata: DataSourceMetadata) {
        typographySettings = metadata.appTypography ?? .runtimeDefault
        semanticColorSettingsLight = metadata.appSemanticColorsLight ?? .default
        semanticColorSettingsDark = metadata.appSemanticColorsDark ?? .darkDefault
        chromeSchemeSetting = AppChromeScheme(rawValue: metadata.appChromeScheme ?? "") ?? .standard
        chromeColorSettings = metadata.appChromeColors
    }

    @MainActor
    static func updateSystemAppearancePreference() {
        systemUsesDarkPalette = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func typography() -> AppTypographySettings {
        typographySettings
    }

    static func chromeScheme() -> AppChromeScheme {
        chromeSchemeSetting
    }

    static func chromeColor(
        for scheme: AppChromeScheme,
        surface: AppChromeSurface,
        useDarkAppearance: Bool
    ) -> NSColor {
        if let hex = chromeColorSettings?.hex(for: scheme, surface: surface, useDarkAppearance: useDarkAppearance) {
            return nsColor(hexString: hex, fallback: 0x000000)
        }
        return scheme.builtInNSColor(for: surface, useDarkAppearance: useDarkAppearance)
    }

    static func semanticColors(light: Bool) -> AppSemanticColorSettings {
        light ? semanticColorSettingsLight : semanticColorSettingsDark
    }

    static func usesDarkPalette() -> Bool {
        switch currentVisualModePreference() {
        case .dark, .darkClean, .darkNew:
            return true
        case .light, .lightClean:
            return false
        case nil:
            return systemUsesDarkPalette
        }
    }

    static func font(for role: AppTypographyRole) -> Font {
        let style = typographySettings.style(for: role)
        let size = max(12, style.size)
        return .system(size: size, weight: style.weight.swiftUIWeight, design: style.family.swiftUIDesign)
    }

    static func semanticColor(_ tone: AppSemanticTone, shaded: Bool, useDarkPalette: Bool) -> NSColor {
        let setting = (useDarkPalette ? semanticColorSettingsDark : semanticColorSettingsLight).tone(for: tone)
        let fallback: Int
        switch (tone, shaded, useDarkPalette) {
        case (.negative, false, false): fallback = 0xF0926C
        case (.negative, true, false): fallback = 0xF1BB93
        case (.inProgress, false, false): fallback = 0xF1E08C
        case (.inProgress, true, false): fallback = 0xFFEFBD
        case (.positive, false, false): fallback = 0xB6D8A6
        case (.positive, true, false): fallback = 0xADDDC6
        case (.neutral, false, false): fallback = 0xA1D1E6
        case (.neutral, true, false): fallback = 0xB5DBED
        case (.negative, false, true): fallback = 0x97141D
        case (.negative, true, true): fallback = 0xAB2D32
        case (.inProgress, false, true): fallback = 0xA97119
        case (.inProgress, true, true): fallback = 0xD4A639
        case (.positive, false, true): fallback = 0x115651
        case (.positive, true, true): fallback = 0x306F69
        case (.neutral, false, true): fallback = 0x124680
        case (.neutral, true, true): fallback = 0x3A72B3
        }
        return nsColor(hexString: shaded ? setting.shadeHex : setting.solidHex, fallback: fallback)
    }

    static func semanticColor(_ tone: AppSemanticTone, shaded: Bool) -> NSColor {
        semanticColor(tone, shaded: shaded, useDarkPalette: usesDarkPalette())
    }
}

func appFont(_ role: AppTypographyRole) -> Font {
    AppAppearanceRegistry.font(for: role)
}

func appNSFont(_ role: AppTypographyRole) -> NSFont {
    let style = AppAppearanceRegistry.typography().style(for: role)
    let size = max(12, style.size)
    let baseFont = NSFont.systemFont(ofSize: size, weight: style.weight.nsFontWeight)
    guard let design = style.family.appKitDesign,
          let descriptor = baseFont.fontDescriptor.withDesign(design),
          let designedFont = NSFont(descriptor: descriptor, size: size) else {
        return baseFont
    }
    return designedFont
}

/// Keeps the active app typeface while giving numeric dates tabular figures.
/// This is less visually disruptive than switching the whole date to a
/// monospaced typeface, and still makes every digit occupy the same width.
func appDateNSFont(_ role: AppTypographyRole = .body) -> NSFont {
    let baseFont = appNSFont(role)
    let descriptor = baseFont.fontDescriptor.addingAttributes([
        .featureSettings: [[
            kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
            kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector
        ]]
    ])
    return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
}

// MARK: - View Chrome

extension View {
    @ViewBuilder
    func appTypography(_ role: AppTypographyRole) -> some View {
        switch role {
        case .fieldLabel:
            self
                .font(appFont(role))
                .foregroundStyle(AppPalette.appText)
                .padding(.leading, AppPalette.fieldHorizontalPadding)
        default:
            self.font(appFont(role))
        }
    }

    func appTextInputChrome(
        horizontalPadding: CGFloat = AppPalette.textFieldHorizontalPadding,
        verticalPadding: CGFloat = AppPalette.textFieldVerticalPadding,
        minHeight: CGFloat = AppPalette.fieldMinHeight,
        fillsWidth: Bool = true,
        fill: Color = AppPalette.fieldSurface,
        stroke: Color = AppPalette.subtleBorder,
        tracksFocus: Bool = true
    ) -> some View {
        if AppRuntime.usesRenewedChrome {
            return AnyView(
                self
                    .textFieldStyle(.plain)
                    .appFormTabRouting()
                    .modifier(AppDirectFieldFocusReporterModifier(), enabled: tracksFocus)
                    .appFieldChrome(
                        minHeight: minHeight,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        fillsWidth: fillsWidth,
                        fill: fill,
                        stroke: stroke
                    )
                    .modifier(AppTextInputFocusChromeModifier())
            )
        }
        return AnyView(
            self
                .textFieldStyle(.roundedBorder)
                .appFormTabRouting()
        )
    }

    func appMenuChrome(
        horizontalPadding: CGFloat = AppPalette.textFieldHorizontalPadding,
        verticalPadding: CGFloat = AppPalette.textFieldVerticalPadding,
        minHeight: CGFloat = AppPalette.fieldMinHeight,
        fillsWidth: Bool = true,
        fill: Color = AppPalette.fieldSurface,
        stroke: Color = AppPalette.subtleBorder
    ) -> some View {
        if AppRuntime.usesRenewedChrome {
            return AnyView(
                self
                    .appFieldChrome(
                        minHeight: minHeight,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        fillsWidth: fillsWidth,
                        fill: fill,
                        stroke: stroke
                    )
            )
        }
        return AnyView(self)
    }

    func appCheckboxStyle() -> some View {
        AnyView(
            toggleStyle(AppCheckboxToggleStyle())
        )
    }

    func appFieldChrome(
        minHeight: CGFloat = AppPalette.fieldMinHeight,
        horizontalPadding: CGFloat = AppPalette.fieldHorizontalPadding,
        verticalPadding: CGFloat = AppPalette.fieldVerticalPadding,
        fillsWidth: Bool = true,
        fill: Color = AppPalette.fieldSurface,
        stroke: Color = AppPalette.subtleBorder
    ) -> some View {
        modifier(
            AppFieldChromeModifier(
                minHeight: minHeight,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                fillsWidth: fillsWidth,
                fill: fill,
                stroke: stroke
            )
        )
    }

    func appFieldChrome(
        state: AppFieldVisualState,
        minHeight: CGFloat = AppPalette.fieldMinHeight,
        horizontalPadding: CGFloat = AppPalette.fieldHorizontalPadding,
        verticalPadding: CGFloat = AppPalette.fieldVerticalPadding,
        fillsWidth: Bool = true
    ) -> some View {
        appFieldChrome(
            minHeight: minHeight,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            fillsWidth: fillsWidth,
            fill: state.fill,
            stroke: state.stroke
        )
        .help(state.helpText ?? "")
    }
}

private extension View {
    @ViewBuilder
    func modifier<M: ViewModifier>(_ modifier: M, enabled: Bool) -> some View {
        if enabled {
            self.modifier(modifier)
        } else {
            self
        }
    }
}

private struct AppCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        AppFocusableCheckboxRow(
            isOn: Binding(
                get: { configuration.isOn },
                set: { configuration.isOn = $0 }
            ),
            label: configuration.label
        )
    }
}

private struct AppFocusableCheckboxRow<Label: View>: View {
    @Binding var isOn: Bool
    let label: Label

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AppFocusableCheckboxControl(isOn: $isOn)
                .frame(width: 18, height: 18)
            label
                .contentShape(Rectangle())
                .onTapGesture {
                    isOn.toggle()
                }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AppFocusableCheckboxControl: NSViewRepresentable {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(isOn: $isOn)
    }

    func makeNSView(context: Context) -> CheckboxContainerView {
        let button = FocusableCheckboxButton(
            checkboxWithTitle: "",
            target: context.coordinator,
            action: #selector(Coordinator.checkboxChanged(_:))
        )
        button.title = ""
        button.allowsMixedState = false
        button.setButtonType(.switch)
        button.controlSize = .regular
        button.focusRingType = .default
        button.translatesAutoresizingMaskIntoConstraints = false
        return CheckboxContainerView(button: button)
    }

    func updateNSView(_ container: CheckboxContainerView, context: Context) {
        context.coordinator.isOn = $isOn
        container.button.state = isOn ? .on : .off
        container.button.isEnabled = isEnabled
        container.button.appearance = NSAppearance.currentDrawing()
    }

    @MainActor
    final class Coordinator: NSObject {
        var isOn: Binding<Bool>

        init(isOn: Binding<Bool>) {
            self.isOn = isOn
        }

        @objc func checkboxChanged(_ sender: NSButton) {
            isOn.wrappedValue = sender.state == .on
        }
    }

    final class FocusableCheckboxButton: NSButton {
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted {
                AppFocusPulse.setFocused(true, on: self, cornerRadius: 4)
            }
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted {
                AppFocusPulse.setFocused(false, on: self, cornerRadius: 4)
            }
            return accepted
        }

        override func layout() {
            super.layout()
            AppFocusPulse.updateLayout(on: self, cornerRadius: 4)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 48 {
                interpretKeyEvents([event])
                return
            }
            if event.keyCode == 49 {
                performClick(nil)
                return
            }
            super.keyDown(with: event)
        }

        override func insertTab(_ sender: Any?) {
            AppFormKeyboardRouting.moveFocus(from: self, direction: .forward)
        }

        override func insertBacktab(_ sender: Any?) {
            AppFormKeyboardRouting.moveFocus(from: self, direction: .backward)
        }

        override func insertNewline(_ sender: Any?) {
            performClick(nil)
        }
    }

    final class CheckboxContainerView: NSView {
        let button: FocusableCheckboxButton

        init(button: FocusableCheckboxButton) {
            self.button = button
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: leadingAnchor),
                button.trailingAnchor.constraint(equalTo: trailingAnchor),
                button.topAnchor.constraint(equalTo: topAnchor),
                button.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { false }
        override var canBecomeKeyView: Bool { false }
    }
}

private struct AppFieldChromeModifier: ViewModifier {
    let minHeight: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let fillsWidth: Bool
    let fill: Color
    let stroke: Color

    func body(content: Content) -> some View {
        if AppRuntime.usesRenewedChrome {
            content
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(minHeight: minHeight, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
        } else {
            content
        }
    }
}

// MARK: - Palette

enum AppPalette {
    private static let nightGreen = hexColor(0x1F833A)
    private static let nightYellow = hexColor(0xE2B122)
    private static let nightRed = hexColor(0xBA1B2C)
    private static let darkNewGreen = hexColor(0x115651)
    private static let darkNewRed = hexColor(0x97141D)
    private static let darkNewGold = hexColor(0xA97119)
    private static let darkNewGoldLight = hexColor(0xD4A639)
    private static let darkNewGreenLight = hexColor(0x306F69)
    private static let darkNewRedLight = hexColor(0xAB2D32)
    private static let renewedDarkPanel = hexColor(0x0B0D0F)
    private static let renewedDarkPanelAlt = hexColor(0x0E1012)
    private static let renewedDarkField = hexColor(0x1F2327)
    private static let renewedDarkPill = hexColor(0x25292E)
    static var isClean: Bool {
        currentVisualModePreference()?.isClean == true
    }

    private static func appChromeSurfaceColor(_ surface: AppChromeSurface) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let useDarkAppearance: Bool
                switch currentVisualModePreference() {
                case .dark, .darkClean, .darkNew:
                    useDarkAppearance = true
                case .light, .lightClean:
                    useDarkAppearance = false
                case nil:
                    useDarkAppearance = appearance.usesDarkPalette
                }
                return AppAppearanceRegistry.chromeColor(
                    for: AppAppearanceRegistry.chromeScheme(),
                    surface: surface,
                    useDarkAppearance: useDarkAppearance
                )
            }
        )
    }

    static let calendarFilterSurface = appChromeSurfaceColor(.calendarFilter)
    static let calendarHeaderSurface = appChromeSurfaceColor(.calendarHeader)
    static let calendarWorkspaceSurface = appChromeSurfaceColor(.calendarWorkspace)
    static let calendarDayRowSurface = appChromeSurfaceColor(.calendarDayRow)

    static func chromeTopColor(for mode: AppVisualMode) -> Color {
        Color(nsColor: chromeTopNSColor(for: mode))
    }

    static func chromeBottomColor(for mode: AppVisualMode) -> Color {
        Color(nsColor: chromeBottomNSColor(for: mode))
    }

    static func chromeTopNSColor(for mode: AppVisualMode) -> NSColor {
        AppAppearanceRegistry.chromeColor(
            for: AppAppearanceRegistry.chromeScheme(),
            surface: .menu,
            useDarkAppearance: mode.usesDarkAppearance
        )
    }

    static func chromeBottomNSColor(for mode: AppVisualMode) -> NSColor {
        AppAppearanceRegistry.chromeColor(
            for: AppAppearanceRegistry.chromeScheme(),
            surface: .menu,
            useDarkAppearance: mode.usesDarkAppearance
        )
    }

    static func cleanNavigationBackgroundColor(for mode: AppVisualMode) -> Color {
        Color(
            nsColor: AppAppearanceRegistry.chromeColor(
                for: AppAppearanceRegistry.chromeScheme(),
                surface: .menu,
                useDarkAppearance: mode.usesDarkAppearance
            )
        )
    }

    static let canvasTop = appChromeSurfaceColor(.workspace)
    static let canvasBottom = appChromeSurfaceColor(.workspace)
    static let chromeTop = appChromeSurfaceColor(.menu)
    static let chromeBottom = appChromeSurfaceColor(.menu)
    static let navigationSurface = appChromeSurfaceColor(.menu)
    static let cardSurface = chromeDynamicColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.82),
        dark: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.17, alpha: 0.94),
        lightClean: NSColor(calibratedWhite: 1.0, alpha: 1),
        darkClean: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1),
        renewedLight: NSColor(calibratedWhite: 1.0, alpha: 1),
        renewedDark: renewedDarkPanel
    )
    static let secondaryCardSurface = chromeDynamicColor(
        light: NSColor.controlBackgroundColor,
        dark: NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.20, alpha: 1),
        lightClean: NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.96, alpha: 1),
        darkClean: NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.18, alpha: 1),
        renewedLight: NSColor(calibratedWhite: 1.0, alpha: 1),
        renewedDark: renewedDarkPanel
    )
    static let fieldSurface = chromeDynamicColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.80),
        dark: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.21, alpha: 1),
        lightClean: NSColor(calibratedWhite: 1.0, alpha: 1),
        darkClean: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.17, alpha: 1),
        renewedLight: NSColor(calibratedWhite: 1.0, alpha: 1),
        renewedDark: renewedDarkField
    )
    static let border = chromeDynamicColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.10),
        lightClean: NSColor(calibratedRed: 0.55, green: 0.60, blue: 0.66, alpha: 0.75),
        darkClean: NSColor(calibratedWhite: 1.0, alpha: 0.16),
        renewedLight: NSColor(calibratedRed: 0.77, green: 0.80, blue: 0.77, alpha: 0.92),
        renewedDark: NSColor(calibratedWhite: 1.0, alpha: 0.18)
    )
    static let subtleBorder = chromeDynamicColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.06),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.06),
        lightClean: NSColor(calibratedRed: 0.62, green: 0.67, blue: 0.73, alpha: 0.42),
        darkClean: NSColor(calibratedWhite: 1.0, alpha: 0.10),
        renewedLight: NSColor(calibratedRed: 0.80, green: 0.83, blue: 0.80, alpha: 0.55),
        renewedDark: NSColor(calibratedWhite: 1.0, alpha: 0.14)
    )
    static let pillSurface = chromeDynamicColor(
        light: NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.98, alpha: 1),
        dark: NSColor(calibratedRed: 0.18, green: 0.24, blue: 0.29, alpha: 1),
        lightClean: NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.96, alpha: 1),
        darkClean: NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.23, alpha: 1),
        renewedLight: NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.92, alpha: 1),
        renewedDark: renewedDarkPill
    )
    static let pillText = chromeDynamicColor(
        light: NSColor(calibratedRed: 0.10, green: 0.27, blue: 0.43, alpha: 1),
        dark: NSColor(calibratedRed: 0.84, green: 0.92, blue: 0.99, alpha: 1),
        lightClean: NSColor(calibratedRed: 0.18, green: 0.24, blue: 0.31, alpha: 1),
        darkClean: NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.97, alpha: 1),
        renewedLight: NSColor(calibratedRed: 0.21, green: 0.29, blue: 0.28, alpha: 1),
        renewedDark: NSColor(calibratedRed: 0.88, green: 0.93, blue: 0.91, alpha: 1)
    )
    static let semanticOnColor = dynamicColor(
        light: .black,
        dark: .white,
        lightClean: .black,
        darkClean: .white,
        darkNew: .white
    )
    static let appText = chromeDynamicColor(
        light: .labelColor,
        dark: .labelColor,
        lightClean: .labelColor,
        darkClean: .labelColor,
        darkNew: .white,
        renewedLight: NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.18, alpha: 1),
        renewedDark: NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.95, alpha: 1)
    )
    private static func accentColor(shaded: Bool, useDarkPalette: Bool? = nil) -> NSColor {
        AppAppearanceRegistry.semanticColor(.positive, shaded: shaded, useDarkPalette: useDarkPalette ?? AppAppearanceRegistry.usesDarkPalette())
    }

    /// Round 17: Save is the accent blue in every mode (it was green in
    /// dark mode, which read as a status).
    static func actionSaveColor(for mode: AppVisualMode) -> NSColor {
        switch mode {
        case .light, .lightClean, .dark, .darkClean, .darkNew:
            return NSColor.controlAccentColor
        }
    }

    static let actionSave = Color(
        nsColor: NSColor(name: nil) { appearance in
            let mode = currentVisualModePreference() ?? (appearance.usesDarkPalette ? AppVisualMode.dark : .light)
            return actionSaveColor(for: mode)
        }
    )
    static func actionDeleteColor(for mode: AppVisualMode) -> NSColor {
        switch mode {
        case .light, .lightClean:
            return hexColor(0xC62828)
        case .dark, .darkClean, .darkNew:
            // Dark enough for a white 13 pt label to clear WCAG AA (4.5:1).
            return hexColor(0xD93036)
        }
    }

    static let actionDelete = Color(
        nsColor: NSColor(name: nil) { appearance in
            let mode = currentVisualModePreference() ?? (appearance.usesDarkPalette ? AppVisualMode.dark : .light)
            return actionDeleteColor(for: mode)
        }
    )
    static func linkActionColor(for mode: AppVisualMode) -> NSColor {
        switch mode {
        case .light, .lightClean:
            return hexColor(0x2F2FE4)
        case .dark, .darkClean, .darkNew:
            return hexColor(0x3A9AFF)
        }
    }
    static let linkAction = Color(
        nsColor: NSColor(name: nil) { appearance in
            let mode = currentVisualModePreference() ?? (appearance.usesDarkPalette ? AppVisualMode.dark : .light)
            return linkActionColor(for: mode)
        }
    )
    static var linkChipBackground: Color {
        Color(nsColor: accentColor(shaded: true).withAlphaComponent(0.62))
    }
    static func selectionColor(for mode: AppVisualMode) -> NSColor {
        switch mode {
        case .light, .lightClean:
            return hexColor(0x3A9AFF)
        case .dark, .darkClean, .darkNew:
            return hexColor(0x261CC1)
        }
    }
    static let inactiveTabSurface = chromeDynamicColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.85),
        dark: NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.20, alpha: 1),
        lightClean: NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.95, alpha: 1),
        darkClean: NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.18, alpha: 1),
        renewedLight: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.95, alpha: 1),
        renewedDark: renewedDarkPanelAlt
    )
    static let activeTabSurface = Color(
        nsColor: NSColor(name: nil) { appearance in
            let mode = currentVisualModePreference() ?? (appearance.usesDarkPalette ? AppVisualMode.dark : .light)
            return selectionColor(for: mode)
        }
    )
    static let activeTabText = Color(
        nsColor: NSColor(name: nil) { appearance in
            let mode = currentVisualModePreference() ?? (appearance.usesDarkPalette ? AppVisualMode.dark : .light)
            return contrastingTextColor(for: selectionColor(for: mode))
        }
    )
    static func mainMenuSelectionSurfaceColor(for mode: AppVisualMode) -> NSColor {
        switch mode {
        case .light, .lightClean:
            return selectionColor(for: mode).withAlphaComponent(0.16)
        case .dark, .darkClean, .darkNew:
            return selectionColor(for: mode)
        }
    }
    static func mainMenuSelectionStrokeColor(for mode: AppVisualMode) -> NSColor {
        switch mode {
        case .light, .lightClean:
            return selectionColor(for: mode).withAlphaComponent(0.68)
        case .dark, .darkClean, .darkNew:
            return selectionColor(for: mode).withAlphaComponent(0.18)
        }
    }
    static func mainMenuSelectionTextColor(for mode: AppVisualMode) -> NSColor {
        switch mode {
        case .light, .lightClean:
            return linkActionColor(for: mode)
        case .dark, .darkClean, .darkNew:
            return contrastingTextColor(for: selectionColor(for: mode))
        }
    }
    static let mainMenuSelectionSurface = Color(
        nsColor: NSColor(name: nil) { appearance in
            let mode = currentVisualModePreference() ?? (appearance.usesDarkPalette ? AppVisualMode.dark : .light)
            return mainMenuSelectionSurfaceColor(for: mode)
        }
    )
    static let mainMenuSelectionStroke = Color(
        nsColor: NSColor(name: nil) { appearance in
            let mode = currentVisualModePreference() ?? (appearance.usesDarkPalette ? AppVisualMode.dark : .light)
            return mainMenuSelectionStrokeColor(for: mode)
        }
    )
    static let mainMenuSelectionText = Color(
        nsColor: NSColor(name: nil) { appearance in
            let mode = currentVisualModePreference() ?? (appearance.usesDarkPalette ? AppVisualMode.dark : .light)
            return mainMenuSelectionTextColor(for: mode)
        }
    )
    static let footerSurface = chromeDynamicColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.72),
        dark: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.14, alpha: 0.98),
        lightClean: NSColor(calibratedWhite: 1.0, alpha: 0.94),
        darkClean: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.13, alpha: 1),
        renewedLight: NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.93, alpha: 0.98),
        renewedDark: renewedDarkPanel
    )
    static let listSurface = appChromeSurfaceColor(.list)
    static let sidebarPanelSurface = listSurface
    static let listContentSurface = chromeDynamicColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.17, alpha: 0.98),
        lightClean: NSColor(calibratedWhite: 1.0, alpha: 1),
        darkClean: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1),
        renewedLight: NSColor(calibratedWhite: 1.0, alpha: 1),
        renewedDark: renewedDarkPanel
    )
    static let detailPanelSurface = appChromeSurfaceColor(.workspace)
    static var vividGreen: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.positive, shaded: false)) }
    static var vividYellow: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.inProgress, shaded: false)) }
    // Round 17: real orange (it used to equal yellow).
    static var vividOrange: Color { statusFill(.warning) }
    static var vividRed: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.negative, shaded: false)) }
    static var vividBlue: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.neutral, shaded: false)) }
    static var shadeGreen: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.positive, shaded: true)) }
    static var shadeYellow: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.inProgress, shaded: true)) }
    static var shadeRed: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.negative, shaded: true)) }
    static var shadeBlue: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.neutral, shaded: true)) }
    static var chartGreen: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.positive, shaded: false)) }
    static var chartYellow: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.inProgress, shaded: false)) }
    static var chartRed: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.negative, shaded: false)) }
    static var chartBlue: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.neutral, shaded: false)) }

    static var statisticsGreen: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.positive, shaded: false)) }
    static var statisticsYellow: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.inProgress, shaded: false)) }
    static var statisticsRed: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.negative, shaded: false)) }
    static var statisticsBlue: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.neutral, shaded: false)) }

    static var deadlineWarningLong: Color { statusFill(.pending) }

    static var deadlineWarningShort: Color { statusFill(.warning) }

    static var deadlineNeutral: Color { shadeBlue }

    static var timelineBarStart: Color {
        Color(nsColor: AppAppearanceRegistry.semanticColor(.positive, shaded: true))
    }

    static var timelineBarEnd: Color {
        Color(nsColor: AppAppearanceRegistry.semanticColor(.positive, shaded: false))
    }

    static var timelineBarStroke: Color {
        Color(nsColor: shaded(AppAppearanceRegistry.semanticColor(.positive, shaded: false), by: 0.18))
    }

    static var timelinePendingBarStart: Color {
        Color(nsColor: AppAppearanceRegistry.semanticColor(.inProgress, shaded: true))
    }

    static var timelinePendingBarEnd: Color {
        Color(nsColor: AppAppearanceRegistry.semanticColor(.inProgress, shaded: false))
    }

    static var timelinePendingBarStroke: Color {
        Color(nsColor: shaded(AppAppearanceRegistry.semanticColor(.inProgress, shaded: false), by: 0.20))
    }

    static var timelineDecisionMarkerFill: Color {
        Color(nsColor: AppAppearanceRegistry.semanticColor(.inProgress, shaded: false))
    }

    static var timelineDecisionMarkerStroke: Color {
        Color(nsColor: shaded(AppAppearanceRegistry.semanticColor(.inProgress, shaded: false), by: 0.20))
    }

    static var timelineGrantedMarkerFill: Color {
        Color(nsColor: AppAppearanceRegistry.semanticColor(.positive, shaded: false))
    }

    static var timelineGrantedMarkerStroke: Color {
        Color(nsColor: shaded(AppAppearanceRegistry.semanticColor(.positive, shaded: false), by: 0.18))
    }

    static var timelineUncertainStroke: Color {
        Color(nsColor: AppAppearanceRegistry.semanticColor(.inProgress, shaded: false))
    }

    // Round 16: text colours (the pale fills were unreadable as text).
    static var dispositionPositiveText: Color {
        statusText(.done)
    }

    static var dispositionWarningText: Color {
        statusText(.negative)
    }

    static var statsCardPendingStart: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.inProgress, shaded: false)) }

    static var statsCardPendingEnd: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.inProgress, shaded: true)) }

    static var statsCardGrantedStart: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.positive, shaded: false)) }

    static var statsCardGrantedEnd: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.positive, shaded: true)) }

    static var statsCardDeclinedStart: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.negative, shaded: false)) }

    static var statsCardDeclinedEnd: Color { Color(nsColor: AppAppearanceRegistry.semanticColor(.negative, shaded: true)) }

    /* legacy definitions retained below only for light/clean structural palette values */
    static let legacyStatsCardPendingStart = dynamicColor(
        light: hexColor(0xFFF3B7),
        dark: nightYellow,
        lightClean: hexColor(0xFFF3B7),
        darkClean: nightYellow,
        darkNew: darkNewGold
    )

    static let legacyStatsCardPendingEnd = dynamicColor(
        light: hexColor(0xFFE281),
        dark: nightYellow,
        lightClean: hexColor(0xFFE281),
        darkClean: nightYellow,
        darkNew: darkNewGoldLight
    )

    static let legacyStatsCardGrantedStart = dynamicColor(
        light: hexColor(0x71CD8C),
        dark: nightGreen,
        lightClean: hexColor(0x71CD8C),
        darkClean: nightGreen,
        darkNew: darkNewGreen
    )

    static let legacyStatsCardGrantedEnd = dynamicColor(
        light: hexColor(0xADDDC6),
        dark: nightGreen,
        lightClean: hexColor(0xADDDC6),
        darkClean: nightGreen,
        darkNew: darkNewGreenLight
    )

    static let legacyStatsCardDeclinedStart = dynamicColor(
        light: hexColor(0xF1BCAF),
        dark: nightRed,
        lightClean: hexColor(0xF1BCAF),
        darkClean: nightRed,
        darkNew: darkNewRed
    )

    static let legacyStatsCardDeclinedEnd = dynamicColor(
        light: hexColor(0xF1E1D5),
        dark: nightRed,
        lightClean: hexColor(0xF1E1D5),
        darkClean: nightRed,
        darkNew: darkNewRedLight
    )

    static var largeCornerRadius: CGFloat {
        AppRuntime.usesRenewedChrome ? 18 : (currentVisualModePreference()?.isClean == true ? 10 : 22)
    }

    static var mediumCornerRadius: CGFloat {
        AppRuntime.usesRenewedChrome ? 14 : (currentVisualModePreference()?.isClean == true ? 8 : 16)
    }

    static var smallCornerRadius: CGFloat {
        AppRuntime.usesRenewedChrome ? 10 : (currentVisualModePreference()?.isClean == true ? 4 : 10)
    }

    static var sectionPadding: CGFloat {
        (AppRuntime.usesRenewedChrome ? 14 : (isClean ? 10 : 12)) * AppDensityRegistry.current().scale
    }

    static var compactSpacing: CGFloat {
        (AppRuntime.usesRenewedChrome ? 12 : (isClean ? 10 : 14)) * AppDensityRegistry.current().scale
    }

    static var titleSpacing: CGFloat {
        max(4, (AppRuntime.usesRenewedChrome ? 6 : (isClean ? 5 : 6)) * AppDensityRegistry.current().scale)
    }

    static var fieldHorizontalPadding: CGFloat {
        max(6, (AppRuntime.usesRenewedChrome ? 8 : 8) * AppDensityRegistry.current().scale)
    }

    static var textFieldHorizontalPadding: CGFloat { 8 }

    static var textFieldVerticalPadding: CGFloat { 3 }

    static var fieldVerticalPadding: CGFloat {
        max(4, (AppRuntime.usesRenewedChrome ? 6 : 6) * AppDensityRegistry.current().scale)
    }

    static var fieldMinHeight: CGFloat {
        max(26, (AppRuntime.usesRenewedChrome ? 30 : 28) * AppDensityRegistry.current().scale)
    }

    static var emptyStateSurface: Color {
        chromeDynamicColor(
            light: NSColor(calibratedWhite: 1.0, alpha: 0.92),
            dark: NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.17, alpha: 0.96),
            lightClean: NSColor(calibratedWhite: 1.0, alpha: 1),
            darkClean: NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.16, alpha: 1),
            renewedLight: NSColor(calibratedRed: 0.985, green: 0.985, blue: 0.975, alpha: 1),
            renewedDark: renewedDarkPanelAlt
        )
    }

    static var emptyStateIconSurface: Color {
        shadeBlue.opacity(AppRuntime.usesRenewedChrome ? 0.18 : 0.14)
    }
}
