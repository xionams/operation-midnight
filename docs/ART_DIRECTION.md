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
| `Hull` | 0.75 | 0.0 | Painted metal. The default, **recoloured per asset**. |
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

**`Hull` is recoloured per asset**, from this same palette — see
`UNIT_HULL_OVERRIDE` and `BUILDING_HULL_OVERRIDE` in
`tools/asset_specs.py`. Every structure wearing one gunmetal made a base
read as a single slate-grey mass: at gameplay zoom you could not tell a
refinery from a barracks without reading its roof fitting, so silhouette
was doing all the work alone. A refinery is ore-stained rust, a barracks
olive, a tech centre pale concrete. The command HQ keeps gunmetal — it is
the flagship, and the colour the rest of the base is read against.

These are the existing palette entries redistributed, not new colours,
and all muted: faction colour is the one thing on screen allowed to be
saturated (§8).

---

## 4. Shape language

**Vehicles are recognised by their running gear.** `tracks()` is a band,
four road wheels, a larger sprocket and idler at each end, and a fender
overhanging the top. The wheels sit slightly proud so the sun picks out a
row of highlights along the hull side — at 40m the individual wheels are
not resolvable, but the *rhythm* is, and that rhythm is what says
"tracked vehicle" rather than "box on the ground". Five wheels was tried;
the fifth is not distinguishable, because the eye reads the rhythm, not
the count.

`wheels()` gives a lighter hub proud of a dark tyre — without it a wheel
is a black disc and reads as a hole in the vehicle.

`stowage()` straps crates and a rolled tarp to a hull. Clutter is what
separates a vehicle in service from a showroom model, and it breaks the
straight line of a deck seen from above, which is the view this game is
played from.

Asymmetry tells the player which way a turret faces when its gun points
at the camera — hence the offset commander's cupola on the tank. A
mantlet where the barrel meets the turret face stops the gun looking like
a stick pushed into a box.

**Height is what reads, not detail.** The structures already carried
plenty of detail — gantry cranes, roll-up doors, vent banks, pipe runs —
and almost none of it registered, because at the 14–45m camera a 0.3m
greeble is one or two pixels. What was missing was never more surface
detail; it was something that breaks the roofline hard enough to be seen
as an *outline*.

`stack()` and `lattice_mast()` in `tools/asset_specs.py` are the shared
vocabulary for that. A chimney is two cylinders and a band, and it
changes the shape a player recognises a building by — the power plant was
3.2m tall on a 5m footprint and read as a shed until it got two.

Give every structure at least one vertical that clears its roof by half
its own height, and make the arrangement asymmetric where two buildings
would otherwise share an outline: the refinery's flare stack sits
opposite its silo so it cannot be confused with the war factory.

Stacks carry an amber hazard band near the top. That is the one place a
saturated accent is allowed on a structure that is not faction colour.

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

Only edges sharper than **65°** are bevelled, which is "hard normals
everywhere except cylinders" made numeric: a box corner is 90° and
bevels, a six-sided road wheel's side edges are 60° and do not.

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

**Panels are laid as irregular courses, never a grid.** Rows of varying
height, each divided into cells of varying width with its own horizontal
offset, so vertical seams do not line up between rows. The first version
used two fixed periods and a `max()` — a perfect grid, which on a
building reads as bathroom tile and was the most artificial thing on
screen.

**Every panel carries its own slightly different value** (0.88–1.0). This
matters more than the seams: a large flat face of one tone reads as
plastic however well it is lit, and the same face broken into plates
differing by a few percent reads as fabricated metal. Only the seams get
relief in the normal map — panel shade is paint, not geometry, and
embossing every plate looks like quilting.

Courses tile because each row's widths sum exactly to the texture size,
and likewise the heights.

Rocks, trees and sandbags stay flat: panel seams on a boulder look like a
mistake, and they are small enough on screen that flat colour costs
nothing. Only poured concrete and asphalt take the sheet.

---

## 9b. Generated art vs third-party art

The line is **gameplay-bearing vs scenery**, not "ours vs theirs".

