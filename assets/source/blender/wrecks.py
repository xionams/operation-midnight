"""What is left after something is destroyed.

One generic burnt hull stood in for every vehicle in the game, from a
scout car to a main battle tank, and ships left nothing at all. A wreck
is information as much as decoration - it tells a player what died here
and roughly how big it was - and a single silhouette for everything
throws that away.

All of these are BURNT: the palette is soot and rust only, no faction
colour and no clean metal, because a wreck that still reads as "olive
vehicle" reads as a live one at gameplay zoom. Low triangle counts
throughout - these persist on the field and are capped by count, so
their cost is paid for the rest of the match.
"""

import math

from om_kit import *  # noqa: F401,F403


def turn(outline, degrees):
    """Rotate a footprint about its own centre.

    plan() takes a centre and a taper but no rotation, so anything lying
    at an angle - a turret blown off its ring - has to be turned here.
    """
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)
    return [(x * c - z * s, x * s + z * c) for x, z in outline]


SOOT = (0.105, 0.098, 0.094)
CHAR = (0.165, 0.150, 0.140)
ASH = (0.30, 0.29, 0.28)
OIL = (0.07, 0.075, 0.085)


def vehicle_wreck_light():
    """A burnt-out light vehicle: scout cars and IFVs. Small, low, with
    the wheels gone and the hull slumped onto its axles."""
    m = Model("vehicle_wreck_light", "props")
    m.bevel = 0.04
    n = m.node("Body")
    ## Hull, canted over: a wreck sitting dead level reads as parked.
    n.plan([(-0.85, -1.5), (0.85, -1.5), (0.95, 0.4), (0.75, 1.5), (-0.75, 1.5), (-0.95, 0.4)],
           0.10, 0.82, "Body", SOOT, taper=0.88)
    n.box((1.5, 0.22, 2.4), (0.0, 0.16, 0.0), "Body", CHAR, rot_z=4)
    ## Burst hatch and a stub of the gun, bent.
    n.box((0.6, 0.12, 0.6), (0.1, 0.86, -0.3), "Metal", CHAR, rot_y=22, rot_z=-9)
    n.tube((0.1, 0.80, -0.5), (0.35, 0.55, -1.7), 0.06, "Metal", SOOT, segments=6)
    ## Axle stubs where the wheels were.
    for x in (-0.9, 0.9):
        for z in (-1.0, 0.2, 1.1):
            n.cylinder(0.12, 0.26, (x, 0.22, z), "Metal", SOOT, axis="x", segments=6)
    ## Scorch skirt, so it sits in the ground instead of on it.
    n.plan([(-1.5, -2.2), (1.5, -2.2), (1.7, 0.6), (1.2, 2.2), (-1.2, 2.2), (-1.7, 0.6)],
           0.0, 0.035, "Body", OIL)
    return m


def vehicle_wreck_heavy():
    """A dead tank: bigger, tracks thrown, turret off its ring and lying
    beside the hull. The thrown turret is the read - nothing else on the
    field looks like that."""
    m = Model("vehicle_wreck_heavy", "props")
    m.bevel = 0.05
    n = m.node("Body")
    n.plan([(-1.25, -2.6), (1.25, -2.6), (1.45, 0.0), (1.25, 2.6), (-1.25, 2.6), (-1.45, 0.0)],
           0.20, 1.05, "Body", SOOT, taper=0.9)
    ## Track runs, one of them broken and trailing off the hull.
    n.box((0.5, 0.42, 5.0), (-1.3, 0.28, 0.0), "Metal", CHAR)
    n.box((0.5, 0.42, 3.4), (1.3, 0.28, -0.6), "Metal", CHAR, rot_y=-7)
    n.box((0.46, 0.14, 1.6), (1.55, 0.09, 1.9), "Metal", CHAR, rot_y=-24)  # thrown track
    ## The turret, upside down on the ground alongside.
    n.plan(turn([(-0.9, -0.5), (0.9, -0.5), (1.0, 0.9), (-1.0, 0.9)], -38),
           0.0, 0.55, "Body", CHAR, center=(2.2, 0.0, 0.9), taper=1.15)
    n.tube((2.4, 0.30, 0.2), (3.0, 0.22, -1.6), 0.10, "Metal", SOOT, segments=8)
    ## Open hull ring where it came off, and a buckled deck.
    n.cylinder(0.85, 0.16, (0.0, 1.06, -0.2), "Metal", OIL, segments=10)
    n.box((1.4, 0.1, 1.2), (0.2, 1.10, 1.3), "Metal", CHAR, rot_z=6)
    n.plan([(-2.0, -3.4), (2.0, -3.4), (2.4, 0.4), (1.8, 3.4), (-1.8, 3.4), (-2.4, 0.4)],
           0.0, 0.035, "Body", OIL)
    return m


