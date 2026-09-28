"""Naval kit: ships, submarine, Naval Yard, sonar buoy.

Origin is at the WATERLINE (y = 0 is Water.level), bow toward -Z.
Shape language (docs/ART_DIRECTION.md 18.4): hulls are lofts with a real
entry at the bow and a flat transom at the stern, so heading reads even
when a ship is stopped. Topsides are NAVY_GREY and the antifouling below
the boot-top is HULL_RED. That red band is visible through shallow
water and marks a ship as a ship from any angle. The submarine is
SUB_BLACK with only the faction band on its sail.
"""

import math

from om_kit import *  # noqa: F401,F403


def hull_ring(half_w, deck_y, keel_y, flare=0.95):
    """A V-bottom section, deck edge to deck edge through the keel.
    Seven points so every ring of a loft has equal counts."""
    w = half_w
    return [(-w, deck_y), (-w * flare, 0.0), (-w * 0.55, keel_y * 0.55), (0.0, keel_y),
            (w * 0.55, keel_y * 0.55), (w * flare, 0.0), (w, deck_y)]


def split_hull(n, stations, top_color, bottom_color, boot=0.08):
    """Loft the hull twice: HULL_RED below the boot-top, grey above.
    stations: [(z, half_width, deck_y, keel_y)] from bow to stern."""
    lower, upper = [], []
    for z, w, deck, keel in stations:
        lower.append((z, [(-w * 0.96, boot), (-w * 0.55, keel * 0.55), (0.0, keel),
                          (w * 0.55, keel * 0.55), (w * 0.96, boot)]))
        upper.append((z, [(-w, deck), (-w * 0.97, boot * 0.5), (w * 0.97, boot * 0.5), (w, deck)]))
    n.loft(lower, "Body", bottom_color)
    n.loft(upper, "Body", top_color)


# ------------------------------------------------------------------ patrol boat

def patrol_boat():
    m = Model("patrol_boat", "naval")
    m.ao_ground = None
    m.bevel = 0.03
    n = m.node("Body")
    # bow (-Z) to transom (+Z): sheer rises to the bow, beam widest aft of mid
    stations = [
        (-2.65, 0.04, 0.78, 0.05),
        (-2.2, 0.42, 0.70, -0.20),
        (-1.4, 0.82, 0.60, -0.42),
        (-0.4, 1.02, 0.55, -0.48),
        (0.8, 1.06, 0.52, -0.46),
        (2.0, 1.0, 0.52, -0.40),
        (2.55, 0.94, 0.52, -0.30),
    ]
    split_hull(n, stations, NAVY_GREY, HULL_RED)
    # deck plate, slightly inset, and a raised foredeck gun platform
    deck = [(-0.02, -2.5), (0.3, -2.1), (0.72, -1.4), (0.92, -0.4), (0.96, 0.8), (0.9, 2.0),
            (0.86, 2.5), (-0.86, 2.5), (-0.9, 2.0), (-0.96, 0.8), (-0.92, -0.4), (-0.72, -1.4),
            (-0.3, -2.1)]
    n.plan(deck, 0.5, 0.56, "Body", DECK)
    # bulwark/boot stripe
    n.box((0.03, 0.06, 3.8), (1.02, 0.4, 0.4), "Body", WHITE)
    n.box((0.03, 0.06, 3.8), (-1.02, 0.4, 0.4), "Body", WHITE)
    # bridge: stepped superstructure just aft of midships
    n.box((1.36, 0.62, 1.5), (0, 0.56 + 0.31, 0.45), "Body", NAVY_GREY, taper=0.92)
    n.box((1.1, 0.5, 1.0), (0, 1.18 + 0.25, 0.3), "Body", NAVY_GREY, taper=0.9)
    n.box((1.02, 0.2, 0.06), (0, 1.5, -0.22), "Glass", GLASS_DARK, rot_x=-20)
    for s in (-1, 1):
        n.box((0.05, 0.18, 0.7), (s * 0.5, 1.5, 0.3), "Glass", GLASS_DARK)
    n.box((1.2, 0.06, 1.12), (0, 1.72, 0.3), "Body", NAVY_DARK)
    # mast with the spinning radar and a nav light
    n.tube((0, 1.72, 0.45), (0, 2.75, 0.55), 0.05, "Metal", STEEL_LIGHT, segments=6)
    n.box((0.7, 0.05, 0.05), (0, 2.35, 0.5), "Metal", STEEL_LIGHT)
    lamp_pos = (0, 2.8, 0.55)
    n.box((0.1, 0.1, 0.1), lamp_pos, "Emissive", LAMP)
    r = m.node("Radar", (0, 2.62, 0.54))
    r.box((0.7, 0.08, 0.1), (0, 0, 0), "Metal", STEEL_LIGHT)
    # faction band across the deck abaft the bridge, and on the bridge roof
    n.box((1.6, 0.03, 0.45), (0, 0.58, 1.55), "Faction", WHITE)
    n.box((0.8, 0.03, 0.6), (0, 1.76, 0.3), "Faction", WHITE)
    # stern: life raft canisters, a stern MG, exhaust
    for s in (-1, 1):
        n.cylinder(0.14, 0.5, (s * 0.6, 0.72, 1.9), "Body", WHITE, axis="z", segments=8)
    n.box((0.3, 0.3, 0.24), (0, 0.72, 2.3), "Metal", GUNMETAL)
    n.tube((0, 0.82, 2.3), (0, 0.88, 1.8), 0.035, "Metal", SHADOW, segments=5)
    n.cylinder(0.08, 0.35, (0.45, 1.1, 1.05), "Metal", SHADOW, segments=6)
    # the forward gun: a shielded mount on the foredeck, which aims
    t = m.node("Turret", (0, 0.56, -1.2))
    t.cylinder(0.36, 0.14, (0, 0.07, 0), "Metal", STEEL, segments=12)
    t.box((0.6, 0.42, 0.5), (0, 0.35, 0.05), "Metal", NAVY_GREY, taper=0.8)
    t.tube((0, 0.38, -0.15), (0, 0.44, -1.15), 0.06, "Metal", GUNMETAL, segments=6)
    t.cylinder(0.08, 0.12, (0, 0.44, -1.15), "Metal", SHADOW, axis="z", segments=6)
    return m


