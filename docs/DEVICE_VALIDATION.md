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

---

# Emulator validation (2026-09-30)

An AVD is now the primary Android validation environment. A physical
device is still required for the four things at the bottom of this
section, and nothing else.

## The AVD

| | |
|---|---|
| Profile | Pixel-class, 1080×2400, 420 dpi |
| Android | 14 (API 34), `google_apis`, x86_64 |
| Acceleration | KVM (CPU). **No host GPU** — the emulator refuses this Intel iGPU for hardware rendering |
| GPU mode | `-gpu lavapipe` (Vulkan via llvmpipe, GLES via **swangle/ANGLE**) |
| Window | `-no-window`; the emulator's Qt UI cannot start here (missing `libxcb-cursor0`) |

```
emulator -avd midnight -gpu lavapipe -no-window -no-snapshot -no-boot-anim -no-audio -no-metrics
```

## Three findings that only an Android run could produce

**1. The Vulkan build does not render under software Vulkan.** Under both
SwiftShader and lavapipe, Godot initialises `Vulkan 1.3.0 - Forward
Mobile` and starts its main loop, then emits `Couldn't present to Vulkan
queue (VkResult error 5)` every few seconds and produces no frames. The
process stays alive at ~0% CPU. This is a software-Vulkan limitation,
not proof of a fault on a real GPU — but it does mean **the shipping
renderer cannot be exercised on this emulator**, and it is why the GL
build exists.

**2. The GL build needs ANGLE, not SwiftShader.** Under raw SwiftShader
every scene shader failed to link:

```
SceneShaderGLES3: Program linking failed:
Fragment shader active uniforms exceed GL_MAX_FRAGMENT_UNIFORM_VECTORS (261)
```

with the result that the game rendered a solid white screen while
reporting 185k triangles a frame. Under `-gpu lavapipe` (which selects
**swangle** for GLES) there are zero link failures and the game renders
correctly. Worth remembering: a real device whose driver reports a low
fragment-uniform limit would hit the same wall on the GL fallback.

**3. Neither `adb screencap` nor `dumpsys gfxinfo` can see this game.**
Screencap returned solid black under Vulkan and solid white under GL
while the renderer was demonstrably working, and gfxinfo froze at 13
frames. Godot draws to its own surface. `PerfProbe` therefore saves
frames from inside the engine to `user://frame_N.png`, which is the only
trustworthy picture of what the game actually drew.

## Reading the numbers off a device

```
adb install -r -t build/operation-midnight-gl.apk        # emulator
adb shell am start -n com.xionams.operationmidnight/com.godot.game.GodotAppLauncher
adb shell run-as com.xionams.operationmidnight cat files/perf.csv
adb exec-out run-as com.xionams.operationmidnight cat files/frame_0.png > frame.png
```

`--perflog` is baked into the export's command line, so logging starts
on its own. **Remove it from `command_line/extra_args` before any store
build** — it writes a CSV every two seconds for the life of the session.

## Still requires physical hardware

Only these. Everything else is validated above.

- **Real GPU performance.** The emulator renders in software; its frame
  rate says nothing about a phone.
- **Thermal throttling.** Cannot be reproduced.
- **Battery impact.** Cannot be measured.
- **Touch ergonomics.** Whether a 44px target is comfortable in a hand
  is not a question `adb input` can answer.
- **The Vulkan renderer itself**, per finding 1 — the RC ships Vulkan
  and only the GL build could be exercised here.
