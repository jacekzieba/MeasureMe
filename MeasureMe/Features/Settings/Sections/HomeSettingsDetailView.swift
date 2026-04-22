import SwiftUI

private extension HomeModuleKind {
    var settingsTitle: String {
        switch self {
        case .summaryHero:
            return AppLocalization.string("Summary hero")
        case .quickActions:
            return AppLocalization.string("Quick actions")
        case .keyMetrics:
            return AppLocalization.string("Key metrics")
        case .recentPhotos:
            return AppLocalization.string("Recent photos")
        case .healthSummary:
            return AppLocalization.string("Health summary")
        case .activationHub:
            return FlowLocalization.app("Activation hub", "Hub aktywacji", "Hub de activación", "Aktivierungs-Hub", "Hub d'activation", "Hub de ativação")
        case .setupChecklist:
            return AppLocalization.string("Setup checklist")
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .summaryHero:
            return AppLocalization.string("Greeting, streak, goals, and momentum")
        case .quickActions:
            return AppLocalization.string("Shortcuts for the most common logging flows")
        case .keyMetrics:
            return AppLocalization.string("Your top tracked measurements")
        case .recentPhotos:
            return AppLocalization.string("Latest progress photos")
        case .healthSummary:
            return AppLocalization.string("Compact health indicator summary")
        case .activationHub:
            return FlowLocalization.app("Guided actions for new users", "Prowadzone akcje dla nowych użytkowników", "Acciones guiadas para nuevos usuarios", "Geführte Aktionen für neue Nutzer", "Actions guidées pour les nouveaux utilisateurs", "Ações guiadas para novos usuários")
        case .setupChecklist:
            return AppLocalization.string("Remaining onboarding and setup tasks")
        }
    }

    var settingsSystemImage: String {
        switch self {
        case .summaryHero:
            return "sparkles.rectangle.stack"
        case .quickActions:
            return "bolt.fill"
        case .keyMetrics:
            return "chart.line.uptrend.xyaxis"
        case .recentPhotos:
            return "photo.on.rectangle"
        case .healthSummary:
            return "heart.text.square"
        case .activationHub:
            return "sparkles.rectangle.stack.fill"
        case .setupChecklist:
            return "list.bullet.clipboard"
        }
    }
}

struct HomeSettingsDetailView: View {
    @ObservedObject private var settingsStore = AppSettingsStore.shared
    private let theme = FeatureTheme.settings

    private var layout: HomeLayoutSnapshot {
        settingsStore.homeLayoutSnapshot()
    }

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("Home"), theme: .settings) {
            moduleOverviewCard
            moduleVisibilitySection
            resetSection
        }
        .accessibilityIdentifier("settings.home.detail")
    }

    private var moduleOverviewCard: some View {
        Section {
            SettingsCard(tint: theme.softTint) {
                SettingsCardHeader(title: AppLocalization.string("Home modules"), systemImage: "square.grid.2x2")
                Text(AppLocalization.string("Home now uses a modular dashboard. Full drag-and-drop editing will come later directly on the Home screen."))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private var moduleVisibilitySection: some View {
        let configurableModules = HomeModuleKind.activeCases.filter { $0 != .quickActions }
        return Section {
            SettingsCard(tint: AppColorRoles.surfacePrimary) {
                SettingsCardHeader(title: AppLocalization.string("Visible modules"), systemImage: "eye")

                ForEach(configurableModules, id: \.self) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        HStack(spacing: 12) {
                            GlassPillIcon(systemName: kind.settingsSystemImage)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.settingsTitle)
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                                Text(kind.settingsSubtitle)
                                    .font(AppTypography.micro)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                            }
                        }
                    }
                    .tint(theme.accent)

                    if kind != configurableModules.last {
                        SettingsRowDivider()
                    }
                }
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private var resetSection: some View {
        Section {
            SettingsCard(tint: AppColorRoles.surfaceInteractive) {
                SettingsCardHeader(title: AppLocalization.string("Layout"), systemImage: "arrow.counterclockwise")
                Text(AppLocalization.string("Restore the recommended Home arrangement while keeping your current module visibility choices."))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)

                Button {
                    Haptics.selection()
                    settingsStore.resetHomeLayout()
                } label: {
                    Text(AppLocalization.string("Reset Home layout"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppSecondaryButtonStyle(cornerRadius: AppRadius.md))
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private func binding(for kind: HomeModuleKind) -> Binding<Bool> {
        Binding(
            get: {
                switch kind {
                case .activationHub:
                    let isVisible = layout.item(for: kind)?.isVisible ?? true
                    return isVisible && !settingsStore.snapshot.onboarding.activationIsDismissed
                default:
                    return layout.item(for: kind)?.isVisible ?? true
                }
            },
            set: { newValue in
                Haptics.selection()
                settingsStore.setHomeModuleVisibility(newValue, for: kind)
                if kind == .activationHub {
                    settingsStore.set(\.onboarding.activationIsDismissed, !newValue)
                }
            }
        )
    }
}
