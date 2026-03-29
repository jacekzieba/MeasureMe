import SwiftUI
import UniformTypeIdentifiers

struct SettingsImportFlowModifier: ViewModifier {
    @Binding var showImportPicker: Bool
    @Binding var showImportStrategyAlert: Bool
    @Binding var pendingImportURLs: [URL]
    @Binding var activeAlert: SettingsAlert?

    let onImport: ([URL], SettingsImporter.Strategy) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [UTType.commaSeparatedText],
                allowsMultipleSelection: true,
                onCompletion: handleImportPickerResult
            )
            .confirmationDialog(
                AppLocalization.string("Import data"),
                isPresented: $showImportStrategyAlert,
                titleVisibility: .visible
            ) {
                Button(AppLocalization.string("Merge (keep existing data)")) {
                    onImport(pendingImportURLs, .merge)
                }
                Button(AppLocalization.string("Replace (delete existing data)"), role: .destructive) {
                    onImport(pendingImportURLs, .replace)
                }
                Button(AppLocalization.string("Cancel"), role: .cancel) {
                    pendingImportURLs = []
                }
            } message: {
                Text(AppLocalization.string("How should MeasureMe handle existing data?"))
            }
    }

    private func handleImportPickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            pendingImportURLs = urls
            showImportStrategyAlert = true
        case .failure(let error):
            activeAlert = .importResult(
                AppLocalization.string("Could not open file: %@", error.localizedDescription)
            )
        }
    }
}
