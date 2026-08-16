# Realistic Base Mesh — Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the body model from a real human base mesh — with head, hands, feet and shoulders — scaled to the user's stature, replacing the headless procedural ring-stack on screen.

**Architecture:** An offline Python script bakes the vendored MakeHuman CC0 sources into two compact binary `.bodymesh` assets (male, female). At runtime a small decoder loads one into plain Swift arrays, and `MannequinView` renders it with a matte clay material. Measurements do not yet drive the shape — that is Stage 2.

**Tech Stack:** Python 3 (stdlib only, no pip dependencies), Swift 6 / SwiftUI, SceneKit, XCTest, swift-snapshot-testing.

## Global Constraints

- **Stage 1 is not shippable.** After it, the mannequin ignores measurements and the morph slider only changes stature. Do not merge to `main` before Stage 2 completes. `BodyGeometryBuilder.swift` and `BodyGeometryBuilderTests.swift` stay in place and untouched for the whole of Stage 1.
- Vendored sources live in `tools/bodymesh/source/` and must stay outside `MeasureMe/` — the project uses `PBXFileSystemSynchronizedRootGroup`, so anything under `MeasureMe/` is pulled into the app target automatically.
- Baked assets ship, so they DO go under `MeasureMe/BodyModel/Resources/`.
- `bake.py` uses the Python standard library only. No pip installs.
- Deployment target is iOS 17.2. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set for the app target, so types meant to be usable off the main actor are marked `nonisolated`, matching every existing file in `MeasureMe/BodyModel/`.
- Existing code comments in `MeasureMe/BodyModel/` are English, with a header block naming the type, its responsibilities, and a "why" section. Match that. Test method comments in `MeasureMeTests` are Polish (`/// Dlaczego: …`). Match that too.
- The `.bodymesh` format is little-endian. Every Apple target is little-endian; the decoder relies on this and must say so in a comment.

---

## File Structure

| File | Responsibility |
|---|---|
| `tools/bodymesh/bake.py` | Offline bake: parse OBJ, apply gender morph, strip helpers, smooth face, normalise, write assets |
| `tools/bodymesh/test_bake.py` | Unit tests for `bake.py`'s pure functions, stdlib only |
| `MeasureMe/BodyModel/Resources/MaleBase.bodymesh` | Baked male mesh (generated, committed) |
| `MeasureMe/BodyModel/Resources/FemaleBase.bodymesh` | Baked female mesh (generated, committed) |
| `MeasureMe/BodyModel/Resources/BodySkeleton.json` | Joint centroids per gender (generated; unused in Stage 1, consumed by Stage 2) |
| `MeasureMe/BodyModel/BodyMeshFile.swift` | `BodyBaseMesh` value type + `.bodymesh` decoder |
| `MeasureMe/BodyModel/BodyBaseMeshProvider.swift` | Bundle lookup, decode, per-gender cache, stature scaling |
| `MeasureMe/BodyModel/MannequinView.swift` | Modified: renders the base mesh, clay material, three-point lighting |
| `MeasureMe/BodyModel/BodyModelScreen.swift` | Modified: threads `resolvedGender` into `MannequinView` |
| `MeasureMeTests/BodyMeshFileTests.swift` | Decoder tests |
| `MeasureMeTests/BodyBaseMeshProviderTests.swift` | Asset-loading and scaling tests |

### The `.bodymesh` format

```
offset  size            field
0       4               magic "BMSH"
4       4               version, UInt32 = 1
8       4               vertexCount, UInt32
12      4               indexCount, UInt32
16      12*vertexCount  positions, Float32 x,y,z
…       12*vertexCount  normals,   Float32 x,y,z
…       4*indexCount    indices,   UInt32, triangle list
```

Positions are normalised: feet at `y = 0`, total height exactly `1.0`, bounding box centred in X and Z. Scaling to a stature is therefore one multiply by `heightCm / 100`.

---

## Task 1: Bake script — pure functions

**Files:**
- Create: `tools/bodymesh/bake.py`
- Test: `tools/bodymesh/test_bake.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `parse_obj(lines) -> (positions, faces)`, `parse_target(lines) -> dict[int, tuple]`, `apply_target(positions, deltas) -> positions`, `compact(positions, faces) -> (positions, faces)`, `triangulate(faces) -> list[tuple]`, `build_adjacency(faces, count) -> list[set]`, `taubin_smooth(positions, adjacency, region, iterations) -> positions`, `normalise(positions) -> positions`, `compute_normals(positions, tris) -> normals`, `encode_bodymesh(positions, normals, tris) -> bytes`. Task 2 calls all of these.

- [ ] **Step 1: Write the failing tests**

Create `tools/bodymesh/test_bake.py`:

```python
#!/usr/bin/env python3
"""Unit tests for bake.py. Stdlib only: run with `python3 tools/bodymesh/test_bake.py`."""
import math
import struct
import sys
import unittest

import bake