# ------------------------------------------------------------------ submarine

def submarine():
    m = Model("submarine", "naval")
    m.ao_ground = None
    m.bevel = 0.02
    n = m.node("Body")
    # a smooth cigar: round sections along Z, blunt bow, tapering tail
    stations = [(-3.0, 0.08), (-2.8, 0.42), (-2.4, 0.66), (-1.6, 0.78), (0.0, 0.8),
                (1.2, 0.76), (2.0, 0.6), (2.6, 0.36), (2.95, 0.12)]
    seg = 12
    rings = []
    for z, r in stations:
        ring = []
        for i in range(seg):
            a = math.tau * i / seg
            ring.append((math.cos(a) * r, math.sin(a) * r * 0.88 - 0.12))
        rings.append((z, ring))
    n.loft(rings, "Body", SUB_BLACK, smooth=True)
    # casing deck on the back
    n.box((0.5, 0.06, 3.8), (0, 0.6, -0.6), "Body", NAVY_DARK)
    # the sail (fin) forward of midships, with dive planes
    sail = [(-0.26, -1.55), (0.26, -1.55), (0.3, -0.6), (0.0, -0.1), (-0.3, -0.6)]
    sail = [(x, z) for x, z in sail]
    n.plan([(-0.22, -1.6), (0.22, -1.6), (0.24, -0.5), (-0.24, -0.5)], 0.5, 1.45,
           "Body", SUB_BLACK, taper=0.86)
    n.box((1.5, 0.06, 0.32), (0, 1.1, -1.3), "Body", SUB_BLACK)  # sail planes
    n.box((0.5, 0.05, 0.9), (0, 1.47, -1.05), "Body", NAVY_DARK)
    # periscope and masts
    n.tube((0.06, 1.45, -1.3), (0.06, 2.05, -1.3), 0.035, "Metal", STEEL, segments=5)
    n.tube((-0.08, 1.45, -1.0), (-0.08, 1.85, -1.0), 0.03, "Metal", STEEL, segments=5)
    n.box((0.06, 0.06, 0.06), (0.06, 2.08, -1.3), "Emissive", LAMP)
    # faction band on both sides of the sail
    for s in (-1, 1):
        n.box((0.03, 0.22, 0.8), (s * 0.235, 1.12, -1.05), "Faction", WHITE)
    # bow planes and cruciform stern fins
    n.box((1.8, 0.05, 0.36), (0, 0.05, -2.3), "Body", SUB_BLACK)
    n.box((1.6, 0.06, 0.6), (0, -0.12, 2.35), "Body", SUB_BLACK, taper=0.7)
    n.box((0.06, 1.3, 0.6), (0, -0.12, 2.35), "Body", SUB_BLACK, taper=0.7)
    # draft marks aft, white: legible at range when surfaced
    for i in range(3):
        n.box((0.03, 0.06, 0.2), (0.62, 0.1 + i * 0.14, 1.7), "Body", WHITE)
    # the screw, which turns
    p = m.node("Propeller", (0, -0.12, 3.0))
    p.cylinder(0.08, 0.2, (0, 0, 0), "Metal", RUST, axis="z", segments=8)
    for i in range(5):
        p.box((0.08, 0.5, 0.04), (0, 0.25, 0), "Metal", RUST, rot_z=72 * i)
    return m


