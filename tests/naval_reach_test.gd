extends Node

## The player must be able to look at every ship they are allowed to own.
##
## The sea navmesh was baked from the raw water polygons. A map draws its
## water far past its own edge on purpose, so the horizon has no visible
## seam - on Coastline the polygon spans x -270..270 on a 220m map - and
## baking straight from it let ships sail some 50m beyond the furthest
## the camera may pan. The player could own a boat they could not centre
## on, click, or follow. The drawn sea is unchanged; only the sea ships
## may USE is now trimmed, to exactly the rectangle the camera can reach.

const COAST := preload("res://config/maps/coastline.tres")
const BOAT := preload("res://config/units/patrol_boat.tres")

var _main: Node3D
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-58s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _cam() -> RTSCamera:
	return get_tree().get_first_node_in_group("rts_camera") as RTSCamera

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	GameState.selected_map = COAST
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	FogOfWar.enabled = false
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	for i in 40:
		await get_tree().physics_frame

	await _sea_is_reachable()
	await _ships_stay_on_the_map()

	GameState.selected_map = null
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()

# --------------------------------------------------------- sea coverage

## Every bit of sea a ship may use has to be inside the camera's reach.
func _sea_is_reachable() -> void:
	var rect: Rect2 = Water.navigable_bounds()
	_check("The navigable sea is bounded at all", rect.size.x < 1e8,
		"%s" % rect)
	var outside: int = 0
	var checked: int = 0
	var worst := Vector2.ZERO
	for ix in 60:
		for iz in 60:
			var x: float = -270.0 + 540.0 * float(ix) / 59.0
			var z: float = -270.0 + 540.0 * float(iz) / 59.0
			if not Water.is_navigable(x, z):
				continue
			checked += 1
			if x < _cam().bounds_min.x or x > _cam().bounds_max.x \
				or z < _cam().bounds_min.y or z > _cam().bounds_max.y:
				outside += 1
				worst = Vector2(x, z)
	_check("Sampled navigable sea exists", checked > 50, "%d points" % checked)
	_check("No navigable sea lies outside the camera's reach", outside == 0,
		"%d of %d outside (e.g. %s)" % [outside, checked, worst])

	## The drawn sea is still big: this trimmed what ships may use, not
	## what the player can see.
	_check("The drawn sea still runs past the map (no visible edge)",
		Water.is_water(-260.0, 120.0), "")

# ------------------------------------------------- ships stay reachable

func _ships_stay_on_the_map() -> void:
	## Put a boat at the far edge of the legal sea and order it further
	## out; it must not be able to go.
	var rect: Rect2 = Water.navigable_bounds()
	var start := Vector3.ZERO
	for ix in 120:
		var x: float = rect.position.x + 2.0 + float(ix)
		if Water.is_navigable(x, rect.end.y - 6.0):
			start = Vector3(x, Water.level, rect.end.y - 6.0)
			break
	_check("Found legal sea to launch from", start != Vector3.ZERO, "%s" % start)
	if start == Vector3.ZERO:
		return

	var boat = BOAT.unit_scene.instantiate()
	boat.stats = BOAT
	boat.is_player_faction = true
	_main.get_node("Level").add_child(boat)
	boat.global_position = start
	for i in 20:
		await get_tree().physics_frame

	## The camera must be able to put it dead centre and keep it there.
	_cam().focus_on(boat.global_position)
	_cam().snap()
	await _frames(3)
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var shot: Vector2 = _cam().unproject_position(boat.global_position + Vector3.UP * 0.8)
	_check("A boat at the edge of the legal sea centres on screen",
		shot.distance_to(centre) < 60.0, "%.0f px off centre" % shot.distance_to(centre))

	## ...and the click that the player would make actually lands.
	SelectionManager.clear_selection()
	SelectionManager._handle_tap(shot, false)
	await get_tree().process_frame
	_check("...and can be clicked there", SelectionManager.selected_units == [boat],
		"%d selected" % SelectionManager.selected_units.size())

	## Ordered far out to sea, it must stop at the legal edge.
	boat.move_to(Vector3(-260.0, Water.level, 200.0))
	for i in 140:
		await get_tree().physics_frame
	var p: Vector3 = boat.global_position
	_check("A boat cannot sail off the playable map",
		rect.has_point(Vector2(p.x, p.z)), "ended at %s, legal %s" % [p, rect])
	_check("...and is still afloat", Water.is_water(p.x, p.z))
