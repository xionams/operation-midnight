"""Land vehicles. Front faces -Z; origin at ground centre.

Shape language (docs/ART_DIRECTION.md 3b):
  - light vehicles are OPEN: visible wheels, roll cages, exposed crew
    space, a gun on a pintle. Nothing about them is armoured.
  - armour is SLOPED: hulls are side profiles with a raked glacis and a
    rear deck, turrets are low and wide with long barrels. Tracks sit
    under skirts with a readable row of road wheels.
  - industrial vehicles are TALL and BOXY: cabs, hoppers, arms - the
    opposite of the low armour silhouette, so an economy unit is never
    mistaken for a combat one.
"""

import math

from om_kit import *  # noqa: F401,F403


def wheel(n, x, z, r, width=0.34, y=None):
    y = r if y is None else y
    n.cylinder(r, width, (x, y, z), "Body", RUBBER, axis="x", segments=8)
    n.cylinder(r * 0.55, width + 0.04, (x, y, z), "Metal", STEEL, axis="x", segments=6)


def track_unit(n, side_x, length, height, color, wheels=5, skirt=True):
    """One side's running gear: track band, road wheels, drive sprocket, skirt."""
    half = length / 2.0
    r = height * 0.42
    # the track band as a rounded side profile
    band = [(-half, 0.05), (-half - r * 0.6, r), (-half + r * 0.2, height * 0.95),
            (half - r * 0.2, height * 0.95), (half + r * 0.6, r), (half, 0.05)]
    n.prism(band, side_x - 0.22, side_x + 0.22, "Body", RUBBER)
    for i in range(wheels):
        z = -half + r + (length - 2 * r) * i / (wheels - 1)
        n.cylinder(r * 0.78, 0.5, (side_x, r * 0.9, z), "Metal", STEEL, axis="x", segments=8)
    if skirt:
        n.box((0.1, height * 0.55, length * 0.92), (side_x + (0.26 if side_x > 0 else -0.26),
              height * 0.62, 0.0), "Body", color)


def scout_vehicle():
    m = Model("scout_vehicle", "units")
    n = m.node("Body")
    L, W = 3.0, 2.0
    # chassis: a low tub with a sharply raked nose
    tub = [(-1.5, 0.42), (-1.45, 0.72), (-0.95, 0.95), (1.25, 0.95), (1.5, 0.82), (1.5, 0.42)]
    n.prism(tub, -0.82, 0.82, "Body", FIELD_GREEN)
    # bonnet rising to the windscreen
    n.prism([(-1.35, 0.95), (-0.35, 1.08), (-0.35, 0.95)], -0.78, 0.78, "Body", OLIVE)
    # fold-down windscreen frame, glass
    n.box((1.5, 0.34, 0.06), (0.0, 1.22, -0.33), "Glass", GLASS_DARK, rot_x=-18)
    n.box((1.58, 0.06, 0.1), (0.0, 1.40, -0.38), "Metal", STEEL)
    # seats / open crew bay
    for x in (-0.4, 0.4):
        n.box((0.46, 0.12, 0.46), (x, 1.02, 0.05), "Body", SHADOW)
        n.box((0.46, 0.44, 0.1), (x, 1.24, 0.3), "Body", SHADOW)
    # roll cage: the "open and light" read
    for x in (-0.72, 0.72):
        n.tube((x, 0.95, 0.38), (x, 1.78, 0.42), 0.05, "Metal", STEEL)
        n.tube((x, 1.78, 0.42), (x * 0.9, 1.5, -0.3), 0.045, "Metal", STEEL)
    n.tube((-0.72, 1.78, 0.42), (0.72, 1.78, 0.42), 0.05, "Metal", STEEL)
    # wheels, set outboard so the car reads as wheeled at range
    for x in (-0.86, 0.86):
        for z in (-0.95, 0.95):
            wheel(n, x, z, 0.42)
            n.box((0.46, 0.06, 0.8), (x, 0.9, z), "Body", OLIVE_DARK)  # fender
    # spare wheel and jerry cans on the tail
    n.cylinder(0.34, 0.2, (0.0, 0.78, 1.58), "Body", RUBBER, axis="z", segments=12)
    for x in (-0.55, 0.55):
        n.box((0.26, 0.42, 0.16), (x, 0.98, 1.44), "Body", OLIVE_DARK)
    # headlamps and a whip antenna
    for x in (-0.55, 0.55):
        n.cylinder(0.09, 0.08, (x, 0.82, -1.5), "Emissive", LAMP, axis="z", segments=8)
    n.tube((0.7, 0.95, 1.2), (0.78, 2.9, 1.3), 0.018, "Metal", SHADOW, segments=4)
    # faction marking on the bonnet and tail
    n.box((0.9, 0.03, 0.5), (0.0, 1.03, -0.85), "Faction", WHITE, rot_x=-7)
    n.box((1.2, 0.03, 0.22), (0.0, 0.97, 1.1), "Faction", WHITE)
    # the machine gun on a ring mount, which aims
    t = m.node("Turret", (0.0, 1.55, 0.55))
    t.cylinder(0.32, 0.08, (0.0, 0.0, 0.0), "Metal", STEEL, segments=12)
    t.box((0.1, 0.34, 0.1), (0.0, 0.18, 0.0), "Metal", SHADOW)
    t.box((0.22, 0.2, 0.62), (0.0, 0.38, -0.12), "Metal", GUNMETAL)
    t.tube((0.0, 0.4, -0.4), (0.0, 0.42, -1.2), 0.035, "Metal", SHADOW)
    t.box((0.12, 0.14, 0.12), (0.12, 0.34, 0.02), "Body", OLIVE_DARK)  # ammo box
    t.box((0.4, 0.26, 0.04), (0.0, 0.46, -0.28), "Body", OLIVE)  # gun shield
    return m


