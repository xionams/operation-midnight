extends Node

## Ends a match both ways and checks the ending is usable.
##
## A win screen is the last thing a player sees, and the easiest thing to
## leave half-built: numbers that do not add up, a button that does
## nothing, or a battle still going on behind the report. This drives a
## real ending rather than calling the overlay directly.

var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-52s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null

func _hq(group: String) -> Node:
	for b in get_tree().get_nodes_in_group(group):
		if is_instance_valid(b) and b.stats != null \
			and b.stats.display_name == "Command Headquarters":
			return b
	return null

func _ready() -> void:
	var scene := get_parent()
	await get_tree().process_frame
	var hud = scene.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	get_tree().paused = false
	await get_tree().process_frame

	## Give the match enough substance that the report has something to
	## say, then win it by destroying the enemy HQ.
	var elapsed: float = 0.0
	while elapsed < 45.0:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

	## Both endings run the same flow; pass 1 to lose instead of win.
	var lose: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg == "1":
			lose = true
	var target := _hq("player_buildings" if lose else "enemy_buildings")
	_check("There is an HQ to destroy", target != null)
	if target == null:
		return _finish()
	target.get_node("HealthComponent").take_damage(999999.0)
	await get_tree().process_frame
	await get_tree().process_frame

	var expected = GameState.MatchState.DEFEAT if lose else GameState.MatchState.VICTORY
	_check("Destroying the %s HQ ends the match" % ("player" if lose else "enemy"),
		GameState.match_state == expected, "(state %d)" % GameState.match_state)
	_check("The result overlay is shown", hud._victory_overlay.visible)
	_check("It says the right result",
		hud._victory_label.text == ("DEFEAT" if lose else "VICTORY"),
		"(%s)" % hud._victory_label.text)
	_check("It says how long the match took",
		hud._subtitle_label.text.contains(MatchStats.formatted_time()),
		"(%s)" % hud._subtitle_label.text)

	## Nothing should still be fighting while the player reads the report.
	_check("The battlefield is paused behind the report", get_tree().paused)

	## The report has to be readable and add up.
	var report: String = hud._report_label.text
	_check("The report is populated", report.length() > 40)
	for heading in ["MATCH TIME", "FORCES", "ENEMY LOSSES", "EXCHANGE", "HARVESTED"]:
		_check("Report includes %s" % heading, report.contains(heading))
	_check("Exchange ratio is expressed, not blank",
		not MatchStats.exchange_ratio().is_empty(), "(%s)" % MatchStats.exchange_ratio())
	_check("Average income is derived",
		MatchStats.income_per_minute() >= 0,
		"(%d/min over %s)" % [MatchStats.income_per_minute(), MatchStats.formatted_time()])

	## Both ways out must exist and be reachable under pause.
	var again := _find_button(hud, "PLAY AGAIN")
	var change := _find_button(hud, "NEW SKIRMISH")
	_check("PLAY AGAIN exists", again != null)
	_check("NEW SKIRMISH exists", change != null)
	_check("The overlay still processes while paused",
		hud._victory_overlay.process_mode == Node.PROCESS_MODE_ALWAYS)

	## A finished match must not leave a save behind offering a resume
	## into a game that is already over.
	_check("The save is cleared when the match ends", not SaveGame.has_save())

	_finish()

func _finish() -> void:
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()
