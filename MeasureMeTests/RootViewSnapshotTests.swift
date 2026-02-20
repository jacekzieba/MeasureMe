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
  func testRootView_snapshot() throws {
    let defaults = UserDefaults.standard
    let baselineLanguage = defaults.object(forKey: "appLanguage")
    let baselineOnboarding = defaults.object(forKey: "hasCompletedOnboarding")
    let baselinePremiumFirstLaunch = defaults.object(forKey: "premium_first_launch_date")
    let wereAnimationsEnabled = UIView.areAnimationsEnabled
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
      UIView.setAnimationsEnabled(wereAnimationsEnabled)
    }

    defaults.set("en", forKey: "appLanguage")
    defaults.set(false, forKey: "hasCompletedOnboarding")
    defaults.set(Date().timeIntervalSince1970, forKey: "premium_first_launch_date")
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
      autoCheckPaywallPrompt: false
    )
      .modelContainer(container)
      .environment(\.colorScheme, .dark) // opcjonalnie; możesz zmienić na .light

    // Hosting + stabilny rozmiar
    let vc = UIHostingController(rootView: view)
    vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    vc.view.setNeedsLayout()
    vc.view.layoutIfNeeded()

    // Porównanie ze snapshotem w __Snapshots__
    assertSnapshot(of: vc, as: .image)
  }
}