| | Source | Why |
|---|---|---|
| Units, structures, defences | Generated from `tools/asset_specs.py` | Carry the runtime-recoloured `Faction` slot (§8) and must match the `body_size` that selection rings, health bars and placement footprints derive from (§5) |
| Trees, rocks, cliffs, bushes, grass, logs, fences | Kenney Nature Kit, CC0 | Carry no faction, block nothing the player reasons about, have no dimension contract with gameplay |
| Military props — barriers, sandbags, drums, crates, debris, masts | Generated | Military dressing; reads as part of the same world as the structures |

The spec language is boxes and cylinders. That is adequate for a war
factory, whose real shape is close to a box. It is not adequate for a
tree: ours was three stacked cylinders, and no lighting or texture pass
makes a cone on a stick read as a tree.

**Imported art is re-palettised, never used as shipped.** Kenney's kit is
authored in a deliberate teal-and-coral scheme — its leaves are genuinely
cyan, not a broken import. `Scenery.NATURE_PALETTE` maps it into §2's
colours by **material name** (`leafsDark`, `woodBark`, `dirt`), so one
small table re-skins the whole pack including anything added later. Doing
it by colour would need an entry per shade and would silently miss any
that did not match exactly.

That remap is also what stops the props reading as off-the-shelf art
sitting on our terrain. Flowers are the one exception that keeps its hue:
they are the only saturated thing out there and are what stops a meadow
being one green mass — muted, so they never compete with faction colour,
which is the one thing on screen that has to win.

Attribution and the full rationale: `assets/models/nature/CREDITS.md`.

---

## 9c. Density

A map is dressed or it is empty, and no amount of lighting fixes empty.
The first pass scattered **90 props across a 220m map** — one object per
540m² — and read as a flat field with some cones in it.

- **~520 scattered props**, placed in **clusters**, not evenly. Vegetation
  grows in stands and rock gathers where rock is; placement picks centres
  and spreads members around them with a normal distribution, so a stand
  has a dense middle and thins at its edge.
- Cluster types carry their own kind lists — `wood`, `copse`, `scree`,
  `meadow`, `ruin` — so a place looks like somewhere rather than like a
  random draw from every prop in the game.
- **~6,200 ground-cover tufts** as `MultiMesh`. There was no grass
  geometry in the project at all before this; "grass" was a colour in a
  texture.

Ground cover is chunked **12×12**, because Godot frustum-culls a
MultiMesh by its whole bounding box and never per instance — one
MultiMesh spanning the map would draw every tuft on it, including those
behind the camera. At this chunk size roughly 4.3k triangles sit in each
chunk and the camera holds only a few.

Cover answers a different question to a prop: a tree must not grow inside
another tree, but grass grows around the foot of one. Treating every prop
as an obstacle rejected over half the tufts. `_is_clear_for_cover`
respects only clearances of 4m or more — bases, roads, ore fields — and
ignores the per-prop ones.

Measured at 120 units: **49.2 FPS**, against 51.3 before the props and
grass. Grass does not cast shadows; thousands of extra shadow-map draws
for a shadow the size of a leaf is not a trade worth making.

---

## 9d. What the ground remembers

Everything in the VFX layer is momentary — a flash, a plume, a shake — so
ten minutes into a match the terrain looked exactly as it did at the
start. A war game whose ground never records that anything happened reads
as a diorama, however well it is lit.

`scripts/vfx/ground_marks.gd` keeps two layers:

- **Scorch**, where things exploded: 0.9m for a shell impact, 1.8m for a
  vehicle, 4.2m for a structure — so a razed base still reads as a razed
  base an hour later.
- **Ruts**, where armour drove. A stamp every 2.2m, laid 2.2× that long
  so consecutive stamps overlap; the texture fades to nothing at both
  ends, so the overlap is what carries the join. At 1.7× the trail read
  as a dashed line. Ruts follow the direction actually *travelled*, not
  the hull facing — a vehicle mid-turn leaves marks along its path, not
  along wherever it happens to point.

Infantry leave nothing: boots do not rut a field at this scale, and at
120 units the trails would be the only thing on screen.

Each layer has its own ring buffer, because they fill at completely
different rates — a burn happens when something dies, a rut every couple
of metres a vehicle drives. Sharing one buffer would let a single
harvester's commute erase the record of a battle.

- **They never fade.** A burn that tidies itself away after fifteen
  seconds is just another particle effect. The point is that the ground
  remembers.
