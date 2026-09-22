extends Node

## Autoload: the game's whole sound layer.
##
## Cues are requested by name through play(), so gameplay never knows
## what a sound actually is. The set is synthesised by tools/make_sfx.py
## (produced by Codex from the audio direction) and lives in
## assets/audio; anything missing falls back to a generated tone, so a
## cue that has not been authored yet is audible rather than silent.
##
## Beds are separate from cues: an ambient wind layer that always runs,
## and two music beds that cross-fade on whether anyone is shooting.

const SAMPLE_RATE: int = 22050
const MAX_VOICES: int = 16
const AUDIO_DIR: String = "res://assets/audio/"

## Fallback tone table, used only when a .wav is missing.
## name -> [frequency Hz, seconds, waveform, volume dB]
const CUES: Dictionary = {
	"select":         [660.0, 0.06, "square", -20.0],
	"order":          [880.0, 0.07, "sine",   -18.0],
	"build_place":    [330.0, 0.16, "square", -14.0],
	"build_done":     [520.0, 0.22, "sine",   -13.0],
	"unit_ready":     [740.0, 0.16, "sine",   -15.0],
	"capture":        [420.0, 0.30, "square", -13.0],
	"sell":           [300.0, 0.30, "saw",    -14.0],
	"low_power":      [140.0, 0.45, "saw",    -12.0],
	"rifle_shot":     [180.0, 0.05, "noise",  -14.0],
	"mg_burst":       [200.0, 0.10, "noise",  -15.0],
	"at_launcher":    [140.0, 0.20, "noise",  -12.0],
	"cannon_shot":    [110.0, 0.18, "noise",   -8.0],
	"artillery_shot": [90.0,  0.28, "noise",   -7.0],
	"impact_small":   [240.0, 0.06, "noise",  -18.0],
	"impact_shell":   [120.0, 0.16, "noise",  -12.0],
	"explosion_small":[90.0,  0.30, "noise",   -9.0],
	"explosion_large":[70.0,  0.45, "noise",   -6.0],
	"victory":        [720.0, 0.80, "sine",    -8.0],
	"defeat":         [150.0, 0.90, "saw",     -8.0],
}

## Beds: name -> volume dB. Looped, never retriggered.
const BEDS: Dictionary = {
	"ambient_wind": -26.0,
	"music_calm":   -22.0,
	"music_combat": -20.0,
}

## How long after the last shot the music stays tense. Short enough that
## a skirmish does not leave combat music running over an empty map,
## long enough that it does not flicker between the two.
const COMBAT_HOLD: float = 9.0
const FADE: float = 1.8

var enabled: bool = true
var music_enabled: bool = true

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0

var _ambient: AudioStreamPlayer
var _calm: AudioStreamPlayer
var _combat: AudioStreamPlayer
var _last_combat: float = -999.0
var _in_combat: bool = false

func _ready() -> void:
	for cue in CUES:
		_streams[cue] = _load_or_synthesise(cue)
	for i in MAX_VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

	_ambient = _make_bed("ambient_wind")
	_calm = _make_bed("music_calm")
	_combat = _make_bed("music_combat")

	EventBus.building_placed.connect(func(_b): play("build_place"))
	EventBus.unit_spawned.connect(func(_u): play("unit_ready"))
	EventBus.command_issued.connect(func(_t, _p): play("order"))
	EventBus.building_sold.connect(func(_b): play("sell"))
	EventBus.construction_ready.connect(func(_s): play("build_done"))
	EventBus.building_captured.connect(func(_b, _p): play("capture"))
	EventBus.low_power_changed.connect(func(low): if low: play("low_power"))
	GameState.selection_changed.connect(func(s): if not s.is_empty(): play("select"))
	GameState.match_ended.connect(_on_match_ended)

## A cue prefers its authored file and falls back to a tone, so an
## un-authored sound is obviously placeholder rather than silence.
func _load_or_synthesise(cue: String) -> AudioStream:
	var path: String = AUDIO_DIR + cue + ".wav"
	if ResourceLoader.exists(path):
		var stream = load(path)
		if stream != null:
			return stream
	var entry: Array = CUES[cue]
	return _synthesise(entry[0], entry[1], entry[2])

