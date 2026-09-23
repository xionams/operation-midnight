#!/usr/bin/env python3
"""The launcher icon, drawn rather than exported from anything.

Android wants PNGs at fixed sizes and Godot will not rasterise an SVG
into one, so this writes them directly - standard library only, same as
every other generator in this project.

The mark is the game's own palette: a dark plate, the amber chevron that
means "resource" everywhere else in the HUD, and a single faction-blue
bar. No text: at 48dp on a home screen a word is a smudge.
"""

import os
import struct
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "icons", "launcher")

PLATE = (0x12, 0x15, 0x18)
STEEL = (0x2E, 0x35, 0x3C)
AMBER = (0xE0, 0xA6, 0x3C)
BLUE = (0x2E, 0x6F, 0xD9)
CONCRETE = (0x8A, 0x85, 0x79)


def write_png(path, width, height, pixels):
    raw = b"".join(b"\x00" + bytes(row) for row in pixels)

    def chunk(tag, data):
        body = tag + data
        return (struct.pack(">I", len(data)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        handle.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        handle.write(chunk(b"IEND", b""))


def draw(size, transparent_ground=False):
    """Returns rows of RGB bytes."""
    rows = []
    unit = size / 64.0
    for y in range(size):
        row = bytearray()
        for x in range(size):
            u, v = x / unit, y / unit          # in a 64x64 design space
            colour = PLATE

            ## Rounded plate, unless this is an adaptive foreground where
            ## Android supplies its own background.
            if transparent_ground:
                colour = None

            inside_plate = True
            radius = 12.0
            for cx, cy in ((radius, radius), (64 - radius, radius),
                           (radius, 64 - radius), (64 - radius, 64 - radius)):
                if ((u < radius and v < radius) or (u > 64 - radius and v < radius)
                        or (u < radius and v > 64 - radius)
                        or (u > 64 - radius and v > 64 - radius)):
                    if (u - cx) ** 2 + (v - cy) ** 2 > radius ** 2:
                        if abs(u - cx) < radius and abs(v - cy) < radius:
                            inside_plate = False
            if not transparent_ground and not inside_plate:
                colour = (0, 0, 0)

            ## A low structure silhouette: base block and a tower.
            if 14 <= u <= 50 and 36 <= v <= 48:
                colour = STEEL
            if 20 <= u <= 34 and 22 <= v <= 36:
                colour = STEEL
            if 14 <= u <= 50 and 33 <= v <= 36:
                colour = CONCRETE          # the roof deck, as in game
            if 20 <= u <= 34 and 19 <= v <= 22:
                colour = CONCRETE

            ## Faction bar across the front of the base.
            if 17 <= u <= 34 and 42 <= v <= 46:
                colour = BLUE

            ## The amber chevron: the resource mark used across the HUD.
            cu, cv = u - 41.0, v - 26.0
            if 0 <= cv <= 13 and abs(cu) <= 9:
                edge = abs(cu)
                if cv >= edge and cv <= edge + 4.5:
                    colour = AMBER

            if colour is None:
                colour = PLATE
            row += bytes(colour)
        rows.append(row)
    return rows


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, size in [("icon_192.png", 192), ("adaptive_fg_432.png", 432),
                       ("adaptive_bg_432.png", 432), ("store_512.png", 512)]:
        if name == "adaptive_bg_432.png":
            rows = [bytearray(bytes(PLATE) * size) for _ in range(size)]
        else:
            rows = draw(size, transparent_ground=(name == "adaptive_fg_432.png"))
        write_png(os.path.join(OUT, name), size, size, rows)
        print("wrote", name, size, "x", size)