- **One `MultiMesh` for every mark on the map**, so the whole record is
  one draw call rather than one per crater. That is what makes permanence
  affordable.
- **Ring buffers cap them**: 96 burns, 160 ruts. The oldest is
  overwritten, which bounds the cost exactly while leaving the ground
  that saw the most traffic the most marked.

**The cap is a fill-rate decision, not a memory one.** Every mark is a
large alpha-blended quad and the layer's AABB spans the map, so none are
ever culled. The rut layer started at 420 and cost **10 FPS at 120
units** — more than shadows, more than the entire effects layer. At 160,
with the stamp spacing widened from 1.4m to 2.2m, it is free. Population
is the only lever that matters for a decal layer.
- **Each mark is randomly spun.** Without it a cluster reads as the same
  stamp repeated rather than as separate craters.
- **They obey fog.** A mark is evidence something happened, so it must
  respect the shroud exactly as the thing that made it does — otherwise a
  burn glimpsed through the fog reports a battle the player has not
  earned the right to know about.

Flat quads rather than Godot `Decal` nodes: the terrain is a flat plane,
so projection buys nothing and costs fill rate on a phone.

Two things worth keeping in mind for any future ground decal:

**Alpha blending, not `blend_mul`.** Multiply is the physically correct
model — soot takes light away rather than replacing it, and it would let
one texture read correctly on grass and on concrete. It rendered every
mark as a visible dark rectangle: the transparent margin of each quad
still washed the ground. Whatever Godot's mul blending does with a white
`ALBEDO`, it is not "leave the destination alone".

**Lit, not unshaded.** Unshaded soot stays bright inside a building's
shadow and floats off the surface it is meant to be part of.

**`Basis.scaled()` scales in WORLD axes, not local.** It scales the
basis's rows, so a non-uniform scale applied that way ignores the mark's
own rotation entirely — every rut came out `width` across world X and 1.0
deep in world Z whatever direction it ran, which is a sliver. Compose
with `Basis.from_scale()` on the right instead. The scorch layer never
showed the bug because its scale is uniform, which is exactly the kind of
thing that hides it until a second caller appears.

---

## 9e. Combat readability

**Damage states.** A fight has to be readable without selecting anything.
Thresholds are the same for units and structures — smoke below 60%
health, fire as well below 30% — so "that one is in trouble" means one
thing wherever the player looks. Repair clears it: a vehicle that keeps
burning after being healed teaches players to distrust the effect.

Infantry get none. A smoke column on a 1.7m figure reads as a bonfire,
and at 120 units it would be the only thing on screen.

Unit plumes are capped at 18 concurrently, like `Wreckage`'s 24 wrecks
and `GroundMarks`' 96 marks. One particle system per damaged vehicle is
worth having; the unbounded version is not.

> `BuildingBase._refresh_damage_visual` returned early on a null `_body`,
> which is the case for **every structure that uses a model** — so
> structure damage states were dead from the moment models landed until
> this pass. Any state that depends on the primitive stand-in's fields is
> dead code in the shipping game.

**Tracers travel.** The original drew a full-length cylinder from muzzle
to target in a single frame and faded it. That reads as a laser however
short the fade, because there is never a moment where the round is
*between* the two. A short streak moving at 200 m/s reads as a round.

The damage is still hitscan and lands instantly — only the *picture* of
the impact waits for the streak to arrive, so a shell never explodes
before its tracer reaches the target.

**Concurrent tracer count is the frame budget's concern, not per-tracer
cost.** A 0.30s flight time is twice the old beam's lifetime and cost ~6
FPS at 120 units in contact. 200 m/s halves the population and returns
almost all of it. One shared mesh and one shared material per tracer
colour, with the node scaled rather than the mesh rebuilt — the old
version allocated a fresh `CylinderMesh` *and* `StandardMaterial3D` for
every shot fired.

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

After the bevel and running-gear passes, all 42 models total **26,194**
triangles. Per class, measured:

