extends Node

## Phase 1 / item 3: garrisonable neutral buildings.
##
## Infantry are sent in with a real right-click, walk to the door, board
## up to capacity, come back out through the sidebar Unload button as the
## SAME units, and are ejected - or cleaned up - when the building goes.

const SOLDIER_STATS := preload("res://config/units/rifle_soldier.tres")
const ENGINEER_STATS := preload("res://config/units/engineer.tres")
const TANK_STATS := preload("res://config/units/assault_vehicle.tres")
const HOUSE_STATS := preload("res://config/buildings/civilian_house.tres")
const BLOCK_STATS := preload("res://config/buildings/civilian_structure.tres")
const WAREHOUSE_STATS := preload("res://config/buildings/civilian_warehouse.tres")

var _main: Node3D
var _fails: Array = []
var _saved_block: Dictionary = {}

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
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-56s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _spawn(stats: UnitStats, player: bool, pos: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	return u

func _spawn_civilian(stats: BuildingStats, pos: Vector3) -> Node:
	var b = stats.scene.instantiate()
	b.stats = stats
	b.is_neutral = true
	_main.get_node("Level/NavRegion").add_child(b)
	b.global_position = pos
	EventBus.building_placed.emit(b)
	return b

func _wait_seconds(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _camera() -> Camera3D:
	return get_tree().get_first_node_in_group("rts_camera") as Camera3D

func _right_click_on(node: Node3D) -> void:
	var cam := _camera()
	cam.focus_on(node.global_position)
	await get_tree().process_frame
	await get_tree().physics_frame
	var aim: Vector3 = node.global_position + Vector3.UP * (node.stats.body_size.y - 0.3)
	var pos: Vector2 = cam.unproject_position(aim)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame
	var up := e.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame

func _select(entities: Array) -> void:
	SelectionManager.clear_selection()
	for u in entities:
		SelectionManager._select_unit(u)

func _run() -> void:
	## Open ground in the south-west quarter, clear of the map's own
	## civilian buildings and blockers.
	var site := Vector3(-60, 0, 10)
	var hold_house: OccupantHold
	var house = _spawn_civilian(HOUSE_STATS, site)
	var block = _spawn_civilian(BLOCK_STATS, site + Vector3(20, 0, 0))
	var warehouse = _spawn_civilian(WAREHOUSE_STATS, site + Vector3(0, 0, -24))
	await _wait_seconds(0.5)

	# --- capacity is data, per building type ---
	hold_house = house.get_node_or_null("GarrisonComponent")
	var hold_block: OccupantHold = block.get_node_or_null("GarrisonComponent")
	var hold_wh: OccupantHold = warehouse.get_node_or_null("GarrisonComponent")
	_check("House, block and warehouse are all garrisonable",
		hold_house != null and hold_block != null and hold_wh != null)
	_check("Capacity follows building size (house < block < warehouse)",
		hold_house.capacity == 2 and hold_block.capacity == 4 and hold_wh.capacity == 8,
		"(%d / %d / %d)" % [hold_house.capacity, hold_block.capacity, hold_wh.capacity])
	_check("The map places garrisonable buildings of different sizes",
		_map_kinds().size() >= 2, "(%s)" % ", ".join(_map_kinds()))

	# --- right-click three soldiers onto a two-man house ---
	var squad: Array = []
	for i in 3:
		squad.append(_spawn(SOLDIER_STATS, true, site + Vector3(-4 + i * 2, 0, 16)))
	await get_tree().process_frame
	InfantryStance.of(squad[0]).set_mode(InfantryStance.Mode.CROUCH)
	squad[0].health.current_health = 101.0
	var pop_before: int = TechTree.population_used(true)
	_select(squad)
	await _right_click_on(house)
	_check("Right-click on a neutral house orders a garrison",
		squad[0].current_command == CommandTypes.Type.GARRISON,
		"(%s)" % CommandTypes.type_name(squad[0].current_command))
	## An enemy along the way must not derail the order.
	var bait = _spawn(SOLDIER_STATS, false, site + Vector3(8, 0, 12))
	await get_tree().process_frame
	bait.get_node("AttackerComponent").set_physics_process(false)
	await _wait_seconds(8.0)
	_check("House holds exactly its capacity", hold_house.occupancy() == 2,
		"(%d)" % hold_house.occupancy())
	var inside: Array = []
	var outside: Array = []
	for u in squad:
		if hold_house.contains(u):
			inside.append(u)
		else:
			outside.append(u)
	_check("The building tracks WHICH units are inside",
		inside.size() == 2 and outside.size() == 1)
	var off_map: bool = true
	var unfindable: bool = true
	var unselected: bool = true
	for u in inside:
		off_map = off_map and is_instance_valid(u) and not u.is_inside_tree()
		unfindable = unfindable and not get_tree().get_nodes_in_group("player_units").has(u)
		unselected = unselected and not SelectionManager.selected_units.has(u)
	_check("Occupants are no longer standing in the world", off_map)
	_check("Occupants cannot be found by group queries (untargetable)", unfindable)
	_check("Occupants were dropped from the selection", unselected)
	_check("The extra soldier is refused and waits outside",
		outside.size() == 1 and outside[0].is_inside_tree()
		and outside[0].current_command == CommandTypes.Type.STOP,
		"(%s)" % (CommandTypes.type_name(outside[0].current_command) if outside.size() == 1 else "-"))
	_check("A refused soldier is at the door, not somewhere else",
		outside.size() == 1 and CombatTarget.distance(outside[0].global_position, house) < 4.0)
	_check("Capacity cannot be exceeded directly either",
		not hold_house.enter(outside[0]) and hold_house.occupancy() == 2)
	_check("Garrisoned soldiers still count against the unit cap",
		TechTree.population_used(true) == pop_before, "(%d vs %d)" % [TechTree.population_used(true), pop_before])
	_check("Occupying a neutral house claims it for the player",
		house.is_player_faction and not house.is_neutral)
	_check("The garrison fires with its occupants' weapon",
		house.get_node_or_null("GarrisonWeapon") != null)
	bait.queue_free()

	# --- unarmed infantry can garrison too (they used to be unable) ---
	var engineer = _spawn(ENGINEER_STATS, true, site + Vector3(20, 0, 12))
	await get_tree().process_frame
	engineer.issue_command(CommandTypes.Type.GARRISON, block.global_position, block)
	await _wait_seconds(6.0)
	_check("An unarmed Engineer can garrison", hold_block.contains(engineer))

	# --- vehicles are refused ---
	var tank = _spawn(TANK_STATS, true, site + Vector3(26, 0, 6))
	await get_tree().process_frame
	_check("Vehicles cannot garrison", not hold_block.enter(tank))
	tank.queue_free()

	# --- exit through the sidebar ---
	_select([house])
	var hud = _main.get_node_or_null("HUD")
	var unload: Button = hud.find_child("UnloadButton", true, false) if hud else null
	_check("Sidebar has an Unload button", unload != null)
	if unload != null:
		unload.pressed.emit()
	await get_tree().process_frame
	_check("Unload empties the house", hold_house.occupancy() == 0)
	var back: bool = true
	var beside: bool = true
	for u in inside:
		back = back and _in_world(u) and get_tree().get_nodes_in_group("player_units").has(u)
		beside = beside and _in_world(u) and CombatTarget.distance(u.global_position, house) < 4.5
	_check("The same units come back out (not copies)", back)
	_check("They come out beside the building", beside)
	_check("Health and posture survive the stay",
		squad[0].health.current_health == 101.0 and InfantryStance.of(squad[0]).is_crouched())
	_check("An emptied civilian house reverts to neutral", house.is_neutral)
	_check("It stops shooting once empty", house.get_node_or_null("GarrisonWeapon") == null
		or house.get_node("GarrisonWeapon").is_queued_for_deletion())
	var walked_from: Vector3 = squad[0].global_position
	squad[0].issue_command(CommandTypes.Type.MOVE, walked_from + Vector3(0, 0, 8))
	await _wait_seconds(1.5)
	_check("A soldier who left can move again",
		squad[0].global_position.distance_to(walked_from) > 1.0)

	# --- the other side can now take it ---
	var enemy_a = _spawn(SOLDIER_STATS, false, site + Vector3(-3, 0, -6))
	await get_tree().process_frame
	_check("An abandoned house is open to the enemy", hold_house.enter(enemy_a))
	_check("...and becomes theirs", not house.is_neutral and not house.is_player_faction)
	_check("A player soldier cannot join an enemy garrison", not hold_house.enter(squad[1]))

	# --- destruction ejects and hurts the occupants, no dangling refs ---
	var full_hp = _spawn(SOLDIER_STATS, false, site + Vector3(3, 0, -6))
	await get_tree().process_frame
	hold_house.enter(full_hp)
	var weak = enemy_a
	weak.health.current_health = 20.0
	## (weak re-enters with 20hp by leaving and coming back)
	hold_house.exit(weak)
	hold_house.enter(weak)
	house.get_node("HealthComponent").take_damage(999999.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("Destroying the building empties the hold",
		not is_instance_valid(hold_house) or hold_house.occupancy() == 0)
	_check("A healthy occupant survives, hurt, back in the world",
		is_instance_valid(full_hp) and full_hp.is_inside_tree()
		and full_hp.health.current_health < full_hp.health.max_health)
	_check("A badly hurt occupant dies in the collapse", not is_instance_valid(weak)
		or weak.health.is_dead())

	# --- selling a garrisoned building lets them walk out ---
	var sold_squad: Array = []
	for i in 2:
		sold_squad.append(_spawn(SOLDIER_STATS, true, block.global_position + Vector3(4 + i, 0, 4)))
	await get_tree().process_frame
	## The engineer is already inside; block is the player's now.
	for u in sold_squad:
		hold_block.enter(u)
	_check("Block holds engineer + two riflemen", hold_block.occupancy() == 3)
	InfantryStance.of(sold_squad[0]).set_mode(InfantryStance.Mode.CROUCH)
	var entry: Dictionary = SaveGame._capture_building(block)
	_check("Saving records who is inside a garrison",
		entry.get("occupants", []).size() == 3, "(%d)" % entry.get("occupants", []).size())
	_saved_block = entry
	block.sell()
	await get_tree().process_frame
	_check("Selling a garrisoned building releases everyone",
		_in_world(sold_squad[0]) and _in_world(sold_squad[1]) and _in_world(engineer))

	# --- a building removed without dying frees its occupants: no leaks ---
	var ghosts: Array = []
	for i in 3:
		ghosts.append(_spawn(SOLDIER_STATS, true, warehouse.global_position + Vector3(6 + i, 0, 6)))
	await get_tree().process_frame
	for u in ghosts:
		hold_wh.enter(u)
	_check("Warehouse takes three of its eight", hold_wh.occupancy() == 3 and hold_wh.free_slots() == 5)
	warehouse.free()
	await get_tree().process_frame
	var all_freed: bool = true
	for u in ghosts:
		all_freed = all_freed and not is_instance_valid(u)
	_check("Removing a building frees the units held inside it", all_freed)

	# --- a saved garrison comes back garrisoned ---
	## Through SaveGame.restore with the game's own spawners, as a resumed
	## match does. The block was sold above, so its cell is free again.
	var pop_pre_restore: int = TechTree.population_used(true)
	SaveGame.restore(_main, {"buildings": [_saved_block], "credits": GameState.credits,
			"enemy_credits": GameState.enemy_credits},
		func(stats, is_player, position): return _main._spawn_unit(stats.unit_scene, stats, is_player, position),
		func(stats, is_player, position, neutral): return _main._spawn_saved_building(stats, is_player, position, neutral),
		func(position, amount): _main._spawn_resource_node(position, amount))
	await get_tree().process_frame
	var restored: Node = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.stats == BLOCK_STATS and not b.is_queued_for_deletion() \
			and Vector2(b.global_position.x, b.global_position.z).distance_to(
				Vector2(_saved_block["position"][0], _saved_block["position"][2])) < 0.5:
			restored = b
	var restored_hold: OccupantHold = restored.get_node_or_null("GarrisonComponent") if restored else null
	_check("Restored building is garrisoned again",
		restored_hold != null and restored_hold.occupancy() == 3,
		"(%d)" % (restored_hold.occupancy() if restored_hold else -1))
	var crouched_back: bool = false
	if restored_hold != null:
		for u in restored_hold.occupants:
			if InfantryStance.of(u) != null and InfantryStance.of(u).is_crouched():
				crouched_back = true
	_check("Occupants keep their posture through save/restore", crouched_back)
	_check("Restored occupants are counted, not duplicated in the world",
		TechTree.population_used(true) == pop_pre_restore + 3,
		"(%d -> %d)" % [pop_pre_restore, TechTree.population_used(true)])

func _in_world(u) -> bool:
	return is_instance_valid(u) and u.is_inside_tree()

func _map_kinds() -> Array:
	var kinds: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.get_node_or_null("GarrisonComponent") != null \
			and b.stats != null and not kinds.has(b.stats.display_name):
			kinds.append(b.stats.display_name)
	return kinds
