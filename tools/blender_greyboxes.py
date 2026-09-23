#!/usr/bin/env python3
"""Rebuild every greybox in Blender, from the same spec as the local one.

    blender --background --python tools/blender_greyboxes.py
    blender --background --python tools/blender_greyboxes.py -- --only command_hq

Blender is not installed in the environment these assets were first built
in, so tools/build_greyboxes.py emits the .glb files directly. This script
exists so the models are editable by a human the moment Blender IS
available: it reads tools/asset_specs.py - the same dimensions, the same
parts, the same materials - and produces the same files.

Because both paths share one spec, "the Blender file" and "the shipped
glb" cannot drift. Change the spec, re-run either one.

Once a greybox is replaced by real modelled art, drop that asset from
ASSETS and keep the .glb; nothing else in the project needs to know.
"""

import os
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)

try:
    import bpy
    import bmesh
    from mathutils import Vector
except ImportError:  # pragma: no cover - only meaningful inside Blender
    sys.exit("This script must be run inside Blender:\n"
             "  blender --background --python tools/blender_greyboxes.py")

import asset_specs  # noqa: E402
import mesh_refine  # noqa: E402
from glb import srgb_to_linear  # noqa: E402

OUT_DIR = os.path.join(TOOLS, "..", "assets", "models")

## Defaults for the refinement pass; --no-refine / --no-ao / --segments N
## override them. See tools/mesh_refine.py for what each stage does.
REFINE = True
BAKE_AO = True
BEVEL_SEGMENTS = 1


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material_for(name, rgba):
    key = "OM_" + name
    if key in bpy.data.materials:
        return bpy.data.materials[key]
    material = bpy.data.materials.new(key)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    linear = [srgb_to_linear(c) for c in rgba[:3]] + [rgba[3]]
    bsdf.inputs["Base Color"].default_value = linear
    roughness, metallic = asset_specs_material_preset(name)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    ## The exported material name is the contract with the runtime: the
    ## faction slot is found by this exact string.
    material.name = name
    return material


def asset_specs_material_preset(name):
    from glb import MATERIAL_PRESETS
    return MATERIAL_PRESETS.get(name, (0.8, 0.0))


def to_blender(position):
    """Spec coordinates (Y-up, glTF convention) into Blender's Z-up space.

    tools/asset_specs.py describes the world the way glTF and Godot do:
    +Y is up. Blender's +Z is up. Feeding spec coordinates straight into
    bmesh therefore lays every model on its side, and the glTF exporter's
    export_yup then "converts" an orientation that was already correct,
    landing the model a further 90 degrees out.

    Nothing caught this for a whole commit because Godot had cached .scn
    imports of the older files and never re-read the new .glb - the
    validation test was measuring the previous models. Delete
    .godot/imported before trusting an asset test.
    """
    x, y, z = position
    return Vector((x, -z, y))


def mesh_from_groups(object_name, mesh_data, materials):
    """Rebuild one of the spec's Mesh objects as real Blender geometry."""
    blender_mesh = bpy.data.meshes.new(object_name)
    obj = bpy.data.objects.new(object_name, blender_mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    slot_index = {}
    for material_name in mesh_data.groups:
        slot_index[material_name] = len(obj.data.materials)
        obj.data.materials.append(materials[material_name])

    for material_name, (positions, _normals, indices) in mesh_data.groups.items():
        index = slot_index[material_name]
        verts = [bm.verts.new(to_blender(p)) for p in positions]
        bm.verts.index_update()
        for i in range(0, len(indices), 3):
            try:
                face = bm.faces.new((verts[indices[i]], verts[indices[i + 1]],
                                     verts[indices[i + 2]]))
                face.material_index = index
            except ValueError:
                ## Duplicate face from a shared vertex; harmless for a greybox.
                continue

    bm.to_mesh(blender_mesh)
    bm.free()

    blender_mesh.validate()
    ## Hard normals everywhere except cylinders, per the art direction.
    for polygon in blender_mesh.polygons:
        polygon.use_smooth = False
    return obj


def build(asset_id, spec):
    clear_scene()
    nodes = spec["builder"]()

    materials = {}
    for _, mesh_data, _ in nodes:
        for material_name in mesh_data.groups:
            rgba = asset_specs.MATERIAL_COLORS[material_name]
            if material_name == "Hull":
                if asset_id in asset_specs.UNIT_HULL_OVERRIDE:
                    rgba = asset_specs.UNIT_HULL_OVERRIDE[asset_id]
                elif asset_id in asset_specs.BUILDING_HULL_OVERRIDE:
                    rgba = asset_specs.BUILDING_HULL_OVERRIDE[asset_id]
            materials[material_name] = material_for(material_name, rgba)

    built = []
    for node_name, mesh_data, translation in nodes:
        obj = mesh_from_groups(node_name, mesh_data, materials)
        if translation and any(translation):
            obj.location = to_blender(translation)
        built.append(obj)

    before = after = 0
    if REFINE:
        ## Decided once for the whole asset; see mesh_refine.should_bevel.
        bevel = mesh_refine.should_bevel(built)
        for obj in built:
            was, now = mesh_refine.refine(
                obj, bevel=bevel, segments=BEVEL_SEGMENTS)
            before += was
            after += now
        ## Baked after every object is in its final place, so the contact
        ## shadow where a turret meets its hull is actually occluded by the
        ## hull rather than by nothing.
        if BAKE_AO:
            mesh_refine.bake_ao(built)

    path = os.path.abspath(os.path.join(OUT_DIR, asset_id + ".glb"))
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        ## These models are flat-coloured per material slot and carry no
        ## maps, so UVs are dead weight in every file. The AO bake rides in
        ## COLOR_0; export_all_vertex_colors would add a second, unused set.
        export_texcoords=False,
        export_vertex_color='ACTIVE' if BAKE_AO else 'NONE',
        export_all_vertex_colors=False,
    )
    return path, before, after


def main():
    global REFINE, BAKE_AO, BEVEL_SEGMENTS
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = argv[argv.index("--only") + 1]
    ## The refinement pass is the expensive and the reversible part, so it
    ## can be switched off to rebuild the plain greyboxes for comparison.
    if "--no-refine" in argv:
        REFINE = False
    if "--no-ao" in argv:
        BAKE_AO = False
    if "--segments" in argv:
        BEVEL_SEGMENTS = int(argv[argv.index("--segments") + 1])

    os.makedirs(OUT_DIR, exist_ok=True)
    count = 0
    total_before = total_after = 0
    for asset_id, spec in sorted(asset_specs.ASSETS.items()):
        if only and asset_id != only:
            continue
        _, before, after = build(asset_id, spec)
        total_before += before
        total_after += after
        print("exported %-24s %5d -> %5d tris%s"
              % (asset_id, before, after, "" if after != before else "  (no bevel)"))
        count += 1
    ratio = (total_after / total_before) if total_before else 1.0
    print("%d model(s) exported to assets/models" % count)
    print("triangles %d -> %d  (x%.2f)" % (total_before, total_after, ratio))


if __name__ == "__main__":
    main()
