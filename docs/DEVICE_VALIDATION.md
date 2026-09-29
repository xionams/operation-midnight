# Device validation

Everything in Phase 5 that a desktop can answer has been answered. This
is the list of what it cannot, and exactly how to settle each item once
a phone is plugged in.

**Nothing in this game has ever run on Android hardware.** `adb` is
installed and working on the development machine; no device has ever
been attached to it. The Vulkan mobile renderer has therefore never
executed on the hardware it is written for, and no number below the
"desktop" column should be read as a prediction.

## The two builds

| APK | What it is | Use it for |
|---|---|---|
| `build/operation-midnight-rc.apk` | Release, 29.7 MB | The release candidate. Play sessions, the definition-of-done checks. |
| `build/operation-midnight-profiling.apk` | Debug, 31.5 MB | Profiling. Has the **RUN BENCHMARK** button and verbose logging. |

Both are arm64-v8a only, minSdk 24, targetSdk 36, package
`com.xionams.operationmidnight`.

> `export_presets.cfg` is gitignored - it holds the keystore password -
> so the signing configuration lives only on the machine that built
> these. To rebuild elsewhere, add to the Android preset:
>
> ```
> keystore/release="<path>/.android/debug.keystore"
> keystore/release_user="androiddebugkey"
> keystore/release_password="android"
> ```
>
> Without it the export still reports DONE, warns that it cannot find a
> release keystore, and writes an APK that will not install.

> Both are signed with the **Android debug keystore**. That is fine for
> side-loading and testing and is NOT publishable: a Play Store upload
> needs a real release key, and once chosen it can never be changed for
> the life of the listing. Generate it before the first store upload,
> not after.

```
adb install -r build/operation-midnight-rc.apk
adb shell am start -n com.xionams.operationmidnight/com.godot.game.GodotApp
```

## The checks, in the order worth doing them

### 1. It installs and launches
Watch the first launch specifically: Godot compiles shaders on first
use, and a long stall or an outright crash here is the most common
mobile-only failure.

```
adb logcat -c && adb logcat | grep -iE "godot|AndroidRuntime|FATAL"
```

### 2. Touch controls
Every one of these is driven by code that has only ever been exercised
by synthetic events (`tests/touch_input_test.gd`), never by a finger:

- one-finger drag pans the camera
- two-finger pinch zooms
- tap selects a unit; tap on empty ground with units selected orders them
- **press and hold** starts a marquee (touch only — on a desktop a slow
  click stays a click; see `SelectionManager._process`)
- drag-place a wall: press, drag, release lays a line
- the sidebar's buttons are all ≥44px, verified at the 1280×720 base the
  project stretches from — check they are actually hittable in a hand

### 3. A full Coastline match
Start a skirmish on Coastline and play it to a result. Specifically
exercise the things that only break over time: build a base, take the
sea, lose units, sell a building, save and resume.

### 4. Frame cost
Tap **Debug** in the sidebar for the live readout (fps, 1% low, worst
frame, draw calls, triangles, VRAM, rounds in flight). For a recorded
run use the profiling APK:

```
adb shell am start -n com.xionams.operationmidnight/com.godot.game.GodotApp
# play, then:
adb shell run-as com.xionams.operationmidnight cat files/perf.csv > perf.csv
```

`user://perf.csv` is written every 2 seconds. It exists because logcat
drops lines under load, which is when the numbers matter.

For the synthetic comparison, use **RUN BENCHMARK** on the launch screen
of the profiling build; it writes `user://benchmark.txt`. Scenario
meanings and the desktop baseline are in `ANDROID_BENCHMARK.md`.

### 5. What to watch for specifically

These are the failure modes this codebase has actually produced, so they
are the ones most likely to recur under different frame timing:

- **Units flying or sinking.** A unit drifting vertically off its
  surface was a real bug (patrol boats reached Y=218). `_settle_on_ground`
  now corrects drift over 0.75m, but it is frame-timing sensitive by
  nature. Watch ships especially.
- **Units stuck at a choke.** Jam recovery escalates over ~7.5s. On a
  slower device that is the same number of seconds but fewer frames.
- **The sidebar overflowing.** It is fitted by measurement at runtime.
  If a device reports a different logical height than 720, the fit
  should absorb it — confirm nothing runs off the bottom.
- **Softlocks at match end.** Victory and defeat overlays pause the
  tree; confirm PLAY AGAIN and NEW SKIRMISH both work on a touch screen.

## Performance triage, if it is slow

In this order, because it is cheapest-to-least-visible:

1. **Water shader** (`shaders/water.gdshader`) — the only full-screen
   transparent pass in the game, and fill rate is a phone's tightest
   budget. Scenario C is the test.
2. **Particle counts** in `scripts/vfx/vfx.gd` — everything Phase 4
   added is alpha-blended, and overdraw is the other half of fill rate.
   Scenario D is the test.
3. **Corpse and wreck caps** — `DeathThroe.MAX_CORPSES` (40) and
   `Wreckage.MAX_WRECKS` (24).
4. **Draw calls** — 1,512 in scenario B. A mobile driver charges far
   more per call than a desktop one; if this is the wall, the answer is
   merging static scenery rather than removing it.

## Still unvalidated after Phase 5

Everything in section 2, 3 and 4 above. Specifically: no touch gesture
has been performed by a human, no match has been played to a result on a
device, no frame has been rendered by a mobile GPU, and the APK has
never been installed.

## Rebuilding the APKs

```
export JAVA_HOME=~/jdk17 PATH=~/jdk17/bin:$PATH
godot --headless --path . --export-release "Android" build/operation-midnight-rc.apk
godot --headless --path . --export-debug   "Android" build/operation-midnight-profiling.apk
```

Verify before trusting one — the export reports DONE even when signing
failed:

```
~/android-sdk/build-tools/34.0.0/apksigner verify --print-certs build/operation-midnight-rc.apk
```
