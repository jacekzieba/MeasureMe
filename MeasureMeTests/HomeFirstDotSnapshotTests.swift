/// Goal: visual proof for Dashboard B — the "first dot" hero shown right after the first measurement.

@testable import MeasureMe

import XCTest
import SwiftUI
import SnapshotTesting

@MainActor
final class HomeFirstDotSnapshotTests: XCTestCase {

    func testSameDayPhotosDoNotClaimZeroDayComparison() {
        let text = HomePhotoComparisonCopy.insightText(days: 0)

        XCTAssertFalse(text.contains("0"))
        XCTAssertTrue(HomePhotoComparisonCopy.insightText(days: 12).contains("12"))
    }

    private func requireSimulatorSnapshotEnvironment() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil else {
            throw XCTSkip("Snapshot baseline is simulator-only")
        }
    }

    private func makeHostingController(colorScheme: ColorScheme) -> UIHostingController<some View> {
        let view = ZStack {
            AppColorRoles.surfaceCanvas.ignoresSafeArea()
            HomeTopSummarySection(
                dateText: "WED, JUN 10",
                greetingTitle: "Week 1 — you're on the board.",
                avatarText: "A",
                profilePhotoData: nil,
                isPremium: true,
                insights: [],
                analysisItems: [],
                showStreak: false,
                streakCount: 0,
                shouldAnimateStreak: false,
                firstDot: HomeFirstDotSnapshot(
                    metricLabel: "Weight · starting point",
                    valueText: "75.0 kg",
                    comeBackText: "Your second entry reveals your first trend — come back for your next check-in."
                ),
                onUnlockPremium: {},
                onOpenStreak: {},
                onStreakAnimationComplete: {},
                onOpenProfile: {},
                onOpenPhotos: {}
            )
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 390, height: 520)
        .preferredColorScheme(colorScheme)

        let vc = UIHostingController(rootView: view)
        vc.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 520)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        return vc
    }

    func testHomeFirstDotHero() async throws {
        try requireSimulatorSnapshotEnvironment()

        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer { UIView.setAnimationsEnabled(wereAnimationsEnabled) }
        UIView.setAnimationsEnabled(false)

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        for scheme in [ColorScheme.light, .dark] {
            let schemeName = scheme == .dark ? "dark" : "light"
            let vc = makeHostingController(colorScheme: scheme)
            let window = UIWindow(frame: vc.view.frame)
            window.rootViewController = vc
            window.makeKeyAndVisible()
            vc.view.setNeedsLayout()
            vc.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(140))
            assertSnapshot(
                of: vc,
                as: .image(precision: 0.99, perceptualPrecision: 0.98),
                named: schemeName,
                record: shouldRecord
            )
        }
    }
}
