import SwiftUI

struct ActiveMetricsSection: View {
    @ObservedObject var store: ActiveMetricsStore
    @Binding var isEditing: Bool
    @Binding var showLimitAlert: Bool
    let scrollProxy: ScrollViewProxy
    var onStopTracking: ((_ kind: MetricKind) -> Void)?

    private var starredCount: Int {
        store.activeKinds.filter { store.isKeyMetric($0) }.count
    }

    var body: some View {
        Section {
            // MARK: - Header
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

                    Button(isEditing ? AppLocalization.string("Done") : AppLocalization.string("tracked.active.editorder")) {
                        isEditing.toggle()
                    }
                    .buttonStyle(.plain)
                }

                Text(AppLocalization.string("tracked.active.description"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AppLocalization.string("tracked.keymetrics.counter", starredCount))
                    .font(AppTypography.micro)
                    .foregroundStyle(starredCount >= 1 ? Color.appAccent : Color.secondary.opacity(0.6))
                    .padding(.top, 2)
            }
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // MARK: - Wiersze metryk z gwiazdkami
            ForEach(store.activeKinds, id: \.self) { kind in
                HStack(spacing: 0) {
                    MetricRowView(
                        kind: kind,
                        isOn: store.binding(for: kind),
                        context: .active(isEditing: isEditing)
                    )

                    if !isEditing {
                        Button {
                            let next = !store.isKeyMetric(kind)
                            let didSet = store.setKeyMetric(next, for: kind)
                            if didSet {
                                Haptics.light()
                            } else {
                                Haptics.error()
                                showLimitAlert = true
                            }
                        } label: {
                            Image(systemName: store.isKeyMetric(kind) ? "star.fill" : "star")
                                .foregroundStyle(store.isKeyMetric(kind) ? Color.appAccent : .secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(store.isKeyMetric(kind)
                            ? AppLocalization.string("accessibility.keymetric.remove")
                            : AppLocalization.string("accessibility.keymetric.add"))
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        store.setEnabled(false, for: kind)
                        Haptics.medium()
                        onStopTracking?(kind)
                    } label: {
                        Label(AppLocalization.string("tracked.active.stoptracking"), systemImage: "xmark.circle")
                    }
                }
            }
            .onMove { indices, newOffset in
                store.moveActiveKinds(fromOffsets: indices, toOffset: newOffset)
                if let moved = store.activeKinds[safe: newOffset - 1] {
                    scrollProxy.scrollTo(moved, anchor: .center)
                }
            }

            // MARK: - Separator
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .textCase(nil)
    }
}