class TestParsing(unittest.TestCase):
    def test_parse_obj_reads_positions_and_grouped_faces(self):
        lines = [
            "v 0 0 0\n", "v 1 0 0\n", "v 1 1 0\n", "v 0 1 0\n",
            "g body\n", "f 1/1 2/2 3/3 4/4\n",
            "g helper-skirt\n", "f 4 3 2 1\n",
        ]
        positions, faces = bake.parse_obj(lines)
        self.assertEqual(positions, [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)])
        self.assertEqual(faces, [("body", [0, 1, 2, 3]), ("helper-skirt", [3, 2, 1, 0])])

    def test_parse_target_skips_comments_and_reads_deltas(self):
        lines = ["# comment\n", "\n", "0 .5 -1 2\n", "7 1 1 1\n"]
        self.assertEqual(bake.parse_target(lines), {0: (0.5, -1.0, 2.0), 7: (1.0, 1.0, 1.0)})

    def test_apply_target_offsets_named_indices_and_ignores_out_of_range(self):
        positions = [(0, 0, 0), (1, 1, 1)]
        out = bake.apply_target(positions, {1: (1, 2, 3), 99: (9, 9, 9)})
        self.assertEqual(out, [(0, 0, 0), (2, 3, 4)])


class TestGeometry(unittest.TestCase):
    def test_compact_drops_unreferenced_vertices_and_remaps(self):
        positions = [(0, 0, 0), (9, 9, 9), (1, 0, 0), (1, 1, 0)]
        positions, faces = bake.compact(positions, [[0, 2, 3]])
        self.assertEqual(positions, [(0, 0, 0), (1, 0, 0), (1, 1, 0)])
        self.assertEqual(faces, [[0, 1, 2]])

    def test_triangulate_fans_a_quad_preserving_winding(self):
        self.assertEqual(bake.triangulate([[0, 1, 2, 3]]), [(0, 1, 2), (0, 2, 3)])

    def test_build_adjacency_links_face_neighbours_both_ways(self):
        adjacency = bake.build_adjacency([[0, 1, 2]], 3)
        self.assertEqual(adjacency[0], {1, 2})
        self.assertEqual(adjacency[1], {0, 2})

    def test_taubin_smooth_applies_the_shrink_then_unshrink_pair(self):
        # Neighbour mean is (1, 0, 0). The lambda pass pulls 9 -> 4.5, the
        # negative mu pass pushes it back out to 4.5 + 0.53 * 4.5 = 6.885.
        positions = [(0, 0, 0), (2, 0, 0), (1, 9, 0)]
        adjacency = [{2}, {2}, {0, 1}]
        out = bake.taubin_smooth(positions, adjacency, region={2}, iterations=1)
        self.assertAlmostEqual(out[2][0], 1.0, places=6)
        self.assertAlmostEqual(out[2][1], 6.885, places=6)

    def test_taubin_smooth_anchors_vertices_outside_the_region(self):
        positions = [(0, 0, 0), (2, 0, 0), (1, 9, 0)]
        adjacency = [{2}, {2}, {0, 1}]
        out = bake.taubin_smooth(positions, adjacency, region=set(), iterations=3)
        self.assertEqual(out, positions)

    def test_taubin_retains_far_more_amplitude_than_a_pure_laplacian(self):
        """Dlaczego: to jest caly powod wyboru Taubina. Przy tej samej liczbie
        usrednien czysty laplasjan zwija bryle (0.5^8), a Taubin nie (0.765^4).

        Uwaga na interpretacje: Taubin chroni NISKIE czestotliwosci, a w
        trojwierzcholkowej zabawce caly sygnal jest wysokoczestotliwosciowy,
        wiec tutaj tez opada — tylko duzo wolniej. Zachowanie bryly widac
        dopiero na prawdziwej siatce i pilnuje go krok weryfikacji w zadaniu 2."""
        positions = [(-1, 0, 0), (1, 0, 0), (0, 1, 0)]
        adjacency = [{2}, {2}, {0, 1}]
        taubin = bake.taubin_smooth(positions, adjacency, region={2}, iterations=4)
        laplacian = positions
        for _ in range(8):
            laplacian = bake.smoothing_pass(laplacian, adjacency, {2}, 0.5)
        self.assertAlmostEqual(taubin[2][1], 0.765 ** 4, places=6)
        self.assertAlmostEqual(laplacian[2][1], 0.5 ** 8, places=6)
        self.assertGreater(taubin[2][1], laplacian[2][1])

    def test_normalise_puts_feet_at_zero_height_at_one_and_centres_xz(self):
        out = bake.normalise([(-2, 10, 4), (2, 30, 8)])
        self.assertEqual(out, [(-0.1, 0.0, -0.1), (0.1, 1.0, 0.1)])

    def test_compute_normals_faces_along_positive_z_for_ccw_winding(self):
        normals = bake.compute_normals([(0, 0, 0), (1, 0, 0), (0, 1, 0)], [(0, 1, 2)])
        for normal in normals:
            self.assertAlmostEqual(normal[2], 1.0, places=6)


class TestEncoding(unittest.TestCase):
    def test_encode_bodymesh_round_trips_through_struct(self):
        blob = bake.encode_bodymesh([(1, 2, 3)], [(0, 1, 0)], [(0, 0, 0)])
        self.assertEqual(blob[:4], b"BMSH")
        version, vertex_count, index_count = struct.unpack_from("<III", blob, 4)
        self.assertEqual((version, vertex_count, index_count), (1, 1, 3))
        self.assertEqual(struct.unpack_from("<fff", blob, 16), (1.0, 2.0, 3.0))
        self.assertEqual(len(blob), 16 + 12 + 12 + 12)


