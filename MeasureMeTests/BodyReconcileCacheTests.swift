import XCTest
@testable import MeasureMe

/// Cel testow: memoizacja uzgadniania objetosci.
/// Dlaczego to wazne: `reconcile` kosztuje ~209 ms na snapshot i leci dwa razy
/// w trybie porownania. Podgrzewanie w tle ma sens tylko wtedy, gdy ekran
/// faktycznie trafia w cache, a nie liczy jeszcze raz.
@MainActor
final class BodyReconcileCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BodyReconcileCache.removeAll()
    }

    private func snapshot(waistCm: Double = 86) -> BodySnapshot {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return BodySnapshot(
            gender: .male, age: 31, heightCm: 180, weightKg: 80, bodyFatPercent: 20,
            neckCm: 38, shouldersCm: 118, chestCm: 100, bustCm: nil,
            waistCm: waistCm, hipsCm: 98, bicepCm: 33, forearmCm: 28,
            thighCm: 58, calfCm: 38, anchorDate: date, sourceDateRange: date...date
        )
    }

    func testFirstResolveStoresAndSecondReturnsTheSameAnswer() async {
        let input = snapshot()
        XCTAssertNil(BodyReconcileCache.cached(input))

        let first = await BodyReconcileCache.resolve(input)
        XCTAssertNotNil(BodyReconcileCache.cached(input))

        let second = await BodyReconcileCache.resolve(input)
        XCTAssertEqual(first.parameters, second.parameters)
        XCTAssertEqual(first.validation, second.validation)
    }

    /// Dlaczego: to jest cala obietnica podgrzewania. Drugie wywolanie ma
    /// odczytac, nie policzyc — a liczenie to setki milisekund.
    func testASecondResolveIsOrdersOfMagnitudeFaster() async {
        let input = snapshot()

        let coldStart = Date()
        _ = await BodyReconcileCache.resolve(input)
        let cold = Date().timeIntervalSince(coldStart)

        let warmStart = Date()
        _ = await BodyReconcileCache.resolve(input)
        let warm = Date().timeIntervalSince(warmStart)

        XCTAssertLessThan(warm, cold / 10, "cold \(cold * 1000) ms vs warm \(warm * 1000) ms")
    }

    func testDifferentMeasurementsDoNotShareAnEntry() async {
        let thin = await BodyReconcileCache.resolve(snapshot(waistCm: 74))
        let wide = await BodyReconcileCache.resolve(snapshot(waistCm: 104))
        XCTAssertNotEqual(thin.parameters, wide.parameters)
        XCTAssertNotNil(BodyReconcileCache.cached(snapshot(waistCm: 74)))
        XCTAssertNotNil(BodyReconcileCache.cached(snapshot(waistCm: 104)))
    }

    /// Dlaczego: snapshot jest kluczem, wiec musi rozroznia daty — inaczej dwie
    /// rozne daty w porownaniu trafilyby w ten sam wpis.
    func testSnapshotsDifferingOnlyByDateAreDistinctKeys() {
        var earlier = snapshot()
        let later = BodySnapshot(
            gender: earlier.gender, age: earlier.age, heightCm: earlier.heightCm,
            weightKg: earlier.weightKg, bodyFatPercent: earlier.bodyFatPercent,
            neckCm: earlier.neckCm, shouldersCm: earlier.shouldersCm,
            chestCm: earlier.chestCm, bustCm: earlier.bustCm, waistCm: earlier.waistCm,
            hipsCm: earlier.hipsCm, bicepCm: earlier.bicepCm, forearmCm: earlier.forearmCm,
            thighCm: earlier.thighCm, calfCm: earlier.calfCm,
            anchorDate: earlier.anchorDate.addingTimeInterval(86_400),
            sourceDateRange: earlier.sourceDateRange
        )
        earlier = snapshot()
        XCTAssertNotEqual(earlier.hashValue, later.hashValue)
        XCTAssertNotEqual(earlier, later)
    }
}
