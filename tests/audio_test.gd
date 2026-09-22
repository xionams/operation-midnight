extends Node

## Checks the sound layer plays the right thing, not that files exist.
##
## Audio is the easiest system to believe is working: nothing throws if a
## cue is missing, a bed never starts, or every weapon reports with the
## same sound. So this asserts on which stream a cue resolves to and on
## the music state machine, rather than on the absence of errors.

var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-54s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _stats(path: String) -> WeaponStats:
	return load(path)

func _ready() -> void:
	var scene := get_parent()
	await get_tree().process_frame
	var hud = scene.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	get_tree().paused = false
	await get_tree().process_frame

	# --- every cue resolves, and to a real file where one was authored ---
	var authored: int = 0
	for cue in AudioDirector.CUES:
		var stream = AudioDirector._streams.get(cue)
		_check("Cue '%s' resolves to a stream" % cue, stream != null)
		if stream != null and stream.resource_path.contains("assets/audio/"):
			authored += 1
	_check("Most cues use authored audio, not the fallback tone",
		authored >= AudioDirector.CUES.size() - 1,
		"(%d of %d)" % [authored, AudioDirector.CUES.size()])

	# --- weapons must not all sound the same ---
	var heard: Dictionary = {}
	var weapons := {
		"rifle": "res://config/weapons/rifle.tres",
		"tank": "res://config/weapons/tank_cannon.tres",
		"artillery": "res://config/weapons/artillery_gun.tres",
		"at": "res://config/weapons/at_launcher.tres",
	}
	for key in weapons:
		var stats := _stats(weapons[key])
		if stats == null:
			continue
		var before: int = AudioDirector._next_voice
		AudioDirector.play_weapon(stats)
		var voice: AudioStreamPlayer = AudioDirector._players[before]
		heard[key] = voice.stream.resource_path.get_file()
	print("TEST| weapon voices: %s" % str(heard))
	_check("Artillery and a rifle do not share a report",
		heard.get("artillery", "a") != heard.get("rifle", "b"))
	_check("A tank does not sound like a rifle",
		heard.get("tank", "a") != heard.get("rifle", "b"))
	_check("Every weapon class has its own report",
		_unique(heard.values()) == heard.size(),
		"(%d distinct of %d)" % [_unique(heard.values()), heard.size()])

	# --- beds ---
	_check("An ambient bed is playing", AudioDirector._ambient.playing)
	_check("The ambient bed loops",
		AudioDirector._ambient.stream is AudioStreamWAV
			and AudioDirector._ambient.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	_check("Both music beds are running", AudioDirector._calm.playing
		and AudioDirector._combat.playing)

	# --- music follows the fighting ---
	AudioDirector._last_combat = -999.0
	await _wait(2.4)
	var calm_quiet: float = AudioDirector._calm.volume_db
	var combat_quiet: float = AudioDirector._combat.volume_db
	_check("With nothing happening, the calm bed is the loud one",
		calm_quiet > combat_quiet, "(calm %.0f dB vs combat %.0f dB)" % [calm_quiet, combat_quiet])

	AudioDirector.play_weapon(_stats("res://config/weapons/tank_cannon.tres"))
	await _wait(2.4)
	_check("Firing brings the combat bed up",
		AudioDirector._combat.volume_db > AudioDirector._calm.volume_db,
		"(combat %.0f dB vs calm %.0f dB)" % [
			AudioDirector._combat.volume_db, AudioDirector._calm.volume_db])
	_check("Combat is registered as recent", AudioDirector._in_combat)

	## And it must settle back down rather than staying tense forever.
	AudioDirector._last_combat = -999.0
	await _wait(2.4)
	_check("It settles back to calm when the shooting stops",
		AudioDirector._calm.volume_db > AudioDirector._combat.volume_db)

	# --- impacts scale with the weapon ---
	var before_i: int = AudioDirector._next_voice
	AudioDirector.play_impact(_stats("res://config/weapons/rifle.tres"))
	var small: String = AudioDirector._players[before_i].stream.resource_path.get_file()
	before_i = AudioDirector._next_voice
	AudioDirector.play_impact(_stats("res://config/weapons/artillery_gun.tres"))
	var big: String = AudioDirector._players[before_i].stream.resource_path.get_file()
	_check("A shell lands differently from a bullet", small != big,
		"(%s vs %s)" % [small, big])

	# --- silence must be honoured ---
	AudioDirector.enabled = false
	var before_q: int = AudioDirector._next_voice
	AudioDirector.play("select")
	_check("Disabling audio stops cues", AudioDirector._next_voice == before_q)
	AudioDirector.enabled = true

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _unique(values) -> int:
	var seen: Dictionary = {}
	for v in values:
		seen[v] = true
	return seen.size()

func _wait(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame
