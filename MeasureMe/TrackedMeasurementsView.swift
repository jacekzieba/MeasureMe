import SwiftUI

struct TrackedMeasurementsView: View {
    @EnvironmentObject private var metricsStore: ActiveMetricsStore

    @State private var isEditingActive = false
    @State private var selectedKind: MetricKind?
    @State private var showKeyMetricsLimitAlert = false

    var body: some View {
        NavigationStack {
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
            }
            .navigationTitle(AppLocalization.string("Tracked measurements"))
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
}

private struct KeyMetricsSection: View {
    @ObservedObject var store: ActiveMetricsStore
    @Binding var showLimitAlert: Bool

    var body: some View {
        Section {
            if store.activeKinds.isEmpty {
                Text(AppLocalization.string("Enable metrics below to pick key metrics for Home."))
                    .foregroundStyle(.secondary)
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
                    .background(Color(.secondarySystemGroupedBackground))
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init())
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string("Home key metrics"))
                Text(AppLocalization.string("Choose up to 3 to show on Home and Measurements."))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
