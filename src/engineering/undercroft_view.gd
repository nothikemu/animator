class_name UndercroftView
extends Node3D
## The Undercroft as a physical object: a one-cell-thick slab of strata whose front face lies
## on the cut plane, with cavities carved into it, live field planes (water, gas, heat) fed
## from the simulation, conduits that show their flow, machines and relics.
##
## Grid cell (x, y) occupies world x in [x, x+1], y in [ground_y - y - 1, ground_y - y],
## z in [BACK_Z, FRONT_Z]. Rows above ground are the village slice and are left to the
## 3D town (only gas is drawn there).

const FRONT_Z := 21.0
const BACK_Z := 20.0
const MACHINE_Z := 20.5
const PIPE_Z := 21.14
const WIRE_Z := 21.24
const WATER_Z := 20.8
const GAS_Z := 20.9
const HEAT_Z := 20.96
const UC_LAYER := 1 << 7                 ## lit by the cut-mode work light only
const PIPE_COLOR := Color(0.61, 0.48, 0.24)
const WIRE_COLOR := Color(0.62, 0.3, 0.2)

var grid: UcGrid
var slab: MeshInstance3D
var water_plane: MeshInstance3D
var gas_plane: MeshInstance3D
var heat_plane: MeshInstance3D
var conduit_root: Node3D
var machine_root: Node3D
var relic_root: Node3D
var light_root: Node3D
var work_light: DirectionalLight3D
var overlay := "none"                    ## none | gas | water | power | heat

var _slab_mat: ShaderMaterial
var _field_mats: Array[ShaderMaterial] = []
var _water_img: Image
var _gas_img: Image
var _heat_img: Image
var _mask_img: Image
var _water_tex: ImageTexture
var _gas_tex: ImageTexture
var _heat_tex: ImageTexture
var _mask_tex: ImageTexture
var _pipe_mat: ShaderMaterial
var _wire_mat: ShaderMaterial
var _net_nodes: Array = []               ## [{node, layer, net}]
var _machine_nodes: Dictionary = {}      ## machine id -> {sprite, light, def}
var _conduit_sig := ""
var _anim_t := 0.0
var _fields_dirty := true
var _sprite_meta: Dictionary = {}


func _ready() -> void:
	name = "UndercroftView"
	_sprite_meta = _load_sprite_meta()
	_slab_mat = AreaView.terrain_material().duplicate() as ShaderMaterial
	_slab_mat.set_shader_parameter("cuttable", false)
	_pipe_mat = _conduit_material(PIPE_COLOR, Color(0.5, 0.85, 0.9), false)
	_wire_mat = _conduit_material(WIRE_COLOR, Color(1.0, 0.82, 0.35), true)
	slab = MeshInstance3D.new()
	slab.name = "Slab"
	slab.material_override = _slab_mat
	slab.layers = 1 | UC_LAYER
	add_child(slab)
	conduit_root = _child("Conduits")
	machine_root = _child("Machines")
	relic_root = _child("Relics")
	light_root = _child("Lights")
	work_light = DirectionalLight3D.new()
	work_light.name = "WorkLight"
	work_light.rotation_degrees = Vector3(-18, 8, 0)
	work_light.light_energy = 1.15
	work_light.light_color = Color(0.96, 0.9, 0.82)
	work_light.light_cull_mask = UC_LAYER
	work_light.shadow_enabled = false
	add_child(work_light)
	Sim.stepped.connect(func() -> void: _fields_dirty = true)
	Sim.ticked.connect(_on_ticked)
	Events.grid_cells_changed.connect(func(_c: Array) -> void: rebuild_slab())
	Events.sim_topology_changed.connect(func() -> void: _conduit_sig = ""; _on_ticked())
	Events.machine_changed.connect(func(_id: int) -> void: sync_machines())
	rebuild()


func _child(n: String) -> Node3D:
	var c := Node3D.new()
	c.name = n
	add_child(c)
	return c


func rebuild() -> void:
	grid = Sim.grid
	if grid == null:
		return
	rebuild_slab()
	_build_fields()
	_build_relics()
	_conduit_sig = ""
	_on_ticked()
	_fields_dirty = true


# --- Coordinates ------------------------------------------------------------------------------

func cell_top(y: int) -> float:
	return float(grid.ground_y - y)


func cell_center(c: Vector2i, z := MACHINE_Z) -> Vector3:
	return Vector3(c.x + 0.5, cell_top(c.y) - 0.5, z)


