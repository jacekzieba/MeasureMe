@testable import MeasureMe

import XCTest
import SwiftUI
import SnapshotTesting
import SwiftData

final class RootViewSnapshotTests: XCTestCase {

  func testRootView_snapshot() throws {
    // SwiftData: in-memory container, żeby @Query miało modelContext
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: MetricGoal.self, MetricSample.self, PhotoEntry.self,
      configurations: config
    )

    // Widok + wstrzyknięcie kontenera
    let view = RootView()
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
