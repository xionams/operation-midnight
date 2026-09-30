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

## Where it ended up

Desktop Vulkan, same 60-unit scene: **1,688 → 967** draw calls.

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
