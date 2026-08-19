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
    func testMissingGenderYieldsNeedsProfile() async {
        let viewModel = BodyModelViewModel()
        await viewModel.load(samples: completeSamples(at: anchor), gender: BodyGender(.notSpecified), age: 30, fallbackHeightCm: 180)
        XCTAssertEqual(viewModel.state, .needsProfile)
    }

    /// Co sprawdza: Niekompletne pomiary daja liste brakow.
    /// Dlaczego: Stan pusty ma wymieniac userowi, czego brakuje.
    /// Kryteria: Stan to .missingMetrics zawierajacy usunieta metryke.
    func testIncompleteSamplesYieldMissingMetrics() async {
        let samples = completeSamples(at: anchor).filter { $0.kindRaw != MetricKind.neck.rawValue }
        let viewModel = BodyModelViewModel()
        await viewModel.load(samples: samples, gender: .male, age: 30, fallbackHeightCm: 180)

        guard case let .missingMetrics(kinds) = viewModel.state else {
            return XCTFail("Expected missingMetrics, got \(viewModel.state)")
        }
        XCTAssertTrue(kinds.contains(.neck))
    }

    /// Co sprawdza: Jeden komplet daje stan .single.
    /// Dlaczego: Feature ma dzialac od pierwszego kompletnego pomiaru, bez morfu.
    /// Kryteria: Stan to .single, a lista zmian jest pusta.
    func testSingleCompleteSnapshotYieldsSingleState() async {
        let viewModel = BodyModelViewModel()
        await viewModel.load(samples: completeSamples(at: anchor), gender: .male, age: 30, fallbackHeightCm: 180)

        guard case .single = viewModel.state else {
            return XCTFail("Expected single, got \(viewModel.state)")
        }
        XCTAssertTrue(viewModel.metricChanges.isEmpty)
    }

    /// Co sprawdza: Dwa komplety oddalone o wiecej niz okno daja porownanie.
    /// Dlaczego: To glowny tryb feature'u.
    /// Kryteria: Stan to .comparison, a lista zmian nie jest pusta i zawiera wiersz talii bez wskazania strony.
    func testTwoDistinctSnapshotsYieldComparison() async {
        let older = completeSamples(at: anchor.addingTimeInterval(-90 * 86_400), waist: 95)
        let newer = completeSamples(at: anchor, waist: 85)

        let viewModel = BodyModelViewModel()
        await viewModel.load(samples: older + newer, gender: .male, age: 30, fallbackHeightCm: 180)

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

    /// Co sprawdza: availableDates jest wypelniane datami kotwiczacymi z porownania.
    /// Dlaczego: Ekran potrzebuje tej listy, by zbudowac pickery dat "From"/"To".
    /// Kryteria: Lista zawiera obie daty kotwiczace, najnowsza pierwsza.
    func testAvailableDatesPopulatedForComparison() async {
        let olderDate = anchor.addingTimeInterval(-90 * 86_400)
        let older = completeSamples(at: olderDate, waist: 95)
        let newer = completeSamples(at: anchor, waist: 85)

        let viewModel = BodyModelViewModel()
        await viewModel.load(samples: older + newer, gender: .male, age: 30, fallbackHeightCm: 180)

        XCTAssertEqual(viewModel.availableDates, [anchor, olderDate])
    }

    /// Co sprawdza: Brak plci czysci availableDates.
    /// Dlaczego: Ekran nie powinien oferowac pickera dat, gdy stan to .needsProfile.
    /// Kryteria: Lista jest pusta mimo kompletnych pomiarow.
    func testAvailableDatesEmptyWhenGenderMissing() async {
        let viewModel = BodyModelViewModel()
        await viewModel.load(samples: completeSamples(at: anchor), gender: BodyGender(.notSpecified), age: 30, fallbackHeightCm: 180)

        XCTAssertTrue(viewModel.availableDates.isEmpty)
    }

    /// Co sprawdza: Pomiary rozrzucone po roznych dniach nadal buduja sylwetke.
    /// Dlaczego: Zgloszenie uzytkownika — "aplikacja prosi o metryki, ktore mam dawno dodane".
    ///   Nikt nie mierzy szesnastu obwodow jednego dnia; user robi to partiami przez tygodnie.
    ///   Przy oknie 14 dni zadna data nie miala kompletu, wiec load() raportowal jako brakujace
    ///   metryki lezace w bazie.
    /// Kryteria: Komplet rozlozony co 10 dni (rozrzut 150 dni) daje sylwetke, nie liste brakow.
    func testMeasurementsScatteredAcrossMonthsStillResolve() async {
        let kinds: [MetricKind] = [
            .height, .weight, .bodyFat, .neck, .shoulders, .chest, .waist, .hips,
            .leftBicep, .rightBicep, .leftForearm, .rightForearm,
            .leftThigh, .rightThigh, .leftCalf, .rightCalf
        ]
        let values: [MetricKind: Double] = [
            .height: 180, .weight: 80, .bodyFat: 18,
            .neck: 38, .shoulders: 118, .chest: 100, .waist: 85, .hips: 98,
            .leftBicep: 34, .rightBicep: 34, .leftForearm: 28, .rightForearm: 28,
            .leftThigh: 58, .rightThigh: 58, .leftCalf: 38, .rightCalf: 38
        ]
        let samples = kinds.enumerated().map { index, kind in
            MetricSample(
                kind: kind,
                value: values[kind] ?? 50,
                date: anchor.addingTimeInterval(Double(-10 * index) * 86_400)
            )
        }

        let viewModel = BodyModelViewModel()
        await viewModel.load(samples: samples, gender: .male, age: 30, fallbackHeightCm: 180)

        if case let .missingMetrics(missing) = viewModel.state {
            XCTFail("Scattered but complete data reported as missing: \(missing.map(\.rawValue))")
        }
    }

    /// Co sprawdza: Daty oddalone o wiecej niz okno zwijania, ale mieszczace sie w oknie probek,
    ///   nadal daja dwie osobne kotwice.
    /// Dlaczego: Poszerzenie okna probek nie moze zlac wszystkich dat w jedna — to zabiloby
    ///   porownanie dwoch stanow ciala, czyli glowny tryb feature'u.
    /// Kryteria: Dwa komplety oddalone o 30 dni daja dwie daty kotwiczace.
    func testWideningTheSampleWindowDoesNotCollapseDistinctAnchors() {
        let olderDate = anchor.addingTimeInterval(-30 * 86_400)
        let samples = completeSamples(at: olderDate, waist: 95) + completeSamples(at: anchor, waist: 85)

        let dates = BodyModelViewModel.availableAnchorDates(
            samples: samples, gender: .male, fallbackHeightCm: 180
        )

        XCTAssertEqual(dates, [anchor, olderDate])
    }

    /// Co sprawdza: morphProgress steruje interpolacja parametrow.
    /// Dlaczego: To wiazanie suwaka z geometria.
    /// Kryteria: t=0 daje starszy stan, t=1 nowszy.
    func testMorphProgressDrivesCurrentParameters() async {
        let older = completeSamples(at: anchor.addingTimeInterval(-90 * 86_400), waist: 95)
        let newer = completeSamples(at: anchor, waist: 85)

        let viewModel = BodyModelViewModel()
        await viewModel.load(samples: older + newer, gender: .male, age: 30, fallbackHeightCm: 180)
        guard case let .comparison(olderResolved, newerResolved) = viewModel.state else {
            return XCTFail("Expected comparison")
        }

        viewModel.morphProgress = 0
        XCTAssertEqual(viewModel.currentParameters, olderResolved.parameters)

        viewModel.morphProgress = 1
        XCTAssertEqual(viewModel.currentParameters, newerResolved.parameters)
    }

    /// Co sprawdza: Dopisanie brakujacej metryki przeprowadza stan z .missingMetrics w .single.
    /// Dlaczego: Na tym stoi uzupelnianie w miejscu — po zapisie ekran ma sam przeliczyc model,
    ///   bez zamykania i ponownego otwierania.
    /// Kryteria: Ten sam view model po ponownym load() z kompletem probek jest w stanie .single.
    func testLoggingTheMissingMetricAdvancesToSingle() async {
        let incomplete = completeSamples(at: anchor).filter { $0.kindRaw != MetricKind.neck.rawValue }
        let viewModel = BodyModelViewModel()
        await viewModel.load(samples: incomplete, gender: .male, age: 30, fallbackHeightCm: 180)

        guard case .missingMetrics = viewModel.state else {
            return XCTFail("Precondition: expected missingMetrics, got \(viewModel.state)")
        }

        let completed = incomplete + [MetricSample(kind: .neck, value: 38, date: anchor)]
        await viewModel.load(samples: completed, gender: .male, age: 30, fallbackHeightCm: 180)

        guard case .single = viewModel.state else {
            return XCTFail("Expected single after logging the missing metric, got \(viewModel.state)")
        }
    }
}