## Grid cell under a world point on the slab (any z).
func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x)), grid.ground_y - int(floor(p.y)) - 1)


# --- Slab -------------------------------------------------------------------------------------

func rebuild_slab() -> void:
	if grid == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var depth_rows := float(grid.h - grid.ground_y)
	for y in range(grid.ground_y, grid.h):
		var depth := float(y - grid.ground_y) / maxf(depth_rows, 1.0)
		for x in grid.w:
			var top := cell_top(y)
			if grid.is_open(x, y):
				_cavity(st, x, y, top, depth)
			else:
				var m := grid.get_mat(x, y)
				var tile := Atlas.variant("strata_" + UcGrid.MAT_NAMES[m], x, y)
				var shade := lerpf(1.0, 0.72, depth)
				# Faint lip of shadow along cavity edges so openings read as holes.
				if y > grid.ground_y and grid.is_open(x, y - 1):
					shade *= 0.92
				_quad_front(st, Vector2(x, top), tile, Color(shade, shade, shade * 1.02))
	st.generate_normals()
	slab.mesh = st.commit()
	_update_mask()


func _quad_front(st: SurfaceTool, tl: Vector2, tile: String, col: Color) -> void:
	var r := Atlas.uv_rect(tile)
	var x0 := tl.x
	var x1 := tl.x + 1.0
	var y0 := tl.y
	var y1 := tl.y - 1.0
	_tri(st, [Vector3(x0, y0, FRONT_Z), Vector3(x1, y0, FRONT_Z), Vector3(x1, y1, FRONT_Z)],
		[r.position, Vector2(r.end.x, r.position.y), r.end], [col, col, col])
	_tri(st, [Vector3(x0, y0, FRONT_Z), Vector3(x1, y1, FRONT_Z), Vector3(x0, y1, FRONT_Z)],
		[r.position, r.end, Vector2(r.position.x, r.end.y)], [col, col, col])


## An open cell below ground: dark back wall with corner occlusion, plus the inner faces of
## any solid neighbours so the cavity has depth.
func _cavity(st: SurfaceTool, x: int, y: int, top: float, depth: float) -> void:
	var r := Atlas.uv_rect(Atlas.variant("strata_air_back", x, y))
	var base := lerpf(0.62, 0.4, depth)
	var c00 := _grey(base * _corner_ao(x, y))
	var c10 := _grey(base * _corner_ao(x + 1, y))
	var c01 := _grey(base * _corner_ao(x, y + 1))
	var c11 := _grey(base * _corner_ao(x + 1, y + 1))
	var p00 := Vector3(x, top, BACK_Z)
	var p10 := Vector3(x + 1, top, BACK_Z)
	var p01 := Vector3(x, top - 1.0, BACK_Z)
	var p11 := Vector3(x + 1, top - 1.0, BACK_Z)
	_tri(st, [p00, p10, p11], [r.position, Vector2(r.end.x, r.position.y), r.end], [c00, c10, c11])
	_tri(st, [p00, p11, p01], [r.position, r.end, Vector2(r.position.x, r.end.y)], [c00, c11, c01])
	# Inner faces: ceiling, floor, left and right walls (z from BACK_Z to FRONT_Z).
	var shade := lerpf(0.55, 0.38, depth)
	if not grid.is_open(x, y - 1) and y - 1 >= grid.ground_y:
		_inner(st, x, y - 1, Vector3(x, top, FRONT_Z), Vector3(x + 1, top, FRONT_Z),
			Vector3(x + 1, top, BACK_Z), Vector3(x, top, BACK_Z), shade * 0.8)
	if grid.in_bounds(x, y + 1) and not grid.is_open(x, y + 1):
		_inner(st, x, y + 1, Vector3(x, top - 1.0, BACK_Z), Vector3(x + 1, top - 1.0, BACK_Z),
			Vector3(x + 1, top - 1.0, FRONT_Z), Vector3(x, top - 1.0, FRONT_Z), shade * 1.25)
	if grid.in_bounds(x - 1, y) and not grid.is_open(x - 1, y):
		_inner(st, x - 1, y, Vector3(x, top, FRONT_Z), Vector3(x, top, BACK_Z),
			Vector3(x, top - 1.0, BACK_Z), Vector3(x, top - 1.0, FRONT_Z), shade)
	if grid.in_bounds(x + 1, y) and not grid.is_open(x + 1, y):
		_inner(st, x + 1, y, Vector3(x + 1, top, BACK_Z), Vector3(x + 1, top, FRONT_Z),
			Vector3(x + 1, top - 1.0, FRONT_Z), Vector3(x + 1, top - 1.0, BACK_Z), shade)


