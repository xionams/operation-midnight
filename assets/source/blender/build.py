"""Build Operation Midnight's Phase 3 models into assets/models/<category>/.

    python assets/source/blender/build.py                 # all
    python assets/source/blender/build.py --only harvester scout_vehicle
    python assets/source/blender/build.py --list

`python` must provide the `bpy` module (pip install bpy==4.2.0, Python
3.11) - or run this file through `blender --background --python`.

Each asset is a function in units.py / buildings.py / naval.py /
civilian.py returning an om_kit.Model. Output paths are derived from the
model's category, so a .tres points at assets/models/<category>/<id>.glb.
"""

import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import om_kit  # noqa: E402
import units  # noqa: E402
import buildings  # noqa: E402
import naval  # noqa: E402
import civilian  # noqa: E402
import wrecks  # noqa: E402

REGISTRY = {}
for module in (units, buildings, naval, civilian, wrecks):
    for asset_id, fn in module.ASSETS.items():
        REGISTRY[asset_id] = fn


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if "--list" in argv:
        for asset_id in sorted(REGISTRY):
            print(asset_id)
        return
    only = None
    if "--only" in argv:
        only = argv[argv.index("--only") + 1:]
    started = time.time()
    total = 0
    for asset_id, fn in sorted(REGISTRY.items()):
        if only and asset_id not in only:
            continue
        model = fn()
        out = os.path.join(om_kit.ROOT, "assets", "models", model.category, asset_id + ".glb")
        tris = om_kit.build(model, out, bevel=getattr(model, "bevel", 0.06))
        total += tris
        print("built %-22s %-10s %6d tris  -> %s" % (
            asset_id, model.category, tris, os.path.relpath(out, om_kit.ROOT)))
    print("done: %d triangles in %.1fs" % (total, time.time() - started))


if __name__ == "__main__":
    main()
