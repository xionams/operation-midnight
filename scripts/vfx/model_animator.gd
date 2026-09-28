class_name ModelAnimator
extends Node

## Brings a model's named parts to life (docs/ART_DIRECTION.md 18.7):
##   Radar / Spinner  constant spin (stops on a building without power)
##   Crane            slow slew back and forth
##   Gantry           slides along its rails
##   Machinery        turns while its refinery has harvesters about
##   Propeller        turns with the ship's speed
## and makes anything afloat ride the swell.
##
## Attached only when the model has something to move, so a wall or a
## house costs nothing. One small _process per animated entity: no
## AnimationPlayer, no tracks, nothing to keep in sync with the art.

var _host: Node3D
var _visual: Node3D
var _spinners: Array = []
var _crane: Node3D
var _gantry: Node3D
var _gantry_home: Vector3
var _machinery: Node3D
var _propeller: Node3D
var _afloat: bool = false
var _t: float = 0.0
var _last_pos: Vector3
var _wake: CPUParticles3D = null
var _bubbles: CPUParticles3D = null
var _speed: float = 0.0
var _primed: bool = false

static func attach(host: Node3D, visual: Node) -> ModelAnimator:
	if visual == null or not (visual is Node3D):
		return null
	var anim := ModelAnimator.new()
	anim.name = "ModelAnimator"
	anim._host = host
	anim._visual = visual
	for part in ["Radar", "Spinner"]:
		var n := visual.find_child(part, true, false) as Node3D
		if n != null:
			anim._spinners.append(n)
	anim._crane = visual.find_child("Crane", true, false) as Node3D
	anim._gantry = visual.find_child("Gantry", true, false) as Node3D
	anim._machinery = visual.find_child("Machinery", true, false) as Node3D
	anim._propeller = visual.find_child("Propeller", true, false) as Node3D
	anim._afloat = _is_afloat(host)
	if anim._spinners.is_empty() and anim._crane == null and anim._gantry == null \
			and anim._machinery == null and anim._propeller == null and not anim._afloat:
		anim.free()
		return null
	if anim._gantry != null:
		anim._gantry_home = anim._gantry.position
	if anim._afloat and host.get("stats") is UnitStats:
		var size: Vector3 = host.stats.body_size
		anim._wake = VFX.wake(host, Vector3(0, 0.05, size.z * 0.5), size.x)
		if host.stats.submerged_stealth:
			anim._bubbles = VFX.bubbles(host, size.z)
	## Desynchronise identical buildings so a base is not a metronome.
	anim._t = randf() * 20.0
	host.add_child(anim)
	return anim

static func _is_afloat(host: Node) -> bool:
	var stats = host.get("stats")
	if stats == null:
		return false
	if stats is UnitStats:
		return stats.movement_domain == PlacementDomain.Domain.WATER
	if stats is BuildingStats:
		## The yard is a pier on pilings: it does not bob. Buoys do.
		return stats.placement_domain == PlacementDomain.Domain.WATER \
			and stats.body_size.x < 3.0
	return false

func _ready() -> void:
	_last_pos = _host.global_position

func _process(delta: float) -> void:
	if not is_instance_valid(_visual):
		queue_free()
		return
	_t += delta
	var powered: bool = _is_powered()
	if powered:
		for s in _spinners:
			(s as Node3D).rotate_y(delta * 1.6)
	if _crane != null:
		_crane.rotation.y = sin(_t * 0.23) * 0.9
	if _gantry != null:
		_gantry.position = _gantry_home + Vector3(sin(_t * 0.17) * 2.4, 0, 0)
	if _machinery != null and powered:
		_machinery.rotate_x(delta * 2.2)
	var speed: float = 0.0
	if _propeller != null or _afloat:
		var here: Vector3 = _host.global_position
		## Movement happens on physics ticks, so a render frame can see
		## none of it: smooth, or the wake flickers on and off.
		## The first frame only primes the position: the host is placed
		## after it enters the tree, and measuring from where it was
		## created read as a burst of speed (a phantom wake at spawn).
		## Teleports (save restore, spawn) are clamped out the same way.
		var measured: float = 0.0
		if _primed:
			measured = Vector2(here.x - _last_pos.x, here.z - _last_pos.z).length() / maxf(delta, 0.001)
			if measured > 40.0:
				measured = 0.0
		_primed = true
		_last_pos = here
		_speed = lerpf(_speed, measured, clampf(delta * 4.0, 0.0, 1.0))
		speed = _speed
	if _propeller != null:
		_propeller.rotate_z(delta * (1.0 + speed * 3.0))
	var submerged: bool = _bubbles != null and Stealth.is_submerged(_host)
	if _wake != null:
		## A submerged boat leaves no surface wake: that is the point of it.
		_wake.emitting = speed > 0.6 and not submerged
	if _bubbles != null:
		_bubbles.emitting = submerged
	if _afloat:
		## Swell: a slow heave plus pitch and roll, damped under way so a
		## moving ship looks driven rather than adrift.
		var calm: float = 1.0 / (1.0 + speed * 0.4)
		_visual.position.y = sin(_t * 1.3) * 0.07 * calm
		_visual.rotation.x = sin(_t * 0.9 + 0.7) * 0.03 * calm - minf(speed, 6.0) * 0.006
		_visual.rotation.z = sin(_t * 1.1) * 0.035 * calm

func _is_powered() -> bool:
	if not (_host is BuildingBase):
		return true
	var b := _host as BuildingBase
	if b.get("is_neutral") == true:
		return false
	return not GameState.is_low_power(b.is_player_faction)