func _inner(st: SurfaceTool, mx: int, my: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, shade: float) -> void:
	var tile := Atlas.variant("strata_" + UcGrid.MAT_NAMES[grid.get_mat(mx, my)], mx, my)
	var r := Atlas.uv_rect(tile)
	var col := Color(shade, shade, shade)
	_tri(st, [a, b, c], [r.position, Vector2(r.end.x, r.position.y), r.end], [col, col, col])
	_tri(st, [a, c, d], [r.position, r.end, Vector2(r.position.x, r.end.y)], [col, col, col])


static func _grey(v: float) -> Color:
	return Color(v, v, v, 1.0)


func _corner_ao(cx: int, cy: int) -> float:
	var solid := 0
	for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var x: int = cx + d.x
		var y: int = cy + d.y
		if not grid.in_bounds(x, y) or not grid.is_open(x, y):
			solid += 1
	return 1.0 - 0.14 * float(solid)


func _tri(st: SurfaceTool, p: Array, uv: Array, col: Array) -> void:
	# Godot's front faces wind clockwise as seen from the viewer; callers author them so.
	for i in 3:
		st.set_color(col[i])
		st.set_uv(uv[i])
		st.add_vertex(p[i])


# --- Fields -----------------------------------------------------------------------------------

func _build_fields() -> void:
	for n in [water_plane, gas_plane, heat_plane]:
		if n:
			n.queue_free()
	_field_mats.clear()
	_water_img = Image.create(grid.w, grid.h, false, Image.FORMAT_RGBA8)
	_gas_img = Image.create(grid.w, grid.h, false, Image.FORMAT_RGBA8)
	_heat_img = Image.create(grid.w, grid.h, false, Image.FORMAT_RGBA8)
	_mask_img = Image.create(grid.w, grid.h, false, Image.FORMAT_RGBA8)
	_water_tex = ImageTexture.create_from_image(_water_img)
	_gas_tex = ImageTexture.create_from_image(_gas_img)
	_heat_tex = ImageTexture.create_from_image(_heat_img)
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	water_plane = _field_plane("Water", 0, _water_tex, WATER_Z)
	gas_plane = _field_plane("Gas", 1, _gas_tex, GAS_Z)
	heat_plane = _field_plane("Heat", 2, _heat_tex, HEAT_Z)
	heat_plane.visible = false
	_update_mask()
	update_fields()


