# Preview harness

`BodyModelPreviewHarness.swift.txt` is an XCTest class that renders the
mannequin for a matrix of dummy bodies and writes contact sheets to
`build/body-previews/`. Every visual decision in the body model was made by
looking at its output.

It lives here, with a `.txt` extension and outside `MeasureMe/`, for the same
reason `source/` does: the project uses `PBXFileSystemSynchronizedRootGroup`, so
anything under `MeasureMe/` is compiled automatically, and this is not something
to ship or to run in CI — a full matrix is ~30 MB of PNGs.

## Use

    cp tools/bodymesh/BodyModelPreviewHarness.swift.txt \
       MeasureMeTests/BodyModelDummyPreviewTests.swift

    DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
      -scheme MeasureMe \
      -destination 'platform=iOS Simulator,id=<UDID>' \
      -only-testing:MeasureMeTests/BodyModelDummyPreviewTests/testRenderDummyBodyMatrix \
      -derivedDataPath build/dd-preview

    rm MeasureMeTests/BodyModelDummyPreviewTests.swift

Delete it again when done, or the full test suite renders matrices.

## What is in it

- `testRenderDummyBodyMatrix` — ten bodies (both genders x slim / average /
  obese / short / tall) at four yaws.
- `testRenderSingleMetricSweeps` — one measurement varied, the rest held.
- `testRenderUndeformedBaseMesh` — the bake with no deformation at all, which
  is how you tell an asset problem from a deformer one.
- `renderRaw` — an SCNView set up exactly like `MannequinView`, taking a
  geometry directly, for rendering an undeformed or hand-built mesh. Its
  `key` / `fill` / `rim` / `ambientIntensity` parameters are how the shoulder
  highlight was traced to the rim light.

`Self.cell` controls the size of one rendered body; 360x640 suits a full matrix,
620x1100 a close-up.
