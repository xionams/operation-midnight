"""The single source of truth for every greybox model.

Both generators read this file - the pure-Python one that runs here, and
tools/blender_greyboxes.py for when Blender is available - so the two can
never drift apart. Dimensions are taken from `body_size` in config/*.tres
and MUST stay in step with them: gameplay derives selection rings, health
bars and placement footprints from those numbers, so a model that
disagrees is a bug you can see.

See docs/ART_DIRECTION.md. Palette entries here are that document's
tables, converted to linear-ish float triples.
"""

import math

from glb import Mesh, box, cylinder, wedge

# ----------------------------------------------------------- palette

GUNMETAL      = (0.227, 0.247, 0.271, 1.0)
STEEL         = (0.290, 0.314, 0.345, 1.0)
OLIVE         = (0.290, 0.318, 0.220, 1.0)
FIELD_GREEN   = (0.235, 0.267, 0.188, 1.0)
CONCRETE      = (0.541, 0.522, 0.475, 1.0)
CONCRETE_DARK = (0.369, 0.357, 0.325, 1.0)
RUST          = (0.431, 0.290, 0.180, 1.0)
SAND          = (0.604, 0.557, 0.431, 1.0)
SHADOW        = (0.133, 0.149, 0.161, 1.0)
AMBER         = (0.878, 0.651, 0.235, 1.0)
GLASS_DARK    = (0.075, 0.098, 0.120, 1.0)
NEUTRAL_MARK  = (0.851, 0.784, 0.478, 1.0)   # overwritten at runtime
FOLIAGE       = (0.196, 0.267, 0.180, 1.0)
BARK          = (0.235, 0.196, 0.161, 1.0)

ASSETS = {}


def asset(asset_id, cls, size, builder, description, tri_budget):
    ASSETS[asset_id] = {
        "id": asset_id, "class": cls, "size": size, "builder": builder,
        "description": description, "tri_budget": tri_budget,
    }


# ------------------------------------------------------- shared motifs

def roof_deck(mesh, width, height, depth, inset=0.9):
    """A lighter deck on top of a structure's main mass.

    From a steep camera the roof is most of what is visible, and with
    walls and roof sharing one colour a base read as a single flat tone
    with faction stripes floating on it. A deck one step lighter than the
    hull gives every structure a top plane that separates it from its
    neighbour, which is cheaper and far more effective than more height.
    """
    ## Concrete, not steel: one step of gunmetal was invisible under this
    ## lighting. A roof needs a real tonal break from the walls or the
    ## whole base reads as one flat shape.
    box(mesh, "Concrete_Dark", (width * inset, 0.14, depth * inset),
        (0.0, height + 0.07, 0.0), chamfer=0.06)
    ## A couple of seams so the deck is not a blank plate.
    for i in (-1, 1):
        box(mesh, "Dark", (width * inset * 0.94, 0.04, 0.09),
            (0.0, height + 0.15, i * depth * inset * 0.26))


def faction_band(mesh, width, height, depth, thickness=0.14):
    """A roof band across the front edge plus one flank stripe.

    Section 8 of the art direction: faction colour on upward-facing
    surfaces, 8-15% of visible area. The first cut of this covered about
    a quarter of every roof, which read as a toy rather than a marking -
    these proportions come to roughly 11%. It is one shared function
    rather than something each asset improvises, so the whole game moves
    together when it is tuned.
    """
    box(mesh, "Faction", (width * 0.70, thickness, depth * 0.085),
        (0.0, height + 0.14 + thickness * 0.5, -depth * 0.33))
    box(mesh, "Faction", (width * 0.085, thickness, depth * 0.50),
        (width * 0.36, height + 0.14 + thickness * 0.5, depth * 0.02))


def stack(mesh, x, z, base_height, tall, radius=0.32, cap="Dark"):
    """A tall exhaust chimney - vertical punctuation that reads at zoom.

    The structures already carried plenty of detail: gantry cranes, roll-up
    doors, vent banks. None of it registered, because at the 14-45m camera
    a 0.3m greeble is one or two pixels. What was missing was not more
    detail, it was HEIGHT - something that breaks the roofline hard enough
    to be seen as an outline rather than as surface.

    A stack is the cheapest way to get it: two cylinders and a band, and
    it changes the shape a player recognises the building by.
    """
    cylinder(mesh, "Metal", radius, tall, (x, base_height + tall / 2.0, z),
             segments=8)
    ## A lip at the top, so the chimney ends in something rather than just
    ## stopping.
    cylinder(mesh, cap, radius * 1.25, 0.16,
             (x, base_height + tall - 0.02, z), segments=8)
    ## Hazard band near the top - the one place a bright accent is allowed
    ## on a structure that is not faction colour.
    cylinder(mesh, "Amber", radius * 1.06, 0.22,
             (x, base_height + tall * 0.78, z), segments=8)


def lattice_mast(mesh, x, z, base_height, tall, radius=0.16):
    """A slender antenna mast. Reads as a line against the ground."""
    cylinder(mesh, "Metal", radius, tall, (x, base_height + tall / 2.0, z),
             segments=6)
    ## Three collars break the shaft so it is not a featureless pole.
    for i in (0.35, 0.62, 0.86):
        cylinder(mesh, "Dark", radius * 2.1, 0.09,
                 (x, base_height + tall * i, z), segments=6)
    cylinder(mesh, "Amber", radius * 1.5, 0.14,
             (x, base_height + tall - 0.08, z), segments=6)


def roof_vents(mesh, count, width, height, depth, radius=0.28):
    for i in range(count):
        x = (i - (count - 1) / 2.0) * (width * 0.24)
        cylinder(mesh, "Metal", radius, 0.55, (x, height + 0.26, depth * 0.22), segments=8)


def tracks(mesh, width, length, height=0.45, inset=0.08):
    """Dark track masses below the hull line - grounds a vehicle cheaply."""
    for side in (-1, 1):
        box(mesh, "Dark", (width * 0.26, height, length),
            (side * (width / 2.0 - width * 0.13 - inset), height / 2.0, 0.0), chamfer=0.06)


def wheels(mesh, width, length, radius=0.34, pairs=2):
    for side in (-1, 1):
        for i in range(pairs):
            z = (i - (pairs - 1) / 2.0) * (length * 0.52)
            cylinder(mesh, "Dark", radius, width * 0.16,
                     (side * (width / 2.0 - width * 0.08), radius, z),
                     segments=10, axis="x")


def sandbags(mesh, cx, cz, length, rot_y=0.0):
    for i in range(3):
        box(mesh, "Dark", (length, 0.22, 0.34),
            (cx, 0.11 + i * 0.2, cz + i * 0.05), rot_y=rot_y, chamfer=0.06)


def crates(mesh, origin, count=3, scale=1.0):
    positions = ((0.0, 0.0), (0.75, 0.2), (0.35, -0.7))
    for i in range(min(count, len(positions))):
        dx, dz = positions[i]
        size = 0.7 * scale
        box(mesh, "Hull", (size, size, size),
            (origin[0] + dx * scale, size / 2.0 + (0.0 if i < 2 else size),
             origin[2] + dz * scale), rot_y=0.3 * i, chamfer=0.05)


# ========================================================== BUILDINGS
#
# Every builder returns [(node_name, Mesh, translation)]. Geometry sits
# at y >= 0 with the origin at ground centre, and each structure gets one
# tall element at the REAR so it never occludes the faction band or the
# health bar (art direction section 10).

