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
    // The observer's sole job is to call objectWillChange when the specific
    // keypath value changes, driving SwiftUI re-renders. We intentionally
    // never read `observer.keyPath` or `observer.store` from wrappedValue /
    // projectedValue — accessing @StateObject.wrappedValue outside a View body
    // causes "Accessing StateObject without being installed on a View" warnings.
    // Instead we keep `keyPath` and `store` as plain stored properties so they
    // are always safe to access regardless of SwiftUI's installation state.
    @StateObject private var observer: _KeyPathSettingObserver<Value>
    private let keyPath: WritableKeyPath<AppSettingsSnapshot, Value>
    private let store: AppSettingsStore

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
        self.keyPath = keyPath
        self.store = store
        _observer = StateObject(wrappedValue: _KeyPathSettingObserver(keyPath: keyPath, store: store))
    }

    var wrappedValue: Value {
        get { store.snapshot[keyPath: keyPath] }
        nonmutating set { store.set(keyPath, newValue) }
    }

    var projectedValue: Binding<Value> {
        store.binding(keyPath)
    }
}
