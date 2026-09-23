# Operation Midnight — Art Direction

One visual language, applied everywhere. This document is the authority.
If an asset disagrees with this file, the asset is wrong.

Read this before making, generating or accepting any asset. Every
generated asset must be produced with the style block in §11 verbatim.

---

## 1. The one-line brief

> A modern mechanised battalion fighting at dusk in a cold industrial
> landscape. Serious, grounded, military. Not science fiction.

Reference feel: Wargame / Act of Aggression / Company of Heroes 2 read
from above, simplified for a phone screen.

**Never:** energy weapons, glowing sci-fi trim, alien geometry, bright
saturated primaries, cartoon proportions, fantasy silhouettes, chrome.

---

## 2. Palette

Everything is built from a narrow, desaturated ground set. Colour is a
gameplay signal, not decoration — the only saturated colour on screen is
faction marking, resources, and danger.

### Ground set (structures, vehicles, terrain)

| Role | Hex | Use |
|---|---|---|
| Gunmetal | `#3A3F45` | Primary structure hull, heavy armour |
| Steel | `#4A5058` | Secondary panels, towers |
| Olive drab | `#4A5138` | Vehicle hulls, infantry webbing |
| Field green | `#3C4430` | Darker vehicle panels |
| Concrete | `#8A8579` | Walls, pads, roads, barriers |
| Concrete dark | `#5E5B53` | Concrete in shadow, kerbs |
| Rust | `#6E4A2E` | Refinery, industrial trim, wear |
| Sand | `#9A8E6E` | Terrain, dirt roads |
| Deep shadow | `#22262A` | Recesses, tracks, under-hull |

### Signal set (never used decoratively)

| Role | Hex | Use |
|---|---|---|
| Player blue | `#2E6FD9` | Player faction markings |
| Enemy red | `#D9342E` | Enemy faction markings |
| Neutral sand | `#D9C87A` | Unowned / capturable structures |
| Resource amber | `#E0A63C` | Ore, harvester cargo, credits |
| Power cyan | `#4FC3C7` | Power indicators only |
| Warning orange | `#E07A2C` | Fire, damage, low power |
| Selection green | `#3ADE5A` | Selection rings, move orders |

**Rule:** if a colour is not in these two tables, it does not appear.

---

## 3. Materials

Four materials cover the entire game. More than this reads as noise at
gameplay zoom and costs draw calls on Android.

| Name | Roughness | Metallic | Notes |
|---|---|---|---|
| `Hull` | 0.75 | 0.0 | Painted metal. The default. |
| `Dark` | 0.85 | 0.0 | Recesses, tracks, tyres, shadow mass |
| `Metal` | 0.45 | 0.8 | Bare/worn metal, barrels, pipes |
| `Faction` | 0.60 | 0.0 | **Recoloured at runtime.** See §8 |
| `Glass` | 0.15 | 0.0 | Windows, optics. Dark, barely lit |
| `Emissive` | — | — | Unshaded. Lights, indicators, VFX only |

Flat colour per material slot remains the base. **That ceiling has been
lifted for detail only** — see section 9. Colour is still assigned per
slot from the palette; what sits on top is one shared greyscale sheet of
panel seams, grime and wear, multiplied in. No per-asset texture art, so
the "consistent stylisation rather than a mix" this rule was protecting
still holds: every surface in the game wears the same sheet.

The original rule said "no normal maps, no textures, this is a deliberate
ceiling". It was written when the alternative was hand-painting 42
assets. It was also the single thing making the game read as untextured
boxes, which is why it changed.

---

## 4. Shape language

- **Boxy, chamfered, industrial.** Rectangular masses with cut corners.
- **Silhouette first.** An asset must be identifiable as a black
  silhouette at 96px. If it is not, the silhouette is wrong — fix the
  shape, not the texture.
- **One dominant read per asset.** Refinery = the hopper. Radar = the
  dish. Tank = the turret. Everything else is supporting mass.
- **Exaggerate the identifying feature by ~20–30%** over realistic
  proportion. A real radar dish is too small to read from the camera.
- **Vertical punctuation.** Each structure gets one tall element (vent,
  mast, chimney, dish) so bases read as skylines, not as a flat grid.
- **No thin geometry.** Nothing thinner than 0.15m; it aliases badly on
  mobile and disappears at zoom.

---

## 5. Scale (metres — authoritative)

