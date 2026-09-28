"""Faction structures. Origin at ground centre; units exit on +X.

Shape language (docs/ART_DIRECTION.md 18.4): every building stands on a
concrete plinth, keeps a rectangular footprint so placement reads honestly,
and carries ONE tall element that names its role from the RTS camera:
HQ radar mast, power plant cooling stacks, barracks arched hall and flag,
refinery silos and conveyor, war factory sawtooth hall and roller door.
Doors and intakes face +X, where the production queue spawns units.
"""

import math

from om_kit import *  # noqa: F401,F403


# ------------------------------------------------------------------ helpers

def plinth(n, w, d, h=0.3, color=CONCRETE_DARK):
    """Stepped concrete pad: a slab with a chamfered lip."""
    n.box((w, h, d), (0, h / 2.0, 0), "Body", color, taper=0.985)
    return h


def hazard_band(n, length, center, along="z", height=0.5, stripes=6):
    """Yellow/black chevron band on a door jamb or apron edge."""
    cx, cy, cz = center
    step = length / stripes
    for i in range(stripes):
        c = HAZARD if i % 2 == 0 else SHADOW
        off = -length / 2.0 + step * (i + 0.5)
        if along == "z":
            n.box((0.06, height, step), (cx, cy, cz + off), "Body", c)
        else:
            n.box((step, height, 0.06), (cx + off, cy, cz), "Body", c)


def lamp(n, pos, r=0.12):
    n.box((r * 2.2, r * 1.2, r * 1.6), pos, "Emissive", LAMP)


def vent(n, pos, size=(0.8, 0.3, 0.8)):
    n.box(size, pos, "Metal", STEEL)
    n.box((size[0] * 0.8, 0.04, size[2] * 0.8), (pos[0], pos[1] + size[1] / 2.0, pos[2]),
          "Body", SHADOW)


def windows_band(n, w, d, y, h=0.42, inset=0.02):
    """A continuous dark glass strip round a block of w x d."""
    n.box((w + inset * 2, h, 0.05), (0, y, -d / 2.0 - inset), "Glass", GLASS_DARK)
    n.box((w + inset * 2, h, 0.05), (0, y, d / 2.0 + inset), "Glass", GLASS_DARK)
    n.box((0.05, h, d + inset * 2), (-w / 2.0 - inset, y, 0), "Glass", GLASS_DARK)
    n.box((0.05, h, d + inset * 2), (w / 2.0 + inset, y, 0), "Glass", GLASS_DARK)


def chamfer_rect(w, d, c):
    hw, hd = w / 2.0, d / 2.0
    return [(-hw + c, -hd), (hw - c, -hd), (hw, -hd + c), (hw, hd - c),
            (hw - c, hd), (-hw + c, hd), (-hw, hd - c), (-hw, -hd + c)]


# ------------------------------------------------------------------ HQ

