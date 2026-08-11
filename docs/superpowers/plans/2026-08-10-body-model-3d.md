# Model 3D sylwetki — plan implementacji

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zamienić wprowadzone obwody ciała w uproszczony manekin 3D i pokazać jego zmianę w czasie jako morf między dwoma datowanymi pomiarami.

**Architecture:** Ciało to ~20 poziomych przekrojów-superelips wzdłuż osi Y. Obwody pochodzą z pomiarów, pozycje pionowe i kształty przekrojów z tablic antropometrycznych. Objętość ma postać analityczną, więc walidacja masy nie wymaga liczenia po siatce, a morf interpoluje parametry przekrojów zamiast wierzchołków. Sześć jednostek matematycznych nie importuje SceneKit i jest testowalnych bez renderowania.

**Tech Stack:** Swift 6.4, SwiftUI, SwiftData, SceneKit (nowa zależność systemowa — bez pakietów zewnętrznych), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-10-body-model-3d-design.md`

## Global Constraints

- Wszystkie wartości metryk w kodzie są w jednostkach metrycznych (kg, cm, %). Konwersja tylko do wyświetlania, przez `MetricKind.valueForDisplay(fromMetric:unitsSystem:)`.
- Wszystkie teksty widoczne dla użytkownika przez `AppLocalization.string(...)`, z wpisami we **wszystkich** plikach `.lproj/Localizable.strings` targetu `MeasureMe`: `en`, `pl`, `de`, `es`, `fr`, `pt-BR`.
- Akcent feature'u to `FeatureTheme.photos` — nigdy `.appAccent` ani kolory zaszyte na sztywno.
- Karty przez `AppGlassCard`, odstępy przez `AppSpacing`, promienie przez `AppRadius`, typografia przez `AppTypography`, animacje przez `AppMotion`.
- Animacje bramkowane przez `AppMotion.shouldAnimate(animationsEnabled:reduceMotion:)`.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` jest ustawione dla targetu `MeasureMe`. Typy czysto obliczeniowe oznaczać `nonisolated`, żeby dało się je wołać spoza main actora.
- Identyfikatory dostępności w konwencji `photos.bodyModel.*`.
- Nowe pliki trafiają do `MeasureMe/BodyModel/` — target używa `PBXFileSystemSynchronizedRootGroup`, więc **nie** trzeba edytować `project.pbxproj`.

### Uruchamianie testów

`xcodebuild` nie jest na domyślnym toolchainie tego Maca. Każde polecenie poprzedzić:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

Wzorzec polecenia testowego używany w całym planie:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -only-testing:MeasureMeTests/<KlasaTestowa>
```

Jeśli symulator nie startuje („cannot be located on disk"): `xcrun simctl erase 423D83EE-E5BE-42DC-A5F8-0B3EB62A0182 && xcrun simctl boot 423D83EE-E5BE-42DC-A5F8-0B3EB62A0182`.

Testy snapshotowe na iOS 27.0 są **oczekiwanie czerwone** w całym repo (niedopasowane baseline'y runtime'u). Nie traktować ich jako regresji; oceniać po testach nie-snapshotowych.

---

## Struktura plików

| Plik | Odpowiedzialność |
|---|---|
| `MeasureMe/BodyModel/Superellipse.swift` | Geometria przekroju: pole, obwód, dopasowanie do zadanego obwodu |
| `MeasureMe/BodyModel/BodySnapshot.swift` | Wartość: 13 metryk + profil + zakres dat |
| `MeasureMe/BodyModel/BodySnapshotBuilder.swift` | `[MetricSample]` → snapshot lub lista braków |
| `MeasureMe/BodyModel/BodyProportions.swift` | Tablice antropometryczne, per gender |
| `MeasureMe/BodyModel/BodyMeshParameters.swift` | ~20 poziomów przekrojów + interpolacja |
| `MeasureMe/BodyModel/BodyMeshSolver.swift` | Snapshot → parametry siatki |
| `MeasureMe/BodyModel/BodyVolumeValidator.swift` | Objętość, gęstość, odchyłka masy, korekta |
| `MeasureMe/BodyModel/BodyGeometryBuilder.swift` | Parametry → `SCNGeometry` |
| `MeasureMe/BodyModel/MannequinView.swift` | `SCNView` w `UIViewRepresentable` |
| `MeasureMe/BodyModel/BodyModelViewModel.swift` | Stan ekranu, wybór dat, morf |
| `MeasureMe/BodyModel/BodyModelScreen.swift` | Ekran w Photos |
| `MeasureMe/MetricChangeRow.swift` | Wyciągnięty z `ComparePhotosView.swift`, `internal` |

---

### Task 1: Superellipse

Geometria przekroju. Podstawa całej reszty — pole przekroju wchodzi do objętości, a dopasowanie obwodu do solvera.

Kluczowa własność: obwód superelipsy skaluje się **liniowo** z półosiami, więc dopasowanie do zadanego obwodu nie wymaga iteracji. Liczymy obwód kształtu jednostkowego i skalujemy.

**Files:**
- Create: `MeasureMe/BodyModel/Superellipse.swift`
- Test: `MeasureMeTests/SuperellipseTests.swift`

**Interfaces:**
- Consumes: nic
- Produces: `Superellipse(semiAxisA:semiAxisB:exponent:)`, `.area: Double`, `.perimeter: Double`, `static func fitting(circumference: Double, aspectRatio: Double, exponent: Double) -> Superellipse`. `aspectRatio` to `semiAxisB / semiAxisA` (głębokość / szerokość).

- [ ] **Step 1: Write the failing test**

Okrąg i elipsa są dokładnymi wyroczniami — znamy ich pole i obwód niezależnie od implementacji.

```swift
/// Cel testow: Sprawdza geometrie przekroju superelipsy uzywana przez model 3D sylwetki.
/// Dlaczego to wazne: Pole przekroju wchodzi do objetosci, a dopasowanie obwodu do solvera.
/// Kryteria zaliczenia: Przypadki okregu i elipsy zgadzaja sie z wzorami analitycznymi.

import XCTest
import Foundation
@testable import MeasureMe

final class SuperellipseTests: XCTestCase {

    /// Co sprawdza: Dla n=2 i aspect=1 superelipsa jest okregiem.
    /// Dlaczego: To jedyna wyrocznia niezalezna od implementacji.
    /// Kryteria: Pole i obwod zgadzaja sie ze wzorami okregu.
    func testCircleCaseMatchesAnalyticFormulas() {
        let circle = Superellipse(semiAxisA: 5, semiAxisB: 5, exponent: 2)
        XCTAssertEqual(circle.area, Double.pi * 25, accuracy: 1e-6)
        XCTAssertEqual(circle.perimeter, 2 * Double.pi * 5, accuracy: 1e-4)
    }

    /// Co sprawdza: Dla n=2 pole elipsy to pi*a*b.
    /// Dlaczego: Weryfikuje czlon gamma we wzorze na pole.
    /// Kryteria: Pole zgadza sie ze wzorem elipsy.
    func testEllipseAreaMatchesAnalyticFormula() {
        let ellipse = Superellipse(semiAxisA: 8, semiAxisB: 4, exponent: 2)
        XCTAssertEqual(ellipse.area, Double.pi * 8 * 4, accuracy: 1e-6)
    }

    /// Co sprawdza: fitting() odtwarza zadany obwod.
    /// Dlaczego: To kontrakt uzywany przez solver dla kazdego pomiaru uzytkownika.
    /// Kryteria: Obwod dopasowanego ksztaltu rowna sie zadanemu ponizej 0.05 mm.
    func testFittingReproducesRequestedCircumference() {
        for aspect in [1.0, 0.72, 0.55] {
            for exponent in [2.0, 2.3, 2.6] {
                let shape = Superellipse.fitting(
                    circumference: 94.0,
                    aspectRatio: aspect,
                    exponent: exponent
                )
                XCTAssertEqual(shape.perimeter, 94.0, accuracy: 0.005)
                XCTAssertEqual(shape.semiAxisB / shape.semiAxisA, aspect, accuracy: 1e-9)
            }
        }
    }

    /// Co sprawdza: Przy stalych polosiach wyzszy wykladnik daje wieksze pole.
    /// Dlaczego: Weryfikuje kierunek czlonu gamma — ksztalt dazy do prostokata 4ab, a nie do elipsy pi*ab.
    /// Kryteria: Pole rosnie monotonicznie z wykladnikiem i zmierza do 4ab.
    func testAreaGrowsWithExponentAtFixedSemiAxes() {
        let areas = [2.0, 2.3, 2.6, 3.0, 8.0].map {
            Superellipse(semiAxisA: 8, semiAxisB: 6, exponent: $0).area
        }
        XCTAssertEqual(areas, areas.sorted())
        XCTAssertLessThan(areas.last!, 4 * 8 * 6)
    }

    /// Co sprawdza: Przy stalym obwodzie wyzszy wykladnik daje MNIEJSZE pole.
    /// Dlaczego: To nierownosc izoperymetryczna — okrag maksymalizuje pole dla danego obwodu,
    ///           wiec ksztalt bardziej pudelkowaty mniej go obejmuje. Solver trzyma staly obwod,
    ///           wiec to jest kierunek, ktory realnie widzi model objetosciowy.
    /// Kryteria: Pole maleje monotonicznie z wykladnikiem.
    func testAreaFallsWithExponentAtFixedCircumference() {
        let areas = [2.0, 2.3, 2.6, 3.0].map {
            Superellipse.fitting(circumference: 80, aspectRatio: 0.75, exponent: $0).area
        }
        XCTAssertEqual(areas, areas.sorted(by: >))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/SuperellipseTests
```

Expected: FAIL — `cannot find 'Superellipse' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Superellipse.swift
//
// **Superellipse**
// Cross-section geometry for the 3D body model.
//
// **Responsibilities:**
// - Analytic area of a superellipse
// - Numeric perimeter by arc-length integration
// - Fitting a shape to a measured circumference
//
// **Why the perimeter is numeric but the area is not:**
// The area of |x/a|^n + |z/b|^n = 1 has a closed form in gamma functions.
// The perimeter does not, so it is integrated. Because the perimeter scales
// linearly with the semi-axes, fitting a shape to a measured circumference
// needs one integration of the unit shape and a multiply — never a solve.
//
import Foundation

nonisolated struct Superellipse: Equatable, Sendable {
    /// Semi-axis along x (half the body width at this level), in cm.
    let semiAxisA: Double
    /// Semi-axis along z (half the body depth at this level), in cm.
    let semiAxisB: Double
    /// Shape exponent. 2 is an ellipse; higher values approach a rectangle.
    let exponent: Double

    /// Number of integration steps for the perimeter. 2048 keeps the circle
    /// case within 1e-6 of 2*pi*r, which is well inside the 0.5 mm invariant
    /// the solver relies on.
    private static let integrationSteps = 2048

    /// Closed-form area: 4ab * Γ(1+1/n)² / Γ(1+2/n).
    var area: Double {
        4 * semiAxisA * semiAxisB * pow(tgamma(1 + 1 / exponent), 2) / tgamma(1 + 2 / exponent)
    }

    /// Arc length of the full outline, integrated over one revolution.
    var perimeter: Double {
        let steps = Self.integrationSteps
        let dt = (2 * Double.pi) / Double(steps)
        var total = 0.0
        var previous = point(at: 0)
        for step in 1...steps {
            let current = point(at: Double(step) * dt)
            total += hypot(current.x - previous.x, current.z - previous.z)
            previous = current
        }
        return total
    }

    /// Parametric point on the outline. The `sign * pow(abs())` form keeps the
    /// parametrisation valid in all four quadrants for non-integer exponents.
    private func point(at t: Double) -> (x: Double, z: Double) {
        let cosT = cos(t)
        let sinT = sin(t)
        let power = 2 / exponent
        return (
            x: semiAxisA * (cosT < 0 ? -1 : 1) * pow(abs(cosT), power),
            z: semiAxisB * (sinT < 0 ? -1 : 1) * pow(abs(sinT), power)
        )
    }

    /// Builds the shape whose perimeter equals `circumference`.
    /// - Parameters:
    ///   - circumference: Measured circumference in cm.
    ///   - aspectRatio: `semiAxisB / semiAxisA` — depth over width.
    ///   - exponent: Shape exponent.
    static func fitting(circumference: Double, aspectRatio: Double, exponent: Double) -> Superellipse {
        let unit = Superellipse(semiAxisA: 1, semiAxisB: aspectRatio, exponent: exponent)
        let scale = circumference / unit.perimeter
        return Superellipse(
            semiAxisA: scale,
            semiAxisB: aspectRatio * scale,
            exponent: exponent
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/Superellipse.swift MeasureMeTests/SuperellipseTests.swift
git commit -m "feat(body-model): superellipse cross-section geometry"
```

---

### Task 2: BodySnapshot i BodySnapshotBuilder

Zamiana surowych `MetricSample` w jeden kompletny stan ciała, z oknem ±14 dni i uśrednianiem lewej/prawej strony.

**Decyzja:** dla par lewa/prawa wymagana jest **co najmniej jedna** strona; gdy obie istnieją, bierzemy średnią. Wymaganie obu podnosiłoby próg wejścia bez zysku dla modelu, skoro i tak uśredniamy.

**Files:**
- Create: `MeasureMe/BodyModel/BodySnapshot.swift`, `MeasureMe/BodyModel/BodySnapshotBuilder.swift`
- Test: `MeasureMeTests/BodySnapshotBuilderTests.swift`

**Interfaces:**
- Consumes: `MetricSample` (`kindRaw: String`, `value: Double`, `date: Date`), `MetricKind`, `BodyGender` (tworzone w Zadaniu 3 — patrz niżej)
- Produces: `BodySnapshot` (pola niżej), `BodySnapshotBuilder.build(samples:anchorDate:gender:age:fallbackHeightCm:) -> BodySnapshotBuildResult`, `BodySnapshotBuilder.requiredKinds(for: BodyGender) -> [MetricKind]`, `BodySnapshotBuilder.windowDays = 14`

> **Uwaga o kolejności.** To zadanie zostało zaimplementowane, zanim ujawnił się problem z `Gender.notSpecified`. Pierwotnie używało `Gender` z `HealthMetricsCalculator.swift`, który ma trzy przypadki. Zadanie 3 wprowadza dwuprzypadkowy `BodyGender` i migruje ten kod. Jeśli implementujesz od zera, użyj `BodyGender` od razu.

- [ ] **Step 1: Write the failing test**

```swift
/// Cel testow: Sprawdza budowanie kompletnego snapshotu ciala z surowych probek.
/// Dlaczego to wazne: Snapshot jest jedynym wejsciem modelu 3D; blad tutaj psuje cala sylwetke.
/// Kryteria zaliczenia: Okno +/-14 dni, usrednianie lewa/prawa i wykrywanie brakow dzialaja zgodnie ze specyfikacja.

import XCTest
import Foundation
@testable import MeasureMe

final class BodySnapshotBuilderTests: XCTestCase {

    private let anchor = Date(timeIntervalSince1970: 1_760_000_000)

    private func day(_ offset: Int) -> Date {
        anchor.addingTimeInterval(Double(offset) * 86_400)
    }

    /// Buduje komplet probek dla mezczyzny, wszystkie w dniu kotwiczacym.
    private func completeMaleSamples(at date: Date) -> [MetricSample] {
        let values: [MetricKind: Double] = [
            .height: 180, .weight: 80, .bodyFat: 18,
            .neck: 38, .shoulders: 118, .chest: 100, .waist: 85, .hips: 98,
            .leftBicep: 34, .rightBicep: 34,
            .leftForearm: 28, .rightForearm: 28,
            .leftThigh: 58, .rightThigh: 58,
            .leftCalf: 38, .rightCalf: 38
        ]
        return values.map { MetricSample(kind: $0.key, value: $0.value, date: date) }
    }

    /// Co sprawdza: Komplet probek daje snapshot, a nie liste brakow.
    /// Dlaczego: To sciezka happy path calego feature'u.
    /// Kryteria: Wynik to .success z wartosciami przepisanymi 1:1.
    func testCompleteSampleSetBuildsSnapshot() {
        let result = BodySnapshotBuilder.build(
            samples: completeMaleSamples(at: anchor),
            anchorDate: anchor,
            gender: .male,
            age: 30,
            fallbackHeightCm: 0
        )
        guard case let .success(snapshot) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(snapshot.heightCm, 180, accuracy: 1e-9)
        XCTAssertEqual(snapshot.waistCm, 85, accuracy: 1e-9)
        XCTAssertNil(snapshot.bustCm)
    }

    /// Co sprawdza: Lewa i prawa strona sa usredniane.
    /// Dlaczego: Spec wymaga jednej, symetrycznej sylwetki.
    /// Kryteria: Bicep 34/36 daje 35.
    func testLeftAndRightAreAveraged() {
        var samples = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.rightBicep.rawValue }
        samples.append(MetricSample(kind: .rightBicep, value: 36, date: anchor))

        guard case let .success(snapshot) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Expected success") }

        XCTAssertEqual(snapshot.bicepCm, 35, accuracy: 1e-9)
    }

    /// Co sprawdza: Jedna strona pary wystarcza.
    /// Dlaczego: Wymaganie obu stron podnosiloby prog wejscia bez zysku dla modelu.
    /// Kryteria: Snapshot powstaje, a wartosc to ta jedna zmierzona strona.
    func testSingleSideOfAPairIsSufficient() {
        let samples = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.rightCalf.rawValue }

        guard case let .success(snapshot) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Expected success") }

        XCTAssertEqual(snapshot.calfCm, 38, accuracy: 1e-9)
    }

    /// Co sprawdza: Granice okna +/-14 dni.
    /// Dlaczego: To rdzen definicji snapshotu ze specyfikacji.
    /// Kryteria: 14 dni wchodzi, 15 dni nie.
    func testWindowBoundaryAtFourteenDays() {
        var inside = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.waist.rawValue }
        inside.append(MetricSample(kind: .waist, value: 85, date: day(-14)))
        guard case .success = BodySnapshotBuilder.build(
            samples: inside, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("14 days should be inside the window") }

        var outside = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.waist.rawValue }
        outside.append(MetricSample(kind: .waist, value: 85, date: day(-15)))
        guard case let .missing(kinds) = BodySnapshotBuilder.build(
            samples: outside, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("15 days should be outside the window") }
        XCTAssertEqual(kinds, [.waist])
    }

    /// Co sprawdza: Wybierana jest probka najblizsza dacie kotwiczacej.
    /// Dlaczego: Snapshot ma reprezentowac moment, nie sredni z okna.
    /// Kryteria: Przy dwoch probkach w oknie wygrywa blizsza.
    func testNearestSampleWithinWindowWins() {
        var samples = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.waist.rawValue }
        samples.append(MetricSample(kind: .waist, value: 90, date: day(-10)))
        samples.append(MetricSample(kind: .waist, value: 85, date: day(-2)))

        guard case let .success(snapshot) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Expected success") }

        XCTAssertEqual(snapshot.waistCm, 85, accuracy: 1e-9)
    }

