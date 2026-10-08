extends Node
## Content database. Loads every JSON file under res://data, validates references and
## exposes lookups. Gameplay code asks Content for definitions and never hardcodes them.

const DATA_DIR := "res://data"

var items: Dictionary = {}
var crops: Dictionary = {}
var machines: Dictionary = {}
var recipes: Dictionary = {}
var npcs: Dictionary = {}
var dialogue: Dictionary = {}      ## npc_id -> {lines: [], convos: {}}
var maps: Dictionary = {}          ## authored areas below Wick (Sallow, the Heart, the Ways)
var threads: Dictionary = {}
var events: Dictionary = {}
var biomes: Dictionary = {}
var lore: Dictionary = {}
var wick_map: Dictionary = {}
var undercroft: Dictionary = {}
var palette: Dictionary = {}
var markets: Dictionary = {}
var requests: Dictionary = {}     ## notice-board request templates
var origins: Dictionary = {}      ## who the salvager was before the fall

var errors: PackedStringArray = []
var loaded := false


func _ready() -> void:
	load_all()


func load_all() -> void:
	errors.clear()
	items = _load_dict("items.json")
	crops = _load_dict("crops.json")
	machines = _load_dict("machines.json")
	recipes = _load_dict("recipes.json")
	threads = _load_dict("threads.json")
	events = _load_dict("events.json")
	biomes = _load_dict("biomes.json")
	lore = _load_dict("lore.json")
	wick_map = _load_dict("wick_map.json")
	undercroft = _load_dict("undercroft_wick.json")
	palette = _load_dict("palette.json")
	markets = _load_dict("markets.json")
	requests = _load_dict("requests.json")
	origins = _load_dict("origins.json")
	origins.erase("_comment")
	npcs = _load_dir("npcs")
	dialogue = _merge_parts(_load_dir("dialogue"))
	maps = _load_dir("maps")
	validate()
	loaded = true
	if errors.is_empty():
		Log.info("content", "loaded %d items, %d crops, %d machines, %d recipes, %d npcs" % [
			items.size(), crops.size(), machines.size(), recipes.size(), npcs.size()])
	else:
		for e in errors:
			Log.error("content", e)


# --- Lookups -------------------------------------------------------------------

func item(id: StringName) -> Dictionary:
	return items.get(String(id), {})


func item_name(id: StringName) -> String:
	return String(item(id).get("name", String(id)))


func crop(id: StringName) -> Dictionary:
	return crops.get(String(id), {})


func machine(id: StringName) -> Dictionary:
	return machines.get(String(id), {})


func npc(id: StringName) -> Dictionary:
	return npcs.get(String(id), {})


func color(name: String, fallback := Color.MAGENTA) -> Color:
	var hex: String = palette.get(name, "")
	if hex.is_empty():
		return fallback
	return Color.html(hex)


func recipes_for_station(station: String) -> Array:
	var out: Array = []
	for id in recipes:
		var r: Dictionary = recipes[id]
		if String(r.get("station", "bench")) == station:
			out.append(id)
	return out


# --- Loading -----------------------------------------------------------------

static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON parse error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _load_dict(file: String) -> Dictionary:
	var path := DATA_DIR.path_join(file)
	if not FileAccess.file_exists(path):
		errors.append("missing data file %s" % path)
		return {}
	var data: Variant = read_json(path)
	if data == null:
		errors.append("could not parse %s" % path)
		return {}
	if not data is Dictionary:
		errors.append("%s must contain a JSON object" % path)
		return {}
	var d: Dictionary = data
	d.erase("_comment")
	return d


## Dialogue for one speaker may be split across files: "barnaby@deep.json" adds its lines and
## conversations to "barnaby". Keeps each chapter's writing in its own file.
func _merge_parts(d: Dictionary) -> Dictionary:
	var out := {}
	var keys := d.keys()
	keys.sort()
	for k: String in keys:
		var base := k.get_slice("@", 0)
		if not out.has(base):
			out[base] = {"lines": [], "convos": {}}
		var part: Dictionary = d[k]
		(out[base].lines as Array).append_array(part.get("lines", []))
		var convos: Dictionary = part.get("convos", {})
		for c: String in convos:
			if out[base].convos.has(c):
				errors.append("dialogue %s: conversation '%s' defined twice" % [base, c])
			out[base].convos[c] = convos[c]
	return out


func _load_dir(sub: String) -> Dictionary:
	var out := {}
	var dir_path := DATA_DIR.path_join(sub)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		errors.append("missing data directory %s" % dir_path)
		return out
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var data: Variant = read_json(dir_path.path_join(f))
		if data is Dictionary:
			out[f.get_basename()] = data
		else:
			errors.append("could not parse %s/%s" % [sub, f])
	return out


# --- Validation ----------------------------------------------------------------

func validate() -> void:
	for id in items:
		_require(items[id], ["name", "desc", "category", "value"], "items.%s" % id)
	for id in crops:
		var c: Dictionary = crops[id]
		_require(c, ["name", "days", "seed", "yield", "ranges"], "crops.%s" % id)
		_ref_item(c.get("seed", ""), "crops.%s.seed" % id)
		for y in c.get("yield", {}):
			_ref_item(y, "crops.%s.yield" % id)
	for id in machines:
		var m: Dictionary = machines[id]
		_require(m, ["name", "desc", "size", "cost"], "machines.%s" % id)
		for it in m.get("cost", {}):
			_ref_item(it, "machines.%s.cost" % id)
	for id in recipes:
		var r: Dictionary = recipes[id]
		_require(r, ["inputs", "output"], "recipes.%s" % id)
		for it in r.get("inputs", {}):
			_ref_item(it, "recipes.%s.inputs" % id)
		var out_id: String = r.get("output", {}).get("item", "")
		if not out_id.is_empty():
			_ref_item(out_id, "recipes.%s.output" % id)
		var out_m: String = r.get("output", {}).get("machine", "")
		if not out_m.is_empty() and not machines.has(out_m):
			errors.append("recipes.%s.output references unknown machine '%s'" % [id, out_m])
	for id in npcs:
		_require(npcs[id], ["name", "role", "values", "schedule"], "npcs.%s" % id)
	for id in markets:
		for it in markets[id].get("buys", []) + markets[id].get("sells", []):
			_ref_item(it, "markets.%s" % id)
	for id in machines:
		for part in machines[id].get("requires", {}):
			_ref_item(part, "machines.%s.requires" % id)
	for id in npcs:
		for key in ["likes", "loves", "dislikes"]:
			for it in npcs[id].get(key, []):
				_ref_item(it, "npcs.%s.%s" % [id, key])


func _require(d: Dictionary, keys: Array, ctx: String) -> void:
	for k in keys:
		if not d.has(k):
			errors.append("%s is missing required key '%s'" % [ctx, k])


func _ref_item(id: String, ctx: String) -> void:
	if not items.has(id):
		errors.append("%s references unknown item '%s'" % [ctx, id])