if __name__ == "__main__":
    sys.path.insert(0, __file__.rsplit("/", 1)[0])
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 tools/bodymesh/test_bake.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'bake'`

- [ ] **Step 3: Write the pure functions**

Create `tools/bodymesh/bake.py`:

```python
#!/usr/bin/env python3
"""
Bakes the vendored MakeHuman CC0 sources into the app's .bodymesh assets.

Run manually; the output is committed. This is not part of the Xcode build.

Order matters: the gender target indexes the FULL base.obj vertex list
(19158 entries), not the body-only subset, so the morph is applied before the
helper and joint groups are stripped.
"""
import json
import math
import struct


def parse_obj(lines):
    """-> (positions, faces) where faces are (group name, [0-based indices])."""
    positions = []
    faces = []
    current = None
    for line in lines:
        if line.startswith("v "):
            parts = line.split()
            positions.append((float(parts[1]), float(parts[2]), float(parts[3])))
        elif line.startswith("g "):
            current = line.split(None, 1)[1].strip()
        elif line.startswith("f "):
            faces.append((current, [int(tok.split("/")[0]) - 1 for tok in line.split()[1:]]))
    return positions, faces


def parse_target(lines):
    """-> {vertex index: (dx, dy, dz)}. MakeHuman targets are `index dx dy dz`."""
    deltas = {}
    for line in lines:
        if line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 4:
            continue
        deltas[int(parts[0])] = (float(parts[1]), float(parts[2]), float(parts[3]))
    return deltas


def apply_target(positions, deltas):
    """Out-of-range indices are ignored: the target may address more vertices
    than the mesh carries, and a KeyError there would be noise, not a defect."""
    out = list(positions)
    for index, (dx, dy, dz) in deltas.items():
        if 0 <= index < len(out):
            x, y, z = out[index]
            out[index] = (x + dx, y + dy, z + dz)
    return out


def compact(positions, faces):
    """Drops vertices no surviving face references, remapping indices."""
    used = sorted({i for face in faces for i in face})
    remap = {old: new for new, old in enumerate(used)}
    return [positions[i] for i in used], [[remap[i] for i in face] for face in faces]


def triangulate(faces):
    """Fan triangulation. base.obj is 100% quads, so each face yields two."""
    tris = []
    for face in faces:
        for k in range(1, len(face) - 1):
            tris.append((face[0], face[k], face[k + 1]))
    return tris


def build_adjacency(faces, count):
    adjacency = [set() for _ in range(count)]
    for face in faces:
        for k, a in enumerate(face):
            b = face[(k + 1) % len(face)]
            adjacency[a].add(b)
            adjacency[b].add(a)
    return adjacency


# Taubin's lambda/mu pair. The negative second factor is what makes the filter
# volume preserving; measured on the real head, 40 iterations leave the
# bounding box at 2.597 -> 2.600 while cutting peak feature amplitude from
# 0.1024 to 0.0383. A plain Laplacian at 10 iterations already shrinks that
# same box by 5%, which would round the skull off instead of the nose.
TAUBIN_LAMBDA = 0.5
TAUBIN_MU = -0.53


def smoothing_pass(positions, adjacency, region, factor):
    """One weighted step toward the neighbour mean. Vertices outside `region`
    are anchored, which pins the region's border so the smoothing cannot creep
    down the neck into the shoulders."""
    out = list(positions)
    for index in region:
        neighbours = adjacency[index]
        if not neighbours:
            continue
        mean = [
            sum(positions[j][axis] for j in neighbours) / len(neighbours)
            for axis in range(3)
        ]
        out[index] = tuple(
            positions[index][axis] + factor * (mean[axis] - positions[index][axis])
            for axis in range(3)
        )
    return out


def taubin_smooth(positions, adjacency, region, iterations):
    """Band-pass smoothing: strips high-frequency detail — the nose, lips and
    eye sockets — while leaving the low-frequency skull shape alone."""
    points = positions
    for _ in range(iterations):
        points = smoothing_pass(points, adjacency, region, TAUBIN_LAMBDA)
        points = smoothing_pass(points, adjacency, region, TAUBIN_MU)
    return points


def normalise(positions):
    """Feet to y=0, height to exactly 1.0, bounding box centred in X and Z."""
    xs = [p[0] for p in positions]
    ys = [p[1] for p in positions]
    zs = [p[2] for p in positions]
    height = max(ys) - min(ys)
    cx = (max(xs) + min(xs)) / 2
    cz = (max(zs) + min(zs)) / 2
    y0 = min(ys)
    return [((x - cx) / height, (y - y0) / height, (z - cz) / height) for x, y, z in positions]


def compute_normals(positions, tris):
    """Smooth normals by accumulating face normals. A vertex touched only by
    degenerate triangles would normalise to NaN, so it falls back to up."""
    acc = [[0.0, 0.0, 0.0] for _ in positions]
    for i0, i1, i2 in tris:
        ax, ay, az = positions[i0]
        bx, by, bz = positions[i1]
        cx, cy, cz = positions[i2]
        ux, uy, uz = bx - ax, by - ay, bz - az
        vx, vy, vz = cx - ax, cy - ay, cz - az
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        for index in (i0, i1, i2):
            acc[index][0] += nx
            acc[index][1] += ny
            acc[index][2] += nz
    normals = []
    for nx, ny, nz in acc:
        length = math.sqrt(nx * nx + ny * ny + nz * nz)
        normals.append((nx / length, ny / length, nz / length) if length > 0 else (0.0, 1.0, 0.0))
    return normals