func _field_plane(n: String, mode: int, tex: Texture2D, z: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(grid.w, grid.h)
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = q
	mi.position = Vector3(grid.w * 0.5, float(grid.ground_y) - grid.h * 0.5, z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/uc_fields.gdshader")
	m.set_shader_parameter("field_nearest", tex)
	m.set_shader_parameter("field_linear", tex)
	m.set_shader_parameter("mask", _mask_tex)
	m.set_shader_parameter("grid_size", Vector2(grid.w, grid.h))
	m.set_shader_parameter("mode", mode)
	mi.material_override = m
	_field_mats.append(m)
	add_child(mi)
	return mi


func _update_mask() -> void:
	if _mask_img == null:
		return
	var data := PackedByteArray()
	data.resize(grid.w * grid.h * 4)
	for y in grid.h:
		for x in grid.w:
			var i := (y * grid.w + x) * 4
			data[i + 3] = 255 if grid.is_open(x, y) else 0
	_mask_img.set_data(grid.w, grid.h, false, Image.FORMAT_RGBA8, data)
	_mask_tex.update(_mask_img)


func update_fields() -> void:
	if grid == null or _water_img == null:
		return
	_fields_dirty = false
	var n := grid.w * grid.h
	var wd := PackedByteArray()
	var gd := PackedByteArray()
	wd.resize(n * 4)
	gd.resize(n * 4)
	var sour := grid.gas[UcGrid.SOUR]
	var stale := grid.gas[UcGrid.STALE]
	var damp := grid.gas[UcGrid.DAMP]
	var fresh := grid.gas[UcGrid.FRESH]
	var show_fresh := overlay == "gas"
	for i in n:
		var o := i * 4
		wd[o] = int(clampf(grid.water[i], 0.0, 1.0) * 255.0)
		wd[o + 1] = int(clampf(grid.flow[i] * 4.0, 0.0, 1.0) * 255.0)
		wd[o + 3] = 255
		gd[o] = int(clampf(sour[i], 0.0, 1.0) * 255.0)
		gd[o + 1] = int(clampf(stale[i], 0.0, 1.0) * 255.0)
		gd[o + 2] = int(clampf(damp[i], 0.0, 1.0) * 255.0)
		gd[o + 3] = int(clampf(fresh[i], 0.0, 1.0) * 255.0) if show_fresh else 0
	_water_img.set_data(grid.w, grid.h, false, Image.FORMAT_RGBA8, wd)
	_gas_img.set_data(grid.w, grid.h, false, Image.FORMAT_RGBA8, gd)
	_water_tex.update(_water_img)
	_gas_tex.update(_gas_img)
	if heat_plane.visible:
		var hd := PackedByteArray()
		hd.resize(n * 4)
		for i in n:
			hd[i * 4] = int(clampf((grid.temp[i] + 20.0) / 140.0, 0.0, 1.0) * 255.0)
			hd[i * 4 + 3] = 255
		_heat_img.set_data(grid.w, grid.h, false, Image.FORMAT_RGBA8, hd)
		_heat_tex.update(_heat_img)


func set_overlay(o: String) -> void:
	overlay = o
	heat_plane.visible = o == "heat"
	gas_plane.material_override.set_shader_parameter("strength", 1.8 if o == "gas" else 1.0)
	gas_plane.material_override.set_shader_parameter("alpha_scale", 0.25 if o == "heat" or o == "power" else 1.0)
	water_plane.material_override.set_shader_parameter("alpha_scale", 1.0 if o != "power" else 0.5)
	_pipe_mat.set_shader_parameter("dim", 0.0 if o in ["none", "water"] else 0.65)
	_wire_mat.set_shader_parameter("dim", 0.0 if o in ["none", "power"] else 0.65)
	for e: Dictionary in _net_nodes:
		var hl := 1.0 if (e.layer == "pipe" and o == "water") or (e.layer == "wire" and o == "power") else 0.0
		(e.node as GeometryInstance3D).set_instance_shader_parameter("highlight", hl)
	_fields_dirty = true


# --- Conduits ---------------------------------------------------------------------------------

func _conduit_material(base: Color, flow: Color, wire: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/conduit.gdshader")
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("flow_color", flow)
	m.set_shader_parameter("is_wire", wire)
	return m


func _signature() -> String:
	var mw := Sim.machines
	var parts := PackedStringArray()
	for layer in [mw.pipes, mw.wires]:
		var keys: Array = layer.keys()
		keys.sort()
		for k: Vector2i in keys:
			parts.append("%d,%d,%.2f" % [k.x, k.y, float(layer[k])])
		parts.append("|")
	var ids: Array = mw.machines.keys()
	ids.sort()
	for id: int in ids:
		parts.append(str(id))
	return ",".join(parts)


func _on_ticked() -> void:
	if grid == null or not is_inside_tree():
		return
	var sig := _signature()
	if sig != _conduit_sig:
		_conduit_sig = sig
		Sim.machines.rebuild()
		_build_conduits()
		sync_machines()
	_update_flows()
	_update_machine_frames()


func _build_conduits() -> void:
	for c in conduit_root.get_children():
		c.queue_free()
	_net_nodes.clear()
	var mw := Sim.machines
	for net: Dictionary in mw.water_nets:
		_net_nodes.append(_net_mesh("pipe", net, mw.pipes))
	for net: Dictionary in mw.power_nets:
		_net_nodes.append(_net_mesh("wire", net, mw.wires))
	# Burnt wire segments are excluded from power nets; draw them on their own.
	var burnt: Array[Vector2i] = []
	for c: Vector2i in mw.wires:
		if float(mw.wires[c]) <= 0.0:
			burnt.append(c)
	if not burnt.is_empty():
		_net_nodes.append(_net_mesh("wire", {"cells": burnt, "machines": []}, mw.wires))
	set_overlay(overlay)


func _net_mesh(layer: String, net: Dictionary, cells_health: Dictionary) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := PIPE_Z if layer == "pipe" else WIRE_Z
	var thick := 0.26 if layer == "pipe" else 0.1
	var cells: Array = net.cells
	var set := {}
	for c: Vector2i in cells:
		set[c] = true
	for c: Vector2i in cells:
		var dmg := 1.0 - float(cells_health.get(c, 1.0))
		var ctr := cell_center(c, z)
		_box(st, ctr, Vector3(thick * 1.25, thick * 1.25, thick * 1.25), dmg, ctr.x + ctr.y)
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var nb := c + d
			if set.has(nb) or cells_health.has(nb):
				if not set.has(nb) and layer == "wire":
					continue
				var nd := maxf(dmg, 1.0 - float(cells_health.get(nb, 1.0)))
				var mid := (ctr + cell_center(nb, z)) * 0.5
				var size := Vector3(1.0, thick, thick) if d.x != 0 else Vector3(thick, 1.0, thick)
				_box(st, mid, size, nd, mid.x if d.x != 0 else -mid.y)
		# Stubs into machines this conduit feeds.
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var nb := c + d
			if Sim.machines.occupancy.has(nb) and not set.has(nb):
				var mid := ctr + Vector3(d.x, -d.y, 0) * 0.3
				var size := Vector3(0.6, thick, thick) if d.x != 0 else Vector3(thick, 0.6, thick)
				_box(st, mid, size, dmg, 0.0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _pipe_mat if layer == "pipe" else _wire_mat
	mi.layers = 1 | UC_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	conduit_root.add_child(mi)
	return {"node": mi, "layer": layer, "net": net}


func _box(st: SurfaceTool, c: Vector3, s: Vector3, dmg: float, along: float) -> void:
	var h := s * 0.5
	# Front, top, bottom, left, right faces (the back is never seen).
	var faces := [
		[Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z), 1.0],
		[Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), 0.85],
		[Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), 0.45],
		[Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), 0.6],
		[Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), 0.6],
	]
	for f: Array in faces:
		var col := Color(clampf(dmg, 0.0, 1.0), float(f[4]), 0.0)
		var pts: Array = [c + f[0], c + f[1], c + f[2], c + f[3]]
		var uvs: Array = []
		for p: Vector3 in pts:
			uvs.append(Vector2(along + (p.x - c.x) + (c.y - p.y), 0.0))
		_tri(st, [pts[0], pts[1], pts[2]], [uvs[0], uvs[1], uvs[2]], [col, col, col])
		_tri(st, [pts[0], pts[2], pts[3]], [uvs[0], uvs[2], uvs[3]], [col, col, col])


