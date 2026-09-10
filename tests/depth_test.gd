extends Node

## Covers the depth systems: the counter table, veterancy, artillery,
## stances, true neutral ownership and captured strategic benefits.

const RIFLE_W := preload("res://config/weapons/rifle.tres")
const AT_W := preload("res://config/weapons/at_launcher.tres")
const CANNON_W := preload("res://config/weapons/tank_cannon.tres")
const ARTY_W := preload("res://config/weapons/artillery_gun.tres")

var _main: Node3D
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	## The skirmish setup screen pauses the tree until START is pressed;
	## harnesses start the match themselves.
	var hud = get_parent().get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	FogOfWar.enabled = false
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-54s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _spawn_unit(path: String, player: bool, pos: Vector3) -> Node:
	var stats: UnitStats = load(path)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	return u

func _run() -> void:
	# --- counter table ---
	var INF := Armor.Type.INFANTRY
	var HVY := Armor.Type.HEAVY
	var STR := Armor.Type.STRUCTURE

	_check("Small arms shred infantry", RIFLE_W.damage_against(INF) > RIFLE_W.damage * 0.9,
		"(%.1f of %.0f)" % [RIFLE_W.damage_against(INF), RIFLE_W.damage])
	_check("Small arms are near useless vs heavy armour",
		RIFLE_W.damage_against(HVY) < RIFLE_W.damage * 0.2,
		"(%.1f)" % RIFLE_W.damage_against(HVY))
	_check("Anti-armor is devastating vs heavy",
		AT_W.damage_against(HVY) > AT_W.damage_against(INF) * 3.0,
		"(%.0f vs %.0f)" % [AT_W.damage_against(HVY), AT_W.damage_against(INF)])
	_check("Anti-armor is poor vs infantry", AT_W.damage_against(INF) < AT_W.damage * 0.5)
	_check("Cannon is inefficient vs dispersed infantry",
		CANNON_W.damage_against(INF) < CANNON_W.damage_against(HVY))
	_check("Explosive is strong vs structures",
		ARTY_W.damage_against(STR) > ARTY_W.damage_against(HVY),
		"(%.0f vs %.0f)" % [ARTY_W.damage_against(STR), ARTY_W.damage_against(HVY)])
	_check("Explosive is strong vs infantry groups",
		ARTY_W.damage_against(INF) > ARTY_W.damage)

	# --- artillery shape ---
	_check("Artillery outranges a tank", ARTY_W.attack_range > CANNON_W.attack_range,
		"(%.0f vs %.0f)" % [ARTY_W.attack_range, CANNON_W.attack_range])
	_check("Artillery has a minimum range", ARTY_W.minimum_range > 0.0)
	_check("Artillery cannot fire point blank", not ARTY_W.in_range(3.0))
	_check("Artillery fires at distance", ARTY_W.in_range(20.0))
	_check("Artillery does splash damage", ARTY_W.splash_radius > 0.0)

	# --- veterancy ---
	var tank = _spawn_unit("res://config/units/assault_vehicle.tres", true, Vector3(-70, 0, 40))
	await get_tree().process_frame
	var vet: VeterancyComponent = tank.get_node_or_null("VeterancyComponent")
	_check("Combat units carry veterancy", vet != null)
	if vet != null:
		var base_hp: float = tank.health.max_health
		_check("Units start Regular", vet.rank == VeterancyComponent.Rank.REGULAR)
		vet.award_damage(1200.0)
		await get_tree().process_frame
		_check("Damage dealt promotes to Veteran",
			vet.rank == VeterancyComponent.Rank.VETERAN,
			"(xp %.0f)" % vet.experience)
		_check("Veteran gains max health", tank.health.max_health > base_hp,
			"(%.0f -> %.0f)" % [base_hp, tank.health.max_health])
		_check("Veteran hits harder", vet.damage_multiplier() > 1.0)
		vet.award_damage(3000.0)
		await get_tree().process_frame
		_check("Further contribution promotes to Elite",
			vet.rank == VeterancyComponent.Rank.ELITE)
		_check("Elite moves faster", vet.speed_multiplier() > 1.0)

	var harvester = _spawn_unit("res://config/units/harvester.tres", true, Vector3(-74, 0, 44))
	await get_tree().process_frame
	_check("Non-combat units earn no rank",
		harvester.get_node_or_null("VeterancyComponent") == null)

	# --- XP goes to whoever dealt the damage, not the last shot ---
	var shooter = _spawn_unit("res://config/units/main_battle_tank.tres", true, Vector3(-66, 0, 40))
	var victim = _spawn_unit("res://config/units/rifle_soldier.tres", false, Vector3(-62, 0, 40))
	await get_tree().process_frame
	var shooter_vet: VeterancyComponent = shooter.get_node("VeterancyComponent")
	var xp_before: float = shooter_vet.experience
	shooter.get_node("Weapon").fire_at(victim, shooter.global_position)
	_check("Dealing damage awards experience", shooter_vet.experience > xp_before,
		"(%.1f -> %.1f)" % [xp_before, shooter_vet.experience])

	# --- stances ---
	_check("Units default to a defensive stance",
		tank.stance == UnitBase.Stance.DEFENSIVE)
	tank.stance = UnitBase.Stance.HOLD
	_check("Hold stance has no chase leash",
		UnitBase.STANCE_LEASH[UnitBase.Stance.HOLD] == 0.0)
	_check("Aggressive stance chases further",
		UnitBase.STANCE_LEASH[UnitBase.Stance.AGGRESSIVE]
		> UnitBase.STANCE_LEASH[UnitBase.Stance.DEFENSIVE])

	# --- patrol ---
	tank.stance = UnitBase.Stance.DEFENSIVE
	tank.issue_command(CommandTypes.Type.PATROL, Vector3(-50, 0, 40))
	_check("Patrol records both ends",
		tank.patrol_to.distance_to(Vector3(-50, 0, 40)) < 1.0
		and tank.patrol_from.distance_to(tank.global_position) < 2.0)

	# --- true neutral ownership ---
	var neutrals: Array = get_tree().get_nodes_in_group("neutral_buildings")
	_check("Map has neutral structures", neutrals.size() >= 3, "(%d)" % neutrals.size())
	var outpost: Node = null
	for n in neutrals:
		if n.stats != null and n.stats.display_name == "Communications Outpost":
			outpost = n
	_check("Communications Outpost exists as neutral", outpost != null)
	if outpost != null:
		_check("Neutral structures are in neither side's building list",
			not outpost.is_in_group("player_buildings")
			and not outpost.is_in_group("enemy_buildings"))
		_check("Neutral structures do not feed a tech tree",
			not TechTree._building_names_for(true).has("Communications Outpost")
			and not TechTree._building_names_for(false).has("Communications Outpost"))

		var power_before: int = GameState.power_generated
		outpost.set_faction(true)
		await get_tree().process_frame
		_check("Capturing transfers ownership",
			outpost.is_player_faction and not outpost.is_neutral)
		_check("Captured structure joins the player's buildings",
			outpost.is_in_group("player_buildings"))
		_check("Captured outpost grants its vision",
			FogOfWar.is_explored_at(outpost.global_position))
		_check("Power bookkeeping stayed consistent",
			GameState.power_generated >= power_before)

	# --- strategic benefits ---
	var supply: Node = null
	for n in get_tree().get_nodes_in_group("strategic_structures"):
		if n.stats != null and n.stats.display_name == "Supply Depot":
			supply = n
	_check("Supply Depot exists", supply != null)
	if supply != null:
		supply.set_faction(true)
		await get_tree().process_frame
		var credits_before: int = GameState.credits
		var waited: float = 0.0
		while waited < 5.0 and GameState.credits <= credits_before:
			waited += get_process_delta_time()
			await get_tree().process_frame
		_check("Captured Supply Depot pays credits over time",
			GameState.credits > credits_before,
			"(+%d in %.1fs)" % [GameState.credits - credits_before, waited])

	# --- garrison ---
	var civilian: Node = null
	for b in get_tree().get_nodes_in_group("neutral_buildings"):
		if b.stats != null and b.stats.display_name == "Civilian Structure":
			civilian = b
			break
	_check("Map has garrisonable civilian structures", civilian != null)
	if civilian != null:
		var garrison = civilian.get_node_or_null("GarrisonComponent")
		_check("Civilian structure has a garrison", garrison != null)
		if garrison != null:
			var squad = _spawn_unit("res://config/units/rifle_soldier.tres", true,
				civilian.global_position + Vector3(3, 0, 0))
			await get_tree().process_frame
			var units_before: int = get_tree().get_nodes_in_group("player_units").size()
			var entered: bool = garrison.enter(squad)
			await get_tree().process_frame
			_check("Infantry can enter a garrison", entered)
			_check("Garrison records the occupant", garrison.occupancy() == 1,
				"(%d)" % garrison.occupancy())
			_check("Occupant leaves the world while inside",
				get_tree().get_nodes_in_group("player_units").size() < units_before)
			_check("Occupying a neutral building claims it",
				civilian.is_player_faction and not civilian.is_neutral)
			_check("Garrison mounts the occupant's weapon",
				civilian.get_node_or_null("GarrisonWeapon") != null)

			var vehicle = _spawn_unit("res://config/units/assault_vehicle.tres", true,
				civilian.global_position + Vector3(4, 0, 0))
			await get_tree().process_frame
			_check("Vehicles cannot garrison", not garrison.enter(vehicle))

			## Losing the building should spill survivors, hurt.
			var before_units: int = get_tree().get_nodes_in_group("player_units").size()
			civilian.get_node("HealthComponent").take_damage(999999.0)
			await get_tree().process_frame
			await get_tree().process_frame
			_check("Destroying a garrison evacuates survivors",
				get_tree().get_nodes_in_group("player_units").size() > before_units,
				"(%d -> %d)" % [before_units, get_tree().get_nodes_in_group("player_units").size()])

	# --- multiple producers speed production ---
	var barracks_stats: BuildingStats = load("res://config/buildings/barracks.tres")
	var b1 = barracks_stats.scene.instantiate()
	b1.stats = barracks_stats; b1.is_player_faction = true
	_main.get_node("Level/NavRegion").add_child(b1)
	b1.global_position = Vector3(-90, 0, 40)
	await get_tree().process_frame
	var single: float = b1.queue._throughput()
	var b2 = barracks_stats.scene.instantiate()
	b2.stats = barracks_stats; b2.is_player_faction = true
	_main.get_node("Level/NavRegion").add_child(b2)
	b2.global_position = Vector3(-96, 0, 46)
	await get_tree().process_frame
	_check("A second Barracks speeds infantry production",
		b1.queue._throughput() > single,
		"(x%.2f -> x%.2f)" % [single, b1.queue._throughput()])