def main_battle_tank():
    """Heavy: low and wide, sloped everywhere, a long gun."""
    m = Model("main_battle_tank", "units")
    n = m.node("Body")
    L = 4.4
    track_unit(n, -1.18, L * 0.96, 0.9, FIELD_GREEN, wheels=6)
    track_unit(n, 1.18, L * 0.96, 0.9, FIELD_GREEN, wheels=6)
    # hull: steep glacis, flat deck, raked rear
    hull = [(-2.2, 0.55), (-2.15, 0.72), (-1.45, 1.15), (1.85, 1.15), (2.2, 0.95), (2.2, 0.55)]
    n.prism(hull, -1.05, 1.05, "Body", FIELD_GREEN)
    # engine deck grilles at the back
    for i in range(3):
        n.box((1.5, 0.05, 0.16), (0.0, 1.18, 1.1 + i * 0.26), "Metal", SHADOW)
    # driver's hatch, tow hooks, headlights
    n.box((0.42, 0.08, 0.36), (-0.45, 1.19, -1.25), "Body", OLIVE_DARK)
    for x in (-0.8, 0.8):
        n.cylinder(0.08, 0.07, (x, 0.95, -2.02), "Emissive", LAMP, axis="z", segments=8)
    n.box((1.8, 0.03, 0.32), (0.0, 1.17, 1.72), "Faction", WHITE)  # rear deck band
    # turret: a wide wedge, faceted front, bustle behind
    t = m.node("Turret", (0.0, 1.15, 0.05))
    ring = [(-0.95, -0.35), (-0.55, -1.25), (0.55, -1.25), (0.95, -0.35), (0.95, 0.95), (-0.95, 0.95)]
    t.plan(ring, 0.0, 0.62, "Body", FIELD_GREEN, taper=0.86)
    t.box((1.5, 0.28, 0.5), (0.0, 0.28, 1.15), "Body", OLIVE_DARK)  # bustle rack
    # gun: mantlet, barrel, bore evacuator, muzzle brake - exaggerated length
    t.box((0.46, 0.36, 0.3), (0.0, 0.34, -1.35), "Body", OLIVE_DARK)
    t.tube((0.0, 0.34, -1.4), (0.0, 0.36, -3.3), 0.1, "Metal", GUNMETAL, segments=10)
    t.cylinder(0.15, 0.36, (0.0, 0.355, -2.35), "Metal", GUNMETAL, axis="z", segments=10)
    t.cylinder(0.14, 0.22, (0.0, 0.36, -3.25), "Metal", SHADOW, axis="z", segments=8)
    # commander's cupola with MG, loader hatch, smoke dischargers, sights
    t.cylinder(0.26, 0.2, (0.42, 0.72, 0.25), "Body", OLIVE_DARK, segments=10)
    t.tube((0.42, 0.9, 0.2), (0.42, 0.92, -0.45), 0.03, "Metal", SHADOW, segments=6)
    t.box((0.34, 0.06, 0.34), (-0.4, 0.66, 0.3), "Body", OLIVE_DARK)
    t.box((0.22, 0.24, 0.26), (-0.55, 0.74, -0.55), "Glass", GLASS_DARK)
    for x in (-0.86, 0.86):
        for k in range(3):
            t.tube((x, 0.45 + k * 0.1, -0.55), (x * 1.18, 0.52 + k * 0.1, -0.78), 0.05, "Metal", SHADOW, segments=6)
    t.box((1.0, 0.03, 0.5), (0.0, 0.64, 0.45), "Faction", WHITE)
    t.tube((0.7, 0.62, 0.8), (0.78, 2.1, 0.9), 0.016, "Metal", SHADOW, segments=4)
    m.bevel = 0.05
    return m


