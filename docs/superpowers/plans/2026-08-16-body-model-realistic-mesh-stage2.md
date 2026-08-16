# Realistic Base Mesh — Stage 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the rendered body carry the user's measured circumferences, so the morph between two dates shows a real change in shape rather than only in stature.

**Architecture:** Each vertex is assigned to a body region by nearest bone. Each region is sliced along its own axis into bands; every band's base circumference is measured once as a convex-hull perimeter. At render time each vertex is scaled radially about its band's centroid by `target / base`, with the factor feathered to 1 across the wrist, ankle and neck so hands, feet and head keep their size.

**Tech Stack:** Python 3 (stdlib only), Swift 6, SceneKit, XCTest.

## Global Constraints

- Everything in the Stage 1 plan's Global Constraints still holds, except that this stage DOES delete `BodyGeometryBuilder.swift` and its tests, in the final task.
- `BodyMeshSolver`, `BodyProportions`, `BodyVolumeValidator` and `Superellipse` stay untouched. They remain the analytic model that reconciles volume against weight; this stage only consumes their output.
- Build and test with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` and `-destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182'`.
- After any `-only-testing` run, check the `Executed N tests` line. A class name that does not exist matches zero tests and still reports `** TEST SUCCEEDED **`.
- Expect 18 pre-existing snapshot failures across `HomeViewSnapshotTests`, `MetricDetailSnapshotTests`, `HealthIndicatorDetailSnapshotTests`, `ExperienceSettingsDetailViewSnapshotTests`, `DataSettingsDetailViewSnapshotTests`, `ComparePhotosSnapshotTests`, `OnboardingSnapshotTests`, `MeasurementsIndicatorsSnapshotTests`. They are stale iOS 27 baselines. Anything outside that set is a regression this branch caused.

## Why a convex hull is the right circumference

A tape measure pulled taut around a waist does not sink into the small of the
back — it spans the concavity. The convex hull perimeter of a cross-section is
therefore not an approximation of the measurement; it *is* the measurement.
The true surface perimeter would over-read.

This choice also makes acceptance criterion 1 hold by construction rather than
by tuning. Scaling every point of a planar set radially about a fixed centre by
`s` multiplies all pairwise distances by `s`, so the hull's perimeter is
multiplied by exactly `s`. With `s = target / base`, the deformed band measures
`target` exactly. The only error left is from feathering the factor between
bands, which is what the ±1% tolerance absorbs.

---

## File Structure

| File | Responsibility |
|---|---|
| `tools/bodymesh/bake.py` | Modified: normalise the skeleton into the mesh's space |
| `MeasureMe/BodyModel/BodySkeleton.swift` | Decoded joints, and the bone segments built from them |
| `MeasureMe/BodyModel/BodyRegionMap.swift` | Vertex → region + position along that region's axis |
| `MeasureMe/BodyModel/ConvexHull.swift` | 2D hull and its perimeter |
| `MeasureMe/BodyModel/BodyBandProfile.swift` | Per-region bands: centroid, axis frame, base circumference |
| `MeasureMe/BodyModel/BodyMeshDeformer.swift` | Applies target circumferences to the base positions |
| `MeasureMe/BodyModel/MannequinView.swift` | Modified: renders deformed positions |
| `MeasureMe/BodyModel/BodyGeometryBuilder.swift` | **Deleted** in the final task |

---

## Task 1: Bake the skeleton into the mesh's coordinate space

**Bug being fixed.** `bake.py` writes `BodySkeleton.json` from joint centroids in
the source file's decimetres (y spans −8.183…9.366) while the mesh it ships
beside is normalised to y 0…1. Every joint in the current file is unusable as
written. Nothing consumed it in stage 1, so this surfaced only now.

**Files:**
- Modify: `tools/bodymesh/bake.py`
- Test: `tools/bodymesh/test_bake.py`

**Interfaces:**
- Produces: `normalise_with(positions, transform)` and `normalisation_of(positions) -> (cx, y0, cz, height)`. `bake()` applies the same transform to mesh and skeleton.

- [ ] **Step 1: Write the failing tests**

Add to `tools/bodymesh/test_bake.py`, inside `TestGeometry`:

```python
    def test_normalisation_of_reports_the_transform_normalise_applies(self):
        positions = [(-2, 10, 4), (2, 30, 8)]
        cx, y0, cz, height = bake.normalisation_of(positions)
        self.assertEqual((cx, y0, cz, height), (0.0, 10.0, 6.0, 20.0))

    def test_normalise_with_matches_normalise_on_the_same_points(self):
        """Dlaczego: szkielet i siatka musza przejsc DOKLADNIE te sama
        transformacje, inaczej stawy nie trafiaja w cialo."""
        positions = [(-2, 10, 4), (2, 30, 8)]
        transform = bake.normalisation_of(positions)
        self.assertEqual(bake.normalise_with(positions, transform), bake.normalise(positions))

    def test_normalise_with_maps_a_point_outside_the_source_set(self):
        transform = bake.normalisation_of([(-2, 10, 4), (2, 30, 8)])
        self.assertEqual(bake.normalise_with([(0, 20, 6)], transform), [(0.0, 0.5, 0.0)])
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 tools/bodymesh/test_bake.py`
Expected: FAIL — `module 'bake' has no attribute 'normalisation_of'`

- [ ] **Step 3: Refactor `normalise` and apply the transform to both**

Replace `normalise` in `tools/bodymesh/bake.py` with:

