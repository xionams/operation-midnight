extends Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var dir := DirAccess.open("res://assets/icons")
	var names: Array = []
	for file in dir.get_files():
		if file.ends_with(".svg"):
			names.append(file)
	names.sort()

	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.position = Vector2(20, 20)
	add_child(grid)

	for name in names:
		var cell := VBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = load("res://assets/icons/" + name)
		icon.custom_minimum_size = Vector2(76, 76)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(icon)
		var label := Label.new()
		label.text = name.get_basename()
		label.add_theme_font_size_override("font_size", 10)
		label.custom_minimum_size = Vector2(76, 14)
		cell.add_child(label)
		grid.add_child(cell)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("res://screenshots/icon_sheet.png")
	print("ICONS| %d rendered" % names.size())
	get_tree().quit()
