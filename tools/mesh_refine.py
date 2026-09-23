#!/usr/bin/env python3
"""Bevel and ambient-occlusion pass, run inside Blender over built greyboxes.

The spec in tools/asset_specs.py describes what a model IS - a hull this
big, a turret there, a faction band along that face. It deliberately says
nothing about how edges catch light, because the writer it was first built
for (tools/glb.py) emits triangles and nothing else.

This module is the difference between those two things. It takes the
objects tools/blender_greyboxes.py has already built and gives them the
two properties a box cannot have on its own:

  Bevelled edges.  A perfectly sharp edge between two flat faces reflects
  nothing, so the only thing separating those faces is their shading. A
  bevel puts a narrow third face along the edge at an intermediate angle,
  which catches a highlight and draws the silhouette of the object. This
  is most of the visual gain, and it is why "low poly" art from 2010 and
  from now look nothing alike.

  Baked ambient occlusion.  Where two surfaces meet in a crevice - a
  turret sitting on a hull, a roof deck on a building - less sky light
  reaches the corner. Baking that into vertex colours costs no texture
  memory and no UV atlas, which matters at 42 models on a phone.

Both stages are optional and measured; see refine() and bake_ao().
"""

import math

try:
    import bpy
    import bmesh
except ImportError:  # pragma: no cover - only meaningful inside Blender
    raise SystemExit("tools/mesh_refine.py must be imported inside Blender")


## Radians. Only edges sharper than this are bevelled, so the flat
## continuation across a subdivided face is left alone.
BEVEL_ANGLE = math.radians(30.0)
## Above this angle a face boundary stays hard. Set to match BEVEL_ANGLE so
## the narrow bevel faces blend into their neighbours while the main faces
## of a box still meet at a crisp line.
SMOOTH_ANGLE = math.radians(30.0)

## Bevel width is derived from each object's own size rather than fixed.
## These models span two orders of magnitude - a 0.18m gun barrel and a
## 12m war factory are in the same file - and a width that reads correctly
## on the factory swallows the barrel whole.
## docs/ART_DIRECTION.md section 6 asks for a chamfer around 0.1m on large
## flat faces. An earlier pass here used 1.2% clamped to 30mm, which at a
## 14-45m camera is roughly one pixel - the bevel was present in the mesh
## and invisible on screen, which is the worst of both. These numbers put
## a 5m structure at the spec'd 0.1m and scale down from there.
WIDTH_FRACTION = 0.030
WIDTH_MIN = 0.010
WIDTH_MAX = 0.100

## Assets whose largest dimension is under this are not bevelled at all.
##
## docs/ART_DIRECTION.md section 6: "No bevel small enough to vanish at
## gameplay zoom." RTSCamera sits between 14m and 45m, and at that range
## a 12mm chamfer on a 1.7m infantry figure is well under a pixel - so it
## buys nothing, and it cost 3.8x the triangles on the one class that
## appears 120 at a time. Measured: infantry went 304 -> 1152 triangles
## against a 400 budget before this gate existed.
MIN_BEVEL_EXTENT = 2.0

AO_SAMPLES = 24
## Ambient occlusion is a multiplier on albedo, and a full-strength bake
## turns every crevice black, which on a top-down camera reads as dirt
## rather than shape. Held well off the floor.
AO_FLOOR = 0.55

COLOR_ATTRIBUTE = "Color"


def _bbox_min_extent(obj):
    """Smallest dimension of the object's local bounding box."""
    dims = [d for d in obj.dimensions]
    positive = [d for d in dims if d > 1e-6]
    return min(positive) if positive else 0.0


def _tris(mesh):
    return sum(len(polygon.vertices) - 2 for polygon in mesh.polygons)


## Vertices closer together than this are the same vertex. The spec works
## in metres and its smallest deliberate feature is around 20mm, so this is
## three orders of magnitude below anything real.
WELD_DISTANCE = 0.0001


