#!/usr/bin/env python3
"""Generate the tiling textures the game's surfaces are painted with.

    ~/tools/blender/4.2/python/bin/python3.11 tools/build_textures.py

Run under Blender's bundled interpreter purely because it ships numpy;
nothing here touches bpy.

Why this exists
---------------
The battlefield was one 528m PlaneMesh filled with a single flat green,
and it is roughly 70% of every frame. No amount of work on the models
competes with that: a player looks at a field of one colour and reads
"unfinished", however good the thing standing on it is.

docs/ART_DIRECTION.md section 3 forbade textures outright - "flat colour
per material slot... a deliberate ceiling". That ceiling was the thing
holding the look back, so it is lifted here for terrain specifically.

Three textures, two sampling scales
-----------------------------------
One texture cannot do this job. Tiled small it visibly repeats; tiled
large it is mush. So the ground samples two:

  macro   - where the ground CHANGES: grass giving way to dry patches,
            worn dirt, bare rock. Tiled once per ~96m, so the player
            reads large regions rather than a pattern.
  detail  - grain, at ~8m. Carries the close-zoom read and breaks up the
            macro's smoothness. Near-neutral luminance so it modulates
            the macro colour rather than fighting it.
  normal  - the detail height as a normal map. Under a low sun this is
            what stops the ground being a mathematically flat surface,
            and it costs one sample.

All three tile seamlessly: the noise lattice wraps, so there is no seam
to hide.
"""

import os
import struct
import zlib

import numpy as np

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "assets", "textures")

MACRO_SIZE = 1024
DETAIL_SIZE = 512
SEED = 20260923

## Authored sRGB, because that is what a PNG albedo is and what Godot
## imports it as. These are the palette's terrain family, not new colours.
GRASS_DARK = (44, 66, 36)
GRASS = (66, 92, 50)
DRY = (104, 102, 60)
DIRT = (86, 71, 50)
ROCK = (98, 98, 92)


def tiling_noise(size, freq, rng):
    """One octave of value noise that wraps at the texture edge."""
    lattice = rng.random((freq, freq)).astype(np.float32)

    coords = np.arange(size, dtype=np.float32) * freq / size
    base = np.floor(coords).astype(np.int32)
    frac = coords - base
    ## Smoothstep, so octaves do not show the lattice as diamond creases.
    frac = frac * frac * (3.0 - 2.0 * frac)

    i0 = base % freq
    i1 = (base + 1) % freq

    v00 = lattice[np.ix_(i0, i0)]
    v01 = lattice[np.ix_(i0, i1)]
    v10 = lattice[np.ix_(i1, i0)]
    v11 = lattice[np.ix_(i1, i1)]

    fx = frac[None, :]
    fy = frac[:, None]
    top = v00 + (v01 - v00) * fx
    bottom = v10 + (v11 - v10) * fx
    return top + (bottom - top) * fy


def fbm(size, base_freq, octaves, rng, persistence=0.5):
    """Stacked octaves. Normalised to 0..1 so callers can reason about it."""
    total = np.zeros((size, size), dtype=np.float32)
    amplitude = 1.0
    total_amplitude = 0.0
    for octave in range(octaves):
        freq = base_freq * (2 ** octave)
        if freq > size:
            break
        total += tiling_noise(size, freq, rng) * amplitude
        total_amplitude += amplitude
        amplitude *= persistence
    total /= max(total_amplitude, 1e-6)
    span = total.max() - total.min()
    if span > 1e-6:
        total = (total - total.min()) / span
    return total


def blend(a, b, t):
    """Lerp two RGB tuples across a 0..1 field, returning HxWx3 float."""
    a = np.array(a, dtype=np.float32)
    b = np.array(b, dtype=np.float32)
    return a[None, None, :] + (b - a)[None, None, :] * t[:, :, None]


def write_png(path, rgb):
    """Minimal 8-bit RGB PNG writer.

    Written by hand rather than through an image library so the bytes are
    exactly the authored sRGB values - no colour management, no gamma
    guessing. The same care as tools/glb.py's srgb_to_linear, for the same
    reason: a silent colour-space conversion is very hard to see and very
    easy to ship.
    """
    data = np.clip(rgb, 0, 255).astype(np.uint8)
    height, width, _ = data.shape
    raw = b"".join(b"\x00" + data[y].tobytes() for y in range(height))

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xffffffff))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)
    return len(png)