def encode_bodymesh(positions, normals, tris):
    """Little-endian; see the format table in the Stage 1 plan."""
    out = bytearray(b"BMSH")
    out += struct.pack("<III", 1, len(positions), len(tris) * 3)
    for point in positions:
        out += struct.pack("<fff", *point)
    for normal in normals:
        out += struct.pack("<fff", *normal)
    for tri in tris:
        out += struct.pack("<III", *tri)
    return bytes(out)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 tools/bodymesh/test_bake.py`
Expected: PASS, 12 tests

- [ ] **Step 5: Commit**

```bash
git add tools/bodymesh/bake.py tools/bodymesh/test_bake.py
git commit -m "feat(body-model): add the bake script's mesh primitives"
```

---

## Task 2: Bake script — end to end, producing the assets

**Files:**
- Modify: `tools/bodymesh/bake.py`
- Create: `MeasureMe/BodyModel/Resources/MaleBase.bodymesh` (generated)
- Create: `MeasureMe/BodyModel/Resources/FemaleBase.bodymesh` (generated)
- Create: `MeasureMe/BodyModel/Resources/BodySkeleton.json` (generated)

**Interfaces:**
- Consumes: every function from Task 1.
- Produces: the three asset files. Task 4 reads `MaleBase.bodymesh` and `FemaleBase.bodymesh` by those exact names; Stage 2 reads `BodySkeleton.json`.

- [ ] **Step 1: Add the driver to `bake.py`**

Append to `tools/bodymesh/bake.py`:

```python
SOURCE = "tools/bodymesh/source"
OUTPUT = "MeasureMe/BodyModel/Resources"

# Measured on the real head: peak feature amplitude falls 0.1024 -> 0.0407 by
# 20 iterations and 0.0383 by 40, then plateaus — what is left at that point is
# the skull's own curvature, not the face. Past 40 the bounding box starts to
# creep (Z 2.112 -> 2.147 by 80) for no further gain, so 40 is the knee of the
# curve. The final call is still visual; this is where to change it.
HEAD_SMOOTHING_ITERATIONS = 40


def joint_centroids(positions, faces):
    """Centroids of the `joint-*` marker cubes -> {joint name: (x, y, z)}."""
    members = {}
    for group, face in faces:
        if group and group.startswith("joint-"):
            members.setdefault(group[len("joint-"):], set()).update(face)
    return {
        name: tuple(sum(positions[i][axis] for i in idx) / len(idx) for axis in range(3))
        for name, idx in members.items()
    }


def head_region(positions, body_indices, skeleton):
    """Everything above the `joint-neck` centroid — 4 280 vertices on the real
    mesh. Note the joint is named `neck`, not `neck-1`; `head` and `head-2` also
    exist, and using either of those would cut the region off mid-skull.

    Deliberately the whole head rather than a front-facing box. A `z > centre`
    test sounds tighter but is not: the `joint-head` centroid sits toward the
    back of the skull, so that test still selects 4 032 of the same 4 280
    vertices while adding a threshold nobody can justify. Taubin does not need
    the box — it removes features by frequency, not by position.

    The eyeballs need no handling here: they live in `helper-l-eye` and
    `helper-r-eye`, so stripping the helper groups already removed them, and the
    face keeps only its sockets."""
    return {i for i in body_indices if positions[i][1] > skeleton["neck"][1]}


def bake(gender):
    with open(f"{SOURCE}/base.obj") as handle:
        positions, faces = parse_obj(handle.readlines())
    with open(f"{SOURCE}/caucasian-{gender}-young.target") as handle:
        positions = apply_target(positions, parse_target(handle.readlines()))

    skeleton = joint_centroids(positions, faces)
    body_faces = [face for group, face in faces if group == "body"]
    body_indices = {i for face in body_faces for i in face}

    region = head_region(positions, body_indices, skeleton)
    adjacency = build_adjacency(body_faces, len(positions))
    positions = taubin_smooth(positions, adjacency, region, HEAD_SMOOTHING_ITERATIONS)

    positions, body_faces = compact(positions, body_faces)
    positions = normalise(positions)
    tris = triangulate(body_faces)

    with open(f"{OUTPUT}/{gender.capitalize()}Base.bodymesh", "wb") as handle:
        handle.write(encode_bodymesh(positions, compute_normals(positions, tris), tris))
    return skeleton, len(positions), len(tris)


def main():
    report = {}
    for gender in ("male", "female"):
        skeleton, vertices, tris = bake(gender)
        report[gender] = skeleton
        print(f"{gender}: {vertices} vertices, {tris} triangles")
    with open(f"{OUTPUT}/BodySkeleton.json", "w") as handle:
        json.dump(report, handle, indent=2, sort_keys=True)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the bake**

```bash
mkdir -p MeasureMe/BodyModel/Resources && python3 tools/bodymesh/bake.py
```

Expected: two lines reporting `13380 vertices, 26756 triangles` for each gender. A vertex count other than 13380 means the group filter is wrong — the body group was measured at exactly 13380 vertices.

- [ ] **Step 3: Verify the output**

```bash
ls -l MeasureMe/BodyModel/Resources/ && python3 -c "
import struct
for g in ('Male','Female'):
    d=open(f'MeasureMe/BodyModel/Resources/{g}Base.bodymesh','rb').read()
    v,i=struct.unpack_from('<II',d,8)
    ys=[struct.unpack_from('<f',d,16+k*12+4)[0] for k in range(v)]
    print(g, d[:4], 'verts',v, 'idx',i, 'y range %.4f..%.4f'%(min(ys),max(ys)), 'size', len(d))
"
```

