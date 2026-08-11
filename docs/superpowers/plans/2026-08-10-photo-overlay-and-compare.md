# Photo Overlay Control + Compare Presentation Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user choose which pose the camera ghost-overlay shows (or turn it off) and how strong it is, and make the Compare screen open on the first tap.

**Architecture:** Two independent slices. Slice A extracts overlay-candidate selection and opacity levels into pure value types, rewires `GuidedCameraView` to a pose picker driven by `@AppStorage`, and carries the chosen pose into `AddPhotoView` so the on-device pose classifier does not overwrite it. Slice B moves the Compare sheet's presentation decision out of `PhotoView` into a testable `ComparePresentationState` value type, removing the `nil` + `Task.yield()` double-write and a redundant `onDisappear` reset.

**Tech Stack:** Swift 6.4, SwiftUI, SwiftData, AVFoundation, XCTest. Xcode 27 beta only (see Global Constraints).

**Spec:** `docs/superpowers/specs/2026-08-10-photo-overlay-and-compare-design.md`

## Global Constraints

- Build/test from the CLI **must** be prefixed with `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. `xcode-select -p` points at CommandLineTools, which has no `xcodebuild`. Do not run `xcode-select -s` (needs the user's password).
- Simulator for all test runs: **iPhone 17 Pro, iOS 27.0, UDID `423D83EE-E5BE-42DC-A5F8-0B3EB62A0182`** (already booted). If booting fails with "cannot be located on disk", run `xcrun simctl erase <udid> && xcrun simctl boot <udid>`.
- **Snapshot tests fail on iOS 27.0 regardless of this work** — roughly 20 across `HomeViewSnapshotTests`, `MetricDetailSnapshotTests`, `HealthIndicatorDetailSnapshotTests`, `ExperienceSettingsDetailViewSnapshotTests`, `DataSettingsDetailViewSnapshotTests`, `ComparePhotosSnapshotTests`, `OnboardingSnapshotTests`. Pre-existing runtime mismatch, not a regression. Judge by non-snapshot tests.
- Every new user-facing string goes through `AppLocalization.string(...)` and **must** be added to all six files `MeasureMe/{en,pl,es,de,fr,pt-BR}.lproj/Localizable.strings` with identical key sets. `LocalizationConsistencyTests` fails the build otherwise, and also fails on any empty value.
- Targets use `PBXFileSystemSynchronizedRootGroup`. New files placed in `MeasureMe/` or `MeasureMeTests/` are picked up automatically — **never** hand-edit `MeasureMe.xcodeproj/project.pbxproj`.
- New test files follow the existing header convention: a `///` block with `Cel testu:`, `Dlaczego to ważne:`, `Kryteria zaliczenia:` before the imports. Tests are XCTest (`final class ...: XCTestCase`), not swift-testing.
- All measurement values stay in metric units internally; not touched by this work.
- Branch is already created: `feat/photo-overlay-control-and-compare-fix`. Commit on it; do not merge to `main`.

---

## File Structure

**Create:**
- `MeasureMe/Photos/PhotoOverlayCandidates.swift` — `PhotoOverlayCandidates` (most-recent image per pose) and `CameraOverlayOpacity` (three discrete levels). Both pure; no SwiftUI, no AVFoundation.
- `MeasureMe/Photos/ComparePresentation.swift` — `PhotoComparePair` (moved out of `PhotoView.swift`) and `ComparePresentationState` (active/pending presentation decision).
- `MeasureMeTests/PhotoOverlayCandidatesTests.swift`
- `MeasureMeTests/ComparePresentationStateTests.swift`
- `MeasureMeTests/AddPhotoPoseHandoffTests.swift`

**Modify:**
- `MeasureMe/CameraPickerView.swift:154-257` — `GuidedCameraView`: new API, pose pill bar, opacity cycle button, conditional hint.
- `MeasureMe/Photos/AddPhotoView.swift:33,44-64` — `poseIsUserChosen` init parameter seeding `didUserChoosePose`.
- `MeasureMe/PhotoView.swift` — overlay candidates + captured pose plumbing (lines ~28-37, ~246-270), Compare presentation state (lines ~311-338, ~396-408, ~465-483), removal of the old `PhotoComparePair` declaration (lines ~485-493).
- `MeasureMe/{en,pl,es,de,fr,pt-BR}.lproj/Localizable.strings` — three new keys.

---

## Task 1: Overlay candidate selection and opacity levels

Pure value types with no dependency on the rest of the work. Nothing else in the plan compiles against `PhotoView` yet, so this task stands alone.

**Files:**
- Create: `MeasureMe/Photos/PhotoOverlayCandidates.swift`
- Test: `MeasureMeTests/PhotoOverlayCandidatesTests.swift`

**Interfaces:**
- Consumes: `PhotoEntry` (`MeasureMe/PhotoEntry.swift`), `PhotoTag` and `PhotoTag.primaryPoseTags` / `isPrimaryPose` (`MeasureMe/PhotoTag.swift`).
- Produces:
  - `PhotoOverlayCandidates.mostRecentByPose(in photos: [PhotoEntry]) -> [PhotoTag: Data]`
  - `enum CameraOverlayOpacity: Int, CaseIterable { case light = 0, medium = 1, strong = 2 }`
  - `CameraOverlayOpacity.init(storedValue: Int)` — clamps out-of-range to `.medium`
  - `CameraOverlayOpacity.value: Double` — `0.12 / 0.22 / 0.35`
  - `CameraOverlayOpacity.next: CameraOverlayOpacity` — wraps `strong -> light`