def assault_vehicle():
    """Medium: a six-wheeled IFV - wheeled, boxy-sloped, a slim autocannon."""
    m = Model("assault_vehicle", "units")
    n = m.node("Body")
    hull = [(-1.8, 0.5), (-1.75, 0.75), (-1.2, 1.25), (1.6, 1.3), (1.8, 1.05), (1.8, 0.5)]
    n.prism(hull, -1.0, 1.0, "Body", OLIVE)
    for z in (-1.15, 0.0, 1.15):
        for x in (-1.06, 1.06):
            wheel(n, x, z, 0.46, width=0.36)
    for x in (-1.08, 1.08):
        n.box((0.18, 0.12, 3.3), (x, 0.98, 0.0), "Body", OLIVE_DARK)  # fender line
    n.box((0.5, 0.36, 0.08), (-0.4, 1.08, -1.46), "Glass", GLASS_DARK, rot_x=-40)  # driver vision
    n.box((1.2, 0.5, 0.08), (0.0, 0.85, 1.83), "Body", OLIVE_DARK)  # rear ramp
    for x in (-0.7, 0.7):
        n.cylinder(0.08, 0.07, (x, 0.85, -1.8), "Emissive", LAMP, axis="z", segments=8)
    n.box((1.3, 0.03, 0.3), (0.0, 1.32, 1.2), "Faction", WHITE)
    for x in (-0.85, 0.85):
        n.box((0.3, 0.3, 0.5), (x, 1.4, 0.95), "Body", OLIVE_DARK)  # stowage bins
    t = m.node("Turret", (0.0, 1.28, -0.1))
    t.plan([(-0.55, -0.5), (0.55, -0.5), (0.7, 0.15), (0.55, 0.6), (-0.55, 0.6), (-0.7, 0.15)],
           0.0, 0.44, "Body", OLIVE, taper=0.85)
    t.box((0.3, 0.24, 0.22), (0.0, 0.24, -0.58), "Body", OLIVE_DARK)
    t.tube((0.0, 0.24, -0.6), (0.0, 0.26, -2.0), 0.055, "Metal", GUNMETAL, segments=8)
    t.cylinder(0.08, 0.2, (0.0, 0.26, -1.95), "Metal", SHADOW, axis="z", segments=8)
    t.box((0.2, 0.18, 0.24), (0.36, 0.52, 0.1), "Glass", GLASS_DARK)
    t.box((0.7, 0.03, 0.4), (0.0, 0.45, 0.2), "Faction", WHITE)
    m.bevel = 0.05
    return m


