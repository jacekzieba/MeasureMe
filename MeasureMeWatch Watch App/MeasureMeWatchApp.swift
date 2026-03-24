import SwiftUI

@main
struct MeasureMeWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var showQuickAdd = false

    var body: some Scene {
        WindowGroup {
            Group {
                if connectivity.isPremium {
                    NavigationStack {
                        MetricListView()
                            .navigationTitle("MeasureMe")
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button {
                                        showQuickAdd = true
                                    } label: {
                                        Image(systemName: "plus")
                                    }
                                    .tint(Color.watchAccent)
                                    .accessibilityLabel(String(localized: "Add", table: "Watch"))
                                    .accessibilityHint(watchLocalized("Opens Quick Add", "Otwiera szybkie dodawanie"))
                                }
                            }
                            .navigationDestination(isPresented: $showQuickAdd) {
                                QuickAddView()
                            }
                    }
                } else {
                    PremiumLockedView()
                }
            }
            .environmentObject(connectivity)
            .onAppear {
                #if targetEnvironment(simulator)
                DebugDataSeeder.seedIfNeeded()
                #endif
                WatchConnectivityManager.shared.activate()
            }
            .task {
                #if !targetEnvironment(simulator)
                await WatchHealthKitWriter.shared.requestAuthorizationIfNeeded()
                #endif
            }
        }
    }
}
