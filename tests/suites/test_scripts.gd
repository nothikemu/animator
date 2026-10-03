extends TestCase
## Every script in the project must compile. Catches parse errors in code paths the other
## tests don't reach.


func test_all_scripts_compile() -> void:
	var bad := []
	for path in _scripts("res://src"):
		var s: Script = load(path)
		if s == null or not s.can_instantiate():
			bad.append(path)
	eq(bad, [], "scripts that failed to compile")


func _scripts(dir_path: String) -> Array:
	var out := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_scripts(dir_path.path_join(d)))
	return out
