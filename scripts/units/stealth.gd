extends Node
class_name Stealth

## Submerged stealth: the submarine's defining trait.
##
## A stealthed unit is invisible and untargetable to the other side
## unless it is EXPOSED, which happens two ways:
##   - an enemy sonar source is within range: anything whose stats carry a
##     `sonar_range` (Patrol Boats, Sonar Buoys) exposes it while in range
##   - it fires: surfacing to launch torpedoes leaves it exposed for
##     SURFACE_TIME seconds, so a submarine that attacks can be answered
##
## Exposure is the whole rule. Every "can I see / pick / shoot this?"
## question asks Stealth.visible_to(), the same way disguised Spies are
## asked through DisguiseAbility.visible_to(), so no system needs its own
## submarine special case. While hidden the unit also counts as
## SUBMERGED for weapon domains (see CombatTarget.domain_of), which is
## what keeps land guns off it even when exposed.

signal exposure_changed(exposed: bool)

const SURFACE_TIME: float = 3.0
const SCAN_INTERVAL: float = 0.25

var _unit: Node3D
var _surfaced_for: float = 0.0
var _detected: bool = false
var _scan_timer: float = 0.0
var _was_exposed: bool = false

func _ready() -> void:
	_unit = get_parent() as Node3D
	_scan_timer = randf() * SCAN_INTERVAL

## Called by the unit's weapon whenever it fires.
func surface() -> void:
	_surfaced_for = SURFACE_TIME
	_notify()

func is_surfaced() -> bool:
	return _surfaced_for > 0.0

func is_exposed() -> bool:
	return _surfaced_for > 0.0 or _detected

func _process(delta: float) -> void:
	if _surfaced_for > 0.0:
		_surfaced_for = maxf(_surfaced_for - delta, 0.0)
	_apply_depth_visual()
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_detected = _in_enemy_sonar()
	_notify()

## What the OWNER sees: a submerged boat is drawn ghosted (and sits lower
## in the water, see UnitBase._settle_on_ground), a surfaced one solid.
## The enemy does not see it at all while hidden - that is FogHideable.
var _drawn_submerged: int = -1

func _apply_depth_visual() -> void:
	var submerged: int = 0 if is_surfaced() else 1
	if submerged == _drawn_submerged or _unit == null:
		return
	_drawn_submerged = submerged
	## Re-settle now rather than after the next half-metre of travel, so a
	## stationary submarine visibly rises to fire and sinks again.
	_unit.set("_settled_at", Vector3.INF)
	for node in _unit.find_children("*", "GeometryInstance3D", true, false):
		if node is Label3D or node.name.begins_with("Health") \
			or node.get_parent().name.begins_with("Health") or node == _unit.get("selection_ring"):
			continue
		(node as GeometryInstance3D).transparency = 0.55 if submerged == 1 else 0.0

func _notify() -> void:
	var exposed := is_exposed()
	if exposed != _was_exposed:
		_was_exposed = exposed
		exposure_changed.emit(exposed)

func _in_enemy_sonar() -> bool:
	if _unit == null or not _unit.is_inside_tree():
		return false
	var mine: bool = _unit.get("is_player_faction") == true
	var enemy_side: String = "enemy" if mine else "player"
	for group in [enemy_side + "_units", enemy_side + "_buildings"]:
		for source in _unit.get_tree().get_nodes_in_group(group):
			if not is_instance_valid(source):
				continue
			var stats = source.get("stats")
			if stats == null:
				continue
			var sonar = stats.get("sonar_range")
			if sonar == null or sonar <= 0.0:
				continue
			if source.global_position.distance_to(_unit.global_position) <= sonar:
				return true
	return false

## May `viewer` (the player side if true) see and target this entity?
## Anything without a Stealth node is always visible; a side always sees
## its own units.
static func visible_to(target: Node, viewer_is_player: bool) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var stealth: Stealth = target.get_node_or_null("Stealth")
	if stealth == null:
		return true
	if target.get("is_player_faction") == viewer_is_player:
		return true
	return stealth.is_exposed()

## True while the entity is running submerged (hidden or merely detected
## but not surfaced). Surfaced submarines are ordinary ships.
static func is_submerged(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var stealth: Stealth = target.get_node_or_null("Stealth")
	return stealth != null and not stealth.is_surfaced()
