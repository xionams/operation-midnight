extends Node

## Phase 1 / item 5: construction territory.
##
## Builds a base the way a player does - each structure a couple of metres
## from the last, heading outward from the HQ - through the real
## placer's validity check, and asserts every step is legal, the base
## really grows, the territory has no holes, the drawn outline is exactly
## the legal boundary, and a wall line can be dragged along the outer
## edge of the base with real mouse input.

const HQ := preload("res://config/buildings/command_hq.tres")
const POWER := preload("res://config/buildings/power_plant.tres")
const REFINERY := preload("res://config/buildings/refinery.tres")
const BARRACKS := preload("res://config/buildings/barracks.tres")
const FACTORY := preload("res://config/buildings/war_factory.tres")
const MG := preload("res://config/buildings/mg_tower.tres")
const WALL := preload("res://config/buildings/wall.tres")
const GATE := preload("res://config/buildings/gate.tres")

const GAP: float = 2.0

var _main: Node3D
var _placer: BuildingPlacer
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
	await _run()
	_placer.cancel_placement()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-56s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _hq() -> Node:
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b.stats == HQ:
			return b
	return null

## Placement exactly as the player's click would validate it.
func _legal(stats: BuildingStats, pos: Vector3) -> bool:
	_placer.start_placement(stats)
	var ok: bool = _placer._check_validity(pos)
	_placer.cancel_placement()
	return ok

func _place(stats: BuildingStats, pos: Vector3) -> Node:
	_placer.start_placement(stats)
	_placer._spawn(pos)
	_placer.cancel_placement()
	await get_tree().process_frame
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b.stats == stats and Vector2(b.global_position.x, b.global_position.z) \
			.distance_to(Vector2(pos.x, pos.z)) < 0.1:
			return b
	return null

