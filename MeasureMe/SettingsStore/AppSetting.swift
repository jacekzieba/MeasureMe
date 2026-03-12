import SwiftUI
import Combine

// MARK: - Per-keypath observer (fires objectWillChange only when THIS value changes)

@MainActor
final class _KeyPathSettingObserver<Value: Equatable>: ObservableObject {
    let keyPath: WritableKeyPath<AppSettingsSnapshot, Value>
    let store: AppSettingsStore
    private var cancellable: AnyCancellable?

    init(keyPath: WritableKeyPath<AppSettingsSnapshot, Value>, store: AppSettingsStore) {
        self.keyPath = keyPath
        self.store = store
        self.cancellable = store.$snapshot
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }
}

// MARK: - Property wrapper

@MainActor
@propertyWrapper
struct AppSetting<Value: Equatable>: DynamicProperty {
    @StateObject private var observer: _KeyPathSettingObserver<Value>

    init(
        wrappedValue: Value,
        _ keyPath: WritableKeyPath<AppSettingsSnapshot, Value>
    ) {
        self.init(wrappedValue: wrappedValue, keyPath, store: .shared)
    }

    init(
        wrappedValue: Value,
        _ keyPath: WritableKeyPath<AppSettingsSnapshot, Value>,
        store: AppSettingsStore
    ) {
        _observer = StateObject(wrappedValue: _KeyPathSettingObserver(keyPath: keyPath, store: store))
    }

    var wrappedValue: Value {
        get { observer.store.snapshot[keyPath: observer.keyPath] }
        nonmutating set { observer.store.set(observer.keyPath, newValue) }
    }

    var projectedValue: Binding<Value> {
        observer.store.binding(observer.keyPath)
    }
}
