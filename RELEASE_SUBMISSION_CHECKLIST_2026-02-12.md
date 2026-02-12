# MeasureMe Release Submission Checklist (2026-02-12)

## Build and Archive
- [x] Debug build passed.
- [x] Test suite passed (`MeasureMeTests` + `MeasureMeUITests` smoke).
- [x] Release archive created:
  - `/Users/jacek/Desktop/MeasureMe/.derivedData/MeasureMe-Release.xcarchive`

## App Configuration
- [x] Bundle ID: `com.jacek.measureme`
- [x] Version: `1.0`
- [x] Build: `1`
- [x] iPhone only (`TARGETED_DEVICE_FAMILY = 1`)
- [x] Portrait on iPhone (`UISupportedInterfaceOrientations~iphone = Portrait`)
- [x] Minimum iOS: `17.2`

## Privacy / Permissions
- [x] Privacy manifest present and bundled (`PrivacyInfo.xcprivacy`).
- [x] Usage descriptions present for Camera, Health (read/write), Photos (read/add).
- [x] HealthKit entitlements present.

## Purchases / Notifications / UX
- [x] Post-purchase reminder opt-in flow asks again and preserves prior notification preference if denied.
- [x] PL copy adjusted to `Sprawdz premium`.
- [x] Accessibility pass applied for premium close action, setup checklist, and save-photo action.

## Signing / Distribution Readiness
- [x] Archive signed successfully (development signing).
- [x] Embedded profile detected: `iOS Team Provisioning Profile: com.jacek.measureme`
  - Team: `K447N5AR8W`
  - Expires: `2026-02-16`
- [ ] Export for App Store Connect failed:
  - Command: `xcodebuild -exportArchive ...` (method `app-store-connect`)
  - Error: `No profiles for 'com.jacek.measureme' were found`
- [ ] Current embedded profile is **development** profile (`iOS Team Provisioning Profile: com.jacek.measureme`), not App Store distribution profile.

## Blocking Items Before Submission
1. Configure valid App Store distribution signing assets in Xcode (account/cert/profile).
2. Re-run archive in Release with distribution signing.
3. Re-run `xcodebuild -exportArchive` with `method=app-store-connect`.
4. Upload the exported build to App Store Connect.
