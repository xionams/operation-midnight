extends Node

## Autoload: the map's visibility memory.
##
## ARCHITECTURE
## Two flat byte grids over the battlefield at CELL_SIZE resolution
## (2m cells => 110x110 = 12,100 cells on a 220m map):
##
##   _explored   sticky. Set once a cell has ever been seen, never cleared.
##   _visible    rebuilt from scratch every update tick from live vision.
##
## Keeping them separate is what makes exploration permanent while
## current intelligence decays - the player remembers terrain they have
## walked, but loses sight of what is moving there now.
##
## Vision is recomputed on a timer (UPDATE_HZ), not per frame, and each
## source stamps a precomputed disc of cell offsets rather than testing
## every cell against every unit. Cost per tick is therefore
## O(sources x cells_in_radius), independent of map area and of how many
## entities are asking whether they can be seen.
##
## The same grid is published as an L8 texture for the terrain shader,
## so the visual fog and the gameplay fog can never disagree.

signal fog_updated

const CELL_SIZE: float = 2.0
const UPDATE_HZ: float = 8.0

## Texture values per state; the shader maps these to brightness.
const SHADE_UNEXPLORED: int = 0
const SHADE_EXPLORED: int = 100
const SHADE_VISIBLE: int = 255

var enabled: bool = true

var _map_size: float = 220.0
var _side: int = 110
var _explored: PackedByteArray = PackedByteArray()
var _visible: PackedByteArray = PackedByteArray()

var _fog_image: Image
var _fog_texture: ImageTexture

var _accum: float = 0.0
var _disc_cache: Dictionary = {}

func _ready() -> void:
	configure(_map_size)

func configure(map_size: float) -> void:
	_map_size = map_size
	_side = int(ceil(map_size / CELL_SIZE))
	var count: int = _side * _side
	_explored = PackedByteArray()
	_explored.resize(count)
	_visible = PackedByteArray()
	_visible.resize(count)
	_fog_image = Image.create(_side, _side, false, Image.FORMAT_L8)
	_fog_image.fill(Color(0, 0, 0))
	_fog_texture = ImageTexture.create_from_image(_fog_image)

func get_texture() -> ImageTexture:
	return _fog_texture

func get_map_size() -> float:
	return _map_size

func get_side() -> int:
	return _side

func cell_index(cx: int, cy: int) -> int:
	return cy * _side + cx

func world_to_cell(pos: Vector3) -> Vector2i:
	var half: float = _map_size * 0.5
	return Vector2i(
		clampi(int((pos.x + half) / CELL_SIZE), 0, _side - 1),
		clampi(int((pos.z + half) / CELL_SIZE), 0, _side - 1))

func is_visible_at(pos: Vector3) -> bool:
	if not enabled:
		return true
	var c := world_to_cell(pos)
	return _visible[cell_index(c.x, c.y)] != 0

func is_explored_at(pos: Vector3) -> bool:
	if not enabled:
		return true
	var c := world_to_cell(pos)
	return _explored[cell_index(c.x, c.y)] != 0

func is_cell_visible(cx: int, cy: int) -> bool:
	return _visible[cell_index(cx, cy)] != 0

func is_cell_explored(cx: int, cy: int) -> bool:
	return _explored[cell_index(cx, cy)] != 0

## Reveals a patch without a unit present. Used to seed the starting base
## area so the player opens with a believable pocket of known ground.
func reveal_area(center: Vector3, radius: float) -> void:
	_stamp(center, radius, _explored)
	_stamp(center, radius, _visible)
	_publish_texture()

func _process(delta: float) -> void:
	if not enabled:
		return
	_accum += delta
	if _accum < 1.0 / UPDATE_HZ:
		return
	_accum = 0.0
	update_now()

func update_now() -> void:
	for i in _visible.size():
		_visible[i] = 0

	for source in _vision_sources():
		var radius: float = _vision_range_of(source)
		if radius <= 0.0:
			continue
		_stamp(source.global_position, radius, _visible)
		_stamp(source.global_position, radius, _explored)

	_publish_texture()
	fog_updated.emit()

## Only the player's own units and structures grant vision. Camera
## position deliberately does not - moving the view over black ground
## must never reveal it.
func _vision_sources() -> Array:
	var sources: Array = get_tree().get_nodes_in_group("player_units")
	sources.append_array(get_tree().get_nodes_in_group("player_buildings"))
	return sources

func _vision_range_of(entity: Node) -> float:
	if not is_instance_valid(entity):
		return 0.0
	var stats = entity.get("stats")
	if stats == null:
		return 0.0
	return stats.vision_range

## Discs of cell offsets are cached per rounded radius, so a tick writes
## only the cells actually inside the circle and never runs a distance
## test in the inner loop.
func _disc_offsets(radius_cells: int) -> PackedInt32Array:
	if _disc_cache.has(radius_cells):
		return _disc_cache[radius_cells]
	var offsets := PackedInt32Array()
	var r_sq: int = radius_cells * radius_cells
	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			if dx * dx + dy * dy <= r_sq:
				offsets.append(dx)
				offsets.append(dy)
	_disc_cache[radius_cells] = offsets
	return offsets

func _stamp(center: Vector3, radius: float, grid: PackedByteArray) -> void:
	var c := world_to_cell(center)
	var radius_cells: int = maxi(1, int(round(radius / CELL_SIZE)))
	var offsets := _disc_offsets(radius_cells)
	var i: int = 0
	while i < offsets.size():
		var cx: int = c.x + offsets[i]
		var cy: int = c.y + offsets[i + 1]
		i += 2
		if cx < 0 or cy < 0 or cx >= _side or cy >= _side:
			continue
		grid[cy * _side + cx] = 1

func _publish_texture() -> void:
	var data := PackedByteArray()
	data.resize(_side * _side)
	for i in data.size():
		if _visible[i] != 0:
			data[i] = SHADE_VISIBLE
		elif _explored[i] != 0:
			data[i] = SHADE_EXPLORED
		else:
			data[i] = SHADE_UNEXPLORED
	_fog_image.set_data(_side, _side, false, Image.FORMAT_L8, data)
	_fog_texture.update(_fog_image)

## Debug/telemetry: what fraction of the battlefield has been explored.
func explored_fraction() -> float:
	var seen: int = 0
	for i in _explored.size():
		if _explored[i] != 0:
			seen += 1
	return float(seen) / float(_explored.size())