func _make_bed(name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	var path: String = AUDIO_DIR + name + ".wav"
	if not ResourceLoader.exists(path):
		return player
	var stream = load(path)
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / 2
	player.stream = stream
	player.volume_db = -80.0
	player.play()
	return player

## Round-robin voices so a burst of events never cuts itself off.
func play(cue: String) -> void:
	if not enabled or not _streams.has(cue):
		return
	var player: AudioStreamPlayer = _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	player.stream = _streams[cue]
	player.volume_db = CUES[cue][3]
	player.play()

## Weapons pick their own voice from what the weapon actually is, so a
## new weapon gets a sensible report without a per-unit lookup table.
func play_weapon(stats: WeaponStats) -> void:
	if stats == null:
		return play("rifle_shot")
	_note_combat()
	## Order matters: a rocket is checked before the damage threshold,
	## because an AT launcher hits hard enough to be mistaken for a tank
	## gun and the launch whoosh is the whole character of the weapon.
	if stats.splash_radius > 0.0:
		play("artillery_shot")
	elif stats.damage_type == DamageTypes.Type.ANTI_ARMOR:
		play("at_launcher")
	elif stats.damage >= 60.0:
		play("cannon_shot")
	elif stats.attack_cooldown <= 0.35:
		play("mg_burst")
	else:
		play("rifle_shot")

func play_impact(stats: WeaponStats) -> void:
	if not enabled:
		return
	if stats != null and (stats.splash_radius > 0.0 or stats.damage >= 60.0):
		play("impact_shell")
	else:
		play("impact_small")

func _note_combat() -> void:
	_last_combat = Time.get_ticks_msec() / 1000.0

func _on_match_ended(victory: bool) -> void:
	play("victory" if victory else "defeat")
	## Nothing should keep droning under the after-action report.
	for bed in [_ambient, _calm, _combat]:
		if bed != null:
			bed.stop()

# ------------------------------------------------------------- music

func _process(delta: float) -> void:
	if _ambient == null:
		return
	var playing: bool = music_enabled and GameState.match_state == GameState.MatchState.PLAYING
	_fade(_ambient, BEDS["ambient_wind"] if playing else -80.0, delta)

	var now: float = Time.get_ticks_msec() / 1000.0
	_in_combat = now - _last_combat < COMBAT_HOLD
	_fade(_calm, BEDS["music_calm"] if playing and not _in_combat else -80.0, delta)
	_fade(_combat, BEDS["music_combat"] if playing and _in_combat else -80.0, delta)

## Linear dB glide. Crossfading in dB is not strictly correct but over
## this range it is inaudible, and it keeps the two beds summing to
## roughly one bed rather than briefly to none.
func _fade(player: AudioStreamPlayer, target: float, delta: float) -> void:
	if player == null or player.stream == null:
		return
	var step: float = (80.0 / FADE) * delta
	player.volume_db = move_toward(player.volume_db, target, step)

# --------------------------------------------------------- fallback

## Builds a mono 16-bit sample with a short attack and an exponential
## decay, which is what stops these reading as flat beeps.
func _synthesise(frequency: float, duration: float, waveform: String) -> AudioStreamWAV:
	var frames: int = int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(frequency * 100.0)

	for i in frames:
		var t: float = float(i) / float(SAMPLE_RATE)
		var phase: float = fmod(t * frequency, 1.0)
		var sample: float
		match waveform:
			"square":
				sample = 1.0 if phase < 0.5 else -1.0
			"saw":
				sample = phase * 2.0 - 1.0
			"noise":
				sample = rng.randf_range(-1.0, 1.0)
			_:
				sample = sin(TAU * frequency * t)

		var progress: float = float(i) / float(frames)
		var attack: float = clampf(progress / 0.04, 0.0, 1.0)
		var envelope: float = attack * pow(1.0 - progress, 2.2)
		var value: int = clampi(int(sample * envelope * 30000.0), -32768, 32767)
		data.encode_s16(i * 2, value)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
