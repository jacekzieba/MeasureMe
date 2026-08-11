/// Cel testow: Sprawdza stan ekranu modelu 3D — dostepne daty, tryby i morf.
/// Dlaczego to wazne: Stan decyduje, co uzytkownik widzi: braki, pojedyncza sylwetke czy porownanie.
/// Kryteria zaliczenia: Przejscia stanow i interpolacja odpowiadaja specyfikacji.

import XCTest
import Foundation
@testable import MeasureMe

@MainActor
final class BodyModelViewModelTests: XCTestCase {

    private let anchor = Date(timeIntervalSince1970: 1_760_000_000)

    private func completeSamples(at date: Date, waist: Double = 85) -> [MetricSample] {
        let values: [MetricKind: Double] = [
            .height: 180, .weight: 80, .bodyFat: 18,
            .neck: 38, .shoulders: 118, .chest: 100, .waist: waist, .hips: 98,
            .leftBicep: 34, .rightBicep: 34, .leftForearm: 28, .rightForearm: 28,
            .leftThigh: 58, .rightThigh: 58, .leftCalf: 38, .rightCalf: 38
        ]
        return values.map { MetricSample(kind: $0.key, value: $0.value, date: date) }
    }

    /// Co sprawdza: Brak plci daje stan .needsProfile.
    /// Dlaczego: Bez plci nie da sie wybrac bazowej siatki.
    /// Kryteria: Stan to .needsProfile mimo kompletnych pomiarow.
    func testMissingGenderYieldsNeedsProfile() {
        let viewModel = BodyModelViewModel()
        viewModel.load(samples: completeSamples(at: anchor), gender: BodyGender(.notSpecified), age: 30, fallbackHeightCm: 180)
        XCTAssertEqual(viewModel.state, .needsProfile)
    }

    /// Co sprawdza: Niekompletne pomiary daja liste brakow.
    /// Dlaczego: Stan pusty ma wymieniac userowi, czego brakuje.
    /// Kryteria: Stan to .missingMetrics zawierajacy usunieta metryke.
    func testIncompleteSamplesYieldMissingMetrics() {
        let samples = completeSamples(at: anchor).filter { $0.kindRaw != MetricKind.neck.rawValue }
        let viewModel = BodyModelViewModel()
        viewModel.load(samples: samples, gender: .male, age: 30, fallbackHeightCm: 180)

        guard case let .missingMetrics(kinds) = viewModel.state else {
            return XCTFail("Expected missingMetrics, got \(viewModel.state)")
        }
        XCTAssertTrue(kinds.contains(.neck))
    }

    /// Co sprawdza: Jeden komplet daje stan .single.
    /// Dlaczego: Feature ma dzialac od pierwszego kompletnego pomiaru, bez morfu.
    /// Kryteria: Stan to .single, a lista zmian jest pusta.
    func testSingleCompleteSnapshotYieldsSingleState() {
        let viewModel = BodyModelViewModel()
        viewModel.load(samples: completeSamples(at: anchor), gender: .male, age: 30, fallbackHeightCm: 180)

        guard case .single = viewModel.state else {
            return XCTFail("Expected single, got \(viewModel.state)")
        }
        XCTAssertTrue(viewModel.metricChanges.isEmpty)
    }

    /// Co sprawdza: Dwa komplety oddalone o wiecej niz okno daja porownanie.
    /// Dlaczego: To glowny tryb feature'u.
    /// Kryteria: Stan to .comparison, a lista zmian nie jest pusta i zawiera wiersz talii bez wskazania strony.
    func testTwoDistinctSnapshotsYieldComparison() {
        let older = completeSamples(at: anchor.addingTimeInterval(-90 * 86_400), waist: 95)
        let newer = completeSamples(at: anchor, waist: 85)

        let viewModel = BodyModelViewModel()
        viewModel.load(samples: older + newer, gender: .male, age: 30, fallbackHeightCm: 180)

        guard case .comparison = viewModel.state else {
            return XCTFail("Expected comparison, got \(viewModel.state)")
        }
        XCTAssertTrue(viewModel.metricChanges.contains { $0.titleKey == "metric.waist" && $0.difference == -10 })
    }

    /// Co sprawdza: Daty kotwiczace bliskie sobie nie tworza osobnych snapshotow.
    /// Dlaczego: Dwie daty w tym samym oknie +/-14 dni opisuja ten sam stan ciala.
    /// Kryteria: Dla probek z jednego tygodnia jest dokladnie jedna data kotwiczaca.
    func testDatesWithinOneWindowCollapseToASingleAnchor() {
        let samples = completeSamples(at: anchor) + completeSamples(at: anchor.addingTimeInterval(-3 * 86_400))
        let dates = BodyModelViewModel.availableAnchorDates(
            samples: samples, gender: .male, fallbackHeightCm: 180
        )
        XCTAssertEqual(dates.count, 1)
    }

    /// Co sprawdza: morphProgress steruje interpolacja parametrow.
    /// Dlaczego: To wiazanie suwaka z geometria.
    /// Kryteria: t=0 daje starszy stan, t=1 nowszy.
    func testMorphProgressDrivesCurrentParameters() {
        let older = completeSamples(at: anchor.addingTimeInterval(-90 * 86_400), waist: 95)
        let newer = completeSamples(at: anchor, waist: 85)

        let viewModel = BodyModelViewModel()
        viewModel.load(samples: older + newer, gender: .male, age: 30, fallbackHeightCm: 180)
        guard case let .comparison(olderResolved, newerResolved) = viewModel.state else {
            return XCTFail("Expected comparison")
        }

        viewModel.morphProgress = 0
        XCTAssertEqual(viewModel.currentParameters, olderResolved.parameters)

        viewModel.morphProgress = 1
        XCTAssertEqual(viewModel.currentParameters, newerResolved.parameters)
    }
}
