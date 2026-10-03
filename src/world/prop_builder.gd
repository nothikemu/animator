class_name PropBuilder
extends RefCounted
## Turns AreaMap props into geometry: static box-built structures go into one shared mesh
## (one draw call); billboards become PixelSprite3D nodes; key lights become Light3D nodes.

const PROPS_DIR := "res://assets/textures/props/"

## House look per variant: wall tiles, roof tile, wall height, roof rise, window style.
const HOUSES := {
	"lease": {"wall": "wall_plank", "roof": "roof_moss_0", "h": 2.4, "rise": 1.3, "lit": false, "chimney": true},
	"lantern_house": {"wall": "wall_stone", "upper": "wall_plaster", "roof": "roof_slate_0", "h": 3.0, "rise": 1.6, "lit": true, "chimney": true},
	"exchange": {"wall": "wall_brick", "roof": "roof_metal_0", "h": 3.2, "rise": 1.2, "lit": true, "chimney": false},
	"odile": {"wall": "wall_plaster", "roof": "roof_slate_dark_0", "h": 2.6, "rise": 1.4, "lit": true, "chimney": true},
	"pump_hall": {"wall": "wall_brick_dark", "roof": "roof_metal_0", "h": 5.6, "rise": 2.0, "lit": false, "chimney": true},
	"annex": {"wall": "wall_plank", "roof": "roof_metal_0", "h": 2.6, "rise": 1.0, "lit": true, "chimney": true},
	"hesper": {"wall": "wall_plaster", "roof": "roof_moss_0", "h": 2.4, "rise": 1.4, "lit": true, "chimney": false},
}

const SELF_LIT_LAYER := 2   ## render layer bit for emissive plants/lamps (not lit by their own light)

const BILLBOARDS := {
	"glowroot": ["glowroot_", 3], "glowroot_small": ["glowroot_small_", 2], "moss_tuft": ["moss_tuft_", 3],
	"mushroom": ["mushroom_", 2], "stalagmite": ["stalagmite_", 3], "shore_rock": ["shore_rock_", 2],
	"rubble_small": ["rubble_small", 0], "rubble": ["rubble", 0], "salvage_harness": ["salvage_harness", 0],
	"town_lamp": ["town_lamp", 0], "porch_lamp": ["porch_lamp", 0], "gear_pile": ["gear_pile", 0],
	"work_lamp": ["work_lamp", 0], "bedroll": ["bedroll", 0], "ember_crystal": ["ember_crystal", 0], "pale_fungus": ["pale_fungus", 0],
	"pale_fungus_small": ["mushroom_", 2], "glowroot_fringe": ["glowroot_small_", 2],
	"crate_broken": ["crate_broken", 0], "ash_pile": ["rubble_small", 0], "cinder_rock": ["shore_rock_", 2],
	"reed": ["moss_tuft_", 3], "drip_rock": ["stalagmite_", 3], "rail": ["gear_pile", 0],
}

var area: AreaMap
var kit := MeshKit.new()               ## static geometry
var root: Node3D
var fade_groups: Dictionary = {}       ## name -> Node3D (e.g. the Lease roof)
var lights: Array[Light3D] = []
var interactables: Array = []          ## [{node, type, data}]
var glowroot_lights := 0


func _init(a: AreaMap, parent: Node3D) -> void:
	area = a
	root = parent


func build_all(material: Material) -> void:
	for p in area.props:
		_prop(p)
	var mi := MeshInstance3D.new()
	mi.name = "Structures"
	mi.mesh = kit.commit()
	mi.material_override = material
	root.add_child(mi)
	for name in fade_groups:
		var fk: MeshKit = fade_groups[name].get_meta("kit")
		var fm := MeshInstance3D.new()
		fm.mesh = fk.commit()
		fm.material_override = material
		fade_groups[name].add_child(fm)
	for l in area.lights:
		_light(Vector3(float(l.x), float(l.y), float(l.z)), String(l.color), float(l.energy), float(l.range), false)


