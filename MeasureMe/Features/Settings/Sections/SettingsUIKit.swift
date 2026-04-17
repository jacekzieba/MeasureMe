import SwiftUI

private let settingsDetailTheme = FeatureTheme.settings
private let settingsDetailTopInset: CGFloat = 12

struct SettingsBackdrop: View {
    var topHeight: CGFloat = 380
    var scrollOffset: CGFloat = 0
    var tint: Color = settingsDetailTheme.strongTint

    var body: some View {
        AppScreenBackground(
            topHeight: topHeight,
            scrollOffset: scrollOffset,
            tint: tint
        )
    }
}

struct SettingsCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            content
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppGlassBackground(
                depth: .elevated,
                cornerRadius: AppRadius.md,
                tint: tint
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}

struct SettingsSectionEyebrow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.eyebrow)
            .foregroundStyle(AppColorRoles.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SettingsCardHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(AppTypography.iconMedium)
                    .foregroundStyle(AppColorRoles.accentPrimary)
            }
            Text(title)
                .font(AppTypography.bodyStrong)
                .foregroundStyle(AppColorRoles.textPrimary)
        }
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColorRoles.borderSubtle)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }
}

struct SettingsSummaryRowLabel: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    var trailingText: String? = nil
    var trailingSymbol: String? = "chevron.right"
    var accent: Color = AppColorRoles.accentPrimary

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            if let systemImage {
                GlassPillIcon(systemName: systemImage)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            if let trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(AppTypography.iconSmall)
                    .foregroundStyle(AppColorRoles.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct SettingsNavigationRow<Destination: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    var trailingText: String? = nil
    var accessibilityIdentifier: String? = nil
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsSummaryRowLabel(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                trailingText: trailingText,
                trailingSymbol: nil
            )
            .accessibilityIdentifier(accessibilityIdentifier ?? "")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct SettingsActionRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    var trailingText: String? = nil
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsSummaryRowLabel(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                trailingText: trailingText
            )
            .accessibilityIdentifier(accessibilityIdentifier ?? "")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct SettingsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SettingsDetailScaffold<Content: View>: View {
    let title: String
    var theme: FeatureTheme = .settings
    @ViewBuilder let content: Content

    init(
        title: String,
        theme: FeatureTheme = .settings,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            SettingsBackdrop(topHeight: 380, tint: theme.strongTint)

            List {
                content
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: settingsDetailTopInset)
                    .accessibilityHidden(true)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct SettingsScrollDetailScaffold<Content: View>: View {
    let title: String
    var theme: FeatureTheme = .settings
    @ViewBuilder let content: Content

    init(
        title: String,
        theme: FeatureTheme = .settings,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            SettingsBackdrop(topHeight: 380, tint: theme.strongTint)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: settingsDetailTopInset)
                    .accessibilityHidden(true)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct SettingsCompactSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.titleCompact)
                .foregroundStyle(AppColorRoles.textPrimary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsStatusBadge: View {
    let title: String
    var accent: Color = settingsDetailTheme.accent

    var body: some View {
        Text(title)
            .font(AppTypography.badge)
            .foregroundStyle(AppColorRoles.textOnAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(accent)
            )
    }
}

struct SettingsToggleRow<Label: View>: View {
    @Binding var isOn: Bool
    var accent: Color = settingsDetailTheme.accent
    var accessibilityIdentifier: String? = nil
    @ViewBuilder let label: Label

    init(
        isOn: Binding<Bool>,
        accent: Color = settingsDetailTheme.accent,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder label: () -> Label
    ) {
        _isOn = isOn
        self.accent = accent
        self.accessibilityIdentifier = accessibilityIdentifier
        self.label = label()
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            label
        }
        .tint(accent)
        .frame(minHeight: 44)
        .onChange(of: isOn) { _, _ in
            Haptics.selection()
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct SettingsValueRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer(minLength: 12)
            trailing
        }
        .frame(minHeight: 44)
    }
}

struct SettingsDestructiveRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: 12) {
                GlassPillIcon(systemName: systemImage)
                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.stateError)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsNoteCard: View {
    let title: String
    let bodyText: String
    var systemImage: String = "info.circle"
    var accent: Color = settingsDetailTheme.accent

    var body: some View {
        SettingsCard(tint: AppColorRoles.surfacePrimary) {
            SettingsCardHeader(title: title, systemImage: systemImage)
            Text(bodyText)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
