# MeasureMe

MeasureMe is an iOS app for tracking body measurements, health trends, and progress photos in one place.
It is built for fast daily/weekly check-ins and long-term progress monitoring with privacy-first defaults.

## Features

- Tracking core metrics: weight, waist, body fat, lean mass, and additional body measurements
- Quick Add flow for fast logging
- Goals and trend visualization
- Photo timeline with tags and side-by-side comparison
- Optional HealthKit sync
- Reminder notifications
- Premium tools: AI insights, advanced indicators, export, comparison tools
- English and Polish localization
- Home screen widget target (`MeasureMeWidget`)

## Platform

- Deployment target: iOS `17.2`
- Recommended runtime: latest iOS available on your device/simulator
- AI insights: iOS `26+` on Apple Intelligence-capable devices

## Tech Stack

- Swift + SwiftUI
- SwiftData
- HealthKit
- StoreKit 2
- WidgetKit
- XCTest / XCUITest

## Repository Structure

- `MeasureMe` - application source code
- `MeasureMeWidget` - widget extension
- `MeasureMeTests` - unit tests and snapshots
- `MeasureMeUITests` - UI tests
- `TestPlans` - shared Xcode test plans for release validation
- `scripts` - local automation helpers for validation and QA
- `docs` - release-validation docs and templates
- `MeasureMe.xcodeproj` - Xcode project and schemes
- `.github/workflows/ios-ci.yml` - CI pipeline

## Quick Start

### Requirements

- macOS with Xcode (CI uses Xcode `26.2`)
- iOS Simulator or physical iPhone
- Apple Developer account (only needed for physical-device signing)

### Open In Xcode

```bash
open MeasureMe.xcodeproj
```

Then:

1. Select the `MeasureMe` scheme.
2. Select a simulator or device.
3. Build and run (`Cmd + R`).

## Build And Test (CLI)

Show available destinations:

```bash
xcodebuild -project MeasureMe.xcodeproj -scheme MeasureMe -showdestinations
```

Build:

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

Run lint:

```bash
swiftlint lint --config .swiftlint.yml
```

## Release Validation

```bash
scripts/release_validation.sh show-test-plans
scripts/release_validation.sh analyze
scripts/release_validation.sh sim-regression
scripts/release_validation.sh device-ui 'platform=iOS,id=<device-id>' build/release-validation/session 1
scripts/release_validation.sh checkers-sim
scripts/release_validation.sh archive-rc
```

Detailed guide: `docs/release-validation.md`.

## Premium / StoreKit

Product identifiers:

- `com.measureme.premium.monthly`
- `com.measureme.premium.yearly`

StoreKit config files:

- `MeasureMe/Premium_local.storekit`
- `Premium.storekit`

## CI (GitHub Actions)

Workflow: `.github/workflows/ios-ci.yml`

- SwiftLint (changed-files check is blocking, full lint is non-blocking report)
- Build
- Analyze (non-blocking)
- Tests
- Matrix lanes for iOS `18.0` and `26.1` with runtime fallback/skip logic

## Privacy

- Data is stored on-device.
- App is offline-first by default.
- HealthKit access is optional and user-controlled.
- Export and sharing are user-initiated.

## License

This repository currently does not include a `LICENSE` file.