def _command_hq():
    m = Mesh()
    w, h, d = 9.0, 5.0, 9.0
    box(m, "Hull", (w, 3.4, d), (0, 1.7, 0), chamfer=0.22)
    box(m, "Steel", (w * 0.52, 2.4, d * 0.52), (0, 4.6, 0.5), chamfer=0.18)
    box(m, "Hull", (w * 0.30, 1.1, d * 0.30), (0, 6.3, 0.5), chamfer=0.12)
    for sx in (-1, 1):
        box(m, "Metal", (0.22, 2.0, 0.22), (sx * w * 0.22, 4.4, -d * 0.22))
    box(m, "Glass", (w * 0.46, 0.65, d * 0.02), (0, 4.9, -d * 0.27))
    # Command mast at the rear, the tallest thing in any player base.
    cylinder(m, "Metal", 0.16, 3.4, (-w * 0.30, h - 0.7, d * 0.34), segments=8)
    box(m, "Metal", (1.5, 0.1, 0.1), (-w * 0.30, h + 0.6, d * 0.34))
    box(m, "Metal", (0.1, 0.1, 0.9), (-w * 0.30, h + 0.25, d * 0.32))
    # Vehicle entrance faces -Z so the rally point reads.
    box(m, "Dark", (2.6, 1.7, 0.35), (0, 0.85, -d / 2.0 + 0.2))
    box(m, "Concrete", (w * 0.9, 0.18, 1.5), (0, 0.09, -d * 0.41))
    for side in (-1, 1):
        box(m, "Dark", (0.5, 2.0, 0.5), (side * w * 0.40, 1.0, -d * 0.40), chamfer=0.08)
    roof_vents(m, 3, w, 3.4, d * 0.7)
    roof_deck(m, w, 3.4, d)
    faction_band(m, w, 3.4, d)
    return [("Body", m, (0, 0, 0))]


def _power_plant():
    m = Mesh()
    w, h, d = 5.0, 3.2, 5.0
    box(m, "Hull", (w, 2.4, d), (0, 1.2, 0), chamfer=0.18)
    # Two cooling towers: the identifying read from above.
    for side in (-1, 1):
        cylinder(m, "Concrete", 1.05, 1.6, (side * 1.25, 2.8, 0.9), segments=12, top_radius=0.85)
        cylinder(m, "Dark", 0.82, 0.12, (side * 1.25, 3.62, 0.9), segments=12)
    box(m, "Metal", (0.3, 0.3, 2.2), (0, 2.4, 0.9))
    for i in range(3):
        cylinder(m, "Metal", 0.14, w * 0.8, (0, 0.7 + i * 0.45, -d * 0.42),
                 segments=6, axis="x")
    box(m, "Dark", (1.4, 1.2, 0.3), (0, 0.6, -d / 2.0 + 0.08))
    ## Two chimneys well clear of the cooling towers. A power plant that
    ## is only 3.2m tall on a 5m footprint reads as a shed; the stacks are
    ## what make it identifiable across the map.
    for side in (-1, 1):
        stack(m, side * 1.9, -d * 0.3, 2.4, 3.6, radius=0.3)
    roof_deck(m, w, 2.4, d)
    faction_band(m, w, 2.4, d)
    return [("Body", m, (0, 0, 0))]


def _refinery():
    m = Mesh()
    w, h, d = 7.0, 3.6, 7.0
    box(m, "Hull", (w * 0.92, 2.4, d * 0.86), (0, 1.2, 0.3), chamfer=0.2)
    # The hopper is the dominant read.
    box(m, "Rust", (2.8, 1.9, 2.8), (-w * 0.14, 2.75, 0.7), chamfer=0.3)
    wedge(m, "Rust", (2.8, 1.0, 2.8), (-w * 0.14, 1.4, 0.7))
    cylinder(m, "Metal", 1.0, 4.0, (w * 0.28, 2.9, -d * 0.16), segments=12)
    cylinder(m, "Dark", 1.08, 0.2, (w * 0.28, 5.0, -d * 0.16), segments=12)
    # Unloading bay: harvesters drive in at -Z.
    box(m, "Concrete", (3.4, 0.16, 2.2), (0, 0.08, -d * 0.34))
    box(m, "Dark", (3.0, 1.5, 0.3), (0, 0.75, -d * 0.42))
    box(m, "Metal", (0.26, 0.26, 2.6), (-w * 0.14, 3.9, 0.7))
    for i in range(2):
        box(m, "Amber", (0.5, 0.3, 0.5), (-w * 0.14 + (i - 0.5) * 1.4, 3.85, 0.7))
    ## Flare stack. The silo already gives the refinery height on one
    ## side; this puts a second, thinner vertical on the other so the
    ## outline is asymmetric and cannot be confused with the war factory.
    stack(m, w * 0.34, d * 0.30, 2.4, 4.4, radius=0.26)
    roof_deck(m, w, 2.4, d)
    faction_band(m, w, 2.4, d)
    return [("Body", m, (0, 0, 0))]


def _barracks():
    m = Mesh()
    w, h, d = 6.0, 3.4, 6.0
    box(m, "Hull", (w, 2.6, d * 0.8), (0, 1.3, 0.3), chamfer=0.18)
    wedge(m, "Hull", (w, 1.4, d * 0.8), (0, 3.3, 0.3))
    box(m, "Dark", (1.5, 1.6, 0.3), (0, 0.8, -d * 0.10))
    box(m, "Concrete", (w * 0.7, 0.16, 1.4), (0, 0.08, -d * 0.38))
    sandbags(m, -w * 0.30, -d * 0.40, 1.8)
    sandbags(m, w * 0.30, -d * 0.40, 1.8)
    lattice_mast(m, w * 0.40, d * 0.36, 2.6, 4.2, radius=0.13)
    box(m, "Faction", (0.5, 0.34, 0.04), (w * 0.40 + 0.30, 6.2, d * 0.36))
    roof_vents(m, 2, w, 3.5, d * 0.5, radius=0.22)
    roof_deck(m, w, 2.6, d)
    faction_band(m, w, 2.6, d)
    return [("Body", m, (0, 0, 0))]


def _war_factory():
    m = Mesh()
    w, h, d = 9.0, 4.2, 9.0
    box(m, "Hull", (w, 3.2, d * 0.9), (0, 1.6, 0.2), chamfer=0.22)
    wedge(m, "Steel", (w, 1.6, d * 0.9), (0, 4.0, 0.2))
    # Roll-up door, the width of a tank, facing -Z.
    box(m, "Dark", (4.0, 2.2, 0.35), (0, 1.1, -d * 0.42))
    for i in range(5):
        box(m, "Metal", (3.8, 0.12, 0.12), (0, 0.4 + i * 0.42, -d * 0.43))
    # Gantry crane across the roof.
    for side in (-1, 1):
        box(m, "Metal", (0.3, 2.2, 0.3), (side * w * 0.38, 4.5, d * 0.22))
    box(m, "Metal", (w * 0.85, 0.34, 0.45), (0, 5.5, d * 0.22))
    box(m, "Dark", (0.7, 0.9, 0.7), (w * 0.12, 4.9, d * 0.22))
    box(m, "Concrete", (5.2, 0.16, 2.0), (0, 0.08, -d * 0.39))
    ## Foundry stacks. The gantry alone sat too close to the roof to break
    ## the outline from above.
    for side in (-1, 1):
        stack(m, side * w * 0.3, -d * 0.28, 4.6, 3.2, radius=0.34)
    roof_vents(m, 3, w, 4.2, d * 0.6)
    roof_deck(m, w, 3.2, d)
    faction_band(m, w, 3.2, d)
    return [("Body", m, (0, 0, 0))]


