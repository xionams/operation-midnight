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
    g = m.node("Barrel", (0.0, 1.49, -1.30))
    g.box((0.46, 0.36, 0.3), (0.0, 0.0, 0.0), "Body", OLIVE_DARK)
    g.tube((0.0, 0.0, -0.05), (0.0, 0.02, -1.95), 0.1, "Metal", GUNMETAL, segments=10)
    g.cylinder(0.15, 0.36, (0.0, 0.015, -1.0), "Metal", GUNMETAL, axis="z", segments=10)
    g.cylinder(0.14, 0.22, (0.0, 0.02, -1.9), "Metal", SHADOW, axis="z", segments=8)
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
    ## The gun is its own node, pivoting on the trunnion, so it can
    ## recoil. Exported flat and re-parented onto the turret at load; see
    ## scripts/combat/turret_aim.gd.
    g = m.node("Barrel", (0.0, 1.52, -0.68))
    g.box((0.3, 0.24, 0.22), (0.0, 0.0, 0.0), "Body", OLIVE_DARK)
    g.tube((0.0, 0.0, -0.02), (0.0, 0.02, -1.42), 0.055, "Metal", GUNMETAL, segments=8)
    g.cylinder(0.08, 0.2, (0.0, 0.02, -1.37), "Metal", SHADOW, axis="z", segments=8)
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
    g = m.node("Barrel", (0.0, 1.67, -0.70))
    g.box((0.52, 0.52, 0.5), (0.0, 0.0, 0.0), "Body", OLIVE_DARK)
    # the howitzer, elevated: long, thick, a big muzzle brake
    g.tube((0.0, 0.08, -0.15), (0.0, 0.93, -2.55), 0.13, "Metal", GUNMETAL, segments=10)
    g.cylinder(0.2, 0.34, (0.0, 0.92, -2.53), "Metal", SHADOW, axis="z", segments=10, rot_y=0)
    g.box((0.3, 0.1, 0.9), (0.0, 0.0, -0.65), "Metal", STEEL, rot_x=-19)  # recuperator
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

## Landmarks as fractions of a 1.80m man, after Drillis & Contini (1966)
## via Winter fig 4.1. The old skeleton put the hip at 0.86 (0.478H
## against a real 0.530H), the shoulder at 1.35 (0.750H against 0.818H)
## and the chin at 1.44 (0.800H against 0.870H): stubby legs, a stretched
## torso and a head sunk into the shoulders. Those are dwarf proportions,
## and no amount of shading or kit rescues them - a figure reads as human
## because the joints are where a human's are, and because there is
## daylight under the chin.
HIP_Y, HIP_X = 0.95, 0.13
SHOULDER_Y, SHOULDER_X = 1.47, 0.27
NECK_Y = 1.57
KNEE_Y, ELBOW_Y = 0.51, 1.13
WRIST_Y = 0.87

## One skeleton for every humanoid. Roles differ by weapon, webbing,
## headgear and vertex colour - not by a rendering architecture each.
SOLDIER_RIG = Rig([
    ("root",         (0, 0, 0),                   (0, 0.2, 0),                None),
    ("pelvis",       (0, HIP_Y, 0),               (0, 1.10, 0),               "root"),
    ("spine",        (0, 1.10, 0),                (0, SHOULDER_Y, 0),         "pelvis"),
    ("head",         (0, NECK_Y, 0),              (0, 1.80, 0),               "spine"),
    ("upper_arm.L",  (-SHOULDER_X, SHOULDER_Y, 0), (-SHOULDER_X, ELBOW_Y, 0), "spine"),
    ("lower_arm.L",  (-SHOULDER_X, ELBOW_Y, 0),   (-SHOULDER_X, WRIST_Y, 0),  "upper_arm.L"),
    ("upper_arm.R",  (SHOULDER_X, SHOULDER_Y, 0), (SHOULDER_X, ELBOW_Y, 0),   "spine"),
    ("lower_arm.R",  (SHOULDER_X, ELBOW_Y, 0),    (SHOULDER_X, WRIST_Y, 0),   "upper_arm.R"),
    ("upper_leg.L",  (-HIP_X, HIP_Y, 0),          (-HIP_X, KNEE_Y, 0),        "pelvis"),
    ("lower_leg.L",  (-HIP_X, KNEE_Y, 0),         (-HIP_X, 0.14, 0),          "upper_leg.L"),
    ("upper_leg.R",  (HIP_X, HIP_Y, 0),           (HIP_X, KNEE_Y, 0),         "pelvis"),
    ("lower_leg.R",  (HIP_X, KNEE_Y, 0),          (HIP_X, 0.14, 0),           "upper_leg.R"),
    ## Carried in the right hand. Godot re-parents nothing at runtime any
    ## more: the weapon moves because its bone does.
    ("weapon",       (0.08, ELBOW_Y, 0),          (0.08, ELBOW_Y, -0.5),      "lower_arm.R"),
])


