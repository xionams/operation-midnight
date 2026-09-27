extends Node

## Phase 1 / item 6: walls form continuous barriers.
##
## Every wall here is laid with a real mouse drag through the building
## placer, exactly as a player lays it. Continuity is then measured three
## ways - the visible meshes, the collision shapes, and the navmesh units
## actually path on - and finally with real units trying to get through.

const WALL := preload("res://config/buildings/wall.tres")
const GATE := preload("res://config/buildings/gate.tres")
const SOLDIER := preload("res://config/units/rifle_soldier.tres")
const TANK := preload("res://config/units/assault_vehicle.tres")

var _main: Node3D
var _placer: BuildingPlacer
var _nav: NavigationRegion3D
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = get_parent().get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	FogOfWar.enabled = false
	var director = get_parent().get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	_placer = _main.get_node("BuildingPlacer")
	_nav = _main.get_node("Level/NavRegion")
	GameState.add_credits(50000)
	## The starting army would shoot the enemy fixtures used below.
	for u in get_tree().get_nodes_in_group("player_units"):
		var gun = u.get_node_or_null("AttackerComponent")
		if gun != null:
			gun.set_physics_process(false)
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-58s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

# ------------------------------------------------------------ input

func _mouse_move(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	Input.parse_input_event(m)
	await get_tree().process_frame

func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame

## One press-drag-release with the wall tool, as the player does it.
func _drag(stats: BuildingStats, from: Vector3, to: Vector3) -> Array:
	var cam := get_tree().get_first_node_in_group("rts_camera") as Camera3D
	cam.focus_on((from + to) * 0.5)
	for i in 3:
		await get_tree().process_frame
	## Aim at cell centres, as the snapped ghost invites the player to:
	## a click exactly on a cell boundary is ambiguous by raycast noise.
	from = Wall.snap(from)
	to = Wall.snap(to)
	var before: Array = _walls()
	_placer.start_placement(stats)
	await get_tree().process_frame
	var a: Vector2 = cam.unproject_position(Vector3(from.x, 0.0, from.z))
	var b: Vector2 = cam.unproject_position(Vector3(to.x, 0.0, to.z))
	await _mouse_move(a)
	await _mouse_button(a, true)
	for t in [0.2, 0.4, 0.6, 0.8, 1.0]:
		await _mouse_move(a.lerp(b, t))
	await _mouse_button(b, false)
	await get_tree().process_frame
	_placer.cancel_placement()
	var added: Array = []
	for w in _walls():
		if not before.has(w):
			added.append(w)
	return added

func _walls() -> Array:
	var out: Array = []
	for b in get_tree().get_nodes_in_group("walls"):
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			out.append(b)
	return out

## The navmesh has caught up with every wall placed so far.
func _settle_nav() -> void:
	for i in 600:
		await get_tree().physics_frame
		var busy: bool = _nav.is_baking() if _nav.has_method("is_baking") else false
		var pending: bool = _main.get("_nav_dirty") == true
		if not busy and not pending and i > 10:
			break
	for i in 4:
		await get_tree().physics_frame

# ------------------------------------------------------ measurements

## Longest uncovered stretch along a line, given boxes (AABBs) that are
## supposed to cover it. Sampled every 5cm across the band `half_width`
## either side of the line's centre, so a wall piece that merely touches
## the line from the side does not count.
func _largest_gap(boxes: Array, from: Vector3, to: Vector3) -> float:
	var length: float = Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))
	var dir := (to - from)
	dir.y = 0.0
	dir = dir.normalized()
	var worst: float = 0.0
	var run: float = 0.0
	var steps: int = int(length / 0.05)
	for i in steps + 1:
		var p: Vector3 = from + dir * (float(i) * 0.05)
		var covered: bool = false
		for box in boxes:
			var aabb: AABB = box
			if p.x >= aabb.position.x - 0.01 and p.x <= aabb.end.x + 0.01 \
				and p.z >= aabb.position.z - 0.01 and p.z <= aabb.end.z + 0.01:
				covered = true
				break
		if covered:
			run = 0.0
		else:
			run += 0.05
			worst = maxf(worst, run)
	return worst

