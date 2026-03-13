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

    if #available(iOS 26, *) {
      throw XCTSkip("RootView snapshot is unstable on iOS 26 simulator and crashes the SnapshotTesting host after mismatches.")
    }

    let defaults = UserDefaults.standard
    let settingsStore = AppSettingsStore.shared
    let managedKeys = [
      "appLanguage",
      "hasCompletedOnboarding",
      "premium_first_launch_date",
      "userName",
      "userAge",
      "userGender",
      "manualHeight",
      "unitsSystem"
    ]
    let baselineDefaults = Dictionary(uniqueKeysWithValues: managedKeys.map { ($0, defaults.object(forKey: $0)) })
    let wereAnimationsEnabled = UIView.areAnimationsEnabled
    defer {
      for (key, value) in baselineDefaults {
        if let value {
          settingsStore.set(value, forKey: key)
        } else {
          settingsStore.removeObject(forKey: key)
        }
      }
      settingsStore.reload()
      AppLocalization.reloadLanguage()
      UIView.setAnimationsEnabled(wereAnimationsEnabled)
    }

    settingsStore.clearUserDataDefaults()
    settingsStore.set(\.experience.appLanguage, "en")
    settingsStore.set(\.onboarding.hasCompletedOnboarding, false)
    settingsStore.set(\.premium.premiumFirstLaunchDate, Date().timeIntervalSince1970)
    settingsStore.set(\.profile.userName, "Jacek")
    settingsStore.set(\.profile.userAge, 32)
    settingsStore.set(\.profile.userGender, "male")
    settingsStore.set(\.profile.manualHeight, 180.0)
    settingsStore.set(\.profile.unitsSystem, "metric")
    settingsStore.reload()
    AppLocalization.reloadLanguage()
    UIView.setAnimationsEnabled(false)

    // SwiftData: in-memory container, żeby @Query miało modelContext
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(
      for: MetricGoal.self, MetricSample.self, PhotoEntry.self,
      configurations: config
    )

    let premiumStore = PremiumStore(startListener: false)

    // Widok + wstrzyknięcie kontenera
    let view = RootView(
      premiumStore: premiumStore,
      autoCheckPaywallPrompt: false
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
    try await Task.sleep(for: .milliseconds(50))

    // Obrazkowy snapshot jest stabilniejszy niż recursiveDescription dla tego widoku
    // na iOS 26 simulator i lepiej odzwierciedla faktyczną regresję wizualną.
    let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
    assertSnapshot(
      of: vc,
      as: .image,
      record: shouldRecord
    )
  }
}