## Helmet plan: an EGG, deeper than wide and narrower at the front. From
## a 62-degree camera the helmet outline is the only facing cue infantry
## have, and a circle gives none.
HELM_PLAN = [(-0.102, -0.128), (0.102, -0.128), (0.126, -0.005),
             (0.106, 0.118), (0.0, 0.162), (-0.106, 0.118), (-0.126, -0.005)]


def _scaled(outline, k):
    cx = sum(p[0] for p in outline) / len(outline)
    cz = sum(p[1] for p in outline) / len(outline)
    return [(cx + (x - cx) * k, cz + (z - cz) * k) for x, z in outline]


## Infantry values, chosen against the TERRAIN rather than against each
## other. Measured: OLIVE (the old uniform) is luma 0.305 and the grass
## it stands on is 0.311 - the man was the same value as the ground, so
## nothing but his boots ever separated him from it. Terrain spans
## 0.146 (dark grass) to 0.494 (dry), so the soldier straddles that band
## instead of sitting inside it: a dark body with one bright cap, so
## whichever ground he is on, one end of him contrasts.
FATIGUE = (0.170, 0.210, 0.130)        # luma 0.19  torso and sleeves
TROUSER = (0.138, 0.172, 0.105)        # luma 0.155
WEBBING = (0.112, 0.138, 0.088)        # luma 0.125 the dark core
RUCK = (0.125, 0.155, 0.098)           # luma 0.14
BOOT = (0.095, 0.108, 0.082)           # luma 0.10
BOOT_SOLE = (0.058, 0.063, 0.055)      # luma 0.06  darkest, anchors him
GLOVE = (0.085, 0.097, 0.075)          # luma 0.09
HELMET_SHELL = (0.240, 0.270, 0.230)   # luma 0.26  below grass
WEAPON_BLACK = (0.075, 0.086, 0.078)   # luma 0.08  max contrast