Expected: magic `b'BMSH'`, 13380 vertices, 80268 indices, y range exactly `0.0000..1.0000`, size 642 208 bytes each.

- [ ] **Step 4: Verify the smoothing kept the skull**

The unit tests can only prove the filter's arithmetic on a toy. This is the
check that it does the right thing to a real head — the claim Task 1's
`test_taubin_retains_far_more_amplitude_than_a_pure_laplacian` docstring defers
to.

```bash
python3 -c "
import sys; sys.path.insert(0,'tools/bodymesh')
import bake
with open('tools/bodymesh/source/base.obj') as h: pos, faces = bake.parse_obj(h.readlines())
with open('tools/bodymesh/source/caucasian-male-young.target') as h:
    pos = bake.apply_target(pos, bake.parse_target(h.readlines()))
sk = bake.joint_centroids(pos, faces)
bf = [f for g, f in faces if g == 'body']
region = bake.head_region(pos, {i for f in bf for i in f}, sk)
adj = bake.build_adjacency(bf, len(pos))
import math
region = sorted(region)
def mean_radius(p):
    c = [sum(p[i][a] for i in region) / len(region) for a in range(3)]
    return sum(math.dist(p[i], c) for i in region) / len(region)
before = mean_radius(pos)
after = mean_radius(bake.taubin_smooth(pos, adj, region, bake.HEAD_SMOOTHING_ITERATIONS))
print('mean radius %.4f -> %.4f  (%.2f%%)' % (before, after, 100 * (after - before) / before))
"
```

Expected: under 1%. Measured at **+0.26%** when this was written.

Use mean radius, **not** the bounding box. The box is measured at the extreme
points, and on a head the extreme points are the ear tips — exactly the
high-frequency detail the filter is supposed to remove. The better the
smoothing works, the worse a bbox metric scores it: bbox X legitimately drops
2.2% here purely because the ears flatten, while the mean radius, which every
one of the 4 231 vertices contributes to, barely moves.

A mean radius that falls by several percent is the real failure signal — it
means the negative mu pass is missing or wrong and the filter has degenerated
into a plain Laplacian, which shrinks.

- [ ] **Step 5: Verify the bake is deterministic**

```bash
shasum MeasureMe/BodyModel/Resources/*.bodymesh > /tmp/bake1.txt && python3 tools/bodymesh/bake.py && shasum MeasureMe/BodyModel/Resources/*.bodymesh | diff /tmp/bake1.txt - && echo DETERMINISTIC
```

Expected: prints `DETERMINISTIC`. This is acceptance criterion 4 from the spec.

- [ ] **Step 6: Commit**

```bash
git add tools/bodymesh/bake.py MeasureMe/BodyModel/Resources
git commit -m "feat(body-model): bake the male and female base meshes"
```

---

## Task 3: `.bodymesh` decoder

**Files:**
- Create: `MeasureMe/BodyModel/BodyMeshFile.swift`
- Test: `MeasureMeTests/BodyMeshFileTests.swift`

**Interfaces:**
- Consumes: the format written by Task 2.
- Produces: `struct BodyBaseMesh` with `positions: [SIMD3<Float>]`, `normals: [SIMD3<Float>]`, `indices: [Int32]`; `enum BodyMeshFile` with `static func decode(_ data: Data) throws -> BodyBaseMesh` and `enum DecodeError: Error, Equatable { case badMagic, unsupportedVersion(UInt32), truncated }`. Task 4 calls `decode`.

- [ ] **Step 1: Write the failing tests**

Create `MeasureMeTests/BodyMeshFileTests.swift`:

```swift
import XCTest
import simd
@testable import MeasureMe

final class BodyMeshFileTests: XCTestCase {
    /// Jeden wierzcholek i jeden trojkat — minimalny poprawny plik.
    private func makeData(
        magic: String = "BMSH",
        version: UInt32 = 1,
        positions: [SIMD3<Float>] = [SIMD3(1, 2, 3)],
        normals: [SIMD3<Float>] = [SIMD3(0, 1, 0)],
        indices: [UInt32] = [0, 0, 0]
    ) -> Data {
        var data = Data(magic.utf8)
        for value in [version, UInt32(positions.count), UInt32(indices.count)] {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        for vector in positions + normals {
            for scalar in [vector.x, vector.y, vector.z] {
                withUnsafeBytes(of: scalar) { data.append(contentsOf: $0) }
            }
        }
        for index in indices {
            withUnsafeBytes(of: index.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    func testDecodeReadsPositionsNormalsAndIndices() throws {
        let mesh = try BodyMeshFile.decode(makeData())
        XCTAssertEqual(mesh.positions, [SIMD3<Float>(1, 2, 3)])
        XCTAssertEqual(mesh.normals, [SIMD3<Float>(0, 1, 0)])
        XCTAssertEqual(mesh.indices, [0, 0, 0])
    }

    func testDecodeRejectsForeignMagic() {
        XCTAssertThrowsError(try BodyMeshFile.decode(makeData(magic: "NOPE"))) { error in
            XCTAssertEqual(error as? BodyMeshFile.DecodeError, .badMagic)
        }
    }

    /// Dlaczego: format ma sie psuc glosno przy zmianie wersji, a nie czytac
    /// starym parserem nowy uklad bajtow i renderowac smieci.
    func testDecodeRejectsFutureVersion() {
        XCTAssertThrowsError(try BodyMeshFile.decode(makeData(version: 2))) { error in
            XCTAssertEqual(error as? BodyMeshFile.DecodeError, .unsupportedVersion(2))
        }
    }

    func testDecodeRejectsTruncatedPayload() {
        XCTAssertThrowsError(try BodyMeshFile.decode(makeData().dropLast(4))) { error in
            XCTAssertEqual(error as? BodyMeshFile.DecodeError, .truncated)
        }
    }

    func testDecodeRejectsDataShorterThanTheHeader() {
        XCTAssertThrowsError(try BodyMeshFile.decode(Data("BMSH".utf8))) { error in
            XCTAssertEqual(error as? BodyMeshFile.DecodeError, .truncated)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeasureMeTests/BodyMeshFileTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'BodyMeshFile' in scope`