def command_hq():
    m = Model("command_hq", "buildings")
    m.bevel = 0.08
    n = m.node("Body")
    base = plinth(n, 9.6, 9.6, 0.32)
    # the bunker: chamfered, battered walls
    n.plan(chamfer_rect(7.4, 7.4, 1.3), base, 2.9, "Body", CONCRETE, taper=0.93)
    # corner buttresses, raked like a blockhouse
    for sx in (-1, 1):
        for sz in (-1, 1):
            n.box((1.1, 2.2, 1.1), (sx * 3.25, base + 1.1, sz * 3.25), "Body", CONCRETE_DARK,
                  rot_y=45, taper=0.55)
    # command deck on top, glazed all round
    n.box((4.6, 1.3, 4.6), (0, 2.9 + 0.65, 0), "Body", CONCRETE_LIGHT)
    windows_band(n, 4.6, 4.6, 3.62, h=0.46)
    n.box((5.0, 0.16, 5.0), (0, 4.28, 0), "Body", CONCRETE_DARK)  # roof lip
    # entrance on +X: a sloped blast porch with a dark doorway
    n.prism([(-1.2, base), (-1.2, 2.0), (1.2, 2.0), (1.2, base)], 3.6, 4.4, "Body", CONCRETE_DARK)
    n.box((0.12, 1.5, 1.6), (4.42, base + 0.75, 0), "Body", SHADOW)
    hazard_band(n, 2.4, (4.45, base + 0.05, 0), along="z", height=0.1, stripes=8)
    lamp(n, (4.45, 2.2, -0.9))
    lamp(n, (4.45, 2.2, 0.9))
    # faction roof marking and wall band
    n.box((3.2, 0.04, 3.2), (0, 4.38, 0), "Faction", WHITE)
    n.box((0.05, 0.5, 3.4), (-3.72, 2.2, 0), "Faction", WHITE)
    # satellite dishes and antenna farm on the deck
    for (x, z, yaw) in ((-1.6, 1.6, 30), (1.6, 1.7, -40)):
        n.cylinder(0.08, 0.5, (x, 4.6, z), "Metal", STEEL, segments=6)
        n.cylinder(0.55, 0.12, (x, 4.95, z), "Metal", STEEL_LIGHT, segments=12,
                   radius_top=0.2, rot_y=yaw)
    for x in (-1.9, -1.5):
        n.tube((x, 4.36, -1.9), (x, 6.2, -1.9), 0.03, "Metal", SHADOW, segments=4)
    # the mast: a lattice-look tapered tower carrying the spinning radar
    n.cylinder(0.34, 2.2, (0.6, 5.46, -0.6), "Metal", GUNMETAL, segments=6, radius_top=0.18)
    n.cylinder(0.3, 0.14, (0.6, 6.6, -0.6), "Metal", STEEL, segments=10)
    lamp(n, (0.6, 6.72, -0.6), r=0.08)
    r = m.node("Radar", (0.6, 6.72, -0.6))
    r.box((2.4, 0.5, 0.14), (0, 0.35, 0.12), "Metal", STEEL_LIGHT, rot_x=-12)
    r.box((0.3, 0.3, 0.3), (0, 0.15, -0.1), "Metal", GUNMETAL)
    # ground clutter that sells scale: sandbags and a fuel tank
    for i in range(4):
        n.box((0.9, 0.35, 0.5), (-4.3, base + 0.18 + (i % 2) * 0.3, -2.4 + i * 0.5), "Body", SAND_DARK)
    n.cylinder(0.45, 1.6, (-2.2, base + 0.5, 4.2), "Metal", OLIVE, axis="x", segments=10)
    return m


# ------------------------------------------------------------------ power

def power_plant():
    m = Model("power_plant", "buildings")
    n = m.node("Body")
    base = plinth(n, 5.8, 5.8)
    # turbine hall across the back (-Z)
    n.box((5.2, 2.0, 2.4), (0, base + 1.0, -1.5), "Body", CONCRETE)
    n.prism([(-2.7, base + 2.0), (-1.5, base + 2.5), (-0.3, base + 2.0)], -2.6, 2.6,
            "Body", ROOF_TIN)
    windows_band(n, 5.2, 2.4, base + 1.35, h=0.28)
    # twin cooling stacks: the silhouette. Waisted like the real thing.
    for x in (-1.25, 1.25):
        n.cylinder(1.0, 2.4, (x, base + 1.2, 1.2), "Body", CONCRETE_LIGHT, segments=16,
                   radius_top=0.72)
        n.cylinder(0.72, 1.8, (x, base + 3.3, 1.2), "Body", CONCRETE_LIGHT, segments=16,
                   radius_top=0.86)
        n.cylinder(0.78, 0.08, (x, base + 4.18, 1.2), "Body", SHADOW, segments=16)
        n.box((0.5, 0.04, 2.0), (x, base + 3.0, 1.2), "Faction", WHITE, rot_y=90)
    # transformer yard on +X with insulators
    for z in (-0.3, 0.9):
        n.box((0.9, 0.9, 0.7), (2.35, base + 0.45, z), "Metal", GUNMETAL)
        for dz in (-0.2, 0.2):
            n.cylinder(0.06, 0.5, (2.35, base + 1.15, z + dz), "Body", WHITE, segments=6)
    # pipes from hall to stacks
    for x in (-1.25, 1.25):
        n.tube((x, base + 0.6, -0.3), (x, base + 0.6, 0.3), 0.18, "Metal", RUST)
    n.box((1.2, 0.05, 1.2), (0, base + 2.03, -1.5), "Faction", WHITE)
    lamp(n, (0, base + 1.6, -0.28))
    vent(n, (-1.6, base + 2.2, -1.9), (0.6, 0.3, 0.6))
    return m


# ------------------------------------------------------------------ barracks

