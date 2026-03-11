/// Cel testu: Chroni rozdzielenie wizualne sekcji Health i Physique przed regresjami.
/// Dlaczego to wazne: Obie sekcje maja inny jezyk wizualny i nie powinny wygladac identycznie.
/// Kryteria zaliczenia: Snapshot sekcji jest stabilny i zgodny ze wzorcem referencyjnym.

@testable import MeasureMe

import XCTest
import SwiftUI
import SnapshotTesting
import SwiftData

final class MeasurementsIndicatorsSnapshotTests: XCTestCase {
    @MainActor
    func testHealthAndPhysiqueSections_snapshot_darkDefault() async throws {
        #if !targetEnvironment(simulator)
        XCTAssertTrue(true, "Physical-device fallback: snapshot baseline is simulator-only")
        return
        #endif

        let defaults = UserDefaults.standard
        let settingsStore = AppSettingsStore.shared
        let keys = [
            "appLanguage",
            "userGender",
            "manualHeight",
            "unitsSystem",
            "showWHtROnHome",
            "showRFMOnHome",
            "showBMIOnHome",
            "showBodyFatOnHome",
            "showLeanMassOnHome",
            "showWHROnHome",
            "showWaistRiskOnHome",
            "showABSIOnHome",
            "showBodyShapeScoreOnHome",
            "showCentralFatRiskOnHome",
            "showConicityOnHome",
            "health_indicators_v2_migrated",
            "showPhysiqueSWR",
            "showPhysiqueCWR",
            "showPhysiqueSHR",
            "showPhysiqueHWR",
            "showPhysiqueBWR",
            "showPhysiqueWHtR",
            "showPhysiqueBodyFat",
            "showPhysiqueRFM"
        ]
        let baselineDefaults = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            for (key, value) in baselineDefaults {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            AppLocalization.reloadLanguage()
            settingsStore.reload()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        settingsStore.set(\.experience.appLanguage, "en")
        AppLocalization.reloadLanguage()
        settingsStore.set(\.profile.userGender, "male")
        settingsStore.set(\.profile.manualHeight, 180.0)
        settingsStore.set(\.profile.unitsSystem, "metric")

        settingsStore.set(\.indicators.showWHtROnHome, true)
        settingsStore.set(\.indicators.showRFMOnHome, true)
        settingsStore.set(\.indicators.showBMIOnHome, true)
        settingsStore.set(\.indicators.showBodyFatOnHome, true)
        settingsStore.set(\.indicators.showLeanMassOnHome, true)
        settingsStore.set(\.indicators.showWHROnHome, true)
        settingsStore.set(\.indicators.showWaistRiskOnHome, true)
        settingsStore.set(\.indicators.showABSIOnHome, true)
        settingsStore.set(\.indicators.showBodyShapeScoreOnHome, true)
        settingsStore.set(\.indicators.showCentralFatRiskOnHome, true)
        settingsStore.set(\.indicators.showConicityOnHome, true)
        settingsStore.set(\.health.healthIndicatorsV2Migrated, true)
        settingsStore.set(\.indicators.showPhysiqueSWR, true)
        settingsStore.set(\.indicators.showPhysiqueCWR, true)
        settingsStore.set(\.indicators.showPhysiqueSHR, true)
        settingsStore.set(\.indicators.showPhysiqueHWR, true)
        settingsStore.set(\.indicators.showPhysiqueBWR, true)
        settingsStore.set(\.indicators.showPhysiqueWHtR, true)
        settingsStore.set(\.indicators.showPhysiqueBodyFat, true)
        settingsStore.set(\.indicators.showPhysiqueRFM, true)
        settingsStore.reload()
        UIView.setAnimationsEnabled(false)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MetricGoal.self, MetricSample.self, PhotoEntry.self,
            configurations: config
        )

        let now = Date()
        let context = ModelContext(container)
        context.insert(MetricSample(kind: .waist, value: 80.0, date: now))
        context.insert(MetricSample(kind: .height, value: 180.0, date: now))
        context.insert(MetricSample(kind: .weight, value: 77.0, date: now))
        context.insert(MetricSample(kind: .hips, value: 98.0, date: now))
        context.insert(MetricSample(kind: .bodyFat, value: 16.0, date: now))
        context.insert(MetricSample(kind: .leanBodyMass, value: 63.0, date: now))
        context.insert(MetricSample(kind: .shoulders, value: 124.0, date: now))
        context.insert(MetricSample(kind: .chest, value: 104.0, date: now))
        context.insert(MetricSample(kind: .bust, value: 96.0, date: now))
        try context.save()

        let premiumStore = PremiumStore(startListener: false)
        premiumStore.isPremium = true
        let router = AppRouter()

        let view = NavigationStack {
            VStack(spacing: 12) {
                HealthMetricsSection(
                    latestWaist: 80.0,
                    latestHeight: 180.0,
                    latestWeight: 77.0,
                    latestHips: 98.0,
                    latestBodyFat: 16.0,
                    latestLeanMass: 63.0,
                    displayMode: .indicatorsOnly,
                    title: "",
                    runSideEffects: false
                )

                PhysiqueIndicatorsSection(
                    latestWaist: 80.0,
                    latestHeight: 180.0,
                    latestWeight: 77.0,
                    latestBodyFat: 16.0,
                    latestShoulders: 124.0,
                    latestChest: 104.0,
                    latestBust: 96.0,
                    latestHips: 98.0
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .toolbar(.hidden, for: .navigationBar)
        }
        .modelContainer(container)
        .environmentObject(premiumStore)
        .environmentObject(router)
        .preferredColorScheme(.dark)

        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 1200)
        let window = UIWindow(frame: vc.view.frame)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }
}