func _base_y(x: int, z: int) -> float:
	return area.world_y(x, z)


func _prop(p: Dictionary) -> void:
	var t := String(p.type)
	var x := int(p.x)
	var z := int(p.z)
	var y := _base_y(x, z)
	var sz: Array = p.get("size", [1, 1])
	match t:
		"house":
			_house(p, y)
		"table":
			kit.box(Vector3(x + 0.05, y + 0.65, z + 0.15), Vector3(float(sz[0]) - 0.1, 0.12, 0.7), {"side": "plank_0", "top": "plank_1"})
			for dx in [0.15, float(sz[0]) - 0.3]:
				kit.box(Vector3(x + dx, y, z + 0.25), Vector3(0.15, 0.65, 0.15), {"side": "beam_0"})
				kit.box(Vector3(x + dx, y, z + 0.6), Vector3(0.15, 0.65, 0.15), {"side": "beam_0"})
		"bench_seat":
			kit.box(Vector3(x + 0.05, y + 0.35, z + 0.3), Vector3(float(sz[0]) - 0.1, 0.1, 0.4), {"side": "plank_0"})
			kit.box(Vector3(x + 0.15, y, z + 0.4), Vector3(0.12, 0.35, 0.2), {"side": "beam_0"})
			kit.box(Vector3(x + float(sz[0]) - 0.27, y, z + 0.4), Vector3(0.12, 0.35, 0.2), {"side": "beam_0"})
		"crate":
			kit.box(Vector3(x + 0.12, y, z + 0.12), Vector3(0.76, 0.7, 0.76), {"side": "plank_1", "top": "plank_0"})
		"crate_stack":
			kit.box(Vector3(x + 0.08, y, z + 0.1), Vector3(0.84, 0.8, 0.8), {"side": "plank_1"})
			kit.box(Vector3(x + 0.2, y + 0.8, z + 0.2), Vector3(0.6, 0.6, 0.6), {"side": "plank_0"})
		"barrel":
			kit.prism(Vector3(x + 0.5, y, z + 0.5), 0.36, 0.85, 8, "plank_1", "plank_0")
		"fence":
			kit.box(Vector3(x, y + 0.45, z + 0.45), Vector3(1.0, 0.1, 0.1), {"side": "beam_0"})
			kit.box(Vector3(x, y + 0.2, z + 0.45), Vector3(1.0, 0.08, 0.08), {"side": "beam_0"})
			kit.box(Vector3(x + 0.02, y, z + 0.42), Vector3(0.14, 0.62, 0.14), {"side": "beam_0"})
		"fence_post", "dock_post":
			kit.box(Vector3(x + 0.38, y - 0.6, z + 0.38), Vector3(0.24, 1.3, 0.24), {"side": "beam_0"})
		"notice_board":
			kit.box(Vector3(x + 0.1, y, z + 0.45), Vector3(0.12, 1.6, 0.12), {"side": "beam_0"})
			kit.box(Vector3(x + 0.78, y, z + 0.45), Vector3(0.12, 1.6, 0.12), {"side": "beam_0"})
			kit.box(Vector3(x - 0.1, y + 0.8, z + 0.42), Vector3(1.2, 0.8, 0.1), {"side": "plank_1", "front": "plank_0"})
			_billboard("lore_page", Vector3(x + 0.25, y + 0.95, z + 0.53), 0.9, false, false)
			_billboard("lore_page", Vector3(x + 0.7, y + 1.0, z + 0.53), 0.8, false, false)
		"market_stall":
			kit.box(Vector3(x, y, z + 0.2), Vector3(float(sz[0]), 0.85, 0.7), {"side": "plank_1", "top": "plank_0"})
			kit.box(Vector3(x - 0.1, y + 1.7, z), Vector3(float(sz[0]) + 0.2, 0.08, 1.1), {"side": "roof_metal_0"})
			kit.box(Vector3(x, y, z + 0.9), Vector3(0.1, 1.7, 0.1), {"side": "beam_0"})
			kit.box(Vector3(x + float(sz[0]) - 0.1, y, z + 0.9), Vector3(0.1, 1.7, 0.1), {"side": "beam_0"})
			_billboard("jars", Vector3(x + 0.7, y + 0.85, z + 0.5), 0.8, false)
		"workbench":
			kit.box(Vector3(x + 0.05, y + 0.75, z + 0.1), Vector3(0.9, 0.12, 0.8), {"side": "plank_0", "top": "metal_brass_0"})
			kit.box(Vector3(x + 0.1, y, z + 0.15), Vector3(0.8, 0.75, 0.7), {"side": "plank_1"})
			_billboard("gear_pile", Vector3(x + 0.5, y + 0.87, z + 0.5), 0.7, false)
		"chest":
			kit.box(Vector3(x + 0.15, y, z + 0.25), Vector3(0.7, 0.5, 0.5), {"side": "plank_1", "top": "metal_brass_0"})
		"bed":
			kit.box(Vector3(x + 0.1, y, z + 0.1), Vector3(0.8, 0.45, float(sz[1]) - 0.2), {"side": "plank_1", "top": "rug_0"})
			kit.box(Vector3(x + 0.1, y + 0.45, z + 0.1), Vector3(0.8, 0.3, 0.4), {"side": "wall_plaster_0"})
		"stove":
			kit.box(Vector3(x + 0.15, y, z + 0.2), Vector3(0.7, 0.8, 0.6), {"side": "wall_stone_0", "top": "metal_brass_0"})
			kit.box(Vector3(x + 0.38, y + 0.8, z + 0.38), Vector3(0.24, 1.6, 0.24), {"side": "metal_brass_0"})
		"shelf":
			kit.box(Vector3(x + 0.1, y + 0.9, z + 0.1), Vector3(0.8, 0.08, 0.35), {"side": "plank_0"})
			_billboard("jars", Vector3(x + 0.5, y + 0.98, z + 0.28), 0.6, false)
		"signpost":
			kit.box(Vector3(x + 0.44, y, z + 0.44), Vector3(0.12, 1.5, 0.12), {"side": "beam_0"})
			kit.box(Vector3(x - 0.1, y + 1.05, z + 0.4), Vector3(1.2, 0.35, 0.08), {"side": "plank_0"})
		"chimney_pipe":
			kit.prism(Vector3(x + 0.5, y, z + 0.5), 0.3, 4.5, 8, "metal_brass_0", "black_0")
		"pipe_pile":
			for i in 3:
				kit.box(Vector3(x + 0.05, y + i * 0.18, z + 0.1 + i * 0.25), Vector3(0.95, 0.16, 0.16), {"side": "metal_brass_0"})
		"moss_frame":
			kit.box(Vector3(x + 0.05, y, z + 0.1), Vector3(float(sz[0]) - 0.1, 0.35, 0.8), {"side": "beam_0", "top": "moss_deep_0"})
		"specimen_rack":
			kit.box(Vector3(x + 0.1, y, z + 0.3), Vector3(0.8, 1.1, 0.4), {"side": "plank_1"})
			_billboard("jars", Vector3(x + 0.5, y + 1.1, z + 0.5), 0.8, false)
		"boat":
			kit.box(Vector3(x - 0.4, -0.35, z + 0.1), Vector3(1.8, 0.3, 0.8), {"side": "plank_1", "top": "plank_0"})
		"reach_gate":
			kit.box(Vector3(x - 0.2, y, z - 0.2), Vector3(1.2, 3.0, 0.4), {"side": "wall_stone_0"})
			kit.box(Vector3(x - 0.2, y, z + float(sz[1]) - 0.2), Vector3(1.2, 3.0, 0.4), {"side": "wall_stone_0"})
			kit.box(Vector3(x - 0.3, y + 3.0, z - 0.3), Vector3(1.4, 0.5, float(sz[1]) + 0.6), {"side": "beam_0"})
			_light(Vector3(x - 0.5, y + 2.6, z + float(sz[1]) * 0.5), "amber", 1.2, 5.0, false)
		"chute":
			_light(Vector3(x + 1.0, 7.0, z + 1.0), "cream", 2.2, 10.0, true, true)
		"bed_roll", "lore_desk":
			pass
		"brick_wall":
			kit.box(Vector3(x, y, z), Vector3(1, 1.4 + float(absi(x * 7 + z * 3) % 3) * 0.4, 1), {"side": "wall_brick_dark_0", "top": "rock_0"})
		"broken_machine":
			kit.box(Vector3(x + 0.1, y, z + 0.1), Vector3(float(sz[0]) - 0.2, 1.1, 0.8), {"side": "metal_brass_0", "top": "rock_0"})
			kit.prism(Vector3(x + 0.6, y + 1.1, z + 0.5), 0.2, 0.8, 6, "metal_brass_0")
		"trunk_valve_housing":
			kit.box(Vector3(x, y, z + 0.1), Vector3(float(sz[0]), 1.6, 0.8), {"side": "metal_brass_0", "top": "metal_brass_0"})
			kit.prism(Vector3(x + float(sz[0]) * 0.5, y + 1.6, z + 0.5), 0.5, 0.25, 8, "metal_brass_0", "metal_brass_0")
		"ruin":
			pass
		"heat_vent":
			_light(Vector3(x + 0.5, y + 0.6, z + 0.5), "ember", 1.6, 4.0, false)
		_:
			if BILLBOARDS.has(t):
				var spec: Array = BILLBOARDS[t]
				var tex := String(spec[0])
				if int(spec[1]) > 0:
					tex += str(absi(x * 31 + z * 17) % int(spec[1]))
				var s := float(p.get("scale", 1.0))
				var sway := t in ["glowroot", "glowroot_small", "moss_tuft", "reed", "glowroot_fringe"]
				var jitter := Vector3(float((x * 13 + z * 7) % 5) * 0.06 - 0.12, 0, float((x * 5 + z * 11) % 5) * 0.06 - 0.12)
				var bb := _billboard(tex, Vector3(x + 0.5, y, z + 0.5) + (jitter if p.get("deco", false) or t in ["moss_tuft", "mushroom", "glowroot_small"] else Vector3.ZERO), s, sway)
				if t in ["glowroot", "glowroot_small", "town_lamp", "porch_lamp", "work_lamp", "pale_fungus", "ember_crystal"] and bb:
					bb.layers = SELF_LIT_LAYER
				if t == "glowroot":
					var gl := _light(Vector3(x + 0.5, y + 2.0 * s, z + 1.1), "glow", 1.1 * s, 6.0 * s, false)
					gl.light_cull_mask = ~SELF_LIT_LAYER & 0xFFFFF
				elif t in ["town_lamp", "porch_lamp", "work_lamp"]:
					var ll := _light(Vector3(x + 0.5, y + (2.2 if t == "town_lamp" else 1.7), z + 0.7),
						"amber" if t != "work_lamp" else "cream", 1.5, 6.5, t == "town_lamp")
					ll.light_cull_mask = ~SELF_LIT_LAYER & 0xFFFFF
				elif t == "pale_fungus" or t == "ember_crystal":
					pass


