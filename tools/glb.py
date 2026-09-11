"""Minimal glTF 2.0 (.glb) writer.

Blender is not installable in this environment without root, so the
greybox meshes are emitted directly. The geometry vocabulary here is
deliberately tiny - boxes, cylinders, wedges, cones - because that is
exactly what the art direction's shape language calls for, and because
anything a greybox needs beyond that should be a real model instead.

Conventions enforced here rather than left to each asset (see
docs/ART_DIRECTION.md section 12): metres, +Y up, -Z forward, origin at
ground centre, CCW winding, normals out.
"""

import json
import math
import struct

# Material presets: (roughness, metallic, unshaded)
MATERIAL_PRESETS = {
    "Hull":     (0.75, 0.0),
    "Dark":     (0.85, 0.0),
    "Metal":    (0.45, 0.8),
    "Faction":  (0.60, 0.0),
    "Glass":    (0.15, 0.0),
    "Emissive": (0.90, 0.0),
}


class Mesh:
    """Accumulates triangles, grouped by material name."""

    def __init__(self):
        # material name -> (positions, normals, indices)
        self.groups = {}

    def _group(self, material):
        if material not in self.groups:
            self.groups[material] = ([], [], [])
        return self.groups[material]

    def add_tri(self, material, a, b, c, normal=None):
        pos, nrm, idx = self._group(material)
        if normal is None:
            ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
            vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
            normal = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
            length = math.sqrt(sum(n * n for n in normal)) or 1.0
            normal = tuple(n / length for n in normal)
        base = len(pos)
        for vertex in (a, b, c):
            pos.append(vertex)
            nrm.append(normal)
        idx.extend((base, base + 1, base + 2))

    def add_quad(self, material, a, b, c, d, normal=None):
        self.add_tri(material, a, b, c, normal)
        self.add_tri(material, a, c, d, normal)


def _rot_y(point, angle):
    if not angle:
        return point
    s, c = math.sin(angle), math.cos(angle)
    x, y, z = point
    return (x * c + z * s, y, -x * s + z * c)


def box(mesh, material, size, pos=(0.0, 0.0, 0.0), rot_y=0.0, chamfer=0.0):
    """Axis-aligned box, optionally chamfered.

    `pos` is the box CENTRE. The chamfer is what stops structures reading
    as untextured cubes under a single light, so it is on by default for
    anything large enough to carry one.
    """
    sx, sy, sz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    c = min(chamfer, sx * 0.6, sy * 0.6, sz * 0.6)

    def place(x, y, z):
        p = _rot_y((x, y, z), rot_y)
        return (p[0] + pos[0], p[1] + pos[1], p[2] + pos[2])

    if c <= 0.0:
        corners = [place(x * sx, y * sy, z * sz)
                   for x, y, z in ((-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1),
                                   (-1, 1, -1), (1, 1, -1), (1, 1, 1), (-1, 1, 1))]
        b = corners
        mesh.add_quad(material, b[7], b[6], b[5], b[4])   # top
        mesh.add_quad(material, b[0], b[1], b[2], b[3])   # bottom
        mesh.add_quad(material, b[3], b[2], b[6], b[7])   # +Z
        mesh.add_quad(material, b[1], b[0], b[4], b[5])   # -Z
        mesh.add_quad(material, b[2], b[1], b[5], b[6])   # +X
        mesh.add_quad(material, b[0], b[3], b[7], b[4])   # -X
        return

    # Chamfered: a top face inset by c, a bottom face, and a skirt.
    top_y, bot_y = sy, -sy
    inner_top = [place(x, top_y, z) for x, z in
                 ((-sx + c, -sz + c), (sx - c, -sz + c), (sx - c, sz - c), (-sx + c, sz - c))]
    outer = [place(x, top_y - c, z) for x, z in
             ((-sx, -sz), (sx, -sz), (sx, sz), (-sx, sz))]
    bottom = [place(x, bot_y, z) for x, z in
              ((-sx, -sz), (sx, -sz), (sx, sz), (-sx, sz))]

    mesh.add_quad(material, inner_top[3], inner_top[2], inner_top[1], inner_top[0])
    mesh.add_quad(material, bottom[0], bottom[1], bottom[2], bottom[3])
    for i in range(4):
        j = (i + 1) % 4
        mesh.add_quad(material, outer[i], outer[j], inner_top[j], inner_top[i])
        mesh.add_quad(material, bottom[i], bottom[j], outer[j], outer[i])


def cylinder(mesh, material, radius, height, pos=(0.0, 0.0, 0.0), segments=12,
             axis="y", rot_y=0.0, top_radius=None):
    """Cylinder/cone. `pos` is the centre. Side normals are smoothed."""
    top_r = radius if top_radius is None else top_radius
    half = height / 2.0

    def place(x, y, z):
        if axis == "z":
            x, y, z = x, z, y
        elif axis == "x":
            x, y, z = y, x, z
        p = _rot_y((x, y, z), rot_y)
        return (p[0] + pos[0], p[1] + pos[1], p[2] + pos[2])

    ring_top, ring_bot, normals = [], [], []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        cx, cz = math.cos(a), math.sin(a)
        ring_top.append(place(cx * top_r, half, cz * top_r))
        ring_bot.append(place(cx * radius, -half, cz * radius))
        n = _rot_y((cx, 0.0, cz), rot_y)
        if axis == "z":
            n = (n[0], n[2], n[1])
        elif axis == "x":
            n = (n[1], n[0], n[2])
        normals.append(n)

    top_c = place(0.0, half, 0.0)
    bot_c = place(0.0, -half, 0.0)
    for i in range(segments):
        j = (i + 1) % segments
        if top_r > 1e-6:
            mesh.add_tri(material, top_c, ring_top[i], ring_top[j])
        mesh.add_tri(material, bot_c, ring_bot[j], ring_bot[i])
        # Sides, with per-vertex smoothed normals.
        pos_g, nrm_g, idx_g = mesh._group(material)
        base = len(pos_g)
        if top_r > 1e-6:
            quad = ((ring_bot[i], normals[i]), (ring_bot[j], normals[j]),
                    (ring_top[j], normals[j]), (ring_top[i], normals[i]))
            for p, n in quad:
                pos_g.append(p)
                nrm_g.append(n)
            idx_g.extend((base, base + 1, base + 2, base, base + 2, base + 3))
        else:
            tri = ((ring_bot[i], normals[i]), (ring_bot[j], normals[j]), (top_c, normals[i]))
            for p, n in tri:
                pos_g.append(p)
                nrm_g.append(n)
            idx_g.extend((base, base + 1, base + 2))


