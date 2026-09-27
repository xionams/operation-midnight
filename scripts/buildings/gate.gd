extends Wall
class_name Gate

## A wall segment the owner's units can walk through.
##
## It is part of the wall grid, so it joins the segments either side and
## turns to face along the run. Like any wall it is carved out of the
## shared navmesh, so for everyone it is a barrier; its owner gets a
## NavigationLink3D straight through it on a navigation layer only that
## side's units carry. Friendly pathing crosses, hostile pathing does not
## even see the link - no per-faction navmesh, no rebake per passing unit.
##
## (The previous gate claimed to let its owner through by dropping a
## collision layer, but units never collided with buildings in the first
## place and the navmesh carved it like any wall, so it blocked both
## sides.)

## Navigation layers. Bit 1 is the shared ground every agent uses; each
## side additionally carries its own bit, which is what gate links are on.
const PLAYER_NAV_LAYER: int = NavLayers.PLAYER_GATE
const ENEMY_NAV_LAYER: int = NavLayers.ENEMY_GATE
## Link ends sit this far either side of the gate's centre: past the
## carve (half a cell plus the navmesh agent radius) and onto open mesh.
const LINK_REACH: float = 3.5

var _link: NavigationLink3D = null

static func nav_layer_for(is_player: bool) -> int:
	return PLAYER_NAV_LAYER if is_player else ENEMY_NAV_LAYER

func _ready() -> void:
	super._ready()
	add_to_group("gates")

## One frame across the run, whatever the neighbours: a gate is never a
## corner piece.
func _parts() -> Array:
	var h: float = stats.body_size.y if stats else 3.2
	if _runs_north_south():
		return [[Vector3(0, h * 0.5, 0), Vector3(THICKNESS, h, GRID)]]
	return [[Vector3(0, h * 0.5, 0), Vector3(GRID, h, THICKNESS)]]

func _runs_north_south() -> bool:
	return (connections & (NORTH | SOUTH)) != 0 and (connections & (EAST | WEST)) == 0

## The gate model spans its opening along X; turn it for a N-S run.
func _rebuild_visual() -> void:
	if _visual_container == null:
		return
	for child in _visual_container.get_children():
		_visual_container.remove_child(child)
		child.queue_free()
	if stats != null and stats.visual_scene != null and OS.get_environment("OM_NO_MODELS").is_empty():
		var model: Node3D = stats.visual_scene.instantiate()
		model.rotation.y = PI * 0.5 if _runs_north_south() else 0.0
		_visual_container.add_child(model)
	else:
		super._rebuild_visual()
	FactionPaint.apply(_visual_container, _faction_color())

func _on_connections_changed() -> void:
	_refresh_link()

func _on_faction_changed() -> void:
	super._on_faction_changed()
	_refresh_link()

## The owner's way through, perpendicular to the run.
func _refresh_link() -> void:
	if _link == null:
		_link = NavigationLink3D.new()
		_link.name = "OwnerPassage"
		_link.bidirectional = true
		add_child(_link)
	var across := Vector3(LINK_REACH, 0, 0) if _runs_north_south() else Vector3(0, 0, LINK_REACH)
	var here: Vector3 = global_position
	var a: Vector3 = -across
	var b: Vector3 = across
	a.y = Terrain.height_at(here.x + a.x, here.z + a.z) - here.y
	b.y = Terrain.height_at(here.x + b.x, here.z + b.z) - here.y
	_link.start_position = a
	_link.end_position = b
	_link.navigation_layers = 0 if is_neutral else nav_layer_for(is_player_faction)
	_link.enabled = not is_neutral
