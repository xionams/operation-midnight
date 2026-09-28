extends Node

## The Phase 3 visual record: ten in-game frames from the real RTS
## camera, on the Coastline map, under match lighting.
##
##   OM_SHOT=<dir> godot res://tests/phase3_shots.tscn
##
## The scene is staged rather than played to that point (the complete
## match is proved separately by tests/coastal_match_test), so each
## shot shows its subject deliberately. Units are live: guns fire,
## ships make wakes, the submarine is really submerged, and damage
## states come from real damage. Fog of war is lifted so the frames show
## the art rather than the shroud, and only the wide establishing shot
## pulls the camera out past the gameplay zoom limit.

const L := "res://config/units/"
const B := "res://config/buildings/"

var _main: Node3D
var _out: String

func _ready() -> void:
	GameState.selected_map = load("res://config/maps/coastline.tres")
	_main = get_parent()
	_out = OS.get_environment("OM_SHOT")
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://screenshots/phase3")
	DirAccess.make_dir_recursive_absolute(_out)
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	## Lift the shroud: stop fog updates, then mark the whole map seen.
	FogOfWar.enabled = false
	FogOfWar.reveal_area(Vector3.ZERO, FogOfWar.get_map_size())
	GameState.credits = 99999
	await _stage()
	await _shoot_all()
	get_tree().quit()

func _u(id: String) -> UnitStats:
	return load(L + id + ".tres")

func _b(id: String) -> BuildingStats:
	return load(B + id + ".tres")

func _spawn(id: String, player: bool, pos: Vector3, yaw: float = 0.0) -> Node:
	var stats := _u(id)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	var y: float = Water.level if stats.movement_domain == PlacementDomain.Domain.WATER \
		else Terrain.height_at(pos.x, pos.z)
	u.global_position = Vector3(pos.x, y, pos.z)
	u.rotation.y = deg_to_rad(yaw)
	return u

func _build(id: String, player: bool, pos: Vector3) -> Node:
	var stats := _b(id)
	var b = stats.scene.instantiate()
	b.stats = stats
	b.is_player_faction = player
	if id.begins_with("civilian"):
		b.is_neutral = true
	_main.get_node("Level/NavRegion").add_child(b)
	b.global_position = Vector3(pos.x, PlacementDomain.surface_y(stats, pos.x, pos.z), pos.z)
	EventBus.building_placed.emit(b)
	return b

func _hurt(n: Node, fraction_left: float) -> void:
	var h = n.get("health")
	if h != null:
		h.current_health = h.max_health * fraction_left
		h.health_changed.emit(h.current_health, h.max_health)

func _hold(n: Node) -> Node:
	var gun = n.get_node_or_null("AttackerComponent")
	if gun != null:
		gun.set_physics_process(false)
	return n

var _patrol: Node
var _sub: Node

