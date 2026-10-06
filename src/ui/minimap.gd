class_name Minimap
extends Control
## The corner map: the current area drawn from its cells (ground by material, water, walls,
## buildings, lamps and glowroots), a window that follows the salvager, residents as coloured
## dots, exits as arrows, and the objective as a pulsing ring (clamped to the rim, with an arrow,
## when it is off the window). In the Reach the map starts dark and fills in as you walk.
##
## Also used full-size by the map panel (`full = true`): the whole area, with place names.

const CELL_PX := 4
const COLORS := {
	"moss_floor": Color("2c4630"), "moss_deep": Color("335836"), "moss": Color("335836"),
	"grass": Color("33502f"), "gravel": Color("4a4640"), "cobble": Color("47454e"),
	"farm_soil": Color("4a3524"), "rock_floor": Color("3a3843"), "stairs": Color("5c5866"),
	"plank": Color("6a5038"), "ash": Color("4a4648"), "basalt": Color("332f38"),
	"blackstone": Color("2f2d36"), "mud": Color("3c3128"), "stone": Color("413f4a"),
	"dirt": Color("4a3a2e"), "water": Color("1f3c5a"), "rock": Color("2a2830"),
}
const NPC_COLORS := {"barnaby": Color("c9a25a"), "odile": Color("d98a4a"), "hesper": Color("8fd06a"),
	"mags": Color("e07a6a"), "grist": Color("b0aab8")}

var full := false
var zoom := 1.0
var _area: AreaMap
var _base: ImageTexture
var _fog_img: Image
var _fog: ImageTexture
var _seen: PackedByteArray
var _t := 0.0
var _fog_t := 0.0
var _font: Font


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiTheme.font()
	Events.area_changed.connect(func(_id: StringName) -> void: _area = null)


func _process(delta: float) -> void:
	_t += delta
	var game := _game()
	if game == null or game.area == null:
		return
	if _area != game.area:
		_rebuild(game.area)
	_fog_t -= delta
	if _fog_t <= 0.0 and _area.id != "wick" and game.player:
		_fog_t = 0.2
		_reveal(game.player.position)
	queue_redraw()


func _game() -> Node:
	var s := get_tree().current_scene if is_inside_tree() else null
	if s and "area" in s and "player" in s:
		return s
	return null


# --- Building the picture ---------------------------------------------------------------------

func _rebuild(a: AreaMap) -> void:
	_area = a
	var img := Image.create(a.w * CELL_PX, a.d * CELL_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color("121116"))
	for z in a.d:
		for x in a.w:
			var h := a.h_at(x, z)
			var col: Color
			if h >= AreaMap.WALL_LEVEL:
				col = Color("17161c")
			elif h == AreaMap.WATER_LEVEL:
				col = COLORS.water.lightened(0.08 if (x * 7 + z * 3) % 11 == 0 else 0.0)
			else:
				col = COLORS.get(a.mat_at(x, z), Color("3a3843"))
				col = col.lightened(clampf(float(h) * 0.035, 0.0, 0.3))
				if a.blocked[a.i(x, z)] != 0:
					col = col.darkened(0.45)
			img.fill_rect(Rect2i(x * CELL_PX, z * CELL_PX, CELL_PX, CELL_PX), col)
			# A wall next to open ground gets a light edge so caverns read as shapes.
			if h >= AreaMap.WALL_LEVEL:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nh := a.h_at(x + d.x, z + d.y)
					if nh < AreaMap.WALL_LEVEL and nh != AreaMap.WATER_LEVEL:
						img.fill_rect(Rect2i(x * CELL_PX, z * CELL_PX, CELL_PX, CELL_PX), Color("2b2833"))
						break
	for p: Dictionary in a.props:
		var t := String(p.get("type", ""))
		var px := int(p.get("x", 0))
		var pz := int(p.get("z", 0))
		if t == "house":
			var sz: Array = p.get("size", [1, 1])
			var r := Rect2i(px * CELL_PX, pz * CELL_PX, int(sz[0]) * CELL_PX, int(sz[1]) * CELL_PX)
			img.fill_rect(r, Color("5a3f2c"))
			img.fill_rect(r.grow(-1), Color("6e4e36"))
			var door: Array = p.get("door", [-1, -1])
			if int(door[0]) >= 0:
				img.fill_rect(Rect2i(int(door[0]) * CELL_PX + 1, int(door[1]) * CELL_PX + 1, CELL_PX - 2, CELL_PX - 2), Color("e8a33d"))
		elif t.begins_with("glowroot") or t == "pale_fungus" or t == "ember_crystal":
			var c := Color("56e0d4") if not t == "ember_crystal" else Color("ff7a2f")
			if t == "pale_fungus":
				c = Color("a58bd6")
			img.fill_rect(Rect2i(px * CELL_PX + 1, pz * CELL_PX + 1, 2, 2), c.darkened(0.25))
		elif t in ["town_lamp", "work_lamp"]:
			img.fill_rect(Rect2i(px * CELL_PX + 1, pz * CELL_PX + 1, 2, 2), Color("f5c875"))
	for r2: Dictionary in a.resources:
		var rc := Color("8e8a96")
		if String(r2.get("item", "")) == "glowglass":
			rc = Color("56e0d4")
		elif String(r2.get("type", "")) == "story_cache":
			rc = Color("efe3c2")
		img.fill_rect(Rect2i(int(r2.x) * CELL_PX + 1, int(r2.z) * CELL_PX + 1, 2, 2), rc)
	_base = ImageTexture.create_from_image(img)
	# Fog of war: Wick is home and fully known; caverns fill in as they're walked.
	_seen = PackedByteArray()
	_seen.resize(a.w * a.d)
	_seen.fill(1 if a.id == "wick" else 0)
	if a.id != "wick":
		var stored := String(GameState.areas.get(a.id, {}).get("seen", ""))
		if stored != "":
			var raw := Marshalls.base64_to_raw(stored)
			if raw.size() == _seen.size():
				_seen = raw
	_fog_img = Image.create(a.w, a.d, false, Image.FORMAT_RGBA8)
	for z in a.d:
		for x in a.w:
			_fog_img.set_pixel(x, z, Color(0.07, 0.066, 0.086, 0.0 if _seen[z * a.w + x] else 1.0))
	_fog = ImageTexture.create_from_image(_fog_img)


