import SwiftUI

struct SettingsDataSection: View {
    let onExport: () -> Void
    let onImport: () -> Void
    let onSeedDummyData: () -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Data"), systemImage: "square.and.arrow.up")
                NavigationLink {
                    DataSettingsDetailView(
                        onExport: onExport,
                        onImport: onImport,
                        onSeedDummyData: onSeedDummyData,
                        onDeleteAll: onDeleteAll
                    )
                } label: {
                    Text(AppLocalization.string("Open data settings"))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