```python
def normalisation_of(positions):
    """-> (cx, y0, cz, height), the transform `normalise` would apply."""
    xs = [p[0] for p in positions]
    ys = [p[1] for p in positions]
    zs = [p[2] for p in positions]
    return (
        (max(xs) + min(xs)) / 2,
        min(ys),
        (max(zs) + min(zs)) / 2,
        max(ys) - min(ys),
    )


def normalise_with(positions, transform):
    """Applies a transform from `normalisation_of`. Points outside the set it
    was derived from map consistently — which is the whole point: the skeleton
    has to land in the same space as the mesh."""
    cx, y0, cz, height = transform
    return [((x - cx) / height, (y - y0) / height, (z - cz) / height) for x, y, z in positions]


def normalise(positions):
    """Feet to y=0, height to exactly 1.0, bounding box centred in X and Z."""
    return normalise_with(positions, normalisation_of(positions))
```

In `bake()`, replace `positions = normalise(positions)` with:

```python
    transform = normalisation_of(positions)
    positions = normalise_with(positions, transform)
    names = sorted(skeleton)
    moved = normalise_with([skeleton[n] for n in names], transform)
    skeleton = dict(zip(names, moved))
```

- [ ] **Step 4: Run the tests, re-bake, and verify the joints land inside the body**

```bash
python3 tools/bodymesh/test_bake.py && python3 tools/bodymesh/bake.py && python3 -c "
import json; d=json.load(open('MeasureMe/BodyModel/Resources/BodySkeleton.json'))['male']
ys=[v[1] for v in d.values()]
print('zakres y stawow: %.3f .. %.3f' % (min(ys), max(ys)))
for n in ('ground','l-ankle','l-knee','pelvis','neck','head-2','l-shoulder','l-elbow','l-hand'):
    print('  %-12s (%6.3f, %6.3f, %6.3f)' % (n, *d[n]))
"
```

Expected: every y within roughly 0…1 (`ground` at ≈0, `head-2` near ≈0.97), and `l-shoulder` around y 0.82 with x ≈ 0.11. A y outside 0…1 by more than a few percent means the transform was taken from the wrong point set.

- [ ] **Step 5: Commit**

```bash
git add tools/bodymesh MeasureMe/BodyModel/Resources
git commit -m "fix(body-model): bake the skeleton into the mesh's coordinate space"
```

---

## Task 2: Skeleton decoding and bone segments

**Files:**
- Create: `MeasureMe/BodyModel/BodySkeleton.swift`
- Test: `MeasureMeTests/BodySkeletonTests.swift`

**Interfaces:**
- Consumes: `BodySkeleton.json`, `BodyGender`.
- Produces: `struct BodyBone { let region: BodyRegion; let start: SIMD3<Float>; let end: SIMD3<Float> }`, `enum BodyRegion: CaseIterable { case torso, head, leftUpperArm, rightUpperArm, leftForearm, rightForearm, leftHand, rightHand, leftThigh, rightThigh, leftShin, rightShin, leftFoot, rightFoot }`, `BodySkeleton.bones(for: BodyGender) throws -> [BodyBone]`. Tasks 3 and 5 consume `bones(for:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import simd
@testable import MeasureMe

final class BodySkeletonTests: XCTestCase {
    func testEveryRegionHasAtLeastOneBone() throws {
        let bones = try BodySkeleton.bones(for: .male)
        for region in BodyRegion.allCases {
            XCTAssertTrue(bones.contains { $0.region == region }, "brak kosci dla \(region)")
        }
    }

    /// Dlaczego: siatka jest znormalizowana do 0...1, a szkielet byl kiedys
    /// wypiekany w decymetrach. Ten test lapie nawrot tamtego bledu.
    func testJointsLandInsideTheNormalisedMesh() throws {
        for gender in BodyGender.allCases {
            for bone in try BodySkeleton.bones(for: gender) {
                for point in [bone.start, bone.end] {
                    XCTAssertTrue((-0.1...1.1).contains(point.y), "\(gender) \(bone.region) y=\(point.y)")
                }
            }
        }
    }

    func testLeftAndRightBonesMirrorAcrossX() throws {
        let bones = try BodySkeleton.bones(for: .male)
        let left = try XCTUnwrap(bones.first { $0.region == .leftUpperArm })
        let right = try XCTUnwrap(bones.first { $0.region == .rightUpperArm })
        XCTAssertEqual(left.start.x, -right.start.x, accuracy: 1e-5)
        XCTAssertEqual(left.start.y, right.start.y, accuracy: 1e-5)
    }

    /// Dlaczego: to jest liczba, ktora wymusila lokalne uklady dla ramion.
    func testTheUpperArmSitsAboutFortyDegreesOffVertical() throws {
        let bone = try XCTUnwrap(try BodySkeleton.bones(for: .male).first { $0.region == .leftUpperArm })
        let axis = bone.end - bone.start
        let degrees = atan2(abs(axis.x), abs(axis.y)) * 180 / .pi
        XCTAssertEqual(degrees, 39.6, accuracy: 3.0)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodySkeletonTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'BodySkeleton' in scope`

- [ ] **Step 3: Write the implementation**

