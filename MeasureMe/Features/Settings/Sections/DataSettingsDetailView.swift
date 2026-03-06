import SwiftUI

struct DataSettingsDetailView: View {
    @AppSetting(\.analytics.analyticsEnabled) private var analyticsEnabled: Bool = true
    let onExport: () -> Void
    let onImport: () -> Void
    let onSeedDummyData: () -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                        SettingsCardHeader(title: AppLocalization.string("Data"), systemImage: "square.and.arrow.up")
                        Button(action: onExport) {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "square.and.arrow.up")
                                Text(AppLocalization.string("Export data"))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        SettingsRowDivider()

                        Button(action: onImport) {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "square.and.arrow.down")
                                Text(AppLocalization.string("Import data"))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        SettingsRowDivider()

                        HStack(alignment: .top, spacing: 12) {
                            GlassPillIcon(systemName: "chart.xyaxis.line")
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppLocalization.string("Share anonymous analytics"))
                                Text(AppLocalization.string("Helps improve app quality and UX. No health values or personal data are sent."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 12)

                            Toggle("", isOn: $analyticsEnabled)
                                .labelsHidden()
                                .frame(width: 52, alignment: .trailing)
                        }
                        .tint(Color.appAccent)
                        .onChange(of: analyticsEnabled) { _, _ in
                            Haptics.selection()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("settings.data.analytics.toggle")

                        SettingsRowDivider()

                        Button(action: onSeedDummyData) {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "wand.and.stars")
                                Text(AppLocalization.string("Seed dummy data"))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        SettingsRowDivider()

                        Button(role: .destructive, action: onDeleteAll) {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "trash")
                                Text(AppLocalization.string("Delete all data"))
                                    .foregroundStyle(.red)
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
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Data"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