    /// Co sprawdza: Bust jest wymagany tylko u kobiet.
    /// Dlaczego: U mezczyzn obwod klatki niesie te sama informacje.
    /// Kryteria: Te same probki bez bustu przechodza dla mezczyzny i nie dla kobiety.
    func testBustRequiredOnlyForFemale() {
        let samples = completeMaleSamples(at: anchor)

        guard case .success = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Male should not need bust") }

        guard case let .missing(kinds) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .female, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Female should need bust") }
        XCTAssertEqual(kinds, [.bust])
    }

    /// Co sprawdza: Brak probki wzrostu jest uzupelniany wzrostem z profilu.
    /// Dlaczego: manualHeight w ustawieniach jest dla wielu userow jedynym zrodlem wzrostu.
    /// Kryteria: Snapshot powstaje i uzywa wartosci fallbackowej.
    func testFallbackHeightIsUsedWhenNoHeightSample() {
        let samples = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.height.rawValue }

        guard case let .success(snapshot) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 178
        ) else { return XCTFail("Expected success") }

        XCTAssertEqual(snapshot.heightCm, 178, accuracy: 1e-9)
    }

    /// Co sprawdza: Braki sa raportowane w calosci, nie po pierwszym napotkanym.
    /// Dlaczego: Stan pusty ma wymieniac userowi wszystko, czego brakuje.
    /// Kryteria: Lista brakow zawiera obie usuniete metryki, posortowana.
    func testAllMissingKindsAreReported() {
        let samples = completeMaleSamples(at: anchor).filter {
            $0.kindRaw != MetricKind.neck.rawValue && $0.kindRaw != MetricKind.bodyFat.rawValue
        }
        guard case let .missing(kinds) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Expected missing") }

        XCTAssertEqual(kinds, [.bodyFat, .neck])
    }

    /// Co sprawdza: sourceDateRange obejmuje wylacznie probki faktycznie uzyte.
    /// Dlaczego: Pole opisuje userowi, z jakiego okresu pochodzi sylwetka; nieuzyta metryka nie ma prawa go rozciagac.
    /// Kryteria: Probki .bust (nieuzywana u mezczyzn) i .leanBodyMass na krancach okna nie zmieniaja zakresu.
    func testSourceDateRangeCoversOnlyUsedSamples() {
        var samples = completeMaleSamples(at: anchor)
        samples.append(MetricSample(kind: .bust, value: 95, date: day(-14)))
        samples.append(MetricSample(kind: .leanBodyMass, value: 65, date: day(14)))

        guard case let .success(snapshot) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Expected success") }

        XCTAssertEqual(snapshot.sourceDateRange.lowerBound, anchor)
        XCTAssertEqual(snapshot.sourceDateRange.upperBound, anchor)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodySnapshotBuilderTests
```

Expected: FAIL — `cannot find 'BodySnapshotBuilder' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// BodySnapshot.swift
//
// **BodySnapshot**
// One complete body state, assembled from measurement samples.
//
// **Responsibilities:**
// - Holding the 13 values the mesh solver needs, in metric units
// - Recording which span of dates the values were drawn from
//
// All circumferences are already averaged across left and right, so the
// solver never sees asymmetry.
//
import Foundation

nonisolated struct BodySnapshot: Equatable, Sendable {
    let gender: BodyGender
    let age: Int
    let heightCm: Double
    let weightKg: Double
    let bodyFatPercent: Double
    let neckCm: Double
    let shouldersCm: Double
    let chestCm: Double
    /// Only populated for `.female`; `chestCm` carries the equivalent for men.
    let bustCm: Double?
    let waistCm: Double
    let hipsCm: Double
    let bicepCm: Double
    let forearmCm: Double
    let thighCm: Double
    let calfCm: Double
    /// The date the user picked. Values may come from up to 14 days either side.
    let anchorDate: Date
    /// Oldest and newest sample dates actually used, for honest labelling.
    let sourceDateRange: ClosedRange<Date>
}
```

```swift
// BodySnapshotBuilder.swift
//
// **BodySnapshotBuilder**
// Turns raw `MetricSample` rows into a complete `BodySnapshot`.
//
// **Responsibilities:**
// - Picking, per metric, the sample nearest the anchor date within ±14 days
// - Averaging left/right pairs into a single value
// - Reporting every missing metric at once, so the empty state can list them
//
import Foundation

nonisolated enum BodySnapshotBuildResult: Equatable {
    case success(BodySnapshot)
    /// Every metric the user still needs to log, in `MetricKind.allCases` order.
    case missing([MetricKind])
}

nonisolated enum BodySnapshotBuilder {
    /// Half-width of the window, in days, that a sample may sit from the anchor.
    static let windowDays = 14

    /// Left/right pairs collapsed into one value each.
    private static let pairs: [(left: MetricKind, right: MetricKind)] = [
        (.leftBicep, .rightBicep),
        (.leftForearm, .rightForearm),
        (.leftThigh, .rightThigh),
        (.leftCalf, .rightCalf)
    ]

    /// Metrics required as a single (non-paired) value.
    private static func singleKinds(for gender: BodyGender) -> [MetricKind] {
        var kinds: [MetricKind] = [
            .height, .weight, .bodyFat, .neck, .shoulders, .chest, .waist, .hips
        ]
        if gender == .female { kinds.append(.bust) }
        return kinds
    }

    /// Every metric the user must have logged for this gender.
    static func requiredKinds(for gender: BodyGender) -> [MetricKind] {
        singleKinds(for: gender) + pairs.flatMap { [$0.left, $0.right] }
    }

    /// - Parameters:
    ///   - samples: All samples available; filtered internally by window.
    ///   - anchorDate: The date the snapshot represents.
    ///   - fallbackHeightCm: `manualHeight` from settings, used when no height
    ///     sample falls in the window. Pass 0 when unset.
    static func build(
        samples: [MetricSample],
        anchorDate: Date,
        gender: BodyGender,
        age: Int,
        fallbackHeightCm: Double
    ) -> BodySnapshotBuildResult {
        let window = Double(windowDays) * 86_400
        // Only kinds this snapshot actually reads may influence it — including
        // its date range. A leanBodyMass or (for men) bust sample sitting in
        // the window must not widen `sourceDateRange`, which is documented as
        // the span of samples actually used.
        let relevant = Set(requiredKinds(for: gender).map(\.rawValue))
        let inWindow = samples.filter {
            relevant.contains($0.kindRaw)
                && abs($0.date.timeIntervalSince(anchorDate)) <= window
        }

        // Nearest sample to the anchor wins, per metric kind.
        var nearest: [String: MetricSample] = [:]
        for sample in inWindow {
            let existing = nearest[sample.kindRaw]
            let isCloser = existing.map {
                abs(sample.date.timeIntervalSince(anchorDate))
                    < abs($0.date.timeIntervalSince(anchorDate))
            } ?? true
            if isCloser { nearest[sample.kindRaw] = sample }
        }

        func value(_ kind: MetricKind) -> Double? {
            nearest[kind.rawValue]?.value
        }

        /// A pair resolves if either side is present; both sides average.
        func pairValue(_ pair: (left: MetricKind, right: MetricKind)) -> Double? {
            switch (value(pair.left), value(pair.right)) {
            case let (left?, right?): return (left + right) / 2
            case let (left?, nil): return left
            case let (nil, right?): return right
            case (nil, nil): return nil
            }
        }

        var missing: [MetricKind] = []
        for kind in singleKinds(for: gender) where value(kind) == nil {
            // Height falls back to the profile value before counting as missing.
            if kind == .height && fallbackHeightCm > 0 { continue }
            missing.append(kind)
        }
        for pair in pairs where pairValue(pair) == nil {
            missing.append(pair.left)
        }

        guard missing.isEmpty else {
            let order = MetricKind.allCases
            return .missing(missing.sorted {
                (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0)
            })
        }

        let usedDates = nearest.values.map(\.date).sorted()
        let range = (usedDates.first ?? anchorDate)...(usedDates.last ?? anchorDate)

        return .success(BodySnapshot(
            gender: gender,
            age: age,
            heightCm: value(.height) ?? fallbackHeightCm,
            weightKg: value(.weight) ?? 0,
            bodyFatPercent: value(.bodyFat) ?? 0,
            neckCm: value(.neck) ?? 0,
            shouldersCm: value(.shoulders) ?? 0,
            chestCm: value(.chest) ?? 0,
            bustCm: gender == .female ? value(.bust) : nil,
            waistCm: value(.waist) ?? 0,
            hipsCm: value(.hips) ?? 0,
            bicepCm: pairValue(pairs[0]) ?? 0,
            forearmCm: pairValue(pairs[1]) ?? 0,
            thighCm: pairValue(pairs[2]) ?? 0,
            calfCm: pairValue(pairs[3]) ?? 0,
            anchorDate: anchorDate,
            sourceDateRange: range
        ))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodySnapshot.swift MeasureMe/BodyModel/BodySnapshotBuilder.swift MeasureMeTests/BodySnapshotBuilderTests.swift
git commit -m "feat(body-model): assemble complete body snapshots from samples"
```

---

### Task 3: BodyProportions i BodyMeshParameters

Tablice antropometryczne i struktura opisująca gotową siatkę.

Wartości poniżej są **zaczątkowe**, oparte na współczynnikach Drillisa–Continiego (pozycje landmarków jako ułamki wzrostu). Kalibruje je test okrągłości z Zadania 5 — jeśli objętość systematycznie odjeżdża, korygujemy tutaj, nie w solverze.

**Files:**
- Create: `MeasureMe/BodyModel/BodyGender.swift`, `MeasureMe/BodyModel/BodyProportions.swift`, `MeasureMe/BodyModel/BodyMeshParameters.swift`
- Modify: `MeasureMe/BodyModel/BodySnapshot.swift`, `MeasureMe/BodyModel/BodySnapshotBuilder.swift`, `MeasureMeTests/BodySnapshotBuilderTests.swift` — migracja `Gender` → `BodyGender`
- Test: `MeasureMeTests/BodyMeshParametersTests.swift`

**Dlaczego `BodyGender` w ogóle istnieje.** `Gender` w `HealthMetricsCalculator.swift` ma trzy przypadki: `.male`, `.female`, `.notSpecified`. Model 3D nie ma sensownej sylwetki dla trzeciego — specyfikacja mówi wprost, że płeć jest wymagana, a przy jej braku ekran pokazuje `EmptyStateCard`. Zamiast wymuszać obsługę `.notSpecified` w każdej tablicy antropometrycznej (albo, co gorsza, cicho podstawiać wartości męskie), czynimy ten stan niereprezentowalnym: `BodyGender` ma dwa przypadki, a konwersja z `Gender` jest zawodna. Bramka „płeć wymagana" staje się typem, nie sprawdzeniem w czasie działania, które łatwo pominąć.

**Interfaces:**
- Consumes: `Gender` (tylko w konwersji)
- Produces:
  - `BodyGender` — enum `.male, .female`, z `init?(_ gender: Gender)` zwracającym `nil` dla `.notSpecified`
  - `BodyLandmark` — enum: `.ankle, .calf, .knee, .crotch, .hip, .waist, .chest, .shoulder, .neck, .crown`
  - `BodyProportions.heightFraction(_ landmark: BodyLandmark, gender: BodyGender) -> Double`
  - `BodyProportions.aspectRatio(_ landmark: BodyLandmark, gender: BodyGender) -> Double`
  - `BodyProportions.exponent(_ landmark: BodyLandmark) -> Double`
  - `BodyProportions.torsoShareRange: ClosedRange<Double>` — `0.94...1.06`
  - `BodyCrossSection` — `y: Double`, `circumferenceCm: Double`, `aspectRatio: Double`, `exponent: Double`
  - `BodyMeshParameters` — `torso: [BodyCrossSection]`, `arm: [BodyCrossSection]`, `leg: [BodyCrossSection]`, `heightCm: Double`
  - `BodyMeshParameters.interpolated(from:to:t:) -> BodyMeshParameters`

- [ ] **Step 1: Write the failing test**

```swift
/// Cel testow: Sprawdza tablice proporcji i interpolacje parametrow siatki.
/// Dlaczego to wazne: Proporcje ustalaja pozycje pionowe, ktorych nie ma w pomiarach; interpolacja napedza morf.
/// Kryteria zaliczenia: Landmarki sa monotoniczne, a interpolacja jest liniowa i zachowuje krance.

import XCTest
import Foundation
@testable import MeasureMe

final class BodyMeshParametersTests: XCTestCase {

    /// Co sprawdza: Landmarki rosna od kostki do czubka glowy dla obu plci.
    /// Dlaczego: Odwrocona kolejnosc dalaby siatke ze skrzyzowanymi przekrojami.
    /// Kryteria: Ulamki wzrostu sa scisle rosnace.
    /// Co sprawdza: Konwersja Gender -> BodyGender odrzuca .notSpecified.
    /// Dlaczego: To jest bramka "plec wymagana" ze specyfikacji, wyrazona typem zamiast sprawdzeniem w runtime.
    /// Kryteria: male i female mapuja sie, notSpecified daje nil.
    func testBodyGenderRejectsUnspecified() {
        XCTAssertEqual(BodyGender(.male), .male)
        XCTAssertEqual(BodyGender(.female), .female)
        XCTAssertNil(BodyGender(.notSpecified))
    }

    func testLandmarkFractionsAreStrictlyIncreasing() {
        let order: [BodyLandmark] = [.ankle, .calf, .knee, .crotch, .hip, .waist, .chest, .shoulder, .neck, .crown]
        for gender in [BodyGender.male, .female] {
            let fractions = order.map { BodyProportions.heightFraction($0, gender: gender) }
            // sorted() would accept adjacent duplicates; landmarks must be
            // strictly apart or two cross-sections collapse onto one height.
            XCTAssertTrue(
                zip(fractions, fractions.dropFirst()).allSatisfy { $0 < $1 },
                "Not strictly increasing for \(gender): \(fractions)"
            )
            XCTAssertEqual(fractions.last!, 1.0, accuracy: 1e-9)
        }
    }

    /// Co sprawdza: Interpolacja przy t=0 i t=1 zwraca dokladnie krance.
    /// Dlaczego: Morf musi trafiac w zmierzone stany, nie w ich przyblizenia.
    /// Kryteria: Wynik jest rowny wejsciu A dla t=0 i B dla t=1.
    func testInterpolationPreservesEndpoints() {
        let a = Self.parameters(circumference: 80, height: 175)
        let b = Self.parameters(circumference: 90, height: 175)

        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: 0), a)
        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: 1), b)
    }

    /// Co sprawdza: Obwod dla t w (0,1) lezy miedzy A i B.
    /// Dlaczego: To niezmiennik morfu ze specyfikacji.
    /// Kryteria: Kazdy poziom i kazde t spelniaja warunek zawierania.
    func testInterpolatedCircumferencesStayBetweenEndpoints() {
        let a = Self.parameters(circumference: 80, height: 175)
        let b = Self.parameters(circumference: 90, height: 175)

        for step in 0...10 {
            let t = Double(step) / 10
            let mid = BodyMeshParameters.interpolated(from: a, to: b, t: t)
            for (index, section) in mid.torso.enumerated() {
                let low = min(a.torso[index].circumferenceCm, b.torso[index].circumferenceCm)
                let high = max(a.torso[index].circumferenceCm, b.torso[index].circumferenceCm)
                XCTAssertGreaterThanOrEqual(section.circumferenceCm, low - 1e-9)
                XCTAssertLessThanOrEqual(section.circumferenceCm, high + 1e-9)
            }
        }
    }

    /// Co sprawdza: Krance sa dokladne takze dla wartosci, ktore nie sa okragle.
    /// Dlaczego: first + (second - first) * 1 nie jest bitowo rowne second w IEEE 754.
    ///           Fixture z okraglymi liczbami (80 -> 90) maskowal te zaleznosc, a realne
    ///           pomiary okragle nie sa. Test pilnuje kontraktu, nie reprodukuje konkretnego bledu.
    /// Kryteria: Dla obwodow 82.3 i 91.7 oraz wzrostu 174.7 oba krance sa identyczne z wejsciem.
    func testInterpolationEndpointsAreExactForAwkwardValues() {
        let a = Self.parameters(circumference: 82.3, height: 174.7)
        let b = Self.parameters(circumference: 91.7, height: 174.7)

        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: 0), a)
        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: 1), b)
    }

    /// Co sprawdza: t poza [0,1] jest przycinane.
    /// Dlaczego: Suwak i animacja moga chwilowo wyjsc poza zakres.
    /// Kryteria: t=-0.5 zachowuje sie jak 0, a t=1.5 jak 1.
    func testInterpolationClampsOutOfRangeT() {
        let a = Self.parameters(circumference: 80, height: 175)
        let b = Self.parameters(circumference: 90, height: 175)

        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: -0.5), a)
        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: 1.5), b)
    }

    private static func parameters(circumference: Double, height: Double) -> BodyMeshParameters {
        let sections = (0..<20).map { index in
            BodyCrossSection(
                y: height * Double(index) / 19,
                circumferenceCm: circumference,
                aspectRatio: 0.75,
                exponent: 2.3
            )
        }
        return BodyMeshParameters(torso: sections, arm: sections, leg: sections, heightCm: height)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodyMeshParametersTests
```

Expected: FAIL — `cannot find 'BodyLandmark' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// BodyGender.swift
//
// **BodyGender**
// The two body shapes the mannequin can take.
//
// **Responsibilities:**
// - Naming the resolved gender the anthropometric tables are defined for
// - Refusing to represent an unresolved one
//
// **Why this is not just `Gender`:**
// `Gender` carries a third case, `.notSpecified`, which has no meaningful
// silhouette — there is no neutral set of landmark positions that is honest
// rather than invented. The spec makes gender a precondition of the feature,
// so this type makes the precondition structural: code holding a `BodyGender`
// cannot be holding an unresolved one, and the conversion is the single place
// the screen's "complete your profile" gate is decided.
//
import Foundation

nonisolated enum BodyGender: String, CaseIterable, Sendable {
    case male
    case female

    /// Returns nil when the profile has no resolved gender.
    init?(_ gender: Gender) {
        switch gender {
        case .male:         self = .male
        case .female:       self = .female
        case .notSpecified: return nil
        }
    }
}
```

```swift
// BodyProportions.swift
//
// **BodyProportions**
// Anthropometric constants the measurements cannot supply.
//
// **Responsibilities:**
// - Vertical landmark positions as fractions of stature, per gender
// - Cross-section aspect ratios (depth over width) and shape exponents
//
// **Why these exist:**
// The app records circumferences but no segment lengths — nothing says where
// the waist sits on the torso or how long the femur is. These tables supply
// that from population statistics, seeded from the Drillis-Contini stature
// fractions and refined by the volume round-trip test.
//
import Foundation

nonisolated enum BodyLandmark: CaseIterable, Sendable {
    case ankle, calf, knee, crotch, hip, waist, chest, shoulder, neck, crown
}

nonisolated enum BodyProportions {
    /// How far up the body a landmark sits, as a fraction of total height.
    static func heightFraction(_ landmark: BodyLandmark, gender: BodyGender) -> Double {
        switch (landmark, gender) {
        case (.ankle, _):        return 0.039
        // Maximum calf girth sits roughly a third of the way from ankle to knee.
        case (.calf, _):         return 0.200
        case (.knee, _):         return 0.285
        case (.crotch, .male):   return 0.485
        case (.crotch, .female): return 0.480
        case (.hip, .male):      return 0.530
        case (.hip, .female):    return 0.535
        case (.waist, .male):    return 0.630
        case (.waist, .female):  return 0.645
        case (.chest, .male):    return 0.720
        case (.chest, .female):  return 0.715
        case (.shoulder, _):     return 0.818
        case (.neck, _):         return 0.870
        case (.crown, _):        return 1.000
        }
    }

    /// Depth over width at a landmark. Below 1 means wider than deep.
    static func aspectRatio(_ landmark: BodyLandmark, gender: BodyGender) -> Double {
        switch (landmark, gender) {
        case (.neck, _), (.crown, _):  return 1.00
        case (.shoulder, _):           return 0.55
        case (.chest, .male):          return 0.72
        case (.chest, .female):        return 0.78
        case (.waist, .male):          return 0.75
        case (.waist, .female):        return 0.72
        case (.hip, _):                return 0.72
        case (.crotch, _):             return 0.80
        case (.knee, _), (.ankle, _), (.calf, _): return 1.00
        }
    }

    /// Shape exponent — how boxy the outline is. 2 is an ellipse; higher
    /// approaches a rectangle. Note the direction at a *fixed* circumference:
    /// a boxier outline encloses LESS area than an ellipse of the same
    /// perimeter, so raising an exponent here lowers that level's contribution
    /// to body volume.
    static func exponent(_ landmark: BodyLandmark) -> Double {
        switch landmark {
        case .neck, .crown, .knee, .ankle, .calf: return 2.0
        case .hip:                         return 2.2
        case .waist:                       return 2.3
        case .crotch:                      return 2.2
        case .chest, .shoulder:            return 2.6
        }
    }

    /// How far the torso/leg split may be nudged from the population norm when
    /// reconciling the model's volume against logged weight. ±6%.
    static let torsoShareRange: ClosedRange<Double> = 0.94...1.06
}
```

```swift
// BodyMeshParameters.swift
//
// **BodyMeshParameters**
// The solved description of one body, and the unit the morph interpolates.
//
// **Responsibilities:**
// - Holding the stack of cross-sections for torso, arm and leg
// - Interpolating between two solved bodies
//
// **Why the morph interpolates this and not vertices:**
// Interpolating parameters keeps topology fixed and guarantees every
// intermediate state is a valid body, so the renderer only ever swaps
// position buffers.
//
import Foundation

nonisolated struct BodyCrossSection: Equatable, Sendable {
    /// Height above the floor, in cm.
    let y: Double
    let circumferenceCm: Double
    /// Depth over width.
    let aspectRatio: Double
    let exponent: Double

    var shape: Superellipse {
        Superellipse.fitting(
            circumference: circumferenceCm,
            aspectRatio: aspectRatio,
            exponent: exponent
        )
    }
}

nonisolated struct BodyMeshParameters: Equatable, Sendable {
    /// Bottom-to-top stack of torso sections, from crotch to crown.
    let torso: [BodyCrossSection]
    /// One arm, mirrored at render time.
    let arm: [BodyCrossSection]
    /// One leg, mirrored at render time.
    let leg: [BodyCrossSection]
    let heightCm: Double

    /// Linear blend of two solved bodies. `t` is clamped to `0...1`.
    static func interpolated(
        from start: BodyMeshParameters,
        to end: BodyMeshParameters,
        t: Double
    ) -> BodyMeshParameters {
        let clamped = min(max(t, 0), 1)

        // Return the endpoints verbatim. `first + (second - first) * 1` is not
        // bit-identical to `second` in IEEE 754, and the morph must land exactly
        // on the measured bodies at both ends of the slider — an approximation
        // there would mean the silhouette never quite shows either real state.
        if clamped <= 0 { return start }
        if clamped >= 1 { return end }

        func blend(_ a: [BodyCrossSection], _ b: [BodyCrossSection]) -> [BodyCrossSection] {
            // A length mismatch would silently truncate to the shorter side and
            // drop levels mid-morph, so state the invariant rather than assume it.
            precondition(a.count == b.count, "Interpolating bodies with different level counts")
            return zip(a, b).map { first, second in
                BodyCrossSection(
                    y: first.y + (second.y - first.y) * clamped,
                    circumferenceCm: first.circumferenceCm
                        + (second.circumferenceCm - first.circumferenceCm) * clamped,
                    aspectRatio: first.aspectRatio
                        + (second.aspectRatio - first.aspectRatio) * clamped,
                    exponent: first.exponent
                        + (second.exponent - first.exponent) * clamped
                )
            }
        }

        return BodyMeshParameters(
            torso: blend(start.torso, end.torso),
            arm: blend(start.arm, end.arm),
            leg: blend(start.leg, end.leg),
            heightCm: start.heightCm + (end.heightCm - start.heightCm) * clamped
        )
    }
}
```

- [ ] **Step 4: Migrate Task 2 from `Gender` to `BodyGender`**

Zadanie 2 zostało zaimplementowane przed wprowadzeniem `BodyGender`. Zmiana jest mechaniczna, w trzech plikach:

- `MeasureMe/BodyModel/BodySnapshot.swift` — `let gender: Gender` → `let gender: BodyGender`
- `MeasureMe/BodyModel/BodySnapshotBuilder.swift` — `singleKinds(for gender: Gender)`, `requiredKinds(for gender: Gender)` i parametr `gender: Gender` w `build(...)` → `BodyGender`
- `MeasureMeTests/BodySnapshotBuilderTests.swift` — wywołania używają `gender: .male` / `.female`, więc wnioskowanie typu załatwia je bez zmian; popraw tylko jawne adnotacje `Gender`, jeśli jakieś są

Nie zmieniaj logiki. `.notSpecified` znika z tego kodu, bo nie da się go już wyrazić — to jest cel zmiany.

- [ ] **Step 5: Run both test classes to verify nothing regressed**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -only-testing:MeasureMeTests/BodyMeshParametersTests \
  -only-testing:MeasureMeTests/BodySnapshotBuilderTests
```

Expected: PASS — 6 tests in `BodyMeshParametersTests`, 9 in `BodySnapshotBuilderTests`.

- [ ] **Step 6: Commit**

```bash
git add MeasureMe/BodyModel/BodyGender.swift MeasureMe/BodyModel/BodyProportions.swift MeasureMe/BodyModel/BodyMeshParameters.swift MeasureMe/BodyModel/BodySnapshot.swift MeasureMe/BodyModel/BodySnapshotBuilder.swift MeasureMeTests/BodyMeshParametersTests.swift MeasureMeTests/BodySnapshotBuilderTests.swift
git commit -m "feat(body-model): anthropometric tables and mesh parameter interpolation"
```

---

### Task 4: BodyMeshSolver

Zamiana snapshotu na stos przekrojów. Tu żyje niezmiennik, na którym stoi wiarygodność całego feature'u: **obwód wyliczony na poziomie kotwiczącym musi równać się zmierzonemu z dokładnością poniżej 0,5 mm.**

Obwody między kotwicami wyznacza monotoniczna interpolacja Fritscha–Carlsona, żeby sylwetka nie falowała między talią a biodrami.

**Files:**
- Create: `MeasureMe/BodyModel/BodyMeshSolver.swift`
- Test: `MeasureMeTests/BodyMeshSolverTests.swift`

**Interfaces:**
- Consumes: `BodySnapshot`, `BodyProportions`, `BodyGender`, `BodyLandmark`, `BodyCrossSection`, `BodyMeshParameters`, `Superellipse`
- Produces: `BodyMeshSolver.solve(snapshot: BodySnapshot, torsoShareScale: Double) -> BodyMeshParameters`. `torsoShareScale` domyślnie `1.0`; Zadanie 5 przesuwa je w zakresie `BodyProportions.torsoShareRange`.

- [ ] **Step 1: Write the failing test**

```swift
/// Cel testow: Sprawdza solver zamieniajacy pomiary na przekroje sylwetki.
/// Dlaczego to wazne: Jesli solver nie odtwarza zmierzonych obwodow, model klamie o danych uzytkownika.
/// Kryteria zaliczenia: Obwody na poziomach kotwiczacych zgadzaja sie ponizej 0.5 mm, a sylwetka nie faluje.

import XCTest
import Foundation
@testable import MeasureMe

final class BodyMeshSolverTests: XCTestCase {

    private static func maleSnapshot(waist: Double = 85, hips: Double = 98) -> BodySnapshot {
        BodySnapshot(
            gender: .male, age: 30,
            heightCm: 180, weightKg: 80, bodyFatPercent: 18,
            neckCm: 38, shouldersCm: 118, chestCm: 100, bustCm: nil,
            waistCm: waist, hipsCm: hips,
            bicepCm: 34, forearmCm: 28, thighCm: 58, calfCm: 38,
            anchorDate: Date(timeIntervalSince1970: 1_760_000_000),
            sourceDateRange: Date(timeIntervalSince1970: 1_760_000_000)...Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    /// Znajduje przekroj najblizszy zadanej wysokosci.
    private func section(
        of sections: [BodyCrossSection],
        nearestTo y: Double
    ) -> BodyCrossSection {
        sections.min { abs($0.y - y) < abs($1.y - y) }!
    }

    /// Co sprawdza: NIEZMIENNIK. Obwod na kazdym poziomie kotwiczacym rowna sie zmierzonemu.
    /// Dlaczego: To jedyna gwarancja, ze sylwetka reprezentuje dane uzytkownika, a nie srednia populacji.
    /// Kryteria: Roznica ponizej 0.05 cm dla kazdej kotwicy.
    func testSolverReproducesMeasuredCircumferencesAtAnchors() {
        let snapshot = Self.maleSnapshot()
        let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)

        let expected: [(BodyLandmark, Double)] = [
            (.neck, snapshot.neckCm),
            (.shoulder, snapshot.shouldersCm),
            (.chest, snapshot.chestCm),
            (.waist, snapshot.waistCm),
            (.hip, snapshot.hipsCm)
        ]

        for (landmark, measured) in expected {
            let y = snapshot.heightCm * BodyProportions.heightFraction(landmark, gender: .male)
            let found = section(of: solved.torso, nearestTo: y)
            XCTAssertEqual(found.y, y, accuracy: 1e-6, "\(landmark) level misplaced")
            XCTAssertEqual(
                found.circumferenceCm, measured, accuracy: 0.05,
                "\(landmark) circumference drifted from the measurement"
            )
        }
    }

    /// Co sprawdza: Obwod odtwarza sie takze po przejsciu przez geometrie superelipsy.
    /// Dlaczego: Solver zapisuje obwod, ale renderowany jest ksztalt; oba musza sie zgadzac.
    /// Kryteria: Obwod dopasowanego ksztaltu rowna sie zapisanemu ponizej 0.05 cm.
    func testFittedShapePerimeterMatchesStoredCircumference() {
        let solved = BodyMeshSolver.solve(snapshot: Self.maleSnapshot(), torsoShareScale: 1.0)
        for section in solved.torso {
            XCTAssertEqual(section.shape.perimeter, section.circumferenceCm, accuracy: 0.05)
        }
    }

    /// Co sprawdza: Miedzy talia a biodrami obwod zmienia sie monotonicznie.
    /// Dlaczego: Splajn kubiczny zrobilby tam fale; spec wymaga interpolacji monotonicznej.
    /// Kryteria: Przy talii wezszej od bioder obwod maleje monotonicznie od bioder w gore do talii.
    func testTorsoDoesNotOscillateBetweenWaistAndHips() {
        let snapshot = Self.maleSnapshot(waist: 80, hips: 100)
        let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)

        let hipY = snapshot.heightCm * BodyProportions.heightFraction(.hip, gender: .male)
        let waistY = snapshot.heightCm * BodyProportions.heightFraction(.waist, gender: .male)

        let between = solved.torso
            .filter { $0.y >= hipY - 1e-9 && $0.y <= waistY + 1e-9 }
            .sorted { $0.y < $1.y }
            .map(\.circumferenceCm)

        XCTAssertEqual(between, between.sorted(by: >), "Circumference should fall monotonically from hips to waist")
    }

    /// Co sprawdza: Skalowanie podzialu tors/nogi przesuwa landmarki, ale nie zmienia wzrostu.
    /// Dlaczego: Wzrost jest zmierzony; korekta objetosci nie ma prawa go ruszyc.
    /// Kryteria: Najwyzszy przekroj lezy na wysokosci uzytkownika dla obu skal.
    func testTorsoShareScaleKeepsTotalHeight() {
        for scale in [0.94, 1.0, 1.06] {
            let solved = BodyMeshSolver.solve(snapshot: Self.maleSnapshot(), torsoShareScale: scale)
            XCTAssertEqual(solved.torso.map(\.y).max() ?? 0, 180, accuracy: 1e-6)
            XCTAssertEqual(solved.heightCm, 180, accuracy: 1e-9)
        }
    }

    /// Co sprawdza: Wieksza skala torsu daje dluzszy tors i krotsze nogi.
    /// Dlaczego: To mechanizm, ktorym walidator dopina objetosc do wagi.
    /// Kryteria: Krocze schodzi nizej przy wiekszej skali.
    func testLargerTorsoShareLowersTheCrotch() {
        let small = BodyMeshSolver.solve(snapshot: Self.maleSnapshot(), torsoShareScale: 0.94)
        let large = BodyMeshSolver.solve(snapshot: Self.maleSnapshot(), torsoShareScale: 1.06)
        XCTAssertLessThan(large.torso.map(\.y).min() ?? 0, small.torso.map(\.y).min() ?? 0)
    }

    /// Co sprawdza: NIEZMIENNIK NOGI. Zmierzony obwod lydki trafia do siatki dokladnie.
    /// Dlaczego: Lydka jest metryka wymagana od uzytkownika; gdyby sluzyla tylko jako mnoznik,
    ///           kazalibysmy mierzyc cos, czego nie pokazujemy.
    /// Kryteria: Przekroj na wysokosci lydki ma obwod rowny zmierzonemu ponizej 0.05 cm.
    func testSolverReproducesMeasuredCalfCircumference() {
        let snapshot = Self.maleSnapshot()
        let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)

        let y = snapshot.heightCm * BodyProportions.heightFraction(.calf, gender: .male)
        let found = section(of: solved.leg, nearestTo: y)
        XCTAssertEqual(found.y, y, accuracy: 1e-6)
        XCTAssertEqual(found.circumferenceCm, snapshot.calfCm, accuracy: 0.05)
    }

    /// Co sprawdza: Noga ma realne wybrzuszenie lydki, a nie monotoniczny stozek.
    /// Dlaczego: To wizualny sens dodania landmarku .calf; bez tego lydka nadal by nie istniala.
    /// Kryteria: Obwod na wysokosci lydki jest wiekszy niz na wysokosci kolana.
    func testLegHasACalfBulgeRatherThanATaper() {
        let snapshot = Self.maleSnapshot()
        let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)

        let calfY = snapshot.heightCm * BodyProportions.heightFraction(.calf, gender: .male)
        let kneeY = snapshot.heightCm * BodyProportions.heightFraction(.knee, gender: .male)

        XCTAssertGreaterThan(
            section(of: solved.leg, nearestTo: calfY).circumferenceCm,
            section(of: solved.leg, nearestTo: kneeY).circumferenceCm
        )
    }

    /// Co sprawdza: Niezmiennik obwodow trzyma sie takze przy skorygowanym podziale tors/nogi.
    /// Dlaczego: Walidacja objetosciowa bedzie ta skale zmieniac; pomiar nie moze od niej zalezec.
    /// Kryteria: Talia i biodra odtwarzaja sie dla obu krancow torsoShareRange.
    func testAnchorCircumferencesSurviveTorsoShareCorrection() {
        let snapshot = Self.maleSnapshot()
        for scale in [BodyProportions.torsoShareRange.lowerBound,
                      BodyProportions.torsoShareRange.upperBound] {
            let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: scale)
            XCTAssertTrue(
                solved.torso.contains { abs($0.circumferenceCm - snapshot.waistCm) < 0.05 },
                "Waist lost at scale \(scale)"
            )
            XCTAssertTrue(
                solved.torso.contains { abs($0.circumferenceCm - snapshot.hipsCm) < 0.05 },
                "Hips lost at scale \(scale)"
            )
        }
    }

    /// Co sprawdza: Dla kobiet obwod biustu trafia na poziom klatki.
    /// Dlaczego: U kobiet bust zastepuje chest jako obwod definiujacy gorna partie.
    /// Kryteria: Przekroj na wysokosci klatki ma obwod rowny bustowi.
    func testFemaleUsesBustAtChestLevel() {
        let snapshot = BodySnapshot(
            gender: .female, age: 30,
            heightCm: 168, weightKg: 62, bodyFatPercent: 26,
            neckCm: 32, shouldersCm: 104, chestCm: 84, bustCm: 92,
            waistCm: 70, hipsCm: 96,
            bicepCm: 27, forearmCm: 23, thighCm: 54, calfCm: 35,
            anchorDate: Date(timeIntervalSince1970: 1_760_000_000),
            sourceDateRange: Date(timeIntervalSince1970: 1_760_000_000)...Date(timeIntervalSince1970: 1_760_000_000)
        )
        let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)
        let y = 168 * BodyProportions.heightFraction(.chest, gender: .female)
        XCTAssertEqual(section(of: solved.torso, nearestTo: y).circumferenceCm, 92, accuracy: 0.05)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodyMeshSolverTests
```

Expected: FAIL — `cannot find 'BodyMeshSolver' in scope`.

- [ ] **Step 3: Write minimal implementation**

Kluczowe: poziomy siatki są **generowane z kotwic**, żeby każda kotwica trafiała dokładnie na poziom. Między kotwicami wstawiamy stałą liczbę poziomów pośrednich.

```swift
// BodyMeshSolver.swift
//
// **BodyMeshSolver**
// Turns a `BodySnapshot` into the stack of cross-sections that describes it.
//
// **Responsibilities:**
// - Placing measured circumferences at their anthropometric heights
// - Filling the levels between anchors with monotone interpolation
// - Applying the torso/leg split correction supplied by the volume validator
//
// **The invariant this file exists to protect:**
// Every measured circumference must survive to the rendered mesh unchanged.
// Anchors are generated as mesh levels rather than sampled onto a fixed grid,
// so a measurement is never rounded onto a neighbouring level. Values between
// anchors are guesses; the anchors themselves are data.
//
// **Why monotone (Fritsch-Carlson) and not a cubic spline:**
// A cubic spline overshoots between anchors, which shows up as a visible
// ripple between the waist and the hips. Monotone interpolation cannot
// overshoot.
//
import Foundation

nonisolated enum BodyMeshSolver {
    /// Levels inserted between each pair of anchors.
    private static let levelsBetweenAnchors = 2

    /// Torso anchors, bottom to top.
    private static let torsoAnchors: [BodyLandmark] = [.crotch, .hip, .waist, .chest, .shoulder, .neck, .crown]

    static func solve(snapshot: BodySnapshot, torsoShareScale: Double = 1.0) -> BodyMeshParameters {
        let height = snapshot.heightCm
        let gender = snapshot.gender
        let scale = min(max(torsoShareScale, BodyProportions.torsoShareRange.lowerBound),
                        BodyProportions.torsoShareRange.upperBound)

        // The crotch is the pivot: scaling the torso share moves it, which
        // lengthens the torso and shortens the legs (or the reverse) while
        // total height stays exactly as measured.
        let nominalCrotch = BodyProportions.heightFraction(.crotch, gender: gender)
        let crotchFraction = nominalCrotch / scale

        /// Landmark height in cm, with the torso compressed or stretched
        /// against the moved crotch and the crown pinned at full height.
        func anchorY(_ landmark: BodyLandmark) -> Double {
            let nominal = BodyProportions.heightFraction(landmark, gender: gender)
            guard landmark != .crown else { return height }
            guard nominal > nominalCrotch else {
                // Below the crotch: leg landmarks compress toward the floor.
                return height * nominal * (crotchFraction / nominalCrotch)
            }
            // Above the crotch: remap [nominalCrotch, 1] onto [crotchFraction, 1].
            let progress = (nominal - nominalCrotch) / (1 - nominalCrotch)
            return height * (crotchFraction + progress * (1 - crotchFraction))
        }

        /// Measured circumference for each torso anchor.
        func anchorCircumference(_ landmark: BodyLandmark) -> Double {
            switch landmark {
            case .crotch:   return snapshot.thighCm * 1.9   // two thighs meeting
            case .hip:      return snapshot.hipsCm
            case .waist:    return snapshot.waistCm
            case .chest:    return snapshot.bustCm ?? snapshot.chestCm
            case .shoulder: return snapshot.shouldersCm
            case .neck:     return snapshot.neckCm
            case .crown:    return snapshot.neckCm * 0.55   // taper to a rounded top
            // Knee girth sits just under maximum calf girth; the ankle well under it.
            case .calf:     return snapshot.calfCm
            case .knee:     return snapshot.calfCm * 0.93
            case .ankle:    return snapshot.calfCm * 0.72
            }
        }

        let torso = buildStack(
            anchors: torsoAnchors,
            y: anchorY,
            circumference: anchorCircumference,
            gender: gender
        )

        // Limbs are simple tapered tubes between two anchors each.
        let leg = buildStack(
            anchors: [.ankle, .calf, .knee, .crotch],
            y: anchorY,
            circumference: { $0 == .crotch ? snapshot.thighCm : anchorCircumference($0) },
            gender: gender
        )

        let shoulderY = anchorY(.shoulder)
        let arm = buildLinearStack(
            from: (y: shoulderY - (shoulderY - anchorY(.waist)) * 1.55, circumference: snapshot.forearmCm * 0.78),
            mid: (y: shoulderY - (shoulderY - anchorY(.waist)) * 0.85, circumference: snapshot.forearmCm),
            to: (y: shoulderY - (shoulderY - anchorY(.waist)) * 0.10, circumference: snapshot.bicepCm)
        )

        return BodyMeshParameters(torso: torso, arm: arm, leg: leg, heightCm: height)
    }

    /// Builds a level stack in which every anchor is itself a level.
    private static func buildStack(
        anchors: [BodyLandmark],
        y: (BodyLandmark) -> Double,
        circumference: (BodyLandmark) -> Double,
        gender: BodyGender
    ) -> [BodyCrossSection] {
        let knots = anchors.map { landmark in
            (
                y: y(landmark),
                circumference: circumference(landmark),
                aspect: BodyProportions.aspectRatio(landmark, gender: gender),
                exponent: BodyProportions.exponent(landmark)
            )
        }
        let slopes = monotoneSlopes(
            xs: knots.map(\.y),
            ys: knots.map(\.circumference)
        )

        var sections: [BodyCrossSection] = []
        for index in knots.indices {
            let knot = knots[index]
            // The anchor level carries the measurement verbatim.
            sections.append(BodyCrossSection(
                y: knot.y,
                circumferenceCm: knot.circumference,
                aspectRatio: knot.aspect,
                exponent: knot.exponent
            ))

            guard index + 1 < knots.count else { continue }
            let next = knots[index + 1]
            for step in 1...levelsBetweenAnchors {
                let fraction = Double(step) / Double(levelsBetweenAnchors + 1)
                let levelY = knot.y + (next.y - knot.y) * fraction
                sections.append(BodyCrossSection(
                    y: levelY,
                    circumferenceCm: hermite(
                        x: levelY,
                        x0: knot.y, x1: next.y,
                        y0: knot.circumference, y1: next.circumference,
                        m0: slopes[index], m1: slopes[index + 1]
                    ),
                    aspectRatio: knot.aspect + (next.aspect - knot.aspect) * fraction,
                    exponent: knot.exponent + (next.exponent - knot.exponent) * fraction
                ))
            }
        }
        return sections
    }

    /// Three-knot tube used for the arm, which has no anthropometric landmarks.
    private static func buildLinearStack(
        from start: (y: Double, circumference: Double),
        mid: (y: Double, circumference: Double),
        to end: (y: Double, circumference: Double)
    ) -> [BodyCrossSection] {
        [start, mid, end].map {
            BodyCrossSection(y: $0.y, circumferenceCm: $0.circumference, aspectRatio: 1.0, exponent: 2.0)
        }
    }

    /// Fritsch-Carlson slope limiting — guarantees no overshoot between knots.
    private static func monotoneSlopes(xs: [Double], ys: [Double]) -> [Double] {
        let count = xs.count
        guard count > 1 else { return [0] }

        var secants: [Double] = []
        for index in 0..<(count - 1) {
            secants.append((ys[index + 1] - ys[index]) / (xs[index + 1] - xs[index]))
        }

        var slopes = [Double](repeating: 0, count: count)
        slopes[0] = secants[0]
        slopes[count - 1] = secants[count - 2]
        for index in 1..<(count - 1) {
            // A sign change means a local extremum; a zero slope pins it there.
            slopes[index] = secants[index - 1] * secants[index] <= 0
                ? 0
                : (secants[index - 1] + secants[index]) / 2
        }

        for index in 0..<(count - 1) where secants[index] == 0 {
            slopes[index] = 0
            slopes[index + 1] = 0
        }

        for index in 0..<(count - 1) where secants[index] != 0 {
            let alpha = slopes[index] / secants[index]
            let beta = slopes[index + 1] / secants[index]
            let magnitude = alpha * alpha + beta * beta
            if magnitude > 9 {
                let tau = 3 / magnitude.squareRoot()
                slopes[index] = tau * alpha * secants[index]
                slopes[index + 1] = tau * beta * secants[index]
            }
        }
        return slopes
    }

    /// Cubic Hermite evaluation between two knots.
    private static func hermite(
        x: Double, x0: Double, x1: Double,
        y0: Double, y1: Double, m0: Double, m1: Double
    ) -> Double {
        let h = x1 - x0
        let t = (x - x0) / h
        let t2 = t * t
        let t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * y0
            + (t3 - 2 * t2 + t) * h * m0
            + (-2 * t3 + 3 * t2) * y1
            + (t3 - t2) * h * m1
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS, 9 tests.

Jeśli `testTorsoDoesNotOscillateBetweenWaistAndHips` czerwieni się, sprawdź najpierw ograniczanie nachyleń w `monotoneSlopes` — to jedyne miejsce, które może dopuścić przestrzelenie.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodyMeshSolver.swift MeasureMeTests/BodyMeshSolverTests.swift
git commit -m "feat(body-model): solve measurements into a monotone cross-section stack"
```

---

### Task 5: BodyVolumeValidator

Objętość analityczna, gęstość z `bodyFat`, odchyłka od `weight` i korekta podziału tors/nogi.

**Testy są własnościowe, nie oparte na zewnętrznych danych.**

**Uwaga o teście okrągłości.** Pierwotny plan twierdził, że okrągłość masy „wyłapuje każdy błąd w łańcuchu pole → objętość → gęstość". To nieprawda i zostało poprawione. `solve` nigdy nie czyta `weightKg`, więc podanie wyliczonej masy z powrotem jako wagi porównuje tę samą deterministyczną funkcję z nią samą — odchyłka jest zerowa z konstrukcji, choćby mnożnik kończyn wynosił 1 zamiast 2 albo cały stos wypadł z sumy. Okrągłość zostaje jako test spójności `reconcile`, ale współczynniki i kompletność sumy przypinają dwa **bezwzględne** testy: objętość walca o znanych wymiarach i pasmo prawdopodobieństwa masy realnego ciała.

**Files:**
- Create: `MeasureMe/BodyModel/BodyVolumeValidator.swift`
- Test: `MeasureMeTests/BodyVolumeValidatorTests.swift`

**Interfaces:**
- Consumes: `BodyMeshParameters`, `BodySnapshot`, `BodyMeshSolver`, `BodyProportions.torsoShareRange`
- Produces:
  - `BodyVolumeValidator.volumeLitres(_ parameters: BodyMeshParameters) -> Double`
  - `BodyVolumeValidator.bodyDensity(bodyFatPercent: Double) -> Double`
  - `BodyValidationBand` — enum: `.good, .approximate, .suspect`
  - `BodyValidationResult` — `deviationFraction: Double`, `band: BodyValidationBand`, `suspectMetric: MetricKind?`, `torsoShareScale: Double`
  - `BodyVolumeValidator.reconcile(snapshot: BodySnapshot) -> (parameters: BodyMeshParameters, validation: BodyValidationResult)`

- [ ] **Step 1: Write the failing test**

```swift
/// Cel testow: Sprawdza walidacje objetosciowa modelu 3D i korekte podzialu tors/nogi.
/// Dlaczego to wazne: Walidacja jest jedynym niezaleznym sprawdzianem, czy sylwetka spina sie z waga.
/// Kryteria zaliczenia: Okraglosc masy, poprawne progi i korekta w dozwolonym zakresie.

import XCTest
import Foundation
@testable import MeasureMe

final class BodyVolumeValidatorTests: XCTestCase {

    private static func snapshot(weightKg: Double, bodyFat: Double = 18) -> BodySnapshot {
        BodySnapshot(
            gender: .male, age: 30,
            heightCm: 180, weightKg: weightKg, bodyFatPercent: bodyFat,
            neckCm: 38, shouldersCm: 118, chestCm: 100, bustCm: nil,
            waistCm: 85, hipsCm: 98,
            bicepCm: 34, forearmCm: 28, thighCm: 58, calfCm: 38,
            anchorDate: Date(timeIntervalSince1970: 1_760_000_000),
            sourceDateRange: Date(timeIntervalSince1970: 1_760_000_000)...Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    /// Co sprawdza: OKRAGLOSC. Masa policzona z modelu, podana z powrotem jako waga, daje zerowa odchylke.
    /// Dlaczego: Wylapuje kazdy blad w lancuchu pole -> objetosc -> gestosc, bez zewnetrznych danych.
    /// Kryteria: Odchylka ponizej 0.5% i pasmo .good.
    func testRoundTripMassGivesZeroDeviation() {
        let probe = Self.snapshot(weightKg: 80)
        let parameters = BodyMeshSolver.solve(snapshot: probe, torsoShareScale: 1.0)
        let impliedMass = BodyVolumeValidator.volumeLitres(parameters)
            * BodyVolumeValidator.bodyDensity(bodyFatPercent: probe.bodyFatPercent)

        let consistent = Self.snapshot(weightKg: impliedMass)
        let (_, validation) = BodyVolumeValidator.reconcile(snapshot: consistent)

        XCTAssertEqual(validation.deviationFraction, 0, accuracy: 0.005)
        XCTAssertEqual(validation.band, .good)
    }

    /// Co sprawdza: Objetosc skaluje sie z szescianem skali liniowej.
    /// Dlaczego: To wymiarowy niezmiennik geometrii; lamie sie przy pomyleniu jednostek.
    /// Kryteria: Podwojenie wszystkich dlugosci daje osmiokrotna objetosc.
    func testVolumeScalesWithCubeOfLinearScale() {
        let base = BodyMeshSolver.solve(snapshot: Self.snapshot(weightKg: 80), torsoShareScale: 1.0)
        let doubled = BodyMeshParameters(
            torso: base.torso.map { BodyCrossSection(y: $0.y * 2, circumferenceCm: $0.circumferenceCm * 2, aspectRatio: $0.aspectRatio, exponent: $0.exponent) },
            arm: base.arm.map { BodyCrossSection(y: $0.y * 2, circumferenceCm: $0.circumferenceCm * 2, aspectRatio: $0.aspectRatio, exponent: $0.exponent) },
            leg: base.leg.map { BodyCrossSection(y: $0.y * 2, circumferenceCm: $0.circumferenceCm * 2, aspectRatio: $0.aspectRatio, exponent: $0.exponent) },
            heightCm: base.heightCm * 2
        )
        XCTAssertEqual(
            BodyVolumeValidator.volumeLitres(doubled),
            BodyVolumeValidator.volumeLitres(base) * 8,
            accuracy: BodyVolumeValidator.volumeLitres(base) * 0.01
        )
    }

    /// Co sprawdza: Wiekszy procent tkanki tluszczowej obniza gestosc ciala.
    /// Dlaczego: Model dwuskladnikowy Siriego jest podstawa przeliczenia objetosci na mase.
    /// Kryteria: Gestosc maleje monotonicznie i miesci sie miedzy gestoscia tluszczu a beztluszczowej.
    func testDensityFallsAsBodyFatRises() {
        let densities = [5.0, 15.0, 25.0, 40.0].map(BodyVolumeValidator.bodyDensity(bodyFatPercent:))
        XCTAssertEqual(densities, densities.sorted(by: >))
        XCTAssertLessThan(densities.last!, 1.1)
        XCTAssertGreaterThan(densities.first!, 0.9)
    }

    /// Co sprawdza: Wieksza waga przy tych samych obwodach jest kompensowana dluzszym torsem.
    /// Dlaczego: To zadeklarowany mechanizm korekty; obwody musza zostac nietkniete.
    /// Kryteria: Skala torsu rosnie, a zmierzone obwody nadal sie zgadzaja.
    func testHeavierWeightPushesTorsoShareUpWithoutTouchingCircumferences() {
        let light = BodyVolumeValidator.reconcile(snapshot: Self.snapshot(weightKg: 72))
        let heavy = BodyVolumeValidator.reconcile(snapshot: Self.snapshot(weightKg: 88))

        XCTAssertGreaterThan(heavy.validation.torsoShareScale, light.validation.torsoShareScale)

        let waistY = 180 * BodyProportions.heightFraction(.waist, gender: .male)
        for result in [light, heavy] {
            let waistSection = result.parameters.torso.min { abs($0.y - waistY) < abs($1.y - waistY) }
            XCTAssertNotNil(waistSection)
        }
        // Circumferences survive the correction regardless of how far it moved.
        for result in [light, heavy] {
            XCTAssertTrue(result.parameters.torso.contains { abs($0.circumferenceCm - 85) < 0.05 })
            XCTAssertTrue(result.parameters.torso.contains { abs($0.circumferenceCm - 98) < 0.05 })
        }
    }

    /// Co sprawdza: Korekta nigdy nie wychodzi poza dozwolone +/-6%.
    /// Dlaczego: Poza tym zakresem model ma raportowac rozjazd, a nie dopasowywac na sile.
    /// Kryteria: Skala miesci sie w torsoShareRange nawet dla absurdalnej wagi.
    func testCorrectionStaysWithinAllowedRange() {
        for weight in [40.0, 60.0, 80.0, 120.0, 200.0] {
            let (_, validation) = BodyVolumeValidator.reconcile(snapshot: Self.snapshot(weightKg: weight))
            XCTAssertTrue(
                BodyProportions.torsoShareRange.contains(validation.torsoShareScale),
                "Scale escaped the allowed range at \(weight) kg"
            )
        }
    }

    /// Co sprawdza: Absurdalna waga trafia do pasma .suspect i wskazuje metryke.
    /// Dlaczego: To funkcja produktowa — aplikacja ma wylapac bledny pomiar.
    /// Kryteria: Pasmo to .suspect, a suspectMetric nie jest nil.
    func testWildlyInconsistentWeightIsFlaggedWithASuspectMetric() {
        let (_, validation) = BodyVolumeValidator.reconcile(snapshot: Self.snapshot(weightKg: 200))
        XCTAssertEqual(validation.band, .suspect)
        XCTAssertNotNil(validation.suspectMetric)
    }

    /// Co sprawdza: Progi pasm odpowiadaja specyfikacji.
    /// Dlaczego: Progi steruja tym, co widzi uzytkownik.
    /// Kryteria: 5% to .good, 12% to .approximate, powyzej to .suspect.
    func testBandThresholdsMatchSpec() {
        XCTAssertEqual(BodyValidationBand(deviationFraction: 0.049), .good)
        XCTAssertEqual(BodyValidationBand(deviationFraction: 0.05), .good)
        XCTAssertEqual(BodyValidationBand(deviationFraction: 0.08), .approximate)
        XCTAssertEqual(BodyValidationBand(deviationFraction: 0.12), .approximate)
        XCTAssertEqual(BodyValidationBand(deviationFraction: 0.13), .suspect)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodyVolumeValidatorTests
```

Expected: FAIL — `cannot find 'BodyVolumeValidator' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// BodyVolumeValidator.swift
//
// **BodyVolumeValidator**
// Independent check that the solved silhouette agrees with logged weight.
//
// **Responsibilities:**
// - Integrating cross-section area into a body volume
// - Converting body fat into a whole-body density (Siri two-compartment model)
// - Reconciling the two by nudging the torso/leg split, and reporting what is left
//
// **What is corrected and what is not:**
// Circumferences are measurements and are never touched — scaling them would
// make the model lie about the user's data. The corrected quantity is the one
// the app never measures: how the user's height divides between torso and
// legs. The torso has a far larger cross-section than the legs, so moving that
// split changes volume substantially at constant height. Beyond ±6% the model
// reports the disagreement rather than forcing a fit.
//
import Foundation

nonisolated enum BodyValidationBand: Equatable, Sendable {
    case good
    case approximate
    case suspect

    init(deviationFraction: Double) {
        switch abs(deviationFraction) {
        case ..<0.0500001: self = .good
        case ..<0.1200001: self = .approximate
        default:           self = .suspect
        }
    }
}

nonisolated struct BodyValidationResult: Equatable, Sendable {
    /// Signed `(predicted - logged) / logged`.
    let deviationFraction: Double
    let band: BodyValidationBand
    /// Metric contributing most to an unresolved disagreement; nil unless `.suspect`.
    let suspectMetric: MetricKind?
    /// Where the torso/leg correction settled.
    let torsoShareScale: Double
}

nonisolated enum BodyVolumeValidator {
    /// Density of fat mass, g/cm³.
    private static let fatDensity = 0.900
    /// Density of fat-free mass, g/cm³.
    private static let leanDensity = 1.100

    /// Siri two-compartment whole-body density.
    static func bodyDensity(bodyFatPercent: Double) -> Double {
        let fraction = min(max(bodyFatPercent / 100, 0), 0.75)
        return 1 / (fraction / fatDensity + (1 - fraction) / leanDensity)
    }

    /// Trapezoidal integration of cross-section area over height, in litres.
    /// Limbs count twice — the solver builds one of each and mirrors at render.
    static func volumeLitres(_ parameters: BodyMeshParameters) -> Double {
        let cubicCentimetres = stackVolume(parameters.torso)
            + 2 * stackVolume(parameters.arm)
            + 2 * stackVolume(parameters.leg)
        return cubicCentimetres / 1000
    }

    private static func stackVolume(_ sections: [BodyCrossSection]) -> Double {
        let sorted = sections.sorted { $0.y < $1.y }
        guard sorted.count > 1 else { return 0 }
        var total = 0.0
        for index in 0..<(sorted.count - 1) {
            let lower = sorted[index]
            let upper = sorted[index + 1]
            total += (lower.shape.area + upper.shape.area) / 2 * (upper.y - lower.y)
        }
        return total
    }

    /// Solves the body, then searches the allowed torso/leg range for the split
    /// that best matches logged weight. The relationship is smooth and
    /// monotonic, so a bisection over the range converges in a few steps.
    static func reconcile(snapshot: BodySnapshot) -> (parameters: BodyMeshParameters, validation: BodyValidationResult) {
        let density = bodyDensity(bodyFatPercent: snapshot.bodyFatPercent)

        func deviation(at scale: Double) -> Double {
            let parameters = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: scale)
            let predicted = volumeLitres(parameters) * density
            guard snapshot.weightKg > 0 else { return 0 }
            return (predicted - snapshot.weightKg) / snapshot.weightKg
        }

        var low = BodyProportions.torsoShareRange.lowerBound
        var high = BodyProportions.torsoShareRange.upperBound
        var best = 1.0

        if deviation(at: low) * deviation(at: high) < 0 {
            for _ in 0..<24 {
                let mid = (low + high) / 2
                if deviation(at: low) * deviation(at: mid) <= 0 { high = mid } else { low = mid }
            }
            best = (low + high) / 2
        } else {
            // No zero crossing inside the range: take whichever end gets closest.
            best = abs(deviation(at: low)) < abs(deviation(at: high))
                ? BodyProportions.torsoShareRange.lowerBound
                : BodyProportions.torsoShareRange.upperBound
        }

        let parameters = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: best)
        let residual = deviation(at: best)
        let band = BodyValidationBand(deviationFraction: residual)

        return (
            parameters,
            BodyValidationResult(
                deviationFraction: residual,
                band: band,
                suspectMetric: band == .suspect ? suspectMetric(for: snapshot, residual: residual) : nil,
                torsoShareScale: best
            )
        )
    }

    /// Ranks measured circumferences by how far each sits from the population
    /// norm for this height and gender, and names the worst outlier. A model
    /// too light means an implausibly small circumference, and vice versa.
    private static func suspectMetric(for snapshot: BodySnapshot, residual: Double) -> MetricKind? {
        // Expected circumference as a fraction of height, from the same tables
        // that place the landmarks.
        let expectations: [(kind: MetricKind, measured: Double, fractionOfHeight: Double)] = [
            (.neck, snapshot.neckCm, 0.211),
            (.shoulders, snapshot.shouldersCm, 0.653),
            (.chest, snapshot.bustCm ?? snapshot.chestCm, 0.556),
            (.waist, snapshot.waistCm, 0.472),
            (.hips, snapshot.hipsCm, 0.544),
            (.leftThigh, snapshot.thighCm, 0.322),
            (.leftCalf, snapshot.calfCm, 0.211),
            (.leftBicep, snapshot.bicepCm, 0.189)
        ]

        return expectations
            .map { item -> (MetricKind, Double) in
                let expected = snapshot.heightCm * item.fractionOfHeight
                let relative = (item.measured - expected) / expected
                // Only count deviations in the direction that explains the residual.
                let aligned = residual < 0 ? -relative : relative
                return (item.kind, aligned)
            }
            .max { $0.1 < $1.1 }
            .map(\.0)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodyVolumeValidator.swift MeasureMeTests/BodyVolumeValidatorTests.swift
git commit -m "feat(body-model): reconcile silhouette volume against logged weight"
```

---

### Task 6: BodyGeometryBuilder

Zamiana parametrów na `SCNGeometry`. Czysto mechaniczne: pierścień wierzchołków na przekrój, pasy trójkątów między pierścieniami.

**Files:**
- Create: `MeasureMe/BodyModel/BodyGeometryBuilder.swift`
- Test: `MeasureMeTests/BodyGeometryBuilderTests.swift`

**Interfaces:**
- Consumes: `BodyMeshParameters`, `BodyCrossSection`, `Superellipse`
- Produces:
  - `BodyGeometryBuilder.segmentsPerRing = 32`
  - `BodyGeometryBuilder.positions(for parameters: BodyMeshParameters) -> [SIMD3<Float>]`
  - `BodyGeometryBuilder.indices(for parameters: BodyMeshParameters) -> [Int32]`
  - `BodyGeometryBuilder.geometry(for parameters: BodyMeshParameters) -> SCNGeometry`

- [ ] **Step 1: Write the failing test**

```swift
/// Cel testow: Sprawdza budowanie siatki 3D z parametrow przekrojow.
/// Dlaczego to wazne: Stala topologia jest warunkiem morfu bez artefaktow.
/// Kryteria zaliczenia: Liczba wierzcholkow i indeksow jest stala niezaleznie od wymiarow, a wierzchołki leza na zadanych wysokosciach.

import XCTest
import SceneKit
@testable import MeasureMe

final class BodyGeometryBuilderTests: XCTestCase {

    private static func parameters(circumference: Double) -> BodyMeshParameters {
        let snapshot = BodySnapshot(
            gender: .male, age: 30,
            heightCm: 180, weightKg: 80, bodyFatPercent: 18,
            neckCm: 38, shouldersCm: 118, chestCm: circumference, bustCm: nil,
            waistCm: 85, hipsCm: 98,
            bicepCm: 34, forearmCm: 28, thighCm: 58, calfCm: 38,
            anchorDate: Date(timeIntervalSince1970: 1_760_000_000),
            sourceDateRange: Date(timeIntervalSince1970: 1_760_000_000)...Date(timeIntervalSince1970: 1_760_000_000)
        )
        return BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)
    }

    /// Co sprawdza: Topologia jest niezalezna od wymiarow ciala.
    /// Dlaczego: Morf podmienia tylko bufor pozycji; zmienna liczba wierzcholkow by to zlamala.
    /// Kryteria: Dwa rozne ciala daja te sama liczbe wierzcholkow i indeksow.
    func testTopologyIsIdenticalAcrossBodies() {
        let slim = Self.parameters(circumference: 90)
        let broad = Self.parameters(circumference: 115)

        XCTAssertEqual(
            BodyGeometryBuilder.positions(for: slim).count,
            BodyGeometryBuilder.positions(for: broad).count
        )
        XCTAssertEqual(
            BodyGeometryBuilder.indices(for: slim),
            BodyGeometryBuilder.indices(for: broad)
        )
    }

    /// Co sprawdza: Liczba wierzcholkow zgadza sie z liczba przekrojow razy segmenty.
    /// Dlaczego: Wylapuje zgubiony lub zdublowany pierscien.
    /// Kryteria: Liczba rowna sumie przekrojow (tors + 2 ramiona + 2 nogi) razy 32.
    func testVertexCountMatchesRingLayout() {
        let parameters = Self.parameters(circumference: 100)
        let rings = parameters.torso.count + 2 * parameters.arm.count + 2 * parameters.leg.count
        XCTAssertEqual(
            BodyGeometryBuilder.positions(for: parameters).count,
            rings * BodyGeometryBuilder.segmentsPerRing
        )
    }

    /// Co sprawdza: Wierzcholki torsu leza dokladnie na wysokosciach przekrojow.
    /// Dlaczego: Przesuniecie w pionie oznaczaloby, ze zmierzony obwod trafia na zla wysokosc.
    /// Kryteria: Kazda wysokosc przekroju wystepuje wsrod wspolrzednych y.
    func testTorsoVerticesSitAtSectionHeights() {
        let parameters = Self.parameters(circumference: 100)
        let ys = Set(BodyGeometryBuilder.positions(for: parameters).map { ($0.y * 1000).rounded() })
        for section in parameters.torso {
            // Positions are in metres; sections in centimetres.
            let expected = ((Float(section.y) / 100) * 1000).rounded()
            XCTAssertTrue(ys.contains(expected), "No ring at y=\(section.y) cm")
        }
    }

    /// Co sprawdza: Geometria powstaje i ma zrodlo pozycji oraz element indeksow.
    /// Dlaczego: To kontrakt wobec SceneKit.
    /// Kryteria: SCNGeometry ma niepuste sources i elements.
    func testGeometryHasSourcesAndElements() {
        let geometry = BodyGeometryBuilder.geometry(for: Self.parameters(circumference: 100))
        XCTAssertFalse(geometry.sources.isEmpty)
        XCTAssertFalse(geometry.elements.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodyGeometryBuilderTests
```

Expected: FAIL — `cannot find 'BodyGeometryBuilder' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// BodyGeometryBuilder.swift
//
// **BodyGeometryBuilder**
// Turns solved cross-sections into SceneKit geometry.
//
// **Responsibilities:**
// - Emitting one ring of vertices per cross-section
// - Stitching neighbouring rings into triangle strips
// - Producing an `SCNGeometry` with positions and normals
//
// **Why topology is fixed:**
// Ring count and segment count never depend on the body's dimensions, so the
// morph can swap the position buffer of an existing geometry instead of
// rebuilding it. Everything here is mechanical — no body knowledge lives in
// this file.
//
// Positions are emitted in metres (SceneKit's convention) while the model
// works in centimetres.
//
import Foundation
import SceneKit

nonisolated enum BodyGeometryBuilder {
    /// Vertices per cross-section ring.
    static let segmentsPerRing = 32

    /// Horizontal offsets, in cm, applied to mirrored limbs.
    private static let armOffsetCm = 22.0
    private static let legOffsetCm = 9.0

    /// Every ring of the body, in a fixed order: torso, both arms, both legs.
    private static func rings(for parameters: BodyMeshParameters) -> [(section: BodyCrossSection, xOffsetCm: Double)] {
        parameters.torso.map { ($0, 0.0) }
            + parameters.arm.map { ($0, -armOffsetCm) }
            + parameters.arm.map { ($0, armOffsetCm) }
            + parameters.leg.map { ($0, -legOffsetCm) }
            + parameters.leg.map { ($0, legOffsetCm) }
    }

    static func positions(for parameters: BodyMeshParameters) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(rings(for: parameters).count * segmentsPerRing)

        for ring in rings(for: parameters) {
            let shape = ring.section.shape
            let power = 2 / shape.exponent
            for segment in 0..<segmentsPerRing {
                let angle = (2 * Double.pi) * Double(segment) / Double(segmentsPerRing)
                let cosA = cos(angle)
                let sinA = sin(angle)
                let x = shape.semiAxisA * (cosA < 0 ? -1 : 1) * pow(abs(cosA), power)
                let z = shape.semiAxisB * (sinA < 0 ? -1 : 1) * pow(abs(sinA), power)
                result.append(SIMD3<Float>(
                    Float((x + ring.xOffsetCm) / 100),
                    Float(ring.section.y / 100),
                    Float(z / 100)
                ))
            }
        }
        return result
    }

    static func indices(for parameters: BodyMeshParameters) -> [Int32] {
        // Stack boundaries must not be stitched across — each stack is closed
        // on its own, or the last torso ring would connect to the first arm ring.
        let stackLengths = [
            parameters.torso.count,
            parameters.arm.count, parameters.arm.count,
            parameters.leg.count, parameters.leg.count
        ]

        var result: [Int32] = []
        var ringBase = 0
        for length in stackLengths {
            for ring in 0..<max(length - 1, 0) {
                for segment in 0..<segmentsPerRing {
                    let next = (segment + 1) % segmentsPerRing
                    let lower = Int32((ringBase + ring) * segmentsPerRing)
                    let upper = Int32((ringBase + ring + 1) * segmentsPerRing)

                    let a = lower + Int32(segment)
                    let b = lower + Int32(next)
                    let c = upper + Int32(segment)
                    let d = upper + Int32(next)

                    result.append(contentsOf: [a, c, b])
                    result.append(contentsOf: [b, c, d])
                }
            }
            ringBase += length
        }
        return result
    }

    static func geometry(for parameters: BodyMeshParameters) -> SCNGeometry {
        let vertices = positions(for: parameters)
        let source = SCNGeometrySource(
            vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        )
        let element = SCNGeometryElement(
            indices: indices(for: parameters),
            primitiveType: .triangles
        )
        let geometry = SCNGeometry(sources: [source], elements: [element])
        return geometry
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodyGeometryBuilder.swift MeasureMeTests/BodyGeometryBuilderTests.swift
git commit -m "feat(body-model): build SceneKit geometry from cross-sections"
```

---

### Task 7: BodyModelViewModel

Stan ekranu: dostępne daty, wybór A i B, pozycja morfu, wynik walidacji, lista zmian metryk.

**Files:**
- Create: `MeasureMe/BodyModel/BodyModelViewModel.swift`
- Test: `MeasureMeTests/BodyModelViewModelTests.swift`

**Interfaces:**
- Consumes: `BodySnapshotBuilder`, `BodyVolumeValidator`, `BodyMeshParameters`, `MetricChange`, `MetricSample`, `BodyGender`
- Produces:
  - `BodyModelState` — enum: `.needsProfile`, `.missingMetrics([MetricKind])`, `.single(BodyModelViewModel.Resolved)`, `.comparison(older: Resolved, newer: Resolved)`
  - `BodyModelViewModel.Resolved` — `snapshot`, `parameters`, `validation`
  - `BodyModelViewModel.availableAnchorDates(samples:gender:fallbackHeightCm:) -> [Date]`
  - `BodyModelViewModel.state` (`@Published`), `.morphProgress` (`@Published`), `.currentParameters: BodyMeshParameters?`, `.metricChanges: [MetricChange]`

- [ ] **Step 1: Write the failing test**

```swift
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
    /// Kryteria: Stan to .comparison, a lista zmian nie jest pusta.
    func testTwoDistinctSnapshotsYieldComparison() {
        let older = completeSamples(at: anchor.addingTimeInterval(-90 * 86_400), waist: 95)
        let newer = completeSamples(at: anchor, waist: 85)

        let viewModel = BodyModelViewModel()
        viewModel.load(samples: older + newer, gender: .male, age: 30, fallbackHeightCm: 180)

        guard case .comparison = viewModel.state else {
            return XCTFail("Expected comparison, got \(viewModel.state)")
        }
        XCTAssertTrue(viewModel.metricChanges.contains { $0.kind == .waist && $0.difference == -10 })
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodyModelViewModelTests
```

Expected: FAIL — `cannot find 'BodyModelViewModel' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// BodyModelViewModel.swift
//
// **BodyModelViewModel**
// Screen state for the 3D body model.
//
// **Responsibilities:**
// - Finding which dates have a complete snapshot behind them
// - Resolving the chosen dates into solved, validated bodies
// - Exposing the interpolated body for the current morph position
//
// Anchor dates are collapsed to one per ±14-day window: two dates inside the
// same window describe the same body state, so offering both as A and B would
// promise a comparison that has no content.
//
import Foundation
import SwiftUI

@MainActor
final class BodyModelViewModel: ObservableObject {

    struct Resolved: Equatable {
        let snapshot: BodySnapshot
        let parameters: BodyMeshParameters
        let validation: BodyValidationResult
    }

    enum BodyModelState: Equatable {
        case needsProfile
        case missingMetrics([MetricKind])
        case single(Resolved)
        case comparison(older: Resolved, newer: Resolved)
    }

    @Published private(set) var state: BodyModelState = .needsProfile
    @Published var morphProgress: Double = 1
    @Published private(set) var metricChanges: [MetricChange] = []

    /// Body for the current morph position, or nil when there is nothing to show.
    var currentParameters: BodyMeshParameters? {
        switch state {
        case .needsProfile, .missingMetrics:
            return nil
        case let .single(resolved):
            return resolved.parameters
        case let .comparison(older, newer):
            return BodyMeshParameters.interpolated(
                from: older.parameters, to: newer.parameters, t: morphProgress
            )
        }
    }

    /// Validation to display — the newer body in a comparison.
    var displayedValidation: BodyValidationResult? {
        switch state {
        case .needsProfile, .missingMetrics: return nil
        case let .single(resolved): return resolved.validation
        case let .comparison(_, newer): return newer.validation
        }
    }

    /// Dates that have a complete snapshot, newest first, one per window.
    nonisolated static func availableAnchorDates(
        samples: [MetricSample],
        gender: BodyGender,
        fallbackHeightCm: Double
    ) -> [Date] {
        let candidates = Set(samples.map(\.date)).sorted(by: >)
        var accepted: [Date] = []
        let window = Double(BodySnapshotBuilder.windowDays) * 86_400

        for candidate in candidates {
            guard !accepted.contains(where: { abs($0.timeIntervalSince(candidate)) <= window }) else { continue }
            let result = BodySnapshotBuilder.build(
                samples: samples, anchorDate: candidate,
                gender: gender, age: 0, fallbackHeightCm: fallbackHeightCm
            )
            if case .success = result { accepted.append(candidate) }
        }
        return accepted
    }

    func load(samples: [MetricSample], gender: BodyGender?, age: Int, fallbackHeightCm: Double) {
        guard let gender else {
            state = .needsProfile
            metricChanges = []
            return
        }

        let dates = Self.availableAnchorDates(
            samples: samples, gender: gender, fallbackHeightCm: fallbackHeightCm
        )

        guard let newest = dates.first else {
            // Report what the most recent attempt was missing.
            let probe = samples.map(\.date).max() ?? Date()
            let result = BodySnapshotBuilder.build(
                samples: samples, anchorDate: probe,
                gender: gender, age: age, fallbackHeightCm: fallbackHeightCm
            )
            if case let .missing(kinds) = result {
                state = .missingMetrics(kinds)
            } else {
                state = .missingMetrics(BodySnapshotBuilder.requiredKinds(for: gender))
            }
            metricChanges = []
            return
        }

        guard let newer = resolve(samples: samples, at: newest, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm) else {
            state = .missingMetrics(BodySnapshotBuilder.requiredKinds(for: gender))
            metricChanges = []
            return
        }

        guard dates.count > 1,
              let oldest = dates.last,
              let older = resolve(samples: samples, at: oldest, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm)
        else {
            state = .single(newer)
            metricChanges = []
            morphProgress = 1
            return
        }

        state = .comparison(older: older, newer: newer)
        metricChanges = Self.changes(from: older.snapshot, to: newer.snapshot)
        morphProgress = 1
    }

    /// Re-resolves both sides after the user picks different dates.
    func select(olderDate: Date, newerDate: Date, samples: [MetricSample], gender: BodyGender, age: Int, fallbackHeightCm: Double) {
        guard let older = resolve(samples: samples, at: olderDate, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm),
              let newer = resolve(samples: samples, at: newerDate, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm)
        else { return }

        state = .comparison(older: older, newer: newer)
        metricChanges = Self.changes(from: older.snapshot, to: newer.snapshot)
        morphProgress = 1
    }

    private func resolve(
        samples: [MetricSample], at date: Date,
        gender: BodyGender, age: Int, fallbackHeightCm: Double
    ) -> Resolved? {
        let result = BodySnapshotBuilder.build(
            samples: samples, anchorDate: date,
            gender: gender, age: age, fallbackHeightCm: fallbackHeightCm
        )
        guard case let .success(snapshot) = result else { return nil }
        let reconciled = BodyVolumeValidator.reconcile(snapshot: snapshot)
        return Resolved(
            snapshot: snapshot,
            parameters: reconciled.parameters,
            validation: reconciled.validation
        )
    }

    /// Per-metric deltas, reusing the row model the photo comparison already uses.
    nonisolated private static func changes(from older: BodySnapshot, to newer: BodySnapshot) -> [MetricChange] {
        let pairs: [(MetricKind, Double, Double)] = [
            (.weight, older.weightKg, newer.weightKg),
            (.bodyFat, older.bodyFatPercent, newer.bodyFatPercent),
            (.neck, older.neckCm, newer.neckCm),
            (.shoulders, older.shouldersCm, newer.shouldersCm),
            (.chest, older.chestCm, newer.chestCm),
            (.waist, older.waistCm, newer.waistCm),
            (.hips, older.hipsCm, newer.hipsCm),
            (.leftBicep, older.bicepCm, newer.bicepCm),
            (.leftForearm, older.forearmCm, newer.forearmCm),
            (.leftThigh, older.thighCm, newer.thighCm),
            (.leftCalf, older.calfCm, newer.calfCm)
        ]

        return pairs.map { kind, old, new in
            MetricChange(
                kind: kind,
                oldValue: old,
                newValue: new,
                difference: new - old,
                storedUnit: kind.unitSymbol(unitsSystem: "metric")
            )
        }
    }
}

/// Shorthand so call sites read `viewModel.state` without the nested name.
typealias BodyModelState = BodyModelViewModel.BodyModelState
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodyModelViewModel.swift MeasureMeTests/BodyModelViewModelTests.swift
git commit -m "feat(body-model): screen state, anchor dates and morph binding"
```

---

### Task 8: Wyciągnięcie MetricChangeRow

`MetricChangeRow` jest dziś `private` wewnątrz `ComparePhotosView.swift`. Ekran modelu 3D ma go użyć, więc trafia do własnego pliku jako `internal`. Zmiana czysto mechaniczna, bez modyfikacji zachowania.

**Files:**
- Create: `MeasureMe/MetricChangeRow.swift`
- Modify: `MeasureMe/ComparePhotosView.swift` — usunięcie `private struct MetricChangeRow` (od `// MARK: - Metric Change Row`)
- Test: `MeasureMeTests/ComparePhotosTests.swift` musi nadal przechodzić bez zmian

- [ ] **Step 1: Locate the exact block to move**

```bash
grep -n "MARK: - Metric Change Row" -A 60 MeasureMe/ComparePhotosView.swift
```

Zanotuj zakres linii od `// MARK: - Metric Change Row` do zamykającego `}` struktury.

- [ ] **Step 2: Create the new file with the block verbatim**

Skopiuj całą strukturę do `MeasureMe/MetricChangeRow.swift`, zmieniając **wyłącznie** `private struct MetricChangeRow` na `struct MetricChangeRow` i dodając nagłówek pliku:

```swift
// MetricChangeRow.swift
//
// **MetricChangeRow**
// One row of a metric's before/after change.
//
// **Why it lives here and not in ComparePhotosView:**
// Both the photo comparison and the 3D body model present the same
// per-metric deltas. Extracted verbatim from ComparePhotosView so the two
// screens cannot drift apart.
//
import SwiftUI

struct MetricChangeRow: View {
    // ...skopiowana zawartość bez zmian...
}
```

- [ ] **Step 3: Delete the original block from ComparePhotosView.swift**

Usuń przeniesiony fragment wraz z komentarzem `// MARK: - Metric Change Row`. Nie ruszaj `MetricChange` — zostaje na miejscu.

- [ ] **Step 4: Verify nothing else changed behaviour**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/MetricChangeTests -only-testing:MeasureMeTests/ComparePresentationStateTests
```

Expected: PASS, bez zmian względem stanu sprzed zadania.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/MetricChangeRow.swift MeasureMe/ComparePhotosView.swift
git commit -m "refactor: extract MetricChangeRow so the body model can reuse it"
```

---

### Task 9: MannequinView

`SCNView` w `UIViewRepresentable`. Jedyny plik feature'u importujący SceneKit poza builderem geometrii.

**Kluczowa pułapka:** `SCNView` nie reaguje sam na zmianę `colorScheme`. Materiał i tło muszą być przeliczane w `updateUIView`.

**Files:**
- Create: `MeasureMe/BodyModel/MannequinView.swift`

**Interfaces:**
- Consumes: `BodyMeshParameters`, `BodyGeometryBuilder`, `FeatureTheme`, `AppColorRoles`
- Produces: `MannequinView(parameters: BodyMeshParameters, rotationRadians: Double)`

- [ ] **Step 1: Write the implementation**

Nie ma tu testu jednostkowego — to cienka warstwa nad SceneKit, weryfikowana testem snapshotowym w Zadaniu 11. Geometria jest już przetestowana w Zadaniu 6.

```swift
// MannequinView.swift
//
// **MannequinView**
// SceneKit host for the body model.
//
// **Responsibilities:**
// - Owning the SCNView, camera and lighting
// - Swapping the geometry's position buffer as the morph moves
// - Re-resolving colours when the appearance changes
//
// **Why the appearance handling is explicit:**
// SCNView does not participate in SwiftUI's colour scheme propagation, so
// materials and the scene background stay at whatever they were built with.
// Without the explicit refresh in updateUIView, light mode renders a dark
// block. This is the only place in the feature where 3D steps outside the
// design system, and it is deliberately contained here.
//
import SwiftUI
import SceneKit

struct MannequinView: UIViewRepresentable {
    let parameters: BodyMeshParameters
    /// Horizontal rotation applied by the drag gesture.
    var rotationRadians: Double = 0

    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.antialiasingMode = .multisampling2X
        view.isUserInteractionEnabled = false
        view.rendersContinuously = false

        let bodyNode = SCNNode(geometry: BodyGeometryBuilder.geometry(for: parameters))
        bodyNode.name = "body"
        view.scene?.rootNode.addChildNode(bodyNode)

        // Frame the body: the model is ~1.8 m tall and centred on the floor.
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 1.15
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.9, 3)
        view.scene?.rootNode.addChildNode(cameraNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 700
        key.position = SCNVector3(2, 3, 3)
        key.look(at: SCNVector3(0, 0.9, 0))
        view.scene?.rootNode.addChildNode(key)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 380
        view.scene?.rootNode.addChildNode(ambient)

        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let bodyNode = view.scene?.rootNode.childNode(withName: "body", recursively: false) else { return }

        // Topology is fixed, so the geometry is rebuilt from the same layout
        // every frame of the morph — cheap at ~1500 vertices, and it keeps the
        // buffer handling in one place.
        bodyNode.geometry = BodyGeometryBuilder.geometry(for: parameters)
        bodyNode.eulerAngles.y = Float(rotationRadians)

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(FeatureTheme.photos.accent)
        material.roughness.contents = 0.85
        material.metalness.contents = 0.0
        material.isDoubleSided = true
        bodyNode.geometry?.materials = [material]

        view.backgroundColor = .clear
        view.scene?.background.contents = UIColor.clear
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild build -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add MeasureMe/BodyModel/MannequinView.swift
git commit -m "feat(body-model): SceneKit mannequin view with appearance-aware materials"
```

---

### Task 10: BodyModelScreen, teksty i wejście z Photos

Ekran, stany brzegowe, bramka premium, dostępność i wpięcie w `PhotoView`.

**Files:**
- Create: `MeasureMe/BodyModel/BodyModelScreen.swift`
- Modify: `MeasureMe/PhotoView.swift` — nowy `@State` i `.sheet`
- Modify: `MeasureMe/{en,pl,de,es,fr,pt-BR}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `BodyModelViewModel`, `MannequinView`, `MetricChangeRow`, `EmptyStateCard`, `PremiumStore`, `AppGlassCard`, `FeatureTheme`, `AppMotion`
- Produces: `BodyModelScreen()`

- [ ] **Step 1: Add the localized strings**

Do **każdego** z sześciu plików `MeasureMe/<lang>.lproj/Localizable.strings` dodaj klucze (wartości angielskie poniżej; przetłumacz na język pliku):

```
"bodyModel.title" = "Body model";
"bodyModel.empty.profile.title" = "Complete your profile";
"bodyModel.empty.profile.message" = "The body model needs your height and sex to place your measurements correctly.";
"bodyModel.empty.profile.action" = "Open profile";
"bodyModel.empty.metrics.title" = "A few measurements to go";
"bodyModel.empty.metrics.message" = "Log these to build your silhouette: %@";
"bodyModel.empty.metrics.action" = "Add measurements";
"bodyModel.premium.title" = "See your silhouette in 3D";
"bodyModel.premium.message" = "Turn your measurements into a body model and watch it change between any two dates.";
"bodyModel.premium.action" = "Unlock";
"bodyModel.quality.approximate" = "This silhouette is an approximation.";
"bodyModel.quality.suspect" = "Your measurements and weight don't quite add up. Check your %@.";
"bodyModel.morph.label" = "Morph between dates";
"bodyModel.morph.play" = "Play";
"bodyModel.dates.older" = "From";
"bodyModel.dates.newer" = "To";
"bodyModel.accessibility.mannequin" = "Body silhouette built from your measurements. Changes are listed below.";
"bodyModel.sourceRange" = "Measured %@ – %@";
```

- [ ] **Step 2: Write the screen**

```swift
// BodyModelScreen.swift
//
// **BodyModelScreen**
// The 3D body model screen, presented from the Photos tab.
//
// **Responsibilities:**
// - Presenting the mannequin, the date pickers and the morph slider
// - Gating on premium and on data completeness
// - Exposing the change list as the accessible equivalent of the 3D view
//
// The rendered geometry is invisible to VoiceOver, so the MetricChangeRow list
// below it is not decoration — it is how the screen's information reaches
// someone who cannot see the mannequin.
//
import SwiftUI
import SwiftData

struct BodyModelScreen: View {
    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.profile.userGender) private var userGender: String = "notSpecified"
    @AppSetting(\.profile.userAge) private var userAge: Int = 0
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0

    @Query(sort: \MetricSample.date, order: .reverse) private var samples: [MetricSample]
    @StateObject private var viewModel = BodyModelViewModel()
    @State private var rotationRadians: Double = 0

    private let theme = FeatureTheme.photos

    private var uiTestModeEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestMode")
    }

    private var hasAccess: Bool { premiumStore.isPremium || uiTestModeEnabled }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    if hasAccess {
                        content
                    } else {
                        premiumTeaser
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppScreenBackground())
            .navigationTitle(AppLocalization.string("bodyModel.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: reload)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .needsProfile:
            EmptyStateCard(
                title: AppLocalization.string("bodyModel.empty.profile.title"),
                message: AppLocalization.string("bodyModel.empty.profile.message"),
                systemImage: "person.crop.circle.badge.questionmark",
                actionTitle: AppLocalization.string("bodyModel.empty.profile.action"),
                action: { dismiss() },
                accessibilityIdentifier: "photos.bodyModel.needsProfile"
            )

        case let .missingMetrics(kinds):
            EmptyStateCard(
                title: AppLocalization.string("bodyModel.empty.metrics.title"),
                message: String(
                    format: AppLocalization.string("bodyModel.empty.metrics.message"),
                    kinds.map(\.title).joined(separator: ", ")
                ),
                systemImage: "ruler",
                actionTitle: AppLocalization.string("bodyModel.empty.metrics.action"),
                action: { dismiss() },
                accessibilityIdentifier: "photos.bodyModel.missingMetrics"
            )

        case .single, .comparison:
            mannequinCard
            if case .comparison = viewModel.state { morphControls }
            qualityNote
            changeList
        }
    }

    private var mannequinCard: some View {
        AppGlassCard(cornerRadius: AppRadius.xl, tint: theme.softTint) {
            Group {
                if let parameters = viewModel.currentParameters {
                    MannequinView(parameters: parameters, rotationRadians: rotationRadians)
                        .frame(height: 380)
                        .gesture(
                            DragGesture()
                                .onChanged { rotationRadians = $0.translation.width / 90 }
                        )
                }
            }
            .accessibilityElement()
            .accessibilityLabel(AppLocalization.string("bodyModel.accessibility.mannequin"))
            .accessibilityIdentifier("photos.bodyModel.mannequin")
        }
    }

    private var morphControls: some View {
        AppGlassCard(tint: theme.softTint) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(AppLocalization.string("bodyModel.morph.label"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)

                Slider(value: $viewModel.morphProgress, in: 0...1)
                    .tint(theme.accent)
                    .accessibilityIdentifier("photos.bodyModel.morphSlider")

                if AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion) {
                    Button(AppLocalization.string("bodyModel.morph.play")) {
                        Haptics.selection()
                        viewModel.morphProgress = 0
                        withAnimation(.easeInOut(duration: 1.5)) { viewModel.morphProgress = 1 }
                    }
                    .buttonStyle(LiquidCapsuleButtonStyle(tint: theme.accent))
                    .accessibilityIdentifier("photos.bodyModel.play")
                }
            }
        }
    }

    @ViewBuilder
    private var qualityNote: some View {
        if let validation = viewModel.displayedValidation, validation.band != .good {
            AppGlassCard(tint: theme.softTint) {
                HStack(alignment: .top, spacing: AppSpacing.xs) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                    Text(qualityMessage(for: validation))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
            }
            .accessibilityIdentifier("photos.bodyModel.qualityNote")
        }
    }

    private func qualityMessage(for validation: BodyValidationResult) -> String {
        switch validation.band {
        case .good:
            return ""
        case .approximate:
            return AppLocalization.string("bodyModel.quality.approximate")
        case .suspect:
            return String(
                format: AppLocalization.string("bodyModel.quality.suspect"),
                validation.suspectMetric?.title ?? ""
            )
        }
    }

    @ViewBuilder
    private var changeList: some View {
        if !viewModel.metricChanges.isEmpty {
            AppGlassCard(tint: theme.softTint) {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(viewModel.metricChanges, id: \.kind) { change in
                        MetricChangeRow(change: change)
                    }
                }
            }
            .accessibilityIdentifier("photos.bodyModel.changeList")
        }
    }

    private var premiumTeaser: some View {
        EmptyStateCard(
            title: AppLocalization.string("bodyModel.premium.title"),
            message: AppLocalization.string("bodyModel.premium.message"),
            systemImage: "figure.stand",
            actionTitle: AppLocalization.string("bodyModel.premium.action"),
            action: { premiumStore.presentPaywall(reason: .feature("body_model")) },
            accessibilityIdentifier: "photos.bodyModel.premiumTeaser"
        )
    }

    private func reload() {
        viewModel.load(
            samples: samples,
            gender: BodyGender(Gender(rawValue: userGender) ?? .notSpecified),
            age: userAge,
            fallbackHeightCm: manualHeight
        )
    }
}
```

- [ ] **Step 3: Wire the entry point into PhotoView**

W `MeasureMe/PhotoView.swift` dodaj obok istniejących `@State` (okolice linii 14):

```swift
@State private var showBodyModel = false
```

Dodaj sheet obok istniejącego `.sheet(item: comparePairBinding)` (linia 348):

```swift
.sheet(isPresented: $showBodyModel) {
    BodyModelScreen()
        .environmentObject(premiumStore)
}
```

Dodaj przycisk uruchamiający, w tym samym pasku narzędzi co Compare:

```swift
Button {
    Haptics.selection()
    showBodyModel = true
} label: {
    Image(systemName: "figure.stand")
}
.accessibilityIdentifier("photos.bodyModel.open")
.accessibilityLabel(AppLocalization.string("bodyModel.title"))
```

- [ ] **Step 4: Verify it builds and existing tests still pass**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/LocalizationConsistencyTests -only-testing:MeasureMeTests/ComparePhotosTests
```

