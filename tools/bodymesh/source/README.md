# Vendored MakeHuman sources

Build-time inputs for `bake.py`. **Not** shipped in the app and **not** part of
any Xcode target — they live outside `MeasureMe/` on purpose, because the
project uses `PBXFileSystemSynchronizedRootGroup` and anything under that
directory is picked up by the build automatically.

| File | Source |
|---|---|
| `base.obj` | `makehumancommunity/makehuman@master:makehuman/data/3dobjs/base.obj` |
| `caucasian-male-young.target` | `…/data/targets/macrodetails/caucasian-male-young.target` |
| `caucasian-female-young.target` | `…/data/targets/macrodetails/caucasian-female-young.target` |

## Licence

**CC0 1.0 Universal.** MakeHuman splits its licensing: the source code is AGPL,
but `LICENSE.md` section C places the assets — *"The base mesh and proxies /
Targets and modifiers / Textures"* — under CC0. Only assets are vendored here,
so the AGPL does not reach this project. No attribution or fee is required for
App Store distribution; this file records the provenance anyway.

## Notes

`base.obj` carries three kinds of geometry. Only `body` is real:

| Group family | Vertices | Fate |
|---|---|---|
| `body` | 13 380 | Kept |
| `helper-*` | 4 778 | Dropped — cloth/hair proxies, includes the eyeballs |
| `joint-*` | 1 000 | Dropped from geometry; centroids kept as the skeleton |

Units are decimetres (body height 16.659 → ×10.805 for 180 cm). The mesh is in
A-pose: the shoulder→elbow axis sits 39.6° off vertical, knee→ankle 9.3°.
