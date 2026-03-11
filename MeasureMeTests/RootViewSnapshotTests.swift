/// Cel testow: Chroni UI przed regresjami wizualnymi poprzez snapshoty RootView.
/// Dlaczego to wazne: Zmiany UI latwo przeoczyc bez automatycznego porownania.
/// Kryteria zaliczenia: Render widoku zgadza sie ze wzorcem snapshot w kontrolowanych warunkach.

@testable import MeasureMe

import XCTest
import SwiftUI
import SnapshotTesting
import SwiftData

final class RootViewSnapshotTests: XCTestCase {

  @MainActor
  /// Co sprawdza: Sprawdza scenariusz: RootView_snapshot.
  /// Dlaczego: Zapobiega regresjom UI/UX, ktore latwo przeoczyc recznie.
  /// Kryteria: Test konczy sie bez bledu i bez efektow ubocznych niezgodnych z oczekiwaniem.
  func testRootView_snapshot() async throws {
    #if !targetEnvironment(simulator)
    XCTAssertTrue(true, "Physical-device fallback: snapshot baseline is simulator-only")
    return
    #endif

    let defaults = UserDefaults.standard
    let settingsStore = AppSettingsStore.shared
    let baselineLanguage = defaults.object(forKey: "appLanguage")
    let baselineOnboarding = defaults.object(forKey: "hasCompletedOnboarding")
    let baselinePremiumFirstLaunch = defaults.object(forKey: "premium_first_launch_date")
    let baselineUserName = defaults.object(forKey: "userName")
    let baselineUserAge = defaults.object(forKey: "userAge")
    let baselineUserGender = defaults.object(forKey: "userGender")
    let baselineManualHeight = defaults.object(forKey: "manualHeight")
    let baselineUnitsSystem = defaults.object(forKey: "unitsSystem")
    let baselineNowOverride = AppClock.overrideNowForTesting
    let wereAnimationsEnabled = UIView.areAnimationsEnabled
    let fixedNow = Date(timeIntervalSince1970: 1_770_000_000)
    defer {
      if let baselineLanguage {
        defaults.set(baselineLanguage, forKey: "appLanguage")
      } else {
        defaults.removeObject(forKey: "appLanguage")
      }
      if let baselineOnboarding {
        defaults.set(baselineOnboarding, forKey: "hasCompletedOnboarding")
      } else {
        defaults.removeObject(forKey: "hasCompletedOnboarding")
      }
      if let baselinePremiumFirstLaunch {
        defaults.set(baselinePremiumFirstLaunch, forKey: "premium_first_launch_date")
      } else {
        defaults.removeObject(forKey: "premium_first_launch_date")
      }
      if let baselineUserName {
        defaults.set(baselineUserName, forKey: "userName")
      } else {
        defaults.removeObject(forKey: "userName")
      }
      if let baselineUserAge {
        defaults.set(baselineUserAge, forKey: "userAge")
      } else {
        defaults.removeObject(forKey: "userAge")
      }
      if let baselineUserGender {
        defaults.set(baselineUserGender, forKey: "userGender")
      } else {
        defaults.removeObject(forKey: "userGender")
      }
      if let baselineManualHeight {
        defaults.set(baselineManualHeight, forKey: "manualHeight")
      } else {
        defaults.removeObject(forKey: "manualHeight")
      }
      if let baselineUnitsSystem {
        defaults.set(baselineUnitsSystem, forKey: "unitsSystem")
      } else {
        defaults.removeObject(forKey: "unitsSystem")
      }
      AppClock.overrideNowForTesting = baselineNowOverride
      AppLocalization.reloadLanguage()
      settingsStore.reload()
      UIView.setAnimationsEnabled(wereAnimationsEnabled)
    }

    AppClock.overrideNowForTesting = fixedNow
    settingsStore.set(\.experience.appLanguage, "en")
    AppLocalization.reloadLanguage()
    settingsStore.set(\.onboarding.hasCompletedOnboarding, false)
    settingsStore.set(\.premium.premiumFirstLaunchDate, fixedNow.timeIntervalSince1970)
    settingsStore.set(\.profile.userName, "Jacek")
    settingsStore.set(\.profile.userAge, 32)
    settingsStore.set(\.profile.userGender, "male")
    settingsStore.set(\.profile.manualHeight, 180.0)
    settingsStore.set(\.profile.unitsSystem, "metric")
    UIView.setAnimationsEnabled(false)

    // SwiftData: in-memory container, żeby @Query miało modelContext
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: MetricGoal.self, MetricSample.self, PhotoEntry.self,
      configurations: config
    )

    let premiumStore = PremiumStore(startListener: false)

    // Widok + wstrzyknięcie kontenera
    let view = RootView(
      premiumStore: premiumStore,
      autoCheckPaywallPrompt: false,
      runDeferredStartupWork: false
    )
      .modelContainer(container)
      .environment(\.colorScheme, .dark) // opcjonalnie; możesz zmienić na .light

    // Hosting + stabilny rozmiar
    let vc = UIHostingController(rootView: view)
    vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)

    // Okno wymagane, żeby SwiftUI poprawnie propagowało środowisko (modelContext, @StateObject)
    // i żeby onAppear/Task miały dostęp do prawidłowego kontekstu.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = vc
    window.makeKeyAndVisible()

    vc.view.setNeedsLayout()
    vc.view.layoutIfNeeded()

    // Pozwól onAppear Task uruchomić się i zakończyć zanim zrobimy snapshot.
    try await Task.sleep(for: .milliseconds(100))

    // Porównanie ze snapshotem w __Snapshots__.
    let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
    assertSnapshot(
      of: vc,
      as: .recursiveDescription,
      record: shouldRecord
    )
  }
}