func _reveal(pos: Vector3) -> void:
	var cx := int(floor(pos.x))
	var cz := int(floor(pos.z))
	var r := 6
	var changed := false
	for z in range(cz - r, cz + r + 1):
		for x in range(cx - r, cx + r + 1):
			if not _area.inside(x, z) or Vector2(x - cx, z - cz).length() > r + 0.5:
				continue
			var i := z * _area.w + x
			if _seen[i] == 0:
				_seen[i] = 1
				_fog_img.set_pixel(x, z, Color(0, 0, 0, 0))
				changed = true
	if changed:
		_fog.update(_fog_img)
		if not GameState.areas.has(_area.id):
			GameState.areas[_area.id] = {"mined": {}}
		GameState.areas[_area.id]["seen"] = Marshalls.raw_to_base64(_seen)


## Fraction of the current cavern walked (for the journal and the map).
func explored() -> float:
	if _seen.is_empty():
		return 0.0
	var n := 0
	for b in _seen:
		n += b
	return float(n) / float(_seen.size())


# --- Drawing ----------------------------------------------------------------------------------

func _draw() -> void:
	var game := _game()
	if game == null or _base == null:
		return
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color("0d0c11"))
	var scale: float
	var origin: Vector2           # screen position of cell (0, 0)
	var pp := Vector2(game.player.position.x, game.player.position.z)
	if full:
		scale = minf(sz.x / float(_area.w), sz.y / float(_area.d))
		origin = (sz - Vector2(_area.w, _area.d) * scale) * 0.5
	else:
		scale = float(CELL_PX) * 1.5 * zoom
		origin = sz * 0.5 - pp * scale
	var map_rect := Rect2(origin, Vector2(_area.w, _area.d) * scale)
	draw_texture_rect(_base, map_rect, false)
	if _area.id != "wick":
		draw_texture_rect(_fog, map_rect, false)
	var to_screen := func(cell: Vector2) -> Vector2: return origin + cell * scale
	# Exits.
	for ex: Dictionary in _area.exits:
		var arr: Array = ex.arrive
		var c := Vector2(float(arr[0]) + 0.5, float(arr[1]) + 0.5)
		if not _is_seen(Vector2i(int(arr[0]), int(arr[1]))):
			continue
		var open := ReachGen.passable({"kind": String(ex.get("kind", ""))}, GameState.flags)
		_draw_diamond(to_screen.call(c), 4.0, UiTheme.LIVING if open else UiTheme.DANGER)
	# Residents.
	for id: String in game.npcs:
		var n: Node3D = game.npcs[id]
		if not n.visible or n.indoors:
			continue
		var p: Vector2 = to_screen.call(Vector2(n.position.x, n.position.z))
		if not Rect2(Vector2.ZERO, sz).grow(-2).has_point(p):
			continue
		var col: Color = NPC_COLORS.get(id, Color("efe3c2"))
		draw_circle(p, 3.6 if not full else 5.0, Color(0.05, 0.04, 0.07, 0.9))
		draw_circle(p, 2.6 if not full else 4.0, col if Society.is_met(id) else col.darkened(0.5))
		if full and Society.is_met(id):
			_label(p + Vector2(7, 4), Society.display_name(id), col, 13)
	# Place names (full map of Wick only).
	if full and _area.id == "wick":
		for k: String in Objectives.PLACE_NAMES:
			if _area.points.has(k) and k not in ["commons", "board", "well"]:
				var pt: Vector2i = _area.points[k]
				_label(to_screen.call(Vector2(pt.x + 0.5, pt.y - 0.6)), String(Objectives.PLACE_NAMES[k]), UiTheme.DIM, 13, true)
	# Objective.
	var o := Objectives.current()
	var lt := Objectives.local_target(o, _area)
	if not lt.is_empty():
		var tc: Vector2i = lt.cell
		var tp: Vector2 = to_screen.call(Vector2(tc.x + 0.5, tc.y + 0.5))
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		var inner := Rect2(Vector2.ZERO, sz).grow(-9)
		if inner.has_point(tp):
			draw_arc(tp, 5.0 + pulse * 3.0, 0, TAU, 20, Color(UiTheme.ACCENT, 0.9 - pulse * 0.4), 2.0)
			draw_circle(tp, 2.2, UiTheme.ACCENT)
			if full and String(lt.label) != "":
				_label(tp + Vector2(9, -6), String(lt.label), UiTheme.ACCENT, 14)
		else:
			# Off the window: a chevron on the rim pointing the way.
			var centre := sz * 0.5
			var dir := (tp - centre).normalized()
			var edge := _clamp_to_rect(centre, dir, inner)
			_draw_chevron(edge, dir, UiTheme.ACCENT.lerp(Color.WHITE, pulse * 0.3))
	# The salvager.
	var me: Vector2 = to_screen.call(pp)
	var f: Vector2 = game.player.facing.normalized() if game.player.facing.length() > 0.1 else Vector2(0, 1)
	var side := Vector2(-f.y, f.x)
	var tri := PackedVector2Array([me + f * 6.0, me - f * 4.0 + side * 4.0, me - f * 2.0, me - f * 4.0 - side * 4.0])
	draw_colored_polygon(tri, Color(0.05, 0.04, 0.07))
	var tri2 := PackedVector2Array([me + f * 4.5, me - f * 3.0 + side * 2.8, me - f * 1.4, me - f * 3.0 - side * 2.8])
	draw_colored_polygon(tri2, UiTheme.TEXT)
	draw_rect(Rect2(Vector2.ZERO, sz), UiTheme.BORDER, false, 2.0)


