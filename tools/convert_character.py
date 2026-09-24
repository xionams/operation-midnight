#!/usr/bin/env python3
"""Turn Kenney's CC0 rigged character into an Operation Midnight soldier.

    ~/tools/blender/blender --background --factory-startup \
        --python tools/convert_character.py -- <pack dir> <out.glb>

The generated infantry in tools/asset_specs.py are 304 triangles of boxes
and they do not move. At 8-10 pixels tall that is not a modelling problem
- no amount of geometry survives that size - it is an ANIMATION problem,
and animation is the one thing the spec language cannot express at all.

Kenney's pack is CC0 and rigged, so this brings it in. Three things have
to happen on the way:

1. **Scale.** The pack is authored ~3.76 units tall; docs/ART_DIRECTION
   section 5 puts infantry at 1.72m, and that figure is what selection
   rings, health bars and crush checks are derived from. It is applied as
   `nodes/root_scale` on the Godot import, NOT here: scaling an armature
   in Blender does not survive the glTF export as a node scale, and
   applying the scale to the armature instead rescales the bones while
   the actions keep storing bone-local translations for the old size.

2. **Faction marking.** The pack is skinned by TEXTURE, and this game's
   faction system is a material slot named `Faction` that is recoloured
   at runtime. A texture-skinned character has nowhere for that to go, so
   a helmet and two shoulder pads are added as geometry, weighted to the
   bones they sit on so they follow the animation. Section 8: infantry
   carry faction colour on helmet and shoulder.

3. **Junk actions.** The FBX exports carry single-frame "Targeting Pose"
   artefacts alongside the real clips; exporting those gives the runtime
   a list of animations most of which do nothing.

4. **Baking the IK.** The pack's rig is IK-driven: its clips key control
   bones (`LeftFootIK`, `KneeCtrl`, `HeelRoll`) and the deform bones
   follow through Blender constraints. glTF has no constraints, so an
   unbaked export produces animations that play - the time advances, the
   player reports itself running - while every deform bone sits in bind
   pose. The character T-poses through the entire clip. Every action is
   baked with visual keying so the deform bones carry the motion
   themselves.

5. **The body material.** The pack skins its character with a loose PNG
   that the FBX does not reference, so the material arrives with no
   texture and - the part that actually bites - a base colour alpha of
   ZERO. Exported as-is the soldier is completely invisible and only the
   faction helmet renders, which is exactly what happened the first time.
   The body is repainted in this game's own palette instead of adopting
   the pack's texture: every other surface in the game is flat colour per
   material slot, and at eight pixels tall a skin texture is invisible
   anyway.
"""

import glob
import os
import sys

import bpy
import addon_utils
from mathutils import Vector

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
from glb import srgb_to_linear  # noqa: E402


def linear(rgba):
    """The palette is authored sRGB; glTF baseColorFactor is linear.

    tools/glb.py has carried this conversion since the whole game came
    out washed out without it. Blender's Base Color input is linear too,
    so a palette value dropped straight in exports a third too bright -
    OLIVE arrived in Godot as (0.57, 0.60, 0.51), a pale grey-green.
    """
    return tuple(srgb_to_linear(c) for c in rgba[:3]) + (rgba[3],)

## docs/ART_DIRECTION.md section 5.
TARGET_HEIGHT = 1.72

## docs/ART_DIRECTION.md section 2: infantry wear OLIVE, the same value
## the generated soldiers already use.
BODY_COLOUR = (0.290, 0.318, 0.220, 1.0)

## Kept deliberately chunky. At gameplay zoom a soldier is under ten
## pixels tall, so a subtle marking is no marking - section 8 asks for
## 8-15% of visible surface, and from this camera the helmet IS most of
## the visible surface.
## The head bone spans a full unit and is about 0.7 wide, so the first
## attempt at 0.62 wide put the helmet INSIDE the skull and nothing
## showed. It has to be wider than the head and sit on top of it.
## The head bone runs from its origin up one full unit and is roughly
## 0.7 across. A helmet has to be WIDER than that and shallow, capping the
## top of the skull: 0.62 wide put it inside the head and nothing showed,
## and 0.92 tall made it a box the head sat inside.
HELMET_SCALE = (0.86, 0.86, 0.40)
HELMET_OFFSET = (0.0, -0.02, 0.76)
PAD_SCALE = (0.34, 0.34, 0.22)


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def faction_material():
    material = bpy.data.materials.new("Faction")
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    ## Neutral sand; the runtime overwrites it per faction. Matches
    ## FactionPaint.NEUTRAL so an un-painted model is never obviously wrong.
    bsdf.inputs["Base Color"].default_value = linear((0.851, 0.784, 0.478, 1.0))
    bsdf.inputs["Roughness"].default_value = 0.6
    material.name = "Faction"
    return material


