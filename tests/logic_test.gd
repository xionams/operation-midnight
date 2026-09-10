extends Node

## Verifies the RA2-style unit logics: armor counters, crushing, Engineer
## capture, Spy infiltration, disguise and detection. Runs headless.

const SOLDIER := preload("res://scenes/units/rifle_soldier.tscn")
const SOLDIER_STATS := preload("res://config/units/rifle_soldier.tres")
const ENGINEER := preload("res://scenes/units/engineer.tscn")
const ENGINEER_STATS := preload("res://config/units/engineer.tres")
const SPY := preload("res://scenes/units/spy.tscn")
const SPY_STATS := preload("res://config/units/spy.tres")
const DOG := preload("res://scenes/units/attack_dog.tscn")
const DOG_STATS := preload("res://config/units/attack_dog.tres")
const TANK := preload("res://scenes/units/assault_vehicle.tscn")
const TANK_STATS := preload("res://config/units/assault_vehicle.tres")
const REFINERY := preload("res://scenes/buildings/refinery.tscn")
const REFINERY_STATS := preload("res://config/buildings/refinery.tres")
const POWER := preload("res://scenes/buildings/power_plant.tscn")
const POWER_STATS := preload("res://config/buildings/power_plant.tres")
const BARRACKS := preload("res://scenes/buildings/barracks.tscn")
const BARRACKS_STATS := preload("res://config/buildings/barracks.tres")
const RIFLE := preload("res://config/weapons/rifle.tres")
const CANNON := preload("res://config/weapons/assault_cannon.tres")

var _main: Node3D
var _nav: Node
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	await get_tree().process_frame
	_nav = _main.get_node("Level/NavRegion")
	## These checks are about combat and ability rules. Fog would hide the
	## test subjects and is covered by its own suite, so switch it off here.
	FogOfWar.enabled = false
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-46s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _spawn_unit(scene: PackedScene, stats: UnitStats, player: bool, pos: Vector3) -> Node:
	var u = scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	return u

func _spawn_building(scene: PackedScene, stats: BuildingStats, player: bool, pos: Vector3) -> Node:
	var b = scene.instantiate()
	b.stats = stats
	b.is_player_faction = player
	_nav.add_child(b)
	b.global_position = pos
	return b