- [ ] **Step 3: Write the decoder**

Create `MeasureMe/BodyModel/BodyMeshFile.swift`:

```swift
// BodyMeshFile.swift
//
// **BodyMeshFile**
// Decoder for the baked `.bodymesh` assets.
//
// **Responsibilities:**
// - Validating the header before trusting any offset
// - Producing plain Swift arrays the deformer and renderer can both use
//
// **Why a private format rather than OBJ or USDZ:**
// The mesh has to be reachable as a flat position array — the morph rewrites
// every vertex per frame — so a loader that hands back an opaque scene graph
// would only have to be unpacked again. Parsing 13 380 ASCII vertices at launch
// also costs roughly 50 000 text-to-float conversions, where this is a memcpy.
//
// **Why little-endian is assumed rather than converted:**
// Every Apple target is little-endian, and the writer is a script in this same
// repository. Byte-swapping here would be dead code that could never be tested.
//
import Foundation
import simd

nonisolated struct BodyBaseMesh: Equatable, Sendable {
    /// Feet at y = 0, total height exactly 1, centred in X and Z.
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [Int32]
}

nonisolated enum BodyMeshFile {
    enum DecodeError: Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt32)
        case truncated
    }

    private static let magic = Array("BMSH".utf8)
    private static let headerSize = 16
    private static let currentVersion: UInt32 = 1

    static func decode(_ data: Data) throws -> BodyBaseMesh {
        guard data.count >= headerSize else { throw DecodeError.truncated }

        return try data.withUnsafeBytes { raw in
            guard Array(raw[0..<4]) == magic else { throw DecodeError.badMagic }

            let version = raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
            guard version == currentVersion else { throw DecodeError.unsupportedVersion(version) }

            let vertexCount = Int(raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
            let indexCount = Int(raw.loadUnaligned(fromByteOffset: 12, as: UInt32.self))

            let vectorBytes = vertexCount * 12
            let expected = headerSize + vectorBytes * 2 + indexCount * 4
            guard data.count == expected else { throw DecodeError.truncated }

            func vectors(at offset: Int) -> [SIMD3<Float>] {
                (0..<vertexCount).map { index in
                    let base = offset + index * 12
                    return SIMD3<Float>(
                        raw.loadUnaligned(fromByteOffset: base, as: Float.self),
                        raw.loadUnaligned(fromByteOffset: base + 4, as: Float.self),
                        raw.loadUnaligned(fromByteOffset: base + 8, as: Float.self)
                    )
                }
            }

            let indicesOffset = headerSize + vectorBytes * 2
            return BodyBaseMesh(
                positions: vectors(at: headerSize),
                normals: vectors(at: headerSize + vectorBytes),
                indices: (0..<indexCount).map {
                    Int32(raw.loadUnaligned(fromByteOffset: indicesOffset + $0 * 4, as: UInt32.self))
                }
            )
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeasureMeTests/BodyMeshFileTests 2>&1 | tail -20`
Expected: PASS, 5 tests

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodyMeshFile.swift MeasureMeTests/BodyMeshFileTests.swift
git commit -m "feat(body-model): decode the baked .bodymesh format"
```

---

## Task 4: Asset provider and stature scaling

**Files:**
- Create: `MeasureMe/BodyModel/BodyBaseMeshProvider.swift`
- Test: `MeasureMeTests/BodyBaseMeshProviderTests.swift`

**Interfaces:**
- Consumes: `BodyMeshFile.decode`, `BodyBaseMesh`, `BodyGender` (a `String`-raw-valued enum, so already `Hashable`).
- Produces: `BodyBaseMeshProvider.mesh(for: BodyGender) throws -> BodyBaseMesh` and `BodyBaseMesh.positions(forHeightCm: Double) -> [SIMD3<Float>]`. Task 5 calls both.

- [ ] **Step 1: Write the failing tests**

Create `MeasureMeTests/BodyBaseMeshProviderTests.swift`:

```swift
import XCTest
import simd
@testable import MeasureMe

final class BodyBaseMeshProviderTests: XCTestCase {
    /// Dlaczego: liczba zmierzona na base.obj — grupa `body` ma dokladnie tyle
    /// wierzcholkow. Rozjazd znaczy, ze wypiek zlapal helpery albo jointy.
    func testBakedMeshesCarryTheBodyGroupOnly() throws {
        for gender in BodyGender.allCases {
            let mesh = try BodyBaseMeshProvider.mesh(for: gender)
            XCTAssertEqual(mesh.positions.count, 13_380, "\(gender)")
            XCTAssertEqual(mesh.normals.count, mesh.positions.count, "\(gender)")
            XCTAssertEqual(mesh.indices.count % 3, 0, "\(gender)")
        }
    }

