#!/usr/bin/env python3
"""Generate the UI icon set as SVG.

Vector rather than PNG because Godot rasterises SVG at import, so one
file serves every DPI from a phone to a tablet - and because an icon set
that is edited as geometry stays consistent, while a set of hand-drawn
bitmaps drifts.

Every icon is the same 64x64 field, the same dark rounded plate, and the
same two-tone treatment: concrete for the form, amber for whatever the
icon is actually about. See docs/ART_DIRECTION.md section 2.
"""

import os

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "icons")

PLATE = "#22262A"
FORM = "#C8C4BA"
FORM_DIM = "#8A8579"
ACCENT = "#E0A63C"
SIGNAL = "#4FC3C7"
DANGER = "#D9342E"
GO = "#3ADE5A"


def rect(x, y, w, h, fill=FORM, rx=1):
    return '<rect x="%g" y="%g" width="%g" height="%g" rx="%g" fill="%s"/>' % (x, y, w, h, rx, fill)


def circle(cx, cy, r, fill=FORM):
    return '<circle cx="%g" cy="%g" r="%g" fill="%s"/>' % (cx, cy, r, fill)


def poly(points, fill=FORM):
    pts = " ".join("%g,%g" % p for p in points)
    return '<polygon points="%s" fill="%s"/>' % (pts, fill)


def line(x1, y1, x2, y2, stroke=FORM, width=3, cap="round"):
    return '<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="%g" stroke-linecap="%s"/>' % (
        x1, y1, x2, y2, stroke, width, cap)


def path(d, fill="none", stroke=FORM, width=3):
    return '<path d="%s" fill="%s" stroke="%s" stroke-width="%g" stroke-linecap="round" stroke-linejoin="round"/>' % (
        d, fill, stroke, width)


