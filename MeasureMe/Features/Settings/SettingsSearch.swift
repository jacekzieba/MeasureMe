import Foundation

enum SettingsSearchRoute: String, Hashable {
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
            SettingsSearchItem(route: .metrics, title: AppLocalization.string("Metrics"), subtitle: AppLocalization.string("Tracked measurements"), keywords: ["metrics", "tracked", "measurements", "metryki", "śledzone", "pomiary"]),
            SettingsSearchItem(route: .indicators, title: AppLocalization.string("Indicators"), subtitle: AppLocalization.string("Choose health and physique indicators"), keywords: ["indicators", "health indicators", "physique indicators", "wskaźniki", "zdrowia", "sylwetki"]),
            SettingsSearchItem(route: .physiqueIndicators, title: AppLocalization.string("Physique indicators"), subtitle: AppLocalization.string("Choose health and physique indicators"), keywords: ["physique", "physique indicators", "sylwetka", "wskaźniki sylwetki"]),
            SettingsSearchItem(route: .health, title: AppLocalization.string("Health"), subtitle: AppLocalization.string("Sync and synced data"), keywords: ["health", "sync", "synced", "zdrowie", "synchronizacja", "synchronizowane"]),
            SettingsSearchItem(route: .notifications, title: AppLocalization.string("Notifications"), subtitle: AppLocalization.string("Manage reminders"), keywords: ["notifications", "reminders", "powiadomienia", "przypomnienia"]),
            SettingsSearchItem(route: .home, title: AppLocalization.string("Home"), subtitle: AppLocalization.string("Home sections visibility"), keywords: ["home", "strona główna", "widoczność"]),
            SettingsSearchItem(route: .aiInsights, title: AppLocalization.string("AI Insights"), subtitle: AppLocalization.string("Enable AI Insights"), keywords: ["ai", "insights", "analizy ai", "apple intelligence"]),
            SettingsSearchItem(route: .units, title: AppLocalization.string("Units"), subtitle: AppLocalization.string("Metric or imperial"), keywords: ["units", "metric", "imperial", "jednostki", "metryczny", "imperialne"]),
            SettingsSearchItem(route: .experience, title: AppLocalization.string("Animations and haptics"), subtitle: AppLocalization.string("Animations and haptics"), keywords: ["animations", "haptics", "animacje", "haptyka"]),
            SettingsSearchItem(route: .language, title: AppLocalization.string("Language"), subtitle: AppLocalization.string("App language"), keywords: ["language", "app language", "język", "polski", "english"]),
            SettingsSearchItem(route: .data, title: AppLocalization.string("Data"), subtitle: AppLocalization.string("Export and delete"), keywords: ["data", "export", "delete", "dane", "eksport", "usuń"]),
            SettingsSearchItem(route: .faq, title: AppLocalization.string("FAQ"), subtitle: AppLocalization.string("Read frequently asked questions"), keywords: ["faq", "help", "pomoc", "pytania"])
        ]
    }
}
