extends Node
class_name OccupantHold

## Units carried inside another entity. The shared core of garrisons
## (infantry in a building) and, later, passenger transports (infantry in
## a vehicle): capacity, who may board, entering, leaving, and what
## happens to the people inside when the host is destroyed or removed.
##
## Occupants are the REAL unit nodes, taken out of the scene tree while
## inside rather than freed and re-created. Out of the tree they are
## automatically absent from every group query - not selectable, not
## targetable, not simulated, invisible to fog - yet they keep their
## health, veterancy and posture, and come back out as the same units.
## (The first garrison stored a {stats, health} snapshot and freed the
## unit, so rank and posture were lost, the building could not say which
## soldiers it held, and nobody could ever leave.)
##
## Subclasses decide the rules that differ between hosts:
##   _accepts_side(unit)   who may board
##   _on_entered / _on_left / _on_emptied   reactions (claiming a
##                         neutral building, mounting a weapon, ...)

signal occupants_changed(count: int)
signal occupant_entered(unit: Node)
signal occupant_left(unit: Node)

## Every hold registers here so side-wide questions (population in use)
## can include people who are currently inside something.
const GROUP: String = "occupant_holds"

@export var capacity: int = 0
@export var infantry_only: bool = true
## How close to the host's footprint edge a unit must get to board.
@export var entry_distance: float = 2.5
## Share of max health each occupant loses when the host is destroyed.
## Anyone who cannot absorb it dies in the collapse.
@export var destruction_damage: float = 0.4

## UnitBase nodes currently inside. Held, not freed.
var occupants: Array = []

var _host: Node3D
## Where each occupant lived in the tree before boarding, so it goes back
## to the same parent (the Level) rather than wherever the host lives.
var _return_parents: Dictionary = {}

func _ready() -> void:
	_host = get_parent() as Node3D
	add_to_group(GROUP)

func host() -> Node3D:
	return _host

func occupancy() -> int:
	return occupants.size()

func has_room() -> bool:
	return occupants.size() < capacity

func free_slots() -> int:
	return maxi(capacity - occupants.size(), 0)

func contains(unit: Node) -> bool:
	return occupants.has(unit)

func can_accept(unit: Node) -> bool:
	if _host == null or not is_instance_valid(unit) or not (unit is UnitBase):
		return false
	var u := unit as UnitBase
	if occupants.has(u) or not has_room() or u.stats == null:
		return false
	if infantry_only and not u.stats.is_infantry:
		return false
	if u.health != null and u.health.is_dead():
		return false
	return _accepts_side(u)

func in_entry_range(unit: Node3D) -> bool:
	return _host != null \
		and CombatTarget.distance(unit.global_position, _host) <= entry_distance

## Take the unit inside. Returns false (and leaves it untouched) when it
## may not board - wrong side, no room, not infantry, already dead.
func enter(unit: Node) -> bool:
	if not can_accept(unit):
		return false
	var u := unit as UnitBase
	_on_entering(u)
	SelectionManager.notify_unit_removed(u)
	var attacker: AttackerComponent = u.get_node_or_null("AttackerComponent")
	if attacker != null:
		attacker.clear_target()
	u.stop_moving()
	u.garrison_target = null
	var parent := u.get_parent()
	_return_parents[u] = parent
	if parent != null:
		parent.remove_child(u)
	occupants.append(u)
	_on_entered(u)
	occupant_entered.emit(u)
	occupants_changed.emit(occupants.size())
	return true

## Put one occupant back into the world beside the host. Returns false if
## it was not inside.
func exit(unit: Node) -> bool:
	var index: int = occupants.find(unit)
	if index < 0:
		return false
	occupants.remove_at(index)
	_place_outside(unit as UnitBase, index)
	_on_left(unit as UnitBase)
	occupant_left.emit(unit)
	occupants_changed.emit(occupants.size())
	if occupants.is_empty():
		_on_emptied()
	return true

## Everyone out. Returns the units that left.
func exit_all() -> Array:
	var leaving: Array = occupants.duplicate()
	for unit in leaving:
		exit(unit)
	return leaving

## The host has been destroyed: everyone is thrown out and hurt. Uses the
## normal damage path, so anyone killed dies properly - death effects,
## stats, selection cleanup - rather than silently vanishing.
func eject_on_destruction() -> Array:
	var survivors: Array = []
	for unit in exit_all():
		if not is_instance_valid(unit):
			continue
		var health: HealthComponent = unit.get_node_or_null("HealthComponent")
		if health != null and destruction_damage > 0.0:
			health.take_damage(health.max_health * destruction_damage, null)
		if health == null or not health.is_dead():
			survivors.append(unit)
	return survivors

## Units taken out of the tree are not freed with their host. If the host
## goes away without releasing them (scene change, quit), free them here
## so nothing is leaked and nothing is left pointing at a dead host.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for unit in occupants:
			if is_instance_valid(unit) and not unit.is_inside_tree():
				unit.free()
		occupants.clear()

## Spread leavers around the host's edge so they do not stack on one
## spot, and snap each to the navmesh so it can path from there.
func _place_outside(unit: UnitBase, slot: int) -> void:
	if not is_instance_valid(unit):
		return
	var parent: Node = _return_parents.get(unit, null)
	_return_parents.erase(unit)
	if not is_instance_valid(parent):
		parent = _host.get_parent() if _host != null else null
	if parent == null:
		unit.queue_free()
		return
	var centre: Vector3 = _host.global_position if _host != null else Vector3.ZERO
	var half: Vector2 = CombatTarget.half_extents(_host) if _host != null else Vector2.ZERO
	var reach: float = maxf(half.x, half.y) + 2.0
	var angle: float = PI * 0.5 + float(slot) * TAU / 8.0
	var spot: Vector3 = centre + Vector3(cos(angle), 0.0, sin(angle)) * reach
	if _host != null and _host.is_inside_tree():
		var map_rid: RID = _host.get_world_3d().navigation_map
		if map_rid.is_valid() and NavigationServer3D.map_get_iteration_id(map_rid) > 0:
			var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, spot)
			if snapped != Vector3.ZERO:
				spot = snapped
	spot.y = Terrain.height_at(spot.x, spot.z)
	parent.add_child(unit)
	unit.global_position = spot
	unit.issue_command(CommandTypes.Type.STOP)

## Occupants still belong to their side: they cost population while
## inside, or garrisoning would be a way round the unit cap.
static func population_inside(tree: SceneTree, is_player: bool) -> int:
	var used: int = 0
	for hold in tree.get_nodes_in_group(GROUP):
		for unit in hold.occupants:
			if is_instance_valid(unit) and unit.stats != null \
				and unit.is_player_faction == is_player:
				used += unit.stats.population
	return used

## Which hold, if any, currently has this unit inside.
static func holding(tree: SceneTree, unit: Node) -> OccupantHold:
	for hold in tree.get_nodes_in_group(GROUP):
		if hold.occupants.has(unit):
			return hold
	return null

# ------------------------------------------------------ subclass hooks

func _accepts_side(_unit: UnitBase) -> bool:
	return true

func _on_entering(_unit: UnitBase) -> void:
	pass

func _on_entered(_unit: UnitBase) -> void:
	pass

func _on_left(_unit: UnitBase) -> void:
	pass

func _on_emptied() -> void:
	pass
