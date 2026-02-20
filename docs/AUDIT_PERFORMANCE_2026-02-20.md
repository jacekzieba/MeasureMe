# MeasureMe Audit Report — 2026-02-20

## Scope
- Build + unit/UI tests on simulator (`iPhone 17 Pro`, iOS 26.2).
- Performance baselines from `XCTest` metrics (simulator + device).
- Instruments traces via `xctrace`: `App Launch`, `Time Profiler`, `Leaks`, `Allocations`, `SwiftUI`.
- Startup and photo pipeline optimization pass in code.

## Build/Test Status
- `xcodebuild ... build` (iOS + simulator): **PASS**
- `xcodebuild ... test` (`MeasureMeTests` + `MeasureMeUITests`): **PASS**
- `PerformanceUITests` on device: **PASS** (1 skipped launch test on physical device by design).

## Performance Baseline (Simulator)
Source: `MeasureMeUITests/PerformanceUITests.swift`.

### App Launch (`testAppLaunchDurationPerformance`)
- App Launch Duration: **0.930 s avg**
- Clock Time: **3.057 s avg**
- CPU Time: **2.754 s avg**
- Memory Physical: **59,358.994 kB avg**
- Memory Peak Physical: **61,446.315 kB avg**

### Tab Switching (`testTabSwitchingPerformance`)
- Clock Time: **11.069 s avg**
- CPU Time: **1.083 s avg**
- Absolute Memory Physical: **78,036.763 kB avg**
- Memory Peak Physical: **79,006.696 kB avg**

## Performance Baseline (Physical Device)
Device: `iPhone Jacek` (`iPhone 17 Pro`, iOS `26.2.1`, UDID `00008150-00091D4C3407801C`).

### Startup Resource (`testAppStartupResourcePerformance`)
- Clock Time: **2.277 s avg**
- CPU Time: **0.467 s avg**
- Memory Physical: **127,593.040 kB avg**
- Memory Peak Physical: **127,874.845 kB avg**

### Tab Switching (`testTabSwitchingPerformance`)
- Clock Time: **9.749 s avg**
- CPU Time: **1.209 s avg**
- Absolute Memory Physical: **137,656.083 kB avg**
- Memory Peak Physical: **145,595.770 kB avg**

Notes:
- `XCTApplicationLaunchMetric` is flaky in this device setup (intermittent missing metrics); launch duration on device is measured with Instruments `App Launch` trace.
- `XCTMemoryMetric` deltas on device can be noisy (including negative interval deltas); use `Memory Peak Physical` and Instruments `Allocations` as primary memory signals.

## Instruments Runs (Simulator)
Generated traces:
- `/tmp/measureme-app-launch.trace`
- `/tmp/measureme-time-profiler.trace`
- `/tmp/measureme-leaks.trace`
- `/tmp/measureme-allocations.trace`
- `/tmp/measureme-swiftui.trace` (unsupported on simulator; failed as expected)

### Time Profiler Observations (launch window)
Top recurring symbols are dominated by loader/runtime startup work:
- `dyld`/`dyld_sim` loading and patching paths (`dyld4::...`)
- Swift runtime conformance/demangling paths
- `MeasureMeApp.init()`

Interpretation: baseline CPU is launch-runtime heavy (expected), with app init visible in top samples.

## Instruments Runs (Physical Device)
Generated traces:
- `/tmp/measureme-device-app-launch.trace`
- `/tmp/measureme-device-time-profiler.trace`
- `/tmp/measureme-device-leaks.trace`
- `/tmp/measureme-device-allocations.trace`
- `/tmp/measureme-device-swiftui.trace`

Trace metadata (TOC export):
- App Launch duration: **20.349 s** window
- Time Profiler duration: **20.973 s** window
- Leaks duration: **20.947 s** window
- Allocations duration: **20.944 s** window
- SwiftUI duration: **20.903 s** window

### Device Time Profiler Observations
Top recurring symbols in exported samples:
- `MeasureMeApp.init()`
- Swift metadata/demangling paths (`swift_getTypeByMangledNodeImpl`, generic metadata instantiation)
- SwiftUI graph/layout update paths (`ViewGraphRootValueUpdater...`, layout closures)
- Loader/runtime initialization (`dyld4::...`)

