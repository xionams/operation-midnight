"""Neutral civilian buildings (garrisonable). Origin at ground centre.

Civilian art uses the warm domestic palette only (BRICK, PLASTER,
ROOF_TILE, ROOF_TIN, TIMBER) and carries NO Faction material: being
unmarked is how a player tells a neutral building from an enemy one.
Each has a pitched or stepped roofline, unlike the flat and battered
military concrete, so the two kits never blur at RTS zoom.
"""

from om_kit import *  # noqa: F401,F403


def gable_roof(n, w, d, y, rise, color, overhang=0.25, along="x"):
    """Pitched roof over a w x d block; the ridge runs along `along`."""
    if along == "x":
        hd = d / 2.0 + overhang
        n.prism([(-hd, y), (0.0, y + rise), (hd, y)], -w / 2.0 - overhang, w / 2.0 + overhang,
                "Body", color)
    else:
        hw = w / 2.0 + overhang
        n.prism([(-hw, y), (0.0, y + rise), (hw, y)], -d / 2.0 - overhang, d / 2.0 + overhang,
                "Body", color, rot_y=90)


def window(n, x, y, z, face, w=0.55, h=0.7, frame=PLASTER):
    """A glazed window with a sill on one face ('x+', 'x-', 'z+', 'z-')."""
    axis, sign = face[0], (1 if face[1] == "+" else -1)
    if axis == "x":
        n.box((0.06, h, w), (x + sign * 0.03, y, z), "Glass", GLASS_DARK)
        n.box((0.14, 0.08, w + 0.14), (x + sign * 0.06, y - h / 2.0 - 0.04, z), "Body", frame)
    else:
        n.box((w, h, 0.06), (x, y, z + sign * 0.03), "Glass", GLASS_DARK)
        n.box((w + 0.14, 0.08, 0.14), (x, y - h / 2.0 - 0.04, z + sign * 0.06), "Body", frame)


def civilian_house():
    """Small two-storey house: plaster walls, tiled gable, chimney, porch."""
    m = Model("civilian_house", "civilian")
    n = m.node("Body")
    W, D, H = 3.6, 3.2, 3.0
    n.box((W + 0.2, 0.3, D + 0.2), (0, 0.15, 0), "Body", CONCRETE_DARK)  # footing
    n.box((W, H - 0.3, D), (0, 0.3 + (H - 0.3) / 2.0, 0), "Body", PLASTER)
    gable_roof(n, W, D, H, 1.3, ROOF_TILE, overhang=0.28)
    # gable-end infill (the prism already closes it; add a timber band)
    n.box((W + 0.04, 0.12, D + 0.04), (0, H - 0.02, 0), "Body", TIMBER)
    n.box((0.5, 1.6, 0.5), (1.0, H + 0.6, 0.7), "Body", BRICK)  # chimney
    n.box((0.6, 0.1, 0.6), (1.0, H + 1.45, 0.7), "Body", CONCRETE_DARK)
    # door and porch on +X
    n.box((0.06, 1.3, 0.8), (W / 2.0 + 0.03, 0.95, -0.6), "Body", TIMBER)
    n.box((0.9, 0.08, 1.4), (W / 2.0 + 0.45, 1.85, -0.6), "Body", ROOF_TIN)
    for z in (-1.2, 0.0):
        n.box((0.08, 1.55, 0.08), (W / 2.0 + 0.8, 1.08, z), "Body", TIMBER)
    # windows, two storeys
    for y in (1.2, 2.3):
        window(n, W / 2.0, y, 0.8, "x+")
        window(n, -W / 2.0, y, -0.6, "x-")
        window(n, -W / 2.0, y, 0.7, "x-")
        for x in (-1.0, 0.8):
            window(n, x, y, D / 2.0, "z+")
            window(n, x, y, -D / 2.0, "z-")
    # a garden fence stub and a water butt: scale cues
    n.cylinder(0.28, 0.7, (-1.9, 0.35, 1.4), "Body", TIMBER, segments=8)
    for i in range(4):
        n.box((0.06, 0.7, 0.06), (1.9 + 0.1 * i, 0.35, 1.9 - i * 0.02), "Body", TIMBER)
    return m


