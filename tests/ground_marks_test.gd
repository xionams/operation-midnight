extends Node

## The battlefield has to remember. Everything else the VFX layer does is
## momentary, so without this the ground ten minutes into a match looks
## exactly as it did at the start.

const EXPECTED: int = 30

var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-52s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _ready() -> void:
	var main := get_parent()
	await get_tree().process_frame
	var hud = main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame

	_check("Ground starts unmarked", GroundMarks.count() == 0,
		"(%d)" % GroundMarks.count())

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var centre: Vector3 = main.map.player_base + Vector3(0, 0, 26)
	for i in EXPECTED:
		var point: Vector3 = centre + Vector3(
			rng.randf_range(-18, 18), 0.0, rng.randf_range(-12, 12))
		if i % 5 == 0:
			VFX.explosion_large(main, point)
		elif i % 2 == 0:
			VFX.explosion_small(main, point)
		else:
			VFX.shell_impact(main, point)

	_check("Every explosion marks the ground",
		GroundMarks.count() == EXPECTED,
		"(%d of %d)" % [GroundMarks.count(), EXPECTED])

	## The ring buffer is what bounds the cost. Overrun it and the count
	## must stop rather than the instance list growing without limit.
	for i in GroundMarks.MAX_MARKS + 40:
		VFX.shell_impact(main, centre)
	_check("Mark count is capped by the ring buffer",
		GroundMarks.count() == GroundMarks.MAX_MARKS,
		"(%d, cap %d)" % [GroundMarks.count(), GroundMarks.MAX_MARKS])

	## Marks are drawn by one MultiMesh however many there are; that is the
	## whole reason they can be permanent.
	var node := main.get_node_or_null("GroundMarks")
	_check("All marks share one MultiMesh", node is MultiMeshInstance3D)
	if node is MultiMeshInstance3D:
		_check("Instance count is fixed at the cap",
			node.multimesh.instance_count == GroundMarks.MAX_MARKS,
			"(%d)" % node.multimesh.instance_count)

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()
