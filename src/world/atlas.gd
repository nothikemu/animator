class_name Atlas
extends RefCounted
## Lookup for the generated tile atlas (assets/textures/terrain.json).

const TEX_PATH := "res://assets/textures/terrain.png"
const EMIT_PATH := "res://assets/textures/terrain_emit.png"
const JSON_PATH := "res://assets/textures/terrain.json"

static var _data: Dictionary = {}
static var _variants: Dictionary = {}    ## base name -> Array of tile names


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = Content.read_json(JSON_PATH)
		_data = d if d is Dictionary else {"tile": 16, "cols": 16, "tiles": {}}
		for name: String in _data.tiles:
			var base := name
			var us := name.rfind("_")
			if us > 0 and name.substr(us + 1).is_valid_int():
				base = name.substr(0, us)
			if not _variants.has(base):
				_variants[base] = []
			_variants[base].append(name)
		for b in _variants:
			_variants[b].sort()
	return _data


## UV rectangle (in 0..1) of a tile. Unknown names fall back to a visible magenta-free tile.
static func uv_rect(name: String) -> Rect2:
	var d := data()
	var t: Variant = d.tiles.get(name)
	if t == null:
		t = d.tiles.get("rock_0", [0, 0])
	var cols := float(d.cols)
	var inset := 0.02 / (cols * float(d.tile))
	return Rect2(Vector2(float(t[0]) / cols + inset, float(t[1]) / cols + inset),
		Vector2(1.0 / cols - inset * 2.0, 1.0 / cols - inset * 2.0))


## Picks a deterministic variant of a base tile name for cell (x, z).
static func variant(base: String, x: int, z: int) -> String:
	data()
	var list: Array = _variants.get(base, [])
	if list.is_empty():
		return base
	var hsh := absi((x * 73856093) ^ (z * 19349663) ^ base.hash())
	return String(list[hsh % list.size()])


static func has(base: String) -> bool:
	data()
	return _variants.has(base) or data().tiles.has(base)