func _update_flows() -> void:
	for e: Dictionary in _net_nodes:
		var net: Dictionary = e.net
		var f := 0.0
		if e.layer == "pipe":
			f = clampf(float(net.get("flow", 0.0)) / 0.6, 0.0, 1.0)
		else:
			var supply := float(net.get("supply", 0.0))
			f = clampf(float(net.get("load", 0.0)) / maxf(supply, 1.0), 0.0, 1.0) if supply > 0.0 else 0.0
			if bool(net.get("overloaded", false)):
				f = 1.0
		(e.node as GeometryInstance3D).set_instance_shader_parameter("flow", f)


# --- Machines ---------------------------------------------------------------------------------

func _load_sprite_meta() -> Dictionary:
	var d: Variant = Content.read_json("res://assets/textures/machines/machines.json")
	return d if d is Dictionary else {}


static func make_machine_sprite(def_id: String, meta: Dictionary, billboard: bool) -> PixelSprite3D:
	var info: Dictionary = meta.get(def_id, {})
	var path := "res://assets/textures/machines/%s.png" % def_id
	if info.is_empty() or not ResourceLoader.exists(path):
		return null
	var t := PixelSprite3D.load_tex(path)
	var s := PixelSprite3D.new()
	var opts := {"rim_strength": 0.25 if billboard else 0.0, "billboard": billboard, "cuttable": billboard, "emit_strength": 2.2}
	s.setup(t[0], t[1] if bool(info.get("emit", false)) else null, Vector2i(int(info.w), int(info.h)),
		Vector2i(int(info.get("frames", 5)), 1), opts)
	return s


