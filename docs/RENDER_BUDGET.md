# Render budget

What the frame costs, where it goes, and how to find out again.

## Measuring it

`scenes/dev/drawcall_audit.tscn` builds the benchmark's worst draw case
— 60 units in contact — and switches each system off in turn, taking the
delta as that system's cost. Deltas rather than absolutes: the renderer
culls and batches, so a category's real cost is what disappears when it
does. Categories overlap (scenery's shadows count in both rows).

```
godot --path . res://scenes/dev/drawcall_audit.tscn
godot --path . res://scenes/dev/census.gd       # mesh instances by owner
godot --path . res://scenes/dev/infantry_scale.tscn
godot --path . res://scenes/dev/android_benchmark.tscn
```

## Measure on an idle machine, and prove it was idle

A whole run of FPS numbers was once taken with a forgotten Android
emulator eating six cores. Nothing in the output said so: draw calls,
triangles and node counts are *counted*, so they stayed correct, and
only the FPS column was wrong — which made the contamination look like
a rendering regression. Scenario B read 33 FPS; on an idle machine the
same build reads 115.

The benchmark now prints `load=` with a verdict in its header, and
refuses to be quietly believed. **Check that line before comparing any
FPS figure to any other.** Counted metrics — draws, triangles, nodes,
VRAM — are unaffected by load and can be compared across runs freely.

## What the first audit found

Desktop Vulkan, 60 units, 1,688 draw calls:

| Category | Draws | Share |
|---|---|---|
| Shadows | 975 | 63% |
| Scenery props | 781 | 51% |
| Unit models | 302 | 20% |
| UI (whole HUD) | 263 | 16% |
| Ground marks | 4 | 0% |
| Health bars | 0 | — |
| Selection rings | 0 | — |

Two things worth knowing before optimising anything here. **Health bars
and selection rings cost nothing** — they are hidden unless wanted, and
the obvious "batch the health bars" work would have bought exactly zero.
And **decoration cost more than the game did**: scenery alone outweighed
units, UI and ground marks together.

## The rules that came out of it

**A material slot is a draw call, and it is paid twice.** Each slot
becomes a mesh surface, and every surface is drawn again into the shadow
map. This is why `om_kit.Node.MERGE` folds Glass into Body, and why
adding a material to a model is not free.

**Chunk size trades culling against draw calls, and on mobile the call
wins.** A batch that is off screen costs one cheap rejected call; a
hundred extra batches cost on every frame wherever the camera looks.
Props chunk at 110m, ground cover on an 8×8 grid. Do not raise these
without measuring.

**Static and repeated means MultiMesh.** Anything scattered — trees,
rocks, road segments, base pads, blocker boulders — goes through
`Scenery._record()` and is batched, never `_spawn()`. `_spawn` remains
for the few props that need to be individual nodes.

**Small things do not cast shadows.** Props and grass are
`SHADOW_CASTING_SETTING_OFF`: a tuft's shadow is smaller than a pixel at
an RTS camera height. Shadow distance is 70m, roughly what the camera
sees at maximum zoom.

**Every spawner has a ceiling.** Corpses 40 (`DeathThroe.MAX_CORPSES`),
wrecks 24 (`Wreckage.MAX_WRECKS`), ground marks per layer, VFX bursts 48
(`VFX.MAX_BURSTS`). Bursts are dropped rather than queued when full: a
flash that arrives late is worse than one that never came.

## What the second audit found

After the scenery batching and the skinned infantry, same 60-unit scene,
desktop Vulkan, **649 draws / 195,180 triangles**:

| Category | Draws | Share | Triangles | Share |
|---|---|---|---|---|
| UI (whole HUD) | 211 | 34% | ~0 | — |
| Shadows | 178 | 33% | 76,022 | 40% |
| Unit models | 153 | 29% | 106,622 | 55% |
| Scenery props | 63 | 12% | 34,172 | 18% |
| Ground marks | 4 | 1% | 1,024 | 0% |
| Health bars | 0 | — | 0 | — |
| Selection rings | 0 | — | 0 | — |

**Counting only draw calls hid half the frame.** Scenery batching traded
calls for triangles — a MultiMesh is culled as one box, so a chunk with
one tree on screen submits every tree it holds — and scenery that fell
from 781 draws to 63 still carries 18% of the geometry. The audit
reports both columns now for that reason.

**The UI is the largest single draw category and it does not scale.**
211 draws is a fixed floor, paid whether the battle holds six units or
two hundred. It is the thing to fix for the *floor*, never for the
*slope*.

## Cost per unit, measured

`infantry_scale.tscn`, desktop Vulkan, idle machine:

| Infantry | FPS | Draws | Triangles |
|---|---|---|---|
| 20 | 180.7 | 218 | 67,238 |
| 60 | 114.6 | 337 | 90,854 |
| 120 | 75.6 | 517 | 126,376 |
| 200 | 50.6 | 757 | 173,736 |

Slope: **3 draws and ~590 triangles per infantryman** (2 draws drawn,
1 shadow). Fixed floor 158 draws.

Per model, from the GLBs themselves:

| | Surfaces | Triangles | Skinned |
|---|---|---|---|
| main_battle_tank | 9 | 2,428 | no |
| scout_vehicle | 6 | 2,104 | no |
| harvester | 4 | 2,048 | no |
| assault_vehicle | 8 | 1,564 | no |
| artillery_vehicle | 7 | 1,492 | no |
| at_squad | 3 | 316 | yes |
| rifle_soldier | 3 | 264 | yes |
| attack_dog | 2 | 144 | yes |

A surface is a draw call and it is paid twice, so a main battle tank
costs 18 draw calls against a rifleman's 3, and nine times his
triangles. Measured in the mix: **30 vehicles cost 210 draws, 7 each.**

## CPU, not just the GPU

Draw calls stopped being the constraint before the frame did. Running
`infantry_scale` with `OM_NO_POSE=1` holds every skeleton at its rest
pose, leaving the identical scene to render, and the difference is what
GDScript bone posing costs:

| Infantry | Posed | Rest only | Posing |
|---|---|---|---|
| 60 | 8.73 ms | 7.63 ms | 1.10 ms |
| 120 | 13.23 ms | 10.49 ms | 2.74 ms |
| 200 | 19.76 ms | 14.27 ms | 5.49 ms |

**~0.027 ms per soldier per frame** — at 200 infantry, 28% of the frame,
spent in `_process` before the renderer is asked for anything. This is
why `DETAIL_RANGE` exists and why the next infantry win is a shared
posing pass rather than more mesh work.

## Where it ended up

Desktop Vulkan, same 60-unit scene: **1,688 → 967 → 649** draw calls
across Phases 6 and 7.

| Category | Before | After |
|---|---|---|
| Shadows | 975 | 325 |
| Scenery props | 781 | 63 |
| Unit models | 302 | 300 |
| UI | 263 | 241 |

Android GL (emulator), benchmark scenarios:

| Scenario | Before | After |
|---|---|---|
| A idle base | 1,772 | 233 |
| B land battle 60 | 3,059 | 1,319 |
| C coastal fleet | 1,264 | 410 |
| D effects storm | 2,780 | 1,671 |
| E max zoom out | 2,832 | 1,762 |

D and E carry *more* content after than before — the benchmark used to
destroy its own scene, so those two were measured over a half-dead
battlefield and a defeat card.

## What is still expensive, and why it was left

**Infantry are ~15 draw calls each** (12 mesh instances plus shadows).
Measured: 20 infantry 458 draws, 60 → 1,057, 120 → 1,957. The rig is
seven jointed nodes because the Phase 4 animation poses them
individually, and the floor for a jointed rig without skinning is one
call per node per material. Collapsing it means skinning the soldier to
an armature — one draw call for the whole man — which is a real piece of
work and would replace the animation system rather than tune it.

**The UI is ~240 calls.** It is a large sidebar with per-item cameos and
it is on screen permanently. Worth revisiting if a device says so.
