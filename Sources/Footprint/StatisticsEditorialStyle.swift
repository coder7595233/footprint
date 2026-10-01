import SwiftUI

/// Editorial styling primitives for the statistics workspace: serif headings,
/// a small-caps kicker line, a short thick rule under the page header, and
/// hairline/ink tokens shared by the statistics charts and tables.
enum StatisticsEditorialStyle {
    /// Strong "ink" used for header underlines and total-row rules.
    static var ink: Color { AppPalette.appText }
    /// Hairline used between table rows.
    static var hairline: Color { AppPalette.border }

    /// The app palette used by the statistics marks. Round 16: the status
    /// colours follow Settings and light/dark mode (no fixed pastels).
    static var paletteGreen: Color { AppPalette.statusFill(.done) }
    static var paletteYellow: Color { AppPalette.statusFill(.pending) }
    static var paletteOrange: Color { AppPalette.statusFill(.warning) }
    /// Blue is a category colour here (not a status): Settings' neutral colour.
    static var paletteBlue: Color { AppPalette.vividBlue }
    static let palettePurple = Color(hex: 0xC9B8E8)
}

private extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

/// Small-caps, letterspaced kicker line ("STATISTIK · ANSLAG").
struct StatisticsKickerText: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(appFont(.secondary).weight(.semibold))
            .tracking(1.8)
            .foregroundStyle(.secondary)
    }
}

/// Serif heading used for the statistics page title and section titles.
struct StatisticsSerifTitleText: View {
    let text: String
    var size: CGFloat = 17

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .serif))
            .foregroundStyle(AppPalette.appText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// The short thick rule that closes the editorial page header.
struct StatisticsEditorialRule: View {
    var body: some View {
        Rectangle()
            .fill(StatisticsEditorialStyle.ink)
            .frame(width: 64, height: 3)
    }
}

/// Kicker + serif title + rule — the page header for a statistics area.
struct StatisticsPageHeader: View {
    let kicker: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatisticsKickerText(text: kicker)
            StatisticsSerifTitleText(text: title, size: 26)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(appFont(.body))
                    .foregroundStyle(.secondary)
            }
            StatisticsEditorialRule()
                .padding(.top, 8)
        }
    }
}
