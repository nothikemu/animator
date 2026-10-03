class_name AreaMap
extends RefCounted
## Walkable 3D area description shared by the hand-authored village and generated caverns.
## Cells are 1 m squares on the XZ plane; height is in half-metre levels.

const WALL_LEVEL := 16                ## cavern walls / cliffs
const WATER_LEVEL := -1               ## water surface cells (not walkable)
const STEP := 0.5                     ## metres per height level
const MAX_CLIMB := 1                  ## levels the player can step up without stairs

var id := ""
var biome := "grove"
var w := 1
var d := 1
var height: PackedInt32Array
var mat: PackedStringArray            ## surface material per cell
var blocked: PackedByteArray          ## props that block movement
var props: Array = []                 ## [{type, x, z, ...}]
var points: Dictionary = {}           ## named spots -> Vector2i
var exits: Array = []                 ## [{x, z, to, arrive}]
var lights: Array = []                ## [{x, z, y, color, energy, range, kind}]
var resources: Array = []             ## [{id, x, z, item, n, hp}]
var meta: Dictionary = {}


func _init(width: int = 1, depth: int = 1) -> void:
	w = width
	d = depth
	height = PackedInt32Array()
	height.resize(w * d)
	height.fill(0)
	mat = PackedStringArray()
	mat.resize(w * d)
	mat.fill("stone")
	blocked = PackedByteArray()
	blocked.resize(w * d)
	blocked.fill(0)


func i(x: int, z: int) -> int:
	return z * w + x


func inside(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < w and z < d


func h_at(x: int, z: int) -> int:
	return height[z * w + x] if inside(x, z) else WALL_LEVEL


func mat_at(x: int, z: int) -> String:
	return mat[z * w + x] if inside(x, z) else "rock"


func world_y(x: int, z: int) -> float:
	return maxf(0.0, float(h_at(x, z))) * STEP if h_at(x, z) != WATER_LEVEL else -0.35


func is_walkable(x: int, z: int) -> bool:
	if not inside(x, z):
		return false
	var hh := height[z * w + x]
	return hh != WATER_LEVEL and hh < WALL_LEVEL and blocked[z * w + x] == 0


## Whether a walker can move from cell a to adjacent cell b (step height rule).
func can_step(ax: int, az: int, bx: int, bz: int) -> bool:
	if not is_walkable(bx, bz):
		return false
	var ha := h_at(ax, az)
	var hb := h_at(bx, bz)
	if mat_at(bx, bz) == "stairs" or mat_at(ax, az) == "stairs":
		return absi(ha - hb) <= 2
	return absi(ha - hb) <= MAX_CLIMB


## Builds an AStarGrid2D for NPC navigation (step rules applied via solid cells).
func build_astar() -> AStarGrid2D:
	var a := AStarGrid2D.new()
	a.region = Rect2i(0, 0, w, d)
	a.cell_size = Vector2.ONE
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	a.update()
	for z in d:
		for x in w:
			if not is_walkable(x, z):
				a.set_point_solid(Vector2i(x, z), true)
	return a


func to_dict() -> Dictionary:
	return {"id": id, "biome": biome, "w": w, "d": d,
		"height": Array(height), "mat": Array(mat), "blocked": Array(blocked),
		"props": props, "exits": exits, "lights": lights, "resources": resources, "meta": meta,
		"points": _points_to_dict()}


func _points_to_dict() -> Dictionary:
	var out := {}
	for k in points:
		out[k] = [points[k].x, points[k].y]
	return out


## Builds an AreaMap from the authored ASCII format (see data/wick_map.json).
static func from_ascii(def: Dictionary) -> AreaMap:
	var rows_h: Array = def.get("height", [])
	var rows_m: Array = def.get("mat", [])
	var legend: Dictionary = def.get("legend", {})
	var width := 0
	for r in rows_h:
		width = maxi(width, String(r).length())
	var a := AreaMap.new(width, rows_h.size())
	a.id = String(def.get("id", "wick"))
	a.biome = String(def.get("biome", "grove"))
	for z in rows_h.size():
		var hr := String(rows_h[z])
		var mr := String(rows_m[z]) if z < rows_m.size() else ""
		for x in width:
			var hc := hr[x] if x < hr.length() else "W"
			a.height[a.i(x, z)] = _height_char(hc)
			var mc := mr[x] if x < mr.length() else "#"
			a.mat[a.i(x, z)] = String(legend.get(mc, "stone"))
			if hc == "~":
				a.mat[a.i(x, z)] = "water"
	for p in def.get("points", {}):
		var v: Array = def.points[p]
		a.points[p] = Vector2i(int(v[0]), int(v[1]))
	a.props = def.get("props", []).duplicate(true)
	a.exits = def.get("exits", []).duplicate(true)
	a.lights = def.get("lights", []).duplicate(true)
	a.meta = def.get("meta", {}).duplicate(true)
	for p in a.props:
		if bool(p.get("block", false)):
			var sz: Array = p.get("size", [1, 1])
			var interior := bool(p.get("interior", false))
			var door: Array = p.get("door", [-1, -1])
			for dz in int(sz[1]):
				for dx in int(sz[0]):
					var cx := int(p.x) + dx
					var cz := int(p.z) + dz
					if not a.inside(cx, cz):
						continue
					# Cutaway houses only block their walls; the door stays open.
					if interior:
						var edge := dx == 0 or dz == 0 or dx == int(sz[0]) - 1 or dz == int(sz[1]) - 1
						if not edge or (cx == int(door[0]) and cz == int(door[1])):
							continue
					a.blocked[a.i(cx, cz)] = 1
	return a


static func _height_char(c: String) -> int:
	if c == "W":
		return WALL_LEVEL
	if c == "~":
		return WATER_LEVEL
	if c.is_valid_int():
		return int(c)
	var code := c.unicode_at(0)
	if code >= 65 and code <= 70:   # A-F = 10-15
		return 10 + code - 65
	return 0
