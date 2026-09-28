class_name DeathThroe
extends Node3D

## What happens to a body after the unit itself is gone.
##
## Units used to vanish on the frame they died - a soldier simply ceased
## to exist, and a ship left nothing at all on the water. That reads as a
## bug even to a player who could not say what was wrong: things that
## were there are suddenly not.
##
## The dying unit still frees itself IMMEDIATELY. Nothing here delays
## selection, targeting, population, or the match-end check; the visual
## is detached from the unit first and animated on its own, so a corpse
## can lie there for a minute without being a unit for even one frame.
## This is the same separation the weapons use: what the game knows and
## what the player sees are allowed to run on different clocks.

## Corpses persist, but not without limit - infantry die in numbers and a
## long match would otherwise carpet the map. Oldest goes first.
const MAX_CORPSES: int = 40
const CORPSE_GROUP: StringName = &"corpses"

const FALL_TIME: float = 0.45
const SINK_TIME: float = 1.8
const COLLAPSE_TIME: float = 0.7

## Detach a dying unit's model so it can outlive the unit. Returns null
## when there is nothing to detach, which is the OM_NO_MODELS case and
## any unit still on a primitive stand-in.
static func take_model(unit: Node) -> Node3D:
	## Units keep their model in _model and buildings in _visual_root;
	## both are the same thing to this code.
	var model: Node3D = unit.get("_model") as Node3D
	if model == null:
		model = unit.get("_visual_root") as Node3D
	if model == null or not is_instance_valid(model) or model.get_parent() != unit:
		return null
	var tree := unit.get_tree()
	if tree == null or tree.current_scene == null:
		return null
	var level := tree.current_scene.get_node_or_null("Level")
	if level == null:
		return null
	var where: Transform3D = model.global_transform
	unit.remove_child(model)
	level.add_child(model)
	model.global_transform = where
	return model

# ----------------------------------------------------------- infantry

## A soldier falls, and stays fallen.
##
## The topple is what makes a death readable at gameplay zoom: infantry
## are a dozen pixels tall, and at that size a body going from upright to
## flat is far more visible than any puff of effect placed where it was.
static func infantry(unit: Node) -> void:
	var model := take_model(unit)
	if model == null:
		return
	_trim(unit.get_tree())
	model.add_to_group(CORPSE_GROUP)
	_darken(model, 0.45)

	## Fall sideways rather than forward: a body pitching onto its face
	## reads as a stumble, one going over on its side reads as dead.
	var tip: float = PI * 0.5 * (1.0 if randf() < 0.5 else -1.0)
	var tween := model.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(model, "rotation:z", model.rotation.z + tip, FALL_TIME)
	## Settle onto the ground rather than through it.
	tween.parallel().tween_property(model, "position:y",
		model.position.y - 0.25, FALL_TIME)

# --------------------------------------------------------------- ships

## A ship goes down by the head, with everything that implies: a column
## of water where it was, bubbles as it goes, and no hulk left behind -
## which is the one honest difference between losing a tank and losing a
## boat.
static func ship(unit: Node, at: Vector3) -> void:
	VFX.water_splash(unit, at, 2.6)
	var model := take_model(unit)
	if model == null:
		return
	VFX.bubbles(model, 2.0)
	var tween := model.create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	## Down, and rolling as she goes.
	tween.tween_property(model, "position:y", model.position.y - 4.0, SINK_TIME)
	tween.parallel().tween_property(model, "rotation:x",
		model.rotation.x + 0.5, SINK_TIME)
	tween.parallel().tween_property(model, "rotation:z",
		model.rotation.z + randf_range(-0.6, 0.6), SINK_TIME)
	tween.tween_callback(model.queue_free)

# ----------------------------------------------------------- buildings

## A structure comes down before the rubble is there. Swapping the model
## for a ruin on one frame is the thing that read as a building
## teleporting into a pile; sinking and squashing it over a beat lets the
## eye see it fall.
static func building(unit: Node) -> void:
	var model := take_model(unit)
	if model == null:
		return
	var tween := model.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(model, "scale:y", model.scale.y * 0.12, COLLAPSE_TIME)
	tween.parallel().tween_property(model, "position:y",
		model.position.y - 0.6, COLLAPSE_TIME)
	## Fade out under the rubble that has already appeared, rather than
	## popping off at the end of the fall.
	tween.parallel().tween_callback(func(): _darken(model, 0.5))
	tween.tween_callback(model.queue_free)

# ------------------------------------------------------------ helpers

## Corpses are the only thing here that persists, so they are the only
## thing that needs a budget.
static func _trim(tree: SceneTree) -> void:
	if tree == null:
		return
	var corpses: Array = tree.get_nodes_in_group(CORPSE_GROUP)
	var excess: int = corpses.size() - (MAX_CORPSES - 1)
	for i in maxi(excess, 0):
		if is_instance_valid(corpses[i]):
			corpses[i].queue_free()

## Dead things stop being the colour they were in life. Applied per
## surface rather than as a shader, because the models arrive with plain
## material overrides and this needs no new pass.
static func _darken(root: Node, amount: float) -> void:
	for child in root.get_children():
		_darken(child, amount)
	if not (root is MeshInstance3D):
		return
	var mesh := root as MeshInstance3D
	for surface in mesh.get_surface_override_material_count():
		var material: Material = mesh.get_surface_override_material(surface)
		if material == null:
			material = mesh.mesh.surface_get_material(surface) if mesh.mesh else null
		if material == null:
			continue
		var copy := material.duplicate() as BaseMaterial3D
		if copy == null:
			continue
		copy.albedo_color = copy.albedo_color.darkened(amount)
		mesh.set_surface_override_material(surface, copy)
