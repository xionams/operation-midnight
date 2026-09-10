extends Control
class_name Minimap

## Strategic overview drawn from the same fog grid the rules use, so it
## can only ever show what the player is genuinely entitled to know:
## unexplored ground stays black, and an enemy dot exists only while
## something of the player's is actually looking at it.
##
## The terrain layer is the fog texture itself, drawn stretched - no
## per-cell drawing - and only the handful of entity dots are drawn per
## frame, so cost does not scale with map area.

const SIZE: float = 190.0

var _dot_player := Color(0.35, 0.75, 1.0)
var _dot_enemy := Color(1.0, 0.25, 0.2)
var _dot_resource := Color(0.2, 0.95, 0.7)
var _dot_building := Color(0.6, 0.85, 1.0)

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	draw_rect(rect, Color(0, 0, 0, 0.85), true)

	var texture := FogOfWar.get_texture()
	if texture != null:
		## The fog texture is greyscale: black unexplored, mid explored,
		## white visible. Tinting it green reads as terrain rather than
		## as a data visualisation.
		draw_texture_rect(texture, rect, false, Color(0.35, 0.62, 0.3))

	_draw_entities("resource_nodes", _dot_resource, 2.5)
	_draw_entities("player_buildings", _dot_building, 3.0)
	_draw_entities("enemy_buildings", _dot_enemy, 3.0)
	_draw_entities("player_units", _dot_player, 2.0)
	_draw_entities("enemy_units", _dot_enemy, 2.0)

	_draw_camera_box()
	draw_rect(rect, Color(0.55, 0.6, 0.45, 0.9), false, 2.0)

func _draw_entities(group: String, color: Color, radius: float) -> void:
	for entity in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(entity):
			continue
		## Anything the fog is hiding must not leak onto the minimap -
		## that would hand the player exactly the tracking the fog exists
		## to deny.
		if FogHideable.is_hidden(entity):
			continue
		draw_circle(_world_to_map(entity.global_position), radius, color)

## Shows roughly what the camera is looking at, so the minimap doubles as
## a "where am I" indicator rather than only a map.
func _draw_camera_box() -> void:
	var camera := get_tree().get_first_node_in_group("rts_camera")
	if camera == null:
		return
	var centre := _world_to_map(camera.pan_target)
	var span: float = (camera.zoom_distance * 1.5 / FogOfWar.get_map_size()) * SIZE
	draw_rect(Rect2(centre - Vector2(span, span) * 0.5, Vector2(span, span)),
		Color(1, 1, 1, 0.65), false, 1.5)

func _world_to_map(pos: Vector3) -> Vector2:
	var map_size: float = FogOfWar.get_map_size()
	var half: float = map_size * 0.5
	return Vector2(
		((pos.x + half) / map_size) * SIZE,
		((pos.z + half) / map_size) * SIZE)

func _map_to_world(point: Vector2) -> Vector3:
	var map_size: float = FogOfWar.get_map_size()
	var half: float = map_size * 0.5
	return Vector3(
		(point.x / SIZE) * map_size - half,
		0.0,
		(point.y / SIZE) * map_size - half)

## Tapping the minimap moves the camera there. It deliberately does not
## reveal anything - looking at a place is not the same as seeing it.
func _gui_input(event: InputEvent) -> void:
	var point: Vector2
	if event is InputEventMouseButton and event.pressed:
		point = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and event.pressed:
		point = (event as InputEventScreenTouch).position
	else:
		return
	var camera := get_tree().get_first_node_in_group("rts_camera")
	if camera != null:
		camera.focus_on(_map_to_world(point))
	accept_event()