def soldier(m, uniform=FATIGUE, gear=WEBBING, helmet="Faction", helmet_color=WHITE,
            trouser=None, pack="standard"):
    """The shared humanoid, as ONE skinned mesh on SOLDIER_RIG.

    Bone positions are fixed by the rig, so everything here is shaped
    AROUND them. What this is trying to fix is that the old figure was
    seven bare boxes - no neck, no hands, a slab for a torso - which read
    as a toy however well it was lit.

    The additions are all silhouette or light-catching, because those are
    the only two things that survive to the gameplay camera: a neck so
    the head is attached to something, hands so the arms end, shoulders
    and a tapered chest so the outline is a person's, webbing so the
    front is not one flat plane, and boots with a sole.

    Returns the node so a variant can add its own kit, tagging each piece
    with the bone that should carry it.
    """
    legs = trouser if trouser is not None else TROUSER
    n = m.skinned("Soldier", SOLDIER_RIG)

    for side, x in (("L", -HIP_X), ("R", HIP_X)):
        n.bone("upper_leg.%s" % side)
        ## Thigh 0.51-0.95, shin 0.14-0.51: a real leg is half the man.
        ## Narrow enough that daylight shows between the legs, which is
        ## one of the strongest "this is a person" cues at any distance.
        n.box((0.165, 0.44, 0.19), (x, 0.73, 0), "Body", legs, taper=0.84)
        n.bone("lower_leg.%s" % side)
        n.box((0.135, 0.37, 0.155), (x, 0.325, 0), "Body", legs, taper=1.05)
        n.box((0.15, 0.115, 0.22), (x, 0.1, -0.02), "Body", BOOT)
        n.box((0.17, 0.045, 0.26), (x, 0.025, -0.03), "Body", BOOT_SOLE)

    n.bone("pelvis")
    ## Hips: short, and narrower than the chest. The waist is the pinch
    ## that makes a torso a torso rather than a column.
    n.box((0.32, 0.15, 0.22), (0, 1.025, 0), "Body", legs, taper=1.05)
    n.box((0.35, 0.055, 0.25), (0, 1.095, 0), "Body", WEBBING)  # belt

    n.bone("spine")
    ## Chest 1.10-1.47, widening into the shoulders.
    n.box((0.33, 0.37, 0.22), (0, 1.285, 0), "Body", uniform, taper=1.18)
    n.box((0.34, 0.28, 0.15), (0, 1.27, 0.09), "Body", gear)   # plate carrier
    for px in (-0.09, 0.09):
        n.box((0.095, 0.08, 0.06), (px, 1.15, 0.145), "Body", gear)
    if pack == "standard":
        n.box((0.27, 0.25, 0.14), (0, 1.30, -0.155), "Body", RUCK)
    elif pack == "tall":
        n.box((0.30, 0.38, 0.16), (0, 1.40, -0.165), "Body", RUCK)

    for side, x in (("L", -SHOULDER_X), ("R", SHOULDER_X)):
        n.bone("spine")
        n.box((0.13, 0.11, 0.185), (x * 0.80, 1.45, 0), "Body", gear)
        ## Faction mark: up-facing, two of them, far apart.
        n.box((0.135, 0.032, 0.16), (x * 0.80, 1.505, 0), helmet, helmet_color)
        n.bone("upper_arm.%s" % side)
        n.box((0.115, 0.34, 0.125), (x, 1.30, 0), "Body", uniform, taper=0.90)
        n.bone("lower_arm.%s" % side)
        n.box((0.10, 0.26, 0.11), (x, 1.00, 0), "Body", uniform, taper=1.04)
        n.box((0.095, 0.105, 0.11), (x, 0.815, 0.01), "Body", GLOVE)

    n.bone("spine")
    ## Neck. Shoulders top out at 1.505 and the chin is at 1.57, so there
    ## is finally visible daylight under the head - which is most of what
    ## separates a man from a peg with a hat on.
    n.box((0.105, 0.085, 0.105), (0, 1.525, 0), "Body", SAND_DARK)

    n.bone("head")
    ## Narrower than it is deep, as a head is. A cube head is the single
    ## loudest toy signal on a figure this size.
    n.box((0.175, 0.195, 0.205), (0, 1.665, 0.005), "Body", SAND, taper=0.93)
    ## Helmet. One faceted dome rather than stacked rings - layering thin
    ## plan slices to get an egg plan put a bevelled seam at every joint
    ## and the whole thing read as a beehive. It sits low enough to cover
    ## the skull, so only the face shows beneath it, and a brim at the
    ## front gives the facing cue the round plan cannot.
    n.sphere(0.136, (0, 1.712, 0.004), "Body", HELMET_SHELL,
             rings=4, segments=10, squash=0.82, smooth=False)
    n.box((0.225, 0.034, 0.10), (0, 1.651, -0.105), "Body", HELMET_SHELL)
    ## Crown in faction colour: small, up-facing, on the surface an RTS
    ## camera sees most of.
    n.box((0.165, 0.030, 0.185), (0, 1.818, 0.012), helmet, helmet_color)
    return n


def _weapon(n):
    """Everything after this rides the weapon bone, which recoils."""
    return n.bone("weapon")


