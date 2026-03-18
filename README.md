# MeasureMe

MeasureMe is an iOS app for tracking body measurements, health trends, and progress photos in one place.
The app is designed for quick daily/weekly check-ins and long-term progress monitoring with privacy-first defaults.

## What It Includes

- Metric tracking (weight, waist, body fat, lean mass, and additional body measurements)
- Quick Add flow for fast logging
- Goals and progress visualization
- Photo tracking, tags, and side-by-side comparison
- Optional HealthKit integration
- Reminder notifications
- Premium features (AI insights, advanced indicators, export, and comparison tools)
- English and Polish localization
- Home screen widget target (`MeasureMeWidget`)

## Platform Support

- Deployment target: iOS `17.2`
- Recommended: latest iOS available for your device
- AI insights: iOS `26+` on Apple Intelligence-capable devices

## Tech Stack

- Swift + SwiftUI
- SwiftData
- HealthKit
- StoreKit 2
- WidgetKit
- XCTest / XCUITest

## Project Layout

- `MeasureMe` - app source code
- `MeasureMeWidget` - widget extension
- `MeasureMeTests` - unit and snapshot tests
- `MeasureMeUITests` - UI tests
- `TestPlans` - shared Xcode test plans for release validation
- `scripts` - local automation helpers for validation and QA runs
- `docs` - release-validation checklist and result templates
- `MeasureMe.xcodeproj` - Xcode project and schemes
- `.github/workflows/ios-ci.yml` - CI pipeline

## Getting Started

### Requirements

- macOS with Xcode (project CI uses Xcode `26.2`)
- iOS Simulator or physical iPhone
- Apple Developer account (only required for running on a physical device with your own signing)

### Open In Xcode

```bash
open MeasureMe.xcodeproj
```

Then:

1. Select the `MeasureMe` scheme.
2. Select a simulator or device.
3. Build and run (`Cmd + R`).

## Command Line Build And Test

List available simulator destinations first:

```bash
xcodebuild -project MeasureMe.xcodeproj -scheme MeasureMe -showdestinations
```

Build (replace destination with one from your machine):

```bash
xcodebuild \
  -project MeasureMe.xcodeproj \
  -scheme MeasureMe \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.1' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run tests:

```bash
xcodebuild \
  -project MeasureMe.xcodeproj \
  -scheme MeasureMe \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.1' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Release validation helpers:

```bash
scripts/release_validation.sh show-test-plans
scripts/release_validation.sh analyze
scripts/release_validation.sh sim-regression
scripts/release_validation.sh device-ui 'platform=iOS,id=<device-id>' build/release-validation/session 1
scripts/release_validation.sh checkers-sim
scripts/release_validation.sh archive-rc
```

Dedicated release-validation docs live in `docs/release-validation.md`.

Run static analysis (non-blocking in CI):

```bash
xcodebuild \
  -project MeasureMe.xcodeproj \
  -scheme MeasureMe \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.1' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  analyze
```

Lint:

```bash
swiftlint lint --config .swiftlint.yml
```

## Premium / StoreKit

Product identifiers:

- `com.measureme.premium.monthly`
- `com.measureme.premium.yearly`

Local StoreKit configuration used by the shared scheme:

- `MeasureMe/Premium_local.storekit`

Additional local config file in repository:

- `Premium.storekit`

## CI

GitHub Actions workflow (`.github/workflows/ios-ci.yml`) runs:

- SwiftLint (changed files blocking, full run non-blocking report)
- Build
- Analyze (non-blocking)
- Tests
- Matrix lanes for iOS runtimes `18.0` and `26.1`, with runtime fallback/skip logic when unavailable

## Privacy

- Data is stored on-device.
- App is offline-first by default.
- HealthKit access is optional and user-controlled.
- Export and sharing are user-initiated.

## License

This repository does not currently include a `LICENSE` file.