func sync_machines() -> void:
	if grid == null:
		return
	var mw := Sim.machines
	for id: int in _machine_nodes.keys():
		if not mw.machines.has(id):
			var e: Dictionary = _machine_nodes[id]
			(e.sprite as Node).queue_free()
			if e.light:
				(e.light as Node).queue_free()
			_machine_nodes.erase(id)
	for id: int in mw.machines:
		var m: MachineState = mw.machines[id]
		if m.cell.y + m.size.y - 1 < grid.ground_y - 1 or _machine_nodes.has(id):
			continue
		var s := make_machine_sprite(m.def_id, _sprite_meta, false)
		if s == null:
			continue
		s.layers = 1 | UC_LAYER
		var bottom := cell_top(m.cell.y + m.size.y - 1) - 1.0
		s.position = Vector3(m.cell.x + m.size.x * 0.5, bottom, MACHINE_Z)
		s.name = "M%d_%s" % [id, m.def_id]
		machine_root.add_child(s)
		var light: OmniLight3D = null
		var d: Dictionary = Content.machine(m.def_id)
		if d.has("light") or d.has("heat") or m.def_id == "burner":
			light = OmniLight3D.new()
			light.light_color = Color(1.0, 0.62, 0.3) if m.def_id == "burner" or d.has("heat") else Color(0.55, 0.95, 0.85)
			light.omni_range = 5.5
			light.omni_attenuation = 0.8
			light.light_energy = 0.0
			light.shadow_enabled = false
			light.position = Vector3(m.cell.x + m.size.x * 0.5, bottom + maxf(m.size.y * 0.8, 1.4), MACHINE_Z + 0.6)
			light_root.add_child(light)
		_machine_nodes[id] = {"sprite": s, "light": light, "def": m.def_id}
	_update_machine_frames()


func _update_machine_frames() -> void:
	var mw := Sim.machines
	for id: int in _machine_nodes:
		var m: MachineState = mw.machines.get(id)
		if m == null:
			continue
		var e: Dictionary = _machine_nodes[id]
		e["running"] = m.status == &"ok" or m.efficiency > 0.05
		e["broken"] = m.health <= 0.0 or m.status == &"broken" or m.status == &"incomplete"
		if e.light:
			var target := 0.0
			if e.running:
				target = 2.2 if m.def_id == "burner" else 2.6 * maxf(m.light, 0.5)
			(e.light as OmniLight3D).light_energy = target


func _process(delta: float) -> void:
	if not visible:
		return
	_anim_t += delta
	if _fields_dirty:
		update_fields()
	var frame_step := int(_anim_t * 7.0)
	for id: int in _machine_nodes:
		var e: Dictionary = _machine_nodes[id]
		var f := 0
		if e.get("broken", false):
			f = 4
		elif e.get("running", false):
			f = 1 + (frame_step + id) % 3
		(e.sprite as GeometryInstance3D).set_instance_shader_parameter("frame", float(f))


func machine_node(id: int) -> Node3D:
	var e: Dictionary = _machine_nodes.get(id, {})
	return e.get("sprite") as Node3D


# --- Relics -----------------------------------------------------------------------------------

func _build_relics() -> void:
	for c in relic_root.get_children():
		c.queue_free()
	for r: Dictionary in Content.undercroft.get("relics", []):
		var t := String(r.get("type", ""))
		var cell := Vector2i(int(r.x), int(r.y))
		var size := Vector2i(1, 1)
		if r.has("size"):
			size = Vector2i(int(r.size[0]), int(r.size[1]))
		var bottom := cell_top(cell.y + size.y - 1) - 1.0
		if t == "stencil":
			var l := Label3D.new()
			l.text = String(r.get("text", ""))
			l.font = UiTheme.font()
			l.font_size = 48
			l.pixel_size = 0.0075
			l.modulate = Color(0.85, 0.78, 0.6, 0.55)
			l.outline_size = 0
			l.shaded = true
			l.position = Vector3(cell.x + 0.1, cell_top(cell.y) - 0.5, BACK_Z + 0.02)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.layers = 1 | UC_LAYER
			relic_root.add_child(l)
		elif t == "old_pipes":
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in 2:
				var x := cell.x + 0.3 + i * 0.4
				_box(st, Vector3(x, bottom + size.y * 0.5, BACK_Z + 0.3), Vector3(0.22, float(size.y), 0.22), 0.0, 0.0)
			st.generate_normals()
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			var m := _conduit_material(Color(0.35, 0.3, 0.25), Color.BLACK, false)
			mi.material_override = m
			mi.layers = 1 | UC_LAYER
			relic_root.add_child(mi)
		else:
			var s := make_machine_sprite(t, _sprite_meta, false)
			if s == null:
				continue
			s.layers = 1 | UC_LAYER
			s.position = Vector3(cell.x + size.x * 0.5, bottom, MACHINE_Z - 0.2)
			s.name = "Relic_" + t
			relic_root.add_child(s)


func relic_at(c: Vector2i) -> Dictionary:
	for r: Dictionary in Content.undercroft.get("relics", []):
		var cell := Vector2i(int(r.x), int(r.y))
		var size := Vector2i(1, 1)
		if r.has("size"):
			size = Vector2i(int(r.size[0]), int(r.size[1]))
		if Rect2i(cell, size).has_point(c):
			return r
	return {}
