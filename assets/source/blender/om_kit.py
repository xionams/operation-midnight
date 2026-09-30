"""Operation Midnight modelling kit (Blender, bpy).

Every Phase 3 model is authored as a Python function against this kit and
built headless in Blender:

    python assets/source/blender/build.py            # every asset
    python assets/source/blender/build.py --only patrol_boat

(`python` here is an interpreter with the `bpy` module - Blender as a
Python module, `pip install bpy==4.2.0` - or run the same file with
`blender --background --python`.)

Conventions (the contract with the game - see docs/ART_DIRECTION.md 3b):
  - Authored in GAME space: metres, +Y up, the model's front faces -Z,
    origin at ground (or waterline) centre. Converted to Blender Z-up
    only when vertices are written, and back by the glTF exporter.
  - A model is a set of NODES. Most assets have one; a part that moves
    gets its own node with its origin at the pivot: "Turret" (aimed by
    TurretAim), "Radar", "Crane", "Fan", "Rotor" (spun by VisualAnimator).
  - Colour is carried in vertex colour (part colour x baked AO), so the
    palette is unlimited while every model uses a handful of materials:
      Body     painted surfaces          rough, dielectric
      Metal    bare machinery            metallic
      Glass    windows, optics           glossy, dark
      Faction  faction markings          recoloured at runtime (FactionPaint)
      Emissive lamps and panels          small, used sparingly
  - A bevel pass chamfers hard edges so they catch light at RTS distance,
    and Cycles bakes ambient occlusion across all nodes together, so the
    contact shadow where a turret meets its hull is real.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

# ------------------------------------------------------------- palette
#
# docs/ART_DIRECTION.md section 2, plus the Phase 3 naval and civilian
# additions (section 3b). sRGB 0-1.

GUNMETAL = (0.227, 0.247, 0.271)
STEEL = (0.290, 0.314, 0.345)
STEEL_LIGHT = (0.42, 0.45, 0.48)
OLIVE = (0.290, 0.318, 0.220)
OLIVE_DARK = (0.22, 0.24, 0.17)
FIELD_GREEN = (0.235, 0.267, 0.188)
CONCRETE = (0.470, 0.455, 0.418)
CONCRETE_DARK = (0.330, 0.320, 0.296)
CONCRETE_LIGHT = (0.555, 0.540, 0.500)
RUST = (0.431, 0.290, 0.180)
SAND = (0.604, 0.557, 0.431)
SAND_DARK = (0.48, 0.44, 0.33)
SHADOW = (0.133, 0.149, 0.161)
RUBBER = (0.09, 0.09, 0.10)
AMBER = (0.878, 0.651, 0.235)
HAZARD = (0.80, 0.62, 0.16)
GLASS_DARK = (0.075, 0.098, 0.120)
NAVY_GREY = (0.34, 0.37, 0.40)
NAVY_DARK = (0.20, 0.22, 0.25)
DECK = (0.30, 0.31, 0.30)
HULL_RED = (0.36, 0.16, 0.13)          # antifouling below the boot top
SUB_BLACK = (0.10, 0.11, 0.12)
BRICK = (0.46, 0.30, 0.24)
PLASTER = (0.70, 0.66, 0.58)
ROOF_TILE = (0.40, 0.24, 0.19)
ROOF_TIN = (0.44, 0.46, 0.46)
TIMBER = (0.36, 0.28, 0.20)
ORE = (0.78, 0.60, 0.20)
ORE_DARK = (0.46, 0.33, 0.12)
LAMP = (1.0, 0.82, 0.45)
WHITE = (1.0, 1.0, 1.0)

MATERIALS = {
    # name: (roughness, metallic, emission strength)
    "Body": (0.78, 0.0, 0.0),
    "Metal": (0.42, 0.75, 0.0),
    "Glass": (0.12, 0.0, 0.0),
    "Faction": (0.6, 0.0, 0.0),
    "Emissive": (0.9, 0.0, 3.0),
}

_SRGB_CACHE = {}


def _linear(c):
    def one(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (one(c[0]), one(c[1]), one(c[2]), 1.0)


def to_blender(p):
    x, y, z = p
    return Vector((x, -z, y))


# --------------------------------------------------------------- model

class Node:
    """One exported object: geometry relative to its own origin (pivot)."""

    def __init__(self, name, origin=(0.0, 0.0, 0.0)):
        self.name = name
        self.origin = origin
        self.bm = bmesh.new()
        self.color_layer = self.bm.loops.layers.float_color.new("Col")
        self.materials = []  # slot index -> material name

    ## Glass is folded into Body rather than owning a slot of its own.
    ## A material slot becomes a mesh surface, a surface becomes a draw
    ## call, and that call is paid TWICE - once in the main pass and once
    ## in the shadow pass. Glass and Emissive slots were 19% of all
    ## surfaces across units, buildings and ships, and a vision block or
    ## a cockpit is a few dark pixels at an RTS camera height whether it
    ## is shiny or matte. Its colour is per-vertex, so it stays as dark
    ## as it was. Emissive is NOT folded: a lamp that glows is a
    ## readability cue, and there are far fewer of them.
    MERGE = {"Glass": "Body"}

    def _slot(self, material):
        material = self.MERGE.get(material, material)
        if material not in self.materials:
            self.materials.append(material)
        return self.materials.index(material)

    # All primitives below take GAME-space coordinates relative to the
    # node origin, and a (material, colour) pair.

    def _finish(self, verts, faces, material, color, smooth=False):
        slot = self._slot(material)
        ## sRGB on purpose: Godot's glTF importer reads COLOR_0 as sRGB
        ## (verified - linear values rendered ~5x too dark).
        col = (color[0], color[1], color[2], 1.0)
        made = []
        for f in faces:
            try:
                face = self.bm.faces.new([verts[i] for i in f])
            except ValueError:
                continue
            face.material_index = slot
            face.smooth = smooth
            for loop in face.loops:
                loop[self.color_layer] = col
            made.append(face)
        return made

    def _verts(self, points, xform):
        return [self.bm.verts.new(to_blender(xform(p))) for p in points]

    @staticmethod
    def _xform(center, rot_y=0.0, rot_x=0.0, rot_z=0.0):
        cy, sy = math.cos(math.radians(rot_y)), math.sin(math.radians(rot_y))
        cx, sx = math.cos(math.radians(rot_x)), math.sin(math.radians(rot_x))
        cz, sz = math.cos(math.radians(rot_z)), math.sin(math.radians(rot_z))

        def f(p):
            x, y, z = p
            # roll (z), pitch (x), then yaw (y)
            x, y = x * cz - y * sz, x * sz + y * cz
            y, z = y * cx - z * sx, y * sx + z * cx
            x, z = x * cy + z * sy, -x * sy + z * cy
            return (x + center[0], y + center[1], z + center[2])
        return f

    def box(self, size, center, material="Body", color=STEEL, rot_y=0.0,
            rot_x=0.0, rot_z=0.0, taper=1.0):
        """Axis box; `taper` < 1 shrinks the top face (a frustum)."""
        w, h, d = size[0] / 2.0, size[1], size[2] / 2.0
        t = taper
        pts = [(-w, 0, -d), (w, 0, -d), (w, 0, d), (-w, 0, d),
               (-w * t, h, -d * t), (w * t, h, -d * t), (w * t, h, d * t), (-w * t, h, d * t)]
        # centre given at the box's vertical middle, like glb.box
        c = (center[0], center[1] - h / 2.0, center[2])
        v = self._verts(pts, self._xform(c, rot_y, rot_x, rot_z))
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        return self._finish(v, faces, material, color)

    def prism(self, profile, x0, x1, material="Body", color=STEEL, center=(0, 0, 0), rot_y=0.0):
        """A side profile [(z, y), ...] extruded across X from x0 to x1.

        The workhorse for vehicle hulls: a sloped glacis, a raked rear
        deck and a skirt are one polygon, not five boxes.
        """
        n = len(profile)
        pts = [(x0, y, z) for z, y in profile] + [(x1, y, z) for z, y in profile]
        v = self._verts(pts, self._xform(center, rot_y))
        faces = [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
        # orientation of the profile decides winding; fix normals later
        for i in range(n):
            j = (i + 1) % n
            faces.append((i, j, n + j, n + i))
        return self._finish(v, faces, material, color)

    def plan(self, outline, y0, y1, material="Body", color=STEEL, center=(0, 0, 0), taper=1.0):
        """A footprint [(x, z), ...] extruded up from y0 to y1."""
        n = len(outline)
        cx = sum(p[0] for p in outline) / n
        cz = sum(p[1] for p in outline) / n
        pts = [(x, y0, z) for x, z in outline] + \
              [(cx + (x - cx) * taper, y1, cz + (z - cz) * taper) for x, z in outline]
        v = self._verts(pts, self._xform(center))
        faces = [tuple(range(n)), tuple(range(n, 2 * n))[::-1]]
        for i in range(n):
            j = (i + 1) % n
            faces.append((i, j, n + j, n + i))
        return self._finish(v, faces, material, color)

    def loft(self, rings, material="Body", color=STEEL, center=(0, 0, 0), cap=True, smooth=False):
        """Skin consecutive rings: [(z, [(x, y), ...]), ...], equal counts.

        Ship hulls and the submarine are lofts: a handful of cross
        sections along the length, which is what gives a bow a real
        entry and a stern a real run instead of a stepped box.
        """
        count = len(rings[0][1])
        pts = []
        for z, ring in rings:
            pts += [(x, y, z) for x, y in ring]
        v = self._verts(pts, self._xform(center))
        faces = []
        for r in range(len(rings) - 1):
            a, b = r * count, (r + 1) * count
            for i in range(count):
                j = (i + 1) % count
                faces.append((a + i, a + j, b + j, b + i))
        if cap:
            faces.append(tuple(range(count))[::-1])
            last = (len(rings) - 1) * count
            faces.append(tuple(range(last, last + count)))
        return self._finish(v, faces, material, color, smooth=smooth)

    def cylinder(self, radius, height, center, material="Metal", color=STEEL,
                 axis="y", segments=12, radius_top=None, rot_y=0.0, smooth=True):
        """Upright by default; axis "x" or "z" lays it down. Centre is mid-height."""
        rt = radius if radius_top is None else radius_top
        ring0, ring1 = [], []
        for i in range(segments):
            a = math.tau * i / segments
            ring0.append((math.cos(a) * radius, -height / 2.0, math.sin(a) * radius))
            ring1.append((math.cos(a) * rt, height / 2.0, math.sin(a) * rt))
        rx = 0.0
        rz = 0.0
        if axis == "x":
            rz = 90.0
        elif axis == "z":
            rx = 90.0
        v = self._verts(ring0 + ring1, self._xform(center, rot_y, rx, rz))
        n = segments
        faces = [tuple(range(n)), tuple(range(n, 2 * n))[::-1]]
        for i in range(n):
            j = (i + 1) % n
            faces.append((i, n + i, n + j, j))
        made = self._finish(v, faces[2:], material, color, smooth=smooth)
        made += self._finish(v, faces[:2], material, color, smooth=False)
        return made

    def tube(self, p0, p1, radius, material="Metal", color=STEEL, segments=8, radius_end=None):
        """A cylinder from point p0 to point p1 (pipes, barrels, masts)."""
        a, b = Vector(p0), Vector(p1)
        d = b - a
        length = d.length
        mid = (a + b) / 2.0
        horizontal = math.hypot(d.x, d.z)
        yaw = math.degrees(math.atan2(d.x, d.z))
        pitch = math.degrees(math.atan2(horizontal, d.y))
        re = radius if radius_end is None else radius_end
        ring0, ring1 = [], []
        for i in range(segments):
            ang = math.tau * i / segments
            ring0.append((math.cos(ang) * radius, -length / 2.0, math.sin(ang) * radius))
            ring1.append((math.cos(ang) * re, length / 2.0, math.sin(ang) * re))
        v = self._verts(ring0 + ring1, self._xform(tuple(mid), yaw, pitch, 0.0))
        n = segments
        faces = [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
        faces += [tuple(range(n)), tuple(range(n, 2 * n))[::-1]]
        return self._finish(v, faces, material, color, smooth=True)

    def sphere(self, radius, center, material="Metal", color=STEEL, rings=6, segments=10, squash=1.0, smooth=True):
        pts = [(0, -radius * squash, 0)]
        for r in range(1, rings):
            phi = math.pi * r / rings
            y = -math.cos(phi) * radius * squash
            rr = math.sin(phi) * radius
            for s in range(segments):
                a = math.tau * s / segments
                pts.append((math.cos(a) * rr, y, math.sin(a) * rr))
        pts.append((0, radius * squash, 0))
        v = self._verts(pts, self._xform(center))
        faces = []
        top = len(pts) - 1
        for s in range(segments):
            faces.append((0, 1 + (s + 1) % segments, 1 + s))
        for r in range(rings - 2):
            a = 1 + r * segments
            b = a + segments
            for s in range(segments):
                t = (s + 1) % segments
                faces.append((a + s, a + t, b + t, b + s))
        last = 1 + (rings - 2) * segments
        for s in range(segments):
            faces.append((last + s, last + (s + 1) % segments, top))
        return self._finish(v, faces, material, color, smooth=smooth)


class Model:
    def __init__(self, asset_id, category, footprint=None):
        self.asset_id = asset_id
        self.category = category
        self.nodes = []
        self.footprint = footprint

    def node(self, name, origin=(0.0, 0.0, 0.0)):
        n = Node(name, origin)
        self.nodes.append(n)
        return n


# -------------------------------------------------------------- build

def _material(name):
    key = name
    if key in bpy.data.materials:
        return bpy.data.materials[key]
    rough, metal, emit = MATERIALS[name]
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0.0:
        bsdf.inputs["Emission Color"].default_value = _linear(LAMP)
        bsdf.inputs["Emission Strength"].default_value = emit
    if name == "Faction":
        bsdf.inputs["Base Color"].default_value = _linear((0.85, 0.78, 0.48))
    return mat


def _bevel(obj, width, segments=1):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    # 50 deg: box edges (90) bevel, cylinder facets (8+ segments, <=45) do
    # not - they are smooth-shaded, and bevelling them only added triangles.
    mod.angle_limit = math.radians(50.0)
    mod.harden_normals = True
    mod.miter_outer = "MITER_ARC"
    bpy.context.view_layer.objects.active = obj
    obj.data.shade_smooth()
    obj.data.set_sharp_from_angle(angle=math.radians(35.0))
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier="Bevel")


def _bake_ao(objects, samples=24, floor=0.28, ground_z=-0.02):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.render.bake.target = "VERTEX_COLORS"
    # AO reach: Cycles defaults to 10 m, at which a roof overhang shades a
    # whole wall (every corner occluded, so the face interpolates dark).
    # Contact shadow in creases and under hulls is what AO is for here.
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 1.1
    ao_layers = []
    for obj in objects:
        attr = obj.data.color_attributes.new("AO", "FLOAT_COLOR", "CORNER")
        obj.data.color_attributes.active_color = attr
        ao_layers.append(attr)
    # a ground plane so the underside of a hull is occluded like the real
    # thing sitting on terrain; removed after the bake
    # (ships float: their models set ao_ground = None and bake in open air)
    ground = None
    if ground_z is not None:
        bpy.ops.mesh.primitive_plane_add(size=200.0, location=(0, 0, ground_z))
        ground = bpy.context.active_object
        ground.data.materials.append(_material("Body"))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    try:
        bpy.ops.object.bake(type="AO")
    except RuntimeError as err:
        print("  AO bake failed: %s" % err)
    if ground is not None:
        bpy.data.objects.remove(ground, do_unlink=True)
    for obj in objects:
        col = obj.data.color_attributes["Col"]
        ao = obj.data.color_attributes["AO"]
        for i in range(len(col.data)):
            a = floor + (1.0 - floor) * ao.data[i].color[0]
            c = col.data[i].color
            col.data[i].color = (c[0] * a, c[1] * a, c[2] * a, 1.0)
        obj.data.color_attributes.remove(ao)
        obj.data.color_attributes.active_color = obj.data.color_attributes["Col"]
        obj.data.color_attributes.render_color_index = 0


def build(model, out_path, bevel=0.06, ao=True):
    ground_z = getattr(model, "ao_ground", -0.02)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = []
    for node in model.nodes:
        mesh = bpy.data.meshes.new(node.name)
        bmesh.ops.recalc_face_normals(node.bm, faces=node.bm.faces)
        bmesh.ops.remove_doubles(node.bm, verts=node.bm.verts, dist=0.0005)
        node.bm.to_mesh(mesh)
        node.bm.free()
        obj = bpy.data.objects.new(node.name, mesh)
        bpy.context.collection.objects.link(obj)
        for name in node.materials:
            mesh.materials.append(_material(name))
        obj.location = to_blender(node.origin)
        objects.append(obj)
    if bevel > 0.0:
        for obj in objects:
            _bevel(obj, bevel)
    if ao:
        _bake_ao(objects, ground_z=ground_z)
    tris = 0
    for obj in objects:
        obj.data.calc_loop_triangles()
        tris += len(obj.data.loop_triangles)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=out_path, export_format="GLB", export_apply=True, export_yup=True,
        export_texcoords=False, export_vertex_color="ACTIVE",
        export_all_vertex_colors=False, use_selection=True)
    return tris
