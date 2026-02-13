import SwiftUI

struct TrackedMeasurementsView: View {
    @EnvironmentObject private var metricsStore: ActiveMetricsStore

    @State private var isEditingActive = false
    @State private var showKeyMetricsLimitAlert = false

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(
                topHeight: 380,
                tint: Color.cyan.opacity(0.22)
            )

            ScrollViewReader { proxy in
                List {
                    KeyMetricsSection(
                        store: metricsStore,
                        showLimitAlert: $showKeyMetricsLimitAlert
                    )

                    if !metricsStore.activeKinds.isEmpty {
                        ActiveMetricsSection(
                            store: metricsStore,
                            isEditing: $isEditingActive,
                            scrollProxy: proxy
                        )
                    }

                    MetricsSection(
                        title: AppLocalization.string("Health App Synced"),
                        subtitle: AppLocalization.string("tracked.section.health.subtitle"),
                        systemImage: "heart.fill",
                        iconTint: Color(red: 1.0, green: 0.27, blue: 0.33),
                        rows: metricsStore.bodyComposition + metricsStore.bodySize,
                        store: metricsStore
                    )

                    MetricsSection(
                        title: AppLocalization.string("Custom metrics"),
                        subtitle: AppLocalization.string("tracked.section.custom.subtitle"),
                        systemImage: "slider.horizontal.3",
                        iconTint: Color.appAccent,
                        rows: metricsStore.upperBody
                            + metricsStore.arms
                            + metricsStore.lowerBody,
                        store: metricsStore
                    )
                }
                .environment(\.editMode, .constant(isEditingActive ? .active : .inactive))
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .listSectionSpacing(20)
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .padding(.top, -8)
            }
        }
        .navigationTitle(AppLocalization.string("Tracked measurements"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert(AppLocalization.string("Limit reached"), isPresented: $showKeyMetricsLimitAlert) {
            Button(AppLocalization.string("OK"), role: .cancel) { }
        } message: {
            Text(AppLocalization.string("You can choose up to 3 key metrics for Home."))
        }
    }
}

private struct KeyMetricsSection: View {
    @ObservedObject var store: ActiveMetricsStore
    @Binding var showLimitAlert: Bool

    private var starredCount: Int {
        store.activeKinds.filter { store.isKeyMetric($0) }.count
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(AppLocalization.string("tracked.keymetrics.header"))
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color.appAccent)
                }
                .font(AppTypography.bodyEmphasis)

                Text(AppLocalization.string("tracked.keymetrics.description"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AppLocalization.string("tracked.keymetrics.counter", starredCount))
                    .font(AppTypography.micro)
                    .foregroundStyle(starredCount >= 1 ? Color.appAccent : Color.secondary.opacity(0.6))
                    .padding(.top, 2)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if store.activeKinds.isEmpty {
                Text(AppLocalization.string("tracked.keymetrics.empty"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(store.activeKinds, id: \.self) { kind in
                    HStack(spacing: 12) {
                        Image(systemName: kind.systemImage)
                            .scaleEffect(x: kind.shouldMirrorSymbol ? -1 : 1, y: 1)
                            .frame(width: MetricsLayout.iconWidth)

                        Text(kind.title)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            let next = !store.isKeyMetric(kind)
                            let didSet = store.setKeyMetric(next, for: kind)
                            if !didSet {
                                showLimitAlert = true
                            }
                        } label: {
                            Image(systemName: store.isKeyMetric(kind) ? "star.fill" : "star")
                                .foregroundStyle(store.isKeyMetric(kind) ? Color.appAccent : .secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(store.isKeyMetric(kind)
                            ? AppLocalization.string("accessibility.keymetric.remove")
                            : AppLocalization.string("accessibility.keymetric.add"))
                    }
                    .frame(maxWidth: .infinity, minHeight: MetricsLayout.rowHeight, alignment: .leading)
                    .padding(.horizontal, MetricsLayout.horizontalPadding)
                    .padding(.vertical, 10)
                    .padding(.vertical, 3)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .textCase(nil)
    }
}
