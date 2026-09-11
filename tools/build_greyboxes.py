#!/usr/bin/env python3
"""Emit every greybox .glb from tools/asset_specs.py.

Also checks each model against its declared size and triangle budget.
A greybox whose bounds disagree with `body_size` is worse than no model
at all - selection rings, health bars and placement footprints are all
derived from those numbers, so the error shows up as art that does not
fit its own collision.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import asset_specs  # noqa: E402
from glb import write_glb  # noqa: E402

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models")
TOLERANCE = 0.06  # metres; chamfers and mast tips are allowed to differ slightly


def bounds(nodes):
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for _, mesh, translation in nodes:
        for positions, _n, _i in mesh.groups.values():
            for point in positions:
                for axis in range(3):
                    value = point[axis] + (translation[axis] if translation else 0.0)
                    lo[axis] = min(lo[axis], value)
                    hi[axis] = max(hi[axis], value)
    return lo, hi


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    problems = []
    rows = []

    for asset_id, spec in sorted(asset_specs.ASSETS.items()):
        nodes = spec["builder"]()

        materials = {}
        for _, mesh, _ in nodes:
            for name in mesh.groups:
                materials[name] = asset_specs.MATERIAL_COLORS[name]
        if asset_id in asset_specs.UNIT_HULL_OVERRIDE and "Hull" in materials:
            materials = dict(materials)
            materials["Hull"] = asset_specs.UNIT_HULL_OVERRIDE[asset_id]

        path = os.path.join(OUT_DIR, asset_id + ".glb")
        triangles = write_glb(path, asset_id, nodes, materials)

        lo, hi = bounds(nodes)
        actual = tuple(hi[i] - lo[i] for i in range(3))
        declared = spec["size"]

        # The origin must sit on the ground: y >= 0, centred in X and Z.
        if lo[1] < -TOLERANCE:
            problems.append("%s: geometry below ground (min y = %.2f)" % (asset_id, lo[1]))
        overhang = asset_specs.OVERHANG.get(asset_id, (0.0, 0.0, 0.0))
        for axis, label in ((0, "x"), (2, "z")):
            centre = (lo[axis] + hi[axis]) / 2.0
            if abs(centre) > 0.35 + overhang[axis] / 2.0:
                problems.append("%s: not centred on %s (centre %.2f)" % (asset_id, label, centre))
        for axis, label in ((0, "x"), (1, "y"), (2, "z")):
            allowed = declared[axis] + overhang[axis] + TOLERANCE
            if actual[axis] > allowed:
                problems.append("%s: %s is %.2f, declared %.2f (+%.2f overhang)" % (
                    asset_id, label, actual[axis], declared[axis], overhang[axis]))
        if triangles > spec["tri_budget"]:
            problems.append("%s: %d tris over budget %d" % (
                asset_id, triangles, spec["tri_budget"]))

        rows.append((asset_id, spec["class"], triangles, spec["tri_budget"], actual, declared))

    width = max(len(r[0]) for r in rows)
    print("%-*s  %-12s %6s %7s  %-22s %s" % (
        width, "asset", "class", "tris", "budget", "actual (w,h,d)", "declared"))
    for asset_id, cls, triangles, budget, actual, declared in rows:
        print("%-*s  %-12s %6d %7d  %-22s %s" % (
            width, asset_id, cls, triangles, budget,
            "%.2f x %.2f x %.2f" % actual,
            "%.2f x %.2f x %.2f" % tuple(declared)))

    total = sum(r[2] for r in rows)
    print("\n%d models, %d triangles total, mean %.0f" % (len(rows), total, total / len(rows)))

    if problems:
        print("\n%d PROBLEM(S):" % len(problems))
        for problem in problems:
            print("  " + problem)
        return 1
    print("\nAll models within declared size and triangle budget.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
