extends Node

## Stages the scenarios the art pass is meant to be judged on.
##
## The plain screenshot tour photographs a passive match, where the player
## builds nothing - so "resource harvesting", "combat" and "defensive
## walls" were pictures of empty grass. This spawns a real tableau with
## the game's own scenes and stats, reveals the fog over it, and
## photographs each one.

const BUILDINGS: Dictionary = {
	"power_plant": ["res://scenes/buildings/power_plant.tscn", "res://config/buildings/power_plant.tres"],
	"refinery": ["res://scenes/buildings/refinery.tscn", "res://config/buildings/refinery.tres"],
	"barracks": ["res://scenes/buildings/barracks.tscn", "res://config/buildings/barracks.tres"],
	"war_factory": ["res://scenes/buildings/war_factory.tscn", "res://config/buildings/war_factory.tres"],
	"radar": ["res://scenes/buildings/radar_center.tscn", "res://config/buildings/radar_center.tres"],
	"tech": ["res://scenes/buildings/tech_center.tscn", "res://config/buildings/tech_center.tres"],
	"wall": ["res://scenes/buildings/wall.tscn", "res://config/buildings/wall.tres"],
	"gate": ["res://scenes/buildings/gate.tscn", "res://config/buildings/gate.tres"],
	"mg_tower": ["res://scenes/buildings/defense_tower.tscn", "res://config/buildings/mg_tower.tres"],
	"at_turret": ["res://scenes/buildings/defense_tower.tscn", "res://config/buildings/at_turret.tres"],
}

const UNITS: Dictionary = {
	"tank": ["res://scenes/units/main_battle_tank.tscn", "res://config/units/main_battle_tank.tres"],
	"artillery": ["res://scenes/units/artillery_vehicle.tscn", "res://config/units/artillery_vehicle.tres"],
	"assault": ["res://scenes/units/assault_vehicle.tscn", "res://config/units/assault_vehicle.tres"],
	"scout": ["res://scenes/units/scout_vehicle.tscn", "res://config/units/scout_vehicle.tres"],
	"harvester": ["res://scenes/units/harvester.tscn", "res://config/units/harvester.tres"],
	"rifle": ["res://scenes/units/rifle_soldier.tscn", "res://config/units/rifle_soldier.tres"],
	"at_squad": ["res://scenes/units/at_squad.tscn", "res://config/units/at_squad.tres"],
}

const PLAYER_BASE := Vector3(-78, 0, 62)
const ENEMY_BASE := Vector3(76, 0, -70)
const ORE_A := Vector3(-56, 0, 34)
const CENTRE := Vector3(6, 0, 6)

var _main: Node3D
var _camera: Node3D

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	_camera = _main.find_child("RTSCamera", true, false)
	_stage()
	## Reveal everything being photographed: the shroud is correct
	## behaviour but it is not what this pass is being judged on.
	for point in [PLAYER_BASE, ENEMY_BASE, ORE_A, CENTRE]:
		FogOfWar.reveal_area(point, 60.0)
	FogOfWar.update_now()
	await _run()
	get_tree().quit()

func _building(kind: String, position: Vector3, is_player: bool) -> Node:
	var entry: Array = BUILDINGS[kind]
	return _main._spawn_building(load(entry[0]), load(entry[1]), is_player, position)

func _unit(kind: String, position: Vector3, is_player: bool) -> Node:
	var entry: Array = UNITS[kind]
	return _main._spawn_unit(load(entry[0]), load(entry[1]), is_player, position)

