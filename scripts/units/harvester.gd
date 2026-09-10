extends UnitBase
class_name Harvester

## Supply Harvester: finds a resource node, drives to it, loads over
## load_time, drives to the nearest refinery, unloads over
## unload_time, delivers credits, and repeats. Credits only enter the
## economy through this physical round trip — never passively — which
## is why harvesters are a valid, vulnerable attack target.

enum State { IDLE, TO_NODE, LOADING, TO_REFINERY, UNLOADING }

var state: State = State.IDLE
var cargo: float = 0.0
var assigned_node = null

var _refinery = null
var _timer: float = 0.0

const ARRIVE_NODE_DISTANCE: float = 4.5
const ARRIVE_REFINERY_DISTANCE: float = 4.5

## The harvester answers the same command vocabulary as everything else;
## HARVEST and RETURN simply mean something to it that they do not mean
## to a tank, which is why the resolver can stay unit-agnostic.
func _handle_command(type: int, position: Vector3, target: Node) -> void:
	match type:
		CommandTypes.Type.HARVEST:
			assigned_node = target
			state = State.IDLE
			_tick_idle()
		CommandTypes.Type.RETURN:
			_refinery = target if target != null else GameState.get_nearest_refinery(global_position, is_player_faction)
			if _refinery:
				move_to(_refinery.global_position)
				state = State.TO_REFINERY
		CommandTypes.Type.STOP:
			state = State.IDLE
			stop_moving()
		_:
			## A manual move order takes the harvester off its route until
			## it is idle again, so the player can always pull it out.
			state = State.IDLE
			super._handle_command(type, position, target)

func _process(delta: float) -> void:
	match state:
		State.IDLE:
			_tick_idle()
		State.TO_NODE:
			_tick_to_node()
		State.LOADING:
			_tick_loading(delta)
		State.TO_REFINERY:
			_tick_to_refinery()
		State.UNLOADING:
			_tick_unloading(delta)

func _tick_idle() -> void:
	if cargo > 0.0:
		_refinery = GameState.get_nearest_refinery(global_position, is_player_faction)
		if _refinery:
			move_to(_refinery.global_position)
			state = State.TO_REFINERY
		return

	if assigned_node == null or not is_instance_valid(assigned_node) or assigned_node.remaining <= 0.0:
		assigned_node = _find_resource_node()
	if assigned_node:
		move_to(assigned_node.global_position)
		state = State.TO_NODE

func _tick_to_node() -> void:
	if not is_instance_valid(assigned_node) or assigned_node.remaining <= 0.0:
		state = State.IDLE
		return
	if nav_agent.is_navigation_finished() or global_position.distance_to(assigned_node.global_position) < ARRIVE_NODE_DISTANCE:
		state = State.LOADING
		_timer = stats.load_time if stats else 6.0

func _tick_loading(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	if is_instance_valid(assigned_node):
		var capacity: float = stats.cargo_capacity if stats else 700.0
		cargo = assigned_node.call("harvest", capacity)
	state = State.IDLE

func _tick_to_refinery() -> void:
	if not is_instance_valid(_refinery):
		state = State.IDLE
		return
	if nav_agent.is_navigation_finished() or global_position.distance_to(_refinery.global_position) < ARRIVE_REFINERY_DISTANCE:
		state = State.UNLOADING
		_timer = stats.unload_time if stats else 3.0

func _tick_unloading(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	if is_instance_valid(_refinery):
		_refinery.call("receive_resources", cargo)
	cargo = 0.0
	state = State.IDLE

func _find_resource_node() -> Node:
	var nearest: Node = null
	var nearest_dist: float = INF
	var candidates: Array = get_tree().get_nodes_in_group("resource_nodes")
	for node in candidates:
		if not is_instance_valid(node) or node.remaining <= 0.0:
			continue
		var dist: float = global_position.distance_squared_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	return nearest
