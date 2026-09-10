extends Node

## Full-match AI competence check: can the NORMAL commander actually run
## a war on its own?
##
## The player side is deliberately passive - it builds nothing and gives
## no orders - so anything that happens is the AI's doing. This is the
## honest way to answer "is the AI capable of winning", because a strong
## AI should beat an opponent who does nothing.

const MATCH_LIMIT: float = 900.0

var _main: Node3D
var _director: AIDirector
var _fails: Array = []
var _peak_army: int = 0
var _peak_buildings: int = 0
var _scouted: bool = false
var _attacked: bool = false
var _rebuilt: bool = false

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	_director = _main.get_node("AIDirector")
	_director.difficulty = AIDirector.Difficulty.NORMAL
	print("TEST| AI opening strategy: ", _director.strategy_name())
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-52s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _enemy_buildings() -> Array:
	return get_tree().get_nodes_in_group("enemy_buildings")

func _has(display_name: String) -> bool:
	for b in _enemy_buildings():
		if is_instance_valid(b) and b.stats != null and b.stats.display_name == display_name:
			return true
	return false

func _army() -> int:
	var n: int = 0
	for u in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(u) and u.stats != null and not u.stats.is_harvester:
			n += 1
	return n

func _run() -> void:
	var elapsed: float = 0.0
	var razed_once: bool = false
	var buildings_after_raze: int = 0

	while elapsed < MATCH_LIMIT and GameState.match_state == GameState.MatchState.PLAYING:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

		_peak_army = maxi(_peak_army, _army())
		_peak_buildings = maxi(_peak_buildings, _enemy_buildings().size())
		if not _director.memory.known_resource_fields.is_empty():
			_scouted = true
		if _director._attack_committed:
			_attacked = true

		## Once it is established, raze a structure and see if it rebuilds.
		if not razed_once and elapsed > 240.0 and _has("Power Plant"):
			for b in _enemy_buildings():
				if is_instance_valid(b) and b.stats != null \
					and b.stats.display_name == "Power Plant":
					b.get_node("HealthComponent").take_damage(999999.0)
					break
			razed_once = true
			await get_tree().process_frame
			buildings_after_raze = _enemy_buildings().size()
		elif razed_once and not _rebuilt and _enemy_buildings().size() > buildings_after_raze:
			_rebuilt = true

	print("TEST| match ran %.0fs, ended state=%d" % [elapsed, GameState.match_state])

	_check("AI built an economy", _has("Resource Refinery"))
	_check("AI harvested credits", GameState.enemy_credits >= 0 and _peak_buildings >= 4,
		"(peak %d buildings)" % _peak_buildings)
	_check("AI progressed its tech", _has("Barracks") or _has("Vehicle Factory"))
	_check("AI produced an army", _peak_army >= 6, "(peak %d)" % _peak_army)
	_check("AI scouted and found resources", _scouted)
	_check("AI committed an attack", _attacked)
	_check("AI rebuilt a destroyed structure", _rebuilt)

	var player_units: int = get_tree().get_nodes_in_group("player_units").size()
	var player_buildings: int = get_tree().get_nodes_in_group("player_buildings").size()
	print("TEST| player left with %d units, %d buildings" % [player_units, player_buildings])
	_check("AI pressured a passive player",
		GameState.match_state == GameState.MatchState.DEFEAT
		or player_units < 3 or player_buildings < 1,
		"(state=%d units=%d buildings=%d)" % [GameState.match_state, player_units, player_buildings])
