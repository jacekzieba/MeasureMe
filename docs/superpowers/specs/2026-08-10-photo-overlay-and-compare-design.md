# Photo capture overlay control + Compare presentation race

Date: 2026-08-10

## Problem

Two independent defects in the Photos feature.

**1. The capture overlay is uncontrollable.** `GuidedCameraView` renders a ghost of a
previous photo at a fixed 18% opacity. `PhotoView` always passes `allPhotos.first` — the
single most recent photo — regardless of which pose the user is about to shoot. Shooting a
chest photo while a back photo is ghosted over the viewfinder is actively unhelpful, and
there is no way to change the ghost or turn it off.

**2. Compare sometimes needs two taps.** After selecting two photos and tapping Compare,
the app intermittently returns to the Photos screen; tapping Compare again works.

## Goals

- The user picks which pose the overlay shows, or turns the overlay off, from inside the
  camera. The choice persists between sessions.
- The user adjusts overlay opacity through three discrete levels.
- Compare opens on the first tap, from every entry point.

## Non-goals

- Front-facing camera support, overlay mirroring, or overlay pan/zoom.
- Changing the `CameraPickerView` retake path inside `AddPhotoView` (line 115).
- Reworking `AppSettingsStore`; the two new preferences are local UI state.
- Changing the 3×3 framing grid, which stays always-on.

---

## Part A — Overlay control

### A1. Overlay candidate selection (pure, testable)

New file `MeasureMe/Photos/PhotoOverlayCandidates.swift`.

```swift
enum PhotoOverlayCandidates {
    /// Most recent image data per primary pose tag.
    /// `photos` must be sorted by date descending.
    static func mostRecentByPose(in photos: [PhotoEntry]) -> [PhotoTag: Data]
}
```

Behaviour:

- Walks `photos` in order, and for each primary pose tag (`front`, `side`, `back`,
  `detail`) on a photo, records `thumbnailOrImageData` if that tag has no entry yet.
- A photo carrying several primary pose tags contributes to each of them.
- Stops early once all four poses are filled.
- Photos with no primary pose tag are skipped.
- Returns `[:]` for an empty input.

Callers must pass a date-descending array. `PhotoView`'s `@Query` is already
`SortDescriptor(\PhotoEntry.date, order: .reverse)`, which satisfies this; the requirement
is documented on the function.

### A2. `GuidedCameraView` API change

`MeasureMe/CameraPickerView.swift`:

```swift
GuidedCameraView(
    selectedImage: Binding<UIImage?>,
    selectedPose: Binding<PhotoTag?>,     // new — nil means "overlay off"
    overlayCandidates: [PhotoTag: Data]   // replaces overlayImageData: Data?
)
```

Both bindings are written before `dismiss()`, so `PhotoView`'s existing `onDismiss`
handler observes a consistent pair.

### A3. Camera UI

Added above the shutter button, inside the existing bottom `VStack`:

- **Pose pills:** `Off | Front | Side | Back | Detail`. Selecting a pose swaps the overlay
  immediately. Selecting `Off` hides the overlay and the opacity control.
- **Opacity button:** visible only when a pose is selected. Cycles three levels —
  **12% / 22% / 35%** — starting at 22%. (Today's fixed value is 18%; 22% becomes the new
  default.)
- **Hint text**, replacing the current unconditional "Match your last pose":
  - pose selected and a candidate exists → "Match your last pose"
  - pose selected and no candidate → "No photo for this pose yet — this will be your first"
  - `Off` → no hint
- The 3×3 grid is unchanged and always drawn.

All new strings go through `AppLocalization.string`. The pose pills carry accessibility
identifiers `photos.guidedCamera.pose.<rawValue>` and `photos.guidedCamera.pose.off`; the
opacity button uses `photos.guidedCamera.opacity`.

### A4. Persistence

Local `@AppStorage` in `GuidedCameraView`, matching the existing
`photos.gridLayoutMode` precedent in `PhotoView_Grid.swift:362`:

- `photos.overlayPose` — `String`, a `PhotoTag` raw value; `""` means off. Default `""`.
- `photos.overlayOpacityLevel` — `Int` in `0...2`, default `1` (22%). Values outside the
  range clamp to `1` on read.

Neither preference goes into `AppSettingsSnapshot`/`AppSettingsKeys`.

### A5. Pose hand-off to `AddPhotoView`

`AddPhotoView` gains one init parameter:

```swift
init(..., initialTags: Set<PhotoTag>? = nil, poseIsUserChosen: Bool = false, ...)
// _didUserChoosePose = State(initialValue: poseIsUserChosen)
```

`didUserChoosePose` already gates `applySuggestedPoseIfNeeded` (`AddPhotoView.swift:436`),
so seeding it `true` stops `PhotoPoseClassifier` from overwriting the user's choice. The
user can still change the tag by hand in the form.

`PhotoView` stores the captured pose alongside the captured image (`capturedImportPose`
next to the existing `capturedImportImage`) and passes it on:

- pose selected → `AddPhotoView(previewImage:, initialTags: [pose], poseIsUserChosen: true, telemetrySource: .photos)`
- `Off` → unchanged call, classifier behaves exactly as today

`PhotoView` computes `overlayCandidates` from `allPhotos` via `PhotoOverlayCandidates`.

