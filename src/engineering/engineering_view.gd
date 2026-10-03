class_name EngineeringView
extends Node
## The cut. The ground in front of the lane falls away, the camera swings down and settles
## face-on to the Undercroft cross-section. From here the player lays pipe and wire, places
## machines, mends, packs and inspects while the town carries on above. Leaving reverses it.

const SIDE_FOV := 34.0
const DIST_DEFAULT := 30.0
const DIST_MIN := 15.0
const DIST_MAX := 46.0
const ENTER_TIME := 1.75
const EXIT_TIME := 1.35
const PICK_Z := 20.6
const OVERLAYS := ["none", "gas", "water", "power", "heat"]
const SPEEDS := [1.0, 2.0, 4.0]
const RELIC_TEXT := {
	"crew_locker": "A crew locker, door rusted half open. A tin cup, a respirator strap gone stiff, and a brass tag on a nail.",
	"gauge": "A pressure gauge, glass starred, needle pinned past the red. The plate reads LOWER STATIONS. Something down there is still pushing.",
	"trunk_valve": "A wheel valve as wide as a cart wheel, rusted solid and wired shut. Stamped: TRUNK — LOWER STATIONS. Someone wrapped the wire very carefully.",
	"stencil": "Stencilled on the brick, nearly gone: STN-7 PRIMARY LIFT. There was a lift here, once. It went down.",
	"old_pipes": "Risers far older than the Wick mains. They go down further than the brickwork does.",
}

var game: Node3D
var view: UndercroftView
var ui: EngUi
var active := false
var busy := false
var tool := "inspect"
var build_def := ""
var overlay := "none"
var speed_i := 0
var cursor := Vector2i(24, 12)
var drag_from: Variant = null            ## Vector2i while dragging conduit
var selected := -1                       ## machine id shown in the panel
var selected_cell: Variant = null        ## Vector2i for conduit / cell / relic panels
var cam_target := Vector2(24.0, -4.5)
var cam_center := Vector2(24.0, -4.5)
var cam_dist := DIST_DEFAULT
var _dist_target := DIST_DEFAULT
var _cursor_node: MeshInstance3D
var _ghost_mesh: MeshInstance3D
var _ghost_sprite: PixelSprite3D
var _ghost_def := ""
var _pad_t := 0.0
var _pad_dir := Vector2i.ZERO
var _hover_key := ""
var _saved_fov := 30.0
var _wipe: ColorRect
var _paused_by_us := false


func _ready() -> void:
	game = get_parent() as Node3D
	view = UndercroftView.new()
	view.visible = false
	add_child(view)
	ui = EngUi.new()
	ui.visible = false
	add_child(ui)
	ui.tool_picked.connect(set_tool)
	ui.build_picked.connect(func(id: String) -> void:
		build_def = id
		set_tool("build")
		ui.close_panel())
	ui.action_picked.connect(_on_action)
	ui.panel_closed.connect(func() -> void:
		selected = -1
		selected_cell = null)
	_build_cursor()
	var wl := CanvasLayer.new()
	wl.layer = 9
	_wipe = ColorRect.new()
	_wipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wm := ShaderMaterial.new()
	wm.shader = preload("res://shaders/strata_wipe.gdshader")
	_wipe.material = wm
	_wipe.visible = false
	wl.add_child(_wipe)
	add_child(wl)
	Sim.ticked.connect(_refresh_panel)


func is_active() -> bool:
	return active


func toggle() -> void:
	if busy:
		return
	if active:
		exit()
	else:
		enter()


# --- Transition -------------------------------------------------------------------------------

func enter() -> void:
	busy = true
	active = true
	var rig: CameraRig = game.rig
	game.player.frozen = true
	GameState.view_mode = "cut"
	Events.view_mode_changed.emit(&"cut")
	Events.prompt_changed.emit("")
	RenderingServer.global_shader_parameter_set("cut_z", UndercroftView.FRONT_Z)
	view.rebuild()
	view.set_overlay(overlay)
	view.visible = true
	var px: float = game.player.global_position.x
	cam_dist = DIST_DEFAULT
	_dist_target = cam_dist
	cam_target = _clamp_center(Vector2(px, -4.5))
	cam_center = cam_target
	cursor = view.world_to_cell(Vector3(px, -3.5, PICK_Z))
	var from := rig.camera.global_transform
	var focus_from: Vector3 = game.player.global_position + Vector3(0, 0.9, 0)
	_saved_fov = rig.camera.fov
	rig.free_transform = from
	rig.mode = "free"
	rig.attrs.dof_blur_near_enabled = false
	Audio.play("cut_open", -3.0)
	Events.camera_impulse.emit(0.3)
	_dust_line()
	var hold := float(Dev.arg("cut_hold", "-1"))
	var t := 0.0
	while t < ENTER_TIME:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := clampf(t / ENTER_TIME, 0.0, 1.0)
		if hold >= 0.0 and k >= hold:
			k = hold
			t = hold * ENTER_TIME
		RenderingServer.global_shader_parameter_set("cut_amount", smoothstep(0.0, 0.5, k))
		var c := _ease(clampf((k - 0.16) / 0.84, 0.0, 1.0))
		var to := _side_transform()
		rig.free_transform = _swing(from, focus_from, to, Vector3(cam_center.x, cam_center.y, UndercroftView.FRONT_Z), c)
		rig.camera.fov = lerpf(_saved_fov, SIDE_FOV, c)
		_set_dof(lerpf(rig.distance, cam_dist, c))
		_wipe_at(c)
	RenderingServer.global_shader_parameter_set("cut_amount", 1.0)
	_wipe.visible = false
	set_tool(tool)
	set_overlay(overlay)
	ui.visible = true
	ui.refresh_keys()
	_update_title()
	game._update_music()
	GameState.discover("places", "undercroft")
	busy = false


