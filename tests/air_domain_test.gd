extends Node

## The air layer's rules, before there is an aircraft to fly them.
##
## `WeaponStats.can_target_air` was authored in eleven weapon configs and
## read by nothing: the field was live in the data and dead in the code.
## These checks are what make every one of those settings mean what it
## says, and what stops the damage table quietly treating aircraft as
## unarmoured.

var _main: Node3D
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-58s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var d = _main.get_node_or_null("AIDirector")
	if d: d.enabled = false
	FogOfWar.enabled = false
	for i in 20:
		await get_tree().physics_frame

	# --- the damage table covers air on every row ---
	var short_rows: Array = []
	for damage in DamageTypes.TABLE:
		if DamageTypes.TABLE[damage].size() <= Armor.Type.AIR:
			short_rows.append(DamageTypes.type_name(damage))
	_check("Every damage type has an AIR column", short_rows.is_empty(),
		"short: %s" % str(short_rows))
	## The guard in multiplier() returns 1.0 past the end of a row, so a
	## missing column reads as "full damage" rather than as an error.
	_check("Nothing does full damage to aircraft by omission",
		DamageTypes.multiplier(DamageTypes.Type.SMALL_ARMS, Armor.Type.AIR) < 0.5,
		"%.2f" % DamageTypes.multiplier(DamageTypes.Type.SMALL_ARMS, Armor.Type.AIR))
	_check("Flak is the answer to aircraft",
		DamageTypes.multiplier(DamageTypes.Type.FLAK, Armor.Type.AIR) > 1.0
			and DamageTypes.multiplier(DamageTypes.Type.FLAK, Armor.Type.HEAVY) < 0.3,
		"air %.2f vs heavy %.2f" % [
			DamageTypes.multiplier(DamageTypes.Type.FLAK, Armor.Type.AIR),
			DamageTypes.multiplier(DamageTypes.Type.FLAK, Armor.Type.HEAVY)])

	# --- a flying unit is classified as air ---
	var base: Vector3 = _main.map.player_base
	var flyer := _spawn_flyer(base + Vector3(12, 0, 10))
	await _frames(8)
	_check("A unit whose movement domain is AIR reads as an air target",
		CombatTarget.domain_of(flyer) == CombatTarget.Domain.AIR,
		CombatTarget.domain_name(CombatTarget.domain_of(flyer)))

	# --- ground weapons refuse it, flak accepts it ---
	var rifle: WeaponStats = load("res://config/weapons/rifle.tres")
	var cannon: WeaponStats = load("res://config/weapons/tank_cannon.tres")
	_check("A rifle cannot reach an aircraft",
		not rifle.reaches(CombatTarget.Domain.AIR))
	_check("A tank cannon cannot reach an aircraft",
		not cannon.reaches(CombatTarget.Domain.AIR))
	_check("Ground weapons still reach the ground",
		rifle.reaches(CombatTarget.Domain.LAND))

	var flak := WeaponStats.new()
	flak.can_target_air = true
	flak.damage_type = DamageTypes.Type.FLAK
	_check("A weapon marked can_target_air reaches aircraft",
		flak.reaches(CombatTarget.Domain.AIR))

	# --- and the refusal is enforced on the live weapon path ---
	var soldier = _spawn("res://config/units/rifle_soldier.tres",
		base + Vector3(10, 0, 10))
	await _frames(8)
	print("TEST| (spawned rifleman)")
	var attacker: AttackerComponent = soldier.get_node_or_null("AttackerComponent")
	_check("The rifleman has an attacker", attacker != null)
	if attacker != null and attacker.weapon != null:
		_check("Its weapon refuses an aircraft as a damage target",
			not attacker.weapon.can_damage(flyer))
		soldier.stance = UnitBase.Stance.AGGRESSIVE
		attacker.set_target(flyer, true)
		await _frames(4)
		_check("A rifleman ordered onto an aircraft refuses the order",
			not attacker.has_target())

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()

func _spawn(path: String, at: Vector3) -> Node:
	var stats: UnitStats = load(path)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = true
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(at.x, Terrain.height_at(at.x, at.z), at.z)
	return u

## No aircraft exists yet, so this is a ground unit carrying air stats,
## held INERT.
##
## Letting it tick aborts the engine: a unit whose movement_domain is AIR
## still runs the ground movement - a NavigationAgent3D on the land
## layer, plus the settle-to-terrain pass - and the two disagree about
## where it is until something gives. That is the constraint the real
## aircraft has to satisfy (A2): it cannot ride the ground mover at all.
## Classification is all this stand-in is for, so it never processes.
func _spawn_flyer(at: Vector3) -> Node:
	var stats: UnitStats = load("res://config/units/scout_vehicle.tres").duplicate()
	stats.movement_domain = PlacementDomain.Domain.AIR
	stats.armor_type = Armor.Type.AIR
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = false
	u.process_mode = Node.PROCESS_MODE_DISABLED
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(at.x, Terrain.height_at(at.x, at.z) + 8.0, at.z)
	var health: HealthComponent = u.get_node_or_null("HealthComponent")
	if health != null:
		health.armor_type = Armor.Type.AIR
	return u