func _stage() -> void:
	# --- the player's base, grown to mid-game -------------------------
	_build("power_plant", true, Vector3(-62, 0, -36))
	_build("power_plant", true, Vector3(-62, 0, -28))
	_build("refinery", true, Vector3(-60, 0, -12))
	_build("barracks", true, Vector3(-96, 0, -34))
	_build("war_factory", true, Vector3(-98, 0, -12))
	var hurt_factory = _build("barracks", true, Vector3(-80, 0, -42))
	_hurt(hurt_factory, 0.45)
	for i in 8:
		_build("wall", true, Vector3(-106 + i * 2, 0, 4))
	_build("gate", true, Vector3(-90, 0, 4))
	for i in 5:
		_build("wall", true, Vector3(-88 + i * 2, 0, 4))
	# --- a squad and armour on the base apron -------------------------
	for i in 3:
		_hold(_spawn("rifle_soldier", true, Vector3(-74 + i * 1.6, 0, -6), 200))
	_hold(_spawn("at_squad", true, Vector3(-74, 0, -3.5), 200))
	_hold(_spawn("engineer", true, Vector3(-71, 0, -3.5), 200))
	_hold(_spawn("main_battle_tank", true, Vector3(-80, 0, -4), 160))
	_hold(_spawn("main_battle_tank", true, Vector3(-84, 0, -2), 160))
	_hold(_spawn("scout_vehicle", true, Vector3(-68, 0, -1), 140))
	_hold(_spawn("assault_vehicle", true, Vector3(-88, 0, -6), 170))
	_hold(_spawn("artillery_vehicle", true, Vector3(-92, 0, 0), 180))
	# --- a town -------------------------------------------------------
	_build("civilian_structure", false, Vector3(-30, 0, -60))
	_build("civilian_house", false, Vector3(-48, 0, -56))
	_build("civilian_warehouse", false, Vector3(-38, 0, -76))
	_build("civilian_house", false, Vector3(-22, 0, -70))
	# --- the coast: yard, buoy, a patrol and a submarine ---------------
	_build("naval_yard", true, Vector3(-80, 0, 28))
	_build("sonar_buoy", true, Vector3(-60, 0, 32))
	_patrol = _spawn("patrol_boat", true, Vector3(-100, 0, 40), 90)
	_sub = _spawn("submarine", true, Vector3(-66, 0, 46), 70)
	_hold(_spawn("patrol_boat", true, Vector3(-74, 0, 40), 100))
	# --- a naval engagement off the centre coast ----------------------
	for i in 2:
		_spawn("patrol_boat", true, Vector3(-28 + i * 5, 0, 52 + i * 3), 90)
		_spawn("patrol_boat", false, Vector3(-8 + i * 5, 0, 56 - i * 3), -90)
	_spawn("submarine", false, Vector3(-4, 0, 50), -90)
	# --- a land battle in the middle -----------------------------------
	for i in 3:
		_spawn("main_battle_tank", true, Vector3(6, 0, -24 + i * 5), 90)
		_spawn("main_battle_tank", false, Vector3(26, 0, -26 + i * 5), -90)
	for i in 4:
		_spawn("rifle_soldier", true, Vector3(2, 0, -26 + i * 3), 90)
		_spawn("rifle_soldier", false, Vector3(30, 0, -28 + i * 3), -90)
	_spawn("assault_vehicle", false, Vector3(28, 0, -12), -90)
	await get_tree().create_timer(1.0).timeout
	_sub.issue_command(CommandTypes.Type.MOVE, Vector3(-40, 0, 60))

func _cam() -> Node:
	return get_tree().get_first_node_in_group("rts_camera")

func _shot(name: String, at: Vector3, zoom: float, wait: float = 1.0) -> void:
	var cam = _cam()
	cam.zoom_distance = zoom
	cam.focus_on(at)
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("SHOT| %s" % name)

func _shoot_all() -> void:
	var cam = _cam()
	await _shot("01_main_base", Vector3(-82, 0, -18), 45.0, 2.0)
	await _shot("02_infantry_and_vehicles", Vector3(-78, 0, -4), 16.0)
	await _shot("03_civilian_area", Vector3(-36, 0, -64), 26.0)
	await _shot("04_coastline", Vector3(-60, 0, 22), 45.0)
	await _shot("05_naval_yard", Vector3(-80, 0, 28), 22.0)
	_patrol.issue_command(CommandTypes.Type.MOVE, Vector3(-40, 0, 44))
	await get_tree().create_timer(2.5).timeout
	await _shot("06_patrol_boat", _patrol.global_position + Vector3(4, 0, 0), 14.0, 0.6)
	await _shot("07_submarine", _sub.global_position, 14.0, 0.6)
	await _shot("08_naval_combat", Vector3(-16, 0, 54), 30.0, 2.0)
	await _shot("09_land_battle", Vector3(16, 0, -20), 30.0, 1.0)
	cam.max_zoom = 110.0
	await _shot("10_wide_land_and_sea", Vector3(-40, 0, 0), 110.0, 1.5)
	cam.max_zoom = 45.0
	print("SHOT| done")
