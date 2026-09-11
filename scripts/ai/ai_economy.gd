extends Node
class_name AIEconomy

## Economic instrumentation and policy for one side.
##
## Split out of AIDirector deliberately: the previous milestone's
## bottleneck was economic, and it took a full-match log to find that -
## guessing produced two wrong fixes first. Everything the commander
## decides about money is computed here from measured state, and the same
## numbers are what the debug HUD and the test harnesses read, so there
## is one account of the economy rather than three.
##
## Nothing here grants income. It observes and advises; the director
## spends.

const SAMPLE_WINDOW: float = 30.0

## Spending priority. Anything at or above CRITICAL may dip into the
## treasury reserve, because the alternative is an economy that cannot
## recover at all.
enum Priority { LUXURY, ARMY, TECH, DEFENCE, ECONOMY, CRITICAL }

@export var is_player: bool = false
@export var reserve_target: int = 1500

var income_per_minute: float = 0.0
var spend_per_minute: float = 0.0

var _last_credits: int = 0
var _window_income: int = 0
var _window_spend: int = 0
var _window_elapsed: float = 0.0
var _round_trips: Array[float] = []

func _ready() -> void:
	_last_credits = GameState.balance_of(is_player)

## Income and spend are inferred from balance deltas rather than hooked
## into every transaction: it costs nothing, cannot drift out of sync
## with reality, and counts money the AI never sees coming.
func _process(delta: float) -> void:
	var now: int = GameState.balance_of(is_player)
	var change: int = now - _last_credits
	if change > 0:
		_window_income += change
	elif change < 0:
		_window_spend += -change
	_last_credits = now

	_window_elapsed += delta
	if _window_elapsed < SAMPLE_WINDOW:
		return
	var scale: float = 60.0 / _window_elapsed
	income_per_minute = float(_window_income) * scale
	spend_per_minute = float(_window_spend) * scale
	_window_income = 0
	_window_spend = 0
	_window_elapsed = 0.0

# --------------------------------------------------------------- state

func _group(kind: String) -> String:
	return ("player_" if is_player else "enemy_") + kind

func refineries() -> Array:
	var list: Array = []
	for building in get_tree().get_nodes_in_group(_group("buildings")):
		if is_instance_valid(building) and building is Refinery:
			list.append(building)
	return list

func harvesters() -> Array:
	var list: Array = []
	for unit in get_tree().get_nodes_in_group(_group("units")):
		if is_instance_valid(unit) and unit.stats != null and unit.stats.is_harvester:
			list.append(unit)
	return list

## A harvester counts as working unless it has run out of anywhere to go.
func active_harvesters() -> int:
	var count: int = 0
	for harvester in harvesters():
		if not harvester.get("no_resources"):
			count += 1
	return count

func idle_harvesters() -> int:
	return harvesters().size() - active_harvesters()

func resource_remaining() -> float:
	var total: float = 0.0
	for field in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(field):
			total += field.remaining
	return total

## Fields with something left that this side could actually reach.
func reachable_fields() -> Array:
	var list: Array = []
	for field in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(field) and field.remaining > 500.0:
			list.append(field)
	return list

# ---------------------------------------------------------- army value

## Army strength measured in credits and in what the units are FOR.
## Twenty rifle squads are not four tanks, and counting heads said they
## were.
func army_value() -> Dictionary:
	var total: int = 0
	var anti_infantry: int = 0
	var anti_armor: int = 0
	var siege: int = 0

	for unit in get_tree().get_nodes_in_group(_group("units")):
		if not is_instance_valid(unit) or unit.stats == null:
			continue
		if unit.stats.is_harvester:
			continue
		var weapon: WeaponStats = unit.stats.weapon_stats
		if weapon == null:
			continue
		var cost: int = unit.stats.cost
		total += cost
		if weapon.multiplier_for(Armor.Type.INFANTRY) >= 0.8:
			anti_infantry += cost
		if weapon.multiplier_for(Armor.Type.HEAVY) >= 0.8:
			anti_armor += cost
		if weapon.multiplier_for(Armor.Type.STRUCTURE) >= 0.5:
			siege += cost

	return {
		"total": total,
		"anti_infantry": anti_infantry,
		"anti_armor": anti_armor,
		"siege": siege,
		"siege_share": float(siege) / maxf(float(total), 1.0),
	}