func _visual_boxes(walls: Array) -> Array:
	var out: Array = []
	for w in walls:
		for mi in w.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.visible or not m.is_visible_in_tree():
				continue
			## Health bars, selection rings and the like are not the wall.
			if m.get_parent() != null and m.get_parent().get_class() == "Node3D" \
				and m.name.begins_with("HealthBar"):
				continue
			if m.get_aabb().size.y < 1.0:
				continue
			out.append(m.global_transform * m.get_aabb())
	return out

func _collision_boxes(walls: Array) -> Array:
	var out: Array = []
	for w in walls:
		for cs in w.find_children("*", "CollisionShape3D", true, false):
			var shape := (cs as CollisionShape3D).shape as BoxShape3D
			if shape == null or (cs as CollisionShape3D).disabled:
				continue
			var t: Transform3D = (cs as CollisionShape3D).global_transform
			out.append(t * AABB(-shape.size * 0.5, shape.size))
	return out

## Whether a unit whose navigation layers are `layers` can walk from
## `from` to `to`. Godot returns a path to the closest reachable point
## when the target is cut off, so "reachable" means the path ends there.
func _reachable(from: Vector3, to: Vector3, layers: int = 1) -> bool:
	var map_rid: RID = _nav.get_world_3d().navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, from, to, true, layers)
	if path.is_empty():
		return false
	var end: Vector3 = path[path.size() - 1]
	return Vector2(end.x, end.z).distance_to(Vector2(to.x, to.z)) < 1.5

func _crosses_line(from: Vector3, to: Vector3, a: Vector3, b: Vector3, layers: int = 1) -> bool:
	var map_rid: RID = _nav.get_world_3d().navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, from, to, true, layers)
	for i in range(1, path.size()):
		var hit = Geometry2D.segment_intersects_segment(
			Vector2(path[i - 1].x, path[i - 1].z), Vector2(path[i].x, path[i].z),
			Vector2(a.x, a.z), Vector2(b.x, b.z))
		if hit != null:
			return true
	return false

