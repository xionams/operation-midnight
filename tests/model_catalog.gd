extends RefCounted

## Every shipped glb under assets/models, category folders included
## (units/, buildings/, naval/, civilian/). "_experiment" is scratch.

static func all_paths(root: String = "res://assets/models") -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".glb"):
			out.append(root.path_join(file))
	for sub in dir.get_directories():
		if sub.begins_with("_"):
			continue
		out.append_array(all_paths(root.path_join(sub)))
	out.sort()
	return out