func _run() -> void:
	# --- 1. armor multiplier table ---
	_check("Rifle shreds infantry", is_equal_approx(RIFLE.damage_against(Armor.Type.INFANTRY), 16.0),
		"(%.1f)" % RIFLE.damage_against(Armor.Type.INFANTRY))
	_check("Rifle barely dents heavy armour", RIFLE.damage_against(Armor.Type.HEAVY) < 3.0,
		"(%.1f)" % RIFLE.damage_against(Armor.Type.HEAVY))
	_check("Cannon is weak vs infantry", CANNON.damage_against(Armor.Type.INFANTRY) < 15.0,
		"(%.1f)" % CANNON.damage_against(Armor.Type.INFANTRY))
	_check("Cannon is full strength vs heavy", is_equal_approx(CANNON.damage_against(Armor.Type.HEAVY), 40.0),
		"(%.1f)" % CANNON.damage_against(Armor.Type.HEAVY))

	# --- 2. armor applied through real damage ---
	var soldier = _spawn_unit(SOLDIER, SOLDIER_STATS, false, Vector3(-20, 0, 0))
	var tank = _spawn_unit(TANK, TANK_STATS, true, Vector3(-26, 0, 0))
	await get_tree().process_frame
	_check("Infantry carries INFANTRY armor",
		soldier.get_node("HealthComponent").armor_type == Armor.Type.INFANTRY)
	_check("Vehicle carries HEAVY armor",
		tank.get_node("HealthComponent").armor_type == Armor.Type.HEAVY)

	var tank_hp_before: float = tank.get_node("HealthComponent").current_health
	soldier.get_node("Weapon").fire_at(tank, soldier.global_position)
	var tank_lost: float = tank_hp_before - tank.get_node("HealthComponent").current_health
	_check("Rifle fire on a tank is nearly harmless", tank_lost < 3.0, "(lost %.1f hp)" % tank_lost)

	var sol_hp_before: float = soldier.get_node("HealthComponent").current_health
	tank.get_node("Weapon").fire_at(soldier, tank.global_position)
	var sol_lost: float = sol_hp_before - soldier.get_node("HealthComponent").current_health
	_check("Cannon fire on infantry is reduced", sol_lost < 20.0 and sol_lost > 0.0, "(lost %.1f hp)" % sol_lost)

	# --- 3. dog refuses targets it cannot hurt ---
	var dog = _spawn_unit(DOG, DOG_STATS, true, Vector3(-30, 0, 0))
	await get_tree().process_frame
	dog.get_node("AttackerComponent").set_target(tank)
	_check("Dog refuses to target a vehicle", not dog.get_node("AttackerComponent").has_target())
	dog.get_node("AttackerComponent").set_target(soldier)
	_check("Dog will target infantry", dog.get_node("AttackerComponent").has_target())

	# --- 4. crushing ---
	var victim = _spawn_unit(SOLDIER, SOLDIER_STATS, false, Vector3(0, 0, 0))
	var crusher = _spawn_unit(TANK, TANK_STATS, true, Vector3(-5, 0, 0))
	await get_tree().process_frame
	## Isolate the crush mechanic. An armed tank sensibly prefers to stop
	## and shoot infantry from range, so it would never make contact; what
	## is under test here is that contact kills, not what a tank chooses.
	var gun := crusher.get_node_or_null("AttackerComponent")
	if gun:
		gun.queue_free()
	await get_tree().process_frame
	crusher.issue_command(CommandTypes.Type.MOVE, Vector3(6, 0, 0))
	var crushed := false
	for i in 300:
		await get_tree().physics_frame
		if not is_instance_valid(victim):
			crushed = true
			break
	_check("Vehicle crushes enemy infantry it drives into", crushed)

	# --- 5. Engineer capture ---
	var enemy_refinery = _spawn_building(REFINERY, REFINERY_STATS, false, Vector3(20, 0, 20))
	await get_tree().process_frame
	var refineries_before: bool = GameState.has_refinery()
	var engineer = _spawn_unit(ENGINEER, ENGINEER_STATS, true, Vector3(14, 0, 20))
	await get_tree().process_frame
	_check("Engineer accepts an enemy building as a target",
		engineer.special_order(enemy_refinery))
	var captured := false
	for i in 400:
		await get_tree().process_frame
		if enemy_refinery.is_player_faction:
			captured = true
			break
	_check("Engineer captures the building", captured)
	_check("Captured refinery registers with the player", GameState.has_refinery() and not refineries_before)
	_check("Engineer is consumed by the capture", not is_instance_valid(engineer))
	_check("Captured building joins the player group", enemy_refinery.is_in_group("player_buildings"))

	# --- 6. Spy infiltration: loot a refinery ---
	var enemy_ref2 = _spawn_building(REFINERY, REFINERY_STATS, false, Vector3(-20, 0, 24))
	await get_tree().process_frame
	var credits_before: int = GameState.credits
	var spy = _spawn_unit(SPY, SPY_STATS, true, Vector3(-26, 0, 24))
	await get_tree().process_frame
	spy.special_order(enemy_ref2)
	var looted := false
	for i in 400:
		await get_tree().process_frame
		if GameState.credits > credits_before:
			looted = true
			break
	_check("Spy loots credits from an enemy refinery", looted,
		"(%d -> %d)" % [credits_before, GameState.credits])
	_check("Infiltrated building is NOT captured", not enemy_ref2.is_player_faction)

	# --- 7. Spy sabotages production ---
	var enemy_barracks = _spawn_building(BARRACKS, BARRACKS_STATS, false, Vector3(24, 0, -20))
	await get_tree().process_frame
	## The AI has been spending all match; production needs funds to test.
	GameState.enemy_credits = 5000
	enemy_barracks.queue.enqueue(SOLDIER_STATS, SOLDIER)
	enemy_barracks.queue.enqueue(SOLDIER_STATS, SOLDIER)
	_check("Enemy barracks has orders queued", enemy_barracks.queue.queue_length() == 2)
	var cleared: int = enemy_barracks.sabotage_production()
	_check("Sabotage clears the queue", cleared == 2 and enemy_barracks.queue.queue_length() == 0)

	# --- 8. Spy blacks out a power plant ---
	## Player-owned: a blackout is felt by whoever owns the plant, and only
	## the player's grid is tracked.
	var plant = _spawn_building(POWER, POWER_STATS, true, Vector3(-24, 0, -24))
	await get_tree().process_frame
	var gen_before: int = GameState.power_generated
	plant.blackout(5.0)
	_check("Blackout removes the plant from the grid",
		GameState.power_generated == gen_before - POWER_STATS.power_generation and plant.is_offline(),
		"(%d -> %d)" % [gen_before, GameState.power_generated])

	# --- 9. disguise and detection ---
	var enemy_spy = _spawn_unit(SPY, SPY_STATS, false, Vector3(40, 0, 40))
	await get_tree().process_frame
	var disguise: DisguiseAbility = enemy_spy.get_node("DisguiseAbility")
	_check("Spy starts disguised", disguise.is_disguised())
	_check("Disguised enemy spy is invisible to the player",
		not DisguiseAbility.visible_to(enemy_spy, true))
	_check("Spy is still visible to its own side",
		DisguiseAbility.visible_to(enemy_spy, false))

	var guard_dog = _spawn_unit(DOG, DOG_STATS, true, Vector3(44, 0, 40))
	var revealed := false
	for i in 200:
		await get_tree().process_frame
		if not disguise.is_disguised():
			revealed = true
			break
	_check("Attack Dog reveals a nearby enemy Spy", revealed)
	_check("Revealed spy becomes visible to the player",
		DisguiseAbility.visible_to(enemy_spy, true))
