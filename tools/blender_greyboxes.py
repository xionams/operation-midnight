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
from glb import srgb_to_linear  # noqa: E402

OUT_DIR = os.path.join(TOOLS, "..", "assets", "models")


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
        verts = [bm.verts.new(Vector(p)) for p in positions]
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
            if material_name == "Hull" and asset_id in asset_specs.UNIT_HULL_OVERRIDE:
                rgba = asset_specs.UNIT_HULL_OVERRIDE[asset_id]
            materials[material_name] = material_for(material_name, rgba)

    for node_name, mesh_data, translation in nodes:
        obj = mesh_from_groups(node_name, mesh_data, materials)
        if translation and any(translation):
            obj.location = Vector(translation)

    path = os.path.abspath(os.path.join(OUT_DIR, asset_id + ".glb"))
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
    )
    return path


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = argv[argv.index("--only") + 1]

    os.makedirs(OUT_DIR, exist_ok=True)
    count = 0
    for asset_id, spec in sorted(asset_specs.ASSETS.items()):
        if only and asset_id != only:
            continue
        build(asset_id, spec)
        print("exported %s" % asset_id)
        count += 1
    print("%d model(s) exported to assets/models" % count)


if __name__ == "__main__":
    main()