func _is_seen(c: Vector2i) -> bool:
	if _seen.is_empty() or not _area.inside(c.x, c.y):
		return true
	return _seen[c.y * _area.w + c.x] != 0


func _label(p: Vector2, text: String, col: Color, fsize: int, centred := false) -> void:
	var fs := UiTheme.size(fsize)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := p - Vector2(w * 0.5, 0) if centred else p
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.05, 0.04, 0.07, 0.9))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_diamond(p: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)


func _draw_chevron(p: Vector2, dir: Vector2, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([p + dir * 6.0, p - dir * 4.0 + side * 5.0, p - dir * 1.0, p - dir * 4.0 - side * 5.0])
	draw_colored_polygon(pts, Color(0.05, 0.04, 0.07))
	draw_colored_polygon(PackedVector2Array([p + dir * 4.5, p - dir * 3.0 + side * 3.5, p - dir * 0.5, p - dir * 3.0 - side * 3.5]), col)


static func _clamp_to_rect(from: Vector2, dir: Vector2, r: Rect2) -> Vector2:
	var t := INF
	if absf(dir.x) > 1e-4:
		t = minf(t, ((r.end.x if dir.x > 0 else r.position.x) - from.x) / dir.x)
	if absf(dir.y) > 1e-4:
		t = minf(t, ((r.end.y if dir.y > 0 else r.position.y) - from.y) / dir.y)
	return from + dir * t
