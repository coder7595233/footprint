import Foundation
import SwiftUI

/// Small UI-only state persisted in the same account-scoped defaults namespace
/// as list sorting. This lets heavy workspace trees be unmounted without
/// changing canonical documents or losing filters the user chose to retain.
@propertyWrapper
@MainActor
struct WorkspaceFilterState<Value: Codable & Sendable>: DynamicProperty {
    @State private var value: Value
    private let defaultsKey: String

    init(wrappedValue defaultValue: Value, _ defaultsKey: String) {
        self.defaultsKey = AppRuntime.scopedDefaultsKey(defaultsKey)
        let restored: Value
        if let data = UserDefaults.standard.data(forKey: self.defaultsKey),
           let decoded = try? JSONDecoder().decode(Value.self, from: data) {
            restored = decoded
            // A value other than the default came back from an earlier run:
            // the list shows "Sparat från förra gången" until it is changed.
            if let defaultData = try? JSONEncoder().encode(defaultValue), defaultData != data {
                RestoredListFilters.markRestored(key: defaultsKey)
            }
        } else {
            restored = defaultValue
        }
        _value = State(initialValue: restored)
    }

    var wrappedValue: Value {
        get { value }
        nonmutating set {
            value = newValue
            RestoredListFilters.markChanged(key: defaultsKey)
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    var projectedValue: Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }
}

protocol AppListSortCriterion: Hashable {
    associatedtype Column: RawRepresentable & Hashable where Column.RawValue == String

    var column: Column { get }
    var ascending: Bool { get set }

    init(column: Column, ascending: Bool)
}

enum ListSortPersistence {
    private struct StoredCriterion: Codable {
        let column: String
        let ascending: Bool
    }

    static func load<Criterion: AppListSortCriterion>(
        defaultsKey: String,
        defaultValue: [Criterion]
    ) -> [Criterion] {
        let key = AppRuntime.scopedDefaultsKey(defaultsKey)
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode([StoredCriterion].self, from: data) else {
            return defaultValue
        }
        let restored = stored.compactMap { item -> Criterion? in
            guard let column = Criterion.Column(rawValue: item.column) else { return nil }
            return Criterion(column: column, ascending: item.ascending)
        }
        return restored.isEmpty ? defaultValue : restored
    }

    static func save<Criterion: AppListSortCriterion>(
        _ history: [Criterion],
        defaultsKey: String
    ) {
        let stored = history.map { StoredCriterion(column: $0.column.rawValue, ascending: $0.ascending) }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: AppRuntime.scopedDefaultsKey(defaultsKey))
    }
}
