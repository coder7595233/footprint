import AppKit
import SwiftUI

/// Persisted, per-list column widths. The default ("auto") width of a column
/// is the width of its longest visible content, capped so very long values
/// truncate instead of blowing the table up. A manual drag on the resize
/// handle between two headers overrides the auto width, and the choice is
/// remembered in UserDefaults until it is changed again (double-click a
/// handle to return that column to auto).
@MainActor
final class AppListColumnWidthModel: ObservableObject {
    static let minimumWidth: CGFloat = 44
    static let maximumWidth: CGFloat = 640

    private let defaultsKey: String
    @Published private var manualWidths: [String: CGFloat]

    init(listKey: String) {
        defaultsKey = "FootprintListColumnWidths.\(listKey)"
        if let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] {
            manualWidths = stored.mapValues { CGFloat($0) }
        } else {
            manualWidths = [:]
        }
    }

    func width(for column: String, auto: CGFloat) -> CGFloat {
        manualWidths[column] ?? auto
    }

    func setManualWidth(_ width: CGFloat, for column: String) {
        let clamped = min(max(width.rounded(), Self.minimumWidth), Self.maximumWidth)
        guard manualWidths[column] != clamped else { return }
        manualWidths[column] = clamped
        persist()
    }

    func resetWidth(for column: String) {
        guard manualWidths.removeValue(forKey: column) != nil else { return }
        persist()
    }

    private func persist() {
        if manualWidths.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(
                manualWidths.mapValues(Double.init),
                forKey: defaultsKey
            )
        }
    }
}

/// Measures the auto width of a column: the widest of the header (plus room
/// for the sort chevron) and the widest cell text, clamped to sensible bounds.
enum AppListColumnAutoWidth {
    static func width(
        header: String,
        values: some Sequence<String>,
        cellFontSize: CGFloat = 13,
        headerFontSize: CGFloat = 12,
        headerAccessoryWidth: CGFloat = 34,
        horizontalPadding: CGFloat = 14,
        minimum: CGFloat = 56,
        maximum: CGFloat = 380
    ) -> CGFloat {
        let headerFont = NSFont.systemFont(ofSize: headerFontSize, weight: .semibold)
        let cellFont = NSFont.systemFont(ofSize: cellFontSize)
        var widest = (header as NSString).size(withAttributes: [.font: headerFont]).width + headerAccessoryWidth
        var measured = 0
        for value in values {
            widest = max(widest, (value as NSString).size(withAttributes: [.font: cellFont]).width)
            measured += 1
            // Sampling bound so huge lists don't pay for a full measurement pass.
            if measured >= 400 { break }
        }
        return min(max(widest + horizontalPadding, minimum), maximum).rounded(.up)
    }
}

/// The thin draggable divider between two column headers. Dragging resizes
/// the column to its LEFT; double-click restores that column's auto width.
struct AppListColumnResizeHandle: View {
    static let width: CGFloat = 7

    @ObservedObject var model: AppListColumnWidthModel
    let column: String
    let currentWidth: CGFloat

    @State private var dragStartWidth: CGFloat?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(isHovering || dragStartWidth != nil ? AppPalette.linkAction : AppPalette.border)
                .frame(width: isHovering || dragStartWidth != nil ? 2 : 1, height: 15)
        }
        .frame(width: Self.width, height: 26)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hovering != isHovering else { return }
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = currentWidth
                    }
                    model.setManualWidth((dragStartWidth ?? currentWidth) + value.translation.width, for: column)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                }
        )
        .onTapGesture(count: 2) {
            model.resetWidth(for: column)
        }
        .help("Dra för att ändra kolumnbredd · dubbelklicka för automatisk bredd")
    }
}