The camera sits ~38m out. These are tuned for that read, and they are
the sizes already used by gameplay (`body_size` in `config/*.tres`).
**Model dimensions must match `body_size` exactly** or selection,
placement and collision will disagree with the art.

| Class | Footprint | Height |
|---|---|---|
| Infantry | 0.9 × 0.9 | 1.8 |
| Light vehicle | 2.0–2.4 wide | 1.2–1.4 |
| Heavy vehicle | 2.6–3.0 wide | 1.5–1.7 |
| Small structure | 5 × 5 | 3.2–4.5 |
| Large structure | 7–9 × 7–9 | 3.6–5.0 |
| Tower | 2.6–3.4 | 4.2–5.5 |
| Wall segment | 2 × 2 | 3.0 |

Infantry are deliberately **oversized** relative to vehicles (a real
soldier beside a real tank is nearly invisible from above). Accept the
inaccuracy; readability wins.

---

## 6. Edge treatment

- Chamfer rather than leaving raw 90° edges — catches the light and
  stops structures reading as untextured boxes.
- No bevel small enough to vanish at gameplay zoom.
- Hard normals everywhere except cylinders (vents, barrels, tanks).
- Panel lines are **geometry or nothing** — never texture detail.

Applied by `tools/mesh_refine.py`, not by hand. Width is 3% of each
object's smallest extent, clamped to 10–100mm, because these assets span
a 0.18m gun barrel and a 12m war factory and one fixed width cannot serve
both. That puts a 5m structure at the 0.1m this section asks for. One
segment, not two: a second segment doubles the added geometry for a
rounding nobody resolves at a 14–45m camera.

A first attempt used 1.2% clamped to 30mm and produced a bevel that was
real in the mesh and invisible on screen — about one pixel at a 40m
camera. If a chamfer cannot be seen at gameplay zoom it is pure cost;
either widen it to the figure above or gate it out entirely.

Assets under 2m in their largest dimension are **not bevelled at all** —
that is the "vanishes at gameplay zoom" rule above, made numeric. It
matters most for infantry, which are the one class that appears 120 at a
time; bevelling them cost 3.8× the triangles for nothing visible.

The same pass bakes ambient occlusion into vertex colours (`COLOR_0`),
which is what darkens the contact where a turret meets a hull or a
cooling tower meets a roof. Vertex colours rather than a texture: no UV
atlas, no VRAM, and nothing to stream on a phone.

---

## 7. Lighting assumptions

One `DirectionalLight3D`, rotation `(-48°, -35°, 0)`, energy ~1.35, warm
(`1.0, 0.957, 0.882`). Cold low sun, late dusk.

- Assets are authored for **top-down-ish light**. Upward faces carry the
  read; vertical faces fall into shadow.
- Shadows are **on**. 2048 map, single orthogonal split, 110m — which is
  what RTSCamera can see at `max_zoom` 45 and no further. An asset may
  now rely on cast shadow to sit on the ground rather than float.
- Ambient comes from a `ProceduralSky`, so it has direction: up-facing
  surfaces catch cool daylight, down-facing ones warm ground bounce. The
  sky is never drawn — the background stays dark so fog of war keeps the
  area past the map edge dark. It exists purely as a light source.
- Filmic tonemapping, exposure 1.35.
- Never bake lighting into base colour beyond gentle top-face lightening.
  Baked *occlusion* is fine and expected — see section 6.
- Emissive is the only self-lit element and is reserved for indicators,
  windows at night, and VFX.

The sun angle was lowered from -55° when shadows were turned on: a high
sun puts every shadow directly under its caster, which from this camera
reads as no shadow at all.

---

## 8. Faction marking rules

Faction identity must be readable **instantly, at full zoom-out, in
peripheral vision.** This is the single most important readability rule
in the game.

1. Every unit and structure carries a material slot literally named
   `Faction`. It is recoloured at runtime — player blue, enemy red,
   neutral sand. Never bake faction colour into the mesh.
2. Faction colour covers **8–15% of the visible surface.** Less is
   unreadable; more looks like a toy.
3. Placement is consistent by class:
   - **Structures:** a roof band across the widest face, plus the
     vertical element's cap.
   - **Vehicles:** turret/cab flank panels and a roof chevron.
   - **Infantry:** helmet and shoulder.
4. Faction colour goes on **upward-facing surfaces wherever possible** —
   that is what the camera sees.
5. Neutral/capturable structures use neutral sand until captured, then
   adopt the capturing faction's colour through the same slot.

---

## 9. Texture rules

