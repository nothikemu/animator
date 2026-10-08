extends TestCase
## References that would otherwise fail silently: a schedule point that doesn't exist sends an
## NPC to the commons; an icon that doesn't exist shows a warning sign.


func test_schedule_points_exist() -> void:
	for id: String in Content.npcs:
		var def: Dictionary = Content.npc(id)
		var pts: Dictionary = Npc.points_for(id)
		var home := String(def.get("home", ""))
		check(pts.has(home), "%s's home '%s' is a point on the map" % [id, home])
		for b: Dictionary in def.get("schedule", []):
			var at := String(b.get("at", ""))
			check(at in ["home", "away"] or pts.has(at), "%s goes to '%s', which exists" % [id, at])


func test_item_icons_exist() -> void:
	var meta: Variant = Content.read_json("res://assets/textures/icons.json")
	check(meta is Dictionary, "icon manifest")
	var icons: Dictionary = meta.icons
	for id: String in Content.items:
		var icon := String(Content.item(id).get("icon", id))
		check(icons.has(icon) or icons.has(id), "item %s has an icon (%s)" % [id, icon])


func test_machine_sprites_exist() -> void:
	var meta: Variant = Content.read_json("res://assets/textures/machines/machines.json")
	for id: String in Content.machines:
		check((meta as Dictionary).has(id), "machine %s has a sprite strip" % id)


## Godot's JSON parser keeps the last of two equal keys without a word, which once dropped a
## story flag (two "on_enter" lists on one thread stage). Scan every data file for repeats.
func test_no_duplicate_keys_in_data() -> void:
	for path in _json_files("res://data"):
		var dupes := _duplicate_keys(FileAccess.get_file_as_string(path))
		check(dupes.is_empty(), "%s repeats keys: %s" % [path, ", ".join(dupes)])


func _json_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_json_files(dir_path.path_join(d)))
	return out


## Walks the text once: a stack of objects (each a set of the keys seen) and arrays; a string
## directly inside an object and followed by ':' is a key.
static func _duplicate_keys(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array = []        # Dictionary (object keys) or null (array)
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if c == "{":
			stack.append({})
		elif c == "[":
			stack.append(null)
		elif c == "}" or c == "]":
			stack.pop_back()
		elif c == "\"":
			var j := i + 1
			while j < n and text[j] != "\"":
				j += 2 if text[j] == "\\" else 1
			var s := text.substr(i + 1, j - i - 1)
			var k := j + 1
			while k < n and text[k] in [" ", "\t", "\n", "\r"]:
				k += 1
			if k < n and text[k] == ":" and not stack.is_empty() and stack.back() is Dictionary:
				var keys: Dictionary = stack.back()
				if keys.has(s):
					out.append(s)
				keys[s] = true
			i = j
		i += 1
	return out