def harvester():
    """Industrial: tall cab-forward truck, ore hopper, front scoop. Nothing
    about it resembles a combat vehicle - an economy unit must never be
    mistaken for one at a glance."""
    m = Model("harvester", "units")
    n = m.node("Body")
    # chassis rails and six big wheels
    n.box((2.1, 0.35, 4.0), (0.0, 0.62, 0.1), "Body", SHADOW)
    for z in (-1.3, 0.35, 1.45):
        for x in (-1.12, 1.12):
            wheel(n, x, z, 0.52, width=0.46)
    # cab: a tall box forward, big glazing, amber beacon
    n.box((2.1, 1.2, 1.2), (0.0, 1.42, -1.35), "Body", SAND)
    n.box((1.9, 0.5, 0.06), (0.0, 1.62, -1.96), "Glass", GLASS_DARK, rot_x=-12)
    n.box((0.06, 0.4, 0.8), (1.06, 1.62, -1.35), "Glass", GLASS_DARK)
    n.box((0.06, 0.4, 0.8), (-1.06, 1.62, -1.35), "Glass", GLASS_DARK)
    n.cylinder(0.11, 0.16, (0.7, 2.1, -1.35), "Emissive", AMBER, segments=8)
    n.cylinder(0.11, 0.16, (-0.7, 2.1, -1.35), "Emissive", AMBER, segments=8)
    # hopper: an open-topped bin, raked sides, ore heaped inside
    n.plan([(-1.25, -0.6), (1.25, -0.6), (1.25, 1.95), (-1.25, 1.95)], 0.8, 2.0, "Body", SAND, taper=1.0)
    n.plan([(-1.05, -0.45), (1.05, -0.45), (1.05, 1.8), (-1.05, 1.8)], 1.6, 2.02, "Body", SHADOW)
    n.loft([(-0.3, [(-0.95, 1.95), (0.95, 1.95), (0.6, 2.2), (-0.6, 2.2)]),
            (0.7, [(-0.95, 1.95), (0.95, 1.95), (0.7, 2.35), (-0.7, 2.35)]),
            (1.7, [(-0.95, 1.95), (0.95, 1.95), (0.6, 2.18), (-0.6, 2.18)])], "Body", ORE)
    for x in (-1.26, 1.26):
        for z in (-0.3, 0.6, 1.5):
            n.box((0.08, 1.0, 0.12), (x, 1.4, z), "Metal", SAND_DARK)  # ribs
    n.box((1.4, 0.03, 0.5), (0.0, 2.02, -1.35), "Faction", WHITE)
    n.box((0.05, 0.4, 1.6), (1.29, 1.1, 0.6), "Faction", WHITE)
    # front scoop on arms: the part that says "gathers"
    for x in (-0.8, 0.8):
        n.tube((x, 0.9, -1.8), (x, 0.55, -2.55), 0.08, "Metal", STEEL)
    n.prism([(-2.9, 0.1), (-2.5, 0.1), (-2.35, 0.75), (-2.5, 0.8), (-2.85, 0.35)], -1.1, 1.1, "Metal", STEEL)
    for i in range(5):
        n.box((0.08, 0.14, 0.3), (-0.8 + i * 0.4, 0.12, -3.0), "Metal", SHADOW)
    # exhaust stack behind the cab
    n.tube((0.95, 1.0, -0.72), (0.95, 2.6, -0.72), 0.08, "Metal", SHADOW)
    m.bevel = 0.05
    return m