```swift
// BodySkeleton.swift
//
// **BodySkeleton**
// The baked joint positions, and the bone segments the region map is built from.
//
// **Responsibilities:**
// - Decoding BodySkeleton.json into the mesh's normalised space
// - Naming the bone chain each body region is measured along
//
// **Why bones rather than height bands:**
// The mesh is in A-pose, so the upper arm sits 39.6 degrees off vertical. A
// horizontal slice through a bicep cuts an ellipse whose perimeter over-reads
// the arm's circumference by 1/cos(39.6) — about 30%. Slicing perpendicular to
// the bone removes that error. Legs are only 9.3 degrees off, worth 1.3%, so
// they could have used height bands; they use bones anyway so there is one
// mechanism rather than two.
//
import Foundation
import simd

nonisolated enum BodyRegion: CaseIterable, Sendable {
    case torso, head
    case leftUpperArm, rightUpperArm, leftForearm, rightForearm, leftHand, rightHand
    case leftThigh, rightThigh, leftShin, rightShin, leftFoot, rightFoot

    /// Regions with no measurement behind them. They ride along with the body
    /// but are never rescaled — nobody measures the circumference of a head.
    var isMeasured: Bool {
        switch self {
        case .head, .leftHand, .rightHand, .leftFoot, .rightFoot: return false
        default: return true
        }
    }
}

nonisolated struct BodyBone: Equatable, Sendable {
    let region: BodyRegion
    let start: SIMD3<Float>
    let end: SIMD3<Float>
}

nonisolated enum BodySkeleton {
    enum LoadError: Error, Equatable {
        case resourceMissing
        case jointMissing(String)
    }

    private static let chain: [(BodyRegion, String, String)] = [
        (.torso, "pelvis", "spine-4"), (.torso, "spine-4", "spine-3"),
        (.torso, "spine-3", "spine-2"), (.torso, "spine-2", "spine-1"),
        (.torso, "spine-1", "neck"),
        (.head, "neck", "head"), (.head, "head", "head-2"),
        (.leftUpperArm, "l-shoulder", "l-elbow"), (.rightUpperArm, "r-shoulder", "r-elbow"),
        (.leftForearm, "l-elbow", "l-hand"), (.rightForearm, "r-elbow", "r-hand"),
        (.leftHand, "l-hand", "l-hand-2"), (.rightHand, "r-hand", "r-hand-2"),
        (.leftThigh, "l-upper-leg", "l-knee"), (.rightThigh, "r-upper-leg", "r-knee"),
        (.leftShin, "l-knee", "l-ankle"), (.rightShin, "r-knee", "r-ankle"),
        (.leftFoot, "l-ankle", "l-foot-2"), (.rightFoot, "r-ankle", "r-foot-2"),
    ]

    private static var cache: [BodyGender: [BodyBone]] = [:]

    static func bones(for gender: BodyGender) throws -> [BodyBone] {
        if let cached = cache[gender] { return cached }

        guard let url = Bundle.main.url(forResource: "BodySkeleton", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        let all = try JSONDecoder().decode(
            [String: [String: [Float]]].self,
            from: Data(contentsOf: url)
        )
        guard let joints = all[gender == .male ? "male" : "female"] else {
            throw LoadError.jointMissing(gender == .male ? "male" : "female")
        }

        func point(_ name: String) throws -> SIMD3<Float> {
            guard let value = joints[name], value.count == 3 else { throw LoadError.jointMissing(name) }
            return SIMD3(value[0], value[1], value[2])
        }

        let bones = try chain.map { BodyBone(region: $0.0, start: try point($0.1), end: try point($0.2)) }
        cache[gender] = bones
        return bones
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Same command as step 2. Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodySkeleton.swift MeasureMeTests/BodySkeletonTests.swift
git commit -m "feat(body-model): decode the baked skeleton into bone segments"
```

---

## Task 3: Region map

**Files:**
- Create: `MeasureMe/BodyModel/BodyRegionMap.swift`
- Test: `MeasureMeTests/BodyRegionMapTests.swift`

**Interfaces:**
- Consumes: `BodyBaseMesh`, `[BodyBone]`.
- Produces: `struct BodyRegionMap { let region: [BodyRegion]; let along: [Float] }` and `BodyRegionMap.build(mesh:bones:) -> BodyRegionMap`. `along[i]` is vertex `i`'s 0…1 position along its own bone. Task 4 consumes both arrays.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import simd
@testable import MeasureMe

final class BodyRegionMapTests: XCTestCase {
    private func makeMap(_ gender: BodyGender = .male) throws -> (BodyBaseMesh, BodyRegionMap) {
        let mesh = try BodyBaseMeshProvider.mesh(for: gender)
        return (mesh, BodyRegionMap.build(mesh: mesh, bones: try BodySkeleton.bones(for: gender)))
    }

    func testEveryVertexGetsARegionAndAPosition() throws {
        let (mesh, map) = try makeMap()
        XCTAssertEqual(map.region.count, mesh.positions.count)
        XCTAssertEqual(map.along.count, mesh.positions.count)
        XCTAssertNil(map.along.first { $0 < 0 || $0 > 1 })
    }

    /// Dlaczego: gdyby ktorys region byl pusty, jego obwod nigdy by nie zadzialal
    /// i blad bylby cichy — model po prostu ignorowalby jeden pomiar.
    func testNoRegionIsEmpty() throws {
        let (_, map) = try makeMap()
        for region in BodyRegion.allCases {
            XCTAssertTrue(map.region.contains(region), "pusty region \(region)")
        }
    }

    func testTheHighestVerticesBelongToTheHead() throws {
        let (mesh, map) = try makeMap()
        let top = mesh.positions.indices.max { mesh.positions[$0].y < mesh.positions[$1].y }!
        XCTAssertEqual(map.region[top], .head)
    }

    func testTheLowestVerticesBelongToAFoot() throws {
        let (mesh, map) = try makeMap()
        let bottom = mesh.positions.indices.min { mesh.positions[$0].y < mesh.positions[$1].y }!
        XCTAssertTrue([.leftFoot, .rightFoot].contains(map.region[bottom]))
    }

