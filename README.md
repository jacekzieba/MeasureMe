# MeasureMe

MeasureMe is an iOS app for tracking body measurements, progress photos, and health-related trends in one place.  
It is designed for consistent check-ins, long-term progress tracking, and privacy-first use.

## Features

- Track body metrics (weight, waist, body fat, lean mass, and circumference measurements)
- View trends and progress over time
- Add and compare progress photos
- Optional HealthKit integration
- Quick Add flow for fast logging
- Goals per metric (increase/decrease with progress calculation)
- Weekly reminders and onboarding boosters
- Offline-first experience with on-device storage
- English and Polish localization

## iOS Support Policy

- Minimum supported OS: iOS 17.2
- Recommended OS: latest iOS available for your device
- AI Insights: requires Apple Intelligence support and iOS 26+ (feature is gated in-app)
- CI validates build/test on iOS 26.1 and attempts an iOS 18.x lane when that simulator runtime is available on the runner

### Premium Features

- AI Insights (requires Apple Intelligence support)
- Health indicators
- Data export
- Photo comparison tools

## Tech Stack

- Swift
- SwiftUI
- SwiftData
- HealthKit
- StoreKit 2
- Charts

## Project Structure

- `/MeasureMe` – main app source code
- `/Assets.xcassets` – shared assets (branding, onboarding, app icon)
- `/MeasureMe.xcodeproj` – Xcode project

## Getting Started

### Requirements

- macOS with Xcode installed
- Xcode 26.2 or newer
- iOS Simulator or physical iPhone for testing
- Apple Developer account (only if you want to run on a physical device with your own signing)

### Run Locally

1. Clone the repository:
   ```bash
   git clone <your-repo-url>
   cd MeasureMe
   ```
2. Open the project:
   ```bash
   open MeasureMe.xcodeproj
   ```
3. Select the `MeasureMe` scheme.
4. Choose a simulator or connected device.
5. Build and run (`Cmd + R`).

## Configuration Notes

- HealthKit is optional and can be skipped during onboarding.
- In-app purchases are configured with StoreKit product identifiers:
  - `com.measureme.premium.monthly`
  - `com.measureme.premium.yearly`
- Local StoreKit config files are included for testing:
  - `MeasureMe/Premium.storekit`
  - `MeasureMe/PremiumLocal.storekit`

## Privacy

- User data is stored on-device.
- The app is offline-first by default.
- HealthKit access is opt-in.
- Export/sharing is user-initiated.

## Status

This repository contains the active development codebase for MeasureMe.

## License

No license file is currently provided in this repository.  
If you plan to publish this project publicly, add a `LICENSE` file to define usage terms.