- [ ] **Step 1: Write the failing tests**

Create `MeasureMeTests/PhotoOverlayCandidatesTests.swift`:

```swift
/// Cel testu: Weryfikuje wybór zdjęcia-overlaya dla każdej pozy oraz poziomy krycia overlaya w aparacie.
/// Dlaczego to ważne: Overlay pokazywał zawsze najnowsze zdjęcie niezależnie od pozy — ta logika
/// decyduje, że użytkownik widzi ghost właściwej pozy albo nie widzi żadnego.
/// Kryteria zaliczenia: Najnowsze zdjęcie wygrywa w obrębie pozy, tagi niepozowe są ignorowane,
/// a poziomy krycia mapują się na 12/22/35% z bezpiecznym fallbackiem.

@testable import MeasureMe

import XCTest

final class PhotoOverlayCandidatesTests: XCTestCase {

    private func makePhoto(
        marker: UInt8,
        daysAgo: Int,
        tags: [PhotoTag]
    ) -> PhotoEntry {
        PhotoEntry(
            imageData: Data([marker]),
            date: Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(-Double(daysAgo) * 86_400),
            tags: tags
        )
    }

    func testMostRecentByPose_emptyInput_returnsEmpty() {
        XCTAssertTrue(PhotoOverlayCandidates.mostRecentByPose(in: []).isEmpty)
    }

    func testMostRecentByPose_newestPhotoWinsWithinPose() {
        // Kolejność malejąca po dacie, tak jak @Query w PhotoView.
        let photos = [
            makePhoto(marker: 1, daysAgo: 1, tags: [.back]),
            makePhoto(marker: 2, daysAgo: 5, tags: [.back]),
            makePhoto(marker: 3, daysAgo: 9, tags: [.front]),
        ]

        let candidates = PhotoOverlayCandidates.mostRecentByPose(in: photos)

        XCTAssertEqual(candidates[.back], Data([1]))
        XCTAssertEqual(candidates[.front], Data([3]))
        XCTAssertNil(candidates[.side])
        XCTAssertNil(candidates[.detail])
    }

    func testMostRecentByPose_photoWithSeveralPosesFillsEachOfThem() {
        let photos = [makePhoto(marker: 7, daysAgo: 0, tags: [.front, .side])]

        let candidates = PhotoOverlayCandidates.mostRecentByPose(in: photos)

        XCTAssertEqual(candidates[.front], Data([7]))
        XCTAssertEqual(candidates[.side], Data([7]))
    }

    func testMostRecentByPose_ignoresNonPrimaryPoseTags() {
        let photos = [makePhoto(marker: 4, daysAgo: 0, tags: [.waist, .wholeBody])]

        XCTAssertTrue(PhotoOverlayCandidates.mostRecentByPose(in: photos).isEmpty)
    }

    func testMostRecentByPose_prefersThumbnailOverFullImage() {
        let photo = PhotoEntry(
            imageData: Data([9, 9, 9]),
            thumbnailData: Data([1]),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [.front]
        )

        XCTAssertEqual(PhotoOverlayCandidates.mostRecentByPose(in: [photo])[.front], Data([1]))
    }

    func testOverlayOpacity_valuesAndFallback() {
        XCTAssertEqual(CameraOverlayOpacity.light.value, 0.12, accuracy: 0.0001)
        XCTAssertEqual(CameraOverlayOpacity.medium.value, 0.22, accuracy: 0.0001)
        XCTAssertEqual(CameraOverlayOpacity.strong.value, 0.35, accuracy: 0.0001)

        XCTAssertEqual(CameraOverlayOpacity(storedValue: 0), .light)
        XCTAssertEqual(CameraOverlayOpacity(storedValue: 1), .medium)
        XCTAssertEqual(CameraOverlayOpacity(storedValue: 2), .strong)
        XCTAssertEqual(CameraOverlayOpacity(storedValue: -1), .medium)
        XCTAssertEqual(CameraOverlayOpacity(storedValue: 3), .medium)
    }

    func testOverlayOpacity_nextWrapsAround() {
        XCTAssertEqual(CameraOverlayOpacity.light.next, .medium)
        XCTAssertEqual(CameraOverlayOpacity.medium.next, .strong)
        XCTAssertEqual(CameraOverlayOpacity.strong.next, .light)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/PhotoOverlayCandidatesTests 2>&1 | tail -30
```

Expected: compilation failure — `cannot find 'PhotoOverlayCandidates' in scope` and `cannot find type 'CameraOverlayOpacity' in scope`.

- [ ] **Step 3: Write the implementation**

Create `MeasureMe/Photos/PhotoOverlayCandidates.swift`:

```swift
import Foundation

/// Wybiera zdjęcie-overlay dla każdej z głównych póz.
enum PhotoOverlayCandidates {

    /// Najnowsze dane obrazu dla każdej z póz `PhotoTag.primaryPoseTags`.
    /// - Parameter photos: lista posortowana malejąco po dacie.
    static func mostRecentByPose(in photos: [PhotoEntry]) -> [PhotoTag: Data] {
        var result: [PhotoTag: Data] = [:]

        for photo in photos {
            for tag in photo.tags where tag.isPrimaryPose && result[tag] == nil {
                result[tag] = photo.thumbnailOrImageData
            }
            if result.count == PhotoTag.primaryPoseTags.count { break }
        }

        return result
    }
}

/// Trzy poziomy krycia ghost-overlaya w aparacie.
enum CameraOverlayOpacity: Int, CaseIterable {
    case light = 0
    case medium = 1
    case strong = 2

    init(storedValue: Int) {
        self = CameraOverlayOpacity(rawValue: storedValue) ?? .medium
    }

    var value: Double {
        switch self {
        case .light: return 0.12
        case .medium: return 0.22
        case .strong: return 0.35
        }
    }

    var next: CameraOverlayOpacity {
        CameraOverlayOpacity(rawValue: (rawValue + 1) % CameraOverlayOpacity.allCases.count) ?? .light
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/PhotoOverlayCandidatesTests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, 7 tests passing.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/Photos/PhotoOverlayCandidates.swift MeasureMeTests/PhotoOverlayCandidatesTests.swift
git commit -m "feat(photos): add per-pose overlay candidate selection and opacity levels"
```