def civilian_structure():
    """Medium urban block: three storeys, flat roof with parapet and water
    tank, shopfront on the ground floor. Garrison fodder in town fights."""
    m = Model("civilian_structure", "civilian")
    n = m.node("Body")
    W, D = 4.8, 4.6
    floors = 3
    fh = 1.35
    n.box((W, 0.35, D), (0, 0.175, 0), "Body", CONCRETE_DARK)
    body_h = floors * fh
    n.box((W, body_h - 0.35, D), (0, 0.35 + (body_h - 0.35) / 2.0, 0), "Body", BRICK)
    # string courses between floors
    for f in range(1, floors):
        n.box((W + 0.08, 0.1, D + 0.08), (0, f * fh + 0.35, 0), "Body", PLASTER)
    # parapet and roof clutter
    n.box((W + 0.1, 0.4, D + 0.1), (0, body_h + 0.2, 0), "Body", PLASTER)
    n.box((W - 0.3, 0.1, D - 0.3), (0, body_h + 0.36, 0), "Body", SHADOW)
    n.cylinder(0.5, 0.9, (1.2, body_h + 1.0, -1.1), "Body", TIMBER, segments=10)
    for x in (0.9, 1.5):
        n.box((0.08, 0.6, 0.08), (x, body_h + 0.4, -1.1), "Metal", STEEL)
    vent_box = (0.7, 0.4, 0.5)
    n.box(vent_box, (-1.4, body_h + 0.5, 1.2), "Metal", STEEL_LIGHT)
    n.box((0.5, 0.7, 0.5), (-1.4, body_h + 0.65, -1.3), "Body", BRICK)  # stair head
    # shopfront on +X: big glass, awning
    n.box((0.06, 1.0, 3.2), (W / 2.0 + 0.03, 0.95, 0), "Glass", GLASS_DARK)
    n.box((0.8, 0.08, 3.4), (W / 2.0 + 0.38, 1.78, 0), "Body", HULL_RED, rot_z=-14)
    # windows on upper floors, all faces
    for f in range(1, floors):
        y = 0.35 + f * fh + 0.62
        for t in (-1.4, 0.0, 1.4):
            window(n, W / 2.0, y, t, "x+", w=0.6, h=0.7)
            window(n, -W / 2.0, y, t, "x-", w=0.6, h=0.7)
            window(n, t, y, D / 2.0, "z+", w=0.6, h=0.7)
            window(n, t, y, -D / 2.0, "z-", w=0.6, h=0.7)
    for t in (-1.4, 1.4):
        window(n, t, 1.0, D / 2.0, "z+", w=0.6, h=0.7)
        window(n, t, 1.0, -D / 2.0, "z-", w=0.6, h=0.7)
    return m


def civilian_warehouse():
    """Low, long warehouse: corrugated tin barrel roof, loading doors, a
    dock ramp. The widest civilian footprint; reads as industrial but
    domestic in colour, never military."""
    m = Model("civilian_warehouse", "civilian")
    n = m.node("Body")
    W, D, H = 8.2, 6.0, 3.0
    n.box((W + 0.3, 0.3, D + 0.3), (0, 0.15, 0), "Body", CONCRETE_DARK)
    n.box((W, H - 0.3, D), (0, 0.3 + (H - 0.3) / 2.0, 0), "Body", CONCRETE_LIGHT)
    # low-pitch tin roof along X with a clerestory
    gable_roof(n, W, D, H, 1.2, ROOF_TIN, overhang=0.3)
    n.box((W * 0.7, 0.5, 0.9), (0, H + 1.05, 0), "Body", ROOF_TIN)
    n.box((W * 0.7, 0.3, 0.06), (0, H + 1.0, -0.46), "Glass", GLASS_DARK)
    n.box((W * 0.7, 0.3, 0.06), (0, H + 1.0, 0.46), "Glass", GLASS_DARK)
    # corrugation ribs on the long walls
    for i in range(12):
        x = -W / 2.0 + 0.35 + i * (W - 0.7) / 11
        for s in (-1, 1):
            n.box((0.08, H - 0.4, 0.05), (x, 1.6, s * (D / 2.0 + 0.02)), "Body", CONCRETE)
    # two roller doors on -Z face plus the loading dock
    for x in (-2.2, 1.6):
        n.box((2.0, 2.2, 0.06), (x, 1.4, -D / 2.0 - 0.03), "Metal", RUST)
        for k in range(5):
            n.box((2.0, 0.05, 0.08), (x, 0.5 + k * 0.42, -D / 2.0 - 0.06), "Metal", TIMBER)
    n.box((6.2, 0.5, 1.2), (-0.3, 0.55, -D / 2.0 - 0.6), "Body", CONCRETE)
    # office door and windows on +X gable
    n.box((0.06, 1.8, 0.9), (W / 2.0 + 0.03, 1.2, 1.4), "Body", TIMBER)
    window(n, W / 2.0, 1.8, -1.2, "x+", w=1.1, h=0.6)
    # pallets and drums outside
    for i in range(3):
        n.box((0.9, 0.18, 0.9), (W / 2.0 + 0.9, 0.09 + i * 0.2, -1.8), "Body", TIMBER)
    for z in (1.0, 1.7):
        n.cylinder(0.3, 0.9, (-W / 2.0 - 0.5, 0.45, z), "Metal", HULL_RED, segments=8)
    return m


ASSETS = {
    "civilian_house": civilian_house,
    "civilian_structure": civilian_structure,
    "civilian_warehouse": civilian_warehouse,
}