def _radar_center():
    m = Mesh()
    w, h, d = 6.0, 6.5, 6.0
    box(m, "Hull", (w * 0.9, 2.6, d * 0.9), (0, 1.3, 0), chamfer=0.2)
    box(m, "Steel", (2.2, 2.2, 2.2), (0, 3.7, 0.5), chamfer=0.15)
    # The dish IS the building. Tilted so it reads from above.
    cylinder(m, "Metal", 0.22, 1.2, (0, 4.9, 0.5), segments=8)
    cylinder(m, "Concrete", 1.9, 0.3, (0, 5.7, 0.2), segments=14, top_radius=2.1)
    cylinder(m, "Dark", 1.55, 0.16, (0, 5.86, 0.2), segments=14)
    box(m, "Metal", (0.14, 0.9, 0.14), (0, 6.1, 0.2))
    box(m, "Glass", (w * 0.5, 0.5, 0.1), (0, 1.5, -d * 0.45))
    roof_deck(m, w, 2.6, d)
    faction_band(m, w, 2.6, d)
    return [("Body", m, (0, 0, 0))]


def _tech_center():
    m = Mesh()
    w, h, d = 7.5, 5.0, 7.5
    box(m, "Hull", (w, 2.9, d), (0, 1.45, 0), chamfer=0.22)
    box(m, "Steel", (w * 0.60, 2.3, d * 0.60), (0, 4.05, 0), chamfer=0.16)
    box(m, "Glass", (w * 0.62, 0.9, d * 0.02), (0, 3.75, -d * 0.33))
    box(m, "Glass", (w * 0.02, 0.9, d * 0.62), (-w * 0.33, 3.75, 0))
    # Antenna array at the rear.
    for i in range(3):
        x = (i - 1) * 1.1
        cylinder(m, "Metal", 0.09, 1.3 + (i == 1) * 0.6, (x, 4.4 + (i == 1) * 0.3, d * 0.30),
                 segments=6)
    box(m, "Metal", (2.6, 0.1, 0.1), (0, 4.9, d * 0.30))
    box(m, "Dark", (1.6, 1.5, 0.3), (0, 0.75, -d / 2.0 + 0.08))
    roof_deck(m, w, 2.9, d)
    faction_band(m, w, 2.9, d)
    return [("Body", m, (0, 0, 0))]


def _forward_post():
    m = Mesh()
    w, h, d = 6.5, 4.0, 6.5
    # Deliberately reads as prefab containers - it is a field expedient,
    # not a permanent building.
    box(m, "Hull", (w * 0.85, 1.3, d * 0.42), (0, 0.65, -d * 0.20), chamfer=0.1)
    box(m, "Hull", (w * 0.85, 1.3, d * 0.42), (0, 0.65, d * 0.24), chamfer=0.1)
    box(m, "Steel", (w * 0.55, 1.2, d * 0.40), (w * 0.10, 1.9, 0.1), chamfer=0.1)
    for i in range(4):
        box(m, "Dark", (0.08, 1.2, 0.08), (-w * 0.36 + i * w * 0.24, 0.65, -d * 0.41))
    cylinder(m, "Metal", 0.11, 2.2, (-w * 0.32, 2.7, d * 0.28), segments=6)
    box(m, "Metal", (0.9, 0.08, 0.08), (-w * 0.32, 3.7, d * 0.28))
    sandbags(m, 0.0, -d * 0.44, 2.6)
    box(m, "Concrete", (w * 0.8, 0.14, d * 0.8), (0, 0.07, 0))
    roof_deck(m, w, 2.5, d)
    faction_band(m, w, 2.5, d)
    return [("Body", m, (0, 0, 0))]


def _mg_tower():
    m = Mesh()
    w, h, d = 2.6, 5.5, 2.6
    box(m, "Concrete", (w * 0.85, 0.5, d * 0.85), (0, 0.25, 0), chamfer=0.1)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box(m, "Metal", (0.22, 3.4, 0.22), (sx * w * 0.28, 2.2, sz * d * 0.28))
    box(m, "Metal", (w * 0.7, 0.12, d * 0.7), (0, 2.0, 0))
    box(m, "Hull", (w * 0.95, 1.1, d * 0.95), (0, 4.45, 0), chamfer=0.14)
    box(m, "Dark", (w * 0.99, 0.35, d * 0.99), (0, 4.05, 0), chamfer=0.08)
    barrel = Mesh()
    cylinder(barrel, "Dark", 0.09, 1.3, (0, 0, -0.5), segments=8, axis="z")
    box(barrel, "Metal", (0.3, 0.24, 0.5), (0, 0, 0.1), chamfer=0.05)
    faction_band(m, w, 5.0, d, thickness=0.2)
    return [("Body", m, (0, 0, 0)), ("Turret", barrel, (0, 4.7, 0))]


def _at_turret():
    m = Mesh()
    w, h, d = 3.4, 4.2, 3.4
    box(m, "Concrete", (w * 0.9, 0.6, d * 0.9), (0, 0.3, 0), chamfer=0.12)
    cylinder(m, "Hull", 1.0, 1.4, (0, 1.25, 0), segments=12)
    for sx in (-1, 1):
        box(m, "Dark", (0.3, 0.9, 0.3), (sx * w * 0.36, 0.45, -d * 0.30))
    turret = Mesh()
    box(turret, "Hull", (1.7, 0.9, 2.0), (0, 0, 0.1), chamfer=0.16)
    wedge(turret, "Hull", (1.7, 0.5, 1.2), (0, 0.7, -0.3))
    # Twin barrels: the anti-armour read at distance.
    for sx in (-1, 1):
        cylinder(turret, "Metal", 0.11, 2.4, (sx * 0.34, 0.05, -1.5), segments=8, axis="z")
    box(turret, "Faction", (1.2, 0.18, 0.5), (0, 0.48, 0.6))
    return [("Body", m, (0, 0, 0)), ("Turret", turret, (0, 2.5, 0))]


def _wall():
    m = Mesh()
    box(m, "Concrete", (2.0, 2.6, 1.1), (0, 1.3, 0), chamfer=0.16)
    box(m, "Concrete_Dark", (2.0, 0.4, 1.35), (0, 2.8, 0), chamfer=0.1)
    box(m, "Concrete_Dark", (0.26, 2.8, 1.3), (0, 1.4, 0))
    return [("Body", m, (0, 0, 0))]


def _gate():
    m = Mesh()
    for sx in (-1, 1):
        box(m, "Concrete", (0.6, 3.0, 1.2), (sx * 0.7, 1.5, 0), chamfer=0.12)
        box(m, "Faction", (0.7, 0.22, 1.3), (sx * 0.7, 3.1, 0))
    # Striped barrier arm, raised - a gate reads as passable.
    box(m, "Metal", (1.5, 0.16, 0.16), (0, 2.35, 0))
    for i in range(3):
        box(m, "Dark", (0.26, 0.19, 0.19), (-0.5 + i * 0.5, 2.35, 0))
    return [("Body", m, (0, 0, 0))]