def artillery_vehicle():
    """Tracked, with a long howitzer carried high: the silhouette is the gun."""
    m = Model("artillery_vehicle", "units")
    n = m.node("Body")
    track_unit(n, -1.05, 3.9, 0.8, OLIVE, wheels=6)
    track_unit(n, 1.05, 3.9, 0.8, OLIVE, wheels=6)
    n.prism([(-2.0, 0.5), (-1.9, 0.75), (-1.4, 1.05), (1.8, 1.05), (2.0, 0.8), (2.0, 0.5)],
            -0.95, 0.95, "Body", OLIVE)
    n.box((0.8, 0.5, 0.3), (0.0, 0.6, 2.05), "Metal", SHADOW)  # recoil spade
    n.box((1.0, 0.03, 0.4), (0.0, 1.07, -1.1), "Faction", WHITE)
    t = m.node("Turret", (0.0, 1.05, 0.35))
    t.plan([(-0.95, -0.9), (0.95, -0.9), (0.95, 1.2), (-0.95, 1.2)], 0.0, 0.95, "Body", OLIVE, taper=0.9)
    t.box((0.52, 0.52, 0.5), (0.0, 0.62, -1.05), "Body", OLIVE_DARK)
    # the howitzer, elevated: long, thick, a big muzzle brake
    t.tube((0.0, 0.7, -1.2), (0.0, 1.55, -3.6), 0.13, "Metal", GUNMETAL, segments=10)
    t.cylinder(0.2, 0.34, (0.0, 1.54, -3.58), "Metal", SHADOW, axis="z", segments=10, rot_y=0)
    t.box((0.3, 0.1, 0.9), (0.0, 0.62, -1.7), "Metal", STEEL, rot_x=-19)  # recuperator
    t.box((1.2, 0.03, 0.6), (0.0, 0.96, 0.6), "Faction", WHITE)
    t.cylinder(0.22, 0.2, (0.5, 1.05, 0.7), "Body", OLIVE_DARK, segments=10)
    m.bevel = 0.05
    return m


ASSETS = {
    "scout_vehicle": scout_vehicle,
    "main_battle_tank": main_battle_tank,
    "assault_vehicle": assault_vehicle,
    "harvester": harvester,
    "artillery_vehicle": artillery_vehicle,
}


# ------------------------------------------------------------------ infantry
#
# One soldier, about 1.8 m, built with RTS proportions: head and helmet a
# little large, weapon thick, stance wide - at gameplay zoom a soldier is a
# dozen pixels and has to read as "a person with a gun", not a peg. The
# helmet is the Faction slot, the only place team colour goes on a man.
#
# JOINTED, not one welded lump. Every limb is its own exported node with
# its origin ON the joint it turns about, so Godot can pose it at runtime
# (see scripts/vfx/infantry_animator.gd) without an armature, skinning,
# or a single baked animation track. A soldier was previously a single
# "Body" mesh, which is why infantry glided: there was nothing to move.
#
# The bind pose is deliberately NEUTRAL - legs together, arms hanging -
# rather than the old posed stride and -35 degree weapon carry. The
# animator supplies the carry pose and the stride, so the same rig can
# stand, walk, run, crouch and fire instead of being frozen in one of
# them.

HIP_Y, HIP_X = 0.86, 0.12
SHOULDER_Y, SHOULDER_X = 1.35, 0.27
NECK_Y = 1.44