def wedge(mesh, material, size, pos=(0.0, 0.0, 0.0), rot_y=0.0):
    """Triangular prism sloping up toward -Z. Ramps, roofs, glacis plates."""
    sx, sy, sz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0

    def place(x, y, z):
        p = _rot_y((x, y, z), rot_y)
        return (p[0] + pos[0], p[1] + pos[1], p[2] + pos[2])

    bl = [place(-sx, -sy, sz), place(sx, -sy, sz), place(sx, -sy, -sz), place(-sx, -sy, -sz)]
    tl = [place(-sx, sy, sz), place(sx, sy, sz)]
    mesh.add_quad(material, bl[0], bl[1], bl[2], bl[3])      # bottom
    mesh.add_quad(material, bl[1], bl[0], tl[0], tl[1])      # back
    mesh.add_quad(material, tl[1], tl[0], bl[3], bl[2])      # slope
    mesh.add_tri(material, bl[0], bl[3], tl[0])
    mesh.add_tri(material, bl[1], tl[1], bl[2])


def _pad(data, alignment=4, fill=b"\x00"):
    remainder = len(data) % alignment
    return data if remainder == 0 else data + fill * (alignment - remainder)


def write_glb(path, name, nodes, materials):
    """Write a .glb.

    `nodes` is a list of (node_name, Mesh, translation).
    `materials` maps material name -> (r, g, b, a).
    """
    buffer = bytearray()
    accessors, buffer_views, meshes, gltf_nodes = [], [], [], []
    material_index, gltf_materials = {}, []

    for mat_name, rgba in materials.items():
        roughness, metallic = MATERIAL_PRESETS.get(mat_name, (0.8, 0.0))
        entry = {
            "name": mat_name,
            "pbrMetallicRoughness": {
                "baseColorFactor": list(rgba),
                "metallicFactor": metallic,
                "roughnessFactor": roughness,
            },
            "doubleSided": False,
        }
        if mat_name == "Emissive":
            entry["emissiveFactor"] = list(rgba[:3])
        material_index[mat_name] = len(gltf_materials)
        gltf_materials.append(entry)

    def add_accessor(values, component_type, type_name, per, minmax=False):
        offset = len(buffer)
        fmt = "<f" if component_type == 5126 else "<I"
        for value in values:
            if per == 1:
                buffer.extend(struct.pack(fmt, value))
            else:
                for component in value:
                    buffer.extend(struct.pack(fmt, component))
        length = len(buffer) - offset
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": length})
        accessor = {
            "bufferView": len(buffer_views) - 1,
            "componentType": component_type,
            "count": len(values),
            "type": type_name,
        }
        if minmax:
            columns = list(zip(*values))
            accessor["min"] = [min(c) for c in columns]
            accessor["max"] = [max(c) for c in columns]
        accessors.append(accessor)
        while len(buffer) % 4:
            buffer.append(0)
        return len(accessors) - 1

    child_indices = []
    for node_name, mesh, translation in nodes:
        primitives = []
        for mat_name, (positions, normals, indices) in mesh.groups.items():
            if not positions:
                continue
            primitives.append({
                "attributes": {
                    "POSITION": add_accessor(positions, 5126, "VEC3", 3, minmax=True),
                    "NORMAL": add_accessor(normals, 5126, "VEC3", 3),
                },
                "indices": add_accessor(indices, 5125, "SCALAR", 1),
                "material": material_index[mat_name],
            })
        if not primitives:
            continue
        meshes.append({"name": node_name, "primitives": primitives})
        node = {"name": node_name, "mesh": len(meshes) - 1}
        if translation and any(translation):
            node["translation"] = list(translation)
        gltf_nodes.append(node)
        child_indices.append(len(gltf_nodes) - 1)

    # No wrapper node: Godot already supplies a root named after the file,
    # and a second one just adds a transform per instance at 120 units.
    gltf = {
        "asset": {"version": "2.0", "generator": "operation-midnight greybox pipeline"},
        "scene": 0,
        "scenes": [{"nodes": child_indices}],
        "nodes": gltf_nodes,
        "meshes": meshes,
        "materials": gltf_materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(buffer)}],
    }

    json_chunk = _pad(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), 4, b" ")
    bin_chunk = _pad(bytes(buffer), 4)
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)

    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(json_chunk), 0x4E4F534A))
        handle.write(json_chunk)
        handle.write(struct.pack("<II", len(bin_chunk), 0x004E4942))
        handle.write(bin_chunk)

    triangles = sum(len(g[2]) // 3 for _, mesh, _ in nodes for g in mesh.groups.values())
    return triangles