def barracks():
    m = Model("barracks", "buildings")
    n = m.node("Body")
    base = plinth(n, 6.6, 6.6)
    # arched Nissen hall along X - the only curved roof in the faction kit
    arch = []
    R = 2.05
    for i in range(11):
        a = math.pi * i / 10
        arch.append((math.cos(a) * R, base + 0.35 + math.sin(a) * R * 0.95))
    profile = [(R, base)] + arch + [(-R, base)]
    n.prism(profile, -2.6, 2.4, "Body", OLIVE)
    # ribs over the arch read as corrugation at range
    for x in (-2.0, -1.0, 0.0, 1.0, 2.0):
        n.prism([(z * 1.02, y + (y - base) * 0.02) for z, y in profile], x - 0.05, x + 0.05,
                "Body", OLIVE_DARK)
    # end walls: concrete gable with the door on +X
    n.prism([(-R, base), (-R, base + 1.8), (R, base + 1.8), (R, base)], 2.4, 2.6, "Body", CONCRETE)
    n.box((0.08, 1.5, 1.3), (2.62, base + 0.75, 0), "Body", SHADOW)
    n.box((0.5, 0.12, 1.8), (2.75, base + 1.65, 0), "Body", CONCRETE_DARK)  # door canopy
    lamp(n, (2.66, base + 1.95, 0))
    hazard_band(n, 1.4, (2.95, base + 0.03, 0), along="z", height=0.06, stripes=6)
    n.prism([(-R, base), (-R, base + 1.6), (R, base + 1.6), (R, base)], -2.8, -2.6, "Body", CONCRETE)
    # small windows along the flanks
    for x in (-1.5, 0.5):
        for s in (-1, 1):
            n.box((0.7, 0.35, 0.06), (x, base + 1.2, s * 2.0), "Glass", GLASS_DARK)
    # faction band along the roof ridge
    n.box((3.6, 0.05, 0.9), (-0.1, base + 2.3, 0), "Faction", WHITE)
    # sandbag breastwork and flagpole in the yard
    for i in range(5):
        n.box((0.8, 0.34, 0.45), (-3.0 + i * 0.05, base + 0.17, -2.9 + i * 0.12), "Body", SAND_DARK,
              rot_y=10 * i)
    for i in range(4):
        n.box((0.8, 0.34, 0.45), (1.6 - i * 0.82, base + 0.17, 2.9), "Body", SAND)
    n.tube((-2.9, base, 2.6), (-2.9, base + 4.6, 2.6), 0.05, "Metal", STEEL_LIGHT, segments=6)
    n.box((0.05, 0.75, 1.2), (-2.9, base + 4.15, 3.22), "Faction", WHITE)
    # ammo crates
    n.box((0.7, 0.45, 0.5), (2.7, base + 0.22, 2.3), "Body", OLIVE_DARK)
    n.box((0.5, 0.35, 0.5), (2.75, base + 0.62, 2.35), "Body", OLIVE)
    return m


# ------------------------------------------------------------------ refinery

def refinery():
    m = Model("refinery", "buildings")
    n = m.node("Body")
    base = plinth(n, 7.6, 7.6)
    # processing hall (-X half)
    n.box((3.6, 2.6, 5.2), (-1.7, base + 1.3, -0.6), "Body", CONCRETE)
    n.prism([(-3.2, base + 2.6), (-0.6, base + 3.3), (2.0, base + 2.6)], -3.5, 0.1, "Body", ROOF_TIN)
    windows_band(n, 3.6, 5.2, base + 1.9, h=0.3)
    # two ore silos with conical tops: the silhouette
    for z in (-1.9, 0.4):
        n.cylinder(1.0, 3.4, (1.6, base + 1.7, z), "Body", CONCRETE_LIGHT, segments=14)
        n.cylinder(1.02, 0.7, (1.6, base + 3.75, z), "Body", RUST, segments=14, radius_top=0.2)
        n.box((0.08, 0.4, 1.4), (2.62, base + 2.6, z), "Faction", WHITE)
        for ring in (0.9, 2.3):
            n.cylinder(1.04, 0.1, (1.6, base + ring, z), "Metal", STEEL, segments=14)
    # intake hopper on +X where harvesters unload, with ore in it
    n.box((1.8, 0.9, 2.2), (2.9, base + 0.45, 2.5), "Metal", GUNMETAL, taper=1.25)
    n.box((1.5, 0.12, 1.8), (2.9, base + 0.92, 2.5), "Body", ORE)
    hazard_band(n, 2.2, (3.85, base + 0.3, 2.5), along="z", height=0.3, stripes=8)
    # conveyor from hopper up to the silos
    n.tube((2.4, base + 0.9, 2.3), (1.6, base + 3.9, 0.6), 0.22, "Metal", STEEL_LIGHT, segments=6)
    n.tube((1.6, base + 3.9, 0.6), (1.6, base + 3.9, -1.7), 0.18, "Metal", STEEL_LIGHT, segments=6)
    # pipe run from silos into the hall
    for y in (0.6, 1.1):
        n.tube((0.6, base + y, -1.9), (-0.1, base + y, -1.9), 0.14, "Metal", RUST)
    # stack
    n.cylinder(0.3, 2.6, (-2.8, base + 3.9, -2.4), "Metal", GUNMETAL, segments=10, radius_top=0.24)
    n.cylinder(0.3, 0.2, (-2.8, base + 5.2, -2.4), "Body", HAZARD, segments=10)
    n.box((2.4, 0.05, 2.4), (-1.8, base + 3.0, 0.2), "Faction", WHITE)
    lamp(n, (0.12, base + 2.2, 1.9))
    # the crusher drum turns while the refinery is working
    k = m.node("Machinery", (-0.1, base + 1.2, 2.4))
    k.cylinder(0.6, 1.1, (0, 0, 0), "Metal", STEEL, axis="x", segments=8)
    for i in range(4):
        k.box((1.2, 0.14, 1.36), (0, 0, 0), "Metal", RUST, rot_x=45 * i)
    return m