func _billboard(tex_name: String, pos: Vector3, scale := 1.0, sway := false, cut := true) -> PixelSprite3D:
	var path := PROPS_DIR + tex_name + ".png"
	var t := PixelSprite3D.load_tex(path)
	if t[0] == null:
		Log.warn("props", "missing sprite %s" % tex_name)
		return null
	var tex: Texture2D = t[0]
	var opts := {"rim_strength": 0.25}
	if tex_name in ["town_lamp", "porch_lamp", "work_lamp"]:
		opts["is_lamp"] = true
	if sway:
		opts["sway"] = 0.05
	if not cut:
		opts["cuttable"] = false
	var s := PixelSprite3D.new()
	s.setup(tex, t[1], Vector2i(tex.get_width(), tex.get_height()), Vector2i(1, 1), opts, scale)
	s.position = pos
	s.name = tex_name
	root.add_child(s)
	return s


const LIGHT_COLORS := {"glow": Color("56e0d4"), "amber": Color("f0aa52"), "cream": Color("efe3c2"),
	"ember": Color("ff7a2f"), "violet": Color("8d6bd6")}


func _light(pos: Vector3, color: String, energy: float, range_m: float, shadows: bool, spot := false) -> Light3D:
	var l: Light3D
	if spot:
		var sl := SpotLight3D.new()
		sl.spot_range = range_m
		sl.spot_angle = 22.0
		sl.spot_attenuation = 0.6
		sl.rotation_degrees = Vector3(-90, 0, 0)
		l = sl
	else:
		var ol := OmniLight3D.new()
		ol.omni_range = range_m
		ol.omni_attenuation = 1.15
		l = ol
	l.light_color = LIGHT_COLORS.get(color, Color.WHITE)
	l.light_energy = energy
	l.shadow_enabled = shadows
	l.position = pos
	l.set_meta("base_energy", energy)
	l.set_meta("kind", color)
	root.add_child(l)
	lights.append(l)
	return l


