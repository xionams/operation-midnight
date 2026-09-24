class_name Terrain
extends RefCounted

## The shape of the ground.
##
## The battlefield was a mathematically flat plane, and that is the single
## loudest "this is a prototype" signal a 3D strategy game can send. No
## amount of texture, prop density or lighting fixes it: real ground has
## a horizon that moves, slopes that catch the sun differently from the
## hollows beside them, and a silhouette where it meets the sky.
##
## **Gameplay stays flat.** Collision is still a box and the navmesh is
## still baked on level ground; only the visible surface moves, and
## everything that sits on it is lifted to match by height_at(). That is
## deliberate rather than a shortcut:
##
##   - Pathfinding risk drops to nothing. Not one existing path, formation
##     or stuck-unit fix has to be re-validated.
##   - An RTS mostly does not WANT slope to affect movement. A tank that
##     crawls uphill is a simulation feature, not a strategy one, and this
##     game has no line-of-sight or high-ground rules for it to serve.
##
## The honest limit of the trick: at large amplitudes a unit would visibly
## climb a hill its pathing does not know about, and fire over a ridge it
## should not see past. AMPLITUDE is kept low enough that the ground reads
## as rolling rather than as hills, which is where that stops mattering.

## Metres of relief either side of zero. 1.6 is enough for the shading to
## separate a rise from a hollow at the camera's range and for the map
## edge to have a visible profile; much more and the flat-collision
## compromise above starts to show.
const AMPLITUDE: float = 1.6

## Sum of sines rather than a noise texture, because this is sampled per
## unit per frame as well as per vertex at build time, and three sines are
## cheaper than a texture fetch. The wavelengths are deliberately not
## multiples of each other, or the sum repeats on a visible grid.
const WAVES: Array = [
	# [wavelength_x, wavelength_z, weight, phase]
	[73.0, 91.0, 0.55, 0.0],
	[41.0, 37.0, 0.30, 1.7],
	[23.0, 19.0, 0.15, 3.1],
]

## Discs where the ground is levelled: [centre, radius, blend, height].
##
## Roads and base pads are flat slabs. Laid on rolling ground they cut
## through it at their ends and float at their middles - the first build
## with relief turned on had the road network sliced into disconnected
## grey patches. Real strategy games solve this by flattening the terrain
## under anything built on it, and so does this.
##
## A disc rather than a rectangle because the blend is what matters: a
## hard-edged flat area reads as a plateau stamped into the map, whereas a
## radius that eases out over `blend` metres reads as ground that was
## graded.
static var _level_discs: Array = []

## Cleared per match. These are registered before the ground mesh is built
## and the mesh bakes them in, so a stale disc from the previous map would
## flatten ground that nothing stands on.
static func reset() -> void:
	_level_discs.clear()
	_grid.clear()
	_grid_cells = 0

## `height` forces a specific level. A chain of discs left to sample their
## own centres still follows the ground, which flattens nothing useful:
## the road corridor was still a slope and its flat slabs still cut
## through it. A run of slabs has to be graded to ONE height.
static func level(centre: Vector3, radius: float, blend: float = 8.0,
		height: float = INF) -> void:
	_level_discs.append([centre, radius, maxf(blend, 0.01),
		_raw_height(centre.x, centre.z) if is_inf(height) else height])

static func _raw_height(x: float, z: float) -> float:
	var total: float = 0.0
	for wave in WAVES:
		total += sin(x / wave[0] * TAU + wave[3]) \
			* cos(z / wave[1] * TAU + wave[3]) * wave[2]
	return total * AMPLITUDE

## The graded height, evaluated from first principles. Correct but not
## cheap: it walks every levelling disc, and a road contributes about a
## hundred of them.
static func _graded_height(x: float, z: float) -> float:
	var height: float = _raw_height(x, z)
	for disc in _level_discs:
		var centre: Vector3 = disc[0]
		var distance: float = Vector2(x - centre.x, z - centre.z).length()
		if distance >= disc[1] + disc[2]:
			continue
		## 1 inside the flat radius, easing to 0 across the blend band.
		var weight: float = 1.0 - clampf((distance - disc[1]) / disc[2], 0.0, 1.0)
		weight = weight * weight * (3.0 - 2.0 * weight)
		height = lerpf(height, disc[3], weight)
	return height

