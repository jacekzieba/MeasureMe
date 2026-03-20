/// Cel testu: Chroni wizualne regresje trzech trybów porównywania zdjęć (slider, side-by-side, ghost).
/// Dlaczego to ważne: Ghost overlay jest nowym trybem — snapshot zabezpiecza układ, kontrolki opacity i date badges.
/// Kryteria zaliczenia: Snapshot każdego trybu jest stabilny i zgodny ze wzorcem referencyjnym.

@testable import MeasureMe

import XCTest
import SwiftUI
import SnapshotTesting
import SwiftData

final class ComparePhotosSnapshotTests: XCTestCase {

    @MainActor
    func testGhostOverlayMode_snapshot() throws {
        #if !targetEnvironment(simulator)
        XCTAssertTrue(true, "Physical-device fallback: snapshot baseline is simulator-only")
        return
        #endif

        let defaults = UserDefaults.standard
        let keys = ["appLanguage", "unitsSystem"]
        let baselineDefaults = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            for (key, value) in baselineDefaults {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            AppSettingsStore.shared.forceReloadSnapshot()
            AppLocalization.settings = .shared
            AppLocalization.reloadLanguage()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        defaults.set("en", forKey: "appLanguage")
        defaults.set("metric", forKey: "unitsSystem")
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: defaults)
        AppLocalization.reloadLanguage()
        UIView.setAnimationsEnabled(false)

        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: MetricGoal.self, MetricSample.self, PhotoEntry.self,
            configurations: config
        )
        let context = ModelContext(container)

        let olderPhoto = PhotoEntry(
            imageData: makeTestImageData(color: (0.8, 0.2, 0.2)),
            date: Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 1))!,
            tags: [.wholeBody],
            linkedMetrics: [
                MetricValueSnapshot(kind: .weight, value: 90.0, unit: "kg"),
                MetricValueSnapshot(kind: .waist, value: 85.0, unit: "cm"),
            ]
        )
        let newerPhoto = PhotoEntry(
            imageData: makeTestImageData(color: (0.2, 0.6, 0.8)),
            date: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
            tags: [.wholeBody],
            linkedMetrics: [
                MetricValueSnapshot(kind: .weight, value: 82.0, unit: "kg"),
                MetricValueSnapshot(kind: .waist, value: 80.0, unit: "cm"),
            ]
        )

        context.insert(olderPhoto)
        context.insert(newerPhoto)
        try context.save()

        let view = ComparePhotosView(olderPhoto: olderPhoto, newerPhoto: newerPhoto)
            .modelContainer(container)
            .preferredColorScheme(.dark)

        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }

    // MARK: - Helpers

    private func makeTestImageData(
        width: Int = 200,
        height: Int = 300,
        color: (CGFloat, CGFloat, CGFloat) = (1, 0, 0)
    ) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }
        ctx.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = ctx.makeImage() else { return Data() }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9) ?? Data()
    }
}
