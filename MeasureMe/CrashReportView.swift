import SwiftUI
import MessageUI

/// Widok do przeglądania i wysyłania raportów crash.
/// Dostępny w Settings → Data → Crash Reports.
struct CrashReportView: View {
    @State private var reports: [CrashReport] = []
    @State private var selectedReport: CrashReport?
    @State private var showShareSheet = false
    @State private var diagnosticReport: String?

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))

            List {
                if reports.isEmpty {
                    Section {
                        AppGlassCard(depth: .base, tint: Color.white.opacity(0.06)) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(AppLocalization.string("No crash reports"), systemImage: "checkmark.shield.fill")
                                    .font(AppTypography.bodyEmphasis)
                                    .foregroundStyle(.green)
                                Text(AppLocalization.string("Everything looks good. No crashes have been recorded."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listSectionSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(reports) { report in
                            Button {
                                selectedReport = report
                            } label: {
                                AppGlassCard(depth: .base, tint: Color.red.opacity(0.08)) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.red)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(report.filename)
                                                .font(AppTypography.bodyEmphasis)
                                                .lineLimit(1)
                                            Text(report.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(AppTypography.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listSectionSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                }

                // Sekcja raportu diagnostycznego
                Section {
                    Button {
                        Haptics.light()
                        diagnosticReport = CrashReporter.shared.generateDiagnosticReport()
                        showShareSheet = true
                    } label: {
                        AppGlassCard(depth: .base, tint: Color.cyan.opacity(0.10)) {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.title3)
                                    .foregroundStyle(Color.appAccent)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(AppLocalization.string("Send diagnostic report"))
                                        .font(AppTypography.bodyEmphasis)
                                    Text(AppLocalization.string("Share recent logs to help debug issues."))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(16)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }
        .navigationTitle(AppLocalization.string("Crash Reports"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            reports = CrashReporter.shared.listReports()
        }
        .sheet(item: $selectedReport) { report in
            CrashReportDetailView(report: report) {
                reports = CrashReporter.shared.listReports()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let text = diagnosticReport {
                CrashShareSheet(items: [text])
            }
        }
    }
}

// MARK: - Detail View

private struct CrashReportDetailView: View {
    let report: CrashReport
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppScreenBackground(topHeight: 200, tint: Color.cyan.opacity(0.16))

                ScrollView {
                    VStack(spacing: 16) {
                        // Actions
                        HStack(spacing: 12) {
                            Button {
                                Haptics.light()
                                showShareSheet = true
                            } label: {
                                Label(AppLocalization.string("Share"), systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(LiquidCapsuleButtonStyle())

                            Button {
                                showDeleteConfirmation = true
                            } label: {
                                Label(AppLocalization.string("Delete"), systemImage: "trash")
                            }
                            .buttonStyle(LiquidCapsuleButtonStyle(tint: .red))
                        }

                        // Report content
                        AppGlassCard(depth: .base, tint: Color.white.opacity(0.04)) {
                            Text(report.content)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.85))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(report.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Close")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                CrashShareSheet(items: [report.content])
            }
            .alert(AppLocalization.string("Delete Report?"), isPresented: $showDeleteConfirmation) {
                Button(AppLocalization.string("Delete"), role: .destructive) {
                    CrashReporter.shared.deleteReport(report)
                    onDelete()
                    dismiss()
                }
                Button(AppLocalization.string("Cancel"), role: .cancel) { }
            }
        }
    }
}

// MARK: - Share Sheet

private struct CrashShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
