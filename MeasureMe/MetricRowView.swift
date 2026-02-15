import SwiftUI

struct MetricRowView: View {
    enum Context {
        case active(isEditing: Bool)
        case normal
    }

    let kind: MetricKind
    let isOn: Binding<Bool>
    let context: Context

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.systemImage)
                .scaleEffect(x: kind.shouldMirrorSymbol ? -1 : 1, y: 1)
                .frame(width: MetricsLayout.iconWidth)

            ViewThatFits(in: .vertical) {
                Text(kind.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(kind.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)

            if case .normal = context {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .accessibilityLabel(kind.title)
                    .frame(width: 52, alignment: .trailing)
                    .transaction { $0.animation = nil }
            }

            // .active context: no trailing toggle — use swipe to stop tracking
        }
        .offset(x: rowOffset)
        .frame(maxWidth: .infinity, minHeight: MetricsLayout.rowHeight, alignment: .leading)
        .padding(.horizontal, MetricsLayout.horizontalPadding)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
    }

    // MARK: - Helpers

    private var rowOffset: CGFloat {
        if case .normal = context {
            return 0
        }
        if case .active(let isEditing) = context {
            return isEditing ? 4 : 0
        }
        return 0
    }

}
