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
    """Little-endian; see the format table in the stage 1 plan."""
    out = bytearray(b"BMSH")
    out += struct.pack("<III", 1, len(positions), len(tris) * 3)
    for point in positions:
        out += struct.pack("<fff", *point)
    for normal in normals:
        out += struct.pack("<fff", *normal)
    for tri in tris:
        out += struct.pack("<III", *tri)
    return bytes(out)


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
