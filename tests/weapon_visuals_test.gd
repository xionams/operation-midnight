extends Node

## Seven weapon classes have to be told apart from the normal gameplay
## camera, and none of it may touch what the weapons actually do.
##
## Before this, every weapon in the game drew the SAME streak, varying
## only in colour and a single girth step chosen off a damage threshold -
## so a torpedo, a rifle round and an artillery shell all crossed the
## field as identical orange sticks at identical speed.

const WEAPONS := {
	"rifle": WeaponVisuals.Class.RIFLE,
	"tower_mg": WeaponVisuals.Class.MACHINE_GUN,
	"tank_cannon": WeaponVisuals.Class.CANNON,
	"at_launcher": WeaponVisuals.Class.ANTI_ARMOR,
	"artillery_gun": WeaponVisuals.Class.ARTILLERY,
	"naval_gun": WeaponVisuals.Class.NAVAL_GUN,
	"torpedo": WeaponVisuals.Class.TORPEDO,
	"dog_bite": WeaponVisuals.Class.MELEE,
}

var _main: Node3D
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-60s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _rounds() -> Array:
	return get_tree().get_nodes_in_group(WeaponVisuals.GROUP)

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
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	FogOfWar.enabled = false
	await _frames(6)

	# --- every weapon declares a class, and they differ ---
	var seen: Dictionary = {}
	for name in WEAPONS:
		var stats: WeaponStats = load("res://config/weapons/%s.tres" % name)
		_check("%s is classed %s" % [name, WeaponVisuals.Class.keys()[WEAPONS[name]]],
			stats.visual_class == WEAPONS[name],
			"got %s" % WeaponVisuals.Class.keys()[stats.visual_class])
		seen[stats.visual_class] = true
	_check("All eight classes are in use across the arsenal", seen.size() == 8,
		"%d distinct" % seen.size())

	# --- the profiles are actually distinguishable, not just labelled ---
	var rifle := WeaponVisuals.PROFILE[WeaponVisuals.Class.RIFLE]
	var mg := WeaponVisuals.PROFILE[WeaponVisuals.Class.MACHINE_GUN]
	var cannon := WeaponVisuals.PROFILE[WeaponVisuals.Class.CANNON]
	var at := WeaponVisuals.PROFILE[WeaponVisuals.Class.ANTI_ARMOR]
	var arty := WeaponVisuals.PROFILE[WeaponVisuals.Class.ARTILLERY]
	var navy := WeaponVisuals.PROFILE[WeaponVisuals.Class.NAVAL_GUN]
	var fish := WeaponVisuals.PROFILE[WeaponVisuals.Class.TORPEDO]

	_check("A machine gun fires a burst; a rifle fires one round",
		int(mg["rounds"]) > 1 and int(rifle["rounds"]) == 1,
		"mg %d vs rifle %d" % [int(mg["rounds"]), int(rifle["rounds"])])
	_check("A cannon round is visibly fatter than a rifle round",
		float(cannon["girth"]) > float(rifle["girth"]) * 2.0,
		"%.1f vs %.1f" % [cannon["girth"], rifle["girth"]])
	_check("Only artillery and the naval gun lob their shells",
		float(arty["arc"]) > 3.0 and float(navy["arc"]) > 0.0
		and float(cannon["arc"]) == 0.0 and float(rifle["arc"]) == 0.0,
		"arty %.1f, navy %.1f, cannon %.1f" % [arty["arc"], navy["arc"], cannon["arc"]])
	_check("Artillery lobs much higher than a flat-trajectory deck gun",
		float(arty["arc"]) > float(navy["arc"]) * 2.0)
	_check("Only rockets, shells and torpedoes leave a trail",
		bool(at["trail"]) and bool(arty["trail"]) and bool(fish["trail"])
		and not bool(rifle["trail"]) and not bool(cannon["trail"]))
	_check("Ordnance that trails is slow enough to follow",
		float(at["speed"]) < float(rifle["speed"]) * 0.4
		and float(fish["speed"]) < float(cannon["speed"]) * 0.3,
		"at %.0f, torpedo %.0f vs rifle %.0f" % [at["speed"], fish["speed"], rifle["speed"]])
	_check("A torpedo is the slowest thing on the field",
		float(fish["speed"]) < float(arty["speed"]))
	_check("Only a launcher throws its smoke backwards",
		String(at["muzzle"]) == "rocket" and String(cannon["muzzle"]) != "rocket")
	_check("A torpedo always ends in a water column",
		String(fish["impact"]) == "water")

	# --- rounds actually travel ---
	var from := Vector3(_main.map.player_base.x, 2.0, _main.map.player_base.z)
	var to: Vector3 = from + Vector3(26, 0, 0)
	var arty_stats: WeaponStats = load("res://config/weapons/artillery_gun.tres")
	WeaponVisuals.projectile(self, arty_stats, from, to)
	await _frames(3)
	var live := _rounds()
	_check("A shell exists in flight", live.size() >= 1, "%d in the air" % live.size())
	if live.size() >= 1:
		var shell: Node3D = live[0]
		var first: Vector3 = shell.global_position
		await _frames(10)
		if is_instance_valid(shell):
			var moved: float = first.distance_to(shell.global_position)
			_check("The shell is travelling, not sitting at the muzzle", moved > 1.0,
				"%.2fm in 10 frames" % moved)
			## The arc: at mid-flight it must be well above the straight line.
			var along: Vector3 = shell.global_position
			var t: float = (along - from).length() / maxf(from.distance_to(to), 0.01)
			var straight: float = lerpf(from.y, to.y, clampf(t, 0.0, 1.0))
			_check("The shell rises above the straight line", along.y > straight + 0.5,
				"%.2fm above" % (along.y - straight))
			_check("The shell leaves a trail", shell.get_child_count() > 0)
	await _frames(60)

	# --- a machine gun puts several rounds in the air, a rifle one ---
	## Sample the PEAK, not one moment. These rounds cross 26m in about a
	## tenth of a second, so a single reading a few frames later catches
	## an empty sky and proves nothing.
	var mg_stats: WeaponStats = load("res://config/weapons/tower_mg.tres")
	WeaponVisuals.projectile(self, mg_stats, from, to)
	var burst: int = 0
	var trace: Array = []
	for i in 16:
		await get_tree().process_frame
		var n: int = _rounds().size()
		trace.append(n)
		burst = maxi(burst, n)
	await _frames(40)
	var rifle_stats: WeaponStats = load("res://config/weapons/rifle.tres")
	WeaponVisuals.projectile(self, rifle_stats, from, to)
	var single: int = 0
	for i in 16:
		await get_tree().process_frame
		single = maxi(single, _rounds().size())
	_check("A burst puts more rounds in the air than a single shot",
		burst > single, "burst %d vs single %d" % [burst, single])
	await _frames(40)

	# --- teeth draw nothing ---
	var bite: WeaponStats = load("res://config/weapons/dog_bite.tres")
	var before: int = _rounds().size()
	var bite_travel: float = WeaponVisuals.projectile(self, bite, from, to)
	await _frames(3)
	_check("A bite fires no projectile", _rounds().size() == before and bite_travel == 0.0)

	# --- and none of it may hold up the damage ---
	await _damage_is_independent()

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()