func _stage() -> void:
	# A developed player base.
	_building("power_plant", PLAYER_BASE + Vector3(16, 0, 2), true)
	_building("power_plant", PLAYER_BASE + Vector3(16, 0, 12), true)
	_building("refinery", PLAYER_BASE + Vector3(2, 0, -16), true)
	_building("barracks", PLAYER_BASE + Vector3(-16, 0, 2), true)
	_building("war_factory", PLAYER_BASE + Vector3(-17, 0, -16), true)
	_building("radar", PLAYER_BASE + Vector3(16, 0, -14), true)
	_building("tech", PLAYER_BASE + Vector3(0, 0, 18), true)

	# A defended perimeter: wall line, gate, and both tower types.
	for i in range(12):
		var x: float = -26.0 + i * 4.0
		if i == 6:
			_building("gate", PLAYER_BASE + Vector3(x, 0, -27), true)
		else:
			_building("wall", PLAYER_BASE + Vector3(x, 0, -27), true)
	_building("mg_tower", PLAYER_BASE + Vector3(-28, 0, -24), true)
	_building("at_turret", PLAYER_BASE + Vector3(24, 0, -24), true)

	# Harvesters working the near ore field.
	for i in range(3):
		_unit("harvester", ORE_A + Vector3(-6.0 + i * 6.0, 0, 7.0), true)

	# A vehicle group in formation.
	for i in range(8):
		var column: int = i % 4
		var row: int = i / 4
		var spot: Vector3 = PLAYER_BASE + Vector3(-10.0 + column * 6.0, 0, 34.0 + row * 7.0)
		_unit("tank" if row == 0 else "assault", spot, true)
	_unit("artillery", PLAYER_BASE + Vector3(14, 0, 41), true)
	_unit("scout", PLAYER_BASE + Vector3(-18, 0, 37), true)

	# A firefight at the centre. Evenly matched on purpose: the first cut
	# put infantry against armour, and the engagement was over before the
	# camera arrived - a photograph of corpses, not of combat.
	for i in range(5):
		_unit("tank", CENTRE + Vector3(-16.0 + i * 8.0, 0, 13.0), true)
	for i in range(4):
		_unit("at_squad", CENTRE + Vector3(-12.0 + i * 8.0, 0, 19.0), true)
	_unit("artillery", CENTRE + Vector3(10, 0, 22), true)
	for i in range(5):
		_unit("tank", CENTRE + Vector3(-16.0 + i * 8.0, 0, -13.0), false)
	for i in range(4):
		_unit("at_squad", CENTRE + Vector3(-12.0 + i * 8.0, 0, -19.0), false)
	_unit("artillery", CENTRE + Vector3(-10, 0, -22), false)

	# A developed enemy base to photograph from the far side.
	_building("power_plant", ENEMY_BASE + Vector3(-16, 0, -2), false)
	_building("refinery", ENEMY_BASE + Vector3(-2, 0, 16), false)
	_building("barracks", ENEMY_BASE + Vector3(16, 0, -2), false)
	_building("war_factory", ENEMY_BASE + Vector3(17, 0, 16), false)
	_building("radar", ENEMY_BASE + Vector3(-16, 0, 14), false)
	_building("mg_tower", ENEMY_BASE + Vector3(0, 0, 24), false)

func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("res://screenshots/%s.png" % name)
	print("SHOW| %s" % name)

func _look(point: Vector3, zoom: float) -> void:
	if _camera == null:
		return
	if _camera.has_method("focus_on"):
		_camera.focus_on(point)
	if "zoom_distance" in _camera:
		_camera.zoom_distance = zoom

func _wait(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

func _run() -> void:
	await _wait(1.5)
	var stops: Array = [
		["player_base", PLAYER_BASE + Vector3(0, 0, -4), 44.0, 1.2],
		["defensive_walls", PLAYER_BASE + Vector3(-2, 0, -24), 30.0, 1.2],
		["resource_harvesting", ORE_A + Vector3(0, 0, 3), 26.0, 1.2],
		["vehicle_group", PLAYER_BASE + Vector3(0, 0, 37), 26.0, 1.2],
		["combat", CENTRE, 36.0, 1.6],
		["enemy_base", ENEMY_BASE, 44.0, 1.2],
		["battlefield_overview", Vector3(-8, 0, 0), 110.0, 1.5],
	]
	for stop in stops:
		_look(stop[1], stop[2])
		await _wait(stop[3])
		await _shoot(stop[0])
	print("SHOW| done")
