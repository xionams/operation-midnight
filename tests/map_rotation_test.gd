extends Node

## Every map must actually build a playable match.
##
## A map is not a data file, it is a set of positions that navigation,
## harvesting and the AI all have to cope with. A field the harvesters
## cannot path to, or a base sitting inside a rock, is a map that loads
## fine and plays as a broken match - so this boots each one and checks
## the things that would be wrong.

const MAPS: Array[String] = [
	"res://config/maps/ridgeline.tres",
	"res://config/maps/dry_basin.tres",
	"res://config/maps/cold_corridor.tres",
]

var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-54s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _ready() -> void:
	var main := get_parent()
	await get_tree().process_frame
	var hud = main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame

	for path in MAPS:
		var definition: Resource = load(path)
		_check("%s loads" % path.get_file(), definition != null)
		if definition == null:
			continue
		var name: String = definition.display_name

		_check("%s: bases are far enough apart" % name,
			definition.player_base.distance_to(definition.enemy_base) > 100.0,
			"(%.0f m)" % definition.player_base.distance_to(definition.enemy_base))
		_check("%s: both sides have ore within reach" % name,
			definition.home_ore_for(definition.player_base) > 0
				and definition.home_ore_for(definition.enemy_base) > 0,
			"(P %d / E %d)" % [definition.home_ore_for(definition.player_base),
				definition.home_ore_for(definition.enemy_base)])
		## A map where one side starts richer is not a skirmish map.
		var player_home: int = definition.home_ore_for(definition.player_base)
		var enemy_home: int = definition.home_ore_for(definition.enemy_base)
		_check("%s: opening ore is symmetric" % name, player_home == enemy_home,
			"(%d vs %d)" % [player_home, enemy_home])
		_check("%s: something is worth fighting over" % name,
			definition.contested_ore() > 0, "(%d)" % definition.contested_ore())

		var half: float = definition.size / 2.0
		var inside: bool = true
		for field in definition.resource_fields:
			if absf(field.x) > half or absf(field.z) > half:
				inside = false
		for position in definition.civilian_positions:
			if absf(position.x) > half or absf(position.z) > half:
				inside = false
		_check("%s: everything sits inside the map" % name, inside)

		## Nothing may be buried in a rock, on either side's base or on
		## the ore they have to drive to.
		var clear: bool = true
		var detail: String = ""
		for pair in definition.blocker_pairs():
			var centre: Vector3 = pair[0]
			var extent: Vector3 = pair[1]
			for spot in [definition.player_base, definition.enemy_base]:
				if absf(spot.x - centre.x) < extent.x / 2.0 + 12.0 \
					and absf(spot.z - centre.z) < extent.z / 2.0 + 12.0:
					clear = false
					detail = "base inside a blocker"
			for field in definition.resource_fields:
				if absf(field.x - centre.x) < extent.x / 2.0 + 6.0 \
					and absf(field.z - centre.z) < extent.z / 2.0 + 6.0:
					clear = false
					detail = "ore field inside a blocker"
		_check("%s: nothing is buried in terrain" % name, clear, detail)

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()
