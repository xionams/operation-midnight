extends Node3D
class_name HealthBar

## A bar that appears only when it is telling the player something: while
## the entity is selected, or for a few seconds after it takes damage.
## Permanently-on bars turn a busy battlefield into noise, and most units
## are at full health most of the time.

const SHOW_AFTER_DAMAGE: float = 4.0
const WIDTH: float = 1.8
const HEIGHT: float = 0.22

const PIPS: Texture2D = preload("res://assets/textures/pips.png")

## How many segments a bar is divided into, by how much health it has.
##
## A solid bar is read by judging a length; a segmented one is read by
## counting, which is faster and more precise. Tying the count to health
## means the pips also carry a second signal for free: a unit with twice
## as many segments is visibly twice as tough, without the bar getting
## any longer.
const PIP_TIERS: Array = [
	[150.0, 3], [350.0, 5], [700.0, 7], [1200.0, 9],
]
const PIP_MAX: int = 12

var _health: HealthComponent
var _fill: MeshInstance3D
var _fill_material: StandardMaterial3D
var _background: MeshInstance3D
var _fill_width: float = WIDTH
var _visible_timer: float = 0.0
var _selected: bool = false

static func attach(entity: Node3D, health: HealthComponent, height: float, width: float) -> HealthBar:
	var bar := HealthBar.new()
	bar.name = "HealthBar"
	bar._health = health
	entity.add_child(bar)
	bar.position = Vector3(0, height + 0.7, 0)
	bar._build(width)
	return bar

func _build(width: float) -> void:
	_background = _make_quad(Color(0.05, 0.05, 0.05, 0.85), width, HEIGHT)
	add_child(_background)

	_fill_width = width * 0.96
	_fill = _make_quad(Color(0.25, 0.9, 0.35), _fill_width, HEIGHT * 0.66)
	_fill_material = _fill.material_override
	_fill.position = Vector3(0, 0, 0.01)
	add_child(_fill)

	## Dividers sit OVER the whole bar, not over the fill, so the empty
	## part stays segmented too - that is what lets a player see how much
	## is missing rather than only how much is left. One quad and one
	## shared texture whatever the segment count.
	var pips := _make_quad(Color(1, 1, 1), _fill_width, HEIGHT * 0.66)
	var pip_material: StandardMaterial3D = pips.material_override
	pip_material.albedo_texture = PIPS
	pip_material.uv1_scale = Vector3(_segments(), 1.0, 1.0)
	pip_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pips.position = Vector3(0, 0, 0.02)
	add_child(pips)

	visible = false
	if _health != null:
		_health.health_changed.connect(_on_health_changed)

func _segments() -> int:
	var maximum: float = _health.max_health if _health != null else 100.0
	for tier in PIP_TIERS:
		if maximum <= tier[0]:
			return tier[1]
	return PIP_MAX

func _make_quad(color: Color, width: float, height: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	instance.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	## Always faces the camera and is never buried in the model it sits on.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	instance.material_override = material
	return instance

func set_selected(selected: bool) -> void:
	_selected = selected
	_refresh_visibility()

func _on_health_changed(current: float, maximum: float) -> void:
	_visible_timer = SHOW_AFTER_DAMAGE
	var fraction: float = clampf(current / maxf(maximum, 0.001), 0.0, 1.0)
	## Scale from the left edge so the bar drains rather than shrinking
	## toward its middle.
	_fill.scale.x = maxf(fraction, 0.001)
	_fill.position.x = -(1.0 - fraction) * _fill_width * 0.5
	_fill_material.albedo_color = _color_for(fraction)
	_refresh_visibility()

func _color_for(fraction: float) -> Color:
	if fraction > 0.6:
		return Color(0.25, 0.9, 0.35)
	if fraction > 0.3:
		return Color(0.95, 0.8, 0.2)
	return Color(0.95, 0.25, 0.2)

func _process(delta: float) -> void:
	if _visible_timer <= 0.0:
		return
	_visible_timer -= delta
	if _visible_timer <= 0.0:
		_refresh_visibility()

func _refresh_visibility() -> void:
	visible = _selected or _visible_timer > 0.0
