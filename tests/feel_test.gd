extends Node

## The feedback layer: acknowledgement, markers and camera reaction.
##
## Feel is the easiest thing to claim and the hardest to prove, so each
## check here is about an observable the player would notice if it broke
## - a ring that never appears, a marker that never clears, a camera that
## shakes for something happening across the map, or one that never
## settles back.

var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-54s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _wait(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

func _ready() -> void:
	var scene := get_parent()
	await get_tree().process_frame
	var hud = scene.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	get_tree().paused = false
	await get_tree().process_frame

	var camera = scene.find_child("RTSCamera", true, false)
	_check("The camera exists", camera != null)
	var units := get_tree().get_nodes_in_group("player_units")
	_check("There are units to select", units.size() >= 2, "(%d)" % units.size())
	if camera == null or units.size() < 2:
		return _finish()

	# --- selection acknowledgement ---
	var unit = units[0]
	_check("A unit starts unselected", not unit.selection_ring.visible)
	unit.set_selected(true)
	_check("Selecting shows the ring", unit.selection_ring.visible)
	_check("The ring pops rather than just appearing",
		unit.selection_ring.scale.x > 1.05,
		"(scale %.2f)" % unit.selection_ring.scale.x)
	await _wait(0.5)
	_check("The pop settles back to size",
		absf(unit.selection_ring.scale.x - 1.0) < 0.05,
		"(scale %.2f)" % unit.selection_ring.scale.x)
	unit.set_selected(false)
	_check("Deselecting hides the ring", not unit.selection_ring.visible)

	## A harvester must not look like a tank in a selection.
	var harvester_colour := Color.BLACK
	var soldier_colour := Color.BLACK
	for u in units:
		var mat = u.selection_ring.material_override
		if u.stats != null and u.stats.is_harvester:
			harvester_colour = mat.albedo_color
		else:
			soldier_colour = mat.albedo_color
	if harvester_colour != Color.BLACK:
		_check("Harvesters carry a different ring colour",
			harvester_colour != soldier_colour)

	# --- command markers ---
	var before: int = _markers()
	CommandMarker.spawn(scene.get_node("Level"), Vector3(0, 0, 0),
		CommandTypes.Type.MOVE)
	await get_tree().process_frame
	_check("Ordering leaves a marker", _markers() > before, "(%d)" % _markers())
	await _wait(CommandMarker.LIFETIME + 0.4)
	_check("The marker clears itself", _markers() == before,
		"(%d left)" % _markers())

	var move_colour := CommandMarker.new()._color_for(CommandTypes.Type.MOVE)
	var attack_colour := CommandMarker.new()._color_for(CommandTypes.Type.ATTACK)
	_check("Move and attack orders are not the same colour",
		move_colour != attack_colour)

	# --- camera reaction ---
	camera.focus_on(Vector3.ZERO)
	await _wait(1.0)

	## Measured on the shake offset itself, not on world position: the
	## camera eases toward its target asymptotically and never exactly
	## arrives, so a couple of centimetres of ordinary easing drift would
	## otherwise read as a shake that never settled.
	camera.shake(0.6, Vector3.ZERO)
	await _wait(0.05)
	_check("A nearby explosion shakes the camera",
		camera._shake_offset.length() > 0.01,
		"(%.3f m)" % camera._shake_offset.length())

	await _wait(1.6)
	_check("The shake settles rather than lingering",
		camera._shake_offset.length() < 0.001,
		"(%.4f m)" % camera._shake_offset.length())

	## And something across the map should not.
	camera.shake(0.6, Vector3(200, 0, 200))
	await _wait(0.05)
	_check("An explosion across the map does not shake the camera",
		camera._shake_offset.length() < 0.001,
		"(%.4f m)" % camera._shake_offset.length())

	## Shake must never drag the battlefield the player is looking at.
	var resting: Vector3 = camera.global_position
	var pan_before: Vector3 = camera.pan_target
	camera.shake(1.0, Vector3.ZERO)
	await _wait(0.3)
	_check("Shaking never moves what the camera is looking at",
		camera.pan_target.is_equal_approx(pan_before))
	await _wait(1.5)

	# --- camera easing ---
	camera.focus_on(Vector3(40, 0, 40))
	await _wait(0.03)
	var moved: float = camera.global_position.distance_to(resting)
	_check("Focusing eases rather than teleporting", moved < 30.0, "(%.1f m)" % moved)
	await _wait(2.0)
	_check("And it arrives", camera.global_position.distance_to(resting) > 20.0,
		"(%.1f m)" % camera.global_position.distance_to(resting))

	_finish()

func _markers() -> int:
	var count: int = 0
	for node in get_parent().get_node("Level").get_children():
		if node is CommandMarker:
			count += 1
	return count

func _finish() -> void:
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()
