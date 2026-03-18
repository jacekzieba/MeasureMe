# Release Validation

This repository now includes a dedicated release-validation setup for the `1.3` line:

- Shared scheme: `MeasureMe Release Validation`
- Shared test plan: `TestPlans/MeasureMe Release Validation.xctestplan`
- Runner script: `scripts/release_validation.sh`

The setup is designed for three lanes:

- `Debug Test`: XCTest and XCUITest execution with `xcresult` output.
- `Release Profile`: `Release` build/profile flow for Instruments.
- `Release Archive`: signed archive or TestFlight candidate build.

## Recommended Session Flow

1. Create a session folder:

```bash
scripts/release_validation.sh start-session 1.3-rc1
```

2. Run static analysis:

```bash
scripts/release_validation.sh analyze /absolute/path/to/session
```

3. Run simulator regression as the fast gate:

```bash
scripts/release_validation.sh sim-regression "platform=iOS Simulator,name=iPhone 16,OS=latest" /absolute/path/to/session
```

4. Run critical UI suites on each physical device:

```bash
scripts/release_validation.sh device-ui "platform=iOS,id=<device-id>" /absolute/path/to/session 1
scripts/release_validation.sh device-ui "platform=iOS,id=<device-id>" /absolute/path/to/session 5
```

Use the first pass for a clean smoke/regression run and the repeated pass for stability.

5. Run checker coverage on simulator:

```bash
scripts/release_validation.sh checkers-sim "platform=iOS Simulator,name=iPhone 16,OS=latest" /absolute/path/to/session
```

Run Main Thread Checker from Xcode on top of this lane because `xcodebuild` does not expose a dedicated CLI flag for it.

6. Produce a release archive:

```bash
scripts/release_validation.sh archive-rc /absolute/path/to/session
```

7. Profile the signed release build in Xcode or print ready-made `xctrace` commands:

```bash
scripts/release_validation.sh profile-guide "<device name or id>"
```

## Device Matrix

- `iPhone A`: Apple Intelligence-capable device, newest stable iOS you have available, signed into iCloud, HealthKit data loaded, RevenueCat/App Store sandbox ready.
- `iPhone B`: non-AI device, ideally older iOS than device A, still supported by the current deployment target (`17.2+`).

If only one device is available, run the same sequence and document the missing lane in the session summary.

## Automated Scope

`device-ui` runs the critical suites called out by the release plan:

- `MeasureMeUITests`
- `OnboardingUITests`
- `SettingsViewUITests`
- `QuickAddUITests`
- `PhotoFlowUITests`
- `MultiPhotoImportUITests`
- `PerformanceUITests`

`sim-regression` keeps the full test plan enabled so unit tests, snapshots and UI regressions still act as the fast gate.
It pins the `Debug-Device` configuration so the run happens once with coverage instead of once per test-plan configuration.

`checkers-sim` pins `Debug-Checkers`, which is intended for sanitizer runs and retry-on-failure behavior.

## Manual Release Checklist

Use `docs/release-validation-template.md` as the session note and fill it during the run.

Fresh install:

- Onboarding flow
- Permission prompts
- Premium gating
- First launch stability
- `PL` and `EN`
- Light, dark and Dynamic Type

Upgrade regression:

- Install previous `main` or the prior RC
- Seed data
- Upgrade to the `1.3` candidate
- Validate settings, premium state, measurements, goals, photos, widget, quick actions and backup metadata

Feature focus:

- Export and share: `CSV`, `JSON`, `PDF`
- RevenueCat purchase, restore and manage subscription
- AI insights, cache, conversation and sanity checker
- iCloud backup, restore and background backup
- Compare photos and transformation card preview/render/share
- Home, onboarding and settings refactor regressions

Regression focus:

- Quick Add
- Measurements history and chart navigation
- Single and multi-photo save
- Reminders
- HealthKit sync allow/deny/revoke
- Widget refresh through the shared app group
- Crash reporting and delete-all/import paths

## Privacy And Performance

For `Release Profile`, profile the following with Instruments:

- `Time Profiler`
- `Leaks`
- `Allocations`
- `Energy Log`
- `Network`
- `File Activity`

Must-cover scenarios:

- cold launch and startup loading
- tab switching
- metric detail entry
- AI generation
- compare photos
- transformation card render/share
- export `PDF/JSON/CSV`
- backup and restore

Privacy checks:

- verify no health values, photo data or personal data leave the device without an explicit user action
- verify TelemetryDeck remains limited to anonymous product signals
- verify iCloud backup packages are encrypted `.measuremebackup` directories
- verify crash logs include diagnostics only when the user enabled the setting
- verify temporary files, widget shared storage and canceled share sheets do not leave stray user data behind

## Artifacts

Every scripted lane writes into a session folder under `build/release-validation/` and should produce:

- `xcresult`
- lane log
- summary note copied from the template

Keep one summary per candidate and compare it with the previous `main` or last shipped/TestFlight baseline.
