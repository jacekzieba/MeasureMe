import SwiftUI

struct TrackedMeasurementsView: View {
    @EnvironmentObject private var metricsStore: ActiveMetricsStore

    @State private var isEditingActive = false
    @State private var showKeyMetricsLimitAlert = false

    // MARK: - Snackbar state
    @State private var snackbarMessage: String = ""
    @State private var snackbarUndoAction: (() -> Void)?
    @State private var showSnackbar: Bool = false
    @State private var snackbarWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(
                topHeight: 380,
                tint: Color.cyan.opacity(0.22)
            )

            ScrollViewReader { proxy in
                List {
                    if !metricsStore.activeKinds.isEmpty {
                        ActiveMetricsSection(
                            store: metricsStore,
                            isEditing: $isEditingActive,
                            showLimitAlert: $showKeyMetricsLimitAlert,
                            scrollProxy: proxy,
                            onStopTracking: { kind in
                                presentSnackbar(
                                    message: AppLocalization.string("tracked.snackbar.removed"),
                                    undo: { metricsStore.setEnabled(true, for: kind) }
                                )
                            }
                        )
                    }

                    MetricsSection(
                        title: AppLocalization.string("Health App Synced"),
                        subtitle: AppLocalization.string("tracked.section.health.subtitle"),
                        systemImage: "heart.fill",
                        iconTint: Color(red: 1.0, green: 0.27, blue: 0.33),
                        rows: metricsStore.bodyComposition + metricsStore.bodySize,
                        store: metricsStore,
                        onToggleChanged: { kind, isEnabled in
                            handleToggleChanged(kind: kind, isEnabled: isEnabled)
                        }
                    )

                    MetricsSection(
                        title: AppLocalization.string("Custom metrics"),
                        subtitle: AppLocalization.string("tracked.section.custom.subtitle"),
                        systemImage: "slider.horizontal.3",
                        iconTint: Color.appAccent,
                        rows: metricsStore.upperBody
                            + metricsStore.arms
                            + metricsStore.lowerBody,
                        store: metricsStore,
                        onToggleChanged: { kind, isEnabled in
                            handleToggleChanged(kind: kind, isEnabled: isEnabled)
                        }
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
        .overlay(alignment: .bottom) {
            snackbarOverlay
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

    // MARK: - Toggle callback

    private func handleToggleChanged(kind: MetricKind, isEnabled: Bool) {
        Haptics.selection()
        let message = isEnabled
            ? AppLocalization.string("tracked.snackbar.added")
            : AppLocalization.string("tracked.snackbar.removed")
        presentSnackbar(
            message: message,
            undo: { metricsStore.setEnabled(!isEnabled, for: kind) }
        )
    }

    // MARK: - Snackbar

    @ViewBuilder
    private var snackbarOverlay: some View {
        if showSnackbar {
            HStack(spacing: 12) {
                Text(snackbarMessage)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white)

                if snackbarUndoAction != nil {
                    Button {
                        snackbarUndoAction?()
                        dismissSnackbar()
                    } label: {
                        Text(AppLocalization.string("tracked.snackbar.undo"))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(Color.appAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.75))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 24)
        }
    }

    private func presentSnackbar(message: String, undo: @escaping () -> Void) {
        // Cancel previous auto-dismiss
        snackbarWorkItem?.cancel()

        snackbarMessage = message
        snackbarUndoAction = undo
        withAnimation(.easeOut(duration: 0.2)) {
            showSnackbar = true
        }

        let work = DispatchWorkItem { dismissSnackbar() }
        snackbarWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func dismissSnackbar() {
        withAnimation(.easeIn(duration: 0.2)) {
            showSnackbar = false
        }
    }
}