func building_value() -> int:
	var total: int = 0
	for building in get_tree().get_nodes_in_group(_group("buildings")):
		if is_instance_valid(building) and building.stats != null:
			total += building.stats.cost
	return total

func queued_value() -> int:
	var total: int = 0
	for building in get_tree().get_nodes_in_group(_group("buildings")):
		if not is_instance_valid(building):
			continue
		var queue = building.get("queue")
		if queue == null:
			continue
		for stats in queue.orders():
			total += stats.cost
	return total

# ------------------------------------------------------------- routes

func record_round_trip(seconds: float) -> void:
	_round_trips.append(seconds)
	if _round_trips.size() > 12:
		_round_trips.pop_front()

func average_round_trip() -> float:
	if _round_trips.is_empty():
		return 0.0
	var total: float = 0.0
	for value in _round_trips:
		total += value
	return total / float(_round_trips.size())

## Credits per minute one harvester actually returns on the current
## route. Long routes are why an extra harvester can be worth more than
## an extra tank.
func credits_per_harvester_minute() -> float:
	var trip: float = average_round_trip()
	if trip <= 0.0:
		return 0.0
	return 700.0 * (60.0 / trip)

# ------------------------------------------------------------- policy

## How many harvesters the refineries can usefully keep busy. Long routes
## justify a fourth per refinery; short ones do not.
func target_harvesters() -> int:
	var count: int = refineries().size()
	if count == 0:
		return 0
	var per_refinery: int = 3
	if average_round_trip() > 45.0:
		per_refinery = 4
	return clampi(count * per_refinery, 3, 8)

func needs_harvester() -> bool:
	return refineries().size() > 0 and harvesters().size() < target_harvesters()

## The treasury floor. It is deliberately abandoned when the economy is
## broken: reserving money while unable to harvest is how an AI turns a
## bad raid into a permanent death.
func effective_reserve() -> int:
	if refineries().is_empty() or active_harvesters() == 0:
		return 0
	return reserve_target

## Whether a purchase at this priority is allowed right now.
func can_afford(cost: int, priority: Priority) -> bool:
	var balance: int = GameState.balance_of(is_player)
	if cost > balance:
		return false
	if priority >= Priority.CRITICAL:
		return true
	if priority >= Priority.ECONOMY:
		## Economic investment may spend down to half the reserve: it is
		## what restores income in the first place.
		return balance - cost >= effective_reserve() / 2
	return balance - cost >= effective_reserve()

## True when the economy can replace what an offensive will cost.
func can_sustain_offensive() -> bool:
	if active_harvesters() < 3:
		return false
	if refineries().size() < 2 and income_per_minute < 3000.0:
		return false
	return GameState.balance_of(is_player) >= effective_reserve() / 2

func snapshot() -> Dictionary:
	var army := army_value()
	return {
		"credits": GameState.balance_of(is_player),
		"income_per_min": int(income_per_minute),
		"spend_per_min": int(spend_per_minute),
		"refineries": refineries().size(),
		"harvesters": harvesters().size(),
		"active_harvesters": active_harvesters(),
		"target_harvesters": target_harvesters(),
		"round_trip": average_round_trip(),
		"army_value": army["total"],
		"siege_value": army["siege"],
		"siege_share": army["siege_share"],
		"queued_value": queued_value(),
		"building_value": building_value(),
		"resource_remaining": int(resource_remaining()),
		"reserve": effective_reserve(),
	}

func format_line(t: float) -> String:
	var s := snapshot()
	return ("ECON| t=%4.0f cr=%5d in/min=%5d out/min=%5d ref=%d harv=%d/%d(%d) trip=%4.1fs "
		+ "army=%5d siege=%4d(%.0f%%) queued=%4d bldg=%5d ore=%6d") % [
		t, s["credits"], s["income_per_min"], s["spend_per_min"],
		s["refineries"], s["active_harvesters"], s["harvesters"], s["target_harvesters"],
		s["round_trip"], s["army_value"], s["siege_value"], s["siege_share"] * 100.0,
		s["queued_value"], s["building_value"], s["resource_remaining"]]
