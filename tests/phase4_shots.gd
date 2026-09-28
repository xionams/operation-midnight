extends Node

## Phase 4's changes, photographed from the normal gameplay camera.
##
## Deliberately NOT a beauty pass from a hand-picked angle: every shot is
## taken at a zoom a player actually uses, because the whole claim being
## made is that the battle reads better from where the game is played.

const COAST := preload("res://config/maps/coastline.tres")
const SHOTS := "res://screenshots/phase4"

const LAND := [
	"res://config/units/rifle_soldier.tres",
	"res://config/units/at_squad.tres",
	"res://config/units/assault_vehicle.tres",
	"res://config/units/main_battle_tank.tres",
	"res://config/units/artillery_vehicle.tres",
]

var _main: Node3D

func _ready() -> void:
	GameState.selected_map = COAST
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	## Switching the fog OFF does not clear what is UNEXPLORED - the
	## terrain shader still paints never-seen ground black, which had the
	## entire sea rendering as a void in the naval captures. Reveal the
	## map as well.
	FogOfWar.enabled = false
	FogOfWar.reveal_area(Vector3.ZERO, COAST.size * 1.5)
	FogOfWar.update_now()
	GameState.add_credits(90000)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	## Let the intro card fade; it dims every frame it is up.
	await _wait(7.0)

	await _infantry_advance()
	await _firefight()
	await _artillery_and_rockets()
	## Naval before the base burns: the burning scenario takes structures
	## to the edge of destruction, and anything already chewed on in the
	## firefight can tip over it - which ends the match and drops the
	## defeat card over every shot after it.
	await _naval_action()
	await _burning_base()

	print("SHOT| DONE")
	GameState.selected_map = null
	get_tree().quit()

func _wait(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		t += get_process_delta_time()
		await get_tree().process_frame

func _cam():
	return get_tree().get_first_node_in_group("rts_camera")

func _spawn(path: String, player: bool, at: Vector3) -> Node:
	var stats: UnitStats = load(path)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(at.x, Terrain.height_at(at.x, at.z), at.z)
	return u

func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [SHOTS, name])
	print("SHOT| %s" % name)

## Infantry on the move, half of them crouched: the posture difference
## has to be visible at the zoom a player fights at.
func _infantry_advance() -> void:
	var base: Vector3 = COAST.player_base
	var squad: Array = []
	for i in 10:
		var u = _spawn(LAND[i % 2], true,
			base + Vector3(-8.0 + float(i % 5) * 3.2, 0, 6.0 + float(i / 5) * 4.0))
		if i >= 5:
			var st = InfantryStance.of(u)
			if st != null:
				st.set_mode(InfantryStance.Mode.CROUCH)
		squad.append(u)
	await _wait(1.0)
	for u in squad:
		u.move_to(u.global_position + Vector3(0, 0, -26))
	_cam().focus_on(base + Vector3(0, 0, 2))
	_cam().zoom_distance = 22.0
	_cam().snap()
	await _wait(2.2)
	await _shoot("01_infantry_run_and_crouch")

## Small arms and cannon in contact.
func _firefight() -> void:
	var base: Vector3 = COAST.player_base
	for i in 8:
		_spawn(LAND[i % 4], false, base + Vector3(-6.0 + float(i) * 2.6, 0, -22.0))
	await _wait(4.0)
	_cam().focus_on(base + Vector3(0, 0, -12))
	_cam().zoom_distance = 28.0
	_cam().snap()
	await _wait(3.0)
	await _shoot("02_firefight")

## The two weapons whose rounds are meant to be unmistakable: a lobbed
## shell and a rocket with a trail behind it.
func _artillery_and_rockets() -> void:
	var base: Vector3 = COAST.player_base
	for i in 3:
		_spawn("res://config/units/artillery_vehicle.tres", true,
			base + Vector3(-10.0 + float(i) * 5.0, 0, 10.0))
		_spawn("res://config/units/at_squad.tres", true,
			base + Vector3(-8.0 + float(i) * 5.0, 0, 5.0))
	await _wait(1.0)
	_cam().focus_on(base + Vector3(0, 0, -6))
	_cam().zoom_distance = 34.0
	_cam().snap()
	await _wait(5.0)
	await _shoot("03_artillery_and_rockets")
	await _wait(2.0)
	await _shoot("04_ordnance_in_flight")

## Critical damage: buildings burning, wrecks and bodies on the ground.
func _burning_base() -> void:
	var base: Vector3 = COAST.player_base
	## Damage DOWN TO a critical fraction rather than subtracting one: a
	## structure the firefight had already hurt would otherwise be
	## finished off, and losing the HQ ends the match mid-photoshoot.
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if not is_instance_valid(b) or b.health == null:
			continue
		var want: float = b.health.max_health * 0.22
		if b.health.current_health > want:
			b.health.take_damage(b.health.current_health - want)
	await _wait(2.5)
	_cam().focus_on(base)
	_cam().zoom_distance = 26.0
	_cam().snap()
	await _wait(1.5)
	await _shoot("05_base_under_fire")

## The sea: hulls, wakes, and a boat going down.
func _naval_action() -> void:
	var sea: Vector3 = Water.nearest_water(COAST.player_base + Vector3(0, 0, 64), 150.0)
	var fleet: Array = []
	for i in 6:
		var u = _spawn("res://config/units/patrol_boat.tres", i % 2 == 0,
			Vector3(sea.x - 9.0 + float(i) * 3.6, 0, sea.z + float(i % 2) * 5.0))
		u.global_position = Vector3(u.global_position.x, Water.level, u.global_position.z)
		fleet.append(u)
	await _wait(1.0)
	for u in fleet:
		u.move_to(u.global_position + Vector3(14, 0, 4))
	_cam().focus_on(sea)
	_cam().zoom_distance = 26.0
	_cam().snap()
	await _wait(3.0)
	await _shoot("06_naval_wakes")
	if fleet.size() > 1 and is_instance_valid(fleet[1]):
		fleet[1].health.take_damage(99999.0)
	await _wait(0.9)
	await _shoot("07_ship_going_down")