def _comms_outpost():
    m = Mesh()
    w, h, d = 5.0, 6.0, 5.0
    box(m, "Concrete", (w * 0.7, 1.6, d * 0.7), (0, 0.8, 0), chamfer=0.16)
    box(m, "Hull", (w * 0.5, 1.0, d * 0.5), (0, 2.1, 0), chamfer=0.12)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box(m, "Metal", (0.16, 3.0, 0.16), (sx * 0.7, 4.1, sz * 0.7))
    box(m, "Metal", (1.7, 0.12, 1.7), (0, 5.5, 0))
    cylinder(m, "Metal", 0.1, 1.0, (0, 5.9, 0), segments=6)
    for i in range(3):
        box(m, "Metal", (1.3 - i * 0.3, 0.08, 0.08), (0, 4.9 + i * 0.35, 0))
    box(m, "Faction", (w * 0.52, 0.22, d * 0.52), (0, 2.68, 0))
    box(m, "Dark", (1.0, 1.1, 0.25), (0, 0.55, -d * 0.34))
    return [("Body", m, (0, 0, 0))]


def _repair_depot():
    m = Mesh()
    w, h, d = 6.0, 3.4, 6.0
    box(m, "Concrete", (w, 0.22, d), (0, 0.11, 0))
    box(m, "Hull", (w * 0.9, 1.6, d * 0.36), (0, 0.8, d * 0.30), chamfer=0.16)
    # Open-sided canopy: you can see the vehicle being worked on.
    for sx in (-1, 1):
        box(m, "Metal", (0.24, 2.4, 0.24), (sx * w * 0.40, 1.2, -d * 0.30))
    box(m, "Steel", (w * 0.95, 0.22, d * 0.55), (0, 2.5, -d * 0.10), chamfer=0.08)
    box(m, "Metal", (0.3, 1.1, 0.3), (w * 0.22, 3.0, -d * 0.10))
    box(m, "Dark", (0.7, 0.5, 0.7), (w * 0.22, 2.3, -d * 0.10))
    crates(m, (-w * 0.30, 0.0, -d * 0.30), count=2, scale=0.8)
    roof_deck(m, w, 1.6, d)
    faction_band(m, w, 1.6, d)
    return [("Body", m, (0, 0, 0))]


def _supply_depot():
    m = Mesh()
    w, h, d = 6.0, 3.6, 6.0
    box(m, "Concrete", (w, 0.2, d), (0, 0.1, 0))
    box(m, "Hull", (w * 0.85, 2.4, d * 0.45), (0, 1.2, d * 0.26), chamfer=0.16)
    wedge(m, "Steel", (w * 0.85, 0.8, d * 0.45), (0, 2.8, d * 0.26))
    crates(m, (-w * 0.24, 0.0, -d * 0.26), count=3, scale=1.0)
    crates(m, (w * 0.26, 0.0, -d * 0.18), count=2, scale=0.9)
    for i in range(2):
        cylinder(m, "Rust", 0.32, 0.9, (w * 0.36, 0.45, d * 0.02 - i * 0.75), segments=10)
    roof_deck(m, w, 2.4, d)
    faction_band(m, w, 2.4, d)
    return [("Body", m, (0, 0, 0))]


def _civilian_structure():
    m = Mesh()
    w, h, d = 5.0, 4.5, 5.0
    box(m, "Concrete", (w * 0.88, 2.6, d * 0.88), (0, 1.3, 0), chamfer=0.14)
    wedge(m, "Rust", (w * 0.96, 1.5, d * 0.96), (0, 3.35, 0))
    for sz in (-1, 1):
        for i in range(2):
            box(m, "Glass", (0.7, 0.8, 0.06), ((i - 0.5) * 1.6, 1.6, sz * d * 0.44))
    box(m, "Dark", (0.9, 1.5, 0.12), (0, 0.75, -d * 0.44))
    cylinder(m, "Concrete_Dark", 0.3, 1.1, (w * 0.28, 4.3, d * 0.22), segments=8)
    return [("Body", m, (0, 0, 0))]


asset("command_hq", "building", (9, 5, 9), _command_hq,
      "Command Headquarters: stepped bunker, comms mast, vehicle entrance", 1800)
asset("power_plant", "building", (5, 3.2, 5), _power_plant,
      "Power Plant: twin cooling towers and pipe runs", 800)
asset("refinery", "building", (7, 3.6, 7), _refinery,
      "Resource Refinery: ore hopper, silo, harvester unloading bay", 1800)
asset("barracks", "building", (6, 3.4, 6), _barracks,
      "Barracks: pitched-roof hall with sandbag frontage", 800)
asset("war_factory", "building", (9, 4.2, 9), _war_factory,
      "Vehicle Factory: shed with roll-up door and gantry crane", 1800)
asset("radar_center", "building", (6, 6.5, 6), _radar_center,
      "Radar Center: tilted dish on a tower block", 800)
asset("tech_center", "building", (7.5, 5, 7.5), _tech_center,
      "Technology Center: glazed upper floor and antenna array", 1800)
asset("forward_post", "building", (6.5, 4, 6.5), _forward_post,
      "Forward Command Post: stacked prefab containers and mast", 800)
asset("mg_tower", "building", (2.6, 5.5, 2.6), _mg_tower,
      "Machine Gun Tower: legged cabin with traversing MG", 400)
asset("at_turret", "building", (3.4, 4.2, 3.4), _at_turret,
      "Anti-Armor Turret: twin-barrel turret on a concrete pad", 400)
asset("wall", "building", (2, 3, 2), _wall,
      "Concrete Wall segment", 400)
asset("gate", "building", (2, 3.2, 2), _gate,
      "Security Gate: posts and raised barrier arm", 400)
asset("comms_outpost", "building", (5, 6, 5), _comms_outpost,
      "Communications Outpost: neutral capturable relay tower", 800)
asset("repair_depot", "building", (6, 3.4, 6), _repair_depot,
      "Repair Depot: open canopy with overhead hoist", 800)
asset("supply_depot", "building", (6, 3.6, 6), _supply_depot,
      "Supply Depot: covered stores, crates and drums", 800)
asset("civilian_structure", "building", (5, 4.5, 5), _civilian_structure,
      "Civilian Structure: garrisonable house with pitched roof", 800)


# ============================================================== UNITS
#
# Infantry are deliberately oversized relative to vehicles: a correctly
# scaled soldier beside a tank is invisible from 38m up. Readability wins
# over accuracy here, as recorded in the art direction.

