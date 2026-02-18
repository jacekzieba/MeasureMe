# MeasureMe

MeasureMe is an iOS app for tracking body measurements, progress photos, and health-related trends in one place.
It is built for consistent check-ins, long-term progress tracking, and privacy-first use.

## Features

- Track body metrics (weight, waist, body fat, lean mass, and circumference)
- Fast logging with a Quick Add flow
- Set goals per metric and monitor progress
- Add progress photos and compare them side-by-side
- Optional HealthKit sync (opt-in)
- Reminder notifications
- AI Insights (premium + Apple Intelligence capable device)
- Data export from Settings (premium)
- English and Polish localization

## iOS Support

- Deployment target: iOS 17.2
- Recommended: latest iOS available for your device
- AI Insights availability: iOS 26+ with Apple Intelligence support

## Premium

Premium unlocks:

- AI Insights
- Health indicators
- Data export
- Photo comparison tools

StoreKit product identifiers:

- `com.measureme.premium.monthly`
- `com.measureme.premium.yearly`

Local StoreKit config included for testing:

- `MeasureMe/Premium.storekit`

## Tech Stack

- Swift + SwiftUI
- SwiftData
- HealthKit
- StoreKit 2
- Charts
- XCTest / XCUITest

## Project Structure

- `MeasureMe` - main application source
- `MeasureMeTests` - unit and snapshot tests
- `MeasureMeUITests` - UI tests
- `Assets.xcassets` - shared assets (icons/branding)
- `MeasureMe.xcodeproj` - Xcode project

## Getting Started

### Requirements

- macOS with Xcode
- Xcode 26.2+
- iOS Simulator or physical iPhone
- Apple Developer account (only for running on physical device with your own signing)

### Run Locally

```bash
open MeasureMe.xcodeproj
```

Then in Xcode:

1. Select the `MeasureMe` scheme.
2. Choose a simulator/device.
3. Build and run (`Cmd + R`).

## CLI Build / Test

Example simulator run:

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

Optional static analysis:

```bash
xcodebuild \
  -project MeasureMe.xcodeproj \
  -scheme MeasureMe \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.1' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  analyze
```

SwiftLint (repository config):

```bash
swiftlint lint --config .swiftlint.yml
```

## CI

GitHub Actions workflow (`.github/workflows/ios-ci.yml`) runs:

- SwiftLint (changed files as blocking + full report as non-blocking)
- Build
- Analyze (non-blocking)
- Tests
- Matrix lanes targeting iOS `18.x` and `26.1` (runtime-dependent fallback/skip handling)

## Privacy

- Data is stored on-device.
- App is offline-first.
- HealthKit access is optional and user-controlled.
- Export/sharing is user-initiated.

## License

No license file is currently included in this repository.
If you plan to publish this project publicly, add a `LICENSE` file to define usage terms.
