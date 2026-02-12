import SwiftUI

struct TrackedMeasurementsView: View {
    @EnvironmentObject private var metricsStore: ActiveMetricsStore

    @State private var isEditingActive = false
    @State private var selectedKind: MetricKind?
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
                            selectedKind: $selectedKind,
                            scrollProxy: proxy
                        )
                    }

                    MetricsSection(
                        title: AppLocalization.string("Health App Synced"),
                        systemImage: "heart.fill",
                        rows: metricsStore.bodyComposition + metricsStore.bodySize,
                        store: metricsStore,
                        selectedKind: $selectedKind
                    )

                    MetricsSection(
                        title: AppLocalization.string("Custom metrics"),
                        systemImage: "slider.horizontal.3",
                        rows: metricsStore.upperBody
                            + metricsStore.arms
                            + metricsStore.lowerBody,
                        store: metricsStore,
                        selectedKind: $selectedKind
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
        .navigationDestination(item: $selectedKind) { kind in
            MetricDetailView(kind: kind)
        }
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

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string("Home key metrics"))
                Text(AppLocalization.string("Choose up to 3 to show on Home and Measurements."))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if store.activeKinds.isEmpty {
                Text(AppLocalization.string("Enable metrics below to pick key metrics for Home."))
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