---

## Task 2: Localized strings for the camera overlay controls

Separate from Task 3 so that a localization mistake fails on its own test, not inside a UI change.

**Files:**
- Modify: `MeasureMe/en.lproj/Localizable.strings`
- Modify: `MeasureMe/pl.lproj/Localizable.strings`
- Modify: `MeasureMe/es.lproj/Localizable.strings`
- Modify: `MeasureMe/de.lproj/Localizable.strings`
- Modify: `MeasureMe/fr.lproj/Localizable.strings`
- Modify: `MeasureMe/pt-BR.lproj/Localizable.strings`
- Test: `MeasureMeTests/LocalizationConsistencyTests.swift` (existing, unmodified)

**Interfaces:**
- Produces: three keys consumed by Task 3 — `"camera.overlay.off"`, `"camera.overlay.noPhotoForPose"`, `"camera.overlay.opacity"`.

Note the existing key `"Match your last pose"` is already present in all six files and is reused as-is.

- [ ] **Step 1: Append the English keys**

Append to the end of `MeasureMe/en.lproj/Localizable.strings`:

```
// Camera overlay controls
"camera.overlay.off" = "Off";
"camera.overlay.noPhotoForPose" = "No photo for this pose yet — this will be your first";
"camera.overlay.opacity" = "Overlay opacity";
```

- [ ] **Step 2: Append the same keys to the other five files**

`MeasureMe/pl.lproj/Localizable.strings`:

```
// Camera overlay controls
"camera.overlay.off" = "Wył.";
"camera.overlay.noPhotoForPose" = "Brak zdjęcia dla tej pozy — to będzie pierwsze";
"camera.overlay.opacity" = "Krycie nakładki";
```

`MeasureMe/es.lproj/Localizable.strings`:

```
// Camera overlay controls
"camera.overlay.off" = "No";
"camera.overlay.noPhotoForPose" = "Aún no hay foto para esta pose: esta será la primera";
"camera.overlay.opacity" = "Opacidad de la superposición";
```

`MeasureMe/de.lproj/Localizable.strings`:

```
// Camera overlay controls
"camera.overlay.off" = "Aus";
"camera.overlay.noPhotoForPose" = "Noch kein Foto für diese Pose – das wird dein erstes";
"camera.overlay.opacity" = "Deckkraft der Überlagerung";
```

`MeasureMe/fr.lproj/Localizable.strings`:

```
// Camera overlay controls
"camera.overlay.off" = "Aucun";
"camera.overlay.noPhotoForPose" = "Aucune photo pour cette pose — ce sera la première";
"camera.overlay.opacity" = "Opacité du calque";
```

`MeasureMe/pt-BR.lproj/Localizable.strings`:

```
// Camera overlay controls
"camera.overlay.off" = "Desl.";
"camera.overlay.noPhotoForPose" = "Ainda não há foto para esta pose — esta será a primeira";
"camera.overlay.opacity" = "Opacidade da sobreposição";
```