# --- Houses ---------------------------------------------------------------------------------

func _house(p: Dictionary, y: float) -> void:
	var v := String(p.variant)
	var spec: Dictionary = HOUSES.get(v, HOUSES.lease)
	var x := float(p.x)
	var z := float(p.z)
	var sz: Array = p.size
	var w := float(sz[0])
	var d := float(sz[1])
	var h := float(spec.h)
	var wall_tile := Atlas.variant(String(spec.wall), int(x), int(z))
	var door: Array = p.get("door", [int(x) + 1, int(z) + int(d) - 1])
	var interior := bool(p.get("interior", false))
	var k := kit
	if interior:
		_interior_house(p, spec, y)
		return
	# Main body (inset slightly so outlines read).
	var tiles := {"side": wall_tile}
	if spec.has("upper"):
		k.box(Vector3(x + 0.1, y, z + 0.1), Vector3(w - 0.2, h * 0.45, d - 0.2), tiles)
		k.box(Vector3(x + 0.1, y + h * 0.45, z + 0.1), Vector3(w - 0.2, h * 0.55, d - 0.2), {"side": Atlas.variant(String(spec.upper), int(x), int(z))})
		k.box(Vector3(x, y + h * 0.45 - 0.08, z), Vector3(w, 0.16, d), {"side": "beam_0"})
	else:
		k.box(Vector3(x + 0.1, y, z + 0.1), Vector3(w - 0.2, h, d - 0.2), tiles)
	# Corner beams.
	for cx in [x + 0.02, x + w - 0.26]:
		k.box(Vector3(cx, y, z + d - 0.26), Vector3(0.24, h, 0.24), {"side": "beam_0"})
	k.gable_roof(Vector3(x + 0.1, y + h, z + 0.1), Vector2(w - 0.2, d - 0.2), float(spec.rise), String(spec.roof), wall_tile)
	# Door and windows on the south face.
	var fz := z + d - 0.1 + 0.012
	var dx := float(door[0]) + 0.5
	k.decal(Vector3(dx, y + 0.9, fz), Vector2(0.9, 1.8), "door_0")
	var win := "window_lit_0" if spec.lit else "window_dark_0"
	var wx := x + 0.9
	while wx < x + w - 0.6:
		if absf(wx - dx) > 1.0:
			k.decal(Vector3(wx, y + h * 0.55, fz), Vector2(0.8, 0.8), win)
		wx += 1.6
	if spec.lit:
		_light(Vector3(dx + 0.6, y + 1.4, fz + 0.6), "amber", 0.9, 4.0, false)
	if spec.chimney:
		k.box(Vector3(x + w - 1.2, y + h + float(spec.rise) * 0.4, z + 0.6), Vector3(0.6, float(spec.rise) * 0.9, 0.6), {"side": "wall_stone_0", "top": "black_0"})
	match v:
		"pump_hall":
			# Great pipes running down the front into the ground, and a dead brass plate.
			for px_ in [x + 1.5, x + w - 2.0]:
				k.prism(Vector3(px_, y - 0.5, z + d + 0.1), 0.35, h + 0.5, 8, "metal_brass_0")
			k.box(Vector3(x + w * 0.5 - 1.0, y + h - 1.4, fz - 0.01), Vector3(2.0, 0.6, 0.06), {"side": "metal_brass_0"})
			k.box(Vector3(x + 2.0, y + h + float(spec.rise) * 0.3, z + 1.0), Vector3(0.9, 2.6, 0.9), {"side": "wall_brick_dark_0", "top": "black_0"})
		"lantern_house":
			_billboard("town_lamp", Vector3(dx + 1.2, y, fz + 0.4), 1.0)
			_light(Vector3(dx + 1.2, y + 2.2, fz + 0.4), "amber", 1.6, 7.0, true)
		"exchange":
			k.box(Vector3(x + 0.8, y + h - 0.3, fz), Vector3(w - 1.6, 0.5, 0.08), {"side": "plank_0"})
			k.box(Vector3(x + w * 0.5 - 0.4, y + h - 0.2, fz + 0.06), Vector3(0.8, 0.3, 0.04), {"side": "metal_brass_0"})
		"hesper":
			_billboard("jars", Vector3(x + w - 0.8, y + 0.9, fz + 0.15), 0.8, false)