func _spawn(stats: UnitStats, player: bool, pos: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	return u

func _inside_rect(p: Vector3, lo: Vector3, hi: Vector3) -> bool:
	return p.x > lo.x and p.x < hi.x and p.z > lo.z and p.z < hi.z

# -------------------------------------------------------------- tests

func _run() -> void:
	## Open ground inside the player's starting territory (HQ at -78, 62,
	## territory 32m): every site below is within 32m of the HQ and clear
	## of the map's blockers and ore.
	var base := Vector3(-78, 0, 62)

	# --- 1. long straight fence, east-west ---
	var h_from := base + Vector3(-14, 0, -12)
	var h_to := base + Vector3(14, 0, -12)
	var h_walls: Array = await _drag(WALL, h_from, h_to)
	await _settle_nav()
	_check("E-W drag lays a full line", h_walls.size() >= 14, "(%d segments)" % h_walls.size())
	var h_line := _line_through(h_walls, true)
	_check("E-W fence: no visible gaps",
		_largest_gap(_visual_boxes(h_walls), h_line[0], h_line[1]) < 0.1,
		"(largest %.2fm)" % _largest_gap(_visual_boxes(h_walls), h_line[0], h_line[1]))
	_check("E-W fence: no collision gaps",
		_largest_gap(_collision_boxes(h_walls), h_line[0], h_line[1]) < 0.1,
		"(largest %.2fm)" % _largest_gap(_collision_boxes(h_walls), h_line[0], h_line[1]))
	var mid_h: Vector3 = (h_line[0] + h_line[1]) * 0.5
	_check("E-W fence: no path crosses it",
		not _crosses_line(mid_h + Vector3(0, 0, -5), mid_h + Vector3(0, 0, 5), h_line[0], h_line[1]))

	# --- 2. long straight fence, north-south ---
	var v_from := base + Vector3(22, 0, -22)
	var v_to := base + Vector3(22, 0, 4)
	var v_walls: Array = await _drag(WALL, v_from, v_to)
	await _settle_nav()
	_check("N-S drag lays a full line", v_walls.size() >= 14, "(%d segments)" % v_walls.size())
	var v_line := _line_through(v_walls, false)
	_check("N-S fence: no visible gaps",
		_largest_gap(_visual_boxes(v_walls), v_line[0], v_line[1]) < 0.1,
		"(largest %.2fm)" % _largest_gap(_visual_boxes(v_walls), v_line[0], v_line[1]))
	_check("N-S fence: no collision gaps",
		_largest_gap(_collision_boxes(v_walls), v_line[0], v_line[1]) < 0.1,
		"(largest %.2fm)" % _largest_gap(_collision_boxes(v_walls), v_line[0], v_line[1]))
	var mid_v: Vector3 = (v_line[0] + v_line[1]) * 0.5
	_check("N-S fence: no path crosses it",
		not _crosses_line(mid_v + Vector3(-5, 0, 0), mid_v + Vector3(5, 0, 0), v_line[0], v_line[1]))

	# --- 3. diagonal drag still makes a sealed line ---
	var d_walls: Array = await _drag(WALL, base + Vector3(-8, 0, -30), base + Vector3(4, 0, -18))
	await _settle_nav()
	var d_line := [base + Vector3(-8, 0, -30), base + Vector3(4, 0, -18)]
	_check("A diagonal drag lays connected pieces, not every other one",
		d_walls.size() >= 11, "(%d segments)" % d_walls.size())
	_check("A diagonal drag is one connected staircase", _connected(d_walls),
		"(%d pieces)" % d_walls.size())
	var d_mid: Vector3 = (d_line[0] + d_line[1]) * 0.5
	var d_normal := Vector3(1, 0, -1).normalized() * 6.0
	_check("No path crosses the diagonal line",
		not _crosses_line(d_mid - d_normal, d_mid + d_normal, d_line[0], d_line[1]))

	# --- 4. a 90-degree corner from two separate drags ---
	var c0 := base + Vector3(-22, 0, -6)
	var c_a: Array = await _drag(WALL, c0, c0 + Vector3(12, 0, 0))
	var c_b: Array = await _drag(WALL, c0, c0 + Vector3(0, 0, 12))
	await _settle_nav()
	var corner_walls: Array = c_a + c_b
	_check("Corner: both legs laid", c_a.size() >= 6 and c_b.size() >= 5,
		"(%d + %d)" % [c_a.size(), c_b.size()])
	var corner_piece = _nearest_wall(corner_walls, c0)
	var mask: int = corner_piece.get("connections") if corner_piece != null and corner_piece.get("connections") != null else -1
	_check("Corner piece knows it joins east and south",
		mask == (Wall.EAST | Wall.SOUTH), "(mask %d)" % mask)
	var corner_at: Vector3 = corner_piece.global_position if corner_piece != null else c0
	_check("Corner: no visible gap turning the corner",
		_largest_gap(_visual_boxes(corner_walls), corner_at + Vector3(3, 0, 0), corner_at + Vector3(0, 0, 0)) < 0.1
		and _largest_gap(_visual_boxes(corner_walls), corner_at, corner_at + Vector3(0, 0, 3)) < 0.1)
	_check("Corner: no path cuts the corner",
		not _reachable(corner_at + Vector3(4, 0, 4), corner_at + Vector3(-4, 0, -4))
		or not _crosses_line(corner_at + Vector3(4, 0, 4), corner_at + Vector3(-4, 0, -4),
			corner_at + Vector3(-1, 0, 1), corner_at + Vector3(1, 0, -1)))

	# --- 5. connection states: straight, T and cross ---
	var t0 := base + Vector3(-12, 0, 18)
	var t_a: Array = await _drag(WALL, t0 + Vector3(-6, 0, 0), t0 + Vector3(6, 0, 0))
	var t_b: Array = await _drag(WALL, t0, t0 + Vector3(0, 0, 6))
	var t_c: Array = await _drag(WALL, t0, t0 + Vector3(0, 0, -6))
	await get_tree().process_frame
	var hub = _nearest_wall(t_a + t_b + t_c, Wall.snap(t0))
	var hub_mask: int = hub.get("connections") if hub != null else -1
	_check("Crossing lines make a four-way piece",
		hub_mask == (Wall.NORTH | Wall.EAST | Wall.SOUTH | Wall.WEST), "(mask %d)" % hub_mask)
	var end_piece = _nearest_wall(t_a, Wall.snap(t0 + Vector3(-6, 0, 0)))
	var end_mask: int = end_piece.get("connections") if end_piece != null else -1
	_check("Line end is an endpoint (one arm)", end_mask == Wall.EAST, "(mask %d)" % end_mask)
	var straight = _nearest_wall(t_a, Wall.snap(t0) + Vector3(-4, 0, 0))
	_check("Mid-line piece is straight E-W",
		straight != null and straight.connections == (Wall.EAST | Wall.WEST))
	var t_mid = _nearest_wall(t_b, Wall.snap(t0) + Vector3(0, 0, 2))
	_check("T-arm piece runs N-S", t_mid != null and t_mid.connections == (Wall.NORTH | Wall.SOUTH),
		"(mask %d)" % (t_mid.connections if t_mid != null else -1))
	_check("Pieces keep a shared visual per state (no per-state scenes)",
		straight != null and straight.get_node_or_null("WallVisual") != null)

	# --- 6. a fully enclosed rectangle, with one gate ---
	var lo := base + Vector3(6, 0, 12)
	var hi := base + Vector3(20, 0, 24)
	var sides: Array = []
	sides += await _drag(WALL, Vector3(lo.x, 0, lo.z), Vector3(hi.x, 0, lo.z))
	sides += await _drag(WALL, Vector3(hi.x, 0, lo.z), Vector3(hi.x, 0, hi.z))
	sides += await _drag(WALL, Vector3(hi.x, 0, hi.z), Vector3(lo.x, 0, hi.z))
	sides += await _drag(WALL, Vector3(lo.x, 0, hi.z), Vector3(lo.x, 0, lo.z))
	await _settle_nav()
	var centre: Vector3 = (lo + hi) * 0.5
	var outside: Vector3 = Vector3(hi.x + 8, 0, centre.z)
	var span_x: int = Wall.cell_of(hi).x - Wall.cell_of(lo).x + 1
	var span_z: int = Wall.cell_of(hi).y - Wall.cell_of(lo).y + 1
	var perimeter: int = 2 * span_x + 2 * span_z - 4
	_check("Rectangle perimeter laid, every cell", sides.size() == perimeter,
		"(%d of %d segments)" % [sides.size(), perimeter])
	var closed: bool = true
	for w in sides:
		closed = closed and _popcount(w.connections) == 2
	_check("Every perimeter piece joins exactly two neighbours (closed loop)", closed)
	_check("Enclosure: no path from outside to inside", not _reachable(outside, centre))
	_check("Enclosure: no path from inside to outside", not _reachable(centre, outside))
	var soldier = _spawn(SOLDIER, false, outside)
	var tank = _spawn(TANK, false, outside + Vector3(0, 0, 4))
	await get_tree().process_frame
	for u in [soldier, tank]:
		u.get_node("AttackerComponent").set_physics_process(false)
		u.issue_command(CommandTypes.Type.MOVE, centre)
	var got_in: bool = false
	for i in 12:
		await get_tree().create_timer(0.5).timeout
		if _inside_rect(soldier.global_position, lo, hi) or _inside_rect(tank.global_position, lo, hi):
			got_in = true
	_check("Infantry and vehicles ordered inside cannot get through",
		not got_in, "(soldier %s, tank %s)" % [str(soldier.global_position), str(tank.global_position)])

	# --- 7. the second wall type: a gate in the perimeter ---
	## Replace one segment of the east side with a gate. Selling must
	## trigger a rebake (it never used to). A single 2m hole is still
	## narrower than the navmesh agent (radius 1.7m), so the enclosure is
	## only opened for real by the gate's passage or a wider breach (8).
	var east_mid = _nearest_wall(sides, Vector3(hi.x, 0, centre.z))
	var gate_at: Vector3 = east_mid.global_position
	var iteration_before: int = NavigationServer3D.map_get_iteration_id(_nav.get_world_3d().navigation_map)
	east_mid.sell()
	await get_tree().process_frame
	await _settle_nav()
	_check("Selling a segment re-bakes the navmesh",
		NavigationServer3D.map_get_iteration_id(_nav.get_world_3d().navigation_map) != iteration_before)
	var gap_neighbour = _nearest_wall(sides, gate_at + Vector3(0, 0, 2))
	_check("Segments beside the gap become line ends",
		gap_neighbour != null and gap_neighbour.connections == Wall.SOUTH,
		"(mask %d)" % (gap_neighbour.connections if gap_neighbour != null else -1))
	var gate_list: Array = await _drag(GATE, gate_at, gate_at)
	await _settle_nav()
	var gate = gate_list[0] if gate_list.size() > 0 else null
	_check("Gate placed in the gap", gate != null and gate is Gate)
	if gate != null:
		_check("Gate connects to the walls either side (N and S)",
			gate.connections == (Wall.NORTH | Wall.SOUTH), "(mask %d)" % gate.connections)
		var side_walls: Array = sides.filter(func(w): return is_instance_valid(w))
		side_walls.append(gate)
		_check("Wall-gate-wall has no visible gap",
			_largest_gap(_visual_boxes(side_walls), gate_at + Vector3(0, 0, -3), gate_at + Vector3(0, 0, 3)) < 0.1)
		var owner_layers: int = 1 | Gate.PLAYER_NAV_LAYER
		var enemy_layers: int = 1 | Gate.ENEMY_NAV_LAYER
		_check("The owner can path through their gate", _reachable(outside, centre, owner_layers))
		_check("The enemy cannot path through it", not _reachable(outside, centre, enemy_layers))
		var mine = _spawn(SOLDIER, true, outside + Vector3(0, 0, -3))
		await get_tree().process_frame
		## Walking, not fighting: this is about the gate.
		mine.get_node("AttackerComponent").set_physics_process(false)
		var foe = _spawn(SOLDIER, false, outside + Vector3(0, 0, 3))
		await get_tree().process_frame
		foe.get_node("AttackerComponent").set_physics_process(false)
		mine.issue_command(CommandTypes.Type.MOVE, centre)
		foe.issue_command(CommandTypes.Type.MOVE, centre)
		var mine_in := false
		var foe_in := false
		for i in 30:
			await get_tree().create_timer(0.5).timeout
			mine_in = mine_in or _inside_rect(mine.global_position, lo, hi)
			foe_in = foe_in or (is_instance_valid(foe) and _inside_rect(foe.global_position, lo, hi))
			if mine_in and i > 16:
				break
		_check("A friendly soldier walks in through the gate", mine_in,
			"(at %s)" % str(mine.global_position))
		_check("The enemy soldier still cannot get in", is_instance_valid(foe) and not foe_in,
			"(at %s)" % (str(foe.global_position) if is_instance_valid(foe) else "freed"))

	# --- 8. destroying segments breaches the wall ---
	var north_side: Array = sides.filter(func(w): return is_instance_valid(w) and absf(w.global_position.z - Wall.snap(lo).z) < 0.5)
	var victim = _nearest_wall(north_side, Vector3(centre.x, 0, lo.z))
	var victim2 = _nearest_wall(north_side, victim.global_position + Vector3(2, 0, 0))
	var breach: Vector3 = (victim.global_position + victim2.global_position) * 0.5
	_check("Before the breach the north side is sealed",
		not _reachable(breach + Vector3(0, 0, -5), breach + Vector3(0, 0, 5), 1))
	victim.get_node("HealthComponent").take_damage(999999.0)
	victim2.get_node("HealthComponent").take_damage(999999.0)
	await get_tree().process_frame
	await _settle_nav()
	_check("Destroying two segments opens a breach units can path through",
		_reachable(breach + Vector3(0, 0, -5), breach + Vector3(0, 0, 5), 1))
	var neighbour = _nearest_wall(north_side, breach + Vector3(-3, 0, 0))
	_check("The pieces beside the breach become line ends",
		neighbour != null and is_instance_valid(neighbour) and not (neighbour.connections & Wall.EAST),
		"(mask %d)" % (neighbour.connections if neighbour != null and is_instance_valid(neighbour) else -1))

	## Optional evidence: OM_SHOT_DIR=/some/dir saves what the fences look like.
	var shot_dir: String = OS.get_environment("OM_SHOT_DIR")
	if not shot_dir.is_empty():
		var cam := get_tree().get_first_node_in_group("rts_camera") as Camera3D
		for view in [["enclosure", centre], ["corner_and_cross", (corner_at + Wall.snap(t0)) * 0.5],
				["straight_lines", (mid_h + mid_v) * 0.5]]:
			cam.focus_on(view[1])
			for i in 20:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(shot_dir.path_join("walls_%s.png" % view[0]))

func _popcount(mask: int) -> int:
	var n: int = 0
	for bit in [Wall.NORTH, Wall.EAST, Wall.SOUTH, Wall.WEST]:
		if mask & bit:
			n += 1
	return n

## True when the pieces form one group through their N/E/S/W joins.
func _connected(walls: Array) -> bool:
	if walls.is_empty():
		return false
	var seen: Dictionary = {walls[0]: true}
	var frontier: Array = [walls[0]]
	while not frontier.is_empty():
		var w = frontier.pop_back()
		for dir in Wall.DIRECTIONS:
			if not (w.connections & dir):
				continue
			var n = Wall.at_cell(w.cell + Wall.DIRECTIONS[dir])
			if n != null and walls.has(n) and not seen.has(n):
				seen[n] = true
				frontier.append(n)
	return seen.size() == walls.size()

## Endpoints of a line of walls, extended to the outer faces.
func _line_through(walls: Array, east_west: bool) -> Array:
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for w in walls:
		lo.x = minf(lo.x, w.global_position.x)
		lo.z = minf(lo.z, w.global_position.z)
		hi.x = maxf(hi.x, w.global_position.x)
		hi.z = maxf(hi.z, w.global_position.z)
	if walls.is_empty():
		return [Vector3.ZERO, Vector3.ZERO]
	if east_west:
		return [Vector3(lo.x - 0.9, 0, lo.z), Vector3(hi.x + 0.9, 0, lo.z)]
	return [Vector3(lo.x, 0, lo.z - 0.9), Vector3(lo.x, 0, hi.z + 0.9)]

func _nearest_wall(walls: Array, p: Vector3) -> Node:
	var best: Node = null
	var best_d: float = INF
	for w in walls:
		if not is_instance_valid(w):
			continue
		var d: float = Vector2(w.global_position.x, w.global_position.z).distance_to(Vector2(p.x, p.z))
		if d < best_d:
			best_d = d
			best = w
	return best
