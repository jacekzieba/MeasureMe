# Visual QA Checklist (P1 PR4)

## Scope
- Dark mode only (`preferredColorScheme(.dark)` intentionally retained).
- Devices: `iPhone 17 Pro` + small device (`iPhone 16e`).
- Dynamic Type: default + `Accessibility XL`.

## Pre-flight
- Launch with deterministic flags:
  - `-auditCapture -useMockData -disableAnalytics -fixedDate 2026-02-20T12:00:00Z`
- Verify no random prompts/noise (review prompts, paywall nags, crash alert).
- Confirm stable seeded data order across two launches.

## Visual rhythm and consistency
- Spacing follows token scale (`4/8/12/16/24/32`) on:
  - Home cards
  - Measurements tiles
  - QuickAdd rows + save area
  - Settings rows
  - Onboarding cards
- Card elevation/border style is consistent per layer (no mixed shadows).
- Primary CTA and secondary CTA styles are consistent across flows.

## State components
- `EmptyStateCard` visible and readable for:
  - Measurements empty state
  - QuickAdd empty state
- `InlineErrorBanner` appears when invalid value entered in QuickAdd.
- `LoadingBlock` appears in premium loading path without layout jumps.

## Accessibility guards
- Min tap targets `>=44x44`:
  - `quickadd.save`
  - `onboarding.back`
  - `onboarding.next`
  - `onboarding.premium.trial`
- AXL does not clip critical controls on:
  - Measurements list
  - QuickAdd
  - Onboarding premium
- VoiceOver labels/value/hints present for custom controls:
  - Metrics section expand/collapse
  - Photo grid selection state

## Regression commands
- Snapshot suite:
  - `xcodebuild -project /Users/jacek/Desktop/MeasureMe/MeasureMe.xcodeproj -scheme MeasureMe -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:MeasureMeTests/P1DesignSystemSnapshotTests`
- UI regression suite:
  - `xcodebuild -project /Users/jacek/Desktop/MeasureMe/MeasureMe.xcodeproj -scheme MeasureMe -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:MeasureMeUITests/AuditCaptureUITests`
- Audit config unit tests:
  - `xcodebuild -project /Users/jacek/Desktop/MeasureMe/MeasureMe.xcodeproj -scheme MeasureMe -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:MeasureMeTests/AuditConfigTests`

## Exit criteria
- All tests above green.
- No clipping or overlap in core screens at default and AXL.
- No component style drift across Home/Measurements/QuickAdd/Photos/Settings/Onboarding.
