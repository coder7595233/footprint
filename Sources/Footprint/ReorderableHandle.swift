import SwiftUI
import UniformTypeIdentifiers

struct StableStringDraftRow: Identifiable, Equatable {
    let id: String
    let index: Int
    let value: String
}

@MainActor
final class StableStringDraftListState {
    private(set) var ids: [String]
    private(set) var valuesSnapshot: [String]

    init(values: [String]) {
        ids = values.map { _ in UUID().uuidString }
        valuesSnapshot = values
    }

    func rows(for values: [String]) -> [StableStringDraftRow] {
        ensureCount(values.count)
        valuesSnapshot = values
        return values.enumerated().map { index, value in
            StableStringDraftRow(id: ids[index], index: index, value: value)
        }
    }

    func updateValue(at index: Int, to value: String) {
        guard valuesSnapshot.indices.contains(index) else { return }
        valuesSnapshot[index] = value
    }

    func append(value: String) {
        ids.append(UUID().uuidString)
        valuesSnapshot.append(value)
    }

    func remove(at index: Int) {
        guard ids.indices.contains(index) else { return }
        ids.remove(at: index)
        valuesSnapshot.remove(at: index)
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        ids.move(fromOffsets: fromOffsets, toOffset: toOffset)
        valuesSnapshot.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func reconcileExternal(_ values: [String]) {
        var availableIndicesByValue: [String: [Int]] = [:]
        for (index, value) in valuesSnapshot.enumerated() {
            availableIndicesByValue[value, default: []].append(index)
        }
        var consumedOffsets: [String: Int] = [:]
        var reconciledIDs: [String] = []
        reconciledIDs.reserveCapacity(values.count)

        for value in values {
            let offset = consumedOffsets[value, default: 0]
            if let candidates = availableIndicesByValue[value], candidates.indices.contains(offset) {
                reconciledIDs.append(ids[candidates[offset]])
                consumedOffsets[value] = offset + 1
            } else {
                reconciledIDs.append(UUID().uuidString)
            }
        }
        ids = reconciledIDs
        valuesSnapshot = values
    }

    private func ensureCount(_ count: Int) {
        if ids.count > count {
            ids.removeLast(ids.count - count)
            valuesSnapshot.removeLast(valuesSnapshot.count - count)
        } else if ids.count < count {
            ids.append(contentsOf: (ids.count..<count).map { _ in UUID().uuidString })
            valuesSnapshot.append(contentsOf: repeatElement("", count: count - valuesSnapshot.count))
        }
    }
}

struct ReorderHandle: View {
    let itemID: String
    @Binding var draggedItemID: String?
    var language: AppLanguage = .swedish

    var body: some View {
        Image(systemName: "arrow.up.arrow.down")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(AppPalette.appText)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .onDrag {
                draggedItemID = itemID
                return NSItemProvider(object: itemID as NSString)
            }
            .help(language.text("Reorder", "Ändra ordning"))
            .accessibilityLabel(language.text("Reorder", "Ändra ordning"))
            .accessibilityHint(language.text("Drag to change the order", "Dra för att ändra ordningen"))
    }
}

struct StringReorderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var items: [String]
    @Binding var draggedItemID: String?
    var onReorder: (() -> Void)? = nil

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItemID,
              draggedItemID != targetID,
              let fromIndex = items.firstIndex(of: draggedItemID),
              let toIndex = items.firstIndex(of: targetID) else { return }

        if items[toIndex] != draggedItemID {
            withAnimation(.easeInOut(duration: 0.12)) {
                items.move(
                    fromOffsets: IndexSet(integer: fromIndex),
                    toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                )
                onReorder?()
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        onReorder?()
        draggedItemID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

struct StableStringReorderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var items: [String]
    let identity: StableStringDraftListState
    @Binding var draggedItemID: String?
    var onReorder: (() -> Void)? = nil

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItemID,
              draggedItemID != targetID,
              let fromIndex = identity.ids.firstIndex(of: draggedItemID),
              let toIndex = identity.ids.firstIndex(of: targetID) else { return }

        withAnimation(.easeInOut(duration: 0.12)) {
            let offsets = IndexSet(integer: fromIndex)
            let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
            items.move(fromOffsets: offsets, toOffset: destination)
            identity.move(fromOffsets: offsets, toOffset: destination)
            onReorder?()
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        onReorder?()
        draggedItemID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

struct AffiliationReorderDropDelegate: DropDelegate {
    let enabled: Bool
    let targetID: String
    @Binding var items: [PublicationAffiliation]
    @Binding var draggedItemID: String?

    func validateDrop(info: DropInfo) -> Bool {
        enabled && info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard enabled else { return }
        guard let draggedItemID,
              draggedItemID != targetID,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItemID }),
              let toIndex = items.firstIndex(where: { $0.id == targetID }) else { return }

        if items[toIndex].id != draggedItemID {
            withAnimation(.easeInOut(duration: 0.12)) {
                items.move(
                    fromOffsets: IndexSet(integer: fromIndex),
                    toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                )
                synchronizePrimaryAffiliation()
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard enabled else { return false }
        synchronizePrimaryAffiliation()
        draggedItemID = nil
        return true
    }

    func dropExited(info: DropInfo) {}

    private func synchronizePrimaryAffiliation() {
        for index in items.indices {
            items[index].isPrimary = index == 0
        }
    }
}

struct IdentifiedReorderDropDelegate<Item: Identifiable>: DropDelegate where Item.ID == String {
    let targetID: String
    @Binding var items: [Item]
    @Binding var draggedItemID: String?
    var onReorder: (() -> Void)? = nil

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItemID,
              draggedItemID != targetID,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItemID }),
              let toIndex = items.firstIndex(where: { $0.id == targetID }) else { return }

        if items[toIndex].id != draggedItemID {
            withAnimation(.easeInOut(duration: 0.12)) {
                items.move(
                    fromOffsets: IndexSet(integer: fromIndex),
                    toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                )
                onReorder?()
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        onReorder?()
        draggedItemID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}
