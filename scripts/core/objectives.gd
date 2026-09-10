extends Node
class_name Objectives

## Drives the match's sense of progression. Each stage names what to do
## next and watches for its own completion, so the player always has a
## concrete instruction rather than an empty sandbox.
##
## Stages are checked on a slow timer against real world state - what is
## standing, what has been explored - rather than being fired by the
## systems that satisfy them, which keeps objectives a read-only observer
## that no gameplay code has to know about.

const CHECK_INTERVAL: float = 1.0

var _stage: int = -1
var _timer: float = 0.0

func _ready() -> void:
	## Deferred: this node is built before the HUD, so emitting straight
	## away would fire into a signal nobody has connected to yet and the
	## player would start the match with an empty objective panel.
	_advance.call_deferred(0)

func _process(delta: float) -> void:
	if GameState.match_state != GameState.MatchState.PLAYING:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	if _is_stage_complete(_stage):
		_advance(_stage + 1)

func _has(display_name: String) -> bool:
	for building in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(building) and building.stats != null \
			and building.stats.display_name == display_name:
			return true
	return false

func _is_stage_complete(stage: int) -> bool:
	match stage:
		0:
			return _has("Power Plant") and _has("Resource Refinery")
		1:
			return _has("Barracks") and _has("Vehicle Factory")
		2:
			## Enough of the map seen to have found something worth finding.
			return FogOfWar.explored_fraction() > 0.28
		3:
			## Final objective stands until the match itself ends.
			return false
	return false

func _advance(stage: int) -> void:
	if stage == _stage:
		return
	_stage = stage
	match stage:
		0:
			_emit("OBJECTIVE", ["Construct a Power Plant", "Construct a Resource Refinery"])
		1:
			_emit("OBJECTIVE UPDATED", ["Construct a Barracks", "Construct a Vehicle Factory"])
		2:
			_emit("OBJECTIVE UPDATED", ["Explore the battlefield", "Locate hostile forces"])
		3:
			_emit("FINAL OBJECTIVE", ["Destroy the enemy Command Headquarters"])

func _emit(title: String, lines: Array) -> void:
	EventBus.objective_changed.emit(title, PackedStringArray(lines))