func _run() -> void:
	# --- radii are data, sized by role ---
	_check("Radius by role: HQ > production > power > defence > wall",
		HQ.build_radius_bonus > FACTORY.build_radius_bonus
		and FACTORY.build_radius_bonus >= BARRACKS.build_radius_bonus
		and BARRACKS.build_radius_bonus > POWER.build_radius_bonus
		and POWER.build_radius_bonus > MG.build_radius_bonus
		and MG.build_radius_bonus > WALL.build_radius_bonus,
		"(%.0f / %.0f / %.0f / %.0f / %.0f / %.0f)" % [HQ.build_radius_bonus,
			FACTORY.build_radius_bonus, BARRACKS.build_radius_bonus,
			POWER.build_radius_bonus, MG.build_radius_bonus, WALL.build_radius_bonus])
	_check("Walls and gates grant no territory",
		WALL.build_radius_bonus == 0.0 and GATE.build_radius_bonus == 0.0)

	var hq = _hq()
	_check("Player HQ exists", hq != null)
	if hq == null:
		return
	var origin: Vector3 = hq.global_position

	# --- every structure fits snugly beside every other ---
	## The complaint: structures had to be spaced unnaturally far apart.
	## Each type, placed GAP metres from the one before it on any side, must
	## land inside the territory of that one alone.
	## Anchors are the structures a base grows from; the neighbour can be
	## anything, including a defence tucked in beside them.
	var anchors: Array = [HQ, FACTORY, BARRACKS, REFINERY, POWER]
	var neighbours: Array = [HQ, FACTORY, BARRACKS, REFINERY, POWER, MG]
	var snug: bool = true
	var worst: String = ""
	for a in anchors:
		for b in neighbours:
			var dx: float = (a.footprint.x + b.footprint.x) * 0.5 + GAP
			var dz: float = (a.footprint.y + b.footprint.y) * 0.5 + GAP
			## Worst case is the diagonal neighbour.
			var reach: float = Vector2(dx, dz).length()
			if reach > a.build_radius_bonus:
				snug = false
				worst = "%s beside %s needs %.1fm, has %.0fm" % [b.display_name, a.display_name, reach, a.build_radius_bonus]
	_check("Anything fits 2m beside any HQ/production/power building, even diagonally",
		snug, "(%s)" % worst)

	# --- a natural chain of buildings extends the base ---
	var east := Vector3(1, 0, 0)
	var chain: Array = [POWER, REFINERY, BARRACKS, POWER, FACTORY]
	var last_stats: BuildingStats = HQ
	var last_pos: Vector3 = origin
	var reach_before: float = HQ.build_radius_bonus
	var all_legal: bool = true
	var placed: Array = []
	var detail: String = ""
	for stats in chain:
		var step: float = (last_stats.footprint.x + stats.footprint.x) * 0.5 + GAP
		var pos: Vector3 = last_pos + east * step
		pos.y = 0.0
		var ok: bool = _legal(stats, pos)
		detail += " %s@%+.0f:%s" % [stats.display_name.get_slice(" ", 0), pos.x - origin.x, "ok" if ok else "NO"]
		if not ok:
			all_legal = false
			break
		placed.append(await _place(stats, pos))
		last_stats = stats
		last_pos = pos
	_check("Five structures placed 2m apart outward are all legal", all_legal, "(%s)" % detail.strip_edges())
	var edge_now: float = 0.0
	for x in range(0, 200):
		if BuildTerritory.contains(get_tree(), origin + east * float(x), true):
			edge_now = float(x)
	_check("The chain pushes the edge well past the HQ's own",
		edge_now >= reach_before + 30.0, "(edge %.0fm, HQ alone %.0fm)" % [edge_now, reach_before])

	# --- no holes: the base is one continuous area ---
	var holes: int = 0
	for x in range(0, int(edge_now)):
		for z in [-6, 0, 6]:
			if not BuildTerritory.contains(get_tree(), origin + Vector3(x, 0, z), true):
				holes += 1
	_check("Overlapping territories form one continuous area", holes == 0, "(%d holes)" % holes)

	# --- the drawn outline IS the legal boundary ---
	var lines := BuildTerritory.outline(get_tree(), true)
	_check("An outline is drawn", lines.size() > 20, "(%d points)" % lines.size())
	var circles := BuildTerritory.circles(get_tree(), true)
	var mismatches: int = 0
	var inner_arcs: int = 0
	for i in range(0, lines.size(), 2):
		var mid: Vector3 = (lines[i] + lines[i + 1]) * 0.5
		## Find the circle this arc belongs to (the one it lies on).
		var centre := Vector3.INF
		for c in circles:
			if absf(Vector2(mid.x, mid.z).distance_to(Vector2(c[0].x, c[0].z)) - c[1]) < 0.2:
				centre = c[0]
				break
		if not centre.is_finite():
			continue
		var outward: Vector3 = (mid - centre)
		outward.y = 0.0
		outward = outward.normalized()
		var inside_ok: bool = BuildTerritory.contains(get_tree(), mid - outward * 0.3, true)
		var outside_ok: bool = BuildTerritory.contains(get_tree(), mid + outward * 0.3, true)
		if not inside_ok or outside_ok:
			mismatches += 1
		## An arc that is buried inside another building's territory would
		## be a drawn line the player cannot place across - there must be none.
		if outside_ok:
			inner_arcs += 1
	_check("Every drawn edge has legal ground inside and none outside",
		mismatches == 0, "(%d of %d segments disagree)" % [mismatches, lines.size() / 2])
	_check("No rings drawn inside the base (union, not circles)", inner_arcs == 0)
	_placer.start_placement(POWER)
	var ring_mesh: ImmediateMesh = _placer._radius_ring.mesh
	_check("The placer draws that outline while placing",
		ring_mesh != null and ring_mesh.get_surface_count() == 1)
	_placer.cancel_placement()
	_placer.start_placement(WALL)
	var wall_ring: ImmediateMesh = _placer._radius_ring.mesh
	_check("Wall placement draws the widened wall outline",
		wall_ring != null and wall_ring.get_surface_count() == 1)
	_placer.cancel_placement()

	# --- walls: special placement rules ---
	var edge_point: Vector3 = origin + east * edge_now
	_check("A wall may go just past the territory edge",
		_legal(WALL, edge_point + east * (BuildTerritory.WALL_MARGIN - 1.0)))
	_check("...but not beyond the wall margin",
		not _legal(WALL, edge_point + east * (BuildTerritory.WALL_MARGIN + 1.5)))
	_check("A normal structure may not go past the edge",
		not _legal(POWER, edge_point + east * 3.0))
	await _place(WALL, edge_point + east * 4.0)
	_check("Walls do not creep the territory outward",
		not BuildTerritory.contains(get_tree(), edge_point + east * 3.0, true))

	# --- a fence along the outside of the base, laid with the mouse ---
	## North side of the chain, just outside the outermost structures,
	## running the length of the base.
	var line_z: float = origin.z - (FACTORY.footprint.y * 0.5 + 3.0)
	var from := Vector3(last_pos.x - 30.0, 0.0, line_z)
	var to := Vector3(last_pos.x + 6.0, 0.0, line_z)
	var walls_before: int = _count_walls()
	GameState.add_credits(5000)
	await _drag_wall(from, to)
	var laid: int = _count_walls() - walls_before
	var expected: int = int(from.distance_to(to) / WALL.footprint.x) + 1
	_check("A dragged fence near the territory edge is fully placed",
		laid == expected, "(%d of %d segments)" % [laid, expected])

func _count_walls() -> int:
	var n: int = 0
	for b in get_tree().get_nodes_in_group("walls"):
		if is_instance_valid(b) and b.is_in_group("player_buildings"):
			n += 1
	return n

func _drag_wall(from: Vector3, to: Vector3) -> void:
	var cam := get_tree().get_first_node_in_group("rts_camera") as Camera3D
	cam.focus_on((from + to) * 0.5)
	for i in 3:
		await get_tree().process_frame
	_placer.start_placement(WALL)
	await get_tree().process_frame
	var a: Vector2 = cam.unproject_position(from)
	var b: Vector2 = cam.unproject_position(to)
	await _mouse_move(a)
	await _mouse_button(a, true)
	for t in [0.25, 0.5, 0.75, 1.0]:
		await _mouse_move(a.lerp(b, t))
	await _mouse_button(b, false)
	await get_tree().process_frame
	_placer.cancel_placement()

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