def _infantry(weapon, bulk=1.0, helmet="Faction", pack=False, toolbox=False):
    """One figure, built to read from directly above.

    The camera sees the top of a soldier's helmet and shoulders and
    almost nothing else, so that is where the silhouette work goes:
    shoulders wider than the hips, a helmet that overhangs and separates
    from them, and a weapon held across the body where it breaks the
    outline. Legs are barely visible from up here and are shaped only
    enough to carry the stance.
    """
    def build():
        m = Mesh()
        # Boots and legs, set apart and leaning forward into the advance.
        for sx in (-1, 1):
            box(m, "Dark", (0.19 * bulk, 0.60, 0.22), (sx * 0.15, 0.30, 0.04), chamfer=0.04)
            box(m, "Dark", (0.21 * bulk, 0.12, 0.30), (sx * 0.15, 0.06, -0.02), chamfer=0.04)
        # Hips, then a chest that is wider and deeper - from above the
        # taper is what says which way this figure faces.
        box(m, "Hull", (0.44 * bulk, 0.24, 0.26 * bulk), (0, 0.72, 0.01), chamfer=0.05)
        box(m, "Hull", (0.52 * bulk, 0.50, 0.32 * bulk), (0, 1.12, -0.03), chamfer=0.07)
        # Webbing across the chest, and shoulders that overhang it.
        box(m, "Dark", (0.55 * bulk, 0.12, 0.34 * bulk), (0, 1.02, -0.03), chamfer=0.03)
        for sx in (-1, 1):
            box(m, "Hull", (0.16 * bulk, 0.18, 0.30 * bulk),
                (sx * 0.30 * bulk, 1.28, -0.03), chamfer=0.06)
            box(m, "Dark", (0.13 * bulk, 0.34, 0.15), (sx * 0.31 * bulk, 1.05, -0.08), chamfer=0.04)
        box(m, "Hull", (0.16, 0.14, 0.16), (0, 1.48, -0.04))
        # Helmet: wider than the head, and brimmed at the front so it
        # casts its own edge instead of merging into the shoulders.
        box(m, helmet, (0.36, 0.18, 0.34), (0, 1.63, -0.04), chamfer=0.08)
        box(m, helmet, (0.34, 0.07, 0.12), (0, 1.57, -0.22), chamfer=0.03)
        box(m, "Faction", (0.56 * bulk, 0.10, 0.15), (0, 1.35, -0.05))
        if pack:
            box(m, "Dark", (0.38, 0.46, 0.22), (0, 1.14, 0.22), chamfer=0.05)
        if toolbox:
            box(m, "Amber", (0.30, 0.22, 0.20), (0.30, 0.62, -0.10), chamfer=0.04)
        if weapon == "rifle":
            box(m, "Dark", (0.07, 0.09, 0.86), (0.20, 1.06, -0.28), chamfer=0.02)
        elif weapon == "launcher":
            cylinder(m, "Dark", 0.11, 1.20, (0.20, 1.26, -0.20), segments=8, axis="z")
            box(m, "Metal", (0.10, 0.18, 0.22), (0.20, 1.12, 0.10))
        elif weapon == "case":
            box(m, "Dark", (0.26, 0.30, 0.10), (0.30, 0.70, 0.0), chamfer=0.03)
        return [("Body", m, (0, 0, 0))]
    return build


def _attack_dog():
    m = Mesh()
    box(m, "Hull", (0.30, 0.34, 0.78), (0, 0.50, 0.02), chamfer=0.08)
    box(m, "Hull", (0.24, 0.26, 0.26), (0, 0.60, -0.50), chamfer=0.06)
    box(m, "Dark", (0.26, 0.12, 0.12), (0, 0.56, -0.66), chamfer=0.03)
    for sx in (-1, 1):
        box(m, "Dark", (0.10, 0.12, 0.10), (sx * 0.09, 0.74, -0.50))
        for sz in (-1, 1):
            box(m, "Dark", (0.10, 0.36, 0.11), (sx * 0.11, 0.18, sz * 0.26))
    box(m, "Dark", (0.08, 0.08, 0.30), (0, 0.62, 0.48))
    box(m, "Faction", (0.32, 0.09, 0.20), (0, 0.68, -0.18))
    return [("Body", m, (0, 0, 0))]


def _scout_vehicle():
    m = Mesh()
    w, h, d = 2.0, 1.2, 3.0
    wheels(m, w, d, radius=0.33, pairs=2)
    box(m, "Hull", (w * 0.82, 0.46, d * 0.88), (0, 0.60, 0), chamfer=0.10)
    wedge(m, "Hull", (w * 0.82, 0.26, d * 0.30), (0, 0.96, -d * 0.28))
    box(m, "Glass", (w * 0.60, 0.22, 0.06), (0, 0.96, -d * 0.16))
    # Open roll bar reads as "light and fast" from above.
    for sx in (-1, 1):
        box(m, "Metal", (0.09, 0.42, 0.09), (sx * w * 0.32, 1.04, d * 0.14))
    box(m, "Metal", (w * 0.70, 0.09, 0.09), (0, 1.24, d * 0.14))
    box(m, "Dark", (0.16, 0.14, 0.62), (0, 1.12, d * 0.04))
    box(m, "Faction", (w * 0.46, 0.08, 0.34), (0, 0.84, d * 0.26))
    box(m, "Faction", (0.20, 0.08, d * 0.50), (w * 0.36, 0.84, 0))
    return [("Body", m, (0, 0, 0))]


def _assault_vehicle():
    m = Mesh()
    w, h, d = 2.4, 1.4, 3.6
    wheels(m, w, d, radius=0.36, pairs=3)
    # Wider at the rear than the front: unambiguous facing from above.
    box(m, "Hull", (w * 0.86, 0.62, d * 0.62), (0, 0.72, d * 0.16), chamfer=0.10)
    box(m, "Hull", (w * 0.72, 0.52, d * 0.34), (0, 0.67, -d * 0.30), chamfer=0.10)
    wedge(m, "Hull", (w * 0.72, 0.34, d * 0.22), (0, 1.06, -d * 0.34))
    box(m, "Glass", (w * 0.52, 0.18, 0.06), (0, 1.02, -d * 0.44))
    box(m, "Dark", (w * 0.60, 0.9, 0.12), (0, 0.62, d * 0.46))
    turret = Mesh()
    box(turret, "Hull", (0.86, 0.40, 0.94), (0, 0, 0), chamfer=0.09)
    cylinder(turret, "Dark", 0.07, 1.0, (0, 0.04, -0.62), segments=8, axis="z")
    box(turret, "Faction", (0.60, 0.09, 0.34), (0, 0.23, 0.18))
    box(m, "Faction", (w * 0.50, 0.08, 0.30), (0, 1.04, d * 0.30))
    return [("Body", m, (0, 0, 0)), ("Turret", turret, (0, 1.22, d * 0.02))]


def _main_battle_tank():
    m = Mesh()
    w, h, d = 3.0, 1.7, 4.4
    tracks(m, w, d * 0.96, height=0.56)
    box(m, "Hull", (w * 0.72, 0.50, d * 0.90), (0, 0.80, 0), chamfer=0.10)
    wedge(m, "Hull", (w * 0.72, 0.34, d * 0.26), (0, 1.20, -d * 0.32))
    for sx in (-1, 1):
        box(m, "Dark", (0.12, 0.16, d * 0.86), (sx * w * 0.37, 1.02, 0))
    turret = Mesh()
    box(turret, "Hull", (1.55, 0.52, 1.75), (0, 0, 0.05), chamfer=0.14)
    wedge(turret, "Hull", (1.55, 0.26, 0.70), (0, 0.39, -0.55))
    # Exaggerated barrel - the primary role cue at distance.
    cylinder(turret, "Metal", 0.105, 2.65, (0, 0.02, -1.70), segments=8, axis="z")
    cylinder(turret, "Dark", 0.145, 0.42, (0, 0.02, -2.85), segments=8, axis="z")
    box(turret, "Dark", (0.22, 0.20, 0.55), (0.48, 0.34, 0.30))
    box(turret, "Faction", (1.05, 0.10, 0.42), (0, 0.29, 0.62))
    box(turret, "Faction", (0.20, 0.10, 1.10), (0.62, 0.29, 0.0))
    return [("Body", m, (0, 0, 0)), ("Turret", turret, (0, 1.32, d * 0.02))]