def build_macro(rng):
    """Where the ground changes: regions, not pattern."""
    size = MACRO_SIZE
    ## Low frequency: these are the big shapes the player navigates by.
    wetness = fbm(size, 3, 4, rng)
    wear = fbm(size, 5, 5, rng)
    rockiness = fbm(size, 7, 4, rng)

    ## Grass varies in depth first.
    rgb = blend(GRASS_DARK, GRASS, wetness)

    ## Dry patches where it is least wet, with a soft threshold so the
    ## boundary reads as ground drying out rather than as a painted edge.
    dry_mask = np.clip((0.55 - wetness) * 2.6, 0.0, 1.0)
    rgb = rgb + (np.array(DRY, dtype=np.float32)[None, None, :] - rgb) \
        * dry_mask[:, :, None]

    ## Worn dirt where traffic would be - independent of wetness, so it
    ## cuts across the grass/dry boundary instead of tracing it.
    dirt_mask = np.clip((wear - 0.62) * 3.4, 0.0, 1.0)
    rgb = rgb + (np.array(DIRT, dtype=np.float32)[None, None, :] - rgb) \
        * dirt_mask[:, :, None]

    ## A little exposed rock, kept rare.
    rock_mask = np.clip((rockiness - 0.80) * 4.0, 0.0, 1.0)
    rgb = rgb + (np.array(ROCK, dtype=np.float32)[None, None, :] - rgb) \
        * rock_mask[:, :, None]
    return rgb


def build_detail(rng):
    """Grain. Centred near mid-grey so it multiplies without tinting."""
    size = DETAIL_SIZE
    grain = fbm(size, 8, 6, rng)
    ## A second, finer field keeps the close zoom from looking like soft
    ## blobs - this is what the player sees when they pinch all the way in.
    speckle = fbm(size, 32, 3, rng)
    height = 0.7 * grain + 0.3 * speckle

    ## Compress around the midpoint: the detail layer must not swing the
    ## macro colour far, or the ground reads as noise rather than surface.
    value = 0.5 + (height - 0.5) * 0.55
    grey = np.clip(value * 255.0, 0, 255)
    return np.stack([grey, grey, grey], axis=-1), height


def build_normal(height, strength=2.0):
    """Normal map from the detail height field, wrapping at the edges."""
    ## np.roll wraps, which is exactly right for a tiling texture.
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength

    ## Godot expects OpenGL-convention normal maps (+Y up).
    nx = -dx
    ny = dy
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / length, ny / length, nz / length

    return np.stack([(nx * 0.5 + 0.5) * 255.0,
                     (ny * 0.5 + 0.5) * 255.0,
                     (nz * 0.5 + 0.5) * 255.0], axis=-1)


SURFACE_SIZE = 512


def build_surface(rng):
    """Panel seams, grime and wear for every structure and vehicle.

    ONE texture for the whole game, applied triplanar. The greyboxes have
    no UVs and unwrapping 42 models by hand to paint each one is not the
    job this pass is doing; triplanar projects from three world axes and
    needs no UVs at all, which suits box-shaped assets almost perfectly.

    Authored near-white because Godot MULTIPLIES albedo_texture into
    albedo_color. That is what lets one greyscale sheet sit on every
    material slot - Hull, Faction, Concrete - and darken its seams without
    touching its colour. Anything with hue in it would tint all of them.

    Returns (rgb, height).
    """
    size = SURFACE_SIZE
    axis = np.arange(size, dtype=np.float32)
    xs = axis[None, :].repeat(size, axis=0)
    ys = axis[:, None].repeat(size, axis=1)

    ## Panel seams. Irregular spacing, because an even grid reads as
    ## graph paper; these are plate joins, not a pattern.
    seams = np.zeros((size, size), dtype=np.float32)
    for coords in (xs, ys):
        for period in (64.0, 128.0):
            phase = rng.random() * period
            d = np.abs(((coords + phase) % period) - period * 0.5)
            ## A seam is a thin dark line with a soft shoulder.
            seams = np.maximum(seams, np.clip(1.0 - d / 1.6, 0.0, 1.0))

    ## Broad grime, so large faces are not one flat value.
    grime = fbm(size, 4, 5, rng)
    ## Fine wear along the grain of the panels.
    wear = fbm(size, 24, 3, rng)

    ## Start just off white and take light away. Never add: this is a
    ## multiplier, and values above 1 would brighten a material past the
    ## colour the art direction assigned it.
    value = np.full((size, size), 1.0, dtype=np.float32)
    value -= 0.22 * seams
    value -= 0.10 * (1.0 - grime)
    value -= 0.06 * wear
    value = np.clip(value, 0.0, 1.0)

    grey = value * 255.0
    ## The height field for the normal map is the seam mask: the seams are
    ## the only thing here that is actually geometry-like relief.
    height = 1.0 - (0.8 * seams + 0.2 * wear)
    return np.stack([grey, grey, grey], axis=-1), height


def main():
    out = os.path.abspath(OUT_DIR)
    os.makedirs(out, exist_ok=True)
    rng = np.random.default_rng(SEED)

    macro = build_macro(rng)
    detail, height = build_detail(rng)
    normal = build_normal(height)
    surface, surface_height = build_surface(rng)
    surface_normal = build_normal(surface_height, strength=3.0)

    for name, image in [("ground_macro", macro),
                        ("ground_detail", detail),
                        ("ground_normal", normal),
                        ("surface_detail", surface),
                        ("surface_normal", surface_normal)]:
        path = os.path.join(out, name + ".png")
        size = write_png(path, image)
        print("wrote %-28s %4dx%-4d %6.1f KiB"
              % (name + ".png", image.shape[1], image.shape[0], size / 1024.0))


if __name__ == "__main__":
    main()
