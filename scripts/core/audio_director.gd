extends Node

## Autoload: placeholder sound effects, generated in code.
##
## No assets to source or license - each cue is a short synthesised tone
## shaped by an envelope, which is enough to answer "did that register?"
## for selection, orders and combat. The point is the architecture: every
## cue is requested by name through play(), so swapping in real audio
## later means filling the sample table, not touching gameplay code.

const SAMPLE_RATE: int = 22050
const MAX_VOICES: int = 12

## name -> [frequency Hz, seconds, waveform, volume dB]
const CUES: Dictionary = {
	"select":       [660.0, 0.06, "square", -18.0],
	"order":        [880.0, 0.07, "sine",   -16.0],
	"build_place":  [330.0, 0.16, "square", -14.0],
	"build_done":   [520.0, 0.22, "sine",   -12.0],
	"unit_ready":   [740.0, 0.16, "sine",   -14.0],
	"attack":       [180.0, 0.05, "noise",  -22.0],
	"explosion":    [80.0,  0.35, "noise",  -10.0],
	"low_power":    [140.0, 0.45, "saw",    -12.0],
	"victory":      [720.0, 0.8,  "sine",   -8.0],
	"defeat":       [150.0, 0.9,  "saw",    -8.0],
}

var enabled: bool = true

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0

func _ready() -> void:
	for cue in CUES:
		_streams[cue] = _synthesise(CUES[cue][0], CUES[cue][1], CUES[cue][2])
	for i in MAX_VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

	EventBus.building_placed.connect(func(_b): play("build_place"))
	EventBus.unit_spawned.connect(func(_u): play("unit_ready"))
	EventBus.command_issued.connect(func(_t, _p): play("order"))
	EventBus.building_sold.connect(func(_b): play("build_place"))
	EventBus.construction_ready.connect(func(_s): play("build_done"))
	GameState.selection_changed.connect(func(s): if not s.is_empty(): play("select"))
	GameState.match_ended.connect(func(v): play("victory" if v else "defeat"))

## Round-robin voices so a burst of events never cuts itself off.
func play(cue: String) -> void:
	if not enabled or not _streams.has(cue):
		return
	var player: AudioStreamPlayer = _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	player.stream = _streams[cue]
	player.volume_db = CUES[cue][3]
	player.play()

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