def soldier(m, uniform=OLIVE, gear=OLIVE_DARK, helmet="Faction", helmet_color=WHITE):
    """Build the shared jointed soldier rig on `m`.

    Returns the parts by name so a variant can hang its own kit on the
    right limb - a launcher on the weapon, a toolbox in a hand.
    """
    parts = {}

    # --- legs: origin on the hip, geometry hanging below it ---
    for name, side in (("Leg_L", -1), ("Leg_R", 1)):
        leg = m.node(name, (side * HIP_X, HIP_Y, 0.0))
        leg.box((0.17, 0.72, 0.19), (0, -0.36, 0), "Body", uniform, taper=0.9)
        leg.box((0.16, 0.14, 0.26), (0, -0.79, -0.04), "Body", RUBBER)
        parts[name] = leg

    # --- torso: origin on the waist, so a lean or a crouch bends here ---
    torso = m.node("Torso", (0.0, HIP_Y, 0.0))
    torso.box((0.46, 0.56, 0.28), (0, 0.28, 0), "Body", uniform, taper=0.92)
    torso.box((0.5, 0.36, 0.32), (0, 0.26, 0), "Body", gear)
    torso.box((0.34, 0.3, 0.16), (0, 0.28, 0.2), "Body", gear)  # pack
    parts["Torso"] = torso

    # --- arms: origin on the shoulder, hanging straight down at rest ---
    for name, side in (("Arm_L", -1), ("Arm_R", 1)):
        arm = m.node(name, (side * SHOULDER_X, SHOULDER_Y, 0.0))
        arm.box((0.13, 0.46, 0.14), (0, -0.23, 0), "Body", uniform)
        parts[name] = arm

    # --- head: origin on the neck, so it can turn and nod ---
    head = m.node("Head", (0.0, NECK_Y, 0.0))
    head.box((0.2, 0.22, 0.2), (0, 0.12, 0), "Body", SAND)
    head.sphere(0.2, (0, 0.22, 0.01), helmet, helmet_color,
                rings=4, segments=8, squash=0.75, smooth=False)
    head.box((0.36, 0.04, 0.38), (0, 0.18, 0.0), helmet, helmet_color)
    parts["Head"] = head
    return parts


def _weapon_node(m, origin=(0.08, 1.12, 0.0)):
    """The held weapon, its own node so it can recoil and be re-parented
    onto the firing arm at runtime."""
    return m.node("Weapon", origin)


def rifle_soldier():
    m = Model("rifle_soldier", "units")
    m.bevel = 0.0  # sub-pixel at RTS zoom; it tripled the triangles
    soldier(m)
    w = _weapon_node(m)
    w.box((0.07, 0.1, 0.9), (0, 0, -0.36), "Metal", GUNMETAL)
    w.box((0.06, 0.16, 0.1), (0, -0.1, -0.3), "Metal", GUNMETAL)
    return m


def at_squad():
    """Anti-tank team: a launcher on the shoulder, fat tube, spare rocket on
    the back - the tube is what says 'this one kills tanks'."""
    m = Model("at_squad", "units")
    m.bevel = 0.0  # sub-pixel at RTS zoom; it tripled the triangles
    parts = soldier(m, uniform=FIELD_GREEN)
    w = _weapon_node(m, (0.2, 1.5, 0.0))
    w.cylinder(0.11, 1.3, (0, 0, -0.1), "Metal", OLIVE_DARK, axis="z", segments=8)
    w.cylinder(0.14, 0.2, (0, 0, -0.78), "Metal", SHADOW, axis="z", segments=8)
    ## The spare rocket rides on the pack, so it stays with the body
    ## rather than swinging with the launcher.
    parts["Torso"].cylinder(0.08, 0.7, (-0.05, 0.34, 0.3), "Metal", OLIVE,
                            axis="y", segments=6)
    return m


def engineer():
    """Engineer: no rifle, a big toolbox and a hard hat stripe - the only
    soldier carrying something square."""
    m = Model("engineer", "units")
    m.bevel = 0.0  # sub-pixel at RTS zoom; it tripled the triangles
    parts = soldier(m, uniform=SAND_DARK, gear=RUST)
    ## Toolbox in the right hand and wrench in the left: hung off the
    ## arms so they swing with them instead of floating alongside.
    parts["Arm_R"].box((0.46, 0.28, 0.2), (0.03, -0.65, -0.05), "Metal", HAZARD)
    parts["Arm_R"].box((0.3, 0.06, 0.06), (0.03, -0.47, -0.05), "Metal", SHADOW)
    parts["Arm_L"].box((0.12, 0.5, 0.12), (-0.03, -0.35, -0.2), "Metal", STEEL, rot_x=-25)
    return m