def naval_debris():
    """What a sunk ship leaves on the surface: a slick, a few planks and
    a floating crate. The hull itself is gone - a sunk ship has no hulk,
    which is the whole difference between losing a boat and a tank - so
    this is deliberately flat and low, riding the waterline."""
    m = Model("naval_debris", "props")
    m.bevel = 0.0
    n = m.node("Body")
    ## The slick: a broad, almost flat sheet. Read at distance, this is
    ## the whole asset.
    n.plan([(-3.4, -2.2), (-1.0, -3.4), (2.6, -2.8), (3.6, 0.2), (2.0, 3.0),
            (-1.4, 3.2), (-3.6, 1.2)], 0.0, 0.04, "Body", OIL)
    ## Planks and a crate, scattered off-centre so it never looks placed.
    for x, z, yaw in ((-1.6, 0.7, 18), (0.9, -1.1, -34), (1.8, 1.6, 62), (-0.4, 2.0, -12)):
        n.box((0.22, 0.09, 1.5), (x, 0.06, z), "Body", CHAR, rot_y=yaw)
    n.box((0.6, 0.42, 0.6), (1.2, 0.18, 0.4), "Body", SOOT, rot_y=24)
    n.box((0.5, 0.3, 0.5), (-2.0, 0.13, -1.2), "Body", ASH, rot_y=-40)
    return m


def building_ruin():
    """A structure's remains: standing wall stubs around a collapsed
    middle, with roof slabs fallen inward. Modelled to match the current
    building kit - the old ruin predates it and reads as a different
    game's asset next to a modelled base."""
    m = Model("building_ruin", "props")
    m.bevel = 0.05
    n = m.node("Body")
    ## Broken wall stubs: different heights, so the outline is jagged.
    stubs = [(-2.0, -2.0, 1.5, 0.45, 1.6), (0.6, -2.1, 2.2, 0.42, 0.9),
             (2.1, -0.2, 0.5, 1.9, 1.3), (-2.1, 0.8, 0.5, 2.0, 1.05),
             (1.0, 2.1, 2.6, 0.44, 0.7)]
    for x, z, w, d, h in stubs:
        n.box((w, h, d), (x, h / 2.0, z), "Body", CONCRETE_DARK, taper=0.94)
    ## Collapsed slabs across the middle, tipped at angles.
    n.box((2.6, 0.18, 2.0), (0.1, 0.30, 0.2), "Body", CONCRETE_DARK, rot_z=-11, rot_y=14)
    n.box((2.0, 0.16, 1.6), (-0.7, 0.52, -0.6), "Body", CONCRETE, rot_z=17, rot_y=-26)
    n.box((1.4, 0.14, 1.2), (1.1, 0.42, 1.1), "Body", CONCRETE_DARK, rot_z=8, rot_y=40)
    ## Exposed rebar and a scorched core.
    for x, z in ((-0.9, 1.4), (1.5, -1.2), (0.2, -1.6)):
        n.tube((x, 0.2, z), (x + 0.12, 1.1, z - 0.1), 0.035, "Metal", RUST, segments=5)
    n.plan([(-2.6, -2.6), (2.6, -2.6), (2.6, 2.6), (-2.6, 2.6)], 0.0, 0.04, "Body", SOOT)
    return m


ASSETS = {
    "vehicle_wreck_light": vehicle_wreck_light,
    "vehicle_wreck_heavy": vehicle_wreck_heavy,
    "naval_debris": naval_debris,
    "building_ruin": building_ruin,
}