---

## Part B — Compare presentation race

### B0. Extract the presentation decision so it can be tested

The existing `PhotoFlowUITests.testPhotoCompareExportLoopDoesNotCrash` already opens Compare
three times in a row and asserts the sheet appears each time — and it passes today, with the
bug present. A UI test cannot reliably pin an intermittent presentation race, so the decision
logic moves out of the view into a value type that can be tested directly.

New file `MeasureMe/Photos/ComparePresentation.swift` holds `PhotoComparePair` (moved
verbatim out of `PhotoView.swift`, its only consumer) plus:

```swift
struct ComparePresentationState {
    private(set) var active: PhotoComparePair?
    private(set) var pending: PhotoComparePair?

    mutating func request(_ pair: PhotoComparePair, presentedFromSheet: Bool)
    mutating func sheetDismissed()
    mutating func activeDismissed()
}
```

- `request(_:presentedFromSheet: false)` sets `active` immediately.
- `request(_:presentedFromSheet: true)` sets `pending` and leaves `active` untouched.
- `sheetDismissed()` promotes `pending` into `active` and clears `pending`; a no-op when
  `pending` is `nil`.
- `activeDismissed()` clears `active`, for the sheet-binding setter.

`PhotoView` keeps one `@State private var comparePresentation = ComparePresentationState()`
and binds the sheet to `active`.

### B1–B3 (applied through B0's type)

The remaining changes are in `MeasureMe/PhotoView.swift`.

### B1. Single-transaction state write

`openCompare` currently writes `selectedComparePair = nil` and then sets the real value
inside `Task { await Task.yield() }` — two state writes in two different update cycles.
It collapses to a single `comparePresentation.request(...)` call. The reset was there to
force re-presentation of an identical pair, which `PhotoComparePair.id` already handles: it
embeds a fresh `presentationID = UUID()` per instance, so every call produces a new sheet
identity.

The `@State private var selectedComparePair: PhotoComparePair?` is replaced by
`@State private var comparePresentation = ComparePresentationState()`, and the sheet binds
to a computed `Binding` whose getter returns `comparePresentation.active` and whose setter
calls `comparePresentation.activeDismissed()` when set to `nil`.

### B2. Remove the redundant reset

`.onDisappear { selectedComparePair = nil }` on the sheet content (`PhotoView.swift:327`)
is deleted. `.sheet(item:)` clears its own binding on dismissal, and this `onDisappear` can
fire during a presentation transition, tearing down a sheet that has just opened.

### B3. Explicit sheet-to-sheet hand-off

Two callers invoke `openCompare` while themselves presented as a sheet:

- `HomeCompareChooserSheet`'s completion (`PhotoView.swift:319`)
- `PhotoDetailView`'s `onCompareRequested` → `handlePhotoDetailCompareRequest`

They get an explicit signal instead of a guessed delay:

```swift
func openCompare(using older: PhotoEntry, _ newer: PhotoEntry, presentedFromSheet: Bool = false)
```

which forwards straight to `comparePresentation.request(pair, presentedFromSheet:)`. The
dismissing sheet's `onDismiss` calls `comparePresentation.sheetDismissed()`:

- `.sheet(item: $compareChooserContext, onDismiss: { comparePresentation.sheetDismissed() })`
- the detail sheet's existing `onDismiss` calls `refreshPhotoContent()` **and**
  `comparePresentation.sheetDismissed()`

`handlePhotoDetailCompareRequest` calls `openCompare(..., presentedFromSheet: true)` and
then clears `selectedPhotoForDetail`, so dismissal drives the presentation.

The premium guard at the top of `openCompare` is untouched.

---

## Verification

| Area | Check |
|---|---|
| `PhotoOverlayCandidates` | Unit tests: empty input; single pose; several photos sharing a pose (newest wins); one photo carrying multiple pose tags; photos with no primary pose tag ignored |
| Opacity level | Unit test: raw values `0`, `1`, `2` map to `12% / 22% / 35%`; out-of-range `-1` and `3` both fall back to `22%` |
| Pose hand-off | Unit test: `poseIsUserChosen: true` leaves `selectedTags` untouched after `applySuggestedPoseIfNeeded` |
| `ComparePresentationState` | Unit tests: direct request activates immediately; sheet-sourced request only parks a pending pair; `sheetDismissed` promotes it; `sheetDismissed` with nothing pending is a no-op; two requests for the same photos yield different `id`s |
| Compare | `PhotoFlowUITests.testPhotoCompareExportLoopDoesNotCrash` stays green (regression guard only — it passes with the bug present, so it is not the proof) |
| Regression | `ComparePhotosSnapshotTests` unchanged; full test plan green |
| Camera | Manual pass on the physical iPhone (the simulator has no camera, and `GuidedCameraView` is skipped in UI-test mode): each pose swaps the ghost, `Off` clears it, opacity cycles, choices survive an app restart, and the chosen pose lands preselected in `AddPhotoView` |

## Decisions taken

- `Off` means no overlay **and** no forced pose — the classifier keeps its current
  behaviour on that path.
- Opacity levels are 12% / 22% / 35%, defaulting to 22%, replacing the fixed 18%.
- `detail` is offered as a pose alongside `front`/`side`/`back`, matching
  `PhotoTag.primaryPoseTags`.
