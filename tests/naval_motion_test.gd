extends Node

## Ships should look like hulls in water, not sprites being dragged.
##
## They already rode a swell and turned a propeller, but they turned flat
## - no heel - their wake was the same size at two knots as at full
## ahead, and a submarine's dive was a single-frame jump because the body
## drops the instant the order lands.

const COAST := preload("res://config/maps/coastline.tres")
const BOAT := preload("res://config/units/patrol_boat.tres")
const SUB := preload("res://config/units/submarine.tres")

var _main: Node3D
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-58s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _launch(stats, at: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = true
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(at.x, Water.level, at.z)
	return u

func _ready() -> void:
	GameState.selected_map = COAST
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
	for i in 30:
		await get_tree().physics_frame

	var sea: Vector3 = Water.nearest_water(COAST.player_base + Vector3(0, 0, 70), 150.0)
	_check("Found open water", Water.is_navigable(sea.x, sea.z), "%s" % sea)
	if not Water.is_navigable(sea.x, sea.z):
		_finish()
		return

	# --- heel ---
	var boat = _launch(BOAT, sea)
	await _frames(10)
	var anim = boat.get_node_or_null("ModelAnimator")
	_check("The boat is animated as something afloat", anim != null and anim._afloat)
	if anim == null:
		_finish()
		return

	## Run it straight first, then turn it hard, and compare how far the
	## hull leans in each case.
	boat.move_to(sea + Vector3(34, 0, 0))
	## Skip the first stretch: the boat turns to face its destination
	## before it runs straight, and that turn heels it just as a later one
	## would. Measuring from frame zero compares a turn against a turn.
	for i in 70:
		await get_tree().process_frame
	var straight_roll: float = 0.0
	for i in 70:
		await get_tree().process_frame
		straight_roll = maxf(straight_roll, absf(anim._heel))
	boat.move_to(boat.global_position + Vector3(-6, 0, 34))
	var turn_roll: float = 0.0
	for i in 110:
		await get_tree().process_frame
		turn_roll = maxf(turn_roll, absf(anim._heel))
	_check("A turning ship heels over", turn_roll > straight_roll + 0.008,
		"straight %.4f vs turning %.4f rad" % [straight_roll, turn_roll])
	_check("...but not absurdly", turn_roll < 0.35, "%.3f rad" % turn_roll)

	# --- wake scales with speed ---
	var wake: CPUParticles3D = anim._wake
	_check("The boat has a wake", wake != null)
	if wake != null:
		boat.move_to(sea + Vector3(50, 0, 0))
		var fast: float = 0.0
		for i in 80:
			await get_tree().process_frame
			if wake.emitting:
				fast = maxf(fast, wake.scale_amount_max)
		boat.stop_moving()
		var slow: float = INF
		for i in 200:
			await get_tree().process_frame
			if not wake.emitting:
				slow = 0.0
				break
			slow = minf(slow, wake.scale_amount_max)
		_check("A ship under way throws a bigger wake than one slowing",
			fast > slow, "under way %.2f, slowing %.2f" % [fast, slow])
	boat.queue_free()

	# --- the dive takes a moment ---
	var sub = _launch(SUB, sea + Vector3(-14, 0, 0))
	await _frames(20)
	var sub_anim = sub.get_node_or_null("ModelAnimator")
	var stealth = sub.get_node_or_null("Stealth")
	_check("The submarine can submerge", stealth != null and sub_anim != null)
	if stealth != null and sub_anim != null:
		## Surface it, let it settle, then let it dive again.
		stealth.surface()
		for i in 40:
			await get_tree().process_frame
		var lag_seen: float = 0.0
		for i in 150:
			await get_tree().process_frame
			lag_seen = maxf(lag_seen, absf(sub_anim._dive_lag))
		_check("The hull lags behind the dive instead of snapping down",
			lag_seen > 0.05, "%.2fm of catch-up seen" % lag_seen)
		await _frames(120)
		_check("...and catches up afterwards", absf(sub_anim._dive_lag) < 0.05,
			"%.3f" % sub_anim._dive_lag)
	_finish()

func _finish() -> void:
	GameState.selected_map = null
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()
