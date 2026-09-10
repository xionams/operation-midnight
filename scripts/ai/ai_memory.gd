extends Node
class_name AIMemory

## What the AI has actually observed, and when.
##
## This exists so the AI can be smart without cheating. It only ever
## records things its own units and structures could see at the time, and
## every record decays: a base sighted two minutes ago is a guess, not a
## fact. The AI is therefore wrong in the same ways a human is - it can
## be baited, and it can be surprised by an army that moved through fog.
##
## Nothing here reads player state directly. Observations are pushed in
## by the scan below, which is gated on the AI's own vision.

const CONFIDENCE_HALFLIFE: float = 45.0
const SCAN_INTERVAL: float = 1.0
const FORGET_AFTER: float = 240.0

## display_name -> {count, last_seen}
var seen_units: Dictionary = {}
var seen_buildings: Dictionary = {}

var player_base_guess: Vector3 = Vector3.ZERO
var has_base_guess: bool = false
var known_resource_fields: Array[Vector3] = []
var recent_attack_positions: Array[Vector3] = []
var losses: Array[Vector3] = []

var _timer: float = 0.0
var _now: float = 0.0

func _process(delta: float) -> void:
	_now += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = SCAN_INTERVAL
	_observe()

## Anything within vision of an AI unit or structure is fair to record.
## This is the only place enemy state enters the AI at all.
func _observe() -> void:
	var eyes: Array = get_tree().get_nodes_in_group("enemy_units")
	eyes.append_array(get_tree().get_nodes_in_group("enemy_buildings"))
	if eyes.is_empty():
		return

	var fresh_units: Dictionary = {}
	for target in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(target) or target.stats == null:
			continue
		if not _visible_to_any(eyes, target.global_position):
			continue
		var key: String = target.stats.display_name
		fresh_units[key] = fresh_units.get(key, 0) + 1

	for key in fresh_units:
		seen_units[key] = {"count": fresh_units[key], "last_seen": _now}

	for target in get_tree().get_nodes_in_group("player_buildings"):
		if not is_instance_valid(target) or target.stats == null:
			continue
		if not _visible_to_any(eyes, target.global_position):
			continue
		seen_buildings[target.stats.display_name] = {
			"position": target.global_position, "last_seen": _now}
		if target.stats.display_name == "Command Headquarters":
			player_base_guess = target.global_position
			has_base_guess = true

	for field in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(field):
			continue
		if not _visible_to_any(eyes, field.global_position):
			continue
		if not known_resource_fields.any(func(p): return p.distance_to(field.global_position) < 6.0):
			known_resource_fields.append(field.global_position)

func _visible_to_any(eyes: Array, point: Vector3) -> bool:
	for eye in eyes:
		if not is_instance_valid(eye) or eye.stats == null:
			continue
		if eye.global_position.distance_to(point) <= eye.stats.vision_range:
			return true
	return false

## Old sightings are worth less. Used to weight counter-production so the
## AI reacts to what it saw recently rather than to ancient history.
func confidence(record: Dictionary) -> float:
	if record.is_empty():
		return 0.0
	var age: float = _now - record.get("last_seen", 0.0)
	if age > FORGET_AFTER:
		return 0.0
	return pow(0.5, age / CONFIDENCE_HALFLIFE)

## Rough read of what the player fields, weighted by how recently each
## sighting happened. Returns fractions that sum to about 1.
func estimated_composition() -> Dictionary:
	var weights: Dictionary = {"infantry": 0.0, "vehicle": 0.0, "armor": 0.0}
	var total: float = 0.0
	for key in seen_units:
		var record: Dictionary = seen_units[key]
		var weight: float = confidence(record) * float(record.get("count", 0))
		if weight <= 0.0:
			continue
		total += weight
		match key:
			"Rifle Squad", "Anti-Armor Squad", "Engineer", "Spy", "Attack Dog":
				weights["infantry"] += weight
			"Main Battle Tank":
				weights["armor"] += weight
			_:
				weights["vehicle"] += weight
	if total <= 0.0:
		return weights
	for key in weights:
		weights[key] /= total
	return weights

func record_attack_at(position: Vector3) -> void:
	recent_attack_positions.append(position)
	if recent_attack_positions.size() > 8:
		recent_attack_positions.pop_front()

func record_loss_at(position: Vector3) -> void:
	losses.append(position)
	if losses.size() > 12:
		losses.pop_front()

func has_seen_building(display_name: String) -> bool:
	return seen_buildings.has(display_name) \
		and confidence(seen_buildings[display_name]) > 0.15