# ------------------------------------------------------------------ factory

def war_factory():
    m = Model("war_factory", "buildings")
    m.bevel = 0.08
    n = m.node("Body")
    base = plinth(n, 9.6, 9.6, 0.32)
    # main hall with a sawtooth north-light roof (ridges run along X)
    n.box((7.6, 3.2, 8.0), (-0.6, base + 1.6, 0), "Body", CONCRETE)
    teeth = 4
    depth = 8.0 / teeth
    for i in range(teeth):
        z0 = -4.0 + i * depth
        n.prism([(z0, base + 3.2), (z0, base + 4.3), (z0 + depth, base + 3.2)], -4.4, 3.2,
                "Body", ROOF_TIN)
        n.prism([(z0 + 0.02, base + 3.25), (z0 + 0.02, base + 4.2), (z0 + 0.12, base + 4.1),
                 (z0 + 0.12, base + 3.25)], -4.3, 3.1, "Glass", GLASS_DARK)
    # big roller door on +X with a gantry frame and hazard jambs
    n.box((0.14, 2.7, 4.2), (3.25, base + 1.35, 0), "Metal", STEEL)
    for i in range(7):
        n.box((0.18, 0.06, 4.1), (3.3, base + 0.3 + i * 0.36, 0), "Metal", GUNMETAL)
    for s in (-1, 1):
        n.box((0.5, 3.4, 0.5), (3.45, base + 1.7, s * 2.4), "Body", CONCRETE_DARK)
        n.box((0.06, 3.0, 0.48), (3.72, base + 1.6, s * 2.4), "Body", HAZARD)
    n.box((1.2, 0.5, 5.4), (3.6, base + 3.55, 0), "Body", CONCRETE_DARK)
    for z in (-1.4, 0, 1.4):
        lamp(n, (4.2, base + 3.3, z))
    # apron with hazard edge
    n.box((2.0, 0.06, 4.8), (4.2, base + 0.03, 0), "Body", CONCRETE_LIGHT)
    hazard_band(n, 4.8, (5.2, base + 0.07, 0), along="z", height=0.06, stripes=10)
    # office annex and stack on -X corner
    n.box((1.6, 2.2, 3.0), (-4.2, base + 1.1, 2.4), "Body", CONCRETE_LIGHT)
    windows_band(n, 1.6, 3.0, base + 1.4, h=0.34)
    n.cylinder(0.35, 5.6, (-4.1, base + 2.8, -3.4), "Metal", GUNMETAL, segments=10, radius_top=0.28)
    n.cylinder(0.36, 0.3, (-4.1, base + 5.45, -3.4), "Body", HAZARD, segments=10)
    # roof gantry crane rails, a vehicle-factory read from above
    for z in (-3.2, 3.2):
        n.box((7.4, 0.2, 0.2), (-0.6, base + 4.45, z), "Metal", RUST)
    n.box((0.4, 0.4, 6.8), (1.0, base + 4.6, 0), "Metal", HAZARD)
    # faction roof panel and side band
    n.box((3.0, 0.05, 2.2), (-1.6, base + 4.0, 0.2), "Faction", WHITE, rot_x=-28)
    n.box((6.0, 0.6, 0.05), (-0.8, base + 2.4, -4.03), "Faction", WHITE)
    return m


ASSETS = {
    "command_hq": command_hq,
    "power_plant": power_plant,
    "barracks": barracks,
    "refinery": refinery,
    "war_factory": war_factory,
}


# ------------------------------------------------------------------ fortification