# ------------------------------------------------------------------ naval yard

def naval_yard():
    """Floating dock, bow-out berth toward +X (NavalYard turns the visual
    so the berth faces the open sea, where ships are launched).
    Two jetties framing a berth, a back quay with workshop and slipway
    ramp, a gantry crane over the berth, and a jib crane on the quay."""
    m = Model("naval_yard", "naval")
    m.ao_ground = -2.6  # the sea floor under the pilings
    m.bevel = 0.06
    n = m.node("Body")
    deck = 0.9
    # jetties along X on either side of the berth
    for s in (-1, 1):
        z = s * 3.4
        n.box((9.2, deck + 0.3, 2.2), (0.2, (deck - 0.3) / 2.0, z), "Body", CONCRETE)
        n.box((9.2, 0.08, 2.0), (0.2, deck + 0.04, z), "Body", CONCRETE_DARK)
        # pilings under the deck edge, visible through the water
        for x in (-3.6, -1.2, 1.2, 3.6):
            n.cylinder(0.22, 2.6, (x, -1.2, z - s * 1.0), "Metal", RUST, segments=8)
        # rubber fenders on the berth side
        for x in (-2.4, -0.4, 1.6, 3.6):
            n.cylinder(0.2, 0.34, (x, deck - 0.45, z - s * 1.14), "Body", RUBBER, axis="x", segments=8)
        # hazard edge and bollards on the berth side
        n.box((9.0, 0.06, 0.18), (0.2, deck + 0.1, z - s * 0.95), "Body", HAZARD)
        for x in (-2.8, 0.0, 2.8):
            n.cylinder(0.14, 0.3, (x, deck + 0.15, z - s * 0.7), "Metal", GUNMETAL, segments=8)
        # jetty-head nav light
        n.cylinder(0.12, 0.6, (4.6, deck + 0.3, z), "Metal", STEEL, segments=6)
        n.box((0.2, 0.2, 0.2), (4.6, deck + 0.7, z), "Emissive", LAMP)
        # gantry rails
        for dz in (-0.35, 0.35):
            n.box((8.0, 0.08, 0.1), (0.4, deck + 0.12, z + dz), "Metal", STEEL_LIGHT)
    # back quay across -X
    n.box((2.2, deck + 0.3, 9.0), (-3.6, (deck - 0.3) / 2.0, 0), "Body", CONCRETE)
    # slipway ramp from the quay into the berth
    n.prism([(-2.5, deck), (-2.5, deck - 0.02), (0.5, -0.6), (0.5, -0.5)], -2.5, 2.5,
            "Body", CONCRETE_DARK, rot_y=90)
    for i in range(5):
        n.box((0.14, 0.08, 4.8), (-2.2 + i * 0.6, deck - 0.3 - i * 0.28, 0), "Metal", RUST)
    # workshop on the quay
    n.box((1.9, 1.8, 3.0), (-3.6, deck + 0.9, -2.8), "Body", CONCRETE_LIGHT)
    n.prism([(-4.4, deck + 1.8), (-2.8, deck + 2.3), (-1.2, deck + 1.8)], -4.6, -2.6,
            "Body", ROOF_TIN, rot_y=90)
    n.box((0.06, 1.2, 1.4), (-2.63, deck + 0.6, -2.8), "Metal", STEEL)
    n.box((0.06, 0.4, 2.2), (-4.57, deck + 1.3, -2.8), "Faction", WHITE)
    n.box((1.4, 0.04, 1.8), (-3.6, deck + 2.12, -2.8), "Faction", WHITE, rot_x=0)
    # stores: containers and drums
    n.box((1.6, 0.8, 0.8), (-3.6, deck + 0.4, 1.8), "Body", HULL_RED)
    n.box((1.6, 0.8, 0.8), (-3.6, deck + 1.2, 1.9), "Body", OLIVE)
    for z in (3.0, 3.6):
        n.cylinder(0.28, 0.8, (-3.2, deck + 0.4, z), "Metal", HAZARD, segments=8)
    # jib crane base on the quay corner
    n.cylinder(0.45, 0.4, (-3.4, deck + 0.2, 3.4), "Metal", HAZARD, segments=10)
    n.box((0.6, 3.2, 0.6), (-3.4, deck + 2.0, 3.4), "Metal", HAZARD, taper=0.7)
    # the gantry spanning the berth: slides along the rails
    g = m.node("Gantry", (0.6, deck, 0))
    for s in (-1, 1):
        g.box((0.3, 3.4, 0.3), (0, 1.7, s * 3.4), "Metal", HAZARD)
        g.box((1.2, 0.3, 0.9), (0, 0.15, s * 3.4), "Metal", GUNMETAL)
    g.box((0.6, 0.5, 7.4), (0, 3.55, 0), "Metal", HAZARD)
    g.box((0.7, 0.5, 0.8), (0, 3.2, 0.6), "Metal", GUNMETAL)  # trolley
    g.tube((0, 2.95, 0.6), (0, 1.6, 0.6), 0.03, "Metal", SHADOW, segments=4)
    g.box((0.4, 0.2, 0.4), (0, 1.5, 0.6), "Metal", GUNMETAL)
    # the jib, which slews
    c = m.node("Crane", (-3.4, deck + 3.6, 3.4))
    c.box((0.8, 0.7, 0.8), (0, 0.35, 0), "Metal", STEEL)
    c.box((0.8, 0.5, 0.6), (0, 0.9, 0.4), "Glass", GLASS_DARK)
    c.tube((0, 0.6, 0), (4.2, 1.2, -1.6), 0.12, "Metal", HAZARD, segments=6)
    c.tube((0, 0.6, 0), (-1.2, 0.5, 0.45), 0.14, "Metal", HAZARD, segments=6)
    c.box((0.7, 0.6, 0.7), (-1.3, 0.3, 0.5), "Metal", CONCRETE_DARK)  # counterweight
    c.tube((4.2, 1.2, -1.6), (4.2, -1.3, -1.6), 0.025, "Metal", SHADOW, segments=4)
    c.box((0.3, 0.25, 0.3), (4.2, -1.4, -1.6), "Metal", GUNMETAL)
    return m


