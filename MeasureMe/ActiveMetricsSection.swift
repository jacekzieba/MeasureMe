import SwiftUI

struct ActiveMetricsSection: View {
    @ObservedObject var store: ActiveMetricsStore
    @Binding var isEditing: Bool
    @Binding var selectedKind: MetricKind?
    let scrollProxy: ScrollViewProxy


    var body: some View {
        Section {
            ForEach(store.activeKinds, id: \.self) { kind in
                MetricRowView(
                    kind: kind,
                    isOn: store.binding(for: kind),
                    context: .active(
                        isEditing: isEditing,
                        onTap: {
                            guard !isEditing else { return }
                            selectedKind = kind
                        }
                    )
                )
            }
            
            .onMove { indices, newOffset in
                store.moveActiveKinds(fromOffsets: indices, toOffset: newOffset)
                if let moved = store.activeKinds[safe: newOffset - 1] {
                    scrollProxy.scrollTo(moved, anchor: .center)
                }
            }

        } header: {
            HStack {
                Label(AppLocalization.string("Active"), systemImage: "checkmark.circle.fill")
                Spacer()
                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                }
                .buttonStyle(.plain)
            }
        }
    }
}