def _artillery_vehicle():
    m = Mesh()
    w, h, d = 2.6, 1.5, 4.0
    tracks(m, w, d * 0.94, height=0.50)
    box(m, "Hull", (w * 0.70, 0.46, d * 0.88), (0, 0.74, 0), chamfer=0.10)
    box(m, "Hull", (w * 0.58, 0.34, d * 0.26), (0, 1.10, -d * 0.30), chamfer=0.08)
    # Spades at the rear: it stops to fire, and the model should say so.
    for sx in (-1, 1):
        box(m, "Dark", (0.24, 0.50, 0.18), (sx * w * 0.24, 0.42, d * 0.48), rot_y=0.0)
    mount = Mesh()
    box(mount, "Hull", (1.30, 0.46, 1.30), (0, 0, 0), chamfer=0.10)
    # A long howitzer raised at ~18 degrees reads instantly as artillery.
    angle = math.radians(18.0)
    length = 3.1
    cz = -math.cos(angle) * length / 2.0
    cy = math.sin(angle) * length / 2.0
    seg = 10
    for i in range(seg):
        t0 = i / float(seg) - 0.5
        pz = -math.cos(angle) * length * t0
        py = math.sin(angle) * length * t0
        cylinder(mount, "Metal", 0.115, length / seg * 1.25, (0, 0.28 + py, pz), segments=8, axis="z")
    box(mount, "Dark", (0.52, 0.40, 0.62), (0, 0.24, 0.34), chamfer=0.06)
    box(mount, "Faction", (0.90, 0.09, 0.34), (0, 0.25, 0.60))
    return [("Body", m, (0, 0, 0)), ("Turret", mount, (0, 1.18, d * 0.04))]


def _harvester():
    m = Mesh()
    w, h, d = 2.8, 2.0, 4.2
    wheels(m, w, d, radius=0.42, pairs=3)
    # The ore bin is the whole silhouette; the cab is small and forward.
    box(m, "Rust", (w * 0.88, 1.10, d * 0.56), (0, 1.20, d * 0.18), chamfer=0.12)
    box(m, "Dark", (w * 0.80, 0.18, d * 0.48), (0, 1.78, d * 0.18))
    box(m, "Hull", (w * 0.60, 0.72, d * 0.26), (0, 1.00, -d * 0.30), chamfer=0.10)
    box(m, "Glass", (w * 0.44, 0.28, 0.06), (0, 1.14, -d * 0.43))
    # Intake scoop at the front, angled into the ground.
    wedge(m, "Metal", (w * 0.86, 0.42, 0.80), (0, 0.46, -d * 0.46))
    for i in range(4):
        box(m, "Dark", (0.12, 0.22, 0.12), (-w * 0.30 + i * w * 0.20, 0.30, -d * 0.50))
    box(m, "Amber", (w * 0.66, 0.14, d * 0.40), (0, 1.80, d * 0.18))
    box(m, "Faction", (w * 0.24, 0.10, d * 0.30), (w * 0.36, 1.72, d * 0.12))
    return [("Body", m, (0, 0, 0))]


asset("rifle_soldier", "unit", (0.9, 1.8, 0.9), _infantry("rifle"),
      "Rifle Squad: standard infantry with carbine", 400)
asset("at_squad", "unit", (0.9, 1.8, 0.9), _infantry("launcher", bulk=1.12, pack=True),
      "Anti-Armor Squad: shoulder launcher and pack", 400)
asset("engineer", "unit", (0.9, 1.8, 0.9),
      _infantry("none", helmet="Amber", toolbox=True),
      "Combat Engineer: hard hat and toolbox, unarmed", 400)
asset("spy", "unit", (0.9, 1.8, 0.9), _infantry("case", bulk=0.9, helmet="Hull"),
      "Spy: no helmet, no weapon, carries a case", 400)
asset("attack_dog", "unit", (0.7, 0.8, 1.4), _attack_dog,
      "Attack Dog: fast anti-infantry scout", 400)
asset("scout_vehicle", "unit", (2.0, 1.2, 3.0), _scout_vehicle,
      "Scout Vehicle: open-topped wheeled recon car", 900)
asset("assault_vehicle", "unit", (2.4, 1.4, 3.6), _assault_vehicle,
      "Assault Vehicle: wheeled APC with light turret", 900)
asset("main_battle_tank", "unit", (3.0, 1.7, 4.4), _main_battle_tank,
      "Main Battle Tank: tracked hull, long-barrel turret", 1400)
asset("artillery_vehicle", "unit", (2.6, 1.5, 4.0), _artillery_vehicle,
      "Artillery Vehicle: tracked chassis with elevated howitzer", 1400)
asset("harvester", "unit", (2.8, 2.0, 4.2), _harvester,
      "Supply Harvester: ore bin, cab and intake scoop", 900)


# ======================================================== ENVIRONMENT

def _ore_field():
    m = Mesh()
    # Angular ore outcrop. Amber is a signal colour: ore must be findable
    # by peripheral vision from across the map.
    clusters = ((0.0, 0.0, 1.5), (1.5, 0.9, 1.05), (-1.35, 0.75, 0.9),
                (0.5, -1.5, 0.8), (-0.9, -1.2, 0.62), (1.8, -0.6, 0.5))
    for x, z, scale in clusters:
        cylinder(m, "Amber", 0.42 * scale, 1.25 * scale, (x, 0.62 * scale, z),
                 segments=6, top_radius=0.06, rot_y=x + z)
        cylinder(m, "Rust", 0.62 * scale, 0.30 * scale, (x, 0.15 * scale, z), segments=6)
    box(m, "Concrete_Dark", (4.6, 0.08, 4.6), (0, 0.04, 0))
    return [("Body", m, (0, 0, 0))]


def _rock_small():
    m = Mesh()
    cylinder(m, "Concrete_Dark", 0.62, 0.68, (0, 0.32, 0), segments=6, top_radius=0.34)
    cylinder(m, "Concrete_Dark", 0.34, 0.40, (0.42, 0.20, 0.30), segments=5, top_radius=0.18)
    return [("Body", m, (0, 0, 0))]


def _rock_large():
    m = Mesh()
    cylinder(m, "Concrete_Dark", 1.5, 1.9, (0, 0.92, 0), segments=7, top_radius=0.78)
    cylinder(m, "Concrete_Dark", 0.85, 1.1, (1.15, 0.54, 0.6), segments=6, top_radius=0.42)
    cylinder(m, "Concrete_Dark", 0.6, 0.7, (-0.9, 0.34, -0.7), segments=5, top_radius=0.3)
    return [("Body", m, (0, 0, 0))]


def _cliff_block():
    m = Mesh()
    box(m, "Concrete_Dark", (4.0, 3.2, 4.0), (0, 1.6, 0), chamfer=0.5)
    box(m, "Sand", (4.2, 0.3, 4.2), (0, 3.2, 0), chamfer=0.4)
    return [("Body", m, (0, 0, 0))]


