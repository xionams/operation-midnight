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
	for i in GroundMarks.cap() + 40:
		VFX.shell_impact(main, centre)
	_check("Mark count is capped by the ring buffer",
		GroundMarks.count() == GroundMarks.cap(),
		"(%d, cap %d)" % [GroundMarks.count(), GroundMarks.cap()])

	## Each layer is one MultiMesh however many marks it holds; that is the
	## whole reason they can be permanent.
	var root := main.get_node_or_null("GroundMarks")
	_check("Ground marks exist as a layered node", root != null)
	if root != null:
		var scorch := root.get_node_or_null(GroundMarks.SCORCH)
		_check("Scorch layer is one MultiMesh", scorch is MultiMeshInstance3D)
		if scorch is MultiMeshInstance3D:
			_check("Scorch instance count is fixed at the cap",
				scorch.multimesh.instance_count == GroundMarks.cap(),
				"(%d)" % scorch.multimesh.instance_count)
		_check("Track layer is its own MultiMesh",
			root.get_node_or_null(GroundMarks.TRACK) is MultiMeshInstance3D)

	## Ruts: laid by driving, and on their own buffer so a harvester's
	## commute cannot erase the record of a battle.
	var before: int = GroundMarks.count(GroundMarks.TRACK)
	for i in 30:
		GroundMarks.track(main, centre + Vector3(i * 1.4, 0, 0),
			Vector3.FORWARD, 3.0, 2.4)
	_check("Driving lays ruts",
		GroundMarks.count(GroundMarks.TRACK) >= before + 30,
		"(%d -> %d)" % [before, GroundMarks.count(GroundMarks.TRACK)])
	_check("Ruts do not consume the scorch buffer",
		GroundMarks.count(GroundMarks.SCORCH) == GroundMarks.cap(),
		"(%d)" % GroundMarks.count(GroundMarks.SCORCH))

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()