Five textures for the entire game, all generated by
`tools/build_textures.py`, all tiling. There is no per-asset texture art
and there is no UV layout anywhere in the project.

| Texture | Size | Used by | Tile |
|---|---|---|---|
| `ground_macro` | 1024² | Battlefield | ~0.44 × map size |
| `ground_detail` | 512² | Battlefield | 8m |
| `ground_normal` | 512² | Battlefield | 8m |
| `surface_detail` | 512² | Structures, vehicles, concrete | 8m models / 12m pads |
| `surface_normal` | 512² | as above | as above |

**Two scales, always.** One texture cannot surface a 528m plane: tiled
small it visibly repeats, tiled large it is mush. The ground samples a
macro layer for *where the ground changes* — grass into dry patch into
worn dirt — and a detail layer for grain. The macro scale is tied to map
size so a bigger map reads as the same handful of regions, not a denser
pattern.

**Greyscale, multiplied.** `surface_detail` is authored near-white and
multiplied into `albedo_color`, which is what lets one sheet darken the
seams of a blue Faction band, a grey Hull and a concrete pad while
leaving each its own colour. Any hue in that sheet would tint all three.
Nothing in it goes above 1.0 — it only ever takes light away, never
brightens a material past the colour the palette assigned it.

**Triplanar, because there are no UVs.** The models are generated and
carry no UV layout. Triplanar projects from three world axes and blends
by normal, which on box-shaped assets is very nearly a correct unwrap for
free. Local-space, not world: world projection slides the seams across a
tank as it drives, which reads as the hull being transparent.

**Panel seams are 1–2m.** A first pass used 0.5m and read as brickwork.
On this camera the failure mode of a detail texture is looking like
masonry — if the seams resolve as a regular grid, they are too dense.

Rocks, trees and sandbags stay flat: panel seams on a boulder look like a
mistake, and they are small enough on screen that flat colour costs
nothing. Only poured concrete and asphalt take the sheet.

---

## 10. Readability rules by class

### Buildings
- Footprint must match `body_size` so the placement grid tells the truth.
- The tall element goes at the **rear** of the footprint so it never
  occludes the faction band or the health bar.
- Entrances/doors face **-Z** (see §12) so the rally point reads.
- Damage states darken the hull and add smoke; they never change
  silhouette (players track buildings by shape).

### Vehicles
- Turret is a separate named node (`Turret`) pivoting on Y, so it can be
  aimed later without touching the hull.
- Tracks/wheels are `Dark` and sit below the hull line — grounds the
  vehicle without adding polygons.
- Barrel length is exaggerated; it is the primary role cue at distance.
- Hull is wider at the rear than the front — gives an unambiguous facing
  read from directly above.

### Infantry
- One squad = one figure (gameplay treats a squad as a unit).
- Blocky, shoulders wider than hips, helmet clearly separate from head.
- Weapon is a held horizontal bar — it is the role cue (rifle short,
  launcher long and thick, engineer carries a toolbox, spy carries
  nothing).
- Slight forward lean so facing is readable from above.

---

## 11. Style block for generated assets

Paste this **verbatim** into every image/asset generation prompt. Do not
paraphrase it per asset — that is how a style drifts.

```
Near-future military RTS asset, stylized realistic low-poly, dark
serious atmosphere, modern military (NOT sci-fi, no energy weapons, no
glowing trim). Desaturated palette: gunmetal #3A3F45, steel #4A5058,
olive drab #4A5138, concrete #8A8579, rust #6E4A2E. Flat matte painted
metal, no chrome, no normal maps. Boxy chamfered industrial shape
language with an exaggerated readable silhouette. Lit by a single cold
low dusk sun from above. Rendered for a top-down isometric RTS camera
roughly 38 metres out, optimized for Android mobile. Strong faction
colour marking on upward-facing surfaces only.
```

---

## 12. Technical conventions (non-negotiable)

| Convention | Value |
|---|---|
| Units | Metres, 1.0 = 1m |
| Up axis | +Y |
| Forward axis | **-Z** (Godot convention) |
| Pivot/origin | Ground centre — geometry sits at y ≥ 0 |
| Winding | Counter-clockwise, normals out |
| Export format | `.glb` (glTF 2.0 binary) |
| Naming | `snake_case.glb`, matching the manifest `id` |
| Node names | Meaningful: `Hull`, `Turret`, `Barrel`, `Dish` |
| Material names | Exactly `Hull`/`Dark`/`Metal`/`Faction`/`Glass` |