func exit() -> void:
	busy = true
	ui.close_panel()
	ui.visible = false
	drag_from = null
	_cursor_node.visible = false
	_ghost_mesh.visible = false
	if _ghost_sprite:
		_ghost_sprite.visible = false
	if _paused_by_us:
		Clock.resume("cut_view")
		_paused_by_us = false
	Clock.set_speed(1.0)
	speed_i = 0
	var rig: CameraRig = game.rig
	var from := rig.camera.global_transform
	var focus_from := Vector3(cam_center.x, cam_center.y, UndercroftView.FRONT_Z)
	var to := rig.explore_transform()
	var focus_to: Vector3 = game.player.global_position + Vector3(0, 0.9, 0)
	Audio.play("cut_close", -4.0)
	var t := 0.0
	while t < EXIT_TIME:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := clampf(t / EXIT_TIME, 0.0, 1.0)
		var c := _ease(clampf(k / 0.85, 0.0, 1.0))
		rig.free_transform = _swing(from, focus_from, to, focus_to, c)
		rig.camera.fov = lerpf(SIDE_FOV, _saved_fov, c)
		_set_dof(lerpf(cam_dist, rig.distance, c))
		_wipe_at(1.0 - c)
		RenderingServer.global_shader_parameter_set("cut_amount", 1.0 - smoothstep(0.45, 1.0, k))
	RenderingServer.global_shader_parameter_set("cut_amount", 0.0)
	_wipe.visible = false
	view.visible = false
	rig.camera.fov = _saved_fov
	rig.mode = "explore"
	rig._apply_dof_settings()
	active = false
	GameState.view_mode = "explore"
	Events.view_mode_changed.emit(&"explore")
	game.player.frozen = false
	game._update_music()
	busy = false


static func _ease(x: float) -> float:
	return -(cos(PI * x) - 1.0) * 0.5


## Camera move between two framings: the position follows a curve that pulls back and
## drops in front of the slab, the view stays locked on a focus point gliding between both.
func _swing(a: Transform3D, fa: Vector3, b: Transform3D, fb: Vector3, c: float) -> Transform3D:
	var p0 := a.origin
	var p2 := b.origin
	var p1 := Vector3(lerpf(p0.x, p2.x, 0.5), maxf(p0.y, p2.y) * 0.55 + minf(p0.y, p2.y) * 0.45, maxf(p0.z, p2.z) + 5.0)
	var u := 1.0 - c
	var pos := p0 * u * u + p1 * 2.0 * u * c + p2 * c * c
	var focus := fa.lerp(fb, c)
	if pos.distance_to(focus) < 0.01:
		return b
	# Blend the look-at basis with the endpoints' exact bases so both ends match perfectly.
	var look := Basis.looking_at(focus - pos, Vector3.UP).get_rotation_quaternion()
	var qa := a.basis.get_rotation_quaternion()
	var qb := b.basis.get_rotation_quaternion()
	var edge := qa.slerp(qb, c)
	var w := sin(PI * c)
	return Transform3D(Basis(edge.slerp(look, w)), pos)


func _wipe_at(c: float) -> void:
	# A brief band of strata sweeps the lens as the camera passes ground level.
	var amt := pow(maxf(0.0, 1.0 - absf(c - 0.62) / 0.14), 2.0) * 0.55
	_wipe.visible = amt > 0.01 and bool(Settings.access.get("flash", 0.7) > 0.0)
	var m := _wipe.material as ShaderMaterial
	m.set_shader_parameter("amount", amt)
	m.set_shader_parameter("travel", c * 1.6)


