# MeasureMe App Store Preflight (2026-02-12)

## Scope
- iPhone only (`TARGETED_DEVICE_FAMILY = 1`)
- Portrait only on iPhone (`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait`)
- iOS deployment target: `17.2` (covers iOS 18+ and iOS 26)

## Build and Tests
- Build: `xcodebuild ... -destination 'generic/platform=iOS' ... build` -> `BUILD SUCCEEDED`
- Tests: `xcodebuild ... -destination 'platform=iOS Simulator,id=34063F65-7421-40CA-8B19-B91EA6A70305' test` -> `TEST SUCCEEDED`
- Unit tests: 4 passed
- UI tests: 1 passed

## Privacy and Permissions
- Privacy manifest present: `MeasureMe/PrivacyInfo.xcprivacy`
  - Declares accessed API category: `UserDefaults` with reason `CA92.1`
  - Tracking disabled
  - No collected data types declared
- Entitlements present: `MeasureMe/MeasureMe.entitlements`
  - HealthKit enabled
  - HealthKit background delivery enabled
- Usage descriptions configured in build settings:
  - Camera
  - Health (read/write)
  - Photo Library (read/add)

## Purchase + Notification Behavior
- Post-purchase trial reminder flow now asks user again before enabling reminder notifications.
- Existing notification preference is preserved when user declines permission.
- Flow is handled via `RootView` dialog/alert and `PremiumStore` logic.

## Accessibility (implemented pass)
- Decorative branding images hidden from VoiceOver where appropriate.
- Added accessibility labels/hints for:
  - Premium close button
  - Save-to-gallery action
  - Setup checklist options/menu
  - Setup checklist completion state announcements

## Performance / Asset Hygiene
- Simplified brand SVG assets to avoid vector runtime issues (`CoreSVG` warning not reproduced after change).
- Removed duplicate app icon binaries (`LOGO 1.png`, `LOGO 2.png`) and unified references to `LOGO.png`.

## Residual Risk / Manual Verification Needed
- Final App Review compliance always requires manual validation on physical devices and App Store Connect checks.
- Recommended manual checks are listed in `DEVICE_TEST_CHECKLIST_IOS18_IOS26_IPHONE_PORTRAIT.md`.
