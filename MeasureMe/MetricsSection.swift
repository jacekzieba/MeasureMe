import SwiftUI

struct MetricsSection: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let iconTint: Color
    let rows: [MetricKind]
    @ObservedObject var store: ActiveMetricsStore
    var onToggleChanged: ((_ kind: MetricKind, _ isNowEnabled: Bool) -> Void)?

    @State private var isExpanded = true
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            headerButton

            if isExpanded {
                ForEach(rows, id: \.self) { kind in
                    MetricRowView(
                        kind: kind,
                        isOn: Binding(
                            get: { store.isEnabled(kind) },
                            set: { newValue in
                                store.setEnabled(newValue, for: kind)
                                onToggleChanged?(kind, newValue)
                            }
                        ),
                        context: .normal
                    )
                }
            }
        }
        .textCase(nil)
        .animation(AppMotion.animation(AppMotion.emphasized, enabled: shouldAnimate), value: isExpanded)
    }

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    private var headerButton: some View {
        Button {
            if shouldAnimate {
                withAnimation(AppMotion.emphasized) {
                    isExpanded.toggle()
                }
            } else {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .foregroundStyle(iconTint)
                    Text(title)
                        .font(AppTypography.headlineEmphasis)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }

                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
