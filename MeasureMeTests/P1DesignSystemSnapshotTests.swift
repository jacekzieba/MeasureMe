@testable import MeasureMe

import SnapshotTesting
import SwiftData
import SwiftUI
import UIKit
import XCTest

@MainActor
final class P1DesignSystemSnapshotTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_771_595_200) // 2026-02-20T12:00:00Z
    private let snapshotSize = CGSize(width: 402, height: 874)
    private var isRecording: Bool {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
    }

    override func setUp() {
        super.setUp()
        prepareDefaultsForSnapshot()
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

        assertSnapshot(of: host(view, size: snapshotSize), as: .image, record: isRecording)
    }

    func testQuickAddSheet_snapshot_darkAXL() throws {
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
        .environment(\.dynamicTypeSize, .accessibility3)

        assertSnapshot(of: host(view, size: snapshotSize), as: .image, record: isRecording)
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

        assertSnapshot(of: host(view, size: snapshotSize), as: .image, record: isRecording)
    }

    func testMeasurementsTab_emptyState_snapshot_darkAXL() throws {
        let container = try makeContainer()
        let premiumStore = PremiumStore(startListener: false)
        let metricsStore = ActiveMetricsStore()

        for kind in metricsStore.allKindsInOrder {
            metricsStore.setEnabled(false, for: kind)
        }

        let view = MeasurementsTabView()
            .environmentObject(premiumStore)
            .environmentObject(metricsStore)
            .modelContainer(container)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, .accessibility3)

        assertSnapshot(of: host(view, size: snapshotSize), as: .image, record: isRecording)
    }

    func testSettings_snapshot_darkDefault() throws {
        let container = try makeContainer()
        let premiumStore = PremiumStore(startListener: false)

        let view = SettingsView()
            .environmentObject(premiumStore)
            .modelContainer(container)
            .environment(\.colorScheme, .dark)

        assertSnapshot(of: host(view, size: snapshotSize), as: .image, record: isRecording)
    }

    func testHome_snapshot_darkDefault() throws {
        let container = try makeContainer()
        try seedSamplesAndPhotos(in: container)
        let premiumStore = PremiumStore(startListener: false)
        let metricsStore = ActiveMetricsStore()
        let router = AppRouter()

        let view = HomeView(autoCheckPaywallPrompt: false)
            .environmentObject(premiumStore)
            .environmentObject(metricsStore)
            .environmentObject(router)
            .modelContainer(container)
            .environment(\.colorScheme, .dark)

        assertSnapshot(of: host(view, size: snapshotSize, wait: 0.25), as: .image, record: isRecording)
    }

    func testMetricDetail_snapshot_darkDefault() throws {
        throw XCTSkip("MetricDetail snapshot is unstable on iOS 26.x test runtime; covered by AuditCaptureUITests screenshot flow.")
    }

    func testPhotoView_snapshot_darkDefault() throws {
        let container = try makeContainer()
        try seedSamplesAndPhotos(in: container)
        let premiumStore = PremiumStore(startListener: false)
        let metricsStore = ActiveMetricsStore()

        let view = PhotoView()
            .environmentObject(premiumStore)
            .environmentObject(metricsStore)
            .modelContainer(container)
            .environment(\.colorScheme, .dark)

        assertSnapshot(of: host(view, size: snapshotSize, wait: 0.45), as: .image, record: isRecording)
    }

    func testOnboardingPremium_snapshot_darkAXL() throws {
        let premiumStore = PremiumStore(startListener: false)
        let view = OnboardingView(initialStepIndex: 3)
            .environmentObject(premiumStore)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, .accessibility3)

        assertSnapshot(of: host(view, size: snapshotSize, wait: 0.2), as: .image, record: isRecording)
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: MetricGoal.self, MetricSample.self, PhotoEntry.self,
            configurations: config
        )
    }

    private func prepareDefaultsForSnapshot() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set("en", forKey: "appLanguage")
        defaults.set(false, forKey: "onboarding_checklist_show")
        defaults.set("Tester", forKey: "userName")
        defaults.set("metric", forKey: "unitsSystem")
        defaults.set(true, forKey: "metric_weight_enabled")
        defaults.set(true, forKey: "metric_bodyFat_enabled")
        defaults.set(true, forKey: "metric_nonFatMass_enabled")
        defaults.set(true, forKey: "metric_waist_enabled")
    }

    private func seedSamplesAndPhotos(in container: ModelContainer) throws {
        let context = ModelContext(container)
        let older = Calendar.current.date(byAdding: .day, value: -30, to: referenceDate) ?? referenceDate
        context.insert(MetricSample(kind: .weight, value: 82.0, date: older))
        context.insert(MetricSample(kind: .weight, value: 80.0, date: referenceDate))
        context.insert(MetricSample(kind: .waist, value: 89.0, date: referenceDate))
        context.insert(MetricGoal(kind: .weight, targetValue: 79.0, createdDate: referenceDate))

        for index in 0..<6 {
            let date = Calendar.current.date(byAdding: .day, value: -index, to: referenceDate) ?? referenceDate
            guard let imageData = makeSnapshotImageData(index: index) else { continue }
            context.insert(PhotoEntry(imageData: imageData, date: date, tags: [.wholeBody], linkedMetrics: []))
        }
        try context.save()
    }

    private func makeSnapshotImageData(index: Int) -> Data? {
        let size = CGSize(width: 512, height: 704)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(hue: CGFloat(index) / 8.0, saturation: 0.45, brightness: 0.95, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.35).setFill()
            UIBezierPath(roundedRect: CGRect(x: 24, y: 24, width: size.width - 48, height: size.height - 48), cornerRadius: 34).fill()
        }
        return image.jpegData(compressionQuality: 0.8)
    }

    private func host<V: View>(_ view: V, size: CGSize, wait: TimeInterval = 0) -> UIViewController {
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(origin: .zero, size: size)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        if wait > 0 {
            RunLoop.main.run(until: Date().addingTimeInterval(wait))
        }
        return vc
    }
}