def weld(obj):
    """Merge coincident vertices so the mesh has interior edges at all.

    This is not an optimisation, it is a precondition. mesh_from_groups
    builds each material group by calling bm.verts.new() per triangle
    corner, so a cube arrives as twelve unconnected triangles that happen
    to touch. Every edge is therefore a boundary edge, no edge has two
    faces, and the angle between those faces is undefined - so a bevel set
    to 'ANGLE' finds nothing to bevel and silently returns the mesh
    unchanged. That is exactly what it did, on all 42 models, before this
    existed.

    Welding across material groups is intentional and safe: faces keep
    their own material_index, and a Hull/Faction seam is coplanar, so the
    angle limit leaves it alone.
    """
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    merged = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=WELD_DISTANCE)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    merged -= len(bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return merged


def bevel_width_for(obj):
    """Bevel width scaled to this object, clamped to a sane band.

    use_clamp_overlap stops a bevel from eating a part narrower than the
    width, but a clamped bevel is an inconsistent bevel: the edge quietly
    gets a different width than its neighbours. Scaling by the object's
    own smallest extent means the clamp is a backstop rather than the
    normal case.
    """
    extent = _bbox_min_extent(obj)
    if extent <= 0.0:
        return WIDTH_MIN
    return max(WIDTH_MIN, min(WIDTH_MAX, extent * WIDTH_FRACTION))


def should_bevel(objects):
    """Whether this asset is big enough on screen for a bevel to show.

    Decided for the asset as a whole rather than per object, so a building
    and the small mast on its roof are treated consistently - a bevelled
    body beside an unbevelled fitting reads as a modelling mistake.
    """
    largest = 0.0
    for obj in objects:
        if obj.type != 'MESH':
            continue
        largest = max(largest, max(obj.dimensions))
    return largest >= MIN_BEVEL_EXTENT


def refine(obj, bevel=True, width=None, segments=1, verbose=False):
    """Bevel and shade one object in place. Returns (tris_before, tris_after).

    Two segments doubles the added geometry for a rounding nobody reads at
    this camera distance, so the default is a single-segment chamfer: one
    extra face per edge, which is all that is needed for the edge to catch
    a highlight.
    """
    mesh = obj.data
    before = _tris(mesh)
    ## Always weld, even when not bevelling: a soup mesh also breaks
    ## smooth shading and gives the AO bake no continuous surface.
    weld(obj)
    if not bevel:
        return before, before

    if width is None:
        width = bevel_width_for(obj)

    view_layer = bpy.context.view_layer
    view_layer.objects.active = obj
    obj.select_set(True)

    modifier = obj.modifiers.new("Bevel", 'BEVEL')
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = 'ANGLE'
    modifier.angle_limit = BEVEL_ANGLE
    modifier.use_clamp_overlap = True
    ## Without hardened normals the auto-smooth below bleeds the bevel's
    ## shading back across the large flat faces, which is the opposite of
    ## what this pass is for.
    modifier.harden_normals = True

    ## harden_normals is a no-op on flat-shaded geometry, so the smoothing
    ## has to be established before the modifier is applied.
    bpy.ops.object.shade_auto_smooth(angle=SMOOTH_ANGLE)
    view_layer.objects.active = obj
    try:
        bpy.ops.object.modifier_apply(modifier="Bevel")
    except RuntimeError as error:
        ## One malformed object must not abort a 42-model run.
        obj.modifiers.remove(modifier)
        print("  refine: bevel failed on %s (%s)" % (obj.name, error))
        return before, before

    after = _tris(mesh)
    if verbose:
        print("  refine %-22s %5d -> %5d tris  (width %.4f)"
              % (obj.name, before, after, width))
    return before, after


def _ensure_color_attribute(mesh):
    existing = mesh.color_attributes.get(COLOR_ATTRIBUTE)
    if existing is not None:
        return existing
    return mesh.color_attributes.new(
        name=COLOR_ATTRIBUTE, type='FLOAT_COLOR', domain='CORNER')


def bake_ao(objects, samples=AO_SAMPLES, floor=AO_FLOOR):
    """Bake AO across ALL of an asset's objects at once, into vertex colours.

    Baking per object would miss the only occlusion that matters here:
    these assets are assemblies, and the interesting contact shadow is
    where the turret meets the hull, not anywhere on the turret alone.

    Returns the (min, max) baked luminance, or None if nothing was baked.
    """
    meshes = [o for o in objects if o.type == 'MESH' and len(o.data.polygons)]
    if not meshes:
        return None

    attributes = []
    for obj in meshes:
        attribute = _ensure_color_attribute(obj.data)
        obj.data.color_attributes.active_color = attribute
        attributes.append(attribute)
        ## A bake target needs at least one material slot to write through.
        if not obj.data.materials:
            obj.data.materials.append(bpy.data.materials.new("OM_BakeDummy"))

    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = samples
    scene.render.bake.target = 'VERTEX_COLORS'
    scene.render.bake.use_selected_to_active = False

    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]

    try:
        bpy.ops.object.bake(type='AO')
    except RuntimeError as error:
        print("  bake_ao: failed (%s)" % error)
        return None

    low, high = 1.0, 0.0
    for attribute in attributes:
        for entry in attribute.data:
            ## Lift the bake off zero before it is written. Godot multiplies
            ## COLOR_0 into albedo, and an unlifted bake would drive the
            ## crevices to black rather than shading them.
            value = floor + (1.0 - floor) * entry.color[0]
            low = min(low, value)
            high = max(high, value)
            entry.color = (value, value, value, 1.0)
    return low, high
