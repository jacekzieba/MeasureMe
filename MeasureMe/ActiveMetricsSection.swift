import SwiftUI

struct ActiveMetricsSection: View {
    @ObservedObject var store: ActiveMetricsStore
    @Binding var isEditing: Bool
    @Binding var selectedKind: MetricKind?
    let scrollProxy: ScrollViewProxy


    var body: some View {
        Section {
            HStack {
                Label(AppLocalization.string("Active"), systemImage: "checkmark.circle.fill")
                Spacer()
                Button(isEditing ? AppLocalization.string("Done") : AppLocalization.string("Edit")) {
                    isEditing.toggle()
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

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
        }
        .textCase(nil)
    }
}
