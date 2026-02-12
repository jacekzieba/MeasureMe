import SwiftUI

struct MetricsSection: View {
    let title: String
    let systemImage: String
    let rows: [MetricKind]
    @ObservedObject var store: ActiveMetricsStore
    @Binding var selectedKind: MetricKind?

    @State private var isExpanded = true
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            if isExpanded {
                ForEach(rows.filter { !store.activeKinds.contains($0) }, id: \.self) { kind in
                    MetricRowView(
                        kind: kind,
                        isOn: store.binding(for: kind),
                        context: .normal(onDetailsTap: {
                            selectedKind = kind
                        })
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        } header: {
            Button {
                if shouldAnimate {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        isExpanded.toggle()
                    }
                } else {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .animation(shouldAnimate ? .spring(response: 0.34, dampingFraction: 0.88) : nil, value: isExpanded)
    }

    private var shouldAnimate: Bool {
        animationsEnabled && !reduceMotion
    }
}