func _interior_house(p: Dictionary, spec: Dictionary, y: float) -> void:
	var x := float(p.x)
	var z := float(p.z)
	var sz: Array = p.size
	var w := float(sz[0])
	var d := float(sz[1])
	var h := float(spec.h)
	var door: Array = p.door
	var wall := Atlas.variant(String(spec.wall), int(x), int(z))
	var t := 0.22
	# Floor.
	kit.box(Vector3(x + t, y, z + t), Vector3(w - 2 * t, 0.04, d - 2 * t), {"side": "floorboard_0", "top": "floorboard_0"})
	# Back and side walls (always visible).
	kit.box(Vector3(x, y, z), Vector3(w, h, t), {"side": wall})
	kit.box(Vector3(x, y, z), Vector3(t, h, d), {"side": wall})
	kit.box(Vector3(x + w - t, y, z), Vector3(t, h, d), {"side": wall})
	kit.decal(Vector3(x + w * 0.5, y + h * 0.6, z + t + 0.01), Vector2(0.8, 0.8), "window_dark_0")
	# Front wall and roof fade when the player is inside (dollhouse cutaway).
	var group := Node3D.new()
	group.name = "Fade_" + String(p.variant)
	var fk := MeshKit.new()
	group.set_meta("kit", fk)
	var dxl := float(door[0]) - x
	fk.box(Vector3(x, y, z + d - t), Vector3(dxl, h, t), {"side": wall})
	fk.box(Vector3(float(door[0]) + 1.0, y, z + d - t), Vector3(x + w - float(door[0]) - 1.0, h, t), {"side": wall})
	fk.box(Vector3(float(door[0]), y + 1.9, z + d - t), Vector3(1.0, h - 1.9, t), {"side": wall})
	fk.decal(Vector3(x + w - 1.2, y + h * 0.55, z + d + 0.012), Vector2(0.8, 0.8), "window_dark_0")
	fk.gable_roof(Vector3(x, y + h, z), Vector2(w, d), float(spec.rise), String(spec.roof), wall)
	if spec.chimney:
		fk.box(Vector3(x + 1.0, y + h + float(spec.rise) * 0.4, z + 0.8), Vector3(0.6, float(spec.rise) * 0.8, 0.6), {"side": "wall_stone_0", "top": "black_0"})
	root.add_child(group)
	fade_groups[String(p.variant)] = group
	group.set_meta("rect", Rect2(x, z, w, d))
