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

from om_kit import *  # noqa: F401,F403


def wheel(n, x, z, r, width=0.34, y=None):
    y = r if y is None else y
    n.cylinder(r, width, (x, y, z), "Body", RUBBER, axis="x", segments=12)
    n.cylinder(r * 0.55, width + 0.04, (x, y, z), "Metal", STEEL, axis="x", segments=8)


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
        n.cylinder(r * 0.78, 0.5, (side_x, r * 0.9, z), "Metal", STEEL, axis="x", segments=10)
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
