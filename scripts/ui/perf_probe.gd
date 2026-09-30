class_name PerfProbe
extends Node

## Frame-cost instrumentation you can read on a phone.
##
## Engine.get_frames_per_second() alone is not enough to profile a
## device: it is an average that hides exactly the thing that ruins a
## mobile session, which is the occasional 90ms frame. This keeps a
## rolling window so the 1% low and the worst frame are both visible,
## alongside the counters that say WHY - draw calls and triangles for a
## geometry problem, video memory for a texture one, particles and rounds
## in flight for an effects one.
##
## It also writes to a file. On a device, logcat drops lines under load,
## which is precisely when the numbers are worth having:
##
##   OM_PERFLOG=1 godot ...           -> user://perf.csv
##   adb shell run-as <package> cat files/perf.csv

## Two seconds at 60fps. Long enough for a 1% low to mean something,
## short enough that the readout still tracks what is on screen now.
const WINDOW: int = 120
const LOG_INTERVAL: float = 2.0
## How often to save a frame to user:// while logging. On a device the
## only trustworthy picture of what the game drew is one the game took
## itself: `adb shell screencap` cannot see Godot's rendering surface on
## an emulator - it returned solid black under Vulkan and solid white
## under GL while the renderer was demonstrably submitting 185k
## triangles a frame.
const SHOT_INTERVAL: float = 15.0
const SHOTS_KEPT: int = 4

var _frames: PackedFloat32Array = PackedFloat32Array()
var _cursor: int = 0
var _filled: int = 0
var _log: FileAccess = null
var _log_timer: float = 0.0
var _shot_timer: float = 0.0
var _shot_index: int = 0
var _worst_ever: float = 0.0

func _ready() -> void:
	_frames.resize(WINDOW)
	process_priority = -100
	## Measure while the tree is paused too. The skirmish setup screen
	## pauses it, and so does every menu - those frames are part of a
	## session and their cost is just as real. Without this the probe
	## recorded nothing at all until a match started, which on a device
	## looks exactly like a game that is not rendering.
	process_mode = Node.PROCESS_MODE_ALWAYS
	## Debug builds log by themselves; release builds never do.
	##
	## This used to need `--perflog` baked into the export's command line,
	## which meant the release candidate shipped writing a CSV every two
	## seconds for the life of a session. Keying off the build type gets
	## the instrumentation onto a device - where there is no practical way
	## to set an environment variable - without it reaching a player. The
	## flag and the env var still work, for forcing it on a release build
	## when something has to be measured in the shipping configuration.
	if OS.is_debug_build() \
		or not OS.get_environment("OM_PERFLOG").is_empty() \
		or OS.get_cmdline_args().has("--perflog") \
		or OS.get_cmdline_user_args().has("--perflog"):
		_open_log()

func _open_log() -> void:
	_log = FileAccess.open("user://perf.csv", FileAccess.WRITE)
	if _log == null:
		return
	_log.store_line("t,fps,low1,worst_ms,draws,tris,nodes,vram_mb,static_mb,units,rounds")
	## Flushed immediately: an unflushed header is indistinguishable from
	## a probe that never ran.
	_log.flush()
	print("PERF| logging to %s" % ProjectSettings.globalize_path("user://perf.csv"))

func _process(delta: float) -> void:
	_frames[_cursor] = delta
	_cursor = (_cursor + 1) % WINDOW
	_filled = mini(_filled + 1, WINDOW)
	_worst_ever = maxf(_worst_ever, delta)
	if _log == null:
		return
	_shot_timer += delta
	if _shot_timer >= SHOT_INTERVAL:
		_shot_timer = 0.0
		_save_frame()
	_log_timer += delta
	if _log_timer < LOG_INTERVAL:
		return
	_log_timer = 0.0
	var s: Dictionary = summary()
	_log.store_line("%.1f,%.1f,%.1f,%.1f,%d,%d,%d,%.1f,%.1f,%d,%d" % [
		Time.get_ticks_msec() / 1000.0, s["fps"], s["low1"], s["worst_ms"],
		s["draws"], s["tris"], s["nodes"], s["vram_mb"], s["static_mb"],
		s["units"], s["rounds"]])
	_log.flush()

## A frame as the ENGINE saw it, not as the platform's screen grabber
## did. Written round-robin so a long session cannot fill the device.
func _save_frame() -> void:
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		return
	image.save_png("user://frame_%d.png" % _shot_index)
	_shot_index = (_shot_index + 1) % SHOTS_KEPT

## Everything worth knowing about the last two seconds.
func summary() -> Dictionary:
	var sorted: Array = []
	for i in _filled:
		sorted.append(_frames[i])
	sorted.sort()
	var n: int = sorted.size()
	var total: float = 0.0
	for dt in sorted:
		total += dt
	## The 1% low, not the single worst frame: one stall while a shader
	## compiles says nothing about how the scene runs.
	var low: float = sorted[maxi(int(n * 0.99) - 1, 0)] if n > 0 else 0.0
	return {
		"fps": (float(n) / total) if total > 0.0 else 0.0,
		"low1": (1.0 / low) if low > 0.0 else 0.0,
		"worst_ms": (sorted[n - 1] * 1000.0) if n > 0 else 0.0,
		"peak_ms": _worst_ever * 1000.0,
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"tris": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"units": get_tree().get_nodes_in_group("units").size(),
		"rounds": get_tree().get_nodes_in_group(WeaponVisuals.GROUP).size(),
	}

## The overlay text. Deliberately short: on a phone this sits over the
## battlefield and a long readout is worse than none.
func to_text() -> String:
	var s: Dictionary = summary()
	return "%d fps  (1%% low %d)\n%.1f ms worst, %.1f peak\n%d draws  %dk tris\n%d MB vram  %d MB heap\n%d units  %d rounds" % [
		int(s["fps"]), int(s["low1"]), s["worst_ms"], s["peak_ms"],
		s["draws"], int(s["tris"] / 1000.0), int(s["vram_mb"]), int(s["static_mb"]),
		s["units"], s["rounds"]]
