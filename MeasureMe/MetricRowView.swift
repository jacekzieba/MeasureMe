import SwiftUI

struct MetricRowView: View {
    enum Context {
        case active(isEditing: Bool, onTap: () -> Void)
        case normal(onDetailsTap: () -> Void)
    }

    let kind: MetricKind
    let isOn: Binding<Bool>
    let context: Context

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.systemImage)
                .scaleEffect(x: kind.shouldMirrorSymbol ? -1 : 1, y: 1)
                .frame(width: MetricsLayout.iconWidth)

            Text(kind.title)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)

            if case .normal = context {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .frame(width: 52, alignment: .trailing)
            }

            if case .active(let isEditing, _) = context, !isEditing {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .frame(width: 52, alignment: .trailing)
            }

            if case .normal(let onDetailsTap) = context {
                Button(action: onDetailsTap) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
        // ⬇️⬇️⬇️ TU DODAJEMY (DO CAŁEGO ROW)
        .offset(x: rowOffset)
        // ⬆️⬆️⬆️ KONIEC DODATKÓW
        .frame(maxWidth: .infinity, minHeight: MetricsLayout.rowHeight, alignment: .leading)
        .padding(.horizontal, MetricsLayout.horizontalPadding)
        .contentShape(Rectangle())
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(separator, alignment: .bottom)
        .onTapGesture {
            if case .active(_, let onTap) = context {
                onTap()
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(.init())
    }

    // MARK: - Helpers

    private var isEditingValue: Bool {
        if case .active(let isEditing, _) = context {
            return isEditing
        }
        return false
    }

    private var rowOffset: CGFloat {
        // W normal context nie offsetuj
        if case .normal = context {
            return 0
        }
        // W active context offsetuj tylko gdy editing
        if case .active(let isEditing, _) = context {
            return isEditing ? 4 : 0
        }
        return 0
    }

    private var separator: some View {
        Divider()
            .padding(.leading, MetricsLayout.separatorInset)
    }
}
