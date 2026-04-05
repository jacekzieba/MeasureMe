import SwiftUI

struct SettingsOverviewSnapshot {
    let accountTitle: String
    let accountSubtitle: String
    let homeModuleSummary: String
    let notificationsSummary: String
    let languageSummary: String
    let unitsSummary: String
    let experienceSummary: String
    let profileSummary: String
    let trackedMetricsSummary: String
    let indicatorsSummary: String
    let aiSummary: String
    let healthSummary: String
    let isPremium: Bool
}

struct SettingsSearchSection: View {
    @Binding var query: String

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Section {
            SettingsCard(tint: AppColorRoles.surfaceElevated) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(AppTypography.iconMedium)
                        .foregroundStyle(AppColorRoles.textTertiary)
                        .accessibilityHidden(true)

                    TextField(
                        AppLocalization.string("Search Settings"),
                        text: $query
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .accessibilityIdentifier("settings.search.field")

                    if isSearching {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppTypography.iconMedium)
                                .foregroundStyle(AppColorRoles.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.search.clear")
                    }
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("settings.section.search")
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(SettingsView.settingsRowInsets)
    }
}

struct SettingsSearchResultsSection: View {
    let items: [SettingsSearchItem]
    let onOpenRoute: (SettingsSearchRoute) -> Void

    var body: some View {
        Section {
            if items.isEmpty {
                Text(AppLocalization.string("No matching settings"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            } else {
                ForEach(items) { item in
                    Button {
                        onOpenRoute(item.route)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(AppTypography.bodyStrong)
                                .foregroundStyle(AppColorRoles.textPrimary)
                            Text(item.subtitle)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .appHitTarget()
                }
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(SettingsView.settingsRowInsets)
    }
}

struct SettingsOverviewSections: View {
    let snapshot: SettingsOverviewSnapshot
    let onOpenRoute: (SettingsSearchRoute) -> Void
    let onRestorePurchases: () -> Void
    let onShareApp: () -> Void
    let onTerms: () -> Void
    let onPrivacy: () -> Void
    let onAccessibility: () -> Void
    let onExplorePremium: () -> Void
    let onManageSubscription: () -> Void

    private let settingsTheme = FeatureTheme.settings
    private let healthTheme = FeatureTheme.health

    var body: some View {
        accountSection
        setupSection
        measurementsSection
        insightsSection
        healthSection
        supportSection
        appSection
    }

    private var accountSection: some View {
        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.account"))

            SettingsCard(tint: settingsTheme.strongTint) {
                HStack(spacing: AppSpacing.sm) {
                    Image("BrandButton")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.accountTitle)
                            .font(AppTypography.displayStatement)
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Text(snapshot.accountSubtitle)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }

                    Spacer()
                }

                if snapshot.isPremium {
                    SettingsActionRow(
                        title: AppLocalization.string("Manage subscription"),
                        subtitle: AppLocalization.string("settings.summary.subscription.manage"),
                        systemImage: "crown.fill",
                        trailingText: nil,
                        accessibilityIdentifier: "settings.row.manageSubscription"
                    ) {
                        onManageSubscription()
                    }

                    SettingsRowDivider()

                    SettingsNavigationRow(
                        title: AppLocalization.string("Premium Edition"),
                        subtitle: AppLocalization.string("settings.app.subscription.view.benefits"),
                        systemImage: "checkmark.seal.fill",
                        trailingText: nil,
                        accessibilityIdentifier: "settings.row.premiumBenefits"
                    ) {
                        PremiumBenefitsInfoView()
                    }
                } else {
                    Text(AppLocalization.string("settings.summary.premium.pitch"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        onExplorePremium()
                    } label: {
                        Text(AppLocalization.string("settings.action.explorePremium"))
                    }
                    .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                    .accessibilityIdentifier("settings.action.explorePremium")
                }
            }
            .accessibilityIdentifier("settings.section.account")
        }
        .settingsOverviewListStyle()
    }

    private var setupSection: some View {
        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.setup"))

            SettingsCard(tint: FeatureTheme.home.softTint) {
                SettingsOverviewRouteRow(route: .home, title: AppLocalization.string("Home"), subtitle: snapshot.homeModuleSummary, systemImage: "house.fill", accessibilityIdentifier: "settings.row.home", onOpenRoute: onOpenRoute)
                SettingsRowDivider()
                SettingsOverviewRouteRow(route: .notifications, title: AppLocalization.string("Notifications"), subtitle: snapshot.notificationsSummary, systemImage: "bell.badge", accessibilityIdentifier: "settings.row.notifications", onOpenRoute: onOpenRoute)
                SettingsRowDivider()
                SettingsOverviewRouteRow(route: .language, title: AppLocalization.string("Language"), subtitle: snapshot.languageSummary, systemImage: "globe", accessibilityIdentifier: "settings.row.language", onOpenRoute: onOpenRoute)
                SettingsRowDivider()
                SettingsOverviewRouteRow(route: .units, title: AppLocalization.string("Units"), subtitle: snapshot.unitsSummary, systemImage: "ruler", accessibilityIdentifier: "settings.row.units", onOpenRoute: onOpenRoute)
                SettingsRowDivider()
                SettingsOverviewRouteRow(route: .experience, title: AppLocalization.string("Appearance, animations and haptics"), subtitle: snapshot.experienceSummary, systemImage: "circle.lefthalf.filled.inverse", accessibilityIdentifier: "settings.row.experience", onOpenRoute: onOpenRoute)
            }
            .accessibilityIdentifier("settings.section.setup")
        }
        .settingsOverviewListStyle()
    }

    private var measurementsSection: some View {
        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.measurements"))

            SettingsCard(tint: FeatureTheme.measurements.softTint) {
                SettingsOverviewRouteRow(route: .profile, title: AppLocalization.string("Profile"), subtitle: snapshot.profileSummary, systemImage: "person.crop.circle", accessibilityIdentifier: "settings.row.profile", onOpenRoute: onOpenRoute)
                SettingsRowDivider()
                SettingsOverviewRouteRow(route: .metrics, title: AppLocalization.string("Metrics"), subtitle: snapshot.trackedMetricsSummary, systemImage: "list.bullet.clipboard", accessibilityIdentifier: "settings.row.metrics", onOpenRoute: onOpenRoute)
                SettingsRowDivider()
                SettingsOverviewRouteRow(route: .indicators, title: AppLocalization.string("Indicators"), subtitle: snapshot.indicatorsSummary, systemImage: "slider.horizontal.3", accessibilityIdentifier: "settings.row.indicators", onOpenRoute: onOpenRoute)
            }
            .accessibilityIdentifier("settings.section.measurements")
        }
        .settingsOverviewListStyle()
    }

    private var insightsSection: some View {
        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.insights"))

            SettingsCard(tint: FeatureTheme.premium.softTint) {
                SettingsOverviewRouteRow(route: .aiInsights, title: AppLocalization.string("AI Insights"), subtitle: snapshot.aiSummary, systemImage: "sparkles", accessibilityIdentifier: "settings.row.ai", onOpenRoute: onOpenRoute)
            }
            .accessibilityIdentifier("settings.section.insights")
        }
        .settingsOverviewListStyle()
    }

