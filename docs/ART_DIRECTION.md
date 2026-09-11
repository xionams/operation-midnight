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

No normal maps. No metallic/roughness textures. Flat colour per material
slot, lit by one directional light. This is a deliberate ceiling: it
keeps the whole game one consistent stylisation rather than a mix of
detailed and flat assets.

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

- Chamfer large flat faces ~0.1m rather than leaving raw 90° edges —
  catches the light and stops structures reading as untextured boxes.
- No bevel small enough to vanish at gameplay zoom.
- Hard normals everywhere except cylinders (vents, barrels, tanks).
- Panel lines are **geometry or nothing** — never texture detail.

---

## 7. Lighting assumptions

One `DirectionalLight3D`, rotation `(-55°, -35°, 0)`, energy ~1.15.
Cold low sun, late dusk.

- Assets are authored for **top-down-ish light**. Upward faces carry the
  read; vertical faces fall into shadow.
- Shadows are currently **off** for mobile performance, so assets must
  read by silhouette and material contrast alone, not cast shadow.
- Never bake lighting into base colour beyond gentle top-face lightening.
- Emissive is the only self-lit element and is reserved for indicators,
  windows at night, and VFX.

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

## 9. Texture resolution rules

Android budget. Greyboxes use flat vertex/material colour and **no
textures at all**.

| Asset class | Max texture | Notes |
|---|---|---|
| Infantry | 256² | Shared atlas preferred |
| Vehicles | 512² | One texture per vehicle |
| Small structures | 512² | |
| Large structures | 1024² | Command HQ, Factory only |
| Environment props | 256² | Shared atlas |
| Terrain | 512² tiling | |
| UI icons | SVG (vector) | Rasterised by Godot at runtime |
| VFX | 128² | Additive, greyscale + tint |

Compression: VRAM (ETC2) on export. No mipmaps on UI.

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

Three environment variables turn off one visual layer each, so the cost
of an art change can be measured rather than argued about:

| Variable | Effect |
|---|---|
| `OM_NO_MODELS` | Units and structures fall back to primitive stand-ins |
| `OM_NO_SCENERY` | Skips pads, roads, rock faces and props |
| `OM_NO_VFX` | Suppresses every particle effect |

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
