import Foundation

enum AppLanguage: String {
    case system
    case en
    case pl
    case es
    case de
    case fr
    case ptBR = "pt-BR"

    static func fromStoredValue(_ raw: String?) -> AppLanguage {
        guard let raw else { return .system }
        if raw == "pt" {
            return .ptBR
        }
        return AppLanguage(rawValue: raw) ?? .system
    }

    private static func localizedBundle(for languageCode: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        return bundle
    }

    static var resolvedSystemLanguage: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("pl") {
            return .pl
        }
        if preferred.hasPrefix("es") {
            return .es
        }
        if preferred.hasPrefix("de") {
            return .de
        }
        if preferred.hasPrefix("fr") {
            return .fr
        }
        if preferred.hasPrefix("pt") {
            return .ptBR
        }
        return .en
    }

    var locale: Locale {
        switch self {
        case .system:
            return .current
        case .en:
            return Locale(identifier: "en")
        case .pl:
            return Locale(identifier: "pl")
        case .es:
            return Locale(identifier: "es")
        case .de:
            return Locale(identifier: "de")
        case .fr:
            return Locale(identifier: "fr")
        case .ptBR:
            return Locale(identifier: "pt-BR")
        }
    }

    var bundle: Bundle {
        switch self {
        case .system:
            return AppLanguage.resolvedSystemLanguage.bundle
        case .en, .pl, .es, .de, .fr, .ptBR:
            return AppLanguage.localizedBundle(for: rawValue) ?? .main
        }
    }
}

enum AppLocalization {
    static var settings: AppSettingsStore = .shared

    /// Buforuje jezyk i bundle, aby ograniczyc koszt odczytu UserDefaults i tworzenia Bundle(path:) przy kazdym wywolaniu.
    /// Bundle(path:) on every call to `string()`.  Invalidated via
    /// `reloadLanguage()` po zmianie jezyka aplikacji.
    private static var _cachedLanguage: AppLanguage?
    private static var _cachedBundle: Bundle?

    static var currentLanguage: AppLanguage {
        if let cached = _cachedLanguage { return cached }
        let lang = loadLanguageFromDefaults()
        _cachedLanguage = lang
        _cachedBundle = lang.bundle
        return lang
    }

    private static var currentBundle: Bundle {
        if let cached = _cachedBundle { return cached }
        let lang = currentLanguage
        let bundle = lang.bundle
        _cachedBundle = bundle
        return bundle
    }

    private static func loadLanguageFromDefaults() -> AppLanguage {
        AppLanguage.fromStoredValue(settings.snapshot.experience.appLanguage)
    }

    /// Wywolaj po zmianie jezyka aplikacji, aby odswiezyc zbuforowany bundle.
    static func reloadLanguage() {
        _cachedLanguage = nil
        _cachedBundle = nil
    }

    static func string(_ key: String, _ args: CVarArg...) -> String {
        let language = currentLanguage
        let bundle = currentBundle
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: args)
    }

    static func systemString(_ key: String, _ args: CVarArg...) -> String {
        let language = AppLanguage.resolvedSystemLanguage
        let bundle = language.bundle
        let locale = language.locale
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: args)
    }

    static func systemPlural(_ key: String, _ count: Int) -> String {
        let language = AppLanguage.resolvedSystemLanguage
        if language != .pl {
            let singularKey = "\(key).one"
            let singularFormat = language.bundle.localizedString(forKey: singularKey, value: singularKey, table: nil)
            if count == 1, singularFormat != singularKey {
                return String(format: singularFormat, locale: language.locale, arguments: [count])
            }
            return systemString(key, count)
        }
        let mod10 = count % 10
        let mod100 = count % 100
        let suffix: String
        if mod10 == 1 && mod100 != 11 {
            suffix = "one"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            suffix = "few"
        } else {
            suffix = "many"
        }
        let pluralKey = "\(key).\(suffix)"
        return systemString(pluralKey, count)
    }

    static func plural(_ key: String, _ count: Int) -> String {
        let language = currentLanguage
        let resolvedBundle: Bundle
        let resolvedLocale: Locale

        switch language {
        case .system:
            let resolvedLanguage = AppLanguage.resolvedSystemLanguage
            resolvedBundle = resolvedLanguage.bundle
            resolvedLocale = resolvedLanguage.locale
        case .en, .pl, .es, .de, .fr, .ptBR:
            resolvedBundle = currentBundle
            resolvedLocale = language.locale
        }

        let shouldUsePolishRules = resolvedLocale.identifier.lowercased().hasPrefix("pl")
        guard shouldUsePolishRules else {
            let singularKey = "\(key).one"
            let singularFormat = resolvedBundle.localizedString(forKey: singularKey, value: singularKey, table: nil)
            if count == 1, singularFormat != singularKey {
                return String(format: singularFormat, locale: resolvedLocale, arguments: [count])
            }
            let format = resolvedBundle.localizedString(forKey: key, value: key, table: nil)
            return String(format: format, locale: resolvedLocale, arguments: [count])
        }

        let suffix: String
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 {
            suffix = "one"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            suffix = "few"
        } else {
            suffix = "many"
        }

        let pluralKey = "\(key).\(suffix)"
        let format = resolvedBundle.localizedString(forKey: pluralKey, value: pluralKey, table: nil)
        if format == pluralKey {
            let fallback = resolvedBundle.localizedString(forKey: key, value: key, table: nil)
            return String(format: fallback, locale: resolvedLocale, arguments: [count])
        }
        return String(format: format, locale: resolvedLocale, arguments: [count])
    }
}