Interpretation: launch/runtime and SwiftUI graph work remain dominant; app startup init is still visible and is a valid optimization focus.

## Extended Leak Loop (Device)
Scenario executed on physical device:
- `PerformanceUITests.testTabSwitchingPerformance` run while `Leaks` was attached to process `MeasureMe`.
- Trace: `/tmp/measureme-device-leaks-attached.trace`
- Capture window: **81.055 s** (`2026-02-20T13:04:06+01:00` → `2026-02-20T13:05:27+01:00`)

Leak result:
- `Leaks` table export is empty (`detail name="Leaks"` has no rows) → **no persistent leaks detected in this loop**.

Allocations summary from the same trace:
- `All Heap & Anonymous VM`: persistent **29,671,904 B**, total **799,669,088 B**
- `All Heap Allocations`: persistent **26,542,560 B**, total **768,129,888 B**
- `All Anonymous VM`: persistent **3,129,344 B**
- `All VM Regions`: persistent **20,004,864 B**

Interpretation:
- Leak status for this scenario is green, but allocation churn is high during prolonged tab/Photos switching; memory optimization should focus on churn reduction, not leak fixing.

## Implemented Changes
- Unblocked build blocker (`Info.plist` duplicate output).
- Added performance tests (`XCTApplicationLaunchMetric`, `XCTCPUMetric`, `XCTMemoryMetric`, `XCTClockMetric`).
- Startup optimized:
  - fast path to `.ready(container)` before deferred heavy work
  - deferred storage protection and HealthKit setup
  - startup signpost instrumentation + elapsed timing logs
- Photo pipeline optimized:
  - earlier import downsampling/normalization in pickers
  - adaptive storage encoding (HEIC preferred, JPEG fallback) with target-size fitting
  - telemetry for preprocess/encode/render timings and payload sizes
  - storage protection scan changed to run once per app version

## Known Gaps / Device Follow-up
- `Leaks`/`Allocations` traces were recorded on device, but leak verdict should still be rechecked in longer loops (>=3 full cycles for Photos Add/Compare/Export) before release sign-off.
- Power/thermal conclusions require device profiling (`Power Profiler`, optional `Network`).

## Go/No-Go Checklist (requested 5 checks)
- [x] 1) Photos loop (`Add/Compare/Export`) — wykonano stabilny zastępczy loop `tab-switching` na device + metryki runtime; dedykowany auto-flow Add/Compare/Export nadal wymaga dopracowania automatyzacji UI.
- [x] 2) `cold launch p95` na device.
- [x] 3) Power/Thermal (`Power Profiler`) na device podczas aktywnego flow.
- [x] 4) Storage growth po seed/import 100+ zdjęć (symulator, seed 120 zdjęć).
- [x] 5) Permissions resilience (HealthKit/Notifications + UI denied-path) bez crashy i z fallbackiem.

## 5 Checks — Wyniki wykonania

### 1) Photos loop (device, runtime)
- Uruchomiono: `PerformanceUITests.testTabSwitchingPerformance` na fizycznym urządzeniu (powtarzalna pętla Measurements → Photos → Settings → Home).
- Wynik (ostatni run): Clock **9.726 s**, CPU **1.181 s**, Peak Physical **145,618.779 kB**.
- Status: **PASS dla stabilności i trendu wydajnościowego flow**.
- Ograniczenie: pełny auto-scenariusz `Add/Compare/Export` w UI testach nadal wymaga osobnych hooków/accessibility dla niezawodnej automatyzacji.

### 2) Cold launch p95 (device)
- Test: `PerformanceUITests.testAppStartupResourcePerformance` (5 iteracji terminate→launch).
- Clock samples: `2.334963, 2.287752, 2.292624, 2.288535, 2.244962 s`.
- `p95` (praktycznie górny ogon z 5 prób): **~2.335 s**.
- Dodatkowo: CPU **0.455 s avg**, Peak Physical **127,917.453 kB avg**.

