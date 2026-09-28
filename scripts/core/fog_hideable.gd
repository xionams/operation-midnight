extends Node
class_name FogHideable

## Attached to every enemy-owned entity. When the fog says the player has
## no eyes on this spot, the entity is not merely dimmed - it is removed
## from the player's world: hidden, unclickable and untargetable.
##
## Hiding is driven by the fog's update signal rather than per-frame
## polling, so the cost is one check per enemy entity per fog tick.
##
## Collision is what makes this real. Clearing the layer means selection
## raycasts and target picks cannot find it at all, so there is no way to
## click, target or track something the player should not know about.

## Static things the player has already found stay on screen once their
## cell is explored - a resource field does not walk away while you are
## not looking. Anything that can move hides the moment vision is lost.
@export var persists_once_explored: bool = false

var hidden_by_fog: bool = false

var _entity: CollisionObject3D
var _saved_layer: int = 0
var _visual_root: Node3D

func _ready() -> void:
	_entity = get_parent() as CollisionObject3D
	if _entity == null:
		return
	_saved_layer = _entity.collision_layer
	_connect_fog()
	# Start hidden until proven visible, so nothing flashes on spawn.
	_refresh()

## _ready runs once, but an entity can leave the tree and come back (a
## soldier stepping out of a garrison). The fog subscription is dropped on
## exit, so it has to be picked up again on re-entry or the returning unit
## would never hide in fog again.
func _enter_tree() -> void:
	if _entity == null:
		return
	_connect_fog()
	_refresh()

func _connect_fog() -> void:
	if not FogOfWar.fog_updated.is_connected(_refresh):
		FogOfWar.fog_updated.connect(_refresh)

func _exit_tree() -> void:
	if FogOfWar.fog_updated.is_connected(_refresh):
		FogOfWar.fog_updated.disconnect(_refresh)

func _refresh() -> void:
	if not is_instance_valid(_entity):
		return
	var seen: bool = FogOfWar.is_explored_at(_entity.global_position) if persists_once_explored \
		else FogOfWar.is_visible_at(_entity.global_position)
	## A submerged submarine is hidden even inside vision unless sonar or
	## its own firing has exposed it - the same removal from the player's
	## world as fog, so it cannot be seen, clicked or targeted either.
	seen = seen and Stealth.visible_to(_entity, true)
	if seen == (not hidden_by_fog):
		return
	_set_hidden(not seen)

func _set_hidden(hide_it: bool) -> void:
	hidden_by_fog = hide_it
	_entity.visible = not hide_it
	_entity.collision_layer = 0 if hide_it else _saved_layer
	if hide_it:
		SelectionManager.notify_unit_removed(_entity)

## Anything asking "may the player interact with this?" goes through here
## rather than reading node visibility, which other systems also touch.
static func is_hidden(entity: Node) -> bool:
	if entity == null or not is_instance_valid(entity):
		return true
	var comp: FogHideable = entity.get_node_or_null("FogHideable")
	return comp != null and comp.hidden_by_fog