def _concrete_barrier():
    m = Mesh()
    # Jersey barrier profile, approximated with a wedge pair.
    box(m, "Concrete", (2.4, 0.42, 0.72), (0, 0.21, 0), chamfer=0.06)
    box(m, "Concrete", (2.4, 0.55, 0.40), (0, 0.68, 0), chamfer=0.08)
    for i in range(2):
        box(m, "Faction", (0.34, 0.10, 0.42), ((i - 0.5) * 1.5, 0.97, 0))
    return [("Body", m, (0, 0, 0))]


def _sandbag_wall():
    m = Mesh()
    for row in range(3):
        count = 4 - row
        for i in range(count):
            x = (i - (count - 1) / 2.0) * 0.62
            box(m, "Sand", (0.58, 0.24, 0.36), (x, 0.12 + row * 0.23, row * 0.06),
                rot_y=0.12 * (i % 2), chamfer=0.08)
    return [("Body", m, (0, 0, 0))]


def _fuel_drum():
    m = Mesh()
    cylinder(m, "Rust", 0.32, 0.92, (0, 0.46, 0), segments=10)
    for i in range(2):
        cylinder(m, "Dark", 0.34, 0.06, (0, 0.30 + i * 0.32, 0), segments=10)
    return [("Body", m, (0, 0, 0))]


def _crate_stack():
    m = Mesh()
    crates(m, (-0.37, 0.0, 0.17), count=3, scale=1.0)
    return [("Body", m, (0, 0, 0))]


def _tree_pine():
    m = Mesh()
    cylinder(m, "Bark", 0.16, 1.1, (0, 0.55, 0), segments=6)
    cylinder(m, "Foliage", 1.05, 1.5, (0, 1.65, 0), segments=7, top_radius=0.42)
    cylinder(m, "Foliage", 0.68, 1.2, (0, 2.75, 0), segments=7, top_radius=0.04)
    return [("Body", m, (0, 0, 0))]


def _tree_bare():
    m = Mesh()
    cylinder(m, "Bark", 0.18, 2.2, (0, 1.1, 0), segments=6, top_radius=0.11)
    for i, (dx, dz) in enumerate(((0.5, 0.2), (-0.45, 0.3), (0.1, -0.5))):
        cylinder(m, "Bark", 0.07, 1.0, (dx * 0.6, 1.9 + i * 0.12, dz * 0.6),
                 segments=5, top_radius=0.03, rot_y=i)
    return [("Body", m, (0, 0, 0))]


def _debris_pile():
    m = Mesh()
    for i, (dx, dz, s, r) in enumerate(((0, 0, 1.0, 0.3), (0.8, 0.4, 0.7, 1.1),
                                        (-0.6, 0.5, 0.6, 0.6), (0.3, -0.7, 0.5, 2.0))):
        box(m, "Concrete_Dark", (0.9 * s, 0.30 * s, 0.7 * s),
            (dx, 0.15 * s, dz), rot_y=r, chamfer=0.05)
    for i in range(3):
        box(m, "Metal", (0.08, 0.08, 1.2), (0.2 - i * 0.4, 0.34, 0.1), rot_y=0.4 * i)
    return [("Body", m, (0, 0, 0))]


def _destroyed_building():
    m = Mesh()
    # A broken shell with one wall standing - reads as "was a building"
    # rather than "is a rock pile".
    box(m, "Concrete_Dark", (4.4, 0.5, 4.4), (0, 0.25, 0), chamfer=0.1)
    box(m, "Concrete_Dark", (4.2, 2.1, 0.42), (0, 1.05, -1.9), chamfer=0.1)
    box(m, "Concrete_Dark", (0.42, 1.4, 2.6), (-1.9, 0.70, 0.3), chamfer=0.1)
    box(m, "Concrete_Dark", (1.6, 0.8, 0.42), (1.2, 0.40, 1.9), chamfer=0.1)
    for i, (dx, dz, r) in enumerate(((0.6, 0.2, 0.5), (-0.7, -0.6, 1.2), (1.1, -1.0, 2.1))):
        box(m, "Concrete_Dark", (0.9, 0.28, 0.8), (dx, 0.62, dz), rot_y=r, chamfer=0.05)
    for i in range(4):
        box(m, "Metal", (0.09, 1.0, 0.09), (-1.2 + i * 0.8, 0.9, -1.6), rot_y=0.2 * i)
    return [("Body", m, (0, 0, 0))]


def _vehicle_wreck():
    """A burnt-out hull, and deliberately not a specific vehicle.

    One wreck stands in for every vehicle in the game, so it has to read
    as "something armoured died here" rather than as a particular tank -
    a recognisable hull would look wrong under three quarters of the
    deaths it marks. Low, broken-backed, and charred rather than painted:
    no faction slot, because a wreck belongs to nobody.
    """
    m = Mesh()
    # Chassis, slumped and slightly askew.
    box(m, "Dark", (2.0, 0.42, 3.0), (0, 0.24, 0), rot_y=0.10, chamfer=0.1)
    # Collapsed tracks either side, one thrown off.
    box(m, "Dark", (0.44, 0.30, 2.7), (-0.86, 0.15, 0.06), rot_y=0.10, chamfer=0.06)
    box(m, "Dark", (0.42, 0.22, 1.6), (1.05, 0.11, -0.55), rot_y=0.42, chamfer=0.06)
    # What is left of the upper hull, blown open and tipped.
    box(m, "Concrete_Dark", (1.35, 0.44, 1.5), (-0.08, 0.62, 0.18), rot_y=-0.18, chamfer=0.12)
    wedge(m, "Concrete_Dark", (1.2, 0.34, 0.9), (0.1, 0.92, -0.35), rot_y=-0.18)
    # A barrel or strut, bent and dropped clear.
    cylinder(m, "Metal", 0.09, 1.7, (0.75, 0.30, 0.95), segments=6, axis="z", rot_y=0.55)
    # Scattered plate.
    for i, (dx, dz, r) in enumerate(((-1.35, 0.9, 0.7), (1.3, 1.25, 1.9), (-0.4, -1.75, 0.3))):
        box(m, "Dark", (0.6, 0.12, 0.5), (dx, 0.06, dz), rot_y=r, chamfer=0.04)
    return [("Body", m, (0, 0, 0))]


def _antenna_mast():
    m = Mesh()
    box(m, "Concrete", (0.9, 0.3, 0.9), (0, 0.15, 0), chamfer=0.06)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box(m, "Metal", (0.08, 4.2, 0.08), (sx * 0.26, 2.2, sz * 0.26))
    for i in range(4):
        box(m, "Metal", (0.62, 0.06, 0.06), (0, 0.9 + i * 0.9, 0))
        box(m, "Metal", (0.06, 0.06, 0.62), (0, 1.35 + i * 0.9, 0))
    cylinder(m, "Metal", 0.05, 0.9, (0, 4.6, 0), segments=5)
    return [("Body", m, (0, 0, 0))]


def _road_segment():
    m = Mesh()
    box(m, "Concrete_Dark", (8.0, 0.06, 8.0), (0, 0.03, 0))
    for i in range(3):
        box(m, "Concrete", (1.4, 0.02, 0.22), (-2.6 + i * 2.6, 0.07, 0))
    return [("Body", m, (0, 0, 0))]


