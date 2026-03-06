import SwiftUI

@MainActor
@propertyWrapper
struct AppSetting<Value>: DynamicProperty {
    private enum Storage {
        case keyPath(WritableKeyPath<AppSettingsSnapshot, Value>)
        case legacyKey(key: String, defaultValue: Value)
    }

    @ObservedObject private var settings: AppSettingsStore
    private let storage: Storage

    @available(*, deprecated, message: "Use keyPath-based AppSetting initializer.")
    init(wrappedValue: Value, _ key: String) {
        self.init(wrappedValue: wrappedValue, key, store: .shared)
    }

    @available(*, deprecated, message: "Use keyPath-based AppSetting initializer.")
    init(wrappedValue: Value, _ key: String, store: AppSettingsStore) {
        self.storage = .legacyKey(key: key, defaultValue: wrappedValue)
        _settings = ObservedObject(wrappedValue: store)
    }

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
        self.storage = .keyPath(keyPath)
        _settings = ObservedObject(wrappedValue: store)
    }

    var wrappedValue: Value {
        get {
            switch storage {
            case .keyPath(let keyPath):
                settings.snapshot[keyPath: keyPath]
            case .legacyKey(let key, let defaultValue):
                settings.value(forKey: key, default: defaultValue)
            }
        }
        nonmutating set {
            DispatchQueue.main.async {
                switch storage {
                case .keyPath(let keyPath):
                    settings.set(keyPath, newValue)
                case .legacyKey(let key, _):
                    settings.set(newValue, forKey: key)
                }
            }
        }
    }

    var projectedValue: Binding<Value> {
        switch storage {
        case .keyPath(let keyPath):
            settings.binding(keyPath)
        case .legacyKey:
            Binding(
                get: { wrappedValue },
                set: { wrappedValue = $0 }
            )
        }
    }
}
