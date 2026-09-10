extends BuildingBase
class_name DefenseTower

## A structure that shoots. Reuses the exact AttackerComponent + Weapon
## pair units carry, so a tower acquires, leads and damages targets by
## the same rules and the same armour table - a Machine Gun Tower is
## therefore genuinely weak against armour rather than weak by a special
## case written into tower code.
##
## Towers are the visible face of LOW POWER: when the grid is short they
## stop firing entirely, which is what turns a power shortage into a
## breach rather than a number on the HUD.

const SCAN_INTERVAL: float = 0.4

var attacker: AttackerComponent
var weapon: Weapon

var _scan_timer: float = 0.0

func _ready() -> void:
	super._ready()
	if stats == null or stats.weapon_stats == null:
		return
	weapon = Weapon.new()
	weapon.name = "Weapon"
	weapon.stats = stats.weapon_stats
	add_child(weapon)

	attacker = AttackerComponent.new()
	attacker.name = "AttackerComponent"
	attacker.weapon = weapon
	add_child(attacker)

func is_offline() -> bool:
	return GameState.is_low_power(is_player_faction)

func _process(delta: float) -> void:
	super._process(delta)
	if attacker == null:
		return

	## Offline towers drop their target and stop scanning, so the player
	## sees defences fall silent the moment the grid browns out.
	if is_offline():
		attacker.clear_target()
		return

	if attacker.has_target():
		return
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = SCAN_INTERVAL
	var target := _nearest_hostile()
	if target != null:
		attacker.set_target(target)

func _nearest_hostile() -> Node:
	var group: String = "enemy_units" if is_player_faction else "player_units"
	var best: Node = null
	var best_dist: float = INF
	for candidate in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(candidate):
			continue
		if is_player_faction and FogHideable.is_hidden(candidate):
			continue
		if not DisguiseAbility.visible_to(candidate, is_player_faction):
			continue
		if not weapon.can_damage(candidate):
			continue
		var dist: float = global_position.distance_to(candidate.global_position)
		if dist > stats.weapon_stats.attack_range or dist >= best_dist:
			continue
		best_dist = dist
		best = candidate
	return best
