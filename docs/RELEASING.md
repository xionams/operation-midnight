# Releasing Operation Midnight

Everything needed to produce a signed Android build, and the two things
that are decisions rather than steps.

## Prerequisites (all under `$HOME`, none need root)

| | Where |
|---|---|
| JDK 17 | `~/jdk17` |
| Android SDK | `~/android-sdk` (platform-tools, build-tools 34, platform 34) |
| Export templates | `~/.local/share/godot/export_templates/4.7.2.stable` |
| Debug keystore | `~/.android/debug.keystore` |
| Release keystore | `~/.android/operation-midnight-release.keystore` |

## Build

```bash
export JAVA_HOME=~/jdk17
export PATH=$JAVA_HOME/bin:$PATH
export ANDROID_HOME=~/android-sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME

# Debug, for sideloading onto your own device
godot --headless --path . --export-debug "Android" build/operation-midnight.apk

# Release, signed for distribution
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$HOME/.android/operation-midnight-release.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="operationmidnight"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="…"
godot --headless --path . --export-release "Android" build/operation-midnight-release.apk

# Confirm the signature before shipping anything
~/android-sdk/build-tools/34.0.0/apksigner verify --print-certs build/operation-midnight-release.apk
```

The signing credentials go through environment variables rather than
`export_presets.cfg`, because that file is committed and a password in
version control is a password that has leaked.

## Presets

**Android** is the one that ships: Vulkan/Mobile renderer, arm64-v8a,
min SDK 24, immersive, landscape.

**Android GL (emulator)** is a testing variant that passes
`--rendering-method gl_compatibility`. It exists because the emulator
cannot present Vulkan frames — the engine initialises correctly and then
nothing reaches the screen. Do not ship it; it is how the game gets
verified end to end without a physical device.

## Two decisions that are yours

**1. The signing key.** A release keystore currently exists at
`~/.android/operation-midnight-release.keystore` so a signed build could
be produced and verified. Before anything is published:

- **Back it up somewhere you will still have in five years.** If this
  file is lost, that app can never be updated again by anyone. Not
  recovered — never updated. A new key means a new listing.
- Consider regenerating it with a passphrase you chose. The current one
  was set here so the pipeline could be proven end to end, and it is
  written in this repository's history.
- `*.keystore` and `*.jks` are gitignored. Keep it that way.

**2. Vulkan on real hardware.** Every device check so far has gone
through the emulator, which can only run the OpenGL variant. The shipping
preset uses Vulkan/Mobile, which is the right target for modern Android
hardware and is the one thing that has never run on any. Install the
debug APK on a real phone before publishing. If it shows a black screen,
the GL preset is the known-good fallback and the renderer setting in
`project.godot` is a one-line change.

## Checklist before publishing

- [ ] Release APK signature verifies
- [ ] Installed and played on a physical device (Vulkan path)
- [ ] Keystore backed up off this machine
- [ ] Version code and name bumped in `export_presets.cfg`
- [ ] Store assets in `docs/store/`
