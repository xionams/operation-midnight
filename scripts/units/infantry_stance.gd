extends Node
class_name InfantryStance

## Infantry posture: RUN or CROUCH.
##
##   RUN     the default. Full speed; the unit's baseline firepower.
##   CROUCH  slow, but steadier and harder-hitting - a firing position.
##
## The numbers live in StanceModifiers resources (config/stances/), set
## per unit type on UnitStats or taken from the shared defaults, so
## balance is tuned in data. This node only remembers which profile is
## active. Movement and weapons ask `modifiers_of(unit)` and multiply,
## which keeps posture out of every other script.
##
## Not to be confused with UnitBase.stance (HOLD / DEFENSIVE /
## AGGRESSIVE), which is about how far a unit will chase - an orthogonal
## choice. A crouched squad can still be told to hold or to hunt.

signal mode_changed(mode: int)

enum Mode { RUN, CROUCH }

const DEFAULT_RUN: StanceModifiers = preload("res://config/stances/infantry_run.tres")
const DEFAULT_CROUCH: StanceModifiers = preload("res://config/stances/infantry_crouch.tres")
## Returned for anything with no posture at all (vehicles, buildings).
static var _neutral: StanceModifiers = null

@export var run_profile: StanceModifiers = DEFAULT_RUN
@export var crouch_profile: StanceModifiers = DEFAULT_CROUCH

var mode: int = Mode.RUN

func set_mode(new_mode: int) -> void:
	if new_mode == mode or not Mode.values().has(new_mode):
		return
	mode = new_mode
	mode_changed.emit(mode)

func toggle() -> void:
	set_mode(Mode.CROUCH if mode == Mode.RUN else Mode.RUN)

func is_crouched() -> bool:
	return mode == Mode.CROUCH

func modifiers() -> StanceModifiers:
	var profile: StanceModifiers = crouch_profile if mode == Mode.CROUCH else run_profile
	return profile if profile != null else neutral()

static func mode_name(value: int) -> String:
	return String(Mode.keys()[value]).capitalize() if Mode.values().has(value) else "-"

static func neutral() -> StanceModifiers:
	if _neutral == null:
		_neutral = StanceModifiers.new()
	return _neutral

## The one lookup every consumer uses. Units without a posture get the
## neutral profile, so callers never branch on "is this infantry".
static func modifiers_of(unit: Node) -> StanceModifiers:
	if unit == null or not is_instance_valid(unit):
		return neutral()
	var stance: InfantryStance = unit.get_node_or_null("InfantryStance")
	return stance.modifiers() if stance != null else neutral()

static func of(unit: Node) -> InfantryStance:
	if unit == null or not is_instance_valid(unit):
		return null
	return unit.get_node_or_null("InfantryStance")