    func testBakedMeshesStandOnTheFloorAtUnitHeight() throws {
        for gender in BodyGender.allCases {
            let ys = try BodyBaseMeshProvider.mesh(for: gender).positions.map(\.y)
            XCTAssertEqual(try XCTUnwrap(ys.min()), 0, accuracy: 1e-5, "\(gender)")
            XCTAssertEqual(try XCTUnwrap(ys.max()), 1, accuracy: 1e-5, "\(gender)")
        }
    }

    func testBakedMeshesContainNoNaN() throws {
        for gender in BodyGender.allCases {
            let mesh = try BodyBaseMeshProvider.mesh(for: gender)
            XCTAssertFalse(mesh.positions.contains { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN }, "\(gender)")
            XCTAssertFalse(mesh.normals.contains { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN }, "\(gender)")
        }
    }

    /// Dlaczego: indeks poza tablica to crash w SceneKit, nie wyjatek.
    func testIndicesStayInsideTheVertexArray() throws {
        for gender in BodyGender.allCases {
            let mesh = try BodyBaseMeshProvider.mesh(for: gender)
            let limit = Int32(mesh.positions.count)
            XCTAssertNil(mesh.indices.first { $0 < 0 || $0 >= limit }, "\(gender)")
        }
    }

    func testScalingToStatureMakesTheMeshThatManyMetresTall() throws {
        let scaled = try BodyBaseMeshProvider.mesh(for: .male).positions(forHeightCm: 182)
        XCTAssertEqual(scaled.map(\.y).max() ?? 0, 1.82, accuracy: 1e-4)
    }

    func testMaleAndFemaleBasesAreDifferentMeshes() throws {
        let male = try BodyBaseMeshProvider.mesh(for: .male)
        let female = try BodyBaseMeshProvider.mesh(for: .female)
        XCTAssertNotEqual(male.positions, female.positions)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeasureMeTests/BodyBaseMeshProviderTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'BodyBaseMeshProvider' in scope`

- [ ] **Step 3: Write the provider**

Create `MeasureMe/BodyModel/BodyBaseMeshProvider.swift`:

```swift
// BodyBaseMeshProvider.swift
//
// **BodyBaseMeshProvider**
// Loads a baked base mesh out of the app bundle, once per gender.
//
// **Responsibilities:**
// - Resolving a gender to its bundled `.bodymesh` resource
// - Caching the decoded mesh for the lifetime of the process
// - Scaling the unit-height mesh to a measured stature
//
// **Why the cache is not a weak one:**
// Two meshes at 13 380 vertices are a little over a megabyte in total and both
// are needed for as long as the screen is reachable. Re-decoding on every
// appearance would trade that megabyte for a hitch on a user-visible transition.
//
import Foundation
import simd

enum BodyBaseMeshProvider {
    enum LoadError: Error, Equatable {
        case resourceMissing(String)
    }

    private static var cache: [BodyGender: BodyBaseMesh] = [:]

    static func mesh(for gender: BodyGender) throws -> BodyBaseMesh {
        if let cached = cache[gender] { return cached }

        let name = gender == .male ? "MaleBase" : "FemaleBase"
        guard let url = Bundle.main.url(forResource: name, withExtension: "bodymesh") else {
            throw LoadError.resourceMissing(name)
        }
        let mesh = try BodyMeshFile.decode(Data(contentsOf: url))
        cache[gender] = mesh
        return mesh
    }
}

extension BodyBaseMesh {
    /// Positions in metres for a body of the given stature. The baked mesh is
    /// exactly one unit tall, so stature is a single uniform scale.
    func positions(forHeightCm heightCm: Double) -> [SIMD3<Float>] {
        let scale = Float(heightCm / 100)
        return positions.map { $0 * scale }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeasureMeTests/BodyBaseMeshProviderTests 2>&1 | tail -20`
Expected: PASS, 6 tests

If `resourceMissing` is thrown, the synchronized group did not pick the files up as bundle resources. Confirm with `find $(xcodebuild -showBuildSettings -scheme MeasureMe 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}')/MeasureMe.app -name '*.bodymesh'` and, if empty, add the `Resources` folder to the target's Copy Bundle Resources phase in Xcode.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodyBaseMeshProvider.swift MeasureMeTests/BodyBaseMeshProviderTests.swift
git commit -m "feat(body-model): load and scale the baked base meshes"
```

---

## Task 5: Render the base mesh

**Files:**
- Modify: `MeasureMe/BodyModel/MannequinView.swift` (whole file)
- Modify: `MeasureMe/BodyModel/BodyModelScreen.swift:192-208`
- Test: `MeasureMeTests/__Snapshots__/BodyModelSnapshotTests/` (re-recorded)

**Interfaces:**
- Consumes: `BodyBaseMeshProvider.mesh(for:)`, `BodyBaseMesh.positions(forHeightCm:)`.
- Produces: `MannequinView(parameters:gender:rotationRadians:)`. Stage 2 replaces the geometry call inside it.

- [ ] **Step 1: Replace the geometry source in `MannequinView`**

In `MeasureMe/BodyModel/MannequinView.swift`, add the gender property next to `parameters`:

```swift
    let parameters: BodyMeshParameters
    let gender: BodyGender
    /// Horizontal rotation applied by the drag gesture.
    var rotationRadians: Double = 0
```

Replace the two `BodyGeometryBuilder.geometry(for: parameters)` calls — one in `makeUIView`, one in `updateUIView` — with `geometry()`, and add:

```swift
    /// Stage 1 renders the base mesh at the measured stature. Measurements do
    /// not reach the shape yet; that is the deformer's job in stage 2.
    private func geometry() -> SCNGeometry? {
        guard let mesh = try? BodyBaseMeshProvider.mesh(for: gender) else { return nil }
        let positions = mesh.positions(forHeightCm: parameters.heightCm)
        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) }),
                SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) })
            ],
            elements: [SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)]
        )
    }
