import Foundation

enum WatchAppLanguage: String {
    case system
    case en
    case pl
    case es
    case de
    case fr
    case ptBR = "pt-BR"

    static func fromStoredValue(_ raw: String?) -> WatchAppLanguage {
        guard let raw else { return .system }
        if raw == "pt" {
            return .ptBR
        }
        return WatchAppLanguage(rawValue: raw) ?? .system
    }

    static var resolvedSystemLanguage: WatchAppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("pl") { return .pl }
        if preferred.hasPrefix("es") { return .es }
        if preferred.hasPrefix("de") { return .de }
        if preferred.hasPrefix("fr") { return .fr }
        if preferred.hasPrefix("pt") { return .ptBR }
        return .en
    }

    var locale: Locale {
        switch self {
        case .system:
            return Self.resolvedSystemLanguage.locale
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
        let code: String
        switch self {
        case .system:
            code = Self.resolvedSystemLanguage.rawValue
        case .en, .pl, .es, .de, .fr, .ptBR:
            code = rawValue
        }

        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

enum WatchLocalization {
    static let appLanguageKey = "watch_app_language"
    static let unitsSystemKey = "watch_units_system"

    static var currentLanguage: WatchAppLanguage {
        WatchAppLanguage.fromStoredValue(storedString(forKey: appLanguageKey))
    }

    static var currentLocale: Locale {
        currentLanguage.locale
    }

    static var storedUnitsSystem: String {
        storedString(forKey: unitsSystemKey) ?? "metric"
    }

    static func string(_ key: String, _ args: CVarArg...) -> String {
        let language = currentLanguage
        let format = language.bundle.localizedString(forKey: key, value: key, table: "Watch")
        guard !args.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: args)
    }

    static func persist(appLanguage: String? = nil, unitsSystem: String? = nil) {
        let defaults = UserDefaults(suiteName: watchAppGroupID)
        if let appLanguage {
            defaults?.set(appLanguage, forKey: appLanguageKey)
            UserDefaults.standard.set(appLanguage, forKey: appLanguageKey)
        }
        if let unitsSystem {
            defaults?.set(unitsSystem, forKey: unitsSystemKey)
            UserDefaults.standard.set(unitsSystem, forKey: unitsSystemKey)
        }
    }

    private static func storedString(forKey key: String) -> String? {
        UserDefaults(suiteName: watchAppGroupID)?.string(forKey: key)
            ?? UserDefaults.standard.string(forKey: key)
    }
}

func watchLocalized(_ english: String, _ polish: String) -> String {
    WatchLocalization.string(english)
}
