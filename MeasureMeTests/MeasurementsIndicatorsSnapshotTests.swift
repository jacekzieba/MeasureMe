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
            AppSettingsStore.shared.forceReloadSnapshot()
            AppLocalization.settings = .shared
            AppLocalization.reloadLanguage()
            settingsStore.reload()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        defaults.set("en", forKey: "appLanguage")
        defaults.set("male", forKey: "userGender")
        defaults.set(180.0, forKey: "manualHeight")
        defaults.set("metric", forKey: "unitsSystem")

        let visibilityKeys = keys.filter { $0.hasPrefix("show") }
        for key in visibilityKeys {
            defaults.set(true, forKey: key)
        }
        defaults.set(true, forKey: "health_indicators_v2_migrated")

        // Force-sync AppSettingsStore.shared snapshot so @AppSetting wrappers reflect test values
        // immediately, without waiting for the normal async 10 ms debounce refresh.
        AppSettingsStore.shared.forceReloadSnapshot()

        // Same sync-load fix for AppLocalization so language is English during render.
        AppLocalization.settings = AppSettingsStore(defaults: defaults)
        AppLocalization.reloadLanguage()

        UIView.setAnimationsEnabled(false)

        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
