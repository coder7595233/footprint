import AppKit
import SwiftUI
import XCTest
@testable import Footprint

/// Round 7 ("Inställningar förklarar sin effekt"): every Swedish/English pair in
/// Settings uses one shared two-column row. These checks only make sure the
/// shared pieces can be drawn, with short and long texts.
final class SettingsBilingualRowsTests: XCTestCase {
    @MainActor
    func testBilingualTableRendersWithShortAndLongTexts() {
        let swedishBinding = Binding.constant("Termin")
        let englishBinding = Binding.constant(
            String(repeating: "A long English sentence that must wrap onto several lines. ", count: 8)
        )

        let table = VStack(alignment: .leading, spacing: SettingsBilingualLayout.rowSpacing) {
            SettingsEffectNote("Påverkar: ett exempel.")
            SettingsBilingualColumnsHeader(language: .swedish, labelTitle: "Undervisning · deltagarform")
            SettingsBilingualPairRow(title: "Ord för termin") {
                SettingsGrowingTextField(placeholder: "Termin", text: swedishBinding)
            } english: {
                SettingsGrowingTextField(placeholder: "Semester", text: englishBinding, minimumLines: 2)
            }
            SettingsBilingualPairRow(
                label: { Text("sv") },
                swedish: { Text("svenska") },
                english: { Text("Swedish") }
            )
        }

        let hostingView = NSHostingView(rootView: table.frame(width: 900))
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostingView.frame.width, 900)
        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
    }
}