**Pivot matters.** Gameplay places objects at ground level and builds
selection rings and health bars from `body_size`. A model whose origin
is at its centre will float or sink and cannot be swapped in blind.

---

## 13. Triangle budget (Android)

| Class | Budget | Greybox target |
|---|---|---|
| Infantry | 400 | ~120 |
| Light vehicle | 900 | ~250 |
| Heavy vehicle | 1,400 | ~350 |
| Small structure | 800 | ~200 |
| Large structure | 1,800 | ~400 |
| Tower / wall | 400 | ~120 |
| Environment prop | 250 | ~60 |

Whole-screen target: a 120-unit battle plus two bases must stay under
~250k triangles. Greyboxes sit far under budget on purpose — the budget
is headroom for the final art pass, not a target to fill now.

After the bevel pass in `tools/mesh_refine.py` all 42 models total 25,768
triangles (from 8,756, ×2.94). Per class, measured:

| Asset | Tris | Class budget |
|---|---|---|
| Infantry (rifle, engineer, spy) | 304 | 400 |
| AT squad | 348 | 400 |
| Scout vehicle | 896 | 900 |
| Main battle tank | 780 | 1,400 |
| Harvester | 1,256 | 1,400 |
| Assault vehicle | 1,252 | 900 ⚠ |
| Artillery vehicle | 1,548 | 1,400 ⚠ |
| Command HQ | 1,324 | 1,800 |
| War factory | 1,132 | 1,800 |
| Barracks | 1,212 | 1,800 |

Two vehicles sit over their class budget and are knowingly left there:
both are single-unit-cap or low-count units, the whole-screen figure is
what actually constrains the frame, and the 120-unit stress test did not
move when the triangle count tripled (51.4 FPS against 50.1 before) —
this game is fill-rate bound, not vertex bound.

No LODs at MVP. Revisit only if the 120-unit stress test regresses.

---

## 14. What "done" means for an asset

1. Correct dimensions from §5, matching `body_size`.
2. Origin at ground centre, forward -Z.
3. Uses only §3 materials, with a `Faction` slot where §8 requires one.
4. Reads as a silhouette at 96px.
5. Inside its §13 triangle budget.
6. Registered in `assets/manifest.json` with honest status.
7. Imports into Godot with no errors and no scale correction.

---

## 15. Performance switches

Four environment variables turn off one visual layer each, so the cost
of an art change can be measured rather than argued about:

| Variable | Effect |
|---|---|
| `OM_NO_MODELS` | Units and structures fall back to primitive stand-ins |
| `OM_NO_SCENERY` | Skips pads, roads, rock faces and props |
| `OM_NO_VFX` | Suppresses every particle effect |
| `OM_NO_SHADOWS` | Sun casts no shadow |
| `OM_NO_DETAIL` | No detail textures; flat colour per slot, as before §9 |

`OM_NO_DETAIL` measured at 120 units: **51.3 FPS on, 55.1 off.** Triplanar
is three samples per map and the models take two maps, so six per
fragment. That is ~4 FPS on desktop; a phone GPU is a different budget
and this switch exists so the cost can be established on device rather
than guessed at.

`OM_NO_SHADOWS` measured, at 2048 and a 110m shadow distance:

| Units | Shadows on | Shadows off |
|---|---|---|
| 40 | 60.1 | 60.0 |
| 80 | 60.1 | 60.1 |
| 120 | 50.1 | 56.8 |

Shadows are free until the unit count gets high, and the cost is fill
rate rather than draw calls - dropping the map from 4096 to 2048
recovered most of it while 1024 put acne stripes across the base pads.

They exist because the first integration of this asset pass cost ~19 FPS
at 120 units and two plausible-sounding explanations (particle count,
uncached materials) both turned out to be wrong. Measured with these:

    models + scenery + VFX off   60.0 / 60.0 / 59.7 FPS   (40 / 80 / 120 units)
    models off only              59.8 / 58.8 / 53.9
    everything on, first cut     52.4 / 47.4 / 40.9
    everything on, after fix     59.7 / 60.0 / 59.4

The cost was draw calls, not triangles: at 120 units the whole scene is
about 30k triangles, but each unit had grown from two surfaces sharing
one material to six. Merging `Metal`, `Glass` and `Amber` into existing
slots on unit-class models only - structures keep their full set, there
being a dozen of them rather than a hundred - recovered all of it.

**Rule for the next art pass: a unit model gets at most three material
slots.** Structures may use the full set.