Expected: PASS. `LocalizationConsistencyTests` przechodzi tylko, jeśli klucze są we wszystkich sześciu językach — to sprawdzian kompletności tłumaczeń.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodyModelScreen.swift MeasureMe/PhotoView.swift MeasureMe/*.lproj/Localizable.strings
git commit -m "feat(body-model): screen, premium gate and Photos entry point"
```

---

### Task 11: Test snapshotowy i UI

Domknięcie: wizualna regresja ekranu i przejście bramki premium.

**Files:**
- Create: `MeasureMeTests/BodyModelSnapshotTests.swift`
- Create: `MeasureMeUITests/BodyModelUITests.swift`

- [ ] **Step 1: Write the snapshot test**

Wzoruj się na `MeasureMeTests/ComparePhotosSnapshotTests.swift` — użyj tego samego helpera i konwencji nazw baseline'ów. Ustaw **jawnie** wszystkie klucze UserDefaults, których używa ekran (`userGender`, `userAge`, `manualHeight`, `animationsEnabled`, `unitsSystem`), w `configureDefaults`. Pominięcie któregokolwiek pozwala stanowi wyciec między biegami.

```swift
/// Cel testow: Snapshot ekranu modelu 3D w obu schematach kolorow.
/// Dlaczego to wazne: Manekin renderuje sie poza systemem designu; regresja kolorow jest tu latwa.
/// Kryteria zaliczenia: Render zgadza sie z baseline'em dla light i dark.
```

Na iOS 27.0 ten test **będzie czerwony przy pierwszym uruchomieniu**, tak jak pozostałe snapshoty w repo. Zarejestruj baseline i odnotuj to w opisie commita.

- [ ] **Step 2: Write the UI test**

```swift
/// Cel testow: Sprawdza wejscie do modelu 3D z zakladki Photos i bramke premium.
/// Dlaczego to wazne: Feature jest platny; zla bramka to albo utracony przychod, albo zablokowany user.
/// Kryteria zaliczenia: Bez premium widoczna zachęta, z premium widoczny manekin.
```

Uruchamiaj z `-uiTestMode`, żeby ominąć zakup, i bez niego dla ścieżki teaserowej. Sprawdzaj `photos.bodyModel.premiumTeaser` oraz `photos.bodyModel.mannequin`.

- [ ] **Step 3: Run both**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodyModelSnapshotTests -only-testing:MeasureMeUITests/BodyModelUITests
```

Rozgrzej symulator krótkim biegiem przed traktowaniem wyników UI jako sygnału — pierwszy bieg na świeżo wyczyszczonym symulatorze potrafi zgłosić kilkadziesiąt fałszywych porażek.

- [ ] **Step 4: Commit**

```bash
git add MeasureMeTests/BodyModelSnapshotTests.swift MeasureMeUITests/BodyModelUITests.swift
git commit -m "test(body-model): snapshot and premium gate coverage"
```

---

## Self-review

**Pokrycie specyfikacji**

| Sekcja specyfikacji | Zadanie |
|---|---|
| 3. Wymagane dane, okno ±14 dni, uśrednianie L/P, bust tylko K | 2 |
| 3. `shoulders` jako obwód | 4 (`anchorCircumference`) |
| 4. Architektura, granica SceneKit | 1–7 (matematyka), 9 (SceneKit) |
| 5. Superelipsa, pole, monotoniczna interpolacja | 1, 3, 4 |
| 5. Pozycje pionowe z tablic | 3 |
| 6. Gęstość Siriego, korekta ±6%, progi 5/12% | 5 |
| 7. Morf parametrów, niezmiennik zawierania | 3, 7 |
| 8. Akcent Photos, komponenty, pułapka `SCNView` | 9, 10 |
| 9. Premium, `.feature("body_model")`, tryb testów UI | 10, 11 |
| 10. Stany brzegowe | 7 (logika), 10 (UI) |
| 11. `AppMotion`, VoiceOver, identyfikatory | 10 |
| 12. Testy 1–6 | 2, 4, 5, 3, 11, 11 |

**Odstępstwo od specyfikacji, świadome:** spec zapowiadał kalibrację `BodyProportions` na percentylach ANSUR II. Zastąpiono ją testem okrągłości masy (Zadanie 5), który sprawdza tę samą własność bez zewnętrznego zbioru danych i bez ryzyka wpisania zmyślonych liczb referencyjnych. Kalibracja na realnych danych ANSUR pozostaje sensownym krokiem po MVP, gdy zbiór będzie pod ręką.

**Placeholdery:** brak. Każdy krok kodowy zawiera kod do wpisania; Zadanie 8 przenosi istniejący blok dosłownie; Zadanie 11 wskazuje istniejący plik jako wzorzec zamiast powtarzać helpery snapshotowe.

**Spójność typów:** `BodySnapshot` (Zadanie 2) używany w 4, 5, 7. `BodyMeshParameters` / `BodyCrossSection` (3) w 4, 5, 6, 7, 9. `Superellipse.fitting` (1) w 3 i 6. `BodyValidationResult` (5) w 7 i 10. `MetricChange` (istniejący) w 7 i 10. `BodyMeshSolver.solve(snapshot:torsoShareScale:)` ma tę samą sygnaturę w 4, 5 i testach 6.