def rifle_soldier():
    m = Model("rifle_soldier", "units")
    m.bevel = 0.018  # edge highlights; flat boxes are why he read as a toy
    m.ao_distance = 0.22  # crease under brim and pack, not a dimmed figure
    m.ao_floor = 0.40
    n = soldier(m, pack=None)
    _weapon(n)
    ## Receiver, barrel, magazine, stock. A rifle made of one slab reads
    ## as a plank from any angle; the magazine under the receiver is the
    ## single piece that most says "weapon" at a glance.
    n.box((0.065, 0.09, 0.40), (0.08, 1.12, -0.18), "Metal", WEAPON_BLACK)
    n.box((0.035, 0.045, 0.46), (0.08, 1.135, -0.58), "Metal", WEAPON_BLACK)
    n.box((0.05, 0.15, 0.09), (0.08, 1.035, -0.20), "Metal", WEAPON_BLACK)
    n.box((0.06, 0.085, 0.26), (0.08, 1.10, 0.14), "Metal", WEAPON_BLACK)
    return m


def at_squad():
    """Anti-tank team: a launcher on the shoulder, fat tube, spare rocket on
    the back - the tube is what says 'this one kills tanks'."""
    m = Model("at_squad", "units")
    m.bevel = 0.018  # edge highlights; flat boxes are why he read as a toy
    m.ao_distance = 0.22  # crease under brim and pack, not a dimmed figure
    m.ao_floor = 0.40
    n = soldier(m, pack="tall")
    _weapon(n)
    n.cylinder(0.11, 1.3, (0.2, 1.5, -0.1), "Metal", OLIVE_DARK, axis="z", segments=8)
    n.cylinder(0.14, 0.2, (0.2, 1.5, -0.78), "Metal", SHADOW, axis="z", segments=8)
    ## The spare rocket rides on the spine, so it stays with the body
    ## rather than swinging with the launcher.
    n.bone("spine")
    n.cylinder(0.08, 0.7, (-0.05, 1.2, 0.3), "Metal", OLIVE, axis="y", segments=6)
    return m


def engineer():
    """Engineer: no rifle, a big toolbox and a hard hat stripe - the only
    soldier carrying something square."""
    m = Model("engineer", "units")
    m.bevel = 0.018  # edge highlights; flat boxes are why he read as a toy
    m.ao_distance = 0.22  # crease under brim and pack, not a dimmed figure
    m.ao_floor = 0.40
    n = soldier(m, uniform=SAND_DARK, gear=RUST)
    ## Toolbox in the right hand and wrench in the left, carried by the
    ## forearm bones so they swing with the arms.
    n.bone("lower_arm.R")
    n.box((0.46, 0.28, 0.2), (0.3, 0.7, -0.05), "Metal", HAZARD)
    n.box((0.3, 0.06, 0.06), (0.3, 0.88, -0.05), "Metal", SHADOW)
    n.bone("lower_arm.L")
    n.box((0.12, 0.5, 0.12), (-0.3, 1.0, -0.2), "Metal", STEEL, rot_x=-25)
    return m


def spy():
    """Spy: a long coat, a soft cap instead of a helmet, a pistol - a
    civilian silhouette among soldiers. Same skeleton as every other
    humanoid; the coat does the work."""
    m = Model("spy", "units")
    m.bevel = 0.018  # edge highlights; flat boxes are why he read as a toy
    m.ao_distance = 0.22  # crease under brim and pack, not a dimmed figure
    m.ao_floor = 0.40
    n = m.skinned("Soldier", SOLDIER_RIG)

    for side, x in (("L", -HIP_X), ("R", HIP_X)):
        n.bone("upper_leg.%s" % side)
        n.box((0.16, 0.36, 0.18), (x, 0.68, 0), "Body", SHADOW)
        n.bone("lower_leg.%s" % side)
        n.box((0.15, 0.36, 0.17), (x, 0.32, 0), "Body", SHADOW)
        n.box((0.16, 0.14, 0.26), (x, 0.07, -0.04), "Body", RUBBER)

    n.bone("pelvis")
    n.box((0.46, 0.3, 0.3), (0, 0.95, 0), "Body", STEEL, taper=1.05)
    n.bone("spine")
    n.box((0.5, 0.62, 0.34), (0, 1.22, 0), "Body", STEEL, taper=0.86)  # coat
    n.box((0.54, 0.1, 0.36), (0, 1.42, 0), "Body", STEEL)

    for side, x in (("L", -SHOULDER_X), ("R", SHOULDER_X)):
        n.bone("upper_arm.%s" % side)
        n.box((0.13, 0.26, 0.14), (x, 1.23, 0), "Body", STEEL)
        n.bone("lower_arm.%s" % side)
        n.box((0.12, 0.25, 0.13), (x, 1.00, 0), "Body", STEEL)

    n.bone("head")
    n.box((0.2, 0.22, 0.2), (0, 1.56, 0), "Body", SAND)
    n.cylinder(0.16, 0.1, (0, 1.70, 0), "Faction", WHITE, segments=8)
    n.box((0.34, 0.03, 0.34), (0, 1.66, -0.04), "Body", SHADOW)

    _weapon(n)
    n.box((0.06, 0.1, 0.24), (0.1, 1.08, -0.3), "Metal", GUNMETAL)
    return m


