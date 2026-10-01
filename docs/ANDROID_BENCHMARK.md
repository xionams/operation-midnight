# Android benchmark

## Status

**Phase 4's numbers below are a desktop baseline. Nothing in this game
has been measured on an Android device.** `adb` is installed on the
development machine but no device has ever been attached, so the Vulkan
mobile path has never executed on the hardware it is written for.

That matters more than it sounds. The limits that decide whether this
runs on a phone are fill rate and memory bandwidth, and neither shows up
on a desktop GPU: a scene that costs 99 FPS here can be the one that
falls over on a device, while one that costs 156 FPS here may be fine.
Treat the desktop column as a *relative* measure between revisions, not
as a prediction.

## Running it

```
godot --path . res://scenes/dev/android_benchmark.tscn     # desktop baseline
```

On a device, install the **profiling** APK (the debug build), tap **RUN
BENCHMARK** on the launch screen, then:

```
adb logcat -s godot | grep BENCH
adb shell run-as <package> cat files/benchmark.txt
```

Every line is written to `user://benchmark.txt` as well as printed,
because logcat on a phone drops lines under load — which is precisely
when the numbers are worth having.

VSync is disabled and `Engine.max_fps` set to 0 by the harness. At a 60
cap every build and every device reports 60 and the benchmark measures
nothing.

## Scenarios

| | What it is | Why it is in the list |
|---|---|---|
| A | A base at rest | The floor. Whatever this costs is paid in every other scenario too. |
| B | 60 units in a land engagement at fighting zoom | The common case. |
| C | A fleet on the coast | The most expensive thing the game draws: see-through water, a shoreline, hulls and wakes in one frame. |
| D | Everything damaged — burning buildings, smoking units, wrecks and corpses | What Phase 4 added. The scenario to watch first on a device. |
| E | Camera pulled back to `max_zoom` | Where draw calls and triangles peak, even though nothing is close enough to see. |

## Desktop baseline

Intel RPL-P integrated graphics, i5-13420H, Godot 4.7.2, uncapped.

**Check the `load=` line in the header before trusting any FPS here.** A
run was once taken with a forgotten Android emulator on six cores and
read 33 FPS where the same build reads 115; the draw and triangle
columns were correct throughout, which is what made it hard to spot.

Phase 7 (skinned infantry), idle machine:

| Scenario | FPS | 1% low | Draws | Triangles | Nodes | VRAM (MB) |
|---|---|---|---|---|---|---|
| A idle base | 197.2 | 150.0 | 196 | 76,559 | 738 | 97.0 |
| B land battle 60 | 114.6 | 90.0 | 519 | 217,079 | 1,657 | 101.1 |
| C coastal fleet | 121.3 | 86.7 | 263 | 89,857 | 1,830 | 101.8 |
| D effects storm | 95.1 | 58.3 | 553 | 358,841 | 1,847 | 101.8 |
| E max zoom out | 96.5 | 75.2 | 619 | 376,588 | 1,832 | 101.7 |

Phase 4, for comparison (also an idle machine — it predates the
emulator):

| Scenario | FPS | 1% low | Draws | Triangles | Nodes | VRAM (MB) |
|---|---|---|---|---|---|---|
| A idle base | 200.2 | 165.0 | 740 | 95,844 | 2,102 | 95.9 |
| B land battle 60 | 99.7 | 79.9 | 1,512 | 237,007 | 2,963 | 98.7 |
| C coastal fleet | 162.9 | 90.0 | 770 | 143,545 | 2,991 | 99.4 |
| D effects storm | 156.1 | 135.0 | 1,382 | 219,005 | 2,843 | 98.7 |
| E max zoom out | 157.4 | 150.0 | 1,485 | 238,170 | 2,843 | 98.7 |

Draw calls fell everywhere — B by 66%, A by 74% — and node counts with
them. But **C, D and E give back FPS while drawing fewer calls**, and
D and E carry 60% more triangles than they did in Phase 4. That is the
scenery-batching trade showing its other side: a MultiMesh chunk is
culled as a single box, so pulling the camera back (E) or filling the
screen with effects (D) submits geometry that per-instance culling used
to reject. Worth measuring on a real phone before deciding whether the
trade was right — a mobile driver's per-call cost is the whole reason
it was made.

## What to look at first on a device

1. **Scenario C.** The water shader is the only full-screen transparent
   pass in the game, and fill rate is a phone's tightest budget.
2. **Scenario B's draw calls (1,512).** Draw calls cost far more on a
   mobile driver than on a desktop one.
3. **Scenario D.** Every effect Phase 4 added is alpha-blended, and
   overdraw is the other half of the fill-rate budget.

If C or D will not hold 30 FPS on the target device, the order to cut in
is: water shader complexity, then particle counts, then the corpse and
wreck caps (`DeathThroe.MAX_CORPSES`, `Wreckage.MAX_WRECKS`) — in that
order, because that is cheapest-to-least-visible.
