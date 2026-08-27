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
| `universal-male-young-minmuscle-maxweight.target` | `…/data/targets/macrodetails/universal-male-young-minmuscle-maxweight.target` |
| `universal-female-young-minmuscle-maxweight.target` | `…/data/targets/macrodetails/universal-female-young-minmuscle-maxweight.target` |

## Licence

**CC0 1.0 Universal.** MakeHuman splits its licensing: the source code is AGPL,
but `LICENSE.md` section C places the assets — *"The base mesh and proxies /
Targets and modifiers / Textures"* — under CC0. Only assets are vendored here,
so the AGPL does not reach this project. No attribution or fee is required for
App Store distribution; this file records the provenance anyway.

## Why two bakes per gender

`bake.py` emits `<Gender>Base.bodymesh` and `<Gender>Heavy.bodymesh`. The app
blends them by body fat before the girth deformer runs, because radial scaling
of cross-sections changes how big a body is, not what kind of body it is — a
lean bake driven to 125 kg comes out as an inflated athlete.

`universal-*-averagemuscle-averageweight.target` is an empty file, which is what
makes the arithmetic simple: the mesh with only the gender target applied IS the
neutral point of the muscle and weight axes, so the weight target is a pure
delta. **minmuscle-maxweight**, not averagemuscle: the latter moves a vertex by
at most 2.8 cm against the gender target's 14.3, because it describes a heavy
body that kept its muscle. The minimum-muscle variant reaches 12.5 cm.

## Notes

`base.obj` carries three kinds of geometry. Only `body` is real:

| Group family | Vertices | Fate |
|---|---|---|
| `body` | 13 380 | Kept |
| `helper-*` | 4 778 | Dropped — cloth/hair proxies, includes the eyeballs |
| `joint-*` | 1 000 | Dropped from geometry; centroids kept as the skeleton |

Units are decimetres (body height 16.659 → ×10.805 for 180 cm). The mesh is in
A-pose: the shoulder→elbow axis sits 39.6° off vertical, knee→ankle 9.3°.