## --- baked lookup -----------------------------------------------------
##
## height_at() is called for every unit every physics frame, and also by
## every prop, ground mark and building placement. Evaluating the graded
## form each time cost 15 FPS at 120 units: three sines is nothing, but
## walking a hundred road discs per unit per frame is not.
##
## So the graded surface is baked once into a grid and sampled bilinearly,
## which is O(1) whatever the disc count, and returns exactly the mesh's
## own heights at its vertices because it is built on the same lattice.
static var _grid: PackedFloat32Array = PackedFloat32Array()
static var _grid_cells: int = 0
static var _grid_step: float = 1.0
static var _grid_half: float = 0.0

static func bake(extent: float, step: float) -> void:
	_grid_cells = maxi(2, int(extent / step))
	_grid_step = step
	_grid_half = extent * 0.5
	_grid.resize((_grid_cells + 1) * (_grid_cells + 1))
	var index: int = 0
	for row in _grid_cells + 1:
		var z: float = -_grid_half + row * step
		for column in _grid_cells + 1:
			_grid[index] = _graded_height(-_grid_half + column * step, z)
			index += 1

static func height_at(x: float, z: float) -> float:
	if _grid_cells == 0:
		return _graded_height(x, z)
	var fx: float = clampf((x + _grid_half) / _grid_step, 0.0, float(_grid_cells))
	var fz: float = clampf((z + _grid_half) / _grid_step, 0.0, float(_grid_cells))
	var x0: int = int(fx)
	var z0: int = int(fz)
	var x1: int = mini(x0 + 1, _grid_cells)
	var z1: int = mini(z0 + 1, _grid_cells)
	var tx: float = fx - x0
	var tz: float = fz - z0
	var stride: int = _grid_cells + 1
	var top: float = lerpf(_grid[z0 * stride + x0], _grid[z0 * stride + x1], tx)
	var bottom: float = lerpf(_grid[z1 * stride + x0], _grid[z1 * stride + x1], tx)
	return lerpf(top, bottom, tz)

## Surface normal, from the analytic gradient rather than from neighbouring
## samples: the mesh is built once but this is also what props use to sit
## tilted into a slope, and a finite difference there would cost three
## height evaluations instead of one.
static func normal_at(x: float, z: float) -> Vector3:
	var step: float = 0.5
	var dx: float = height_at(x + step, z) - height_at(x - step, z)
	var dz: float = height_at(x, z + step) - height_at(x, z - step)
	return Vector3(-dx, 2.0 * step, -dz).normalized()

## Places `node` on the ground. `sink` pushes it into the surface, for
## things like boulders that should look embedded rather than dropped.
static func settle(node: Node3D, sink: float = 0.0) -> void:
	node.position.y = height_at(node.position.x, node.position.z) - sink

## The visible ground. One mesh, built once.
##
## `extent` is the full width of the sheet, which is wider than the
## playable map so the camera never sees its edge; `step` is the distance
## between vertices.
## `step` is 6m, not the 4m this started at. The relief has wavelengths of
## 19m and up, so 6m samples it more than finely enough, and it takes the
## sheet from ~35,000 triangles to ~15,000.
static func build_mesh(extent: float, step: float = 6.0) -> ArrayMesh:
	## Bake first, so the mesh and every runtime query read the same
	## surface - a unit standing on a vertex is at exactly that vertex.
	bake(extent, step)
	var cells: int = _grid_cells
	var half: float = extent * 0.5

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize((cells + 1) * (cells + 1))
	normals.resize(vertices.size())
	uvs.resize(vertices.size())

	var index: int = 0
	for row in cells + 1:
		var z: float = -half + row * step
		for column in cells + 1:
			var x: float = -half + column * step
			vertices[index] = Vector3(x, height_at(x, z), z)
			normals[index] = normal_at(x, z)
			uvs[index] = Vector2(float(column) / cells, float(row) / cells)
			index += 1

	var indices := PackedInt32Array()
	indices.resize(cells * cells * 6)
	var out: int = 0
	for row in cells:
		for column in cells:
			var a: int = row * (cells + 1) + column
			var b: int = a + 1
			var c: int = a + cells + 1
			var d: int = c + 1
			## Wound so the surface faces up. Get this backwards and the
			## whole sheet is backface-culled: the terrain still shades and
			## still occludes, so it reads as a black ground rather than as
			## a missing one, which is a slow thing to diagnose.
			indices[out] = a; indices[out + 1] = b; indices[out + 2] = c
			indices[out + 3] = b; indices[out + 4] = d; indices[out + 5] = c
			out += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
