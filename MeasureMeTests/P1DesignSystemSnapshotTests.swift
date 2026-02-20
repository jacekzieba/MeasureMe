@testable import MeasureMe

import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest

@MainActor
final class P1DesignSystemSnapshotTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_771_595_200) // 2026-02-20T12:00:00Z
    private var isRecording: Bool {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
    }

    func testQuickAddSheet_snapshot_darkDefault() throws {
        let container = try makeContainer()
        let router = AppRouter()

        let view = QuickAddSheetView(
            kinds: [.weight, .bodyFat, .leanBodyMass],
            latest: [.weight: (80.0, referenceDate)],
            unitsSystem: "metric",
            onSaved: {}
        )
        .environmentObject(router)
        .modelContainer(container)
        .environment(\.colorScheme, .dark)

        assertSnapshot(of: host(view, width: 402, height: 874), as: .image, record: isRecording)
    }

    func testMeasurementsTab_emptyState_snapshot_darkDefault() throws {
        let container = try makeContainer()
        let premiumStore = PremiumStore(startListener: false)
        let metricsStore = ActiveMetricsStore()

        // Wszystkie metryki wyłączone, żeby wymusić pusty stan.
        for kind in metricsStore.allKindsInOrder {
            metricsStore.setEnabled(false, for: kind)
        }

        let view = MeasurementsTabView()
            .environmentObject(premiumStore)
            .environmentObject(metricsStore)
            .modelContainer(container)
            .environment(\.colorScheme, .dark)

        assertSnapshot(of: host(view, width: 402, height: 874), as: .image, record: isRecording)
    }

    func testSettings_snapshot_darkDefault() throws {
        let container = try makeContainer()
        let premiumStore = PremiumStore(startListener: false)

        let view = SettingsView()
            .environmentObject(premiumStore)
            .modelContainer(container)
            .environment(\.colorScheme, .dark)

        assertSnapshot(of: host(view, width: 402, height: 874), as: .image, record: isRecording)
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: MetricGoal.self, MetricSample.self, PhotoEntry.self,
            configurations: config
        )
    }

    private func host<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> UIViewController {
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        return vc
    }
}