## The slowest weapon in the game must still kill on the frame it fires.
## Damage is resolved instantly and only the PICTURE of the impact waits
## for the round to arrive; if that ever inverted, a torpedo's 26 m/s
## would become a gameplay delay nobody asked for.
func _damage_is_independent() -> void:
	var sub := preload("res://config/units/submarine.tres")
	var boat := preload("res://config/units/patrol_boat.tres")
	var attacker = sub.unit_scene.instantiate()
	attacker.stats = sub
	attacker.is_player_faction = true
	_main.get_node("Level").add_child(attacker)
	attacker.global_position = Vector3(0, 0, 0)
	var victim = boat.unit_scene.instantiate()
	victim.stats = boat
	victim.is_player_faction = false
	_main.get_node("Level").add_child(victim)
	victim.global_position = Vector3(20, 0, 0)
	await _frames(4)

	var weapon: Weapon = attacker.find_child("Weapon", true, false)
	if weapon == null:
		for child in attacker.get_children():
			if child is Weapon:
				weapon = child
	_check("The submarine carries a torpedo",
		weapon != null and weapon.stats.visual_class == WeaponVisuals.Class.TORPEDO)
	if weapon == null:
		return
	var before: float = victim.health.current_health
	weapon.fire_at(victim, attacker.global_position)
	## One frame: far less than the ~0.8s the torpedo takes to cross 20m.
	await get_tree().process_frame
	_check("A torpedo's damage lands at once, not when the picture arrives",
		victim.health.current_health < before,
		"%.0f -> %.0f hp on the next frame" % [before, victim.health.current_health])
	_check("...while its round is still in the water", _rounds().size() > 0,
		"%d in flight" % _rounds().size())
	attacker.queue_free()
	victim.queue_free()
