import SwiftUI
import SwiftData

// MARK: - UI Test Hooks

extension HomeView {

    var homeUITestHooks: some View {
        VStack(spacing: 0) {
            if showActivationHub {
                Text("1")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.module.activationHub.visible")
                    .frame(width: 1, height: 1)
                    .clipped()
                Text(activationCurrentTask?.rawValue ?? "")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.activation.currentTask")
                    .frame(width: 1, height: 1)
                    .clipped()
            }

            if showHomeSettingsSheet {
                Text("1")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.settings.sheet.present")
                    .frame(width: 1, height: 1)
                    .clipped()
            }

            Text(nextFocusInsight.accessibilityValue)
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("home.nextFocus.mode")
                .frame(width: 1, height: 1)
                .clipped()

            Text(nextFocusInsight.cta)
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("home.nextFocus.cta")
                .frame(width: 1, height: 1)
                .clipped()

            ForEach(homeSecondaryMetricUITestKinds, id: \.self) { kind in
                Button {
                    if viewModel.expandedSecondaryMetrics.contains(kind) {
                        viewModel.expandedSecondaryMetrics.remove(kind)
                    } else {
                        viewModel.expandedSecondaryMetrics.insert(kind)
                    }
                } label: {
                    Color.clear
                        .frame(width: 80, height: 80)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle \(kind.rawValue)")
                .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).toggle")
            }

            ForEach(Array(viewModel.expandedSecondaryMetrics), id: \.self) { kind in
                VStack {
                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("expanded")
                .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).expanded")
                .frame(width: 44, height: 44)
                .opacity(0.01)
                .allowsHitTesting(false)
            }

            ForEach(Array(viewModel.expandedSecondaryMetrics), id: \.self) { kind in
                Button("collapse") { collapseSecondaryMetric(kind) }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .opacity(0.01)
                .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).collapseHook")
            }

            Text("\(viewModel.expandedSecondaryMetrics.count)")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("home.keyMetrics.secondary.expandedCount")
                .frame(width: 1, height: 1)
                .clipped()

            Text(viewModel.expandedSecondaryMetrics.map(\.rawValue).sorted().joined(separator: ","))
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("home.keyMetrics.secondary.expandedIDs")
                .frame(width: 1, height: 1)
                .clipped()
        }
    }

    var homeSecondaryMetricUITestKinds: [MetricKind] {
        let visibleBuiltInSecondary = dashboardKeyIdentifiers.dropFirst().compactMap(MetricKind.init(rawValue:))
        if !visibleBuiltInSecondary.isEmpty {
            return visibleBuiltInSecondary
        }

        let fallbackKinds: [MetricKind] = [.bodyFat, .leanBodyMass, .waist]
        let activeFallbackKinds = fallbackKinds.filter { metricsStore.activeKinds.contains($0) }
        return activeFallbackKinds.isEmpty ? fallbackKinds : activeFallbackKinds
    }
}
