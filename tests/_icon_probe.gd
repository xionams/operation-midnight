extends SceneTree
func _init():
	var d := DirAccess.open("res://assets/icons")
	var bad := 0
	var n := 0
	for f in d.get_files():
		if not f.ends_with(".svg"): continue
		n += 1
		var tex = load("res://assets/icons/" + f)
		if tex == null or tex.get_width() == 0:
			print("ICON| FAIL ", f); bad += 1
	print("ICON| %d icons, %d failed" % [n, bad])
	quit(1 if bad > 0 else 0)