def bolt_on(name, bone, offset, scale, rig, material):
    """A box that rides a bone, so it follows the animation.

    Weighted rather than parented to the bone directly: a separate object
    parented to a bone is a second draw call per soldier, and at 120 units
    that is 120 extra draws for a helmet.
    """
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bpy.ops.mesh.primitive_cube_add(size=1.0)
    cube = bpy.context.object
    cube.name = name + "_src"
    head = rig.data.bones[bone].head_local
    cube.location = Vector(head) + Vector(offset)
    cube.scale = Vector(scale)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    cube.data.materials.append(material)
    group = cube.vertex_groups.new(name=bone)
    group.add(range(len(cube.data.vertices)), 1.0, 'REPLACE')

    bpy.data.objects.remove(obj, do_unlink=True)
    return cube


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    base, out = argv[0], argv[1]
    addon_utils.enable("io_scene_gltf2", default_set=True)
    clear()

    bpy.ops.import_scene.fbx(filepath=os.path.join(base, "Model/characterMedium.fbx"))
    rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    body = next(o for o in bpy.data.objects if o.type == 'MESH')
    keep = {o.name for o in bpy.data.objects}

    if rig.animation_data is None:
        rig.animation_data_create()
    kept = set()
    pending = []

    ## Each animation FBX arrives with its own armature and its own
    ## action. Take the action, give it to the real rig as an NLA strip
    ## so the exporter emits it, and drop the duplicate skeleton.
    for path in sorted(glob.glob(os.path.join(base, "Animations", "*.fbx"))):
        name = os.path.splitext(os.path.basename(path))[0]
        before = set(bpy.data.actions.keys())
        bpy.ops.import_scene.fbx(filepath=path)
        clip = None
        for action in bpy.data.actions:
            if action.name in before:
                continue
            ## Anything one frame long is a bind-pose artefact, not a clip.
            if action.frame_range[1] - action.frame_range[0] > 1.5:
                clip = action
        if clip is not None:
            clip.name = name
            clip.use_fake_user = True
            pending.append(clip)
            print("  clip %-8s %d frames" % (name, clip.frame_range[1] - clip.frame_range[0]))
        for obj in list(bpy.data.objects):
            if obj.name not in keep:
                bpy.data.objects.remove(obj, do_unlink=True)

    ## Bake each clip onto the deform bones. See the docstring: without
    ## this the export animates control bones nobody is listening to.
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.select_all(action='SELECT')
    for clip in pending:
        rig.animation_data.action = clip
        start, end = int(clip.frame_range[0]), int(clip.frame_range[1])
        bpy.context.scene.frame_start = start
        bpy.context.scene.frame_end = end
        baked = bpy.ops.nla.bake(
            frame_start=start, frame_end=end, step=1,
            only_selected=False, visual_keying=True,
            clear_constraints=False, clear_parents=False,
            use_current_action=True, bake_types={'POSE'})
        result = rig.animation_data.action
        result.name = clip.name
        result.use_fake_user = True
        kept.add(result.name)
        print("  baked %-8s -> %d fcurves" % (result.name, len(result.fcurves)))
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.animation_data.action = None

    for name in sorted(kept):
        action = bpy.data.actions.get(name)
        if action is None:
            continue
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, int(action.frame_range[0]), action)

    ## Drop every action that did not become a clip, or the runtime gets a
    ## list of animations most of which are a single bind pose. Tracked by
    ## name rather than by use_fake_user - the FBX importer sets a fake
    ## user on everything it brings in, so that flag says nothing here.
    for action in list(bpy.data.actions):
        if action.name not in kept:
            bpy.data.actions.remove(action)

    ## Repaint the imported body. Without this it exports with alpha 0
    ## and the soldier is invisible; see the module docstring.
    for slot in body.data.materials:
        if slot is None:
            continue
        slot.use_nodes = True
        bsdf = slot.node_tree.nodes.get("Principled BSDF")
        if bsdf is not None:
            bsdf.inputs["Base Color"].default_value = linear(BODY_COLOUR)
            bsdf.inputs["Roughness"].default_value = 0.85
            if "Alpha" in bsdf.inputs:
                bsdf.inputs["Alpha"].default_value = 1.0
        slot.blend_method = 'OPAQUE'
        slot.name = "Fatigues"

    material = faction_material()
    parts = [
        bolt_on("Helmet", "Head", HELMET_OFFSET, HELMET_SCALE, rig, material),
        bolt_on("PadL", "LeftShoulder", (0.14, 0.0, 0.02), PAD_SCALE, rig, material),
        bolt_on("PadR", "RightShoulder", (-0.14, 0.0, 0.02), PAD_SCALE, rig, material),
    ]

    ## One mesh, so a soldier stays one draw call.
    bpy.ops.object.select_all(action='DESELECT')
    for part in parts:
        part.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()

    ## The joined parts need the armature deform the body already has.
    if not any(m.type == 'ARMATURE' for m in body.modifiers):
        modifier = body.modifiers.new("Armature", 'ARMATURE')
        modifier.object = rig

    ## Report the scale Godot needs rather than applying it; see the
    ## module docstring for why this is not done here.
    factor = TARGET_HEIGHT / max(body.dimensions.z, 1e-6)
    print("  authored %.2f units tall -> set nodes/root_scale=%.4f"
          % (body.dimensions.z, factor))

    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(
        filepath=out, export_format='GLB',
        export_animations=True, export_skins=True,
        export_animation_mode='ACTIONS', export_yup=True)
    print("  wrote %s (%d bytes)" % (out, os.path.getsize(out)))


if __name__ == "__main__":
    main()
