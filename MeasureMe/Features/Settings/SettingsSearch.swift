import Foundation

enum SettingsSearchRoute: String, Hashable, Identifiable {
    case profile
    case metrics
    case indicators
    case physiqueIndicators
    case health
    case notifications
    case home
    case aiInsights
    case units
    case experience
    case language
    case data
    case faq
    case about

    var id: String { rawValue }
}

struct SettingsSearchItem: Identifiable {
    let route: SettingsSearchRoute
    let title: String
    let subtitle: String
    let keywords: [String]

    var id: String { route.rawValue + "_" + title }
}

enum SettingsSearchCatalog {
    static var items: [SettingsSearchItem] {
        [
            SettingsSearchItem(route: .profile, title: AppLocalization.string("Profile"), subtitle: AppLocalization.string("Name, gender, age, height"), keywords: ["profile", "name", "gender", "age", "height", "profil", "imię", "płeć", "wiek", "wzrost"]),
            SettingsSearchItem(route: .metrics, title: AppLocalization.string("Metrics"), subtitle: AppLocalization.string("Tracked measurements"), keywords: ["metrics", "tracked", "measurements", "metryki", "śledzone", "pomiary", "add metric", "remove metric", "dodaj metrykę"]),
            SettingsSearchItem(route: .indicators, title: AppLocalization.string("Indicators"), subtitle: AppLocalization.string("Choose health and physique indicators"), keywords: ["indicators", "health indicators", "physique indicators", "wskaźniki", "zdrowia", "sylwetki", "bmi", "whr", "rfm", "absi"]),
            SettingsSearchItem(route: .physiqueIndicators, title: AppLocalization.string("Physique indicators"), subtitle: AppLocalization.string("Choose health and physique indicators"), keywords: ["physique", "physique indicators", "sylwetka", "wskaźniki sylwetki", "swr", "cwr", "shr"]),
            SettingsSearchItem(route: .health, title: AppLocalization.string("Health"), subtitle: AppLocalization.string("Sync and synced data"), keywords: ["health", "sync", "synced", "healthkit", "apple health", "zdrowie", "synchronizacja", "synchronizowane", "import"]),
            SettingsSearchItem(route: .notifications, title: AppLocalization.string("Notifications"), subtitle: AppLocalization.string("Manage reminders"), keywords: ["notifications", "reminders", "alerts", "smart", "push", "powiadomienia", "przypomnienia", "alerty"]),
            SettingsSearchItem(route: .home, title: AppLocalization.string("Home"), subtitle: AppLocalization.string("Home sections visibility"), keywords: ["home", "dashboard", "sections", "visibility", "widgets", "strona główna", "widoczność", "sekcje"]),
            SettingsSearchItem(route: .aiInsights, title: AppLocalization.string("AI Insights"), subtitle: AppLocalization.string("Enable AI Insights"), keywords: ["ai", "insights", "artificial intelligence", "apple intelligence", "analizy ai", "spostrzeżenia", "sztuczna inteligencja"]),
            SettingsSearchItem(route: .units, title: AppLocalization.string("Units"), subtitle: AppLocalization.string("Metric or imperial"), keywords: ["units", "metric", "imperial", "kg", "lbs", "cm", "inch", "jednostki", "metryczny", "imperialne"]),
            SettingsSearchItem(route: .experience, title: AppLocalization.string("Appearance, animations and haptics"), subtitle: AppLocalization.string("Appearance, animations and haptics"), keywords: ["appearance", "light", "dark", "theme", "animations", "haptics", "vibration", "motion", "wygląd", "jasny", "ciemny", "motyw", "animacje", "haptyka", "wibracje"]),
            SettingsSearchItem(route: .language, title: AppLocalization.string("Language"), subtitle: AppLocalization.string("App language"), keywords: ["language", "app language", "locale", "polish", "english", "język", "polski", "angielski"]),
            SettingsSearchItem(route: .data, title: AppLocalization.string("Data"), subtitle: AppLocalization.string("Export, backup and delete"), keywords: ["data", "export", "delete", "backup", "icloud", "restore", "import", "json", "csv", "pdf", "dane", "eksport", "usuń", "kopia", "przywróć"]),
            SettingsSearchItem(route: .faq, title: AppLocalization.string("FAQ"), subtitle: AppLocalization.string("Read frequently asked questions"), keywords: ["faq", "help", "questions", "support", "pomoc", "pytania", "pomoc techniczna", "jak"]),
            SettingsSearchItem(route: .about, title: AppLocalization.string("About"), subtitle: AppLocalization.string("App version and legal"), keywords: ["about", "version", "legal", "privacy", "terms", "o aplikacji", "wersja", "prywatność"])
        ]
    }
}