def wall():
    """One 2 m slab, 1.1 m deep, 3 m tall. Wall.gd scales copies of it into
    every straight run and corner stub, so it must survive being squashed
    to half length: detail is kept to the cap, the base and the face."""
    m = Model("wall", "buildings")
    m.bevel = 0.05
    n = m.node("Body")
    # battered footing
    n.box((2.0, 0.5, 1.1), (0, 0.25, 0), "Body", CONCRETE_DARK)
    # the panel, slightly tapered
    n.box((2.0, 2.2, 0.86), (0, 0.5 + 1.1, 0), "Body", CONCRETE, taper=0.94)
    # face joints and a faction band on both faces
    for s in (-1, 1):
        n.box((0.06, 2.1, 0.04), (0.97, 1.6, s * 0.43), "Body", SHADOW)
        n.box((2.0, 0.26, 0.04), (0, 2.2, s * 0.425), "Faction", WHITE)
    # coping cap
    n.box((2.0, 0.3, 1.0), (0, 2.85, 0), "Body", CONCRETE_LIGHT, taper=0.8)
    return m


def gate():
    """A 2 m opening between two posts with a lifting boom barrier and
    hazard striping: a gap in the line that says 'ours go through'."""
    m = Model("gate", "buildings")
    m.bevel = 0.05
    n = m.node("Body")
    for x in (-0.8, 0.8):
        n.box((0.5, 0.5, 1.2), (x, 0.25, 0), "Body", CONCRETE_DARK)
        n.box((0.4, 2.7, 0.9), (x, 0.5 + 1.35, 0), "Body", CONCRETE, taper=0.9)
        n.box((0.44, 0.3, 0.96), (x, 3.05, 0), "Body", CONCRETE_LIGHT)
        n.box((0.42, 0.24, 0.05), (x, 2.4, -0.46), "Faction", WHITE)
        n.box((0.42, 0.24, 0.05), (x, 2.4, 0.46), "Faction", WHITE)
        lamp(n, (x, 3.26, 0), r=0.09)
    # overhead lintel, like a checkpoint
    n.box((2.1, 0.32, 0.5), (0, 2.95, 0), "Metal", GUNMETAL)
    hazard_band(n, 2.0, (0, 2.95, -0.26), along="x", height=0.3, stripes=8)
    hazard_band(n, 2.0, (0, 2.95, 0.26), along="x", height=0.3, stripes=8)
    # the boom barrier across the opening
    for i in range(6):
        c = HAZARD if i % 2 == 0 else WHITE
        n.box((0.2, 0.14, 0.14), (-0.5 + i * 0.2, 1.0, 0), "Body", c)
    # counterweight box
    n.box((0.3, 0.4, 0.3), (0.8, 1.0, 0.55), "Metal", STEEL)
    # threshold plate
    n.box((1.2, 0.06, 1.2), (0, 0.03, 0), "Metal", STEEL)
    return m


# ------------------------------------------------------------------ resources

def ore_field():
    """A ~4 m ore deposit: dark churned apron, amber ore boulders.
    ResourceNode scales the model's Y by what remains, so boulders sit on
    the apron rather than floating, and a depleted field flattens."""
    m = Model("ore_field", "props")
    m.bevel = 0.04
    n = m.node("Body")
    # apron: an irregular low disc of dark spoil
    ring = []
    import random
    rnd = random.Random(7)
    for i in range(14):
        a = math.tau * i / 14
        r = 2.4 + rnd.uniform(-0.35, 0.3)
        ring.append((math.cos(a) * r, math.sin(a) * r))
    n.plan(ring, 0.0, 0.12, "Body", ORE_DARK, taper=0.9)
    # ore boulders: squashed faceted spheres in two tones
    rocks = [(0.0, 0.0, 0.9), (1.2, 0.5, 0.6), (-1.0, 0.8, 0.65), (0.5, -1.2, 0.55),
             (-0.9, -0.9, 0.5), (1.5, -0.6, 0.4), (-1.6, 0.0, 0.38), (0.2, 1.6, 0.42)]
    for i, (x, z, r) in enumerate(rocks):
        c = ORE if i % 3 != 2 else ORE_DARK
        sq = 0.75 + rnd.uniform(-0.1, 0.15)
        # half-buried: the bottom pole just above the apron
        n.sphere(r, (x, 0.1 + r * sq * 0.9, z), "Body", c, rings=4, segments=6,
                 squash=sq, smooth=False)
    # a few loose chips
    for i in range(10):
        a = rnd.uniform(0, math.tau)
        d = rnd.uniform(1.0, 2.2)
        s = rnd.uniform(0.12, 0.22)
        n.box((s, s * 0.7, s), (math.cos(a) * d, 0.16, math.sin(a) * d), "Body", ORE,
              rot_y=rnd.uniform(0, 90))
    return m


ASSETS.update({
    "wall": wall,
    "gate": gate,
    "ore_field": ore_field,
})
