import SwiftUI

struct MetricsSection: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let iconTint: Color
    let rows: [MetricKind]
    @ObservedObject var store: ActiveMetricsStore

    @State private var isExpanded = true
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var inactiveRows: [MetricKind] {
        rows.filter { !store.activeKinds.contains($0) }
    }

    var body: some View {
        Section {
            headerButton

            if isExpanded {
                ForEach(inactiveRows, id: \.self) { kind in
                    MetricRowView(
                        kind: kind,
                        isOn: store.binding(for: kind),
                        context: .normal
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if inactiveRows.isEmpty {
                    Text(AppLocalization.string("tracked.section.allempty"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.tertiary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .textCase(nil)
        .animation(shouldAnimate ? .spring(response: 0.34, dampingFraction: 0.88) : nil, value: isExpanded)
    }

    private var shouldAnimate: Bool {
        animationsEnabled && !reduceMotion
    }

    private var headerButton: some View {
        Button {
            if shouldAnimate {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
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