    /// Dlaczego: strony nie moga sie mieszac — lewa reka po prawej stronie
    /// oznaczalaby, ze pomiar bicepsa trafia w niewlasciwe ramie.
    func testArmRegionsStayOnTheirOwnSideOfTheBody() throws {
        let (mesh, map) = try makeMap()
        for index in mesh.positions.indices {
            switch map.region[index] {
            case .leftUpperArm, .leftForearm, .leftHand:
                XCTAssertGreaterThan(mesh.positions[index].x, -0.02)
            case .rightUpperArm, .rightForearm, .rightHand:
                XCTAssertLessThan(mesh.positions[index].x, 0.02)
            default: break
            }
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `cannot find 'BodyRegionMap' in scope`

- [ ] **Step 3: Write the implementation**

```swift
// BodyRegionMap.swift
//
// **BodyRegionMap**
// Which part of the body each vertex belongs to, and where along it.
//
// **Responsibilities:**
// - Assigning every vertex to its nearest bone
// - Recording how far along that bone the vertex sits, as 0...1
//
// **Why nearest-bone rather than a height band:**
// At chest height a horizontal band contains the torso and both upper arms, so
// height alone cannot tell them apart, and a chest measurement would end up
// scaling the arms. Distance to the bone segment separates them the way the
// anatomy does.
//
import Foundation
import simd

nonisolated struct BodyRegionMap: Sendable {
    let region: [BodyRegion]
    /// 0 at the bone's start joint, 1 at its end joint.
    let along: [Float]

    static func build(mesh: BodyBaseMesh, bones: [BodyBone]) -> BodyRegionMap {
        var regions = [BodyRegion](repeating: .torso, count: mesh.positions.count)
        var alongs = [Float](repeating: 0, count: mesh.positions.count)

        for (index, point) in mesh.positions.enumerated() {
            var bestDistance = Float.greatestFiniteMagnitude
            for bone in bones {
                let axis = bone.end - bone.start
                let lengthSquared = simd_length_squared(axis)
                // A zero-length bone would divide by zero; clamp turns it into
                // a plain point-to-point distance instead.
                let t = lengthSquared > 0
                    ? min(max(simd_dot(point - bone.start, axis) / lengthSquared, 0), 1)
                    : 0
                let distance = simd_distance(point, bone.start + axis * t)
                if distance < bestDistance {
                    bestDistance = distance
                    regions[index] = bone.region
                    alongs[index] = t
                }
            }
        }
        return BodyRegionMap(region: regions, along: alongs)
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Expected: `Executed 5 tests, with 0 failures`.

If `testNoRegionIsEmpty` fails for a hand or foot, the hand/foot bones are too
short to win against the forearm or shin. Extend them: use `l-hand-3` rather
than `l-hand-2` as the hand's end joint.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodyRegionMap.swift MeasureMeTests/BodyRegionMapTests.swift
git commit -m "feat(body-model): assign every vertex to its nearest bone"
```

---

## Task 4: Convex hull and band profiles

**Files:**
- Create: `MeasureMe/BodyModel/ConvexHull.swift`
- Create: `MeasureMe/BodyModel/BodyBandProfile.swift`
- Test: `MeasureMeTests/ConvexHullTests.swift`
- Test: `MeasureMeTests/BodyBandProfileTests.swift`

**Interfaces:**
- Produces: `ConvexHull.perimeter(of: [SIMD2<Float>]) -> Float`; `struct BodyBand { let centroid: SIMD3<Float>; let axis: SIMD3<Float>; let circumference: Float }`; `BodyBandProfile.build(mesh:map:bones:bandsPerRegion:) -> [BodyRegion: [BodyBand]]`. Task 5 consumes the profile.

- [ ] **Step 1: Write the hull tests**

```swift
import XCTest
import simd
@testable import MeasureMe

final class ConvexHullTests: XCTestCase {
    func testPerimeterOfAUnitSquareIsFour() {
        let square: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        XCTAssertEqual(ConvexHull.perimeter(of: square), 4, accuracy: 1e-5)
    }

    /// Dlaczego: tasma krawiecka nie wchodzi we wklesloscia — punkt wewnetrzny
    /// nie moze zmienic wyniku.
    func testInteriorPointsDoNotChangeThePerimeter() {
        let square: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        XCTAssertEqual(ConvexHull.perimeter(of: square + [SIMD2(0.5, 0.5)]), 4, accuracy: 1e-5)
    }

    func testAConcaveOutlineMeasuresAsItsHull() {
        // Kwadrat z wcieciem w gornej krawedzi: tasma go pomija.
        let concave: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0.5, 0.4), SIMD2(0, 1)
        ]
        XCTAssertEqual(ConvexHull.perimeter(of: concave), 4, accuracy: 1e-5)
    }

    /// Dlaczego: to jest wlasnosc, na ktorej stoi kryterium round-tripu.
    func testScalingAboutTheCentroidScalesThePerimeterExactly() {
        let points: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(3, 0), SIMD2(3, 2), SIMD2(0, 2)]
        let centre = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
        let scaled = points.map { centre + ($0 - centre) * 1.37 }
        XCTAssertEqual(
            ConvexHull.perimeter(of: scaled),
            ConvexHull.perimeter(of: points) * 1.37,
            accuracy: 1e-4
        )
    }

    func testDegenerateInputsDoNotCrash() {
        XCTAssertEqual(ConvexHull.perimeter(of: []), 0)
        XCTAssertEqual(ConvexHull.perimeter(of: [SIMD2(1, 1)]), 0)
        XCTAssertEqual(ConvexHull.perimeter(of: [SIMD2(0, 0), SIMD2(1, 0)]), 2, accuracy: 1e-5)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `cannot find 'ConvexHull' in scope`

- [ ] **Step 3: Write the hull**

```swift
// ConvexHull.swift
//
// **ConvexHull**
// The perimeter a tape measure would read around a cross-section.
//
// **Why the hull and not the outline:**
// A tape pulled taut around a waist spans the small of the back rather than
// sinking into it. The hull's perimeter is therefore the measurement itself,
// not an approximation of it; the true surface outline would over-read.
//
// Monotone chain (Andrew's), O(n log n).
//
import Foundation
import simd

nonisolated enum ConvexHull {
    static func perimeter(of points: [SIMD2<Float>]) -> Float {
        let hull = hull(of: points)
        guard hull.count > 1 else { return 0 }
        // Two points are a degenerate hull: out and back is twice the span.
        return hull.indices.reduce(0) { total, index in
            total + simd_distance(hull[index], hull[(index + 1) % hull.count])
        }
    }

    static func hull(of points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard points.count > 2 else { return points }
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }

        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        func chain(_ input: [SIMD2<Float>]) -> [SIMD2<Float>] {
            var result: [SIMD2<Float>] = []
            for point in input {
                while result.count >= 2 && cross(result[result.count - 2], result[result.count - 1], point) <= 0 {
                    result.removeLast()
                }
                result.append(point)
            }
            result.removeLast()
            return result
        }

        return chain(sorted) + chain(sorted.reversed())
    }
}
```

- [ ] **Step 4: Run the hull tests**

Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Write the band-profile tests**

```swift
import XCTest
import simd
@testable import MeasureMe

final class BodyBandProfileTests: XCTestCase {
    private func makeProfile() throws -> [BodyRegion: [BodyBand]] {
        let mesh = try BodyBaseMeshProvider.mesh(for: .male)
        let bones = try BodySkeleton.bones(for: .male)
        return BodyBandProfile.build(
            mesh: mesh,
            map: BodyRegionMap.build(mesh: mesh, bones: bones),
            bones: bones,
            bandsPerRegion: 24
        )
    }

    func testEveryRegionGetsBandsWithAPositiveCircumference() throws {
        let profile = try makeProfile()
        for region in BodyRegion.allCases {
            let bands = try XCTUnwrap(profile[region], "\(region)")
            XCTAssertFalse(bands.isEmpty, "\(region)")
            XCTAssertNil(bands.first { $0.circumference <= 0 }, "\(region)")
        }
    }

    /// Dlaczego: liczby sanity-check na prawdziwym ciele. Siatka jest wysoka
    /// na 1,0, wiec obwod pasa wypada okolo 0,45 przy wzroscie 180 cm — czyli
    /// jakies 81 cm. Rzad wielkosci musi sie zgadzac, inaczej skala jest zla.
    func testTorsoCircumferencesAreInAPlausibleRange() throws {
        let bands = try XCTUnwrap(try makeProfile()[.torso])
        for band in bands {
            XCTAssertGreaterThan(band.circumference, 0.15)
            XCTAssertLessThan(band.circumference, 0.85)
        }
    }

    /// Dlaczego: os ramienia musi byc odchylona od pionu, inaczej przekroj idzie
    /// poziomo i obwod bicepsa jest zawyzony o ~30%.
    func testTheUpperArmBandsAreTiltedOffVertical() throws {
        let bands = try XCTUnwrap(try makeProfile()[.leftUpperArm])
        let axis = try XCTUnwrap(bands.first).axis
        XCTAssertGreaterThan(abs(axis.x), 0.4)
    }

    func testAnArmBandIsThinnerThanATorsoBand() throws {
        let profile = try makeProfile()
        let arm = try XCTUnwrap(profile[.leftUpperArm]?.map(\.circumference).max())
        let torso = try XCTUnwrap(profile[.torso]?.map(\.circumference).max())
        XCTAssertLessThan(arm, torso)
    }
}
```

- [ ] **Step 6: Run to verify they fail**

Expected: FAIL — `cannot find 'BodyBandProfile' in scope`

- [ ] **Step 7: Write the band profile**

```swift
// BodyBandProfile.swift
//
// **BodyBandProfile**
// The base mesh measured, once, so the deformer only has to scale.
//
// **Responsibilities:**
// - Splitting each region into bands along its bone
// - Recording each band's centroid, axis and base circumference
//
// **Why this is precomputed:**
// None of it depends on the user's measurements, so it is derived once per
// gender at load. What remains per frame is a lookup and a multiply per vertex,
// which is what keeps the morph smooth at 13 380 vertices.
//
import Foundation
import simd

nonisolated struct BodyBand: Equatable, Sendable {
    let centroid: SIMD3<Float>
    /// Unit vector along the bone this band was cut perpendicular to.
    let axis: SIMD3<Float>
    let circumference: Float
}

nonisolated enum BodyBandProfile {
    static func build(
        mesh: BodyBaseMesh,
        map: BodyRegionMap,
        bones: [BodyBone],
        bandsPerRegion: Int
    ) -> [BodyRegion: [BodyBand]] {
        var members: [BodyRegion: [[Int]]] = [:]
        for region in BodyRegion.allCases {
            members[region] = Array(repeating: [], count: bandsPerRegion)
        }
        for index in mesh.positions.indices {
            let slot = min(Int(map.along[index] * Float(bandsPerRegion)), bandsPerRegion - 1)
            members[map.region[index]]?[slot].append(index)
        }

        var profile: [BodyRegion: [BodyBand]] = [:]
        for region in BodyRegion.allCases {
            let axis = regionAxis(region, bones: bones)
            let (right, up) = frame(for: axis)
            profile[region] = members[region]!.compactMap { indices -> BodyBand? in
                guard !indices.isEmpty else { return nil }
                let centroid = indices.reduce(SIMD3<Float>.zero) { $0 + mesh.positions[$1] }
                    / Float(indices.count)
                let flat = indices.map { index -> SIMD2<Float> in
                    let offset = mesh.positions[index] - centroid
                    return SIMD2(simd_dot(offset, right), simd_dot(offset, up))
                }
                return BodyBand(
                    centroid: centroid,
                    axis: axis,
                    circumference: ConvexHull.perimeter(of: flat)
                )
            }
        }
        return profile
    }

    /// Mean direction of the bones making up a region.
    static func regionAxis(_ region: BodyRegion, bones: [BodyBone]) -> SIMD3<Float> {
        let directions = bones.filter { $0.region == region }
            .map { simd_normalize($0.end - $0.start) }
        guard !directions.isEmpty else { return SIMD3(0, 1, 0) }
        let sum = directions.reduce(SIMD3<Float>.zero, +)
        return simd_length(sum) > 0 ? simd_normalize(sum) : SIMD3(0, 1, 0)
    }

    /// Any two unit vectors spanning the plane perpendicular to `axis`. The
    /// choice of seed only has to avoid being parallel to the axis; which
    /// perpendicular pair comes out does not matter, because the perimeter of a
    /// planar set does not depend on how the plane is coordinatised.
    static func frame(for axis: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let seed = abs(axis.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let right = simd_normalize(simd_cross(seed, axis))
        return (right, simd_normalize(simd_cross(axis, right)))
    }
}
```

- [ ] **Step 8: Run to verify they pass**

Expected: `Executed 4 tests, with 0 failures` for `BodyBandProfileTests`.

- [ ] **Step 9: Commit**

```bash
git add MeasureMe/BodyModel/ConvexHull.swift MeasureMe/BodyModel/BodyBandProfile.swift MeasureMeTests/ConvexHullTests.swift MeasureMeTests/BodyBandProfileTests.swift
git commit -m "feat(body-model): measure the base mesh as tape-measure circumferences"
```

---

## Task 5: The deformer

**Files:**
- Create: `MeasureMe/BodyModel/BodyMeshDeformer.swift`
- Test: `MeasureMeTests/BodyMeshDeformerTests.swift`

**Interfaces:**
- Consumes: everything above, plus `BodyMeshParameters`.
- Produces: `BodyMeshDeformer.deform(mesh:map:profile:parameters:) -> [SIMD3<Float>]`.

**Mapping from the solver to regions.** `BodyMeshParameters` carries stacks of
`BodyCrossSection` with `y` in centimetres and a circumference. Convert to the
mesh's unit space by dividing by `parameters.heightCm`. For `.torso`, look the
target up by the band centroid's height. For limbs, the solver's `arm` and `leg`
stacks are indexed the same way: sample them by the band's position along the
bone. Regions where `isMeasured` is false take a factor of exactly 1.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import simd
@testable import MeasureMe

final class BodyMeshDeformerTests: XCTestCase {
    private func fixture() throws -> (BodyBaseMesh, BodyRegionMap, [BodyRegion: [BodyBand]]) {
        let mesh = try BodyBaseMeshProvider.mesh(for: .male)
        let bones = try BodySkeleton.bones(for: .male)
        let map = BodyRegionMap.build(mesh: mesh, bones: bones)
        let profile = BodyBandProfile.build(mesh: mesh, map: map, bones: bones, bandsPerRegion: 24)
        return (mesh, map, profile)
    }

    private func snapshot(waistCm: Double) -> BodySnapshot {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return BodySnapshot(
            gender: .male, age: 31, heightCm: 180, weightKg: 80, bodyFatPercent: 20,
            neckCm: 38, shouldersCm: 118, chestCm: 100, bustCm: nil,
            waistCm: waistCm, hipsCm: 98, bicepCm: 33, forearmCm: 28,
            thighCm: 58, calfCm: 38,
            anchorDate: date, sourceDateRange: date...date
        )
    }

    /// Dlaczego: to jest kryterium akceptacji nr 1 ze specu — kazdy zmierzony
    /// obwod musi dotrwac do siatki.
    func testAMeasuredWaistSurvivesToTheDeformedMesh() throws {
        let (mesh, map, profile) = try fixture()
        let parameters = BodyMeshSolver.solve(snapshot: snapshot(waistCm: 86))
        let deformed = BodyMeshDeformer.deform(
            mesh: mesh, map: map, profile: profile, parameters: parameters
        )
        let measured = BodyMeshDeformer.circumference(
            of: deformed, map: map, region: .torso,
            atHeight: Float(BodyProportions.heightFraction(.waist, gender: .male))
        )
        XCTAssertEqual(Double(measured) * 180, 86, accuracy: 86 * 0.01)
    }

    func testABiggerWaistProducesABiggerBody() throws {
        let (mesh, map, profile) = try fixture()
        func waistWidth(_ cm: Double) -> Float {
            let deformed = BodyMeshDeformer.deform(
                mesh: mesh, map: map, profile: profile,
                parameters: BodyMeshSolver.solve(snapshot: snapshot(waistCm: cm))
            )
            return BodyMeshDeformer.circumference(
                of: deformed, map: map, region: .torso,
                atHeight: Float(BodyProportions.heightFraction(.waist, gender: .male))
            )
        }
        XCTAssertGreaterThan(waistWidth(96), waistWidth(76))
    }

    /// Dlaczego: nikt nie mierzy glowy ani dloni, wiec nie wolno ich skalowac.
    func testUnmeasuredRegionsAreLeftExactlyWhereTheyWere() throws {
        let (mesh, map, profile) = try fixture()
        let deformed = BodyMeshDeformer.deform(
            mesh: mesh, map: map, profile: profile,
            parameters: BodyMeshSolver.solve(snapshot: snapshot(waistCm: 96))
        )
        let scale = Float(180.0 / 100)
        for index in mesh.positions.indices where !map.region[index].isMeasured {
            XCTAssertEqual(
                simd_distance(deformed[index], mesh.positions[index] * scale), 0, accuracy: 1e-4
            )
        }
    }

    func testTheOutputHasOnePositionPerInputVertex() throws {
        let (mesh, map, profile) = try fixture()
        let deformed = BodyMeshDeformer.deform(
            mesh: mesh, map: map, profile: profile,
            parameters: BodyMeshSolver.solve(snapshot: snapshot(waistCm: 86))
        )
        XCTAssertEqual(deformed.count, mesh.positions.count)
        XCTAssertNil(deformed.first { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN })
    }

    func testDeformingIsFastEnoughForTheMorphSlider() throws {
        let (mesh, map, profile) = try fixture()
        let parameters = BodyMeshSolver.solve(snapshot: snapshot(waistCm: 86))
        measure {
            _ = BodyMeshDeformer.deform(mesh: mesh, map: map, profile: profile, parameters: parameters)
        }
    }
}
```

That initialiser list is the real memberwise one, checked against
`MeasureMe/BodyModel/BodySnapshot.swift`: note `weightKg` and `bodyFatPercent`,
and that `age`, `anchorDate` and `sourceDateRange` are all required.

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `cannot find 'BodyMeshDeformer' in scope`

- [ ] **Step 3: Write the deformer**

```swift
// BodyMeshDeformer.swift
//
// **BodyMeshDeformer**
// Applies the solver's circumferences to the base mesh.
//
// **Why the offset is split along and around the bone:**
// Only the component perpendicular to the bone is scaled. Scaling the whole
// offset would make a thicker waist a longer one as well, and would drag the
// shoulders up as the chest grew.
//
// **Why this satisfies the round-trip criterion by construction:**
// Scaling a planar set radially about a fixed centre by `s` multiplies every
// pairwise distance by `s`, so its convex hull perimeter — the tape-measure
// reading — is multiplied by exactly `s`. With `s = target / base` the band
// measures `target`. The residual error comes only from feathering `s` between
// bands, which is what the 1% tolerance is for.
//
import Foundation
import simd

nonisolated enum BodyMeshDeformer {
    static func deform(
        mesh: BodyBaseMesh,
        map: BodyRegionMap,
        profile: [BodyRegion: [BodyBand]],
        parameters: BodyMeshParameters
    ) -> [SIMD3<Float>] {
        let stature = Float(parameters.heightCm / 100)
        let factors = scaleFactors(parameters: parameters, profile: profile)

        return mesh.positions.indices.map { index in
            let region = map.region[index]
            let base = mesh.positions[index]
            guard region.isMeasured,
                  let bands = profile[region], bands.count > 1,
                  let regionFactors = factors[region]
            else { return base * stature }

            let slot = map.along[index] * Float(bands.count - 1)
            let lower = min(Int(slot), bands.count - 2)
            let blend = slot - Float(lower)

            let centroid = simd_mix(
                bands[lower].centroid, bands[lower + 1].centroid, SIMD3(repeating: blend)
            )
            let factor = regionFactors[lower]
                + (regionFactors[lower + 1] - regionFactors[lower]) * blend

            let axis = bands[lower].axis
            let offset = base - centroid
            let alongAxis = simd_dot(offset, axis) * axis
            return (centroid + alongAxis + (offset - alongAxis) * factor) * stature
        }
    }

    /// One `target / base` factor per band. Unmeasured regions never reach here.
    static func scaleFactors(
        parameters: BodyMeshParameters,
        profile: [BodyRegion: [BodyBand]]
    ) -> [BodyRegion: [Float]] {
        var result: [BodyRegion: [Float]] = [:]
        for (region, bands) in profile where region.isMeasured {
            result[region] = bands.map { band in
                let stack = solverStack(for: region, parameters: parameters)
                let target = Float(
                    sample(stack, atHeightCm: Double(band.centroid.y) * parameters.heightCm)
                        / parameters.heightCm
                )
                // A band whose base measures zero cannot be scaled into
                // anything meaningful; leaving it at 1 is the honest fallback.
                return band.circumference > 0 ? target / band.circumference : 1
            }
        }
        return result
    }

    private static func solverStack(
        for region: BodyRegion, parameters: BodyMeshParameters
    ) -> [BodyCrossSection] {
        switch region {
        case .leftUpperArm, .rightUpperArm, .leftForearm, .rightForearm: return parameters.arm
        case .leftThigh, .rightThigh, .leftShin, .rightShin:             return parameters.leg
        default:                                                        return parameters.torso
        }
    }

    /// Linear interpolation through a solver stack, clamped at both ends.
    private static func sample(_ stack: [BodyCrossSection], atHeightCm height: Double) -> Double {
        guard let first = stack.first, let last = stack.last else { return 0 }
        if height <= first.y { return first.circumferenceCm }
        if height >= last.y { return last.circumferenceCm }
        for index in 0..<(stack.count - 1) where height <= stack[index + 1].y {
            let low = stack[index], high = stack[index + 1]
            let span = high.y - low.y
            let t = span > 0 ? (height - low.y) / span : 0
            return low.circumferenceCm + (high.circumferenceCm - low.circumferenceCm) * t
        }
        return last.circumferenceCm
    }

    /// The tape-measure reading of a rendered body. Used by the tests; this is
    /// how acceptance criterion 1 is checked against the actual output rather
    /// than against the intent.
    static func circumference(
        of positions: [SIMD3<Float>],
        map: BodyRegionMap,
        region: BodyRegion,
        atHeight height: Float
    ) -> Float {
        let band: Float = 0.01
        let members = positions.indices.filter {
            map.region[$0] == region && abs(positions[$0].y - height) < band
        }
        guard !members.isEmpty else { return 0 }
        let centroid = members.reduce(SIMD3<Float>.zero) { $0 + positions[$1] } / Float(members.count)
        return ConvexHull.perimeter(of: members.map {
            SIMD2(positions[$0].x - centroid.x, positions[$0].z - centroid.z)
        })
    }
}
```

Note that `circumference(of:...)` measures in the **horizontal** plane, matching
how a waist is actually measured, while the deformer scales in the plane
perpendicular to the bone. For the torso those coincide. The test asserts on the
torso for exactly that reason — an arm assertion would need the bone frame and
would be testing the test.

- [ ] **Step 4: Run to verify they pass**

Expected: `Executed 5 tests, with 0 failures`. If the round-trip test misses by
more than 1%, raise `bandsPerRegion` — the error comes from feathering the
factor across a band, so narrower bands shrink it.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodyMeshDeformer.swift MeasureMeTests/BodyMeshDeformerTests.swift
git commit -m "feat(body-model): deform the base mesh to the measured circumferences"
```

---

## Task 6: Render the deformed mesh, and delete the ring stacks

**Files:**
- Modify: `MeasureMe/BodyModel/MannequinView.swift`
- Delete: `MeasureMe/BodyModel/BodyGeometryBuilder.swift`
- Delete: `MeasureMeTests/BodyGeometryBuilderTests.swift`
- Test: snapshots re-recorded

- [ ] **Step 1: Cache the map and profile per gender**

Add to `BodyBaseMeshProvider`:

```swift
    private static var rigs: [BodyGender: (map: BodyRegionMap, profile: [BodyRegion: [BodyBand]])] = [:]

    /// Built once per gender; none of it depends on the user's measurements.
    static func rig(for gender: BodyGender) throws -> (map: BodyRegionMap, profile: [BodyRegion: [BodyBand]]) {
        if let cached = rigs[gender] { return cached }
        let mesh = try mesh(for: gender)
        let bones = try BodySkeleton.bones(for: gender)
        let map = BodyRegionMap.build(mesh: mesh, bones: bones)
        let built = (map, BodyBandProfile.build(mesh: mesh, map: map, bones: bones, bandsPerRegion: 24))
        rigs[gender] = built
        return built
    }
```

- [ ] **Step 2: Point `MannequinView.geometry()` at the deformer**

Replace the `positions` line with:

```swift
        let rig = try? BodyBaseMeshProvider.rig(for: gender)
        guard let rig else { return nil }
        let positions = BodyMeshDeformer.deform(
            mesh: mesh, map: rig.map, profile: rig.profile, parameters: parameters
        )
```

Normals must be recomputed — the old ones no longer match the surface. Add a
`BodyMeshDeformer.normals(for:indices:)` that accumulates face normals the same
way `bake.py` does, and use it here. Also delete the stage 1 caveat paragraph
from the file's header comment; it is no longer true.

- [ ] **Step 3: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Delete the ring-stack builder**

```bash
git rm MeasureMe/BodyModel/BodyGeometryBuilder.swift MeasureMeTests/BodyGeometryBuilderTests.swift
```

Then check nothing still refers to it:

```bash
grep -rn "BodyGeometryBuilder" MeasureMe MeasureMeTests MeasureMeUITests --include="*.swift" || echo "brak odwolan"
```

`Superellipse.swift` stays — `BodyVolumeValidator` reads `shape.area` from it.
Confirm with `grep -rn "Superellipse\|\.shape\." MeasureMe --include="*.swift"`.

- [ ] **Step 5: Re-record the snapshots and look at them**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodyModelSnapshotTests 2>&1 | grep -cE "Automatically recorded"
```

Then open the PNGs and check: the proportions still read as a human, no pinching
at the wrists, ankles or neck, no collapsed armpit or crotch, and the silhouette
visibly differs from the stage 1 render. Crop the torso and limbs to inspect:

```bash
python3 -c "
from PIL import Image
im = Image.open('MeasureMeTests/__Snapshots__/BodyModelSnapshotTests/testBodyModelComparison_snapshot_light.1.png')
im.crop((400,500,800,1200)).resize((800,1400), Image.LANCZOS).save('/tmp/body.png')
"
```

The spec flags the armpit and crotch as the likely failure: radial scaling
assumes a convex cross-section, and those two are concave. If they pinch,
that is the cause.

- [ ] **Step 6: Run the whole suite**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests 2>&1 | grep -E "^Test Case.*failed|Executed [0-9]+ tests"`

Expected: the same 18 failures listed in Global Constraints and nothing else.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(body-model): drive the mannequin from the measured circumferences"
```

---

## Deliberately not in this plan: the piecewise-linear Y warp

The spec lists a Y warp that would move the mesh's own landmark heights to match
the solver's, carrying the volume validator's ±6% torso/leg split correction
into the geometry. It is left out on purpose, not overlooked.

Most of its effect is already covered: the deformer looks each band's target up
*by height*, so a solver that places the waist lower already applies the waist
circumference lower on the mesh. What the warp would add is moving the mesh's
proportions themselves — a second-order refinement on top of that.

Adding it before seeing the deformer render would mean tuning two unfamiliar
mechanisms against one another. Revisit once stage 2's render is in front of us,
and only if the torso's proportions actually look wrong.

## Stage 2 exit criteria

- [ ] A measured waist round-trips to the rendered mesh within 1%
- [ ] Head, hands and feet are bit-identical to the base mesh after stature scaling
- [ ] No seams or pinching at the wrist, ankle, neck, armpit or crotch
- [ ] The morph slider visibly changes shape, not only stature
- [ ] `BodyGeometryBuilder` and its tests are gone, with no references left
- [ ] `MeasureMeTests` shows the same 18 pre-existing failures and no others
- [ ] The branch is ready to merge — this is the first point at which that is true
