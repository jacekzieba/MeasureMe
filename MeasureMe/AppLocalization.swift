import Foundation

enum AppLanguage: String {
    case system
    case en
    case pl

    var locale: Locale {
        switch self {
        case .system:
            return .current
        case .en:
            return Locale(identifier: "en")
        case .pl:
            return Locale(identifier: "pl")
        }
    }

    var bundle: Bundle {
        switch self {
        case .system:
            return .main
        case .en, .pl:
            guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                return .main
            }
            return bundle
        }
    }
}

enum AppLocalization {
    static var currentLanguage: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        return AppLanguage(rawValue: raw) ?? .system
    }

    static func string(_ key: String, _ args: CVarArg...) -> String {
        let language = currentLanguage
        let format = language.bundle.localizedString(forKey: key, value: key, table: nil)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: args)
    }

    static func systemString(_ key: String, _ args: CVarArg...) -> String {
        let lang = Locale.preferredLanguages.first?.lowercased() ?? ""
        let bundle: Bundle
        let locale: Locale
        if lang.hasPrefix("pl"), let path = Bundle.main.path(forResource: "pl", ofType: "lproj"), let plBundle = Bundle(path: path) {
            bundle = plBundle
            locale = Locale(identifier: "pl")
        } else if let path = Bundle.main.path(forResource: "en", ofType: "lproj"), let enBundle = Bundle(path: path) {
            bundle = enBundle
            locale = Locale(identifier: "en")
        } else {
            bundle = .main
            locale = .current
        }
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: args)
    }

    static func systemPlural(_ key: String, _ count: Int) -> String {
        let lang = Locale.preferredLanguages.first?.lowercased() ?? ""
        if !lang.hasPrefix("pl") {
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
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        let resolvedBundle: Bundle
        let resolvedLocale: Locale

        switch language {
        case .system:
            if preferred.hasPrefix("pl"),
               let path = Bundle.main.path(forResource: "pl", ofType: "lproj"),
               let bundle = Bundle(path: path) {
                resolvedBundle = bundle
                resolvedLocale = Locale(identifier: "pl")
            } else if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
                      let bundle = Bundle(path: path) {
                resolvedBundle = bundle
                resolvedLocale = Locale(identifier: "en")
            } else {
                resolvedBundle = .main
                resolvedLocale = .current
            }
        case .en, .pl:
            resolvedBundle = language.bundle
            resolvedLocale = language.locale
        }

        let shouldUsePolishRules = resolvedLocale.identifier.lowercased().hasPrefix("pl")
        guard shouldUsePolishRules else {
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