func _dust_line() -> void:
	var parent := game.area_view as Node3D
	if parent == null:
		return
	for i in 12:
		var x := 2.0 + float(i) * 4.0 + randf_range(-1.0, 1.0)
		Fx.burst(parent, Vector3(x, 0.05, UndercroftView.FRONT_Z + 0.2), "dust")


func _side_transform() -> Transform3D:
	var tilt := cam_dist * 0.08
	var pos := Vector3(cam_center.x, cam_center.y + tilt, UndercroftView.FRONT_Z + cam_dist)
	var look := Vector3(cam_center.x, cam_center.y, UndercroftView.FRONT_Z)
	return Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)


func _set_dof(d: float) -> void:
	var rig: CameraRig = game.rig
	rig.attrs.dof_blur_far_distance = d + 2.5
	rig.attrs.dof_blur_far_transition = 10.0


func _half_extents(dist: float) -> Vector2:
	var hh := dist * tan(deg_to_rad(SIDE_FOV * 0.5))
	var vp := get_viewport().get_visible_rect().size
	return Vector2(hh * vp.x / maxf(vp.y, 1.0), hh)


func _clamp_center(c: Vector2) -> Vector2:
	var g := view.grid if view.grid else Sim.grid
	var he := _half_extents(cam_dist)
	var x0 := he.x - 1.5
	var x1 := float(g.w) - he.x + 1.5
	var bottom := float(g.ground_y - g.h)
	var y0 := bottom - 1.0 + he.y
	var y1 := 6.0 - he.y
	var out := c
	out.x = clampf(c.x, x0, x1) if x0 <= x1 else g.w * 0.5
	out.y = clampf(c.y, y0, y1) if y0 <= y1 else (y0 + y1) * 0.5
	return out


# --- Frame update -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active or busy:
		return
	var rig: CameraRig = game.rig
	var pad := Settings.last_device == "pad"
	var panel_focus := get_viewport().gui_get_focus_owner() != null
	var mv := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_down", "move_up"))
	if not pad:
		cam_target += mv * delta * cam_dist * 0.75
	elif not panel_focus and not Dialogue.active:
		_pad_cursor(mv, delta)
	var zoom := Input.get_axis("zoom_in", "zoom_out")
	if pad and absf(zoom) > 0.3:
		_dist_target = clampf(_dist_target + zoom * delta * 14.0, DIST_MIN, DIST_MAX)
	cam_dist = lerpf(cam_dist, _dist_target, clampf(delta * 8.0, 0.0, 1.0))
	cam_target = _clamp_center(cam_target)
	cam_center = cam_center.lerp(cam_target, clampf(delta * 9.0, 0.0, 1.0))
	rig.free_transform = _side_transform()
	_set_dof(cam_dist)
	if not pad:
		var hit: Variant = _mouse_point()
		if hit is Vector3:
			cursor = view.world_to_cell(hit)
	cursor = Vector2i(clampi(cursor.x, 0, view.grid.w - 1), clampi(cursor.y, 0, view.grid.h - 1))
	_update_cursor()
	_update_hover()


func _pad_cursor(mv: Vector2, delta: float) -> void:
	var dir := Vector2i.ZERO
	if mv.length() > 0.45:
		if absf(mv.x) > absf(mv.y):
			dir = Vector2i(signi(int(sign(mv.x))), 0)
		else:
			dir = Vector2i(0, -signi(int(sign(mv.y))))
	if dir == Vector2i.ZERO:
		_pad_dir = dir
		_pad_t = 0.0
		return
	_pad_t -= delta
	if dir != _pad_dir:
		_pad_dir = dir
		_pad_t = 0.28
		cursor += dir
	elif _pad_t <= 0.0:
		_pad_t = 0.085
		cursor += dir
	# Keep the cursor comfortably on screen.
	var he := _half_extents(cam_dist) * 0.72
	var wc := view.cell_center(cursor)
	if wc.x < cam_target.x - he.x:
		cam_target.x = wc.x + he.x
	elif wc.x > cam_target.x + he.x:
		cam_target.x = wc.x - he.x
	if wc.y < cam_target.y - he.y:
		cam_target.y = wc.y + he.y
	elif wc.y > cam_target.y + he.y:
		cam_target.y = wc.y - he.y


func _mouse_point() -> Variant:
	var cam: Camera3D = game.rig.camera
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.z) < 0.0001:
		return null
	var t := (PICK_Z - o.z) / d.z
	if t < 0.0:
		return null
	return o + d * t


# --- Cursor & ghosts --------------------------------------------------------------------------

func _build_cursor() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 2
	_cursor_node = MeshInstance3D.new()
	_cursor_node.material_override = m
	_cursor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor_node.visible = false
	add_child(_cursor_node)
	_ghost_mesh = MeshInstance3D.new()
	_ghost_mesh.material_override = m
	_ghost_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_mesh.visible = false
	add_child(_ghost_mesh)