- [ ] **Step 3: Run the localization tests and confirm they pass**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/LocalizationConsistencyTests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`. A failure listing `Missing: camera.overlay...` means one of the six files was skipped.

- [ ] **Step 4: Commit**

```bash
git add MeasureMe/en.lproj/Localizable.strings MeasureMe/pl.lproj/Localizable.strings MeasureMe/es.lproj/Localizable.strings MeasureMe/de.lproj/Localizable.strings MeasureMe/fr.lproj/Localizable.strings MeasureMe/pt-BR.lproj/Localizable.strings
git commit -m "i18n: add camera overlay control strings"
```

---

## Task 3: Camera pose picker and opacity control

Rewrites `GuidedCameraView`'s API and chrome, and updates its single call site so the commit builds. It has no unit test of its own — `GuidedCameraView` owns an `AVCaptureSession` and is skipped entirely in UI-test mode — so its gate is a clean build plus the manual device pass in Task 6. Its testable logic already lives in Task 1.

**Files:**
- Modify: `MeasureMe/CameraPickerView.swift:154-257`
- Modify: `MeasureMe/PhotoView.swift` (state block ~line 29, computed properties ~line 53, camera sheet ~lines 246-263)

**Interfaces:**
- Consumes: `PhotoOverlayCandidates.mostRecentByPose(in:)` and `CameraOverlayOpacity` from Task 1; the three keys from Task 2; `PhotoTag.primaryPoseTags`, `PhotoTag.title` (`MeasureMe/PhotoTag.swift`).
- Produces: the new `GuidedCameraView` signature, plus `PhotoView.cameraPickerPose` and `PhotoView.overlayCandidates`, all consumed by Task 4:

```swift
GuidedCameraView(
    selectedImage: Binding<UIImage?>,
    selectedPose: Binding<PhotoTag?>,
    overlayCandidates: [PhotoTag: Data]
)
```

- [ ] **Step 1: Replace the `GuidedCameraView` struct**

In `MeasureMe/CameraPickerView.swift`, replace the whole `struct GuidedCameraView: View { ... }` block (currently lines 154-257, ending just before `private struct GuidedCameraGrid`) with:

```swift
struct GuidedCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedImage: UIImage?
    @Binding var selectedPose: PhotoTag?
    let overlayCandidates: [PhotoTag: Data]

    @AppStorage("photos.overlayPose") private var storedOverlayPose: String = ""
    @AppStorage("photos.overlayOpacityLevel") private var storedOpacityLevel: Int = CameraOverlayOpacity.medium.rawValue

    @StateObject private var camera = GuidedCameraController()

    private var activePose: PhotoTag? {
        guard let pose = PhotoTag(rawValue: storedOverlayPose), pose.isPrimaryPose else { return nil }
        return pose
    }

    private var overlayOpacity: CameraOverlayOpacity {
        CameraOverlayOpacity(storedValue: storedOpacityLevel)
    }

    private var overlayImage: UIImage? {
        guard let activePose, let data = overlayCandidates[activePose] else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        ZStack {
            GuidedCameraPreview(session: camera.session)
                .ignoresSafeArea()

            if let overlayImage {
                Image(uiImage: overlayImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(overlayOpacity.value)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            GuidedCameraGrid()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Button(AppLocalization.string("Cancel")) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.45))

                    Spacer()

                    if activePose != nil {
                        opacityButton
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 14) {
                    if let hintText {
                        Text(hintText)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.smmd)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.45), in: Capsule())
                    }

                    poseBar

                    Button {
                        selectedPose = activePose
                        camera.capture()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 78, height: 78)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 62, height: 62)
                        }
                    }
                    .disabled(camera.isCapturing)
                    .accessibilityIdentifier("photos.guidedCamera.capture")
                    .accessibilityLabel(AppLocalization.string("Take Photo"))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 32)
            }
        }
        .background(Color.black)
        .task {
            await camera.requestAndStart()
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: camera.capturedImage) { _, image in
            guard let image else { return }
            selectedImage = image
            dismiss()
        }
        .overlay {
            if let errorMessage = camera.errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .font(AppTypography.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button(AppLocalization.string("Close")) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(AppSpacing.lg)
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
                .padding()
            }
        }
    }

    private var hintText: String? {
        guard let activePose else { return nil }
        if overlayCandidates[activePose] != nil {
            return AppLocalization.string("Match your last pose")
        }
        return AppLocalization.string("camera.overlay.noPhotoForPose")
    }

    private var opacityButton: some View {
        Button {
            storedOpacityLevel = overlayOpacity.next.rawValue
        } label: {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(Color.black.opacity(0.45), in: Circle())
        }
        .accessibilityIdentifier("photos.guidedCamera.opacity")
        .accessibilityLabel(AppLocalization.string("camera.overlay.opacity"))
    }

    private var poseBar: some View {
        HStack(spacing: 6) {
            poseButton(title: AppLocalization.string("camera.overlay.off"), pose: nil)
            ForEach(PhotoTag.primaryPoseTags) { pose in
                poseButton(title: pose.title, pose: pose)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.45), in: Capsule())
    }

    private func poseButton(title: String, pose: PhotoTag?) -> some View {
        let isSelected = activePose == pose
        return Button {
            storedOverlayPose = pose?.rawValue ?? ""
        } label: {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isSelected ? Color.white : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photos.guidedCamera.pose.\(pose?.rawValue ?? "off")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
```

- [ ] **Step 2: Update the single call site so the commit builds**

`GuidedCameraView` has exactly one call site, in `MeasureMe/PhotoView.swift`. Three edits there.

First, add the pose state directly after the existing `@State private var cameraPickerImage: UIImage? = nil` (line 28):

```swift
    @State private var cameraPickerPose: PhotoTag? = nil
```

Second, add a computed property right after `canDisplayPhotos` (around line 53):

```swift
    private var overlayCandidates: [PhotoTag: Data] {
        PhotoOverlayCandidates.mostRecentByPose(in: allPhotos)
    }
```

Third, replace the `GuidedCameraView(...)` call inside the camera sheet (currently lines 255-258) with:

```swift
                    GuidedCameraView(
                        selectedImage: $cameraPickerImage,
                        selectedPose: $cameraPickerPose,
                        overlayCandidates: overlayCandidates
                    )
```

Leave the sheet's `onDismiss` closure alone — Task 4 extends it to carry the pose into the form.

- [ ] **Step 3: Build and confirm it is clean**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild build -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' 2>&1 | grep -E "error:|BUILD" | head -20
```

Expected: `** BUILD SUCCEEDED **` and no `error:` lines.

Swift will warn that `cameraPickerPose` is written but never read — that is expected at this point; Task 4 reads it. Do not silence the warning with `_ =` or by deleting the property.

- [ ] **Step 4: Commit**

```bash
git add MeasureMe/CameraPickerView.swift MeasureMe/PhotoView.swift
git commit -m "feat(camera): pose picker and opacity control for the capture overlay"
```

---

## Task 4: Wire the camera into PhotoView and hand the pose to AddPhotoView

Closes the API change from Task 3 and delivers the first working slice: choosing a pose in the camera changes the ghost and preselects the tag in the form.

**Files:**
- Modify: `MeasureMe/Photos/AddPhotoView.swift:33,44-64`
- Modify: `MeasureMe/PhotoView.swift` (state block ~lines 28-37, camera sheet ~lines 246-270)
- Test: `MeasureMeTests/AddPhotoPoseHandoffTests.swift`

**Interfaces:**
- Consumes: `GuidedCameraView(selectedImage:selectedPose:overlayCandidates:)` from Task 3; `PhotoOverlayCandidates.mostRecentByPose(in:)` from Task 1.
- Produces: `AddPhotoView.init(..., initialTags: Set<PhotoTag>? = nil, poseIsUserChosen: Bool = false, ...)`.

- [ ] **Step 1: Write the failing test**

Create `MeasureMeTests/AddPhotoPoseHandoffTests.swift`:

```swift
/// Cel testu: Weryfikuje, że poza wybrana ręcznie w aparacie nie jest nadpisywana przez klasyfikator pozy.
/// Dlaczego to ważne: Użytkownik deklaruje pozę przed zdjęciem (steruje nią overlay); automat nie może
/// tej decyzji cofnąć w formularzu dodawania zdjęcia.
/// Kryteria zaliczenia: Z poseIsUserChosen == true tagi po applySuggestedPoseIfNeeded się nie zmieniają,
/// a bez tej flagi klasyfikator może je podmienić.

@testable import MeasureMe

import XCTest
import SwiftUI

@MainActor
final class AddPhotoPoseHandoffTests: XCTestCase {

    private func makeSolidImage() -> UIImage {
        let size = CGSize(width: 64, height: 64)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testUserChosenPoseSurvivesTheClassifier() async {
        let view = AddPhotoView(
            previewImage: makeSolidImage(),
            initialTags: [.back],
            poseIsUserChosen: true
        )

        await view.applySuggestedPoseIfNeeded(from: makeSolidImage())

        XCTAssertEqual(view.selectedTags, [.back])
    }

    func testDefaultConstructionLeavesTheClassifierEnabled() {
        let view = AddPhotoView(previewImage: makeSolidImage(), initialTags: [.back])

        XCTAssertFalse(view.didUserChoosePose)
        XCTAssertEqual(view.selectedTags, [.back])
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/AddPhotoPoseHandoffTests 2>&1 | tail -30
```

Expected: three compilation errors — `extra argument 'poseIsUserChosen' in call`, plus `'selectedTags' is inaccessible due to 'private' protection level` and the same for `'didUserChoosePose'`. (Verified against the current tree: `@testable import` reaches `internal`, not `private`, and both are `@State private var`.)

- [ ] **Step 3: Expose the two state properties to the test target**

In `MeasureMe/Photos/AddPhotoView.swift`, drop `private` from exactly these two declarations (lines 28 and 33) and nothing else:

```swift
    /// Widoczne dla testów (AddPhotoPoseHandoffTests) — poza tym traktuj jak prywatne.
    @State var selectedTags: Set<PhotoTag> = [.front]
```

```swift
    /// Widoczne dla testów (AddPhotoPoseHandoffTests) — poza tym traktuj jak prywatne.
    @State var didUserChoosePose = false
```

`applySuggestedPoseIfNeeded` (line 434) is already internal; leave it alone.

- [ ] **Step 4: Add the `poseIsUserChosen` parameter**

In `MeasureMe/Photos/AddPhotoView.swift`, add the parameter to `init` after `initialTags` and seed the state. The init becomes:

```swift
    init(
        previewImage: UIImage? = nil,
        previewSource: PhotoLibraryImageSource? = nil,
        initialDate: Date? = nil,
        initialTags: Set<PhotoTag>? = nil,
        poseIsUserChosen: Bool = false,
        initialMetricValues: [MetricKind: Double] = [:],
        telemetrySource: PhotoTelemetrySource = .photos,
        onPreparedForBatch: ((PreparedPhotoDraft) -> Void)? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.initialPreviewSource = previewSource
        self.shouldApplyInitialSourceDate = initialDate == nil
        self.onPreparedForBatch = onPreparedForBatch
        self.onSaved = onSaved
        self.telemetrySource = telemetrySource
        self._selectedImage = State(initialValue: previewImage)
        self._isLoadingPreview = State(initialValue: previewImage == nil && previewSource != nil)
        self._date = State(initialValue: initialDate ?? AppClock.now)
        self._selectedTags = State(initialValue: initialTags ?? [.front])
        self._didUserChoosePose = State(initialValue: poseIsUserChosen)
        self._metricValues = State(initialValue: initialMetricValues)
    }
```

- [ ] **Step 5: Run the test and confirm it passes**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/AddPhotoPoseHandoffTests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, 2 tests passing.

- [ ] **Step 6: Add the captured-pose state to PhotoView**

Task 3 already added `cameraPickerPose` and the `overlayCandidates` computed property — do not add them again. In `MeasureMe/PhotoView.swift`, add one more property directly after the existing `@State private var capturedImportImage: UIImage? = nil`:

```swift
    @State private var capturedImportPose: PhotoTag? = nil
```

- [ ] **Step 7: Carry the pose out of the camera sheet**

In `MeasureMe/PhotoView.swift`, replace the camera sheet block (starting `.sheet(isPresented: $showCamera, onDismiss: {`) with the version below. Only the `onDismiss` closure changes; the content closure is what Task 3 left:

```swift
            .sheet(isPresented: $showCamera, onDismiss: {
                if let img = cameraPickerImage {
                    capturedImportImage = img
                    capturedImportPose = cameraPickerPose
                    showCapturedImportSheet = true
                    cameraPickerImage = nil
                }
                cameraPickerPose = nil
            }) {
                if UIImagePickerController.isSourceTypeAvailable(.camera), !uiTestModeEnabled {
                    GuidedCameraView(
                        selectedImage: $cameraPickerImage,
                        selectedPose: $cameraPickerPose,
                        overlayCandidates: overlayCandidates
                    )
                } else {
                    CameraPickerView(selectedImage: $cameraPickerImage)
                }
            }
```

- [ ] **Step 8: Pass the pose into AddPhotoView**

In `MeasureMe/PhotoView.swift`, replace the captured-import sheet block (currently lines 264-271, starting `.sheet(isPresented: $showCapturedImportSheet, onDismiss: {`) with:

```swift
            .sheet(isPresented: $showCapturedImportSheet, onDismiss: {
                capturedImportImage = nil
                capturedImportPose = nil
            }) {
                NavigationStack {
                    AddPhotoView(
                        previewImage: capturedImportImage,
                        initialTags: capturedImportPose.map { [$0] },
                        poseIsUserChosen: capturedImportPose != nil,
                        telemetrySource: .photos
                    )
                        .environmentObject(metricsStore)
                }
            }
```

- [ ] **Step 9: Build and confirm it is clean**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild build -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' 2>&1 | grep -E "error:|BUILD" | head -20
```

Expected: `** BUILD SUCCEEDED **` and no `error:` lines.

- [ ] **Step 10: Commit**

```bash
git add MeasureMe/Photos/AddPhotoView.swift MeasureMe/PhotoView.swift MeasureMeTests/AddPhotoPoseHandoffTests.swift
git commit -m "feat(photos): carry the camera pose into the add-photo form"
```

---

## Task 5: Compare presentation state

Independent of Tasks 1-4. Fixes the double-tap defect.

**Files:**
- Create: `MeasureMe/Photos/ComparePresentation.swift`
- Modify: `MeasureMe/PhotoView.swift` (state ~line 37, sheets ~lines 311-338, `openCompare` ~lines 396-408, `handlePhotoDetailCompareRequest` ~line 472, `PhotoComparePair` declaration ~lines 485-493)
- Test: `MeasureMeTests/ComparePresentationStateTests.swift`

**Interfaces:**
- Consumes: `PhotoEntry`.
- Produces: `PhotoComparePair` (relocated, unchanged shape) and `ComparePresentationState` with `active`, `pending`, `request(_:presentedFromSheet:)`, `sheetDismissed()`, `activeDismissed()`.

- [ ] **Step 1: Write the failing test**

Create `MeasureMeTests/ComparePresentationStateTests.swift`:

```swift
/// Cel testu: Weryfikuje decyzję o prezentacji ekranu porównania — natychmiast albo po zamknięciu
/// poprzedniego sheeta.
/// Dlaczego to ważne: Compare bywał otwierany dopiero za drugim naciśnięciem, bo stan był zapisywany
/// w dwóch osobnych cyklach aktualizacji. Ta logika zastępuje tamten wyścig.
/// Kryteria zaliczenia: Żądanie spoza sheeta aktywuje od razu, żądanie z sheeta czeka na dismiss,
/// a każde żądanie tworzy nową tożsamość prezentacji.

@testable import MeasureMe

import XCTest

final class ComparePresentationStateTests: XCTestCase {

    private func makePair() -> PhotoComparePair {
        let older = PhotoEntry(
            imageData: Data([1]),
            date: Date(timeIntervalSince1970: 1_600_000_000),
            tags: [.front]
        )
        let newer = PhotoEntry(
            imageData: Data([2]),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [.front]
        )
        return PhotoComparePair(olderPhoto: older, newerPhoto: newer)
    }

    func testDirectRequestActivatesImmediately() {
        var state = ComparePresentationState()
        let pair = makePair()

        state.request(pair, presentedFromSheet: false)

        XCTAssertEqual(state.active?.id, pair.id)
        XCTAssertNil(state.pending)
    }

    func testSheetSourcedRequestOnlyParksPending() {
        var state = ComparePresentationState()
        let pair = makePair()

        state.request(pair, presentedFromSheet: true)

        XCTAssertNil(state.active)
        XCTAssertEqual(state.pending?.id, pair.id)
    }

    func testSheetDismissedPromotesPending() {
        var state = ComparePresentationState()
        let pair = makePair()
        state.request(pair, presentedFromSheet: true)

        state.sheetDismissed()

        XCTAssertEqual(state.active?.id, pair.id)
        XCTAssertNil(state.pending)
    }

    func testSheetDismissedWithoutPendingIsNoOp() {
        var state = ComparePresentationState()

        state.sheetDismissed()

        XCTAssertNil(state.active)
        XCTAssertNil(state.pending)
    }

    func testSheetDismissedDoesNotClobberAnActivePair() {
        var state = ComparePresentationState()
        let pair = makePair()
        state.request(pair, presentedFromSheet: false)

        state.sheetDismissed()

        XCTAssertEqual(state.active?.id, pair.id)
    }

    func testActiveDismissedClearsActive() {
        var state = ComparePresentationState()
        state.request(makePair(), presentedFromSheet: false)

        state.activeDismissed()

        XCTAssertNil(state.active)
    }

    func testRepeatedRequestForTheSamePhotosProducesANewIdentity() {
        var state = ComparePresentationState()
        let older = PhotoEntry(
            imageData: Data([1]),
            date: Date(timeIntervalSince1970: 1_600_000_000),
            tags: [.front]
        )
        let newer = PhotoEntry(
            imageData: Data([2]),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [.front]
        )

        state.request(PhotoComparePair(olderPhoto: older, newerPhoto: newer), presentedFromSheet: false)
        let firstID = state.active?.id
        state.activeDismissed()
        state.request(PhotoComparePair(olderPhoto: older, newerPhoto: newer), presentedFromSheet: false)

        XCTAssertNotNil(firstID)
        XCTAssertNotEqual(firstID, state.active?.id)
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/ComparePresentationStateTests 2>&1 | tail -30
```

Expected: compilation failure — `cannot find type 'ComparePresentationState' in scope`.

- [ ] **Step 3: Create the new file**

Create `MeasureMe/Photos/ComparePresentation.swift`:

```swift
import Foundation

struct PhotoComparePair: Identifiable {
    let presentationID = UUID()
    let olderPhoto: PhotoEntry
    let newerPhoto: PhotoEntry

    var id: String {
        "\(olderPhoto.persistentModelID)_\(newerPhoto.persistentModelID)_\(presentationID.uuidString)"
    }
}

/// Decyduje, kiedy ekran porównania ma się pokazać: od razu, czy dopiero po zamknięciu
/// sheeta, z którego przyszło żądanie.
struct ComparePresentationState {
    private(set) var active: PhotoComparePair?
    private(set) var pending: PhotoComparePair?

    mutating func request(_ pair: PhotoComparePair, presentedFromSheet: Bool) {
        if presentedFromSheet {
            pending = pair
        } else {
            active = pair
        }
    }

    mutating func sheetDismissed() {
        guard let pair = pending else { return }
        pending = nil
        active = pair
    }

    mutating func activeDismissed() {
        active = nil
    }
}
```

- [ ] **Step 4: Delete the old `PhotoComparePair` declaration**

In `MeasureMe/PhotoView.swift`, delete the now-duplicate declaration (currently lines 485-493):

```swift
struct PhotoComparePair: Identifiable {
    let presentationID = UUID()
    let olderPhoto: PhotoEntry
    let newerPhoto: PhotoEntry

    var id: String {
        "\(olderPhoto.persistentModelID)_\(newerPhoto.persistentModelID)_\(presentationID.uuidString)"
    }
}
```

Leave `TemporaryHeroPairOverride` immediately below it untouched.

- [ ] **Step 5: Run the test and confirm it passes**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/ComparePresentationStateTests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, 7 tests passing.

- [ ] **Step 6: Swap PhotoView onto the new state**

In `MeasureMe/PhotoView.swift`, replace:

```swift
    @State private var selectedComparePair: PhotoComparePair?
```

with:

```swift
    @State private var comparePresentation = ComparePresentationState()
```

Then add the sheet binding next to the other computed bindings (right after `sourceChooserSheetBinding`, around line 73):

```swift
    private var comparePairBinding: Binding<PhotoComparePair?> {
        Binding(
            get: { comparePresentation.active },
            set: { newValue in
                if newValue == nil { comparePresentation.activeDismissed() }
            }
        )
    }
```

- [ ] **Step 7: Rewrite `openCompare`**

In `MeasureMe/PhotoView.swift`, replace the whole `openCompare` function (currently lines 396-408) with:

```swift
    func openCompare(
        using olderPhoto: PhotoEntry,
        _ newerPhoto: PhotoEntry,
        presentedFromSheet: Bool = false
    ) {
        guard premiumStore.isPremium else {
            premiumStore.presentPaywall(reason: .photoComparison)
            return
        }
        let sorted = [olderPhoto, newerPhoto].sorted { $0.date < $1.date }
        guard sorted.count == 2 else { return }
        comparePresentation.request(
            PhotoComparePair(olderPhoto: sorted[0], newerPhoto: sorted[1]),
            presentedFromSheet: presentedFromSheet
        )
    }
```

- [ ] **Step 8: Rewire the three sheets**

In `MeasureMe/PhotoView.swift`, replace the block spanning the chooser, compare and detail sheets (currently lines 311-338) with:

```swift
            .sheet(item: $compareChooserContext, onDismiss: {
                comparePresentation.sheetDismissed()
            }) { context in
                HomeCompareChooserSheet(
                    photos: allPhotos,
                    initialOlderPhoto: context.olderPhoto,
                    initialNewerPhoto: context.newerPhoto,
                    preferredSlot: context.preferredSlot,
                    onSelectionChanged: handleCompareChooserSelectionChange
                ) { olderPhoto, newerPhoto in
                    openCompare(using: olderPhoto, newerPhoto, presentedFromSheet: true)
                }
            }
            .sheet(item: comparePairBinding) { pair in
                ComparePhotosView(
                    olderPhoto: pair.olderPhoto,
                    newerPhoto: pair.newerPhoto
                )
            }
            .sheet(item: $selectedPhotoForDetail, onDismiss: {
                refreshPhotoContent()
                comparePresentation.sheetDismissed()
            }) { photo in
                PhotoDetailView(photo: photo, onCompareRequested: handlePhotoDetailCompareRequest) {
                    handlePhotoDeletedFromDetail(photo)
                }
                    .environmentObject(metricsStore)
            }
```

Two removals are load-bearing here: the `.onDisappear { selectedComparePair = nil }` that used to hang off `ComparePhotosView`, and the `Task { await Task.yield() }` deferral that Step 7 already dropped.

- [ ] **Step 9: Update `handlePhotoDetailCompareRequest`**

In `MeasureMe/PhotoView.swift`, replace it (currently lines 472-475) with:

```swift
    private func handlePhotoDetailCompareRequest(_ olderPhoto: PhotoEntry, _ newerPhoto: PhotoEntry) {
        openCompare(using: olderPhoto, newerPhoto, presentedFromSheet: true)
        selectedPhotoForDetail = nil
    }
```

Order matters: the request must be parked before the sheet starts dismissing, because dismissal is what promotes it.

- [ ] **Step 10: Build and confirm it is clean**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild build -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' 2>&1 | grep -E "error:|warning: var|BUILD" | head -20
```

Expected: `** BUILD SUCCEEDED **`, no `error:` lines. If the compiler reports `selectedComparePair` still in use, grep for it — every reference must be gone:

```bash
grep -n "selectedComparePair" MeasureMe/PhotoView.swift
```

Expected: no output.

- [ ] **Step 11: Commit**

```bash
git add MeasureMe/Photos/ComparePresentation.swift MeasureMe/PhotoView.swift MeasureMeTests/ComparePresentationStateTests.swift
git commit -m "fix(photos): open Compare on the first tap"
```

---

## Task 6: Full verification and manual device pass

**Files:**
- Modify: none expected. If a regression surfaces, fix it in the file that caused it and note it in the commit.

**Interfaces:**
- Consumes: everything from Tasks 1-5.
- Produces: nothing consumed by later tasks — this is the closing gate.

- [ ] **Step 1: Run the full unit test suite**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests 2>&1 | tail -60
```

Expected: about 765 tests. Failures are acceptable **only** if every one is a `Snapshot does not match reference` in one of the suites named in Global Constraints. Any other failure blocks the task. Confirm with:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests 2>&1 | grep -E "^Test Case .* failed|error:" | grep -v "Snapshot does not match reference"
```

Expected: no output.

- [ ] **Step 2: Run the Compare UI regression test**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeUITests/PhotoFlowUITests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`. If it fails on the first attempt after a simulator erase, run it once more before treating the failure as real — a cold simulator produces spurious navigation-level UI failures.

- [ ] **Step 3: Build, install and launch on the physical iPhone**

The simulator has no camera and `GuidedCameraView` is bypassed in UI-test mode, so the camera changes can only be checked on the device. Ask the user to unlock the iPhone first — the launch command hangs silently with an empty log on a locked device.

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild -scheme MeasureMe -destination 'platform=iOS,id=AA001863-CBB8-516A-ACFD-7771B3FC8A25' -allowProvisioningUpdates build 2>&1 | tail -5
```

Then install and launch (substitute the built product path reported by the build, under `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug-iphoneos/MeasureMe.app`):

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcrun devicectl device install app --device AA001863-CBB8-516A-ACFD-7771B3FC8A25 <path>/MeasureMe.app
```

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcrun devicectl device process launch --device AA001863-CBB8-516A-ACFD-7771B3FC8A25 --console --terminate-existing com.jacek.measureme
```

`install app` with the same bundle ID preserves the container — never `uninstall`; it would wipe the user's real measurements and photos.

- [ ] **Step 4: Walk the manual checklist on the device**

Ask the user to confirm each item, in Photos → add → Take Photo:

1. The pose bar shows `Off / Front / Side / Back / Detail`; `Off` is selected on a fresh install and no ghost is drawn.
2. Selecting a pose that has photos swaps the ghost to the newest photo with that tag, and the hint reads "Match your last pose".
3. Selecting a pose that has no photos draws no ghost and shows "No photo for this pose yet — this will be your first".
4. The opacity button appears only when a pose is selected, and cycling it steps the ghost through three visibly different strengths, wrapping back to the faintest.
5. Closing and reopening the camera restores the last pose and opacity; the same holds after force-quitting and relaunching the app.
6. Taking a photo with a pose selected opens the form with that pose already ticked, and it stays ticked.
7. Taking a photo with `Off` selected leaves the automatic pose suggestion working as before.
8. Selecting two photos → Compare opens the comparison screen on the first tap, repeatedly.
9. Opening Compare from the chooser sheet and from a photo's detail screen also works on the first tap.

- [ ] **Step 5: Commit any fixes and report**

If Steps 1-4 required no changes, there is nothing to commit. Otherwise:

```bash
git add -A
git commit -m "fix(photos): address findings from the device verification pass"
```

Report to the user: which checklist items passed, which needed a fix, and the exact unit-test failure list (expected to be snapshot-only).

---

## Notes for the implementer

- Three assumptions in this plan were checked against the real toolchain on 2026-08-10 with a throwaway test, so do not re-litigate them:
  - `PhotoEntry(...)` constructed without a `ModelContext` works fine in tests, and `thumbnailOrImageData` behaves normally on it.
  - `persistentModelID` on such an unattached instance returns a **temporary** identifier whose `String(describing:)` is byte-identical across different instances. `PhotoComparePair.id` therefore varies only by its `presentationID` in unit tests — never write a test asserting that two pairs built from *different* unattached photos have different ids.
  - `selectedTags` and `didUserChoosePose` are `@State private var` today; `@testable import` cannot reach them, which is why Task 4 Step 3 exists.
- `PhotoView.swift` line numbers drift as tasks land. Every "currently lines N-M" reference is against the state of the file at the start of this plan; locate the code by its quoted content, not by the number.
- `PhotoOverlayCandidates.mostRecentByPose(in:)` requires date-descending input. `PhotoView`'s `@Query` already sorts that way (`SortDescriptor(\PhotoEntry.date, order: .reverse)`) — do not add a re-sort inside the function; it would hide a caller mistake behind a silent cost.
- Do not touch the `CameraPickerView(selectedImage:)` retake path inside `AddPhotoView` (line 115). It is out of scope.
- Do not add the two `@AppStorage` keys to `AppSettingsSnapshot`/`AppSettingsKeys`. Local UI preferences use plain `@AppStorage` in this codebase (`photos.gridLayoutMode`, `compare.ghostHintDismissed`).
