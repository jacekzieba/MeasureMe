# MeasureMe

MeasureMe is a privacy-first iOS and watchOS app for tracking body measurements, body-composition trends, goals, streaks, and progress photos.

The app is built around fast daily or weekly check-ins, long-term progress review, optional HealthKit sync, and companion surfaces such as widgets, App Shortcuts, Apple Watch, and watch complications.

## Current App Version

- iOS app: `1.4` (`15`)
- Widget extension: `1.4` (`14`)
- watchOS app and complications: `1.4` (`14`)

## Features

- Measurement tracking for weight, body fat, lean body mass, height, waist, neck, shoulders, bust, chest, arms, hips, thighs, and calves.
- Quick Add flows from the app, home screen quick actions, widgets, App Shortcuts, and Apple Watch.
- Goal tracking, streaks, trend summaries, charts, and prediction logic.
- Health indicators such as BMI, WHR, WHtR, conicity, and related physique indicators.
- Progress photo capture, import, tags, filters, timeline views, thumbnails, comparison, and transformation-card export.
- Optional HealthKit import/write sync for supported body metrics.
- Optional iCloud backup and restore flow.
- Premium capabilities including AI insights, advanced summaries, iCloud backup, exports, and comparison tooling.
- Home screen widgets for selected metrics, smart metric summaries, and streaks.
- Apple Watch app with quick logging, HealthKit write support, WatchConnectivity sync, and complications.
- App Intents and localized App Shortcuts.
- Localizations: English, Polish, German, Spanish, French, and Brazilian Portuguese.

## Platform

- iOS deployment target: `17.2`
- watchOS deployment target: `26.2`
- CI Xcode version: `26.2`
- CI simulator lanes: iOS `18.0` and `26.1` with runtime fallback/skip handling
- AI/Apple Intelligence-facing features require supported OS and device capabilities

## Tech Stack

- Swift and SwiftUI
- SwiftData
- HealthKit
- WidgetKit
- App Intents / App Shortcuts
- WatchConnectivity
- StoreKit / RevenueCat
- TelemetryDeck analytics
- XCTest, XCUITest, and Point-Free SnapshotTesting
- SwiftLint

## Targets And Schemes

Shared schemes live in `MeasureMe.xcodeproj/xcshareddata/xcschemes`.

- `MeasureMe` - main iOS app
- `MeasureMeWidget` - iOS WidgetKit extension
- `MeasureMeWatch Watch App` - watchOS companion app
- `MeasureMeWatchComplicationsExtension` - watchOS complications
- `MeasureMe Release Validation` - release validation scheme

## Repository Structure

- `MeasureMe/` - main iOS app source, SwiftData models, feature views, settings, services, App Intents, and localization files
- `MeasureMe/DesignSystem/` - shared UI tokens, control styles, state components, and design-system notes
- `MeasureMeWidget/` - WidgetKit providers, intents, views, and localized widget strings
- `MeasureMeWatch Watch App/` - watchOS app entry point, quick-add UI, WatchConnectivity, HealthKit writer, and localized watch strings
- `MeasureMeWatchComplications/` - WidgetKit complication bundle, provider, intents, and views
- `MeasureMeTests/` - unit tests, snapshot tests, data/import/export tests, and service tests
- `MeasureMeUITests/` - onboarding, quick-add, settings, photo flow, layout, and performance UI tests
- `MeasureMeWatch Watch AppTests/` and `MeasureMeWatch Watch AppUITests/` - watchOS test targets
- `Config/` - app and widget Info.plist files
- `TestPlans/` - release validation XCTest plan
- `scripts/` - local release-validation automation
- `.github/workflows/ios-ci.yml` - GitHub Actions CI pipeline
- `Assets.xcassets/` and target-specific asset catalogs - app icons, brand assets, widget/watch assets, and metric imagery

## Quick Start

### Requirements

- macOS with Xcode `26.2` or newer for parity with CI
- iOS Simulator or physical iPhone
- watchOS Simulator or Apple Watch for watch targets
- Apple Developer account for physical-device signing, HealthKit, widgets, watch app, and app-group entitlement testing
- SwiftLint for local lint checks

### Open In Xcode

```bash
open MeasureMe.xcodeproj
```

Then:

1. Select the `MeasureMe` scheme.
2. Select an iOS simulator or device.
3. Build and run with `Cmd + R`.

## Build And Test From CLI

Show available destinations:

```bash
xcodebuild -project MeasureMe.xcodeproj -scheme MeasureMe -showdestinations
```

Build the iOS app:

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

Run static analysis:

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

Build the widget:

```bash
xcodebuild \
  -project MeasureMe.xcodeproj \
  -scheme MeasureMeWidget \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.1' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Build the watch app:

```bash
xcodebuild \
  -project MeasureMe.xcodeproj \
  -scheme 'MeasureMeWatch Watch App' \
  -destination 'generic/platform=watchOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Release Validation

Local release checks are driven by `scripts/release_validation.sh` and `TestPlans/MeasureMe Release Validation.xctestplan`.

```bash
scripts/release_validation.sh show-test-plans
scripts/release_validation.sh analyze
scripts/release_validation.sh sim-regression
scripts/release_validation.sh device-ui 'platform=iOS,id=<device-id>' build/release-validation/session 1
scripts/release_validation.sh checkers-sim
scripts/release_validation.sh archive-rc
```

The validation script prints the expected arguments and creates artifacts under `build/release-validation/`.

## Premium And Billing

Billing is implemented through RevenueCat.

Product identifiers:

- `com.measureme.premium.monthly`
- `com.measureme.premium.yearly`

StoreKit configuration files:

- `MeasureMe/Premium_local.storekit`
- `Premium.storekit`

## CI

GitHub Actions workflow: `.github/workflows/ios-ci.yml`

The CI pipeline runs:

- SwiftLint on changed Swift files as a blocking check
- Full SwiftLint report as a non-blocking report
- Xcode setup for Xcode `26.2`
- Simulator destination resolution with runtime fallback
- Debug build
- Static analysis as a non-blocking check
- XCTest test run

## Privacy

- Measurement and photo data are stored on-device by default.
- HealthKit access is optional and user-controlled.
- iCloud backup is optional and handled by the app's custom backup flow.
- Exporting, sharing, and photo-library writes are user-initiated.
- The app disables SwiftData CloudKit sync and uses its own backup path instead.

## License

This repository currently does not include a `LICENSE` file.