## The dog gets its own skeleton rather than being forced onto the
## humanoid one: four legs, a spine that runs horizontally, and a tail.
DOG_RIG = Rig([
    ("root",      (0, 0, 0),           (0, 0.2, 0),          None),
    ("spine",     (0, 0.56, 0.3),      (0, 0.56, -0.3),      "root"),
    ("neck",      (0, 0.68, -0.3),     (0, 0.84, -0.52),     "spine"),
    ("head",      (0, 0.84, -0.56),    (0, 0.84, -0.84),     "neck"),
    ("tail",      (0, 0.72, 0.4),      (0, 0.80, 0.68),      "spine"),
    ("leg.FL",    (-0.1, 0.42, -0.28), (-0.1, 0.0, -0.28),   "spine"),
    ("leg.FR",    (0.1, 0.42, -0.28),  (0.1, 0.0, -0.28),    "spine"),
    ("leg.BL",    (-0.1, 0.42, 0.3),   (-0.1, 0.0, 0.3),     "spine"),
    ("leg.BR",    (0.1, 0.42, 0.3),    (0.1, 0.0, 0.3),      "spine"),
])


def attack_dog():
    """Attack dog: low and long, head up, tail out, a faction collar.
    One skinned mesh on its own four-legged skeleton."""
    m = Model("attack_dog", "units")
    m.bevel = 0.018  # edge highlights; flat boxes are why he read as a toy
    m.ao_distance = 0.22  # crease under brim and pack, not a dimmed figure
    m.ao_floor = 0.40
    n = m.skinned("Dog", DOG_RIG)

    n.bone("spine")
    n.box((0.3, 0.32, 0.8), (0, 0.56, 0.02), "Body", TIMBER, taper=0.92)
    n.bone("neck")
    n.box((0.24, 0.26, 0.3), (0, 0.78, -0.46), "Body", TIMBER, rot_x=-20)
    n.box((0.26, 0.06, 0.12), (0, 0.8, -0.38), "Faction", WHITE)  # collar
    n.bone("head")
    n.box((0.22, 0.22, 0.28), (0, 0.9, -0.62), "Body", TIMBER)
    n.box((0.14, 0.12, 0.2), (0, 0.84, -0.8), "Body", SHADOW)  # muzzle
    for side in (-1, 1):
        n.box((0.06, 0.12, 0.06), (side * 0.08, 1.05, -0.58), "Body", SHADOW)
    n.bone("tail")
    n.box((0.06, 0.06, 0.34), (0, 0.72, 0.52), "Body", TIMBER, rot_x=30)

    for name, x, z, shade in (("FL", -0.1, -0.28, SHADOW), ("FR", 0.1, -0.28, SHADOW),
                              ("BL", -0.1, 0.3, TIMBER), ("BR", 0.1, 0.3, TIMBER)):
        n.bone("leg.%s" % name)
        n.box((0.08, 0.42, 0.09), (x, 0.21, z), "Body", shade)
    return m


ASSETS.update({
    "rifle_soldier": rifle_soldier,
    "at_squad": at_squad,
    "engineer": engineer,
    "spy": spy,
    "attack_dog": attack_dog,
})
