extends Node

## A real cold launch, with nothing bypassed.
##
## Every other harness calls hud._begin_match() to skip the skirmish
## setup screen, which is exactly how a bug that made the game
## unstartable survived: the intro overlay was drawn on top of the setup
## screen while the tree was paused, so its fade never ran and the START
## button was unreachable. This test presses START the way a player does.

var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-50s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null

func _ready() -> void:
	var main := get_parent()
	await get_tree().process_frame
	await get_tree().process_frame
	var hud = main.get_node_or_null("HUD")
	_check("HUD exists", hud != null)

	_check("A cold launch pauses for the setup screen", get_tree().paused)
	var start := _find_button(hud, "START OPERATION")
	_check("START OPERATION button exists", start != null)

	## The whole bug: something covering the button the player must press.
	if start != null:
		var blocked: bool = hud._intro_overlay != null and hud._intro_overlay.visible
		_check("Nothing is covering the setup screen", not blocked)
		start.pressed.emit()
		await get_tree().process_frame
		_check("Pressing START unpauses the match", not get_tree().paused)

	var elapsed: float = 0.0
	while elapsed < 6.0:
		elapsed += get_process_delta_time()
		await get_tree().process_frame
	_check("The intro clears itself once the match runs",
		hud._intro_overlay == null or not hud._intro_overlay.visible)
	_check("The battlefield is live", get_tree().get_nodes_in_group("player_buildings").size() >= 1)

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()
