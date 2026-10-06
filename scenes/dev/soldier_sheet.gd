extends Node

## What an infantryman actually looks like, close enough to judge.
##
## Gameplay zoom is almost straight down and about 25m up, so nobody has
## ever really SEEN these models - every screenshot shows a 20-pixel
## smudge. This puts one on screen from four sides at arm's length, then
## the whole infantry lineup, then the same man at the zoom a player
## actually plays at, so the gap between the two is visible.

const RIFLE := preload("res://config/units/rifle_soldier.tres")
const AT := preload("res://config/units/at_squad.tres")
const ENGINEER := preload("res://config/units/engineer.tres")
const SPY := preload("res://config/units/spy.tres")
const DOG := preload("res://config/units/attack_dog.tres")

var _main: Node3D
var _cam: Camera3D
var _at: Vector3

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"): hud._begin_match()
	await get_tree().process_frame
	if hud: hud.visible = false
	var d = _main.get_node_or_null("AIDirector")
	if d: d.enabled = false
	FogOfWar.enabled = false
	FogOfWar.reveal_area(Vector3.ZERO, FogOfWar.get_map_size())
	for i in 20: await get_tree().physics_frame

	## Away from the base, so the backdrop is ground rather than buildings.
	_at = _main.map.player_base + Vector3(30, 0, 34)
	## Onto the ground. Framing from y=0 while the man stands on terrain
	## several metres up is what put his head above the top of frame.
	_at.y = Terrain.height_at(_at.x, _at.z)
	_cam = Camera3D.new()
	_main.add_child(_cam)
	_cam.fov = 40.0
	_cam.make_current()
	for i in 10: await get_tree().process_frame

	## One man, four sides, close enough to count the polygons.
	var man := _spawn(RIFLE, _at)
	await _settle(man)
	var eye: float = 1.05
	for shot in [["front", 0.0], ["three_quarter", 38.0],
			["side", 90.0], ["back", 180.0]]:
		var a: float = deg_to_rad(float(shot[1]))
		_look_from(_at + Vector3(sin(a) * 2.5, eye, cos(a) * 2.5),
			_at + Vector3(0, 0.90, 0))
		await _save("soldier_%s" % shot[0])

	## The whole family, so the silhouettes can be compared.
	man.queue_free()
	await get_tree().process_frame
	var line := [RIFLE, AT, ENGINEER, SPY, DOG]
	var crowd: Array = []
	for i in line.size():
		var u := _spawn(line[i], _at + Vector3(-3.2 + i * 1.6, 0, 0))
		crowd.append(u)
		await _settle(u)
	_look_from(_at + Vector3(0, 1.7, 7.0), _at + Vector3(0, 0.85, 0))
	await _save("soldier_lineup", crowd, 0.12)

	## And the same thing at the distance the game is actually played at.
	_look_from(_at + Vector3(0, 19.0, 17.0), _at)
	await _save("soldier_gameplay_zoom", crowd, 1.4)

	print("SHEET| DONE")
	get_tree().quit()

func _spawn(stats, at: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = true
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(at.x, Terrain.height_at(at.x, at.z), at.z)
	return u

## Let him arrive, stand still and settle into the idle pose.
func _settle(unit: Node) -> void:
	for i in 10: await get_tree().physics_frame
	if unit.has_method("stop_moving"):
		unit.stop_moving()
	for i in 24: await get_tree().process_frame

func _look_from(eye: Vector3, target: Vector3) -> void:
	_cam.global_position = eye
	_cam.look_at(target, Vector3.UP)

## Saves a crop framed on the SUBJECT rather than on the viewport.
## Guessing a crop box by eye wasted two renders on pictures of boots.
func _save(name: String, subjects: Array = [], pad: float = 0.55) -> void:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if not subjects.is_empty():
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		## From the drawn geometry's own bounds. Offsets guessed from the
		## node origin produced two sheets of boots, because a unit's
		## origin is not where you assume it is.
		for s in subjects:
			if not is_instance_valid(s):
				continue
			for vis in (s as Node).find_children("*", "VisualInstance3D", true, false):
				var v := vis as VisualInstance3D
				if not v.visible:
					continue
				var box: AABB = v.get_aabb()
				for i in 8:
					var at: Vector2 = _cam.unproject_position(
						v.global_transform * box.get_endpoint(i))
					lo = Vector2(minf(lo.x, at.x), minf(lo.y, at.y))
					hi = Vector2(maxf(hi.x, at.x), maxf(hi.y, at.y))
		var m: float = maxf(hi.y - lo.y, hi.x - lo.x) * pad
		var rect := Rect2i(
			Vector2i(int(lo.x - m), int(lo.y - m)),
			Vector2i(int(hi.x - lo.x + m * 2.0), int(hi.y - lo.y + m * 2.0)))
		rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if rect.size.x > 16 and rect.size.y > 16:
			img = img.get_region(rect)
	img.save_png("res://screenshots/%s.png" % name)
	print("SHEET| %-24s %dx%d" % [name, img.get_width(), img.get_height()])
