extends Node
class_name VeterancyComponent

## Units that survive fights get better, which is what turns an army from
## a consumable into something worth retreating with. Rank is earned by
## dealing damage, not by landing the final blow, so a tank that softened
## a target and then died to it still banked the work.

signal rank_changed(rank: int)

enum Rank { REGULAR, VETERAN, ELITE }

const VETERAN_XP: float = 100.0
const ELITE_XP: float = 300.0
const REGEN_DELAY: float = 8.0
const REGEN_RATE: float = 0.01

## [health multiplier, damage multiplier, speed multiplier]
const BONUS: Dictionary = {
	Rank.REGULAR: [1.00, 1.00, 1.00],
	Rank.VETERAN: [1.10, 1.10, 1.00],
	Rank.ELITE:   [1.20, 1.20, 1.10],
}

var rank: int = Rank.REGULAR
var experience: float = 0.0

var _unit: UnitBase
var _chevrons: MeshInstance3D
var _since_damage: float = 0.0

func _ready() -> void:
	_unit = get_parent() as UnitBase
	if _unit != null and _unit.health != null:
		_unit.health.health_changed.connect(func(_c, _m): _since_damage = 0.0)
	_build_chevrons()

static func rank_name(value: int) -> String:
	return Rank.keys()[value].capitalize()

func damage_multiplier() -> float:
	return BONUS[rank][1]

func speed_multiplier() -> float:
	return BONUS[rank][2]

## XP is proportional to damage dealt, so contribution is rewarded even
## when something else lands the kill.
func award_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	experience += amount * 0.1
	var earned: int = Rank.REGULAR
	if experience >= ELITE_XP:
		earned = Rank.ELITE
	elif experience >= VETERAN_XP:
		earned = Rank.VETERAN
	if earned != rank:
		_promote(earned)

func _promote(new_rank: int) -> void:
	var previous_fraction: float = _unit.health.health_fraction() if _unit.health else 1.0
	rank = new_rank
	if _unit != null and _unit.health != null and _unit.stats != null:
		## Promotion raises the ceiling and keeps the same proportion of
		## health, so ranking up mid-fight is a real boost but not a heal.
		_unit.health.max_health = _unit.stats.max_health * BONUS[rank][0]
		_unit.health.current_health = _unit.health.max_health * previous_fraction
		_unit.health.health_changed.emit(_unit.health.current_health, _unit.health.max_health)
	_refresh_chevrons()
	rank_changed.emit(rank)

## Elite crews patch their own vehicle up between engagements.
func _process(delta: float) -> void:
	if rank != Rank.ELITE or _unit == null or _unit.health == null:
		return
	_since_damage += delta
	if _since_damage < REGEN_DELAY:
		return
	if _unit.health.current_health >= _unit.health.max_health:
		return
	_unit.health.heal(_unit.health.max_health * REGEN_RATE * delta)

func _build_chevrons() -> void:
	_chevrons = MeshInstance3D.new()
	_chevrons.name = "RankChevrons"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 0.08, 0.12)
	_chevrons.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.85, 0.25)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	_chevrons.material_override = material
	var height: float = _unit.stats.body_size.y if _unit != null and _unit.stats else 1.5
	_chevrons.position = Vector3(0, height + 0.45, 0)
	_chevrons.visible = false
	if _unit != null:
		_unit.add_child(_chevrons)

func _refresh_chevrons() -> void:
	if _chevrons == null:
		return
	_chevrons.visible = rank != Rank.REGULAR
	_chevrons.scale = Vector3(1.0, 1.0, 1.0) if rank == Rank.VETERAN else Vector3(1.4, 1.0, 2.0)
	var material := _chevrons.material_override as StandardMaterial3D
	if material:
		material.albedo_color = Color(0.85, 0.85, 0.9) if rank == Rank.VETERAN else Color(1.0, 0.8, 0.2)