ICONS = {
    # ---------------------------------------------------------- buildings
    "bld_command_hq": [rect(12, 26, 40, 26, FORM), rect(20, 18, 24, 10, FORM_DIM),
                       line(32, 6, 32, 18, ACCENT, 3), line(26, 9, 38, 9, ACCENT, 3),
                       rect(28, 40, 8, 12, PLATE)],
    "bld_power_plant": [rect(10, 30, 44, 22, FORM),
                        poly([(18, 30), (26, 30), (24, 14), (20, 14)], FORM_DIM),
                        poly([(38, 30), (46, 30), (44, 14), (40, 14)], FORM_DIM),
                        poly([(32, 20), (26, 34), (31, 34), (28, 46), (38, 30), (33, 30)], ACCENT)],
    "bld_refinery": [rect(10, 34, 44, 18, FORM),
                     poly([(16, 34), (34, 34), (30, 14), (20, 14)], FORM_DIM),
                     rect(40, 18, 10, 16, FORM_DIM), circle(25, 26, 4, ACCENT)],
    "bld_barracks": [poly([(8, 28), (32, 14), (56, 28)], FORM_DIM),
                     rect(12, 28, 40, 24, FORM), rect(28, 36, 8, 16, PLATE),
                     rect(12, 28, 40, 4, ACCENT, 0)],
    "bld_war_factory": [poly([(8, 26), (32, 12), (56, 26)], FORM_DIM),
                        rect(10, 26, 44, 26, FORM), rect(20, 34, 24, 18, PLATE),
                        line(20, 38, 44, 38, FORM_DIM, 2), line(20, 44, 44, 44, FORM_DIM, 2)],
    "bld_radar_center": [rect(14, 36, 36, 16, FORM), rect(26, 24, 12, 12, FORM_DIM),
                         path("M 16 22 A 18 18 0 0 1 48 14", "none", ACCENT, 4),
                         line(32, 14, 32, 24, FORM_DIM, 3)],
    "bld_tech_center": [rect(12, 28, 40, 24, FORM), rect(20, 16, 24, 12, FORM_DIM),
                        circle(32, 22, 4, SIGNAL), line(22, 10, 22, 16, ACCENT, 2),
                        line(32, 6, 32, 16, ACCENT, 2), line(42, 10, 42, 16, ACCENT, 2)],
    "bld_forward_post": [rect(10, 32, 26, 12, FORM), rect(10, 44, 26, 8, FORM_DIM),
                         rect(36, 36, 18, 16, FORM),
                         line(46, 16, 46, 36, ACCENT, 3), line(40, 20, 52, 20, ACCENT, 2)],
    "bld_mg_tower": [line(20, 52, 26, 30, FORM_DIM, 3), line(44, 52, 38, 30, FORM_DIM, 3),
                     rect(20, 18, 24, 14, FORM), line(32, 25, 54, 25, ACCENT, 4),
                     rect(18, 30, 28, 4, FORM_DIM, 0)],
    "bld_at_turret": [rect(16, 40, 32, 12, FORM_DIM), rect(22, 26, 20, 14, FORM),
                      line(32, 30, 56, 22, ACCENT, 4), line(32, 36, 56, 28, ACCENT, 4)],
    "bld_wall": [rect(8, 24, 48, 12, FORM), rect(8, 38, 48, 12, FORM),
                 line(32, 24, 32, 36, PLATE, 3), line(20, 38, 20, 50, PLATE, 3),
                 line(44, 38, 44, 50, PLATE, 3)],
    "bld_gate": [rect(10, 20, 10, 32, FORM), rect(44, 20, 10, 32, FORM),
                 rect(20, 24, 24, 6, ACCENT, 1), line(24, 40, 40, 40, FORM_DIM, 3)],
    "bld_comms_outpost": [rect(22, 42, 20, 10, FORM),
                          poly([(26, 42), (38, 42), (36, 20), (28, 20)], FORM_DIM),
                          line(22, 26, 42, 26, ACCENT, 2), line(24, 34, 40, 34, ACCENT, 2),
                          circle(32, 14, 4, SIGNAL)],
    "bld_repair_depot": [rect(10, 38, 44, 14, FORM),
                         path("M 24 32 L 32 24 L 40 32", "none", FORM_DIM, 3),
                         path("M 26 20 L 34 12 L 42 20 L 36 26 L 28 18 Z", ACCENT, ACCENT, 2)],
    "bld_supply_depot": [poly([(8, 26), (32, 16), (56, 26)], FORM_DIM),
                         rect(12, 30, 18, 18, FORM), rect(34, 34, 16, 14, FORM),
                         line(12, 38, 30, 38, PLATE, 2), line(34, 40, 50, 40, PLATE, 2)],
    "bld_civilian": [poly([(8, 30), (32, 12), (56, 30)], ACCENT),
                     rect(14, 30, 36, 22, FORM), rect(28, 40, 8, 12, PLATE),
                     rect(18, 34, 7, 7, FORM_DIM), rect(39, 34, 7, 7, FORM_DIM)],

    # -------------------------------------------------------------- units
    "unit_rifle_soldier": [circle(32, 16, 7, FORM), rect(25, 24, 14, 18, FORM),
                           rect(22, 42, 6, 14, FORM_DIM), rect(36, 42, 6, 14, FORM_DIM),
                           line(38, 22, 52, 34, ACCENT, 3)],
    "unit_at_squad": [circle(30, 16, 7, FORM), rect(23, 24, 15, 18, FORM),
                      rect(21, 42, 6, 14, FORM_DIM), rect(34, 42, 6, 14, FORM_DIM),
                      rect(34, 16, 22, 7, ACCENT, 3)],
    "unit_engineer": [circle(32, 16, 7, ACCENT), rect(25, 24, 14, 18, FORM),
                      rect(22, 42, 6, 14, FORM_DIM), rect(36, 42, 6, 14, FORM_DIM),
                      rect(40, 34, 14, 10, ACCENT, 2)],
    "unit_spy": [circle(32, 16, 7, FORM_DIM), rect(25, 24, 14, 18, FORM),
                 rect(22, 42, 6, 14, FORM_DIM), rect(36, 42, 6, 14, FORM_DIM),
                 rect(41, 32, 12, 10, SIGNAL, 2)],
    "unit_attack_dog": [rect(18, 30, 26, 12, FORM, 4), circle(48, 28, 7, FORM),
                        rect(20, 42, 5, 10, FORM_DIM), rect(36, 42, 5, 10, FORM_DIM),
                        line(16, 30, 8, 22, FORM_DIM, 3), poly([(50, 20), (54, 24), (46, 24)], ACCENT)],
    "unit_scout_vehicle": [rect(12, 28, 40, 12, FORM, 2), circle(20, 44, 7, FORM_DIM),
                           circle(44, 44, 7, FORM_DIM), rect(22, 20, 20, 8, FORM_DIM, 2),
                           line(40, 24, 54, 24, ACCENT, 3)],
    "unit_assault_vehicle": [rect(10, 26, 44, 14, FORM, 2), circle(19, 44, 7, FORM_DIM),
                             circle(32, 44, 7, FORM_DIM), circle(45, 44, 7, FORM_DIM),
                             rect(24, 16, 16, 10, FORM_DIM, 2), line(38, 21, 56, 21, ACCENT, 3)],
    "unit_main_battle_tank": [rect(8, 34, 48, 14, FORM_DIM, 3), rect(12, 24, 40, 12, FORM, 2),
                              rect(24, 14, 18, 10, FORM, 2), line(40, 19, 60, 19, ACCENT, 4),
                              line(14, 41, 50, 41, PLATE, 2)],
    "unit_artillery_vehicle": [rect(8, 36, 48, 14, FORM_DIM, 3), rect(14, 26, 36, 12, FORM, 2),
                               line(30, 30, 56, 10, ACCENT, 5), rect(24, 22, 14, 8, FORM, 2)],
    "unit_harvester": [rect(10, 24, 32, 20, ACCENT, 2), rect(42, 28, 12, 16, FORM, 2),
                       circle(20, 48, 6, FORM_DIM), circle(34, 48, 6, FORM_DIM),
                       circle(48, 48, 5, FORM_DIM), poly([(4, 44), (12, 36), (12, 46)], FORM_DIM)],

    # ----------------------------------------------------------- commands
    "cmd_move": [path("M 32 52 L 32 14", "none", GO, 4),
                 poly([(32, 8), (24, 20), (40, 20)], GO), circle(32, 52, 5, GO)],
    "cmd_attack": [circle(32, 32, 16, "none"), path("M 32 32 m -16 0 a 16 16 0 1 0 32 0 a 16 16 0 1 0 -32 0", "none", DANGER, 3),
                   line(32, 10, 32, 22, DANGER, 3), line(32, 42, 32, 54, DANGER, 3),
                   line(10, 32, 22, 32, DANGER, 3), line(42, 32, 54, 32, DANGER, 3),
                   circle(32, 32, 4, DANGER)],
    "cmd_attack_move": [path("M 14 50 L 14 20", "none", DANGER, 4),
                        poly([(14, 12), (7, 24), (21, 24)], DANGER),
                        circle(42, 32, 11, "none"), path("M 42 32 m -11 0 a 11 11 0 1 0 22 0 a 11 11 0 1 0 -22 0", "none", DANGER, 3),
                        circle(42, 32, 3, DANGER)],
    "cmd_stop": [rect(18, 18, 28, 28, DANGER, 3)],
    "cmd_guard": [path("M 32 8 L 52 16 L 52 34 C 52 46 32 56 32 56 C 32 56 12 46 12 34 L 12 16 Z", FORM, FORM, 2),
                  path("M 24 32 L 30 38 L 42 24", "none", PLATE, 4)],
    "cmd_patrol": [path("M 16 40 A 16 16 0 1 1 48 40", "none", SIGNAL, 4),
                   poly([(48, 46), (40, 34), (56, 34)], SIGNAL),
                   circle(16, 44, 4, SIGNAL)],
    "cmd_hold": [rect(12, 28, 40, 10, FORM, 2), line(20, 20, 20, 28, FORM_DIM, 3),
                 line(44, 20, 44, 28, FORM_DIM, 3), line(16, 44, 48, 44, ACCENT, 4)],
    "cmd_aggro": [poly([(32, 8), (40, 26), (58, 26), (44, 38), (50, 56), (32, 44),
                        (14, 56), (20, 38), (6, 26), (24, 26)], DANGER)],
    "cmd_sell": [circle(32, 32, 20, ACCENT),
                 path("M 38 24 C 30 20 24 24 24 28 C 24 36 40 34 40 42 C 40 46 34 48 26 44",
                      "none", PLATE, 4)],
    "cmd_repair": [path("M 26 20 L 34 12 L 44 22 L 36 30 Z", ACCENT, ACCENT, 2),
                   line(32, 30, 18, 48, FORM, 6)],
    "cmd_capture": [rect(18, 12, 4, 44, FORM_DIM), poly([(22, 14), (48, 20), (22, 30)], GO),
                    line(14, 54, 30, 54, FORM_DIM, 3)],
    "cmd_garrison": [rect(14, 26, 36, 26, FORM), poly([(10, 26), (32, 12), (54, 26)], FORM_DIM),
                     poly([(32, 50), (26, 40), (38, 40)], GO)],

    # --------------------------------------------------------- categories
    "cat_buildings": [rect(10, 30, 20, 22, FORM), rect(34, 20, 20, 32, FORM_DIM),
                      rect(16, 36, 8, 8, PLATE), rect(40, 28, 8, 8, PLATE)],
    "cat_defense": [path("M 32 8 L 52 16 L 52 34 C 52 46 32 56 32 56 C 32 56 12 46 12 34 L 12 16 Z",
                         FORM, FORM, 2), line(32, 20, 32, 40, ACCENT, 4)],
    "cat_infantry": [circle(22, 18, 6, FORM), rect(16, 25, 12, 15, FORM),
                     rect(14, 40, 5, 12, FORM_DIM), rect(25, 40, 5, 12, FORM_DIM),
                     circle(44, 18, 6, FORM_DIM), rect(38, 25, 12, 15, FORM_DIM)],
    "cat_vehicles": [rect(8, 30, 48, 14, FORM, 2), circle(20, 48, 6, FORM_DIM),
                     circle(44, 48, 6, FORM_DIM), rect(22, 20, 18, 10, FORM_DIM, 2),
                     line(38, 25, 56, 25, ACCENT, 3)],

    # ------------------------------------------------------------ status
    "ui_credits": [circle(32, 32, 20, ACCENT),
                   path("M 38 24 C 30 20 24 24 24 28 C 24 36 40 34 40 42 C 40 46 34 48 26 44",
                        "none", PLATE, 4), line(32, 16, 32, 50, PLATE, 2)],
    "ui_power": [poly([(36, 6), (18, 34), (30, 34), (26, 58), (46, 28), (34, 28)], SIGNAL)],
    "ui_unit_cap": [circle(24, 20, 7, FORM), rect(17, 28, 14, 16, FORM),
                    circle(44, 22, 6, FORM_DIM), rect(38, 29, 12, 14, FORM_DIM),
                    line(12, 50, 52, 50, ACCENT, 3)],
    "ui_veteran": [poly([(32, 16), (48, 40), (40, 40), (32, 28), (24, 40), (16, 40)], ACCENT)],
    "ui_elite": [poly([(32, 10), (48, 30), (40, 30), (32, 20), (24, 30), (16, 30)], ACCENT),
                 poly([(32, 30), (48, 50), (40, 50), (32, 40), (24, 50), (16, 50)], ACCENT)],
    "ui_objective": [circle(32, 32, 20, "none"),
                     path("M 32 32 m -20 0 a 20 20 0 1 0 40 0 a 20 20 0 1 0 -40 0", "none", ACCENT, 3),
                     circle(32, 32, 11, "none"),
                     path("M 32 32 m -11 0 a 11 11 0 1 0 22 0 a 11 11 0 1 0 -22 0", "none", ACCENT, 3),
                     circle(32, 32, 4, DANGER)],
    "ui_resource": [poly([(32, 10), (46, 28), (38, 52), (26, 52), (18, 28)], ACCENT),
                    poly([(32, 10), (46, 28), (32, 32), (18, 28)], "#F0C878")],
}


def write_icon(name, shapes):
    body = "".join(shapes)
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
        '<rect width="64" height="64" rx="10" fill="%s"/>%s</svg>' % (PLATE, body)
    )
    with open(os.path.join(OUT_DIR, name + ".svg"), "w") as handle:
        handle.write(svg)


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, shapes in sorted(ICONS.items()):
        write_icon(name, shapes)
    print("%d icons written to assets/icons" % len(ICONS))