# ------------------------------------------------------------------ sonar buoy

def sonar_buoy():
    m = Model("sonar_buoy", "naval")
    m.ao_ground = None
    m.bevel = 0.03
    n = m.node("Body")
    # float: a squat drum riding the waterline, red below
    n.cylinder(0.72, 0.5, (0, -0.25, 0), "Body", HULL_RED, segments=12, radius_top=0.7)
    n.cylinder(0.7, 0.36, (0, 0.18, 0), "Body", HAZARD, segments=12, radius_top=0.62)
    n.cylinder(0.64, 0.06, (0, 0.38, 0), "Body", SHADOW, segments=12)
    # hydrophone cable and the sensor body hanging below
    n.tube((0, -0.5, 0), (0, -2.2, 0), 0.04, "Metal", SHADOW, segments=4)
    n.cylinder(0.2, 0.5, (0, -2.4, 0), "Metal", NAVY_DARK, segments=8)
    # mast, faction flag panel, light
    n.cylinder(0.12, 1.4, (0, 1.1, 0), "Metal", STEEL_LIGHT, segments=8, radius_top=0.07)
    n.box((0.04, 0.3, 0.46), (0, 1.3, 0.26), "Faction", WHITE)
    n.box((0.46, 0.3, 0.04), (0.26, 1.3, 0), "Faction", WHITE)
    n.box((0.16, 0.16, 0.16), (0, 1.9, 0), "Emissive", LAMP)
    # the spinning sensor head
    s = m.node("Spinner", (0, 2.1, 0))
    s.cylinder(0.26, 0.14, (0, 0, 0), "Metal", STEEL, segments=10)
    s.box((0.9, 0.06, 0.1), (0, 0.12, 0), "Metal", STEEL_LIGHT)
    return m


ASSETS = {
    "patrol_boat": patrol_boat,
    "submarine": submarine,
    "naval_yard": naval_yard,
    "sonar_buoy": sonar_buoy,
}
