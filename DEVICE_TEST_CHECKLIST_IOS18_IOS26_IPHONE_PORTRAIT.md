# Device Test Checklist (iPhone, Portrait, iOS 18 + iOS 26)

## Devices / OS
- [ ] iPhone with iOS 18.x (real device)
- [ ] iPhone with iOS 26.x (real device)
- [ ] Test in portrait only

## First Launch / Onboarding
- [ ] App opens without crash.
- [ ] Onboarding appears once on first launch.
- [ ] Progress through all onboarding steps works in portrait.
- [ ] Premium slide CTA works and opens purchase flow.
- [ ] Polish copy shows `Sprawdz premium` in relevant premium CTA/card.

## Navigation / Layout
- [ ] Tab bar layout matches expected baseline.
- [ ] Tapping each tab works: Home / Measurements / Photos / Settings.
- [ ] Add (`+`) action opens composer/modal and returns correctly.
- [ ] No clipped controls or overlap in portrait on small and large iPhones.

## Purchase / Subscription
- [ ] Purchase flow starts and completes (sandbox account).
- [ ] Restore purchases works.
- [ ] Manage subscription link opens correctly.
- [ ] Paywall legal links open correctly: Terms of Use (Apple EULA) and Privacy Policy.
- [ ] Onboarding premium step shows and opens legal links: Terms of Use and Privacy Policy.
- [ ] Onboarding premium step Restore purchases action is visible and actionable.
- [ ] After trial activation, app asks again about reminder notifications (does not silently force preference).
- [ ] If permission denied, previous notifications preference remains unchanged.

## Notifications
- [ ] Notification permission prompt appears when expected.
- [ ] Weekly reminder can be scheduled.
- [ ] Trial ending reminder schedules only when notifications are enabled.
- [ ] Reminder toggles in Settings reflect real behavior.

## Health / Photos Permissions
- [ ] HealthKit permission prompt appears and returns safely on allow/deny.
- [ ] Photo library read and save permission flows work.
- [ ] Camera permission flow works.

## Accessibility (VoiceOver / Dynamic behavior)
- [ ] Premium close button is readable and actionable in VoiceOver.
- [ ] Decorative brand images are not redundantly announced.
- [ ] Setup checklist rows announce title + status (completed/incomplete/loading).
- [ ] Save-to-gallery button announces action clearly.

## Data / Stability
- [ ] Add/edit/delete measurement works.
- [ ] Photo add/delete/compare works.
- [ ] App relaunch preserves key state (onboarding complete, selected settings, reminders).
- [ ] No visible runtime error banners or stuck loading states in normal flows.

## Release Readiness
- [ ] Version/build numbers in Xcode match planned release.
- [ ] App Store metadata/screenshots reflect portrait iPhone experience.
- [ ] Privacy answers in App Store Connect match current implementation.
- [ ] Settings > App contains links for Terms of Use, Privacy Policy, Accessibility.