    private var healthSection: some View {
        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.health"))

            SettingsCard(tint: healthTheme.softTint) {
                SettingsOverviewRouteRow(route: .health, title: AppLocalization.string("Health"), subtitle: snapshot.healthSummary, systemImage: "heart.fill", accessibilityIdentifier: "settings.row.health", onOpenRoute: onOpenRoute)
            }
            .accessibilityIdentifier("settings.section.health")
        }
        .settingsOverviewListStyle()
    }

    private var supportSection: some View {
        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.support"))

            SettingsCard(tint: FeatureTheme.photos.softTint) {
                SettingsOverviewRouteRow(route: .data, title: AppLocalization.string("Data"), subtitle: AppLocalization.string("settings.summary.data"), systemImage: "square.and.arrow.up", accessibilityIdentifier: "settings.row.data", onOpenRoute: onOpenRoute)
                SettingsRowDivider()
                SettingsOverviewRouteRow(route: .faq, title: AppLocalization.string("FAQ"), subtitle: AppLocalization.string("settings.summary.support"), systemImage: "questionmark.circle", accessibilityIdentifier: "settings.row.faq", onOpenRoute: onOpenRoute)
                SettingsRowDivider()
                SettingsOverviewRouteRow(route: .about, title: AppLocalization.string("About"), subtitle: AppLocalization.string("About MeasureMe"), systemImage: "info.circle", accessibilityIdentifier: "settings.row.about", onOpenRoute: onOpenRoute)
            }
            .accessibilityIdentifier("settings.section.support")
        }
        .settingsOverviewListStyle()
    }

    private var appSection: some View {
        Section {
            SettingsCard(tint: FeatureTheme.measurements.softTint) {
                SettingsCardHeader(title: AppLocalization.string("App"), systemImage: "iphone.gen3.sizes")

                Button(action: onRestorePurchases) {
                    SettingsAppSectionRowLabel(
                        title: AppLocalization.string("Restore purchases"),
                        trailingSymbol: "arrow.clockwise.circle"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("settings.row.restorePurchases")

                SettingsRowDivider()

                Button(action: onShareApp) {
                    SettingsAppSectionRowLabel(
                        title: AppLocalization.string("Share app"),
                        subtitle: "MeasureMe – Body Tracker",
                        trailingSymbol: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("settings.row.shareApp")

                SettingsRowDivider()

                Button(action: onTerms) {
                    SettingsAppSectionRowLabel(
                        title: AppLocalization.string("Terms of Use"),
                        trailingSymbol: "arrow.up.right.square"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                SettingsRowDivider()

                Button(action: onPrivacy) {
                    SettingsAppSectionRowLabel(
                        title: AppLocalization.string("Privacy Policy"),
                        trailingSymbol: "arrow.up.right.square"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                SettingsRowDivider()

                Button(action: onAccessibility) {
                    SettingsAppSectionRowLabel(
                        title: AppLocalization.string("Accessibility"),
                        trailingSymbol: "arrow.up.right.square"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("settings.section.app")
        }
        .settingsOverviewListStyle()
    }
}

private struct SettingsOverviewRouteRow: View {
    let route: SettingsSearchRoute
    let title: String
    let subtitle: String
    let systemImage: String
    let accessibilityIdentifier: String
    let onOpenRoute: (SettingsSearchRoute) -> Void

    var body: some View {
        SettingsActionRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            onOpenRoute(route)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct SettingsAppSectionRowLabel: View {
    let title: String
    let subtitle: String?
    let trailingSymbol: String?
    var trailingColor: Color = .secondary

    init(
        title: String,
        subtitle: String? = nil,
        trailingSymbol: String? = nil,
        trailingColor: Color = .secondary
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailingSymbol = trailingSymbol
        self.trailingColor = trailingColor
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
            }

            Spacer(minLength: 8)

            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trailingColor)
                    .frame(width: 18, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

private extension View {
    func settingsOverviewListStyle() -> some View {
        self
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(SettingsView.settingsRowInsets)
    }
}