def spy():
    """Spy: a long coat, a soft cap instead of a helmet, a pistol - a
    civilian silhouette among soldiers. Same rig, different build: the
    coat makes the hips sit lower than a soldier's."""
    m = Model("spy", "units")
    m.bevel = 0.0  # sub-pixel at RTS zoom; it tripled the triangles
    hip, shoulder, neck = 0.75, 1.37, 1.46
    for name, side in (("Leg_L", -1), ("Leg_R", 1)):
        leg = m.node(name, (side * 0.12, hip, 0.0))
        leg.box((0.16, 0.6, 0.18), (0, -0.3, 0), "Body", SHADOW)
        leg.box((0.16, 0.14, 0.26), (0, -0.68, -0.04), "Body", RUBBER)
    torso = m.node("Torso", (0.0, hip, 0.0))
    torso.box((0.5, 0.95, 0.34), (0, 0.25, 0), "Body", STEEL, taper=0.82)  # coat
    torso.box((0.54, 0.1, 0.36), (0, 0.67, 0), "Body", STEEL)
    for name, side in (("Arm_L", -1), ("Arm_R", 1)):
        arm = m.node(name, (side * 0.29, shoulder, 0.0))
        arm.box((0.13, 0.5, 0.14), (0, -0.25, 0), "Body", STEEL)
    head = m.node("Head", (0.0, neck, 0.0))
    head.box((0.2, 0.22, 0.2), (0, 0.12, 0), "Body", SAND)
    head.cylinder(0.16, 0.1, (0, 0.26, 0), "Faction", WHITE, segments=8)
    head.box((0.34, 0.03, 0.34), (0, 0.22, -0.04), "Body", SHADOW)
    w = _weapon_node(m, (0.3, 0.9, 0.0))
    w.box((0.06, 0.1, 0.24), (0, 0, -0.12), "Metal", GUNMETAL)
    return m


def attack_dog():
    """Attack dog: low and long, head up, tail out, a faction collar.

    Jointed like the soldiers so it can run rather than slide: four legs
    on their own hips, a head that can drop to the scent, a tail that
    wags. The body is the root part everything else hangs off.
    """
    m = Model("attack_dog", "units")
    m.bevel = 0.0  # sub-pixel at RTS zoom; it tripled the triangles
    torso = m.node("Torso", (0.0, 0.56, 0.0))
    torso.box((0.3, 0.32, 0.8), (0, 0, 0.02), "Body", TIMBER, taper=0.92)
    torso.box((0.24, 0.26, 0.3), (0, 0.22, -0.46), "Body", TIMBER, rot_x=-20)  # neck

    head = m.node("Head", (0.0, 0.84, -0.56))
    head.box((0.22, 0.22, 0.28), (0, 0.06, -0.06), "Body", TIMBER)
    head.box((0.14, 0.12, 0.2), (0, 0.0, -0.24), "Body", SHADOW)  # muzzle
    for side in (-1, 1):
        head.box((0.06, 0.12, 0.06), (side * 0.08, 0.21, -0.02), "Body", SHADOW)  # ears
    head.box((0.26, 0.06, 0.12), (0, -0.04, 0.18), "Faction", WHITE)  # collar

    ## Front legs forward of the shoulder, back legs behind the haunch,
    ## each on its own hip so a gallop reads from the silhouette.
    for name, side, dz, shade in (
            ("Leg_FL", -1, -0.28, SHADOW), ("Leg_FR", 1, -0.28, SHADOW),
            ("Leg_BL", -1, 0.3, TIMBER), ("Leg_BR", 1, 0.3, TIMBER)):
        leg = m.node(name, (side * 0.1, 0.42, dz))
        leg.box((0.08, 0.42, 0.09), (0, -0.21, 0), "Body", shade)

    tail = m.node("Tail", (0.0, 0.72, 0.4))
    tail.box((0.06, 0.06, 0.34), (0, 0.0, 0.12), "Body", TIMBER, rot_x=30)
    return m


ASSETS.update({
    "rifle_soldier": rifle_soldier,
    "at_squad": at_squad,
    "engineer": engineer,
    "spy": spy,
    "attack_dog": attack_dog,
})
