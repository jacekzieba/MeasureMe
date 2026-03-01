import SwiftUI

struct AboutSettingsDetailView: View {
    @AppSetting("diagnostics_logging_enabled") private var diagnosticsLoggingEnabled: Bool = true
    @Environment(\.openURL) private var openURL
    let onReportBug: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("About"), systemImage: "info.circle")

                        Button {
                            openURL(LegalLinks.about)
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "safari")
                                Text(AppLocalization.string("Website"))
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.secondary)
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
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.secondary)
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
                    SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                        SettingsCardHeader(title: AppLocalization.string("Diagnostics"), systemImage: "exclamationmark.bubble")

                        NavigationLink {
                            CrashReportView()
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "exclamationmark.bubble")
                                Text(AppLocalization.string("Crash Reports"))
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
                                Text(AppLocalization.string("When enabled, recent app logs may be attached to reports you share."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 12)

                            Toggle("", isOn: $diagnosticsLoggingEnabled)
                                .labelsHidden()
                                .frame(width: 52, alignment: .trailing)
                        }
                        .tint(Color.appAccent)
                        .onChange(of: diagnosticsLoggingEnabled) { _, _ in
                            Haptics.selection()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("settings.data.diagnostics.logging.toggle")
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.04)) {
                        SettingsCardHeader(title: AppLocalization.string("Credits"), systemImage: "heart")

                        Button {
                            openURL(URL(string: "https://icons8.com")!)
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "paintbrush")
                                Text(AppLocalization.string("Icons by Icons8"))
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.secondary)
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
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("About"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
