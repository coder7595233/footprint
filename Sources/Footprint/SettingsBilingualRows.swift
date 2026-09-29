import SwiftUI

/// Shared building blocks for Settings.
///
/// - `SettingsEffectNote`: the short grey line under a setting that says what
///   the setting changes in the app ("Påverkar: …").
/// - `SettingsBilingualColumnsHeader` + `SettingsBilingualPairRow`: every
///   Swedish/English pair in Settings uses the same two columns, Swedish to
///   the left and English to the right, one row per item with a row label.
/// - `SettingsGrowingTextField`: a text field that grows downwards to show its
///   whole text instead of scrolling inside the field.
enum SettingsBilingualLayout {
    static let labelWidth: CGFloat = 240
    static let columnSpacing: CGFloat = 12
    /// Space between two Swedish/English rows (kept tight so many terms fit).
    static let rowSpacing: CGFloat = 5
}

/// A short secondary-text line that says what a setting affects.
struct SettingsEffectNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Column headings "Svenska" (left) and "Engelska" (right) above
/// `SettingsBilingualPairRow`s.
struct SettingsBilingualColumnsHeader: View {
    let language: AppLanguage
    var labelTitle: String = ""
    var labelWidth: CGFloat = SettingsBilingualLayout.labelWidth

    var body: some View {
        HStack(alignment: .bottom, spacing: SettingsBilingualLayout.columnSpacing) {
            Text(labelTitle)
                .appTypography(.tableHeader)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(labelTitle)
                .frame(width: labelWidth, alignment: .leading)
            Text(language.text("Swedish", "Svenska"))
                .appTypography(.tableHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(language.text("English", "Engelska"))
                .appTypography(.tableHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
    }
}

/// The one-line row label used by `SettingsBilingualPairRow(title:)`.
struct SettingsBilingualRowTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .appTypography(.fieldLabel)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(title)
            .padding(.top, 5)
    }
}

/// One compact Swedish/English row: a one-line row label, then the Swedish
/// field on the left and the English field on the right. No box around the
/// row. Both fields are top-aligned so a taller field never pushes the other
/// one down. Stack rows in a `VStack(spacing: SettingsBilingualLayout.rowSpacing)`.
/// The label column is usually a plain title; rows that need an editable code
/// or a button there pass their own `label` view.
struct SettingsBilingualPairRow<RowLabel: View, SwedishField: View, EnglishField: View>: View {
    let labelWidth: CGFloat
    let rowLabel: RowLabel
    let swedishField: SwedishField
    let englishField: EnglishField

    init(
        labelWidth: CGFloat = SettingsBilingualLayout.labelWidth,
        @ViewBuilder label: () -> RowLabel,
        @ViewBuilder swedish: () -> SwedishField,
        @ViewBuilder english: () -> EnglishField
    ) {
        self.labelWidth = labelWidth
        self.rowLabel = label()
        self.swedishField = swedish()
        self.englishField = english()
    }

    var body: some View {
        HStack(alignment: .top, spacing: SettingsBilingualLayout.columnSpacing) {
            rowLabel
                .frame(width: labelWidth, alignment: .topLeading)

            swedishField
                .frame(maxWidth: .infinity, alignment: .topLeading)

            englishField
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

extension SettingsBilingualPairRow where RowLabel == SettingsBilingualRowTitle {
    init(
        title: String,
        labelWidth: CGFloat = SettingsBilingualLayout.labelWidth,
        @ViewBuilder swedish: () -> SwedishField,
        @ViewBuilder english: () -> EnglishField
    ) {
        self.labelWidth = labelWidth
        self.rowLabel = SettingsBilingualRowTitle(title: title)
        self.swedishField = swedish()
        self.englishField = english()
    }
}

/// A text field that grows vertically to show all of its text. `minimumLines`
/// only sets the starting height; there is no upper limit.
struct SettingsGrowingTextField: View {
    let placeholder: String
    @Binding var text: String
    var minimumLines: Int = 1

    private var lineRange: PartialRangeFrom<Int> {
        max(minimumLines, 1)...
    }

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(lineRange)
            .fixedSize(horizontal: false, vertical: true)
            .appTextInputChrome()
    }
}
