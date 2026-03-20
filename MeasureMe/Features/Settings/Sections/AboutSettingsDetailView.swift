import SwiftUI

struct AboutSettingsDetailView: View {
    @AppSetting(\.diagnostics.diagnosticsLoggingEnabled) private var diagnosticsLoggingEnabled: Bool = true
    @Environment(\.openURL) private var openURL
    private let theme = FeatureTheme.settings
    let onReportBug: () -> Void

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("About"), theme: .settings) {
            Section {
                SettingsCard(tint: AppColorRoles.surfacePrimary) {
                    SettingsCardHeader(title: AppLocalization.string("About"), systemImage: "info.circle")

                        Button {
                            openURL(LegalLinks.about)
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "safari")
                                Text(AppLocalization.string("Website"))
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(AppColorRoles.textTertiary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        SettingsRowDivider()

                        Button {
                            openURL(LegalLinks.featureRequest)
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "lightbulb")
                                Text(AppLocalization.string("Feature request"))
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(AppColorRoles.textTertiary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        SettingsRowDivider()

                        Button {
                            onReportBug()
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "ladybug")
                                Text(AppLocalization.string("Report a bug"))
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(settingsComponentsRowInsets)
            .listRowBackground(Color.clear)

            Section {
                SettingsCard(tint: AppColorRoles.surfacePrimary) {
                    SettingsCardHeader(title: AppLocalization.string("Diagnostics"), systemImage: "exclamationmark.bubble")

                        NavigationLink {
                            CrashReportView()
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "exclamationmark.bubble")
                                Text(AppLocalization.string("Crash Reports"))
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }

                        SettingsRowDivider()

                        HStack(alignment: .top, spacing: 12) {
                            GlassPillIcon(systemName: "doc.text")
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppLocalization.string("Include diagnostic logs in crash reports"))
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                                Text(AppLocalization.string("When enabled, recent app logs may be attached to reports you share."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                            }

                            Spacer(minLength: 12)

                            Toggle("", isOn: $diagnosticsLoggingEnabled)
                                .labelsHidden()
                                .frame(width: 52, alignment: .trailing)
                        }
                        .tint(theme.accent)
                        .onChange(of: diagnosticsLoggingEnabled) { _, _ in Haptics.selection() }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("settings.data.diagnostics.logging.toggle")
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(settingsComponentsRowInsets)
            .listRowBackground(Color.clear)

            Section {
                SettingsCard(tint: AppColorRoles.surfaceInteractive) {
                    SettingsCardHeader(title: AppLocalization.string("Credits"), systemImage: "heart")

                        Button {
                            openURL(URL(string: "https://icons8.com")!)
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "paintbrush")
                                Text(AppLocalization.string("Icons by Icons8"))
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(AppColorRoles.textTertiary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(settingsComponentsRowInsets)
            .listRowBackground(Color.clear)
        }
    }
}