## Pixel-style frame around a rectangle of cells (top-left cell, size in cells).
func _frame_mesh(tl: Vector2i, size: Vector2i, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := float(tl.x)
	var x1 := float(tl.x + size.x)
	var y0 := view.cell_top(tl.y)
	var y1 := y0 - size.y
	var t := 0.07
	var z := UndercroftView.FRONT_Z + 0.05
	_rect(st, Vector2(x0, y0), Vector2(x1, y0 - t), z, col)
	_rect(st, Vector2(x0, y1 + t), Vector2(x1, y1), z, col)
	_rect(st, Vector2(x0, y0), Vector2(x0 + t, y1), z, col)
	_rect(st, Vector2(x1 - t, y0), Vector2(x1, y1), z, col)
	var fill := Color(col, 0.12)
	_rect(st, Vector2(x0 + t, y0 - t), Vector2(x1 - t, y1 + t), z, fill)
	return st.commit()


static func _rect(st: SurfaceTool, a: Vector2, b: Vector2, z: float, col: Color) -> void:
	var p := [Vector3(a.x, a.y, z), Vector3(b.x, a.y, z), Vector3(b.x, b.y, z), Vector3(a.x, b.y, z)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.add_vertex(p[i])


func _update_cursor() -> void:
	var size := Vector2i.ONE
	var tl := cursor
	var col := Color(0.95, 0.85, 0.55, 0.95)
	_ghost_mesh.visible = false
	var want_ghost := ""
	match tool:
		"build":
			var d: Dictionary = Content.machine(build_def)
			var s: Array = d.get("size", [1, 1])
			size = Vector2i(int(s[0]), int(s[1]))
			tl = _build_origin()
			var err := _build_error()
			col = Color(0.45, 0.95, 0.6, 0.95) if err == "" else Color(0.95, 0.4, 0.3, 0.95)
			want_ghost = build_def
		"pipe", "wire":
			if drag_from is Vector2i:
				_ghost_mesh.mesh = _drag_mesh()
				_ghost_mesh.visible = true
		"remove":
			col = Color(0.95, 0.55, 0.35, 0.95)
	var m := Sim.machines.machine_at(cursor)
	if m and tool in ["inspect", "remove"]:
		tl = m.cell
		size = m.size
	var key := "%s|%s|%s" % [tl, size, col]
	if key != String(_cursor_node.get_meta("key", "")):
		_cursor_node.set_meta("key", key)
		_cursor_node.mesh = _frame_mesh(tl, size, col)
	_cursor_node.visible = true
	_update_ghost_sprite(want_ghost, tl, size, col)


func _update_ghost_sprite(def_id: String, tl: Vector2i, size: Vector2i, col: Color) -> void:
	if def_id != _ghost_def:
		if _ghost_sprite:
			_ghost_sprite.queue_free()
			_ghost_sprite = null
		_ghost_def = def_id
		if def_id != "":
			_ghost_sprite = UndercroftView.make_machine_sprite(def_id, view._sprite_meta, false)
			if _ghost_sprite:
				add_child(_ghost_sprite)
	if _ghost_sprite == null:
		return
	_ghost_sprite.visible = def_id != ""
	var bottom := view.cell_top(tl.y + size.y - 1) - 1.0
	_ghost_sprite.position = Vector3(tl.x + size.x * 0.5, bottom, UndercroftView.FRONT_Z + 0.08)
	_ghost_sprite.set_tint(Color(col.r * 1.1, col.g * 1.1, col.b * 1.1, 1.0))
	_ghost_sprite.set_fade(0.65)


func _drag_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not drag_from is Vector2i:
		return out
	var a: Vector2i = drag_from
	var b := cursor
	var corner := Vector2i(b.x, a.y) if absi(b.x - a.x) >= absi(b.y - a.y) else Vector2i(a.x, b.y)
	for seg: Array in [[a, corner], [corner, b]]:
		var p: Vector2i = seg[0]
		var q: Vector2i = seg[1]
		var step := Vector2i(signi(q.x - p.x), signi(q.y - p.y))
		var c := p
		while true:
			if out.is_empty() or out[out.size() - 1] != c:
				out.append(c)
			if c == q:
				break
			c += step
	return out


func _drag_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var layer := Sim.machines.pipes if tool == "pipe" else Sim.machines.wires
	var have := GameState.inventory.count(Sim.conduit_item(tool))
	var z := UndercroftView.FRONT_Z + 0.04
	for c in _drag_cells():
		var col := Color(0.45, 0.95, 0.6, 0.5)
		if layer.has(c):
			col = Color(0.8, 0.8, 0.8, 0.25)
		elif not Sim.machines.can_lay_conduit(c, view.grid):
			col = Color(0.95, 0.35, 0.3, 0.55)
		else:
			have -= 1
			if have < 0:
				col = Color(0.95, 0.6, 0.3, 0.45)
		var top := view.cell_top(c.y)
		_rect(st, Vector2(c.x + 0.2, top - 0.2), Vector2(c.x + 0.8, top - 0.8), z, col)
	return st.commit()


func _build_origin() -> Vector2i:
	var d: Dictionary = Content.machine(build_def)
	var s: Array = d.get("size", [1, 1])
	# The cursor marks the bottom-left cell: machines are placed by where they stand.
	return cursor - Vector2i(0, int(s[1]) - 1)


func _build_error() -> String:
	if build_def == "":
		return "unknown"
	var err := Sim.machines.placement_error(build_def, _build_origin(), view.grid)
	if err != "":
		return err
	if not GameState.inventory.has_all(Content.machine(build_def).get("cost", {})):
		return "no_materials"
	return ""


# --- Hover text -------------------------------------------------------------------------------

func _update_hover() -> void:
	var key := "%s|%s|%s|%s|%d" % [cursor, tool, build_def, drag_from, Sim.field_steps / 6]
	if key == _hover_key:
		return
	_hover_key = key
	var text := _describe(cursor)
	var hint := ""
	var p := Settings.binding_label("primary") if Settings.last_device == "kb" else Settings.binding_label("interact")
	var back := Settings.binding_label("secondary") if Settings.last_device == "kb" else Settings.binding_label("cancel")
	match tool:
		"inspect":
			hint = "[%s] look closer" % p
		"pipe", "wire":
			var item := Sim.conduit_item(tool)
			var have := GameState.inventory.count(item)
			if drag_from is Vector2i:
				var n := 0
				var layer := Sim.machines.pipes if tool == "pipe" else Sim.machines.wires
				for c in _drag_cells():
					if not layer.has(c) and Sim.machines.can_lay_conduit(c, view.grid):
						n += 1
				text = "%d %s — you have %d" % [n, Content.item_name(item).to_lower(), have]
				hint = "release to lay   [%s] stop" % back
			else:
				hint = "[%s] hold and drag to lay %s (%d in pack)   [%s] stop" % [p, tool, have, back]
		"build":
			var err := _build_error()
			var nm := String(Content.machine(build_def).get("name", build_def))
			text = nm + (" — fits here." if err == "" else " — " + Inspect.place_reason(err))
			hint = "[%s] place   [%s] build menu   [%s] stop" % [p, Settings.binding_label("build_menu"), back]
		"repair":
			hint = "[%s] mend   [%s] stop" % [p, back]
		"fill":
			hint = "[%s] pack with 2 blackstone (%d in pack)   [%s] stop" % [p, GameState.inventory.count("blackstone"), back]
		"remove":
			hint = "[%s] salvage   [%s] stop" % [p, back]
	ui.set_hover(text, hint)


func _describe(c: Vector2i) -> String:
	var g := view.grid
	var m := Sim.machines.machine_at(c)
	if m:
		var d: Dictionary = Content.machine(m.def_id)
		return "%s — %s" % [String(d.get("name", m.def_id)), Inspect.status(m.status)]
	var r := view.relic_at(c)
	if not r.is_empty():
		return _relic_name(String(r.type)) + " — something left behind."
	var parts := PackedStringArray()
	if Sim.machines.pipes.has(c):
		parts.append(_conduit_state("pipe", float(Sim.machines.pipes[c])))
	if Sim.machines.wires.has(c):
		parts.append(_conduit_state("wire", float(Sim.machines.wires[c])))
	var base := Inspect.cell_text(g, c)
	if parts.is_empty():
		return base
	return "%s · %s" % [" · ".join(parts), base]


static func _conduit_state(layer: String, hp: float) -> String:
	if layer == "pipe":
		return "Pipe" if hp >= 1.0 else ("Burst pipe, spilling" if hp <= 0.0 else "Cracked pipe, leaking")
	return "Wire" if hp >= 1.0 else ("Burnt-out wire" if hp <= 0.0 else "Scorched wire")


static func _relic_name(t: String) -> String:
	return {"crew_locker": "Crew locker", "gauge": "Old gauge", "trunk_valve": "Trunk valve",
		"stencil": "Stencil", "old_pipes": "Old risers"}.get(t, t.capitalize())


# --- Input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active or busy:
		return
	var vp := get_viewport()
	if Dialogue.active:
		if event.is_action_pressed("interact") or event.is_action_pressed("confirm") or (event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
			game.dialogue_box.advance()
			vp.set_input_as_handled()
		return
	if game.panels and game.panels.has_method("is_open") and game.panels.is_open():
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("secondary"):
		vp.set_input_as_handled()
		if vp.gui_get_focus_owner():
			vp.gui_get_focus_owner().release_focus()
			ui.close_panel()
		elif drag_from != null:
			drag_from = null
		elif tool != "inspect":
			set_tool("inspect")
		elif ui.is_panel_open():
			ui.close_panel()
		elif event.is_action_pressed("cancel"):
			exit()
		return
	if event.is_action_pressed("cut_view"):
		vp.set_input_as_handled()
		exit()
		return
	if event.is_action_pressed("overlay_next"):
		set_overlay(OVERLAYS[(OVERLAYS.find(overlay) + 1) % OVERLAYS.size()])
		Audio.ui("ui_tick", -8.0)
	elif event.is_action_pressed("build_menu"):
		if ui.mode == "build":
			ui.close_panel()
		else:
			ui.show_build_menu()
			if Settings.last_device == "pad":
				ui.focus_panel()
	elif event.is_action_pressed("tool_next") or event.is_action_pressed("tool_prev"):
		var ids: Array = EngUi.TOOLS.map(func(t: Array) -> String: return String(t[0]))
		var i := ids.find(tool) + (1 if event.is_action_pressed("tool_next") else -1)
		set_tool(String(ids[posmod(i, ids.size())]))
	elif event.is_action_pressed("time_pause"):
		if _paused_by_us:
			Clock.resume("cut_view")
		else:
			Clock.pause("cut_view")
		_paused_by_us = not _paused_by_us
		_update_title()
	elif event.is_action_pressed("time_speed"):
		speed_i = (speed_i + 1) % SPEEDS.size()
		Clock.set_speed(SPEEDS[speed_i])
		_update_title()
	elif event.is_action_pressed("zoom_in"):
		_dist_target = clampf(_dist_target - 2.0, DIST_MIN, DIST_MAX)
	elif event.is_action_pressed("zoom_out"):
		_dist_target = clampf(_dist_target + 2.0, DIST_MIN, DIST_MAX)
	elif event.is_action_pressed("primary") or event.is_action_pressed("interact"):
		_press()
	elif event.is_action_released("primary") or event.is_action_released("interact"):
		_release()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_7:
			set_tool(String(EngUi.TOOLS[k - KEY_1][0]))
		else:
			return
	else:
		return
	vp.set_input_as_handled()


func set_tool(id: String) -> void:
	if id == "build" and (build_def == "" or not GameState.can_build(build_def)):
		build_def = ""
		ui.show_build_menu()
		if Settings.last_device == "pad":
			ui.focus_panel()
		return
	tool = id
	drag_from = null
	ui.set_tool(id)
	if id != "inspect" and ui.mode == "inspect":
		ui.close_panel()
	_hover_key = ""


func set_overlay(o: String) -> void:
	overlay = o
	view.set_overlay(o)
	ui.set_overlay(o)
	_update_title()


func _update_title() -> void:
	var t := "THE UNDERCROFT"
	if overlay != "none":
		t += "  ·  %s" % overlay.capitalize()
	if _paused_by_us:
		t += "  ·  paused"
	elif speed_i > 0:
		t += "  ·  ×%d" % int(SPEEDS[speed_i])
	ui.set_title(t)


# --- Tool actions -----------------------------------------------------------------------------

func _press() -> void:
	match tool:
		"pipe", "wire":
			drag_from = cursor
		"inspect":
			_select_at(cursor)
		"build":
			_place()
		"repair":
			_repair_at(cursor)
		"fill":
			_fill_at(cursor)
		"remove":
			_remove_at(cursor)
	_hover_key = ""


func _release() -> void:
	if not drag_from is Vector2i or not tool in ["pipe", "wire"]:
		return
	var cells := _drag_cells()
	drag_from = null
	var item := Sim.conduit_item(tool)
	var before := GameState.inventory.count(item)
	var laid := Sim.lay_conduit(tool, cells)
	if laid > 0:
		Audio.play("pipe_lay" if tool == "pipe" else "wire_lay", -4.0)
		Events.toast.emit("Laid %d %s." % [laid, tool], &"info")
		GameState.add_deed("engineered", 0.2 * laid)
	elif before == 0:
		Events.toast.emit("No %s left in your pack." % Content.item_name(item).to_lower(), &"warn")
	else:
		Events.toast.emit("Nothing to lay there.", &"info")
	_hover_key = ""


func _place() -> void:
	var err := Sim.build(build_def, _build_origin())
	if err != "":
		Events.toast.emit(Inspect.place_reason(err), &"warn")
		Audio.ui("ui_error", -6.0)
		return
	Audio.play("build", -3.0)
	Events.camera_impulse.emit(0.06)
	var d: Dictionary = Content.machine(build_def)
	Events.toast.emit("%s built." % String(d.get("name", build_def)), &"good")
	if not GameState.inventory.has_all(d.get("cost", {})):
		set_tool("inspect")


func _repair_at(c: Vector2i) -> void:
	for layer in ["pipe", "wire"]:
		var l := Sim.machines.pipes if layer == "pipe" else Sim.machines.wires
		if l.has(c) and float(l[c]) < 1.0:
			var err := Sim.repair(layer, c)
			if err == "":
				Audio.play("repair", -4.0)
				Events.toast.emit("Mended the %s." % layer, &"good")
			else:
				Events.toast.emit("Need %s to mend that." % ("seal gum or a pipe section" if layer == "pipe" else "a wire coil"), &"warn")
			return
	Events.toast.emit(Inspect.place_reason("not_damaged"), &"info")


func _fill_at(c: Vector2i) -> void:
	if c.y < view.grid.ground_y:
		Events.toast.emit("That's the lane. People walk there.", &"info")
		return
	var err := Sim.fill_cell(c)
	if err == "":
		Audio.play("mine", -6.0)
		Events.toast.emit("Packed with blackstone.", &"info")
	elif err == "no_materials":
		Events.toast.emit("Packing a cell takes 2 blackstone.", &"warn")
	else:
		Events.toast.emit("Can't pack that.", &"info")


func _remove_at(c: Vector2i) -> void:
	var m := Sim.machines.machine_at(c)
	if m:
		if m.fixed:
			Events.toast.emit("That's part of the town. Leave it be.", &"info")
			return
		var nm := String(Content.machine(m.def_id).get("name", m.def_id))
		if Sim.deconstruct(c):
			Audio.play("salvage", -4.0)
			Events.toast.emit("Salvaged the %s." % nm.to_lower(), &"info")
			ui.close_panel()
		return
	if Sim.remove_conduit("pipe", c) or Sim.remove_conduit("wire", c):
		Audio.play("salvage", -8.0)
		return
	Events.toast.emit("Nothing to salvage there.", &"info")


func _select_at(c: Vector2i) -> void:
	var m := Sim.machines.machine_at(c)
	if m:
		selected = m.id
		selected_cell = null
		_show_machine(m)
	else:
		selected = -1
		selected_cell = c
		_show_cell(c)
	if Settings.last_device == "pad":
		ui.focus_panel()


func _refresh_panel() -> void:
	if not active or not ui.is_panel_open() or ui.mode != "inspect":
		return
	if get_viewport().gui_get_focus_owner():
		return   # don't rebuild buttons under a pad player's focus
	if selected >= 0:
		var m: MachineState = Sim.machines.machines.get(selected)
		if m:
			_show_machine(m)
		else:
			ui.close_panel()
	elif selected_cell is Vector2i:
		_show_cell(selected_cell)


func _show_machine(m: MachineState) -> void:
	var d: Dictionary = Content.machine(m.def_id)
	ui.show_machine(m, d, Inspect.machine_lines(m, d), _machine_actions(m, d))


func _machine_actions(m: MachineState, d: Dictionary) -> Array:
	var acts: Array = []
	if d.has("crank") or (d.has("pump") and bool(d.pump.get("manual", false))):
		acts.append(["crank", "", "Crank it (10 minutes)", true, "gear"])
	if d.has("fuel"):
		var any := false
		for item: String in d.fuel.get("items", {}):
			var n := GameState.inventory.count(item)
			if n > 0:
				any = true
				acts.append(["load", item, "Feed it %s (%d)" % [Content.item_name(item).to_lower(), n], true, item])
		if not any:
			acts.append(["", "", "Feed it: glowbeet or ember resin", false])
	if d.has("filter"):
		var item := String(d.filter.get("item", ""))
		var n := GameState.inventory.count(item)
		acts.append(["load", item, "Fit a %s (%d)" % [Content.item_name(item).to_lower(), n], n > 0, item])
	if d.has("compost"):
		var item := String(d.compost.get("input", ""))
		var n := GameState.inventory.count(item)
		acts.append(["load", item, "Add %s (%d)" % [Content.item_name(item).to_lower(), n], n > 0, item])
	if d.has("requires"):
		for item: String in d.requires:
			var need := int(d.requires[item]) - int(m.story.get(item, 0))
			if need > 0:
				var n := GameState.inventory.count(item)
				acts.append(["install", item, "Fit %s (%d of %d)" % [Content.item_name(item).to_lower(), n, need], n > 0, item])
	if m.waste >= 1.0:
		acts.append(["empty", "", "Empty it", true, String(d.get("waste", {}).get("item", d.get("compost", {}).get("output", "sludge")))])
	if not m.fixed:
		acts.append(["toggle", "", "Switch it off" if m.enabled else "Switch it on", true])
		acts.append(["remove", "", "Salvage it (half the parts back)", true, "tool_hammer"])
	return acts


func _show_cell(c: Vector2i) -> void:
	var r := view.relic_at(c)
	if not r.is_empty():
		var t := String(r.type)
		var acts: Array = []
		if t == "crew_locker" and not GameState.has_flag("took_crew_tag"):
			acts.append(["relic_take", t, "Take the brass tag", true, "crew_tag"])
		ui.show_info(_relic_name(t), String(RELIC_TEXT.get(t, "")), PackedStringArray(), acts)
		if not GameState.has_flag("seen_relic_" + t):
			GameState.set_flag("seen_relic_" + t)
			GameState.discover("lore", "relic_" + t)
		return
	var lines := PackedStringArray()
	var g := view.grid
	var acts: Array = []
	for layer in ["pipe", "wire"]:
		var l := Sim.machines.pipes if layer == "pipe" else Sim.machines.wires
		if l.has(c):
			var hp := float(l[c])
			lines.append(_conduit_state(layer, hp) + ".")
			var net := _net_at(layer, c)
			if layer == "pipe" and not net.is_empty():
				lines.append("Water through this line: %s." % Inspect._amount(float(net.get("flow", 0.0)), 1.0))
			elif layer == "wire" and not net.is_empty():
				var sup := float(net.get("supply", 0.0))
				lines.append("Power on this wire: %s." % ("none" if sup <= 0.0 else ("overloaded!" if bool(net.get("overloaded", false)) else "%s of what's asked" % ("all" if float(net.get("load", 0.0)) <= sup else "not all"))))
			if hp < 1.0:
				acts.append(["mend", layer, "Mend it", true, "tool_wrench"])
			acts.append(["pull", layer, "Pull up the %s" % layer, true, "tool_hammer"])
	if c.y >= g.ground_y and g.is_open(c.x, c.y):
		acts.append(["pack", "", "Pack with blackstone (2)", GameState.inventory.count("blackstone") >= 2, "blackstone"])
	ui.show_info("Here", Inspect.cell_text(g, c), lines, acts)


func _net_at(layer: String, c: Vector2i) -> Dictionary:
	var nets: Array = Sim.machines.water_nets if layer == "pipe" else Sim.machines.power_nets
	for n: Dictionary in nets:
		if (n.cells as Array).has(c):
			return n
	return {}


func _on_action(act: String, arg: String) -> void:
	var m: MachineState = Sim.machines.machines.get(selected) if selected >= 0 else null
	match act:
		"crank":
			if m and Sim.crank(m.id):
				Audio.play("well_crank", -4.0)
				Clock.advance(10.0)
				GameState.add_deed("cranked", 1.0)
				Events.toast.emit("You crank until your arms ache.", &"info")
		"load", "install":
			if m:
				var n := Sim.load_item(m.id, arg, 5 if act == "load" else 99)
				if n > 0:
					Audio.play("pickup", -6.0)
					Events.toast.emit(("Fitted %s." if act == "install" else "Added %d %s.") % ([Content.item_name(arg).to_lower()] if act == "install" else [n, Content.item_name(arg).to_lower()]), &"info")
					if act == "install":
						GameState.add_deed("restored", 1.0, {"machine": m.def_id})
				else:
					Events.toast.emit("It won't take any more.", &"info")
		"empty":
			if m:
				var got := Sim.collect_output(m.id)
				for item: String in got:
					Events.toast.emit("Collected %d %s." % [int(got[item]), Content.item_name(item).to_lower()], &"info")
		"toggle":
			if m:
				m.enabled = not m.enabled
				Sim.machines.mark_dirty()
				Events.machine_changed.emit(m.id)
				Audio.ui("ui_tick", -6.0)
		"remove":
			if m:
				_remove_at(m.cell)
				return
		"relic_take":
			GameState.set_flag("took_crew_tag")
			GameState.give("wren_token", 1)
			game.monologue("The tag reads W. ASKEW — TRUNK CREW. The brass is warm. Not warm like a pocket. Warm like the rock below it.")
		"mend":
			if selected_cell is Vector2i:
				_repair_at(selected_cell)
		"pull":
			if selected_cell is Vector2i and Sim.remove_conduit(arg, selected_cell):
				Audio.play("salvage", -8.0)
		"pack":
			if selected_cell is Vector2i:
				_fill_at(selected_cell)
	_refresh_after_action()


func _refresh_after_action() -> void:
	_hover_key = ""
	if get_viewport().gui_get_focus_owner():
		get_viewport().gui_get_focus_owner().release_focus()
	_refresh_panel()
	if Settings.last_device == "pad" and ui.is_panel_open():
		ui.focus_panel()
