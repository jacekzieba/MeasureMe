import SwiftUI

@main
struct MeasureMeWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if connectivity.isPremium {
                    TabView {
                        MetricListView()
                            .tag(0)

                        QuickAddView()
                            .tag(1)
                    }
                    .tabViewStyle(.verticalPage)
                } else {
                    PremiumLockedView()
                }
            }
            .environmentObject(connectivity)
        }
    }

    init() {
        WatchConnectivityManager.shared.activate()

        Task {
            await WatchHealthKitWriter.shared.requestAuthorizationIfNeeded()
        }
    }
}
