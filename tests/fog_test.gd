extends Node

## Verifies the visibility model: permanent exploration, decaying current
## vision, and enemies genuinely disappearing rather than being dimmed.

const SCOUT := preload("res://scenes/units/scout_vehicle.tscn")
const SCOUT_STATS := preload("res://config/units/scout_vehicle.tres")
const TANK := preload("res://scenes/units/assault_vehicle.tscn")
const TANK_STATS := preload("res://config/units/assault_vehicle.tres")

var _main: Node3D
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	await get_tree().process_frame
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-48s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _spawn(scene: PackedScene, stats: UnitStats, player: bool, pos: Vector3) -> Node:
	var u = scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	return u

func _run() -> void:
	# --- map scale and opening knowledge ---
	_check("Map is 220m", is_equal_approx(FogOfWar.get_map_size(), 220.0),
		"(%.0f)" % FogOfWar.get_map_size())
	_check("Fog grid is 110x110 cells", FogOfWar.get_side() == 110,
		"(%d)" % FogOfWar.get_side())

	var explored: float = FogOfWar.explored_fraction()
	_check("Match starts mostly unexplored", explored < 0.15,
		"(%.1f%% explored)" % (explored * 100.0))

	_check("Player base area starts explored",
		FogOfWar.is_explored_at(Vector3(-78, 0, 62)))
	_check("Enemy base starts unexplored",
		not FogOfWar.is_explored_at(Vector3(76, 0, -70)))
	_check("Central resource field starts unexplored",
		not FogOfWar.is_explored_at(Vector3(6, 0, 6)))

	# --- exploration by movement ---
	var far := Vector3(-78, 0, -10)
	_check("Target area starts unexplored", not FogOfWar.is_explored_at(far))

	var scout = _spawn(SCOUT, SCOUT_STATS, true, Vector3(-78, 0, 40))
	scout.move_to(far)
	var reached := false
	for i in 900:
		await get_tree().physics_frame
		if scout.global_position.distance_to(far) < 6.0:
			reached = true
			break
	_check("Scout reaches the unexplored area", reached,
		"(at %.0f,%.0f)" % [scout.global_position.x, scout.global_position.z])
	FogOfWar.update_now()
	_check("Scouting reveals the area", FogOfWar.is_explored_at(far))
	_check("Area is currently visible while the scout is there",
		FogOfWar.is_visible_at(far))

	# --- exploration is permanent, vision is not ---
	scout.global_position = Vector3(-78, 0, 62)
	FogOfWar.update_now()
	_check("Area stays explored after the scout leaves", FogOfWar.is_explored_at(far))
	_check("Area is no longer currently visible", not FogOfWar.is_visible_at(far))

	# --- camera does not reveal ---
	var camera := get_tree().get_first_node_in_group("rts_camera")
	var secret := Vector3(60, 0, -60)
	camera.focus_on(secret)
	for i in 20:
		await get_tree().process_frame
	FogOfWar.update_now()
	_check("Moving the camera does NOT reveal terrain", not FogOfWar.is_explored_at(secret))

	# --- enemies hide and reveal ---
	var enemy = _spawn(TANK, TANK_STATS, false, Vector3(-40, 0, 62))
	await get_tree().process_frame
	FogOfWar.update_now()
	await get_tree().process_frame
	_check("Enemy outside vision is hidden", FogHideable.is_hidden(enemy))
	_check("Hidden enemy is not visible in the scene", not enemy.visible)
	_check("Hidden enemy cannot be hit by a pick ray", enemy.collision_layer == 0)

	var watcher = _spawn(TANK, TANK_STATS, true, Vector3(-44, 0, 62))
	await get_tree().process_frame
	FogOfWar.update_now()
	await get_tree().process_frame
	_check("Enemy inside vision becomes visible", not FogHideable.is_hidden(enemy))
	_check("Revealed enemy is selectable/targetable again", enemy.collision_layer != 0)

	# --- targeting refuses what the player cannot see ---
	watcher.global_position = Vector3(-78, 0, 62)
	FogOfWar.update_now()
	await get_tree().process_frame
	_check("Enemy hides again when the watcher withdraws", FogHideable.is_hidden(enemy))
	var attacker: AttackerComponent = watcher.get_node("AttackerComponent")
	attacker.set_target(enemy)
	_check("Cannot target an enemy hidden by fog", not attacker.has_target())

	# --- vision range actually differs per unit ---
	_check("Scout sees further than an Assault Vehicle",
		SCOUT_STATS.vision_range > TANK_STATS.vision_range,
		"(%.0f vs %.0f)" % [SCOUT_STATS.vision_range, TANK_STATS.vision_range])