| Asset | Tris | Class budget | |
|---|---|---|---|
| Infantry (rifle, engineer, spy) | 304 | 400 | ✓ |
| AT squad | 348 | 400 | ✓ |
| Scout vehicle | 856 | 900 | ✓ |
| Harvester | 1,192 | 1,400 | ✓ |
| Assault vehicle | 1,332 | 900 | ⚠ |
| Main battle tank | 1,760 | 1,400 | ⚠ |
| Artillery vehicle | 1,892 | 1,400 | ⚠ |
| Command HQ | 1,148 | 1,800 | ✓ |
| War factory | 1,404 | 1,800 | ✓ |
| Barracks | 1,252 | 1,800 | ✓ |
| Power plant | 1,312 | 1,800 | ✓ |
| Refinery | 1,016 | 1,800 | ✓ |

**The three vehicles over budget are knowingly left there.** The class
budgets were set before anything had been measured, and what has been
measured since says they are the wrong constraint:

- Triangle count is not what costs frames here. The models tripled in the
  bevel pass and the 120-unit stress test did not move. The same test
  loses ~9 FPS to the effects layer and ~5 to shadows — this game is fill
  rate bound.
- The whole-screen figure is the one that constrains a frame, and at 120
  units of the heaviest vehicle plus two bases it is still inside ~250k.
- Infantry, the one class that genuinely appears 120 at a time, is
  comfortably under.

Treat the per-class column as a smell test rather than a limit, and the
120-unit stress test as the actual gate.

**Bevelling cylinders is nearly pure waste.** The angle between adjacent
side faces of an n-sided prism is 360/n — 60° for a six-sided road wheel,
45° for an eight-sided barrel — so a 30° bevel limit chamfered every one
of them, for a rounding well under a pixel. Raising the limit to 65°
(§6) took the whole model set *down* from 27,496 to 26,194 triangles at
the same time as the running gear was added.

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
| `OM_NO_VFX` | Suppresses every particle effect, and ground marks |
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

---

## 16. Imported rigged characters — evaluated, not adopted

Kenney's **Animated Characters** packs are CC0 and rigged, so infantry
animation was evaluated properly rather than argued about.
`tools/convert_character.py` is the working pipeline and
`tests/skinned_cost_test.gd` is the measurement.

**Cost is not the problem.** 120 skinned, animated characters cost
**+1.07 ms/frame** against 120 static generated ones (6.19 → 7.26 ms);
at 360 it is +2.40 ms. In the real scene at ~48 FPS that is roughly 2–3
FPS. Affordable.

**The model is the problem.** Kenney's character is a smooth, featureless
mannequin: no rifle, no webbing, no boots, no helmet. Our generated
soldier is 304 triangles of boxes and it reads as a *soldier* — it
carries a weapon and has kit. Swapping to the import would make infantry
**look worse while moving better**, at 5× the triangles.

So the conclusion is the opposite of the one the search started with:
**the animation is the prize, not the mesh.** The right shape of this
work is a rig on our own geometry with these clips retargeted onto it,
not a wholesale model swap. Our soldiers have no rig, so that is the
piece of work to cost next.

Four things the pipeline had to solve, all of which will recur for any
rigged import:

- **The rig is IK-driven.** Its clips key control bones (`LeftFootIK`,
  `KneeCtrl`, `HeelRoll`) and the deform bones follow through Blender
  constraints. glTF has no constraints, so an unbaked export produces
  animations that *play* — the time advances, the player reports itself
  running — while every deform bone sits in bind pose and the character
  T-poses through the whole clip. Bake with visual keying.
- **The body material exports with base-colour alpha 0**, because the
  pack skins by a loose PNG the FBX never references. Exported as-is the
  soldier is completely invisible and only the bolted-on faction geometry
  renders.
- **Palette colours need `srgb_to_linear`.** Blender's Base Color input
  is linear, same as glTF `baseColorFactor`. OLIVE dropped straight in
  arrived in Godot as `(0.57, 0.60, 0.51)` — a pale grey-green. The same
  trap `tools/glb.py` has guarded since the whole game came out washed
  out.
- **Armature scale does not survive the glTF export** as a node scale,
  and applying it to the armature rescales the bones while the actions
  keep storing bone-local translations for the old size. Scale on the
  Godot import with `nodes/root_scale`.

Faction marking on a texture-skinned character has no material slot to
use, so `convert_character.py` bolts a helmet and two shoulder pads onto
the rig, weighted to their bones rather than parented — a parented object
is a second draw call per soldier, which at 120 units is 120 extra draws
for a hat.