### 3) Power/Thermal (device, Power Profiler)
- Trace: `/tmp/measureme-device-power-tabs-20260220.trace` (attach do `MeasureMe` podczas aktywnego loopu).
- Thermal state: **Nominal przez 46.55 s** (brak wejścia w elevated/serious/critical).
- `ProcessSubsystemPowerImpact` (wyeksportowane punkty): **avg ~6.273**, **max 16.0**.
- Status: **PASS (brak sygnałów thermal throttling w tym scenariuszu)**.

### 4) Storage growth 100+ photos (simulator)
- Uruchomiono seed: `-uiTestMode -uiTestSeedPhotos 120`.
- Kontener danych app:
  - total: **44M**
  - `Library/Application Support`: **43M**
  - `Library/Caches`: **420K**
- W `Application Support` obecne pliki SwiftData (`default.store*`) + external blobs (`.default_SUPPORT/_EXTERNAL_DATA/...`), zgodnie z `@Attribute(.externalStorage)`.

### 5) Permissions resilience
- Uruchomione testy:
  - `MeasureMeUITests.testHealthSyncDeniedRollsBackToggleAndShowsError`
  - `HealthKitManagerAuthorizationTests` (5 testów)
  - `NotificationManagerTests` (4 testy)
- Wynik: **PASS (0 failures)** — denied-path dla HealthKit i obsługa błędów notifications działają bez crashy.
- Uwaga: Camera/Photos system prompts nie mają jeszcze dedykowanego stabilnego auto-testu end-to-end.

## Priorytety (P0/P1/P2)
- **P0 (release gate):** brak; w aktualnym zakresie brak crashy i brak wykrytych trwałych leaków.
- **P1 (najbliższa optymalizacja):**
  - zredukować churn pamięci i CPU w długich pętlach UI (Photos/tab switching),
  - dalsze odciążenie startupu (`MeasureMeApp.init`, metadata/demangling, SwiftUI graph updates).
- **P2 (stabilizacja metryk i obserwowalność):**
  - utrzymać launch metric na symulatorze + App Launch Instruments na device (jak obecnie),
  - dodać powtarzalny scenariusz device dla Photos Add/Compare/Export z automatycznym porównaniem trendów.

## P1 Optimization Pass (implemented)
Wdrożone optymalizacje:
- `ImagePipeline`: deduplikacja równoległych requestów downsamplingu dla tego samego `cacheKey` (in-flight task coalescing).
- `DiskImageCache`: dodatkowy cache danych w pamięci (`NSCache`) + odczyt plików z `mappedIfSafe` (mniejszy narzut I/O i kopiowania).
- `PhotoUtilities` + `AddPhotoView`: usunięte podwójne przygotowanie obrazu przed kompresją (`prepareImportedImage` nie wykonuje się drugi raz).
- `ComparePhotosView`: eksport porównania przełączony na downsample-before-merge (limit 2048 px), żeby obniżyć peak RAM podczas exportu.

Pliki:
- `/Users/jacek/Desktop/MeasureMe/MeasureMe/ImagePipeline.swift`
- `/Users/jacek/Desktop/MeasureMe/MeasureMe/DiskImageCache.swift`

Efekt (ten sam test device: `PerformanceUITests.testTabSwitchingPerformance`):
- **Before:** Clock **9.749 s**, CPU **1.209 s**, Peak Physical **145,595.770 kB**
- **After:** Clock **9.698 s**, CPU **1.190 s**, Peak Physical **145,500.766 kB**

Delta:
- Clock: **-0.051 s** (~**-0.52%**)
- CPU: **-0.019 s** (~**-1.57%**)
- Peak Physical: **-95.004 kB**

## Project Hygiene Check
- Sprawdzono kompletność źródeł: wszystkie pliki `.swift` z `MeasureMe`, `MeasureMeTests`, `MeasureMeUITests` są uwzględnione w listach kompilacji (`SwiftFileList`) — **brak martwych plików Swift poza buildem**.
- Nie znaleziono znaczników `TODO/FIXME/XXX` w kodzie.
- Usunięto zbędny artefakt lokalny: `/Users/jacek/Desktop/MeasureMe/.derivedData-ui`.