```

- [ ] **Step 2: Swap the material for clay and light it**

In `updateUIView`, replace the material block:

```swift
        // A matte, near-neutral clay. Deliberately not skin: a half-realistic
        // skin tone on a body that is not actually the user's reads as uncanny,
        // where clay reads as a model of a body, which is what this is.
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.78, green: 0.76, blue: 0.73, alpha: 1)
        material.roughness.contents = 0.65
        material.metalness.contents = 0.0
        material.isDoubleSided = false
        bodyNode.geometry?.materials = [material]
```

`isDoubleSided` drops to `false`: the base mesh is a closed volume, so back faces are never meant to be visible, and drawing them was only ever hiding the old open-ended tubes.

In `makeUIView`, replace the two-light rig with three lights, so the silhouette reads in both themes:

```swift
        for (intensity, position) in [(700.0, SCNVector3(2, 3, 3)),
                                      (260.0, SCNVector3(-3, 2, 1)),
                                      (180.0, SCNVector3(0, 2, -4))] {
            let node = SCNNode()
            node.light = SCNLight()
            node.light?.type = .directional
            node.light?.intensity = intensity
            node.position = position
            node.look(at: SCNVector3(0, 0.9, 0))
            view.scene?.rootNode.addChildNode(node)
        }

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 300
        view.scene?.rootNode.addChildNode(ambient)
```

- [ ] **Step 3: Add the contact shadow**

Without it the body floats off the card's background. In `makeUIView`, after
the lights, make the key light cast a deferred shadow onto an invisible plane
at the feet:

```swift
        // A shadow catcher: `.deferred` draws the shadow without lighting the
        // plane itself, so the floor never appears — only the darkening under
        // the feet, which is the only cue that the body is standing on
        // something rather than hovering.
        let floor = SCNNode(geometry: SCNPlane(width: 4, height: 4))
        floor.eulerAngles.x = -.pi / 2
        floor.geometry?.firstMaterial?.lightingModel = .constant
        floor.geometry?.firstMaterial?.writesToDepthBuffer = false
        floor.geometry?.firstMaterial?.colorBufferWriteMask = []
        floor.castsShadow = false
        view.scene?.rootNode.addChildNode(floor)
```

and on the first (700-intensity) light only:

```swift
            node.light?.castsShadow = true
            node.light?.shadowMode = .deferred
            node.light?.shadowRadius = 12
            node.light?.shadowColor = UIColor.black.withAlphaComponent(0.35)
```

Apply `castsShadow` to just that one light — three shadow-casting lights would
give the body three overlapping shadows.

- [ ] **Step 4: Pass the gender in from the screen**

In `MeasureMe/BodyModel/BodyModelScreen.swift`, change the `mannequinCard` guard to bind both values:

```swift
                if let parameters = viewModel.currentParameters, let gender = resolvedGender {
                    MannequinView(parameters: parameters, gender: gender, rotationRadians: rotationRadians)
```

- [ ] **Step 5: Build and check it compiles**

Run: `xcodebuild build -scheme MeasureMe -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Re-record the snapshots and look at them**

Run the snapshot tests, let them fail, then inspect the recorded images:

```bash
xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeasureMeTests/BodyModelSnapshotTests 2>&1 | tail -20
```

Open `MeasureMeTests/__Snapshots__/BodyModelSnapshotTests/*.png` and check, against the reference the user supplied: head present and featureless, hands and feet present, shoulders continuous with the torso, no visible seam at the neck, wrists or ankles, and shading that reads as a solid volume rather than a flat cut-out. If the face still shows a nose or lips, raise `HEAD_SMOOTHING_ITERATIONS` in `bake.py`, re-run the bake, and repeat.

Delete the stale baselines and re-record only once the render looks right.

- [ ] **Step 7: Run the whole body-model suite**

Run: `xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MeasureMeTests 2>&1 | tail -30`
Expected: PASS. `BodyGeometryBuilderTests` still passes — that file is untouched and stays until stage 2.

- [ ] **Step 8: Commit**

```bash
git add MeasureMe/BodyModel/MannequinView.swift MeasureMe/BodyModel/BodyModelScreen.swift MeasureMeTests/__Snapshots__
git commit -m "feat(body-model): render the real base mesh instead of ring stacks"
```

---

## Stage 1 exit criteria

- [ ] `python3 tools/bodymesh/test_bake.py` passes
- [ ] The bake is byte-for-byte reproducible (spec acceptance criterion 4)
- [ ] `MeasureMeTests` passes in full
- [ ] The rendered mannequin has a head, hands, feet and shoulders, and is visually close to the supplied reference
- [ ] `BodyGeometryBuilder.swift` is unchanged and still on the branch
- [ ] The branch is NOT merged — the mannequin ignores measurements until stage 2 lands

## Deferred to Stage 2

`BodyRegionMap`, `BodyMeshDeformer`, the piecewise-linear Y warp for the torso/leg
split, the circumference round-trip test, and the removal of
`BodyGeometryBuilder.swift` with its tests. `BodySkeleton.json` is produced by
this stage but read by that one.
