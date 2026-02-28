import SwiftUI

@MainActor
@propertyWrapper
struct AppSetting<Value>: DynamicProperty {
    @ObservedObject private var settings: AppSettingsStore
    private let key: String
    private let defaultValue: Value

    init(wrappedValue: Value, _ key: String) {
        self.init(wrappedValue: wrappedValue, key, store: .shared)
    }

    init(wrappedValue: Value, _ key: String, store: AppSettingsStore) {
        self.defaultValue = wrappedValue
        self.key = key
        _settings = ObservedObject(wrappedValue: store)
    }

    var wrappedValue: Value {
        get { settings.value(forKey: key, default: defaultValue) }
        nonmutating set { settings.set(newValue, forKey: key) }
    }

    var projectedValue: Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }
}