def _base_pad():
    m = Mesh()
    ## A plain slab with no kerb: pads are laid edge to edge, and any trim
    ## on the border draws a grid of seams across what should read as one
    ## continuous apron.
    box(m, "Concrete", (10.0, 0.08, 10.0), (0, 0.04, 0))
    return [("Body", m, (0, 0, 0))]


asset("ore_field", "environment", (4.6, 1.9, 4.6), _ore_field,
      "Resource field: angular amber ore outcrop on a dark apron", 400)
asset("rock_small", "environment", (1.4, 0.7, 1.4), _rock_small, "Small rock", 250)
asset("rock_large", "environment", (3.4, 1.9, 3.4), _rock_large, "Large rock outcrop", 250)
asset("cliff_block", "environment", (4.2, 3.5, 4.2), _cliff_block,
      "Cliff block: tileable impassable terrain mass", 250)
asset("concrete_barrier", "environment", (2.4, 1.0, 0.8), _concrete_barrier,
      "Jersey barrier with faction stripes", 250)
asset("sandbag_wall", "environment", (2.6, 0.8, 0.5), _sandbag_wall,
      "Sandbag emplacement", 250)
asset("fuel_drum", "environment", (0.7, 0.95, 0.7), _fuel_drum, "Fuel drum", 250)
asset("crate_stack", "environment", (1.6, 1.4, 1.6), _crate_stack, "Supply crate stack", 250)
asset("tree_pine", "environment", (2.1, 3.5, 2.1), _tree_pine, "Conifer", 250)
asset("tree_bare", "environment", (1.4, 2.9, 1.4), _tree_bare, "Bare winter tree", 250)
asset("debris_pile", "environment", (2.4, 0.5, 2.0), _debris_pile, "Rubble and rebar", 250)
asset("destroyed_building", "environment", (4.4, 2.1, 4.4), _destroyed_building,
      "Destroyed structure shell", 250)
asset("vehicle_wreck", "environment", (3.4, 1.2, 3.9), _vehicle_wreck,
      "Burnt-out vehicle hull, generic to any armoured death", 250)
asset("antenna_mast", "environment", (0.9, 5.1, 0.9), _antenna_mast,
      "Lattice antenna mast prop", 250)
asset("road_segment", "environment", (8.0, 0.1, 8.0), _road_segment,
      "Tileable road slab with centre markings", 250)
asset("base_pad", "environment", (10.0, 0.1, 10.0), _base_pad,
      "Concrete base pad with kerbs", 250)

# Material name -> colour. Resolved per asset at build time; `Faction` is
# a placeholder that the runtime repaints per owner.
MATERIAL_COLORS = {
    "Hull": GUNMETAL, "Steel": STEEL, "Dark": SHADOW, "Metal": STEEL,
    "Concrete": CONCRETE, "Concrete_Dark": CONCRETE_DARK, "Rust": RUST,
    "Sand": SAND, "Glass": GLASS_DARK, "Amber": AMBER, "Faction": NEUTRAL_MARK,
    "Olive": OLIVE, "Field_Green": FIELD_GREEN, "Foliage": FOLIAGE, "Bark": BARK,
}

# Every structure wearing GUNMETAL made a base read as one slate-grey
# mass: at gameplay zoom you could not tell a refinery from a barracks
# without reading its roof fitting. Each building type now carries its own
# industrial identity, so the silhouette is not doing all the work alone.
#
# Kept inside the palette of section 2 - these are the existing structure
# colours redistributed, not new ones - and deliberately muted, because
# faction colour is the one thing on screen allowed to be saturated.
BUILDING_HULL_OVERRIDE = {
    "power_plant":       CONCRETE_DARK,   # civil infrastructure, poured
    "refinery":          RUST,            # industrial, ore-stained
    "barracks":          OLIVE,           # the one the infantry come from
    "war_factory":       STEEL,           # heavy fabrication
    "radar_center":      STEEL,
    "tech_center":       CONCRETE,        # laboratory, palest of the set
    "supply_depot":      SAND,
    "repair_depot":      RUST,
    "comms_outpost":     STEEL,
    "forward_post":      OLIVE,
    "civilian_structure": CONCRETE,
    # command_hq keeps GUNMETAL: it is the flagship, and the colour the
    # rest of the base is read against.
}

# Vehicles and infantry wear olive rather than structure gunmetal.
UNIT_HULL_OVERRIDE = {
    "rifle_soldier": OLIVE, "at_squad": OLIVE, "engineer": OLIVE, "spy": STEEL,
    "attack_dog": BARK, "scout_vehicle": FIELD_GREEN, "assault_vehicle": OLIVE,
    "main_battle_tank": FIELD_GREEN, "artillery_vehicle": OLIVE, "harvester": SAND,
}


# ------------------------------------------------------- declared overhang
#
# (x, y, z) metres by which an asset may exceed `body_size`. Barrels,
# masts, dishes and scoops are meant to break the box - that is the
# "vertical punctuation" and "exaggerated barrel" the art direction asks
# for. Everything absent from this table must fit its footprint exactly.
OVERHANG = {
    "command_hq":        (0.0, 2.2, 0.0),   # tower and comms mast
    "power_plant":       (0.0, 2.9, 0.1),   # cooling towers and chimneys
    "refinery":          (0.0, 3.3, 0.1),   # hopper, silo and flare stack
    "barracks":          (0.0, 3.6, 0.0),   # pitched roof and comms mast
    "war_factory":       (0.0, 3.7, 0.0),   # gantry crane and foundry stacks
    "radar_center":      (0.0, 0.1, 0.0),   # dish
    "tech_center":       (0.0, 1.4, 0.1),   # antenna array
    "comms_outpost":     (0.0, 0.5, 0.0),   # mast
    "civilian_structure": (0.0, 0.4, 0.0),  # chimney
    "repair_depot":      (0.0, 0.2, 0.0),   # overhead hoist
    "at_turret":         (0.0, 0.0, 0.9),   # twin barrels
    "gate":              (0.2, 0.1, 0.0),   # barrier arm
    "main_battle_tank":  (0.0, 0.2, 0.8),   # main gun
    "assault_vehicle":   (0.0, 0.2, 0.9),   # turret gun
    "artillery_vehicle": (0.0, 0.6, 0.0),   # elevated howitzer
    "scout_vehicle":     (0.0, 0.2, 0.0),   # roll bar and MG
    "harvester":         (0.0, 0.0, 1.1),   # intake scoop
    "at_squad":          (0.0, 0.0, 0.4),   # launcher tube
    "crate_stack":       (0.0, 0.0, 0.3),
}


# ------------------------------------------------- draw-call reduction
#
# Applied to unit-class assets only. A steel barrel on an olive tank is a
# detail nobody can resolve at 38 metres; a draw call per unit per frame
# is something the frame timer resolves very clearly.
UNIT_MATERIAL_MERGE = {
    "Metal": "Hull",
    "Glass": "Dark",
    "Amber": "Faction",
}


def merge_groups(mesh, mapping):
    """Fold one material's triangles into another, in place."""
    for source, target in mapping.items():
        if source not in mesh.groups:
            continue
        positions, normals, indices = mesh.groups.pop(source)
        if target not in mesh.groups:
            mesh.groups[target] = ([], [], [])
        tp, tn, ti = mesh.groups[target]
        offset = len(tp)
        tp.extend(positions)
        tn.extend(normals)
        ti.extend(index + offset for index in indices)
