import XCTest
import SwiftUI
import SwiftData
@testable import MeasureMe

@MainActor
final class HomeStartupOptimizationTests: XCTestCase {
    func testDeltaText_UsesNewestMinusOldestFromWindow() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MetricSample.self,
            MetricGoal.self,
            PhotoEntry.self,
            configurations: config
        )
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let older = MetricSample(kind: .weight, value: 81, date: now.addingTimeInterval(-6 * 86_400))
        let newer = MetricSample(kind: .weight, value: 79.5, date: now.addingTimeInterval(-2 * 86_400))
        context.insert(newer)
        context.insert(older)
        try context.save()

        let text = HomeView.deltaText(
            samples: [newer, older],
            kind: .weight,
            unitsSystem: "metric",
            days: 7,
            now: now
        )

        XCTAssertEqual(text, "-1.5 kg")
    }

    func testDeltaText_ReturnsNilForSingleSample() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let one = MetricSample(kind: .waist, value: 88, date: now.addingTimeInterval(-1 * 86_400))
        let text = HomeView.deltaText(
            samples: [one],
            kind: .waist,
            unitsSystem: "metric",
            days: 7,
            now: now
        )
        XCTAssertNil(text)
    }

    func testIsAfterPhotoSyncCursor_UsesDateAndIDTieBreak() {
        let cursorDate = Date(timeIntervalSince1970: 1_770_000_000).timeIntervalSince1970
        XCTAssertTrue(
            HomeView.isAfterPhotoSyncCursor(
                photoDate: Date(timeIntervalSince1970: cursorDate + 60),
                photoID: "a",
                cursorDate: cursorDate,
                cursorID: "z"
            )
        )
        XCTAssertFalse(
            HomeView.isAfterPhotoSyncCursor(
                photoDate: Date(timeIntervalSince1970: cursorDate - 60),
                photoID: "z",
                cursorDate: cursorDate,
                cursorID: "a"
            )
        )
        XCTAssertTrue(
            HomeView.isAfterPhotoSyncCursor(
                photoDate: Date(timeIntervalSince1970: cursorDate),
                photoID: "photo_020",
                cursorDate: cursorDate,
                cursorID: "photo_010"
            )
        )
        XCTAssertFalse(
            HomeView.isAfterPhotoSyncCursor(
                photoDate: Date(timeIntervalSince1970: cursorDate),
                photoID: "photo_009",
                cursorDate: cursorDate,
                cursorID: "photo_010"
            )
        )
    }

    func testNewestPhotoSyncCursor_PicksLatestCandidate() {
        let base = Date(timeIntervalSince1970: 1_770_000_000)
        let cursor = HomeView.newestPhotoSyncCursor(candidates: [
            (date: base.addingTimeInterval(-20), id: "photo_001"),
            (date: base, id: "photo_010"),
            (date: base, id: "photo_020")
        ])

        XCTAssertEqual(cursor?.date, base.timeIntervalSince1970)
        XCTAssertEqual(cursor?.id, "photo_020")
    }

    func testHealthMetricsSectionSummaryRendersWithoutModelContainer() {
        let defaults = UserDefaults.standard
        let baselinePremiumEntitlement = defaults.object(forKey: "premium_entitlement")
        defer {
            if let baselinePremiumEntitlement {
                defaults.set(baselinePremiumEntitlement, forKey: "premium_entitlement")
            } else {
                defaults.removeObject(forKey: "premium_entitlement")
            }
        }
        defaults.set(true, forKey: "premium_entitlement")

        let premiumStore = PremiumStore(startListener: false)
        premiumStore.isPremium = true

        let view = HealthMetricsSection(
            latestWaist: 84,
            latestHeight: 180,
            latestWeight: 79,
            latestHips: 99,
            latestBodyFat: 16,
            latestLeanMass: 64,
            weightDelta7dText: "-0.7 kg",
            waistDelta7dText: "-0.5 cm",
            displayMode: .summaryOnly,
            title: "Health"
        )
        .environmentObject(premiumStore)

        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 260)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()

        XCTAssertNotNil(vc.view)
    }
}
