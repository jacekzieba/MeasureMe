import SwiftUI

struct ActiveMetricsSection: View {
    @ObservedObject var store: ActiveMetricsStore
    @Binding var isEditing: Bool
    let scrollProxy: ScrollViewProxy

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label {
                        Text(AppLocalization.string("tracked.active.header"))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .font(AppTypography.bodyEmphasis)

                    Spacer()

                    Button(isEditing ? AppLocalization.string("Done") : AppLocalization.string("Edit")) {
                        isEditing.toggle()
                    }
                    .buttonStyle(.plain)
                }

                Text(AppLocalization.string("tracked.active.description"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(store.activeKinds, id: \.self) { kind in
                MetricRowView(
                    kind: kind,
                    isOn: store.binding(for: kind),
                    context: .active(isEditing: isEditing)
                )
            }
            .onMove { indices, newOffset in
                store.moveActiveKinds(fromOffsets: indices, toOffset: newOffset)
                if let moved = store.activeKinds[safe: newOffset - 1] {
                    scrollProxy.scrollTo(moved, anchor: .center)
                }
            }
        }
        .textCase(nil)
    }
}
